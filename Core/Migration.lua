local addonName, ns = ...

-- Hand-over from the old FlightTimer addon. SavedVariables are per-addon files, so FlightTimerDB only
-- exists while FlightTimer itself is loaded (the TOC's OptionalDeps makes it load first). While it is
-- loaded it stays in charge: Tomte copies its data on load and again on PLAYER_LOGOUT (which fires just
-- before SavedVariables are written, also on /reload), and the flight module stays blocked.
-- Only Migration_Run touches the WoW API; the rest is unit-tested.

-- FlightTimer's own runtime state: its in-progress flight and music-volume backup.
local RUNTIME_KEYS = { current = true, musicVolumeBackup = true }

local function DeepCopy(value)
	if type(value) ~= "table" then
		return value
	end
	local copy = {}
	for k, v in pairs(value) do
		copy[k] = DeepCopy(v)
	end
	return copy
end

function ns.CopyFlightData(src)
	local copy = {}
	for k, v in pairs(src) do
		if not RUNTIME_KEYS[k] then
			copy[k] = DeepCopy(v)
		end
	end
	return copy
end

local flightTimerLoaded = false

function ns.FlightTimerLoaded()
	return flightTimerLoaded
end

function ns.Migration_Run(db)
	flightTimerLoaded = C_AddOns.IsAddOnLoaded("FlightTimer") and true or false
	if not (flightTimerLoaded and type(FlightTimerDB) == "table") then
		return
	end
	db.flight = ns.CopyFlightData(FlightTimerDB)
	db.flightImported = true
	ns.Print("flight data copied from FlightTimer. Disable FlightTimer and /reload to switch over.")
	local logout = CreateFrame("Frame")
	logout:RegisterEvent("PLAYER_LOGOUT")
	logout:SetScript("OnEvent", function()
		if type(FlightTimerDB) == "table" then
			db.flight = ns.CopyFlightData(FlightTimerDB)
		end
	end)
end
