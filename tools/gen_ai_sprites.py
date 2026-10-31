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
COLLAPSE_H = 34      # collapsing pose height
DEAD_W = 44          # lying-dead pose width

# pose sheet cell order (row-major), index -> pose key
POSE_KEYS = ["idle", "run_a", "run_b", "shoot", "melee", "hurt", "collapse", "dead", "crouch"]

# frame counts must match SpriteLibrary.CHAR_ANIMS
CHAR_ANIMS = {
    "idle": 4, "run": 6, "shoot": 3, "melee": 3, "hurt": 2,
    "die": 6, "crouch": 2, "slide": 2, "jump": 2,
}

SHEETS = {
    # char_id: source filename in tools/ai_src
    "assault": "A_3x3_sprite_sheet_grid__9_equ_2026-10-31T00-09-11.png",
    "heavy":   "A_3x3_sprite_sheet_grid__9_equ_2026-10-31T00-10-54.png",
    "medic":   "A_3x3_sprite_sheet_grid__9_equ_2026-10-31T00-11-04.png",
    "ninja":   "A_3x3_sprite_sheet_grid__9_equ_2026-10-31T00-11-17.png",
    "officer": "A_3x3_sprite_sheet_grid_with_E_2026-10-31T00-44-41.png",
    "scout":   "A_3x3_sprite_sheet_grid__9_equ_2026-10-31T00-11-38.png",
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


def extract_poses(sheet: Image.Image, expected: int = 9, grid: tuple[int, int] = (3, 3)) -> list[Image.Image]:
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
def assemble(poses: dict[str, Image.Image]) -> dict[str, Image.Image]:
    strips = {}
    idle, ra, rb = poses["idle"], poses["run_a"], poses["run_b"]
    shoot, melee = poses["shoot"], poses["melee"]
    hurt, collapse, dead, crouch = poses["hurt"], poses["collapse"], poses["dead"], poses["crouch"]

    def strip(frames):
        w = sum(f.width for f in frames)
        out = Image.new("RGBA", (w, FRAME), (0, 0, 0, 0))
        x = 0
        for f in frames:
            out.alpha_composite(f, (x, 0))
            x += f.width
        return out

    strips["idle"] = strip([idle, shift(idle, dy=-1), shift(idle, dy=-2), shift(idle, dy=-1)])
    strips["run"] = strip([ra, shift(ra, dy=-1), rb, shift(rb, dy=-1), shift(ra, dy=-2), shift(rb, dy=-2)])
    strips["shoot"] = strip([shoot, shift(shoot, dx=-1, dy=-1), shoot])
    strips["melee"] = strip([melee, shift(melee, dx=2), shift(melee, dx=1, dy=-1)])
    strips["hurt"] = strip([hurt, shift(hurt, dx=-1)])
    strips["die"] = strip([collapse, shift(collapse, dy=-2),
                           shift(dead, squash=0.85), dead, shift(dead, dy=-1), dead])
    strips["crouch"] = strip([crouch, shift(crouch, squash=0.94)])
    strips["slide"] = strip([rot_fit(crouch, -10), rot_fit(crouch, -16)])
    strips["jump"] = strip([shift(ra, dy=-2), shift(rb, dy=-2)])
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
    for key in ("idle", "run_a", "run_b", "shoot", "melee", "hurt", "crouch"):
        poses[key] = place(pixelize(poses_raw[key], FRAME, BODY_H))
    poses["collapse"] = place(pixelize(poses_raw["collapse"], FRAME, COLLAPSE_H))
    poses["dead"] = place(pixelize(poses_raw["dead"], DEAD_W, FRAME // 2))

    strips = assemble(poses)
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
