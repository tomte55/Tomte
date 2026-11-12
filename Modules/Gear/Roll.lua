local addonName, ns = ...

-- Gear Check, roll advice (World of Warcraft: Forever only; tools/forever_list.lua): a card beside each group loot roll
-- saying need, greed or pass and why, with that button lit. A small upgrade gives way to a party member the item is
-- built for (their class and group role, read here; never inspected). It only suggests. Rules in RollData.lua, verdicts from
-- Forever.lua (ns.GearForever_RollVerdict), the setting is "Roll advice" there. Blizzard's GroupLootFrame1-4
-- (Blizzard_UIPanels_Game, GroupLootFrame.lua) call GroupLootFrame_SetupItemDisplay for each roll they show; that's hooked
-- once, so with the setting off the hook only hides the cards.

local NUM_FRAMES = 4 -- Blizzard's GroupLootFrame1-4
local CARD_WIDTH = 210
local PAD = 8
local RETRY = 0.5 -- seconds between tries while the item's data loads
local MAX_TRIES = 6
local WAIT_CLICK = 30 -- seconds /tomte gear roll waits for a shift-click on an item
local ROLL_WORDS = { need = "Need", greed = "Greed", pass = "Pass" }
local ROLL_ROLES = { need = "success", greed = "accent", pass = "textMuted" }

local UI = ns.UI

local cards = {} -- [Blizzard's roll frame] = our card

local function Buttons(frame)
	local box = frame.LootButtonContainer
	if not box then
		return nil
	end
	local greed = box.GreedButton
	if greed and not greed:IsShown() and box.TransmogButton and box.TransmogButton:IsShown() then
		greed = box.TransmogButton
	end
	return { need = box.NeedButton, greed = greed, pass = box.PassButton }
end

local function Unlight(frame)
	for _, button in pairs(Buttons(frame) or {}) do
		button:UnlockHighlight()
	end
end

local function Card(frame)
	local card = cards[frame]
	if not card then
		card = CreateFrame("Frame", nil, frame)
		card:SetWidth(CARD_WIDTH)
		card:SetPoint("LEFT", frame, "RIGHT", 4, 0)
		UI.Panel(card, { alpha = 0.95 })
		card.roll = UI.Text(card, 14, "text", "title")
		card.roll:SetPoint("TOPLEFT", PAD, -PAD)
		card.text = UI.Text(card, 11, "text")
		card.text:SetPoint("TOPLEFT", card.roll, "BOTTOMLEFT", 0, -3)
		card.text:SetWidth(CARD_WIDTH - 2 * PAD)
		card.reason = UI.Text(card, 11, "warning")
		card.reason:SetPoint("TOPLEFT", card.text, "BOTTOMLEFT", 0, -2)
		card.reason:SetWidth(CARD_WIDTH - 2 * PAD)
		cards[frame] = card
	end
	return card
end

-- A recipe: "known", "other" (a red "Requires Tailoring (75)": not your profession, or not yet) or "learnable".
local skillPattern
local function RecipeState(link)
	local data = C_TooltipInfo and C_TooltipInfo.GetHyperlink(link)
	skillPattern = skillPattern or (ITEM_MIN_SKILL and ns.Gear_FormatPattern(ITEM_MIN_SKILL))
	local state = "learnable"
	for _, line in ipairs(data and data.lines or {}) do
		local text = line.leftText
		if text and not ns.IsSecret(text) then
			if text == ITEM_SPELL_KNOWN then
				return "known"
			elseif skillPattern and text:find(skillPattern) and ns.GearForever_IsRed(line.leftColor) then
				state = "other"
			end
		end
	end
	return state
end

-- A plain bag: its slots, read from "10 Slot Bag", and your smallest bag (0 with a bag slot empty).
local bagPattern
local function BagInfo(link)
	local data = C_TooltipInfo and C_TooltipInfo.GetHyperlink(link)
	bagPattern = bagPattern or (CONTAINER_SLOTS and ns.Gear_FormatPattern(CONTAINER_SLOTS))
	local slots
	for _, line in ipairs(data and data.lines or {}) do
		local text = line.leftText
		if text and not ns.IsSecret(text) and bagPattern then
			local n = text:match(bagPattern)
			if n then
				slots = tonumber(n)
				break
			end
		end
	end
	if not slots then
		return nil
	end
	local smallest
	for bag = 1, NUM_BAG_SLOTS do
		local n = C_Container.GetContainerNumSlots(bag)
		smallest = (not smallest or n < smallest) and n or smallest
	end
	return { slots = slots, smallest = smallest or 0 }
end

local function Role(unit)
	local role = UnitGroupRolesAssigned and UnitGroupRolesAssigned(unit)
	return role ~= "NONE" and role or nil
end

-- Everyone else in the group, as GearRoll_BuiltFor takes them; nil when you're alone.
local function Members()
	if not IsInGroup() then
		return nil
	end
	local prefix, count = "party", GetNumGroupMembers() - 1
	if IsInRaid() then
		prefix, count = "raid", GetNumGroupMembers()
	end
	local members = {}
	for i = 1, count do
		local unit = prefix .. i
		if UnitExists(unit) and not UnitIsUnit(unit, "player") and UnitIsConnected(unit) then
			local name = UnitName(unit)
			local className, class = UnitClass(unit)
			local level = UnitLevel(unit)
			if name and class and not ns.IsSecret(name) and not ns.IsSecret(level) then
				members[#members + 1] = { name = name, class = class, className = className, level = level,
					role = Role(unit) }
			end
		end
	end
	return members
end

-- The party member a small upgrade should go to instead (RollData.lua), judged at the level you're judged at.
local function BuiltFor(cand, judgeAt)
	local members = cand and Members()
	if not (members and members[1]) then
		return nil
	end
	local _, class = UnitClass("player")
	return ns.GearRoll_BuiltFor(cand, { class = class, level = judgeAt, role = Role("player") }, members)
end

-- What the advice needs about this roll, or nil while the item's data loads. last: the final try, so gear that still
-- has no verdict (one you wear already) is advised on without it.
local function Read(link, count, canNeed, canGreed, last)
	if not link then
		return nil
	end
	local _, _, _, _, minLevel, _, _, _, equipLoc, _, sellPrice, classID, subclassID = C_Item.GetItemInfo(link)
	if not equipLoc then
		C_Item.RequestLoadItemDataByID((C_Item.GetItemInfoInstant(link)))
		return nil
	end
	local info = { canNeed = canNeed, canGreed = canGreed, sell = (sellPrice or 0) * (count or 1) }
	if equipLoc ~= "" and ns.GearForever_Slots(equipLoc, ns.GearForever_RangedSlot()) then
		info.gear = true
		local level = UnitLevel("player")
		local judgeAt = ns.GearRoll_JudgeLevel(level, minLevel)
		if not judgeAt then
			info.needsLevel = minLevel
		else
			local cand
			info.verdict, cand = ns.GearForever_RollVerdict(link, judgeAt)
			if not info.verdict and not last then
				return nil -- loading, or worn already: a retry settles it
			end
			info.ahead = judgeAt > level and judgeAt or nil
			info.builtFor = info.verdict and BuiltFor(cand, judgeAt)
		end
	elseif classID == ns.GEARROLL_CLASS_RECIPE then
		info.recipe = RecipeState(link)
	elseif classID == ns.GEARROLL_CLASS_CONTAINER and subclassID == 0 then
		info.bag = BagInfo(link)
	end
	return info
end

-- The advice's line under need, greed or pass.
local function Words(advice)
	local sell = advice.sell or 0
	if not advice.text then
		return sell > 0 and ("Sells for %s"):format(ns.Price(sell)) or "Nothing you need"
	elseif sell > 0 and advice.roll ~= "need" then
		return ("%s. Sells for %s"):format(advice.text, ns.Price(sell))
	end
	return advice.text
end

local Explain

-- /tomte gear roll with no item waits for the next shift-click on one (bags, links, the character window): typing the
-- command and then shift-clicking needs the chat box open, which is easy to miss.
local waitUntil = 0
local clickHooked = false
local function WaitForClick()
	waitUntil = GetTime() + WAIT_CLICK
	if not clickHooked and HandleModifiedItemClick then
		clickHooked = true
		hooksecurefunc("HandleModifiedItemClick", function(link)
			if GetTime() < waitUntil and IsShiftKeyDown() and type(link) == "string" then
				waitUntil = 0
				Explain(link)
			end
		end)
	end
	ns.Print(("Gear Check: shift-click an item in the next %d seconds."):format(WAIT_CLICK))
end

-- /tomte gear roll [item]: the advice for any item, as if it dropped in a group. Group rolls are hard to come by.
function Explain(link)
	if not (link and link:find("|Hitem:")) then
		WaitForClick()
		return
	end
	if not ns.GearForever_RollAdviceOn() then
		ns.Print("Gear Check: roll advice is off (Gear Check settings).")
		return
	end
	local info = Read(link, 1, true, true, true)
	if not info then
		ns.Print("Gear Check: that item is still loading. Try again.")
		return
	end
	local advice = ns.GearRoll_Advice(info)
	ns.Print(("%s: %s. %s%s"):format(link, ROLL_WORDS[advice.roll], Words(advice),
		advice.reason and (" (" .. advice.reason .. ")") or ""))
end
ns.GearRoll_Explain = Explain

local function Hide(frame)
	if cards[frame] then
		cards[frame]:Hide()
	end
	Unlight(frame)
end

local Show
local function Retry(frame, rollID, tries)
	if tries >= MAX_TRIES then
		return
	end
	C_Timer.After(RETRY, function()
		if frame:IsShown() and frame.rollID == rollID then
			Show(frame, tries + 1)
		end
	end)
end

function Show(frame, tries)
	tries = tries or 0
	Hide(frame)
	if not (ns.GearForever_RollAdviceOn() and frame.rollID and frame:IsShown()) then
		return
	end
	local _, _, count, _, _, canNeed, canGreed = GetLootRollItemInfo(frame.rollID)
	local info = Read(GetLootRollItemLink(frame.rollID), count, canNeed, canGreed, tries >= MAX_TRIES)
	if not info then
		Retry(frame, frame.rollID, tries)
		return
	end
	local advice = ns.GearRoll_Advice(info)
	local card = Card(frame)
	card.roll:SetText(ROLL_WORDS[advice.roll])
	UI.SetTextRole(card.roll, ROLL_ROLES[advice.roll])
	card.text:SetText(Words(advice))
	card.reason:SetText(advice.reason or "")
	card.reason:SetShown(advice.reason ~= nil)
	local height = PAD * 2 + card.roll:GetStringHeight() + 3 + card.text:GetStringHeight()
	if advice.reason then
		height = height + 2 + card.reason:GetStringHeight()
	end
	card:SetHeight(height)
	card:Show()
	local button = (Buttons(frame) or {})[advice.roll]
	if button then
		button:LockHighlight()
	end
end

-- Draw again (the setting or Gear Check turned on or off).
function ns.GearRoll_Refresh()
	for i = 1, NUM_FRAMES do
		local frame = _G["GroupLootFrame" .. i]
		if frame then
			Show(frame)
		end
	end
end

EventUtil.ContinueOnAddOnLoaded("Blizzard_UIPanels_Game", function()
	hooksecurefunc("GroupLootFrame_SetupItemDisplay", function(frame)
		Show(frame)
	end)
	for i = 1, NUM_FRAMES do
		local frame = _G["GroupLootFrame" .. i]
		if frame then
			frame:HookScript("OnHide", Hide)
		end
	end
end)
