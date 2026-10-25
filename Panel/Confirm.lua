local addonName, ns = ...

-- A yes/no question in the theme ("Reset Alts to its defaults?", "Clear the Recent list?"), instead of Blizzard's
-- popup. One shared dialog; a new question replaces an open one. Esc or No closes it, Enter or Yes accepts. Text
-- after a blank line ("Forget X?\n\nTomte drops ...") is the detail, smaller and muted under the question.

local UI = ns.UI
local WIDTH = 400
local PAD = 18
local BUTTONS_H = 44 -- the button row and the space under it
local DETAIL_GAP = 8

local dialog

local function Close()
	if dialog and dialog:IsShown() then
		dialog:Hide()
	end
end

local function Accept()
	local onAccept = dialog.onAccept
	Close()
	if onAccept then
		onAccept() -- a click or a key press: a hardware event, as C_UI.Reload needs
	end
end

local function Build()
	-- Out of combat Esc and Enter are handled below; in combat (no keyboard) Esc closes it through UI.CloseOnEscape,
	-- before the Tomte window under it.
	dialog = UI.Dialog("TomteConfirm", WIDTH, nil, { y = 160 })
	-- Fixed widths (not anchored to the dialog's sides), so the wrapped height is known right after SetText.
	dialog.text = UI.Text(dialog, 14, "heading", "title")
	dialog.text:SetPoint("TOPLEFT", PAD, -PAD)
	dialog.text:SetWidth(WIDTH - 2 * PAD)
	dialog.text:SetWordWrap(true)
	dialog.text:SetJustifyH("LEFT")
	dialog.detail = UI.Text(dialog, 12, "textMuted")
	dialog.detail:SetPoint("TOPLEFT", dialog.text, "BOTTOMLEFT", 0, -DETAIL_GAP)
	dialog.detail:SetWidth(WIDTH - 2 * PAD)
	dialog.detail:SetWordWrap(true)
	dialog.detail:SetJustifyH("LEFT")
	dialog.no = UI.Button(dialog, 80, "No")
	dialog.no:SetHeight(22)
	dialog.no:SetPoint("BOTTOMRIGHT", -PAD, 14)
	dialog.no:SetScript("OnClick", function()
		UI.Sound("off")
		Close()
	end)
	dialog.yes = UI.Button(dialog, 80, "Yes")
	dialog.yes:SetHeight(22)
	dialog.yes:SetPoint("RIGHT", dialog.no, "LEFT", -8, 0)
	dialog.yes:SetScript("OnClick", function()
		UI.Sound("confirm")
		Accept()
	end)
	-- Keys: Esc = No, Enter = Yes (unless the question popped up on its own: opts.noEnter), everything else goes on
	-- to the game. Keyboard input can't be claimed in combat, so there the buttons are the only way.
	dialog:SetScript("OnKeyDown", function(self, key)
		if InCombatLockdown() then
			return
		end
		if key == "ENTER" and self.noEnter then
			self:SetPropagateKeyboardInput(true)
			return
		end
		local mine = key == "ESCAPE" or key == "ENTER"
		self:SetPropagateKeyboardInput(not mine)
		if key == "ESCAPE" then
			Close()
		elseif key == "ENTER" then
			Accept()
		end
	end)
end

-- text: the question; onAccept() runs on Yes. opts.yes / opts.no: other button labels. opts.noEnter: Enter isn't Yes
-- (a question that comes up without a click, where Enter may be meant for the chat box).
function ns.Confirm_Show(text, onAccept, opts)
	if not dialog then
		Build()
	end
	opts = opts or {}
	dialog.noEnter = opts.noEnter
	UI.PlaceDialog(dialog) -- WorldFrame while a dialogue addon hides UIParent (Waypoints asks at guards)
	dialog.onAccept = onAccept
	local question, detail = text:match("^(.-)\n\n(.+)$")
	dialog.text:SetText(question or text)
	dialog.detail:SetText(detail or "")
	dialog.detail:SetShown(detail ~= nil)
	dialog.yes.label:SetText(opts.yes or YES)
	dialog.no.label:SetText(opts.no or NO)
	UI.FitButton(dialog.yes, 80, 24)
	UI.FitButton(dialog.no, 80, 24)
	local textH = dialog.text:GetStringHeight() + (detail and DETAIL_GAP + dialog.detail:GetStringHeight() or 0)
	dialog:SetHeight(PAD + textH + 16 + BUTTONS_H)
	if not dialog:IsShown() then
		dialog:Show()
		UI.Appear(dialog)
	end
	dialog:Raise()
	if not InCombatLockdown() then
		dialog:EnableKeyboard(true)
		dialog:SetPropagateKeyboardInput(true)
	else
		dialog:EnableKeyboard(false)
	end
end
