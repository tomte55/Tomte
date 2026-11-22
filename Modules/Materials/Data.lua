local addonName, ns = ...

-- Material uses: pure logic (no WoW API calls; unit-tested in tests/test_materials.lua). Turns what Alts knows (which
-- characters' recipes use an item) and the generated table (which professions use it) into tooltip lines.
-- The tooltip hook is in Materials.lua; the table is Generated.lua (tools/materials.py).

local SHORT_NAMES = 2 -- characters named per profession before "+n"
local SHIFT_RECIPES = 5 -- recipe lines with Shift before "+n more"

local function ByName(a, b)
	return a.name < b.name
end

local function MostFirst(a, b)
	if a.total ~= b.total then
		return a.total > b.total
	end
	return a.name < b.name
end

-- Your professions in usedBy (Alts_UsedByChars entries), most known recipes first, then by name:
-- { { base, name, total, chars = { name, ... } } }, chars ordered the same way.
local function Yours(usedBy)
	local list, byBase = {}, {}
	for _, entry in ipairs(usedBy) do
		local p = byBase[entry.base]
		if not p then
			p = { base = entry.base, name = entry.profName or "?", total = 0, chars = {} }
			byBase[entry.base] = p
			list[#list + 1] = p
		end
		p.total = p.total + #entry.recipes
		p.chars[#p.chars + 1] = { name = entry.name or "?", total = #entry.recipes }
	end
	table.sort(list, MostFirst)
	for _, p in ipairs(list) do
		table.sort(p.chars, MostFirst)
	end
	return list, byBase
end

-- "Kesha, Mira +1"
local function Names(chars)
	local names = {}
	for i = 1, math.min(SHORT_NAMES, #chars) do
		names[i] = chars[i].name
	end
	local text = table.concat(names, ", ")
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
	for i = 1, math.min(SHIFT_RECIPES, #order) do
		local r = who[order[i]]
		lines[#lines + 1] = { text = ("  %s - %s"):format(r.name, table.concat(r.chars, ", ")), role = "textMuted" }
	end
	if #order > SHIFT_RECIPES then
		lines[#lines + 1] = { text = ("  +%d more"):format(#order - SHIFT_RECIPES), role = "textMuted" }
	end
end

-- "Used in: First Aid (Kesha, Mira +1), Tailoring (Aldric), Blacksmithing, Engineering": your professions first
-- with who has them, then the table's other professions by name. With Shift, recipe counts instead of names (the
-- table's count where it has one). The line comes as parts, each with its own color role.
local function UsedInLine(input, usedBy)
	local yours, byBase = Yours(usedBy)
	local uses = input.uses or {}
	local others = {}
	for line, count in pairs(uses) do
		local name = not byBase[line] and input.profName(line)
		if name then
			others[#others + 1] = { name = name, count = count }
		end
	end
	table.sort(others, ByName)
	if #yours == 0 and #others == 0 then
		return nil
	end
	local parts = { { text = "Used in: ", role = "textMuted" } }
	local function Add(text, role)
		if #parts > 1 then
			parts[#parts + 1] = { text = ", ", role = "textMuted" }
		end
		parts[#parts + 1] = { text = text, role = role }
	end
	for _, p in ipairs(yours) do
		local detail = input.shift and tostring(uses[p.base] or p.total) or Names(p.chars)
		Add(("%s (%s)"):format(p.name, detail), "accent")
	end
	for _, p in ipairs(others) do
		Add(input.shift and ("%s (%d)"):format(p.name, p.count) or p.name, "textFaint")
	end
	local texts = {}
	for i, part in ipairs(parts) do
		texts[i] = part.text
	end
	return { text = table.concat(texts), parts = parts }
end

-- Whether the generated table can know the item: its ID is no newer than the newest trade good or reagent of the
-- build the table was made from (MATERIALS_LAST_ITEM). Item IDs are handed out in rising order.
function ns.Materials_Known(itemID, lastKnown)
	return type(itemID) == "number" and type(lastKnown) == "number" and itemID <= lastKnown
end

-- input = { usedBy (Alts_UsedBy's list), uses (MATERIALS_USES entry or nil), isMaterial (a trade good or plain
-- reagent), known (Materials_Known), notUsed (the setting), shift, profName = function(skillLine) -> localized name
-- or nil }
-- -> { { text, role } or { text, parts = { { text, role } } } } (theme color roles; text is the plain whole line)
function ns.Materials_Lines(input)
	local lines = {}
	local usedBy = input.usedBy or {}
	local usedIn = UsedInLine(input, usedBy)
	if usedIn then
		lines[#lines + 1] = usedIn
		if input.shift then
			RecipeLines(usedBy, lines)
		end
	elseif #usedBy == 0 and not input.uses and input.isMaterial and input.known and input.notUsed then
		lines[#lines + 1] = { text = "Not used in crafting", role = "textFaint" }
	end
	return lines
end
