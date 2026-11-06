-- Run from the AddOns folder: lua Tomte/tests/test_compat.lua
local H = dofile("Tomte/tests/harness.lua")
local test, eq = H.test, H.eq

local GLOBALS = {
	"C_AddOns", "GetAddOnMetadata", "ChatFrameUtil", "ChatFrame_SendTell", "ChatFrame_SendBNetTell",
	"ChatFrame_ReplyTell", "ChatFrame_OpenChat", "ChatEdit_InsertLink", "ChatFrame_AddMessageEventFilter",
	"ChatFrame_RemoveMessageEventFilter", "C_ChatInfo", "SendChatMessage", "C_SpecializationInfo", "hooksecurefunc",
	"C_SpellBook", "IsSpellKnown", "C_EventUtils", "CreateFrame", "Ambiguate",
}

-- Loads Compat.lua with only the given game globals present.
local function Load(globals)
	for _, name in ipairs(GLOBALS) do
		_G[name] = nil
	end
	for name, value in pairs(globals or {}) do
		_G[name] = value
	end
	local ns = {}
	assert(loadfile("Tomte/Core/Compat.lua"))("Tomte", ns)
	return ns
end

local function Metadata(flavor)
	return { GetAddOnMetadata = function(_, field)
		return field == "X-Tomte-Flavor" and flavor or nil
	end }
end

test("retail metadata sets the Forever flag from the TOC tag", function()
	eq(Load({ C_AddOns = Metadata("forever") }).FOREVER, true, "tagged")
	eq(Load({ C_AddOns = Metadata(nil) }).FOREVER, false, "untagged")
end)

test("classic metadata falls back to the global", function()
	local ns = Load({ GetAddOnMetadata = function(addon, field)
		return addon == "Tomte" and field == "Version" and "1.22.0" or nil
	end })
	eq(ns.AddOnMetadata("Tomte", "Version"), "1.22.0", "version")
	eq(ns.FOREVER, false, "no tag")
end)

test("metadata that errors reads as nil", function()
	local ns = Load({ C_AddOns = { GetAddOnMetadata = function()
		error("bad addon")
	end } })
	eq(ns.AddOnMetadata("Tomte", "Version"), nil, "value")
	eq(ns.FOREVER, false, "flag")
end)

test("no metadata API at all", function()
	local ns = Load({})
	eq(ns.AddOnMetadata("Tomte", "Version"), nil, "value")
	eq(ns.FOREVER, false, "flag")
end)

test("retail chat calls ChatFrameUtil only", function()
	local calls = {}
	local ns = Load({
		ChatFrameUtil = { SendTell = function(name)
			calls[#calls + 1] = "util:" .. name
		end },
		ChatFrame_SendTell = function(name)
			calls[#calls + 1] = "old:" .. name
		end,
	})
	ns.Chat_SendTell("Aldric")
	eq(#calls, 1, "one call")
	eq(calls[1], "util:Aldric", "retail API")
end)

test("on Forever a whisper goes straight to the chat box, without your own realm", function()
	local box = {}
	function box:SetChatType(kind)
		self.kind = kind
	end
	function box:SetTellTarget(target)
		self.target = target
	end
	function box:UpdateHeader()
		self.updated = true
	end
	local typed, opened
	local ns = Load({
		C_AddOns = { GetAddOnMetadata = function(_, field)
			return field == "X-Tomte-Flavor" and "forever" or nil
		end },
		Ambiguate = function(name)
			return (name:gsub("%-MyRealm$", ""))
		end,
		ChatFrameUtil = {
			SendTell = function(name)
				typed = name
			end,
			ChooseBoxForSend = function()
				return box
			end,
			GetActiveWindow = function()
				return nil
			end,
			OpenChat = function(text)
				opened = text
			end,
		},
	})
	ns.Chat_SendTell("Mira Ashvale-MyRealm")
	eq(box.kind, "WHISPER")
	eq(box.target, "Mira Ashvale", "your own realm comes off")
	eq(box.updated, true)
	eq(opened, "", "opens the box")
	eq(typed, nil, "nothing typed for the box to read")
	ns.Chat_SendTell("Mira Ashvale-OtherRealm")
	eq(box.target, "Mira Ashvale-OtherRealm", "another realm stays")
end)

test("classic chat falls back to the ChatFrame_ globals", function()
	local told
	local ns = Load({
		ChatFrame_SendTell = function(name)
			told = name
		end,
		ChatEdit_InsertLink = function(link)
			return link == "x"
		end,
	})
	ns.Chat_SendTell("Aldric")
	eq(told, "Aldric", "tell")
	eq(ns.Chat_InsertLink("x"), true, "insert link result")
end)

test("chat filters use the classic globals", function()
	local added, removed
	local ns = Load({
		ChatFrame_AddMessageEventFilter = function(event, fn)
			added = event
		end,
		ChatFrame_RemoveMessageEventFilter = function(event, fn)
			removed = event
		end,
	})
	ns.Chat_AddFilter("CHAT_MSG_CHANNEL", print)
	ns.Chat_RemoveFilter("CHAT_MSG_CHANNEL", print)
	eq(added, "CHAT_MSG_CHANNEL", "added")
	eq(removed, "CHAT_MSG_CHANNEL", "removed")
end)

test("send passes all four arguments to the global", function()
	local got
	local ns = Load({ SendChatMessage = function(...)
		got = { ... }
	end })
	ns.Chat_Send("hi", "WHISPER", nil, "Kesha")
	eq(got[1], "hi", "text")
	eq(got[2], "WHISPER", "type")
	eq(got[3], nil, "language")
	eq(got[4], "Kesha", "target")
end)

test("send prefers C_ChatInfo", function()
	local where
	local ns = Load({
		C_ChatInfo = { SendChatMessage = function()
			where = "retail"
		end },
		SendChatMessage = function()
			where = "global"
		end,
	})
	ns.Chat_Send("hi", "SAY")
	eq(where, "retail", "retail API")
end)

test("hooking sends: the table on retail, the global on classic", function()
	local hooked = {}
	local function Hook(a, b)
		hooked[#hooked + 1] = type(a) == "table" and "table:" .. b or "global:" .. a
	end
	Load({ C_ChatInfo = { SendChatMessage = print }, hooksecurefunc = Hook }).Chat_HookSend(print)
	Load({ SendChatMessage = print, hooksecurefunc = Hook }).Chat_HookSend(print)
	eq(hooked[1], "table:SendChatMessage", "retail")
	eq(hooked[2], "global:SendChatMessage", "classic")
end)

test("no specs without C_SpecializationInfo", function()
	local ns = Load({})
	eq(ns.SpecName(), nil, "name")
	eq(ns.SpecID(), nil, "id")
end)

test("specs on retail", function()
	local ns = Load({ C_SpecializationInfo = {
		GetSpecialization = function()
			return 2
		end,
		GetSpecializationInfo = function(index)
			return index == 2 and 66 or nil, index == 2 and "Protection" or nil
		end,
	} })
	eq(ns.SpecName(), "Protection", "name")
	eq(ns.SpecID(), 66, "id")
end)

test("no spec chosen yet", function()
	local ns = Load({ C_SpecializationInfo = {
		GetSpecialization = function()
			return nil
		end,
		GetSpecializationInfo = function()
			error("no index")
		end,
	} })
	eq(ns.SpecName(), nil, "name")
end)

test("a C_SpecializationInfo without GetSpecialization means no specs", function()
	local ns = Load({ C_SpecializationInfo = {} })
	eq(ns.SpecName(), nil, "name")
	eq(ns.SpecID(), nil, "id")
end)

test("spec index 0 counts as no spec", function()
	local ns = Load({ C_SpecializationInfo = {
		GetSpecialization = function()
			return 0
		end,
		GetSpecializationInfo = function()
			return 1, "Wrong"
		end,
	} })
	eq(ns.SpecName(), nil, "name")
end)

test("spell known: C_SpellBook on retail, the global on classic", function()
	local retail = Load({
		C_SpellBook = { IsSpellKnown = function(id)
			return id == 131474
		end },
		IsSpellKnown = function()
			error("old API used")
		end,
	})
	eq(retail.SpellKnown(131474), true, "retail known")
	eq(retail.SpellKnown(7620), false, "retail unknown")
	local classic = Load({ IsSpellKnown = function(id)
		return id == 7620
	end })
	eq(classic.SpellKnown(7620), true, "classic known")
	eq(Load({}).SpellKnown(7620), false, "no API")
end)

test("NotForever is the opposite of the flag", function()
	eq(Load({ C_AddOns = Metadata("forever") }).NotForever(), false, "forever")
	eq(Load({}).NotForever(), true, "retail")
end)

test("event valid: C_EventUtils when there", function()
	local ns = Load({ C_EventUtils = { IsEventValid = function(event)
		return event == "READY_CHECK"
	end } })
	eq(ns.EventValid("READY_CHECK"), true, "known")
	eq(ns.EventValid("LFG_PROPOSAL_SHOW"), false, "unknown")
end)

test("event valid: a test registration without C_EventUtils", function()
	local frame = { RegisterEvent = function(_, event)
		if event ~= "READY_CHECK" then
			error("unknown event")
		end
	end, UnregisterEvent = function() end }
	local ns = Load({ CreateFrame = function()
		return frame
	end })
	eq(ns.EventValid("READY_CHECK"), true, "known")
	eq(ns.EventValid("LFG_PROPOSAL_SHOW"), false, "unknown")
end)

H.done()
