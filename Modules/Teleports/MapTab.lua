local addonName, ns = ...

-- Teleports tab in the world map's side panel (after Quests / Events / Map Legend). The list rows are ordinary
-- frames; one secure button parented to UIParent moves over the row under the mouse and gets that row's action
-- (a secure button inside the map would make the map protected, so it couldn't open or close in combat). In combat
-- the secure button is hidden and the list greys out; the map itself keeps working.
--
-- The tab itself (switching with Blizzard's tabs without taint) is Panel/MapTabs.lua.

local UI = ns.UI
local GOLD, WHITE, GREY, DIM = UI.GOLD, UI.WHITE, UI.GREY, UI.DIM
local ROW_H, HEADER_H, ICON = 34, 24, 26
local TAB_ICON = "Interface\\Icons\\Spell_Arcane_PortalDalaran"
local TICK = 1 -- seconds between cooldown text updates
local PIN_SIZE = 34
local KEY = "tp"

local db
local panel, secure, pin
local rows, used = {}, 0
local hoverRow
local tick = 0
local Refresh

local function InCombat()
	return InCombatLockdown()
end

-- Tooltip -----------------------------------------------------------------------------------------------------------

local function ShowTooltip(owner, e)
	GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
	if e.kind == "spell" then
		GameTooltip:SetSpellByID(e.id)
	elseif e.kind == "toy" then
		GameTooltip:SetToyByItemID(e.id)
	elseif e.kind == "item" then
		GameTooltip:SetItemByID(e.id)
	else
		GameTooltip:SetText(e.name)
		if e.desc then
			GameTooltip:AddLine(e.desc, 1, 1, 1, true)
		end
	end
	if e.dest then
		GameTooltip:AddLine("To: " .. e.dest, GOLD[1], GOLD[2], GOLD[3])
	end
	if not e.known then
		GameTooltip:AddLine("Not earned yet: time this dungeon on Mythic+ to get it.", 1, 0.5, 0.3, true)
	elseif InCombat() then
		GameTooltip:AddLine("In combat: teleports are off until combat ends.", 1, 0.3, 0.25)
	else
		GameTooltip:AddLine(db.favorites[e.key] and "Right-click: remove from favorites" or "Right-click: add to favorites",
			GREY[1], GREY[2], GREY[3])
	end
	GameTooltip:Show()
end

-- Map pin -----------------------------------------------------------------------------------------------------------

local function HidePin()
	if pin then
		pin:Hide()
	end
end

local function ShowPin(e)
	if not e.pinPos then
		HidePin()
		return
	end
	local canvas = WorldMapFrame:GetCanvas()
	if not pin then
		pin = CreateFrame("Frame", nil, canvas)
		pin.ring = pin:CreateTexture(nil, "OVERLAY")
		pin.ring:SetAllPoints()
		pin.ring:SetAtlas("Waypoint-MapPin-Tracked")
		pin.ring:SetVertexColor(GOLD[1], GOLD[2], GOLD[3])
	end
	pin:SetParent(canvas)
	pin:SetFrameLevel(canvas:GetFrameLevel() + 2000)
	local scale = WorldMapFrame.ScrollContainer:GetCanvasScale()
	pin:SetSize(PIN_SIZE / scale, PIN_SIZE / scale)
	pin:ClearAllPoints()
	pin:SetPoint("CENTER", canvas, "TOPLEFT", e.pinPos.x * canvas:GetWidth(), -e.pinPos.y * canvas:GetHeight())
	pin:Show()
end

-- Secure overlay button ---------------------------------------------------------------------------------------------

local ATTRIBUTES = { "spell", "toy", "item", "house-neighborhood-guid", "house-guid", "house-plot-id" }

local function SetAction(e)
	for _, key in ipairs(ATTRIBUTES) do
		secure:SetAttribute(key, nil)
	end
	if e.kind == "spell" then
		secure:SetAttribute("type", "spell")
		secure:SetAttribute("spell", e.id)
	elseif e.kind == "toy" then
		secure:SetAttribute("type", "toy")
		secure:SetAttribute("toy", e.id)
	elseif e.kind == "item" then
		secure:SetAttribute("type", "item")
		secure:SetAttribute("item", "item:" .. e.id)
	elseif e.kind == "random" then
		secure:SetAttribute("type", "toy")
		secure:SetAttribute("toy", ns.Tp_RandomHearthToy())
	elseif e.kind == "home" then
		secure:SetAttribute("type", "teleporthome")
		secure:SetAttribute("house-neighborhood-guid", e.house.neighborhoodGUID)
		secure:SetAttribute("house-guid", e.house.houseGUID)
		secure:SetAttribute("house-plot-id", e.house.plotID)
	end
end

local function Detach()
	if not secure then
		return
	end
	if not InCombat() then
		secure:Hide()
		secure:ClearAllPoints()
	end
	secure.row = nil
end

local function SetHover(row, on)
	if row then
		row.hover:SetShown(on)
	end
end

-- A protected frame can't be anchored to an ordinary one, so the secure button is placed in UIParent coordinates over
-- the row's on-screen rect, clipped to the visible part of the list. Returns false when nothing of the row shows.
local function PlaceOver(row)
	local scale = row:GetEffectiveScale() / UIParent:GetEffectiveScale()
	local left, bottom, width, height = row:GetRect()
	local cLeft, cBottom, cWidth, cHeight = panel.scroll:GetRect()
	if not left or not cLeft then
		return false
	end
	local top = math.min(bottom + height, cBottom + cHeight)
	bottom = math.max(bottom, cBottom)
	local right = math.min(left + width, cLeft + cWidth)
	left = math.max(left, cLeft)
	if top <= bottom or right <= left then
		return false
	end
	secure:ClearAllPoints()
	secure:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", left * scale, bottom * scale)
	secure:SetSize((right - left) * scale, (top - bottom) * scale)
	return true
end

local function Attach(row)
	if not secure or InCombat() or not row.entry or not row.entry.known then
		return false
	end
	if not PlaceOver(row) then
		return false
	end
	SetAction(row.entry)
	secure.row = row
	secure:Show()
	return true
end

local function CreateSecure()
	secure = CreateFrame("Button", nil, UIParent, "SecureActionButtonTemplate")
	secure:SetFrameStrata("FULLSCREEN_DIALOG")
	secure:Hide()
	secure:RegisterForClicks("AnyUp")
	secure:SetAttribute("useOnKeyDown", false)
	-- Right-click doesn't cast: it toggles the favorite in PostClick.
	secure:SetAttribute("type2", "macro")
	secure:SetAttribute("macrotext2", "")
	secure:SetScript("OnEnter", function(self)
		if self.row then
			SetHover(self.row, true)
			ShowTooltip(self, self.row.entry)
			ShowPin(self.row.entry)
		end
	end)
	secure:SetScript("OnLeave", function(self)
		SetHover(self.row, false)
		GameTooltip:Hide()
		HidePin()
		Detach()
	end)
	secure:SetScript("PostClick", function(self, button)
		local e = self.row and self.row.entry
		if not e then
			return
		end
		if button == "RightButton" then
			db.favorites[e.key] = not db.favorites[e.key] or nil
			Detach()
			GameTooltip:Hide()
			Refresh()
		elseif e.kind == "random" and not InCombat() then
			SetAction(e) -- a different toy next time
		end
	end)
	secure:EnableMouseWheel(true)
	secure:SetScript("OnMouseWheel", function(self, delta)
		SetHover(self.row, false)
		GameTooltip:Hide()
		HidePin()
		Detach()
		panel.scroll:SetScroll(panel.scroll:GetVerticalScroll() - delta * 40)
	end)
end

-- Setting attributes on a secure button isn't allowed in combat: a tab built in combat (the module turned on, or a
-- /reload mid-fight) gets its button when combat ends. Until then rows just show their tooltip.
local waitForCombat
local function EnsureSecure()
	if secure then
		return
	end
	if not InCombat() then
		CreateSecure()
		return
	end
	if not waitForCombat then
		waitForCombat = CreateFrame("Frame")
		waitForCombat:SetScript("OnEvent", function(self)
			self:UnregisterAllEvents()
			if not secure then
				CreateSecure()
			end
		end)
	end
	waitForCombat:RegisterEvent("PLAYER_REGEN_ENABLED")
end

-- Rows --------------------------------------------------------------------------------------------------------------

local function NewRow()
	local row = CreateFrame("Frame", nil, panel.scroll.content)
	row:EnableMouse(true)
	row.hover = row:CreateTexture(nil, "BACKGROUND")
	row.hover:SetAllPoints()
	row.hover:SetColorTexture(1, 1, 1, 0.06)
	row.hover:Hide()
	row.icon = row:CreateTexture(nil, "ARTWORK")
	row.icon:SetSize(ICON, ICON)
	row.icon:SetPoint("LEFT", 6, 0)
	row.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	row.cd = UI.Text(row, 11, WHITE)
	row.cd:SetJustifyH("RIGHT")
	row.cd:SetPoint("RIGHT", -6, 0)
	row.name = UI.Text(row, 12, WHITE)
	row.name:SetWordWrap(false)
	row.name:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 8, 0)
	row.name:SetPoint("RIGHT", row.cd, "LEFT", -6, 0)
	row.sub = UI.Text(row, 11, GREY)
	row.sub:SetWordWrap(false)
	row.sub:SetPoint("BOTTOMLEFT", row.icon, "BOTTOMRIGHT", 8, 0)
	row.sub:SetPoint("RIGHT", row.cd, "LEFT", -6, 0)
	row.title = UI.Text(row, 12, GOLD)
	row.title:SetPoint("BOTTOMLEFT", 6, 4)
	row.line = row:CreateTexture(nil, "ARTWORK")
	row.line:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.25)
	row.line:SetHeight(1)
	row.line:SetPoint("BOTTOMLEFT", 6, 1)
	row.line:SetPoint("BOTTOMRIGHT", -6, 1)
	row:SetScript("OnEnter", function(self)
		if not self.entry then
			return
		end
		hoverRow = self
		local owner = Attach(self) and secure or self
		SetHover(self, true)
		ShowTooltip(owner, self.entry)
		ShowPin(self.entry)
	end)
	row:SetScript("OnLeave", function(self)
		if secure and secure.row == self then
			return
		end
		SetHover(self, false)
		GameTooltip:Hide()
		HidePin()
	end)
	return row
end

local function Row()
	used = used + 1
	local row = rows[used] or NewRow()
	rows[used] = row
	row:Show()
	return row
end

local function UpdateCooldown(row)
	local e = row.entry
	local left = e.known and ns.Tp_Cooldown(e)
	local ready = left == 0
	if not e.known then
		row.cd:SetText("")
	elseif left == nil then
		row.cd:SetText("-")
	elseif left > 0 then
		row.cd:SetText(ns.Tp_FormatCooldown(left))
	else
		row.cd:SetText("")
	end
	local usable = e.known and ready and not InCombat()
	row.icon:SetDesaturated(not usable)
	local c = e.known and (usable and WHITE or GREY) or DIM
	row.name:SetTextColor(c[1], c[2], c[3])
end

local function SetEntry(row, e)
	row.entry = e
	row.title:Hide()
	row.line:Hide()
	row.icon:Show()
	row.name:Show()
	row.sub:Show()
	row.cd:Show()
	row.icon:SetTexture(e.icon or 134400)
	row.name:SetText(e.name)
	local sub = e.dest or e.group or ""
	if e.equips then
		sub = sub .. "  |cff999999(equips first)|r"
	end
	row.sub:SetText(sub)
	UpdateCooldown(row)
end

local function SetHeader(row, title)
	row.entry = nil
	row.icon:Hide()
	row.name:Hide()
	row.sub:Hide()
	row.cd:Hide()
	row.title:SetText(title)
	row.title:Show()
	row.line:Show()
end

-- Layout ------------------------------------------------------------------------------------------------------------

local function ViewedMapNames()
	local mapID = WorldMapFrame:GetMapID()
	local info = mapID and C_Map.GetMapInfo(mapID)
	-- The whole world (or cosmic) map would match everything.
	if not info or info.mapType < Enum.UIMapType.Continent then
		return nil
	end
	return ns.Tp_MapNames(mapID)
end

-- IsVisible: the tab stays selected (and shown) while the map is closed; bag and spell events mustn't redraw it then.
-- [mapNames][text] = whether it goes there: matching every entry against every name under a continent is a lot of
-- string work, and the answer only changes with the map.
local mentions = setmetatable({}, { __mode = "k" })
local function Mentions(text, mapNames)
	if not text then
		return false
	end
	local known = mentions[mapNames]
	if not known then
		known = {}
		mentions[mapNames] = known
	end
	if known[text] == nil then
		known[text] = ns.Tp_Mentions(text, mapNames.names)
	end
	return known[text]
end

function Refresh()
	if not panel or not panel:IsVisible() then
		return
	end
	Detach()
	for i = 1, used do
		rows[i]:Hide()
		rows[i].entry = nil
	end
	used = 0
	local mapNames = ViewedMapNames()
	local entries = ns.Tp_Entries(db)
	for _, e in ipairs(entries) do
		e.favorite = db.favorites[e.key] == true
		e.here = mapNames ~= nil and Mentions(e.dest or e.desc, mapNames)
		e.pinPos = mapNames and ns.Tp_PinPosition(e, mapNames) or nil
	end
	local hidden = {}
	for key, shown in pairs(db.sections) do
		hidden[key] = not shown
	end
	local sections = ns.Tp_Sections(entries, { showUnearned = db.showUnearned, hidden = hidden })

	local y = 0
	for _, section in ipairs(sections) do
		local header = Row()
		header:SetHeight(HEADER_H)
		header:SetPoint("TOPLEFT", 0, -y)
		header:SetPoint("RIGHT")
		SetHeader(header, section.title)
		y = y + HEADER_H + 2
		for _, e in ipairs(section.entries) do
			local row = Row()
			row:SetHeight(ROW_H)
			row:SetPoint("TOPLEFT", 0, -y)
			row:SetPoint("RIGHT")
			SetEntry(row, e)
			y = y + ROW_H
		end
		y = y + 6
	end
	panel.empty:SetShown(#sections == 0)
	panel.scroll:SetContentHeight(y)
	panel.note:SetText(InCombat() and "|cffff5040In combat: teleports are off until combat ends.|r"
		or "Click to teleport, right-click to favorite.")
end

local function OnUpdate(self, elapsed)
	tick = tick + elapsed
	if tick < TICK then
		return
	end
	tick = 0
	for i = 1, used do
		if rows[i].entry then
			UpdateCooldown(rows[i])
		end
	end
end

-- Tab ---------------------------------------------------------------------------------------------------------------

local function Build()
	if panel then
		return
	end
	local _
	_, panel = ns.MapTabs_Add({
		key = KEY, icon = TAB_ICON, tooltip = "Teleports",
		onShow = function()
			Refresh()
		end,
		onHide = function()
			Detach()
			HidePin()
		end,
		onMapChanged = function()
			Refresh()
		end,
	})
	if not panel then
		return
	end
	-- Reopening the map on the same map isn't a map change: redraw what was skipped while it was closed.
	panel:HookScript("OnShow", function()
		Refresh()
	end)
	panel.note = UI.Text(panel, 11, GREY)
	panel.note:SetPoint("TOPLEFT", panel.title, "BOTTOMLEFT", 0, -4)
	panel.note:SetPoint("RIGHT", -10, 0)
	panel.scroll = UI.Scroll(panel)
	panel.scroll:SetPoint("TOPLEFT", panel.note, "BOTTOMLEFT", -6, -8)
	panel.scroll:SetPoint("BOTTOMRIGHT", -10, 8)
	panel.empty = UI.Text(panel, 12, GREY)
	panel.empty:SetPoint("TOPLEFT", panel.scroll, "TOPLEFT", 6, -4)
	panel.empty:SetPoint("RIGHT", -10, 0)
	panel.empty:SetText("No teleports on this character.")
	panel:SetScript("OnUpdate", OnUpdate)
	panel:SetScript("OnHide", function()
		Detach()
		HidePin()
	end)
	panel.scroll:HookScript("OnMouseWheel", Detach)
	EnsureSecure()
end

-- API for Teleports.lua ---------------------------------------------------------------------------------------------

function ns.TpTab_Init(moduleDB)
	db = moduleDB
end

function ns.TpTab_SetEnabled(enabled)
	if enabled then
		Build()
	end
	ns.MapTabs_SetShown(KEY, enabled)
end

function ns.TpTab_Refresh()
	if ns.MapTabs_IsActive(KEY) then
		Refresh()
	end
end

function ns.TpTab_CombatStart()
	if secure then
		SetHover(secure.row, false)
		secure:Hide() -- still allowed: PLAYER_REGEN_DISABLED runs before the lockdown
		secure:ClearAllPoints()
		secure.row = nil
	end
	ns.TpTab_Refresh()
end

-- /tomte tp open: the map with this tab showing.
function ns.TpTab_Open()
	if InCombat() then
		ns.Print("not in combat.")
		return
	end
	if not WorldMapFrame:IsShown() then
		ToggleWorldMap()
	end
	if QuestMapFrame:IsShown() then
		ns.MapTabs_Select(KEY)
	else
		ns.Print("open the map's quest log panel, then click the portal tab.")
	end
end
