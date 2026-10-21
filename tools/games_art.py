"""Textures for the Games module (Media/Games/*.tga): white card suits on transparent, tinted in game by theme role.

  Spade.tga, Heart.tga, Diamond.tga, Club.tga   the four suits, drawn from circles and polygons

Run from the repo root: python tools/games_art.py. Needs Pillow. New files need a full client restart.
"""

from pathlib import Path

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


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    for name, fn in (("Spade", spade), ("Heart", heart), ("Diamond", diamond), ("Club", club)):
        white(shape(SIZE, fn)).save(OUT / (name + ".tga"))
    print("wrote", ", ".join(p.name for p in sorted(OUT.glob("*.tga"))))


if __name__ == "__main__":
    main()
