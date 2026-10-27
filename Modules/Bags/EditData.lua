local addonName, ns = ...

-- Bags: editing the categories: pure logic (no WoW API calls; unit-tested in tests/test_bagsedit.lua). The layout is
-- Data.lua's node list (categories, sections holding categories, dividers); the player's copy lives in the module's
-- saved layout, made from the defaults on the first edit. Every node gets a key so the editor can point at it.
-- Sharing writes nodes as text and reads them back. The editor page is EditPage.lua.

local SHARE_HEADER = "TomteBags:1" -- first line of a shared text; the number is the format's version
local PLACES = { "bags", "bank", "warband" }

local function Copy(value)
	if type(value) ~= "table" then
		return value
	end
	local out = {}
	for k, v in pairs(value) do
		out[k] = Copy(v)
	end
	return out
end

-- Keys -------------------------------------------------------------------------------------------------------------

local function Walk(nodes, fn, parent)
	for i, node in ipairs(nodes) do
		if fn(node, nodes, i, parent) then
			return true
		end
		if node.kind == "section" and Walk(node.children or {}, fn, node) then
			return true
		end
	end
	return false
end

-- A key not used in layout yet: prefix .. n.
local function FreshKey(layout, prefix)
	local used = {}
	Walk(layout, function(node)
		if node.key then
			used[node.key] = true
		end
	end)
	local n = 1
	while used[prefix .. n] do
		n = n + 1
	end
	return prefix .. n
end

-- A copy of layout with every node keyed (the defaults' dividers have none). Fields Data.lua adds while sorting
-- (order, section) are left out.
function ns.BagsEdit_Copy(layout)
	local out = Copy(layout)
	Walk(out, function(node)
		node.order, node.section = nil, nil
	end)
	Walk(out, function(node)
		if not node.key then
			node.key = FreshKey(out, node.kind == "divider" and "d" or "n")
		end
	end)
	return out
end

-- The list holding the node with key, its index there, the node and the section it's in (nil at the top).
function ns.BagsEdit_Find(layout, key)
	local found
	Walk(layout, function(node, list, i, parent)
		if node.key == key then
			found = { list = list, index = i, node = node, section = parent }
			return true
		end
	end)
	if found then
		return found.list, found.index, found.node, found.section
	end
	return nil
end

-- Editing ----------------------------------------------------------------------------------------------------------

-- Moves a node one place up (delta -1) or down (+1) in its list. Returns true when it moved.
function ns.BagsEdit_Move(layout, key, delta)
	local list, i = ns.BagsEdit_Find(layout, key)
	local j = i and i + delta
	if not j or j < 1 or j > #list then
		return false
	end
	list[i], list[j] = list[j], list[i]
	return true
end

-- Moves a category into a section (at its end), or out of it to the top level right after the section (sectionKey
-- nil). Sections and dividers stay at the top level. Returns true when it moved.
function ns.BagsEdit_SetSection(layout, key, sectionKey)
	local list, i, node, current = ns.BagsEdit_Find(layout, key)
	if not node or node.kind ~= "category" then
		return false
	end
	if (current and current.key) == sectionKey then
		return false
	end
	local target, at
	if sectionKey then
		local _, _, section = ns.BagsEdit_Find(layout, sectionKey)
		if not section or section.kind ~= "section" then
			return false
		end
		section.children = section.children or {}
		target, at = section.children, #section.children + 1
	end
	table.remove(list, i)
	if not target then
		local _, sectionIndex = ns.BagsEdit_Find(layout, current.key)
		target, at = layout, sectionIndex + 1
	end
	table.insert(target, at, node)
	return true
end

-- A new category at the end of a section (sectionKey), or at the top of the layout. Returns the node.
function ns.BagsEdit_AddCategory(layout, name, rule, sectionKey)
	local node = { kind = "category", key = FreshKey(layout, "c"), name = name, rule = rule or "", priority = 0 }
	if sectionKey then
		local _, _, section = ns.BagsEdit_Find(layout, sectionKey)
		if section and section.kind == "section" then
			section.children = section.children or {}
			table.insert(section.children, node)
			return node
		end
	end
	table.insert(layout, 1, node)
	return node
end

-- A new section or divider at the top of the layout. Returns the node.
function ns.BagsEdit_AddSection(layout, name)
	local node = { kind = "section", key = FreshKey(layout, "s"), name = name, children = {} }
	table.insert(layout, 1, node)
	return node
end

function ns.BagsEdit_AddDivider(layout)
	local node = { kind = "divider", key = FreshKey(layout, "d") }
	table.insert(layout, 1, node)
	return node
end

-- Removes a node. A section's categories move to the top level where it was. Other and Empty can't go (every item
-- needs a place): only hidden. Returns true when removed.
function ns.BagsEdit_Remove(layout, key)
	local list, i, node = ns.BagsEdit_Find(layout, key)
	if not node or node.auto == "other" or node.auto == "empty" then
		return false
	end
	table.remove(list, i)
	if node.kind == "section" then
		for n, child in ipairs(node.children or {}) do
			table.insert(list, i + n - 1, child)
		end
	end
	return true
end

-- Item IDs pasted or dropped into a category's always-include list: "123, 456 789" -> { [123] = true, ... }.
function ns.BagsEdit_ParseIDs(text)
	local ids = {}
	for id in (text or ""):gmatch("%d+") do
		ids[tonumber(id)] = true
	end
	return ids
end

-- The always-include list as text, lowest ID first.
function ns.BagsEdit_IDsText(ids)
	local list = {}
	for id in pairs(ids or {}) do
		list[#list + 1] = id
	end
	table.sort(list)
	for i, id in ipairs(list) do
		list[i] = tostring(id)
	end
	return table.concat(list, ", ")
end

-- Saved searches: { { name, text } }. Saving under a name already used replaces it.
function ns.BagsEdit_SaveSearch(searches, name, text)
	for _, saved in ipairs(searches) do
		if saved.name == name then
			saved.text = text
			return saved
		end
	end
	local saved = { name = name, text = text }
	searches[#searches + 1] = saved
	return saved
end

-- Sharing ----------------------------------------------------------------------------------------------------------

local function Escape(text)
	return (tostring(text or ""):gsub("\\", "\\\\"):gsub("|", "\\p"):gsub("\n", "\\n"))
end

local function Unescape(text)
	return (text:gsub("\\(.)", function(c)
		if c == "p" then
			return "|"
		elseif c == "n" then
			return "\n"
		end
		return c
	end))
end

-- Splits a line on unescaped "|".
local function Fields(line)
	local fields, current, i = {}, {}, 1
	while i <= #line do
		local c = line:sub(i, i)
		if c == "\\" then
			current[#current + 1] = line:sub(i, i + 1)
			i = i + 2
		elseif c == "|" then
			fields[#fields + 1] = Unescape(table.concat(current))
			current = {}
			i = i + 1
		else
			current[#current + 1] = c
			i = i + 1
		end
	end
	fields[#fields + 1] = Unescape(table.concat(current))
	return fields
end

local function Flags(node)
	local flags = {}
	if node.ownLine then
		flags[#flags + 1] = "o"
	end
	if node.hidden then
		flags[#flags + 1] = "h"
	end
	for _, place in ipairs(PLACES) do
		if node.shows and node.shows[place] == false then
			flags[#flags + 1] = "-" .. place
		end
	end
	return table.concat(flags, ",")
end

local function ReadFlags(node, text)
	for flag in (text or ""):gmatch("[^,]+") do
		if flag == "o" then
			node.ownLine = true
		elseif flag == "h" then
			node.hidden = true
		elseif flag:sub(1, 1) == "-" then
			node.shows = node.shows or {}
			node.shows[flag:sub(2)] = false
		end
	end
end

-- Categories as text to paste elsewhere (sections with their categories; dividers left out). One line per node:
-- kind|name|priority|flags|rule|item IDs, a section's categories after it marked with kind "in".
function ns.BagsEdit_Export(nodes)
	local lines = { SHARE_HEADER }
	local function Line(kind, node)
		lines[#lines + 1] = table.concat({
			kind, Escape(node.name), tostring(node.priority or 0), Flags(node), Escape(node.rule or node.auto or ""),
			(ns.BagsEdit_IDsText(node.items):gsub(" ", "")),
		}, "|")
	end
	for _, node in ipairs(nodes) do
		if node.kind == "category" and not node.auto then
			Line("cat", node)
		elseif node.kind == "section" then
			Line("sec", node)
			for _, child in ipairs(node.children or {}) do
				if child.kind == "category" and not child.auto then
					Line("in", child)
				end
			end
		end
	end
	return table.concat(lines, "\n")
end

-- Shared text back to nodes for layout: added at the top with new keys. Returns the added nodes, or nil and a
-- reason.
function ns.BagsEdit_Import(layout, text)
	local lines = {}
	for line in (text or ""):gmatch("[^\r\n]+") do
		lines[#lines + 1] = line
	end
	if lines[1] ~= SHARE_HEADER then
		return nil, "That isn't a Tomte bag category text."
	end
	local added, section = {}, nil
	for n = 2, #lines do
		local f = Fields(lines[n])
		if #f < 6 then
			return nil, ("Line %d is cut short."):format(n)
		end
		local node = { name = f[2], priority = tonumber(f[3]) or 0, rule = f[5] }
		ReadFlags(node, f[4])
		local ids = ns.BagsEdit_ParseIDs(f[6])
		if next(ids) then
			node.items = ids
		end
		if f[1] == "sec" then
			node.kind, node.rule, node.priority, node.children = "section", nil, nil, {}
			section = node
			added[#added + 1] = node
		elseif f[1] == "in" and section then
			node.kind = "category"
			table.insert(section.children, node)
		elseif f[1] == "cat" or f[1] == "in" then
			node.kind = "category"
			section = nil
			added[#added + 1] = node
		end
	end
	for i = #added, 1, -1 do
		table.insert(layout, 1, added[i])
	end
	Walk(layout, function(node)
		if not node.key then
			node.key = FreshKey(layout, node.kind == "section" and "s" or "c")
		end
	end)
	return added
end
