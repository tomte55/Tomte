local addonName, ns = ...

-- Tomte map: the art. The world map's own picture, both continents and every zone, each a frame on the canvas in its
-- own art pixels, scaled to where the world map puts that map (C_Map.GetMapRectOnMap). A zone's picture also shows its
-- neighbours and a parchment border, so each zone is cut to its own shape: its art is sampled on a grid, the game
-- says which zone owns each point (C_Map.GetMapInfoAtPosition on the continent) and only the zone's own cells are
-- drawn, as horizontal runs. Zones also get the parts of them you've explored (C_MapExplorationInfo), as the game's
-- map does. Built on first sight, a few hundred samples and textures a frame (setting hundreds of files at once
-- hitches; OpenMap measured about 35 ms for 300), hidden while out of view. The loader is a child of the canvas, so it pauses while the window is closed and
-- goes on when it opens. Geometry in Data.lua; the view in Window.lua.

local LOAD_PER_FRAME = 48 -- texture files set per frame while art loads
local CELL = 12 -- art pixels: the grid a zone is cut on (about 1.2% of a zone's width; finer is smoother and slower)
local SAMPLES_PER_FRAME = 500 -- GetMapInfoAtPosition calls per frame while zones are cut
local OVERLAY_TILE = 256 -- explored-area pieces are cut in 256-pixel files (MapExplorationPinMixin)
local MAP_CONTINENT, MAP_ZONE = 2, 3 -- Enum.UIMapType
local FILTER = "TRILINEAR" -- mipmapped: the art is drawn far smaller than its files at most zooms

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

local function Wake()
	if not loader:GetScript("OnUpdate") then
		loader:SetScript("OnUpdate", Load)
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

-- The explored parts of a zone, drawn over its base art.
local function BuildOverlays(region)
	for _, tex in ipairs(region.overlays or {}) do
		tex:Hide()
		tex.file = nil
	end
	region.overlays = {}
	for _, info in ipairs(C_MapExplorationInfo.GetExploredMapTextures(region.mapID) or {}) do
		if not info.isShownByMouseOver and info.fileDataIDs then
			for _, tile in ipairs(ns.Map_Tiles(info.textureWidth, info.textureHeight, OVERLAY_TILE, OVERLAY_TILE, true)) do
				local file = info.fileDataIDs[tile.index]
				if file then
					local tex = AddTile(region, file, tile, "ARTWORK", 0, info.offsetX, info.offsetY)
					region.overlays[#region.overlays + 1] = tex
				end
			end
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
	if region.level == "zone" then
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
				local city = C_Map.IsCityMap and C_Map.IsCityMap(child.mapID)
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

-- After the view moved: the art of level ("world", "continent" or "zone") that overlaps viewBox shows; the rest hides.
-- Continents stay under the zones as a backdrop.
function ns.MapArt_Update(viewBox, level)
	Show(world, level == "world")
	for _, c in ipairs(continents) do
		Show(c, level ~= "world" and ns.Map_Overlaps(c.box, viewBox))
	end
	for _, z in ipairs(zones) do
		Show(z, level == "zone" and ns.Map_Overlaps(z.box, viewBox))
	end
end

-- The game revealed more of a zone: its overlays are cut again (the shown ones now, the rest on first sight).
function ns.MapArt_Explored()
	for _, z in ipairs(zones) do
		if z.frame and z.cut then
			BuildOverlays(z)
			if z.visible then
				for _, tex in ipairs(z.overlays) do
					Want(tex)
				end
			end
		end
	end
end
