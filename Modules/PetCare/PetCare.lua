local addonName, ns = ...

-- Pet care (World of Warcraft: Forever only; tools/forever_list.lua): a one-click feed button for Hunters when the pet isn't
-- happy, with food it eats from your bags. Happiness, diets and training points don't exist on retail. The button is secure
-- and only changes out of combat: feeding is a protected cast. Rules in Data.lua. See
-- docs/superpowers/specs/2026-11-05-tomte-forever-leveling.md.

local FEED_PET = 6991 -- Blizzard's FEED_PET_SPELL_ID (Blizzard_FrameXMLUtil/ItemUtil.lua)
local ICON = 132161 -- ability_hunter_beastcall, as Hunter Pets
local BAGS = { 0, 1, 2, 3, 4 }
local SIZE = 44
local BUTTON_NAME = "TomtePetFeed"
local UPDATE_DELAY = 0.3 -- seconds: bursts of bag and pet events
local TOAST_HOLD = 10

local UI = ns.UI

local module, db, button
local food -- what the button feeds now
local toldNoFood = false
local events = CreateFrame("Frame")

local function IsHunter()
	local _, class = UnitClass("player")
	return class == "HUNTER"
end

local function PetOut()
	return UnitExists("pet") and not UnitIsDead("pet")
end

local function Foods()
	local list = {}
	for _, bag in ipairs(BAGS) do
		for slot = 1, C_Container.GetContainerNumSlots(bag) or 0 do
			local info = C_Container.GetContainerItemInfo(bag, slot)
			if info and info.itemID and C_PetInfo.CanPetEatItem(info.itemID) then
				list[#list + 1] = { bag = bag, slot = slot, itemID = info.itemID, icon = info.iconFileID,
					count = info.stackCount, ilvl = C_Item.GetDetailedItemLevelInfo(info.itemID) }
			end
		end
	end
	return list
end

local function ShowTooltip(self)
	GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
	local happiness, damage = C_PetInfo.GetPetHappiness()
	GameTooltip:SetText("Feed your pet")
	UI.TipLine(("%s, doing %d%% damage"):format(ns.PetCare_Mood(happiness) or "?", damage or 0), "text")
	if food then
		UI.TipLine(("%s (%d)"):format(C_Item.GetItemNameByID(food.itemID) or "?", food.count or 1), "textMuted")
	end
	local left = ns.PetCare_TrainingLeft(C_PetInfo.GetPetTrainingPoints())
	if left > 0 then
		UI.TipLine(("%d training points to spend"):format(left), "textMuted")
	end
	GameTooltip:Show()
end

-- Created out of combat, on first need: protected frames can't be made in combat.
local function CreateButton()
	button = CreateFrame("Button", BUTTON_NAME, UIParent, "SecureActionButtonTemplate")
	button:SetSize(SIZE, SIZE)
	button:SetFrameStrata("MEDIUM")
	button:SetMovable(true)
	button:SetClampedToScreen(true)
	button:RegisterForClicks("AnyDown")
	button:SetAttribute("useOnKeyDown", true)
	button.icon = button:CreateTexture(nil, "ARTWORK")
	button.icon:SetAllPoints()
	button.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	button:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
	button:SetScript("OnEnter", ShowTooltip)
	button:SetScript("OnLeave", GameTooltip_Hide)
	button:ClearAllPoints()
	button:SetPoint(db.frame.point, UIParent, db.frame.relPoint, db.frame.x, db.frame.y)
	button:Hide()
end

local function Hide()
	if button and not InCombatLockdown() then
		button:SetAttribute("type", nil)
		button:SetAttribute("macrotext", nil)
		button:Hide()
	end
end

-- Out of combat only: the secure attributes can't change in combat.
local function Update()
	if not module.active or InCombatLockdown() then
		return
	end
	food = nil
	if ns.EditMode_Active() then -- something to drag, which feeds nothing
		if not button then
			CreateButton()
		end
		button:SetAttribute("type", nil)
		button:SetAttribute("macrotext", nil)
		button.icon:SetTexture(ICON)
		button:Show()
		return
	end
	if not PetOut() or not ns.PetCare_WantsFood((C_PetInfo.GetPetHappiness())) then
		toldNoFood = false
		Hide()
		return
	end
	local spellName = C_Spell.GetSpellName(FEED_PET)
	food = ns.PetCare_PickFood(Foods(), UnitLevel("pet"))
	if not (food and spellName) then
		Hide()
		if not toldNoFood and db.noFoodToast then
			toldNoFood = true
			local diet = ns.PetCare_DietText(C_PetInfo.GetPetFoodTypes())
			ns.Toast_Show({ owner = "petcare", label = "Pet care", title = "Your pet is hungry",
				text = "No food for it in your bags." .. (diet and (" It eats: " .. diet .. ".") or ""), icon = ICON,
				hold = TOAST_HOLD })
		end
		return
	end
	if not button then
		CreateButton()
	end
	button.icon:SetTexture(food.icon or ICON)
	button:SetAttribute("type", "macro")
	button:SetAttribute("macrotext", ns.PetCare_Macro(spellName, food))
	button:Show()
end

local updateSoon = UI.Debounce(UPDATE_DELAY, Update)

-- Events ---------------------------------------------------------------------------------------------------------------

events.UNIT_HAPPINESS = updateSoon
events.UNIT_PET = updateSoon
events.BAG_UPDATE_DELAYED = updateSoon
events.PLAYER_ENTERING_WORLD = updateSoon

-- Fires just before the lockdown starts: the last moment a secure button can be hidden.
function events:PLAYER_REGEN_DISABLED()
	Hide()
end

events.PLAYER_REGEN_ENABLED = updateSoon

local EVENTS = { "BAG_UPDATE_DELAYED", "PLAYER_ENTERING_WORLD", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED" }

events:SetScript("OnEvent", ns.Perf_WrapEvents(function(self, event, ...)
	self[event](self, ...)
end))

ns.EditMode_Register({
	name = "Feed pet button",
	frame = function()
		return button
	end,
	refresh = Update,
	saved = function()
		local point, _, relPoint, x, y = button:GetPoint()
		db.frame.point, db.frame.relPoint, db.frame.x, db.frame.y = point, relPoint, x, y
	end,
	module = "petcare",
	reset = function()
		db.frame.point, db.frame.relPoint, db.frame.x, db.frame.y = "CENTER", "CENTER", 0, -160
		if button and not InCombatLockdown() then
			button:ClearAllPoints()
			button:SetPoint(db.frame.point, UIParent, db.frame.relPoint, db.frame.x, db.frame.y)
		end
	end,
})

-- Commands ------------------------------------------------------------------------------------------------------------

local function Why()
	if not ns.Module_RequireOn(module) then
		return
	end
	if not PetOut() then
		ns.Print("Pet care: no pet out.")
		return
	end
	local happiness, damage, loyalty = C_PetInfo.GetPetHappiness()
	local foods = Foods()
	local pick = ns.PetCare_PickFood(foods, UnitLevel("pet"))
	ns.Print(("Pet care: %s, %s%% damage, loyalty rate %s, %s."):format(ns.PetCare_Mood(happiness) or "unknown",
		tostring(damage), tostring(loyalty), C_PetInfo.GetPetLoyalty() or "no loyalty"))
	ns.Print(("Eats: %s. %d foods in your bags%s."):format(ns.PetCare_DietText(C_PetInfo.GetPetFoodTypes()) or "unknown",
		#foods, pick and (", would feed " .. (C_Item.GetItemNameByID(pick.itemID) or "?")) or ""))
	ns.Print(("%d training points to spend. Feed Pet: %s."):format(
		ns.PetCare_TrainingLeft(C_PetInfo.GetPetTrainingPoints()), tostring(C_Spell.GetSpellName(FEED_PET))))
end

-- Module ---------------------------------------------------------------------------------------------------------------

module = ns.RegisterModule({
	key = "petcare",
	name = "Pet care",
	category = "class",
	icon = ICON,
	summary = "A one-click feed button when your pet isn't happy.",
	description = "When your pet isn't happy, a button appears with the right food from your bags: one click feeds it. "
		.. "Its tooltip shows your pet's mood, its damage and its training points. Out of combat only.",
	enabledByDefault = true,
	blocked = function()
		if not IsHunter() then
			return "Only for hunters."
		end
	end,
	toasts = "Pet care",
	defaults = {
		noFoodToast = true,
		frame = { point = "CENTER", relPoint = "CENTER", x = 0, y = -160 }, -- the button's spot (/tomte unlock)
	},
	init = function(moduleDB)
		db = moduleDB
	end,
	toggle = function(active)
		if active then
			for _, event in ipairs(EVENTS) do
				events:RegisterEvent(event)
			end
			events:RegisterUnitEvent("UNIT_HAPPINESS", "pet")
			events:RegisterUnitEvent("UNIT_PET", "player")
			updateSoon()
		else
			events:UnregisterAllEvents()
			toldNoFood = false
			food = nil
			Hide()
			ns.Toast_Clear("petcare")
		end
	end,
	commands = {
		{ "why", "your pet's mood, diet, food in your bags and training points", Why },
	},
	options = {
		{ type = "header", label = "Feeding" },
		{ type = "checkbox", key = "noFoodToast", label = "Tell me when there's no food",
			tooltip = "A toast with what your pet eats when it's hungry and your bags have nothing for it." },
	},
})
