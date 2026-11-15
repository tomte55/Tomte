local addonName, ns = ...

-- Tomte map: pure logic (no WoW API calls; unit-tested in tests/test_map.lua). The canvas is the world map's art
-- (W x H canvas units, map 947's art pixels); a view shows it around a centre (u, v: 0..1 across the canvas) at a zoom
-- (1: the whole canvas fits the view). Placing maps on the canvas, zooming about a point, what the view sees, and
-- how art is cut into tiles. Drawn by Art.lua and Pins.lua, the window in Window.lua, registered in Map.lua.

-- A map's rectangle on the world map (C_Map.GetMapRectOnMap: minX, maxX, minY, maxY, 0..1) as a canvas box.
function ns.Map_Box(minX, maxX, minY, maxY, W, H)
	return { l = minX * W, t = minY * H, w = (maxX - minX) * W, h = (maxY - minY) * H }
end

-- A spot x, y (0..1) on a map with that box, in canvas units.
function ns.Map_InBox(box, x, y)
	return box.l + x * box.w, box.t + y * box.h
end

-- The spot (0..1 on the map) of canvas point cx, cy in box, or nil outside it.
function ns.Map_FromBox(box, cx, cy)
	if box.w <= 0 or box.h <= 0 then
		return nil
	end
	local x, y = (cx - box.l) / box.w, (cy - box.t) / box.h
	if x < 0 or x > 1 or y < 0 or y > 1 then
		return nil
	end
	return x, y
end

-- How many view pixels a canvas unit takes at zoom 1: the canvas just fits.
function ns.Map_Fit(viewW, viewH, W, H)
	return math.min(viewW / W, viewH / H)
end

-- The view keeps u, v on the canvas and the zoom within its range.
function ns.Map_Clamp(view, minZoom, maxZoom)
	view.zoom = math.min(math.max(view.zoom, minZoom), maxZoom)
	view.u = math.min(math.max(view.u, 0), 1)
	view.v = math.min(math.max(view.v, 0), 1)
	return view
end

-- Canvas point under view offset sx, sy (pixels from the view's centre, x right, y down).
function ns.Map_At(view, sx, sy, fit, W, H)
	local s = fit * view.zoom
	return view.u * W + sx / s, view.v * H + sy / s
end

-- View offset (pixels from the centre, x right, y down) of canvas point cx, cy.
function ns.Map_ToView(view, cx, cy, fit, W, H)
	local s = fit * view.zoom
	return (cx - view.u * W) * s, (cy - view.v * H) * s
end

-- Zooms to newZoom keeping the canvas point under view offset sx, sy where it is (zoom toward the cursor).
function ns.Map_ZoomAbout(view, sx, sy, newZoom, fit, W, H)
	local cx, cy = ns.Map_At(view, sx, sy, fit, W, H)
	view.zoom = newZoom
	local s = fit * newZoom
	view.u = (cx - sx / s) / W
	view.v = (cy - sy / s) / H
	return view
end

-- Moves the view by dx, dy view pixels (a drag: the canvas follows the mouse).
function ns.Map_Pan(view, dx, dy, fit, W, H)
	local s = fit * view.zoom
	view.u = view.u - dx / s / W
	view.v = view.v - dy / s / H
	return view
end

-- The canvas box the view shows, grown by margin (0.35: 35% each way) so art is ready before it scrolls in.
function ns.Map_ViewBox(view, viewW, viewH, fit, W, H, margin)
	local s = fit * view.zoom
	local hw, hh = viewW / 2 / s * (1 + (margin or 0)), viewH / 2 / s * (1 + (margin or 0))
	local cx, cy = view.u * W, view.v * H
	return { l = cx - hw, t = cy - hh, w = hw * 2, h = hh * 2 }
end

function ns.Map_Overlaps(a, b)
	return a.l < b.l + b.w and b.l < a.l + a.w and a.t < b.t + b.h and b.t < a.t + a.h
end

-- The zoom at which box fills about `share` of the view's smaller side.
function ns.Map_ZoomFor(box, viewW, viewH, fit, share)
	local s = math.min(viewW / box.w, viewH / box.h) * (share or 1)
	return s / fit
end

-- Tiles for art totalW x totalH cut tileW x tileH, row by row (the order of the game's file lists): each
-- { index, x, y, w, h, u, v } with x, y its top left, w, h the part used and u, v the texture coordinates of that part.
-- fileW, fileH: a tile file's size (the same as the tile for map art); powerOfTwo: the last row and column are their
-- own smaller files, the next power of two from 16 up (explored-area overlays, as the game's MapExplorationPinMixin).
function ns.Map_Tiles(totalW, totalH, tileW, tileH, powerOfTwo)
	local list = {}
	local cols, rows = math.ceil(totalW / tileW), math.ceil(totalH / tileH)
	local function Side(total, tile, i, n)
		if i < n then
			return tile, tile
		end
		local used = total - (n - 1) * tile
		if used <= 0 then
			used = tile
		end
		if not powerOfTwo then
			return used, tile
		end
		local file = 16
		while file < used do
			file = file * 2
		end
		return used, file
	end
	for row = 1, rows do
		local h, fileH = Side(totalH, tileH, row, rows)
		for col = 1, cols do
			local w, fileW = Side(totalW, tileW, col, cols)
			list[#list + 1] = {
				index = (row - 1) * cols + col, x = (col - 1) * tileW, y = (row - 1) * tileH, w = w, h = h,
				u = w / fileW, v = h / fileH,
			}
		end
	end
	return list
end

-- A zone cut to its own shape: inside(col, row) says whether the cell at that column and row (cells of `cell` pixels
-- over art totalW x totalH) is the zone's. Returns the runs of cells that are, row by row: { x0, x1, y0, y1 } in art
-- pixels, neighbouring cells of a row joined into one run.
function ns.Map_Runs(totalW, totalH, cell, inside)
	local runs = {}
	local cols, rows = math.ceil(totalW / cell), math.ceil(totalH / cell)
	for row = 1, rows do
		local y0, y1 = (row - 1) * cell, math.min(row * cell, totalH)
		local start
		for col = 1, cols + 1 do
			local yes = col <= cols and inside(col, row)
			if yes and not start then
				start = col
			elseif not yes and start then
				runs[#runs + 1] = { x0 = (start - 1) * cell, x1 = math.min((col - 1) * cell, totalW), y0 = y0, y1 = y1 }
				start = nil
			end
		end
	end
	return runs
end

-- The pieces of map art (tiles tileW x tileH, row by row, totalW wide) that a run covers: each
-- { index, x, y, w, h, left, right, top, bottom } with x, y, w, h in art pixels and the texture coordinates of the piece.
function ns.Map_RunPieces(run, totalW, tileW, tileH)
	local pieces = {}
	local cols = math.ceil(totalW / tileW)
	local row = math.floor(run.y0 / tileH) + 1
	local lastRow = math.floor((run.y1 - 0.001) / tileH) + 1
	for r = row, lastRow do
		local ty = (r - 1) * tileH
		local y0, y1 = math.max(run.y0, ty), math.min(run.y1, ty + tileH)
		local first, last = math.floor(run.x0 / tileW) + 1, math.floor((run.x1 - 0.001) / tileW) + 1
		for c = first, math.min(last, cols) do
			local tx = (c - 1) * tileW
			local x0, x1 = math.max(run.x0, tx), math.min(run.x1, tx + tileW)
			if x1 > x0 and y1 > y0 then
				pieces[#pieces + 1] = {
					index = (r - 1) * cols + c, x = x0, y = y0, w = x1 - x0, h = y1 - y0,
					left = (x0 - tx) / tileW, right = (x1 - tx) / tileW, top = (y0 - ty) / tileH, bottom = (y1 - ty) / tileH,
				}
			end
		end
	end
	return pieces
end

-- Which art shows at a zoom: "world" (the world map's own picture), "continent", "zone" (continents with zones over
-- them). continentZoom, zoneZoom: where each starts.
function ns.Map_Level(zoom, continentZoom, zoneZoom)
	if zoom >= zoneZoom then
		return "zone"
	elseif zoom >= continentZoom then
		return "continent"
	end
	return "world"
end
