local addonName, ns = ...

-- Other addons: a settings page listing every addon a module names in its uses / conflicts / replaces, with whether
-- it's loaded here. Rows and their text in AddonsData.lua; drawn as status rows by Options.lua. Nothing to set.

local UI = ns.UI

local function Loaded(name)
	return C_AddOns.IsAddOnLoaded(name) and true or false
end

local function Exists(name)
	return C_AddOns.DoesAddOnExist(name) and true or false
end

local function Active(module)
	return module.active
end

-- One status row per addon. Addons don't load or unload without a reload, so the rows are built once.
local function Row(kind, row)
	return {
		type = "status",
		label = function()
			return row.addon .. "  " .. UI.Wrap(ns.Addons_ModuleNames(row), "textFaint")
		end,
		status = function()
			return ns.Addons_Status(kind, row, Active)
		end,
		shown = kind == "replaces" and function()
			return row.state == "loaded" -- only worth a word while both run
		end or nil,
		tooltip = ns.Addons_Tooltip(kind, row),
	}
end

local module
module = ns.RegisterModule({
	key = "addons",
	name = "Other addons",
	category = "tomte",
	icon = 136243, -- trade_engineering
	summary = "Addons that clash with Tomte, work with it, or do what Tomte already does.",
	description = "Every addon a Tomte module works with, clashes with or can stand in for, and whether you have it. "
		.. "Hover a row to see which module cares and why.",
	alwaysOn = true,
	options = {},
	init = function()
		local rows = ns.Addons_Rows(ns.modules, Loaded, Exists)
		for _, kind in ipairs(ns.ADDONS_KINDS) do
			module.options[#module.options + 1] = { type = "header", label = kind.title }
			for _, row in ipairs(rows[kind.key]) do
				module.options[#module.options + 1] = Row(kind.key, row)
			end
		end
	end,
})
