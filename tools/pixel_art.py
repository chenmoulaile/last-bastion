"""Tiny pixel-art toolkit used by the asset generators.

Everything is drawn at 1x with integer coordinates so the result stays crisp
when Godot imports it with nearest-neighbour filtering.
"""
from __future__ import annotations

import math
import random
from PIL import Image, ImageDraw, ImageFont

OUT = (10, 11, 15, 255)

P = {
    "black": (10, 11, 15, 255),
    "ink": (18, 21, 27, 255),
    "night": (25, 30, 38, 255),
    "coal": (36, 43, 52, 255),
    "slate": (54, 64, 76, 255),
    "steel": (78, 91, 104, 255),
    "ash": (112, 124, 135, 255),
    "smoke": (150, 160, 168, 255),
    "bone": (196, 202, 202, 255),
    "white": (235, 238, 233, 255),
    "skin_dark": (95, 62, 48, 255),
    "skin": (143, 96, 68, 255),
    "skin_light": (188, 137, 96, 255),
    "skin_pale": (201, 180, 151, 255),
    "blood_dark": (57, 12, 16, 255),
    "blood": (112, 22, 28, 255),
    "blood_bright": (168, 34, 38, 255),
    "red": (211, 58, 52, 255),
    "red_hot": (255, 96, 74, 255),
    "rust": (128, 67, 36, 255),
    "brown_dark": (60, 40, 28, 255),
    "brown": (92, 62, 38, 255),
    "tan": (141, 104, 63, 255),
    "sand": (184, 149, 92, 255),
    "yellow_dark": (99, 71, 24, 255),
    "yellow": (201, 154, 48, 255),
    "gold": (241, 195, 82, 255),
    "olive_dark": (39, 47, 31, 255),
    "olive": (65, 78, 45, 255),
    "olive_light": (99, 113, 62, 255),
    "green_dark": (24, 37, 29, 255),
    "green": (45, 68, 44, 255),
    "green_light": (78, 105, 58, 255),
    "toxic_dark": (55, 66, 26, 255),
    "toxic": (124, 139, 44, 255),
    "acid": (172, 196, 55, 255),
    "acid_bright": (210, 232, 96, 255),
    "bile": (151, 170, 40, 255),
    "bile_light": (196, 209, 71, 255),
    "blue_dark": (23, 36, 50, 255),
    "blue": (35, 61, 83, 255),
    "blue_light": (55, 96, 122, 255),
    "cyan": (74, 148, 158, 255),
    "cyan_light": (127, 207, 201, 255),
    "purple_dark": (43, 28, 51, 255),
    "purple": (75, 48, 87, 255),
    "purple_light": (111, 74, 124, 255),
    "orange": (205, 108, 40, 255),
    "orange_light": (238, 158, 58, 255),
    "fire": (255, 198, 64, 255),
    "fire_white": (255, 244, 190, 255),
}


def rgba(c, a=255):
    if isinstance(c, tuple):
        if len(c) == 4:
            return c
        return (c[0], c[1], c[2], a)
    return (c, c, c, a)


def shade(c, factor):
    c = rgba(c)
    return (
        max(0, min(255, int(c[0] * factor))),
        max(0, min(255, int(c[1] * factor))),
        max(0, min(255, int(c[2] * factor))),
        c[3],
    )


def mix(a, b, t):
    a, b = rgba(a), rgba(b)
    return tuple(int(a[i] * (1 - t) + b[i] * t) for i in range(4))


class Canvas:
    def __init__(self, w, h, bg=None):
        self.w = w
        self.h = h
        self.img = Image.new("RGBA", (w, h), rgba(bg) if bg else (0, 0, 0, 0))
        self.d = ImageDraw.Draw(self.img)

    def px(self, x, y, c):
        if 0 <= x < self.w and 0 <= y < self.h:
            c = rgba(c)
            if c[3] >= 255:
                self.img.putpixel((int(x), int(y)), c)
            elif c[3] > 0:
                dst = self.img.getpixel((int(x), int(y)))
                a = c[3] / 255.0
                out = (
                    int(c[0] * a + dst[0] * (1 - a)),
                    int(c[1] * a + dst[1] * (1 - a)),
                    int(c[2] * a + dst[2] * (1 - a)),
                    min(255, int(c[3] + dst[3] * (1 - a))),
                )
                self.img.putpixel((int(x), int(y)), out)

    def get(self, x, y):
        if 0 <= x < self.w and 0 <= y < self.h:
            return self.img.getpixel((int(x), int(y)))
        return (0, 0, 0, 0)

    def _shape(self, kind, args, c, fill=True):
        c = rgba(c)
        if c[3] >= 255:
            d = self.d
            if kind == "rect":
                d.rectangle(args, fill=c) if fill else d.rectangle(args, outline=c)
            elif kind == "ellipse":
                d.ellipse(args, fill=c) if fill else d.ellipse(args, outline=c)
            elif kind == "line":
                d.line(args[0], fill=c, width=args[1])
            elif kind == "poly":
                d.polygon(args, fill=c)
            elif kind == "text":
                d.text(args[0], args[1], font=args[2], fill=c)
        elif c[3] > 0:
            layer = Image.new("RGBA", (self.w, self.h), (0, 0, 0, 0))
            d = ImageDraw.Draw(layer)
            if kind == "rect":
                d.rectangle(args, fill=c) if fill else d.rectangle(args, outline=c)
            elif kind == "ellipse":
                d.ellipse(args, fill=c) if fill else d.ellipse(args, outline=c)
            elif kind == "line":
                d.line(args[0], fill=c, width=args[1])
            elif kind == "poly":
                d.polygon(args, fill=c)
            elif kind == "text":
                d.text(args[0], args[1], font=args[2], fill=c)
            self.img.alpha_composite(layer)

    def rect(self, x0, y0, x1, y1, c, fill=True):
        if x1 < x0:
            x0, x1 = x1, x0
        if y1 < y0:
            y0, y1 = y1, y0
        self._shape("rect", [x0, y0, x1, y1], c, fill)

    def ellipse(self, cx, cy, rx, ry, c, fill=True):
        self._shape("ellipse", [cx - rx, cy - ry, cx + rx, cy + ry], c, fill)

    def line(self, pts, c, width=1):
        self._shape("line", [pts, width], c, True)

    def poly(self, pts, c):
        self._shape("poly", pts, c, True)

    def text(self, xy, s, font, c):
        self._shape("text", [xy, s, font], c, True)

    def outline(self, c=OUT, diagonal=False):
        src = self.img.load()
        w, h = self.w, self.h
        mask = [[src[x, y][3] > 0 for y in range(h)] for x in range(w)]
        offs = [(-1, 0), (1, 0), (0, -1), (0, 1)]
        if diagonal:
            offs += [(-1, -1), (1, -1), (-1, 1), (1, 1)]
        for x in range(w):
            for y in range(h):
                if mask[x][y]:
                    continue
                for dx, dy in offs:
                    nx, ny = x + dx, y + dy
                    if 0 <= nx < w and 0 <= ny < h and mask[nx][ny]:
                        self.px(x, y, c)
                        break
        return self

    def shadow(self, x0, y0, x1, y1, alpha=80):
        self.rect(x0, y0, x1, y1, (5, 7, 10, alpha))

    def noise(self, c, density=0.08, box=None, seed=1, alpha=None):
        rnd = random.Random(seed)
        x0, y0, x1, y1 = box if box else (0, 0, self.w - 1, self.h - 1)
        for y in range(y0, y1 + 1):
            for x in range(x0, x1 + 1):
                if rnd.random() < density:
                    col = rgba(c)
                    if alpha is not None:
                        col = (col[0], col[1], col[2], alpha)
                    if self.get(x, y)[3] > 0:
                        self.px(x, y, col)

    def paste(self, other, x, y):
        self.img.alpha_composite(other.img, (x, y))
        return self

    def scaled(self, factor):
        return self.img.resize((self.w * factor, self.h * factor), Image.NEAREST)

    def save(self, path):
        self.img.save(path)


def load_font(size, bold=False):
    base = "C:/Users/chenk/AppData/Local/Temp/opencode/"
    name = "silkscreen_bold.ttf" if bold else "silkscreen.ttf"
    try:
        return ImageFont.truetype(base + name, size)
    except Exception:
        return ImageFont.load_default()


def sheet(frames):
    """Horizontally concatenate equal-sized canvases into one sheet."""
    if not frames:
        return None
    w, h = frames[0].w, frames[0].h
    out = Image.new("RGBA", (w * len(frames), h), (0, 0, 0, 0))
    for i, f in enumerate(frames):
        out.alpha_composite(f.img, (i * w, 0))
    return out


def save_sheet(frames, path):
    im = sheet(frames)
    if im:
        im.save(path)


def contact_sheet(items, path, scale=4, bg=(24, 28, 34, 255), cols=6, cell_w=None, cell_h=None, label=True):
    """items: list of (name, PIL.Image)."""
    if not items:
        return
    font = load_font(8)
    cw = cell_w or (max(im.width for _, im in items) * scale + 8)
    ch = cell_h or (max(im.height for _, im in items) * scale + 18)
    rows = math.ceil(len(items) / cols)
    out = Image.new("RGBA", (cw * cols, ch * rows), bg)
    d = ImageDraw.Draw(out)
    for i, (name, im) in enumerate(items):
        cx = (i % cols) * cw
        cy = (i // cols) * ch
        im2 = im.resize((im.width * scale, im.height * scale), Image.NEAREST)
        ox = cx + (cw - im2.width) // 2
        oy = cy + 14
        out.alpha_composite(im2, (ox, oy))
        if label:
            d.text((cx + 3, cy + 2), name[:22], font=font, fill=(190, 198, 205, 255))
    out.save(path)


def dither_rect(cv, x0, y0, x1, y1, c1, c2, seed=1, density=0.5):
    rnd = random.Random(seed)
    for y in range(y0, y1 + 1):
        for x in range(x0, x1 + 1):
            cv.px(x, y, c1 if rnd.random() < density else c2)
