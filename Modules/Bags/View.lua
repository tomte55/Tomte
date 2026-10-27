local addonName, ns = ...

-- Bags: drawing a set of items into a frame, shared by the bag window (Window.lua) and the bank window (Bank.lua):
-- categories (Data.lua sorts items into them, Layout.lua packs them) or one bag, section headings that fold, dividers,
-- category labels, kept places while a window that takes items is open, and the item buttons (Buttons.lua).

local LABEL_H = 13 -- a category's label line
local SECTION_H = 18 -- a section heading
local LINE_GAP = 6 -- between lines
local GAP = 2 -- between icons
local FADED = 0.3 -- a category label whose items are all filtered out by the search

local UI = ns.UI

local View = {}
View.__index = View

-- A view drawing into body (a frame); db is the module's saved settings (columns, sizes, sort); folded is this
-- window's own table of folded sections ([section key] = true), so the bag and bank windows fold apart.
function ns.BagsView_New(body, db, folded)
	return setmetatable({ body = body, db = db, folded = folded, labels = {}, headings = {}, rules = {} }, View)
end

local function Pooled(pool, i, make)
	local item = pool[i]
	if not item then
		item = make()
		pool[i] = item
	end
	return item
end

function View:Label(i)
	return Pooled(self.labels, i, function()
		local fs = UI.Text(self.body, 10, "textMuted", "label")
		fs:SetWordWrap(false)
		return fs
	end)
end

function View:Heading(i)
	return Pooled(self.headings, i, function()
		local b = CreateFrame("Button", nil, self.body)
		b:SetHeight(SECTION_H)
		b.text = UI.Text(b, 12, "heading", "title")
		b.text:SetPoint("LEFT")
		b:SetScript("OnClick", function(h)
			self.folded[h.key] = not self.folded[h.key] or nil
			ns.BagsWindow_Relayout()
		end)
		return b
	end)
end

function View:Rule(i)
	return Pooled(self.rules, i, function()
		return UI.Hairline(self.body, 100, 0.5)
	end)
end

-- The blocks Layout.lua packs, and the records each category shows (one Empty button per kind of slot, carrying how
-- many are free). Hidden categories are left out with their items.
function View:CategoryBlocks(items, layout, place)
	local db = self.db
	local byKey = ns.Bags_Assign(items, ns.Bags_Flatten(layout), place)
	local blocks, contents = {}, {}
	local function Add(node, section)
		if node.hidden then
			return
		end
		local list = byKey[node.key] or {}
		if node.auto == "empty" then
			local firstOfKind, free = {}, {}
			for _, slot in ipairs(list) do
				free[slot.kind] = (free[slot.kind] or 0) + 1
				if not firstOfKind[slot.kind] then
					firstOfKind[slot.kind] = slot
				end
			end
			list = {}
			for _, kind in ipairs({ "normal", "reagent" }) do
				if firstOfKind[kind] then
					-- A copy: the slot's own record may also stand in its old place while places are kept, as a plain
					-- empty slot without Empty's count and leaf.
					list[#list + 1] = setmetatable({ free = free[kind] }, { __index = firstOfKind[kind] })
				end
			end
		else
			ns.Bags_SortItems(list, db.sortMethod, db.sortReverse)
		end
		blocks[#blocks + 1] = { kind = "category", key = node.key, label = node.name, count = #list, section = section,
			ownLine = node.ownLine }
		contents[node.key] = list
	end
	for _, node in ipairs(layout) do
		if node.kind == "section" then
			blocks[#blocks + 1] = { kind = "section", key = node.key, label = node.name, folded = self.folded[node.key] }
			for _, child in ipairs(node.children or {}) do
				if child.kind == "category" then
					Add(child, node.key)
				end
			end
		elseif node.kind == "divider" then
			blocks[#blocks + 1] = { kind = "divider" }
		elseif node.kind == "category" then
			Add(node, nil)
		end
	end
	return blocks, contents
end

-- One bag: every item, sorted, then the empty slots.
function View:SingleBlocks(items)
	local filled, empty = {}, {}
	for _, item in ipairs(items) do
		if item.empty then
			empty[#empty + 1] = item
		else
			filled[#filled + 1] = item
		end
	end
	ns.Bags_SortItems(filled, self.db.sortMethod, self.db.sortReverse)
	for _, slot in ipairs(empty) do
		filled[#filled + 1] = slot
	end
	return { { kind = "category", key = "all", count = #filled } }, { all = filled }
end

-- Forgets the kept places (the window closed, or what takes items closed).
function View:Release()
	self.snapshot = nil
end

-- Draws items. opts: layout (category nodes), place ("bags" | "bank" | "warband"), holding (keep places),
-- matches(item) -> bright or faded, paint (Buttons.lua's paint options), button(item) -> the item's button (default:
-- its bag slot's). Returns the drawn width and height.
function View:Draw(items, opts)
	local db = self.db
	if db.group then
		items = ns.Bags_Group(items)
	end
	local blocks, contents
	if db.view == "single" then
		blocks, contents = self:SingleBlocks(items)
	else
		blocks, contents = self:CategoryBlocks(items, opts.layout, opts.place)
	end
	if opts.holding then
		if self.snapshot then
			local bySlot = {}
			for _, item in ipairs(items) do
				bySlot[item.bag * 1000 + item.slot] = item
			end
			contents = ns.Bags_KeepPlaces(self.snapshot, contents, bySlot)
			for _, block in ipairs(blocks) do
				if block.kind == "category" then
					block.count = #(contents[block.key] or {})
				end
			end
		else
			self.snapshot = ns.Bags_Snapshot(contents)
		end
	else
		self.snapshot = nil
	end
	local size = db.iconSize
	local placed, height, width = ns.Bags_Pack(blocks, {
		columns = opts.columns or db.columns, icon = size, gap = GAP, label = LABEL_H, section = SECTION_H,
		spacing = db.spacing, lineGap = LINE_GAP,
	})
	local nLabels, nHeadings, nRules = 0, 0, 0
	local paint = opts.paint
	local body = self.body
	local drawn = {} -- [button] = true
	for _, p in ipairs(placed) do
		local block = p.block
		if block.kind == "section" then
			nHeadings = nHeadings + 1
			local h = self:Heading(nHeadings)
			h.key = block.key
			h.text:SetText((block.folded and "+ " or "- ") .. block.label)
			h:SetWidth(p.width)
			h:ClearAllPoints()
			h:SetPoint("TOPLEFT", body, "TOPLEFT", p.x, -p.y)
			h:Show()
		elseif block.kind == "divider" then
			nRules = nRules + 1
			local r = self:Rule(nRules)
			r:SetWidth(p.width)
			r:ClearAllPoints()
			r:SetPoint("TOPLEFT", body, "TOPLEFT", p.x, -(p.y + LINE_GAP / 2))
			r:Show()
		else
			local list = contents[block.key]
			local anyMatch = false
			for i, cell in ipairs(p.cells) do
				local item = list[i]
				local button = opts.button and opts.button(item, i) or ns.BagsButtons_Get(item.bag, item.slot, body)
				paint.matches = opts.matches(item)
				paint.free = item.free
				anyMatch = anyMatch or paint.matches
				ns.BagsButtons_Place(button, body, cell.x, cell.y, size)
				ns.BagsButtons_Paint(button, item, paint)
				drawn[button] = true
			end
			if block.label then
				nLabels = nLabels + 1
				local fs = self:Label(nLabels)
				fs:SetText(block.label)
				fs:SetWidth(math.max(p.width, size))
				fs:ClearAllPoints()
				fs:SetPoint("TOPLEFT", body, "TOPLEFT", p.x, -p.y)
				fs:SetAlpha(anyMatch and 1 or FADED)
				fs:Show()
			end
		end
	end
	ns.BagsButtons_HideOthers(drawn, body)
	for i = nLabels + 1, #self.labels do
		self.labels[i]:Hide()
	end
	for i = nHeadings + 1, #self.headings do
		self.headings[i]:Hide()
	end
	for i = nRules + 1, #self.rules do
		self.rules[i]:Hide()
	end
	body:SetSize(width, math.max(height, 1))
	return width, height
end
