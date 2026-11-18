-- Run from the AddOns folder: lua Tomte/tests/test_map.lua
local ns = {}
assert(loadfile("Tomte/Modules/Map/Data.lua"))("Tomte", ns)

local H = dofile("Tomte/tests/harness.lua")
local test, eq, near = H.test, H.eq, H.near

local W, Hh = 1000, 500

test("box and spots on it", function()
	local box = ns.Map_Box(0.1, 0.3, 0.2, 0.6, W, Hh)
	near(box.l, 100); near(box.t, 100); near(box.w, 200); near(box.h, 200)
	local cx, cy = ns.Map_InBox(box, 0.5, 0.25)
	near(cx, 200); near(cy, 150)
	local x, y = ns.Map_FromBox(box, cx, cy)
	near(x, 0.5); near(y, 0.25)
	eq(ns.Map_FromBox(box, 50, 150), nil, "outside")
end)

test("fit: the canvas just fits", function()
	near(ns.Map_Fit(800, 600, W, Hh), 0.8)
	near(ns.Map_Fit(800, 200, W, Hh), 0.4)
end)

test("view offset and canvas point round trip", function()
	local view = { u = 0.5, v = 0.5, zoom = 2 }
	local fit = 0.8
	local cx, cy = ns.Map_At(view, 80, -40, fit, W, Hh)
	near(cx, 550); near(cy, 225)
	local sx, sy = ns.Map_ToView(view, cx, cy, fit, W, Hh)
	near(sx, 80); near(sy, -40)
end)

test("zoom about the cursor keeps that point still", function()
	local view = { u = 0.3, v = 0.6, zoom = 1.5 }
	local fit = 0.8
	local cx, cy = ns.Map_At(view, 120, 60, fit, W, Hh)
	ns.Map_ZoomAbout(view, 120, 60, 6, fit, W, Hh)
	eq(view.zoom, 6)
	local ax, ay = ns.Map_At(view, 120, 60, fit, W, Hh)
	near(ax, cx); near(ay, cy)
end)

test("pan follows the mouse", function()
	local view = { u = 0.5, v = 0.5, zoom = 2 }
	local fit = 1
	local before = ns.Map_At(view, 0, 0, fit, W, Hh)
	ns.Map_Pan(view, 100, 0, fit, W, Hh)
	local after = ns.Map_At(view, 100, 0, fit, W, Hh)
	near(after, before, "the point under the mouse moved with it")
end)

test("clamp", function()
	local view = ns.Map_Clamp({ u = -1, v = 2, zoom = 100 }, 1, 48)
	eq(view.u, 0); eq(view.v, 1); eq(view.zoom, 48)
	-- Canvas 1000 x 500 in a 600 x 400 view at fit 0.6: 600 x 300 on screen, wider than tall.
	local fitted = ns.Map_Clamp({ u = 0.1, v = 0.9, zoom = 1 }, 1, 48, 600, 400, 0.6, 1000, 500)
	near(fitted.u, 0.5, "as wide as the view: centred"); near(fitted.v, 0.5, "smaller than the view: centred")
	local zoomed = ns.Map_Clamp({ u = 0, v = 1, zoom = 4 }, 1, 48, 600, 400, 0.6, 1000, 500)
	near(zoomed.u, 0.125, "no empty band left"); near(zoomed.v, 1 - 1 / 6, "no empty band below")
end)

test("view box and overlap", function()
	local box = ns.Map_ViewBox({ u = 0.5, v = 0.5, zoom = 2 }, 800, 400, 0.8, W, Hh, 0)
	near(box.w, 500); near(box.h, 250); near(box.l, 250); near(box.t, 125)
	eq(ns.Map_Overlaps(box, { l = 700, t = 300, w = 10, h = 10 }), true)
	eq(ns.Map_Overlaps(box, { l = 760, t = 300, w = 10, h = 10 }), false)
	local wide = ns.Map_ViewBox({ u = 0.5, v = 0.5, zoom = 2 }, 800, 400, 0.8, W, Hh, 0.5)
	near(wide.w, 750, "margin grows it")
end)

test("zoom for a box", function()
	-- A 100x100 box in an 800x400 view at fit 0.8: 4 view pixels per unit fills the height, zoom 5.
	near(ns.Map_ZoomFor({ l = 0, t = 0, w = 100, h = 100 }, 800, 400, 0.8, 1), 5)
end)

test("map art tiles: last row and column cropped, same file size", function()
	local tiles = ns.Map_Tiles(1002, 668, 256, 256)
	eq(#tiles, 12, "4 columns, 3 rows")
	eq(tiles[4].index, 4); eq(tiles[4].x, 768); near(tiles[4].w, 234); near(tiles[4].u, 234 / 256)
	eq(tiles[5].y, 256, "row by row")
	near(tiles[12].h, 156); near(tiles[12].v, 156 / 256)
	near(tiles[1].u, 1)
end)

test("explored overlay tiles: the last ones are smaller power-of-two files", function()
	local tiles = ns.Map_Tiles(300, 100, 256, 256, true)
	eq(#tiles, 2)
	near(tiles[1].w, 256); near(tiles[1].v, 100 / 128, "a 100-pixel row sits in a 128 file")
	near(tiles[2].w, 44); near(tiles[2].u, 44 / 64)
	tiles = ns.Map_Tiles(256, 10, 256, 256, true)
	near(tiles[1].v, 10 / 16, "16 is the smallest file")
end)

test("zone cut: runs of cells joined per row", function()
	-- 4 x 2 cells of 10 pixels over 40 x 15 art; row 1: cells 2-3, row 2: cells 1 and 4.
	local grid = { { false, true, true, false }, { true, false, false, true } }
	local runs = ns.Map_Runs(40, 15, 10, function(col, row)
		return grid[row][col]
	end)
	eq(#runs, 3)
	eq(runs[1].x0, 10); eq(runs[1].x1, 30); eq(runs[1].y0, 0); eq(runs[1].y1, 10)
	eq(runs[2].x0, 0); eq(runs[2].x1, 10); eq(runs[2].y1, 15, "the last row ends with the art")
	eq(runs[3].x0, 30); eq(runs[3].x1, 40, "a run to the right edge")
end)

test("zone cut: a run's pieces across tiles", function()
	-- Art 600 wide in 256 tiles (3 columns); a run from x 200 to 300, y 250 to 270 crosses two columns and two rows.
	local pieces = ns.Map_RunPieces({ x0 = 200, x1 = 300, y0 = 250, y1 = 270 }, 600, 256, 256)
	eq(#pieces, 4)
	local p = pieces[1]
	eq(p.index, 1); eq(p.x, 200); eq(p.w, 56); eq(p.y, 250); eq(p.h, 6)
	near(p.left, 200 / 256); near(p.right, 1); near(p.top, 250 / 256); near(p.bottom, 1)
	p = pieces[4]
	eq(p.index, 5, "row 2, column 2"); eq(p.x, 256); eq(p.w, 44); eq(p.y, 256); eq(p.h, 14)
	near(p.left, 0); near(p.right, 44 / 256); near(p.bottom, 14 / 256)
end)

test("world yards to a map spot", function()
	-- A map whose x runs west to east (world y falling) and y north to south (world x falling), as continents do.
	local from = ns.Map_FromWorld({ x = 1000, y = 2000 }, { x = 1000, y = -2000 }, { x = -3000, y = 2000 })
	local x, y = from(1000, 2000)
	near(x, 0); near(y, 0)
	x, y = from(-1000, 0)
	near(x, 0.5, "halfway east"); near(y, 0.5, "halfway south")
	eq(ns.Map_FromWorld({ x = 0, y = 0 }, { x = 1, y = 1 }, { x = 2, y = 2 }), nil, "corners on a line")
end)

test("minimap tile corners", function()
	local n, w, s, e = ns.Map_MiniTileWorld(32 * 64 + 32)
	near(n, 0); near(w, 0); near(s, -1600 / 3); near(e, -1600 / 3)
	n, w = ns.Map_MiniTileWorld(31 * 64 + 30)
	near(n, 2 * 1600 / 3, "two tiles north"); near(w, 1600 / 3, "one tile west")
end)

test("fade", function()
	eq(ns.Map_Fade(5, 10, 20), 0); eq(ns.Map_Fade(25, 10, 20), 1); near(ns.Map_Fade(15, 10, 20), 0.5)
end)

test("art level by zoom", function()
	eq(ns.Map_Level(1, 1.8, 4), "world")
	eq(ns.Map_Level(2, 1.8, 4), "continent")
	eq(ns.Map_Level(4, 1.8, 4), "zone")
end)

test("levels fade into each other", function()
	local c, z = ns.Map_LevelAlphas(1, 1.6, 3.5, 1.25)
	eq(c, 0); eq(z, 0)
	c, z = ns.Map_LevelAlphas(1.6, 1.6, 3.5, 1.25)
	near(c, 0.5, "halfway at the continents' start"); eq(z, 0)
	c, z = ns.Map_LevelAlphas(3.5, 1.6, 3.5, 1.25)
	eq(c, 1, "continents whole before zones start"); near(z, 0.5)
	c, z = ns.Map_LevelAlphas(10, 1.6, 3.5, 1.25)
	eq(c, 1); eq(z, 1)
end)

test("pins grow close up", function()
	eq(ns.Map_PinGrow(1, 1.6), 1); eq(ns.Map_PinGrow(8, 1.6), 1)
	near(ns.Map_PinGrow(16, 1.6), 1.3, "halfway in log space"); near(ns.Map_PinGrow(64, 1.6), 1.6)
	near(ns.Map_PinGrow(64, 1.3), 1.3)
end)

test("pins that overlap gather and ring round their middle", function()
	local spots = ns.Map_Clusters({ { x = 0, y = 0, key = 2 }, { x = 5, y = 0, key = 1 }, { x = 12, y = 0, key = 3 },
		{ x = 200, y = 0, key = 4 } }, 16)
	eq(spots[4].tx, 200, "alone: where it is"); eq(spots[4].ty, 0)
	for i = 1, 3 do
		for j = i + 1, 3 do
			local d = math.sqrt((spots[i].tx - spots[j].tx) ^ 2 + (spots[i].ty - spots[j].ty) ^ 2)
			assert(d > 15, ("pins %d and %d still overlap (%.1f)"):format(i, j, d))
		end
	end
	near(spots[2].tx, 17 / 3, "the lowest key on top, over the middle")
	local x1, y1 = ns.Map_FanOffset(1, 2, 16)
	local x2, y2 = ns.Map_FanOffset(2, 2, 16)
	near(math.sqrt((x1 - x2) ^ 2 + (y1 - y2) ^ 2), 16, "neighbours a gap apart")
	eq(ns.Map_FanOffset(1, 1, 16), 0)
end)

test("a flight: close stays in, far rises out and comes back in, in one move", function()
	local from = { u = 0.5, v = 0.5, zoom = 8 }
	local f = ns.Map_Flight(from, { u = 0.51, v = 0.5, zoom = 16 }, 800, 600, 0.8, 1000, 500, 1)
	eq(f.rise, 0, "close by"); eq(f.zoom, 16)
	from = { u = 0.2, v = 0.5, zoom = 16 }
	f = ns.Map_Flight(from, { u = 0.8, v = 0.5, zoom = 16 }, 800, 600, 0.8, 1000, 500, 1)
	assert(f.rise > 2, "far: out until both fit")
	assert(f.time >= 0.45 and f.time <= 2)
	local u, v, zoom = ns.Map_FlightAt(from, f, 0)
	near(u, 0.2); near(zoom, 16)
	u, v, zoom = ns.Map_FlightAt(from, f, 0.5)
	near(u, 0.5, "halfway across at the middle"); assert(zoom < 3, "zoomed out in the middle")
	u, v, zoom = ns.Map_FlightAt(from, f, 1)
	near(u, 0.8); near(zoom, 16)
end)

test("pins further south drawn on top", function()
	local order = ns.Map_DrawOrder({ { y = 0.5 }, { y = 0.2 }, { y = 0.5 }, { y = 0.9 } })
	eq(order[1], 2); eq(order[2], 1); eq(order[3], 3, "a tie keeps its order"); eq(order[4], 4)
end)

test("quest log search: every word, any case, any text", function()
	local texts = { "Boulderslide Ravine", "Stonetalon Mountains", "0/10 Resonite Crystal" }
	eq(ns.Map_QuestMatches("", texts), true)
	eq(ns.Map_QuestMatches("  ", texts), true)
	eq(ns.Map_QuestMatches("ravine", texts), true)
	eq(ns.Map_QuestMatches("crystal stonetalon", texts), true, "words from different texts")
	eq(ns.Map_QuestMatches("crystal barrens", texts), false)
	eq(ns.Map_QuestMatches("(", texts), false, "plain text, not a pattern")
	eq(ns.Map_QuestMatches("ravine", { nil, "Ravine" }), true, "nils skipped")
end)

test("quest steps: ready, objectives, or the summary", function()
	local ready = ns.Map_QuestSteps({ { text = "0/1 Head" } }, true, "Bring a head.")
	eq(#ready, 1); eq(ready[1].text, "Ready to turn in"); eq(ready[1].role, "success")
	local steps = ns.Map_QuestSteps({ { text = "0/10 Resonite Crystal" }, { text = "Investigate Cave", finished = true } })
	eq(#steps, 1, "done steps left out"); eq(steps[1].text, "- 0/10 Resonite Crystal"); eq(steps[1].role, "textMuted")
	eq(#ns.Map_QuestSteps({ { text = "Done", finished = true } }, false, "Summary"), 0, "no summary for counted quests")
	local told = ns.Map_QuestSteps({}, false, "  Deliver the envelope.\n")
	eq(#told, 1); eq(told[1].text, "- Deliver the envelope.")
	eq(#ns.Map_QuestSteps({}, false, "  "), 0)
	eq(#ns.Map_QuestSteps(nil, false, nil), 0)
end)

test("town markers close together group", function()
	local spots = { { x = 0, y = 0 }, { x = 5, y = 0 }, { x = 100, y = 100 }, { x = 0, y = 8 }, { x = 30, y = 0 } }
	local groups = ns.Map_Group(spots, #spots, 10)
	eq(#groups, 3)
	eq(#groups[1].members, 3, "the first, its neighbour and the one under it")
	near(groups[1].x, 5 / 3); near(groups[1].y, 8 / 3)
	eq(groups[2].members[1], 3)
	eq(groups[3].members[1], 5, "too far from the first spot")
	eq(#ns.Map_Group(spots, 2, 10), 1, "only the first n")
	eq(#ns.Map_Group(spots, 0, 10), 0)
	-- Filled again into the last call's list: the same tables, nothing left over from before.
	local kept, firstGroup = groups, groups[1]
	local again = ns.Map_Group(spots, #spots, 10, kept)
	eq(again, kept); eq(again[1], firstGroup, "a group table reused")
	eq(#again, 3); eq(#again[1].members, 3); eq(again[3].members[1], 5)
	again = ns.Map_Group({ { x = 0, y = 0 }, { x = 50, y = 0 } }, 2, 10, kept)
	eq(#again, 2, "fewer groups: the rest dropped"); eq(#again[1].members, 1, "old members gone")
end)

test("view box: filled into a given table", function()
	local out = {}
	local box = ns.Map_ViewBox({ u = 0.5, v = 0.5, zoom = 2 }, 800, 400, 0.8, 1000, 500, 0, out)
	eq(box, out)
	near(box.w, 500); near(box.l, 250)
end)

test("pins that ring out: a second call with fewer pins, nothing left from the first", function()
	local spots = ns.Map_Clusters({ { x = 0, y = 0, key = 1 }, { x = 5, y = 0, key = 2 }, { x = 8, y = 0, key = 3 } }, 16)
	assert(spots[1].ty < 0, "the lowest key on top")
	spots = ns.Map_Clusters({ { x = 0, y = 0, key = 7 } }, 16)
	eq(spots[1].tx, 0); eq(spots[1].ty, 0)
	spots = ns.Map_Clusters({}, 16)
	eq(#spots, 0)
end)

test("town rows: your side and your class", function()
	local rows = {
		{ 1453, 60, 70, "Aldric", "Banker", "A" },
		{ 1454, 50, 40, "Kesha", "Banker", "H" },
		{ 1453, 61, 71, "Mira", "Warrior Trainer", "A", "WARRIOR" },
		{ 1453, 62, 72, "Tobin", "Mage Trainer", "A", "MAGE" },
		{ 1437, 10, 20 },
	}
	local mine = ns.Map_TownRows(rows, "A", "MAGE")
	eq(#mine, 3)
	eq(mine[1].name, "Aldric"); near(mine[1].x, 0.6); near(mine[1].y, 0.7); eq(mine[1].mapID, 1453)
	eq(mine[2].name, "Tobin", "other classes' trainers left out")
	eq(mine[3].name, nil, "a row for both sides (a mailbox)")
	eq(#ns.Map_TownRows(nil, "H"), 0)
	for _, kind in ipairs(ns.MAP_TOWN_KINDS) do
		eq(type(kind.key), "string"); eq(type(kind.icon), "string")
	end
end)

H.done()
