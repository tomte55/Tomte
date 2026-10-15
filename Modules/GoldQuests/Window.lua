local addonName, ns = ...

-- Gold world quests window: an on-screen widget like the Crafting list and Almost Done (subtle panel, no border; not
-- closed by Esc). Drag the title to move it, the corner grip to
-- resize it, the minus folds it to its title. Two views: Gold (gold world quests by zone, special assignments,
-- weekly caches, each a folding section) and Characters (world quest gold and caches per character). Rows are plain
-- frames: tracking goes through ns.SafeTrack, nothing here is protected. Gold.lua owns the data and the route.

local UI = ns.UI
local DEFAULT_W, DEFAULT_H = 380, 460
local MIN_W, MIN_H, MAX_W, MAX_H = 330, 180, 720, 1000
local TITLE_H = 48
local FOLDED_H = 26
local HEAD_H, ZONE_H, ROW_H, LINE_H = 24, 20, 20, 18
local LEFT_W = 66 -- gold amount / state column
local LOADING_TICK, CLOCK_TICK = 2, 30
local TIME_ROLES = { critical = "danger", low = "warning", normal = "textMuted" }
local STATE_TEXT = { done = "Done", up = "Up", locked = "Locked" }
local STATE_ROLES = { done = "success", up = "accent", locked = "warning" }
local SECTIONS = {
	quests = "Gold world quests",
	assignments = "Special assignments",
	caches = "Weekly caches",
}

local db
local frame
local rows, used = {}, 0
local expanded = {} -- [guid] = true: characters unfolded in the Characters view (this session)
local tick, clock = 0, 0
local Draw

-- Actions ---------------------------------------------------------------------------------------------------------

local function IsTracked(questID)
	return C_SuperTrack.GetSuperTrackedQuestID() == questID
end

local function ToggleTrack(questID)
	if IsTracked(questID) then
		ns.SafeTrack(function()
			C_SuperTrack.SetSuperTrackedQuestID(0)
		end)
	else
		ns.WQ_Track({ id = questID })
	end
end

local function OpenMap(mapID)
	if not mapID then
		return
	end
	if InCombatLockdown() then
		ns.Print("not in combat.")
		return
	end
	if not WorldMapFrame:IsShown() then
		ToggleWorldMap()
	end
	WorldMapFrame:SetMapID(mapID)
end

-- A locked special assignment: a map pin on its spot (the placeholder quest's or the POI's).
local function PinAssignment(a)
	local x, y = a.x, a.y
	if not x and a.unlock and a.zoneID then
		x, y = C_TaskQuest.GetQuestLocation(a.unlock, a.zoneID)
	end
	if x and y and a.zoneID and C_Map.CanSetUserWaypointOnMap(a.zoneID) then
		ns.TrackPin(a.zoneID, x, y)
	elseif a.unlock then
		ns.WQ_Track({ id = a.unlock })
	end
end

-- Tooltips --------------------------------------------------------------------------------------------------------

local Line = UI.TipLine

local function QuestTooltip(row, q)
	GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
	GameTooltip:SetText(q.title, UI.Color("heading"))
	local tags = ns.WQ_Tags(q)
	Line(q.zone .. (tags ~= "" and ("  ·  " .. tags) or ""), "textMuted")
	local time, tier = ns.WQ_TimeText(q.seconds)
	if time then
		Line(time .. " left", TIME_ROLES[tier])
	end
	Line(" ")
	Line(ns.WQ_FormatGold(q.money), "heading")
	for _, item in ipairs(q.items) do
		Line((item.count or 1) > 1 and (item.count .. " " .. item.name) or item.name)
	end
	for _, c in ipairs(q.currencies) do
		Line(("%d %s"):format(c.amount or 0, c.name or "?"))
	end
	for _, r in ipairs(q.reps) do
		Line(("+%d %s"):format(r.amount or 0, r.name or "?"))
	end
	local stop = ns.WQRoute_Index(q.id)
	if stop then
		Line(" ")
		Line(("Route stop %d"):format(stop), "accent")
	end
	Line(" ")
	Line(IsTracked(q.id) and "Click: stop tracking" or "Click: track it", "textMuted")
	Line("Right-click: open its zone on the map", "textMuted")
	Line("Shift-click: link in chat", "textMuted")
	GameTooltip:Show()
end

local function AssignmentTooltip(row, a)
	GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
	GameTooltip:SetText(a.title, UI.Color("heading"))
	Line(a.zone, "textMuted")
	Line(STATE_TEXT[a.state], STATE_ROLES[a.state])
	if a.state == "locked" then
		if a.have and a.need then
			Line(("%d of %d world quests done to unlock it"):format(a.have, a.need))
		else
			Line("Unlocks after more world quests in its zone.", "textMuted")
		end
	end
	local time, tier = ns.WQ_TimeText(a.seconds)
	if time then
		Line(time .. " left", TIME_ROLES[tier])
	end
	if a.state == "up" then
		Line(" ")
		Line(IsTracked(a.quest) and "Click: stop tracking" or "Click: track it", "textMuted")
	elseif a.state == "locked" then
		Line(" ")
		Line("Click: map pin on it", "textMuted")
	end
	GameTooltip:Show()
end

local function CacheTooltip(row, c)
	GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
	GameTooltip:SetText(c.label, UI.Color("heading"))
	if c.done then
		Line("Done this week", "success")
		for _, name in ipairs(ns.Gold_CacheDoneNames(c.cache, ns.Gold_TurnedIn())) do
			Line("  " .. name, "textMuted")
		end
	else
		Line("Not done this week", "danger")
		if ns.Gold_TrackingFresh() then
			Line("Tomte started tracking this week: it may be done already.", "textMuted", true)
		end
	end
	Line(" ")
	Line("Right-click: hide this row (the module's settings bring it back)", "textMuted", true)
	GameTooltip:Show()
end

-- Rows ------------------------------------------------------------------------------------------------------------

local function OnRowEnter(self)
	local d = self.data
	if not d then
		return
	end
	self.hover:Show()
	if d.kind == "quest" then
		QuestTooltip(self, d.q)
	elseif d.kind == "assignment" then
		AssignmentTooltip(self, d.a)
	elseif d.kind == "cache" then
		CacheTooltip(self, d.c)
	end
end

local function OnRowLeave(self)
	self.hover:Hide()
	GameTooltip:Hide()
end

local function OnRowClick(self, button)
	local d = self.data
	if not d then
		return
	end
	if d.kind == "header" then
		db.collapsed[d.key] = not db.collapsed[d.key]
		Draw()
	elseif d.kind == "char" then
		expanded[d.guid] = not expanded[d.guid]
		Draw()
	elseif d.kind == "quest" then
		if button == "RightButton" then
			OpenMap(d.q.zoneID)
		elseif IsShiftKeyDown() then
			UI.InsertLink(GetQuestLink(d.q.id))
		else
			ToggleTrack(d.q.id)
			Draw()
		end
	elseif d.kind == "assignment" then
		if d.a.state == "up" then
			ToggleTrack(d.a.quest)
			Draw()
		elseif d.a.state == "locked" then
			PinAssignment(d.a)
		end
	elseif d.kind == "cache" and button == "RightButton" then
		db.hiddenCaches[d.c.key] = true
		GameTooltip:Hide()
		ns.GoldWindow_Refresh()
	end
end

local function NewRow()
	local row = CreateFrame("Button", nil, frame.scroll.content)
	row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	row.hover = row:CreateTexture(nil, "BACKGROUND")
	row.hover:SetAllPoints()
	row.hover:SetColorTexture(UI.Color("hover"))
	row.hover:Hide()
	row.tracked = row:CreateTexture(nil, "ARTWORK")
	row.tracked:SetColorTexture(UI.RGBA("accent", 0.9))
	row.tracked:SetWidth(2)
	row.tracked:SetPoint("TOPLEFT", 0, -2)
	row.tracked:SetPoint("BOTTOMLEFT", 0, 2)
	row.left = UI.Text(row, 12, "heading", "number")
	row.left:SetJustifyH("RIGHT")
	row.left:SetWordWrap(false)
	row.right = UI.Text(row, 11, "textMuted", "number")
	row.right:SetJustifyH("RIGHT")
	row.right:SetPoint("RIGHT", -6, 0)
	row.name = UI.Text(row, 12, "text")
	row.name:SetWordWrap(false)
	row.name:SetPoint("RIGHT", row.right, "LEFT", -6, 0)
	row.line = row:CreateTexture(nil, "ARTWORK")
	row.line:SetColorTexture(UI.RGBA("frame", 0.4))
	row.line:SetHeight(1)
	row.line:SetPoint("BOTTOMLEFT", 6, 1)
	row.line:SetPoint("BOTTOMRIGHT", -6, 1)
	row:SetScript("OnEnter", OnRowEnter)
	row:SetScript("OnLeave", OnRowLeave)
	row:SetScript("OnClick", OnRowClick)
	return row
end

-- A row at y with the given height and indent. left: text in the fixed column (nil hides the column).
local function Row(y, height, indent, data)
	used = used + 1
	local row = rows[used] or NewRow()
	rows[used] = row
	row:SetHeight(height)
	row:ClearAllPoints()
	row:SetPoint("TOPLEFT", 0, -y)
	row:SetPoint("RIGHT")
	row.data = data
	row:EnableMouse(data ~= nil)
	row.tracked:Hide()
	row.line:Hide()
	row.left:Hide()
	UI.SetFont(row.left, "number", 12)
	row.right:SetText("")
	UI.SetTextRole(row.right, "textMuted")
	row.name:ClearAllPoints()
	row.name:SetPoint("LEFT", 8 + indent, 0)
	row.name:SetPoint("RIGHT", row.right, "LEFT", -6, 0)
	row.name:SetWordWrap(false)
	UI.SetFont(row.name, "body", 12)
	UI.SetTextRole(row.name, "text")
	row:Show()
	return row
end

local function SetLeft(row, text, role, indent)
	row.left:ClearAllPoints()
	row.left:SetPoint("LEFT", 8 + indent, 0)
	row.left:SetWidth(LEFT_W)
	row.left:SetText(text)
	UI.SetTextRole(row.left, role)
	row.left:Show()
	row.name:ClearAllPoints()
	row.name:SetPoint("LEFT", row.left, "RIGHT", 10, 0)
	row.name:SetPoint("RIGHT", row.right, "LEFT", -6, 0)
end

-- Layout ----------------------------------------------------------------------------------------------------------

local function Header(y, key, title, right)
	local collapsed = db.collapsed[key]
	local row = Row(y, HEAD_H, 0, { kind = "header", key = key })
	UI.SetFont(row.name, "title", 13)
	UI.SetTextRole(row.name, "heading")
	row.name:SetText((collapsed and "+ " or "- ") .. title)
	row.right:SetText(right or "")
	row.line:Show()
	return y + HEAD_H + 2, collapsed
end

-- A muted line that wraps (the row grows to fit it).
local function Note(y, text, indent)
	indent = indent or 8
	local row = Row(y, LINE_H, indent, nil)
	UI.SetTextRole(row.name, "textMuted")
	row.name:ClearAllPoints()
	row.name:SetPoint("TOPLEFT", 8 + indent, -2)
	row.name:SetWidth(math.max(frame.scroll.content:GetWidth() - indent - 16, 50))
	row.name:SetWordWrap(true)
	row.name:SetText(text)
	local height = math.max(LINE_H, math.ceil(row.name:GetStringHeight()) + 4)
	row:SetHeight(height)
	return y + height
end

local function DrawQuests(y, model)
	local group = model.group
	local collapsed
	local right = group.count > 0 and ("%d  ·  %s"):format(group.count, ns.Gold(group.total)) or ""
	if model.pending > 0 and group.count > 0 then
		right = UI.Wrap("loading…  ", "textFaint") .. right
	end
	y, collapsed = Header(y, "quests", SECTIONS.quests, right)
	if collapsed then
		return y + 4
	end
	if group.count == 0 then
		y = Note(y, model.pending > 0 and "Loading rewards…" or "None up right now.")
		if model.pending == 0 and model.expansion ~= ns.ContentExpansion() then
			y = Note(y, "An older expansion's world quests show once this character has unlocked them.")
		end
	end
	for _, zone in ipairs(group.zones) do
		local zoneRow = Row(y, ZONE_H, 4, nil)
		UI.SetTextRole(zoneRow.name, "heading")
		zoneRow.name:SetText(zone.name)
		zoneRow.right:SetText(("%d  ·  %s"):format(#zone.quests, ns.Gold(zone.total)))
		y = y + ZONE_H
		for _, q in ipairs(zone.quests) do
			local row = Row(y, ROW_H, 4, { kind = "quest", q = q })
			SetLeft(row, ns.WQ_FormatGold(q.money), "heading", 4)
			local stop = ns.WQRoute_Index(q.id)
			row.name:SetText(stop and (UI.Wrap(stop .. ".", "accent") .. " " .. q.title) or q.title)
			local time, tier = ns.WQ_TimeText(q.seconds)
			row.right:SetText(time or "")
			UI.SetTextRole(row.right, TIME_ROLES[tier or "normal"])
			row.tracked:SetShown(IsTracked(q.id))
			y = y + ROW_H
		end
	end
	return y + 6
end

local function DrawAssignments(y, model)
	if #model.assignments == 0 then
		return y
	end
	local collapsed
	y, collapsed = Header(y, "assignments", SECTIONS.assignments)
	if collapsed then
		return y + 4
	end
	for _, a in ipairs(model.assignments) do
		local row = Row(y, ROW_H, 4, { kind = "assignment", a = a })
		SetLeft(row, STATE_TEXT[a.state], STATE_ROLES[a.state], 4)
		UI.SetFont(row.left, "body", 12)
		row.name:SetText(a.title .. "  " .. UI.Wrap(a.zone, "textFaint"))
		if a.state == "locked" and a.have and a.need then
			row.right:SetText(("%d/%d"):format(a.have, a.need))
		elseif a.state ~= "done" then
			local time, tier = ns.WQ_TimeText(a.seconds)
			row.right:SetText(time or "")
			UI.SetTextRole(row.right, TIME_ROLES[tier or "normal"])
		end
		row.tracked:SetShown(a.quest ~= nil and IsTracked(a.quest))
		y = y + ROW_H
	end
	return y + 6
end

local function DrawCaches(y, model)
	if #model.caches == 0 then
		return y
	end
	local done = 0
	for _, c in ipairs(model.caches) do
		if c.done then
			done = done + 1
		end
	end
	local collapsed
	y, collapsed = Header(y, "caches", SECTIONS.caches, ("%d/%d"):format(done, #model.caches))
	if collapsed then
		return y + 4
	end
	for _, c in ipairs(model.caches) do
		local row = Row(y, ROW_H, 4, { kind = "cache", c = c })
		SetLeft(row, c.done and "Done" or "Not done", c.done and "success" or "danger", 4)
		UI.SetFont(row.left, "body", 12)
		row.name:SetText(c.label)
		UI.SetTextRole(row.name, c.done and "textMuted" or "text")
		y = y + ROW_H
	end
	return y + 6
end

local function DrawGold(model)
	if not model then
		return Note(0, "Tomte has no gold world quest data for " .. ns.ExpansionName(ns.ContentExpansion()) .. ".", 0)
	end
	local y = DrawQuests(0, model)
	y = DrawAssignments(y, model)
	return DrawCaches(y, model)
end

local function DrawChars()
	local now = GetServerTime()
	local list = ns.Gold_Characters(now)
	local y = 0
	if #list == 0 then
		return Note(0, "No characters yet. Each character shows up once it logs in at max level.", 0)
	end
	for _, entry in ipairs(list) do
		local char = entry.char
		local week, caches = ns.Gold_CharWeek(char, now)
		local row = Row(y, HEAD_H, 0, { kind = "char", guid = entry.guid })
		row.name:SetText((expanded[entry.guid] and "- " or "+ ") .. UI.ClassColored(char.name or "?", char.class)
			.. UI.Wrap("  " .. (char.realm or ""), "textFaint"))
		row.right:SetText(ns.Gold(week) .. " this week")
		UI.SetTextRole(row.right, week > 0 and "heading" or "textMuted")
		row.line:Show()
		y = y + HEAD_H + 2
		if expanded[entry.guid] then
			y = Note(y, ("Level %s  ·  %s from world quests in all"):format(char.level or "?",
				ns.Gold(char.totalCopper or 0)), 12)
			for _, cache in ipairs(ns.Content_Get(char.expansion, "caches") or {}) do
				local done = caches[cache.key] == true
				local line = Row(y, LINE_H, 12, nil)
				SetLeft(line, done and "Done" or "Not done", done and "success" or "danger", 12)
				UI.SetFont(line.left, "body", 11)
				line.name:SetText(ns.Gold_CacheLabel(cache))
				UI.SetTextRole(line.name, done and "textMuted" or "text")
				y = y + LINE_H
			end
			y = y + 6
		end
	end
	return y
end

function Draw()
	if not (frame and frame:IsShown()) or db.window.collapsed then
		return
	end
	local owner = GameTooltip:GetOwner()
	local ours = owner and owner.data ~= nil and owner:GetParent() == frame.scroll.content
	for i = 1, used do
		rows[i]:Hide()
		rows[i].data = nil
	end
	used = 0
	local model = ns.Gold_LastModel()
	local height
	local chars = db.view == "chars"
	frame.sub:SetShown(chars)
	frame.expansion:SetShown(not chars)
	if chars then
		frame.sub:SetText("World quest gold this week")
		frame.charsButton.label:SetText("Quests")
		height = DrawChars()
	else
		frame.expansion:Refresh()
		frame.charsButton.label:SetText("Characters")
		height = DrawGold(model)
	end
	frame.routeButton.label:SetText(ns.WQRoute_Active() and "Stop route" or "Route")
	UI.FitButton(frame.routeButton, 56, 16)
	UI.FitButton(frame.charsButton, 56, 16)
	frame.scroll:SetContentHeight(height)
	if ours then
		GameTooltip:Hide()
	end
	-- IsMouseOver ignores the scroll clipping: rows scrolled out of view lie over whatever is below the window.
	if not frame.scroll:IsMouseOver() then
		return
	end
	for i = 1, used do
		if rows[i].data and rows[i]:IsMouseOver() then
			OnRowEnter(rows[i])
		end
	end
end

-- Frame -----------------------------------------------------------------------------------------------------------

local function SavePlace()
	db.window.point = UI.TopLeftPoint(frame)
	if not db.window.collapsed then
		db.window.w, db.window.h = frame:GetSize()
	end
end

local function Place()
	frame:ClearAllPoints()
	local p = db.window.point
	if p then
		frame:SetPoint(p[1], UIParent, p[2], p[3], p[4])
	else
		frame:SetPoint("CENTER", UIParent, "CENTER", 300, 60)
	end
end

local function ApplyLook()
	frame:SetScale(db.scale or 1)
	if frame.themePanel then
		frame.themePanel:SetAlpha(db.opacity or 0.55)
	end
	local folded = db.window.collapsed
	frame.scroll:SetShown(not folded)
	frame.grip:SetShown(not folded)
	frame.sub:SetShown(not folded and db.view == "chars")
	frame.expansion:SetShown(not folded and db.view ~= "chars")
	frame.routeButton:SetShown(not folded)
	frame.charsButton:SetShown(not folded)
	frame.line:SetShown(not folded)
	frame.fold.label:SetText(folded and "+" or "-")
	if folded then
		frame:SetResizeBounds(MIN_W, FOLDED_H, MAX_W, FOLDED_H)
	else
		frame:SetResizeBounds(MIN_W, MIN_H, MAX_W, MAX_H)
	end
	frame:SetSize(db.window.w or DEFAULT_W, folded and FOLDED_H or (db.window.h or DEFAULT_H))
end

local function Build()
	frame = CreateFrame("Frame", "TomteGoldWindow", UIParent)
	frame:SetFrameStrata("MEDIUM")
	frame:SetClampedToScreen(true)
	frame:SetMovable(true)
	frame:SetResizable(true)
	frame:EnableMouse(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", frame.StartMoving)
	frame:SetScript("OnDragStop", function()
		frame:StopMovingOrSizing()
		SavePlace()
	end)
	frame:Hide()
	UI.Panel(frame, { alpha = db.opacity, subtle = true })

	local title = UI.Text(frame, 10, "textMuted", "label")
	title:SetPoint("TOPLEFT", 10, -8)
	title:SetText(ns.Spaced("Gold world quests"))
	local close = UI.Button(frame, 20, "x")
	close:SetPoint("TOPRIGHT", -4, -3)
	close:SetScript("OnClick", function()
		ns.GoldWindow_Hide()
	end)
	frame.fold = UI.Button(frame, 20, "-")
	frame.fold:SetPoint("RIGHT", close, "LEFT", -4, 0)
	frame.fold:SetScript("OnClick", function()
		if not db.window.collapsed then
			SavePlace()
		end
		db.window.collapsed = not db.window.collapsed
		ApplyLook()
		SavePlace()
		Draw()
	end)
	local settings = CreateFrame("Button", nil, frame)
	settings:SetSize(16, 16)
	settings:SetPoint("RIGHT", frame.fold, "LEFT", -6, 0)
	settings.icon = settings:CreateTexture(nil, "ARTWORK")
	settings.icon:SetAllPoints()
	settings.icon:SetTexture(UI.GEAR)
	settings.icon:SetTexCoord(0, 0.5, 0, 0.5)
	settings.icon:SetVertexColor(UI.RGB("textMuted"))
	settings:SetScript("OnEnter", function(self)
		self.icon:SetVertexColor(UI.RGB("accent"))
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		GameTooltip:SetText("Settings", 1, 1, 1)
		GameTooltip:Show()
	end)
	settings:SetScript("OnLeave", function(self)
		self.icon:SetVertexColor(UI.RGB("textMuted"))
		GameTooltip:Hide()
	end)
	settings:SetScript("OnClick", function()
		ns.Panel_OpenModule("wgq")
	end)

	frame.sub = UI.Text(frame, 11, "textMuted")
	frame.sub:SetPoint("TOPLEFT", 10, -28)
	frame.sub:SetWordWrap(false)
	frame.charsButton = UI.Button(frame, 80, "Characters")
	frame.charsButton:SetPoint("TOPRIGHT", -4, -24)
	frame.charsButton:SetScript("OnClick", function()
		db.view = db.view == "chars" and "gold" or "chars"
		frame.scroll:SetScroll(0)
		Draw()
	end)
	frame.routeButton = UI.Button(frame, 60, "Route")
	frame.routeButton:SetPoint("RIGHT", frame.charsButton, "LEFT", -4, 0)
	frame.routeButton:SetScript("OnClick", function()
		if ns.WQRoute_Active() then
			ns.WQRoute_Stop()
		else
			ns.Gold_StartRoute()
		end
		Draw()
	end)
	frame.routeButton:HookScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		if ns.WQRoute_Active() then
			GameTooltip:SetText("Stop the route", 1, 1, 1)
			if ns.WQRoute_Owner() ~= "wgq" then
				Line("Started in the World quests map tab.", "textMuted")
			end
		else
			GameTooltip:SetText("Route", 1, 1, 1)
			Line("Tracks the gold world quests one by one, nearest first from where you stand. Hand one in and the "
				.. "next is tracked.", "text", true)
		end
		GameTooltip:Show()
	end)
	frame.routeButton:HookScript("OnLeave", function()
		GameTooltip:Hide()
	end)
	frame.sub:SetPoint("RIGHT", frame.routeButton, "LEFT", -6, 0)
	frame.expansion = UI.Dropdown(frame, 140)
	frame.expansion:SetPoint("TOPLEFT", 6, -24)
	frame.expansion.choices = ns.Gold_ExpansionChoices
	frame.expansion.getValue = ns.Gold_ViewExpansion
	frame.expansion.setValue = function(value)
		ns.Gold_SetViewExpansion(value)
		frame.scroll:SetScroll(0)
		ns.GoldWindow_Refresh()
	end
	frame.line = UI.Hairline(frame, DEFAULT_W - 40, 0.5)
	frame.line:SetPoint("TOPLEFT", 10, -TITLE_H)
	frame.line:SetPoint("TOPRIGHT", -10, -TITLE_H)

	frame.scroll = UI.Scroll(frame)
	frame.scroll:SetPoint("TOPLEFT", 6, -TITLE_H - 4)
	frame.scroll:SetPoint("BOTTOMRIGHT", -14, 14)
	frame.scroll.onWidthChanged = function()
		Draw() -- notes wrap to the width
	end

	frame.grip = CreateFrame("Button", nil, frame)
	frame.grip:SetSize(14, 14)
	frame.grip:SetPoint("BOTTOMRIGHT", -3, 3)
	frame.grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
	frame.grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
	frame.grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
	frame.grip:SetScript("OnMouseDown", function()
		frame:StartSizing("BOTTOMRIGHT")
	end)
	frame.grip:SetScript("OnMouseUp", function()
		frame:StopMovingOrSizing()
		SavePlace()
	end)

	frame:SetScript("OnUpdate", function(_, elapsed)
		tick, clock = tick + elapsed, clock + elapsed
		if tick < LOADING_TICK then
			return
		end
		tick = 0
		local model = ns.Gold_LastModel()
		if (model and model.pending > 0) or clock >= CLOCK_TICK then
			clock = 0
			ns.GoldWindow_Refresh()
		end
	end)
	Place()
	ApplyLook()
end

-- API for Gold.lua ------------------------------------------------------------------------------------------------

function ns.GoldWindow_Init(moduleDB)
	db = moduleDB
end

-- A fresh scan and a redraw (only while shown).
function ns.GoldWindow_Refresh()
	if frame and frame:IsShown() then
		clock = 0
		ns.Gold_Scan()
		Draw()
	end
end

-- A redraw from the last scan.
function ns.GoldWindow_Redraw()
	Draw()
end

function ns.GoldWindow_Show()
	if not frame then
		Build()
	end
	db.window.shown = true
	frame:Show()
	ApplyLook()
	ns.GoldWindow_Refresh()
end

function ns.GoldWindow_Hide()
	db.window.shown = false
	if frame then
		frame:Hide()
		GameTooltip:Hide()
	end
end

function ns.GoldWindow_Toggle()
	if frame and frame:IsShown() then
		ns.GoldWindow_Hide()
	else
		ns.GoldWindow_Show()
	end
end

function ns.GoldWindow_IsShown()
	return frame ~= nil and frame:IsShown()
end

-- Scale and opacity settings.
function ns.GoldWindow_ApplyLook()
	if frame then
		ApplyLook()
	end
end

function ns.GoldWindow_ResetPlace()
	db.window.point, db.window.w, db.window.h, db.window.collapsed = nil, nil, nil, false
	if frame then
		Place()
		ApplyLook()
		Draw()
	end
end

-- Module off: hide without forgetting that it was open.
function ns.GoldWindow_Close()
	if frame then
		frame:Hide()
	end
end
