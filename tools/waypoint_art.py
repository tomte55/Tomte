"""The Waypoints arrow (Media/Travel/Arrow.tga), shown on World of Warcraft: Forever, which has no in-world markers: a
navigation arrowhead with a notch at the back, lying flat on the ground and seen from behind and above, so pointing
ahead reads as pointing forward. A flat picture can't be turned in game and stay flat, so this is a sheet of FRAMES
directions (8 x 8 cells, the first pointing ahead, then turning left), and Marker.lua picks the cell.

Each cell: the top face white, its thickness below it grey, a black outline round both. The game tints it with the
theme's accent (SetVertexColor): the top is the accent, the side a darker accent, the outline stays black.

Run from the repo root: python tools/waypoint_art.py. Needs Pillow. A new or changed file needs a full client restart.
"""

import math
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageFilter

OUT = Path(__file__).resolve().parent.parent / "Media" / "Travel"
GRID = 8
FRAMES = GRID * GRID  # 64 directions, 5.6 degrees apart
CELL = 128  # shown at about 48 UI units
SS = 4  # supersampling for antialiased edges
# The arrowhead on the ground, pointing ahead (+y), as fractions of the cell: tip, right wing, notch, left wing.
SHAPE = [(0.0, 0.40), (0.30, -0.30), (0.0, -0.13), (-0.30, -0.30)]
FLAT = 0.38  # how much the ground squashes toward the camera: 1 is seen from straight above
THICK = 0.06  # the arrow's thickness, as a fraction of the cell
OUTLINE = 4  # pixels at the cell size
SIDE = 140  # the thickness's grey: tinted, a darker accent


def cell(angle):
    """One direction: angle in radians, 0 = ahead, growing to the left."""
    big = CELL * SS
    c = big / 2
    cos, sin = math.cos(angle), math.sin(angle)
    points = []
    for x, y in SHAPE:
        gx, gy = x * cos - y * sin, x * sin + y * cos
        points.append((c + gx * big, c - gy * FLAT * big - THICK * big / 2))
    top = Image.new("L", (big, big), 0)
    ImageDraw.Draw(top).polygon(points, fill=255)
    # The thickness: the face moved down step by step, merged.
    body = top.copy()
    steps = int(THICK * big)
    for d in range(1, steps + 1):
        body = ImageChops.lighter(body, ImageChops.offset(top, 0, d))
    grown = body.filter(ImageFilter.MaxFilter(OUTLINE * SS * 2 + 1))
    top, body, grown = (m.resize((CELL, CELL), Image.LANCZOS) for m in (top, body, grown))
    img = Image.new("RGBA", (CELL, CELL), (0, 0, 0, 0))
    img = Image.composite(Image.new("RGBA", (CELL, CELL), (0, 0, 0, 235)), img, grown)
    img = Image.composite(Image.new("RGBA", (CELL, CELL), (SIDE, SIDE, SIDE, 255)), img, body)
    img = Image.composite(Image.new("RGBA", (CELL, CELL), (255, 255, 255, 255)), img, top)
    img.putalpha(ImageChops.lighter(grown, body))
    return img


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    sheet = Image.new("RGBA", (CELL * GRID, CELL * GRID), (0, 0, 0, 0))
    for i in range(FRAMES):
        sheet.paste(cell(i * 2 * math.pi / FRAMES), ((i % GRID) * CELL, (i // GRID) * CELL))
    sheet.save(OUT / "Arrow.tga")
    print("wrote", OUT / "Arrow.tga")


if __name__ == "__main__":
    main()
