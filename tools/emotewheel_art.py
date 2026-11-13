"""Textures for the Emote wheel (Media/EmoteWheel/*.tga): grey shapes on transparent, tinted in game by theme role.

  Slice<N>.tga   one slice of an N-slice ring (N = 4 to 12), pointing up, with a gap on each side; shaded darker
                 toward the middle so the ring has depth. Turned into place with SetRotation.
  Arc<N>.tga     the picked slice's lit band along the outer edge, with a soft light falling inward
  Hub.tga        the middle disc, lit in the center and darker toward its edge
  HubRing.tga    a hairline circle around the middle
  Shadow.tga     soft dark shadow under the whole wheel, so it reads on bright ground
  Acts.tga       the editor's mark for an emote your character acts out: a figure waving
  Voice.tga      the editor's mark for an emote with a voice line: a speaker with two sound waves

Edges are computed analytically (distance to each edge, one pixel of ramp), so they stay clean at any size.
The geometry below must match RADIUS, INNER and GAP in Modules/EmoteWheel/Wheel.lua.

Run from the repo root: python tools/emotewheel_art.py. Needs Pillow and numpy. New files need a full client restart.
"""

import math
from pathlib import Path

import numpy as np
from PIL import Image, ImageFilter

from showcase_art import shape, white

OUT = Path(__file__).resolve().parent.parent / "Media" / "EmoteWheel"

RADIUS = 150  # the slice ring's outer edge, in wheel units (Wheel.lua)
INNER = 54  # the middle's radius
GAP = 6  # between the middle and the slices
SLICE_GAP = 3.5  # between two slices, in wheel units: a constant-width channel, not a wedge
ARC = 4  # the picked band's width at the rim
ARC_GLOW = 22  # how far the band's light reaches inward
SHADOW_PAD = 40  # the shadow texture reaches this far past the ring
SLICE_PX = 512  # slice and arc textures cover 2 * RADIUS
HUB_PX = 256  # hub textures cover 2 * INNER
SHADOW_PX = 256
GLYPH_PX = 64  # the editor's marks, shown at about 14 pixels


def grid(px, half_units):
    """x, y (y up) in wheel units at each pixel center of a px square covering -half_units .. half_units."""
    unit = 2 * half_units / px
    c = (np.arange(px) + 0.5) * unit - half_units
    x, y = np.meshgrid(c, -c)
    return x, y, unit


def cover(dist, unit):
    """Coverage from a signed distance (wheel units, positive inside): a one-pixel antialiased ramp."""
    return np.clip(dist / unit + 0.5, 0, 1)


def save(value, alpha, path):
    v = (np.clip(value, 0, 1) * 255).astype(np.uint8)
    a = (np.clip(alpha, 0, 1) * 255).astype(np.uint8)
    Image.fromarray(np.dstack([v, v, v, a]), "RGBA").save(path)


def slice_dist(x, y, count):
    """Signed distance into one slice of a count-slice ring centered on straight up."""
    h = math.pi / count
    r = np.hypot(x, y)
    left = -x * math.cos(h) + y * math.sin(h) - SLICE_GAP / 2
    right = x * math.cos(h) + y * math.sin(h) - SLICE_GAP / 2
    inner = r - (INNER + GAP)
    outer = RADIUS - r
    return np.minimum(np.minimum(left, right), np.minimum(inner, outer)), r


def slice_tex(count):
    x, y, unit = grid(SLICE_PX, RADIUS)
    d, r = slice_dist(x, y, count)
    t = np.clip((r - (INNER + GAP)) / (RADIUS - INNER - GAP), 0, 1)
    value = 0.72 + 0.2 * t ** 1.4  # darker toward the middle
    value = np.where(d < 1.2, 1.0, value)  # a lit lip along every edge
    return value, cover(d, unit)


def arc_tex(count):
    x, y, unit = grid(SLICE_PX, RADIUS)
    d, r = slice_dist(x, y, count)
    band = cover(r - (RADIUS - ARC), unit)
    inward = np.clip(RADIUS - ARC - r, 0, None)
    light = 0.32 * np.exp(-inward / (ARC_GLOW / 3))
    return np.ones_like(r), np.maximum(band, light) * cover(d, unit)


def hub_tex():
    x, y, unit = grid(HUB_PX, INNER)
    r = np.hypot(x, y)
    value = 1.0 - 0.22 * np.clip(r / INNER, 0, 1) ** 2
    return value, cover(INNER - r, unit)


def hub_ring_tex(width=1.5):
    x, y, unit = grid(HUB_PX, INNER)
    r = np.hypot(x, y)
    mid = INNER - width / 2 - unit
    return np.ones_like(r), cover(width / 2 - np.abs(r - mid), unit)


def shadow_tex():
    half = RADIUS + SHADOW_PAD
    x, y, unit = grid(SHADOW_PX, half)
    r = np.hypot(x, y)
    disc = Image.fromarray((cover(RADIUS + 4 - r, unit) * 255).astype(np.uint8), "L")
    soft = np.asarray(disc.filter(ImageFilter.GaussianBlur(14 / unit)), dtype=np.float64) / 255
    return np.zeros_like(r), soft


def acts_tex():
    """A figure waving: head, body, one arm up, legs apart (round-capped strokes)."""
    def draw(d, s):
        u = s / 64
        w = round(6 * u)

        def stroke(*pts):
            d.line([(x * u, y * u) for x, y in pts], fill=255, width=w, joint="curve")
            for x, y in (pts[0], pts[-1]):
                d.ellipse((x * u - w / 2, y * u - w / 2, x * u + w / 2, y * u + w / 2), fill=255)
        d.ellipse((24 * u, 4 * u, 38 * u, 18 * u), fill=255)
        stroke((31, 22), (30, 40))
        stroke((31, 26), (44, 18), (50, 6))
        stroke((31, 26), (19, 36))
        stroke((30, 40), (22, 58))
        stroke((30, 40), (40, 58))
    return white(shape(GLYPH_PX, draw))


def voice_tex():
    """A speaker with two sound waves."""
    def draw(d, s):
        u = s / 64
        d.rectangle((6 * u, 24 * u, 16 * u, 40 * u), fill=255)
        d.polygon([(14 * u, 24 * u), (30 * u, 10 * u), (30 * u, 54 * u), (14 * u, 40 * u)], fill=255)
        for r in (11, 21):
            d.arc((30 * u - r * u, 32 * u - r * u, 30 * u + r * u, 32 * u + r * u), -48, 48, fill=255,
                  width=round(5 * u))
    return white(shape(GLYPH_PX, draw))


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    for n in range(4, 13):
        save(*slice_tex(n), OUT / f"Slice{n}.tga")
        save(*arc_tex(n), OUT / f"Arc{n}.tga")
    save(*hub_tex(), OUT / "Hub.tga")
    save(*hub_ring_tex(), OUT / "HubRing.tga")
    save(*shadow_tex(), OUT / "Shadow.tga")
    acts_tex().save(OUT / "Acts.tga")
    voice_tex().save(OUT / "Voice.tga")
    print("wrote", ", ".join(p.name for p in sorted(OUT.glob("*.tga"))))


if __name__ == "__main__":
    main()
