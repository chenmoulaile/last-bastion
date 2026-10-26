"""Generate combat FX, screen overlays and UI icons."""
from __future__ import annotations

import math
import os
import random
import sys

from PIL import Image, ImageDraw, ImageFont

sys.path.insert(0, os.path.dirname(__file__))
from pixel_art import Canvas, P, shade, mix, save_sheet, contact_sheet, OUT, load_font

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
FX = os.path.join(ROOT, "assets", "sprites", "fx")
UI = os.path.join(ROOT, "assets", "sprites", "ui")
os.makedirs(FX, exist_ok=True)
os.makedirs(UI, exist_ok=True)


def blood_burst(frame, n=6):
    cv = Canvas(32, 32)
    rnd = random.Random(900 + frame)
    t = frame / (n - 1)
    for i in range(22):
        ang = rnd.random() * math.tau
        dist = (2 + rnd.random() * 12) * (0.35 + t * 1.4)
        x = 16 + math.cos(ang) * dist
        y = 16 + math.sin(ang) * dist * 0.8
        r = max(1, int(3 * (1 - t) + 1))
        col = P["blood_bright"] if i % 3 == 0 else P["blood"]
        cv.ellipse(int(x), int(y), r, r, (col[0], col[1], col[2], int(230 * (1 - t * 0.7))))
    if frame < 3:
        cv.ellipse(16, 16, 5 - frame, 4 - frame, P["blood_dark"])
    return cv


def muzzle_flash(frame):
    cv = Canvas(16, 12)
    cx, cy = 3, 6
    if frame == 0:
        cv.poly([(cx, cy - 2), (cx + 5, cy - 4), (cx + 4, cy - 1), (cx + 10, cy), (cx + 4, cy + 1), (cx + 5, cy + 4), (cx, cy + 2)], (255, 244, 190, 255))
        cv.poly([(cx, cy - 1), (cx + 5, cy - 2), (cx + 4, cy), (cx + 8, cy), (cx + 4, cy + 1), (cx + 5, cy + 2), (cx, cy + 1)], P["fire"])
        cv.px(cx + 2, cy, P["white"])
    else:
        cv.poly([(cx, cy - 1), (cx + 3, cy - 2), (cx + 3, cy), (cx + 6, cy), (cx + 3, cy + 1), (cx + 3, cy + 2), (cx, cy + 1)], (255, 198, 64, 200))
    return cv


def tracer():
    cv = Canvas(16, 3)
    cv.rect(0, 1, 15, 1, (255, 238, 170, 220))
    cv.rect(0, 0, 15, 0, (255, 210, 100, 110))
    cv.rect(0, 2, 15, 2, (255, 210, 100, 110))
    cv.rect(12, 0, 15, 2, (255, 250, 220, 255))
    return cv


def shell():
    cv = Canvas(5, 4)
    cv.rect(1, 0, 3, 3, (190, 152, 67, 255))
    cv.rect(1, 0, 3, 1, (238, 208, 120, 255))
    cv.rect(0, 2, 4, 3, (137, 105, 46, 255))
    cv.outline(OUT)
    return cv


def explosion(frame, n=6):
    cv = Canvas(64, 64)
    t = frame / (n - 1)
    cx, cy = 32, 34
    if frame == 0:
        cv.ellipse(cx, cy, 8, 7, (255, 248, 200, 255))
        cv.ellipse(cx, cy, 5, 4, P["white"])
    else:
        r = int(10 + t * 26)
        cv.ellipse(cx, cy, r, int(r * 0.8), (255, 150, 50, int(220 * (1 - t * 0.6))))
        cv.ellipse(cx, cy, int(r * 0.75), int(r * 0.6), (255, 214, 95, int(240 * (1 - t * 0.5))))
        cv.ellipse(cx, cy, int(r * 0.45), int(r * 0.35), (255, 248, 210, int(255 * (1 - t * 0.7))))
        for i in range(14):
            rnd = random.Random(700 + frame * 20 + i)
            ang = rnd.random() * math.tau
            dist = r * (0.7 + rnd.random() * 0.9)
            x = cx + math.cos(ang) * dist
            y = cy + math.sin(ang) * dist * 0.7
            rr = max(1, int(4 * (1 - t)))
            cv.ellipse(int(x), int(y), rr, rr, (80 + int(60 * (1 - t)), 70, 60, int(200 * (1 - t))))
    return cv


def smoke(frame, n=6):
    cv = Canvas(48, 48)
    rnd = random.Random(1200)
    t = frame / (n - 1)
    for i in range(9):
        x = 24 + rnd.randrange(-10, 10)
        y = 30 - int(t * 14) + rnd.randrange(-6, 6)
        r = int(5 + t * 12 + rnd.randrange(0, 5))
        cv.ellipse(x, y, r, r, (88, 91, 88, int(90 * (1 - t))))
    return cv


def spark(frame, n=3):
    cv = Canvas(12, 12)
    rnd = random.Random(1300 + frame)
    for i in range(10):
        ang = rnd.random() * math.tau
        dist = rnd.random() * (3 + frame * 3)
        x = 6 + math.cos(ang) * dist
        y = 6 + math.sin(ang) * dist
        cv.px(int(x), int(y), P["fire_white"] if i % 2 else P["fire"])
    return cv


def fire_frame(frame, n=6):
    cv = Canvas(32, 32)
    rnd = random.Random(1500)
    for i in range(7):
        x = 3 + i * 4 + rnd.randrange(-1, 2)
        h = 10 + rnd.randrange(0, 12)
        sway = math.sin((frame / n) * math.tau + i) * 2
        cv.poly([(x - 2, 31), (x + sway, 31 - h), (x + 3, 31)], (172, 55, 30, 220))
        cv.poly([(x - 1, 31), (x + sway + 1, 31 - h + 4), (x + 2, 31)], (236, 131, 42, 230))
        cv.poly([(x, 31), (x + sway + 1, 31 - h + 9), (x + 2, 31)], (255, 224, 116, 240))
    cv.rect(0, 30, 31, 31, (91, 40, 26, 180))
    return cv


def acid_splash(frame, n=4):
    cv = Canvas(32, 24)
    rnd = random.Random(1600 + frame)
    t = frame / (n - 1)
    cv.ellipse(16, 20, int(6 + t * 10), int(2 + t * 3), (126, 148, 44, 200))
    for i in range(12):
        x = 16 + rnd.randrange(-12, 13)
        y = 12 - int(t * 8) + rnd.randrange(-4, 5)
        cv.ellipse(x, y, 1 + (i % 2), 1, P["acid_bright"] if i % 2 else P["acid"])
    return cv


def bile_splash(frame, n=4):
    cv = Canvas(32, 24)
    rnd = random.Random(1700 + frame)
    t = frame / (n - 1)
    cv.ellipse(16, 18, int(7 + t * 11), int(3 + t * 4), (127, 143, 39, 210))
    for i in range(14):
        x = 16 + rnd.randrange(-13, 14)
        y = 11 - int(t * 7) + rnd.randrange(-4, 5)
        cv.ellipse(x, y, 1 + (i % 3), 1 + (i % 2), P["bile_light"] if i % 2 else P["bile"])
    return cv


def make_fx():
    save_sheet([blood_burst(i) for i in range(6)], os.path.join(FX, "blood_burst.png"))
    save_sheet([muzzle_flash(i) for i in range(2)], os.path.join(FX, "muzzle_flash.png"))
    tracer().save(os.path.join(FX, "tracer.png"))
    shell().save(os.path.join(FX, "shell.png"))
    save_sheet([explosion(i) for i in range(6)], os.path.join(FX, "explosion.png"))
    save_sheet([smoke(i) for i in range(6)], os.path.join(FX, "smoke.png"))
    save_sheet([spark(i) for i in range(3)], os.path.join(FX, "spark.png"))
    save_sheet([fire_frame(i) for i in range(6)], os.path.join(FX, "fire.png"))
    save_sheet([acid_splash(i) for i in range(4)], os.path.join(FX, "acid_splash.png"))
    save_sheet([bile_splash(i) for i in range(4)], os.path.join(FX, "bile_splash.png"))
    # rain drop
    cv = Canvas(3, 10)
    cv.line([(2, 0), (0, 9)], (150, 170, 182, 120))
    cv.px(1, 5, (190, 208, 218, 160))
    cv.save(os.path.join(FX, "rain_drop.png"))


def make_overlays():
    w, h = 640, 360
    # vignette
    cv = Canvas(w, h)
    for y in range(h):
        for x in range(w):
            dx = (x - w / 2) / (w / 2)
            dy = (y - h / 2) / (h / 2)
            d = min(1.0, math.sqrt(dx * dx + dy * dy) / 1.35)
            a = int(max(0.0, (d - 0.35) / 0.65) ** 1.7 * 170)
            cv.px(x, y, (5, 6, 8, a))
    cv.save(os.path.join(UI, "vignette.png"))
    # red low-health vignette
    cv = Canvas(w, h)
    for y in range(h):
        for x in range(w):
            dx = (x - w / 2) / (w / 2)
            dy = (y - h / 2) / (h / 2)
            d = min(1.0, math.sqrt(dx * dx + dy * dy) / 1.25)
            a = int(max(0.0, (d - 0.25) / 0.75) ** 2 * 210)
            cv.px(x, y, (130, 14, 18, a))
    cv.save(os.path.join(UI, "lowhp.png"))
    # bile splatter overlay
    cv = Canvas(w, h)
    rnd = random.Random(2100)
    for i in range(34):
        x = rnd.randrange(w)
        y = rnd.randrange(h)
        r = rnd.randrange(8, 48)
        cv.ellipse(x, y, r, r, (110, 126, 34, rnd.randrange(30, 90)))
    for i in range(16):
        x = rnd.randrange(w)
        y = rnd.randrange(h)
        cv.ellipse(x, y, rnd.randrange(3, 12), rnd.randrange(2, 8), (154, 171, 48, 140))
    cv.save(os.path.join(UI, "bile_overlay.png"))
    # rain overlay (tileable horizontally)
    cv = Canvas(w, h)
    rnd = random.Random(2200)
    for i in range(220):
        x = rnd.randrange(w)
        y = rnd.randrange(h)
        ln = rnd.randrange(4, 14)
        cv.line([(x, y), (x - 2, y + ln)], (158, 176, 188, rnd.randrange(24, 70)))
    cv.save(os.path.join(UI, "rain.png"))
    # grain
    cv = Canvas(128, 128)
    rnd = random.Random(2300)
    for y in range(128):
        for x in range(128):
            if rnd.random() < 0.18:
                cv.px(x, y, (200, 200, 190, rnd.randrange(8, 26)))
    cv.save(os.path.join(UI, "grain.png"))
    # hitmarker
    cv = Canvas(16, 16)
    c = (238, 236, 226, 235)
    for pts in [[(4, 4), (7, 7)], [(11, 4), (8, 7)], [(4, 11), (7, 8)], [(11, 11), (8, 8)]]:
        cv.line(pts, c, 1)
    cv.px(8, 8, (255, 90, 70, 255))
    cv.save(os.path.join(UI, "hitmarker.png"))


# ---------------------------------------------------------------- UI icons
def make_skill_icons():
    def base():
        cv = Canvas(24, 24, (24, 28, 34, 255))
        cv.rect(0, 0, 23, 23, (41, 47, 55, 255), fill=False)
        cv.rect(1, 1, 22, 22, (29, 34, 41, 255), fill=False)
        return cv

    # assault - speed boot + bolt
    cv = base()
    cv.poly([(4, 14), (12, 10), (12, 14), (17, 12), (14, 20), (9, 18), (5, 19)], P["olive_light"])
    cv.line([(2, 9), (7, 9)], P["gold"])
    cv.line([(1, 12), (5, 12)], P["gold"])
    cv.poly([(15, 4), (12, 9), (15, 9), (13, 13), (19, 7), (16, 7)], P["fire"])
    cv.outline(OUT)
    cv.save(os.path.join(UI, "skill_assault.png"))
    # medic - cross
    cv = base()
    cv.ellipse(12, 12, 9, 9, (60, 69, 72, 255))
    cv.ellipse(12, 12, 8, 8, (198, 204, 196, 255))
    cv.rect(10, 5, 13, 19, P["red"])
    cv.rect(5, 10, 19, 13, P["red"])
    cv.rect(10, 5, 11, 19, P["red_hot"])
    cv.rect(5, 10, 19, 11, P["red_hot"])
    cv.outline(OUT)
    cv.save(os.path.join(UI, "skill_medic.png"))
    # heavy - shield
    cv = base()
    cv.poly([(12, 3), (20, 6), (19, 14), (12, 21), (5, 14), (4, 6)], (116, 127, 138, 255))
    cv.poly([(12, 5), (18, 7), (17, 13), (12, 18), (7, 13), (6, 7)], (62, 73, 83, 255))
    cv.rect(11, 8, 12, 15, P["gold"])
    cv.rect(8, 11, 16, 12, P["gold"])
    cv.outline(OUT)
    cv.save(os.path.join(UI, "skill_heavy.png"))
    # scout - roll
    cv = base()
    cv.ellipse(12, 12, 8, 8, (55, 62, 69, 255), fill=False)
    cv.ellipse(12, 12, 8, 8, (55, 62, 69, 255), fill=False)
    cv.line([(7, 15), (12, 10), (17, 15)], P["cyan_light"], 2)
    cv.line([(7, 11), (12, 6), (17, 11)], P["cyan_light"], 2)
    cv.ellipse(12, 18, 3, 2, P["cyan"])
    cv.outline(OUT)
    cv.save(os.path.join(UI, "skill_scout.png"))
    # ninja - kunai
    cv = base()
    cv.poly([(6, 20), (15, 4), (19, 6), (10, 21)], (191, 198, 202, 255))
    cv.poly([(8, 18), (15, 7), (17, 8), (11, 19)], (234, 238, 236, 255))
    cv.rect(4, 18, 9, 21, (57, 38, 31, 255))
    cv.line([(2, 22), (7, 17)], P["blood"], 2)
    cv.outline(OUT)
    cv.save(os.path.join(UI, "skill_ninja.png"))
    # officer - star/banner
    cv = base()
    cv.poly([(4, 4), (20, 4), (18, 20), (12, 17), (6, 20)], (63, 78, 92, 255))
    cv.poly([(12, 6), (14, 11), (19, 11), (15, 14), (16, 19), (12, 16), (8, 19), (9, 14), (5, 11), (10, 11)], P["gold"])
    cv.outline(OUT)
    cv.save(os.path.join(UI, "skill_officer.png"))
    # class icons
    cv = base()
    cv.rect(6, 8, 17, 15, (91, 102, 76, 255))
    cv.ellipse(12, 8, 6, 5, (113, 124, 95, 255))
    cv.rect(5, 12, 18, 14, (60, 68, 52, 255))
    cv.px(12, 11, P["gold"])
    cv.outline(OUT)
    cv.save(os.path.join(UI, "class_rifleman.png"))
    cv = base()
    cv.rect(3, 10, 20, 13, (55, 62, 63, 255))
    cv.rect(5, 7, 16, 11, (88, 98, 96, 255))
    cv.rect(9, 13, 12, 19, (48, 53, 55, 255))
    cv.rect(14, 13, 18, 15, P["gold"])
    cv.outline(OUT)
    cv.save(os.path.join(UI, "class_gunner.png"))
    cv = base()
    cv.ellipse(12, 12, 8, 8, (194, 201, 191, 255))
    cv.rect(10, 6, 13, 18, P["red"])
    cv.rect(6, 10, 18, 13, P["red"])
    cv.outline(OUT)
    cv.save(os.path.join(UI, "class_medic.png"))
    cv = base()
    cv.ellipse(12, 14, 6, 7, (76, 89, 59, 255))
    cv.rect(10, 4, 14, 8, (103, 118, 82, 255))
    cv.rect(12, 2, 16, 5, P["steel"])
    cv.rect(14, 3, 17, 4, P["ash"])
    cv.outline(OUT)
    cv.save(os.path.join(UI, "class_demolisher.png"))
    # command icons
    for name, draw in [
        ("cmd_follow", lambda cv: (cv.line([(5, 6), (10, 12), (5, 18)], P["cyan_light"], 2), cv.line([(11, 6), (16, 12), (11, 18)], P["cyan_light"], 2), cv.line([(17, 6), (22, 12), (17, 18)], P["cyan"], 2))),
        ("cmd_advance", lambda cv: (cv.line([(4, 12), (19, 12)], P["gold"], 3), cv.poly([(15, 5), (23, 12), (15, 19)], P["gold"]))),
        ("cmd_hold", lambda cv: (cv.poly([(12, 3), (20, 6), (19, 14), (12, 21), (5, 14), (4, 6)], P["gold"]), cv.rect(11, 8, 12, 16, (32, 36, 38, 255)), cv.rect(8, 11, 16, 12, (32, 36, 38, 255)))),
        ("cmd_focus", lambda cv: (cv.ellipse(12, 12, 8, 8, P["red"], False), cv.ellipse(12, 12, 2, 2, P["red"]), cv.line([(12, 1), (12, 6)], P["red"], 2), cv.line([(12, 18), (12, 23)], P["red"], 2), cv.line([(1, 12), (6, 12)], P["red"], 2), cv.line([(18, 12), (23, 12)], P["red"], 2))),
    ]:
        cv = base()
        draw(cv)
        cv.outline(OUT)
        cv.save(os.path.join(UI, f"{name}.png"))
    # status icons
    cv = base()
    cv.rect(5, 8, 19, 12, P["red"])
    cv.rect(8, 4, 16, 9, P["blood"])
    cv.rect(9, 9, 12, 17, P["red_hot"])
    cv.outline(OUT)
    cv.save(os.path.join(UI, "status_pin.png"))
    cv = base()
    cv.ellipse(12, 8, 4, 4, P["bone"])
    cv.rect(8, 12, 16, 18, P["bone"])
    cv.rect(8, 18, 16, 21, P["blood"])
    cv.outline(OUT)
    cv.save(os.path.join(UI, "status_down.png"))
    cv = base()
    cv.ellipse(12, 12, 8, 8, (50, 50, 50, 255))
    cv.poly([(12, 4), (20, 12), (12, 20)], (185, 185, 178, 255))
    cv.outline(OUT)
    cv.save(os.path.join(UI, "status_bw.png"))
    # crosshair / threat arrow / misc
    cv = Canvas(20, 20)
    c = (232, 230, 218, 230)
    cv.rect(9, 2, 10, 6, c)
    cv.rect(9, 14, 10, 18, c)
    cv.rect(2, 9, 6, 10, c)
    cv.rect(14, 9, 18, 10, c)
    cv.px(9, 9, c)
    cv.save(os.path.join(UI, "crosshair.png"))
    cv = Canvas(14, 14)
    cv.poly([(7, 1), (13, 12), (7, 9), (1, 12)], P["red"])
    cv.outline(OUT)
    cv.save(os.path.join(UI, "threat_arrow.png"))
    # skull / horde
    cv = Canvas(20, 20)
    cv.ellipse(10, 8, 7, 6, P["bone"])
    cv.rect(7, 12, 13, 16, P["bone"])
    cv.rect(7, 7, 9, 9, P["ink"])
    cv.rect(12, 7, 14, 9, P["ink"])
    cv.rect(9, 13, 10, 15, P["ink"])
    cv.rect(11, 13, 12, 15, P["ink"])
    cv.outline(OUT)
    cv.save(os.path.join(UI, "icon_horde.png"))
    cv = Canvas(20, 20)
    cv.poly([(3, 16), (5, 7), (10, 4), (15, 7), (17, 16)], P["skin_dark"])
    cv.rect(5, 8, 16, 14, P["skin"])
    cv.rect(7, 7, 14, 11, P["skin_light"])
    cv.outline(OUT)
    cv.save(os.path.join(UI, "icon_tank.png"))
    cv = Canvas(20, 20)
    cv.ellipse(10, 10, 8, 8, (52, 55, 52, 255))
    cv.ellipse(10, 10, 6, 6, P["skin_pale"])
    cv.rect(8, 7, 10, 10, P["ink"])
    cv.px(9, 10, P["red_hot"])
    cv.line([(9, 12), (9, 16)], P["blood"], 1)
    cv.outline(OUT)
    cv.save(os.path.join(UI, "icon_witch.png"))
    cv = Canvas(20, 20)
    cv.ellipse(10, 10, 8, 8, (60, 76, 50, 255), False)
    for ang in [0, 120, 240]:
        a = math.radians(ang)
        cv.ellipse(int(10 + math.cos(a) * 4), int(10 + math.sin(a) * 4), 3, 3, P["acid"])
    cv.save(os.path.join(UI, "icon_special.png"))
    # rank stamps
    f = ImageFont.truetype("C:/Users/chenk/AppData/Local/Temp/opencode/silkscreen_bold.ttf", 44)
    for letter, col in [("S", (235, 198, 90, 255)), ("A", (196, 201, 197, 255)), ("B", (180, 143, 101, 255)), ("C", (135, 139, 140, 255)), ("D", (118, 112, 102, 255)), ("F", (150, 63, 58, 255))]:
        cv = Canvas(64, 64)
        cv.ellipse(32, 32, 29, 29, (24, 26, 29, 210))
        cv.ellipse(32, 32, 27, 27, (48, 49, 47, 255), False)
        cv.ellipse(32, 32, 24, 24, col, False)
        cv.text((32 - 13, 8), letter, f, col)
        cv.ellipse(32, 32, 29, 29, (24, 26, 29, 0))
        cv.save(os.path.join(UI, f"rank_{letter}.png"))
    # chapter cards
    ENV = os.path.join(ROOT, "assets", "sprites", "environment")
    chapters = [
        ("ch1", "第一章", "郊区突围", "suburb", (183, 95, 54, 255)),
        ("ch2", "第二章", "城市废墟", "city", (77, 120, 139, 255)),
        ("ch3", "第三章", "军事基地", "military", (123, 135, 85, 255)),
        ("ch4", "第四章", "最后防线", "bridge", (160, 64, 56, 255)),
    ]
    f_cn = ImageFont.truetype("C:/Users/chenk/AppData/Local/Temp/opencode/zcool.ttf", 30)
    f_small = ImageFont.truetype("C:/Users/chenk/AppData/Local/Temp/opencode/zcool.ttf", 16)
    f_num = ImageFont.truetype("C:/Users/chenk/AppData/Local/Temp/opencode/silkscreen_bold.ttf", 18)
    for cid, num, name, theme, accent in chapters:
        bg = Canvas(320, 180)
        for layer in ["sky", "far", "mid"]:
            im = Image.open(os.path.join(ENV, f"bg_{theme}_{layer}.png")).convert("RGBA")
            bg.img.alpha_composite(im.crop((0, 0, 320, 180)))
        # dark gradient at the bottom for text
        for y in range(80, 180):
            a = int((y - 80) / 100 * 170)
            bg.rect(0, y, 319, y, (10, 12, 14, a))
        bg.rect(0, 0, 319, 179, (10, 12, 14, 0), False)
        bg.rect(0, 0, 319, 0, accent)
        bg.rect(0, 179, 319, 179, accent)
        bg.text((14, 18), cid.upper().replace("CH", "CHAPTER "), f_num, accent)
        bg.text((14, 112), name, f_cn, (230, 224, 208, 255))
        bg.text((15, 148), num, f_small, (170, 166, 152, 255))
        bg.rect(14, 144, 84, 146, accent)
        bg.save(os.path.join(UI, f"{cid}.png"))


# ---------------------------------------------------------------- achievements
ACHIEVEMENTS = [
    ("first_blood", "skull", (190, 70, 60, 255)),
    ("door", "door", (172, 120, 70, 255)),
    ("witch", "candle", (215, 170, 78, 255)),
    ("tank", "fist", (150, 110, 80, 255)),
    ("combo", "bolt", (220, 180, 70, 255)),
    ("arsenal", "ammo", (160, 150, 110, 255)),
    ("commander", "star", (200, 170, 80, 255)),
    ("medic", "cross", (210, 210, 200, 255)),
    ("expert", "skull", (180, 70, 70, 255)),
    ("squad", "helmets", (150, 160, 120, 255)),
    ("stealth", "eye", (120, 170, 160, 255)),
    ("no_downs", "shield", (160, 175, 185, 255)),
    ("codex", "book", (150, 130, 90, 255)),
    ("scavenger", "pack", (170, 140, 80, 255)),
    ("no_one_left", "people", (190, 170, 120, 255)),
    ("fire", "flame", (210, 110, 60, 255)),
    ("barrel", "barrel", (180, 100, 70, 255)),
    ("hunter", "claw", (150, 120, 140, 255)),
    ("s_rank", "letter_s", (235, 198, 90, 255)),
    ("last_stand", "flag", (200, 80, 70, 255)),
]


def ach_icon(symbol, col):
    cv = Canvas(24, 24)
    # medal ribbon
    cv.poly([(4, 2), (9, 2), (12, 10), (8, 10)], (110, 52, 48, 255))
    cv.poly([(15, 2), (20, 2), (16, 10), (12, 10)], (74, 66, 58, 255))
    cv.ellipse(12, 14, 9, 9, (34, 37, 40, 255))
    cv.ellipse(12, 14, 8, 8, (82, 86, 82, 255))
    cv.ellipse(12, 14, 7, 7, (48, 52, 52, 255))
    c = col
    if symbol == "skull":
        cv.ellipse(12, 12, 4, 4, P["bone"])
        cv.rect(10, 14, 14, 18, P["bone"])
        cv.px(10, 12, P["ink"]); cv.px(14, 12, P["ink"])
        cv.px(11, 16, P["ink"]); cv.px(13, 16, P["ink"])
    elif symbol == "door":
        cv.rect(8, 7, 16, 21, c)
        cv.rect(9, 8, 15, 20, shade(c, 0.6))
        cv.px(14, 14, P["gold"])
    elif symbol == "candle":
        cv.rect(11, 9, 13, 20, (198, 188, 160, 255))
        cv.poly([(12, 4), (15, 9), (12, 12), (9, 9)], P["fire"])
        cv.px(12, 8, P["fire_white"])
    elif symbol == "fist":
        cv.ellipse(12, 14, 6, 5, P["skin"])
        cv.rect(7, 10, 17, 15, P["skin_light"])
        cv.rect(8, 9, 11, 12, P["skin"])
        cv.rect(11, 9, 14, 12, P["skin"])
        cv.rect(14, 10, 17, 13, P["skin_dark"])
    elif symbol == "bolt":
        cv.poly([(14, 5), (8, 13), (12, 13), (10, 20), (17, 11), (13, 11)], c)
    elif symbol == "ammo":
        cv.rect(6, 9, 18, 20, (74, 83, 52, 255))
        for x in [8, 11, 14, 17]:
            cv.rect(x, 10, x + 1, 16, P["gold"])
    elif symbol == "star":
        pts = []
        for i in range(10):
            ang = -math.pi / 2 + i * math.pi / 5
            r = 7 if i % 2 == 0 else 3
            pts.append((12 + math.cos(ang) * r, 13 + math.sin(ang) * r))
        cv.poly(pts, c)
    elif symbol == "cross":
        cv.rect(10, 7, 13, 21, c)
        cv.rect(6, 11, 18, 14, c)
    elif symbol == "helmets":
        for x in [7, 12, 17]:
            cv.ellipse(x, 12, 3, 2, (90, 104, 78, 255))
            cv.rect(x - 3, 12, x + 3, 15, (70, 82, 62, 255))
    elif symbol == "eye":
        cv.ellipse(12, 13, 8, 5, (196, 196, 180, 255))
        cv.ellipse(12, 13, 3, 3, c)
        cv.px(12, 13, P["ink"])
    elif symbol == "shield":
        cv.poly([(12, 5), (19, 8), (18, 16), (12, 21), (6, 16), (5, 8)], c)
        cv.poly([(12, 7), (17, 9), (16, 15), (12, 19), (8, 15), (7, 9)], shade(c, 0.5))
    elif symbol == "book":
        cv.rect(6, 7, 18, 19, c)
        cv.rect(7, 8, 17, 18, shade(c, 0.55))
        cv.rect(11, 8, 13, 18, shade(c, 0.3))
    elif symbol == "pack":
        cv.rect(7, 7, 17, 19, c)
        cv.rect(8, 6, 16, 9, shade(c, 1.2))
        cv.rect(9, 11, 15, 17, shade(c, 0.6))
        cv.rect(10, 12, 14, 13, P["gold"])
    elif symbol == "people":
        for x in [7, 12, 17]:
            cv.ellipse(x, 9, 2, 2, P["bone"])
            cv.rect(x - 2, 11, x + 2, 18, c)
    elif symbol == "flame":
        cv.poly([(12, 4), (17, 11), (15, 17), (12, 20), (9, 17), (7, 11)], c)
        cv.poly([(12, 9), (14, 13), (12, 17), (10, 13)], P["fire_white"])
    elif symbol == "barrel":
        cv.rect(8, 6, 16, 20, c)
        cv.rect(8, 8, 16, 9, shade(c, 0.6))
        cv.rect(8, 15, 16, 16, shade(c, 0.6))
        cv.rect(11, 10, 13, 14, P["gold"])
    elif symbol == "claw":
        for i in range(3):
            cv.line([(7 + i * 4, 6), (6 + i * 4, 20)], c, 2)
        cv.line([(6, 20), (18, 20)], shade(c, 0.6), 1)
    elif symbol == "letter_s":
        f = ImageFont.truetype("C:/Users/chenk/AppData/Local/Temp/opencode/silkscreen_bold.ttf", 16)
        cv.text((6, 6), "S", f, c)
    elif symbol == "flag":
        cv.rect(7, 5, 8, 21, (150, 145, 130, 255))
        cv.poly([(9, 6), (20, 9), (16, 12), (20, 15), (9, 15)], c)
    cv.outline(OUT)
    return cv


def make_achievements():
    for aid, sym, col in ACHIEVEMENTS:
        ach_icon(sym, col).save(os.path.join(UI, f"ach_{aid}.png"))
    contact_sheet([(aid, Image.open(os.path.join(UI, f"ach_{aid}.png"))) for aid, _, _ in ACHIEVEMENTS], os.path.join(ROOT, "build", "preview_achievements.png"), scale=3, cols=5)


if __name__ == "__main__":
    make_fx()
    make_overlays()
    make_skill_icons()
    make_achievements()
    print("fx + ui generated")
