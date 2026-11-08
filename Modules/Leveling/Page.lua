local addonName, ns = ...

-- Leveling (World of Warcraft: Forever only): the page in the Tomte window. The XP block across the top; what's waiting,
-- the trainer's next level and weapon skills on the left; quests by what they're worth on the right (one column on a narrow
-- window). Redrawn when shown or when the game says something changed. Rules in Data.lua, reads in Read.lua; registered in
-- Leveling.lua.

local PAD = 8
local COL_GAP = 32
local TWO_COLUMNS = 640 -- content width from which the page is drawn in two columns
local LEFT_SHARE = 0.46
local BLOCK_GAP = 20
local HEAD_H = 32
local UPCOMING_ROWS = 6
local SKILL_H = 30
local SKILL_BAR_H = 4
local GROUP_H = 26
local GROUP_GAP = 10
local QUEST_H = 22
local LEVEL_W = 28 -- a quest's level, right-aligned, wide enough for "60+"
local MARK_W = 3 -- the active or tracked quest's bar, left of its level
local TRACK_W, TRACK_H = 78, 18 -- a group's Track all button, wide enough for "Untrack all"
local REFRESH_DELAY = 0.5 -- seconds: quest and bag events come in bursts

local UI = ns.UI
local Kit = ns.HomeKit

local page, c -- c: the scroll content
local heads, texts = {}, {}
local todoRows, upcomingRows, skillRows, groupRows, questRows = {}, {}, {}, {}, {}

-- "1,200 XP" or a price: the right-hand text of a to-do row (the page's and Home's).
function ns.Leveling_TodoRight(item)
	if item.xp then
		return ("%s XP"):format(ns.Thousands(item.xp))
	end
	return item.cost and item.cost > 0 and ns.Price(item.cost) or nil
end

local function Heading(key)
	heads[key] = heads[key] or Kit.Heading(c)
	heads[key]:Show()
	return heads[key]
end

local function Line(key)
	if not texts[key] then
		texts[key] = UI.Text(c, 12, "textMuted")
		texts[key]:SetJustifyH("LEFT")
		texts[key]:SetWordWrap(true)
	end
	texts[key]:Show()
	return texts[key]
end

local function Place(region, x, y, width)
	region:ClearAllPoints()
	region:SetPoint("TOPLEFT", c, "TOPLEFT", x, -y)
	region:SetWidth(width)
end

-- A wrapped line of text; returns the y under it.
local function PlaceLine(key, text, x, y, width)
	local fs = Line(key)
	Place(fs, x, y, width)
	fs:SetText(text)
	return y + fs:GetStringHeight() + 4
end

-- Left column ---------------------------------------------------------------------------------------------------------

local function DrawTodo(state, x, y, width)
	local todo = state.todo
	local head = Heading("todo")
	head:Set("To do", #todo == 0 and "Nothing waiting" or nil)
	Place(head, x, y, width)
	y = y + HEAD_H
	for i, item in ipairs(todo) do
		local row = Kit.PoolRow(todoRows, i, c)
		row:Set(item.icon, item.text, item.role, ns.Leveling_TodoRight(item), item.xp and "success" or nil, item.sub or "")
		Place(row, x, y, width)
		y = y + Kit.ROW2_H
	end
	Kit.HideFrom(todoRows, #todo + 1)
	if state.fine then
		y = PlaceLine("fine", state.fine, x, y + (#todo > 0 and 6 or 0), width)
	end
	return y
end

local function DrawUpcoming(state, x, y, width)
	local list = state.upcoming
	local head = Heading("upcoming")
	head:SetShown(state.nextLevel ~= nil)
	if not state.nextLevel then
		Kit.HideFrom(upcomingRows, 1)
		return y
	end
	head:Set("Next at your trainer", ("Level %d"):format(state.nextLevel))
	y = y + BLOCK_GAP
	Place(head, x, y, width)
	y = y + HEAD_H
	local shown = math.min(#list, UPCOMING_ROWS)
	for i = 1, shown do
		local row = Kit.PoolRow(upcomingRows, i, c)
		row:Set(nil, ns.Leveling_ServiceName(list[i]), "text", list[i].cost > 0 and ns.Price(list[i].cost) or nil)
		Place(row, x, y, width)
		y = y + Kit.ROW_H
	end
	Kit.HideFrom(upcomingRows, shown + 1)
	if #list > shown then
		y = PlaceLine("upcomingMore", ("and %d more"):format(#list - shown), x, y + 2, width)
	end
	return y
end

local function SkillRow(i)
	local row = skillRows[i]
	if not row then
		row = CreateFrame("Frame", nil, c)
		row:SetHeight(SKILL_H)
		row.right = UI.Text(row, 12, "textMuted", "number")
		row.right:SetPoint("TOPRIGHT")
		row.name = UI.Text(row, 13, "text")
		row.name:SetPoint("TOPLEFT")
		row.name:SetPoint("RIGHT", row.right, "LEFT", -10, 0)
		row.name:SetJustifyH("LEFT")
		row.name:SetWordWrap(false)
		row.bar = UI.Bar(row, SKILL_BAR_H)
		row.bar:SetPoint("BOTTOMLEFT", 0, 6)
		row.bar:SetPoint("BOTTOMRIGHT", 0, 6)
		skillRows[i] = row
	end
	row:Show()
	return row
end

local function DrawSkills(state, x, y, width)
	local skills = state.skills
	local head = Heading("skills")
	head:Set("Weapon skills", #skills == 0 and "All close to their cap" or nil)
	y = y + BLOCK_GAP
	Place(head, x, y, width)
	y = y + HEAD_H
	for i, s in ipairs(skills) do
		local row = SkillRow(i)
		row.name:SetText(s.worn and (s.name .. "  " .. UI.Wrap("in use", "warning")) or s.name)
		row.right:SetText(("%d / %d"):format(s.rank, s.max))
		row.bar:SetColorRole(s.worn and "warning" or nil)
		row.bar:SetValue(s.rank / s.max)
		Place(row, x, y, width)
		y = y + SKILL_H
	end
	for i = #skills + 1, #skillRows do
		skillRows[i]:Hide()
	end
	return y
end

-- Quests --------------------------------------------------------------------------------------------------------------

-- A quest's tooltip on owner: objectives, and what a click does. The next quests widget (NextQuests.lua) shows it too.
function ns.LevelingPage_QuestTooltip(owner, q, anchor)
	GameTooltip:SetOwner(owner, anchor or "ANCHOR_RIGHT")
	GameTooltip:SetText(q.title or "?", 1, 1, 1, 1, true)
	if q.complete then
		GameTooltip:AddLine("Ready to turn in", UI.RGB("success"))
	end
	if q.dungeon then
		local generic = q.dungeon == "Dungeon" or q.dungeon == "Raid"
		GameTooltip:AddLine(generic and (q.dungeon .. " quest") or ("Dungeon: " .. q.dungeon), UI.RGB("info"))
	end
	for _, o in ipairs(C_QuestLog.GetQuestObjectives(q.questID) or {}) do
		if o.text and o.text ~= "" then
			GameTooltip:AddLine(o.text, UI.RGB(o.finished and "success" or "text"))
		end
	end
	GameTooltip:AddLine(" ")
	if C_SuperTrack and not q.active then
		GameTooltip:AddLine("Click to make it your active quest", UI.RGB("textMuted"))
	end
	GameTooltip:AddLine(q.watched and "Shift-click to stop tracking" or "Shift-click to track", UI.RGB("textMuted"))
	GameTooltip:Show()
end

-- The bar at a quest row's left edge: accent for the active quest, faint for one that's only tracked.
function ns.LevelingPage_ShowMark(mark, q)
	mark:SetColorTexture(UI.Color(q.active and "accent" or "textFaint"))
	mark:SetShown(q.watched or q.active)
end

-- Click: the active quest, as the quest log's map button makes it (tracked too, so the tracker shows it). Shift-click:
-- tracked or not. Through ns.SafeTrack: the objective tracker and map redraw inside the call, which in combat hits
-- protected frames. Then q's watched and active are read again and done() runs.
function ns.LevelingPage_QuestClick(q, done)
	local id = q.questID
	local toggle = IsShiftKeyDown() or not C_SuperTrack
	ns.SafeTrack(function()
		if toggle then
			if C_QuestLog.GetQuestWatchType(id) then
				C_QuestLog.RemoveQuestWatch(id)
			else
				C_QuestLog.AddQuestWatch(id)
			end
		else
			if not C_QuestLog.GetQuestWatchType(id) then
				C_QuestLog.AddQuestWatch(id)
			end
			C_SuperTrack.SetSuperTrackedQuestID(id)
		end
		q.watched = C_QuestLog.GetQuestWatchType(id) ~= nil
		q.active = C_SuperTrack ~= nil and C_SuperTrack.GetSuperTrackedQuestID() == id
		done()
	end)
end

local function QuestTooltip(row)
	ns.LevelingPage_QuestTooltip(row, row.quest)
end

local function ShowWatched(row)
	ns.LevelingPage_ShowMark(row.mark, row.quest)
end

local function OnQuestClick(row)
	ns.LevelingPage_QuestClick(row.quest, function()
		ShowWatched(row)
		if GameTooltip:IsOwned(row) then
			QuestTooltip(row)
		end
	end)
end

local function QuestRow(i)
	local row = questRows[i]
	if not row then
		row = CreateFrame("Frame", nil, c)
		row:SetHeight(QUEST_H)
		row:EnableMouse(true)
		row.bg = row:CreateTexture(nil, "BACKGROUND")
		row.bg:SetAllPoints()
		row.bg:SetColorTexture(UI.Color("hover"))
		row.bg:Hide()
		row.mark = row:CreateTexture(nil, "ARTWORK") -- tracked: a bar on the row's left edge
		row.mark:SetPoint("TOPLEFT", 0, -3)
		row.mark:SetPoint("BOTTOMLEFT", 0, 3)
		row.mark:SetWidth(MARK_W)
		row.level = UI.Text(row, 13, "textMuted", "number")
		row.level:SetPoint("LEFT")
		row.level:SetWidth(LEVEL_W)
		row.level:SetJustifyH("RIGHT")
		row.right = UI.Text(row, 12, "textMuted", "number")
		row.right:SetPoint("RIGHT", -4, 0)
		row.title = UI.Text(row, 13, "text")
		row.title:SetPoint("LEFT", row.level, "RIGHT", 10, 0)
		row.title:SetPoint("RIGHT", row.right, "LEFT", -10, 0)
		row.title:SetJustifyH("LEFT")
		row.title:SetWordWrap(false)
		row:SetScript("OnEnter", function(self)
			self.bg:Show()
			QuestTooltip(self)
		end)
		row:SetScript("OnLeave", function(self)
			self.bg:Hide()
			GameTooltip:Hide()
		end)
		row:SetScript("OnMouseUp", function(self, button)
			if button == "LeftButton" and self:IsMouseOver() then
				OnQuestClick(self)
			end
		end)
		questRows[i] = row
	end
	row:Show()
	return row
end

local function AllWatched(list)
	for _, q in ipairs(list) do
		if not q.watched then
			return false
		end
	end
	return true
end

-- Tracks every quest in a group, or stops tracking them all when they all are. Through ns.SafeTrack, as OnQuestClick.
-- The game's watch limit may leave some untracked; the page redraws from what it says.
local function ToggleGroupWatch(row)
	local list = row.list
	local untrack = AllWatched(list)
	ns.SafeTrack(function()
		for _, q in ipairs(list) do
			if untrack then
				C_QuestLog.RemoveQuestWatch(q.questID)
			elseif not C_QuestLog.GetQuestWatchType(q.questID) then
				C_QuestLog.AddQuestWatch(q.questID)
			end
		end
		ns.LevelingPage_Refresh()
	end)
end

local function GroupRow(i)
	local row = groupRows[i]
	if not row then
		row = CreateFrame("Frame", nil, c)
		row:SetHeight(GROUP_H)
		row.count = UI.Text(row, 12, "textMuted", "number")
		row.count:SetPoint("BOTTOMRIGHT", -4, 6)
		row.track = UI.Button(row, TRACK_W, "Track all")
		row.track:SetHeight(TRACK_H)
		row.track:SetPoint("BOTTOMRIGHT", row.count, "BOTTOMLEFT", -10, -3)
		row.track:SetScript("OnClick", function()
			ToggleGroupWatch(row)
		end)
		row.name = UI.Text(row, 14, "text", "title")
		row.name:SetPoint("BOTTOMLEFT", 0, 5)
		row.name:SetPoint("RIGHT", row.track, "LEFT", -10, 0)
		row.name:SetJustifyH("LEFT")
		row.name:SetWordWrap(false)
		row.line = Kit.HLine(row)
		row.line:SetPoint("BOTTOMLEFT")
		row.line:SetPoint("BOTTOMRIGHT")
		groupRows[i] = row
	end
	row:Show()
	return row
end

local function DrawQuests(state, x, y, width)
	local head = Heading("quests")
	head:Set("Quests", state.questCount > 0 and ("%d in your log"):format(state.questCount) or nil)
	Place(head, x, y, width)
	y = y + HEAD_H
	local usedGroups, usedQuests = 0, 0
	for _, group in ipairs(ns.LEVELING_QUEST_GROUPS) do
		local list = state.groups[group.key]
		if #list > 0 then
			usedGroups = usedGroups + 1
			local g = GroupRow(usedGroups)
			g.name:SetText(group.name)
			UI.SetTextRole(g.name, group.role)
			g.count:SetText(#list)
			g.list = list
			g.track.label:SetText(AllWatched(list) and "Untrack all" or "Track all")
			y = y + (usedGroups > 1 and GROUP_GAP or 0)
			Place(g, x, y, width)
			y = y + GROUP_H + 3
			for _, q in ipairs(list) do
				usedQuests = usedQuests + 1
				local row = QuestRow(usedQuests)
				row.quest = q
				ShowWatched(row)
				row.level:SetText(("%s%s"):format(tostring(q.level or "?"), q.elite and "+" or ""))
				UI.SetTextRole(row.level, group.role)
				row.title:SetText(q.dungeon and ("%s  %s"):format(q.title or "?", UI.Wrap(q.dungeon, "info")) or q.title or "?")
				UI.SetTextRole(row.title, group.textRole)
				if q.timeLeft then
					row.right:SetText(ns.Leveling_TimeLeft(q.timeLeft))
					UI.SetTextRole(row.right, "warning")
				else
					row.right:SetText(q.xp > 0 and ("%s XP"):format(ns.Thousands(q.xp)) or "")
					UI.SetTextRole(row.right, group.key == "grey" and "textFaint" or "textMuted")
				end
				Place(row, x, y, width)
				y = y + QUEST_H
			end
		end
	end
	for i = usedGroups + 1, #groupRows do
		groupRows[i]:Hide()
	end
	for i = usedQuests + 1, #questRows do
		questRows[i]:Hide()
	end
	if state.questCount == 0 then
		y = PlaceLine("noQuests", "Your quest log is empty. Pick up a few nearby and they'll be sorted here.", x, y, width)
	elseif texts.noQuests then
		texts.noQuests:Hide()
	end
	return y
end

-- Page -----------------------------------------------------------------------------------------------------------------

local function Layout()
	if not page or page.list:GetWidth() <= 1 then
		return
	end
	local state = ns.LevelingRead_State()
	local width = page.list:GetWidth() - 2 * PAD
	if texts.fine then
		texts.fine:Hide()
	end
	if texts.upcomingMore then
		texts.upcomingMore:Hide()
	end

	page.xp:ClearAllPoints()
	page.xp:SetPoint("TOPLEFT", c, "TOPLEFT", PAD, 0)
	page.xp:SetWidth(width)
	local top = page.xp:Set(state) + BLOCK_GAP

	local two = width >= TWO_COLUMNS
	local leftW = two and math.floor((width - COL_GAP) * LEFT_SHARE) or width
	local y = DrawTodo(state, PAD, top, leftW)
	y = DrawUpcoming(state, PAD, y, leftW)
	y = DrawSkills(state, PAD, y, leftW)
	local questY = two and top or y + BLOCK_GAP
	local questX = two and PAD + leftW + COL_GAP or PAD
	local bottom = DrawQuests(state, questX, questY, two and width - leftW - COL_GAP or width)
	page.list:SetContentHeight(math.max(y, bottom) + PAD)
end

local function Create(frame)
	page = frame
	page.list = UI.Scroll(page)
	page.list:SetPoint("TOPLEFT", 0, -PAD)
	page.list:SetPoint("BOTTOMRIGHT", -12, 0)
	c = page.list.content
	page.xp = ns.LevelingXP_Create(c)
	page.list.onWidthChanged = Layout
end

local redraw = UI.Debounce(REFRESH_DELAY, function()
	if page and page:IsVisible() then
		Layout()
	elseif ns.Panel_IsShown() then
		ns.Panel_Refresh() -- Home's section
	end
end)

-- From Leveling.lua when something it shows changed. Nothing is read while the window is closed.
function ns.LevelingPage_Refresh()
	redraw()
end

ns.LevelingPage = {
	title = "Leveling",
	Create = Create,
	Refresh = Layout,
}
