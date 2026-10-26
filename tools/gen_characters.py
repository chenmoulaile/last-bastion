"""Generate original survivor sprites, portraits and weapon sprites.

The silhouettes/colour language are inspired by the L4D2 survivor cast, but
every pixel here is generated from scratch by this script.
"""
from __future__ import annotations

import math
import os
import sys

from PIL import Image

sys.path.insert(0, os.path.dirname(__file__))
from pixel_art import Canvas, P, shade, mix, save_sheet, contact_sheet, OUT, load_font

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
CHARS = os.path.join(ROOT, "assets", "sprites", "characters")
WEAPONS = os.path.join(ROOT, "assets", "sprites", "weapons")
os.makedirs(CHARS, exist_ok=True)
os.makedirs(WEAPONS, exist_ok=True)

STYLES = {
    "assault": dict(
        name="突击兵", skin=P["skin"], hair=(48, 33, 24, 255), jacket=P["olive"],
        jacket_hi=P["olive_light"], jacket_lo=P["olive_dark"], pants=P["tan"],
        boots=P["brown_dark"], pack=P["olive_dark"], bandana=P["blood_bright"],
        build=0, cap=None, mask=None, scarf=None, vest=None, armband=None,
        bald=False, beard=False, glasses=False, hood=False,
    ),
    "medic": dict(
        name="医疗兵", skin=P["skin_light"], hair=(74, 50, 33, 255), jacket=P["bone"],
        jacket_hi=P["white"], jacket_lo=P["smoke"], pants=(64, 72, 78, 255),
        boots=P["coal"], pack=(82, 92, 96, 255), bandana=None,
        build=0, cap=(212, 216, 210, 255), mask=None, scarf=None, vest=None,
        armband=P["red"], bald=False, beard=False, glasses=False, hood=False,
    ),
    "heavy": dict(
        name="重装兵", skin=(92, 62, 45, 255), hair=(30, 26, 24, 255), jacket=(58, 68, 78, 255),
        jacket_hi=(84, 97, 108, 255), jacket_lo=(35, 42, 49, 255), pants=(52, 53, 48, 255),
        boots=P["ink"], pack=(44, 50, 55, 255), bandana=None,
        build=1, cap=None, mask=None, scarf=None, vest=(46, 54, 61, 255),
        armband=None, bald=True, beard=True, glasses=False, hood=False,
    ),
    "scout": dict(
        name="侦察兵", skin=P["skin_light"], hair=(34, 27, 22, 255), jacket=(178, 139, 45, 255),
        jacket_hi=(214, 176, 72, 255), jacket_lo=(112, 84, 28, 255), pants=(47, 52, 55, 255),
        boots=P["brown_dark"], pack=(82, 60, 33, 255), bandana=None,
        build=0, cap=(74, 93, 48, 255), mask=None, scarf=None, vest=None,
        armband=None, bald=False, beard=False, glasses=False, hood=False,
    ),
    "ninja": dict(
        name="特勤", skin=P["skin_pale"], hair=P["ink"], jacket=(38, 41, 48, 255),
        jacket_hi=(61, 65, 73, 255), jacket_lo=(22, 24, 29, 255), pants=(29, 32, 37, 255),
        boots=P["black"], pack=(33, 35, 40, 255), bandana=P["blood"],
        build=0, cap=None, mask=(32, 35, 41, 255), scarf=P["blood"], vest=None,
        armband=None, bald=False, beard=False, glasses=False, hood=True,
    ),
    "officer": dict(
        name="军官", skin=(118, 82, 58, 255), hair=(29, 27, 25, 255), jacket=(40, 52, 67, 255),
        jacket_hi=(61, 76, 92, 255), jacket_lo=(26, 34, 45, 255), pants=(112, 92, 58, 255),
        boots=P["brown_dark"], pack=(44, 50, 56, 255), bandana=None,
        build=0, cap=(39, 51, 64, 255), mask=None, scarf=None, vest=(49, 61, 73, 255),
        armband=None, bald=False, beard=False, glasses=True, hood=False, beret=True,
    ),
}


def limb(cv, x0, y0, x1, y1, c, width=2):
    cv.line([(x0, y0), (x1, y1)], c, width)
    cv.px(x0, y0, c)
    cv.px(x1, y1, c)


def boot(cv, x, y, c, dark=None):
    dark = dark or shade(c, 0.6)
    cv.rect(x - 2, y, x + 2, y + 2, c)
    cv.rect(x - 2, y + 2, x + 3, y + 3, dark)


def draw_head(cv, st, cx, top, bob=0, hurt=False):
    skin = st["skin"]
    hair = st["hair"]
    # neck
    cv.rect(cx - 2, top + 7, cx + 1, top + 9, shade(skin, 0.8))
    # skull / jaw
    cv.ellipse(cx, top + 4, 4, 4, skin)
    cv.rect(cx - 3, top + 5, cx + 3, top + 8, skin)
    # back of head hair
    cv.rect(cx - 4, top + 1, cx - 2, top + 7, hair)
    cv.rect(cx - 5, top + 2, cx - 3, top + 5, hair)
    # hair cap
    cv.rect(cx - 3, top, cx + 2, top + 2, hair)
    if st["bald"]:
        cv.rect(cx - 3, top, cx + 2, top + 2, skin)
        cv.rect(cx - 3, top + 2, cx + 2, top + 3, shade(skin, 0.8))
        cv.px(cx + 1, top + 1, shade(skin, 1.15))
    # face shading
    cv.rect(cx + 2, top + 4, cx + 3, top + 7, shade(skin, 0.86))
    cv.px(cx + 4, top + 5, shade(skin, 0.92))
    cv.px(cx + 3, top + 5, skin)
    # eye
    eye = P["ink"] if not hurt else P["red"]
    if st["glasses"]:
        cv.rect(cx + 1, top + 4, cx + 3, top + 5, (20, 24, 29, 255))
        cv.px(cx + 3, top + 4, P["steel"])
    elif st["hood"]:
        cv.px(cx + 2, top + 4, P["cyan_light"])
        cv.px(cx + 1, top + 4, shade(P["cyan_light"], 0.6))
    else:
        cv.px(cx + 2, top + 4, eye)
        cv.px(cx + 1, top + 4, shade(skin, 0.55))
    # nose + mouth
    cv.px(cx + 4, top + 6, shade(skin, 0.9))
    cv.px(cx + 3, top + 7, shade(skin, 0.55))
    if hurt:
        cv.rect(cx + 1, top + 8, cx + 3, top + 8, P["blood_dark"])
    # beard
    if st["beard"]:
        cv.rect(cx - 2, top + 8, cx + 3, top + 10, hair)
        cv.rect(cx + 1, top + 8, cx + 3, top + 9, shade(hair, 1.2))
    # bandana
    if st["bandana"]:
        cv.rect(cx - 4, top + 2, cx + 3, top + 3, st["bandana"])
        cv.rect(cx - 6, top + 3, cx - 4, top + 4, st["bandana"])
        cv.px(cx - 5, top + 4, shade(st["bandana"], 0.7))
    # cap
    if st["cap"] and not st.get("beret"):
        cv.rect(cx - 4, top - 1, cx + 3, top + 1, st["cap"])
        cv.rect(cx + 1, top + 1, cx + 5, top + 2, shade(st["cap"], 0.75))
        if st["name"] == "医疗兵":
            cv.px(cx - 1, top, P["red"])
            cv.rect(cx - 1, top - 1, cx, top + 1, P["red"])
    if st.get("beret"):
        cv.rect(cx - 4, top - 1, cx + 2, top + 1, st["cap"])
        cv.rect(cx + 2, top, cx + 4, top + 1, shade(st["cap"], 1.25))
        cv.px(cx - 2, top - 1, P["gold"])
    # hood
    if st["hood"]:
        cv.rect(cx - 5, top - 1, cx + 2, top + 2, st["jacket"])
        cv.rect(cx - 6, top + 2, cx - 4, top + 8, st["jacket_lo"])
        cv.px(cx + 2, top + 1, st["jacket_hi"])
    # mask (ninja)
    if st["mask"]:
        cv.rect(cx - 3, top + 5, cx + 3, top + 8, st["mask"])
        cv.px(cx + 2, top + 5, P["skin_pale"])
    # scarf tail
    if st["scarf"]:
        cv.rect(cx - 7, top + 9, cx - 4, top + 10, st["scarf"])
        cv.px(cx - 8, top + 10, shade(st["scarf"], 0.8))


def draw_torso(cv, st, bob=0, lean=0, crouch=0):
    y = 12 + bob + crouch
    w = st["build"]
    x0 = 10 - w + lean
    x1 = 20 + w + lean
    # backpack
    cv.rect(x0 - 4, y + 1, x0 - 1, y + 8, st["pack"])
    cv.rect(x0 - 4, y + 1, x0 - 3, y + 8, shade(st["pack"], 1.2))
    cv.rect(x0 - 3, y + 4, x0 - 1, y + 5, shade(st["pack"], 0.7))
    # torso jacket
    cv.poly([(x0, y + 1), (x1, y + 1), (x1 + 1, y + 8), (x1 - 1, y + 11), (x0 + 1, y + 11), (x0 - 1, y + 8)], st["jacket"])
    cv.rect(x0 + 1, y + 1, x0 + 3, y + 9, st["jacket_hi"])
    cv.rect(x1 - 1, y + 3, x1, y + 9, st["jacket_lo"])
    # collar
    cv.rect(x0 + 3, y, x1 - 2, y + 1, shade(st["jacket"], 0.7))
    # zipper / straps
    cv.line([(x1 - 3, y + 2), (x1 - 3, y + 9)], shade(st["jacket"], 0.6))
    cv.rect(x0, y + 4, x1 - 2, y + 5, shade(st["jacket"], 0.55))
    # belt
    cv.rect(x0 + 1, y + 9, x1, y + 10, P["brown_dark"])
    cv.px(x1 - 3, y + 9, P["gold"])
    # vest
    if st["vest"]:
        cv.rect(x0 + 2, y + 1, x1 - 1, y + 8, st["vest"])
        cv.rect(x0 + 2, y + 1, x0 + 3, y + 8, shade(st["vest"], 1.3))
        cv.rect(x0 + 4, y + 5, x1 - 2, y + 7, shade(st["vest"], 0.75))
        cv.rect(x0 + 5, y + 3, x0 + 7, y + 6, shade(st["vest"], 0.65))
    # armband
    if st["armband"]:
        cv.rect(x1 - 3, y + 3, x1 - 1, y + 5, st["armband"])
        cv.px(x1 - 2, y + 4, P["white"])
    # small red cross on medic chest
    if st["name"] == "医疗兵":
        cv.rect(x0 + 4, y + 3, x0 + 6, y + 4, P["red"])
        cv.rect(x0 + 5, y + 2, x0 + 5, y + 5, P["red"])
    # grime
    cv.px(x0 + 2, y + 7, shade(st["jacket"], 0.7))
    cv.px(x1 - 2, y + 2, shade(st["jacket"], 0.75))


def draw_legs(cv, st, mode, frame, n, crouch=0):
    pants = st["pants"]
    dark = shade(pants, 0.65)
    boots = st["boots"]
    y_hip = 22 + crouch
    if mode == "idle":
        boot(cv, 13, 27 + crouch, boots)
        boot(cv, 18, 27 + crouch, boots)
        cv.rect(12, y_hip, 15, 27 + crouch, pants)
        cv.rect(17, y_hip, 20, 27 + crouch, shade(pants, 0.85))
        cv.rect(12, y_hip, 14, 24 + crouch, pants)
    elif mode in ("run", "walk"):
        phase = frame / n * math.tau
        swing = math.sin(phase)
        lift_f = max(0.0, math.sin(phase + 0.4))
        lift_b = max(0.0, math.sin(phase + math.pi + 0.4))
        fx = 17 + int(round(swing * 4))
        bx = 13 - int(round(swing * 4))
        fy = 27 + crouch - int(round(lift_f * 3))
        by = 27 + crouch - int(round(lift_b * 3))
        # back leg
        limb(cv, 13, y_hip, bx, by - 3, dark, 3)
        boot(cv, bx, by, shade(boots, 0.75))
        # front leg
        limb(cv, 17, y_hip, fx, fy - 3, pants, 3)
        boot(cv, fx, fy, boots)
        cv.px(fx, fy - 2, shade(pants, 1.2))
    elif mode == "crouch":
        cv.rect(11, y_hip - 2, 15, 26, pants)
        cv.rect(17, y_hip - 2, 21, 26, shade(pants, 0.85))
        cv.rect(10, 25, 16, 27, boots)
        cv.rect(17, 25, 23, 27, boots)
        cv.rect(11, 24, 15, 26, shade(boots, 1.1))
    elif mode == "jump":
        limb(cv, 14, y_hip, 11, 25, dark, 3)
        limb(cv, 18, y_hip, 21, 24, pants, 3)
        boot(cv, 10, 25, shade(boots, 0.8))
        boot(cv, 21, 24, boots)
    elif mode == "slide":
        # body is already lowered by the caller; legs stretched forward
        limb(cv, 15, 25, 24, 27, dark, 3)
        limb(cv, 16, 26, 25, 29, pants, 3)
        boot(cv, 24, 27, shade(boots, 0.8))
        boot(cv, 25, 29, boots)
    else:
        boot(cv, 13, 27 + crouch, boots)
        boot(cv, 18, 27 + crouch, boots)
        cv.rect(12, y_hip, 15, 27 + crouch, pants)
        cv.rect(17, y_hip, 20, 27 + crouch, shade(pants, 0.85))


def draw_arm(cv, st, mode, frame, n, crouch=0):
    sleeve = st["jacket"]
    hi = st["jacket_hi"]
    skin = st["skin"]
    sy = 14 + crouch
    if mode in ("run", "walk"):
        swing = math.sin(frame / n * math.tau)
        ex = 21 + int(round(swing * 2))
        ey = sy + 3
        hand = (23 + int(round(swing * 2)), sy + 6)
        limb(cv, 19, sy, ex, ey, sleeve, 3)
        limb(cv, ex, ey, hand[0], hand[1], shade(sleeve, 0.8), 2)
        cv.rect(hand[0] - 1, hand[1] - 1, hand[0], hand[1], skin)
    elif mode == "melee":
        # thrust forward
        ext = 4 if frame == 0 else 7 if frame == 1 else 5
        limb(cv, 19, sy, 23, sy + 1, hi, 3)
        limb(cv, 23, sy + 1, 25 + ext, sy + 2, sleeve, 2)
        cv.rect(25 + ext, sy + 1, 27 + ext, sy + 3, skin)
    elif mode == "hurt":
        limb(cv, 18, sy, 21, sy + 4, sleeve, 3)
        cv.rect(21, sy + 4, 23, sy + 6, skin)
    else:
        # idle/shoot: forward grip
        recoil = 1 if mode == "shoot" and frame == 0 else 0
        limb(cv, 19 - recoil, sy, 22 - recoil, sy + 2, hi, 3)
        limb(cv, 22 - recoil, sy + 2, 24 - recoil, sy + 3, sleeve, 2)
        cv.rect(24 - recoil, sy + 2, 26 - recoil, sy + 4, skin)
        cv.px(26 - recoil, sy + 3, shade(skin, 0.8))


def draw_survivor(st, mode, frame, n):
    cv = Canvas(32, 32)
    crouch = 4 if mode == "crouch" else 0
    bob = 0
    if mode == "idle":
        bob = 1 if frame in (2, 3) else 0
    elif mode == "shoot":
        bob = 0
    elif mode == "run":
        bob = 0 if frame % 3 else 1
    if mode == "slide":
        crouch = 6
        bob = 3
    # ground shadow
    cv.shadow(7, 29, 27, 30, 90)
    draw_torso(cv, st, bob=bob, crouch=crouch)
    if mode == "die":
        return draw_death(cv, st, frame)
    draw_legs(cv, st, mode, frame, n, crouch)
    draw_head(cv, st, 15, 3 + bob + crouch, hurt=(mode == "hurt"))
    draw_arm(cv, st, mode, frame, n, crouch)
    if mode == "slide":
        # horizontal body: override torso area with a leaning silhouette
        cv.rect(8, 21, 23, 26, st["jacket"])
        cv.rect(8, 21, 23, 22, st["jacket_hi"])
        cv.rect(20, 17, 26, 22, st["skin"])
        cv.rect(20, 16, 25, 18, st["hair"])
        cv.rect(8, 25, 14, 27, st["pants"])
    # grime
    for x, y in [(12, 17), (18, 20), (14, 24), (20, 15)]:
        if cv.get(x, y)[3]:
            cv.px(x, y, shade(cv.get(x, y), 0.72))
    cv.outline(OUT)
    return cv


def draw_death(cv, st, frame):
    skin, jacket, pants, boots = st["skin"], st["jacket"], st["pants"], st["boots"]
    if frame == 0:
        draw_head(cv, st, 15, 4, hurt=True)
        draw_legs(cv, st, "idle", 0, 1)
        draw_arm(cv, st, "hurt", 0, 1)
    elif frame == 1:
        cv.rect(10, 20, 21, 27, jacket)
        cv.rect(11, 26, 15, 29, pants)
        cv.rect(17, 26, 21, 29, pants)
        cv.rect(9, 27, 15, 30, boots)
        draw_head(cv, st, 17, 12, hurt=True)
        cv.rect(21, 22, 24, 23, skin)
    else:
        drop = min(3, frame - 2)
        y = 25 + drop
        cv.rect(7, y, 24, y + 4, jacket)
        cv.rect(7, y, 24, y + 1, st["jacket_hi"])
        cv.rect(23, y - 2, 27, y + 2, skin)
        cv.rect(23, y - 3, 26, y - 1, st["hair"])
        cv.rect(7, y + 3, 16, y + 5, pants)
        cv.rect(5, y + 3, 9, y + 5, boots)
        cv.rect(18, y + 4, 22, y + 6, boots)
        if frame >= 4:
            cv.rect(4, y + 5, 29, y + 6, P["blood_dark"])
            cv.rect(9, y + 6, 24, y + 7, P["blood"])
            cv.px(12, y + 4, P["blood_bright"])
            cv.px(20, y + 3, P["blood"])
    cv.outline(OUT)
    return cv


ANIMS = {
    "idle": (4, ["idle"]),
    "run": (6, ["run"]),
    "shoot": (3, ["shoot"]),
    "melee": (3, ["melee"]),
    "hurt": (2, ["hurt"]),
    "die": (6, ["die"]),
    "crouch": (2, ["crouch"]),
    "slide": (2, ["slide"]),
    "jump": (2, ["jump"]),
}


def gen_characters():
    preview = []
    for cid, st in STYLES.items():
        for anim, (n, modes) in ANIMS.items():
            frames = [draw_survivor(st, modes[0], i, n) for i in range(n)]
            save_sheet(frames, os.path.join(CHARS, f"{cid}_{anim}.png"))
        idle = draw_survivor(st, "idle", 0, 4)
        run = draw_survivor(st, "run", 1, 6)
        preview.append((cid, idle.img))
        preview.append((cid + "_run", run.img))
        # portrait: crop head/shoulders and upscale
        crop = idle.img.crop((7, 2, 25, 20)).resize((36, 36), Image.NEAREST)
        p = Canvas(40, 40, (23, 27, 33, 255))
        p.rect(0, 0, 39, 39, shade(st["jacket"], 0.45))
        p.rect(1, 1, 38, 38, (23, 27, 33, 255))
        p.paste_img = None
        p.img.alpha_composite(crop, (2, 3))
        p.rect(0, 36, 39, 39, st["jacket"])
        p.rect(0, 36, 39, 37, st["jacket_hi"])
        p.rect(0, 0, 39, 0, OUT)
        p.rect(0, 39, 39, 39, OUT)
        p.rect(0, 0, 0, 39, OUT)
        p.rect(39, 0, 39, 39, OUT)
        p.img.save(os.path.join(CHARS, f"{cid}_portrait.png"))
    contact_sheet(preview, os.path.join(ROOT, "build", "preview_characters.png"), scale=4, cols=4)


# ---------------------------------------------------------------- weapons
WEAPON_SPECS = {
    "m9": dict(size=(14, 10), kind="pistol"),
    "ar15": dict(size=(26, 11), kind="rifle"),
    "smg": dict(size=(22, 12), kind="smg"),
    "shotgun": dict(size=(28, 10), kind="shotgun"),
    "sniper": dict(size=(30, 12), kind="sniper"),
    "lmg": dict(size=(28, 14), kind="lmg"),
    "axe": dict(size=(22, 14), kind="axe"),
    "katana": dict(size=(30, 8), kind="katana"),
    "chainsaw": dict(size=(24, 14), kind="chainsaw"),
    "grenade": dict(size=(10, 12), kind="grenade"),
    "molotov": dict(size=(10, 16), kind="molotov"),
    "bile": dict(size=(10, 14), kind="bile"),
    "medkit": dict(size=(14, 12), kind="medkit"),
    "pills": dict(size=(10, 10), kind="pills"),
    "ammo": dict(size=(14, 10), kind="ammo"),
    "gold": dict(size=(14, 8), kind="gold"),
}


def gen_weapon(wid, spec):
    w, h = spec["size"]
    cv = Canvas(w, h)
    kind = spec["kind"]
    metal = P["steel"]
    metal_hi = P["ash"]
    metal_lo = P["coal"]
    wood = P["brown"]
    wood_hi = P["tan"]
    y = h // 2
    if kind == "pistol":
        cv.rect(1, y - 2, w - 3, y, metal)
        cv.rect(1, y - 2, w - 3, y - 1, metal_hi)
        cv.rect(3, y, 5, y + 3, P["coal"])
        cv.rect(2, y + 2, 4, y + 3, wood)
        cv.rect(w - 3, y - 1, w - 1, y, metal_lo)
        cv.px(w - 2, y - 2, P["ash"])
    elif kind == "rifle":
        cv.rect(1, y - 2, 6, y + 1, wood)
        cv.rect(1, y - 2, 5, y - 1, wood_hi)
        cv.rect(5, y - 2, w - 5, y, metal)
        cv.rect(6, y - 2, w - 6, y - 1, metal_hi)
        cv.rect(11, y, 13, y + 3, P["coal"])
        cv.rect(17, y - 3, 20, y - 1, P["coal"])
        cv.rect(w - 5, y - 1, w - 1, y, metal_lo)
        cv.px(w - 2, y - 2, P["ash"])
    elif kind == "smg":
        cv.rect(1, y - 2, 4, y + 1, P["coal"])
        cv.rect(4, y - 2, w - 4, y + 1, metal)
        cv.rect(5, y - 2, w - 5, y - 1, metal_hi)
        cv.rect(7, y + 1, 9, y + 4, P["coal"])
        cv.rect(14, y - 3, 16, y - 1, metal_lo)
        cv.rect(w - 4, y, w - 1, y + 1, metal_lo)
    elif kind == "shotgun":
        cv.rect(1, y - 1, 7, y + 1, wood)
        cv.rect(1, y - 1, 6, y, wood_hi)
        cv.rect(6, y - 2, w - 3, y, metal)
        cv.rect(7, y - 2, w - 4, y - 1, metal_hi)
        cv.rect(11, y + 1, 18, y + 3, wood)
        cv.rect(12, y + 1, 17, y + 2, wood_hi)
        cv.rect(w - 3, y - 1, w - 1, y, metal_lo)
    elif kind == "sniper":
        cv.rect(1, y - 1, 8, y + 1, P["olive_dark"])
        cv.rect(7, y - 2, w - 3, y, metal)
        cv.rect(8, y - 2, w - 4, y - 1, metal_hi)
        cv.rect(11, y - 5, 18, y - 2, P["coal"])
        cv.rect(12, y - 4, 17, y - 3, P["cyan"])
        cv.rect(12, y + 1, 14, y + 3, P["coal"])
        cv.rect(w - 4, y - 1, w - 1, y, metal_lo)
    elif kind == "lmg":
        cv.rect(1, y - 2, 7, y + 1, P["olive_dark"])
        cv.rect(6, y - 3, w - 5, y + 1, metal)
        cv.rect(7, y - 3, w - 6, y - 1, metal_hi)
        cv.rect(10, y + 1, 16, y + 5, P["coal"])
        cv.rect(11, y + 2, 15, y + 4, P["steel"])
        cv.rect(w - 5, y - 2, w - 1, y, metal_lo)
        cv.rect(14, y - 5, 17, y - 3, P["coal"])
    elif kind == "axe":
        cv.rect(2, y + 3, 6, y + 5, wood)
        cv.line([(4, y + 4), (w - 6, y - 2)], wood, 3)
        cv.line([(4, y + 3), (w - 6, y - 3)], wood_hi, 1)
        cv.poly([(w - 8, y - 5), (w - 2, y - 6), (w - 1, y), (w - 7, y + 2)], metal)
        cv.poly([(w - 7, y - 4), (w - 3, y - 5), (w - 3, y - 1)], metal_hi)
        cv.px(w - 2, y - 4, P["blood"])
    elif kind == "katana":
        cv.rect(1, y, 4, y + 3, P["ink"])
        cv.rect(4, y + 1, 7, y + 2, P["gold"])
        cv.line([(7, y + 1), (w - 1, y - 1)], metal_hi, 2)
        cv.line([(7, y + 2), (w - 2, y)], metal, 1)
        cv.px(w - 1, y - 1, P["white"])
        cv.px(w - 2, y - 2, P["ash"])
    elif kind == "chainsaw":
        cv.rect(2, y - 3, 12, y + 4, P["orange"])
        cv.rect(3, y - 3, 11, y - 2, P["orange_light"])
        cv.rect(5, y + 1, 8, y + 3, P["coal"])
        cv.rect(12, y - 2, w - 1, y + 2, metal_lo)
        cv.rect(12, y - 2, w - 2, y - 1, metal_hi)
        for x in range(13, w - 1, 3):
            cv.px(x, y + 2, P["bone"])
            cv.px(x + 1, y - 2, P["bone"])
    elif kind == "grenade":
        cv.ellipse(w // 2, y + 3, 4, 4, P["olive"])
        cv.ellipse(w // 2, y + 3, 3, 3, P["olive_light"])
        cv.rect(w // 2 - 1, y - 3, w // 2 + 1, y - 1, P["steel"])
        cv.rect(w // 2 + 1, y - 3, w // 2 + 3, y - 2, P["ash"])
        cv.px(w // 2, y + 3, P["yellow_dark"])
    elif kind == "molotov":
        cv.rect(3, y, w - 4, h - 2, (86, 116, 82, 255))
        cv.rect(4, y + 1, w - 5, h - 4, (120, 154, 101, 255))
        cv.rect(4, y - 4, w - 5, y, (70, 94, 67, 255))
        cv.rect(w // 2 - 1, y - 7, w // 2, y - 4, P["bone"])
        cv.rect(w // 2 - 2, y - 8, w // 2 + 1, y - 7, P["rust"])
        cv.rect(4, y + 4, w - 5, y + 6, P["orange_light"])
        cv.px(5, y + 3, P["fire"])
    elif kind == "bile":
        cv.rect(2, y, w - 3, h - 2, (70, 83, 43, 255))
        cv.rect(3, y + 1, w - 4, h - 4, (128, 145, 52, 255))
        cv.rect(w // 2 - 1, y - 4, w // 2 + 1, y, P["steel"])
        cv.rect(3, y + 5, w - 4, y + 7, P["bile_light"])
        cv.px(4, y + 4, P["acid_bright"])
    elif kind == "medkit":
        cv.rect(1, y - 3, w - 2, h - 2, (206, 210, 203, 255))
        cv.rect(1, y - 3, w - 2, y - 2, P["white"])
        cv.rect(w // 2 - 3, y - 1, w // 2 + 2, y + 3, P["red"])
        cv.rect(w // 2 - 1, y - 3, w // 2, y + 5, P["red"])
        cv.rect(3, y - 4, 6, y - 2, P["steel"])
    elif kind == "pills":
        cv.rect(1, y - 2, w - 2, h - 2, (200, 120, 44, 255))
        cv.rect(2, y - 1, w - 3, h - 4, P["orange_light"])
        cv.rect(2, y - 4, w - 3, y - 1, P["white"])
        cv.px(w // 2, y - 2, P["red"])
    elif kind == "ammo":
        cv.rect(1, y - 2, w - 2, h - 2, P["olive_dark"])
        cv.rect(2, y - 1, w - 3, h - 4, P["olive"])
        cv.rect(3, y, 5, y + 3, P["gold"])
        cv.rect(6, y, 8, y + 3, P["gold"])
        cv.rect(9, y, 11, y + 3, P["gold"])
    elif kind == "gold":
        cv.poly([(1, h - 2), (w - 2, h - 2), (w - 4, y + 1), (3, y + 1)], P["gold"])
        cv.rect(3, y + 1, w - 4, y + 2, P["fire_white"])
        cv.rect(5, y + 4, 7, y + 5, P["white"])
        cv.rect(9, y + 3, 11, y + 4, P["yellow"])
    cv.outline(OUT)
    return cv


def gen_weapons():
    items = []
    for wid, spec in WEAPON_SPECS.items():
        cv = gen_weapon(wid, spec)
        cv.save(os.path.join(WEAPONS, f"{wid}.png"))
        items.append((wid, cv.img))
    contact_sheet(items, os.path.join(ROOT, "build", "preview_weapons.png"), scale=4, cols=6)


if __name__ == "__main__":
    gen_characters()
    gen_weapons()
    print("characters + weapons generated")
