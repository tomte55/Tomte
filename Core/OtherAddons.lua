local addonName, ns = ...

-- Other addons: what another addon is doing right now, so a module doing the same job can step aside or line up
-- with it. Everything is read at call time and guarded: the other addon may be missing, older or newer. EllesmereUI and
-- MelloUI each have a section below.
-- EllesmereUI is a suite of separate addons (EllesmereUIChat, EllesmereUIMinimap, ...) sharing one saved table,
-- EllesmereUIDB; a part that isn't loaded does nothing, whatever its settings say.

local IsAddOnLoaded = C_AddOns.IsAddOnLoaded

-- True while that EllesmereUI part (e.g. "Chat" for EllesmereUIChat) is loaded.
function ns.Ellesmere_Loaded(part)
	return IsAddOnLoaded("EllesmereUI" .. part) == true
end

-- One of EllesmereUI's on/off settings in EllesmereUIDB, read the way EllesmereUI reads it: unset means on.
-- section: a feature's own table in EllesmereUIDB (its "enabled" key), or nil for a top-level key.
local function EllesmereSwitch(section, key)
	local saved = rawget(_G, "EllesmereUIDB")
	if type(saved) ~= "table" then
		return true
	end
	if section then
		saved = saved[section]
		if type(saved) ~= "table" then
			return true
		end
	end
	return saved[key] ~= false
end

-- EllesmereUI Quality of Life repairs and sells grey items at every vendor (both on unless turned off there).
function ns.Ellesmere_VendorRepairs()
	return ns.Ellesmere_Loaded("QoL") and EllesmereSwitch(nil, "autoRepair")
end

function ns.Ellesmere_VendorSellsJunk()
	return ns.Ellesmere_Loaded("QoL") and EllesmereSwitch(nil, "autoSellJunk")
end

-- EllesmereUI Forever Essentials' Flight Timer bar (Forever only, on unless turned off there).
function ns.Ellesmere_FlightTimer()
	return ns.Ellesmere_Loaded("ForeverEssentials") and ns.FOREVER and EllesmereSwitch("flightTimer", "enabled")
end

-- MelloUI --------------------------------------------------------------------------------------------------------

-- MelloUI is one addon (the global MelloUI) with optional parts (MelloUI_Chat, MelloUI_Route, ...). Every feature is a
-- module in its own registry, switched on or off in /mello (some through its UI Modifications page), so a loaded part
-- can still be off. Read through its own functions: GetModule(name) (module.isEnabled: running now, once MelloUI has
-- started its modules), IsModuleEnabled(name) (the saved switch, before that) and GetModuleDB(name) (its settings with
-- its defaults filled in). pcall: these are MelloUI's internals and could change or error.

local function Mello()
	local mello = rawget(_G, "MelloUI")
	if type(mello) == "table" and type(rawget(mello, "GetModule")) == "function" then
		return mello
	end
	return nil
end

-- True while MelloUI's module `name` (e.g. "Vendor", "Chat", "BagWindow") is on.
function ns.Mello_On(name)
	local mello = Mello()
	if not mello then
		return false
	end
	if rawget(mello, "initialized") then
		local ok, module = pcall(mello.GetModule, mello, name)
		return ok and type(module) == "table" and module.isEnabled == true
	end
	local ok, on = pcall(mello.IsModuleEnabled, mello, name)
	return ok and on == true
end

-- True while MelloUI's module `name` is on with its setting `key` on (e.g. "Vendor", "autoRepair"). Read the way
-- GetModuleDB fills it in (MelloUIDB.modules[name], else the module's default), without its walk over every default:
-- the nameplates ask this on each update.
function ns.Mello_Does(name, key)
	if not ns.Mello_On(name) then
		return false
	end
	local mello = Mello()
	local saved = type(rawget(mello, "db")) == "table" and mello.db.modules
	saved = type(saved) == "table" and saved[name]
	local value = type(saved) == "table" and saved[key]
	if value == nil then
		local ok, module = pcall(mello.GetModule, mello, name)
		value = ok and type(module) == "table" and type(module.defaults) == "table" and module.defaults[key]
	end
	return value == true
end

-- A module's blocked() and its other checks read MelloUI live, so a switch flipped in /mello starts or stops the
-- Tomte module that does the same job at once. MelloUI's bus calls back inside its own pcall: the refresh runs on
-- the next frame, once for a burst (a profile load fires every setting).
local refreshPending = false

local function RefreshModules()
	refreshPending = false
	if not ns.db then
		return
	end
	for _, module in ipairs(ns.modules) do
		ns.RefreshModule(module)
	end
end

local function QueueRefresh()
	if not refreshPending then
		refreshPending = true
		C_Timer.After(0, RefreshModules)
	end
end

local melloWatch = CreateFrame("Frame")
melloWatch:RegisterEvent("PLAYER_LOGIN")
melloWatch:SetScript("OnEvent", function(self)
	self:UnregisterEvent("PLAYER_LOGIN")
	local mello = Mello()
	if not (mello and type(rawget(mello, "On")) == "function") then
		return
	end
	pcall(mello.On, mello, "module", QueueRefresh, melloWatch)
	pcall(mello.On, mello, "setting", QueueRefresh, melloWatch)
	-- MelloUI starts its modules around login, maybe after Tomte read the saved switches.
	QueueRefresh()
end)

-- Minimap shape --------------------------------------------------------------------------------------------------

-- EllesmereUI Minimap's shapes: the round ones; "square" and "rectangular" draw square corners.
local ELLESMERE_ROUND = { circle = true, textured_circle = true }

-- The minimap's shape in the LibDBIcon convention ("ROUND", "SQUARE", "CORNER-TOPLEFT", ...): GetMinimapShape when a
-- minimap addon defines it, else EllesmereUI Minimap's own shape (it reshapes the map without defining that), else
-- Blizzard's round map. pcall: EllesmereUI's function is internal and could change or error.
function ns.MinimapShape()
	local get = rawget(_G, "GetMinimapShape")
	if type(get) == "function" then
		local ok, shape = pcall(get)
		if ok and type(shape) == "string" then
			return shape
		end
	end
	if ns.Ellesmere_Loaded("Minimap") then
		local registry = rawget(_G, "EllesmereUI")
		registry = type(registry) == "table" and registry._ModuleNS
		local module = type(registry) == "table" and registry.EllesmereUIMinimap
		local shapeOf = type(module) == "table" and module.MinimapShape
		if type(shapeOf) == "function" then
			local ok, shape = pcall(shapeOf)
			if ok and type(shape) == "string" then
				return ELLESMERE_ROUND[shape] and "ROUND" or "SQUARE"
			end
		end
		return "SQUARE" -- EllesmereUI Minimap's default
	end
	return "ROUND"
end
