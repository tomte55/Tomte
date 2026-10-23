local addonName, ns = ...

-- Housing decor: your houses. A small window (the Decor page's Houses button, /tomte decor houses) lists every house
-- you own with a Teleport button each, plus Return while you're visiting a house, and the teleport's cooldown. The
-- Teleport home key binding (CLICK TomteDecorHome) teleports to your first house (your faction's neighborhood first),
-- or back where you came from while visiting. Teleporting is a protected action (C_Housing.TeleportHome and
-- ReturnAfterVisitingHouse have restrictions), so the buttons are secure action buttons ("teleporthome" and
-- "returnhome" in SecureTemplates.lua), made and changed out of combat only, and the window closes in combat.
-- Order and the binding's choice in EditorData.lua; registered in Decor.lua. The Teleports module lists your houses
-- on its map tab too (Modules/Teleports/Owned.lua); this list works without it.

local WIDTH = 320
local ROW_H = 36
local PAD = 12
local TOP = 44 -- the title and the cooldown line above the rows
local MAX_ROWS = 6 -- houses a player can own is far below this
local HOME_BUTTON = "TomteDecorHome" -- global: the CLICK binding in Bindings.xml needs it
local ICON_HOUSE = 7252953 -- the dashboard's teleport-to-house icon
local ICON_RETURN = 236350 -- the leave-home icon
local HOUSE_ATTRIBUTES = { "house-neighborhood-guid", "house-guid", "house-plot-id" }
local UI = ns.UI

local OWNER = "houses"
local events = ns.Decor_Events

local db
local active = false
local houses = {} -- HouseInfo list from PLAYER_HOUSE_LIST_UPDATED
local requested = false
local window, home
local rows = {}
local pendingHome = false -- the home button's action changes once combat ends

local function CanReturn()
	if not (C_HousingNeighborhood and C_HousingNeighborhood.CanReturnAfterVisitingHouse) then
		return false
	end
	local ok, can = pcall(C_HousingNeighborhood.CanReturnAfterVisitingHouse)
	return ok and can == true
end

local function FactionMatches()
	local out = {}
	for _, h in ipairs(houses) do
		if h.neighborhoodGUID and h.houseGUID then
			local ok, match = pcall(C_Housing.DoesFactionMatchNeighborhood, h.neighborhoodGUID)
			out[h.houseGUID] = ok and match == true
		end
	end
	return out
end

local function Rows()
	return ns.DecorEditor_HouseRows(houses, FactionMatches())
end

-- Seconds left on the house teleport's cooldown (0 = ready), or nil when the game doesn't say.
local function Cooldown()
	local info = C_Housing.GetVisitCooldownInfo and C_Housing.GetVisitCooldownInfo()
	if not info or ns.IsSecret(info.startTime) or ns.IsSecret(info.duration) then
		return nil
	end
	local start, duration = info.startTime or 0, info.duration or 0
	if duration == 0 or info.isEnabled == false then
		return 0
	end
	return math.max(math.floor(start + duration - GetTime()), 0)
end

local function SetHouse(button, house)
	for _, key in ipairs(HOUSE_ATTRIBUTES) do
		button:SetAttribute(key, nil)
	end
	if house then
		button:SetAttribute("type", "teleporthome")
		button:SetAttribute("house-neighborhood-guid", house.neighborhoodGUID)
		button:SetAttribute("house-guid", house.houseGUID)
		button:SetAttribute("house-plot-id", house.plotID)
	end
end

local function SetReturn(button)
	SetHouse(button, nil)
	button:SetAttribute("type", "returnhome")
end

-- Teleport home key ---------------------------------------------------------------------------------------------------

local function UpdateHome()
	if not home then
		return
	end
	if InCombatLockdown() then
		pendingHome = true
		return
	end
	pendingHome = false
	local action, house = ns.DecorEditor_HomeAction(Rows(), CanReturn())
	if not (active and db.houses) or action == "none" then
		SetHouse(home, nil)
		home:SetAttribute("type", nil)
	elseif action == "return" then
		SetReturn(home)
	else
		SetHouse(home, house)
	end
end

-- Made at load, so a key bound to it works from the first press. Off screen; a binding clicks it.
local function CreateHome()
	home = CreateFrame("Button", HOME_BUTTON, UIParent, "SecureActionButtonTemplate")
	home:SetSize(1, 1)
	home:SetPoint("BOTTOMRIGHT", UIParent, "TOPLEFT", -10, 10)
	home:RegisterForClicks("AnyUp")
	home:SetAttribute("useOnKeyDown", false)
	-- Out of combat the choice is made again on every press: visiting a house changes it.
	home:SetScript("PreClick", function()
		if not InCombatLockdown() then
			UpdateHome()
		end
	end)
	home:SetScript("PostClick", function()
		if not (active and db.houses) then
			return
		end
		if not home:GetAttribute("type") then
			ns.Print("no house to teleport to (or the house list isn't read yet).")
		end
	end)
end
CreateHome()
_G["BINDING_NAME_CLICK " .. HOME_BUTTON .. ":LeftButton"] = "Teleport home (or back from a visit)"

-- Window ------------------------------------------------------------------------------------------------------------

local function RowEnter(self)
	self.hover:Show()
	GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
	if self.isReturn then
		GameTooltip:SetText("Return", UI.Color("heading"))
		UI.TipLine("Back to where you were before visiting a house.", "text", true)
	else
		GameTooltip:SetText(self.name:GetText() or "", UI.Color("heading"))
		UI.TipLine("Click to teleport to this house.", "text", true)
	end
	GameTooltip:Show()
end

local function RowLeave(self)
	self.hover:Hide()
	GameTooltip:Hide()
end

local function CreateRow(i)
	local row = CreateFrame("Button", nil, window, "SecureActionButtonTemplate")
	row:SetHeight(ROW_H)
	row:SetPoint("TOPLEFT", window, "TOPLEFT", PAD, -TOP - (i - 1) * (ROW_H + 4))
	row:SetPoint("TOPRIGHT", window, "TOPRIGHT", -PAD, -TOP - (i - 1) * (ROW_H + 4))
	row:RegisterForClicks("AnyUp")
	row:SetAttribute("useOnKeyDown", false)
	UI.Surface(row, 0.35)
	row.hover = row:CreateTexture(nil, "ARTWORK")
	row.hover:SetAllPoints()
	row.hover:SetColorTexture(UI.RGBA("hover", 0.6))
	row.hover:Hide()
	row.icon = row:CreateTexture(nil, "ARTWORK", nil, 1)
	row.icon:SetSize(ROW_H - 8, ROW_H - 8)
	row.icon:SetPoint("LEFT", 4, 0)
	row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	row.name = UI.Text(row, 13, "heading", "title")
	row.name:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 8, -2)
	row.name:SetPoint("RIGHT", -8, 0)
	row.name:SetWordWrap(false)
	row.where = UI.Text(row, 11, "textMuted")
	row.where:SetPoint("BOTTOMLEFT", row.icon, "BOTTOMRIGHT", 8, 2)
	row.where:SetPoint("RIGHT", -8, 0)
	row.where:SetWordWrap(false)
	row:SetScript("OnEnter", RowEnter)
	row:SetScript("OnLeave", RowLeave)
	rows[i] = row
	return row
end

local function Fill()
	if not window or InCombatLockdown() then
		return
	end
	local list = Rows()
	local n = 0
	if CanReturn() then
		n = 1
		local row = rows[1] or CreateRow(1)
		row.isReturn = true
		SetReturn(row)
		row.icon:SetTexture(ICON_RETURN)
		row.name:SetText("Return")
		row.where:SetText("Back from your visit")
		row:Show()
	end
	for _, r in ipairs(list) do
		if n >= MAX_ROWS then
			break
		end
		n = n + 1
		local row = rows[n] or CreateRow(n)
		row.isReturn = false
		SetHouse(row, r.house)
		row.icon:SetTexture(ICON_HOUSE)
		row.name:SetText(r.name)
		row.where:SetText(r.where or "")
		row:Show()
	end
	for i = n + 1, #rows do
		rows[i]:Hide()
	end
	window.empty:SetShown(n == 0)
	local left = Cooldown()
	if left == nil then
		window.cooldown:SetText("")
	elseif left > 0 then
		window.cooldown:SetText(UI.Wrap("Teleport cooldown: " .. ns.Clock(left), "warning"))
	else
		window.cooldown:SetText(UI.Wrap("Teleport ready", "success"))
	end
	window:SetHeight(TOP + math.max(n, 1) * (ROW_H + 4) + PAD)
end

-- A protected frame (SecureFrameTemplate), so the secure rows can be anchored in it.
local function CreateWindow()
	window = CreateFrame("Frame", nil, UIParent, "SecureFrameTemplate")
	window:SetSize(WIDTH, TOP + ROW_H + PAD)
	window:SetPoint("CENTER", 0, 80)
	window:SetFrameStrata("DIALOG")
	window:SetToplevel(true)
	window:EnableMouse(true)
	window:SetMovable(true)
	window:SetClampedToScreen(true)
	window:RegisterForDrag("LeftButton")
	window:SetScript("OnDragStart", function(self)
		if not InCombatLockdown() then
			self:StartMoving()
		end
	end)
	window:SetScript("OnDragStop", window.StopMovingOrSizing)
	window:Hide()
	UI.Panel(window)
	local title = UI.Text(window, 15, "heading", "title")
	title:SetPoint("TOPLEFT", PAD, -PAD)
	title:SetText("Your houses")
	window.cooldown = UI.Text(window, 11, "textMuted")
	window.cooldown:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -3)
	window.empty = UI.Text(window, 12, "textMuted")
	window.empty:SetPoint("TOPLEFT", PAD, -TOP - 8)
	window.empty:SetPoint("RIGHT", -PAD, 0)
	window.empty:SetText("No house found yet.")
	local close = UI.Button(window, 60, "Close")
	close:SetPoint("TOPRIGHT", -PAD, -PAD)
	close:SetScript("OnClick", function()
		if not InCombatLockdown() then
			window:Hide()
		end
	end)
	UI.CloseOnEscape(window)
end

local function Request()
	if C_Housing and C_Housing.GetPlayerOwnedHouses then
		requested = true
		C_Housing.GetPlayerOwnedHouses() -- answers with PLAYER_HOUSE_LIST_UPDATED
	end
end

-- The Decor page's Houses button and /tomte decor houses.
function ns.DecorHouses_Toggle()
	if not (active and db.houses) then
		ns.Print("the house list is off (Housing decor settings).")
		return
	end
	if InCombatLockdown() then
		ns.Print("the house list opens out of combat.")
		return
	end
	if window and window:IsShown() then
		window:Hide()
		return
	end
	if not window then
		CreateWindow()
	end
	Request()
	Fill()
	window:Show()
end

-- /tomte decor home: teleporting needs a click or a key press, never a command.
function ns.DecorHouses_HomeHelp()
	ns.Print("teleporting home needs a click or a key: bind \"Teleport home\" (Key Bindings > Tomte), or use the "
		.. "Teleport buttons in the house list.")
	if not InCombatLockdown() and not (window and window:IsShown()) then
		ns.DecorHouses_Toggle()
	end
end

events:On(OWNER, "PLAYER_HOUSE_LIST_UPDATED", function(_, list)
	houses = type(list) == "table" and list or {}
	UpdateHome()
	if window and window:IsShown() then
		Fill()
	end
end)

events:On(OWNER, "PLAYER_REGEN_DISABLED", function()
	-- The window was opened from code before combat; protected, so it has to go now.
	if window and window:IsShown() then
		window:Hide()
	end
end)

events:On(OWNER, "PLAYER_REGEN_ENABLED", function()
	if pendingHome then
		UpdateHome()
	end
	if not (active and db.houses) then
		-- Watched only to clear the home button after a stop that fell in combat (Watch).
		events:UnwatchAll(OWNER)
	end
end)

local function Refresh()
	UpdateHome()
	if window and window:IsShown() then
		Fill()
	end
end
events:On(OWNER, "HOUSE_PLOT_ENTERED", Refresh)
events:On(OWNER, "HOUSE_PLOT_EXITED", Refresh)

-- Called by Decor.lua -------------------------------------------------------------------------------------------------

function ns.DecorHouses_Init(moduleDB)
	db = moduleDB
end

-- The house list is read once per session, on the first loading screen with the list on (or when the window opens).
events:On(OWNER, "PLAYER_ENTERING_WORLD", function()
	if not requested then
		Request()
	end
end)

local function Watch()
	events:UnwatchAll(OWNER)
	if not (active and db.houses) then
		if window and window:IsShown() and not InCombatLockdown() then
			window:Hide()
		end
		if pendingHome then
			-- Turned off in combat: the home button keeps its teleport until combat ends.
			events:Watch(OWNER, "PLAYER_REGEN_ENABLED")
		end
		return
	end
	events:TryWatch(OWNER, "PLAYER_HOUSE_LIST_UPDATED")
	events:TryWatch(OWNER, "HOUSE_PLOT_ENTERED")
	events:TryWatch(OWNER, "HOUSE_PLOT_EXITED")
	events:Watch(OWNER, "PLAYER_REGEN_DISABLED")
	events:Watch(OWNER, "PLAYER_REGEN_ENABLED")
	events:Watch(OWNER, "PLAYER_ENTERING_WORLD")
	if not requested and ns.inWorld then
		Request()
	end
end

function ns.DecorHouses_Start()
	active = true
	Watch()
	UpdateHome()
end

function ns.DecorHouses_Stop()
	active = false
	UpdateHome() -- first: in combat it marks the change pending, which Watch keeps an event for
	Watch()
end

-- The Houses setting changed.
function ns.DecorHouses_Apply()
	UpdateHome()
	Watch()
end

-- Shown on the Decor page while the list is on.
function ns.DecorHouses_Enabled()
	return active and db.houses == true
end
