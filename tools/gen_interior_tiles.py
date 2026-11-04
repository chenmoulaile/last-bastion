"""wp3-interior-visuals: 生成室内专用图集 interior_{theme}.png 与家具贴片 interior_furniture.png。

彻底摆脱「室内 = 街道立面图集」的复用：每主题 256x96 图集（16 列 x 6 行，
每格 16px），行布局与 building_builder.gd build_interior 的 tile 坐标一一对应：

  row 0  木地板顶面（暖棕横纹拼板）            —— base_row 行走面
  row 1  墙面（灰泥/墙纸，竖条纹或碎花图案）    —— 室内侧墙上段
  row 2  踢脚线行（墙纸 + 下缘木踢脚板）        —— 侧墙贴地一行
  row 3  天花板（顶部落影 + 底缘高光，兼作平台顶）
  row 4  地板下填充（暗色地基/渣土）            —— base_row+1..+4
  row 5  平台木缘（木板侧面，木箱纹）           —— 二层平台行

interior_furniture.png：5 格 32x32 —— 桌 / 货架 / 木箱 / 床垫 / 下行楼梯贴片。

本机 Python：py -3.14（裸 python 是 MSYS2 3.12，无 PIL）。
重跑前先删 tools/__pycache__。
"""
from __future__ import annotations

import os
import sys

from PIL import Image

sys.path.insert(0, os.path.dirname(__file__))
from pixel_art import Canvas, rgba, shade, mix

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
ENV = os.path.join(ROOT, "assets", "sprites", "environment")
os.makedirs(ENV, exist_ok=True)

THEMES = {
    "suburb": dict(
        # 暖橡木地板 + 米黄墙纸（竖条纹）：临街民居
        floor=(150, 104, 58), floor_hi=(178, 130, 78), floor_dark=(112, 74, 40),
        grain=(128, 86, 46), seam=(96, 62, 34),
        wall=(196, 172, 128), wall_dark=(168, 144, 102), motif=(176, 148, 104),
        base=(96, 62, 34), base_hi=(128, 88, 50),
        ceil=(206, 190, 156), ceil_dark=(164, 146, 112), beam=(178, 158, 120),
        sub=(46, 36, 30), sub_hi=(62, 48, 40),
        plat=(120, 82, 44), plat_hi=(150, 106, 60), plat_dark=(88, 58, 32),
    ),
    "city": dict(
        # 深胡桃木地板 + 暖灰墙纸（几何纹）：市区公寓
        floor=(122, 84, 52), floor_hi=(148, 106, 66), floor_dark=(92, 60, 38),
        grain=(104, 70, 42), seam=(76, 50, 32),
        wall=(158, 144, 122), wall_dark=(130, 118, 98), motif=(138, 124, 100),
        base=(74, 54, 38), base_hi=(100, 74, 52),
        ceil=(168, 158, 140), ceil_dark=(130, 120, 102), beam=(144, 132, 112),
        sub=(40, 36, 32), sub_hi=(54, 48, 42),
        plat=(98, 68, 42), plat_hi=(124, 90, 56), plat_dark=(72, 48, 30),
    ),
    "subway": dict(
        # 旧橡木地板 + 站内灰绿墙裙墙纸：地铁站用房
        floor=(136, 96, 54), floor_hi=(162, 120, 72), floor_dark=(104, 70, 40),
        grain=(116, 80, 44), seam=(86, 58, 34),
        wall=(150, 154, 134), wall_dark=(122, 128, 108), motif=(128, 136, 112),
        base=(70, 76, 58), base_hi=(96, 104, 78),
        ceil=(172, 174, 152), ceil_dark=(134, 138, 116), beam=(148, 152, 128),
        sub=(38, 40, 32), sub_hi=(52, 54, 42),
        plat=(108, 76, 44), plat_hi=(134, 98, 58), plat_dark=(80, 54, 32),
    ),
    "military": dict(
        # 松木地板 + 军绿灰泥墙（水泥裙）：营房
        floor=(142, 106, 62), floor_hi=(168, 132, 82), floor_dark=(110, 80, 46),
        grain=(122, 90, 50), seam=(92, 66, 38),
        wall=(142, 146, 110), wall_dark=(116, 120, 88), motif=(124, 130, 94),
        base=(78, 82, 56), base_hi=(104, 108, 74),
        ceil=(178, 176, 148), ceil_dark=(140, 138, 110), beam=(154, 152, 122),
        sub=(42, 42, 32), sub_hi=(56, 56, 42),
        plat=(114, 82, 48), plat_hi=(140, 104, 62), plat_dark=(84, 58, 34),
    ),
    "bridge": dict(
        # 锈红旧地板 + 水泥灰墙（模板孔）：桥区工业楼
        floor=(128, 84, 48), floor_hi=(154, 106, 62), floor_dark=(98, 62, 36),
        grain=(108, 70, 40), seam=(80, 52, 30),
        wall=(148, 144, 138), wall_dark=(120, 116, 110), motif=(130, 126, 118),
        base=(84, 58, 38), base_hi=(112, 80, 52),
        ceil=(166, 162, 154), ceil_dark=(128, 124, 116), beam=(142, 138, 128),
        sub=(40, 36, 32), sub_hi=(54, 48, 42),
        plat=(104, 70, 42), plat_hi=(130, 92, 56), plat_dark=(76, 50, 30),
    ),
}


def floor_tile(cv: Canvas, ox: int, oy: int, th: dict, variant: int) -> None:
    """16px 木地板：暖棕横纹拼板——4px 高板条、板间深缝、板内水平木纹。"""
    cv.rect(ox, oy, ox + 15, oy + 15, th["floor"])
    for by in range(4):
        y = oy + by * 4
        tone = 1.0 + ((variant + by * 5) % 4 - 1) * 0.055
        cv.rect(ox, y, ox + 15, y + 2, shade(th["floor"], tone))
        cv.rect(ox, y, ox + 15, y, shade(th["floor"], tone * 1.18))    # 板顶高光
        cv.rect(ox, y + 3, ox + 15, y + 3, th["seam"])                 # 板缝
        # 横向木纹短划
        gx = ((variant * 7 + by * 3) % 10)
        cv.rect(ox + gx, y + 1, ox + gx + 4, y + 1, th["grain"])
        cv.rect(ox + ((gx + 8) % 13), y + 2, ox + ((gx + 8) % 13) + 3, y + 2, shade(th["grain"], 0.85))
    # 竖向拼板端缝（每板条错位）
    for by in range(4):
        y = oy + by * 4
        off = (variant * 5 + by * 7) % 16
        cv.rect(ox + off, y, ox + off, y + 2, th["floor_dark"])
    cv.noise(shade(th["floor"], 1.08), 0.05, (ox, oy, ox + 15, oy + 15), 2000 + variant)


def wall_tile(cv: Canvas, ox: int, oy: int, th: dict, variant: int) -> None:
    """16px 室内墙面：灰泥底 + 墙纸图案（竖条纹 / 菱格 / 小碎花）。"""
    cv.rect(ox, oy, ox + 15, oy + 15, th["wall"])
    kind = variant % 4
    if kind == 0:
        # 竖条纹墙纸
        for x in range(1, 16, 4):
            cv.rect(ox + x, oy, ox + x + 1, oy + 15, th["motif"])
            cv.rect(ox + x, oy, ox + x, oy + 15, th["wall_dark"])
    elif kind == 1:
        # 菱格纹
        for y in range(2, 16, 5):
            for x in range(2, 16, 6):
                cx, cy = ox + x + (3 if (y // 5) % 2 else 0), oy + y
                cv.rect(cx, cy, cx + 1, cy + 1, th["wall_dark"])
                cv.rect(cx - 1, cy + 1, cx, cy + 1, th["motif"])
                cv.rect(cx + 2, cy + 1, cx + 3, cy + 1, th["motif"])
    elif kind == 2:
        # 小碎花点
        for y in range(2, 16, 6):
            for x in range(2, 16, 7):
                cx, cy = ox + x + (3 if (y // 6) % 2 else 0), oy + y
                cv.rect(cx - 1, cy, cx + 1, cy, th["motif"])
                cv.rect(cx, cy - 1, cx, cy + 1, th["motif"])
    else:
        # 素灰泥 + 渗渍
        cv.rect(ox + 4 + (variant % 3) * 3, oy, ox + 5 + (variant % 3) * 3, oy + 7, th["wall_dark"])
    cv.noise(th["wall_dark"], 0.045, (ox, oy, ox + 15, oy + 15), 2100 + variant)
    cv.noise(shade(th["wall"], 1.05), 0.03, (ox, oy, ox + 15, oy + 15), 2200 + variant)


def baseboard_tile(cv: Canvas, ox: int, oy: int, th: dict, variant: int) -> None:
    """16px 踢脚线行：上段延续墙纸，下 6px 木踢脚板（亮顶缘 + 落影）。"""
    wall_tile(cv, ox, oy, th, variant)
    cv.rect(ox, oy + 10, ox + 15, oy + 15, th["base"])            # 踢脚板
    cv.rect(ox, oy + 10, ox + 15, oy + 10, th["base_hi"])         # 亮顶缘
    cv.rect(ox, oy + 11, ox + 15, oy + 11, shade(th["base_hi"], 1.15))
    cv.rect(ox, oy + 15, ox + 15, oy + 15, shade(th["base"], 0.7))
    for x in range(2, 16, 7):
        cv.rect(ox + x, oy + 12, ox + x, oy + 14, shade(th["base"], 0.82))  # 板纹


def ceiling_tile(cv: Canvas, ox: int, oy: int, th: dict, variant: int) -> None:
    """16px 天花板：灰泥吊顶 + 顶部落影 + 底缘高光（兼作平台顶面观感）。"""
    cv.rect(ox, oy, ox + 15, oy + 15, th["ceil"])
    cv.rect(ox, oy, ox + 15, oy + 2, th["ceil_dark"])              # 贴顶落影
    cv.rect(ox, oy + 15, ox + 15, oy + 15, shade(th["ceil"], 1.14))
    # 吊顶梁：每 8px 一道
    for x in range(0, 16, 8):
        cv.rect(ox + x + (variant % 3), oy + 4, ox + x + (variant % 3) + 1, oy + 12, th["beam"])
    cv.noise(th["ceil_dark"], 0.07, (ox, oy + 3, ox + 15, oy + 13), 2300 + variant)


def subfloor_tile(cv: Canvas, ox: int, oy: int, th: dict, variant: int) -> None:
    """16px 地板下填充：暗色地基/渣土。"""
    cv.rect(ox, oy, ox + 15, oy + 15, th["sub"])
    cv.noise(th["sub_hi"], 0.10, (ox, oy, ox + 15, oy + 15), 2400 + variant)
    cv.noise(shade(th["sub"], 0.82), 0.07, (ox, oy, ox + 15, oy + 15), 2500 + variant)


def platform_tile(cv: Canvas, ox: int, oy: int, th: dict, variant: int) -> None:
    """16px 平台木缘：木板侧面——顶缘亮面、板身竖纹、底部落影。"""
    cv.rect(ox, oy, ox + 15, oy + 15, th["plat"])
    cv.rect(ox, oy, ox + 15, oy + 2, th["plat_hi"])                # 板顶亮面
    cv.rect(ox, oy, ox + 15, oy, shade(th["plat_hi"], 1.15))
    cv.rect(ox, oy + 3, ox + 15, oy + 3, th["plat_dark"])
    for x in range(1, 16, 5):
        sx = ox + x + (variant % 3)
        cv.rect(sx, oy + 4, sx, oy + 12, shade(th["plat"], 0.78))  # 竖纹
    cv.rect(ox, oy + 14, ox + 15, oy + 15, shade(th["plat_dark"], 0.8))
    cv.noise(shade(th["plat"], 1.08), 0.06, (ox, oy + 4, ox + 15, oy + 13), 2600 + variant)


# ---------------- 家具贴片（32x32 x 5） ----------------

FURN = {
    "table": 0, "shelf": 1, "crate": 2, "mattress": 3, "stairs_down": 4,
}

WOOD = (126, 86, 48)
WOOD_HI = (156, 112, 66)
WOOD_DK = (92, 60, 34)
IRON = (72, 76, 82)
IRON_HI = (104, 110, 116)
SHEET = (206, 196, 176)
SHEET_DK = (172, 160, 140)
BLANKET = (150, 72, 56)


def draw_table(cv: Canvas, ox: int, oy: int) -> None:
    """桌：桌面板 + 四腿（侧视两条）。"""
    cv.rect(ox + 1, oy + 14, ox + 30, oy + 18, WOOD)          # 桌面
    cv.rect(ox + 1, oy + 14, ox + 30, oy + 14, WOOD_HI)
    cv.rect(ox + 1, oy + 18, ox + 30, oy + 18, WOOD_DK)
    cv.rect(ox + 3, oy + 19, ox + 5, oy + 31, WOOD_DK)        # 左腿
    cv.rect(ox + 3, oy + 19, ox + 4, oy + 31, WOOD)
    cv.rect(ox + 26, oy + 19, ox + 28, oy + 31, WOOD_DK)      # 右腿
    cv.rect(ox + 27, oy + 19, ox + 28, oy + 31, shade(WOOD_DK, 0.85))
    cv.rect(ox + 6, oy + 21, ox + 25, oy + 22, shade(WOOD_DK, 0.8))  # 横撑
    cv.rect(ox + 8, oy + 15, ox + 13, oy + 16, shade(WOOD, 1.12))    # 面上木纹


def draw_shelf(cv: Canvas, ox: int, oy: int) -> None:
    """货架：三层木架 + 杂物（箱/罐/瓶）。"""
    cv.rect(ox + 3, oy + 1, ox + 28, oy + 31, WOOD_DK)        # 框架
    cv.rect(ox + 4, oy + 2, ox + 27, oy + 30, shade(WOOD_DK, 0.55))
    for sy in (9, 18, 27):
        cv.rect(ox + 4, oy + sy, ox + 27, oy + sy + 1, WOOD)
        cv.rect(ox + 4, oy + sy, ox + 27, oy + sy, WOOD_HI)
    cv.rect(ox + 3, oy + 1, ox + 4, oy + 31, WOOD)            # 立柱
    cv.rect(ox + 27, oy + 1, ox + 28, oy + 31, WOOD)
    # 层上杂物
    cv.rect(ox + 6, oy + 5, ox + 11, oy + 8, (150, 104, 58))   # 小箱
    cv.rect(ox + 6, oy + 5, ox + 11, oy + 5, (176, 128, 76))
    cv.rect(ox + 14, oy + 4, ox + 16, oy + 8, (110, 140, 96))  # 瓶
    cv.rect(ox + 19, oy + 5, ox + 24, oy + 8, (96, 108, 128))  # 罐
    cv.rect(ox + 7, oy + 14, ox + 11, oy + 17, (140, 96, 60))
    cv.rect(ox + 15, oy + 14, ox + 17, oy + 17, (168, 120, 64))
    cv.rect(ox + 20, oy + 13, ox + 23, oy + 17, (128, 92, 96))
    cv.rect(ox + 6, oy + 23, ox + 12, oy + 26, (104, 84, 60))
    cv.rect(ox + 16, oy + 22, ox + 22, oy + 26, (92, 72, 52))
    cv.rect(ox + 16, oy + 22, ox + 22, oy + 22, (116, 92, 66))


def draw_crate(cv: Canvas, ox: int, oy: int) -> None:
    """木箱：箱体 + 交叉板条 + 铁角。"""
    cv.rect(ox + 3, oy + 8, ox + 28, oy + 31, WOOD)
    cv.rect(ox + 3, oy + 8, ox + 28, oy + 9, WOOD_HI)
    cv.rect(ox + 3, oy + 30, ox + 28, oy + 31, WOOD_DK)
    cv.rect(ox + 3, oy + 8, ox + 4, oy + 31, WOOD_HI)          # 立边
    cv.rect(ox + 27, oy + 8, ox + 28, oy + 31, WOOD_DK)
    # 交叉板条
    for i in range(9):
        cv.rect(ox + 5 + i, oy + 10 + i, ox + 6 + i, oy + 11 + i, shade(WOOD, 1.12))
        cv.rect(ox + 26 - i, oy + 10 + i, ox + 27 - i, oy + 11 + i, shade(WOOD, 0.88))
    # 铁角
    for cx, cy in ((3, 8), (26, 8), (3, 29), (26, 29)):
        cv.rect(ox + cx, oy + cy, ox + cx + 2, oy + cy + 2, IRON)
        cv.rect(ox + cx, oy + cy, ox + cx + 1, oy + cy + 1, IRON_HI)


def draw_mattress(cv: Canvas, ox: int, oy: int) -> None:
    """床垫（矮榻）：毯面 + 枕头 + 床脚。"""
    cv.rect(ox + 1, oy + 20, ox + 30, oy + 29, SHEET)          # 床垫
    cv.rect(ox + 1, oy + 20, ox + 30, oy + 21, shade(SHEET, 1.1))
    cv.rect(ox + 1, oy + 28, ox + 30, oy + 29, SHEET_DK)
    cv.rect(ox + 3, oy + 16, ox + 10, oy + 21, (226, 220, 204))  # 枕头
    cv.rect(ox + 3, oy + 16, ox + 10, oy + 16, (240, 236, 222))
    cv.rect(ox + 12, oy + 17, ox + 29, oy + 20, BLANKET)       # 毯子
    cv.rect(ox + 12, oy + 17, ox + 29, oy + 17, shade(BLANKET, 1.18))
    for i in range(4):
        cv.rect(ox + 14 + i * 4, oy + 18, ox + 14 + i * 4, oy + 19, shade(BLANKET, 0.8))
    cv.rect(ox + 2, oy + 30, ox + 4, oy + 31, WOOD_DK)         # 床脚
    cv.rect(ox + 27, oy + 30, ox + 29, oy + 31, WOOD_DK)


def draw_stairs_down(cv: Canvas, ox: int, oy: int) -> None:
    """下行楼梯贴片：黑洞口 + 逐级下沉的台阶 + 侧缘木框。"""
    cv.rect(ox + 2, oy + 6, ox + 29, oy + 31, (14, 12, 14))    # 洞口
    # 台阶：右高左低，逐级下沉
    for i in range(5):
        sx = ox + 4 + i * 5
        top = oy + 8 + i * 4
        cv.rect(sx, top, sx + 4, oy + 31, (64, 56, 50))
        cv.rect(sx, top, sx + 4, top + 1, (96, 84, 72))        # 阶面亮缘
        cv.rect(sx, top + 2, sx + 4, top + 3, (34, 30, 28))    # 阶下落影
    cv.rect(ox + 1, oy + 5, ox + 30, oy + 5, WOOD_HI)          # 洞口上缘木框
    cv.rect(ox + 1, oy + 5, ox + 1, oy + 31, WOOD)
    cv.rect(ox + 30, oy + 5, ox + 30, oy + 31, WOOD_DK)
    cv.rect(ox + 2, oy + 31, ox + 29, oy + 31, (8, 7, 8))


def make_interior(theme: str) -> None:
    th = THEMES[theme]
    cv = Canvas(256, 96)
    for col in range(16):
        floor_tile(cv, col * 16, 0, th, col)
        wall_tile(cv, col * 16, 16, th, col)
        baseboard_tile(cv, col * 16, 32, th, col)
        ceiling_tile(cv, col * 16, 48, th, col)
        subfloor_tile(cv, col * 16, 64, th, col)
        platform_tile(cv, col * 16, 80, th, col)
    out = os.path.join(ENV, f"interior_{theme}.png")
    cv.save(out)
    print(f"interior_{theme}.png 256x96 ok")


def make_furniture() -> None:
    cv = Canvas(160, 32)
    draw_table(cv, 0, 0)
    draw_shelf(cv, 32, 0)
    draw_crate(cv, 64, 0)
    draw_mattress(cv, 96, 0)
    draw_stairs_down(cv, 128, 0)
    out = os.path.join(ENV, "interior_furniture.png")
    cv.save(out)
    print("interior_furniture.png 160x32 ok")


def main() -> None:
    for theme in THEMES:
        make_interior(theme)
    make_furniture()
    # 预览：五主题室内行 + 家具，供人眼复核
    scale = 2
    items = [(f"interior_{t}", Image.open(os.path.join(ENV, f"interior_{t}.png"))) for t in THEMES]
    items.append(("furniture", Image.open(os.path.join(ENV, "interior_furniture.png"))))
    w = max(im.width for _, im in items) * scale
    h = sum(im.height * scale + 4 for _, im in items)
    sheet = Image.new("RGBA", (w, h), (24, 22, 26, 255))
    y = 0
    for _, im in items:
        sheet.alpha_composite(im.resize((im.width * scale, im.height * scale), Image.NEAREST), (0, y))
        y += im.height * scale + 4
    sheet.save(os.path.join(ROOT, "build", "preview_interior.png"))
    print("build/preview_interior.png ok")


if __name__ == "__main__":
    main()
