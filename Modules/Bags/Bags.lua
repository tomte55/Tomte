local addonName, ns = ...

-- Bags: Tomte's own bag and bank windows in place of Blizzard's: items sorted into categories the player can edit
-- (or one bag), marks for upgrades, transmog and more, search with saved searches, other characters' bags (from Item
-- counts). docs/superpowers/specs/2026-10-27-tomte-bags-design.md. Pure rules in Search.lua, Data.lua, EditData.lua
-- and Layout.lua; the reader in Read.lua, buttons in Buttons.lua, drawing in View.lua, the windows in Window.lua and
-- Bank.lua, the categories page in EditPage.lua, the takeover in Takeover.lua.

-- Full bag replacements: Tomte's bags stay off while one is loaded.
local OTHER_BAGS = { "Baganator", "Bagnon", "ArkInventory", "AdiBags", "BetterBags", "EnhanceQoLBags" }
local ITEM_DATA_DELAY = 0.3 -- seconds to gather a burst of GET_ITEM_INFO_RECEIVED into one redraw

local module, db
local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(self, event, ...)
	self[event](self, ...)
end)

local itemDataTimer

function ns.Bags_Active()
	return module ~= nil and module.active == true
end

-- The categories in use: the player's edited copy, or the defaults (Data.lua) until the first edit.
function ns.Bags_Layout()
	if db and db.layout and #db.layout > 0 then
		return db.layout
	end
	return ns.BAGS_LAYOUT
end

-- The player's own copy to edit (made from the defaults on the first edit).
function ns.Bags_EditLayout()
	if not (db.layout and #db.layout > 0) then
		db.layout = ns.BagsEdit_Copy(ns.BAGS_LAYOUT)
	end
	return db.layout
end

-- After an edit: both windows redraw with the new categories.
function ns.Bags_LayoutChanged()
	ns.BagsWindow_Relayout()
end

-- A search becomes a category at the top (the saved searches menu), and the categories page opens on it.
function ns.Bags_SearchToCategory(name, text)
	local node = ns.BagsEdit_AddCategory(ns.Bags_EditLayout(), name, text)
	ns.Bags_LayoutChanged()
	ns.Print(("%s is a category now, at the top of your bags. Edit it on the Bag categories page."):format(name))
	if ns.BagsEditPage_Select then
		ns.BagsEditPage_Select(node.key)
	end
end

-- Drops every cached item and redraws: Gear Check's verdicts or the transmog collection changed.
function ns.Bags_Reread()
	if ns.Bags_Active() then
		ns.BagsRead_Invalidate(nil)
		ns.BagsWindow_Refresh()
	end
end

-- Events -----------------------------------------------------------------------------------------------------------

function events:BAG_UPDATE_DELAYED()
	ns.BagsWindow_Refresh()
	ns.BagsBank_Refresh()
end

function events:BAG_UPDATE(bag)
	ns.BagsRead_Invalidate(bag)
end

events.ITEM_LOCK_CHANGED = events.BAG_UPDATE_DELAYED
events.BAG_NEW_ITEMS_UPDATED = events.BAG_UPDATE_DELAYED
events.EQUIPMENT_SETS_CHANGED = events.BAG_UPDATE_DELAYED

function events:BAG_CONTAINER_UPDATE()
	ns.BagsRead_Invalidate(nil)
	ns.BagsWindow_Refresh()
end

-- The bank: a tab bought or changed, the Warband bank's gold.
function events:BANK_TABS_CHANGED()
	ns.BagsBank_Relayout()
end

events.BANK_TAB_SETTINGS_UPDATED = events.BANK_TABS_CHANGED

function events:ACCOUNT_MONEY()
	ns.BagsBank_Refresh()
end

function events:BAG_UPDATE_COOLDOWN()
	ns.BagsButtons_UpdateCooldowns()
end

function events:TRANSMOG_COLLECTION_UPDATED()
	ns.Bags_Reread()
end

-- Items you couldn't use may be fine now. UnitLevel (and so the red "Requires Level" lines) can lag behind the
-- event, as Gear.lua found: read everything again once it's caught up.
function events:PLAYER_LEVEL_UP()
	ns.Bags_Reread()
	C_Timer.After(2, ns.Bags_Reread)
end

function events:GET_ITEM_INFO_RECEIVED()
	if itemDataTimer then
		return
	end
	itemDataTimer = C_Timer.NewTimer(ITEM_DATA_DELAY, function()
		itemDataTimer = nil
		if ns.Bags_Active() then
			ns.BagsWindow_ItemDataArrived()
			ns.BagsBank_Refresh() -- cheap when the bank is closed; its items load the same way
		end
	end)
end

function events:PLAYER_MONEY()
	ns.BagsWindow_RefreshFooter()
end

function events:CURRENCY_DISPLAY_UPDATE()
	ns.BagsWindow_RefreshFooter()
	ns.BagsCurrencies_Refresh()
end

function events:CURSOR_CHANGED()
	ns.BagsWindow_CursorChanged()
end

-- A merchant, the mailbox, a trade, the Auction House, the scrapper, a socket...: what fits it is bright, the rest
-- fades (Window.lua's Situation, Blizzard's item context matching).
-- While one of these windows is open, items keep their places (Window.lua): selling, mailing, trading, depositing
-- or scrapping leaves an empty slot where the item was. Enum.PlayerInteractionType: TradePartner, Merchant, Banker,
-- GuildBanker, Vendor, MailInfo, Auctioneer, ScrappingMachine, ItemInteraction, ItemUpgrade, CharacterBanker,
-- AccountBanker.
local HOLDING = {
	[1] = true, [5] = true, [8] = true, [10] = true, [12] = true, [17] = true, [21] = true, [40] = true, [44] = true,
	[53] = true, [67] = true, [68] = true,
}
local holdingOpen = {} -- [interaction type] = true while open

function events:PLAYER_INTERACTION_MANAGER_FRAME_SHOW(kind)
	if HOLDING[kind] then
		holdingOpen[kind] = true
		ns.BagsWindow_SetHolding(true)
	end
	ns.BagsWindow_Refresh()
end

function events:PLAYER_INTERACTION_MANAGER_FRAME_HIDE(kind)
	holdingOpen[kind] = nil
	ns.BagsWindow_SetHolding(next(holdingOpen) ~= nil)
	ns.BagsWindow_Refresh()
end
events.SOCKET_INFO_UPDATE = events.BAG_UPDATE_DELAYED
events.SOCKET_INFO_CLOSE = events.BAG_UPDATE_DELAYED

local EVENTS = {
	"BAG_UPDATE", "BAG_UPDATE_DELAYED", "ITEM_LOCK_CHANGED", "BAG_NEW_ITEMS_UPDATED", "BAG_CONTAINER_UPDATE",
	"BAG_UPDATE_COOLDOWN", "EQUIPMENT_SETS_CHANGED", "TRANSMOG_COLLECTION_UPDATED", "GET_ITEM_INFO_RECEIVED",
	"PLAYER_MONEY", "CURRENCY_DISPLAY_UPDATE", "CURSOR_CHANGED", "PLAYER_INTERACTION_MANAGER_FRAME_SHOW",
	"PLAYER_INTERACTION_MANAGER_FRAME_HIDE", "SOCKET_INFO_UPDATE", "SOCKET_INFO_CLOSE", "BANK_TABS_CHANGED",
	"BANK_TAB_SETTINGS_UPDATED", "ACCOUNT_MONEY", "PLAYER_LEVEL_UP",
}

local function Start()
	for _, event in ipairs(EVENTS) do
		events:RegisterEvent(event)
	end
	ns.BagsRead_Invalidate(nil)
	ns.BagsTakeover_Start()
	ns.BagsBank_Start()
end

local function Stop()
	events:UnregisterAllEvents()
	if itemDataTimer then
		itemDataTimer:Cancel()
		itemDataTimer = nil
	end
	ns.BagsTakeover_Stop()
	ns.BagsBank_Stop()
	ns.BagsButtons_SetMouse(true)
	ns.BagsRead_Invalidate(nil)
	wipe(holdingOpen)
	ns.BagsWindow_SetHolding(false)
end

-- Commands ---------------------------------------------------------------------------------------------------------

-- /tomte bags why <item link>: which category the item is in, and why.
local function Why(_, rawArg)
	local text = rawArg and rawArg:match("^%s*(.-)%s*$")
	local itemID = text and text ~= "" and C_Item.GetItemInfoInstant(tonumber(text) or text)
	if not itemID then
		ns.Print("Shift-click an item into the command: /tomte bags why <item>")
		return
	end
	local found
	for _, item in ipairs((ns.BagsRead_Bags())) do
		if item.itemID == itemID then
			found = item
			break
		end
	end
	if not found then
		ns.Print("That item isn't in your bags.")
		return
	end
	local categories = ns.Bags_Flatten(ns.Bags_Layout())
	ns.Print(("%s:"):format(found.link or found.name or itemID))
	for _, line in ipairs(ns.Bags_Why(found, categories)) do
		ns.Print("  " .. line)
	end
end

local function Columns(v)
	return ("%d icons"):format(v)
end

local function Pixels(v)
	return ("%d px"):format(v)
end

local function Corners()
	return { { value = "TOPLEFT", text = "Top left" }, { value = "TOPRIGHT", text = "Top right" },
		{ value = "BOTTOMLEFT", text = "Bottom left" }, { value = "BOTTOMRIGHT", text = "Bottom right" },
		{ value = "off", text = "Off" } }
end

local function CornerRow(key, label, tooltip)
	return { type = "dropdown", key = "corners." .. key, label = label, choices = Corners,
		onChange = ns.BagsWindow_Relayout, tooltip = tooltip }
end

local function Check(key, label, tooltip)
	return { type = "checkbox", key = key, label = label, onChange = ns.BagsWindow_Relayout, tooltip = tooltip }
end

-- Auto open rows: the windows the game opens the bags for, then the ones Tomte can add.
local AUTO_OPEN = {
	{ "vendor", "Vendor" }, { "mail", "Mailbox" }, { "bank", "Bank" }, { "auction", "Auction House" },
	{ "scrapping", "Scrapping machine" }, { "catalyst", "Catalyst and item conversion" },
	{ "upgrade", "Item upgrade" }, { "guildbank", "Guild bank" }, { "crafting", "Professions" },
	{ "character", "Character panel" }, { "socket", "Socketing gems" }, { "trade", "Trade" },
}

local function AutoOpenRows(rows)
	rows[#rows + 1] = { type = "header", label = "Open the bags with" }
	for _, entry in ipairs(AUTO_OPEN) do
		rows[#rows + 1] = { type = "checkbox", key = "autoOpen." .. entry[1], label = entry[2] }
	end
	return rows
end

module = ns.RegisterModule({
	key = "bags",
	name = "Bags",
	category = "gear",
	icon = 133633, -- inv_misc_bag_08
	summary = "Your bags sorted into categories, with upgrade and transmog marks.",
	description = "Replaces the game's bags with one window: items sorted into categories (or one big bag), Gear Check's upgrade arrows, a mark on appearances you haven't collected, item levels, and a search that understands things like is:upgrade or ilvl>600.",
	enabledByDefault = false,
	conflicts = (function()
		local list = {}
		for _, addon in ipairs(OTHER_BAGS) do
			list[#list + 1] = { addon = addon, why = "Tomte's bags stay off while another bag addon is enabled" }
		end
		return list
	end)(),
	replaces = { { addon = "CanIMogIt", why = "a mark on bag items whose appearance you haven't collected" } },
	defaults = {
		view = "categories", -- categories | single
		columns = 12, -- icons per row
		iconSize = 36, -- pixels
		spacing = 10, -- pixels between categories on one line
		group = false, -- stacks of the same item shown as one icon with the total
		buttonsOnHover = false, -- the top bar's buttons only while the mouse is over the window
		locked = false, -- the window can't be dragged
		-- Where each mark sits on an item: TOPLEFT | TOPRIGHT | BOTTOMLEFT | BOTTOMRIGHT | off. Marks sharing a corner:
		-- the first that applies shows (Data.lua's BAGS_MARKS order). The stack count is the game's, bottom right.
		corners = {
			junk = "TOPLEFT", upgrade = "TOPLEFT", crafting = "TOPRIGHT", transmog = "TOPRIGHT", set = "TOPRIGHT",
			petlevel = "BOTTOMLEFT", ilvl = "BOTTOMLEFT",
		},
		ilvlColor = "quality", -- quality | plain
		looks = { fontSize = 12, newGlow = true, greyJunk = true, redUnusable = true, context = true },
		sortMethod = "quality", -- quality | type | name | ilvl (Data.lua's BAGS_SORTS), inside each category
		sortReverse = false,
		sortOnOpen = false, -- the game's Clean Up whenever the bags open (out of combat)
		-- Windows that open the bags with them. The game's own (vendor ... catalyst) on by default, as it does.
		autoOpen = {
			vendor = true, mail = true, bank = true, auction = true, scrapping = true, catalyst = true, upgrade = true,
			guildbank = false, crafting = false, character = false, socket = false, trade = false,
		},
		folded = {}, -- [section key] = true while folded
		position = {}, -- point, relPoint, x, y once dragged
		bankPosition = {}, -- the bank window's, the same way
		bankWidth = 22, -- icons per row in the bank window (wide rather than tall)
		bankFolded = {}, -- the bank window's folded sections, apart from the bags' (folded)
		bankStart = "warband", -- warband | character: which bank shows when you open the bank
		-- The player's categories (Data.lua's node shape, every node keyed: EditData.lua); empty until the first edit,
		-- and then the defaults stay as they were.
		layout = {},
		searches = {}, -- { { name, text } } saved searches, in the order saved
	},
	init = function(saved)
		db = saved
		ns.BagsWindow_Init(saved)
		ns.BagsTakeover_Init(saved)
		ns.BagsBank_Init(saved)
		ns.BagsEditPage_Init(saved)
	end,
	blocked = function()
		for _, addon in ipairs(OTHER_BAGS) do
			if C_AddOns.IsAddOnLoaded(addon) then
				return ("The %s addon is still enabled. Disable it and /reload to use Tomte's bags."):format(addon)
			end
		end
	end,
	toggle = function(active)
		if active then
			Start()
		else
			Stop()
		end
	end,
	home = {
		{ kind = "page", key = "bagcategories", order = 60, name = "Bag categories", icon = 133633,
			page = { Create = function(f)
				ns.BagsEditPage_Create(f)
			end, Refresh = function(f)
				ns.BagsEditPage_Refresh(f)
			end },
			summary = function()
				return "Your bag categories: rules, order, sections, sharing."
			end },
	},
	commands = {
		{ "why", "which category an item is in and why: /tomte bags why <item>", Why },
	},
	options = AutoOpenRows({
		{ type = "header", label = "Bag window" },
		{ type = "dropdown", key = "view", label = "View", onChange = ns.BagsWindow_Relayout, choices = function()
			return { { value = "categories", text = "Categories" }, { value = "single", text = "One bag" } }
		end, tooltip = "Categories sorts your items into groups. One bag shows everything in one grid." },
		{ type = "slider", key = "columns", label = "Width", min = 8, max = 24, step = 1, format = Columns,
			onChange = ns.BagsWindow_Relayout, tooltip = "How many icons fit in one row." },
		{ type = "slider", key = "iconSize", label = "Icon size", min = 28, max = 44, step = 1, format = Pixels,
			onChange = ns.BagsWindow_Relayout },
		{ type = "dropdown", key = "bankStart", label = "Bank opens on", choices = function()
			return { { value = "warband", text = "Warband bank" }, { value = "character", text = "Character bank" } }
		end, tooltip = "Which bank shows first when you talk to a banker. A banker with only one of them opens that one." },
		{ type = "slider", key = "bankWidth", label = "Bank width", min = 8, max = 36, step = 1, format = Columns,
			onChange = ns.BagsWindow_Relayout, tooltip = "How many icons fit in one row of the bank window." },
		{ type = "slider", key = "spacing", label = "Category spacing", min = 4, max = 30, step = 1, format = Pixels,
			onChange = ns.BagsWindow_Relayout, tooltip = "The gap between categories that share a line." },
		Check("group", "Group identical items",
			"Stacks of the same item show as one icon with the total. Clicking it uses or picks up the first stack."),
		Check("buttonsOnHover", "Buttons only on hover", "The buttons in the top bar show while the mouse is over the window."),
		Check("locked", "Lock the window", "The window can't be dragged."),
		{ type = "button", label = "Position", text = "Reset", onClick = function()
			ns.BagsWindow_ResetPosition()
		end, tooltip = "Move the bag window back to the bottom right. Drag its top to move it." },

		{ type = "button", label = "Categories", text = "Edit", onClick = function()
			ns.Panel_OpenPage("bagcategories")
		end, tooltip = "Add your own categories, change their rules and order, and share them." },

		{ type = "header", label = "On items" },
		CornerRow("ilvl", "Item level", "The item level on weapons and armor."),
		{ type = "dropdown", key = "ilvlColor", label = "Item level color", onChange = ns.BagsWindow_Relayout,
			choices = function()
				return { { value = "quality", text = "Quality" }, { value = "plain", text = "Plain" } }
			end, tooltip = "Quality: the item level in the item's quality color (blue for rare, purple for epic)." },
		CornerRow("upgrade", "Upgrade arrow",
			"Gear Check's arrows: green for an upgrade, yellow for maybe, in Tomte's color for another character. Needs Gear Check on."),
		CornerRow("transmog", "Transmog mark",
			"An X on items whose appearance you haven't collected: in the accent color when this character can learn it, grey when only another class can."),
		CornerRow("junk", "Junk coin", "The coin on grey items, not only at a merchant."),
		CornerRow("crafting", "Crafting list",
			"A dot on items your crafting list (Alts) wants moved; the item's tooltip says how many."),
		CornerRow("set", "Equipment set", "A small blue square on items in one of your equipment sets."),
		CornerRow("petlevel", "Battle pet level", "The level of a caged battle pet."),
		{ type = "slider", key = "looks.fontSize", label = "Number size", min = 9, max = 16, step = 1, format = Pixels,
			onChange = ns.BagsWindow_Relayout, tooltip = "Item levels, pet levels and free slots." },
		Check("looks.newGlow", "New item glow", "The glow on items you just got."),
		Check("looks.greyJunk", "Grey out junk", "Grey items show in grey."),
		Check("looks.redUnusable", "Red when you can't use it",
			"Gear and recipes your character can't use (armor type, class, skill or level) get a red tint."),
		Check("looks.context", "Fade what doesn't fit",
			"Items that can't go into the open window fade: a merchant won't buy them, they can't be mailed, traded or auctioned, or they don't fit the scrapper, a socket, an upgrade or the catalyst."),

		{ type = "header", label = "Sorting" },
		{ type = "dropdown", key = "sortMethod", label = "Order in a category", onChange = ns.BagsWindow_Relayout,
			choices = function()
				return { { value = "quality", text = "Quality" }, { value = "type", text = "Item type" },
					{ value = "name", text = "Name" }, { value = "ilvl", text = "Item level" } }
			end, tooltip = "How items line up inside each category (and in the one bag view)." },
		Check("sortReverse", "Reverse the order"),
		{ type = "checkbox", key = "sortOnOpen", label = "Clean up when the bags open",
			tooltip = "Runs the game's Clean Up every time the bags open, out of combat. Gear Check sets its direction." },
	}),
})
