local addonName, ns = ...

-- Performance: the readout, a small line on screen ("58 fps   18 ms   Tomte 0.1%") colored by how Tomte is doing.
-- Hovering it shows more (the numbers, the busiest modules now, the last hitch; lines from Data.lua), a click opens
-- the Performance page. Moved in Blizzard's Edit Mode (Core/EditMode.lua). Updated every second while it shows.
-- Registered in Performance.lua, which owns its saved position (db.readout).

local REFRESH_SECONDS = 1
local PAD_X, PAD_Y = 10, 5

local UI = ns.UI

local frame, ticker, db
local wanted = false -- the module is on with the readout setting on
local prev, rates, sampledAt = {}, {}, nil -- the modules' live rates for the tooltip (Perf_UpdateRates)

local function Sample()
	local now = GetTime()
	if sampledAt then
		ns.Perf_UpdateRates(ns.Perf_Stats(), prev, rates, now - sampledAt)
	else
		ns.Perf_UpdateRates(ns.Perf_Stats(), prev, {}, 1) -- the first sample only sets prev
	end
	sampledAt = now
end

local function ShowTip()
	local game = ns.PerfRead_Game(false)
	local t = game.tomte
	local lines = ns.Perf_ReadoutLines({
		fps = game.fps, home = game.home, world = game.world, peak = t.peak, mem = ns.PerfRead_TomteMemory(),
		now = ns.Perf_Percent(game.app.recent, game.overall.recent, t.recent),
		session = ns.Perf_Percent(game.app.session, game.overall.session, t.session),
		all = ns.Perf_Percent(game.app.recent, game.overall.recent, game.overall.recent),
	}, ns.Perf_ModuleRows(ns.Perf_Stats(), rates, "now"), ns.Perf_Hitches()[1], GetTime())
	GameTooltip:SetOwner(frame, "ANCHOR_BOTTOM")
	GameTooltip:SetText("Tomte performance", UI.Color("heading"))
	for _, line in ipairs(lines) do
		if line.right then
			local lr, lg, lb = UI.RGB("textMuted")
			local rr, rg, rb = UI.RGB(line.role or "text")
			GameTooltip:AddDoubleLine(line.left, line.right, lr, lg, lb, rr, rg, rb)
		else
			UI.TipLine(line.left, line.role or "text")
		end
	end
	GameTooltip:AddLine(" ")
	UI.TipLine("Click for the Performance page.", "textMuted")
	GameTooltip:Show()
end

local function Update()
	if not frame then
		return
	end
	Sample()
	local game = ns.PerfRead_Game(false)
	local share = ns.Perf_Percent(game.app.recent, game.overall.recent, game.tomte.recent)
	frame.text:SetText(ns.Perf_ReadoutText(game.fps, math.max(game.home or 0, game.world or 0), share))
	UI.SetTextRole(frame.text, (ns.Perf_Verdict(share)))
	frame:SetSize(frame.text:GetStringWidth() + 2 * PAD_X, frame.text:GetStringHeight() + 2 * PAD_Y)
	if GameTooltip:IsOwned(frame) then
		ShowTip()
	end
end

local function Build()
	frame = CreateFrame("Frame", nil, UIParent)
	frame:SetFrameStrata("MEDIUM")
	frame:SetClampedToScreen(true)
	UI.Panel(frame, { subtle = true, alpha = 0.55 }) -- see-through like Almost Done's tracker
	frame.text = UI.Text(frame, 12, "text", "number")
	frame.text:SetPoint("CENTER")
	frame:EnableMouse(true)
	frame:SetScript("OnEnter", ShowTip)
	frame:SetScript("OnLeave", GameTooltip_Hide)
	frame:SetScript("OnMouseUp", function(_, button)
		if button == "LeftButton" then
			GameTooltip:Hide()
			ns.Panel_OpenPage("performance")
		end
	end)
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
			if GameTooltip:IsOwned(frame) then
				GameTooltip:Hide()
			end
			frame:Hide()
		end
		wipe(prev)
		wipe(rates)
		sampledAt = nil
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
