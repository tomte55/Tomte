local addonName, ns = ...

-- Other addons: what another addon is doing right now, so a module doing the same job can step aside or line up
-- with it. Everything is read at call time and guarded: the other addon may be missing, older or newer.
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
