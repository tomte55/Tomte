-- Run from the AddOns folder: lua Tomte/tests/test_addons.lua
local ns = {}
assert(loadfile("Tomte/Panel/AddonsData.lua"))("Tomte", ns)

local H = dofile("Tomte/tests/harness.lua")
local test, eq = H.test, H.eq

local LOADED = { Auctionator = true, Pawn = true, WaypointUI = true }
local INSTALLED = { Auctionator = true, Pawn = true, WaypointUI = true, Syndicator = true, Angleur = true }
local function loaded(name)
	return LOADED[name] == true
end
local function exists(name)
	return INSTALLED[name] == true
end

local alts = { name = "Alts", uses = {
	{ addon = "Syndicator", why = "item counts", without = "only this character" },
	{ addon = "Auctionator", why = "shopping lists" },
} }
local value = { name = "Gold & value", uses = { { addon = "Auctionator", why = "auction prices" } } }
local gear = { name = "Gear Check", uses = { { addon = "Simulationcraft", why = "the /simc export" } },
	replaces = { { addon = "Pawn", why = "upgrades on tooltips" } } }
local way = { name = "Waypoints", conflicts = { { addon = "WaypointUI", why = "stays off" } } }
local fish = { name = "Fishing", conflicts = { { addon = "Angleur", why = "both bind a key" } } }
local MODULES = { alts, value, gear, way, fish }

test("state: loaded, installed but off, missing", function()
	eq(ns.Addons_State("Auctionator", loaded, exists), "loaded")
	eq(ns.Addons_State("Syndicator", loaded, exists), "off")
	eq(ns.Addons_State("Nope", loaded, exists), "missing")
end)

test("one row per addon, shared by every module naming it", function()
	local rows = ns.Addons_Rows(MODULES, loaded, exists)
	eq(#rows.uses, 3, "Auctionator, Syndicator, Simulationcraft")
	eq(rows.uses[1].addon, "Auctionator", "loaded first")
	eq(#rows.uses[1].modules, 2)
	eq(ns.Addons_ModuleNames(rows.uses[1]), "Alts, Gold & value", "registration order")
	eq(rows.uses[2].addon, "Syndicator", "installed before missing")
	eq(rows.uses[3].addon, "Simulationcraft")
	eq(#rows.conflicts, 2)
	eq(rows.conflicts[1].addon, "WaypointUI")
	eq(#rows.replaces, 1)
end)

test("no declarations: empty cards", function()
	local rows = ns.Addons_Rows({ { name = "X" } }, loaded, exists)
	eq(#rows.uses + #rows.conflicts + #rows.replaces, 0)
end)

test("status per kind", function()
	local function Status(kind, row, active)
		return table.concat({ ns.Addons_Status(kind, row, active) }, "|")
	end
	local rows = ns.Addons_Rows(MODULES, loaded, exists)
	local function on()
		return true
	end
	local function off()
		return false
	end
	eq(Status("conflicts", rows.conflicts[1], on), "Clashes now|danger")
	eq(Status("conflicts", rows.conflicts[2], on), "Installed, off|textFaint")
	eq(Status("uses", rows.uses[1], on), "Loaded|success")
	eq(Status("uses", rows.uses[3], on), "Not installed|textFaint")
	eq(Status("replaces", rows.replaces[1], on), "You can turn it off|warning")
	eq(Status("replaces", rows.replaces[1], off), "Tomte's version is off|textMuted")
end)

test("tooltip: a line per module, what's lost without a used addon", function()
	local rows = ns.Addons_Rows(MODULES, loaded, exists)
	eq(ns.Addons_Tooltip("uses", rows.uses[2]), "Alts: item counts. Without it: only this character")
	eq(ns.Addons_Tooltip("uses", rows.uses[1]), "Alts: shopping lists\nGold & value: auction prices")
	eq(ns.Addons_Tooltip("replaces", rows.replaces[1]),
		"Gear Check: upgrades on tooltips\nRunning both does the same job twice.")
end)

H.done()
