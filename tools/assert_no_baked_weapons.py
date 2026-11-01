#!/usr/bin/env python3
"""Assert character frames contain NO baked-in weapons (P0-1).

Heuristic: a gun reads as a long thin horizontal run of dark metallic pixels
(gun palette: desaturated blue-grey, brightness 40..110, saturation low)
detached from the body silhouette. For every animation strip we scan each frame
for horizontal runs >= 10px of gun-palette pixels that form a standalone band
(<= 4px tall). A real body is tall; arms holding nothing are skin/sleeve colors.

Exit code 1 if any violation.
"""
from __future__ import annotations

import sys
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
CHARS = ROOT / "assets" / "sprites" / "characters"


def is_gun_palette(px) -> bool:
    r, g, b = int(px[0]), int(px[1]), int(px[2])
    mx, mn = max(r, g, b), min(r, g, b)
    return 30 <= mx <= 120 and (mx - mn) <= 26 and b >= r


def check_strip(path: Path) -> list[str]:
    im = Image.open(path).convert("RGBA")
    a = np.asarray(im)
    h, w = a.shape[:2]
    # frame width from CHAR_ANIMS table replicated here
    counts = {"idle": 4, "run": 8, "shoot": 3, "melee": 3, "hurt": 2,
              "die": 6, "crouch": 3, "slide": 2, "jump": 2}
    issues: list[str] = []
    for anim, n in counts.items():
        if not path.name.endswith(f"_{anim}.png"):
            continue
        fw = w // n
        for f in range(n):
            frame = a[:, f * fw:(f + 1) * fw]
            alpha = frame[:, :, 3] > 40
            for y in range(8, min(h, 38)):  # 枪械只会出现在胸/手高度带（8..38）；地面靴子/阴影除外
                run = 0
                for x in range(fw):
                    if alpha[y, x] and is_gun_palette(frame[y, x]):
                        run += 1
                    else:
                        if run >= 10:
                            # confirm band thinness: rows above/below mostly empty
                            above = alpha[max(0, y - 5):max(0, y - 2), max(0, x - run):x]
                            below = alpha[min(h - 1, y + 2):min(h, y + 5), max(0, x - run):x]
                            th = (above.sum() + below.sum()) / max(1, run * 6)
                            if th < 0.25:
                                issues.append(f"{path.name} {anim}#{f} gun-like band at y={y} len={run}")
                        run = 0
                if run >= 10:
                    issues.append(f"{path.name} {anim}#{f} gun-like band at y={y} len={run}")
    return issues


def main() -> None:
    all_issues: list[str] = []
    for path in sorted(CHARS.glob("*_*.png")):
        name = path.name
        if any(name.endswith(f"_{a}.png") for a in
               ["idle", "run", "shoot", "melee", "hurt", "die", "crouch", "slide", "jump"]):
            all_issues.extend(check_strip(path))
    if all_issues:
        for issue in all_issues[:20]:
            print("[no-gun] VIOLATION:", issue)
        print(f"[no-gun] FAIL: {len(all_issues)} violations")
        sys.exit(1)
    print("[no-gun] PASS: no baked-in weapons detected in character frames")


if __name__ == "__main__":
    main()
