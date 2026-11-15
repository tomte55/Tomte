local addonName, ns = ...

-- Tomte map: your quest log in the map's side panel (Side.lua), under the game's zone headings, the active quest marked.
-- Click a quest: your active quest, and the map glides to it. Right-click: the Quest list's menu (details, share, find
-- group). Hover: its pin on the map grows and comes to the top (ns.MapPins_Hover). Quests are read by Leveling
-- (ns.LevelingRead_Quests).

local ROW_H, HEADER_H = 34, 24
local PAD = 6
local REDRAW = 0.2 -- seconds: quest log events come in bursts
local FIND = 18 -- pixels: the find button on a quest row
local FIND_ATLAS = "common-search-magnifyingglass"
local FIND_TEXTURE = "Interface\\Common\\UI-Searchbox-Icon" -- without that atlas

local UI = ns.UI

local frame, scroll, empty
local rows, used = {}, 0
local Redraw

-- Rows ------------------------------------------------------------------------------------------------------------------

local function Tip(row)
	ns.LevelingPage_QuestTooltip(row, row.quest, "ANCHOR_LEFT",
		ns.QuestList_Active and ns.QuestList_Active() and "Right-click for more" or "")
end

local function NewRow()
	local row = CreateFrame("Button", nil, scroll.content)
	row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	row.hover = row:CreateTexture(nil, "BACKGROUND")
	row.hover:SetAllPoints()
	row.hover:SetColorTexture(UI.Color("hover"))
	row.hover:Hide()
	row.mark = row:CreateTexture(nil, "ARTWORK")
	row.mark:SetWidth(2)
	row.mark:SetPoint("TOPLEFT", 0, -4)
	row.mark:SetPoint("BOTTOMLEFT", 0, 4)
	row.level = UI.Text(row, 11, "textMuted", "number")
	row.level:SetWidth(24)
	row.level:SetJustifyH("RIGHT")
	row.level:SetPoint("TOPLEFT", PAD, -5)
	row.name = UI.Text(row, 12, "text")
	row.name:SetWordWrap(false)
	row.name:SetPoint("TOPLEFT", row.level, "TOPRIGHT", 8, 0)
	row.name:SetPoint("RIGHT", -(PAD + FIND + 4), 0)
	-- Find: the map flies out, across and in to the quest, its pin ringed (as the Dungeon journal's Show on map).
	row.find = CreateFrame("Button", nil, row)
	row.find:SetSize(FIND, FIND)
	row.find:SetPoint("RIGHT", -PAD, 0)
	row.find.icon = row.find:CreateTexture(nil, "ARTWORK")
	row.find.icon:SetAllPoints()
	if not row.find.icon:SetAtlas(FIND_ATLAS) then
		row.find.icon:SetTexture(FIND_TEXTURE)
	end
	row.find.icon:SetVertexColor(UI.Color("textMuted"))
	row.find:SetScript("OnEnter", function(self)
		self:GetParent().hover:Show()
		self.icon:SetVertexColor(UI.Color("accent"))
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		UI.TipLine("Find on the map", "heading")
		GameTooltip:Show()
	end)
	row.find:SetScript("OnLeave", function(self)
		self.icon:SetVertexColor(UI.Color("textMuted"))
		GameTooltip:Hide()
		local row = self:GetParent()
		if not row:IsMouseOver() then
			row.hover:Hide()
			self:Hide()
		end
	end)
	row.find:SetScript("OnClick", function(self)
		local q = self:GetParent().quest
		if q then
			ns.MapWindow_FindQuest(q.questID, q.title)
		end
	end)
	row.sub = UI.Text(row, 11, "textMuted")
	row.sub:SetWordWrap(false)
	row.sub:SetPoint("TOPLEFT", row.name, "BOTTOMLEFT", 0, -3)
	row.sub:SetPoint("RIGHT", -(PAD + FIND + 4), 0)
	row.title = UI.Text(row, 12, "heading")
	row.title:SetPoint("BOTTOMLEFT", PAD, 5)
	row.count = UI.Text(row, 11, "textMuted")
	row.count:SetPoint("BOTTOMRIGHT", -PAD, 5)
	row.line = row:CreateTexture(nil, "ARTWORK")
	row.line:SetColorTexture(UI.RGBA("frame", 0.4))
	row.line:SetHeight(1)
	row.line:SetPoint("BOTTOMLEFT", PAD, 1)
	row.line:SetPoint("BOTTOMRIGHT", -PAD, 1)
	row:SetScript("OnEnter", function(self)
		if self.quest then
			self.hover:Show()
			-- Asked now: the quests' spots may have been read after this row was drawn.
			self.find:SetShown(ns.MapPins_QuestSpot(self.quest.questID) ~= nil)
			Tip(self)
			ns.MapPins_Hover(self.quest.questID)
		end
	end)
	row:SetScript("OnLeave", function(self)
		if self.find:IsMouseOver() then
			return -- onto its own find button
		end
		self.find:Hide()
		self.hover:Hide()
		GameTooltip:Hide()
		ns.MapPins_Hover(nil)
	end)
	row:SetScript("OnClick", function(self, button)
		local q = self.quest
		if not q then
			return
		end
		if button == "RightButton" then
			if ns.QuestList_Active and ns.QuestList_Active() then
				ns.QuestList_Menu(self, q)
			end
			return
		end
		ns.MapWindow_GoToQuest(q.questID)
		if not q.active then
			ns.LevelingPage_MakeActive(q.questID, function()
				ns.MapPins_Quests()
			end)
		end
	end)
	return row
end

local function Row(height)
	used = used + 1
	local row = rows[used] or NewRow()
	rows[used] = row
	row:SetHeight(height)
	row:Show()
	return row
end

local function SetHeader(row, title, n)
	row.quest = nil
	row.find:Hide()
	row.mark:Hide()
	row.level:Hide()
	row.name:Hide()
	row.sub:Hide()
	row.title:SetText(title)
	row.title:Show()
	row.count:SetText(ns.QuestList_CountText(n))
	row.count:Show()
	row.line:Show()
end

local function SetQuest(row, q, playerLevel, greenRange)
	row.quest = q
	row.title:Hide()
	row.count:Hide()
	row.line:Hide()
	row.level:Show()
	row.name:Show()
	row.sub:Show()
	ns.LevelingPage_ShowMark(row.mark, q)
	row.level:SetText(ns.QuestList_LevelText(q.level, q.elite))
	UI.SetTextRole(row.level, ns.QuestList_DifficultyRole(q.level, playerLevel, greenRange))
	row.name:SetText(q.title or "?")
	UI.SetTextRole(row.name, q.active and "accent" or "text")
	local sub = ns.QuestList_ProgressText(ns.QuestListRead_Objectives(q.questID), q.complete)
	local onMap = ns.MapPins_QuestSpot(q.questID) ~= nil
	row.onMap = onMap
	row.find:SetShown(onMap and row:IsMouseOver())
	if not onMap then
		sub = (sub and sub .. "  " or "") .. UI.Wrap("not on the map", "textFaint")
	end
	row.sub:SetText(sub or "")
	UI.SetTextRole(row.sub, q.complete and "success" or "textMuted")
end

-- Drawing ---------------------------------------------------------------------------------------------------------------

local function Draw()
	if not (frame and frame:IsVisible()) then
		return
	end
	for i = 1, used do
		rows[i]:Hide()
		rows[i].quest = nil
	end
	used = 0
	local quests = ns.LevelingRead_Quests()
	-- Under their headings, in the log's order; a heading's count is its quests.
	local groups, order = {}, {}
	for _, q in ipairs(quests) do
		local key = q.zone or ""
		if not groups[key] then
			groups[key] = {}
			order[#order + 1] = key
		end
		local g = groups[key]
		g[#g + 1] = q
	end
	local playerLevel = UnitLevel("player")
	local greenRange = GetQuestGreenRange and GetQuestGreenRange()
	local y = 0
	for _, key in ipairs(order) do
		local header = Row(HEADER_H)
		header:SetPoint("TOPLEFT", 0, -y)
		header:SetPoint("RIGHT")
		SetHeader(header, key ~= "" and key or OTHER or "Other", #groups[key])
		y = y + HEADER_H + 2
		for _, q in ipairs(groups[key]) do
			local row = Row(ROW_H)
			row:SetPoint("TOPLEFT", 0, -y)
			row:SetPoint("RIGHT")
			SetQuest(row, q, playerLevel, greenRange)
			y = y + ROW_H
		end
		y = y + 6
	end
	empty:SetShown(#quests == 0)
	ns.MapSide_Count(#quests)
	scroll:SetContentHeight(y)
end

Redraw = UI.Debounce(REDRAW, Draw)

-- From Side.lua and Map.lua ---------------------------------------------------------------------------------------------

function ns.MapQuests_Build(parent)
	frame = CreateFrame("Frame", nil, parent)
	frame:SetAllPoints(parent)
	scroll = UI.Scroll(frame)
	scroll:SetPoint("TOPLEFT", 0, 0)
	scroll:SetPoint("BOTTOMRIGHT", -8, 0)
	empty = UI.Text(frame, 12, "textMuted")
	empty:SetPoint("TOPLEFT", PAD, -6)
	empty:SetPoint("RIGHT", -PAD, 0)
	empty:SetText("Your quest log is empty.")
	empty:Hide()
	frame:SetScript("OnShow", Draw)
	return frame
end

-- The quest log or the active quest changed (a moment later, once a burst of events is over).
function ns.MapQuests_Refresh()
	if frame and frame:IsVisible() then
		Redraw()
	end
end
