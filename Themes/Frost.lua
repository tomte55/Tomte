local addonName, ns = ...

-- Northrend: deep blue-slate panels, frost-white text, a glacier-blue accent, silvery steel frames, window-pane rime
-- in the corner art, a fine snow speckle and an ice-crystal flourish. Forum titles, the client's font for the rest.
-- Art and font come from tools/themes/frost.py.

local Theme = ns.Theme
local Hex = Theme.HexColor

local ART = Theme.MEDIA .. "Theme\\Frost\\"
local FORUM = Theme.MEDIA .. "Fonts\\FrostForum-Regular.ttf"

-- Forum has Latin and Cyrillic; Korean and Chinese keep the client's fonts.
local CLIENT_FONTS = { koKR = true, zhCN = true, zhTW = true }

local function Fonts(locale)
	local fonts = Theme.ClientFonts()
	if not CLIENT_FONTS[locale] then
		fonts.title = FORUM
	end
	return fonts
end

Theme.Register("frost", {
	label = "Northrend",
	order = 4,
	panel = "art",
	art = { ornaments = true, glow = 0.06, glowTint = "accent", contours = 0.09, grain = 0.07, vignette = 0.5, rule = 0.5 },
	media = {
		grain = ART .. "Snow",
		contours = ART .. "Rime",
		flourish = ART .. "Flourish",
	},
	fonts = Fonts,
	fontBump = { title = 1 }, -- Forum is light and has a small x-height
	colors = {
		bg = Hex("#171e28"),
		bgTop = Hex("#1c2531"),
		bgBottom = Hex("#121820"),
		surface = { 0, 0, 0, 0.24 },
		hover = Hex("#86c8ea", 0.13),
		text = Hex("#e2ebf3"),
		heading = Hex("#eef6fc"),
		textMuted = Hex("#91a2b4"),
		textFaint = Hex("#627181"),
		accent = Hex("#86c8ea"),
		accentDeep = Hex("#2c6a92"),
		frame = Hex("#8e9cab"),
		frameDark = Hex("#06080b"),
		rule = Hex("#b9cadb", 0.13),
		contour = Hex("#d8ecfa"),
		success = Hex("#85c99b"),
		warning = Hex("#e2bb62"),
		danger = Hex("#e2735f"),
	},
})
