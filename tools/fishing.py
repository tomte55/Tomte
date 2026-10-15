"""Prints the fishing channel spell IDs for ns.FISHING_CHANNELS in Modules/Fishing/Data.lua, from the client's spell
tables read from wago.tools CSV exports. Dev-only, not in the release zip.

    python -I tools/fishing.py <build> [csv-dir]

<build> is the client build, e.g. 12.1.5.70391. With no csv-dir the tables are downloaded into a new, empty temp
folder. Tables: SpellName, SpellEffect.

A spell counts when its (English) name contains "Fishing" and it either needs the Fishing skill (a SKILL effect, 118,
on skill line 356) or channels an aura (APPLY_AURA, 6) while summoning a bobber object (SUMMON_OBJECT 50 or 171).
That covers the profession's own cast and the quest, toy and event variants with other names ("Ice Fishing", "Void
Hole Fishing"); toys that only place an object (a fishing chair) don't channel and are left out. Spells named exactly
like the player's Fishing spell are also matched by name at run time, so a missing one of those still works.
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))  # the -I flag leaves the script folder off sys.path
import wago

SKILL, AURA, SUMMON_OBJECT, SUMMON_OBJECT_SLOT = 118, 6, 50, 171
FISHING_SKILL_LINE = "356"


def fishing_spells(names, effects):
    found = []
    for spell_id, name in names.items():
        if "Fishing" not in name:
            continue
        kinds = effects.get(spell_id, [])
        needs_skill = any(e == SKILL and misc == FISHING_SKILL_LINE for e, misc in kinds)
        channels_bobber = any(e == AURA for e, _ in kinds) and any(
            e in (SUMMON_OBJECT, SUMMON_OBJECT_SLOT) for e, _ in kinds)
        if needs_skill or channels_bobber:
            found.append(spell_id)
    return sorted(found)


def main():
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    data = wago.load(wago.folder_from_argv("fishing-"), ["SpellName", "SpellEffect"], sys.argv[1])
    names = {int(r["ID"]): r["Name_lang"] for r in data["SpellName"]}
    effects = {}
    for r in data["SpellEffect"]:
        effects.setdefault(int(r["SpellID"]), []).append((int(r["Effect"]), r["EffectMiscValue_0"]))
    ids = fishing_spells(names, effects)
    print("-- %d spells, build %s" % (len(ids), sys.argv[1]))
    line = "\t"
    for spell_id in ids:
        item = "%d, " % spell_id
        if len(line.expandtabs(4)) + len(item) > 118:
            print(line.rstrip())
            line = "\t"
        line += item
    print(line.rstrip())


if __name__ == "__main__":
    main()
