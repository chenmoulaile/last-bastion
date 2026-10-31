#!/usr/bin/env python3
"""S2 environment pipeline: backgrounds, tiles, props from AI source sheets."""
from __future__ import annotations

import sys
from pathlib import Path

import numpy as np
from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parent))
from gen_ai_sprites import SRC, ROOT, remove_background, fill_holes, pixelize, extract_poses  # noqa: E402

EOUT = ROOT / "assets" / "sprites" / "environment"

BG_W, BG_H = 960, 360
MID_MAX_H, FAR_MAX_H = 150, 100

BG_MAP = {
    ("suburb", "mid"): "A_wide_horizontal_building_ban_2026-10-31T01-05-44.png",
    ("suburb", "far"): "A_wide_horizontal_building_ban_2026-10-31T01-05-55.png",
    ("city", "mid"):   "A_wide_horizontal_building_ban_2026-10-31T01-06-07.png",
    ("city", "far"):   "A_wide_horizontal_building_ban_2026-10-31T01-06-18.png",
    ("subway", "mid"): "A_wide_horizontal_scenery_band_2026-10-31T01-06-28.png",
    ("subway", "far"): "A_wide_horizontal_scenery_band_2026-10-31T01-07-00.png",
    ("military", "mid"): "A_wide_horizontal_scenery_band_2026-10-31T01-07-11.png",
    ("military", "far"): "A_wide_horizontal_scenery_band_2026-10-31T01-07-22.png",
    ("bridge", "mid"):   "A_wide_horizontal_scenery_band_2026-10-31T01-07-32.png",
    ("bridge", "far"):   "A_wide_horizontal_scenery_band_2026-10-31T01-07-43.png",
}

TILE_MAP = {
    "suburb":   "Seamless_tileable_chunky_pixel_2026-10-31T01-08-27.png",
    "city":     "Seamless_tileable_chunky_pixel_2026-10-31T01-08-39.png",
    "subway":   "Seamless_tileable_chunky_pixel_2026-10-31T01-08-49.png",
    "military": "Seamless_tileable_chunky_pixel_2026-10-31T01-09-00.png",
    "bridge":   "Seamless_tileable_chunky_pixel_2026-10-31T01-09-10.png",
}

# 4x2 props sheet
PROPS_A = {
    "car": (80, 36), "dumpster": (40, 28), "sandbags": (40, 18), "barrel": (16, 24),
    "barrel_explosive": (16, 24), "crate": (20, 20), "streetlight": (16, 80), "generator": (32, 24),
}
# 3x3 objects sheet
PROPS_B = {
    "door_wood": (24, 48), "door_metal": (24, 48), "door_glass": (24, 48),
    "window_frame": (32, 48), "sign": (40, 28), "radio": (22, 16),
    "apc": (140, 52), "helicopter": (120, 52), "elevator": (64, 88),
}


def strip_paper_white(img: Image.Image) -> Image.Image:
    """Remove sealed white regions the border flood-fill could not reach
    (e.g. continuous building walls sealing the background); enclosed whites
    are restored afterwards by fill_holes."""
    a = np.asarray(img).copy()
    rgb = a[:, :, :3].astype(np.int16)
    lum = rgb.mean(axis=2)
    sat = rgb.max(axis=2) - rgb.min(axis=2)
    kill = (lum > 232) & (sat < 28) & (a[:, :, 3] > 40)
    a[kill] = (0, 0, 0, 0)
    return Image.fromarray(a, "RGBA")


def strip_dark_sky(img: Image.Image) -> Image.Image:
    """Bands sometimes come with a baked near-black sky. Flood from the borders
    over near-black low-saturation pixels to make it transparent."""
    a = np.asarray(img).copy()
    rgb = a[:, :, :3].astype(np.int16)
    h, w, _ = rgb.shape
    lum = rgb.mean(axis=2)
    sat = rgb.max(axis=2) - rgb.min(axis=2)
    if lum[:8].mean() > 40:      # top of band is bright -> no dark sky
        return img
    from collections import deque
    is_dark = (lum < 34) & (sat < 20)
    mask = np.zeros((h, w), dtype=bool)
    dq = deque()
    for x in range(w):
        for y in (0, h - 1):
            if is_dark[y, x] and not mask[y, x]:
                mask[y, x] = True; dq.append((y, x))
    for y in range(h):
        for x in (0, w - 1):
            if is_dark[y, x] and not mask[y, x]:
                mask[y, x] = True; dq.append((y, x))
    while dq:
        y, x = dq.popleft()
        for ny, nx in ((y-1, x), (y+1, x), (y, x-1), (y, x+1)):
            if 0 <= ny < h and 0 <= nx < w and not mask[ny, nx] and is_dark[ny, nx]:
                mask[ny, nx] = True; dq.append((ny, nx))
    a[mask] = (0, 0, 0, 0)
    return Image.fromarray(a, "RGBA")


def make_bg(src: Path, out: Path, max_h: int, colors: int = 40) -> None:
    img = remove_background(Image.open(src).convert("RGB"))
    img = strip_paper_white(img)
    img = fill_holes(img)
    img = img.crop(img.getbbox())
    scale = min(BG_W / img.width, max_h / img.height)
    nw, nh = max(1, round(img.width * scale)), max(1, round(img.height * scale))
    band = img.resize((nw, nh), Image.LANCZOS).convert("RGB").quantize(colors=colors, method=Image.MEDIANCUT,
                                                                       dither=Image.Dither.NONE).convert("RGBA")
    band = strip_dark_sky(band)
    # mirror-tile narrow bands to fill the full 960 width (seamless by construction)
    if nw < BG_W:
        pieces = [band]
        flip = True
        while sum(p.width for p in pieces) < BG_W:
            last = pieces[-1]
            pieces.append(last.transpose(Image.FLIP_LEFT_RIGHT) if flip else last)
            flip = not flip
        tiled = Image.new("RGBA", (sum(p.width for p in pieces), nh), (0, 0, 0, 0))
        x = 0
        for p in pieces:
            tiled.alpha_composite(p, (x, 0)); x += p.width
        band = tiled.crop((0, 0, BG_W, nh))
        nw = BG_W
    canvas = Image.new("RGBA", (BG_W, BG_H), (0, 0, 0, 0))
    canvas.alpha_composite(band, (0, BG_H - nh))
    canvas.save(out)
    print(f"[ok] {out.name}: band {nw}x{nh}")


def make_tiles(src: Path, out: Path) -> None:
    tex = Image.open(src).convert("RGB").resize((256, 96), Image.LANCZOS)
    tex = tex.quantize(colors=32, method=Image.MEDIANCUT, dither=Image.Dither.NONE).convert("RGB")
    a = np.asarray(tex).astype(np.int16)

    def band(y0: int, mul: float = 1.0, top_light: int = 0) -> Image.Image:
        b = np.clip(a[y0:y0 + 16] * mul, 0, 255).astype(np.uint8).copy()
        if top_light:
            b[:top_light] = np.clip(b[:top_light].astype(np.int16) * 1.25 + 20, 0, 255).astype(np.uint8)
        return Image.fromarray(b)

    atlas = Image.new("RGB", (256, 128))
    atlas.paste(band(0, top_light=3), (0, 0))    # row 0: surface
    atlas.paste(band(16), (0, 16))               # row 1: fill
    atlas.paste(band(32, mul=0.92), (0, 32))     # row 2: variant
    atlas.paste(band(48, mul=1.05), (0, 48))     # row 3: platform
    atlas.paste(band(64, mul=0.72), (0, 80))     # row 5: deep
    atlas.save(out)
    print(f"[ok] {out.name}")


def make_props(sheet_file: str, mapping: dict, grid: tuple[int, int]) -> None:
    sheet = Image.open(SRC / sheet_file)
    tiles = extract_poses(sheet, expected=len(mapping), grid=grid)
    for i, (name, (bw, bh)) in enumerate(mapping.items()):
        tile = tiles[i] if i < len(tiles) else Image.new("RGBA", (8, 8), (0, 0, 0, 0))
        img = pixelize(tile, bw, bh, colors=28)
        img.save(EOUT / f"{name}.png")
        print(f"[ok] prop {name} -> {img.size}")


if __name__ == "__main__":
    for (theme, layer), fname in BG_MAP.items():
        make_bg(SRC / fname, EOUT / f"bg_{theme}_{layer}.png", MID_MAX_H if layer == "mid" else FAR_MAX_H)
    for theme, fname in TILE_MAP.items():
        make_tiles(SRC / fname, EOUT / f"tiles_{theme}.png")
    make_props("A_4x2_sprite_sheet_grid__8_equ_2026-10-31T01-09-21.png", PROPS_A, (4, 2))
    make_props("A_3x3_sprite_sheet_grid__9_equ_2026-10-31T01-09-34.png", PROPS_B, (3, 3))
    print("done")
