local addonName, ns = ...

-- Alts, recipes you can learn now: pure logic (no WoW API calls; unit-tested in tests/test_alts_learn.lua). Which
-- recipe items stopped saying in red that you can't learn them, and the toast's words. Read and toasted in
-- Learnable.lua.

local MAX_LINES = 4 -- recipes named in a toast for several; the rest are "and n more"
local WHERE = { bags = "In your bags.", bank = "In your bank.", warband = "In the Warband bank." }
local WHERE_SHORT = { bags = "bags", bank = "bank", warband = "Warband bank" }

-- The recipes you can learn now that you couldn't, or didn't hold, before: red before and not now (a skill-up or a
-- level), or new since (looted, bought, taken from the mail). before, now: [key] = red (true | false); seen: [key] =
-- true for every key held before now, read or not (a recipe whose data hadn't loaded at the first read isn't new).
-- Returns the keys, sorted.
function ns.Alts_NewlyLearnable(before, now, seen)
	local keys = {}
	for key, red in pairs(now) do
		if red == false and (before[key] == true or not seen[key]) then
			keys[#keys + 1] = key
		end
	end
	table.sort(keys)
	return keys
end

-- The toast's title and text. entries: { { name, where = "bags" | "bank" | "warband" } } in order.
function ns.Alts_LearnToast(entries)
	if #entries == 1 then
		return entries[1].name, "You can learn it now. " .. (WHERE[entries[1].where] or "")
	end
	local lines = {}
	for i = 1, math.min(#entries, MAX_LINES) do
		local e = entries[i]
		lines[i] = ("%s (%s)"):format(e.name, WHERE_SHORT[e.where] or e.where)
	end
	if #entries > MAX_LINES then
		lines[#lines + 1] = ("and %d more"):format(#entries - MAX_LINES)
	end
	return ("%d recipes you can learn now"):format(#entries), table.concat(lines, "\n")
end
