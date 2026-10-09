"""Builds Modules/Travel/Network.lua from Blizzard's waypoint tables (the network the game uses to route quests
through portals, zeppelins and tunnels), read from wago.tools CSV exports. Dev-only, not in the release zip.

    python tools/waynet.py <build> [csv-dir]

<build> is the client build, e.g. 12.1.0.69933. With no csv-dir the tables are downloaded into a temp folder.
Tables: WaypointNode, WaypointEdge, WaypointSafeLocs, WaypointMapVolume, PlayerCondition, ModifierTree.

Unlock conditions (PlayerCondition and its ModifierTree) are compiled into small expression trees that
Route.lua evaluates. What an addon can't check (areas, auras, world states, content tuning, reputation and the
rest) becomes "?", unknown, which never blocks a route on its own.
"""
import csv
import os
import sys
import tempfile
import urllib.request

TABLES = ["WaypointNode", "WaypointEdge", "WaypointSafeLocs", "WaypointMapVolume", "PlayerCondition", "ModifierTree"]
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "Modules", "Travel", "Network.lua")

UNKNOWN = "?"


def load(folder, build):
    data = {}
    for name in TABLES:
        path = os.path.join(folder, name + ".csv")
        if not os.path.exists(path):
            url = "https://wago.tools/db2/%s/csv?build=%s" % (name, build)
            print("downloading", url)
            urllib.request.urlretrieve(url, path)
        with open(path, encoding="utf-8") as f:
            data[name] = list(csv.DictReader(f))
    return data


def num(row, key):
    value = row.get(key)
    return int(value) if value not in (None, "") else 0


# Expressions: True, False, "?" (unknown) or a list ["and", ...], ["or", ...], ["atleast", n, ...], ["not", e]
# and leaves ["faction", "Horde"], ["class", ids], ["quest", id], ["onquest", id], ["ready", id],
# ["questor", id], ["spell", id], ["ach", id], ["level", min, max], ["pc", id].

def AND(parts):
    out = []
    for p in parts:
        if p is False:
            return False
        if p is True:
            continue
        out.append(p)
    if not out:
        return True
    return out[0] if len(out) == 1 else ["and"] + out


def OR(parts):
    out = []
    for p in parts:
        if p is True:
            return True
        if p is False:
            continue
        out.append(p)
    if not out:
        return False
    return out[0] if len(out) == 1 else ["or"] + out


def NOT(e):
    if e is True:
        return False
    if e is False:
        return True
    if e == UNKNOWN:
        return UNKNOWN
    return ["not", e]


def logic(value, results):
    """TrinityCore's PlayerConditionLogic: bit 16+i negates result i; 2-bit ops chain the results (1 and, 2 or)."""
    results = list(results)
    for i in range(len(results)):
        if (value >> (16 + i)) & 1:
            results[i] = NOT(results[i])
    expr = results[0]
    for i in range(1, len(results)):
        op = (value >> (2 * (i - 1))) & 3
        if op == 1:
            expr = AND([expr, results[i]])
        elif op == 2:
            expr = OR([expr, results[i]])
    return expr


class Compiler:
    def __init__(self, data):
        self.pc = {r["ID"]: r for r in data["PlayerCondition"]}
        self.mt = {r["ID"]: r for r in data["ModifierTree"]}
        self.kids = {}
        for r in data["ModifierTree"]:
            self.kids.setdefault(r["Parent"], []).append(r["ID"])
        self.conds = {}
        self.factions = {}
        # Race masks of the plain Horde (923) and Alliance (924) conditions.
        for cid, faction in (("923", "Horde"), ("924", "Alliance")):
            r = self.pc[cid]
            self.factions[(r["RaceMasks_0"], r["RaceMasks_1"])] = faction

    def condition(self, cid):
        """Compiles a PlayerCondition into self.conds and returns a reference to it (or a constant)."""
        cid = str(cid)
        if cid in ("", "0"):
            return True
        if cid not in self.conds:
            self.conds[cid] = None  # cycle guard
            self.conds[cid] = self.compile_pc(cid)
        expr = self.conds[cid]
        if expr is True or expr is False or expr == UNKNOWN:
            return expr
        return ["pc", int(cid)]

    def compile_pc(self, cid):
        r = self.pc.get(cid)
        if not r:
            return UNKNOWN
        parts = []
        masks = (r["RaceMasks_0"], r["RaceMasks_1"])
        if masks not in (("0", "0"), ("-1", "-1"), ("", "")):
            faction = self.factions.get(masks)
            parts.append(["faction", faction] if faction else UNKNOWN)
        if num(r, "ClassMask"):
            mask = num(r, "ClassMask") & 0xFFFFFFFF
            parts.append(["class", [i + 1 for i in range(32) if mask >> i & 1]])
        if num(r, "MinLevel") or num(r, "MaxLevel"):
            parts.append(["level", num(r, "MinLevel"), num(r, "MaxLevel")])

        def slots(prefix, make, count=4):
            return [make(num(r, "%s_%d" % (prefix, i))) if num(r, "%s_%d" % (prefix, i)) else True
                    for i in range(count) if "%s_%d" % (prefix, i) in r]

        checks = [
            ("SpellLogic", "SpellID", lambda v: ["spell", v]),
            ("PrevQuestLogic", "PrevQuestID", lambda v: ["quest", v]),
            ("CurrQuestLogic", "CurrQuestID", lambda v: ["onquest", v]),
            ("CurrentCompletedQuestLogic", "CurrentCompletedQuestID", lambda v: ["ready", v]),
            ("AchievementLogic", "Achievement", lambda v: ["ach", v]),
        ]
        for logic_key, prefix, make in checks:
            if num(r, logic_key):
                parts.append(logic(num(r, logic_key), slots(prefix, make)))
        # Set but not checkable from an addon.
        for key in ("AreaLogic", "AuraSpellLogic", "WorldStateExpressionID", "ContentTuningID", "SkillLogic",
                    "ReputationLogic", "LfgLogic", "CurrencyLogic", "QuestKillID", "PhaseID", "PhaseGroupID",
                    "CovenantID", "MinAvgItemLevel", "MinAvgEquippedItemLevel", "LanguageID", "PartyStatus",
                    "WeatherID", "MinFactionID_0"):
            if num(r, key):
                parts.append(UNKNOWN)
        if num(r, "ModifierTreeID"):
            parts.append(self.tree(r["ModifierTreeID"]))
        return self.and3(parts)

    @staticmethod
    def and3(parts):
        known = [p for p in parts if p != UNKNOWN]
        expr = AND(known)
        if expr is False or len(known) == len(parts):
            return expr
        return UNKNOWN if expr is True else ["and", expr, UNKNOWN]

    def leaf(self, r):
        t, a, b = int(r["Type"]), int(r["Asset"]), int(r["SecondaryAsset"])
        if t == 2:
            return self.condition(a)
        if t == 73:
            return self.tree(str(a))
        if t == 116:
            return ["faction", "Horde" if a == 0 else "Alliance"]
        if t == 26:
            return ["class", [a]]
        if t == 84:
            return ["onquest", a]
        if t == 110:
            return ["quest", a]
        if t == 111:
            return ["ready", a]
        if t == 271:
            return ["questor", a]
        if t == 369:
            return AND([["questor", a], NOT(["questor", b])])
        if t == 86:
            return ["ach", a]
        return UNKNOWN

    def tree(self, tid):
        r = self.mt.get(str(tid))
        if not r:
            return UNKNOWN
        op, amount = int(r["Operator"]), int(r["Amount"]) or 1
        if r["Type"] != "0":
            e = self.leaf(r)
            return NOT(e) if op == 3 else e
        subs = [self.tree(k) for k in self.kids.get(str(tid), [])]
        if op == 8:
            if amount == 1:
                known = [s for s in subs if s != UNKNOWN]
                expr = OR(known)
                if expr is True or len(known) == len(subs):
                    return expr
                return UNKNOWN if expr is False else ["or", expr, UNKNOWN]
            return ["atleast", amount] + subs
        expr = self.and3(subs)
        return NOT(expr) if op == 3 else expr


def lua(value):
    if value is True:
        return "true"
    if value is False:
        return "false"
    if value is None:
        return "nil"
    if isinstance(value, str):
        return '"' + value.replace("\\", "\\\\").replace('"', '\\"') + '"'
    if isinstance(value, float):
        return ("%.1f" % value).rstrip("0").rstrip(".")
    if isinstance(value, int):
        return str(value)
    return "{ " + ", ".join(lua(v) for v in value) + " }"


def build(data, build_id):
    comp = Compiler(data)
    locs = {r["ID"]: r for r in data["WaypointSafeLocs"]}
    nodes = {}
    for r in data["WaypointNode"]:
        loc = locs.get(r["SafeLocID"])
        if not loc or "[DNT" in r["Name_lang"]:
            continue  # spells usable anywhere (mage portals) have no place to point at; test nodes
        nodes[r["ID"]] = {
            "map": int(loc["MapID"]), "x": float(loc["Pos_0"]), "y": float(loc["Pos_1"]),
            "type": num(r, "Type"), "vol": num(r, "WaypointMapVolumeID"),
            "cond": comp.condition(r["PlayerConditionID"]), "name": r["Name_lang"],
        }
    edges = []
    for r in data["WaypointEdge"]:
        if r["Start"] in nodes and r["End"] in nodes:
            cond = comp.condition(r["PlayerConditionID"])
            if cond is not False:
                edges.append((int(r["Start"]), int(r["End"]), num(r, "Field_8_1_5_29281_005"), cond))
    volumes = {}
    for r in data["WaypointMapVolume"]:
        b = [float(r["Bounds_%d" % i]) for i in range(6)]
        volumes[int(r["ID"])] = False if b[0] == b[3] and b[1] == b[4] else [b[0], b[1], b[3], b[4]]

    out = ["local addonName, ns = ...", "",
           "-- Generated by tools/waynet.py from Blizzard's waypoint tables (build %s), the network the game uses to" % build_id,
           "-- route quests. Don't edit by hand: run the script again after a patch. Node: { map (instance), x, y, type",
           "-- (1 leave by, 2 arrive at, 0 path), volume, condition, name }. Edge: { from, to, cost, condition }. Conditions",
           "-- are expression trees for Route.lua (\"?\" = can't be checked by an addon).", "",
           "ns.WAY_NET_BUILD = %s" % lua(build_id), "", "ns.WAY_NET_NODES = {"]
    for nid in sorted(nodes, key=int):
        n = nodes[nid]
        out.append("\t[%s] = { %d, %s, %s, %d, %d, %s, %s }," % (
            nid, n["map"], lua(round(n["x"], 1)), lua(round(n["y"], 1)), n["type"], n["vol"], lua(n["cond"]),
            lua(n["name"])))
    out += ["}", "", "ns.WAY_NET_EDGES = {"]
    for e in edges:
        out.append("\t{ %d, %d, %d, %s }," % (e[0], e[1], e[2], lua(e[3])))
    out += ["}", "", "-- Volume: { x1, y1, x2, y2 } bounds, or false for an interior with no bounds.",
            "ns.WAY_NET_VOLUMES = {"]
    for vid in sorted(volumes):
        v = volumes[vid]
        out.append("\t[%d] = %s," % (vid, "false" if v is False else lua([round(c, 1) for c in v])))
    out += ["}", "", "ns.WAY_NET_CONDS = {"]
    for cid in sorted(comp.conds, key=int):
        expr = comp.conds[cid]
        if not (expr is True or expr is False or expr == UNKNOWN):
            out.append("\t[%s] = %s," % (cid, lua(expr)))
    out += ["}", ""]
    return "\n".join(out), len(nodes), len(edges)


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(1)
    build_id = sys.argv[1]
    folder = sys.argv[2] if len(sys.argv) > 2 else tempfile.mkdtemp(prefix="waynet")
    text, node_count, edge_count = build(load(folder, build_id), build_id)
    with open(OUT, "w", encoding="utf-8", newline="\n") as f:
        f.write(text)
    print("wrote %s: %d nodes, %d edges" % (os.path.normpath(OUT), node_count, edge_count))


if __name__ == "__main__":
    main()
