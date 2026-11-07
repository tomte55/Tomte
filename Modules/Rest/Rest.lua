local addonName, ns = ...

-- Eat and drink (World of Warcraft: Forever only; tools/forever_list.lua): one key (Key Bindings > Tomte) or button uses your
-- best food and drink, a bandage with no food left, and warns when you're running out. Out of combat only: the button is
-- secure. The game hides your health from addons even out of combat (UnitHealth always returns a secret value, measured
-- on 1.60.1), so nothing here can decide by it. Instead the button stays up, faint, and the game itself lights it through a
-- curve when you're low; a press always eats. Rules in Data.lua. See
-- docs/superpowers/specs/2026-11-06-tomte-forever-rest-and-chat-groups.md.

local BUTTON_NAME = "TomteRest"
local SIZE = 44
local ICON = 136000 -- spell_misc_food, as Buff reminders
local BAGS = { 0, 1, 2, 3, 4 }
local UPDATE_DELAY = 0.3 -- seconds: bursts of health, aura and bag events
local TOAST_HOLD = 8
local FAINT = 0.35 -- the button's opacity when nothing is low

local UI = ns.UI
local IsSecret = ns.IsSecret

local module, db, button
local curves = {} -- [key] = { curve = the game's curve, at = the setting it's built for }
local supplies -- { food = {...}, drink = {...}, bandage = {...} } in the bags, nil until read again after a bag change
local kinds = {} -- [itemID] = "food" | "drink" | "bandage" | false: what an item is never changes
local buffFood = {} -- [itemID] = its tooltip names Well Fed
local lastCount = {} -- [kind] = how many were carried at the last read, for the low warning
local events = CreateFrame("Frame")

local function SpellNames()
	return { food = C_Spell.GetSpellName(ns.REST_FOOD_SPELL), drink = C_Spell.GetSpellName(ns.REST_DRINK_SPELL),
		bandage = C_Spell.GetSpellName(ns.REST_BANDAGE_SPELL) }
end

local function ItemKind(itemID)
	if kinds[itemID] == nil then
		local spellName = C_Item.GetItemSpell(itemID)
		if not spellName then
			return nil -- no spell, or its data isn't loaded yet: ask again next time
		end
		kinds[itemID] = ns.Rest_ItemKind(spellName, SpellNames()) or false
	end
	return kinds[itemID] or nil
end

local function IsBuffFood(itemID)
	if buffFood[itemID] == nil then
		local wellFed = (C_Spell.GetSpellName(ns.REST_WELL_FED) or ""):lower()
		local data = C_TooltipInfo.GetItemByID(itemID)
		if not (data and wellFed ~= "") then
			return false
		end
		buffFood[itemID] = false
		for _, line in ipairs(data.lines) do
			if line.leftText and line.leftText:lower():find(wellFed, 1, true) then
				buffFood[itemID] = true
			end
		end
	end
	return buffFood[itemID]
end

local function WarnLow(kind, count)
	local limit = db.lowCount
	if ns.Rest_JustLow(lastCount[kind], count, limit) and (kind ~= "drink" or UnitPowerMax("player", Enum.PowerType.Mana) > 0) then
		ns.Toast_Show({ owner = "rest", label = "Eat and drink", title = kind == "food" and "Running low on food"
			or "Running low on drink", text = ("%d left in your bags."):format(count), icon = ICON, hold = TOAST_HOLD })
	end
	lastCount[kind] = count
end

local function ReadSupplies()
	if supplies then
		return supplies
	end
	supplies = { food = {}, drink = {}, bandage = {} }
	local seen = {}
	local counts = { food = 0, drink = 0 }
	for _, bag in ipairs(BAGS) do
		for slot = 1, C_Container.GetContainerNumSlots(bag) or 0 do
			local info = C_Container.GetContainerItemInfo(bag, slot)
			local kind = info and info.itemID and ItemKind(info.itemID)
			if kind then
				counts[kind] = (counts[kind] or 0) + (info.stackCount or 1)
				if not seen[info.itemID] and C_Item.IsUsableItem(info.itemID) ~= false then
					seen[info.itemID] = true
					local _, _, _, _, level = C_Item.GetItemInfo(info.itemID)
					local list = supplies[kind]
					list[#list + 1] = { itemID = info.itemID, level = level,
						buff = kind == "food" and IsBuffFood(info.itemID) or false }
				end
			end
		end
	end
	WarnLow("food", counts.food)
	WarnLow("drink", counts.drink)
	-- Dead or a ghost, IsUsableItem says no to every food and drink: that read isn't kept, or after reviving the button
	-- said "No food" with full bags until the bags next changed.
	local read = supplies
	if UnitIsDeadOrGhost("player") then
		supplies = nil
	end
	return read
end

local function HasAura(name, filter)
	return name ~= nil and C_UnitAuras.GetAuraDataBySpellName("player", name, filter) ~= nil
end

-- A share of a maximum, nil when it can't be read (secret, or no maximum).
local function Share(value, max)
	if IsSecret(value) or IsSecret(max) or not max or max <= 0 then
		return nil
	end
	return value / max
end

local function Situation()
	local have = ReadSupplies()
	local food, drink, bandage = ns.Rest_Pick(have.food), ns.Rest_Pick(have.drink), ns.Rest_Pick(have.bandage)
	local names = SpellNames()
	local maxMana = UnitPowerMax("player", Enum.PowerType.Mana)
	local hasMana = IsSecret(maxMana) or maxMana > 0
	local mana = Share(UnitPower("player", Enum.PowerType.Mana), maxMana)
	return {
		blocked = InCombatLockdown() or UnitIsDeadOrGhost("player") or IsMounted() or UnitOnTaxi("player")
			or UnitInVehicle("player"),
		health = Share(UnitHealth("player"), UnitHealthMax("player")),
		mana = mana,
		manaUnknown = hasMana and mana == nil,
		hasMana = hasMana,
		healthAt = db.healthAt / 100,
		manaAt = db.manaAt / 100,
		eating = HasAura(names.food, "HELPFUL"),
		drinking = HasAura(names.drink, "HELPFUL"),
		bandaged = HasAura(C_Spell.GetSpellName(ns.REST_BANDAGED), "HARMFUL"),
		food = food and food.itemID,
		drink = drink and drink.itemID,
		bandage = bandage and bandage.itemID,
	}
end

local function ShowTooltip(self)
	GameTooltip:SetOwner(self, "ANCHOR_TOP")
	GameTooltip:SetText("Eat and drink")
	local s = Situation()
	local function Line(label, itemID)
		if itemID then
			UI.TipLine(("%s: %s"):format(label, C_Item.GetItemNameByID(itemID) or "?"), "text")
		end
	end
	Line("Food", s.food)
	Line("Drink", s.drink)
	Line("Bandage", s.bandage)
	UI.TipLine("Bright when you're low. Click or press the key once, out of combat, and it eats whatever your health. "
		.. "Low on mana, it drinks first and eats on the next press. "
		.. "Key Bindings > Tomte > Eat and drink.", "textMuted", true)
	GameTooltip:Show()
end

-- The macro for this press: read at the click, so it's right whatever changed since the button was last drawn.
local function PreClick()
	if InCombatLockdown() then
		return
	end
	button:SetAttribute("type", "macro")
	button:SetAttribute("macrotext", module.active and ns.Rest_Macro(ns.Rest_Plan(Situation()).uses) or "")
end

local function NewFace(parent)
	local face = CreateFrame("Frame", nil, parent)
	face:SetAllPoints()
	face.icon = face:CreateTexture(nil, "ARTWORK")
	face.icon:SetAllPoints()
	UI.ActionIcon(face, face.icon, SIZE)
	face.label = UI.Text(face, 11, "text", "label")
	face.label:SetPoint("TOP", face, "BOTTOM", 0, -3)
	return face
end

-- Out of combat only: protected frames can't be made in combat.
local function CreateButton()
	button = CreateFrame("Button", BUTTON_NAME, UIParent, "SecureActionButtonTemplate")
	button:SetSize(SIZE, SIZE)
	button:SetFrameStrata("MEDIUM")
	button:SetMovable(true)
	button:SetClampedToScreen(true)
	button:RegisterForClicks("AnyDown")
	button:SetAttribute("useOnKeyDown", true)
	button:SetAttribute("type", "macro")
	button:SetAttribute("macrotext", "")
	button:SetScript("PreClick", PreClick)
	-- The same face three times: faint always, and one each that the game lights for low health and low mana. Two lit
	-- layers as hidden values can't be combined in Lua. Plain frames, so the secret opacity stays off the secure button.
	button.faint = NewFace(button)
	button.faint:SetAlpha(FAINT)
	button.forHealth = NewFace(button)
	button.forMana = NewFace(button)
	button:SetScript("OnEnter", ShowTooltip)
	button:SetScript("OnLeave", GameTooltip_Hide)
	button:ClearAllPoints()
	button:SetPoint(db.frame.point, UIParent, db.frame.relPoint, db.frame.x, db.frame.y)
	button:Hide()
end

local function Fill(texture, desaturated, text, role)
	for _, face in ipairs({ button.faint, button.forHealth, button.forMana }) do
		face.icon:SetTexture(texture)
		face.icon:SetDesaturated(desaturated)
		face.label:SetText(text)
		UI.SetTextRole(face.label, role)
	end
end

-- The game's curve for a setting; only rebuilt when the setting moves.
local function Curve(key, at)
	local entry = curves[key]
	if not entry then
		entry = { curve = C_CurveUtil.CreateCurve() }
		entry.curve:SetType(Enum.LuaCurveType.Linear)
		curves[key] = entry
	end
	if entry.at ~= at then
		entry.at = at
		entry.curve:ClearPoints()
		for _, point in ipairs(ns.Rest_CurvePoints(at)) do
			entry.curve:AddPoint(point[1], point[2])
		end
	end
	return entry.curve
end

-- An opacity: possibly a secret one, which only the game can read. Passed on, never compared.
local function HealthLight(s)
	if s.eating then
		return 0
	elseif s.health then
		return s.health < s.healthAt and 1 or 0
	end
	return UnitHealthPercent("player", true, Curve("health", s.healthAt))
end

local function ManaLight(s)
	if s.drinking or not s.hasMana then
		return 0
	elseif s.mana then
		return s.mana < s.manaAt and 1 or 0
	end
	return UnitPowerPercent("player", Enum.PowerType.Mana, false, Curve("mana", s.manaAt))
end

-- Out of combat only: the button is protected.
local function Update()
	if not module.active or InCombatLockdown() then
		return
	end
	if not button then
		CreateButton()
	end
	if ns.EditMode_Active() then -- something to drag
		Fill(ICON, false, "Eat and drink", "textMuted")
		button.forHealth:SetAlpha(1)
		button.forMana:SetAlpha(0)
		button:Show()
		return
	end
	local s = Situation()
	local plan = ns.Rest_Plan(s)
	if not (db.shown and plan.text) then
		button:Hide()
		return
	end
	Fill(plan.icon and C_Item.GetItemIconByID(plan.icon) or ICON, plan.icon == nil, plan.text, plan.role)
	button.forHealth:SetAlpha(HealthLight(s))
	button.forMana:SetAlpha(ManaLight(s))
	button:Show()
end

-- Not UI.Debounce, which starts its wait over at each call: health and mana keep changing while you recover, just when the
-- button is needed, so it might never get to run.
local updatePending = false
local function updateSoon()
	if updatePending then
		return
	end
	updatePending = true
	C_Timer.After(UPDATE_DELAY, function()
		updatePending = false
		Update()
	end)
end

function events:BAG_UPDATE_DELAYED()
	supplies = nil
	updateSoon()
end

-- Fires just before the lockdown starts: the last moment a secure button can change.
function events:PLAYER_REGEN_DISABLED()
	if button then
		button:SetAttribute("macrotext", "")
		button:Hide()
	end
end

events.PLAYER_REGEN_ENABLED = updateSoon
events.PLAYER_ENTERING_WORLD = updateSoon
events.PLAYER_MOUNT_DISPLAY_CHANGED = updateSoon
-- Back alive: what you carry is usable again, so it's read afresh.
function events:PLAYER_ALIVE()
	supplies = nil
	updateSoon()
end

events.PLAYER_UNGHOST = events.PLAYER_ALIVE
events.UNIT_HEALTH = updateSoon
events.UNIT_POWER_UPDATE = updateSoon
events.UNIT_AURA = updateSoon

events:SetScript("OnEvent", ns.Perf_WrapEvents(function(self, event, ...)
	self[event](self, ...)
end))

local EVENTS = { "BAG_UPDATE_DELAYED", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "PLAYER_ENTERING_WORLD",
	"PLAYER_MOUNT_DISPLAY_CHANGED", "PLAYER_ALIVE", "PLAYER_UNGHOST" }

ns.EditMode_Register({
	name = "Eat and drink button",
	frame = function()
		return button
	end,
	refresh = Update,
	saved = function()
		local point, _, relPoint, x, y = button:GetPoint()
		db.frame.point, db.frame.relPoint, db.frame.x, db.frame.y = point, relPoint, x, y
	end,
	module = "rest",
	reset = function()
		db.frame.point, db.frame.relPoint, db.frame.x, db.frame.y = "CENTER", "CENTER", 0, -220
		if button and not InCombatLockdown() then
			button:ClearAllPoints()
			button:SetPoint(db.frame.point, UIParent, db.frame.relPoint, db.frame.x, db.frame.y)
		end
	end,
})

local function Why()
	if not ns.Module_RequireOn(module) then
		return
	end
	local names = SpellNames()
	ns.Print(("Eat and drink: the game calls them %s, %s and %s."):format(tostring(names.food), tostring(names.drink),
		tostring(names.bandage)))
	local have = ReadSupplies()
	ns.Print(("In your bags: %d kinds of food, %d of drink, %d of bandage."):format(#have.food, #have.drink, #have.bandage))
	local s = Situation()
	local plan = ns.Rest_Plan(s)
	ns.Print(("Health %s, mana %s. A press now: %s."):format(
		s.health and (("%d%%"):format(s.health * 100)) or "hidden by the game",
		s.mana and (("%d%%"):format(s.mana * 100)) or (s.manaUnknown and "hidden by the game" or "none"),
		#plan.uses > 0 and ns.Rest_Macro(plan.uses):gsub("\n", ", ")
		or (plan.text or "nothing")))
	-- Each thing that keeps the button away.
	print(("  held back by: combat %s, dead %s, mounted %s, taxi %s, vehicle %s, health secret %s"):format(
		tostring(InCombatLockdown()), tostring(UnitIsDeadOrGhost("player")), tostring(IsMounted()),
		tostring(UnitOnTaxi("player")), tostring(UnitInVehicle("player")), tostring(IsSecret(UnitHealth("player")))))
	print(("  eating %s, drinking %s, setting to show it %s, says %s"):format(tostring(s.eating), tostring(s.drinking),
		tostring(db.shown), tostring(plan.text)))
	if button then
		print(("  button: shown %s, visible %s, at %s %d %d, size %d"):format(tostring(button:IsShown()),
			tostring(button:IsVisible()), tostring(db.frame.point), db.frame.x, db.frame.y, button:GetWidth()))
	else
		print("  button: not made yet")
	end
end

local function Percent(v)
	return ("%d%%"):format(v)
end

module = ns.RegisterModule({
	key = "rest",
	name = "Eat and drink",
	category = "class",
	icon = ICON,
	summary = "One key or button that eats and drinks the best you carry.",
	description = "A faint button that lights up when your health or mana is low. One press uses your best food, and drink if "
		.. "you're low on mana, or a bandage with no food left. Buff food is kept for last. The game doesn't let addons read "
		.. "your health, so a press eats whatever your health is. Bind the key under Key Bindings > Tomte. It warns you when "
		.. "you're running out. Out of combat only.",
	enabledByDefault = true,
	toasts = "Running low",
	defaults = {
		shown = true,
		healthAt = 70, -- percent
		manaAt = 70, -- percent
		lowCount = 5, -- warn when you're down to this many; 0 is never
		frame = { point = "CENTER", relPoint = "CENTER", x = 0, y = -220 }, -- the button's spot (/tomte unlock)
	},
	init = function(moduleDB)
		db = moduleDB
	end,
	toggle = function(active)
		if active then
			for _, event in ipairs(EVENTS) do
				events:RegisterEvent(event)
			end
			events:RegisterUnitEvent("UNIT_HEALTH", "player")
			events:RegisterUnitEvent("UNIT_POWER_UPDATE", "player")
			events:RegisterUnitEvent("UNIT_AURA", "player")
			supplies = nil
			updateSoon()
		else
			events:UnregisterAllEvents()
			if button and not InCombatLockdown() then
				button:SetAttribute("macrotext", "")
				button:Hide()
			end
			ns.Toast_Clear("rest")
		end
	end,
	commands = {
		{ "why", "what the button would use now, and why", Why },
	},
	options = {
		{ type = "header", label = "Eat and drink" },
		{ type = "checkbox", key = "shown", label = "Show the button", onChange = function()
			updateSoon()
		end, tooltip = "Faint until you're low. The key works either way. Blizzard's Edit Mode moves the button." },
		{ type = "slider", key = "healthAt", label = "Light up below this health", min = 30, max = 95, step = 5, format = Percent,
			onChange = function()
				updateSoon()
			end },
		{ type = "slider", key = "manaAt", label = "Light up and drink below this mana", min = 30, max = 95, step = 5, format = Percent,
			onChange = function()
				updateSoon()
			end },
		{ type = "slider", key = "lowCount", label = "Warn at this many left", min = 0, max = 20, step = 1,
			tooltip = "A toast when your food or drink drops to this many. 0 turns it off." },
	},
})
