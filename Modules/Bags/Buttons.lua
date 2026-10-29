local addonName, ns = ...

-- Bags: the item buttons. Blizzard's own container item button template (not protected: buttons can be made and moved
-- in combat), one per bag slot, painted with Blizzard's item button functions plus Tomte's marks in the corners the
-- player picked (Data.lua decides which mark wins a shared corner) and the free-slot count. Blizzard's click code reads the bag from the button's
-- parent (a holder frame per bag, holder:SetID(bag)) and the slot from button:SetID(slot); nothing else is written
-- on the buttons for it, so using an item stays Blizzard's untainted code (ContainerFrame.lua,
-- ContainerFrameItemButton_OnClick). Our overlays live in a side table, not as fields on Blizzard's buttons.

local TEMPLATE = "ContainerFrameItemButtonTemplate"
local BUTTON = 37 -- the template's own size; ours are scaled from it (its art doesn't resize)
-- Every mark has Gear Check's arrow look (ns.Gear_Arrow): the plain glyph in its color, no plate or outline, over a
-- black copy of itself SHADOW_X, SHADOW_Y away.
local SHADOW_X, SHADOW_Y, SHADOW_ALPHA = 1.5, -1.5, 0.9
-- The transmog mark (on a 37 px button; the button's scale shrinks it with the icon): an X of two CROSS_LEN by
-- CROSS_W bars in a BADGE square.
local BADGE, CROSS_LEN, CROSS_W = 16, 16, 4
local SET_MARK = 7 -- the equipment set square's side
local CRAFT_DOT = 9 -- the crafting list's dot (how many is on the item's tooltip: Alts/List.lua)
-- Hairline slots (docs/superpowers/specs/2026-10-27-tomte-bags-ui-design.md): Blizzard's slot art and thick quality
-- border hidden; a dark fill, the icon inset, a 1-pixel frame in the theme's rule color or the item's quality color
-- (uncommon and better), the accent under the mouse.
local ICON_INSET = 2
local FILL, EMPTY_FILL = 0.35, 0.12 -- black behind an item, and (lighter) inside an empty slot: a faint dent
local EMPTY_EDGE = 0.12 -- an empty slot's frame: barely there, so the items stand out (0.6 and 0.3 still read as
                        -- loud, measured in game)
local PLAIN_EDGE = 0.7 -- the frame of an item below Uncommon (or without a quality): the theme's muted text color, a
                       -- step brighter than the window's rules so it still reads as an item
local QUALITY_FRAME = 2 -- Enum.ItemQuality.Uncommon: from here up the frame takes the quality color
local REAGENT_ATLAS = "bags-icon-reagents" -- Blizzard's reagent bag filter icon, on empty reagent slots
local LEAF, LEAF_ALPHA = 20, 0.5
local ARROW_SCALE = 0.85 -- Gear Check's arrow on a full-size button; the button's own scale shrinks it further
local INSET = 2 -- a corner overlay's distance from the button's edges
local COUNT_PULL = -3 -- the stack count's text box ends this much closer to the right edge than INSET (past it:
                      -- over the digits' empty right side)
-- A corner's x and y direction away from its edges.
local CORNER_DIRS = {
	TOPLEFT = { 1, -1 }, TOPRIGHT = { -1, -1 }, BOTTOMLEFT = { 1, 1 }, BOTTOMRIGHT = { -1, 1 },
}

local UI = ns.UI

local holders = {} -- [bag] = holder frame, a child of the window body that shows that bag
local buttons = {} -- [bag * 1000 + slot] = button
local views = {} -- [host] = { display-only buttons } (another character's items, Bags.lua's browsing)
local extras = {} -- [button] = { ilvl, pet, mark, set, craft, free, fontSize, red, arrows = { [kind] = widget } }
-- false while an item from outside the bags is on the cursor (ns.BagsButtons_SetMouse); the bag window's buttons only
-- (bags 0-5), the bank's keep taking clicks so a bank item can go back or move inside the bank.
local mouseOn = true
local BANK_FIRST = 6 -- the first bank tab's container ID (Enum.BagIndex.CharacterBankTab_1)

local function Holder(bag, host)
	local holder = holders[bag]
	if not holder then
		holder = CreateFrame("Frame", nil, host)
		holder:SetID(bag)
		holder:SetAllPoints()
		holders[bag] = holder
	end
	return holder
end

local function Shadow(text)
	text:SetShadowOffset(SHADOW_X, SHADOW_Y)
	text:SetShadowColor(0, 0, 0, SHADOW_ALPHA)
end

-- Number overlays (item level, pet level, free slots, the template's stack count) at the chosen size: outlined (the
-- shadow alone didn't read on bright icons, measured in game) with the marks' shadow too.
local function SetNumberFont(button, e, size)
	if e.fontSize ~= size then
		e.fontSize = size
		local sizes = { [e.ilvl] = size, [e.pet] = size, [e.free] = size + 1 }
		if button.Count then
			sizes[button.Count] = size
		end
		for text, s in pairs(sizes) do
			UI.SetFont(text, "number", s, "OUTLINE")
			Shadow(text)
		end
	end
end

-- A mark drawn by draw(texture) twice: the glyph, and its black shadow under it. mark:SetColor(role) colors the glyph.
local function Mark(button, w, h, draw)
	local mark = CreateFrame("Frame", nil, button)
	mark:SetSize(w, h)
	mark:SetFrameLevel(button:GetFrameLevel() + 3)
	local glyphs = {}
	for _, shadow in ipairs({ true, false }) do
		local holder = CreateFrame("Frame", nil, mark)
		holder:SetSize(w, h)
		holder:SetPoint("CENTER", shadow and SHADOW_X or 0, shadow and SHADOW_Y or 0)
		for _, t in ipairs(draw(holder, shadow and 1 or 2)) do
			if shadow then
				t:SetColorTexture(0, 0, 0, SHADOW_ALPHA)
			else
				glyphs[#glyphs + 1] = t
			end
		end
	end
	function mark:SetColor(role)
		for _, t in ipairs(glyphs) do
			t:SetColorTexture(UI.Color(role))
		end
	end
	return mark
end

-- The transmog mark: an X of two crossed bars.
local function Cross(holder, sub)
	local bars = {}
	for i, angle in ipairs({ math.pi / 4, -math.pi / 4 }) do
		local bar = holder:CreateTexture(nil, "ARTWORK", nil, sub)
		bar:SetSize(CROSS_LEN, CROSS_W)
		bar:SetPoint("CENTER")
		bar:SetRotation(angle)
		bars[i] = bar
	end
	return bars
end

-- The crafting list's mark: a dot (a number there read as a stack count, measured in game).
local function Dot(holder, sub)
	local t = holder:CreateTexture(nil, "ARTWORK", nil, sub)
	t:SetAllPoints()
	UI.CircleMask(t, holder)
	return { t }
end

-- The equipment set mark: a square.
local function Square(holder, sub)
	local t = holder:CreateTexture(nil, "ARTWORK", nil, sub)
	t:SetAllPoints()
	return { t }
end

local function Extras(button)
	local e = extras[button]
	if e then
		return e
	end
	e = { arrows = {} }
	local normal = button:GetNormalTexture()
	if normal then
		normal:SetAlpha(0)
	end
	e.fill = button:CreateTexture(nil, "BACKGROUND", nil, -1)
	e.fill:SetAllPoints()
	local icon = button.icon or button.Icon
	if icon then
		icon:ClearAllPoints()
		icon:SetPoint("TOPLEFT", ICON_INSET, -ICON_INSET)
		icon:SetPoint("BOTTOMRIGHT", -ICON_INSET, ICON_INSET)
	end
	UI.Border(button, "rule")
	button:HookScript("OnEnter", function(self)
		UI.BorderTo(self, "accent")
	end)
	button:HookScript("OnLeave", function(self)
		local ex = extras[self]
		UI.BorderTo(self, ex.edge or "rule", ex.edgeAlpha)
	end)
	e.ilvl = button:CreateFontString(nil, "OVERLAY")
	e.pet = button:CreateFontString(nil, "OVERLAY")
	e.mark = Mark(button, BADGE, BADGE, Cross)
	e.set = Mark(button, SET_MARK, SET_MARK, Square)
	e.craft = Mark(button, CRAFT_DOT, CRAFT_DOT, Dot)
	if button.JunkIcon then
		-- Blizzard's junk coin gets the marks' shadow: a black copy of its atlas under it.
		e.junkShadow = button:CreateTexture(nil, "ARTWORK", nil, 7)
		e.junkShadow:SetAtlas(button.JunkIcon:GetAtlas())
		e.junkShadow:SetVertexColor(0, 0, 0, SHADOW_ALPHA)
		e.junkShadow:SetPoint("TOPLEFT", button.JunkIcon, "TOPLEFT", SHADOW_X, SHADOW_Y)
		e.junkShadow:SetPoint("BOTTOMRIGHT", button.JunkIcon, "BOTTOMRIGHT", SHADOW_X, SHADOW_Y)
		e.junkShadow:Hide()
	end
	if button.Count then
		-- The template's stack count sat nearer the middle than the item level does on the other side: it hugs the
		-- corner instead, growing leftward. The number font's digits carry empty space on their right (a "2" measured
		-- 13.7 wide at size 12 in game), so at the marks' inset it still read as further in than the item level.
		button.Count:SetJustifyH("RIGHT")
		button.Count:ClearAllPoints()
		button.Count:SetPoint("BOTTOMRIGHT", -(INSET + COUNT_PULL), INSET)
	end
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

-- The button for one bag slot, made on first use in host (the body of the window that shows that bag: the bag
-- window for bags 0-5, the bank window for bank tabs).
function ns.BagsButtons_Get(bag, slot, host)
	local key = bag * 1000 + slot
	local button = buttons[key]
	if not button then
		button = CreateFrame("ItemButton", nil, Holder(bag, host), TEMPLATE)
		button:SetID(slot)
		button:EnableMouse(mouseOn or bag >= BANK_FIRST)
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
	if e.junkShadow then
		e.junkShadow:Hide()
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
			if e.junkShadow then
				e.junkShadow:Show()
			end
		elseif mark == "upgrade" then
			local widget = Arrow(button, e, item.upgrade)
			Corner(widget, corner, -INSET)
			widget:Show()
		elseif mark == "crafting" then
			e.craft:SetColor("accent")
			Corner(e.craft, corner, 1)
			e.craft:Show()
		elseif mark == "transmog" then
			e.mark:SetColor(item.look == "you" and "accent" or "textMuted")
			Corner(e.mark, corner)
			e.mark:Show()
		elseif mark == "set" then
			e.set:SetColor("info")
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

local function ViewTooltip(self)
	if self.link then
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetHyperlink(self.link)
		GameTooltip:Show()
	end
end

-- A display-only button (i) in host: another character's item, with its tooltip and nothing to click.
function ns.BagsButtons_GetView(host, i)
	local list = views[host]
	if not list then
		list = {}
		views[host] = list
	end
	local button = list[i]
	if not button then
		button = CreateFrame("ItemButton", nil, host)
		button.viewOnly = true
		button:SetScript("OnEnter", ViewTooltip)
		button:SetScript("OnLeave", function()
			GameTooltip:Hide()
		end)
		button:SetScript("OnClick", function(self)
			if self.link then
				HandleModifiedItemClick(self.link)
			end
		end)
		list[i] = button
	end
	return button
end

-- Puts a button at x, y (pixels from host's top-left) at size pixels.
function ns.BagsButtons_Place(button, host, x, y, size)
	local scale = size / BUTTON
	button:SetScale(scale)
	button:ClearAllPoints()
	button:SetPoint("TOPLEFT", host, "TOPLEFT", x / scale, -y / scale)
end

-- The hairline frame and fill for an item (nil: an empty slot), kept for the hover to come back to. pays: the open
-- vendor takes the item as payment, framed in the accent instead of its quality.
local function Frame(button, e, item, pays)
	if item then
		e.fill:SetColorTexture(0, 0, 0, FILL)
		local q = item.quality
		if pays then
			e.edge, e.edgeAlpha = "accent", 1
		elseif q and q >= QUALITY_FRAME then
			local r, g, b = C_Item.GetItemQualityColor(q)
			e.edge, e.edgeAlpha = { r, g, b }, 1
		else
			e.edge, e.edgeAlpha = "textMuted", PLAIN_EDGE
		end
	else
		e.fill:SetColorTexture(0, 0, 0, EMPTY_FILL)
		e.edge, e.edgeAlpha = "rule", EMPTY_EDGE
	end
	if button.IconBorder then
		button.IconBorder:Hide()
	end
	if button:IsMouseOver() and button:IsVisible() then
		UI.SetBorderColor(button, "accent")
	else
		UI.SetBorderColor(button, e.edge, e.edgeAlpha)
	end
end

-- A display-only button's look: icon, count, quality, the marks. Blizzard's bag button calls aren't on it.
local function PaintView(button, e, item, opts)
	button.link = item.link
	button:SetItemButtonTexture(item.icon)
	SetItemButtonQuality(button, item.quality, item.link)
	Frame(button, e, item)
	SetItemButtonCount(button, item.count)
	SetItemButtonDesaturated(button, opts.greyJunk and item.junk)
	PlaceMarks(button, e, item, opts)
	e.free:SetText("")
	e.leaf:Hide()
	button:SetMatchesSearch(opts.matches ~= false)
	button:Show()
end

-- Blizzard's UpdateCooldown colors the icon (white, or grey while the item can't be used yet), so the red of an item
-- you can't use goes on after it. The game's red, not the theme's danger: a softer red tints the icon pink.
local function UpdateCooldown(button, hasItem)
	button:UpdateCooldown(hasItem)
	local e = extras[button]
	if hasItem and e and e.red then
		SetItemButtonTextureVertexColor(button, RED_FONT_COLOR:GetRGB())
	end
end

-- Paints a button for its record. opts: matches (false: faded by the search), free (the free-slot count an Empty
-- slot shows, or nil), corners ([mark] = "TOPLEFT" | "TOPRIGHT" | "BOTTOMLEFT" | "BOTTOMRIGHT" | "off"), ilvlColor
-- ("quality" | "plain"), fontSize, newGlow, greyJunk, redUnusable, context (fade items that don't fit the open
-- window: Blizzard's item context matching), pays (the open vendor takes the item as payment).
function ns.BagsButtons_Paint(button, item, opts)
	local e = Extras(button)
	SetNumberFont(button, e, opts.fontSize)
	if button.viewOnly then
		PaintView(button, e, item, opts)
		return
	end
	ClearItemButtonOverlay(button)
	if item.empty then
		button:SetHasItem(nil)
		button:SetItemButtonTexture(nil)
		-- An empty slot shows the template's slot picture (emptyBackgroundAtlas, ItemButtonTemplate.lua) in the icon;
		-- ours is the faint square. Setting an item's texture shows the icon again.
		local icon = button.icon or button.Icon
		if icon then
			icon:Hide()
		end
		SetItemButtonQuality(button, nil)
		Frame(button, e, nil)
		SetItemButtonCount(button, 0)
		SetItemButtonDesaturated(button, false)
		SetItemButtonTextureVertexColor(button, 1, 1, 1)
		button:UpdateNewItem(nil)
		button:UpdateJunkItem(nil, true)
		button:UpdateQuestItem(false, nil, nil)
		e.red = false
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
		Frame(button, e, item, opts.pays)
		SetItemButtonCount(button, item.count)
		SetItemButtonDesaturated(button, item.locked or (opts.greyJunk and item.junk))
		e.red = opts.redUnusable and item.unusable or false -- painted by UpdateCooldown below
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
		UpdateCooldown(button, item.icon)
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
function ns.BagsButtons_HideOthers(placed, host)
	for _, button in pairs(buttons) do
		if not placed[button] and button:IsShown() and button:GetParent():GetParent() == host then
			button:Hide()
		end
	end
	for _, button in ipairs(views[host] or {}) do
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
	for key, button in pairs(buttons) do
		if key < BANK_FIRST * 1000 then
			button:EnableMouse(on)
		end
	end
end

-- Cooldown swipes only (BAG_UPDATE_COOLDOWN), without a full redraw.
function ns.BagsButtons_UpdateCooldowns()
	for _, button in pairs(buttons) do
		if button:IsShown() then
			UpdateCooldown(button, C_Container.HasContainerItem(button:GetParent():GetID(), button:GetID()))
		end
	end
end
