local addonName, ns = ...

-- Tomte's tabs in the world map's side panel, stacked under Blizzard's Map Legend tab (Teleports, Collect here,
-- World quests).
-- Only one content frame shows at a time: picking one of ours hides Blizzard's frames and our other panels;
-- picking one of Blizzard's tabs gives its frames back.
--
-- QuestMapFrame:SetDisplayMode is never called (that would taint the quest log's state). Blizzard's content frames are
-- hidden directly, and a hook on SetDisplayMode hands control back when one of Blizzard's tabs is used.
--
-- ns.MapTabs_Add({ key, icon, tooltip, title, onShow(panel), onHide(panel), onMapChanged(panel) }) -> tab, panel
-- ns.MapTabs_SetShown(key, shown), ns.MapTabs_Select(key), ns.MapTabs_IsActive(key), ns.MapTabs_Open(key)
-- ns.MapTabs_Opener(button, opensMap, dims): a Home button that opens the world map first (dimmed in combat).
-- ns.MapTabs_ResolveMap(mapID): which map a tab lists for the viewed map (shared by Collect here and World quests).

local UI = ns.UI
local MAX_MAP_DEPTH = 10

local tabs = {} -- in the order they were added: { key, spec, tab, panel, shown }
local byKey = {}
local activeKey
local hooked = false
local COMBAT_ALPHA = 0.45 -- an opener button in combat, when its click can't open the map
local dimmed = setmetatable({}, { __mode = "k" }) -- [opener button] = its opensMap, for buttons that dim in combat
local combatWatch, inCombat
local WatchCombat

local function Layout()
	local anchor = QuestMapFrame.MapLegendTab
	for _, t in ipairs(tabs) do
		if t.shown then
			t.tab:ClearAllPoints()
			t.tab:SetPoint("TOP", anchor, "BOTTOM", 0, -3)
			anchor = t.tab
		end
	end
end

local function Deactivate(t)
	t.tab:SetChecked(false)
	t.panel:Hide()
	if t.spec.onHide then
		t.spec.onHide(t.panel)
	end
end

-- Blizzard switched tabs (or re-selected the one it thinks is shown): give its frames back.
local function GiveBack(questMap)
	if not activeKey then
		return
	end
	local t = byKey[activeKey]
	activeKey = nil
	Deactivate(t)
	for _, frame in ipairs(questMap.ContentFrames) do
		frame:SetShown(frame.displayMode == questMap.displayMode)
	end
	for _, b in ipairs(questMap.TabButtons) do
		b:SetChecked(b.displayMode == questMap.displayMode)
	end
end

function ns.MapTabs_Select(key)
	local t = byKey[key]
	if not t or not t.shown then
		return
	end
	for _, frame in ipairs(QuestMapFrame.ContentFrames) do
		frame:Hide()
	end
	for _, b in ipairs(QuestMapFrame.TabButtons) do
		b:SetChecked(false)
	end
	if activeKey and activeKey ~= key then
		Deactivate(byKey[activeKey])
	end
	activeKey = key
	t.tab:SetChecked(true)
	t.panel:Show()
	if t.spec.onShow then
		t.spec.onShow(t.panel)
	end
end

function ns.MapTabs_IsActive(key)
	return activeKey == key
end

-- Shows tab key when the world map and its side panel are open (/tomte ... open, Home, zone toasts); otherwise says
-- how to get there. Never opens the map or sets its zone itself: a map shown or moved by addon code keeps that taint in
-- its saved map ID, and pressing M in combat on the same zone later gets Blizzard's own pin code blocked (measured
-- 12.1). Buttons open it first through ns.MapTabs_Opener. Returns true when the tab shows.
function ns.MapTabs_Open(key)
	local t = byKey[key]
	if not (t and t.shown) then
		return false
	end
	if not (WorldMapFrame:IsShown() and QuestMapFrame:IsShown()) then
		if InCombatLockdown() then
			ns.Print_Combat("open the map")
		else
			ns.Print(("open the map (M) with its side panel, then the %s tab."):format(t.spec.tooltip or key))
		end
		return false
	end
	ns.MapTabs_Select(key)
	return true
end

-- Combat dimming of opener buttons --------------------------------------------------------------------------------

-- The opener does nothing in combat (the template's click is refused): buttons that would open the map dim, and
-- their tooltips say why (ns.MapTabs_CombatTip).
local function WouldOpen(button)
	local opensMap = dimmed[button]
	return opensMap ~= nil and inCombat and opensMap(button, "LeftButton") and true or false
end

function ns.MapTabs_OpenerSync(button)
	if dimmed[button] then
		button:SetAlpha(WouldOpen(button) and COMBAT_ALPHA or 1)
	end
end

-- Adds the combat line to GameTooltip (the caller shows it) when button's click can't open the map right now.
function ns.MapTabs_CombatTip(button)
	if WouldOpen(button) then
		UI.TipLine("Can't open the map in combat", "warning")
	end
end

function WatchCombat()
	if combatWatch then
		return
	end
	-- Never unregistered: it only re-dims the opener buttons that are shown, and the Tomte window is core.
	combatWatch = CreateFrame("Frame")
	combatWatch:RegisterEvent("PLAYER_REGEN_DISABLED")
	combatWatch:RegisterEvent("PLAYER_REGEN_ENABLED")
	combatWatch:SetScript("OnEvent", function(_, event)
		-- PLAYER_REGEN_DISABLED fires just before the lockdown starts, so the event says it, not InCombatLockdown.
		inCombat = event == "PLAYER_REGEN_DISABLED"
		for button in pairs(dimmed) do
			if button:IsShown() then
				ns.MapTabs_OpenerSync(button)
			end
		end
	end)
	inCombat = InCombatLockdown()
end

-- Makes a button (created from InsecureActionButtonTemplate) open the world map with its side panel through
-- Blizzard's own code, so the map isn't tainted (see ns.MapTabs_Open): the click is passed to the quest log micro
-- button, whose OnClick runs ToggleQuestLog. Only out of combat (the template does nothing in combat).
-- opensMap(button, mouseButton) says whether this click should open the map. The button's own action goes in PostClick,
-- which runs after the map is open.
-- dims: the button dims in combat while its click would open the map (Home's blocks, rows, facts and the rail; not
-- toasts, which fade by their own alpha). After changing what decides opensMap, call ns.MapTabs_OpenerSync(button).
function ns.MapTabs_Opener(button, opensMap, dims)
	if dims then
		dimmed[button] = opensMap
		button:HookScript("OnShow", ns.MapTabs_OpenerSync)
		WatchCombat()
	end
	button:RegisterForClicks("LeftButtonUp")
	-- Else, with the ActionButtonUseKeyDown CVar on, the template acts on the down press, which this button never gets.
	button:SetAttribute("useOnKeyDown", false)
	button:SetScript("PreClick", function(self, mouseButton)
		-- Already open: ToggleQuestLog would close it.
		local open = QuestLogMicroButton ~= nil and not InCombatLockdown() and opensMap(self, mouseButton)
			and not (WorldMapFrame:IsShown() and QuestMapFrame:IsShown())
		self:SetAttribute("type", open and "click" or nil)
		self:SetAttribute("clickbutton", open and QuestLogMicroButton or nil)
	end)
end

function ns.MapTabs_SetShown(key, shown)
	local t = byKey[key]
	if not t then
		return
	end
	t.shown = shown and true or false
	t.tab:SetShown(t.shown)
	if not t.shown and activeKey == key then
		GiveBack(QuestMapFrame)
	end
	Layout()
end

local function CreateTab(spec)
	local tab = CreateFrame("Frame", nil, QuestMapFrame, "LargeSideTabButtonTemplate")
	tab.tooltipText = spec.tooltip
	tab.Icon:SetTexture(spec.icon)
	tab.Icon:SetSize(24, 24)
	tab.Icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	function tab:SetChecked(checked)
		self.Icon:SetDesaturated(not checked)
		self.Icon:SetAlpha(checked and 1 or 0.7)
		self.SelectedTexture:SetShown(checked)
	end
	tab:SetChecked(false)
	tab:SetCustomOnMouseUpHandler(function(_, button, upInside)
		if button == "LeftButton" and upInside then
			ns.MapTabs_Select(spec.key)
		end
	end)
	return tab
end

local function CreatePanel(spec)
	local panel = CreateFrame("Frame", nil, QuestMapFrame)
	panel:SetPoint("TOPLEFT", QuestMapFrame.ContentsAnchor, "TOPLEFT")
	-- -22: the right inset Blizzard's own content frames use (QuestsFrame, MapLegend in QuestMapFrame.xml).
	panel:SetPoint("BOTTOMRIGHT", QuestMapFrame.ContentsAnchor, "BOTTOMRIGHT", -22, 0)
	panel:Hide()
	panel.look = UI.Panel(panel, { size = "medium", alpha = 0.96 })
	panel.title = UI.Text(panel, 14, "heading", "title")
	panel.title:SetPoint("TOPLEFT", 10, -10)
	panel.title:SetText(spec.title or spec.tooltip)
	return panel
end

local function Hook()
	if hooked then
		return
	end
	hooked = true
	hooksecurefunc(QuestMapFrame, "SetDisplayMode", GiveBack)
	hooksecurefunc(WorldMapFrame, "OnMapChanged", function()
		local t = activeKey and byKey[activeKey]
		if t and t.spec.onMapChanged then
			t.spec.onMapChanged(t.panel)
		end
	end)
end

-- Returns tab, panel (the same ones when the key was added before), or nil when the map's side panel isn't there.
function ns.MapTabs_Add(spec)
	local existing = byKey[spec.key]
	if existing then
		return existing.tab, existing.panel
	end
	if not QuestMapFrame or not QuestMapFrame.MapLegendTab then
		return nil
	end
	local t = { key = spec.key, spec = spec, shown = true }
	t.tab = CreateTab(spec)
	t.panel = CreatePanel(spec)
	tabs[#tabs + 1] = t
	byKey[spec.key] = t
	Hook()
	Layout()
	return t.tab, t.panel
end

-- The map to list for a viewed map: zones and dungeons as they are, micro and orphan maps up to their zone,
-- continents as a whole. Returns mapID, info, "zone" | "continent", or nil for the world and cosmic maps.
function ns.MapTabs_ResolveMap(mapID)
	local depth = 0
	while mapID and mapID > 0 and depth < MAX_MAP_DEPTH do
		local info = C_Map.GetMapInfo(mapID)
		if not info then
			return nil
		end
		local t = info.mapType
		if t == Enum.UIMapType.Zone or t == Enum.UIMapType.Dungeon then
			return mapID, info, "zone"
		elseif t == Enum.UIMapType.Continent then
			return mapID, info, "continent"
		elseif t == Enum.UIMapType.World or t == Enum.UIMapType.Cosmic then
			return nil
		end
		mapID, depth = info.parentMapID, depth + 1
	end
	return nil
end
