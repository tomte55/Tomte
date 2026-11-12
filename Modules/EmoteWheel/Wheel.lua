local addonName, ns = ...

-- Emote wheel: the wheel itself. A ring of slices around a middle that shows the slice under the cursor; it opens
-- at the cursor while the key is held and says which slice was picked when it closes. Drawn from discs (the portrait
-- mask), the Showcase art and Line objects: the spokes, and the picked slice's wedge as a fan of thick lines (a
-- texture can't be cut into a wedge). The same drawing makes the settings preview. Rules in Data.lua, registered in
-- EmoteWheel.lua.

local ART = ns.Theme.MEDIA .. "Showcase\\"
local DISC = "Interface\\CharacterFrame\\TempPortraitAlphaMask" -- a white disc
local RADIUS = 150 -- slice ring, at scale 1
local INNER = 54 -- the middle's radius
local GAP = 6 -- the dark ring between the middle and the slices
local LABEL_R = 106 -- slice names sit this far out
local MARK_R = RADIUS - 12 -- the small diamond on each slice
local FAN_STEP = math.rad(2) -- one line of the picked wedge per this many radians: small enough to look round
local FAN_MAX = 46 -- lines in the fan: a 90 degree slice (4 slices) at FAN_STEP
local HIGHLIGHT_MIX = 0.38 -- share of the accent color in the picked wedge, mixed into the background
local FADE_IN = 0.08 -- seconds
local OUTER = RADIUS + 10 -- the wheel's own frame reaches this far: the rims sit outside the slices
local UI = ns.UI

local Angle, Point = ns.EmoteWheel_Angle, ns.EmoteWheel_Point

local live -- the wheel that opens at the cursor
local state -- while live is open: { slices, opts, picked, onPick }

local function Disc(w, sublevel, size)
	local t = w:CreateTexture(nil, "BACKGROUND", nil, sublevel)
	t:SetTexture(DISC)
	t:SetSize(size, size)
	t:SetPoint("CENTER")
	return t
end

local function Paint(t, role, alpha)
	local r, g, b = UI.RGBA(role)
	t:SetVertexColor(r, g, b, alpha or 1)
end

local function Mixed(role, into, share)
	local r1, g1, b1 = UI.RGBA(into)
	local r2, g2, b2 = UI.RGBA(role)
	return r1 + (r2 - r1) * share, g1 + (g2 - g1) * share, b1 + (b2 - b1) * share
end

local function Build(parent)
	local w = CreateFrame("Frame", nil, parent)
	w:SetSize(OUTER * 2, OUTER * 2)
	w.glow = w:CreateTexture(nil, "BACKGROUND", nil, -8)
	w.glow:SetTexture(ART .. "Glow")
	w.glow:SetSize(OUTER * 2 + 70, OUTER * 2 + 70)
	w.glow:SetPoint("CENTER")
	w.outerLine = Disc(w, -7, (RADIUS + 9) * 2)
	w.outerGap = Disc(w, -6, (RADIUS + 7) * 2)
	w.rim = Disc(w, -5, (RADIUS + 3) * 2)
	w.base = Disc(w, -4, RADIUS * 2)

	w.fan = {}
	for i = 1, FAN_MAX do
		local line = w:CreateLine(nil, "ARTWORK", nil, 0)
		line:Hide()
		w.fan[i] = line
	end
	w.spokes, w.marks, w.names, w.cmds = {}, {}, {}, {}
	for i = 1, ns.EMOTEWHEEL_MAX do
		local spoke = w:CreateLine(nil, "ARTWORK", nil, 2)
		spoke:SetThickness(2)
		w.spokes[i] = spoke
		local mark = w:CreateTexture(nil, "OVERLAY")
		mark:SetTexture(ART .. "Diamond")
		mark:SetSize(8, 8)
		w.marks[i] = mark
		w.names[i] = UI.Text(w, 15, "text", "title")
		w.names[i]:SetJustifyH("CENTER")
		w.names[i]:SetWordWrap(false)
		w.cmds[i] = UI.Text(w, 11, "textMuted")
		w.cmds[i]:SetJustifyH("CENTER")
		w.cmds[i]:SetWordWrap(false)
	end

	w.ring = w:CreateTexture(nil, "ARTWORK", nil, 3)
	w.ring:SetTexture(DISC)
	w.ring:SetSize((INNER + GAP) * 2, (INNER + GAP) * 2)
	w.ring:SetPoint("CENTER")
	w.middleRim = w:CreateTexture(nil, "ARTWORK", nil, 4)
	w.middleRim:SetTexture(DISC)
	w.middleRim:SetSize(INNER * 2, INNER * 2)
	w.middleRim:SetPoint("CENTER")
	w.middle = w:CreateTexture(nil, "ARTWORK", nil, 5)
	w.middle:SetTexture(DISC)
	w.middle:SetSize(INNER * 2 - 4, INNER * 2 - 4)
	w.middle:SetPoint("CENTER")

	w.title = UI.Text(w, 17, "accent", "title")
	w.title:SetJustifyH("CENTER")
	w.title:SetWordWrap(false)
	w.title:SetWidth(INNER * 2 - 12)
	w.title:SetPoint("BOTTOM", w, "CENTER", 0, 6)
	w.detail = UI.Text(w, 11, "textMuted")
	w.detail:SetJustifyH("CENTER")
	w.detail:SetWidth(INNER * 2 - 14)
	w.detail:SetMaxLines(2)
	w.detail:SetPoint("TOP", w, "CENTER", 0, 2)
	return w
end

-- Colors from the theme on every layout: a theme switch reaches an open or reopened wheel.
local function Colorize(w)
	Paint(w.glow, "accent", 0.22)
	Paint(w.outerLine, "accent", 0.55)
	Paint(w.outerGap, "bg")
	Paint(w.rim, "accent")
	Paint(w.base, "bg")
	Paint(w.ring, "frameDark")
	Paint(w.middleRim, "accent")
	Paint(w.middle, "bg")
	local r, g, b = Mixed("accent", "bg", HIGHLIGHT_MIX)
	for _, line in ipairs(w.fan) do
		line:SetColorTexture(r, g, b, 1)
	end
	for _, spoke in ipairs(w.spokes) do
		spoke:SetColorTexture(UI.RGBA("frameDark"))
	end
end

local function Fan(w, index, count)
	local used = 0
	if index then
		local step = 2 * math.pi / count
		local n = math.min(math.ceil(step / FAN_STEP), FAN_MAX)
		local each = step / n
		local thick = 2 * RADIUS * math.sin(each / 2) + 1.5 -- wide enough at the rim that neighbours overlap
		local from = Angle(index, count) - step / 2
		for k = 1, n do
			local a = from + (k - 0.5) * each
			local line = w.fan[k]
			local x1, y1 = Point(a, INNER + GAP - 2)
			local x2, y2 = Point(a, RADIUS - 1)
			line:SetStartPoint("CENTER", w, x1, y1)
			line:SetEndPoint("CENTER", w, x2, y2)
			line:SetThickness(thick)
			line:Show()
		end
		used = n
	end
	for k = used + 1, FAN_MAX do
		w.fan[k]:Hide()
	end
end

-- The slice text with %t filled in, for showing (the target's name, or "%t" left as it is without one).
local function Shown(text, target)
	return ns.EmoteWheel_Fill(text, target) or text
end

-- slices: from ns.EmoteWheel_Slices; opts: { showCommand, showTarget, target (name or nil) }; picked: slice index
-- or nil.
local function Layout(w, slices, opts, picked)
	Colorize(w)
	local count = math.max(#slices, ns.EMOTEWHEEL_MIN)
	local step = 2 * math.pi / count
	local small = count > 8
	local nameWidth = math.min(118, 2 * LABEL_R * math.sin(step / 2) + 10)
	for i = 1, ns.EMOTEWHEEL_MAX do
		local spoke, mark, name, cmd = w.spokes[i], w.marks[i], w.names[i], w.cmds[i]
		if i > count then
			spoke:Hide()
			mark:Hide()
			name:Hide()
			cmd:Hide()
		else
			local edge = Angle(i, count) - step / 2
			local x1, y1 = Point(edge, INNER + GAP)
			local x2, y2 = Point(edge, RADIUS)
			spoke:SetStartPoint("CENTER", w, x1, y1)
			spoke:SetEndPoint("CENTER", w, x2, y2)
			spoke:Show()

			local slice = slices[i]
			local on = picked == i
			local a = Angle(i, count)
			local mx, my = Point(a, MARK_R)
			mark:ClearAllPoints()
			mark:SetPoint("CENTER", w, "CENTER", mx, my)
			Paint(mark, "accent", on and 1 or 0.45)
			mark:SetShown(slice ~= nil)

			local lx, ly = Point(a, LABEL_R)
			local withCmd = opts.showCommand and slice ~= nil
			UI.SetFont(name, "title", small and 13 or 15)
			name:SetWidth(nameWidth)
			name:ClearAllPoints()
			name:SetPoint(withCmd and "BOTTOM" or "CENTER", w, "CENTER", lx, ly)
			name:SetText(slice and ns.EmoteWheel_Label(slice) or "")
			UI.SetTextRole(name, on and "accent" or "text")
			name:Show()
			cmd:SetWidth(nameWidth)
			cmd:ClearAllPoints()
			cmd:SetPoint("TOP", name, "BOTTOM", 0, -1)
			cmd:SetText(withCmd and ns.EmoteWheel_Short(Shown(slice.text, opts.target), small and 12 or 15) or "")
			UI.SetTextRole(cmd, on and "accent" or "textMuted", on and 0.85 or nil)
			cmd:SetShown(withCmd)
		end
	end
	local slice = picked and slices[picked]
	Fan(w, slice and picked, count)
	local lines = {}
	if slice then
		w.title:SetText(ns.EmoteWheel_Label(slice))
		UI.SetTextRole(w.title, "accent")
		if opts.showCommand then
			lines[#lines + 1] = ns.EmoteWheel_Short(Shown(slice.text, opts.target), 16)
		end
	else
		w.title:SetText(opts.cancelText or "")
		UI.SetTextRole(w.title, "textMuted")
	end
	if opts.showTarget and opts.target then
		lines[#lines + 1] = "> " .. ns.EmoteWheel_Short(opts.target, 14)
	end
	w.detail:SetText(table.concat(lines, "\n"))
end

-- Open at the cursor -------------------------------------------------------------------------------------------------

local function CursorOffset()
	local x, y = GetCursorPosition()
	local scale = live:GetEffectiveScale()
	local cx, cy = live:GetCenter()
	return x / scale - cx, y / scale - cy
end

local function OnUpdate(self, elapsed)
	if self.fade then
		self.fade = self.fade + elapsed
		local p = math.min(self.fade / FADE_IN, 1)
		self:SetAlpha(state.opts.alpha * ns.Smoothstep(p))
		if p >= 1 then
			self.fade = nil
		end
	end
	local dx, dy = CursorOffset()
	local count = math.max(#state.slices, ns.EMOTEWHEEL_MIN)
	local index = ns.EmoteWheel_SliceAt(dx, dy, count, state.opts.centerCancels and INNER or GAP * 3)
	if index and not state.slices[index] then
		index = nil -- an empty slice of a wheel with fewer than the minimum
	end
	if not index and not state.opts.centerCancels then
		index = state.picked -- back in the middle: keep the last slice
	end
	if index ~= state.picked then
		state.picked = index
		Layout(live, state.slices, state.opts, index)
	end
end

-- slices, opts as for Layout, plus opts.scale, opts.alpha and opts.centerCancels.
function ns.EmoteWheel_Open(slices, opts)
	if not live then
		live = Build(UIParent)
		live:SetFrameStrata("FULLSCREEN_DIALOG")
		live:SetClampedToScreen(true)
		live:EnableMouse(false) -- the cursor moves freely over it; nothing under it is blocked
		live:Hide()
		live:SetScript("OnUpdate", OnUpdate)
	end
	state = { slices = slices, opts = opts }
	live:SetScale(opts.scale)
	local x, y = GetCursorPosition()
	local scale = live:GetEffectiveScale()
	live:ClearAllPoints()
	live:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x / scale, y / scale)
	Layout(live, slices, opts, nil)
	if UI.MotionLevel() == "off" then
		live.fade = nil
		live:SetAlpha(opts.alpha)
	else
		live.fade = 0
		live:SetAlpha(0)
	end
	live:Show()
end

-- Closes the wheel; returns the picked slice (from the slices it was opened with) or nil.
function ns.EmoteWheel_Close()
	if not (live and live:IsShown()) then
		return nil
	end
	live:Hide()
	local slice = state.picked and state.slices[state.picked]
	state = nil
	return slice
end

function ns.EmoteWheel_IsOpen()
	return live ~= nil and live:IsShown()
end

-- A still wheel drawn into host for the settings preview, picked slice highlighted. Returns its size.
function ns.EmoteWheel_Draw(host, slices, opts, picked)
	local w = host.wheel
	if not w then
		w = Build(host)
		w:SetPoint("TOPLEFT")
		host.wheel = w
	end
	w:SetScale(opts.scale or 1)
	w:SetAlpha(opts.alpha or 1)
	Layout(w, slices, opts, picked)
	local size = OUTER * 2 * (opts.scale or 1)
	return size, size
end
