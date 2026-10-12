local addonName, ns = ...

-- Showcase slot card: our own item card on a slot hover, as in the mockup's "Slot tooltip" frame. Quality rule and
-- the item's 3D model (its icon for jewelry, or while the model can't show), item level with the upgrade track, slot, armor type and bind state, stats with your percent, Use/Equip
-- lines, enchant and sockets, Gear Check's rank lines, and the click hints. Holding Alt swaps it for the full game
-- tooltip. Design: docs/superpowers/specs/2026-10-12-tomte-showcase-gear-menu-design.md.

local UI = ns.UI
local ART = ns.Theme.MEDIA .. "Showcase\\"
local DIAMOND, GLOW, RING, STAR = ART .. "Diamond", ART .. "Glow", ART .. "Ring", ART .. "Star"

local W, PAD = 380, 20
local ICON_X, ICON_Y = W - 53, -49 -- the icon diamond's center
local MODEL_W, MODEL_H = 140, 120 -- the item model, top right (height: at least; it fills the header)
local MODEL_TOP, MODEL_GAP = 10, 12 -- from the card's top edge, and above the divider
local NAME_W = W - 2 * PAD - 110
local ROW = 21
local FOOTER_H = 32
local MAX_EFFECTS = 4
-- Secondary stat colors, as on the stats panel's split bar (Scene.lua).
local STAT_ROLES = { CRIT = "danger", HASTE = "warning", MASTERY = "accent", VERS = "success" }
local PRIMARY_KEYS = { [1] = "STR", [2] = "AGI", [4] = "INT" }
local RATINGS = { CRIT = "CR_CRIT_MELEE", HASTE = "CR_HASTE_MELEE", MASTERY = "CR_MASTERY",
	VERS = "CR_VERSATILITY_DAMAGE_DONE" }
local LINE = Enum.TooltipDataLineType
local EFFECT_TYPES = {
	[LINE.ItemSpellTriggerOnUse] = true, [LINE.ItemSpellTriggerOnEquip] = true, [LINE.ItemSpellTriggerOnProc] = true,
}
local BIND_LABELS = {
	soulbound = "ITEM_SOULBOUND", warbound = "ITEM_ACCOUNTBOUND", warboundUntilEquip = "ITEM_ACCOUNTBOUND_UNTIL_EQUIP",
	boe = "ITEM_BIND_ON_EQUIP",
}
local ARMOR_CLASS, WEAPON_CLASS = 4, 2

local CARD = {}
ns.CharShowCard = CARD
-- The module's event frame, shared by Menu.lua and Showcase.lua (loaded after this file).
ns.CharShow_Events = ns.NewEvents()

local card, tooltip
local owner -- the slot widget the card is showing
local altShown = false
local watcher = CreateFrame("Frame") -- watches Alt while a slot is hovered
watcher:Hide()

-- Pools: a fill takes what it needs from the start of each pool; the rest is hidden.
local pools = { texts = {}, swatches = {}, icons = {}, rings = {}, stars = {}, pips = {} }
local used = {}

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

local function Tint(t, color, alpha)
	t:SetVertexColor(UI.RGBA(color, alpha))
end

local function Take(name, make)
	local pool = pools[name]
	used[name] = (used[name] or 0) + 1
	local item = pool[used[name]]
	if not item then
		item = make()
		pool[used[name]] = item
	end
	item:ClearAllPoints()
	item:Show()
	return item
end

local function ReleaseAll()
	for name, pool in pairs(pools) do
		for i = 1, #pool do
			pool[i]:Hide()
		end
		used[name] = 0
	end
end

-- A pooled text. width: wrap at it; nil: one line.
local function Text(size, role, fontRole, width)
	local fs = Take("texts", function()
		local f = card.body:CreateFontString(nil, "OVERLAY")
		f:SetShadowOffset(1, -1)
		f:SetShadowColor(0, 0, 0, 0.8)
		return f
	end)
	ns.Theme.SetFont(fs, fontRole or "body", size)
	fs:SetTextColor(UI.RGBA(role or "text"))
	fs:SetJustifyH("LEFT")
	fs:SetWordWrap(width ~= nil)
	fs:SetWidth(width or 0)
	return fs
end

local function Put(region, x, y)
	region:SetPoint("TOPLEFT", card.body, "TOPLEFT", x, y)
end

local function PutRight(region, y)
	region:SetPoint("TOPRIGHT", card.body, "TOPRIGHT", -PAD, y)
end

local function Swatch(role)
	local t = Take("swatches", function()
		return Tex(card.body, "ARTWORK")
	end)
	t:SetSize(4, 16)
	Tint(t, role, 1)
	return t
end

local function GemIcon(file)
	local t = Take("icons", function()
		local i = Tex(card.body, "ARTWORK", nil, 16)
		UI.CircleMask(i, card.body)
		return i
	end)
	t:SetTexture(file)
	return t
end

local function SocketRing(role)
	local t = Take("rings", function()
		return Tex(card.body, "OVERLAY", RING, 18)
	end)
	Tint(t, role, 1)
	return t
end

local function Star(role)
	local t = Take("stars", function()
		return Tex(card.body, "ARTWORK", STAR, 12)
	end)
	Tint(t, role, 1)
	return t
end

local function Pip(lit)
	local t = Take("pips", function()
		return Tex(card.body, "ARTWORK", DIAMOND, 8)
	end)
	Tint(t, "heading", lit and 1 or 0.25)
	return t
end

-- Data ---------------------------------------------------------------------------------------------------------------

local function StatLabels()
	return {
		ARMOR = RESISTANCE0_NAME or "Armor", STR = SPELL_STAT1_NAME, AGI = SPELL_STAT2_NAME, INT = SPELL_STAT4_NAME,
		STA = SPELL_STAT3_NAME, CRIT = STAT_CRITICAL_STRIKE, HASTE = STAT_HASTE, MASTERY = STAT_MASTERY,
		VERS = STAT_VERSATILITY,
	}
end

local function PrimaryKey(ctx)
	if ctx and ctx.primary then
		return ctx.primary
	end
	local spec = C_SpecializationInfo.GetSpecialization()
	local primaryStat = spec and select(6, C_SpecializationInfo.GetSpecializationInfo(spec))
	return PRIMARY_KEYS[primaryStat]
end

-- What this much of a secondary rating is worth to you, in percent (nil when unknown or secret).
local function StatPercent(key, amount)
	local cr = _G[RATINGS[key]]
	if not (cr and GetCombatRatingBonusForCombatRatingValue) then
		return nil
	end
	local bonus = GetCombatRatingBonusForCombatRatingValue(cr, amount)
	if type(bonus) ~= "number" or not ns.Readable(bonus) then
		return nil
	end
	if key == "MASTERY" then
		-- The rating gives mastery points; the spec turns each point into its own percent.
		local effect, points = GetMasteryEffect(), GetMastery()
		if not ns.Readable(effect, points) or type(points) ~= "number" or points <= 0 then
			return nil
		end
		bonus = bonus * effect / points
	end
	return bonus
end

local function MetaLine(slot, desc, link)
	local slotName = desc.equipLoc and _G[desc.equipLoc]
	local subType
	if desc.classID == WEAPON_CLASS or (desc.classID == ARMOR_CLASS and desc.subclassID and desc.subclassID >= 1
		and desc.subclassID <= 4 and desc.equipLoc ~= "INVTYPE_CLOAK") then
		subType = C_Item.GetItemSubClassInfo(desc.classID, desc.subclassID)
	end
	local state = ns.GearItems_BindState(link, ItemLocation:CreateFromEquipmentSlot(slot))
	local bind = state and _G[BIND_LABELS[state]]
	return ns.CharShow_MetaLine(slotName, subType, bind)
end

-- Use / Equip / proc lines, from the worn item's tooltip data.
local function EffectLines(slot)
	local list = {}
	local data = C_TooltipInfo.GetInventoryItem("player", slot)
	for _, line in ipairs(data and data.lines or {}) do
		local text = line.leftText
		if EFFECT_TYPES[line.type] and text and not ns.IsSecret(text) and text ~= "" and #list < MAX_EFFECTS then
			list[#list + 1] = text
		end
	end
	return list
end

-- Building ------------------------------------------------------------------------------------------------------------

local function CreateCard(parent)
	card = CreateFrame("Frame", nil, parent)
	card:SetFrameStrata("TOOLTIP")
	card:SetWidth(W)
	card:SetClampedToScreen(true)
	card:Hide()
	local bg = Tex(card, "BACKGROUND", nil, nil, -8)
	bg:SetAllPoints()
	Tint(bg, "bg", 0.94)
	UI.Border(card, "frame", 0.35)
	card.glow = Tex(card, "BACKGROUND", GLOW, 220, -7)
	card.glow:SetPoint("CENTER", card, "TOPLEFT", ICON_X, ICON_Y)
	card.glow:SetBlendMode("ADD")
	card.rule = Tex(card, "ARTWORK")
	card.rule:SetPoint("TOPLEFT")
	card.rule:SetPoint("TOPRIGHT")
	card.rule:SetHeight(2)

	local function Centered(t)
		t:SetPoint("CENTER", card, "TOPLEFT", ICON_X, ICON_Y)
		return t
	end
	card.edge = Centered(Tex(card, "BORDER", DIAMOND, 70))
	card.inner = Centered(Tex(card, "BORDER", DIAMOND, 64, 1))
	Tint(card.inner, "frameDark", 0.95)
	card.icon = Centered(Tex(card, "ARTWORK", nil, 58))
	local mask = card:CreateMaskTexture()
	mask:SetTexture(DIAMOND, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
	mask:SetAllPoints(card.icon)
	card.icon:AddMaskTexture(mask)

	-- The item on a featureless mannequin (armor) or on its own (weapons), with the transmog collection's camera
	-- for its slot: Blizzard's wardrobe models do the same (Blizzard_Wardrobe.lua).
	card.model = CreateFrame("DressUpModel", nil, card)
	card.model:SetWidth(MODEL_W)
	card.model:SetUseTransmogSkin(true)
	card.model:SetAutoDress(false)
	card.model:SetKeepModelOnHide(true)
	card.model:SetDoBlend(false)
	card.model:SetObeyHideInTransmogFlag(true)
	card.model:SetScript("OnModelLoaded", function(self)
		if self.cameraID then
			self:RefreshCamera()
			Model_ApplyUICamera(self, self.cameraID)
		end
	end)
	card.model:Hide()

	card.body = CreateFrame("Frame", nil, card)
	card.body:SetAllPoints()
	card.body:SetFrameLevel(card.model:GetFrameLevel() + 1)

	card.divider = UI.Hairline(card.body, W - 2 * PAD, 0.45)

	card.verdict = CreateFrame("Frame", nil, card.body)
	card.verdict:SetWidth(W - 2 * PAD)
	card.verdict.bg = Tex(card.verdict, "BACKGROUND")
	card.verdict.bg:SetAllPoints()
	UI.Border(card.verdict, "success", 0.35)
	card.verdict.mark = Tex(card.verdict, "ARTWORK", DIAMOND, 12)
	card.verdict.mark:SetPoint("TOPLEFT", 12, -11)
	card.verdict.lines = {}

	card.footer = CreateFrame("Frame", nil, card)
	card.footer:SetPoint("BOTTOMLEFT")
	card.footer:SetPoint("BOTTOMRIGHT")
	card.footer:SetHeight(FOOTER_H)
	local fbg = Tex(card.footer, "BACKGROUND")
	fbg:SetAllPoints()
	Tint(fbg, "frameDark", 0.55)
	local fline = Tex(card.footer, "BORDER")
	fline:SetPoint("TOPLEFT")
	fline:SetPoint("TOPRIGHT")
	fline:SetHeight(1)
	Tint(fline, "frame", 0.18)
	local left = UI.Text(card.footer, 12, "textFaint")
	left:SetPoint("LEFT", PAD, 0)
	left:SetText("Click for options")
	local right = UI.Text(card.footer, 12, "textFaint")
	right:SetPoint("RIGHT", -PAD, 0)
	right:SetText("Shift-click to link")

	-- The key hint above the card: [Alt] Full tooltip.
	local hint = CreateFrame("Frame", nil, card)
	hint:SetSize(160, 24)
	hint:SetPoint("BOTTOMLEFT", card, "TOPLEFT", 0, 6)
	local key = CreateFrame("Frame", nil, hint)
	key:SetSize(40, 22)
	key:SetPoint("LEFT")
	local kbg = Tex(key, "BACKGROUND")
	kbg:SetAllPoints()
	Tint(kbg, "surface", 1)
	UI.Border(key, "frame", 0.6)
	local ktext = UI.Text(key, 12, "heading", "label")
	ktext:SetPoint("CENTER", 0, 0)
	ktext:SetText(ALT_KEY_TEXT or "Alt")
	local htext = UI.Text(hint, 13, "textMuted")
	htext:SetPoint("LEFT", key, "RIGHT", 8, 0)
	htext:SetText("Full tooltip")
end

-- Slots with no appearance of their own: the icon instead of a model.
local NO_MODEL = { [2] = true, [11] = true, [12] = true, [13] = true, [14] = true }

local SWORD_CAMERA = 238 -- the transmog collection's sword camera: for weapons without a camera of their own

local function Debug(text)
	if ns.charShowDB and ns.charShowDB.debugCamera then
		ns.Print("Showcase model: " .. text)
	end
end

-- The worn slot's own appearance (sourceID, visualID): for items C_TransmogCollection.GetItemInfo knows nothing
-- about (not transmoggable). 12.x transmog locations: Narcissus builds them the same way.
local function SlotAppearance(slot)
	if not (C_Transmog.GetSlotVisualInfo and C_TransmogOutfitInfo and TransmogLocationMixin) then
		return nil
	end
	local ok, info = pcall(function()
		local location = CreateFromMixins(TransmogLocationMixin)
		location:Set({ slotID = slot, slot = C_TransmogOutfitInfo.GetTransmogOutfitSlotFromInventorySlot(slot - 1),
			transmogType = 0, isSecondary = false })
		return C_Transmog.GetSlotVisualInfo(location:GetData())
	end)
	if ok and type(info) == "table" then
		return info.baseSourceID, info.baseVisualID
	end
	return nil
end

-- Shows the item's model; false when it has none (jewelry, no appearance, player model not ready). Weapons (item
-- class 2) are shown on their own by their appearance (SetItemAppearance); armor, shields and off-hand frills on
-- the mannequin (TryOn).
local function ShowModel(slot, link, desc)
	local model = card.model
	if NO_MODEL[slot] then
		return false
	end
	local visualID, sourceID = C_TransmogCollection.GetItemInfo(link)
	if not (visualID and sourceID) or sourceID == 0 then
		sourceID, visualID = SlotAppearance(slot)
	end
	if not (visualID and sourceID) or sourceID == 0 or visualID == 0 then
		Debug(("no appearance for slot %d"):format(slot))
		return false
	end
	local weapon = desc.classID == WEAPON_CLASS
	if not weapon and not IsUnitModelReadyForUI("player") then
		Debug("player model not ready")
		return false
	end
	if model.sourceID ~= sourceID then
		model.sourceID = sourceID
		local cameraID = C_TransmogCollection.GetAppearanceCameraIDBySource(sourceID)
		if weapon and (not cameraID or cameraID == 0) then
			cameraID = SWORD_CAMERA
		end
		model.cameraID = cameraID
		Debug(("slot %d source %d visual %d camera %s"):format(slot, sourceID, visualID, tostring(cameraID)))
		if weapon then
			model:SetItemAppearance(visualID)
		else
			model:SetUnit("player", false)
			model:Undress()
			model:FreezeAnimation(0, 0, 0)
			model:TryOn(sourceID)
		end
	end
	model:Show()
	model:RefreshCamera()
	if model.cameraID then
		Model_ApplyUICamera(model, model.cameraID)
	end
	return true
end

-- Header: name, item level, track and pips, meta line. Returns the y below it.
local function FillHeader(w, desc, link, color)
	Tint(card.edge, color, 1)
	Tint(card.glow, color, 0.35)
	card.rule:SetGradient("HORIZONTAL", UI.ColorObject(color, 1), UI.ColorObject(color, 0))
	card.icon:SetTexture(GetInventoryItemTexture("player", w.slot))
	local modeled = ShowModel(w.slot, link, desc)
	if not modeled then
		card.model:Hide()
	end
	card.edge:SetShown(not modeled)
	card.inner:SetShown(not modeled)
	card.icon:SetShown(not modeled)

	local name = Text(20, color, "title", NAME_W)
	name:SetText(C_Item.GetItemNameByID(link) or C_Item.GetItemInfo(link) or "")
	Put(name, PAD, -18)
	local y = -18 - math.ceil(name:GetStringHeight()) - 6

	local ilvl = Text(38, "heading", "number")
	ilvl:SetText(w.ilvl or "")
	Put(ilvl, PAD, y)
	local x = PAD + math.ceil(ilvl:GetUnboundedStringWidth()) + 12
	local track, cur, max = ns.CharShow_Track(desc.upgrade)
	if track then
		local word = Text(12, "textMuted")
		word:SetText(track)
		Put(word, x, y - 8)
		x = x + math.ceil(word:GetUnboundedStringWidth()) + 6
		for i = 1, max do
			Put(Pip(i <= cur), x, y - 11)
			x = x + 9
		end
		local maxIlvl = desc.upgrade.maxIlvl
		if maxIlvl and w.ilvl and maxIlvl > w.ilvl then
			local m = Text(11, "textFaint", "number")
			m:SetText(("max %d"):format(maxIlvl))
			Put(m, x + 4, y - 9)
		end
	end
	y = y - 44
	local meta = Text(14, "textMuted")
	meta:SetText(MetaLine(w.slot, desc, link))
	Put(meta, PAD, y)
	local bottom = math.min(y - 24, modeled and -(MODEL_TOP + MODEL_H + MODEL_GAP) or -100)
	if modeled then
		-- The model fills the header: from just under the top edge to a gap above the divider.
		card.model:ClearAllPoints()
		card.model:SetPoint("TOPRIGHT", card, "TOPRIGHT", -10, -MODEL_TOP)
		card.model:SetHeight(-bottom - MODEL_TOP - MODEL_GAP)
		card.model:RefreshCamera() -- framed again for the new size
		if card.model.cameraID then
			Model_ApplyUICamera(card.model, card.model.cameraID)
		end
	end
	return bottom
end

local function FillStats(desc, ctx, y)
	for _, row in ipairs(ns.CharShow_CardStats(desc.stats, PrimaryKey(ctx), StatLabels())) do
		if row.secondary then
			Put(Swatch(STAT_ROLES[row.key] or "accent"), PAD, y - 1)
			local t = Text(15, "text")
			t:SetText(row.text)
			Put(t, PAD + 14, y)
			local pct = ns.CharShow_Percent(StatPercent(row.key, row.amount))
			if pct then
				local p = Text(14, "textMuted", "number")
				p:SetText(pct)
				PutRight(p, y)
			end
		else
			local t = Text(15, "text")
			t:SetText(row.text)
			Put(t, PAD, y)
		end
		y = y - ROW
	end
	return y
end

local function FillEffects(slot, y)
	for _, text in ipairs(EffectLines(slot)) do
		local t = Text(13, "success", nil, W - 2 * PAD)
		t:SetText(text)
		Put(t, PAD, y)
		y = y - math.ceil(t:GetStringHeight()) - 5
	end
	return y
end

-- Enchant line and one row per socket.
local function FillEnchantAndGems(w, desc, ctx, y)
	local hints = w.hints or {}
	local text, role
	if hints.enchant then
		text, role = hints.enchant, "success"
	elseif hints.missing then
		text, role = "No enchant", "danger"
	end
	if text then
		Put(Star(role), PAD, y - 3)
		local t = Text(14, role, nil, W - 2 * PAD - 120)
		t:SetWordWrap(false)
		t:SetText(text)
		Put(t, PAD + 18, y)
		if hints.missing then
			local note = Text(12, "textFaint")
			note:SetText(("%s takes one"):format(_G[desc.equipLoc] or "This slot"))
			PutRight(note, y + 1)
		end
		y = y - ROW
	end
	local gems = desc.gemSlots or {}
	for i = 1, desc.sockets or 0 do
		local id = gems[i]
		if id then
			Put(GemIcon(C_Item.GetItemIconByID(id)), PAD + 1, y - 1)
			Put(SocketRing(w.color or "text"), PAD, y)
			local t = Text(14, "text")
			t:SetText(C_Item.GetItemNameByID(id) or "")
			Put(t, PAD + 24, y)
			local stats = ns.GearItems_GemStats(id)
			if stats then
				local s = Text(12, "textFaint")
				s:SetText(ns.Gear_StatLabel(stats))
				PutRight(s, y + 1)
			end
		else
			Put(SocketRing("danger"), PAD, y)
			local t = Text(14, "danger")
			t:SetText("Empty socket")
			Put(t, PAD + 24, y)
			if ctx and ctx.best then
				local s = Text(12, "textFaint")
				s:SetText(("best: %s"):format(ctx.best.name))
				PutRight(s, y + 1)
			end
		end
		y = y - ROW
	end
	return y
end

-- Gear Check's rank lines in a tinted box (hidden when there are none).
local function FillVerdict(link, y)
	local box = card.verdict
	local lines = ns.Gear_ItemLines and ns.Gear_ItemLines(link) or {}
	for _, fs in ipairs(box.lines) do
		fs:Hide()
	end
	if #lines == 0 then
		box:Hide()
		return y
	end
	local role = "success"
	for _, line in ipairs(lines) do
		if not line.reason and line.role then
			role = line.role
			break
		end
	end
	box.bg:SetColorTexture(UI.RGBA(role, 0.08))
	UI.SetBorderColor(box, role, 0.35)
	Tint(box.mark, role, 1)
	local ly = -9
	for i, line in ipairs(lines) do
		local fs = box.lines[i]
		if not fs then
			fs = UI.Text(box, 13, "text")
			fs:SetWidth(W - 2 * PAD - 44)
			fs:SetWordWrap(true)
			box.lines[i] = fs
		end
		fs:SetTextColor(UI.RGBA(line.reason and "textMuted" or line.role or role))
		ns.Theme.SetFont(fs, "body", line.reason and 12 or 14)
		fs:SetText(line.text)
		fs:ClearAllPoints()
		fs:SetPoint("TOPLEFT", 34, ly)
		fs:Show()
		ly = ly - math.ceil(fs:GetStringHeight()) - 3
	end
	box:SetHeight(-ly + 6)
	box:ClearAllPoints()
	Put(box, PAD, y)
	box:Show()
	return y + ly - 6
end

local function Fill(w)
	ReleaseAll()
	local link = GetInventoryItemLink("player", w.slot)
	local desc = w.desc
	if not link or not desc then
		return false
	end
	local ctx = ns.Gear_Context and ns.Gear_Context()
	local color = w.color or "text"
	local y = FillHeader(w, desc, link, color)
	card.divider:ClearAllPoints()
	Put(card.divider, PAD, y)
	y = FillStats(desc, ctx, y - 14)
	y = FillEffects(w.slot, y - 6)
	y = FillEnchantAndGems(w, desc, ctx, y - 4)
	y = FillVerdict(link, y - 8)
	card:SetHeight(-y + 14 + FOOTER_H)
	return true
end

-- Showing ------------------------------------------------------------------------------------------------------------

local function Place(w)
	card:SetScale(w:GetParent():GetScale()) -- the slot's group scale
	card:ClearAllPoints()
	if w.side == "LEFT" then
		card:SetPoint("TOPLEFT", w, "TOPLEFT", w.cardX or 0, 0)
	else
		card:SetPoint("TOPLEFT", w, "TOPRIGHT", 12, 0)
	end
end

local function ShowFullTooltip(w)
	card:Hide()
	tooltip:SetOwner(w, "ANCHOR_NONE")
	tooltip:ClearAllPoints()
	tooltip:SetPoint("TOPLEFT", card, "TOPLEFT")
	tooltip:SetInventoryItem("player", w.slot)
	tooltip:Show()
end

local function Update()
	if not owner then
		return
	end
	if IsAltKeyDown() then
		ShowFullTooltip(owner)
	else
		tooltip:Hide()
		card:Show()
	end
end

watcher:SetScript("OnUpdate", function()
	local alt = IsAltKeyDown() and true or false
	if alt ~= altShown then
		altShown = alt
		Update()
	end
end)

function CARD.Create(parent, gameTooltip)
	tooltip = gameTooltip
	CreateCard(parent)
end

-- w: a slot widget (Scene.lua) with .slot, .side, .desc, .hints, .color, .ilvl, .cardX.
function CARD.Show(w)
	if not card then
		return
	end
	if not Fill(w) then
		-- Not loaded yet: the game's own tooltip until it is (a refresh brings the card).
		owner = w
		Place(w)
		ShowFullTooltip(w)
		watcher:Hide()
		return
	end
	owner = w
	Place(w)
	altShown = IsAltKeyDown() and true or false
	Update()
	watcher:Show()
end

function CARD.Hide()
	owner = nil
	watcher:Hide()
	if card then
		card:Hide()
	end
	if tooltip then
		tooltip:Hide()
	end
end

-- The slot it shows changed (gear, gems, enchants): fill it again.
function CARD.Refresh()
	if owner then
		CARD.Show(owner)
	end
end

function CARD.IsMouseOver()
	return card and card:IsShown() and card:IsMouseOver()
end
