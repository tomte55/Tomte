local addonName, ns = ...

-- Loot: pure logic (no WoW API calls; unit-tested in tests/test_loot.lua). Turns the loot slots Read.lua reads into
-- the lines the window's looks (Look*.lua) and the feed (Feed.lua) show: sorting, folding junk, paging, the Panel
-- look's featured item, the small text after each line, whether the game auto-loots (fast loot) and whether taken
-- loot goes to the feed, which boss loot counts as valuable, which currency gains are worth a line, the loot
-- source's title and reputation gains read from the game's chat text.
--
-- An entry (one loot slot, Read.lua): { slot, kind = "item" | "money" | "currency" | "none", name, icon, quantity,
--   quality, locked, quest = "starts" | "item" | nil, link, itemID, currencyID, classID, subclassID,
--   subType (the item's localized subtype: "Cloth", "Cooking"), toy, sell (vendor copper each), value and stale
--   (Gold & value's copper each), owned, newLook, verdict = { text, role, upgrade, maybe } (Gear Check), taken }

local QUALITY_POOR = 0 -- Enum.ItemQuality
local QUALITY_COMMON = 1
local QUALITY_EPIC = 4
local QUALITY_LEGENDARY = 5
local CLASS_WEAPON, CLASS_ARMOR, CLASS_MISC, CLASS_BATTLEPET = 2, 4, 15, 17 -- Enum.ItemClass
local MISC_JUNK, MISC_PET, MISC_MOUNT = 0, 2, 5 -- Enum.ItemMiscellaneousSubclass
local JUNK_FOLD_MIN = 2 -- a single junk item keeps its own line
local KIND_ORDER = { money = 1, currency = 2, item = 3 } -- coin first, as the game lists it
local QUESTION_ICON = 134400 -- inv_misc_questionmark: a currency without its own icon (a hidden tracker)
-- Description markers on the game's internal currencies ("(Hidden)", "DNT" = do not translate).
local HIDDEN_MARKERS = { "(Hidden)", "DNT" }

-- Fast loot -----------------------------------------------------------------------------------------------------

-- Whether the game auto-loots this window: LOOT_READY's autoloot payload when it could be read (a boolean), else the
-- auto-loot setting (CVar autoLootDefault) flipped while the auto-loot key (the AUTOLOOTTOGGLE modifier) is held.
function ns.Loot_ShouldAutoLoot(payload, cvar, modifier)
	if type(payload) == "boolean" then
		return payload
	end
	return (cvar == true) ~= (modifier == true)
end

-- Whether what's taken from a loot window goes to the feed: always with auto loot (the feed is how auto loot shows
-- up, stuck loot taken from the window included), by hand only while "Show hand-looted items in the feed" is on.
function ns.Loot_FeedsTaken(auto, feedManual)
	return auto == true or feedManual == true
end

-- Entries ---------------------------------------------------------------------------------------------------------

function ns.Loot_IsGear(e)
	return e.kind == "item" and (e.classID == CLASS_WEAPON or e.classID == CLASS_ARMOR)
end

function ns.Loot_IsJunk(e)
	return e.kind == "item" and e.quality == QUALITY_POOR and e.quest == nil
end

local function HasValue(e)
	return e.value ~= nil and e.value > 0
end

-- Copper for the whole stack: Gold & value's price, else (none, or 0) the vendor price; nil when neither is known.
function ns.Loot_Worth(e)
	local each = HasValue(e) and e.value or e.sell
	if not each or each <= 0 then
		return nil
	end
	return each * math.max(e.quantity or 1, 1)
end

local function KindRank(e)
	return KIND_ORDER[e.kind] or 4
end

-- Coin, then currency, then items: quest items first, then by quality (best first), then in the game's slot order.
function ns.Loot_Compare(a, b)
	local ka, kb = KindRank(a), KindRank(b)
	if ka ~= kb then
		return ka < kb
	end
	if (a.quest ~= nil) ~= (b.quest ~= nil) then
		return a.quest ~= nil
	end
	local qa, qb = a.quality or QUALITY_COMMON, b.quality or QUALITY_COMMON
	if qa ~= qb then
		return qa > qb
	end
	return (a.slot or 0) < (b.slot or 0)
end

local function VerdictRank(e)
	local v = e.verdict
	if v and v.upgrade then
		return 2
	elseif v and v.maybe then
		return 1
	end
	return 0
end

-- The best item, as an index into entries: an upgrade (Gear Check) first, then the most valuable, then the best
-- quality. Only items count, and only those `allow` accepts (default: all); nil when there are none.
function ns.Loot_BestIndex(entries, allow)
	local best, bestKey
	for i, e in ipairs(entries) do
		if e.kind == "item" and not ns.Loot_IsJunk(e) and (not allow or allow(e)) then
			local key = { VerdictRank(e), ns.Loot_Worth(e) or 0, e.quality or QUALITY_COMMON }
			local better = not bestKey
			if bestKey then
				for k = 1, #key do
					if key[k] ~= bestKey[k] then
						better = key[k] > bestKey[k]
						break
					end
				end
			end
			if better then
				best, bestKey = i, key
			end
		end
	end
	return best
end

-- What deserves the Panel look's big spot: a Gear Check upgrade or a valuable item (Loot_IsValuable), still there.
local function Featurable(e)
	if e.taken then
		return false
	end
	if e.verdict and e.verdict.upgrade then
		return true
	end
	return ns.Loot_IsValuable({ classID = e.classID, subclassID = e.subclassID, quality = e.quality, toy = e.toy })
end

-- The item for the Panel look's big spot, as an index into entries; nil when nothing deserves it (then every item
-- is a row). The best of them by Loot_BestIndex's order.
function ns.Loot_FeaturedIndex(entries)
	return ns.Loot_BestIndex(entries, Featurable)
end

-- Lines -------------------------------------------------------------------------------------------------------------
-- A line is { entry = e } or, for folded junk, { junk = { entries }, quantity, worth, icon, taken }.

-- opts.foldJunk: two or more junk items become one line at the end. opts.skip: an entry to leave out (the Panel's
-- featured item, shown on its own). opts.hideTaken: what's been taken makes no line (the window shows only what's
-- left). opts.skipMoney: coin makes no line (the Panel shows it in its footer). Entries of kind "none" (an emptied
-- slot) never make a line.
function ns.Loot_Lines(entries, opts)
	opts = opts or {}
	local list, junk = {}, {}
	for _, e in ipairs(entries) do
		if e.kind ~= "none" and e ~= opts.skip and not (opts.hideTaken and e.taken)
			and not (opts.skipMoney and e.kind == "money") then
			if opts.foldJunk and ns.Loot_IsJunk(e) then
				junk[#junk + 1] = e
			else
				list[#list + 1] = e
			end
		end
	end
	if #junk < JUNK_FOLD_MIN then
		for _, e in ipairs(junk) do
			list[#list + 1] = e
		end
		junk = {}
	end
	table.sort(list, ns.Loot_Compare)
	local lines = {}
	for i, e in ipairs(list) do
		lines[i] = { entry = e }
	end
	if #junk > 0 then
		table.sort(junk, ns.Loot_Compare)
		local line = { junk = junk, quantity = 0, worth = 0, icon = junk[1].icon, taken = true }
		for _, e in ipairs(junk) do
			line.quantity = line.quantity + math.max(e.quantity or 1, 1)
			line.worth = line.worth + (ns.Loot_Worth(e) or 0)
			line.taken = line.taken and e.taken == true
		end
		lines[#lines + 1] = line
	end
	return lines
end

-- The entries a line stands for.
function ns.Loot_LineEntries(line)
	return line.junk or { line.entry }
end

-- One page of lines: the lines on it, the page (kept within range) and the number of pages (at least 1).
function ns.Loot_Page(lines, perPage, page)
	perPage = math.max(perPage or 1, 1)
	local pages = math.max(math.ceil(#lines / perPage), 1)
	page = math.min(math.max(page or 1, 1), pages)
	local out = {}
	for i = (page - 1) * perPage + 1, math.min(page * perPage, #lines) do
		out[#out + 1] = lines[i]
	end
	return out, page, pages
end

-- Slots that can still be taken (not taken, not locked), in slot order.
function ns.Loot_Takeable(entries)
	local slots = {}
	for _, e in ipairs(entries) do
		if e.kind ~= "none" and not e.taken and not e.locked then
			slots[#slots + 1] = e.slot
		end
	end
	table.sort(slots)
	return slots
end

-- How many slots still hold something (locked ones too): after auto-loot, anything here is stuck and needs the window.
function ns.Loot_Remaining(entries)
	local n = 0
	for _, e in ipairs(entries) do
		if e.kind ~= "none" and not e.taken then
			n = n + 1
		end
	end
	return n
end

-- Text after a line --------------------------------------------------------------------------------------------------

function ns.Loot_QuantityText(quantity)
	if quantity and quantity > 1 then
		return "x" .. ns.Thousands(quantity)
	end
	return ""
end

local function PriceText(copper, stale)
	return ns.Price(copper) .. (stale and "?" or "")
end

-- The stack's price as text (a "?" after a stale auction price); nil when it has no worth.
function ns.Loot_WorthText(e)
	local worth = ns.Loot_Worth(e)
	return worth and PriceText(worth, HasValue(e) and e.stale) or nil
end

-- The small parts after an entry's name as { text, role } (theme color roles), each only when its extra is on.
-- opts: { newLook, owned, value, verdict = "tag" (a short Upgrade tag, List) | "full" (Gear Check's headline) }.
-- Locked and quest items say so first.
function ns.Loot_Details(e, opts)
	opts = opts or {}
	local out = {}
	local function add(text, role)
		out[#out + 1] = { text = text, role = role }
	end
	if e.locked and not e.taken then
		add("Can't loot", "danger")
	end
	if e.quest == "starts" then
		add("Starts a quest", "info")
	elseif e.quest == "item" then
		add("Quest", "warning")
	end
	if opts.newLook and e.newLook then
		add("New look", "accent")
	end
	local v = opts.verdict and e.verdict
	if v then
		if opts.verdict == "full" and v.text then
			add(v.text, v.role or "textMuted")
		elseif v.upgrade then
			add("Upgrade", "success")
		elseif v.maybe then
			add("Maybe upgrade", "warning")
		end
	end
	if opts.owned and e.owned and e.owned > 0 and not ns.Loot_IsGear(e) then
		add(ns.Thousands(e.owned) .. " owned", "textMuted")
	end
	if opts.value then
		local worth = ns.Loot_WorthText(e)
		if worth then
			add(worth, "textMuted")
		end
	end
	return out
end

function ns.Loot_JunkName(quantity)
	return quantity == 1 and "1 junk item" or (ns.Thousands(quantity) .. " junk items")
end

-- The folded junk line's worth, when the value extra is on.
function ns.Loot_JunkDetails(line, opts)
	if opts and opts.value and line.worth and line.worth > 0 then
		return { { text = PriceText(line.worth), role = "textMuted" } }
	end
	return {}
end

-- Where the loot came from ----------------------------------------------------------------------------------------

-- s = { fishing, fishingName, names = { known source names }, sources = number of distinct sources }.
function ns.Loot_SourceTitle(s)
	if s.fishing then
		return s.fishingName or "Fishing"
	end
	local name = s.names and s.names[1]
	local n = s.sources or 0
	if n > 1 then
		return name and (name .. " +" .. (n - 1)) or (n .. " corpses")
	end
	return name or "Loot"
end

-- Boss loot banner ---------------------------------------------------------------------------------------------------

-- Valuable boss loot: mounts, pets, toys, legendaries and class set tokens (epic "junk" class items).
-- info = { classID, subclassID, quality, toy }.
function ns.Loot_IsValuable(info)
	if info.toy then
		return true
	end
	local quality = info.quality or QUALITY_COMMON
	if quality >= QUALITY_LEGENDARY or info.classID == CLASS_BATTLEPET then
		return true
	end
	if info.classID == CLASS_MISC then
		if info.subclassID == MISC_MOUNT or info.subclassID == MISC_PET then
			return true
		end
		return info.subclassID == MISC_JUNK and quality >= QUALITY_EPIC
	end
	return false
end

-- Currency lines ----------------------------------------------------------------------------------------------------

-- Whether a currency gain is one the player would recognize, from C_CurrencyInfo's CurrencyInfo. The game also counts
-- internal trackers as currencies ("11.0 Delves - System - Seasonal Affix ..."): they have no description, a generic
-- icon or a "(Hidden)" / "DNT" note in it, and the game itself never shows them.
function ns.Loot_IsShownCurrency(info)
	if not (info and info.discovered and not info.isHeader and info.name and info.name ~= "") then
		return false
	end
	if not info.iconFileID or info.iconFileID == 0 or info.iconFileID == QUESTION_ICON then
		return false
	end
	local description = info.description
	if not description or description == "" then
		return false
	end
	for _, marker in ipairs(HIDDEN_MARKERS) do
		if description:find(marker, 1, true) then
			return false
		end
	end
	return true
end

-- Reputation lines --------------------------------------------------------------------------------------------------

-- The game's "reputation increased" strings (FACTION_STANDING_INCREASED and its bonus variants) as patterns. A
-- "%.1f" bonus becomes a capture like any other. Missing (nil) strings are skipped.
function ns.Loot_RepPatterns(formats)
	local list = {}
	for _, fmt in pairs(formats) do
		if type(fmt) == "string" and fmt ~= "" then
			local pattern, spec = ns.FormatToPattern((fmt:gsub("%%%.%d+f", "%%s")))
			list[#list + 1] = { pattern = pattern, spec = spec, plain = fmt }
		end
	end
	-- Longest first: the bonus variants start with the plain string's text.
	table.sort(list, function(a, b)
		return #a.plain > #b.plain
	end)
	return list
end

-- Faction name and amount (a number, or nil when the message doesn't say) from a reputation chat line; nil when it
-- isn't one.
function ns.Loot_ParseRep(text, patterns)
	for _, p in ipairs(patterns) do
		local captures = ns.FormatMatch(text, p.pattern, p.spec)
		if captures and captures[1] then
			return captures[1], tonumber(captures[2])
		end
	end
	return nil
end

-- Recently shown --------------------------------------------------------------------------------------------------
-- So one gain isn't shown twice (a looted currency also fires the currency event; a boss item also a loot toast).

function ns.Loot_RecentNote(recent, key, now)
	recent[key] = now
end

function ns.Loot_RecentHas(recent, key, now, window)
	local at = recent[key]
	return at ~= nil and now - at <= window
end
