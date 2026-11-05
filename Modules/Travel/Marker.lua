local addonName, ns = ...

-- Waypoints: the frames. A full-screen holder (on UIParent, or on WorldFrame so it survives Alt+Z) with four
-- views that Waypoint.lua switches between: the far marker (diamond, beam, footer), the close-up card, the
-- edge arrow and the compass (the edge arrow over your head, turning with you, with the footer). Drawn from color textures in the theme's colors; only the target's own icon is an atlas or
-- texture. Positions come in as screen pixels (UIParent-independent), so the views convert by their own scale.
-- The settings previews draw a still sample with the same view builders (WayMarker_DrawSample, at the bottom).

local UI = ns.UI

local DIAMOND = 32 -- outer diamond side before rotation
local ICON = 22
local BEAM_H = 300
local CARD_W = 300
local CARD_COMPACT_W = 220
local CARD_ICON = 32
local CARD_COMPACT_ICON = 20
local CARD_LINES = 3
-- Card height with text lines: top padding, the name line, the gap above the lines, the lines, bottom padding.
local CARD_PAD_TOP, CARD_NAME_H, CARD_LINES_GAP, CARD_PAD_BOTTOM = 8, 18, 4, 10
local CARD_TIMER_H = 14 -- the countdown line of a timed target, along the card's bottom
local ARROW_R = 34 -- chevron tip distance from the arrow's center
local ARROW_ARM = 16
local EDGE_RX, EDGE_RY = 0.4, 0.36 -- edge ellipse radii as a share of the screen size
local COMPASS_Y = 0.22 -- compass height above the screen center, as a share of the screen height (over your head)

-- The settings preview's made-up target (WayMarker_DrawSample).
local SAMPLE_NAME = "Mira's Rest"
local SAMPLE_ICON = { atlas = "Waypoint-MapPin-Tracked" } -- a map pin's icon, as Target.lua shows it
local SAMPLE_FAR_YARDS = 600 -- the distance where the marker shows at its set size (WAY_SCALE_DISTANCE)
local SAMPLE_CARD_YARDS = 80
local SAMPLE_ARRIVAL = 38 -- seconds
local SAMPLE_TIME = "12:30" -- the countdown of a timed target
local SAMPLE_BEAM = 110 -- how much of the beam shows over the diamond's center (the real one is BEAM_H tall)
local SAMPLE_ARROW_ANGLE = math.pi / 4 -- up and to the right
local SAMPLE_TARGET = {
	name = "Kesha's Lost Satchel",
	icon = SAMPLE_ICON,
	lines = { "Find the satchel by the old well: 0/1" },
	endsAt = 0, -- timed: only whether it's set matters to the card
}

local holder, far, card, arrow
local db
local view -- "far" | "card" | "offscreen" | nil
local arrowAngle

local function Shadowed(fs)
	fs:SetShadowOffset(1, -1)
	fs:SetShadowColor(0, 0, 0, 1)
	return fs
end

-- icon: { atlas = name } or { texture = fileID/path, coords = { l, r, t, b } } or nil.
local function SetIcon(tex, icon)
	if icon and icon.atlas then
		tex:SetAtlas(icon.atlas)
		tex:Show()
	elseif icon and icon.texture then
		tex:SetTexture(icon.texture)
		if icon.coords then
			tex:SetTexCoord(unpack(icon.coords))
		else
			tex:SetTexCoord(0, 1, 0, 1)
		end
		tex:Show()
	else
		tex:Hide()
	end
end

local function Diamond(parent, size, layer)
	local outer = parent:CreateTexture(nil, layer or "BORDER")
	outer:SetColorTexture(UI.Color("accent"))
	outer:SetSize(size, size)
	outer:SetRotation(math.pi / 4)
	local inner = parent:CreateTexture(nil, "ARTWORK", nil, -1)
	inner:SetColorTexture(UI.RGBA("bg", 0.92))
	inner:SetSize(size - 4, size - 4)
	inner:SetRotation(math.pi / 4)
	inner:SetPoint("CENTER", outer)
	return outer, inner
end

-- Far view: diamond with the icon, a beam rising from it and the footer under it. The frame's center is the target.
-- The views are built into any parent (the holder, or a settings preview's frame) and returned.
local function CreateFar(parent)
	local far = CreateFrame("Frame", nil, parent)
	far:SetSize(DIAMOND * 1.5, DIAMOND * 1.5)
	far.diamond = Diamond(far, DIAMOND)
	far.diamond:SetPoint("CENTER")
	far.icon = far:CreateTexture(nil, "OVERLAY")
	far.icon:SetSize(ICON, ICON)
	far.icon:SetPoint("CENTER")

	-- Beam: a bright core and a soft glow, both fading out toward the top. Textures on `far` itself in BACKGROUND,
	-- starting at the diamond's center, so the diamond (BORDER and up) covers their base.
	local solid, clear = UI.ColorObject("accent", 0.9), UI.ColorObject("accent", 0)
	local glow = far:CreateTexture(nil, "BACKGROUND", nil, -1)
	glow:SetColorTexture(1, 1, 1, 1)
	glow:SetSize(20, BEAM_H)
	glow:SetPoint("BOTTOM", far, "CENTER")
	glow:SetGradient("VERTICAL", UI.ColorObject("accent", 0.18), clear)
	local core = far:CreateTexture(nil, "BACKGROUND", nil, 1)
	core:SetColorTexture(1, 1, 1, 1)
	core:SetSize(3, BEAM_H)
	core:SetPoint("BOTTOM", far, "CENTER")
	core:SetGradient("VERTICAL", solid, clear) -- VERTICAL: first color is the bottom
	far.beam = { glow, core }

	far.footer = Shadowed(UI.Text(far, 15, "text"))
	far.footer:SetJustifyH("CENTER")
	far.footer:SetPoint("TOP", far, "CENTER", 0, -DIAMOND * 0.85)
	far.footer:SetWidth(320)
	far.footer:SetSpacing(2)
	far:Hide()
	return far
end

-- Card view: a small themed panel, anchored so its bottom-center diamond sits on the target.
local function CreateCard(parent)
	local card = CreateFrame("Frame", nil, parent)
	card:SetSize(CARD_W, 60)
	UI.Panel(card, { alpha = 0.88, subtle = true })
	card.accent = card:CreateTexture(nil, "ARTWORK")
	card.accent:SetColorTexture(UI.Color("accent"))
	card.accent:SetPoint("TOPLEFT", 1, -1)
	card.accent:SetPoint("BOTTOMLEFT", 1, 1)
	card.accent:SetWidth(2)

	card.icon = card:CreateTexture(nil, "ARTWORK")
	card.icon:SetSize(CARD_ICON, CARD_ICON)
	card.icon:SetPoint("TOPLEFT", 10, -8)
	card.distance = Shadowed(UI.Text(card, 13, "textMuted", "number"))
	card.distance:SetJustifyH("RIGHT")
	card.distance:SetPoint("TOPRIGHT", -8, -10)
	card.name = Shadowed(UI.Text(card, 16, "heading"))
	card.name:SetPoint("RIGHT", card.distance, "LEFT", -6, 0)
	card.name:SetWordWrap(false)
	card.lines = Shadowed(UI.Text(card, 13, "text"))
	card.lines:SetPoint("TOPLEFT", card.name, "BOTTOMLEFT", 0, -CARD_LINES_GAP)
	card.lines:SetWidth(CARD_W - (10 + CARD_ICON + 8) - 8) -- explicit: the height is measured before the card is placed
	card.lines:SetSpacing(2)
	card.lines:SetJustifyV("TOP")
	-- Countdown of a timed target (world quest, event): lined up with the name, along the bottom (placed in SetTarget).
	card.timer = Shadowed(UI.Text(card, 12, "textMuted", "number"))
	card.timer:Hide()

	card.pin = Diamond(card, 10, "OVERLAY")
	card.pin:SetPoint("CENTER", card, "BOTTOM", 0, -10)
	card:Hide()
	return card
end

-- Edge arrow: the icon in a small diamond and an accent chevron that orbits it, pointing at the target.
local function CreateArrow(parent)
	local arrow = CreateFrame("Frame", nil, parent)
	arrow:SetSize(ARROW_R * 2 + ARROW_ARM, ARROW_R * 2 + ARROW_ARM)
	arrow.diamond = Diamond(arrow, DIAMOND - 4)
	arrow.diamond:SetPoint("CENTER")
	arrow.icon = arrow:CreateTexture(nil, "OVERLAY")
	arrow.icon:SetSize(ICON - 2, ICON - 2)
	arrow.icon:SetPoint("CENTER")
	arrow.arms = {}
	for i = 1, 2 do
		local arm = arrow:CreateTexture(nil, "OVERLAY")
		arm:SetColorTexture(UI.Color("accent"))
		arm:SetSize(4, ARROW_ARM)
		arrow.arms[i] = arm
	end
	-- Compass only: the footer under the arrow.
	arrow.label = Shadowed(UI.Text(arrow, 15, "text"))
	arrow.label:SetJustifyH("CENTER")
	arrow.label:SetPoint("TOP", arrow, "BOTTOM", 0, -2)
	arrow.label:SetWidth(320)
	arrow.label:SetSpacing(2)
	arrow.label:Hide()
	arrow:Hide()
	return arrow
end

-- Chevron for a direction (radians, 0 = right): the tip at ARROW_R, each arm angled back from it.
local function PointArrow(arrow, angle)
	local tipX, tipY = ARROW_R * math.cos(angle), ARROW_R * math.sin(angle)
	for i, arm in ipairs(arrow.arms) do
		local armAngle = angle + (i == 1 and 0.75 or -0.75) * math.pi
		local half = ARROW_ARM / 2 - 1
		arm:ClearAllPoints()
		arm:SetPoint("CENTER", arrow, "CENTER", tipX + half * math.cos(armAngle), tipY + half * math.sin(armAngle))
		arm:SetRotation(armAngle - math.pi / 2)
	end
end

local function Build()
	holder = CreateFrame("Frame")
	-- The bottom of the UI: the marker stands in for something in the world, so every window draws over it.
	holder:SetFrameStrata("BACKGROUND")
	holder:SetFrameLevel(1)
	far = CreateFar(holder)
	card = CreateCard(holder)
	arrow = CreateArrow(holder)
end

-- The look settings (saved, or a settings preview's) on a set of views; any of far, card, arrow may be nil.
local function ApplyLook(s, far, card, arrow)
	if far then
		for _, tex in ipairs(far.beam) do
			tex:SetShown(s.beam)
			tex:SetAlpha(s.beamAlpha)
		end
	end
	if arrow then
		arrow:SetScale(s.arrowScale)
	end
	if card then
		local compact = s.style == "minimal"
		card:SetWidth(compact and CARD_COMPACT_W or CARD_W)
		card.lines:SetShown(not compact)
		card.icon:SetSize(compact and CARD_COMPACT_ICON or CARD_ICON, compact and CARD_COMPACT_ICON or CARD_ICON)
		card.compact = compact
	end
end

-- The card's name, lines, countdown room and height for a target; countdown: the Countdown setting.
local function FillCard(card, target, countdown)
	SetIcon(card.icon, target.icon)
	card.name:SetText(target.name or "")
	card.name:ClearAllPoints()
	card.name:SetPoint("RIGHT", card.distance, "LEFT", -6, 0)
	local nameX = 10
	if card.icon:IsShown() then
		card.name:SetPoint("TOPLEFT", card.icon, "TOPRIGHT", 8, card.compact and -1 or 0)
		nameX = 10 + card.icon:GetWidth() + 8
	else
		card.name:SetPoint("TOPLEFT", 10, -8)
	end
	card.timer:ClearAllPoints()
	card.timer:SetPoint("BOTTOMLEFT", card, "BOTTOMLEFT", nameX, 6)
	local lines = {}
	for i = 1, math.min(#(target.lines or {}), CARD_LINES) do
		lines[i] = target.lines[i]
	end
	card.lines:SetText(table.concat(lines, "\n"))
	-- A timed target keeps a line free for the countdown; a full card without text lines has room for it already.
	local timed = target.endsAt ~= nil and countdown
	card.timer:SetShown(timed)
	card.lastTime = nil
	if card.compact then
		card:SetHeight(CARD_COMPACT_ICON + 16 + (timed and CARD_TIMER_H or 0))
	elseif #lines == 0 then
		card:SetHeight(CARD_ICON + 16)
	else
		card:SetHeight(math.max(CARD_ICON + 16, CARD_PAD_TOP + CARD_NAME_H + CARD_LINES_GAP + card.lines:GetStringHeight()
			+ CARD_PAD_BOTTOM + (timed and CARD_TIMER_H or 0)))
	end
end

-- Screen pixels (bottom-left origin) -> offset for a view anchored to the holder's bottom-left.
local function Place(frame, point, sx, sy)
	local scale = frame:GetEffectiveScale()
	frame:ClearAllPoints()
	frame:SetPoint(point, holder, "BOTTOMLEFT", sx / scale, sy / scale)
end

function ns.WayMarker_Apply(saved)
	db = saved
	if not holder then
		Build()
	end
	local parent = db.showWhenHidden and WorldFrame or UIParent
	holder:SetParent(parent)
	holder:SetAllPoints(parent)
	-- Again after SetParent, which can carry the new parent's strata over.
	holder:SetFrameStrata("BACKGROUND")
	-- On WorldFrame, match UIParent's scale so sizes don't jump when the option changes.
	holder:SetScale(parent == WorldFrame and UIParent:GetEffectiveScale() / WorldFrame:GetEffectiveScale() or 1)
	ApplyLook(db, far, card, arrow)
end

-- target: { name, icon, lines = { "text", ... }, endsAt } from Target.lua.
function ns.WayMarker_SetTarget(target)
	if not holder then
		return
	end
	SetIcon(far.icon, target.icon)
	SetIcon(arrow.icon, target.icon)
	FillCard(card, target, db.countdown)
end

function ns.WayMarker_SetAlpha(alpha)
	holder:SetAlpha(alpha)
end

local anchoredTo -- the navigation frame the far and card views are anchored to (AnchorTo below)

function ns.WayMarker_Hide()
	if holder then
		anchoredTo = nil -- a new navigation frame may come with the next target
		far:Hide()
		card:Hide()
		arrow:Hide()
	end
	view = nil
end

-- The navigation frame's center in screen pixels, or nil.
function ns.WayMarker_NavPoint(navFrame)
	local x, y = navFrame:GetCenter()
	if not x then
		return nil
	end
	-- GetFrame is typed ScriptRegion; Blizzard treats its coordinates as UIParent-scaled.
	local scale = navFrame.GetEffectiveScale and navFrame:GetEffectiveScale() or UIParent:GetEffectiveScale()
	return x * scale, y * scale
end

-- Far and card views are anchored straight to Blizzard's navigation frame, so the layout engine keeps them on it
-- in the same frame the engine moves it (reading GetCenter and copying it lags a frame behind camera turns).
-- Re-anchored only when the navigation frame changes.
local function AnchorTo(navFrame)
	if anchoredTo == navFrame then
		return
	end
	anchoredTo = navFrame
	far:ClearAllPoints()
	far:SetPoint("CENTER", navFrame, "CENTER")
	card:ClearAllPoints()
	card:SetPoint("BOTTOM", navFrame, "CENTER", 0, 10) -- the pin diamond sits 10 below the card
end

-- Shows one view. state: "far" | "card" | "offscreen"; sx, sy: target in screen pixels (for the edge arrow);
-- footer/distance text; scale: distance scale for the far view; timeText and timeRole: the card's countdown.
function ns.WayMarker_Show(state, navFrame, sx, sy, footer, distanceText, scale, timeText, timeRole)
	AnchorTo(navFrame)
	if state ~= view then
		far:SetShown(state == "far")
		card:SetShown(state == "card")
		arrow:SetShown(state == "offscreen")
		arrow.label:Hide()
		if state == "offscreen" and view ~= "offscreen" then
			arrowAngle = nil -- snap to the first direction instead of sweeping in from the last one
		end
		view = state
	end
	if state == "far" then
		local s = db.scale * scale
		if far.lastScale ~= s then
			far.lastScale = s
			far:SetScale(s)
		end
		if far.lastFooter ~= footer then
			far.lastFooter = footer
			far.footer:SetText(footer or "")
		end
	elseif state == "card" then
		if card.lastScale ~= db.scale then
			card.lastScale = db.scale
			card:SetScale(db.scale)
		end
		if card.lastDistance ~= distanceText then
			card.lastDistance = distanceText
			card.distance:SetText(distanceText or "")
		end
		if card.lastTime ~= timeText then
			card.lastTime = timeText
			card.timer:SetText(timeText or "")
			UI.SetTextRole(card.timer, timeRole or "textMuted")
		end
	elseif state == "offscreen" then
		local w, h = holder:GetSize()
		local hs = holder:GetEffectiveScale()
		w, h = w * hs, h * hs
		local cx, cy = w / 2, h / 2
		local ex, ey, rotation = ns.Way_EdgePoint(sx - cx, sy - cy, w * EDGE_RX, h * EDGE_RY)
		local target = rotation + math.pi / 2
		arrowAngle = arrowAngle and ns.Way_TurnToward(arrowAngle, target, 0.3) or target
		PointArrow(arrow, arrowAngle)
		Place(arrow, "CENTER", cx + ex, cy + ey)
	end
end

-- Compass view: the edge arrow over your head, pointing at angle (radians, 0 = right, up = ahead; Way_Compass),
-- with the footer under it. Needs no navigation frame.
function ns.WayMarker_ShowCompass(angle, footer)
	if view ~= "compass" then
		far:Hide()
		card:Hide()
		arrow:Show()
		arrow.label:Show()
		arrowAngle = nil
		view = "compass"
	end
	if arrow.lastFooter ~= footer then
		arrow.lastFooter = footer
		arrow.label:SetText(footer or "")
	end
	arrowAngle = arrowAngle and ns.Way_TurnToward(arrowAngle, angle, 0.3) or angle
	PointArrow(arrow, arrowAngle)
	local w, h = holder:GetSize()
	local hs = holder:GetEffectiveScale()
	Place(arrow, "CENTER", w * hs / 2, h * hs * (0.5 + COMPASS_Y))
end

-- Settings preview ---------------------------------------------------------------------------------------------

-- A still sample of the views for a settings preview (Panel/Preview.lua), drawn into host by the same code as the
-- real marker. s: the look settings (style, scale, alpha, beam, beamAlpha, footer, metric, countdown, arrowScale);
-- parts: "far" (the marker), "card", "both" (marker over card) or "arrow". Returns the width and height drawn.
function ns.WayMarker_DrawSample(host, s, parts)
	local v = host.waySample
	if not v then
		v = { root = CreateFrame("Frame", nil, host) }
		v.root:SetAllPoints(host)
		v.root:SetClipsChildren(true) -- the beam is cut off where the sample ends, it fades out upward anyway
		v.far, v.card, v.arrow = CreateFar(v.root), CreateCard(v.root), CreateArrow(v.root)
		host.waySample = v
	end
	local far, card, arrow = v.far, v.card, v.arrow
	ApplyLook(s, far, card, arrow)
	v.root:SetAlpha(s.alpha) -- the real marker's opacity is on the holder
	local timeText = s.countdown and UI.Wrap(SAMPLE_TIME, "warning") or nil
	local showFar = parts == "far" or parts == "both"
	local showCard = parts == "card" or parts == "both"
	far:SetShown(showFar)
	card:SetShown(showCard)
	arrow:SetShown(parts == "arrow")

	if parts == "arrow" then
		SetIcon(arrow.icon, SAMPLE_ICON)
		PointArrow(arrow, SAMPLE_ARROW_ANGLE)
		local side = arrow:GetWidth() * s.arrowScale
		arrow:ClearAllPoints()
		arrow:SetPoint("CENTER", v.root, "TOPLEFT", side / 2 / s.arrowScale, -side / 2 / s.arrowScale)
		return side, side
	end

	local width, height = 0, 0
	if showFar then
		-- At SAMPLE_FAR_YARDS the distance scale is 1, so the marker shows at the Marker size setting.
		local fs = s.scale * ns.Way_DistanceScale(SAMPLE_FAR_YARDS)
		far:SetScale(fs)
		SetIcon(far.icon, SAMPLE_ICON)
		local footer = ns.Way_FooterText(s.footer, ns.Way_FormatDistance(SAMPLE_FAR_YARDS, s.metric),
			ns.Way_FormatArrival(SAMPLE_ARRIVAL), SAMPLE_NAME, timeText)
		far.footer:SetText(footer or "")
		local above = s.beam and SAMPLE_BEAM or DIAMOND * 0.75 * fs
		local below = DIAMOND * 0.85 * fs + (footer and far.footer:GetStringHeight() * fs or 0)
		-- Both views hang from the sample's top center; the margin keeps the footer's shadow inside the clip.
		width = (math.max(DIAMOND * 1.5, footer and far.footer:GetStringWidth() or 0) + 16) * fs
		height = above + below + 4
		far:ClearAllPoints()
		far:SetPoint("CENTER", v.root, "TOP", 0, -above / fs)
	end
	if showCard then
		local cs = s.scale
		card:SetScale(cs)
		card.distance:SetText(ns.Way_FormatDistance(SAMPLE_CARD_YARDS, s.metric))
		FillCard(card, SAMPLE_TARGET, s.countdown)
		card.timer:SetText(timeText or "")
		local gap = showFar and 8 or 0
		local w = card:GetWidth() * cs
		-- The pin diamond hangs 10 below the card (rotated: about 7 more).
		card:ClearAllPoints()
		card:SetPoint("TOP", v.root, "TOP", 0, -(height + gap) / cs)
		height = height + gap + (card:GetHeight() + 17) * cs
		width = math.max(width, w)
	end
	return width, height
end
