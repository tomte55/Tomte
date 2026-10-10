local addonName, ns = ...

-- The theme: every color and font Tomte draws with, by role (docs/superpowers/specs/2026-10-10-redesign-design.md).
-- Code asks for a role (ns.UI.Color("accent"), ns.Theme.Font("title")), never for a number or a font path, so a
-- second theme later is only a second table here. Read once when frames are built: switching themes means a reload.

local MEDIA = "Interface\\AddOns\\Tomte\\Media\\"

local function Hex(hex, alpha)
	local r, g, b = hex:match("^#(%x%x)(%x%x)(%x%x)$")
	return { tonumber(r, 16) / 255, tonumber(g, 16) / 255, tonumber(b, 16) / 255, alpha }
end

local Theme = {
	name = "cartographer",
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
	media = {
		grain = MEDIA .. "Theme\\Grain",
		contours = MEDIA .. "Theme\\Contours",
		flourish = MEDIA .. "Theme\\Flourish",
		glow = MEDIA .. "Theme\\Glow",
	},
}
ns.Theme = Theme

local CINZEL = MEDIA .. "Fonts\\Cinzel-Medium.ttf"
local ALEGREYA = MEDIA .. "Fonts\\Alegreya-Regular.ttf"
local NUMBERS = MEDIA .. "Fonts\\AlegreyaNumbers-Regular.ttf"

-- Cinzel has no Cyrillic; neither font has Korean or Chinese. Those clients keep their own fonts for what's missing.
local CLIENT_FONTS = { koKR = true, zhCN = true, zhTW = true }

function Theme.FontsFor(locale)
	if CLIENT_FONTS[locale] then
		return { title = STANDARD_TEXT_FONT, body = STANDARD_TEXT_FONT, number = STANDARD_TEXT_FONT }
	end
	local title = CINZEL
	if locale == "ruRU" then
		title = GameFontNormalHuge:GetFont()
	end
	return { title = title, body = ALEGREYA, number = NUMBERS }
end

local fonts

-- fontRole: "title", "body", "number", or "chat" (text other players wrote: always the chat font, so it shows the
-- way it does in chat whatever language it's in).
function Theme.Font(fontRole)
	if fontRole == "chat" then
		return (ChatFontNormal:GetFont())
	end
	fonts = fonts or Theme.FontsFor(GetLocale())
	return fonts[fontRole or "body"] or fonts.body
end

-- Alegreya has a small x-height: one point up keeps body text the size the old fonts had at the same number.
function Theme.FontSize(fontRole, size)
	fonts = fonts or Theme.FontsFor(GetLocale())
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
