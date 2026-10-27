local addonName, ns = ...

-- Module registry. Pure logic: no WoW API calls (unit-tested with plain Lua). Errors from a module's
-- toggle/init go to ns.errorHandler (Core.lua points it at geterrorhandler(), so BugSack shows them).

ns.modules = {} -- in registration order
ns.modulesByKey = {}

-- Adds what's missing from src (the defaults) to dst. A saved value whose shape changed is replaced: a table where
-- the default is a table now, the default where a table was saved but the default is a plain value now.
function ns.MergeDefaults(src, dst)
	for k, v in pairs(src) do
		if type(v) == "table" then
			if type(dst[k]) ~= "table" then
				dst[k] = {}
			end
			ns.MergeDefaults(v, dst[k])
		elseif dst[k] == nil or type(dst[k]) == "table" then
			dst[k] = v
		end
	end
	return dst
end

-- Settings schema: db.schema = how many of the ordered migrations (Migrations.lua) have run on these saved variables.
-- Each runs once, in order, before defaults are merged; a fresh install runs them all on an empty table, so a
-- migration must cope with missing keys. One that errors stops the run (reported, retried next login).
function ns.RunMigrations(db, migrations)
	local done = type(db.schema) == "number" and db.schema or 0
	for i = done + 1, #migrations do
		local ok = xpcall(function()
			migrations[i](db)
		end, function(err)
			return ns.errorHandler(err)
		end)
		if not ok then
			return
		end
		db.schema = i
	end
end

-- Reset to defaults ---------------------------------------------------------------------------------------
-- A module's db mixes settings with what it collected (history, caches, alt snapshots, flight times, tame log)
-- and lists the user built (favorites, pins, hidden entries). A reset only touches keys in module.defaults, and
-- of those keeps every collection (a default that is an empty table, or tables of only empty tables) and the
-- keys in module.keep (data whose default isn't a collection). Keys not in the defaults are never touched.

-- Also what a shareable setting is (Core/Profile.lua): export, import and reset agree.
function ns.IsCollection(v)
	if type(v) ~= "table" then
		return false
	end
	for _, child in pairs(v) do
		if not ns.IsCollection(child) then
			return false
		end
	end
	return true
end

function ns.ResetModuleSettings(module)
	local defaults, db = module.defaults, module.db
	if not (defaults and db) then
		return
	end
	local keep = {}
	for _, key in ipairs(module.keep or {}) do
		keep[key] = true
	end
	for key, value in pairs(defaults) do
		if not keep[key] and not ns.IsCollection(value) then
			db[key] = nil
		end
	end
	ns.MergeDefaults(defaults, db) -- in place: modules keep their reference to module.db
end

-- Every module's settings (as above), which modules are on (enabled), the window's place and layout (panel) and the
-- social toast's position (toast). coreDefaults: Core.lua's. Every other top-level key is kept: cinematic (the
-- engine's music volume and pitch limit backups), setup, bugs, profileBackup, schema and the session data.
function ns.ResetAllSettings(db, coreDefaults)
	for _, module in ipairs(ns.modules) do
		ns.ResetModuleSettings(module)
	end
	db.enabled, db.panel, db.toast = {}, {}, {}
	ns.MergeDefaults(coreDefaults, db)
end

-- A dropdown's value when it's one of choices ({ value, text }), otherwise the default.
function ns.ChoiceOrDefault(value, choices, default)
	for _, choice in ipairs(choices) do
		if choice.value == value then
			return value
		end
	end
	return default
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

-- Home entries (module.home). Every entry has kind, a unique key, optional order (sort key, default 100) and optional
-- shown(); it shows while its module is active and shown() (if any) is true. By kind (Panel/Home*.lua, Panel/Rail.lua, Panel/Panel.lua):
--   "page"     a page in the Tomte window and a rail row: name, icon or atlas, page = { Create(frame), Refresh(frame) },
--              summary() (rail tooltip), pill() -> n and pillTip (a count on its rail row, shown above 0 while
--              "Counts on the rail" is on; cheap, existing state only)
--   "map"      a rail row that opens a world map tab: name, icon or atlas, summary(), open()
--   "quick"    an action button under the hero: name, count() -> n (shown above 0), open()
--   "around"   a block in Home's "Around you" column: name, icon, title() ("Name: counts"), items(limit) -> rows
--              { icon, text, color, right, rightColor, onEnter, onClick, hint (the default tooltip's click line, when
--              there's no onEnter) }, maxRows, keepEmpty, open(), openText
--              (the heading's tooltip), opensMap (the heading and rows without their own click open the world map
--              before open() runs), progress() (0..1 while something is still being read, a thin line under the
--              heading; nil when done); the user can untick it in the Tomte window settings
--   "section"  a Home section that draws itself: slot ("week", "characters", "next", "recent", "events"; the first
--              entry per slot wins), Create(frame, kit), Refresh(frame) -> wanted height
--   "next"     a Next up source (Modules/NextUp): name, candidates(now), score
-- A module's summary/count/shown/items/...: called through ns.HomeCall, so errors go to BugSack and count as
-- "nothing".
function ns.HomeCall(fn, ...)
	if not fn then
		return nil
	end
	local ok, value = xpcall(fn, function(err)
		return ns.errorHandler(err)
	end, ...)
	if ok then
		return value
	end
	return nil
end

function ns.HomeEntryVisible(entry)
	return entry.module.active and (not entry.shown or ns.HomeCall(entry.shown) == true)
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

-- Sorts entries by entry.order (lowest first, default 100), then by index[entry] (registration order).
local function SortEntries(list, index)
	table.sort(list, function(a, b)
		local x, y = a.order or 100, b.order or 100
		if x ~= y then
			return x < y
		end
		return index[a] < index[b]
	end)
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
	SortEntries(list, index)
	return list
end

-- Every "around" block of every module, on or off, in Home's order: { key, name } for the Tomte window's
-- "Around you shows" switches (Panel/Window.lua).
function ns.Home_AroundChoices()
	local list, index = {}, {}
	for _, module in ipairs(ns.modules) do
		for _, entry in ipairs(module.home or {}) do
			if entry.kind == "around" then
				list[#list + 1] = entry
				index[entry] = #list
			end
		end
	end
	SortEntries(list, index)
	local choices = {}
	for i, entry in ipairs(list) do
		choices[i] = { key = entry.key, name = entry.name }
	end
	return choices
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

-- Lines for the settings header from module.uses / module.conflicts / module.replaces ({ addon, why }).
-- isLoaded(addon) -> bool. ok: a used addon is loaded, or a conflicting or replaced one isn't. addon: its name;
-- conflict: from module.conflicts; overlap: from module.replaces (an addon doing the module's job). A used addon's
-- optional `unneeded()` returning true leaves its line out (something in Tomte does its job now).
function ns.ModuleDependencies(module, isLoaded)
	local lines = {}
	for _, dep in ipairs(module.uses or {}) do
		local loaded = isLoaded(dep.addon)
		if loaded or not (dep.unneeded and dep.unneeded()) then
			lines[#lines + 1] = {
				ok = loaded,
				addon = dep.addon,
				text = ("Uses %s: %s"):format(dep.addon, loaded and dep.why or ("not loaded, " .. (dep.without or dep.why))),
			}
		end
	end
	for _, dep in ipairs(module.conflicts or {}) do
		local loaded = isLoaded(dep.addon)
		lines[#lines + 1] = {
			ok = not loaded,
			addon = dep.addon,
			conflict = true,
			text = ("Conflicts with %s: %s"):format(dep.addon, dep.why),
		}
	end
	for _, dep in ipairs(module.replaces or {}) do
		local loaded = isLoaded(dep.addon)
		lines[#lines + 1] = {
			ok = not loaded,
			addon = dep.addon,
			overlap = true,
			text = ("Does what %s does: %s. You can turn %s off."):format(dep.addon, dep.why, dep.addon),
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

-- The line for a command, key binding or button of a module that isn't running: "Gathering is off. Turn it on in
-- /tomte.", or its blocked reason ("Hunter Pets: Only for hunters.") when it can't run here at all.
function ns.Module_OffText(module, blockedReason)
	local name = module.name or module.key
	if blockedReason then
		return name .. ": " .. blockedReason
	end
	return name .. " is off. Turn it on in /tomte."
end

-- A /tomte command runs while its module is active; cmd.whileOff = true lets it run while off (a status line that
-- reports the off state itself).
function ns.Module_CommandAllowed(module, cmd)
	return module.active == true or (cmd ~= nil and cmd.whileOff == true)
end

local function Call(fn, arg)
	-- Look the handler up on every call: tests and Core.lua replace it.
	xpcall(function()
		fn(arg)
	end, function(err)
		return ns.errorHandler(err)
	end)
end

-- Functions called with a module after it started or stopped (the minimap buttons follow their module).
ns.moduleToggled = {}

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
	for _, fn in ipairs(ns.moduleToggled) do
		Call(fn, module)
	end
end

-- Core.lua has already set ns.db and merged its defaults; the tests call this directly with a bare table, so it
-- sets ns.db and db.enabled itself.
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

-- A live cinematic state some active module still owns (see the engine's music and pitch cleanup).
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
