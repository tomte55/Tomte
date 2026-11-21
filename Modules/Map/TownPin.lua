local addonName, ns = ...

-- Tomte map: a click on a town marker (a trainer, a banker, a mailbox ...) puts your map pin on it, named after who
-- stands there. A marker standing for several opens a menu to pick one. Wired in Pins.lua (LayoutTowns); the rows
-- come from Data/Forever/Townsfolk.lua through ns.Map_TownRows, with their canvas spots (cx, cy) added.

local UI = ns.UI

-- A row's spot as your map pin. Its own map may not take one (a city's inside): then the maps above it, up to the
-- continent, as a Ctrl-click on the map does (Window.lua). Through Waypoints when it's there: it shows the name.
local function PinRow(r, kindName)
	local title = r.name or kindName
	local mapID, x, y, seen = r.mapID, r.x, r.y, {}
	while mapID and not seen[mapID] do
		seen[mapID] = true
		if x and C_Map.CanSetUserWaypointOnMap(mapID) then
			if ns.Way_SetPoint then
				ns.Way_SetPoint(mapID, x, y, title, r.name and r.title and { subtitle = r.title } or nil)
			else
				ns.TrackPin(mapID, x, y)
			end
			return
		end
		local map = C_Map.GetMapInfo(mapID)
		mapID = map and map.parentMapID
		local box = mapID and ns.MapArt_Box(mapID)
		x, y = nil, nil
		if box and r.cx then
			x, y = ns.Map_FromBox(box, r.cx, r.cy)
		end
	end
	ns.Print("can't place a map pin there.")
end

-- pin: a town pin from Pins.lua (rows, kindName). One row: pinned. Several: a menu of the named ones; markers without
-- names (mailboxes) stand so close together that the first one does.
function ns.MapTown_Click(pin)
	local rows, kindName = pin.rows, pin.kindName
	if not rows or #rows == 0 then
		return
	end
	local named = 0
	for _, r in ipairs(rows) do
		if r.name then
			named = named + 1
		end
	end
	if named < 2 then
		for _, r in ipairs(rows) do
			if r.name or named == 0 then
				PinRow(r, kindName)
				return
			end
		end
	end
	UI.ContextMenu(pin, function(_, root)
		root:CreateTitle(MAP_PIN or "Map pin")
		for _, r in ipairs(rows) do
			if r.name then
				local text = r.title and ("%s %s"):format(r.name, UI.Wrap(r.title, "textMuted")) or r.name
				root:CreateButton(text, function()
					PinRow(r, kindName)
				end)
			end
		end
	end)
end

-- The tooltip's last line for a town pin of this many rows.
function ns.MapTown_Hint(rows)
	local named = 0
	for _, r in ipairs(rows) do
		if r.name then
			named = named + 1
		end
	end
	return named > 1 and "Click: put your map pin on one of them" or "Click: put your map pin here"
end
