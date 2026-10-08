local addonName, ns = ...

-- Profession gear across characters: what each one wears (Collect.lua stores the links), the best craft for each
-- tool and accessory slot from the recipes somebody knows, and which bag items are an upgrade for whom. Used by the
-- Crafting tab's "Gear for" marks, the Profession gear tab, the mailbox (Send.lua) and Next up. Everything is
-- compared by item level: profession stats aren't in C_Item.GetItemStats under documented keys, so the "+n
-- Multicraft" lines are only shown (read from the tooltip), not weighed. Pure parts in Data.lua.

-- Item loading ---------------------------------------------------------------------------------------------------

-- Item data loads on demand; whatever shows it is drawn again once a batch has arrived.
local redraw = ns.UI.Debounce(0.2, function()
	ns.AltsCraft_Refresh()
	ns.AltsProfTab_Refresh()
	ns.AltsSend_OnGearReady()
end)
local waitingFor = {} -- [itemID or link] = true while it loads

-- Whether the item's data is cached; asks for it (and redraws later) when it isn't. key: the link, for crafted items
-- whose bonus data has to load with them.
function ns.AltsItem_Loaded(itemID, key)
	if C_Item.IsItemDataCachedByID(itemID) then
		return true
	end
	key = key or itemID
	if not waitingFor[key] then
		waitingFor[key] = true
		local item = type(key) == "string" and Item:CreateFromItemLink(key) or Item:CreateFromItemID(itemID)
		item:ContinueOnItemLoad(function()
			waitingFor[key] = nil
			redraw()
		end)
	end
	return false
end

-- An item's level, false while it loads.
function ns.AltsItem_Ilvl(link)
	local itemID = link and C_Item.GetItemInfoInstant(link)
	if not (itemID and ns.AltsItem_Loaded(itemID, link)) then
		return false
	end
	return C_Item.GetDetailedItemLevelInfo(link) or false
end

-- "+45 Multicraft", "+12 Blacksmithing Skill": the item's "+n" tooltip lines, for showing what it gives.
function ns.AltsItem_StatLines(link)
	local data = link and C_TooltipInfo.GetHyperlink(link)
	local out = {}
	for _, line in ipairs(data and data.lines or {}) do
		local text = line.leftText
		if text and not (issecretvalue and issecretvalue(text)) and text:find("^%+[%d,%.]+ %a") then
			out[#out + 1] = text
		end
	end
	return out
end

-- Worn profession gear --------------------------------------------------------------------------------------------

-- A profession item's profession (base skill line) and kind ("tool" | "acc"), from a link or item ID; nil otherwise.
function ns.AltsProf_ItemOf(item)
	if not item then
		return nil
	end
	local _, _, _, equipLoc, _, classID, subclassID = C_Item.GetItemInfoInstant(item)
	return ns.Alts_ProfItem(classID, subclassID, equipLoc)
end

-- c's profession gear: { { base, kind, ilvl (false while loading), link } }, kept per snapshot once it has loaded.
local wornCache = {}
function ns.AltsProf_Worn(c)
	local cached = wornCache[c.guid]
	if cached and cached.at == c.profGearAt and cached.complete then
		return cached.worn
	end
	local worn, complete = {}, true
	for _, link in pairs(c.profGear or {}) do
		local base, kind = ns.AltsProf_ItemOf(link)
		if base then
			local ilvl = ns.AltsItem_Ilvl(link)
			worn[#worn + 1] = { base = base, kind = kind, ilvl = ilvl, link = link }
			complete = complete and ilvl ~= false
		end
	end
	table.sort(worn, function(a, b)
		return (a.ilvl or 0) > (b.ilvl or 0)
	end)
	wornCache[c.guid] = { at = c.profGearAt, worn = worn, complete = complete }
	return worn
end

-- What a profession item would replace on c (Alts_ProfTarget); nil before c's profession gear has been read.
function ns.AltsProf_Target(c, base, kind)
	if not c.profGear then
		return nil
	end
	return ns.Alts_ProfTarget(ns.AltsProf_Worn(c), base, kind)
end

-- Best crafts ---------------------------------------------------------------------------------------------------

-- [base .. ":" .. kind] = { recipeID, ... }: the recipes that make profession gear. Rebuilt when recipes change.
local index
local producers

function ns.AltsProf_RecipesChanged()
	index, producers = nil, nil
end

local function Index()
	if index then
		return index
	end
	index = {}
	for id, r in pairs(ns.altsDB.recipes) do
		local base, kind = ns.AltsProf_ItemOf(r.item)
		if base then
			local key = base .. ":" .. kind
			index[key] = index[key] or {}
			table.insert(index[key], id)
		end
	end
	return index
end

-- The best craft somebody knows for c's tool or accessory slot of a profession: { recipeID, lo, hi, mark, gain },
-- nil when none is an upgrade (or c's profession gear or the item levels haven't been read).
function ns.AltsProf_BestCraft(c, base, kind)
	local target = ns.AltsProf_Target(c, base, kind)
	if not target then
		return nil
	end
	local db = ns.altsDB
	local cands = {}
	for _, id in ipairs(Index()[base .. ":" .. kind] or {}) do
		local r = db.recipes[id]
		if r.out then
			local lo, hi = ns.AltsItem_Ilvl(r.out[1]), ns.AltsItem_Ilvl(r.out[2])
			if lo and hi then
				cands[#cands + 1] = { recipeID = id, lo = lo, hi = hi, known = ns.Alts_RecipeStatus(db.chars, r, id) == "known" }
			end
		end
	end
	return ns.Alts_BestProfCraft(cands, target)
end

-- Whether the account has every material for one craft of a recipe and somebody knows each step.
function ns.AltsProf_CanCraft(recipeID)
	local db = ns.altsDB
	producers = producers or ns.Alts_Producers(db.recipes)
	local ok, plan = pcall(ns.Alts_Plan, recipeID, 1, {
		recipes = db.recipes, chars = db.chars, producers = producers,
		maxDepth = db.chain == "one" and 1 or ns.ALTS_FULL_DEPTH,
		count = function(items)
			return (ns.Alts_Have(items))
		end,
	})
	return ok and plan.missing == 0 and plan.unknown == 0
end

-- "+25 item level" or "free slot".
function ns.AltsProf_GainText(mark, gain)
	if mark == "empty" or gain == nil then
		return "free slot"
	end
	return ("+%d item level"):format(gain)
end

-- Bag items -----------------------------------------------------------------------------------------------------

-- The other character a profession item in your bags helps most: { guid, gain } (gain nil for a free slot), nil when
-- it's nobody's upgrade, is one for you (it stays with you), or hasn't loaded.
function ns.AltsProf_BagUpgrade(link)
	local base, kind = ns.AltsProf_ItemOf(link)
	if not base then
		return nil
	end
	local ilvl = ns.AltsItem_Ilvl(link)
	if not ilvl then
		return nil
	end
	local db = ns.altsDB
	local me = UnitGUID("player")
	local mine = db.chars[me]
	if mine and mine.profs and mine.profs[base] then
		local t = ns.AltsProf_Target(mine, base, kind)
		local mark = t and ns.Alts_Upgrade(ilvl, ilvl, t)
		if mark == "sure" or mark == "empty" then
			return nil
		end
	end
	local targets = {}
	for guid, c in pairs(db.chars) do
		if guid ~= me and c.profs and c.profs[base] then
			local t = ns.AltsProf_Target(c, base, kind)
			if t then
				targets[#targets + 1] = { guid = guid, target = t }
			end
		end
	end
	return ns.Alts_ProfBagUpgrade(ilvl, targets)
end

-- Next up ---------------------------------------------------------------------------------------------------------

local KIND_TEXT = { tool = "Tool", acc = "Accessory" }

local function ProfName(c, base)
	return c.profs and c.profs[base] and c.profs[base].name or "?"
end

-- "an upgrade at every quality (+12 item level)", "an upgrade at the higher qualities (up to +12 item level)",
-- "fills an empty slot".
local function UpgradeText(best)
	if best.mark == "empty" then
		return "fills an empty slot"
	elseif best.mark == "sure" then
		return ("an upgrade at every quality (+%d item level)"):format(best.gain)
	end
	return ("an upgrade at the higher qualities (up to +%d item level)"):format(best.gain)
end
ns.AltsProf_UpgradeText = UpgradeText

-- "A better tool or accessory can be crafted now": for each character's professions, the best known craft that's an
-- upgrade, when the account has its materials. Yours first.
function ns.AltsProf_NextUp()
	local db = ns.altsDB
	local list = {}
	if not db then
		return list
	end
	local me = UnitGUID("player")
	for guid, c in pairs(db.chars) do
		for base in pairs(c.profs or {}) do
			for _, kind in ipairs({ "tool", "acc" }) do
				local best = ns.AltsProf_BestCraft(c, base, kind)
				if best and ns.AltsProf_CanCraft(best.recipeID) then
					local recipe = db.recipes[best.recipeID]
					local _, who = ns.Alts_RecipeStatus(db.chars, recipe, best.recipeID)
					local crafter = who and who[1]
					local mine = guid == me
					local whose = mine and "your" or ((c.name or "?") .. "'s")
					list[#list + 1] = {
						key = ("profgear:%s:%d:%s"):format(guid, base, kind),
						state = ("%d:%s"):format(best.recipeID, tostring(best.gain)),
						text = ("Craft %s for %s %s"):format(recipe.name or "?", whose, ProfName(c, base)),
						why = ("%s: %s. %s knows it, and the materials are on hand."):format(KIND_TEXT[kind],
							UpgradeText(best), crafter and crafter.name or "Somebody"),
						right = best.mark == "empty" and "new" or ("+%d"):format(best.gain),
						icon = recipe.icon,
						bonus = mine and 6 or 0,
						onClick = function()
							ns.AltsCraft_Open(best.recipeID, mine and "me" or guid)
						end,
						hint = "Click to open it in the Crafting tab",
					}
				end
			end
		end
	end
	return list
end
