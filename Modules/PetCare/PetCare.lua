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
local BEAST_TRAINING = 5149 -- checked on wowhead.com/forever, 2026-11-06
local TRAIN_BUTTON_NAME = "TomtePetTrain"
local TRAIN_ABOVE = 20 -- px above the feed button: clears the training button's own label
local UPDATE_DELAY = 0.3 -- seconds: bursts of bag and pet events
local TOAST_HOLD = 10

local UI = ns.UI

local module, db, button
local food -- what the button feeds now
local toldNoFood = false
local toldNoSpell = false
local eatingUntil -- GetTime() when the feeding seen last ends
local fedBefore = false -- fed since the pet was last happy
local ticker -- counts the feeding down under the button
local trainButton
local trainerOpen = false -- Beast Training's window
local toldTraining -- what the last training toast was about
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

-- Seconds left of the feeding seen last, nil when there's none.
local function EatingLeft()
	local left = eatingUntil and eatingUntil - GetTime()
	return left and left > 0 and left or nil
end

local function ShowTooltip(self)
	GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
	local happiness, damage = C_PetInfo.GetPetHappiness()
	GameTooltip:SetText("Feed your pet")
	UI.TipLine(("%s, doing %d%% damage"):format(ns.PetCare_Mood(happiness) or "?", damage or 0), "text")
	if EatingLeft() then
		UI.TipLine("It's eating now, so there's no need to click. If it's still hungry afterwards, you can feed it again.",
			"text", true)
	elseif food then
		UI.TipLine(("%s (%d)"):format(C_Item.GetItemNameByID(food.itemID) or "?", food.count or 1), "text")
		local text, role = ns.PetCare_FoodTip(food.value)
		UI.TipLine(text, role, true)
		UI.TipLine(("Click once, then wait: it eats for %d seconds. The button goes away when it's happy."):format(
			ns.PETCARE_EAT_SECONDS), "textMuted", true)
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
	UI.ActionIcon(button, button.icon, SIZE)
	button.label = UI.Text(button, 11, "text", "label")
	button.label:SetPoint("TOP", button, "BOTTOM", 0, -3)
	button:SetScript("OnEnter", ShowTooltip)
	button:SetScript("OnLeave", GameTooltip_Hide)
	button:ClearAllPoints()
	button:SetPoint(db.frame.point, UIParent, db.frame.relPoint, db.frame.x, db.frame.y)
	button:Hide()
end

-- A click casts Feed Pet and hands it this bag slot. Blizzard's button only touches the item while a spell is waiting for
-- one, so a Feed Pet that didn't start does nothing. A "/cast, /use" macro made the hunter eat the food instead (seen in
-- game, Feed Pet not learned yet). unit "none" is the macro's [@none]: the spell waits for its item instead of going to a soft target.
local function SetFood(spellName, picked)
	button:SetAttribute("type", spellName and "spell" or nil)
	button:SetAttribute("spell", spellName)
	button:SetAttribute("unit", spellName and "none" or nil)
	button:SetAttribute("target-bag", picked and picked.bag)
	button:SetAttribute("target-slot", picked and picked.slot)
end

local function StopTicker()
	if ticker then
		ticker:Cancel()
		ticker = nil
	end
end

local function Hide()
	StopTicker()
	if button and not InCombatLockdown() then
		SetFood(nil)
		button:Hide()
	end
end

-- The button's picture and words. greyed: nothing a click would do now.
local function Paint(icon, greyed, text, role)
	if not button then
		CreateButton()
	end
	button.icon:SetTexture(icon)
	button.icon:SetDesaturated(greyed)
	button.label:SetText(text)
	UI.SetTextRole(button.label, role)
end

local Update

-- Once a second while it eats: the countdown, then whether it needs more. Not protected, so the words may change in combat.
local function Tick()
	local left = EatingLeft()
	if not left then
		StopTicker()
		Update()
	elseif button and button:IsShown() then
		button.label:SetText((ns.PetCare_Label({ eatingLeft = left })))
	end
end

-- Out of combat only: the secure attributes can't change in combat.
function Update()
	if not module.active or InCombatLockdown() then
		return
	end
	food = nil
	if ns.EditMode_Active() then -- something to drag, which feeds nothing
		Paint(ICON, false, "Feed pet", "textMuted")
		SetFood(nil)
		button:Show()
		return
	end
	if not PetOut() or not ns.PetCare_WantsFood((C_PetInfo.GetPetHappiness())) then
		toldNoFood, toldNoSpell, fedBefore = false, false, false
		Hide()
		return
	end
	-- A feeding takes a while to show in its mood. The button stays, greyed with a countdown, so more food isn't wasted on
	-- a pet that's already eating and it's clear that the answer is to wait.
	local left = EatingLeft()
	if left then
		Paint(ICON, true, ns.PetCare_Label({ eatingLeft = left }))
		SetFood(nil)
		button:Show()
		ticker = ticker or C_Timer.NewTicker(1, Tick)
		return
	end
	-- A new hunter has a pet before Feed Pet: GetSpellName answers for any spell, so it says nothing about this.
	if not ns.SpellKnown(FEED_PET) then
		Hide()
		if not toldNoSpell and db.noFoodToast then
			toldNoSpell = true
			ns.Toast_Show({ owner = "petcare", label = "Pet care", title = "Your pet is hungry",
				text = "You haven't learned Feed Pet yet.", icon = ICON, hold = TOAST_HOLD })
		end
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
	food.value = ns.PetCare_FoodValue(food.ilvl, UnitLevel("pet"))
	Paint(food.icon or ICON, false, ns.PetCare_Label({ value = food.value, fedBefore = fedBefore }))
	SetFood(spellName, food)
	button:Show()
end

-- Training ---------------------------------------------------------------------------------------------------------------

-- A button above the feed one (so Edit Mode moves both) that opens Beast Training, up while there's something to do there.
-- What the window offers is only readable while it's open, so it's remembered per pet (db.training).

-- One pet of one character. The name, as there's no pet number to read away from a stable: a renamed pet starts over.
local function PetKey()
	local name = UnitName("pet")
	return name and not ns.IsSecret(name) and (UnitGUID("player") .. ":" .. name) or nil
end

local function PointsLeft()
	return ns.PetCare_TrainingLeft(C_PetInfo.GetPetTrainingPoints())
end

local function HideTraining()
	if trainButton and not InCombatLockdown() then
		trainButton:Hide()
	end
end

local function TrainTooltip(self)
	GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
	GameTooltip:SetText("Train your pet")
	local record = db.training[PetKey() or ""]
	UI.TipLine(ns.PetCare_TrainingText(record and "ready" or "unread", PointsLeft(), record and record.rows,
		UnitLevel("pet")), "text", true)
	UI.TipLine("Click to open Beast Training. This goes away once you've looked, until there's more to spend.",
		"textMuted", true)
	GameTooltip:Show()
end

-- Out of combat only: it's protected, and anchored to the feed button, which has to exist for that.
local function CreateTrainButton()
	if not button then
		CreateButton()
	end
	trainButton = CreateFrame("Button", TRAIN_BUTTON_NAME, UIParent, "SecureActionButtonTemplate")
	trainButton:SetSize(SIZE, SIZE)
	trainButton:SetFrameStrata("MEDIUM")
	trainButton:RegisterForClicks("AnyDown")
	trainButton:SetAttribute("useOnKeyDown", true)
	trainButton:SetPoint("BOTTOM", button, "TOP", 0, TRAIN_ABOVE)
	trainButton.icon = trainButton:CreateTexture(nil, "ARTWORK")
	trainButton.icon:SetAllPoints()
	UI.ActionIcon(trainButton, trainButton.icon, SIZE)
	trainButton.icon:SetTexture(C_Spell.GetSpellTexture(BEAST_TRAINING))
	trainButton.label = UI.Text(trainButton, 11, "text", "label")
	trainButton.label:SetPoint("TOP", trainButton, "BOTTOM", 0, -3)
	trainButton.label:SetText("Train pet")
	trainButton:SetScript("OnEnter", TrainTooltip)
	trainButton:SetScript("OnLeave", GameTooltip_Hide)
	trainButton:Hide()
end

-- Out of combat only, like the feed button.
local function UpdateTraining()
	if not module.active or InCombatLockdown() then
		return
	end
	local key = PetOut() and PetKey()
	if not (key and db.trainReminder and not trainerOpen and not ns.EditMode_Active()
		and ns.SpellKnown(BEAST_TRAINING)) then
		HideTraining()
		return
	end
	local left, level = PointsLeft(), UnitLevel("pet")
	local record = db.training[key]
	local state = ns.PetCare_TrainingState(record, left, level)
	if not state then
		HideTraining()
		return
	end
	if not trainButton then
		CreateTrainButton()
	end
	trainButton:SetAttribute("type", "macro")
	trainButton:SetAttribute("macrotext", "/cast " .. (C_Spell.GetSpellName(BEAST_TRAINING) or ""))
	trainButton:Show()
	-- Once for each new thing to say, not on every bag or mood change while the button is up.
	local said = key .. ":" .. state .. ":" .. left .. ":" .. level
	if toldTraining ~= said then
		toldTraining = said
		ns.Toast_Show({ owner = "petcare", label = "Pet care", title = state == "ready"
			and "Your pet can learn something new" or "Your pet has training points",
			text = ns.PetCare_TrainingText(state, left, record and record.rows, level),
			icon = C_Spell.GetSpellTexture(BEAST_TRAINING), hold = TOAST_HOLD })
	end
end

-- The Beast Training window is open (Blizzard's class trainer window, in its pet mode): what it offers now.
local function ReadTrainer()
	local key = PetKey()
	if not key or C_Trainer.GetTrainerType() ~= Enum.TrainerType.Pet then
		return
	end
	local rows = {}
	for i = 1, GetNumTrainerServices() or 0 do
		local name, serviceType, _, level, rank = GetTrainerServiceInfo(i)
		rows[#rows + 1] = ns.PetCare_SlimTraining(name, serviceType, rank, level, (GetTrainerServiceCost(i)))
	end
	db.training[key] = { rows = rows, seenLeft = PointsLeft(), seenLevel = UnitLevel("pet") }
end

local updateSoon = UI.Debounce(UPDATE_DELAY, function()
	Update()
	UpdateTraining()
end)

local function TrainerChanged()
	trainerOpen = true
	ReadTrainer()
	UpdateTraining()
end

events.TRAINER_SHOW = TrainerChanged
events.TRAINER_UPDATE = TrainerChanged

function events:TRAINER_CLOSED()
	trainerOpen = false
	UpdateTraining()
end

-- While the window is open its points count as seen.
function events:UNIT_PET_TRAINING_POINTS()
	if trainerOpen then
		ReadTrainer()
	end
	updateSoon()
end

-- Events ---------------------------------------------------------------------------------------------------------------

events.UNIT_HAPPINESS = updateSoon
events.UNIT_PET = updateSoon
events.BAG_UPDATE_DELAYED = updateSoon
events.SPELLS_CHANGED = updateSoon -- Feed Pet just learned
events.PLAYER_ENTERING_WORLD = updateSoon

-- Any Feed Pet counts, this button's or the spellbook's.
function events:UNIT_SPELLCAST_SUCCEEDED(_, _, spellID)
	if not ns.IsSecret(spellID) and spellID == FEED_PET then
		eatingUntil = GetTime() + ns.PETCARE_EAT_SECONDS
		fedBefore = true
		Update()
	end
end

-- Fires just before the lockdown starts: the last moment a secure button can be hidden.
function events:PLAYER_REGEN_DISABLED()
	Hide()
	HideTraining()
end

events.PLAYER_REGEN_ENABLED = updateSoon

local EVENTS = { "BAG_UPDATE_DELAYED", "PLAYER_ENTERING_WORLD", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED",
	"SPELLS_CHANGED", "TRAINER_SHOW", "TRAINER_UPDATE", "TRAINER_CLOSED", "UNIT_PET_TRAINING_POINTS" }

events:SetScript("OnEvent", ns.Perf_WrapEvents(function(self, event, ...)
	self[event](self, ...)
end))

ns.EditMode_Register({
	name = "Feed pet button",
	frame = function()
		return button
	end,
	refresh = function()
		Update()
		UpdateTraining()
	end,
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
		#foods, pick and (", would feed %s (%s)"):format(C_Item.GetItemNameByID(pick.itemID) or "?",
			ns.PetCare_FoodValue(pick.ilvl, UnitLevel("pet"))) or ""))
	ns.Print(("%d training points to spend. Feed Pet: %s."):format(
		ns.PetCare_TrainingLeft(C_PetInfo.GetPetTrainingPoints()), ns.SpellKnown(FEED_PET) and "learned" or "not learned"))
end

-- Module ---------------------------------------------------------------------------------------------------------------

module = ns.RegisterModule({
	key = "petcare",
	name = "Pet care",
	category = "class",
	icon = ICON,
	summary = "A one-click feed button when your pet isn't happy.",
	description = "When your pet isn't happy, a button appears with the right food from your bags. Click it once: it counts "
		.. "down while your pet eats and only asks again if it's still hungry, so no food is wasted. Its tooltip shows your "
		.. "pet's mood, its damage and its training points. A second button opens Beast Training when your pet can learn "
		.. "something new. Out of combat only.",
	enabledByDefault = true,
	blocked = function()
		if not IsHunter() then
			return "Only for hunters."
		end
	end,
	toasts = "Pet care",
	defaults = {
		noFoodToast = true,
		trainReminder = true,
		training = {}, -- [player GUID:pet name] = { rows = { { name, level, cost } }, seenLeft, seenLevel } (Beast Training)
		frame ={ point = "CENTER", relPoint = "CENTER", x = 0, y = -160 }, -- the button's spot (/tomte unlock)
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
			events:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
			updateSoon()
		else
			events:UnregisterAllEvents()
			toldNoFood, toldNoSpell, fedBefore = false, false, false
			eatingUntil = nil
			food = nil
			trainerOpen, toldTraining = false, nil
			Hide()
			HideTraining()
			ns.Toast_Clear("petcare")
		end
	end,
	commands = {
		{ "why", "your pet's mood, diet, food in your bags and training points", Why },
	},
	options = {
		{ type = "header", label = "Feeding" },
		{ type = "checkbox", key = "noFoodToast", label = "Tell me when I can't feed it",
			tooltip = "A toast when your pet is hungry and you haven't learned Feed Pet, or your bags have nothing it eats (with what it eats)." },

		{ type = "header", label = "Training" },
		{ type = "checkbox", key = "trainReminder", label = "Remind me when my pet can learn something",
			onChange = function()
				updateSoon()
			end,
			tooltip = "A toast and a button that opens Beast Training when your pet has the points and level for something new. It learns what's on offer each time you open Beast Training." },
	},
})
