"""Textures for the Showcase module (Media/Showcase/*.tga): white shapes on transparent, tinted in game by theme
role or item quality.

  Diamond.tga   filled diamond (a square turned 45 degrees), antialiased; also the icon mask
  Glow.tga      soft diamond glow behind a slot
  Ring.tga      thin circle outline (item level dial, empty sockets)
  RingThick.tga the item level dial's track
  Dot.tga       soft round dot (leader line ends, dial ticks)
  Star.tga      small four-pointed star (enchant line)

Run from the repo root: python tools/showcase_art.py. Needs Pillow. New files need a full client restart.
"""

import math
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

OUT = Path(__file__).resolve().parent.parent / "Media" / "Showcase"
SS = 4  # supersampling for antialiased edges


def white(alpha):
    out = Image.new("RGBA", alpha.size, (255, 255, 255, 0))
    out.putalpha(alpha)
    return out


def shape(size, draw_fn):
    """Draw at SS x size with draw_fn(draw, big_size), downsample: an antialiased L mask."""
    big = Image.new("L", (size * SS, size * SS), 0)
    draw_fn(ImageDraw.Draw(big), size * SS)
    return big.resize((size, size), Image.LANCZOS)


def diamond_points(s, inset):
    c = s / 2
    r = c - inset
    return [(c, c - r), (c + r, c), (c, c + r), (c - r, c)]


def diamond(size=64):
    return white(shape(size, lambda d, s: d.polygon(diamond_points(s, SS), fill=255)))


def glow(size=128):
    a = shape(size, lambda d, s: d.polygon(diamond_points(s, s * 0.2), fill=255))
    a = a.filter(ImageFilter.GaussianBlur(size * 0.1))
    return white(a)


def ring(size=128, width=2):
    def draw(d, s):
        w = width * SS
        d.ellipse((SS, SS, s - SS, s - SS), outline=255, width=w)
    return white(shape(size, draw))


def dot(size=32):
    a = shape(size, lambda d, s: d.ellipse((s * 0.2, s * 0.2, s * 0.8, s * 0.8), fill=255))
    return white(a.filter(ImageFilter.GaussianBlur(size * 0.06)))


def star(size=32):
    def draw(d, s):
        c, r, k = s / 2, s / 2 - SS, s * 0.12
        pts = []
        for i in range(8):
            ang = math.pi / 2 - i * math.pi / 4
            rad = r if i % 2 == 0 else k
            pts.append((c + rad * math.cos(ang), c - rad * math.sin(ang)))
        d.polygon(pts, fill=255)
    return white(shape(size, draw))


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    diamond().save(OUT / "Diamond.tga")
    glow().save(OUT / "Glow.tga")
    ring().save(OUT / "Ring.tga")
    ring(width=6).save(OUT / "RingThick.tga")
    dot().save(OUT / "Dot.tga")
    star().save(OUT / "Star.tga")
    print("wrote", ", ".join(p.name for p in sorted(OUT.glob("*.tga"))))


if __name__ == "__main__":
    main()
