local addonName, ns = ...

-- Settings sidebar: search and every module grouped under collapsible categories, each with an on/off checkbox.
-- Built and refreshed by Panel.lua (ns.PanelSidebar_Create, ns.PanelSidebar_Refresh).

local UI = ns.UI
local SIDEBAR_W = 220
local ROW_H, HEADER_H = 24, 26

local sidebar -- the frames: list, search, noMatches
local searchText = ""
local moduleRows, listHeaders = {}, {}

local function Selected()
	return ns.Panel_Selected()
end

local function Refresh()
	ns.Panel_Refresh()
end

local function HideTooltip()
	GameTooltip:Hide()
end

local RefreshList -- forward declaration

local function Select(module)
	ns.db.panel.selected = module.key
	Refresh()
end

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
	row.name = UI.Text(row, 13, "text")
	row.name:SetPoint("LEFT", row.check, "RIGHT", 10, 0)
	row.name:SetPoint("RIGHT", -8, 0)
	row.name:SetWordWrap(false)

	local function Enter()
		local module = row.module
		row.bg:Show()
		GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
		GameTooltip:SetText(module.name, UI.Color("heading"))
		if module.description then
			GameTooltip:AddLine(module.description, 1, 1, 1, true)
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

local function SetRow(row, module, selected)
	row.module = module
	local reason = ns.ModuleBlockedReason(module)
	row.check:SetChecked(ns.ModuleEnabled(module))
	row.check:SetEnabled(reason == nil and not module.alwaysOn)
	UI.SetTextRole(row.name, reason and "textFaint" or (selected and "heading" or "text"))
	row.name:SetText(module.name)
	row.bar:SetShown(selected)
	row.bg:SetShown(selected or row:IsMouseOver())
end

-- Category header: click to collapse or expand it (saved). While searching, every match shows.
local function CreateCategoryHeader(parent)
	local b = CreateFrame("Button", nil, parent)
	b:SetHeight(HEADER_H)
	b.toggle = UI.Text(b, 12, "textMuted")
	b.toggle:SetPoint("BOTTOMLEFT", 10, 6)
	b.toggle:SetWidth(10)
	b.text = UI.Text(b, 11, "textMuted", "label")
	b.text:SetPoint("BOTTOMLEFT", b.toggle, "BOTTOMRIGHT", 4, 0)
	b.count = UI.Text(b, 11, "textFaint", "number")
	b.count:SetPoint("BOTTOMRIGHT", -10, 6)
	b:SetScript("OnEnter", function(self)
		UI.SetTextRole(self.text, "text")
	end)
	b:SetScript("OnLeave", function(self)
		UI.SetTextRole(self.text, self.color)
	end)
	b:SetScript("OnClick", function(self)
		local collapsed = ns.db.panel.collapsed
		collapsed[self.category] = not collapsed[self.category] or nil
		PlaySound(collapsed[self.category] and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
		RefreshList()
	end)
	return b
end

function RefreshList()
	local list = sidebar.list
	local content = list.content
	local current = Selected()
	local searching = searchText ~= ""
	local rowCount, headerCount, y = 0, 0, 0
	for _, cat in ipairs(ns.ModuleCategories()) do
		local matches = {}
		for _, module in ipairs(ns.modules) do
			if module.category == cat and ns.ModuleMatches(module, searchText) then
				matches[#matches + 1] = module
			end
		end
		if #matches > 0 then
			local collapsed = not searching and ns.db.panel.collapsed[cat] == true
			headerCount = headerCount + 1
			local header = listHeaders[headerCount] or CreateCategoryHeader(content)
			listHeaders[headerCount] = header
			header.category = cat
			header:SetEnabled(not searching)
			header.toggle:SetText(searching and "" or (collapsed and "+" or "-"))
			header.text:SetText(cat:upper())
			header.count:SetText(#matches)
			-- A collapsed category holding the selected module stays in the accent, so you can see where it is.
			header.color = (collapsed and current and current.category == cat) and "accent" or "textMuted"
			UI.SetTextRole(header.text, header.color)
			header:ClearAllPoints()
			header:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
			header:SetPoint("RIGHT", content, "RIGHT")
			header:Show()
			y = y + HEADER_H
			if not collapsed then
				for _, module in ipairs(matches) do
					rowCount = rowCount + 1
					local row = moduleRows[rowCount] or CreateModuleRow(content)
					moduleRows[rowCount] = row
					row:ClearAllPoints()
					row:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
					row:SetPoint("RIGHT", content, "RIGHT")
					SetRow(row, module, module == current)
					row:Show()
					y = y + ROW_H
				end
			end
		end
	end
	for i = rowCount + 1, #moduleRows do
		moduleRows[i]:Hide()
	end
	for i = headerCount + 1, #listHeaders do
		listHeaders[i]:Hide()
	end
	sidebar.noMatches:SetShown(headerCount == 0)
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
	frame.search = CreateSearch(frame)
	local list = UI.Scroll(frame)
	list:SetPoint("TOPLEFT", frame.search, "BOTTOMLEFT", -8, -10)
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
