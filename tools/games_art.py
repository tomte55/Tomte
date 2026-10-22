"""Textures for the Games module (Media/Games/*.tga): white shapes on transparent, tinted in game by theme role.

  Spade.tga, Heart.tga, Diamond.tga, Club.tga   the four suits, drawn from circles and polygons
  Stand.tga, Split.tga, Double.tga, Hit.tga     the blackjack play buttons' icons (a hand, two cards, a x2 chip,
                                                an arrow down)

Run from the repo root: python tools/games_art.py. Needs Pillow. New files need a full client restart.
"""

import math
from pathlib import Path

from PIL import ImageFont

from artlib import FONTS
from showcase_art import shape, white

OUT = Path(__file__).resolve().parent.parent / "Media" / "Games"
SIZE = 64  # shown at 12 to 28 pixels


def lobes(d, s, lobe_y, r, tip_y):
    """Two round lobes side by side and a point at tip_y: a heart (point down) or a spade's body (point up)."""
    left, right = s * 0.5 - r * 0.95, s * 0.5 + r * 0.95
    for cx in (left, right):
        d.ellipse((cx - r, lobe_y - r, cx + r, lobe_y + r), fill=255)
    base = lobe_y + (r if tip_y > lobe_y else -r) * 0.25
    d.polygon([(left - r * 0.97, base), (right + r * 0.97, base), (s * 0.5, tip_y)], fill=255)


def stem(d, s):
    d.polygon([(s * 0.5, s * 0.55), (s * 0.66, s * 0.95), (s * 0.34, s * 0.95)], fill=255)


def heart(d, s):
    lobes(d, s, s * 0.36, s * 0.235, s * 0.90)


def spade(d, s):
    lobes(d, s, s * 0.56, s * 0.22, s * 0.06)
    stem(d, s)


def diamond(d, s):
    d.polygon([(s * 0.5, s * 0.05), (s * 0.84, s * 0.5), (s * 0.5, s * 0.95), (s * 0.16, s * 0.5)], fill=255)


def club(d, s):
    r = s * 0.19
    for cx, cy in ((s * 0.5, s * 0.27), (s * 0.29, s * 0.55), (s * 0.71, s * 0.55)):
        d.ellipse((cx - r, cy - r, cx + r, cy + r), fill=255)
    d.polygon([(s * 0.5, s * 0.3), (s * 0.62, s * 0.55), (s * 0.38, s * 0.55)], fill=255)
    stem(d, s)


def rounded_rect(cx, cy, w, h, r, angle=0.0, steps=8):
    """Points of a w x h rectangle with corner radius r centred on (cx, cy), turned `angle` degrees clockwise."""
    a = math.radians(angle)
    ca, sa = math.cos(a), math.sin(a)
    pts = []
    corners = ((w / 2 - r, -h / 2 + r, -90), (w / 2 - r, h / 2 - r, 0), (-w / 2 + r, h / 2 - r, 90),
               (-w / 2 + r, -h / 2 + r, 180))
    for x0, y0, start in corners:
        for i in range(steps + 1):
            t = math.radians(start + 90 * i / steps)
            x, y = x0 + r * math.cos(t), y0 + r * math.sin(t)
            pts.append((cx + x * ca - y * sa, cy + x * sa + y * ca))
    return pts


def finger(d, s, tip, base, w_tip, w_base):
    """A finger from tip to base (fractions of s), round at the tip, tapering from w_base to w_tip."""
    (tx, ty), (bx, by) = (tip[0] * s, tip[1] * s), (base[0] * s, base[1] * s)
    length = math.hypot(bx - tx, by - ty)
    nx, ny = (by - ty) / length, -(bx - tx) / length  # unit normal
    a, b = w_tip * s / 2, w_base * s / 2
    d.polygon([(tx + nx * a, ty + ny * a), (bx + nx * b, by + ny * b), (bx - nx * b, by - ny * b),
               (tx - nx * a, ty - ny * a)], fill=255)
    d.ellipse((tx - a, ty - a, tx + a, ty + a), fill=255)
    d.ellipse((bx - b, by - b, bx + b, by + b), fill=255)


def stand(d, s):
    """An open hand, palm out, fingers slightly fanned, thumb out to the side: stop."""
    dx = -0.05  # the thumb sticks out right: shift the whole hand left so it sits centred in the icon
    for tip, base in (((0.22, 0.29), (0.31, 0.62)), ((0.37, 0.11), (0.42, 0.56)), ((0.53, 0.06), (0.54, 0.56)),
                      ((0.69, 0.13), (0.65, 0.58))):
        finger(d, s, (tip[0] + dx, tip[1]), (base[0] + dx, base[1]), 0.095, 0.115)
    # The palm leans toward the thumb, so its round bottom sits under the middle of the whole hand.
    d.ellipse((s * (0.27 + dx), s * 0.44, s * (0.79 + dx), s * 0.96), fill=255)
    d.polygon(rounded_rect(s * (0.5 + dx), s * 0.6, s * 0.5, s * 0.24, s * 0.06), fill=255)
    finger(d, s, (0.89 + dx, 0.54), (0.68 + dx, 0.78), 0.12, 0.17)


def split(d, s):
    """Two card outlines fanned out and overlapping, a pip on each."""
    w, h, r, edge, gap = s * 0.40, s * 0.62, s * 0.06, s * 0.07, s * 0.05
    for cx, angle in ((0.31, -13), (0.69, 13)):
        cx = s * cx
        # Clear a margin round the front card so its edge stays apart from the card behind.
        d.polygon(rounded_rect(cx, s * 0.5, w + gap * 2, h + gap * 2, r + gap, angle), fill=0)
        d.polygon(rounded_rect(cx, s * 0.5, w, h, r, angle), fill=255)
        d.polygon(rounded_rect(cx, s * 0.5, w - edge * 2, h - edge * 2, r * 0.4, angle), fill=0)
        p = s * 0.085
        d.polygon([(cx, s * 0.5 - p), (cx + p * 0.75, s * 0.5), (cx, s * 0.5 + p), (cx - p * 0.75, s * 0.5)],
                  fill=255)


def double(d, s):
    """A poker chip (notches round the rim) with a big x2 cut out of the middle."""
    c, r = s * 0.5, s * 0.49
    d.ellipse((c - r, c - r, c + r, c + r), fill=255)
    for i in range(6):  # notches at the rim, each pointing at the centre
        a = math.radians(i * 60)
        nx, ny = c + r * 0.9 * math.sin(a), c - r * 0.9 * math.cos(a)
        d.polygon(rounded_rect(nx, ny, s * 0.12, r * 0.24, 0, angle=i * 60), fill=0)
    big = ImageFont.truetype(str(FONTS / "Philosopher-Bold.ttf"), int(s * 0.62))
    small = ImageFont.truetype(str(FONTS / "Philosopher-Bold.ttf"), int(s * 0.36))
    xw, tw = d.textlength("x", font=small), d.textlength("2", font=big)
    left = c - (xw + tw) / 2
    # A stroke thickens the font's thin strokes so the 2 still reads at button size.
    d.text((left + xw / 2, c + s * 0.06), "x", fill=0, font=small, anchor="mm", stroke_width=int(s * 0.015),
           stroke_fill=0)
    d.text((left + xw + tw / 2, c + s * 0.02), "2", fill=0, font=big, anchor="mm", stroke_width=int(s * 0.025),
           stroke_fill=0)


def hit(d, s):
    """A triangle pointing down: another card."""
    d.polygon([(s * 0.08, s * 0.2), (s * 0.92, s * 0.2), (s * 0.5, s * 0.84)], fill=255)


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    for name, fn in (("Spade", spade), ("Heart", heart), ("Diamond", diamond), ("Club", club), ("Stand", stand),
                     ("Split", split), ("Double", double), ("Hit", hit)):
        white(shape(SIZE, fn)).save(OUT / (name + ".tga"))
    print("wrote", ", ".join(p.name for p in sorted(OUT.glob("*.tga"))))


if __name__ == "__main__":
    main()
