local addonName, ns = ...

-- Collect here tab in the world map's side panel (under Teleports): what's still missing on the map you're looking
-- at, in folding sections. Rows are ordinary frames (nothing here is a protected action). Click opens the journal,
-- shift-click links in chat, right-click on a rare that's up sets a waypoint. Tab switching is Panel/MapTabs.lua.

local UI = ns.UI
local KEY = "collect"
local TAB_ICON = "Interface\\Icons\\Ability_Mount_RidingHorse"
local ROW_H, HEADER_H, ICON = 34, 24, 26
local function UpNow() -- built when used: the theme is chosen on ADDON_LOADED
	return UI.Wrap("Up now", "success")
end

local db
local panel
local rows, used = {}, 0
local Refresh

-- The progress line's read: how far the journals are read, nil once they all are.
local function ReadProgress()
	local state = ns.Collect_State()
	if state.mounts and state.pets and state.achievements then
		return nil
	end
	return state.progress
end

-- Tooltip and model preview ------------------------------------------------------------------------------------------------------

local function ShowPreview(e)
	if panel.preview then
		ns.ModelPreview_Show(panel.preview, db.preview and ns.Entry_Model(e) or nil)
	end
end

local function HidePreview()
	if panel.preview then
		ns.ModelPreview_Hide(panel.preview)
	end
end

local function Hint(text)
	GameTooltip:AddLine(text, UI.RGB("textMuted"))
end

local function ShowTooltip(row)
	local e = row.entry
	GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
	if e.kind == "ach" then
		local link = GetAchievementLink(e.id)
		if link then
			GameTooltip:SetHyperlink(link)
		else
			GameTooltip:SetText(e.name)
		end
		Hint("Click: open in the Achievements window")
		Hint("Shift-click: link in chat")
	else
		GameTooltip:SetText(e.name)
		if e.source and e.source ~= "" then
			GameTooltip:AddLine((e.source:gsub("|n", "\n")), 1, 1, 1, true)
		end
		if e.zone then
			GameTooltip:AddLine(e.zone, UI.RGB("heading"))
		end
		if e.upNow then
			GameTooltip:AddLine(UpNow() .. ": " .. (e.drop or "") .. " is up nearby.", 1, 1, 1, true)
		end
		Hint(e.kind == "mount" and "Click: open in the Mount Journal" or "Click: open in the Pet Journal")
		if e.kind == "mount" then
			Hint("Shift-click: link in chat")
		end
		if e.upNow then
			Hint("Right-click: waypoint to " .. (e.drop or "it"))
		end
	end
	GameTooltip:Show()
	ShowPreview(e)
end

-- Rows ----------------------------------------------------------------------------------------------------------

local function OnRowClick(self, button)
	if self.section then
		db.collapsed[self.section] = not db.collapsed[self.section]
		Refresh()
		return
	end
	local e = self.entry
	if not e then
		return
	end
	if button == "LeftButton" then
		if IsShiftKeyDown() then
			ns.Entry_Link(e)
		else
			ns.Entry_Open(e)
		end
	elseif button == "RightButton" and e.upNow then
		ns.Collect_Waypoint(e.upNow, e.drop)
	end
end

local function NewRow()
	local row = CreateFrame("Frame", nil, panel.scroll.content)
	row.isCollectRow = true
	row:EnableMouse(true)
	row.hover = row:CreateTexture(nil, "BACKGROUND")
	row.hover:SetAllPoints()
	row.hover:SetColorTexture(UI.Color("hover"))
	row.hover:Hide()
	row.icon = row:CreateTexture(nil, "ARTWORK")
	row.icon:SetSize(ICON, ICON)
	row.icon:SetPoint("LEFT", 6, 0)
	row.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	row.right = UI.Text(row, 11, "textMuted")
	row.right:SetJustifyH("RIGHT")
	row.right:SetPoint("RIGHT", -6, 0)
	row.name = UI.Text(row, 12, "text")
	row.name:SetWordWrap(false)
	row.name:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 8, 0)
	row.name:SetPoint("RIGHT", row.right, "LEFT", -6, 0)
	row.sub = UI.Text(row, 11, "textMuted")
	row.sub:SetWordWrap(false)
	row.sub:SetPoint("BOTTOMLEFT", row.icon, "BOTTOMRIGHT", 8, 0)
	row.sub:SetPoint("RIGHT", row.right, "LEFT", -6, 0)
	row.title = UI.Text(row, 12, "heading")
	row.title:SetPoint("BOTTOMLEFT", 6, 4)
	row.line = row:CreateTexture(nil, "ARTWORK")
	row.line:SetColorTexture(UI.RGBA("frame", 0.4))
	row.line:SetHeight(1)
	row.line:SetPoint("BOTTOMLEFT", 6, 1)
	row.line:SetPoint("BOTTOMRIGHT", -6, 1)
	row:SetScript("OnEnter", function(self)
		self.hover:SetShown(self.entry ~= nil or self.section ~= nil)
		if self.entry then
			ShowTooltip(self)
		end
	end)
	row:SetScript("OnLeave", function(self)
		self.hover:Hide()
		GameTooltip:Hide()
		HidePreview()
	end)
	row:SetScript("OnMouseUp", OnRowClick)
	return row
end

local function Row()
	used = used + 1
	local row = rows[used] or NewRow()
	rows[used] = row
	row:Show()
	return row
end

-- A row's key for UI.ListArrivals.
local function RowKey(row)
	if row.section then
		return "section:" .. row.section
	end
	return row.entry and (row.entry.kind .. ":" .. tostring(row.entry.id)) or nil
end

local function SetHeader(row, section)
	row.entry, row.section = nil, section.key
	row.icon:Hide()
	row.name:Hide()
	row.sub:Hide()
	row.right:Show()
	row.right:SetText(section.collapsed and "+" or "-")
	row.title:SetText(("%s (%d)"):format(section.title, #section.entries))
	row.title:Show()
	row.line:Show()
end

local function SubText(e)
	if e.kind == "ach" then
		local text = ("%d%%"):format(math.floor(e.percent or 0))
		if e.total and e.total > 0 then
			text = text .. ("  ·  %d/%d"):format(e.done or 0, e.total)
		end
		return text
	end
	local parts = {}
	if e.upNow then
		parts[#parts + 1] = UpNow()
	end
	if e.zone then
		parts[#parts + 1] = e.zone
	end
	if e.line then
		parts[#parts + 1] = e.line
	end
	return table.concat(parts, "  ·  ")
end

local function SetEntry(row, e)
	row.entry, row.section = e, nil
	row.title:Hide()
	row.line:Hide()
	row.icon:Show()
	row.name:Show()
	row.sub:Show()
	row.icon:SetTexture(e.icon or 134400)
	row.name:SetText(e.name)
	row.sub:SetText(SubText(e))
	if e.kind == "ach" and e.points and e.points > 0 then
		row.right:SetText(e.points)
		row.right:Show()
	else
		row.right:SetText("")
	end
end

-- Layout --------------------------------------------------------------------------------------------------------

function Refresh()
	if not panel or not panel:IsVisible() then -- the tab stays shown while the map is closed
		return
	end
	-- Only our own tooltip goes (map pins use GameTooltip too); it comes back for the hovered row below. The model
	-- preview stays up so a redraw doesn't restart it.
	local owner = GameTooltip:GetOwner()
	local ours = owner and owner.isCollectRow
	if ours then
		GameTooltip:Hide()
	end
	for i = 1, used do
		rows[i]:Hide()
		rows[i].hover:Hide()
		rows[i].entry, rows[i].section = nil, nil
	end
	used = 0
	local state = ns.Collect_State()
	local loading = not (state.mounts and state.pets and state.achievements)
	local entries, mapName, _, mapID = ns.Collect_ForMap(WorldMapFrame:GetMapID())
	if not entries then
		HidePreview()
		panel.note:SetText("")
		panel.progress:Stop()
		panel.empty:SetText("Open a zone or a continent to see what's left to collect there.")
		panel.empty:Show()
		panel.scroll:SetContentHeight(1)
		return
	end
	ns.Collect_ApplyVignettes(entries, mapID)
	ns.Collect_ReadProgress(entries)
	local note = mapName
	if loading then
		note = note .. "  " .. UI.Wrap("reading the journals...", "textFaint")
		panel.progress:Track(ReadProgress)
	else
		panel.progress:Stop()
	end
	panel.note:SetText(note)
	local sections = ns.Collect_Sections(entries, { show = db.show, collapsed = db.collapsed })
	local y = 0
	for _, section in ipairs(sections) do
		local header = Row()
		header:SetHeight(HEADER_H)
		header.space = HEADER_H + 8 -- with the gap under it and after the section
		header:SetPoint("TOPLEFT", 0, -y)
		header:SetPoint("RIGHT")
		SetHeader(header, section)
		y = y + HEADER_H + 2
		if not section.collapsed then
			for _, e in ipairs(section.entries) do
				local row = Row()
				row:SetHeight(ROW_H)
				row.space = nil
				row:SetPoint("TOPLEFT", 0, -y)
				row:SetPoint("RIGHT")
				SetEntry(row, e)
				y = y + ROW_H
			end
		end
		y = y + 6
	end
	panel.empty:SetText(loading and "Reading the journals..."
		or "Nothing left here that the journals know about. Only mounts and pets whose source names a zone, and achievements that name it, can be listed.")
	panel.empty:SetShown(#sections == 0)
	panel.scroll:SetContentHeight(y)
	-- While the journals are read and on the redraw after: what a catalog just added fades in, the rest slides.
	local seen = (loading or panel.wasLoading) and panel.seenMap == mapID and panel.seen or nil
	panel.seen = (loading or panel.wasLoading) and UI.ListArrivals(rows, used, seen, RowKey) or nil
	panel.seenMap, panel.wasLoading = mapID, loading
	local hovered
	-- IsMouseOver ignores the scroll clipping: rows scrolled out of view lie over the map.
	local inView = panel.scroll:IsMouseOver()
	for i = 1, used do
		local row = rows[i]
		if inView and row:IsMouseOver() and (row.entry or row.section) then
			row.hover:Show()
			if row.entry then
				ShowTooltip(row)
				hovered = row.entry
			end
		end
	end
	if ours and not hovered then
		HidePreview()
	end
end

local function Build()
	if panel then
		return
	end
	local _
	_, panel = ns.MapTabs_Add({
		key = KEY, icon = TAB_ICON, tooltip = "Collect here",
		onMapChanged = function()
			Refresh()
		end,
	})
	if not panel then
		return
	end
	panel.note = UI.Text(panel, 11, "textMuted")
	panel.note:SetPoint("TOPLEFT", panel.title, "BOTTOMLEFT", 0, -4)
	panel.note:SetPoint("RIGHT", -10, 0)
	panel.note:SetWordWrap(false)
	-- In the gap under the note while the journals are read.
	panel.progress = UI.ProgressLine(panel)
	panel.progress:SetPoint("TOPLEFT", panel.note, "BOTTOMLEFT", 0, -4)
	panel.progress:SetPoint("RIGHT", -10, 0)
	panel.scroll = UI.Scroll(panel)
	panel.scroll:SetPoint("TOPLEFT", panel.note, "BOTTOMLEFT", -6, -8)
	panel.scroll:SetPoint("BOTTOMRIGHT", -10, 8)
	panel.empty = UI.Text(panel, 12, "textMuted")
	panel.empty:SetPoint("TOPLEFT", panel.scroll, "TOPLEFT", 6, -4)
	panel.empty:SetPoint("RIGHT", -10, 0)
	panel.preview = ns.ModelPreview_Create(panel)
	-- The tab stays selected while the map is closed, and reopening it on the same map isn't a map change.
	panel:HookScript("OnShow", function()
		Refresh()
	end)
end

-- API for Collect.lua -------------------------------------------------------------------------------------------

function ns.CollectTab_Init(moduleDB)
	db = moduleDB
end

function ns.CollectTab_SetEnabled(enabled)
	if enabled then
		Build()
	end
	ns.MapTabs_SetShown(KEY, enabled)
end

function ns.CollectTab_IsShown()
	return ns.MapTabs_IsActive(KEY) and WorldMapFrame:IsShown()
end

function ns.CollectTab_Refresh()
	if ns.MapTabs_IsActive(KEY) then
		Refresh()
	end
end

-- Something on the list was just earned (called by Collect.lua before the lists drop it): its row, when it's in view,
-- bursts as it leaves. Silent: the game plays its own sound for a new mount, pet or achievement.
function ns.CollectTab_Celebrate(kind, id)
	if not (panel and panel:IsVisible()) then
		return
	end
	local top, bottom = panel.scroll:GetTop(), panel.scroll:GetBottom()
	for i = 1, used do
		local row = rows[i]
		local e = row.entry
		local _, y = row:GetCenter()
		local earned = e and e.kind == kind
			and (kind == "ach" and e.id == id or kind ~= "ach" and not ns.Journal_StillMissing(kind, e.id))
		if earned and y and top and y < top and y > bottom then
			-- On the panel, not the row: the redraw that follows hands the row to another entry or hides it.
			UI.Burst(panel, row.icon, true)
			return
		end
	end
end

-- /tomte collect open, Home and the zone toast: this tab on the open map. True when it shows.
function ns.CollectTab_Open()
	return ns.Module_RequireOn("collect") and ns.MapTabs_Open(KEY)
end
