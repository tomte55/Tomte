local addonName, ns = ...

-- Crafting list: pure logic (unit-tested with plain Lua). Tracked crafts, where their materials are, and the to-do
-- for the character you're on. List.lua reads the game (Syndicator, bags) and draws the tracker, the List tab, the
-- mailbox rows and the bank marks.
--
-- A pool holds what the account has per item and place: pool.places[itemID] = { { guid, where, n } } with where =
-- "bags" | "bank" | "mail" | "warband" (guid nil for the Warband bank). Crafts take from it in list order, so two
-- crafts never count the same items.

local max, min = math.max, math.min

-- List ------------------------------------------------------------------------------------------------------------

-- Adds crafts of a recipe (to the existing entry when it's listed already). Returns the entry.
function ns.Alts_ListAdd(list, recipeID, crafts, now)
	for _, e in ipairs(list) do
		if e.recipeID == recipeID then
			e.crafts = e.crafts + max(crafts or 1, 1)
			return e
		end
	end
	local e = { recipeID = recipeID, crafts = max(crafts or 1, 1), added = now }
	list[#list + 1] = e
	return e
end

function ns.Alts_ListRemove(list, recipeID)
	for i = #list, 1, -1 do
		if list[i].recipeID == recipeID then
			table.remove(list, i)
		end
	end
end

-- One craft of a listed recipe was made: counts it down, drops it at 0 when auto. Returns the entry (or nil).
function ns.Alts_ListCrafted(list, recipeID, auto)
	for i, e in ipairs(list) do
		if e.recipeID == recipeID then
			e.crafts = e.crafts - 1
			e.made = (e.made or 0) + 1
			if e.crafts <= 0 then
				if auto then
					table.remove(list, i)
				else
					e.crafts = 0
				end
			end
			return e
		end
	end
	return nil
end

-- Pool ------------------------------------------------------------------------------------------------------------

-- where(itemID) -> { { guid, where, n } } for one item; read once per item.
function ns.Alts_Pool(where)
	return { places = {}, where = where }
end

local function Places(pool, itemID)
	local places = pool.places[itemID]
	if not places then
		places = {}
		for i, p in ipairs(pool.where(itemID) or {}) do
			places[i] = { guid = p.guid, where = p.where, n = p.n }
		end
		pool.places[itemID] = places
	end
	return places
end

-- What's left of these items (quality ranks of one reagent) in the pool.
function ns.Alts_PoolTotal(pool, items)
	local total = 0
	for _, itemID in ipairs(items) do
		for _, p in ipairs(Places(pool, itemID)) do
			total = total + p.n
		end
	end
	return total
end

-- Order to take from: the crafter's bags, bank, mail, then the Warband bank, then the character you're on, then
-- everyone else.
local function Rank(p, dest, me)
	local base = p.guid == dest and 0 or (p.guid == nil and 10 or (p.guid == me and 20 or 30))
	local within = p.where == "bags" and 0 or (p.where == "bank" and 1 or (p.where == "mail" and 2 or 3))
	return base + within
end

-- Takes n of these items for `dest`. Returns { { itemID, guid, where, n } } and how many are still missing.
function ns.Alts_PoolTake(pool, items, n, dest, me)
	local candidates = {}
	for _, itemID in ipairs(items) do
		for _, p in ipairs(Places(pool, itemID)) do
			if p.n > 0 then
				candidates[#candidates + 1] = { itemID = itemID, p = p, rank = Rank(p, dest, me) }
			end
		end
	end
	table.sort(candidates, function(a, b)
		if a.rank ~= b.rank then
			return a.rank < b.rank
		end
		return a.p.n > b.p.n
	end)
	local taken = {}
	for _, c in ipairs(candidates) do
		if n <= 0 then
			break
		end
		local use = min(c.p.n, n)
		c.p.n = c.p.n - use
		n = n - use
		taken[#taken + 1] = { itemID = c.itemID, guid = c.p.guid, where = c.p.where, n = use }
	end
	return taken, n
end

-- Plans and to-do -------------------------------------------------------------------------------------------------

local function SlotKey(items)
	return table.concat(items, ",")
end

-- [slotKey] = the step (and so the crafter) that uses this material first.
function ns.Alts_StepOf(plan, recipes)
	local out = {}
	for _, step in ipairs(plan.steps) do
		local recipe = recipes[step.recipeID]
		for _, slot in ipairs(recipe and recipe.reagents or {}) do
			local key = SlotKey(slot.items)
			out[key] = out[key] or step
		end
	end
	return out
end

local function CrafterOf(step)
	local c = step and step.crafters and step.crafters[1]
	return c and c.guid or nil
end

-- One tracked craft: its plan, where the materials come from, and the to-do lines for `me`.
-- ctx = { me, chars, recipes, plan = function(recipeID, crafts, count) -> plan, pool, itemName(itemID),
--         recipeName(recipeID), price(itemID) -> copper | nil (optional), gold(copper) -> text }
-- Line kinds: "grab" (your bank), "collect" (your mail), "take" (Warband bank), "mail" (from your bags to the
-- crafter), "fetch" (your bank or mail, then mail it), "other" (someone else has it), "missing", "craft" (a step
-- someone does), "ready" (you can craft it now), "wait" (the crafter crafts it, not you).
function ns.Alts_CraftTodo(entry, ctx)
	local pool = ctx.pool
	local plan = ctx.plan(entry.recipeID, entry.crafts, function(items)
		return ns.Alts_PoolTotal(pool, items)
	end)
	local stepOf = ns.Alts_StepOf(plan, ctx.recipes)
	local final = plan.steps[#plan.steps]
	local finalCrafter = CrafterOf(final)
	local me = ctx.me
	local lines, inPlace, needed = {}, 0, 0
	local outstanding = 0 -- units that still have to move or be found for the final crafter
	local function Name(guid)
		local c = guid and ctx.chars[guid]
		return c and c.name or "?"
	end
	local function Add(line)
		lines[#lines + 1] = line
	end

	for _, m in ipairs(plan.materials) do
		local step = stepOf[SlotKey(m.items)]
		local dest = CrafterOf(step) or finalCrafter
		-- The part that comes from what we have (a crafted shortfall is made by its own step).
		local fromStock = m.crafted and min(m.have, m.need) or (m.need - m.missing)
		local taken = ns.Alts_PoolTake(pool, m.items, fromStock, dest, me)
		needed = needed + m.need
		for _, t in ipairs(taken) do
			local name = ctx.itemName(t.itemID)
			if t.guid == dest and t.where == "bags" then
				inPlace = inPlace + t.n
			else
				outstanding = outstanding + t.n
				local line = { itemID = t.itemID, n = t.n, from = t.guid, where = t.where, to = dest }
				if t.guid == nil then
					line.kind = "take"
					line.text = dest == me and ("Take %d %s from the Warband bank"):format(t.n, name)
						or ("Take %d %s from the Warband bank for %s"):format(t.n, name, Name(dest))
					line.mine = true
				elseif t.guid == me and dest == me then
					line.kind = t.where == "mail" and "collect" or "grab"
					line.text = t.where == "mail" and ("Collect %d %s from your mail"):format(t.n, name)
						or ("Grab %d %s from your bank"):format(t.n, name)
					line.mine = true
				elseif t.guid == me then
					if t.where == "bags" then
						line.kind = "mail"
						line.text = ("Mail %d %s to %s"):format(t.n, name, Name(dest))
					else
						line.kind = "fetch"
						line.text = ("Grab %d %s from your %s, then mail it to %s"):format(t.n, name,
							t.where == "mail" and "mail" or "bank", Name(dest))
					end
					line.mine = true
				else
					line.kind = "other"
					local place = t.where == "bags" and "" or (" (%s)"):format(t.where)
					line.text = t.guid == dest and ("%s has %d %s in the %s"):format(Name(t.guid), t.n, name, t.where)
						or ("%s has %d %s%s for %s"):format(Name(t.guid), t.n, name, place, Name(dest))
				end
				Add(line)
			end
		end
		if m.missing > 0 then
			outstanding = outstanding + m.missing
			local price = ctx.price and ctx.price(m.items[1])
			Add({ kind = "missing", itemID = m.items[1], n = m.missing,
				text = ("Buy or gather %d %s%s"):format(m.missing, ctx.itemName(m.items[1]),
					price and (" (~%s)"):format(ctx.gold(price * m.missing)) or ""), mine = true })
		end
	end
	for _, step in ipairs(plan.steps) do
		if step ~= final then
			local crafter = CrafterOf(step)
			local what = ("%d %s"):format(step.crafts, ctx.recipeName(step.recipeID))
			Add({ kind = "craft", recipeID = step.recipeID, mine = crafter == me,
				text = crafter == me and ("Craft %s first"):format(what)
					or crafter and ("%s: craft %s first"):format(Name(crafter), what)
					or ("Nobody knows how to craft %s"):format(what) })
		end
	end
	local finalText = ("%d %s"):format(entry.crafts, ctx.recipeName(entry.recipeID))
	if outstanding == 0 and #plan.steps <= 1 then
		Add({ kind = finalCrafter == me and "ready" or "wait", mine = finalCrafter == me,
			text = finalCrafter == me and ("Craft %s: you have everything"):format(finalText)
				or ("%s can craft %s: everything is there"):format(Name(finalCrafter), finalText) })
	elseif finalCrafter ~= me then
		Add({ kind = "wait", text = ("%s crafts %s"):format(finalCrafter and Name(finalCrafter) or "Nobody", finalText) })
	end
	-- Your lines first, the rest in their order.
	local ordered = {}
	for _, l in ipairs(lines) do
		if l.mine then
			ordered[#ordered + 1] = l
		end
	end
	for _, l in ipairs(lines) do
		if not l.mine then
			ordered[#ordered + 1] = l
		end
	end
	return {
		entry = entry, plan = plan, lines = ordered, crafter = finalCrafter,
		inPlace = inPlace, needed = needed, done = outstanding == 0 and #plan.steps <= 1,
	}
end

-- Every tracked craft in list order (one pool, so they don't count the same items twice).
function ns.Alts_ListTodo(list, ctx)
	local out = {}
	for _, entry in ipairs(list) do
		if ctx.recipes[entry.recipeID] then
			out[#out + 1] = ns.Alts_CraftTodo(entry, ctx)
		end
	end
	return out
end

-- Mail for one craft: what to attach from your bags, as { { itemID, n } } (the "mail" lines), and to whom.
function ns.Alts_CraftMail(todo)
	local wants, to = {}, nil
	for _, l in ipairs(todo.lines) do
		if l.kind == "mail" then
			if not to or l.to == to then
				to = l.to
				wants[#wants + 1] = { itemID = l.itemID, n = l.n }
			end
		end
	end
	return wants, to
end

-- How to attach `wants` from bag stacks ({ bag, slot, itemID, count }): { { bag, slot, split = n | nil } } with at most
-- `max` attachments. exact: split stacks to send only what's needed; else whole stacks until it's covered.
function ns.Alts_AttachPlan(wants, stacks, exact, maxSlots)
	local out = {}
	local used = {}
	for _, w in ipairs(wants) do
		local left = w.n
		for i, s in ipairs(stacks) do
			if left <= 0 or #out >= (maxSlots or 12) then
				break
			end
			if s.itemID == w.itemID and not used[i] then
				used[i] = true
				if exact and s.count > left then
					out[#out + 1] = { bag = s.bag, slot = s.slot, split = left, itemID = s.itemID }
					left = 0
				else
					out[#out + 1] = { bag = s.bag, slot = s.slot, itemID = s.itemID, n = s.count }
					left = left - s.count
				end
			end
		end
	end
	return out
end

-- [itemID] = count, the items your to-do lines move (for the bag and bank marks).
function ns.Alts_MarkedItems(todos)
	local marked = {}
	for _, t in ipairs(todos) do
		for _, l in ipairs(t.lines) do
			if l.mine and l.itemID and l.kind ~= "missing" then
				marked[l.itemID] = (marked[l.itemID] or 0) + l.n
			end
		end
	end
	return marked
end

-- Progress of a craft as a fraction (materials in the crafter's bags / needed).
function ns.Alts_CraftProgress(todo)
	if todo.needed <= 0 then
		return 1
	end
	return min(todo.inPlace / todo.needed, 1)
end
