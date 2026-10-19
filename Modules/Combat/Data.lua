local addonName, ns = ...

-- Pet Health pure logic (unit-tested with plain Lua): class profiles, when the bar shows, which reminder to
-- give, and the point lists for the color and warning curves. Curve input is the unit's health as 0..1.

-- One entry per class that has a combat pet. spells: the icon row under the bar ({ id, buff = true } times the
-- buff on the pet), filtered to known spells at run time. revive / call: the spells a "dead" / "no pet" reminder
-- names (see ns.PetBar_SummonSpell). wantsPet: [specID] = true (always) or "option" (only with the "Marksmanship
-- uses a pet" style setting on). specs: when set, the bar and reminders are for these specs only. sacrifice: a
-- player aura that means the pet was given up on purpose.
-- Warlock demons in the order a reminder names them before any summon this session: Felguard (Demonology), then
-- the ones every spec has.
local DEMONS = { 30146, 691, 697, 366222, 688 } -- Felguard, Felhunter, Voidwalker, Sayaad, Imp
local PROFILES = {
	HUNTER = {
		unit = "pet",
		-- Icons under the bar: Mend Pet (its buff on the pet is timed too) and Exhilaration (heals the pet fully).
		spells = { { id = 136, buff = true }, { id = 109304 } },
		revive = { 982 }, -- Revive Pet
		call = { 883 }, -- Call Pet 1
		wantsPet = { [253] = true, [255] = true, [254] = "option" },
	},
	-- Untested in game (2026-10-19): the author has no warlock. Health Funnel (755) was removed in 12.0.0, so the
	-- row has no heal, only Fel Domination's cooldown.
	WARLOCK = {
		unit = "pet",
		spells = { { id = 333889 } }, -- Fel Domination
		revive = DEMONS,
		call = DEMONS,
		wantsPet = { [265] = true, [266] = true, [267] = true },
		sacrifice = 196099, -- Grimoire of Sacrifice's buff on the warlock
	},
	-- Untested in game (2026-10-19): the author has no death knight. Unholy only: the other specs' Raise Dead
	-- (46585) is a temporary ghoul.
	DEATHKNIGHT = {
		unit = "pet",
		spells = { { id = 63560, buff = true } }, -- Dark Transformation, its buff on the ghoul timed
		revive = { 46584 }, -- Raise Dead (Unholy's permanent ghoul)
		call = { 46584 },
		wantsPet = { [252] = true },
		specs = { [252] = true },
	},
}

local THROTTLE = 10 -- seconds between two of the same reminder

-- Health colors (green full, orange hurt, red low), as Blizzard's own health bars read: game meaning, not theme.
local GREEN = { 0.25, 0.85, 0.3 } -- theme: health color (game meaning)
local ORANGE = { 1, 0.7, 0.2 } -- theme: health color (game meaning)
local RED = { 1, 0.2, 0.15 } -- theme: health color (game meaning)

function ns.PetBar_Profile(class)
	return class and PROFILES[class] or nil
end

-- Whether the bar and reminders apply to this spec. A profile without specs covers every spec; with specs, an
-- unknown spec (not loaded yet) doesn't pass.
function ns.PetBar_ForSpec(profile, specID)
	if not profile.specs then
		return true
	end
	return specID ~= nil and profile.specs[specID] == true
end

-- sacrificed: the profile's sacrifice aura is on (the pet was given up on purpose).
function ns.PetBar_WantsPet(profile, specID, optionOn, sacrificed)
	if sacrificed then
		return false
	end
	local want = specID and profile.wantsPet[specID]
	return want == true or (want == "option" and optionOn == true)
end

-- The spell a reminder names from list: the summon cast last when it's in the list and known, else the first known
-- one, else the first. isKnown(spellID) -> bool.
function ns.PetBar_SummonSpell(list, last, isKnown)
	if last then
		for _, id in ipairs(list) do
			if id == last and isKnown(id) then
				return id
			end
		end
	end
	for _, id in ipairs(list) do
		if isKnown(id) then
			return id
		end
	end
	return list[1]
end

-- Whether spellID is one of the profile's revive or call spells (remembered as the last summon).
function ns.PetBar_IsSummon(profile, spellID)
	for _, list in ipairs({ profile.revive, profile.call }) do
		for _, id in ipairs(list) do
			if id == spellID then
				return true
			end
		end
	end
	return false
end

-- Whether some spec of the profile only wants a pet with the option on (the settings row shows then).
function ns.PetBar_HasOption(profile)
	for _, want in pairs(profile.wantsPet) do
		if want == "option" then
			return true
		end
	end
	return false
end

-- s: { unlocked, offSpec, vehicle, petBattle, hasPet, dead, wantsPet, inCombat, hurt }. mode: "always" | "combat".
-- hurt is only known out of combat (health is secret in combat), nil otherwise.
function ns.PetBar_Visible(mode, s)
	if s.unlocked then
		return true
	end
	if s.offSpec then
		return false
	end
	if s.vehicle or s.petBattle then
		return false
	end
	if s.dead then
		return true
	end
	if not s.hasPet then
		return s.inCombat and s.wantsPet or false
	end
	return mode == "always" or s.inCombat or s.hurt == true
end

-- trigger: "died" | "combatStart" | "combatEnd". Returns "dead", "missing" or nil.
function ns.PetBar_Reminder(trigger, s)
	if not s.wantsPet or s.mounted or s.onTaxi or s.vehicle or s.petBattle or s.playerDead then
		return nil
	end
	if s.dead then
		return "dead"
	end
	if trigger ~= "died" and not s.hasPet then
		return "missing"
	end
	return nil
end

-- true (and remembers now) when this reminder hasn't fired in the last THROTTLE seconds.
function ns.PetBar_Throttle(last, key, now)
	if last[key] and now - last[key] < THROTTLE then
		return false
	end
	last[key] = now
	return true
end

-- Warning glow alpha: 0 at and above the threshold, 0.45 just under it, 1 from half the threshold down.
function ns.PetBar_AlphaPoints(threshold)
	return {
		{ 0, 1 },
		{ threshold * 0.5, 1 },
		{ threshold - 0.005, 0.45 },
		{ threshold, 0 },
		{ 1, 0 },
	}
end

-- Bar color: { x, r, g, b }. Red up to half the threshold, orange at it, green from 15 % above it.
function ns.PetBar_ColorPoints(threshold)
	local points = {
		{ 0, RED },
		{ threshold * 0.5, RED },
		{ threshold, ORANGE },
		{ math.min(threshold + 0.15, 0.99), GREEN },
		{ 1, GREEN },
	}
	local out = {}
	for _, p in ipairs(points) do
		if #out == 0 or p[1] > out[#out][1] then
			out[#out + 1] = { p[1], p[2][1], p[2][2], p[2][3] }
		end
	end
	return out
end
