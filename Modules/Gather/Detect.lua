local addonName, ns = ...

-- Gathering detection: the player's casts and the loot window, turned into plain tables for Gather.lua.
-- No combat log in 12.x: a gather is a loot window (not secret) classified by the cast before it (can be secret)
-- and by what's in it (Data.lua). Skill and knowledge are read from the profession APIs, never parsed from chat.
-- Every payload, GUID, link and name is checked with issecretvalue: a secret one makes that piece unknown.

local db, handlers
local running = false
local names = {} -- [localized anchor spell name] = kind
local notNames = {} -- [localized name of a GATHER_NOT spell] = true (Opening has many spell IDs, one name)
local learning = {} -- Gather_Learn's pending counts (per login)
local lastCast -- { spellID, kind, at, name, target, notGather }
local sentGUID, sentTarget -- the last UNIT_SPELLCAST_SENT, for the node's name
-- The open loot window (Build): { slots, fishing, cast, kind, reason, sources, objectID, nodeName, at, committed }.
local win
local pending = {} -- [slot] = item, booked when the slot is looted
local lastWhy -- what the last loot window was, for /tomte gather why
local dropsDone = {} -- [base skill line] = weekly drops done, last reading
local progressDirty = false

local KIND_OF_LINE = {}
for kind, line in pairs(ns.GATHER_SKILL_LINES) do
	KIND_OF_LINE[line] = kind
end

local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(self, event, ...)
	self[event](self, ...)
end)

local Secret = ns.IsSecret

local function Readable(v)
	return v ~= nil and not Secret(v)
end

local function Call(name, ...)
	local fn = handlers and handlers[name]
	if fn then
		fn(...)
	end
end

---------------------------------------------------------------------------------------------------------------
-- Professions, skill and knowledge

local function Profs()
	local content = ns.Content_Get and ns.ContentExpansion and ns.Content_Get(ns.ContentExpansion(), "profs")
	return content or {}
end

-- The character's gathering professions: { { base, kind, index, name, icon, rank, def } }.
function ns.GatherDetect_Profs()
	local list = {}
	local first, second, _, fishing = GetProfessions()
	local defs = Profs()
	for _, index in ipairs({ first or false, second or false, fishing or false }) do
		if index then
			local name, icon, rank, _, _, _, base = GetProfessionInfo(index)
			local kind = base and KIND_OF_LINE[base]
			if kind then
				list[#list + 1] = { base = base, kind = kind, index = index, name = name, icon = icon, rank = rank,
					def = defs[base] }
			end
		end
	end
	return list
end

local function SkillOf(p)
	local child = p.def and p.def.child
	if child then
		local ok, info = pcall(C_TradeSkillUI.GetProfessionInfoBySkillLineID, child)
		local level = ok and type(info) == "table" and info.skillLevel or nil
		if Readable(level) and type(level) == "number" and level > 0 then
			return level
		end
	end
	return Readable(p.rank) and p.rank or nil
end

local function KnowledgeOf(p)
	local child = p.def and p.def.child
	if not (child and C_ProfSpecs) then
		return nil
	end
	local ok, has = pcall(C_ProfSpecs.SkillLineHasSpecialization, child)
	if not (ok and has == true) then
		return nil
	end
	local ok2, info = pcall(C_ProfSpecs.GetCurrencyInfoForSkillLine, child)
	local n = ok2 and type(info) == "table" and info.numAvailable or nil
	return Readable(n) and type(n) == "number" and n or nil
end

-- Weekly knowledge drops done and possible for a profession: done, total (nil when the content has none).
function ns.GatherDetect_Drops(p)
	local def = p.def
	if not (def and def.drops) then
		return nil
	end
	local done, total = 0, #def.drops
	for _, quest in ipairs(def.drops) do
		if C_QuestLog.IsQuestFlaggedCompleted(quest) then
			done = done + 1
		end
	end
	if def.bigDrop then
		total = total + 1
		if C_QuestLog.IsQuestFlaggedCompleted(def.bigDrop) then
			done = done + 1
		end
	end
	return done, total
end

-- Reads skill, knowledge and drops of every gathering profession and hands them to Gather.lua. A drop count above
-- the last reading is a find (the first reading only sets the baseline).
function ns.GatherDetect_ReadProgress()
	progressDirty = false
	for _, p in ipairs(ns.GatherDetect_Profs()) do
		local line = p.def and p.def.child or p.base
		Call("skill", line, SkillOf(p), p)
		local k = KnowledgeOf(p)
		if k then
			Call("knowledge", line, k, p)
		end
		local done, total = ns.GatherDetect_Drops(p)
		if done then
			local before = dropsDone[p.base]
			if before and done > before then
				for _ = 1, done - before do
					Call("find", { kind = "drop", skillLine = p.base, at = GetServerTime(), done = done, total = total })
				end
			end
			dropsDone[p.base] = done
		end
	end
end

---------------------------------------------------------------------------------------------------------------
-- Casts

function events:UNIT_SPELLCAST_SENT(unit, target, castGUID, spellID)
	if Readable(castGUID) and Readable(target) and type(target) == "string" and target ~= "" then
		sentGUID, sentTarget = castGUID, target
	else
		sentGUID, sentTarget = nil, nil
	end
end

function events:UNIT_SPELLCAST_SUCCEEDED(unit, castGUID, spellID)
	if not Readable(spellID) or type(spellID) ~= "number" then
		lastCast = nil
		return
	end
	local name = C_Spell.GetSpellName(spellID)
	if not Readable(name) then
		name = nil
	end
	local target
	if sentGUID and Readable(castGUID) and castGUID == sentGUID then
		target = sentTarget
	end
	local kind = ns.Gather_SpellKind(spellID, name, names, db.spells)
	lastCast = { spellID = spellID, name = name, at = GetTime(), target = target, kind = kind,
		notGather = not kind and name ~= nil and notNames[name] == true or nil }
end

---------------------------------------------------------------------------------------------------------------
-- The loot window

local function ReadSources(slot)
	local list = {}
	local values = { GetLootSourceInfo(slot) }
	for i = 1, #values, 2 do
		local guid = values[i]
		if Readable(guid) and type(guid) == "string" then
			list[#list + 1] = guid
		end
	end
	return list
end

local function ReadSlots()
	local slots = {}
	local n = GetNumLootItems()
	if not Readable(n) then
		return slots
	end
	for slot = 1, n do
		local slotType = GetLootSlotType(slot)
		if Readable(slotType) and slotType == Enum.LootSlotType.Item then
			local link = GetLootSlotLink(slot)
			local _, _, quantity, _, quality = GetLootSlotInfo(slot)
			if Readable(link) and type(link) == "string" then
				local itemID, _, _, _, _, classID, subClassID = C_Item.GetItemInfoInstant(link)
				if itemID then
					slots[#slots + 1] = {
						slot = slot, link = link, itemID = itemID, classID = classID, subClassID = subClassID,
						count = Readable(quantity) and type(quantity) == "number" and quantity or 1,
						quality = Readable(quality) and quality or nil,
						sources = ReadSources(slot),
					}
				end
			end
		end
	end
	return slots
end

local function FreshCast()
	if lastCast and GetTime() - lastCast.at <= ns.GATHER_CAST_FRESH then
		return lastCast
	end
	return nil
end

local function Rank(link)
	local ok, rank = pcall(C_TradeSkillUI.GetItemReagentQualityByItemInfo, link)
	return ok and Readable(rank) and type(rank) == "number" and rank or nil
end

local function MapID()
	local mapID = C_Map.GetBestMapForUnit("player")
	return Readable(mapID) and mapID or nil
end

local function HasKind(kind)
	for _, p in ipairs(ns.GatherDetect_Profs()) do
		if p.kind == kind then
			return true
		end
	end
	return false
end

local function Build()
	local w = { slots = ReadSlots(), fishing = IsFishingLoot() == true }
	local cast = FreshCast()
	w.cast = cast
	if cast and #w.slots > 0 then
		lastCast = nil -- one cast opens one window: a skinning cast must not also claim the next corpse looted
	end
	local kind, reason = ns.Gather_Classify(w, cast, { now = GetTime(), fishing = db.fishing })
	if cast and cast.notGather and not w.fishing then
		kind, reason = nil, "opening (spell " .. cast.spellID .. ")" -- an Opening/Survey variant Tomte doesn't list
	end
	local learned
	-- Gather_Learn refuses GATHER_NOT spells too; checking here skips the contents scan for them.
	if cast and not cast.kind and not cast.notGather and not ns.GATHER_NOT[cast.spellID] and not w.fishing then
		-- An unknown readable cast: learn it from the node it opened, by its contents, and only for a profession the
		-- character has. Never from corpses: skinning ranks share the "Skinning" name, which already matches, and a
		-- combat spell with a cast bar (Aimed Shot) before looting a beast with leather would be learned wrongly.
		local contents, sourceType = ns.Gather_ContentsKind(w)
		local fits = sourceType == "GameObject" and (contents == "mining" or contents == "herbalism")
		if fits and HasKind(contents) then
			learned = ns.Gather_Learn(db.spells, learning, cast, w, contents)
			if learned then
				cast.kind = learned
				if not kind then
					kind, reason = learned, "learned spell " .. cast.spellID
				end
			end
		end
	end
	w.kind, w.reason = kind, reason
	-- Sources, the node's object ID and name.
	local sources, seen = {}, {}
	for _, slot in ipairs(w.slots) do
		for _, guid in ipairs(slot.sources) do
			if not seen[guid] then
				seen[guid] = true
				sources[#sources + 1] = guid
			end
		end
	end
	w.sources = sources
	local objectID
	for _, guid in ipairs(sources) do
		local t, id = ns.Gather_ParseGUID(guid)
		if t == "GameObject" and id then
			objectID = id
			break
		end
	end
	w.objectID = objectID
	w.nodeName = kind and kind ~= "fishing" and kind ~= "skinning" and cast and cast.target or nil
	lastWhy = { kind = kind, reason = reason, cast = cast and { spellID = cast.spellID, name = cast.name,
		kind = cast.kind, age = GetTime() - cast.at } or nil, sources = sources, slots = #w.slots, learned = learned }
	return w
end

-- The gather is handed over once the window is sure not to be a container (LOOT_OPENED), or at the first looted
-- slot or the close, whichever comes first.
local function Commit()
	if not win or win.committed then
		return
	end
	win.committed = true
	if not win.kind then
		return
	end
	local mapID = MapID()
	Call("gather", { at = GetServerTime(), kind = win.kind, sources = win.sources, mapID = mapID,
		objectID = win.objectID, nodeName = win.nodeName })
	for _, s in ipairs(win.slots) do
		pending[s.slot] = {
			itemID = s.itemID, link = s.link, count = s.count, quality = s.quality, kind = win.kind, mapID = mapID,
			unit = ns.Value_ItemPrice and ns.Value_ItemPrice(s.link) or nil, rank = Rank(s.link),
		}
	end
	progressDirty = true
end

local WINDOW_STALE = 60 -- a window older than this without LOOT_CLOSED is forgotten

local function Open()
	if win and #win.slots > 0 and GetTime() - win.at < WINDOW_STALE then
		return -- LOOT_READY twice, or READY then OPENED: one window is handled once
	end
	wipe(pending)
	win = Build()
	win.at = GetTime()
end

function events:LOOT_READY()
	Open()
end

function events:LOOT_OPENED(autoLoot, isFromItem)
	if isFromItem == true then
		Open()
		if win.committed then
			return
		end
		win.kind, win.reason = nil, "container"
		if lastWhy then
			lastWhy.kind, lastWhy.reason = nil, "container"
		end
		win.committed = true
		return
	end
	Open()
	Commit()
end

function events:LOOT_SLOT_CLEARED(slot)
	Commit()
	if not Readable(slot) then
		return
	end
	local it = ns.Gather_Booked(pending, slot)
	if it then
		it.at = GetServerTime()
		Call("item", it)
		if ns.Gather_IsFind(it.quality) then
			Call("find", { kind = "item", itemID = it.itemID, link = it.link, at = it.at })
		end
	end
end

function events:LOOT_CLOSED()
	Commit()
	win = nil
	wipe(pending)
	if progressDirty then
		ns.GatherDetect_ReadProgress()
	end
end

function events:SKILL_LINES_CHANGED()
	if handlers and handlers.running and handlers.running() then
		ns.GatherDetect_ReadProgress()
	end
end
events.TRAIT_TREE_CURRENCY_INFO_UPDATED = events.SKILL_LINES_CHANGED

---------------------------------------------------------------------------------------------------------------
-- Start, stop, why

local EVENTS = { "LOOT_READY", "LOOT_OPENED", "LOOT_SLOT_CLEARED", "LOOT_CLOSED", "SKILL_LINES_CHANGED",
	"TRAIT_TREE_CURRENCY_INFO_UPDATED" }

-- handlers = { gather(g), item(it), find(f), skill(line, level, prof), knowledge(line, available, prof), running() }
function ns.GatherDetect_Start(saved, h)
	db, handlers = saved, h
	if running then
		return
	end
	running = true
	wipe(names)
	for id, kind in pairs(ns.GATHER_SPELLS) do
		local name = C_Spell.GetSpellName(id)
		if name then
			names[name] = kind
		end
	end
	wipe(notNames)
	for id in pairs(ns.GATHER_NOT) do
		local name = C_Spell.GetSpellName(id)
		if name and not names[name] then
			notNames[name] = true
		end
	end
	events:RegisterUnitEvent("UNIT_SPELLCAST_SENT", "player")
	events:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
	for _, event in ipairs(EVENTS) do
		events:RegisterEvent(event)
	end
	-- Baseline for the weekly drops (a later rise is a find).
	for _, p in ipairs(ns.GatherDetect_Profs()) do
		dropsDone[p.base] = ns.GatherDetect_Drops(p)
	end
end

function ns.GatherDetect_Stop()
	running = false
	events:UnregisterAllEvents()
	win, lastCast = nil, nil
	wipe(pending)
end

local function KindName(kind)
	return kind or "not counted"
end

function ns.GatherDetect_Why()
	local lines = {}
	if not lastWhy then
		lines[#lines + 1] = "no loot window since login."
	else
		local w = lastWhy
		lines[#lines + 1] = ("last loot window: %s (%s), %d item %s."):format(KindName(w.kind), w.reason or "?", w.slots,
			w.slots == 1 and "slot" or "slots")
		local counts, order = {}, {}
		for _, guid in ipairs(w.sources) do
			local t, id = ns.Gather_ParseGUID(guid)
			local key = (t or "?") .. (id and (" " .. id) or "")
			if not counts[key] then
				order[#order + 1] = key
			end
			counts[key] = (counts[key] or 0) + 1
		end
		local parts = {}
		for _, key in ipairs(order) do
			parts[#parts + 1] = counts[key] > 1 and (key .. " x" .. counts[key]) or key
		end
		lines[#lines + 1] = "sources: " .. (#parts > 0 and table.concat(parts, ", ") or "none readable")
		local c = w.cast
		if c then
			lines[#lines + 1] = ("cast: spell %d%s, %.1fs before, %s."):format(c.spellID, c.name and (" (" .. c.name .. ")") or "",
				c.age, c.kind and ("gathering: " .. c.kind) or "not a known gathering spell")
		else
			-- "3 seconds" is ns.GATHER_CAST_FRESH (Data.lua): change both together.
			lines[#lines + 1] = "cast: none readable in the 3 seconds before."
		end
		if w.learned then
			lines[#lines + 1] = ("learned spell %d as %s."):format(c and c.spellID or 0, w.learned)
		end
	end
	local learned = {}
	for id, kind in pairs(db and db.spells or {}) do
		learned[#learned + 1] = ("%d %s"):format(id, kind)
	end
	table.sort(learned)
	lines[#lines + 1] = "learned spells: " .. (#learned > 0 and table.concat(learned, ", ") or "none")
	return lines
end
