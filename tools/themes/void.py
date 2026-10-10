"""Builds the Void theme's art and fonts (Themes/Void.lua, docs/superpowers/specs/2026-10-10-tomte-themes-design.md).

Writes Media/Theme/Void/{Stars,Tendrils,Flourish}.tga and, with --fonts-src, Media/Fonts/Philosopher-*.ttf and
OFL-Philosopher.txt under the addon root.

  python tools/themes/void.py [--fonts-src DIR] [--preview OUT.png]

DIR holds Google Fonts' Philosopher-Regular.ttf, Philosopher-Bold.ttf and OFL.txt
(https://github.com/google/fonts, ofl/philosopher). --preview renders a panel mock-up with the theme's colors.
Needs Pillow (and fontTools for the fonts). Output is the same on every run (fixed seeds).
"""

import argparse
import math
import random
import shutil
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parent.parent.parent
OUT = ROOT / "Media" / "Theme" / "Void"
FONTS = ROOT / "Media" / "Fonts"


def stars(size=256, seed=11):
    """Seamless starfield: sparse white pinpoints on transparent, most dim, a few with a soft halo.

    Every point is drawn at its position and at the wrapped copies, so the tile repeats without seams."""
    rnd = random.Random(seed)
    ss = 4
    n = size * ss
    img = Image.new("L", (n, n))
    draw = ImageDraw.Draw(img)

    def dot(x, y, r, v):
        for ox in (-n, 0, n):
            for oy in (-n, 0, n):
                cx, cy = x + ox, y + oy
                if -r <= cx <= n + r and -r <= cy <= n + r:
                    draw.ellipse((cx - r, cy - r, cx + r, cy + r), fill=v)

    for _ in range(70):  # faint dust
        dot(rnd.uniform(0, n), rnd.uniform(0, n), 0.5 * ss, rnd.randint(70, 130))
    for _ in range(26):  # ordinary stars
        dot(rnd.uniform(0, n), rnd.uniform(0, n), 0.55 * ss, rnd.randint(150, 220))
    halos = Image.new("L", (n, n))
    hdraw = ImageDraw.Draw(halos)
    for _ in range(5):  # bright ones with a halo
        x, y = rnd.uniform(0, n), rnd.uniform(0, n)
        dot(x, y, 0.7 * ss, 255)
        for ox in (-n, 0, n):
            for oy in (-n, 0, n):
                r = 2.6 * ss
                hdraw.ellipse((x + ox - r, y + oy - r, x + ox + r, y + oy + r), fill=60)
    # Blur the halos on a 3x3 tiling so the blur wraps too.
    big = Image.new("L", (n * 3, n * 3))
    for x in range(3):
        for y in range(3):
            big.paste(halos, (x * n, y * n))
    halos = big.filter(ImageFilter.GaussianBlur(1.6 * ss)).crop((n, n, n * 2, n * 2))
    alpha = ImageChops.lighter(img, halos).resize((size, size), Image.LANCZOS)
    out = Image.new("RGBA", (size, size), (255, 255, 255, 0))
    out.putalpha(alpha)
    return out


def value_noise(size, cells, rnd):
    """Smooth noise: a small random grid scaled up bicubically."""
    small = Image.new("L", (cells, cells))
    small.putdata([rnd.randint(0, 255) for _ in range(cells * cells)])
    return small.resize((size, size), Image.BICUBIC)


def tendrils(size=512, seed=23):
    """Void tendrils curling out of the bottom-right corner over a faint nebula wisp, white, fading with distance.

    The corner is the file's bottom-right (UI.Panel crops from there and mirrors to other corners)."""
    rnd = random.Random(seed)
    ss = 2
    n = size * ss
    lines = Image.new("L", (n, n))
    draw = ImageDraw.Draw(lines)
    # Each tendril rises from the bottom or right edge near the corner, sweeps up-left in a gentle arc and curls into
    # a small spiral at its tip (the heading turns faster towards the end).
    specs = [
        # edge ("b" bottom, "r" right), offset from the corner px, angle (deg from straight left, towards up),
        # length px, curl direction, sweep (rad over the body), tip curl (rad), width px
        ("b", 20, 30, 400, 1, 0.6, 6.0, 2.2),
        ("r", 40, 62, 430, -1, 0.5, 6.4, 2.0),
        ("b", 110, 70, 300, -1, 0.7, 3.8, 1.7),
        ("r", 130, 18, 330, 1, 0.6, 5.5, 1.7),
        ("b", 0, 46, 470, -1, 0.4, 7.0, 2.4),
        ("b", 210, 84, 200, 1, 0.9, 3.4, 1.3),
        ("r", 230, 8, 210, -1, 0.9, 3.4, 1.3),
    ]
    for edge, off, ang, length, turn, sweep, tip, width in specs:
        if edge == "b":
            x, y = n - 1 - off * ss, n + 2 * ss
        else:
            x, y = n + 2 * ss, n - 1 - off * ss
        # Pointing left, turned `ang` degrees towards up (y grows downwards).
        heading = math.atan2(-math.sin(math.radians(ang)), -math.cos(math.radians(ang)))
        steps = int(length * 1.5)
        prev = (x, y)
        wob = rnd.uniform(0, 6.28)
        for i in range(steps):
            t = i / steps
            # Gentle sweep, then a spiral at the tip; a small wobble keeps it organic.
            heading += turn * (sweep + tip * 6 * t ** 5) / steps + 0.004 * math.sin(wob + t * 11)
            x += math.cos(heading) * ss / 1.5
            y += math.sin(heading) * ss / 1.5
            fade = (1 - t) ** 0.7
            w = max(0.6, width * (1 - t * 0.8)) * ss
            v = int(255 * fade)
            draw.line((prev, (x, y)), fill=v, width=max(1, int(round(w))))
            prev = (x, y)
    lines = lines.filter(ImageFilter.GaussianBlur(0.6 * ss))
    lines = lines.resize((size, size), Image.LANCZOS)

    # Nebula: two octaves of smooth noise, shaped into wisps, faded out from the corner.
    neb = ImageChops.add(
        value_noise(size, 6, rnd).point(lambda v: v // 2),
        value_noise(size, 14, rnd).point(lambda v: v // 2),
    )
    neb = neb.point(lambda v: max(0, int((v - 120) * 2.2)))
    neb = neb.filter(ImageFilter.GaussianBlur(10))
    mask = Image.new("L", (size, size))
    mp = mask.load()
    for yy in range(size):
        for xx in range(size):
            d = math.hypot(size - 1 - xx, size - 1 - yy) / (size * 0.95)
            mp[xx, yy] = int(255 * max(0.0, 1 - d) ** 1.6)
    neb = ImageChops.multiply(neb, mask).point(lambda v: int(v * 0.45))

    # Tendrils fade towards the far edges too, so the cropped art never ends in a hard line.
    edge = Image.new("L", (size, size))
    ep = edge.load()
    for yy in range(size):
        for xx in range(size):
            d = math.hypot(size - 1 - xx, size - 1 - yy) / size
            ep[xx, yy] = int(255 * max(0.0, 1 - d * 0.85) ** 0.9)
    lines = ImageChops.multiply(lines, edge)

    alpha = ImageChops.lighter(lines, neb)
    out = Image.new("RGBA", (size, size), (255, 255, 255, 0))
    out.putalpha(alpha)
    return out


def flourish(w=256, h=16):
    """A four-pointed star in the middle with hairlines fading towards both ends, white."""
    ss = 4
    W, H = w * ss, h * ss
    img = Image.new("L", (W, H))
    pix = img.load()
    cx, cy = W / 2, H / 2
    arm = 7 * ss  # star arm length
    for y in range(H):
        for x in range(W):
            ax, ay = abs(x - cx) / arm, abs(y - cy) / arm
            v = 0.0
            # Astroid-like star: |x|^0.5 + |y|^0.5 <= 1 gives four thin points.
            if ax <= 1 and ay <= 1 and math.sqrt(ax) + math.sqrt(ay) <= 1:
                v = 1.0
            elif abs(y - cy) <= 0.5 * ss and abs(x - cx) > arm * 1.6:
                d = abs(x - cx) - arm * 1.6
                v = max(0.0, 1.0 - d / (cx - arm * 1.6)) ** 1.3
            pix[x, y] = int(255 * v)
    alpha = img.resize((w, h), Image.LANCZOS)
    out = Image.new("RGBA", (w, h), (255, 255, 255, 0))
    out.putalpha(alpha)
    return out


def fonts(src):
    from fontTools.ttLib import TTFont
    from fontTools.varLib import instancer

    FONTS.mkdir(parents=True, exist_ok=True)
    for name in ("Philosopher-Regular.ttf", "Philosopher-Bold.ttf"):
        f = TTFont(src / name)
        if "fvar" in f:  # Google ships static Philosopher files; pin the weight if that ever changes
            f = instancer.instantiateVariableFont(f, {"wght": 700 if "Bold" in name else 400})
        f.save(FONTS / name)
    shutil.copy(src / "OFL.txt", FONTS / "OFL-Philosopher.txt")


def verify():
    from fontTools.ttLib import TTFont

    for name, size in (("Stars", (256, 256)), ("Tendrils", (512, 512)), ("Flourish", (256, 16))):
        img = Image.open(OUT / (name + ".tga"))
        assert img.size == size and img.mode == "RGBA", (name, img.size, img.mode)
        r, g, b, a = img.split()
        assert r.getextrema() == (255, 255) and g.getextrema() == (255, 255), name + " is not white art"
        assert a.getextrema()[1] > 0, name + " is empty"
    # The starfield must tile: opposite edges may not both be lit in one spot (no cut-off dots) - compare wrapped
    # neighbours with interior neighbours.
    a = Image.open(OUT / "Stars.tga").split()[3]
    px, s = a.load(), a.size[0]
    seam = sum(abs(px[0, y] - px[s - 1, y]) + abs(px[y, 0] - px[y, s - 1]) for y in range(s))
    inner = sum(abs(px[s // 2, y] - px[s // 2 - 1, y]) + abs(px[y, s // 2] - px[y, s // 2 - 1]) for y in range(s))
    assert seam <= inner * 3 + 255, ("seam", seam, inner)
    for f in ("Philosopher-Regular.ttf", "Philosopher-Bold.ttf"):
        font = TTFont(FONTS / f)
        assert "fvar" not in font, f + " is still variable"
        cmap = font.getBestCmap()
        assert all(cp in cmap for cp in range(0x410, 0x450)), f + " lacks Cyrillic"
    print("ok: Void art and fonts")


def preview(path):
    """640x400 mock-up of a large UI.Panel in the Void theme (colors copied from Themes/Void.lua)."""
    from PIL import ImageFont

    def hx(s, a=1.0):
        return (int(s[1:3], 16), int(s[3:5], 16), int(s[5:7], 16), int(a * 255))

    C = {
        "bgTop": hx("#16122a"), "bgBottom": hx("#0c0a17"), "surface": (0, 0, 0, int(0.26 * 255)),
        "hover": hx("#a46bff", 0.15), "text": hx("#e6e1f7"), "heading": hx("#d4c6ff"),
        "textMuted": hx("#9d96bd"), "textFaint": hx("#6c6690"), "accent": hx("#a46bff"),
        "accentDeep": hx("#4a1fa6"), "frame": hx("#6e5fae"), "frameDark": hx("#050409"),
        "rule": hx("#8f80d6", 0.16), "contour": hx("#b38aff"), "success": hx("#7fd9ab"),
        "warning": hx("#ebbb6c"), "danger": hx("#ff6f8e"),
    }
    ART = {"glow": 0.07, "contours": 0.16, "grain": 0.55, "vignette": 0.5, "outer": 2, "inset": 5, "rule": 0.4}
    W, H = 640, 400

    def tint(img, color, alpha):
        layer = Image.new("RGBA", img.size, color[:3] + (0,))
        layer.putalpha(img.split()[3].point(lambda v: int(v * alpha)))
        return layer

    base = Image.new("RGBA", (W, H))
    bp = base.load()
    for y in range(H):
        t = y / (H - 1)
        c = tuple(int(C["bgTop"][i] * (1 - t) + C["bgBottom"][i] * t) for i in range(3)) + (255,)
        for x in range(W):
            bp[x, y] = c
    # glow: the quarter of the spot whose center is the top-left corner
    glow = Image.new("L", (256, 256))
    gp = glow.load()
    for y in range(256):
        for x in range(256):
            gp[x, y] = int(255 * max(0.0, 1 - math.hypot(x - 127.5, y - 127.5) / 127.5) ** 2)
    g = Image.new("RGBA", (256, 256), (255, 255, 255, 0))
    g.putalpha(glow)
    g = g.crop((128, 128, 256, 256)).resize((int(W * 0.7), int(H * 0.8)))
    base.alpha_composite(tint(g, (255, 255, 255, 255), ART["glow"]), (0, 0))
    ten = Image.open(OUT / "Tendrils.tga")
    cw, ch = min(W, 512), min(H, 512)
    ten = ten.crop((512 - cw, 512 - ch, 512, 512))
    base.alpha_composite(tint(ten, C["contour"], ART["contours"]), (W - cw, H - ch))
    st = Image.open(OUT / "Stars.tga")
    for x in range(0, W, 256):
        for y in range(0, H, 256):
            base.alpha_composite(tint(st, (255, 255, 255, 255), ART["grain"]), (x, y))
    vig = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    vp = vig.load()
    D = 26
    for y in range(H):
        for x in range(W):
            d = min(x, y, W - 1 - x, H - 1 - y)
            if d < D:
                vp[x, y] = (0, 0, 0, int(255 * ART["vignette"] * (1 - d / D)))
    base.alpha_composite(vig)
    base = base.convert("RGB")  # ImageDraw only blends translucent fills on RGB images
    dr = ImageDraw.Draw(base, "RGBA")
    o = ART["outer"]
    dr.rectangle((0, 0, W - 1, H - 1), outline=C["frameDark"], width=o)
    i = ART["inset"]
    fr = C["frame"][:3] + (int(255 * ART["rule"]),)
    dr.rectangle((i, i, W - 1 - i, H - 1 - i), outline=fr, width=1)

    fdir = Path("C:/Windows/Fonts")
    title = ImageFont.truetype(str(FONTS / "Philosopher-Bold.ttf"), 22)
    body = ImageFont.truetype(str(FONTS / "Philosopher-Regular.ttf"), 14)
    client = ImageFont.truetype(str(fdir / "segoeui.ttf"), 13)  # stand-in for the client font (numbers)

    tw = dr.textlength("Weekly Vault", font=title)
    dr.text(((W - tw) / 2, 22), "Weekly Vault", font=title, fill=C["heading"])
    fl = tint(Image.open(OUT / "Flourish.tga").resize((160, 10)), C["frame"], 0.8)
    base.paste(fl, ((W - 160) // 2, 54), fl)

    x0 = 32
    dr.text((x0, 80), "Raid: Liberation of Undermine", font=body, fill=C["text"])
    dr.text((x0, 100), "Two more bosses for the second slot", font=body, fill=C["textMuted"])
    dr.text((x0, 118), "Resets Tuesday", font=body, fill=C["textFaint"])
    # accent bar
    bx, by, bw, bh = x0, 144, 300, 6
    dr.rectangle((bx, by, bx + bw, by + bh), fill=(0, 0, 0, 102))
    fw = int(bw * 0.62)
    for xx in range(fw):
        t = xx / max(1, fw - 1)
        c = tuple(int(C["accentDeep"][k] * (1 - t) + C["accent"][k] * t) for k in range(3)) + (255,)
        dr.line((bx + xx, by, bx + xx, by + bh), fill=c)
    dr.line((bx, by, bx + bw, by), fill=(0, 0, 0, 153))
    dr.text((bx + bw + 10, by - 6), "5 / 8", font=client, fill=C["accent"])
    # hover row
    dr.rectangle((x0 - 6, 168, 330, 190), fill=C["hover"])
    dr.text((x0, 171), "Mythic+ (hovered row)", font=body, fill=C["text"])
    dr.text((280, 172), "12", font=client, fill=C["textMuted"])
    dr.text((x0, 196), "Delves", font=body, fill=C["text"])
    dr.text((280, 197), "3", font=client, fill=C["textMuted"])
    # surface box
    sx, sy = 360, 80
    dr.rectangle((sx, sy, sx + 240, sy + 130), fill=C["surface"])
    dr.rectangle((sx, sy, sx + 240, sy + 130), outline=C["frame"][:3] + (int(255 * 0.35),), width=1)
    dr.text((sx + 12, sy + 10), "Slot 1", font=body, fill=C["heading"])
    dr.text((sx + 12, sy + 34), "Item level 645", font=body, fill=C["text"])
    dr.text((sx + 12, sy + 56), "Ready", font=body, fill=C["success"])
    dr.text((sx + 80, sy + 56), "Expiring", font=body, fill=C["warning"])
    dr.text((sx + 160, sy + 56), "Missing", font=body, fill=C["danger"])
    dr.text((sx + 12, sy + 84), "Selected: accent text", font=body, fill=C["accent"])
    # rule
    dr.line((x0, 232, W - 32, 232), fill=C["rule"])
    dr.text((x0, 244), "A list people read: calm, cool, a few stars in the dark.", font=body, fill=C["text"])
    dr.text((x0, 266), "Muted secondary line with details", font=body, fill=C["textMuted"])
    dr.text((x0, 286), "Faint hint text", font=body, fill=C["textFaint"])
    Path(path).parent.mkdir(parents=True, exist_ok=True)
    base.convert("RGB").save(path)
    print("preview:", path)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--fonts-src", type=Path)
    ap.add_argument("--preview", type=Path)
    args = ap.parse_args()
    OUT.mkdir(parents=True, exist_ok=True)
    stars().save(OUT / "Stars.tga")
    tendrils().save(OUT / "Tendrils.tga")
    flourish().save(OUT / "Flourish.tga")
    if args.fonts_src:
        fonts(args.fonts_src)
    verify()
    if args.preview:
        preview(args.preview)


if __name__ == "__main__":
    main()
