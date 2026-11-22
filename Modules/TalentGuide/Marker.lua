local addonName, ns = ...

-- Talent guide: the marks on the talent window. The next talent of the build glows with a "Next" tag; talents with
-- points the order doesn't give them yet get an amber border, talents off the build a red one; a line under the trees
-- names the build and the step, and a Builds button opens the build menu (TalentGuide.lua fills it). Our own frames,
-- anchored to Blizzard's talent buttons (never parented to them or changing them). Registered in TalentGuide.lua,
-- which refreshes this on the talent window's events.

local GLOW_OUT = 6 -- pixels the glow reaches past the talent button
local GLOW_LOW = 0.35 -- the glow's lowest alpha in its pulse
local GLOW_PULSE = 0.8 -- seconds per half pulse
local WAIT_GLOW = 0.6 -- alpha of the steady glow on the next talent while no point can go in yet
local BORDER_OUT = 2 -- pixels the early / off-build border sits outside the button
local STATUS_Y = 14 -- pixels the status line sits above the talent window's bottom edge
local BUTTON_X, BUTTON_Y = -24, 9 -- the Builds button from the window's bottom right
local ALERT_Y = 8 -- pixels between Apply Changes and the warning line above it
local PLATE_PAD = 8 -- pixels the warning's dark plate reaches past its text
local UI = ns.UI

local module -- set by ns.TalentGuideMarker_Init
local nextMark, status, menuButton
local borders = {}

local function TalentsFrame()
	return PlayerSpellsFrame and PlayerSpellsFrame.TalentsFrame
end

local function NewNextMark(parent)
	local mark = CreateFrame("Frame", nil, parent)
	mark.glow = mark:CreateTexture(nil, "OVERLAY")
	mark.glow:SetAtlas("bags-glow-white")
	mark.glow:SetPoint("TOPLEFT", -GLOW_OUT, GLOW_OUT)
	mark.glow:SetPoint("BOTTOMRIGHT", GLOW_OUT, -GLOW_OUT)
	mark.glow:SetBlendMode("ADD")
	mark.tag = UI.Text(mark, 11, "accent", "label")
	mark.tag:SetPoint("BOTTOM", mark, "TOP", 0, GLOW_OUT)
	mark.tag:SetText("Next")
	mark.pulse = mark.glow:CreateAnimationGroup() -- only the glow pulses, the tag stays readable
	mark.pulse:SetLooping("BOUNCE")
	local fade = mark.pulse:CreateAnimation("Alpha")
	fade:SetFromAlpha(1)
	fade:SetToAlpha(GLOW_LOW)
	fade:SetDuration(GLOW_PULSE)
	mark:Hide()
	return mark
end

local function NewBorder(parent)
	local mark = CreateFrame("Frame", nil, parent)
	UI.Border(mark, "danger")
	mark:Hide()
	return mark
end

local function Place(mark, button, out)
	mark:ClearAllPoints()
	mark:SetPoint("TOPLEFT", button, "TOPLEFT", -out, out)
	mark:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", out, -out)
	mark:SetFrameStrata(button:GetFrameStrata())
	mark:SetFrameLevel(button:GetFrameLevel() + 10)
	mark:Show()
end

local function Build(frame)
	nextMark = NewNextMark(frame)
	status = CreateFrame("Frame", nil, frame)
	status:SetSize(1, 1)
	status.text = UI.Text(status, 12, "text")
	status.text:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 24, STATUS_Y)
	status.text:SetPoint("RIGHT", frame, "CENTER", -110, 0) -- clear of the Apply Changes button
	status.text:SetJustifyH("LEFT")
	status.text:SetWordWrap(false)
	menuButton = UI.Button(frame, 80, "Builds")
	menuButton:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", BUTTON_X, BUTTON_Y)
	menuButton:SetScript("OnClick", function(self)
		UI.ContextMenu(self, function(_, root)
			ns.TalentGuide_FillMenu(root)
		end)
	end)
	UI.FitButton(menuButton, 80, 24)
	-- Points that went astray: centered just above Apply Changes, where the eye goes before applying, on a dark plate
	-- so it reads over the tree art.
	local apply = frame.ApplyButton
	status.alert = UI.Text(status, 13, "text")
	if apply then
		status.alert:SetPoint("BOTTOM", apply, "TOP", 0, ALERT_Y)
	else
		status.alert:SetPoint("BOTTOM", frame, "BOTTOM", 0, STATUS_Y + 30)
	end
	status.alert:SetJustifyH("CENTER")
	status.alert:SetWordWrap(false)
	status.plate = status:CreateTexture(nil, "BACKGROUND")
	status.plate:SetPoint("TOPLEFT", status.alert, "TOPLEFT", -PLATE_PAD, PLATE_PAD / 2)
	status.plate:SetPoint("BOTTOMRIGHT", status.alert, "BOTTOMRIGHT", PLATE_PAD, -PLATE_PAD / 2)
end

local function HideMarks()
	if nextMark then
		nextMark.pulse:Stop()
		nextMark:Hide()
	end
	for _, mark in ipairs(borders) do
		mark:Hide()
	end
end

function ns.TalentGuideMarker_Hide()
	HideMarks()
	if status then
		status:Hide()
		menuButton:Hide()
	end
end

local function Count(set)
	local n = 0
	for _ in pairs(set) do
		n = n + 1
	end
	return n
end

-- Points that went astray: "1 talent ahead of the order  -  1 talent off the build", or "".
local function AlertText(view)
	if not view then
		return ""
	end
	local parts = {}
	local early, off = Count(view.early), Count(view.off)
	if early > 0 then
		parts[#parts + 1] = UI.Wrap(early == 1 and "1 talent ahead of the order"
			or (early .. " talents ahead of the order"), "warning")
	end
	if off > 0 then
		parts[#parts + 1] = UI.Wrap(off == 1 and "1 talent off the build" or (off .. " talents off the build"), "danger")
	end
	return table.concat(parts, "  -  ")
end

-- The status line: the build's name and where you are in it.
local function StatusText(view)
	if not view then
		return ns.TalentGuide_Following() and UI.Wrap("Talent guide: your build doesn't fit this talent tree.", "warning")
			or "Talent guide: no build. Press Builds to paste one."
	end
	-- The name without its note ("Frost 18/0/33", not "... (recommended)"): the line has room up to Apply Changes.
	local name = UI.Wrap((view.name:gsub("%s*%b()$", "")), "accent")
	local text
	if view.nextStep then
		local step = view.nextStep
		text = ("Talent guide: %s  -  step %d/%d: %s (%d/%d), level %d"):format(name, step.step, #view.build.order,
			view.nextName or "?", step.rank, view.nextMax or step.rank, step.level)
	elseif view.build.order then
		text = ("Talent guide: %s  -  %s"):format(name, UI.Wrap("done", "success"))
	else
		text = ("Talent guide: %s  -  %d of %d points (no point order: every unfinished talent is marked)")
			:format(name, view.done, view.build.points)
	end
	return text
end

-- Draws the marks for the talent window as it is now; hides them when there's nothing to show.
function ns.TalentGuideMarker_Refresh()
	local frame = TalentsFrame()
	if not (module and module.active and frame and frame:IsVisible()) or (frame.IsInspecting and frame:IsInspecting())
		or not frame.GetConfigID then
		ns.TalentGuideMarker_Hide()
		return
	end
	if not nextMark then
		Build(frame)
	end
	HideMarks()
	local view = ns.TalentGuide_View(frame:GetConfigID())
	menuButton:SetFrameLevel(frame:GetFrameLevel() + 20)
	menuButton:Show()
	status:SetFrameLevel(frame:GetFrameLevel() + 20)
	status.text:SetTextColor(UI.RGBA("text"))
	status.text:SetText(StatusText(view))
	status.alert:SetTextColor(UI.RGBA("text"))
	local alert = view and view.marks and view.offMarks and AlertText(view) or ""
	status.alert:SetText(alert)
	status.plate:SetColorTexture(UI.RGBA("bg", 0.8))
	status.plate:SetShown(alert ~= "")
	status:Show()
	if not view or not view.marks then
		return
	end

	local glowNodes = {}
	if view.nextStep then
		glowNodes[1] = view.nextStep.nodeID
	elseif not view.build.order then
		glowNodes = view.missing
	end
	local used = 0
	local function Mark(nodeID, role)
		local button = frame:GetTalentButtonByNodeID(nodeID)
		if not button then
			return
		end
		used = used + 1
		borders[used] = borders[used] or NewBorder(frame)
		UI.SetBorderColor(borders[used], role)
		Place(borders[used], button, BORDER_OUT)
	end

	-- The next talent: a pulsing glow and "Next" when a point can go in now; with no point to spend, only a quiet
	-- border and the level it comes at, so "take this" and "this comes next" look different. A build without an
	-- order has no next talent: the first unfinished one glows untagged and the rest get an accent border (below).
	local first = glowNodes[1] and frame:GetTalentButtonByNodeID(glowNodes[1])
	local waiting = view.nextStep and not view.canBuy
	if first and waiting then
		-- A steady, softer glow in the info color: clearly marked, but not the pulsing gold of "take this now".
		Mark(glowNodes[1], "info")
		Place(nextMark, first, 0)
		nextMark.glow:Show()
		nextMark.glow:SetVertexColor(UI.RGBA("info", WAIT_GLOW))
		nextMark.tag:SetText(("Level %d"):format(view.nextStep.level))
		nextMark.tag:SetTextColor(UI.RGBA("info"))
		nextMark.tag:Show()
	elseif first then
		Place(nextMark, first, 0)
		nextMark.glow:Show()
		nextMark.glow:SetVertexColor(UI.RGBA("accent"))
		nextMark.tag:SetText("Next")
		nextMark.tag:SetTextColor(UI.RGBA("accent"))
		nextMark.tag:SetShown(view.nextStep ~= nil)
		nextMark.pulse:Play()
	end

	for i = 2, #glowNodes do
		Mark(glowNodes[i], "accent")
	end
	if view.offMarks then
		for nodeID in pairs(view.early) do
			Mark(nodeID, "warning")
		end
		for nodeID in pairs(view.off) do
			Mark(nodeID, "danger")
		end
	end
end

function ns.TalentGuideMarker_Init(owner)
	module = owner
end
