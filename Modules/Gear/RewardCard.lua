local addonName, ns = ...

-- Gear Check's quest reward pick: when a quest lets you choose a reward, a card names the best choice for you (by
-- Gear Check's verdict) and the one that sells for the most. Display only: it never clicks a reward. It sits above
-- DialogueUI's window when that's open, else where Edit Mode put it. The pick is in Rewards.lua; started and
-- stopped by Gear.lua.

local CARD_W = 300
local PAD = 12
local LABEL_W = 84 -- the "Best for you" / "Most gold" column
local ROW_GAP = 8
local REFRESH_DELAY = 0.2 -- seconds: item data arrives in bursts
local DIALOGUE_GAP = 6 -- between the card and DialogueUI's window under it
-- Quest reward headline colors (Rules.lua's color keys) to theme roles, as on the tooltips.
local COLOR_ROLES = { green = "success", yellow = "warning", grey = "textMuted", red = "danger", orange = "warning" }

local UI = ns.UI
local Pick = ns.GearRewards_Pick

local db
local card
local questOpen = false -- between QUEST_COMPLETE and QUEST_FINISHED
local events = ns.Gear_Events

-- Card -------------------------------------------------------------------------------------------------------------

-- Row i of card f (Dress), made on first need.
local function Row(f, i)
	local row = f.rows[i]
	if row then
		return row
	end
	row = {}
	row.label = UI.Text(f, 11, "textMuted", "label")
	row.label:SetWidth(LABEL_W)
	row.label:SetJustifyH("LEFT")
	row.name = UI.Text(f, 13, "heading")
	row.name:SetPoint("LEFT", row.label, "RIGHT", 4, 0)
	row.name:SetPoint("RIGHT", f, "RIGHT", -PAD, 0)
	row.name:SetJustifyH("LEFT")
	row.name:SetWordWrap(false)
	row.sub = UI.Text(f, 11, "textMuted")
	row.sub:SetPoint("TOPLEFT", row.name, "BOTTOMLEFT", 0, -2)
	row.sub:SetPoint("RIGHT", f, "RIGHT", -PAD, 0)
	row.sub:SetJustifyH("LEFT")
	f.rows[i] = row
	return row
end

-- DialogueUI's quest window while it's shown, else nil.
local function DialogueWindow()
	if not C_AddOns.IsAddOnLoaded("DialogueUI") then
		return nil
	end
	local frame = _G.DUIQuestFrame
	return frame and frame:IsShown() and frame or nil
end

-- Centered above DialogueUI's window when it's open (only read, never changed), else where Edit Mode put it. Edit
-- Mode always uses the saved spot, so a drag isn't undone.
local function Place()
	card:SetScale(UIParent:GetEffectiveScale() / WorldFrame:GetEffectiveScale()) -- so x, y are UIParent units
	card:ClearAllPoints()
	local window = not ns.EditMode_Active() and DialogueWindow()
	if window then
		card:SetPoint("BOTTOM", window, "TOP", 0, DIALOGUE_GAP)
		return
	end
	local p = db.rewardCard
	card:SetPoint(p.point, WorldFrame, p.relPoint, p.x, p.y)
end

-- The card's looks on f: the real card's and the settings preview's (GearRewardCard_DrawSample below).
local function Dress(f)
	f:SetSize(CARD_W, 80)
	UI.Panel(f, { alpha = 0.95 })
	f.title = UI.Text(f, 10, "textMuted", "label")
	f.title:SetPoint("TOPLEFT", PAD, -PAD)
	f.title:SetText(ns.Spaced("Quest reward"))
	f.rows = {}
end

local function Build()
	-- On WorldFrame: DialogueUI and similar addons hide UIParent while you talk to the quest giver.
	card = CreateFrame("Frame", nil, WorldFrame)
	card:SetFrameStrata("HIGH")
	card:SetClampedToScreen(true)
	card:SetMovable(true)
	card:Hide()
	Dress(card)
end

-- rows: list of { label, name, sub } (sub may be nil). Lays them out on card f (Dress) and sizes it.
local function Draw(f, rows)
	local y = PAD + f.title:GetStringHeight() + ROW_GAP
	for i, r in ipairs(rows) do
		local row = Row(f, i)
		row.label:ClearAllPoints()
		row.label:SetPoint("TOPLEFT", PAD, -y - 2)
		row.label:SetText(r.label)
		row.name:ClearAllPoints()
		row.name:SetPoint("TOPLEFT", PAD + LABEL_W + 4, -y)
		row.name:SetPoint("RIGHT", f, "RIGHT", -PAD, 0)
		row.name:SetText(r.name)
		row.sub:SetText(r.sub or "")
		row.sub:SetShown(r.sub ~= nil)
		row.label:Show()
		row.name:Show()
		y = y + row.name:GetStringHeight()
		if r.sub then
			y = y + 2 + row.sub:GetStringHeight()
		end
		y = y + ROW_GAP
	end
	for i = #rows + 1, #f.rows do
		local row = f.rows[i]
		row.label:Hide()
		row.name:Hide()
		row.sub:Hide()
	end
	f:SetHeight(y - ROW_GAP + PAD)
end

-- Rows ---------------------------------------------------------------------------------------------------------------

local function ItemName(c)
	if not c.name then
		return UI.Wrap(RETRIEVING_ITEM_INFO, "textMuted")
	end
	local color = c.quality and ITEM_QUALITY_COLORS[c.quality]
	return color and UI.Wrap(c.name, color) or c.name
end

local function Price(c)
	return UI.Wrap(ns.Price(c.sell), "text")
end

-- The quest's reward choices: { name, quality, sell, verdict }. judged: whether Gear Check could judge them (on, with
-- a spec). Nil while there's no choice to make.
local function Choices()
	local n = GetNumQuestChoices()
	if not n or n < 2 then
		return nil
	end
	local ctx = ns.Gear_Context()
	local choices = {}
	for i = 1, n do
		local c = {}
		local link = GetQuestItemLink("choice", i)
		if link and not ns.IsSecret(link) then
			local name, _, quality, _, _, _, _, _, _, _, sell = C_Item.GetItemInfo(link)
			c.name, c.quality, c.sell = name, quality, sell
			c.verdict = ctx and ns.Gear_Verdict(link, ctx)
			local equipLoc = select(4, C_Item.GetItemInfoInstant(link))
			c.gear = equipLoc ~= nil and equipLoc ~= "" and equipLoc ~= "INVTYPE_NON_EQUIP_IGNORE"
		end
		choices[i] = c
	end
	return choices, ctx ~= nil
end

local function Rows(choices, judged)
	local best, _, gold = Pick(choices)
	local rows = {}
	if judged then
		if best then
			local c = choices[best]
			local headline, color = ns.Gear_Headline(c.verdict)
			local sub = UI.Wrap(headline, COLOR_ROLES[color] or "textMuted")
			if gold == best then
				sub = sub .. UI.Wrap("  ·  sells for ", "textMuted") .. Price(c)
			end
			rows[#rows + 1] = { label = gold == best and "Best, most gold" or "Best for you", name = ItemName(c),
				sub = sub }
		else
			rows[#rows + 1] = { label = "Best for you", name = UI.Wrap("No upgrade here", "textMuted") }
		end
	end
	if gold and gold ~= best then
		local c = choices[gold]
		rows[#rows + 1] = { label = "Most gold", name = ItemName(c), sub = UI.Wrap("Sells for ", "textMuted") .. Price(c) }
	end
	return rows
end

-- The open quest's reward choice Gear Check calls a clean upgrade, or nil (Gear Check off, no spec, nothing sure).
-- Quests' "Pick the reward for me" takes it. Nil until every choice is read (its name, and a verdict for gear): a
-- still-loading choice could be the bigger upgrade, and a picked reward can't be undone.
function ns.GearRewards_BestChoice()
	if not ns.gearModule.active then
		return nil
	end
	local choices, judged = Choices()
	if not (choices and judged) then
		return nil
	end
	for _, c in ipairs(choices) do
		if not c.name or (c.gear and not c.verdict) then
			return nil
		end
	end
	local best, sure = Pick(choices)
	return sure and best or nil
end

-- What Edit Mode shows while no quest is open.
local function PreviewRows()
	return {
		{ label = "Best for you", name = UI.Wrap("A reward for you", "heading"),
			sub = UI.Wrap("Upgrade +4.2%: equip it", "success") },
		{ label = "Most gold", name = UI.Wrap("Another reward", "heading"),
			sub = UI.Wrap("Sells for ", "textMuted") .. UI.Wrap(ns.Price(125000), "text") },
	}
end

local function Refresh()
	local on = db and db.rewardPick and ns.gearModule.active
	local rows
	if on and questOpen then
		local choices, judged = Choices()
		if choices then
			rows = Rows(choices, judged)
		end
	end
	if on and (not rows or #rows == 0) and ns.EditMode_Active() then
		rows = PreviewRows()
	end
	if not rows or #rows == 0 then
		if card then
			card:Hide()
		end
		return
	end
	if not card then
		Build()
	end
	if not (card:IsShown() and ns.EditMode_Active()) then
		Place()
	end
	Draw(card, rows)
	card:Show()
end
ns.GearRewardCard_Refresh = Refresh

-- The settings preview (Panel/Preview.lua): the card with Edit Mode's sample rows, drawn by Dress and Draw.
function ns.GearRewardCard_DrawSample(host)
	local f = host.card
	if not f then
		f = CreateFrame("Frame", nil, host)
		f:SetPoint("TOPLEFT")
		Dress(f)
		host.card = f
	end
	Draw(f, PreviewRows())
	return CARD_W, f:GetHeight()
end

local refreshSoon = UI.Debounce(REFRESH_DELAY, Refresh)

-- Events -------------------------------------------------------------------------------------------------------------

events:On("rewards", "QUEST_COMPLETE", function()
	questOpen = true
	events:Watch("rewards", "QUEST_ITEM_UPDATE")
	events:Watch("rewards", "GET_ITEM_INFO_RECEIVED")
	Refresh()
	-- DialogueUI may open its window after this handler (same event): place the card again once it has.
	C_Timer.After(0, Refresh)
end)

events:On("rewards", "QUEST_FINISHED", function()
	questOpen = false
	events:Unwatch("rewards", "QUEST_ITEM_UPDATE")
	events:Unwatch("rewards", "GET_ITEM_INFO_RECEIVED")
	Refresh()
end)

events:On("rewards", "QUEST_ITEM_UPDATE", refreshSoon)
events:On("rewards", "GET_ITEM_INFO_RECEIVED", refreshSoon)

ns.EditMode_Register({
	name = "Quest reward pick",
	frame = function()
		return card
	end,
	refresh = Refresh,
	saved = function()
		local point, _, relPoint, x, y = card:GetPoint()
		local p = db.rewardCard
		p.point, p.relPoint, p.x, p.y = point, relPoint, x, y
	end,
	module = "gear",
	-- The same position as the rewardCard default in Gear.lua.
	reset = function()
		local p = db.rewardCard
		p.point, p.relPoint, p.x, p.y = "TOP", "TOP", 0, -120
		if card then
			Place()
		end
	end,
})

function ns.GearRewardCard_Start(moduleDB)
	db = moduleDB
	events:Watch("rewards", "QUEST_COMPLETE")
	events:Watch("rewards", "QUEST_FINISHED")
end

function ns.GearRewardCard_Stop()
	events:UnwatchAll("rewards")
	questOpen = false
	Refresh()
end
