local addonName, ns = ...

-- Alts: pure logic (no WoW API calls; tested with plain Lua). Collect.lua reads the game into TomteDB.alts:
--   chars[guid]   = { guid, name, realm, class (token, "PRIEST"), race, level, levelUp (PLAYER_LEVEL_UP's level until
--                     the next read), spec (name), specID, primary ("STR" | "AGI" | "INT", the spec's main stat), ilvl,
--                     money, zone, seen, rested (0-150 %, nil at max level), gear = { [invSlot] = itemLink } (worn,
--                     slots 1-17 without the shirt), gearAt (when the gear last changed), profGear = { [invSlot] =
--                     itemLink } (worn profession tools and accessories, slots 20-30), profGearAt,
--                     profs = { [base skill line] = { name, icon, base, line (the content expansion's skill line),
--                     skill, max, unspent, known = { [recipeID] = true }, scannedAt (last recipe read), secondary (true
--                     for archaeology, fishing and cooking) } } }
--                   specID, primary and gear are for Gear Check's upgrades for alts (Gear/Alts.lua); worth (bag and
--                   bank value) is written by Modules/Value/Value.lua.
--   recipes[id]   = { v (Collect.lua's RECIPE_VERSION), name, icon, line (expansion skill line), lineName, category,
--                     base (profession skill line), item, qMin, qMax, out = { link at the lowest quality, at the
--                     highest } (gear and tools), outQ = { link at each quality, lowest first } (gear and tools), nq
--                     (how many qualities, nil for one), reagents = { { items = { itemID, ... (quality ranks) }, qty } } }
--   warbandMoney, warbandAt = the Warband bank's gold (copper) and when it was read; warbandWorth is Value.lua's.
-- A plan answers "what does it take to craft this recipe with what the account has": a shopping list of materials
-- (needed, have, missing) and the crafts in order, crafted materials worked out from other known recipes.
-- Roster and profession text: RosterData.lua. Gear and crafting quality: GearData.lua. Forgetting a character: Forget.lua.

local max, min, ceil = math.max, math.min, math.ceil

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

-- [itemID] = { recipeID, ... }: the recipes that use each item as a material (every quality rank of a slot).
function ns.Alts_ReagentIndex(recipes)
	local byItem = {}
	for id, r in pairs(recipes) do
		for _, slot in ipairs(r.reagents or {}) do
			for _, item in ipairs(slot.items or {}) do
				local list = byItem[item]
				if not list then
					list = {}
					byItem[item] = list
				end
				if list[#list] ~= id then -- the same item twice in one recipe counts once
					list[#list + 1] = id
				end
			end
		end
	end
	for _, list in pairs(byItem) do
		table.sort(list)
	end
	return byItem
end

-- Who knows the recipes (ids, from Alts_ReagentIndex): { { name, class, base, profName, recipes = { { id, name } } } },
-- one entry per character and profession, most recipes first, then by name and profession; recipes by name.
function ns.Alts_UsedByChars(chars, recipes, ids)
	local list = {}
	for _, c in pairs(chars) do
		for _, prof in pairs(c.profs or {}) do
			local entry
			for _, id in ipairs(ids or {}) do
				local r = recipes[id]
				if r and r.base == prof.base and prof.known and prof.known[id] then
					if not entry then
						entry = { name = c.name, class = c.class, base = prof.base, profName = prof.name, recipes = {} }
						list[#list + 1] = entry
					end
					entry.recipes[#entry.recipes + 1] = { id = id, name = r.name }
				end
			end
		end
	end
	for _, entry in ipairs(list) do
		table.sort(entry.recipes, function(a, b)
			return (a.name or "") < (b.name or "")
		end)
	end
	table.sort(list, function(a, b)
		if #a.recipes ~= #b.recipes then
			return #a.recipes > #b.recipes
		elseif a.name ~= b.name then
			return (a.name or "") < (b.name or "")
		end
		return (a.profName or "") < (b.profName or "")
	end)
	return list
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
--          collapsed = { [key] = true | false }, expand = true to ignore collapsed (while searching),
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

-- The rank picked for a reagent slot: its item ID and position, nil for any rank. ranks = { [slot key] = itemID }.
local function PickedRank(ranks, items)
	local itemID = ranks and ranks[SlotKey(items)]
	if itemID then
		for i, id in ipairs(items) do
			if id == itemID then
				return itemID, i
			end
		end
	end
	return nil
end

-- Builds the plan to craft `crafts` times recipeID.
-- ctx = { recipes, chars, producers (Alts_Producers), count = function(itemIDs) -> total the account has,
--         maxDepth (ALTS_FULL_DEPTH or 1), ranks = { [slot key] = itemID } (optional: a reagent's chosen rank) }
-- A slot with a chosen rank is a material of that item alone, apart from the same reagent at any rank.
-- Returns {
--   materials = { { items, slot (the slot's full rank list), name?, need, have, missing, crafted = recipeID?,
--                   top = true when the recipe itself uses it, craftShort = units its craft makes } },  -- first-seen order
--   steps     = { { recipeID, crafts, crafters = { char }, learnable = { char }, quality = the rank its material was
--                   picked at (nil: any) } }, -- do them in this order
--   missing   = total units still missing (0 = everything can be made), unknown = steps nobody knows yet }
function ns.Alts_Plan(recipeID, crafts, ctx)
	local materials, byKey = {}, {}
	local steps = {}
	local reserved = {} -- [slotKey] = units already promised to an earlier slot
	local made = {} -- [slotKey] = units the planned crafts make (leftovers serve later slots)
	local stepFor, subs = {}, {} -- [recipeID] = step; [recipeID] = { sub recipeIDs } in first-use order
	local plan = { materials = materials, steps = steps, missing = 0, unknown = 0 }

	local function Material(slotItems)
		local picked = PickedRank(ctx.ranks, slotItems)
		local items = picked and { picked } or slotItems
		-- A picked rank keeps its slot in the key: the same item can be a slot of its own elsewhere in the chain.
		local key = picked and (SlotKey(slotItems) .. "=" .. picked) or SlotKey(items)
		local m = byKey[key]
		if not m then
			m = { items = items, slot = slotItems, need = 0, have = ctx.count(items) or 0, missing = 0 }
			byKey[key] = m
			materials[#materials + 1] = m
		end
		return m, key
	end

	local function Craft(id, n, depth, stack, quality)
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
				-- By the slot's full rank list: recipes are indexed by the item they make, not each rank of it.
				local sub = depth < ctx.maxDepth and PickProducer(slot.items, ctx.producers, ctx.recipes, ctx.chars, stack)
				if sub then
					m.crafted = sub
					m.craftShort = (m.craftShort or 0) + short
					local count = ceil(short / ns.Alts_Yield(ctx.recipes[sub]))
					made[key] = (made[key] or 0) + count * ns.Alts_Yield(ctx.recipes[sub])
					reserved[key] = reserved[key] + short
					subs[id] = subs[id] or {}
					table.insert(subs[id], sub)
					Craft(sub, count, depth + 1, stack, (select(2, PickedRank(ctx.ranks, slot.items))))
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
			if quality and (step.quality or 0) < quality then
				step.quality = quality -- made at two ranks: the higher one
			end
			return
		end
		local known, learnable = ns.Alts_Crafters(ctx.chars, recipe, id)
		stepFor[id] = { recipeID = id, crafts = n, crafters = known, learnable = learnable, quality = quality }
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
-- "known", "Aldric" | "learnable", "Aldric, Mira, Bob, +2", profession base | nil (nobody has the profession).
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
