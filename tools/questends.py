"""Builds Data/Forever/QuestEnds.lua: where each quest is handed in, on World of Warcraft: Forever.

From QuestieDB's Forever data (github.com/Questie/QuestieDB, data/Forever/ at the commit below): a quest's finishers
(foreverQuestDB.lua) and where they stand (foreverNpcDB.lua, foreverObjectDB.lua). Only facts are taken: quest, NPC and
object IDs and spawn coordinates. QuestieDB's LICENSE.md lets others copy under GPLv3 terms (Tomte's license); credited
in README's Credits. Read by the quest route (Modules/Leveling/Route.lua).

Fetch the three files into a folder of their own, then, from the Tomte folder:
    python -I tools/questends.py <folder> <QuestieDB commit the files came from>
They're read as text by the small parser below and never run.
"""
import os
import re
import sys

OUT = os.path.join("Data", "Forever", "QuestEnds.lua")

# QuestieDB's keys (1-based): questKeys.finishedBy = { {npcIDs}, {objectIDs} }; npcKeys.spawns / zoneID;
# objectKeys.spawns / zoneID. Spawns: { [areaID] = { {x, y}, ... } } in zone percent.
QUEST_FINISHED_BY = 3
NPC_SPAWNS, NPC_ZONE = 7, 9
OBJECT_SPAWNS, OBJECT_ZONE = 4, 5


class Parser:
    """A Lua table literal as Python values: numbers, strings, nil (None), booleans and { ... } as a list, or a dict
    once the table has [key] = value entries (list entries then go under 1, 2, ...)."""

    TOKEN = re.compile(r'\s*(?:(\{)|(\})|(,)|(nil)|(true|false)|(-?\d+(?:\.\d+)?(?:e-?\d+)?)|"((?:[^"\\]|\\.)*)"'
                       r"|'((?:[^'\\]|\\.)*)')")
    KEY = re.compile(r"\s*\[(-?\d+)\]\s*=")

    def __init__(self, text):
        self.text, self.pos = text, 0

    def next(self):
        m = self.TOKEN.match(self.text, self.pos)
        if not m:
            raise ValueError("can't read at %d: %r" % (self.pos, self.text[self.pos:self.pos + 40]))
        self.pos = m.end()
        return m

    def value(self):
        m = self.next()
        if m.group(1):
            return self.table()
        if m.group(4):
            return None
        if m.group(5):
            return m.group(5) == "true"
        if m.group(6):
            n = m.group(6)
            return float(n) if ("." in n or "e" in n) else int(n)
        s = m.group(7) if m.group(7) is not None else m.group(8)
        return re.sub(r"\\(.)", r"\1", s)

    def table(self):
        items, keyed = [], {}
        while True:
            key = self.KEY.match(self.text, self.pos)
            if key:
                self.pos = key.end()
                keyed[int(key.group(1))] = self.value()
                continue
            save = self.pos
            m = self.next()
            if m.group(2):
                break
            if m.group(3):
                continue
            self.pos = save
            items.append(self.value())
        if not keyed:
            return items
        for i, v in enumerate(items):
            keyed.setdefault(i + 1, v)
        return keyed


def field(row, index):
    if isinstance(row, dict):
        return row.get(index)
    return row[index - 1] if len(row) >= index else None


def read_rows(path, marker):
    text = open(path, encoding="utf-8").read()
    body = text[text.index(marker):]
    rows = {}
    for m in re.finditer(r"^\[(\d+)\] = (\{.*\}),\s*$", body, re.M):
        rows[int(m.group(1))] = Parser(m.group(2)).value()
    return rows


def spot(row, spawns_key, zone_key):
    """(areaID, x, y) where it stands: its main zone's first spawn, else the first zone's first spawn."""
    spawns = field(row, spawns_key) if row else None
    if not isinstance(spawns, dict) or not spawns:
        return None
    zone = field(row, zone_key)
    for area in ([zone] if zone in spawns else []) + sorted(spawns):
        coords = spawns.get(area)
        if isinstance(coords, list) and coords and isinstance(coords[0], list) and len(coords[0]) >= 2:
            x, y = coords[0][0], coords[0][1]
            if isinstance(x, (int, float)) and isinstance(y, (int, float)) and x >= 0 and y >= 0:
                return area, x, y
    return None


def ids(value):
    return [v for v in (value or []) if isinstance(v, int)] if isinstance(value, list) else []


def main():
    if len(sys.argv) < 3:
        sys.exit(__doc__)
    folder, commit = sys.argv[1], sys.argv[2]
    quests = read_rows(os.path.join(folder, "foreverQuestDB.lua"), "questData = [[return {")
    npcs = read_rows(os.path.join(folder, "foreverNpcDB.lua"), "npcData = [[return {")
    objects = read_rows(os.path.join(folder, "foreverObjectDB.lua"), "objectData = [[return {")

    ends = {}
    for qid, row in quests.items():
        finished = field(row, QUEST_FINISHED_BY)
        if not isinstance(finished, list):
            continue
        found = None
        for npc in ids(finished[0] if len(finished) > 0 else None):
            found = spot(npcs.get(npc), NPC_SPAWNS, NPC_ZONE)
            if found:
                break
        if not found:
            for obj in ids(finished[1] if len(finished) > 1 else None):
                found = spot(objects.get(obj), OBJECT_SPAWNS, OBJECT_ZONE)
                if found:
                    break
        if found:
            ends[qid] = found

    lines = [
        "local addonName, ns = ...",
        "",
        "-- Generated by tools/questends.py: don't edit. From QuestieDB's Forever data (github.com/Questie/QuestieDB,",
        "-- data/Forever/ at commit %s), copied under GPLv3 terms as its LICENSE.md allows." % commit,
        "-- questEnds: [questID] = \"areaID:x:y\", where the quest is handed in (its finisher's main spot, zone percent).",
        "-- Read by the quest route (Modules/Leveling/Route.lua).",
        "",
        "ns.Content_Register(ns.CONTENT_FOREVER, \"questEnds\", {",
    ]
    for qid in sorted(ends):
        area, x, y = ends[qid]
        lines.append("\t[%d] = \"%d:%g:%g\"," % (qid, area, x, y))
    lines.append("})")
    with open(OUT, "w", encoding="utf-8", newline="\r\n") as f:
        f.write("\n".join(lines) + "\n")
    print("%s: %d of %d quests" % (OUT, len(ends), len(quests)))


if __name__ == "__main__":
    main()
