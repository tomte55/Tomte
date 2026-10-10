"""Builds the Emerald Dream theme's art and title font (Themes/Emerald.lua).

Writes Media/Theme/Emerald/{Grain,Vines,Flourish}.tga and Media/Fonts/UncialAntiqua-Regular.ttf + its OFL text.

  python tools/themes/emerald.py --fonts-src DIR

DIR holds Google Fonts' UncialAntiqua-Regular.ttf and OFL.txt (https://github.com/google/fonts, ofl/uncialantiqua).
Needs Pillow and fontTools. Output is the same on every run (fixed seeds).
"""

import argparse
import math
import random
import shutil
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parent.parent.parent
OUT = ROOT / "Media" / "Theme" / "Emerald"
FONTS = ROOT / "Media" / "Fonts"


def _seamless_noise(size, rnd, sigma, blur):
    """Gaussian noise around 128, blurred with wrap-around (tile 3x3, blur, take the middle) so it tiles."""
    base = Image.new("L", (size, size))
    base.putdata([max(0, min(255, int(rnd.gauss(128, sigma)))) for _ in range(size * size)])
    big = Image.new("L", (size * 3, size * 3))
    for x in range(3):
        for y in range(3):
            big.paste(base, (x * size, y * size))
    big = big.filter(ImageFilter.GaussianBlur(blur))
    return big.crop((size, size, size * 2, size * 2))


def grain(size=256, seed=23):
    """Mossy grain: fine noise over soft blotches, grey around 128 with alpha growing with the distance from 128
    (lightens and darkens; drawn untinted)."""
    rnd = random.Random(seed)
    fine = _seamless_noise(size, rnd, 46, 0.6)
    mottle = _seamless_noise(size, rnd, 90, 6)
    # The blotches are faint after the blur: stretch them back out around 128.
    mottle = mottle.point(lambda v: max(0, min(255, int(128 + (v - 128) * 9))))
    out = Image.new("RGBA", (size, size))
    px = []
    for f, m in zip(fine.get_flattened_data(), mottle.get_flattened_data()):
        d = (f - 128) * 0.75 + (m - 128) * 0.5
        a = max(0, min(255, int(abs(d) * 1.5)))
        c = 255 if d > 0 else 0
        px.append((c, c, c, a))
    out.putdata(px)
    return out


def _leaf(draw, x, y, ang, length, width, lw, ss):
    """Outlined leaf from its stalk at (x, y) pointing along ang, with a midrib and a few side veins."""
    ca, sa = math.cos(ang), math.sin(ang)
    nx, ny = -sa, ca
    steps = 24
    left, right = [], []
    for i in range(steps + 1):
        t = i / steps
        w = width * math.sin(math.pi * t) ** 0.9 * (1 - 0.35 * t)
        px, py = x + ca * length * t, y + sa * length * t
        left.append((px + nx * w, py + ny * w))
        right.append((px - nx * w, py - ny * w))
    outline = left + right[::-1] + [left[0]]
    draw.line([(a * ss, b * ss) for a, b in outline], fill=255, width=max(1, int(lw * ss)), joint="curve")
    tip = (x + ca * length, y + sa * length)
    draw.line([(x * ss, y * ss), (tip[0] * ss, tip[1] * ss)], fill=200, width=max(1, int(lw * 0.8 * ss)))
    for t in (0.3, 0.5, 0.7):
        bx, by = x + ca * length * t, y + sa * length * t
        w = width * math.sin(math.pi * t) ** 0.9 * (1 - 0.35 * t) * 0.8
        for side in (1, -1):
            ex = bx + ca * length * 0.12 + nx * w * side
            ey = by + sa * length * 0.12 + ny * w * side
            draw.line([(bx * ss, by * ss), (ex * ss, ey * ss)], fill=150, width=max(1, int(lw * 0.6 * ss)))


def _vine(draw, rnd, x, y, ang, length, lw, ss, turn=None, leaves=True, depth=0):
    """A stem walking from (x, y) with a gently wandering curve that tightens into a curl at its end. Leaves and
    small side tendrils grow along it."""
    step = 2.0
    n = int(length / step)
    turn = turn or rnd.choice((1, -1))
    wobble = rnd.uniform(0, math.tau)
    pts = [(x, y)]
    next_leaf = rnd.uniform(22, 34)
    side = rnd.choice((1, -1))
    travelled = 0.0
    branched = False
    for i in range(n):
        t = i / n
        # Wander early, curl hard at the end (curvature grows like a spiral's).
        k = 0.007 * math.sin(wobble + t * 5) + turn * (0.002 + 0.81 * max(0.0, t - 0.74) ** 1.6)
        ang += k * step
        x += math.cos(ang) * step
        y += math.sin(ang) * step
        pts.append((x, y))
        travelled += step
        if leaves and travelled >= next_leaf and t < 0.8:
            travelled = 0.0
            next_leaf = rnd.uniform(28, 42)
            la = ang + side * rnd.uniform(0.6, 1.0)
            size = (1 - t * 0.6) * rnd.uniform(19, 27)
            _leaf(draw, x, y, la, size, size * 0.38, lw * 0.85, ss)
            side = -side
        if depth == 0 and not branched and 0.3 < t < 0.6 and rnd.random() < 0.02:
            branched = True
            _vine(draw, rnd, x, y, ang - turn * rnd.uniform(0.7, 1.1), length * rnd.uniform(0.25, 0.4), lw * 0.75,
                ss, -turn, leaves=rnd.random() < 0.5, depth=1)
    # Taper: thick at the root, thin at the curl.
    for i in range(len(pts) - 1):
        t = i / len(pts)
        w = lw * (1.2 - 0.6 * t)
        a, b = pts[i], pts[i + 1]
        draw.line([(a[0] * ss, a[1] * ss), (b[0] * ss, b[1] * ss)], fill=255, width=max(1, int(w * ss)))


def vines(size=512, fade=500, seed=5):
    """Curling vines with veined leaves growing out of the bottom-right corner, white, fading out with the radius."""
    ss = 4
    rnd = random.Random(seed)
    img = Image.new("L", (size * ss, size * ss))
    draw = ImageDraw.Draw(img)
    c = size - 1
    specs = [  # start on the edges, direction, length, curl direction (1 = clockwise on screen)
        ((c + 4, c - 40), math.pi * 1.04, 470, 1),
        ((c - 30, c + 4), math.pi * 1.36, 430, -1),
        ((c + 4, c - 190), math.pi * 1.10, 290, -1),
        ((c - 200, c + 4), math.pi * 1.44, 270, 1),
    ]
    for (x, y), ang, length, turn in specs:
        _vine(draw, rnd, x, y, ang, length, 1.3, ss, turn)
    alpha = img.resize((size, size), Image.LANCZOS)
    # Fade with the distance from the corner.
    mask = Image.new("L", (size, size))
    mp = mask.load()
    for y in range(size):
        for x in range(size):
            r = math.hypot(c - x, c - y)
            mp[x, y] = int(255 * max(0.0, 1 - r / fade) ** 0.7)
    alpha = ImageChops.multiply(alpha, mask)
    out = Image.new("RGBA", (size, size), (255, 255, 255, 0))
    out.putalpha(alpha)
    return out


def flourish(w=256, h=16):
    """A small leaf pair in the middle with a hairline vine fading towards both ends, white."""
    ss = 4
    img = Image.new("L", (w * ss, h * ss))
    draw = ImageDraw.Draw(img)
    cx, cy = w / 2, h / 2
    # Hairline with a slow wave, fading out.
    for side in (1, -1):
        prev = None
        for i in range(0, 118):
            x = cx + side * (12 + i)
            y = cy + 1.2 * math.sin(i / 9.0)
            v = int(255 * max(0.0, 1 - i / 118) ** 1.3)
            if prev:
                draw.line([(prev[0] * ss, prev[1] * ss), (x * ss, y * ss)], fill=v, width=int(1.0 * ss))
            prev = (x, y)
    # Two leaves pointing out from the center, a dot between them.
    for side in (1, -1):
        ang = 0 if side == 1 else math.pi
        pts = []
        for i in range(25):
            t = i / 24
            pts.append((cx + side * 1.5 + math.cos(ang) * 12 * t, cy - 2.6 * math.sin(math.pi * t)))
        for i in range(24, -1, -1):
            t = i / 24
            pts.append((cx + side * 1.5 + math.cos(ang) * 12 * t, cy + 2.6 * math.sin(math.pi * t)))
        draw.polygon([(a * ss, b * ss) for a, b in pts], fill=255)
    r = 1.6 * ss
    draw.ellipse((cx * ss - r, cy * ss - r, cx * ss + r, cy * ss + r), fill=255)
    alpha = img.resize((w, h), Image.LANCZOS)
    out = Image.new("RGBA", (w, h), (255, 255, 255, 0))
    out.putalpha(alpha)
    return out


def fonts(src):
    from fontTools.ttLib import TTFont

    FONTS.mkdir(parents=True, exist_ok=True)
    f = TTFont(src / "UncialAntiqua-Regular.ttf")
    assert "fvar" not in f, "expected the static file"
    f.save(FONTS / "UncialAntiqua-Regular.ttf")
    shutil.copy(src / "OFL.txt", FONTS / "OFL-UncialAntiqua.txt")


def verify():
    from fontTools.ttLib import TTFont

    for name, size in (("Grain", (256, 256)), ("Vines", (512, 512)), ("Flourish", (256, 16))):
        img = Image.open(OUT / (name + ".tga"))
        assert img.size == size and img.mode == "RGBA", (name, img.size, img.mode)
        assert img.getchannel("A").getbbox(), name + " is empty"
        if name != "Grain":
            assert img.convert("RGB").getextrema() == ((255, 255), (255, 255), (255, 255)), name + " not white"
    font = TTFont(FONTS / "UncialAntiqua-Regular.ttf")
    cmap = font.getBestCmap()
    assert all(ord(ch) in cmap for ch in "AZaz09ÅÄÖäöüßéèçñ"), "Latin glyphs"
    assert 0x416 not in cmap, "has Cyrillic now: Themes/Emerald.lua can use it on ruRU"
    print("ok: Emerald art and font")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--fonts-src", type=Path, required=True)
    args = ap.parse_args()
    OUT.mkdir(parents=True, exist_ok=True)
    grain().save(OUT / "Grain.tga")
    vines().save(OUT / "Vines.tga")
    flourish().save(OUT / "Flourish.tga")
    fonts(args.fonts_src)
    verify()


if __name__ == "__main__":
    main()
