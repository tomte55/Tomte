local addonName, ns = ...

-- Talent guide: reads the class talent tree from the game into plain tables for Data.lua (node list sorted by ID as
-- build strings expect, the three trees, current ranks). Registered in TalentGuide.lua.

local GetNodeInfo = C_Traits.GetNodeInfo

-- The trees of a talent tree (Arcane, Fire, Frost) in the talent window's order: list of { groupID, name }.
local function Trees(treeID)
	local list = {}
	for _, info in ipairs(C_Traits.GetGroupDisplayInfoByTreeID(treeID) or {}) do
		list[#list + 1] = { groupID = info.groupID, name = info.displayName, order = info.orderIndex or 0 }
	end
	table.sort(list, function(a, b)
		return a.order < b.order
	end)
	return list
end

-- Which of trees a node's groupIDs belong to: an index, or nil.
local function TreeIndex(trees, groupIDs)
	for i, tree in ipairs(trees) do
		for _, groupID in ipairs(groupIDs or {}) do
			if groupID == tree.groupID then
				return i
			end
		end
	end
	return nil
end

-- The talent config the character uses now (the active spec group's on Forever), or nil before it has loaded.
function ns.TalentGuideRead_ActiveConfig()
	local configID = C_ClassTalents.GetActiveConfigID()
	return configID and configID ~= 0 and configID or nil
end

-- The class tree as a config sees it: { configID, treeID, nodes = { { id, maxRanks } } sorted by id,
-- current = { [nodeID] = ranks purchased (points placed but not applied count) }, treeOf = { [nodeID] = index },
-- treeNames = { ... } }, or nil while the config isn't readable.
function ns.TalentGuideRead_Tree(configID)
	configID = configID or ns.TalentGuideRead_ActiveConfig()
	local config = configID and C_Traits.GetConfigInfo(configID)
	local treeID = config and config.treeIDs and config.treeIDs[1]
	if not treeID then
		return nil
	end
	local trees = Trees(treeID)
	local tree = { configID = configID, treeID = treeID, nodes = {}, current = {}, treeOf = {}, treeNames = {},
		trees = #trees }
	for i, t in ipairs(trees) do
		tree.treeNames[i] = t.name
	end
	for _, nodeID in ipairs(C_Traits.GetTreeNodes(treeID) or {}) do
		local info = GetNodeInfo(configID, nodeID)
		-- Talents only: a node with nothing to pick, or outside the three trees, isn't in a build string.
		local index = info and TreeIndex(trees, info.groupIDs)
		if info and info.ID ~= 0 and #info.entryIDs > 0 and info.maxRanks > 0 and (index or #trees == 0) then
			tree.nodes[#tree.nodes + 1] = { id = nodeID, maxRanks = info.maxRanks }
			tree.treeOf[nodeID] = index
			if info.ranksPurchased > 0 then
				tree.current[nodeID] = info.ranksPurchased
			end
		end
	end
	table.sort(tree.nodes, function(a, b)
		return a.id < b.id
	end)
	return tree
end

-- A talent's name, from its first entry's definition.
function ns.TalentGuideRead_NodeName(configID, nodeID)
	local info = GetNodeInfo(configID, nodeID)
	local entryID = info and info.entryIDs[1]
	local entry = entryID and C_Traits.GetEntryInfo(configID, entryID)
	local definition = entry and entry.definitionID and C_Traits.GetDefinitionInfo(entry.definitionID)
	if not definition then
		return nil
	end
	local name = definition.overrideName
	if name and name ~= "" then
		return name
	end
	return definition.spellID and C_Spell.GetSpellName(definition.spellID) or nil
end

-- Whether a point can go into a talent right now: its tree and arrows unlocked (canPurchaseRank, which measured
-- true in game with 0 unspent points) and a point left to pay for it, counting points placed but not applied.
function ns.TalentGuideRead_CanBuy(configID, treeID, nodeID)
	local info = GetNodeInfo(configID, nodeID)
	if not (info and info.canPurchaseRank) then
		return false
	end
	local have, any = {}, false
	for _, currency in ipairs(C_Traits.GetTreeCurrencyInfo(configID, treeID, false) or {}) do
		have[currency.traitCurrencyID] = currency.quantity
		any = any or currency.quantity > 0
	end
	local costs = C_Traits.GetNodeCost(configID, nodeID) or {}
	if #costs == 0 then
		return any
	end
	for _, cost in ipairs(costs) do
		if (have[cost.ID] or 0) < cost.amount then
			return false
		end
	end
	return true
end

-- A talent's max rank.
function ns.TalentGuideRead_MaxRanks(configID, nodeID)
	local info = GetNodeInfo(configID, nodeID)
	return info and info.maxRanks or 0
end
