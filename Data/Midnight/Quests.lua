local addonName, ns = ...

-- Midnight (expansion 11): event sign-up gossip options the Quests module picks for you. See Core/Content.lua.
-- Gossip option IDs from Plumber (Modules/AutoJoinEvents.lua; IDs only, read 2026-10-23). No Midnight event of
-- this kind is known yet; the older ones still run for a Midnight character, so they stay on the list.

ns.Content_Register(11, "questGossip", {
	{ gossipOptionID = 120733, name = "Theater Troupe" }, -- Stage Manager Huberta, Isle of Dorn
	{ gossipOptionID = 109275, name = "Time Rift" }, -- Soridormi, Thaldraszus
})
