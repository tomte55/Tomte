local addonName, ns = ...

-- Performance: the readout, a small line on screen ("58 fps   18 ms   Tomte 0.1%") colored by how Tomte is doing.
-- Moved in Blizzard's Edit Mode (Core/EditMode.lua). Updated every second while it shows. Registered in
-- Performance.lua, which owns its saved position (db.readout).

local REFRESH_SECONDS = 1
local PAD_X, PAD_Y = 10, 5

local UI = ns.UI

local frame, ticker, db
local wanted = false -- the module is on with the readout setting on

local function Update()
	if not frame then
		return
	end
	local game = ns.PerfRead_Game(false)
	local share = ns.Perf_Percent(game.app.recent, game.overall.recent, game.tomte.recent)
	frame.text:SetText(ns.Perf_ReadoutText(game.fps, math.max(game.home or 0, game.world or 0), share))
	UI.SetTextRole(frame.text, (ns.Perf_Verdict(share)))
	frame:SetSize(frame.text:GetStringWidth() + 2 * PAD_X, frame.text:GetStringHeight() + 2 * PAD_Y)
end

local function Build()
	frame = CreateFrame("Frame", nil, UIParent)
	frame:SetFrameStrata("MEDIUM")
	frame:SetClampedToScreen(true)
	UI.Panel(frame, { subtle = true, alpha = 0.9 })
	frame.text = UI.Text(frame, 12, "text", "number")
	frame.text:SetPoint("CENTER")
	frame:Hide()
end

local function Place()
	local pos = db.readout
	frame:ClearAllPoints()
	frame:SetPoint(pos.point, UIParent, pos.relPoint, pos.x, pos.y)
end

local function Show(on)
	if on then
		if not frame then
			Build()
		end
		Place()
		Update()
		frame:Show()
		if not ticker then
			ticker = C_Timer.NewTicker(REFRESH_SECONDS, Update)
		end
	else
		if ticker then
			ticker:Cancel()
			ticker = nil
		end
		if frame then
			frame:Hide()
		end
	end
end

local function Refresh()
	Show(wanted or (db ~= nil and ns.EditMode_Active() and ns.modulesByKey.perf.active))
end

function ns.PerfReadout_Set(moduleDB, on)
	db = moduleDB
	wanted = on
	Refresh()
end

-- Same position as defaults.readout in Performance.lua.
function ns.PerfReadout_Reset()
	local pos = db.readout
	pos.point, pos.relPoint, pos.x, pos.y = "TOPRIGHT", "TOPRIGHT", -220, -8
	if frame then
		Place()
	end
end

ns.EditMode_Register({
	name = "Performance readout",
	frame = function()
		return frame
	end,
	refresh = Refresh,
	saved = function()
		local point, _, relPoint, x, y = frame:GetPoint()
		local pos = db.readout
		pos.point, pos.relPoint, pos.x, pos.y = point, relPoint, x, y
	end,
	module = "perf",
	reset = ns.PerfReadout_Reset,
})
