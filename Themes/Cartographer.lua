local addonName, ns = ...

-- Cartographer: dark map paper with grain and faint contour rings, thin brown frames, Cinzel titles, Alegreya text and
-- a muted arcane-purple accent (docs/superpowers/specs/2026-10-10-redesign-design.md). Art and fonts come from
-- tools/theme_art.py.

local Theme = ns.Theme
local Hex = Theme.HexColor

local FONTS = Theme.MEDIA .. "Fonts\\"
local CINZEL = FONTS .. "Cinzel-Medium.ttf"
local ALEGREYA = FONTS .. "Alegreya-Regular.ttf"
local NUMBERS = FONTS .. "AlegreyaNumbers-Regular.ttf"

-- Cinzel has no Cyrillic; neither font has Korean or Chinese. Those clients keep their own fonts for what's missing.
local CLIENT_FONTS = { koKR = true, zhCN = true, zhTW = true }

local function Fonts(locale)
	if CLIENT_FONTS[locale] then
		return Theme.ClientFonts()
	end
	local title = CINZEL
	if locale == "ruRU" then
		title = GameFontNormalHuge:GetFont()
	end
	return { title = title, body = ALEGREYA, number = NUMBERS }
end

Theme.Register("cartographer", {
	label = "Cartographer",
	order = 3,
	panel = "art",
	art = { ornaments = true }, -- the rest is ART_DEFAULTS in Core/Theme.lua, which are Cartographer's values
	fonts = Fonts,
	fontBump = { body = 1, number = 1 }, -- Alegreya has a small x-height
	colors = {
		bg = Hex("#191a1e"),
		bgTop = Hex("#1d2026"),
		bgBottom = Hex("#15171b"),
		surface = { 0, 0, 0, 0.19 },
		hover = Hex("#a99be0", 0.14),
		text = Hex("#e6dcc4"),
		heading = Hex("#eadbb5"),
		textMuted = Hex("#9c9480"),
		textFaint = Hex("#6b6658"),
		accent = Hex("#a99be0"),
		accentDeep = Hex("#5d4f9a"),
		frame = Hex("#8a7b5a"),
		frameDark = Hex("#0a0b0d"),
		rule = Hex("#a8956a", 0.15),
		contour = Hex("#d9c79a"),
		success = Hex("#8fbf7a"),
		warning = Hex("#d9a55b"),
		danger = Hex("#d0654f"),
	},
})
