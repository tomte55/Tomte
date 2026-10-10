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

local ns = {}
assert(loadfile("Tomte/Core/Theme.lua"))("Tomte", ns)
local Theme = ns.Theme

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
end)

test("the font files the theme names exist", function()
	for _, path in pairs(Theme.FontsFor("enUS")) do
		local file = path:gsub("^Interface\\AddOns\\", ""):gsub("\\", "/")
		local f = io.open(file, "rb")
		assert(f, "missing " .. file)
		f:close()
	end
	for _, path in pairs(Theme.media) do
		local file = path:gsub("^Interface\\AddOns\\", ""):gsub("\\", "/") .. ".tga"
		local f = io.open(file, "rb")
		assert(f, "missing " .. file)
		f:close()
	end
end)

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

test("no hardcoded colors or fonts outside Core/Theme.lua", function()
	local hits = {}
	for _, file in ipairs(TocFiles()) do
		if file ~= "Core/Theme.lua" then
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

if failures > 0 then
	print(failures .. " failed")
	os.exit(1)
end
