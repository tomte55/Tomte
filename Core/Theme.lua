local addonName, ns = ...

-- The theme: every color and font Tomte draws with, by role (docs/superpowers/specs/2026-10-10-redesign-design.md).
-- Code asks for a role (ns.UI.Color("accent"), ns.Theme.Font("title")), never for a number or a font path.
-- Core.lua calls Theme.Apply with the saved choice on ADDON_LOADED, before any frame is built; nothing reads a
-- color while the files load (tests/test_theme.lua checks). Switching themes means a reload: there's no repaint.

local MEDIA = "Interface\\AddOns\\Tomte\\Media\\"

local function Hex(hex, alpha)
	local r, g, b = hex:match("^#(%x%x)(%x%x)(%x%x)$")
	return { tonumber(r, 16) / 255, tonumber(g, 16) / 255, tonumber(b, 16) / 255, alpha }
end

-- A Blizzard color global (a ColorMixin like NORMAL_FONT_COLOR), or `hex` where it's missing (the unit tests).
local function Global(name, hex, alpha)
	local c = _G[name]
	if type(c) == "table" and type(c.r) == "number" then
		return { c.r, c.g, c.b, alpha }
	end
	return Hex(hex, alpha)
end

local CINZEL = MEDIA .. "Fonts\\Cinzel-Medium.ttf"
local ALEGREYA = MEDIA .. "Fonts\\Alegreya-Regular.ttf"
local NUMBERS = MEDIA .. "Fonts\\AlegreyaNumbers-Regular.ttf"

-- Cinzel has no Cyrillic; neither font has Korean or Chinese. Those clients keep their own fonts for what's missing.
local CLIENT_FONTS = { koKR = true, zhCN = true, zhTW = true }

local function CartographerFonts(locale)
	if CLIENT_FONTS[locale] then
		return { title = STANDARD_TEXT_FONT, body = STANDARD_TEXT_FONT, number = STANDARD_TEXT_FONT }
	end
	local title = CINZEL
	if locale == "ruRU" then
		title = GameFontNormalHuge:GetFont()
	end
	return { title = title, body = ALEGREYA, number = NUMBERS }
end

-- The game's own font in every role: STANDARD_TEXT_FONT already is the right one for each client language.
local function ClientFonts()
	return { title = STANDARD_TEXT_FONT, body = STANDARD_TEXT_FONT, number = STANDARD_TEXT_FONT }
end

-- Each theme: label (the Settings dropdown), colors by role, fonts(locale), and panel = how UI.Panel draws:
-- "cartographer" (grain, contours, glow, vignette, ruled frame, ink flourishes) or "blizzard" (the tooltip border).
local THEMES = {
	cartographer = {
		label = "Cartographer",
		panel = "cartographer",
		fonts = CartographerFonts,
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
	},
	-- The stock UI: gold headings, white text, the tooltip's navy fill and grey border, the game's fonts.
	blizzard = {
		label = "Blizzard default",
		panel = "blizzard",
		fonts = ClientFonts,
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
	},
}
local ORDER = { "blizzard", "cartographer" }
local DEFAULT = "blizzard"

local Theme = {
	colors = {},
	media = {
		grain = MEDIA .. "Theme\\Grain",
		contours = MEDIA .. "Theme\\Contours",
		flourish = MEDIA .. "Theme\\Flourish",
		glow = MEDIA .. "Theme\\Glow",
	},
}
ns.Theme = Theme
Theme.DEFAULT = DEFAULT

local fonts

-- Makes `name` the theme (an unknown or missing name is the default). The colors table stays the same table.
function Theme.Apply(name)
	if not THEMES[name] then
		name = DEFAULT
	end
	local t = THEMES[name]
	Theme.name, Theme.panel = name, t.panel
	for role in pairs(Theme.colors) do
		Theme.colors[role] = nil
	end
	for role, c in pairs(t.colors) do
		Theme.colors[role] = c
	end
	fonts = nil
end

-- { { value, text } } for the Settings dropdown, in order.
function Theme.Choices()
	local list = {}
	for _, name in ipairs(ORDER) do
		list[#list + 1] = { value = name, text = THEMES[name].label }
	end
	return list
end

-- The ink flourishes under titles belong to Cartographer only.
function Theme.HasOrnaments()
	return Theme.panel == "cartographer"
end

-- Cartographer's fonts for a client language (the Blizzard theme always uses the client's own).
Theme.FontsFor = CartographerFonts

-- fontRole: "title", "body", "number", or "chat" (text other players wrote: always the chat font, so it shows the
-- way it does in chat whatever language it's in).
function Theme.Font(fontRole)
	if fontRole == "chat" then
		return (ChatFontNormal:GetFont())
	end
	fonts = fonts or THEMES[Theme.name].fonts(GetLocale())
	return fonts[fontRole or "body"] or fonts.body
end

-- Alegreya has a small x-height: one point up keeps body text the size the old fonts had at the same number.
function Theme.FontSize(fontRole, size)
	fonts = fonts or THEMES[Theme.name].fonts(GetLocale())
	if (fontRole == nil or fontRole == "body" or fontRole == "number") and fonts.body ~= STANDARD_TEXT_FONT then
		return size + 1
	end
	return size
end

-- Sets a font string's font by role: fs, "body"|"title"|"number"|"chat", size in the old fonts' points, flags.
-- If the file can't be loaded (a /reload right after installing: the game only sees new files after a restart, or a
-- broken unzip), it falls back to the client's font instead of leaving the string with no font.
function Theme.SetFont(fs, fontRole, size, flags)
	if fs:SetFont(Theme.Font(fontRole), Theme.FontSize(fontRole, size), flags or "") then
		return true
	end
	return fs:SetFont(STANDARD_TEXT_FONT, size, flags or "")
end

local function Get(role)
	local c = Theme.colors[role]
	if not c then
		error("Tomte theme: no color role '" .. tostring(role) .. "'", 3)
	end
	return c
end

-- r, g, b, a (a is 1 when the role has none).
function Theme.Color(role)
	local c = Get(role)
	return c[1], c[2], c[3], c[4] or 1
end

-- r, g, b only: for calls where a 4th value means something else (GameTooltip:AddLine's 4th is wrap).
function Theme.RGB(role)
	local c = Get(role)
	return c[1], c[2], c[3]
end

-- "ffrrggbb" for |c escapes.
function Theme.Hex(role)
	local c = Get(role)
	local function B(v)
		return math.floor(v * 255 + 0.5)
	end
	return ("ff%02x%02x%02x"):format(B(c[1]), B(c[2]), B(c[3]))
end

function Theme.Wrap(text, role)
	return "|c" .. Theme.Hex(role) .. tostring(text) .. "|r"
end

Theme.Apply(DEFAULT) -- until Core.lua applies the saved choice
