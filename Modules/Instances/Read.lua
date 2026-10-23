local addonName, ns = ...

-- Instances: reads the game into plain tables for Data.lua and the UI files (Badge, Entrance, Queue), and the one
-- place that changes difficulty. Makes the module's event bus (ns.Instances_Events). Nothing here is read in a way
-- that depends on combat: every value that may be secret is checked with ns.IsSecret first.

local IsSecret = ns.IsSecret
local D = ns.INSTANCES_DIFF

ns.Instances_Events = ns.NewEvents()

local function Num(v)
	if v == nil or IsSecret(v) or type(v) ~= "number" then
		return nil
	end
	return v
end

local function Bool(v)
	if IsSecret(v) then
		return nil
	end
	return v and true or false
end

local function Str(v)
	if v == nil or IsSecret(v) or type(v) ~= "string" then
		return nil
	end
	return v
end

-- Current instance ------------------------------------------------------------------------------------------------

local function DelveTier()
	if not (C_DelvesUI and C_DelvesUI.HasActiveDelve and C_DelvesUI.GetActiveDelveTier) then
		return nil
	end
	-- Blizzard's InstanceDifficultyMixin:IsInDelve: every lair is a delve, but a lair has no tier to show.
	if not C_DelvesUI.HasActiveDelve() or (C_DelvesUI.IsInLair and C_DelvesUI.IsInLair()) then
		return nil
	end
	local ok, info = pcall(C_DelvesUI.GetActiveDelveTier) -- "via party data": can be missing for a moment
	return ok and type(info) == "table" and Num(info.tier) or nil
end

local function WorldTier()
	if not (C_DelvesUI and C_DelvesUI.GetWorldTierDifficultyForActivePlayer and Enum.WorldTierDifficulty) then
		return nil
	end
	local tier = C_DelvesUI.GetWorldTierDifficultyForActivePlayer()
	if IsSecret(tier) then
		return nil
	end
	if tier == Enum.WorldTierDifficulty.Heroic then
		return "heroic"
	elseif tier == Enum.WorldTierDifficulty.Mythic then
		return "mythic"
	end
	return nil
end

-- The instance you're in, as Data.lua's Instances_BadgeText takes it, plus name, instanceID and difficultyName.
function ns.InstancesRead_Current()
	local name, instanceType, difficultyID, difficultyName, maxPlayers, _, _, instanceID, groupSize, lfgID,
		hasWorldTier = GetInstanceInfo()
	local info = {
		name = Str(name),
		instanceType = Str(instanceType) or "none",
		difficultyID = Num(difficultyID) or 0,
		difficultyName = Str(difficultyName),
		maxPlayers = Num(maxPlayers),
		instanceID = Num(instanceID),
		groupSize = Num(groupSize),
		lfgID = Num(lfgID),
	}
	if info.difficultyID > 0 then
		local _, _, isHeroic, isChallengeMode, displayHeroic, displayMythic, _, isLFR = GetDifficultyInfo(info.difficultyID)
		info.isHeroic, info.isChallengeMode = Bool(isHeroic), Bool(isChallengeMode)
		info.displayHeroic, info.displayMythic, info.isLFR = Bool(displayHeroic), Bool(displayMythic), Bool(isLFR)
	end
	if info.isChallengeMode or info.difficultyID == D.keystone then
		local level = C_ChallengeMode.GetActiveKeystoneInfo()
		info.keystone = Num(level)
	end
	if info.instanceType == "scenario" then
		info.delveTier = DelveTier()
	end
	if not IsSecret(hasWorldTier) and hasWorldTier then
		info.worldTier = WorldTier()
	end
	return info
end

-- Choosing difficulty -------------------------------------------------------------------------------------------

function ns.InstancesRead_GroupState()
	local inInstance = IsInInstance()
	return {
		inInstance = Bool(inInstance),
		inGroup = Bool(IsInGroup()),
		isLeader = Bool(UnitIsGroupLeader("player")),
		inInstanceGroup = Bool(IsInGroup(LE_PARTY_CATEGORY_INSTANCE)),
	}
end

-- true, or false and the reason (Data.lua's rule).
function ns.InstancesRead_CanChoose()
	return ns.Instances_CanChoose(ns.InstancesRead_GroupState())
end

-- The chosen dungeon, raid and legacy raid difficulty (what the next instance you enter will be).
function ns.InstancesRead_Chosen()
	return Num(GetDungeonDifficultyID()), Num(GetRaidDifficultyID()), Num(GetLegacyRaidDifficultyID())
end

-- kind:
--   "dungeon"     a dungeon difficulty (1, 2, 23)
--   "raid"        a raid difficulty (14, 15, 16), through Blizzard's own SetRaidDifficulties (Blizzard_UnitPopup,
--                 what the portrait menu calls), which keeps the legacy setting in step with Normal / Heroic
--   "legacy"      a size (3 or 4) for old raids, set on top of the current Normal / Heroic (Data's LegacyFor)
--   "legacyFull"  size and heroic together (3, 4, 5, 6): the raid difficulty is set to match first
-- The game says the change in chat itself. Returns false and the reason when you can't choose now.
function ns.InstancesRead_SetDifficulty(kind, difficultyID)
	local ok, reason = ns.InstancesRead_CanChoose()
	if not ok then
		return false, reason
	end
	if kind == "dungeon" then
		SetDungeonDifficultyID(difficultyID)
	elseif kind == "raid" then
		if SetRaidDifficulties then
			SetRaidDifficulties(true, difficultyID)
		else
			SetRaidDifficultyID(difficultyID)
		end
	elseif kind == "legacy" then
		local target = ns.Instances_LegacyFor(difficultyID, Num(GetRaidDifficultyID()))
		if not target then
			return false, ns.INSTANCES_LEGACY_MYTHIC_REASON
		end
		SetLegacyRaidDifficultyID(target)
	else
		-- Both set directly: SetRaidDifficulties reads the raid difficulty back, which hasn't changed yet here.
		local heroic = difficultyID == D.raid10Heroic or difficultyID == D.raid25Heroic
		SetRaidDifficultyID(heroic and D.raidHeroic or D.raidNormal)
		SetLegacyRaidDifficultyID(difficultyID)
	end
	return true
end

-- A difficulty's name in the client's language ("Heroic").
function ns.InstancesRead_DifficultyName(difficultyID)
	local name = difficultyID and GetDifficultyInfo(difficultyID)
	return Str(name) or tostring(difficultyID)
end

-- Lockouts ------------------------------------------------------------------------------------------------------

-- Your saves for one instance (InstanceID, as GetInstanceInfo and EJ_GetInstanceInfo give it), as Data.lua's
-- Instances_SaveFor takes them. RequestRaidInfo refreshes them (UPDATE_INSTANCE_INFO).
function ns.InstancesRead_Saves(instanceID)
	local saves = {}
	if not instanceID then
		return saves
	end
	for i = 1, GetNumSavedInstances() do
		local _, _, _, difficultyID, locked, extended, _, _, _, _, numEncounters, encounterProgress, _, savedID =
			GetSavedInstanceInfo(i)
		if Num(savedID) == instanceID then
			saves[#saves + 1] = {
				difficultyID = Num(difficultyID),
				locked = Bool(locked),
				extended = Bool(extended),
				numEncounters = Num(numEncounters),
				encounterProgress = Num(encounterProgress),
			}
		end
	end
	return saves
end

-- Instance portals ------------------------------------------------------------------------------------------------

local function EntrancesOn(mapID)
	local list = {}
	for _, e in ipairs(C_EncounterJournal.GetDungeonEntrancesForMap(mapID) or {}) do
		if e.position and e.journalInstanceID then
			list[#list + 1] = { x = e.position.x, y = e.position.y, journalInstanceID = e.journalInstanceID,
				name = e.name }
		end
	end
	return list
end

-- The map you're on and the instance portals on it: mapID, { { x, y, journalInstanceID, name } }. Only portals you
-- discovered are listed (C_EncounterJournal.GetDungeonEntrancesForMap). In a small map inside a zone (a town, a
-- cave) without portals of its own, the zone's map and its portals.
function ns.InstancesRead_Entrances()
	local mapID = C_Map.GetBestMapForUnit("player")
	if not mapID or IsSecret(mapID) then
		return nil, {}
	end
	local list = EntrancesOn(mapID)
	if #list == 0 then
		local info = C_Map.GetMapInfo(mapID)
		local parent = info and info.mapType and info.mapType > Enum.UIMapType.Zone and info.parentMapID
		if parent and parent > 0 then
			return parent, EntrancesOn(parent)
		end
	end
	return mapID, list
end

-- The player's spot on mapID (0..1) and the map's size in yards, or nil where the game gives no position.
function ns.InstancesRead_Position(mapID)
	local pos = mapID and C_Map.GetPlayerMapPosition(mapID, "player")
	if not pos then
		return nil
	end
	local x, y = pos:GetXY()
	if IsSecret(x, y) then
		return nil
	end
	local w, h = C_Map.GetMapWorldSize(mapID)
	return x, y, w, h
end

-- An instance from the Encounter Journal: { name, instanceID, isRaid, isLegacy }, without selecting it
-- (EJ_SelectInstance would change what the open journal shows). isLegacy: a raid entered at the 10 / 25 player
-- setting. dungeonAreaMapID is 0 for raids before Siege of Orgrimmar, the first raid on Normal / Heroic / Mythic
-- (warcraft.wiki.gg API_EJ_GetInstanceInfo; Timewalking raids have one).
function ns.InstancesRead_Journal(journalInstanceID)
	local name, _, _, _, _, _, areaMapID, _, _, instanceID, _, isRaid = EJ_GetInstanceInfo(journalInstanceID)
	if not name then
		return nil
	end
	isRaid = Bool(isRaid)
	return { name = name, instanceID = Num(instanceID), isRaid = isRaid, isLegacy = isRaid and Num(areaMapID) == 0 }
end

-- Queue -----------------------------------------------------------------------------------------------------------

-- The Dungeon Finder queue you're waiting in (QueueStatusEntry_SetUpLFG reads the same): { category, name, needs,
-- totals, average, queuedTime } or nil. needs/totals are nil for queues without roles (scenarios).
function ns.InstancesRead_Queue()
	for category = 1, NUM_LE_LFG_CATEGORYS do
		local mode = GetLFGMode(category)
		if mode == "queued" then
			local hasData, _, tankNeeds, healerNeeds, dpsNeeds, totalTanks, totalHealers, totalDPS, _, _, name,
				_, _, _, _, myWait, queuedTime = GetLFGQueueStats(category)
			if hasData and not IsSecret(hasData) then
				local q = { category = category, name = Str(name), average = Num(myWait), queuedTime = Num(queuedTime) }
				if Num(totalTanks) and Num(totalHealers) and Num(totalDPS) and category ~= LE_LFG_CATEGORY_SCENARIO then
					q.needs = { tank = Num(tankNeeds), healer = Num(healerNeeds), dps = Num(dpsNeeds) }
					q.totals = { tank = totalTanks, healer = totalHealers, dps = totalDPS }
				end
				return q
			end
		end
	end
	return nil
end

-- Dungeon Finder's random dungeons, as Data.lua's Instances_PickHoliday takes them.
function ns.InstancesRead_RandomDungeons()
	local list = {}
	for i = 1, GetNumRandomDungeons() do
		local id = GetLFGRandomDungeonInfo(i)
		local isHoliday = select(16, GetLFGRandomDungeonInfo(i))
		local isTimeWalker = select(19, GetLFGRandomDungeonInfo(i))
		local joinable = id and IsLFGDungeonJoinable(id)
		if id then
			list[#list + 1] = { id = id, isHoliday = isHoliday and true or false,
				isTimeWalker = isTimeWalker and true or false, joinable = joinable and true or false }
		end
	end
	return list
end
