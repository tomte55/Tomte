local addonName, ns = ...

-- Almost Done: what an achievement rewards and whether you own it. The reward item (C_AchievementInfo.GetRewardItemID)
-- is checked against the mount, pet, toy, housing and transmog journals; without an item the reward text decides
-- (Data.lua). Results are cached per achievement until a collection changes.

local GetRewardItemID = C_AchievementInfo.GetRewardItemID

ns.ACH_REWARD_ICONS = {
	mount = "Interface\\Icons\\Ability_Mount_RidingHorse",
	pet = "Interface\\Icons\\INV_Box_PetCarrier_01",
	toy = "Interface\\Icons\\INV_Misc_Toy_10",
	title = "Interface\\Icons\\INV_Scroll_11",
	appearance = "Interface\\Icons\\INV_Chest_Cloth_17",
	decor = "Interface\\Icons\\INV_Misc_Furniture_Chair_03",
	other = "Interface\\Icons\\INV_Misc_Gift_01",
}

ns.ACH_REWARD_NAMES = {
	mount = "Mount", pet = "Pet", toy = "Toy", title = "Title", appearance = "Appearance", decor = "Decor",
	other = "Reward",
}

local RETRY = 10 -- seconds before an item reward we couldn't type is looked up again (item data still loading)

local cache = {} -- [achievementID] = info | false

local function MountInfo(itemID)
	local mountID = C_MountJournal.GetMountFromItem(itemID)
	if not mountID then
		return nil
	end
	local name, _, icon, _, _, _, _, _, _, _, isCollected = C_MountJournal.GetMountInfoByID(mountID)
	local displayID, _, _, isSelfMount, _, sceneID = C_MountJournal.GetMountInfoExtraByID(mountID)
	if not displayID then
		-- Mounts with several looks have no single display ID: use the first one.
		local all = C_MountJournal.GetMountAllCreatureDisplayInfoByID(mountID)
		displayID = all and all[1] and all[1].creatureDisplayID
	end
	return { type = "mount", owned = isCollected and true or false, name = name, icon = icon, displayID = displayID,
		sceneID = sceneID, selfMount = isSelfMount }
end

local function PetInfo(itemID)
	local name, icon, _, _, _, _, _, _, _, _, _, displayID, speciesID = C_PetJournal.GetPetInfoByItemID(itemID)
	if not speciesID then
		return nil
	end
	local collected = C_PetJournal.GetNumCollectedInfo(speciesID)
	local sceneID = C_PetJournal.GetPetModelSceneInfoBySpeciesID(speciesID)
	return { type = "pet", owned = (collected or 0) > 0, name = name, icon = icon, displayID = displayID,
		sceneID = sceneID }
end

local function ToyInfo(itemID)
	local toyItemID, name, icon = C_ToyBox.GetToyInfo(itemID)
	if not toyItemID then
		return nil
	end
	return { type = "toy", owned = PlayerHasToy(itemID) and true or false, name = name, icon = icon }
end

local function DecorInfo(itemID)
	if not (C_HousingCatalog and C_HousingCatalog.GetCatalogEntryInfoByItem) then
		return nil
	end
	local ok, entry = pcall(C_HousingCatalog.GetCatalogEntryInfoByItem, itemID)
	if not (ok and entry) then
		return nil
	end
	local have = (entry.totalNumStored or 0) + (entry.remainingRedeemable or 0) + (entry.totalNumPlaced or 0)
	return { type = "decor", owned = have > 0, name = entry.name, icon = entry.iconTexture }
end

local function AppearanceInfo(itemID)
	local ok, appearanceID = pcall(C_TransmogCollection.GetItemInfo, itemID)
	if not (ok and appearanceID) then
		return nil
	end
	local name, link, _, _, _, _, _, _, _, icon = C_Item.GetItemInfo(itemID)
	return { type = "appearance", owned = C_TransmogCollection.PlayerHasTransmog(itemID) and true or false,
		name = name, icon = icon, link = link }
end

local LOOKUPS = { MountInfo, PetInfo, ToyInfo, DecorInfo, AppearanceInfo }

local function Lookup(record)
	local itemID = record.rewardItem
	if itemID == nil then
		itemID = GetRewardItemID(record.id) or false
		record.rewardItem = itemID
	end
	if itemID then
		for _, lookup in ipairs(LOOKUPS) do
			local info = lookup(itemID)
			if info then
				info.itemID = itemID
				return info
			end
		end
	end
	local textType = ns.Ach_RewardTypeFromText(record.reward)
	if not textType then
		return false
	end
	-- An item we couldn't type (or that isn't cached yet: GetItemInfo may still be loading) shows as "other".
	return { type = textType, owned = false, itemID = itemID or nil }
end

-- { type, owned, name, icon, itemID, displayID, sceneID, link } or nil when the achievement has no reward.
function ns.Ach_RewardInfo(record)
	local info = cache[record.id]
	if info == nil or (info and info.retryAt and GetTime() > info.retryAt) then
		info = Lookup(record)
		-- Item data still loading: an untyped item, or an appearance without its link yet.
		if info and ((info.type == "other" and info.itemID) or (info.type == "appearance" and not info.link)) then
			info.retryAt = GetTime() + RETRY
		end
		cache[record.id] = info
	end
	return info or nil
end

function ns.Ach_RewardsChanged()
	wipe(cache)
end
