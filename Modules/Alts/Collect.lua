local addonName, ns = ...

-- Alts: reads the game into TomteDB.alts (layout in PlanData.lua). The character snapshot is refreshed on entering the
-- world and on level, spec, gear (the worn items too, for Gear Check), zone, gold, rest and profession events,
-- debounced to one read per second and never in combat. Recipes are read while this character's own profession
-- window is open (not a linked, guild or NPC one): every recipe of the expansion the window shows, in small batches
-- so the window doesn't hitch. The Warband bank's gold is read once per account. Each part is read on its own, so
-- one failing API leaves the others working.
-- APIs: Blizzard UI source 12.1.0 (69933) + warcraft.wiki.gg (docs/superpowers/specs/2026-10-05-tomte-alts-design.md).

local DEBOUNCE = 1
local PROF_RETRIES = 5 -- reads again while the professions aren't loaded yet (ReadProfs), this many times
local GEAR_SLOTS = { 1, 2, 3, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17 } -- worn gear without shirt (4) and tabard
local PRIMARY_KEYS = { [1] = "STR", [2] = "AGI", [4] = "INT" } -- LE_UNIT_STAT_*, GetSpecializationInfo's primaryStat
local BATCH = 30 -- recipes read per frame
local RESCAN_AFTER = 30 -- seconds before the same profession is read again (the list event also fires on filters)
local RECIPE_VERSION = 4 -- bump to re-read stored recipes (2: category and expansion name, 3: gear output links,
-- 4: output links at every quality and the number of qualities; CraftGear.lua checks for 4)

local db, guid
local pending
local scan -- { ids, i, prof, ticker }
local lastScan = {} -- [expansion skill line] = GetTime() of the last finished scan

-- One bus for the module's files (CraftMats, Send and List attach to it); this file loads first.
local events = ns.NewEvents()
ns.Alts_Events = events

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

-- Worn profession gear (tool and accessories, slots 20-30; Blizzard_ProfessionsCrafting.xml), for the Profession
-- gear tab. Read only once the worn gear has (at login neither has arrived yet), and not while a link is missing.
local PROF_SLOTS = { 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30 }
local function ReadProfGear(c)
	if not c.gear then
		return
	end
	local gear = {}
	for _, slot in ipairs(PROF_SLOTS) do
		local link = GetInventoryItemLink("player", slot)
		if not link and GetInventoryItemID("player", slot) then
			return
		end
		gear[slot] = link
	end
	local old, same = c.profGear, c.profGear ~= nil
	for _, slot in ipairs(PROF_SLOTS) do
		same = same and old[slot] == gear[slot]
	end
	if not same then
		c.profGear = gear
		c.profGearAt = GetServerTime()
	end
end

-- Rested XP matters until the account's level cap (not the content expansion's: a Midnight owner's 80 still levels).
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

-- The skill line of a profession for the character's content expansion (Core/Content.lua), from Weekly's data.
-- Professions aren't tied to level: a low-level alt (no data for its level band) gets the newest expansion the
-- account owns that has data.
local function ExpansionLine(base)
	local def = ns.Weekly_ProfDef(ns.ContentExpansion(), base)
	if not def then
		local owned = GetExpansionLevel()
		local expansions = ns.Content_Expansions()
		for i = #expansions, 1, -1 do
			if expansions[i] <= owned then
				def = ns.Weekly_ProfDef(expansions[i], base)
				if def then
					break
				end
			end
		end
	end
	return def and def.child
end

-- The skill in each expansion's line Content has data for (recipe items need "Midnight Leatherworking (50)", not
-- the profession's overall skill). A line the game doesn't answer for keeps its last reading.
local function ReadTiers(base, before)
	local tiers = {}
	for line, level in pairs(before or {}) do
		tiers[line] = level
	end
	for _, expansion in ipairs(ns.Content_Expansions()) do
		local def = ns.Weekly_ProfDef(expansion, base)
		if def and def.child then
			local ok, info = pcall(C_TradeSkillUI.GetProfessionInfoBySkillLineID, def.child)
			local level = ok and type(info) == "table" and info.skillLevel or nil
			if ns.Readable(level) and type(level) == "number" and level > 0 then
				tiers[def.child] = level
			end
		end
	end
	return tiers
end

local function ReadUnspent(line)
	if not (line and C_ProfSpecs.SkillLineHasSpecialization(line)) then
		return nil
	end
	local info = C_ProfSpecs.GetCurrencyInfoForSkillLine(line)
	return info and info.numAvailable or nil
end

-- Professions keyed by their base skill line; known recipes and the last knowledge reading carry over. line is the
-- character's content expansion's skill line, worked out each time (not the one a recipe read last browsed), and
-- unspent knowledge is that line's: an older reading only carries over when it was of the same line.
local function ReadProfs(c)
	local old = c.profs or {}
	local profs = {}
	-- Every profession: the two main ones, then archaeology, fishing and cooking (only cooking has recipes).
	local first, second, archaeology, fishing, cooking = GetProfessions()
	-- Right after login the game can answer with no professions, or with professions it can't describe yet. Reading
	-- that would drop every known recipe (the crafting list then said nobody knows them until the profession window
	-- was opened, measured in game): keep what was read before until the answer is complete.
	if not (first or second or archaeology or fishing or cooking) and next(old) then
		return false
	end
	for _, index in pairs({ first, second, archaeology, fishing, cooking }) do
		if not select(7, GetProfessionInfo(index)) then
			return false
		end
	end
	for _, index in pairs({ first, second, archaeology, fishing, cooking }) do
		local name, icon, skill, maxSkill, _, _, base = GetProfessionInfo(index)
		if base then
			local before = old[base] or {}
			local line = ExpansionLine(base)
			local unspent = ReadUnspent(line)
			if unspent == nil and before.line == line then
				unspent = before.unspent
			end
			profs[base] = {
				name = name, icon = icon, base = base, line = line, skill = skill, max = maxSkill,
				unspent = unspent, known = before.known or {}, scannedAt = before.scannedAt,
				tiers = ReadTiers(base, before.tiers),
				secondary = (index ~= first and index ~= second) or nil,
			}
		end
	end
	c.profs = profs
	return true
end

-- The professions read, as one string: a change (learned, unlearned, or read for the first time) redraws the
-- crafting list, whose plans need to know who crafts what.
local function ProfsKey(c)
	local bases = {}
	for base, p in pairs(c.profs or {}) do
		bases[#bases + 1] = base .. ":" .. (p.known and next(p.known) and "k" or "")
	end
	table.sort(bases)
	return table.concat(bases, ",")
end

local profRetries = 0

local function Refresh()
	pending = false
	if not db then
		return
	end
	if InCombatLockdown() then
		events:Watch("collect", "PLAYER_REGEN_ENABLED")
		return
	end
	local c = Me()
	Try(ReadBasics, c)
	Try(ReadSpec, c)
	Try(ReadGear, c)
	Try(ReadProfGear, c)
	Try(ReadRest, c)
	local profsBefore = ProfsKey(c)
	local ok, read = Try(ReadProfs, c)
	if ok and read == false and profRetries < PROF_RETRIES then
		profRetries = profRetries + 1
		C_Timer.After(DEBOUNCE, ns.AltsCollect_Request)
	end
	if ProfsKey(c) ~= profsBefore and ns.AltsList_Changed then
		ns.AltsList_Changed()
	end
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

-- Gear and profession tools: the output's link at every crafting quality, lowest first, without optional reagents
-- (what Customer Orders shows: Blizzard_ProfessionsTemplates.lua, GetRecipeOutputItemData(spellID, {}, nil,
-- qualityID)). For the Crafting tab's item levels; nil for things that aren't worn.
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
		local all, complete = {}, true
		for i, qualityID in ipairs(q) do
			all[i] = Link(qualityID)
			complete = complete and all[i] ~= nil
		end
		local lo, hi = all[1], all[#q]
		if not (lo and hi) then
			return nil
		end
		-- A middle quality that didn't answer costs only the exact item levels, not the range.
		return { lo, hi }, complete and #q > 1 and all or nil
	end
	local link = Link(nil)
	return link and { link, link } or nil
end

-- out = { lowest, highest } and outQ = every quality's link (PlanData.lua). An error there costs only the item levels,
-- not the recipe.
local function OutputLinks(...)
	local ok, out, outQ = pcall(ReadOutputLinks, ...)
	if not (ok and type(out) == "table") then
		return nil, nil
	end
	return out, outQ
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
	local out, outQ = OutputLinks(id, info, schematic.outputItemID)
	db.recipes[id] = {
		v = RECIPE_VERSION, name = info.name, icon = info.icon, base = prof.base, line = scan.line,
		lineName = scan.lineName, category = category and category.name or nil,
		item = schematic.outputItemID, qMin = schematic.quantityMin, qMax = schematic.quantityMax,
		reagents = ReadReagents(schematic),
		out = out, outQ = outQ, nq = info.qualityIDs and #info.qualityIDs > 1 and #info.qualityIDs or nil,
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
			-- Knowledge only from the character's own expansion (the window may show an older one).
			if prof.line and scan.line == prof.line then
				prof.unspent = ReadUnspent(scan.line) or prof.unspent
			end
		end
		lastScan[scan.line] = GetTime()
		-- The window re-reads every RESCAN_AFTER while open: only say so (and redraw) when it found something, on
		-- the first read or when asked to.
		local tell = scan.updated > 0 or scan.force or scan.first
		if tell then
			ns.Print(("Alts: read %d recipes from %s (%d new or updated)."):format(#scan.ids,
				scan.lineName or "this profession", scan.updated))
		end
		StopScan()
		if tell then
			ns.Alts_RecipesChanged()
		end
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
		return ("read less than %d seconds ago"):format(RESCAN_AFTER)
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
	scan = { ids = ids, i = 1, prof = prof, line = line, lineName = child and child.professionName or nil, updated = 0,
		force = force, first = not lastScan[line] }
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

-- Item counts (Tomte's own record) is on: every character's items are counted.
local function TomteCounts()
	return ns.Counts_Active ~= nil and ns.Counts_Active()
end

-- Items on every character are counted (Item counts, or else Syndicator); false: this character and the Warband
-- bank only.
function ns.Alts_HasSyndicator()
	return TomteCounts() or SyndicatorAPI() ~= nil
end

-- How many of these items (quality ranks of one reagent) the account has, and where: total, { { name, n, class } }
-- sorted most first. From Item counts, else Syndicator; without either: this character's bags, bank, reagents and
-- Warband bank.
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
	if TomteCounts() then
		-- Other characters from the record; this one and the Warband bank live from the game (the record has the bank
		-- only once it was opened with Item counts on). Worn gear isn't material.
		local me = UnitGUID("player")
		for _, itemID in ipairs(items) do
			for _, w in ipairs(ns.Counts_Where(ns.Counts_Entry(itemID))) do
				if w.guid and w.guid ~= me and w.where ~= "equipped" then
					local name = ns.Counts_CharName(w.guid) or "?"
					local char = ns.altsDB and ns.altsDB.chars[w.guid]
					Add(name, w.n, char and char.class)
				end
			end
			local mine = C_Item.GetItemCount(itemID, true, false, true, false)
			local all = C_Item.GetItemCount(itemID, true, false, true, true)
			Add(UnitName("player"), mine, select(2, UnitClass("player")))
			Add("Warband bank", (all or 0) - (mine or 0))
		end
	elseif api then
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
	if not ok or type(money) ~= "number" or ns.IsSecret(money) then
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
	events:On("collect", event, ns.AltsCollect_Request)
end

events:On("collect", "PLAYER_ENTERING_WORLD", function()
	ns.AltsCollect_Request()
	ReadWarband(false)
end)

events:On("collect", "ACCOUNT_MONEY", function()
	ReadWarband(true)
end)

events:On("collect", "BANKFRAME_OPENED", function()
	ReadWarband(true)
end)

events:On("collect", "BANKFRAME_CLOSED", function()
	ReadWarband(true)
end)

-- UnitLevel can still be the old level here.
events:On("collect", "PLAYER_LEVEL_UP", function(_, level)
	if db then
		Me().levelUp = level
	end
	ns.AltsCollect_Request()
end)

events:On("collect", "TRADE_SKILL_LIST_UPDATE", function()
	StartScan()
end)

events:On("collect", "TRADE_SKILL_CLOSE", function()
	StopScan()
	ns.AltsCollect_Request() -- knowledge points may have been spent
end)

events:On("collect", "NEW_RECIPE_LEARNED", function(_, recipeID)
	local recipe = db and db.recipes[recipeID]
	local prof = recipe and Me().profs[recipe.base]
	if prof then
		prof.known[recipeID] = true
		ns.Alts_RecipesChanged()
	end
end)

events:On("collect", "PLAYER_REGEN_ENABLED", function(self)
	self:Unwatch("collect", "PLAYER_REGEN_ENABLED")
	ns.AltsCollect_Request()
end)

-- Last played. Gold isn't read here: GetMoney() already says 0 during logout (seen 2026-10-05); the value from the
-- last PLAYER_MONEY read stands.
events:On("collect", "PLAYER_LOGOUT", function()
	local c = db and guid and db.chars[guid]
	if c then
		c.seen = GetServerTime()
	end
end)

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
		events:Watch("collect", event)
	end
	for _, event in ipairs({ "PLAYER_ENTERING_WORLD", "PLAYER_LEVEL_UP", "TRADE_SKILL_LIST_UPDATE", "TRADE_SKILL_CLOSE",
		"NEW_RECIPE_LEARNED", "PLAYER_LOGOUT", "ACCOUNT_MONEY", "BANKFRAME_OPENED", "BANKFRAME_CLOSED" }) do
		events:Watch("collect", event)
	end
	if ns.inWorld then
		ns.AltsCollect_Request()
		ReadWarband(false)
	end
end

function ns.AltsCollect_Stop()
	events:UnwatchAll("collect")
	StopScan()
	db = nil
end
