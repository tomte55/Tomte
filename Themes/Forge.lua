local addonName, ns = ...

-- Forge: dark iron and soot panels with a hammered-metal grain, warm ember light from the corner, bronze frames, faint
-- dwarven runes and rivets in octagonal bands in the corner art, Grenze titles and an ember-orange accent
-- (docs/superpowers/specs/2026-10-10-tomte-themes-design.md). Art and the title font come from tools/themes/forge.py.

local Theme = ns.Theme
local Hex = Theme.HexColor

local ART = Theme.MEDIA .. "Theme\\Forge\\"
local GRENZE = Theme.MEDIA .. "Fonts\\Grenze-SemiBold.ttf"

-- Grenze has no Cyrillic, Korean or Chinese. Text and numbers stay in the client's font everywhere (it reads best in
-- lists); only titles are Grenze.
local CLIENT_FONTS = { koKR = true, zhCN = true, zhTW = true }

local function Fonts(locale)
	local fonts = Theme.ClientFonts()
	if CLIENT_FONTS[locale] then
		return fonts
	end
	if locale == "ruRU" then
		fonts.title = GameFontNormalHuge:GetFont()
	else
		fonts.title = GRENZE
	end
	return fonts
end

Theme.Register("forge", {
	label = "Forge",
	order = 5,
	panel = "art",
	art = {
		glow = 0.08, -- the glow file is ember-colored (it isn't tinted), so it reads as forge light
		contours = 0.07,
		grain = 0.07,
		vignette = 0.5,
		rule = 0.45,
		ornaments = true,
	},
	media = {
		grain = ART .. "Grain",
		contours = ART .. "Runes",
		flourish = ART .. "Flourish",
		glow = ART .. "Glow",
	},
	fonts = Fonts,
	fontBump = { title = 1 }, -- Grenze is condensed
	colors = {
		bg = Hex("#1b1816"),
		bgTop = Hex("#221d1a"),
		bgBottom = Hex("#131110"),
		surface = { 0, 0, 0, 0.24 },
		hover = Hex("#f08a3c", 0.13),
		text = Hex("#eedfcb"),
		heading = Hex("#f2c88e"),
		textMuted = Hex("#a89584"),
		textFaint = Hex("#76685c"),
		accent = Hex("#f08a3c"),
		accentDeep = Hex("#8e3514"),
		frame = Hex("#a6764a"),
		frameDark = Hex("#090706"),
		rule = Hex("#b98756", 0.17),
		contour = Hex("#e3ad7c"),
		success = Hex("#9dc47c"),
		warning = Hex("#e8cb5a"),
		danger = Hex("#e2605a"),
	},
})
