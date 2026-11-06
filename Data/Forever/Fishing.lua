local addonName, ns = ...

-- World of Warcraft: Forever: Fishing's lures (see Core/Content.lua; read in Modules/Fishing/Rod.lua), weakest first: Shiny
-- Bauble, Nightcrawlers, Flesh Eating Worm, Bright Baubles, Aquadynamic Fish Attractor. Item IDs and order checked on
-- wowhead.com and warcraft.wiki.gg's Fishing_lure, 2026-11-06; the bonuses themselves aren't confirmed on Forever.

ns.Content_Register(ns.CONTENT_FOREVER, "lures", { 6529, 6530, 7307, 6532, 6533 })
