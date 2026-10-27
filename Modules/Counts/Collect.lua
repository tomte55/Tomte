local addonName, ns = ...

-- Item counts: reads what this character owns into the record (shape in Data.lua): the bags whenever they change,
-- worn gear, the character bank and the Warband bank while the bank is open, the mailbox while it's open, the guild
-- bank tab you look at. Other characters keep what was read when they last played. Started and stopped by Counts.lua.

local BAGS = { 0, 1, 2, 3, 4, 5 } -- backpack, bags 1-4, reagent bag (Enum.BagIndex)
local EQUIP_FIRST, EQUIP_LAST = 1, 19 -- inventory slots of worn gear (head .. tabard)
local MAIL_ATTACHMENTS = 16 -- ATTACHMENTS_MAX_RECEIVE (MailFrame.lua)
local GUILD_SLOTS = 98 -- MAX_GUILDBANK_SLOTS_PER_TAB (Blizzard_GuildBankUI.lua)
local DELAY = 0.5 -- seconds to gather a burst of bag events into one read

local events = ns.NewEvents()
ns.Counts_Events = events

local db
local timers = {}
local bankOpen, mailOpen = false, false

local IsSecret = ns.IsSecret

local function Me()
	local guid = UnitGUID("player")
	local char = db.chars[guid]
	if not char then
		char = { places = {} }
		db.chars[guid] = char
	end
	char.name = UnitName("player")
	char.realm = GetNormalizedRealmName()
	char.class = select(2, UnitClass("player"))
	char.places = char.places or {}
	return char
end

-- { { id, link, count } } of every filled slot in these containers.
local function ReadContainers(containers)
	local list = {}
	for _, bag in ipairs(containers) do
		for slot = 1, C_Container.GetContainerNumSlots(bag) do
			local info = C_Container.GetContainerItemInfo(bag, slot)
			if info and info.itemID and not IsSecret(info.itemID, info.stackCount) then
				list[#list + 1] = { id = info.itemID, link = info.hyperlink, count = info.stackCount or 1 }
			end
		end
	end
	return list
end

local function TabIDs(bankType)
	local ids = {}
	for _, tab in ipairs(C_Bank.FetchPurchasedBankTabData(bankType) or {}) do
		ids[#ids + 1] = tab.ID
	end
	return ids
end

-- Readers --------------------------------------------------------------------------------------------------------------

local function ReadBags()
	Me().places.bags = ReadContainers(BAGS)
end

local function ReadEquipped()
	local list = {}
	for slot = EQUIP_FIRST, EQUIP_LAST do
		local id = GetInventoryItemID("player", slot)
		if id then
			list[#list + 1] = { id = id, link = GetInventoryItemLink("player", slot), count = 1 }
		end
	end
	Me().places.equipped = list
end

local function ReadBank()
	if not bankOpen then
		return
	end
	if C_Bank.CanViewBank(Enum.BankType.Character) then
		Me().places.bank = ReadContainers(TabIDs(Enum.BankType.Character))
	end
	if C_Bank.CanViewBank(Enum.BankType.Account) then
		db.warband.items = ReadContainers(TabIDs(Enum.BankType.Account))
		db.warband.at = GetServerTime()
	end
end

local function ReadMail()
	if not mailOpen then
		return
	end
	local list = {}
	for i = 1, GetInboxNumItems() do
		for j = 1, MAIL_ATTACHMENTS do
			local _, id, _, count = GetInboxItem(i, j)
			if id then
				list[#list + 1] = { id = id, count = count or 1 }
			end
		end
	end
	Me().places.mail = list
end

local function ReadGuildBank()
	local guild = GetGuildInfo("player")
	local tab = GetCurrentGuildBankTab()
	if not (guild and tab) then
		return
	end
	local key = guild .. "-" .. GetNormalizedRealmName()
	local record = db.guilds[key] or { tabs = {} }
	db.guilds[key] = record
	record.name, record.at = guild, GetServerTime()
	local list = {}
	for slot = 1, GUILD_SLOTS do
		local link = GetGuildBankItemLink(tab, slot)
		if link then
			local _, count = GetGuildBankItemInfo(tab, slot)
			list[#list + 1] = { id = C_Item.GetItemInfoInstant(link), link = link, count = count or 1 }
		end
	end
	record.tabs[tab] = list
end

-- Runs a reader once a burst of events has passed, then tells who listens (Counts.lua).
local function Soon(name, reader)
	if timers[name] then
		return
	end
	timers[name] = C_Timer.NewTimer(DELAY, function()
		timers[name] = nil
		if db then
			reader()
			Me().at = GetServerTime()
			ns.Counts_Changed()
		end
	end)
end

-- Events ---------------------------------------------------------------------------------------------------------------

events:On("collect", "BAG_UPDATE_DELAYED", function()
	Soon("bags", ReadBags)
	if bankOpen then
		Soon("bank", ReadBank)
	end
end)
events:On("collect", "PLAYER_EQUIPMENT_CHANGED", function()
	Soon("equipped", ReadEquipped)
end)
events:On("collect", "BANKFRAME_OPENED", function()
	bankOpen = true
	Soon("bank", ReadBank)
end)
events:On("collect", "BANKFRAME_CLOSED", function()
	bankOpen = false
end)
events:On("collect", "PLAYER_ACCOUNT_BANK_TAB_SLOTS_CHANGED", function()
	Soon("bank", ReadBank)
end)
events:On("collect", "MAIL_SHOW", function()
	mailOpen = true
end)
events:On("collect", "MAIL_CLOSED", function()
	mailOpen = false
end)
events:On("collect", "MAIL_INBOX_UPDATE", function()
	Soon("mail", ReadMail)
end)
events:On("collect", "GUILDBANKBAGSLOTS_CHANGED", function()
	if db.guildBank then
		Soon("guild", ReadGuildBank)
	end
end)
events:On("collect", "PLAYER_MONEY", function()
	Me().money = GetMoney()
end)

local EVENTS = {
	"BAG_UPDATE_DELAYED", "PLAYER_EQUIPMENT_CHANGED", "BANKFRAME_OPENED", "BANKFRAME_CLOSED",
	"PLAYER_ACCOUNT_BANK_TAB_SLOTS_CHANGED", "MAIL_SHOW", "MAIL_CLOSED", "MAIL_INBOX_UPDATE",
	"GUILDBANKBAGSLOTS_CHANGED", "PLAYER_MONEY",
}

function ns.CountsCollect_Start(moduleDB)
	db = moduleDB
	for _, event in ipairs(EVENTS) do
		events:TryWatch("collect", event)
	end
	local char = Me()
	char.money = GetMoney()
	Soon("bags", ReadBags)
	Soon("equipped", ReadEquipped)
end

function ns.CountsCollect_Stop()
	events:UnwatchAll("collect")
	for name, timer in pairs(timers) do
		timer:Cancel()
		timers[name] = nil
	end
	bankOpen, mailOpen = false, false
end
