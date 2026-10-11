local addonName, ns = ...

-- Gear Check, part 3: chat hints. No weights (once per session and spec), built-in weights at max level (once per
-- character and spec, and again when the season moves past theirs), missing enchants and empty sockets when the
-- character pane opens. Contexts are in Context.lua; Gear.lua triggers the hints.

local function DB()
	return ns.gearDB
end

local Context = ns.Gear_OwnContext
local SpecAt = ns.Gear_SpecAt
local CurrentSeason = ns.Gear_CurrentSeason

local _, _, classID = UnitClass("player")

local noWeightsSaid = {}

-- This character's db.hinted table ([specID] = seen). Saved data from older versions may still hold account-wide
-- [specID] keys; those of this character's class are moved in (Gear_MigrateHinted).
local function CharHinted()
	local guid = UnitGUID("player")
	if not DB().hinted[guid] then
		local own = {}
		for i = 1, C_SpecializationInfo.GetNumSpecializationsForClassID(classID) or 0 do
			local spec = SpecAt(i)
			if spec then
				own[spec.id] = true
			end
		end
		ns.Gear_MigrateHinted(DB().hinted, guid, own)
	end
	return DB().hinted[guid]
end

-- The max level of the content expansion of level (nil: this character's).
local function MaxLevel(level)
	return ns.ContentMaxLevel(ns.ContentExpansion(level))
end

-- level: PLAYER_LEVEL_UP's new level (UnitLevel can lag behind it).
local function WeightsHint(level)
	if not ns.gearModule.active then
		return
	end
	local ctx = Context()
	if not ctx then
		return
	end
	local name = ctx.spec.name
	if ctx.source == "none" then
		if not noWeightsSaid[ctx.spec.id] then
			noWeightsSaid[ctx.spec.id] = true
			ns.Print(("Gear Check: no stat weights for %s, so item level decides. For better verdicts, sim stat "
				.. "weights on Raidbots and /tomte gear import."):format(name))
		end
		return
	end
	local hinted = CharHinted()
	level = level or UnitLevel("player")
	local kind, seen = ns.Gear_WeightsHint(ctx.source, ctx.scales, hinted[ctx.spec.id], CurrentSeason(), level,
		MaxLevel(level))
	if kind == "max" then
		ns.Print(("%s is max level: sim %s on Raidbots for weights that fit your gear, then /tomte gear import.")
			:format(UnitName("player"), name))
	elseif kind == "stale" then
		ns.Print(("Gear Check: the built-in weights for %s are from %s and may be out of date. Sim on Raidbots "
			.. "and /tomte gear import."):format(name, ctx.scales.seasonName))
	end
	if kind then
		hinted[ctx.spec.id] = seen
	end
end

local lastAudit

local function AuditHint()
	if not (ns.gearModule.active and DB().enchantHints) then
		return
	end
	local equipped = ns.GearItems_Equipped()
	if not equipped then
		return
	end
	local text = ns.Gear_AuditText(ns.Gear_Audit(equipped))
	if text and text ~= lastAudit then
		ns.Print("Gear Check: " .. text .. ". Hover the item for details.")
	end
	lastAudit = text
end

ns.GearHints_Weights = WeightsHint
ns.GearHints_Audit = AuditHint
ns.GearHints_MaxLevel = MaxLevel
