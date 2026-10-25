local addonName, ns = ...

-- Settings page for the selected module: a header (icon, name, summary with "More" for the full description,
-- addon chips, the on/off switch and "Open <page>" buttons), a warning strip while it's blocked, then its options as
-- cards (Options.lua). Built and refreshed by Panel.lua (ns.PanelModulePage_Create, ns.PanelModulePage_Refresh).

local UI = ns.UI
local PAD = 24 -- page text inset; content frames sit 8 px further out
ns.PANEL_PAD = PAD
local ICON = 40
local CHIP_H = 18
local SCROLL_BAR = 10 -- room right of the options scroll for its thumb
local ROW_INSET = 14 -- a card row's control sits this far in from the card edge (Options.lua)
local CHIP_PAD = 8 -- text inset on each side of a chip

local page
local expanded = false -- the full description is showing (reset when another module is selected)
local shownFor -- module the header was last filled for

local function Selected()
	return ns.Panel_Selected()
end

local function Refresh()
	ns.Panel_Refresh()
end

local function IsLoaded(addon)
	return C_AddOns.IsAddOnLoaded(addon) and true or false
end

-- Header pieces -------------------------------------------------------------------------------------------------

local function CreateSwitch(parent)
	local toggle = CreateFrame("Button", nil, parent)
	toggle:SetHeight(20)
	toggle.switch = UI.Switch(toggle)
	toggle.switch:SetPoint("RIGHT")
	toggle.label = UI.Text(toggle, 13, "text")
	toggle.label:SetPoint("RIGHT", toggle.switch, "LEFT", -8, 0)
	toggle:SetWidth(70)
	toggle:SetScript("OnClick", function(self)
		if self.switch:IsEnabled() then
			self.switch:Click() -- the label toggles it too
		end
	end)
	toggle.switch.onChange = function(checked)
		local key = Selected().key
		ns.SetModuleEnabled(key, checked)
		Refresh()
		if checked then
			ns.PanelSidebar_Flash(key) -- its row in the list lights up too
		end
	end
	return toggle
end

local function Chip(i)
	local chip = page.chips[i]
	if chip then
		return chip
	end
	chip = CreateFrame("Frame", nil, page)
	chip:SetHeight(CHIP_H)
	chip.text = UI.Text(chip, 11, "success")
	chip.text:SetPoint("LEFT", CHIP_PAD, 0)
	chip.dot = chip:CreateTexture(nil, "ARTWORK")
	chip.dot:SetSize(4, 4)
	chip.dot:SetPoint("RIGHT", chip.text, "LEFT", -5, 0)
	chip.text:SetPoint("LEFT", CHIP_PAD + 9, 0)
	UI.Border(chip, "success", 0.5)
	chip:EnableMouse(true)
	chip:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_BOTTOMRIGHT")
		GameTooltip:SetText(self.line.text, 1, 1, 1, 1, true)
		GameTooltip:Show()
	end)
	chip:SetScript("OnLeave", GameTooltip_Hide)
	page.chips[i] = chip
	return chip
end

-- Addons the module uses as chips (green when loaded, faint when not; the tooltip says what for), and a red chip
-- for a conflicting addon that is loaded (amber for a loaded addon the module does the job of). Chips that would run past maxW (into the "Open" buttons) are left out.
local function LayoutChips(module, anchor, maxW)
	local shown = 0
	local used = anchor == page.more and page.more:GetWidth() or 0
	for _, line in ipairs(ns.ModuleDependencies(module, IsLoaded)) do
		if not ((line.conflict or line.overlap) and line.ok) then
			local chip = Chip(shown + 1)
			chip.text:SetText(line.conflict and ("Conflicts with " .. line.addon)
				or line.overlap and ("Also running " .. line.addon) or line.addon)
			local w = math.ceil(chip.text:GetStringWidth()) + 2 * CHIP_PAD + 9
			local gap = shown == 0 and (anchor == page.more and 12 or 0) or 6
			if used + gap + w > maxW then
				break
			end
			shown = shown + 1
			used = used + gap + w
			chip.line = line
			local role = line.conflict and "danger" or line.overlap and "warning" or (line.ok and "success" or "textFaint")
			UI.SetTextRole(chip.text, role)
			chip.dot:SetColorTexture(UI.Color(role))
			UI.SetBorderColor(chip, role, 0.5)
			chip:SetWidth(w)
			chip:ClearAllPoints()
			chip:SetPoint("LEFT", anchor, "RIGHT", gap, 0)
			chip:Show()
			anchor = chip
		end
	end
	for i = shown + 1, #page.chips do
		page.chips[i]:Hide()
	end
	return shown
end

local function OpenButton(i)
	local b = page.openButtons[i]
	if not b then
		b = UI.Button(page, 80, "")
		b:SetHeight(22)
		b:SetScript("OnClick", function(self)
			ns.Panel_OpenPage(self.entry.key)
		end)
		page.openButtons[i] = b
	end
	return b
end

-- Page ------------------------------------------------------------------------------------------------------------

function ns.PanelModulePage_Create(parent)
	page = CreateFrame("Frame", nil, parent)
	page.icon = page:CreateTexture(nil, "ARTWORK")
	page.icon:SetSize(ICON, ICON)
	page.icon:SetPoint("TOPLEFT", PAD, -18)
	page.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	page.iconRing = CreateFrame("Frame", nil, page)
	page.iconRing:SetAllPoints(page.icon)
	UI.Border(page.iconRing, "accent", 0.7)

	page.toggle = CreateSwitch(page)
	page.toggle:SetPoint("TOPRIGHT", -PAD, -18)
	page.actions = CreateFrame("Frame", nil, page) -- the "Open" buttons, right-aligned under the switch
	page.actions:SetPoint("TOPRIGHT", page.toggle, "BOTTOMRIGHT", 0, -8)
	page.actions:SetSize(1, 22)

	page.title = UI.Text(page, 21, "heading", "title")
	page.title:SetPoint("TOPLEFT", page.icon, "TOPRIGHT", 14, 1)
	page.title:SetWordWrap(false)
	page.summary = UI.Text(page, 13, "textMuted")
	page.summary:SetPoint("TOPLEFT", page.title, "BOTTOMLEFT", 0, -6)
	page.summary:SetWordWrap(true)
	page.desc = UI.Text(page, 12, "textMuted")
	page.desc:SetPoint("TOPLEFT", page.summary, "BOTTOMLEFT", 0, -6)
	page.desc:SetWordWrap(true)

	page.more = CreateFrame("Button", nil, page)
	page.more:SetHeight(CHIP_H)
	page.more.text = UI.Text(page.more, 12, "accent")
	page.more.text:SetPoint("LEFT")
	page.more:SetScript("OnClick", function()
		expanded = not expanded
		UI.Sound("pick")
		ns.PanelModulePage_Refresh()
	end)
	page.more:SetScript("OnEnter", function(self)
		UI.SetTextRole(self.text, "heading")
	end)
	page.more:SetScript("OnLeave", function(self)
		UI.SetTextRole(self.text, "accent")
	end)
	page.chipAnchor = CreateFrame("Frame", nil, page) -- where the chips start when there's no "More"
	page.chipAnchor:SetSize(1, CHIP_H)
	page.chips = {}
	page.openButtons = {}

	-- Warning strip while the module is blocked.
	page.blocked = CreateFrame("Frame", nil, page)
	UI.Surface(page.blocked, 0.6)
	UI.SetBorderColor(page.blocked, "danger", 0.6)
	page.blocked.text = UI.Text(page.blocked, 12, "danger")
	page.blocked.text:SetPoint("TOPLEFT", 12, -8)
	page.blocked.text:SetPoint("RIGHT", -12, 0)
	page.blocked.text:SetWordWrap(true)

	page.options = UI.Scroll(page)
	page.none = UI.Text(page, 12, "textMuted")
	page.none:SetText("Nothing to set here. It does its job on its own.")
	-- Once the settings view has closed, its next refresh is an arrival (UI.EnterUp), not a redraw. Set on hide rather
	-- than on show: the window's OnShow refreshes, and may run before this page's OnShow.
	page.arriving = true
	page:SetScript("OnHide", function()
		page.arriving = true
	end)
	page:SetScript("OnSizeChanged", function()
		if page:IsVisible() then
			-- Text widths and the blocked strip's height follow the page width; the cards re-lay themselves
			-- (the options scroll's onWidthChanged), so they aren't rebuilt on every frame of a resize.
			ns.PanelModulePage_Refresh(true)
		end
	end)
	return page
end

-- headerOnly: the window is being resized; the options keep their rows.
function ns.PanelModulePage_Refresh(headerOnly)
	local module = Selected()
	if not module then
		return
	end
	-- Another module picked or the settings view opened: the page rises in. A redraw after a setting changed doesn't.
	local arriving = not headerOnly and (shownFor ~= module or page.arriving)
	if not headerOnly then
		page.arriving = false
	end
	if shownFor ~= module then
		expanded = false
		shownFor = module
	end
	local reason = ns.ModuleBlockedReason(module)
	local open = reason == nil
	local group = ns.PanelLayout_Group(module.category)
	page.icon:SetTexture(module.icon or (group and group.icon) or ns.ICON)
	page.icon:SetDesaturated(not open)
	page.title:SetText(module.name)

	-- Switch, then the "Open" buttons under it, lined up with the right edge of the option cards (capped in width,
	-- Options.lua) rather than the window's; the text column ends left of the wider of the two.
	local optionsW = page:GetWidth() - 2 * (PAD - 8) - SCROLL_BAR
	local showOptions = open and module.options ~= nil and #module.options > 0
	local right = (PAD - 8) + (showOptions and ns.PanelOptions_Width(module, optionsW) or optionsW) - ROW_INSET
	page.toggle:SetShown(not module.alwaysOn)
	page.toggle:ClearAllPoints()
	page.toggle:SetPoint("TOPRIGHT", page, "TOPLEFT", right, -18)
	page.actions:ClearAllPoints()
	if module.alwaysOn then
		page.actions:SetPoint("TOPRIGHT", page, "TOPLEFT", right, -18)
	else
		page.actions:SetPoint("TOPRIGHT", page.toggle, "BOTTOMRIGHT", 0, -8)
	end
	page.toggle.switch:SetChecked(ns.ModuleEnabled(module))
	page.toggle.switch:SetEnabled(open)
	page.toggle.label:SetText(ns.ModuleEnabled(module) and "On" or "Off")
	UI.SetTextRole(page.toggle.label, open and "text" or "textFaint")
	local shownButtons, x = 0, 0
	for _, entry in ipairs(open and ns.ModulePages(module) or {}) do
		if ns.HomeEntryVisible(entry) then
			shownButtons = shownButtons + 1
			local b = OpenButton(shownButtons)
			b.entry = entry
			b.label:SetText("Open " .. entry.name .. " >")
			b:SetWidth(b.label:GetStringWidth() + 24)
			b:ClearAllPoints()
			b:SetPoint("TOPRIGHT", page.actions, "TOPRIGHT", -x, 0)
			b:Show()
			x = x + b:GetWidth() + 8
		end
	end
	for i = shownButtons + 1, #page.openButtons do
		page.openButtons[i]:Hide()
	end
	local actionsW = math.max(module.alwaysOn and 0 or page.toggle:GetWidth(), x)
	local textW = math.max(right - actionsW - 24 - (PAD + ICON + 14), 120)
	page.title:SetWidth(textW)
	page.summary:SetWidth(textW)
	page.desc:SetWidth(textW)

	-- Summary, "More" for the full description, then the chips on one line.
	local summary = module.summary or module.description or ""
	local hasMore = module.summary ~= nil and module.description ~= nil and module.description ~= module.summary
	page.summary:SetText(summary)
	page.desc:SetText(expanded and hasMore and module.description or "")
	page.desc:SetShown(expanded and hasMore)
	local below = (expanded and hasMore) and page.desc or page.summary
	page.more:SetShown(hasMore)
	page.more.text:SetText(expanded and "Less" or "More")
	page.more:SetWidth(page.more.text:GetStringWidth())
	page.more:ClearAllPoints()
	page.more:SetPoint("TOPLEFT", below, "BOTTOMLEFT", 0, -8)
	page.chipAnchor:ClearAllPoints()
	page.chipAnchor:SetPoint("TOPRIGHT", below, "BOTTOMLEFT", 0, -8)
	local chips = LayoutChips(module, hasMore and page.more or page.chipAnchor, textW)
	local top = (hasMore or chips > 0) and (hasMore and page.more or page.chipAnchor) or below

	-- The header ends under the text or the icon, whichever is lower: a spacer under each, take the lower one.
	local textBottom = top:GetBottom()
	local iconBottom = page.icon:GetBottom()
	local headerAnchor = top
	if textBottom and iconBottom and iconBottom < textBottom then
		headerAnchor = page.icon
	end
	if shownButtons > 0 then
		local buttonsBottom = page.actions:GetBottom()
		local anchorBottom = headerAnchor:GetBottom()
		if buttonsBottom and anchorBottom and buttonsBottom < anchorBottom then
			headerAnchor = page.actions
		end
	end
	local function Below(frame, gap)
		frame:ClearAllPoints()
		frame:SetPoint("TOP", headerAnchor, "BOTTOM", 0, -gap)
		frame:SetPoint("LEFT", page, "LEFT", PAD, 0)
		frame:SetPoint("RIGHT", page, "RIGHT", -PAD, 0)
	end

	-- Nothing below the header while blocked (its data may be getting replaced).
	page.blocked:SetShown(not open)
	if not open then
		Below(page.blocked, 14)
		page.blocked.text:SetText(reason)
		page.blocked:SetHeight(page.blocked.text:GetStringHeight() + 16)
		headerAnchor = page.blocked
	end

	page.options:SetShown(showOptions)
	if showOptions then
		page.options:ClearAllPoints()
		page.options:SetPoint("TOP", headerAnchor, "BOTTOM", 0, -16)
		page.options:SetPoint("LEFT", page, "LEFT", PAD - 8, 0)
		page.options:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", -(PAD - 8) - SCROLL_BAR, 14)
		if not headerOnly then
			ns.PanelOptions_Build(page.options, module, arriving)
		end
	else
		ns.PanelOptions_Release()
	end
	page.none:SetShown(open and not showOptions and shownButtons == 0)
	page.none:ClearAllPoints()
	page.none:SetPoint("TOPLEFT", headerAnchor, "BOTTOMLEFT", 0, -16)

	-- The header rises in as one block (its pieces sit on the page itself, so each gets the same UI.EnterUp); the
	-- cards follow one after another (Options.lua).
	if arriving then
		local header = { page.icon, page.iconRing, page.title, page.summary, page.desc, page.more, page.toggle,
			page.blocked, page.none }
		for _, list in ipairs({ page.chips, page.openButtons }) do
			for _, frame in ipairs(list) do
				header[#header + 1] = frame
			end
		end
		for _, region in ipairs(header) do
			if region:IsShown() then
				UI.EnterUp(region)
			end
		end
	end
end
