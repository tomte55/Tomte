local addonName, ns = ...

-- More ns.UI controls for the settings cards: an on/off switch and segmented buttons. The rest of the widget kit is
-- in Widgets.lua.

local UI = ns.UI
local SWITCH_W, SWITCH_H = 28, 14
local KNOB = 10
local SEGMENT_PAD = 10 -- text inset on each side of a segment
local SEGMENT_H = 20

-- Switch: same API as UI.Checkbox (SetChecked, .checked, .onChange, Enable/Disable dims it).
function UI.Switch(parent)
	local b = CreateFrame("Button", nil, parent)
	b:SetSize(SWITCH_W, SWITCH_H)
	b:SetHitRectInsets(-4, -4, -4, -4)
	b.track = b:CreateTexture(nil, "BACKGROUND")
	b.track:SetAllPoints()
	UI.Border(b, "frame", 0.6)
	b.knob = b:CreateTexture(nil, "ARTWORK")
	b.knob:SetSize(KNOB, KNOB)
	function b:SetChecked(on)
		self.checked = on and true or false
		self.knob:ClearAllPoints()
		if self.checked then
			self.track:SetColorTexture(UI.Color("accent"))
			self.track:SetAlpha(0.85)
			self.knob:SetColorTexture(UI.Color("bg"))
			self.knob:SetPoint("RIGHT", -2, 0)
		else
			self.track:SetColorTexture(UI.Color("surface"))
			self.track:SetAlpha(1)
			self.knob:SetColorTexture(UI.Color("textFaint"))
			self.knob:SetPoint("LEFT", 2, 0)
		end
	end
	b:SetScript("OnClick", function(self)
		self:SetChecked(not self.checked)
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
