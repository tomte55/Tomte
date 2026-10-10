-- Run from the AddOns folder: lua Tomte/tests/test_fishing.lua
local ns = {}
assert(loadfile("Tomte/Modules/Fishing/Data.lua"))("Tomte", ns)

local failures = 0
local function test(name, fn)
	local ok, err = pcall(fn)
	if ok then
		print("ok   " .. name)
	else
		failures = failures + 1
		print("FAIL " .. name .. ": " .. tostring(err))
	end
end
local function eq(actual, expected, label)
	if actual ~= expected then
		error((label or "value") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual), 2)
	end
end
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

print(failures == 0 and "all passed" or (failures .. " failed"))
if failures > 0 then
	os.exit(1)
end
