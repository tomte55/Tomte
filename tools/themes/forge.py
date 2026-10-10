"""Builds the Forge theme's art and title font (Themes/Forge.lua, docs/superpowers/specs/2026-10-10-tomte-themes-design.md).

Writes Media/Theme/Forge/{Grain,Runes,Flourish,Glow}.tga and, with --fonts-src, Media/Fonts/Grenze-SemiBold.ttf +
OFL-Grenze.txt under the addon root.

  python tools/themes/forge.py [--fonts-src DIR] [--preview OUT.png]

DIR holds Google Fonts' variable Grenze and its license: Grenze[wght].ttf, OFL.txt
(https://github.com/google/fonts/tree/main/ofl/grenze). --preview renders a sample panel with the palette read from
Themes/Forge.lua. Needs Pillow (and fontTools for the font). Output is the same on every run (fixed seed).
"""

import argparse
import math
import random
import re
import shutil
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parent.parent.parent
OUT = ROOT / "Media" / "Theme" / "Forge"
FONTS = ROOT / "Media" / "Fonts"

SIZES = {"Grain": (256, 256), "Runes": (512, 512), "Flourish": (256, 16), "Glow": (256, 256)}


def grain(size=256, seed=55):
    """Seamless hammered metal: overlapping shallow dents lit from the top-left, over fine noise.

    Grey around 128 with alpha growing with the distance from 128 (like Cartographer's grain), so it lightens and
    darkens whatever fill is under it."""
    rnd = random.Random(seed)
    val = [0.0] * (size * size)
    # Each dent overwrites what's under it (the newest blow flattens the older ones), with a soft rim.
    for _ in range(260):
        cx, cy = rnd.uniform(0, size), rnd.uniform(0, size)
        rad = rnd.uniform(6, 15)
        amp = rnd.uniform(26, 40)
        r = int(rad) + 1
        for oy in range(-r, r + 1):
            for ox in range(-r, r + 1):
                d = math.hypot(ox, oy) / rad
                if d >= 1:
                    continue
                # Slope of a bowl toward the light: the far (bottom-right) wall catches it.
                shade = amp * (ox + oy) / (rad * 1.41)
                w = min(1.0, (1 - d) * 3)  # soft edge
                i = ((int(cy) + oy) % size) * size + (int(cx) + ox) % size
                val[i] = val[i] * (1 - w) + shade * w
    noise = Image.new("L", (size, size))
    noise.putdata([max(0, min(255, int(128 + v + rnd.gauss(0, 12)))) for v in val])
    # Tile 3x3, blur, take the middle: the blur wraps around, so the result tiles.
    big = Image.new("L", (size * 3, size * 3))
    for x in range(3):
        for y in range(3):
            big.paste(noise, (x * size, y * size))
    tile = big.filter(ImageFilter.GaussianBlur(0.7)).crop((size, size, size * 2, size * 2))
    out = Image.new("RGBA", (size, size))
    px = []
    for v in tile.get_flattened_data():
        d = v - 128
        a = max(0, min(255, int(abs(d) * 1.6)))
        c = 255 if d > 0 else 0
        px.append((c, c, c, a))
    out.putdata(px)
    return out


# Runes as strokes in a box: u across (-0.5..0.5), v up (0..1). Elder Futhark shapes.
RUNES = [
    [((-.25, 0), (-.25, 1)), ((-.25, .55), (.3, .85)), ((-.25, .8), (.3, 1))],  # fehu
    [((-.25, 0), (-.25, 1)), ((-.25, .78), (.25, .52), (-.25, .26))],  # thurisaz
    [((-.25, 0), (-.25, 1)), ((-.25, 1), (.25, .78)), ((-.25, .74), (.25, .52))],  # ansuz
    [((-.25, 0), (-.25, 1)), ((-.25, 1), (.25, .78), (-.25, .56), (.25, 0))],  # raidho
    [((.25, 1), (-.25, .5), (.25, 0))],  # kaunan
    [((-.3, 0), (.3, 1)), ((-.3, 1), (.3, 0))],  # gebo
    [((-.28, 0), (-.28, 1)), ((.28, 0), (.28, 1)), ((-.28, .62), (.28, .38))],  # hagalaz
    [((0, 0), (0, 1)), ((-.3, .62), (.3, .38))],  # nauthiz
    [((0, 0), (0, 1)), ((-.3, .7), (0, 1), (.3, .7))],  # tiwaz
    [((0, 0), (0, 1)), ((-.3, 1), (0, .62), (.3, 1))],  # algiz
    [((-.3, 0), (.3, 1), (.3, 0), (-.3, 1), (-.3, 0))],  # dagaz
    [((-.3, 0), (0, .3), (.3, 0)), ((0, .3), (-.3, .65), (0, 1), (.3, .65), (0, .3))],  # othala
    [((-.25, 0), (-.25, 1)), ((.25, 0), (.25, 1)), ((-.25, 1), (.25, .6)), ((.25, 1), (-.25, .6))],  # mannaz
    [((0, 0), (0, 1)), ((0, .5), (.3, .75)), ((0, .5), (-.3, .25))],  # sowilo-ish stave
]

T = math.sqrt(2) - 1


def octagon(r):
    """The quarter of a regular octagon of radius r around the corner, as offsets (dx, dy) from it."""
    return [(r, -4), (r, r * T), (r * T, r), (-4, r)]


def runes(size=512, fade=520, seed=11):
    """Octagonal bands around the bottom-right corner, one holding a row of runes and one a row of rivets, white,
    fading out with the radius."""
    ss = 4
    n = size * ss
    img = Image.new("L", (n, n))
    dr = ImageDraw.Draw(img)
    c = n - 1

    def P(dx, dy):
        return (c - dx * ss, c - dy * ss)

    def line(pts, w=1.2):
        dr.line([P(*p) for p in pts], fill=255, width=max(1, int(w * ss)), joint="curve")

    for r in (64, 86, 118, 158, 184, 222, 256, 300, 352, 400, 456):
        line(octagon(r), 1.3 if r in (118, 158, 300, 352) else 1.1)

    # Runes on the bands 118..158 and 300..352: placed per straight segment, kept off the bends.
    rnd = random.Random(seed)

    def rune_band(mid, h, step):
        pts = octagon(mid)
        pts[0], pts[-1] = (mid, 0), (0, mid)
        for (x0, y0), (x1, y1) in zip(pts, pts[1:]):
            seg = math.hypot(x1 - x0, y1 - y0)
            tx, ty = (x1 - x0) / seg, (y1 - y0) / seg
            nx, ny = ty, -tx  # outward (away from the corner)
            if nx * (x0 + x1) + ny * (y0 + y1) < 0:
                nx, ny = -nx, -ny
            count = int((seg - step * 0.7) // step)
            for k in range(count):
                s = (seg - (count - 1) * step) / 2 + k * step
                bx, by = x0 + tx * s, y0 + ty * s
                for stroke in rnd.choice(RUNES):
                    q = [(bx + tx * u * h * 0.7 + nx * (v - 0.5) * h, by + ty * u * h * 0.7 + ny * (v - 0.5) * h)
                         for u, v in stroke]
                    line(q, 1.25)

    rune_band(138, 24, 20)
    rune_band(326, 30, 26)

    # Rivets halfway between 184 and 222.
    pts = octagon(203)
    pts[0], pts[-1] = (203, 0), (0, 203)
    for (x0, y0), (x1, y1) in zip(pts, pts[1:]):
        seg = math.hypot(x1 - x0, y1 - y0)
        count = max(1, int(seg // 24))
        for k in range(count + 1):
            if k == 0 and (x0, y0) != pts[0]:
                continue  # the bend already has one
            f = k / count
            x, y = P(x0 + (x1 - x0) * f, y0 + (y1 - y0) * f)
            rr = 2.4 * ss
            dr.ellipse((x - rr, y - rr, x + rr, y + rr), fill=255)

    alpha = img.resize((size, size), Image.LANCZOS)
    fall = Image.new("L", (size, size))
    fp = fall.load()
    for y in range(size):
        for x in range(size):
            r = math.hypot(size - 1 - x, size - 1 - y)
            fp[x, y] = int(255 * max(0.0, 1 - r / fade) ** 0.8)
    alpha = ImageChops.multiply(alpha, fall)
    out = Image.new("RGBA", (size, size), (255, 255, 255, 0))
    out.putalpha(alpha)
    return out


def glow(size=256):
    """Soft spot fading out from the center. Ember-colored: UI.Panel draws the glow untinted."""
    img = Image.new("L", (size, size))
    pix = img.load()
    c = (size - 1) / 2
    for y in range(size):
        for x in range(size):
            d = math.hypot(x - c, y - c) / c
            pix[x, y] = int(255 * max(0.0, 1 - d) ** 2)
    out = Image.new("RGBA", (size, size), (255, 176, 112, 0))
    out.putalpha(img)
    return out


def flourish(w=256, h=16):
    """A hex nut in the middle, two smaller studs on each side, hairlines fading towards both ends, white."""
    ss = 4
    W, H = w * ss, h * ss
    img = Image.new("L", (W, H))
    dr = ImageDraw.Draw(img)
    cx, cy = W / 2, H / 2

    def hexagon(x, y, r):
        return [(x + r * math.cos(math.pi / 3 * k), y + r * math.sin(math.pi / 3 * k)) for k in range(6)]

    dr.polygon(hexagon(cx, cy, 5.5 * ss), fill=255)
    dr.ellipse((cx - 1.6 * ss, cy - 1.6 * ss, cx + 1.6 * ss, cy + 1.6 * ss), fill=0)  # the bolt hole
    for side in (-1, 1):
        for off, r in ((12, 2.2), (19, 1.6)):
            x = cx + side * off * ss
            dr.polygon([(x - r * ss, cy), (x, cy - r * ss), (x + r * ss, cy), (x, cy + r * ss)], fill=255)
    pix = img.load()
    start = 24 * ss
    for x in range(W):
        ax = abs(x - cx)
        if ax < start:
            continue
        v = max(0.0, 1.0 - (ax - start) / (cx - start)) ** 1.3
        for y in range(H):
            if abs(y + 0.5 - cy) <= 0.5 * ss:
                pix[x, y] = int(255 * v)
    alpha = img.resize((w, h), Image.LANCZOS)
    out = Image.new("RGBA", (w, h), (255, 255, 255, 0))
    out.putalpha(alpha)
    return out


def fonts(src):
    from fontTools.ttLib import TTFont
    from fontTools.varLib import instancer

    FONTS.mkdir(parents=True, exist_ok=True)
    grenze = instancer.instantiateVariableFont(TTFont(src / "Grenze[wght].ttf"), {"wght": 600},
                                               updateFontNames=True)
    grenze.save(FONTS / "Grenze-SemiBold.ttf")
    shutil.copy(src / "OFL.txt", FONTS / "OFL-Grenze.txt")


def verify():
    for name, size in SIZES.items():
        img = Image.open(OUT / (name + ".tga"))
        assert img.size == size and img.mode == "RGBA", (name, img.size, img.mode)
        assert img.getchannel("A").getextrema()[1] > 0, name + " is empty"
    runes_img = Image.open(OUT / "Runes.tga")
    assert runes_img.getpixel((511, 511))[3] == 0 and runes_img.getpixel((0, 0))[3] == 0, "corner art bounds"
    font = FONTS / "Grenze-SemiBold.ttf"
    if font.exists():
        from fontTools.ttLib import TTFont

        assert "fvar" not in TTFont(font), "Grenze is still variable"
    print("ok: Forge art" + (" and font" if font.exists() else ""))


# Preview ---------------------------------------------------------------------------------------------------------


def palette():
    text = (ROOT / "Themes" / "Forge.lua").read_text(encoding="utf-8")
    colors = {}
    for role, hexv, alpha in re.findall(r'(\w+) = Hex\("#(\w{6})"(?:, ([\d.]+))?\)', text):
        colors[role] = tuple(int(hexv[i:i + 2], 16) for i in (0, 2, 4)) + (float(alpha or 1),)
    m = re.search(r"surface = \{ 0, 0, 0, ([\d.]+) \}", text)
    colors["surface"] = (0, 0, 0, float(m.group(1)))
    art = {k: float(v) for k, v in re.findall(r"\b(glow|contours|grain|vignette|rule) = ([\d.]+)", text)}
    return colors, art


def tinted(img, rgb, alpha):
    out = Image.new("RGBA", img.size, rgb + (0,))
    out.putalpha(img.getchannel("A").point(lambda a: int(a * alpha)))
    return out


def preview(path):
    from PIL import ImageFont

    col, art = palette()
    W, H = 640, 400
    rgb = lambda role: col[role][:3]
    panel = Image.new("RGBA", (W, H))
    top, bot = rgb("bgTop"), rgb("bgBottom")
    d = ImageDraw.Draw(panel)
    for y in range(H):
        f = y / (H - 1)
        d.line([(0, y), (W, y)], fill=tuple(int(top[i] + (bot[i] - top[i]) * f) for i in range(3)) + (255,))
    g = Image.open(OUT / "Glow.tga").crop((128, 128, 256, 256)).resize((int(W * 0.7), int(H * 0.8)))
    g.putalpha(g.getchannel("A").point(lambda a: int(a * art["glow"])))
    panel.alpha_composite(g)
    panel.alpha_composite(tinted(Image.open(OUT / "Runes.tga"), rgb("contour"), art["contours"]),
                          (W - 512, H - 512) if H >= 512 else (W - 512, 0), (0, 512 - H) if H < 512 else (0, 0))
    gr = Image.open(OUT / "Grain.tga")
    gr.putalpha(gr.getchannel("A").point(lambda a: int(a * art["grain"])))
    for x in range(0, W, 256):
        for y in range(0, H, 256):
            panel.alpha_composite(gr, (x, y))
    vig = Image.new("RGBA", (W, H))
    vp = vig.load()
    for y in range(H):
        for x in range(W):
            e = min(x, y, W - 1 - x, H - 1 - y)
            if e < 26:
                vp[x, y] = (0, 0, 0, int(255 * art["vignette"] * (1 - e / 26)))
    panel.alpha_composite(vig)
    d = ImageDraw.Draw(panel)
    d.rectangle((0, 0, W - 1, H - 1), outline=rgb("frameDark") + (255,), width=2)
    fr = rgb("frame") + (int(255 * art["rule"]),)
    d.rectangle((5, 5, W - 6, H - 6), outline=fr, width=1)

    title_font = ImageFont.truetype(str(FONTS / "Grenze-SemiBold.ttf"), 26)
    body = ImageFont.truetype("C:/Windows/Fonts/arial.ttf", 14)  # stand-in for the client's Friz Quadrata
    small = ImageFont.truetype("C:/Windows/Fonts/arial.ttf", 12)
    d.text((W / 2, 30), "The Great Forge", font=title_font, fill=rgb("heading"), anchor="mt")
    fl = tinted(Image.open(OUT / "Flourish.tga").resize((160, 10), Image.LANCZOS), rgb("frame"), 0.8)
    panel.alpha_composite(fl, (W // 2 - 80, 64))

    y = 92
    rows = [("Thorium Bar", "128", "text"), ("Ironforge reputation", "Revered", "text"),
            ("Dark Iron Ore", "34", "text")]
    for i, (name, val, role) in enumerate(rows):
        if i == 1:
            hv = Image.new("RGBA", (W - 60, 24), rgb("hover") + (int(255 * col["hover"][3]),))
            panel.alpha_composite(hv, (30, y - 4))
        d.text((40, y), name, font=body, fill=rgb(role))
        d.text((W - 40, y), val, font=body, fill=rgb("text"), anchor="ra")
        y += 26
    d.text((40, y), "Muted: last crafted 3 days ago", font=small, fill=rgb("textMuted"))
    d.text((40, y + 18), "Faint: hint text, keybind notes", font=small, fill=rgb("textFaint"))
    y += 46
    d.text((40, y), "Smelting progress", font=body, fill=rgb("heading"))
    d.text((W - 40, y), "62%", font=body, fill=rgb("accent"), anchor="ra")
    y += 22
    bw = W - 80


    panel.alpha_composite(Image.new("RGBA", (bw, 7), (0, 0, 0, 102)), (40, y))
    a, b = rgb("accentDeep"), rgb("accent")
    fw = int(bw * 0.62)
    for x in range(fw):
        f = x / max(1, fw - 1)
        d.line([(40 + x, y + 1), (40 + x, y + 6)], fill=tuple(int(a[i] + (b[i] - a[i]) * f) for i in range(3)))
    d.line([(40, y), (40 + bw, y)], fill=(0, 0, 0, 153))
    y += 22
    box = Image.new("RGBA", (bw, 70), (0, 0, 0, int(255 * col["surface"][3])))
    panel.alpha_composite(box, (40, y))
    d.rectangle((40, y, 40 + bw - 1, y + 69), outline=rgb("frame") + (int(255 * 0.35),))
    d.text((52, y + 10), "Surface box: weekly vault slot", font=body, fill=rgb("text"))
    x = 52
    for word, role in (("Ready", "success"), ("Expiring", "warning"), ("Failed", "danger"), ("Accent", "accent")):
        d.text((x, y + 40), word, font=body, fill=rgb(role))
        x += body.getlength(word) + 24
    Path(path).parent.mkdir(parents=True, exist_ok=True)
    panel.convert("RGB").save(path)
    print("preview:", path)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--fonts-src", type=Path)
    ap.add_argument("--preview", type=Path)
    args = ap.parse_args()
    OUT.mkdir(parents=True, exist_ok=True)
    grain().save(OUT / "Grain.tga")
    runes().save(OUT / "Runes.tga")
    flourish().save(OUT / "Flourish.tga")
    glow().save(OUT / "Glow.tga")
    if args.fonts_src:
        fonts(args.fonts_src)
    verify()
    if args.preview:
        preview(args.preview)


if __name__ == "__main__":
    main()
