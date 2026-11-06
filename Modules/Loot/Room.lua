local addonName, ns = ...

-- Loot, Make room (World of Warcraft: Forever only; tools/forever_list.lua): when loot doesn't fit in your bags, a button under the
-- loot window destroys your cheapest junk and loots it. Anything but grey junk takes a second click. Rules in RoomData.lua, the window
-- in Window.lua. DeleteCursorItem needs a real click and destroys one item per click (warcraft.wiki.gg/wiki/API_DeleteCursorItem).

local LAST_BAG = 4 -- bag IDs: 0 is the backpack, 1 to 4 the bags you wear
local HEIGHT = 40
local GAP = 4 -- under the window
local LABEL_PAD = 8
local MIN_WIDTH = 260 -- two lines of item names fit
local ARM_SECONDS = 5 -- how long the first click of a confirmation counts
local LOOT_WAIT = 3 -- seconds: the deleted item has to leave the bags before the loot fits; after this it's left to the player
local HEARTHSTONE = 6948

local UI = ns.UI

local db, button
local window -- the loot window, while it can loot
local entries
local plan
local armedFor -- the bag and slot of the item the first click named
local pending -- { slot = the loot slot to take once the bags have changed, at = GetTime() }
local watcher = CreateFrame("Frame")

local function IsKept(itemID)
	local tools = ns.Content_Get(ns.CONTENT_FOREVER, "professionTools")
	return itemID == HEARTHSTONE or (tools ~= nil and tools[itemID] == true)
end

local function ReadCandidate(bag, slot, info)
	local _, _, _, _, _, classID = C_Item.GetItemInfoInstant(info.itemID)
	local name, _, _, _, _, _, _, _, _, _, sell = C_Item.GetItemInfo(info.hyperlink)
	local price = ns.Value_ItemPrice and ns.Value_ItemPrice(info.hyperlink) or nil
	return {
		bag = bag, slot = slot, itemID = info.itemID, link = info.hyperlink, name = name or info.itemName,
		count = info.stackCount or 1, quality = info.quality, classID = classID, bound = info.isBound, noValue = info.hasNoValue,
		locked = info.isLocked, sell = sell, value = price, kept = IsKept(info.itemID),
		upgrade = ns.Gear_BagArrow ~= nil and ns.Gear_BagArrow(info.hyperlink) ~= nil,
	}
end

-- The bags that take an item, for LootRoom_Fits, and what's in them that could make room for it.
local function ReadBags(itemID, maxStack)
	local bags, candidates = {}, {}
	local family = C_Item.GetItemFamily(itemID)
	for bag = 0, LAST_BAG do
		local free, bagFamily = C_Container.GetContainerNumFreeSlots(bag)
		if ns.Bags_BagTakes(bagFamily, family) and C_Container.GetContainerNumSlots(bag) > 0 then
			local topUp = 0
			for slot = 1, C_Container.GetContainerNumSlots(bag) do
				local info = C_Container.GetContainerItemInfo(bag, slot)
				if info and not ns.IsSecret(info.itemID) and info.hyperlink then
					if info.itemID == itemID then
						topUp = topUp + math.max(maxStack - (info.stackCount or 1), 0)
					end
					candidates[#candidates + 1] = ReadCandidate(bag, slot, info)
				end
			end
			bags[#bags + 1] = { free = free or 0, topUp = topUp }
		end
	end
	return bags, candidates
end

-- What the button should offer now, nil when everything fits.
local function ReadPlan()
	local blocked, read = {}, {}
	for _, e in ipairs(entries or {}) do
		if e.kind == "item" and e.itemID and not e.taken and not e.locked then
			local _, _, _, _, _, _, _, maxStack = C_Item.GetItemInfo(e.itemID)
			local bags, candidates = ReadBags(e.itemID, maxStack or 1)
			if not ns.LootRoom_Fits(e.quantity, bags) then
				blocked[#blocked + 1] = e
				read[e] = candidates
			end
		end
	end
	local loot = ns.LootRoom_PickLoot(blocked)
	return loot and ns.LootRoom_Plan(loot, read[loot]) or nil
end

local function Draw()
	local isArmed = plan.kind == "destroy" and armedFor and armedFor.bag == plan.target.bag and armedFor.slot == plan.target.slot
	button.label:SetText(ns.LootRoom_Text(plan, isArmed))
	button:SetEnabled(plan.kind == "destroy")
	button:SetWidth(math.max(window:GetWidth(), MIN_WIDTH))
	button.label:SetWidth(button:GetWidth() - 2 * LABEL_PAD)
	button:Show()
end

local function Refresh()
	if not (button and window and db.makeRoom) then
		if button then
			button:Hide()
		end
		return
	end
	plan = ReadPlan()
	if plan then
		Draw()
	else
		button:Hide()
		armedFor = nil
	end
end

local function Destroy(target)
	if CursorHasItem() then
		ns.Print("Put down the item you're holding first.")
		return false
	end
	C_Container.PickupContainerItem(target.bag, target.slot)
	-- The one thing that must never go wrong: only what the button named goes.
	local kind, itemID = GetCursorInfo()
	if kind ~= "item" or itemID ~= target.itemID then
		ClearCursor()
		return false
	end
	DeleteCursorItem()
	if CursorHasItem() then
		ClearCursor()
		return false
	end
	ns.Print(("Destroyed %s to make room."):format(target.link or target.name or "an item"))
	return true
end

local function OnClick()
	-- Read again: the bags may have changed since it was drawn, and what's destroyed must be what it says now.
	local shown = plan
	plan = ReadPlan()
	if not plan or plan.kind ~= "destroy" or not shown or shown.kind ~= "destroy" or shown.target.itemID ~= plan.target.itemID then
		Refresh()
		return
	end
	local target = plan.target
	if plan.confirm and not (armedFor and armedFor.bag == target.bag and armedFor.slot == target.slot) then
		armedFor = { bag = target.bag, slot = target.slot }
		local armed = armedFor
		C_Timer.After(ARM_SECONDS, function()
			if armedFor == armed then
				armedFor = nil
				Refresh()
			end
		end)
		Draw()
		return
	end
	armedFor = nil
	if Destroy(target) then
		local waiting = { slot = plan.loot.slot, at = GetTime() }
		pending = waiting
		button:SetEnabled(false) -- until the bags have changed: one item per click, and this one has gone
		C_Timer.After(LOOT_WAIT, function() -- the bags never answered: don't leave the button dead
			if pending == waiting then
				pending = nil
				Refresh()
			end
		end)
	end
end

local function ShowTooltip(self)
	GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
	GameTooltip:SetText("Make room")
	if plan and plan.kind == "destroy" then
		UI.TipLine(plan.confirm and "No grey junk left, so this one takes a second click." or "Grey junk, your cheapest.", "text", true)
		UI.TipLine("Destroying can't be undone.", "warning")
	end
	UI.TipLine("Never touches quest items, soulbound items, upgrades, food, ammo, bags, profession tools, your hearthstone or anything rare.",
		"textMuted", true)
	GameTooltip:Show()
end

local function Build(parent)
	button = UI.Button(parent, MIN_WIDTH, "")
	button:SetHeight(HEIGHT)
	button:SetPoint("TOPLEFT", parent, "BOTTOMLEFT", 0, -GAP)
	button.label:SetWordWrap(true)
	button.label:SetJustifyH("CENTER")
	button:SetScript("OnClick", OnClick)
	button:HookScript("OnEnter", ShowTooltip)
	button:HookScript("OnLeave", GameTooltip_Hide)
	button:Hide()
	parent:HookScript("OnHide", function()
		watcher:UnregisterAllEvents()
		window, entries, plan, armedFor, pending = nil, nil, nil, nil, nil
	end)
end

watcher:SetScript("OnEvent", ns.Perf_WrapEvents(function()
	if pending then
		local slot, at = pending.slot, pending.at
		pending = nil
		if window and GetTime() - at <= LOOT_WAIT then
			LootSlot(slot)
		end
	end
	Refresh()
end))

-- From the loot window, each time it draws. live: it's showing real loot that can be taken.
function ns.LootRoom_Update(parent, live, lootEntries)
	if not (db and db.makeRoom and live) then
		if button then
			button:Hide()
		end
		return
	end
	if not button then
		Build(parent)
	end
	window, entries = parent, lootEntries
	watcher:RegisterEvent("BAG_UPDATE_DELAYED")
	if not pending then
		Refresh()
	end
end

-- /tomte loot why.
function ns.LootRoom_Why()
	ns.Print(("Make room: %s."):format(plan and ns.LootRoom_Text(plan, false):gsub("\n", " ") or "nothing to do"))
end

function ns.LootRoom_Init(moduleDB)
	db = moduleDB
end

function ns.LootRoom_Refresh()
	Refresh()
end
