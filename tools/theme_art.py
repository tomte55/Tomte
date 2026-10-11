"""Builds the Cartographer theme's art and fonts (docs/superpowers/specs/2026-10-10-redesign-design.md).

Writes Media/Theme/{Grain,Contours,Flourish,Glow}.tga and Media/Fonts/*.ttf + OFL texts under the addon root.

  python tools/theme_art.py --fonts-src DIR     (or --art-only to skip the fonts)

DIR holds Google Fonts' variable files and licenses: Cinzel[wght].ttf, Alegreya[wght].ttf, OFL-Cinzel.txt,
OFL-Alegreya.txt (https://github.com/google/fonts, ofl/cinzel and ofl/alegreya). Needs Pillow and fontTools.
Output is the same on every run (fixed seed).
"""

import argparse
import math
import random
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))  # the -I flag leaves the script folder off sys.path
import artlib
from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
THEME = ROOT / "Media" / "Theme"
FONTS = ROOT / "Media" / "Fonts"


def grain(size=128, seed=7):
    """Seamless fine noise: grey around 128 with alpha growing with distance from 128, so it lightens and darkens."""
    return artlib.signed_rgba(artlib.seamless_noise(size, random.Random(seed), 46, 0.6), 1.6)


def contours(size=512, step=18, fade=500):
    """Wobbly terrain rings around the bottom-right corner, white, fading out with the radius.

    The wobble depends smoothly on the angle and the radius, so every ring is one unbroken line."""
    ss = 2  # supersample for anti-aliasing
    n = size * ss
    img = Image.new("L", (n, n))
    pix = img.load()
    half = 0.6  # half line width in px
    for y in range(n):
        for x in range(n):
            dx, dy = (n - 1 - x) / ss, (n - 1 - y) / ss
            r = math.hypot(dx, dy)
            if r > fade or r < 30:
                continue
            th = math.atan2(dy, dx)
            w = r + 4.0 * math.sin(3 * th + r / 40) + 2.5 * math.sin(7 * th - r / 25)
            d = abs(((w + step / 2) % step) - step / 2)  # distance to the nearest ring, about in px
            if d < half + 0.5:
                cov = min(1.0, half + 0.5 - d)
                pix[x, y] = int(255 * cov * (1 - r / fade) ** 0.8)
    return artlib.finish(img, size, size)


def flourish(w=256, h=16):
    """Diamond in the middle with hairlines fading towards both ends, white."""
    ss = 4
    W, H = w * ss, h * ss
    img = Image.new("L", (W, H))
    pix = img.load()
    cx, cy = W / 2, H / 2
    dia = 4 * ss  # half diagonal
    for y in range(H):
        for x in range(W):
            ax, ay = abs(x - cx), abs(y - cy)
            if ax + ay <= dia:
                pix[x, y] = 255
    artlib.hairline(img, cx, cy, dia, ss, 1.3)
    return artlib.finish(img, w, h)


def fonts(src):
    from fontTools.ttLib import TTFont

    FONTS.mkdir(parents=True, exist_ok=True)

    artlib.static_font(src / "Cinzel[wght].ttf", FONTS / "Cinzel-Medium.ttf", 500)
    artlib.static_font(src / "Alegreya[wght].ttf", FONTS / "Alegreya-Regular.ttf", 400)

    # WoW can't turn on OpenType lnum/tnum, so make the tabular lining digits the default ones.
    nums = TTFont(FONTS / "Alegreya-Regular.ttf")
    names = ["zero", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine"]
    order = set(nums.getGlyphOrder())
    for table in nums["cmap"].tables:
        if table.isUnicode():
            for i, name in enumerate(names):
                if 0x30 + i in table.cmap and name + ".tf" in order:
                    table.cmap[0x30 + i] = name + ".tf"
    family = "Alegreya Numbers Tomte"
    for rec in nums["name"].names:
        if rec.nameID in (1, 16):
            rec.string = family
        elif rec.nameID == 4:
            rec.string = family + " Regular"
        elif rec.nameID == 6:
            rec.string = "AlegreyaNumbersTomte-Regular"
        elif rec.nameID == 3:
            rec.string = "AlegreyaNumbersTomte-Regular;modified from Alegreya"
    nums.save(FONTS / "AlegreyaNumbers-Regular.ttf")

    artlib.copy_license(src, "OFL-Cinzel.txt", "OFL-Cinzel.txt")
    artlib.copy_license(src, "OFL-Alegreya.txt", "OFL-Alegreya.txt")


def verify():
    from fontTools.ttLib import TTFont

    for name, size in (("Grain", (128, 128)), ("Contours", (512, 512)), ("Flourish", (256, 16)), ("Glow", (256, 256))):
        img = Image.open(THEME / (name + ".tga"))
        assert img.size == size and img.mode == "RGBA", (name, img.size, img.mode)
    nums = TTFont(FONTS / "AlegreyaNumbers-Regular.ttf")
    cmap, hmtx = nums.getBestCmap(), nums["hmtx"]
    widths = {hmtx[cmap[0x30 + i]][0] for i in range(10)}
    assert len(widths) == 1, widths
    for f in ("Cinzel-Medium.ttf", "Alegreya-Regular.ttf"):
        assert "fvar" not in TTFont(FONTS / f), f + " is still variable"
    print("ok: art and fonts; digit width", widths.pop())


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--fonts-src", type=Path)
    ap.add_argument("--art-only", action="store_true", help="skip the font step")
    args = ap.parse_args()
    if not args.fonts_src and not args.art_only:
        ap.error("--fonts-src is required unless --art-only is given")
    THEME.mkdir(parents=True, exist_ok=True)
    grain().save(THEME / "Grain.tga")
    contours().save(THEME / "Contours.tga")
    flourish().save(THEME / "Flourish.tga")
    artlib.glow().save(THEME / "Glow.tga")
    if not args.art_only:
        fonts(args.fonts_src)
    verify()


if __name__ == "__main__":
    main()
