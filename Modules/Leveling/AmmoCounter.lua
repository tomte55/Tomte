local addonName, ns = ...

-- Leveling (World of Warcraft: Forever only): the ammo counter. An icon with your full count, past the 999 the game's quiver
-- number stops at; its tooltip lists every ammo you carry, and a click equips the next one. Shows while you have a bow, gun
-- or crossbow. The low warning and the vendor's buy button are Leveling.lua's. Rules in Data.lua, bag reads in Read.lua.

local BUTTON_NAME = "TomteAmmoCounter"
local SIZE = 36
local LABEL_GAP = 3
local UPDATE_DELAY = 0.3 -- seconds: a bag sort or a purchase is a burst of events
local COMBAT_TICK = 1 -- seconds: Auto Shot has no event of its own, and a counter is most use mid-fight
local ICON = "Interface\\Icons\\INV_Ammo_Arrow_02"
local DEFAULT_POINT = { point = "CENTER", relPoint = "CENTER", x = -120, y = -180 }

local UI = ns.UI
local IsSecret = ns.IsSecret

local db, button, ticker
local active = false
local updatePending = false
local events = ns.NewEvents()
local OWNER = "ammoCounter"

-- The next ammo a click would equip, and everything carried.
local function Switch(weapon)
	local types = ns.Leveling_AmmoTypes(ns.LevelingRead_AmmoCarried(), weapon, UnitLevel("player"))
	return ns.Leveling_AmmoNext(types, ns.LevelingRead_AmmoSlot()), types
end

local function ShowTooltip(self)
	GameTooltip:SetOwner(self, "ANCHOR_TOP")
	GameTooltip:SetText("Ammo")
	local _, _, weapon = ns.LevelingRead_Ammo()
	local nextType, types = Switch(weapon)
	local equipped = ns.LevelingRead_AmmoSlot()
	for _, ammo in ipairs(types) do
		UI.TipLine(("%s: %s%s"):format(ammo.name or "?", ns.Thousands(ammo.count), ammo.itemID == equipped and " (equipped)" or
			(ammo.fits and "" or " (can't use)")), ammo.fits and "text" or "textMuted")
	end
	if #types == 0 then
		UI.TipLine("None in your bags.", "textMuted")
	end
	if nextType then
		UI.TipLine(("Click to equip %s. Out of combat only."):format(nextType.name or "the next one"), "textMuted", true)
	end
	GameTooltip:Show()
end

-- The macro for this press: read at the click, so it's right whatever changed since the button was last drawn.
local function PreClick()
	if InCombatLockdown() then
		return
	end
	local _, _, weapon = ns.LevelingRead_Ammo()
	local nextType = Switch(weapon)
	button:SetAttribute("macrotext", active and nextType and ns.Leveling_AmmoMacro(nextType.itemID) or "")
end

-- Out of combat only: protected frames can't be made in combat.
local function CreateButton()
	button = CreateFrame("Button", BUTTON_NAME, UIParent, "SecureActionButtonTemplate")
	button:SetSize(SIZE, SIZE)
	button:SetFrameStrata("MEDIUM")
	button:SetMovable(true)
	button:SetClampedToScreen(true)
	button:RegisterForClicks("LeftButtonDown")
	button:SetAttribute("useOnKeyDown", true)
	button:SetAttribute("type", "macro")
	button:SetAttribute("macrotext", "")
	button:SetScript("PreClick", PreClick)
	button.icon = button:CreateTexture(nil, "ARTWORK")
	button.icon:SetAllPoints()
	UI.ActionIcon(button, button.icon, SIZE)
	button.count = UI.Text(button, 13, "text", "number")
	button.count:SetPoint("TOP", button, "BOTTOM", 0, -LABEL_GAP)
	button.hint = UI.Text(button, 11, "textMuted", "label")
	button.hint:SetPoint("TOP", button.count, "BOTTOM", 0, -1)
	button:SetScript("OnEnter", ShowTooltip)
	button:SetScript("OnLeave", GameTooltip_Hide)
	button:SetPoint(db.ammoFrame.point, UIParent, db.ammoFrame.relPoint, db.ammoFrame.x, db.ammoFrame.y)
	button:Hide()
end

local function Draw(icon, count, role, hint)
	button.icon:SetTexture(icon)
	button.icon:SetDesaturated(count == 0)
	button.count:SetText(ns.Thousands(count))
	UI.SetTextRole(button.count, role)
	button.hint:SetText(hint or "")
end

-- In combat only the number and color change: the button can't be shown or hidden, and the bags aren't scanned.
local function Update()
	local locked = InCombatLockdown()
	if not (active and db.ammoCounter) then
		if button and not locked then
			button:Hide()
		end
		return
	end
	if not button then
		if locked then
			return
		end
		CreateButton()
	end
	if ns.EditMode_Active() then -- something to drag
		Draw(ICON, 1000, "text", "Ammo")
		if not locked then
			button:Show()
		end
		return
	end
	local needs, count, weapon = ns.LevelingRead_Ammo()
	if IsSecret(count) then
		return
	end
	local equipped = ns.LevelingRead_AmmoSlot()
	local nextType = not locked and Switch(weapon) or nil
	local view = ns.Leveling_AmmoView(needs, count, db.ammoLow, equipped and ns.LevelingRead_ItemFits(equipped, weapon),
		nextType ~= nil)
	if view then
		local _, icon = ns.LevelingRead_AmmoItem()
		Draw(icon or ICON, view.count, view.role, view.hint)
	end
	if not locked then
		button:SetShown(view ~= nil)
		-- A click equips while the mouse stays on the button, and the bags change under it: the tooltip follows.
		if view and GameTooltip:IsShown() and GameTooltip:GetOwner() == button then
			ShowTooltip(button)
		end
	end
end

local function UpdateSoon()
	if updatePending then
		return
	end
	updatePending = true
	C_Timer.After(UPDATE_DELAY, function()
		updatePending = false
		Update()
	end)
end

for _, event in ipairs({ "BAG_UPDATE", "BAG_UPDATE_DELAYED", "PLAYER_EQUIPMENT_CHANGED", "PLAYER_ENTERING_WORLD",
	"PLAYER_LEVEL_UP" }) do
	events:On(OWNER, event, UpdateSoon)
end
events:On(OWNER, "UNIT_INVENTORY_CHANGED", UpdateSoon)

-- Fires just before the lockdown starts: the last moment a secure button can change.
events:On(OWNER, "PLAYER_REGEN_DISABLED", function()
	if button then
		button:SetAttribute("macrotext", "")
	end
	if not ticker then
		ticker = C_Timer.NewTicker(COMBAT_TICK, Update)
	end
end)

events:On(OWNER, "PLAYER_REGEN_ENABLED", function()
	if ticker then
		ticker:Cancel()
		ticker = nil
	end
	if not active then -- turned off during the fight: the button can hide now
		events:UnwatchAll(OWNER)
	end
	Update()
end)

ns.EditMode_Register({
	name = "Ammo counter",
	frame = function()
		return button
	end,
	refresh = Update,
	saved = function()
		local point, _, relPoint, x, y = button:GetPoint()
		db.ammoFrame.point, db.ammoFrame.relPoint, db.ammoFrame.x, db.ammoFrame.y = point, relPoint, x, y
	end,
	module = "leveling",
	reset = function()
		db.ammoFrame.point, db.ammoFrame.relPoint = DEFAULT_POINT.point, DEFAULT_POINT.relPoint
		db.ammoFrame.x, db.ammoFrame.y = DEFAULT_POINT.x, DEFAULT_POINT.y
		if button and not InCombatLockdown() then
			button:ClearAllPoints()
			button:SetPoint(db.ammoFrame.point, UIParent, db.ammoFrame.relPoint, db.ammoFrame.x, db.ammoFrame.y)
		end
	end,
})

function ns.LevelingAmmo_Update()
	UpdateSoon()
end

-- For /tomte leveling why.
function ns.LevelingAmmo_Why()
	local _, count, weapon = ns.LevelingRead_Ammo()
	local nextType, types = Switch(weapon)
	ns.Print(("Ammo: slot holds item %s, count %s. A click equips %s."):format(tostring(ns.LevelingRead_AmmoSlot()),
		tostring(count), nextType and tostring(nextType.name) or "nothing"))
	for _, ammo in ipairs(types) do
		print(("  %s (item %d): %d, usable %s"):format(tostring(ammo.name), ammo.itemID, ammo.count, tostring(ammo.fits)))
	end
end

function ns.LevelingAmmo_Start(moduleDB)
	db = moduleDB
	active = true
	for _, event in ipairs({ "BAG_UPDATE", "BAG_UPDATE_DELAYED", "PLAYER_EQUIPMENT_CHANGED", "PLAYER_ENTERING_WORLD",
		"PLAYER_LEVEL_UP", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED" }) do
		events:Watch(OWNER, event)
	end
	events:Watch(OWNER, "UNIT_INVENTORY_CHANGED", "player")
	UpdateSoon()
end

function ns.LevelingAmmo_Stop()
	active = false
	if ticker then
		ticker:Cancel()
		ticker = nil
	end
	events:UnwatchAll(OWNER)
	if InCombatLockdown() then
		events:Watch(OWNER, "PLAYER_REGEN_ENABLED") -- a secure button can't hide until the fight ends
	else
		Update()
	end
end
