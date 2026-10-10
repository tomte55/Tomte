local addonName, ns = ...

-- Durability: a toast when the worst equipped item drops under a threshold (once per crossing) and a red one when
-- something breaks; plus a banner when you zone into a dungeon, raid or delve with low gear, the same way the
-- hunter pet check does. Rules in Data.lua.

local ENTER_DELAY = 4 -- seconds after zoning in, as the pet check
local ACCENT = "warning" -- toast and banner accents (roles)
local RED = "danger"
local ICON = "Interface\\Icons\\Trade_BlackSmithing"

local SLOT_NAMES = {
	[INVSLOT_HEAD] = "Head", [INVSLOT_SHOULDER] = "Shoulders", [INVSLOT_CHEST] = "Chest", [INVSLOT_WAIST] = "Waist",
	[INVSLOT_LEGS] = "Legs", [INVSLOT_FEET] = "Feet", [INVSLOT_WRIST] = "Wrists", [INVSLOT_HAND] = "Hands",
	[INVSLOT_MAINHAND] = "Main hand", [INVSLOT_OFFHAND] = "Off hand",
}

local module, db
local alertState = {}
local wornLinks = {} -- [slot] = link at the last check: tells a break from putting on a broken item

local function Slots()
	local list = {}
	for slot = INVSLOT_FIRST_EQUIPPED, INVSLOT_LAST_EQUIPPED do
		local cur, max = GetInventoryItemDurability(slot)
		if cur and max and max > 0 then
			list[#list + 1] = { slot = slot, cur = cur, max = max }
		end
	end
	return list
end

local function SlotName(slot)
	return SLOT_NAMES[slot] or ("slot " .. slot)
end

-- "Legs: [Item]" (the link keeps the item's quality color).
local function SlotText(slot)
	local link = GetInventoryItemLink("player", slot)
	return link and ("%s: %s"):format(SlotName(slot), link) or SlotName(slot)
end

-- Whether the worn gear changed since the last call (the first call counts as changed).
local function Swapped()
	local changed = next(wornLinks) == nil
	for slot = INVSLOT_FIRST_EQUIPPED, INVSLOT_LAST_EQUIPPED do
		local link = GetInventoryItemLink("player", slot) or false
		if wornLinks[slot] ~= link then
			changed = true
			wornLinks[slot] = link
		end
	end
	return changed
end

local function Check()
	local lowest, slot, broken = ns.Durability_Summary(Slots())
	local alert = ns.Durability_Alert(alertState, lowest, broken, db.threshold / 100, Swapped())
	if alert == "broken" and db.broken then
		ns.Toast_Show({
			owner = "dura", label = "Broken", accent = RED, title = broken == 1 and "An item broke" or (broken .. " items broke"),
			text = SlotText(slot) .. "\nIts stats don't count until you repair it.", icon = ICON, hold = 10,
			holdInCombat = true,
		})
	elseif alert == "broken" or alert == "low" then
		ns.Toast_Show({
			owner = "dura", label = "Durability", accent = ACCENT, title = "Gear at " .. ns.Durability_Percent(lowest),
			text = "Worst: " .. SlotText(slot), icon = ICON, hold = 8, holdInCombat = true,
		})
	end
end

local function InstanceCheck()
	if not module.active or not db.instance then
		return
	end
	local lowest, slot = ns.Durability_Summary(Slots())
	if not lowest or lowest >= db.instanceThreshold / 100 then
		return
	end
	ns.Banner_Show({
		owner = "dura",
		label = "Repair",
		accent = ACCENT,
		title = "Repair before you pull: gear at " .. ns.Durability_Percent(lowest),
		subtitle = "Worst: " .. SlotName(slot),
		icon = ICON,
		hold = 5,
	})
	PlaySound(SOUNDKIT.RAID_WARNING)
end

local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(self, event, ...)
	self[event](self, ...)
end)

events.UPDATE_INVENTORY_DURABILITY = Check
events.PLAYER_EQUIPMENT_CHANGED = Check

function events:PLAYER_ENTERING_WORLD()
	Check()
	local _, instanceType, difficultyID = GetInstanceInfo()
	if ns.Hunter_ContentKind(instanceType, difficultyID) then
		C_Timer.After(ENTER_DELAY, InstanceCheck)
	end
end

local function Toggle(active)
	if active then
		events:RegisterEvent("UPDATE_INVENTORY_DURABILITY")
		events:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
		events:RegisterEvent("PLAYER_ENTERING_WORLD")
		if ns.inWorld then
			Check()
		end
	else
		events:UnregisterAllEvents()
		ns.Toast_Clear("dura")
		ns.Banner_Clear("dura")
	end
end

local function Percent(v)
	return ("%d%%"):format(v)
end

-- Equipped items with durability, worst first.
local function Worst()
	local slots = Slots()
	table.sort(slots, function(a, b)
		return a.cur / a.max < b.cur / b.max
	end)
	return slots
end

-- The worst n slots as { { percent = "45%", text = "Legs: [Item]" } } (Home's Durability tooltip).
function ns.Durability_WorstSlots(n)
	local list = {}
	for i, s in ipairs(Worst()) do
		if i > n then
			break
		end
		list[i] = { percent = ns.Durability_Percent(s.cur / s.max), text = SlotText(s.slot) }
	end
	return list
end

-- /tomte dura list (and a click on Home's Durability).
function ns.Durability_List()
	local slots = Worst()
	if #slots == 0 then
		ns.Print("nothing equipped has durability.")
		return
	end
	ns.Print("durability:")
	for _, s in ipairs(slots) do
		print(("  %s  %s"):format(ns.Durability_Percent(s.cur / s.max), SlotText(s.slot)))
	end
end

module = ns.RegisterModule({
	key = "dura",
	name = "Durability",
	category = "Upkeep",
	description = "A toast when your gear drops below a durability threshold or an item breaks, and a warning when you enter a dungeon, raid or delve with low gear.",
	enabledByDefault = true,
	defaults = {
		threshold = 30, -- percent
		broken = true,
		instance = true,
		instanceThreshold = 50, -- percent
	},
	home = {
		{ kind = "next", key = "nextdura", name = "Low durability", score = 90,
			description = "Your worst item is under the durability threshold, or something broke.",
			candidates = function()
				local lowest, slot, broken = ns.Durability_Summary(Slots())
				if not lowest or (lowest >= db.threshold / 100 and (broken or 0) == 0) then
					return {}
				end
				local pct = math.floor(lowest * 100) -- floored like the toast and the list
				return { {
					key = "dura:low", state = math.floor(pct / 10),
					text = (broken or 0) > 0 and "Repair: something broke" or ("Repair: gear at %d%%"):format(pct),
					why = "Worst: " .. SlotText(slot), right = Percent(pct), icon = ICON,
					color = (broken or 0) > 0 and RED or nil,
				} }
			end },
	},
	init = function(moduleDB)
		db = moduleDB
	end,
	toggle = Toggle,
	commands = {
		{ "list", "durability of every equipped item, worst first", ns.Durability_List },
	},
	options = {
		{ type = "header", label = "Toasts" },
		{ type = "slider", key = "threshold", label = "Warn below", min = 10, max = 60, step = 5, format = Percent,
			tooltip = "One toast when your worst item drops below this. It warns again after you've repaired." },
		{ type = "checkbox", key = "broken", label = "When an item breaks" },
		{ type = "header", label = "Instances" },
		{ type = "checkbox", key = "instance", label = "Check when entering an instance",
			tooltip = "Dungeons, raids and delves." },
		{ type = "slider", key = "instanceThreshold", label = "Warn below", min = 20, max = 80, step = 5,
			format = Percent },
	},
})
