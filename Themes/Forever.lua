local addonName, ns = ...

-- Forever: Tomte drawn with World of Warcraft: Forever's own frames, buttons and tabs, so it looks like part of that
-- game (docs/superpowers/specs/2026-11-06-tomte-forever-theme-design.md). Loaded on Forever only (tools/forever_list.lua).
-- The art is the client's, drawn by Panel/ForeverArt.lua and Panel/ForeverTabs.lua; these colors are for what sits on it.

local Theme = ns.Theme
local Hex, Global = Theme.HexColor, Theme.GlobalColor

Theme.Register("forever", {
	label = "Forever",
	order = 1.5, -- right after Blizzard default
	panel = "forever",
	-- Panels too small for the metal frame and widgets over the game world still use the art path: a flat fill and a
	-- rule, nothing else.
	art = { glow = 0, contours = 0, grain = 0, vignette = 0, outer = 1, inset = 0, rule = 0.6, subtleRule = 0.5,
		opacity = false },
	fonts = Theme.ClientFonts,
	colors = {
		bg = Hex("#2b211a"), -- laid over the rock texture to warm and darken it (Panel/ForeverArt.lua)
		bgTop = Hex("#2f271f"),
		bgBottom = Hex("#241d17"),
		surface = { 0, 0, 0, 0.28 },
		hover = Hex("#ffd100", 0.12),
		text = Global("HIGHLIGHT_FONT_COLOR", "#ffffff"),
		heading = Global("NORMAL_FONT_COLOR", "#ffd100"),
		textMuted = Hex("#c9bda6"),
		textFaint = Hex("#8f8472"),
		accent = Global("NORMAL_FONT_COLOR", "#ffd100"),
		accentDeep = Hex("#a66b00"),
		frame = Hex("#a8834a"), -- the frames' bronze
		frameDark = Hex("#14100b"),
		rule = Hex("#c29a5a", 0.22),
		contour = Hex("#c29a5a"),
		success = Global("GREEN_FONT_COLOR", "#19ff19"),
		warning = Global("ORANGE_FONT_COLOR", "#ff8040"),
		danger = Hex("#ff4a3a"), -- RED_FONT_COLOR is hard to read on this brown
		info = Global("LIGHTBLUE_FONT_COLOR", "#87aaff"),
	},
})
