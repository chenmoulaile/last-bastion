#!/usr/bin/env python3
"""S2 pipeline: zombie sheets -> strips with procedural animations; weapon sheet -> sprites.

Usage:
    python tools/gen_ai_s2.py zombies
    python tools/gen_ai_s2.py weapons
"""
from __future__ import annotations

import sys
from pathlib import Path

import numpy as np
from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parent))
from gen_ai_sprites import (  # noqa: E402
    SRC, ROOT, OUT, PREVIEW, extract_poses, pixelize, place, shift, rot, crop_content,
)

ZOUT = ROOT / "assets" / "sprites" / "zombies"
WOUT = ROOT / "assets" / "sprites" / "weapons"
EOUT = ROOT / "assets" / "sprites" / "environment"

Z_SHEETS = {
    "shamblers": "A_3x2_sprite_sheet_grid__6_equ_2026-10-31T00-53-53.png",
    "armored":   "A_3x2_sprite_sheet_grid__6_equ_2026-10-31T00-54-04.png",
    "mutants":   "A_3x2_sprite_sheet_grid__6_equ_2026-10-31T00-54-15.png",
}

# sheet name -> [zombie prefixes in cell order]
Z_MAP = {
    "shamblers": ["common_a", "common_b", "common_c", "common_d", "mud", "scavenger"],
    "armored":   ["hardhat", "hazmat", "riot", "clown", "smoker", "boomer"],
    "mutants":   ["spitter", "hunter", "charger", "jockey", "tank", "witch"],
}

# per-zombie frame size (must match zombie_*.tres sprite_size)
Z_FRAMES = {
    "common_a": (36, 48), "common_b": (36, 48), "common_c": (36, 48), "common_d": (36, 48),
    "mud": (36, 48), "scavenger": (36, 48), "clown": (36, 48), "hardhat": (36, 48),
    "hazmat": (36, 48), "riot": (36, 48),
    "smoker": (48, 48), "spitter": (48, 48), "hunter": (48, 48), "jockey": (48, 48),
    "boomer": (48, 48),
    "witch": (48, 72), "charger": (60, 60), "tank": (96, 96),
}

# extra anims beyond idle/run/attack/hurt/die
Z_EXTRA = {
    "boomer": ["inflate"], "charger": ["charge", "punch"], "hunter": ["pin", "pounce"],
    "jockey": ["leap", "ride"], "spitter": ["spit"], "tank": ["punch", "throw"],
    "witch": ["chase", "scream"],
}


def anchored(base: Image.Image, deg: float = 0.0, dx: int = 0, dy: int = 0,
             stretch_x: float = 1.0, squash_y: float = 1.0) -> Image.Image:
    """Transform a placed frame, keeping feet at the bottom center."""
    img = base
    if stretch_x != 1.0 or squash_y != 1.0:
        nw = max(1, round(img.width * stretch_x))
        nh = max(1, round(img.height * squash_y))
        img = img.resize((nw, nh), Image.NEAREST)
    if deg != 0.0:
        img = rot(img, deg)
    canvas = Image.new("RGBA", base.size, (0, 0, 0, 0))
    x = (base.width - img.width) // 2 + dx
    y = base.height - img.height + dy
    canvas.alpha_composite(img, (x, y))
    return canvas


def make_strips(base: Image.Image, prefix: str) -> dict[str, Image.Image]:
    fw, fh = base.size
    strips: dict[str, list[Image.Image]] = {}

    strips["idle"] = [base, shift(base, dy=-1), shift(base, dy=-2), shift(base, dy=-1)]
    strips["run"] = [anchored(base, 5), anchored(base, 0, dy=-1), anchored(base, -5),
                     anchored(base, 0, dy=-1), anchored(base, 6, dy=-2), anchored(base, -6, dy=-2)]
    strips["attack"] = [base, anchored(base, 8, dx=2), anchored(base, 10, dx=4), anchored(base, 5, dx=2)]
    strips["hurt"] = [shift(base, dx=-1), shift(base, dx=-2)]
    lying = anchored(base, 90)
    strips["die"] = [anchored(base, 15), anchored(base, 40, dy=-1), anchored(base, 70, dy=-2),
                     lying, shift(lying, dy=-1), lying]
    for extra in Z_EXTRA.get(prefix, []):
        if extra == "inflate":
            strips[extra] = [base, anchored(base, stretch_x=1.15), anchored(base, stretch_x=1.3)]
        elif extra in ("charge", "pounce", "leap"):
            strips[extra] = [anchored(base, -8, dx=1), anchored(base, -12, dx=3, dy=-1),
                             anchored(base, -8, dx=2), anchored(base, -4, dx=1)]
        elif extra == "punch":
            strips[extra] = [base, anchored(base, 8, dx=3), anchored(base, 5, dx=2)]
        elif extra == "spit":
            strips[extra] = [anchored(base, -6), anchored(base, -10, dy=-1), anchored(base, -4)]
        elif extra == "ride":
            strips[extra] = [anchored(base, squash_y=0.85), anchored(base, squash_y=0.8, dy=1)]
        elif extra == "pin":
            strips[extra] = [anchored(base, squash_y=0.8), anchored(base, squash_y=0.75, dy=1)]
        elif extra == "scream":
            strips[extra] = [anchored(base, -8, dy=-1), anchored(base, -11, dy=-2)]
        elif extra == "throw":
            strips[extra] = [anchored(base, -6, dx=-1, dy=-1), anchored(base, 6, dx=1, dy=-2),
                             anchored(base, 10, dx=2)]
        elif extra == "chase":
            strips[extra] = [anchored(base, 7), anchored(base, 0, dy=-1), anchored(base, -7),
                             anchored(base, 0, dy=-1), anchored(base, 8, dy=-2), anchored(base, -8, dy=-2)]

    def strip(frames):
        out = Image.new("RGBA", (fw * len(frames), fh), (0, 0, 0, 0))
        for i, f in enumerate(frames):
            out.alpha_composite(f, (i * fw, 0))
        return out

    return {k: strip(v) for k, v in strips.items()}


def process_zombies() -> None:
    for sheet_name, path in Z_SHEETS.items():
        sheet = Image.open(SRC / path)
        tiles = extract_poses(sheet, expected=6, grid=(3, 2))
        prefixes = Z_MAP[sheet_name]
        for i, prefix in enumerate(prefixes):
            fw, fh = Z_FRAMES[prefix]
            tile = tiles[i]
            # place into the PER-ZOMBIE frame canvas (place() hardcodes 48x48)
            px = pixelize(tile, fw - 4, fh - 4, colors=28)
            base = Image.new("RGBA", (fw, fh), (0, 0, 0, 0))
            base.alpha_composite(px, ((fw - px.width) // 2, fh - px.height))
            strips = make_strips(base, prefix)
            for anim, img in strips.items():
                img.save(ZOUT / f"{prefix}_{anim}.png")
            if "--preview" in sys.argv:
                PREVIEW.mkdir(parents=True, exist_ok=True)
                row = Image.new("RGBA", (sum(s.width + 4 for s in strips.values()), fh), (50, 44, 42, 255))
                x = 0
                for s in strips.values():
                    row.alpha_composite(s, (x, 0)); x += s.width + 4
                row.save(PREVIEW / f"z_{prefix}.png")
            print(f"[ok] zombie {prefix}: {len(strips)} anims @ {fw}x{fh}")


# ---------------------------------------------------------------------------
W_MAP = ["ar15", "m9", "shotgun", "smg", "sniper", "lmg", "chainsaw", "katana",
         "axe", "grenade", "molotov", "medkit", "ammo", "pills", "gold", "bile"]
W_BOX = {
    "ar15": (40, 14), "m9": (22, 12), "shotgun": (40, 12), "smg": (30, 12),
    "sniper": (44, 12), "lmg": (42, 16), "chainsaw": (34, 18), "katana": (40, 10),
    "axe": (26, 16), "grenade": (12, 14), "molotov": (12, 16), "medkit": (16, 12),
    "ammo": (14, 12), "pills": (10, 12), "gold": (14, 10), "bile": (12, 14),
}


def process_weapons() -> None:
    sheet = Image.open(SRC / "A_4x4_sprite_sheet_grid__16_eq_2026-10-31T00-54-26.png")
    tiles = extract_poses(sheet, expected=16, grid=(4, 4))
    for i, wid in enumerate(W_MAP):
        tile = tiles[i] if i < len(tiles) else Image.new("RGBA", (8, 8), (0, 0, 0, 0))
        bw, bh = W_BOX[wid]
        img = pixelize(tile, bw, bh, colors=24)
        img.save(WOUT / f"{wid}.png")
        # matching pickup icon in environment/
        pickup = f"pickup_{wid}.png"
        if (EOUT / pickup).exists():
            px = pixelize(tile, 14, 14, colors=20)
            canvas = Image.new("RGBA", (16, 16), (0, 0, 0, 0))
            canvas.alpha_composite(px, ((16 - px.width) // 2, (16 - px.height) // 2))
            canvas.save(EOUT / pickup)
        print(f"[ok] weapon {wid} -> {img.size}")
    if "--preview" in sys.argv:
        row = Image.new("RGBA", (sum((W_BOX[w][0] + 6) for w in W_MAP), 24), (50, 44, 42, 255))
        x = 0
        for w in W_MAP:
            im = Image.open(WOUT / f"{w}.png")
            row.alpha_composite(im, (x, (24 - im.height) // 2)); x += im.width + 6
        row.resize((row.width * 3, row.height * 3), Image.NEAREST).save(PREVIEW / "weapons.png")


if __name__ == "__main__":
    mode = sys.argv[1] if len(sys.argv) > 1 else "all"
    if mode in ("zombies", "all"):
        process_zombies()
    if mode in ("weapons", "all"):
        process_weapons()
    print("done")
