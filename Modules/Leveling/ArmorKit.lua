local addonName, ns = ...

-- Leveling (World of Warcraft: Forever only): the armor kit button. While you carry a kit and worn gear it fits has nothing on
-- it, one press puts the best kit you can use on that piece. It never offers a piece with an enchant or kit, as a kit replaces
-- what's there. Also a line on the kit's tooltip. Out of combat only: the button is secure. Rules in Data.lua, reads in
-- Read.lua, the To do row in Data.lua's checklist.

local BUTTON_NAME = "TomteArmorKit"
local SIZE = 36
local LABEL_GAP = 3
local UPDATE_DELAY = 0.3 -- seconds: a purchase or a gear swap is a burst of events
local ICON = "Interface\\Icons\\INV_Misc_ArmorKit_17"
local DEFAULT_POINT = { point = "CENTER", relPoint = "CENTER", x = 120, y = -180 }

local UI = ns.UI

local db, button
local active = false
local updatePending = false
local tooltipHooked = false
local events = ns.NewEvents()
local OWNER = "armorKit"

local function ShowTooltip(self)
	GameTooltip:SetOwner(self, "ANCHOR_TOP")
	local plan = ns.LevelingRead_KitPlan()
	if plan then
		GameTooltip:SetText(plan.kit.name or "Armor kit")
		UI.TipLine(("Click to put it on %s."):format(plan.gear or plan.label), "text", true)
		UI.TipLine(ns.Leveling_KitTipLine(plan.empty), "textMuted", true)
	else
		GameTooltip:SetText("Armor kit")
	end
	UI.TipLine("Never goes on a piece that already has an enchant or kit. Out of combat only.", "textMuted", true)
	GameTooltip:Show()
end

-- The macro for this press: read at the click, so it's right whatever changed since the button was last drawn.
local function PreClick()
	if InCombatLockdown() then
		return
	end
	local plan = active and ns.LevelingRead_KitPlan()
	button:SetAttribute("macrotext", plan and ns.Leveling_KitMacro(plan.kit.itemID, plan.slot) or "")
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
	button.count = UI.Text(button, 11, "text", "number")
	button.count:SetPoint("BOTTOMRIGHT", -3, 3)
	button.label = UI.Text(button, 11, "text", "label")
	button.label:SetPoint("TOP", button, "BOTTOM", 0, -LABEL_GAP)
	button.label:SetWordWrap(false)
	button:SetScript("OnEnter", ShowTooltip)
	button:SetScript("OnLeave", GameTooltip_Hide)
	button:SetPoint(db.armorKitFrame.point, UIParent, db.armorKitFrame.relPoint, db.armorKitFrame.x, db.armorKitFrame.y)
	button:Hide()
end

-- Out of combat only: the button is protected.
local function Update()
	if InCombatLockdown() then
		return
	end
	if not (active and db.armorKit) then
		if button then
			button:Hide()
		end
		return
	end
	if not button then
		CreateButton()
	end
	if ns.EditMode_Active() then -- something to drag
		button.icon:SetTexture(ICON)
		button.count:SetText("")
		button.label:SetText("Armor kit")
		button:Show()
		return
	end
	local plan = ns.LevelingRead_KitPlan()
	if not plan then
		button:Hide()
		return
	end
	button.icon:SetTexture(C_Item.GetItemIconByID(plan.kit.itemID) or ICON)
	button.count:SetText(plan.kit.count)
	button.label:SetText(plan.gear or plan.label)
	button:Show()
	-- It moves on to the next piece with the mouse still on it: the tooltip follows.
	if GameTooltip:IsShown() and GameTooltip:GetOwner() == button then
		ShowTooltip(button)
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

-- Post-calls can't be removed: it does nothing while off.
local function OnItemTooltip(tooltip, data)
	local itemID = data and data.id
	if not (active and db.armorKit and tooltip == GameTooltip and type(itemID) == "number" and not ns.IsSecret(itemID)
		and ns.LevelingRead_IsKit(itemID)) then
		return
	end
	UI.TipLine(ns.Leveling_KitTipLine(ns.Leveling_EmptyGear(ns.LevelingRead_KitGear())), "textMuted")
end

local WATCHED = { "BAG_UPDATE_DELAYED", "PLAYER_EQUIPMENT_CHANGED", "PLAYER_ENTERING_WORLD", "PLAYER_LEVEL_UP",
	"PLAYER_REGEN_ENABLED", "GET_ITEM_INFO_RECEIVED" }
for _, event in ipairs(WATCHED) do
	events:On(OWNER, event, UpdateSoon)
end
events:On(OWNER, "UNIT_INVENTORY_CHANGED", UpdateSoon)

-- Fires just before the lockdown starts: the last moment a secure button can change.
events:On(OWNER, "PLAYER_REGEN_DISABLED", function()
	if button then
		button:SetAttribute("macrotext", "")
		button:Hide()
	end
end)

ns.EditMode_Register({
	name = "Armor kit button",
	frame = function()
		return button
	end,
	refresh = Update,
	saved = function()
		local point, _, relPoint, x, y = button:GetPoint()
		db.armorKitFrame.point, db.armorKitFrame.relPoint, db.armorKitFrame.x, db.armorKitFrame.y = point, relPoint, x, y
	end,
	module = "leveling",
	reset = function()
		db.armorKitFrame.point, db.armorKitFrame.relPoint = DEFAULT_POINT.point, DEFAULT_POINT.relPoint
		db.armorKitFrame.x, db.armorKitFrame.y = DEFAULT_POINT.x, DEFAULT_POINT.y
		if button and not InCombatLockdown() then
			button:ClearAllPoints()
			button:SetPoint(db.armorKitFrame.point, UIParent, db.armorKitFrame.relPoint, db.armorKitFrame.x, db.armorKitFrame.y)
		end
	end,
})

function ns.LevelingKit_Update()
	UpdateSoon()
end

-- For /tomte leveling why.
function ns.LevelingKit_Why()
	local plan = ns.LevelingRead_KitPlan()
	ns.Print(("Armor kits: a click puts on %s."):format(plan and (tostring(plan.kit.name) .. " on " .. plan.label) or "nothing"))
	for _, gear in ipairs(ns.LevelingRead_KitGear()) do
		print(("  %s: %s, enchant %s"):format(gear.label, tostring(gear.name), tostring(ns.Leveling_ItemEnchant(gear.link))))
	end
end

function ns.LevelingKit_Start(moduleDB)
	db = moduleDB
	active = true
	for _, event in ipairs(WATCHED) do
		events:Watch(OWNER, event)
	end
	events:Watch(OWNER, "PLAYER_REGEN_DISABLED")
	events:Watch(OWNER, "UNIT_INVENTORY_CHANGED", "player")
	if not tooltipHooked then
		tooltipHooked = true
		TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, ns.Perf_Wrap(OnItemTooltip, "tooltip"))
	end
	UpdateSoon()
end

function ns.LevelingKit_Stop()
	active = false
	events:UnwatchAll(OWNER)
	if InCombatLockdown() then
		events:Watch(OWNER, "PLAYER_REGEN_ENABLED") -- a secure button can't hide until the fight ends
	else
		Update()
	end
end
