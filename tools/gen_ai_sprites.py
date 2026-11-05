#!/usr/bin/env python3
"""AI sprite pipeline: slice pose sheets -> pixelize -> assemble animation strips.

Usage:
    python tools/gen_ai_sprites.py            # process all configured sheets
    python tools/gen_ai_sprites.py --preview  # also write a contact sheet to tools/_preview

Reads sources from tools/ai_src (AI-generated 3x3 pose sheets), writes final
strips directly into assets/sprites/characters/ using the exact filenames the
game expects (SpriteLibrary.CHAR_ANIMS).
"""
from __future__ import annotations

import sys
from collections import deque
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "tools" / "ai_src"
OUT = ROOT / "assets" / "sprites" / "characters"
PREVIEW = ROOT / "tools" / "_preview"

# --- target geometry --------------------------------------------------------
FRAME = 48           # character frame size (48x48)
BODY_H = 44          # standing pose content height inside the frame
CROUCH_H = 30        # wp3-crouch-size: crouching pose height (~68% of BODY_H,
                     # so crouch reads clearly shorter than standing)
COLLAPSE_H = 34      # collapsing pose height
DEAD_W = 44          # lying-dead pose width

# pose sheet cell order (row-major), index -> pose key
# 4x3 无枪姿势表（P0-1/P1-6）：12 格 = idle + 4 步态 + aim + melee + hurt + crouch + collapse + dead + jump
POSE_KEYS = ["idle", "run_a", "run_b", "run_c", "run_d", "aim",
             "melee", "hurt", "crouch", "collapse", "dead", "jump"]

# frame counts must match SpriteLibrary.CHAR_ANIMS
CHAR_ANIMS = {
    "idle": 4, "run": 8, "shoot": 3, "melee": 3, "hurt": 2,
    "die": 6, "crouch": 3, "slide": 2, "jump": 2,
}

SHEETS = {
    # char_id: 4x3 无枪姿势表（P0-1：身体帧不得包含任何枪械）
    "assault": "A_4x3_sprite_sheet_grid_with_E_2026-11-01T08-27-13.png",
    "heavy":   "A_4x3_sprite_sheet_grid_with_E_2026-11-01T08-27-41.png",
    "medic":   "A_4x3_sprite_sheet_grid_with_E_2026-11-01T08-28-05.png",
    "ninja":   "A_4x3_sprite_sheet_grid_with_E_2026-11-01T08-28-50.png",
    "officer": "A_4x3_sprite_sheet_grid_with_E_2026-11-01T08-29-17.png",
    "scout":   "A_4x3_sprite_sheet_grid_with_E_2026-11-01T08-29-43.png",
}


# ---------------------------------------------------------------------------
# background removal & extraction
# ---------------------------------------------------------------------------
def erase_gridlines(rgb: np.ndarray) -> np.ndarray:
    """Remove thin full-length dark gridlines (isolated runs of dark rows/cols <=6px)."""
    h, w, _ = rgb.shape
    bright = rgb.mean(axis=2)
    out = rgb.copy()
    dark = bright < 140

    def thin_runs(flags: np.ndarray, axis_len: int, span: int) -> np.ndarray:
        """Return boolean mask (True = thin isolated dark line) along one axis."""
        line = np.zeros(axis_len, dtype=bool)
        i = 0
        while i < axis_len:
            if flags[i]:
                j = i
                while j < axis_len and flags[j]:
                    j += 1
                run = j - i
                lo, hi = max(0, i - 4), min(axis_len, j + 4)
                neighbor = flags[max(0, i - 12):i].mean() if i > 0 else 0
                neighbor2 = flags[j:j + 12].mean() if j < axis_len else 0
                if run <= 6 and neighbor < 0.3 and neighbor2 < 0.3:
                    line[i:j] = True
                i = j
            else:
                i += 1
        return line

    drows = dark.mean(axis=1) > 0.55
    dcols = dark.mean(axis=0) > 0.55
    rows = np.where(thin_runs(drows, h, w))[0]
    cols = np.where(thin_runs(dcols, w, h))[0]
    mask = np.zeros((h, w), dtype=bool)
    for r in rows:
        mask[max(0, r-1):r+2, :] = True
    for c in cols:
        mask[:, max(0, c-1):c+2] = True
    out[mask] = 255
    return out


def remove_background(img: Image.Image) -> Image.Image:
    """Flood-fill removal of light background (white or checkerboard) from borders."""
    rgb = np.asarray(img.convert("RGB"), dtype=np.int16)
    rgb = erase_gridlines(rgb)
    h, w, _ = rgb.shape

    border = np.concatenate([rgb[0, :], rgb[-1, :], rgb[:, 0], rgb[:, -1]])
    bright = border[border.mean(axis=1) > 140]
    tones = np.unique(bright // 32, axis=0) if len(bright) else []

    def is_bg(px) -> bool:
        # matches one of the border background tones (within tolerance)...
        q = px // 32
        if any(np.array_equal(q, t) for t in tones):
            return True
        # ...or is clearly bright paper-white (checker highlights)
        m = px.mean()
        sat = int(px.max()) - int(px.min())
        return m > 210 and sat < 40

    mask = np.zeros((h, w), dtype=bool)  # True = background
    dq = deque()
    for x in range(w):
        for y in (0, h - 1):
            if is_bg(rgb[y, x]) and not mask[y, x]:
                mask[y, x] = True
                dq.append((y, x))
    for y in range(h):
        for x in (0, w - 1):
            if is_bg(rgb[y, x]) and not mask[y, x]:
                mask[y, x] = True
                dq.append((y, x))
    while dq:
        y, x = dq.popleft()
        for ny, nx in ((y-1, x), (y+1, x), (y, x-1), (y, x+1)):
            if 0 <= ny < h and 0 <= nx < w and not mask[ny, nx] and is_bg(rgb[ny, nx]):
                mask[ny, nx] = True
                dq.append((ny, nx))

    out = np.asarray(img.convert("RGBA")).copy()
    out[mask] = (0, 0, 0, 0)
    return Image.fromarray(out, "RGBA")


def fill_holes(img: Image.Image) -> Image.Image:
    """Fill enclosed transparent holes (e.g. white flash cores eaten by bg removal)."""
    a = np.asarray(img).copy()
    alpha = a[:, :, 3] > 40
    h, w = alpha.shape
    reachable = np.zeros((h, w), dtype=bool)
    dq = deque()
    for x in range(w):
        for y in (0, h - 1):
            if not alpha[y, x] and not reachable[y, x]:
                reachable[y, x] = True
                dq.append((y, x))
    for y in range(h):
        for x in (0, w - 1):
            if not alpha[y, x] and not reachable[y, x]:
                reachable[y, x] = True
                dq.append((y, x))
    while dq:
        y, x = dq.popleft()
        for ny, nx in ((y-1, x), (y+1, x), (y, x-1), (y, x+1)):
            if 0 <= ny < h and 0 <= nx < w and not alpha[ny, nx] and not reachable[ny, nx]:
                reachable[ny, nx] = True
                dq.append((ny, nx))
    holes = (~alpha) & (~reachable)
    if holes.any():
        # fill with nearest opaque color via simple dilation
        for _ in range(6):
            dil = alpha.copy()
            dil[1:, :] |= alpha[:-1, :]; dil[:-1, :] |= alpha[1:, :]
            dil[:, 1:] |= alpha[:, :-1]; dil[:, :-1] |= alpha[:, 1:]
            new_px = dil & ~alpha
            for y, x in zip(*np.where(new_px)):
                for ny, nx in ((y-1, x), (y+1, x), (y, x-1), (y, x+1)):
                    if 0 <= ny < h and 0 <= nx < w and alpha[ny, nx]:
                        a[y, x, :3] = a[ny, nx, :3]
                        break
            alpha = dil
        a[:, :, 3] = np.where(alpha, 255, 0)
    return Image.fromarray(a, "RGBA")


def _split_bands(flags: np.ndarray, min_gap: int = 10, min_len: int = 12) -> list[tuple[int, int]]:
    """Contiguous True runs in a 1-D boolean mask, merging small gaps."""
    idx = np.where(flags)[0]
    if len(idx) == 0:
        return []
    bands = []
    start = prev = idx[0]
    for i in idx[1:]:
        if i - prev > min_gap:
            if prev - start >= min_len:
                bands.append((int(start), int(prev) + 1))
            start = i
        prev = i
    if prev - start >= min_len:
        bands.append((int(start), int(prev) + 1))
    return bands


def _band_to_cells(bands: list[tuple[int, int]], span: int, count: int = 3) -> list[tuple[int, int]]:
    """Assign content bands to `count` equal cells (nearest center), merging overlaps."""
    cell_w = span / count
    slots: list[list[tuple[int, int]]] = [[] for _ in range(count)]
    for (a, b) in bands:
        c = (a + b) / 2
        k = min(count - 1, max(0, int(c / cell_w)))
        slots[k].append((a, b))
    out = []
    for k in range(count):
        if not slots[k]:
            out.append((round(k * cell_w), round((k + 1) * cell_w)))
        else:
            out.append((min(a for a, _ in slots[k]), max(b for _, b in slots[k])))
    return out


def extract_poses(sheet: Image.Image, expected: int = 12, grid: tuple[int, int] = (4, 3)) -> list[Image.Image]:
    """Whole-sheet extraction via projection-profile band splitting.

    Split rows by content bands, then columns within each row band — immune to
    grid offsets, split weapons and unconnected pose pieces. grid = (cols, rows).
    """
    cols_n, rows_n = grid
    cleaned = fill_holes(remove_background(sheet))
    a = np.asarray(cleaned)
    alpha = a[:, :, 3] > 40
    h, w = alpha.shape

    row_bands = _split_bands(alpha.any(axis=1))
    if len(row_bands) < rows_n:
        print(f"  [warn] row bands = {len(row_bands)}, fallback to grid")
        row_bands = [(round(r * h / rows_n), round((r + 1) * h / rows_n)) for r in range(rows_n)]
    else:
        row_bands = _band_to_cells(row_bands, h, count=rows_n)

    out = []
    for (y0, y1) in row_bands:
        col_bands = _split_bands(alpha[y0:y1].any(axis=0))
        if len(col_bands) < cols_n:
            print(f"  [warn] col bands = {len(col_bands)} in rows {y0}:{y1}, fallback to grid")
            cw = w / cols_n
            col_bands = [(round(c * cw), round((c + 1) * cw)) for c in range(cols_n)]
        else:
            col_bands = _band_to_cells(col_bands, w, count=cols_n)
        for (x0, x1) in col_bands:
            tile = a[y0:y1, x0:x1].copy()
            tile = _trim_glow(tile)
            ys, xs = np.where(tile[:, :, 3] > 40)
            if len(ys) == 0:
                out.append(Image.new("RGBA", (8, 8), (0, 0, 0, 0)))
            else:
                out.append(Image.fromarray(tile[ys.min():ys.max()+1, xs.min():xs.max()+1], "RGBA"))
    if len(out) != expected:
        print(f"  [warn] expected {expected} poses, got {len(out)}")
    return out


def _trim_glow(canvas: np.ndarray) -> np.ndarray:
    """Erase white ground-glow wedges the model sometimes paints under feet."""
    tile = canvas.copy()
    ys, xs = np.where(tile[:, :, 3] > 40)
    if len(ys) == 0:
        return tile
    y_bottom = ys.max()
    zone = tile[int(y_bottom * 0.80):, :, :]
    rgbz = zone[:, :, :3].astype(np.int16)
    lum = rgbz.mean(axis=2)
    sat = rgbz.max(axis=2) - rgbz.min(axis=2)
    glow = (lum > 195) & (sat < 50) & (zone[:, :, 3] > 40)
    zone[glow] = (0, 0, 0, 0)
    return tile


def crop_content(img: Image.Image) -> Image.Image:
    a = np.asarray(img)
    ys, xs = np.where(a[:, :, 3] > 40)
    if len(ys) == 0:
        return img
    return img.crop((xs.min(), ys.min(), xs.max()+1, ys.max()+1))


# ---------------------------------------------------------------------------
# pixelization
# ---------------------------------------------------------------------------
def pixelize(img: Image.Image, box_w: int, box_h: int, colors: int = 26) -> Image.Image:
    """Downscale to the target box + quantize -> crisp chunky pixel art."""
    src = img.convert("RGBA")
    scale = min(box_w / src.width, box_h / src.height)
    nw, nh = max(1, round(src.width * scale)), max(1, round(src.height * scale))
    # two-step: area-average to ~2x target for smooth color stats, then nearest
    step = src.resize((max(nw, 2), max(nh, 2)), Image.LANCZOS) if src.width > nw * 2 else src
    small = step.resize((nw, nh), Image.BOX)
    # quantize RGB with alpha-aware palette
    opaque = np.asarray(small.getchannel("A")) > 90
    rgb = small.convert("RGB")
    q = rgb.quantize(colors=colors, method=Image.MEDIANCUT, dither=Image.Dither.NONE)
    qrgb = q.convert("RGB")
    out = np.asarray(qrgb).copy()
    alpha = np.where(opaque, 255, 0).astype(np.uint8)
    rgba = np.dstack([out, alpha])
    return Image.fromarray(rgba, "RGBA")


def place(img: Image.Image, anchor_bottom: bool = True, dy: int = 0, dx: int = 0) -> Image.Image:
    """Place a pixelized sprite into a FRAME-sized canvas."""
    canvas = Image.new("RGBA", (FRAME, FRAME), (0, 0, 0, 0))
    x = (FRAME - img.width) // 2 + dx
    y = (FRAME - img.height) if anchor_bottom else (FRAME - img.height) // 2
    y += dy
    canvas.alpha_composite(img, (x, y))
    return canvas


def shift(img: Image.Image, dy: int = 0, dx: int = 0, squash: float = 1.0) -> Image.Image:
    """Vertical bob / squash variants of a placed frame."""
    if squash != 1.0:
        nw, nh = img.width, max(1, round(img.height * squash))
        img = img.resize((nw, nh), Image.NEAREST)
    out = Image.new("RGBA", img.size, (0, 0, 0, 0))
    out.alpha_composite(img, (dx, dy))
    return out


def squash_bottom(img: Image.Image, squash: float) -> Image.Image:
    """wp3-crouch-size: crop content, squash its height, re-place bottom-anchored.

    shift(squash=...) shrinks the whole 48px frame and strip() composites frames
    top-aligned, which lifts the feet 1-2px off the ground line (frame bottom
    row 47). Squashing the cropped content and re-placing bottom-anchored keeps
    every frame's feet planted while the head dips.
    """
    content = crop_content(img)
    nh = max(1, round(content.height * squash))
    return place(content.resize((content.width, nh), Image.NEAREST))


# --- wp2-run-anim-rework：程序化跑步腿部循环 --------------------------------
# 美术审计实测：mirror_legs 绕腿带质心水平镜像会产生膝反关节 + 髋线错位
# （f5 质心差达 5-6px）+ 相邻帧腿带 XOR 高达 258-321px 的跳变。本节改为：
# run_a 上半身（0..27 行）做 2px 起伏 bob，源骨盆块（28..31 行）原位保留，
# 双腿按 4 脉冲足环逐帧程序化重绘——每帧仅一条腿的足端动 1-2px，
# 左右腿严格交替发力，相邻帧腿带 XOR 稳定落在 8-20px 且 wrap 连续。
def _shade(c: tuple[int, int, int], f: float) -> tuple[int, int, int, int]:
    return (max(0, min(255, round(c[0] * f))),
            max(0, min(255, round(c[1] * f))),
            max(0, min(255, round(c[2] * f))), 255)


# 每角色腿/靴/鞋底配色（取自各角色源表腿区实测 census）与腿宽 (大腿, 小腿, 靴)
RUN_PALETTES = {
    "assault": dict(near=(33, 38, 34), far=(20, 23, 19), boot=(22, 43, 41), boot_far=(14, 29, 27),
                    sole=(10, 14, 13), wn=(5, 4, 5), wf=(4, 3, 5)),
    "heavy":   dict(near=(36, 70, 80), far=(20, 37, 43), boot=(25, 49, 57), boot_far=(16, 32, 37),
                    sole=(7, 11, 12), wn=(6, 5, 6), wf=(5, 4, 5)),
    "medic":   dict(near=(64, 55, 29), far=(40, 35, 18), boot=(29, 49, 63), boot_far=(19, 33, 43),
                    sole=(20, 22, 18), wn=(5, 4, 5), wf=(4, 3, 5)),
    "ninja":   dict(near=(26, 47, 55), far=(15, 27, 32), boot=(35, 68, 77), boot_far=(22, 43, 49),
                    sole=(5, 9, 9), wn=(4, 3, 5), wf=(4, 3, 5)),
    "officer": dict(near=(34, 38, 31), far=(21, 24, 20), boot=(35, 58, 61), boot_far=(22, 38, 40),
                    sole=(12, 22, 17), wn=(5, 4, 5), wf=(4, 3, 5)),
    "scout":   dict(near=(78, 67, 36), far=(48, 42, 23), boot=(36, 52, 69), boot_far=(24, 34, 46),
                    sole=(23, 23, 20), wn=(5, 4, 5), wf=(4, 3, 5)),
}

# 足端环（dx 相对锚点, dy 提升量）：站地 → 前迈 → 抬起 → 后收 → 落回
RUN_LOOP = [(0, 0), (1, 0), (1, -2), (0, -2)]
RUN_NEAR_T = [0, 1, 1, 2, 2, 3, 3, 0]   # 近腿在偶→奇帧间脉冲
RUN_FAR_T = [2, 2, 3, 3, 0, 0, 1, 1]    # 远腿在奇→偶帧间脉冲（与近腿严格交错）
RUN_DY = [0, 0, -1, -2, 0, 0, -1, -2]   # 触地帧躯干最低、腾空帧最高（2px 起伏）


def _thick_line(cv: np.ndarray, x0: float, y0: float, x1: float, y1: float,
                w: int, col: tuple[int, int, int, int]) -> None:
    n = int(max(abs(x1 - x0), abs(y1 - y0))) * 2 + 2
    r = w // 2
    for t in np.linspace(0.0, 1.0, n):
        x = int(round(x0 + (x1 - x0) * t))
        y = int(round(y0 + (y1 - y0) * t))
        cv[max(0, y - r):y + r + 1, max(0, x - r):x + r + 1] = col


def _draw_leg(cv: np.ndarray, hx: int, hy: int, fx: int, fy: int,
              wv: tuple[int, int, int], col: tuple[int, int, int, int],
              boot_col: tuple[int, int, int, int],
              sole_col: tuple[int, int, int, int]) -> None:
    """大腿(髋→膝)+小腿(膝→踝)+靴子(2 行)+鞋底(1 行)，膝弯随腿压缩量。"""
    from math import hypot
    d = hypot(fx - hx, fy - hy)
    bend = max(0, min(3, int(round(3.0 - 0.16 * d))))
    kx = hx + (fx - hx) * 0.30 - bend
    ky = hy + (fy - hy) * 0.5
    wt, ws, bw = wv
    _thick_line(cv, hx, hy, kx, ky, wt, col)
    _thick_line(cv, kx, ky, fx, fy - 3, ws, col)  # 止于踝上 2px，避免盖章盖掉靴子位移
    bw2 = bw // 2
    cv[fy - 2:fy, max(0, fx - bw2):fx + bw2 + 1] = boot_col
    cv[fy:fy + 1, max(0, fx - bw2 + 1):fx + bw2] = sole_col


def build_run_strip(ra: Image.Image, char_id: str) -> Image.Image:
    """8 帧跑步条带：run_a 上半身 + 骨盆原位 + 程序化交替腿循环。"""
    pal = RUN_PALETTES.get(char_id, RUN_PALETTES["assault"])
    src = np.asarray(ra).copy()
    up = src.copy()
    up[28:, :, :] = 0
    hem = up[27:28, :, :].copy()  # 下摆底行，躯干上移时向下拉伸补缝
    band = src[28:32, :, 3] > 40
    xs = np.nonzero(band)[1]
    hx = int(round(float(xs.mean()))) if len(xs) else FRAME // 2
    near_c = pal["near"] + (255,)
    far_c = pal["far"] + (255,)
    boot_c = pal["boot"] + (255,)
    bootf_c = pal["boot_far"] + (255,)
    sole_c = pal["sole"] + (255,)
    frames = []
    for i in range(8):
        cv = np.zeros((FRAME, FRAME, 4), np.uint8)
        dy = RUN_DY[i]
        ex, el = RUN_LOOP[RUN_FAR_T[i]]
        _draw_leg(cv, hx - 5, 29, hx - 6 + ex, 47 + el, pal["wf"], far_c, bootf_c, _shade(pal["sole"], 0.8))
        ex, el = RUN_LOOP[RUN_NEAR_T[i]]
        _draw_leg(cv, hx + 3, 29, hx + 4 + ex, 47 + el, pal["wn"], near_c, boot_c, sole_c)
        # 躯干 0..27 行整体上移 |dy|，底部用下摆行拉伸补缝（不触碰 28+ 腿带）
        if dy < 0:
            cv[0:28 + dy, :, :] = up[-dy:28, :, :]
            cv[28 + dy:28, :, :] = hem
        else:
            cv[dy:28, :, :] = up[0:28 - dy, :, :]
        cv[28:32, :, :] = src[28:32, :, :]  # 源骨盆块原位保留，衔接裤色
        frames.append(Image.fromarray(cv, "RGBA"))
    strip = Image.new("RGBA", (FRAME * 8, FRAME), (0, 0, 0, 0))
    for i, f in enumerate(frames):
        strip.alpha_composite(f, (i * FRAME, 0))
    return strip


def rot(img: Image.Image, deg: float) -> Image.Image:
    return img.rotate(deg, resample=Image.NEAREST, expand=True)


def rot_fit(img: Image.Image, deg: float) -> Image.Image:
    """Rotate and re-fit into a FRAME-sized canvas (bottom anchored)."""
    r = rot(img, deg)
    if r.width > FRAME or r.height > FRAME:
        s = min(FRAME / r.width, FRAME / r.height)
        r = r.resize((max(1, round(r.width * s)), max(1, round(r.height * s))), Image.NEAREST)
    canvas = Image.new("RGBA", (FRAME, FRAME), (0, 0, 0, 0))
    canvas.alpha_composite(r, ((FRAME - r.width) // 2, FRAME - r.height))
    return canvas


# ---------------------------------------------------------------------------
# strip assembly
# ---------------------------------------------------------------------------
def assemble(poses: dict[str, Image.Image], char_id: str = "assault") -> dict[str, Image.Image]:
    strips = {}
    idle = poses["idle"]
    ra, rb, rc, rd = poses["run_a"], poses["run_b"], poses["run_c"], poses["run_d"]
    shoot, melee = poses["shoot"], poses["melee"]
    hurt, collapse, dead, crouch = poses["hurt"], poses["collapse"], poses["dead"], poses["crouch"]
    jump = poses["jump"]

    def strip(frames):
        w = sum(f.width for f in frames)
        out = Image.new("RGBA", (w, FRAME), (0, 0, 0, 0))
        x = 0
        for f in frames:
            out.alpha_composite(f, (x, 0))
            x += f.width
        return out

    # P1-6：idle 4 帧呼吸（胸腔/头部微动）
    strips["idle"] = strip([idle, shift(idle, dy=-1), idle, shift(idle, dy=-1)])
    # wp2-run-anim-rework：8 帧跑步循环改为「run_a 上半身 bob + 程序化交替腿」，
    # 消除 mirror_legs 的膝反关节/髋线错位/相邻帧跳变；AI 真 8 姿势源图放入
    # tools/ai_src/ 登记 POSE_KEYS 后仍可无损替换（build_run_strip 只依赖 run_a）。
    strips["run"] = build_run_strip(ra, char_id)
    strips["shoot"] = strip([shoot, shift(shoot, dx=-1, dy=-1), shoot])
    strips["melee"] = strip([melee, shift(melee, dx=2), shift(melee, dx=1, dy=-1)])
    strips["hurt"] = strip([hurt, shift(hurt, dx=-1)])
    strips["die"] = strip([collapse, shift(collapse, dy=-2),
                           shift(dead, squash=0.85), dead, shift(dead, dy=-1), dead])
    # wp3-crouch-size：蹲姿呼吸帧改为「裁内容→压高→底对齐重放」，三帧脚底都钉在
    # frame 底行（旧 shift(squash=0.96)/shift(dy=-1) 会把脚底抬离地面线 1-2px）。
    strips["crouch"] = strip([crouch, squash_bottom(crouch, 0.96), squash_bottom(crouch, 0.92)])
    strips["slide"] = strip([rot_fit(crouch, -10), rot_fit(crouch, -16)])
    strips["jump"] = strip([shift(jump, dy=-2), shift(jump, dy=1)])
    return strips


def make_portrait(pose_src: Image.Image) -> Image.Image:
    """Bust portrait: square anchored at the head (topmost content), high-res source."""
    img = crop_content(pose_src)
    a = np.asarray(img)
    h, w = a.shape[:2]
    side = max(24, round(h * 0.42))
    # find x-centroid of the topmost 10% band (the head)
    band = a[: max(2, int(h * 0.10)), :, 3] > 40
    xs = np.where(band.any(axis=0))[0]
    head_x = int(xs.mean()) if len(xs) else w // 2
    x0 = min(max(0, head_x - side // 2), max(0, w - side))
    head = img.crop((x0, 0, min(w, x0 + side), min(h, side)))
    sq = Image.new("RGBA", (side, side), (0, 0, 0, 0))
    sq.alpha_composite(head, (0, 0))
    return pixelize(sq, FRAME, FRAME, colors=32)


# ---------------------------------------------------------------------------
def process_character(char_id: str, filename: str) -> None:
    src = SRC / filename
    if not src.exists():
        print(f"[skip] {char_id}: missing {src}")
        return
    sheet = Image.open(src)
    tiles = extract_poses(sheet, expected=len(POSE_KEYS))
    poses_raw = {}
    for i, key in enumerate(POSE_KEYS):
        poses_raw[key] = tiles[i] if i < len(tiles) else Image.new("RGBA", (8, 8), (0, 0, 0, 0))

    # pixelize with per-pose target geometry
    poses = {}
    for key in ("idle", "run_a", "run_b", "run_c", "run_d", "aim", "melee", "hurt", "jump"):
        poses[key] = place(pixelize(poses_raw[key], FRAME, BODY_H))
    # wp3-crouch-size：蹲姿用独立 CROUCH_H 目标高度（同 COLLAPSE_H 机制）——
    # 源表蹲姿格与站姿格内容高度相同（AI 没画矮），若继续走 BODY_H 归一化，
    # 蹲姿成品与站姿同为 44px 高、只向两侧变宽（实测宽 1.4-1.8 倍），即
    # 「蹲下明显更大」的根因；压到 CROUCH_H=30（≈站姿 68%）后蹲姿明确变矮。
    poses["crouch"] = place(pixelize(poses_raw["crouch"], FRAME, CROUCH_H))
    poses["collapse"] = place(pixelize(poses_raw["collapse"], FRAME, COLLAPSE_H))
    poses["dead"] = place(pixelize(poses_raw["dead"], DEAD_W, FRAME // 2))
    poses["shoot"] = poses["aim"]  # 瞄准姿势即射击姿势（武器由 WeaponSprite 叠加）

    strips = assemble(poses, char_id)
    OUT.mkdir(parents=True, exist_ok=True)
    for anim, strip_img in strips.items():
        strip_img.save(OUT / f"{char_id}_{anim}.png")
    make_portrait(poses_raw["idle"]).save(OUT / f"{char_id}_portrait.png")

    if "--preview" in sys.argv:
        PREVIEW.mkdir(parents=True, exist_ok=True)
        row = Image.new("RGBA", (sum(s.width for s in strips.values()) + 40, FRAME * 2 + 10), (45, 45, 55, 255))
        x = 0
        for anim in CHAR_ANIMS:
            row.alpha_composite(strips[anim], (x, 0)); x += strips[anim].width + 4
        row.alpha_composite(make_portrait(poses_raw["idle"]), (0, FRAME + 5))
        row.alpha_composite(place(pixelize(poses_raw["idle"], FRAME, BODY_H)), (60, FRAME + 5))
        row.alpha_composite(place(pixelize(poses_raw["run_a"], FRAME, BODY_H)), (120, FRAME + 5))
        row.alpha_composite(place(pixelize(poses_raw["dead"], DEAD_W, FRAME // 2)), (180, FRAME + 5))
        row.save(PREVIEW / f"{char_id}.png")
    print(f"[ok] {char_id}: wrote {len(strips)} strips + portrait")


if __name__ == "__main__":
    for cid, fname in SHEETS.items():
        process_character(cid, fname)
    print("done ->", OUT)
