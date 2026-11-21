local addonName, ns = ...

-- Find (World of Warcraft: Forever): /tomte find tailor puts your map pin on the nearest townsperson whose name or
-- title matches, and says plainly where that is (here in your zone, or outside it and how far). The NPCs are the Tomte
-- map's town markers (Data/Forever/Townsfolk.lua, read through ns.Map_TownRows and ns.MAP_TOWN_KINDS in
-- Modules/Map/Data.lua). Matching and order in Data.lua; the Tomte map's search box in Modules/Map/FindBox.lua.

local ICON = "Interface\\Icons\\INV_Misc_Spyglass_02"
local TRACKING_ART = "Interface\\Minimap\\Tracking\\"
local SIDE = { Horde = "H", Alliance = "A" } -- Townsfolk.lua's sides
local ALSO = 2 -- other matches named under the one pinned

local module, db
-- Every townsperson you'd use (your side, your class's trainers), read on the first search: { mapID, x, y, name,
-- title, kind, kindName, icon, haystack, and once first matched: read = true, zone, world }.
local people

-- Reads ----------------------------------------------------------------------------------------------------------------

local function MapName(mapID)
	local info = mapID and C_Map.GetMapInfo(mapID)
	return info and info.name or nil
end

local function World(mapID, x, y)
	local map, pos = C_Map.GetWorldPosFromMapPos(mapID, CreateVector2D(x, y))
	if map and pos then
		return { map = map, x = pos.x, y = pos.y }
	end
end

local function People()
	if people then
		return people
	end
	people = {}
	local data = ns.Content_Get(ns.CONTENT_FOREVER, "townsfolk") or {}
	local side, class = SIDE[UnitFactionGroup("player") or ""], select(2, UnitClass("player"))
	for _, kind in ipairs(ns.MAP_TOWN_KINDS) do
		local kindName = _G[kind.global] or kind.name
		for _, r in ipairs(ns.Map_TownRows(data[kind.key], side, class)) do
			r.kind, r.kindName, r.icon = kind.key, kindName, TRACKING_ART .. kind.icon
			r.haystack = ns.Find_Haystack(r.name, r.title, { kindName, kind.name })
			people[#people + 1] = r
		end
	end
	return people
end

-- Your zone and where you stand in it, as Find_Rank takes it; world is nil where the game gives no position.
local function Me()
	local mapID = C_Map.GetBestMapForUnit("player")
	if not (mapID and ns.Readable(mapID)) then
		return nil
	end
	local pos = C_Map.GetPlayerMapPosition(mapID, "player")
	local x, y
	if pos then
		x, y = pos:GetXY()
	end
	local me = { mapID = mapID, zone = MapName(mapID) }
	if x and ns.Readable(x) and ns.Readable(y) and not (x == 0 and y == 0) then
		me.world = World(mapID, x, y)
	end
	return me
end

-- Searching ------------------------------------------------------------------------------------------------------------

-- For the Tomte map's search box too: the matches for text, nearest first (Data.lua, Find_Rank), and you ({ mapID,
-- zone, world } or nil). Each match also gets where = "here in Orgrimmar, 40 yards" or "outside Orgrimmar: ...".
function ns.Find_Search(text)
	local words = ns.Find_Words(text)
	local found = {}
	if #words == 0 then
		return found
	end
	for _, r in ipairs(People()) do
		if ns.Find_Matches(words, r.haystack) then
			if not r.read then
				r.read = true
				r.zone = MapName(r.mapID)
				r.world = World(r.mapID, r.x, r.y)
			end
			found[#found + 1] = r
		end
	end
	local me = Me()
	ns.Find_Rank(found, me)
	for _, r in ipairs(found) do
		r.where = ns.Find_Where(r, me and me.zone, ns.Thousands)
	end
	return found, me
end

-- Who a match is: "Snang (Journeyman Tailor)", or the kind for a mailbox.
function ns.Find_Label(r)
	if not r.name then
		return r.kindName
	end
	return r.title and ("%s (%s)"):format(r.name, r.title) or r.name
end

-- Your map pin on a match, named after them (Waypoints shows it). Its own map may not take a pin (a city's inside):
-- then the maps above it, up to the continent, through its world position. Returns true when placed (or placed once
-- combat ends), false when no map around it takes a pin.
function ns.Find_Pin(r)
	local title = r.name or r.kindName
	local opts = r.name and r.title and { subtitle = r.title } or nil
	local mapID, x, y, seen = r.mapID, r.x, r.y, {}
	while mapID and not seen[mapID] do
		seen[mapID] = true
		if x and C_Map.CanSetUserWaypointOnMap(mapID) then
			if ns.Way_SetPoint then
				return ns.Way_SetPoint(mapID, x, y, title, opts) ~= nil
			end
			ns.TrackPin(mapID, x, y)
			return true
		end
		local info = C_Map.GetMapInfo(mapID)
		mapID = info and info.parentMapID
		x, y = nil, nil
		if mapID and r.world and C_Map.GetMapPosFromWorldPos then
			local _, pos = C_Map.GetMapPosFromWorldPos(r.world.map, CreateVector2D(r.world.x, r.world.y), mapID)
			if pos and pos.x >= 0 and pos.x <= 1 and pos.y >= 0 and pos.y <= 1 then
				x, y = pos.x, pos.y
			end
		end
	end
	return false
end

-- The command -----------------------------------------------------------------------------------------------------------

local function Usage()
	ns.Print("/tomte find <what>: your map pin on the nearest one, for example /tomte find tailor, /tomte find "
		.. "expert enchanter, /tomte find mailbox. Also on the Tomte map's magnifying glass.")
end

local function Find(text, rawText)
	text = strtrim(rawText or text or "")
	if text == "" then
		Usage()
		return
	end
	local found = ns.Find_Search(text)
	local best = found[1]
	if not best then
		ns.Print(("nobody found for \"%s\". Try a title or what they do: tailor, banker, innkeeper, mailbox, "
			.. "mage trainer, repair."):format(text))
		return
	end
	if ns.Find_Pin(best) then
		ns.Print(("%s, %s: map pin placed."):format(ns.Find_Label(best), best.where))
	else
		ns.Print(("%s, %s (can't place a map pin there)."):format(ns.Find_Label(best), best.where))
	end
	for i = 2, math.min(#found, ALSO + 1) do
		print(("  also: %s, %s"):format(ns.Find_Label(found[i]), found[i].where))
	end
end

-- Module ----------------------------------------------------------------------------------------------------------------

module = ns.RegisterModule({
	key = "find",
	name = "Find",
	category = "travel",
	icon = ICON,
	summary = "Find the nearest trainer, banker, mailbox or other townsperson and put your map pin on them.",
	description = "Type what you're looking for, such as /tomte find tailor or /tomte find expert enchanter, and your "
		.. "map pin goes on the nearest one, named after them. Someone in the zone you're in comes first; when the "
		.. "nearest is somewhere else, it says so and how far. Works with names, titles (Journeyman Tailor, Banker, "
		.. "Mage Trainer) and professions (tailoring, enchanting). Also from the magnifying glass on the Tomte map.",
	enabledByDefault = true,
	defaults = {
		last = "", -- the last search typed on its settings page
	},
	init = function(moduleDB)
		db = moduleDB
	end,
	toggle = function()
	end,
	commands = {}, -- everything typed goes to the fallback: /tomte find <what>
	fallbackCommand = { "<what>", "your map pin on the nearest trainer, banker, mailbox ... (/tomte find tailor)",
		Find, pattern = "" },
	options = {
		{ type = "header", label = "Find" },
		{ type = "input", key = "last", label = "Find someone", placeholder = "tailor, banker, mailbox ...",
			onChange = function(text)
				if text and text ~= "" then
					Find(text)
				end
			end,
			tooltip = "Type what you're looking for and press Enter: your map pin goes on the nearest one. Or type "
				.. "/tomte find and what you're looking for." },
	},
})

-- The Tomte map's search box asks before it searches.
function ns.Find_IsOn()
	return module.active == true
end
