local addonName, ns = ...

-- Alts: reads the game into TomteDB.alts (layout in Data.lua). The character snapshot is refreshed on entering the
-- world and on level, spec, gear (the worn items too, for Gear Check), zone, gold, rest and profession events,
-- debounced to one read per second and never in combat. Recipes are read while this character's own profession window is open (not a linked, guild or
-- NPC one): every recipe of the player's expansion for that profession, in small batches so the window doesn't
-- hitch. The Warband bank's gold is read once per account. Each part is read on its own, so one failing API leaves
-- the others working.
-- APIs: Blizzard UI source 12.1.0 (69933) + warcraft.wiki.gg, see the Alts spec.

local DEBOUNCE = 1
local GEAR_SLOTS = { 1, 2, 3, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17 } -- worn gear without shirt (4) and tabard
local PRIMARY_KEYS = { [1] = "STR", [2] = "AGI", [4] = "INT" } -- LE_UNIT_STAT_*, GetSpecializationInfo's primaryStat
local BATCH = 30 -- recipes read per frame
local RESCAN_AFTER = 30 -- seconds before the same profession is read again (the list event also fires on filters)
local RECIPE_VERSION = 3 -- bump to re-read stored recipes (2: category and expansion name, 3: gear output links)

local db, guid
local pending
local scan -- { ids, i, prof, ticker }
local lastScan = {} -- [expansion skill line] = GetTime() of the last finished scan

local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(self, event, ...)
	self[event](self, ...)
end)

local function Try(reader, ...)
	return xpcall(reader, function(err)
		return ns.errorHandler(err)
	end, ...)
end

local function Me()
	guid = guid or UnitGUID("player")
	local c = db.chars[guid]
	if not c then
		c = { guid = guid, profs = {} }
		db.chars[guid] = c
	end
	return c
end

-- Character -----------------------------------------------------------------------------------------------

local function ReadBasics(c)
	c.name = UnitName("player")
	c.realm = GetNormalizedRealmName()
	c.class = select(2, UnitClass("player"))
	c.race = UnitRace("player")
	c.level = c.levelUp or UnitLevel("player")
	c.levelUp = nil
	c.money = GetMoney()
	c.zone = GetZoneText()
	c.seen = GetServerTime()
end

local function ReadSpec(c)
	local index = C_SpecializationInfo.GetSpecialization()
	if index and index > 0 then
		local specID, name, _, _, _, primaryStat = C_SpecializationInfo.GetSpecializationInfo(index)
		c.spec = name
		if specID and specID > 0 then
			c.specID = specID
			c.primary = PRIMARY_KEYS[primaryStat]
		end
	end
	local _, equipped = GetAverageItemLevel()
	if equipped and equipped > 0 then
		c.ilvl = math.floor(equipped)
	end
end

-- Worn gear for Gear Check's upgrades for alts (links work on any character). Not stored while a worn item's link
-- hasn't arrived, or nothing at all is worn (a read at login before the inventory has); gearAt changes only when
-- the gear does (Gear Check's cache for the character goes with it).
local function ReadGear(c)
	local gear, any = {}, false
	for _, slot in ipairs(GEAR_SLOTS) do
		local link = GetInventoryItemLink("player", slot)
		if not link and GetInventoryItemID("player", slot) then
			return
		end
		gear[slot] = link
		any = any or link ~= nil
	end
	if not any then
		return
	end
	local old, same = c.gear, c.gear ~= nil
	for _, slot in ipairs(GEAR_SLOTS) do
		same = same and old[slot] == gear[slot]
	end
	if not same then
		c.gear = gear
		c.gearAt = GetServerTime()
	end
end

local function ReadRest(c)
	local maxLevel = GetMaxLevelForPlayerExpansion and GetMaxLevelForPlayerExpansion()
	if maxLevel and c.level and c.level >= maxLevel then
		c.rested = nil
		return
	end
	local xpMax = UnitXPMax("player")
	local rested = GetXPExhaustion() or 0
	c.rested = xpMax and xpMax > 0 and math.min(math.floor(rested / xpMax * 100 + 0.5), 150) or nil
end

-- The player's expansion skill line of a profession (War Within for War Within players), from the Weekly table.
local function ExpansionLine(base)
	local def = ns.Weekly_ProfDef(ns.Weekly_Expansion(GetExpansionLevel()), base)
	return def and def.child
end
ns.Alts_ExpansionLine = ExpansionLine

local function ReadUnspent(line)
	if not (line and C_ProfSpecs.SkillLineHasSpecialization(line)) then
		return nil
	end
	local info = C_ProfSpecs.GetCurrencyInfoForSkillLine(line)
	return info and info.numAvailable or nil
end

-- Professions keyed by their base skill line; known recipes and the last knowledge reading carry over.
local function ReadProfs(c)
	local old = c.profs or {}
	local profs = {}
	-- Every profession: the two main ones, then archaeology, fishing and cooking (only cooking has recipes).
	local first, second, archaeology, fishing, cooking = GetProfessions()
	for _, index in pairs({ first, second, archaeology, fishing, cooking }) do
		local name, icon, skill, maxSkill, _, _, base = GetProfessionInfo(index)
		if base then
			local before = old[base] or {}
			local line = before.line or ExpansionLine(base)
			local unspent = ReadUnspent(line)
			profs[base] = {
				name = name, icon = icon, base = base, line = line, skill = skill, max = maxSkill,
				unspent = unspent or before.unspent, known = before.known or {}, scannedAt = before.scannedAt,
				secondary = (index ~= first and index ~= second) or nil,
			}
		end
	end
	c.profs = profs
end

local function Refresh()
	pending = false
	if not db then
		return
	end
	if InCombatLockdown() then
		events:RegisterEvent("PLAYER_REGEN_ENABLED")
		return
	end
	local c = Me()
	Try(ReadBasics, c)
	Try(ReadSpec, c)
	Try(ReadGear, c)
	Try(ReadRest, c)
	Try(ReadProfs, c)
	ns.Alts_Changed()
end

function ns.AltsCollect_Request()
	if not db or pending then
		return
	end
	pending = true
	C_Timer.After(DEBOUNCE, Refresh)
end

-- Recipes -------------------------------------------------------------------------------------------------

-- This character's own profession window, with its recipe list ready.
local function LocalWindow()
	local ui = C_TradeSkillUI
	if not ui.IsTradeSkillReady() or (ui.IsDataSourceChanging and ui.IsDataSourceChanging()) then
		return false
	end
	if ui.IsTradeSkillLinked() or ui.IsTradeSkillGuild() or (ui.IsTradeSkillGuildMember and ui.IsTradeSkillGuildMember())
		or ui.IsNPCCrafting() or (ui.IsRuneforging and ui.IsRuneforging()) then
		return false
	end
	return true
end

-- Required basic reagents (quality ranks in one slot); optional, finishing and currency slots are left out.
local function ReadReagents(schematic)
	local reagents = {}
	for _, slot in ipairs(schematic.reagentSlotSchematics or {}) do
		if slot.required and slot.reagentType == Enum.CraftingReagentType.Basic
			and slot.dataSlotType ~= Enum.TradeskillSlotDataType.Currency then
			local items = {}
			for _, r in ipairs(slot.reagents or {}) do
				if r.itemID then
					items[#items + 1] = r.itemID
				end
			end
			if #items > 0 and (slot.quantityRequired or 0) > 0 then
				reagents[#reagents + 1] = { items = items, qty = slot.quantityRequired }
			end
		end
	end
	return reagents
end

-- Gear and profession tools: the output's link at the lowest and the highest crafting quality, without optional
-- reagents (what Customer Orders shows: Blizzard_ProfessionsTemplates.lua, GetRecipeOutputItemData(spellID, {},
-- nil, qualityID)). For the Crafting tab's item levels; nil for things that aren't worn.
local function ReadOutputLinks(id, info, itemID)
	local equipLoc = itemID and select(4, C_Item.GetItemInfoInstant(itemID))
	if not equipLoc or equipLoc == "" or equipLoc == "INVTYPE_NON_EQUIP_IGNORE" or not info.hasSingleItemOutput then
		return nil
	end
	local function Link(qualityID)
		local out = C_TradeSkillUI.GetRecipeOutputItemData(id, {}, nil, qualityID)
		return out and out.hyperlink
	end
	local q = info.qualityIDs
	if q and #q > 0 then
		local lo, hi = Link(q[1]), Link(q[#q])
		return lo and hi and { lo, hi } or nil
	end
	local link = Link(nil)
	return link and { link, link } or nil
end

-- An error there costs only the item levels, not the recipe.
local function OutputLinks(...)
	local ok, links = pcall(ReadOutputLinks, ...)
	return ok and type(links) == "table" and links or nil
end

local function ReadRecipe(id, prof)
	local info = C_TradeSkillUI.GetRecipeInfo(id)
	if not info or info.isDummyRecipe or info.isRecraft or info.isSalvageRecipe or info.isGatheringRecipe then
		return
	end
	prof.known[id] = info.learned or nil
	local stored = db.recipes[id]
	if stored and stored.v == RECIPE_VERSION then
		return
	end
	local schematic = C_TradeSkillUI.GetRecipeSchematic(id, false)
	if not schematic then
		return
	end
	scan.updated = scan.updated + 1
	local category = info.categoryID and C_TradeSkillUI.GetCategoryInfo(info.categoryID)
	db.recipes[id] = {
		v = RECIPE_VERSION, name = info.name, icon = info.icon, base = prof.base, line = scan.line,
		lineName = scan.lineName, category = category and category.name or nil,
		item = schematic.outputItemID, qMin = schematic.quantityMin, qMax = schematic.quantityMax,
		reagents = ReadReagents(schematic),
		out = OutputLinks(id, info, schematic.outputItemID),
	}
end

local function StopScan()
	if scan and scan.ticker then
		scan.ticker:Cancel()
	end
	scan = nil
end

local function StepScan()
	if not (scan and db) then
		StopScan()
		return
	end
	local stop = math.min(scan.i + BATCH - 1, #scan.ids)
	for i = scan.i, stop do
		Try(ReadRecipe, scan.ids[i], scan.prof)
	end
	scan.i = stop + 1
	if scan.i > #scan.ids then
		-- The snapshot may have replaced the profession table during the scan (known is shared, this isn't).
		local prof = Me().profs[scan.prof.base]
		if prof then
			prof.scannedAt = GetServerTime()
			prof.line = scan.line
			prof.unspent = ReadUnspent(scan.line) or prof.unspent
		end
		lastScan[scan.line] = GetTime()
		ns.Print(("Alts: read %d recipes from %s (%d new or updated)."):format(#scan.ids,
			scan.lineName or "this profession", scan.updated))
		StopScan()
		ns.Alts_RecipesChanged()
	end
end

-- Reads the recipes of the expansion the window shows (its dropdown: a levelling character may be on an older one;
-- switching it reads that one too). Returns why it didn't start, for /tomte alts scan.
local function StartScan(force)
	if not db then
		return "Alts is off"
	elseif not LocalWindow() then
		return "no profession window of your own is open (or it's still loading)"
	end
	local base = C_TradeSkillUI.GetBaseProfessionInfo()
	base = base and base.professionID
	local prof = base and Me().profs[base]
	if not prof then
		return ("this character's professions don't include skill line %s"):format(tostring(base))
	end
	local child = C_TradeSkillUI.GetChildProfessionInfo()
	local line = child and child.professionID and child.professionID > 0 and child.professionID or prof.line
	if not line then
		return "no expansion skill line"
	end
	if scan then
		if scan.line == line then
			return "already reading"
		end
		StopScan() -- the window switched to another expansion: read that one instead
	end
	if not force and lastScan[line] and GetTime() - lastScan[line] < RESCAN_AFTER then
		return "read less than 30 seconds ago"
	end
	local all = C_TradeSkillUI.GetAllRecipeIDs and C_TradeSkillUI.GetAllRecipeIDs()
	if not all or #all == 0 then
		all = C_TradeSkillUI.GetFilteredRecipeIDs() or {}
	end
	local ids = {}
	for _, id in ipairs(all) do
		if C_TradeSkillUI.IsRecipeInSkillLine(id, line) then
			ids[#ids + 1] = id
		end
	end
	if #ids == 0 then
		return ("none of the %d recipes belong to skill line %d"):format(#all, line)
	end
	scan = { ids = ids, i = 1, prof = prof, line = line, lineName = child and child.professionName or nil, updated = 0 }
	scan.ticker = C_Timer.NewTicker(0, StepScan)
	return nil, #ids, child and child.professionName
end

-- /tomte alts scan: read the open profession window now and say what happened.
function ns.AltsCollect_ScanNow()
	local reason, count, name = StartScan(true)
	if reason then
		ns.Print("Alts: can't read recipes: " .. reason .. ".")
	else
		ns.Print(("Alts: reading %d recipes of %s."):format(count, name or "this profession"))
	end
end

-- Counts ---------------------------------------------------------------------------------------------------

-- Syndicator's API table when it's loaded and ready (named so it doesn't hide the global Syndicator).
local function SyndicatorAPI()
	local api = _G.Syndicator and _G.Syndicator.API
	if api and api.GetInventoryInfoByItemID and api.IsReady and api.IsReady() then
		return api
	end
	return nil
end

function ns.Alts_HasSyndicator()
	return SyndicatorAPI() ~= nil
end

-- How many of these items (quality ranks of one reagent) the account has, and where: total, { { name, n, class } }
-- sorted most first. Without Syndicator: this character's bags, bank, reagents and Warband bank.
function ns.Alts_Have(items)
	local total, byWhere, classOf = 0, {}, {}
	local function Add(where, n, class)
		if n and n > 0 then
			total = total + n
			byWhere[where] = (byWhere[where] or 0) + n
			classOf[where] = class
		end
	end
	local api = SyndicatorAPI()
	if api then
		for _, itemID in ipairs(items) do
			local info = api.GetInventoryInfoByItemID(itemID, false, false)
			for _, c in ipairs(info and info.characters or {}) do
				Add(c.character, (c.bags or 0) + (c.bank or 0) + (c.mail or 0), c.className)
			end
			Add("Warband bank", info and info.warband and info.warband[1])
		end
	else
		for _, itemID in ipairs(items) do
			local mine = C_Item.GetItemCount(itemID, true, false, true, false)
			local all = C_Item.GetItemCount(itemID, true, false, true, true)
			Add(UnitName("player"), mine, select(2, UnitClass("player")))
			Add("Warband bank", (all or 0) - (mine or 0))
		end
	end
	local list = {}
	for where, n in pairs(byWhere) do
		list[#list + 1] = { name = where, n = n, class = classOf[where] }
	end
	table.sort(list, function(a, b)
		if a.n ~= b.n then
			return a.n > b.n
		end
		return a.name < b.name
	end)
	return total, list
end

-- Warband bank gold -----------------------------------------------------------------------------------------

-- Once per account: TomteDB.alts.warbandMoney (copper) and warbandAt (when read). Read like Syndicator does: only
-- while this client holds the account inventory lock (another logged-in client may be changing it). Blizzard's
-- own money frame reads it on ACCOUNT_MONEY (Blizzard_MoneyFrame, MoneyTypeInfo.ACCOUNT). On entering the world a
-- 0 isn't stored, as the bank data may not be there yet; ACCOUNT_MONEY and the bank frame store anything.
local function ReadWarband(keepZero)
	if not (db and C_Bank and C_Bank.FetchDepositedMoney and Enum.BankType and Enum.BankType.Account) then
		return
	end
	if C_PlayerInfo.HasAccountInventoryLock and not C_PlayerInfo.HasAccountInventoryLock() then
		return
	end
	local ok, money = pcall(C_Bank.FetchDepositedMoney, Enum.BankType.Account)
	if not ok or type(money) ~= "number" or (issecretvalue and issecretvalue(money)) then
		return
	end
	if money == 0 and not keepZero then
		return
	end
	local changed = db.warbandMoney ~= money
	db.warbandMoney, db.warbandAt = money, GetServerTime()
	if changed then
		ns.Alts_Changed()
	end
end

-- Events ---------------------------------------------------------------------------------------------------

local REFRESH_EVENTS = {
	"ACTIVE_PLAYER_SPECIALIZATION_CHANGED", "PLAYER_AVG_ITEM_LEVEL_UPDATE", "PLAYER_EQUIPMENT_CHANGED",
	"ZONE_CHANGED_NEW_AREA", "PLAYER_MONEY",
	"UPDATE_EXHAUSTION", "SKILL_LINES_CHANGED", "TRAIT_TREE_CURRENCY_INFO_UPDATED", "TRADE_SKILL_SHOW",
}
for _, event in ipairs(REFRESH_EVENTS) do
	events[event] = ns.AltsCollect_Request
end

function events:PLAYER_ENTERING_WORLD()
	ns.AltsCollect_Request()
	ReadWarband(false)
end

function events:ACCOUNT_MONEY()
	ReadWarband(true)
end

function events:BANKFRAME_OPENED()
	ReadWarband(true)
end

function events:BANKFRAME_CLOSED()
	ReadWarband(true)
end

-- UnitLevel can still be the old level here.
function events:PLAYER_LEVEL_UP(level)
	if db then
		Me().levelUp = level
	end
	ns.AltsCollect_Request()
end

function events:TRADE_SKILL_LIST_UPDATE()
	StartScan()
end

function events:TRADE_SKILL_CLOSE()
	StopScan()
	ns.AltsCollect_Request() -- knowledge points may have been spent
end

function events:NEW_RECIPE_LEARNED(recipeID)
	local recipe = db and db.recipes[recipeID]
	local prof = recipe and Me().profs[recipe.base]
	if prof then
		prof.known[recipeID] = true
		ns.Alts_RecipesChanged()
	end
end

function events:PLAYER_REGEN_ENABLED()
	self:UnregisterEvent("PLAYER_REGEN_ENABLED")
	ns.AltsCollect_Request()
end

-- Last played. Gold isn't read here: GetMoney() already says 0 during logout (seen 2026-10-05); the value from the
-- last PLAYER_MONEY read stands.
function events:PLAYER_LOGOUT()
	local c = db and guid and db.chars[guid]
	if c then
		c.seen = GetServerTime()
	end
end

-- The window's expansion dropdown only switches the skill line it shows (no recipe list event fires), so the
-- switch itself starts a read. A post-hook plus a timer: Blizzard's own call path isn't touched.
local hooked = false
local function HookSkillLineSwitch()
	if hooked then
		return
	end
	hooked = true
	hooksecurefunc(C_TradeSkillUI, "SetProfessionChildSkillLineID", function()
		C_Timer.After(0.3, function()
			if db then
				StartScan()
			end
		end)
	end)
end

function ns.AltsCollect_Start(moduleDB)
	db = moduleDB
	HookSkillLineSwitch()
	for _, event in ipairs(REFRESH_EVENTS) do
		events:RegisterEvent(event)
	end
	for _, event in ipairs({ "PLAYER_ENTERING_WORLD", "PLAYER_LEVEL_UP", "TRADE_SKILL_LIST_UPDATE", "TRADE_SKILL_CLOSE",
		"NEW_RECIPE_LEARNED", "PLAYER_LOGOUT", "ACCOUNT_MONEY", "BANKFRAME_OPENED", "BANKFRAME_CLOSED" }) do
		events:RegisterEvent(event)
	end
	if ns.inWorld then
		ns.AltsCollect_Request()
		ReadWarband(false)
	end
end

function ns.AltsCollect_Stop()
	events:UnregisterAllEvents()
	StopScan()
	db = nil
end
