"""Generate original infected sprites inspired by the L4D2 infected archetypes.

Silhouette language (hooded hunter, bloated boomer, giant-armed charger, long
necked spitter, tiny jockey, hulking tank, crying witch) is used as reference;
all pixels are original.
"""
from __future__ import annotations

import math
import os
import sys

from PIL import Image

sys.path.insert(0, os.path.dirname(__file__))
from pixel_art import Canvas, P, shade, mix, save_sheet, contact_sheet, OUT

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
ZDIR = os.path.join(ROOT, "assets", "sprites", "zombies")
os.makedirs(ZDIR, exist_ok=True)

SKINS = [
    (126, 139, 99, 255),
    (146, 137, 105, 255),
    (110, 126, 96, 255),
    (157, 146, 119, 255),
]
SHIRTS = [
    (72, 80, 82, 255),
    (104, 82, 60, 255),
    (72, 62, 72, 255),
    (86, 92, 68, 255),
]
PANTS = [(57, 61, 65, 255), (66, 57, 47, 255), (48, 54, 63, 255)]
HAIRS = [(42, 36, 31, 255), (61, 45, 31, 255), (30, 30, 32, 255), (84, 60, 36, 255)]


def limb(cv, x0, y0, x1, y1, c, width=2):
    cv.line([(x0, y0), (x1, y1)], c, width)
    cv.px(x0, y0, c)
    cv.px(x1, y1, c)


def common_head(cv, cx, top, skin, hair, variant, hurt=False):
    cv.rect(cx - 2, top + 7, cx + 1, top + 9, shade(skin, 0.8))
    cv.ellipse(cx, top + 4, 4, 4, skin)
    cv.rect(cx - 3, top + 5, cx + 3, top + 8, skin)
    cv.rect(cx - 4, top + 1, cx - 2, top + 6, hair)
    cv.rect(cx - 3, top, cx + 2, top + 2, hair)
    # sunken eye + blood
    cv.rect(cx + 1, top + 4, cx + 2, top + 5, (23, 20, 21, 255))
    cv.px(cx + 2, top + 4, P["blood_bright"] if hurt else (120, 32, 30, 255))
    cv.px(cx + 4, top + 6, shade(skin, 0.8))
    cv.px(cx + 3, top + 7, P["blood_dark"])
    cv.rect(cx + 2, top + 8, cx + 3, top + 8, P["blood"])
    cv.px(cx + 1, top + 9, shade(skin, 0.7))
    # wounds
    cv.px(cx - 1, top + 3, shade(skin, 0.65))
    cv.px(cx + 1, top + 2, P["blood_dark"])
    if variant % 3 == 0:
        cv.rect(cx - 3, top + 8, cx + 3, top + 10, hair)  # beard
    if variant % 4 == 1:
        cv.rect(cx - 5, top + 3, cx - 3, top + 9, hair)  # longer hair


def common_body(v, mode, frame, n, x=0, y=0, scale=1.0):
    """Draw one common infected into a 24x32 canvas (or 28x36 for outfits)."""
    skin = SKINS[v % len(SKINS)]
    shirt = SHIRTS[v % len(SHIRTS)]
    pants = PANTS[v % len(PANTS)]
    hair = HAIRS[v % len(HAIRS)]
    cv = Canvas(24, 32)
    bob = 0
    if mode == "idle":
        bob = 1 if frame in (2, 3) else 0
    if mode == "run":
        bob = 0 if frame % 3 else 1
    hurt = mode == "hurt"
    crouch = 0
    # shadow
    cv.shadow(4, 29, 21, 30, 90)
    # back leg
    if mode == "die":
        return common_death(cv, v, skin, shirt, pants, hair, frame)
    if mode == "attack":
        bob = 0
    if mode in ("run", "walk"):
        swing = math.sin(frame / n * math.tau)
        fx = 14 + int(round(swing * 4))
        bx = 9 - int(round(swing * 3))
        fy = 28 - int(round(max(0, math.sin(frame / n * math.tau + 0.5)) * 3))
        by = 29 - int(round(max(0, math.sin(frame / n * math.tau + math.pi)) * 3))
        limb(cv, 10, 22 + bob, bx, by - 2, shade(pants, 0.7), 3)
        cv.rect(bx - 2, by, bx + 2, by + 2, shade(P["brown_dark"], 0.8))
        limb(cv, 14, 22 + bob, fx, fy - 2, pants, 3)
        cv.rect(fx - 2, fy, fx + 2, fy + 2, P["brown_dark"])
    elif mode == "crouch":
        cv.rect(7, 23, 12, 27, pants)
        cv.rect(13, 23, 18, 27, shade(pants, 0.85))
        cv.rect(6, 26, 13, 28, P["brown_dark"])
        cv.rect(13, 26, 20, 28, P["brown_dark"])
        crouch = 3
    else:
        cv.rect(8, 22 + bob, 11, 29, shade(pants, 0.75))
        cv.rect(13, 22 + bob, 16, 29, pants)
        cv.rect(7, 28, 12, 30, P["brown_dark"])
        cv.rect(13, 28, 18, 30, shade(P["brown_dark"], 0.8))
    # torso
    ty = 12 + bob + crouch
    cv.poly([(7, ty), (17, ty), (18, ty + 8), (16, ty + 11), (8, ty + 11), (6, ty + 8)], shirt)
    cv.rect(8, ty, 10, ty + 9, shade(shirt, 1.25))
    cv.rect(15, ty + 2, 17, ty + 9, shade(shirt, 0.7))
    # torn shirt / exposed flesh
    cv.rect(11, ty + 5, 15, ty + 8, skin)
    cv.px(12, ty + 6, P["blood_dark"])
    cv.px(13, ty + 7, P["blood"])
    cv.rect(8, ty + 9, 16, ty + 10, shade(pants, 0.6))
    # arms reaching forward
    if mode == "attack":
        cv.rect(14, ty + 1, 22, ty + 3, shirt)
        cv.rect(20, ty + 2, 23, ty + 4, skin)
        cv.rect(13, ty + 4, 21, ty + 6, shirt)
        cv.rect(20, ty + 5, 23, ty + 7, skin)
        cv.px(23, ty + 3, P["blood_bright"])
    elif mode == "run":
        swing = math.sin(frame / n * math.tau)
        limb(cv, 7, ty + 2, 5, ty + 7 + int(swing * 2), shirt, 2)
        limb(cv, 17, ty + 2, 20, ty + 6 + int(swing * 2), shirt, 2)
        cv.rect(19, ty + 6 + int(swing * 2), 21, ty + 8 + int(swing * 2), skin)
    else:
        limb(cv, 7, ty + 2, 5, ty + 7, shirt, 2)
        limb(cv, 17, ty + 2, 20, ty + 5, shirt, 2)
        cv.rect(19, ty + 5, 21, ty + 7, skin)
        cv.px(21, ty + 6, P["blood"])
        limb(cv, 8, ty + 2, 6, ty + 8, shirt, 2)
        cv.rect(5, ty + 7, 7, ty + 9, skin)
    # head
    common_head(cv, 12, 3 + bob + crouch, skin, hair, v, hurt)
    # accessories
    draw_uncommon_accessory(cv, v, ty, bob + crouch, mode)
    # grime
    for x, y in [(9, ty + 3), (14, ty + 4), (11, 27), (16, 18)]:
        if cv.get(x, y)[3]:
            cv.px(x, y, shade(cv.get(x, y), 0.7))
    cv.outline(OUT)
    return cv


def draw_uncommon_accessory(cv, v, ty, off, mode):
    kind = (["common"] * 4 + ["riot", "hazmat", "mud", "hardhat", "clown", "scavenger"])[v]
    if kind == "riot":
        # helmet + visor + ballistic vest + shield on the front arm
        cv.rect(8, 2 + off, 16, 4 + off, (38, 48, 60, 255))
        cv.rect(8, 4 + off, 16, 6 + off, (26, 33, 42, 255))
        cv.rect(9, 5 + off, 15, 6 + off, (54, 78, 92, 255))
        cv.rect(7, ty + 1, 18, ty + 8, (40, 49, 59, 255))
        cv.rect(8, ty + 2, 10, ty + 7, (61, 72, 84, 255))
        cv.rect(11, ty + 2, 17, ty + 4, (28, 34, 42, 255))
        # shield
        cv.rect(17, ty + 3, 21, ty + 12, (48, 58, 70, 255))
        cv.rect(17, ty + 3, 18, ty + 12, (83, 94, 105, 255))
        cv.rect(18, ty + 6, 20, ty + 7, (28, 34, 40, 255))
    elif kind == "hazmat":
        # full yellow suit, hood and gas mask
        cv.rect(6, ty - 1, 19, ty + 11, (158, 142, 52, 255))
        cv.rect(7, ty, 10, ty + 10, (191, 173, 70, 255))
        cv.rect(14, ty + 1, 18, ty + 10, (115, 101, 35, 255))
        cv.rect(8, 1 + off, 16, 8 + off, (158, 142, 52, 255))
        cv.rect(9, 2 + off, 15, 4 + off, (191, 173, 70, 255))
        cv.rect(10, 5 + off, 15, 7 + off, (43, 51, 42, 255))
        cv.rect(11, 5 + off, 14, 6 + off, (122, 178, 157, 255))
        cv.rect(10, 8 + off, 14, 9 + off, (78, 86, 48, 255))
        cv.rect(15, ty + 4, 18, ty + 5, (54, 58, 32, 255))
    elif kind == "mud":
        cv.rect(6, ty, 19, ty + 11, (73, 57, 40, 255))
        cv.rect(7, ty, 10, ty + 10, (92, 73, 49, 255))
        cv.rect(9, 2 + off, 17, 8 + off, (76, 60, 41, 255))
        cv.rect(10, 4 + off, 15, 6 + off, (54, 42, 31, 255))
        cv.px(12, 5 + off, P["acid"])
        for x, y in [(7, ty + 8), (18, ty + 9), (10, ty + 11), (15, ty + 6)]:
            cv.rect(x, y, x + 1, y + 2, (60, 47, 33, 255))
    elif kind == "hardhat":
        cv.rect(8, 1 + off, 16, 4 + off, (207, 162, 44, 255))
        cv.rect(9, 1 + off, 15, 2 + off, (238, 200, 87, 255))
        cv.rect(7, 3 + off, 17, 4 + off, (151, 112, 29, 255))
        cv.rect(7, ty + 1, 18, ty + 9, (193, 102, 35, 255))
        cv.rect(8, ty + 2, 10, ty + 8, (222, 133, 53, 255))
        cv.rect(12, ty + 2, 17, ty + 3, (221, 218, 190, 255))
        cv.rect(12, ty + 5, 17, ty + 6, (221, 218, 190, 255))
    elif kind == "clown":
        # white face paint, red nose, green hair, striped shirt
        cv.rect(9, 3 + off, 16, 9 + off, (214, 205, 188, 255))
        cv.rect(9, 4 + off, 10, 8 + off, (235, 228, 210, 255))
        cv.px(14, 6 + off, P["red"])
        cv.px(11, 5 + off, P["ink"])
        cv.px(14, 5 + off, P["ink"])
        cv.rect(8, 2 + off, 10, 4 + off, (74, 148, 88, 255))
        cv.rect(15, 1 + off, 18, 4 + off, (147, 61, 136, 255))
        cv.rect(9, 9 + off, 15, 10 + off, P["red"])
        cv.rect(7, ty, 18, ty + 11, (178, 51, 52, 255))
        for yy in range(ty, ty + 11, 3):
            cv.rect(7, yy, 18, yy + 1, (221, 211, 190, 255))
        cv.rect(6, 27, 13, 29, (147, 46, 50, 255))
        cv.rect(13, 27, 20, 29, (147, 46, 50, 255))
        cv.rect(4, 29, 8, 30, (35, 31, 34, 255))
        cv.rect(17, 29, 21, 30, (35, 31, 34, 255))
    elif kind == "scavenger":
        # survivor-looking: backpack, beanie, blue jacket
        cv.rect(4, ty + 1, 7, ty + 9, (58, 72, 55, 255))
        cv.rect(4, ty + 1, 5, ty + 9, (82, 99, 72, 255))
        cv.rect(5, ty + 3, 7, ty + 4, (122, 97, 51, 255))
        cv.rect(7, ty, 18, ty + 11, (51, 74, 92, 255))
        cv.rect(8, ty, 10, ty + 10, (72, 101, 122, 255))
        cv.rect(8, 1 + off, 16, 3 + off, (63, 65, 58, 255))
        cv.rect(7, 3 + off, 17, 4 + off, (47, 49, 43, 255))
        cv.rect(8, ty + 9, 17, ty + 10, (94, 73, 42, 255))


def common_death(cv, v, skin, shirt, pants, hair, frame):
    if frame == 0:
        cv.rect(7, 16, 17, 26, shirt)
        cv.rect(8, 24, 12, 29, pants)
        cv.rect(13, 24, 17, 29, pants)
        common_head(cv, 12, 8, skin, hair, v, True)
    else:
        y = 25 + min(3, frame - 1)
        cv.rect(4, y, 20, y + 4, shirt)
        cv.rect(4, y, 20, y + 1, shade(shirt, 1.2))
        cv.rect(18, y - 2, 22, y + 2, skin)
        cv.rect(17, y - 3, 20, y - 1, hair)
        cv.rect(4, y + 3, 12, y + 5, pants)
        cv.rect(2, y + 4, 5, y + 6, P["brown_dark"])
        if frame >= 3:
            cv.rect(2, y + 5, 23, y + 6, P["blood_dark"])
            cv.rect(6, y + 6, 20, y + 7, P["blood"])
            cv.px(9, y + 4, P["blood_bright"])
    cv.outline(OUT)
    return cv


COMMON_VARIANTS = ["common_a", "common_b", "common_c", "common_d", "riot", "hazmat", "mud", "hardhat", "clown", "scavenger"]


def gen_common():
    preview = []
    for v, name in enumerate(COMMON_VARIANTS):
        for anim, n in [("idle", 4), ("run", 6), ("attack", 4), ("hurt", 2), ("die", 6)]:
            frames = [common_body(v, anim, i, n) for i in range(n)]
            save_sheet(frames, os.path.join(ZDIR, f"{name}_{anim}.png"))
        preview.append((name, common_body(v, "idle", 0, 4).img))
        preview.append((name + "_run", common_body(v, "run", 1, 6).img))
    contact_sheet(preview, os.path.join(ROOT, "build", "preview_commons.png"), scale=4, cols=6)


# ------------------------------------------------------------ special: hunter
def hunter(mode, frame, n):
    cv = Canvas(32, 32)
    cv.shadow(5, 29, 27, 30, 90)
    grey = (74, 79, 85, 255)
    grey_hi = (103, 108, 112, 255)
    grey_lo = (47, 51, 57, 255)
    skin = (129, 143, 121, 255)
    mask = (196, 193, 170, 255)
    crouch = 5
    bob = 1 if mode == "idle" and frame in (1, 3) else 0
    if mode == "pounce":
        # airborne, stretched horizontally
        cv.rect(6, 15, 20, 22, grey)
        cv.rect(6, 15, 19, 17, grey_hi)
        cv.rect(19, 12, 27, 20, skin)
        cv.rect(21, 12, 26, 14, grey)
        cv.rect(23, 15, 26, 16, P["ink"])
        cv.rect(24, 17, 26, 18, P["blood_dark"])
        limb(cv, 18, 19, 26, 24, grey_lo, 2)
        limb(cv, 8, 21, 3, 26, grey, 3)
        limb(cv, 12, 22, 8, 29, grey, 3)
        limb(cv, 6, 17, 2, 14, grey_lo, 2)
        cv.rect(1, 13, 4, 15, skin)
        cv.rect(2, 12, 4, 13, P["bone"])
        cv.outline(OUT)
        return cv
    # crouched body
    y = 18 + bob
    # legs
    limb(cv, 12, y + 3, 8, 28, grey_lo, 3)
    limb(cv, 17, y + 3, 21, 27, grey, 3)
    cv.rect(6, 27, 11, 29, P["ink"])
    cv.rect(20, 26, 25, 29, P["ink"])
    # torso hunched
    cv.poly([(9, y - 2), (21, y - 2), (23, y + 5), (19, y + 8), (9, y + 8), (7, y + 4)], grey)
    cv.rect(10, y - 2, 13, y + 6, grey_hi)
    cv.rect(19, y, 22, y + 6, grey_lo)
    cv.rect(12, y + 5, 19, y + 7, shade(grey, 0.65))
    # hood + head
    cv.ellipse(16, y - 5, 5, 5, grey)
    cv.rect(12, y - 7, 20, y - 3, grey)
    cv.rect(13, y - 8, 19, y - 5, grey_hi)
    cv.rect(16, y - 7, 21, y - 1, mask)
    cv.rect(18, y - 6, 20, y - 5, P["ink"])
    cv.rect(18, y - 3, 21, y - 2, P["ink"])
    cv.rect(19, y - 1, 21, y, P["blood_dark"])
    # claws
    limb(cv, 20, y + 1, 27, y + 2, grey, 2)
    cv.rect(26, y + 1, 29, y + 3, skin)
    cv.px(29, y, P["bone"])
    cv.px(29, y + 2, P["bone"])
    limb(cv, 9, y + 2, 5, y + 7, grey_lo, 2)
    cv.rect(3, y + 6, 6, y + 8, skin)
    # attack flash
    if mode == "attack":
        cv.rect(25, y - 1, 30, y + 4, P["blood_bright"])
    cv.outline(OUT)
    return cv


def hunter_death(frame):
    cv = Canvas(32, 32)
    y = 23 + min(3, frame)
    cv.rect(5, y, 23, y + 4, (74, 79, 85, 255))
    cv.rect(5, y, 23, y + 1, (103, 108, 112, 255))
    cv.rect(21, y - 3, 27, y + 1, (196, 193, 170, 255))
    cv.rect(23, y - 2, 25, y - 1, P["ink"])
    cv.rect(5, y + 3, 14, y + 5, (47, 51, 57, 255))
    if frame >= 3:
        cv.rect(2, y + 5, 29, y + 6, P["blood_dark"])
        cv.rect(8, y + 6, 25, y + 7, P["blood"])
    cv.outline(OUT)
    return cv


# ------------------------------------------------------------ special: smoker
def smoker(mode, frame, n):
    cv = Canvas(32, 40)
    cv.shadow(4, 37, 27, 38, 90)
    skin = (150, 154, 89, 255)
    skin_hi = (183, 185, 112, 255)
    skin_lo = (102, 108, 57, 255)
    rag = (82, 75, 55, 255)
    bob = 1 if mode in ("idle", "attack") and frame % 2 else 0
    if mode == "die":
        y = 30 + min(3, frame)
        cv.rect(3, y, 27, y + 5, skin)
        cv.rect(3, y, 27, y + 1, skin_hi)
        cv.rect(24, y - 3, 29, y + 2, skin)
        cv.rect(4, y + 4, 18, y + 6, rag)
        if frame >= 3:
            cv.rect(1, y + 6, 30, y + 7, P["blood_dark"])
            cv.rect(6, y + 7, 26, y + 8, (94, 108, 45, 255))
        cv.outline(OUT)
        return cv
    # thin legs
    limb(cv, 11, 29, 8, 37, rag, 3)
    limb(cv, 17, 29, 21, 37, shade(rag, 0.8), 3)
    cv.rect(5, 36, 11, 38, P["brown_dark"])
    cv.rect(19, 36, 25, 38, P["brown_dark"])
    # distended torso
    y = 13 + bob
    cv.ellipse(15, y + 9, 8, 9, skin)
    cv.ellipse(15, y + 9, 6, 8, skin_hi)
    cv.rect(9, y + 1, 21, y + 8, rag)
    cv.rect(10, y + 2, 13, y + 6, shade(rag, 1.2))
    cv.rect(11, y + 8, 20, y + 10, skin_lo)
    cv.rect(13, y + 12, 19, y + 14, P["bile"])
    cv.px(12, y + 10, P["bile_light"])
    # ribs / boils
    for x, yy in [(10, y + 6), (20, y + 7), (14, y + 13), (18, y + 4)]:
        cv.px(x, yy, P["blood_dark"])
    # long arms
    limb(cv, 8, y + 3, 3, y + 12, skin_lo, 3)
    cv.rect(1, y + 11, 5, y + 14, skin)
    limb(cv, 22, y + 3, 27, y + 10, skin, 3)
    cv.rect(26, y + 9, 30, y + 12, skin_hi)
    # head (small, thrust forward)
    cv.rect(13, y - 7, 18, y + 2, skin)
    cv.ellipse(16, y - 5, 4, 4, skin)
    cv.rect(14, y - 8, 19, y - 5, skin_lo)
    cv.px(18, y - 6, (38, 31, 22, 255))
    cv.px(18, y - 5, P["bile"])
    # mouth open
    if mode in ("attack", "idle"):
        cv.rect(17, y - 2, 21, y + 1, (46, 29, 30, 255))
        cv.rect(18, y - 1, 21, y, (109, 47, 51, 255))
        cv.rect(19, y, 22, y + 2, (134, 76, 78, 255))
        if mode == "attack":
            cv.rect(21, y, 26, y + 1, (145, 89, 90, 255))
    # cough puff
    if mode == "attack":
        for x, yy in [(27, y - 6), (29, y - 3), (24, y - 8)]:
            cv.px(x, yy, (141, 151, 111, 160))
    cv.outline(OUT)
    return cv


# ------------------------------------------------------------ special: boomer
def boomer(mode, frame, n):
    cv = Canvas(36, 36)
    cv.shadow(3, 33, 33, 34, 100)
    skin = (156, 161, 132, 255)
    skin_hi = (192, 196, 163, 255)
    skin_lo = (108, 114, 92, 255)
    bile = (154, 169, 45, 255)
    bile_hi = (202, 215, 83, 255)
    rag = (71, 63, 51, 255)
    bob = 1 if mode == "idle" and frame in (1, 3) else 0
    if mode == "die":
        y = 27 + min(4, frame)
        cv.ellipse(18, y + 2, 15, 6, skin)
        cv.ellipse(18, y + 2, 13, 5, skin_hi)
        cv.rect(13, y - 3, 23, y + 2, skin)
        cv.rect(16, y - 4, 22, y - 1, skin_lo)
        if frame >= 2:
            cv.ellipse(18, y + 4, 14, 3, bile)
            cv.rect(2, y + 5, 34, y + 6, (94, 108, 34, 255))
        cv.outline(OUT)
        return cv
    # tiny legs
    cv.rect(11, 30, 16, 34, rag)
    cv.rect(20, 30, 25, 34, shade(rag, 0.8))
    cv.rect(9, 33, 16, 35, P["brown_dark"])
    cv.rect(20, 33, 28, 35, P["brown_dark"])
    # massive belly
    inflate = 0
    if mode == "inflate":
        inflate = 1 + frame
    y = 10 + bob
    cv.ellipse(18, y + 13, 15 + inflate, 13 + inflate, skin)
    cv.ellipse(18, y + 13, 12 + inflate, 11 + inflate, skin_hi)
    cv.ellipse(18, y + 16, 10 + inflate, 7 + inflate, shade(skin, 0.92))
    # shirt scrap / straps
    cv.rect(7, y + 3, 29, y + 8, rag)
    cv.rect(8, y + 3, 12, y + 7, shade(rag, 1.3))
    cv.rect(24, y + 3, 29, y + 7, shade(rag, 0.7))
    cv.rect(15, y + 20, 22, y + 22, bile)
    cv.rect(8, y + 14, 13, y + 16, bile)
    cv.px(10, y + 14, bile_hi)
    # tiny arms
    limb(cv, 5, y + 7, 2, y + 14, skin_lo, 3)
    cv.rect(1, y + 13, 5, y + 16, skin)
    limb(cv, 31, y + 7, 34, y + 13, skin, 3)
    cv.rect(32, y + 12, 35, y + 15, skin_hi)
    # small head sunk into body
    cv.ellipse(18, y - 1, 6, 5, skin)
    cv.rect(14, y - 4, 22, y + 1, skin_lo)
    cv.rect(16, y - 5, 21, y - 3, skin)
    cv.rect(19, y - 2, 21, y, (44, 33, 30, 255))
    cv.px(20, y - 1, bile_hi)
    cv.rect(17, y - 1, 19, y, P["blood_dark"])
    # drool
    cv.rect(21, y, 23, y + 2, bile)
    if mode == "attack":
        cv.rect(23, y + 1, 31, y + 3, bile_hi)
        cv.px(32, y + 3, bile)
    cv.outline(OUT)
    return cv


# ------------------------------------------------------------ special: charger
def charger(mode, frame, n):
    cv = Canvas(40, 40)
    cv.shadow(3, 37, 37, 38, 110)
    skin = (141, 113, 91, 255)
    skin_hi = (173, 141, 112, 255)
    skin_lo = (96, 73, 58, 255)
    shirt = (78, 64, 54, 255)
    pants = (58, 55, 49, 255)
    bob = 1 if mode == "idle" and frame in (1, 3) else 0
    if mode == "die":
        y = 29 + min(4, frame)
        cv.rect(2, y, 37, y + 6, skin)
        cv.rect(2, y, 37, y + 1, skin_hi)
        cv.rect(29, y - 5, 38, y + 2, skin)
        cv.rect(4, y + 5, 24, y + 7, pants)
        if frame >= 3:
            cv.rect(0, y + 7, 39, y + 8, P["blood_dark"])
            cv.rect(6, y + 8, 34, y + 9, P["blood"])
        cv.outline(OUT)
        return cv
    y = 16 + bob
    # legs wide
    limb(cv, 14, y + 7, 9, 37, pants, 4)
    limb(cv, 22, y + 7, 29, 37, shade(pants, 0.8), 4)
    cv.rect(5, 35, 14, 38, P["brown_dark"])
    cv.rect(27, 35, 35, 38, P["brown_dark"])
    # hunched torso
    cv.poly([(9, y - 1), (27, y - 2), (31, y + 8), (26, y + 13), (12, y + 13), (7, y + 7)], shirt)
    cv.rect(10, y - 1, 14, y + 10, shade(shirt, 1.3))
    cv.rect(25, y + 2, 30, y + 10, shade(shirt, 0.7))
    cv.rect(13, y + 9, 25, y + 11, skin_lo)
    # harness straps
    cv.line([(11, y), (16, y + 12)], (105, 83, 54, 255), 2)
    cv.line([(25, y), (20, y + 12)], (105, 83, 54, 255), 2)
    # massive front arm
    if mode in ("charge", "punch"):
        cv.ellipse(31, y + 7, 8, 7, skin)
        cv.ellipse(31, y + 7, 6, 5, skin_hi)
        cv.rect(24, y + 3, 31, y + 11, skin)
        cv.rect(31, y + 3, 38, y + 8, skin_lo)
        cv.rect(36, y + 1, 39, y + 9, skin_hi)
        cv.px(37, y + 3, P["blood_dark"])
    else:
        cv.ellipse(30, y + 8, 7, 7, skin)
        cv.ellipse(30, y + 8, 5, 5, skin_hi)
        cv.rect(24, y + 5, 30, y + 11, skin)
        cv.rect(34, y + 8, 38, y + 12, skin_lo)
        cv.px(35, y + 9, P["blood_dark"])
    # small back arm
    limb(cv, 10, y + 2, 5, y + 8, skin_lo, 3)
    cv.rect(3, y + 7, 7, y + 10, skin)
    # small head, low between shoulders
    cv.ellipse(24, y - 5, 5, 5, skin)
    cv.rect(20, y - 7, 28, y - 2, skin_lo)
    cv.rect(22, y - 8, 27, y - 5, skin)
    cv.px(26, y - 5, (38, 31, 26, 255))
    cv.rect(26, y - 3, 29, y - 2, P["blood_dark"])
    cv.px(25, y - 2, P["bone"])
    # charge dust
    if mode == "charge":
        for x, yy in [(1, 36), (3, 34), (6, 36)]:
            cv.px(x, yy, (150, 137, 110, 170))
    cv.outline(OUT)
    return cv


# ------------------------------------------------------------ special: spitter
def spitter(mode, frame, n):
    cv = Canvas(32, 40)
    cv.shadow(4, 37, 27, 38, 90)
    skin = (128, 151, 79, 255)
    skin_hi = (167, 187, 105, 255)
    skin_lo = (88, 105, 52, 255)
    acid = (172, 196, 55, 255)
    acid_hi = (216, 236, 103, 255)
    rag = (83, 72, 53, 255)
    bob = 1 if mode == "idle" and frame in (1, 3) else 0
    if mode == "die":
        y = 31 + min(3, frame)
        cv.rect(2, y, 29, y + 4, skin)
        cv.rect(2, y, 29, y + 1, skin_hi)
        cv.rect(25, y - 4, 31, y + 2, skin)
        cv.rect(4, y + 3, 18, y + 5, rag)
        if frame >= 2:
            cv.rect(0, y + 5, 31, y + 6, acid)
            cv.rect(7, y + 6, 25, y + 7, skin_lo)
        cv.outline(OUT)
        return cv
    # thin legs
    limb(cv, 12, 30, 9, 37, rag, 2)
    limb(cv, 18, 30, 21, 37, shade(rag, 0.8), 2)
    cv.rect(6, 36, 12, 38, P["brown_dark"])
    cv.rect(19, 36, 25, 38, P["brown_dark"])
    # swollen belly
    y = 17 + bob
    cv.ellipse(15, y + 6, 8, 7, skin)
    cv.ellipse(15, y + 6, 6, 5, skin_hi)
    cv.rect(8, y, 22, y + 4, rag)
    cv.rect(9, y, 12, y + 3, shade(rag, 1.3))
    cv.rect(11, y + 4, 20, y + 6, skin_lo)
    cv.rect(13, y + 8, 19, y + 9, acid)
    # long thin neck
    cv.rect(14, y - 9, 18, y, skin)
    cv.rect(15, y - 9, 17, y - 2, skin_hi)
    cv.px(16, y - 5, skin_lo)
    # head
    cv.ellipse(17, y - 12, 5, 4, skin)
    cv.rect(14, y - 15, 21, y - 10, skin_lo)
    cv.rect(17, y - 13, 20, y - 11, skin_hi)
    cv.px(19, y - 12, (45, 36, 24, 255))
    cv.px(20, y - 12, acid_hi)
    # mouth drooling acid
    cv.rect(19, y - 10, 23, y - 8, (52, 33, 28, 255))
    cv.rect(20, y - 9, 23, y - 8, acid)
    cv.rect(21, y - 7, 23, y - 5, acid)
    if mode == "spit":
        cv.rect(22, y - 8, 31, y - 6, acid_hi)
        cv.px(31, y - 5, acid)
    # arms
    limb(cv, 8, y + 1, 3, y + 7, skin_lo, 2)
    limb(cv, 22, y + 1, 27, y + 6, skin, 2)
    cv.rect(26, y + 5, 29, y + 8, skin_hi)
    cv.outline(OUT)
    return cv


# ------------------------------------------------------------ special: jockey
def jockey(mode, frame, n):
    cv = Canvas(28, 30)
    cv.shadow(3, 27, 24, 28, 90)
    skin = (168, 146, 122, 255)
    skin_hi = (198, 176, 147, 255)
    skin_lo = (122, 102, 84, 255)
    rag = (70, 61, 51, 255)
    bob = 1 if mode == "idle" and frame in (1, 3) else 0
    if mode == "die":
        y = 22 + min(3, frame)
        cv.rect(2, y, 25, y + 4, skin)
        cv.rect(2, y, 25, y + 1, skin_hi)
        cv.rect(21, y - 4, 27, y + 1, skin)
        cv.rect(4, y + 3, 16, y + 5, rag)
        if frame >= 2:
            cv.rect(0, y + 5, 27, y + 6, P["blood_dark"])
        cv.outline(OUT)
        return cv
    y = 14 + bob
    # bent legs
    limb(cv, 10, y + 8, 7, 23, rag, 2)
    limb(cv, 15, y + 8, 18, 23, shade(rag, 0.8), 2)
    cv.rect(5, 22, 11, 24, P["brown_dark"])
    cv.rect(17, 22, 23, 24, P["brown_dark"])
    # tiny torso, hunched
    cv.poly([(8, y), (18, y), (19, y + 7), (16, y + 9), (9, y + 9), (7, y + 6)], rag)
    cv.rect(9, y, 11, y + 7, shade(rag, 1.3))
    cv.rect(9, y + 5, 17, y + 7, skin_lo)
    # long arms
    if mode in ("leap", "ride"):
        limb(cv, 8, y + 1, 2, y - 2, skin_lo, 2)
        limb(cv, 18, y + 1, 25, y + 4, skin, 2)
        cv.rect(24, y + 3, 27, y + 6, skin_hi)
    else:
        limb(cv, 8, y + 2, 4, y + 8, skin_lo, 2)
        limb(cv, 18, y + 2, 23, y + 7, skin, 2)
        cv.rect(22, y + 6, 25, y + 9, skin_hi)
    # oversized head, jutting forward
    cv.ellipse(17, y - 4, 6, 5, skin)
    cv.rect(13, y - 8, 22, y - 3, skin_lo)
    cv.rect(15, y - 9, 21, y - 6, skin_hi)
    cv.rect(18, y - 6, 21, y - 4, (38, 31, 27, 255))
    cv.px(20, y - 5, P["red_hot"])
    # huge grin
    cv.rect(17, y - 2, 24, y, (46, 28, 28, 255))
    cv.rect(18, y - 2, 23, y - 1, (214, 205, 180, 255))
    cv.px(19, y, (214, 205, 180, 255))
    cv.px(22, y, (214, 205, 180, 255))
    # laugh lines
    cv.px(23, y - 3, P["blood_dark"])
    if mode == "leap":
        cv.rect(23, y + 6, 27, y + 8, skin)
    cv.outline(OUT)
    return cv


# ------------------------------------------------------------ special: tank
def tank(mode, frame, n):
    cv = Canvas(64, 64)
    cv.shadow(3, 60, 61, 62, 130)
    skin = (133, 122, 103, 255)
    skin_hi = (174, 161, 136, 255)
    skin_lo = (88, 79, 67, 255)
    pants = (52, 53, 46, 255)
    bob = 1 if mode == "idle" and frame in (1, 3) else 0
    if mode == "die":
        y = 46 + min(6, frame * 2)
        cv.ellipse(32, y + 8, 29, 11, skin)
        cv.ellipse(32, y + 8, 25, 9, skin_hi)
        cv.rect(40, y - 5, 56, y + 5, skin)
        cv.rect(6, y + 8, 38, y + 13, pants)
        cv.rect(2, y + 15, 62, y + 17, P["blood_dark"])
        cv.rect(10, y + 17, 54, y + 19, P["blood"])
        cv.outline(OUT)
        return cv
    y = 16 + bob
    # legs - thick and short
    cv.rect(19, y + 26, 29, 58, pants)
    cv.rect(35, y + 26, 45, 58, shade(pants, 0.8))
    cv.rect(17, 56, 31, 61, P["brown_dark"])
    cv.rect(33, 56, 47, 61, shade(P["brown_dark"], 0.8))
    cv.rect(19, y + 26, 22, 56, shade(pants, 1.2))
    # waist / belt
    cv.rect(17, y + 22, 47, y + 28, pants)
    cv.rect(18, y + 22, 46, y + 23, (90, 82, 60, 255))
    # broad chest
    cv.poly([(14, y + 2), (26, y - 3), (42, y - 3), (52, y + 4), (48, y + 24), (16, y + 24)], skin)
    cv.poly([(18, y + 2), (30, y - 1), (38, y), (42, y + 21), (20, y + 22)], skin_hi)
    cv.rect(24, y + 12, 40, y + 21, shade(skin, 0.92))
    # pecs / abs
    cv.rect(20, y + 4, 31, y + 8, skin_hi)
    cv.rect(35, y + 4, 45, y + 8, skin_hi)
    cv.line([(32, y + 2), (32, y + 20)], skin_lo, 2)
    cv.line([(22, y + 10), (31, y + 12)], skin_lo, 1)
    cv.line([(34, y + 10), (43, y + 12)], skin_lo, 1)
    # wounds
    cv.line([(20, y + 14), (25, y + 22)], P["blood_dark"], 1)
    cv.px(26, y + 15, P["blood"])
    cv.px(40, y + 15, P["blood_dark"])
    cv.rect(37, y + 6, 42, y + 8, P["blood_dark"])
    # shoulders + massive arms
    cv.ellipse(12, y + 8, 9, 11, skin_lo)
    cv.ellipse(52, y + 8, 9, 11, skin)
    if mode == "punch":
        # right arm extended forward
        cv.rect(48, y + 4, 61, y + 15, skin)
        cv.rect(49, y + 4, 57, y + 7, skin_hi)
        cv.ellipse(61, y + 10, 7, 8, skin_hi)
        cv.rect(60, y + 4, 64, y + 15, skin_lo)
        cv.rect(55, y + 13, 63, y + 16, skin_lo)
        # left arm hanging
        cv.rect(5, y + 8, 14, y + 28, skin_lo)
        cv.ellipse(8, y + 28, 7, 7, skin)
    elif mode == "throw":
        # right arm raised overhead with a rock
        cv.rect(46, y - 14, 58, y + 10, skin)
        cv.rect(48, y - 14, 55, y - 9, skin_hi)
        cv.ellipse(52, y - 18, 8, 8, skin_hi)
        cv.rect(55, y - 22, 62, y - 15, (101, 97, 88, 255))
        cv.rect(57, y - 21, 60, y - 18, (139, 133, 120, 255))
        # left arm hanging
        cv.rect(5, y + 8, 14, y + 28, skin_lo)
        cv.ellipse(8, y + 28, 7, 7, skin)
    else:
        cv.rect(5, y + 8, 14, y + 34, skin_lo)
        cv.ellipse(8, y + 35, 8, 8, skin)
        cv.rect(50, y + 8, 60, y + 34, skin)
        cv.rect(51, y + 8, 55, y + 31, skin_hi)
        cv.ellipse(56, y + 35, 8, 8, skin_hi)
        cv.rect(54, y + 30, 62, y + 40, skin_lo)
        cv.rect(53, y + 38, 63, y + 42, skin_hi)
    # arm separation lines
    cv.line([(17, y + 4), (14, y + 18)], shade(skin_lo, 0.7), 2)
    cv.line([(47, y + 4), (50, y + 18)], shade(skin_lo, 0.7), 2)
    # neck + small head
    cv.rect(28, y - 4, 37, y + 2, skin_lo)
    cv.ellipse(33, y - 10, 8, 8, skin)
    cv.rect(26, y - 15, 40, y - 6, skin_lo)
    cv.rect(27, y - 16, 39, y - 11, skin_hi)
    cv.rect(34, y - 12, 40, y - 9, (38, 29, 24, 255))
    cv.px(37, y - 10, P["red_hot"])
    cv.px(38, y - 10, P["orange_light"])
    cv.rect(32, y - 7, 41, y - 4, (48, 28, 27, 255))
    cv.px(34, y - 6, P["bone"])
    cv.px(37, y - 6, P["bone"])
    cv.px(40, y - 6, P["bone"])
    cv.line([(26, y - 12), (30, y - 7)], P["blood_dark"], 1)
    if mode == "punch":
        for x, yy in [(60, y + 1), (63, y + 3), (58, y + 14)]:
            cv.px(x, yy, (203, 189, 160, 180))
    cv.outline(OUT)
    return cv


# ------------------------------------------------------------ special: witch
def witch(mode, frame, n):
    cv = Canvas(32, 48)
    cv.shadow(4, 45, 28, 46, 100)
    skin = (196, 190, 174, 255)
    skin_hi = (226, 221, 206, 255)
    skin_lo = (145, 138, 126, 255)
    dress = (122, 120, 113, 255)
    dress_hi = (154, 151, 142, 255)
    dress_lo = (83, 81, 77, 255)
    hair = (30, 28, 30, 255)
    hair_hi = (52, 49, 51, 255)
    if mode == "die":
        y = 38 + min(4, frame)
        cv.ellipse(16, y + 2, 14, 6, dress)
        cv.ellipse(16, y + 2, 12, 5, dress_hi)
        cv.rect(9, y - 5, 23, y + 2, hair)
        cv.rect(18, y - 3, 25, y + 1, skin)
        cv.rect(4, y + 4, 17, y + 6, skin_lo)
        if frame >= 2:
            cv.rect(0, y + 5, 31, y + 6, P["blood_dark"])
            cv.rect(6, y + 6, 26, y + 7, P["blood"])
        cv.outline(OUT)
        return cv
    if mode in ("idle", "scream"):
        # seated, knees drawn up, head bowed, hair over the face
        y = 31
        # skirt pooled on the ground
        cv.ellipse(16, y + 8, 13, 7, dress)
        cv.ellipse(16, y + 9, 10, 5, dress_hi)
        cv.rect(4, y + 12, 28, y + 15, dress_lo)
        cv.rect(3, y + 14, 29, y + 15, dress)
        # blood on the hem
        cv.rect(8, y + 13, 14, y + 14, P["blood_dark"])
        cv.rect(19, y + 12, 25, y + 13, P["blood"])
        # knees
        cv.ellipse(9, y + 6, 5, 6, dress_lo)
        cv.ellipse(23, y + 6, 5, 6, dress_lo)
        cv.rect(7, y + 8, 12, y + 11, skin_lo)
        cv.rect(20, y + 8, 26, y + 11, skin)
        cv.rect(7, y + 9, 9, y + 10, skin_hi)
        # torso
        cv.rect(11, y - 7, 22, y + 6, dress)
        cv.rect(12, y - 7, 15, y + 4, dress_hi)
        cv.rect(19, y - 5, 22, y + 5, dress_lo)
        cv.rect(12, y + 1, 21, y + 3, P["blood_dark"])
        # arms wrapped around knees
        cv.rect(6, y + 1, 12, y + 4, skin_lo)
        cv.rect(20, y + 1, 27, y + 4, skin)
        cv.rect(5, y + 3, 9, y + 6, skin)
        cv.rect(23, y + 3, 27, y + 6, skin_hi)
        # head bowed
        cv.ellipse(16, y - 13, 6, 6, skin)
        cv.rect(10, y - 20, 23, y - 9, hair)
        cv.rect(11, y - 22, 22, y - 14, hair_hi)
        cv.rect(9, y - 13, 13, y + 8, hair)
        cv.rect(20, y - 13, 24, y + 6, hair)
        # face strip
        cv.rect(15, y - 13, 20, y - 7, skin)
        cv.rect(16, y - 12, 19, y - 8, skin_hi)
        cv.px(18, y - 11, P["red_hot"])
        cv.px(19, y - 11, P["blood_bright"])
        cv.px(18, y - 10, P["blood"])
        cv.px(18, y - 9, P["blood"])
        cv.rect(17, y - 7, 20, y - 6, (92, 50, 53, 255))
        if mode == "scream":
            # head snaps up, mouth open, arms out
            cv.rect(10, y - 24, 23, y - 14, hair)
            cv.rect(11, y - 26, 21, y - 18, hair_hi)
            cv.rect(12, y - 17, 21, y - 8, skin)
            cv.px(14, y - 14, P["red_hot"])
            cv.px(19, y - 14, P["red_hot"])
            cv.rect(15, y - 11, 21, y - 8, (46, 26, 28, 255))
            cv.rect(16, y - 10, 20, y - 9, (106, 53, 55, 255))
            cv.rect(1, y - 3, 8, y, skin_lo)
            cv.rect(24, y - 3, 31, y, skin)
            cv.rect(2, y - 6, 6, y - 3, skin)
            cv.rect(26, y - 6, 30, y - 3, skin_hi)
            cv.px(3, y - 6, P["bone"])
            cv.px(29, y - 6, P["bone"])
        cv.outline(OUT)
        return cv
    # standing: chase / attack
    y = 10
    bob = 1 if frame % 2 else 0
    # legs
    limb(cv, 14, y + 28, 11, 43, skin_lo, 3)
    limb(cv, 18, y + 28, 22, 43, skin, 3)
    cv.rect(8, 42, 14, 45, skin_lo)
    cv.rect(20, 42, 26, 45, skin)
    # ragged dress
    cv.poly([(10, y + 10), (22, y + 10), (28, y + 30), (4, y + 30)], dress)
    cv.poly([(12, y + 10), (18, y + 10), (21, y + 29), (8, y + 29)], dress_hi)
    cv.rect(4, y + 27, 28, y + 31, dress_lo)
    cv.rect(6, y + 30, 11, y + 31, dress)
    cv.rect(17, y + 29, 23, y + 30, dress)
    cv.rect(9, y + 24, 15, y + 25, P["blood_dark"])
    cv.rect(18, y + 22, 24, y + 23, P["blood"])
    # torso / arms
    cv.rect(11, y + 2, 21, y + 11, dress)
    cv.rect(12, y + 2, 14, y + 10, dress_hi)
    if mode == "attack":
        cv.rect(20, y + 2, 31, y + 5, skin)
        cv.rect(28, y + 1, 32, y + 6, skin_hi)
        cv.px(31, y + 2, P["bone"])
        cv.px(31, y + 4, P["bone"])
        cv.rect(3, y + 7, 11, y + 10, skin_lo)
        cv.rect(1, y + 9, 4, y + 11, skin)
    else:
        cv.rect(4, y + 5, 12, y + 8, skin_lo)
        cv.rect(21, y + 4, 29, y + 7, skin)
        cv.rect(26, y + 6, 30, y + 10, skin_hi)
        cv.px(29, y + 9, P["bone"])
    # head + long hair
    cv.ellipse(16, y - 4, 6, 6, skin)
    cv.rect(10, y - 12, 23, y - 2, hair)
    cv.rect(11, y - 14, 21, y - 8, hair_hi)
    cv.rect(9, y - 6, 13, y + 16, hair)
    cv.rect(20, y - 6, 24, y + 14, hair)
    cv.rect(15, y - 4, 20, y + 1, skin)
    cv.rect(16, y - 3, 19, y - 1, skin_hi)
    cv.px(18, y - 2, P["red_hot"])
    cv.px(19, y - 2, P["blood_bright"])
    cv.px(18, y - 1, P["blood"])
    cv.rect(17, y + 1, 20, y + 2, (91, 49, 52, 255))
    if mode == "attack":
        cv.rect(15, y + 1, 21, y + 3, (52, 27, 30, 255))
        cv.rect(14, y + 2, 20, y + 3, P["bone"])
    cv.outline(OUT)
    return cv


SPECIALS = {
    "hunter": dict(size=(32, 32), draw=hunter, anims=[("idle", 4), ("run", 6), ("pounce", 3), ("pin", 2), ("hurt", 2), ("die", 6)]),
    "smoker": dict(size=(32, 40), draw=smoker, anims=[("idle", 4), ("run", 6), ("attack", 4), ("hurt", 2), ("die", 6)]),
    "boomer": dict(size=(36, 36), draw=boomer, anims=[("idle", 4), ("run", 6), ("inflate", 3), ("attack", 3), ("hurt", 2), ("die", 6)]),
    "charger": dict(size=(40, 40), draw=charger, anims=[("idle", 4), ("run", 6), ("charge", 4), ("punch", 3), ("hurt", 2), ("die", 6)]),
    "spitter": dict(size=(32, 40), draw=spitter, anims=[("idle", 4), ("run", 6), ("spit", 3), ("hurt", 2), ("die", 6)]),
    "jockey": dict(size=(28, 30), draw=jockey, anims=[("idle", 4), ("run", 6), ("leap", 3), ("ride", 2), ("hurt", 2), ("die", 6)]),
    "tank": dict(size=(64, 64), draw=tank, anims=[("idle", 4), ("run", 6), ("punch", 3), ("throw", 3), ("hurt", 2), ("die", 6)]),
    "witch": dict(size=(32, 48), draw=witch, anims=[("idle", 4), ("scream", 2), ("chase", 6), ("attack", 3), ("hurt", 2), ("die", 6)]),
}


def gen_specials():
    preview = []
    for name, spec in SPECIALS.items():
        for anim, n in spec["anims"]:
            if name == "hunter" and anim == "die":
                frames = [hunter_death(i) for i in range(n)]
            else:
                frames = [spec["draw"](anim, i, n) for i in range(n)]
            save_sheet(frames, os.path.join(ZDIR, f"{name}_{anim}.png"))
        base_anim = "idle"
        preview.append((name, spec["draw"](base_anim, 0, 4).img))
        if name in ("hunter", "charger", "tank"):
            preview.append((name + "_act", spec["draw"]("pounce" if name == "hunter" else "charge" if name == "charger" else "punch", 1, 3).img))
    contact_sheet(preview, os.path.join(ROOT, "build", "preview_specials.png"), scale=4, cols=5)


if __name__ == "__main__":
    gen_common()
    gen_specials()
    print("zombies generated")
