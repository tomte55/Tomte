local addonName, ns = ...

-- Other addons page: pure logic (no WoW API calls; unit-tested in tests/test_addons.lua). Gathers every module's
-- uses / conflicts / replaces ({ addon, why, without }) into one row per addon, and the status text each row shows.
-- The page is Panel/Addons.lua.

-- The cards, in page order. key: the module field read; title: the card's header.
ns.ADDONS_KINDS = {
	{ key = "conflicts", title = "Clashes with Tomte" },
	{ key = "uses", title = "Works with Tomte" },
	{ key = "replaces", title = "Tomte can replace" },
}

-- Addon state order inside a card: what needs a look first.
local STATE_ORDER = { loaded = 1, off = 2, missing = 3 }

-- "loaded", "off" (installed but not loaded) or "missing". loaded(addon) and exists(addon) -> bool.
function ns.Addons_State(addon, loaded, exists)
	if loaded(addon) then
		return "loaded"
	end
	return exists(addon) and "off" or "missing"
end

-- { [kind key] = rows } with rows = { { addon, state, modules = { { module, why, without } } } }: one row per addon
-- (several modules naming it share it, in registration order), loaded first, then by name.
function ns.Addons_Rows(modules, loaded, exists)
	local result = {}
	for _, kind in ipairs(ns.ADDONS_KINDS) do
		local rows, byAddon = {}, {}
		for _, module in ipairs(modules) do
			for _, dep in ipairs(module[kind.key] or {}) do
				local row = byAddon[dep.addon]
				if not row then
					row = { addon = dep.addon, state = ns.Addons_State(dep.addon, loaded, exists), modules = {} }
					byAddon[dep.addon] = row
					rows[#rows + 1] = row
				end
				row.modules[#row.modules + 1] = { module = module, why = dep.why, without = dep.without }
			end
		end
		table.sort(rows, function(a, b)
			if a.state ~= b.state then
				return STATE_ORDER[a.state] < STATE_ORDER[b.state]
			end
			return a.addon:lower() < b.addon:lower()
		end)
		result[kind.key] = rows
	end
	return result
end

-- The modules' names, comma separated.
function ns.Addons_ModuleNames(row)
	local names = {}
	for _, use in ipairs(row.modules) do
		names[#names + 1] = use.module.name
	end
	return table.concat(names, ", ")
end

-- The status on the right of a row: text, color role. active(module) -> bool: the module is running.
function ns.Addons_Status(kind, row, active)
	local state = row.state
	if kind == "conflicts" then
		if state == "loaded" then
			return "Clashes now", "danger"
		end
		return state == "off" and "Installed, off" or "Not installed", "textFaint"
	elseif kind == "uses" then
		if state == "loaded" then
			return "Loaded", "success"
		end
		return state == "off" and "Installed, off" or "Not installed", "textFaint"
	end
	if state ~= "loaded" then
		return state == "off" and "Installed, off" or "Not installed", "textFaint"
	end
	for _, use in ipairs(row.modules) do
		if active(use.module) then
			return "You can turn it off", "warning"
		end
	end
	return "Tomte's version is off", "textMuted"
end

-- The row's tooltip: one line per module saying what the addon means for it.
function ns.Addons_Tooltip(kind, row)
	local lines = {}
	for _, use in ipairs(row.modules) do
		local text = use.module.name .. ": " .. use.why
		if kind == "uses" and use.without then
			text = text .. ". Without it: " .. use.without
		end
		lines[#lines + 1] = text
	end
	if kind == "replaces" then
		lines[#lines + 1] = "Running both does the same job twice."
	end
	return table.concat(lines, "\n")
end
