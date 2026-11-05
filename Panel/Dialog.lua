local addonName, ns = ...

-- One text dialog for copying and pasting: guide links and team scripts (Pet Battles), bug reports, settings
-- strings. Read-only text comes selected for Ctrl+C, which also closes the dialog; editable text gets a Save (or
-- spec.saveText) button whose onSave may return an error to show instead of closing.

local UI = ns.UI
local popup

-- Scrolls to the newest text a frame after SetText: the edit box knows its height only once it laid the text out.
local function ScrollToEnd()
	C_Timer.After(0, function()
		if popup:IsShown() then
			popup.scroll:SetScroll(math.huge)
		end
	end)
end

local function Build()
	-- Parent and scale are set on every show (ns.Dialog_Show).
	popup = UI.Dialog("TomteDialog", 460, 150, { y = 120 }) -- Escape closes it
	popup.title = UI.Text(popup, 14, "heading", "title")
	popup.title:SetPoint("TOPLEFT", 14, -12)
	popup.hint = UI.Text(popup, 11, "textMuted")
	popup.hint:SetPoint("TOPLEFT", popup.title, "BOTTOMLEFT", 0, -4)
	popup.hint:SetPoint("RIGHT", -14, 0)
	popup.hint:SetJustifyH("LEFT")

	local box = CreateFrame("Frame", nil, popup)
	box:SetPoint("TOPLEFT", popup.hint, "BOTTOMLEFT", 0, -8) -- below the hint, however many lines it wraps to
	box:SetPoint("BOTTOMRIGHT", -14, 40)
	UI.Surface(box)
	popup.scroll = UI.Scroll(box)
	popup.scroll:SetPoint("TOPLEFT", 6, -6)
	popup.scroll:SetPoint("BOTTOMRIGHT", -10, 6)
	local edit = CreateFrame("EditBox", nil, popup.scroll.content)
	edit:SetMultiLine(true)
	edit:SetAutoFocus(false)
	edit:SetPoint("TOPLEFT")
	edit:SetPoint("RIGHT")
	UI.SetFont(edit, "number", 12)
	edit:SetTextColor(UI.Color("text"))
	edit:SetScript("OnEscapePressed", function()
		popup:Hide()
	end)
	-- Ctrl+C on read-only text copies it and closes the dialog (like SimulationCraft's). Closed a frame later, so the
	-- copy happens first.
	edit:SetScript("OnKeyDown", function(_, key)
		if key == "C" and IsControlKeyDown() and popup.spec.readOnly then
			C_Timer.After(0, function()
				popup:Hide()
			end)
		end
	end)
	edit:SetScript("OnTextChanged", function(self, userInput)
		if userInput and popup.spec.readOnly then
			self:SetText(popup.spec.text)
			self:HighlightText()
		end
		popup.scroll:SetContentHeight(self:GetHeight())
	end)
	edit:SetScript("OnCursorChanged", function(self, _, y, _, h)
		local scroll = popup.scroll
		local top = -y
		if top < scroll:GetVerticalScroll() then
			scroll:SetScroll(top)
		elseif top + h > scroll:GetVerticalScroll() + scroll:GetHeight() then
			scroll:SetScroll(top + h - scroll:GetHeight())
		end
	end)
	popup.scroll.onWidthChanged = function(width)
		edit:SetWidth(width)
	end
	box:EnableMouse(true)
	box:SetScript("OnMouseDown", function()
		edit:SetFocus()
	end)
	popup.edit = edit

	popup.error = UI.Text(popup, 11, "danger")
	popup.error:SetPoint("BOTTOMLEFT", 14, 14)
	popup.error:SetWordWrap(false)
	popup.close = UI.Button(popup, 80, "Close")
	popup.close:SetPoint("BOTTOMRIGHT", -14, 10)
	popup.close:SetScript("OnClick", function()
		popup:Hide()
	end)
	popup.save = UI.Button(popup, 80, "Save")
	popup.save:SetPoint("RIGHT", popup.close, "LEFT", -8, 0)
	popup.save:SetScript("OnClick", function()
		local err = popup.spec.onSave and popup.spec.onSave(popup.edit:GetText())
		if err then
			popup.error:SetText(err)
			UI.Shake(popup) -- refused: the text can't be saved as it is
		else
			popup:Hide()
		end
	end)
	popup.error:SetPoint("RIGHT", popup.save, "LEFT", -8, 0)

	-- Optional checkbox bottom left (spec.check) that changes the text, e.g. Chat Copy's "Clean lines".
	popup.check = UI.Checkbox(popup)
	popup.check:SetPoint("BOTTOMLEFT", 16, 13)
	popup.check.label = UI.Text(popup, 12, "text")
	popup.check.label:SetPoint("LEFT", popup.check, "RIGHT", 8, 0)
	popup.check.onChange = function(checked)
		local spec = popup.spec
		spec.text = spec.check.onChange(checked) or ""
		popup.edit:SetText(spec.text)
		popup.edit:SetFocus()
		popup.edit:HighlightText()
		if spec.atEnd then
			ScrollToEnd()
		end
	end
end

-- spec = { title, hint, text, readOnly, height, width, saveText = "Save", onSave(text) -> error text | nil,
--   atEnd (start scrolled to the end), check = { label, checked, onChange(checked) -> new text } }
function ns.Dialog_Show(spec)
	if not popup then
		Build()
	end
	popup.spec = spec
	UI.PlaceDialog(popup) -- WorldFrame while a dialogue addon hides UIParent, so it opens from the tamer card too
	popup.title:SetText(spec.title or "")
	popup.hint:SetText(spec.hint or "")
	popup.error:SetText("")
	popup:SetSize(spec.width or 460, spec.height or (spec.readOnly and 150 or 320))
	popup.save:SetShown(not spec.readOnly)
	popup.save.label:SetText(spec.saveText or "Save")
	UI.FitButton(popup.save, 80, 24)
	popup.check:SetShown(spec.check ~= nil)
	popup.check.label:SetShown(spec.check ~= nil)
	if spec.check then
		popup.check:SetChecked(spec.check.checked)
		popup.check.label:SetText(spec.check.label)
	end
	popup.edit:SetText(spec.text or "")
	popup.scroll:SetScroll(0)
	if not popup:IsShown() then
		popup:Show()
		UI.Appear(popup)
	end
	popup.edit:SetFocus()
	if spec.readOnly then
		popup.edit:HighlightText()
	else
		popup.edit:SetCursorPosition(0)
	end
	if spec.atEnd then
		ScrollToEnd()
	end
end
