local addonName, ns = ...

-- Gold & value, item markers: pure logic (no WoW API calls; unit-tested in tests/test_value_markers.lua). One marker
-- per bag item, saying what to do with it: vendor, auction, disenchant, keep, keep for a quest or delete. Markers.lua
-- reads the facts below from the game; MarkerArt.lua draws the markers.
--
-- Facts about an item (everything you carry of it is judged together):
--   ignored       the player left it out (/tomte value ignore)
--   skip          "bag" | "key" | "tool" | "ammo" | "hearth" | "pet": never marked
--   quality       Enum.ItemQuality (0 = Poor)
--   classID       Enum.ItemClass
--   vendor        copper a vendor pays for one (0: nothing)
--   noValue       the game says vendors won't buy it
--   bound         soulbound or warbound: it can't be auctioned
--   consumable    something you use up (potions, food, scrolls)
--   collectible   a toy, mount or pet to learn
--   crafting      on the crafting list (Alts): it's wanted for a craft
--   questFor      the title of a quest in your log that names it
--   startsQuest   it starts a quest; questDone: that quest is done; questActive: that quest is in your log
--   openable      it opens with a right-click (it holds loot)
--   recipe        a recipe item: Value_RecipeFact of who can learn it ({ known } or { name, skill, need, profName,
--                 now }), nil when nobody can
--   questItem     the game calls it a quest item
--   upgrade       Gear Check's arrow ("upgrade" | "maybe" | "alt" | "later") or nil
--   inSet         it's in one of your equipment sets
--   newLook       its appearance isn't collected yet
--   unusable      red on its tooltip: you can't use it
--   sell          Value_SellVerdict for the whole stack, or nil (bound, or no auction price)
--   destroy       copper its disenchanting materials are worth (TSM), or nil
--   canDisenchant you know Disenchant (needed for a soulbound item)
--   count         how many you carry
--   minGain       the player's limit: copper a stack must gain somewhere else to beat a vendor

local WEAPON, ARMOR, QUEST = 2, 4, 12 -- Enum.ItemClass
local UNCOMMON, EPIC = 2, 4 -- Enum.ItemQuality: what can be disenchanted

-- The markers, in the order the settings and the rules page list them. role: the color they're drawn in (MarkerArt.lua
-- draws vendor as the game's coin and disenchant in the epic quality color).
ns.VALUE_MARKERS = {
	{ key = "vendor", name = "Vendor it" },
	{ key = "auction", name = "Auction it" },
	{ key = "disenchant", name = "Disenchant it" },
	{ key = "keep", name = "Keep it" },
	{ key = "quest", name = "Keep for a quest" },
	{ key = "delete", name = "Safe to delete" },
}

local NAMES = {}
for _, m in ipairs(ns.VALUE_MARKERS) do
	NAMES[m.key] = m.name
end

function ns.Value_MarkerName(kind)
	return NAMES[kind]
end

-- The rules, in the order they're tried: the first that fits decides. kind nil: no marker. For the "How each marker is
-- decided" window; Value_Marker returns the rule's index.
ns.VALUE_MARKER_RULES = {
	{ title = "No marker: left alone", text = "Items you told Tomte to ignore (/tomte value ignore), bags, keys, "
		.. "hearthstones, profession tools, ammunition and caged battle pets." },
	{ kind = "quest", title = "Keep for a quest", text = "A quest in your log names it in its objectives, or it starts "
		.. "a quest you haven't taken or done yet." },
	{ kind = "delete", title = "Delete", text = "It starts a quest you've already done, or it's soulbound gear you "
		.. "can't use and whose look you have, and no vendor buys it." },
	{ kind = "keep", title = "Keep: gear", text = "Gear Check calls it an upgrade (for you or another character), "
		.. "it's in an equipment set, or its appearance isn't in your collection yet." },
	{ kind = "keep", title = "Keep: you or an alt can learn it", text = "A recipe that one of your characters with "
		.. "that profession hasn't learned, now or once their skill is high enough (from Alts). When one of them knows "
		.. "it already, or none has the profession, the rules below decide." },
	{ kind = "disenchant", title = "Disenchant", text = "Green to epic gear whose materials are worth more than the "
		.. "auction house pays for it, and more than a vendor by over your limit. Needs TSM's prices; a soulbound one "
		.. "only if you know Disenchant." },
	{ kind = "keep", title = "Keep: open it", text = "Something that opens with a right-click (a bundle, a "
		.. "satchel, a crate)." },
	{ title = "No marker: an unknown quest item", text = "The game calls it a quest item, or it started a quest "
		.. "that's in your log now, but no quest objective names it. Tomte can't tell whether a quest still needs it." },
	{ kind = "keep", title = "Keep: something to learn or craft with", text = "A toy, mount or pet, or a material on "
		.. "your crafting list, unless it sells well at the auction house." },
	{ kind = "keep", title = "Keep: can't be sold", text = "No vendor buys it and the auction house doesn't want it "
		.. "either: a book, a keepsake, a soulbound trinket." },
	{ kind = "keep", title = "Keep: soulbound and you use it up", text = "A soulbound potion, food or scroll." },
	{ kind = "vendor", title = "Vendor: soulbound", text = "Anything else soulbound a vendor buys: it can't be "
		.. "auctioned." },
	{ kind = "vendor", title = "Vendor: grey", text = "Grey junk, unless it sells well at the auction house." },
	{ kind = "keep", title = "Keep: costs more than your limit to replace", text = "Something you use up (a potion, "
		.. "food, a bandage) that would cost more than your limit to buy back." },
	{ kind = "auction", title = "Auction", text = "It sells at the auction house, and the whole stack makes more than "
		.. "a vendor pays by over your limit (after the auction house's cut and the chance it doesn't sell)." },
	{ kind = "vendor", title = "Vendor: cheap, or slow to sell", text = "The auction house makes less than your limit "
		.. "more than a vendor, or it rarely sells there." },
	{ title = "No marker: nothing to go on", text = "Something you can trade that a vendor buys, with no auction "
		.. "price known (scan the auction house with Auctionator or TSM)." },
}

local R = {} -- rule indexes by name, for the code below
for i, key in ipairs({ "skip", "quest", "delete", "gear", "recipe", "disenchant", "open", "leftover", "learn", "unsellable",
	"boundUse", "bound", "grey", "replace", "auction", "cheap", "nothing" }) do
	R[key] = i
end

-- "Aldric can learn it (Leatherworking 95)." / "Aldric can learn it later (Leatherworking 50/90)." from f.recipe.
function ns.Value_LearnerText(r)
	local prof = r.profName or "?"
	if r.now then
		return r.skill and ("%s can learn it (%s %d)."):format(r.name, prof, r.skill)
			or ("%s can learn it (%s)."):format(r.name, prof)
	end
	return ("%s can learn it later (%s %d/%d)."):format(r.name, prof, r.skill or 0, r.need or 0)
end

-- f.recipe from Alts' learners (Alts_RecipeLearners: { known, ready, low, need, profName }): someone knows it, or
-- the one who can learn it now (the first), else the one closest to it. nil without learners.
function ns.Value_RecipeFact(who)
	if not who then
		return nil
	end
	if who.known and #who.known > 0 then
		return { known = true }
	end
	local first = who.ready and who.ready[1]
	if first then
		return { name = first.c.name, skill = first.skill, profName = who.profName, need = who.need, now = true }
	end
	local best
	for _, entry in ipairs(who.low or {}) do
		if not best or (entry.skill or 0) > (best.skill or 0) then
			best = entry
		end
	end
	if best then
		return { name = best.c.name, skill = best.skill, profName = who.profName, need = who.need, now = false }
	end
	return nil
end

local function Verdict(rule, why)
	return { kind = ns.VALUE_MARKER_RULES[rule].kind, rule = rule, why = why }
end

local function Sellable(f)
	return not f.noValue and (f.vendor or 0) > 0
end

local function IsGear(f)
	return f.classID == WEAPON or f.classID == ARMOR
end

local function Listing(f)
	return f.sell ~= nil and f.sell.kind == "ah"
end

-- Disenchanting beats both selling it and listing it, by the player's limit.
local function WorthDisenchanting(f)
	if not (f.destroy and IsGear(f) and f.quality and f.quality >= UNCOMMON and f.quality <= EPIC) then
		return false
	end
	if f.bound and not f.canDisenchant then
		return false
	end
	local count = f.count or 1
	local vendor = (f.vendor or 0) * count
	local auction = f.sell and f.sell.expected * count or 0
	return f.destroy * count >= vendor + (f.minGain or 0) and f.destroy * count > auction
end

-- The marker for an item: { kind (a VALUE_MARKERS key, nil for none), rule (index into VALUE_MARKER_RULES), why
-- (a short reason for the tooltip) }.
function ns.Value_Marker(f)
	if f.ignored then
		return Verdict(R.skip, "You told Tomte to ignore it.")
	elseif f.skip then
		return Verdict(R.skip, nil)
	end
	-- A quest starter's own tooltip already names its quest ("Starts: ..."), so its reason doesn't again. Once its quest
	-- is taken it's only needed when an objective names it; otherwise it's an unknown quest item (below).
	if f.questFor then
		return Verdict(R.quest, f.startsQuest and "Its quest needs it handed in." or ("For %s."):format(f.questFor))
	elseif f.startsQuest and not f.questDone and not f.questActive then
		return Verdict(R.quest, "It starts a quest.")
	end
	if not Sellable(f) and not Listing(f) then
		if f.startsQuest and f.questDone then
			return Verdict(R.delete, "Its quest is done and no vendor buys it.")
		elseif f.bound and IsGear(f) and f.unusable and not f.newLook and not f.upgrade then
			return Verdict(R.delete, "Soulbound, you can't use it and no vendor buys it.")
		end
	end
	if f.upgrade == "alt" then
		return Verdict(R.gear, "An upgrade for another character.")
	elseif f.upgrade then
		return Verdict(R.gear, "Gear Check: an upgrade.")
	elseif f.inSet then
		return Verdict(R.gear, "In an equipment set.")
	elseif f.newLook then
		return Verdict(R.gear, "Its appearance isn't collected.")
	end
	local learner = f.recipe and not f.recipe.known and f.recipe.name and f.recipe
	if learner then
		return Verdict(R.recipe, ns.Value_LearnerText(learner))
	end
	if WorthDisenchanting(f) then
		return Verdict(R.disenchant, "Its materials are worth more.")
	end
	if f.openable then
		return Verdict(R.open, "Right-click to open it.")
	end
	if f.startsQuest and f.questActive then
		return Verdict(R.leftover, "Its quest is in your log, and no objective names it.")
	elseif (f.questItem or f.classID == QUEST) and not f.startsQuest then
		return Verdict(R.leftover, "A quest item no quest in your log names.")
	end
	if (f.collectible or f.crafting) and not Listing(f) then
		return Verdict(R.learn, f.crafting and "On your crafting list." or "Something to learn.")
	end
	if not Sellable(f) and not Listing(f) then
		return Verdict(R.unsellable, "No vendor buys it.")
	end
	if f.bound then
		if f.consumable then
			return Verdict(R.boundUse, "Soulbound, and you use it up.")
		end
		return Verdict(R.bound, "Soulbound: it can't be auctioned.")
	end
	if f.quality == 0 and not Listing(f) then
		return Verdict(R.grey, "Grey junk.")
	end
	if f.sell then
		if Listing(f) then
			if f.consumable then
				return Verdict(R.replace, "You use it up, and it costs more than your limit to replace.")
			end
			return Verdict(R.auction, "Sells at the auction house for clearly more.")
		end
		if f.sell.kind == "slow" then
			return Verdict(R.cheap, "Rarely sells at the auction house.")
		elseif f.sell.expected <= (f.vendor or 0) then
			return Verdict(R.cheap, "A vendor pays more than the auction house would.")
		elseif f.sell.kind == "small" then
			return Verdict(R.cheap, "The auction house makes less than your limit more.")
		end
		return Verdict(R.cheap, "A vendor pays about as much.")
	end
	return Verdict(R.nothing, "No auction price known.")
end

-- Whether a quest objective's text names the item ("Gnoll Paw: 3/8", "3/8 Gnoll Paw", "Bring the Gnoll Paw").
-- Both are the game's own text, so this works in every client language. Names shorter than MIN_NAME are left out:
-- they'd match inside other words.
local MIN_NAME = 3
function ns.Value_ObjectiveNames(objectiveText, itemName)
	if not (objectiveText and itemName) or #itemName < MIN_NAME then
		return false
	end
	return objectiveText:lower():find(itemName:lower(), 1, true) ~= nil
end

-- The title of the first quest whose objectives name the item, or nil. quests: { { title, objectives = { texts } } }.
function ns.Value_QuestFor(itemName, quests)
	for _, quest in ipairs(quests) do
		for _, text in ipairs(quest.objectives or {}) do
			if ns.Value_ObjectiveNames(text, itemName) then
				return quest.title
			end
		end
	end
	return nil
end

-- "In your bags now: 3 to vendor, 2 to auction." from counts ([kind] = items), in VALUE_MARKERS' order; nil when
-- nothing is marked.
local SHORT = { vendor = "to vendor", auction = "to auction", disenchant = "to disenchant", keep = "to keep",
	quest = "for quests", delete = "to delete" }
function ns.Value_MarkerSummary(counts)
	local parts = {}
	for _, m in ipairs(ns.VALUE_MARKERS) do
		local n = counts[m.key]
		if n and n > 0 then
			parts[#parts + 1] = ("%d %s"):format(n, SHORT[m.key])
		end
	end
	if #parts == 0 then
		return nil
	end
	return table.concat(parts, ", ")
end
