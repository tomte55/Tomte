local addonName, ns = ...

-- Alts: the roster, gold, weekly status and profession text (pure logic, tested with plain Lua). The saved-data layout
-- is described in PlanData.lua; gear is in GearData.lua.

local floor, max = math.floor, math.max

-- Roster ------------------------------------------------------------------------------------------------------

-- Money text lives in Core/Format.lua; these names stay for the callers.
ns.Alts_Gold = ns.Gold
ns.Alts_Price = ns.Price

-- "now" / "5 min" / "3 h" / "2 days" / "3 weeks"
function ns.Alts_Ago(seconds)
	seconds = max(seconds or 0, 0)
	if seconds < 120 then
		return "now"
	elseif seconds < 3600 then
		return floor(seconds / 60) .. " min"
	elseif seconds < 2 * 86400 then
		return floor(seconds / 3600) .. " h"
	elseif seconds < 14 * 86400 then
		return floor(seconds / 86400) .. " days"
	end
	return floor(seconds / (7 * 86400)) .. " weeks"
end

ns.ALTS_SORTS = {
	{ key = "level", text = "Level" },
	{ key = "name", text = "Name" },
	{ key = "ilvl", text = "Item level" },
	{ key = "gold", text = "Gold" },
	{ key = "seen", text = "Last played" },
}

-- Characters in roster order: current character first, then by the sort key (high first; names A-Z).
function ns.Alts_Roster(chars, sortKey, currentGuid)
	local list = {}
	for guid, c in pairs(chars) do
		if guid ~= currentGuid then
			list[#list + 1] = c
		end
	end
	local field = ({ level = "level", ilvl = "ilvl", gold = "money", seen = "seen" })[sortKey]
	table.sort(list, function(a, b)
		if field then
			local x, y = a[field] or 0, b[field] or 0
			if x ~= y then
				return x > y
			end
		end
		return (a.name or "") < (b.name or "")
	end)
	if currentGuid and chars[currentGuid] then
		table.insert(list, 1, chars[currentGuid])
	end
	return list
end

-- Every character's gold, plus the Warband bank's when it's known (copper, optional).
function ns.Alts_TotalGold(chars, warband)
	local total = warband or 0
	for _, c in pairs(chars) do
		total = total + (c.money or 0)
	end
	return total
end

-- " (Warband 300,000g)" after a total, "" when the Warband bank is empty or was never read.
function ns.Alts_WarbandText(warband)
	if not warband or warband < 10000 then
		return ""
	end
	return (" (Warband %s)"):format(ns.Alts_Gold(warband))
end

-- The eleven main professions (base skill lines) in name order, with a stand-in icon.
ns.ALTS_PROFESSIONS = {
	{ 171, "Alchemy", "Interface\\Icons\\Trade_Alchemy" },
	{ 164, "Blacksmithing", "Interface\\Icons\\Trade_BlackSmithing" },
	{ 333, "Enchanting", "Interface\\Icons\\Trade_Engraving" },
	{ 202, "Engineering", "Interface\\Icons\\Trade_Engineering" },
	{ 182, "Herbalism", "Interface\\Icons\\Trade_Herbalism" },
	{ 773, "Inscription", "Interface\\Icons\\INV_Inscription_Tradeskill01" },
	{ 755, "Jewelcrafting", "Interface\\Icons\\INV_Misc_Gem_01" },
	{ 165, "Leatherworking", "Interface\\Icons\\Trade_LeatherWorking" },
	{ 186, "Mining", "Interface\\Icons\\Trade_Mining" },
	{ 393, "Skinning", "Interface\\Icons\\INV_Misc_Pelt_Wolf_01" },
	{ 197, "Tailoring", "Interface\\Icons\\Trade_Tailoring" },
}

-- Names of the main professions none of the characters has, in name order.
function ns.Alts_Uncovered(chars)
	local list = {}
	for _, p in ipairs(ns.ALTS_PROFESSIONS) do
		local has = false
		for _, c in pairs(chars) do
			if c.profs and c.profs[p[1]] then
				has = true
			end
		end
		if not has then
			list[#list + 1] = p[2]
		end
	end
	return list
end

-- Characters with a free main profession slot (fewer than two), highest level first (so max level first), then
-- by name.
function ns.Alts_FreeSlots(chars)
	local list = {}
	for _, c in pairs(chars) do
		if #ns.Alts_Profs(c) < 2 then
			list[#list + 1] = c
		end
	end
	table.sort(list, function(a, b)
		if (a.level or 0) ~= (b.level or 0) then
			return (a.level or 0) > (b.level or 0)
		end
		return (a.name or "") < (b.name or "")
	end)
	return list
end

-- "Nobody has Inscription. Free profession slot: Tomtis (lvl 80), Mira (lvl 34)." for one or more missing
-- professions ("Inscription or Skinning"); at most 4 names, then "+n".
function ns.Alts_GapText(missing, free)
	local what = #missing > 1 and (table.concat(missing, ", ", 1, #missing - 1) .. " or " .. missing[#missing])
		or (missing[1] or "?")
	if #free == 0 then
		return ("Nobody has %s, and every character has two professions."):format(what)
	end
	local names = {}
	for i, c in ipairs(free) do
		if i > 4 then
			names[#names + 1] = "+" .. (#free - 4)
			break
		end
		names[#names + 1] = ("%s (lvl %d)"):format(c.name or "?", c.level or 0)
	end
	return ("Nobody has %s. Free profession slot: %s."):format(what, table.concat(names, ", "))
end

-- "6h" / "2d 3h" / "25m"
local function Until(seconds)
	seconds = max(floor(seconds), 0)
	local d, h = floor(seconds / 86400), floor(seconds % 86400 / 3600)
	if d > 0 then
		return ("%dd %dh"):format(d, h)
	elseif h > 0 then
		return h .. "h"
	end
	return max(floor(seconds / 60), 1) .. "m"
end

-- Great Vault and Concentration of a character, from Weekly's view of it (ns.Weekly_View at `now`):
-- { vault = "Vault 4/9" | "Vault rewards waiting" | nil,
--   conc = { { name, qty, max, full, text = "full" | "full in 6h" | "" } } (by name) }, nil when there's neither.
function ns.Alts_WeeklyStatus(view, now)
	if not view then
		return nil
	end
	local status = { conc = {} }
	if view.vaultReady then
		status.vault = "Vault rewards waiting"
	else
		local unlocked, total = 0, 0
		for _, slots in pairs(view.vault or {}) do
			for _, s in ipairs(slots) do
				total = total + 1
				if (s.progress or 0) >= (s.threshold or 1) then
					unlocked = unlocked + 1
				end
			end
		end
		if total > 0 then
			status.vault = ("Vault %d/%d"):format(unlocked, total)
		end
	end
	for _, p in pairs(view.profs or {}) do
		local conc = p.conc
		if conc and conc.qty and (conc.max or 0) > 0 then
			local text = ""
			if conc.full then
				text = "full"
			elseif conc.fullAt and conc.fullAt > now then
				text = "full in " .. Until(conc.fullAt - now)
			end
			status.conc[#status.conc + 1] = { name = p.name or "?", qty = conc.qty, max = conc.max, full = conc.full == true,
				text = text }
		end
	end
	table.sort(status.conc, function(a, b)
		return a.name < b.name
	end)
	if not status.vault and #status.conc == 0 then
		return nil
	end
	return status
end

-- "Vault 4/9 · Concentration: Blacksmithing full, Alchemy full in 6h" (a full one highlighted), "" for nil.
-- fullHex: "ffrrggbb" for the highlight; the UI passes the theme's (this file has no theme in the unit tests).
function ns.Alts_WeeklyLine(status, fullHex)
	if not status then
		return ""
	end
	local parts = {}
	if status.vault then
		parts[1] = status.vault
	end
	local concs = {}
	for _, c in ipairs(status.conc) do
		local text = c.text ~= "" and (c.name .. " " .. c.text) or ("%s %d/%d"):format(c.name, c.qty, c.max)
		concs[#concs + 1] = c.full and ("|c%s%s|r"):format(fullHex or "ffffd100", text) or text -- theme: the UI passes fullHex
	end
	if #concs > 0 then
		parts[#parts + 1] = "Concentration: " .. table.concat(concs, ", ")
	end
	return table.concat(parts, " · ")
end

-- A character's main professions by name (secondary=true: archaeology, fishing and cooking instead). { prof }.
function ns.Alts_Profs(c, secondary)
	local list = {}
	for _, prof in pairs(c.profs or {}) do
		if (prof.secondary == true) == (secondary == true) then
			list[#list + 1] = prof
		end
	end
	table.sort(list, function(a, b)
		return (a.name or "") < (b.name or "")
	end)
	return list
end

-- "Secondary: Cooking 52/100, Fishing 20/100" for tooltips, nil when there are none.
function ns.Alts_SecondaryText(c)
	local parts = {}
	for _, prof in ipairs(ns.Alts_Profs(c, true)) do
		parts[#parts + 1] = ns.Alts_ProfText(prof)
	end
	return #parts > 0 and ("Secondary: " .. table.concat(parts, ", ")) or nil
end

-- "Blacksmithing 72/100" (short = "Blac 72"); unspent knowledge is drawn separately.
function ns.Alts_ProfText(prof, short)
	local name = prof.name or "?"
	if short then
		name = name:sub(1, 4)
	end
	if prof.skill and prof.max and prof.max > 0 then
		return short and ("%s %d"):format(name, prof.skill) or ("%s %d/%d"):format(name, prof.skill, prof.max)
	end
	return name
end
