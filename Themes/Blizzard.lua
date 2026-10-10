local addonName, ns = ...

-- Blizzard default: the stock UI. Gold headings, white text, the tooltip's navy fill and grey border, the game's fonts.

local Theme = ns.Theme
local Hex, Global = Theme.HexColor, Theme.GlobalColor

Theme.Register("blizzard", {
	label = "Blizzard default",
	order = 1,
	panel = "blizzard",
	fonts = Theme.ClientFonts,
	colors = {
		bg = Global("TOOLTIP_DEFAULT_BACKGROUND_COLOR", "#171730"),
		bgTop = Global("TOOLTIP_DEFAULT_BACKGROUND_COLOR", "#171730"),
		bgBottom = Hex("#0e0e1e"),
		surface = { 0, 0, 0, 0.3 },
		hover = Hex("#ffffff", 0.09), -- a light wash, as Blizzard's list highlights
		text = Global("HIGHLIGHT_FONT_COLOR", "#ffffff"),
		heading = Global("NORMAL_FONT_COLOR", "#ffd100"),
		textMuted = Hex("#b4b4b4"),
		textFaint = Global("GRAY_FONT_COLOR", "#808080"),
		accent = Global("NORMAL_FONT_COLOR", "#ffd100"),
		accentDeep = Hex("#a66b00"),
		frame = Hex("#7f7f7f"),
		frameDark = { 0, 0, 0, 0.35 }, -- see-through like the tooltip fill (Home's character backdrop)
		rule = Hex("#ffffff", 0.12),
		contour = Hex("#ffffff"),
		success = Global("GREEN_FONT_COLOR", "#19ff19"),
		warning = Global("ORANGE_FONT_COLOR", "#ff8040"),
		danger = Global("RED_FONT_COLOR", "#ff2020"),
	},
})
