local addonName, ns = ...

-- Dungeon journal: the right side of a dungeon: a boss's band and loot tiles, a quest's band (its giver standing in
-- it) and details, and Before you go (your quests to pick up on the way, by zone). Shared through ns.DJKit (Read.lua);
-- laid out by Page.lua.

local UI = ns.UI
local Kit = ns.HomeKit
local J = ns.DJKit

local SWITCH_W = 190 -- room kept on the band for the Usable by you switch

-- Map pins --------------------------------------------------------------------------------------------------------------

-- Opens the Tomte map on the spot, highlighted (when the map has a way to), and sets a waypoint so the arrow guides.
local function PinClick(row)
	local p = row.pin
	-- false: the pin waits for combat to end (Waypoint.lua says so itself); nil: no pin for that map.
	local placed = p.map and ns.Way_SetPoint and ns.Way_SetPoint(p.map, p.x / 100, p.y / 100, p.label)
	local shown = p.map and ns.MapWindow_ShowSpot and ns.MapWindow_ShowSpot(p.map, p.x / 100, p.y / 100, p.label)
	if shown then
		return
	elseif placed == nil then
		ns.Print(("%s: no pin for that place."):format(p.label))
	elseif placed then
		ns.Print(("Pin set: %s, %s %.1f, %.1f."):format(p.label, p.zone or "?", p.x, p.y))
	end
end
J.PinClick = PinClick

local function PinTooltip(row)
	GameTooltip:SetOwner(row, "ANCHOR_NONE")
	GameTooltip:SetPoint("BOTTOMRIGHT", row, "TOPRIGHT", 0, 4)
	GameTooltip:SetText(row.pin.label)
	UI.TipLine("Click to put a pin on the map.", "textMuted")
	GameTooltip:Show()
end

-- text: the row's line ("Starts at: Thom Filch"); label: the pin's name; the second line says where.
local function PlaceRow(y, width, text, label, map, x, y2, zone)
	local row = J.DetailRow(y, width)
	local where = zone and x and ("%s %.1f, %.1f"):format(zone, x, y2) or zone or ""
	if map and x then
		row.pin = { map = map, x = x, y = y2, label = label, zone = zone }
		row.onClick, row.onEnter = PinClick, PinTooltip
	end
	row:Set(nil, text, "text", map and x and "Show on map" or nil, "accent", where)
	return y + Kit.ROW2_H
end

-- Quests ----------------------------------------------------------------------------------------------------------------

local function TurnIn(q)
	local spot = ns.Content_Get(ns.CONTENT_FOREVER, "questEnds")
	spot = spot and spot[q.id]
	if not spot then
		return nil
	end
	local area, x, y = spot:match("^(%d+):([%d.]+):([%d.]+)$")
	area = tonumber(area)
	if not area then
		return nil
	end
	local zone = C_Map.GetAreaInfo and C_Map.GetAreaInfo(area)
	return ns.MapForArea(area), tonumber(x), tonumber(y), zone
end

local function QuestByID(id)
	for _, wing in ipairs(J.state.inst.wings) do
		for _, q in ipairs(wing.quests) do
			if q.id == id then
				return q
			end
		end
	end
end

function J.DrawQuest(q, width)
	local c = J.page.right.content
	local PAD = J.PAD
	local state = ns.DJ_QuestState(q, J.Context())
	local about = {}
	if q.lvl then
		about[#about + 1] = ("From level %d"):format(q.lvl)
	end
	about[#about + 1] = q.side and J.SideName(q.side) or "Both sides"
	J.Stage(J.page.stage, J.QuestTitle(q), table.concat(about, ", "), J.STATE_TEXT[state], J.STATE_COLOR[state],
		q.giver)
	local y = PAD + 4
	if q.goals then
		y = J.Label(c, y, width, "Objectives")
		y = J.Text(c, y, width, table.concat(q.goals, "\n"), "textMuted", 13)
	end
	y = J.Label(c, y, width, "Where")
	local zoneName = J.MapName(q.map)
	if q.giver and q.giverName then
		y = PlaceRow(y, width, "Starts at: " .. q.giverName, q.giverName, q.map, q.x, q.y, zoneName)
	elseif q.map and q.x then
		-- No giver's name: an object (a disc, a gem, a sign) or someone the data doesn't name.
		y = PlaceRow(y, width, "Starts at: " .. (zoneName or "a spot on the map"), J.QuestTitle(q), q.map, q.x, q.y,
			zoneName)
	elseif q.item then
		local row = J.DetailRow(y, width)
		row:Set(C_Item.GetItemIconByID(q.item), "Starts from an item: " .. (J.ItemName(q.item) or "..."), "text", nil,
			nil, "Drops in the dungeon or nearby")
		y = y + Kit.ROW2_H
	else
		y = J.Text(c, y, width, "Where it starts isn't known yet.", "textFaint", 12)
	end
	local map, x, ty, zone = TurnIn(q)
	if zone then
		y = PlaceRow(y, width, "Turn in", "Turn in: " .. J.QuestTitle(q), map, x, ty, zone)
	end
	if q.after then
		local names = {}
		for _, id in ipairs(q.after) do
			local before = QuestByID(id)
			names[#names + 1] = J.QuestName(id, before and before.name or ("quest " .. id))
		end
		y = J.Text(c, y + J.TEXT_GAP, width, "Follows " .. table.concat(names, ", "), "textMuted", 12)
	end
	if q.rewards then
		y = J.Label(c, y, width, "Rewards")
		y = J.Tiles(c, q.rewards, y + 2, width)
	end
	return y
end

-- Before you go: the quests to pick up on the way, by the zone they start in.
function J.DrawPrep(width)
	local c = J.page.right.content
	local groups = ns.DJ_Prep(J.state.inst, J.Context())
	local n = 0
	for _, g in ipairs(groups) do
		n = n + #g.list
	end
	J.Stage(J.page.stage, "Before you go", "Your quests for this dungeon you can take now, by where they start",
		n == 0 and "Nothing to pick up" or (n == 1 and "1 quest to pick up" or ("%d quests to pick up"):format(n)),
		n == 0 and "textMuted" or "accent")
	local y = J.PAD + 4
	for _, g in ipairs(groups) do
		local zone = J.MapName(g.map)
		y = J.Label(c, y, width, zone or "Elsewhere")
		for _, q in ipairs(g.list) do
			local title = J.QuestTitle(q)
			y = PlaceRow(y, width, q.giverName and (title .. ": " .. q.giverName) or title, q.giverName or title, q.map,
				q.x, q.y, zone)
		end
	end
	if n == 0 then
		y = J.Text(c, y, width, "No quest for this dungeon waits to be picked up: you have them, did them, or they "
			.. "start from an item or at a higher level.", "textMuted", 13)
	end
	return y
end

-- Bosses ----------------------------------------------------------------------------------------------------------------

local function Count(n, one, many)
	return n == 1 and one or many:format(n)
end

function J.DrawBoss(entry, width)
	local c = J.page.right.content
	local boss = entry.boss
	local total, shown, upgrades = #boss.loot, 0, 0
	for _, id in ipairs(boss.loot) do
		if J.Shown(id) then
			shown = shown + 1
			if J.IsUpgrade(id) then
				upgrades = upgrades + 1
			end
		end
	end
	local note = Count(total, "1 item", "%d items")
	if upgrades > 0 then
		note = note .. ", " .. Count(upgrades, "1 upgrade for you", "%d upgrades for you")
	end
	if shown < total then
		note = note .. (", %d hidden"):format(total - shown)
	end
	if boss.extra then
		J.Stage(J.page.stage, boss.name, "Rare spawns first, then drops from any mob in the dungeon", note, nil, nil,
			SWITCH_W)
	else
		local list, n = ns.DJ_Bosses(J.state.inst), 0
		for i, e in ipairs(list) do
			n = (e.boss == boss) and i or n
		end
		local bosses = #list - (list[#list].boss.extra and 1 or 0)
		local where = entry.wing and entry.wing.name or J.state.inst.name
		J.Stage(J.page.stage, boss.name, ("%s, boss %d of %d"):format(where, n, bosses), note,
			upgrades > 0 and "success" or nil, boss.npc, SWITCH_W)
	end
	if total == 0 then
		return J.Text(c, J.PAD + 4, width, "No loot known for this boss yet.", "textMuted", 13)
	elseif shown == 0 then
		return J.Text(c, J.PAD + 4, width, ("Nothing here you can use. Turn off Usable by you to see all %s."):format(
			Count(total, "1 item", "%d items")), "textMuted", 13)
	end
	return J.Tiles(c, boss.loot, J.PAD + 4, width)
end
J.SWITCH_W = SWITCH_W
