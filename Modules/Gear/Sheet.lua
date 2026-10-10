local addonName, ns = ...

-- Gear Check on the character sheet: a Gear button under the trinkets (where Pawn's was), with a red count when
-- worn items miss enchants or gems, and a panel docked to the right of the character frame: the stat weights in
-- use (with Import / Remove), the best gem, and every worn item that's missing something. Built when the
-- character frame's addon loads; the panel only shows on the Character tab (it's a child of PaperDollFrame).

local UI = ns.UI
local WIDTH = 300
local PAD = 14
local LINE_H = 18
local ITEM_H = 30
local SECTION_GAP = 14

local button, panel
local lines, items = {}, {}
local usedLines, usedItems = 0, 0
local requested = false

local function DB()
	return ns.gearDB
end

local function Wanted()
	return ns.gearModule.active and DB().sheetButton
end

-- Layout helpers -------------------------------------------------------------------------------------------------

-- role: theme color role of the text.
local function Line(y, text, role, size, indent)
	usedLines = usedLines + 1
	local fs = lines[usedLines]
	if not fs then
		fs = panel.content:CreateFontString(nil, "OVERLAY")
		fs:SetShadowOffset(1, -1)
		fs:SetJustifyH("LEFT")
		fs:SetWordWrap(true)
		lines[usedLines] = fs
	end
	UI.SetFont(fs, "body", size or 12)
	UI.SetTextRole(fs, role)
	fs:ClearAllPoints()
	fs:SetPoint("TOPLEFT", panel.content, "TOPLEFT", indent or 0, -y)
	fs:SetPoint("RIGHT", panel.content, "RIGHT")
	fs:SetText(text)
	fs:Show()
	return math.max(fs:GetStringHeight(), LINE_H - 4) + 4
end

local function Header(y, text)
	return Line(y, ns.Spaced(text), "textMuted", 10)
end

local function NewItemRow()
	local row = CreateFrame("Button", nil, panel.content)
	row:SetHeight(ITEM_H)
	row.hover = row:CreateTexture(nil, "BACKGROUND")
	row.hover:SetAllPoints()
	row.hover:SetColorTexture(1, 1, 1, 0.05)
	row.hover:Hide()
	row.icon = row:CreateTexture(nil, "ARTWORK")
	row.icon:SetSize(24, 24)
	row.icon:SetPoint("LEFT", 2, 0)
	row.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	row.name = UI.Text(row, 12, "text")
	row.name:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 8, 1)
	row.name:SetPoint("RIGHT", -4, 0)
	row.name:SetWordWrap(false)
	row.problem = UI.Text(row, 11, "danger")
	row.problem:SetPoint("BOTTOMLEFT", row.icon, "BOTTOMRIGHT", 8, -1)
	row.problem:SetPoint("RIGHT", -4, 0)
	row:SetScript("OnEnter", function(self)
		self.hover:Show()
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetInventoryItem("player", self.slot)
		GameTooltip:Show()
	end)
	row:SetScript("OnLeave", function(self)
		self.hover:Hide()
		GameTooltip:Hide()
	end)
	return row
end

local function ItemRow(y, entry)
	usedItems = usedItems + 1
	local row = items[usedItems] or NewItemRow()
	items[usedItems] = row
	row:ClearAllPoints()
	row:SetPoint("TOPLEFT", panel.content, "TOPLEFT", 0, -y)
	row:SetPoint("RIGHT", panel.content, "RIGHT")
	row.slot = entry.slot
	row.icon:SetTexture(GetInventoryItemTexture("player", entry.slot))
	local name, _, quality = C_Item.GetItemInfo(entry.link)
	local r, g, b = C_Item.GetItemQualityColor(quality or 1)
	row.name:SetText(name or entry.link)
	row.name:SetTextColor(r, g, b)
	row.problem:SetText(ns.Gear_AuditEntryText(entry))
	row:Show()
	return ITEM_H
end

-- Content ------------------------------------------------------------------------------------------------------

local function SortedWeights(weights)
	local list = {}
	for key, value in pairs(weights) do
		list[#list + 1] = { ns.GEAR_STAT_LABELS[key] or key, value }
	end
	table.sort(list, function(a, b)
		if a[2] ~= b[2] then
			return a[2] > b[2]
		end
		return a[1] < b[1]
	end)
	return list
end

local function SourceText(ctx)
	if ctx.source == "imported" then
		return ("Imported: %s"):format(ctx.label or "Raidbots")
	elseif ctx.source == "builtin" then
		return ("Built-in: %s%s"):format(ctx.label, ns.Gear_IsGuideLabel(ctx.label) and ": import a sim for better" or "")
	end
	return "None: item level decides. Import Raidbots weights for better verdicts."
end

-- Returns the y below the weights section, and places the Import / Remove buttons.
local function WeightsSection(y, ctx)
	y = y + Header(y, "Stat weights")
	if not ctx then
		y = y + Line(y, "No specialization yet.", "textMuted")
		panel.import:Hide()
		panel.remove:Hide()
		return y
	end
	y = y + Line(y, ctx.spec.name, "heading", 14)
	y = y + Line(y, SourceText(ctx), ctx.source == "none" and "danger" or "textMuted", 11)
	if ctx.source ~= "none" then
		for _, entry in ipairs(SortedWeights(ctx.weights)) do
			y = y + Line(y, ("%s  %s"):format(entry[1], UI.Wrap(("%.2f"):format(entry[2]), "text")), "textMuted", 12, 8)
		end
	end
	panel.import:ClearAllPoints()
	panel.import:SetPoint("TOPLEFT", panel.content, "TOPLEFT", 0, -(y + 4))
	panel.import:Show()
	panel.remove:SetShown(ctx.source == "imported")
	return y + 32
end

local function GemSection(y, ctx)
	y = y + Header(y, "Best gem")
	if ctx and ctx.best then
		y = y + Line(y, ctx.best.name, "text")
		y = y + Line(y, ns.Gear_StatLabel(ctx.best.stats), "textMuted", 11)
	else
		y = y + Line(y, "Not known yet (gem data loading).", "textFaint", 11)
	end
	return y
end

local function GearSection(y, list)
	y = y + Header(y, "Your gear")
	if not list then
		return y + Line(y, "Reading your gear...", "textFaint", 11)
	end
	if #list == 0 then
		return y + Line(y, "Everything is enchanted and socketed.", "success", 12)
	end
	for _, entry in ipairs(list) do
		y = y + ItemRow(y, entry)
	end
	return y
end

local function Problems(list)
	local n = 0
	for _, entry in ipairs(list or {}) do
		n = n + (entry.enchant and 1 or 0) + entry.empty
	end
	return n
end

local function Layout()
	local equipped = ns.GearItems_Equipped()
	local list = equipped and ns.Gear_AuditList(equipped)
	local count = Problems(list)
	button.badge:SetShown(count > 0)
	button.badgeText:SetShown(count > 0)
	button.badgeText:SetText(count)
	if not panel:IsVisible() then
		return
	end
	usedLines, usedItems = 0, 0
	local ctx = ns.Gear_Context()
	local y = WeightsSection(0, ctx)
	y = GemSection(y + SECTION_GAP, ctx)
	y = GearSection(y + SECTION_GAP, list)
	for i = usedLines + 1, #lines do
		lines[i]:Hide()
	end
	for i = usedItems + 1, #items do
		items[i]:Hide()
	end
	panel.scroll:SetContentHeight(y + 8)
end

-- Frames -------------------------------------------------------------------------------------------------------

local function SetOpen(open)
	DB().sheetOpen = open
	ns.GearSheet_Refresh()
end

local function BuildButton()
	button = UI.Button(PaperDollFrame, 48, "Gear")
	button:SetHeight(24)
	button:SetPoint("TOPRIGHT", CharacterTrinket1Slot, "BOTTOMRIGHT", -1, -8)
	button:HookScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText("Gear Check", UI.Color("heading"))
		GameTooltip:AddLine("Stat weights, best gem, and missing enchants and sockets.", 1, 1, 1, true)
		GameTooltip:Show()
	end)
	button:HookScript("OnLeave", function()
		GameTooltip:Hide()
	end)
	button:SetScript("OnClick", function()
		PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
		SetOpen(not DB().sheetOpen)
	end)
	-- Count of missing enchants and empty sockets.
	local badge = button:CreateTexture(nil, "OVERLAY")
	badge:SetSize(16, 16)
	badge:SetPoint("CENTER", button, "TOPRIGHT", -2, -2)
	badge:SetColorTexture(UI.Color("danger"))
	button.badge = badge
	button.badgeText = UI.Text(button, 10, "text", "number")
	button.badgeText:SetPoint("CENTER", badge, "CENTER", 0, 0)
	button.badgeText:SetJustifyH("CENTER")
end

local function BuildPanel()
	panel = CreateFrame("Frame", nil, PaperDollFrame)
	panel:SetWidth(WIDTH)
	panel:SetPoint("TOPLEFT", CharacterFrame, "TOPRIGHT", 2, 0)
	panel:SetPoint("BOTTOMLEFT", CharacterFrame, "BOTTOMRIGHT", 2, 0)
	panel:EnableMouse(true)
	UI.Panel(panel)

	local title = UI.Text(panel, 16, "heading", "title")
	title:SetPoint("TOPLEFT", PAD, -12)
	title:SetText("Gear Check")
	local close = UI.Button(panel, 20, "x")
	close:SetPoint("TOPRIGHT", -8, -10)
	close:SetScript("OnClick", function()
		SetOpen(false)
	end)
	local settings = UI.Button(panel, 20, "")
	settings:SetPoint("RIGHT", close, "LEFT", -6, 0)
	local gear = settings:CreateTexture(nil, "ARTWORK")
	gear:SetSize(14, 14)
	gear:SetPoint("CENTER")
	gear:SetTexture(UI.GEAR)
	gear:SetTexCoord(0, 0.5, 0, 0.5)
	gear:SetVertexColor(UI.Color("accent"))
	settings:HookScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:SetText("Gear Check settings", UI.Color("heading"))
		GameTooltip:Show()
	end)
	settings:HookScript("OnLeave", function()
		GameTooltip:Hide()
	end)
	settings:SetScript("OnClick", function()
		ns.Panel_OpenModule("gear")
	end)
	local line = UI.Hairline(panel, 200, 0.4)
	line:ClearAllPoints()
	line:SetPoint("TOPLEFT", PAD, -44)
	line:SetPoint("TOPRIGHT", -PAD, -44)

	local sim = UI.Button(panel, 150, "How to sim an item")
	sim:SetHeight(22)
	sim:SetPoint("BOTTOMLEFT", PAD, 12)
	sim:SetScript("OnClick", ns.Gear_PrintSimSteps)

	panel.scroll = UI.Scroll(panel)
	panel.scroll:SetPoint("TOPLEFT", PAD, -56)
	panel.scroll:SetPoint("BOTTOMRIGHT", -PAD, 44)
	panel.scroll.onWidthChanged = function()
		Layout()
	end
	panel.content = panel.scroll.content

	panel.import = UI.Button(panel.content, 70, "Import")
	panel.import:SetHeight(22)
	panel.import:SetScript("OnClick", ns.Gear_OpenImport)
	panel.remove = UI.Button(panel.content, 70, "Remove")
	panel.remove:SetHeight(22)
	panel.remove:SetPoint("LEFT", panel.import, "RIGHT", 6, 0)
	panel.remove:SetScript("OnClick", function()
		local dialog = StaticPopup_Show("TOMTE_CONFIRM", "Remove the imported stat weights for your current spec?")
		if dialog then
			dialog.data = ns.Gear_ClearWeights
		end
	end)

	panel:SetScript("OnShow", Layout)
	panel:SetScript("OnHide", function()
		GameTooltip:Hide()
	end)
end

-- Button and panel follow the module, the option and the open state; the panel's content is rebuilt.
function ns.GearSheet_Refresh()
	if not button then
		return
	end
	local wanted = Wanted()
	button:SetShown(wanted)
	panel:SetShown(wanted and DB().sheetOpen)
	if wanted then
		Layout()
	end
end

-- The character pane on its Character tab with the Gear Check panel open (Home's Item level). ToggleCharacter's
-- second argument only shows (it doesn't close a pane that's already on that tab). Not in combat, where showing a
-- UI panel from addon code can be blocked.
function ns.GearSheet_Open()
	if InCombatLockdown() then
		ns.Print("not in combat.")
		return
	end
	DB().sheetOpen = true
	ToggleCharacter("PaperDollFrame", true)
	ns.GearSheet_Refresh()
end

-- From the module's Start: build once the character frame exists.
function ns.GearSheet_Init()
	if requested then
		ns.GearSheet_Refresh()
		return
	end
	requested = true
	EventUtil.ContinueOnAddOnLoaded("Blizzard_UIPanels_Game", function()
		BuildButton()
		BuildPanel()
		PaperDollFrame:HookScript("OnShow", function()
			ns.GearSheet_Refresh()
		end)
		ns.GearSheet_Refresh()
	end)
end
