local addonName, ns = ...

-- Gold & value, item markers: reads a bag item's facts for MarkerData.lua's rules (ns.Value_Marker) and keeps each
-- slot's marker until the item, the quest log, your gear or the settings change. Also the tooltip line and the
-- commands. Drawn by MarkerArt.lua; shown in Tomte's bags (Modules/Bags/Read.lua and Buttons.lua) and in the game's
-- and Baganator's (MarkerBags.lua). Settings and toggle in Value.lua (ns.ValueMarkers_*).

local CONSUMABLE, CONTAINER, WEAPON, PROJECTILE, ARMOR, QUIVER, QUEST, KEY, BATTLEPET, PROFESSION =
	0, 1, 2, 6, 4, 11, 12, 13, 17, 19 -- Enum.ItemClass
local SKIP = { [CONTAINER] = "bag", [KEY] = "key", [PROJECTILE] = "ammo", [QUIVER] = "ammo", [PROFESSION] = "tool",
	[BATTLEPET] = "pet" }
local UNCOMMON, EPIC = 2, 4 -- Enum.ItemQuality: what can be disenchanted
local DISENCHANT = 13262 -- the Disenchant spell, on retail and Forever
local CHANGE_DELAY = 0.5 -- seconds to gather a burst of quest log, gear or skill events into one redraw
-- Seconds a slot's marker is kept: prices change without the item changing (an Auctionator scan, TSM's data loading
-- after login), so a marker is judged again on the first draw after this.
local PRICE_TTL = 60
local RECIPE = 9 -- Enum.ItemClass.Recipe
local BIND_ON_PICKUP, BIND_QUEST = 1, 4 -- Enum.ItemBind
local BAGS = { 0, 1, 2, 3, 4, 5 } -- Backpack .. ReagentBag (Enum.BagIndex): the summary's count
-- Forever has no profession equipment class: Bags_ItemClass files its tools under it. Nil on retail.
local TOOLS = ns.FOREVER and ns.Content_Get(ns.CONTENT_FOREVER, "professionTools") or nil

local UI = ns.UI
local IsSecret = ns.IsSecret

local module, db
local events = ns.NewEvents()
ns.Value_Events = events

local cache = {} -- [bag * 1000 + slot] = { link, total, gen, at (GetTime), marker }
local linkCache = {} -- [link] = { total, gen, at, marker }: items known by their link alone (Value_LinkMarker)
local gen = 0 -- bumped when anything a marker depends on changed: every cached marker is judged again
local quests -- { { title, objectives = { texts } } } from the quest log; nil until read again
local sets -- ns.EquipmentSetSlots(), nil until read again

local function Active()
	return module ~= nil and module.active == true
end

-- Facts -------------------------------------------------------------------------------------------------------------

local function ReadQuests()
	local list = {}
	for i = 1, C_QuestLog.GetNumQuestLogEntries() do
		local info = C_QuestLog.GetInfo(i)
		if info and not info.isHeader and info.questID then
			local texts = {}
			for _, o in ipairs(C_QuestLog.GetQuestObjectives(info.questID) or {}) do
				if o.text and o.text ~= "" and not IsSecret(o.text) then
					texts[#texts + 1] = o.text
				end
			end
			list[#list + 1] = { title = info.title, objectives = texts }
		end
	end
	return list
end

local function IsToy(itemID)
	return C_ToyBox ~= nil and C_ToyBox.GetToyInfo ~= nil and C_ToyBox.GetToyInfo(itemID) ~= nil
end

local function IsCollectible(itemID)
	return IsToy(itemID) or C_MountJournal.GetMountFromItem(itemID) ~= nil
		or (C_PetJournal.GetPetInfoByItemID ~= nil and C_PetJournal.GetPetInfoByItemID(itemID) ~= nil)
end

-- What disenchanting one is worth (TSM's Destroy price), or nil without TSM.
local function DestroyValue(itemID, classID, quality)
	if not ((classID == WEAPON or classID == ARMOR) and quality and quality >= UNCOMMON and quality <= EPIC) then
		return nil
	end
	return ns.ValueSell_TSMNumber and ns.ValueSell_TSMNumber("Destroy", "i:" .. itemID)
end

-- The facts MarkerData.lua's rules read; nil while the item's data is loading (or unreadable). src: the item, from a
-- bag slot (SlotSource) or from a link alone (Value_LinkMarker): { link, itemID, stackCount, quality, hasNoValue,
-- isBound, hasLoot, quest (ItemQuestInfo or nil), location (an ItemLocation or nil), tooltip() (its tooltip data),
-- unusable() (whether it says in red you can't use it) }.
local function Facts(src, inSet)
	local link, itemID = src.link, src.itemID
	if not link or IsSecret(link, itemID, src.stackCount) then
		return nil
	end
	if link:find("|Hbattlepet:") then
		return { skip = "pet" }
	end
	local name, _, quality, _, _, _, _, _, _, _, price, classID, subclassID, bindType = C_Item.GetItemInfo(link)
	if not name then
		return nil
	end
	classID = ns.Bags_ItemClass(itemID, classID, subclassID, TOOLS)
	local bind = ns.Bags_BindState(bindType, src.isBound)
	local f = {
		ignored = db.markers.ignore[itemID] == true,
		skip = SKIP[classID] or (ns.BAGS_HEARTHS[itemID] and "hearth") or nil,
		quality = src.quality or quality, classID = classID, vendor = price or 0, noValue = src.hasNoValue,
		bound = bind == "soulbound" or bind == "warbound",
		consumable = classID == CONSUMABLE,
		count = math.max(C_Item.GetItemCount(itemID), src.stackCount or 1),
		minGain = db.sell.minGain,
		inSet = inSet,
	}
	if f.ignored or f.skip then
		return f
	end
	local quest = src.quest
	f.questItem = quest and quest.isQuestItem or false
	f.startsQuest = quest and quest.questID ~= nil or false
	f.questDone = f.startsQuest and C_QuestLog.IsQuestFlaggedCompleted(quest.questID) or false
	f.questActive = f.startsQuest and quest.isActive == true or false
	f.openable = src.hasLoot == true -- ContainerItemInfo: it opens with a right-click
	quests = quests or ReadQuests()
	f.questFor = ns.Value_QuestFor(name, quests)
	if classID == WEAPON or classID == ARMOR then
		if ns.Gear_BagArrow then -- Gear Check's, retail or Forever; looked up at call time (it may be off)
			f.upgrade = ns.Gear_BagArrow(link, src.location, src.isBound)
		end
		local look = ns.NewAppearance(link)
		-- Another class's look only counts while the item can still go to one of your characters.
		f.newLook = look == "you" or (look == "other" and bind ~= "soulbound")
		f.unusable = src.unusable()
		f.destroy = DestroyValue(itemID, classID, f.quality)
		f.canDisenchant = f.destroy ~= nil and ns.SpellKnown(DISENCHANT)
	end
	if classID == RECIPE and ns.Alts_RecipeLearnersFor then -- Alts may be off: then nil, and the selling rules decide
		f.recipe = ns.Value_RecipeFact(ns.Alts_RecipeLearnersFor(itemID, src.tooltip()))
	end
	f.collectible = IsCollectible(itemID)
	f.crafting = ns.AltsList_Marked ~= nil and (ns.AltsList_Marked(itemID) or 0) ~= 0 and true or false
	f.sell = ns.Value_SellAdvice(link, f.count, f.bound)
	return f
end

-- Markers -------------------------------------------------------------------------------------------------------------

-- Facts' source for the item in a bag slot.
local function SlotSource(bag, slot, info)
	return {
		link = info.hyperlink, itemID = info.itemID, stackCount = info.stackCount, quality = info.quality,
		hasNoValue = info.hasNoValue, isBound = info.isBound, hasLoot = info.hasLoot,
		quest = C_Container.GetContainerItemQuestInfo(bag, slot),
		location = ItemLocation:CreateFromBagAndSlot(bag, slot),
		tooltip = function()
			return C_TooltipInfo.GetBagItem(bag, slot)
		end,
		unusable = function()
			return ns.BagsRead_Unusable(bag, slot)
		end,
	}
end

local function InSet(bag, slot)
	sets = sets or ns.EquipmentSetSlots()
	return sets[bag * 1000 + slot] ~= nil
end

-- The marker for the item in a bag slot: { kind (a VALUE_MARKERS key, nil for none), rule, why }; an empty table for
-- an empty slot or an item still loading; nil while Gold & value is off. inSet: whether it's in an equipment set (the
-- caller may know; nil looks it up).
function ns.Value_BagMarker(bag, slot, inSet)
	if not Active() then
		return nil
	end
	if type(bag) ~= "number" or type(slot) ~= "number" then -- not a bag slot: nothing to judge
		return {}
	end
	local info = C_Container.GetContainerItemInfo(bag, slot)
	local key = bag * 1000 + slot
	if not info or not info.hyperlink or IsSecret(info.hyperlink, info.itemID) then
		cache[key] = nil
		return {}
	end
	local total = C_Item.GetItemCount(info.itemID)
	local c = cache[key]
	local now = GetTime()
	if c and c.link == info.hyperlink and c.total == total and c.gen == gen and now - c.at < PRICE_TTL then
		return c.marker
	end
	if inSet == nil then
		inSet = InSet(bag, slot)
	end
	local f = Facts(SlotSource(bag, slot, info), inSet)
	if not f then
		return {} -- loading: not cached, asked again on the next draw
	end
	local marker = ns.Value_Marker(f)
	marker.facts = f
	cache[key] = { link = info.hyperlink, total = total, gen = gen, at = now, marker = marker }
	return marker
end

-- The marker for an item known by its link alone: your bank as last seen, read away from the banker (Modules/Bags
-- Bank.lua). Judged for the character you're on, so only for your own and the Warband bank. Nothing a slot would add:
-- no quest-starter flag, no "opens", no equipment set. Kept per link as the bag slots' markers are.
function ns.Value_LinkMarker(link, count)
	if not Active() then
		return nil
	end
	if not link or IsSecret(link) then
		return {}
	end
	local itemID = C_Item.GetItemInfoInstant(link)
	if not itemID then
		return {}
	end
	local total = C_Item.GetItemCount(itemID, true)
	local c = linkCache[link]
	local now = GetTime()
	if c and c.total == total and c.gen == gen and now - c.at < PRICE_TTL then
		return c.marker
	end
	local bindType = select(14, C_Item.GetItemInfo(link))
	local f = Facts({
		link = link, itemID = itemID, stackCount = count,
		isBound = bindType == BIND_ON_PICKUP or bindType == BIND_QUEST, -- these are bound once you have them
		tooltip = function()
			return C_TooltipInfo.GetHyperlink(link)
		end,
		unusable = function()
			return ns.BagsRead_LinkUnusable(link)
		end,
	}, false)
	if not f then
		return {}
	end
	local marker = ns.Value_Marker(f)
	marker.facts = f
	linkCache[link] = { total = total, gen = gen, at = now, marker = marker }
	return marker
end

-- How many items of each marker the bags hold: [kind] = stacks.
function ns.Value_MarkerCounts()
	local counts = {}
	for _, bag in ipairs(BAGS) do
		for slot = 1, C_Container.GetContainerNumSlots(bag) do
			local marker = ns.Value_BagMarker(bag, slot)
			if marker and marker.kind then
				counts[marker.kind] = (counts[marker.kind] or 0) + 1
			end
		end
	end
	return counts
end

-- Every marker judged again, and the bags that show them redrawn.
function ns.Value_MarkersChanged()
	gen = gen + 1
	quests, sets = nil, nil
	wipe(linkCache)
	if ns.Bags_Reread then
		ns.Bags_Reread()
	end
	if ns.ValueMarkerBags_Repaint then
		ns.ValueMarkerBags_Repaint()
	end
end

local changedSoon = UI.Debounce(CHANGE_DELAY, function()
	if Active() then
		ns.Value_MarkersChanged()
	end
end)

-- Quests taken, done or progressed; gear equipped (upgrades); sets, looks, skills (Disenchant) and levels. Learning a
-- spell is LEARNED_SPELL_IN_SKILL_LINE on retail, LEARNED_SPELL_IN_TAB on older clients (TryWatch skips a missing one).
local CHANGES = {
	"QUEST_LOG_UPDATE", "QUEST_TURNED_IN", "PLAYER_EQUIPMENT_CHANGED", "EQUIPMENT_SETS_CHANGED",
	"TRANSMOG_COLLECTION_UPDATED", "SKILL_LINES_CHANGED", "LEARNED_SPELL_IN_SKILL_LINE", "LEARNED_SPELL_IN_TAB",
	"PLAYER_LEVEL_UP",
}
-- The quest log as far as markers care: titles and objective texts without their counts.
local function QuestSignature(list)
	local parts = {}
	for _, q in ipairs(list) do
		parts[#parts + 1] = q.title or ""
		for _, text in ipairs(q.objectives) do
			parts[#parts + 1] = (text:gsub("%d", ""))
		end
	end
	return table.concat(parts, "\n")
end

local questSignature
-- QUEST_LOG_UPDATE comes with every objective's tick: only a quest taken or gone, or its objectives changing, counts.
local questsSoon = UI.Debounce(CHANGE_DELAY, function()
	if not Active() then
		return
	end
	local signature = QuestSignature(ReadQuests())
	if signature ~= questSignature then
		questSignature = signature
		ns.Value_MarkersChanged()
	end
end)

for _, event in ipairs(CHANGES) do
	events:On("markers", event, event == "QUEST_LOG_UPDATE" and questsSoon or changedSoon)
end

-- Tooltip ----------------------------------------------------------------------------------------------------------

local ROLES = { vendor = "warning", auction = "warning", disenchant = "info", keep = "success", quest = "warning",
	delete = "danger" }

-- The bag and slot of the item a tooltip shows, when it's one of yours in a bag.
local function BagSlot(data)
	local location = ns.Value_TooltipLocation(data) -- Sell.lua: checked before Blizzard's IsValid can error
	if not (location and location:IsBagAndSlot()) then
		return nil
	end
	local bag, slot = location:GetBagAndSlot()
	if type(bag) == "number" and type(slot) == "number" then
		return bag, slot
	end
	return nil
end

ns.ValueMarkers_BagSlot = BagSlot -- Sell.lua: a bag item's price line uses its marker's numbers

local function OnItem(tooltip, data)
	if not (Active() and db.markers.tooltip and tooltip.AddLine and data) then
		return
	end
	local bag, slot = BagSlot(data)
	if not bag then
		return
	end
	local marker = ns.Value_BagMarker(bag, slot)
	if not (marker and marker.kind) then
		return
	end
	local text = UI.Wrap(ns.Value_MarkerName(marker.kind), ROLES[marker.kind])
	if marker.why then
		text = text .. "  " .. UI.Wrap(marker.why, "textMuted")
	end
	tooltip:AddLine(text)
end

local hooked = false

-- Commands ---------------------------------------------------------------------------------------------------------

-- The first bag slot holding the item in text (a link or an ID), or nil.
local function FindInBags(text)
	local itemID = text and text ~= "" and C_Item.GetItemInfoInstant(tonumber(text) or text)
	if not itemID then
		return nil
	end
	for _, bag in ipairs(BAGS) do
		for slot = 1, C_Container.GetContainerNumSlots(bag) do
			local info = C_Container.GetContainerItemInfo(bag, slot)
			if info and info.itemID == itemID then
				return bag, slot, itemID, info.hyperlink
			end
		end
	end
	return nil, nil, itemID
end

local function Trim(text)
	return text and text:match("^%s*(.-)%s*$") or ""
end

-- /tomte value why <item>: the marker, the rule that decided it, and the facts it read.
function ns.ValueMarkers_Why(_, rawArg)
	local bag, slot, itemID, link = FindInBags(Trim(rawArg))
	if not itemID then
		ns.Print("Shift-click an item into the command: /tomte value why <item>")
		return
	elseif not bag then
		ns.Print("That item isn't in your bags.")
		return
	end
	local marker = ns.Value_BagMarker(bag, slot)
	if not (marker and marker.rule) then
		ns.Print("Gold & value is off, or the item is still loading. Try again in a moment.")
		return
	end
	local rule = ns.VALUE_MARKER_RULES[marker.rule]
	ns.Print(("%s: %s (rule %d, %s)"):format(link, marker.kind and ns.Value_MarkerName(marker.kind) or "no marker",
		marker.rule, rule.title))
	if marker.why then
		ns.Print("  " .. marker.why)
	end
	local f, parts = marker.facts or {}, {}
	for _, k in ipairs({ "skip", "quality", "classID", "vendor", "noValue", "bound", "consumable", "count", "questItem",
		"startsQuest", "questDone", "questActive", "openable", "questFor", "upgrade", "inSet", "newLook", "unusable", "destroy", "canDisenchant",
		"collectible", "crafting" }) do
		if f[k] ~= nil and f[k] ~= false then
			parts[#parts + 1] = ("%s=%s"):format(k, tostring(f[k]))
		end
	end
	if f.recipe then
		parts[#parts + 1] = f.recipe.known and "recipe=known" or ("recipe=" .. ns.Value_LearnerText(f.recipe))
	end
	if f.sell then
		local s = f.sell
		parts[#parts + 1] = ("auction %s each from %s, expected %s, rate %s (%s)"):format(
			ns.Price(math.floor(s.market + 0.5)), ns.Value_SourceName(), ns.Price(math.floor(s.expected + 0.5)),
			s.saleRate and ("%d%%"):format(math.floor(s.saleRate * 100 + 0.5)) or "none", s.kind)
	end
	ns.Print("  " .. table.concat(parts, ", "))
end

-- /tomte value ignore <item>: no marker on it, or a marker again.
function ns.ValueMarkers_Ignore(_, rawArg)
	local _, _, itemID, link = FindInBags(Trim(rawArg))
	if not itemID then
		ns.Print("Shift-click an item into the command: /tomte value ignore <item>")
		return
	end
	local name = link or ("item " .. itemID)
	if db.markers.ignore[itemID] then
		db.markers.ignore[itemID] = nil
		ns.Print(("%s gets a marker again."):format(name))
	else
		db.markers.ignore[itemID] = true
		ns.Print(("%s gets no marker now. The same command gives it one again."):format(name))
	end
	ns.Value_MarkersChanged()
end

-- "In your bags now: ..." for the settings page and the rules window.
function ns.ValueMarkers_Summary()
	if not Active() then
		return "Turn Gold & value on to see the markers."
	end
	local text = ns.Value_MarkerSummary(ns.Value_MarkerCounts())
	return text and ("In your bags now: %s."):format(text) or "Nothing in your bags is marked."
end

-- Start and stop -------------------------------------------------------------------------------------------------------

function ns.ValueMarkers_Init(mod, saved)
	module, db = mod, saved
end

function ns.ValueMarkers_Toggle(active)
	for _, event in ipairs(CHANGES) do
		if active then
			events:TryWatch("markers", event)
		else
			events:Unwatch("markers", event)
		end
	end
	-- Post-calls can't be removed: OnItem checks the module and the setting.
	if active and not hooked and TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall then
		hooked = true
		TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, ns.Perf_Wrap(OnItem, "tooltip"))
	end
	wipe(cache)
	ns.Value_MarkersChanged()
	if ns.ValueMarkerBags_Toggle then
		ns.ValueMarkerBags_Toggle(active)
	end
end
