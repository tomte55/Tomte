local addonName, ns = ...

-- Loot, Make room (World of Warcraft: Forever only; tools/forever_list.lua): when loot doesn't fit in your bags, a button under the
-- loot window destroys your cheapest junk and loots it. Anything but grey junk takes a second click. Rules in RoomData.lua, the window
-- in Window.lua. DeleteCursorItem needs a real click and destroys one item per click (warcraft.wiki.gg/wiki/API_DeleteCursorItem).

local LAST_BAG = 4 -- bag IDs: 0 is the backpack, 1 to 4 the bags you wear
local HEIGHT = 40 -- at least: grows when a long item name wraps the text to a third line
local LABEL_PAD_Y = 7 -- above and below the text
local GAP = 4 -- under the window
local LABEL_PAD = 8
local MIN_WIDTH = 260 -- two lines of item names fit
local ARM_SECONDS = 5 -- how long the first click of a confirmation counts
local LOOT_WAIT = 3 -- seconds: the deleted item has to leave the bags before the loot fits; after this it's left to the player
local HEARTHSTONE = 6948
local ROLL_GRACE = 5 -- seconds past a roll's time limit before it's taken as over (the server's answer can lag)

local UI = ns.UI

local db, button
local window -- the loot window, while it can loot
local entries
local plan
local armedFor -- the bag and slot of the item the first click named
local pending -- { slot, at = GetTime(), name, gone = the destroyed item's link }: loot to take once the bags have changed
-- [rollID] = { name, handle (the corpse's lootHandle), ends (GetTime) }: group rolls not decided yet. A roll is open
-- from START_LOOT_ROLL until you win it (LOOT_ITEM_ROLL_WON), every roll on the corpse is done (LOOT_ROLLS_COMPLETE)
-- or its time limit has passed. Not until CANCEL_LOOT_ROLL: that comes as soon as you pick Need or Greed (it hides
-- your roll frame), while the others are still rolling (Living Root was offered for destroying mid-roll that way).
local rolls = {}
local watcher = CreateFrame("Frame")

local function ItemName(link)
	return link and link:match("%[(.-)%]")
end

local function Rolling(name)
	local now = GetTime()
	for rollID, roll in pairs(rolls) do
		if now > roll.ends then
			rolls[rollID] = nil
		elseif roll.name == name or roll.name == nil then
			return true -- an unnamed roll (its item not loaded yet) holds every loot back, to be safe
		end
	end
	return false
end

-- For the loot reader (Read.lua): an item counts as locked while it's rolled for.
ns.LootRoom_Rolling = Rolling

local Refresh

local function OnRoll(event, ...)
	if event == "START_LOOT_ROLL" then
		local rollID, rollTime, handle = ...
		-- The link can lag an uncached item; the roll's own info names it too.
		local _, name = GetLootRollItemInfo(rollID)
		local seconds = (tonumber(rollTime) or 60000) / 1000 + ROLL_GRACE
		rolls[rollID] = { name = ItemName(GetLootRollItemLink(rollID)) or name, handle = handle, ends = GetTime() + seconds }
		C_Timer.After(seconds + 0.1, function()
			ns.Loot_RollsChanged()
			Refresh()
		end)
	elseif event == "LOOT_ITEM_ROLL_WON" then
		local name = ItemName(...)
		for rollID, roll in pairs(rolls) do
			if roll.name == name then
				rolls[rollID] = nil
			end
		end
	elseif event == "LOOT_ROLLS_COMPLETE" then
		local handle = ...
		for rollID, roll in pairs(rolls) do
			if roll.handle == nil or roll.handle == handle then
				rolls[rollID] = nil
			end
		end
	elseif event == "CANCEL_ALL_LOOT_ROLLS" then
		wipe(rolls)
	end
end

-- The loot slot as the game has it right now (the window's entries can lag a roll or another player's looting): the item
-- is still there, still the same one, and not locked to you.
local function SlotStillYours(loot)
	if not (LootSlotHasItem(loot.slot)) then
		return false
	end
	local _, name, _, _, _, locked = GetLootSlotInfo(loot.slot)
	return name == loot.name and not locked and not Rolling(loot.name)
end

local function ReadCandidate(bag, slot, info)
	local _, _, _, _, _, classID, subclassID = C_Item.GetItemInfoInstant(info.itemID)
	local name, _, _, _, _, _, _, _, _, _, sell = C_Item.GetItemInfo(info.hyperlink)
	-- What it would really fetch, where it sells best (Gold & value), else its auction or vendor price.
	local price = ns.Value_SellPrice and ns.Value_SellPrice(info.hyperlink, info.isBound)
		or ns.Value_ItemPrice and ns.Value_ItemPrice(info.hyperlink, info.isBound) or nil
	return {
		bag = bag, slot = slot, itemID = info.itemID, link = info.hyperlink, name = name or info.itemName,
		count = info.stackCount or 1, quality = info.quality, classID = ns.BagsRead_ItemClass(info.itemID, classID, subclassID),
		bound = info.isBound, noValue = info.hasNoValue, locked = info.isLocked, sell = sell, value = price,
		kept = info.itemID == HEARTHSTONE,
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
	return loot and ns.LootRoom_Plan(loot, read[loot], Rolling(loot.name)) or nil
end

-- The item the button would destroy, lit in the bags so it can be looked at first.
local function Spotlight()
	local target = plan and plan.kind == "destroy" and button and button:IsShown() and plan.target
	ns.Bags_Spotlight(target and target.bag, target and target.slot)
end

local function Draw()
	local isArmed = plan.kind == "destroy" and armedFor and armedFor.bag == plan.target.bag and armedFor.slot == plan.target.slot
	button.label:SetText(ns.LootRoom_Text(plan, isArmed))
	button:SetEnabled(plan.kind == "destroy")
	button:SetWidth(math.max(window:GetWidth(), MIN_WIDTH))
	button.label:SetWidth(button:GetWidth() - 2 * LABEL_PAD)
	button:SetHeight(math.max(HEIGHT, math.ceil(button.label:GetStringHeight()) + 2 * LABEL_PAD_Y))
	button:Show()
	Spotlight()
end

local function HideButton()
	if button then
		button:Hide()
	end
	ns.Bags_Spotlight(nil)
end

Refresh = function()
	if not (button and window and db.makeRoom) then
		HideButton()
		return
	end
	plan = ReadPlan()
	if plan then
		Draw()
	else
		HideButton()
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
	-- Nothing is destroyed for loot that has been rolled on, taken or locked since the window last drew.
	if not SlotStillYours(plan.loot) then
		Refresh()
		return
	end
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
		local waiting = { slot = plan.loot.slot, at = GetTime(), name = plan.loot.name,
			gone = target.link or target.name }
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

-- The destroyed item can't come back; if the loot went elsewhere meanwhile, say so plainly.
local function LostLoot(waiting)
	ns.Print(("%s was taken before Tomte could loot it. %s was destroyed for it."):format(waiting.name or "The loot",
		waiting.gone or "An item"))
end

local function TakePending()
	local waiting = pending
	pending = nil
	if not (window and GetTime() - waiting.at <= LOOT_WAIT) then
		return
	end
	if LootSlotHasItem(waiting.slot) and select(2, GetLootSlotInfo(waiting.slot)) == waiting.name then
		LootSlot(waiting.slot)
	else
		LostLoot(waiting)
	end
end

-- The item it would destroy, as the game shows it, then what Make room is.
local function ShowTooltip(self)
	GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
	if plan and plan.kind == "destroy" then
		GameTooltip:SetBagItem(plan.target.bag, plan.target.slot)
		GameTooltip:AddLine(" ")
		UI.TipLine("Make room", "heading")
	else
		GameTooltip:SetText("Make room")
	end
	if plan and plan.kind == "destroy" then
		UI.TipLine(plan.confirm and "No grey junk left, so this one takes a second click." or "Grey junk, your cheapest.", "text", true)
		UI.TipLine("Destroying can't be undone.", "warning")
	end
	UI.TipLine("Never touches quest items, soulbound items, upgrades, food, ammo, bags, profession tools, your hearthstone or anything rare.",
		"textMuted", true)
	GameTooltip:Show()
	-- SetBagItem opens the shared "Equipped" comparison when alwaysCompareItems is on; it says nothing about
	-- destroying junk. Hidden after the fact rather than by setting GameTooltip.supportsItemComparison, which would
	-- taint a key Blizzard's tooltip code reads. Holding Shift still compares.
	if plan and plan.kind == "destroy" and not IsModifiedClick("COMPAREITEMS") then
		if ShoppingTooltip1 then
			ShoppingTooltip1:Hide()
		end
		if ShoppingTooltip2 then
			ShoppingTooltip2:Hide()
		end
	end
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
		if pending then
			LostLoot(pending)
		end
		watcher:UnregisterAllEvents()
		window, entries, plan, armedFor, pending = nil, nil, nil, nil, nil
		ns.Bags_Spotlight(nil)
	end)
end

watcher:SetScript("OnEvent", ns.Perf_WrapEvents(function()
	if pending then
		TakePending()
	end
	Refresh()
end))

-- Rolls are watched from login: a roll starts as soon as anyone opens the corpse, often before your own loot window
-- (Tail Spike was offered for destroying mid-roll when this only started with the window), and it can outlast it.
-- The game's loot window doesn't mark a rolled item as locked on Forever, so these events are the only sign.
local rollWatcher = CreateFrame("Frame")
rollWatcher:SetScript("OnEvent", ns.Perf_WrapEvents(function(_, event, ...)
	OnRoll(event, ...)
	ns.Loot_RollsChanged()
	Refresh()
end))
for _, event in ipairs({ "START_LOOT_ROLL", "LOOT_ITEM_ROLL_WON", "LOOT_ROLLS_COMPLETE", "CANCEL_ALL_LOOT_ROLLS" }) do
	if ns.EventValid(event) then
		rollWatcher:RegisterEvent(event)
	end
end

-- From the loot window, each time it draws. live: it's showing real loot that can be taken.
function ns.LootRoom_Update(parent, live, lootEntries)
	if not (db and db.makeRoom and live) then
		HideButton()
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
