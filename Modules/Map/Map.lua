local addonName, ns = ...

-- Tomte map (World of Warcraft: Forever): our own world map, one seamless world you zoom and pan, in a window of
-- Tomte's own, so nothing of Blizzard's map is touched (calls into it taint, see the project's map notes). Main file:
-- module, db, events while the window shows, key binding, commands. The window in Window.lua, art in Art.lua, pins in
-- Pins.lua, maths in Data.lua. See docs/superpowers/specs/2026-11-15-tomte-world-map-design.md.

local WORLD_MAP_ID = 947 -- Azeroth: the world map both continents sit on (OpenMap measured it on Forever)
local ICON = "Interface\\Icons\\INV_Misc_Map_01"

local module, db
local events = CreateFrame("Frame")
local shown = false
local ApplyKey -- the settings' key (below)
local keyPending = false -- it changed in combat: applied when that ends

local EVENTS = {
	"QUEST_LOG_UPDATE", "QUEST_POI_UPDATE", "USER_WAYPOINT_UPDATED", "MAP_EXPLORATION_UPDATED", "PLAYER_ENTERING_WORLD",
}

-- The world map's ID: Azeroth, or the client's fallback world map where Azeroth has no art.
function ns.Map_WorldID()
	local layers = C_Map.GetMapArtLayers(WORLD_MAP_ID)
	if layers and layers[1] then
		return WORLD_MAP_ID
	end
	local fallback = C_Map.GetFallbackWorldMapID and C_Map.GetFallbackWorldMapID()
	layers = fallback and C_Map.GetMapArtLayers(fallback)
	return layers and layers[1] and fallback or nil
end

-- Events: only while the window shows ------------------------------------------------------------------------------

events:SetScript("OnEvent", function(_, event)
	if event == "PLAYER_REGEN_ENABLED" then
		events:UnregisterEvent("PLAYER_REGEN_ENABLED")
		if keyPending then
			ApplyKey()
		end
		return
	elseif event == "USER_WAYPOINT_UPDATED" then
		ns.MapPins_Waypoint()
	elseif event == "MAP_EXPLORATION_UPDATED" then
		ns.MapArt_Explored()
	else
		ns.MapPins_Quests()
		ns.MapQuests_Refresh()
	end
end)

-- Whether the Tomte map is on (other modules check before sending the player to it).
function ns.Map_IsOn()
	return module ~= nil and module.active == true
end

-- Window.lua: the window showed or hid.
function ns.Map_Shown(on)
	shown = on
	for _, event in ipairs(EVENTS) do
		if on then
			events:RegisterEvent(event)
		else
			events:UnregisterEvent(event)
		end
	end
end

ns.ActiveQuest_OnChange(function()
	if shown then
		ns.MapPins_Quests()
		ns.MapQuests_Refresh()
	end
end)

local function Toggle()
	if ns.Module_RequireOn(module) then
		ns.MapWindow_Toggle()
	end
end

-- The keys: a hidden button clicked by them (Key Bindings > Tomte: "CLICK TomteMapButton:LeftButton" opens the map,
-- ":RightButton" the map with its quest log, like the game's M and L). Command bindings (a <Binding> calling Lua)
-- didn't show in Forever's Key Bindings and an override to one did nothing (2026-11-15); click bindings work there.
-- Acts on the key going down; a client that sends only the release acts on that.
local KEY_REPEAT = 0.5 -- seconds: a release this soon after a press is the same key press
local keyButton = CreateFrame("Button", "TomteMapButton", UIParent)
keyButton:Hide()
keyButton:RegisterForClicks("AnyDown", "AnyUp")
local lastDown = 0
keyButton:SetScript("OnClick", function(_, mouseButton, down)
	local now = GetTime()
	if down then
		lastDown = now
	elseif now - lastDown < KEY_REPEAT then
		return
	end
	if ns.Module_RequireOn(module) then
		ns.MapWindow_Toggle(mouseButton == "RightButton")
	end
end)

-- The settings' keys: override bindings clicking that button, over the game's own use of those keys (M and L open
-- this map instead of the game's). Override bindings can't change in combat: then once it ends.
local keyOwner
function ApplyKey()
	if InCombatLockdown() then
		keyPending = true
		events:RegisterEvent("PLAYER_REGEN_ENABLED")
		return
	end
	keyPending = false
	keyOwner = keyOwner or CreateFrame("Frame")
	ClearOverrideBindings(keyOwner)
	if not (module and module.active) then
		return
	end
	if type(db.key) == "string" and db.key ~= "" then
		SetOverrideBindingClick(keyOwner, true, db.key, "TomteMapButton", "LeftButton")
	end
	if type(db.logKey) == "string" and db.logKey ~= "" then
		SetOverrideBindingClick(keyOwner, true, db.logKey, "TomteMapButton", "RightButton")
	end
end

-- Commands --------------------------------------------------------------------------------------------------------------

local function Why()
	local worldID = ns.Map_WorldID()
	ns.Print(("Tomte map: world map %s, %d continents, %d zones."):format(tostring(worldID),
		#ns.MapArt_Continents(), #ns.MapArt_Zones()))
	if not ns.MapWindow_State then
		return
	end
	local state, level, W, H, fit = ns.MapWindow_State()
	print(("  canvas %dx%d, fit %.3f, zoom %.2f (%s art), centre %.3f, %.3f"):format(W, H, fit, state.zoom, level,
		state.u, state.v))
	local drawn, textures = 0, 0
	for _, list in ipairs({ ns.MapArt_Continents(), ns.MapArt_Zones() }) do
		for _, r in ipairs(list) do
			if r.visible then
				drawn = drawn + 1
				textures = textures + #r.textures
			end
		end
	end
	print(("  %d maps shown, %d textures on them"):format(drawn, textures))
	local loaded, version, known = ns.MapArt_AddonState()
	local modes, cut = {}, {}
	for _, z in ipairs(ns.MapArt_Zones()) do
		if z.mode then
			modes[z.mode] = (modes[z.mode] or 0) + 1
		end
		if z.mode == "cut" then
			local info = C_Map.GetMapInfo(z.mapID)
			cut[#cut + 1] = ("%s (map %d, art %s, parent %s)"):format(z.name or "?", z.mapID,
				tostring(C_Map.GetMapArtID(z.mapID)), tostring(info and info.parentMapID))
		end
	end
	print(("  Tomte_MapArt %s (version %s, Tomte knows %s); zones drawn: %d masked, %d from pieces, %d cut"):format(
		loaded and "loaded" or "not loaded", tostring(version), tostring(known), modes.mask or 0, modes.pieces or 0,
		modes.cut or 0))
	for _, line in ipairs(cut) do
		print("  cut: " .. line)
	end
end

-- Options ---------------------------------------------------------------------------------------------------------------

local function ZoomText(v)
	return ("%gx"):format(math.floor(v * 100 + 0.5) / 100)
end

local function Relayout()
	if ns.MapWindow_Relayout then
		ns.MapWindow_Relayout()
	end
end

module = ns.RegisterModule({
	key = "map",
	name = "Tomte map",
	category = "travel",
	icon = ICON,
	summary = "A world map of Tomte's own: the whole world in one piece, zoomed with the wheel.",
	description = "A world map in its own window: both continents and every zone stitched into one world you zoom "
		.. "toward the mouse and drag around. Shows you and your party, your quests (the active one with its area), "
		.. "flight masters, dungeon entrances and your map pin. Click a quest to make it your active quest, Ctrl-click "
		.. "to place a map pin, right-click to zoom out. Open it with /tomte map or a key (Key Bindings > Tomte); bind "
		.. "M to it to use it instead of the game's map. It never touches the game's map, so it can't break it, and it "
		.. "works in combat.",
	enabledByDefault = false,
	uses = { { addon = "Tomte_MapArt", why = "soft borders between zones",
		without = "zones are drawn from their explored areas, with harder edges" } },
	defaults = {
		quests = true,
		questArea = true, -- the active quest's area on its zone
		taxis = true,
		dungeons = true,
		party = true,
		pinScale = 1,
		key = "", -- a key that opens the map (binding string, "" for none), on top of Key Bindings > Tomte
		logKey = "", -- a key that opens it with its quest log (as the game's L)
		revealAll = true, -- every part of each zone drawn, explored or not (needs Tomte_MapArt)
		continentZoom = 1.2, -- zoom (1: the whole world fits) where the continents' own maps fade in
		zoneZoom = 5, -- and the zones'
		sideShown = true, -- the side panel right of the map
		side = "quests", -- its tab: "quests" or "tp" (Teleports)
		ground = true, -- the game's minimap pictures close up
		groundZoom = 10, -- zoom where they start fading in
		window = false, -- { w, h, point, relPoint, x, y } once moved or resized
	},
	init = function(moduleDB)
		db = moduleDB
		ns.MapArt_RevealAll(db.revealAll)
		ns.MapWindow_Init(db)
	end,
	toggle = function(on)
		if not on then
			ns.MapWindow_Hide()
		end
		ApplyKey()
	end,
	commands = {
		{ hidden = true, "", "open or close the map", function()
			Toggle()
		end },
		{ debug = true, "why", "what the map has loaded and where it looks", function()
			Why()
		end },
		{ "reset", "put the map window back in the middle at its default size", function()
			ns.MapWindow_ResetFrame()
		end },
	},
	options = {
		{ type = "header", label = "Map" },
		{ type = "button", label = "Open the map", text = "Open", onClick = function()
			Toggle()
		end, tooltip = "Or bind a key to it in Key Bindings > Tomte (Tomte map). Bind M to use it instead of the game's map." },
		{ type = "key", key = "key", label = "Map key", onChange = ApplyKey,
			tooltip = "A key that opens and closes the map, as you last left its quest log. Pick M to use it instead of the game's map. Also under Key Bindings > Tomte." },
		{ type = "key", key = "logKey", label = "Quest log key", onChange = ApplyKey,
			tooltip = "A key that opens the map with its quest log showing, without changing how the map key opens it. Pick L to use it instead of the game's quest log." },
		{ type = "button", label = "Window", text = "Reset", onClick = function()
			ns.MapWindow_ResetFrame()
		end, tooltip = "Back in the middle of the screen at its default size." },
		{ type = "checkbox", key = "revealAll", label = "Show the whole map", onChange = function(on)
			ns.MapArt_RevealAll(on)
		end, tooltip = "Draw every part of each zone, also the ones you haven't explored yet. Needs Tomte Map Art; without it the whole map always shows." },
		{ type = "slider", key = "pinScale", label = "Icon size", min = 0.7, max = 1.6, step = 0.05,
			format = function(v)
				return ("%d%%"):format(math.floor(v * 100 + 0.5))
			end, onChange = Relayout },

		{ type = "header", label = "Detail" },
		{ type = "slider", key = "continentZoom", label = "Continent maps from", min = 1.1, max = 3, step = 0.1,
			format = ZoomText, onChange = Relayout,
			tooltip = "How far you zoom in (1x: the whole world fits) before each continent's own map fades in over the world map." },
		{ type = "slider", key = "zoneZoom", label = "Zone maps from", min = 2, max = 12, step = 0.25,
			format = ZoomText, onChange = Relayout,
			tooltip = "How far you zoom in before each zone's own map fades in over its continent." },
		{ type = "checkbox", key = "ground", label = "Ground pictures close up", onChange = Relayout,
			tooltip = "The game's minimap pictures over the map once you're zoomed in close: the real ground, rocks and roads." },
		{ type = "slider", key = "groundZoom", label = "Ground pictures from", min = 3, max = 40, step = 1,
			parent = "ground", format = ZoomText, onChange = Relayout,
			tooltip = "Lower shows them sooner. Zoomed far out there are too many of them to draw, so they stay off there." },
		{ type = "button", label = "Detail", text = "Defaults", onClick = function()
			db.continentZoom, db.zoneZoom, db.ground, db.groundZoom = 1.2, 5, true, 10
			Relayout()
			ns.Panel_Refresh()
		end, tooltip = "Back to the zooms the map starts with." },

		{ type = "header", label = "On the map" },
		{ type = "checkbox", key = "quests", label = "Quests", onChange = Relayout,
			tooltip = "Every quest in your log with a spot on the map: a gold ? once it's ready to hand in. The active quest is larger. Click one to make it your active quest." },
		{ type = "checkbox", key = "questArea", label = "The active quest's area", parent = "quests", onChange = function()
			if ns.MapPins_Quests then
				ns.MapPins_Quests()
			end
		end, tooltip = "Drawn on its zone as the game's map draws it." },
		{ type = "checkbox", key = "taxis", label = "Flight masters", onChange = Relayout },
		{ type = "checkbox", key = "dungeons", label = "Dungeon entrances", onChange = Relayout },
		{ type = "checkbox", key = "party", label = "Party and raid members", onChange = Relayout },
	},
})
