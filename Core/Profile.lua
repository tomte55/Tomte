local addonName, ns = ...

-- Settings profiles: what a setting is (the same line "Reset settings" draws, Core/Modules.lua), collecting them,
-- and checking a string from someone else before anything is written. Pure: no WoW API. The C_EncodingUtil codec is
-- passed in (Panel/Share.lua), so tests use a fake one.
--
-- A setting: a value under module.defaults, reached through tables that aren't collections (ns.IsCollection), except
-- module.keep (personal text), keys named collapsed/view at any depth (which tab or section was open), tables with a
-- point key (a frame's position) and module.noShare paths (one screen's or one character's state). Plus
-- module.shareMaps: settings kept in a map whose default is empty ({ name = "boolean" | "number" | "string" }).
--
-- Imported data is only ever compared and written as a plain value at a path that exists in the current schema.
-- Nothing in it is called or run.

ns.PROFILE_VERSION = 1
ns.PROFILE_PREFIX = "Tomte"
ns.PROFILE_MAX_TEXT = 20000
ns.PROFILE_MAX_DATA = 262144 -- decompressed bytes, checked by the codec
ns.PROFILE_MAX_ENTRIES = 2000
ns.PROFILE_MAX_STRING = 200

local UI_STATE = { collapsed = true, view = true }
local MAP_KEY = "^[%w_%-]+$"
local MAP_KEY_MAX = 64
local ENABLED = "_enabled"

local ERR_EMPTY = "Paste a Tomte settings string first."
local ERR_LONG = "Too long to be a Tomte settings string."
local ERR_NOT = "That's not a Tomte settings string."
local ERR_NEWER = "Made by a newer Tomte. Update Tomte first."
local ERR_DAMAGED = "The string is damaged. Copy it again."

local function Listed(list, path)
	for _, p in ipairs(list or {}) do
		if path == p or path:sub(1, #p + 1) == p .. "." then
			return true
		end
	end
	return false
end

local function Walk(module, src, prefix, schema, keep)
	for k, v in pairs(src) do
		assert(type(k) ~= "string" or not k:find(".", 1, true),
			"default keys can't contain a dot: " .. tostring(module.key) .. " " .. tostring(k))
		local path = prefix .. tostring(k)
		local skip = UI_STATE[k] or (prefix == "" and keep[k]) or Listed(module.noShare, path)
		if not skip then
			if type(v) == "table" then
				if v.point == nil and not ns.IsCollection(v) then
					Walk(module, v, path .. ".", schema, keep)
				end
			elseif type(v) == "boolean" or type(v) == "number" or type(v) == "string" then
				schema[path] = type(v)
			end
		end
	end
end

-- { [path] = "boolean" | "number" | "string" }, paths joined with "."; a shareMaps entry is "<name>.*".
function ns.Profile_Schema(module)
	local schema, keep = {}, {}
	for _, k in ipairs(module.keep or {}) do
		keep[k] = true
	end
	Walk(module, module.defaults or {}, "", schema, keep)
	for name, t in pairs(module.shareMaps or {}) do
		schema[name .. ".*"] = t
	end
	return schema
end

function ns.Profile_Get(tbl, path)
	local value = tbl
	for part in path:gmatch("[^.]+") do
		if type(value) ~= "table" then
			return nil
		end
		value = value[part]
	end
	return value
end

function ns.Profile_Set(tbl, path, value)
	local parent, last = tbl, nil
	for part in path:gmatch("[^.]+") do
		if last then
			if type(parent[last]) ~= "table" then
				parent[last] = {}
			end
			parent = parent[last]
		end
		last = part
	end
	parent[last] = value
end

-- The saved choice, or the module's default (ns.ModuleEnabled without ns.db).
local function EnabledIn(db, module)
	local saved = type(db.enabled) == "table" and db.enabled[module.key]
	if type(saved) == "boolean" then
		return saved
	end
	return module.enabledByDefault == true
end

local function ValidMapKey(k)
	return type(k) == "string" and #k <= MAP_KEY_MAX and k:find(MAP_KEY) ~= nil
end

-- Every shareable value (not only the changed ones: importing makes you match) and every module's on/off state.
function ns.Profile_Collect(db, modules, version)
	local payload = { v = ns.PROFILE_VERSION, from = version, enabled = {}, settings = {} }
	for _, module in ipairs(modules) do
		if not module.alwaysOn then
			payload.enabled[module.key] = EnabledIn(db, module)
		end
		local mdb = db[module.key]
		if type(mdb) == "table" then
			local out, any = {}, false
			for path, t in pairs(ns.Profile_Schema(module)) do
				local map = path:match("^(.+)%.%*$")
				if map then
					local values = ns.Profile_Get(mdb, map)
					if type(values) == "table" then
						for k, v in pairs(values) do
							if ValidMapKey(k) and type(v) == t then
								out[map .. "." .. k] = v
								any = true
							end
						end
					end
				else
					local v = ns.Profile_Get(mdb, path)
					if type(v) == t then
						out[path] = v
						any = true
					end
				end
			end
			if any then
				payload.settings[module.key] = out
			end
		end
	end
	return payload
end

local function OptionFor(module, path)
	for _, spec in ipairs(module.options or {}) do
		if spec.key == path then
			return spec
		end
	end
	return nil
end

-- The schema type for an imported path, or nil.
local function TypeFor(schema, path)
	if type(path) ~= "string" or path:find("*", 1, true) then
		return nil
	end
	if schema[path] then
		return schema[path]
	end
	local map, k = path:match("^(.+)%.([^.]+)$")
	if map and schema[map .. ".*"] and ValidMapKey(k) then
		return schema[map .. ".*"]
	end
	return nil
end

local function InChoices(spec, value)
	local choices = spec.choices
	if type(choices) == "function" then
		local ok, list = pcall(choices)
		if not ok then
			return false
		end
		choices = list
	end
	if type(choices) ~= "table" then
		return false
	end
	for _, choice in ipairs(choices) do
		if type(choice) == "table" and choice.value == value then
			return true
		end
	end
	return false
end

-- The value as it may be written, or nil when it doesn't fit.
local function CheckValue(module, path, t, value)
	if type(value) ~= t then
		return nil
	end
	if t == "number" then
		if value ~= value or value == math.huge or value == -math.huge then
			return nil
		end
	elseif t == "string" then
		if #value > ns.PROFILE_MAX_STRING or value:find("|", 1, true) then
			return nil
		end
	end
	local spec = OptionFor(module, path)
	if spec then
		if spec.type == "slider" and t == "number" then
			if type(spec.min) == "number" and value < spec.min then
				value = spec.min
			end
			if type(spec.max) == "number" and value > spec.max then
				value = spec.max
			end
		elseif spec.type == "dropdown" and not InChoices(spec, value) then
			return nil
		end
	end
	return value
end

local function SortRows(rows)
	table.sort(rows, function(a, b)
		return a.path < b.path
	end)
end

-- result = { groups = { { key, name, rows = { { path, label, old, new } } } }, changes = n, skipped = n }, or nil, err.
-- The module on/off group (key "_enabled") comes first, then modules in registration order. Only values that
-- differ from db are rows.
function ns.Profile_Check(payload, modules, db)
	if type(payload) ~= "table" or type(payload.v) ~= "number" or payload.v < 1 then
		return nil, ERR_NOT
	end
	if payload.v > ns.PROFILE_VERSION then
		return nil, ERR_NEWER
	end
	local byKey = {}
	for _, module in ipairs(modules) do
		byKey[module.key] = module
	end
	local read, skipped, changes = 0, 0, 0
	local function Budget()
		if read >= ns.PROFILE_MAX_ENTRIES then
			return false
		end
		read = read + 1
		return true
	end

	local groups = {}
	local enabledRows = {}
	if type(payload.enabled) == "table" then
		for key, on in pairs(payload.enabled) do
			if not Budget() then
				break
			end
			local module = type(key) == "string" and byKey[key]
			if module and not module.alwaysOn and type(on) == "boolean" then
				if EnabledIn(db, module) ~= on then
					enabledRows[#enabledRows + 1] = { path = key, label = module.name, old = EnabledIn(db, module),
						new = on }
				end
			else
				skipped = skipped + 1
			end
		end
	end
	if #enabledRows > 0 then
		SortRows(enabledRows)
		groups[1] = { key = ENABLED, name = "Modules on/off", rows = enabledRows }
		changes = changes + #enabledRows
	end

	local settings = type(payload.settings) == "table" and payload.settings or {}
	local rowsByModule = {}
	for key, values in pairs(settings) do
		if read >= ns.PROFILE_MAX_ENTRIES then
			break
		end
		local module = type(key) == "string" and byKey[key]
		if type(values) ~= "table" then
			if Budget() then
				skipped = skipped + 1
			end
		elseif not module then
			for _ in pairs(values) do
				if not Budget() then
					break
				end
				skipped = skipped + 1
			end
		else
			local schema = ns.Profile_Schema(module)
			local mdb = type(db[module.key]) == "table" and db[module.key] or {}
			local rows = {}
			for path, value in pairs(values) do
				if not Budget() then
					break
				end
				local t = TypeFor(schema, path)
				local checked = t and CheckValue(module, path, t, value)
				if checked == nil then
					skipped = skipped + 1
				else
					local old = ns.Profile_Get(mdb, path)
					if old ~= checked then
						local spec = OptionFor(module, path)
						rows[#rows + 1] = { path = path, label = spec and type(spec.label) == "string" and spec.label
							or path, old = old, new = checked }
					end
				end
			end
			if #rows > 0 then
				SortRows(rows)
				rowsByModule[module.key] = rows
				changes = changes + #rows
			end
		end
	end
	for _, module in ipairs(modules) do
		local rows = rowsByModule[module.key]
		if rows then
			groups[#groups + 1] = { key = module.key, name = module.name, rows = rows }
		end
	end
	return { groups = groups, changes = changes, skipped = skipped }
end

-- Writes the rows of the chosen groups (chosen[groupKey] = true). Returns how many values were written.
function ns.Profile_Apply(db, result, chosen)
	local written = 0
	for _, group in ipairs(result.groups) do
		if chosen[group.key] then
			for _, row in ipairs(group.rows) do
				if group.key == ENABLED then
					db.enabled[row.path] = row.new
				else
					if type(db[group.key]) ~= "table" then
						db[group.key] = {}
					end
					ns.Profile_Set(db[group.key], row.path, row.new)
				end
				written = written + 1
			end
		end
	end
	return written
end

-- codec = { encode = function(payload) -> string, decode = function(string) -> table }; both may raise.
function ns.Profile_Encode(payload, codec)
	local ok, body = pcall(codec.encode, payload)
	if not ok or type(body) ~= "string" or body == "" then
		return nil, "Couldn't build the string" .. (ok and "." or (": " .. tostring(body)))
	end
	return ns.PROFILE_PREFIX .. ns.PROFILE_VERSION .. ":" .. body
end

function ns.Profile_Decode(text, codec)
	if type(text) ~= "string" then
		return nil, ERR_EMPTY
	end
	-- Pasted from Discord or a whisper: code fences, spaces and line breaks.
	text = text:gsub("`", ""):gsub("%s+", "")
	if text == "" then
		return nil, ERR_EMPTY
	end
	if #text > ns.PROFILE_MAX_TEXT then
		return nil, ERR_LONG
	end
	local n, body = text:match("^" .. ns.PROFILE_PREFIX .. "(%d+):(.+)$")
	n = tonumber(n)
	if not n or n < 1 then
		return nil, ERR_NOT
	end
	if n > ns.PROFILE_VERSION then
		return nil, ERR_NEWER
	end
	local ok, payload = pcall(codec.decode, body)
	if not ok or type(payload) ~= "table" then
		return nil, ERR_DAMAGED
	end
	return payload
end

function ns.Profile_ValueText(v)
	if type(v) == "boolean" then
		return v and "on" or "off"
	elseif type(v) == "number" then
		if v == math.floor(v) then
			return ("%d"):format(v)
		end
		return (("%.2f"):format(v):gsub("0+$", ""):gsub("%.$", ""))
	elseif type(v) == "string" then
		return "\"" .. v .. "\""
	elseif v == nil then
		return "(not set)"
	end
	return tostring(v)
end
