local addonName, ns = ...

-- Pet Health: a pet bar under the character (UnitBar.lua) with a color and warning glow that follow pet
-- health, a "heal below this line" tick and Mend Pet / Exhilaration cooldowns; plus banner reminders when the pet
-- dies, when you pull without one, and when combat ends with it dead. Pure rules in Data.lua. Classes come in
-- through the profiles there (hunters for now).

local PREVIEW_PERIOD = 6 -- seconds for the unlocked preview to sweep 100% -> 5% -> 100%
local COMBAT_END_DELAY = 1
local RED = { 1, 0.3, 0.25 }
local GetSpecialization = C_SpecializationInfo.GetSpecialization
local GetSpecializationInfo = C_SpecializationInfo.GetSpecializationInfo

local module, db, profile, bar
local inCombat = false
local wasDead -- nil until we've seen the pet once this session: no "died" reminder for a pet already dead
local petName -- last readable name, for reminders after the pet is gone
local lastReminder = {}
local previewTime = 0
local spellsDirty = true -- the spell row is rebuilt on the next Update (spellbook or spec changed)

local function IsSecret(v)
	return issecretvalue ~= nil and issecretvalue(v)
end

local function SpecID()
	local index = GetSpecialization()
	return index and GetSpecializationInfo(index) or nil
end

local function PetDead()
	local dead = UnitIsDead("pet")
	return not IsSecret(dead) and dead or false
end

-- Out of combat only (health is secret in combat): pet below full health.
local function PetHurt()
	if inCombat then
		return nil
	end
	local health, max = UnitHealth("pet"), UnitHealthMax("pet")
	if IsSecret(health) or IsSecret(max) then
		return nil
	end
	return health < max
end

-- Locked, and Blizzard's Edit Mode isn't open (it shows the preview too).
local function Locked()
	return db.frame.locked and not ns.EditMode_Active()
end

local function Situation()
	local hasPet = UnitExists("pet")
	return {
		unlocked = not Locked(),
		hasPet = hasPet,
		dead = hasPet and PetDead(),
		hurt = hasPet and PetHurt() or nil,
		wantsPet = ns.PetBar_WantsPet(profile, SpecID(), db.marksman),
		inCombat = inCombat,
		vehicle = UnitHasVehicleUI("player"),
		petBattle = C_PetBattles.IsInBattle(),
		mounted = IsMounted(),
		onTaxi = UnitOnTaxi("player"),
		playerDead = UnitIsDeadOrGhost("player"),
	}
end

local function ReadName()
	local name = UnitName("pet")
	if name and not IsSecret(name) then
		petName = name
	end
	return name
end

local function SpellName(spellID)
	return C_Spell.GetSpellName(spellID) or ""
end

local function Remind(trigger, s)
	local enabled = { died = db.remind.died, combatStart = db.remind.pull, combatEnd = db.remind.after }
	if not enabled[trigger] then
		return
	end
	local key = ns.PetBar_Reminder(trigger, s)
	if not key or not ns.PetBar_Throttle(lastReminder, key, GetTime()) then
		return
	end
	local name = petName or "Your pet"
	local spec
	if key == "dead" then
		spec = {
			title = trigger == "died" and (name .. " died") or (name .. " is dead"),
			subtitle = SpellName(profile.revive),
			icon = C_Spell.GetSpellTexture(profile.revive),
		}
	else
		spec = { title = "No pet", subtitle = SpellName(profile.call), icon = C_Spell.GetSpellTexture(profile.call) }
	end
	spec.owner, spec.label, spec.accent, spec.hold = "pet", "Pet", RED, 3
	ns.Banner_Show(spec)
	if db.sound then
		PlaySound(SOUNDKIT.RAID_WARNING, "Master")
	end
end

local function SavePosition(point, relPoint, x, y)
	local pos = db.frame
	pos.point, pos.relPoint, pos.x, pos.y = point, relPoint, x, y
end

-- The profile's spells this character has (talents, level).
local function KnownSpells()
	local known = {}
	for _, spell in ipairs(profile.spells) do
		if C_SpellBook.IsSpellKnown(spell.id) then
			known[#known + 1] = spell
		end
	end
	return known
end

local function ApplyLayout()
	bar:ClearAllPoints()
	bar:SetPoint(db.frame.point, UIParent, db.frame.relPoint, db.frame.x, db.frame.y)
	bar:SetScale(db.scale)
	bar:SetThreshold(db.threshold / 100)
	bar:SetShowPercent(db.showPercent)
	bar:SetLocked(db.frame.locked)
end

local function ShowPreview()
	local p = (previewTime % PREVIEW_PERIOD) / PREVIEW_PERIOD -- 0..1
	local fraction = 0.05 + 0.95 * math.abs(1 - 2 * p)
	bar:ShowFake(petName or "Pet", fraction)
end

local function Update()
	if not module.active then
		return
	end
	local s = Situation()
	if s.hasPet then
		ReadName()
	end

	-- Pet died (UnitIsDead isn't secret). The first look this session only sets the baseline.
	if s.hasPet then
		if s.dead and wasDead == false then
			Remind("died", s)
		end
		wasDead = s.dead
	end

	if not ns.PetBar_Visible(db.visibility, s) then
		if bar then
			bar:Hide()
		end
		return
	end
	if not bar then
		bar = ns.UnitBar_Create(SavePosition)
		ApplyLayout()
	end
	if spellsDirty then
		spellsDirty = false
		bar:SetSpells(KnownSpells())
	end
	if s.unlocked and not inCombat then
		ShowPreview()
	elseif s.dead then
		bar:ShowDead(ReadName(), "DEAD")
	elseif s.hasPet then
		bar:ShowUnit("pet")
		bar:RefreshBuff("pet")
	else
		bar:ShowMissing("NO PET")
	end
	bar:Show()
end

-- The unlocked preview sweeps the fake health so the colors, tick and glow can be seen.
local previewDriver = CreateFrame("Frame")
previewDriver:Hide()
previewDriver:SetScript("OnUpdate", function(self, dt)
	previewTime = previewTime + dt
	if bar and bar:IsShown() and not inCombat then
		ShowPreview()
	end
end)

local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(self, event, ...)
	self[event](self, ...)
end)

local UNIT_EVENTS = { "UNIT_HEALTH", "UNIT_MAXHEALTH", "UNIT_FLAGS" }
local EVENTS = {
	"PLAYER_ENTERING_WORLD", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED",
	"SPELL_UPDATE_COOLDOWN", "PLAYER_SPECIALIZATION_CHANGED", "UNIT_ENTERED_VEHICLE", "UNIT_EXITED_VEHICLE",
	"PET_BATTLE_OPENING_START", "PET_BATTLE_CLOSE", "PLAYER_DEAD", "PLAYER_ALIVE", "PLAYER_UNGHOST",
	"PLAYER_MOUNT_DISPLAY_CHANGED", "SPELLS_CHANGED",
}

-- Health ticks: when the bar already shows the live pet and health can't change whether it shows (in combat,
-- or "Always with a pet"), only the bar moves. A death, or a change that may show or hide it, takes Update.
local function HealthChanged()
	if not module.active then
		return
	end
	if bar and bar:IsShown() and not bar.state and Locked() and UnitExists("pet") and not PetDead()
		and (inCombat or db.visibility == "always") then
		bar:ShowUnit("pet")
		return
	end
	Update()
end

local function SpellsChanged()
	spellsDirty = true
	Update()
end

events.UNIT_HEALTH = HealthChanged
events.UNIT_MAXHEALTH = HealthChanged
events.UNIT_FLAGS = Update
events.UNIT_PET = Update
events.SPELLS_CHANGED = SpellsChanged
events.PLAYER_SPECIALIZATION_CHANGED = SpellsChanged
events.UNIT_ENTERED_VEHICLE = Update
events.UNIT_EXITED_VEHICLE = Update
events.PET_BATTLE_OPENING_START = Update
events.PET_BATTLE_CLOSE = Update
events.PLAYER_DEAD = Update
events.PLAYER_ALIVE = Update
events.PLAYER_UNGHOST = Update
events.PLAYER_MOUNT_DISPLAY_CHANGED = Update

function events:PLAYER_ENTERING_WORLD()
	inCombat = InCombatLockdown()
	spellsDirty = true
	Update()
end

function events:UNIT_AURA()
	if bar and bar:IsShown() and UnitExists("pet") and (Locked() or inCombat) then
		bar:RefreshBuff("pet")
	end
end

function events:SPELL_UPDATE_COOLDOWN()
	if bar and bar:IsShown() then
		bar:RefreshCooldown()
	end
end

function events:PLAYER_REGEN_DISABLED()
	inCombat = true
	Update()
	Remind("combatStart", Situation())
end

function events:PLAYER_REGEN_ENABLED()
	inCombat = false
	Update()
	C_Timer.After(COMBAT_END_DELAY, function()
		if module.active and not inCombat then
			Remind("combatEnd", Situation())
		end
	end)
end

local function Start()
	for _, event in ipairs(EVENTS) do
		events:RegisterEvent(event)
	end
	for _, event in ipairs(UNIT_EVENTS) do
		events:RegisterUnitEvent(event, "pet")
	end
	events:RegisterUnitEvent("UNIT_AURA", "pet")
	events:RegisterUnitEvent("UNIT_PET", "player") -- not every raid member's pet
	previewDriver:SetShown(not Locked())
	if ns.inWorld then
		events:PLAYER_ENTERING_WORLD()
	end
end

local function Stop()
	events:UnregisterAllEvents()
	previewDriver:Hide()
	if bar then
		bar:Hide()
	end
	ns.Banner_Clear("pet")
end

local function SetLocked(locked)
	db.frame.locked = locked
	previewDriver:SetShown(module.active and not Locked() or false)
	if bar then
		bar:SetLocked(locked)
	end
	Update()
end

ns.EditMode_Register({
	name = "Pet Health",
	frame = function()
		return bar
	end,
	refresh = function()
		if module.active then
			previewDriver:SetShown(not Locked())
			Update()
		end
	end,
	saved = function()
		local point, _, relPoint, x, y = bar:GetPoint()
		SavePosition(point, relPoint, x, y)
	end,
})

local function Relayout()
	if bar then
		ApplyLayout()
	end
	Update()
end

local function ResetPosition()
	db.frame.point, db.frame.relPoint, db.frame.x, db.frame.y = "CENTER", "CENTER", 0, -170
	Relayout()
end

local VISIBILITY = {
	{ value = "combat", text = "In combat, or hurt" },
	{ value = "always", text = "Always with a pet" },
}

local function Percent(v)
	return ("%d%%"):format(v)
end

local function Scale(v)
	return ("%.1f"):format(v)
end

local function Command(fn)
	return function()
		if not module.active then
			ns.Print("Pet Health is off.")
			return
		end
		fn()
	end
end

module = ns.RegisterModule({
	key = "pet",
	name = "Pet Health",
	category = "Combat",
	description = "A pet health bar under your character that turns red and glows when your pet needs healing, with Mend Pet and Exhilaration cooldowns, and reminders when your pet dies or you pull without one.",
	enabledByDefault = true,
	defaults = {
		frame = { point = "CENTER", relPoint = "CENTER", x = 0, y = -170, locked = true },
		scale = 1,
		threshold = 40, -- percent
		showPercent = true,
		visibility = "combat",
		marksman = false,
		remind = { died = true, pull = true, after = true },
		sound = true,
	},
	init = function(moduleDB)
		db = moduleDB
		local _, class = UnitClass("player")
		profile = ns.PetBar_Profile(class)
	end,
	blocked = function()
		if not profile then
			return "No pet profile for your class yet."
		end
	end,
	toggle = function(active)
		if active then
			Start()
		else
			Stop()
		end
	end,
	commands = {
		{ "unlock", "move the pet bar (shows a preview)", Command(function()
			SetLocked(false)
			ns.Print("drag the pet bar, then /tomte pet lock.")
		end) },
		{ "lock", "lock the pet bar", Command(function()
			SetLocked(true)
			ns.Print("pet bar locked.")
		end) },
		{ "reset", "move the pet bar back under your character", Command(ResetPosition) },
	},
	options = {
		{ type = "header", label = "Bar" },
		{ type = "checkbox", key = "frame.locked", label = "Lock pet bar", onChange = SetLocked,
			tooltip = "Unlock to drag the bar. While unlocked it shows a preview that sweeps through the colors and the warning glow. Blizzard's Edit Mode moves it too." },
		{ type = "dropdown", key = "visibility", label = "Show", choices = function()
			return VISIBILITY
		end, onChange = Update,
			tooltip = "A dead pet, or no pet in combat, always shows." },
		{ type = "slider", key = "threshold", label = "Warning below", min = 20, max = 70, step = 5,
			format = Percent, onChange = Relayout,
			tooltip = "Below this the bar turns red and glows. The gold tick on the bar marks it: a good time for Mend Pet." },
		{ type = "slider", key = "scale", label = "Size", min = 0.6, max = 1.6, step = 0.1, format = Scale,
			onChange = Relayout },
		{ type = "checkbox", key = "showPercent", label = "Show percent", onChange = Relayout },
		{ type = "button", label = "Position", text = "Reset", onClick = Command(ResetPosition),
			tooltip = "Move the bar back under your character." },

		{ type = "header", label = "Reminders" },
		{ type = "checkbox", key = "remind.died", label = "When your pet dies" },
		{ type = "checkbox", key = "remind.pull", label = "When you pull without a pet" },
		{ type = "checkbox", key = "remind.after", label = "After combat if it's dead" },
		{ type = "checkbox", key = "sound", label = "Warning sound" },
		{ type = "checkbox", key = "marksman", label = "Marksmanship uses a pet", onChange = Update,
			tooltip = "Remind a Marksmanship hunter about the pet too." },
	},
})
