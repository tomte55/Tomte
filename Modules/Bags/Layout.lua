local addonName, ns = ...

-- Bags: pure logic (no WoW API calls; unit-tested in tests/test_bagslayout.lua): packs categories into lines like
-- text, small ones side by side, for Window.lua to draw.

-- blocks: an ordered list of
--   { kind = "category", key, label, count, section, ownLine }   (label nil: no label line, the one-bag view;
--                                                                  ownLine: nothing shares its line)
--   { kind = "section", key, label, folded }             (its categories follow with section = its key)
--   { kind = "divider" }
-- opts: columns (icons per row), icon, gap (between icons), label (label line height), section (heading height),
-- spacing (between categories on one line), lineGap (between lines).
-- Returns placed, height, width. placed[i] = { block, x, y, width, cells = { { x, y } ... } } in pixels from the
-- top-left. A category is min(count, columns) icons wide and goes on the current line when it fits; sections,
-- dividers, the first category after a section's contents and an ownLine category start a new line. Empty
-- categories, the categories of a folded section and sections whose categories are all empty are left out.
function ns.Bags_Pack(blocks, opts)
	local cell = opts.icon + opts.gap
	local width = opts.columns * cell - opts.gap
	local placed = {}
	local x, top, lineHeight = 0, 0, 0
	local currentSection, folded = nil, {}
	local filled = {} -- [section key] = true when one of its categories has items
	for _, block in ipairs(blocks) do
		if block.kind == "category" and block.section and (block.count or 0) > 0 then
			filled[block.section] = true
		end
	end

	local function NewLine()
		if x > 0 or lineHeight > 0 then
			top = top + lineHeight + opts.lineGap
		end
		x, lineHeight = 0, 0
	end

	for _, block in ipairs(blocks) do
		if block.kind == "section" and filled[block.key] then
			NewLine()
			placed[#placed + 1] = { block = block, x = 0, y = top, width = width }
			top = top + opts.section
			currentSection = block.key
			folded[block.key] = block.folded and true or nil
		elseif block.kind == "divider" then
			NewLine()
			placed[#placed + 1] = { block = block, x = 0, y = top, width = width }
			top = top + opts.lineGap
			currentSection = nil
		elseif block.kind == "category" and (block.count or 0) > 0 and not (block.section and folded[block.section]) then
			if block.section ~= currentSection then
				NewLine()
				currentSection = block.section
			end
			if block.ownLine then
				NewLine()
			end
			local across = math.min(block.count, opts.columns)
			local w = across * cell - opts.gap
			if x > 0 and x + opts.spacing + w > width then
				NewLine()
			end
			local left = x > 0 and (x + opts.spacing) or 0
			local labelHeight = block.label and opts.label or 0
			local cells = {}
			for i = 1, block.count do
				local col, row = (i - 1) % opts.columns, math.floor((i - 1) / opts.columns)
				cells[i] = { x = left + col * cell, y = top + labelHeight + row * cell }
			end
			local rows = math.ceil(block.count / opts.columns)
			placed[#placed + 1] = { block = block, x = left, y = top, width = w, cells = cells }
			x = left + w
			lineHeight = math.max(lineHeight, labelHeight + rows * cell - opts.gap)
			if block.ownLine then
				NewLine()
			end
		end
	end
	local height = top + lineHeight
	return placed, height, width
end
