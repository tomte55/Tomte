local addonName, ns = ...

-- Dressing room, title manager: the character window's title list (PaperDollFrame.TitleManagerPane) gets a search box
-- and an Owned / Missing / All filter. Our own list lies over Blizzard's while the pane is open (Blizzard's is faded
-- out underneath and back when ours hides), so Blizzard's list and its functions stay untouched; a click on an owned
-- title sets it (SetCurrentTitle, from the click). Filtering and sorting in Data.lua; registered in DressUp.lua.

local OWNER = "dressupTitles"
local ROW_H = 20
local SEARCH_H = 22
local GAP = 4
local THUMB_ROOM = 10 -- UI.Scroll's thumb sits right of the list
local COVER_RIGHT = 22 -- Blizzard's scroll bar sits 8 px right of the 172 px pane: covered too
local NO_TITLE = -1 -- Blizzard's id for "no title" (PaperDollFrame.lua)

local UI = ns.UI
local FilterTitles = ns.DressUp_FilterTitles
local FILTERS = ns.DRESSUP_TITLE_FILTERS
local events = ns.DressUp_Events

local module, db
local hooked = false
local view -- our list over the pane
local rows = {}

local function On()
	return module and module.active and db.titles
end

local function Pane()
	return PaperDollFrame and PaperDollFrame.TitleManagerPane
end

local function FadeBlizzard(faded)
	local pane = Pane()
	if not pane then
		return
	end
	for _, part in ipairs({ pane.ScrollBox, pane.ScrollBar }) do
		part:SetAlpha(faded and 0 or 1)
	end
end

local function AllTitles()
	local list = {}
	for id = 1, GetNumTitles() do
		-- isPlayerTitle: Blizzard's own list (PaperDollFrame.lua GetKnownTitles) skips ids where it's false.
		local name, isPlayerTitle = GetTitleName(id)
		if name and isPlayerTitle then
			list[#list + 1] = { id = id, name = name, known = IsTitleKnown(id) }
		end
	end
	return list
end

-- Rows ---------------------------------------------------------------------------------------------------------------

local function RowEnter(row)
	row.hover:Show()
	if row.known == false then
		GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
		UI.TipLine(row.label:GetText(), "heading")
		UI.TipLine("Not earned yet", "textMuted")
		GameTooltip:Show()
	end
end

local function RowLeave(row)
	row.hover:Hide()
	GameTooltip_Hide()
end

local function RowClick(row)
	if row.known == false then
		return
	end
	UI.Sound("pick")
	SetCurrentTitle(row.titleID)
end

local function Row(i)
	local row = rows[i]
	if row then
		return row
	end
	row = CreateFrame("Button", nil, view.scroll.content)
	row:SetHeight(ROW_H)
	row:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_H)
	row:SetPoint("RIGHT")
	row.hover = row:CreateTexture(nil, "BACKGROUND")
	row.hover:SetAllPoints()
	row.hover:SetColorTexture(UI.Color("hover"))
	row.hover:Hide()
	row.mark = row:CreateTexture(nil, "ARTWORK")
	row.mark:SetPoint("TOPLEFT")
	row.mark:SetPoint("BOTTOMLEFT")
	row.mark:SetWidth(2)
	row.mark:SetColorTexture(UI.Color("accent"))
	row.label = UI.Text(row, 12, "text")
	row.label:SetPoint("LEFT", 8, 0)
	row.label:SetPoint("RIGHT", -4, 0)
	row.label:SetWordWrap(false)
	row:SetScript("OnEnter", RowEnter)
	row:SetScript("OnLeave", RowLeave)
	row:SetScript("OnClick", RowClick)
	rows[i] = row
	return row
end

local function Refresh()
	if not (view and view:IsShown()) then
		return
	end
	local current = GetCurrentTitle()
	local list = FilterTitles(AllTitles(), view.search:GetText(), db.titleFilter)
	-- "No title" first, as in Blizzard's list, while owned titles show and nothing is searched.
	if db.titleFilter ~= "missing" and strtrim(view.search:GetText()) == "" then
		table.insert(list, 1, { id = NO_TITLE, name = PLAYER_TITLE_NONE, known = true })
	end
	for i, t in ipairs(list) do
		local row = Row(i)
		row.titleID, row.known = t.id, t.known
		row.label:SetText(t.name)
		local selected = t.id == current or (t.id == NO_TITLE and (current or 0) <= 0)
		UI.SetTextRole(row.label, not t.known and "textFaint" or selected and "accent" or "text")
		row.mark:SetShown(selected)
		row:Show()
	end
	for i = #list + 1, #rows do
		rows[i]:Hide()
	end
	view.empty:SetShown(#list == 0)
	view.scroll:SetContentHeight(#list * ROW_H)
end

-- The view -----------------------------------------------------------------------------------------------------------

local function SearchBox(parent)
	local box = CreateFrame("EditBox", nil, parent)
	box:SetHeight(SEARCH_H)
	box:SetAutoFocus(false)
	UI.SearchBoxClear(box)
	UI.SetFont(box, "body", 12)
	UI.SetTextRole(box, "text")
	box:SetTextInsets(8, 8, 0, 0)
	UI.Surface(box, 0.35)
	local placeholder = UI.Text(box, 12, "textFaint")
	placeholder:SetPoint("LEFT", 8, 0)
	placeholder:SetText("Search titles")
	local refresh = UI.Debounce(UI.SEARCH_DELAY, Refresh)
	box:SetScript("OnTextChanged", function(self)
		placeholder:SetShown(self:GetText() == "")
		refresh()
	end)
	box:SetScript("OnEscapePressed", function(self)
		self:SetText("")
		self:ClearFocus()
	end)
	box:SetScript("OnEnterPressed", box.ClearFocus)
	return box
end

local function CreateView(pane)
	view = CreateFrame("Frame", nil, pane)
	view:SetPoint("TOPLEFT", pane, "TOPLEFT")
	view:SetPoint("BOTTOMRIGHT", pane, "BOTTOMRIGHT", COVER_RIGHT, 0)
	view:SetFrameLevel(pane.ScrollBox:GetFrameLevel() + 20)
	view:EnableMouse(true)
	view.search = SearchBox(view)
	view.search:SetPoint("TOPLEFT", 2, -2)
	view.search:SetPoint("TOPRIGHT", -2, -2)
	view.filter = UI.Segmented(view)
	view.filter:SetPoint("TOPLEFT", view.search, "BOTTOMLEFT", 0, -GAP)
	view.filter.choices = function()
		return FILTERS
	end
	view.filter.getValue = function()
		return db.titleFilter
	end
	view.filter.setValue = function(value)
		db.titleFilter = value
		Refresh()
	end
	view.scroll = UI.Scroll(view)
	view.scroll:SetPoint("TOPLEFT", view.filter, "BOTTOMLEFT", 0, -GAP)
	view.scroll:SetPoint("BOTTOMRIGHT", -THUMB_ROOM, 2)
	view.empty = UI.Text(view, 12, "textMuted")
	view.empty:SetPoint("TOP", view.scroll, "TOP", 0, -12)
	view.empty:SetText("No titles found")
	view:SetScript("OnShow", function()
		FadeBlizzard(true)
		view.filter:Refresh()
		Refresh()
	end)
	view:SetScript("OnHide", function()
		FadeBlizzard(false)
	end)
	view:Hide()
end

local function Update()
	local pane = Pane()
	if not (view and pane) then
		return
	end
	view:SetShown(On() and pane:IsShown() or false)
end

local function Hook()
	local pane = Pane()
	if hooked or not pane then
		return
	end
	hooked = true -- hooks can't be undone: Update checks On()
	CreateView(pane)
	pane:HookScript("OnShow", Update)
	Update()
end

events:On(OWNER, "KNOWN_TITLES_UPDATE", Refresh)
events:On(OWNER, "UNIT_NAME_UPDATE", Refresh)

function ns.DressUp_TitlesInit(mod, settings)
	module, db = mod, settings
end

-- On toggle and when the setting changes.
function ns.DressUp_TitlesUpdate()
	if On() then
		events:Watch(OWNER, "KNOWN_TITLES_UPDATE")
		events:Watch(OWNER, "UNIT_NAME_UPDATE", "player")
		if not hooked then
			EventUtil.ContinueOnAddOnLoaded("Blizzard_UIPanels_Game", Hook)
		end
	else
		events:UnwatchAll(OWNER)
	end
	Update()
end
