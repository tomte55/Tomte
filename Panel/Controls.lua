local addonName, ns = ...

-- More ns.UI controls: an on/off switch, segmented buttons, a resize grip, a progress line with the fade and slide
-- for what arrives after it, a flash, card hover, skeleton rows for lists still being read, and Esc handling for
-- Tomte's windows. The rest of the widget kit is in Widgets.lua;
-- menus and the list a UI.Dropdown opens are in Menu.lua.

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
local FADE_SECONDS = 0.45 -- one region's fade in UI.FadeIn (0.25 s with an ease-out read as no fade at all in game)
local STAGGER_STEP = 0.06 -- most seconds between two rows' fades in UI.FadeInRows
local STAGGER_ROWS = 10 -- about a screenful of list rows: UI.FadeInRows spreads only these
local MIN_ANIM_SECONDS = 0.001 -- the alpha-0 hold's length without a delay, and UI.SlideDown's jump up (above 0)
local SLIDE_DOWN_SECONDS = 0.4 -- UI.SlideDown, and the spread of rows fading in after a read (UI.FADE_SPREAD)
UI.FADE_SPREAD = SLIDE_DOWN_SECONDS
local FLASH_SECONDS = 0.7 -- UI.Flash: the wash rises and fades in this time
local FLASH_RISE = 0.25 -- share of it spent rising
local CARD_POLL = 0.05 -- seconds between checks that the mouse is still on a hovered card (only while hovered)
local CARD_HOVER_IN, CARD_HOVER_OUT = 0.15, 0.3
local CARD_BORDER = 0.5 -- accent alpha of a hovered card's border: dimmer than a hovered button's
local CARD_WASH = 0.5 -- share of the hover color's own alpha: a big card at a button's wash looked selected
local CARD_LIFT = 6 -- height of the shadow under a hovered card (it grows from 1)
local CARD_SHADOW = 0.45
local CARD_PING_DEPTH = 4 -- how many parents up UI.CardHoverPing looks for the card
local SKELETON_ROW_H = 24 -- a Home list row (HomeKit ROW_H)
local SKELETON_ICON = 18
local SKELETON_BAR = 8 -- text bar height
local SKELETON_NUMBER = 36 -- the right-hand number bar's width
-- Each row's text bar as a share of the room, so the rows differ.
local SKELETON_WIDTHS = { 0.72, 0.55, 0.64, 0.48 } -- theme: widths, not a color
local SKELETON_ALPHA = 0.18
local SKELETON_SHINE = 0.14 -- the sweeping band's brightest alpha
local SKELETON_BAND = 70 -- the band's width
local SKELETON_SWEEP, SKELETON_PAUSE = 1.1, 0.5 -- seconds for one sweep, and the rest before the next

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

	-- p: 0 = off, 1 = on, in between while sliding. The knob overshoots a little and settles (UI.EaseOutBack) in the
	-- direction it's sliding; the fill and color ease plainly.
	local function Show(self, p)
		self.progress = p
		local eased = ns.Smoothstep(p)
		self.fill:SetWidth(math.max((width - 2 * pixel) * eased, 0.001))
		self.fill:SetShown(eased > 0)
		local knob = eased
		if self:GetScript("OnUpdate") then
			knob = self.checked and UI.EaseOutBack(p) or 1 - UI.EaseOutBack(1 - p)
		end
		local x = inset + travel * knob
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

	-- No OnHide snap: OnUpdate pauses while hidden, so a slide cut short by a page rebuild (rows hidden and shown
	-- again) finishes when it shows.
	function b:SetChecked(on)
		on = on and true or false
		if on == self.checked and self:GetScript("OnUpdate") then
			return -- a page refresh during the click's slide: let it finish
		end
		self.checked = on
		self:SetScript("OnUpdate", nil)
		Show(self, self.checked and 1 or 0)
	end
	b:SetScript("OnClick", function(self)
		self.checked = not self.checked
		if UI.MotionLevel() == "off" then
			Show(self, self.checked and 1 or 0)
		else
			self:SetScript("OnUpdate", Slide)
		end
		if self.checked then
			UI.Pop(self.knob, 0.25)
		end
		UI.Sound(self.checked and "on" or "off")
		if self.onChange then
			self.onChange(self.checked)
		end
	end)
	b:SetScript("OnEnter", function(self)
		UI.BorderTo(self, "accent", 1)
	end)
	b:SetScript("OnLeave", function(self)
		UI.BorderTo(self, "frame", 0.6)
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

	-- One accent line for a single choice, sliding to the chosen segment; toggles keep a line per segment.
	f.indicator = f:CreateTexture(nil, "OVERLAY")
	f.indicator:SetColorTexture(UI.Color("accent"))
	f.indicator:SetHeight(2)
	f.indicator:Hide()

	local function Paint(seg, selected)
		UI.TweenStop(seg.bg, "alpha")
		seg.bg:SetAlpha((selected or seg:IsMouseOver()) and 1 or 0)
		seg.line:SetShown(selected and f.isOn ~= nil)
		UI.SetTextRole(seg.label, selected and "text" or "textMuted")
	end

	local function PlaceIndicator(from)
		local to
		for _, seg in ipairs(f.segments) do
			if seg:IsShown() and Selected(seg.value) then
				to = seg
			end
		end
		if f.isOn or not to then
			f.indicator:Hide()
			return
		end
		local toX, toW = select(4, to:GetPoint(1)), to:GetWidth()
		local function Put(x, w)
			f.indicator:ClearAllPoints()
			f.indicator:SetPoint("BOTTOMLEFT", x, 0)
			f.indicator:SetWidth(w)
		end
		f.indicator:Show()
		if not from or not f:IsVisible() then
			UI.TweenStop(f.indicator, "slide")
			Put(toX, toW)
			return
		end
		UI.Tween(f.indicator, "slide", 0.22, function(t)
			Put(UI.Lerp(from.x, toX, t), UI.Lerp(from.w, toW, t))
		end, nil, UI.EaseOutBack)
	end

	local function IndicatorNow()
		if not f.indicator:IsShown() then
			return nil
		end
		local x = select(4, f.indicator:GetPoint(1)) or 0
		return { x = x, w = f.indicator:GetWidth() }
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
		seg.bg:SetAlpha(0)
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
			UI.AlphaTo(self.bg, Selected(self.value) and 1 or 0, 0.2)
			if f.onLeave then
				f.onLeave()
			end
		end)
		seg:SetScript("OnClick", function(self)
			if f.toggle then
				f.toggle(self.value)
				UI.Sound("pick")
				f:Refresh()
			elseif f.getValue() ~= self.value then
				UI.Sound("pick")
				local from = IndicatorNow()
				f.setValue(self.value)
				f:Refresh(from)
				UI.Pop(self.label, 0.1)
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

	-- from: where the indicator was before a click ({ x, w }), so it slides from there.
	function f:Refresh(from)
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
		PlaceIndicator(from)
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

-- Fades a frame or region in from nothing to the alpha it has (a dimmed button stays dimmed), for content that just
-- arrived after a progress line. Callers fade only on the change from reading to done, not on every redraw.
-- delay (seconds) holds it at nothing first, for rows that fade in one after another (UI.FadeInRows).
function UI.FadeIn(region, delay)
	if UI.MotionLevel() == "off" then
		return
	end
	local group = region.fadeIn
	if not group then
		group = region:CreateAnimationGroup()
		-- A start delay alone would show the region at full alpha until its fade begins: an alpha-0 hold goes first.
		group.hold = group:CreateAnimation("Alpha")
		group.hold:SetOrder(1)
		group.hold:SetFromAlpha(0)
		group.hold:SetToAlpha(0)
		group.alpha = group:CreateAnimation("Alpha")
		group.alpha:SetOrder(2)
		group.alpha:SetFromAlpha(0)
		group.alpha:SetSmoothing("IN_OUT")
		region.fadeIn = group
	end
	group:Stop()
	group.hold:SetDuration(math.max(delay or 0, MIN_ANIM_SECONDS))
	group.alpha:SetDuration(FADE_SECONDS)
	group.alpha:SetToAlpha(region:GetAlpha())
	group:Play()
end

-- Fades rows[first..last] in from the top down, spread over spread seconds (at most STAGGER_STEP apart). Only the
-- first STAGGER_ROWS are spread out; the rest start with the last of them, so a long list doesn't trickle in.
function UI.FadeInRows(rows, first, last, spread)
	local n = last - first + 1
	if n <= 0 then
		return
	end
	spread = spread or 0
	local step = math.min(STAGGER_STEP, spread / math.min(n, STAGGER_ROWS))
	for i = first, last do
		UI.FadeIn(rows[i], math.min((i - first) * step, spread))
	end
end

-- For a list redrawn while (or just after) its data was read: rows whose key wasn't in seen fade in top down, and
-- the rows below the first new one slide down by the new rows' height (row.space when set, else its height), so the
-- list opens instead of jumping. keyOf(row) names a row (nil: not tracked). seen nil (a first draw, another map)
-- animates nothing. gone: the height of rows that left in their place (the new rows replace them). Returns the keys
-- shown now, to pass as seen next time.
function UI.ListArrivals(rows, n, seen, keyOf, gone)
	local keys, news, below, height = {}, {}, {}, 0
	for i = 1, n do
		local row = rows[i]
		local key = keyOf(row)
		if key ~= nil then
			keys[key] = true
		end
		if seen and key ~= nil and not seen[key] then
			news[#news + 1] = row
			height = height + (row.space or row:GetHeight())
		elseif #news > 0 then
			below[#below + 1] = row
		end
	end
	UI.FadeInRows(news, 1, #news, SLIDE_DOWN_SECONDS)
	UI.SlideDown(below, 1, #below, height - (gone or 0))
	return keys
end

-- Draws frames[first..last] dy higher (dy < 0: lower) and eases them into their places. Moves only how they're
-- drawn: their anchors are already final.
local function SlideFrom(frames, first, last, dy)
	for i = first, last do
		local frame = frames[i]
		local group = frame.slideDown
		if not group then
			group = frame:CreateAnimationGroup()
			-- Within a group, a finished translation stays applied until the group ends: up at once, then down.
			group.up = group:CreateAnimation("Translation")
			group.up:SetOrder(1)
			group.up:SetDuration(MIN_ANIM_SECONDS)
			group.down = group:CreateAnimation("Translation")
			group.down:SetOrder(2)
			group.down:SetDuration(SLIDE_DOWN_SECONDS)
			group.down:SetSmoothing("IN_OUT")
			frame.slideDown = group
		end
		group:Stop()
		group.up:SetOffset(0, dy)
		group.down:SetOffset(0, -dy)
		group:Play()
	end
end

-- Slides frames[first..last] down into their places from height higher, for what sits below rows that just
-- arrived (the space opens instead of jumping).
function UI.SlideDown(frames, first, last, height)
	if height <= 0 or UI.MotionLevel() == "off" then
		return
	end
	SlideFrom(frames, first, last, height)
end

-- Slides frames[first..last] up into their places from height lower, for what sits below rows that just left (the
-- gap closes instead of jumping).
function UI.SlideUp(frames, first, last, height)
	if height <= 0 or UI.MotionLevel() == "off" then
		return
	end
	SlideFrom(frames, first, last, -height)
end

-- Flash, card hover and skeleton rows ---------------------------------------------------------------------------------

-- Washes frame in role (accent by default) up to peak alpha (default 0.25) and back out: something on it just
-- changed (a module turned on, a count that moved). The wash is a texture made once per frame on its BACKGROUND
-- layer, above a hover wash. Fades only, so it plays on "subtle" too.
function UI.Flash(frame, role, peak)
	local wash = frame.flashWash
	if not wash then
		wash = frame:CreateTexture(nil, "BACKGROUND", nil, 3)
		wash:SetAllPoints()
		wash:SetAlpha(0)
		frame.flashWash = wash
	end
	if UI.MotionLevel() == "off" or not frame:IsVisible() then
		UI.TweenStop(wash, "flash")
		wash:SetAlpha(0)
		return
	end
	wash:SetColorTexture(UI.RGBA(role or "accent", 1))
	peak = peak or 0.25
	UI.Tween(wash, "flash", FLASH_SECONDS, function(_, p)
		local a = p < FLASH_RISE and p / FLASH_RISE or (1 - p) / (1 - FLASH_RISE)
		wash:SetAlpha(peak * ns.Smoothstep(a))
	end)
end

-- Hover state for a card: its border eases toward accent, a faint wash comes up and a soft shadow grows under it (a
-- lift that leaves the text on its pixels). The card takes mouse motion only (clicks pass through); its rows take the
-- mouse too, so while hovered it polls IsMouseOver instead of trusting OnLeave, and a row's own OnEnter calls
-- UI.CardHoverPing so a card entered straight onto a row lights up too.
-- opts.outset: the look reaches this far past the card and draws its own border, invisible at rest (Home's sections,
-- which have no box). Without it the card's own border (UI.Surface) eases, from opts.role / opts.alpha
-- ("frame", 0.35) at rest.
function UI.CardHover(card, opts)
	opts = opts or {}
	local out = opts.outset or 0
	local h = { card = card, out = out }
	if out > 0 or not card.borderEdges then
		h.ring = CreateFrame("Frame", nil, card)
		h.ring:SetPoint("TOPLEFT", -out, out)
		h.ring:SetPoint("BOTTOMRIGHT", out, -out)
		UI.Border(h.ring, "accent", 0)
		h.restRole, h.restAlpha = "accent", 0
	else
		h.ring = card
		h.restRole, h.restAlpha = opts.role or "frame", opts.alpha or 0.35
	end
	h.wash = card:CreateTexture(nil, "BACKGROUND", nil, 2)
	h.wash:SetPoint("TOPLEFT", -out, out)
	h.wash:SetPoint("BOTTOMRIGHT", out, -out)
	h.wash:SetAlpha(0)
	h.shadow = card:CreateTexture(nil, "BACKGROUND", nil, -8)
	h.shadow:SetColorTexture(1, 1, 1, 1)
	h.shadow:SetPoint("TOPLEFT", card, "BOTTOMLEFT", 2 - out, -out)
	h.shadow:SetPoint("TOPRIGHT", card, "BOTTOMRIGHT", out - 2, -out)
	h.shadow:SetHeight(1)
	h.shadow:SetAlpha(0)
	h.watch = CreateFrame("Frame", nil, card)
	card.cardHover = h

	local function Over()
		return card:IsVisible() and card:IsMouseOver(out, -out, -out, out)
	end

	local function Lift(on, now)
		local fromH, fromA = h.shadow:GetHeight(), h.shadow:GetAlpha()
		local toH, toA = on and CARD_LIFT or 1, on and 1 or 0
		if now then
			UI.TweenStop(h.shadow, "lift")
			h.shadow:SetHeight(toH)
			h.shadow:SetAlpha(toA)
			return
		end
		UI.Tween(h.shadow, "lift", on and CARD_HOVER_IN or CARD_HOVER_OUT, function(t)
			h.shadow:SetHeight(UI.Lerp(fromH, toH, t))
			h.shadow:SetAlpha(UI.Lerp(fromA, toA, t))
		end)
	end

	function h:Off(now)
		self.on = false
		self.watch:SetScript("OnUpdate", nil)
		if now then
			UI.SetBorderColor(self.ring, self.restRole, self.restAlpha)
			UI.TweenStop(self.wash, "alpha")
			self.wash:SetAlpha(0)
		else
			UI.BorderTo(self.ring, self.restRole, self.restAlpha, CARD_HOVER_OUT)
			UI.AlphaTo(self.wash, 0, CARD_HOVER_OUT)
		end
		Lift(false, now)
	end

	local since = 0
	local function Poll(_, elapsed)
		since = since + elapsed
		if since < CARD_POLL then
			return
		end
		since = 0
		if not Over() then
			h:Off()
		end
	end

	function h:On()
		if self.on or not Over() then
			return
		end
		self.on = true
		-- Colors are read here, not when the card is made: a theme switch reaches them.
		local r, g, b, a = UI.Color("hover")
		self.wash:SetColorTexture(r, g, b, (a or 1) * CARD_WASH)
		self.shadow:SetGradient("VERTICAL", UI.ColorObject("bgBottom", 0), UI.ColorObject("frameDark", CARD_SHADOW))
		UI.BorderTo(self.ring, "accent", CARD_BORDER, CARD_HOVER_IN)
		UI.AlphaTo(self.wash, 1, CARD_HOVER_IN)
		Lift(true)
		since = 0
		self.watch:SetScript("OnUpdate", Poll)
	end

	card:SetMouseMotionEnabled(true)
	card:HookScript("OnEnter", function()
		h:On()
	end)
	-- Hidden mid-hover (a page change, a pooled card released): back to rest at once, not stuck lit.
	card:HookScript("OnHide", function()
		if h.on then
			h:Off(true)
		end
	end)
	return h
end

-- From a row's OnEnter: lights the card the row sits on (UI.CardHover), a few parents up.
function UI.CardHoverPing(region)
	local frame = region and region:GetParent()
	for _ = 1, CARD_PING_DEPTH do
		if not frame then
			return
		end
		if frame.cardHover then
			frame.cardHover:On()
			return
		end
		frame = frame:GetParent()
	end
end

-- Placeholder rows for a list still being read: an icon square, a text bar and a short number bar per row, muted,
-- with a soft band of light sweeping across them while shown (static bars when Motion is off). The caller anchors it
-- (its height is rows * rowHeight), shows it while reading and hides it when the real rows arrive.
-- skeleton:SetRows(n) changes the row count.
local function Bone(sk)
	local bone = CreateFrame("Frame", nil, sk)
	bone:SetClipsChildren(true)
	bone.bg = bone:CreateTexture(nil, "BACKGROUND")
	bone.bg:SetAllPoints()
	bone.band = CreateFrame("Frame", nil, bone)
	bone.band.left = bone.band:CreateTexture(nil, "ARTWORK")
	bone.band.left:SetPoint("TOPLEFT")
	bone.band.left:SetPoint("BOTTOMRIGHT", bone.band, "BOTTOM")
	bone.band.left:SetColorTexture(1, 1, 1, 1)
	bone.band.right = bone.band:CreateTexture(nil, "ARTWORK")
	bone.band.right:SetPoint("TOPLEFT", bone.band, "TOP")
	bone.band.right:SetPoint("BOTTOMRIGHT")
	bone.band.right:SetColorTexture(1, 1, 1, 1)
	bone.anim = bone.band:CreateAnimationGroup()
	bone.anim:SetLooping("REPEAT")
	bone.move = bone.anim:CreateAnimation("Translation")
	bone.move:SetDuration(SKELETON_SWEEP)
	bone.move:SetEndDelay(SKELETON_PAUSE)
	bone.move:SetSmoothing("IN_OUT")
	return bone
end

function UI.Skeleton(parent, rows, rowHeight)
	local sk = CreateFrame("Frame", nil, parent)
	sk.rowHeight = rowHeight or SKELETON_ROW_H
	sk.bones = {}

	-- Each bone's band starts left of the skeleton and runs its whole width, so the sweep lines up down the rows.
	local function Place(bone, x, y, w, hgt)
		bone:ClearAllPoints()
		bone:SetPoint("TOPLEFT", sk, "TOPLEFT", x, -y)
		bone:SetSize(math.max(w, 1), hgt)
		bone.band:ClearAllPoints()
		bone.band:SetPoint("TOPLEFT", sk, "TOPLEFT", -SKELETON_BAND, -y)
		bone.band:SetSize(SKELETON_BAND, hgt)
		bone:Show()
	end

	local function Paint()
		local clear, bright = UI.ColorObject("text", 0), UI.ColorObject("text", SKELETON_SHINE)
		local r, g, b = UI.Color("textFaint")
		for _, bone in ipairs(sk.bones) do
			bone.bg:SetColorTexture(r, g, b, SKELETON_ALPHA)
			bone.band.left:SetGradient("HORIZONTAL", clear, bright)
			bone.band.right:SetGradient("HORIZONTAL", bright, clear)
		end
	end

	local function Play()
		local width = sk:GetWidth()
		local moving = UI.MotionLevel() ~= "off" and sk:IsVisible() and width and width > 1
		for _, bone in ipairs(sk.bones) do
			bone.anim:Stop()
			bone.band:SetShown(moving and true or false)
			if moving and bone:IsShown() then
				bone.move:SetOffset(width + SKELETON_BAND, 0)
				bone.anim:Play()
			end
		end
	end

	function sk:Layout()
		local width = self:GetWidth()
		if not (width and width > 1) then
			return
		end
		local rh = self.rowHeight
		local iconSize = math.min(SKELETON_ICON, rh - 6)
		local barH = SKELETON_BAR
		local numberW = SKELETON_NUMBER
		local room = width - iconSize - 8 - numberW - 16
		local n = 0
		for i = 1, self.rows do
			local top = (i - 1) * rh
			local function Next()
				n = n + 1
				self.bones[n] = self.bones[n] or Bone(self)
				return self.bones[n]
			end
			Place(Next(), 0, top + math.floor((rh - iconSize) / 2), iconSize, iconSize)
			local barY = top + math.floor((rh - barH) / 2)
			Place(Next(), iconSize + 8, barY, math.floor(room * SKELETON_WIDTHS[(i - 1) % #SKELETON_WIDTHS + 1]), barH)
			Place(Next(), width - numberW, barY, numberW, barH)
		end
		for i = n + 1, #self.bones do
			self.bones[i].anim:Stop()
			self.bones[i]:Hide()
		end
		Paint()
		Play()
	end

	function sk:SetRows(count)
		self.rows = math.max(count or 1, 1)
		self:SetHeight(self.rows * self.rowHeight)
		self:Layout()
	end

	sk:SetScript("OnShow", function(self)
		self:Layout()
	end)
	sk:SetScript("OnSizeChanged", function(self)
		self:Layout()
	end)
	-- Only sweeps while shown: a hidden skeleton runs nothing.
	sk:SetScript("OnHide", function(self)
		for _, bone in ipairs(self.bones) do
			bone.anim:Stop()
		end
	end)
	sk.rows = math.max(rows or 3, 1)
	sk:SetHeight(sk.rows * sk.rowHeight)
	return sk
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
