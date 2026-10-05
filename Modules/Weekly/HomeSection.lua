local addonName, ns = ...

-- Weekly board on Tomte's Home ("week" slot): the Great Vault as its 3×3 grid (earned slots show their item level,
-- the next one its progress) and what's still open this week for this character, in two columns.

local UI = ns.UI
local GOLD, WHITE, GREY, DIM = UI.GOLD, UI.WHITE, UI.GREY, UI.DIM
local SLOT_W, SLOT_H, SLOT_GAP = 46, 24, 6
local VAULT_W = 96 + 3 * (SLOT_W + SLOT_GAP)
local TODO_H = 22

local function SetColor(fs, c)
	fs:SetTextColor(c[1], c[2], c[3])
end

local function ResetText()
	local seconds = C_DateAndTime.GetSecondsUntilWeeklyReset()
	if not seconds or seconds <= 0 then
		return nil
	end
	local days, hours = math.floor(seconds / 86400), math.floor(seconds % 86400 / 3600)
	if days > 0 then
		return ("resets in %d day%s %d h"):format(days, days == 1 and "" or "s", hours)
	end
	return ("resets in %d h"):format(math.max(hours, 1))
end

local function CreateSlot(parent)
	local slot = CreateFrame("Frame", nil, parent)
	slot:SetSize(SLOT_W, SLOT_H)
	slot.bg = slot:CreateTexture(nil, "BACKGROUND")
	slot.bg:SetAllPoints()
	UI.Border(slot, 1, 1, 1, 0.12)
	slot.text = slot:CreateFontString(nil, "OVERLAY")
	slot.text:SetFont(ns.HomeKit.NARROW_FONT, 13, "")
	slot.text:SetPoint("CENTER")
	return slot
end

local function SetSlot(slot, s, isNext)
	if s and s.progress >= s.threshold then
		slot.bg:SetColorTexture(0.17, 0.14, 0.07, 1)
		UI.SetBorderColor(slot, GOLD[1], GOLD[2], GOLD[3], 0.75)
		slot.text:SetText(s.ilvl and tostring(s.ilvl) or "done")
		SetColor(slot.text, GOLD)
	else
		slot.bg:SetColorTexture(0.09, 0.09, 0.11, 1)
		UI.SetBorderColor(slot, 1, 1, 1, 0.12)
		slot.text:SetText(s and isNext and ("%d/%d"):format(s.progress, s.threshold) or "")
		SetColor(slot.text, GREY)
	end
end

local function Create(frame, Kit)
	frame.heading = Kit.Heading(frame)
	frame.heading:SetPoint("TOPLEFT")
	frame.heading:SetWidth(VAULT_W)
	frame.labels, frame.slots = {}, {}
	for t, track in ipairs(ns.WEEKLY_TRACKS) do
		local y = -(40 + (t - 1) * (SLOT_H + SLOT_GAP))
		local label = UI.Text(frame, 13, GREY)
		label:SetPoint("TOPLEFT", 0, y - 5)
		label:SetText(track.label)
		frame.labels[t] = label
		frame.slots[t] = {}
		for i = 1, 3 do
			local slot = CreateSlot(frame)
			slot:SetPoint("TOPLEFT", 96 + (i - 1) * (SLOT_W + SLOT_GAP), y)
			frame.slots[t][i] = slot
		end
	end

	frame.todoHead = Kit.Heading(frame)
	frame.todoHead:SetPoint("TOPLEFT", VAULT_W + 40, 0)
	frame.todoHead:SetPoint("RIGHT")
	frame.todoHead.title:SetFont(STANDARD_TEXT_FONT, 13, "")
	SetColor(frame.todoHead.title, GREY)
	frame.todo = {}

	frame.note = UI.Text(frame, 13, GREY)
	frame.note:SetPoint("TOPLEFT", 0, -40)
	frame.note:SetPoint("RIGHT")
	frame.note:SetWordWrap(true)
end

local function Refresh(frame)
	local Kit = ns.HomeKit
	frame.heading:Set("This week", ResetText())
	local v = ns.Weekly_CurrentView()
	local hasView = v ~= nil
	frame.note:SetShown(not hasView)
	for t, track in ipairs(ns.WEEKLY_TRACKS) do
		frame.labels[t]:SetShown(hasView)
		local slots = hasView and v.vault and v.vault[track.key] or {}
		local _, nextSlot = ns.Weekly_VaultGoal(slots)
		for i, slot in ipairs(frame.slots[t]) do
			slot:SetShown(hasView)
			SetSlot(slot, slots[i], i == nextSlot)
		end
	end
	frame.todoHead:SetShown(hasView)
	if not hasView then
		-- Below max level: levelling progress instead (the board only follows max-level characters).
		local level, xp, xpMax = UnitLevel("player"), UnitXP("player"), UnitXPMax("player")
		local parts = { ("Level %d"):format(level) }
		if xpMax and xpMax > 0 then
			parts[#parts + 1] = ("%d%% of the way to %d"):format(math.floor(xp / xpMax * 100), level + 1)
			local rested = GetXPExhaustion()
			if rested and rested > 0 then
				parts[#parts + 1] = ("|cff73d973rested %d%%|r"):format(math.min(math.floor(rested / xpMax * 100 + 0.5), 150))
			end
		end
		frame.note:SetText(table.concat(parts, ", ") .. ". |cff9e9e9eThe weekly board starts at max level.|r")
		Kit.HideFrom(frame.todo, 1)
		return 64
	end

	frame.todoHead:Set(("Still open for %s"):format(UnitName("player")), nil, "Open Weekly board", function()
		ns.Panel_OpenPage("weekly")
	end)
	local rows = ns.Weekly_HomeTodo(v, ns.weeklyDB.learned and ns.weeklyDB.quests or {})
	local left = VAULT_W + 40
	local width = frame:GetWidth() - left
	local perCol = math.max(math.floor((frame:GetHeight() - 36) / TODO_H), 1)
	local cols = width >= 520 and 2 or 1
	local colW = (width - (cols - 1) * 28) / cols
	local shown = math.min(#rows, perCol * cols)
	for i = 1, shown do
		local r = rows[i]
		local row = Kit.PoolRow(frame.todo, i, frame)
		row:SetHeight(TODO_H)
		row:Set(nil, r.text, r.done and DIM or WHITE, r.right, r.done and DIM or GREY)
		local col, line = math.floor((i - 1) / perCol), (i - 1) % perCol
		row:ClearAllPoints()
		row:SetPoint("TOPLEFT", left + col * (colW + 28), -(36 + line * TODO_H))
		row:SetWidth(colW)
	end
	Kit.HideFrom(frame.todo, shown + 1)
	if #rows == 0 then
		frame.todoHead:Set(("Nothing tracked yet for %s"):format(UnitName("player")), nil, "Open Weekly board", function()
			ns.Panel_OpenPage("weekly")
		end)
	end
end

ns.WeeklyHomeSection = { kind = "section", slot = "week", key = "weeklysection", Create = Create, Refresh = Refresh }
