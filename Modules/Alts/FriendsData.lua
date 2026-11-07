local addonName, ns = ...

-- Friend crafting: pure logic (no WoW API calls; unit-tested in tests/test_alts_friends.lua). What a player shares
-- with friends about their characters' crafting (Friend sharing's per-friend "crafts" set), friends' characters merged
-- into the Crafting tab's search, and craft requests between friends: their states and messages. The game side is
-- Friends.lua, the mailbox block FriendMail.lua, the Requests section RequestsSection.lua.
--
-- Payload, records ending in ";":
--   c<name>,<realm>,<faction A|H|>,<class>,<level>;           a character (the next p records are its professions)
--   p<base>,<skill>,<max>=<recipeID>.<recipeID>...;            a profession and the recipes it knows
--   r<recipeID>,<itemID>,<base>,<name>=<itemID>:<qty>.<...>;   a recipe, once: what it makes and needs
-- Names and realms have the separators replaced by spaces, so a record always reads.

local NAME_SEPARATORS = "[;,:=%.%^|]"
local HASH_MOD = 2147483648 -- 2^31: djb2 stays exact in Lua 5.1 doubles (as Flight's ShareData.lua)
local MAX_AMOUNT = 200 -- a request asks for at most this many crafts

-- Requests move forward only: each event leads to a state, taken when it's further along than the request is. Answers
-- can be lost or overtake each other (Battle.net delivery isn't ordered, and only the latest answer is resent to a
-- friend who was offline), so a later state skips the ones before it and a late "got" changes nothing. Declined and
-- cancelled end any open request.
local RANK = { waiting = 1, sent = 2, delivered = 3, accepted = 4, made = 5 } -- the open states
local LEADS_TO = { sent = "sent", got = "delivered", accepted = "accepted", made = "made", done = "done" }
local ENDS = { declined = "declined", cancel = "cancelled" }
local ANSWERS = { got = true, accepted = true, declined = true, made = true, done = true, cancel = true }

local function Clean(text)
	return (tostring(text or ""):gsub(NAME_SEPARATORS, " "))
end

local function SortedKeys(t)
	local keys = {}
	for k in pairs(t or {}) do
		keys[#keys + 1] = k
	end
	table.sort(keys)
	return keys
end

-- Export and import ------------------------------------------------------------------------------------------------

-- What this player shares: every character with professions (sorted by name) and each recipe they know, once.
-- chars and recipes as in TomteDB.alts (PlanData.lua).
function ns.AltsFriends_Export(chars, recipes)
	local list = {}
	for _, c in pairs(chars or {}) do
		if next(c.profs or {}) then
			list[#list + 1] = c
		end
	end
	table.sort(list, function(a, b)
		return (a.name or "") < (b.name or "")
	end)
	local out, used = {}, {}
	for _, c in ipairs(list) do
		local faction = c.faction == "Horde" and "H" or (c.faction == "Alliance" and "A" or "")
		out[#out + 1] = ("c%s,%s,%s,%s,%d;"):format(Clean(c.name), Clean(c.realm), faction, Clean(c.class),
			tonumber(c.level) or 0)
		for _, base in ipairs(SortedKeys(c.profs)) do
			local p = c.profs[base]
			local ids = SortedKeys(p.known)
			for _, id in ipairs(ids) do
				used[id] = true
			end
			out[#out + 1] = ("p%d,%d,%d=%s;"):format(base, tonumber(p.skill) or 0, tonumber(p.max) or 0,
				table.concat(ids, "."))
		end
	end
	for _, id in ipairs(SortedKeys(used)) do
		local r = recipes and recipes[id]
		if r then
			local mats = {}
			for _, slot in ipairs(r.reagents or {}) do
				local item = slot.items and slot.items[1]
				if item then
					mats[#mats + 1] = ("%d:%d"):format(item, tonumber(slot.qty) or 1)
				end
			end
			out[#out + 1] = ("r%d,%d,%d,%s=%s;"):format(id, tonumber(r.item) or 0, tonumber(r.base) or 0, Clean(r.name),
				table.concat(mats, "."))
		end
	end
	return table.concat(out)
end

-- The payload's revision for Friend sharing's hello: a hash of all of it, so friends ask again whenever it changed.
function ns.AltsFriends_Revision(payload)
	local h = 5381
	for i = 1, #payload do
		h = (h * 33 + payload:byte(i)) % HASH_MOD
	end
	return h
end

local function Numbers(text)
	local list = {}
	for n in (text or ""):gmatch("%d+") do
		list[#list + 1] = tonumber(n)
	end
	return list
end

-- A friend's payload: { chars = { { name, realm, faction ("A" | "H" | ""), class, level, profs = { [base] = { skill,
-- max, known = { [recipeID] = true } } } } }, recipes = { [recipeID] = { item, base, name, reagents = { { items =
-- { itemID }, qty } } } } }, or nil, reason.
function ns.AltsFriends_Import(payload)
	local data = { chars = {}, recipes = {} }
	local char
	for record in (payload or ""):gmatch("([^;]*);") do
		local kind, body = record:sub(1, 1), record:sub(2)
		if kind == "c" then
			local name, realm, faction, class, level = body:match("^([^,]*),([^,]*),([AH]?),([^,]*),(%d+)$")
			if not name or name == "" then
				return nil, "bad character"
			end
			char = { name = name, realm = realm, faction = faction, class = class, level = tonumber(level), profs = {} }
			data.chars[#data.chars + 1] = char
		elseif kind == "p" then
			local base, skill, max, ids = body:match("^(%d+),(%d+),(%d+)=([%d%.]*)$")
			if not (char and base) then
				return nil, "bad profession"
			end
			local known = {}
			for _, id in ipairs(Numbers(ids)) do
				known[id] = true
			end
			char.profs[tonumber(base)] = { base = tonumber(base), skill = tonumber(skill), max = tonumber(max),
				known = known }
		elseif kind == "r" then
			local id, item, base, name, mats = body:match("^(%d+),(%d+),(%d+),([^=]*)=([%d%.:]*)$")
			if not id then
				return nil, "bad recipe"
			end
			local reagents = {}
			for itemID, qty in mats:gmatch("(%d+):(%d+)") do
				reagents[#reagents + 1] = { items = { tonumber(itemID) }, qty = tonumber(qty) }
			end
			data.recipes[tonumber(id)] = { item = tonumber(item), base = tonumber(base), name = name, reagents = reagents }
		else
			return nil, "unknown record"
		end
	end
	if payload ~= "" and not payload:find(";$") then
		return nil, "not a crafts payload"
	end
	return data
end

-- Friends' characters ----------------------------------------------------------------------------------------------

-- A World of Warcraft: Forever realm without its server number: "CAMWOWEU4Realm5PvE" -> "CAMWOWEU4RealmPvE". There's
-- no realm to pick there, only a ruleset, and friends on one ruleset play together from different numbered servers
-- (seen in game: Realm5PvE and Realm3PvE). The ruleset stays in the name: players on another can't be reached.
function ns.AltsFriends_ForeverRealm(realm)
	return (tostring(realm or ""):gsub("[%s%-]", ""):gsub("Realm%d+", "Realm"))
end

-- Whether mail reaches a friend's character: your faction ("Horde" | "Alliance"; an unknown one on either side
-- counts as reachable) and a realm mail reaches (ns.Alts_Reachable; realms nil: unknown, reachable). realmKey
-- (optional): realms is keyed by it (AltsFriends_ForeverRealm on Forever).
function ns.AltsFriends_Reachable(c, faction, realms, realmKey)
	local theirs, mine = c.faction or "", (faction or ""):sub(1, 1)
	if theirs ~= "" and mine ~= "" and theirs ~= mine then
		return false
	end
	if realmKey then
		return not realms or not c.realm or c.realm == "" or realms[realmKey(c.realm)] == true
	end
	return ns.Alts_Reachable(c, realms)
end

-- Your characters and recipes with each friend's reachable characters added, as new tables (yours aren't changed).
-- friends = { [BattleTag] = { at, data (AltsFriends_Import's) } }; opts = { faction, realms, realmKey (as in
-- AltsFriends_Reachable), online = { [tag] = true } }.
-- A friend's character is keyed "friend:<tag>:<name>-<realm>" and carries friend = { tag, online, seen }; a recipe
-- only a friend knows is added with friend = true.
function ns.AltsFriends_Merge(chars, recipes, friends, opts)
	opts = opts or {}
	local c2, r2 = {}, {}
	for k, v in pairs(chars or {}) do
		c2[k] = v
	end
	for k, v in pairs(recipes or {}) do
		r2[k] = v
	end
	for tag, entry in pairs(friends or {}) do
		local data = entry.data or {}
		local shown = {} -- [recipeID] = true: known by one of this friend's characters that's shown
		for _, c in ipairs(data.chars or {}) do
			if ns.AltsFriends_Reachable(c, opts.faction, opts.realms, opts.realmKey) then
				local profs = {}
				for base, p in pairs(c.profs or {}) do
					profs[base] = { base = base, skill = p.skill, max = p.max, known = p.known }
					for id in pairs(p.known or {}) do
						shown[id] = true
					end
				end
				c2["friend:" .. tag .. ":" .. c.name .. "-" .. (c.realm or "")] = { name = c.name, realm = c.realm,
					faction = c.faction, class = c.class, level = c.level, profs = profs,
					friend = { tag = tag, online = (opts.online or {})[tag] == true, seen = entry.at } }
			end
		end
		for id, r in pairs(data.recipes or {}) do
			if shown[id] and not r2[id] then
				r2[id] = { name = r.name, item = r.item, base = r.base, reagents = r.reagents, friend = true }
			end
		end
	end
	return c2, r2
end

-- Requests ---------------------------------------------------------------------------------------------------------

-- A request: { id, mine (true: you asked), friend (BattleTag), recipeID, itemID, amount, mats (true: the asker mails
-- the materials), crafter, asker, askerRealm, at, state }. fields are copied; state defaults to "waiting".
function ns.AltsFriends_NewRequest(fields)
	local req = {}
	for k, v in pairs(fields or {}) do
		req[k] = v
	end
	req.state = req.state or "waiting"
	return req
end

-- Moves a request on by an event (sent, got, accepted, declined, made, done, cancel). False when it doesn't apply.
function ns.AltsFriends_Apply(req, event)
	local rank = RANK[req.state]
	if not rank then
		return false -- over already
	end
	local to = ENDS[event]
	if not to then
		to = LEADS_TO[event]
		if not to or (RANK[to] or math.huge) <= rank then
			return false
		end
	end
	req.state = to
	return true
end

-- Whether a request still needs something done (not done, declined or cancelled).
function ns.AltsFriends_Open(req)
	return RANK[req.state] ~= nil
end

-- How many items a request's crafts make: crafts times what one craft makes (the crafter's recipe's qMin; 1 unknown).
function ns.AltsFriends_ItemCount(req, recipe)
	return (req.amount or 1) * (recipe and tonumber(recipe.qMin) or 1)
end

local function FactionLetter(faction)
	return faction == "Horde" and "H" or (faction == "Alliance" and "A" or "")
end

-- The asker's faction goes last ("H", "A" or ""), so an ask from a Tomte without it still decodes.
function ns.AltsFriends_EncodeAsk(req)
	return ("%s;ask;%d;%d;%d;%d;%s;%s;%s;%s"):format(req.id, req.recipeID or 0, req.itemID or 0, req.amount or 1,
		req.mats and 1 or 0, Clean(req.crafter), Clean(req.asker), Clean(req.askerRealm), FactionLetter(req.askerFaction))
end

function ns.AltsFriends_EncodeAnswer(id, event)
	return id .. ";" .. event
end

-- A request message: { id, kind = "ask", recipeID, itemID, amount, mats, crafter, asker, askerRealm } or { id, kind =
-- an answer event }; nil for anything else.
function ns.AltsFriends_Decode(text)
	local id, kind, rest = (text or ""):match("^([^;]+);(%l+);?(.*)$")
	if not id then
		return nil
	end
	if kind == "ask" then
		local recipeID, itemID, amount, mats, crafter, asker, realm, faction =
			rest:match("^(%d+);(%d+);(%d+);([01]);([^;]*);([^;]*);([^;]*);?([AH]?)$")
		if not recipeID then
			return nil
		end
		return { id = id, kind = "ask", recipeID = tonumber(recipeID), itemID = tonumber(itemID),
			amount = math.min(math.max(tonumber(amount), 1), MAX_AMOUNT), mats = mats == "1", crafter = crafter,
			asker = asker, askerRealm = realm, askerFaction = faction }
	elseif ANSWERS[kind] and rest == "" then
		return { id = id, kind = kind }
	end
	return nil
end

-- An ask from a friend: stored as their request (delivered to you) the first time; a repeat (resent after a lost
-- answer) returns the stored one untouched. -> request, true when it's new.
function ns.AltsFriends_TakeAsk(requests, msg, tag, now)
	local old = requests[msg.id]
	if old then
		return old, false
	end
	local req = ns.AltsFriends_NewRequest({ id = msg.id, mine = false, friend = tag, recipeID = msg.recipeID,
		itemID = msg.itemID, amount = msg.amount, mats = msg.mats, crafter = msg.crafter, asker = msg.asker,
		askerRealm = msg.askerRealm, askerFaction = msg.askerFaction, at = now, state = "delivered" })
	requests[msg.id] = req
	return req, true
end

-- What the mailbox offers to send for requests, newest first: { { req, kind = "mats" | "item", to = { name, realm },
-- wants = { { itemID, n } } } }. "mats": your open request whose materials you said you'd mail and haven't yet (a
-- waiting one too: mail reaches offline characters); "item": a friend's request you've made and not yet sent.
-- recipes: yours merged with friends' (for the materials of a recipe only they know). opts = { faction, realms,
-- realmKey }: only
-- recipients the character at the mailbox can reach (AltsFriends_Reachable); nil: everyone.
function ns.AltsFriends_MailGroups(requests, recipes, opts)
	local groups = {}
	local function Add(g)
		if not opts or ns.AltsFriends_Reachable(g.to, opts.faction, opts.realms, opts.realmKey) then
			groups[#groups + 1] = g
		end
	end
	for _, req in pairs(requests or {}) do
		local open = ns.AltsFriends_Open(req)
		if req.mine and open and req.mats and not req.matsSent and req.state ~= "made" and not req.hidden then
			local wants = {}
			for _, m in ipairs(ns.AltsFriends_Materials(recipes[req.recipeID] or {}, req.amount)) do
				wants[#wants + 1] = { itemID = m.itemID, n = m.count }
			end
			if #wants > 0 then
				Add({ req = req, kind = "mats", wants = wants,
					to = { name = req.crafter, realm = req.crafterRealm, faction = req.crafterFaction or "" } })
			end
		elseif not req.mine and req.state == "made" and req.itemID and req.itemID > 0 then
			Add({ req = req, kind = "item",
				to = { name = req.asker, realm = req.askerRealm, faction = req.askerFaction or "" },
				wants = { { itemID = req.itemID, n = ns.AltsFriends_ItemCount(req, recipes[req.recipeID]) } } })
		end
	end
	table.sort(groups, function(a, b)
		return (a.req.at or 0) > (b.req.at or 0)
	end)
	return groups
end

-- A recipe's materials for amount crafts: { { itemID, count } } (each reagent's first item).
function ns.AltsFriends_Materials(recipe, amount)
	local list = {}
	for _, slot in ipairs(recipe.reagents or {}) do
		local item = slot.items and slot.items[1]
		if item then
			list[#list + 1] = { itemID = item, count = (slot.qty or 1) * (amount or 1) }
		end
	end
	return list
end
