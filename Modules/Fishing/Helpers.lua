local addonName, ns = ...

-- Fishing: the CVars set while a cast is out (soft interact for the reel press, auto loot, louder splash) and their
-- backup. The old values are saved in TomteDB.fishing.restore before the first SetCVar, so a crash or disconnect
-- mid-cast is put right at the next login. A value goes back only while it still holds what Tomte set: a change the
-- player made meanwhile wins. SoftTargetInteract and SoftTargetInteractRange are secure CVars (warcraft.wiki.gg CVar
-- list): out of combat only, so a restore that falls in combat waits for PLAYER_REGEN_ENABLED.

local db
local pending = false -- secure values still to put back after combat

local function Current()
	local current = {}
	for _, cvar in ipairs(ns.FISHING_CVARS) do
		current[cvar] = C_CVar.GetCVar(cvar)
	end
	return current
end

local function Apply(values)
	for cvar, value in pairs(values) do
		C_CVar.SetCVar(cvar, value)
	end
end

local function FishingNow()
	return ns.Fishing_IsFishing ~= nil and ns.Fishing_IsFishing()
end

-- The module's event bus (Key.lua and Fishing.lua share it). Helpers loads first, so its handlers run first.
local events = ns.NewEvents()
ns.Fishing_Events = events
local OWNER = "helpers"

function ns.FishingHelpers_Start()
	if not db then
		return
	end
	local current = Current()
	local plan = ns.Fishing_CVarPlan({ autoLoot = db.autoLoot, loud = db.loud }, current)
	if InCombatLockdown() then
		for cvar in pairs(ns.FISHING_SECURE_CVARS) do
			plan[cvar] = nil
		end
	end
	ns.Fishing_Backup(db.restore, plan, current) -- before any SetCVar
	Apply(plan)
end

function ns.FishingHelpers_Stop()
	if not (db and next(db.restore)) then
		pending = false
		return
	end
	if InCombatLockdown() then
		-- The plain CVars go back now; the secure ones after combat.
		local now = {}
		for cvar, entry in pairs(db.restore) do
			if not ns.FISHING_SECURE_CVARS[cvar] then
				now[cvar] = entry
			end
		end
		for cvar in pairs(now) do
			db.restore[cvar] = nil
		end
		Apply(ns.Fishing_RestoreList(now, Current()))
		pending = next(db.restore) ~= nil
		if pending then
			events:Watch(OWNER, "PLAYER_REGEN_ENABLED")
		end
		return
	end
	Apply(ns.Fishing_RestoreList(db.restore, Current()))
	pending = false
end

function ns.FishingHelpers_Pending()
	return pending
end

-- { [cvar] = { old, set } } still backed up (for /tomte fishing status).
function ns.FishingHelpers_Backups()
	return db and db.restore or {}
end

events:On(OWNER, "PLAYER_REGEN_ENABLED", function()
	events:Unwatch(OWNER, "PLAYER_REGEN_ENABLED")
	if pending and not FishingNow() then -- still fishing: the key's own stop restores later
		ns.FishingHelpers_Stop()
	end
end)

-- Crash or disconnect recovery: a backup left from last session, with no cast out now.
events:On(OWNER, "PLAYER_ENTERING_WORLD", function()
	events:Unwatch(OWNER, "PLAYER_ENTERING_WORLD")
	C_Timer.After(0, function() -- after Key.lua's own PLAYER_ENTERING_WORLD has seen a cast still out (/reload)
		if next(db.restore) and not FishingNow() then
			ns.FishingHelpers_Stop()
		end
	end)
end)

-- Logging out mid-cast: put the values back before the client saves them.
events:On(OWNER, "PLAYER_LOGOUT", function()
	ns.FishingHelpers_Stop()
end)

function ns.FishingHelpers_Init(moduleDB)
	db = moduleDB
	events:Watch(OWNER, "PLAYER_ENTERING_WORLD")
	events:Watch(OWNER, "PLAYER_LOGOUT")
end
