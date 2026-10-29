local addonName, ns = ...

-- Loot: reads the open loot window into plain entries for Data.lua, the window (Window.lua) and the feed (Feed.lua),
-- one per slot (the shape is listed at the top of Data.lua). The extras (owned count, new appearance, Gear Check's
-- verdict, Gold & value's price) are read only while their switch is on. Values a 12.x client keeps secret are
-- skipped. Gear Check and Gold & value are asked through their ns.Gear_* / ns.Value_* functions, looked up at call
-- time: either may be off or missing.

local FISHING_SPELL = 131474 -- the Fishing spell, for the window's title (as Modules/Fishing names it)
-- The units that can be the corpse or object being looted, for the source's name.
local SOURCE_UNITS = { "target", "mouseover", "softinteract" }
-- Gear Check's headline color keys (Rules.lua) to theme roles, as its reward card maps them.
local VERDICT_ROLES = { green = "success", yellow = "warning", grey = "textMuted", red = "danger", orange = "warning" }

local Readable = ns.Readable
local IsGear = ns.Loot_IsGear

-- Extras -----------------------------------------------------------------------------------------------------------

-- An appearance you haven't collected from any source, and can collect on this character.
local function NewLook(link)
	return ns.NewAppearance(link) == "you"
end

local function Verdict(link, ctx)
	local verdictOf = ns.Gear_Verdict
	if not (ctx and verdictOf) then
		return nil
	end
	local v, headline, color = verdictOf(link, ctx)
	if not v then
		return nil
	end
	local clean, maybe = ns.Gear_IsCleanUpgrade, ns.Gear_IsMaybeUpgrade
	return {
		text = headline,
		role = VERDICT_ROLES[color] or "textMuted",
		upgrade = clean ~= nil and clean(v) or false,
		maybe = maybe ~= nil and maybe(v) or false,
	}
end

-- Gold & value's price for one: copper and whether it's stale; nil while that module is off.
local function Price(link)
	local priceOf = ns.Value_ItemPrice
	if not priceOf then
		return nil
	end
	local copper, _, stale = priceOf(link)
	return copper, stale
end

-- How many of an item you own: bags, bank, reagent bank and warband bank.
function ns.Loot_Owned(itemID)
	return C_Item.GetItemCount(itemID, true, false, true, true)
end

-- The item fields and the extras that are switched on (opts from Loot_ReadOptions).
local function ItemExtras(e, opts)
	local itemID, _, _, _, _, classID, subclassID = C_Item.GetItemInfoInstant(e.link)
	if not itemID then
		return
	end
	e.itemID, e.classID, e.subclassID = itemID, classID, subclassID
	local name, _, quality, _, _, _, subType, _, _, icon, sell = C_Item.GetItemInfo(e.link)
	e.name = e.name or name
	e.quality = e.quality or quality or C_Item.GetItemQualityByID(e.link) -- known before the full item data
	e.icon = e.icon or icon
	e.sell = sell
	e.subType = subType
	e.toy = C_ToyBox.GetToyInfo(itemID) ~= nil
	if opts.owned then
		e.owned = ns.Loot_Owned(itemID) -- read as the loot opens: the feed reads it again once it's in the bags
	end
	if opts.newLook and IsGear(e) then
		e.newLook = NewLook(e.link)
	end
	if opts.verdict and IsGear(e) then
		e.verdict = Verdict(e.link, opts.ctx)
	end
	if opts.value then
		e.value, e.stale = Price(e.link)
	end
end

-- What to read, from the module's extras. Gear Check's context is made once per read (it judges every item).
function ns.Loot_ReadOptions(db)
	local x = db.extras
	local context = x.verdict and ns.Gear_Context
	return {
		owned = x.owned,
		newLook = x.newLook,
		verdict = x.verdict,
		value = x.value,
		ctx = context and context() or nil,
	}
end

-- Slots ------------------------------------------------------------------------------------------------------------

function ns.Loot_ReadSlot(slot, opts)
	local slotType = GetLootSlotType(slot)
	local icon, name, quantity, currencyID, quality, locked, isQuestItem, questID, isActive, isCoin =
		GetLootSlotInfo(slot)
	if not Readable(slotType, icon, name, quantity, currencyID, quality, locked, isQuestItem, questID, isActive,
		isCoin) then
		return { slot = slot, kind = "none" }
	end
	local e = { slot = slot, icon = icon, name = name, quantity = quantity, quality = quality, locked = locked == true }
	if isCoin or slotType == Enum.LootSlotType.Money then
		e.kind = "money"
		e.name = name and (name:gsub("\n", " ")) -- one line per coin type in the game's text
	elseif slotType == Enum.LootSlotType.Currency or currencyID then
		e.kind, e.currencyID = "currency", currencyID
		-- Currencies that come as containers (a pile of a currency) show the container, as the game's window does.
		if currencyID and CurrencyContainerUtil then
			e.name, e.icon, e.quantity, e.quality = CurrencyContainerUtil.GetCurrencyContainerInfo(currencyID,
				quantity, name, icon, quality)
		end
	elseif slotType == Enum.LootSlotType.Item then
		e.kind = "item"
	else
		e.kind = "none"
		return e
	end
	-- As the game's window marks them: a quest you're not on yet, or an item a quest of yours needs.
	if questID and not isActive then
		e.quest = "starts"
	elseif questID or isQuestItem then
		e.quest = "item"
	end
	local link = GetLootSlotLink(slot)
	if Readable(link) and type(link) == "string" then
		e.link = link
		if e.kind == "item" then
			ItemExtras(e, opts)
		end
	end
	return e
end

function ns.Loot_ReadAll(opts)
	local entries = {}
	local n = GetNumLootItems()
	if not (Readable(n) and type(n) == "number") then
		return entries
	end
	for slot = 1, n do
		entries[slot] = ns.Loot_ReadSlot(slot, opts)
	end
	return entries
end

-- An item that arrived without a loot window (a loot pop-up, a roll won, boss loot), as an entry for the feed.
function ns.Loot_ReadLink(link, quantity, opts)
	local e = { slot = 0, kind = "item", link = link, quantity = quantity, taken = true }
	ItemExtras(e, opts)
	return e
end

-- A currency from its link (loot pop-ups) or ID (currency gains), as an entry for the feed.
function ns.Loot_ReadCurrency(currencyID, link, quantity)
	local info
	if link then
		info = C_CurrencyInfo.GetCurrencyInfoFromLink(link)
		currencyID = currencyID or C_CurrencyInfo.GetCurrencyIDFromLink(link)
	elseif currencyID then
		info = C_CurrencyInfo.GetCurrencyInfo(currencyID)
	end
	if not ns.Loot_IsShownCurrency(info) then
		return nil
	end
	return { slot = 0, kind = "currency", currencyID = currencyID, name = info.name, icon = info.iconFileID,
		quality = info.quality, quantity = quantity, link = link, taken = true }
end

-- Where the loot came from ------------------------------------------------------------------------------------------

-- The window's title: the corpse's or object's name when it's your target or under the mouse, the number of corpses
-- for area loot, Fishing, or "Loot".
function ns.Loot_ReadSource()
	local guids, sources = {}, 0
	local n = GetNumLootItems()
	for slot = 1, (Readable(n) and n or 0) do
		local values = { GetLootSourceInfo(slot) }
		for i = 1, #values, 2 do
			local guid = values[i]
			if Readable(guid) and type(guid) == "string" and not guids[guid] then
				guids[guid] = true
				sources = sources + 1
			end
		end
	end
	local names = {}
	for _, unit in ipairs(SOURCE_UNITS) do
		local guid = UnitGUID(unit)
		if guid and Readable(guid) and guids[guid] then
			local name = UnitName(unit)
			if name and Readable(name) then
				names[1] = name
				break
			end
		end
	end
	return ns.Loot_SourceTitle({
		fishing = IsFishingLoot() == true,
		fishingName = C_Spell.GetSpellName(FISHING_SPELL),
		names = names,
		sources = sources,
	})
end
