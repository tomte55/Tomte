local addonName, ns = ...

-- Void: near-black indigo panels with a sparse starfield, void tendrils and a nebula wisp in the corner, cool
-- lavender-white text, a vivid void-violet accent and Philosopher titles and text. Art and fonts come from
-- tools/themes/void.py.

local Theme = ns.Theme
local Hex = Theme.HexColor

local ART = Theme.MEDIA .. "Theme\\Void\\"
local FONTS = Theme.MEDIA .. "Fonts\\"
local TITLE = FONTS .. "Philosopher-Bold.ttf"
local BODY = FONTS .. "Philosopher-Regular.ttf"

-- Philosopher has Latin and Cyrillic, no Korean or Chinese. Its digits are proportional, so numbers keep the
-- client's font everywhere.
local CLIENT_FONTS = { koKR = true, zhCN = true, zhTW = true }

local function Fonts(locale)
	if CLIENT_FONTS[locale] then
		return Theme.ClientFonts()
	end
	return { title = TITLE, body = BODY, number = STANDARD_TEXT_FONT }
end

Theme.Register("void", {
	label = "Void",
	order = 7,
	panel = "art",
	art = {
		glow = 0.07,
		glowTint = "accent", -- violet light from the top-left
		contours = 0.16, -- thin tendrils and a soft wisp: needs a bit more than Cartographer's rings
		grain = 0.22, -- the stars: sparse points, kept dim so they sit behind the text
		vignette = 0.5,
		rule = 0.4,
		ornaments = true,
	},
	media = {
		grain = ART .. "Stars",
		contours = ART .. "Tendrils",
		flourish = ART .. "Flourish",
	},
	fonts = Fonts,
	fontBump = { body = 1 }, -- Philosopher has a small x-height
	colors = {
		bg = Hex("#120f22"),
		bgTop = Hex("#16122a"),
		bgBottom = Hex("#0c0a17"),
		surface = { 0, 0, 0, 0.26 },
		hover = Hex("#a46bff", 0.15),
		text = Hex("#e6e1f7"),
		heading = Hex("#d4c6ff"),
		textMuted = Hex("#9d96bd"),
		textFaint = Hex("#6c6690"),
		accent = Hex("#a46bff"),
		accentDeep = Hex("#4a1fa6"),
		frame = Hex("#6e5fae"),
		frameDark = Hex("#050409"),
		rule = Hex("#8f80d6", 0.16),
		contour = Hex("#b38aff"),
		success = Hex("#7fd9ab"),
		warning = Hex("#ebbb6c"),
		danger = Hex("#ff6f8e"),
	},
})
