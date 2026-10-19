local addonName, ns = ...

-- Session recap tracking: what nobody else detects. Achievements, collections, renown, upgrades and tames come in
-- through ns.Session_Note (Moments, Gear Check, Hunter Pets).
-- - Gold: each money change is booked to what's open (loot window, auction house, mailbox, merchant).
-- - Loot: "You receive ..." messages (not purchases or deliveries, Recap_IsLoot); the quality option picks what's listed.
-- - Rares: rare units seen (vignettes, target, mouseover) count once when they die as your target, your party kills
--   them, or you loot them.
-- Every GUID, text and classification is checked for secret values: in instances they simply don't count.

local MAX_ENTRIES = 40
local MAX_CANDIDATES = 200
local ITEM_RETRY = 1 -- seconds before looking at an uncached item again
local ITEM_TRIES = 5 -- retries before an item that never loads is skipped
local P = Enum.PlayerInteractionType
local CONTEXTS = { [P.Merchant] = "vendor", [P.MailInfo] = "mail", [P.Auctioneer] = "auction",
	[P.TradePartner] = "trade" }
-- Loot windows and bonus rolls ("You receive loot"), and items pushed into the bags ("You receive item": quest
-- rewards, but also purchases and deliveries, which Recap_IsLoot leaves out).
local LOOT_FORMATS = {
	looted = { "LOOT_ITEM_SELF", "LOOT_ITEM_SELF_MULTIPLE", "LOOT_ITEM_BONUS_ROLL_SELF",
		"LOOT_ITEM_BONUS_ROLL_SELF_MULTIPLE" },
	pushed = { "LOOT_ITEM_PUSHED_SELF", "LOOT_ITEM_PUSHED_SELF_MULTIPLE" },
}
local EVENTS = {
	"LOOT_OPENED", "LOOT_CLOSED", "PLAYER_INTERACTION_MANAGER_FRAME_SHOW", "PLAYER_INTERACTION_MANAGER_FRAME_HIDE",
	"CHAT_MSG_LOOT", "VIGNETTES_UPDATED", "VIGNETTE_MINIMAP_UPDATED", "PLAYER_TARGET_CHANGED", "UPDATE_MOUSEOVER_UNIT",
	"PLAYER_TARGET_DIED", "PARTY_KILL",
}

local context = {} -- { loot, vendor, mail, auction, trade } = true while open
local candidates, candidateCount = {}, 0 -- [guid] = name: rares seen this session
local lootPatterns

local events = ns.NewEvents() -- shared with Recap.lua (owners "track", "recap")
ns.Recap_Events = events

local function Readable(...)
	return not ns.IsSecret(...)
end

-- Every note goes through here (ours and the ones from other modules via ns.Session_Note).
local function Note(entry)
	entry.at = entry.at or GetServerTime()
	local session = ns.Session_Current()
	if entry.kind == "rare" then
		if session.rares[entry.guid] then
			return -- the log may have dropped it already: this remembers it for the whole session
		end
		session.rares[entry.guid] = true
	end
	if ns.Recap_AddNote(session.log, entry, MAX_ENTRIES) and ns.RecapScene_Refresh then
		ns.RecapScene_Refresh()
	end
end

---------------------------------------------------------------------------------------------------------------
-- Gold

local function OnMoney(session, delta)
	ns.Recap_GoldAttribute(session.gold, delta, ns.Recap_MoneySource(context))
end

local lootWindows = 0 -- counts openings: a close only ends the loot context if no new window opened since

events:On("track", "LOOT_OPENED", function()
	lootWindows = lootWindows + 1
	context.loot = true
	for slot = 1, GetNumLootItems() do
		local sources = { GetLootSourceInfo(slot) }
		for i = 1, #sources, 2 do
			local guid = sources[i]
			if Readable(guid) and candidates[guid] then
				Note({ kind = "rare", guid = guid, title = candidates[guid] })
			end
		end
	end
end)

events:On("track", "LOOT_CLOSED", function()
	-- Auto-loot: the money can land just after the window closes.
	local opened = lootWindows
	C_Timer.After(0.5, function()
		if lootWindows == opened then
			context.loot = nil
		end
	end)
end)

events:On("track", "PLAYER_INTERACTION_MANAGER_FRAME_SHOW", function(_, kind)
	if CONTEXTS[kind] then
		context[CONTEXTS[kind]] = true
	end
end)

events:On("track", "PLAYER_INTERACTION_MANAGER_FRAME_HIDE", function(_, kind)
	if CONTEXTS[kind] then
		context[CONTEXTS[kind]] = nil
	end
end)

---------------------------------------------------------------------------------------------------------------
-- Loot

local function NoteItem(link, tries, count)
	local name, _, quality, _, _, _, _, _, _, icon = C_Item.GetItemInfo(link)
	if not name then
		if tries < ITEM_TRIES then
			C_Timer.After(ITEM_RETRY, function()
				if ns.recapModule.active then
					NoteItem(link, tries + 1, count)
				end
			end)
		end
		return
	end
	if ns.Value_NoteLoot then
		ns.Value_NoteLoot(link, count) -- Gold & value: every item, priced now
	end
	if quality and quality >= ns.recapDB.lootQuality then
		Note({ kind = "loot", title = name, icon = icon, quality = quality, link = link, itemID = ns.Recap_ItemID(link) })
	end
end

events:On("track", "CHAT_MSG_LOOT", function(_, text)
	if not Readable(text) then
		return -- chat lockdown
	end
	if not lootPatterns then
		lootPatterns = {}
		for kind, keys in pairs(LOOT_FORMATS) do
			local formats = {}
			for _, key in ipairs(keys) do
				formats[#formats + 1] = _G[key]
			end
			lootPatterns[kind] = ns.Recap_LootPatterns(formats)
		end
	end
	local link, count, kind = ns.Recap_LootMessage(text, lootPatterns)
	if link and ns.Recap_IsLoot(kind, context) then
		NoteItem(link, 0, count)
	end
end)

---------------------------------------------------------------------------------------------------------------
-- Rares

local function AddCandidate(guid, name)
	if candidates[guid] then
		return
	end
	if candidateCount >= MAX_CANDIDATES then
		wipe(candidates)
		candidateCount = 0
	end
	candidates[guid] = name or "Rare"
	candidateCount = candidateCount + 1
end

local function CheckVignette(vignetteGUID)
	local info = vignetteGUID and Readable(vignetteGUID) and C_VignetteInfo.GetVignetteInfo(vignetteGUID)
	if info and Readable(info.objectGUID, info.atlasName, info.name, info.isDead)
		and ns.Recap_IsRareVignette(info.atlasName, info.objectGUID) and not info.isDead then
		AddCandidate(info.objectGUID, info.name)
	end
end

local function ScanVignettes()
	for _, vignetteGUID in ipairs(C_VignetteInfo.GetVignettes() or {}) do
		CheckVignette(vignetteGUID)
	end
end

events:On("track", "VIGNETTES_UPDATED", ScanVignettes)

events:On("track", "VIGNETTE_MINIMAP_UPDATED", function(_, vignetteGUID)
	CheckVignette(vignetteGUID)
end)

local function NoteUnit(unit)
	local guid = UnitGUID(unit)
	if not guid or not Readable(guid) then
		return
	end
	local classification = UnitClassification(unit)
	if not Readable(classification) or not ns.Moments_IsRareClassification(classification) then
		return
	end
	if UnitCanAttack("player", unit) and not UnitIsDead(unit) then
		local name = UnitName(unit)
		AddCandidate(guid, Readable(name) and name or nil)
	end
end

events:On("track", "PLAYER_TARGET_CHANGED", function()
	NoteUnit("target")
end)

events:On("track", "UPDATE_MOUSEOVER_UNIT", function()
	NoteUnit("mouseover")
end)

events:On("track", "PLAYER_TARGET_DIED", function()
	local guid = UnitGUID("target")
	if guid and Readable(guid) and candidates[guid] then
		Note({ kind = "rare", guid = guid, title = candidates[guid] })
	end
end)

events:On("track", "PARTY_KILL", function(_, _, targetGUID)
	if targetGUID and Readable(targetGUID) and candidates[targetGUID] then
		Note({ kind = "rare", guid = targetGUID, title = candidates[targetGUID] })
	end
end)

---------------------------------------------------------------------------------------------------------------

function ns.RecapTrack_Start()
	for _, event in ipairs(EVENTS) do
		events:Watch("track", event)
	end
	ns.Recap_OnNote = Note
	ns.Session_OnMoney = OnMoney
	if ns.inWorld then
		ScanVignettes()
	end
end

function ns.RecapTrack_Stop()
	events:UnwatchAll("track")
	ns.Recap_OnNote = nil
	ns.Session_OnMoney = nil
	wipe(context)
end
