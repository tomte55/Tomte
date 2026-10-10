local addonName, ns = ...

-- Collect here: the data. Once per session the mount and pet catalogs are read a few milliseconds per frame (only
-- uncollected ones whose source names a zone are kept), then the achievement index rides the shared achievement
-- walk (Achievements/Walk.lua): lower-case "name\ndescription" of every achievement the account hasn't completed.
-- ns.Collect_ForMap answers for a map from those, cached per map until something changes. Journal filters are never
-- touched. Parsing and matching are in Data.lua.

local BUDGET_MS = 4
local MAX_SPECIES = 6000 -- battle pet species IDs are read 1..MAX_SPECIES
local WALK_KEY = "collect"

local mounts, pets = {}, {} -- { kind, id, spellID, name, icon, source, parsed }
local achIndex = {} -- [achievementID] = lower-case "name\ndescription"
local pending -- achievement index being built
local ready = { mounts = false, pets = false, achievements = false }
local build -- { phase = "mounts" | "pets", ids, i }
local cache = {} -- [mapID] = entries
local running = false
local onChanged = function() end

local builder = CreateFrame("Frame")
builder:Hide()

local function Changed()
	wipe(cache)
	onChanged()
end

function ns.Collect_SetChanged(fn)
	onChanged = fn
end

-- Catalogs ---------------------------------------------------------------------------------------------------------

local function AddMount(mountID)
	local name, spellID, icon, _, _, _, _, _, _, shouldHideOnChar, isCollected = C_MountJournal.GetMountInfoByID(mountID)
	if not name or isCollected or shouldHideOnChar then
		return
	end
	local _, _, source = C_MountJournal.GetMountInfoExtraByID(mountID)
	local parsed = ns.Collect_ParseSource(source)
	if #parsed.zones > 0 then
		mounts[#mounts + 1] = { kind = "mount", id = mountID, spellID = spellID, name = name, icon = icon,
			source = source, parsed = parsed }
	end
end

local function AddPet(speciesID)
	-- pcall: an unused species ID may error instead of returning nothing.
	local ok, name, icon, _, _, sourceText, _, _, _, _, _, obtainable = pcall(C_PetJournal.GetPetInfoBySpeciesID, speciesID)
	if not ok or not name or not obtainable then
		return
	end
	local owned = C_PetJournal.GetNumCollectedInfo(speciesID)
	if owned and owned > 0 then
		return
	end
	local parsed = ns.Collect_ParseSource(sourceText)
	if #parsed.zones > 0 then
		pets[#pets + 1] = { kind = "pet", id = speciesID, name = name, icon = icon, source = sourceText, parsed = parsed }
	end
end

local function VisitAchievement(id)
	local _, name, _, completed, _, _, _, description = GetAchievementInfo(id)
	if name and not completed then
		pending[id] = (name .. "\n" .. (description or "")):lower()
	end
end

local function WalkFinished()
	achIndex, pending = pending or {}, nil
	ready.achievements = true
	Changed()
end

local function StartWalk()
	pending = {}
	ns.AchWalk_Join(WALK_KEY, { visit = VisitAchievement, finish = WalkFinished })
end

builder:SetScript("OnUpdate", function(self)
	local deadline = debugprofilestop() + BUDGET_MS
	while debugprofilestop() < deadline do
		if build.phase == "mounts" then
			local mountID = build.ids[build.i]
			if mountID then
				AddMount(mountID)
				build.i = build.i + 1
			else
				ready.mounts = true
				build.phase, build.i = "pets", 1
				Changed()
			end
		else
			if build.i <= MAX_SPECIES then
				AddPet(build.i)
				build.i = build.i + 1
			else
				ready.pets = true
				build = nil
				self:Hide()
				Changed()
				StartWalk()
				return
			end
		end
	end
end)

function ns.Collect_Start()
	if running then
		return
	end
	running = true
	wipe(mounts)
	wipe(pets)
	wipe(achIndex)
	ready.mounts, ready.pets, ready.achievements = false, false, false
	build = { phase = "mounts", ids = C_MountJournal.GetMountIDs() or {}, i = 1 }
	builder:Show()
end

function ns.Collect_Stop()
	running = false
	build, pending = nil, nil
	builder:Hide()
	ns.AchWalk_Leave(WALK_KEY)
	wipe(mounts)
	wipe(pets)
	wipe(achIndex)
	wipe(cache)
	ready.mounts, ready.pets, ready.achievements = false, false, false
end

-- { mounts, pets, achievements (each true when ready), progress 0..1 }
function ns.Collect_State()
	local progress = 0
	if ready.mounts then
		progress = progress + 1
	elseif build and build.phase == "mounts" then
		progress = progress + (build.i - 1) / math.max(#build.ids, 1)
	end
	if ready.pets then
		progress = progress + 1
	elseif build and build.phase == "pets" then
		progress = progress + (build.i - 1) / MAX_SPECIES
	end
	if ready.achievements then
		progress = progress + 1
	else
		progress = progress + (ns.AchWalk_Progress(WALK_KEY) or 0)
	end
	return { mounts = ready.mounts, pets = ready.pets, achievements = ready.achievements, progress = progress / 3 }
end

local StillMissing

-- An achievement was earned, or a mount or pet learned: the lists follow. Only entries of that kind leave the
-- cached maps; their achievement matching (the slow part) is kept.
function ns.Collect_Earned(kind, id)
	if kind == "ach" and id then
		achIndex[id] = nil
	end
	for _, entries in pairs(cache) do
		for i = #entries, 1, -1 do
			local e = entries[i]
			if e.kind == kind and (kind == "ach" and e.id == id or kind ~= "ach" and not StillMissing(e)) then
				table.remove(entries, i)
			end
		end
	end
	onChanged()
end

-- Maps -------------------------------------------------------------------------------------------------------------

-- A dungeon's maps are often named after a floor; sources and achievements name the instance. EJ_GetInstanceForMap
-- takes a uiMapID; EJ_GetInstanceInfo with an ID doesn't change the journal's selection.
local function InstanceName(mapID, info)
	if info.mapType ~= Enum.UIMapType.Dungeon then
		return nil
	end
	local instanceID = EJ_GetInstanceForMap(mapID)
	local name = instanceID and instanceID > 0 and EJ_GetInstanceInfo(instanceID)
	return name ~= "" and name or nil
end

-- [lower-case name] = name: the map, everything under it and its dungeon entrances (Teleports' list).
local function NameSet(mapID, extra)
	local set = {}
	for _, name in ipairs(ns.Tp_MapNames(mapID).names) do
		set[name:lower()] = set[name:lower()] or name
	end
	if extra then
		set[extra:lower()] = set[extra:lower()] or extra
	end
	return set
end

-- What one map is matched against: { { set, zone } } for mounts and pets (zone: the name shown on rows in a
-- continent view) and the names an achievement has to mention.
local function Groups(mapID, info, kind)
	if kind == "zone" then
		local instance = InstanceName(mapID, info)
		return { { set = NameSet(mapID, instance) } }, { info.name, instance }
	end
	local groups = { { set = { [info.name:lower()] = info.name }, zone = info.name } }
	local achNames = { info.name }
	for _, child in ipairs(C_Map.GetMapChildrenInfo(mapID, Enum.UIMapType.Zone) or {}) do
		groups[#groups + 1] = { set = NameSet(child.mapID), zone = child.name }
		achNames[#achNames + 1] = child.name
	end
	return groups, achNames
end

function StillMissing(e)
	if e.kind == "mount" then
		local isCollected = select(11, C_MountJournal.GetMountInfoByID(e.id))
		return not isCollected
	end
	local owned = C_PetJournal.GetNumCollectedInfo(e.id)
	return not owned or owned == 0
end

local function AddMatches(entries, list, groups)
	for _, e in ipairs(list) do
		for _, g in ipairs(groups) do
			if ns.Collect_MatchZones(e.parsed.zones, g.set) then
				if StillMissing(e) then
					entries[#entries + 1] = { kind = e.kind, id = e.id, spellID = e.spellID, name = e.name, icon = e.icon,
						source = e.source, line = e.parsed.line, drop = e.parsed.drop, zone = g.zone }
				end
				break
			end
		end
	end
end

local function AddAchievements(entries, achNames)
	local names = {}
	for i, name in ipairs(achNames) do
		names[i] = name:lower()
	end
	for id, text in pairs(achIndex) do
		if ns.Collect_LowerMentions(text, names) then
			local _, name, points, completed, _, _, _, _, _, icon = GetAchievementInfo(id)
			if name and not completed then
				entries[#entries + 1] = { kind = "ach", id = id, name = name, icon = icon, points = points }
			elseif completed then
				achIndex[id] = nil
			end
		end
	end
end

-- Progress is read live for the achievements a map lists (matching is cached, progress isn't); completed ones
-- leave the list.
function ns.Collect_ReadProgress(entries)
	for i = #entries, 1, -1 do
		local e = entries[i]
		if e.kind == "ach" then
			local completed = select(4, GetAchievementInfo(e.id))
			if completed then
				table.remove(entries, i)
				achIndex[e.id] = nil
			else
				local percent, _, _, _, have, need = ns.Ach_Percent(ns.Ach_ReadCriteria(e.id))
				e.percent, e.done, e.total = percent or 0, have, need
			end
		end
	end
end

-- entries for a viewed map, the listed map's name and kind; nil for the world and cosmic maps.
function ns.Collect_ForMap(viewedMapID)
	local mapID, info, kind = ns.MapTabs_ResolveMap(viewedMapID)
	if not mapID then
		return nil
	end
	local entries = cache[mapID]
	if not entries then
		entries = {}
		local groups, achNames = Groups(mapID, info, kind)
		AddMatches(entries, mounts, groups)
		AddMatches(entries, pets, groups)
		AddAchievements(entries, achNames)
		cache[mapID] = entries
	end
	return entries, info.name, kind, mapID
end

-- The names a viewed map is matched with, for /tomte collect here.
function ns.Collect_MapNames(viewedMapID)
	local mapID, info, kind = ns.MapTabs_ResolveMap(viewedMapID)
	if not mapID then
		return nil
	end
	local groups, achNames = Groups(mapID, info, kind)
	local names = {}
	for _, g in ipairs(groups) do
		for _, name in pairs(g.set) do
			names[#names + 1] = name
		end
	end
	table.sort(names)
	return names, achNames
end

-- Vignettes --------------------------------------------------------------------------------------------------------

local function Secret(value)
	return issecretvalue ~= nil and issecretvalue(value)
end

-- Pins the rare and tracks it (like /way). Prefers the map you stand on: a continent can't take a map pin.
function ns.Collect_Waypoint(upNow, name)
	local mapID, x, y = upNow.mapID, upNow.x, upNow.y
	local playerMap = C_Map.GetBestMapForUnit("player")
	local pos = playerMap and C_VignetteInfo.GetVignettePosition(upNow.guid, playerMap)
	if pos and not Secret(pos.x) and C_Map.CanSetUserWaypointOnMap(playerMap) then
		mapID, x, y = playerMap, pos.x, pos.y
	end
	if not C_Map.CanSetUserWaypointOnMap(mapID) then
		ns.Print("can't place a map pin there.")
		return
	end
	C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(mapID, x, y))
	C_SuperTrack.SetSuperTrackedUserWaypoint(true)
	ns.Print(("tracking %s."):format(name or "the rare"))
end

-- Marks entries whose drop is a vignette up right now: e.upNow = { x, y, mapID, guid }. Returns { { entry, guid, name } }.
function ns.Collect_ApplyVignettes(entries, mapID)
	local byDrop = {}
	for _, e in ipairs(entries) do
		e.upNow = nil
		if e.drop then
			local key = e.drop:lower()
			byDrop[key] = byDrop[key] or {}
			table.insert(byDrop[key], e)
		end
	end
	local found = {}
	if not next(byDrop) then
		return found
	end
	for _, guid in ipairs(C_VignetteInfo.GetVignettes() or {}) do
		local info = C_VignetteInfo.GetVignetteInfo(guid)
		if info and not Secret(info.name) and info.name and not info.isDead then
			local list = byDrop[info.name:lower()]
			local pos = list and C_VignetteInfo.GetVignettePosition(guid, mapID)
			if pos and not Secret(pos.x) then
				for _, e in ipairs(list) do
					e.upNow = { x = pos.x, y = pos.y, mapID = mapID, guid = guid }
					found[#found + 1] = { entry = e, guid = guid, name = info.name }
				end
			end
		end
	end
	return found
end
