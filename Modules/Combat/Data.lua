local addonName, ns = ...

-- Pet Health pure logic (unit-tested with plain Lua): class profiles, when the bar shows, which reminder to
-- give, and the point lists for the color and warning curves. Curve input is the unit's health as 0..1.

-- One entry per class that has a combat pet. wantsPet: [specID] = true (always) or "option" (only with the
-- "Marksmanship uses a pet" style setting on).
local PROFILES = {
	HUNTER = {
		unit = "pet",
		-- Icons under the bar: Mend Pet (its buff on the pet is timed too) and Exhilaration (heals the pet fully).
		spells = { { id = 136, buff = true }, { id = 109304 } },
		revive = 982, -- Revive Pet
		call = 883, -- Call Pet 1
		wantsPet = { [253] = true, [255] = true, [254] = "option" },
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

function ns.PetBar_WantsPet(profile, specID, optionOn)
	local want = specID and profile.wantsPet[specID]
	return want == true or (want == "option" and optionOn == true)
end

-- s: { unlocked, vehicle, petBattle, hasPet, dead, wantsPet, inCombat, hurt }. mode: "always" | "combat".
-- hurt is only known out of combat (health is secret in combat), nil otherwise.
function ns.PetBar_Visible(mode, s)
	if s.unlocked then
		return true
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
