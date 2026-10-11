local addonName, ns = ...

-- Number, money and time text shared by every module. Pure Lua (unit-tested in tests/test_format.lua); loads before
-- Core.lua so data files can use it at file load. Outputs match what each module printed before it moved here.

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

-- "50,000g": only gold once there is any (detailed keeps the silver: "1,234g 56s"), else silver and copper.
-- icons = { gold, silver, copper } format strings that take the amount.
function ns.Coins(copper, detailed, icons)
	local g = floor(copper / 10000)
	local s = floor(copper / 100) % 100
	local c = copper % 100
	local parts = {}
	if g > 0 then
		parts[1] = icons.gold:format(ns.Thousands(g))
		if detailed and s > 0 then
			parts[2] = icons.silver:format(s)
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

-- "45s", "12:34" or "1:23:45" for whole seconds.
function ns.Clock(seconds)
	if seconds >= 3600 then
		return ("%d:%02d:%02d"):format(floor(seconds / 3600), floor(seconds % 3600 / 60), seconds % 60)
	elseif seconds >= 60 then
		return ("%d:%02d"):format(floor(seconds / 60), seconds % 60)
	end
	return seconds .. "s"
end
