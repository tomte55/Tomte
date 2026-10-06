local addonName, ns = ...

-- Session recap tracking: what nobody else detects. Achievements, collections, renown, upgrades and tames come in
-- through ns.Session_Note (Moments, Gear Check, Hunter Pets).
-- - Gold: each money change is booked to what's open (loot window, auction house, mailbox, merchant).
-- - Loot: "You receive ..." messages for items at or above the quality option.
-- - Rares: rare units seen (vignettes, target, mouseover) count once when they die as your target, your party kills
--   them, or you loot them.
-- Every GUID, text and classification is checked for secret values: in instances they simply don't count.

local MAX_ENTRIES = 40
local MAX_CANDIDATES = 200
local ITEM_RETRY = 1 -- seconds before looking at an uncached item again
local P = Enum.PlayerInteractionType
local CONTEXTS = { [P.Merchant] = "vendor", [P.MailInfo] = "mail", [P.Auctioneer] = "auction" }
local LOOT_FORMATS = { "LOOT_ITEM_SELF", "LOOT_ITEM_SELF_MULTIPLE", "LOOT_ITEM_PUSHED_SELF",
	"LOOT_ITEM_PUSHED_SELF_MULTIPLE", "LOOT_ITEM_BONUS_ROLL_SELF", "LOOT_ITEM_BONUS_ROLL_SELF_MULTIPLE" }
local EVENTS = {
	"LOOT_OPENED", "LOOT_CLOSED", "PLAYER_INTERACTION_MANAGER_FRAME_SHOW", "PLAYER_INTERACTION_MANAGER_FRAME_HIDE",
	"CHAT_MSG_LOOT", "VIGNETTES_UPDATED", "VIGNETTE_MINIMAP_UPDATED", "PLAYER_TARGET_CHANGED", "UPDATE_MOUSEOVER_UNIT",
	"PLAYER_TARGET_DIED", "PARTY_KILL",
}

local context = {} -- { loot, vendor, mail, auction } = true while open
local candidates, candidateCount = {}, 0 -- [guid] = name: rares seen this session
local lootPatterns

local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(self, event, ...)
	self[event](self, ...)
end)

local function Readable(...)
	if not issecretvalue then
		return true
	end
	for i = 1, select("#", ...) do
		if issecretvalue((select(i, ...))) then
			return false
		end
	end
	return true
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

function events:LOOT_OPENED()
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
end

function events:LOOT_CLOSED()
	-- Auto-loot: the money can land just after the window closes.
	local opened = lootWindows
	C_Timer.After(0.5, function()
		if lootWindows == opened then
			context.loot = nil
		end
	end)
end

function events:PLAYER_INTERACTION_MANAGER_FRAME_SHOW(kind)
	if CONTEXTS[kind] then
		context[CONTEXTS[kind]] = true
	end
end

function events:PLAYER_INTERACTION_MANAGER_FRAME_HIDE(kind)
	if CONTEXTS[kind] then
		context[CONTEXTS[kind]] = nil
	end
end

---------------------------------------------------------------------------------------------------------------
-- Loot

local function NoteItem(link, tries, count)
	local name, _, quality, _, _, _, _, _, _, icon = C_Item.GetItemInfo(link)
	if not name then
		if tries < 5 then
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

function events:CHAT_MSG_LOOT(text)
	if not Readable(text) then
		return -- chat lockdown
	end
	if not lootPatterns then
		local formats = {}
		for _, key in ipairs(LOOT_FORMATS) do
			formats[#formats + 1] = _G[key]
		end
		lootPatterns = ns.Recap_LootPatterns(formats)
	end
	local link, count = ns.Recap_LootLink(text, lootPatterns)
	if link then
		NoteItem(link, 0, count)
	end
end

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

events.VIGNETTES_UPDATED = ScanVignettes

function events:VIGNETTE_MINIMAP_UPDATED(vignetteGUID)
	CheckVignette(vignetteGUID)
end

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
		AddCandidate(guid, UnitName(unit))
	end
end

function events:PLAYER_TARGET_CHANGED()
	NoteUnit("target")
end

function events:UPDATE_MOUSEOVER_UNIT()
	NoteUnit("mouseover")
end

function events:PLAYER_TARGET_DIED()
	local guid = UnitGUID("target")
	if guid and Readable(guid) and candidates[guid] then
		Note({ kind = "rare", guid = guid, title = candidates[guid] })
	end
end

function events:PARTY_KILL(_, targetGUID)
	if targetGUID and Readable(targetGUID) and candidates[targetGUID] then
		Note({ kind = "rare", guid = targetGUID, title = candidates[targetGUID] })
	end
end

---------------------------------------------------------------------------------------------------------------

function ns.RecapTrack_Start()
	for _, event in ipairs(EVENTS) do
		events:RegisterEvent(event)
	end
	ns.Recap_OnNote = Note
	ns.Session_OnMoney = OnMoney
	if ns.inWorld then
		ScanVignettes()
	end
end

function ns.RecapTrack_Stop()
	events:UnregisterAllEvents()
	ns.Recap_OnNote = nil
	ns.Session_OnMoney = nil
	wipe(context)
end
