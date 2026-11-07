local addonName, ns = ...

-- Where to get it (World of Warcraft: Forever only; tools/forever_list.lua): find any item by name and see where to buy, gather or farm
-- it, the best places for your level first, with a map pin. A line on item tooltips, and Ctrl+right-click on an item opens it. Rules in
-- Data.lua, the page in Page.lua, the data in Data/Forever/ItemSources.lua (pfQuest's, Classic's: Forever may differ).

local PAGE_KEY = "sources"
local ICON = "Interface\\Icons\\INV_Misc_Map_01"
local PARENT_MAPS = { 1414, 1415 } -- Kalimdor, Eastern Kingdoms

local module, db
local zoneMaps -- [zone name] = its map ID, built on first use
local hooked = false

function ns.Sources_Tables()
	return { items = ns.SOURCES_ITEMS, units = ns.SOURCES_UNITS, objects = ns.SOURCES_OBJECTS, zones = ns.SOURCES_ZONES,
		skinned = ns.SOURCES_SKINNED }
end

-- The zone you're in, as the table names it (English), for vendors there first: the map's name is in the client's language, so
-- it's matched against each zone's own localized name. Item tooltips ask often: kept until you're on another map.
local hereMap, hereName
local function HereZone()
	local mapID = C_Map.GetBestMapForUnit("player")
	if mapID == hereMap then
		return hereName
	end
	hereMap, hereName = mapID, nil
	local info = mapID and C_Map.GetMapInfo(mapID)
	while info and info.mapType > Enum.UIMapType.Zone and info.parentMapID ~= 0 do
		info = C_Map.GetMapInfo(info.parentMapID) -- a city district or cave: the zone it's in
	end
	if info then
		for areaID, english in pairs(ns.SOURCES_ZONES) do
			if (C_Map.GetAreaInfo and C_Map.GetAreaInfo(areaID) or english) == info.name then
				hereName = english
				break
			end
		end
	end
	return hereName
end

function ns.Sources_ForMe(itemID)
	return ns.Sources_Sort(ns.Sources_Read(ns.Sources_Tables(), itemID), UnitLevel("player"), (UnitFactionGroup("player")),
		HereZone())
end

local function BuildZoneMaps()
	zoneMaps = {}
	for _, parent in ipairs(PARENT_MAPS) do
		for _, info in ipairs(C_Map.GetMapChildrenInfo(parent, Enum.UIMapType.Zone, true) or {}) do
			zoneMaps[info.name] = info.mapID
		end
	end
end

-- The map for a zone's area ID: its name in this client's language if the game knows it, or the table's English one.
local function MapFor(source)
	if not zoneMaps then
		BuildZoneMaps()
	end
	local localized = C_Map.GetAreaInfo and C_Map.GetAreaInfo(source.zone)
	return zoneMaps[localized or ""] or zoneMaps[source.zoneName or ""]
end

-- A zone to skin in is pinned where most of its creatures of the right level are.
function ns.Sources_Pin(source)
	local label = source.kind == "skin" and "Beasts to skin" or source.name
	local mapID = MapFor(source)
	if not (mapID and ns.Way_SetPoint and ns.Way_SetPoint(mapID, source.x / 100, source.y / 100, label)) then
		ns.Print(("%s is in %s: no pin for that place."):format(label, source.zoneName or "a place the map doesn't show"))
		return
	end
	ns.Print(("Pin set: %s, %s %.1f, %.1f."):format(label, source.zoneName or "?", source.x, source.y))
end

-- Post-calls can't be removed: this does nothing while off.
local function OnItemTooltip(tooltip, data)
	local itemID = data and data.id
	if not (module.active and db.tooltip and tooltip == GameTooltip and type(itemID) == "number" and not ns.IsSecret(itemID)) then
		return
	end
	local line = ns.SOURCES_ITEMS[itemID] and ns.Sources_TipLine(ns.Sources_ForMe(itemID), UnitLevel("player"))
	if line then
		ns.UI.TipLine(line, "textMuted")
	end
end

-- Ctrl+right-click on any item link or bag item. A post-hook: whatever the game does with the click still happens.
local function OnModifiedClick(link)
	if not (module.active and db.ctrlClick and type(link) == "string" and IsControlKeyDown()
		and GetMouseButtonClicked() == "RightButton") then
		return
	end
	local itemID = C_Item.GetItemInfoInstant(link)
	if itemID and ns.SOURCES_ITEMS[itemID] then
		ns.SourcesPage_ShowItem(itemID)
		ns.Panel_OpenPage(PAGE_KEY)
	end
end

local function Lookup(_, rawArg)
	ns.SourcesPage_ShowSearch(rawArg or "")
	ns.Panel_OpenPage(PAGE_KEY)
end

module = ns.RegisterModule({
	key = "sources",
	name = "Where to get it",
	category = "gear",
	icon = ICON,
	summary = "Find any item and see where to buy, gather or farm it.",
	description = "Type an item's name to see who sells it, what it's gathered from and which mobs drop it, the best places for your "
		.. "level first, and for leather and hides the zones to skin beasts in. Click a place to put a pin on the map. Also a line on item tooltips, and Ctrl+right-click on an item opens it. "
		.. "It's Classic's data, so Forever may differ, and crafted items and quest rewards aren't covered yet.",
	enabledByDefault = true,
	defaults = {
		tooltip = true,
		ctrlClick = true,
	},
	home = {
		{ kind = "page", key = PAGE_KEY, order = 8, name = "Where to get it", icon = ICON, page = ns.SourcesPage,
			summary = function()
				return "Find any item"
			end },
	},
	init = function(moduleDB)
		db = moduleDB
	end,
	toggle = function(active)
		if active and not hooked then
			hooked = true
			TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, ns.Perf_Wrap(OnItemTooltip, "tooltip"))
			hooksecurefunc("HandleModifiedItemClick", OnModifiedClick)
		end
	end,
	commands = {
		{ "find", "look up where to get an item, for example /tomte sources find linen cloth", Lookup },
	},
	options = {
		{ type = "header", label = "Where to get it" },
		{ type = "checkbox", key = "tooltip", label = "A line on item tooltips",
			tooltip = "The best way to get the item for your level, for example who drops it and where." },
		{ type = "checkbox", key = "ctrlClick", label = "Ctrl+right-click opens an item",
			tooltip = "On an item in your bags or a link in chat." },
	},
})
