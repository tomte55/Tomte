local addonName, ns = ...

-- DPS meter: pure logic (no WoW API calls; unit-tested in tests/test_meter.lua). Which places of the game's ranking show
-- and when the meter is up. The ranking itself is the game's (C_DamageMeter lists sources best first); its amounts are
-- secret in combat, so nothing here compares or sums them. Read in Read.lua, drawn by Window.lua, wired in Meter.lua.

-- The places to show: the top `lines`, and yours below them when you're further down. count: sources in the
-- ranking; mine: your place in it, or nil. Returns { place, ... } in order.
function ns.Meter_Rows(count, mine, lines)
	local rows = {}
	for place = 1, math.min(count, lines) do
		rows[#rows + 1] = place
	end
	if mine and mine > lines and mine <= count then
		rows[#rows + 1] = mine
	end
	return rows
end

-- Whether the meter shows. s: { grouped, solo (the setting), inCombat, endedAgo (seconds since your last fight ended,
-- nil when there's been none), linger (seconds it stays after a fight), instancesOnly (the setting), inInstance }.
function ns.Meter_Shows(s)
	if not (s.grouped or s.solo) then
		return false
	end
	if s.instancesOnly and not s.inInstance then
		return false
	end
	if s.inCombat then
		return true
	end
	return s.endedAgo ~= nil and s.endedAgo < s.linger
end

-- The numbers on a line for the "number" setting ("rate" | "total" | "both"): the right-hand one, and the dimmer one
-- left of it (nil for none). Each is a field of a ranking source ("perSecond" | "total").
function ns.Meter_Numbers(number)
	if number == "total" then
		return "total", nil
	elseif number == "both" then
		return "perSecond", "total"
	end
	return "perSecond", nil
end

-- Whether a saved spot keeps the edge the meter grows from: growing up keeps its bottom edge in place, growing down
-- its top. point: { point, relPoint, x, y }; nil (the default spot) always fits, as each direction has its own.
function ns.Meter_PointFits(point, grow)
	if not point then
		return true
	end
	local top = point[1]:find("^TOP") ~= nil
	return top == (grow ~= "up")
end
