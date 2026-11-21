local addonName, ns = ...

-- Zeppelins and boats on World of Warcraft: Forever, for Waypoints' routes (Modules/Travel/ForeverRouter.lua). Each
-- has two ends: { uiMapID, x, y (percent), the place's name }; side "H" or "A" for the side whose towns it serves, nil for
-- both. Flight paths aren't here: the router reads those from the game.
-- Zeppelin towers and the Ratchet boat: where their zeppelin masters and shipmasters stand (QuestieDB's Forever NPC data,
-- github.com/Questie/QuestieDB, GPL-3.0: positions only). The Alliance boats have no such NPC: their docks are read
-- off the classic-era zone maps and not yet checked on Forever.

ns.Content_Register(ns.CONTENT_FOREVER, "transports", {
	-- Frezza and Zapetta.
	{ kind = "zeppelin", side = "H", a = { 1411, 50.82, 13.54, "Orgrimmar" }, b = { 1420, 60.74, 58.87, "Undercity" } },
	-- Snurk Bucksquick and Squibby Overspeck.
	{ kind = "zeppelin", side = "H", a = { 1411, 50.69, 12.89, "Orgrimmar" }, b = { 1434, 31.54, 29.36, "Grom'gol" } },
	-- Hin Denburg and Nez'raz.
	{ kind = "zeppelin", side = "H", a = { 1420, 61.78, 59.18, "Undercity" }, b = { 1434, 31.43, 29.91, "Grom'gol" } },
	-- Grimble and Grizzlowe.
	{ kind = "boat", a = { 1413, 63.54, 38.61, "Ratchet" }, b = { 1434, 26.08, 73.35, "Booty Bay" } },
	-- Not checked on Forever.
	{ kind = "boat", side = "A", a = { 1437, 4.6, 63.6, "Menethil Harbor" }, b = { 1445, 71.6, 56.4, "Theramore" } },
	{ kind = "boat", side = "A", a = { 1437, 4.5, 57.0, "Menethil Harbor" }, b = { 1439, 32.4, 43.8, "Auberdine" } },
	{ kind = "boat", side = "A", a = { 1439, 33.2, 40.2, "Auberdine" }, b = { 1438, 54.9, 96.8, "Rut'theran Village" } },
})
