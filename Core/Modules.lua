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

ns.homeByKey = {} -- [entry key] = home entry

function ns.RegisterModule(module)
	assert(module.key and not ns.modulesByKey[module.key], "module key missing or already registered")
	module.active = false
	ns.modules[#ns.modules + 1] = module
	ns.modulesByKey[module.key] = module
	for _, entry in ipairs(module.home or {}) do
		assert(entry.key and not ns.homeByKey[entry.key], "home entry key missing or already registered")
		entry.module = module
		ns.homeByKey[entry.key] = entry
	end
	return module
end

-- Home entries (module.home): kind "page" (a page in the Tomte window), "map" (opens a world map tab) or "quick"
-- (an action button). An entry shows while its module is active and its optional shown() is true.
-- A page entry may have pill() -> n: a count on its rail row (same contract as a quick action's count: cheap,
-- existing state only, called through ns.HomeCall); shown above 0 while "Counts on the rail" is on, pillTip says
-- what it counts in the row's tooltip.
function ns.HomeEntryVisible(entry)
	return entry.module.active and (not entry.shown or entry.shown() == true)
end

-- "Around you shows" (Tomte window settings): an "around" entry the user unticked stays off Home.
local function AroundHidden(entry)
	local window = ns.db and ns.db.window
	local around = window and window.around
	return type(around) == "table" and around[entry.key] == false
end

-- A rail pill's text: "" at 0 (or no count), "99+" above two digits.
function ns.Home_PillText(n)
	if type(n) ~= "number" or n < 1 then
		return ""
	end
	n = math.floor(n)
	return n > 99 and "99+" or tostring(n)
end

-- Sorted by entry.order (lowest first, default 100), then registration order.
function ns.HomeEntries(kind)
	local list, index = {}, {}
	for _, module in ipairs(ns.modules) do
		for _, entry in ipairs(module.home or {}) do
			if entry.kind == kind and ns.HomeEntryVisible(entry) and not (kind == "around" and AroundHidden(entry)) then
				list[#list + 1] = entry
				index[entry] = #list
			end
		end
	end
	table.sort(list, function(a, b)
		local x, y = a.order or 100, b.order or 100
		if x ~= y then
			return x < y
		end
		return index[a] < index[b]
	end)
	return list
end

-- The module's page entries (for the settings page's "Open ..." buttons), visible or not.
function ns.ModulePages(module)
	local list = {}
	for _, entry in ipairs(module.home or {}) do
		if entry.kind == "page" then
			list[#list + 1] = entry
		end
	end
	return list
end

-- Lines for the settings header from module.uses / module.conflicts ({ addon, why }). isLoaded(addon) -> bool.
-- ok: a used addon is loaded, or a conflicting one isn't.
function ns.ModuleDependencies(module, isLoaded)
	local lines = {}
	for _, dep in ipairs(module.uses or {}) do
		local loaded = isLoaded(dep.addon)
		lines[#lines + 1] = {
			ok = loaded,
			text = ("Uses %s: %s"):format(dep.addon, loaded and dep.why or ("not loaded, " .. (dep.without or dep.why))),
		}
	end
	for _, dep in ipairs(module.conflicts or {}) do
		local loaded = isLoaded(dep.addon)
		lines[#lines + 1] = {
			ok = not loaded,
			text = ("Conflicts with %s: %s"):format(dep.addon, dep.why),
		}
	end
	return lines
end

-- The user's choice (TomteDB.enabled), or the module's default when they never toggled it.
function ns.ModuleEnabled(module)
	if module.alwaysOn then
		return true
	end
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

-- Where the Tomte window reopens. last = { view = "home" | "page" | "settings", page = entry key, at = server time }
-- (saved when it closes); within `seconds` of closing it reopens there, otherwise on Home. A page that's no longer
-- available (pageOk(key) false) also means Home. Returns view, page key.
function ns.PanelResume(last, now, seconds, pageOk)
	if not last or not last.at or seconds <= 0 or now - last.at > seconds then
		return "home", nil
	end
	if last.view == "page" then
		if last.page and pageOk(last.page) then
			return "page", last.page
		end
		return "home", nil
	end
	return last.view == "settings" and "settings" or "home", nil
end
