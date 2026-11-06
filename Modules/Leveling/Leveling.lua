local addonName, ns = ...

-- Leveling (World of Warcraft: Forever only; tools/forever_list.lua): what a level up means for you. What's new at your
-- class trainer, old spell ranks on your bars, talent points, ammo and reagents, weapon skills and your quests sorted by
-- what's worth doing. Forever has spell ranks, ammo and weapon skills; retail has none of them. Rules in Data.lua, reads
-- in Read.lua, the page in Page.lua. See docs/superpowers/specs/2026-11-05-tomte-forever-leveling.md.

local ICON = 134376 -- the icon of its settings group (Panel/Layout.lua)
local LEVEL_DELAY = 2 -- seconds: UnitLevel and the spellbook can lag behind PLAYER_LEVEL_UP
local CHECK_DELAY = 2 -- seconds of quiet before bars and supplies are read again
local TOAST_HOLD = 12
local BUY_W, BUY_GAP = 230, 4
local BUY_SETTLE = 1.5 -- seconds after a purchase before the bags are trusted again: they update as the server answers
local AUTO_DELAY = 1 -- seconds after a vendor opens: an item whose data hasn't loaded has no level, and could pick wrong
local PAGE_KEY = "levelingpage"
ns.LEVELING_PAGE_KEY = PAGE_KEY -- the Home section opens it

local UI = ns.UI

local module, db, buyButton
local events = CreateFrame("Frame")
local oldRanksKnown -- [spell text] = true: already told; nil until the first read, which says nothing
local lowSupplies = {} -- [key] = true: already warned, until it recovers
local merchantOpen = false
local buySettling = false -- a purchase was just made and the bags haven't caught up

function ns.Leveling_DB()
	return db
end

local function Toast(label, title, text, icon)
	ns.Toast_Show({
		owner = "leveling",
		label = label,
		title = title,
		text = text,
		icon = icon or ICON,
		hold = TOAST_HOLD,
		onClick = function()
			ns.Panel_OpenPage(PAGE_KEY)
		end,
	})
end

-- Trainer ------------------------------------------------------------------------------------------------------------

local function SaveTrainer()
	local rows, seesLater = ns.LevelingRead_Trainer()
	if not rows then
		return
	end
	local guid = UnitGUID("player")
	local char = db.chars[guid] or {}
	char.services = ns.Leveling_MergeTrainer(char.services, rows, UnitLevel("player"), seesLater)
	db.chars[guid] = char
	ns.LevelingPage_Refresh()
end

local function LevelReport()
	if not module.active then
		return
	end
	local char = db.chars[UnitGUID("player")]
	if db.trainer and char and char.services then
		local ready = ns.Leveling_TrainerSplit(char.services, UnitLevel("player"))
		if #ready > 0 then
			local names = {}
			for i, s in ipairs(ready) do
				names[i] = ns.Leveling_ServiceName(s)
			end
			Toast("Class trainer", ("%d new to learn"):format(#ready), ns.Leveling_JoinNames(names, 4))
		end
	end
	if db.talents and ns.LevelingRead_UnspentTalents() then
		Toast("Talents", "Talent points to spend", "Open your talents and spend them.")
	end
	ns.LevelingPage_Refresh()
end

-- Bars and supplies ----------------------------------------------------------------------------------------------------

local function CheckRanks(bars)
	local known = {}
	local fresh = {}
	for _, text in ipairs(ns.Leveling_OldRanks(bars)) do
		known[text] = true
		if oldRanksKnown and not oldRanksKnown[text] then
			fresh[#fresh + 1] = text
		end
	end
	oldRanksKnown = known
	if db.ranks and #fresh > 0 then
		Toast("Spell ranks", "An old rank is on your bars", ns.Leveling_JoinNames(fresh, 3))
	end
end

local function CheckSupplies(bars)
	local keys, entries = {}, {}
	local needs, count = ns.LevelingRead_Ammo()
	local state = db.ammo and ns.Leveling_AmmoState(needs, count, db.ammoLow)
	if state == "none" or state == "low" then
		local name, icon = ns.LevelingRead_AmmoItem()
		keys[1] = "ammo:" .. state
		entries[keys[1]] = { kind = "ammo", out = state == "none", name = name, icon = icon,
			countText = ns.Thousands(count) }
	end
	if db.reagents then
		for _, r in ipairs(ns.Leveling_LowReagents(bars, db.reagentLow)) do
			local key = "reagent:" .. r.name
			keys[#keys + 1] = key
			entries[key] = { kind = "reagent", name = r.name, count = r.count }
		end
	end
	local fresh
	fresh, lowSupplies = ns.Leveling_NewlyLow(lowSupplies, keys)
	if #fresh > 0 then
		local list = {}
		for i, key in ipairs(fresh) do
			list[i] = entries[key]
		end
		local title, text, icon = ns.Leveling_SupplyToast(list)
		Toast("Supplies", title, text, icon)
	end
end

-- What the button buys right now: the item, how many and what that costs. Filling an ammo bag only offers the best ammo
-- you can use, so being short on gold doesn't fill it with worse; without one, you get the best you can afford a stack of.
local function PlanPurchase(weapon, money)
	local items, level = ns.LevelingRead_Merchant(), UnitLevel("player")
	local item = ns.Leveling_PickAmmo(items, weapon, level)
	if not item then
		return nil
	end
	local ammoRoom, normalRoom = ns.Leveling_AmmoRoom(ns.LevelingRead_AmmoBags(item), item.maxStack)
	if not ammoRoom then
		item = ns.Leveling_PickAmmo(items, weapon, level, money)
		if not item then
			return nil
		end
		ammoRoom, normalRoom = ns.Leveling_AmmoRoom(ns.LevelingRead_AmmoBags(item), item.maxStack)
	end
	local amount, cost = ns.Leveling_AmmoFill(item, ammoRoom, normalRoom, C_Item.GetItemCount(item.itemID), db.ammoTarget,
		money)
	return amount > 0 and { item = item, amount = amount, cost = cost } or nil
end

local UpdateBuyButton

local function Buy(plan)
	-- The button is gone until the bags have caught up: buying again on the old numbers would overflow.
	buySettling = true
	buyButton.plan = nil
	buyButton:Hide()
	for _, quantity in ipairs(ns.Leveling_BuyBatches(plan.amount, plan.item.maxBuy)) do
		BuyMerchantItem(plan.item.index, quantity)
	end
	C_Timer.After(BUY_SETTLE, function()
		buySettling = false
		if module.active then
			UpdateBuyButton()
		end
	end)
end

local function AutoBuy()
	local needs, _, weapon = ns.LevelingRead_Ammo()
	if not (merchantOpen and not buySettling and db.ammoBuy and db.ammoAuto and needs) then
		return
	end
	local plan = PlanPurchase(weapon, ns.Leveling_AutoBudget(GetMoney()))
	if plan then
		Buy(plan)
		Toast("Supplies", "Ammo bought", ("%s x%s for %s."):format(plan.item.name, ns.Thousands(plan.amount),
			ns.Price(plan.cost)), plan.item.icon)
	end
end

UpdateBuyButton = function()
	if not buyButton then
		return
	end
	local needs, _, weapon = ns.LevelingRead_Ammo()
	local plan
	if merchantOpen and not buySettling and db.ammoBuy and needs then
		plan = PlanPurchase(weapon, GetMoney())
	end
	buyButton.plan = plan
	if plan then
		buyButton.label:SetText(("Buy %s x%s (%s)"):format(plan.item.name, ns.Thousands(plan.amount), ns.Price(plan.cost)))
	end
	buyButton:SetShown(plan ~= nil)
end

local function CreateBuyButton()
	buyButton = UI.Button(MerchantFrame, BUY_W, "")
	buyButton:SetPoint("BOTTOM", MerchantFrame, "TOP", 0, BUY_GAP)
	buyButton:SetScript("OnClick", function(self)
		if self.plan then
			Buy(self.plan)
		end
	end)
	buyButton:Hide()
end

local check = UI.Debounce(CHECK_DELAY, function()
	if not module.active or InCombatLockdown() then
		return
	end
	local bars = ns.LevelingRead_Bars()
	CheckRanks(bars)
	CheckSupplies(bars)
	UpdateBuyButton()
	ns.LevelingPage_Refresh()
end)

-- Events ---------------------------------------------------------------------------------------------------------------

function events:PLAYER_ENTERING_WORLD()
	check()
end

function events:PLAYER_LEVEL_UP()
	C_Timer.After(LEVEL_DELAY, LevelReport)
	check()
end

function events:TRAINER_SHOW()
	SaveTrainer()
end

function events:TRAINER_UPDATE()
	SaveTrainer()
end

function events:TRAINER_SERVICE_INFO_NAME_UPDATE()
	SaveTrainer()
end

events.SPELLS_CHANGED = check
events.ACTIONBAR_SLOT_CHANGED = check
events.BAG_UPDATE_DELAYED = check
events.PLAYER_EQUIPMENT_CHANGED = check
events.PLAYER_REGEN_ENABLED = check -- reagents and ammo used in combat aren't read during it

function events:MERCHANT_SHOW()
	merchantOpen = true
	if not buyButton then
		CreateBuyButton()
	end
	UpdateBuyButton()
	C_Timer.After(AUTO_DELAY, AutoBuy)
end

events.MERCHANT_UPDATE = UpdateBuyButton

function events:MERCHANT_CLOSED()
	merchantOpen = false
	UpdateBuyButton()
end

function events:SKILL_LINES_CHANGED()
	ns.LevelingPage_Refresh()
end

function events:QUEST_LOG_UPDATE()
	ns.LevelingPage_Refresh()
end

function events:PLAYER_XP_UPDATE()
	ns.LevelingPage_Refresh()
end

function events:UPDATE_EXHAUSTION()
	ns.LevelingPage_Refresh()
end

local EVENTS = {
	"PLAYER_XP_UPDATE", "UPDATE_EXHAUSTION",
	"PLAYER_ENTERING_WORLD", "PLAYER_LEVEL_UP", "TRAINER_SHOW", "TRAINER_UPDATE", "TRAINER_SERVICE_INFO_NAME_UPDATE",
	"SPELLS_CHANGED", "ACTIONBAR_SLOT_CHANGED", "BAG_UPDATE_DELAYED", "PLAYER_EQUIPMENT_CHANGED", "PLAYER_REGEN_ENABLED",
	"MERCHANT_SHOW", "MERCHANT_UPDATE", "MERCHANT_CLOSED", "SKILL_LINES_CHANGED", "QUEST_LOG_UPDATE",
}

events:SetScript("OnEvent", ns.Perf_WrapEvents(function(self, event, ...)
	self[event](self, ...)
end))

-- Commands ------------------------------------------------------------------------------------------------------------

local function Why()
	if not ns.Module_RequireOn(module) then
		return
	end
	local char = db.chars[UnitGUID("player")]
	local level = UnitLevel("player")
	if char and char.services then
		local ready, nextLevel = ns.Leveling_TrainerSplit(char.services, level)
		ns.Print(("Leveling: %d saved from your trainer, %d to learn now, next at level %s."):format(#char.services, #ready,
			tostring(nextLevel)))
	else
		ns.Print("Leveling: no visit to your class trainer saved yet.")
	end
	local bars = ns.LevelingRead_Bars()
	local needs, count, weapon = ns.LevelingRead_Ammo()
	ns.Print(("%d spells on your bars, %d old ranks, %d low on reagents."):format(#bars, #ns.Leveling_OldRanks(bars),
		#ns.Leveling_LowReagents(bars, db.reagentLow)))
	ns.Print(("Uses ammo: %s, count %s, weapon type %s. Talent points: %s."):format(tostring(needs), tostring(count),
		tostring(weapon), tostring(ns.LevelingRead_UnspentTalents())))
	ns.Print(("%d quests, %d weapon skills."):format(#ns.LevelingRead_Quests(), #ns.LevelingRead_Skills()))
end

-- Module ---------------------------------------------------------------------------------------------------------------

module = ns.RegisterModule({
	key = "leveling",
	name = "Leveling",
	category = "week",
	icon = ICON,
	summary = "What's new at your trainer, old spell ranks, ammo and reagents, and which quests to do.",
	description = "A page and short toasts for leveling: what's new at your class trainer after each level (Tomte learns "
		.. "the list when you visit), old spell ranks still on your bars, unspent talent points, low ammo and reagents, "
		.. "weapon skills that are behind, and your quests sorted into ready to turn in, worth doing now, hard and grey.",
	enabledByDefault = true,
	toasts = "Leveling",
	defaults = {
		home = true,
		trainer = true,
		ranks = true,
		talents = true,
		ammo = true,
		ammoLow = 100,
		ammoTarget = 400,
		ammoBuy = true,
		ammoAuto = false,
		reagents = true,
		reagentLow = 5,
		chars = {}, -- [player GUID] = { services = { { name, rank, level, cost } } } from the last class trainer visit
	},
	keep = { "chars" },
	noShare = { "chars" },
	home = {
		ns.LevelingHomeSection,
		{ kind = "page", key = PAGE_KEY, order = 2, name = "Leveling", icon = ICON, page = ns.LevelingPage,
			summary = function()
				local char = db and db.chars[UnitGUID("player")]
				if not (char and char.services) then
					return "Visit your class trainer once"
				end
				local ready = ns.Leveling_TrainerSplit(char.services, UnitLevel("player"))
				return #ready > 0 and ("%d to learn at your trainer"):format(#ready) or "Nothing new at your trainer"
			end },
	},
	init = function(moduleDB)
		db = moduleDB
	end,
	toggle = function(active)
		if active then
			for _, event in ipairs(EVENTS) do
				events:RegisterEvent(event)
			end
			check()
		else
			events:UnregisterAllEvents()
			merchantOpen = false
			oldRanksKnown = nil
			wipe(lowSupplies)
			if buyButton then
				buyButton:Hide()
			end
			ns.Toast_Clear("leveling")
		end
	end,
	commands = {
		{ "open", "open the Leveling page", function()
			ns.Panel_OpenPage(PAGE_KEY)
		end },
		{ "why", "what Leveling reads right now: trainer list, bars, ammo, talents", Why },
	},
	options = {
		{ type = "header", label = "Home" },
		{ type = "checkbox", key = "home", label = "Show on Home", onChange = function()
			ns.Panel_Refresh()
		end, tooltip = "Your XP and what's waiting, at the top of Home until you reach the level cap." },
		{ type = "header", label = "After a level up" },
		{ type = "checkbox", key = "trainer", label = "New at your class trainer",
			tooltip = "A toast with what you can learn now. Tomte learns the list when you visit your class trainer, so visit once first." },
		{ type = "checkbox", key = "talents", label = "Talent points to spend" },
		{ type = "checkbox", key = "ranks", label = "Old ranks on your bars",
			tooltip = "A toast when a spell on your bars has a higher rank you know. Tomte names it; you drag the new one on." },
		{ type = "header", label = "Supplies" },
		{ type = "checkbox", key = "ammo", label = "Ammo warning", onChange = check },
		{ type = "slider", key = "ammoLow", label = "Warn at", min = 20, max = 400, step = 20, parent = "ammo",
			onChange = check },
		{ type = "checkbox", key = "ammoBuy", label = "Buy ammo button at vendors", onChange = check,
			tooltip = "A button above the vendor's window when it sells the right ammo for your weapon. One click fills your quiver or ammo pouch, and nothing spills into your other bags." },
		{ type = "checkbox", key = "ammoAuto", label = "Buy automatically", parent = "ammoBuy",
			tooltip = "Buys when you open a vendor that sells your ammo, without a click, spending at most a quarter of your gold. A toast says what it bought." },
		{ type = "slider", key = "ammoTarget", label = "Buy up to, no quiver", min = 200, max = 2000, step = 200,
			parent = "ammoBuy", onChange = check,
			tooltip = "How much ammo one click buys when you have no quiver or ammo pouch for it, so it doesn't take over your bags." },
		{ type = "checkbox", key = "reagents", label = "Reagent warning", onChange = check,
			tooltip = "Spells on your action bars that use a reagent and have few casts left." },
		{ type = "slider", key = "reagentLow", label = "Warn at casts left", min = 1, max = 20, step = 1,
			parent = "reagents", onChange = check },
	},
})
