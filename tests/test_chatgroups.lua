-- Run from the AddOns folder: lua Tomte/tests/test_chatgroups.lua
local ns = { CONTENT_FOREVER = 0 }
local registered
function ns.Content_Register(_, _, list)
	registered = list
end
assert(loadfile("Tomte/Data/Forever/Dungeons.lua"))("Tomte", ns)
assert(loadfile("Tomte/Modules/ChatGroups/Data.lua"))("Tomte", ns)

local H = dofile("Tomte/tests/harness.lua")
local test, eq = H.test, H.eq

local function parse(text)
	return ns.ChatGroups_Parse(text, registered)
end

test("groups asking for people", function()
	local e = parse("LF2M RFC need tank and heals!")
	eq(e.kind, "group")
	eq(e.dungeon, "rfc")
	eq(e.tank, true)
	eq(e.heal, true)
	eq(e.dps, false)
	eq(parse("LFM WC").kind, "group")
	eq(parse("need healer for sfk").kind, "group")
	eq(parse("lf tank for bfd").kind, "group", "lf plus a role")
	eq(parse("Looking for more, Gnomeregan").dungeon, "gnomer")
end)

test("players asking for a group", function()
	local e = parse("Priest LFG Deadmines, can heal")
	eq(e.kind, "player")
	eq(e.dungeon, "vc")
	eq(e.heal, true)
	eq(parse("looking for group sm").kind, "player")
	eq(parse("lf rfk").kind, "player", "lf with no role")
end)

test("the whole word counts", function()
	eq(parse("lfm stockade").dungeon, "stocks")
	eq(parse("lfm astronomy").dungeon, nil, "no dungeon in there")
	eq(parse("I need a drink"), nil, "no dungeon")
	eq(parse("lfm ST").dungeon, "st")
	eq(parse("lfm sharp").dungeon, nil)
end)

test("the longest name wins at the same spot, the first dungeon wins overall", function()
	eq(parse("lfm dm east").dungeon, "dire")
	eq(parse("lfm dm").dungeon, "vc")
	eq(parse("lfm dire maul tribute").dungeon, "dire")
	eq(parse("lfm wc then sfk").dungeon, "wc")
	eq(parse("lf1m Zul'Farrak").dungeon, "zf", "the apostrophe")
end)

test("what isn't someone looking", function()
	eq(parse("WTS RFC boost 5g"), nil, "selling")
	eq(parse("rfc is a great dungeon"), nil, "no one looking")
	eq(parse("Guild recruiting for sm runs lfm"), nil, "guild ad")
	eq(parse("lfm"), nil, "no dungeon")
	eq(parse(nil), nil)
end)

test("plainly asking counts without a dungeon, as for a quest", function()
	local e = parse("lfg fizle claw quest")
	eq(e.kind, "player")
	eq(e.dungeon, nil)
	eq(parse("LF2M Elder Crag, need healer").kind, "group")
	eq(parse("LF2M Elder Crag, need healer").heal, true)
	eq(parse("looking for group fizle claw").kind, "player")
end)

test("a linked quest gives its name and level", function()
	local e = parse("LFG [[12] Hallkor's Hoof (96877)]")
	eq(e.kind, "player")
	eq(e.quest, "Hallkor's Hoof")
	eq(e.questLevel, 12)
	e = parse("LFM |cffffff00|Hquest:99052:11|h[Threat from Below]|h|r")
	eq(e.kind, "group")
	eq(e.quest, "Threat from Below")
	eq(e.questLevel, 11)
	e = parse("LFM |cffffff00|Hquest:99052:-1|h[[11] Threat from Below (99052)]|h|r")
	eq(e.quest, "Threat from Below")
	eq(e.questLevel, 11)
	e = parse("lfg fizle claw quest")
	eq(e.quest, nil)
	eq(e.questLevel, nil)
	eq(parse("[[12] Hallkor's Hoof (96877)]"), nil, "only a link: nobody is asking")
end)

test("the quest's level counts for the level filter, and names the row", function()
	local byKey = ns.ChatGroups_ByKey(registered)
	local list = { { kind = "player", quest = "Hoof", questLevel = 12 }, { kind = "player" } }
	eq(#ns.ChatGroups_View(list, "all", true, 12, byKey), 2)
	eq(#ns.ChatGroups_View(list, "all", true, 40, byKey), 1, "too far from your level; what has no level stays")
	eq(ns.ChatGroups_Title(list[1], byKey), "[12] Hoof: Looking for a group")
	eq(ns.ChatGroups_Title({ kind = "group", quest = "Hoof" }, byKey), "Hoof: Needs more people")
end)

test("without a dungeon, loose words don't count", function()
	eq(parse("need healer pls"), nil, "need alone")
	eq(parse("lf enchanter"), nil, "lf alone: mostly someone after a service")
	eq(parse("anyone want to look for more"), nil)
	eq(parse("lfg"), nil, "says nothing else")
	eq(parse("LFM!"), nil, "says nothing else")
	eq(parse("wts lfg fizle claw"), nil, "selling")
	eq(parse("guild lfm for quests"), nil, "a guild ad")
end)

test("links count as their name", function()
	eq(parse("lfm |cffffff00|Hquest:1:13|h[Ragefire Chasm]|h|r").dungeon, "rfc")
end)

test("Add: a sender's new message replaces the old, newest first, capped", function()
	local list = {}
	ns.ChatGroups_Add(list, { sender = "Aldric", at = 1 })
	ns.ChatGroups_Add(list, { sender = "Kesha", at = 2 })
	ns.ChatGroups_Add(list, { sender = "Aldric", at = 3 })
	eq(#list, 2)
	eq(list[1].sender, "Aldric")
	eq(list[1].at, 3)
	for i = 1, 100 do
		ns.ChatGroups_Add(list, { sender = "S" .. i, at = i })
	end
	eq(#list, 60)
	eq(list[1].sender, "S100")
end)

test("Prune takes out the old", function()
	local list = { { at = 95 }, { at = 50 } }
	ns.ChatGroups_Prune(list, 100, 10)
	eq(#list, 1)
	eq(list[1].at, 95)
end)

test("View filters by kind and level", function()
	local byKey = ns.ChatGroups_ByKey(registered)
	local list = { { kind = "group", dungeon = "rfc" }, { kind = "player", dungeon = "rfc" }, { kind = "group", dungeon = "strat" } }
	eq(#ns.ChatGroups_View(list, "all", false, 15, byKey), 3)
	eq(#ns.ChatGroups_View(list, "group", false, 15, byKey), 2)
	eq(#ns.ChatGroups_View(list, "player", false, 15, byKey), 1)
	eq(#ns.ChatGroups_View(list, "all", true, 15, byKey), 2, "near 15")
	eq(#ns.ChatGroups_View(list, "all", true, 60, byKey), 1, "near 60")
	list[#list + 1] = { kind = "player" }
	eq(#ns.ChatGroups_View(list, "all", true, 60, byKey), 2, "no dungeon: stays, its level isn't known")
	eq(#ns.ChatGroups_View(list, "group", true, 60, byKey), 1, "but still goes by kind")
end)

test("Title names the dungeon, or says it's something else", function()
	local byKey = ns.ChatGroups_ByKey(registered)
	eq(ns.ChatGroups_Title({ kind = "group", dungeon = "rfc", tank = true }, byKey), "Ragefire Chasm: Needs tank")
	eq(ns.ChatGroups_Title({ kind = "player" }, byKey), "Quest or other: Looking for a group")
end)

test("Near reaches a little past a dungeon's levels", function()
	local d = { min = 20, max = 30 }
	eq(ns.ChatGroups_Near(d, 17), true)
	eq(ns.ChatGroups_Near(d, 16), false)
	eq(ns.ChatGroups_Near(d, 33), true)
	eq(ns.ChatGroups_Near(d, 34), false)
	eq(ns.ChatGroups_Near(nil, 20), false)
end)

test("RoleText reads for both kinds", function()
	eq(ns.ChatGroups_RoleText({ kind = "group", tank = true, heal = true }), "Needs tank, healer")
	eq(ns.ChatGroups_RoleText({ kind = "group" }), "Needs more people")
	eq(ns.ChatGroups_RoleText({ kind = "player", dps = true }), "Looking for a group as damage")
	eq(ns.ChatGroups_RoleText({ kind = "player" }), "Looking for a group")
end)

test("every dungeon is complete, with unique keys", function()
	local seen = {}
	for _, d in ipairs(registered) do
		eq(seen[d.key], nil, d.key)
		seen[d.key] = true
		eq(type(d.name), "string", d.key)
		eq(d.min <= d.max, true, d.key)
		eq(#d.aliases > 0, true, d.key)
	end
end)

H.done()
