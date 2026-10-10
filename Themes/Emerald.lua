local addonName, ns = ...

-- Emerald Dream: deep moss-green panels with a mossy grain and curling vines in the corner, old-gold frames, cream
-- text, Uncial Antiqua titles and a jade accent. Jade leans blue so the leaf-green "success" still reads as done.
-- Art and the font come from tools/themes/emerald.py.

local Theme = ns.Theme
local Hex = Theme.HexColor

local ART = Theme.MEDIA .. "Theme\\Emerald\\"
local UNCIAL = Theme.MEDIA .. "Fonts\\UncialAntiqua-Regular.ttf"

-- Uncial Antiqua has no Cyrillic, Korean or Chinese: those clients keep their own fonts for titles. Body text and
-- numbers are always the client's font (lists stay plain and readable).
local CLIENT_FONTS = { koKR = true, zhCN = true, zhTW = true }

local function Fonts(locale)
	local fonts = Theme.ClientFonts()
	fonts.label = STANDARD_TEXT_FONT -- Uncial is too ornate for small button and list-header labels
	if locale == "ruRU" then
		fonts.title = GameFontNormalHuge:GetFont()
	elseif not CLIENT_FONTS[locale] then
		fonts.title = UNCIAL
	end
	return fonts
end

Theme.Register("emerald", {
	label = "Emerald Dream",
	order = 6,
	panel = "art",
	art = {
		glow = 0.06,
		contours = 0.07,
		grain = 0.05,
		vignette = 0.5,
		ornaments = true,
	},
	media = {
		grain = ART .. "Grain",
		contours = ART .. "Vines",
		flourish = ART .. "Flourish",
	},
	fonts = Fonts,
	colors = {
		bg = Hex("#15231b"),
		bgTop = Hex("#1a2b22"),
		bgBottom = Hex("#0f1914"),
		surface = { 0, 0, 0, 0.22 },
		hover = Hex("#5fcfa8", 0.13),
		text = Hex("#ebe5cc"),
		heading = Hex("#e8d49a"),
		textMuted = Hex("#9fae94"),
		textFaint = Hex("#6c7a66"),
		accent = Hex("#5fcfa8"),
		accentDeep = Hex("#22715a"),
		frame = Hex("#8f7d4c"),
		frameDark = Hex("#070b08"),
		rule = Hex("#b39b5e", 0.16),
		contour = Hex("#bfe0a8"),
		success = Hex("#a9d46a"),
		warning = Hex("#e2b257"),
		danger = Hex("#e07560"),
	},
})
