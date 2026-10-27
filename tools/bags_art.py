"""Icons for the Bags windows' header and footer buttons (Media/Bags/*.tga): white shapes on transparent, tinted in game
by theme role, so they fit every theme. Drawn on a 64 grid (supersampled), filled shapes with cut-outs: they're shown at
18 pixels, where thin outlines and item art turn into blobs.

  Bag       a bag with a handle (the bag slots)
  People    two people (other characters)
  Bank      a building with columns
  Broom     a broom (Clean Up)
  Star      a five-point star (saved searches)
  Gear      a gear (settings)
  Coin      a coin (currencies)
  Close     an X

Run from the repo root: python tools/bags_art.py. Needs Pillow. New files need a full client restart.
"""

import math
from pathlib import Path

from PIL import Image, ImageDraw

from artlib import finish

OUT = Path(__file__).resolve().parent.parent / "Media" / "Bags"
SIZE = 64  # the saved texture
SS = 8  # supersampling
CUT = 3.5  # a cut-out's width (gap between parts), in grid units


def canvas():
    img = Image.new("L", (SIZE * SS, SIZE * SS), 0)
    return img, ImageDraw.Draw(img)


def P(*xy):
    """Grid units to canvas pixels: P(x, y) or P(x0, y0, x1, y1)."""
    return tuple(v * SS for v in xy)


def W(units):
    return max(1, round(units * SS))


def save(img, name):
    finish(img, SIZE, SIZE).save(OUT / (name + ".tga"))


def bag():
    img, d = canvas()
    # The handle: a thick arc over the body.
    d.arc(P(20, 4, 44, 30), 180, 360, fill=255, width=W(5))
    d.line([P(20, 16), P(20, 24)], fill=255, width=W(5))
    d.line([P(44, 16), P(44, 24)], fill=255, width=W(5))
    # The body (as wide as the other icons), and the flap's edge cut across it with a clasp.
    d.rounded_rectangle(P(5, 22, 59, 60), radius=W(8), fill=255)
    d.line([P(5, 34), P(59, 34)], fill=0, width=W(CUT))
    d.rounded_rectangle(P(27, 30, 37, 42), radius=W(2), fill=0)
    d.rounded_rectangle(P(29.5, 32.5, 34.5, 39.5), radius=W(1), fill=255)
    save(img, "Bag")


def people():
    img, d = canvas()
    # The one behind, to the right.
    d.ellipse(P(35, 4, 52, 21), fill=255)
    d.pieslice(P(30, 25, 61, 79), 180, 360, fill=255)
    # The one in front, with a cut around it so the two read apart; as tall as the other icons.
    d.ellipse(P(12 - CUT, 5 - CUT, 34 + CUT, 27 + CUT), fill=0)
    d.pieslice(P(3 - CUT, 30 - CUT, 43 + CUT, 92 + CUT), 180, 360, fill=0)
    d.ellipse(P(12, 5, 34, 27), fill=255)
    d.pieslice(P(3, 30, 43, 92), 180, 360, fill=255)
    save(img, "People")


def bank():
    img, d = canvas()
    d.polygon([P(6, 22), P(32, 6), P(58, 22)], fill=255)  # the roof
    d.rectangle(P(8, 24, 56, 28), fill=255)  # the beam under it
    for x in (11, 22.5, 35.5, 47):  # the columns
        d.rectangle(P(x, 31, x + 6, 48), fill=255)
    d.rectangle(P(8, 51, 56, 55), fill=255)  # the steps
    d.rectangle(P(4, 57, 60, 60), fill=255)
    save(img, "Bank")


def broom():
    img, d = canvas()
    # The handle, from the top right down to the binding.
    d.line([P(56, 6), P(34, 32)], fill=255, width=W(7))
    # The bristles: a wide fan below the binding, a few strands cut into it.
    d.polygon([P(22, 26), P(44, 40), P(34, 62), P(2, 50)], fill=255)
    d.line([P(22, 30), P(43, 44)], fill=0, width=W(CUT))  # the binding's edge
    for (x0, y0, x1, y1) in ((28, 46, 20, 58), (18, 40, 8, 50)):
        d.line([P(x0, y0), P(x1, y1)], fill=0, width=W(2.5))
    save(img, "Broom")


def star():
    img, d = canvas()
    c, outer, inner = 32, 28, 11.5
    pts = []
    for i in range(10):
        ang = math.pi / 2 + i * math.pi / 5
        r = outer if i % 2 == 0 else inner
        pts.append(P(c + r * math.cos(ang), c + 2 - r * math.sin(ang)))
    d.polygon(pts, fill=255)
    save(img, "Star")


def gear():
    img, d = canvas()
    c, teeth = 32, 8
    for i in range(teeth):
        ang = i * 2 * math.pi / teeth
        dx, dy = math.cos(ang), math.sin(ang)
        px, py = -dy, dx
        half, r0, r1 = 4.5, 13, 25  # a little inside the square, so it weighs the same as the other icons
        pts = [(c + dx * r0 + px * half, c + dy * r0 + py * half), (c + dx * r1 + px * half, c + dy * r1 + py * half),
            (c + dx * r1 - px * half, c + dy * r1 - py * half), (c + dx * r0 - px * half, c + dy * r0 - py * half)]
        d.polygon([P(x, y) for x, y in pts], fill=255)
    d.ellipse(P(c - 18.5, c - 18.5, c + 18.5, c + 18.5), fill=255)
    d.ellipse(P(c - 7, c - 7, c + 7, c + 7), fill=0)
    save(img, "Gear")


def coin():
    img, d = canvas()
    # Two coins, the front one over the back one with a cut between them; each with a ring inside its rim.
    d.ellipse(P(4, 4, 42, 42), fill=255)
    d.ellipse(P(10, 10, 36, 36), outline=0, width=W(CUT))
    d.ellipse(P(20 - CUT, 20 - CUT, 60 + CUT, 60 + CUT), fill=0)
    d.ellipse(P(20, 20, 60, 60), fill=255)
    d.ellipse(P(27, 27, 53, 53), outline=0, width=W(CUT))
    save(img, "Coin")


def close():
    img, d = canvas()
    d.line([P(14, 14), P(50, 50)], fill=255, width=W(7))
    d.line([P(50, 14), P(14, 50)], fill=255, width=W(7))
    save(img, "Close")


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    for draw in (bag, people, bank, broom, star, gear, coin, close):
        draw()
    print("wrote", ", ".join(p.name for p in sorted(OUT.glob("*.tga"))))


if __name__ == "__main__":
    main()
