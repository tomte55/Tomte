local addonName, ns = ...

-- Alts: forgetting a character across every saved store (pure logic, tested with plain Lua).

-- Forgetting a character --------------------------------------------------------------------------------------

-- Realm names compared the way GetNormalizedRealmName writes them (no spaces or dashes), case-insensitive.
local function SquashRealm(realm)
	return (tostring(realm or ""):lower():gsub("[%s%-]", ""))
end

-- The stored characters "name" or "name-realm" (any case) means, across stores (lists of [guid] = { name, realm }
-- tables, e.g. Alts' and Weekly's chars). Returns { matches = { { guid, name, realm } } (sorted by realm, never the
-- current character), playing = the current character matched too, ambiguous = matches on more than one realm
-- without a realm given }.
function ns.Alts_ForgetMatches(stores, input, currentGuid)
	input = tostring(input or ""):match("^%s*(.-)%s*$"):lower()
	local name, realm = input:match("^([^%-]+)%-(.+)$")
	name = name or input
	local found, playing = {}, false
	for _, store in ipairs(stores) do
		for guid, c in pairs(store or {}) do
			if type(c) == "table" and (c.name or ""):lower() == name
				and (not realm or SquashRealm(c.realm) == SquashRealm(realm)) then
				if guid == currentGuid then
					playing = true
				elseif found[guid] then
					found[guid].realm = found[guid].realm or c.realm
				else
					found[guid] = { guid = guid, name = c.name, realm = c.realm }
				end
			end
		end
	end
	local matches, realms, nRealms = {}, {}, 0
	for _, m in pairs(found) do
		matches[#matches + 1] = m
		local key = SquashRealm(m.realm)
		if not realms[key] then
			realms[key] = true
			nRealms = nRealms + 1
		end
	end
	table.sort(matches, function(a, b)
		if (a.realm or "") ~= (b.realm or "") then
			return (a.realm or "") < (b.realm or "")
		end
		return a.guid < b.guid
	end)
	return { matches = matches, playing = playing, ambiguous = not realm and nRealms > 1 }
end

-- Every per-character store in the saved variables (root = TomteDB), keyed by player GUID: module key, field.
local FORGET_STORES = {
	{ "alts", "chars" },
	{ "weekly", "chars" }, { "weekly", "hidden" },
	{ "ach", "cache" }, { "ach", "pins" },
	{ "gear", "weights" }, { "gear", "hinted" },
	{ "hunter", "chars" },
	{ "moments", "zones" },
	{ "way", "routes" },
}

-- Removes a character from every store in TomteDB: the ones above, the last session (sessionLast) and its finished
-- sessions in Recap's history and its entries in the Recent feed. Returns how many entries went.
function ns.Alts_ForgetEverywhere(root, guid)
	local removed = 0
	if not (root and guid) then
		return removed
	end
	for _, s in ipairs(FORGET_STORES) do
		local t = type(root[s[1]]) == "table" and root[s[1]][s[2]]
		if type(t) == "table" and t[guid] ~= nil then
			t[guid] = nil
			removed = removed + 1
		end
	end
	if type(root.sessionLast) == "table" and root.sessionLast[guid] ~= nil then
		root.sessionLast[guid] = nil
		removed = removed + 1
	end
	local lists = {
		type(root.recap) == "table" and root.recap.history,
		type(root.recent) == "table" and root.recent.entries,
	}
	for _, list in pairs(lists) do
		if type(list) == "table" then
			for i = #list, 1, -1 do
				if type(list[i]) == "table" and list[i].guid == guid then
					table.remove(list, i)
					removed = removed + 1
				end
			end
		end
	end
	return removed
end
