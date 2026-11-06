#!/usr/bin/env python3
"""wp10-dots-visibility: clean stray components out of character sprite strips.

判定逻辑复刻 tools/clean_weapon_sprites.py:35-68（8 连通域 alpha>40、保留最大域、
距主体 <=1px 且面积 >=8px 的域并入），但删除不是唯一手段——角色条带上有两类
"残余"其实是管线缺陷，直接删会毁图：

1. 1px 透明竖缝（tools/gen_ai_sprites.py erase_gridlines 把角色身体暗色列误判成
   网格线白化，洪泛后成缝）：把 heavy_hurt/heavy_jump/scout_portrait 的身体切成
   两半，左半身会被误判成 235-365px 的"残余"。处理 = 逐行缝合：对左右邻都不透
   明的透明像素，用左邻像素色回填（恢复被误删的身体列）。

2. 悬空影子条（medic/ninja/officer/scout/heavy 的 *_jump 影子与脚分离 3px，且精灵
   整体移动时影子跟着飞）：处理 = 整体上移贴脚（对齐 assault_jump 已有的连脚影子
   形态），不删除影子本身。

真正的孤立杂点（悬浮尘点等）仍按 clean_weapon_sprites 同款删除。

Usage:
    py -3.14 tools/clean_character_strays.py            # dry-run: 打印计划不写盘
    py -3.14 tools/clean_character_strays.py --apply    # 实际写盘
    py -3.14 tools/clean_character_strays.py --apply --only heavy_hurt.png ...
"""
from __future__ import annotations

import sys
from collections import deque
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
CHARACTERS = ROOT / "assets" / "sprites" / "characters"
ALPHA_MIN = 40
JOIN_DIST = 1       # px: 与 clean_weapon_sprites.py:31 一致
MIN_JOIN_AREA = 8   # px: 与 clean_weapon_sprites.py:32 一致
SEAM_MIN_RUN = 5    # 竖缝列至少这么多行"左右都不透明而中间透明"才认定是缝
SHADOW_LIFT_MAX = 6  # 影子上移贴脚的最大尝试距离(px)


def components(mask: np.ndarray) -> list[list[tuple[int, int]]]:
    """同 tools/clean_weapon_sprites.py:35-56 的 8 连通域标定。"""
    h, w = mask.shape
    seen = np.zeros_like(mask, dtype=bool)
    out: list[list[tuple[int, int]]] = []
    for y in range(h):
        for x in range(w):
            if not mask[y, x] or seen[y, x]:
                continue
            q = deque([(y, x)])
            seen[y, x] = True
            comp: list[tuple[int, int]] = []
            while q:
                cy, cx = q.popleft()
                comp.append((cy, cx))
                for dy in (-1, 0, 1):
                    for dx in (-1, 0, 1):
                        ny, nx = cy + dy, cx + dx
                        if 0 <= ny < h and 0 <= nx < w and mask[ny, nx] and not seen[ny, nx]:
                            seen[ny, nx] = True
                            q.append((ny, nx))
            out.append(comp)
    return out


def dilate(mask: np.ndarray, dist: int) -> np.ndarray:
    """同 tools/clean_weapon_sprites.py:59-68 的 4 向膨胀。"""
    out = mask.copy()
    for _ in range(dist):
        shifted = out.copy()
        shifted[1:, :] |= out[:-1, :]
        shifted[:-1, :] |= out[1:, :]
        shifted[:, 1:] |= out[:, :-1]
        shifted[:, :-1] |= out[:, 1:]
        out = shifted
    return out


def residual_mask(mask: np.ndarray) -> np.ndarray:
    """clean 同款判定：最大域 + 距主体 <=JOIN_DIST 且 >=MIN_JOIN_AREA 的域并入，
    返回"残余"像素掩模（会被判违例的部分）。"""
    comps = sorted(components(mask), key=len, reverse=True)
    if not comps:
        return np.zeros_like(mask, dtype=bool)
    keep = np.zeros_like(mask, dtype=bool)
    for y, x in comps[0]:
        keep[y, x] = True
    zone = dilate(keep, JOIN_DIST)
    changed = True
    while changed:
        changed = False
        for comp in comps[1:]:
            if len(comp) < MIN_JOIN_AREA:
                continue
            if any(zone[y, x] for y, x in comp):
                for y, x in comp:
                    if not keep[y, x]:
                        keep[y, x] = True
                        changed = True
                zone = dilate(keep, JOIN_DIST)
    return mask & ~keep


def frames_of(path: Path) -> list[tuple[int, Image.Image]]:
    im = Image.open(path).convert("RGBA")
    w, h = im.size
    if h == 48 and w % 48 == 0 and w > 48:
        return [(i, im.crop((i * 48, 0, (i + 1) * 48, 48))) for i in range(w // 48)]
    return [(0, im)]


def seam_columns(mask: np.ndarray) -> list[tuple[int, int]]:
    """竖缝列：该列上"左右同行都不透明而自己透明"的行数 >= SEAM_MIN_RUN。"""
    h, w = mask.shape
    out = []
    for x in range(1, w - 1):
        n = int(sum(1 for y in range(h) if mask[y, x - 1] and mask[y, x + 1] and not mask[y, x]))
        if n >= SEAM_MIN_RUN:
            out.append((x, n))
    return out


def stitch_seams(fr: Image.Image) -> tuple[Image.Image, int]:
    """回填 1px 缝：对 mask[y,x-1] 与 mask[y,x+1] 均不透明的透明像素，
    用左邻不透明像素色回填（左邻透明则用右邻）。返回 (新帧, 回填像素数)。"""
    a = np.asarray(fr).copy()
    mask = a[:, :, 3] > ALPHA_MIN
    h, w = mask.shape
    filled = 0
    for y in range(h):
        for x in range(1, w - 1):
            if mask[y, x]:
                continue
            if not (mask[y, x - 1] and mask[y, x + 1]):
                continue
            src = x - 1 if mask[y, x - 1] else x + 1
            a[y, x] = a[y, src]
            a[y, x, 3] = 255
            filled += 1
    return Image.fromarray(a, "RGBA"), filled


def lift_shadow_color(frame: Image.Image, comp: list[tuple[int, int]], body: np.ndarray) -> tuple[Image.Image, int] | None:
    """把影子域整体上移到与主体 8 连通（对齐 assault_jump 已有的连脚影子形态），
    保留影子像素原色。逐 px 试 dy=1..SHADOW_LIFT_MAX，成功即返回 (新帧, dy)。"""
    """同 lift_shadow，但保留影子像素原色。"""
    a = np.asarray(frame).copy()
    ys = [p[0] for p in comp]
    xs = [p[1] for p in comp]
    top = min(ys)
    colors = {p: tuple(int(v) for v in a[p[0], p[1]]) for p in comp}
    for dy in range(1, SHADOW_LIFT_MAX + 1):
        if top - dy < 0:
            break
        moved = np.zeros_like(body)
        for y, x in comp:
            moved[y - dy, x] = True
        if (moved & body).any():
            continue
        if len(components(body | moved)) == 1:
            for (y, x), rgba in colors.items():
                a[y, x] = (0, 0, 0, 0)
            for (y, x), rgba in colors.items():
                a[y - dy, x] = rgba
            return Image.fromarray(a, "RGBA"), dy
    return None


def is_shadow_band(comp: list[tuple[int, int]]) -> bool:
    ys = [p[0] for p in comp]
    xs = [p[1] for p in comp]
    h = max(ys) - min(ys) + 1
    w = max(xs) - min(xs) + 1
    return h <= 4 and w >= 8 and min(ys) >= 40


def process_file(path: Path, apply: bool) -> tuple[bool, list[str]]:
    """返回 (是否需要写盘, 日志行)。"""
    log: list[str] = []
    im = Image.open(path).convert("RGBA")
    changed = False
    out_frames: list[Image.Image] = []
    for fi, fr in frames_of(path):
        a = np.asarray(fr)
        mask = a[:, :, 3] > ALPHA_MIN
        seams = seam_columns(mask)
        if seams:
            fr, n = stitch_seams(fr)
            log.append(f"  f{fi}: stitched seam col(s) {[(x, c) for x, c in seams]} -> filled {n}px")
            changed = True
            a = np.asarray(fr)
            mask = a[:, :, 3] > ALPHA_MIN
        resid = residual_mask(mask)
        n_resid = int(resid.sum())
        if n_resid == 0:
            out_frames.append(fr)
            continue
        body = mask & ~resid
        comps_r = sorted(components(resid), key=len, reverse=True)
        for comp in comps_r:
            ys = [p[0] for p in comp]
            xs = [p[1] for p in comp]
            bbox = f"{len(comp)}px x[{min(xs)},{max(xs)}] y[{min(ys)},{max(ys)}]"
            if is_shadow_band(comp):
                res = lift_shadow_color(fr, comp, body)
                if res is None:
                    log.append(f"  f{fi}: SHADOW LIFT FAILED for {bbox} (kept as-is)")
                    continue
                fr, dy = res
                log.append(f"  f{fi}: lifted shadow {bbox} up {dy}px onto feet")
                changed = True
                body = np.asarray(fr)[:, :, 3] > ALPHA_MIN
            else:
                aa = np.asarray(fr).copy()
                for y, x in comp:
                    aa[y, x] = (0, 0, 0, 0)
                fr = Image.fromarray(aa, "RGBA")
                log.append(f"  f{fi}: deleted stray dot {bbox}")
                changed = True
        out_frames.append(fr)
    if changed and apply:
        sheet = Image.new("RGBA", im.size, (0, 0, 0, 0))
        if im.size[0] > 48 and im.size[1] == 48:
            for i, fr in enumerate(out_frames):
                sheet.paste(fr, (i * 48, 0))
        else:
            sheet = out_frames[0]
        sheet.save(path)
    return changed, log


def main() -> None:
    apply = "--apply" in sys.argv
    only = None
    if "--only" in sys.argv:
        only = set(sys.argv[sys.argv.index("--only") + 1:])
    total = 0
    for path in sorted(CHARACTERS.glob("*.png")):
        if only and path.name not in only:
            continue
        changed, log = process_file(path, apply)
        if log:
            print(f"[stray] {path.name}")
            for line in log:
                print(line)
            total += 1
    mode = "APPLIED" if apply else "DRY-RUN"
    print(f"[stray] {mode}: {total} file(s) touched")
    if apply and total:
        # 写盘后重读盘复验（每帧残余必须归零）
        still = []
        for path in sorted(CHARACTERS.glob("*.png")):
            if only and path.name not in only:
                continue
            for fi, fr in frames_of(path):
                mask = np.asarray(fr)[:, :, 3] > ALPHA_MIN
                if int(residual_mask(mask).sum()) != 0:
                    still.append(f"{path.name} f{fi}")
                    break
        if still:
            print(f"[stray] VERIFY FAIL: residual remains in {', '.join(still)}")
            sys.exit(1)
        print("[stray] VERIFY PASS: all frames residual 0")
    if not apply:
        print("[stray] (dry-run only, re-run with --apply to write)")


if __name__ == "__main__":
    main()
