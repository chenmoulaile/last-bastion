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
from PIL import Image, ImageDraw

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


def pose_attack(base: Image.Image, lean: float = 0.0, dx: int = 0, dy: int = 0,
                stretch: float = 1.0, swipe: bool = False) -> Image.Image:
    """True attack pose instead of a shifted copy of the idle frame: the legs
    stay planted while the upper body leans / reaches toward the target.
    Source art faces right, so a forward lean is a clockwise rotation (negative
    PIL angle) plus a positive dx shift. Used for attack frames 0-3 and punch.
    """
    fw, fh = base.size
    legs_h = max(4, fh // 3)
    legs = base.crop((0, fh - legs_h, fw, fh))
    body = base.crop((0, 0, fw, fh - legs_h))
    if lean != 0.0:
        # rotate with expand, then centre-crop back to the original upper-body
        # box so pixels stay 1:1 (a resize refit squashed big frames like tank)
        r = rot(body, lean)
        cx, cy = r.width // 2, r.height // 2
        x0 = cx - body.width // 2
        y0 = cy - body.height // 2
        body = r.crop((x0, y0, x0 + body.width, y0 + body.height))
    if stretch != 1.0:
        body = body.resize((max(1, round(body.width * stretch)), body.height), Image.NEAREST)
    cv = Image.new("RGBA", (fw, fh), (0, 0, 0, 0))
    cv.alpha_composite(legs, (0, fh - legs_h))
    bx = (fw - body.width) // 2 + dx
    by = (fh - legs_h) - body.height + dy
    if bx >= 0 and by >= 0:
        cv.alpha_composite(body, (bx, by))
    else:
        cv.paste(body, (bx, by), body)  # paste tolerates negative offsets
    if swipe:
        # short diagonal claw streaks ahead of the contact pose (right-facing art)
        d = ImageDraw.Draw(cv)
        col = (168, 34, 38, 120)
        for i in range(3):
            yy = fh // 3 + i * (fh // 10)
            d.line([(fw - 16, yy), (fw - 4, yy + 4)], fill=col, width=2)
    return cv


def make_strips(base: Image.Image, prefix: str) -> dict[str, Image.Image]:
    fw, fh = base.size
    strips: dict[str, list[Image.Image]] = {}

    strips["idle"] = [base, shift(base, dy=-1), shift(base, dy=-2), shift(base, dy=-1)]
    strips["run"] = [anchored(base, 5), anchored(base, 0, dy=-1), anchored(base, -5),
                     anchored(base, 0, dy=-1), anchored(base, 6, dy=-2), anchored(base, -6, dy=-2)]
    # attack: wind-up -> swing -> contact -> recover (syncs with damage frame 2)
    strips["attack"] = [pose_attack(base, lean=7, dx=-2),
                        pose_attack(base, lean=-5, dx=2, dy=-1),
                        pose_attack(base, lean=-10, dx=4, stretch=1.07, swipe=True),
                        pose_attack(base, lean=-3, dx=1)]
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
            # charger/tank melee: wind-up -> contact -> recover
            strips[extra] = [pose_attack(base, lean=7, dx=-1),
                             pose_attack(base, lean=-10, dx=4, stretch=1.08, swipe=True),
                             pose_attack(base, lean=-3, dx=1)]
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
