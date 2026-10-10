local addonName, ns = ...

-- Fishing: pure rules (no WoW API; unit-tested in tests/test_fishing.lua).
-- Fishing channel spell IDs and the bobber's game-object ID (35591) are game facts taken from Angleur's tables
-- (LegolandoBloom, All Rights Reserved: IDs only, no code). Toy and aura IDs checked on wowhead.

ns.FISHING_SPELL = 131474 -- the Fishing spell you cast (spellbook); its channel is 131476
ns.FISHING_BOBBER_OBJECT = 35591
ns.FISHING_RAFT_RENEW = 60 -- renew a raft with less than this many seconds left
ns.FISHING_LOOT_TIMEOUT = 3 -- loot protection never blocks longer than this
ns.FISHING_CHANNELS = {}
for _, id in ipairs({
	7620, 131476, 51294, 18248, 131474, 33095, 7732, 7731, 110410, 88868, 131490, 139505, 1252746, 158743,
	219847, 227511, 262860, 249045, 301092, 295727, 361269, 377895, 405274, 398703, 377831, 437890, 438491,
	463743, 1224771, 1294463, 1303761, 1239040, 1239227, 1241356, 1286703, 1303612, 1282907, 1239033,
}) do
	ns.FISHING_CHANNELS[id] = true
end
ns.FISHING_RAFTS = { -- toy item, its aura
	{ item = 85500, aura = 124036 }, -- Anglers Fishing Raft
	{ item = 198428, aura = 383268 }, -- Tuskarr Dinghy
	{ item = 166461, aura = 288758 }, -- Gnarlwood Waveboard
	{ item = 235801, aura = 1218420 }, -- Personal Fishing Barge
}
ns.FISHING_BOBBER_TOY = { item = 202207, aura = 397827 } -- Reusable Oversized Bobber: 1 h buff, 15 min cooldown

-- Every CVar the plan below can change. SoftTargetInteract and SoftTargetInteractRange are secure (out of combat
-- only); the others aren't.
ns.FISHING_CVARS = {
	"SoftTargetInteract", "SoftTargetInteractRange", "SoftTargetInteractRangeIsHard", "autoLootDefault",
	"Sound_MusicVolume", "Sound_AmbienceVolume", "Sound_SFXVolume", "Sound_EnableSoundWhenGameIsInBG",
}
ns.FISHING_SECURE_CVARS = { SoftTargetInteract = true, SoftTargetInteractRange = true }

function ns.Fishing_IsFishingSpell(spellID, spellName, fishingName)
	if type(spellID) == "number" and ns.FISHING_CHANNELS[spellID] then
		return true
	end
	return type(spellName) == "string" and type(fishingName) == "string" and spellName == fishingName
end

-- "GameObject-0-server-instance-zone-<id>-spawn" -> id. Anything else -> nil.
function ns.Fishing_ObjectID(guid)
	if type(guid) ~= "string" then
		return nil
	end
	-- guid:match, not strsplit: the same code runs in plain Lua tests and in game.
	local kind, id = guid:match("^(%a+)%-[^-]*%-[^-]*%-[^-]*%-[^-]*%-(%d+)")
	if kind ~= "GameObject" then
		return nil
	end
	return tonumber(id)
end

-- The chosen raft when it's owned, otherwise a random owned one (pick 0) or the first owned one. nil: none owned.
function ns.Fishing_PickRaft(owned, pick, random)
	if type(owned) ~= "table" or #owned == 0 then
		return nil
	end
	if pick and pick ~= 0 then
		for _, item in ipairs(owned) do
			if item == pick then
				return item
			end
		end
		return owned[1]
	end
	return owned[random(#owned)]
end

local function Action(kind, reason, item)
	return { kind = kind, reason = reason, item = item }
end

-- What the next press of the key does. s: the game right now, opts: the settings (see the plan's interface).
-- Order: loot protection, a cast already out, can't act, not learned, mounted, swimming, bobber toy, raft renew, cast.
function ns.Fishing_NextAction(s, opts)
	local raftOn = opts.raft and opts.raft.on
	if s.lootOpen and opts.lootProtect then
		return Action("none", "loot")
	end
	if s.fishing then
		return Action("none", "fishing") -- a click while the bobber is out: reeling in is the key's job
	end
	if s.dead then
		return Action("none", "dead")
	end
	if s.blocked then
		return Action("none", "blocked")
	end
	if not s.known then
		return Action("none", "unknown")
	end
	if s.mounted then
		if opts.dismount and not s.flying then
			return Action("dismount", "mounted")
		end
		return Action("none", "mounted")
	end
	if s.swimming then
		local raft = raftOn and ns.Fishing_PickRaft(s.rafts, opts.raft.pick, opts.random)
		if raft then
			return Action("toy", "raft", raft)
		end
		return Action("none", "swimming")
	end
	if opts.bobber and s.bobberOwned and s.bobberReady and not s.bobberUp then
		return Action("toy", "bobber", ns.FISHING_BOBBER_TOY.item)
	end
	if raftOn and s.raftLeft and s.raftLeft < ns.FISHING_RAFT_RENEW then
		local raft = ns.Fishing_PickRaft(s.rafts, opts.raft.pick, opts.random)
		if raft then
			return Action("toy", "renew", raft)
		end
	end
	return Action("cast", "cast")
end

-- CVar values compare as numbers when both are numbers ("1" == "1.0"), otherwise as text.
local function Same(a, b)
	local x, y = tonumber(a), tonumber(b)
	if x and y then
		return x == y
	end
	return a == b
end
ns.Fishing_SameValue = Same

-- The CVars to set while a cast is out: { [cvar] = value }, only those whose value would change.
function ns.Fishing_CVarPlan(opts, current)
	local plan = {}
	local function want(cvar, value)
		if not Same(current[cvar], value) then
			plan[cvar] = value
		end
	end
	want("SoftTargetInteract", "3")
	local range = tonumber(current.SoftTargetInteractRange)
	if not (range and range >= 15) then
		plan.SoftTargetInteractRange = "15"
	end
	want("SoftTargetInteractRangeIsHard", "0")
	if opts.autoLoot then
		want("autoLootDefault", "1")
	end
	local loud = opts.loud
	if loud and loud.on then
		want("Sound_MusicVolume", "0")
		want("Sound_AmbienceVolume", "0")
		want("Sound_SFXVolume", tostring(loud.sfx or 1))
		if loud.background then
			want("Sound_EnableSoundWhenGameIsInBG", "1")
		end
	end
	return plan
end

-- Saves the old value of each planned CVar not already backed up (a second cast keeps the first old value).
function ns.Fishing_Backup(restore, plan, current)
	for cvar, value in pairs(plan) do
		if not restore[cvar] then
			restore[cvar] = { old = current[cvar], set = value }
		end
	end
end

-- { [cvar] = old } for every backup whose CVar still holds what Tomte set (a change the player made meanwhile
-- wins). Empties the backup either way.
function ns.Fishing_RestoreList(restore, current)
	local list = {}
	for cvar, entry in pairs(restore) do
		if type(entry) == "table" and entry.old ~= nil and Same(current[cvar], entry.set) then
			list[cvar] = entry.old
		end
		restore[cvar] = nil -- clearing a field during pairs() is allowed in Lua
	end
	return list
end

-- The secure button's macro for an action. names = { fishing, toy }; "" when a name isn't loaded.
function ns.Fishing_MacroText(action, names)
	if action.kind == "cast" or action.kind == "dismount" then
		if not names.fishing then
			return ""
		end
		local cast = "/cast " .. names.fishing
		return action.kind == "dismount" and ("/dismount\n" .. cast) or cast
	end
	if action.kind == "toy" then
		return names.toy and ("/use " .. names.toy) or ""
	end
	return ""
end

-- "CTRL-SHIFT-F" -> "F", "CTRL--" -> "-": IsKeyDown takes the key itself.
function ns.Fishing_BaseKey(key)
	if key:sub(-1) == "-" then
		return "-"
	end
	return key:match("([^-]+)$") or key
end

-- True when no key in the list is held. isDown(key) -> bool.
function ns.Fishing_KeysUp(keys, isDown)
	for _, key in ipairs(keys) do
		if isDown(ns.Fishing_BaseKey(key)) then
			return false
		end
	end
	return true
end
