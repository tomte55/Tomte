local addonName, ns = ...

-- First-run presets: which modules a new user starts with. Pure (no WoW API), unit-tested. The window is
-- Panel/Setup.lua. Base modules are in every preset: cheap, quiet, and the class ones only run for their class.
-- A module that isn't in a preset's list is switched off by it, except the ones in SETUP_UNTOUCHED (left as they are
-- unless the preset lists them); one added in a later Tomte version follows its own enabledByDefault until the user
-- runs /tomte setup again.

ns.SETUP_BASE = { "minimap", "vendor", "dura", "hunter", "pet", "rogue" }

-- A preset (Everything too) leaves these as the player has them unless it lists them in `on`: switching someone's
-- whisper toasts or group alerts off is a surprise, not a preset.
ns.SETUP_UNTOUCHED = { "whispers", "mentions", "friends", "alerts" }

ns.SETUP_PRESETS = {
	{ key = "minimal", name = "Minimal", text = "Just the helpers, nothing pops up.",
		on = { "way", "mount", "tp", "gear" } },
	{ key = "collector", name = "Collector", text = "Mounts, pets, achievements, holidays and the places to get them.",
		on = { "way", "mount", "tp", "flight", "collect", "ach", "pets", "wq", "moments", "next", "recent", "events",
			"delves" } },
	{ key = "crafter", name = "Crafter", text = "Professions, gathering, alts, gold and trade chat.",
		on = { "way", "mount", "tp", "gear", "alts", "value", "weekly", "next", "recent", "gather", "fishing", "wgq",
			"tradefilter", "chattabs" } },
	{ key = "social", name = "Social", text = "Whispers, mentions, friends, group alerts and chat.",
		on = { "way", "mount", "tp", "recent", "whispers", "mentions", "friends", "alerts", "share", "tradefilter",
			"chattabs", "chattags", "chatcopy" } },
	{ key = "everything", name = "Everything", text = "All of Tomte, as it comes.", all = true },
}

local function UntouchedSet()
	local set = {}
	for _, k in ipairs(ns.SETUP_UNTOUCHED) do
		set[k] = true
	end
	return set
end

function ns.Setup_Preset(key)
	for _, preset in ipairs(ns.SETUP_PRESETS) do
		if preset.key == key then
			return preset
		end
	end
	return nil
end

-- { clear = true, keep = set } for Everything (every module back to its default, except the untouched ones), else
-- { enabled = { [key] = bool } } for every module the preset decides (untouched ones only when it lists them).
function ns.Setup_Plan(key, modules)
	local preset = ns.Setup_Preset(key)
	if not preset then
		return nil, "unknown preset"
	end
	local untouched = UntouchedSet()
	if preset.all then
		return { clear = true, keep = untouched }
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
		if not module.alwaysOn and (on[module.key] or not untouched[module.key]) then
			enabled[module.key] = on[module.key] == true
		end
	end
	return { enabled = enabled }
end

-- Whether the plan decides module at all.
local function Touches(plan, module)
	if plan.clear then
		return not plan.keep[module.key]
	end
	return plan.enabled[module.key] ~= nil
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
		if not module.alwaysOn and Touches(plan, module) and Wants(plan, module) then
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
		if not module.alwaysOn and Touches(plan, module) and ns.ModuleEnabled(module) ~= Wants(plan, module) then
			return false
		end
	end
	return true
end

-- Writes the choices into db.enabled in place (the panel holds a reference), then starts and stops modules.
function ns.Setup_Apply(db, plan, modules)
	if plan.clear then
		for k in pairs(db.enabled) do
			if not plan.keep[k] then
				db.enabled[k] = nil
			end
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
