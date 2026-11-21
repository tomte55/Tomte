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
-- With the view's size (vw, vh pixels, fit, canvas W x H) the canvas also keeps covering the view: no empty edge
-- shows while it's larger than the view, and it sits in the middle while it's smaller.
function ns.Map_Clamp(view, minZoom, maxZoom, vw, vh, fit, W, H)
	view.zoom = math.min(math.max(view.zoom, minZoom), maxZoom)
	local function Side(c, viewPx, total)
		if not viewPx then
			return math.min(math.max(c, 0), 1)
		end
		local half = viewPx / 2 / (fit * view.zoom) / total -- half the view, as a share of the canvas
		if half >= 0.5 then
			return 0.5
		end
		return math.min(math.max(c, half), 1 - half)
	end
	view.u = Side(view.u, vw, W)
	view.v = Side(view.v, vh, H)
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

-- The canvas box the view shows, grown by margin (0.35: 35% each way) so art is ready before it scrolls in. out: a
-- table to fill (the view moves every frame while dragged), or nil for a new one.
function ns.Map_ViewBox(view, viewW, viewH, fit, W, H, margin, out)
	local s = fit * view.zoom
	local hw, hh = viewW / 2 / s * (1 + (margin or 0)), viewH / 2 / s * (1 + (margin or 0))
	local cx, cy = view.u * W, view.v * H
	out = out or {}
	out.l, out.t, out.w, out.h = cx - hw, cy - hh, hw * 2, hh * 2
	return out
end

-- The canvas box around points ({ cx, cy } each), grown by pad (a share of its size) each way and at least one unit,
-- so a single point still gets one: what the flight map frames. nil for no points.
function ns.Map_BoxAround(points, pad)
	local l, t, r, b
	for _, p in ipairs(points) do
		l, t = math.min(l or p.cx, p.cx), math.min(t or p.cy, p.cy)
		r, b = math.max(r or p.cx, p.cx), math.max(b or p.cy, p.cy)
	end
	if not l then
		return nil
	end
	local gw, gh = math.max((r - l) * pad, 1), math.max((b - t) * pad, 1)
	return { l = l - gw, t = t - gh, w = r - l + 2 * gw, h = b - t + 2 * gh }
end

-- What the flight map frames (nodes: { cx, cy, key, name }, key "current", "reachable" or "distant"): where you are
-- and where you're flying next: the flight master your route flies to (flyTo, its name), else the one nearest you.
-- Every flight path you know at once framed both ends of a continent, the whole world in view (seen 2026-11-21); the
-- rest are a wheel turn out. Away from a flight master you know (no current one): every one you can fly to.
function ns.Map_FlightFrame(nodes, flyTo)
	local here
	local reachable = {}
	for _, n in ipairs(nodes) do
		if n.key == "current" then
			here = n
		elseif n.key == "reachable" then
			reachable[#reachable + 1] = n
		end
	end
	if not here then
		return #reachable > 0 and reachable or nodes
	end
	local next
	for _, n in ipairs(reachable) do
		if flyTo and n.name == flyTo then
			next = n
		end
	end
	if not next then
		next = reachable[ns.Map_Nearest(reachable, here.cx, here.cy) or 0]
	end
	return { here, next }
end

-- The index of the point ({ cx, cy } each) nearest x, y, or nil for none.
function ns.Map_Nearest(points, x, y)
	local best, bestD
	for i, p in ipairs(points) do
		local d = (p.cx - x) ^ 2 + (p.cy - y) ^ 2
		if not bestD or d < bestD then
			best, bestD = i, d
		end
	end
	return best
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

-- Minimap tiles -------------------------------------------------------------------------------------------------------

local MINI_TILE = 1600 / 3 -- yards across one terrain (and minimap) tile
local MINI_GRID = 64

-- From world yards to a spot on a map, given the world points of the map's corners 0,0, 1,0 and 0,1 (each { x, y },
-- as C_Map.GetWorldPosFromMapPos gives them). Returns a function (wx, wy) -> x, y (0..1 on the map), or nil when the
-- corners don't span the map.
function ns.Map_FromWorld(w00, w10, w01)
	local ax, ay = w10.x - w00.x, w10.y - w00.y -- world change across the map's x
	local bx, by = w01.x - w00.x, w01.y - w00.y -- and its y
	local det = ax * by - ay * bx
	if math.abs(det) < 1e-9 then
		return nil
	end
	return function(wx, wy)
		local dx, dy = wx - w00.x, wy - w00.y
		return (dx * by - dy * bx) / det, (ax * dy - ay * dx) / det
	end
end

-- A minimap tile's corners in world yards: key = x * 64 + y (x running east, y south). Returns the north-west corner
-- and the south-east one: wx1, wy1, wx2, wy2 (world x grows north, y west; tile 32, 32 starts at 0, 0).
function ns.Map_MiniTileWorld(key)
	local x, y = math.floor(key / MINI_GRID), key % MINI_GRID
	local north, west = (32 - y) * MINI_TILE, (32 - x) * MINI_TILE
	return north, west, north - MINI_TILE, west - MINI_TILE
end

-- 0..1 between from and to, eased (the minimap tiles fade in as you zoom).
function ns.Map_Fade(v, from, to)
	local t = math.min(math.max((v - from) / (to - from), 0), 1)
	return t * t * (3 - 2 * t)
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

-- How much of the continents' and the zones' art shows at a zoom (0..1 each): each fades in across its start, from
-- start / band to start * band (in log space, as the zoom eases), so one level melts into the next instead of popping in.
function ns.Map_LevelAlphas(zoom, continentZoom, zoneZoom, band)
	local z, b = math.log(zoom), math.log(band)
	local c, s = math.log(continentZoom), math.log(zoneZoom)
	return ns.Map_Fade(z, c - b, c + b), ns.Map_Fade(z, s - b, s + b)
end

-- How much larger pins are drawn at a zoom: as they are up to zone zoom, growing to most times from 8x to 32x (close
-- up the art is many times larger and pins their size looked lost on it).
function ns.Map_PinGrow(zoom, most)
	return 1 + (most - 1) * ns.Map_Fade(math.log(zoom), math.log(8), math.log(32))
end

-- A flight from view `from` to `to` ({ u, v, zoom } each): one move { u, v, zoom, time, rise }. rise: how far (log
-- zoom) it zooms out above the straight way from one zoom to the other at its middle, just enough to see both places
-- (0 when they're close or the target is already in view). vw, vh: the view in pixels; fit: the canvas's base scale;
-- W, H: the canvas; minZoom: the least zoom.
local FLIGHT_ROOM = 1.4 -- both places fit with this much room
function ns.Map_Flight(from, to, vw, vh, fit, W, H, minZoom)
	local dx, dy = math.abs(to.u - from.u) * W, math.abs(to.v - from.v) * H
	local both = math.min(vw / (dx * FLIGHT_ROOM + 1), vh / (dy * FLIGHT_ROOM + 1)) / fit
	local out = math.max(minZoom, both) -- the zoom that shows both places
	local middle = (math.log(from.zoom) + math.log(to.zoom)) / 2
	local rise = math.max(0, middle - math.log(out))
	local zoomPart = math.abs(math.log(to.zoom / from.zoom)) * 0.12 + rise * 0.22
	local pan = math.sqrt(dx * dx + dy * dy) * fit * out / vw
	local time = math.min(math.max(0.45 + zoomPart * 1.3 + 0.4 * math.min(pan, 1.5), 0.45), 2)
	return { u = to.u, v = to.v, zoom = to.zoom, time = time, rise = rise }
end

-- Where a flight is at p (0..1): pan eased in and out more gently than the zoom, so it moves mostly while zoomed out;
-- zoom along the straight way in log space, lifted by rise in the middle. Returns u, v, zoom.
function ns.Map_FlightAt(from, flight, p)
	local e = p * p * (3 - 2 * p)
	local panE = e * e * (3 - 2 * e)
	local u = from.u + (flight.u - from.u) * panE
	local v = from.v + (flight.v - from.v) * panE
	local logZoom = math.log(from.zoom) + (math.log(flight.zoom) - math.log(from.zoom)) * e - flight.rise * 4 * e * (1 - e)
	return u, v, math.exp(logZoom)
end

-- Pins that overlap on the view gather into groups (pins closer than gap, and pins close to those), and each group
-- spreads round its middle in a ring, in a fixed order (key), so each can be seen and clicked, as the game's map
-- spreads its quest pins. spots: { x, y, key } in view pixels; sets each spot's tx, ty (where to draw it).
-- Runs every frame the view moves, so it makes no tables: the groups are runs of one sorted list of indexes, kept
-- between calls (one table per group per frame made about 2 KB a frame, measured 2026-11-18).
local clusterParent, clusterOrder, clusterSpots = {}, {}, nil

local function ClusterRoot(i)
	local parent = clusterParent
	while parent[i] ~= i do
		parent[i] = parent[parent[i]]
		i = parent[i]
	end
	return i
end

-- By group (its root, once every index points straight at it), then by key inside a group.
local function ByGroupThenKey(a, b)
	local ra, rb = clusterParent[a], clusterParent[b]
	if ra ~= rb then
		return ra < rb
	end
	return clusterSpots[a].key < clusterSpots[b].key
end

function ns.Map_Clusters(spots, gap)
	local n = #spots
	local parent, order = clusterParent, clusterOrder
	for i = 1, n do
		parent[i] = i
	end
	for i = 1, n - 1 do
		for j = i + 1, n do
			local a, b = spots[i], spots[j]
			if (a.x - b.x) ^ 2 + (a.y - b.y) ^ 2 < gap * gap then
				parent[ClusterRoot(j)] = ClusterRoot(i)
			end
		end
	end
	for i = 1, n do
		parent[i] = ClusterRoot(i)
		order[i] = i
	end
	for i = n + 1, #order do
		order[i] = nil
	end
	clusterSpots = spots
	table.sort(order, ByGroupThenKey)
	clusterSpots = nil
	local first = 1
	while first <= n do
		local root, last = parent[order[first]], first
		while last < n and parent[order[last + 1]] == root do
			last = last + 1
		end
		local count = last - first + 1
		if count == 1 then
			local sp = spots[order[first]]
			sp.tx, sp.ty = sp.x, sp.y
		else
			local cx, cy = 0, 0
			for k = first, last do
				local sp = spots[order[k]]
				cx, cy = cx + sp.x, cy + sp.y
			end
			cx, cy = cx / count, cy / count
			for k = first, last do
				local sp = spots[order[k]]
				local ox, oy = ns.Map_FanOffset(k - first + 1, count, gap)
				sp.tx, sp.ty = cx + ox, cy + oy
			end
		end
		first = last + 1
	end
	return spots
end

-- Where pin i of n in a group sits from their spot, in pixels (x right, y down): round a ring wide enough that
-- neighbours are gap apart, the first at the top. 0, 0 for a pin alone.
function ns.Map_FanOffset(i, n, gap)
	if not n or n < 2 then
		return 0, 0
	end
	local r = gap / 2 / math.sin(math.pi / n)
	local angle = -math.pi / 2 + (i - 1) * 2 * math.pi / n
	return r * math.cos(angle), r * math.sin(angle)
end

-- Town markers --------------------------------------------------------------------------------------------------------

-- The town marker kinds, in the minimap tracking menu's order: key (Data/Forever/Townsfolk.lua's, and db.town's),
-- the game's name for it (a global, looked up when shown) with an English fallback, and its tracking icon
-- (Interface\Minimap\Tracking\<icon>). Flight masters and dungeons are the map's own pins, in the same menu.
ns.MAP_TOWN_KINDS = {
	{ key = "auctioneer", global = "MINIMAP_TRACKING_AUCTIONEER", name = "Auctioneer", icon = "Auctioneer" },
	{ key = "banker", global = "MINIMAP_TRACKING_BANKER", name = "Banker", icon = "Banker" },
	{ key = "battlemaster", global = "MINIMAP_TRACKING_BATTLEMASTER", name = "Battlemaster", icon = "BattleMaster" },
	{ key = "innkeeper", global = "MINIMAP_TRACKING_INNKEEPER", name = "Innkeeper", icon = "Innkeeper" },
	{ key = "mailbox", global = "MINIMAP_TRACKING_MAILBOX", name = "Mailbox", icon = "Mailbox" },
	{ key = "class", global = "MINIMAP_TRACKING_TRAINER_CLASS", name = "Class Trainer", icon = "Class" },
	{ key = "profession", global = "MINIMAP_TRACKING_TRAINER_PROFESSION", name = "Profession Trainers",
		icon = "Profession" },
	{ key = "repair", global = "MINIMAP_TRACKING_REPAIR", name = "Repair", icon = "Repair" },
	{ key = "stablemaster", global = "MINIMAP_TRACKING_STABLEMASTER", name = "Stable Master", icon = "StableMaster" },
}

-- The rows of one kind you'd use: friendly to your side ("A" or "H"; a row without a side serves both) and, for
-- class trainers, of your class (token). rows: Townsfolk.lua's { map, x, y, name, title, side, class }. Returns
-- { mapID, x, y (0..1), name, title }.
function ns.Map_TownRows(rows, side, class)
	local out = {}
	for _, r in ipairs(rows or {}) do
		if (not r[6] or r[6] == side) and (not r[7] or r[7] == class) then
			out[#out + 1] = { mapID = r[1], x = r[2] / 100, y = r[3] / 100, name = r[4], title = r[5] }
		end
	end
	return out
end

-- Quest log search ----------------------------------------------------------------------------------------------------

-- Whether a quest matches what's typed in the quest log's search box: every word (any case) somewhere in its texts
-- (title, zone heading, objective lines; nils skipped). Empty text matches everything.
function ns.Map_QuestMatches(text, texts)
	local words = {}
	for word in (text or ""):lower():gmatch("%S+") do
		words[#words + 1] = word
	end
	if #words == 0 then
		return true
	end
	local all = {}
	for i = 1, #texts do
		if texts[i] then
			all[#all + 1] = tostring(texts[i]):lower()
		end
	end
	local haystack = table.concat(all, "\n")
	for _, word in ipairs(words) do
		if not haystack:find(word, 1, true) then
			return false
		end
	end
	return true
end

-- The lines under a quest in the map's quest log while its steps show, as the game's quest log has them: "Ready to
-- turn in" once it can be handed in, else each objective not done yet ("- 0/10 Resonite Crystal"; done ones are
-- left out, as the game's log does), else the quest's own short summary (a quest with nothing to count). objectives: { { text, finished } }. Returns
-- { { text, role } }.
function ns.Map_QuestSteps(objectives, complete, summary)
	if complete then
		return { { text = "Ready to turn in", role = "success" } }
	end
	local lines = {}
	for _, o in ipairs(objectives or {}) do
		if not o.finished then
			lines[#lines + 1] = { text = "- " .. o.text, role = "textMuted" }
		end
	end
	if #(objectives or {}) == 0 and summary and summary:find("%S") then
		lines[1] = { text = "- " .. summary:gsub("^%s+", ""):gsub("%s+$", ""), role = "textMuted" }
	end
	return lines
end

-- Town markers of one kind close together on the view become one pin: each spot joins the first group whose first
-- spot is within gap (pixels) of it. spots[1..n]: { x, y } in view pixels, always in the same order, so groups don't
-- change from frame to frame while nothing moves. Returns { { x, y (the members' middle), members = { i, ... } } }.
-- out: the list from the last call to fill again, its group tables reused (the view moves every frame while dragged),
-- or nil for a new one.
function ns.Map_Group(spots, n, gap, out)
	local groups = out or {}
	local count = 0
	local gap2 = gap * gap
	for i = 1, n do
		local s = spots[i]
		local home
		for k = 1, count do
			local g = groups[k]
			local first = spots[g.members[1]]
			local dx, dy = s.x - first.x, s.y - first.y
			if dx * dx + dy * dy <= gap2 then
				home = g
				break
			end
		end
		if home then
			home.members[#home.members + 1] = i
			home.sx, home.sy = home.sx + s.x, home.sy + s.y
		else
			count = count + 1
			local g = groups[count]
			if g then
				for m = #g.members, 1, -1 do
					g.members[m] = nil
				end
			else
				g = { members = {} }
				groups[count] = g
			end
			g.members[1], g.sx, g.sy = i, s.x, s.y
		end
	end
	for k = #groups, count + 1, -1 do
		groups[k] = nil
	end
	for k = 1, count do
		local g = groups[k]
		g.x, g.y = g.sx / #g.members, g.sy / #g.members
	end
	return groups
end

-- The order pins are drawn in: those further south (larger y) on top, as on the game's map, so overlapping pins
-- always stack the same way. spots: { y = ... } each; returns a list of their indexes, the one to draw first first.
function ns.Map_DrawOrder(spots)
	local order = {}
	for i = 1, #spots do
		order[i] = i
	end
	table.sort(order, function(a, b)
		if spots[a].y ~= spots[b].y then
			return spots[a].y < spots[b].y
		end
		return a < b
	end)
	return order
end
