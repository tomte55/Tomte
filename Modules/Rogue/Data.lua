local addonName, ns = ...

-- Rogue Poisons: pure logic (no WoW API calls; unit-tested with plain Lua). Which poisons a rogue should have on,
-- and which ones to offer when one is missing or about to run out.

-- Poison spell IDs (the weapon buff on the player has the same ID). Lethal ones in the order they're offered
-- when you haven't picked one yet; Assassination prefers Deadly Poison, the other specs Instant Poison.
ns.ROGUE_LETHAL = { 2823, 315584, 8679, 381664 } -- Deadly, Instant, Wound, Amplifying
ns.ROGUE_NONLETHAL = { 3408, 381637, 5761 } -- Crippling, Atrophic, Numbing
ns.ROGUE_DRAGON_TEMPERED_BLADES = 381801 -- talent: two lethal and two non-lethal poisons at once
local DEADLY, INSTANT = 2823, 315584
local SPEC_ASSASSINATION = 259

local KIND = {}
for _, id in ipairs(ns.ROGUE_LETHAL) do
	KIND[id] = "lethal"
end
for _, id in ipairs(ns.ROGUE_NONLETHAL) do
	KIND[id] = "nonLethal"
end

-- "lethal", "nonLethal" or nil.
function ns.Rogue_PoisonKind(spellID)
	return KIND[spellID]
end

-- Order to offer poisons of one kind in: what this character applied last first, then the default order.
local function Order(kind, specID, last)
	local order, seen = {}, {}
	local function add(id)
		if id and KIND[id] == kind and not seen[id] then
			seen[id] = true
			order[#order + 1] = id
		end
	end
	for _, id in ipairs(last or {}) do
		add(id)
	end
	if kind == "lethal" then
		if specID == SPEC_ASSASSINATION then
			add(DEADLY)
		else
			add(INSTANT)
		end
		for _, id in ipairs(ns.ROGUE_LETHAL) do
			add(id)
		end
	else
		for _, id in ipairs(ns.ROGUE_NONLETHAL) do
			add(id)
		end
	end
	return order
end

-- Remembers the poison just applied at the front of its kind's list (kept to 4 entries).
function ns.Rogue_RememberPoison(last, spellID)
	if not KIND[spellID] then
		return last
	end
	last = last or {}
	for i = #last, 1, -1 do
		if last[i] == spellID then
			table.remove(last, i)
		end
	end
	table.insert(last, 1, spellID)
	while #last > 4 do
		table.remove(last)
	end
	return last
end

-- What's wrong with the poisons. s = {
--   known = { [spellID] = true }, the poisons this character can cast
--   active = { [spellID] = seconds left (math.huge when unknown) }, the poisons on the weapons
--   twoEach = Dragon-Tempered Blades (two of each kind),
--   specID, last = { lethal = { ids }, nonLethal = { ids } } (newest first),
-- }
-- rules = { lethal = bool, nonLethal = bool, lowSeconds = number }.
-- Returns a list of { spellID, kind, reason = "missing" | "low", left = seconds (low only) }: lethal first, low
-- ones before missing ones within a kind.
function ns.Rogue_PoisonProblems(s, rules)
	local problems = {}
	for _, kind in ipairs({ "lethal", "nonLethal" }) do
		if rules[kind] then
			local want = s.twoEach and 2 or 1
			local order = Order(kind, s.specID, s.last and s.last[kind])
			local on, missing = 0, {}
			for _, id in ipairs(order) do
				local left = s.active[id]
				if left then
					on = on + 1
					if left < rules.lowSeconds then
						problems[#problems + 1] = { spellID = id, kind = kind, reason = "low", left = left }
					end
				end
			end
			for _, id in ipairs(order) do
				if on + #missing >= want then
					break
				end
				if s.known[id] and not s.active[id] then
					missing[#missing + 1] = { spellID = id, kind = kind, reason = "missing" }
				end
			end
			for _, p in ipairs(missing) do
				problems[#problems + 1] = p
			end
		end
	end
	return problems
end

-- "42 min", "3 min", "45 sec".
function ns.Rogue_FormatLeft(seconds)
	if seconds >= 60 then
		return math.floor(seconds / 60) .. " min"
	end
	return math.max(0, math.floor(seconds)) .. " sec"
end
