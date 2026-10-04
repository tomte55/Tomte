local addonName, ns = ...

-- Gear Check's upgrade reveal: gear that's new to your bags (loot, quest rewards, the vault, mail, trades) and is
-- a clean upgrade gets a Moments reveal (the "Gear upgrade" type: banner or cinematic with the item icon) and a
-- toast that equips it on click. New = an item GUID not seen in the bags or worn since login. Items taken out of
-- a bank aren't new. Which items count (best per slot, minimum gain) is in Data.lua.

local BAGS = { 0, 1, 2, 3, 4 } -- backpack and the four bags (gear never goes in the reagent bag)
local EQUIP_SLOTS = { 1, 2, 3, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17 }
local SETTLE = 8 -- seconds after login or a loading screen in which bag items are only noted (bags fill in)
local RETRY = 1 -- seconds between tries for items that are still loading
local MAX_TRIES = 6
local MAX_REVEALS = 3 -- at once (a vault or a mailbox full of gear)
local TOAST_HOLD = 30
local P = Enum.PlayerInteractionType
local BANKS = { [P.Banker] = true, [P.GuildBanker] = true, [P.CharacterBanker] = true, [P.AccountBanker] = true,
	[P.VoidStorageBanker] = true }

local db
local known = {} -- [item GUID] = true: in the bags or worn since login
local waiting = {} -- [item GUID] = tries, new items whose data hasn't loaded
local banking = {} -- [interaction type] = true while a bank is open
local settleUntil = 0
local retryQueued

local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(self, event, ...)
	self[event](self, ...)
end)

local function Secret(v)
	return issecretvalue and issecretvalue(v)
end

local function GUIDAt(location)
	if not C_Item.DoesItemExist(location) then
		return nil
	end
	local guid = C_Item.GetItemGUID(location)
	if not guid or Secret(guid) then
		return nil
	end
	return guid
end

-- Each equippable item in the bags: fn(guid, link, bag, slot, location).
local function EachBagGear(fn)
	for _, bag in ipairs(BAGS) do
		for slot = 1, C_Container.GetContainerNumSlots(bag) or 0 do
			local link = C_Container.GetContainerItemLink(bag, slot)
			local equipLoc = link and not Secret(link) and select(4, C_Item.GetItemInfoInstant(link))
			if equipLoc and ns.Gear_Slots(equipLoc) then
				local location = ItemLocation:CreateFromBagAndSlot(bag, slot)
				local guid = GUIDAt(location)
				if guid then
					fn(guid, link, bag, slot, location)
				end
			end
		end
	end
end

local function NoteWorn()
	for _, slot in ipairs(EQUIP_SLOTS) do
		local guid = GUIDAt(ItemLocation:CreateFromEquipmentSlot(slot))
		if guid then
			known[guid] = true
		end
	end
end

local function Banking()
	return next(banking) ~= nil
end

---------------------------------------------------------------------------------------------------------------
-- Showing one

local function Equip(guid)
	if InCombatLockdown() then
		ns.Print("Gear Check: you can't change gear in combat.")
		return
	end
	local found
	EachBagGear(function(g, link, bag, slot)
		if g == guid then
			found = { link = link, bag = bag, slot = slot }
		end
	end)
	if not found then
		ns.Print("Gear Check: that item isn't in your bags anymore.")
		return
	end
	-- Judged again: the gear worn may have changed since (e.g. the weaker ring is the other one now).
	local verdict = ns.Gear_EvaluateLink(found.link)
	ClearCursor()
	if verdict and verdict.slot then
		C_Container.PickupContainerItem(found.bag, found.slot)
		EquipCursorItem(verdict.slot) -- bind-on-equip items ask first (Blizzard's popup)
	else
		C_Item.EquipItemByName(found.link)
	end
end

-- item = { guid, link, verdict, name, icon, quality }
local function Reveal(item)
	local v = item.verdict
	local r, g, b = C_Item.GetItemQualityColor(item.quality or 1)
	local color = { r, g, b }
	local equipped = ns.GearItems_Equipped()
	local old = equipped and v.slot and equipped[v.slot]
	local oldName = old and C_Item.GetItemNameByID(old.itemID)
	local label = ns.Gear_RevealLabel(v)
	local desc = ns.GearItems_Describe(item.link)

	ns.Session_Note("upgrade", { title = item.name or item.link, icon = item.icon, quality = item.quality,
		itemID = C_Item.GetItemInfoInstant(item.link), detail = label })
	ns.Moments_Trigger("upgrade", { -- shown in the Moments style for "Gear upgrade" (nothing when Moments is off)
		label = label,
		title = item.name or item.link,
		subtitle = ns.Gear_RevealLine(desc and desc.ilvl, oldName, old and old.ilvl),
		detail = v.reasons[1], -- a clean upgrade only has notes: "Completes your 4-set", a socket, ...
		icon = item.icon, -- for the banner style
		itemIcon = item.icon,
		itemColor = color,
		tier = ns.Gear_RevealTier(item.quality),
	})
	if db.revealToast then
		ns.Toast_Show({
			owner = "gear",
			label = label,
			accent = color,
			title = item.name or item.link,
			text = (oldName and ("Replaces " .. oldName .. ". ") or "") .. "Click to equip, right-click to dismiss.",
			icon = item.icon,
			hold = TOAST_HOLD,
			holdInCombat = true,
			onClick = function()
				Equip(item.guid)
			end,
		})
	end
end

-- Judges the given bag items and reveals the best per slot. Returns how many were revealed; nil when some
-- weren't loaded yet (they're left in `notReady`).
local function Judge(list, notReady)
	local judged = {}
	for _, item in ipairs(list) do
		local verdict, cand = ns.Gear_EvaluateLink(item.link)
		if cand then
			item.verdict = verdict
			judged[#judged + 1] = item
		elseif notReady then
			notReady[#notReady + 1] = item
		end
	end
	local picks = ns.Gear_PickReveals(judged, db.revealMinPct)
	for i = 1, math.min(#picks, MAX_REVEALS) do
		Reveal(picks[i])
	end
	return #picks
end

local function Describe(guid, link, location)
	return { guid = guid, link = link, name = C_Item.GetItemName(location), icon = C_Item.GetItemIcon(location),
		quality = C_Item.GetItemQuality(location) }
end

---------------------------------------------------------------------------------------------------------------
-- Watching the bags

local Scan

local function QueueRetry()
	if retryQueued then
		return
	end
	retryQueued = true
	C_Timer.After(RETRY, function()
		retryQueued = false
		Scan(true)
	end)
end

-- New gear in the bags since the last scan, plus earlier new items that hadn't loaded (retry = only those).
function Scan(retry)
	if not (ns.gearModule.active and db.reveal) then
		return
	end
	local settled = GetTime() >= settleUntil and not Banking()
	local list = {}
	EachBagGear(function(guid, link, _, _, location)
		if waiting[guid] then
			list[#list + 1] = Describe(guid, link, location)
		elseif not known[guid] and not retry then
			known[guid] = true
			if settled then
				waiting[guid] = 0
				list[#list + 1] = Describe(guid, link, location)
			end
		end
	end)
	if #list == 0 then
		wipe(waiting) -- whatever was waiting has left the bags
		return
	end
	local notReady = {}
	Judge(list, notReady)
	local before = waiting
	waiting = {}
	for _, item in ipairs(notReady) do
		local tries = (before[item.guid] or 0) + 1
		if tries < MAX_TRIES then
			waiting[item.guid] = tries
		end
	end
	if next(waiting) then
		QueueRetry()
	end
end

-- Note everything now in the bags and worn as seen, without revealing it.
local function NoteAll()
	EachBagGear(function(guid)
		known[guid] = true
	end)
	NoteWorn()
end

function events:PLAYER_ENTERING_WORLD()
	settleUntil = GetTime() + SETTLE
	NoteAll()
end

function events:BAG_UPDATE_DELAYED()
	if GetTime() < settleUntil then
		NoteAll() -- bags still filling in after login
		return
	end
	-- Gear Check's own handler (Gear.lua) runs on the same event; let it drop its bag cache first.
	C_Timer.After(0, function()
		Scan(false)
	end)
end

function events:PLAYER_EQUIPMENT_CHANGED()
	NoteWorn()
end

function events:PLAYER_INTERACTION_MANAGER_FRAME_SHOW(kind)
	if BANKS[kind] then
		banking[kind] = true
	end
end

function events:PLAYER_INTERACTION_MANAGER_FRAME_HIDE(kind)
	if BANKS[kind] then
		banking[kind] = nil
		C_Timer.After(0, NoteAll) -- the last withdrawals may land after the bank closed
	end
end

---------------------------------------------------------------------------------------------------------------

-- /tomte gear upgrades: reveal the clean upgrades already in the bags.
function ns.GearReveal_ShowBags()
	if not ns.gearModule.active then
		ns.Print("Gear Check is off.")
		return
	end
	local list = {}
	EachBagGear(function(guid, link, _, _, location)
		list[#list + 1] = Describe(guid, link, location)
	end)
	local notReady = {}
	local n = Judge(list, notReady)
	if n == 0 then
		ns.Print(#notReady > 0 and "Gear Check: some items are still loading, try again in a moment."
			or ("Gear Check: no clean upgrades of at least %s%% in your bags."):format(db.revealMinPct))
	end
end

function ns.GearReveal_Start(moduleDB)
	db = moduleDB
	for _, event in ipairs({ "PLAYER_ENTERING_WORLD", "BAG_UPDATE_DELAYED", "PLAYER_EQUIPMENT_CHANGED",
		"PLAYER_INTERACTION_MANAGER_FRAME_SHOW", "PLAYER_INTERACTION_MANAGER_FRAME_HIDE" }) do
		events:RegisterEvent(event)
	end
	settleUntil = GetTime() + SETTLE
	NoteAll()
end

function ns.GearReveal_Stop()
	events:UnregisterAllEvents()
	wipe(waiting)
	wipe(banking)
	ns.Toast_Clear("gear")
end
