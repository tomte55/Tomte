local addonName, ns = ...

-- Dungeon journal: loot as a grid of raised tiles (the icon in its frame with a glow in the item's quality color, the
-- name, slot and type, a badge: Upgrade, Owned, the level it needs) with a star for items you want. Shared through
-- ns.DJKit (Read.lua); drawn by Detail.lua.

local TILE_H = 64
local TILE_MIN_W = 210 -- a column is at least this wide: two or three across
local MAX_COLS = 3
local TILE_GAP = 10
local ICON = 40
local GLOW_SCALE = 1.75 -- the quality glow's size against the icon's
local GLOW = "Interface\\Buttons\\UI-ActionButton-Border" -- the game's item glow, tinted by quality
local MIN_GLOW_QUALITY = 2 -- uncommon and up glow
local STAR = 16
local STAR_OFF_ALPHA = 0.35 -- the star on hover, for an item not wanted yet
local NOT_FOR_YOU_ALPHA = 0.55 -- a tile for gear you can't use, while it isn't hidden
local SHADOW_H = 4
local SHADOW_ALPHA = 0.35
-- The star: the first of these atlases the client has, else the reputation star's filled half.
local STAR_ATLASES = { "PetJournal-FavoritesIcon", "auctionhouse-icon-favorite" }
local STAR_TEXTURE = "Interface\\Common\\ReputationStar"

local UI = ns.UI
local J = ns.DJKit

local tiles = {}
local used = 0

-- Art --------------------------------------------------------------------------------------------------------------------

local starAtlas
function J.StarArt(tex, on)
	if starAtlas == nil then
		starAtlas = false
		for _, name in ipairs(STAR_ATLASES) do
			if C_Texture.GetAtlasInfo(name) then
				starAtlas = name
				break
			end
		end
	end
	if starAtlas then
		tex:SetAtlas(starAtlas)
	else
		tex:SetTexture(STAR_TEXTURE)
		tex:SetTexCoord(0, 0.5, 0, 0.5)
	end
	tex:SetDesaturated(not on)
	tex:SetAlpha(on and 1 or STAR_OFF_ALPHA)
end

-- Item text ------------------------------------------------------------------------------------------------------------

-- Slot and type ("Back, Cloth"), from what the client knows without the item loaded.
local function ItemSub(id)
	local _, _, subType, equipLoc, _, classID = C_Item.GetItemInfoInstant(id)
	local slot = equipLoc and equipLoc ~= "" and equipLoc ~= "INVTYPE_NON_EQUIP_IGNORE" and _G[equipLoc]
	local parts = {}
	if slot and slot ~= "" then
		parts[#parts + 1] = slot
	end
	if subType and subType ~= "" and (classID == Enum.ItemClass.Armor or classID == Enum.ItemClass.Weapon) then
		parts[#parts + 1] = subType
	end
	return table.concat(parts, ", ")
end
J.ItemSub = ItemSub

-- The badge: what matters most about the item for you, and its color role.
local function Badge(id, level)
	if J.Owned(id) then
		return "Owned", "textMuted"
	elseif J.IsUpgrade(id) then
		return "Upgrade", "success"
	elseif J.NotForYou(id) then
		return "Not for you", "textFaint"
	end
	local need = select(5, C_Item.GetItemInfo(id))
	if need and need > level then
		return ("Level %d"):format(need), "warning"
	end
	return nil
end

-- Handlers ---------------------------------------------------------------------------------------------------------------

function J.ItemLink(id)
	return select(2, C_Item.GetItemInfo(id))
end

local function Tooltip(self)
	GameTooltip:SetOwner(self, "ANCHOR_NONE")
	GameTooltip:SetPoint("BOTTOMLEFT", self, "TOPLEFT", ICON + 20, -8)
	GameTooltip:SetItemByID(self.itemID)
	UI.TipLine(J.IsWanted(self.itemID) and "Click the star or right-click: not wanted any more"
		or "Click the star or right-click: want this", "textMuted")
	GameTooltip:Show()
end

-- A click on the star, or a right-click, stars it; Shift-click links it to chat, Ctrl-click tries it on.
local function Click(self, button)
	if button == "RightButton" or self.star:IsMouseOver() then
		UI.Sound(J.ToggleWanted(self.itemID) and "on" or "off")
		J.Layout()
		return
	end
	local link = J.ItemLink(self.itemID)
	if link then
		HandleModifiedItemClick(link)
	end
end

local function ShowStar(tile, hover)
	local wanted = J.IsWanted(tile.itemID)
	J.StarArt(tile.star.tex, wanted)
	tile.star:SetShown(wanted or hover)
end

-- A tile ----------------------------------------------------------------------------------------------------------------

local function NewTile(parent)
	local t = CreateFrame("Button", nil, parent)
	t:SetHeight(TILE_H)
	t:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	UI.Surface(t, 0.35)
	t.lift = t:CreateTexture(nil, "BORDER")
	t.lift:SetPoint("TOPLEFT", 1, -1)
	t.lift:SetPoint("TOPRIGHT", -1, -1)
	t.lift:SetHeight(1)
	t.shadow = t:CreateTexture(nil, "BACKGROUND", nil, -2)
	t.shadow:SetPoint("TOPLEFT", t, "BOTTOMLEFT", 1, 0)
	t.shadow:SetPoint("TOPRIGHT", t, "BOTTOMRIGHT", -1, 0)
	t.shadow:SetHeight(SHADOW_H)
	t.shadow:SetColorTexture(1, 1, 1)
	UI.HoverWash(t)

	t.iconFrame = CreateFrame("Frame", nil, t)
	t.iconFrame:SetSize(ICON, ICON)
	t.iconFrame:SetPoint("TOPLEFT", 10, -(TILE_H - ICON) / 2)
	t.icon = t.iconFrame:CreateTexture(nil, "ARTWORK")
	t.icon:SetAllPoints()
	UI.ActionIcon(t.iconFrame, t.icon, ICON)
	t.glow = t.iconFrame:CreateTexture(nil, "OVERLAY", nil, 2)
	t.glow:SetTexture(GLOW)
	t.glow:SetBlendMode("ADD")
	t.glow:SetSize(ICON * GLOW_SCALE, ICON * GLOW_SCALE)
	t.glow:SetPoint("CENTER")

	t.name = UI.Text(t, 14, "text")
	t.name:SetJustifyH("LEFT")
	t.name:SetJustifyV("TOP")
	t.name:SetPoint("TOPLEFT", t.iconFrame, "TOPRIGHT", 10, 0)
	t.name:SetPoint("RIGHT", t, "RIGHT", -(STAR + 10), 0)
	t.name:SetMaxLines(2)
	t.sub = UI.Text(t, 12, "textMuted")
	t.sub:SetJustifyH("LEFT")
	t.sub:SetWordWrap(false)
	t.sub:SetPoint("BOTTOMLEFT", t.iconFrame, "BOTTOMRIGHT", 10, 0)
	t.badge = UI.Text(t, 12, "success")
	t.badge:SetJustifyH("RIGHT")
	t.badge:SetPoint("BOTTOMRIGHT", t, "BOTTOMRIGHT", -10, (TILE_H - ICON) / 2)
	t.sub:SetPoint("RIGHT", t.badge, "LEFT", -8, 0)

	-- Only a picture: a frame of its own would take the mouse, and the tile would see it leave (and hide the star) as
	-- the pointer reached it. Click reads whether the click landed on it.
	t.star = CreateFrame("Frame", nil, t)
	t.star:SetSize(STAR + 8, STAR + 8)
	t.star:SetPoint("TOPRIGHT", -2, -2)
	t.star.tex = t.star:CreateTexture(nil, "OVERLAY")
	t.star.tex:SetSize(STAR, STAR)
	t.star.tex:SetPoint("CENTER")

	t:SetScript("OnClick", Click)
	t:SetScript("OnEnter", function(self)
		UI.HoverOn(self)
		ShowStar(self, true)
		Tooltip(self)
	end)
	t:SetScript("OnLeave", function(self)
		UI.HoverOff(self, self.mark and "accent" or "frame", self.mark and 1 or 0.35)
		ShowStar(self, false)
		GameTooltip:Hide()
	end)
	return t
end

local function Fill(t, id, level)
	t.itemID = id
	t.icon:SetTexture(C_Item.GetItemIconByID(id))
	local name = J.ItemName(id)
	local quality = C_Item.GetItemQualityByID(id)
	if name and quality then
		local r, g, b = C_Item.GetItemQualityColor(quality)
		t.name:SetTextColor(r, g, b)
		t.glow:SetVertexColor(r, g, b)
		t.glow:SetShown(quality >= MIN_GLOW_QUALITY)
	else
		UI.SetTextRole(t.name, "textFaint")
		t.glow:Hide()
	end
	t.name:SetText(name or "Loading...")
	t.sub:SetText(ItemSub(id))
	local badge, role = Badge(id, level)
	t.badge:SetText(badge or "")
	UI.SetTextRole(t.badge, role or "textMuted")
	t:SetAlpha(J.NotForYou(id) and NOT_FOR_YOU_ALPHA or 1)
	t.lift:SetColorTexture(UI.RGBA("text", 0.06))
	t.shadow:SetGradient("VERTICAL", UI.ColorObject("frameDark", 0), UI.ColorObject("frameDark", SHADOW_ALPHA))
	t.mark = J.state.mark == id
	-- A redraw under the pointer (an item's data arriving as its tooltip shows) keeps the hover look.
	local hover = t:IsVisible() and t:IsMouseOver()
	if not hover then
		UI.SetBorderColor(t, t.mark and "accent" or "frame", t.mark and 1 or 0.35)
	end
	ShowStar(t, hover)
end

-- The grid --------------------------------------------------------------------------------------------------------------

function J.BeginTiles()
	used = 0
	J.markY = nil
end

function J.HideUnusedTiles()
	for i = used + 1, #tiles do
		tiles[i]:Hide()
	end
end

-- Should this item show? Not one the server doesn't have, nor (with Usable by you on) gear Gear Check says isn't for you.
function J.Shown(id)
	return not J.missing[id] and not (J.DB().usableOnly and J.NotForYou(id))
end

-- Lays out ids as tiles in parent from y, x = J.PAD; returns the y under them. A marked tile's top is kept in J.markY.
function J.Tiles(parent, ids, y, width)
	local cols = math.max(1, math.min(MAX_COLS, math.floor((width + TILE_GAP) / (TILE_MIN_W + TILE_GAP))))
	local w = (width - (cols - 1) * TILE_GAP) / cols
	local level = UnitLevel("player")
	local n = 0
	for _, id in ipairs(ids) do
		if J.Shown(id) then
			used = used + 1
			local t = tiles[used]
			if not t then
				t = NewTile(parent)
				tiles[used] = t
			end
			t:SetParent(parent)
			local col, rowN = n % cols, math.floor(n / cols)
			local top = y + rowN * (TILE_H + TILE_GAP)
			t:ClearAllPoints()
			t:SetPoint("TOPLEFT", parent, "TOPLEFT", J.PAD + col * (w + TILE_GAP), -top)
			t:SetWidth(w)
			Fill(t, id, level)
			t:Show()
			if t.mark then
				J.markY = top
			end
			n = n + 1
		end
	end
	if n == 0 then
		return y
	end
	return y + math.ceil(n / cols) * (TILE_H + TILE_GAP)
end
