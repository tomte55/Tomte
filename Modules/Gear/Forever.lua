local addonName, ns = ...

-- Gear Check on World of Warcraft: Forever: a leveling helper. Upgrade verdicts on item tooltips, the same verdicts for
-- the Loot feed and the quest reward card (RewardCard.lua), and a click-to-equip toast for new upgrades in the bags.
-- Retail's Gear.lua and its files don't load there. Rules in ForeverRules.lua, item reading in ForeverItems.lua; only
-- the Forever TOC loads these (tools/forever_list.lua).

local SETTLE = 8 -- seconds after login or a loading screen in which bag items are only noted (bags fill in)
local RETRY = 1 -- seconds between tries for new items that are still loading
local MAX_TRIES = 12
local MAX_TOASTS = 3 -- at once (a mailbox full of gear)
local TOAST_HOLD = 30 -- seconds the click-to-equip toast stays
local EQUIPPED_HOLD = 5 -- seconds for the "Equipped" toast
local EQUIP_WAIT = 60 -- seconds a clicked item may take to be worn (a Bind on Equip popup waits for you)
local LEVEL_LAG = 2 -- seconds: UnitLevel (and the red "Requires Level" lines) can lag behind PLAYER_LEVEL_UP
local INFO_BURST = 0.3 -- seconds: item data arrives in bursts
-- Verdict color keys (Rules.lua) to theme roles, as retail's tooltip does.
local COLOR_ROLES = { green = "success", yellow = "warning", grey = "textMuted", red = "danger", orange = "warning" }
local MAX_REASONS = 3

local UI = ns.UI
local events = ns.Gear_Events

local module, db
local ownCtx
local seen = {} -- [link] = how many are in the bags (ForeverRules: GearForever_NewItems)
local pending = {} -- [link] = tries, new items whose data hasn't loaded
local settleUntil = 0
local banking = false
local retryQueued = false
local equipping -- { itemID, name, icon, oldName, untilTime }: clicked on the toast, not worn yet

-- Verdicts for other files --------------------------------------------------------------------------------------------

local function Context()
	if not ownCtx then
		local _, class = UnitClass("player")
		ownCtx = ns.GearForever_Context({ class = class, level = UnitLevel("player"),
			rangedSlot = ns.GearForever_RangedSlot(), levelingIlvl = db.levelingIlvl,
			weaponSkills = ns.GearForever_WeaponSkills() })
	end
	return ownCtx
end

-- verdict (nil when worn or not gear), candidate descriptor. Nothing while items load.
local function Evaluate(link, ctx)
	local worn = ns.GearForever_Worn()
	local cand = worn and ns.GearForever_Describe(link)
	if not cand then
		return nil
	end
	return ns.GearForever_Evaluate(cand, worn, ctx or Context()), cand
end

-- The same two functions retail's Gear.lua gives the Loot feed and the reward card.
function ns.Gear_Context()
	if not (module and module.active) then
		return nil
	end
	return Context()
end

function ns.Gear_Verdict(link, ctx)
	if not (module and module.active) then
		return nil
	end
	local v = Evaluate(link, ctx)
	if not v then
		return nil
	end
	return v, ns.Gear_Headline(v)
end

-- The arrow for an item in Tomte's own bags (Modules/Bags): "upgrade", "maybe" or nil, as retail's Baganator.lua says.
function ns.Gear_BagArrow(link)
	if not (module.active and link) then
		return nil
	end
	local verdict = Evaluate(link)
	if ns.Gear_IsCleanUpgrade(verdict) then
		return "upgrade"
	elseif ns.Gear_IsMaybeUpgrade(verdict) then
		return "maybe"
	end
	return nil
end

local function Invalidate()
	ownCtx = nil
	ns.GearRewardCard_Refresh()
	if ns.Bags_Reread then
		ns.Bags_Reread()
	end
end

-- Tooltips ---------------------------------------------------------------------------------------------------------

local function TooltipLink(tooltip)
	if TooltipUtil and TooltipUtil.GetDisplayedItem then
		local _, link = TooltipUtil.GetDisplayedItem(tooltip)
		return link
	end
	local _, link = tooltip:GetItem()
	return link
end

local function OnItem(tooltip)
	if not (module.active and tooltip.AddLine) then
		return
	end
	if (tooltip == ShoppingTooltip1 or tooltip == ShoppingTooltip2) and not db.compareTooltips then
		return
	end
	local link = TooltipLink(tooltip)
	if not link or ns.IsSecret(link) then
		return
	end
	local verdict = Evaluate(link)
	if not verdict or (verdict.kind == "downgrade" and not db.showDowngrades) then
		return
	end
	local headline, color = ns.Gear_Headline(verdict)
	tooltip:AddLine(UI.Wrap("Gear:", "accent") .. " " .. UI.Wrap(headline, COLOR_ROLES[color]), nil, nil, nil, true)
	if db.showReasons then
		for i = 1, math.min(#verdict.reasons, MAX_REASONS) do
			tooltip:AddLine(UI.Wrap("   " .. verdict.reasons[i], "textMuted"), nil, nil, nil, true)
		end
	end
end

local function HookTooltips()
	if module.tooltipHooked then
		return
	end
	module.tooltipHooked = true -- hooks can't be removed; OnItem checks module.active
	local hook = ns.Perf_Wrap(OnItem, "tooltip")
	if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall then
		TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, hook)
	elseif GameTooltip:HasScript("OnTooltipSetItem") then
		GameTooltip:HookScript("OnTooltipSetItem", hook)
		ItemRefTooltip:HookScript("OnTooltipSetItem", hook)
	end
end

-- New upgrades in the bags --------------------------------------------------------------------------------------------

local function FindInBags(link)
	for _, item in ipairs(ns.GearForever_BagGear()) do
		if item.link == link then
			return item
		end
	end
	return nil
end

-- The clicked item went on in this slot: a short toast says so.
local function CheckEquipped(slot)
	if not equipping then
		return
	end
	if GetTime() > equipping.untilTime then
		equipping = nil
		return
	end
	if GetInventoryItemID("player", slot) ~= equipping.itemID then
		return
	end
	ns.Toast_Show({
		owner = "gear",
		label = "Equipped",
		accent = "success",
		title = equipping.name,
		text = equipping.oldName and ("Replaced " .. equipping.oldName .. ".") or "Now worn.",
		icon = equipping.icon,
		hold = EQUIPPED_HOLD,
	})
	if db.equipSound and SOUNDKIT.UI_ITEM_UPGRADE_UI_ITEM_UPGRADED then
		PlaySound(SOUNDKIT.UI_ITEM_UPGRADE_UI_ITEM_UPGRADED)
	end
	equipping = nil
end

local function Equip(link, name, icon, oldName)
	if InCombatLockdown() then
		ns.Print_Combat("change gear")
		return
	end
	local found = FindInBags(link)
	if not found then
		ns.Print("Gear Check: that item isn't in your bags anymore.")
		return
	end
	-- Judged again: what's worn may have changed since (the weaker ring is the other one now).
	local verdict = Evaluate(link)
	equipping = { itemID = C_Item.GetItemInfoInstant(link), name = name or link, icon = icon, oldName = oldName,
		untilTime = GetTime() + EQUIP_WAIT }
	ClearCursor()
	if verdict and verdict.slot then
		C_Container.PickupContainerItem(found.bag, found.slot)
		EquipCursorItem(verdict.slot) -- bind-on-equip items ask first (Blizzard's popup)
	else
		(C_Item.EquipItemByName or EquipItemByName)(link)
	end
end

local function Toast(item)
	local v = item.verdict
	local name, _, quality, _, _, _, _, _, _, icon = C_Item.GetItemInfo(item.link)
	local worn = ns.GearForever_Worn()
	local old = worn and worn[v.slot]
	local oldName = old and C_Item.GetItemInfo(old.link)
	local color = ITEM_QUALITY_COLORS[quality or 1]
	ns.Session_Note("upgrade", { title = name or item.link, icon = icon, quality = quality,
		itemID = C_Item.GetItemInfoInstant(item.link), detail = ns.Gear_RevealLabel(v) })
	ns.Toast_Show({
		owner = "gear",
		label = ns.Gear_RevealLabel(v),
		accent = { color.r, color.g, color.b },
		title = name or item.link,
		text = (oldName and ("Replaces " .. oldName .. ". ") or "") .. "Click to equip, right-click to dismiss.",
		icon = icon,
		hold = TOAST_HOLD,
		holdInCombat = true,
		onClick = function()
			Equip(item.link, name, icon, oldName)
		end,
	})
end

-- Judges links and toasts the best per slot. Returns how many qualified; links still loading go into notReady.
local function Judge(links, notReady)
	local judged = {}
	for _, link in ipairs(links) do
		local verdict, cand = Evaluate(link)
		if cand then
			if verdict then
				judged[#judged + 1] = { link = link, verdict = verdict }
			end
		elseif notReady then
			notReady[#notReady + 1] = link
		end
	end
	local picks = ns.Gear_PickReveals(judged, 0)
	for i = 1, math.min(#picks, MAX_TOASTS) do
		Toast(picks[i])
	end
	return #picks
end

local Scan

local function QueueRetry()
	if retryQueued then
		return
	end
	retryQueued = true
	C_Timer.After(RETRY, function()
		retryQueued = false
		if module.active then
			Scan()
		end
	end)
end

local function BagLinks()
	local links = {}
	for _, item in ipairs(ns.GearForever_BagGear()) do
		links[#links + 1] = item.link
	end
	return links
end

-- Notes what's in the bags without saying anything.
local function NoteBags()
	local _, now = ns.GearForever_NewItems(seen, BagLinks())
	seen = now
end

function Scan()
	local new, now = ns.GearForever_NewItems(seen, BagLinks())
	seen = now
	if not db.revealToast or banking or GetTime() < settleUntil then
		wipe(pending)
		return
	end
	local links = {}
	for _, link in ipairs(new) do
		pending[link] = pending[link] or 0
	end
	for link in pairs(pending) do
		if now[link] then
			links[#links + 1] = link
		else
			pending[link] = nil -- it left the bags
		end
	end
	if #links == 0 then
		return
	end
	local notReady = {}
	Judge(links, notReady)
	local before = pending
	pending = {}
	for _, link in ipairs(notReady) do
		local tries = (before[link] or 0) + 1
		if tries < MAX_TRIES then
			pending[link] = tries
		end
	end
	if next(pending) then
		QueueRetry()
	end
end

-- Events -------------------------------------------------------------------------------------------------------------

events:On("gear", "PLAYER_ENTERING_WORLD", function()
	settleUntil = GetTime() + SETTLE
	ns.GearForever_ForgetWorn()
	NoteBags()
	Invalidate()
end)

events:On("gear", "PLAYER_EQUIPMENT_CHANGED", function(_, slot)
	ns.GearForever_ForgetWorn()
	Invalidate()
	CheckEquipped(slot)
end)

events:On("gear", "BAG_UPDATE_DELAYED", function()
	if GetTime() < settleUntil then
		NoteBags() -- bags still filling in after login
		return
	end
	Scan()
end)

-- Weapon skills go into the verdicts (ForeverRules: BehindSkill).
events:On("gear", "SKILL_LINES_CHANGED", function()
	Invalidate()
end)

events:On("gear", "PLAYER_LEVEL_UP", function()
	ns.GearForever_ForgetAll()
	Invalidate()
	C_Timer.After(LEVEL_LAG, function()
		if module.active then
			ns.GearForever_ForgetAll()
			Invalidate()
		end
	end)
end)

local refreshSoon = UI.Debounce(INFO_BURST, function()
	if module.active then
		Invalidate()
	end
end)
events:On("gear", "GET_ITEM_INFO_RECEIVED", refreshSoon)

-- Items taken out of a bank aren't new.
events:On("gear", "BANKFRAME_OPENED", function()
	banking = true
end)

events:On("gear", "BANKFRAME_CLOSED", function()
	banking = false
	C_Timer.After(0, NoteBags) -- the last withdrawals may land after the bank closed
end)

-- Commands -------------------------------------------------------------------------------------------------------------

local function ShowUpgrades()
	if not ns.Module_RequireOn(module) then
		return
	end
	local notReady = {}
	if Judge(BagLinks(), notReady) == 0 then
		ns.Print(#notReady > 0 and "Gear Check: some items are still loading, try again in a moment."
			or "Gear Check: no clean upgrades in your bags.")
	end
end

-- What Gear Check sees: for checking in game.
local function Why()
	if not ns.Module_RequireOn(module) then
		return
	end
	local ctx = Context()
	ns.Print(("Gear Check: %s level %s, ranged slot %s, %s."):format(tostring(ctx.class), tostring(ctx.level),
		tostring(ctx.rangedSlot), ctx.leveling and "higher item level wins" or "stats decide"))
	local worn = ns.GearForever_Worn()
	if not worn then
		ns.Print("Worn items are still loading, try again in a moment.")
		return
	end
	for slot = 1, 19 do
		local desc = worn[slot]
		if desc then
			ns.Print(("%d: %s, item level %s%s"):format(slot, desc.link, tostring(desc.ilvl),
				desc.dps and (", %.1f damage per second"):format(desc.dps) or ""))
		end
	end
end

-- Start and stop -----------------------------------------------------------------------------------------------------

local function Start()
	for _, event in ipairs({ "PLAYER_ENTERING_WORLD", "PLAYER_EQUIPMENT_CHANGED", "BAG_UPDATE_DELAYED",
		"PLAYER_LEVEL_UP", "GET_ITEM_INFO_RECEIVED", "SKILL_LINES_CHANGED" }) do
		events:Watch("gear", event)
	end
	events:TryWatch("gear", "BANKFRAME_OPENED")
	events:TryWatch("gear", "BANKFRAME_CLOSED")
	HookTooltips()
	settleUntil = GetTime() + SETTLE
	ns.GearForever_ForgetWorn()
	NoteBags()
	ns.GearRewardCard_Start(db)
	Invalidate()
end

local function Stop()
	events:UnwatchAll("gear")
	ns.GearRewardCard_Stop()
	ns.Toast_Clear("gear")
	wipe(pending)
	banking = false
	ownCtx = nil
	equipping = nil
end

module = ns.RegisterModule({
	key = "gear",
	name = "Gear Check",
	category = "gear",
	icon = 133071, -- inv_helmet_03
	summary = "Item tooltips say whether gear is an upgrade while you level, and why not.",
	description = "Says on each item's tooltip whether it's an upgrade for your class. While leveling a higher item "
		.. "level wins, weapons go by damage for the classes that swing them, and gear you can't use yet or with the "
		.. "wrong main stat says so. When a quest lets you choose a reward, a card names the best one and the one that "
		.. "sells for the most, and new upgrades in your bags get a toast you click to equip.",
	enabledByDefault = true,
	toasts = "Gear upgrades",
	defaults = {
		showReasons = true,
		showDowngrades = true,
		levelingIlvl = true,
		compareTooltips = false,
		rewardPick = true,
		rewardCard = { point = "TOP", relPoint = "TOP", x = 0, y = -120 }, -- the reward card's spot (/tomte unlock)
		revealToast = true,
		equipSound = true,
	},
	init = function(moduleDB)
		db = moduleDB
	end,
	toggle = function(active)
		if active then
			Start()
		else
			Stop()
		end
	end,
	commands = {
		{ "upgrades", "toast the clean upgrades already in your bags", ShowUpgrades },
		{ "why", "your class, level and worn gear as Gear Check reads them", Why },
	},
	options = {
		{ type = "header", label = "Tooltip" },
		{ type = "checkbox", key = "showReasons", label = "Show reasons",
			tooltip = "Short lines under the verdict, e.g. the damage of both weapons." },
		{ type = "checkbox", key = "showDowngrades", label = "Show downgrades" },
		{ type = "checkbox", key = "levelingIlvl", label = "While leveling, higher item level wins", onChange = Invalidate,
			tooltip = "Below level 60, gear with a higher item level is an upgrade and gear with a lower one a downgrade. "
				.. "Weapons still go by damage for the classes that swing them. Off, rough stat values for your class "
				.. "decide." },
		{ type = "checkbox", key = "compareTooltips", label = "Also on comparison tooltips",
			tooltip = "The tooltips of your equipped items that appear next to the hovered one." },
		{ type = "header", label = "New gear" },
		{ type = "checkbox", key = "rewardPick", label = "Quest reward pick", onChange = function()
			ns.GearRewardCard_Refresh()
		end, preview = ns.Preview_When("rewardPick", function(host)
			return ns.GearRewardCard_DrawSample(host)
		end), tooltip = "When a quest lets you choose a reward, a card names the best one for you and the one that sells "
			.. "for the most. Move it with /tomte unlock." },
		{ type = "checkbox", key = "revealToast", label = "Equip toast",
			tooltip = "A toast when gear new to your bags is a clean upgrade: click it to equip the item, right-click to "
				.. "dismiss. Not in combat." },
		{ type = "checkbox", key = "equipSound", label = "Sound when equipped", parent = "revealToast",
			tooltip = "Play the item upgrade sound with the \"Equipped\" toast once the upgrade from the toast is worn." },
	},
})
ns.gearModule = module
