#!/usr/bin/env python3
"""Clean AI-generated weapon sprites: keep only the main silhouette, drop stray dots.

The generated sheets leave isolated cyan-white speckles and thin horizontal bands
around the weapon. In-game these render as floating "white dust" beside the gun.

Rules
-----
* 8-connected component labelling on alpha>40.
* Keep the largest component (the gun body) and any component whose bounding box
  overlaps/joins it within 2px (muzzle brake, magazine, grip usually connected).
* Delete everything else (isolated dots, thin bands, fragments).
* Optionally boost brightness/contrast so the weapon reads against dark uniforms.

Usage:
    python tools/clean_weapon_sprites.py           # clean all weapons in place
    python tools/clean_weapon_sprites.py --report  # dry-run, print counts only
"""
from __future__ import annotations

import sys
from collections import deque
from pathlib import Path

import numpy as np
from PIL import Image, ImageEnhance

ROOT = Path(__file__).resolve().parent.parent
WEAPONS = ROOT / "assets" / "sprites" / "weapons"
ALPHA_MIN = 40
JOIN_DIST = 1       # px: components closer than this to the body are attached
MIN_JOIN_AREA = 8   # px: smaller fragments are noise even when adjacent


def components(mask: np.ndarray) -> list[list[tuple[int, int]]]:
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
    out = mask.copy()
    for _ in range(dist):
        shifted = out.copy()
        shifted[1:, :] |= out[:-1, :]
        shifted[:-1, :] |= out[1:, :]
        shifted[:, 1:] |= out[:, :-1]
        shifted[:, :-1] |= out[:, 1:]
        out = shifted
    return out


def clean_file(path: Path, dry: bool) -> tuple[int, int]:
    im = Image.open(path).convert("RGBA")
    a = np.asarray(im).copy()
    mask = a[:, :, 3] > ALPHA_MIN
    comps = components(mask)
    if not comps:
        return 0, 0
    comps.sort(key=len, reverse=True)
    keep = np.zeros_like(mask, dtype=bool)
    body = comps[0]
    for y, x in body:
        keep[y, x] = True
    # attach components touching the dilated body (muzzle, magazine, grip)
    body_zone = dilate(keep, JOIN_DIST)
    changed = True
    while changed:
        changed = False
        for comp in comps[1:]:
            if len(comp) < MIN_JOIN_AREA:
                continue
            if any(body_zone[y, x] for y, x in comp):
                for y, x in comp:
                    if not keep[y, x]:
                        keep[y, x] = True
                        changed = True
                body_zone = dilate(keep, JOIN_DIST)
    removed = int(mask.sum() - keep.sum())
    if dry:
        return removed, int(mask.sum())
    a[~keep] = (0, 0, 0, 0)
    out = Image.fromarray(a, "RGBA")
    # brightness/contrast one notch up so the gun silhouettes against dark uniforms
    rgb = out.convert("RGBA")
    arr = np.asarray(rgb).astype(np.float32)
    alpha = arr[:, :, 3:4]
    boosted = np.clip((arr[:, :, :3] - 16.0) * 1.28 + 26.0, 0, 255)
    arr[:, :, :3] = boosted
    arr[:, :, 3:4] = alpha
    Image.fromarray(arr.astype(np.uint8), "RGBA").save(path)
    return removed, int(mask.sum())


def main() -> None:
    dry = "--report" in sys.argv
    total_removed = 0
    for path in sorted(WEAPONS.glob("*.png")):
        if path.name.endswith(".import"):
            continue
        removed, before = clean_file(path, dry)
        total_removed += removed
        print(f"[clean] {path.name:16s} removed={removed:3d} of {before:3d}")
    # assert: after cleaning, only one component must remain per file
    bad = 0
    for path in sorted(WEAPONS.glob("*.png")):
        im = Image.open(path).convert("RGBA")
        mask = np.asarray(im)[:, :, 3] > ALPHA_MIN
        comps = components(mask)
        if len(comps) > 1 or (comps and len(comps[0]) < mask.sum()):
            bad += 1
            print(f"[clean] RESIDUAL COMPONENTS in {path.name}: {len(comps)}")
    print(f"[clean] total removed px = {total_removed}, residual files = {bad}")
    if bad:
        sys.exit(1)


if __name__ == "__main__":
    main()
