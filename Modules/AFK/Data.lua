local addonName, ns = ...

-- AFK module, pure logic: no WoW API calls (unit-tested with plain Lua).

local EPSILON = 1e-6 -- level + fraction sums aren't exact in floating point

function ns.AFK_ClockText(hour, minute, military)
	if military then
		return ("%02d:%02d"):format(hour, minute)
	end
	local suffix = hour < 12 and "AM" or "PM"
	local h = hour % 12
	if h == 0 then
		h = 12
	end
	return ("%d:%02d %s"):format(h, minute, suffix)
end

-- Progress since the session start, from level + fraction of the level (xp / xpMax). nil when none.
function ns.AFK_XPGain(startLevel, startFraction, level, fraction)
	local delta = (level + fraction) - (startLevel + startFraction)
	if delta <= EPSILON then
		return nil
	end
	if delta < 1 - EPSILON then
		return ("+%d%% of a level"):format(math.floor(delta * 100 + EPSILON))
	end
	return ("+%.1f levels"):format(delta)
end

-- Appends a whisper; past max the oldest is dropped (list.dropped counts them).
function ns.AFK_AddWhisper(list, entry, max)
	list[#list + 1] = entry
	while #list > max do
		table.remove(list, 1)
		list.dropped = (list.dropped or 0) + 1
	end
end

-- The newest n whispers, oldest first, and how many whispers in total aren't among them.
function ns.AFK_VisibleWhispers(list, n)
	local first = math.max(#list - n + 1, 1)
	local shown = {}
	for i = first, #list do
		shown[#shown + 1] = list[i]
	end
	return shown, (first - 1) + (list.dropped or 0)
end
