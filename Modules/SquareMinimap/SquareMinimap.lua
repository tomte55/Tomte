local addonName, ns = ...

-- Square minimap: the minimap drawn square, with a thin frame in Tomte's colours instead of the round border. While on,
-- ns.MinimapShape (Core/OtherAddons.lua) answers "SQUARE", so Minimap Buttons, the Quest list's minimap markers and
-- Gather's minimap marks follow it. Other addons' minimap buttons (LibDBIcon and the like) ask the global
-- GetMinimapShape, the convention minimap addons share: while on, it's defined to say "SQUARE" (only when no other
-- addon has one; taken away again when turned off) and LibDBIcon's buttons are placed again. It steps aside when
-- another addon already shapes the minimap. Blizzard puts its
-- round mask back when the minimap's rotation changes (MinimapClusterMixin:UpdateMinimapConfig), so a hook applies
-- ours again; the hook does nothing while the module is off.

local SQUARE = "Interface\\Buttons\\WHITE8X8"
-- Put back when turned off: Forever's minimap sets this atlas (Camelot/Minimap.lua ModeData); elsewhere the round
-- portrait mask Blizzard_HybridMinimap's circle uses.
local ROUND_FOREVER = "ui-hud-minimap-frame-generic-mask"
local ROUND = "Interface\\CharacterFrame\\TempPortraitAlphaMask"

local UI = ns.UI

local module
local on = false
local frame -- the thin border round the square map
local dielPoints -- the day and night icon's own anchors while it's moved: { { point, relativeTo, relativePoint, x, y } }
local hooked = false

-- Ours, for the other addons' buttons (see the top).
local function Square()
	return "SQUARE"
end

-- Another addon shapes the minimap: it defines GetMinimapShape, or it's EllesmereUI's minimap.
local function OtherShaper()
	local get = rawget(_G, "GetMinimapShape")
	return (type(get) == "function" and get ~= Square) or ns.Ellesmere_Loaded("Minimap")
end

-- LibDBIcon places its buttons by GetMinimapShape when it lays them out: ask it to again. pcall: another addon's
-- library, its API could change.
local function PlaceLibraryButtons()
	local stub = rawget(_G, "LibStub")
	local ok, lib = pcall(function()
		return stub and stub("LibDBIcon-1.0", true)
	end)
	if not (ok and type(lib) == "table" and type(lib.objects) == "table" and type(lib.Refresh) == "function") then
		return
	end
	for name in pairs(lib.objects) do
		pcall(lib.Refresh, lib, name)
	end
end

local function ShareShape(square)
	if square and rawget(_G, "GetMinimapShape") == nil then
		_G.GetMinimapShape = Square
	elseif not square and rawget(_G, "GetMinimapShape") == Square then
		_G.GetMinimapShape = nil
	end
	PlaceLibraryButtons()
end

local function Hybrid(square)
	local hybrid = rawget(_G, "HybridMinimap")
	if hybrid and hybrid.CircleMask then
		hybrid.CircleMask:SetTexture(square and SQUARE or ROUND, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
	end
end

local function Border()
	if not frame then
		frame = CreateFrame("Frame", nil, Minimap)
		frame:SetAllPoints(Minimap)
		frame:SetFrameLevel(Minimap:GetFrameLevel() + 2)
		frame:EnableMouse(false)
		UI.Border(frame, "frameDark", 1)
	end
	return frame
end

-- Forever's day and night icon (MinimapCluster.DielFrame, Camelot/Diel.lua) sits on the round map's rim, over a
-- square map's top right: on the corner instead, mostly outside the map. Its own anchors are put back when the module
-- is turned off; Blizzard places it again when Edit Mode scales the minimap (SetEditModeScale, hooked).
local function MoveDiel(square)
	local diel = MinimapCluster and MinimapCluster.DielFrame
	if not diel then
		return
	end
	if square then
		if not dielPoints then
			dielPoints = {}
			for i = 1, diel:GetNumPoints() do
				dielPoints[i] = { diel:GetPoint(i) }
			end
		end
		diel:ClearAllPoints()
		diel:SetPoint("CENTER", Minimap, "TOPRIGHT", 8, 8)
	elseif dielPoints then
		diel:ClearAllPoints()
		for _, p in ipairs(dielPoints) do
			diel:SetPoint(unpack(p))
		end
		dielPoints = nil
	end
end

local function Apply()
	if not on then
		return
	end
	MoveDiel(true)
	Minimap:SetMaskTexture(SQUARE)
	Hybrid(true)
	if MinimapCompassTexture then
		MinimapCompassTexture:Hide()
	end
	if MinimapCompassTextureUnderlay then
		MinimapCompassTextureUnderlay:Hide()
	end
	Border():Show()
end

local function Undo()
	if ns.FOREVER then
		Minimap:SetMaskTexture(ROUND_FOREVER)
	else
		Minimap:SetMaskTexture(ROUND)
	end
	Hybrid(false)
	MoveDiel(false)
	if MinimapCompassTexture then
		MinimapCompassTexture:Show()
	end
	-- Blizzard shows the underlay only for a turning minimap (Camelot/Minimap.lua).
	if MinimapCompassTextureUnderlay and ns.FOREVER then
		MinimapCompassTextureUnderlay:SetShown(C_CVar.GetCVarBool("rotateMinimap"))
	end
	if frame then
		frame:Hide()
	end
end

local function Hook()
	if hooked then
		return
	end
	hooked = true
	if MinimapCluster and MinimapCluster.UpdateMinimapConfig then
		hooksecurefunc(MinimapCluster, "UpdateMinimapConfig", Apply)
	end
	if MinimapCluster and MinimapCluster.SetEditModeScale then
		hooksecurefunc(MinimapCluster, "SetEditModeScale", function()
			if on then
				dielPoints = nil -- Blizzard's new spot is the one to put back
				MoveDiel(true)
			end
		end)
	end
end

-- Everything that follows the minimap's shape places itself again.
local function ShapeChanged()
	if ns.Minimap_PlaceButtons then
		ns.Minimap_PlaceButtons()
	end
	if ns.QuestListMini_Refresh then
		ns.QuestListMini_Refresh()
	end
end

-- Core/OtherAddons.lua: whether Tomte draws the minimap square right now.
function ns.SquareMinimap_On()
	return on
end

local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(_, _, name)
	if name == "Blizzard_HybridMinimap" and on then
		Hybrid(true)
	end
end)

module = ns.RegisterModule({
	key = "squareMinimap",
	name = "Square minimap",
	category = "interface",
	icon = "Interface\\Icons\\INV_Misc_Map02",
	summary = "A square minimap with a thin frame.",
	description = "Draws the minimap square, with a thin frame instead of the round border, so it shows more of the "
		.. "ground in its corners. Minimap buttons and Tomte's minimap markers follow it. Off when another addon "
		.. "already shapes your minimap.",
	enabledByDefault = false,
	blocked = function()
		if OtherShaper() then
			return "Another addon shapes your minimap."
		end
	end,
	defaults = {},
	toggle = function(enabled)
		local want = enabled and not OtherShaper()
		if want == on then
			return
		end
		on = want
		if on then
			Hook()
			events:RegisterEvent("ADDON_LOADED")
			Apply()
		else
			events:UnregisterEvent("ADDON_LOADED")
			Undo()
		end
		ShareShape(on)
		ShapeChanged()
	end,
})
