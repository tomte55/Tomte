local addonName, ns = ...

-- Compat: one place for game APIs that retail moved or renamed, so the same code runs on retail and on World of
-- Warcraft: Forever (game type camelot, on the retail engine). Each helper looks the API up when it's called, retail
-- name first, the older name second, so retail calls exactly what it called before. Unit-tested in
-- tests/test_compat.lua. See docs/superpowers/specs/2026-11-05-tomte-forever-all-modules.md.

-- An addon's TOC field. pcall: the API errors on an addon name the client doesn't know.
function ns.AddOnMetadata(addon, field)
	local get = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
	if not get then
		return nil
	end
	local ok, value = pcall(get, addon, field)
	return ok and value or nil
end

-- True when the Forever TOC loaded us (it carries "## X-Tomte-Flavor: forever"); code that differs checks this.
ns.FOREVER = ns.AddOnMetadata(addonName, "X-Tomte-Flavor") == "forever"

-- For settings rows of retail-only features: shown = ns.NotForever.
function ns.NotForever()
	return not ns.FOREVER
end

-- Chat ------------------------------------------------------------------------------------------------------------

-- ChatFrameUtil.<name> on retail, else the Classic global.
local function ChatAPI(name, classic)
	return (ChatFrameUtil and ChatFrameUtil[name]) or _G[classic]
end

-- Forever's character names can have a space ("Mira Ashvale"). SendTell types "/w name" for the chat box to read, which takes
-- "Mira Ashvale-Realm" as written and can't send to it (seen in game). So there the box gets the name directly, without your own
-- realm, the way the game's own reply does it (ChatFrameUtil.ReplyTell).
local function ForeverTell(name)
	local util = ChatFrameUtil
	if not (ns.FOREVER and util and util.ChooseBoxForSend and util.GetActiveWindow and util.OpenChat) then
		return false
	end
	local box = util.ChooseBoxForSend()
	box:SetChatType("WHISPER")
	box:SetTellTarget(Ambiguate and Ambiguate(name, "none") or name)
	box:UpdateHeader()
	if box ~= util.GetActiveWindow() then
		util.OpenChat("")
	end
	return true
end

function ns.Chat_SendTell(name)
	if ForeverTell(name) then
		return
	end
	return ChatAPI("SendTell", "ChatFrame_SendTell")(name)
end

function ns.Chat_SendBNetTell(token)
	return ChatAPI("SendBNetTell", "ChatFrame_SendBNetTell")(token)
end

function ns.Chat_ReplyTell()
	return ChatAPI("ReplyTell", "ChatFrame_ReplyTell")()
end

function ns.Chat_Open(text)
	return ChatAPI("OpenChat", "ChatFrame_OpenChat")(text)
end

function ns.Chat_InsertLink(link)
	return ChatAPI("InsertLink", "ChatEdit_InsertLink")(link)
end

function ns.Chat_AddFilter(event, fn)
	return ChatAPI("AddMessageEventFilter", "ChatFrame_AddMessageEventFilter")(event, fn)
end

function ns.Chat_RemoveFilter(event, fn)
	return ChatAPI("RemoveMessageEventFilter", "ChatFrame_RemoveMessageEventFilter")(event, fn)
end

function ns.Chat_Send(text, chatType, language, target)
	local send = (C_ChatInfo and C_ChatInfo.SendChatMessage) or SendChatMessage
	return send(text, chatType, language, target)
end

-- An emote by token ("BOW"), at target (a name) or, without one, at your current target. 12.0 moved DoEmote.
function ns.Chat_Emote(token, target)
	local perform = (C_ChatInfo and C_ChatInfo.PerformEmote) or DoEmote
	return perform(token, target)
end

-- fn(text, chatType, language, target) after every chat message the player sends.
function ns.Chat_HookSend(fn)
	if C_ChatInfo and C_ChatInfo.SendChatMessage then
		hooksecurefunc(C_ChatInfo, "SendChatMessage", fn)
	else
		hooksecurefunc("SendChatMessage", fn)
	end
end

-- Realm -----------------------------------------------------------------------------------------------------------

-- World of Warcraft: Forever stopped telling addons the realm in a 1.60.1 hotfix (2026-11-21): GetRealmName and
-- GetNormalizedRealmName answer "" and GetRealmID 0 (seen in game). A player GUID still names the server
-- ("Player-6939-00BF0A06"), so Tomte remembers each realm it has seen by that number: known is TomteDB.realms,
-- { [realm number from a GUID] = normalized realm name }, filled while the game still answered (and from older
-- saved characters by migration 24).

local function GuidRealmID(guid)
	return type(guid) == "string" and guid:match("^Player%-(%d+)%-") or nil
end

-- Notes a realm seen with a player GUID. Empty realms and other GUIDs teach nothing.
function ns.Realm_Learn(known, guid, realm)
	local id = GuidRealmID(guid)
	if id and type(realm) == "string" and realm ~= "" then
		known[id] = realm
	end
end

-- The realm last seen on this GUID's server, or nil.
function ns.Realm_Find(known, guid)
	local id = GuidRealmID(guid)
	return id and known[id] or nil
end

-- Your realm, normalized (no spaces or dashes): the game's answer, else the one last seen on your server; nil when
-- neither is known. Use this instead of GetNormalizedRealmName or GetRealmName, which can answer "".
function ns.RealmName()
	local known = ns.db and ns.db.realms
	local guid = UnitGUID and UnitGUID("player")
	local live = GetNormalizedRealmName and GetNormalizedRealmName()
	if type(live) == "string" and live ~= "" then
		if known then
			ns.Realm_Learn(known, guid, live)
		end
		return live
	end
	return known and ns.Realm_Find(known, guid) or nil
end

-- Events ----------------------------------------------------------------------------------------------------------

-- Whether this client knows an event (RegisterEvent errors on one it doesn't). Without C_EventUtils, a test
-- registration on a scratch frame answers; the pcall is for exactly that error.
local probe
function ns.EventValid(event)
	if C_EventUtils and C_EventUtils.IsEventValid then
		return C_EventUtils.IsEventValid(event) == true
	end
	probe = probe or CreateFrame("Frame")
	local ok = pcall(probe.RegisterEvent, probe, event)
	if ok then
		probe:UnregisterEvent(event)
	end
	return ok
end

-- Bags ------------------------------------------------------------------------------------------------------------

-- The item ID in a bag slot, or nil. The plain call where the client has it: GetContainerItemInfo makes a table per
-- slot, and a scan of every slot on each bag update was a good part of the garbage Tomte made (Performance report).
function ns.BagSlotItemID(bag, slot)
	local container = C_Container
	if container.GetContainerItemID then
		return container.GetContainerItemID(bag, slot)
	end
	local info = container.GetContainerItemInfo(bag, slot)
	return info and info.itemID
end

-- Spells ----------------------------------------------------------------------------------------------------------

function ns.SpellKnown(spellID)
	local known = (C_SpellBook and C_SpellBook.IsSpellKnown) or IsSpellKnown
	return known ~= nil and known(spellID) == true
end

-- Specs -----------------------------------------------------------------------------------------------------------

-- The player's spec ID and name, or nil where the game has no specs or none is chosen yet.
local function Spec()
	local info = C_SpecializationInfo
	local index = info and info.GetSpecialization and info.GetSpecialization()
	if not index or index == 0 then
		return nil
	end
	return info.GetSpecializationInfo(index)
end

function ns.SpecID()
	return (Spec())
end

function ns.SpecName()
	return select(2, Spec())
end
