local addonName, ns = ...

-- Almost Done: the Top 5 tracker. A small window with pinned achievements first, then the closest ones. Click a
-- row to open it, right-click to pin or unpin. Unlocked, the whole window drags; rows whose progress went up
-- flash for a moment.

local UI = ns.UI
local GOLD, WHITE, GREY = UI.GOLD, UI.WHITE, UI.GREY
local ROWS = 5
local WIDTH = 260
local ROW_H = 26
local TITLE_H = 20
local ICON = 18
local TRACK_W = WIDTH - 16 - (6 + ICON + 8) -- row insets, icon and its gaps
local FLASH = 1.5 -- seconds
local DEFAULT_POINT = { "TOPRIGHT", "TOPRIGHT", -250, -250 }

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
	GameTooltip:SetText(entry.name, GOLD[1], GOLD[2], GOLD[3])
	GameTooltip:AddLine(ns.Ach_ProgressText(entry), 1, 1, 1)
	if entry.last then
		GameTooltip:AddLine("Left: " .. entry.last, 0.8, 0.8, 0.8, true)
	end
	if entry.reward ~= "" then
		GameTooltip:AddLine(entry.reward, 0.5, 0.88, 0.5, true)
	end
	GameTooltip:AddLine(entry.pinned and "Right-click to unpin" or "Right-click to pin", 0.5, 0.5, 0.5)
	GameTooltip:Show()
end

local function CreateRow(i)
	local row = CreateFrame("Button", nil, frame)
	row:SetHeight(ROW_H)
	row:SetPoint("TOPLEFT", 8, -(TITLE_H + (i - 1) * ROW_H))
	row:SetPoint("RIGHT", -8, 0)
	row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	row.flash = row:CreateTexture(nil, "BACKGROUND")
	row.flash:SetAllPoints()
	row.flash:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 1)
	row.flash:SetAlpha(0)
	row.pin = row:CreateTexture(nil, "ARTWORK")
	row.pin:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 1)
	row.pin:SetPoint("TOPLEFT", 0, -3)
	row.pin:SetPoint("BOTTOMLEFT", 0, 3)
	row.pin:SetWidth(2)
	row.icon = row:CreateTexture(nil, "ARTWORK")
	row.icon:SetSize(ICON, ICON)
	row.icon:SetPoint("LEFT", 6, 0)
	row.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	row.percent = UI.Text(row, 11, GREY)
	row.percent:SetPoint("TOPRIGHT", 0, -3)
	row.percent:SetJustifyH("RIGHT")
	row.name = UI.Text(row, 12, WHITE)
	row.name:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 8, 1)
	row.name:SetPoint("RIGHT", row.percent, "LEFT", -6, 0)
	row.name:SetWordWrap(false)
	row.track = row:CreateTexture(nil, "ARTWORK")
	row.track:SetColorTexture(1, 1, 1, 0.12)
	row.track:SetHeight(2)
	row.track:SetPoint("BOTTOMLEFT", row.icon, "BOTTOMRIGHT", 8, 1)
	row.track:SetPoint("RIGHT")
	row.fill = row:CreateTexture(nil, "OVERLAY")
	row.fill:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.9)
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
	row:SetScript("OnUpdate", function(self, dt)
		if self.flashLeft then
			self.flashLeft = self.flashLeft - dt
			if self.flashLeft <= 0 then
				self.flashLeft = nil
				self.flash:SetAlpha(0)
			else
				self.flash:SetAlpha(0.25 * self.flashLeft / FLASH)
			end
		end
	end)
	return row
end

local function SavePoint()
	local point, _, relPoint, x, y = frame:GetPoint(1)
	DB().point = { point, relPoint, x, y }
end

local function Build()
	inCombat = inCombat or InCombatLockdown() -- built mid-fight (/reload, turned on): the REGEN events already went by
	frame = CreateFrame("Frame", nil, UIParent)
	frame:SetSize(WIDTH, TITLE_H + ROWS * ROW_H + 8)
	frame:SetFrameStrata("MEDIUM")
	frame:SetClampedToScreen(true)
	frame:SetMovable(true)
	frame:Hide()
	local bg = frame:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints()
	bg:SetColorTexture(UI.BG[1], UI.BG[2], UI.BG[3], 0.55)
	frame.title = UI.Text(frame, 10, GREY)
	frame.title:SetPoint("TOPLEFT", 10, -6)
	frame.title:SetText(ns.Spaced("Almost done"))
	for i = 1, ROWS do
		rows[i] = CreateRow(i)
	end

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
	UI.Border(mover, GOLD[1], GOLD[2], GOLD[3], 0.8)
	local hint = UI.Text(mover, 10, GOLD)
	hint:SetPoint("TOPRIGHT", -8, -6)
	hint:SetText("drag to move")
	frame.mover = mover
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
	for i, row in ipairs(rows) do
		local entry = top[i]
		local old = row.entry
		row.entry = entry
		row:SetShown(entry ~= nil)
		if entry then
			row.icon:SetTexture(entry.icon)
			row.name:SetText(entry.name)
			row.percent:SetText(("%d%%"):format(math.floor(entry.percent)))
			row.pin:SetShown(entry.pinned == true)
			row.fill:SetWidth(math.max(TRACK_W * math.min(entry.percent, 100) / 100, 1))
			if flashIDs and flashIDs[entry.id] and old and old.id == entry.id and entry.percent > old.percent then
				row.flashLeft = FLASH
			end
		end
	end
	frame.count = #top
	ns.AchTracker_Apply()
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
	local editMode = ns.EditMode_Active()
	frame.mover:SetShown(not db.locked and not editMode)
	local hasRows = (frame.count or 0) > 0
	local show = active and db.shown and (hasRows or not db.locked or editMode)
		and not (db.hideInCombat and inCombat)
	frame:SetShown(show)
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
})
