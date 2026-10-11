local addonName, ns = ...

-- Showcase scene (the cinematic engine's scene contract, Cinematic/Engine.lua). The "field manual" look from the
-- 2026-10-11 mockup: gear in two columns of diamonds strung on thin rails; on the right, with no box, the name block, an item level dial, tiles for the base stats, one bar split
-- by secondary stat rating, and chips for the rest.
-- Layout is in design units of a 1600 x 900 screen (the mockup): each group is scaled to the real screen height and
-- placed at the same fraction of the width. Textures come from tools/showcase_art.py (Media/Showcase), tinted by
-- theme role or item quality. GameTooltip lives on the hidden UIParent, so the slots have their own tooltip.

local UI = ns.UI
local ART = ns.Theme.MEDIA .. "Showcase\\"
local DIAMOND, GLOW, RING, DOT, STAR = ART .. "Diamond", ART .. "Glow", ART .. "Ring", ART .. "Dot", ART .. "Star"
local RING_THICK = ART .. "RingThick"
local DISC = "Interface\\CharacterFrame\\TempPortraitAlphaMask"

local DESIGN_W, DESIGN_H = 1600, 900
local LEFT_X = 84 -- left gear boxes, from the left edge
local RIGHT_X = 1026 -- right gear boxes end here
local STATS_X, STATS_Y = 1130, 120
local TOP, ROW = 128, 78 -- first gear row, row step
local BOX_W, BOX_H = 470, 60
local ICON_C = 27 -- icon center, from the box's top corner
local EDGE, INNER, ICON = 54, 49, 44 -- diamond sizes: quality edge, dark inner, item icon
local TEXT_X, TEXT_W = 62, 270
local RAIL_TOP, RAIL_BOTTOM = 130, 790
local SHADE_LEFT, SHADE_RIGHT = 520, 640 -- design widths of the dark gradients behind the columns and stats
local STATS_W = 410
local DIAL, DIAL_R = 132, 52
local DIAL_STEPS = 160 -- the progress arc is this many overlapping soft dots: a smooth line with round ends
local TILE_X, TILE_H, GAP = 156, 58, 8
local LEGEND_ROW = 46
local SLOT_FADE_STEP = 0.035 -- each slot fades in a little after the one above
local CLOSE_FADE = 0.3 -- seconds: everything fades out this fast on close, before the UI is back
-- Secondary stat colors, by theme role.
local STAT_ROLES = { crit = "danger", haste = "warning", mastery = "accent", versatility = "success" }

local SCENE = {}
ns.CharShowScene = SCENE

local root, tooltip, stats
local groups = {} -- left, right, stats: scaled to the screen
local shades = {}
local shadeFrame -- holds the shades: gradient textures ignore their own alpha, so the frame fades them
local rails = {}
local closing, closeT = false, 0
local slots = {} -- [slot] = slot widget
local slotOrder = {} -- widgets in fade-in order
local showHints = true

local ENCHANT_LINE = Enum and Enum.TooltipDataLineType and Enum.TooltipDataLineType.ItemEnchantmentPermanent

-- Helpers ------------------------------------------------------------------------------------------------------------

local function Tex(parent, layer, file, size, sublevel)
	local t = parent:CreateTexture(nil, layer, nil, sublevel)
	if file then
		t:SetTexture(file)
	else
		t:SetColorTexture(1, 1, 1, 1)
	end
	if size then
		t:SetSize(size, size)
	end
	return t
end

-- color: a theme role or a { r, g, b } table (item quality, class).
local function Tint(t, color, alpha)
	t:SetVertexColor(UI.RGBA(color, alpha))
end

-- A 1px border around frame; returns a setter for its color.
local function Border(frame)
	local edges = {}
	for i, points in ipairs({ { "TOPLEFT", "TOPRIGHT" }, { "BOTTOMLEFT", "BOTTOMRIGHT" }, { "TOPLEFT", "BOTTOMLEFT" },
		{ "TOPRIGHT", "BOTTOMRIGHT" } }) do
		local e = Tex(frame, "BORDER")
		e:SetPoint(points[1])
		e:SetPoint(points[2])
		if i <= 2 then
			e:SetHeight(1)
		else
			e:SetWidth(1)
		end
		edges[i] = e
	end
	return function(color, alpha)
		for _, e in ipairs(edges) do
			Tint(e, color, alpha)
		end
	end
end

local function EnchantText(slot)
	if not ENCHANT_LINE then
		return nil
	end
	local data = C_TooltipInfo.GetInventoryItem("player", slot)
	for _, line in ipairs(data and data.lines or {}) do
		if line.type == ENCHANT_LINE and line.leftText and not ns.IsSecret(line.leftText) then
			return ns.CharShow_EnchantText(line.leftText, ENCHANTED_TOOLTIP_LINE)
		end
	end
	return nil
end

local function AtMaxLevel()
	local maxLevel = ns.GearHints_MaxLevel and ns.GearHints_MaxLevel()
	return maxLevel ~= nil and UnitLevel("player") >= maxLevel
end

-- Slots --------------------------------------------------------------------------------------------------------------

local function SlotOnEnter(self)
	if not GetInventoryItemLink("player", self.slot) then
		return
	end
	-- Pinned by hand: the slot sits in a scaled group, and the ANCHOR_ modes put the tooltip far from it.
	tooltip:SetOwner(self, "ANCHOR_NONE")
	tooltip:ClearAllPoints()
	if self.side == "LEFT" then
		tooltip:SetPoint("TOPLEFT", self, "TOPLEFT", TEXT_X + TEXT_W, 0) -- after the text
	else
		tooltip:SetPoint("TOPLEFT", self, "TOPRIGHT", 8, 0) -- right of the icon, toward the stats
	end
	tooltip:SetInventoryItem("player", self.slot)
	tooltip:Show()
end

local function SlotOnLeave()
	tooltip:Hide()
end

local function SlotOnClick(self)
	if IsModifiedClick("CHATLINK") then
		UI.InsertLink(GetInventoryItemLink("player", self.slot))
	end
end

-- Puts region with its top corner (on the slot's side) x units in from the box's side, y down.
local function Put(w, region, x, y)
	region:ClearAllPoints()
	region:SetPoint("TOP" .. w.side, w, "TOP" .. w.side, w.sign * x, y)
end

local function CreateSlot(group, slot, side, row)
	local w = CreateFrame("Button", nil, group)
	w.slot, w.side, w.sign = slot, side, side == "LEFT" and 1 or -1
	w:SetSize(BOX_W, BOX_H)
	w:SetPoint("TOP" .. side, group, "TOP" .. side, 0, -(TOP + (row - 1) * ROW))
	w:RegisterForClicks("LeftButtonUp")
	w:SetScript("OnEnter", SlotOnEnter)
	w:SetScript("OnLeave", SlotOnLeave)
	w:SetScript("OnClick", SlotOnClick)

	local function Centered(region)
		region:SetPoint("CENTER", w, "TOP" .. side, w.sign * ICON_C, -ICON_C)
		return region
	end
	w.glow = Centered(Tex(w, "BACKGROUND", GLOW, 100))
	w.glow:SetBlendMode("ADD")
	w.edge = Centered(Tex(w, "BORDER", DIAMOND, EDGE))
	w.inner = Centered(Tex(w, "BORDER", DIAMOND, INNER, 1))
	Tint(w.inner, "frameDark", 0.9)
	w.icon = Centered(Tex(w, "ARTWORK", nil, ICON))
	local mask = w:CreateMaskTexture()
	mask:SetTexture(DIAMOND, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
	mask:SetAllPoints(w.icon)
	w.icon:AddMaskTexture(mask)

	w.name = UI.Text(w, 17, "text", "title")
	w.name:SetWordWrap(false)
	w.name:SetJustifyH(side)
	w.name:SetWidth(TEXT_W)
	Put(w, w.name, TEXT_X, -2)

	-- Item level pill.
	w.pill = CreateFrame("Frame", nil, w)
	w.pill:SetHeight(19)
	w.pillBg = Tex(w.pill, "BACKGROUND")
	w.pillBg:SetAllPoints()
	w.pillBorder = Border(w.pill)
	w.pillText = UI.Text(w.pill, 13, "text", "number")
	w.pillText:SetPoint("CENTER", 0, 0)

	w.track = UI.Text(w, 12, "textMuted")
	w.pips = {}
	for i = 1, 8 do
		w.pips[i] = Tex(w, "ARTWORK", DIAMOND, 9)
	end
	w.sockets = {}
	for i = 1, 3 do
		local s = Tex(w, "ARTWORK", nil, 11)
		UI.CircleMask(s, w)
		local ring = Tex(w, "OVERLAY", RING, 12)
		ring:SetPoint("CENTER", s)
		w.sockets[i] = { gem = s, ring = ring }
	end

	w.star = Tex(w, "ARTWORK", STAR, 12)
	Put(w, w.star, TEXT_X, -46)
	w.hint = UI.Text(w, 13, "success")
	w.hint:SetWordWrap(false)
	w.hint:SetJustifyH(side)
	w.hint:SetWidth(TEXT_W - 16)
	Put(w, w.hint, TEXT_X + 16, -45)

	slots[slot] = w
	return w
end

local function HideHintParts(w)
	w.track:Hide()
	for _, p in ipairs(w.pips) do
		p:Hide()
	end
	for _, s in ipairs(w.sockets) do
		s.gem:Hide()
		s.ring:Hide()
	end
	w.star:Hide()
	w.hint:Hide()
end

local function ShowEmpty(w)
	local _, emptyTexture = GetInventorySlotInfo(ns.CHARSHOW_SLOT_NAMES[w.slot])
	w.icon:SetTexture(emptyTexture)
	w.icon:SetDesaturated(true)
	w.icon:SetAlpha(0.35)
	Tint(w.edge, "frame", 0.45)
	w.glow:Hide()
	w.name:SetText("")
	w.pill:Hide()
	HideHintParts(w)
end

-- The second line, from the icon outward: item level pill, track word and pips, sockets. Then the enchant line.
local function LayoutDetails(w, color, ilvl, desc, hints)
	local x = TEXT_X
	w.pillText:SetText(ilvl or "")
	local pillW = math.ceil(w.pillText:GetUnboundedStringWidth()) + 14
	w.pill:SetWidth(pillW)
	w.pillBg:SetColorTexture(UI.RGBA(color, 0.28))
	w.pillBorder(color, 0.6)
	Put(w, w.pill, x, -23)
	w.pill:SetShown(ilvl ~= nil)
	x = x + pillW + 8

	HideHintParts(w)
	if not showHints then
		return
	end
	local track, cur, max = ns.CharShow_Track(desc and desc.upgrade)
	if track then
		w.track:SetText(track)
		Put(w, w.track, x, -26)
		w.track:Show()
		x = x + math.ceil(w.track:GetUnboundedStringWidth()) + 6
		for i = 1, math.min(max, #w.pips) do
			local p = w.pips[i]
			Tint(p, "heading", i <= cur and 1 or 0.25)
			Put(w, p, x, -27)
			p:Show()
			x = x + 9
		end
		x = x + 5
	end
	for i, s in ipairs(w.sockets) do
		local gemID = desc and desc.gemIDs and desc.gemIDs[i]
		if i <= hints.gems + hints.empty then
			Put(w, s.gem, x, -27)
			if i <= hints.gems and gemID then
				s.gem:SetTexture(C_Item.GetItemIconByID(gemID))
				s.gem:Show()
				Tint(s.ring, color, 0.8)
			else
				Tint(s.ring, "danger", 1)
			end
			s.ring:Show()
			x = x + 14
		end
	end

	local text, role
	if hints.missing then
		text, role = "No enchant", "danger"
	elseif hints.enchant then
		text, role = hints.enchant, "success"
	end
	if text then
		w.hint:SetText(text)
		w.hint:SetTextColor(UI.Color(role))
		Tint(w.star, role, 1)
		w.hint:Show()
		w.star:Show()
	end
end

local function RefreshSlot(w)
	local slot = w.slot
	local link = GetInventoryItemLink("player", slot)
	if not link or ns.IsSecret(link) then
		ShowEmpty(w)
		return
	end
	local quality = GetInventoryItemQuality("player", slot)
	local color = "text"
	if quality then
		local r, g, b = C_Item.GetItemQualityColor(quality)
		color = { r, g, b }
	end
	w.icon:SetTexture(GetInventoryItemTexture("player", slot))
	w.icon:SetDesaturated(false)
	w.icon:SetAlpha(1)
	Tint(w.edge, color, 1)
	Tint(w.glow, color, 0.5)
	w.glow:Show()
	w.name:SetTextColor(UI.RGBA(color))
	w.name:SetText(C_Item.GetItemNameByID(link) or C_Item.GetItemInfo(link) or "")

	local ilvl = C_Item.GetCurrentItemLevel(ItemLocation:CreateFromEquipmentSlot(slot))
	local desc = ns.GearItems_Describe and ns.GearItems_Describe(link)
	local hints = desc and ns.CharShow_Hints(desc, ns.Gear_EnchantSlot(slot, desc.equipLoc), AtMaxLevel(),
		desc.enchanted and EnchantText(slot)) or { gems = 0, empty = 0, missing = false }
	LayoutDetails(w, color, ilvl, desc, hints)
end

-- Stats --------------------------------------------------------------------------------------------------------------

-- Every stat entry ({ key, label, value, rating, percent, group }), unfiltered; the role and a shield.
local function ReadStats()
	local entries = {}
	local function Add(key, label, value, rating, percent, group)
		if not ns.Readable(value) or (rating ~= nil and not ns.Readable(rating)) then
			return
		end
		entries[#entries + 1] = { key = key, label = label, value = value, rating = rating, percent = percent,
			group = group }
	end
	local spec = C_SpecializationInfo.GetSpecialization()
	local role, primaryStat
	if spec then
		local _
		_, _, _, _, role, primaryStat = C_SpecializationInfo.GetSpecializationInfo(spec, false, false, nil,
			UnitSex("player"))
	end
	if primaryStat then
		Add("primary", _G["SPELL_STAT" .. primaryStat .. "_NAME"], select(2, UnitStat("player", primaryStat)), nil,
			false, 1)
	end
	Add("stamina", SPELL_STAT3_NAME, select(2, UnitStat("player", 3)), nil, false, 1)
	Add("health", HEALTH, UnitHealthMax("player"), nil, false, 1)
	Add("armor", STAT_ARMOR, select(2, UnitArmor("player")), nil, false, 1)

	-- Crit as Blizzard's sheet picks it: the best of spell (lowest school), ranged and melee.
	local spellCrit = GetSpellCritChance(2)
	for school = 3, MAX_SPELL_SCHOOLS or 7 do
		spellCrit = math.min(spellCrit, GetSpellCritChance(school))
	end
	local rangedCrit, meleeCrit = GetRangedCritChance(), GetCritChance()
	local crit, critRating
	if spellCrit >= rangedCrit and spellCrit >= meleeCrit then
		crit, critRating = spellCrit, CR_CRIT_SPELL
	elseif rangedCrit >= meleeCrit then
		crit, critRating = rangedCrit, CR_CRIT_RANGED
	else
		crit, critRating = meleeCrit, CR_CRIT_MELEE
	end
	Add("crit", STAT_CRITICAL_STRIKE, crit, GetCombatRating(critRating), true, 2)
	Add("haste", STAT_HASTE, GetHaste(), GetCombatRating(CR_HASTE_MELEE), true, 2)
	Add("mastery", STAT_MASTERY, GetMasteryEffect(), GetCombatRating(CR_MASTERY), true, 2)
	Add("versatility", STAT_VERSATILITY, GetCombatRatingBonus(CR_VERSATILITY_DAMAGE_DONE)
		+ GetVersatilityBonus(CR_VERSATILITY_DAMAGE_DONE), GetCombatRating(CR_VERSATILITY_DAMAGE_DONE), true, 2)
	Add("leech", STAT_LIFESTEAL, GetLifesteal(), GetCombatRating(CR_LIFESTEAL), true, 3)
	Add("avoidance", STAT_AVOIDANCE, GetAvoidance(), GetCombatRating(CR_AVOIDANCE), true, 3)
	Add("speed", STAT_SPEED, GetSpeed(), GetCombatRating(CR_SPEED), true, 3)
	Add("dodge", STAT_DODGE, GetDodgeChance(), GetCombatRating(CR_DODGE), true, 4)
	Add("parry", STAT_PARRY, GetParryChance(), GetCombatRating(CR_PARRY), true, 4)
	Add("block", STAT_BLOCK, GetBlockChance(), GetCombatRating(CR_BLOCK), true, 4)
	local hasShield = C_PaperDollInfo.OffhandHasShield and C_PaperDollInfo.OffhandHasShield()
	return entries, role == "TANK", hasShield
end

local function Group(entries, group)
	local list = {}
	for _, e in ipairs(entries) do
		if e.group == group then
			list[#list + 1] = e
		end
	end
	return list
end

local function Upper(text)
	return ns.Spaced((text or ""):upper())
end

local function CreateNameBlock()
	stats.name = UI.Text(stats, 46, "text", "title")
	stats.name:SetPoint("TOPLEFT", 0, 0)
	stats.name:SetWidth(STATS_W - 40)
	stats.name:SetWordWrap(false)
	stats.name:SetShadowOffset(2, -2)
	stats.rule = Tex(stats, "ARTWORK")
	stats.rule:SetSize(150, 2)
	stats.rule:SetPoint("TOPLEFT", 0, -60)
	stats.ruleEdge = Tex(stats, "ARTWORK", DIAMOND, 11)
	stats.ruleEdge:SetPoint("CENTER", stats.rule, "RIGHT", 10, 0)
	stats.ruleInner = Tex(stats, "ARTWORK", DIAMOND, 7, 1)
	stats.ruleInner:SetPoint("CENTER", stats.ruleEdge)
	Tint(stats.ruleInner, "frameDark", 1)
	stats.title = UI.Text(stats, 16, "textMuted")
	stats.title:SetPoint("TOPLEFT", 0, -72)
	stats.sub = UI.Text(stats, 16, "heading")
	stats.sub:SetPoint("TOPLEFT", 0, -94)
end

local function CreateDial()
	local dial = CreateFrame("Frame", nil, stats)
	dial:SetSize(DIAL, DIAL)
	dial:SetPoint("TOPLEFT", 0, -126)
	local disc = Tex(dial, "BACKGROUND", DISC, 116)
	disc:SetPoint("CENTER")
	Tint(disc, "frameDark", 0.6)
	local outer = Tex(dial, "BORDER", RING, 118)
	outer:SetPoint("CENTER")
	Tint(outer, "frame", 0.4)
	-- The track (the thick ring's stroke sits on DIAL_R), then the lit arc over it.
	local track = Tex(dial, "BORDER", RING_THICK, 111, 1)
	track:SetPoint("CENTER")
	Tint(track, "accent", 0.18)
	dial.arc = {}
	for i = 1, DIAL_STEPS do
		local t = Tex(dial, "ARTWORK", DOT, 9)
		local a = math.pi / 2 - (i - 1) / DIAL_STEPS * 2 * math.pi -- clockwise from the top
		t:SetPoint("CENTER", dial, "CENTER", DIAL_R * math.cos(a), DIAL_R * math.sin(a))
		Tint(t, "accent", 1)
		dial.arc[i] = t
	end
	-- Four short ticks outside the ring, at the top, right, bottom and left.
	for _, d in ipairs({ { 0, 1 }, { 1, 0 }, { 0, -1 }, { -1, 0 } }) do
		local tick = Tex(dial, "ARTWORK")
		tick:SetSize(d[1] == 0 and 1 or 6, d[1] == 0 and 6 or 1)
		tick:SetPoint("CENTER", dial, "CENTER", d[1] * 59, d[2] * 59)
		Tint(tick, "heading", 0.45)
	end
	dial.label = UI.Text(dial, 9, "textMuted", "label")
	dial.label:SetPoint("CENTER", 0, 23)
	dial.label:SetText((STAT_AVERAGE_ITEM_LEVEL or "Item level"):upper())
	dial.number = UI.Text(dial, 40, "heading", "number")
	dial.number:SetPoint("CENTER", 0, 0)
	dial.best = UI.Text(dial, 11, "textMuted", "number")
	dial.best:SetPoint("CENTER", 0, -26)
	stats.dial = dial
end

local function CreateTiles()
	stats.tiles = {}
	local w = (STATS_W - TILE_X - GAP) / 2
	local top = -126 - (DIAL - 2 * TILE_H - GAP) / 2 -- centered on the dial
	for i = 1, 4 do
		local tile = CreateFrame("Frame", nil, stats)
		tile:SetSize(w, TILE_H)
		local col, row = (i - 1) % 2, math.floor((i - 1) / 2)
		tile:SetPoint("TOPLEFT", TILE_X + col * (w + GAP), top - row * (TILE_H + GAP))
		local bg = Tex(tile, "BACKGROUND")
		bg:SetAllPoints()
		Tint(bg, "bg", 0.72)
		Border(tile)("rule", 1)
		tile.label = UI.Text(tile, 11, "textMuted", "label")
		tile.label:SetPoint("TOPLEFT", 12, -10)
		tile.value = UI.Text(tile, 20, "text", "number")
		tile.value:SetPoint("TOPLEFT", tile.label, "BOTTOMLEFT", 0, -4)
		stats.tiles[i] = tile
	end
end

local SPLIT_Y = -126 - DIAL - 24

local function CreateSplit()
	stats.splitTitle = UI.Text(stats, 12, "textMuted", "label")
	stats.splitTitle:SetPoint("TOPLEFT", 0, SPLIT_Y)
	stats.splitTitle:SetText(Upper("Secondary stats"))
	stats.splitNote = UI.Text(stats, 12, "textFaint")
	stats.splitNote:SetPoint("TOPRIGHT", 0, SPLIT_Y)
	stats.splitNote:SetText("share of your rating")
	stats.bars, stats.legend = {}, {}
	local colW = (STATS_W - 18) / 2
	for i = 1, 4 do
		stats.bars[i] = Tex(stats, "ARTWORK")
		stats.bars[i]:SetHeight(12)
		local item = CreateFrame("Frame", nil, stats)
		item:SetSize(colW, 34)
		local col, row = (i - 1) % 2, math.floor((i - 1) / 2)
		item:SetPoint("TOPLEFT", col * (colW + 18), SPLIT_Y - 46 - row * LEGEND_ROW)
		item.swatch = Tex(item, "ARTWORK")
		item.swatch:SetSize(4, 30)
		item.swatch:SetPoint("LEFT", 0, 0)
		item.label = UI.Text(item, 15, "text")
		item.label:SetPoint("TOPLEFT", 14, -1)
		item.pct = UI.Text(item, 17, "text", "number")
		item.pct:SetPoint("TOPRIGHT", 0, 0)
		item.rating = UI.Text(item, 11, "textFaint", "number")
		item.rating:SetPoint("TOPLEFT", item.label, "BOTTOMLEFT", 0, -3)
		stats.legend[i] = item
	end
end

local function Chip(i)
	stats.chips = stats.chips or {}
	local chip = stats.chips[i]
	if not chip then
		chip = CreateFrame("Frame", nil, stats)
		chip:SetHeight(24)
		local bg = Tex(chip, "BACKGROUND")
		bg:SetAllPoints()
		Tint(bg, "bg", 0.72)
		Border(chip)("rule", 1)
		chip.text = UI.Text(chip, 13, "text")
		chip.text:SetPoint("LEFT", 10, 0)
		stats.chips[i] = chip
	end
	return chip
end

local function RefreshStats()
	local _, classFile = UnitClass("player")
	local classColor = classFile and C_ClassColor.GetClassColor(classFile)
	local cc = classColor and { classColor:GetRGB() } or "accent"
	stats.name:SetText(UnitName("player"))
	stats.rule:SetGradient("HORIZONTAL", UI.ColorObject(cc, 1), UI.ColorObject(cc, 0))
	Tint(stats.ruleEdge, cc, 1)
	stats.title:SetText(ns.CharShow_Title(GetTitleName(GetCurrentTitle())) or "")
	local spec = C_SpecializationInfo.GetSpecialization()
	local specName = spec and select(2, C_SpecializationInfo.GetSpecializationInfo(spec, false, false, nil,
		UnitSex("player")))
	stats.sub:SetText(ns.CharShow_Subtitle(UnitLevel("player"), specName, UnitClass("player")))

	local best, equipped = GetAverageItemLevel()
	equipped, best = math.floor(equipped or 0), math.floor(best or 0)
	local _, lit = ns.CharShow_DialFill(equipped, best, DIAL_STEPS)
	for i, t in ipairs(stats.dial.arc) do
		t:SetShown(i <= lit)
	end
	stats.dial.number:SetText(equipped)
	stats.dial.best:SetText(("bags %d"):format(best))

	local entries, isTank, hasShield = ReadStats()
	local base = Group(entries, 1)
	for i, tile in ipairs(stats.tiles) do
		local e = base[i]
		if e then
			tile.label:SetText(Upper(e.label))
			tile.value:SetText((ns.CharShow_StatText(e)))
			tile:Show()
		else
			tile:Hide()
		end
	end

	local parts = ns.CharShow_Split(Group(entries, 2)) or {}
	local x = 0
	local room = STATS_W - 2 * math.max(#parts - 1, 0)
	for i, bar in ipairs(stats.bars) do
		local p, item = parts[i], stats.legend[i]
		if p then
			local role = STAT_ROLES[p.key] or "accent"
			local width = math.max(p.share * room, 0.001)
			bar:ClearAllPoints()
			bar:SetPoint("TOPLEFT", stats, "TOPLEFT", x, SPLIT_Y - 22)
			bar:SetWidth(width)
			bar:SetGradient("VERTICAL", UI.ColorObject(role, 0.65), UI.ColorObject(role, 1))
			bar:SetShown(p.share > 0)
			x = x + width + 2
			Tint(item.swatch, role, 1)
			item.label:SetText(p.label)
			item.pct:SetText((ns.CharShow_StatText({ value = p.value or 0, percent = true })))
			item.rating:SetText(("%s rating"):format(ns.Thousands(p.rating)))
			item:Show()
		else
			bar:Hide()
			item:Hide()
		end
	end

	-- Chips: leech, avoidance, speed, and a tank's dodge, parry and block, when they count.
	local rest = {}
	for _, e in ipairs(entries) do
		if e.group >= 3 then
			rest[#rest + 1] = e
		end
	end
	local cx, cy, n = 0, SPLIT_Y - 46 - 2 * LEGEND_ROW - 6, 0
	for i, e in ipairs(ns.CharShow_FilterStats(rest, isTank, hasShield)) do
		local chip = Chip(i)
		chip.text:SetText(("%s  %s"):format(e.label, (ns.CharShow_StatText(e))))
		local w = math.ceil(chip.text:GetUnboundedStringWidth()) + 20
		chip:SetWidth(w)
		if cx > 0 and cx + w > STATS_W then
			cx, cy = 0, cy - 30
		end
		chip:ClearAllPoints()
		chip:SetPoint("TOPLEFT", cx, cy)
		chip:Show()
		cx = cx + w + 8
		n = i
	end
	for i = n + 1, #(stats.chips or {}) do
		stats.chips[i]:Hide()
	end
end

local function CreateStats()
	stats = CreateFrame("Frame", nil, root)
	stats:SetSize(STATS_W, 600)
	stats:EnableMouse(true) -- clicks here don't reach the world (no camera grab)
	groups.stats = stats
	CreateNameBlock()
	CreateDial()
	CreateTiles()
	CreateSplit()
	stats.close = UI.Button(stats, 28, "x")
	stats.close:SetHeight(28)
	stats.close:SetPoint("TOPRIGHT", stats, "TOPRIGHT", 10, 0)
	stats.close:SetScript("OnClick", function()
		ns.CharShow_Close()
	end)
end

-- Scene contract -----------------------------------------------------------------------------------------------------

local function CreateShade(side, design)
	local t = Tex(shadeFrame, "BACKGROUND", nil, nil, -8)
	t:SetPoint("TOP" .. side)
	t:SetPoint("BOTTOM" .. side)
	local dark, clear = CreateColor(0, 0, 0, side == "LEFT" and 0.62 or 0.82), CreateColor(0, 0, 0, 0)
	if side == "LEFT" then
		t:SetGradient("HORIZONTAL", dark, clear)
	else
		t:SetGradient("HORIZONTAL", clear, dark)
	end
	shades[side] = { tex = t, design = design }
end

local function CreateGearGroup(key, list, side)
	local group = CreateFrame("Frame", nil, root)
	group:SetSize(BOX_W, DESIGN_H)
	groups[key] = group
	local rail = UI.VLine(group, 0.55)
	rails[#rails + 1] = rail
	local railX = side == "LEFT" and ICON_C or BOX_W - ICON_C
	rail:SetPoint("TOP", group, "TOPLEFT", railX, -RAIL_TOP)
	rail:SetPoint("BOTTOM", group, "TOPLEFT", railX, -RAIL_BOTTOM)
	for row, slot in ipairs(list) do
		if slot then
			slotOrder[#slotOrder + 1] = CreateSlot(group, slot, side, row)
		end
	end
end

function SCENE.Create(parent)
	root = parent
	tooltip = CreateFrame("GameTooltip", "TomteShowcaseTooltip", root, "GameTooltipTemplate") -- named: the template
	tooltip:SetFrameStrata("TOOLTIP")
	shadeFrame = CreateFrame("Frame", nil, root)
	shadeFrame:SetAllPoints(root)
	shadeFrame:SetFrameLevel(root:GetFrameLevel()) -- under the gear and stats groups
	CreateShade("LEFT", SHADE_LEFT)
	CreateShade("RIGHT", SHADE_RIGHT)
	CreateGearGroup("left", ns.CHARSHOW_LEFT, "LEFT")
	CreateGearGroup("right", ns.CHARSHOW_RIGHT, "RIGHT")
	CreateStats()
end

-- Groups are scaled so the design's 900 units fill the screen height, and placed at the design's fraction of the width.
local function Layout()
	-- The screen in the scene's units (from WorldFrame: the scene may not have its size yet on the first Begin).
	local toScene = WorldFrame:GetEffectiveScale() / root:GetEffectiveScale()
	local width, height = WorldFrame:GetWidth() * toScene, WorldFrame:GetHeight() * toScene
	local k = height / DESIGN_H
	local function At(x)
		return x / DESIGN_W * width / k -- a design x as an offset in a group's own (scaled) units
	end
	for _, g in pairs(groups) do
		g:SetScale(k)
		g:ClearAllPoints()
	end
	groups.left:SetPoint("TOPLEFT", root, "TOPLEFT", At(LEFT_X), 0)
	groups.right:SetPoint("TOPRIGHT", root, "TOPLEFT", At(RIGHT_X), 0)
	groups.stats:SetPoint("TOPLEFT", root, "TOPLEFT", At(STATS_X), -STATS_Y)
	for _, shade in pairs(shades) do
		shade.tex:SetWidth(shade.design / DESIGN_W * width)
	end
end

function SCENE.Begin(state)
	-- Same on-screen size as the normal UI, whatever the UI scale.
	root:SetScale(UIParent:GetEffectiveScale() / WorldFrame:GetEffectiveScale())
	showHints = state.hints ~= false
	Layout()
	SCENE.Refresh()
	closing, closeT = false, 0
	root:SetAlpha(0)
end

function SCENE.Refresh()
	if not root then
		return
	end
	for _, w in ipairs(slotOrder) do
		RefreshSlot(w)
	end
	RefreshStats()
end

function SCENE.RefreshStats()
	if root then
		RefreshStats()
	end
end

function SCENE.Update(contentAlpha, dt)
	if closing then
		closeT = closeT + (dt or 0)
		root:SetAlpha(math.max(0, 1 - closeT / CLOSE_FADE))
		return
	end
	root:SetAlpha(1)
	stats:SetAlpha(contentAlpha)
	shadeFrame:SetAlpha(math.min(contentAlpha * 1.5, 1))
	for _, rail in ipairs(rails) do
		rail:SetAlpha(contentAlpha)
	end
	for i, w in ipairs(slotOrder) do
		w:SetAlpha(math.max(0, math.min(1, contentAlpha * 1.6 - (i - 1) * SLOT_FADE_STEP)))
	end
end

function SCENE.End()
	closing, closeT = true, 0
	tooltip:Hide()
	ns.CharShow_OnEnd()
end

-- Whether the mouse is over the scene's own frames (a press there isn't a camera grab).
function SCENE.MouseOverOwn()
	if not root or not root:IsVisible() then
		return false
	end
	if stats:IsMouseOver() then
		return true
	end
	for _, w in ipairs(slotOrder) do
		if w:IsMouseOver() then
			return true
		end
	end
	return false
end
