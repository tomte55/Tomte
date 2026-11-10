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
-- nil when there's been none), linger (seconds it stays after a fight) }.
function ns.Meter_Shows(s)
	if not (s.grouped or s.solo) then
		return false
	end
	if s.inCombat then
		return true
	end
	return s.endedAgo ~= nil and s.endedAgo < s.linger
end
