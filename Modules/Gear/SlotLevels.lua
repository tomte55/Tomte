local addonName, ns = ...

-- Item level in the top-left corner of each gear slot on the character sheet and the Inspect window, in the item's
-- quality color. Hooks Blizzard's slot update functions, which already run whenever a slot changes (and, on Inspect,
-- again on INSPECT_READY). The shirt and tabard are left out.

local UI = ns.UI
local SIZE = 12
local INSET = 2
local INSET_ONE = -1
local SLOTS = { "Head", "Neck", "Shoulder", "Back", "Chest", "Wrist", "Hands", "Waist", "Legs", "Feet", "Finger0",
	"Finger1", "Trinket0", "Trinket1", "MainHand", "SecondaryHand" }
local SKIP = { [INVSLOT_BODY] = true, [INVSLOT_TABARD] = true }

local requested = false

local function Wanted()
	return ns.gearModule.active and ns.gearDB.slotLevels
end

local function Label(button)
	local fs = button.tomteLevel
	if not fs then
		fs = button:CreateFontString(nil, "OVERLAY", nil, 7)
		fs:SetShadowOffset(1, -1)
		fs:SetShadowColor(0, 0, 0, 1)
		button.tomteLevel = fs
	end
	UI.SetFont(fs, "number", SIZE, "OUTLINE")
	return fs
end

local function Show(button, level, quality)
	if not level or level <= 1 then
		if button.tomteLevel then
			button.tomteLevel:Hide()
		end
		return
	end
	local fs = Label(button)
	local r, g, b = C_Item.GetItemQualityColor(quality or 1) -- 4th return is a hex string
	fs:SetTextColor(r, g, b)
	local text = tostring(level)
	-- Digits are equal width, so a leading 1 sits inset; pull it left to line up with the others.
	fs:SetPoint("TOPLEFT", text:sub(1, 1) == "1" and INSET_ONE or INSET, -2)
	fs:SetText(text)
	fs:Show()
end

local function UpdatePlayer(button)
	local slot = button:GetID()
	if not Wanted() or SKIP[slot] then
		return Show(button)
	end
	local location = ItemLocation:CreateFromEquipmentSlot(slot)
	if not C_Item.DoesItemExist(location) then
		return Show(button)
	end
	Show(button, C_Item.GetCurrentItemLevel(location), GetInventoryItemQuality("player", slot))
end

local function UpdateInspect(button)
	local unit = InspectFrame and InspectFrame.unit
	local slot = button:GetID()
	local link = unit and not SKIP[slot] and Wanted() and GetInventoryItemLink(unit, slot)
	button.tomteLink = link
	if not link then
		return Show(button)
	end
	local item = Item:CreateFromItemLink(link)
	if item:IsItemDataCached() then
		Show(button, C_Item.GetDetailedItemLevelInfo(link), GetInventoryItemQuality(unit, slot))
		return
	end
	-- Another player's item may not be cached yet; its level reads right once it is.
	Show(button)
	item:ContinueOnItemLoad(function()
		if button.tomteLink == link and InspectFrame.unit == unit then
			Show(button, C_Item.GetDetailedItemLevelInfo(link), GetInventoryItemQuality(unit, slot))
		end
	end)
end

local function Each(prefix, update)
	for _, name in ipairs(SLOTS) do
		local button = _G[prefix .. name .. "Slot"]
		if button then
			update(button)
		end
	end
end

-- After the option or the module changes.
function ns.GearSlotLevels_Refresh()
	if not requested then
		return
	end
	if CharacterHeadSlot then
		Each("Character", UpdatePlayer)
	end
	if InspectHeadSlot and InspectFrame:IsShown() then
		Each("Inspect", UpdateInspect)
	elseif InspectHeadSlot then
		Each("Inspect", Show)
	end
end

-- From the module's Start. Hooks can't be removed, so they check Wanted().
function ns.GearSlotLevels_Init()
	if requested then
		ns.GearSlotLevels_Refresh()
		return
	end
	requested = true
	EventUtil.ContinueOnAddOnLoaded("Blizzard_UIPanels_Game", function()
		hooksecurefunc("PaperDollItemSlotButton_Update", UpdatePlayer)
		Each("Character", UpdatePlayer)
	end)
	EventUtil.ContinueOnAddOnLoaded("Blizzard_InspectUI", function()
		hooksecurefunc("InspectPaperDollItemSlotButton_Update", UpdateInspect)
	end)
end
