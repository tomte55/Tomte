local addonName, ns = ...

-- Hunter Pets on World of Warcraft: Forever: the aspect button. Shows out of combat when no aspect is on, and one click
-- (or the "Put on your aspect" key binding) casts the best one you know. Not in an inn or a city, mounted, on a flight
-- or dead. Casting is protected, so the button is secure and only changes out of combat: it hides as a fight starts.
-- Rules in Data.lua (Hunter_AspectToCast); registered in Hunter.lua. Forever only: not in the retail TOC.

local BUTTON_NAME = "TomteHunterAspect"
local SIZE = 40
local LABEL_GAP = 3
local UPDATE_DELAY = 0.2 -- seconds: an aspect swap is a burst of aura events
local DEFAULT_POINT = { point = "CENTER", relPoint = "CENTER", x = 0, y = -140 }

local UI = ns.UI
local IsSecret = ns.IsSecret

local db, button
local active = false
local updatePending = false
local events = ns.NewEvents()
local OWNER = "hunterAspect"

-- Whether an aspect is on: true, false, or nil when the buffs can't be read right now.
local function AnyAspectOn()
	if C_Secrets and C_Secrets.ShouldAurasBeSecret and C_Secrets.ShouldAurasBeSecret() then
		return nil
	end
	for _, id in ipairs(ns.HUNTER_ASPECTS) do
		local name = C_Spell.GetSpellName(id)
		if name then
			local aura = C_UnitAuras.GetAuraDataBySpellName("player", name, "HELPFUL")
			if IsSecret(aura) then
				return nil
			end
			if aura then
				return true
			end
		end
	end
	return false
end

local function Situation()
	local known = {}
	for _, id in ipairs(ns.HUNTER_ASPECT_BEST) do
		known[id] = ns.SpellKnown(id)
	end
	return {
		known = known,
		anyOn = AnyAspectOn(),
		combat = InCombatLockdown(),
		dead = UnitIsDeadOrGhost("player"),
		resting = IsResting(),
		mounted = IsMounted(),
		taxi = UnitOnTaxi("player"),
	}
end

local function ShowTooltip(self)
	GameTooltip:SetOwner(self, "ANCHOR_TOP")
	GameTooltip:SetText(self.spellName or "Aspect")
	UI.TipLine("No aspect is on. Click to put it on.", "text", true)
	GameTooltip:Show()
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
	button:SetAttribute("type", "spell")
	button.icon = button:CreateTexture(nil, "ARTWORK")
	button.icon:SetAllPoints()
	UI.ActionIcon(button, button.icon, SIZE)
	button.label = UI.Text(button, 11, "warning", "label")
	button.label:SetPoint("TOP", button, "BOTTOM", 0, -LABEL_GAP)
	button.label:SetText("No aspect")
	button:SetScript("OnEnter", ShowTooltip)
	button:SetScript("OnLeave", GameTooltip_Hide)
	button:SetPoint(db.aspectFrame.point, UIParent, db.aspectFrame.relPoint, db.aspectFrame.x, db.aspectFrame.y)
	button:Hide()
end

-- The button's spell is set here, out of combat; in combat nothing changes (it hid as the fight started).
local function Update()
	if InCombatLockdown() then
		return
	end
	local spellID
	if active and db.aspect then
		spellID = ns.EditMode_Active() and ns.HUNTER_ASPECT_BEST[1] or ns.Hunter_AspectToCast(Situation())
	end
	if not spellID then
		if button then
			button:Hide()
		end
		return
	end
	if not button then
		CreateButton()
	end
	-- By name, without a rank: the game casts the highest rank you know.
	button.spellName = C_Spell.GetSpellName(spellID)
	button:SetAttribute("spell", button.spellName)
	button.icon:SetTexture(C_Spell.GetSpellTexture(spellID))
	button:Show()
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

local WATCHED = { "PLAYER_ENTERING_WORLD", "PLAYER_REGEN_ENABLED", "PLAYER_UPDATE_RESTING", "PLAYER_MOUNT_DISPLAY_CHANGED",
	"PLAYER_CONTROL_LOST", "PLAYER_CONTROL_GAINED", "PLAYER_ALIVE", "PLAYER_UNGHOST", "PLAYER_DEAD", "SPELLS_CHANGED" }
for _, event in ipairs(WATCHED) do
	events:On(OWNER, event, UpdateSoon)
end
events:On(OWNER, "UNIT_AURA", UpdateSoon)

-- Fires just before the lockdown starts: the last moment a secure button can hide.
events:On(OWNER, "PLAYER_REGEN_DISABLED", function()
	if button then
		button:Hide()
	end
end)

ns.EditMode_Register({
	name = "Aspect button",
	frame = function()
		return button
	end,
	refresh = Update,
	saved = function()
		local point, _, relPoint, x, y = button:GetPoint()
		db.aspectFrame.point, db.aspectFrame.relPoint, db.aspectFrame.x, db.aspectFrame.y = point, relPoint, x, y
	end,
	module = "hunter",
	reset = function()
		db.aspectFrame.point, db.aspectFrame.relPoint = DEFAULT_POINT.point, DEFAULT_POINT.relPoint
		db.aspectFrame.x, db.aspectFrame.y = DEFAULT_POINT.x, DEFAULT_POINT.y
		if button and not InCombatLockdown() then
			button:ClearAllPoints()
			button:SetPoint(db.aspectFrame.point, UIParent, db.aspectFrame.relPoint, db.aspectFrame.x, db.aspectFrame.y)
		end
	end,
})

function ns.HunterAspect_Update()
	UpdateSoon()
end

-- For /tomte hunter aspect: what the button sees.
function ns.HunterAspect_Why()
	local s = Situation()
	local known = {}
	for _, id in ipairs(ns.HUNTER_ASPECT_BEST) do
		known[#known + 1] = ("%s %s"):format(tostring(C_Spell.GetSpellName(id)), s.known[id] and "known" or "not known")
	end
	local cast = ns.Hunter_AspectToCast(s)
	ns.Print(("Aspect: %s. An aspect on: %s. Combat %s, dead %s, resting %s, mounted %s, flying %s. The button: %s."):format(
		table.concat(known, ", "), tostring(s.anyOn), tostring(s.combat), tostring(s.dead), tostring(s.resting),
		tostring(s.mounted), tostring(s.taxi), cast and tostring(C_Spell.GetSpellName(cast)) or "hidden"))
end

function ns.HunterAspect_Start(moduleDB)
	db = moduleDB
	active = true
	for _, event in ipairs(WATCHED) do
		events:Watch(OWNER, event)
	end
	events:Watch(OWNER, "PLAYER_REGEN_DISABLED")
	events:Watch(OWNER, "UNIT_AURA", "player")
	UpdateSoon()
end

function ns.HunterAspect_Stop()
	active = false
	events:UnwatchAll(OWNER)
	if InCombatLockdown() then
		events:Watch(OWNER, "PLAYER_REGEN_ENABLED") -- a secure button can't hide until the fight ends
	else
		Update()
	end
end
