local addonName, ns = ...

-- Material uses: pure logic (no WoW API calls; unit-tested in tests/test_materials.lua). Turns what Alts knows (which
-- characters' recipes use an item) and the generated table (which professions use it) into tooltip lines.
-- The tooltip hook is in Materials.lua; the table is Generated.lua (tools/materials.py).

local SHORT_NAMES = 2 -- characters named on the short line before "+n"
local SHIFT_RECIPES = 5 -- recipe lines with Shift before "+n more"

local function ByName(a, b)
	return a.name < b.name
end

-- Characters in usedBy (Alts_UsedByChars entries), most recipes in total first, then by name:
-- { { name, total, entries = { entry, ... } } }
local function Characters(usedBy)
	local list, byName = {}, {}
	for _, entry in ipairs(usedBy) do
		local c = byName[entry.name]
		if not c then
			c = { name = entry.name or "?", total = 0, entries = {} }
			byName[entry.name] = c
			list[#list + 1] = c
		end
		c.total = c.total + #entry.recipes
		c.entries[#c.entries + 1] = entry
	end
	table.sort(list, function(a, b)
		if a.total ~= b.total then
			return a.total > b.total
		end
		return a.name < b.name
	end)
	return list
end

local function ShortLine(usedBy)
	local chars = Characters(usedBy)
	if #chars == 1 then
		local parts = {}
		for _, entry in ipairs(chars[1].entries) do
			parts[#parts + 1] = ("%s (%d)"):format(entry.profName or "?", #entry.recipes)
		end
		return ("Used by %s: %s"):format(chars[1].name, table.concat(parts, ", "))
	end
	local names = {}
	for i = 1, math.min(SHORT_NAMES, #chars) do
		names[i] = chars[i].name
	end
	local text = "Used by " .. table.concat(names, ", ")
	if #chars > SHORT_NAMES then
		text = text .. " +" .. (#chars - SHORT_NAMES)
	end
	return text
end

-- One line per recipe, in usedBy's order, with everyone who knows it.
local function RecipeLines(usedBy, lines)
	local order, who = {}, {}
	for _, entry in ipairs(usedBy) do
		for _, r in ipairs(entry.recipes) do
			if not who[r.id] then
				who[r.id] = { name = r.name or "?", chars = {} }
				order[#order + 1] = r.id
			end
			table.insert(who[r.id].chars, entry.name or "?")
		end
	end
	lines[#lines + 1] = { text = "Used by", role = "accent" }
	for i = 1, math.min(SHIFT_RECIPES, #order) do
		local r = who[order[i]]
		lines[#lines + 1] = { text = ("  %s - %s"):format(r.name, table.concat(r.chars, ", ")), role = "textMuted" }
	end
	if #order > SHIFT_RECIPES then
		lines[#lines + 1] = { text = ("  +%d more"):format(#order - SHIFT_RECIPES), role = "textMuted" }
	end
end

-- The professions in uses that line 1 doesn't already show, by name: "Also: A, B" ("A (4), B (1)" with Shift).
local function AlsoLine(uses, usedBy, profName, shift)
	local shown = {}
	for _, entry in ipairs(usedBy) do
		shown[entry.base] = true
	end
	local profs = {}
	for line, count in pairs(uses) do
		local name = not shown[line] and profName(line)
		if name then
			profs[#profs + 1] = { name = name, count = count }
		end
	end
	if #profs == 0 then
		return nil
	end
	table.sort(profs, ByName)
	local parts = {}
	for i, p in ipairs(profs) do
		parts[i] = shift and ("%s (%d)"):format(p.name, p.count) or p.name
	end
	return "Also: " .. table.concat(parts, ", ")
end

-- Whether the generated table can know the item: its ID is no newer than the newest trade good or reagent of the
-- build the table was made from (MATERIALS_LAST_ITEM). Item IDs are handed out in rising order.
function ns.Materials_Known(itemID, lastKnown)
	return type(itemID) == "number" and type(lastKnown) == "number" and itemID <= lastKnown
end

-- input = { usedBy (Alts_UsedBy's list), uses (MATERIALS_USES entry or nil), isMaterial (a trade good or plain
-- reagent), known (Materials_Known), notUsed (the setting), shift, profName = function(skillLine) -> localized name
-- or nil }
-- -> { { text, role } } (theme color roles)
function ns.Materials_Lines(input)
	local lines = {}
	local usedBy = input.usedBy or {}
	if #usedBy > 0 then
		if input.shift then
			RecipeLines(usedBy, lines)
		else
			lines[#lines + 1] = { text = ShortLine(usedBy), role = "accent" }
		end
	end
	if input.uses then
		local also = AlsoLine(input.uses, usedBy, input.profName, input.shift)
		if also then
			lines[#lines + 1] = { text = also, role = "textFaint" }
		end
	elseif #usedBy == 0 and input.isMaterial and input.known and input.notUsed then
		lines[#lines + 1] = { text = "Not used in crafting", role = "textFaint" }
	end
	return lines
end
