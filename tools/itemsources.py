"""Builds Data/Forever/ItemSources.lua: where to get items, from pfQuest's vanilla database.

github.com/shagu/pfQuest, MIT License, Copyright (c) 2017-2021 Eric Mauser (Shagu). Classic's data: Forever may differ, and the
page says so. Fetch these from the commit below into one folder, named with the slash as an underscore (db/enUS/items.lua is
enUS_items.lua): db/items.lua, db/units.lua, db/objects.lua, db/enUS/items.lua, db/enUS/units.lua, db/enUS/objects.lua,
db/enUS/zones.lua. Then, from the Tomte folder: python -I tools/itemsources.py <folder>

The files are read as text by the small parser below and never run: they're downloaded, and only their numbers and strings are used.
"""
import math
import os
import re
import sys

PFQUEST_COMMIT = "104f35678ca39ab1fb78b655f815cc7016f5e0c8"
OUT = os.path.join("Data", "Forever", "ItemSources.lua")

BAND = 10  # levels: the drops kept are the best in each band of mob levels, so every level finds some
PER_ZONE = 2  # in each band, the best this many in each zone, so each side of the world finds some
PER_BAND = 12
SPAWNS_COUNTED = 10  # as Sources_Score in Modules/Sources/Data.lua
MAX_VENDORS = 200  # every vendor: the page keeps those who'd sell to you, and a cap by ID left mostly one side's (Salt: 3 of 78 for Horde)
MAX_OBJECTS = 12
MIN_CHANCE = 0.5  # percent: rarer world drops aren't a way to get something. An item with nothing better keeps its best.

# Skinning isn't in pfQuest's database: the levels of the creatures each leather and hide is skinned from, in Classic. From
# warcraft.wiki.gg's item pages (2026-11-07) where they give one; the others (marked) follow the hide skinned from the same
# creatures. pfQuest has no creature types, so the zones listed are where normal hostile creatures of those levels live: the
# beasts there are the ones to skin.
SKINNED = {
    2934: (1, 15),   # Ruined Leather Scraps: "low-level mobs" (estimate)
    2318: (1, 25),   # Light Leather (estimate: with Light Hide's creatures and below)
    783: (9, 25),    # Light Hide
    2319: (20, 35),  # Medium Leather (estimate: Medium Hide's)
    4232: (20, 35),  # Medium Hide
    4234: (25, 47),  # Heavy Leather
    4235: (30, 45),  # Heavy Hide
    4304: (40, 50),  # Thick Leather
    8169: (40, 50),  # Thick Hide (estimate: Thick Leather's)
    8170: (50, 60),  # Rugged Leather (with Rugged Hide's creatures)
    8171: (50, 60),  # Rugged Hide
}
MIN_SKIN_SPAWNS = 15  # creatures of the right level in a zone before it's worth going there to skin
MAX_SKIN_ZONES = 16
NOT_FOR_SKINNING = {2597, 3277, 3358}  # Alterac Valley, Warsong Gulch, Arathi Basin: battlegrounds, not a place to go skinning


def level_range(lvl):
    nums = [int(n) for n in re.findall(r"\d+", str(lvl if lvl is not None else "1"))]
    return (nums[0], nums[-1]) if nums else (1, 1)


def skin_zones(low, high, units):
    """Zones with normal hostile creatures in low..high: [(zone, lowest, highest, x, y, spawns)], the most creatures first. x, y is
    the spawn nearest the middle of them there, for the map pin."""
    by_zone = {}
    for unit in units.values():
        if not isinstance(unit, dict) or unit.get("fac") or unit.get("rnk"):
            continue
        a, b = level_range(unit.get("lvl"))
        if b < low or a > high:
            continue
        level = min(max((a + b) / 2, low), high)
        for c in (unit.get("coords") or {}).values():
            zone = c.get(3)
            if zone and zone > 0 and zone not in NOT_FOR_SKINNING:
                z = by_zone.setdefault(zone, {"spots": [], "levels": []})
                z["spots"].append(c)
                z["levels"].append(level)
    rows = []
    for zone, z in by_zone.items():
        spots, levels = z["spots"], sorted(z["levels"])
        if len(spots) < MIN_SKIN_SPAWNS:
            continue
        sx = sum(c[1] for c in spots) / len(spots)
        sy = sum(c[2] for c in spots) / len(spots)
        best = min(spots, key=lambda c: (c[1] - sx) ** 2 + (c[2] - sy) ** 2)
        # The levels most of them are (a tenth at each end left out): a zone's odd low or high creature would stretch it.
        a = int(levels[len(levels) // 10])
        b = int(math.ceil(levels[(len(levels) * 9) // 10]))
        rows.append((zone, a, max(a, b), best[1], best[2], len(spots)))
    return sorted(rows, key=lambda r: (-r[5], r[0]))[:MAX_SKIN_ZONES]

TOKEN = re.compile(r'\s*(?:--[^\n]*\n\s*)*(?:(\{)|(\})|(=)|(,)|(;)|\[|\]|("(?:[^"\\]|\\.)*")|(-?\d+(?:\.\d+)?)|(true|false|nil)|([A-Za-z_]\w*))')


def parse(text, start):
    """The table literal starting at text[start] (a "{"), as a dict: list items get keys 1, 2, 3..."""
    table, pos, index, key = {}, start + 1, 1, None
    while True:
        m = TOKEN.match(text, pos)
        if not m:
            raise ValueError("can't read at %d: %r" % (pos, text[pos:pos + 40]))
        tok = m.group(0).strip()
        pos = m.end()
        if tok == "}":
            return table, pos
        if tok in (",", ";"):
            continue
        if tok == "[":
            m2 = TOKEN.match(text, pos)
            key = value_of(m2.group(0).strip())
            pos = m2.end()
            pos = TOKEN.match(text, pos).end()  # the ]
            pos = TOKEN.match(text, pos).end()  # the =
            continue
        if tok == "{":
            value, pos = parse(text, m.end() - 1)
        else:
            name = tok
            after = TOKEN.match(text, pos)
            if m.group(9) and after and after.group(0).strip() == "=":  # name = value
                key = name
                pos = after.end()
                continue
            value = value_of(tok)
        if key is None:
            table[index] = value
            index += 1
        else:
            table[key] = value
            key = None


def value_of(tok):
    if tok.startswith('"'):
        return re.sub(r"\\(.)", r"\1", tok[1:-1])
    if re.fullmatch(r"-?\d+", tok):
        return int(tok)
    if re.fullmatch(r"-?\d+\.\d+", tok):
        return float(tok)
    return {"true": True, "false": False}.get(tok)


def load(folder, name, field):
    with open(os.path.join(folder, name + ".lua"), encoding="utf-8", errors="replace") as f:
        text = f.read()
    m = re.search(r'pfDB\["[^"]+"\]\["%s"\]\s*=\s*\{' % field, text)
    if not m:
        raise ValueError(name + ": no table")
    return parse(text, m.end() - 1)[0]


def main_spot(coords):
    """Where something mostly stands: the zone with the most spawns, and the spawn closest to the middle of them there."""
    by_zone = {}
    for c in (coords or {}).values():
        zone = c.get(3)
        if zone and zone > 0:
            by_zone.setdefault(zone, []).append(c)
    if not by_zone:
        return None
    zone = sorted(by_zone, key=lambda z: (-len(by_zone[z]), z))[0]
    spots = by_zone[zone]
    sx = sum(c[1] for c in spots) / len(spots)
    sy = sum(c[2] for c in spots) / len(spots)
    best = min(spots, key=lambda c: (c[1] - sx) ** 2 + (c[2] - sy) ** 2)
    return zone, best[1], best[2], len(spots)


def low_level(lvl):
    m = re.match(r"\d+", str(lvl if lvl is not None else "1"))
    return int(m.group(0)) if m else 1


def clean(text):
    return str(text).replace("|", "/")


def g(number):
    return ("%g" % number)


def lua_string(text):
    return '"' + text.replace("\\", "\\\\").replace('"', '\\"') + '"'


def pick_drops(found, units, names):
    bands, everything = {}, []
    for uid in sorted(found or {}):
        unit = units.get(uid)
        spot = unit and uid in names and main_spot(unit.get("coords"))
        # With a faction it's a guard or townsfolk, not something to farm. Named Classic bosses have none, so they stay.
        if spot and not unit.get("fac"):
            row = (found[uid], uid, spot[0], found[uid] * min(spot[3], SPAWNS_COUNTED))
            everything.append(row)
            bands.setdefault(low_level(unit.get("lvl")) // BAND, []).append(row)
    likelier = lambda r: (-r[3], -r[0], r[1])
    kept = []
    for band in sorted(bands):
        per_zone, chosen = {}, []
        for row in sorted(bands[band], key=likelier):
            if row[0] >= MIN_CHANCE and per_zone.get(row[2], 0) < PER_ZONE and len(chosen) < PER_BAND:
                per_zone[row[2]] = per_zone.get(row[2], 0) + 1
                chosen.append(row)
        kept += chosen
    if not kept and everything:
        kept = sorted(everything, key=likelier)[:1]
    return sorted(kept, key=likelier)


def pick_places(found, data, names, limit):
    rows = []
    for tid in sorted(found or {}):
        thing = data.get(tid)
        if thing and tid in names and main_spot(thing.get("coords")):
            rows.append((found[tid] or 0, tid))
    return sorted(rows, key=lambda r: (-r[0], r[1]))[:limit]


def main():
    folder = sys.argv[1]
    items = load(folder, "items", "data")
    units = load(folder, "units", "data")
    objects = load(folder, "objects", "data")
    item_names = load(folder, "enUS_items", "enUS")
    unit_names = load(folder, "enUS_units", "enUS")
    object_names = load(folder, "enUS_objects", "enUS")
    zone_names = load(folder, "enUS_zones", "enUS")

    used_units, used_objects, used_zones, lines, skin_lines = set(), set(), set(), [], []
    for iid in sorted(items):
        name = item_names.get(iid)
        item = items[iid]
        if not name or not isinstance(item, dict):
            continue
        drops = pick_drops(item.get("U"), units, unit_names)
        vendors = pick_places(item.get("V"), units, unit_names, MAX_VENDORS)
        found = pick_places(item.get("O"), objects, object_names, MAX_OBJECTS)
        skins = skin_zones(SKINNED[iid][0], SKINNED[iid][1], units) if iid in SKINNED else []
        if skins:
            used_zones.update(r[0] for r in skins)
            spots = ",".join("%d:%d-%d:%s:%s:%d" % (zone, a, b, g(x), g(y), n) for zone, a, b, x, y, n in skins)
            skin_lines.append("\t[%d]=%s," % (iid, lua_string("%d-%d|%s" % (SKINNED[iid][0], SKINNED[iid][1], spots))))
        if not (drops or vendors or found or skins):
            continue
        parts = []
        for chance, uid, _, _ in drops:
            used_units.add(uid)
            parts.append("u%d:%s" % (uid, g(chance)))
        for _, uid in vendors:
            used_units.add(uid)
            parts.append("v%d" % uid)
        for chance, oid in found:
            used_objects.add(oid)
            parts.append("o%d:%s" % (oid, g(chance)))
        lines.append("\t[%d]=%s," % (iid, lua_string(clean(name) + "|" + ",".join(parts))))

    unit_lines = []
    for uid in sorted(used_units):
        unit = units[uid]
        zone, x, y, spawns = main_spot(unit.get("coords"))
        used_zones.add(zone)
        fields = [clean(unit_names[uid]), str(unit.get("lvl", "?")), str(unit.get("fac", "")), str(unit.get("rnk", "")), str(zone),
                  g(x), g(y), str(spawns)]
        unit_lines.append("\t[%d]=%s," % (uid, lua_string("|".join(fields))))
    object_lines = []
    for oid in sorted(used_objects):
        zone, x, y, spawns = main_spot(objects[oid].get("coords"))
        used_zones.add(zone)
        fields = [clean(object_names[oid]), str(zone), g(x), g(y), str(spawns)]
        object_lines.append("\t[%d]=%s," % (oid, lua_string("|".join(fields))))
    zone_lines = ["\t[%d]=%s," % (z, lua_string(clean(zone_names.get(z, "")))) for z in sorted(used_zones)]

    head = [
        "local addonName, ns = ...",
        "",
        "-- Generated by tools/itemsources.py: don't edit. From pfQuest's vanilla database (github.com/shagu/pfQuest), commit",
        "-- %s. MIT License, Copyright (c) 2017-2021 Eric Mauser (Shagu). Classic's data: Forever may differ." % PFQUEST_COMMIT,
        '-- items: [itemID] = "name|sources", each source u<unit>:<chance> (drop), v<unit> (vendor) or o<object>:<chance> (gathered or',
        "-- found). units: name|levels|faction|rank|zone|x|y|spawns. objects: name|zone|x|y|spawns. zones: [area ID] = name.",
        "-- skinned: [itemID] = \"low-high|zone:low-high:x:y:spawns,...\": the creature levels it's skinned from (Classic, from",
        "-- warcraft.wiki.gg; not in pfQuest), then zones with normal hostile creatures of those levels, their levels there and a spot.",
        "",
    ]
    out = head + ["ns.SOURCES_ITEMS = {"] + lines + ["}", "ns.SOURCES_UNITS = {"] + unit_lines + ["}", "ns.SOURCES_OBJECTS = {"] + \
        object_lines + ["}", "ns.SOURCES_ZONES = {"] + zone_lines + ["}", "ns.SOURCES_SKINNED = {"] + skin_lines + ["}", ""]
    with open(OUT, "w", encoding="utf-8", newline="\r\n") as f:
        f.write("\n".join(out))
    print("%d items, %d units, %d objects, %d zones, %d KB" % (len(lines), len(unit_lines), len(object_lines), len(zone_lines),
                                                              os.path.getsize(OUT) // 1024))


if __name__ == "__main__":
    main()
