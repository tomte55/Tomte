local addonName, ns = ...

-- Bags: the item buttons. Blizzard's own container item button template (not protected: buttons can be made and moved
-- in combat), one per bag slot, painted with Blizzard's item button functions plus Tomte's marks in the corners the
-- player picked (Data.lua decides which mark wins a shared corner) and the free-slot count. Blizzard's click code reads the bag from the button's
-- parent (a holder frame per bag, holder:SetID(bag)) and the slot from button:SetID(slot); nothing else is written
-- on the buttons for it, so using an item stays Blizzard's untainted code (ContainerFrame.lua,
-- ContainerFrameItemButton_OnClick). Our overlays live in a side table, not as fields on Blizzard's buttons.

local TEMPLATE = "ContainerFrameItemButtonTemplate"
local BUTTON = 37 -- the template's own size; ours are scaled from it (its art doesn't resize)
-- The transmog badge (on a 37 px button; the button's scale shrinks it with the icon): a dark ring, a filled disc,
-- a white diamond in the middle.
local BADGE, BADGE_RING, BADGE_GEM = 16, 2, 5
local SET_MARK = 6 -- the equipment set square's side
local REAGENT_ATLAS = "bags-icon-reagents" -- Blizzard's reagent bag filter icon, on empty reagent slots
local LEAF, LEAF_ALPHA = 20, 0.5
local ARROW_SCALE = 0.85 -- Gear Check's arrow on a full-size button; the button's own scale shrinks it further
local INSET = 2 -- a corner overlay's distance from the button's edges
-- A corner's x and y direction away from its edges.
local CORNER_DIRS = {
	TOPLEFT = { 1, -1 }, TOPRIGHT = { -1, -1 }, BOTTOMLEFT = { 1, 1 }, BOTTOMRIGHT = { -1, 1 },
}

local UI = ns.UI

local host -- the window frame the buttons are placed on (ns.BagsButtons_SetHost)
local holders = {} -- [bag] = holder frame
local buttons = {} -- [bag * 1000 + slot] = button
local extras = {} -- [button] = { ilvl, pet, mark, set, craft, free, fontSize, arrows = { [kind] = widget } }
local mouseOn = true -- false while an item from outside the bags is on the cursor (ns.BagsButtons_SetMouse)

local function Holder(bag)
	local holder = holders[bag]
	if not holder then
		holder = CreateFrame("Frame", nil, host)
		holder:SetID(bag)
		holder:SetAllPoints()
		holders[bag] = holder
	end
	return holder
end

-- Number overlays (item level, pet level, free slots) at the chosen size, outlined so they read on any icon.
local function SetNumberFont(e, size)
	if e.fontSize ~= size then
		e.fontSize = size
		UI.SetFont(e.ilvl, "number", size, "OUTLINE")
		UI.SetFont(e.pet, "number", size, "OUTLINE")
		UI.SetFont(e.craft.count, "number", size - 1, "OUTLINE")
		UI.SetFont(e.free, "number", size + 1, "OUTLINE")
	end
end

-- The crafting list's mark: its count on a dark plate with an accent edge (as Alts/List.lua draws it in Baganator).
local function CraftMark(button)
	local f = CreateFrame("Frame", nil, button)
	f:SetSize(22, 14)
	local bg = f:CreateTexture(nil, "ARTWORK")
	bg:SetAllPoints()
	bg:SetColorTexture(0, 0, 0, 0.75)
	local edge = f:CreateTexture(nil, "OVERLAY")
	edge:SetColorTexture(UI.Color("accent"))
	edge:SetPoint("BOTTOMLEFT")
	edge:SetPoint("BOTTOMRIGHT")
	edge:SetHeight(1)
	f.count = f:CreateFontString(nil, "OVERLAY")
	f.count:SetPoint("CENTER")
	return f
end

-- The transmog badge: its disc (badge.fill) takes the color.
local function Badge(button)
	local badge = CreateFrame("Frame", nil, button)
	badge:SetSize(BADGE, BADGE)
	badge:SetFrameLevel(button:GetFrameLevel() + 3)
	local ring = badge:CreateTexture(nil, "ARTWORK", nil, 1)
	ring:SetAllPoints()
	ring:SetColorTexture(0, 0, 0, 0.9)
	UI.CircleMask(ring, badge)
	badge.fill = badge:CreateTexture(nil, "ARTWORK", nil, 2)
	badge.fill:SetPoint("TOPLEFT", BADGE_RING, -BADGE_RING)
	badge.fill:SetPoint("BOTTOMRIGHT", -BADGE_RING, BADGE_RING)
	UI.CircleMask(badge.fill, badge)
	local gem = badge:CreateTexture(nil, "ARTWORK", nil, 3)
	gem:SetSize(BADGE_GEM, BADGE_GEM)
	gem:SetPoint("CENTER")
	gem:SetColorTexture(1, 1, 1, 1)
	gem:SetRotation(math.pi / 4)
	return badge
end

local function Extras(button)
	local e = extras[button]
	if e then
		return e
	end
	e = { arrows = {} }
	e.ilvl = button:CreateFontString(nil, "OVERLAY")
	e.pet = button:CreateFontString(nil, "OVERLAY")
	e.mark = Badge(button)
	e.set = button:CreateTexture(nil, "OVERLAY", nil, 2)
	e.set:SetSize(SET_MARK, SET_MARK)
	e.craft = CraftMark(button)
	e.free = button:CreateFontString(nil, "OVERLAY")
	e.free:SetPoint("BOTTOMRIGHT", -3, 3)
	e.leaf = button:CreateTexture(nil, "OVERLAY", nil, 1)
	e.leaf:SetAtlas(REAGENT_ATLAS)
	e.leaf:SetSize(LEAF, LEAF)
	e.leaf:SetPoint("CENTER")
	e.leaf:SetAlpha(LEAF_ALPHA)
	extras[button] = e
	return e
end

function ns.BagsButtons_SetHost(frame)
	host = frame
end

-- The button for one bag slot, made on first use.
function ns.BagsButtons_Get(bag, slot)
	local key = bag * 1000 + slot
	local button = buttons[key]
	if not button then
		button = CreateFrame("ItemButton", nil, Holder(bag), TEMPLATE)
		button:SetID(slot)
		button:EnableMouse(mouseOn)
		buttons[key] = button
	end
	return button
end

-- Puts region in a corner of the button ("TOPLEFT", ...), extra pixels further in; false when the corner is "off".
local function Corner(region, corner, extra)
	local dir = CORNER_DIRS[corner]
	if not dir then
		return false
	end
	local inset = INSET + (extra or 0)
	region:ClearAllPoints()
	region:SetPoint(corner, dir[1] * inset, dir[2] * inset)
	return true
end

-- Gear Check's arrow of this kind ("upgrade", "maybe", "alt"), made on first use.
local function Arrow(button, e, kind)
	local widget = e.arrows[kind]
	if not widget then
		widget = ns.Gear_Arrow(button, ns.GEAR_ARROW_ROLES[kind])
		widget:SetScale(ARROW_SCALE)
		e.arrows[kind] = widget
	end
	return widget
end

-- Hides every mark (empty slots, and before an item's marks are placed).
local function HideMarks(button, e)
	e.ilvl:Hide()
	e.pet:Hide()
	e.mark:Hide()
	e.set:Hide()
	e.craft:Hide()
	for _, widget in pairs(e.arrows) do
		widget:Hide()
	end
	if button.JunkIcon then
		button.JunkIcon:Hide()
	end
end

-- The marks an item carries (Data.lua's BAGS_MARKS keys), placed in their corners: the first of each corner wins.
local function PlaceMarks(button, e, item, opts)
	HideMarks(button, e)
	local crafting = ns.AltsList_Marked and ns.AltsList_Marked(item.itemID)
	local has = {
		junk = item.junk, upgrade = item.upgrade, crafting = crafting, transmog = item.look, set = item.set ~= nil,
		petlevel = item.petLevel, ilvl = item.ilvl and item.ilvl > 1,
	}
	for corner, mark in pairs(ns.Bags_CornerMarks(has, opts.corners)) do
		if mark == "junk" and button.JunkIcon then
			Corner(button.JunkIcon, corner, -1)
			button.JunkIcon:Show()
		elseif mark == "upgrade" then
			local widget = Arrow(button, e, item.upgrade)
			Corner(widget, corner, -INSET)
			widget:Show()
		elseif mark == "crafting" then
			e.craft.count:SetText(crafting)
			UI.SetTextRole(e.craft.count, "accent")
			Corner(e.craft, corner, -1)
			e.craft:Show()
		elseif mark == "transmog" then
			e.mark.fill:SetColorTexture(UI.Color(item.look == "you" and "accent" or "textMuted"))
			Corner(e.mark, corner, -1)
			e.mark:Show()
		elseif mark == "set" then
			e.set:SetColorTexture(UI.Color("info"))
			Corner(e.set, corner, 1)
			e.set:Show()
		elseif mark == "petlevel" then
			e.pet:SetText(item.petLevel)
			UI.SetTextRole(e.pet, "text")
			Corner(e.pet, corner)
			e.pet:Show()
		elseif mark == "ilvl" then
			e.ilvl:SetText(item.ilvl)
			if opts.ilvlColor == "quality" and item.quality then
				local r, g, b = C_Item.GetItemQualityColor(item.quality) -- its 4th return is a hex string, not alpha
				e.ilvl:SetTextColor(r, g, b)
			else
				UI.SetTextRole(e.ilvl, "text")
			end
			Corner(e.ilvl, corner)
			e.ilvl:Show()
		end
	end
end

-- Puts a button at x, y (pixels from the host's top-left) at size pixels.
function ns.BagsButtons_Place(button, x, y, size)
	local scale = size / BUTTON
	button:SetScale(scale)
	button:ClearAllPoints()
	button:SetPoint("TOPLEFT", host, "TOPLEFT", x / scale, -y / scale)
end

-- Paints a button for its record. opts: matches (false: faded by the search), free (the free-slot count an Empty
-- slot shows, or nil), corners ([mark] = "TOPLEFT" | "TOPRIGHT" | "BOTTOMLEFT" | "BOTTOMRIGHT" | "off"), ilvlColor
-- ("quality" | "plain"), fontSize, newGlow, greyJunk, redUnusable, context (fade items that don't fit the open
-- window: Blizzard's item context matching).
function ns.BagsButtons_Paint(button, item, opts)
	local e = Extras(button)
	SetNumberFont(e, opts.fontSize)
	ClearItemButtonOverlay(button)
	if item.empty then
		button:SetHasItem(nil)
		button:SetItemButtonTexture(nil)
		SetItemButtonQuality(button, nil)
		SetItemButtonCount(button, 0)
		SetItemButtonDesaturated(button, false)
		SetItemButtonTextureVertexColor(button, 1, 1, 1)
		button:UpdateNewItem(nil)
		button:UpdateJunkItem(nil, true)
		button:UpdateQuestItem(false, nil, nil)
		button:UpdateCooldown(nil)
		button:SetReadable(false)
		HideMarks(button, e)
		UI.SetTextRole(e.free, "textMuted")
		e.free:SetText(opts.free and ns.Thousands(opts.free) or "")
		e.leaf:SetShown(opts.free ~= nil and item.kind == "reagent") -- Empty's buttons only, not a kept place
	else
		button:SetHasItem(item.icon)
		button:SetItemButtonTexture(item.icon)
		SetItemButtonQuality(button, item.quality, item.link, false, item.bind == "soulbound")
		SetItemButtonCount(button, item.count)
		SetItemButtonDesaturated(button, item.locked or (opts.greyJunk and item.junk))
		if opts.redUnusable and item.unusable then
			SetItemButtonTextureVertexColor(button, UI.Color("danger"))
		else
			SetItemButtonTextureVertexColor(button, 1, 1, 1)
		end
		button:UpdateQuestItem(item.quest, item.questID, item.questActive)
		button:UpdateNewItem(item.quality)
		if not opts.newGlow then
			button.NewItemTexture:Hide()
			button.flashAnim:Stop()
			button.newitemglowAnim:Stop()
		end
		button:UpdateJunkItem(item.quality, not item.price or item.price == 0)
		if opts.context then
			button:UpdateItemContextMatching()
		else
			-- Read only for the overlay's look (ItemButtonMixin:GetItemContextOverlayMode); SetMatchesSearch redraws it.
			button.itemContextMatchResult = ItemButtonUtil.ItemContextMatchResult.DoesNotApply
		end
		button:UpdateCooldown(item.icon)
		button:SetReadable(item.isReadable)
		PlaceMarks(button, e, item, opts)
		e.free:SetText("")
		e.leaf:Hide()
	end
	button:SetMatchesSearch(opts.matches ~= false)
	button:CheckUpdateTooltip(GameTooltip:GetOwner())
	button:Show()
end

-- Hides the buttons not in placed ([button] = true for the ones the window just drew). Only those: hiding a button
-- under the mouse or with its stack split open would close the split and flicker the tooltip
-- (ContainerFrameItemButtonMixin:OnHide).
function ns.BagsButtons_HideOthers(placed)
	for _, button in pairs(buttons) do
		if not placed[button] and button:IsShown() then
			button:Hide()
		end
	end
end

-- Off: clicks and drops go through the buttons to the window (an item from the bank goes into any free slot, instead
-- of swapping with the item it's dropped on).
function ns.BagsButtons_SetMouse(on)
	if mouseOn == on then
		return
	end
	mouseOn = on
	for _, button in pairs(buttons) do
		button:EnableMouse(on)
	end
end

-- Cooldown swipes only (BAG_UPDATE_COOLDOWN), without a full redraw.
function ns.BagsButtons_UpdateCooldowns()
	for _, button in pairs(buttons) do
		if button:IsShown() then
			button:UpdateCooldown(C_Container.HasContainerItem(button:GetParent():GetID(), button:GetID()))
		end
	end
end
