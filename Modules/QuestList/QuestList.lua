local addonName, ns = ...

-- Quest list: Tomte's own list in place of the game's objective tracker (World of Warcraft: Forever for now). Main
-- file: db, events, hiding Blizzard's tracker and giving it back, follow-the-nearest, clicks and menus, options,
-- commands, Edit Mode. Grouping rules in Data.lua, reads in Read.lua and Leveling's Read.lua, Spoken's Play buttons in
-- Spoken.lua, drawing in List.lua. Leveling's Next quests widget steps aside while this is on (QuestList_Active).
-- See docs/superpowers/specs/2026-11-10-tomte-quest-list-design.md.

local CLUSTER_YARDS = 300 -- as Next quests: quests this close to another share a stop
local MOVE_REDRAW = 100 -- yards walked before the stops are worked out again
local MOVE_DISTANCE = 20 -- yards walked before only the distances are written again
local TICK = 2 -- seconds between position checks while the list shows
local UPDATE_DELAY = 0.3 -- seconds: quest log events come in bursts
local IDLE_ALPHA = 0.35 -- the list while the mouse is away (Fade until mouse-over)
local FADE_SECONDS = 0.6 -- easing into and out of combat, and to and from the mouse-over fade
local DEFAULT_POINT = { "TOPRIGHT", "TOPRIGHT", -90, -260 }
local ICON = 134332 -- inv_misc_note_06

local UI = ns.UI

local module, db, frame, ticker
local active = false
local updatePending = false
local events = ns.NewEvents()
local OWNER = "questList"
local TRACKER_OWNER = "questListTracker" -- waits for the game's tracker to load

local points = {} -- [questID] = Leveling's quest spot, read again when the log changes or you change maps
local pointsMap
local pointsStale = true
local drawnAt, distanceAt -- where you stood at the last full draw, and at the last distance update
local shown = {} -- the sections last drawn
local expanded = {} -- [section key] = true: "+N more" clicked (this session)
local seen = {} -- [questID] = { have = { [objective] = count }, complete, changed (GetTime of the last progress) }
local followed -- the quest follow-the-nearest last made active
-- Folds and opens clicked on stops, this visit only: stops change as you move, so a choice made on one doesn't stick to
-- whatever stop takes its key later. Wiped when the nearest stop changes.
local stopFolds = {}
local nearestKey
local axes, axesMap -- which way east and north run on your zone's map (Read.lua's QuestListRead_Axes)
local lastActive -- the active quest at the last update: a new one (picked on the map, say) opens its group
local inCombat = false

function ns.QuestList_DB()
	return db
end

-- Leveling asks this: while the list is on, the Next quests widget doesn't show.
function ns.QuestList_Active()
	return active
end

-- Blizzard's tracker ----------------------------------------------------------------------------------------------

-- Muted while the list is on (Tracker.lua says why it isn't hidden or moved). Not loaded yet: tried again when
-- Blizzard_ObjectiveTracker loads.
local function ApplyTracker()
	if ns.QuestListTracker_Mute(active) then
		events:UnwatchAll(TRACKER_OWNER)
	else
		events:Watch(TRACKER_OWNER, "ADDON_LOADED")
	end
end
events:On(TRACKER_OWNER, "ADDON_LOADED", function(_, name)
	if name == "Blizzard_ObjectiveTracker" then
		ApplyTracker()
	end
end)

-- Frame -----------------------------------------------------------------------------------------------------------

local function Place()
	local p = db.frame.point or DEFAULT_POINT
	frame:ClearAllPoints()
	frame:SetPoint(p[1], UIParent, p[2], p[3], p[4])
end

local function Build()
	frame = ns.QuestListUI_New(UIParent)
	frame:Hide()
	Place()
end

local Hide

local function HiddenForCombat()
	return inCombat and db.combat == "hide"
end

-- Eases the list to the alpha it should have now: faded or hidden in combat, faded while the mouse is away. Hidden in
-- combat, it fades out first and hides once it's gone (a click-through list at alpha 0 would still take the mouse).
function ns.QuestList_ApplyAlpha()
	if not frame then
		return
	end
	local a = 1
	if HiddenForCombat() then
		a = 0
	elseif inCombat and db.combat == "fade" then
		a = db.combatAlpha
	end
	if db.mouseFade and not frame.hovered then
		a = math.min(a, IDLE_ALPHA)
	end
	if not frame:IsShown() then
		UI.TweenStop(frame, "alpha")
		frame:SetAlpha(a)
		return
	end
	UI.AlphaTo(frame, a, FADE_SECONDS, a == 0 and function()
		if HiddenForCombat() then
			Hide()
		end
	end or nil)
end

Hide = function()
	if frame then
		frame:Hide()
	end
	if ticker then
		ticker:Cancel()
		ticker = nil
	end
	shown = {}
end

-- Data --------------------------------------------------------------------------------------------------------------

local function Yards(from, to)
	if not (from and to) or from.continent ~= to.continent then
		return nil
	end
	local dx, dy = from.x - to.x, from.y - to.y
	return math.sqrt(dx * dx + dy * dy)
end

-- This character's saved quest choices: hidden (on the Hidden line) and folded (from the quest's menu).
local function Char()
	local guid = UnitGUID("player")
	local char = db.chars[guid]
	if not char then
		char = { hidden = {}, folded = {} }
		db.chars[guid] = char
	end
	return char
end

-- Each quest's objectives, and what moved since the last update (flash), what just completed (justDone) and when it
-- last made progress (for auto-fold).
local function Annotate(quests, you)
	local now = GetTime()
	for _, q in ipairs(quests) do
		local id = q.questID
		q.objectives = ns.QuestListRead_Objectives(id)
		local before = seen[id]
		local after = { have = {}, complete = q.complete, changed = before and before.changed or now }
		q.flash = nil
		for k, obj in ipairs(q.objectives) do
			after.have[k] = obj.have
			if before and obj.have and before.have[k] and obj.have > before.have[k] then
				q.flash = q.flash or {}
				q.flash[k] = true
				after.changed = now
			end
		end
		q.justDone = before ~= nil and q.complete and not before.complete or nil
		if q.justDone then
			after.changed = now
		end
		seen[id] = after
		q.folded = ns.QuestList_QuestFolded(Char().folded[id], db.autoFold, after.changed, now)
		q.yards = Yards(you, points[id])
	end
end

-- Choices saved for quests no longer in the log go.
local function Prune(quests)
	local inLog = {}
	for _, q in ipairs(quests) do
		inLog[q.questID] = true
	end
	local char = Char()
	for _, set in ipairs({ char.hidden, char.folded }) do
		for id in pairs(set) do
			if not inLog[id] then
				set[id] = nil
			end
		end
	end
	for id in pairs(seen) do
		if not inLog[id] then
			seen[id] = nil
		end
	end
end

-- Follow-the-nearest: the nearest stop's top quest becomes Tomte's active quest when it changes (a quest you pick
-- yourself stays until then: picking one lets go of the follow, ns.ActiveQuest_Follow). Never the game's active quest:
-- setting that from here tainted the objective tracker and the map's quest log (see ns.ActiveQuest_Follow).
local function Follow(q)
	if not q then
		return
	end
	-- Your own map pin (or corpse) is what you're heading for: hands off. Forgotten, so the nearest quest is followed
	-- again as soon as the pin goes.
	if ns.OwnTargetTracked() then
		if followed then
			followed = nil
			ns.ActiveQuest_Follow(nil)
		end
		return
	end
	if q.questID == followed then
		return
	end
	followed = q.questID
	ns.ActiveQuest_Follow(q.questID)
end

-- Hidden in combat counts once the fade out has hidden it (ApplyAlpha); until then the list keeps drawing.
local function HiddenNow()
	return (HiddenForCombat() and not (frame and frame:IsShown()))
		or (db.hideInstances and ns.QuestListRead_InInstance())
end

local Tick

-- A stop in the zone you're in is named by the way it lies from you (its nearest quest); elsewhere by its zone.
local function NameStop(s, you, nearestPoint, here)
	s.zoneName = s.zoneName or s.title
	if you and nearestPoint and axes and s.zoneName == here then
		local dx, dy = nearestPoint.x - you.x, nearestPoint.y - you.y
		s.title = ns.QuestList_Compass(dx * axes.ex + dy * axes.ey, dx * axes.nx + dy * axes.ny, s.distance)
	else
		s.title = s.zoneName
	end
end

-- Each shown quest's yards, and each stop's distance (its nearest quest) and name.
local function Distances(you, redraw)
	local here = ns.QuestListRead_Zone()
	for _, s in ipairs(shown) do
		local nearest, nearestPoint
		for _, q in ipairs(s.quests) do
			q.yards = Yards(you, points[q.questID])
			if q.yards and (not nearest or q.yards < nearest) then
				nearest, nearestPoint = q.yards, points[q.questID]
			end
		end
		if s.kind == "stop" then
			s.distance = nearest or s.distance
			NameStop(s, you, nearestPoint, here)
		end
	end
	if redraw ~= false then
		ns.QuestListUI_Distances(frame)
	end
end

local function Folds()
	local merged = {}
	for key, v in pairs(db.folded) do
		if not key:find("^stop:") then
			merged[key] = v
		end
	end
	for key, v in pairs(stopFolds) do
		merged[key] = v
	end
	return merged
end

-- The sections to draw, from the quests and stops just read.
local function Sections(quests, stops)
	return ns.QuestList_Sections(quests, stops, {
		show = db.show, groupBy = db.groupBy, zone = ns.QuestListRead_Zone(), turnInsFirst = db.turnInsFirst,
		open = db.open, stops = db.stops, perSection = db.perSection, folded = Folds(), expanded = expanded,
		hidden = Char().hidden, instance = ns.QuestListRead_Instance(),
	})
end

local function Update()
	if not active then
		Hide()
		return
	end
	if HiddenNow() and not ns.EditMode_Active() then
		Hide()
		return
	end
	local you, mapID = ns.LevelingRead_You()
	if pointsStale or pointsMap ~= mapID then
		points, pointsMap, pointsStale = mapID and ns.LevelingRead_QuestPoints(mapID) or {}, mapID, false
	end
	local quests = ns.LevelingRead_QuestsTagged()
	Prune(quests)
	Annotate(quests, you)
	local stops = db.groupBy == "stop" and ns.Leveling_NextStops(quests, points, you, IsInGroup(), CLUSTER_YARDS) or {}
	local sections = Sections(quests, stops)
	-- A new active quest (picked on the map, in the quest log or here): a fold you clicked on its group goes, so it
	-- shows (Data.lua opens the group holding the active quest and puts the quest first).
	local activeID = ns.ActiveQuest_ID()
	if activeID ~= lastActive then
		lastActive = activeID
		for _, s in ipairs(sections) do
			for _, q in ipairs(s.quests) do
				if q.questID == activeID and s.kind ~= "hidden" and (stopFolds[s.key] ~= nil or db.folded[s.key] ~= nil) then
					stopFolds[s.key], db.folded[s.key] = nil, nil
					sections = Sections(quests, stops)
				end
			end
		end
	end
	-- Somewhere new (another stop is nearest): the fold clicks made on the old stops go.
	local first = sections[1] and sections[1].kind == "stop" and sections[1].key or nil
	if first ~= nearestKey then
		nearestKey = first
		if next(stopFolds) then
			wipe(stopFolds)
			sections = Sections(quests, stops)
		end
	end
	local _, zoneMap = ns.QuestListRead_Zone()
	if zoneMap ~= axesMap then
		axes, axesMap = zoneMap and ns.QuestListRead_Axes(zoneMap), zoneMap
	end
	shown = sections
	Distances(you, false)
	if #sections == 0 and not ns.EditMode_Active() then
		Hide()
		return
	end
	if db.follow then
		Follow(ns.QuestList_FollowQuest(sections))
	elseif followed then -- turned off in the settings
		followed = nil
		ns.ActiveQuest_Follow(nil)
	end
	if not frame then
		Build()
	end
	drawnAt, distanceAt = you, you
	frame:SetScale(db.scale)
	ns.QuestListUI_Draw(frame, sections, #quests, ns.QuestListSpoken_Speaking())
	frame:Show()
	ns.QuestList_ApplyAlpha()
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
		Update()
	end)
end

-- The followed quest or the game's active quest changed: the active quest's mark moves.
ns.ActiveQuest_OnChange(function()
	if active then
		UpdateSoon()
	end
end)

-- Distances only: each shown quest's yards and each stop's (its nearest quest).
Tick = function()
	if not (frame and frame:IsShown()) then
		return
	end
	local you = ns.LevelingRead_You()
	if not you then
		return -- no position (an instance): nothing to measure
	end
	local moved = drawnAt and Yards(drawnAt, you) or math.huge
	if db.groupBy == "stop" and moved >= MOVE_REDRAW then
		Update()
	elseif Yards(distanceAt, you) == nil or Yards(distanceAt, you) >= MOVE_DISTANCE then
		distanceAt = you
		Distances(you)
	end
end

-- Clicks (from List.lua) ------------------------------------------------------------------------------------------

-- Hidden from the list or back (Tomte's own choice; what the game tracks stays as it is).
local function ToggleHidden(q)
	local hidden = Char().hidden
	hidden[q.questID] = not hidden[q.questID] or nil
	UI.Sound("pick")
	Update()
end

-- Click: the active quest. Shift-click: hidden from the list, or back.
function ns.QuestList_QuestClick(q)
	if IsShiftKeyDown() then
		ToggleHidden(q)
		return
	end
	ns.LevelingPage_QuestClick(q, UpdateSoon)
end

-- The tooltip's line for Shift-click (List.lua shows Leveling's quest tooltip with it).
function ns.QuestList_ShiftLine(q)
	return Char().hidden[q.questID] and "Shift-click to show it in the list" or "Shift-click to hide it from the list"
end

function ns.QuestList_ToggleSection(key)
	for _, s in ipairs(shown) do
		if s.key == key then
			if s.kind == "stop" then
				stopFolds[key] = s.open
			else
				db.folded[key] = s.open
			end
			break
		end
	end
	Update()
end

function ns.QuestList_ExpandSection(key)
	expanded[key] = true
	Update()
end

function ns.QuestList_ToggleFollow()
	db.follow = not db.follow
	followed = nil -- turned on: the nearest quest is followed right away
	if not db.follow then
		ns.ActiveQuest_Follow(nil)
	end
	Update()
end

function ns.QuestList_ToggleCollapsed()
	db.collapsed = not db.collapsed
	Update()
end

-- The quest's text, objectives and rewards in Blizzard's own quest details window (the one its quest log opens), not
-- the world map: opening the map from code taints it (see ns.MapTabs_Opener). The window keeps the quest in its own
-- field, which Blizzard clears when it closes. Out of combat only: it's a UI panel, and in combat the map reads that
-- field while doing protected things.
local function ShowDetails(q)
	if InCombatLockdown() then
		ns.Print("The quest's details open after combat: try again then.")
		return
	end
	QuestLogPopupDetailFrame:ShowQuest(q.questID)
end

local function Abandon(q)
	ns.Confirm_Show(("Abandon %s?"):format(q.title or "this quest"), function()
		C_QuestLog.SetSelectedQuest(q.questID)
		C_QuestLog.SetAbandonQuest()
		C_QuestLog.AbandonQuest()
	end)
end

function ns.QuestList_Menu(owner, q)
	UI.ContextMenu(owner, function(_, root)
		root:CreateTitle(q.title or "?")
		if QuestLogPopupDetailFrame and QuestLogPopupDetailFrame.ShowQuest then
			root:CreateButton("Show details", function()
				ShowDetails(q)
			end)
		end
		if C_SuperTrack and not q.active then
			root:CreateButton("Make active", function()
				ns.SafeTrack(function()
					ns.LevelingPage_MakeActive(q.questID)
				end)
				UpdateSoon()
			end)
		end
		root:CreateButton(q.watched and "Stop tracking" or "Track", function()
			ns.SafeTrack(function()
				if C_QuestLog.GetQuestWatchType(q.questID) then
					C_QuestLog.RemoveQuestWatch(q.questID)
				else
					C_QuestLog.AddQuestWatch(q.questID)
				end
			end)
			UpdateSoon()
		end)
		root:CreateButton(q.folded and "Show objectives" or "Fold to its title", function()
			Char().folded[q.questID] = not q.folded
			Update()
		end)
		root:CreateButton(Char().hidden[q.questID] and "Show in the list" or "Hide from the list", function()
			ToggleHidden(q)
		end)
		if C_QuestLog.SetSelectedQuest and C_QuestLog.SetAbandonQuest and C_QuestLog.AbandonQuest then
			root:CreateDivider()
			root:CreateButton("Abandon", function()
				Abandon(q)
			end)
		end
	end)
end

-- Events ----------------------------------------------------------------------------------------------------------

local function QuestsChanged()
	pointsStale = true
	UpdateSoon()
end

local function CombatStart()
	inCombat = true
	ns.QuestList_ApplyAlpha()
end

local function CombatEnd()
	inCombat = false
	ns.QuestList_ApplyAlpha()
	UpdateSoon() -- shows it again if combat hid it; it fades in from where the fade out left it
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
	USER_WAYPOINT_UPDATED = UpdateSoon, -- a pin placed or removed: follow steps aside or picks up again
	PLAYER_REGEN_DISABLED = CombatStart,
	PLAYER_REGEN_ENABLED = CombatEnd,
}
for event, fn in pairs(WATCHED) do
	events:On(OWNER, event, fn)
end

-- Spoken's queue changed: the quest it reads gets its marker (the buttons follow the queue themselves).
local function SpokenChanged()
	if active and frame and frame:IsShown() and db.speaking then
		UpdateSoon()
	end
end

local function Start()
	active = true
	inCombat = InCombatLockdown()
	for event in pairs(WATCHED) do
		events:Watch(OWNER, event)
	end
	ns.QuestListSpoken_Start(SpokenChanged)
	ApplyTracker()
	if ns.LevelingNext_Update then
		ns.LevelingNext_Update()
	end
	pointsStale = true
	UpdateSoon()
end

local function Stop()
	active = false
	events:UnwatchAll(OWNER)
	ns.QuestListSpoken_Stop()
	ApplyTracker()
	Hide()
	if followed then
		ns.ActiveQuest_Follow(nil)
	end
	followed = nil
	wipe(seen)
	if ns.LevelingNext_Update then
		ns.LevelingNext_Update()
	end
end

ns.EditMode_Register({
	name = "Quest list",
	frame = function()
		return frame
	end,
	refresh = function()
		Update()
	end,
	saved = function()
		db.frame.point = UI.TopLeftPoint(frame)
	end,
	module = "questlist",
	options = { "scale", "width" },
	reset = function()
		db.frame.point = nil
		if frame then
			Place()
		end
	end,
})

-- Commands --------------------------------------------------------------------------------------------------------

local function Why()
	ns.Print(("Quest list: game's tracker %s, grouped by %s, showing %s quests."):format(
		ns.QuestListTracker_State(), db.groupBy, db.show))
	local ok, why = ns.QuestListSpoken_Status()
	if ns.QuestListSpoken_Installed() then
		print(ok and "  Spoken: Play buttons on." or ("  Spoken: no Play buttons (" .. tostring(why) .. ")."))
	end
	for i, s in ipairs(shown) do
		local names = {}
		for k, q in ipairs(s.quests) do
			names[k] = q.title or "?"
		end
		print(("  %d. %s (%s, %s): %s"):format(i, s.title, s.kind, s.open and "open" or "folded",
			table.concat(names, ", ")))
		for k = 1, s.shown do
			local play = ns.QuestListSpoken_Why(s.quests[k].questID)
			if play then
				print(("     %s: Play %s"):format(s.quests[k].title or "?", play))
			end
		end
	end
end

-- Options ---------------------------------------------------------------------------------------------------------

local function Redraw()
	Update()
end

local function Preview(host)
	return ns.QuestListUI_Preview(host)
end

local function Choices(list)
	return function()
		return list
	end
end

local function Percent(v)
	return ("%d%%"):format(math.floor(v * 100 + 0.5))
end

module = ns.RegisterModule({
	key = "questlist",
	name = "Quest list",
	category = "quests",
	icon = ICON,
	summary = "Your quests grouped by where they are, in place of the game's quest tracker.",
	description = "Replaces the game's quest tracker with a list grouped by where your quests are: the nearest stop "
		.. "first, turn-ins on top, objectives as bars, and how far each quest is. Click a quest to make it your active "
		.. "quest, Shift-click to hide it on a folded Hidden line, right-click for more. With Spoken installed, each "
		.. "quest gets its Play button. Turn it off and the game's tracker comes back.",
	enabledByDefault = false,
	keep = { "chars" },
	noShare = { "chars" },
	uses = { { addon = "Spoken", why = "a Play button on each quest", without = "no Play buttons" } },
	conflicts = { { addon = "EllesmereUIQuestTracker", why = "it has its own quest tracker; the Quest list stays off while it's enabled" } },
	alongside = { { addon = "MelloUI", why = "the Quest list stays off while MelloUI's own Quest Tracker is on" } },
	blocked = function()
		if ns.Ellesmere_Loaded("QuestTracker") then
			return "Off while EllesmereUI's quest tracker is enabled."
		end
		if ns.Mello_On("QuestTracker") then
			return "Off while MelloUI's Quest Tracker is on (/mello)."
		end
	end,
	defaults = {
		show = "all", -- "all" | "tracked"
		groupBy = "stop", -- "stop" | "zone" | "list"
		follow = true,
		open = 1, -- sections shown open
		stops = 3, -- nearest stops with a group of their own; the rest share Other quests
		turnInsFirst = true,
		perSection = 6, -- quests per section before "+N more"
		width = 280,
		scale = 1,
		maxHeight = 600, -- taller lists scroll
		objectives = "bars", -- "bars" | "text"
		level = "colored", -- "colored" | "plain" | "hidden"
		background = "none", -- "none" | "faint" | "panel"
		doneObjectives = "dim", -- "dim" | "green" | "hide"
		animate = true,
		glow = true,
		combat = "fade", -- "show" | "fade" | "hide"
		combatAlpha = 0.4,
		mouseFade = false,
		hideInstances = false,
		autoFold = false,
		xp = true,
		distance = true,
		metric = false,
		spoken = true,
		speaking = true,
		collapsed = false,
		folded = {}, -- [section key] = true (folded) | false (opened), the player's own clicks
		chars = {}, -- [player GUID] = { hidden = { [questID] = true }, folded = { [questID] = true | false } }
		frame = {}, -- point: the list's spot (UI.TopLeftPoint), nil for the default
	},
	init = function(moduleDB)
		db = moduleDB
	end,
	toggle = function(on)
		if on then
			Start()
		else
			Stop()
		end
	end,
	commands = {
		{ "why", "how the Quest list groups your quests right now, and whether Spoken's buttons work", function()
			if ns.Module_RequireOn(module) then
				Why()
			end
		end },
		{ "reset", "put the Quest list back in its default spot", function()
			db.frame.point = nil
			if frame then
				Place()
			end
		end },
	},
	options = {
		{ type = "header", label = "Layout" },
		{ type = "dropdown", key = "show", label = "Show", onChange = Redraw, preview = Preview,
			choices = Choices({ { value = "all", text = "All quests" }, { value = "tracked", text = "Tracked only" } }),
			tooltip = "All quests: every quest in your log. Tracked only: the quests the game tracks, as its own tracker shows them. Either way, Shift-click a quest to put it on the folded Hidden line at the bottom, and again to bring it back." },
		{ type = "dropdown", key = "groupBy", label = "Group by", onChange = Redraw, preview = Preview,
			choices = Choices({ { value = "stop", text = "Nearby stop" }, { value = "zone", text = "Zone" },
				{ value = "list", text = "Nothing" } }),
			tooltip = "Nearby stop: quests close to each other are one stop, the nearest first, as in Leveling's Next quests. The nearest few get a group each; the rest wait in Other quests." },
		{ type = "checkbox", key = "follow", label = "Follow the nearest quest", onChange = Redraw,
			tooltip = "The top quest of the nearest stop becomes your active quest in Tomte (marked in the list, and Waypoints' arrow points to it) each time a new one comes to the top. A quest you pick yourself, here or on the map, stays active until then. The game's own map and tracker keep the quest you picked there." },
		{ type = "slider", key = "open", label = "Groups shown open", min = 1, max = 5, step = 1, onChange = Redraw,
			preview = Preview, tooltip = "The rest show as one line each. Click a group's name to open or fold it." },
		{ type = "slider", key = "stops", label = "Stops listed", min = 1, max = 8, step = 1, onChange = Redraw,
			shown = function()
				return db.groupBy == "stop"
			end, tooltip = "The nearest stops get a group each. Quests farther away, and those no stop takes (hard and grey quests, quests with no spot on the map), wait in one folded Other quests group, nearest first." },
		{ type = "checkbox", key = "turnInsFirst", label = "Turn-ins on top", onChange = Redraw },
		{ type = "slider", key = "perSection", label = "Quests per group", min = 3, max = 15, step = 1,
			onChange = Redraw, tooltip = "Past this, a \"+ more\" line shows the rest when clicked." },
		{ type = "slider", key = "width", label = "Width", min = 220, max = 400, step = 10, onChange = Redraw,
			preview = Preview },
		{ type = "slider", key = "scale", label = "Size", min = 0.7, max = 1.3, step = 0.05, format = Percent,
			onChange = Redraw, preview = Preview },
		{ type = "slider", key = "maxHeight", label = "Highest", min = 300, max = 900, step = 50, onChange = Redraw,
			tooltip = "Taller lists scroll with the mouse wheel." },
		{ type = "button", label = "Position", text = "Reset", onClick = function()
			db.frame.point = nil
			if frame then
				Place()
			end
		end, tooltip = "Move the list back to the right side of the screen. Blizzard's Edit Mode moves it too." },

		{ type = "header", label = "Look" },
		{ type = "dropdown", key = "objectives", label = "Objectives", onChange = Redraw, preview = Preview,
			choices = Choices({ { value = "bars", text = "Bars" }, { value = "text", text = "Text" } }),
			tooltip = "Bars: a thin bar under objectives with a count above one, such as 4/6." },
		{ type = "dropdown", key = "level", label = "Quest level", onChange = Redraw, preview = Preview,
			choices = Choices({ { value = "colored", text = "Colored" }, { value = "plain", text = "Plain" },
				{ value = "hidden", text = "Hidden" } }),
			tooltip = "Colored: by how hard the quest is for you, as in the quest log." },
		{ type = "dropdown", key = "background", label = "Background", onChange = Redraw, preview = Preview,
			choices = Choices({ { value = "none", text = "None" }, { value = "faint", text = "Faint" },
				{ value = "panel", text = "Panel" } }) },
		{ type = "dropdown", key = "doneObjectives", label = "Finished objectives", onChange = Redraw,
			preview = Preview, choices = Choices({ { value = "dim", text = "Dimmed" }, { value = "green", text = "Green" },
				{ value = "hide", text = "Hidden" } }) },
		{ type = "checkbox", key = "glow", label = "Highlight the active quest", onChange = Redraw, preview = Preview },
		{ type = "checkbox", key = "animate", label = "Flash on progress",
			tooltip = "An objective's count flashes when it goes up, and a quest flashes green when it's done." },

		{ type = "header", label = "When it shows" },
		{ type = "dropdown", key = "combat", label = "In combat", onChange = Redraw,
			choices = Choices({ { value = "show", text = "Show" }, { value = "fade", text = "Fade" },
				{ value = "hide", text = "Hide" } }) },
		{ type = "slider", key = "combatAlpha", label = "Faded to", min = 0.1, max = 0.9, step = 0.05, format = Percent,
			onChange = Redraw, shown = function()
				return db.combat == "fade"
			end },
		{ type = "checkbox", key = "mouseFade", label = "Faded until the mouse is on it", onChange = function()
			ns.QuestList_ApplyAlpha()
		end },
		{ type = "checkbox", key = "hideInstances", label = "Hide in dungeons and raids", onChange = Redraw },
		{ type = "checkbox", key = "autoFold", label = "Fold quests you leave alone", onChange = Redraw,
			tooltip = "A quest with no progress for 30 minutes shows only its title. Right-click a quest to fold or unfold it yourself." },

		{ type = "header", label = "Details" },
		{ type = "checkbox", key = "xp", label = "XP each quest gives", onChange = Redraw, preview = Preview },
		{ type = "checkbox", key = "distance", label = "Distance to each quest", onChange = Redraw, preview = Preview },
		{ type = "checkbox", key = "metric", label = "Distances in meters", onChange = Redraw,
			tooltip = "Meters and kilometers instead of the game's yards." },

		{ type = "header", label = "Spoken", shown = function()
			return ns.QuestListSpoken_Installed()
		end },
		{ type = "checkbox", key = "spoken", label = "Play buttons", onChange = Redraw, shown = function()
			return ns.QuestListSpoken_Installed()
		end, tooltip = function()
			local ok, why = ns.QuestListSpoken_Status()
			return ok and "Spoken's Play button on each quest it has a recording for. Spoken's own setting for tracker buttons turns them off too."
				or ("This Spoken version isn't supported, so there are no Play buttons (" .. tostring(why) .. ").")
		end },
		{ type = "checkbox", key = "speaking", label = "Mark the quest being read", onChange = Redraw,
			shown = function()
				return ns.QuestListSpoken_Installed()
			end, tooltip = "The quest Spoken is reading gets a blue title while it speaks." },
	},
})
