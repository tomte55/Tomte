local addonName, ns = ...

-- Tomte map: the game's own minimap pictures over the map art when zoomed in close, the way OpenMap blends them in
-- (its Map/Close.lua). Which file shows each terrain tile is in Data/Forever/MinimapTiles.lua (tools/minimaptiles.py);
-- tiles are placed through the continent's world corners (C_Map.GetWorldPosFromMapPos) and drawn only near the view,
-- from a pool. Geometry in Data.lua; Window.lua calls ns.MapMini_Update after every move.

local FADE_FROM, FADE_TO = 10, 22 -- zoom: the tiles fade in between these (a tile is about 100 to 230 pixels there)
local MIX = 0.85 -- the tiles' alpha once faded in: a little of the map's colour stays under them
local DESATURATE = 0.35 -- the minimap's colours are stronger than the parchment's (OpenMap uses the same)
local MAX_TILES = 120 -- never more textures than this: zoomed out further, no tiles
local LEVEL = 20 -- frame levels above the canvas: over every zone's art, under the quest area (Pins.lua, 30)

local layer
local tiles = {} -- { box, file }, both continents
local pool, used = {}, 0
local built = false

-- The world corners of a continent's map, as a function from world yards to 0..1 on it, and its instance map ID.
local function Corners(mapID)
	local function W(x, y)
		local instance, pos = C_Map.GetWorldPosFromMapPos(mapID, CreateVector2D(x, y))
		if pos then
			local wx, wy = pos:GetXY()
			return instance, { x = wx, y = wy }
		end
	end
	local instance, w00 = W(0, 0)
	local _, w10 = W(1, 0)
	local _, w01 = W(0, 1)
	if not (w00 and w10 and w01) then
		return nil
	end
	return ns.Map_FromWorld(w00, w10, w01), instance
end

local function Build()
	built = true
	local data = ns.Content_Get(ns.CONTENT_FOREVER, "minimapTiles")
	if not data then
		return
	end
	for _, c in ipairs(ns.MapArt_Continents()) do
		local from, instance = Corners(c.mapID)
		local files = from and instance and data[instance]
		if files then
			for key, file in pairs(files) do
				local n, w, s, e = ns.Map_MiniTileWorld(key)
				local x1, y1 = from(n, w)
				local x2, y2 = from(s, e)
				local l, t = ns.Map_InBox(c.box, math.min(x1, x2), math.min(y1, y2))
				local r, b = ns.Map_InBox(c.box, math.max(x1, x2), math.max(y1, y2))
				tiles[#tiles + 1] = { box = { l = l, t = t, w = r - l, h = b - t }, file = file }
			end
		end
	end
end

local function Texture(i)
	local tex = pool[i]
	if not tex then
		tex = layer:CreateTexture(nil, "ARTWORK")
		tex:SetDesaturation(DESATURATE)
		pool[i] = tex
	end
	return tex
end

-- Window.lua: the canvas frame (built once).
function ns.MapMini_Init(canvas)
	layer = CreateFrame("Frame", nil, canvas)
	layer:SetAllPoints(canvas)
	layer:EnableMouse(false)
	layer:SetFrameLevel(canvas:GetFrameLevel() + LEVEL)
end

-- After every move: the tiles near the view, at the alpha this zoom gives them.
function ns.MapMini_Update(viewBox, zoom)
	if not layer then
		return
	end
	local mix = MIX * ns.Map_Fade(zoom, FADE_FROM, FADE_TO)
	local near = {}
	if mix > 0 then
		if not built then
			Build()
		end
		for _, tile in ipairs(tiles) do
			if ns.Map_Overlaps(tile.box, viewBox) then
				near[#near + 1] = tile
				if #near > MAX_TILES then
					near = {}
					break
				end
			end
		end
	end
	local n = #near
	for i, tile in ipairs(near) do
		local tex = Texture(i)
		if tex.file ~= tile.file then
			tex:SetTexture(tile.file, nil, nil, "LINEAR")
			tex.file = tile.file
		end
		if tex.tile ~= tile then
			tex.tile = tile
			tex:ClearAllPoints()
			tex:SetPoint("TOPLEFT", layer, "TOPLEFT", tile.box.l, -tile.box.t)
			tex:SetSize(tile.box.w, tile.box.h)
		end
		tex:Show()
	end
	for i = n + 1, used do
		pool[i]:Hide()
	end
	used = n
	layer:SetAlpha(mix)
	layer:SetShown(n > 0)
end
