local addonName, ns = ...

-- Teleports data and pure logic (unit-tested with plain Lua). Dungeon (Hero's Path) and mage teleports aren't listed
-- here: Owned.lua finds them in the spellbook's flyouts. What's here is everything that isn't in a flyout. A wrong or
-- unowned ID just doesn't show up.

-- Class spells outside flyouts.
ns.TP_CLASS_SPELLS = {
	556, -- Astral Recall (Shaman)
	50977, -- Death Gate (Death Knight)
	193753, -- Dreamwalk (Druid)
	18960, -- Teleport: Moonglade (Druid)
	126892, -- Zen Pilgrimage (Monk)
}

ns.TP_HEARTHSTONE = 6948

-- Other hearthstone-like items (not toys).
ns.TP_HEARTH_ITEMS = {
	110560, -- Garrison Hearthstone
	140192, -- Dalaran Hearthstone
}

-- Hearthstone toys: same destination as your Hearthstone. /tomte tp scan checks them against the toy box.
ns.TP_HEARTH_TOYS = {
	54452, -- Ethereal Portal
	64488, -- The Innkeeper's Daughter
	93672, -- Dark Portal
	142542, -- Tome of Town Portal
	162973, -- Greatfather Winter's Hearthstone
	163045, -- Headless Horseman's Hearthstone
	165669, -- Lunar Elder's Hearthstone
	165670, -- Peddlefeet's Lovely Hearthstone
	165802, -- Noble Gardener's Hearthstone
	166746, -- Fire Eater's Hearthstone
	166747, -- Brewfest Reveler's Hearthstone
	168907, -- Holographic Digitalization Hearthstone
	172179, -- Eternal Traveler's Hearthstone
	180290, -- Night Fae Hearthstone
	182773, -- Necrolord Hearthstone
	183716, -- Venthyr Sinstone
	184353, -- Kyrian Hearthstone
	188952, -- Dominated Hearthstone
	190196, -- Enlightened Hearthstone
	190237, -- Broker Translocation Matrix
	193588, -- Timewalker's Hearthstone
	200630, -- Ohn'ir Windsage's Hearthstone
	206195, -- Path of the Naaru
	208704, -- Deepdweller's Earthen Hearthstone
	209035, -- Hearthstone of the Flame
	210455, -- Draenic Hologem
	212337, -- Stone of the Hearth
	228940, -- Notorious Thread's Hearthstone
}

-- Teleport toys and items with a fixed destination. kind = "toy" | "item".
ns.TP_ITEMS = {
	{ kind = "toy", id = 18984 }, -- Dimensional Ripper - Everlook
	{ kind = "toy", id = 18986 }, -- Ultrasafe Transporter: Gadgetzan
	{ kind = "toy", id = 30542 }, -- Dimensional Ripper - Area 52
	{ kind = "toy", id = 30544 }, -- Ultrasafe Transporter: Toshley's Station
	{ kind = "toy", id = 48933 }, -- Wormhole Generator: Northrend
	{ kind = "toy", id = 87215 }, -- Wormhole Generator: Pandaria
	{ kind = "toy", id = 112059 }, -- Wormhole Centrifuge (Draenor)
	{ kind = "toy", id = 151652 }, -- Wormhole Generator: Argus
	{ kind = "toy", id = 198156 }, -- Wyrmhole Generator: Dragon Isles
	{ kind = "toy", id = 221966 }, -- Wormhole Generator: Khaz Algar
	{ kind = "toy", id = 140324 }, -- Mobile Telemancy Beacon (Suramar)
	{ kind = "toy", id = 129276 }, -- Beginner's Guide to Dimensional Rifting (Azsuna)
	{ kind = "item", id = 46874 }, -- Argent Crusader's Tabard
	{ kind = "item", id = 32757 }, -- Blessed Medallion of Karabor
	{ kind = "item", id = 28585 }, -- Ruby Slippers
	{ kind = "item", id = 103678 }, -- Time-Lost Artifact
	{ kind = "item", id = 37863 }, -- Direbrew's Remote
	{ kind = "item", id = 128353 }, -- Admiral's Compass
	{ kind = "item", id = 118662 }, -- Bladespire Relic
	{ kind = "item", id = 40586 }, -- Band of the Kirin Tor
	{ kind = "item", id = 44934 }, -- Loop of the Kirin Tor
	{ kind = "item", id = 44935 }, -- Ring of the Kirin Tor
	{ kind = "item", id = 40585 }, -- Signet of the Kirin Tor
	{ kind = "item", id = 45688 }, -- Inscribed Band of the Kirin Tor
	{ kind = "item", id = 45689 }, -- Inscribed Loop of the Kirin Tor
	{ kind = "item", id = 45690 }, -- Inscribed Ring of the Kirin Tor
	{ kind = "item", id = 45691 }, -- Inscribed Signet of the Kirin Tor
	{ kind = "item", id = 48954 }, -- Etched Band of the Kirin Tor
	{ kind = "item", id = 48955 }, -- Etched Loop of the Kirin Tor
	{ kind = "item", id = 48956 }, -- Etched Ring of the Kirin Tor
	{ kind = "item", id = 48957 }, -- Etched Signet of the Kirin Tor
	{ kind = "item", id = 51557 }, -- Runed Signet of the Kirin Tor
	{ kind = "item", id = 51558 }, -- Runed Loop of the Kirin Tor
	{ kind = "item", id = 51559 }, -- Runed Ring of the Kirin Tor
	{ kind = "item", id = 51560 }, -- Runed Band of the Kirin Tor
	{ kind = "item", id = 139599 }, -- Empowered Ring of the Kirin Tor
}

ns.TP_SECTIONS = {
	{ key = "favorites", title = "Favorites" },
	{ key = "here", title = "To this map" },
	{ key = "hearth", title = "Hearthstone" },
	{ key = "dungeon", title = "Dungeons" },
	{ key = "class", title = "Class" },
	{ key = "items", title = "Items and toys" },
}

-- The place a teleport's description names, or nil: "Teleport to the entrance to The Stonevault." -> "The Stonevault",
-- "Teleports the caster to Stormwind." -> "Stormwind", "Creates a portal, teleporting group members ... to
-- Orgrimmar." -> "Orgrimmar".
function ns.Tp_Destination(desc)
	if not desc or desc == "" then
		return nil
	end
	local place = desc:match("entrance to (.-)%.%s") or desc:match("entrance to (.-)%.$")
		or desc:match("[Tt]eleport.- to (.-)%.%s") or desc:match("[Tt]eleport.- to (.-)%.$")
		or desc:match("[Tt]eleport.- to (.-)[,%.]")
	if place then
		place = place:gsub("^the entrance to ", "")
	end
	return place
end

-- true when text names one of the places, or is part of one ("Stormwind" for "Stormwind City"). Case-insensitive;
-- anything shorter than 4 letters is skipped so stray short words don't match.
function ns.Tp_Mentions(text, names)
	if not text or #text < 4 then
		return false
	end
	local lower = text:lower()
	for _, name in ipairs(names) do
		if #name >= 4 then
			local n = name:lower()
			if lower:find(n, 1, true) or n:find(lower, 1, true) then
				return true
			end
		end
	end
	return false
end

-- entries: { key, section, name, known, current (this M+ season), favorite, here (goes to the viewed map) }.
-- opts = { showUnearned, hidden = { [sectionKey] = true } }. Returns { { key, title, entries } } in display order.
-- Unknown entries only show for current-season dungeons with showUnearned on, after the known ones.
function ns.Tp_Sections(entries, opts)
	local hidden = opts.hidden or {}
	local buckets = {}
	for _, s in ipairs(ns.TP_SECTIONS) do
		buckets[s.key] = {}
	end
	for _, e in ipairs(entries) do
		local visible = e.known or (e.section == "dungeon" and e.current and opts.showUnearned)
		if visible then
			if e.known and e.favorite then
				table.insert(buckets.favorites, e)
			end
			if e.known and e.here then
				table.insert(buckets.here, e)
			end
			table.insert(buckets[e.section], e)
		end
	end
	local function rank(e)
		local r = 0
		if not e.known then
			r = r + 2
		end
		if e.section == "dungeon" and not e.current then
			r = r + 1
		end
		return r
	end
	local out = {}
	for _, s in ipairs(ns.TP_SECTIONS) do
		local list = buckets[s.key]
		if #list > 0 and not hidden[s.key] then
			table.sort(list, function(a, b)
				local ra, rb = rank(a), rank(b)
				if ra ~= rb then
					return ra < rb
				end
				if (a.order or 0) ~= (b.order or 0) then
					return (a.order or 0) < (b.order or 0)
				end
				return a.name < b.name
			end)
			out[#out + 1] = { key = s.key, title = s.title, entries = list }
		end
	end
	return out
end

-- "1:23:45", "12:34" or "45s" for a cooldown in seconds.
function ns.Tp_FormatCooldown(seconds)
	seconds = math.ceil(seconds)
	if seconds >= 3600 then
		return ("%d:%02d:%02d"):format(seconds / 3600, (seconds % 3600) / 60, seconds % 60)
	elseif seconds >= 60 then
		return ("%d:%02d"):format(seconds / 60, seconds % 60)
	end
	return seconds .. "s"
end
