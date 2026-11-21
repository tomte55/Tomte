local addonName, ns = ...

-- Quest list: the quest item button. One button beside the list holds the usable item of the quest that matters now
-- (Data.lua's QuestList_ItemQuest: the followed quest's, else the first one down the list), and a key binding presses
-- it. Using an item is protected, so the button is secure: it can't be anchored to the list (protected frames can't
-- anchor to ordinary ones), so it's placed in UIParent's coordinates next to it, and it changes only out of combat. In
-- a fight it keeps the item it had; what changed is applied when the fight ends. Started from QuestList.lua.
-- A quest the game gives no quest log item (most of Forever's) can still have one: an item in your bags that Forever's
-- quest item data ties to it (Data.lua's QuestList_BagItems), such as the Etched Phial you use at the Sacred Flame.

local BUTTON_NAME = "TomteQuestItem" -- named for the CLICK binding (Bindings.xml)
local BINDING = "CLICK " .. BUTTON_NAME .. ":LeftButton"
local SIZE = 36
local GAP = 6 -- between the list and the button

local UI = ns.UI
local events = ns.QuestList_Events
local OWNER = "questListItem"

local button
local active = false
local pending -- { quest, list } waiting for the fight to end; false: hide then
local questID -- the quest whose item the button holds
local itemID, fromBag -- that item, and whether it's a bag item rather than the quest log's own
local bagItems, bagCounts = {}, {} -- [questID] = itemID (QuestList_BagItems), [itemID] = how many you carry
local bagKey = "" -- what bagItems were read from: bags that change other items don't redraw the list
local onBagsChanged -- the list's redraw, from QuestListItem_Start

local function LogIndex()
	return questID and C_QuestLog.GetLogIndexForQuestID(questID)
end

local function UpdateCooldown()
	if not (button and questID) then
		return
	end
	local start, duration, enable
	if fromBag then
		start, duration, enable = C_Item.GetItemCooldown(itemID)
	else
		local index = LogIndex()
		if not index then
			return
		end
		start, duration, enable = GetQuestLogSpecialItemCooldown(index)
	end
	if start and not ns.IsSecret(start, duration, enable) then
		CooldownFrame_Set(button.cooldown, start, duration, enable)
	end
end

local function UpdateHotkey()
	if not button then
		return
	end
	local key = GetBindingKey(BINDING)
	button.hotkey:SetText(key and GetBindingText(key, true) or "")
end

local function ShowTooltip(self)
	if fromBag and itemID then
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		GameTooltip:SetItemByID(itemID)
		GameTooltip:Show()
		return
	end
	local index = LogIndex()
	if not index then
		return
	end
	GameTooltip:SetOwner(self, "ANCHOR_LEFT")
	GameTooltip:SetQuestLogSpecialItem(index)
	GameTooltip:Show()
end

-- Reads which quests have an item in your bags; true when that changed (the list redraws then).
local function ReadBags()
	local data = ns.Content_Get(ns.CONTENT_FOREVER, "questItems")
	local carried, counts = {}, {}
	if data then
		carried, counts = ns.QuestListRead_CarriedQuestItems(data)
	end
	local parts = {}
	for i, id in ipairs(carried) do
		parts[i] = id .. "x" .. counts[id]
	end
	local key = table.concat(parts, ",")
	if key == bagKey then
		return false
	end
	bagKey, bagCounts = key, counts
	bagItems = data and ns.QuestList_BagItems(data, carried) or {}
	return true
end

-- From QuestList.lua's update: quests the game gives no item get the one in your bags that belongs to them.
function ns.QuestListItem_AddBagItems(quests)
	for _, q in ipairs(quests) do
		local id = not q.itemLink and bagItems[q.questID]
		if id then
			q.itemLink, q.itemCharges, q.bagItem = "item:" .. id, bagCounts[id], true
		end
	end
end

-- Out of combat only: protected frames can't be made in combat.
local function CreateButton()
	button = CreateFrame("Button", BUTTON_NAME, UIParent, "SecureActionButtonTemplate")
	button:SetSize(SIZE, SIZE)
	button:SetFrameStrata("MEDIUM")
	button:SetClampedToScreen(true)
	button:RegisterForClicks("AnyUp", "AnyDown")
	button:SetAttribute("useOnKeyDown", true) -- the key binding uses it on the press, as action bars do
	button:SetAttribute("type", "item")
	button.icon = button:CreateTexture(nil, "ARTWORK")
	button.icon:SetAllPoints()
	UI.ActionIcon(button, button.icon, SIZE)
	button.cooldown = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
	button.cooldown:SetAllPoints(button.icon)
	button.count = UI.Text(button, 11, "text", "number")
	button.count:SetPoint("BOTTOMRIGHT", -2, 2)
	button.hotkey = UI.Text(button, 10, "textMuted", "label")
	button.hotkey:SetPoint("TOPRIGHT", -2, -2)
	button:SetScript("OnEnter", ShowTooltip)
	button:SetScript("OnLeave", GameTooltip_Hide)
	button:Hide()
end

-- Next to the list in UIParent's coordinates: on the side toward the middle of the screen, level with its top.
local function Place(list)
	local left, top, right = list:GetLeft(), list:GetTop(), list:GetRight()
	if not (left and top and right) then
		return false
	end
	local s = list:GetEffectiveScale() / UIParent:GetEffectiveScale()
	button:ClearAllPoints()
	if (left + right) / 2 * s > UIParent:GetWidth() / 2 then
		button:SetPoint("TOPRIGHT", UIParent, "BOTTOMLEFT", left * s - GAP, top * s)
	else
		button:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", right * s + GAP, top * s)
	end
	return true
end

-- Out of combat: the button holds quest's item next to list, or hides (quest nil).
local function Apply(quest, list)
	itemID = quest and quest.itemLink and tonumber(quest.itemLink:match("item:(%d+)"))
	fromBag = quest and quest.bagItem or false
	if not (itemID and list) then
		questID = nil
		if button then
			button:Hide()
		end
		return
	end
	if not button then
		CreateButton()
	end
	if not Place(list) then
		button:Hide()
		return
	end
	questID = quest.questID
	button:SetAttribute("item", "item:" .. itemID)
	button.icon:SetTexture(quest.itemIcon or C_Item.GetItemIconByID(itemID))
	button.count:SetText(quest.itemCharges and quest.itemCharges > 1 and quest.itemCharges or "")
	UpdateHotkey()
	UpdateCooldown()
	button:Show()
end

-- From QuestList.lua's draw: quest (a quest row with an item) or nil, and the list frame it sits beside.
function ns.QuestListItem_Set(quest, list)
	if not active or not ns.QuestList_DB().itemButton then
		quest = nil
	end
	if InCombatLockdown() then
		pending = quest and { quest = quest, list = list } or false
		return
	end
	pending = nil
	Apply(quest, list)
end

events:On(OWNER, "PLAYER_REGEN_ENABLED", function()
	if not active then
		events:Unwatch(OWNER, "PLAYER_REGEN_ENABLED") -- only kept for hiding after a fight (QuestListItem_Stop)
	end
	if pending ~= nil then
		local p = pending
		pending = nil
		if p then
			Apply(p.quest, p.list)
		else
			Apply(nil)
		end
	end
end)
events:On(OWNER, "BAG_UPDATE_COOLDOWN", UpdateCooldown)
events:On(OWNER, "UPDATE_BINDINGS", UpdateHotkey)
events:On(OWNER, "BAG_UPDATE_DELAYED", function()
	if ReadBags() and onBagsChanged then
		onBagsChanged()
	end
end)

-- onChange: the list's redraw, called when the quest items in your bags change.
function ns.QuestListItem_Start(onChange)
	active = true
	onBagsChanged = onChange
	bagKey = nil -- read again: the bags may have changed while the list was off
	ReadBags()
	for _, event in ipairs({ "PLAYER_REGEN_ENABLED", "BAG_UPDATE_COOLDOWN", "UPDATE_BINDINGS", "BAG_UPDATE_DELAYED" }) do
		events:Watch(OWNER, event)
	end
end

-- The list is off: the button goes (after the fight, if there is one; PLAYER_REGEN_ENABLED stays watched until then).
function ns.QuestListItem_Stop()
	active = false
	onBagsChanged = nil
	events:Unwatch(OWNER, "BAG_UPDATE_COOLDOWN")
	events:Unwatch(OWNER, "UPDATE_BINDINGS")
	events:Unwatch(OWNER, "BAG_UPDATE_DELAYED")
	if InCombatLockdown() then
		pending = false
		return
	end
	events:Unwatch(OWNER, "PLAYER_REGEN_ENABLED")
	pending = nil
	Apply(nil)
end
