local addonName, ns = ...

-- More ns.UI controls: an on/off switch, segmented buttons, a resize grip, a progress line and Esc handling for
-- Tomte's windows. The rest of the widget kit is in Widgets.lua; menus and the list a UI.Dropdown opens are in
-- Menu.lua.

local UI = ns.UI
local SWITCH_W, SWITCH_H = 34, 16
local KNOB_W = 9
local KNOB_INSET = 3 -- on all four sides, so the knob is 10 tall
local SLIDE_SECONDS = 0.15
UI.SWITCH_SECONDS = SLIDE_SECONDS -- Options.lua waits this long before re-laying rows after a switch
local SEGMENT_PAD = 10 -- text inset on each side of a segment
local SEGMENT_H = 20
local PROGRESS_POLL = 0.25 -- seconds between reads of a progress line's read()
local PROGRESS_EASE = 6 -- how fast a progress line catches up with the read value (per second)
local BUSY_SECONDS = 1.6 -- one sweep of a busy line's segment
local BUSY_SPAN = 0.25 -- the busy segment's share of the line's width

-- Switch: same API as UI.Checkbox (SetChecked, .checked, .onChange, Enable/Disable dims it). Square, like the rest
-- of the kit: a knob slides across and the accent gradient (as in UI.Bar) fills the track behind it. Only a click
-- animates; SetChecked from code (a page being built) shows the state at once.
function UI.Switch(parent)
	local b = CreateFrame("Button", nil, parent)
	-- Everything is measured in whole screen pixels and drawn unsnapped, like UI.Border's edges: in UI units below a
	-- UI scale of 1, pixel-grid snapping rounded each knob edge on its own, so knobs came out a pixel off-center or a
	-- pixel bigger depending on where each switch sat on screen.
	local scale = b:GetEffectiveScale()
	local pixel = PixelUtil.GetPixelToUIUnitFactor() / scale
	local width = PixelUtil.GetNearestPixelSize(SWITCH_W, scale)
	local inset = PixelUtil.GetNearestPixelSize(KNOB_INSET, scale, 3) -- at least the border plus a 2-pixel gap
	local knobW = PixelUtil.GetNearestPixelSize(KNOB_W, scale)
	local travel = width - knobW - 2 * inset
	b:SetSize(width, PixelUtil.GetNearestPixelSize(SWITCH_H, scale))
	b:SetHitRectInsets(-4, -4, -4, -4)
	local function Unsnapped(t)
		t:SetTexelSnappingBias(0)
		t:SetSnapToPixelGrid(false)
		return t
	end
	b.track = Unsnapped(b:CreateTexture(nil, "BACKGROUND"))
	b.track:SetAllPoints()
	b.track:SetColorTexture(0, 0, 0, 0.3)
	-- Under the border (UI.Border draws on BORDER) and 1 px inside it, so the outline shows all round when on.
	b.fill = Unsnapped(b:CreateTexture(nil, "BACKGROUND", nil, 1))
	b.fill:SetPoint("TOPLEFT", pixel, -pixel)
	b.fill:SetPoint("BOTTOMLEFT", pixel, pixel)
	b.fill:SetColorTexture(1, 1, 1, 1)
	b.fill:SetGradient("HORIZONTAL", UI.ColorObject("accentDeep"), UI.ColorObject("accent"))
	b.fill:SetAlpha(0.85)
	UI.Border(b, "frame", 0.6)
	-- Same inset on all four sides; its height follows the track.
	b.knob = Unsnapped(b:CreateTexture(nil, "ARTWORK"))
	b.knob:SetWidth(knobW)
	local offR, offG, offB = UI.Color("textMuted")
	local onR, onG, onB = UI.Color("text")

	-- p: 0 = off, 1 = on, in between while sliding.
	local function Show(self, p)
		self.progress = p
		local eased = ns.Smoothstep(p)
		self.fill:SetWidth(math.max((width - 2 * pixel) * eased, 0.001))
		self.fill:SetShown(eased > 0)
		local x = inset + travel * eased
		self.knob:SetPoint("TOPLEFT", x, -inset)
		self.knob:SetPoint("BOTTOMLEFT", x, inset)
		self.knob:SetColorTexture(offR + (onR - offR) * eased, offG + (onG - offG) * eased, offB + (onB - offB) * eased)
	end

	local function Slide(self, elapsed)
		local target = self.checked and 1 or 0
		local step = elapsed / SLIDE_SECONDS
		local p = target > self.progress and math.min(self.progress + step, 1) or math.max(self.progress - step, 0)
		Show(self, p)
		if p == target then
			self:SetScript("OnUpdate", nil)
		end
	end

	function b:SetChecked(on)
		on = on and true or false
		if on == self.checked and self:GetScript("OnUpdate") then
			return -- a page refresh during the click's slide: let it finish
		end
		self.checked = on
		self:SetScript("OnUpdate", nil)
		Show(self, self.checked and 1 or 0)
	end
	b:SetScript("OnHide", function(self)
		-- A slide cut short ends where it was going.
		self:SetScript("OnUpdate", nil)
		Show(self, self.checked and 1 or 0)
	end)
	b:SetScript("OnClick", function(self)
		self.checked = not self.checked
		self:SetScript("OnUpdate", Slide)
		PlaySound(self.checked and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF)
		if self.onChange then
			self.onChange(self.checked)
		end
	end)
	b:SetScript("OnEnter", function(self)
		UI.SetBorderColor(self, "accent", 1)
	end)
	b:SetScript("OnLeave", function(self)
		UI.SetBorderColor(self, "frame", 0.6)
	end)
	b:SetScript("OnEnable", function(self)
		self:SetAlpha(1)
	end)
	b:SetScript("OnDisable", function(self)
		self:SetAlpha(0.35)
	end)
	b:SetChecked(false)
	return b
end

-- Segmented buttons: one segment per choice, the current one lit. Set getValue, setValue and choices like
-- UI.Dropdown, then call Refresh (lays the segments out and sizes the frame to them). For toggles that can each be
-- on (several at once), set isOn(value) -> bool and toggle(value) instead of getValue and setValue. Optional
-- onEnter(value, text) and onLeave() follow the mouse over the segments.
function UI.Segmented(parent)
	local f = CreateFrame("Frame", nil, parent)
	f:SetHeight(SEGMENT_H)
	UI.Border(f, "frame", 0.5)
	f.segments = {}
	f.measure = UI.Text(f, 12, "text")
	f.measure:Hide()

	local function Selected(value)
		if f.isOn then
			return f.isOn(value) == true
		end
		return f.getValue() == value
	end

	local function Paint(seg, selected)
		seg.bg:SetShown(selected or seg:IsMouseOver())
		seg.line:SetShown(selected)
		UI.SetTextRole(seg.label, selected and "text" or "textMuted")
	end

	local function Segment(i)
		local seg = f.segments[i]
		if seg then
			return seg
		end
		seg = CreateFrame("Button", nil, f)
		seg:SetHeight(SEGMENT_H)
		seg.bg = seg:CreateTexture(nil, "BACKGROUND")
		seg.bg:SetAllPoints()
		seg.bg:SetColorTexture(UI.Color("hover"))
		seg.line = seg:CreateTexture(nil, "ARTWORK")
		seg.line:SetColorTexture(UI.Color("accent"))
		seg.line:SetPoint("BOTTOMLEFT")
		seg.line:SetPoint("BOTTOMRIGHT")
		seg.line:SetHeight(2)
		seg.rule = seg:CreateTexture(nil, "ARTWORK")
		seg.rule:SetColorTexture(UI.Color("frame"))
		seg.rule:SetAlpha(0.5)
		seg.rule:SetPoint("TOPLEFT")
		seg.rule:SetPoint("BOTTOMLEFT")
		seg.rule:SetWidth(1)
		seg.label = UI.Text(seg, 12, "textMuted")
		seg.label:SetPoint("CENTER", 0, 0)
		seg:SetScript("OnEnter", function(self)
			Paint(self, Selected(self.value))
			if f.onEnter then
				f.onEnter(self.value, self.label:GetText())
			end
		end)
		seg:SetScript("OnLeave", function(self)
			self.bg:SetShown(Selected(self.value))
			if f.onLeave then
				f.onLeave()
			end
		end)
		seg:SetScript("OnClick", function(self)
			if f.toggle then
				f.toggle(self.value)
				PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
				f:Refresh()
			elseif f.getValue() ~= self.value then
				PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
				f.setValue(self.value)
				f:Refresh()
			end
		end)
		f.segments[i] = seg
		return seg
	end

	-- Width of each choice's segment (label + padding), for ns.PanelLayout_UseSegments.
	function f:Widths(choices)
		local widths = {}
		for i, choice in ipairs(choices) do
			self.measure:SetText(choice.text)
			widths[i] = math.ceil(self.measure:GetUnboundedStringWidth()) + 2 * SEGMENT_PAD
		end
		return widths
	end

	function f:Refresh()
		local choices = self.choices()
		local x = 0
		for i, choice in ipairs(choices) do
			local seg = Segment(i)
			seg.value = choice.value
			seg.label:SetText(choice.text)
			local w = math.ceil(seg.label:GetUnboundedStringWidth()) + 2 * SEGMENT_PAD
			seg:SetWidth(w)
			seg:ClearAllPoints()
			seg:SetPoint("TOPLEFT", x, 0)
			seg.rule:SetShown(i > 1)
			Paint(seg, Selected(choice.value))
			seg:Show()
			x = x + w
		end
		for i = #choices + 1, #self.segments do
			self.segments[i]:Hide()
		end
		self:SetWidth(math.max(x, 1))
		return x
	end

	return f
end

-- Drag handle in frame's bottom right corner that resizes it (frame must be resizable, with its bounds set).
-- onDone() runs when the drag ends (to save the size).
function UI.ResizeGrip(frame, onDone)
	local grip = CreateFrame("Button", nil, frame)
	grip:SetSize(16, 16)
	grip:SetPoint("BOTTOMRIGHT", -2, 2)
	grip:SetFrameLevel(frame:GetFrameLevel() + 20)
	grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
	grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
	grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
	grip:SetScript("OnMouseDown", function()
		frame:StartSizing("BOTTOMRIGHT")
	end)
	grip:SetScript("OnMouseUp", function()
		frame:StopMovingOrSizing()
		if onDone then
			onDone()
		end
	end)
	return grip
end

-- Progress line -------------------------------------------------------------------------------------------------------

-- A faint 1px line for something still being read. line:Track(read) polls read() while the line is shown: a number
-- (0..1) fills it, eased; true (waiting on the game, nothing to count) sweeps a short segment across; nil hides the
-- line and stops polling. The caller anchors it and redraws its own content when the read is done.
-- Track returns whether the line shows. line:Stop() hides it.
function UI.ProgressLine(parent)
	local line = CreateFrame("Frame", nil, parent)
	line:SetHeight(1)
	line.track = line:CreateTexture(nil, "BACKGROUND")
	line.track:SetAllPoints()
	line.track:SetColorTexture(UI.RGBA("accent", 0.12))
	line.fill = line:CreateTexture(nil, "ARTWORK")
	line.fill:SetColorTexture(UI.RGBA("accent", 0.7))
	line:Hide()

	local function Draw(self)
		local width = self:GetWidth()
		local left, right = 0, width * self.shown
		if self.busy then
			-- The segment enters from the left edge and leaves at the right, clipped to the track.
			local span = width * BUSY_SPAN
			local x = (width + span) * ns.Smoothstep((self.clock % BUSY_SECONDS) / BUSY_SECONDS) - span
			left, right = math.max(x, 0), math.min(x + span, width)
		end
		self.fill:SetShown(right - left >= 1)
		self.fill:ClearAllPoints()
		self.fill:SetPoint("TOPLEFT", left, 0)
		self.fill:SetPoint("BOTTOMLEFT", left, 0)
		self.fill:SetWidth(math.max(right - left, 1))
	end

	local function Read(self)
		local value = self.read()
		if value == nil then
			self:Stop()
			return false
		end
		self.busy = value == true
		self.target = self.busy and 0 or math.min(math.max(value, 0), 1)
		return true
	end

	local function Update(self, elapsed)
		self.clock = self.clock + elapsed
		self.poll = self.poll - elapsed
		if self.poll <= 0 then
			self.poll = PROGRESS_POLL
			if not Read(self) then
				return
			end
		end
		self.shown = self.shown + (self.target - self.shown) * math.min(elapsed * PROGRESS_EASE, 1)
		Draw(self)
	end

	function line:Track(read)
		local first = self.read ~= read
		self.read = read
		if not Read(self) then
			return false
		end
		if first then
			self.shown, self.clock = self.target, 0
		end
		self.poll = PROGRESS_POLL
		self:Show()
		Draw(self)
		self:SetScript("OnUpdate", Update)
		return true
	end

	function line:Stop()
		self.read = nil
		self:SetScript("OnUpdate", nil)
		self:Hide()
	end

	-- Under fs's text (left-aligned text), as wide as it: line:Below(fs):Track(read).
	function line:Below(fs)
		self:ClearAllPoints()
		self:SetPoint("TOPLEFT", fs, "BOTTOMLEFT", 0, -2)
		self:SetWidth(math.max(fs:GetStringWidth(), 1))
		return self
	end

	return line
end

-- A progress line's read for a wait on the game with nothing to count: busy until the caller stops the line (when
-- what it waited for arrives and it redraws).
function UI.ProgressBusy()
	return true
end

-- Escape --------------------------------------------------------------------------------------------------------------

-- Esc closes the Tomte frame on top (the last one shown), one per press, so a dialog over the Tomte window closes on
-- its own. One dummy in UISpecialFrames stands for all of them: Blizzard's CloseSpecialWindows hides it, its OnHide
-- closes the top frame a frame later, and while more are open the dummy shows again. Works in combat, where a frame
-- can't take keyboard input. (RegisterGameMenuEscHandler would be the direct way, but registering a handler from addon
-- code taints the Esc chain.) Alt+Z and loss of control run CloseAllWindows too, and UIParent still counts as shown
-- a frame after Alt+Z (measured 12.1), so only a hide that came with Esc (ToggleGameMenu, the Esc binding) closes
-- anything; after the others the frames stay and come back with the UI.
local escapeOpen = {} -- shown frames in the order they were shown: the last one is on top
local escapeDummy
local escAt -- GetTime() of the last ToggleGameMenu (Esc): the same value in the frame the dummy hid means Esc hid it

-- Drops every frame that isn't shown any more from the list (also one hidden by code while UIParent was hidden,
-- whose OnHide never came).
local function EscapeForget()
	for i = #escapeOpen, 1, -1 do
		if not escapeOpen[i]:IsShown() then
			table.remove(escapeOpen, i)
		end
	end
end

local function EscapeListed(frame)
	for _, f in ipairs(escapeOpen) do
		if f == frame then
			return true
		end
	end
	return false
end

local function EscapeDummy()
	if escapeDummy then
		return escapeDummy
	end
	escapeDummy = CreateFrame("Frame", "TomteEscape", UIParent)
	escapeDummy:Hide()
	tinsert(UISpecialFrames, "TomteEscape")
	-- Only notes the press; Esc handling is Tomte's own, always on, so the hook never needs switching off. It runs
	-- after Blizzard's Esc chain, in the same frame as the dummy's OnHide; the close waits a frame for it.
	hooksecurefunc("ToggleGameMenu", function()
		escAt = GetTime()
	end)
	escapeDummy:SetScript("OnHide", function(self)
		-- Still shown: UIParent hid (Alt+Z, a cinematic), not Esc; the frames come back with it.
		if self:IsShown() then
			return
		end
		local hidAt = GetTime()
		C_Timer.After(0, function()
			EscapeForget()
			-- Esc closes the top frame; Alt+Z, the AFK screen or a loss of control keep them all.
			local top = escAt == hidAt and escapeOpen[#escapeOpen]
			if top then
				top:Hide() -- its OnHide takes it off the list
			end
			if #escapeOpen > 0 and not self:IsShown() then
				self:Show()
			end
		end)
	end)
	return escapeDummy
end

-- Esc closes frame, the last one shown first. Call it after the frame's own SetScript("OnShow"/"OnHide"): SetScript
-- drops hooks.
function UI.CloseOnEscape(frame)
	local dummy = EscapeDummy()
	frame:HookScript("OnShow", function(self)
		EscapeForget()
		-- Already listed: UIParent is back after Alt+Z or a cinematic; the frame keeps its place in the order.
		if not EscapeListed(self) then
			escapeOpen[#escapeOpen + 1] = self
		end
		dummy:Show()
	end)
	frame:HookScript("OnHide", function(self)
		-- Still shown: only UIParent hid, the frame comes back with it and stays on the list.
		if self:IsShown() then
			return
		end
		EscapeForget()
		if #escapeOpen == 0 then
			dummy:Hide()
		end
	end)
end
