local addonName, ns = ...

-- Compat: one place for game APIs that retail moved or renamed, so the same code runs on retail and on World of
-- Warcraft: Forever (a Classic-style client). Each helper looks the API up when it's called, retail name first,
-- the Classic name second, so retail calls exactly what it called before. Unit-tested in tests/test_compat.lua.
-- See docs/superpowers/specs/2026-10-25-tomte-forever-design.md.

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

function ns.Chat_SendTell(name)
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

-- fn(text, chatType, language, target) after every chat message the player sends.
function ns.Chat_HookSend(fn)
	if C_ChatInfo and C_ChatInfo.SendChatMessage then
		hooksecurefunc(C_ChatInfo, "SendChatMessage", fn)
	else
		hooksecurefunc("SendChatMessage", fn)
	end
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
