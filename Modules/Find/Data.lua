local addonName, ns = ...

-- Find: pure logic (no WoW API calls; unit-tested in tests/test_find.lua). Which townsfolk match what was typed and in
-- what order: the ones in your zone first, then the rest of your continent by distance, then other continents. The
-- game is read in Find.lua; the map's search box is Modules/Map/FindBox.lua.

-- Endings dropped from a typed word, so a profession's name finds its trainers' titles: "tailoring" finds "Tailor",
-- "enchanting" "Enchanter", "alchemy" "Alchemist", "herbalism" "Herbalist".
local ENDINGS = { "ing", "ism", "y" }
local MIN_STEM = 4 -- letters: a shorter stem ("min" from "mining") would match too much

-- What was typed as words, each with the forms it may be found as (lower case). Empty text: no words.
function ns.Find_Words(text)
	local words = {}
	for word in (text or ""):lower():gmatch("%S+") do
		local forms = { word }
		for _, ending in ipairs(ENDINGS) do
			local stem = word:sub(-#ending) == ending and word:sub(1, -#ending - 1)
			if stem and #stem >= MIN_STEM then
				forms[#forms + 1] = stem
			end
		end
		words[#words + 1] = forms
	end
	return words
end

-- Whether every word (Find_Words) is somewhere in haystack (lower case), in one of its forms. No words: false (an
-- empty search finds nobody).
function ns.Find_Matches(words, haystack)
	if #words == 0 then
		return false
	end
	for _, forms in ipairs(words) do
		local found = false
		for _, form in ipairs(forms) do
			if haystack:find(form, 1, true) then
				found = true
				break
			end
		end
		if not found then
			return false
		end
	end
	return true
end

-- The text one townsperson is searched by: name, title and what kind they are (each kind's names: "Profession
-- Trainers", so "tailor trainer" finds "Journeyman Tailor"), lower case. kindNames: list of strings, nils skipped.
function ns.Find_Haystack(name, title, kindNames)
	local out = {}
	local function Add(s)
		if s then
			out[#out + 1] = tostring(s):lower()
		end
	end
	Add(name)
	Add(title)
	for _, k in ipairs(kindNames or {}) do
		Add(k)
	end
	return table.concat(out, "\n")
end

-- Sorts matches in place and marks each: here = in your zone (same mapID), dist = yards from you (same continent
-- only, else nil), far = on another continent. rows: { mapID, world = { map, x, y } or nil, name, zone }. me:
-- { mapID, world } (world nil inside an instance: then nobody has a distance). Order: your zone by distance, the rest
-- of your continent by distance, then the others by zone and name.
function ns.Find_Rank(rows, me)
	local w = me and me.world
	for _, r in ipairs(rows) do
		r.here = me ~= nil and r.mapID == me.mapID
		r.dist, r.far = nil, false
		if w and r.world then
			if r.world.map == w.map then
				local dx, dy = r.world.x - w.x, r.world.y - w.y
				r.dist = math.sqrt(dx * dx + dy * dy)
			else
				r.far = true
			end
		end
	end
	local function Group(r)
		return r.here and 1 or r.dist and 2 or 3
	end
	table.sort(rows, function(a, b)
		local ga, gb = Group(a), Group(b)
		if ga ~= gb then
			return ga < gb
		end
		if a.dist and b.dist and a.dist ~= b.dist then
			return a.dist < b.dist
		end
		if (a.zone or "") ~= (b.zone or "") then
			return (a.zone or "") < (b.zone or "")
		end
		return (a.name or "") < (b.name or "")
	end)
	return rows
end

-- Yards rounded as said aloud: to 10 under a thousand, else to 100. Returns a number.
function ns.Find_RoundYards(yards)
	local step = yards < 1000 and 10 or 100
	return math.max(step, math.floor(yards / step + 0.5) * step)
end

-- Where a match is, plainly: "here in Orgrimmar, 40 yards", "outside Orgrimmar: Durotar, 900 yards", "outside
-- Orgrimmar: Stonetalon Mountains, another continent". hereZone: your zone's name (nil: "outside your zone").
-- number: formats a whole number ("1,200"), so the pure file needs no game API.
function ns.Find_Where(r, hereZone, number)
	local dist = r.dist and (number(ns.Find_RoundYards(r.dist)) .. " yards")
	if r.here then
		return ("here in %s%s"):format(r.zone or hereZone or "your zone", dist and (", " .. dist) or "")
	end
	local outside = hereZone and ("outside " .. hereZone) or "outside your zone"
	local how = dist or (r.far and "another continent")
	return ("%s: %s%s"):format(outside, r.zone or "?", how and (", " .. how) or "")
end
