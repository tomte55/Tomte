local addonName, ns = ...

-- Gear Check, part 1: the evaluator contexts (this character's, its other specs', other characters') and the
-- cached verdict helpers. Tooltip lines are in Tooltip.lua, chat hints in Hints.lua, Baganator in Baganator.lua,
-- weights import and commands in Weights.lua; the module, events and registration are in Gear.lua.

local GetSpecialization = C_SpecializationInfo.GetSpecialization
local GetSpecializationInfo = C_SpecializationInfo.GetSpecializationInfo

local function DB()
	return ns.gearDB
end

local PRIMARY_KEYS = { [1] = "STR", [2] = "AGI", [4] = "INT" } -- LE_UNIT_STAT_*
ns.GEAR_PRIMARY_KEYS = PRIMARY_KEYS

local _, classToken, classID = UnitClass("player")

local function SpecAt(index)
	local specID, name, _, icon, _, primaryStat = GetSpecializationInfo(index)
	if not specID or specID == 0 then
		return nil
	end
	return { index = index, id = specID, name = name, icon = icon, primary = PRIMARY_KEYS[primaryStat] }
end

local function Spec()
	local index = GetSpecialization()
	return index and SpecAt(index)
end

-- Display season ID, nil when the game doesn't say (0 between seasons) or the client has no such API (guarded, so
-- that's nil rather than an error).
local function CurrentSeason()
	local id = C_SeasonInfo and C_SeasonInfo.GetCurrentDisplaySeasonID and C_SeasonInfo.GetCurrentDisplaySeasonID()
	return (id and id > 0) and id or nil
end

-- Below the account's level cap (not the content expansion's: a Midnight owner's 80 still levels), where a higher
-- item level wins whatever the stats (Gear_Evaluate's ctx.leveling).
local function Leveling(level)
	level = level or UnitLevel("player")
	if not level or ns.IsSecret(level) then
		return false
	end
	return level < GetMaxLevelForPlayerExpansion()
end

-- The evaluator context for a spec ({ id, name, primary }, index only for this character's own specs). guid, class
-- and level default to this character; another character's guid, class token and level judge for them (their
-- imported weights, their armor type, their content expansion's built-in set). ctx.scales is that set;
-- ctx.complete once the best gem is known (or the set has no gems).
local function ContextFor(spec, guid, class, level)
	if not (spec and spec.id and spec.primary) then
		return nil
	end
	local set = ns.Gear_ScalesForLevel(level)
	local ctx = ns.Gear_BuildContext(spec, guid or UnitGUID("player"), class or classToken, DB().weights, set,
		ns.GearItems_Gems(set.gems))
	if ctx then
		ctx.scales = set
		ctx.complete = ctx.best ~= nil or #set.gems == 0
		ctx.leveling = DB().levelingIlvl and Leveling(level)
	end
	return ctx
end

-- This character's context, kept until InvalidateVerdicts (spec, level, weights, items arrived): Baganator and
-- tooltips ask for one per item. Not kept while the gems load (no best gem yet), like Alts.lua does.
local ownCtx
local function Context()
	local spec = Spec()
	if ownCtx and spec and ownCtx.spec.id == spec.id and ownCtx.scales == ns.Gear_ScalesForLevel() then
		return ownCtx
	end
	local ctx = ContextFor(spec)
	ownCtx = ctx and ctx.complete and ctx or nil
	return ctx
end

-- This character's context for another of its specs (tooltip rank and off-spec lines), kept like ownCtx.
local specCtx = {} -- [specID] = ctx
local function SpecContext(spec)
	local held = spec and specCtx[spec.id]
	if held and held.scales == ns.Gear_ScalesForLevel() then
		return held
	end
	local ctx = ContextFor(spec)
	if ctx and ctx.complete then
		specCtx[spec.id] = ctx
	end
	return ctx
end

-- The class's other specs, for off-spec verdicts.
local function OtherSpecs(current)
	local list = {}
	for i = 1, C_SpecializationInfo.GetNumSpecializationsForClassID(classID) or 0 do
		if i ~= current.index then
			list[#list + 1] = SpecAt(i)
		end
	end
	return list
end

-- Whether a link is gear with a slot to judge, from GetItemInfoInstant alone (no item data or tooltip read).
local function IsGearLink(link)
	local equipLoc = select(4, C_Item.GetItemInfoInstant(link))
	return equipLoc and ns.Gear_Slots(equipLoc)
end

-- verdict (nil when worn), candidate descriptor, equipped snapshot. Nothing while items load.
local function Evaluate(link, ctx)
	ctx = ctx or Context()
	local equipped = ctx and ns.GearItems_Equipped()
	local cand = equipped and ns.GearItems_Describe(link)
	if not cand then
		return nil
	end
	ctx.specOK = cand.specs == nil or cand.specs[ctx.spec.id] == true
	local verdict = ns.Gear_Evaluate(cand, equipped, ctx)
	ctx.specOK = nil -- the context is shared: don't let this item's answer reach the next one
	return verdict, cand, equipped
end

-- Drops the cached contexts (ownCtx, specCtx) and has Baganator ask for every item's arrows again.
local function InvalidateVerdicts()
	ownCtx = nil
	wipe(specCtx)
	if Baganator and Baganator.API and Baganator.API.RequestItemButtonsRefresh then
		Baganator.API.RequestItemButtonsRefresh()
	end
end

-- Another character's context from Alts' stored snapshot (chars[guid]: specID, spec, primary, class token); nil
-- until their spec has been read. Their level picks their built-in set (content expansion); whether they can wear an
-- item is Gear_AltVerdict's.
function ns.Gear_ContextForChar(char)
	return ContextFor(ns.Gear_CharSpec(char), char.guid, char.class, char.level)
end
ns.Gear_EvaluateLink = Evaluate
ns.Gear_SpecAt = SpecAt
ns.Gear_CurrentSeason = CurrentSeason
ns.Gear_OwnContext = Context
ns.Gear_SpecContext = SpecContext
ns.Gear_OtherSpecs = OtherSpecs
ns.Gear_IsGearLink = IsGearLink
ns.Gear_InvalidateVerdicts = InvalidateVerdicts
