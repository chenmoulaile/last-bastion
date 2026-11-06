#!/usr/bin/env python3
"""wp10-dots-visibility: assert NO stray-dot components in any sprite strip.

范围：assets/sprites/characters/*.png（*_die/*_run/*_idle/*_jump/*_hurt/*_crouch/
*_melee/*_shoot/*_slide/*_portrait 等全部条带）+ assets/sprites/weapons/*.png
（bile/pills 等全部单图）。其他目录（zombies/fx/environment…）不在本断言范围。

判定：与 tools/clean_weapon_sprites.py:35-68 完全同款——8 连通域（alpha>40）、
保留最大域、与主体膨胀 1px（JOIN_DIST=1）接触且面积 >=8px（MIN_JOIN_AREA=8）
的域并入，其余像素计为残余（stray）。判定原语（components/dilate/三个常量）
直接 import 自 clean_weapon_sprites，避免两份实现漂移。

48 高且宽为 48 倍数的图按 48x48 帧逐帧判定（带内相邻帧间隔 >=5px 透明边，
8 连通不会跨帧误并）；其余图（单图武器/头像）整图判定。

任何 stray > 0 即 exit 1。

Usage:
    py -3.14 tools/assert_no_stray_dots.py
"""
from __future__ import annotations

import sys
from pathlib import Path

import numpy as np
from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parent))

from clean_weapon_sprites import ALPHA_MIN, JOIN_DIST, MIN_JOIN_AREA, components, dilate

ROOT = Path(__file__).resolve().parent.parent
DIRS = (
    ROOT / "assets" / "sprites" / "characters",
    ROOT / "assets" / "sprites" / "weapons",
)


def frames_of(path: Path) -> list[tuple[int, Image.Image]]:
    im = Image.open(path).convert("RGBA")
    w, h = im.size
    if h == 48 and w % 48 == 0 and w > 48:
        return [(i, im.crop((i * 48, 0, (i + 1) * 48, 48))) for i in range(w // 48)]
    return [(0, im)]


def residual_mask(mask: np.ndarray) -> np.ndarray:
    """clean_weapon_sprites.clean_file(:71-96) 的 keep 逻辑（只读版）：
    最大域 + 距主体 <=JOIN_DIST 且 >=MIN_JOIN_AREA 的域并入，其余返回。"""
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


def main() -> int:
    bad: list[str] = []
    checked = 0
    frames_checked = 0
    for d in DIRS:
        for path in sorted(d.glob("*.png")):
            if path.name.endswith(".import"):
                continue
            checked += 1
            for fi, fr in frames_of(path):
                frames_checked += 1
                mask = np.asarray(fr)[:, :, 3] > ALPHA_MIN
                resid = residual_mask(mask)
                n = int(resid.sum())
                if n == 0:
                    continue
                comps = sorted(components(resid), key=len, reverse=True)
                desc = []
                for c in comps[:4]:
                    ys = [p[0] for p in c]
                    xs = [p[1] for p in c]
                    desc.append(f"{len(c)}px x[{min(xs)},{max(xs)}] y[{min(ys)},{max(ys)}]")
                tag = f"frame {fi}" if len(frames_of(path)) > 1 else "whole"
                print(f"[wp10-stray] STRAY {d.name}/{path.name} {tag}: {n}px ({'; '.join(desc)})")
                bad.append(f"{d.name}/{path.name}#{fi}")
            if any(b.startswith(f"{d.name}/{path.name}") for b in bad):
                continue
            print(f"[wp10-stray] OK    {d.name}/{path.name}")
    print(f"[wp10-stray] checked {checked} file(s) / {frames_checked} frame(s)")
    if bad:
        print(f"[wp10-stray] FAIL: stray dots in {len(set(bad))} file(s): {', '.join(sorted(set(bad)))}")
        return 1
    print("[wp10-stray] PASS: 0 stray pixels across characters + weapons")
    return 0


if __name__ == "__main__":
    sys.exit(main())
