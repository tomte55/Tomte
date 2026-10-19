local addonName, ns = ...

-- Delves: readers for keys and shards, the Great Vault's World track and the delve companion. Each part is read
-- out of combat, debounced (DelvesRead_Dirty), inside xpcall (a failure keeps the old value and goes to BugSack once
-- per part per session), and cached for the page, the entrance note, Home and Next up. The companion calls are
-- Blizzard_DelvesCompanionConfiguration's own; nothing here changes a curio, a role or a tier. A companion level that
-- rises fires the "companion" moment.

local db
local state = {} -- { keys, keyLine, canCombine, vault, companion }
local dirty = {}
local timer
local primed = {} -- [faction] = true once read this session (the first read only stores the level)
local reported = {} -- [part] = true once its read error went to BugSack

local events = ns.Delves_Events

local function Def()
	local expansion = ns.ContentExpansion()
	return ns.Content_Get(expansion, "delves"), expansion
end

local function ReadKeys(def, expansion)
	local k = { perKey = def.shardsPerKey or 100 }
	local info = C_CurrencyInfo.GetCurrencyInfo(def.keyCurrency)
	k.keys = info and info.quantity or 0
	local s = def.shards or {}
	if s.currency then
		local c = C_CurrencyInfo.GetCurrencyInfo(s.currency)
		if c then
			k.shards = c.quantity or 0
			if (c.maxWeeklyQuantity or 0) > 0 then
				k.shardWeek = { n = c.quantityEarnedThisWeek or 0, of = c.maxWeeklyQuantity }
			end
		end
	elseif s.items then
		local n = 0
		for _, id in ipairs(s.items) do
			n = n + (C_Item.GetItemCount(id, true) or 0)
		end
		k.shards = n
	end
	k.earned = ns.Delves_Earned(ns.Weekly_ReadCurated and ns.Weekly_ReadCurated(expansion), "keys")
	return k
end

local function ReadVault(def)
	local world = Enum.WeeklyRewardChestThresholdType.World
	local activities = C_WeeklyRewards.GetActivities(world) or {}
	table.sort(activities, function(a, b)
		return a.index < b.index
	end)
	local slots, tierID = {}, nil
	for i, a in ipairs(activities) do
		slots[i] = { threshold = a.threshold, progress = a.progress, level = a.level }
		if not tierID and (a.activityTierID or 0) > 0 then
			tierID = a.activityTierID
		end
	end
	local runs = C_WeeklyRewards.GetSortedProgressForActivity(world, true) or {}
	local ladder, top
	if tierID then
		ladder, top = ns.Delves_Ladder(C_WeeklyRewards.GetNextActivitiesIncrease, 1, tierID)
	end
	if not top or top <= 1 then
		top = def.vaultTopTier or 8
	end
	return { slots = slots, runs = runs, ladder = ladder, top = top, plan = ns.Delves_VaultPlan(slots, runs, top) }
end

local function ActiveEntry(configID, nodeID)
	local node = nodeID and nodeID > 0 and C_Traits.GetNodeInfo(configID, nodeID)
	return node and node.activeEntry and node.activeEntry.entryID or nil
end

local function Curio(configID, nodeID)
	local entryID = ActiveEntry(configID, nodeID)
	local entry = entryID and C_Traits.GetEntryInfo(configID, entryID)
	local definition = entry and entry.definitionID and C_Traits.GetDefinitionInfo(entry.definitionID)
	local spellID = definition and (definition.overriddenSpellID or definition.spellID)
	local spell = spellID and C_Spell.GetSpellInfo(spellID)
	if not spell then
		return nil
	end
	local curio = { name = spell.name, icon = spell.iconID, spellID = spellID }
	local condID = entry.conditionIDs and entry.conditionIDs[1]
	local cond = condID and C_Traits.GetConditionInfo(configID, condID)
	if cond and cond.traitCondAccountElementID then
		curio.rarity = C_DelvesUI.GetCurioRarityByTraitCondAccountElementID(cond.traitCondAccountElementID)
		curio.link = curio.rarity and C_DelvesUI.GetCurioLink(spellID, curio.rarity)
	end
	return curio
end

local function SeasonData()
	local id = C_DelvesUI.GetDelvesFactionForSeason and C_DelvesUI.GetDelvesFactionForSeason() or 0
	return id, (id > 0 and C_MajorFactions.GetMajorFactionData(id) or nil)
end

local function ReadCompanion(def, expansion)
	local _, season = SeasonData()
	local useSeason = ns.Delves_PickCompanionSource(season, expansion) == "season"
	local companionID = useSeason and season.playerCompanionID or nil
	local faction = companionID and C_DelvesUI.GetFactionForCompanion(companionID) or def.companionFaction
	if faction == 0 then
		faction = def.companionFaction
	end
	local ranks = faction and C_GossipInfo.GetFriendshipReputationRanks(faction)
	local data = faction and C_Reputation.GetFactionDataByID(faction)
	if not (ranks and (ranks.maxLevel or 0) > 0 and data and data.name) then
		return nil
	end
	local c = { faction = faction, name = data.name, level = ranks.currentLevel or 0, maxLevel = ranks.maxLevel,
		companionID = companionID }
	local rep = C_GossipInfo.GetFriendshipReputation(faction)
	if rep and rep.nextThreshold then
		c.xp, c.xpMax = rep.standing - rep.reactionThreshold, rep.nextThreshold - rep.reactionThreshold
	end
	if useSeason and season.name then
		c.journey = { name = season.name, level = season.renownLevel, earned = season.renownReputationEarned,
			threshold = season.renownLevelThreshold, max = season.maxLevel }
	end
	if not companionID then
		return c
	end
	c.displayID = C_DelvesUI.GetCreatureDisplayInfoForCompanion(companionID)
	local tree = C_DelvesUI.GetTraitTreeForCompanion(companionID)
	local configID = tree and tree > 0 and C_Traits.GetConfigIDByTreeID(tree)
	if not configID then
		return c
	end
	c.roleNames = {}
	local subtreeRole = {}
	for enum, role in pairs(ns.DELVES_ROLE_BY_ENUM) do
		local sub = C_DelvesUI.GetRoleSubtreeForCompanion(enum, companionID)
		local info = sub and sub > 0 and C_Traits.GetSubTreeInfo(configID, sub)
		if info then
			c.roleNames[role] = info.name
			subtreeRole[sub] = role
		end
	end
	local roleEntry = ActiveEntry(configID, C_DelvesUI.GetRoleNodeForCompanion(companionID))
	local entry = roleEntry and C_Traits.GetEntryInfo(configID, roleEntry)
	if entry and entry.subTreeID then
		c.role = subtreeRole[entry.subTreeID]
		c.roleName = c.role and c.roleNames[c.role]
	end
	c.combat = Curio(configID, C_DelvesUI.GetCurioNodeForCompanion(Enum.CurioType.Combat, companionID))
	c.utility = Curio(configID, C_DelvesUI.GetCurioNodeForCompanion(Enum.CurioType.Utility, companionID))
	return c
end

-- Only after a level was stored and this faction was read once this session: a login (or a switch between the
-- season and the fallback faction) is never a level-up. A jump of more than MAX_LEVEL_STEP is data arriving late,
-- not a level-up.
local MAX_LEVEL_STEP = 3
local function CompanionMoment(c)
	local levels = db.companionLevel
	local last = levels[c.faction]
	if primed[c.faction] and last and last > 0 and c.level > last and c.level - last <= MAX_LEVEL_STEP then
		ns.Moments_Trigger("companion", { label = "Level " .. c.level, title = c.name, displayID = c.displayID })
	end
	levels[c.faction] = c.level
	primed[c.faction] = true
end

local READERS = {
	keys = function(def, expansion)
		local k = ReadKeys(def, expansion)
		state.keys = k
		state.keyLine, state.canCombine = ns.Delves_KeyLine(k)
	end,
	vault = function(def)
		state.vault = ReadVault(def)
	end,
	companion = function(def, expansion)
		if not C_DelvesUI then
			return
		end
		local c = ReadCompanion(def, expansion)
		state.companion = c
		if c then
			CompanionMoment(c)
		end
	end,
}
local ORDER = { "keys", "vault", "companion" }

-- No reads in combat, as a precaution: nothing here is needed mid-fight. The cache stays as it was until
-- PLAYER_REGEN_ENABLED.
local function ReadDirty()
	if InCombatLockdown() then
		events:Watch("read", "PLAYER_REGEN_ENABLED")
		return
	end
	local def, expansion = Def()
	if not def then
		wipe(dirty)
		wipe(state)
		return
	end
	for _, part in ipairs(ORDER) do
		if dirty[part] then
			dirty[part] = nil
			xpcall(function()
				READERS[part](def, expansion)
			end, function(err)
				if not reported[part] then
					reported[part] = true
					ns.errorHandler(err)
				end
			end)
		end
	end
	if ns.Delves_Changed then
		ns.Delves_Changed()
	end
end

events:On("read", "PLAYER_REGEN_ENABLED", function(self)
	self:Unwatch("read", "PLAYER_REGEN_ENABLED")
	ReadDirty()
end)

-- part: "keys", "vault", "companion" or nil for all. One read a second later (out of combat).
function ns.DelvesRead_Dirty(part)
	if part then
		dirty[part] = true
	else
		for _, p in ipairs(ORDER) do
			dirty[p] = true
		end
	end
	if not timer then
		timer = C_Timer.NewTimer(1, function()
			timer = nil
			ReadDirty()
		end)
	end
end

function ns.DelvesRead_Stop()
	if timer then
		timer:Cancel()
		timer = nil
	end
	events:Unwatch("read", "PLAYER_REGEN_ENABLED")
end

function ns.DelvesRead_Init(saved)
	db = saved
end

function ns.DelvesRead_State()
	return state
end

-- The season's delve faction, its expansion and its companion ID, for /tomte data.
function ns.DelvesRead_Season()
	if not C_DelvesUI then
		return nil
	end
	local id, season = SeasonData()
	return id, season and season.expansionID, season and season.playerCompanionID
end

function ns.DelvesRead_PlayerRole()
	local i = C_SpecializationInfo.GetSpecialization()
	if not i or i == 0 then
		return nil
	end
	return (select(5, C_SpecializationInfo.GetSpecializationInfo(i)))
end

function ns.DelvesRead_RoleHint()
	local c = state.companion
	if not (db and db.roleHint and c and c.role) then
		return nil
	end
	return ns.Delves_RoleHint(ns.DelvesRead_PlayerRole(), c.role, c.name, c.roleNames)
end
