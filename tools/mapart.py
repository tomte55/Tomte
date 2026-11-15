"""Builds the Tomte_MapArt addon (World of Warcraft: Forever): a soft mask for each zone and continent, so the Tomte map can draw a
zone's full picture without its parchment frame and neighbours (Modules/Map/Art.lua). Also writes
Data/Forever/MapArtIndex.lua in Tomte: which masks the addon has.

A zone's mask is its territory on its continent:
- its own land: the union of its explored-area pieces (WorldMapOverlay, every piece, explored or not), closed and
  filled. The pieces only cover the zone's named areas, so own land alone leaves holes between zones, where the
  continent's far coarser picture showed;
- grown out from there over the continent's land (read from the continent picture's colours: its land is saturated,
  its sea grey) until it meets a neighbour's, at most REACH, never onto its own picture's burnt frame;
- grown a little more under its neighbours (the larger zone is drawn first, so seams have no see-through line) and
  blurred.
A zone that isn't on a continent's picture gets its own land only.

Each zone's place names (in its pieces, dark capitals on a pale glow, the same brown as its roads and mountains) are
found by their layout: small dark shapes of one height side by side on one baseline, three or more, with the words and
lines next to them. Where two zones' pieces carry a name in the same spot (a zone's map also names places just past
its edge, often cut off: Thousand Needles' "Razorfen Kraul"), only the one of the zone whose territory holds that spot
is kept; every other name is kept, also near a border (Camp Taurajo). Their boxes go in the index and a soft mask of
them in the addon (Masks/Labels<art>.tga): the map
draws those parts of the pieces again above every zone, so a neighbour's picture or the territory's edge doesn't cut a
name (Modules/Map/Art.lua). The idea of zone territories follows OpenMap's
territory masks (MIT, github.com/openmap-world/openmap, tools/map-preview/territory.py); written anew here, with
Pillow and numpy.

The masks are made from Blizzard's art, so they ship in their own addon, outside the git repo and outside Tomte's zip.

From the Tomte folder:
    python -P tools/mapart.py <build, e.g. 1.60.1.70938> <cache folder> <Tomte_MapArt folder>
(-P, not -I: Pillow and numpy may live in the user's site-packages, which -I hides.)
Downloads the tables and the BLP files it needs from wago.tools one at a time (a few hundred files, a few minutes the
first time; cached after that).
"""
import os
import sys
import time
import urllib.request
from collections import defaultdict

import numpy as np
from PIL import Image, ImageChops, ImageDraw, ImageFilter

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import wago  # noqa: E402

VERSION = 6  # bump when the masks change shape: Tomte only uses an addon whose version it knows (MapArtIndex.lua)
ART_W, ART_H = 1002, 668  # every map's art on this client (its UiMapArt layer)
TILE = 256  # art and pieces are cut in 256-pixel tiles, a piece's last row and column in the next power of two
MASK = 256  # the mask file's size (stretched over the art; soft edges don't need more)
CLOSE = 13  # art pixels: gaps between a zone's pieces up to about half this are closed
GROW = 5  # art pixels: a zone off any continent: its edge grown this much (odd) before the blur
BLUR = 4  # art pixels: that zone's soft edge
G = 2  # territory grid pixels per continent art pixel
REACH = 60  # grid pixels a zone's territory grows past its own land at most (zones are about 250 to 550 across)
MARGIN = 0.03  # share of a zone's picture on each side that is its burnt frame: never part of its territory
FRAME_FADE = 0.04  # share of a zone's picture inside that margin over which its art fades in (a hard cut there showed
# as a straight line where a zone's territory reached its picture's edge: Feralas's top over Desolace)
OVERLAP = 4  # grid pixels a territory reaches under its neighbours before the blur
SOFT = 2  # grid pixels: the territory's soft edge
LAND_S, LAND_V = 160, 110  # a continent picture's land: HSV saturation and value above these (its sea is greyer)
SHORE = 80  # art pixels of sea round a continent's land that its picture keeps (the world picture shows past it;
# wide enough that the world picture's own continent names, which sit by the coasts, stay under it)
SHORE_SOFT = 24  # art pixels: how softly that sea band fades
EDGE = (0.05, 0.15)  # share of a continent picture from each side where it is gone / whole, whatever its land (its
# frame is gone; a wide fade leaves no line where its sea and the world picture's differ in colour)
FRAME = 0.07  # share of a continent picture on each side that is never land (its burnt frame reads as land by colour)
INDEX = os.path.join("Data", "Forever", "MapArtIndex.lua")
LABEL_MASK = 512  # the names mask's size: sharper than the territories', the boxes are small
GLYPH_H, GLYPH_W, GLYPH_N = (5, 14), (2, 16), 5  # a letter: height and width in art pixels, at least this many pixels
CONTRAST = 0.66  # a letter's pixel is darker than this share of its surroundings (6-pixel box blur)
LINE_TOL, LINE_GAP = 2, 1.2  # letters of a line: top and bottom within this many pixels, gaps under this many heights
LABEL_PAD = (1.0, 0.5)  # a name's box reaches this many letter heights past its letters, sideways and up and down
# (the pale glow round them; sideways more, so an end letter the search missed is still in)
LABEL_SOFT = 3  # art pixels: how softly a name's patch fades into what's under it
LABEL_MAX_H = 5  # a name's box is at most this many letter heights tall (busy coasts otherwise grew boxes)
MAP_CONTINENT, MAP_ZONE = 2, 3


def fetch(fid, folder, build):
    path = os.path.join(folder, "%d.blp" % fid)
    if not (os.path.exists(path) and os.path.getsize(path) > 64):
        url = "https://wago.tools/api/casc/%d?download&version=%s" % (fid, build)
        req = urllib.request.Request(url, headers={"User-Agent": wago.UA})
        body = b""
        for attempt in range(5):
            try:
                with urllib.request.urlopen(req) as resp:
                    body = resp.read()
            except OSError as err:  # wago.tools answers a burst with 5xx now and then
                print("  retrying", fid, err)
            if len(body) > 64:  # a missing file answers 200 with an (almost) empty body
                break
            time.sleep(3)
        else:
            print("  no file for", fid)
            return None
        with open(path, "wb") as f:
            f.write(body)
        time.sleep(0.3)  # one at a time, gently: bursts get empty answers
    return Image.open(path).convert("RGBA")


def side(total, i, n):
    """Used pixels of tile i (0-based) of n along a side of `total`."""
    return TILE if i < n - 1 else total - (n - 1) * TILE


def fill_holes(img):
    """What the outside can't reach becomes solid. Padded so the whole outside is one region."""
    w, h = img.size
    pad = Image.new("L", (w + 4, h + 4), 0)
    pad.paste(img, (2, 2))
    ImageDraw.floodfill(pad, (0, 0), 128)
    return pad.point(lambda v: 0 if v == 128 else 255).crop((2, 2, w + 2, h + 2))


def own_land(pieces, folder, build):
    """The pieces' alpha laid out on the art, closed and filled, as a 0/255 L image."""
    land = Image.new("L", (ART_W, ART_H), 0)
    for x, y, w, h, files in pieces:
        cols, rows = -(-w // TILE), -(-h // TILE)
        for r in range(rows):
            for c in range(cols):
                i = r * cols + c
                if i >= len(files):
                    continue
                img = fetch(files[i], folder, build)
                if img is None:
                    continue
                uw, uh = side(w, c, cols), side(h, r, rows)
                alpha = img.getchannel("A").crop((0, 0, uw, uh))
                spot = Image.new("L", (ART_W, ART_H), 0)
                spot.paste(alpha, (x + c * TILE, y + r * TILE))
                land = ImageChops.lighter(land, spot)
    solid = land.point(lambda v: 255 if v > 127 else 0)
    return fill_holes(solid.filter(ImageFilter.MaxFilter(CLOSE)).filter(ImageFilter.MinFilter(CLOSE)))


def pieces_picture(pieces, folder, build):
    """The pieces drawn together (RGBA, transparent where none), as the game lays them on the art."""
    img = Image.new("RGBA", (ART_W, ART_H), (0, 0, 0, 0))
    for x, y, w, h, files in pieces:
        cols, rows = -(-w // TILE), -(-h // TILE)
        for r in range(rows):
            for c in range(cols):
                i = r * cols + c
                if i >= len(files):
                    continue
                tile = fetch(files[i], folder, build)
                if tile is None:
                    continue
                part = tile.convert("RGBA").crop((0, 0, side(w, c, cols), side(h, r, rows)))
                img.alpha_composite(part, (x + c * TILE, y + r * TILE))
    return img


def glyph_shapes(mask):
    """Connected dark shapes (8 neighbours): (left, top, right, bottom, pixels) each."""
    h, w = mask.shape
    seen = np.zeros_like(mask, bool)
    shapes = []
    for y0, x0 in zip(*np.nonzero(mask)):
        if seen[y0, x0]:
            continue
        stack = [(y0, x0)]
        seen[y0, x0] = True
        l = r = x0
        t = b = y0
        n = 0
        while stack:
            y, x = stack.pop()
            n += 1
            l, r, t, b = min(l, x), max(r, x), min(t, y), max(b, y)
            for yy in (y - 1, y, y + 1):
                for xx in (x - 1, x, x + 1):
                    if 0 <= yy < h and 0 <= xx < w and mask[yy, xx] and not seen[yy, xx]:
                        seen[yy, xx] = True
                        stack.append((yy, xx))
        shapes.append((l, t, r, b, n))
    return shapes


def label_boxes(img):
    """Boxes (left, top, right, bottom, art pixels) round the place names in a zone's pieces."""
    a = np.asarray(img).astype(float)
    lum = a[..., 0] * 0.3 + a[..., 1] * 0.59 + a[..., 2] * 0.11
    mean = np.asarray(Image.fromarray(lum.clip(0, 255).astype(np.uint8)).filter(ImageFilter.BoxBlur(6))).astype(float)
    dark = (lum < CONTRAST * mean) & (lum < 150) & (a[..., 3] > 200) & (a[..., 2] < a[..., 0])
    glyphs = sorted((g for g in glyph_shapes(dark) if GLYPH_H[0] <= g[3] - g[1] + 1 <= GLYPH_H[1]
                     and GLYPH_W[0] <= g[2] - g[0] + 1 <= GLYPH_W[1] and g[4] >= GLYPH_N), key=lambda g: g[0])
    used = [False] * len(glyphs)
    lines = []  # [left, top, right, bottom, letters, height]
    for i, g in enumerate(glyphs):
        if used[i]:
            continue
        chain, last = [g], g
        used[i] = True
        for j in range(i + 1, len(glyphs)):
            o = glyphs[j]
            if used[j]:
                continue
            gh = last[3] - last[1] + 1
            if o[0] - last[2] > LINE_GAP * gh + 1:
                if o[0] - last[2] > 3 * gh:
                    break
                continue
            if abs(o[1] - last[1]) <= LINE_TOL and abs(o[3] - last[3]) <= LINE_TOL:
                chain.append(o)
                used[j] = True
                last = o
        if len(chain) >= 2:
            lines.append([min(c[0] for c in chain), min(c[1] for c in chain), max(c[2] for c in chain),
                          max(c[3] for c in chain), len(chain), max(c[3] - c[1] + 1 for c in chain)])
    boxes = []
    taken = [False] * len(lines)
    for i, ln in enumerate(lines):
        if taken[i] or ln[4] < 3:
            continue
        box, gh = list(ln[:4]), ln[5]
        taken[i] = True
        grew = True
        while grew:
            grew = False
            for j, o in enumerate(lines):
                if taken[j] or abs(o[5] - gh) > 3:
                    continue
                if o[0] <= box[2] + 2 * gh and o[2] >= box[0] - 2 * gh and o[1] <= box[3] + 1.2 * gh \
                        and o[3] >= box[1] - 1.2 * gh and max(box[3], o[3]) - min(box[1], o[1]) <= LABEL_MAX_H * gh:
                    box = [min(box[0], o[0]), min(box[1], o[1]), max(box[2], o[2]), max(box[3], o[3])]
                    taken[j] = True
                    grew = True
        px, py = LABEL_PAD[0] * gh, LABEL_PAD[1] * gh
        boxes.append((max(int(box[0] - px), 0), max(int(box[1] - py), 0), min(int(box[2] + px + 1), ART_W),
                      min(int(box[3] + py + 1), ART_H)))
    return boxes


def label_mask(boxes):
    """The names' soft mask (art-sized L image)."""
    m = Image.new("L", (ART_W, ART_H), 0)
    d = ImageDraw.Draw(m)
    for l, t, r, b in boxes:
        d.rectangle((l, t, r, b), fill=255)
    return m.filter(ImageFilter.GaussianBlur(LABEL_SOFT))


def picture(art, art_tiles, folder, build):
    """A map's whole picture (layer 0), RGB."""
    img = Image.new("RGB", (ART_W + TILE, ART_H + TILE))
    for row, col, fid in art_tiles[art]:
        tile = fetch(fid, folder, build)
        if tile is not None:
            img.paste(tile.convert("RGB"), (col * TILE, row * TILE))
    return img.crop((0, 0, ART_W, ART_H))


def continent_land(art, art_tiles, folder, build, size):
    """Where a continent's picture shows land, as a bool grid of `size`."""
    hsv = np.asarray(picture(art, art_tiles, folder, build).filter(ImageFilter.GaussianBlur(1.5)).convert("HSV"))
    land = Image.fromarray((((hsv[..., 1] > LAND_S) & (hsv[..., 2] > LAND_V)) * 255).astype(np.uint8))
    land = fill_holes(land.filter(ImageFilter.MaxFilter(7)).filter(ImageFilter.MinFilter(7)))
    land = land.filter(ImageFilter.MinFilter(3)).filter(ImageFilter.MaxFilter(3))  # specks off
    grid = np.asarray(land.resize(size, Image.BILINEAR)) > 127
    w, h = size
    fx, fy = int(w * FRAME), int(h * FRAME)
    grid[:fy, :] = grid[h - fy:, :] = False
    grid[:, :fx] = grid[:, w - fx:] = False
    return grid


class Layout:
    """Where a zone lies on its continent's map, as C_Map.GetMapRectOnMap(zone, continent): through the zone's first
    UiMapAssignment and the continent's assignment on the same game map that holds it."""

    def __init__(self, rows):
        self.rows = defaultdict(list)
        for r in rows:
            self.rows[int(r["UiMapID"])].append(r)
        for rs in self.rows.values():
            rs.sort(key=lambda r: (int(r["OrderIndex"]), -self.area(r)))

    @staticmethod
    def area(r):
        return (float(r["UiMax_0"]) - float(r["UiMin_0"])) * (float(r["UiMax_1"]) - float(r["UiMin_1"]))

    @staticmethod
    def on(r, x, y):
        """World position x, y (yards on r's game map) as 0..1 on r's map. World x runs up the map, y to the left."""
        f = lambda k: float(r[k])
        u = f("UiMin_0") + (f("Region_4") - y) / (f("Region_4") - f("Region_1")) * (f("UiMax_0") - f("UiMin_0"))
        v = f("UiMin_1") + (f("Region_3") - x) / (f("Region_3") - f("Region_0")) * (f("UiMax_1") - f("UiMin_1"))
        return u, v

    def rect(self, zone, continent):
        """(left, top, width, height), 0..1 on the continent, or None."""
        for a in self.rows.get(zone, []):
            f = lambda k: float(a[k])
            mine = [r for r in self.rows.get(continent, []) if r["MapID"] == a["MapID"]]
            if not mine or f("UiMax_0") <= f("UiMin_0") or f("UiMax_1") <= f("UiMin_1"):
                continue
            cx, cy = (f("Region_0") + f("Region_3")) / 2, (f("Region_1") + f("Region_4")) / 2
            host = next((r for r in mine if float(r["Region_0"]) <= cx <= float(r["Region_3"])
                         and float(r["Region_1"]) <= cy <= float(r["Region_4"])), mine[0])
            u0, v0 = self.on(host, f("Region_3"), f("Region_4"))
            u1, v1 = self.on(host, f("Region_0"), f("Region_1"))
            w = (max(u0, u1) - min(u0, u1)) / (f("UiMax_0") - f("UiMin_0"))
            h = (max(v0, v1) - min(v0, v1)) / (f("UiMax_1") - f("UiMin_1"))
            return min(u0, u1) - f("UiMin_0") * w, min(v0, v1) - f("UiMin_1") * h, w, h
        return None


def territories(zones, land):
    """zones: [(left, top, width, height) in grid pixels, own land as a bool grid], drawn first to last (a later one
    wins where two own the same spot). Grows each zone's land over `land` (bool grid) until it meets another's, REACH
    at most, inside its own picture less its frame. Returns a label grid: the zone's index, -1 for none."""
    gh, gw = land.shape
    labels = np.full((gh, gw), -1, np.int16)
    land = land.copy()
    for i, (_, own) in enumerate(zones):
        labels[own] = i
        land |= own
    left = np.array([b[0] + b[2] * MARGIN for b, _ in zones])
    right = np.array([b[0] + b[2] * (1 - MARGIN) for b, _ in zones])
    top = np.array([b[1] + b[3] * MARGIN for b, _ in zones])
    bottom = np.array([b[1] + b[3] * (1 - MARGIN) for b, _ in zones])
    ys, xs = np.mgrid[0:gh, 0:gw]

    def inside(near):
        known = near >= 0
        i = np.where(known, near, 0)
        return known & (xs >= left[i]) & (xs < right[i]) & (ys >= top[i]) & (ys < bottom[i])

    for _ in range(REACH):
        free = (labels < 0) & land
        if not free.any():
            break
        grown = labels.copy()
        for dy, dx in ((0, 1), (0, -1), (1, 0), (-1, 0)):
            near = np.full_like(labels, -1)
            near[max(dy, 0):gh + min(dy, 0), max(dx, 0):gw + min(dx, 0)] = \
                labels[max(-dy, 0):gh + min(-dy, 0), max(-dx, 0):gw + min(-dx, 0)]
            take = free & (grown < 0) & inside(near)
            grown[take] = near[take]
        labels = grown
    return labels


def place(own, box, shape):
    """A zone's own land (art pixels) on the grid at box (left, top, width, height, grid pixels)."""
    x0, y0, w, h = box
    small = np.asarray(own.resize((w, h), Image.BILINEAR)) > 127
    grid = np.zeros(shape, bool)
    gx0, gy0, gx1, gy1 = max(x0, 0), max(y0, 0), min(x0 + w, shape[1]), min(y0 + h, shape[0])
    grid[gy0:gy1, gx0:gx1] = small[gy0 - y0:gy1 - y0, gx0 - x0:gx1 - x0]
    return grid


def territory_mask(labels, i, box):
    """Zone i's mask (art-sized L image): its territory, reaching OVERLAP under its neighbours, inside its picture
    less the frame (fading in over FRAME_FADE), blurred."""
    x0, y0, w, h = box
    m = Image.fromarray(((labels == i) * 255).astype(np.uint8)).filter(ImageFilter.MaxFilter(2 * OVERLAP + 1))
    m = np.asarray(m.filter(ImageFilter.GaussianBlur(SOFT))).astype(np.float32)
    gh, gw = labels.shape
    xs = (np.arange(gw) - x0) / w
    ys = (np.arange(gh) - y0) / h
    sx = np.clip((np.minimum(xs, 1 - xs) - MARGIN) / FRAME_FADE, 0, 1)
    sy = np.clip((np.minimum(ys, 1 - ys) - MARGIN) / FRAME_FADE, 0, 1)
    edge = np.minimum(sy[:, None], sx[None, :])
    edge = edge * edge * (3 - 2 * edge)
    m = Image.fromarray((m * edge).astype(np.uint8))
    return m.crop((x0, y0, x0 + w, y0 + h)).resize((ART_W, ART_H), Image.BILINEAR)


def continent_mask(land):
    """A continent's mask (art-sized L image): its land and a band of sea round it, fading out softly, and fading out
    toward its picture's frame, so the world picture under it shows past its shores without a seam."""
    small = Image.fromarray((land * 255).astype(np.uint8)).resize((ART_W, ART_H), Image.BILINEAR)
    for _ in range(SHORE // 6):
        small = small.filter(ImageFilter.MaxFilter(13))
    small = small.filter(ImageFilter.GaussianBlur(SHORE_SOFT))
    xs = np.minimum(np.arange(ART_W), ART_W - 1 - np.arange(ART_W)) / ART_W
    ys = np.minimum(np.arange(ART_H), ART_H - 1 - np.arange(ART_H)) / ART_H
    edge = np.clip((np.minimum(xs[None, :], ys[:, None]) - EDGE[0]) / (EDGE[1] - EDGE[0]), 0, 1)
    edge = edge * edge * (3 - 2 * edge)
    return Image.fromarray((np.asarray(small) * edge).astype(np.uint8))


def soften(own):
    """A zone off any continent: its own land grown a little and blurred."""
    return own.filter(ImageFilter.MaxFilter(GROW)).filter(ImageFilter.GaussianBlur(BLUR))


def write_tga(alpha, path, size=MASK):
    alpha = alpha.resize((size, size), Image.LANCZOS)
    img = Image.merge("RGBA", (Image.new("L", alpha.size, 255),) * 3 + (alpha,))
    img.save(path, compression=None)  # 32-bit uncompressed TGA: what the client reads


def write_addon(out, arts, build):
    with open(os.path.join(out, "Tomte_MapArt.toc"), "w", encoding="utf-8", newline="\r\n") as f:
        f.write("## Interface: 16001\n## Title: Tomte Map Art\n"
                "## Notes: Zone masks for the Tomte map (World of Warcraft: Forever). Made from Blizzard's map art.\n"
                "## Version: %d\n## Author: tomte55\n" % VERSION)
    with open(os.path.join(out, "README.txt"), "w", encoding="utf-8", newline="\r\n") as f:
        f.write("Tomte Map Art %d: %d zone masks for the Tomte map, built by Tomte's tools/mapart.py from build %s.\n"
                "Made from Blizzard Entertainment's map art; not covered by Tomte's license.\n" % (VERSION, len(arts), build))


def write_index(arts, continents, labels, build):
    lines = [
        "local addonName, ns = ...",
        "",
        "-- Generated by tools/mapart.py from build %s: don't edit. The zone masks the Tomte_MapArt addon has" % build,
        "-- (Interface\\AddOns\\Tomte_MapArt\\Masks\\Zone<uiMapArtID>.tga), used only while that addon is loaded and its",
        "-- ## Version is this version. Drawn by Modules/Map/Art.lua.",
        "",
        "ns.Content_Register(ns.CONTENT_FOREVER, \"mapArtIndex\", {",
        "\tversion = %d," % VERSION,
        "\tmasks = { %s }," % ", ".join("[%d] = true" % a for a in sorted(arts)),
        "\tcontinents = { %s }, -- Masks\\Continent<uiMapArtID>.tga" % ", ".join(
            "[%d] = true" % a for a in sorted(continents)),
        "\t-- [uiMapArtID] = the place names' boxes { left, top, right, bottom } (art pixels), Masks\\Labels<uiMapArtID>.tga",
        "\tlabels = {",
    ]
    for art in sorted(labels):
        lines.append("\t\t[%d] = { %s }," % (art, ", ".join("{ %d, %d, %d, %d }" % b for b in labels[art])))
    lines += [
        "\t},",
        "})",
    ]
    with open(INDEX, "w", encoding="utf-8", newline="\r\n") as f:
        f.write("\n".join(lines) + "\n")


def main():
    if len(sys.argv) < 4:
        raise SystemExit(__doc__)
    build, folder, out = sys.argv[1], sys.argv[2], sys.argv[3]
    os.makedirs(folder, exist_ok=True)
    os.makedirs(os.path.join(out, "Masks"), exist_ok=True)
    data = wago.load(folder, ["WorldMapOverlay", "WorldMapOverlayTile", "UiMapXMapArt", "UiMap", "UiMapAssignment",
                              "UiMapArtTile"], build)
    maps = {int(r["ID"]): r for r in data["UiMap"]}
    art_of = {}
    for r in data["UiMapXMapArt"]:
        if r["PhaseID"] == "0":
            art_of.setdefault(int(r["UiMapID"]), int(r["UiMapArtID"]))
    art_tiles = defaultdict(list)
    for t in data["UiMapArtTile"]:
        if t["LayerIndex"] == "0":
            art_tiles[int(t["UiMapArtID"])].append((int(t["RowIndex"]), int(t["ColIndex"]), int(t["FileDataID"])))
    tiles = defaultdict(list)
    for t in data["WorldMapOverlayTile"]:
        if int(t["LayerIndex"]) == 0:
            tiles[int(t["WorldMapOverlayID"])].append((int(t["RowIndex"]), int(t["ColIndex"]), int(t["FileDataID"])))
    pieces = defaultdict(list)
    for o in data["WorldMapOverlay"]:
        oid = int(o["ID"])
        if tiles[oid]:
            pieces[int(o["UiMapArtID"])].append((int(o["OffsetX"]), int(o["OffsetY"]), int(o["TextureWidth"]),
                                                 int(o["TextureHeight"]), [fid for _, _, fid in sorted(tiles[oid])]))
    zones = [m for m, r in maps.items() if int(r["Type"]) == MAP_ZONE and pieces.get(art_of.get(m))]
    layout = Layout(data["UiMapAssignment"])
    masks, shores, names = {}, {}, {}  # names: [art] = its place names' boxes
    by_continent = defaultdict(list)
    for z in zones:
        parent = int(maps[z]["ParentUiMapID"])
        if parent in maps and int(maps[parent]["Type"]) == MAP_CONTINENT and art_of.get(parent) in art_tiles \
                and layout.rect(z, parent):
            by_continent[parent].append(z)
    for c, members in sorted(by_continent.items()):
        print("continent %d (%s): %d zones" % (c, maps[c]["Name_lang"], len(members)))
        gw, gh = ART_W * G, ART_H * G
        land = continent_land(art_of[c], art_tiles, folder, build, (gw, gh))
        shores[art_of[c]] = continent_mask(land)
        members.sort(key=lambda z: -layout.rect(z, c)[2])  # largest first: drawn first in game too (Art.lua)
        placed = []
        for z in members:
            l, t, w, h = layout.rect(z, c)
            box = (round(l * gw), round(t * gh), round(w * gw), round(h * gh))
            print("  %s" % maps[z]["Name_lang"])
            placed.append((box, place(own_land(pieces[art_of[z]], folder, build), box, (gh, gw))))
        labels = territories(placed, land)
        found = []  # (zone index, box in art pixels, box on the continent grid, owner of its middle)
        for i, z in enumerate(members):
            masks[art_of[z]] = territory_mask(labels, i, placed[i][0])
            gx0, gy0, gw_, gh_ = placed[i][0]
            for b in label_boxes(pieces_picture(pieces[art_of[z]], folder, build)):
                g = (gx0 + b[0] / ART_W * gw_, gy0 + b[1] / ART_H * gh_, gx0 + b[2] / ART_W * gw_,
                     gy0 + b[3] / ART_H * gh_)
                mx, my = int((g[0] + g[2]) / 2), int((g[1] + g[3]) / 2)
                owner = labels[my, mx] if 0 <= my < labels.shape[0] and 0 <= mx < labels.shape[1] else -1
                found.append((i, b, g, owner))
        # Two zones naming the same spot: the zone whose territory holds it keeps its name.
        for i, b, g, owner in found:
            clash = any(j != i and g[0] < h[2] and g[2] > h[0] and g[1] < h[3] and g[3] > h[1] and owner != i
                        and (o == j or owner == j) for j, _, h, o in found)
            if not clash:
                names.setdefault(art_of[members[i]], []).append(b)
    for z in zones:
        if art_of[z] not in masks:
            print("zone %d (%s), off any continent" % (z, maps[z]["Name_lang"]))
            masks[art_of[z]] = soften(own_land(pieces[art_of[z]], folder, build))
    labels = {}
    for art, boxes in names.items():
        if boxes:
            labels[art] = boxes
            write_tga(label_mask(boxes), os.path.join(out, "Masks", "Labels%d.tga" % art), LABEL_MASK)
    print("place names in %d zones, %d in all" % (len(labels), sum(len(b) for b in labels.values())))
    for art, mask in masks.items():
        write_tga(mask, os.path.join(out, "Masks", "Zone%d.tga" % art))
    for art, mask in shores.items():
        write_tga(mask, os.path.join(out, "Masks", "Continent%d.tga" % art))
    write_addon(out, list(masks), build)
    write_index(list(masks), list(shores), labels, build)
    print("wrote %d masks to %s and %s" % (len(masks), out, INDEX))


if __name__ == "__main__":
    main()
