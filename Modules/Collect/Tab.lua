local addonName, ns = ...

-- Collect here tab in the world map's side panel (under Teleports): what's still missing on the map you're looking
-- at, in folding sections. Rows are ordinary frames (nothing here is a protected action). Click opens the journal,
-- shift-click links in chat, right-click on a rare that's up sets a waypoint. Tab switching is Panel/MapTabs.lua.

local UI = ns.UI
local KEY = "collect"
local TAB_ICON = "Interface\\Icons\\Ability_Mount_RidingHorse"
local ROW_H, HEADER_H, ICON = 34, 24, 26
local LOADING_TICK = 1 -- seconds between refreshes while the journals are read
local function UpNow() -- built when used: the theme is chosen on ADDON_LOADED
	return UI.Wrap("Up now", "success")
end

local db
local panel
local rows, used = {}, 0
local tick = 0
local Refresh

-- Actions -------------------------------------------------------------------------------------------------------

local function InsertLink(link)
	local insert = (ChatFrameUtil and ChatFrameUtil.InsertLink) or ChatEdit_InsertLink
	if link and insert then
		insert(link)
	end
end

local function Link(e)
	if e.kind == "mount" then
		InsertLink(e.spellID and C_MountJournal.GetMountLink(e.spellID))
	elseif e.kind == "ach" then
		ns.Ach_Link(e.id)
	end
end

local function OpenJournal(e)
	if InCombatLockdown() then
		ns.Print("the journal opens after combat.")
		return
	end
	if e.kind == "ach" then
		ns.Ach_Open(e.id)
		return
	end
	local tabIndex = e.kind == "mount" and COLLECTIONS_JOURNAL_TAB_INDEX_MOUNTS or COLLECTIONS_JOURNAL_TAB_INDEX_PETS
	SetCollectionsJournalShown(true, tabIndex)
	if e.kind == "mount" and MountJournal_SelectByMountID then
		MountJournal_SelectByMountID(e.id)
	elseif e.kind == "pet" and PetJournal and PetJournal_SelectSpecies then
		PetJournal_SelectSpecies(PetJournal, e.id)
	end
end

-- Tooltip and model preview ------------------------------------------------------------------------------------------------------

-- The turning model next to the tooltip (Panel/ModelPreview.lua), for mounts and pets.
local function ModelFor(e)
	if e.kind == "mount" then
		local displayID, _, _, isSelfMount, _, sceneID = C_MountJournal.GetMountInfoExtraByID(e.id)
		if not displayID then
			-- Mounts with several looks have no single display ID: use the first one.
			local all = C_MountJournal.GetMountAllCreatureDisplayInfoByID(e.id)
			displayID = all and all[1] and all[1].creatureDisplayID
		end
		return { sceneID = sceneID, displayID = displayID, selfMount = isSelfMount, name = e.name, sub = "Mount" }
	elseif e.kind == "pet" then
		local displayID = select(12, C_PetJournal.GetPetInfoBySpeciesID(e.id))
		local sceneID = C_PetJournal.GetPetModelSceneInfoBySpeciesID(e.id)
		return { sceneID = sceneID, displayID = displayID, name = e.name, sub = "Battle pet" }
	end
	return nil
end

local function ShowPreview(e)
	if panel.preview then
		ns.ModelPreview_Show(panel.preview, db.preview and ModelFor(e) or nil)
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
			Link(e)
		else
			OpenJournal(e)
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
		panel.empty:SetText("Open a zone or a continent to see what's left to collect there.")
		panel.empty:Show()
		panel.scroll:SetContentHeight(1)
		return
	end
	ns.Collect_ApplyVignettes(entries, mapID)
	ns.Collect_ReadProgress(entries)
	local note = mapName
	if loading then
		note = note .. "  " .. UI.Wrap(("reading the journals... %d%%"):format(math.floor(state.progress * 100)), "textFaint")
	end
	panel.note:SetText(note)
	local sections = ns.Collect_Sections(entries, { show = db.show, collapsed = db.collapsed })
	local y = 0
	for _, section in ipairs(sections) do
		local header = Row()
		header:SetHeight(HEADER_H)
		header:SetPoint("TOPLEFT", 0, -y)
		header:SetPoint("RIGHT")
		SetHeader(header, section)
		y = y + HEADER_H + 2
		if not section.collapsed then
			for _, e in ipairs(section.entries) do
				local row = Row()
				row:SetHeight(ROW_H)
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
	local hovered
	for i = 1, used do
		local row = rows[i]
		if row:IsMouseOver() and (row.entry or row.section) then
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

local function OnUpdate(_, elapsed)
	tick = tick + elapsed
	if tick < LOADING_TICK then
		return
	end
	tick = 0
	local state = ns.Collect_State()
	if not (state.mounts and state.pets and state.achievements) then
		Refresh()
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
	panel.scroll = UI.Scroll(panel)
	panel.scroll:SetPoint("TOPLEFT", panel.note, "BOTTOMLEFT", -6, -8)
	panel.scroll:SetPoint("BOTTOMRIGHT", -10, 8)
	panel.empty = UI.Text(panel, 12, "textMuted")
	panel.empty:SetPoint("TOPLEFT", panel.scroll, "TOPLEFT", 6, -4)
	panel.empty:SetPoint("RIGHT", -10, 0)
	panel:SetScript("OnUpdate", OnUpdate)
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

-- /tomte collect open and the zone toast: the map on this tab.
function ns.CollectTab_Open()
	if InCombatLockdown() then
		ns.Print("not in combat.")
		return
	end
	if not WorldMapFrame:IsShown() then
		ToggleWorldMap()
	end
	if QuestMapFrame:IsShown() then
		ns.MapTabs_Select(KEY)
	else
		ns.Print("open the map's quest log panel, then click the horse tab.")
	end
end
