"""Textures for the Games module (Media/Games/*.tga): white shapes on transparent, tinted in game by theme role.

  Spade.tga, Heart.tga, Diamond.tga, Club.tga   the four suits, drawn from circles and polygons
  Stand.tga, Split.tga, Double.tga, Hit.tga     the blackjack play buttons' icons (a hand, two cards, a x2 chip,
                                                an arrow down)
  Felt.tga, Rail.tga                            the table: grey felt (tinted by the chosen felt) and its padded rail
  PrintMain.tga, PrintRule.tga                  the rules printed on the felt, on arcs that follow the rail
  Ring.tga, Chip.tga, ChipMarks.tga             the betting circle and a chip (body, then its edge inserts)
  Shoe.tga, Tray.tga                            the dealing shoe and the discard tray, shaded grey
  Back*.tga                                     card back patterns (Cashier), 128 x 182 in a 128 x 256 texture

Run from the repo root: python tools/games_art.py. Needs Pillow. New files need a full client restart.
"""

import math
import random
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageFont

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


# The table ----------------------------------------------------------------------------------------------------------
#
# Felt-local pixels: the felt is FELT_W x FELT_H on screen (Modules/Games/Felt.lua repeats these), its curved player
# side an arc round a centre CY above the felt's top edge. The rail runs along that arc; the print sits on arcs round
# the same centre, so all of it curves together.

FELT_W, FELT_H = 540, 384
CY = -244  # the arcs' centre, above the felt
RAIL_R = FELT_H - CY  # outer edge of the rail: touches the felt's bottom in the middle
RAIL_W = 18
PRINT_TOP, PRINT_H = 80, 135  # the print texture covers felt rows PRINT_TOP .. PRINT_TOP + PRINT_H
MAIN_R, RULE_R, BAND_R = 379, 397, (410, 432)  # baselines of the big and small arc lines; the band's two edges
CINZEL = FONTS / "Cinzel-Medium.ttf"


def felt_mask(w, h, scale):
    """The felt's shape at `scale` texture pixels per felt pixel: the rectangle cut by the rail's arc."""
    ss = 4
    img = Image.new("L", (w * ss, h * ss), 0)
    d = ImageDraw.Draw(img)
    k = scale * ss
    cx, cy, r = FELT_W / 2 * k, CY * k, RAIL_R * k
    d.ellipse((cx - r, cy - r, cx + r, cy + r), fill=255)
    d.rectangle((FELT_W * k, 0, w * ss, h * ss), fill=0)
    d.rectangle((0, FELT_H * k, w * ss, h * ss), fill=0)
    return img.resize((w, h), Image.LANCZOS)


def felt(size=512):
    """Grey felt to be tinted: a fine weave, a soft light from the dealer's side and the rail's shadow near the arc."""
    scale = size / FELT_W
    rnd = random.Random(7)
    grey = Image.new("L", (size, size), 0)
    px = grey.load()
    cx, cy = FELT_W / 2, CY
    for y in range(size):
        for x in range(size):
            fx, fy = x / scale, y / scale
            r = math.hypot(fx - cx, fy - cy)
            # Light: brightest a little below the dealer's row, falling off toward the edges and the rail.
            light = 1 - 0.32 * min(math.hypot((fx - cx) / (FELT_W * 0.62), (fy - 150) / (FELT_H * 0.95)), 1) ** 1.6
            shadow = max(0.0, 1 - (RAIL_R - RAIL_W - r) / 14) * 0.25 if r < RAIL_R - RAIL_W else 0.25
            shadow = max(shadow, 0.3 * max(0.0, 1 - fy / 10))  # the top edge: the dealer's side tucks under
            weave =((x + y) % 3 == 0) * 6 + ((x - y) % 3 == 0) * 4
            v = 215 * light * (1 - shadow) + weave + rnd.uniform(-7, 7)
            px[x, y] = max(0, min(255, int(v)))
    return Image.merge("RGBA", (grey, grey, grey, felt_mask(size, size, scale)))


def rail(size=512):
    """The padded rail along the curved side: a rounded tube, lit from above, to be tinted."""
    scale = size / FELT_W
    ss = 2
    big = size * ss
    grey = Image.new("L", (big, big), 0)
    alpha = Image.new("L", (big, big), 0)
    gp, ap = grey.load(), alpha.load()
    k = scale * ss
    cx, cy = FELT_W / 2 * k, CY * k
    outer, inner = RAIL_R * k, (RAIL_R - RAIL_W) * k
    for y in range(big):
        for x in range(big):
            if x >= FELT_W * k or y >= FELT_H * k:
                continue
            r = math.hypot(x - cx, y - cy)
            if inner <= r <= outer:
                t = (r - inner) / (outer - inner)  # 0 at the felt, 1 at the outside
                tube = math.sin(math.pi * t)
                highlight = math.exp(-((t - 0.32) / 0.12) ** 2)
                gp[x, y] = int(min(255, 95 + 120 * tube + 60 * highlight))
                ap[x, y] = 255
    # Stitching: a dashed line along the rail's inner edge.
    d = ImageDraw.Draw(alpha)
    dg = ImageDraw.Draw(grey)
    seam = inner + 3.5 * k
    steps = 900
    for i in range(steps):
        if i % 3 == 0:
            continue
        a0, a1 = -math.pi / 2 + math.pi * i / steps, -math.pi / 2 + math.pi * (i + 1) / steps
        x0, y0 = cx + seam * math.sin(a0), cy + seam * math.cos(a0)
        x1, y1 = cx + seam * math.sin(a1), cy + seam * math.cos(a1)
        if 0 <= x0 < FELT_W * k and 0 <= y0 < FELT_H * k:
            dg.line((x0, y0, x1, y1), fill=235, width=max(1, int(k * 0.8)))
    grey = grey.resize((size, size), Image.LANCZOS)
    alpha = alpha.resize((size, size), Image.LANCZOS)
    return Image.merge("RGBA", (grey, grey, grey, alpha))


def arc_text(mask, text, font, radius, scale, top, tracking=0.0):
    """Draws text on mask so it follows the arc of `radius` round the table's centre, as a smile, each letter upright
    to the centre. scale: mask pixels per felt pixel; top: the felt row at the mask's top."""
    cx, cy = FELT_W / 2 * scale, (CY - top) * scale
    r = radius * scale
    widths = [font.getlength(ch) + tracking * font.size for ch in text]
    total = sum(widths)
    # Letters sit above the baseline: spacing measured half a cap height in keeps them even.
    r_mid = r - font.size * 0.35
    angle = total / 2 / r_mid
    cell = int(font.size * 2.2)
    for ch, w in zip(text, widths):
        mid = angle - w / 2 / r_mid
        angle -= w / r_mid
        if ch == " ":
            continue
        glyph = Image.new("L", (cell, cell), 0)
        ImageDraw.Draw(glyph).text((cell / 2, cell / 2), ch, fill=255, font=font, anchor="ms")
        glyph = glyph.rotate(-math.degrees(mid), resample=Image.BICUBIC)
        x, y = cx - r * math.sin(mid), cy + r * math.cos(mid)
        layer = Image.new("L", mask.size, 0)
        layer.paste(glyph, (int(round(x - cell / 2)), int(round(y - cell / 2))))
        mask.paste(ImageChops.lighter(mask, layer))


def arc_band(mask, r0, r1, half_angle, scale, top, width):
    d = ImageDraw.Draw(mask)
    cx, cy = FELT_W / 2 * scale, (CY - top) * scale
    for r in (r0, r1):
        rr = r * scale
        pts = []
        for i in range(201):
            a = -half_angle + 2 * half_angle * i / 200
            pts.append((cx + rr * math.sin(a), cy + rr * math.cos(a)))
        d.line(pts, fill=255, width=width, joint="curve")
    for a in (-half_angle, half_angle):  # the band's ends
        d.line([(cx + r0 * scale * math.sin(a), cy + r0 * scale * math.cos(a)),
                (cx + r1 * scale * math.sin(a), cy + r1 * scale * math.cos(a))], fill=255, width=width)


def print_layers(w=1024, h=256):
    """The rules printed on the felt, white, two textures: PrintMain (BLACKJACK PAYS 3 TO 2 and the band, tinted
    accent) and PrintRule (the dealer's rule, tinted a faint text color)."""
    ss = 2
    scale = w / FELT_W * ss
    main = Image.new("L", (w * ss, h * ss), 0)
    rule = Image.new("L", (w * ss, h * ss), 0)
    arc_text(main, "BLACKJACK PAYS 3 TO 2", ImageFont.truetype(str(CINZEL), int(23 * scale)), MAIN_R, scale,
             PRINT_TOP, tracking=0.06)
    arc_text(rule, "DEALER MUST DRAW TO 16 AND STAND ON ALL 17'S", ImageFont.truetype(str(CINZEL), int(9.5 * scale)),
             RULE_R, scale, PRINT_TOP, tracking=0.12)
    band_font = ImageFont.truetype(str(CINZEL), int(9 * scale))
    band_text = "DOUBLE ON ANY TWO CARDS"
    arc_band(main, BAND_R[0], BAND_R[1], 0.42, scale, PRINT_TOP, max(1, int(scale * 0.9)))
    arc_text(main, band_text, band_font, BAND_R[1] - 7, scale, PRINT_TOP, tracking=0.25)
    return (white(main.resize((w, h), Image.LANCZOS)), white(rule.resize((w, h), Image.LANCZOS)))


def bet_ring(d, s):
    """The betting circle: a ring with a thin second ring inside."""
    c = s / 2
    for r, w in ((s * 0.48, s * 0.035), (s * 0.40, s * 0.014)):
        d.ellipse((c - r, c - r, c + r, c + r), outline=255, width=max(1, int(w)))


def chip(d, s):
    """A chip seen from above: the body, to be tinted by its value."""
    c, r = s / 2, s * 0.48
    d.ellipse((c - r, c - r, c + r, c + r), fill=255)


def chip_marks(d, s):
    """A chip's edge inserts and inner ring, drawn over the body in a light color."""
    c, r = s / 2, s * 0.48
    for i in range(6):
        a0 = i * 60 - 9
        d.pieslice((c - r, c - r, c + r, c + r), a0, a0 + 18, fill=255)
    hole = r * 0.78
    d.ellipse((c - hole, c - hole, c + hole, c + hole), fill=0)
    for rr, w in ((r * 0.62, s * 0.03),):
        d.ellipse((c - rr, c - rr, c + rr, c + rr), outline=255, width=max(1, int(w)))


def shoe(d, s):
    """The dealing shoe from above at an angle: a box with a sloped front and a card showing in its mouth."""
    d.polygon([(s * 0.10, s * 0.28), (s * 0.80, s * 0.18), (s * 0.92, s * 0.62), (s * 0.20, s * 0.80)], fill=150)
    d.polygon([(s * 0.10, s * 0.28), (s * 0.80, s * 0.18), (s * 0.82, s * 0.28), (s * 0.12, s * 0.38)], fill=215)
    d.polygon([(s * 0.20, s * 0.80), (s * 0.92, s * 0.62), (s * 0.94, s * 0.70), (s * 0.22, s * 0.88)], fill=95)
    d.polygon([(s * 0.30, s * 0.50), (s * 0.70, s * 0.44), (s * 0.78, s * 0.64), (s * 0.36, s * 0.72)], fill=255)


def tray(d, s):
    """The discard tray: a shallow box with a few cards lying in it."""
    d.rounded_rectangle((s * 0.08, s * 0.24, s * 0.92, s * 0.78), radius=s * 0.06, fill=150)
    d.rounded_rectangle((s * 0.14, s * 0.30, s * 0.86, s * 0.72), radius=s * 0.04, fill=95)
    for i in range(4):
        y = s * (0.40 + i * 0.06)
        d.rectangle((s * 0.22, y, s * 0.78, y + s * 0.025), fill=235)


def grey_shape(size, fn):
    """Like shape(), but the fill value is kept as brightness: a shaded grey drawing, tinted in game."""
    big = Image.new("L", (size * 4, size * 4), 0)
    fn(ImageDraw.Draw(big), size * 4)
    grey = big.resize((size, size), Image.LANCZOS)
    alpha = big.point(lambda v: 255 if v > 0 else 0).resize((size, size), Image.LANCZOS)
    out = Image.merge("RGBA", (grey, grey, grey, alpha))
    # Unpremultiply: the downsample darkened the edges along with their coverage.
    px = out.load()
    for y in range(size):
        for x in range(size):
            v, _, _, a = px[x, y]
            if 0 < a < 255:
                v = min(255, int(v * 255 / a))
                px[x, y] = (v, v, v, a)
    return out


# Card backs: a pattern over the back's base color, 128 x 182 inside a 128 x 256 texture (a card is 52 x 74).

BACK_W, BACK_H = 128, 182


def back_lattice(d, w, h):
    step = 14
    for i in range(-h, w + h, step):
        d.line((i, 0, i + h, h), fill=255, width=2)
        d.line((i, h, i + h, 0), fill=255, width=2)


def back_sunburst(d, w, h):
    cx, cy = w / 2, h / 2
    for i in range(24):
        a0, a1 = math.radians(i * 15), math.radians(i * 15 + 6)
        far = w + h
        d.polygon([(cx, cy), (cx + far * math.cos(a0), cy + far * math.sin(a0)),
                   (cx + far * math.cos(a1), cy + far * math.sin(a1))], fill=255)
    r = w * 0.17
    d.ellipse((cx - r * 1.35, cy - r * 1.35, cx + r * 1.35, cy + r * 1.35), fill=0)
    d.ellipse((cx - r, cy - r, cx + r, cy + r), fill=255)


def back_damask(d, w, h):
    step = 22
    for row, y in enumerate(range(-step, h + step, step)):
        for x in range(-step, w + step, step):
            x0 = x + (step / 2 if row % 2 else 0)
            p = step * 0.32
            d.polygon([(x0, y - p), (x0 + p * 0.7, y), (x0, y + p), (x0 - p * 0.7, y)], fill=255)
            q = step * 0.09
            d.ellipse((x0 + step / 2 - q, y - q, x0 + step / 2 + q, y + q), fill=255)


def back_stars(d, w, h):
    rnd = random.Random(3)
    for _ in range(70):
        x, y, s = rnd.uniform(0, w), rnd.uniform(0, h), rnd.uniform(2, 5)
        d.polygon([(x, y - s), (x + s * 0.3, y - s * 0.3), (x + s, y), (x + s * 0.3, y + s * 0.3), (x, y + s),
                   (x - s * 0.3, y + s * 0.3), (x - s, y), (x - s * 0.3, y - s * 0.3)], fill=255)
    cx, cy, r = w / 2, h / 2, w * 0.2
    d.ellipse((cx - r * 1.3, cy - r * 1.3, cx + r * 1.3, cy + r * 1.3), fill=0)
    d.ellipse((cx - r, cy - r, cx + r, cy + r), fill=255)
    d.ellipse((cx - r * 0.55, cy - r * 1.05, cx + r * 1.25, cy + r * 0.75), fill=0)


def back_spades(d, w, h):
    s = 20
    for row, y in enumerate(range(0, h + s, s)):
        for x in range(0, w + s, s):
            ox = x + (s / 2 if row % 2 else 0) - s / 2
            tile = Image.new("L", (s * 4, s * 4), 0)
            spade(ImageDraw.Draw(tile), s * 4)
            d.bitmap((ox - s * 0.3, y - s * 0.3), tile.resize((int(s * 0.6), int(s * 0.6)), Image.LANCZOS), fill=255)


def back_chevron(d, w, h):
    step, depth = 16, 10
    for y in range(-step, h + step, step):
        pts = []
        for x in range(0, w + depth * 2, depth * 2):
            pts += [(x, y + depth), (x + depth, y)]
        d.line(pts, fill=255, width=4, joint="curve")


def back_waves(d, w, h):
    for y in range(4, h + 12, 11):
        pts = [(x, y + 3.5 * math.sin(x / 9.0 + y * 0.3)) for x in range(0, w + 1, 2)]
        d.line(pts, fill=255, width=3, joint="curve")


BACKS = (("BackLattice", back_lattice), ("BackSunburst", back_sunburst), ("BackDamask", back_damask),
         ("BackStars", back_stars), ("BackSpades", back_spades), ("BackChevron", back_chevron),
         ("BackWaves", back_waves))


def back(fn):
    """A card back's pattern: drawn supersampled through ScaledDraw, so patterns think in final pixels."""
    ss = 4
    tmp = Image.new("L", (BACK_W * ss, BACK_H * ss), 0)
    fn(ScaledDraw(ImageDraw.Draw(tmp), ss), BACK_W, BACK_H)
    big = tmp.resize((BACK_W, BACK_H), Image.LANCZOS)
    out = Image.new("L", (128, 256), 0)
    out.paste(big, (0, 0))
    return white(out)


class ScaledDraw:
    """An ImageDraw that takes final-size coordinates and draws them ss times bigger (for supersampling)."""

    def __init__(self, d, ss):
        self.d, self.ss = d, ss

    def _pts(self, pts):
        return [(x * self.ss, y * self.ss) for x, y in pts]

    def line(self, xy, fill, width=1, joint=None):
        if len(xy) == 4 and not isinstance(xy[0], tuple):
            xy = [(xy[0], xy[1]), (xy[2], xy[3])]
        self.d.line(self._pts(xy), fill=fill, width=int(width * self.ss), joint=joint)

    def polygon(self, pts, fill):
        self.d.polygon(self._pts(pts), fill=fill)

    def ellipse(self, box, fill):
        self.d.ellipse([v * self.ss for v in box], fill=fill)

    def bitmap(self, xy, img, fill):
        big = img.resize((img.width * self.ss, img.height * self.ss), Image.LANCZOS)
        self.d.bitmap((int(xy[0] * self.ss), int(xy[1] * self.ss)), big, fill=fill)


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    for name, fn in (("Spade", spade), ("Heart", heart), ("Diamond", diamond), ("Club", club), ("Stand", stand),
                     ("Split", split), ("Double", double), ("Hit", hit)):
        white(shape(SIZE, fn)).save(OUT / (name + ".tga"))
    felt().save(OUT / "Felt.tga")
    rail().save(OUT / "Rail.tga")
    main_print, rule_print = print_layers()
    main_print.save(OUT / "PrintMain.tga")
    rule_print.save(OUT / "PrintRule.tga")
    white(shape(128, bet_ring)).save(OUT / "Ring.tga")
    white(shape(SIZE, chip)).save(OUT / "Chip.tga")
    white(shape(SIZE, chip_marks)).save(OUT / "ChipMarks.tga")
    grey_shape(SIZE * 2, shoe).save(OUT / "Shoe.tga")
    grey_shape(SIZE * 2, tray).save(OUT / "Tray.tga")
    for name, fn in BACKS:
        back(fn).save(OUT / (name + ".tga"))
    print("wrote", ", ".join(p.name for p in sorted(OUT.glob("*.tga"))))


if __name__ == "__main__":
    main()
