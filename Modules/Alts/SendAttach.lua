local addonName, ns = ...

-- Send to alt, attaching: puts an attach plan (Alts_AttachPlan in ListData.lua) on the Send Mail tab's slots, for
-- the crafting list's mail (Send.lua) and friends' crafts (FriendMail.lua).

-- A split dropped straight on a mail slot attaches there on retail. On Forever the whole stack it came from went in
-- (seen in game, 2026-11-22; like a split that won't sell from the cursor, Upkeep/SellSplit.lua), so there each split
-- goes into a free bag slot first and is attached once it has landed (about 1.2 s, measured for SellSplit).
local SPLIT_WAIT = 5 -- seconds a split may take to land before it's left in the bags
local LAST_BAG = 4 -- bag IDs: 0 is the backpack, 1 to 4 the bags you wear
local placing -- { list = { { bag, slot, itemID, count, done } }, slot = last mail slot used } while splits land

-- Empty slots in plain bags (a profession bag may not take the item), top bag first.
local function FreeBagSlots()
	local out = {}
	for bag = 0, LAST_BAG do
		local _, family = C_Container.GetContainerNumFreeSlots(bag)
		if family == 0 then
			for _, slot in ipairs(C_Container.GetContainerFreeSlots(bag) or {}) do
				out[#out + 1] = { bag = bag, slot = slot }
			end
		end
	end
	return out
end

-- Attaches the splits that have landed; stops once all are in, the mailbox closed or the wait ran out.
local function AttachLanded(timedOut)
	if not placing then
		return
	end
	local left = 0
	for _, p in ipairs(placing.list) do
		if not p.done then
			local info = C_Container.GetContainerItemInfo(p.bag, p.slot)
			if info and info.itemID == p.itemID and info.stackCount == p.count and not info.isLocked then
				ClearCursor()
				C_Container.PickupContainerItem(p.bag, p.slot)
				placing.slot = placing.slot + 1
				ClickSendMailItemButton(placing.slot)
				ClearCursor()
				p.done = true
			else
				left = left + 1
			end
		end
	end
	if left == 0 or timedOut or not (MailFrame and MailFrame:IsShown()) then
		if left > 0 then
			ns.Print(("%d split stack%s didn't arrive in time: %s in your bags, attach %s by hand."):format(left,
				left == 1 and "" or "s", left == 1 and "it's" or "they're", left == 1 and "it" or "them"))
		end
		placing = nil
		ns.AltsSend_Refresh()
	end
end

-- Puts plan (Alts_AttachPlan's) on the Send Mail tab's slots.
local function AttachPlanned(plan)
	ClearCursor()
	local slot, list, free = 0, {}, ns.FOREVER and FreeBagSlots() or nil
	for _, a in ipairs(plan) do
		if a.split and free then
			local to = table.remove(free, 1)
			if to then
				C_Container.SplitContainerItem(a.bag, a.slot, a.split)
				C_Container.PickupContainerItem(to.bag, to.slot)
				ClearCursor() -- didn't take it: back where it came from
				list[#list + 1] = { bag = to.bag, slot = to.slot, itemID = a.itemID, count = a.split }
			end
		else
			if a.split then
				C_Container.SplitContainerItem(a.bag, a.slot, a.split)
			else
				C_Container.PickupContainerItem(a.bag, a.slot)
			end
			slot = slot + 1
			ClickSendMailItemButton(slot)
			ClearCursor()
		end
	end
	if #list > 0 then
		local mine = { list = list, slot = slot }
		placing = mine
		C_Timer.After(SPLIT_WAIT, function()
			if placing == mine then
				AttachLanded(true)
			end
		end)
	end
end
ns.AltsSend_AttachPlanned = AttachPlanned

-- Whether splits are still landing: Send waits until they're attached.
function ns.AltsSend_Placing()
	return placing ~= nil
end

-- On every bag change at the mailbox (Send.lua): attaches the splits that have landed.
function ns.AltsSend_AttachLanded()
	AttachLanded()
end

-- The mailbox closed: splits still landing stay in the bags.
function ns.AltsSend_StopPlacing()
	placing = nil
end
