local addonName, ns = ...

-- One Great Vault slot box, shared by Home's "This week" and the board: unlocked is gold with its item level, the
-- next slot shows its progress, later ones are empty (or their progress in dim, on the board).

local UI = ns.UI
local GOLD, GREY, DIM = UI.GOLD, UI.GREY, UI.DIM

local function SetColor(fs, c)
	fs:SetTextColor(c[1], c[2], c[3])
end

function ns.WeeklySlot_Create(parent, width, height, fontSize)
	local slot = CreateFrame("Frame", nil, parent)
	slot:SetSize(width, height)
	slot.bg = slot:CreateTexture(nil, "BACKGROUND")
	slot.bg:SetAllPoints()
	UI.Border(slot, 1, 1, 1, 0.12)
	slot.text = slot:CreateFontString(nil, "OVERLAY")
	slot.text:SetFont(ns.HomeKit.NARROW_FONT, fontSize or 13, "")
	slot.text:SetPoint("CENTER")
	return slot
end

-- s = { progress, threshold, ilvl } or nil. showLater: later locked slots show their progress, dimmed.
function ns.WeeklySlot_Set(slot, s, isNext, showLater)
	if s and s.progress >= s.threshold then
		slot.bg:SetColorTexture(0.17, 0.14, 0.07, 1)
		UI.SetBorderColor(slot, GOLD[1], GOLD[2], GOLD[3], 0.75)
		slot.text:SetText(s.ilvl and tostring(s.ilvl) or "done")
		SetColor(slot.text, GOLD)
	else
		slot.bg:SetColorTexture(0.09, 0.09, 0.11, 1)
		UI.SetBorderColor(slot, 1, 1, 1, isNext and 0.3 or 0.12)
		local show = s and (isNext or showLater)
		slot.text:SetText(show and ("%d/%d"):format(s.progress, s.threshold) or "")
		SetColor(slot.text, isNext and GREY or DIM)
	end
end
