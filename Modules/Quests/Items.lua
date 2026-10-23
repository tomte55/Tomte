local addonName, ns = ...

-- Quests: items that start a quest. Deleting one shows a card under the game's "Delete this item?" question naming
-- the quest and where you stand with it; its tooltip in your bags says the same. The quest comes from the bag slot
-- (C_Container.GetContainerItemQuestInfo), so it's read where the item sits: the cursor's slot while deleting,
-- the tooltip's bag slot. State text in Data.lua; started and stopped by Quests.lua.

local OWNER = "items"
local CARD_W = 300
local PAD = 10
local CARD_GAP = 4 -- below the game's question
-- The game's delete questions, quest items first (GameDialogDefs.lua).
local DELETE_POPUPS = { "DELETE_QUEST_ITEM", "DELETE_GOOD_QUEST_ITEM", "DELETE_ITEM", "DELETE_GOOD_ITEM" }
-- Item classes that can start a quest: Questitem (12) and Miscellaneous (15).
local STARTER_CLASSES = { [12] = true, [15] = true }

local UI = ns.UI
local IsSecret = ns.IsSecret
local events = ns.Quests_Events

local db
local enabled = false
local hooked = false
local card
local cardQuest -- questID the card shows
local requested = {} -- [questID] = true once its data was asked for

local function QuestTitle(questID)
	local title = C_QuestLog.GetTitleForQuestID(questID)
	if title and not IsSecret(title) then
		return title
	end
	if not requested[questID] then
		requested[questID] = true
		C_QuestLog.RequestLoadQuestByID(questID)
	end
	return nil
end

local function State(questID)
	return ns.Quests_ItemQuestState({
		onQuest = C_QuestLog.IsOnQuest(questID),
		ready = C_QuestLog.ReadyForTurnIn(questID),
		done = C_QuestLog.IsQuestFlaggedCompleted(questID),
		doneOnAccount = C_QuestLog.IsQuestFlaggedCompletedOnAccount(questID),
	})
end

-- The quest an item in a bag slot starts, or nil.
local function SlotQuest(bag, slot)
	if not (bag and slot) or IsSecret(bag, slot) then
		return nil
	end
	local info = C_Container.GetContainerItemQuestInfo(bag, slot)
	local questID = info and info.questID
	if questID and not IsSecret(questID) and questID ~= 0 then
		return questID
	end
	return nil
end

-- Delete card -----------------------------------------------------------------------------------------------------

local function Build()
	card = CreateFrame("Frame", nil, UIParent)
	card:SetSize(CARD_W, 60)
	card:SetFrameStrata("DIALOG")
	card:SetClampedToScreen(true)
	card:Hide()
	UI.Panel(card, { size = "small" })
	card.title = UI.Text(card, 11, "warning", "label")
	card.title:SetPoint("TOPLEFT", PAD, -PAD)
	card.title:SetText("This item starts a quest")
	card.quest = UI.Text(card, 14, "heading", "title")
	card.quest:SetPoint("TOPLEFT", card.title, "BOTTOMLEFT", 0, -4)
	card.quest:SetWidth(CARD_W - 2 * PAD)
	card.state = UI.Text(card, 12, "textMuted")
	card.state:SetPoint("TOPLEFT", card.quest, "BOTTOMLEFT", 0, -4)
	card.state:SetWidth(CARD_W - 2 * PAD)
end

local function DeleteDialog()
	for _, which in ipairs(DELETE_POPUPS) do
		local name, dialog = StaticPopup_Visible(which)
		dialog = dialog or (name and _G[name])
		if dialog then
			return dialog
		end
	end
	return nil
end

local function HideCard()
	cardQuest = nil
	events:Unwatch(OWNER, "CURSOR_CHANGED")
	if card then
		card:Hide()
	end
end

local function FillCard()
	local questID = cardQuest
	card.quest:SetText(QuestTitle(questID) or ("Quest " .. questID))
	local text, role = State(questID)
	card.state:SetText(text)
	UI.SetTextRole(card.state, role)
	card:SetHeight(PAD * 2 + card.title:GetStringHeight() + card.quest:GetStringHeight()
		+ card.state:GetStringHeight() + 8)
	card:ClearAllPoints()
	local dialog = DeleteDialog()
	if dialog then
		card:SetPoint("TOP", dialog, "BOTTOM", 0, -CARD_GAP)
	else
		card:SetPoint("TOP", UIParent, "TOP", 0, -260)
	end
	card:Show()
end

local function OnDeleteConfirm()
	if not db.itemDelete then
		return
	end
	local location = C_Cursor.GetCursorItem()
	local questID
	if location and location:IsBagAndSlot() then
		questID = SlotQuest(location:GetBagAndSlot())
	end
	if not questID then
		HideCard()
		return
	end
	if not card then
		Build()
	end
	cardQuest = questID
	events:Watch(OWNER, "CURSOR_CHANGED")
	C_Timer.After(0, function() -- once the game's question is up, to sit under it
		if cardQuest == questID then
			FillCard()
		end
	end)
end

events:On(OWNER, "DELETE_ITEM_CONFIRM", OnDeleteConfirm)
events:On(OWNER, "CURSOR_CHANGED", function()
	if not CursorHasItem() then -- deleted, or put back (No and Esc clear the cursor)
		HideCard()
	end
end)
events:On(OWNER, "QUEST_DATA_LOAD_RESULT", function(_, questID)
	if cardQuest and questID == cardQuest and card and card:IsShown() then
		FillCard()
	end
end)

-- Tooltip ---------------------------------------------------------------------------------------------------------

local function OnItem(tooltip, data)
	if not (enabled and db.itemTooltip and tooltip.AddLine and data) then
		return
	end
	local itemID = data.id
	if IsSecret(itemID) or type(itemID) ~= "number" then
		return
	end
	local classID = select(6, C_Item.GetItemInfoInstant(itemID))
	if not STARTER_CLASSES[classID] then
		return
	end
	local info = tooltip.processingInfo
	local args = info and info.getterName == "GetBagItem" and info.getterArgs
	local questID = args and SlotQuest(args[1], args[2])
	if not questID then
		return
	end
	local text, role = State(questID)
	tooltip:AddLine(" ")
	tooltip:AddLine(UI.Wrap("Starts: ", "textMuted") .. UI.Wrap(QuestTitle(questID) or ("quest " .. questID),
		"heading"), 1, 1, 1, true)
	tooltip:AddLine(UI.Wrap(text, role), 1, 1, 1, true)
end

-- Start and stop --------------------------------------------------------------------------------------------------

function ns.QuestsItems_Start(moduleDB)
	db = moduleDB
	enabled = true
	events:Watch(OWNER, "DELETE_ITEM_CONFIRM")
	events:Watch(OWNER, "QUEST_DATA_LOAD_RESULT")
	if not hooked then
		hooked = true -- post-calls can't be removed; OnItem checks enabled
		TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, OnItem)
	end
end

function ns.QuestsItems_Stop()
	enabled = false
	events:UnwatchAll(OWNER)
	HideCard()
end
