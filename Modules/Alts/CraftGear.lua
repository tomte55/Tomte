local addonName, ns = ...

-- Alts page, Crafting tab: what a craft means for a character's gear (the "Gear for" filter). Item info, worn item
-- levels and the row mark and tooltip text. CraftTab.lua has the shared helpers and entry points, CraftResults.lua
-- the list and CraftDetail.lua the detail that show these.

local S = ns.AltsCraft_State
local UI = ns.UI
local ClassName, ProfName = ns.AltsCraft_ClassName, ns.AltsCraft_ProfName -- CraftTab.lua

-- Gear for a character ---------------------------------------------------------------------------------------

local Loaded, Ilvl = ns.AltsItem_Loaded, ns.AltsItem_Ilvl -- ProfGear.lua

-- The character the "Gear for" filter names, nil for anyone.
local function ForChar()
	local v = S.db.filterFor
	if v == "me" then
		return S.db.chars[UnitGUID("player")]
	end
	return v and v ~= "all" and S.db.chars[v] or nil
end

-- What Alts_GearFor needs about a recipe's item (classID, subclassID, equipLoc, primaries), nil for recipes that make
-- no item. Kept once the main stats have read; until then primaries is nil (not held against it).
local itemInfo = {}
local function ItemInfo(recipe)
	local itemID = recipe.item
	if not itemID then
		return nil
	end
	if itemInfo[itemID] then
		return itemInfo[itemID]
	end
	local _, _, _, equipLoc, _, classID, subclassID = C_Item.GetItemInfoInstant(itemID)
	if not classID then
		return nil
	end
	local info = { classID = classID, subclassID = subclassID, equipLoc = equipLoc }
	if equipLoc == "" or equipLoc == "INVTYPE_NON_EQUIP_IGNORE" then
		info.primaries = {} -- not worn: nothing to load
		itemInfo[itemID] = info
		return info
	end
	local link = recipe.out and recipe.out[2] or ("item:" .. itemID)
	if Loaded(itemID, recipe.out and link or nil) then
		local stats = ns.Gear_NormalizeStats(C_Item.GetItemStats(link))
		info.primaries = stats.PRIMARY or {}
		itemInfo[itemID] = info
	end
	return info
end

-- c's worn item levels for Alts_WornFor ({ [slot] = ilvl | false, twoHand, offWeapon }), kept per gear snapshot.
local wornCache = {}
local function Worn(c)
	local cached = wornCache[c.guid]
	if cached and cached.at == c.gearAt and cached.complete then
		return cached.worn
	end
	local worn, complete = {}, true
	for slot, link in pairs(c.gear or {}) do
		worn[slot] = Ilvl(link)
		complete = complete and worn[slot] ~= false
	end
	local main = c.gear and c.gear[16]
	if main then
		local _, _, _, loc, _, _, sub = C_Item.GetItemInfoInstant(main)
		-- INVTYPE_RANGEDRIGHT is guns, crossbows and wands; a wand (Enum.ItemWeaponSubclass 19) leaves the off hand free.
		worn.twoHand = loc == "INVTYPE_2HWEAPON" or loc == "INVTYPE_RANGED" or (loc == "INVTYPE_RANGEDRIGHT" and sub ~= 19)
	end
	local off = c.gear and c.gear[17]
	if off then
		local _, _, _, _, _, classID = C_Item.GetItemInfoInstant(off)
		worn.offWeapon = classID == Enum.ItemClass.Weapon -- a shield or held-in-off-hand item is Armor
	end
	wornCache[c.guid] = { at = c.gearAt, worn = worn, complete = complete }
	return worn
end

-- The quality a craft is compared at: the craft's own pick, else "Compare crafted gear at" (nil: the range).
local function CompareQuality(own)
	return own or ns.AltsProf_GearQuality()
end

-- Everything the row mark, its tooltip and the detail line say about a recipe for c, compared at quality q (nil:
-- every quality): { kind ("gear" | "tool"), lo, hi (item levels at the lowest and highest quality, or both at q;
-- nil: not read yet, or loading), quality (q when it applied), unread (q asked for but only the range is stored),
-- target (Alts_WornFor), mark, gain (Alts_Upgrade) }, nil when c can't use it.
local function ForInfo(recipe, c, q)
	local kind = ns.Alts_GearFor(ItemInfo(recipe), c)
	if not kind then
		return nil
	end
	local r = { kind = kind }
	local loLink, hiLink, exact = ns.Alts_QualityLinks(recipe, q)
	if loLink then
		local lo, hi = Ilvl(loLink), Ilvl(hiLink)
		r.lo, r.hi = lo or nil, hi or nil
		r.loading = lo == false or hi == false
		r.quality = exact and ns.Alts_ClampQuality(recipe, q) or nil
		r.unread = q ~= nil and not exact and (recipe.v or 0) < 4 -- read before every quality's link was stored
	end
	if kind == "gear" and c.gear then
		r.target = ns.Alts_WornFor(ItemInfo(recipe).equipLoc, Worn(c))
	elseif kind == "tool" then
		local base, profKind = ns.AltsProf_ItemOf(recipe.item)
		r.target = base and ns.AltsProf_Target(c, base, profKind)
		r.noProfGear = not c.profGear
	end
	if r.target then
		r.mark, r.gain = ns.Alts_Upgrade(r.lo, r.hi, r.target)
	end
	return r
end

local function IlvlRange(r)
	if r.lo and r.hi and r.lo ~= r.hi then
		return ("%d-%d"):format(r.lo, r.hi)
	end
	return tostring(r.hi or r.lo)
end

-- The row mark: "+13" green (an upgrade at every quality), yellow (only at the higher qualities), "new" (empty
-- slot), a dim "-" when it isn't one.
local function MarkText(r)
	if not r or not r.mark then
		return ""
	elseif r.mark == "empty" then
		return UI.Wrap("new", "success")
	elseif r.mark == "sure" then
		return UI.Wrap(("+%d"):format(r.gain), "success")
	elseif r.mark == "top" then
		return UI.Wrap(("+%d"):format(r.gain), "warning")
	end
	return UI.Wrap("-", "textFaint")
end

-- One line on what the craft means for c (row tooltip and the detail).
local function ForText(r, c, recipe)
	local name = ClassName(c)
	if not r then
		return ("%s can't use this."):format(name)
	elseif not recipe.out then
		return ("Item level not read yet: open %s on a crafter once."):format(ProfName(recipe.base))
	elseif r.loading or not r.hi then
		return "Item level loading..."
	end
	-- "Item level 606 at quality 5", or the range when no quality is picked (or only the range has been read).
	local ilvl = r.quality and ("Item level %d at quality %d"):format(r.hi, r.quality)
		or ("Item level %s by quality"):format(IlvlRange(r))
	local unread = r.unread and (" Open %s on a crafter once to read every quality."):format(ProfName(recipe.base)) or ""
	if r.kind == "tool" and r.noProfGear then
		return ("%s. %s's profession gear hasn't been read yet: log in on them once.%s"):format(ilvl, name, unread)
	end
	local t = r.target
	local where
	if not t then
		where = ""
	elseif t.twoHand then
		return ("%s. %s wears a two-hander, so an off-hand item can't be compared.%s"):format(ilvl, name, unread)
	elseif t.loading then
		return ("%s (%s's gear is loading).%s"):format(ilvl, name, unread)
	elseif t.ilvl then
		where = (", %s wears %d (%s)"):format(name, t.ilvl, t.name)
	else
		where = (", %s has a free %s slot"):format(name, t.name:lower())
	end
	local verdict = ""
	if r.mark == "sure" and r.quality then
		verdict = ": " .. UI.Wrap(("an upgrade (+%d)"):format(r.gain), "success")
	elseif r.mark == "sure" then
		verdict = ": " .. UI.Wrap(("an upgrade at every quality (+%d to +%d)"):format(r.gain, r.hi - t.ilvl), "success")
	elseif r.mark == "top" then
		verdict = ": " .. UI.Wrap(("an upgrade only at the higher qualities (up to +%d)"):format(r.gain), "warning")
	elseif r.mark == "no" then
		verdict = ": not an upgrade"
	elseif r.mark == "empty" then
		verdict = ": " .. UI.Wrap("fills it", "success")
	end
	return ("%s%s%s.%s"):format(ilvl, where, verdict, unread)
end

ns.AltsCraft_ForChar = ForChar
ns.AltsCraft_CompareQuality = CompareQuality
ns.AltsCraft_ForInfo = ForInfo
ns.AltsCraft_MarkText = MarkText
ns.AltsCraft_ForText = ForText
