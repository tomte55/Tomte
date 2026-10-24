local addonName, ns = ...

-- Housing decor: a nicer View Houses window (right-click a player > View Houses). Blizzard's window (HouseListFrame in
-- Blizzard_HouseList, loaded on demand) stays: its title, close button, place and the menu entry are Blizzard's. Its
-- fold-out rows are hidden and Tomte shows one open card per house instead, with the neighborhood's picture across
-- the card (its housing loading screen, picked in EditorData.lua; a neighborhood not there gets the blurred
-- "housing-dashboard-bg-<suffix>" art Blizzard's House Finder uses) and a Visit button. The window isn't replaced: Plumber's swap of the HouseListFrame global taints the unit menu until a /reload.
-- Art crop in EditorData.lua; registered in Decor.lua.

local CARD_H = 112 -- the name, two lines and the button with room between them
local PAD = 14 -- inside a card, around its text and button
local GAP = 8 -- between the cards and around them
local HEADER = 34 -- Blizzard's wood title strip
local MAX_SHOWN = 3 -- cards before the list scrolls
local ART_FOCUS_Y = 0.4 -- which band of a fallback picture shows (0 = top): the houses, not the sky or the ground
local SHADE_SHARE = 0.75 -- part of the card's width, from the left, darkened behind the text
local SHADE_ALPHA = 0.9 -- the shade at the card's left edge, fading to none
local VISIT_W = 120
local VISIT_H = 22
local SEPARATOR = "  \194\183  " -- a middle dot between owner and plot
-- Fallback for a neighborhood EditorData.lua has no picture for: Blizzard's dashboard art (blurred, but there).
local ART_PREFIX = "housing-dashboard-bg-" -- + C_Housing.GetNeighborhoodTextureSuffix (Blizzard_HousingHouseFinder)
local UI = ns.UI

local OWNER = "houselist"
local events = ns.Decor_Events

local db
local active = false
local hooked = false
local list -- the HouseInfo list Blizzard's window shows now (nil while it loads)
local applied = false -- our cards stand in for Blizzard's rows
local holder -- our scroll frame inside Blizzard's window
local cards = {}

local function On()
	return active and db.houseList == true
end

-- Blizzard's own window: nil before Blizzard_HouseList loads, or when another addon put its own frame under that name.
local function Window()
	local frame = HouseListFrame
	if frame and frame.ScrollBox and frame.ScrollBar then
		return frame
	end
	return nil
end

-- The neighborhood picture as an AtlasInfo-shaped table, or nil for a neighborhood without one.
local function ArtInfo(house)
	if not (C_Housing.GetNeighborhoodTextureSuffix and house.neighborhoodGUID) then
		return nil
	end
	local ok, suffix = pcall(C_Housing.GetNeighborhoodTextureSuffix, house.neighborhoodGUID)
	if not ok or type(suffix) ~= "string" or suffix == "" then
		return nil
	end
	return ns.DecorEditor_NeighborhoodArt(suffix) or C_Texture.GetAtlasInfo(ART_PREFIX .. suffix)
end

-- Cards ---------------------------------------------------------------------------------------------------------------

local function Layout(card)
	local w, h = card:GetSize()
	card.shade:SetWidth(math.max(w * SHADE_SHARE, 1))
	local info = card.artInfo
	local l, r, t, b = ns.DecorEditor_ArtCrop(info, math.max(w - 2, 1) / math.max(h - 2, 1),
		info and info.focusY or ART_FOCUS_Y)
	card.art:SetShown(l ~= nil)
	card.shade:SetShown(l ~= nil)
	if l then
		card.art:SetTexture(info.file or info.filename)
		card.art:SetTexCoord(l, r, t, b)
	end
end

local function VisitLook(card)
	UI.SetTextRole(card.visit.label, InCombatLockdown() and "textFaint" or "heading")
end

local function VisitEnter(button)
	if InCombatLockdown() then
		GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
		UI.TipLine(ERR_HOUSING_RESULT_LOCKED_BY_COMBAT or "Not in combat.", "danger", true)
		GameTooltip:Show()
	end
end

local function VisitLeave(button)
	if GameTooltip:GetOwner() == button then
		GameTooltip:Hide()
	end
end

local function VisitPostClick()
	if not InCombatLockdown() and SOUNDKIT.HOUSING_SOCIAL_MENU_VISIT_HOUSE then
		PlaySound(SOUNDKIT.HOUSING_SOCIAL_MENU_VISIT_HOUSE)
	end
end

local function Line(card, above, gap)
	local fs = UI.Text(card, 12, "text")
	fs:SetPoint("TOPLEFT", above, "BOTTOMLEFT", 0, -gap)
	fs:SetPoint("RIGHT", -PAD, 0)
	fs:SetWordWrap(false)
	return fs
end

local function CreateCard(i)
	local card = CreateFrame("Frame", nil, holder.content)
	card:SetHeight(CARD_H)
	card:SetPoint("TOPLEFT", 0, -(i - 1) * (CARD_H + GAP))
	card:SetPoint("TOPRIGHT", 0, -(i - 1) * (CARD_H + GAP))
	card.bg = UI.Surface(card, 0.5)
	card.art = card:CreateTexture(nil, "BORDER")
	card.art:SetPoint("TOPLEFT", 1, -1)
	card.art:SetPoint("BOTTOMRIGHT", -1, 1)
	card.shade = card:CreateTexture(nil, "BORDER", nil, 1)
	card.shade:SetPoint("TOPLEFT", card.art)
	card.shade:SetPoint("BOTTOMLEFT", card.art)
	card.shade:SetColorTexture(1, 1, 1, 1)
	card.name = UI.Text(card, 15, "heading", "title")
	card.name:SetPoint("TOPLEFT", PAD, -PAD)
	card.name:SetPoint("RIGHT", -PAD, 0)
	card.name:SetWordWrap(false)
	card.info = Line(card, card.name, 7)
	card.neighborhood = Line(card, card.info, 4)
	card.visit = UI.Button(card, VISIT_W, VIEW_HOUSES_VISIT_BUTTON)
	card.visit:SetHeight(VISIT_H)
	card.visit:SetPoint("BOTTOMLEFT", PAD, PAD)
	card.visit:HookScript("OnEnter", VisitEnter)
	card.visit:HookScript("OnLeave", VisitLeave)
	-- C_Housing.VisitHouse is restricted: a click on Blizzard's "visithouse" secure action does it. The insecure
	-- template runs it out of combat only, isn't protected (so it can sit on this ordinary frame) and passes the hover to
	-- the themed button under it.
	card.action = CreateFrame("Button", nil, card.visit, "InsecureActionButtonTemplate")
	card.action:SetAllPoints()
	card.action:SetPropagateMouseMotion(true)
	card.action:RegisterForClicks("AnyUp")
	card.action:SetAttribute("useOnKeyDown", false)
	card.action:SetAttribute("type", "visithouse")
	card.action:SetScript("PostClick", VisitPostClick)
	card:SetScript("OnSizeChanged", Layout)
	cards[i] = card
	return card
end

local function Label(label, value)
	return UI.Wrap(label, "textMuted") .. " " .. (value or "")
end

-- "Owner: Gingerbeard · Plot #1", and the neighborhood below only when the house name doesn't already say it.
local function SetCard(card, house)
	card.name:SetText(house.houseName or "")
	card.info:SetText(Label(HOUSING_DASHBOARD_OWNER_LABEL, house.ownerName) .. UI.Wrap(SEPARATOR, "textFaint")
		.. HOUSING_PLOT_NUMBER:format(house.plotID or 0))
	local showNeighborhood = ns.DecorEditor_ShowNeighborhood(house.houseName, house.neighborhoodName)
	card.neighborhood:SetText(showNeighborhood and Label(HOUSING_DASHBOARD_NEIGHBORHOOD_LABEL, house.neighborhoodName)
		or "")
	card.action:SetAttribute("house-neighborhood-guid", house.neighborhoodGUID)
	card.action:SetAttribute("house-guid", house.houseGUID)
	card.action:SetAttribute("house-plot-id", house.plotID)
	-- Theme colors read on every fill, so a theme switch reaches them.
	card.shade:SetGradient("HORIZONTAL", UI.ColorObject("surface", SHADE_ALPHA), UI.ColorObject("surface", 0))
	card.artInfo = ArtInfo(house)
	Layout(card)
	VisitLook(card)
end

-- Window --------------------------------------------------------------------------------------------------------------

local function CreateHolder(frame)
	holder = UI.Scroll(frame)
	holder:SetPoint("TOPLEFT", GAP + 2, -HEADER)
	holder:SetPoint("BOTTOMRIGHT", -14, GAP)
end

local function Fill()
	local frame = Window()
	if not frame then
		return
	end
	if not holder then
		CreateHolder(frame)
	end
	applied = true
	frame.ScrollBox:Hide()
	frame.ScrollBar:Hide()
	local houses = list or {}
	for i, house in ipairs(houses) do
		local card = cards[i] or CreateCard(i)
		SetCard(card, house)
		card:Show()
	end
	for i = #houses + 1, #cards do
		cards[i]:Hide()
	end
	local shown = ns.DecorEditor_CardsShown(#houses, MAX_SHOWN)
	frame:SetHeight(HEADER + shown * (CARD_H + GAP) + GAP)
	holder:Show()
	holder:SetContentHeight(#houses * (CARD_H + GAP) - GAP)
	holder:SetScroll(0)
end

-- Blizzard's rows back. Its list was filled while hidden; a window open right now shows them on its next open.
local function Restore()
	local frame = Window()
	if not (applied and frame) then
		return
	end
	applied = false
	holder:Hide()
	frame.ScrollBox:Show()
	frame.ScrollBar:Show()
	if frame.UpdateHeight then
		frame:UpdateHeight(list and #list or 0)
	end
end

-- Runs after Blizzard filled its own list (nil first, while it asks the server). Hooks can't be undone: it checks On.
local function OnListUpdated(_, houses)
	list = houses
	if On() then
		Fill()
	end
end

local function Hook()
	local frame = Window()
	if hooked or not frame then
		return
	end
	hooked = true
	hooksecurefunc(frame, "OnHouseListUpdated", OnListUpdated)
end

events:On(OWNER, "ADDON_LOADED", function(_, name)
	if name == "Blizzard_HouseList" then
		events:Unwatch(OWNER, "ADDON_LOADED")
		Hook()
	end
end)

local function CombatChanged()
	if applied then
		for _, card in ipairs(cards) do
			VisitLook(card)
		end
	end
end
events:On(OWNER, "PLAYER_REGEN_DISABLED", CombatChanged)
events:On(OWNER, "PLAYER_REGEN_ENABLED", CombatChanged)

local function Watch()
	events:UnwatchAll(OWNER)
	if not On() then
		Restore()
		return
	end
	events:Watch(OWNER, "PLAYER_REGEN_DISABLED")
	events:Watch(OWNER, "PLAYER_REGEN_ENABLED")
	if C_AddOns.IsAddOnLoaded("Blizzard_HouseList") then
		Hook()
	else
		events:Watch(OWNER, "ADDON_LOADED")
	end
	local frame = Window()
	if frame and frame:IsShown() and list then
		Fill()
	end
end

-- Called by Decor.lua -------------------------------------------------------------------------------------------------

function ns.DecorHouseList_Init(moduleDB)
	db = moduleDB
end

function ns.DecorHouseList_Start()
	active = true
	Watch()
end

function ns.DecorHouseList_Stop()
	active = false
	Watch()
end

-- The View Houses setting changed.
function ns.DecorHouseList_Apply()
	Watch()
end
