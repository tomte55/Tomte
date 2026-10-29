local addonName, ns = ...

-- Number, money and time text, and patterns for Blizzard's format strings, shared by every module. Pure Lua
-- (unit-tested in tests/test_format.lua); loads before Core.lua so data files can use it at file load. Outputs match
-- what each module printed before it moved here.

local floor, abs, max = math.floor, math.abs, math.max

-- 1234567 -> "1,234,567". nil -> "0". Floors, and keeps a minus sign outside the groups ("-1,234").
function ns.Thousands(n)
	local sign, digits = tostring(floor(n or 0)):match("^(-?)(%d+)$")
	local head = (#digits - 1) % 3 + 1
	return sign .. digits:sub(1, head) .. digits:sub(head + 1):gsub("%d%d%d", ",%0")
end

-- Whole gold: 1234567890 copper -> "123,456g".
function ns.Gold(copper)
	return ns.Thousands(floor((copper or 0) / 10000)) .. "g"
end

-- A price: "12g" from a gold up, else "45s" or "80c" (so a cheap reagent isn't "0g").
function ns.Price(copper)
	copper = floor(copper or 0)
	if copper >= 10000 then
		return ns.Gold(copper)
	elseif copper >= 100 then
		return floor(copper / 100) .. "s"
	end
	return copper .. "c"
end

-- "+2,500g" / "-2,500g"; "" for nil. For gold differences (session recap, Home).
function ns.SignedGold(copper)
	if not copper then
		return ""
	end
	return (copper < 0 and "-" or "+") .. ns.Gold(abs(copper))
end

-- "50,000g": only gold once there is any (detailed keeps the silver: "1,234g 56s"; "exact" the copper too:
-- "1,234g 56s 78c"), else silver and copper. icons = { gold, silver, copper } format strings that take the amount.
function ns.Coins(copper, detailed, icons)
	local g = floor(copper / 10000)
	local s = floor(copper / 100) % 100
	local c = copper % 100
	local parts = {}
	if g > 0 then
		parts[1] = icons.gold:format(ns.Thousands(g))
		if detailed and s > 0 then
			parts[#parts + 1] = icons.silver:format(s)
		end
		if detailed == "exact" and c > 0 then
			parts[#parts + 1] = icons.copper:format(c)
		end
	else
		if s > 0 then
			parts[#parts + 1] = icons.silver:format(s)
		end
		if c > 0 or s == 0 then
			parts[#parts + 1] = icons.copper:format(c)
		end
	end
	return table.concat(parts, " ")
end

-- "now", "5m", "2h", "3d". Nil and negative count as now.
function ns.Ago(seconds)
	seconds = max(seconds or 0, 0)
	if seconds < 60 then
		return "now"
	elseif seconds < 3600 then
		return floor(seconds / 60) .. "m"
	elseif seconds < 86400 then
		return floor(seconds / 3600) .. "h"
	end
	return floor(seconds / 86400) .. "d"
end

-- Ago for a sentence: "just now", "5m ago", "2h ago".
function ns.AgoText(seconds)
	local ago = ns.Ago(seconds)
	return ago == "now" and "just now" or (ago .. " ago")
end

-- "45s", "12:34" or "1:23:45" for whole seconds.
function ns.Clock(seconds)
	if seconds >= 3600 then
		return ("%d:%02d:%02d"):format(floor(seconds / 3600), floor(seconds % 3600 / 60), seconds % 60)
	elseif seconds >= 60 then
		return ("%d:%02d"):format(floor(seconds / 60), seconds % 60)
	end
	return seconds .. "s"
end

-- Blizzard format strings as patterns ---------------------------------------------------------------------------------
-- Used by Moments (discoveries), Session recap (loot) and Friends Online (the "has come online" message).

local CAPTURES = { s = "(.+)", d = "(%d+)" }

local function Split(text, sep)
	local list = {}
	for piece in (text .. sep):gmatch("(.-)" .. sep) do
		if piece ~= "" then
			list[#list + 1] = piece
		end
	end
	return list
end

-- "Discovered: %s" -> "^Discovered: (.+)$" (also %d -> (%d+)). Other magic characters are escaped.
-- Positional specifiers ("%1$s entdeckt: %2$d ...", German) become captures too. Grammar tokens (|1a;b; and
-- |4a:b;, a choice of words such as Korean particles) match any text; right after a capture, the chosen
-- word is cut from the capture when matching. |3-n(...) (declension) keeps its inside.
-- Returns the pattern and a spec for FormatMatch (nil when plain captures in order are all it needs):
-- spec.order[capture] = argument position, spec.trims[capture] = words to cut from its end.
function ns.FormatToPattern(fmt)
	fmt = fmt:gsub("|3%-%d+%((.-)%)", "%1")
	local parts, order, trims, special = {}, {}, {}, false
	local i, n = 1, #fmt
	local lastWasCapture = false
	while i <= n do
		local pos, spec, after = fmt:match("^%%(%d+)%$([sd])()", i)
		if not pos then
			spec, after = fmt:match("^%%([sd])()", i)
		end
		local choice1, choice4 = fmt:match("^|1([^;]*;[^;]*);", i), fmt:match("^|4([^;]*);", i)
		if spec then
			parts[#parts + 1] = CAPTURES[spec]
			order[#order + 1] = pos and tonumber(pos) or #order + 1
			special = special or pos ~= nil
			i = after
			lastWasCapture = true
		elseif choice1 or choice4 then
			parts[#parts + 1] = ".-"
			if lastWasCapture then
				trims[#order] = choice1 and Split(choice1, ";") or Split(choice4, ":")
				special = true
			end
			i = i + #(choice1 or choice4) + 3
			lastWasCapture = false
		elseif fmt:find("^%%%%", i) then
			parts[#parts + 1] = "%%"
			i = i + 2
			lastWasCapture = false
		else
			parts[#parts + 1] = (fmt:sub(i, i):gsub("[%^%$%(%)%.%[%]%*%+%-%?%%]", "%%%0"))
			i = i + 1
			lastWasCapture = false
		end
	end
	return "^" .. table.concat(parts) .. "$", special and { order = order, trims = trims } or nil
end

-- text:match(pattern) as a list of captures in argument order (spec from FormatToPattern, nil = as
-- matched), or nil when it doesn't match.
function ns.FormatMatch(text, pattern, spec)
	local captures = { text:match(pattern) }
	if captures[1] == nil then
		return nil
	end
	if not spec then
		return captures
	end
	local out = {}
	for i, pos in ipairs(spec.order) do
		local capture = captures[i]
		for _, word in ipairs(spec.trims[i] or {}) do
			if #capture > #word and capture:sub(-#word) == word then
				capture = capture:sub(1, -#word - 1)
				break
			end
		end
		out[pos] = capture
	end
	return out
end
