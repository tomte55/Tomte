local addonName, ns = ...

-- Vendor Helper, selling part of a stack (World of Warcraft: Forever only; tools/forever_list.lua). Measured on Forever
-- 1.60.1: a split stack held on the cursor doesn't sell when dropped on the vendor, not even with PickupMerchantItem(0), while
-- a whole stack does. So a split dropped there goes into a free bag slot and sells from it. Rules in Data.lua.

-- How long the server may take to place the split before it's left in the bags. Measured: about 1.2 s, and the slot reads empty
-- until then, so the sale can't start sooner. Checking every frame instead of on the bag events gained nothing.
local WAIT_SECONDS = 5
local LAST_BAG = 4 -- bag IDs: 0 is the backpack, 1 to 4 the bags you wear
local TAB_MERCHANT = 1 -- MerchantFrame.selectedTab; 2 is the buyback page

local active, hooked, waiting = false, false, false
local held -- { itemID, noValue, count }: the split on the cursor
local placed -- { bag, slot, itemID, count }: the split on its way into a free slot
local events = CreateFrame("Frame")

local function Selling()
	return MerchantFrame:IsShown() and MerchantFrame.selectedTab == TAB_MERCHANT
end

local function FreeSlot(itemID)
	local family = C_Item.GetItemFamily(itemID)
	local bags = {}
	for bag = 0, LAST_BAG do
		local _, bagFamily = C_Container.GetContainerNumFreeSlots(bag)
		bags[#bags + 1] = { bag = bag, takes = ns.Bags_BagTakes(bagFamily, family),
			free = C_Container.GetContainerFreeSlots(bag) or {} }
	end
	return ns.Upkeep_SplitSlot(bags)
end

local function StopWaiting()
	placed = nil
	events:UnregisterEvent("BAG_UPDATE_DELAYED")
	events:UnregisterEvent("ITEM_LOCK_CHANGED")
end

local function SellIfArrived()
	if not placed then
		return
	end
	if not (active and Selling()) then
		StopWaiting() -- the vendor closed: the split stays in the bags
		return
	end
	if ns.Upkeep_SplitArrived(placed, C_Container.GetContainerItemInfo(placed.bag, placed.slot)) then
		local bag, slot = placed.bag, placed.slot
		StopWaiting()
		C_Container.UseContainerItem(bag, slot)
	end
end

-- Runs after Blizzard's own drop, so what's still on the cursor is what the game didn't sell.
local function OnDrop()
	if not (active and held and Selling()) then
		return
	end
	local kind, itemID = GetCursorInfo()
	if kind ~= "item" or itemID ~= held.itemID then
		held = nil
		return
	end
	if held.noValue then
		return -- the vendor doesn't buy it: nothing to move
	end
	local bag, slot = FreeSlot(itemID)
	if not bag then
		ns.Print("Selling part of a stack needs a free bag slot.")
		return
	end
	local mine = { bag = bag, slot = slot, itemID = itemID, count = held.count }
	held, placed = nil, mine
	events:RegisterEvent("BAG_UPDATE_DELAYED")
	events:RegisterEvent("ITEM_LOCK_CHANGED")
	C_Container.PickupContainerItem(bag, slot)
	C_Timer.After(WAIT_SECONDS, function()
		if placed == mine then
			StopWaiting()
			ns.Print("Couldn't sell that: it's in your bags.")
		end
	end)
	SellIfArrived()
end

local function OnSplit(bag, slot, count)
	if not active then
		return
	end
	local info = C_Container.GetContainerItemInfo(bag, slot)
	held = info and { itemID = info.itemID, noValue = info.hasNoValue, count = count } or nil
end

-- Hooks can't be undone: each does nothing while Vendor Helper is off. The merchant window may load after Tomte.
local function Hook()
	if hooked then
		return
	end
	hooked = true
	hooksecurefunc(C_Container, "SplitContainerItem", OnSplit)
	MerchantFrame:HookScript("OnMouseUp", OnDrop)
	-- Blizzard's drag-and-drop on the window and its clicks on an item's row both come through this.
	hooksecurefunc("MerchantItemButton_OnClick", function(_, button)
		if button == "LeftButton" then
			OnDrop()
		end
	end)
end

events:SetScript("OnEvent", ns.Perf_WrapEvents(function(_, event)
	if event == "CURSOR_CHANGED" then
		if not CursorHasItem() then
			held = nil
		end
	else
		SellIfArrived()
	end
end))

function ns.UpkeepSellSplit_Toggle(on)
	active = on
	held = nil
	StopWaiting()
	if on then
		events:RegisterEvent("CURSOR_CHANGED")
		if not waiting then
			waiting = true
			EventUtil.ContinueOnAddOnLoaded("Blizzard_UIPanels_Game", Hook)
		end
	else
		events:UnregisterEvent("CURSOR_CHANGED")
	end
end
