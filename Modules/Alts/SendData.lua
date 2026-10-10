local addonName, ns = ...

-- Send to alt: pure logic (unit-tested with plain Lua). Which of this character's stacks another character uses,
-- and who gets them. Send.lua reads the bags and drives the mailbox and the Warband bank.

-- [itemID] = { [guid] = number of known recipes that use it }, from every character's known recipes.
function ns.Alts_ReagentUsers(chars, recipes)
	local users = {}
	for guid, c in pairs(chars) do
		for base, prof in pairs(c.profs or {}) do
			for recipeID in pairs(prof.known or {}) do
				local recipe = recipes[recipeID]
				for _, slot in ipairs(recipe and recipe.reagents or {}) do
					for _, itemID in ipairs(slot.items or {}) do
						local u = users[itemID]
						if not u then
							u = {}
							users[itemID] = u
						end
						u[guid] = (u[guid] or 0) + 1
					end
				end
			end
		end
	end
	return users
end

-- "12345 = Mira, linen cloth = Tolvan" -> { { match = 12345 | "linen cloth", to = "mira" } }. Lines or commas.
function ns.Alts_ParseRules(text)
	local rules = {}
	for part in (text or ""):gmatch("[^,\n;]+") do
		local left, right = part:match("^%s*(.-)%s*=%s*(.-)%s*$")
		if left and right and left ~= "" and right ~= "" then
			rules[#rules + 1] = { match = tonumber(left) or left:lower(), to = right:lower() }
		end
	end
	return rules
end

local function ByName(chars, name)
	for guid, c in pairs(chars) do
		if (c.name or ""):lower() == name then
			return guid
		end
	end
	return nil
end

-- A realm name as GetNormalizedRealmName and GetAutoCompleteRealms give it: no spaces or dashes.
local function NormalRealm(realm)
	return (realm or ""):gsub("[%s%-]", "")
end

-- The realms mail can reach: { [normalized realm] = true } from the connected realms (GetAutoCompleteRealms, which
-- is empty on a realm that isn't connected) and your own.
function ns.Alts_RealmSet(realms, myRealm)
	local set = {}
	for _, realm in ipairs(realms or {}) do
		set[NormalRealm(realm)] = true
	end
	set[NormalRealm(myRealm)] = true
	return set
end

-- Whether mail reaches a character. realms = ns.Alts_RealmSet(...), or nil when it isn't known (then everyone is
-- reachable); a character without a stored realm is taken to be reachable too.
function ns.Alts_Reachable(c, realms)
	if not realms or not c or not c.realm or c.realm == "" then
		return true
	end
	return realms[NormalRealm(c.realm)] == true
end

-- Who gets one item, or nil. ctx = { me, chars, users, plan = { [itemID] = guid }, rules, realms (optional, mail
-- only: characters on realms mail can't reach are left out) }.
-- name = the item's name (for name rules). Order: a manual rule, then the craft plan, then whoever knows the most
-- recipes using it (ties: the most recently played). Nothing when this character uses it itself.
function ns.Alts_Recipient(itemID, name, ctx)
	local function Ok(guid)
		return guid ~= ctx.me and ctx.chars[guid] ~= nil and ns.Alts_Reachable(ctx.chars[guid], ctx.realms)
	end
	for _, rule in ipairs(ctx.rules or {}) do
		if rule.match == itemID or (name and rule.match == name:lower()) then
			local guid = ByName(ctx.chars, rule.to)
			if guid and Ok(guid) then
				return guid, "rule"
			end
			return nil
		end
	end
	local users = ctx.users[itemID]
	if users and users[ctx.me] then
		return nil
	end
	local planned = ctx.plan and ctx.plan[itemID]
	if planned and Ok(planned) then
		return planned, "plan"
	end
	local best, bestN, bestSeen
	for guid, n in pairs(users or {}) do
		local seen = ctx.chars[guid] and ctx.chars[guid].seen or 0
		if Ok(guid) and (not best or n > bestN or (n == bestN and seen > bestSeen)) then
			best, bestN, bestSeen = guid, n, seen
		end
	end
	return best, best and "recipes" or nil
end

-- Groups stacks by recipient. stacks = { { bag, slot, itemID, name, count, ... } }; filter(stack) -> bool keeps a
-- stack (mailable, warbound, ...). Returns { { guid, stacks = { ... }, count } } sorted by most stacks, then name.
function ns.Alts_SendGroups(stacks, ctx, filter)
	local byGuid, groups = {}, {}
	for _, s in ipairs(stacks) do
		if not filter or filter(s) then
			local guid, why = ns.Alts_Recipient(s.itemID, s.name, ctx)
			if guid then
				local g = byGuid[guid]
				if not g then
					g = { guid = guid, stacks = {}, count = 0 }
					byGuid[guid] = g
					groups[#groups + 1] = g
				end
				s.why = why
				g.stacks[#g.stacks + 1] = s
				g.count = g.count + (s.count or 1)
			end
		end
	end
	table.sort(groups, function(a, b)
		if #a.stacks ~= #b.stacks then
			return #a.stacks > #b.stacks
		end
		local na, nb = ctx.chars[a.guid].name or "", ctx.chars[b.guid].name or ""
		return na < nb
	end)
	return groups
end

-- Bag stacks left once the tracked crafts' mails have what they need (claims: [itemID] = amount). A stack a craft
-- draws on is left out whole: attaching it here would mail it twice.
function ns.Alts_Unclaimed(stacks, claims)
	local left, out = {}, {}
	for itemID, n in pairs(claims) do
		left[itemID] = n
	end
	for _, s in ipairs(stacks) do
		local need = left[s.itemID]
		if need and need > 0 then
			left[s.itemID] = need - (s.count or 1)
		else
			out[#out + 1] = s
		end
	end
	return out
end

-- The next mail's stacks: the first `max` (12) of a group.
function ns.Alts_NextMail(group, max)
	local list = {}
	for i = 1, math.min(#group.stacks, max or 12) do
		list[i] = group.stacks[i]
	end
	return list
end

-- [itemID] = guid of the crafter of the step that uses it, from a Crafting tab plan (ns.Alts_Plan result).
function ns.Alts_PlanAssignments(plan, recipes)
	local out = {}
	for _, step in ipairs(plan and plan.steps or {}) do
		local crafter = step.crafters and step.crafters[1]
		local recipe = recipes[step.recipeID]
		if crafter and crafter.guid and recipe then
			for _, slot in ipairs(recipe.reagents or {}) do
				for _, itemID in ipairs(slot.items or {}) do
					out[itemID] = out[itemID] or crafter.guid
				end
			end
		end
	end
	return out
end

-- Gold to send to top a character up to `target` copper (nil when it already has it or we can't spare it).
-- spare = what this character has, keep = what it keeps for itself.
function ns.Alts_TopUp(has, target, spare, keep)
	local need = target - (has or 0)
	if need <= 0 then
		return nil
	end
	local can = (spare or 0) - (keep or 0)
	if can <= 0 then
		return nil
	end
	return math.min(need, can)
end

-- Mail recipient for a character: "Name" on your realm, "Name-Realm" otherwise (realm without spaces or dashes).
function ns.Alts_MailName(c, myRealm)
	local realm = (c.realm or ""):gsub("[%s%-]", "")
	local mine = (myRealm or ""):gsub("[%s%-]", "")
	if realm == "" or realm == mine then
		return c.name
	end
	return c.name .. "-" .. realm
end

-- Gear for alts (Gear Check's upgrades for alts): stacks the caller marked with s.to (the character it's the best
-- upgrade for) and s.route ("mail" for Bind on Equip, "warband" for warbound), only those going by route, grouped by
-- who gets them. Same shape as Alts_SendGroups plus gear = true, sorted by name. realms (optional, as in
-- Alts_Reachable): characters mail can't reach are left out.
function ns.Alts_GearGroups(stacks, route, chars, realms)
	local byGuid, groups = {}, {}
	for _, s in ipairs(stacks) do
		if s.to and s.route == route and chars[s.to] and ns.Alts_Reachable(chars[s.to], realms) then
			local g = byGuid[s.to]
			if not g then
				g = { guid = s.to, stacks = {}, count = 0, gear = true }
				byGuid[s.to] = g
				groups[#groups + 1] = g
			end
			g.stacks[#g.stacks + 1] = s
			g.count = g.count + (s.count or 1)
		end
	end
	table.sort(groups, function(a, b)
		return (chars[a.guid].name or "") < (chars[b.guid].name or "")
	end)
	return groups
end
