local addonName, ns = ...

-- Item counts: Tomte's own record of what every character owns (bags, bank, mail, worn gear), the Warband bank and
-- the guild banks you look at, for item tooltips ("who has it"), the crafting list's materials (Alts) and looking at
-- another character's bags (Bags). Replaces Syndicator. Counting in Data.lua, reading in Collect.lua, tooltips in
-- Tooltip.lua.

local module, db
local index -- Data.lua's Counts_Index of the record, rebuilt when the record changed
local listeners = {} -- functions called after the record changed

function ns.Counts_Active()
	return module ~= nil and module.active == true
end

-- The record changed (Collect.lua): drop the index, tell the listeners (Alts' crafting list, the bag window).
function ns.Counts_Changed()
	index = nil
	for _, fn in ipairs(listeners) do
		ns.HomeCall(fn)
	end
end

-- fn() runs after every change to the record while Item counts is on.
function ns.Counts_OnChange(fn)
	listeners[#listeners + 1] = fn
end

-- One item's counts (Data.lua's index entry), nil when nobody has it or the module is off.
function ns.Counts_Entry(itemID)
	if not ns.Counts_Active() then
		return nil
	end
	index = index or ns.Counts_Index(db)
	return index[itemID]
end

-- Every item ID anyone in the record has (for Bags' search across characters).
function ns.Counts_ItemIDs()
	local ids = {}
	if not ns.Counts_Active() then
		return ids
	end
	index = index or ns.Counts_Index(db)
	for id in pairs(index) do
		ids[#ids + 1] = id
	end
	return ids
end

-- The characters in the record: { { guid, name, class, me } } by name.
function ns.Counts_Characters()
	local list = {}
	if not ns.Counts_Active() then
		return list
	end
	local me = UnitGUID("player")
	for guid, char in pairs(db.chars) do
		list[#list + 1] = { guid = guid, name = char.name or "?", class = char.class, me = guid == me }
	end
	table.sort(list, function(a, b)
		return a.name < b.name
	end)
	return list
end

-- The record itself (Data.lua's shape), read-only for Bags' search across characters.
function ns.Counts_Record()
	return db
end

function ns.Counts_CharName(guid)
	local char = db and db.chars[guid]
	return char and char.name
end

-- A character's items in one place ("bags", "bank", ...): { { id, link, count } }.
function ns.Counts_CharItems(guid, place)
	local char = db and db.chars[guid]
	return char and char.places and char.places[place] or {}
end

-- /tomte counts forget <name>
local function Forget(_, rawArg)
	local name = rawArg and rawArg:match("^%s*(.-)%s*$")
	if not name or name == "" then
		ns.Print("Which character? /tomte counts forget <name>")
		return
	end
	local me = UnitGUID("player")
	for guid, char in pairs(db.chars) do
		if char.name and char.name:lower() == name:lower() and guid ~= me then
			db.chars[guid] = nil
			ns.Counts_Changed()
			if ns.BagsWindow_ViewOwn then
				ns.BagsWindow_ViewOwn()
			end
			ns.Print(("%s is forgotten: their items no longer count."):format(char.name))
			return
		end
	end
	ns.Print(("No other character called %s is in the record."):format(name))
end

local function List()
	local chars = ns.Counts_Characters()
	if #chars == 0 then
		ns.Print("No characters recorded yet.")
		return
	end
	for _, c in ipairs(chars) do
		local char = db.chars[c.guid]
		local n = 0
		for _, items in pairs(char.places or {}) do
			n = n + #items
		end
		ns.Print(("%s: %d stacks, last read %s"):format(c.name, n, char.at and ns.Ago(GetServerTime() - char.at) or "never"))
	end
end

module = ns.RegisterModule({
	key = "counts",
	name = "Item counts",
	category = "gear",
	icon = 134327, -- inv_misc_note_01
	summary = "How many of an item each of your characters has, on its tooltip.",
	description = "Remembers what each of your characters carries: bags, bank, mail and worn gear, plus the Warband bank and the guild banks you look at. Item tooltips say who has how many and where. The crafting list (Alts) counts materials on every character with it, and Tomte's bags can show another character's bags.",
	enabledByDefault = true,
	replaces = { { addon = "Syndicator", why = "item counts on every character, for tooltips and the crafting list" } },
	defaults = {
		tooltip = true,
		guildBank = true, -- read guild bank tabs you look at
		chars = {}, -- [player GUID] = { name, realm, class, money, at, places = { [place] = { { id, link, count } } } }
		warband = {}, -- { at, items = { { id, link, count } } }
		guilds = {}, -- ["Guild-Realm"] = { name, at, tabs = { [tab] = { { id, link, count } } } }
	},
	noShare = { "chars", "warband", "guilds" },
	init = function(saved)
		db = saved
		ns.CountsTooltip_Init(module, saved)
	end,
	toggle = function(active)
		if active then
			ns.CountsCollect_Start(db)
			ns.CountsTooltip_Update()
		else
			ns.CountsCollect_Stop()
			index = nil
		end
		ns.Counts_Changed()
	end,
	commands = {
		{ "list", "the characters Item counts knows, and when each was read", List },
		{ "forget", "stop counting a character's items: /tomte counts forget <name>", Forget },
	},
	options = {
		{ type = "header", label = "Item counts" },
		{ type = "checkbox", key = "tooltip", label = "Counts on item tooltips", onChange = ns.CountsTooltip_Update,
			tooltip = "Item tooltips list who has how many of the item and where." },
		{ type = "checkbox", key = "guildBank", label = "Count guild banks",
			tooltip = "Guild bank tabs are counted when you look at them." },
	},
})
