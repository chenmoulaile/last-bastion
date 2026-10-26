"""Generate tile atlases, parallax backgrounds, props and the title screen art."""
from __future__ import annotations

import math
import os
import random
import sys

from PIL import Image, ImageDraw, ImageFilter, ImageFont

sys.path.insert(0, os.path.dirname(__file__))
from pixel_art import Canvas, P, shade, mix, save_sheet, contact_sheet, OUT, load_font

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
ENV = os.path.join(ROOT, "assets", "sprites", "environment")
os.makedirs(ENV, exist_ok=True)

THEMES = {
    "suburb": dict(
        sky_top=(33, 39, 47, 255), sky_bot=(126, 91, 66, 255),
        ground=(72, 68, 60, 255), ground_top=(112, 106, 91, 255),
        ground_hi=(140, 132, 113, 255), fill=(57, 55, 51, 255),
        grass=(75, 88, 50, 255), grass_hi=(104, 118, 66, 255),
        brick=(92, 64, 52, 255), brick_hi=(123, 87, 70, 255), mortar=(62, 47, 41, 255),
        concrete=(88, 86, 80, 255), concrete_hi=(112, 109, 100, 255),
        wood=(94, 67, 41, 255), wood_hi=(127, 94, 57, 255),
        metal=(80, 86, 88, 255), metal_hi=(110, 117, 118, 255), rust=(116, 67, 41, 255),
        tile=(84, 91, 85, 255), tile_hi=(116, 122, 112, 255), grout=(51, 56, 53, 255),
        glass=(47, 70, 76, 255), accent=(176, 92, 48, 255), safe=(70, 82, 72, 255),
        hazard=(190, 154, 44, 255), dark=(26, 30, 33, 255),
    ),
    "city": dict(
        sky_top=(22, 28, 39, 255), sky_bot=(62, 71, 85, 255),
        ground=(63, 67, 72, 255), ground_top=(97, 101, 105, 255),
        ground_hi=(127, 130, 132, 255), fill=(48, 52, 57, 255),
        grass=(59, 68, 50, 255), grass_hi=(84, 94, 66, 255),
        brick=(83, 59, 54, 255), brick_hi=(114, 81, 73, 255), mortar=(53, 42, 42, 255),
        concrete=(76, 79, 84, 255), concrete_hi=(103, 106, 110, 255),
        wood=(80, 60, 42, 255), wood_hi=(110, 84, 57, 255),
        metal=(69, 78, 86, 255), metal_hi=(98, 110, 119, 255), rust=(111, 65, 43, 255),
        tile=(70, 80, 84, 255), tile_hi=(102, 113, 116, 255), grout=(43, 49, 52, 255),
        glass=(45, 72, 85, 255), accent=(166, 77, 52, 255), safe=(58, 72, 72, 255),
        hazard=(181, 146, 43, 255), dark=(19, 23, 29, 255),
    ),
    "subway": dict(
        sky_top=(13, 17, 18, 255), sky_bot=(31, 36, 34, 255),
        ground=(53, 52, 47, 255), ground_top=(81, 79, 70, 255),
        ground_hi=(104, 101, 89, 255), fill=(41, 41, 38, 255),
        grass=(45, 53, 42, 255), grass_hi=(66, 76, 58, 255),
        brick=(70, 62, 50, 255), brick_hi=(96, 86, 69, 255), mortar=(45, 40, 34, 255),
        concrete=(67, 69, 64, 255), concrete_hi=(90, 92, 84, 255),
        wood=(73, 57, 39, 255), wood_hi=(100, 79, 53, 255),
        metal=(63, 68, 67, 255), metal_hi=(91, 98, 95, 255), rust=(103, 61, 38, 255),
        tile=(62, 77, 70, 255), tile_hi=(92, 110, 100, 255), grout=(37, 45, 41, 255),
        glass=(35, 55, 57, 255), accent=(157, 92, 45, 255), safe=(56, 69, 60, 255),
        hazard=(173, 141, 44, 255), dark=(11, 14, 15, 255),
    ),
    "military": dict(
        sky_top=(38, 43, 39, 255), sky_bot=(102, 101, 82, 255),
        ground=(66, 68, 57, 255), ground_top=(98, 100, 84, 255),
        ground_hi=(124, 125, 105, 255), fill=(51, 53, 45, 255),
        grass=(69, 76, 51, 255), grass_hi=(95, 103, 69, 255),
        brick=(81, 72, 57, 255), brick_hi=(108, 96, 76, 255), mortar=(54, 48, 39, 255),
        concrete=(80, 81, 70, 255), concrete_hi=(107, 108, 93, 255),
        wood=(83, 67, 45, 255), wood_hi=(112, 91, 60, 255),
        metal=(69, 76, 63, 255), metal_hi=(98, 107, 88, 255), rust=(112, 69, 41, 255),
        tile=(72, 79, 66, 255), tile_hi=(101, 109, 90, 255), grout=(46, 51, 42, 255),
        glass=(48, 66, 58, 255), accent=(165, 101, 47, 255), safe=(63, 75, 62, 255),
        hazard=(184, 150, 45, 255), dark=(22, 25, 21, 255),
    ),
    "bridge": dict(
        sky_top=(24, 31, 43, 255), sky_bot=(86, 75, 72, 255),
        ground=(57, 61, 66, 255), ground_top=(88, 92, 96, 255),
        ground_hi=(117, 120, 122, 255), fill=(44, 48, 53, 255),
        grass=(54, 64, 49, 255), grass_hi=(78, 89, 65, 255),
        brick=(78, 59, 54, 255), brick_hi=(107, 81, 74, 255), mortar=(50, 42, 41, 255),
        concrete=(72, 76, 82, 255), concrete_hi=(99, 104, 110, 255),
        wood=(77, 61, 44, 255), wood_hi=(106, 85, 60, 255),
        metal=(66, 74, 83, 255), metal_hi=(96, 106, 116, 255), rust=(112, 66, 43, 255),
        tile=(67, 76, 81, 255), tile_hi=(98, 108, 113, 255), grout=(41, 47, 51, 255),
        glass=(42, 66, 79, 255), accent=(167, 80, 53, 255), safe=(57, 71, 72, 255),
        hazard=(178, 145, 44, 255), dark=(18, 22, 28, 255),
    ),
}

TILE = 16


def fill_noise(cv, x0, y0, x1, y1, base, hi, lo, seed, density=0.12):
    rnd = random.Random(seed)
    cv.rect(x0, y0, x1, y1, base)
    for y in range(y0, y1 + 1):
        for x in range(x0, x1 + 1):
            r = rnd.random()
            if r < density * 0.5:
                cv.px(x, y, hi)
            elif r < density:
                cv.px(x, y, lo)


def draw_ground_top(cv, ox, oy, th, variant, seed):
    rnd = random.Random(seed)
    base, top, hi = th["ground"], th["ground_top"], th["ground_hi"]
    cv.rect(ox, oy, ox + 15, oy + 15, base)
    cv.rect(ox, oy, ox + 15, oy + 1, hi)
    cv.rect(ox, oy + 2, ox + 15, oy + 3, top)
    cv.rect(ox, oy + 4, ox + 15, oy + 4, shade(top, 0.8))
    for i in range(10):
        x = ox + rnd.randrange(16)
        y = oy + 5 + rnd.randrange(11)
        cv.px(x, y, shade(base, 1.25 if rnd.random() < 0.5 else 0.75))
    if variant % 3 == 1:
        x = ox + rnd.randrange(3, 13)
        cv.line([(x, oy + 5), (x + 2, oy + 8), (x + 1, oy + 12)], shade(base, 0.65))
    if variant % 3 == 2:
        cv.rect(ox + rnd.randrange(2, 10), oy + 7, ox + rnd.randrange(11, 14), oy + 9, shade(base, 0.8))
    if variant >= 4:
        cv.rect(ox, oy + 4, ox + 15, oy + 5, P["blood_dark"])


def draw_ground_fill(cv, ox, oy, th, variant, seed):
    rnd = random.Random(seed)
    fill_noise(cv, ox, oy, ox + 15, oy + 15, th["fill"], shade(th["fill"], 1.18), shade(th["fill"], 0.8), seed)
    if variant % 4 == 0:
        for i in range(3):
            x = ox + rnd.randrange(1, 13)
            y = oy + rnd.randrange(1, 14)
            cv.rect(x, y, x + rnd.randrange(1, 4), y + 1, shade(th["fill"], 0.7))
    if variant % 4 == 2:
        cv.rect(ox, oy + 7, ox + 15, oy + 8, shade(th["fill"], 0.85))


def draw_brick(cv, ox, oy, th, variant, seed):
    base, hi, mortar = th["brick"], th["brick_hi"], th["mortar"]
    cv.rect(ox, oy, ox + 15, oy + 15, base)
    for row in range(4):
        y = oy + row * 4
        cv.rect(ox, y + 3, ox + 15, y + 3, mortar)
        offset = 0 if row % 2 == 0 else 4
        for bx in range(-1, 3):
            x = ox + offset + bx * 8
            cv.rect(x + 7, y, x + 7, y + 2, mortar)
            cv.px(x + 1, y + 1, hi)
    if variant % 3 == 1:
        cv.rect(ox + 4, oy + 5, ox + 7, oy + 6, shade(base, 0.65))
        cv.px(ox + 12, oy + 10, shade(base, 0.6))
    if variant % 3 == 2:
        cv.px(ox + 2, oy + 8, P["blood_dark"])
        cv.px(ox + 3, oy + 8, P["blood"])
        cv.px(ox + 3, oy + 9, P["blood_dark"])


def draw_concrete(cv, ox, oy, th, variant, seed):
    fill_noise(cv, ox, oy, ox + 15, oy + 15, th["concrete"], th["concrete_hi"], shade(th["concrete"], 0.8), seed, 0.16)
    if variant % 3 == 0:
        cv.rect(ox, oy + 7, ox + 15, oy + 7, shade(th["concrete"], 0.85))
    if variant % 3 == 1:
        x = ox + 4
        cv.line([(x, oy + 2), (x + 2, oy + 6), (x, oy + 10), (x + 1, oy + 14)], shade(th["concrete"], 0.65))
    if variant % 3 == 2:
        cv.rect(ox + 9, oy + 3, ox + 12, oy + 4, shade(th["concrete"], 0.72))
        cv.rect(ox + 2, oy + 11, ox + 5, oy + 12, shade(th["concrete"], 1.15))


def draw_wood(cv, ox, oy, th, variant, seed):
    base, hi = th["wood"], th["wood_hi"]
    cv.rect(ox, oy, ox + 15, oy + 15, base)
    for x in range(0, 16, 4):
        cv.rect(ox + x, oy, ox + x, oy + 15, shade(base, 0.65))
        cv.rect(ox + x + 1, oy, ox + x + 1, oy + 15, hi)
    if variant % 2:
        for y in range(2, 16, 7):
            cv.rect(ox + 2, oy + y, ox + 13, oy + y, shade(base, 0.75))
    if variant % 3 == 2:
        cv.px(ox + 7, oy + 6, P["blood_dark"])


def draw_metal(cv, ox, oy, th, variant, seed):
    base, hi = th["metal"], th["metal_hi"]
    cv.rect(ox, oy, ox + 15, oy + 15, base)
    cv.rect(ox, oy, ox + 15, oy + 1, hi)
    cv.rect(ox, oy + 7, ox + 15, oy + 8, shade(base, 0.7))
    for x, y in [(2, 2), (13, 2), (2, 13), (13, 13), (7, 10)]:
        cv.px(ox + x, oy + y, hi if variant % 2 else shade(base, 0.6))
    if variant % 3 == 0:
        cv.rect(ox + 3, oy + 10, ox + 11, oy + 12, th["rust"])
        cv.px(ox + 5, oy + 11, shade(th["rust"], 1.2))
    if variant % 3 == 2:
        cv.line([(ox + 2, oy + 2), (ox + 6, oy + 5), (ox + 4, oy + 9)], shade(base, 0.55))


def draw_tile(cv, ox, oy, th, variant, seed):
    base, hi, grout = th["tile"], th["tile_hi"], th["grout"]
    cv.rect(ox, oy, ox + 15, oy + 15, base)
    for y in range(0, 16, 8):
        for x in range(0, 16, 8):
            cv.rect(ox + x + 1, oy + y + 1, ox + x + 7, oy + y + 7, hi if (x + y) % 16 == 0 else base)
            cv.rect(ox + x, oy + y, ox + x + 7, oy + y, grout)
            cv.rect(ox + x, oy + y, ox + x, oy + y + 7, grout)
    if variant % 2:
        cv.px(ox + 3, oy + 5, shade(base, 0.65))
        cv.px(ox + 12, oy + 12, shade(base, 0.65))


def draw_window(cv, ox, oy, th, variant, seed):
    cv.rect(ox, oy, ox + 15, oy + 15, th["dark"])
    cv.rect(ox + 1, oy + 1, ox + 14, oy + 14, th["glass"])
    cv.rect(ox + 1, oy + 1, ox + 14, oy + 2, shade(th["glass"], 1.3))
    cv.rect(ox + 7, oy, ox + 8, oy + 15, shade(th["metal"], 0.8))
    cv.rect(ox, oy + 7, ox + 15, oy + 8, shade(th["metal"], 0.8))
    cv.rect(ox, oy, ox + 15, oy, th["metal_hi"])
    cv.rect(ox, oy + 15, ox + 15, oy + 15, th["metal"])
    if variant % 2:
        cv.line([(ox + 2, oy + 2), (ox + 5, oy + 6), (ox + 4, oy + 11)], shade(th["glass"], 1.5))
        cv.px(ox + 10, oy + 4, shade(th["glass"], 1.4))
    if variant >= 2:
        cv.rect(ox + 1, oy + 4, ox + 14, oy + 5, th["wood"])
        cv.rect(ox + 1, oy + 11, ox + 14, oy + 12, th["wood"])
        cv.rect(ox + 2, oy + 4, ox + 14, oy + 5, th["wood_hi"])


def draw_platform(cv, ox, oy, th, kind, part, seed):
    if kind == "wood":
        base, hi = th["wood"], th["wood_hi"]
        cv.rect(ox, oy, ox + 15, oy + 5, base)
        cv.rect(ox, oy, ox + 15, oy + 1, hi)
        cv.rect(ox, oy + 5, ox + 15, oy + 6, shade(base, 0.6))
        if part == 0:
            cv.rect(ox + 2, oy + 6, ox + 5, oy + 9, shade(base, 0.7))
        elif part == 2:
            cv.rect(ox + 10, oy + 6, ox + 13, oy + 9, shade(base, 0.7))
        for x in range(1, 16, 5):
            cv.px(ox + x, oy + 3, shade(base, 0.7))
    elif kind == "metal":
        base, hi = th["metal"], th["metal_hi"]
        cv.rect(ox, oy, ox + 15, oy + 4, base)
        cv.rect(ox, oy, ox + 15, oy + 1, hi)
        cv.rect(ox, oy + 4, ox + 15, oy + 5, shade(base, 0.55))
        for x in range(2, 16, 5):
            cv.px(ox + x, oy + 2, hi)
        if part == 1:
            cv.rect(ox + 6, oy + 5, ox + 8, oy + 8, shade(base, 0.6))
    else:
        base, hi = th["concrete"], th["concrete_hi"]
        cv.rect(ox, oy, ox + 15, oy + 5, base)
        cv.rect(ox, oy, ox + 15, oy + 1, hi)
        cv.rect(ox, oy + 5, ox + 15, oy + 6, shade(base, 0.6))
        if part != 1:
            cv.rect(ox + (2 if part == 0 else 11), oy + 5, ox + (4 if part == 0 else 13), oy + 8, shade(base, 0.7))


def draw_stairs(cv, ox, oy, th, variant, seed):
    cv.rect(ox, oy, ox + 15, oy + 15, th["dark"])
    for i in range(4):
        y = oy + 15 - i * 4
        cv.rect(ox + i * 4, y - 4, ox + 15, y - 1, th["concrete"])
        cv.rect(ox + i * 4, y - 4, ox + 15, y - 3, th["concrete_hi"])


def draw_hazard(cv, ox, oy, th, variant, seed):
    cv.rect(ox, oy, ox + 15, oy + 15, (31, 30, 26, 255))
    for i in range(-16, 32, 8):
        cv.poly([(ox + i, oy + 15), (ox + i + 4, oy + 15), (ox + i + 12, oy), (ox + i + 8, oy)], th["hazard"])
    cv.rect(ox, oy, ox + 15, oy, shade(th["hazard"], 0.6))
    cv.rect(ox, oy + 15, ox + 15, oy + 15, shade(th["hazard"], 0.5))


def draw_safe(cv, ox, oy, th, variant, seed):
    fill_noise(cv, ox, oy, ox + 15, oy + 15, th["safe"], shade(th["safe"], 1.2), shade(th["safe"], 0.8), seed)
    cv.rect(ox, oy + 5, ox + 15, oy + 6, (142, 155, 122, 255))
    cv.rect(ox, oy + 7, ox + 15, oy + 7, shade(th["safe"], 0.65))
    if variant % 2:
        cv.rect(ox + 3, oy + 10, ox + 12, oy + 11, shade(th["safe"], 0.8))


def draw_glass(cv, ox, oy, th, variant, seed):
    cv.rect(ox, oy, ox + 15, oy + 15, (0, 0, 0, 0))
    cv.rect(ox, oy, ox + 15, oy + 15, th["glass"])
    cv.rect(ox, oy, ox + 15, oy, shade(th["glass"], 1.5))
    cv.rect(ox, oy, ox, oy + 15, shade(th["glass"], 1.3))
    for i in range(3):
        cv.line([(ox + 3 + i * 4, oy + 2), (ox + 8 + i * 4, oy + 13)], shade(th["glass"], 1.6), 1)
    cv.rect(ox, oy + 7, ox + 15, oy + 8, shade(th["glass"], 0.7))
    cv.rect(ox + 7, oy, ox + 8, oy + 15, shade(th["glass"], 0.7))


def draw_chainlink(cv, ox, oy, th, variant, seed):
    cv.rect(ox, oy, ox + 15, oy + 15, (0, 0, 0, 0))
    c = (96, 100, 98, 210)
    for i in range(0, 20, 4):
        cv.line([(ox + i, oy), (ox + i - 16, oy + 16)], c)
        cv.line([(ox + i, oy + 16), (ox + i - 16, oy)], c)
    cv.rect(ox, oy, ox + 15, oy, shade(c, 1.3))
    cv.rect(ox, oy, ox, oy + 15, shade(c, 1.3))


def draw_vent(cv, ox, oy, th, variant, seed):
    cv.rect(ox, oy, ox + 15, oy + 15, th["metal"])
    for y in range(2, 15, 3):
        cv.rect(ox + 2, oy + y, ox + 13, oy + y, shade(th["metal"], 0.55))
        cv.rect(ox + 2, oy + y + 1, ox + 13, oy + y + 1, th["metal_hi"])
    cv.rect(ox, oy, ox + 15, oy, th["metal_hi"])


def draw_pipe(cv, ox, oy, th, vertical, seed):
    cv.rect(ox, oy, ox + 15, oy + 15, (0, 0, 0, 0))
    if vertical:
        cv.rect(ox + 5, oy, ox + 10, oy + 15, th["metal"])
        cv.rect(ox + 6, oy, ox + 7, oy + 15, th["metal_hi"])
        cv.rect(ox + 4, oy + 2, ox + 11, oy + 4, shade(th["metal"], 0.7))
    else:
        cv.rect(ox, oy + 5, ox + 15, oy + 10, th["metal"])
        cv.rect(ox, oy + 6, ox + 15, oy + 7, th["metal_hi"])
        cv.rect(ox + 2, oy + 4, ox + 4, oy + 11, shade(th["metal"], 0.7))


def draw_blood_wall(cv, ox, oy, th, variant, seed):
    rnd = random.Random(seed)
    cv.rect(ox, oy, ox + 15, oy + 15, (0, 0, 0, 0))
    for i in range(14):
        x = ox + rnd.randrange(16)
        y = oy + rnd.randrange(16)
        cv.px(x, y, P["blood"] if rnd.random() < 0.6 else P["blood_dark"])
    for i in range(5):
        x = ox + rnd.randrange(2, 14)
        cv.line([(x, oy + rnd.randrange(2, 8)), (x + rnd.randrange(-2, 3), oy + rnd.randrange(8, 15))], P["blood"], 1)


def draw_poster(cv, ox, oy, th, variant, seed):
    cv.rect(ox, oy, ox + 15, oy + 15, (0, 0, 0, 0))
    cv.rect(ox + 3, oy + 2, ox + 13, oy + 14, (188, 181, 154, 255))
    cv.rect(ox + 3, oy + 2, ox + 13, oy + 4, (144, 50, 42, 255))
    for y in range(6, 12, 2):
        cv.rect(ox + 5, oy + y, ox + 11, oy + y, (91, 86, 74, 255))
    cv.px(ox + 13, oy + 13, P["blood_dark"])
    cv.rect(ox + 2, oy + 1, ox + 14, oy + 15, (0, 0, 0, 0))


def draw_graffiti(cv, ox, oy, th, variant, seed):
    cv.rect(ox, oy, ox + 15, oy + 15, (0, 0, 0, 0))
    c = (170, 66, 62, 210) if variant % 2 else (83, 137, 140, 210)
    pts = [(ox + 2, oy + 11), (ox + 5, oy + 6), (ox + 8, oy + 10), (ox + 12, oy + 5), (ox + 14, oy + 8)]
    cv.line(pts, c, 2)
    cv.line([(ox + 3, oy + 13), (ox + 12, oy + 12)], c, 1)


def draw_atlas(theme):
    th = THEMES[theme]
    cv = Canvas(256, 128)
    for col in range(16):
        ox, oy = col * 16, 0
        draw_ground_top(cv, ox, oy, th, col, 100 + col)
        draw_ground_fill(cv, ox, 16, th, col, 200 + col)
    for col in range(16):
        ox, oy = col * 16, 32
        if col < 3:
            draw_brick(cv, ox, oy, th, col, 300 + col)
        elif col < 6:
            draw_concrete(cv, ox, oy, th, col, 310 + col)
        elif col < 8:
            draw_wood(cv, ox, oy, th, col, 320 + col)
        elif col < 10:
            draw_metal(cv, ox, oy, th, col, 330 + col)
        elif col < 12:
            draw_tile(cv, ox, oy, th, col, 340 + col)
        elif col == 12:
            draw_safe(cv, ox, oy, th, 1, 350)
        elif col == 13:
            draw_chainlink(cv, ox, oy, th, 0, 351)
        elif col == 14:
            draw_glass(cv, ox, oy, th, 0, 352)
        else:
            draw_hazard(cv, ox, oy, th, 0, 353)
    # windows / doors / details
    for col in range(16):
        ox, oy = col * 16, 48
        if col < 4:
            draw_window(cv, ox, oy, th, col, 400 + col)
        elif col < 7:
            draw_platform(cv, ox, oy, th, "wood", col - 4, 410 + col)
        elif col < 10:
            draw_platform(cv, ox, oy, th, "metal", col - 7, 420 + col)
        elif col < 13:
            draw_platform(cv, ox, oy, th, "concrete", col - 10, 430 + col)
        elif col == 13:
            draw_stairs(cv, ox, oy, th, 0, 440)
        elif col == 14:
            draw_vent(cv, ox, oy, th, 0, 441)
        else:
            draw_hazard(cv, ox, oy, th, 0, 442)
    for col in range(16):
        ox, oy = col * 16, 64
        if col == 0:
            draw_pipe(cv, ox, oy, th, False, 500)
        elif col == 1:
            draw_pipe(cv, ox, oy, th, True, 501)
        elif col == 2:
            draw_blood_wall(cv, ox, oy, th, 0, 502)
        elif col == 3:
            draw_blood_wall(cv, ox, oy, th, 1, 503)
        elif col == 4:
            draw_poster(cv, ox, oy, th, 0, 504)
        elif col == 5:
            draw_graffiti(cv, ox, oy, th, 0, 505)
        elif col == 6:
            draw_graffiti(cv, ox, oy, th, 1, 506)
        elif col == 7:
            draw_window(cv, ox, oy, th, 2, 507)
        elif col == 8:
            draw_chainlink(cv, ox, oy, th, 0, 508)
        elif col == 9:
            draw_stairs(cv, ox, oy, th, 0, 509)
        elif col == 10:
            draw_vent(cv, ox, oy, th, 0, 510)
        elif col == 11:
            draw_pipe(cv, ox, oy, th, False, 511)
        elif col == 12:
            draw_pipe(cv, ox, oy, th, True, 512)
        elif col == 13:
            draw_poster(cv, ox, oy, th, 1, 513)
        elif col == 14:
            draw_graffiti(cv, ox, oy, th, 0, 514)
        else:
            draw_blood_wall(cv, ox, oy, th, 0, 515)
    # bottom rows: decorative backgrounds and solids
    for col in range(16):
        ox, oy = col * 16, 80
        fill_noise(cv, ox, oy, ox + 15, oy + 15, shade(th["dark"], 1.0 + col * 0.02), shade(th["dark"], 1.15), shade(th["dark"], 0.8), 600 + col, 0.1)
    for col in range(16):
        ox, oy = col * 16, 96
        if col < 4:
            draw_platform(cv, ox, oy, th, "concrete", col, 700 + col)
        elif col < 8:
            draw_platform(cv, ox, oy, th, "metal", col - 4, 710 + col)
        elif col < 12:
            draw_platform(cv, ox, oy, th, "wood", col - 8, 720 + col)
        else:
            draw_hazard(cv, ox, oy, th, 0, 730 + col)
    # last row: solid dark / hazard / safe variants
    for col in range(16):
        ox, oy = col * 16, 112
        if col < 4:
            fill_noise(cv, ox, oy, ox + 15, oy + 15, th["dark"], shade(th["dark"], 1.2), shade(th["dark"], 0.8), 800 + col, 0.15)
        elif col < 8:
            draw_safe(cv, ox, oy, th, col, 810 + col)
        elif col < 12:
            draw_tile(cv, ox, oy, th, col, 820 + col)
        else:
            draw_hazard(cv, ox, oy, th, 0, 830 + col)
    cv.save(os.path.join(ENV, f"tiles_{theme}.png"))


# ------------------------------------------------------------------ backgrounds
def sky_layer(theme, w=640, h=360):
    th = THEMES[theme]
    cv = Canvas(w, h)
    for y in range(h):
        t = y / (h - 1)
        c = mix(th["sky_top"], th["sky_bot"], t ** 1.2)
        cv.rect(0, y, w - 1, y, c)
        # subtle dithering
        if y % 4 == 0:
            cv.rect(0, y, w - 1, y, mix(c, (255, 255, 255, 255), 0.02))
    rnd = random.Random(11)
    # moon / sun glow
    if theme in ("suburb", "city", "bridge"):
        mx, my = (500, 74) if theme != "bridge" else (140, 82)
        for r in range(46, 0, -2):
            a = int(10 * (1 - r / 46))
            cv.ellipse(mx, my, r, r, (210, 206, 186, a))
        cv.ellipse(mx, my, 17, 17, (205, 201, 181, 255))
        cv.ellipse(mx - 5, my - 4, 12, 12, (222, 217, 197, 255))
        cv.ellipse(mx + 7, my + 3, 4, 4, (190, 186, 168, 255))
    # clouds
    for i in range(18):
        cx = rnd.randrange(-80, w + 80)
        cy = rnd.randrange(20, 170)
        rx = rnd.randrange(30, 120)
        ry = rnd.randrange(5, 18)
        col = mix(th["sky_top"], th["sky_bot"], rnd.random() * 0.6)
        col = (col[0], col[1], col[2], rnd.randrange(30, 80))
        cv.ellipse(cx, cy, rx, ry, col)
        cv.ellipse(cx + rx // 2, cy + 2, rx // 2, ry, col)
    # smoke plumes / distant fires
    if theme != "subway":
        for i in range(3):
            fx = 70 + i * 230 + rnd.randrange(-30, 30)
            for j in range(18):
                cv.ellipse(fx + int(math.sin(j * 0.7) * 8), 180 - j * 8, 10 + j, 5 + j // 2, (48, 44, 42, 22))
            for j in range(6):
                cv.ellipse(fx + rnd.randrange(-5, 5), 210 - j * 5, 4 + j, 2 + j, (190, 92, 44, 40))
    # rain for some themes
    if theme in ("city", "bridge"):
        for i in range(160):
            x = rnd.randrange(w)
            y = rnd.randrange(h)
            cv.line([(x, y), (x - 1, y + 6)], (160, 172, 180, 34))
    return cv


def far_layer(theme, w=960, h=360):
    th = THEMES[theme]
    cv = Canvas(w, h)
    rnd = random.Random(21)
    base = mix(th["sky_top"], (22, 25, 28, 255), 0.55)
    if theme == "subway":
        cv.rect(0, 0, w - 1, h - 1, (0, 0, 0, 0))
        # tunnel arch / pillars
        for i in range(0, w, 240):
            cv.rect(i, 40, i + 34, h - 30, (22, 26, 25, 255))
            cv.rect(i + 4, 40, i + 8, h - 30, (35, 40, 37, 255))
            cv.ellipse(i + 17, 54, 13, 13, (140, 120, 66, 40))
            cv.ellipse(i + 17, 54, 5, 5, (220, 192, 120, 90))
        for i in range(0, w, 120):
            cv.rect(i, 90, i + 60, 96, (32, 36, 33, 255))
        return cv
    # distant skyline (kept low so the sky and moon stay readable)
    x = -20
    while x < w + 40:
        bw = rnd.randrange(28, 84)
        bh = rnd.randrange(34, 132)
        top = 286 - bh
        col = mix(base, th["sky_bot"], 0.34 + rnd.random() * 0.12)
        cv.rect(x, top, x + bw, 300, col)
        # roof details
        if rnd.random() < 0.35:
            cv.rect(x + bw // 3, top - rnd.randrange(6, 20), x + bw // 3 + 3, top, col)
        if rnd.random() < 0.2:
            cv.rect(x + bw // 2, top - 8, x + bw // 2 + 10, top, shade(col, 0.8))
        # windows
        for wy in range(top + 8, 280, 11):
            for wx in range(x + 5, x + bw - 5, 9):
                if rnd.random() < 0.22:
                    wc = (181, 155, 98, 150) if rnd.random() < 0.7 else (105, 147, 140, 120)
                    cv.px(wx, wy, wc)
        x += bw + rnd.randrange(4, 22)
    # smoke
    for i in range(8):
        sx = rnd.randrange(w)
        for j in range(12):
            cv.ellipse(sx + int(math.sin(j * 0.5) * 6), 250 - j * 10, 12 + j, 6 + j // 2, (34, 33, 32, 18))
    # ground silhouette + atmospheric haze
    cv.rect(0, 286, w - 1, h - 1, (18, 21, 23, 255))
    cv.rect(0, 250, w - 1, 286, (40, 43, 45, 60))
    return cv


def mid_layer(theme, w=960, h=360):
    th = THEMES[theme]
    cv = Canvas(w, h)
    rnd = random.Random(31)
    if theme == "subway":
        cv.rect(0, 0, w - 1, h - 1, (0, 0, 0, 0))
        cv.rect(0, 260, w - 1, h - 1, (26, 29, 27, 255))
        for i in range(0, w, 160):
            cv.rect(i + 20, 80, i + 28, 280, (38, 43, 40, 255))
            cv.rect(i + 21, 80, i + 23, 280, (54, 61, 56, 255))
            cv.ellipse(i + 24, 100, 10, 10, (170, 145, 80, 28))
            cv.ellipse(i + 24, 100, 4, 4, (220, 190, 120, 70))
        # rails
        cv.rect(0, 300, w - 1, 302, (68, 68, 62, 255))
        cv.rect(0, 312, w - 1, 314, (55, 55, 51, 255))
        for i in range(0, w, 26):
            cv.rect(i, 302, i + 4, 312, (44, 44, 41, 255))
        return cv
    base = mix(th["sky_top"], (16, 19, 21, 255), 0.5)
    # buildings closer, with gaps so the parallax reads
    x = -40
    while x < w + 80:
        bw = rnd.randrange(60, 150)
        bh = rnd.randrange(55, 180)
        top = 302 - bh
        col = shade(base, 0.72 + rnd.random() * 0.16)
        cv.rect(x, top, x + bw, 320, col)
        cv.rect(x, top, x + bw, top + 3, shade(col, 1.2))
        # windows
        for wy in range(top + 12, 300, 14):
            for wx in range(x + 8, x + bw - 8, 12):
                if rnd.random() < 0.22:
                    cv.rect(wx, wy, wx + 3, wy + 5, (165, 143, 95, 100))
        # fire escape / sign
        if rnd.random() < 0.4:
            for wy in range(top + 30, 280, 26):
                cv.rect(x + bw - 20, wy, x + bw - 6, wy + 1, (48, 50, 49, 255))
                cv.rect(x + bw - 8, wy, x + bw - 7, wy + 18, (48, 50, 49, 255))
        if rnd.random() < 0.3:
            cv.rect(x + 8, top + 20, x + 30, top + 34, (94, 43, 38, 255))
            cv.rect(x + 10, top + 22, x + 28, top + 32, (132, 66, 52, 255))
        x += bw + rnd.randrange(24, 80)
    # trees / poles in suburb
    if theme == "suburb":
        for i in range(7):
            tx = rnd.randrange(w)
            cv.rect(tx, 190, tx + 3, 310, (42, 37, 32, 255))
            for j in range(5):
                cv.ellipse(tx + rnd.randrange(-14, 14), 175 - j * 8, rnd.randrange(10, 24), rnd.randrange(6, 14), (40, 46, 35, 230))
    # fences / barriers
    cv.rect(0, 316, w - 1, 320, (30, 33, 33, 255))
    for i in range(0, w, 18):
        cv.rect(i, 310, i + 2, 320, (38, 41, 40, 255))
    return cv


def make_backgrounds():
    for theme in THEMES:
        sky_layer(theme).save(os.path.join(ENV, f"bg_{theme}_sky.png"))
        far_layer(theme).save(os.path.join(ENV, f"bg_{theme}_far.png"))
        mid_layer(theme).save(os.path.join(ENV, f"bg_{theme}_mid.png"))
        draw_atlas(theme)


# ------------------------------------------------------------------ props
def prop_door(kind="wood"):
    cv = Canvas(24, 48)
    if kind == "wood":
        base, hi, lo = (103, 74, 44, 255), (140, 105, 64, 255), (66, 47, 30, 255)
    elif kind == "metal":
        base, hi, lo = (74, 83, 91, 255), (109, 119, 127, 255), (45, 51, 57, 255)
    else:
        base, hi, lo = (80, 114, 119, 255), (123, 161, 163, 255), (46, 70, 74, 255)
    cv.rect(1, 1, 22, 47, lo)
    cv.rect(2, 2, 21, 46, base)
    cv.rect(3, 3, 20, 22, hi)
    cv.rect(3, 25, 20, 44, shade(base, 0.92))
    cv.rect(3, 3, 20, 5, shade(hi, 1.1))
    cv.rect(3, 25, 20, 27, shade(hi, 1.1))
    cv.rect(17, 23, 20, 26, (201, 163, 71, 255))
    cv.rect(17, 24, 19, 25, (240, 205, 120, 255))
    cv.rect(1, 1, 22, 1, (31, 28, 25, 255))
    cv.rect(1, 47, 22, 47, (20, 20, 20, 255))
    if kind == "wood":
        cv.line([(6, 6), (6, 20)], lo)
        cv.line([(6, 28), (6, 42)], lo)
        cv.px(10, 12, (57, 39, 25, 255))
    if kind == "metal":
        for y in [6, 13, 31, 40]:
            cv.px(4, y, (159, 168, 174, 255))
            cv.px(19, y, (159, 168, 174, 255))
    if kind == "glass":
        cv.rect(4, 6, 19, 20, (130, 173, 174, 255))
        cv.rect(4, 6, 8, 20, (170, 205, 203, 255))
        cv.line([(5, 7), (18, 19)], (213, 231, 228, 255))
    cv.outline(OUT)
    cv.save(os.path.join(ENV, f"door_{kind}.png"))


def prop_barrel(explosive=False):
    cv = Canvas(16, 24)
    base = (151, 61, 47, 255) if explosive else (73, 88, 92, 255)
    hi = (193, 92, 63, 255) if explosive else (102, 118, 120, 255)
    lo = (92, 37, 31, 255) if explosive else (44, 54, 58, 255)
    cv.rect(2, 2, 13, 23, lo)
    cv.rect(3, 3, 12, 22, base)
    cv.rect(4, 3, 7, 22, hi)
    cv.rect(2, 5, 13, 6, lo)
    cv.rect(2, 18, 13, 19, lo)
    cv.rect(2, 2, 13, 2, hi)
    cv.rect(2, 23, 13, 23, lo)
    if explosive:
        cv.rect(6, 9, 9, 15, (223, 196, 86, 255))
        cv.rect(7, 10, 8, 11, (60, 48, 30, 255))
        cv.rect(7, 13, 8, 14, (60, 48, 30, 255))
        cv.px(11, 8, (223, 196, 86, 255))
    else:
        cv.px(5, 8, (167, 173, 170, 255))
        cv.px(10, 15, (39, 47, 49, 255))
    cv.outline(OUT)
    cv.save(os.path.join(ENV, "barrel_explosive.png" if explosive else "barrel.png"))


def prop_crate():
    cv = Canvas(20, 20)
    base, hi, lo = (111, 82, 48, 255), (148, 113, 68, 255), (69, 50, 31, 255)
    cv.rect(1, 1, 18, 18, lo)
    cv.rect(2, 2, 17, 17, base)
    cv.rect(3, 3, 16, 4, hi)
    cv.rect(3, 3, 4, 16, hi)
    cv.line([(3, 3), (16, 16)], lo, 2)
    cv.line([(16, 3), (3, 16)], lo, 2)
    cv.rect(2, 9, 17, 10, lo)
    cv.px(6, 6, (170, 137, 87, 255))
    cv.outline(OUT)
    cv.save(os.path.join(ENV, "crate.png"))


def prop_car():
    cv = Canvas(80, 36)
    body = (92, 46, 44, 255)
    hi = (130, 70, 62, 255)
    lo = (53, 29, 30, 255)
    glass = (54, 79, 84, 255)
    cv.rect(3, 12, 76, 29, lo)
    cv.rect(5, 10, 74, 27, body)
    cv.rect(7, 11, 72, 14, hi)
    cv.rect(20, 3, 56, 14, body)
    cv.rect(22, 4, 54, 12, glass)
    cv.rect(24, 4, 36, 11, (74, 103, 108, 255))
    cv.rect(39, 4, 52, 11, (43, 64, 69, 255))
    cv.rect(20, 3, 56, 4, hi)
    cv.rect(5, 22, 74, 24, lo)
    cv.rect(8, 27, 16, 30, (28, 29, 29, 255))
    cv.rect(62, 27, 70, 30, (28, 29, 29, 255))
    cv.rect(12, 27, 15, 30, (64, 65, 63, 255))
    cv.rect(66, 27, 69, 30, (64, 65, 63, 255))
    cv.rect(76, 17, 78, 21, (214, 193, 138, 255))
    cv.rect(1, 17, 3, 21, (166, 62, 54, 255))
    cv.rect(7, 15, 13, 16, (51, 35, 31, 255))
    cv.px(30, 8, (120, 151, 154, 255))
    cv.outline(OUT)
    cv.save(os.path.join(ENV, "car.png"))


def prop_dumpster():
    cv = Canvas(40, 28)
    base, hi, lo = (57, 79, 67, 255), (82, 106, 89, 255), (35, 49, 42, 255)
    cv.rect(1, 5, 38, 26, lo)
    cv.rect(2, 6, 37, 25, base)
    cv.rect(3, 6, 36, 8, hi)
    cv.rect(3, 12, 36, 13, lo)
    cv.rect(3, 20, 36, 21, lo)
    cv.rect(6, 0, 34, 5, lo)
    cv.rect(7, 1, 33, 4, base)
    cv.rect(3, 26, 10, 27, (24, 28, 26, 255))
    cv.rect(29, 26, 36, 27, (24, 28, 26, 255))
    cv.outline(OUT)
    cv.save(os.path.join(ENV, "dumpster.png"))


def prop_sandbags():
    cv = Canvas(40, 18)
    for row in range(3):
        for i in range(3 - row % 2):
            x = 2 + i * 13 + (6 if row % 2 else 0)
            y = 12 - row * 5
            cv.ellipse(x + 6, y, 7, 4, (138, 119, 78, 255))
            cv.ellipse(x + 6, y - 1, 5, 3, (167, 148, 101, 255))
            cv.rect(x + 2, y + 2, x + 10, y + 3, (91, 77, 51, 255))
    cv.outline(OUT)
    cv.save(os.path.join(ENV, "sandbags.png"))


def prop_light():
    cv = Canvas(16, 80)
    cv.rect(7, 10, 9, 79, (38, 42, 43, 255))
    cv.rect(7, 10, 8, 79, (62, 68, 68, 255))
    cv.rect(5, 6, 11, 10, (42, 45, 45, 255))
    cv.rect(6, 7, 10, 9, (184, 166, 104, 255))
    cv.ellipse(8, 8, 3, 2, (234, 211, 133, 255))
    cv.rect(3, 79, 12, 80, (31, 34, 34, 255))
    cv.outline(OUT)
    cv.save(os.path.join(ENV, "streetlight.png"))


def prop_sign():
    cv = Canvas(40, 28)
    cv.rect(1, 1, 38, 24, (40, 43, 43, 255))
    cv.rect(2, 2, 37, 23, (184, 171, 126, 255))
    cv.rect(2, 2, 37, 6, (128, 60, 48, 255))
    cv.rect(5, 9, 34, 11, (84, 80, 66, 255))
    cv.rect(5, 14, 27, 16, (84, 80, 66, 255))
    cv.rect(5, 19, 31, 21, (84, 80, 66, 255))
    cv.px(34, 20, P["blood_dark"])
    cv.outline(OUT)
    cv.save(os.path.join(ENV, "sign.png"))


def prop_helicopter():
    cv = Canvas(120, 52)
    body = (66, 78, 71, 255)
    hi = (94, 108, 96, 255)
    lo = (39, 47, 43, 255)
    cv.ellipse(62, 30, 38, 13, lo)
    cv.ellipse(62, 29, 36, 11, body)
    cv.ellipse(62, 27, 33, 8, hi)
    cv.rect(24, 22, 100, 35, body)
    cv.rect(26, 22, 96, 24, hi)
    cv.rect(96, 24, 118, 28, lo)
    cv.rect(110, 18, 114, 26, body)
    cv.rect(28, 35, 36, 42, lo)
    cv.rect(82, 35, 90, 42, lo)
    cv.rect(30, 42, 36, 44, (25, 28, 27, 255))
    cv.rect(82, 42, 88, 44, (25, 28, 27, 255))
    cv.rect(30, 13, 92, 15, lo)
    cv.rect(32, 14, 90, 15, (59, 65, 61, 255))
    cv.rect(58, 4, 60, 14, lo)
    cv.rect(58, 5, 59, 13, (75, 81, 76, 255))
    cv.rect(56, 3, 116, 4, lo)
    cv.rect(58, 4, 114, 4, (82, 89, 83, 255))
    cv.rect(50, 17, 72, 21, (40, 56, 58, 255))
    cv.rect(52, 18, 70, 20, (77, 109, 112, 255))
    cv.rect(34, 27, 40, 30, (186, 58, 47, 255))
    cv.rect(44, 27, 52, 29, (192, 172, 96, 255))
    cv.outline(OUT)
    cv.save(os.path.join(ENV, "helicopter.png"))


def prop_apc():
    cv = Canvas(140, 52)
    body = (67, 76, 57, 255)
    hi = (92, 103, 78, 255)
    lo = (41, 47, 36, 255)
    cv.rect(4, 14, 132, 42, lo)
    cv.rect(6, 12, 130, 40, body)
    cv.rect(8, 12, 128, 16, hi)
    cv.rect(10, 16, 42, 30, (49, 57, 43, 255))
    cv.rect(12, 17, 40, 29, (72, 84, 63, 255))
    cv.rect(46, 18, 126, 34, shade(body, 0.9))
    cv.rect(48, 18, 124, 20, hi)
    cv.rect(50, 22, 60, 26, (43, 52, 40, 255))
    cv.rect(64, 22, 74, 26, (43, 52, 40, 255))
    cv.rect(88, 8, 96, 18, lo)
    cv.rect(94, 4, 122, 8, lo)
    cv.rect(96, 5, 120, 7, (73, 83, 63, 255))
    for x in [22, 44, 96, 118]:
        cv.ellipse(x, 42, 10, 8, (28, 30, 26, 255))
        cv.ellipse(x, 42, 7, 5, (54, 56, 48, 255))
        cv.ellipse(x, 42, 3, 2, (91, 93, 80, 255))
    cv.rect(4, 34, 132, 36, lo)
    cv.rect(112, 10, 116, 14, (196, 62, 48, 255))
    cv.rect(118, 10, 122, 14, (196, 62, 48, 255))
    cv.outline(OUT)
    cv.save(os.path.join(ENV, "apc.png"))


def prop_elevator():
    cv = Canvas(64, 88)
    cv.rect(0, 0, 63, 87, (49, 54, 57, 255))
    cv.rect(3, 3, 60, 84, (69, 76, 79, 255))
    cv.rect(6, 6, 57, 81, (38, 43, 46, 255))
    cv.rect(8, 8, 55, 79, (96, 104, 106, 255))
    cv.rect(10, 10, 53, 77, (71, 79, 82, 255))
    cv.rect(30, 10, 33, 77, (43, 49, 52, 255))
    cv.rect(32, 10, 33, 77, (124, 132, 133, 255))
    cv.rect(14, 20, 46, 22, (55, 62, 64, 255))
    cv.rect(14, 60, 46, 62, (55, 62, 64, 255))
    cv.rect(44, 38, 48, 46, (208, 173, 78, 255))
    cv.rect(18, 4, 46, 8, (29, 32, 33, 255))
    cv.rect(20, 5, 44, 7, (117, 180, 164, 255))
    cv.outline(OUT)
    cv.save(os.path.join(ENV, "elevator.png"))


def prop_generator():
    cv = Canvas(32, 24)
    cv.rect(1, 3, 30, 23, (44, 48, 47, 255))
    cv.rect(2, 4, 29, 22, (78, 85, 78, 255))
    cv.rect(3, 5, 28, 8, (105, 112, 101, 255))
    cv.rect(4, 10, 12, 20, (45, 50, 47, 255))
    cv.rect(15, 10, 27, 20, (58, 64, 59, 255))
    for y in range(11, 20, 3):
        cv.rect(16, y, 26, y + 1, (39, 44, 41, 255))
    cv.rect(6, 12, 10, 18, (188, 163, 66, 255))
    cv.px(8, 14, (240, 218, 123, 255))
    cv.outline(OUT)
    cv.save(os.path.join(ENV, "generator.png"))


def prop_radio():
    cv = Canvas(22, 16)
    cv.rect(1, 4, 20, 15, (44, 50, 47, 255))
    cv.rect(2, 5, 19, 14, (67, 76, 66, 255))
    cv.rect(3, 6, 10, 12, (31, 36, 34, 255))
    cv.rect(4, 7, 9, 11, (84, 142, 118, 255))
    cv.px(14, 8, (190, 165, 77, 255))
    cv.px(16, 8, (190, 165, 77, 255))
    cv.rect(17, 1, 18, 5, (42, 46, 43, 255))
    cv.outline(OUT)
    cv.save(os.path.join(ENV, "radio.png"))


def prop_barbed():
    cv = Canvas(40, 10)
    cv.rect(0, 4, 39, 5, (82, 84, 80, 255))
    for x in range(2, 40, 8):
        cv.line([(x, 0), (x + 3, 9)], (108, 110, 104, 255))
        cv.line([(x, 9), (x + 3, 0)], (108, 110, 104, 255))
        cv.px(x + 1, 4, (150, 150, 142, 255))
    cv.outline(OUT)
    cv.save(os.path.join(ENV, "barbed_wire.png"))


def prop_windowframe():
    cv = Canvas(32, 48)
    cv.rect(0, 0, 31, 47, (57, 62, 63, 255))
    cv.rect(2, 2, 29, 45, (0, 0, 0, 0))
    cv.rect(2, 2, 29, 6, (72, 78, 79, 255))
    cv.rect(2, 41, 29, 45, (72, 78, 79, 255))
    cv.rect(2, 2, 6, 45, (72, 78, 79, 255))
    cv.rect(25, 2, 29, 45, (72, 78, 79, 255))
    cv.rect(14, 2, 17, 45, (64, 70, 71, 255))
    cv.rect(2, 21, 29, 24, (64, 70, 71, 255))
    cv.outline(OUT)
    cv.save(os.path.join(ENV, "window_frame.png"))


def prop_pickups():
    # medkit, ammo, pills, gold with a readable glow
    for name, base, detail in [
        ("pickup_medkit", (202, 206, 197, 255), P["red"]),
        ("pickup_ammo", (83, 91, 55, 255), P["gold"]),
        ("pickup_pills", (197, 126, 52, 255), P["white"]),
        ("pickup_gold", (208, 165, 59, 255), P["fire_white"]),
        ("pickup_grenade", (80, 92, 52, 255), P["steel"]),
        ("pickup_molotov", (96, 129, 91, 255), P["orange_light"]),
        ("pickup_bile", (110, 125, 53, 255), P["acid"]),
    ]:
        cv = Canvas(16, 16)
        cv.ellipse(8, 9, 6, 5, (10, 12, 12, 90))
        if name == "pickup_medkit":
            cv.rect(2, 4, 13, 14, base)
            cv.rect(2, 4, 13, 6, P["white"])
            cv.rect(6, 6, 9, 12, detail)
            cv.rect(4, 8, 11, 10, detail)
            cv.rect(6, 3, 9, 5, P["steel"])
        elif name == "pickup_ammo":
            cv.rect(2, 5, 13, 14, base)
            cv.rect(3, 6, 12, 13, (105, 114, 70, 255))
            for x in [4, 7, 10]:
                cv.rect(x, 7, x + 2, 12, detail)
                cv.px(x, 7, P["fire_white"])
        elif name == "pickup_pills":
            cv.rect(3, 5, 12, 14, base)
            cv.rect(4, 6, 11, 12, P["orange_light"])
            cv.rect(3, 3, 12, 6, P["white"])
            cv.rect(7, 4, 9, 5, detail)
        elif name == "pickup_gold":
            cv.poly([(1, 13), (14, 13), (12, 6), (3, 6)], base)
            cv.rect(3, 6, 12, 8, P["fire_white"])
            cv.rect(5, 9, 7, 10, P["white"])
        elif name == "pickup_grenade":
            cv.ellipse(8, 9, 5, 5, base)
            cv.ellipse(8, 8, 4, 4, (112, 127, 74, 255))
            cv.rect(6, 2, 10, 5, P["steel"])
            cv.rect(9, 3, 11, 4, detail)
        elif name == "pickup_molotov":
            cv.rect(5, 4, 11, 14, (86, 116, 82, 255))
            cv.rect(6, 5, 9, 13, (124, 158, 105, 255))
            cv.rect(6, 1, 9, 4, P["bone"])
            cv.rect(5, 0, 9, 2, detail)
            cv.rect(6, 9, 9, 11, P["orange_light"])
        else:
            cv.rect(4, 4, 11, 14, base)
            cv.rect(5, 5, 10, 13, (139, 155, 64, 255))
            cv.rect(6, 1, 9, 4, P["steel"])
            cv.rect(5, 8, 10, 10, detail)
        cv.outline(OUT)
        cv.save(os.path.join(ENV, f"{name}.png"))


def prop_misc():
    # blood decals
    for i in range(3):
        cv = Canvas(32, 16)
        rnd = random.Random(40 + i)
        for j in range(30):
            x = 4 + rnd.randrange(24)
            y = 7 + rnd.randrange(8)
            cv.ellipse(x, y, rnd.randrange(1, 4), rnd.randrange(1, 3), P["blood_dark"])
        for j in range(20):
            x = 6 + rnd.randrange(20)
            y = 8 + rnd.randrange(6)
            cv.ellipse(x, y, rnd.randrange(1, 3), rnd.randrange(1, 2), P["blood"])
        cv.img.save(os.path.join(ENV, f"blood_decal_{i}.png"))
    # acid pool
    cv = Canvas(48, 16)
    cv.ellipse(24, 9, 21, 6, (85, 103, 35, 255))
    cv.ellipse(24, 8, 18, 4, P["acid"])
    cv.ellipse(24, 7, 13, 3, P["acid_bright"])
    for x in [7, 16, 29, 39]:
        cv.ellipse(x, 10, 4, 2, P["acid"])
        cv.px(x, 5, P["acid_bright"])
    cv.img.save(os.path.join(ENV, "acid_pool.png"))
    # fire zone
    cv = Canvas(32, 24)
    for x in range(2, 31, 6):
        cv.poly([(x, 23), (x + 5, 10), (x + 7, 23)], (176, 62, 32, 220))
        cv.poly([(x + 2, 23), (x + 5, 14), (x + 6, 23)], (236, 138, 42, 230))
        cv.poly([(x + 3, 23), (x + 5, 18), (x + 5, 23)], (255, 226, 128, 240))
    cv.img.save(os.path.join(ENV, "fire_zone.png"))


def make_props():
    prop_door("wood")
    prop_door("metal")
    prop_door("glass")
    prop_barrel(False)
    prop_barrel(True)
    prop_crate()
    prop_car()
    prop_dumpster()
    prop_sandbags()
    prop_light()
    prop_sign()
    prop_helicopter()
    prop_apc()
    prop_elevator()
    prop_generator()
    prop_radio()
    prop_barbed()
    prop_windowframe()
    prop_pickups()
    prop_misc()


# ------------------------------------------------------------------ title art
def title_bg():
    w, h = 640, 360
    cv = Canvas(w, h)
    # burning dusk sky
    for y in range(h):
        t = y / h
        if t < 0.62:
            c = mix((18, 23, 35, 255), (95, 60, 57, 255), (t / 0.62) ** 1.15)
        else:
            c = mix((95, 60, 57, 255), (178, 93, 55, 255), min(1.0, (t - 0.62) / 0.28))
        cv.rect(0, y, w - 1, y, c)
    rnd = random.Random(77)
    # moon + halo
    for r in range(90, 0, -2):
        cv.ellipse(492, 78, r, r, (214, 194, 154, max(1, int(4 * (1 - r / 90)))))
    cv.ellipse(492, 78, 28, 28, (203, 187, 158, 255))
    cv.ellipse(483, 69, 18, 18, (222, 205, 175, 255))
    cv.ellipse(500, 86, 5, 5, (188, 174, 150, 255))
    # ragged clouds
    for i in range(14):
        cx = rnd.randrange(-120, w + 120)
        cy = rnd.randrange(24, 150)
        rx = rnd.randrange(50, 150)
        ry = rnd.randrange(6, 20)
        cv.ellipse(cx, cy, rx, ry, (34, 32, 36, rnd.randrange(30, 70)))
        cv.ellipse(cx + rx // 3, cy + 3, rx // 2, ry, (44, 40, 43, rnd.randrange(20, 45)))
    # distant skyline
    x = -20
    while x < w + 40:
        bw = rnd.randrange(28, 70)
        bh = rnd.randrange(24, 70)
        top = 264 - bh
        col = (53, 47, 47, 255)
        cv.rect(x, top, x + bw, 300, col)
        for wy in range(top + 6, 258, 9):
            for wx in range(x + 4, x + bw - 4, 8):
                if rnd.random() < 0.18:
                    cv.px(wx, wy, (190, 142, 78, 160))
        x += bw + rnd.randrange(4, 20)
    # nearer ruins, leaving the moon clear
    for bx, bw, bh in [(0, 96, 130), (96, 70, 96), (560, 80, 150)]:
        top = 300 - bh
        cv.rect(bx, top, bx + bw, 310, (28, 27, 30, 255))
        cv.rect(bx, top, bx + bw, top + 3, (42, 39, 40, 255))
        for wy in range(top + 12, 290, 13):
            for wx in range(bx + 8, bx + bw - 8, 11):
                if rnd.random() < 0.2:
                    cv.rect(wx, wy, wx + 3, wy + 5, (176, 128, 71, 120))
    # distant Tank silhouette behind the squad
    try:
        from gen_zombies import tank
        tframe = tank("idle", 0, 4).img.resize((176, 176), Image.NEAREST)
        tp = tframe.load()
        tsil = Image.new("RGBA", tframe.size, (0, 0, 0, 0))
        tsp = tsil.load()
        for yy in range(176):
            for xx in range(176):
                if tp[xx, yy][3] > 0:
                    tsp[xx, yy] = (18, 18, 21, 110)
        cv.img.alpha_composite(tsil, (438, 132))
    except Exception:
        pass
    # street + debris
    cv.rect(0, 298, w - 1, h - 1, (31, 30, 31, 255))
    cv.rect(0, 298, w - 1, 301, (53, 48, 45, 255))
    for i in range(80):
        dx = rnd.randrange(w)
        dy = rnd.randrange(305, 356)
        cv.rect(dx, dy, dx + rnd.randrange(2, 12), dy + rnd.randrange(1, 3), (43, 41, 40, 255))
    # burning wreck left
    cv.rect(4, 300, 46, 318, (47, 39, 36, 255))
    cv.rect(8, 304, 42, 312, (78, 44, 37, 255))
    for j in range(8):
        cv.ellipse(20 + rnd.randrange(-3, 4), 300 - j * 3, 6 + j, 2 + j // 2, (222, 106, 43, 70))
    for j in range(10):
        cv.ellipse(24 + int(math.sin(j) * 6), 286 - j * 8, 8 + j, 4 + j // 2, (39, 36, 35, 22))
    # barricade
    cv.rect(0, 326, 196, 332, (55, 48, 41, 255))
    cv.rect(0, 338, 196, 344, (55, 48, 41, 255))
    for x in range(4, 196, 28):
        cv.line([(x, 318), (x + 16, 350)], (68, 59, 49, 255), 3)
    for x in range(10, 190, 34):
        cv.px(x, 326, (168, 145, 94, 255))
    # four survivors (original sprites, silhouette + rim light)
    from gen_characters import STYLES, draw_survivor
    for i, cid in enumerate(["assault", "medic", "heavy", "scout"]):
        frame = draw_survivor(STYLES[cid], "idle", 0, 4).img
        frame = frame.resize((128, 128), Image.NEAREST)
        px = frame.load()
        sil = Image.new("RGBA", frame.size, (0, 0, 0, 0))
        sp = sil.load()
        for yy in range(128):
            for xx in range(128):
                if px[xx, yy][3] > 0:
                    sp[xx, yy] = (12, 13, 16, 255)
        ox = 34 + i * 146
        cv.img.alpha_composite(sil, (ox, 196))
        rim = Image.new("RGBA", frame.size, (0, 0, 0, 0))
        rp = rim.load()
        for yy in range(1, 128):
            for xx in range(127):
                if px[xx, yy][3] > 0 and (px[xx - 1, yy][3] == 0 or px[xx, yy - 1][3] == 0):
                    if xx < 74:
                        rp[xx, yy] = (190, 104, 60, 170)
        cv.img.alpha_composite(rim, (ox, 196))
    # low fog
    for i in range(14):
        cv.ellipse(rnd.randrange(w), 340, rnd.randrange(80, 180), rnd.randrange(5, 14), (90, 78, 68, 18))
    # soft vignette
    vig = Image.new("L", (w, h), 0)
    vp = vig.load()
    cx, cy = w * 0.5, h * 0.45
    maxd = math.sqrt(cx * cx + cy * cy)
    for yy in range(h):
        for xx in range(w):
            d = math.sqrt((xx - cx) ** 2 + (yy - cy) ** 2) / maxd
            vp[xx, yy] = int(max(0.0, (d - 0.62) / 0.38) ** 1.6 * 105)
    black = Image.new("RGBA", (w, h), (6, 7, 9, 255))
    black.putalpha(vig)
    cv.img.alpha_composite(black)
    cv.img.save(os.path.join(ENV, "title_bg.png"))
    # logo
    logo = Canvas(440, 118)
    f1 = load_font(40, True)
    f2 = ImageFont.truetype("C:/Users/chenk/AppData/Local/Temp/opencode/zcool.ttf", 24)
    logo.text((5, 4), "LAST BASTION", f1, (10, 11, 14, 255))
    logo.text((2, 1), "LAST BASTION", f1, (226, 221, 205, 255))
    logo.rect(2, 56, 372, 60, (164, 36, 34, 255))
    logo.rect(2, 60, 318, 62, (94, 21, 23, 255))
    logo.text((5, 63), "最 后 防 线", f2, (206, 186, 146, 255))
    logo.rect(380, 58, 436, 60, (120, 27, 29, 255))
    logo.save(os.path.join(ENV, "logo.png"))
    # icon
    icon = Canvas(128, 128)
    icon.rect(0, 0, 127, 127, (18, 21, 26, 255))
    icon.rect(4, 4, 123, 123, (42, 48, 54, 255))
    icon.rect(8, 8, 119, 119, (22, 26, 31, 255))
    icon.poly([(64, 14), (108, 28), (102, 80), (64, 114), (26, 80), (20, 28)], (188, 175, 148, 255))
    icon.poly([(64, 22), (98, 34), (93, 76), (64, 102), (35, 76), (30, 34)], (38, 43, 49, 255))
    icon.rect(60, 38, 68, 86, (184, 45, 41, 255))
    icon.rect(44, 52, 84, 60, (184, 45, 41, 255))
    icon.rect(60, 38, 64, 86, (224, 92, 73, 255))
    icon.rect(44, 52, 84, 56, (224, 92, 73, 255))
    icon.outline(OUT)
    icon.img.save(os.path.join(ENV, "icon_128.png"))
    icon.img.resize((64, 64), Image.NEAREST).save(os.path.join(ROOT, "icon.png"))


def make_all():
    make_backgrounds()
    make_props()
    title_bg()
    # contact sheet of props
    items = []
    for f in ["door_wood", "door_metal", "barrel", "barrel_explosive", "crate", "car", "dumpster", "sandbags", "streetlight", "sign", "helicopter", "apc", "elevator", "generator", "radio", "barbed_wire", "window_frame", "pickup_medkit", "pickup_ammo", "pickup_pills", "pickup_gold", "acid_pool", "fire_zone"]:
        p = os.path.join(ENV, f + ".png")
        if os.path.exists(p):
            items.append((f, Image.open(p)))
    contact_sheet(items, os.path.join(ROOT, "build", "preview_props.png"), scale=3, cols=5)
    # background preview
    for theme in THEMES:
        bg = Image.new("RGBA", (640, 360), (0, 0, 0, 255))
        for layer, alpha in [("sky", 255), ("far", 255), ("mid", 255)]:
            im = Image.open(os.path.join(ENV, f"bg_{theme}_{layer}.png")).convert("RGBA")
            if alpha < 255:
                a = im.getchannel("A").point(lambda v: v * alpha // 255)
                im.putalpha(a)
            if layer == "sky":
                bg.alpha_composite(im.crop((0, 0, 640, 360)))
            else:
                bg.alpha_composite(im.crop((0, 0, 640, 360)))
        bg.save(os.path.join(ROOT, "build", f"preview_bg_{theme}.png"))


if __name__ == "__main__":
    make_all()
    print("environment generated")
