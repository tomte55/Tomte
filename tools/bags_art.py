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
    d.arc(P(21, 6, 43, 30), 180, 360, fill=255, width=W(5))
    d.line([P(21, 18), P(21, 24)], fill=255, width=W(5))
    d.line([P(43, 18), P(43, 24)], fill=255, width=W(5))
    # The body, and the flap's edge cut across it.
    d.rounded_rectangle(P(10, 22, 54, 58), radius=W(8), fill=255)
    d.line([P(10, 33), P(54, 33)], fill=0, width=W(CUT))
    d.rounded_rectangle(P(28, 30, 36, 40), radius=W(2), fill=0)
    d.rounded_rectangle(P(30, 32, 34, 38), radius=W(1), fill=255)
    save(img, "Bag")


def people():
    img, d = canvas()
    # The one behind, to the right.
    d.ellipse(P(35, 12, 51, 28), fill=255)
    d.pieslice(P(30, 31, 60, 71), 180, 360, fill=255)
    # The one in front, with a cut around it so the two read apart.
    d.ellipse(P(13 - CUT, 14 - CUT, 33 + CUT, 34 + CUT), fill=0)
    d.pieslice(P(4 - CUT, 36 - CUT, 42 + CUT, 84 + CUT), 180, 360, fill=0)
    d.ellipse(P(13, 14, 33, 34), fill=255)
    d.pieslice(P(4, 36, 42, 84), 180, 360, fill=255)
    d.rectangle(P(0, 60, 64, 64), fill=0)
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
        half, r0, r1 = 5, 14, 28
        pts = [(c + dx * r0 + px * half, c + dy * r0 + py * half), (c + dx * r1 + px * half, c + dy * r1 + py * half),
            (c + dx * r1 - px * half, c + dy * r1 - py * half), (c + dx * r0 - px * half, c + dy * r0 - py * half)]
        d.polygon([P(x, y) for x, y in pts], fill=255)
    d.ellipse(P(c - 21, c - 21, c + 21, c + 21), fill=255)
    d.ellipse(P(c - 8, c - 8, c + 8, c + 8), fill=0)
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
