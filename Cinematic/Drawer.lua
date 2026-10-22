local addonName, ns = ...

-- Cinematic games drawer: a small tab on the right edge of a cinematic slides out a panel of games to play while it
-- runs (the flight scene, Modules/Flight/Scene.lua). Games register with ns.Drawer_Add (the Casino in
-- Modules/Games/Casino.lua) and are picked from a list; the picked game's window docks in the panel. Esc slides the
-- panel shut (the game waits in it), and the cinematic's end closes the game. Plain frames: nothing here is
-- protected. The panel takes the mouse, so clicks on it never reach the letterbox (a click there pauses).

local PAD = 14 -- around the game, inside the panel
local HEADER_H = 40 -- the panel's title row
local MARGIN = 20 -- between the panel and the screen edge, and the letterbox bands
local MIN_W, MIN_H = 360, 200 -- the panel's smallest body, before any game asks for more
local MAX_WIDTH = 0.55 -- of the screen width: the panel shrinks to stay inside it
local SLIDE_TIME = 0.35 -- seconds to slide out or in
local HANDLE_W, HANDLE_H = 20, 76
local HANDLE_IDLE = 0.4 -- the tab's alpha while the mouse is elsewhere (it sits over the world)
local ROW_H, ROW_GAP = 58, 8 -- a game in the list
local ICON_SIZE = 38

local UI
local entries = {}
local root, panel, handle, list, body
local rows = {}
local open = false -- the panel is out (or on its way out)
local progress = 0 -- 0 shut .. 1 out
local current -- the entry being played, nil while the list shows
local fit = 1 -- the panel's scale: below 1 where the screen is too small for the biggest game

-- Layout ---------------------------------------------------------------------------------------------------------

-- The panel's size at scale 1: room for the biggest game under the title row.
local function PanelSize()
	local w, h = MIN_W, MIN_H
	for _, entry in ipairs(entries) do
		w = math.max(w, entry.width)
		h = math.max(h, entry.height)
	end
	return w + 2 * PAD, HEADER_H + h + PAD
end

local function Layout()
	local w, h = PanelSize()
	panel:SetSize(w, h)
	local room = root:GetHeight() * (1 - 2 * ns.CINEMATIC_BAND) - 2 * MARGIN
	fit = math.min(1, room / h, root:GetWidth() * MAX_WIDTH / w)
	panel:SetScale(fit)
end

-- Slid by progress: fully out it sits MARGIN in from the right edge, shut it's just past it (the tab stays on screen).
local function Place()
	local e = ns.Smoothstep(progress)
	local margin = MARGIN / fit -- offsets are in the panel's own (scaled) units
	panel:SetPoint("RIGHT", root, "RIGHT", -margin + (1 - e) * (panel:GetWidth() + margin), 0)
end

local function PaintHandle()
	local hover = handle:IsMouseOver()
	handle:SetAlpha((hover or open) and 1 or HANDLE_IDLE)
	handle.arrow:SetText(open and ">" or "<")
	UI.SetTextRole(handle.arrow, hover and "accent" or "text")
end

-- The list and the game ------------------------------------------------------------------------------------------

local ShowList

local function Header()
	panel.back:SetShown(current ~= nil)
	panel.title:ClearAllPoints()
	if current then
		panel.title:SetPoint("LEFT", panel.back, "RIGHT", 10, 0)
		panel.title:SetText(current.name)
	else
		panel.title:SetPoint("TOPLEFT", PAD + 2, -14)
		panel.title:SetText("Games")
	end
end

-- Closes the game being played (its window goes back where it lives outside the cinematic).
local function StopGame()
	local entry = current
	current = nil
	if entry then
		entry.Close()
	end
end

local function Play(entry)
	current = entry
	list:Hide()
	body:Show()
	Header()
	entry.Open(body, function()
		-- The game closed itself (its own close button): back to the list.
		if current == entry then
			current = nil
			ShowList()
		end
	end)
end

local function Row(i)
	if rows[i] then
		return rows[i]
	end
	local row = CreateFrame("Button", nil, list)
	row:SetHeight(ROW_H)
	row:SetPoint("TOPLEFT", 0, -(i - 1) * (ROW_H + ROW_GAP))
	row:SetPoint("RIGHT")
	row.bg = UI.Surface(row)
	row.icon = row:CreateTexture(nil, "ARTWORK")
	row.icon:SetSize(ICON_SIZE, ICON_SIZE)
	row.icon:SetPoint("LEFT", 10, 0)
	row.name = UI.Text(row, 15, "heading", "title")
	row.name:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 12, -2)
	row.text = UI.Text(row, 12, "textMuted")
	row.text:SetPoint("BOTTOMLEFT", row.icon, "BOTTOMRIGHT", 12, 2)
	row.text:SetPoint("RIGHT", -10, 0)
	row.text:SetWordWrap(false)
	row:SetScript("OnEnter", function(self)
		self.bg:SetColorTexture(UI.Color("hover"))
	end)
	row:SetScript("OnLeave", function(self)
		self.bg:SetColorTexture(UI.Color("surface"))
	end)
	row:SetScript("OnClick", function(self)
		Play(self.entry)
	end)
	rows[i] = row
	return row
end

-- The games that can be played now (a game's module may be off).
local function Available()
	local shown = {}
	for _, entry in ipairs(entries) do
		if entry.Shown() then
			shown[#shown + 1] = entry
		end
	end
	return shown
end

function ShowList()
	StopGame()
	body:Hide()
	list:Show()
	local shown = Available()
	for i, entry in ipairs(shown) do
		local row = Row(i)
		row.entry = entry
		row.icon:SetTexture(entry.icon)
		row.name:SetText(entry.name)
		row.text:SetText(entry.text)
		row.bg:SetColorTexture(UI.Color("surface"))
		row:Show()
	end
	for i = #shown + 1, #rows do
		rows[i]:Hide()
	end
	Header()
end

local function Toggle()
	open = not open
	if open then
		Layout()
		Place()
		if not current then
			ShowList()
		end
		panel:Show()
	end
	PaintHandle()
end

-- Building -------------------------------------------------------------------------------------------------------

local function Create(parent, letterbox)
	UI = ns.UI
	root = CreateFrame("Frame", nil, parent)
	root:SetAllPoints(letterbox)
	root:SetFrameLevel(letterbox:GetFrameLevel() + 20) -- above the scene's card and the hint

	panel = CreateFrame("Frame", nil, root)
	panel:EnableMouse(true)
	panel:Hide()
	UI.Panel(panel)

	panel.back = UI.Button(panel, 24, "<")
	panel.back:SetPoint("TOPLEFT", PAD, -10)
	panel.back:SetScript("OnClick", function()
		ShowList()
	end)
	panel.title = UI.Text(panel, 16, "heading", "title")
	panel.hint = UI.Text(panel, 11, "textMuted")
	panel.hint:SetPoint("TOPRIGHT", -PAD - 2, -16)
	panel.hint:SetText("Esc to close")

	list = CreateFrame("Frame", nil, panel)
	list:SetPoint("TOPLEFT", PAD, -HEADER_H)
	list:SetPoint("BOTTOMRIGHT", -PAD, PAD)
	-- The game's window docks here (entry.Open).
	body = CreateFrame("Frame", nil, panel)
	body:SetPoint("TOPLEFT", PAD, -HEADER_H)
	body:SetPoint("BOTTOMRIGHT", -PAD, PAD)
	body:Hide()

	handle = CreateFrame("Button", nil, root)
	handle:SetSize(HANDLE_W, HANDLE_H)
	handle:SetPoint("RIGHT", panel, "LEFT", 0, 0)
	UI.Surface(handle)
	handle.arrow = UI.Text(handle, 14, "text")
	handle.arrow:SetPoint("CENTER")
	handle:SetScript("OnClick", Toggle)
	handle:SetScript("OnEnter", PaintHandle)
	handle:SetScript("OnLeave", PaintHandle)
	handle:Hide()
end

-- API ------------------------------------------------------------------------------------------------------------

-- entry: key, name, text (one line under the name), icon (file ID), width and height (its window at scale 1),
-- Shown() (it can be played now), Open(host, onClosed) (dock its window in host, a frame of width x height or
-- smaller scaled; call onClosed if the game closes itself), Close() (undock and close it; no onClosed).
-- Called at file load.
function ns.Drawer_Add(entry)
	entries[#entries + 1] = entry
end

-- A scene's Create: the drawer lives in the scene's frame, over the letterbox.
function ns.Drawer_Create(parent, letterbox)
	Create(parent, letterbox)
end

-- A scene's Begin: shut, on the list, the tab shown when there's a game to play.
function ns.Drawer_Begin()
	root:SetScale(UIParent:GetEffectiveScale() / WorldFrame:GetEffectiveScale())
	StopGame()
	open, progress = false, 0
	panel:Hide()
	Layout()
	Place()
	handle:SetShown(#Available() > 0)
	PaintHandle()
end

-- A scene's Update.
function ns.Drawer_Update(alpha, dt)
	root:SetAlpha(alpha)
	local target = open and 1 or 0
	if progress == target then
		return
	end
	if target > progress then
		progress = math.min(progress + dt / SLIDE_TIME, 1)
	else
		progress = math.max(progress - dt / SLIDE_TIME, 0)
	end
	Place()
	if progress == 0 then
		panel:Hide()
	end
end

-- A scene's Escape: slides an open drawer shut (true), or leaves Esc to the cinematic (false).
function ns.Drawer_Escape()
	if not open then
		return false
	end
	Toggle()
	return true
end

-- A scene's End: the game closes, the drawer shuts and the tab goes (nothing left to click while the bands slide out).
function ns.Drawer_End()
	StopGame()
	open, progress = false, 0
	panel:Hide()
	handle:Hide()
end
