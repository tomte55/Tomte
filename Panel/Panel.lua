local addonName, ns = ...

-- The Tomte window: standalone and resizable (/tomte, the addon compartment, the minimap button; Esc closes it).
-- Size and position are saved. Opening it goes back to the last view if it was closed a little while ago, else Home
-- (ns.Panel_Open). Three views:
--   home     the character, module sections and "Around you" (Home*.lua), with the rail on the left.
--   page     a content page (module.home entry of kind "page") with the rail (Rail.lua) on the left.
--   settings left: the module list (Sidebar.lua). Right: the selected module's page (ModulePage.lua).
-- Options > AddOns only has a button that opens it. Built on first use.

local UI = ns.UI
local DEFAULT_W, DEFAULT_H = 1040, 680 -- room for two columns of option cards (ModulePage.lua)
local MIN_W, MIN_H = 820, 560
local TITLE_H = 36
local PAD = ns.PANEL_PAD

local panel
local view, openEntry = "home", nil -- this session; openEntry is the page shown in the page view
local Refresh -- forward declaration

-- The saved selection, or the first module when there is none (or it no longer exists).
local function Selected()
	local key = ns.db.panel.selected
	return key and ns.modulesByKey[key] or ns.modules[1]
end
ns.Panel_Selected = Selected

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

local function IsLoaded(addon)
	return C_AddOns.IsAddOnLoaded(addon) and true or false
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
		ns.PanelSidebar_Refresh()
		ns.PanelModulePage_Refresh()
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
	diamond:SetShown(ns.Theme.HasOrnaments())
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
	local sidebar = ns.PanelSidebar_Create(settings)
	sidebar:SetPoint("TOPLEFT")
	sidebar:SetPoint("BOTTOMLEFT")
	local page = ns.PanelModulePage_Create(settings)
	page:SetPoint("TOPLEFT", sidebar, "TOPRIGHT")
	page:SetPoint("BOTTOMRIGHT")
	local divider = UI.VLine(settings)
	divider:SetPoint("TOP", sidebar, "TOPRIGHT", 0, -12)
	divider:SetPoint("BOTTOM", sidebar, "BOTTOMRIGHT", 0, 12)
	UI.ResizeGrip(panel, SaveLayout)

	panel:SetScript("OnShow", function()
		Refresh()
	end)
	panel:SetScript("OnHide", function()
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
	UI.CloseOnEscape(panel) -- after the SetScripts above: they would drop its hooks
end

-- Background opacity from the "Tomte window" settings (Panel/Window.lua), for themes that offer it (Theme.art.opacity).
function ns.Panel_ApplyLook()
	if panel then
		local window = ns.db.window
		local opacity = ns.Theme.art.opacity and window and window.opacity or 0.96
		panel.look:SetAlpha(opacity)
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

-- World map tab entries: Home's buttons open the map first (ns.MapTabs_Opener); with the map open the module shows its
-- tab and the window steps aside, otherwise (in combat) the module says why (ns.MapTabs_Open) and the window stays.
function ns.Panel_OpenMap(entry)
	if entry.open() and panel then
		panel:Hide()
	end
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
end

-- Addon compartment (minimap addons button); named in the TOC, so it has to be global.
function Tomte_OnAddonCompartmentClick()
	ns.Panel_Toggle()
end
