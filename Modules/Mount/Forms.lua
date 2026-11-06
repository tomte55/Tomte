local addonName, ns = ...

-- Smart Mount: the class forms the key can take instead of a mount (druid Travel Form and Cat Form, shaman Ghost
-- Wolf), and whether you're on the move. When to take them is decided in Data.lua (Mount_UseForm); used by Mount.lua.

local CLASS_FORMS = {
	-- Travel Form runs, swims and flies; Cat Form is the druid's way to run indoors. keep: /cast !Cat Form stays in
	-- the form instead of toggling it off.
	DRUID = { travel = 783, indoor = 768, flies = true, keep = true },
	SHAMAN = { travel = 2645, indoor = 2645 }, -- Ghost Wolf, indoors too
}
-- On Forever (wowhead.com/forever) Travel Form and Ghost Wolf are outdoors only and only run; flies stays on because
-- Mount.lua's combat macro reads it as "outdoors only" (its FormFirst ignores it there). Ghost Wolf has a 3 second cast.
local FOREVER_FORMS = {
	DRUID = { travel = 783, indoor = 768, flies = true, keep = true },
	SHAMAN = { travel = 2645, flies = true, castTime = true },
}

local IsSecret = ns.IsSecret

local function Forms()
	return (ns.FOREVER and FOREVER_FORMS or CLASS_FORMS)[UnitClassBase("player")]
end

local function KnownName(spellID)
	if C_SpellBook.IsSpellKnown(spellID) then
		return C_Spell.GetSpellName(spellID)
	end
	return nil
end

-- True for a class with a travel form, whether or not it's learned yet (the settings show its rows).
function ns.MountForms_Class()
	return Forms() ~= nil
end

-- For the Forever settings: Ghost Wolf has no indoor use there, and a cast time.
function ns.MountForms_HasIndoor()
	local f = Forms()
	return f ~= nil and f.indoor ~= nil
end

function ns.MountForms_CastTime()
	local f = Forms()
	return f ~= nil and f.castTime == true
end

-- The travel form's spell name when you know it, and whether it flies.
function ns.MountForms_Travel()
	local f = Forms()
	if not f then
		return nil
	end
	local name = KnownName(f.travel)
	return name, name and f.flies or false
end

-- The form to take indoors, ready for /cast, or nil.
function ns.MountForms_Indoor()
	local f = Forms()
	local name = f and f.indoor and KnownName(f.indoor) -- a Forever shaman has no indoor form
	if name and f.keep then
		return "!" .. name
	end
	return name
end

function ns.MountForms_Moving()
	local speed = GetUnitSpeed("player")
	if IsSecret(speed) then
		return false
	end
	return speed > 0 or IsFalling()
end
