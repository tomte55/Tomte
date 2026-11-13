local addonName, ns = ...

-- The Forever theme's rail: Home, the pages and the world map tabs as icon tabs on the window's right edge, like the
-- Character window's. Same job and interface as Rail.lua (rail:Refresh(selected)). Forever only (tools/forever_list.lua);
-- Panel.lua picks it when Theme.panel is "forever". Art: LargeSideTabButtonTemplate. It's a Frame there, and a map tab has
-- to be a secure Button (ns.MapTabs_Opener), so the tabs are built here from the same atlases.

local TAB_ATLAS = "common-sidetab"
local TAB_HEIGHT_TRIM = 5 -- the art's transparent space, so tabs stack without gaps (SidePanelTabButtonMixin)
local ICON_SIZE = 50 -- fills the tab's inside, as fillToInterior does; the mask rounds it
local ICON_L, ICON_R = 0.03, 0.97 -- trims a spell icon's own border, as fillToInterior does
local ICON_X = -4 -- the Camelot tab art has more empty space on the right (Camelot/SharedUIPanelTemplates.lua)
local TOP_OFFSET = 30 -- where the column starts below the window's top (CharacterFrameModeTabs)
local BOTTOM_ROOM = 8
local MAP_GAP = 10 -- between the pages and the map tabs
local MIN_SCALE = 0.5 -- past this an icon can't be told apart; the column runs past the window instead

local UI = ns.UI
local Kit = ns.HomeKit

-- The page's count on its icon, and its line in the tooltip.
local function UpdatePill(tab)
	local text, tip = ns.PanelRail_Pill(tab.entry)
	tab.pill:SetText(text)
	tab.pillTip = text ~= "" and tip or nil
end

local function CreateTab(parent, onSelect, width, height)
	-- Map tabs open the world map first (ns.MapTabs_Opener); the tab's own click is its PostClick.
	local tab = CreateFrame("Button", nil, parent, "InsecureActionButtonTemplate")
	ns.MapTabs_Opener(tab, function(self)
		return self.entry ~= nil and self.entry.kind == "map"
	end, true)
	tab:SetSize(width, height)
	tab.back = tab:CreateTexture(nil, "BACKGROUND")
	tab.back:SetAtlas(TAB_ATLAS, true)
	tab.back:SetPoint("CENTER")
	tab.icon = tab:CreateTexture(nil, "ARTWORK")
	tab.icon:SetSize(ICON_SIZE, ICON_SIZE)
	tab.icon:SetPoint("CENTER", ICON_X, 0)
	local mask = tab:CreateMaskTexture()
	mask:SetAtlas("common-sidetab-mask", true)
	mask:SetPoint("CENTER")
	tab.icon:AddMaskTexture(mask)
	tab.selected = tab:CreateTexture(nil, "OVERLAY")
	tab.selected:SetAtlas("common-sidetab-selected", true)
	tab.selected:SetPoint("CENTER")
	tab.selected:Hide()
	local hover = tab:CreateTexture(nil, "HIGHLIGHT")
	hover:SetAtlas("common-sidetab-hover", true)
	hover:SetPoint("CENTER")

	tab.pill = UI.Text(tab, 12, "text", "number")
	tab.pill:SetPoint("BOTTOMRIGHT", ICON_X - 4, 6)
	tab.pill:SetJustifyH("RIGHT")
	tab.pill:SetShadowColor(0, 0, 0, 1)

	tab:SetScript("OnEnter", function(self)
		if self.entry then
			ns.PanelRail_Tooltip(self)
		else
			-- The rail's Home row says its name; a tab has only its icon.
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:SetText("Home", UI.Color("heading"))
			GameTooltip:Show()
		end
	end)
	tab:SetScript("OnLeave", function()
		GameTooltip:Hide()
	end)
	tab:SetScript("OnMouseDown", function(self)
		self.icon:SetPoint("CENTER", ICON_X + 1, -1)
	end)
	tab:SetScript("OnMouseUp", function(self)
		self.icon:SetPoint("CENTER", ICON_X, 0)
	end)
	tab:SetScript("PostClick", function(self)
		onSelect(self.entry)
	end)
	return tab
end

-- window: the frame the column hangs on. onSelect(entry) runs on a click; entry is nil for the Home tab.
function ns.PanelRail_CreateTabs(parent, window, onSelect)
	local info = C_Texture.GetAtlasInfo(TAB_ATLAS)
	local tabW, tabH = info.width, info.height - TAB_HEIGHT_TRIM
	local rail = CreateFrame("Frame", nil, parent)
	rail:SetWidth(tabW)
	local tabs = {}
	local columnH = 0

	-- A long column shrinks to fit the window, so no page ends up out of reach. The anchor's offset is in the rail's own
	-- scale.
	local function Fit()
		local room = window:GetHeight() - TOP_OFFSET - BOTTOM_ROOM
		local scale = columnH > 0 and math.max(math.min(room / columnH, 1), MIN_SCALE) or 1
		rail:SetScale(scale)
		rail:ClearAllPoints()
		rail:SetPoint("TOPLEFT", window, "TOPRIGHT", 0, -TOP_OFFSET / scale)
	end
	window:HookScript("OnSizeChanged", Fit)

	local function Place(i, entry, y, selected)
		local tab = tabs[i]
		if not tab then
			tab = CreateTab(rail, onSelect, tabW, tabH)
			tabs[i] = tab
		end
		tab.entry = entry
		ns.MapTabs_OpenerSync(tab)
		ns.PanelRail_SetIcon(tab.icon, entry)
		if not (entry and entry.atlas) then
			tab.icon:SetTexCoord(ICON_L, ICON_R, ICON_L, ICON_R) -- an atlas on this tab before left its own
		end
		tab.selected:SetShown(selected)
		UpdatePill(tab)
		tab:ClearAllPoints()
		tab:SetPoint("TOPLEFT", rail, "TOPLEFT", 0, -y)
		tab:Show()
	end

	-- Counts change without the rail redrawing, so they alone are re-read once a second while it shows (as Rail.lua).
	local PILL_EVERY = 1
	local since = 0
	local UpdatePills = ns.Perf_Wrap(function()
		for _, tab in ipairs(tabs) do
			if tab:IsShown() and tab.entry then
				UpdatePill(tab)
			end
		end
	end, "OnUpdate")
	-- The frames in between return before the timing wrapper: no Performance bookkeeping on them.
	rail:SetScript("OnUpdate", function(_, elapsed)
		since = since + elapsed
		if since < PILL_EVERY then
			return
		end
		since = 0
		UpdatePills()
	end)

	-- selected: the open page's entry, or nil on Home.
	function rail:Refresh(selected)
		local n, y = 1, 0
		Place(1, nil, y, selected == nil)
		y = y + tabH
		for _, entry in ipairs(ns.HomeRailPages()) do
			n = n + 1
			Place(n, entry, y, entry == selected)
			y = y + tabH
		end
		local maps = ns.HomeEntries("map")
		if #maps > 0 then
			y = y + MAP_GAP
			for _, entry in ipairs(maps) do
				n = n + 1
				Place(n, entry, y, false)
				y = y + tabH
			end
		end
		for i = n + 1, #tabs do
			tabs[i]:Hide()
		end
		columnH = y
		self:SetHeight(y)
		Fit()
	end

	Fit()
	return rail
end
