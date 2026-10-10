local addonName, ns = ...

-- Pet Battles: pure rules. The type chart (from the game's own modifier, never hardcoded), matchup scores and
-- swap advice, team picking for Load team, readiness, the leveling queue and Xu-Fu note helpers. No WoW API calls:
-- callers pass plain tables (tests/test_pets.lua).
--
-- Pet families are the game's 1..10 (1 Humanoid ... 10 Mechanical). A pet for matchups:
--   { type, dead, abilities = { { type, noHints, usable } } }
-- An owned pet (Journal.lua): { guid, species, level, rarity (1-6), health, maxHealth, type, abilities = { 6 ids } }

ns.PETS_MAX_LEVEL = 25
ns.PETS_SWAP_MARGIN = 2 -- points the best pet must beat the active one by before Tomte suggests a swap

-- chart[attackType][defenderType] = modifier (1.5 strong, ~0.67 weak, 1 neutral).
function ns.Pets_TypeChart(modifier, n)
	local chart = {}
	for atk = 1, n do
		chart[atk] = {}
		for def = 1, n do
			chart[atk][def] = modifier(atk, def) or 1
		end
	end
	return chart
end

local function Mod(chart, atk, def)
	local row = atk and chart[atk]
	return row and def and row[def] or 1
end

-- Attack types that are strong against defType, lowest first.
function ns.Pets_Strong(chart, defType)
	local out = {}
	for atk = 1, #chart do
		if Mod(chart, atk, defType) > 1 then
			out[#out + 1] = atk
		end
	end
	return out
end

-- Attack types that are weak against defType (the pet "resists" them), lowest first.
function ns.Pets_Resists(chart, defType)
	local out = {}
	for atk = 1, #chart do
		if Mod(chart, atk, defType) < 1 then
			out[#out + 1] = atk
		end
	end
	return out
end

-- Score of `pet` against the active `enemy`: +1 per usable ability strong against it, -1 per weak one; +1 per enemy
-- attack the pet resists, -1 per enemy attack it is weak to. Abilities without strong/weak hints don't count.
function ns.Pets_Matchup(chart, pet, enemy)
	local info = { strong = 0, weak = 0, resists = 0, weakTo = 0 }
	for _, a in ipairs(pet.abilities or {}) do
		if a.type and not a.noHints and a.usable ~= false then
			local m = Mod(chart, a.type, enemy.type)
			if m > 1 then
				info.strong = info.strong + 1
			elseif m < 1 then
				info.weak = info.weak + 1
			end
		end
	end
	for _, a in ipairs(enemy.abilities or {}) do
		if a.type and not a.noHints then
			local m = Mod(chart, a.type, pet.type)
			if m > 1 then
				info.weakTo = info.weakTo + 1
			elseif m < 1 then
				info.resists = info.resists + 1
			end
		end
	end
	return info.strong - info.weak + info.resists - info.weakTo, info
end

-- Best ally against the enemy. opts = { active, leveling }: dead pets and the leveling pet are skipped, a tie keeps
-- the active pet, otherwise the first highest wins.
-- Returns bestIndex (nil when no pet can fight), scores = { [i] = { score, info } }.
function ns.Pets_Best(chart, allies, enemy, opts)
	opts = opts or {}
	local scores, best = {}, nil
	for i, p in ipairs(allies) do
		if not p.dead and i ~= opts.leveling then
			local score, info = ns.Pets_Matchup(chart, p, enemy)
			scores[i] = { score = score, info = info }
			if not best or score > scores[best].score
				or (score == scores[best].score and i == opts.active) then
				best = i
			end
		end
	end
	return best, scores
end

-- { index, info, score } when another pet beats the active one by PETS_SWAP_MARGIN, else nil.
function ns.Pets_SwapAdvice(chart, allies, enemy, opts)
	local best, scores = ns.Pets_Best(chart, allies, enemy, opts)
	if not best or best == opts.active then
		return nil
	end
	local active = allies[opts.active]
	local activeScore = active and not active.dead and ns.Pets_Matchup(chart, active, enemy) or nil
	if activeScore and scores[best].score - activeScore < ns.PETS_SWAP_MARGIN then
		return nil
	end
	return { index = best, info = scores[best].info, score = scores[best].score }
end

-- encounters = { [xufuID] = { npcs = {...} } } -> { [npcID] = { xufuID, ... } } (ids sorted).
function ns.Pets_IndexEncounters(encounters)
	local index = {}
	for id, e in pairs(encounters) do
		for _, npc in ipairs(e.npcs or {}) do
			index[npc] = index[npc] or {}
			table.insert(index[npc], id)
		end
	end
	for _, ids in pairs(index) do
		table.sort(ids)
	end
	return index
end

-- An enemy team as a key that doesn't depend on slot order.
function ns.Pets_Signature(speciesList)
	local copy = {}
	for i, s in ipairs(speciesList) do
		copy[i] = s
	end
	table.sort(copy)
	return table.concat(copy, ",")
end

-- Team picking -------------------------------------------------------------------------------------------------

local function Alive(p)
	return (p.health or 0) > 0
end

-- Is a better than b for a team slot? Level 25 first, then rarity, then health, then "already in this slot".
-- (Living pets go before dead ones in Pick.)
local function Better(a, b, slotted)
	local a25, b25 = a.level >= ns.PETS_MAX_LEVEL, b.level >= ns.PETS_MAX_LEVEL
	if a25 ~= b25 then
		return a25
	end
	if a.level ~= b.level then
		return a.level > b.level
	end
	if (a.rarity or 0) ~= (b.rarity or 0) then
		return (a.rarity or 0) > (b.rarity or 0)
	end
	local ah, bh = a.health / math.max(a.maxHealth or 1, 1), b.health / math.max(b.maxHealth or 1, 1)
	if ah ~= bh then
		return ah > bh
	end
	return a.guid == slotted and b.guid ~= slotted
end

-- The best unused pet that matches; a living one if there is one, else a dead one (so the card can say it's dead and
-- Heal fixes it, rather than calling it missing).
local function Pick(owned, used, slotted, match)
	local best, dead
	for _, p in ipairs(owned) do
		if not used[p.guid] and match(p) then
			if Alive(p) then
				if not best or Better(p, best, slotted) then
					best = p
				end
			elseif not dead or Better(p, dead, slotted) then
				dead = p
			end
		end
	end
	return best or dead
end

-- team.pets = { tag x3 } (Strings.lua tags). current = { [slot] = guid }. opts = { leveling = guid }.
-- Returns picks = { [slot] = { guid, abilities = { id|nil x3 }, dead } | { keep = true } },
-- missing = { { slot, species, another } } (another: you own that species, just not one more copy).
-- Ability digit d (1 or 2) in tier i is the species' ability i (d = 1) or i + 3 (d = 2); 0 leaves the tier alone.
function ns.Pets_PickTeam(team, owned, current, opts)
	opts = opts or {}
	local picks, missing, used = {}, {}, {}
	-- Pets the team names by species or as the leveling pet are taken first, so a random slot can't take them.
	local order = {}
	for slot = 1, 3 do
		local tag = team.pets[slot]
		if tag and tag.kind ~= "random" then
			order[#order + 1] = slot
		end
	end
	for slot = 1, 3 do
		local tag = team.pets[slot]
		if tag and tag.kind == "random" then
			order[#order + 1] = slot
		end
	end
	for slot = 1, 3 do
		picks[slot] = { keep = true }
	end
	for _, slot in ipairs(order) do
		local tag = team.pets[slot]
		local chosen
		if tag.kind == "species" then
			chosen = Pick(owned, used, current[slot], function(p)
				return p.species == tag.species
			end)
			if not chosen then
				local another
				for _, p in ipairs(owned) do
					another = another or (p.species == tag.species) or nil
				end
				missing[#missing + 1] = { slot = slot, species = tag.species, another = another }
			end
		elseif tag.kind == "random" then
			chosen = Pick(owned, used, current[slot], function(p)
				return tag.type == 0 or p.type == tag.type
			end)
		elseif tag.kind == "leveling" and opts.leveling then
			for _, p in ipairs(owned) do
				if p.guid == opts.leveling and not used[p.guid] then
					chosen = p
				end
			end
		end
		if chosen then
			used[chosen.guid] = true
			local abilities = {}
			if tag.kind == "species" then
				for tier = 1, 3 do
					local d = tag.abilities[tier]
					if d == 1 or d == 2 then
						abilities[tier] = chosen.abilities and chosen.abilities[tier + (d - 1) * 3]
					end
				end
			end
			picks[slot] = { guid = chosen.guid, abilities = abilities, dead = not Alive(chosen) or nil }
		end
	end
	table.sort(missing, function(a, b)
		return a.slot < b.slot
	end)
	return picks, missing
end

-- loadout = { [slot] = { level, health, maxHealth } | nil }. opts = { leveling = slot, minLevel = 25 }.
-- Problems in slot order: { kind = "empty" | "dead" | "low" | "hurt", slot }. One per slot, worst first.
function ns.Pets_Readiness(loadout, opts)
	opts = opts or {}
	local minLevel = opts.minLevel or ns.PETS_MAX_LEVEL
	local problems = {}
	for slot = 1, 3 do
		local p = loadout[slot]
		local kind
		if not p then
			kind = "empty"
		elseif (p.health or 0) <= 0 then
			kind = "dead"
		elseif p.level < minLevel and slot ~= opts.leveling then
			kind = "low"
		elseif p.health < (p.maxHealth or p.health) then
			kind = "hurt"
		end
		if kind then
			problems[#problems + 1] = { kind = kind, slot = slot }
		end
	end
	return problems
end

-- First queued pet you still own that's under 25, and the queue without the pets that are done or gone.
function ns.Pets_NextLeveling(queue, owned)
	local byGuid = {}
	for _, p in ipairs(owned) do
		byGuid[p.guid] = p
	end
	local cleaned = {}
	for _, guid in ipairs(queue) do
		local p = byGuid[guid]
		if p and p.level < ns.PETS_MAX_LEVEL then
			cleaned[#cleaned + 1] = guid
		end
	end
	return cleaned[1], cleaned
end

-- Xu-Fu notes -------------------------------------------------------------------------------------------------

-- Xu-Fu's exported notes start with "Strategy added by <author>".
function ns.Pets_ParseAuthor(notes)
	if type(notes) ~= "string" then
		return nil
	end
	local author = notes:match("^%s*Strategy added by ([^\n]+)")
	return author and author:gsub("%s+$", "") or nil
end

local ENTITIES = { nbsp = " ", lt = "<", gt = ">", quot = '"', apos = "'", ["#39"] = "'" }

function ns.Pets_Unescape(text)
	text = text:gsub("&(#?%w+);", function(name)
		if ENTITIES[name] then
			return ENTITIES[name]
		end
		local code = name:match("^#(%d+)$")
		if code and tonumber(code) < 128 then
			return string.char(tonumber(code))
		end
	end)
	return (text:gsub("&amp;", "&"))
end

-- Forum markup out of the notes: [url=...]text[/url] keeps the text; [b], [i], [u] and their closers go.
function ns.Pets_CleanNotes(notes)
	local text = notes:gsub("%[url=[^%]]*%](.-)%[/url%]", "%1")
	text = text:gsub("%[/?[biuBIU]%]", "")
	return ns.Pets_Unescape(text)
end
