"""Textures for the Cursor highlight module (Media/Cursor/*.tga): white shapes on transparent, antialiased, tinted in
game (theme accent, class color, a custom color or a rainbow). Power-of-two sizes, big enough to stay sharp when
the ring is shown at up to 160 UI units with a shake pop on a 4K screen.

  Ring.tga       thin circle outline (the default ring)
  RingThick.tga  bold circle outline
  Glow.tga       soft halo: brightest a little inside the edge, fading out both ways, an open middle
  Crosshair.tga  thin circle with four ticks pointing in toward the cursor
  Dot.tga        soft glowing dot (trail)
  Star.tga       five-pointed star with a faint glow (trail)
  Sparkle.tga    four-pointed twinkle with long thin rays and a bright core (trail)
  RingSmall.tga  thin circle outline for trail rings

Run from the repo root: python tools/cursor_art.py. Needs Pillow. New files need a full client restart.
"""

import math
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageFilter

from artlib import white

OUT = Path(__file__).resolve().parent.parent / "Media" / "Cursor"
SS = 4  # supersampling for antialiased edges


def shape(size, draw_fn):
    """Draw at SS x size with draw_fn(draw, big_size), downsample: an antialiased L mask."""
    big = Image.new("L", (size * SS, size * SS), 0)
    draw_fn(ImageDraw.Draw(big), size * SS)
    return big.resize((size, size), Image.LANCZOS)


def radial(size, fn):
    """L mask from fn(d) -> 0..1, d = distance from the center as a fraction of the half size."""
    img = Image.new("L", (size, size))
    pix = img.load()
    c = (size - 1) / 2
    for y in range(size):
        for x in range(size):
            pix[x, y] = int(255 * max(0.0, min(1.0, fn(math.hypot(x - c, y - c) / c))))
    return img


def ring(size, width):
    """Circle outline `width` pixels (at the final size) wide, touching the edge less a small margin."""
    def draw(d, s):
        m = 2 * SS
        d.ellipse((m, m, s - m, s - m), outline=255, width=round(width * SS))
    return shape(size, draw)


def glow(size):
    # A wide soft band peaking at 0.62 of the radius: the cursor itself stays clear in the middle.
    def fn(d):
        if d >= 1:
            return 0.0
        inner = math.exp(-((d - 0.62) / 0.16) ** 2)
        outer = math.exp(-((d - 0.62) / 0.22) ** 2)
        return (inner if d < 0.62 else outer) * (1 - d ** 8)
    return radial(size, fn)


def crosshair(size):
    line = size * 0.022  # a little bolder than the thin ring so the ticks read at small sizes

    def draw(d, s):
        m, w = 2 * SS, round(line * SS)
        d.ellipse((m, m, s - m, s - m), outline=255, width=w)
        c = s / 2
        tick_out, tick_in = c - m - w * 0.5, c * 0.42  # from the circle in to 42% of the radius
        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            x0, y0 = c + dx * tick_in, c + dy * tick_in
            x1, y1 = c + dx * tick_out, c + dy * tick_out
            d.line((x0, y0, x1, y1), fill=255, width=w)
    return shape(size, draw)


def dot(size):
    return radial(size, lambda d: math.exp(-(d / 0.42) ** 2) * (1 - d ** 6) if d < 1 else 0.0)


def with_glow(mask, blur, strength):
    """The mask plus a soft blurred copy of itself around it."""
    halo = mask.filter(ImageFilter.GaussianBlur(blur)).point(lambda v: int(v * strength))
    return ImageChops.lighter(mask, halo)


def star(size):
    def draw(d, s):
        c, r, k = s / 2, s * 0.36, s * 0.36 * 0.42
        pts = []
        for i in range(10):
            ang = math.pi / 2 + i * math.pi / 5
            rad = r if i % 2 == 0 else k
            pts.append((c + rad * math.cos(ang), c - rad * math.sin(ang)))
        d.polygon(pts, fill=255)
    return with_glow(shape(size, draw), size * 0.06, 0.8)


def sparkle(size):
    # Four rays with concave sides (a twinkle, not a diamond), longer up/down than sideways.
    def draw(d, s):
        c = s / 2
        pts = []
        for i in range(720):
            ang = i * math.pi / 360  # from straight up, clockwise
            length = 0.46 - 0.12 * math.sin(ang) ** 2  # 0.46 of the size up and down, 0.34 sideways
            ray = abs(math.cos(2 * ang)) ** 24  # 1 on the four axes, falling off fast in between
            rad = s * (0.035 + length * ray)
            pts.append((c + rad * math.sin(ang), c - rad * math.cos(ang)))
        d.polygon(pts, fill=255)
    core = radial(size, lambda d: math.exp(-(d / 0.18) ** 2))
    return ImageChops.lighter(with_glow(shape(size, draw), size * 0.03, 0.7), core)


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    # 512 pixels shown at 64 UI units: an 18-pixel line is about 2 units, a 44-pixel line about 5.5.
    white(ring(512, 18)).save(OUT / "Ring.tga")
    white(ring(512, 44)).save(OUT / "RingThick.tga")
    white(glow(512)).save(OUT / "Glow.tga")
    white(crosshair(512)).save(OUT / "Crosshair.tga")
    white(dot(128)).save(OUT / "Dot.tga")
    white(star(128)).save(OUT / "Star.tga")
    white(sparkle(256)).save(OUT / "Sparkle.tga")
    # Trail rings are shown at 8 to 30 units: 10 of 128 pixels stays one to two pixels wide.
    white(ring(128, 10)).save(OUT / "RingSmall.tga")
    print("wrote", ", ".join(p.name for p in sorted(OUT.glob("*.tga"))))


if __name__ == "__main__":
    main()
