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
-- The transmog mark (on a 37 px button; the button's scale shrinks it with the icon): a coat hanger in a BADGE square,
-- drawn from HANGER_W wide strokes: a hook, two arms down from it and a bar across the bottom. Seen in game: a badge
-- with a dark X read as "delete" beside the item marker's red X, a gold ring (Forever's accent) as the vendor coin, a
-- drawn shirt as the letter T, and a bare X in the accent color got lost on busy icons. The game's only transmog atlas
-- on both clients (transmog-icon-ui, the Transmogrify window's round portrait) would read as the coin too.
local BADGE = 15
local HANGER_W = 2
local HANGER_ARM = 10.3 -- from the hook's foot (0, 3) to a bottom corner (+-7, -4.5)
local HANGER_ANGLE = 0.75 -- radians the arms lean from upright: atan(7 / 7.5)
local SET_MARK = 7 -- the equipment set square's side
-- The crafting list's mark: a little list, three LIST_W by LIST_H lines LIST_GAP apart (how many is on the item's
-- tooltip: Alts/List.lua). It was a dot, which looked like the item marker's vendor coin (seen in game).
local CRAFT_MARK = 9
local LIST_W, LIST_H, LIST_GAP = 9, 2, 1.5
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

-- The transmog mark: a coat hanger. Strokes are w x h at x, y from the center, turned by angle.
local function Hanger(holder, sub)
	local strokes = {
		{ HANGER_W, 3, 0, 4.5 }, -- the hook's stem
		{ 3, HANGER_W, 1, 6.5 }, -- over the top of the hook
		{ HANGER_W, 2, 2.5, 5.5 }, -- and down its far side
		{ HANGER_W, HANGER_ARM, -3.5, -0.75, -HANGER_ANGLE }, -- left arm
		{ HANGER_W, HANGER_ARM, 3.5, -0.75, HANGER_ANGLE }, -- right arm
		{ 14, HANGER_W, 0, -4.5 }, -- the bar across the bottom
	}
	local out = {}
	for i, s in ipairs(strokes) do
		local t = holder:CreateTexture(nil, "ARTWORK", nil, sub)
		t:SetSize(s[1], s[2])
		t:SetPoint("CENTER", s[3], s[4])
		if s[5] then
			t:SetRotation(s[5])
		end
		out[i] = t
	end
	return out
end

-- The crafting list's mark: three short lines, a list (a number there read as a stack count, measured in game).
local function List(holder, sub)
	local lines = {}
	for i = -1, 1 do
		local t = holder:CreateTexture(nil, "ARTWORK", nil, sub)
		t:SetSize(LIST_W, LIST_H)
		t:SetPoint("CENTER", 0, i * (LIST_H + LIST_GAP))
		lines[#lines + 1] = t
	end
	return lines
end

-- The equipment set mark: a square.
local function Square(holder, sub)
	local t = holder:CreateTexture(nil, "ARTWORK", nil, sub)
	t:SetAllPoints()
	return { t }
end

-- Blizzard asks before selling an item you could still return for a refund (ContainerFrame_GetExtendedPriceString).
local function Refundable(bag, slot)
	local info = C_Container.GetContainerItemPurchaseInfo(bag, slot, false)
	return info and info.refundSeconds ~= nil
end

-- Right-click on a grouped item at a merchant: Blizzard's click has sold the first stack, this sells the others. Runs
-- after Blizzard's code (a hook), so that stays untainted. Each place is read again: the bags may have changed since
-- the icon was painted. Vendor Helper sells the same way, several items at once with no wait.
local function SellOtherStacks(button, mouseButton)
	local item = extras[button].grouped
	if not item or mouseButton ~= "RightButton" or IsModifiedClick() or InCombatLockdown() then
		return
	end
	if not (MerchantFrame:IsShown() and MerchantFrame.selectedTab == 1) or Refundable(item.bag, item.slot) then
		return
	end
	for _, place in ipairs(ns.Bags_StacksToSell(item)) do
		local info = C_Container.GetContainerItemInfo(place.bag, place.slot)
		if info and info.hyperlink == item.link and not info.isLocked and not Refundable(place.bag, place.slot) then
			C_Container.UseContainerItem(place.bag, place.slot)
		end
	end
end

-- A grouped item's tooltip says how its stacks are split up. A post-call, as the item button rebuilds its tooltip every
-- 0.2 s. Post-calls can't be removed: it does nothing for any other owner, and a button only has a record while drawn.
local stackLineHooked = false
local function OnItemTooltip(tooltip)
	local e = tooltip == GameTooltip and extras[tooltip:GetOwner()]
	local item = e and e.stacked
	if not item then
		return
	end
	local _, _, _, _, _, _, _, maxStack = C_Item.GetItemInfo(item.itemID)
	local line = ns.Bags_StackLine(item.count, item.stacks, maxStack)
	if line then
		UI.TipLine(line, "textMuted")
	end
end

local function Extras(button)
	local e = extras[button]
	if e then
		return e
	end
	e = { arrows = {} }
	-- The Forever theme keeps the template's own slot art and quality border: that's how the game's bags look there.
	local gameArt = ns.Theme.panel == "forever"
	local normal = button:GetNormalTexture()
	if normal and not gameArt then
		normal:SetAlpha(0)
	end
	e.fill = button:CreateTexture(nil, "BACKGROUND", nil, -1)
	e.fill:SetAllPoints()
	local icon = button.icon or button.Icon
	if icon and not gameArt then
		icon:ClearAllPoints()
		icon:SetPoint("TOPLEFT", ICON_INSET, -ICON_INSET)
		icon:SetPoint("BOTTOMRIGHT", -ICON_INSET, ICON_INSET)
	end
	UI.Border(button, "rule", gameArt and 0 or nil)
	button:HookScript("OnClick", SellOtherStacks)
	button:HookScript("OnEnter", function(self)
		if not gameArt then
			UI.BorderTo(self, "accent")
		end
		local name = extras[self].kindName
		if name then
			-- Owned by a child: the tooltip calls its owner's UpdateTooltip every 0.2 s, and the item button's rebuilds it for
			-- the empty slot, which wipes this text (ContainerFrameItemButtonMixin:OnUpdate).
			GameTooltip:SetOwner(extras[self].tipOwner, "ANCHOR_RIGHT")
			GameTooltip:SetText(("Free slots: %s"):format(name))
			GameTooltip:Show()
		end
	end)
	button:HookScript("OnLeave", function(self)
		local ex = extras[self]
		UI.BorderTo(self, ex.edge or "rule", ex.edgeAlpha)
		if ex.kindName then
			GameTooltip:Hide()
		end
	end)
	e.ilvl = button:CreateFontString(nil, "OVERLAY")
	e.pet = button:CreateFontString(nil, "OVERLAY")
	e.mark = Mark(button, BADGE, BADGE, Hanger)
	e.set = Mark(button, SET_MARK, SET_MARK, Square)
	e.craft = Mark(button, CRAFT_MARK, CRAFT_MARK, List)
	e.marker = ns.Value_MarkerWidget(button) -- Gold & value's item marker (its vendor coin stands in for Blizzard's)
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
	-- A special bag's picture on Empty's button for its slots, so a quiver's free slots read as the quiver's.
	e.bagIcon = button:CreateTexture(nil, "OVERLAY", nil, 1)
	e.bagIcon:SetSize(LEAF, LEAF)
	e.bagIcon:SetPoint("CENTER")
	e.bagIcon:SetAlpha(LEAF_ALPHA)
	e.bagIcon:Hide()
	e.tipOwner = CreateFrame("Frame", nil, button) -- takes no mouse: only owns the Empty tooltip
	e.tipOwner:SetAllPoints()
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
	e.marker:SetKind(nil)
	for _, widget in pairs(e.arrows) do
		widget:Hide()
	end
	if button.JunkIcon then
		button.JunkIcon:Hide() -- the item marker's coin is the one that shows, in the corner the player picked
	end
end

-- The marks an item carries (Data.lua's BAGS_MARKS keys), placed in their corners: the first of each corner in the
-- player's order wins. item.crafting stands in for the crafting list on the marks editor's samples.
local function PlaceMarks(button, e, item, opts)
	HideMarks(button, e)
	local crafting = item.crafting
	if crafting == nil then
		crafting = ns.AltsList_Marked and ns.AltsList_Marked(item.itemID)
	end
	local has = {
		upgrade = item.upgrade, marker = item.marker and item.marker.kind, crafting = crafting, transmog = item.look,
		set = item.set ~= nil, petlevel = item.petLevel, ilvl = item.ilvl and item.ilvl > 1,
	}
	for corner, mark in pairs(ns.Bags_CornerMarks(has, opts.corners, opts.markOrder)) do
		if mark == "upgrade" then
			local widget = Arrow(button, e, item.upgrade)
			Corner(widget, corner, -INSET)
			widget:Show()
		elseif mark == "marker" then
			e.marker:SetKind(item.marker.kind)
			Corner(e.marker, corner, -1)
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
local function Frame(button, e, item, pays, tint)
	if ns.Theme.panel == "forever" then
		-- The template's art shows the slot and the quality: a line only for what it can't say.
		e.fill:SetColorTexture(0, 0, 0, 0)
		if pays or tint then
			e.edge, e.edgeAlpha = pays and "accent" or tint, 1
		else
			e.edge, e.edgeAlpha = "rule", 0
		end
		UI.SetBorderColor(button, e.edge, e.edgeAlpha)
		return
	end
	if item then
		e.fill:SetColorTexture(0, 0, 0, FILL)
		local q = item.quality
		if pays then
			e.edge, e.edgeAlpha = "accent", 1
		elseif tint then
			e.edge, e.edgeAlpha = tint, 1
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
	Frame(button, e, item, nil, opts.tint)
	SetItemButtonCount(button, item.count)
	SetItemButtonDesaturated(button, opts.greyJunk and item.junk)
	PlaceMarks(button, e, item, opts)
	e.free:SetText("")
	e.leaf:Hide()
	e.bagIcon:Hide()
	e.kindName = nil
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

-- Spotlight: one bag slot another module points at (Loot's Make room: what it offers to destroy) ---------------------

local SPOT_OUT = 3 -- pixels the glow reaches past the button
local SPOT_PULSE = 0.6 -- seconds from bright to faint
local SPOT_LOW = 0.35 -- the faint end of the pulse
local spotlight -- { bag, slot } or nil
local blizzSpot -- the glow on Blizzard's own bag button, while Tomte's bags are off
local blizzSpots = {} -- [Blizzard's bag button] = its glow, made on first use (kept here, not on their buttons)

local function NewSpot(button)
	local spot = CreateFrame("Frame", nil, button)
	spot:SetPoint("TOPLEFT", -SPOT_OUT, SPOT_OUT)
	spot:SetPoint("BOTTOMRIGHT", SPOT_OUT, -SPOT_OUT)
	spot:SetFrameLevel(button:GetFrameLevel() + 5)
	spot.glow = spot:CreateTexture(nil, "OVERLAY")
	spot.glow:SetAtlas("bags-glow-white")
	spot.glow:SetAllPoints()
	UI.Border(spot, "danger")
	spot.pulse = spot:CreateAnimationGroup()
	spot.pulse:SetLooping("BOUNCE")
	local fade = spot.pulse:CreateAnimation("Alpha")
	fade:SetFromAlpha(1)
	fade:SetToAlpha(SPOT_LOW)
	fade:SetDuration(SPOT_PULSE)
	spot:Hide()
	return spot
end

local function ShowSpot(spot, on)
	if not on then
		spot.pulse:Stop()
		spot:Hide()
		return
	end
	spot.glow:SetVertexColor(UI.RGBA("danger"))
	UI.SetBorderColor(spot, "danger")
	spot:Show()
	if UI.MotionLevel() ~= "off" then
		spot.pulse:Play()
	end
end

local function PaintSpot(button, e, item)
	local on = spotlight ~= nil and not item.empty and ns.Bags_HoldsSlot(item, spotlight.bag, spotlight.slot)
	if on and not e.spot then
		e.spot = NewSpot(button)
	end
	if e.spot then
		ShowSpot(e.spot, on)
	end
end

-- Lights one bag slot (nil: none) in Tomte's bag window, or in Blizzard's bags while Tomte's are off.
function ns.Bags_Spotlight(bag, slot)
	local same = spotlight and bag and spotlight.bag == bag and spotlight.slot == slot
	if same or (not spotlight and not bag) then
		return
	end
	spotlight = bag and { bag = bag, slot = slot } or nil
	if blizzSpot then
		ShowSpot(blizzSpot, false)
		blizzSpot = nil
	end
	if ns.Bags_Active() then
		ns.BagsWindow_Refresh()
	elseif bag and ContainerFrameUtil_GetItemButtonAndContainer then
		local button = ContainerFrameUtil_GetItemButtonAndContainer(bag, slot)
		if button then
			blizzSpots[button] = blizzSpots[button] or NewSpot(button)
			blizzSpot = blizzSpots[button]
			ShowSpot(blizzSpot, true)
		end
	end
end

-- Paints a button for its record. opts: matches (false: faded by the search), free (the free-slot count an Empty
-- slot shows, or nil), corners ([mark] = "TOPLEFT" | "TOPRIGHT" | "BOTTOMLEFT" | "BOTTOMRIGHT" | "off"), markOrder
-- (Data.lua's Bags_MarkOrder: which mark wins a shared corner), ilvlColor
-- ("quality" | "plain"), fontSize, newGlow, greyJunk, redUnusable, context (fade items that don't fit the open
-- window: Blizzard's item context matching), pays (the open vendor takes the item as payment), tint (its category's
-- color role, for the frame).
function ns.BagsButtons_Paint(button, item, opts)
	local e = Extras(button)
	e.grouped = item.more and item or nil
	e.stacked = item.stacks and item or nil
	if e.stacked and not stackLineHooked then
		stackLineHooked = true
		TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, ns.Perf_Wrap(OnItemTooltip, "tooltip"))
	end
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
		-- ours is the faint square (the Forever theme keeps the picture). Setting an item's texture shows the icon again.
		local icon = button.icon or button.Icon
		if icon and ns.Theme.panel ~= "forever" then
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
		local special = opts.free ~= nil and item.kind ~= "normal" and item.kind ~= "reagent"
		e.kindName = opts.free ~= nil and item.kind ~= "normal" and ns.Bags_SlotKindName(item.kind) or nil
		if special then
			e.bagIcon:SetTexture(GetInventoryItemTexture("player", C_Container.ContainerIDToInventoryID(item.bag)))
		end
		e.bagIcon:SetShown(special)
	else
		button:SetHasItem(item.icon)
		button:SetItemButtonTexture(item.icon)
		SetItemButtonQuality(button, item.quality, item.link, false, item.bind == "soulbound")
		Frame(button, e, item, opts.pays, opts.tint)
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
		-- Blizzard's coin at a merchant goes by quality alone: an upgrade (a grey one while leveling) counts as no value.
		button:UpdateJunkItem(item.quality, not item.price or item.price == 0 or item.upgrade ~= nil)
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
		e.bagIcon:Hide()
		e.kindName = nil
	end
	PaintSpot(button, e, item)
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
