local addonName, ns = ...

-- The War Within (expansion 10): event sign-up gossip options the Quests module picks for you. See
-- Core/Content.lua. Gossip option IDs from Plumber (Modules/AutoJoinEvents.lua; IDs only, read 2026-10-23).
-- Time Rift is Dragonflight's, but still runs every hour for a War Within character.

ns.Content_Register(10, "questGossip", {
	{ gossipOptionID = 120733, name = "Theater Troupe" }, -- Stage Manager Huberta, Isle of Dorn
	{ gossipOptionID = 109275, name = "Time Rift" }, -- Soridormi, Thaldraszus
})
