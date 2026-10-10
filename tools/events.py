"""Builds Modules/Holidays/Generated.lua (the holiday toys and the Timewalking calendar textures) from the client's
Toy and Holidays tables, read from wago.tools CSV exports, and prints a coverage report for the mounts and pets.
Dev-only, not in the release zip.

    python -I tools/events.py <build> [csv-dir]

<build> is the client build, e.g. 12.1.0.69933. With no csv-dir the tables are downloaded into a new, empty temp
folder. Tables: Toy, Mount, BattlePetSpecies, Holidays, HolidayNames.

Toys have no source API in game, so the toy -> holiday table is generated here with Tomte's own matching rules
(the English holiday names below, plus the language-free currency links and cost icons from Table.lua). Mounts and
pets are matched in game (Catalog.lua) with localized names; the report lists the ones those rules would miss, to be
placed by hand into `extra` in Table.lua. Toys the rules miss go into TOY_EXTRA below.
"""
import csv
import os
import re
import sys
import tempfile
import urllib.request

TABLES = ["Toy", "Mount", "BattlePetSpecies", "Holidays", "HolidayNames"]
HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.join(HERE, "..")
TABLE_LUA = os.path.join(ROOT, "Modules", "Holidays", "Table.lua")
OUT = os.path.join(ROOT, "Modules", "Holidays", "Generated.lua")
UA = ("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) "
      "Chrome/124.0 Safari/537.36")
WORLD_EVENT = "6"  # SourceTypeEnum: World Event

# English holiday names, dev time only (the game matches with the localized names it gives).
NAMES = {"darkmoon": ["Darkmoon Faire", "Darkmoon Island"], "lunar": ["Lunar Festival"],
         "love": ["Love is in the Air"], "noblegarden": ["Noblegarden"], "childrens": ["Children's Week"],
         "midsummer": ["Midsummer Fire Festival", "Midsummer"], "pirates": ["Pirates' Day"],
         "brewfest": ["Brewfest"], "hallows": ["Hallow's End"], "dead": ["Day of the Dead"],
         "pilgrims": ["Pilgrim's Bounty"], "winterveil": ["Feast of Winter Veil", "Winter Veil"],
         "timewalking": ["Timewalking"]}

# Toys that belong to a holiday but whose source text doesn't say so: { key: [itemID] } (name in a comment).
TOY_EXTRA = {
    "winterveil": [188680],  # sold by the Smokywood Pastures Vendor, drops from Stolen Present
}

# Holiday bosses and holiday containers (English, dev only): unmatched sources naming one are reported.
HINTS = ["headless horseman", "ahune", "direbrew", "hummel", "crown chemical", "loot-filled pumpkin",
         "keg-shaped", "smokywood", "stolen present", "gaily wrapped", "lovely merchant", "candy bucket"]

# Toys whose source text matches but that aren't from the holiday: [itemID] (name in a comment).
TOY_SKIP = []


def load(folder, build):
    data = {}
    for name in TABLES:
        path = os.path.join(folder, name + ".csv")
        if not os.path.exists(path):
            url = "https://wago.tools/db2/%s/csv?build=%s" % (name, build)
            print("downloading", url)
            req = urllib.request.Request(url, headers={"User-Agent": UA})
            with urllib.request.urlopen(req) as resp, open(path, "wb") as f:
                f.write(resp.read())
        with open(path, encoding="utf-8") as f:
            data[name] = list(csv.DictReader(f))
    return data


def table_signals():
    """Currencies and icons per holiday key, read from Table.lua."""
    with open(TABLE_LUA, encoding="utf-8") as f:
        text = f.read()
    signals = {}
    text = text.split("ns.EVENTS_DARKMOON_QUESTS")[0]
    starts = list(re.finditer(r'key = "(\w+)"', text))
    for n, m in enumerate(starts):
        key = m.group(1)
        body = text[m.end():starts[n + 1].start() if n + 1 < len(starts) else len(text)]
        cur = re.search(r"currencies = \{([^}]*)\}", body)
        icons = re.search(r"icons = \{([^}]*)\}", body)
        signals[key] = {
            "currencies": {int(x) for x in re.findall(r"\d+", cur.group(1))} if cur else set(),
            "icons": {s.replace("\\\\", "\\").lower() for s in re.findall(r'"([^"]+)"', icons.group(1))}
            if icons else set(),
        }
    for key in NAMES:
        signals.setdefault(key, {"currencies": set(), "icons": set()})
    return signals


def clean(raw):
    text = raw.replace("|n", "\n")
    text = re.sub(r"\|c[0-9a-fA-F]{8}", "", text).replace("|r", "")
    text = re.sub(r"\|T.*?\|t", "", text)
    text = re.sub(r"\|H.*?\|h(.*?)\|h", r"\1", text)
    return text.strip()


def mentions(lower, name):
    name = name.lower()
    start = 0
    while True:
        i = lower.find(name, start)
        if i < 0:
            return False
        before = lower[i - 1] if i > 0 else ""
        after = lower[i + len(name)] if i + len(name) < len(lower) else ""
        if not (before.isalnum() or after.isalnum()):
            return True
        start = i + 1


def match(raw, signals):
    """Mirrors ns.Events_MatchSource: the first holiday key the source text points at, or None."""
    if not raw:
        return None
    for key, s in signals.items():
        for cid in re.findall(r"\|Hcurrency:(\d+)", raw):
            if int(cid) in s["currencies"]:
                return key
        for path in re.findall(r"\|T([^:|]+)", raw):
            if re.sub(r"\.blp$", "", path.lower()) in s["icons"]:
                return key
    lower = clean(raw).lower()
    for key, names in NAMES.items():
        for n in names:
            if mentions(lower, n):
                return key
    return None


def word_hit(text):
    lower = (text or "").lower()
    for key, names in NAMES.items():
        for n in names:
            if mentions(lower, n):
                return key
    return None


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(1)
    build = sys.argv[1]
    folder = sys.argv[2] if len(sys.argv) > 2 else tempfile.mkdtemp(prefix="tomte_events_")
    data = load(folder, build)
    signals = table_signals()

    toys = {}
    unmatched_toys = []
    for row in data["Toy"]:
        item = int(row["ItemID"])
        if item in TOY_SKIP:
            continue
        key = match(row["SourceText_lang"], signals)
        if key:
            toys.setdefault(key, set()).add(item)
        elif row["SourceTypeEnum"] == WORLD_EVENT:
            unmatched_toys.append((item, clean(row["SourceText_lang"])))
    for key, items in TOY_EXTRA.items():
        toys.setdefault(key, set()).update(items)

    names = {r["ID"]: r["Name_lang"] for r in data["HolidayNames"]}
    tw = set()
    for row in data["Holidays"]:
        if names.get(row["HolidayNameID"]) == "Timewalking Dungeon Event":
            for i in range(3):
                fid = int(row["TextureFileDataID_%d" % i] or 0)
                if fid:
                    tw.add(fid)

    lines = ["local addonName, ns = ...", "",
             "-- Generated by tools/events.py from the client's Toy and Holidays tables (wago.tools, build %s). "
             "Do not edit." % build,
             "ns.EVENTS_TOYS = {"]
    for key in sorted(toys):
        ids = sorted(toys[key])
        chunks = [", ".join(str(i) for i in ids[n:n + 12]) for n in range(0, len(ids), 12)]
        lines.append("\t%s = {" % key)
        for c in chunks:
            lines.append("\t\t%s," % c)
        lines.append("\t},")
    lines.append("}")
    tws = sorted(tw)
    lines.append("ns.EVENTS_TW_TEXTURES = {")
    for n in range(0, len(tws), 10):
        lines.append("\t%s," % ", ".join(str(i) for i in tws[n:n + 10]))
    lines.append("}")
    with open(OUT, "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(lines) + "\n")
    total = sum(len(v) for v in toys.values())
    print("wrote %s: %d toys in %d holidays, %d Timewalking textures" % (OUT, total, len(toys), len(tws)))

    print("\n== Toys with source type World Event (SourceTypeEnum 6) that didn't match")
    for item, text in unmatched_toys:
        print("  %d  %s" % (item, text.replace("\n", " | ")))

    word_only, event_miss, hinted = [], [], []
    placed = set()
    for items in toys.values():
        placed.update(items)
    for row in data["Toy"]:
        text = clean(row["SourceText_lang"])
        if int(row["ItemID"]) not in placed and any(h in text.lower() for h in HINTS):
            hinted.append(("toy", row["ItemID"], "", text))
    for kind, table, id_key in (("mount", "Mount", "ID"), ("pet", "BattlePetSpecies", "ID")):
        for row in data[table]:
            source = row.get("SourceText_lang", "")
            if match(source, signals):
                continue
            label = row.get("Name_lang") or ""
            lower = clean(source).lower()
            if any(h in lower for h in HINTS):
                hinted.append((kind, row[id_key], label, clean(source)))
                continue
            hit = word_hit(label) or word_hit(row.get("Description_lang"))
            if hit:
                word_only.append((kind, row[id_key], hit, label, clean(source)))
            elif row.get("SourceTypeEnum") == WORLD_EVENT:
                event_miss.append((kind, row[id_key], label, clean(source)))
    print("\n== Sources that name a holiday boss or container but didn't match (kind, id, name, source)")
    for r in hinted:
        print("  %s %s %s :: %s" % (r[0], r[1], r[2], r[3].replace("\n", " | ")))
    print("\n== Mounts/pets that mention a holiday word only in their name or description "
          "(kind, id, holiday, name, source)")
    for r in word_only:
        print("  %s %s [%s] %s :: %s" % (r[0], r[1], r[2], r[3], r[4].replace("\n", " | ")))
    print("\n== Mounts/pets with SourceTypeEnum 6 that didn't match (kind, id, name, source)")
    for r in event_miss:
        print("  %s %s %s :: %s" % (r[0], r[1], r[2], r[3].replace("\n", " | ")))


if __name__ == "__main__":
    main()
