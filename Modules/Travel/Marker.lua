local addonName, ns = ...

-- Waypoints: the frames. A full-screen holder (on UIParent, or on WorldFrame so it survives Alt+Z) with three
-- views that Waypoint.lua switches between: the far marker (diamond, beam, footer), the close-up card and the
-- edge arrow. Drawn from color textures in the theme's colors; only the target's own icon is an atlas or
-- texture. Positions come in as screen pixels (UIParent-independent), so the views convert by their own scale.

local UI = ns.UI

local DIAMOND = 32 -- outer diamond side before rotation
local ICON = 22
local BEAM_H = 300
local CARD_W = 300
local CARD_COMPACT_W = 220
local CARD_ICON = 32
local CARD_COMPACT_ICON = 20
local CARD_LINES = 3
local ARROW_R = 34 -- chevron tip distance from the arrow's center
local ARROW_ARM = 16
local EDGE_RX, EDGE_RY = 0.4, 0.36 -- edge ellipse radii as a share of the screen size

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
local function CreateFar()
	far = CreateFrame("Frame", nil, holder)
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
end

-- Card view: a small themed panel, anchored so its bottom-center diamond sits on the target.
local function CreateCard()
	card = CreateFrame("Frame", nil, holder)
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
	card.lines:SetPoint("TOPLEFT", card.name, "BOTTOMLEFT", 0, -4)
	card.lines:SetWidth(CARD_W - (10 + CARD_ICON + 8) - 8) -- explicit: the height is measured before the card is placed
	card.lines:SetSpacing(2)
	card.lines:SetJustifyV("TOP")

	card.pin = Diamond(card, 10, "OVERLAY")
	card.pin:SetPoint("CENTER", card, "BOTTOM", 0, -10)
	card:Hide()
end

-- Edge arrow: the icon in a small diamond and an accent chevron that orbits it, pointing at the target.
local function CreateArrow()
	arrow = CreateFrame("Frame", nil, holder)
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
	arrow:Hide()
end

-- Chevron for a direction (radians, 0 = right): the tip at ARROW_R, each arm angled back from it.
local function PointArrow(angle)
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
	holder:SetFrameStrata("BACKGROUND")
	holder:SetFrameLevel(1)
	CreateFar()
	CreateCard()
	CreateArrow()
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
	holder:SetFrameStrata("BACKGROUND")
	-- On WorldFrame, match UIParent's scale so sizes don't jump when the option changes.
	holder:SetScale(parent == WorldFrame and UIParent:GetEffectiveScale() / WorldFrame:GetEffectiveScale() or 1)
	for _, tex in ipairs(far.beam) do
		tex:SetShown(db.beam)
		tex:SetAlpha(db.beamAlpha)
	end
	arrow:SetScale(db.arrowScale)
	local compact = db.style == "minimal"
	card:SetWidth(compact and CARD_COMPACT_W or CARD_W)
	card.lines:SetShown(not compact)
	card.icon:SetSize(compact and CARD_COMPACT_ICON or CARD_ICON, compact and CARD_COMPACT_ICON or CARD_ICON)
	card.compact = compact
end

-- target: { name, icon, lines = { "text", ... } } from Target.lua.
function ns.WayMarker_SetTarget(target)
	if not holder then
		return
	end
	SetIcon(far.icon, target.icon)
	SetIcon(card.icon, target.icon)
	SetIcon(arrow.icon, target.icon)
	card.name:SetText(target.name or "")
	card.name:ClearAllPoints()
	card.name:SetPoint("RIGHT", card.distance, "LEFT", -6, 0)
	if card.icon:IsShown() then
		card.name:SetPoint("TOPLEFT", card.icon, "TOPRIGHT", 8, card.compact and -1 or 0)
	else
		card.name:SetPoint("TOPLEFT", 10, -8)
	end
	local lines = {}
	for i = 1, math.min(#(target.lines or {}), CARD_LINES) do
		lines[i] = target.lines[i]
	end
	card.lines:SetText(table.concat(lines, "\n"))
	if card.compact or #lines == 0 then
		card:SetHeight(card.compact and CARD_COMPACT_ICON + 16 or CARD_ICON + 16)
	else
		card:SetHeight(math.max(CARD_ICON + 16, 8 + 18 + 4 + card.lines:GetStringHeight() + 10))
	end
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
-- footer/distance text; scale: distance scale for the far view.
function ns.WayMarker_Show(state, navFrame, sx, sy, footer, distanceText, scale)
	AnchorTo(navFrame)
	if state ~= view then
		far:SetShown(state == "far")
		card:SetShown(state == "card")
		arrow:SetShown(state == "offscreen")
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
	elseif state == "offscreen" then
		local w, h = holder:GetSize()
		local hs = holder:GetEffectiveScale()
		w, h = w * hs, h * hs
		local cx, cy = w / 2, h / 2
		local ex, ey, rotation = ns.Way_EdgePoint(sx - cx, sy - cy, w * EDGE_RX, h * EDGE_RY)
		local target = rotation + math.pi / 2
		arrowAngle = arrowAngle and ns.Way_TurnToward(arrowAngle, target, 0.3) or target
		PointArrow(arrowAngle)
		Place(arrow, "CENTER", cx + ex, cy + ey)
	end
end
