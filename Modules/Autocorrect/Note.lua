local addonName, ns = ...

-- Autocorrect: the small note above the chat edit box after a fix ("thinkk > think   Backspace undoes"), or that
-- Autocorrect is paused in combat chat. Shown and hidden by Autocorrect.lua.

local PAD_X, PAD_Y = 8, 4
local GAP = 2 -- between the note and the edit box
local SIZE = 12
local HINT = "Backspace undoes"
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
end

local function Place(editBox, showHint)
	if not note then
		Create()
	end
	note:ClearAllPoints()
	note:SetPoint("BOTTOMLEFT", editBox, "TOPLEFT", 0, GAP)
	note:SetFrameLevel(editBox:GetFrameLevel() + 1)
	note.hint:SetShown(showHint)
	UI.SetTextRole(note.text, "text")
	UI.SetTextRole(note.hint, "textFaint")
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

function ns.AutocorrectNote_Paused(editBox)
	if not note then
		Create()
	end
	note.text:SetText(UI.Wrap(PAUSED, "textMuted"))
	Place(editBox, false)
end

function ns.AutocorrectNote_Hide()
	if note then
		note:Hide()
	end
end
