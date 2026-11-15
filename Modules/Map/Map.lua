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
	if event == "USER_WAYPOINT_UPDATED" then
		ns.MapPins_Waypoint()
	elseif event == "MAP_EXPLORATION_UPDATED" then
		ns.MapArt_Explored()
	else
		ns.MapPins_Quests()
	end
end)

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
	end
end)

local function Toggle()
	if ns.Module_RequireOn(module) then
		ns.MapWindow_Toggle()
	end
end

ns.Binding_Add("MAP", "map", function()
	ns.MapWindow_Toggle()
end)

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
		revealAll = true, -- every part of each zone drawn, explored or not (needs Tomte_MapArt)
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
