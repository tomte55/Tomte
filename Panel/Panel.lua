local addonName, ns = ...

-- The Tomte window: standalone and resizable (/tomte, the addon compartment, the minimap button; Esc closes it).
-- Size and position are saved. Three views:
--   home     tiles for content pages and world map tabs, a Quick row (Home.lua). Every open starts here.
--   page     a content page (module.home entry of kind "page") with the rail (Home.lua) on the left.
--   settings left: search and every module grouped under collapsible categories, each with an on/off checkbox.
--            Right: the selected module: header, dependency lines, "Open <page>" buttons, its options (Options.lua).
-- Options > AddOns only has a button that opens it. Built on first use.

local UI = ns.UI
local DEFAULT_W, DEFAULT_H = 960, 640
local MIN_W, MIN_H = 820, 560
local SIDEBAR_W = 220
local OPTIONS_MAX_W = 560
local TITLE_H = 36
local ROW_H, HEADER_H = 24, 26
local PAD = 24 -- page text inset; content frames sit 8 px further out

local panel, escape
local searchText = ""
local moduleRows, listHeaders = {}, {}
local view, openEntry = "home", nil -- this session; openEntry is the page shown in the page view
local Refresh, RefreshList, RefreshPage -- forward declarations

-- The saved selection, or the first module when there is none (or it no longer exists).
local function Selected()
	local key = ns.db.panel.selected
	return key and ns.modulesByKey[key] or ns.modules[1]
end

local function HideTooltip()
	GameTooltip:Hide()
end

-- Window size and position -------------------------------------------------------------------------------

local function Clamp(value, low, high)
	return math.min(math.max(value, low), high)
end

-- Max is the screen, which can be smaller than the saved size after a resolution or UI scale change.
local function ApplyLayout()
	local maxW, maxH = math.max(UIParent:GetWidth(), MIN_W), math.max(UIParent:GetHeight(), MIN_H)
	panel:SetResizeBounds(MIN_W, MIN_H, maxW, maxH)
	local layout = ns.db.panel.layout
	panel:ClearAllPoints()
	if layout then
		panel:SetSize(Clamp(layout.w, MIN_W, maxW), Clamp(layout.h, MIN_H, maxH))
		panel:SetPoint(layout.point, UIParent, layout.relPoint, layout.x, layout.y)
	else
		panel:SetSize(DEFAULT_W, DEFAULT_H)
		panel:SetPoint("CENTER")
	end
end

local function SaveLayout()
	local point, _, relPoint, x, y = panel:GetPoint(1)
	ns.db.panel.layout = { point = point, relPoint = relPoint, x = x, y = y, w = panel:GetWidth(), h = panel:GetHeight() }
end

-- Sidebar ------------------------------------------------------------------------------------------------

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
	b.text = UI.Text(b, 11, "textMuted", "title")
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
	local list = panel.list
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
	panel.noMatches:SetShown(headerCount == 0)
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

local function CreateSidebar(parent)
	local sidebar = CreateFrame("Frame", nil, parent)
	sidebar:SetWidth(SIDEBAR_W)
	panel.search = CreateSearch(sidebar)
	local list = UI.Scroll(sidebar)
	list:SetPoint("TOPLEFT", panel.search, "BOTTOMLEFT", -8, -10)
	list:SetPoint("BOTTOMRIGHT", -10, 10)
	panel.list = list
	panel.noMatches = UI.Text(list.content, 12, "textMuted")
	panel.noMatches:SetPoint("TOP", list, "TOP", 0, -20)
	panel.noMatches:SetText("No matching modules.")
	return sidebar
end

-- Module settings page -----------------------------------------------------------------------------------

-- The options column is capped so a slider doesn't end up far from its label on a wide panel.
local function UpdateOptionsWidth()
	local page = panel.page
	page.options:SetWidth(math.min(page:GetWidth() - 2 * (PAD - 8) - 10, OPTIONS_MAX_W))
end

local function IsLoaded(addon)
	return C_AddOns.IsAddOnLoaded(addon) and true or false
end

local function CreatePage(parent)
	local page = CreateFrame("Frame", nil, parent)
	page.title = UI.Text(page, 19, "heading", "title")
	page.title:SetPoint("TOPLEFT", PAD, -16)
	page.title:SetWordWrap(false)

	-- "Enabled" checkbox; the label toggles it too.
	local toggle = CreateFrame("Button", nil, page)
	toggle:SetPoint("TOPRIGHT", -PAD, -20)
	toggle:SetHeight(20)
	toggle.check = UI.Checkbox(toggle)
	toggle.check:SetPoint("RIGHT")
	toggle.label = UI.Text(toggle, 13, "text")
	toggle.label:SetPoint("RIGHT", toggle.check, "LEFT", -8, 0)
	toggle.label:SetText("Enabled")
	toggle:SetWidth(toggle.label:GetStringWidth() + 24)
	toggle:SetScript("OnClick", function(self)
		if self.check:IsEnabled() then
			self.check:Click()
		end
	end)
	toggle.check.onChange = function(checked)
		ns.SetModuleEnabled(Selected().key, checked)
		Refresh()
	end
	page.toggle = toggle
	page.title:SetPoint("RIGHT", toggle, "LEFT", -16, 0)

	page.desc = UI.Text(page, 12, "textMuted")
	page.desc:SetPoint("TOPLEFT", page.title, "BOTTOMLEFT", 0, -8)
	page.desc:SetPoint("RIGHT", -PAD, 0)
	page.desc:SetWordWrap(true)
	page.reason = UI.Text(page, 12, "danger")
	page.reason:SetPoint("TOPLEFT", page.desc, "BOTTOMLEFT", 0, -8)
	page.reason:SetPoint("RIGHT", -PAD, 0)
	page.reason:SetWordWrap(true)
	page.deps = {} -- Uses / Conflicts lines (green when fine, red when not)
	page.openButtons = {} -- "Open <page>" for the module's content pages

	page.options = UI.Scroll(page)
	page.none = UI.Text(page, 12, "textMuted")
	page.none:SetText("No options.")
	page:SetScript("OnSizeChanged", UpdateOptionsWidth)
	return page
end

function RefreshPage()
	local page = panel.page
	local module = Selected()
	if not module then
		return
	end
	page.title:SetText(module.name)
	page.desc:SetText(module.description or "")
	local reason = ns.ModuleBlockedReason(module)
	page.reason:SetText(reason or "")
	page.reason:SetShown(reason ~= nil)
	page.toggle.check:SetChecked(ns.ModuleEnabled(module))
	page.toggle.check:SetEnabled(reason == nil)
	page.toggle:SetShown(not module.alwaysOn)
	UI.SetTextRole(page.toggle.label, reason and "textFaint" or "text")

	-- Content starts under the last header line.
	local top = reason and page.reason or page.desc
	local lines = ns.ModuleDependencies(module, IsLoaded)
	for i, line in ipairs(lines) do
		local fs = page.deps[i]
		if not fs then
			fs = UI.Text(page, 12, "textMuted")
			fs:SetWordWrap(true)
			page.deps[i] = fs
		end
		UI.SetTextRole(fs, line.ok and "success" or "danger")
		fs:SetText(line.text)
		fs:ClearAllPoints()
		fs:SetPoint("TOPLEFT", top, "BOTTOMLEFT", 0, i == 1 and -10 or -4)
		fs:SetPoint("RIGHT", -PAD, 0)
		fs:Show()
		top = fs
	end
	for i = #lines + 1, #page.deps do
		page.deps[i]:Hide()
	end

	-- Nothing below the header while blocked (its data may be getting replaced).
	local open = reason == nil
	local shownButtons, x = 0, 0
	for _, entry in ipairs(open and ns.ModulePages(module) or {}) do
		if ns.HomeEntryVisible(entry) then
			shownButtons = shownButtons + 1
			local b = page.openButtons[shownButtons]
			if not b then
				b = UI.Button(page, 80, "")
				b:SetHeight(22)
				b:SetScript("OnClick", function(self)
					ns.Panel_OpenPage(self.entry.key)
				end)
				page.openButtons[shownButtons] = b
			end
			b.entry = entry
			b.label:SetText("Open " .. entry.name .. " >")
			b:SetWidth(b.label:GetStringWidth() + 24)
			b:ClearAllPoints()
			b:SetPoint("TOPLEFT", top, "BOTTOMLEFT", x, -14)
			b:Show()
			x = x + b:GetWidth() + 8
		end
	end
	for i = shownButtons + 1, #page.openButtons do
		page.openButtons[i]:Hide()
	end
	if shownButtons > 0 then
		top = page.openButtons[1]
	end

	local showOptions = open and module.options ~= nil and #module.options > 0
	page.options:SetShown(showOptions)
	if showOptions then
		page.options:ClearAllPoints()
		page.options:SetPoint("TOPLEFT", top, "BOTTOMLEFT", -8, -12)
		page.options:SetPoint("BOTTOMLEFT", page, "BOTTOMLEFT", PAD - 8, 14)
		UpdateOptionsWidth()
		ns.PanelOptions_Build(page.options, module)
	else
		ns.PanelOptions_Release()
	end
	page.none:SetShown(open and not showOptions and shownButtons == 0)
	page.none:ClearAllPoints()
	page.none:SetPoint("TOPLEFT", top, "BOTTOMLEFT", 0, -16)
end

-- Content page view ---------------------------------------------------------------------------------------

local function CreatePageView(parent)
	local pv = CreateFrame("Frame", nil, parent)
	pv.rail = ns.PanelRail_Create(pv, function(entry)
		if not entry then
			view, openEntry = "home", nil
			Refresh()
		elseif entry.kind == "map" then
			ns.Panel_OpenMap(entry)
		else
			ns.Panel_OpenPage(entry.key)
		end
	end)
	pv.rail:SetPoint("TOPLEFT")
	pv.rail:SetPoint("BOTTOMLEFT")
	local host = CreateFrame("Frame", nil, pv)
	host:SetPoint("TOPLEFT", pv.rail, "TOPRIGHT")
	host:SetPoint("BOTTOMRIGHT")
	host.title = UI.Text(host, 19, "heading", "title")
	host.title:SetPoint("TOPLEFT", PAD, -16)
	host.title:SetWordWrap(false)
	host.uses = UI.Text(host, 12, "textMuted")
	host.uses:SetPoint("TOPRIGHT", -PAD, -22)
	host.uses:SetJustifyH("RIGHT")
	host.title:SetPoint("RIGHT", host.uses, "LEFT", -16, 0)
	host.frames = {} -- [entry] = frame
	pv.host = host
	return pv
end

local function RefreshPageView()
	local pv = panel.pageView
	local entry = view == "page" and openEntry or nil
	pv.rail:Refresh(entry)
	local host = pv.host
	for owner, frame in pairs(host.frames) do
		if owner ~= entry then
			frame:Hide()
		end
	end
	host.title:SetShown(entry ~= nil)
	host.uses:SetShown(entry ~= nil)
	panel.home:SetShown(entry == nil)
	if not entry then
		panel.home:Refresh()
		return
	end
	host.title:SetText(entry.name)
	-- Only the addons it uses; conflicts are a settings matter.
	local parts = {}
	for _, line in ipairs(ns.ModuleDependencies({ uses = entry.module.uses }, IsLoaded)) do
		parts[#parts + 1] = UI.Wrap(line.text, line.ok and "success" or "danger")
	end
	host.uses:SetText(table.concat(parts, "\n"))
	local frame = host.frames[entry]
	if not frame then
		frame = CreateFrame("Frame", nil, host)
		frame:Hide()
		entry.page.Create(frame)
		host.frames[entry] = frame
	end
	frame:ClearAllPoints()
	frame:SetPoint("TOPLEFT", host, "TOPLEFT", PAD - 8, -54)
	frame:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT", -(PAD - 8), 14)
	if not frame:IsShown() then
		frame:Show()
		if entry.page.Refresh then
			entry.page.Refresh(frame) -- only when it becomes visible
		end
	end
end

local function UpdateTitle()
	local tb = panel.titleBar
	if view == "page" and openEntry then
		tb.sub:SetText("- " .. openEntry.name)
	elseif view == "settings" then
		tb.sub:SetText("- Settings")
	else
		tb.sub:SetText("")
	end
	tb.nav.label:SetText(view == "settings" and "< Home" or "Settings")
end

function Refresh()
	if not (panel and panel:IsShown()) then
		return
	end
	-- A page whose module was turned off (or no longer applies) falls back to Home.
	if view == "page" and not (openEntry and ns.HomeEntryVisible(openEntry)) then
		view, openEntry = "home", nil
	end
	-- A page frame left shown would skip its Refresh the next time it's opened.
	if view ~= "page" then
		for _, frame in pairs(panel.pageView.host.frames) do
			frame:Hide()
		end
	end
	panel.pageView:SetShown(view ~= "settings")
	panel.settings:SetShown(view == "settings")
	UpdateTitle()
	if view ~= "settings" then
		RefreshPageView() -- Home is the page view without a page
	else
		RefreshList()
		RefreshPage()
	end
end

-- Window -------------------------------------------------------------------------------------------------

local function CreateTitleBar()
	local titleBar = CreateFrame("Frame", nil, panel)
	titleBar:SetPoint("TOPLEFT")
	titleBar:SetPoint("TOPRIGHT")
	titleBar:SetHeight(TITLE_H)
	titleBar:EnableMouse(true)
	titleBar:RegisterForDrag("LeftButton")
	titleBar:SetScript("OnDragStart", function()
		panel:StartMoving()
	end)
	titleBar:SetScript("OnDragStop", function()
		panel:StopMovingOrSizing()
		SaveLayout()
	end)
	local icon = titleBar:CreateTexture(nil, "ARTWORK")
	icon:SetSize(20, 20)
	icon:SetPoint("LEFT", 14, 0)
	icon:SetTexture(ns.ICON)
	local title = UI.Text(titleBar, 18, "heading", "title")
	title:SetPoint("LEFT", icon, "RIGHT", 8, -2)
	title:SetText("Tomte")
	titleBar.sub = UI.Text(titleBar, 13, "textMuted", "title")
	titleBar.sub:SetPoint("LEFT", title, "RIGHT", 10, 0)
	local close = UI.Button(titleBar, 20, "x")
	close:SetPoint("RIGHT", -10, 0)
	close:SetScript("OnClick", function()
		panel:Hide()
	end)
	-- Settings from Home or a page; back to Home from Settings.
	local nav = UI.Button(titleBar, 84, "Settings")
	nav:SetPoint("RIGHT", close, "LEFT", -8, 0)
	nav:SetScript("OnClick", function()
		PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
		view = view == "settings" and "home" or "settings"
		Refresh()
	end)
	titleBar.nav = nav
	local version = UI.Text(titleBar, 12, "textFaint", "number")
	version:SetPoint("RIGHT", nav, "LEFT", -12, 0)
	version:SetText("v" .. ns.VERSION)
	panel.titleBar = titleBar
	local line = UI.Hairline(titleBar, 100, 0.6)
	line:ClearAllPoints()
	line:SetPoint("BOTTOMLEFT", 20, 0)
	line:SetPoint("BOTTOMRIGHT", -20, 0)
	-- The ink flourish's diamond in the middle of the line.
	local diamond = titleBar:CreateTexture(nil, "OVERLAY")
	diamond:SetTexture(ns.Theme.media.flourish)
	diamond:SetTexCoord(0.44, 0.56, 0, 1)
	diamond:SetSize(18, 10)
	diamond:SetPoint("CENTER", line, "CENTER", 0, 0)
	diamond:SetVertexColor(UI.Color("frame"))
end

local function CreateResizeGrip()
	local grip = CreateFrame("Button", nil, panel)
	grip:SetSize(16, 16)
	grip:SetPoint("BOTTOMRIGHT", -2, 2)
	grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
	grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
	grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
	grip:SetScript("OnMouseDown", function()
		panel:StartSizing("BOTTOMRIGHT")
	end)
	grip:SetScript("OnMouseUp", function()
		panel:StopMovingOrSizing()
		SaveLayout()
	end)
end

local function Build()
	panel = CreateFrame("Frame", "TomtePanel", UIParent)
	panel:SetFrameStrata("HIGH")
	panel:SetToplevel(true)
	panel:EnableMouse(true)
	panel:SetMovable(true)
	panel:SetResizable(true)
	panel:SetDontSavePosition(true) -- we save it ourselves (TomteDB.panel.layout)
	panel:SetClampedToScreen(true)
	panel:Hide()
	panel.look = UI.Panel(panel, { size = "large" })
	ns.Panel_ApplyLook()
	CreateTitleBar()

	local body = CreateFrame("Frame", nil, panel)
	body:SetPoint("TOPLEFT", 0, -TITLE_H)
	body:SetPoint("BOTTOMRIGHT")

	panel.pageView = CreatePageView(body)
	panel.pageView:SetAllPoints()

	-- Home lives in the page view's host, beside the rail.
	panel.home = ns.PanelHome_Create(panel.pageView.host, function(entry)
		if entry.kind == "page" then
			ns.Panel_OpenPage(entry.key)
		elseif entry.kind == "map" or entry.kind == "around" then
			ns.Panel_OpenMap(entry)
		else
			panel:Hide() -- the action shows its own window or card
			entry.open()
		end
	end)
	panel.home:SetAllPoints()

	local settings = CreateFrame("Frame", nil, body)
	settings:SetAllPoints()
	panel.settings = settings
	local sidebar = CreateSidebar(settings)
	sidebar:SetPoint("TOPLEFT")
	sidebar:SetPoint("BOTTOMLEFT")
	local page = CreatePage(settings)
	page:SetPoint("TOPLEFT", sidebar, "TOPRIGHT")
	page:SetPoint("BOTTOMRIGHT")
	panel.page = page
	local divider = UI.VLine(settings)
	divider:SetPoint("TOP", sidebar, "TOPRIGHT", 0, -12)
	divider:SetPoint("BOTTOM", sidebar, "BOTTOMRIGHT", 0, 12)
	CreateResizeGrip()

	panel:SetScript("OnShow", function()
		escape:Show()
		Refresh()
	end)
	panel:SetScript("OnHide", function()
		escape:Hide()
		HideTooltip()
		ns.db.panel.last = { view = view, page = view == "page" and openEntry and openEntry.key or nil, at = GetServerTime() }
		for _, frame in pairs(panel.pageView.host.frames) do
			frame:Hide() -- so the page refreshes when it's shown again
		end
		for _, module in ipairs(ns.modules) do
			if module.panelClosed then
				module.panelClosed()
			end
		end
	end)
end

-- Background opacity from the "Tomte window" settings (Panel/Window.lua).
function ns.Panel_ApplyLook()
	if panel then
		local window = ns.db.window
		panel.look:SetAlpha(window and window.opacity or 0.96)
	end
end

local function Show()
	if not panel then
		Build()
	end
	if panel:IsShown() then
		Refresh()
		return
	end
	ApplyLayout()
	panel:Show() -- OnShow refreshes
end

-- From /tomte, the minimap button or the compartment: back where you were if it was closed a little while ago
-- (Tomte window setting), otherwise Home.
function ns.Panel_Open()
	local window = ns.db.window
	local resumeView, key = ns.PanelResume(ns.db.panel.last, GetServerTime(), (window and window.resume or 5) * 60,
		function(pageKey)
			local entry = ns.homeByKey[pageKey]
			return entry ~= nil and entry.kind == "page" and ns.HomeEntryVisible(entry)
		end)
	view, openEntry = resumeView, key and ns.homeByKey[key] or nil
	Show()
end

-- The module's settings. tab "page" (old callers) opens its first content page instead.
function ns.Panel_OpenModule(key, tab)
	local module = ns.modulesByKey[key]
	if tab == "page" and module then
		local entry = ns.ModulePages(module)[1]
		if entry then
			ns.Panel_OpenPage(entry.key)
			return
		end
	end
	ns.db.panel.selected = key
	view = "settings"
	Show()
end

-- A content page by its home entry key (falls back to Home when it isn't available).
function ns.Panel_OpenPage(key)
	local entry = ns.homeByKey[key]
	if entry and entry.kind == "page" and ns.HomeEntryVisible(entry) then
		view, openEntry = "page", entry
	else
		view, openEntry = "home", nil
	end
	Show()
end

-- World map tab entries: the module opens the map on its tab; the window steps aside.
function ns.Panel_OpenMap(entry)
	if panel then
		panel:Hide()
	end
	entry.open()
end

function ns.Panel_Hide()
	if panel then
		panel:Hide()
	end
end

-- Redraw what's shown (a Home section whose height changed, a page whose data changed).
function ns.Panel_Refresh()
	Refresh()
end

function ns.Panel_IsShown()
	return panel ~= nil and panel:IsShown()
end

function ns.Panel_Toggle()
	if panel and panel:IsShown() then
		panel:Hide()
	else
		ns.Panel_Open()
	end
end

-- Options > AddOns > Tomte: a short page with a button that opens the panel.
local function CreateSettingsStub()
	local holder = CreateFrame("Frame")
	holder:Hide()
	local title = UI.Text(holder, 19, "heading", "title")
	title:SetPoint("TOPLEFT", 16, -16)
	title:SetText("Tomte")
	local text = UI.Text(holder, 13, "text")
	text:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -12)
	text:SetPoint("RIGHT", -16, 0)
	text:SetWordWrap(true)
	text:SetText("Tomte's settings have their own window. Open it here, with /tomte, or from the minimap button.")
	local open = UI.Button(holder, 120, "Open Tomte")
	open:SetHeight(24)
	open:SetPoint("TOPLEFT", text, "BOTTOMLEFT", 0, -16)
	open:SetScript("OnClick", function()
		if SettingsPanel and SettingsPanel:IsShown() then
			HideUIPanel(SettingsPanel)
		end
		ns.Panel_Open()
	end)
	local category = Settings.RegisterCanvasLayoutCategory(holder, "Tomte")
	Settings.RegisterAddOnCategory(category)
end

-- Called on ADDON_LOADED. The panel itself is built the first time it is shown.
function ns.Panel_Init()
	CreateSettingsStub()
	-- Esc closes the panel: UISpecialFrames hides this dummy, which hides the panel.
	escape = CreateFrame("Frame", "TomtePanelEscape", UIParent)
	escape:Hide()
	table.insert(UISpecialFrames, "TomtePanelEscape")
	escape:SetScript("OnHide", function()
		if panel then
			panel:Hide()
		end
	end)
end

-- Addon compartment (minimap addons button); named in the TOC, so it has to be global.
function Tomte_OnAddonCompartmentClick()
	ns.Panel_Toggle()
end
