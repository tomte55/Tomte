local addonName, ns = ...

-- Tooltip extras: pure logic (no WoW API calls; unit-tested in tests/test_tips.lua). Merging the per-expansion data
-- (Data/<Expansion>/Tips.lua), and the text of each line: reputation standing, reagent counts, the key a chest
-- needs, vendor places and choice window counts. The game is read in Read.lua, lines are added in Tooltip.lua.

local floor = math.floor

-- One lookup of a data kind ("repSpells", "vendors", ...) from every expansion's tips table. Every kind is keyed by
-- a game ID (item, spell, choice), so all expansions can share one lookup: a War Within token still shows on a
-- Midnight character. sources: list of tips tables, oldest expansion first; a later one wins on a clash.
function ns.Tips_Merge(sources, kind)
	local merged = {}
	for _, tips in ipairs(sources) do
		for id, value in pairs(tips[kind] or {}) do
			merged[id] = value
		end
	end
	return merged
end

-- A repSpells value (one faction ID, or a list for a token that raises several) as a list.
function ns.Tips_FactionList(value)
	if type(value) == "table" then
		return value
	end
	return value and { value } or {}
end

-- Reputation --------------------------------------------------------------------------------------------------------

local function Progress(earned, threshold)
	return ns.Thousands(earned) .. " / " .. ns.Thousands(threshold)
end

-- rec (Read.lua's Tips_FactionRecord): kind "renown" | "friend" | "plain", level, maxLevel, standing (label text),
-- earned, threshold, maxed, paragon = { value, threshold, pending } or nil. Returns text, color role.
function ns.Tips_RepStatus(rec)
	local label
	if rec.kind == "renown" then
		label = "Renown " .. (rec.level or 0)
	elseif rec.kind == "friend" and rec.level and rec.maxLevel and rec.maxLevel > 0 then
		label = (rec.standing or "") .. " (rank " .. rec.level .. " of " .. rec.maxLevel .. ")"
	else
		label = rec.standing or ""
	end
	local paragon = rec.paragon
	if rec.maxed and paragon and (paragon.threshold or 0) > 0 then
		if paragon.pending then
			return "Paragon: a reward is waiting for you", "success"
		end
		return "Paragon " .. Progress((paragon.value or 0) % paragon.threshold, paragon.threshold), "accent"
	end
	if rec.maxed then
		return label .. ", maxed: this gives you nothing more", "warning"
	end
	if (rec.threshold or 0) > 0 then
		return label .. "  " .. Progress(rec.earned or 0, rec.threshold), "text"
	end
	return label, "text"
end

-- Reagents ----------------------------------------------------------------------------------------------------------

-- reagents: { { name, have, need } } for one recipe. Returns rows { left, right, role } and how many times you can
-- make it now (0 when anything is short).
function ns.Tips_ReagentRows(reagents)
	local rows, crafts = {}, nil
	for _, r in ipairs(reagents) do
		local need = math.max(r.need or 1, 1)
		local have = r.have or 0
		local enough = have >= need
		rows[#rows + 1] = {
			left = r.name or "?",
			right = ns.Thousands(have) .. " / " .. ns.Thousands(need),
			role = enough and "text" or "danger",
		}
		local times = floor(have / need)
		crafts = crafts and math.min(crafts, times) or times
	end
	return rows, crafts or 0
end

function ns.Tips_CraftsText(crafts)
	if crafts > 1 then
		return "You have enough for " .. ns.Thousands(crafts) .. ".", "success"
	elseif crafts == 1 then
		return "You have enough for one.", "success"
	end
	return nil
end

-- Keys --------------------------------------------------------------------------------------------------------------

-- The key line on a locked chest or door: left, right, role.
function ns.Tips_KeyLine(keyName, have, need)
	need = need or 1
	have = have or 0
	return "Opens with " .. (keyName or "a key"), ns.Thousands(have) .. " / " .. ns.Thousands(need),
		have >= need and "success" or "danger"
end

-- Vendors -----------------------------------------------------------------------------------------------------------

-- A vendors value as a list of places ({ npc, name, map, x, y, ... } or { places = { ... } }).
function ns.Tips_VendorPlaces(value)
	if not value then
		return {}
	end
	return value.places or { value }
end

-- Which place a Ctrl-click pins: the nearest one on the map you're on, else the first.
-- mapID, x, y: the player's map and position (nil when unknown).
function ns.Tips_PickVendor(places, mapID, x, y)
	local best, bestDistance = 1, nil
	if not (mapID and x and y) then
		return best
	end
	for i, place in ipairs(places) do
		if place.map == mapID then
			local dx, dy = place.x - x, place.y - y
			local distance = dx * dx + dy * dy
			if not bestDistance or distance < bestDistance then
				best, bestDistance = i, distance
			end
		end
	end
	return best
end

-- "Mounts: Skedgit Cinderbangs, Undermine (second floor)". who: the NPC's or area's name (nil: only the place).
function ns.Tips_VendorText(place, who, mapName)
	local text = who and (mapName and (who .. ", " .. mapName) or who) or mapName or "?"
	if place.note then
		text = text .. " (" .. place.note .. ")"
	end
	if place.label then
		text = place.label .. ": " .. text
	end
	return text
end

-- Choice windows ----------------------------------------------------------------------------------------------------

-- What to count under a choice window: the token it takes (from data, first), then each option's item and
-- currency rewards, each once. options: C_PlayerChoice option infos (only rewardInfo is read).
-- token: { item = id } or { currency = id } or nil. Returns { { kind = "item" | "currency", id } }.
function ns.Tips_ChoiceEntries(options, token, limit)
	local list, seen = {}, {}
	local function add(kind, id)
		local key = id and (kind .. id)
		if key and not seen[key] and #list < (limit or math.huge) then
			seen[key] = true
			list[#list + 1] = { kind = kind, id = id }
		end
	end
	if token then
		if token.item then
			add("item", token.item)
		elseif token.currency then
			add("currency", token.currency)
		end
	end
	for _, option in ipairs(options or {}) do
		local rewards = option.rewardInfo or {}
		for _, item in ipairs(rewards.itemRewards or {}) do
			add("item", item.itemId)
		end
		for _, currency in ipairs(rewards.currencyRewards or {}) do
			add("currency", currency.currencyId)
		end
	end
	return list
end

-- "Radiant Echo: 12" for the choice window strip.
function ns.Tips_CountText(name, have)
	return (name or "?") .. ": " .. ns.Thousands(have or 0)
end
