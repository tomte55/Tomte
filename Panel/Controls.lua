local addonName, ns = ...

-- More ns.UI controls: an on/off switch, segmented buttons and a resize grip. The rest of the widget kit is in
-- Widgets.lua; menus and the list a UI.Dropdown opens are in Menu.lua.

local UI = ns.UI
local SWITCH_W, SWITCH_H = 34, 16
local KNOB_W = 9
local KNOB_INSET = 3 -- on all four sides, so the knob is 10 tall
local SLIDE_SECONDS = 0.15
UI.SWITCH_SECONDS = SLIDE_SECONDS -- Options.lua waits this long before re-laying rows after a switch
local SEGMENT_PAD = 10 -- text inset on each side of a segment
local SEGMENT_H = 20

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
-- UI.Dropdown, then call Refresh (lays the segments out and sizes the frame to them).
function UI.Segmented(parent)
	local f = CreateFrame("Frame", nil, parent)
	f:SetHeight(SEGMENT_H)
	UI.Border(f, "frame", 0.5)
	f.segments = {}
	f.measure = UI.Text(f, 12, "text")
	f.measure:Hide()

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
			Paint(self, f.getValue() == self.value)
			if f.onEnter then
				f.onEnter()
			end
		end)
		seg:SetScript("OnLeave", function(self)
			self.bg:SetShown(f.getValue() == self.value)
			if f.onLeave then
				f.onLeave()
			end
		end)
		seg:SetScript("OnClick", function(self)
			if f.getValue() ~= self.value then
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
		local value = self.getValue()
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
			Paint(seg, choice.value == value)
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
