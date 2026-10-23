local addonName, ns = ...

-- Settings sidebar: a rail of group icons (ns.PANEL_GROUPS, Layout.lua), each with its short name under it, and
-- beside it the list column: search, the selected group's name and modules, each with an on/off checkbox. Searching
-- lists matches from every group. Built and refreshed by Panel.lua (ns.PanelSidebar_Create, ns.PanelSidebar_Refresh).

local UI = ns.UI
local RAIL_W = 72
local RAIL_INSET = 3 -- keeps the buttons clear of the window border, which some themes draw over the body's edge
local RAIL_LABEL = 10 -- label font size; a label wider than its button steps down to RAIL_LABEL_MIN
local RAIL_LABEL_MIN = 8
local LIST_W = 176
local SIDEBAR_W = RAIL_W + LIST_W
local RAIL_ROW_H = 46 -- icon, label and a little air above and below
local RAIL_ICON = 24
local ROW_H = 24

local sidebar -- the frames: rail, list column
local searchText = ""
local moduleRows, railButtons = {}, {}
local lastInGroup = {} -- [group key] = module key last shown in it (this session)

local function Selected()
	return ns.Panel_Selected()
end

local function Refresh()
	ns.Panel_Refresh()
end

local function HideTooltip()
	GameTooltip:Hide()
end

local function GroupModules(key)
	local list = {}
	for _, module in ipairs(ns.modules) do
		if module.category == key then
			list[#list + 1] = module
		end
	end
	return list
end

local function SetGroupIcon(texture, group)
	texture:SetTexture(group and group.icon or ns.ICON)
end

local function Select(module)
	ns.db.panel.selected = module.key
	Refresh()
end

-- Rail ---------------------------------------------------------------------------------------------------------

local function SelectGroup(key)
	local modules = GroupModules(key)
	local module = ns.modulesByKey[lastInGroup[key]] or modules[1]
	if not module then
		return
	end
	PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
	if sidebar.search:GetText() ~= "" then
		sidebar.search:SetText("") -- a group click leaves search, or the list would keep showing the matches
		sidebar.search:ClearFocus()
	end
	searchText = ""
	Select(module)
end

local function CreateRailButton(rail, group)
	local b = CreateFrame("Button", nil, rail)
	b:SetHeight(RAIL_ROW_H)
	b.group = group
	b.bg = b:CreateTexture(nil, "BACKGROUND")
	b.bg:SetAllPoints()
	b.bg:SetColorTexture(UI.Color("hover"))
	b.bar = b:CreateTexture(nil, "ARTWORK")
	b.bar:SetColorTexture(UI.Color("accent"))
	b.bar:SetPoint("TOPLEFT")
	b.bar:SetPoint("BOTTOMLEFT")
	b.bar:SetWidth(2)
	b.icon = b:CreateTexture(nil, "ARTWORK")
	b.icon:SetSize(RAIL_ICON, RAIL_ICON)
	b.icon:SetPoint("TOP", 0, -5)
	b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	SetGroupIcon(b.icon, group)
	b.ring = CreateFrame("Frame", nil, b)
	b.ring:SetAllPoints(b.icon)
	UI.Border(b.ring, "frame", 0.6)
	b.name = UI.Text(b, RAIL_LABEL, "text", "label")
	b.name:SetPoint("TOP", b.icon, "BOTTOM", 0, -3)
	b.name:SetWidth(RAIL_W - RAIL_INSET - 4)
	b.name:SetJustifyH("CENTER")
	b.name:SetWordWrap(false)
	b.name:SetText(group.short or group.name)
	-- Wide label fonts (small caps) overflow the button at full size, so those labels step down instead.
	local size = RAIL_LABEL
	while size > RAIL_LABEL_MIN and b.name:GetUnboundedStringWidth() > b.name:GetWidth() do
		size = size - 1
		ns.Theme.SetFont(b.name, "label", size)
	end
	b:SetScript("OnEnter", function(self)
		self.bg:Show()
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText(group.name, UI.Color("heading"))
		local n = #GroupModules(group.key)
		GameTooltip:AddLine(n == 1 and "1 module" or (n .. " modules"), UI.RGB("textMuted"))
		GameTooltip:Show()
	end)
	b:SetScript("OnLeave", function(self)
		self.bg:SetShown(self.selected)
		HideTooltip()
	end)
	b:SetScript("OnClick", function(self)
		SelectGroup(self.group.key)
	end)
	return b
end

local function CreateRail(parent)
	local rail = CreateFrame("Frame", nil, parent)
	rail:SetPoint("TOPLEFT")
	rail:SetPoint("BOTTOMLEFT")
	rail:SetWidth(RAIL_W)
	rail.edge = rail:CreateTexture(nil, "BORDER")
	rail.edge:SetColorTexture(UI.Color("rule"))
	rail.edge:SetAlpha(0.6)
	rail.edge:SetPoint("TOPRIGHT", 0, -12)
	rail.edge:SetPoint("BOTTOMRIGHT", 0, 12)
	rail.edge:SetWidth(1)

	-- The buttons sit on a scroll child: twelve groups don't fit a short window, so the wheel scrolls the rail
	-- (no scrollbar, the rail is too narrow for one).
	local scroll = CreateFrame("ScrollFrame", nil, rail)
	scroll:SetPoint("TOPLEFT")
	scroll:SetPoint("BOTTOMRIGHT", -1, 0)
	local child = CreateFrame("Frame", nil, scroll)
	child:SetWidth(RAIL_W - 1)
	scroll:SetScrollChild(child)
	rail.scroll = scroll
	scroll:EnableMouseWheel(true)
	scroll:SetScript("OnMouseWheel", function(self, delta)
		local max = math.max(0, child:GetHeight() - self:GetHeight())
		self:SetVerticalScroll(math.min(max, math.max(0, self:GetVerticalScroll() - delta * RAIL_ROW_H)))
	end)

	local y = 10
	for i, group in ipairs(ns.PANEL_GROUPS) do
		local b = CreateRailButton(child, group)
		b:SetPoint("TOPLEFT", RAIL_INSET, -y)
		b:SetPoint("RIGHT", child, "RIGHT")
		b.top = y
		railButtons[i] = b
		y = y + RAIL_ROW_H
		if i == 1 then -- Tomte is pinned: a short rule under it
			local rule = child:CreateTexture(nil, "ARTWORK")
			rule:SetColorTexture(UI.Color("rule"))
			rule:SetAlpha(0.6)
			rule:SetHeight(1)
			rule:SetPoint("TOPLEFT", 10, -(y + 4))
			rule:SetPoint("TOPRIGHT", -10, -(y + 4))
			y = y + 9
		end
	end
	child:SetHeight(y + 10)
	return rail
end

-- Scrolls the rail just enough to show button b.
local function ShowRailButton(b)
	local scroll = sidebar.rail.scroll
	local view = scroll:GetHeight()
	if view <= 0 then
		return
	end
	local offset = scroll:GetVerticalScroll()
	if b.top < offset then
		scroll:SetVerticalScroll(math.max(0, b.top - 10))
	elseif b.top + RAIL_ROW_H > offset + view then
		scroll:SetVerticalScroll(b.top + RAIL_ROW_H + 10 - view)
	end
end

local function RefreshRail(current)
	for _, b in ipairs(railButtons) do
		local modules = GroupModules(b.group.key)
		local usable = false
		for _, module in ipairs(modules) do
			if not ns.ModuleBlockedReason(module) then
				usable = true
				break
			end
		end
		b.selected = current ~= nil and current.category == b.group.key
		b.bar:SetShown(b.selected)
		b.bg:SetShown(b.selected or b:IsMouseOver())
		b.icon:SetDesaturated(not usable)
		b.icon:SetAlpha(usable and 1 or 0.5)
		UI.SetTextRole(b.name, usable and (b.selected and "heading" or "text") or "textFaint")
		if b.selected then
			ShowRailButton(b)
		end
	end
end

-- Module list ----------------------------------------------------------------------------------------------------

local function CreateModuleRow(parent)
	local row = CreateFrame("Button", nil, parent)
	row:SetHeight(ROW_H)
	row.bg = row:CreateTexture(nil, "BACKGROUND")
	row.bg:SetAllPoints()
	row.bg:SetColorTexture(UI.Color("hover"))
	row.bar = row:CreateTexture(nil, "ARTWORK")
	row.bar:SetColorTexture(UI.Color("accent"))
	row.bar:SetPoint("TOPLEFT")
	row.bar:SetPoint("BOTTOMLEFT")
	row.bar:SetWidth(2)
	row.check = UI.Checkbox(row)
	row.check:SetPoint("LEFT", 12, 0)
	row.groupIcon = row:CreateTexture(nil, "ARTWORK")
	row.groupIcon:SetSize(14, 14)
	row.groupIcon:SetPoint("RIGHT", -8, 0)
	row.groupIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	row.name = UI.Text(row, 13, "text")
	row.name:SetPoint("LEFT", row.check, "RIGHT", 10, 0)
	row.name:SetWordWrap(false)

	local function Enter()
		local module = row.module
		row.bg:Show()
		GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
		GameTooltip:SetText(module.name, UI.Color("heading"))
		local about = module.summary or module.description
		if about then
			GameTooltip:AddLine(about, 1, 1, 1, true)
		end
		local reason = ns.ModuleBlockedReason(module)
		if reason then
			local r, g, b = UI.Color("danger")
			GameTooltip:AddLine(reason, r, g, b, true)
		end
		GameTooltip:Show()
	end
	local function Leave()
		row.bg:SetShown(row.module == Selected())
		HideTooltip()
	end
	row:SetScript("OnEnter", Enter)
	row:SetScript("OnLeave", Leave)
	row.check:HookScript("OnEnter", Enter)
	row.check:HookScript("OnLeave", Leave)
	row:SetScript("OnClick", function()
		Select(row.module)
	end)
	row.check.onChange = function(checked)
		ns.SetModuleEnabled(row.module.key, checked)
		Refresh()
	end
	return row
end

-- searching: the row shows its group's icon on the right.
local function SetRow(row, module, selected, searching)
	row.module = module
	local reason = ns.ModuleBlockedReason(module)
	row.check:SetChecked(ns.ModuleEnabled(module))
	row.check:SetEnabled(reason == nil and not module.alwaysOn)
	UI.SetTextRole(row.name, reason and "textFaint" or (selected and "heading" or "text"))
	row.name:SetText(module.name)
	row.groupIcon:SetShown(searching)
	if searching then
		SetGroupIcon(row.groupIcon, ns.PanelLayout_Group(module.category))
	end
	row.name:SetPoint("RIGHT", searching and row.groupIcon or row, searching and "LEFT" or "RIGHT", -8, 0)
	row.bar:SetShown(selected)
	row.bg:SetShown(selected or row:IsMouseOver())
end

local function RefreshList()
	local list = sidebar.list
	local content = list.content
	local current = Selected()
	if current then
		lastInGroup[current.category] = current.key
	end
	RefreshRail(current)

	local searching = searchText ~= ""
	local modules = {}
	if searching then
		for _, module in ipairs(ns.modules) do
			local group = ns.PanelLayout_Group(module.category)
			if ns.PanelLayout_Matches(module, group and group.name, searchText) then
				modules[#modules + 1] = module
			end
		end
		sidebar.heading:SetText("Search")
		sidebar.about:SetText(#modules == 1 and "1 module" or (#modules .. " modules"))
	else
		local group = current and ns.PanelLayout_Group(current.category)
		modules = group and GroupModules(group.key) or {}
		sidebar.heading:SetText(group and group.name or "")
		sidebar.about:SetText(group and group.description or "")
	end

	local y = 0
	for i, module in ipairs(modules) do
		local row = moduleRows[i] or CreateModuleRow(content)
		moduleRows[i] = row
		row:ClearAllPoints()
		row:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
		row:SetPoint("RIGHT", content, "RIGHT")
		SetRow(row, module, module == current, searching)
		row:Show()
		y = y + ROW_H
	end
	for i = #modules + 1, #moduleRows do
		moduleRows[i]:Hide()
	end
	sidebar.noMatches:SetShown(searching and #modules == 0)
	list:SetContentHeight(y + 8)
end

local function CreateSearch(parent)
	local box = CreateFrame("EditBox", nil, parent)
	box:SetHeight(22)
	box:SetPoint("TOPLEFT", 12, -14)
	box:SetPoint("RIGHT", -12, 0)
	box:SetAutoFocus(false)
	UI.SetFont(box, "body", 12)
	UI.SetTextRole(box, "text")
	box:SetTextInsets(8, 8, 0, 0)
	UI.Surface(box, 0.35)
	local placeholder = UI.Text(box, 12, "textFaint")
	placeholder:SetPoint("LEFT", 8, 0)
	placeholder:SetText("Search")
	local refresh = UI.Debounce(UI.SEARCH_DELAY, function()
		RefreshList() -- the page keeps showing the selected module, even when it's filtered out
	end)
	box:SetScript("OnTextChanged", function(self)
		local text = self:GetText()
		placeholder:SetShown(text == "")
		searchText = strtrim(text):lower()
		refresh()
	end)
	box:SetScript("OnEscapePressed", function(self)
		self:SetText("")
		self:ClearFocus()
	end)
	box:SetScript("OnEnterPressed", box.ClearFocus)
	box:SetScript("OnEditFocusGained", function(self)
		UI.SetBorderColor(self, "accent", 0.8)
	end)
	box:SetScript("OnEditFocusLost", function(self)
		UI.SetBorderColor(self, "frame", 0.35)
	end)
	return box
end

function ns.PanelSidebar_Create(parent)
	local frame = CreateFrame("Frame", nil, parent)
	frame:SetWidth(SIDEBAR_W)
	sidebar = frame
	frame.rail = CreateRail(frame)

	local column = CreateFrame("Frame", nil, frame)
	column:SetPoint("TOPLEFT", RAIL_W, 0)
	column:SetPoint("BOTTOMRIGHT")
	frame.search = CreateSearch(column)
	frame.heading = UI.Text(column, 15, "heading", "title")
	frame.heading:SetPoint("TOPLEFT", frame.search, "BOTTOMLEFT", 0, -14)
	frame.heading:SetPoint("RIGHT", -12, 0)
	frame.heading:SetWordWrap(false)
	frame.about = UI.Text(column, 11, "textMuted")
	frame.about:SetPoint("TOPLEFT", frame.heading, "BOTTOMLEFT", 0, -4)
	frame.about:SetPoint("RIGHT", -12, 0)
	frame.about:SetWordWrap(true)
	frame.about:SetHeight(28) -- two lines, so the list starts at the same place in every group
	frame.about:SetMaxLines(2)
	frame.about:SetJustifyV("TOP")
	local list = UI.Scroll(column)
	list:SetPoint("TOPLEFT", frame.about, "BOTTOMLEFT", -12, -6)
	list:SetPoint("BOTTOMRIGHT", -10, 10)
	frame.list = list
	frame.noMatches = UI.Text(list.content, 12, "textMuted")
	frame.noMatches:SetPoint("TOP", list, "TOP", 0, -20)
	frame.noMatches:SetText("No matching modules.")
	return frame
end

function ns.PanelSidebar_Refresh()
	RefreshList()
end
