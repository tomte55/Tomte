local addonName, ns = ...

-- Tomte classic: the look before the Cartographer redesign (the tree before commit 8906b7a). A flat near-black fill
-- with a 1 px gold border on the edge, gold headings and accents, light grey text, Morpheus titles, Friz Quadrata
-- text and Arial Narrow numbers. No grain, glow, corner art, vignette or flourishes. Values are the old UI.GOLD,
-- UI.WHITE, UI.GREY, UI.DIM, UI.BG and UI.BOX and the modules' old GREEN, ORANGE and RED.

local Theme = ns.Theme

local GOLD = { 1, 0.82, 0.45 }

-- The old code used these files directly. Morpheus has a Cyrillic build; neither it nor Arial Narrow has Korean or
-- Chinese, so those clients keep their own fonts.
local CLIENT_FONTS = { koKR = true, zhCN = true, zhTW = true }

local function Fonts(locale)
	if CLIENT_FONTS[locale] then
		return Theme.ClientFonts()
	end
	local title = locale == "ruRU" and "Fonts\\MORPHEUS_CYR.TTF" or "Fonts\\MORPHEUS.TTF"
	-- Buttons and list headers were the body font then, in gold.
	return { title = title, label = STANDARD_TEXT_FONT, body = STANDARD_TEXT_FONT, number = "Fonts\\ARIALN.TTF" }
end

Theme.Register("classic", {
	label = "Tomte classic",
	order = 2,
	panel = "art",
	art = {
		glow = 0,
		contours = 0,
		grain = 0,
		vignette = 0,
		outer = 0,
		inset = 0, -- the border sat on the edge
		rule = 0.45, -- the window's gold border alpha
		ornaments = false,
	},
	fonts = Fonts,
	colors = {
		bg = { 0.06, 0.06, 0.07 }, -- UI.BG, a flat fill
		bgTop = { 0.06, 0.06, 0.07 },
		bgBottom = { 0.06, 0.06, 0.07 },
		surface = { 0.11, 0.11, 0.12, 1 }, -- UI.BOX, opaque inset boxes
		hover = { 1, 1, 1, 0.05 }, -- the rows' white hover wash
		text = { 0.92, 0.92, 0.92 }, -- UI.WHITE
		heading = GOLD,
		textMuted = { 0.62, 0.62, 0.62 }, -- UI.GREY
		textFaint = { 0.4, 0.4, 0.4 }, -- UI.DIM
		accent = GOLD,
		accentDeep = { 0.81, 0.67, 0.37 }, -- gold at 0.8 over the fill: the old flat bar fill
		frame = GOLD, -- borders were gold at an alpha
		frameDark = { 0.05, 0.05, 0.06 }, -- Home's character well
		rule = { 1, 0.82, 0.45, 0.12 }, -- faint gold row lines
		contour = GOLD, -- unused: no corner art
		success = { 0.45, 0.85, 0.45 }, -- the modules' GREEN
		warning = { 1, 0.6, 0.2 }, -- ORANGE (world quest time, weekly board)
		danger = { 1, 0.45, 0.35 }, -- RED
	},
})
