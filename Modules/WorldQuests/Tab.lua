local addonName, ns = ...

-- World quests tab in the world map's side panel (under Collect here): the viewed map's world quests in folding
-- sections by reward. Rows are ordinary frames (nothing here is a protected action). Hover marks the quest on the
-- map with our own pulsing highlight (Blizzard's MapCanvas.PingQuestID would make the map's pin pools tainted),
-- click super-tracks it (what Blizzard's pin click does), shift-click links it, right-click opens its zone on a
-- continent or stops tracking it on a zone. Tab switching is Panel/MapTabs.lua.

local UI = ns.UI
local GOLD, WHITE, GREY = UI.GOLD, UI.WHITE, UI.GREY
local KEY = "wq"
local TAB_ICON = "Interface\\Icons\\INV_Misc_Map_01"
local ROW_H, HEADER_H, ICON = 34, 24, 26
local LOADING_TICK = 1 -- seconds between refreshes while rewards load
local CLOCK_TICK = 30 -- seconds between refreshes otherwise (time left, expired quests)
local ARROW_ATLAS = "Navigation-Tracked-Arrow" -- Blizzard's super-tracking arrow; points up as drawn
local ARROW_LIFT = 10 -- gap between the quest's spot and the arrow's tip
local ARROW_BOB = 6 -- how far it rises
local BOB_PERIOD = 1.3 -- seconds per up-and-down
local FADE_IN = 0.15 -- seconds
local MARKER_RESUME = 0.5 -- seconds: hidden and shown again for the same quest within this, it carries on
local SHADOW_X, SHADOW_Y = 2, -3
local MARKER_STRATA = "FULLSCREEN_DIALOG" -- above every map layer (RareScanner pins are DIALOG), below tooltips
local REP_ICON = "Interface\\Icons\\Achievement_Reputation_01"
local GOLD_ICON = "Interface\\Icons\\INV_Misc_Coin_01"
local NO_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"
local TIME_COLORS = { critical = { 1, 0.3, 0.25 }, low = { 1, 0.6, 0.2 }, normal = GREY }
local MAIN_COLOR = "|cffe6e6e6"
local WORTH_COLOR = "|cff4ee44e"
local COLLECTIBLE_SUB = { mount = "Mount", pet = "Battle pet", toy = "Toy" }

local db
local panel
local rows, used = {}, 0
local tick, clock = 0, 0
local marker
local pending = 0
local Refresh

-- Actions -------------------------------------------------------------------------------------------------------

local function InsertLink(link)
	local insert = (ChatFrameUtil and ChatFrameUtil.InsertLink) or ChatEdit_InsertLink
	if link and insert then
		insert(link)
	end
end

local function IsTracked(q)
	return C_SuperTrack.GetSuperTrackedQuestID() == q.id
end

-- Blizzard's pin click (WorldQuestPinMixin:OnMouseClickAction), without QuestUtil.TrackWorldQuest (it writes a
-- Blizzard upvalue, which would taint it).
local function Track(q)
	if IsTracked(q) then
		C_SuperTrack.SetSuperTrackedQuestID(0)
		return
	end
	if C_QuestLog.GetQuestWatchType(q.id) ~= Enum.QuestWatchType.Manual then
		C_QuestLog.AddWorldQuestWatch(q.id, Enum.QuestWatchType.Automatic)
	end
	C_SuperTrack.SetSuperTrackedQuestID(q.id)
end

local function Untrack(q)
	if IsTracked(q) then
		C_SuperTrack.SetSuperTrackedQuestID(0)
	end
	if C_QuestLog.GetQuestWatchType(q.id) ~= nil then
		C_QuestLog.RemoveWorldQuestWatch(q.id)
	end
end

-- Our own highlight on the map (a plain frame, not a map pin): Blizzard's super-tracking arrow, turned to point down
-- at the quest's spot, with a soft shadow, bobbing smoothly above the pin without covering it. The bob is a sine
-- driven per frame with pixel snapping off (a looping animation reverses with a visible snap). Scaled to the UI, so
-- it's the same size on screen at any map zoom.
local function ArrowTexture(parent, layer)
	local tex = parent:CreateTexture(nil, layer)
	tex:SetAtlas(ARROW_ATLAS, true)
	tex:SetRotation(math.pi)
	tex:SetSnapToPixelGrid(false)
	tex:SetTexelSnappingBias(0)
	return tex
end

local function PlaceArrow(phase)
	local rise = ARROW_BOB * phase
	marker.arrow:SetPoint("BOTTOM", marker, "CENTER", 0, ARROW_LIFT + rise)
	marker.shadow:SetPoint("BOTTOM", marker, "CENTER", SHADOW_X + rise * 0.3, ARROW_LIFT + SHADOW_Y + rise * 0.5)
	marker.shadow:SetAlpha(0.6 - 0.25 * phase)
end

local function OnMarkerUpdate(self, elapsed)
	self.t = self.t + elapsed
	local phase = (1 - math.cos(self.t * 2 * math.pi / BOB_PERIOD)) / 2 -- 0 at rest, 1 at the top, eased both ways
	PlaceArrow(phase)
	self:SetAlpha(math.min(1, self.t / FADE_IN))
end

local function BuildMarker(canvas)
	marker = CreateFrame("Frame", nil, canvas)
	marker:EnableMouse(false)
	marker:SetSize(1, 1)
	marker.shadow = ArrowTexture(marker, "BACKGROUND")
	marker.shadow:SetVertexColor(0, 0, 0)
	marker.arrow = ArrowTexture(marker, "OVERLAY")
	marker:SetScript("OnUpdate", OnMarkerUpdate)
	marker:Hide()
end

local function HideMarker()
	if marker and marker:IsShown() then
		marker.hiddenAt = GetTime()
		marker:Hide()
	end
end

local function ShowMarker(q)
	local canvas = WorldMapFrame:GetCanvas()
	local x, y = C_TaskQuest.GetQuestLocation(q.id, WorldMapFrame:GetMapID())
	if not (canvas and x and y and (x > 0 or y > 0)) then
		HideMarker()
		return
	end
	if not marker then
		BuildMarker(canvas)
	end
	-- Offsets are in the marker's own (scaled) units.
	local scale = UIParent:GetEffectiveScale() / canvas:GetEffectiveScale()
	marker:SetScale(scale)
	marker:SetFrameStrata(MARKER_STRATA)
	marker:ClearAllPoints()
	marker:SetPoint("CENTER", canvas, "TOPLEFT", x * canvas:GetWidth() / scale, -y * canvas:GetHeight() / scale)
	if not marker:IsShown() then
		-- A redraw hides and re-shows the rows (mouse leave, then enter): the same quest coming back right away carries
		-- on bobbing instead of starting over.
		local resume = marker.questID == q.id and marker.hiddenAt and GetTime() - marker.hiddenAt < MARKER_RESUME
		if not resume then
			marker.t = 0
			marker:SetAlpha(0)
			PlaceArrow(0)
		end
		marker:Show()
	end
	marker.questID = q.id
end

-- Tooltip and model preview -------------------------------------------------------------------------------------

local function ModelFor(item)
	if not item then
		return nil
	end
	if item.collectible == "mount" then
		local mountID = C_MountJournal.GetMountFromItem(item.itemID)
		if not mountID then
			return nil
		end
		local displayID, _, _, _, _, sceneID = C_MountJournal.GetMountInfoExtraByID(mountID)
		if not displayID then
			local all = C_MountJournal.GetMountAllCreatureDisplayInfoByID(mountID)
			displayID = all and all[1] and all[1].creatureDisplayID
		end
		return { sceneID = sceneID, displayID = displayID, name = item.name, sub = COLLECTIBLE_SUB.mount }
	elseif item.collectible == "pet" then
		local _, _, _, _, _, _, _, _, _, _, _, displayID, speciesID = C_PetJournal.GetPetInfoByItemID(item.itemID)
		local sceneID = speciesID and C_PetJournal.GetPetModelSceneInfoBySpeciesID(speciesID)
		return { sceneID = sceneID, displayID = displayID, name = item.name, sub = COLLECTIBLE_SUB.pet }
	elseif item.appearance and item.link then
		return { link = item.link, name = item.name, sub = "Appearance you don't have" }
	end
	return nil
end

local function HidePreview()
	if panel.preview then
		ns.ModelPreview_Hide(panel.preview)
	end
end

local function Line(text, color, wrap)
	color = color or WHITE
	GameTooltip:AddLine(text, color[1], color[2], color[3], wrap)
end

local function QuestLines(q, header)
	if header then
		Line(" ")
		Line(q.title, GOLD)
	end
	local where = { q.zone, ns.WQ_Tags(q) ~= "" and ns.WQ_Tags(q) or nil }
	if #where > 0 then
		Line(table.concat(where, "  ·  "), GREY)
	end
	local time, tier = ns.WQ_TimeText(q.seconds)
	if time then
		Line(time .. " left", TIME_COLORS[tier])
	end
end

local function RewardLines(q, skipItem)
	if not q.loaded then
		Line("Loading rewards…", GREY)
		return
	end
	for _, item in ipairs(q.items) do
		if item ~= skipItem then
			local text = (item.count or 1) > 1 and (item.count .. " " .. item.name) or item.name
			if item.collectible then
				text = COLLECTIBLE_SUB[item.collectible] .. ": " .. text .. " (missing)"
			elseif item.gear and item.ilvl then
				text = text .. " (ilvl " .. item.ilvl .. ")"
			end
			Line(text)
			if item.headline then
				Line("  " .. item.headline, GREY)
			end
		end
	end
	for _, c in ipairs(q.currencies) do
		Line(("%d %s%s"):format(c.amount or 0, c.name or "?", c.capped and " (capped)" or ""))
	end
	if q.money > 0 then
		Line(ns.WQ_FormatGold(q.money))
	end
	for _, r in ipairs(q.reps) do
		Line(("+%d %s%s"):format(r.amount or 0, r.name or "?", r.max and " (max renown)" or ""))
	end
	if q.xp > 0 and #q.items + #q.currencies + #q.reps == 0 and q.money == 0 then
		Line(q.xp .. " experience")
	end
end

local function ShowTooltip(row)
	local q = row.quest
	local item = ns.WQ_MainItem(q)
	GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
	if item and item.index then
		-- The item's own tooltip, as on Blizzard's pin (Gear Check adds its verdict to it).
		GameTooltip:SetQuestLogItem("reward", item.index, q.id)
		QuestLines(q, true)
		RewardLines(q, item)
	else
		GameTooltip:SetText(q.title, GOLD[1], GOLD[2], GOLD[3])
		QuestLines(q, false)
		Line(" ")
		RewardLines(q)
	end
	Line(" ")
	Line(IsTracked(q) and "Click: stop tracking" or "Click: track it", GREY)
	Line(panel.kind == "continent" and "Right-click: open its zone" or "Right-click: untrack", GREY)
	Line("Shift-click: link in chat", GREY)
	GameTooltip:Show()
	if panel.preview then
		ns.ModelPreview_Show(panel.preview, db.preview and ModelFor(item) or nil)
	end
end

-- Rows ----------------------------------------------------------------------------------------------------------

local function OnRowClick(self, button)
	if self.section then
		db.collapsed[self.section] = not db.collapsed[self.section]
		Refresh()
		return
	end
	local q = self.quest
	if not q then
		return
	end
	if button == "LeftButton" then
		if IsShiftKeyDown() then
			InsertLink(GetQuestLink(q.id))
		else
			Track(q)
		end
	elseif button == "RightButton" then
		if panel.kind == "continent" and q.zoneID then
			WorldMapFrame:SetMapID(q.zoneID)
		else
			Untrack(q)
		end
	end
end

local function NewRow()
	local row = CreateFrame("Frame", nil, panel.scroll.content)
	row.isWQRow = true
	row:EnableMouse(true)
	row.hover = row:CreateTexture(nil, "BACKGROUND")
	row.hover:SetAllPoints()
	row.hover:SetColorTexture(1, 1, 1, 0.06)
	row.hover:Hide()
	row.tracked = row:CreateTexture(nil, "ARTWORK")
	row.tracked:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.9)
	row.tracked:SetWidth(2)
	row.tracked:SetPoint("TOPLEFT", 0, -3)
	row.tracked:SetPoint("BOTTOMLEFT", 0, 3)
	row.icon = row:CreateTexture(nil, "ARTWORK")
	row.icon:SetSize(ICON, ICON)
	row.icon:SetPoint("LEFT", 6, 0)
	row.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	row.right = UI.Text(row, 11, GREY)
	row.right:SetJustifyH("RIGHT")
	row.right:SetPoint("TOPRIGHT", -6, -4)
	row.name = UI.Text(row, 12, WHITE)
	row.name:SetWordWrap(false)
	row.name:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 8, 0)
	row.name:SetPoint("RIGHT", row.right, "LEFT", -6, 0)
	row.sub = UI.Text(row, 11, GREY)
	row.sub:SetWordWrap(false)
	row.sub:SetPoint("BOTTOMLEFT", row.icon, "BOTTOMRIGHT", 8, 0)
	row.sub:SetPoint("RIGHT", -6, 0)
	row.title = UI.Text(row, 12, GOLD)
	row.title:SetPoint("BOTTOMLEFT", 6, 4)
	row.toggle = UI.Text(row, 11, GREY)
	row.toggle:SetPoint("BOTTOMRIGHT", -6, 4)
	row.line = row:CreateTexture(nil, "ARTWORK")
	row.line:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.25)
	row.line:SetHeight(1)
	row.line:SetPoint("BOTTOMLEFT", 6, 1)
	row.line:SetPoint("BOTTOMRIGHT", -6, 1)
	row:SetScript("OnEnter", function(self)
		self.hover:SetShown(self.quest ~= nil or self.section ~= nil)
		if self.quest then
			ShowTooltip(self)
			ShowMarker(self.quest)
		end
	end)
	row:SetScript("OnLeave", function(self)
		self.hover:Hide()
		GameTooltip:Hide()
		HidePreview()
		HideMarker()
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
	row.quest, row.section = nil, section.key
	row.icon:Hide()
	row.name:Hide()
	row.sub:Hide()
	row.right:Hide()
	row.tracked:Hide()
	row.toggle:SetText(section.collapsed and "+" or "-")
	row.toggle:Show()
	row.title:SetText(("%s (%d)"):format(section.title, #section.quests))
	row.title:Show()
	row.line:Show()
end

local function SubText(q)
	local parts = {}
	if panel.kind == "continent" and q.zone then
		parts[#parts + 1] = q.zone
	end
	local tags = ns.WQ_Tags(q)
	if tags ~= "" then
		parts[#parts + 1] = tags
	end
	local main, secondary = ns.WQ_RewardText(q)
	parts[#parts + 1] = (q.section == "worth" and WORTH_COLOR or MAIN_COLOR) .. main .. "|r"
	if secondary then
		parts[#parts + 1] = secondary
	end
	return table.concat(parts, "  ·  ")
end

local function RowIcon(q)
	local kind, reward = ns.WQ_MainReward(q)
	if reward and reward.icon then
		return reward.icon
	elseif kind == "gold" then
		return GOLD_ICON
	elseif kind == "rep" then
		return REP_ICON
	end
	return NO_ICON
end

local function SetQuest(row, q)
	row.quest, row.section = q, nil
	row.title:Hide()
	row.toggle:Hide()
	row.line:Hide()
	row.icon:Show()
	row.name:Show()
	row.sub:Show()
	row.icon:SetTexture(RowIcon(q))
	row.icon:SetDesaturated(q.dim == true)
	row.name:SetText(q.title)
	local color = q.dim and GREY or WHITE
	row.name:SetTextColor(color[1], color[2], color[3])
	row.sub:SetText(SubText(q))
	local time, tier = ns.WQ_TimeText(q.seconds)
	row.right:SetText(time or "")
	local tc = TIME_COLORS[tier or "normal"]
	row.right:SetTextColor(tc[1], tc[2], tc[3])
	row.right:Show()
	row.tracked:SetShown(IsTracked(q))
end

-- Layout --------------------------------------------------------------------------------------------------------

local function Options()
	return { show = db.show, worth = db.worth, collapsed = db.collapsed, maxLevel = ns.WQ_MaxLevel() }
end

local function Count(sections)
	local n = 0
	for _, s in ipairs(sections) do
		n = n + #s.quests
	end
	return n
end

function Refresh()
	if not panel or not panel:IsShown() then
		return
	end
	-- Only our own tooltip goes (map pins use GameTooltip too); it comes back for the hovered row below. The model
	-- preview stays up so a redraw doesn't restart it.
	local owner = GameTooltip:GetOwner()
	local ours = owner and owner.isWQRow
	if ours then
		GameTooltip:Hide()
	end
	for i = 1, used do
		rows[i]:Hide()
		rows[i].hover:Hide()
		rows[i].quest, rows[i].section = nil, nil
	end
	used = 0
	clock = 0
	local quests, mapName, kind, _, loading = ns.WQ_ForMap(WorldMapFrame:GetMapID())
	panel.kind = kind
	pending = loading or 0
	if not quests then
		HidePreview()
		HideMarker()
		panel.note:SetText("")
		panel.empty:SetText("Open a zone or a continent to see its world quests.")
		panel.empty:Show()
		panel.scroll:SetContentHeight(1)
		return
	end
	local sections = ns.WQ_Sections(quests, Options())
	local count = Count(sections)
	local note = ("%s  ·  %d %s"):format(mapName, count, count == 1 and "quest" or "quests")
	if pending > 0 then
		note = note .. "  |cff999999·  loading rewards…|r"
	end
	panel.note:SetText(note)
	local y = 0
	for _, section in ipairs(sections) do
		local header = Row()
		header:SetHeight(HEADER_H)
		header:SetPoint("TOPLEFT", 0, -y)
		header:SetPoint("RIGHT")
		SetHeader(header, section)
		y = y + HEADER_H + 2
		if not section.collapsed then
			for _, q in ipairs(section.quests) do
				local row = Row()
				row:SetHeight(ROW_H)
				row:SetPoint("TOPLEFT", 0, -y)
				row:SetPoint("RIGHT")
				SetQuest(row, q)
				y = y + ROW_H
			end
		end
		y = y + 6
	end
	panel.empty:SetText(pending > 0 and "Loading world quests..." or "No world quests here.")
	panel.empty:SetShown(#sections == 0)
	panel.scroll:SetContentHeight(y)
	local hovered
	for i = 1, used do
		local row = rows[i]
		if row:IsMouseOver() and (row.quest or row.section) then
			row.hover:Show()
			if row.quest then
				ShowTooltip(row)
				hovered = row.quest
			end
		end
	end
	if ours and not hovered then
		HidePreview()
		HideMarker()
	end
end

local function OnUpdate(_, elapsed)
	tick, clock = tick + elapsed, clock + elapsed
	if tick < LOADING_TICK then
		return
	end
	tick = 0
	if pending > 0 or clock >= CLOCK_TICK then
		Refresh()
	end
end

local function Build()
	if panel then
		return
	end
	local _
	_, panel = ns.MapTabs_Add({
		key = KEY, icon = TAB_ICON, tooltip = "World quests",
		onMapChanged = function()
			Refresh()
		end,
		onHide = function()
			HideMarker()
		end,
	})
	if not panel then
		return
	end
	panel.note = UI.Text(panel, 11, GREY)
	panel.note:SetPoint("TOPLEFT", panel.title, "BOTTOMLEFT", 0, -4)
	panel.note:SetPoint("RIGHT", -10, 0)
	panel.note:SetWordWrap(false)
	panel.scroll = UI.Scroll(panel)
	panel.scroll:SetPoint("TOPLEFT", panel.note, "BOTTOMLEFT", -6, -8)
	panel.scroll:SetPoint("BOTTOMRIGHT", -10, 8)
	panel.empty = UI.Text(panel, 12, GREY)
	panel.empty:SetPoint("TOPLEFT", panel.scroll, "TOPLEFT", 6, -4)
	panel.empty:SetPoint("RIGHT", -10, 0)
	panel:SetScript("OnUpdate", OnUpdate)
	panel.preview = ns.ModelPreview_Create(panel)
	-- The tab stays selected while the map is closed, and reopening it on the same map isn't a map change.
	panel:HookScript("OnShow", function()
		Refresh()
	end)
end

-- API for WorldQuests.lua ---------------------------------------------------------------------------------------

function ns.WQTab_Init(moduleDB)
	db = moduleDB
end

function ns.WQTab_SetEnabled(enabled)
	if enabled then
		Build()
	end
	ns.MapTabs_SetShown(KEY, enabled)
end

function ns.WQTab_IsShown()
	return ns.MapTabs_IsActive(KEY) and WorldMapFrame:IsShown()
end

function ns.WQTab_Refresh()
	if ns.MapTabs_IsActive(KEY) then
		Refresh()
	end
end

-- /tomte wq open and the zone toast: the map on this tab.
function ns.WQTab_Open()
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
		ns.Print("open the map's quest log panel, then click the map tab.")
	end
end
