local addonName, ns = ...

-- First-run presets: which modules a new user starts with. Pure (no WoW API), unit-tested. The window is
-- Panel/Setup.lua. Base modules are in every preset: cheap, quiet, and the class ones only run for their class.
-- A module that isn't in a preset's list is switched off by it; one added in a later Tomte version follows its own
-- enabledByDefault until the user runs /tomte setup again.

ns.SETUP_BASE = { "minimap", "vendor", "dura", "hunter", "pet", "rogue" }

ns.SETUP_PRESETS = {
	{ key = "minimal", name = "Minimal", text = "Just the helpers, nothing pops up.",
		on = { "way", "mount", "tp", "gear" } },
	{ key = "collector", name = "Collector", text = "Mounts, pets, achievements, holidays and the places to get them.",
		on = { "way", "mount", "tp", "flight", "collect", "ach", "pets", "wq", "moments", "next", "recent", "events",
			"delves" } },
	{ key = "crafter", name = "Crafter", text = "Professions, gathering, alts and gold.",
		on = { "way", "mount", "tp", "gear", "alts", "value", "weekly", "next", "recent", "gather", "fishing" } },
	{ key = "everything", name = "Everything", text = "All of Tomte, as it comes.", all = true },
}

function ns.Setup_Preset(key)
	for _, preset in ipairs(ns.SETUP_PRESETS) do
		if preset.key == key then
			return preset
		end
	end
	return nil
end

-- { clear = true } for Everything (every module back to its default), else { enabled = { [key] = bool } } for every
-- module that has a choice.
function ns.Setup_Plan(key, modules)
	local preset = ns.Setup_Preset(key)
	if not preset then
		return nil, "unknown preset"
	end
	if preset.all then
		return { clear = true }
	end
	local on = {}
	for _, k in ipairs(ns.SETUP_BASE) do
		on[k] = true
	end
	for _, k in ipairs(preset.on) do
		on[k] = true
	end
	local enabled = {}
	for _, module in ipairs(modules) do
		if not module.alwaysOn then
			enabled[module.key] = on[module.key] == true
		end
	end
	return { enabled = enabled }
end

-- Whether the plan wants module on.
local function Wants(plan, module)
	if plan.clear then
		return module.enabledByDefault == true
	end
	return plan.enabled[module.key] == true
end

function ns.Setup_OnNames(key, modules)
	local plan = ns.Setup_Plan(key, modules)
	local names = {}
	if not plan then
		return names
	end
	for _, module in ipairs(modules) do
		if not module.alwaysOn and Wants(plan, module) then
			names[#names + 1] = module.name
		end
	end
	return names
end

function ns.Setup_Matches(key, modules)
	local plan = ns.Setup_Plan(key, modules)
	if not plan then
		return false
	end
	for _, module in ipairs(modules) do
		if not module.alwaysOn and ns.ModuleEnabled(module) ~= Wants(plan, module) then
			return false
		end
	end
	return true
end

-- Writes the choices into db.enabled in place (the panel holds a reference), then starts and stops modules.
function ns.Setup_Apply(db, plan, modules)
	if plan.clear then
		for k in pairs(db.enabled) do
			db.enabled[k] = nil
		end
	else
		for k, v in pairs(plan.enabled) do
			db.enabled[k] = v
		end
	end
	for _, module in ipairs(modules) do
		ns.RefreshModule(module)
	end
end

function ns.Setup_MarkFresh(db)
	db.setup = { state = "pending" }
end

-- Settings migration 2 (Core/Migrations.lua): saved variables from before the picker existed are an existing user's. They
-- never see the picker by surprise (only through /tomte setup) and get no message about it.
function ns.Setup_Migrate(db)
	if type(db.setup) ~= "table" then
		db.setup = {}
	end
	if db.setup.state == nil then
		db.setup.state = "done"
	end
end
