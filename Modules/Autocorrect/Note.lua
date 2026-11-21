local addonName, ns = ...

-- Autocorrect: the small note above the chat edit box after a fix ("thinkk > think   Backspace undoes"), after an
-- undo (the offer to never make that fix again, the only part that takes a click), or that Autocorrect is paused in
-- combat chat. Shown and hidden by Autocorrect.lua.

local PAD_X, PAD_Y = 8, 4
local GAP = 2 -- between the note and the edit box
local SIZE = 12
local HINT = "Backspace undoes"
local KEPT_HINT = "Click to never fix it"
local PAUSED = "Autocorrect paused in combat chat"

local UI = ns.UI

local note

local function Create()
	note = CreateFrame("Frame", nil, UIParent)
	note:SetFrameStrata("DIALOG")
	note:Hide()
	UI.Panel(note, { subtle = true, alpha = 0.9 })
	note.text = UI.Text(note, SIZE, "text", "body")
	note.text:SetPoint("LEFT", PAD_X, 0)
	note.hint = UI.Text(note, SIZE, "textFaint", "body")
	note.hint:SetPoint("LEFT", note.text, "RIGHT", 10, 0)
	-- Mouse down, not up: a click may move the chat box's focus, and the offer ends with the line.
	note:SetScript("OnMouseDown", function()
		local onClick = note.onClick
		if onClick then
			note.onClick = nil
			onClick()
		end
	end)
end

-- onClick: only the after-undo offer takes clicks; the other notes let them through to whatever is under them.
local function Place(editBox, showHint, onClick)
	if not note then
		Create()
	end
	note.onClick = onClick
	note:EnableMouse(onClick ~= nil)
	note:ClearAllPoints()
	note:SetPoint("BOTTOMLEFT", editBox, "TOPLEFT", 0, GAP)
	note:SetFrameLevel(editBox:GetFrameLevel() + 1)
	note.hint:SetShown(showHint)
	UI.SetTextRole(note.text, "text")
	UI.SetTextRole(note.hint, onClick and "accent" or "textFaint")
	local width = note.text:GetStringWidth() + (showHint and (10 + note.hint:GetStringWidth()) or 0)
	note:SetSize(math.ceil(width) + 2 * PAD_X, math.ceil(note.text:GetStringHeight()) + 2 * PAD_Y)
	note:Show()
end

-- The fix just made: the word as typed, an arrow, the fix, and the undo hint.
function ns.AutocorrectNote_Show(editBox, typed, fix)
	if not note then
		Create()
	end
	note.text:SetText(UI.Wrap(typed, "textMuted") .. "  >  " .. UI.Wrap(fix, "success"))
	note.hint:SetText(HINT)
	Place(editBox, true)
end

-- After Backspace put the typed word back: "teh kept   Click to never fix it". onClick runs once, on that click.
function ns.AutocorrectNote_Kept(editBox, typed, onClick)
	if not note then
		Create()
	end
	note.text:SetText(UI.Wrap(typed, "text") .. UI.Wrap(" kept", "textMuted"))
	note.hint:SetText(KEPT_HINT)
	Place(editBox, true, onClick)
end

function ns.AutocorrectNote_Paused(editBox)
	if not note then
		Create()
	end
	note.text:SetText(UI.Wrap(PAUSED, "textMuted"))
	Place(editBox, false)
end

function ns.AutocorrectNote_Hide()
	if note then
		note.onClick = nil
		note:EnableMouse(false)
		note:Hide()
	end
end
