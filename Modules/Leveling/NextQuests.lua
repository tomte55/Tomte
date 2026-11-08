local addonName, ns = ...

-- Leveling (World of Warcraft: Forever only): the next quests widget. Your quests grouped by where they are into stops,
-- the nearest stop first: its quests (turn-ins first, then by level) and a line for the stop after it. A click makes a
-- quest active, Shift-click tracks it (as on the page). Moved in Edit Mode. Rules in Data.lua (Leveling_NextStops), reads
-- in Read.lua; started from Leveling.lua. See docs/superpowers/specs/2026-11-08-tomte-forever-next-quests.md.

local WIDTH = 270
local PAD = 10
local TITLE_H = 26
local ROW_H = 18
local LEVEL_W = 24
local MARK_W = 3
local CLUSTER_YARDS = 300 -- quests this close to another on the stop join it: about a camp or a stretch of road
local MOVE_REDRAW = 100 -- yards walked before the stops are sorted again
local MOVE_DISTANCE = 20 -- yards walked before only the distances are written again
local TICK = 2 -- seconds between position checks while the widget shows
local UPDATE_DELAY = 0.5 -- seconds: quest log events come in bursts
local DEFAULT_POINT = { "TOPRIGHT", "TOPRIGHT", -260, -330 }

local UI = ns.UI

local db, frame, ticker
local active = false
local updatePending = false
local points = {} -- quest spots ([questID] = Read.lua's point), kept until the next full update reads them again
local pointsMap -- the map they were read from
local pointsStale = true -- the quest log changed since: read them again at the next update
local drawnAt -- where you stood at the last full draw
local distanceAt -- where you stood when the distances were last written
local shownStops = {}
local events = ns.NewEvents()
local OWNER = "nextQuests"

local function GroupRole(key)
	for _, g in ipairs(ns.LEVELING_QUEST_GROUPS) do
		if g.key == key then
			return g.role
		end
	end
	return "text"
end

local function YardsText(distance)
	return distance and ("%s yd"):format(ns.Thousands(ns.Leveling_StopYards(distance))) or ""
end

local function Moved(from, to)
	if not (from and to) or from.continent ~= to.continent then
		return math.huge
	end
	local dx, dy = from.x - to.x, from.y - to.y
	return math.sqrt(dx * dx + dy * dy)
end

-- Frame ---------------------------------------------------------------------------------------------------------------

local function Place()
	local p = db.nextFrame.point or DEFAULT_POINT
	frame:ClearAllPoints()
	frame:SetPoint(p[1], UIParent, p[2], p[3], p[4])
end

local function RowEnter(self)
	self.bg:Show()
	if self.quest then
		ns.LevelingPage_QuestTooltip(self, self.quest, "ANCHOR_LEFT")
	end
end

local function RowLeave(self)
	self.bg:Hide()
	GameTooltip:Hide()
end

local function RowClick(self)
	if not self.quest or self.sample then
		return
	end
	ns.LevelingPage_QuestClick(self.quest, function()
		ns.LevelingPage_ShowMark(self.mark, self.quest)
		if GameTooltip:IsOwned(self) then
			RowEnter(self)
		end
	end)
end

local function Row(i)
	local row = frame.rows[i]
	if not row then
		row = CreateFrame("Button", nil, frame)
		row:SetHeight(ROW_H)
		row:RegisterForClicks("LeftButtonUp")
		row.bg = row:CreateTexture(nil, "BACKGROUND")
		row.bg:SetAllPoints()
		row.bg:SetColorTexture(UI.Color("hover"))
		row.bg:Hide()
		row.mark = row:CreateTexture(nil, "ARTWORK") -- active or tracked, as on the page
		row.mark:SetPoint("TOPLEFT", 0, -2)
		row.mark:SetPoint("BOTTOMLEFT", 0, 2)
		row.mark:SetWidth(MARK_W)
		row.level = UI.Text(row, 12, "textMuted", "number")
		row.level:SetPoint("LEFT", MARK_W, 0)
		row.level:SetWidth(LEVEL_W)
		row.level:SetJustifyH("RIGHT")
		row.right = UI.Text(row, 11, "textMuted", "number")
		row.right:SetPoint("RIGHT", -2, 0)
		row.title = UI.Text(row, 12, "text")
		row.title:SetPoint("LEFT", row.level, "RIGHT", 8, 0)
		row.title:SetPoint("RIGHT", row.right, "LEFT", -8, 0)
		row.title:SetJustifyH("LEFT")
		row.title:SetWordWrap(false)
		row:SetScript("OnEnter", RowEnter)
		row:SetScript("OnLeave", RowLeave)
		row:SetScript("OnClick", RowClick)
		frame.rows[i] = row
	end
	return row
end

local function Build()
	frame = CreateFrame("Frame", nil, UIParent)
	frame:SetSize(WIDTH, 60)
	frame:SetFrameStrata("MEDIUM")
	frame:SetClampedToScreen(true)
	frame:SetMovable(true)
	frame:Hide()
	UI.Panel(frame, { alpha = 0.55, subtle = true })
	frame.distance = UI.Text(frame, 12, "textMuted", "number")
	frame.distance:SetPoint("TOPRIGHT", -26, -8)
	frame.title = UI.Text(frame, 13, "heading", "title")
	frame.title:SetPoint("TOPLEFT", PAD, -7)
	frame.title:SetPoint("RIGHT", frame.distance, "LEFT", -8, 0)
	frame.title:SetJustifyH("LEFT")
	frame.title:SetWordWrap(false)
	frame.after = UI.Text(frame, 11, "textMuted")
	frame.after:SetJustifyH("LEFT")
	frame.after:SetWordWrap(false)
	frame.rows = {}
	frame.collapse = UI.CollapseButton(frame, function()
		return db.nextCollapsed
	end, function()
		db.nextCollapsed = not db.nextCollapsed
		ns.LevelingNext_Update()
	end)
	Place()
end

-- Drawing --------------------------------------------------------------------------------------------------------------

-- Made-up stops for Edit Mode when there's nothing to show.
local function SampleStops()
	local function Q(id, title, level, xp, complete)
		return { questID = id, title = title, level = level, xp = xp, complete = complete }
	end
	return {
		{ zone = "The Barrens", distance = 240, quests = { Q(1, "Thistle Roots", 17, 0, true),
			Q(2, "Bristleback Raiders", 18, 1650), Q(3, "Watering Hole Trouble", 19, 1800) },
			groups = { [1] = "done", [2] = "now", [3] = "now" } },
		{ zone = "Stonetalon Mountains", distance = 1180, quests = { Q(4, "a", 20, 0) }, groups = {} },
	}
end

local function DrawDistances(you)
	local first, second = shownStops[1], shownStops[2]
	if not first then
		return
	end
	if you and not shownStops.sample then
		for _, stop in ipairs({ first, second }) do
			local nearest
			for _, q in ipairs(stop.quests) do
				local d = points[q.questID] and Moved(you, points[q.questID])
				if d and d ~= math.huge then
					nearest = nearest and math.min(nearest, d) or d
				end
			end
			stop.distance = nearest
		end
	end
	frame.distance:SetText(YardsText(first.distance))
	local parts = {}
	if (shownStops.more or 0) > 0 then
		parts[#parts + 1] = ("%d more here."):format(shownStops.more)
	end
	if second then
		local n = #second.quests
		parts[#parts + 1] = ("Then: %s, %d %s%s"):format(second.zone or "elsewhere", n, n == 1 and "quest" or "quests",
			second.distance and ("  ·  " .. YardsText(second.distance)) or "")
	end
	frame.after:SetText(table.concat(parts, " "))
end

local function Draw(stops, you)
	shownStops = stops
	local first = stops[1]
	frame.title:SetText(("Next: %s"):format(first.zone or "nearby"))
	local collapsed = db.nextCollapsed
	local y = TITLE_H
	local used = 0
	if not collapsed then
		for _, q in ipairs(first.quests) do
			if used >= db.nextCount then
				break
			end
			used = used + 1
			local row = Row(used)
			row.quest, row.sample = q, stops.sample
			local group = first.groups[q.questID] or "now"
			row.level:SetText(("%s%s"):format(tostring(q.level or "?"), q.elite and "+" or ""))
			UI.SetTextRole(row.level, GroupRole(group))
			row.title:SetText(q.dungeon and ("%s  %s"):format(q.title or "?", UI.Wrap(q.dungeon, "info")) or q.title or "?")
			if group == "done" then
				row.right:SetText("turn in")
				UI.SetTextRole(row.right, "success")
			elseif q.timeLeft then
				row.right:SetText(ns.Leveling_TimeLeft(q.timeLeft))
				UI.SetTextRole(row.right, "warning")
			else
				row.right:SetText((q.xp or 0) > 0 and ("%s XP"):format(ns.Thousands(q.xp)) or "")
				UI.SetTextRole(row.right, "textMuted")
			end
			ns.LevelingPage_ShowMark(row.mark, q)
			row:ClearAllPoints()
			row:SetPoint("TOPLEFT", PAD - 4, -y)
			row:SetPoint("RIGHT", -PAD + 4, 0)
			row:Show()
			y = y + ROW_H
		end
	end
	for i = used + 1, #frame.rows do
		frame.rows[i]:Hide()
	end
	local more = #first.quests - used
	stops.more = not collapsed and more or 0
	if not collapsed and (stops[2] or more > 0) then
		frame.after:ClearAllPoints()
		frame.after:SetPoint("TOPLEFT", PAD, -(y + 3))
		frame.after:SetPoint("RIGHT", -PAD, 0)
		frame.after:Show()
		y = y + ROW_H + 2
	else
		frame.after:Hide()
	end
	frame:SetHeight(collapsed and TITLE_H + 4 or y + 6)
	DrawDistances(you)
end

-- Updates --------------------------------------------------------------------------------------------------------------

local function Hide()
	if frame then
		frame:Hide()
	end
	if ticker then
		ticker:Cancel()
		ticker = nil
	end
	shownStops = {}
end

local function Tick()
	if not (frame and frame:IsShown()) or shownStops.sample then
		return
	end
	local you = ns.LevelingRead_You()
	if Moved(drawnAt, you) >= MOVE_REDRAW then
		ns.LevelingNext_Update()
	elseif Moved(distanceAt, you) >= MOVE_DISTANCE then
		distanceAt = you
		DrawDistances(you)
	end
end

function ns.LevelingNext_Update()
	if not (active and db.nextQuests) then
		Hide()
		return
	end
	local you, mapID = ns.LevelingRead_You()
	if pointsStale or pointsMap ~= mapID then
		points, pointsMap, pointsStale = mapID and ns.LevelingRead_QuestPoints(mapID) or {}, mapID, false
	end
	local stops = ns.Leveling_NextStops(ns.LevelingRead_QuestsTagged(), points, you, IsInGroup(), CLUSTER_YARDS)
	if #stops == 0 then
		if not ns.EditMode_Active() then
			Hide()
			return
		end
		stops = SampleStops()
		stops.sample = true
	end
	if not frame then
		Build()
	end
	drawnAt, distanceAt = you, you
	Draw(stops, you)
	frame:Show()
	if not ticker then
		ticker = C_Timer.NewTicker(TICK, Tick)
	end
end

local function UpdateSoon()
	if updatePending then
		return
	end
	updatePending = true
	C_Timer.After(UPDATE_DELAY, function()
		updatePending = false
		ns.LevelingNext_Update()
	end)
end

-- The quest log changed: its spots are read again.
local function QuestsChanged()
	pointsStale = true
	UpdateSoon()
end

local WATCHED = {
	QUEST_LOG_UPDATE = QuestsChanged,
	QUEST_ACCEPTED = QuestsChanged,
	QUEST_REMOVED = QuestsChanged,
	QUEST_TURNED_IN = QuestsChanged,
	ZONE_CHANGED_NEW_AREA = QuestsChanged,
	PLAYER_ENTERING_WORLD = QuestsChanged,
	PLAYER_LEVEL_UP = UpdateSoon,
	GROUP_ROSTER_UPDATE = UpdateSoon,
	QUEST_WATCH_LIST_CHANGED = UpdateSoon,
	SUPER_TRACKING_CHANGED = UpdateSoon,
}
for event, fn in pairs(WATCHED) do
	events:On(OWNER, event, fn)
end

ns.EditMode_Register({
	name = "Next quests",
	frame = function()
		return frame
	end,
	refresh = function()
		ns.LevelingNext_Update()
	end,
	saved = function()
		db.nextFrame.point = UI.TopLeftPoint(frame)
	end,
	module = "leveling",
	reset = function()
		db.nextFrame.point = nil
		if frame then
			Place()
		end
	end,
})

-- For /tomte leveling next: what the widget sees.
function ns.LevelingNext_Why()
	local you, mapID = ns.LevelingRead_You()
	local found = mapID and ns.LevelingRead_QuestPoints(mapID) or {}
	local quests = ns.LevelingRead_QuestsTagged()
	local n = 0
	for _ in pairs(found) do
		n = n + 1
	end
	ns.Print(("Next quests: map %s, you %s, %d of %d quests have a spot, grouped %s."):format(tostring(mapID),
		you and ("%.0f, %.0f on %d"):format(you.x, you.y, you.continent) or "unknown", n, #quests, tostring(IsInGroup())))
	for i, stop in ipairs(ns.Leveling_NextStops(quests, found, you, IsInGroup(), CLUSTER_YARDS)) do
		local names = {}
		for k, q in ipairs(stop.quests) do
			names[k] = q.title or "?"
		end
		print(("  %d. %s, %s: %s"):format(i, tostring(stop.zone), YardsText(stop.distance), table.concat(names, ", ")))
	end
end

function ns.LevelingNext_Start(moduleDB)
	db = moduleDB
	active = true
	for event in pairs(WATCHED) do
		events:Watch(OWNER, event)
	end
	pointsStale = true
	UpdateSoon()
end

function ns.LevelingNext_Stop()
	active = false
	events:UnwatchAll(OWNER)
	pointsStale = true
	Hide()
end
