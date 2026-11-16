local addonName, ns = ...

-- Dungeon journal (World of Warcraft: Forever only; tools/forever_list.lua): every dungeon's quests, bosses and loot
-- in a page of the Tomte window. Rules in Data.lua, the page in Page.lua, the data in Data/Forever/DungeonJournal.lua
-- (generated from AllTheThings by tools/dungeonjournal.lua).
-- See docs/superpowers/specs/2026-11-15-tomte-dungeon-journal-design.md.

local PAGE_KEY = "dungeonjournal"
local ICON = "Interface\\Icons\\INV_Misc_Book_11"

local db

function ns.DJ_DB()
	return db
end

-- Inside a dungeon it opens on that one.
local function Open()
	ns.DJPage_Show("here")
	ns.Panel_OpenPage(PAGE_KEY)
end

-- For other modules (the Tomte map's dungeon entrances): opens the journal on a dungeon (its instance ID). Says so in
-- chat and does nothing while the journal is off.
function ns.DJ_Open(instanceID)
	if ns.Module_RequireOn("dj") then
		ns.DJPage_Show(instanceID)
		ns.Panel_OpenPage(PAGE_KEY)
	end
end

ns.RegisterModule({
	key = "dj",
	name = "Dungeon journal",
	category = "quests",
	icon = ICON,
	summary = "Every dungeon's quests, bosses and loot.",
	description = "A page listing every dungeon by your level, with the quests you can take there and the upgrades it "
		.. "drops. Open one for its quests (what to pick up on the way, who starts each and where, with a map pin, "
		.. "what they ask and what they give) or its bosses and what each drops, marked when it's an upgrade or you "
		.. "own it. Star items you want; pin the entrance on the map. Search by dungeon, boss, quest or item. Open it "
		.. "with /tomte dj (inside a dungeon it opens on that one), a key binding or a minimap button. From "
		.. "AllTheThings' data, so a new dungeon's loot may still be missing.",
	enabledByDefault = true,
	replaces = { { addon = "DungeonJournal", why = "dungeon quests, bosses and loot" } },
	defaults = {
		otherSide = false, -- the dungeon's quest list also shows the other faction's and other classes'
		usableOnly = false, -- loot hides gear Gear Check says isn't for you
		chars = {}, -- [player GUID] = { wanted = { [itemID] = true } }: items starred
	},
	minimapButton = {
		name = "Dungeon journal",
		icon = ICON,
		shownByDefault = false,
		onClick = function()
			Open()
		end,
		tooltip = function(tooltip)
			tooltip:AddLine("Dungeon journal", ns.UI.RGB("heading"))
			tooltip:AddLine("Click to open it", ns.UI.RGB("accent"))
		end,
	},
	home = {
		{ kind = "page", key = PAGE_KEY, order = 9, name = "Dungeon journal", icon = ICON, page = ns.DJPage,
			summary = function()
				return "Dungeon quests, bosses and loot"
			end },
	},
	init = function(moduleDB)
		db = moduleDB
	end,
	toggle = function()
		-- Nothing runs in the background: the page registers its events only while it's shown.
	end,
	commands = {
		{ "", "open the Dungeon journal", Open, hidden = true },
	},
	options = {
		{ type = "header", label = "Dungeon journal" },
		{ type = "checkbox", key = "otherSide", label = "Show the other side's quests",
			tooltip = "In a dungeon's quest list, also the quests of the other faction and other classes, dimmed." },
		{ type = "checkbox", key = "usableOnly", label = "Only loot usable by you",
			tooltip = "Hides gear Gear Check says isn't for you (a weapon type you can't learn, armor you can't wear). "
				.. "Needs Gear Check on." },
	},
})

-- The key: a hidden button clicked by it (Key Bindings > Tomte: "CLICK TomteDungeonJournalButton:LeftButton", listed
-- in Bindings_Forever.xml, the file Forever reads), as the Tomte map's keys are. Acts on the key going down; a client
-- that sends only the release acts on that.
local KEY_REPEAT = 0.5 -- seconds: a release this soon after a press is the same key press
local keyButton = CreateFrame("Button", "TomteDungeonJournalButton", UIParent)
keyButton:Hide()
keyButton:RegisterForClicks("AnyDown", "AnyUp")
local lastDown = 0
keyButton:SetScript("OnClick", function(_, _, down)
	local now = GetTime()
	if down then
		lastDown = now
	elseif now - lastDown < KEY_REPEAT then
		return
	end
	if ns.Module_RequireOn("dj") then
		Open()
	end
end)
