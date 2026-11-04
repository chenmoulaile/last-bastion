#!/usr/bin/env python3
"""wp8-tests-ci: assert weapon sprites contain no stray dots (武器杂点断言).

A weapon PNG passes when tools/clean_weapon_sprites.py 的杂点判定（dry 模式，
只读不改文件）报告 removed == 0——即除了与枪身主体相连的部分外，没有孤立
噪点/细碎残片。出现任何杂点即 exit 1。

Usage:
    py -3.14 tools/assert_weapon_clean.py
"""
from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from clean_weapon_sprites import WEAPONS, clean_file


def main() -> None:
    bad: list[str] = []
    for path in sorted(WEAPONS.glob("*.png")):
        removed, total = clean_file(path, True)  # dry=True：只统计，不写盘
        status = "OK" if removed == 0 else "STRAY"
        print(f"[wp8-clean] {path.name:20s} stray={removed:4d} of {total:4d} {status}")
        if removed != 0:
            bad.append(path.name)
    if bad:
        print(f"[wp8-clean] FAIL: {len(bad)} weapon sheet(s) contain stray dots: {', '.join(bad)}")
        sys.exit(1)
    print(f"[wp8-clean] PASS: all weapon sheets clean ({len(list(WEAPONS.glob('*.png')))} files)")


if __name__ == "__main__":
    main()
