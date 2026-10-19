local addonName, ns = ...

-- Minimap Buttons module: round buttons on the minimap's edge, one per module that offers one and that the user ticked.
-- Tomte's own opens the panel (right-click: the Weekly board's popup). Each is dragged around the edge on its own.
-- A module offers a button with module.minimapButton = { name, icon, onClick(mouseButton), tooltip(GameTooltip),
-- shownByDefault }; it shows while the module is active.
-- Looks like LibDBIcon's retail buttons (same Blizzard textures and sizes), without the library.
-- Positioning maths is in Data.lua.

local DEFAULT_ANGLE = 225
local STEP = -26 -- degrees between buttons placed or reset by Tomte (up the left edge); about one button apart
local RADIUS = 5 -- how far outside the minimap's edge the button sits (LibDBIcon's default)

local UI = ns.UI
local module
local buttons = {} -- [module key] = button frame
local dragging -- the button being dragged

local function Saved(key)
	return module.db.buttons[key]
end

local function Place(button)
	-- GetMinimapShape isn't Blizzard's: minimap skin addons define it (the LibDBIcon convention). Without one it's round.
	local shape = GetMinimapShape and GetMinimapShape() or "ROUND"
	local x, y = ns.Minimap_Offset(Saved(button.key).angle, Minimap:GetWidth() / 2 + RADIUS,
		Minimap:GetHeight() / 2 + RADIUS, shape)
	button:ClearAllPoints()
	button:SetPoint("CENTER", Minimap, "CENTER", x, y)
end

local function FollowCursor(button)
	local mx, my = Minimap:GetCenter()
	local px, py = GetCursorPosition()
	local scale = Minimap:GetEffectiveScale()
	Saved(button.key).angle = ns.Minimap_Angle(px / scale - mx, py / scale - my)
	Place(button)
end

local function ShowTooltip(button)
	if dragging then
		return
	end
	GameTooltip:SetOwner(button, "ANCHOR_LEFT")
	GameTooltip:SetText(button.spec.name, UI.Color("heading"))
	if button.spec.tooltip then
		button.spec.tooltip(GameTooltip)
	end
	GameTooltip:AddLine("Drag to move", UI.RGB("textMuted"))
	GameTooltip:Show()
end

local function Create(owner)
	local spec = owner.minimapButton
	local button = CreateFrame("Button", nil, Minimap)
	button.key, button.spec = owner.key, spec
	button:SetSize(31, 31)
	button:SetFrameStrata("MEDIUM")
	button:SetFixedFrameStrata(true)
	button:SetFrameLevel(8)
	button:SetFixedFrameLevel(true)
	button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	button:RegisterForDrag("LeftButton")
	button:SetHighlightTexture(136477) -- Interface\Minimap\UI-Minimap-ZoomButton-Highlight

	local background = button:CreateTexture(nil, "BACKGROUND")
	background:SetTexture(136467) -- Interface\Minimap\UI-Minimap-Background
	background:SetSize(24, 24)
	background:SetPoint("CENTER")
	local icon = button:CreateTexture(nil, "ARTWORK")
	icon:SetTexture(spec.icon)
	icon:SetSize(18, 18)
	icon:SetPoint("CENTER")
	UI.CircleMask(icon, button)
	local border = button:CreateTexture(nil, "OVERLAY")
	border:SetTexture(136430) -- Interface\Minimap\MiniMap-TrackingBorder
	border:SetSize(50, 50)
	border:SetPoint("TOPLEFT")

	button:SetScript("OnClick", function(_, mouseButton)
		spec.onClick(mouseButton)
	end)
	button:SetScript("OnEnter", ShowTooltip)
	button:SetScript("OnLeave", function()
		GameTooltip:Hide()
	end)
	button:SetScript("OnDragStart", function(self)
		dragging = self
		GameTooltip:Hide()
		self:LockHighlight()
		self:SetScript("OnUpdate", FollowCursor)
	end)
	button:SetScript("OnDragStop", function(self)
		dragging = nil
		self:SetScript("OnUpdate", nil)
		self:UnlockHighlight()
	end)
	buttons[owner.key] = button
	return button
end

-- Modules offering a button, in registration (TOC) order.
local function Owners()
	local list = {}
	for _, owner in ipairs(ns.modules) do
		if owner.minimapButton then
			list[#list + 1] = owner
		end
	end
	return list
end

local function Wanted(owner)
	return module.active and owner.active and Saved(owner.key).shown
end

-- Angles of the buttons on the minimap now, but the one for skip.
local function TakenAngles(skip)
	local taken = {}
	for key, button in pairs(buttons) do
		if key ~= skip and button:IsShown() then
			taken[#taken + 1] = Saved(key).angle
		end
	end
	return taken
end

-- A small dot on Tomte's button (Recent: something you haven't seen).
local dotWanted = false
local function ApplyDot()
	local button = buttons.minimap
	if not button then
		return
	end
	if not button.dot then
		button.dot = button:CreateTexture(nil, "OVERLAY", nil, 2)
		button.dot:SetSize(10, 10)
		button.dot:SetPoint("TOPRIGHT", -4, -4)
		button.dot:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask")
		button.dot:SetVertexColor(UI.Color("accent"))
	end
	button.dot:SetShown(dotWanted)
end

function ns.Minimap_SetDot(shown)
	dotWanted = shown and true or false
	ApplyDot()
end

-- Shows and hides every button to match its module and the user's ticks. A button shown for the first time gets a
-- free spot on the edge.
local function Refresh()
	for _, owner in ipairs(Owners()) do
		local button = buttons[owner.key]
		if Wanted(owner) then
			local saved = Saved(owner.key)
			if not saved.angle then
				saved.angle = ns.Minimap_FreeAngle(TakenAngles(owner.key), DEFAULT_ANGLE, STEP, math.abs(STEP))
			end
			button = button or Create(owner)
			Place(button)
			button:Show()
		elseif button then
			if dragging == button then
				button:GetScript("OnDragStop")(button)
			end
			button:Hide()
		end
	end
	ApplyDot()
end

local function ResetPositions()
	local shown = {}
	for _, owner in ipairs(Owners()) do
		if Wanted(owner) then
			shown[#shown + 1] = owner.key
		end
	end
	local angles = ns.Minimap_Spread(#shown, DEFAULT_ANGLE, STEP)
	for i, key in ipairs(shown) do
		Saved(key).angle = angles[i]
		Place(buttons[key])
	end
end

local function TomteTooltip(tooltip)
	local r, g, b = UI.RGB("text")
	tooltip:AddLine("Click to open Tomte", UI.RGB("accent"))
	if ns.Weekly_Active and ns.Weekly_Active() then
		tooltip:AddLine("Right-click for this week's open items", UI.RGB("accent"))
	end
	local nextUp = ns.NextUp_TooltipLines and ns.NextUp_TooltipLines()
	if nextUp and #nextUp > 0 then
		tooltip:AddLine(" ")
		tooltip:AddLine("Next up", UI.RGB("heading"))
		for _, line in ipairs(nextUp) do
			tooltip:AddLine(line, r, g, b, true)
		end
		tooltip:AddLine(" ")
	end
end

module = ns.RegisterModule({
	key = "minimap",
	name = "Minimap Buttons",
	category = "tomte",
	icon = 237387, -- inv_misc_map08
	summary = "Pick which buttons sit on the minimap's edge.",
	description = "Buttons on the minimap's edge: Tomte's opens this window, and some modules offer their own. "
		.. "Tick the ones you want below. Drag a button to move it around the minimap.",
	enabledByDefault = true,
	minimapButton = {
		name = "Tomte",
		icon = ns.ICON,
		shownByDefault = true,
		onClick = function(mouseButton)
			if mouseButton == "RightButton" then
				if ns.Weekly_TogglePopup then -- Weekly board (it ignores the click while turned off)
					ns.Weekly_TogglePopup()
				end
			else
				ns.Panel_Toggle()
			end
		end,
		tooltip = TomteTooltip,
	},
	defaults = {
		buttons = {}, -- [module key] = { shown = bool, angle = degrees or nil until first shown }
	},
	init = function(saved)
		local options = { { type = "header", label = "Buttons" } }
		for _, owner in ipairs(Owners()) do
			local entry = saved.buttons[owner.key]
			if type(entry) ~= "table" then
				entry = { shown = owner.minimapButton.shownByDefault == true }
				saved.buttons[owner.key] = entry
			end
			options[#options + 1] = { type = "checkbox", key = "buttons." .. owner.key .. ".shown",
				label = owner.minimapButton.name, onChange = Refresh,
				tooltip = owner ~= module and ("Shows while the %s module is on."):format(owner.name) or nil }
		end
		options[#options + 1] = { type = "button", label = "Positions", text = "Reset", onClick = ResetPositions,
			tooltip = "Line the buttons up from the bottom left of the minimap." }
		module.options = options
	end,
	toggle = Refresh,
})

-- Buttons follow their module on and off.
ns.moduleToggled[#ns.moduleToggled + 1] = function(owner)
	if owner ~= module and owner.minimapButton then
		Refresh()
	end
end

-- Edit Mode can resize the minimap.
Minimap:HookScript("OnSizeChanged", function()
	for _, button in pairs(buttons) do
		if button:IsShown() then
			Place(button)
		end
	end
end)
