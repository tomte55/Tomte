-- Run from the AddOns folder: lua Tomte/tests/test_fishing.lua
local ns = {}
assert(loadfile("Tomte/Modules/Fishing/Data.lua"))("Tomte", ns)

local H = dofile("Tomte/tests/harness.lua")
local test, eq = H.test, H.eq
local function first()
	return 1
end

test("fishing spell by id and by name", function()
	eq(ns.Fishing_IsFishingSpell(131476, "Fishing", "Fishing"), true, "id")
	eq(ns.Fishing_IsFishingSpell(999999999, "Fishing", "Fishing"), true, "name")
	eq(ns.Fishing_IsFishingSpell(999999999, "Fireball", "Fishing"), false, "other")
	eq(ns.Fishing_IsFishingSpell(nil, nil, "Fishing"), false, "nil")
	eq(ns.Fishing_IsFishingSpell(999999999, "Fishing", nil), false, "no fishing name")
	eq(ns.Fishing_IsFishingSpell("131476", nil, "Fishing"), false, "not a number")
end)

test("object id from guid", function()
	eq(ns.Fishing_ObjectID("GameObject-0-3767-2444-2424-35591-0000ABCDEF"), 35591)
	eq(ns.Fishing_ObjectID("Creature-0-3767-2444-2424-12345-0000ABCDEF"), nil, "creature")
	eq(ns.Fishing_ObjectID("junk"), nil, "junk")
	eq(ns.Fishing_ObjectID(nil), nil, "nil")
	eq(ns.Fishing_ObjectID(""), nil, "empty")
	eq(ns.Fishing_ObjectID(42), nil, "number")
end)

test("raft pick", function()
	eq(ns.Fishing_PickRaft({ 85500, 198428 }, 198428, first), 198428, "chosen")
	eq(ns.Fishing_PickRaft({ 85500 }, 198428, first), 85500, "chosen not owned -> first owned")
	eq(ns.Fishing_PickRaft({ 85500, 198428 }, 0, function(n)
		return n
	end), 198428, "random")
	eq(ns.Fishing_PickRaft({}, 0, first), nil, "none owned")
	eq(ns.Fishing_PickRaft(nil, 0, first), nil, "no list")
end)

local OPTS = { lootProtect = true, dismount = false, raft = { on = false, pick = 0 }, bobber = false, random = first }
local function S(t)
	local s = { known = true, rafts = {} }
	for k, v in pairs(t or {}) do
		s[k] = v
	end
	return s
end
local function O(t)
	local o = {}
	for k, v in pairs(OPTS) do
		o[k] = v
	end
	for k, v in pairs(t or {}) do
		o[k] = v
	end
	return o
end

test("next action: plain cast", function()
	eq(ns.Fishing_NextAction(S(), O()).kind, "cast")
end)

test("next action: blockers in order", function()
	eq(ns.Fishing_NextAction(S({ lootOpen = true }), O()).reason, "loot")
	eq(ns.Fishing_NextAction(S({ lootOpen = true }), O({ lootProtect = false })).kind, "cast", "protection off")
	eq(ns.Fishing_NextAction(S({ dead = true }), O()).kind, "none")
	eq(ns.Fishing_NextAction(S({ blocked = true }), O()).kind, "none")
	eq(ns.Fishing_NextAction(S({ known = false }), O()).reason, "unknown")
	eq(ns.Fishing_NextAction(S({ known = false }), O()).kind, "none", "unknown does nothing")
	eq(ns.Fishing_NextAction(S({ lootOpen = true, dead = true }), O()).reason, "loot", "loot first")
	eq(ns.Fishing_NextAction(S({ dead = true, known = false }), O()).reason, "dead", "dead before unknown")
	eq(ns.Fishing_NextAction(S({ fishing = true }), O()).reason, "fishing", "a click while the bobber is out")
end)

test("next action: mounted", function()
	eq(ns.Fishing_NextAction(S({ mounted = true }), O()).kind, "none")
	eq(ns.Fishing_NextAction(S({ mounted = true }), O({ dismount = true })).kind, "dismount")
	eq(ns.Fishing_NextAction(S({ mounted = true, flying = true }), O({ dismount = true })).kind, "none", "flying")
end)

test("next action: swimming and rafts", function()
	eq(ns.Fishing_NextAction(S({ swimming = true }), O()).kind, "none", "no raft option")
	local raftOn = O({ raft = { on = true, pick = 0 } })
	eq(ns.Fishing_NextAction(S({ swimming = true }), raftOn).kind, "none", "no raft owned")
	local a = ns.Fishing_NextAction(S({ swimming = true, rafts = { 85500 } }), raftOn)
	eq(a.kind, "toy")
	eq(a.item, 85500)
	eq(ns.Fishing_NextAction(S({ rafts = { 85500 }, raftLeft = 30 }), raftOn).kind, "toy", "renew under 60 s")
	eq(ns.Fishing_NextAction(S({ rafts = { 85500 }, raftLeft = 300 }), raftOn).kind, "cast", "plenty left")
	eq(ns.Fishing_NextAction(S({ rafts = { 85500 }, raftLeft = 30 }), O()).kind, "cast", "rafts off: no renew")
	eq(ns.Fishing_NextAction(S({ rafts = {}, raftLeft = 30 }), raftOn).kind, "cast", "renew, none owned")
end)

test("next action: oversized bobber", function()
	local on = O({ bobber = true })
	local a = ns.Fishing_NextAction(S({ bobberOwned = true, bobberReady = true }), on)
	eq(a.kind, "toy")
	eq(a.item, 202207)
	eq(ns.Fishing_NextAction(S({ bobberOwned = true, bobberReady = true, bobberUp = true }), on).kind, "cast", "up")
	eq(ns.Fishing_NextAction(S({ bobberOwned = true, bobberReady = false }), on).kind, "cast", "cooldown")
	eq(ns.Fishing_NextAction(S({ bobberOwned = false, bobberReady = true }), on).kind, "cast", "not owned")
	eq(ns.Fishing_NextAction(S({ bobberOwned = true, bobberReady = true }), O()).kind, "cast", "option off")
end)

test("cvar plan: soft interact always, helpers by option", function()
	local cur = { SoftTargetInteract = "1", SoftTargetInteractRange = "10", SoftTargetInteractRangeIsHard = "0",
		autoLootDefault = "0", Sound_MusicVolume = "0.4", Sound_AmbienceVolume = "0.6", Sound_SFXVolume = "0.5",
		Sound_EnableSoundWhenGameIsInBG = "0" }
	local p = ns.Fishing_CVarPlan({ autoLoot = true, loud = { on = false } }, cur)
	eq(p.SoftTargetInteract, "3")
	eq(p.SoftTargetInteractRange, "15")
	eq(p.autoLootDefault, "1")
	eq(p.SoftTargetInteractRangeIsHard, nil, "already 0")
	eq(p.Sound_MusicVolume, nil, "loud off")
	p = ns.Fishing_CVarPlan({ autoLoot = false, loud = { on = true, sfx = 1, background = true } }, cur)
	eq(p.autoLootDefault, nil)
	eq(p.Sound_MusicVolume, "0")
	eq(p.Sound_AmbienceVolume, "0")
	eq(p.Sound_SFXVolume, "1")
	eq(p.Sound_EnableSoundWhenGameIsInBG, "1")
	p = ns.Fishing_CVarPlan({ autoLoot = false, loud = { on = true, sfx = 0.5, background = false } }, cur)
	eq(p.Sound_SFXVolume, nil, "same volume")
	eq(p.Sound_EnableSoundWhenGameIsInBG, nil, "background off")
	cur.SoftTargetInteract, cur.SoftTargetInteractRange, cur.SoftTargetInteractRangeIsHard = "3", "20", "1"
	p = ns.Fishing_CVarPlan({ autoLoot = false, loud = { on = false } }, cur)
	eq(p.SoftTargetInteract, nil, "already on")
	eq(p.SoftTargetInteractRange, nil, "already wider")
	eq(p.SoftTargetInteractRangeIsHard, "0", "hard range off")
	cur.Sound_MusicVolume = "0.000000"
	p = ns.Fishing_CVarPlan({ autoLoot = false, loud = { on = true, sfx = 1 } }, cur)
	eq(p.Sound_MusicVolume, nil, "0.000000 is 0")
	p = ns.Fishing_CVarPlan({}, {})
	eq(p.SoftTargetInteract, "3", "missing current values")
end)

test("backup and restore", function()
	local restore = {}
	ns.Fishing_Backup(restore, { autoLootDefault = "1", SoftTargetInteract = "3" },
		{ autoLootDefault = "0", SoftTargetInteract = "1" })
	eq(restore.autoLootDefault.old, "0")
	eq(restore.autoLootDefault.set, "1")
	ns.Fishing_Backup(restore, { autoLootDefault = "1" }, { autoLootDefault = "1" })
	eq(restore.autoLootDefault.old, "0", "second backup keeps the first old value")
	local back = ns.Fishing_RestoreList(restore, { autoLootDefault = "1", SoftTargetInteract = "2" })
	eq(back.autoLootDefault, "0", "still ours -> restore")
	eq(back.SoftTargetInteract, nil, "player changed it -> leave it")
	eq(next(restore), nil, "backup emptied")
	eq(next(ns.Fishing_RestoreList({}, {})), nil, "nothing to restore")
	restore = { Sound_SFXVolume = { old = "0.5", set = "1" } }
	back = ns.Fishing_RestoreList(restore, { Sound_SFXVolume = "1.0" })
	eq(back.Sound_SFXVolume, "0.5", "1.0 is still 1")
end)

test("macro text", function()
	local names = { fishing = "Fishing", toy = "Anglers Fishing Raft" }
	eq(ns.Fishing_MacroText({ kind = "cast" }, names), "/cast Fishing")
	eq(ns.Fishing_MacroText({ kind = "dismount" }, names), "/dismount\n/cast Fishing")
	eq(ns.Fishing_MacroText({ kind = "toy", item = 85500 }, names), "/use Anglers Fishing Raft")
	eq(ns.Fishing_MacroText({ kind = "none" }, names), "")
	eq(ns.Fishing_MacroText({ kind = "toy", item = 85500 }, { fishing = "Fishing" }), "", "toy name not loaded")
	eq(ns.Fishing_MacroText({ kind = "cast" }, {}), "", "fishing name not loaded")
end)

test("keys up", function()
	local down = { ["§"] = true }
	local isDown = function(k)
		return down[k] == true
	end
	eq(ns.Fishing_KeysUp({ "§" }, isDown), false)
	eq(ns.Fishing_KeysUp({ "F", "§" }, isDown), false, "second key held")
	eq(ns.Fishing_KeysUp({ "F" }, isDown), true)
	eq(ns.Fishing_KeysUp({}, isDown), true, "no keys")
	eq(ns.Fishing_KeysUp({ "SHIFT-§" }, isDown), false, "modifier stripped: the main key is held")
	eq(ns.Fishing_KeysUp({ "CTRL-SHIFT-F" }, isDown), true, "modifiers stripped")
end)

test("base key", function()
	eq(ns.Fishing_BaseKey("SHIFT-F"), "F")
	eq(ns.Fishing_BaseKey("BUTTON4"), "BUTTON4")
	eq(ns.Fishing_BaseKey("ALT-CTRL-MINUS"), "MINUS")
	eq(ns.Fishing_BaseKey("CTRL--"), "-")
	eq(ns.Fishing_BaseKey("-"), "-")
end)

test("underlight angler: fixed only for the Angler at tier 0", function()
	eq(ns.Fishing_AnglerNeedsFix(133755, 0), true)
	eq(ns.Fishing_AnglerNeedsFix(133755, nil), true, "no tier reported")
	eq(ns.Fishing_AnglerNeedsFix(133755, 1), false, "the game reports it right")
	eq(ns.Fishing_AnglerNeedsFix(128402, 0), false, "another artifact")
	eq(ns.Fishing_AnglerShowsTier(1), true)
	eq(ns.Fishing_AnglerShowsTier(0), true)
	eq(ns.Fishing_AnglerShowsTier(2), false)
	eq(ns.Fishing_AnglerShowsTier(nil), false)
end)

test("rods: only a fishing pole counts, the highest level wins", function()
	eq(ns.Fishing_IsRod(2, 20), true)
	eq(ns.Fishing_IsRod(2, 7), false, "a sword")
	eq(ns.Fishing_IsRod(4, 20), false, "not a weapon")
	eq(ns.Fishing_IsRod(nil, nil), false)
	eq(ns.Fishing_PickRod({}), nil)
	eq(ns.Fishing_PickRod({ { itemID = 1, ilvl = 5 }, { itemID = 2, ilvl = 30 }, { itemID = 3, ilvl = 30 } }), 2)
	eq(ns.Fishing_PickRod({ { itemID = 1 } }), 1, "level unknown")
end)

test("lures: the strongest on hand", function()
	local function has(ids)
		return function(id)
			return ids[id] == true
		end
	end
	eq(ns.Fishing_PickLure({ 1, 2, 3 }, has({ [1] = true, [2] = true })), 2)
	eq(ns.Fishing_PickLure({ 1, 2, 3 }, has({})), nil)
	eq(ns.Fishing_PickLure({}, has({ [1] = true })), nil)
end)

test("next action: the rod, then a lure, then the cast", function()
	local opts = { dismount = true }
	local function act(extra)
		local s = { known = true }
		for k, v in pairs(extra) do
			s[k] = v
		end
		return ns.Fishing_NextAction(s, opts)
	end
	eq(act({}).kind, "cast", "retail never sets these")
	eq(act({ needsRod = true, rod = 7 }).kind, "equip")
	eq(act({ needsRod = true, rod = 7 }).item, 7)
	eq(act({ needsRod = true }).reason, "norod")
	eq(act({ needsRod = true }).kind, "none")
	eq(act({ needsRod = true, rod = 7, lure = 9 }).kind, "equip", "the rod first")
	eq(act({ lure = 9 }).kind, "lure")
	eq(act({ lure = 9 }).item, 9)
	eq(act({ lure = 9, lureUp = true }).kind, "cast", "already on")
	eq(act({ lureUp = true }).kind, "cast", "none carried")
	eq(act({ needsRod = true, rod = 7, swimming = true }).reason, "swimming", "not in the water")
	eq(act({ needsRod = true, rod = 7, mounted = true }).kind, "equip", "before the dismount")
	eq(act({ mounted = true }).kind, "dismount")
	eq(act({ needsRod = true, rod = 7, mounted = true, flying = true }).reason, "mounted", "not while flying")
end)

test("macros for the rod and a lure", function()
	eq(ns.Fishing_MacroText({ kind = "equip", item = 6256 }, {}), "/equip item:6256")
	eq(ns.Fishing_MacroText({ kind = "lure", item = 6529 }, {}), "/use item:6529\n/use 16")
end)

H.done()
