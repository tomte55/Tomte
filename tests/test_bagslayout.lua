-- Run from the AddOns folder: lua Tomte/tests/test_bagslayout.lua
local ns = {}
assert(loadfile("Tomte/Modules/Bags/Layout.lua"))("Tomte", ns)

local H = dofile("Tomte/tests/harness.lua")
local test, eq = H.test, H.eq

-- 10 columns of 30 px icons with 2 px gaps: a cell is 32, the full width 318.
local OPTS = { columns = 10, icon = 30, gap = 2, label = 14, section = 20, spacing = 12, lineGap = 6 }

local function cat(key, count, section, label)
	local text = key
	if label == false then
		text = nil
	end
	return { kind = "category", key = key, label = text, count = count, section = section }
end

local function find(placed, key)
	for _, p in ipairs(placed) do
		if p.block.key == key then
			return p
		end
	end
	return nil
end

test("two small categories share a line", function()
	local placed, _, width = ns.Bags_Pack({ cat("a", 3), cat("b", 3) }, OPTS)
	eq(width, 318)
	local b = find(placed, "b")
	eq(b.y, 0)
	eq(b.x, 3 * 32 - 2 + 12)
	eq(b.cells[1].x, b.x)
	eq(b.cells[1].y, 14)
end)

test("a category that doesn't fit starts a new line", function()
	local placed = ns.Bags_Pack({ cat("a", 3), cat("b", 3), cat("c", 9) }, OPTS)
	local c = find(placed, "c")
	eq(c.x, 0)
	eq(c.y, 14 + 30 + 6)
end)

test("a big category wraps over full rows", function()
	local placed, height = ns.Bags_Pack({ cat("a", 25) }, OPTS)
	local a = find(placed, "a")
	eq(#a.cells, 25)
	eq(a.width, 318)
	eq(a.cells[11].x, 0)
	eq(a.cells[11].y, 14 + 32)
	eq(a.cells[25].y, 14 + 64)
	eq(height, 14 + 3 * 32 - 2)
end)

test("sections start a new line and folded ones hide their categories", function()
	local placed, height = ns.Bags_Pack({
		cat("a", 2),
		{ kind = "section", key = "s", label = "S", folded = true },
		cat("b", 2, "s"),
		cat("c", 2),
	}, OPTS)
	local s = find(placed, "s")
	eq(s.y, 14 + 30 + 6)
	eq(find(placed, "b"), nil)
	local c = find(placed, "c")
	eq(c.y, s.y + 20)
	eq(c.x, 0)
	eq(height, c.y + 14 + 30)
end)

test("the first category after a section's contents starts a new line", function()
	local placed = ns.Bags_Pack({
		{ kind = "section", key = "s", label = "S" },
		cat("b", 2, "s"),
		cat("c", 2),
	}, OPTS)
	local b, c = find(placed, "b"), find(placed, "c")
	eq(b.y, 20)
	eq(c.x, 0)
	eq(c.y, 20 + 14 + 30 + 6)
end)

test("a section whose categories are all empty is left out", function()
	local placed = ns.Bags_Pack({
		cat("a", 2),
		{ kind = "section", key = "s", label = "S" },
		cat("b", 0, "s"),
		{ kind = "section", key = "t", label = "T" },
		cat("c", 1, "t"),
	}, OPTS)
	eq(find(placed, "s"), nil)
	local t = find(placed, "t")
	eq(t.y, 14 + 30 + 6)
	eq(find(placed, "c").y, t.y + 20)
end)

test("a folded section with items still shows its heading", function()
	local placed = ns.Bags_Pack({
		{ kind = "section", key = "s", label = "S", folded = true },
		cat("b", 3, "s"),
	}, OPTS)
	eq(find(placed, "s").y, 0)
	eq(find(placed, "b"), nil)
end)

test("an ownLine category shares its line with nothing", function()
	local own = cat("new", 2)
	own.ownLine = true
	local placed = ns.Bags_Pack({ own, cat("b", 2), cat("c", 2) }, OPTS)
	eq(find(placed, "new").y, 0)
	local b, c = find(placed, "b"), find(placed, "c")
	eq(b.x, 0)
	eq(b.y, 14 + 30 + 6)
	eq(c.y, b.y, "the next ones share a line again")
	own = cat("up", 1)
	own.ownLine = true
	placed = ns.Bags_Pack({ cat("a", 2), own }, OPTS)
	eq(find(placed, "up").x, 0)
	eq(find(placed, "up").y, 14 + 30 + 6)
end)

test("empty categories are skipped", function()
	local placed = ns.Bags_Pack({ cat("a", 0), cat("b", 1) }, OPTS)
	eq(find(placed, "a"), nil)
	eq(find(placed, "b").x, 0)
end)

test("an unlabeled block has no label line", function()
	local placed, height = ns.Bags_Pack({ cat("all", 12, nil, false) }, OPTS)
	eq(find(placed, "all").cells[1].y, 0)
	eq(height, 2 * 32 - 2)
end)

test("a divider starts a new line and takes a line gap", function()
	local placed = ns.Bags_Pack({ cat("a", 2), { kind = "divider" }, cat("b", 2) }, OPTS)
	eq(find(placed, "b").y, 14 + 30 + 6 + 6)
end)

H.done()
