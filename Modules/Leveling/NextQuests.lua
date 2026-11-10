local addonName, ns = ...

-- Leveling (World of Warcraft: Forever only): the next quests widget. Your quests grouped by where they are into stops,
-- the nearest stop first. The heading says where: the stop's distance and zone.
-- Under it the stop's quests (turn-ins first, then by level), each with what it gives and how far, and a line for the
-- stop after it. A click makes a quest active, Shift-click tracks it (as on the page). Moved in Edit Mode. Rules in Data.lua (Leveling_NextStops), reads
-- in Read.lua; started from Leveling.lua. See docs/superpowers/specs/2026-11-08-tomte-forever-next-quests.md.

local WIDTH = 270
local PAD = 10
local HEAD_H = 32 -- the heading: distance and zone; a hairline under it
local ROW_H = 34 -- a quest: its title, and under it what it gives and how far
local ROW_TOP = 4
local LEVEL_W = 26 -- wide enough for an elite quest's "60+"
local MARK_W = 3
local AFTER_DIST_W = 56 -- the next stop's distance, right of its line
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
local followed -- the quest the widget last made active: a quest you pick yourself stays until the top one changes
local addedWatch -- the quest the widget put on the objective tracker (not one you tracked): untracked when it moves on
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

-- A stop's distance in yards or meters (the setting), rounded to tens; Waypoints' formatting ("975 m", "1.2 km").
local function YardsText(distance)
	if not distance then
		return ""
	end
	local yards = ns.Leveling_StopYards(distance)
	if ns.Way_FormatDistance then
		return ns.Way_FormatDistance(yards, db.nextMetric)
	end
	return ("%s yd"):format(ns.Thousands(yards))
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

-- The active quest's title in the heading color, the others plain; the bar as on the page.
local function ShowActive(row)
	ns.LevelingPage_ShowMark(row.mark, row.quest)
	UI.SetTextRole(row.title, row.quest.active and "heading" or "text")
end

local function RowClick(self)
	if not self.quest or self.sample then
		return
	end
	ns.LevelingPage_QuestClick(self.quest, function()
		ShowActive(self)
		if GameTooltip:IsOwned(self) then
			RowEnter(self)
		end
	end)
end

-- A quest: its level and title, and under the title what it gives (or "Turn in") and how far it is.
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
		row.mark:SetPoint("TOPLEFT", 0, -3)
		row.mark:SetPoint("BOTTOMLEFT", 0, 3)
		row.mark:SetWidth(MARK_W)
		row.level = UI.Text(row, 12, "textMuted", "number")
		row.level:SetPoint("TOPLEFT", MARK_W, -ROW_TOP)
		row.level:SetWidth(LEVEL_W)
		row.level:SetJustifyH("RIGHT")
		row.title = UI.Text(row, 12, "text")
		row.title:SetPoint("TOPLEFT", row.level, "TOPRIGHT", 7, 0)
		row.title:SetPoint("RIGHT", -4, 0)
		row.title:SetJustifyH("LEFT")
		row.title:SetWordWrap(false)
		row.gives = UI.Text(row, 11, "textMuted", "number")
		row.gives:SetPoint("TOPLEFT", row.title, "BOTTOMLEFT", 0, -2)
		row.dist = UI.Text(row, 11, "textFaint", "number")
		row.dist:SetPoint("RIGHT", -4, 0)
		row.dist:SetPoint("TOP", row.gives, "TOP")
		row.dist:SetJustifyH("RIGHT")
		row:SetScript("OnEnter", RowEnter)
		row:SetScript("OnLeave", RowLeave)
		row:SetScript("OnClick", RowClick)
		frame.rows[i] = row
	end
	return row
end

-- Next to the minimize button and shown with it (on mouseover): a box, filled while the top quest is followed (Follow,
-- below). UI.FollowBox in Panel/Widgets.lua.
local function FollowButton(f)
	return UI.FollowBox(f, function()
		return db.nextFollow
	end, function()
		db.nextFollow = not db.nextFollow
		followed = nil -- turned on: the top quest is made active right away
		ns.LevelingNext_Update()
	end, function(on)
		return on and "Following the top quest" or "Not following the top quest",
			on and "The top quest becomes your active quest. Click to stop."
				or "Click to make the top quest your active quest each time a new one comes up."
	end)
end

local function Build()
	frame = CreateFrame("Frame", nil, UIParent)
	frame:SetSize(WIDTH, 60)
	frame:SetFrameStrata("MEDIUM")
	frame:SetClampedToScreen(true)
	frame:SetMovable(true)
	frame:Hide()
	UI.Panel(frame, { alpha = 0.55, subtle = true })
	-- Where: the distance (the biggest thing here), and the zone, quiet after it.
	frame.distance = UI.Text(frame, 17, "heading", "number")
	frame.distance:SetPoint("LEFT", frame, "TOPLEFT", PAD, -HEAD_H / 2)
	frame.zone = UI.Text(frame, 12, "textMuted", "title")
	frame.zone:SetPoint("BOTTOMLEFT", frame.distance, "BOTTOMRIGHT", 7, 1)
	frame.zone:SetPoint("RIGHT", -46, 0) -- clear of the buttons that show on mouseover
	frame.zone:SetJustifyH("LEFT")
	frame.zone:SetWordWrap(false)
	frame.rule = UI.Hairline(frame, WIDTH - 2 * PAD, 0.6)
	frame.rule:SetPoint("TOPLEFT", PAD, -HEAD_H)
	-- After the stop: how many more are here, then the stop after it and how far.
	frame.after = UI.Text(frame, 11, "textMuted")
	frame.after:SetJustifyH("LEFT")
	frame.after:SetWordWrap(true) -- a long zone name takes a second line
	frame.afterDist = UI.Text(frame, 11, "textFaint", "number")
	frame.afterDist:SetJustifyH("RIGHT")
	frame.rows = {}
	frame.collapse = UI.CollapseButton(frame, function()
		return db.nextCollapsed
	end, function()
		db.nextCollapsed = not db.nextCollapsed
		ns.LevelingNext_Update()
	end)
	frame.follow = FollowButton(frame)
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

-- A quest's distance from you, or nil without both spots.
local function QuestYards(you, q)
	local d = you and points[q.questID] and Moved(you, points[q.questID])
	return d ~= math.huge and d or nil
end

-- The distances (the heading's, each quest's, the next stop's) and the frame's height, which follows the last line. Again every MOVE_DISTANCE yards walked.
local function DrawDistances(you)
	local first, second = shownStops[1], shownStops[2]
	if not first then
		return
	end
	if you and not shownStops.sample then
		for _, stop in ipairs({ first, second }) do
			local nearest
			for _, q in ipairs(stop.quests) do
				local d = QuestYards(you, q)
				if d and (not nearest or d < nearest) then
					nearest = d
				end
			end
			stop.distance = nearest
		end
	end
	frame.distance:SetText(first.distance and YardsText(first.distance) or "")
	for _, row in ipairs(frame.rows) do
		if row:IsShown() and row.quest then
			row.dist:SetText(YardsText(row.sample and nil or QuestYards(you, row.quest)))
		end
	end
	if not frame.after:IsShown() then
		return
	end
	local lines = {}
	if (shownStops.more or 0) > 0 then
		lines[#lines + 1] = shownStops.more == 1 and "1 more quest here" or ("%d more quests here"):format(shownStops.more)
	end
	if second then
		local n = #second.quests
		-- "Then 2 quests further on" in the same zone, "Then 1 quest in Stonetalon Mountains" in another.
		local quests = n == 1 and "1 quest" or ("%d quests"):format(n)
		local where = (second.zone and second.zone ~= first.zone) and (" in " .. second.zone) or " further on"
		lines[#lines + 1] = ("Then %s"):format(UI.Wrap(quests .. where, "text"))
		frame.afterDist:SetText(YardsText(second.distance))
	else
		frame.afterDist:SetText("")
	end
	frame.after:SetText(table.concat(lines, "\n"))
	frame:SetHeight(frame.afterY + frame.after:GetStringHeight() + PAD)
end

local function Draw(stops, you)
	shownStops = stops
	local first = stops[1]
	frame.zone:SetText(first.zone or "Nearby")
	local collapsed = db.nextCollapsed
	frame.rule:SetShown(not collapsed)
	local y = HEAD_H + 4
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
				row.gives:SetText("Turn in")
				UI.SetTextRole(row.gives, "success")
			elseif q.timeLeft then
				row.gives:SetText(ns.Leveling_TimeLeft(q.timeLeft))
				UI.SetTextRole(row.gives, "warning")
			else
				row.gives:SetText((q.xp or 0) > 0 and ("%s XP"):format(ns.Thousands(q.xp)) or "")
				UI.SetTextRole(row.gives, "textMuted")
			end
			ShowActive(row)
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
		frame.after:SetPoint("TOPLEFT", PAD, -(y + 4))
		frame.after:SetPoint("RIGHT", -(PAD + AFTER_DIST_W), 0)
		frame.after:Show()
		frame.afterDist:ClearAllPoints()
		frame.afterDist:SetPoint("TOPRIGHT", -PAD, -(y + 4))
		frame.afterDist:Show()
		frame.afterY = y + 4
	else
		frame.after:Hide()
		frame.afterDist:Hide()
	end
	frame:SetHeight(collapsed and HEAD_H + 2 or y + 6)
	DrawDistances(you)
end

-- Updates --------------------------------------------------------------------------------------------------------------

-- The top quest becomes the active one (marked on the map; Waypoints' arrow follows it) when it changes. Through
-- ns.SafeTrack: the map and tracker redraw inside the call, which in combat hits protected frames.
local function Follow(q)
	if not (q and C_SuperTrack) then
		return
	end
	-- Your own map pin (or corpse) is what you're heading for: hands off until it goes (ns.OwnTargetTracked).
	if ns.OwnTargetTracked() then
		followed = nil
		return
	end
	if q.questID == followed then
		return
	end
	followed = q.questID
	local id = q.questID
	ns.SafeTrack(function()
		-- On the tracker too, as a click does. The quest this put there before goes, so the tracker doesn't fill up.
		if addedWatch and addedWatch ~= id and C_QuestLog.GetQuestWatchType(addedWatch) then
			C_QuestLog.RemoveQuestWatch(addedWatch)
		end
		addedWatch = nil
		if not C_QuestLog.GetQuestWatchType(id) then
			C_QuestLog.AddQuestWatch(id)
			addedWatch = id
		end
		if C_SuperTrack.GetSuperTrackedQuestID() ~= id then
			ns.LevelingPage_MakeActive(id)
		end
	end)
end

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
	-- The Quest list shows these stops itself (Modules/QuestList): no second widget, and it follows the nearest quest.
	if not (active and db.nextQuests) or (ns.QuestList_Active and ns.QuestList_Active()) then
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
	if db.nextFollow and not stops.sample then
		Follow(stops[1].quests[1])
	end
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
	USER_WAYPOINT_UPDATED = UpdateSoon,
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
