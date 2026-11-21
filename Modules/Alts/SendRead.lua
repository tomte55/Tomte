local addonName, ns = ...

-- Send to alt: what Send.lua reads from the game: this character's bag stacks, the realms mail reaches and every
-- character's reagent users. The panel is in Send.lua, the rules in SendData.lua.

local QUEST = 12 -- Enum.ItemClass.Questitem
local CONSUMABLE = 0 -- Enum.ItemClass.Consumable
local FOOD_DRINK = 5 -- Enum.ItemConsumableSubclass.Fooddrink: stays with you (Alts_Recipient)

-- This character's bag stacks with what the rules need.
local function BagStacks()
	local stacks = {}
	for bag = 0, 5 do -- Backpack .. ReagentBag
		for slot = 1, C_Container.GetContainerNumSlots(bag) or 0 do
			local info = C_Container.GetContainerItemInfo(bag, slot)
			if info and info.itemID and not info.isLocked then
				local _, _, _, _, _, classID, subClassID = C_Item.GetItemInfoInstant(info.itemID)
				if classID ~= QUEST then
					stacks[#stacks + 1] = {
						bag = bag, slot = slot, itemID = info.itemID, name = info.itemName, count = info.stackCount,
						icon = info.iconFileID, link = info.hyperlink, bound = info.isBound, quality = info.quality,
						classID = classID, food = classID == CONSUMABLE and subClassID == FOOD_DRINK,
					}
				end
			end
		end
	end
	return stacks
end

-- The realms mail reaches (ns.Alts_RealmSet), nil while that isn't known. The connected realms don't change in a
-- session, so a non-empty list is kept. C_AutoComplete.GetAutoCompleteRealms answers an empty list on a realm that
-- isn't connected.
local realmSet
function ns.Alts_MailRealms()
	if realmSet then
		return realmSet
	end
	local myRealm = ns.RealmName()
	if not myRealm then
		return nil
	end
	local ok, realms = pcall(C_AutoComplete.GetAutoCompleteRealms)
	realms = ok and type(realms) == "table" and realms or {}
	local set = ns.Alts_RealmSet(realms, myRealm)
	if #realms > 0 then
		realmSet = set
	end
	return set
end

-- Every character's reagent users, kept until recipes or characters change (Alts_RecipesChanged, a new recipe, a
-- mailbox or bank visit) or a minute has passed: the panel is drawn again on bag changes.
local usersCache, usersAt
local function UsersChanged()
	usersCache = nil
end

local function Users()
	local now = GetTime()
	if not usersCache or now - usersAt > 60 then
		usersCache, usersAt = ns.Alts_ReagentUsers(ns.altsDB.chars, ns.altsDB.recipes), now
	end
	return usersCache
end

-- For Send.lua, Deposit.lua and FriendMail.lua.
ns.AltsSend_BagStacks = BagStacks
ns.AltsSend_UsersChanged = UsersChanged
ns.AltsSend_Users = Users
