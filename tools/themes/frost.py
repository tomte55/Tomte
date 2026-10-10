"""Builds the Frost theme's art and font (Themes/Frost.lua; docs/superpowers/specs/2026-10-10-tomte-themes-design.md).

Writes Media/Theme/Frost/{Rime,Snow,Flourish}.tga and Media/Fonts/FrostForum-Regular.ttf + OFL-Forum.txt.

  python tools/themes/frost.py [--fonts-src DIR] [--preview PNG]

DIR holds Google Fonts' Forum-Regular.ttf and its OFL.txt (https://github.com/google/fonts, ofl/forum). Without
--fonts-src only the art is rebuilt. --preview renders a mock panel with the theme's palette. Needs Pillow (and
fontTools for the font). Output is the same on every run (fixed seed).
"""

import argparse
import math
import random
import shutil
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parent.parent.parent
THEME = ROOT / "Media" / "Theme" / "Frost"
FONTS = ROOT / "Media" / "Fonts"
FONT = "FrostForum-Regular.ttf"


def white(alpha):
    """White RGBA image with `alpha` (an L image) as its alpha."""
    out = Image.new("RGBA", alpha.size, (255, 255, 255, 0))
    out.putalpha(alpha)
    return out


def snow(size=128, seed=11):
    """Seamless fine frost speckle: sparse soft white flecks, a few brighter, on transparent (drawn wrapped)."""
    rnd = random.Random(seed)
    ss = 4
    n = size * ss
    img = Image.new("L", (n, n))
    d = ImageDraw.Draw(img)
    for _ in range(170):
        x, y = rnd.uniform(0, n), rnd.uniform(0, n)
        big = rnd.random() < 0.12
        r = (rnd.uniform(1.6, 2.4) if big else rnd.uniform(0.7, 1.3)) * ss / 2
        v = rnd.randint(170, 255) if big else rnd.randint(70, 160)
        for ox in (-n, 0, n):
            for oy in (-n, 0, n):
                cx, cy = x + ox, y + oy
                d.ellipse((cx - r, cy - r, cx + r, cy + r), fill=v)
    alpha = img.resize((size, size), Image.LANCZOS)
    return white(alpha)


def rime(size=512, seed=5, fade=470):
    """Frost growing from the bottom-right corner: feathery ice branches with 60-degree side shoots, plus a few
    small six-armed crystals further out. White, fading out with the distance from the corner."""
    rnd = random.Random(seed)
    ss = 2
    n = size * ss
    img = Image.new("L", (n, n))
    d = ImageDraw.Draw(img)
    ox, oy = n - 1, n - 1  # the corner

    def fadeAt(x, y):
        r = math.hypot(ox - x, oy - y) / ss
        return max(0.0, 1 - r / fade) ** 0.9

    def line(x1, y1, x2, y2, w, v):
        f = fadeAt((x1 + x2) / 2, (y1 + y2) / 2)
        if f > 0:
            d.line((x1, y1, x2, y2), fill=int(255 * v * f), width=max(1, int(round(w * ss))))

    def branch(x, y, ang, length, w, depth):
        # A wobbly main stem in short segments; side shoots at +-60 degrees, shorter towards the tip.
        seg = 6 * ss
        steps = max(1, int(length * ss / seg))
        for i in range(steps):
            ang += rnd.uniform(-0.03, 0.03)
            nx, ny = x + math.cos(ang) * seg, y + math.sin(ang) * seg
            line(x, y, nx, ny, w, 1.0)
            left = 1 - i / steps
            if depth > 0 and i > 0 and i % (2 if depth > 1 else 3) == 0 and rnd.random() < 0.8:
                for side in (-1, 1):
                    if rnd.random() < 0.7:
                        sub = length * 0.32 * left * rnd.uniform(0.6, 1.1)
                        if sub > 4:
                            branch(nx, ny, ang + side * math.pi / 3, sub, w * 0.75, depth - 1)
            x, y = nx, ny

    # Fronds grow in from the bottom and right edges near the corner, like frost on a window pane.
    for k in range(4):
        along = 30 + k * 85 + rnd.uniform(-15, 15)
        branch(ox - along * ss, oy, -math.pi / 2 - rnd.uniform(0.25, 0.6), rnd.uniform(170, 300), 1.0, 2)  # up-left
        along = 40 + k * 85 + rnd.uniform(-15, 15)
        branch(ox, oy - along * ss, math.pi + rnd.uniform(0.25, 0.6), rnd.uniform(170, 300), 1.0, 2)  # left-up
    branch(ox, oy, math.pi * 1.25, 380, 1.1, 2)  # the long diagonal one

    # Loose crystals.
    for _ in range(22):
        r = rnd.uniform(150, 430)
        th = math.pi + rnd.uniform(0.05, math.pi / 2 - 0.05)
        cx, cy = ox + math.cos(th) * r * ss, oy + math.sin(th) * r * ss
        arm = rnd.uniform(5, 11) * ss
        rot = rnd.uniform(0, math.pi / 3)
        for a in range(6):
            t = rot + a * math.pi / 3
            ex, ey = cx + math.cos(t) * arm, cy + math.sin(t) * arm
            line(cx, cy, ex, ey, 0.9, 0.9)
            for frac in (0.55,):
                bx, by = cx + math.cos(t) * arm * frac, cy + math.sin(t) * arm * frac
                for side in (-1, 1):
                    tt = t + side * math.pi / 3
                    line(bx, by, bx + math.cos(tt) * arm * 0.35, by + math.sin(tt) * arm * 0.35, 0.8, 0.8)

    alpha = img.filter(ImageFilter.GaussianBlur(0.4 * ss)).resize((size, size), Image.LANCZOS)
    return white(alpha)


def flourish(w=256, h=16):
    """A small six-armed ice crystal in the middle (inside the center 0.44..0.56 the title line crops), two tiny
    diamonds beside it and hairlines fading towards both ends. White."""
    ss = 4
    W, H = w * ss, h * ss
    img = Image.new("L", (W, H))
    d = ImageDraw.Draw(img)
    cx, cy = W / 2, H / 2
    arm = 6.5 * ss
    for a in range(6):
        t = math.pi / 2 + a * math.pi / 3
        ex, ey = cx + math.cos(t) * arm, cy + math.sin(t) * arm
        d.line((cx, cy, ex, ey), fill=255, width=int(1.1 * ss))
        bx, by = cx + math.cos(t) * arm * 0.55, cy + math.sin(t) * arm * 0.55
        for side in (-1, 1):
            tt = t + side * math.pi / 3
            d.line((bx, by, bx + math.cos(tt) * arm * 0.3, by + math.sin(tt) * arm * 0.3), fill=220, width=int(0.8 * ss))
    for side in (-1, 1):
        dx = cx + side * 11 * ss
        r = 1.8 * ss
        d.polygon([(dx - r, cy), (dx, cy - r), (dx + r, cy), (dx, cy + r)], fill=230)
    pix = img.load()
    start = 14 * ss
    half = 0.5 * ss
    for x in range(W):
        ax = abs(x - cx)
        if ax <= start:
            continue
        v = max(0.0, 1.0 - (ax - start) / (cx - start)) ** 1.4
        for y in range(int(cy - half), int(cy + half)):
            pix[x, y] = max(pix[x, y], int(255 * v))
    alpha = img.resize((w, h), Image.LANCZOS)
    return white(alpha)


def font(src):
    from fontTools.ttLib import TTFont

    FONTS.mkdir(parents=True, exist_ok=True)
    f = TTFont(src / "Forum-Regular.ttf")
    if "fvar" in f:
        from fontTools.varLib import instancer

        f = instancer.instantiateVariableFont(f, {"wght": 400})
    f.save(FONTS / FONT)
    shutil.copy(src / "OFL.txt", FONTS / "OFL-Forum.txt")


def verify():
    for name, size in (("Snow", (128, 128)), ("Rime", (512, 512)), ("Flourish", (256, 16))):
        img = Image.open(THEME / (name + ".tga"))
        assert img.size == size and img.mode == "RGBA", (name, img.size, img.mode)
        r, g, b, a = img.split()
        assert r.getextrema() == (255, 255) and g.getextrema() == (255, 255), name + " is not white art"
        assert a.getextrema()[1] > 100, name + " is empty"
    if (FONTS / FONT).exists():
        from fontTools.ttLib import TTFont

        t = TTFont(FONTS / FONT)
        assert "fvar" not in t, FONT + " is still variable"
        cmap = t.getBestCmap()
        assert 0x416 in cmap, FONT + " lost its Cyrillic"
        assert (FONTS / "OFL-Forum.txt").exists(), "license text"
    print("ok: Frost art" + (" and font" if (FONTS / FONT).exists() else ""))


# Preview -------------------------------------------------------------------------------------------------------

PAL = {
    "bgTop": "#1c2531", "bgBottom": "#121820", "surface": (0, 0, 0, 0.24), "hover": ("#86c8ea", 0.13),
    "text": "#e2ebf3", "heading": "#eef6fc", "textMuted": "#91a2b4", "textFaint": "#627181",
    "accent": "#86c8ea", "accentDeep": "#2c6a92", "frame": "#8e9cab", "frameDark": "#06080b",
    "rule": ("#b9cadb", 0.13), "contour": "#d8ecfa", "success": "#85c99b", "warning": "#e2bb62",
    "danger": "#e2735f",
}
ART = {"glow": 0.06, "contours": 0.09, "grain": 0.07, "vignette": 0.5, "outer": 2, "inset": 5, "rule": 0.5}


def rgb(c):
    if isinstance(c, tuple) and isinstance(c[0], str):
        c = c[0]
    if isinstance(c, str):
        return tuple(int(c[i:i + 2], 16) for i in (1, 3, 5))
    return tuple(int(v * 255) for v in c[:3])


def over(base, layer, alpha=1.0, pos=(0, 0)):
    """Composite RGBA `layer` with extra `alpha` onto RGB `base`."""
    if alpha != 1.0:
        a = layer.getchannel("A").point(lambda v: int(v * alpha))
        layer = layer.copy()
        layer.putalpha(a)
    base.paste(layer, pos, layer)


def tint(img, color):
    out = Image.new("RGBA", img.size, rgb(color) + (0,))
    out.putalpha(img.getchannel("A"))
    return out


def preview(path):
    from PIL import ImageFont

    W, H = 640, 400
    top, bot = rgb(PAL["bgTop"]), rgb(PAL["bgBottom"])
    im = Image.new("RGB", (W, H))
    px = im.load()
    for y in range(H):
        t = y / (H - 1)
        c = tuple(int(top[i] * (1 - t) + bot[i] * t) for i in range(3))
        for x in range(W):
            px[x, y] = c
    glow = Image.open(ROOT / "Media" / "Theme" / "Glow.tga")
    g = glow.crop((128, 128, 256, 256)).resize((int(W * 0.7), int(H * 0.8)))
    over(im, g, ART["glow"])
    rimeImg = tint(Image.open(THEME / "Rime.tga"), PAL["contour"])
    over(im, rimeImg.crop((512 - W if W < 512 else 0, 512 - H, 512, 512)), ART["contours"], (max(0, W - 512), 0))
    snowImg = Image.open(THEME / "Snow.tga")
    for x in range(0, W, 128):
        for y in range(0, H, 128):
            over(im, snowImg, ART["grain"], (x, y))
    # Vignette.
    vig = Image.new("L", (W, H))
    vp = vig.load()
    D = 26
    for y in range(H):
        for x in range(W):
            e = min(x, y, W - 1 - x, H - 1 - y)
            if e < D:
                vp[x, y] = int(255 * ART["vignette"] * (1 - e / D))
    im.paste((0, 0, 0), (0, 0), vig)
    d = ImageDraw.Draw(im, "RGBA")
    for i in range(ART["outer"]):
        d.rectangle((i, i, W - 1 - i, H - 1 - i), outline=rgb(PAL["frameDark"]))
    ins = ART["inset"]
    d.rectangle((ins, ins, W - 1 - ins, H - 1 - ins), outline=rgb(PAL["frame"]) + (int(255 * ART["rule"]),))

    title = ImageFont.truetype(str(FONTS / FONT), 26)
    body = ImageFont.truetype("C:/Windows/Fonts/segoeui.ttf", 14)  # stands in for the client's font
    d.text((W / 2, 34), "Weekly Progress", font=title, fill=rgb(PAL["heading"]), anchor="mm")
    fl = tint(Image.open(THEME / "Flourish.tga"), PAL["frame"]).resize((160, 10), Image.LANCZOS)
    over(im, fl, 0.8, (W // 2 - 80, 52))
    d = ImageDraw.Draw(im, "RGBA")
    rule = rgb(PAL["rule"]) + (int(255 * PAL["rule"][1]),)
    y = 78
    rows = [("Great Vault: Mythic+", "3 / 8", "text"), ("Weekly quest: Spreading the Light", "done", "success"),
            ("World boss", "not yet", "warning"), ("Crafting orders", "2 expired", "danger")]
    for i, (a, b, role) in enumerate(rows):
        if i == 1:
            d.rectangle((20, y - 4, W - 21, y + 22), fill=rgb(PAL["hover"]) + (int(255 * PAL["hover"][1]),))
            d.rectangle((20, y - 4, 21, y + 22), fill=rgb(PAL["accent"]))
        d.text((30, y), a, font=body, fill=rgb(PAL["text"]))
        d.text((W - 30, y), b, font=body, fill=rgb(PAL[role]), anchor="ra")
        d.line((24, y + 23, W - 25, y + 23), fill=rule)
        y += 28
    d.text((30, y + 4), "Resets in 2 days 14 hours", font=body, fill=rgb(PAL["textMuted"]))
    d.text((30, y + 24), "Nothing tracked on this character yet", font=body, fill=rgb(PAL["textFaint"]))
    # Progress bar.
    by = y + 54
    d.rectangle((30, by, W - 31, by + 9), fill=(0, 0, 0, 90))
    fillW = int((W - 61) * 0.62)
    a1, a2 = rgb(PAL["accentDeep"]), rgb(PAL["accent"])
    for x in range(fillW):
        t = x / max(1, fillW - 1)
        d.line((30 + x, by + 1, 30 + x, by + 8), fill=tuple(int(a1[i] * (1 - t) + a2[i] * t) for i in range(3)))
    d.text((W - 30, by + 16), "62%", font=body, fill=rgb(PAL["textMuted"]), anchor="ra")
    # Surface box.
    sy = by + 40
    d.rectangle((30, sy, 300, sy + 60), fill=(0, 0, 0, int(255 * PAL["surface"][3])),
                outline=rgb(PAL["frame"]) + (int(255 * 0.35),))
    d.text((42, sy + 10), "Valdrakken", font=body, fill=rgb(PAL["heading"]))
    d.text((42, sy + 32), "Ready  ", font=body, fill=rgb(PAL["success"]))
    d.text((100, sy + 32), "Soon  ", font=body, fill=rgb(PAL["warning"]))
    d.text((150, sy + 32), "Missing", font=body, fill=rgb(PAL["danger"]))
    d.text((330, sy + 10), "Link-like accent text", font=body, fill=rgb(PAL["accent"]))
    Path(path).parent.mkdir(parents=True, exist_ok=True)
    im.save(path)
    print("preview:", path)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--fonts-src", type=Path)
    ap.add_argument("--preview", type=Path)
    args = ap.parse_args()
    THEME.mkdir(parents=True, exist_ok=True)
    snow().save(THEME / "Snow.tga")
    rime().save(THEME / "Rime.tga")
    flourish().save(THEME / "Flourish.tga")
    if args.fonts_src:
        font(args.fonts_src)
    verify()
    if args.preview:
        preview(args.preview)


if __name__ == "__main__":
    main()
