local addonName, ns = ...

-- Tomte map: the art. The world map's own picture, both continents and every zone, each a frame on the canvas in its
-- own art pixels, scaled to where the world map puts that map (C_Map.GetMapRectOnMap). A zone's picture also shows its
-- neighbours and a parchment border. With the Tomte_MapArt addon a zone's picture is drawn through its soft territory
-- mask (its land and what lies nearer it than any other zone's, tools/mapart.py), its explored-area pieces over it
-- (every one, or only those you've explored: Map.lua's "whole map" setting) and its place names drawn again above every
-- zone (the addon's names masks); without it, the zone is drawn from
-- its explored-area pieces, every one of them (Data/Forever/MapReveal.lua), which cover only its own land. A zone
-- without pieces there is cut to its own shape: its art is sampled on a grid, the game says which zone owns each point
-- (C_Map.GetMapInfoAtPosition on the continent) and only the zone's own cells are drawn, as horizontal runs (blocky:
-- the game only knows rough shapes), with the parts of it you've explored (C_MapExplorationInfo) over it, as the
-- game's map does. Built on first sight, a few hundred samples and textures a frame (setting hundreds of files at once
-- hitches; OpenMap measured about 35 ms for 300), hidden while out of view. The loader is a child of the canvas, so it
-- pauses while the window is closed and goes on when it opens. Geometry in Data.lua; the view in Window.lua.

local LOAD_PER_FRAME = 48 -- texture files set per frame while art loads
local CELL = 12 -- art pixels: the grid a zone is cut on (about 1.2% of a zone's width; finer is smoother and slower)
local SAMPLES_PER_FRAME = 500 -- GetMapInfoAtPosition calls per frame while zones are cut
local ART_ADDON = "Tomte_MapArt" -- the zone masks, made by tools/mapart.py (optional, shipped on its own)
local MASKS = "Interface\\AddOns\\Tomte_MapArt\\Masks\\" -- then Zone<uiMapArtID> or Continent<uiMapArtID>
local FLAT = "Interface\\AddOns\\Tomte_MapArt\\Flat\\" -- then Zone<uiMapArtID>_<tile>: a zone's merged picture
local FLAT_VERSION = 7 -- the art addon's first version with them
local GAPS_VERSION = 8 -- and with the continents' gaps masks (Masks\Gaps<uiMapArtID>)
local OVERLAY_TILE = 256 -- explored-area pieces are cut in 256-pixel files (MapExplorationPinMixin)
local MAP_CONTINENT, MAP_ZONE = 2, 3 -- Enum.UIMapType
local FILTER = "TRILINEAR" -- mipmapped: the art is drawn far smaller than its files at most zooms
local LABELS_LEVEL = 12 -- frame levels over the canvas: the place names, over every zone's art (3 to 8), under the
-- minimap pictures (Mini.lua, 20)

local world -- { mapID, box, ... } the world map's own picture
local continents = {} -- list of regions
local zones = {} -- list of regions, the largest first (cities on top)
local byMap = {} -- [mapID] = region
local boxes = {} -- [mapID] = canvas box (any map, read once)
local canvas, W, H, worldID
local queue, queueHead, queueTail = {}, 1, 0 -- textures waiting for their file, first to last
local cuts = {} -- zones being cut, first first: { region, routine }
local owners = {} -- [mapID at a point] = the zone it belongs to (caves and sub-zones belong to theirs), false: none
local budget = 0 -- samples left this frame
local loader
local revealAll = true -- Map.lua's "whole map" setting: every part of a masked zone drawn, explored or not

-- Maps on the canvas -----------------------------------------------------------------------------------------------

-- The canvas box of any map (its rectangle on the world map), or nil for one the world map doesn't place.
function ns.MapArt_Box(mapID)
	local known = boxes[mapID]
	if known ~= nil then
		return known or nil
	end
	local minX, maxX, minY, maxY = C_Map.GetMapRectOnMap(mapID, worldID)
	local box = false
	if minX and maxX and maxY and maxX > minX and maxY > minY then
		box = ns.Map_Box(minX, maxX, minY, maxY, W, H)
	end
	boxes[mapID] = box
	return box or nil
end

-- A spot x, y (0..1) on mapID in canvas units, or nil.
function ns.MapArt_ToCanvas(mapID, x, y)
	local box = mapID and ns.MapArt_Box(mapID)
	if box then
		return ns.Map_InBox(box, x, y)
	end
end

-- The smallest zone whose box holds canvas point cx, cy, or nil (a spot given on a continent's map gets its zone).
function ns.MapArt_ZoneAt(cx, cy)
	local best
	for _, z in ipairs(zones) do
		local b = z.box
		if cx >= b.l and cx <= b.l + b.w and cy >= b.t and cy <= b.t + b.h
			and (not best or b.w * b.h < best.box.w * best.box.h) then
			best = z
		end
	end
	return best
end

function ns.MapArt_Continents()
	return continents
end

function ns.MapArt_Zones()
	return zones
end

function ns.MapArt_WorldID()
	return worldID
end

-- Loading -------------------------------------------------------------------------------------------------------------

local Want

local function Load()
	budget = SAMPLES_PER_FRAME
	while cuts[1] and budget > 0 do
		local ok, err = coroutine.resume(cuts[1].routine)
		if not ok then
			table.remove(cuts, 1)
			error(err)
		elseif coroutine.status(cuts[1].routine) == "dead" then
			table.remove(cuts, 1)
		end
	end
	local n = 0
	while queueHead <= queueTail and n < LOAD_PER_FRAME do
		local tex = queue[queueHead]
		queue[queueHead] = nil
		queueHead = queueHead + 1
		tex.queued = nil
		if tex.file and not tex.loaded then
			tex:SetTexture(tex.file, nil, nil, FILTER)
			tex.loaded = true
			n = n + 1
		end
	end
	if queueHead > queueTail then
		queue, queueHead, queueTail = {}, 1, 0
		if not cuts[1] then
			loader:SetScript("OnUpdate", nil)
		end
	end
end

local LoadTimed = ns.Perf_Wrap(Load, "loader · OnUpdate")

local function Wake()
	if not loader:GetScript("OnUpdate") then
		loader:SetScript("OnUpdate", LoadTimed)
	end
end

Want = function(tex)
	if not tex.loaded and not tex.queued then
		tex.queued = true
		queueTail = queueTail + 1
		queue[queueTail] = tex
		Wake()
	end
end

-- Building ------------------------------------------------------------------------------------------------------------

local function Region(mapID, box, level)
	return { mapID = mapID, box = box, level = level, textures = {} }
end

local function AddTile(region, file, tile, layer, sublevel, ox, oy)
	local tex = region.frame:CreateTexture(nil, layer, nil, sublevel)
	tex:SetPoint("TOPLEFT", region.frame, "TOPLEFT", (ox or 0) + tile.x, -((oy or 0) + tile.y))
	tex:SetSize(tile.w, tile.h)
	tex:SetTexCoord(0, tile.u, 0, tile.v)
	tex.file = file
	region.textures[#region.textures + 1] = tex
	return tex
end

-- Whether art rect l, t, w, h touches one of the zone's place name boxes (Data/Forever/MapArtIndex.lua).
local function OnALabel(region, l, t, w, h)
	for _, b in ipairs(region.labelBoxes) do
		if l < b[3] and l + w > b[1] and t < b[4] and t + h > b[2] then
			return true
		end
	end
	return false
end

-- One explored-area piece at x, y on its zone's art, w x h, its files in order (256-pixel tiles); masked like the
-- zone's picture when it has a mask. The tiles that hold a place name are drawn again on the zone's names frame,
-- through the names mask (Tomte_MapArt, tools/mapart.py): above every zone's art, so neither a neighbour's picture nor
-- the territory's edge cuts a name. (All pieces above every zone cut names too: one zone's colour covered the next
-- one's names, measured 2026-11-15.)
local function AddPiece(region, x, y, w, h, fileAt)
	for _, tile in ipairs(ns.Map_Tiles(w, h, OVERLAY_TILE, OVERLAY_TILE, true)) do
		local file = fileAt(tile.index)
		if file then
			local tex = AddTile(region, file, tile, "ARTWORK", 0, x, y)
			if region.mask then
				tex:AddMaskTexture(region.mask)
			end
			region.overlays[#region.overlays + 1] = tex
			if region.labels and OnALabel(region, x + tile.x, y + tile.y, tile.w, tile.h) then
				local copy = AddTile(region, file, tile, "ARTWORK", 0, x, y)
				copy:SetParent(region.labels)
				copy:AddMaskTexture(region.labelMask)
				region.overlays[#region.overlays + 1] = copy
			end
		end
	end
end

-- The parts of a zone drawn over its base art: the ones you've explored, as the game's map does, or with "the whole
-- map" on (and a zone drawn through its mask) every one of them (Data/Forever/MapReveal.lua).
local function BuildOverlays(region)
	for _, tex in ipairs(region.overlays or {}) do
		tex:Hide()
		tex.file = nil
	end
	region.overlays = {}
	if region.flat then
		-- The merged picture already holds every piece: only its tiles under a place name are drawn again, on the
		-- names frame (as AddPiece does with the pieces).
		if region.labels then
			for i, tile in ipairs(region.tiles) do
				if OnALabel(region, tile.x, tile.y, tile.w, tile.h) then
					local copy = AddTile(region, region.base[i].file, tile, "ARTWORK", 0)
					copy:SetParent(region.labels)
					copy:AddMaskTexture(region.labelMask)
					region.overlays[#region.overlays + 1] = copy
				end
			end
		end
		return
	end
	local all = revealAll and region.mode == "mask" and ns.Content_Get(ns.CONTENT_FOREVER, "mapReveal")
	local pieces = all and region.artID and all[region.artID]
	if pieces then
		for _, p in ipairs(pieces) do
			AddPiece(region, p[1], p[2], p[3], p[4], function(i)
				return p[4 + i]
			end)
		end
		return
	end
	for _, info in ipairs(C_MapExplorationInfo.GetExploredMapTextures(region.mapID) or {}) do
		if not info.isShownByMouseOver and info.fileDataIDs then
			AddPiece(region, info.offsetX, info.offsetY, info.textureWidth, info.textureHeight, function(i)
				return info.fileDataIDs[i]
			end)
		end
	end
end

-- The zone a map belongs to: itself for a zone, the zone above a cave or sub-zone; false for anything else.
local function Owner(mapID)
	local known = owners[mapID]
	if known ~= nil then
		return known
	end
	local info, seen = C_Map.GetMapInfo(mapID), {}
	while info and info.mapType > MAP_ZONE and info.parentMapID and not seen[info.mapID] do
		seen[info.mapID] = true
		info = C_Map.GetMapInfo(info.parentMapID)
	end
	local owner = info and info.mapType == MAP_ZONE and info.mapID or false
	owners[mapID] = owner
	return owner
end

-- Cuts a zone to its own shape (runs from Load, a few hundred samples a frame), then draws it.
local function Cut(region, layer, files)
	local cont = region.continent
	local function Inside(col, row)
		if budget <= 0 then
			coroutine.yield()
		end
		budget = budget - 1
		-- The cell's middle: zone art pixels -> 0..1 on the zone -> canvas -> 0..1 on the continent.
		local zx = math.min(((col - 0.5) * CELL) / layer.layerWidth, 1)
		local zy = math.min(((row - 0.5) * CELL) / layer.layerHeight, 1)
		local cx, cy = ns.Map_InBox(region.box, zx, zy)
		local x, y = ns.Map_FromBox(cont.box, cx, cy)
		if not x then
			return false
		end
		local info = C_Map.GetMapInfoAtPosition(cont.mapID, x, y)
		if not info then
			return false
		end
		if info.mapID == region.mapID then
			return true
		end
		-- A city covers its whole rectangle there (OpenMap measured it): it's part of the zone it sits in.
		if C_Map.IsCityMap and C_Map.IsCityMap(info.mapID) then
			return true
		end
		return Owner(info.mapID) == region.mapID
	end
	local runs = ns.Map_Runs(layer.layerWidth, layer.layerHeight, CELL, Inside)
	for _, run in ipairs(runs) do
		for _, piece in ipairs(ns.Map_RunPieces(run, layer.layerWidth, layer.tileWidth, layer.tileHeight)) do
			local file = files[piece.index]
			if file then
				local tex = region.frame:CreateTexture(nil, "BACKGROUND")
				tex:SetPoint("TOPLEFT", region.frame, "TOPLEFT", piece.x, -piece.y)
				tex:SetSize(piece.w, piece.h)
				tex:SetTexCoord(piece.left, piece.right, piece.top, piece.bottom)
				tex.file = file
				region.textures[#region.textures + 1] = tex
			end
		end
	end
	BuildOverlays(region)
	region.cut = true
	if region.visible then
		for _, tex in ipairs(region.textures) do
			if tex.file then
				Want(tex)
			end
		end
	end
end

-- The mask Tomte_MapArt has for a zone's or a continent's art, or nil: only while that addon is loaded and is the
-- version Data/Forever/MapArtIndex.lua was made for (an older art addon's masks may not match).
local artOK -- nil: not asked yet
local function MaskFile(artID, level)
	if artOK == nil then
		local index = ns.Content_Get(ns.CONTENT_FOREVER, "mapArtIndex")
		artOK = index and C_AddOns.IsAddOnLoaded(ART_ADDON)
			and C_AddOns.GetAddOnMetadata(ART_ADDON, "Version") == tostring(index.version) and index or false
	end
	if not artOK then
		return nil
	elseif level == "zone" and artOK.masks[artID] then
		return MASKS .. "Zone" .. artID
	elseif level == "continent" and artOK.continents and artOK.continents[artID] then
		return MASKS .. "Continent" .. artID
	end
end

-- A continent's gaps mask (its picture where no zone's lies over it, tools/mapart.py), or nil before version 8.
local function GapsFile(artID)
	MaskFile(artID, "continent")
	if artOK and artOK.version >= GAPS_VERSION and artOK.continents and artOK.continents[artID] then
		return MASKS .. "Gaps" .. artID
	end
end

-- The file a zone's merged picture's tile index is in (its base art with every piece over it, tools/mapart.py), or nil
-- where the art addon has none (before version 7).
local function FlatFile(artID, index)
	MaskFile(artID, "zone")
	if artOK and artOK.version >= FLAT_VERSION and artOK.masks[artID] then
		return FLAT .. "Zone" .. artID .. "_" .. index
	end
end

-- A masked zone's base tiles: its merged picture while the whole map shows (one picture, so it fades evenly: Fade.lua),
-- else the game's base art with the explored pieces over it (BuildOverlays). Set again when that setting changes.
local function SetBaseFiles(region)
	region.flat = false
	for _, tex in ipairs(region.base or {}) do
		local flat = revealAll and FlatFile(region.artID, tex.tileIndex)
		region.flat = region.flat or flat ~= nil
		local file = flat or region.gameFiles[tex.tileIndex]
		if tex.file ~= file then
			tex.file, tex.loaded = file, nil
			if region.visible then
				Want(tex)
			end
		end
	end
end

-- A zone's place name boxes and their mask file, or nil (the art addon's index, as MaskFile).
local function LabelFiles(artID)
	MaskFile(artID, "zone")
	local boxes = artOK and artOK.labels and artOK.labels[artID]
	if boxes then
		return boxes, MASKS .. "Labels" .. artID
	end
end

-- For /tomte map why: whether the art addon is loaded, its version and the version Tomte knows.
function ns.MapArt_AddonState()
	local index = ns.Content_Get(ns.CONTENT_FOREVER, "mapArtIndex")
	return C_AddOns.IsAddOnLoaded(ART_ADDON), C_AddOns.GetAddOnMetadata(ART_ADDON, "Version"), index and index.version
end

-- The region's frame and textures, on first sight (a zone's after it's cut).
local function Build(region, frameLevel)
	local layers = C_Map.GetMapArtLayers(region.mapID)
	local layer = layers and layers[1]
	if not (layer and layer.layerWidth and layer.layerWidth > 0) then
		region.broken = true
		return
	end
	local frame = CreateFrame("Frame", nil, canvas)
	frame:EnableMouse(false)
	frame:SetSize(layer.layerWidth, layer.layerHeight)
	-- One scale for both sides: the world map keeps each map's proportions.
	local scale = region.box.w / layer.layerWidth
	frame:SetScale(scale)
	frame:SetPoint("TOPLEFT", canvas, "TOPLEFT", region.box.l / scale, -region.box.t / scale)
	frame:SetFrameLevel(frameLevel)
	region.frame = frame
	local files = C_Map.GetMapArtLayerTextures(region.mapID, 1) or {}
	local artID = region.level ~= "world" and C_Map.GetMapArtID and C_Map.GetMapArtID(region.mapID) or nil
	local maskFile = artID and MaskFile(artID, region.level)
	region.artID = artID
	if maskFile then
		-- The whole picture through its soft mask (Tomte_MapArt): a zone's detail without frame or neighbours, fading
		-- out at its border; a continent's land and shores without its frame, the world picture showing past them.
		local mask = frame:CreateMaskTexture()
		mask:SetTexture(maskFile, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
		mask:SetAllPoints(frame)
		region.base, region.gameFiles, region.tiles = {}, files, {}
		for _, tile in ipairs(ns.Map_Tiles(layer.layerWidth, layer.layerHeight, layer.tileWidth, layer.tileHeight)) do
			if files[tile.index] then
				local tex = AddTile(region, files[tile.index], tile, "BACKGROUND", 0)
				tex:AddMaskTexture(mask)
				tex.tileIndex = tile.index
				region.base[#region.base + 1] = tex
				region.tiles[#region.tiles + 1] = tile
			end
		end
		region.cut, region.mode, region.mask = true, "mask", mask
		local gapsFile = region.level == "continent" and GapsFile(artID)
		if gapsFile then
			-- The same picture again through its gaps mask (where no zone's picture lies over it): shown while the map
			-- fades and the rest of the continent fades out under the zones (ApplyAlphas), so a capital's land and the
			-- sea stay one picture instead of a hole (seen 2026-11-19).
			local gapsMask = frame:CreateMaskTexture()
			gapsMask:SetTexture(gapsFile, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
			gapsMask:SetAllPoints(frame)
			region.gaps = {}
			for _, tile in ipairs(region.tiles) do
				local tex = AddTile(region, files[tile.index], tile, "ARTWORK", 0)
				tex:AddMaskTexture(gapsMask)
				tex:SetAlpha(0)
				region.gaps[#region.gaps + 1] = tex
			end
		end
		if region.level == "zone" then
			SetBaseFiles(region)
			-- Its place names, drawn again above every zone (AddPiece). A child, so it fades and hides with the zone.
			local boxes, labelFile = LabelFiles(artID)
			if boxes then
				local labels = CreateFrame("Frame", nil, frame)
				labels:SetAllPoints(frame)
				labels:EnableMouse(false)
				labels:SetFrameLevel(canvas:GetFrameLevel() + LABELS_LEVEL)
				local labelMask = labels:CreateMaskTexture()
				labelMask:SetTexture(labelFile, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
				labelMask:SetAllPoints(frame)
				region.labels, region.labelMask, region.labelBoxes = labels, labelMask, boxes
			end
			-- The picture alone lacks most of a zone's detail: the game draws it in the explored-area pieces.
			BuildOverlays(region)
		end
		return
	end
	local reveal = region.level == "zone" and artID and ns.Content_Get(ns.CONTENT_FOREVER, "mapReveal")
	local pieces = reveal and reveal[artID]
	if pieces then
		-- Drawn from its explored-area pieces only, all of them (Data/Forever/MapReveal.lua): they cover the zone's own
		-- land, so no frame or neighbours show (its base picture had both).
		region.overlays = {}
		for _, p in ipairs(pieces) do
			for _, tile in ipairs(ns.Map_Tiles(p[3], p[4], OVERLAY_TILE, OVERLAY_TILE, true)) do
				local file = p[4 + tile.index]
				if file then
					region.overlays[#region.overlays + 1] = AddTile(region, file, tile, "ARTWORK", 0, p[1], p[2])
				end
			end
		end
		region.cut, region.mode = true, "pieces"
		return
	end
	if region.level == "zone" then
		region.mode = "cut"
		cuts[#cuts + 1] = { region = region, routine = coroutine.create(function()
			Cut(region, layer, files)
		end) }
		Wake()
		return
	end
	for _, tile in ipairs(ns.Map_Tiles(layer.layerWidth, layer.layerHeight, layer.tileWidth, layer.tileHeight)) do
		if files[tile.index] then
			AddTile(region, files[tile.index], tile, "BACKGROUND", 0)
		end
	end
end

-- A capital the game doesn't flag as a city (none of the old capitals are on this client): its art has no
-- explored-area pieces (an empty list in Data/Forever/MapReveal.lua). Drawn as a zone it covered its neighbour with its
-- whole rectangle (Thunder Bluff over Mulgore).
local function IsCapital(mapID)
	local reveal = ns.Content_Get(ns.CONTENT_FOREVER, "mapReveal")
	local artID = reveal and C_Map.GetMapArtID and C_Map.GetMapArtID(mapID)
	local pieces = artID and reveal[artID]
	return pieces ~= nil and #pieces == 0
end

-- The world map's layout: its picture, the continents on it and their zones. Once per session (the maps don't move).
function ns.MapArt_Init(canvasFrame, width, height, worldMapID)
	canvas, W, H, worldID = canvasFrame, width, height, worldMapID
	loader = CreateFrame("Frame", nil, canvas)
	world = Region(worldID, { l = 0, t = 0, w = W, h = H }, "world")
	for _, info in ipairs(C_Map.GetMapChildrenInfo(worldID, MAP_CONTINENT) or {}) do
		local box = ns.MapArt_Box(info.mapID)
		if box then
			local region = Region(info.mapID, box, "continent")
			region.name = info.name
			continents[#continents + 1] = region
			byMap[info.mapID] = region
			for _, child in ipairs(C_Map.GetMapChildrenInfo(info.mapID, MAP_ZONE) or {}) do
				-- Cities are left out: their zone's art draws them, and their own rectangle would cover its neighbours.
				local city = C_Map.IsCityMap and C_Map.IsCityMap(child.mapID) or IsCapital(child.mapID)
				local zoneBox = not city and not byMap[child.mapID] and ns.MapArt_Box(child.mapID)
				if zoneBox then
					local zone = Region(child.mapID, zoneBox, "zone")
					zone.name, zone.continent = child.name, region
					zones[#zones + 1] = zone
					byMap[child.mapID] = zone
				end
			end
		end
	end
	table.sort(zones, function(a, b)
		return a.box.w * a.box.h > b.box.w * b.box.h
	end)
	local base = canvas:GetFrameLevel()
	world.order = base + 1
	for _, c in ipairs(continents) do
		c.order = base + 2
	end
	for i, z in ipairs(zones) do
		z.order = base + 3 + math.floor(i / 8) -- smaller zones (cities) above the big ones
	end
end

-- Showing ---------------------------------------------------------------------------------------------------------------

local function Show(region, on)
	if on then
		if not region.frame and not region.broken then
			Build(region, region.order)
		end
		if region.frame then
			region.frame:Show()
			-- Asked for once per showing (the view moves every frame while dragged); a zone still being cut asks when done.
			if not region.visible then
				for _, tex in ipairs(region.textures) do
					if tex.file then
						Want(tex)
					end
				end
				if region.level == "zone" and not region.cut then
					Wake()
				end
			end
		end
	elseif region.frame then
		region.frame:Hide()
	end
	region.visible = on and region.frame ~= nil
end

-- After the view moved: the continents and zones that overlap viewBox show at the alpha this zoom gives their level
-- (Data.lua, Map_LevelAlphas), so each level fades in over the one under it; the rest hides. Continents stay under the
-- zones as a backdrop.
-- While the window fades (Fade.lua) the levels under the one on top fade out with it: a window's alpha reaches each
-- level on its own, so at half alpha every level showed through the one above, muddy and hardly see-through (seen
-- 2026-11-19). cover: how far the window has faded (0..1); fading: it isn't solid (0 or 1); lastContinent, lastZone:
-- the zoom's level alphas, kept for SetCover.
local cover, fading = 0, 0
local lastContinent, lastZone = 0, 0
local allFlat = false -- every zone in view is drawn from its merged picture (SetBaseFiles)

-- What goes:
-- - everything under the ground pictures, which fill the view edge to edge (Mini.lua shows all its tiles or none), at
--   once as the fade starts: the ground is still solid then, so nothing shows, where fading it along let the yellow
--   paper map show through the ground for a moment (seen 2026-11-19);
-- - along with the fade, the world picture under the continents (its sea), the continents under the zones when every
--   zone in view is one merged picture (its territory reaches its neighbours'; the game's base art and pieces leave
--   gaps, so then the continent stays), and the place names drawn again over the zones (two layers there).
local applied = {} -- the inputs last applied: nothing is set again while they're the same
local stacked = 1 -- the levels' alphas added up (MapArt_Layers)

local function ApplyAlphas()
	local ground = ns.MapMini_Showing()
	if applied.cover == cover and applied.fading == fading and applied.ground == ground and applied.c == lastContinent
		and applied.z == lastZone then
		return
	end
	applied.cover, applied.fading, applied.ground, applied.c, applied.z = cover, fading, ground, lastContinent, lastZone
	local underGround = 1 - fading * ground
	local worldAlpha = (1 - cover * math.max(lastContinent, lastZone)) * underGround
	local continentAlpha = lastContinent * underGround
	-- How far the continent hands over to its gaps copy: the whole picture fades out under the zones, the copy that
	-- only covers what no zone does fades in (Build). Without a gaps copy (an older art addon) nothing stays there.
	local handOver = allFlat and cover * lastZone or 0
	local zoneAlpha = lastZone * underGround
	if world and world.frame then
		world.frame:SetAlpha(worldAlpha)
	end
	for _, r in ipairs(continents) do
		if r.frame then
			r.frame:SetAlpha(continentAlpha)
			for _, tex in ipairs(r.base or {}) do
				tex:SetAlpha(1 - handOver)
			end
			for _, tex in ipairs(r.gaps or {}) do
				tex:SetAlpha(handOver)
			end
		end
	end
	for _, r in ipairs(zones) do
		if r.frame then
			r.frame:SetAlpha(zoneAlpha)
			if r.labels then
				r.labels:SetAlpha(1 - cover)
			end
		end
	end
	-- The gaps copy lies beside the zones, not under them: one picture deep.
	stacked = math.max(1, (world and world.frame and worldAlpha or 0) + continentAlpha * (1 - handOver) + zoneAlpha
		+ ground)
end

function ns.MapArt_Update(viewBox, continentAlpha, zoneAlpha)
	-- The world picture stays under the continents: with their masks they fade out past their shores.
	Show(world, true)
	for _, r in ipairs(continents) do
		Show(r, continentAlpha > 0 and ns.Map_Overlaps(r.box, viewBox))
	end
	local flat, any = true, false
	for _, r in ipairs(zones) do
		Show(r, zoneAlpha > 0 and ns.Map_Overlaps(r.box, viewBox))
		if r.visible then
			any = true
			flat = flat and r.flat == true
		end
	end
	allFlat = any and flat
	lastContinent, lastZone = continentAlpha, zoneAlpha
	applied.cover = nil -- a frame may have been built just now: all are set again
	ApplyAlphas()
end

-- How many pictures lie on top of each other on the land now, as their alphas added up (so it moves smoothly as a level
-- fades in or out): the world, the continents, the zones and the ground pictures (Mini.lua). Fade.lua fades the view
-- more when there are more of them.
function ns.MapArt_Layers()
	ApplyAlphas() -- the ground pictures may have changed since (Mini.lua is laid out after this file)
	return stacked
end

-- Fade.lua's "why": every zone in view is drawn from its merged picture.
function ns.MapArt_AllFlat()
	return allFlat
end

-- Fade.lua's "why": a zone frame showing now, else a continent's, else the world's.
function ns.MapArt_TopFrame()
	for _, list in ipairs({ zones, continents }) do
		for _, r in ipairs(list) do
			if r.visible and r.frame then
				return r.frame
			end
		end
	end
	return world and world.frame
end

-- Fade.lua, each frame while it fades: amount, how far (0..1); started, whether it's left solid at all.
function ns.MapArt_SetCover(amount, started)
	cover, fading = amount, started and 1 or 0
	ApplyAlphas()
end

local function Rebuild(region)
	if region.base then
		SetBaseFiles(region)
	end
	BuildOverlays(region)
	if region.visible then
		for _, tex in ipairs(region.overlays) do
			Want(tex)
		end
	end
end

-- Map.lua's "whole map" setting: every part of each zone, or only those you've explored.
function ns.MapArt_RevealAll(on)
	if revealAll == on then
		return
	end
	revealAll = on
	for _, z in ipairs(zones) do
		if z.frame and z.mode == "mask" then
			Rebuild(z)
		end
	end
end

-- The game revealed more of a zone: its overlays are cut again (the shown ones now, the rest on first sight). Zones
-- drawn from all their pieces show them all already.
function ns.MapArt_Explored()
	for _, z in ipairs(zones) do
		if z.frame and z.cut and z.mode ~= "pieces" and not (z.mode == "mask" and revealAll) then
			Rebuild(z)
		end
	end
end
