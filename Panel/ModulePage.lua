local addonName, ns = ...

-- Settings page for the selected module: header, dependency lines, "Open <page>" buttons and its options
-- (Options.lua). Built and refreshed by Panel.lua (ns.PanelModulePage_Create, ns.PanelModulePage_Refresh).

local UI = ns.UI
local OPTIONS_MAX_W = 560
local PAD = 24 -- page text inset; content frames sit 8 px further out
ns.PANEL_PAD = PAD

local page

local function Selected()
	return ns.Panel_Selected()
end

local function Refresh()
	ns.Panel_Refresh()
end

-- The options column is capped so a slider doesn't end up far from its label on a wide panel.
local function UpdateOptionsWidth()
	page.options:SetWidth(math.min(page:GetWidth() - 2 * (PAD - 8) - 10, OPTIONS_MAX_W))
end

local function IsLoaded(addon)
	return C_AddOns.IsAddOnLoaded(addon) and true or false
end

function ns.PanelModulePage_Create(parent)
	page = CreateFrame("Frame", nil, parent)
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

function ns.PanelModulePage_Refresh()
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
