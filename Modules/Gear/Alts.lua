local addonName, ns = ...

-- Gear Check, upgrades for alts: whether gear that can get to another character (warbound, or Bind on Equip and not
-- bound yet) is a clean upgrade for them, judged with what Alts stored when they were last played (worn gear, spec,
-- main stat, class, level) and their own weights. Verdicts are cached per item link and character; a character's
-- cache goes when its gear, spec or level change (a stamp), and all of them when weights or the setting change.
-- Used by the tooltip and the Baganator arrow (Gear.lua) and the mailbox and bank (Alts/Send.lua). Pure parts
-- (bind state, who counts, the verdict, the lines) in Advice.lua.

local MAX_VERDICTS = 500 -- per character, then the cache starts over

local perChar = {} -- [guid] = { stamp, ctx, equipped, verdicts = { [link] = verdict | false }, n }

local function Stamp(c)
	return ("%s:%s:%s"):format(tostring(c.gearAt), tostring(c.specID), tostring(c.level))
end

local function Entry(c)
	local stamp = Stamp(c)
	local e = perChar[c.guid]
	if not e or e.stamp ~= stamp then
		e = { stamp = stamp, verdicts = {}, n = 0 }
		perChar[c.guid] = e
	end
	return e
end

-- The character's worn gear as descriptors (cached per link by Items.lua), nil while one of them loads. Kept once
-- every item has read in full.
local function Equipped(c, e)
	if e.equipped then
		return e.equipped
	end
	local snapshot, complete = {}, true
	for slot, link in pairs(c.gear) do
		local desc = ns.GearItems_Describe(link)
		if not desc then
			return nil
		end
		snapshot[slot] = desc
		complete = complete and not desc.unread
	end
	if complete then
		e.equipped = snapshot
	end
	return snapshot
end

-- The verdict for c when it's a clean upgrade, false when it isn't (or c can't be judged), nil while something loads.
local function Verdict(c, link, cand, e)
	local cached = e.verdicts[link]
	if cached ~= nil then
		return cached
	end
	local ctx = e.ctx or ns.Gear_ContextForChar(c)
	if not ctx then
		return false
	end
	if ctx.best then
		e.ctx = ctx -- without a best gem the gems hadn't loaded yet: build it again next time
	end
	local equipped = Equipped(c, e)
	if not equipped then
		return nil
	end
	local v = ns.Gear_AltVerdict(cand, equipped, ctx, c.level)
	local result = ns.Gear_IsCleanUpgrade(v) and v or false
	if e.equipped and not cand.unread then
		if e.n >= MAX_VERDICTS then
			wipe(e.verdicts)
			e.n = 0
		end
		e.verdicts[link] = result
		e.n = e.n + 1
	end
	return result
end

-- Clean upgrades of link for other characters: { { guid, name, spec, verdict } } best first (Gear_SortAltUpgrades),
-- and whether some character couldn't be judged yet (items loading). Doesn't check whether the item can get to them:
-- GearAlts_Route does.
function ns.GearAlts_Upgrades(link)
	local db, alts = ns.gearDB, ns.altsDB
	-- Alts has to be on: it keeps the snapshots current (and Gear Check's setting says it needs it).
	if not (link and db and alts and alts.chars and ns.gearModule and ns.gearModule.active and ns.altsModule
		and ns.altsModule.active) or db.altUpgrades == "off" then
		return {}, false
	end
	local cand = ns.GearItems_Describe(link)
	if not cand then
		return {}, true
	end
	if not ns.Gear_Slots(cand.equipLoc) then
		return {}, false
	end
	local maxLevel = GetMaxLevelForPlayerExpansion and GetMaxLevelForPlayerExpansion()
	local list, loading = {}, false
	for _, c in ipairs(ns.Gear_AltsToJudge(alts.chars, UnitGUID("player"), GetServerTime(), db.altUpgrades, maxLevel)) do
		local v = Verdict(c, link, cand, Entry(c))
		if v == nil then
			loading = true
		elseif v then
			list[#list + 1] = { guid = c.guid, name = c.name, spec = c.spec, verdict = v }
		end
	end
	return ns.Gear_SortAltUpgrades(list), loading
end

-- "mail" | "warband" | nil: how the item gets to another character (Gear_TransferRoute). location, lines and bound
-- as for GearItems_BindState (any of them may be nil).
function ns.GearAlts_Route(link, location, lines, bound)
	if not link then
		return nil
	end
	return ns.Gear_TransferRoute(ns.GearItems_BindState(link, location, lines, bound))
end

-- Weights or the setting changed: judge everything again.
function ns.GearAlts_Invalidate()
	wipe(perChar)
end
