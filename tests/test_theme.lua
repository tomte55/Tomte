-- Run from the AddOns folder: lua Tomte/tests/test_theme.lua
STANDARD_TEXT_FONT = "Fonts\\CLIENT.TTF"
GameFontNormalHuge = { GetFont = function()
	return "Fonts\\CLIENT_TITLE.TTF", 20, ""
end }
ChatFontNormal = { GetFont = function()
	return "Fonts\\CHAT.TTF", 14, ""
end }
local locale = "enUS"
GetLocale = function()
	return locale
end

-- Core/Theme.lua and every Themes/*.lua file, in TOC order.
local function LoadTheme()
	local ns = {}
	assert(loadfile("Tomte/Core/Theme.lua"))("Tomte", ns)
	for line in io.lines("Tomte/Tomte.toc") do
		local file = line:match("^(Themes[/\\][%w_]+%.lua)%s*$")
		if file then
			assert(loadfile("Tomte/" .. file:gsub("\\", "/")))("Tomte", ns)
		end
	end
	return ns
end

local ns = LoadTheme()
local Theme = ns.Theme
assert(Theme.name == "blizzard", "loads with the default theme")
Theme.Apply("cartographer") -- the color and font tests below are Cartographer's

local failures = 0
local function test(name, fn)
	local ok, err = pcall(fn)
	if ok then
		print("ok   " .. name)
	else
		failures = failures + 1
		print("FAIL " .. name .. ": " .. tostring(err))
	end
end
local function eq(actual, expected, label)
	if actual ~= expected then
		error((label or "value") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual), 2)
	end
end
local function endsWith(s, tail)
	return type(s) == "string" and s:sub(-#tail) == tail
end

local ROLES = { "bg", "bgTop", "bgBottom", "surface", "hover", "text", "heading", "textMuted", "textFaint", "accent",
	"accentDeep", "frame", "frameDark", "rule", "contour", "success", "warning", "danger" }

test("every color role exists with 3 or 4 numbers in 0..1", function()
	for _, role in ipairs(ROLES) do
		local c = Theme.colors[role]
		assert(c, "missing role " .. role)
		assert(#c == 3 or #c == 4, role .. " has " .. #c .. " numbers")
		for i = 1, #c do
			assert(type(c[i]) == "number" and c[i] >= 0 and c[i] <= 1, role .. "[" .. i .. "] out of range")
		end
	end
end)

test("Color returns alpha 1 when the role has none", function()
	local r, g, b, a = Theme.Color("text")
	eq(a, 1, "alpha")
	local _, _, _, a2 = Theme.Color("surface")
	eq(a2, 0.19, "surface alpha")
end)

test("an unknown role is an error, not silently black", function()
	assert(not pcall(Theme.Color, "gold"), "expected an error")
end)

test("Hex and Wrap", function()
	eq(Theme.Hex("accent"), "ffa99be0")
	eq(Theme.Hex("frameDark"), "ff0a0b0d")
	eq(Theme.Wrap("x", "danger"), "|cffd0654fx|r")
	eq(Theme.Wrap(3, "success"), "|cff8fbf7a3|r")
end)

test("Latin clients get Cinzel, Alegreya and the Numbers build", function()
	for _, loc in ipairs({ "enUS", "enGB", "deDE", "frFR", "esES", "esMX", "itIT", "ptBR" }) do
		local f = Theme.FontsFor(loc)
		assert(endsWith(f.title, "Cinzel-Medium.ttf"), loc .. " title")
		assert(endsWith(f.body, "Alegreya-Regular.ttf"), loc .. " body")
		assert(endsWith(f.number, "AlegreyaNumbers-Regular.ttf"), loc .. " number")
	end
end)

test("Russian keeps Alegreya but titles use the client's font", function()
	local f = Theme.FontsFor("ruRU")
	eq(f.title, "Fonts\\CLIENT_TITLE.TTF", "title")
	assert(endsWith(f.body, "Alegreya-Regular.ttf"), "body")
	assert(endsWith(f.number, "AlegreyaNumbers-Regular.ttf"), "number")
end)

test("Korean and Chinese use the client's fonts everywhere", function()
	for _, loc in ipairs({ "koKR", "zhCN", "zhTW" }) do
		local f = Theme.FontsFor(loc)
		eq(f.title, STANDARD_TEXT_FONT, loc .. " title")
		eq(f.body, STANDARD_TEXT_FONT, loc .. " body")
		eq(f.number, STANDARD_TEXT_FONT, loc .. " number")
	end
end)

test("Font: chat is always the chat font, unknown roles fall back to body", function()
	eq(Theme.Font("chat"), "Fonts\\CHAT.TTF", "chat")
	assert(endsWith(Theme.Font(), "Alegreya-Regular.ttf"), "default")
	assert(endsWith(Theme.Font("nope"), "Alegreya-Regular.ttf"), "unknown")
	assert(endsWith(Theme.Font("label"), "Cinzel-Medium.ttf"), "label falls back to title")
	eq(Theme.FontSize("label", 11), 11, "label takes title's bump (none)")
	eq(Theme.FontSize("nope", 11), 12, "unknown takes body's bump")
	eq(Theme.FontSize("chat", 13), 13, "chat is never bumped")
end)

test("Apply: Blizzard default swaps colors and fonts in the same tables", function()
	local colors = Theme.colors
	Theme.Apply("blizzard")
	assert(Theme.colors == colors, "colors table replaced")
	eq(Theme.name, "blizzard", "name")
	eq(Theme.panel, "blizzard", "panel")
	eq(Theme.media.grain, Theme.MEDIA .. "Theme\\Grain", "media defaults")
	eq(Theme.Hex("heading"), "ffffd100", "heading is NORMAL_FONT_COLOR's fallback")
	eq(Theme.Font("title"), STANDARD_TEXT_FONT, "title")
	eq(Theme.Font("number"), STANDARD_TEXT_FONT, "number")
	eq(Theme.FontSize("body", 12), 12, "no size bump on the client's font")
	assert(not Theme.HasOrnaments(), "no flourishes")
	for _, role in ipairs(ROLES) do
		assert(Theme.colors[role], "blizzard misses role " .. role)
	end
	Theme.Apply("cartographer")
	eq(Theme.Hex("accent"), "ffa99be0", "back to Cartographer")
	assert(endsWith(Theme.Font("title"), "Cinzel-Medium.ttf"), "Cinzel again")
	eq(Theme.FontSize("body", 12), 13, "Alegreya bump")
	assert(Theme.HasOrnaments(), "flourishes")
end)

test("Apply: an unknown or missing name is the default", function()
	eq(Theme.DEFAULT, "blizzard", "default")
	Theme.Apply("cartographer")
	Theme.Apply("neon")
	eq(Theme.name, "blizzard", "unknown")
	Theme.Apply("cartographer")
	Theme.Apply(nil)
	eq(Theme.name, "blizzard", "nil")
	eq(Theme.Hex("accent"), "ffffd100", "default colors")
	Theme.Apply("cartographer")
end)

test("Apply: Blizzard colors come from the game's globals when they exist", function()
	NORMAL_FONT_COLOR = { r = 0.5, g = 0.25, b = 0 }
	local ns2 = LoadTheme()
	NORMAL_FONT_COLOR = nil
	ns2.Theme.Apply("blizzard")
	eq(ns2.Theme.Hex("heading"), "ff804000", "heading")
	eq(ns2.Theme.Hex("accent"), "ff804000", "accent")
end)

test("Choices lists every theme once, default first", function()
	local choices = Theme.Choices()
	eq(choices[1].value, Theme.DEFAULT, "first")
	eq(choices[1].text, "Blizzard default", "label")
	local seen, labels = {}, {}
	for _, c in ipairs(choices) do
		assert(not seen[c.value], "twice: " .. c.value)
		assert(type(c.text) == "string" and c.text ~= "" and not labels[c.text], "bad or duplicate label: " .. c.value)
		seen[c.value], labels[c.text] = true, true
	end
	assert(seen.cartographer, "cartographer")
end)

-- Every registered theme ------------------------------------------------------------------------------------------

local LOCALES = { "enUS", "enGB", "deDE", "frFR", "esES", "esMX", "itIT", "ptBR", "ruRU", "koKR", "zhCN", "zhTW" }
local ART_KEYS = { glow = "number", contours = "number", contourSize = "number", grain = "number", vignette = "number",
	outer = "number", inset = "number", rule = "number", ornaments = "boolean", opacity = "boolean", glowTint = "string", subtleRule = "number" }
local MEDIA_KEYS = { grain = true, contours = true, flourish = true, glow = true }

local function FileExists(path, ext)
	local file = path:gsub("^Interface\\AddOns\\", ""):gsub("\\", "/") .. (ext or "")
	local f = io.open(file, "rb")
	if f then
		f:close()
	end
	return f ~= nil, file
end

-- WCAG contrast of two colors (alpha ignored).
local function Luminance(c)
	local function ch(v)
		return v <= 0.03928 and v / 12.92 or ((v + 0.055) / 1.055) ^ 2.4
	end
	return 0.2126 * ch(c[1]) + 0.7152 * ch(c[2]) + 0.0722 * ch(c[3])
end
local function Contrast(a, b)
	local la, lb = Luminance(a), Luminance(b)
	if la < lb then
		la, lb = lb, la
	end
	return (la + 0.05) / (lb + 0.05)
end
-- The lowest contrast each role may have against the panel fill (bg, bgTop and bgBottom, the worst of them).
-- Calibrated on Blizzard default and Cartographer.
local MIN_CONTRAST = { text = 9, heading = 7, textMuted = 4.5, textFaint = 2.8, accent = 4.5, success = 4.2,
	warning = 4.2, danger = 4.2, frame = 2 }

for _, name in ipairs(Theme.Names()) do
	test("theme " .. name .. ": colors, fonts, art, media", function()
		local def = Theme.Get(name)
		assert(def.panel == "art" or def.panel == "blizzard", "panel")
		for _, role in ipairs(ROLES) do
			local c = def.colors[role]
			assert(c, "missing role " .. role)
			assert(#c == 3 or #c == 4, role .. " has " .. #c .. " numbers")
			for i = 1, #c do
				assert(type(c[i]) == "number" and c[i] >= 0 and c[i] <= 1, role .. "[" .. i .. "] out of range")
			end
		end
		for role in pairs(def.colors) do
			local known = false
			for _, r in ipairs(ROLES) do
				known = known or r == role
			end
			assert(known, "unknown role " .. role)
		end
		for role, min in pairs(MIN_CONTRAST) do
			for _, fill in ipairs({ "bg", "bgTop", "bgBottom" }) do
				local cr = Contrast(def.colors[role], def.colors[fill])
				assert(cr >= min, ("%s on %s: contrast %.2f, needs %.1f"):format(role, fill, cr, min))
			end
		end
		for key, v in pairs(def.art or {}) do
			assert(ART_KEYS[key] and type(v) == ART_KEYS[key], "bad art key " .. key)
		end
		local tint = def.art and def.art.glowTint
		assert(not tint or def.colors[tint], "glowTint is no color role")
		for key, path in pairs(def.media or {}) do
			assert(MEDIA_KEYS[key], "bad media key " .. key)
			local ok, file = FileExists(path, ".tga")
			assert(ok, "missing " .. file)
		end
		for _, loc in ipairs(LOCALES) do
			local f = def.fonts(loc)
			for _, role in ipairs({ "title", "body", "number", "label" }) do
				local path = f[role]
				assert(type(path) == "string" or (role == "label" and path == nil), loc .. " " .. role)
				if path and path:find("^Interface\\AddOns\\") then
					assert(loc ~= "koKR" and loc ~= "zhCN" and loc ~= "zhTW", loc .. " " .. role .. ": own font on a CJK client")
					local ok, file = FileExists(path)
					assert(ok, "missing " .. file)
				end
			end
		end
		for role in pairs(def.fontBump or {}) do
			assert(role == "title" or role == "body" or role == "number", "fontBump role " .. role)
		end
		Theme.Apply(name)
		eq(Theme.name, name, "applies")
		for _, path in pairs(Theme.media) do
			local ok, file = FileExists(path, ".tga")
			assert(ok, "missing " .. file)
		end
		Theme.Apply("cartographer")
	end)
end

-- Source scan: colors and fonts come from the theme. Lua files are read from the TOC.
-- A line can opt out with a trailing "-- theme: <reason>" comment (Blizzard-defined colors and the like).
local function TocFiles()
	local files = {}
	for line in io.lines("Tomte/Tomte.toc") do
		if line:match("%.lua%s*$") then
			files[#files + 1] = line:gsub("%s+$", ""):gsub("\\", "/")
		end
	end
	return files
end

local function NumericColor(args)
	-- First three arguments as numbers: not themed unless it's pure black or white shading.
	local r, g, b = args:match("^%s*([%d%.]+)%s*,%s*([%d%.]+)%s*,%s*([%d%.]+)")
	if not r then
		return false
	end
	r, g, b = tonumber(r), tonumber(g), tonumber(b)
	if (r == 0 and g == 0 and b == 0) or (r == 1 and g == 1 and b == 1) then
		return false
	end
	return true
end

test("no hardcoded colors or fonts outside Core/Theme.lua and Themes/", function()
	local hits = {}
	for _, file in ipairs(TocFiles()) do
		if file ~= "Core/Theme.lua" and not file:find("^Themes/") then
			local n = 0
			for line in io.lines("Tomte/" .. file) do
				n = n + 1
				local code = line:gsub("%-%-.*$", "")
				if not line:find("%-%- theme:") then
					local bad
					for _, fn in ipairs({ "SetColorTexture", "SetTextColor", "SetVertexColor", "CreateColor" }) do
						for args in code:gmatch(fn .. "%(([^)]*)") do
							if NumericColor(args) then
								bad = "numeric " .. fn
							end
						end
					end
					-- A color constant: an UPPER_CASE local or a *color* field set to three numbers, one of them a
					-- fraction (local RED = { 1, 0.45, 0.35 }). Coordinates in data tables don't look like that.
					local named = code:match("^%s*local%s+[%u_][%u%d_]*%s*=%s*{") or code:lower():find("colou?r[%w_]*%s*=%s*{")
					for a, b, c in (named and code or ""):gmatch("{%s*([%d%.]+)%s*,%s*([%d%.]+)%s*,%s*([%d%.]+)%s*[,}]") do
						if (a .. b .. c):find("%.") and NumericColor(a .. "," .. b .. "," .. c) then
							bad = "color table"
						end
					end
					-- ... and an inline one picked by a condition: x and { 1, 0.82, 0.45 } or nil.
					for a, b, c in code:gmatch("[ad][nr]d?%s+{%s*([%d%.]+)%s*,%s*([%d%.]+)%s*,%s*([%d%.]+)%s*[,}]") do
						if (a .. b .. c):find("%.") and NumericColor(a .. "," .. b .. "," .. c) then
							bad = "color table"
						end
					end
					-- Tooltip lines colored with numbers (white 1, 1, 1 is fine).
					for _, fn in ipairs({ "AddLine", "AddDoubleLine", "SetText" }) do
						for args in code:gmatch(":" .. fn .. "%(([^)]*)") do
							local r, g, b = args:match(",%s*([%d%.]+)%s*,%s*([%d%.]+)%s*,%s*([%d%.]+)%s*,?[^,]*$")
							if r and NumericColor(r .. "," .. g .. "," .. b) then
								bad = "numeric " .. fn
							end
						end
					end
					if code:find("|c[fF][fF]%x%x%x%x%x%x") then
						bad = "inline |cff color"
					end
					if code:find("STANDARD_TEXT_FONT") or code:find("Fonts\\\\") then
						bad = "font path"
					end
					if code:find("UI%.GOLD") or code:find("UI%.WHITE") or code:find("UI%.GREY") or code:find("UI%.DIM")
						or code:find("UI%.BG") or code:find("UI%.BOX") or code:find("SCENE_GOLD") then
						bad = "old color constant"
					end
					if bad then
						hits[#hits + 1] = file .. ":" .. n .. " " .. bad
					end
				end
			end
		end
	end
	if #hits > 0 then
		error(#hits .. " hits:\n  " .. table.concat(hits, "\n  "))
	end
end)

-- Nothing may color or set a font while the files load: the theme is only chosen on ADDON_LOADED (Core.lua), so a
-- color read earlier would keep the default theme's. Tracks block depth by keywords (crude, but the code base is
-- plain: no keywords inside long strings).
local THEME_CALLS = { Color = true, RGB = true, RGBA = true, Hex = true, Wrap = true, Font = true, SetFont = true,
	FontSize = true, ColorObject = true }

test("no theme colors or fonts read at file load", function()
	local hits = {}
	for _, file in ipairs(TocFiles()) do
		if file ~= "Core/Theme.lua" and not file:find("^Themes/") then
			local depth, n = 0, 0
			for line in io.lines("Tomte/" .. file) do
				n = n + 1
				local code = line:gsub("%-%-.*$", ""):gsub('"[^"]*"', '""'):gsub("'[^']*'", "''")
				if depth == 0 then
					for path in code:gmatch("([%w_%.]+)%(") do
						local owner, fn = path:match("^(.-)%.?([%w_]+)$")
						if (owner == "UI" or owner == "Theme" or owner == "ns.Theme" or owner == "ns.UI")
							and THEME_CALLS[fn] and not code:find("^%s*function%s") then
							hits[#hits + 1] = file .. ":" .. n .. " " .. path
						end
					end
				end
				for _, word in ipairs({ "function", "do", "then", "repeat" }) do
					for _ in code:gmatch("%f[%w_]" .. word .. "%f[^%w_]") do
						depth = depth + 1
					end
				end
				for _, word in ipairs({ "end", "until", "elseif" }) do
					for _ in code:gmatch("%f[%w_]" .. word .. "%f[^%w_]") do
						depth = depth - 1
					end
				end
			end
			if depth ~= 0 then
				hits[#hits + 1] = file .. ": block depth " .. depth .. " at the end (scanner confused)"
			end
		end
	end
	if #hits > 0 then
		error(#hits .. " hits:\n  " .. table.concat(hits, "\n  "))
	end
end)

if failures > 0 then
	print(failures .. " failed")
	os.exit(1)
end
