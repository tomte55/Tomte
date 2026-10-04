local addonName, ns = ...

-- Tomte's tabs in the world map's side panel, stacked under Blizzard's Map Legend tab (Teleports, Collect here).
-- Only one content frame shows at a time: picking one of ours hides Blizzard's frames and our other panels;
-- picking one of Blizzard's tabs gives its frames back.
--
-- QuestMapFrame:SetDisplayMode is never called (that would taint the quest log's state). Blizzard's content frames are
-- hidden directly, and a hook on SetDisplayMode hands control back when one of Blizzard's tabs is used.
--
-- ns.MapTabs_Add({ key, icon, tooltip, title, onShow(panel), onHide(panel), onMapChanged(panel) }) -> tab, panel
-- ns.MapTabs_SetShown(key, shown), ns.MapTabs_Select(key), ns.MapTabs_IsActive(key)

local UI = ns.UI

local tabs = {} -- in the order they were added: { key, spec, tab, panel, shown }
local byKey = {}
local activeKey
local hooked = false

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
	panel:SetPoint("BOTTOMRIGHT", QuestMapFrame.ContentsAnchor, "BOTTOMRIGHT", -22, 0)
	panel:Hide()
	panel.bg = panel:CreateTexture(nil, "BACKGROUND")
	panel.bg:SetAllPoints()
	panel.bg:SetColorTexture(0.06, 0.06, 0.07, 0.94)
	panel.title = UI.Text(panel, 14, UI.GOLD)
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
