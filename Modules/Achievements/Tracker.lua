local addonName, ns = ...

-- Almost Done: the Top 5 tracker. A small window with pinned achievements first, then the closest ones. Click a
-- row to open it, right-click to pin or unpin. Unlocked, the whole window drags; rows whose progress went up
-- flash for a moment, their bar grows and a shine runs across them. An achievement that joins the list while it shows
-- fades in and the rows that moved glide to their new places. The minus in the corner (on hover) folds it down to its
-- title, easing (ns.EditMode_Fold in Core/EditMode.lua).

local UI = ns.UI
local ROWS = 5
local WIDTH = 260
local ROW_H = 26
local TITLE_H = 20
local ICON = 18
local TRACK_W = WIDTH - 16 - (6 + ICON + 8) -- row insets, icon and its gaps
local FLASH = 1.5 -- seconds
local DEFAULT_POINT = { "TOPRIGHT", "TOPRIGHT", -250, -250 }
local SAMPLE_ICON = 236376 -- the achievement shield (also the sample toast's)
-- The settings preview's rows before the first scan has any (the first one pinned).
local SAMPLE = {
	{ name = "Treasures of the Hollow", icon = SAMPLE_ICON, percent = 92, pinned = true },
	{ name = "Explore the Isle", icon = SAMPLE_ICON, percent = 88 },
	{ name = "Level 10", icon = SAMPLE_ICON, percent = 80 },
}

local frame
local rows = {}
local inCombat = false

local function DB()
	return ns.achDB.tracker
end

local function ShowTooltip(row)
	local entry = row.entry
	if not entry then
		return
	end
	GameTooltip:SetOwner(row, "ANCHOR_NONE")
	local x = frame:GetCenter()
	local onLeft = x and x < UIParent:GetWidth() / 2 * UIParent:GetEffectiveScale() / frame:GetEffectiveScale()
	local _, y = row:GetCenter()
	local onTop = y and y > UIParent:GetHeight() / 2 * UIParent:GetEffectiveScale() / frame:GetEffectiveScale()
	local vertical = onTop and "TOP" or "BOTTOM"
	if onLeft then
		GameTooltip:SetPoint(vertical .. "LEFT", row, vertical .. "RIGHT", 16, 0)
	else
		GameTooltip:SetPoint(vertical .. "RIGHT", row, vertical .. "LEFT", -16, 0)
	end
	GameTooltip:SetText(entry.name, UI.Color("heading"))
	GameTooltip:AddLine(ns.Ach_ProgressText(entry), 1, 1, 1)
	if entry.last then
		local r, g, b = UI.RGB("textMuted") -- unpacked: a call in mid-list gives only its first value
		GameTooltip:AddLine("Left: " .. entry.last, r, g, b, true)
	end
	if entry.reward ~= "" then
		local r, g, b = UI.RGB("success")
		GameTooltip:AddLine(entry.reward, r, g, b, true)
	end
	GameTooltip:AddLine(entry.pinned and "Right-click to unpin" or "Right-click to pin", UI.RGB("textMuted"))
	GameTooltip:Show()
end

-- A row's flash fading out. Set as OnUpdate when a flash starts, removed when it's done.
local function FlashUpdate(self, dt)
	self.flashLeft = self.flashLeft - dt
	if self.flashLeft <= 0 then
		self.flashLeft = nil
		self.flash:SetAlpha(0)
		self:SetScript("OnUpdate", nil)
	else
		self.flash:SetAlpha(0.25 * self.flashLeft / FLASH)
	end
end
local FlashUpdateTimed = ns.Perf_Wrap(FlashUpdate, "OnUpdate")

local function CreateRow(parent, i)
	local row = CreateFrame("Button", nil, parent)
	row:SetHeight(ROW_H)
	row:SetPoint("TOPLEFT", 8, -(TITLE_H + (i - 1) * ROW_H))
	row:SetPoint("RIGHT", -8, 0)
	row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	row.flash = row:CreateTexture(nil, "BACKGROUND")
	row.flash:SetAllPoints()
	row.flash:SetColorTexture(UI.Color("accent"))
	row.flash:SetAlpha(0)
	row.pin = row:CreateTexture(nil, "ARTWORK")
	row.pin:SetColorTexture(UI.Color("accent"))
	row.pin:SetPoint("TOPLEFT", 0, -3)
	row.pin:SetPoint("BOTTOMLEFT", 0, 3)
	row.pin:SetWidth(2)
	row.icon = row:CreateTexture(nil, "ARTWORK")
	row.icon:SetSize(ICON, ICON)
	row.icon:SetPoint("LEFT", 6, 0)
	row.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	row.percent = UI.Text(row, 11, "textMuted", "number")
	row.percent:SetPoint("TOPRIGHT", 0, -3)
	row.percent:SetJustifyH("RIGHT")
	row.name = UI.Text(row, 12, "text")
	row.name:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 8, 1)
	row.name:SetPoint("RIGHT", row.percent, "LEFT", -6, 0)
	row.name:SetWordWrap(false)
	row.track = row:CreateTexture(nil, "ARTWORK")
	row.track:SetColorTexture(1, 1, 1, 0.12)
	row.track:SetHeight(2)
	row.track:SetPoint("BOTTOMLEFT", row.icon, "BOTTOMRIGHT", 8, 1)
	row.track:SetPoint("RIGHT")
	row.fill = row:CreateTexture(nil, "OVERLAY")
	row.fill:SetColorTexture(UI.RGBA("accent", 0.9))
	row.fill:SetHeight(2)
	row.fill:SetPoint("LEFT", row.track, "LEFT")
	row:SetScript("OnEnter", ShowTooltip)
	row:SetScript("OnLeave", function()
		GameTooltip:Hide()
	end)
	row:SetScript("OnClick", function(self, button)
		local entry = self.entry
		if not entry then
			return
		end
		if button == "RightButton" then
			if entry.pinned then
				ns.Ach_Unpin(entry.id)
			else
				ns.Ach_Pin(entry.id)
			end
		else
			ns.Ach_Open(entry.id)
		end
	end)
	return row
end

local function FillWidth(percent)
	return math.max(TRACK_W * math.min(percent, 100) / 100, 1)
end

local function FillRow(row, entry)
	row.icon:SetTexture(entry.icon)
	row.name:SetText(entry.name)
	row.percent:SetText(("%d%%"):format(math.floor(entry.percent)))
	row.pin:SetShown(entry.pinned == true)
	UI.TweenStop(row.fill, "width") -- a row refilled mid-growth (another entry now) takes its own width at once
	row.fill:SetWidth(FillWidth(entry.percent))
end

-- A step gained, seen live: the bar grows from where it was, the percent pops and a shine runs across the row; a
-- row that reached 100% bursts.
local function Celebrate(row, from, to)
	if not row:IsVisible() then
		return
	end
	local a, b = FillWidth(from), FillWidth(to)
	row.fill:SetWidth(a)
	UI.Tween(row.fill, "width", FLASH / 2, function(e)
		row.fill:SetWidth(UI.Lerp(a, b, e))
	end)
	UI.Pop(row.percent, 0.25)
	UI.Shine(row)
	if to >= 100 then
		-- Silent: the game plays its own sound for a finished achievement.
		UI.Burst(row, row.icon, true)
	end
end

-- The tracker's look on f: the panel, the title and ROWS rows (f.rows). Shared by the real tracker and the settings
-- preview.
local function Dress(f)
	f:SetSize(WIDTH, TITLE_H + ROWS * ROW_H + 8)
	UI.Panel(f, { alpha = 0.55, subtle = true })
	f.title = UI.Text(f, 10, "textMuted", "label")
	f.title:SetPoint("TOPLEFT", 10, -6)
	f.title:SetText(ns.Spaced("Almost done"))
	f.rows = {}
	for i = 1, ROWS do
		f.rows[i] = CreateRow(f, i)
	end
end

local function SavePoint()
	DB().point = UI.TopLeftPoint(frame)
end

local function Build()
	inCombat = inCombat or InCombatLockdown() -- built mid-fight (/reload, turned on): the REGEN events already went by
	frame = CreateFrame("Frame", nil, UIParent)
	frame:SetFrameStrata("MEDIUM")
	frame:SetClampedToScreen(true)
	frame:SetMovable(true)
	frame:Hide()
	Dress(frame)
	rows = frame.rows

	-- Unlocked: a cover over the rows takes the drag (rows don't click while moving).
	local mover = CreateFrame("Frame", nil, frame)
	mover:SetAllPoints()
	mover:SetFrameLevel(frame:GetFrameLevel() + 10)
	mover:EnableMouse(true)
	mover:RegisterForDrag("LeftButton")
	mover:SetScript("OnDragStart", function()
		frame:StartMoving()
	end)
	mover:SetScript("OnDragStop", function()
		frame:StopMovingOrSizing()
		SavePoint()
	end)
	UI.Border(mover, "accent", 0.8)
	local hint = UI.Text(mover, 10, "accent")
	hint:SetPoint("TOPRIGHT", -26, -6) -- left of the collapse button
	hint:SetText("drag to move")
	frame.mover = mover

	frame.collapse = UI.CollapseButton(frame, function()
		return DB().collapsed
	end, function()
		local before = ns.EditMode_FoldStart(frame, rows)
		DB().collapsed = not DB().collapsed
		ns.AchTracker_Apply()
		ns.EditMode_Fold(frame, before, rows)
	end)
end

local function Place()
	local p = DB().point or DEFAULT_POINT
	frame:ClearAllPoints()
	frame:SetPoint(p[1], UIParent, p[2], p[3], p[4])
end

-- flashIDs: set of achievement IDs whose progress changed (their rows flash when the percent went up).
function ns.AchTracker_Refresh(flashIDs)
	if not frame then
		return
	end
	local top = ns.achModule.active and ns.Ach_Top(ROWS) or {}
	local spots = frame.spots
	for i, row in ipairs(rows) do
		local entry = top[i]
		local old = row.entry
		row.entry = entry
		row.key, row.y = entry and entry.id, (i - 1) * ROW_H
		if entry then
			FillRow(row, entry)
			if flashIDs and flashIDs[entry.id] and old and old.id == entry.id and entry.percent > old.percent then
				row.flashLeft = FLASH
				row:SetScript("OnUpdate", FlashUpdateTimed)
				Celebrate(row, old.percent, entry.percent)
			end
		end
	end
	frame.count = #top
	ns.AchTracker_Apply()
	-- Seen live (shown and open before and after): what joined fades in, what moved glides.
	if frame.spots then
		frame.spots = ns.EditMode_Reflow(rows, frame.count, spots)
	end
end

-- combat: true/false when entering/leaving combat, nil to keep the current state.
function ns.AchTracker_Apply(combat)
	if combat ~= nil then
		inCombat = combat
	end
	local db = DB()
	local active = ns.achModule.active
	if not frame then
		if not (active and db.shown) then
			return
		end
		Build()
		Place()
		ns.AchTracker_Refresh()
		return
	end
	frame:SetScale(db.scale)
	local collapsed = db.collapsed
	frame:SetHeight(collapsed and TITLE_H + 2 or TITLE_H + ROWS * ROW_H + 8)
	ns.EditMode_FoldKeep(frame)
	for i, row in ipairs(rows) do
		row:SetShown(not collapsed and i <= (frame.count or 0))
	end
	local editMode = ns.EditMode_Active()
	frame.mover:SetShown(not db.locked and not editMode)
	local hasRows = (frame.count or 0) > 0
	local show = active and db.shown and (hasRows or not db.locked or editMode)
		and not (db.hideInCombat and inCombat)
	frame:SetShown(show)
	-- Where the rows are drawn, while they show: the next Refresh glides from there. Nothing while folded or hidden,
	-- so a list that opens or shows again just appears.
	if frame:IsVisible() and not collapsed then
		frame.spots = frame.spots or ns.EditMode_Reflow(rows, frame.count or 0, nil)
	else
		frame.spots = nil
	end
end

-- The settings preview (Panel/Preview.lua): the tracker with your own top achievements, or SAMPLE before the first
-- scan, at the scale under the mouse. Drawn by Dress and FillRow like the real one.
function ns.AchTracker_DrawSample(host, get)
	local f = host.tracker
	if not f then
		f = CreateFrame("Frame", nil, host)
		f:SetPoint("TOPLEFT")
		Dress(f)
		host.tracker = f
	end
	local top = ns.achModule.active and ns.Ach_Top(ROWS) or {}
	if #top == 0 then
		top = SAMPLE
	end
	for i, row in ipairs(f.rows) do
		local entry = top[i]
		row:SetShown(entry ~= nil)
		if entry then
			FillRow(row, entry)
		end
	end
	local scale = get("tracker.scale") or 1
	f:SetScale(scale)
	return f:GetWidth() * scale, f:GetHeight() * scale
end

ns.EditMode_Register({
	name = "Almost Done",
	frame = function()
		return frame
	end,
	refresh = function()
		ns.AchTracker_Apply()
	end,
	saved = SavePoint,
	module = "ach",
	options = { "tracker.scale", "tracker.hideInCombat" },
	reset = function()
		DB().point = nil
		if frame then
			Place()
		end
	end,
})
