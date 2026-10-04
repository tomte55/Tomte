local addonName, ns = ...

-- Weekly popup: a small window with only what is still open this week for the current character. Right-click on the
-- minimap button or /tomte weekly popup toggles it; Esc closes it; drag the title to move it (position saved).

local UI = ns.UI
local GOLD, GREY = UI.GOLD, UI.GREY
local WIDTH, TITLE_H, FOOT_H = 340, 36, 40
local MIN_LIST_H, MAX_LIST_H = 60, 420

local frame, list

local function SavePosition()
	local point, _, relativePoint, x, y = frame:GetPoint()
	ns.weeklyDB.popup.point = { point, relativePoint, x, y }
end

local function Place()
	frame:ClearAllPoints()
	local p = ns.weeklyDB.popup.point
	if p then
		frame:SetPoint(p[1], UIParent, p[2], p[3], p[4])
	else
		frame:SetPoint("TOPRIGHT", Minimap, "BOTTOMLEFT", -10, -10)
	end
end

local function Layout()
	local v = ns.Weekly_CurrentView()
	local db = ns.weeklyDB
	local items = v and ns.Weekly_OpenModel(v, db.quests, GetServerTime(), db.learned) or {}
	local height = list:Render(items)
	frame.empty:SetShown(#items == 0)
	if not v then
		frame.empty:SetText("The weekly board tracks max-level characters.")
	else
		frame.empty:SetText("|TInterface\\RaidFrame\\ReadyCheck-Ready:14|t  All done this week.")
	end
	local listH = math.min(math.max(height, MIN_LIST_H), MAX_LIST_H)
	frame:SetHeight(TITLE_H + 8 + listH + FOOT_H)
	local now = GetServerTime()
	local snap = v and ns.weeklyDB.chars[v.guid]
	frame.reset:SetText(snap and snap.nextReset and snap.nextReset > now
		and ("Reset in " .. ns.Weekly_Duration(snap.nextReset - now)) or "")
end

local function Build()
	frame = CreateFrame("Frame", nil, UIParent)
	frame:SetWidth(WIDTH)
	frame:SetFrameStrata("HIGH")
	frame:SetMovable(true)
	frame:SetClampedToScreen(true)
	frame:EnableMouse(true)
	frame:Hide()
	local bg = frame:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints()
	bg:SetColorTexture(UI.BG[1], UI.BG[2], UI.BG[3], UI.BG[4])
	UI.Border(frame, GOLD[1], GOLD[2], GOLD[3], 0.35)

	local titleBar = CreateFrame("Frame", nil, frame)
	titleBar:SetPoint("TOPLEFT")
	titleBar:SetPoint("TOPRIGHT")
	titleBar:SetHeight(TITLE_H)
	titleBar:EnableMouse(true)
	titleBar:RegisterForDrag("LeftButton")
	titleBar:SetScript("OnDragStart", function()
		frame:StartMoving()
	end)
	titleBar:SetScript("OnDragStop", function()
		frame:StopMovingOrSizing()
		SavePosition()
	end)
	local title = UI.Text(titleBar, 20, GOLD, ns.SCENE_TITLE_FONT)
	title:SetPoint("LEFT", 14, -2)
	title:SetText("This week")
	local close = UI.Button(titleBar, 20, "x")
	close:SetPoint("RIGHT", -10, 0)
	close:SetScript("OnClick", function()
		frame:Hide()
	end)
	frame.reset = UI.Text(titleBar, 11, GREY)
	frame.reset:SetPoint("RIGHT", close, "LEFT", -10, 0)
	local line = UI.Hairline(titleBar, WIDTH - 40, 0.5)
	line:SetPoint("BOTTOM")

	list = ns.WeeklyList(frame)
	list.scroll:SetPoint("TOPLEFT", 4, -TITLE_H - 4)
	list.scroll:SetPoint("BOTTOMRIGHT", -10, FOOT_H)
	frame.empty = UI.Text(frame, 13, UI.WHITE)
	frame.empty:SetPoint("TOPLEFT", 16, -TITLE_H - 16)
	frame.empty:SetPoint("RIGHT", -16, 0)
	frame.empty:SetWordWrap(true)

	local open = UI.Button(frame, 110, "Open board")
	open:SetPoint("BOTTOMRIGHT", -10, 10)
	open:SetScript("OnClick", function()
		frame:Hide()
		ns.Panel_OpenModule("weekly", "page")
	end)

	frame:SetScript("OnShow", function()
		ns.WeeklyCollect_Request()
		Layout()
	end)

	-- Esc closes it: UISpecialFrames hides this dummy, which hides the window.
	local escape = CreateFrame("Frame", "TomteWeeklyEscape", UIParent)
	escape:Hide()
	table.insert(UISpecialFrames, "TomteWeeklyEscape")
	escape:SetScript("OnHide", function()
		if UIParent:IsShown() then -- not when a cinematic or Alt-Z hides the whole UI
			frame:Hide()
		end
	end)
	frame:HookScript("OnShow", function()
		escape:Show()
	end)
	frame:HookScript("OnHide", function()
		escape:Hide()
	end)
	Place()
end

function ns.WeeklyPopup_Toggle()
	if not frame then
		Build()
	end
	frame:SetShown(not frame:IsShown())
end

function ns.WeeklyPopup_Hide()
	if frame then
		frame:Hide()
	end
end

function ns.WeeklyPopup_Refresh()
	if frame and frame:IsShown() then
		Layout()
	end
end

function ns.WeeklyPopup_ResetPosition()
	if ns.weeklyDB then
		ns.weeklyDB.popup.point = nil
	end
	if frame then
		Place()
	end
end
