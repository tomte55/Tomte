local addonName, ns = ...

-- Module registry. Pure logic: no WoW API calls (unit-tested with plain Lua). Errors from a module's
-- toggle/init go to ns.errorHandler (Core.lua points it at geterrorhandler(), so BugSack shows them).

ns.modules = {} -- in registration order
ns.modulesByKey = {}

function ns.MergeDefaults(src, dst)
	for k, v in pairs(src) do
		if type(v) == "table" then
			if type(dst[k]) ~= "table" then
				dst[k] = {}
			end
			ns.MergeDefaults(v, dst[k])
		elseif dst[k] == nil then
			dst[k] = v
		end
	end
	return dst
end

function ns.RegisterModule(module)
	assert(module.key and not ns.modulesByKey[module.key], "module key missing or already registered")
	module.active = false
	ns.modules[#ns.modules + 1] = module
	ns.modulesByKey[module.key] = module
	return module
end

-- The user's choice (TomteDB.enabled), or the module's default when they never toggled it.
function ns.ModuleEnabled(module)
	local saved = ns.db.enabled[module.key]
	if saved == nil then
		return module.enabledByDefault == true
	end
	return saved
end

function ns.ModuleBlockedReason(module)
	if module.blocked then
		return module.blocked()
	end
	return nil
end

function ns.ModuleWanted(module)
	return ns.ModuleEnabled(module) and ns.ModuleBlockedReason(module) == nil
end

local function Call(fn, arg)
	-- Look the handler up on every call: tests and Core.lua replace it.
	xpcall(function()
		fn(arg)
	end, function(err)
		return ns.errorHandler(err)
	end)
end

-- Start or stop the module when its wanted state changed. module.active is set first, so a toggle(true)
-- that errors still counts as active and turning the module off runs its cleanup.
function ns.RefreshModule(module)
	local wanted = ns.ModuleWanted(module)
	if wanted == module.active then
		return
	end
	module.active = wanted
	if module.toggle then
		Call(module.toggle, wanted)
	end
end

function ns.InitModules(db)
	ns.db = db
	db.enabled = db.enabled or {}
	for _, module in ipairs(ns.modules) do
		if type(db[module.key]) ~= "table" then
			db[module.key] = {}
		end
		if module.defaults then
			ns.MergeDefaults(module.defaults, db[module.key])
		end
		module.db = db[module.key]
		if module.init then
			Call(module.init, module.db)
		end
	end
	for _, module in ipairs(ns.modules) do
		ns.RefreshModule(module)
	end
end

function ns.SetModuleEnabled(key, enabled)
	ns.db.enabled[key] = enabled and true or false
	ns.RefreshModule(ns.modulesByKey[key])
end

function ns.ModuleCategories()
	local list, seen = {}, {}
	for _, module in ipairs(ns.modules) do
		if not seen[module.category] then
			seen[module.category] = true
			list[#list + 1] = module.category
		end
	end
	return list
end

-- text must already be lower case; "" matches everything.
function ns.ModuleMatches(module, text)
	if text == "" then
		return true
	end
	return module.name:lower():find(text, 1, true) ~= nil
		or (module.description or ""):lower():find(text, 1, true) ~= nil
end

-- A live cinematic state some active module still owns (see the engine's music cleanup).
function ns.AnyCinematicState()
	for _, module in ipairs(ns.modules) do
		if module.active and module.cinematicState then
			local state = module.cinematicState()
			if state then
				return state
			end
		end
	end
	return nil
end
