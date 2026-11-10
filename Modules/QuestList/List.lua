local addonName, ns = ...

-- Quest list: the on-screen list, and the same drawing for the settings preview. A title bar (Quests and how many),
-- then each section from Data.lua (QuestList_Sections): a header (a stop's place and distance, a zone, Hidden) that
-- folds on click, its quests (level, title, Spoken's Play button) with their objectives as bars or text and a line for
-- XP and distance, and "+N more". Taller than its maximum height, it scrolls with the mouse wheel. QuestList.lua owns
-- the data: it fills each quest's objectives, yards, folded and flash fields before calling QuestListUI_Draw, and
-- handles clicks through ns.QuestList_* functions.

local PAD = 8
local TITLE_H = 24
local HEADER_H = 18
local QUEST_H = 17 -- a quest's title line
local LINE_H = 14 -- an objective or the detail line, as text
local BAR_LINE_H = 18 -- an objective with its bar under the label
local BAR_H = 2 -- thin, so the bar sits under its text instead of competing with it
local BAR_FILL_ALPHA = 0.7
local BAR_TRACK_ALPHA = 0.25
local MORE_H = 16
local QUEST_GAP = 5
local SECTION_GAP = 10 -- space, not a rule, sets one group off from the next
local ROW_INSET = 4 -- rows reach this far into the side padding so their hover wash has room
local MARK_W = 2
local LEVEL_W = 24 -- wide enough for an elite quest's "60+"
local SPOKEN_W = 18 -- Spoken's Play button and its gap
local SCROLL_STEP = 40
local MOUSE_POLL = 0.2 -- seconds between mouse-over checks (Fade until mouse-over)
local BACKGROUND_ALPHA = { none = 0, faint = 0.45, panel = 0.85 }
local HIDDEN_ALPHA = 0.6 -- quests on the Hidden line
local ACTIVE_BAND_ALPHA = 0.05 -- the active quest's band: a hint under its accent bar, not a block
local CHEVRON_LEN, CHEVRON_W = 5, 1.5 -- each of the fold chevron's two strokes
local CHEVRON_REACH = CHEVRON_LEN / 2 * math.sqrt(0.5) -- how far a stroke's middle sits from the chevron's point

local UI = ns.UI

-- Sample ------------------------------------------------------------------------------------------------------------

-- Made-up quests for Edit Mode with an empty log and for the settings preview.
local function SampleSections()
	local function O(label, have, need, finished)
		return { label = label, have = have, need = need, finished = finished or false }
	end
	local q1 = { questID = -1, title = "Kill Grundig Darkcloud", level = 18, xp = 1650, active = true, watched = true,
		yards = 140, objectives = { O("Grundig Darkcloud slain", 0, 1), O("Grimtotem Brute slain", 4, 6) } }
	local q2 = { questID = -2, title = "Serena Bloodfeather", level = 20, complete = true, watched = true, yards = 210,
		objectives = {} }
	local q3 = { questID = -3, title = "Chen's Empty Keg", level = 24, xp = 2100, watched = true, yards = 260,
		objectives = { O("Lightning Gland", 5, 5, true), O("Thunderhawk Saliva Gland", 0, 1), O("Kodo Liver", 0, 1) } }
	local q4 = { questID = -4, title = "...and that note you found", level = 22, watched = true, objectives = {} }
	return {
		{ key = "s1", kind = "stop", title = "Camp Taurajo", distance = 140, quests = { q2, q1, q3 }, shown = 3, more = 0,
			open = true },
		{ key = "s2", kind = "stop", title = "Thousand Needles", distance = 1180, quests = { q4 }, shown = 0, more = 0,
			open = false },
	}
end

-- Pieces ------------------------------------------------------------------------------------------------------------

local function GroupRole(q)
	local key = ns.Leveling_QuestGroup and ns.Leveling_QuestGroup(q)
	for _, g in ipairs(ns.LEVELING_QUEST_GROUPS or {}) do
		if g.key == key then
			return g.role
		end
	end
	return "text"
end

local function YardsText(yards)
	if not yards then
		return ""
	end
	local rounded = ns.Leveling_StopYards and ns.Leveling_StopYards(yards) or math.floor(yards)
	if ns.Way_FormatDistance then
		return ns.Way_FormatDistance(rounded, ns.QuestList_DB().metric)
	end
	return ("%s yd"):format(ns.Thousands(rounded))
end

local function Hover(self)
	self.bg:Show()
end

local function Unhover(self)
	self.bg:Hide()
	GameTooltip:Hide()
end

local function HoverWash(b)
	b.bg = b:CreateTexture(nil, "BACKGROUND")
	b.bg:SetAllPoints()
	b.bg:SetColorTexture(UI.Color("hover"))
	b.bg:Hide()
end

-- The fold chevron: two strokes meeting at a point, drawn from rotated color bars (as Bags draws its cross). Pointing
-- right while the group is folded, down while it's open.
local function Chevron(parent)
	local c = CreateFrame("Frame", nil, parent)
	c:SetSize(8, 8)
	c.strokes = {}
	for i = 1, 2 do
		local t = c:CreateTexture(nil, "ARTWORK")
		t:SetSize(CHEVRON_LEN, CHEVRON_W)
		c.strokes[i] = t
	end
	function c:Point(open)
		local a, b = self.strokes[1], self.strokes[2]
		local r, q = CHEVRON_REACH, math.pi / 4
		a:ClearAllPoints()
		b:ClearAllPoints()
		if open then
			a:SetPoint("CENTER", -r, r - 1)
			b:SetPoint("CENTER", r, r - 1)
		else
			a:SetPoint("CENTER", -r + 1, r)
			b:SetPoint("CENTER", -r + 1, -r)
		end
		a:SetRotation(-q)
		b:SetRotation(q)
	end
	function c:SetRole(role)
		for _, t in ipairs(self.strokes) do
			t:SetColorTexture(UI.Color(role))
		end
	end
	return c
end

local function HeaderRole(h)
	return h.section and h.section.kind == "hidden" and "textFaint" or "textMuted"
end

local function HeaderEnter(self)
	self.bg:Show()
	UI.SetTextRole(self.name, "text")
	self.chevron:SetRole("accent")
end

local function HeaderLeave(self)
	self.bg:Hide()
	UI.SetTextRole(self.name, HeaderRole(self))
	self.chevron:SetRole("textFaint")
end

local function Header(f, i)
	local h = f.headers[i]
	if not h then
		h = CreateFrame("Button", nil, f.content)
		h:SetHeight(HEADER_H)
		HoverWash(h)
		h.chevron = Chevron(h)
		h.chevron:SetPoint("LEFT", ROW_INSET + MARK_W + 1, 0)
		h.chevron:SetRole("textFaint")
		h.name = UI.Text(h, 11, "textMuted", "label")
		h.name:SetPoint("LEFT", h.chevron, "RIGHT", 5, 0)
		h.name:SetJustifyH("LEFT")
		h.name:SetWordWrap(false)
		h.right = UI.Text(h, 10, "textMuted", "number")
		h.right:SetPoint("RIGHT", -ROW_INSET, 0)
		h.right:SetJustifyH("RIGHT")
		h.count = UI.Text(h, 10, "textFaint", "number")
		h.count:SetPoint("RIGHT", h.right, "LEFT", -8, 0)
		h.count:SetJustifyH("RIGHT")
		h.name:SetPoint("RIGHT", h.count, "LEFT", -6, 0)
		h:SetScript("OnEnter", HeaderEnter)
		h:SetScript("OnLeave", HeaderLeave)
		h:SetScript("OnClick", function(self)
			if not (f.sample or f.showingSample) then
				UI.Sound("pick")
				ns.QuestList_ToggleSection(self.key)
			end
		end)
		f.headers[i] = h
	end
	return h
end

local function QuestEnter(self)
	self.bg:Show()
	if self.quest and not self.list.sample and not self.list.showingSample then
		ns.LevelingPage_QuestTooltip(self, self.quest, "ANCHOR_LEFT", ns.QuestList_ShiftLine(self.quest))
	end
end

local function QuestRow(f, i)
	local row = f.quests[i]
	if not row then
		row = CreateFrame("Button", nil, f.content)
		row.list = f
		row:SetHeight(QUEST_H)
		row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
		row.glow = row:CreateTexture(nil, "BACKGROUND", nil, -1)
		row.glow:SetAllPoints()
		row.glow:SetColorTexture(UI.Color("accent"))
		row.glow:SetAlpha(ACTIVE_BAND_ALPHA)
		HoverWash(row)
		row.mark = row:CreateTexture(nil, "ARTWORK")
		row.mark:SetPoint("TOPLEFT", 0, -2)
		row.mark:SetPoint("BOTTOMLEFT", 0, 2)
		row.mark:SetWidth(MARK_W)
		row.level = UI.Text(row, 10, "textMuted", "number")
		row.level:SetPoint("LEFT", MARK_W + 3, 0)
		row.level:SetJustifyH("RIGHT")
		row.title = UI.Text(row, 12, "text")
		row.title:SetJustifyH("LEFT")
		row.title:SetWordWrap(false)
		row:SetScript("OnEnter", QuestEnter)
		row:SetScript("OnLeave", Unhover)
		row:SetScript("OnClick", function(self, button)
			if f.sample or f.showingSample or not self.quest then
				return
			end
			if button == "RightButton" then
				ns.QuestList_Menu(self, self.quest)
			else
				ns.QuestList_QuestClick(self.quest)
			end
		end)
		f.quests[i] = row
	end
	return row
end

local function Line(f, i)
	local line = f.lines[i]
	if not line then
		line = CreateFrame("Frame", nil, f.content)
		line.text = UI.Text(line, 11, "textMuted")
		line.text:SetPoint("TOPLEFT", 0, -1)
		line.text:SetJustifyH("LEFT")
		line.text:SetWordWrap(false)
		line.count = UI.Text(line, 11, "textMuted", "number")
		line.count:SetPoint("TOPRIGHT", 0, -1)
		line.count:SetJustifyH("RIGHT")
		line.barBg = line:CreateTexture(nil, "ARTWORK")
		line.barBg:SetPoint("BOTTOMLEFT", 0, 2)
		line.barBg:SetPoint("BOTTOMRIGHT", 0, 2)
		line.barBg:SetHeight(BAR_H)
		line.barFill = line:CreateTexture(nil, "ARTWORK", nil, 1)
		line.barFill:SetPoint("TOPLEFT", line.barBg, "TOPLEFT")
		line.barFill:SetPoint("BOTTOMLEFT", line.barBg, "BOTTOMLEFT")
		f.lines[i] = line
	end
	return line
end

local function More(f, i)
	local m = f.mores[i]
	if not m then
		m = CreateFrame("Button", nil, f.content)
		m:SetHeight(MORE_H)
		HoverWash(m)
		m.text = UI.Text(m, 10, "textFaint")
		m.text:SetPoint("LEFT", 0, 0)
		m:SetScript("OnEnter", Hover)
		m:SetScript("OnLeave", Unhover)
		m:SetScript("OnClick", function(self)
			if not (f.sample or f.showingSample) then
				UI.Sound("pick")
				ns.QuestList_ExpandSection(self.key)
			end
		end)
		f.mores[i] = m
	end
	return m
end

-- Frame -------------------------------------------------------------------------------------------------------------

local function Scroll(f, delta)
	local most = math.max(0, f.contentH - f.listH)
	f.scroll = math.min(math.max((f.scroll or 0) - delta * SCROLL_STEP, 0), most)
	f.content:SetPoint("TOPLEFT", 0, f.scroll)
end

-- A list on parent. sample: the settings preview's copy (takes no mouse, shows sample quests).
function ns.QuestListUI_New(parent, sample)
	local f = CreateFrame("Frame", nil, parent)
	f.sample = sample
	f:SetSize(280, TITLE_H)
	f.panel = UI.Panel(f, { alpha = BACKGROUND_ALPHA.faint, subtle = true })
	f.title = UI.Text(f, 13, "heading", "title")
	f.title:SetPoint("TOPLEFT", PAD, -6)
	f.title:SetText("Quests")
	f.count = UI.Text(f, 11, "textFaint", "number")
	f.count:SetPoint("BOTTOMLEFT", f.title, "BOTTOMRIGHT", 6, 1)
	f.clip = CreateFrame("Frame", nil, f)
	f.clip:SetPoint("TOPLEFT", 0, -TITLE_H)
	f.clip:SetPoint("BOTTOMRIGHT", 0, PAD / 2)
	f.clip:SetClipsChildren(true)
	f.content = CreateFrame("Frame", nil, f.clip)
	f.content:SetPoint("TOPLEFT")
	f.content:SetSize(280, 1)
	f.headers, f.quests, f.lines, f.mores = {}, {}, {}, {}
	f.scroll = 0
	f.contentH, f.listH = 0, 0
	if not sample then
		f:SetFrameStrata("LOW")
		f:SetClampedToScreen(true)
		f:SetMovable(true)
		f:SetScript("OnMouseWheel", Scroll)
		-- Set before UI.CollapseButton, which hooks OnUpdate (a SetScript after it would drop its hook).
		local since = 0
		f:SetScript("OnUpdate", function(self, elapsed)
			since = since + elapsed
			if since < MOUSE_POLL or not ns.QuestList_DB().mouseFade then
				return
			end
			since = 0
			local over = self:IsMouseOver()
			if over ~= self.hovered then
				self.hovered = over
				ns.QuestList_ApplyAlpha()
			end
		end)
		f.collapse = UI.CollapseButton(f, function()
			return ns.QuestList_DB().collapsed
		end, function()
			ns.QuestList_ToggleCollapsed()
		end)
		-- Follow the nearest quest, switched on the list itself (the same setting as in the Layout card).
		f.follow = UI.FollowBox(f, function()
			return ns.QuestList_DB().follow
		end, function()
			ns.QuestList_ToggleFollow()
		end, function(on)
			return on and "Following the nearest quest" or "Not following the nearest quest",
				on and "The nearest stop's top quest becomes your active quest. Click to stop."
					or "Click to make the nearest stop's top quest your active quest each time a new one comes up."
		end)
	end
	return f
end

-- Drawing -----------------------------------------------------------------------------------------------------------

local function TitleRole(q, speaking)
	if speaking then
		return "info"
	elseif q.active then
		return "heading"
	end
	return "text"
end

-- A header's right side: a stop's distance, and how many quests it holds while folded (a zone or Hidden: the count
-- alone).
local function HeaderTexts(h)
	local s = h.section
	h.name:SetText(s.title)
	local count = ns.QuestList_CountText(#s.quests)
	if s.kind == "stop" and s.distance then
		h.right:SetText(YardsText(s.distance))
		h.count:SetText(s.open and "" or count)
	else
		h.right:SetText(count)
		h.count:SetText("")
	end
end

-- One objective line at y; returns its height.
local function DrawObjective(f, li, obj, x, y, width, bars, doneMode, flash)
	local line = Line(f, li)
	local share = bars and ns.QuestList_ObjectiveShare(obj)
	local role = obj.finished and (doneMode == "green" and "success" or "textFaint") or "textMuted"
	line.quest = nil -- not a detail line: the distance refresh leaves it alone
	line:ClearAllPoints()
	line:SetPoint("TOPLEFT", x, -y)
	line:SetWidth(width)
	line.text:ClearAllPoints()
	line.text:SetPoint("TOPLEFT", 0, -1)
	UI.SetTextRole(line.text, role)
	if share then
		line.text:SetText(obj.label)
		line.text:SetPoint("RIGHT", line.count, "LEFT", -6, 0)
		line.count:SetText(("%d/%d"):format(obj.have or 0, obj.need))
		UI.SetTextRole(line.count, role)
		line.count:Show()
		line.barBg:SetColorTexture(UI.Color("textFaint"))
		line.barBg:SetAlpha(BAR_TRACK_ALPHA)
		line.barBg:Show()
		line.barFill:SetColorTexture(UI.Color(obj.finished and "success" or "accent"))
		line.barFill:SetAlpha(BAR_FILL_ALPHA)
		line.barFill:SetWidth(math.max(1, width * share))
		line.barFill:SetShown(share > 0)
		line:SetHeight(BAR_LINE_H)
	else
		line.text:SetText(ns.QuestList_ObjectiveText(obj))
		line.text:SetPoint("RIGHT", 0, 0)
		line.count:Hide()
		line.barBg:Hide()
		line.barFill:Hide()
		line:SetHeight(LINE_H)
	end
	line:Show()
	if flash and ns.QuestList_DB().animate then
		UI.Pop(line.text)
	end
	return line:GetHeight()
end

-- The detail line under a quest: XP or time left on the left, its distance on the right when its stop's header
-- doesn't already say it. nil when there's nothing.
local function Details(q, db, s)
	local left, leftRole
	if q.complete then
		left, leftRole = "Ready to turn in", "success"
	elseif q.timeLeft and ns.Leveling_TimeLeft then
		left, leftRole = ns.Leveling_TimeLeft(q.timeLeft) .. " left", "warning"
	elseif db.xp and (q.xp or 0) > 0 then
		left, leftRole = ("%s XP"):format(ns.Thousands(q.xp)), "textFaint"
	end
	local right = db.distance and ns.QuestList_ShowQuestDistance(s, q) and YardsText(q.yards) or nil
	if not (left or right) then
		return nil
	end
	return left or "", leftRole or "textFaint", right or ""
end

local function DrawDetail(f, li, q, s, x, y, width, db)
	local left, role, right = Details(q, db, s)
	if not left then
		return 0
	end
	local line = Line(f, li)
	line:ClearAllPoints()
	line:SetPoint("TOPLEFT", x, -y)
	line:SetWidth(width)
	line.text:ClearAllPoints()
	line.text:SetPoint("TOPLEFT", 0, -1)
	line.text:SetPoint("RIGHT", line.count, "LEFT", -6, 0)
	line.text:SetText(left)
	UI.SetTextRole(line.text, role)
	line.count:SetText(right)
	UI.SetTextRole(line.count, "textFaint")
	line.count:Show()
	line.barBg:Hide()
	line.barFill:Hide()
	line:SetHeight(LINE_H)
	line.quest, line.section = q, s
	line:Show()
	return LINE_H
end

-- Draws sections into f. total: quests in the log (for the title bar); speaking: the quest Spoken reads, or nil.
-- Each quest carries objectives, yards, folded and flash (set by QuestList.lua, or the sample's own).
function ns.QuestListUI_Draw(f, sections, total, speaking)
	local db = ns.QuestList_DB()
	if #sections == 0 then
		sections, total = SampleSections(), 4
		f.showingSample = true
	else
		f.showingSample = false
	end
	local width = db.width
	f:SetWidth(width)
	f.content:SetWidth(width)
	f.panel:SetAlpha(BACKGROUND_ALPHA[db.background] or BACKGROUND_ALPHA.faint)
	-- No background: no edge either, the list stands on the world as the game's tracker does.
	for _, edge in ipairs(f.panel.inner or {}) do
		edge:SetShown(db.background ~= "none")
	end
	f.count:SetText(tostring(total or 0))
	local levelW = db.level == "hidden" and 0 or LEVEL_W
	local textX = MARK_W + 3 + levelW + (levelW > 0 and 5 or 0) -- inside a row
	local objX = ROW_INSET + textX + 2
	local objW = width - objX - PAD - 2
	local bars = db.objectives == "bars"
	local spokenOn = db.spoken and not f.sample
	local nh, nq, nl, nm = 0, 0, 0, 0
	local y = 2
	local collapsed = db.collapsed and not f.sample
	f.clip:SetShown(not collapsed)
	if not collapsed then
		for si, s in ipairs(sections) do
			if si > 1 then
				y = y + SECTION_GAP
			end
			if s.kind ~= "list" then
				nh = nh + 1
				local h = Header(f, nh)
				h.key, h.section = s.key, s
				h:ClearAllPoints()
				h:SetPoint("TOPLEFT", PAD - ROW_INSET, -y)
				h:SetPoint("RIGHT", f.content, "RIGHT", -(PAD - ROW_INSET), 0)
				h.chevron:Point(s.open)
				h.name:SetText(s.title)
				UI.SetTextRole(h.name, HeaderRole(h))
				HeaderTexts(h)
				h:Show()
				y = y + HEADER_H + 2
			end
			for i = 1, s.shown do
				local q = s.quests[i]
				nq = nq + 1
				local row = QuestRow(f, nq)
				row.quest = q
				row:ClearAllPoints()
				row:SetPoint("TOPLEFT", PAD - ROW_INSET, -y)
				row:SetPoint("RIGHT", f.content, "RIGHT", -(PAD - ROW_INSET), 0)
				local isSpeaking = db.speaking and speaking ~= nil and speaking == q.questID
				row.level:SetWidth(math.max(levelW, 1))
				row.level:SetShown(levelW > 0)
				row.level:SetText(ns.QuestList_LevelText(q.level, q.elite))
				UI.SetTextRole(row.level, db.level == "colored" and GroupRole(q) or "textMuted")
				row.title:SetText(q.title or "?")
				UI.SetTextRole(row.title, TitleRole(q, isSpeaking))
				row.mark:SetColorTexture(UI.Color(isSpeaking and "info" or "accent"))
				row.mark:SetShown(q.active or isSpeaking)
				row.glow:SetShown(db.glow and q.active or false)
				row:SetAlpha(s.kind == "hidden" and HIDDEN_ALPHA or 1)
				-- Spoken's Play button, at the right of the title.
				local hasPlay = false
				if spokenOn then
					if row.spoken == nil then
						row.spoken = ns.QuestListSpoken_Button(row) or false
						if row.spoken then
							row.spoken:SetPoint("RIGHT", -2, 0)
							row.spoken:SetFrameLevel(row:GetFrameLevel() + 3)
						end
					end
					if row.spoken then
						hasPlay = ns.QuestListSpoken_Bind(row.spoken, q.questID, q.title)
					end
				elseif row.spoken then
					row.spoken:Hide()
				end
				row.title:ClearAllPoints()
				row.title:SetPoint("LEFT", textX, 0)
				row.title:SetPoint("RIGHT", hasPlay and -SPOKEN_W or -4, 0)
				row:Show()
				if q.justDone and db.animate then
					UI.Flash(row, "success")
				end
				y = y + QUEST_H
				if not q.folded then
					local objectives = q.objectives or {}
					if not q.complete then
						for k, obj in ipairs(objectives) do
							if not (obj.finished and db.doneObjectives == "hide") then
								nl = nl + 1
								y = y + DrawObjective(f, nl, obj, objX, y, objW, bars, db.doneObjectives,
									q.flash and q.flash[k])
							end
						end
					end
					nl = nl + 1
					local used = DrawDetail(f, nl, q, s, objX, y, objW, db)
					if used == 0 then
						nl = nl - 1
					end
					y = y + used
				end
				y = y + QUEST_GAP
			end
			if s.more > 0 then
				nm = nm + 1
				local m = More(f, nm)
				m.key = s.key
				m:ClearAllPoints()
				m:SetPoint("TOPLEFT", objX - 2, -y)
				m:SetPoint("RIGHT", f.content, "RIGHT", -PAD, 0)
				m.text:SetText(("Show %d more"):format(s.more))
				m:Show()
				y = y + MORE_H
			end
		end
	end
	for i = nh + 1, #f.headers do
		f.headers[i]:Hide()
	end
	for i = nq + 1, #f.quests do
		f.quests[i]:Hide()
	end
	for i = nl + 1, #f.lines do
		f.lines[i]:Hide()
	end
	for i = nm + 1, #f.mores do
		f.mores[i]:Hide()
	end
	f.contentH = y
	f.content:SetHeight(math.max(y, 1))
	local room = math.max(db.maxHeight - TITLE_H, HEADER_H)
	f.listH = collapsed and 0 or math.min(y, room)
	f:SetHeight(collapsed and TITLE_H or (TITLE_H + f.listH + PAD / 2))
	if not f.sample then
		f:EnableMouseWheel(not collapsed and y > room)
		Scroll(f, 0)
	end
end

-- Writes the distances again (quests' yards and stops' distances, already updated by QuestList.lua) without a redraw.
function ns.QuestListUI_Distances(f)
	if f.showingSample then
		return
	end
	for _, h in ipairs(f.headers) do
		if h:IsShown() and h.section then
			HeaderTexts(h)
		end
	end
	local db = ns.QuestList_DB()
	for _, line in ipairs(f.lines) do
		if line:IsShown() and line.quest then
			local _, _, right = Details(line.quest, db, line.section)
			line.count:SetText(right or "")
		end
	end
end

-- The settings preview: a sample list drawn with the settings under the mouse.
function ns.QuestListUI_Preview(host)
	local f = host.questList
	if not f then
		f = ns.QuestListUI_New(host, true)
		f:SetPoint("TOPLEFT")
		host.questList = f
	end
	ns.QuestListUI_Draw(f, {}, 0, nil)
	local scale = ns.QuestList_DB().scale or 1
	f:SetScale(scale)
	return f:GetWidth() * scale, f:GetHeight() * scale
end
