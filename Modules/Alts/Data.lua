local addonName, ns = ...

-- Alts: pure logic (no WoW API calls; tested with plain Lua). Collect.lua reads the game into TomteDB.alts:
--   chars[guid]   = { guid, name, realm, class (token, "PRIEST"), race, level, spec (name), specID, primary ("STR" |
--                     "AGI" | "INT", the spec's main stat), ilvl, money, zone, seen, rested (0-150 %, nil at max level),
--                     gear = { [invSlot] = itemLink } (worn, slots 1-17 without the shirt), gearAt (when the gear
--                     last changed), profs = { [skillLine] = { name, base, skill, max, unspent, known = { [recipeID] } } } }
--                   specID, primary and gear are for Gear Check's upgrades for alts (Gear/Alts.lua).
--   recipes[id]   = { name, line (expansion skill line), base (profession skill line), item, qMin, qMax,
--                     reagents = { { items = { itemID, ... (quality ranks) }, qty } } }
-- A plan answers "what does it take to craft this recipe with what the account has": a shopping list of materials
-- (needed, have, missing) and the crafts in order, crafted materials worked out from other known recipes.

local floor, ceil, max, min = math.floor, math.ceil, math.max, math.min

ns.ALTS_FULL_DEPTH = 8 -- "full chain"; "one step" is 1

-- [itemID] = { recipeID, ... }: the recipes that make each item.
function ns.Alts_Producers(recipes)
	local byItem = {}
	for id, r in pairs(recipes) do
		if r.item then
			local list = byItem[r.item]
			if not list then
				list = {}
				byItem[r.item] = list
			end
			list[#list + 1] = id
		end
	end
	for _, list in pairs(byItem) do
		table.sort(list)
	end
	return byItem
end

-- Characters (sorted by name) who know the recipe, and those who could learn it (they have its profession).
function ns.Alts_Crafters(chars, recipe, recipeID)
	local known, learnable = {}, {}
	for _, c in pairs(chars) do
		local knows, hasProf = false, false
		for _, prof in pairs(c.profs or {}) do
			if prof.known and prof.known[recipeID] then
				knows = true
			end
			if recipe and prof.base == recipe.base then
				hasProf = true
			end
		end
		if knows then
			known[#known + 1] = c
		elseif hasProf then
			learnable[#learnable + 1] = c
		end
	end
	local function ByName(a, b)
		return (a.name or "") < (b.name or "")
	end
	table.sort(known, ByName)
	table.sort(learnable, ByName)
	return known, learnable
end

-- "known" | "learnable" | "none"
function ns.Alts_RecipeStatus(chars, recipe, recipeID)
	local known, learnable = ns.Alts_Crafters(chars, recipe, recipeID)
	if #known > 0 then
		return "known", known
	elseif #learnable > 0 then
		return "learnable", learnable
	end
	return "none", {}
end

-- Recipes matching opts (a string is just the search text):
--   text      lower case, plain find in the name ("" = all)
--   char      guid: only that character's recipes (with learnable, also the ones it could learn)
--   base      profession skill line: only that profession
--   learnable false: only recipes somebody knows
-- Known first, then learnable, then by name. Returns { { id, recipe, status, who } } (at most limit).
function ns.Alts_Search(recipes, chars, opts, limit)
	if type(opts) ~= "table" then
		opts = { text = opts or "" }
	end
	local text = opts.text or ""
	local order = { known = 1, learnable = 2, none = 3 }
	local char = opts.char and chars[opts.char]
	local list = {}
	for id, r in pairs(recipes) do
		if (text == "" or (r.name or ""):lower():find(text, 1, true)) and (not opts.base or r.base == opts.base) then
			local status, who = ns.Alts_RecipeStatus(chars, r, id)
			local keep = opts.learnable ~= false or status == "known"
			if keep and opts.char then
				local prof
				for _, pr in pairs(char and char.profs or {}) do
					if pr.base == r.base then
						prof = pr
					end
				end
				local knows = prof and prof.known and prof.known[id]
				keep = knows or (opts.learnable ~= false and prof ~= nil) or false
			end
			if keep then
				list[#list + 1] = { id = id, recipe = r, status = status, who = who }
			end
		end
	end
	table.sort(list, function(a, b)
		if order[a.status] ~= order[b.status] then
			return order[a.status] < order[b.status]
		end
		if a.recipe.name ~= b.recipe.name then
			return (a.recipe.name or "") < (b.recipe.name or "")
		end
		return a.id < b.id
	end)
	if limit and #list > limit then
		for i = #list, limit + 1, -1 do
			list[i] = nil
		end
	end
	return list
end

-- Search results as a grouped list: profession > expansion > category > recipes, like the profession window.
-- opts = { profName = function(base) -> name, current = function(recipe) -> true for the expansion you're in,
--          collapsed = { [key] = true | false }, expand = true to ignore collapsed (while searching) }
--          lineName = function(recipe) -> expansion name when the recipe didn't store one (optional) }
-- A group without a saved state is open, except expansions other than the current one (when one is current).
-- Levels that would say nothing are left out: an expansion named like its profession (no name known), and a lone
-- "Other" category.
-- Expansions: the current one first, then newest (highest skill line) first. Returns rows:
--   { kind = "prof" | "exp" | "cat", key, text, count, collapsed } and { kind = "recipe", result }.
function ns.Alts_Group(results, opts)
	local profs, byBase = {}, {}
	for _, res in ipairs(results) do
		local r = res.recipe
		local base = r.base or 0
		local p = byBase[base]
		if not p then
			p = { base = base, name = opts.profName(base) or "?", exps = {}, byLine = {}, count = 0 }
			byBase[base] = p
			profs[#profs + 1] = p
		end
		local line = r.line or 0
		local e = p.byLine[line]
		if not e then
			local lineName = r.lineName or (opts.lineName and opts.lineName(r))
			e = { line = line, name = lineName or p.name, current = opts.current(r) == true, cats = {}, byCat = {},
				count = 0 }
			p.byLine[line] = e
			p.exps[#p.exps + 1] = e
		end
		local catName = r.category or "Other"
		local c = e.byCat[catName]
		if not c then
			c = { name = catName, results = {} }
			e.byCat[catName] = c
			e.cats[#e.cats + 1] = c
		end
		c.results[#c.results + 1] = res
		e.count, p.count = e.count + 1, p.count + 1
	end
	table.sort(profs, function(a, b)
		return a.name < b.name
	end)
	local rows = {}
	local function Header(kind, key, text, count, foldByDefault)
		local saved = opts.collapsed[key]
		local collapsed = not opts.expand and (saved == true or (saved == nil and foldByDefault == true))
		rows[#rows + 1] = { kind = kind, key = key, text = text, count = count, collapsed = collapsed }
		return collapsed
	end
	for _, p in ipairs(profs) do
		local pKey = "p" .. p.base
		if not Header("prof", pKey, p.name, p.count) then
			table.sort(p.exps, function(a, b)
				if a.current ~= b.current then
					return a.current
				end
				return a.line > b.line
			end)
			local anyCurrent = p.exps[1] and p.exps[1].current
			for _, e in ipairs(p.exps) do
				local eKey = pKey .. ":" .. e.line
				local showExp = e.name ~= p.name
				if not (showExp and Header("exp", eKey, e.name, e.count, anyCurrent and not e.current)) then
					table.sort(e.cats, function(a, b)
						return a.name < b.name
					end)
					local showCats = not (#e.cats == 1 and e.cats[1].name == "Other")
					for _, c in ipairs(e.cats) do
						if not (showCats and Header("cat", eKey .. ":" .. c.name, c.name, #c.results)) then
							for _, res in ipairs(c.results) do
								rows[#rows + 1] = { kind = "recipe", result = res }
							end
						end
					end
				end
			end
		end
	end
	return rows
end

-- Whether a profession line's name ("Dragon Isles Blacksmithing") belongs to a continent ("Dragon Isles").
local LINE_ALIASES = { ["broken isles"] = "legion", ["kul tiras"] = "kul tiran", ["zandalar"] = "zandalari",
	["the shadowlands"] = "shadowlands" }
function ns.Alts_LineInContinent(lineName, continentName)
	if not (lineName and continentName and continentName ~= "") then
		return false
	end
	local line, continent = lineName:lower(), continentName:lower()
	local prefix = LINE_ALIASES[continent] or continent
	return line:sub(1, #prefix) == prefix
end

-- Items a recipe yields per craft (the low end of a range: what you can count on).
function ns.Alts_Yield(recipe)
	return max(recipe.qMin or 1, 1)
end

local function SlotKey(items)
	return table.concat(items, ",")
end

-- Which recipe to use for a crafted material: one somebody knows (then any), lowest ID for a stable answer.
local function PickProducer(itemIDs, producers, recipes, chars, stack)
	local fallback
	for _, itemID in ipairs(itemIDs) do
		for _, id in ipairs(producers[itemID] or {}) do
			if not stack[id] and recipes[id] then
				if #(ns.Alts_Crafters(chars, recipes[id], id)) > 0 then
					return id
				end
				fallback = fallback or id
			end
		end
	end
	return fallback
end

-- Builds the plan to craft `crafts` times recipeID.
-- ctx = { recipes, chars, producers (Alts_Producers), count = function(itemIDs) -> total the account has,
--         maxDepth (ALTS_FULL_DEPTH or 1) }
-- Returns {
--   materials = { { items, name?, need, have, missing, crafted = recipeID?, top = true when the recipe itself uses
--                   it, craftShort = units its craft makes } },  -- in first-seen order
--   steps     = { { recipeID, crafts, crafters = { char }, learnable = { char } } }, -- do them in this order
--   missing   = total units still missing (0 = everything can be made), unknown = steps nobody knows yet }
function ns.Alts_Plan(recipeID, crafts, ctx)
	local materials, byKey = {}, {}
	local steps = {}
	local reserved = {} -- [slotKey] = units already promised to an earlier slot
	local made = {} -- [slotKey] = units the planned crafts make (leftovers serve later slots)
	local stepFor, subs = {}, {} -- [recipeID] = step; [recipeID] = { sub recipeIDs } in first-use order
	local plan = { materials = materials, steps = steps, missing = 0, unknown = 0 }

	local function Material(items)
		local key = SlotKey(items)
		local m = byKey[key]
		if not m then
			m = { items = items, need = 0, have = ctx.count(items) or 0, missing = 0 }
			byKey[key] = m
			materials[#materials + 1] = m
		end
		return m, key
	end

	local function Craft(id, n, depth, stack)
		local recipe = ctx.recipes[id]
		stack[id] = true
		for _, slot in ipairs(recipe and recipe.reagents or {}) do
			local m, key = Material(slot.items)
			if depth == 0 then
				m.top = true
			end
			local need = slot.qty * n
			m.need = m.need + need
			local free = max(m.have + (made[key] or 0) - (reserved[key] or 0), 0)
			local use = min(free, need)
			reserved[key] = (reserved[key] or 0) + use
			local short = need - use
			if short > 0 then
				local sub = depth < ctx.maxDepth and PickProducer(slot.items, ctx.producers, ctx.recipes, ctx.chars, stack)
				if sub then
					m.crafted = sub
					m.craftShort = (m.craftShort or 0) + short
					local count = ceil(short / ns.Alts_Yield(ctx.recipes[sub]))
					made[key] = (made[key] or 0) + count * ns.Alts_Yield(ctx.recipes[sub])
					reserved[key] = reserved[key] + short
					subs[id] = subs[id] or {}
					table.insert(subs[id], sub)
					Craft(sub, count, depth + 1, stack)
				else
					m.missing = m.missing + short
					plan.missing = plan.missing + short
				end
			end
		end
		stack[id] = nil
		local step = stepFor[id]
		if step then
			step.crafts = step.crafts + n
			return
		end
		local known, learnable = ns.Alts_Crafters(ctx.chars, recipe, id)
		stepFor[id] = { recipeID = id, crafts = n, crafters = known, learnable = learnable }
		if #known == 0 then
			plan.unknown = plan.unknown + 1
		end
	end

	Craft(recipeID, max(crafts or 1, 1), 0, {})

	-- Steps in the order to do them: every recipe after the crafts that make its materials.
	local placed = {}
	local function Place(id)
		if placed[id] then
			return
		end
		placed[id] = true
		for _, sub in ipairs(subs[id] or {}) do
			Place(sub)
		end
		steps[#steps + 1] = stepFor[id]
	end
	Place(recipeID)
	return plan
end

-- What to buy for one plan or a list of plans (the Crafting list): { { itemID, qty } } in first-seen order, one per
-- material (its first quality rank). "full": only what's missing (crafted materials are made from their own,
-- which are listed). "one": the recipe's own materials, a crafted one too (bought instead of made).
function ns.Alts_ShoppingItems(plans, mode)
	if plans.materials then
		plans = { plans }
	end
	local list, byItem = {}, {}
	for _, plan in ipairs(plans) do
		for _, m in ipairs(plan.materials or {}) do
			local qty
			if mode == "one" then
				qty = m.top and (m.missing + (m.craftShort or 0)) or 0
			else
				qty = m.missing
			end
			if qty > 0 then
				local itemID = m.items[1]
				local entry = byItem[itemID]
				if not entry then
					entry = { itemID = itemID, qty = 0 }
					byItem[itemID] = entry
					list[#list + 1] = entry
				end
				entry.qty = entry.qty + qty
			end
		end
	end
	return list
end

-- Recipe items ----------------------------------------------------------------------------------------------

-- The recipe a recipe item teaches, by name: "Plans: Charged Runeaxe" -> "charged runeaxe" (the part after the
-- "Recipe:", "Pattern:", "Formula:"... prefix; the whole name without one), lower case.
function ns.Alts_RecipeItemName(itemName)
	if type(itemName) ~= "string" or itemName == "" then
		return nil
	end
	local rest = itemName:match("^[^:]+:%s*(.+)$")
	return (rest or itemName):lower()
end

-- [lower-case recipe name] = { recipeID, ... }
function ns.Alts_RecipesByName(recipes)
	local byName = {}
	for id, r in pairs(recipes) do
		if r.name then
			local key = r.name:lower()
			byName[key] = byName[key] or {}
			table.insert(byName[key], id)
		end
	end
	for _, ids in pairs(byName) do
		table.sort(ids)
	end
	return byName
end

-- The tooltip line for a recipe item teaching one of these recipes (same name, so maybe several):
-- "known", "Tomten" | "learnable", "Tomten, Mira, Bob, +2", profession base | nil (nobody has the profession).
function ns.Alts_RecipeItemStatus(chars, recipes, ids)
	local known, learnable, seen, base = {}, {}, {}, nil
	for _, id in ipairs(ids or {}) do
		local k, l = ns.Alts_Crafters(chars, recipes[id], id)
		for _, c in ipairs(k) do
			if not seen[c] then
				seen[c] = true
				known[#known + 1] = c
			end
		end
		if #l > 0 then
			base = base or recipes[id].base
		end
		for _, c in ipairs(l) do
			if not seen[c] then
				seen[c] = true
				learnable[#learnable + 1] = c
			end
		end
	end
	local function Names(list)
		table.sort(list, function(a, b)
			return (a.name or "") < (b.name or "")
		end)
		local parts = {}
		for i, c in ipairs(list) do
			if i > 3 then
				parts[#parts + 1] = "+" .. (#list - 3)
				break
			end
			parts[#parts + 1] = c.name or "?"
		end
		return table.concat(parts, ", ")
	end
	if #known > 0 then
		return "known", Names(known)
	end
	if #learnable > 0 then
		return "learnable", Names(learnable), base
	end
	return nil
end

-- Roster ------------------------------------------------------------------------------------------------------

-- "12,345g" (gold only; copper in, rounded down).
function ns.Alts_Gold(copper)
	local gold = floor((copper or 0) / 10000)
	local text = tostring(gold)
	while true do
		local replaced
		text, replaced = text:gsub("^(%d+)(%d%d%d)", "%1,%2")
		if replaced == 0 then
			break
		end
	end
	return text .. "g"
end

-- A price: "12g" from a gold up, else "45s" or "80c" (so a cheap reagent isn't "0g").
function ns.Alts_Price(copper)
	copper = floor(copper or 0)
	if copper >= 10000 then
		return ns.Alts_Gold(copper)
	elseif copper >= 100 then
		return floor(copper / 100) .. "s"
	end
	return copper .. "c"
end

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

-- "Vault 4/9 · Concentration: Blacksmithing full, Alchemy full in 6h" (a full one in gold), "" for nil.
function ns.Alts_WeeklyLine(status)
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
		concs[#concs + 1] = c.full and ("|cffffd100%s|r"):format(text) or text
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
