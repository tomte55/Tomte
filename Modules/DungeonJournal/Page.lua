local addonName, ns = ...

-- Dungeon journal: the page in the Tomte window. The dungeon list is laid out around your level; open a dungeon and its
-- quests or bosses list sits in a recessed well on the left, the picked one on the right under a lit band (Stage.lua),
-- loot as tiles (Tiles.lua). Rules in Data.lua, reads in Read.lua, pieces in Parts.lua, the lists in Lists.lua, the
-- details in Detail.lua; registered in DungeonJournal.lua; the data is Data/Forever/DungeonJournal.lua.

local PAD = 8
local TOP_H = 34 -- the search row
local HEAD_H = 44 -- the dungeon's header: back button, name, Show entrance, Quests | Bosses
local LIST_W = 250 -- the left list's well in a dungeon
local GAP = 12 -- between the well and the details
local WELL_INSET = 4 -- the list inside its well
local FOOT_H = 34 -- the well's foot in the quests tab: the other side's switch
local SEARCH_W = 260
local RELAYOUT = 0.2 -- seconds: item and quest names arriving in a burst redraw once
local MARK_ABOVE = 12 -- a searched item scrolled to sits this far below the top

local UI = ns.UI
local J = ns.DJKit
local S = J.state

local page

-- Layout ----------------------------------------------------------------------------------------------------------------

local function DrawDungeon()
	local inst = S.inst
	local ctx = J.Context()
	local about = { ns.DJ_LevelText(inst.min, inst.max) }
	local n = #ns.DJ_Quests(inst, ctx.side, ctx.class, false)
	about[#about + 1] = n == 0 and ("no %s quests"):format(J.SideName(ctx.side))
		or (n == 1 and "1 quest for you" or ("%d quests for you"):format(n))
	page.name:SetText(inst.name)
	page.about:SetText(table.concat(about, ", "))
	page.tabs:Refresh()

	local quests = S.tab == "quests"
	page.foot:SetShown(quests)
	page.other:SetChecked(J.DB().otherSide)
	page.usable:SetShown(not quests)
	page.usableLabel:SetShown(not quests)
	page.usable:SetChecked(J.DB().usableOnly)
	page.left:ClearAllPoints()
	page.left:SetPoint("TOPLEFT", page.well, "TOPLEFT", 0, -WELL_INSET)
	page.left:SetPoint("BOTTOMRIGHT", page.well, "BOTTOMRIGHT", -WELL_INSET, quests and FOOT_H or WELL_INSET)

	local lw = LIST_W - 2 * PAD - WELL_INSET - 6
	local ly = quests and J.DrawQuestList(lw) or J.DrawBossList(lw)
	page.left:SetContentHeight(ly + PAD)

	local rw = page.right:GetWidth() - 2 * PAD
	local ry = PAD
	local pick = S.pick
	-- Hidden only when nothing is picked: hiding resets the model, and a redraw (an item's data arriving on hover)
	-- would then load it again, flashing and replaying its idle.
	if pick and rw > 0 then
		if pick.prep then
			ry = J.DrawPrep(rw)
		elseif pick.quest then
			ry = J.DrawQuest(pick.quest, rw)
		else
			ry = J.DrawBoss(pick, rw)
		end
	else
		page.stage:Hide()
	end
	page.right:SetContentHeight(ry + PAD)
	if J.scrollToMark and J.markY then
		J.scrollToMark = false
		page.right:SetVerticalScroll(math.max(J.markY - MARK_ABOVE, 0))
	end
end

local function Layout()
	if not (page and page:IsVisible()) then
		return
	end
	J.BeginParts()
	J.BeginTiles()
	J.NewPass()
	local dungeon = S.inst ~= nil
	page.search:SetShown(not dungeon)
	page.level:SetShown(not dungeon)
	for _, f in ipairs(page.dungeonOnly) do
		f:SetShown(dungeon)
	end
	if not dungeon then
		page.right.thumb:Hide() -- the scroll bar isn't the scroll frame's child; it shows itself when there's more
	end
	if dungeon then
		DrawDungeon()
	else
		page.stage:Hide()
		page.level:SetText(("You're level %d"):format(UnitLevel("player")))
		page.left:ClearAllPoints()
		page.left:SetPoint("TOPLEFT", 0, -(PAD + TOP_H))
		page.left:SetPoint("BOTTOMRIGHT", -12, 0)
		local y = J.DrawDungeons(page.left:GetWidth() - 2 * PAD)
		page.left:SetContentHeight(y + PAD)
	end
	J.HideUnusedParts()
	J.HideUnusedTiles()
end
J.Layout = Layout

local relayout = UI.Debounce(RELAYOUT, Layout)

local VERDICT_EVENTS = { PLAYER_EQUIPMENT_CHANGED = true, PLAYER_LEVEL_UP = true, SKILL_LINES_CHANGED = true }

local function OnEvent(_, event, id, success)
	if event == "ITEM_DATA_LOAD_RESULT" and success == false then
		J.missing[id] = true
	elseif VERDICT_EVENTS[event] then
		J.ResetVerdicts()
	end
	relayout()
end

-- Building --------------------------------------------------------------------------------------------------------------

local function ShowEntrance()
	local inst = S.inst
	local map, x, y = J.Entrance(inst)
	if not map then
		ns.Print(("%s: its entrance isn't known yet. Once you've found it, the map knows it too."):format(inst.name))
		return
	end
	J.PinClick({ pin = { map = map, x = x, y = y, label = inst.name, zone = J.MapName(map) } })
end

local function CreateHeader()
	page.dungeonOnly = {}
	local function Only(f)
		page.dungeonOnly[#page.dungeonOnly + 1] = f
		return f
	end

	local back = Only(UI.Button(page, 120, "All dungeons"))
	back:SetHeight(26)
	UI.FitButton(back, 110, 28, true)
	back:SetPoint("TOPLEFT", PAD, -PAD - 2)
	back:SetScript("OnClick", function()
		UI.Sound("nav")
		S.inst, S.pick, S.mark = nil, nil, nil
		Layout()
	end)

	page.name = Only(UI.Text(page, 26, "heading", "title"))
	page.name:SetPoint("LEFT", back, "RIGHT", 16, 0)
	page.about = Only(UI.Text(page, 13, "textMuted"))
	page.about:SetPoint("BOTTOMLEFT", page.name, "BOTTOMRIGHT", 12, 2)

	page.tabs = Only(UI.Segmented(page))
	page.tabs:SetPoint("TOPRIGHT", -PAD - 12, -PAD - 2)
	page.tabs.choices = function()
		return { { value = "quests", text = "Quests" }, { value = "bosses", text = "Bosses" } }
	end
	page.tabs.getValue = function()
		return S.tab
	end
	page.tabs.setValue = function(value)
		if value ~= S.tab then
			S.tab, S.pick, S.mark = value, nil, nil
			page.left:SetVerticalScroll(0)
			page.right:SetVerticalScroll(0)
			Layout()
		end
	end

	local entrance = Only(UI.Button(page, 120, "Show entrance"))
	entrance:SetHeight(26)
	UI.FitButton(entrance, 110, 28, true)
	entrance:SetPoint("RIGHT", page.tabs, "LEFT", -12, 0)
	entrance:SetScript("OnClick", ShowEntrance)
	entrance:SetScript("OnEnter", function(self)
		UI.HoverOn(self)
		GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
		GameTooltip:SetText("Show entrance", UI.RGB("heading"))
		UI.TipLine("Puts a pin on the map at the dungeon's door.", "textMuted")
		GameTooltip:Show()
	end)
	entrance:HookScript("OnLeave", function()
		GameTooltip:Hide()
	end)
end

local function CreateBody()
	local top = PAD + HEAD_H
	page.well = J.CreateWell(page)
	page.well:SetPoint("TOPLEFT", 0, -top)
	page.well:SetPoint("BOTTOMLEFT", 0, 0)
	page.well:SetWidth(LIST_W)
	page.dungeonOnly[#page.dungeonOnly + 1] = page.well

	-- The well's foot in the quests tab: the other side's quests switch.
	page.foot = CreateFrame("Frame", nil, page.well)
	page.foot:SetPoint("BOTTOMLEFT", WELL_INSET, WELL_INSET)
	page.foot:SetPoint("BOTTOMRIGHT", -WELL_INSET, WELL_INSET)
	page.foot:SetHeight(FOOT_H - WELL_INSET)
	page.foot.rule = UI.Hairline(page.foot, 10, 0.6, "rule")
	page.foot.rule:SetPoint("TOPLEFT")
	page.foot.rule:SetPoint("TOPRIGHT")
	page.other = UI.Switch(page.foot)
	page.other:SetPoint("RIGHT", -PAD, 0)
	page.other.onChange = function(on)
		J.DB().otherSide = on
		S.pick = nil
		page.right:SetVerticalScroll(0)
		Layout()
	end
	local otherLabel = UI.Text(page.foot, 12, "textMuted")
	otherLabel:SetPoint("LEFT", PAD, 0)
	otherLabel:SetText("Other side's quests")

	page.right = UI.Scroll(page)
	page.right.onWidthChanged = Layout
	page.dungeonOnly[#page.dungeonOnly + 1] = page.right

	page.stage = J.CreateStage(page)
	page.stage:SetPoint("TOPLEFT", page.well, "TOPRIGHT", GAP, 0)
	page.stage:SetPoint("RIGHT", page, "RIGHT", -12, 0)
	page.stage:SetFrameLevel(page.right:GetFrameLevel() + 5) -- its shadow falls on the loot
	page.right:SetPoint("TOPLEFT", page.stage, "BOTTOMLEFT", -PAD + 2, 0)
	page.right:SetPoint("BOTTOMRIGHT", -12, 0)

	-- Usable by you, on the band in the bosses tab.
	page.usable = UI.Switch(page.stage)
	page.usable:SetPoint("TOPRIGHT", -16, -16)
	page.usable.onChange = function(on)
		J.DB().usableOnly = on
		page.right:SetVerticalScroll(0)
		Layout()
	end
	page.usableLabel = UI.Text(page.stage, 12, "textMuted")
	page.usableLabel:SetPoint("RIGHT", page.usable, "LEFT", -8, 0)
	page.usableLabel:SetText("Usable by you")
end

local function Create(frame)
	page = frame
	J.page = page
	page.search = ns.BagsKit_Search(page, "Dungeon, boss, quest or item", function()
		page.left:SetVerticalScroll(0)
		Layout()
	end)
	page.search.help:Hide()
	page.search:SetPoint("TOPLEFT", PAD, -PAD)
	page.search:SetWidth(SEARCH_W)
	page.level = UI.Text(page, 12, "textMuted")
	page.level:SetPoint("RIGHT", page, "TOPRIGHT", -PAD - 16, -PAD - 11)

	CreateHeader()
	page.left = UI.Scroll(page)
	page.left.onWidthChanged = Layout
	CreateBody()

	-- Names come in from the server after the first ask: redraw once a burst of them is in. Only while shown.
	page.events = CreateFrame("Frame", nil, page)
	page.events:SetScript("OnEvent", OnEvent)
	local function Watch()
		for _, event in ipairs({ "ITEM_DATA_LOAD_RESULT", "QUEST_DATA_LOAD_RESULT", "QUEST_LOG_UPDATE",
			"BAG_UPDATE_DELAYED", "PLAYER_EQUIPMENT_CHANGED", "PLAYER_LEVEL_UP", "SKILL_LINES_CHANGED" }) do
			page.events:RegisterEvent(event)
		end
	end
	page:HookScript("OnShow", Watch)
	page:HookScript("OnHide", function()
		page.events:UnregisterAllEvents()
		J.StopPreload()
	end)
	if page:IsShown() then
		Watch()
	end
end

-- Opens a dungeon by instance ID (nil: the list; "here": the dungeon you're in, else the list). Before the page was
-- first opened this waits for Create.
local pendingID

function ns.DJPage_Show(instanceID)
	pendingID = instanceID or false
	if not page then
		return
	end
	local id = pendingID
	pendingID = nil
	if id == "here" then
		local here = ns.DJ_Here()
		id = here and here.id or false
	end
	S.inst, S.pick, S.mark = nil, nil, nil
	for _, d in ipairs(J.List()) do
		if d.id == id then
			J.Open(d)
			return
		end
	end
	Layout()
end

ns.DJPage = {
	title = "Dungeon journal",
	Create = Create,
	Refresh = function()
		if pendingID ~= nil then
			ns.DJPage_Show(pendingID or nil)
		end
		Layout()
	end,
}
