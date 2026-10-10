local addonName, ns = ...

-- The theme: every color and font Tomte draws with, by role (docs/superpowers/specs/2026-10-10-redesign-design.md,
-- 2026-10-10-tomte-themes-design.md). Code asks for a role (ns.UI.Color("accent"), ns.Theme.Font("title")), never
-- for a number or a font path. Each theme is one file in Themes/ that calls Theme.Register; Core.lua calls
-- Theme.Apply with the saved choice on ADDON_LOADED, before any frame is built. Nothing reads a color while the files
-- load (tests/test_theme.lua checks). Switching themes means a reload: there's no repaint.

local MEDIA = "Interface\\AddOns\\Tomte\\Media\\"

local THEMES = {}
local DEFAULT = "blizzard"

-- How UI.Panel draws a theme whose `panel` is "art" (Panel/Widgets.lua). A theme's `art` table overrides any of these.
-- Alphas of 0 turn a layer off. Textures are white art tinted by a color role.
local ART_DEFAULTS = {
	glow = 0.05, -- soft light from the top-left corner (media.glow)
	glowTint = false, -- a color role that tints the glow (false = white light)
	contours = 0.06, -- corner art on large panels (media.contours, tinted "contour"), cropped not scaled
	contourSize = 512, -- the corner art file's size in px
	grain = 0.06, -- tiled texture over the whole panel (media.grain)
	vignette = 0.45, -- dark inner edge, black at this alpha
	outer = 2, -- px of frameDark edge outside the rule (0 = none)
	inset = 5, -- px from the edge to the thin "frame" rule
	rule = 0.45, -- the rule's alpha
	subtleRule = 0.22, -- the rule's alpha on subtle panels (widgets and toasts over the game world)
	ornaments = false, -- the flourish under titles and on the title line (media.flourish, tinted "frame")
	opacity = true, -- the Tomte window's Background opacity setting applies
}

-- The art every theme gets unless it names its own (Cartographer's, made by tools/theme_art.py).
local MEDIA_DEFAULTS = {
	grain = MEDIA .. "Theme\\Grain",
	contours = MEDIA .. "Theme\\Contours",
	flourish = MEDIA .. "Theme\\Flourish",
	glow = MEDIA .. "Theme\\Glow",
}

local Theme = {
	MEDIA = MEDIA,
	colors = {},
	media = {},
	art = {},
}
ns.Theme = Theme
Theme.DEFAULT = DEFAULT

-- For theme files: "#rrggbb" (+ alpha) → { r, g, b, a }.
function Theme.HexColor(hex, alpha)
	local r, g, b = hex:match("^#(%x%x)(%x%x)(%x%x)$")
	return { tonumber(r, 16) / 255, tonumber(g, 16) / 255, tonumber(b, 16) / 255, alpha }
end

-- For theme files: a Blizzard color global (a ColorMixin like NORMAL_FONT_COLOR), or `hex` where it's missing (the
-- unit tests).
function Theme.GlobalColor(name, hex, alpha)
	local c = _G[name]
	if type(c) == "table" and type(c.r) == "number" then
		return { c.r, c.g, c.b, alpha }
	end
	return Theme.HexColor(hex, alpha)
end

-- For theme files: the game's own font in every role. STANDARD_TEXT_FONT already is the right one for each client
-- language.
function Theme.ClientFonts()
	return { title = STANDARD_TEXT_FONT, body = STANDARD_TEXT_FONT, number = STANDARD_TEXT_FONT }
end

-- Adds a theme. def:
--   label   the Settings dropdown text
--   order   sort key in the dropdown (lower first)
--   colors  { [role] = { r, g, b[, a] } }, every role tests/test_theme.lua lists
--   fonts   function(locale) → { title, body, number[, label] } file paths (fall back to the client's font where a
--           file has no glyphs for that language). label (small UI labels: buttons, list headers) defaults to title.
--   panel   "art" (layered texture panel, tuned by `art`) or "blizzard" (the tooltip's nine-slice border)
--   art     optional overrides of ART_DEFAULTS
--   media   optional { grain, contours, flourish, glow } texture paths over MEDIA_DEFAULTS
--   fontBump optional { [fontRole] = points } added to sizes when that role isn't the client's font (a font with a
--           small x-height reads a point small)
function Theme.Register(name, def)
	assert(type(name) == "string" and not THEMES[name], "Tomte theme: bad or duplicate name")
	THEMES[name] = def
	if name == DEFAULT and not Theme.name then
		Theme.Apply(DEFAULT) -- until Core.lua applies the saved choice
	end
end

local fonts

local function Merge(into, defaults, overrides)
	for k in pairs(into) do
		into[k] = nil
	end
	for k, v in pairs(defaults) do
		into[k] = v
	end
	for k, v in pairs(overrides or {}) do
		into[k] = v
	end
end

-- Makes `name` the theme (an unknown or missing name is the default). colors, media and art stay the same tables.
function Theme.Apply(name)
	if not THEMES[name] then
		name = DEFAULT
	end
	local t = THEMES[name]
	Theme.name, Theme.panel = name, t.panel
	Merge(Theme.colors, t.colors)
	Merge(Theme.media, MEDIA_DEFAULTS, t.media)
	Merge(Theme.art, ART_DEFAULTS, t.art)
	fonts = nil
end

-- The registered themes' names, in dropdown order.
function Theme.Names()
	local list = {}
	for name in pairs(THEMES) do
		list[#list + 1] = name
	end
	table.sort(list, function(a, b)
		local oa, ob = THEMES[a].order or 100, THEMES[b].order or 100
		if oa ~= ob then
			return oa < ob
		end
		return a < b
	end)
	return list
end

-- { { value, text } } for the Settings dropdown, in order.
function Theme.Choices()
	local list = {}
	for _, name in ipairs(Theme.Names()) do
		list[#list + 1] = { value = name, text = THEMES[name].label }
	end
	return list
end

-- A theme's definition (the tests read it).
function Theme.Get(name)
	return THEMES[name]
end

-- The flourishes under titles and on the title line.
function Theme.HasOrnaments()
	return Theme.panel == "art" and Theme.art.ornaments and true or false
end

-- `name`'s fonts for a client language (default: the current theme).
function Theme.FontsFor(locale, name)
	return THEMES[name or Theme.name].fonts(locale)
end

-- The role a theme's fonts table answers for fontRole: label falls back to title, anything unknown to body.
local function Resolve(fontRole)
	fonts = fonts or THEMES[Theme.name].fonts(GetLocale())
	fontRole = fontRole or "body"
	if not fonts[fontRole] and fontRole == "label" then
		fontRole = "title"
	end
	return fonts[fontRole] and fontRole or "body"
end

-- fontRole: "title", "label", "body", "number", or "chat" (text other players wrote: always the chat font, so it
-- shows the way it does in chat whatever language it's in).
function Theme.Font(fontRole)
	if fontRole == "chat" then
		return (ChatFontNormal:GetFont())
	end
	local role = Resolve(fontRole)
	return fonts[role]
end

-- Sizes are in the client font's points; a theme's fontBump adds to roles drawn in its own font files.
function Theme.FontSize(fontRole, size)
	if fontRole == "chat" then
		return size
	end
	local role = Resolve(fontRole)
	local bump = THEMES[Theme.name].fontBump
	if bump and bump[role] and fonts[role]:find("^Interface\\AddOns\\") then -- not on a game-font fallback
		return size + bump[role]
	end
	return size
end

-- Sets a font string's font by role: fs, "body"|"title"|"number"|"chat", size in the client font's points, flags.
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
