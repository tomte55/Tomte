local addonName, ns = ...

-- Talent check: pure logic (no WoW API calls; unit-tested in tests/test_talents.lua). Which saved loadout a place
-- wants, when to offer a switch or to remember a hand switch, and the saved table's shape. Reading the game and the
-- card are in Talents.lua and Card.lua.

-- Kinds of place, in the order settings and lists show them.
ns.TALENTS_KINDS = { "world", "dungeon", "raid", "delve", "pvp" }
-- Kinds whose instances can have their own loadout (an override by instance ID).
local OVERRIDABLE = { dungeon = true, raid = true, delve = true }
-- As the place reads in a sentence ("for dungeons you use B") and as a list label.
local KIND_PHRASE = { world = "the open world", dungeon = "dungeons", raid = "raids", delve = "delves", pvp = "PvP" }
local KIND_LABEL = { world = "Open world", dungeon = "Dungeons", raid = "Raids", delve = "Delves", pvp = "PvP" }
local KIND_ORDER = {}
for i, kind in ipairs(ns.TALENTS_KINDS) do
	KIND_ORDER[kind] = i
end

-- Places ----------------------------------------------------------------------------------------------------------

-- instanceType, difficultyID from GetInstanceInfo() -> "world" | "dungeon" | "raid" | "delve" | "pvp" | nil (other
-- scenarios). ns.Check_ContentKind (Core/CheckData.lua) knows dungeons, raids and delves.
function ns.Talents_PlaceKind(instanceType, difficultyID)
	if instanceType == "none" then
		return "world"
	elseif instanceType == "pvp" or instanceType == "arena" then
		return "pvp"
	end
	return ns.Check_ContentKind(instanceType, difficultyID)
end

-- A place: { kind, instanceID, name } (instanceID and name only where overrides exist), or nil.
function ns.Talents_Place(instanceType, difficultyID, instanceID, name)
	local kind = ns.Talents_PlaceKind(instanceType, difficultyID)
	if not kind then
		return nil
	end
	if OVERRIDABLE[kind] and type(instanceID) == "number" and instanceID > 0 then
		return { kind = kind, instanceID = instanceID, name = name }
	end
	return { kind = kind }
end

-- "dungeon:2660" or "world:": one key per place, for "asked once" bookkeeping.
function ns.Talents_PlaceKey(place)
	return place.kind .. ":" .. (place.instanceID or "")
end

function ns.Talents_KindPhrase(kind)
	return KIND_PHRASE[kind] or kind
end

function ns.Talents_KindLabel(kind)
	return KIND_LABEL[kind] or kind
end

-- Saved table -----------------------------------------------------------------------------------------------------
-- char = { specs = { [specID] = spec } }
-- spec = { kinds = { [kind] = configID }, instances = { [instanceID] = { config = configID, name = "Ara-Kara" } } }

function ns.Talents_Spec(char, specID, create)
	char.specs = char.specs or {}
	local spec = char.specs[specID]
	if not spec and create then
		spec = { kinds = {}, instances = {} }
		char.specs[specID] = spec
	end
	if spec then
		spec.kinds = spec.kinds or {}
		spec.instances = spec.instances or {}
	end
	return spec
end

-- The loadout this place wants and where that comes from: configID, "instance" | "kind"; nil when nothing (still
-- existing) is saved. valid = { [configID] = true } for the spec's saved loadouts.
function ns.Talents_Wanted(spec, place, valid)
	if not (spec and place) then
		return nil
	end
	local override = place.instanceID and spec.instances[place.instanceID]
	if override and valid[override.config] then
		return override.config, "instance"
	end
	local id = spec.kinds[place.kind]
	if id and valid[id] then
		return id, "kind"
	end
	return nil
end

-- scope "kind": for every place of this kind (drops this instance's own choice, which would win otherwise);
-- "instance": only this instance.
function ns.Talents_Remember(spec, place, configID, scope)
	if scope == "instance" and place.instanceID then
		spec.instances[place.instanceID] = { config = configID, name = place.name }
	else
		spec.kinds[place.kind] = configID
		if place.instanceID then
			spec.instances[place.instanceID] = nil
		end
	end
end

-- Forgets saved choices whose loadout no longer exists. Only call with the spec's real list: an empty list can mean
-- "not loaded yet". Returns how many were forgotten.
function ns.Talents_Prune(spec, valid)
	local n = 0
	for kind, id in pairs(spec.kinds) do
		if not valid[id] then
			spec.kinds[kind] = nil
			n = n + 1
		end
	end
	for instanceID, entry in pairs(spec.instances) do
		if type(entry) ~= "table" or not valid[entry.config] then
			spec.instances[instanceID] = nil
			n = n + 1
		end
	end
	return n
end

-- Every saved choice of a character: { specID, kind, instanceID, name, config }, by specOrder (list of specIDs; other
-- specs after), then kind, then the kind itself before its instances (by name).
function ns.Talents_Entries(char, specOrder)
	local rank = {}
	for i, specID in ipairs(specOrder or {}) do
		rank[specID] = i
	end
	local list = {}
	for specID, spec in pairs(char.specs or {}) do
		for kind, id in pairs(spec.kinds or {}) do
			list[#list + 1] = { specID = specID, kind = kind, config = id }
		end
		for instanceID, entry in pairs(spec.instances or {}) do
			if type(entry) == "table" then
				list[#list + 1] = { specID = specID, instanceID = instanceID, name = entry.name, config = entry.config }
			end
		end
	end
	table.sort(list, function(a, b)
		local ra, rb = rank[a.specID] or 100 + a.specID, rank[b.specID] or 100 + b.specID
		if ra ~= rb then
			return ra < rb
		end
		local ia, ib = a.instanceID and 1 or 0, b.instanceID and 1 or 0
		if ia ~= ib then
			return ia < ib
		end
		if a.kind then
			return KIND_ORDER[a.kind] < KIND_ORDER[b.kind]
		end
		local na, nb = a.name or "", b.name or ""
		if na ~= nb then
			return na < nb
		end
		return a.instanceID < b.instanceID
	end)
	return list
end

-- Forgets one entry from Talents_Entries.
function ns.Talents_Forget(char, entry)
	local spec = ns.Talents_Spec(char, entry.specID)
	if not spec then
		return
	end
	if entry.instanceID then
		spec.instances[entry.instanceID] = nil
	else
		spec.kinds[entry.kind] = nil
	end
	if not next(spec.kinds) and not next(spec.instances) then
		char.specs[entry.specID] = nil
	end
end

-- Decisions -------------------------------------------------------------------------------------------------------
-- s = {
--   place = Talents_Place(...) or nil, spec = saved spec table or nil,
--   active = the selected loadout's configID or nil (Default loadout), starter = Starter Build active,
--   keyRunning = a Mythic+ key is running, valid = { [configID] = true }, count = how many saved loadouts,
--   learn = "Learn on its own" setting,
-- }

-- What to do now: { action = "none" | "learn" | "switch", reason, want, source }. reason is a key of REASONS.
function ns.Talents_Decide(s)
	if not s.place then
		return { action = "none", reason = "noPlace" }
	end
	if s.keyRunning then
		return { action = "none", reason = "keyRunning" }
	end
	if s.starter then
		return { action = "none", reason = "starter" }
	end
	if (s.count or 0) == 0 then
		return { action = "none", reason = "noLoadouts" }
	end
	local want, source = ns.Talents_Wanted(s.spec, s.place, s.valid)
	if not want then
		if s.active and s.valid[s.active] then
			if s.learn then
				return { action = "learn", reason = "learn", want = s.active }
			end
			return { action = "none", reason = "nothingSavedNoLearn" }
		end
		return { action = "none", reason = "nothingSaved" }
	end
	if s.active == want then
		return { action = "none", reason = "onIt", want = want, source = source }
	end
	return { action = "switch", reason = "wrong", want = want, source = source }
end

-- After a hand switch to configID: offer to remember it for this place? declined = { [placeKey .. "#" .. configID] =
-- true } (answered No this session). Returns true and what the place wanted before (nil when nothing).
function ns.Talents_ShouldOffer(s, configID, declined)
	if not s.place or s.starter or s.keyRunning or not configID or not s.valid[configID] then
		return false
	end
	local want = ns.Talents_Wanted(s.spec, s.place, s.valid)
	if want == configID then
		return false
	end
	if declined and declined[ns.Talents_PlaceKey(s.place) .. "#" .. configID] then
		return false
	end
	return true, want
end

local REASONS = {
	noPlace = "This isn't a place Talent check knows (it checks the open world, dungeons, raids, delves and PvP).",
	keyRunning = "A Mythic+ key is running: talents can't change now.",
	starter = "You're on the Starter Build: Talent check leaves it alone.",
	noLoadouts = "This spec has no saved loadouts.",
	learn = "Nothing saved for this place yet: Talent check remembers the loadout you're on.",
	nothingSavedNoLearn = "Nothing saved for this place, and learning on its own is off.",
	nothingSaved = "Nothing saved for this place, and you're not on a saved loadout to learn.",
	onIt = "You're on the loadout saved for this place.",
	wrong = "You're not on the loadout saved for this place: the card offers the switch.",
}

function ns.Talents_ReasonText(reason)
	return REASONS[reason] or reason
end

-- Texts -----------------------------------------------------------------------------------------------------------

-- How the place reads in a sentence: the instance's name for an override, else the kind ("dungeons").
function ns.Talents_PlacePhrase(place, source)
	if source == "instance" and place.name then
		return place.name
	end
	return ns.Talents_KindPhrase(place.kind)
end

-- "You're on A; for dungeons you use B." activeName nil: the Default loadout.
function ns.Talents_WrongText(activeName, wantName, placePhrase)
	local on = activeName and ("You're on " .. activeName) or "You're on no saved loadout"
	return ("%s; for %s you use %s."):format(on, placePhrase, wantName)
end

-- "Use A for dungeons from now on?"
function ns.Talents_OfferText(name, place)
	return ("Use %s for %s from now on?"):format(name, ns.Talents_KindPhrase(place.kind))
end

-- A saved entry as a settings or chat line: "Protection - Dungeons: Mythic build".
function ns.Talents_EntryText(entry, specName, loadoutName)
	local where = entry.instanceID and (entry.name or ("Instance " .. entry.instanceID))
		or ns.Talents_KindLabel(entry.kind)
	return ("%s - %s: %s"):format(specName, where, loadoutName)
end
