"""wp2-facade-dk-style: 生成专用建筑立面图集 facade_{theme}.png。

摆脱「立面 = 路面砖」的灰色石板观感：每主题 256x128 图集（16 列 x 8 行，
每格 16px），行布局与 building_builder.gd 的 tile 坐标约定一一对应：

  row 0  内部地板顶面（水泥铺面，顶部高光）   —— build_interior 的 base_row
  row 1  上段墙体（抹灰/釉面/金属壁板）col 3 = 门楣木梁 —— wall_row_hi
  row 2  地板填充（暗色渣土/混凝土）           —— build_interior 楼板下填充
  row 3  屋顶檐口/天花板（压顶石 + 下缘阴影）   —— 屋顶两行 + 内部天花板
  row 4  内部侧墙（深色砖）col 4 = 内墙砖      —— build_interior 侧墙
  row 5  下段墙体（砖墙）col 5 = 门框立柱      —— wall_row_lo

本机 Python：py -3.14（裸 python 是 MSYS2 3.12，无 PIL）。
重跑前先删 tools/__pycache__。
"""
from __future__ import annotations

import os
import sys

from PIL import Image

sys.path.insert(0, os.path.dirname(__file__))
from pixel_art import Canvas, P, rgba, shade, mix

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
ENV = os.path.join(ROOT, "assets", "sprites", "environment")
os.makedirs(ENV, exist_ok=True)

THEMES = {
    "suburb": dict(
        # 红棕砖 + 米黄抹灰 + 深木檐：临街民居
        brick=(122, 74, 58), brick_dark=(96, 56, 44), mortar=(74, 52, 44),
        plaster=(188, 168, 132), plaster_dark=(158, 138, 106), stain=(142, 118, 88),
        trim=(84, 58, 36), roof=(88, 62, 48), roof_hi=(122, 90, 66), ledge=(150, 138, 112),
        floor=(96, 88, 72), floor_hi=(126, 116, 94), fill=(52, 48, 42),
        inner=(66, 46, 38), inner_hi=(88, 62, 50),
        lit=(244, 196, 110),
    ),
    "city": dict(
        # 深灰褐砖 + 暖灰抹灰 + 钢檐：市区公寓
        brick=(96, 70, 62), brick_dark=(74, 52, 48), mortar=(58, 46, 44),
        plaster=(150, 138, 118), plaster_dark=(120, 110, 94), stain=(104, 92, 78),
        trim=(62, 66, 72), roof=(58, 60, 66), roof_hi=(92, 96, 102), ledge=(128, 128, 126),
        floor=(80, 80, 78), floor_hi=(108, 108, 104), fill=(44, 44, 46),
        inner=(54, 40, 38), inner_hi=(74, 56, 52),
        lit=(232, 190, 104),
    ),
    "subway": dict(
        # 釉面绿砖墙 + 灰浆抹灰 + 混凝土檐：地铁站口/票房
        brick=(86, 100, 92), brick_dark=(66, 78, 72), mortar=(46, 56, 52),
        plaster=(148, 152, 138), plaster_dark=(118, 124, 110), stain=(100, 106, 94),
        trim=(56, 66, 60), roof=(64, 68, 62), roof_hi=(96, 102, 92), ledge=(126, 132, 120),
        floor=(78, 82, 72), floor_hi=(106, 110, 96), fill=(38, 42, 38),
        inner=(52, 60, 54), inner_hi=(70, 80, 72),
        lit=(220, 200, 110),
    ),
    "military": dict(
        # 混凝土砌块 + 橄榄绿壁板 + 军绿檐：营房/工事
        brick=(104, 104, 92), brick_dark=(82, 82, 72), mortar=(62, 62, 54),
        plaster=(112, 118, 88), plaster_dark=(88, 94, 68), stain=(76, 82, 58),
        trim=(58, 62, 44), roof=(72, 78, 58), roof_hi=(102, 108, 80), ledge=(128, 132, 110),
        floor=(88, 88, 76), floor_hi=(114, 114, 98), fill=(44, 46, 40),
        inner=(60, 60, 50), inner_hi=(80, 80, 68),
        lit=(236, 202, 118),
    ),
    "bridge": dict(
        # 锈蚀钢板 + 冷灰混凝土 + 钢桁架檐：桥区工业楼
        brick=(108, 76, 56), brick_dark=(84, 58, 44), mortar=(60, 48, 42),
        plaster=(118, 122, 126), plaster_dark=(92, 96, 100), stain=(76, 80, 84),
        trim=(66, 58, 50), roof=(70, 62, 54), roof_hi=(104, 92, 76), ledge=(122, 124, 122),
        floor=(82, 84, 82), floor_hi=(110, 112, 108), fill=(42, 44, 46),
        inner=(70, 50, 38), inner_hi=(92, 66, 50),
        lit=(228, 186, 100),
    ),
}


def brick_tile(cv: Canvas, ox: int, oy: int, th: dict, seed: int) -> None:
    """16px 砖墙：4px 高砖层、错缝 8px 宽砖，砖缝灌浆色，砖面带明暗。"""
    rnd_r = seed % 16
    cv.rect(ox, oy, ox + 15, oy + 15, th["mortar"])
    for by in range(4):
        y = oy + by * 4
        offset = 4 if by % 2 else 0
        for bx in range(3):
            x = ox + ((bx * 8 + offset) % 16)
            x1 = min(x + 6, ox + 15)
            tone = 1.0 + ((rnd_r + bx + by * 3) % 5 - 2) * 0.045
            cv.rect(x, y, x1, y + 2, shade(th["brick"], tone))
            cv.rect(x, y, x1, y, shade(th["brick"], tone * 1.14))
            cv.rect(x, y + 2, x1, y + 2, th["brick_dark"])


def plaster_tile(cv: Canvas, ox: int, oy: int, th: dict, variant: int) -> None:
    """16px 抹灰墙：基底 + 噪点，部分变体带水平壁板缝或渗水渍。"""
    cv.rect(ox, oy, ox + 15, oy + 15, th["plaster"])
    if variant % 4 == 1:
        # 壁板：水平板缝 + 板面高光
        for y in range(3, 16, 4):
            cv.rect(ox, oy + y, ox + 15, oy + y, th["plaster_dark"])
            cv.rect(ox, oy + y + 1, ox + 15, oy + y + 1, shade(th["plaster"], 1.12))
    elif variant % 4 == 2:
        # 渗水渍：从顶部往下拖一道暗痕
        x = ox + 3 + (variant % 3) * 4
        cv.rect(x, oy, x + 2, oy + 9, th["stain"])
        cv.rect(x + 1, oy + 10, x + 2, oy + 12, mix(th["stain"], th["plaster"], 0.5))
    elif variant % 4 == 3:
        # 抹灰破损：露出一小块底砖
        cv.rect(ox + 9, oy + 8, ox + 14, oy + 13, th["brick_dark"])
        cv.rect(ox + 10, oy + 9, ox + 13, oy + 10, th["brick"])
    cv.noise(th["plaster_dark"], 0.10, (ox, oy, ox + 15, oy + 15), 700 + variant)
    cv.noise(shade(th["plaster"], 1.08), 0.07, (ox, oy, ox + 15, oy + 15), 800 + variant)


def cornice_tile(cv: Canvas, ox: int, oy: int, th: dict, variant: int) -> None:
    """16px 檐口：顶部压顶石亮边、齿状托架、下缘落影。"""
    cv.rect(ox, oy, ox + 15, oy + 15, th["roof"])
    cv.rect(ox, oy, ox + 15, oy + 2, th["ledge"])            # 压顶石
    cv.rect(ox, oy, ox + 15, oy, shade(th["ledge"], 1.2))    # 高光
    cv.rect(ox, oy + 3, ox + 15, oy + 4, shade(th["roof"], 0.7))
    # 齿托：每 4px 一齿
    for x in range(0, 16, 4):
        off = 1 if variant % 2 else 0
        cv.rect(ox + x + off, oy + 6, ox + x + 1 + off, oy + 10, shade(th["roof"], 1.25))
    cv.rect(ox, oy + 12, ox + 15, oy + 15, shade(th["roof"], 0.62))  # 落影
    if variant % 5 == 0:
        cv.noise(shade(th["roof"], 0.8), 0.12, (ox, oy + 5, ox + 15, oy + 11), 900 + variant)


def floor_top_tile(cv: Canvas, ox: int, oy: int, th: dict, variant: int) -> None:
    """16px 地板顶面：铺面板 + 顶部高光，供内部房间使用。"""
    cv.rect(ox, oy, ox + 15, oy + 15, th["floor"])
    cv.rect(ox, oy, ox + 15, oy + 1, th["floor_hi"])
    cv.rect(ox, oy + 15, ox + 15, oy + 15, shade(th["floor"], 0.72))
    for x in range(0, 16, 8):
        cv.rect(ox + x + 7, oy + 2, ox + x + 7, oy + 14, shade(th["floor"], 0.85))
    cv.noise(shade(th["floor"], 1.1), 0.06, (ox, oy, ox + 15, oy + 15), 1000 + variant)


def fill_tile(cv: Canvas, ox: int, oy: int, th: dict, variant: int) -> None:
    """16px 楼板填充：暗色渣土/混凝土。"""
    cv.rect(ox, oy, ox + 15, oy + 15, th["fill"])
    cv.noise(shade(th["fill"], 1.18), 0.10, (ox, oy, ox + 15, oy + 15), 1100 + variant)
    cv.noise(shade(th["fill"], 0.85), 0.08, (ox, oy, ox + 15, oy + 15), 1200 + variant)


def inner_wall_tile(cv: Canvas, ox: int, oy: int, th: dict, seed: int) -> None:
    """16px 内部侧墙：深色砖。"""
    rnd_r = seed % 16
    cv.rect(ox, oy, ox + 15, oy + 15, shade(th["inner"], 0.8))
    for by in range(4):
        y = oy + by * 4
        offset = 4 if by % 2 else 0
        for bx in range(3):
            x = ox + ((bx * 8 + offset) % 16)
            x1 = min(x + 6, ox + 15)
            tone = 1.0 + ((rnd_r + bx + by) % 4 - 1) * 0.05
            cv.rect(x, y, x1, y + 2, shade(th["inner"], tone))
            cv.rect(x, y, x1, y, th["inner_hi"])


def lintel_tile(cv: Canvas, ox: int, oy: int, th: dict) -> None:
    """row1 col3 门楣：横木梁，下缘落影（嵌在墙里的观感）。"""
    cv.rect(ox, oy, ox + 15, oy + 15, th["plaster"])
    cv.rect(ox, oy + 3, ox + 15, oy + 10, th["trim"])
    cv.rect(ox, oy + 3, ox + 15, oy + 4, shade(th["trim"], 1.3))
    for x in range(2, 16, 5):
        cv.rect(ox + x, oy + 5, ox + x, oy + 9, shade(th["trim"], 0.75))
    cv.rect(ox, oy + 11, ox + 15, oy + 12, shade(th["trim"], 0.55))


def pillar_tile(cv: Canvas, ox: int, oy: int, th: dict) -> None:
    """row5 col5 门框立柱：石砌方柱，左右暗缘 + 中段亮面。"""
    cv.rect(ox, oy, ox + 15, oy + 15, th["brick_dark"])
    cv.rect(ox + 3, oy, ox + 12, oy + 15, shade(th["brick"], 1.18))
    cv.rect(ox + 3, oy, ox + 4, oy + 15, shade(th["brick"], 0.72))
    cv.rect(ox + 11, oy, ox + 12, oy + 15, shade(th["brick"], 0.72))
    cv.rect(ox + 5, oy, ox + 10, oy + 15, shade(th["brick"], 1.3))
    for y in range(0, 16, 4):
        cv.rect(ox + 3, oy + y, ox + 12, oy + y, shade(th["mortar"], 0.9))


def make_facade(theme: str) -> None:
    th = THEMES[theme]
    cv = Canvas(256, 128)
    # row 0: 地板顶面 | row 1: 抹灰上段墙（col3 = 门楣）| row 2: 楼板填充
    for col in range(16):
        floor_top_tile(cv, col * 16, 0, th, col)
        if col == 3:
            lintel_tile(cv, col * 16, 16, th)
        else:
            plaster_tile(cv, col * 16, 16, th, col)
        fill_tile(cv, col * 16, 32, th, col)
    # row 3: 檐口/天花板 | row 4: 内部侧墙 | row 5: 砖墙下段（col5 = 立柱）
    for col in range(16):
        cornice_tile(cv, col * 16, 48, th, col)
        inner_wall_tile(cv, col * 16, 64, th, col + 3)
        if col == 5:
            pillar_tile(cv, col * 16, 80, th)
        else:
            brick_tile(cv, col * 16, 80, th, col)
    out = os.path.join(ENV, f"facade_{theme}.png")
    cv.save(out)
    print(f"facade_{theme}.png 256x128 ok")


def main() -> None:
    for theme in THEMES:
        make_facade(theme)
    # 预览：五主题并排（上=墙/檐，下=内部行），供人眼复核
    items = [(f"facade_{t}", Image.open(os.path.join(ENV, f"facade_{t}.png"))) for t in THEMES]
    scale, cols = 2, 5
    w, h = 256 * scale, 128 * scale
    sheet = Image.new("RGBA", (w * cols, h), (10, 11, 15, 255))
    for i, (_, im) in enumerate(items):
        sheet.alpha_composite(im.resize((w, h), Image.NEAREST), (i * w, 0))
    sheet.save(os.path.join(ROOT, "build", "preview_facade.png"))
    print("build/preview_facade.png ok")


if __name__ == "__main__":
    main()
