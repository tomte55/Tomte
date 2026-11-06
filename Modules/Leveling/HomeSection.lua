local addonName, ns = ...

-- Leveling (World of Warcraft: Forever only) on Tomte's Home, in the "week" slot Forever has no Weekly board for: the XP
-- block on the left, what's waiting on the right. Hidden at the level cap. Registered in Leveling.lua.

local HEAD_H = 36
local XP_W = 260
local COL_GAP = 40
local ROW_COL_GAP = 28
local TWO_COLS_W = 520 -- the room beside the XP block from which the rows split into two columns

local UI = ns.UI

local function OpenPage()
	ns.Panel_OpenPage(ns.LEVELING_PAGE_KEY)
end

local function Create(frame, Kit)
	frame.heading = Kit.Heading(frame)
	frame.heading:SetPoint("TOPLEFT")
	frame.heading:SetPoint("TOPRIGHT")
	frame.xp = ns.LevelingXP_Create(frame, true)
	frame.xp:SetPoint("TOPLEFT", 0, -HEAD_H)
	frame.xp:SetWidth(XP_W)
	frame.rows = {}
	frame.none = UI.Text(frame, 13, "textMuted")
	frame.none:SetPoint("TOPLEFT", XP_W + COL_GAP, -(HEAD_H + 6))
	frame.none:SetPoint("RIGHT")
	frame.none:SetJustifyH("LEFT")
	frame.none:SetWordWrap(true)
end

-- Returns the height it wants.
local function Refresh(frame)
	local Kit = ns.HomeKit
	local state = ns.LevelingRead_State()
	local todo = state.todo
	frame.heading:Set("Leveling", #todo > 0 and (#todo == 1 and "1 thing waiting" or ("%d things waiting"):format(#todo)) or nil,
		"Open Leveling", OpenPage)
	local xpH = frame.xp:Set(state)

	local left = XP_W + COL_GAP
	local width = frame:GetWidth() - left
	local cols = width >= TWO_COLS_W and 2 or 1
	local colW = (width - (cols - 1) * ROW_COL_GAP) / cols
	local perCol = math.max(math.floor((frame:GetHeight() - HEAD_H) / Kit.ROW2_H), 1)
	local shown = math.min(#todo, perCol * cols)
	for i = 1, shown do
		local item = todo[i]
		local row = Kit.PoolRow(frame.rows, i, frame)
		row:Set(item.icon, item.text, item.role, ns.Leveling_TodoRight(item), item.xp and "success" or nil, item.sub or "")
		row.onClick = OpenPage
		row:ClearAllPoints()
		row:SetPoint("TOPLEFT", left + math.floor((i - 1) / perCol) * (colW + ROW_COL_GAP), -(HEAD_H + (i - 1) % perCol * Kit.ROW2_H))
		row:SetWidth(colW)
	end
	Kit.HideFrom(frame.rows, shown + 1)

	frame.none:SetShown(#todo == 0)
	if #todo == 0 then
		local nextUp = state.nextLevel and (" Next at your trainer: level %d."):format(state.nextLevel) or ""
		frame.none:SetText("Nothing waiting." .. nextUp)
	end
	local rowsH = math.min(math.ceil(shown / cols), perCol) * Kit.ROW2_H
	return HEAD_H + math.max(xpH, rowsH, 18)
end

ns.LevelingHomeSection = {
	kind = "section", slot = "week", key = "levelingsection", Create = Create, Refresh = Refresh,
	shown = function()
		return ns.Leveling_DB().home and UnitLevel("player") < GameRulesUtil.GetEffectiveMaxLevelForPlayer()
	end,
}
