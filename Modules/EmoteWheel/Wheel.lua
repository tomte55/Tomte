local addonName, ns = ...

-- Emote wheel: the wheel itself. A ring of separate slices around a middle that shows the slice under the cursor; it
-- opens at the cursor while the key is held and says which slice was picked when it closes. Drawn from grey art
-- tinted by theme role (tools/emotewheel_art.py): one slice texture per slice count, turned into place, a lit arc on
-- the picked slice, the middle disc and a soft shadow under it all. The same drawing makes the settings preview. Rules
-- in Data.lua, registered in EmoteWheel.lua.

local ART = ns.Theme.MEDIA .. "EmoteWheel\\"
local RADIUS = 150 -- slice ring, at scale 1; RADIUS, INNER and GAP match tools/emotewheel_art.py
local INNER = 54 -- the middle's radius
local GAP = 6 -- the open ring between the middle and the slices
local SHADOW_R = RADIUS + 40 -- the shadow texture's reach
local LABEL_R = 106 -- slice names sit this far out
local LABEL_ROOM = 8 -- a label this close to its slice's sides or rims moves to where it has more room
local LABEL_SHIFT = 30 -- how far sideways it may move
local LINE_GAP = 1 -- between a slice's name and its command
local SLICE_ALPHA = 0.92 -- the slices let a little of the world through
local EMPTY_ALPHA = 0.45 -- a slot of a wheel with fewer than the minimum slices
local SHADOW_ALPHA = 0.55
local HUB_RING_ALPHA = 0.55
local HIGHLIGHT_MIX = 0.16 -- share of the accent color in the picked slice, mixed into the background
local HOVER_MIX = 0.07 -- the editor: a slice under the mouse, a step short of picked
local FADE_IN = 0.08 -- seconds
local OUTER = RADIUS + 10 -- the wheel's own frame reaches this far
local UI = ns.UI

local Angle = ns.EmoteWheel_Angle

local places = {} -- [slice, count, text sizes] = where its label goes: { x, y, name dy, command dy }
local live -- the wheel that opens at the cursor
local state -- while live is open: { slices, opts, picked, onPick }

local function Art(w, layer, sublevel, file, radius)
	local t = w:CreateTexture(nil, layer, nil, sublevel)
	if file then
		t:SetTexture(ART .. file)
	end
	t:SetSize(radius * 2, radius * 2)
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
	w.shadow = Art(w, "BACKGROUND", -8, "Shadow", SHADOW_R)
	w.arc = Art(w, "ARTWORK", 0, nil, RADIUS)
	w.slices, w.names, w.cmds = {}, {}, {}
	for i = 1, ns.EMOTEWHEEL_MAX do
		w.slices[i] = Art(w, "BACKGROUND", -4, nil, RADIUS)
		w.names[i] = UI.Text(w, 15, "text", "title")
		w.names[i]:SetJustifyH("CENTER")
		w.names[i]:SetWordWrap(false)
		w.cmds[i] = UI.Text(w, 11, "textMuted")
		w.cmds[i]:SetJustifyH("CENTER")
		w.cmds[i]:SetWordWrap(false)
	end

	w.hub = Art(w, "ARTWORK", 4, "Hub", INNER)
	w.hubRing = Art(w, "ARTWORK", 5, "HubRing", INNER)

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
	Paint(w.shadow, "bg", SHADOW_ALPHA) -- the art is black, so any tint stays a shadow
	Paint(w.arc, "accent")
	Paint(w.hub, "bg")
	Paint(w.hubRing, "accent", HUB_RING_ALPHA)
end

-- One slice texture per slice count, drawn pointing up; turned to its place (SetRotation turns counter-clockwise,
-- Angle counts clockwise).
local function Turn(t, count, i)
	t:SetTexture(ART .. "Slice" .. count)
	t:SetRotation(-Angle(i, count))
end

-- The slice text with %t filled in, for showing (the target's name, or "%t" left as it is without one), its lines
-- joined into one.
local function Shown(text, target)
	return ns.EmoteWheel_OneLine(ns.EmoteWheel_Fill(text, target) or text)
end

-- What a slice is called on the wheel; a slice the editor hasn't filled yet (no text) shows opts.emptyLabel.
local function Name(slice, opts)
	if slice.text == "" then
		return opts.emptyLabel or ""
	end
	return ns.EmoteWheel_Label(slice)
end

-- Places slice i's name (and command line under it) where the label fits its slice (Data.lua's EmoteWheel_LabelPlace),
-- measured from the text as set. Remembered per text and size: the wheel lays out again on every slice the cursor
-- crosses.
local function PlaceLabel(w, name, cmd, i, count)
	local nameW, nameH = name:GetStringWidth(), name:GetStringHeight()
	local cmdW, cmdH = 0, 0
	if cmd then
		cmdW, cmdH = cmd:GetStringWidth(), cmd:GetStringHeight()
	end
	local key = ("%d:%d:%.1f:%.1f:%.1f:%.1f"):format(i, count, nameW, nameH, cmdW, cmdH)
	local spot = places[key]
	if not spot then
		local height = cmd and (nameH + LINE_GAP + cmdH) or nameH
		local nameDy = (height - nameH) / 2 -- the lines' middles, from the label's middle
		local boxes = { { nameW, nameH, nameDy } }
		if cmd then
			boxes[2] = { cmdW, cmdH, nameDy - (nameH + cmdH) / 2 - LINE_GAP }
		end
		local x, y = ns.EmoteWheel_LabelPlace(Angle(i, count), 2 * math.pi / count, boxes, LABEL_R, INNER + GAP,
			RADIUS, LABEL_ROOM, LABEL_SHIFT)
		spot = { x, y, nameDy, boxes[2] and boxes[2][3] }
		places[key] = spot
	end
	name:ClearAllPoints()
	name:SetPoint("CENTER", w, "CENTER", spot[1], spot[2] + spot[3])
	if cmd then
		cmd:ClearAllPoints()
		cmd:SetPoint("CENTER", w, "CENTER", spot[1], spot[2] + spot[4])
	end
end

-- slices: from ns.EmoteWheel_Slices; opts: { showCommand, showTarget, target (name or nil), hover (the editor: a slice
-- under the mouse), emptyLabel }; picked: slice index or nil.
local function Layout(w, slices, opts, picked)
	Colorize(w)
	local count = math.max(#slices, ns.EMOTEWHEEL_MIN)
	local step = 2 * math.pi / count
	local small = count > 8
	local nameWidth = math.min(118, 2 * LABEL_R * math.sin(step / 2) + 10)
	local hr, hg, hb = Mixed("accent", "bg", HIGHLIGHT_MIX)
	local vr, vg, vb = Mixed("accent", "bg", HOVER_MIX)
	for i = 1, ns.EMOTEWHEEL_MAX do
		local tex, name, cmd = w.slices[i], w.names[i], w.cmds[i]
		if i > count then
			tex:Hide()
			name:Hide()
			cmd:Hide()
		else
			local slice = slices[i]
			local on = picked == i
			local blank = slice ~= nil and slice.text == ""
			Turn(tex, count, i)
			if on then
				tex:SetVertexColor(hr, hg, hb, SLICE_ALPHA)
			elseif opts.hover == i then
				tex:SetVertexColor(vr, vg, vb, slice and SLICE_ALPHA or EMPTY_ALPHA)
			else
				Paint(tex, "bg", slice and SLICE_ALPHA or EMPTY_ALPHA)
			end
			tex:Show()

			local withCmd = opts.showCommand and slice ~= nil and not blank
			UI.SetFont(name, "title", small and 13 or 15)
			name:SetWidth(nameWidth)
			name:SetText(slice and Name(slice, opts) or "")
			UI.SetTextRole(name, on and "accent" or blank and "textFaint" or "text")
			name:Show()
			cmd:SetWidth(nameWidth)
			cmd:SetText(withCmd and ns.EmoteWheel_Short(Shown(slice.text, opts.target), small and 12 or 15) or "")
			UI.SetTextRole(cmd, on and "accent" or "textMuted", on and 0.85 or nil)
			cmd:SetShown(withCmd)
			PlaceLabel(w, name, withCmd and cmd or nil, i, count)
		end
	end
	local slice = picked and slices[picked]
	if slice then
		w.arc:SetTexture(ART .. "Arc" .. count)
		w.arc:SetRotation(-Angle(picked, count))
	end
	w.arc:SetShown(slice ~= nil)
	local lines = {}
	if slice then
		w.title:SetText(Name(slice, opts))
		UI.SetTextRole(w.title, slice.text == "" and "textFaint" or "accent")
		if opts.showCommand and slice.text ~= "" then
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

-- The slice of a wheel drawn into host (EmoteWheel_Draw) under the cursor, empty slots of a short wheel too: 1 to
-- max(count, minimum), or nil over the middle or off the ring.
function ns.EmoteWheel_SliceUnder(host, count)
	local w = host.wheel
	if not w then
		return nil
	end
	local x, y = GetCursorPosition()
	local scale = w:GetEffectiveScale()
	local cx, cy = w:GetCenter()
	local dx, dy = x / scale - cx, y / scale - cy
	if dx * dx + dy * dy > RADIUS * RADIUS then
		return nil
	end
	return ns.EmoteWheel_SliceAt(dx, dy, math.max(count, ns.EMOTEWHEEL_MIN), INNER)
end
