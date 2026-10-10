local addonName, ns = ...

-- One Great Vault slot box, shared by Home's "This week" and the board: unlocked is in the accent with its item
-- level, the next slot shows its progress, later ones are empty (or their progress, faint, on the board).

local UI = ns.UI

function ns.WeeklySlot_Create(parent, width, height, fontSize)
	local slot = CreateFrame("Frame", nil, parent)
	slot:SetSize(width, height)
	slot.bg = slot:CreateTexture(nil, "BACKGROUND")
	slot.bg:SetAllPoints()
	UI.Border(slot, "rule")
	slot.text = slot:CreateFontString(nil, "OVERLAY")
	UI.SetFont(slot.text, "number", fontSize or 13)
	slot.text:SetPoint("CENTER")
	return slot
end

-- s = { progress, threshold, ilvl } or nil. showLater: later locked slots show their progress, dimmed.
function ns.WeeklySlot_Set(slot, s, isNext, showLater)
	if s and s.progress >= s.threshold then
		slot.bg:SetColorTexture(UI.RGBA("accentDeep", 0.35))
		UI.SetBorderColor(slot, "accent", 0.75)
		slot.text:SetText(s.ilvl and tostring(s.ilvl) or "done")
		UI.SetTextRole(slot.text, "accent")
	else
		slot.bg:SetColorTexture(UI.Color("surface"))
		-- The next slot gets the frame's rule, later ones the faint row rule.
		if isNext then
			UI.SetBorderColor(slot, "frame", 0.3)
		else
			UI.SetBorderColor(slot, "rule")
		end
		local show = s and (isNext or showLater)
		slot.text:SetText(show and ("%d/%d"):format(s.progress, s.threshold) or "")
		UI.SetTextRole(slot.text, isNext and "textMuted" or "textFaint")

	end
end
