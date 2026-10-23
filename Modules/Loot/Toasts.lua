local addonName, ns = ...

-- Loot: the lines that don't come from a loot window, shown in the feed (Feed.lua) in every style.
--  * Replace loot pop-ups: Blizzard's alert frame stops listening to its loot toast events (boss loot, bonus rolls,
--    containers, rolls won) and the same loot shows as feed lines. Only events this file took are given back, on
--    Stop or when the switch goes off. Unregistering (rather than hooking or replacing Blizzard's functions) keeps
--    Blizzard's alert code untainted.
--  * Boss loot banner: Blizzard's banner keeps the kill part; its loot part is unchanged, left out while you're solo,
--    or replaced by feed lines for valuable items only. Same approach: BossBanner stops getting ENCOUNTER_LOOT_RECEIVED
--    while that's wanted. Re-sending the event to Blizzard's handler from here would run it tainted, and in 12.x
--    tainted code can't index a table with the event's (secret) names.
--  * Reputation and currency lines, an extra.
-- Also creates the module's event bus (ns.Loot_Events), shared with Loot.lua.

local OWNER = "toasts"
local TOAST_EVENTS = { "SHOW_LOOT_TOAST", "SHOW_LOOT_TOAST_UPGRADE", "LOOT_ITEM_ROLL_WON" }
local BANNER_EVENT = "ENCOUNTER_LOOT_RECEIVED"
local SAME_GAIN = 3 -- seconds in which a second report of the same item or currency is the same gain
local REP_ICON = 236681 -- achievement_reputation_01
local HONOR_ICON = 413584 -- achievement_guildperk_honorablemention
-- The game's "reputation increased" messages (GlobalStrings); missing ones are skipped.
local REP_STRINGS = { "FACTION_STANDING_INCREASED", "FACTION_STANDING_INCREASED_ACH_BONUS",
	"FACTION_STANDING_INCREASED_BONUS", "FACTION_STANDING_INCREASED_DOUBLE_BONUS",
	"FACTION_STANDING_INCREASED_ACCOUNT_WIDE", "FACTION_STANDING_INCREASED_GENERIC" }

local UI = ns.UI
local Readable = ns.Readable

local events = ns.NewEvents()
ns.Loot_Events = events

local db, module
local taken = {} -- [event] = true: toast events this file took from AlertFrame
local bannerTaken = false
-- [key] = GetTime() of the last line for it: "i:<itemID>", or "c:<currencyID>:<amount>" (a currency's pop-up and its
-- currency event are one gain; two different gains rarely share the amount).
local recent = {}
local repPatterns

-- Same gain twice --------------------------------------------------------------------------------------------------

local function ItemKey(link)
	local itemID = link and C_Item.GetItemInfoInstant(link)
	return itemID and ("i:" .. itemID) or nil
end

-- Loot.lua notes each item taken from a loot window, so a loot pop-up or boss loot line for it adds nothing.
function ns.LootToasts_Note(e)
	local key = e.link and ItemKey(e.link)
	if key then
		ns.Loot_RecentNote(recent, key, GetTime())
	end
end

local function Fresh(key)
	if not key then
		return true
	end
	local now = GetTime()
	if ns.Loot_RecentHas(recent, key, now, SAME_GAIN) then
		return false
	end
	ns.Loot_RecentNote(recent, key, now)
	return true
end

-- Lines ------------------------------------------------------------------------------------------------------------

local function ReadOptions()
	return ns.Loot_ReadOptions(db)
end

-- key: what makes it the same gain (default: the item).
local function PushItem(link, quantity, suffix, key)
	if not (Readable(link, quantity) and type(link) == "string") or not Fresh(key or ItemKey(link)) then
		return
	end
	ns.LootFeed_PushEntry(ns.Loot_ReadLink(link, quantity, ReadOptions()), suffix)
end

local function PushCurrency(currencyID, link, quantity)
	local e = ns.Loot_ReadCurrency(currencyID, link, quantity)
	if e and Fresh(e.currencyID and ("c:" .. e.currencyID .. ":" .. tostring(quantity))) then
		ns.LootFeed_PushEntry(e)
	end
end

-- Blizzard's AlertFrame handlers for these events (AlertFrames.lua), turned into feed lines.
events:On(OWNER, "SHOW_LOOT_TOAST", function(_, typeIdentifier, itemLink, quantity, _, _, isPersonal)
	if not Readable(typeIdentifier, itemLink, quantity, isPersonal) then
		return
	end
	if typeIdentifier == "item" then
		PushItem(itemLink, quantity)
	elseif typeIdentifier == "money" then
		ns.LootFeed_PushMoney(quantity)
	elseif typeIdentifier == "currency" and isPersonal then -- the game only toasts personal currency
		PushCurrency(nil, itemLink, quantity)
	elseif typeIdentifier == "honor" then
		ns.LootFeed_Push({ icon = HONOR_ICON, text = UI.Wrap("+" .. ns.Thousands(quantity), "success") .. " "
			.. (HONOR or "Honor"), role = "success" })
	end
end)

events:On(OWNER, "SHOW_LOOT_TOAST_UPGRADE", function(_, itemLink, quantity)
	PushItem(itemLink, quantity, UI.Wrap("Upgraded", "accent"))
end)

events:On(OWNER, "LOOT_ITEM_ROLL_WON", function(_, itemLink, quantity, _, roll)
	local suffix = Readable(roll) and type(roll) == "number" and UI.Wrap("Won (" .. roll .. ")", "success")
		or UI.Wrap("Won", "success")
	PushItem(itemLink, quantity, suffix)
end)

-- Valuable boss loot, where Blizzard's banner would show it: in dungeons and raids. Your own item also comes as a
-- loot toast (the first of the two shows); someone else's is its own gain, even when you got the same item.
local function PushValuable(itemID, itemLink, quantity, playerName, className)
	if not (module.active and db.banner == "valuable") then
		return
	end
	local _, _, _, _, _, classID, subclassID = C_Item.GetItemInfoInstant(itemID)
	local valuable = ns.Loot_IsValuable({
		classID = classID,
		subclassID = subclassID,
		quality = C_Item.GetItemQualityByID(itemID),
		toy = C_ToyBox.GetToyInfo(itemID) ~= nil,
	})
	if not valuable then
		return
	end
	local name = Readable(playerName, className) and type(playerName) == "string" and Ambiguate(playerName, "short")
	local mine = not name or name == UnitName("player")
	local key = ItemKey(itemLink)
	if not mine and key then
		key = key .. ":" .. name
	end
	PushItem(itemLink, quantity, name and UI.ClassColored(name, className) or nil, key)
end

events:On(OWNER, BANNER_EVENT, function(_, _, itemID, itemLink, quantity, playerName, className)
	local _, instanceType = GetInstanceInfo()
	if instanceType ~= "party" and instanceType ~= "raid" then
		return
	end
	if not (Readable(itemID, itemLink, quantity) and type(itemID) == "number" and type(itemLink) == "string") then
		return
	end
	-- The quality is only known once the item's data has loaded.
	local item = Item:CreateFromItemID(itemID)
	if item:IsItemEmpty() then
		return
	end
	item:ContinueOnItemLoad(function()
		PushValuable(itemID, itemLink, quantity, playerName, className)
	end)
end)

events:On(OWNER, "CHAT_MSG_COMBAT_FACTION_CHANGE", function(_, text)
	if not (Readable(text) and type(text) == "string") then
		return
	end
	if not repPatterns then
		local formats = {}
		for _, name in ipairs(REP_STRINGS) do
			formats[#formats + 1] = _G[name]
		end
		repPatterns = ns.Loot_RepPatterns(formats)
	end
	local faction, amount = ns.Loot_ParseRep(text, repPatterns)
	if not faction then
		return
	end
	local gain = amount and UI.Wrap("+" .. ns.Thousands(amount), "success") .. " " or ""
	ns.LootFeed_Push({ icon = REP_ICON, text = gain .. UI.Wrap(faction, "heading"), role = "success" })
end)

events:On(OWNER, "CURRENCY_DISPLAY_UPDATE", function(_, currencyID, _, change)
	if not (Readable(currencyID, change) and currencyID and type(change) == "number" and change > 0) then
		return
	end
	PushCurrency(currencyID, nil, change)
end)

-- Taking and giving back ------------------------------------------------------------------------------------------

local function TakeToasts(take)
	local alerts = _G.AlertFrame
	for _, event in ipairs(TOAST_EVENTS) do
		if take and not taken[event] then
			if alerts and alerts:IsEventRegistered(event) then
				alerts:UnregisterEvent(event)
				taken[event] = true
			end
			events:TryWatch(OWNER, event)
		elseif not take then
			if taken[event] and alerts then
				alerts:RegisterEvent(event)
			end
			taken[event] = nil
			events:Unwatch(OWNER, event)
		end
	end
end

local function HoldBannerLoot(hold)
	local banner = _G.BossBanner
	if not banner then
		return
	end
	if hold and not bannerTaken and banner:IsEventRegistered(BANNER_EVENT) then
		banner:UnregisterEvent(BANNER_EVENT)
		bannerTaken = true
	elseif not hold and bannerTaken then
		banner:RegisterEvent(BANNER_EVENT)
		bannerTaken = false
	end
end

local function ApplyBanner()
	local mode = module.active and db.banner or "blizzard"
	if mode == "solo" then
		HoldBannerLoot(not IsInGroup())
		events:Watch(OWNER, "GROUP_ROSTER_UPDATE")
	else
		HoldBannerLoot(mode == "valuable")
		events:Unwatch(OWNER, "GROUP_ROSTER_UPDATE")
	end
	if mode == "valuable" then
		events:Watch(OWNER, BANNER_EVENT)
	else
		events:Unwatch(OWNER, BANNER_EVENT)
	end
end

events:On(OWNER, "GROUP_ROSTER_UPDATE", ApplyBanner)

-- Applies the switches: on Start, on Stop (module.active is false by then: gives everything back) and when a
-- setting changes.
function ns.LootToasts_Apply()
	local on = module.active
	TakeToasts(on and db.popups)
	ApplyBanner()
	for _, event in ipairs({ "CHAT_MSG_COMBAT_FACTION_CHANGE", "CURRENCY_DISPLAY_UPDATE" }) do
		if on and db.extras.repCurrency then
			events:Watch(OWNER, event)
		else
			events:Unwatch(OWNER, event)
		end
	end
	if not on then
		wipe(recent)
	end
end

function ns.LootToasts_Init(moduleDB, lootModule)
	db, module = moduleDB, lootModule
end
