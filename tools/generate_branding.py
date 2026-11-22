#!/usr/bin/env python3
"""Generate all nas_client branding assets from one vector-like design.

Design: a warm little "home file house" -- a rounded cottage with a heart in
its round window, a tiny antenna with signal arcs, and two device nodes
(green = Samba, blue = FTP) dotted-line connected to it.

Requires Pillow >= 10. Run from anywhere:

    python tools/generate_branding.py

All coordinates below are in a 1000x1000 design space; the renderer maps that
space into any output box, so the same drawing produces the app icon, the
Android adaptive foreground, the splash logo and the README banner.
"""

from __future__ import annotations

import math
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = Path(__file__).resolve().parents[1]
BRAND = ROOT / "assets" / "brand"
RES = ROOT / "android" / "app" / "src" / "main" / "res"

# ---------------------------------------------------------------- palette --
BG_LIGHT = (255, 250, 240)   # top-left of the icon gradient
BG_WARM = (255, 216, 182)    # bottom-right of the icon gradient
LAUNCH_BG = "#FFF6E9"
ADAPTIVE_BG = "#FFE7C8"

ROOF = (214, 91, 48)
ROOF_HI = (240, 143, 94)
BODY = (255, 253, 248)
BODY_EDGE = (239, 210, 178)
WINDOW = (255, 231, 204)
WINDOW_EDGE = (247, 206, 165)
HEART = (236, 121, 105)
FEET = (236, 203, 164)
ANTENNA = (198, 104, 63)
SIGNAL = (222, 146, 100)
NODE_GREEN = (125, 178, 146)
NODE_BLUE = (137, 165, 216)
DOT = (231, 186, 150)
INK = (28, 23, 20)
MUTED = (124, 115, 106)


# --------------------------------------------------------------- helpers ---
def diagonal_gradient(size: int, a: tuple[int, int, int], b: tuple[int, int, int]) -> Image.Image:
    n = 160
    small = Image.new("RGB", (n, n))
    px = small.load()
    for y in range(n):
        for x in range(n):
            t = (x + y) / (2 * (n - 1))
            px[x, y] = tuple(round(v + (w - v) * t) for v, w in zip(a, b))
    return small.resize((size, size), Image.LANCZOS)


def heart_points(cx: float, cy: float, w: float, h: float, n: int = 180):
    pts = []
    for i in range(n):
        t = 2 * math.pi * i / n
        x = 16 * math.sin(t) ** 3
        y = 13 * math.cos(t) - 5 * math.cos(2 * t) - 2 * math.cos(3 * t) - math.cos(4 * t)
        pts.append((cx + x / 16 * w / 2, cy - (y + 2.5) / 17 * h / 2))
    return pts


class Canvas:
    """Maps the 1000x1000 design space into a box on a pixel canvas."""

    def __init__(self, size: int, box=(0, 0, 1000, 1000)):
        self.size = size
        self.img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
        self.k = size / 1000
        self.sx = (box[2] - box[0]) / 1000
        self.sy = (box[3] - box[1]) / 1000
        self.ox, self.oy = box[0], box[1]
        self.scale = min(self.sx, self.sy)

    def p(self, x, y):
        return ((self.ox + x * self.sx) * self.k, (self.oy + y * self.sy) * self.k)

    def box(self, x0, y0, x1, y1):
        return (*self.p(x0, y0), *self.p(x1, y1))

    def pts(self, points):
        return [self.p(x, y) for x, y in points]

    def line(self, points, fill, width, joint="curve"):
        ImageDraw.Draw(self.img).line(self.pts(points), fill=fill, width=self.w(width), joint=joint)

    def w(self, value):
        return max(1, round(value * self.scale * self.k))

    def ellipse(self, bbox, fill=None, outline=None, width=1):
        ImageDraw.Draw(self.img).ellipse(
            self.box(*bbox), fill=fill, outline=outline,
            width=self.w(width) if outline else 1,
        )

    def round_rect(self, bbox, radius, fill=None, outline=None, width=1):
        ImageDraw.Draw(self.img).rounded_rectangle(
            self.box(*bbox), radius=self.w(radius), fill=fill, outline=outline,
            width=self.w(width) if outline else 1,
        )

    def polygon(self, points, fill):
        ImageDraw.Draw(self.img).polygon(self.pts(points), fill=fill)

    def arc(self, bbox, start, end, fill, width):
        ImageDraw.Draw(self.img).arc(self.box(*bbox), start, end, fill=fill, width=self.w(width))

    def overlay(self, layer: Image.Image):
        self.img = Image.alpha_composite(self.img, layer)


# ---------------------------------------------------------------- emblem ---
def emblem(size: int, box=(0, 0, 1000, 1000), nodes: bool = True) -> Image.Image:
    c = Canvas(size, box)

    # Soft ground shadow on its own layer so the blur blends correctly.
    sh = Canvas(size, box)
    sh.ellipse((255, 730, 745, 818), fill=(168, 100, 62, 105))
    blurred = sh.img.filter(ImageFilter.GaussianBlur(c.w(34)))
    c.overlay(blurred)

    d = ImageDraw.Draw(c.img)

    # Dotted links + device nodes sit behind the house.
    if nodes:
        for x0, x1 in ((202, 288), (712, 798)):
            for x in range(x0, x1, 22):
                c.ellipse((x - 5, 512 - 5, x + 5, 512 + 5), fill=(*DOT, 190))
        for cx, color in ((168, NODE_GREEN), (832, NODE_BLUE)):
            c.ellipse((cx - 39, 481, cx + 39, 559), fill=(255, 255, 255, 150))
            c.ellipse((cx - 31, 489, cx + 31, 551), fill=color)
            c.ellipse((cx - 11, 509, cx + 11, 531), fill=(255, 255, 255, 225))

    # Signal arcs above the roof.
    c.arc((414, 158, 586, 330), 212, 328, (*SIGNAL, 205), 13)
    c.arc((368, 112, 632, 372), 218, 322, (*SIGNAL, 130), 11)

    # Antenna.
    c.line([(500, 268), (500, 196)], fill=ANTENNA, width=13)
    c.ellipse((482, 178, 518, 214), fill=ROOF)

    # Gable fill, tucked under the roof strokes so the cottage reads as solid.
    c.polygon([(500, 290), (292, 424), (708, 424)], fill=(243, 176, 133))

    # Cottage body.
    c.round_rect((298, 424, 702, 762), 62, fill=BODY, outline=BODY_EDGE, width=7)
    # A quiet inner highlight along the top of the body.
    c.round_rect((326, 448, 674, 486), 19, fill=(255, 255, 255, 120))

    # Round window + heart.
    c.ellipse((410, 500, 590, 680), fill=WINDOW, outline=WINDOW_EDGE, width=7)
    c.ellipse((426, 516, 574, 664), fill=(255, 244, 226, 150))
    c.polygon(heart_points(500, 588, 112, 104), fill=HEART)

    # Drawer seam + two little feet.
    c.round_rect((356, 706, 644, 716), 5, fill=BODY_EDGE)
    c.round_rect((344, 752, 396, 786), 14, fill=FEET)
    c.round_rect((604, 752, 656, 786), 14, fill=FEET)

    # Gabled roof, drawn last so it overlaps the body like an eave.
    c.line([(266, 442), (500, 258), (734, 442)], fill=ROOF, width=56)
    for x, y in ((266, 442), (500, 258), (734, 442)):
        c.ellipse((x - 28, y - 28, x + 28, y + 28), fill=ROOF)
    c.line([(292, 424), (500, 262), (610, 342)], fill=(*ROOF_HI, 120), width=10)

    # Two tiny sparkles for warmth.
    for sx, sy, r in ((196, 348, 9), (812, 336, 7)):
        c.polygon(
            [(sx, sy - r * 2), (sx + r * 0.55, sy - r * 0.55),
             (sx + r * 2, sy), (sx + r * 0.55, sy + r * 0.55),
             (sx, sy + r * 2), (sx - r * 0.55, sy + r * 0.55),
             (sx - r * 2, sy), (sx - r * 0.55, sy - r * 0.55)],
            fill=(255, 255, 255, 205),
        )

    del d
    return c.img


def icon(size: int = 1024) -> Image.Image:
    s = 2000
    img = diagonal_gradient(s, BG_LIGHT, BG_WARM).convert("RGBA")

    glow = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    ImageDraw.Draw(glow).ellipse((520, -420, 1420, 480), fill=(255, 255, 255, 115))
    img = Image.alpha_composite(img, glow.filter(ImageFilter.GaussianBlur(150)))

    img = Image.alpha_composite(img, emblem(s))

    mask = Image.new("L", (s, s), 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, s - 1, s - 1), radius=round(s * 0.225), fill=255)
    img.putalpha(mask)
    return img.resize((size, size), Image.LANCZOS)


# ----------------------------------------------------------------- banner ---
def _font(path: str, px: int):
    try:
        return ImageFont.truetype(path, px)
    except OSError:
        return ImageFont.load_default()


def banner() -> Image.Image:
    w, h = 1280, 400
    img = diagonal_gradient(max(w, h), (255, 251, 244), (255, 235, 214)).convert("RGBA")
    img = img.crop((0, 0, w, h))

    # A soft warm halo behind the mark.
    glow = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    ImageDraw.Draw(glow).ellipse((-120, -260, 520, 380), fill=(255, 255, 255, 120))
    img = Image.alpha_composite(img, glow.filter(ImageFilter.GaussianBlur(70)))

    mark = icon(300)
    img.alpha_composite(mark, (66, 50))

    d = ImageDraw.Draw(img)
    title_font = _font("C:/Windows/Fonts/segoeuib.ttf", 76)
    d.text((406, 118), "nas_client", font=title_font, fill=INK)

    # Chinese product name as a small warm badge next to the wordmark.
    badge_x = 406 + d.textlength("nas_client", font=title_font) + 26
    badge_font = _font("C:/Windows/Fonts/msyhbd.ttc", 29)
    badge_w = int(d.textlength("近邻盘", font=badge_font)) + 48
    d.rounded_rectangle((badge_x, 136, badge_x + badge_w, 192), radius=28,
                        fill=(255, 240, 224))
    d.text((badge_x + 24, 143), "近邻盘", font=badge_font, fill=ROOF)

    d.text((410, 214), "把身边的网盘，轻轻装进口袋",
           font=_font("C:/Windows/Fonts/msyhbd.ttc", 30), fill=MUTED)
    d.rounded_rectangle((410, 278, 448, 316), radius=19, fill=NODE_GREEN)
    d.rounded_rectangle((458, 278, 496, 316), radius=19, fill=NODE_BLUE)
    d.text((514, 284), "Samba  /  FTP  /  LAN  /  Android",
           font=_font("C:/Windows/Fonts/segoeui.ttf", 24), fill=(150, 118, 96))

    # Hairline at the bottom, in the app's accent colour family.
    d.rounded_rectangle((66, 372, 1214, 376), radius=2, fill=(240, 206, 178))
    return img


# ------------------------------------------------------------------- main ---
def main() -> None:
    BRAND.mkdir(parents=True, exist_ok=True)

    full = icon(1024)
    full.save(BRAND / "icon.png")
    full.resize((512, 512), Image.LANCZOS).save(BRAND / "icon_512.png")
    banner().save(BRAND / "banner.png")

    for folder, px in (("mipmap-mdpi", 48), ("mipmap-hdpi", 72),
                       ("mipmap-xhdpi", 96), ("mipmap-xxhdpi", 144),
                       ("mipmap-xxxhdpi", 192)):
        target = RES / folder
        target.mkdir(parents=True, exist_ok=True)
        full.resize((px, px), Image.LANCZOS).save(target / "ic_launcher.png")

    # Adaptive icon foreground: 432x432, transparent, art kept in the safe zone.
    foreground = emblem(864, (195, 195, 805, 805), nodes=False)
    foreground.resize((432, 432), Image.LANCZOS).save(
        RES / "drawable-nodpi" / "ic_launcher_foreground.png"
    )

    # Splash logo: transparent, no rounded background of its own.
    splash = emblem(768, (60, 60, 940, 940), nodes=False)
    splash.resize((288, 288), Image.LANCZOS).save(RES / "drawable-nodpi" / "launch_logo.png")

    for name in ("values", "values-night"):
        (RES / name / "colors.xml").write_text(
            '<?xml version="1.0" encoding="utf-8"?>\n'
            "<resources>\n"
            f'    <color name="launch_bg">{LAUNCH_BG}</color>\n'
            f'    <color name="ic_launcher_background">{ADAPTIVE_BG}</color>\n'
            "</resources>\n",
            encoding="utf-8",
        )

    print("Branding assets written to", BRAND.relative_to(ROOT), "and android/app/src/main/res/")


if __name__ == "__main__":
    main()
