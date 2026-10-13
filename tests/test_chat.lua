-- Run from the AddOns folder: lua Tomte/tests/test_chat.lua
local ns = {}
assert(loadfile("Tomte/Modules/Social/Data.lua"))("Tomte", ns)
assert(loadfile("Tomte/Modules/Chat/Data.lua"))("Tomte", ns)

local H = dofile("Tomte/tests/harness.lua")
local test, eq = H.test, H.eq
local function has(list, value)
	for _, v in ipairs(list) do
		if v == value then
			return true
		end
	end
	return false
end

local function wrap(word)
	return "<" .. word .. ">"
end

test("BuildKeywords: profession names and abbreviations", function()
	local words = ns.Chat_BuildKeywords({ { name = "Blacksmithing", skillLine = 164 }, { name = "Mining", skillLine = 186 } }, true, "")
	for _, w in ipairs({ "blacksmithing", "bs", "smith", "blacksmith", "mining", "miner", "ore" }) do
		eq(has(words, w), true, w)
	end
end)

test("BuildKeywords: own keywords added, duplicates dropped", function()
	local words = ns.Chat_BuildKeywords({ { name = "Blacksmithing", skillLine = 164 } }, true, "BS, thorium , LF smith")
	eq(has(words, "thorium"), true, "thorium")
	eq(has(words, "lf smith"), true, "lf smith")
	local count = 0
	for _, w in ipairs(words) do
		if w == "bs" then
			count = count + 1
		end
	end
	eq(count, 1, "bs once")
end)

test("BuildKeywords: professions off, unknown skill line, empty", function()
	local words = ns.Chat_BuildKeywords({ { name = "Blacksmithing", skillLine = 164 } }, false, "thorium")
	eq(#words, 1)
	eq(words[1], "thorium")
	words = ns.Chat_BuildKeywords({ { name = "Archaeology", skillLine = 794 } }, true, "")
	eq(#words, 1, "name only")
	eq(words[1], "archaeology")
	eq(#ns.Chat_BuildKeywords({}, true, ""), 0, "empty")
	eq(#ns.Chat_BuildKeywords(nil, true, nil), 0, "nil")
end)

test("Decide: keyword shows, no keyword hides, ignore word hides", function()
	local kw, ignore = { "bs", "blacksmithing" }, { "wts", "boost" }
	eq(ns.Chat_Decide("LF BS for crafting order", kw, ignore), true)
	eq(ns.Chat_Decide("WTS heroic boost cheap", kw, ignore), false)
	eq(ns.Chat_Decide("WTS Blacksmithing crafts, whisper", kw, ignore), false)
	eq(ns.Chat_Decide("WTS Blacksmithing crafts, whisper", kw, nil), true, "no ignore list")
	eq(ns.Chat_Decide("bsx is not a word match", kw, ignore), false, "whole words")
	eq(ns.Chat_Decide("anything", {}, ignore), false, "no keywords")
end)

test("Decide: keyword inside an item link counts", function()
	local text = "WTB |cffffffff|Hitem:12359::::::::80|h[Thorium Bar]|h|r x20"
	eq(ns.Chat_Decide(text, { "thorium" }, {}), true)
end)

test("Highlight: whole words, original case kept", function()
	eq(ns.Chat_Highlight("LF BS, need a bs now", { "bs" }, wrap), "LF <BS>, need a <bs> now")
	eq(ns.Chat_Highlight("BSX and xbs", { "bs" }, wrap), "BSX and xbs")
end)

test("Highlight: longest keyword wins, phrases work", function()
	eq(ns.Chat_Highlight("need a blacksmith", { "smith", "blacksmith" }, wrap), "need a <blacksmith>")
	eq(ns.Chat_Highlight("LF Smith please", { "lf smith" }, wrap), "<LF Smith> please")
end)

test("Highlight: never inside a link, escapes untouched", function()
	local link = "|cffffffff|Hitem:12359::::::::80|h[Thorium Bar]|h|r"
	eq(ns.Chat_Highlight("WTB " .. link .. " thorium", { "thorium" }, wrap), "WTB " .. link .. " <thorium>")
	eq(ns.Chat_Highlight("|cff00ff00green|r bs", { "bs", "ff00" }, wrap), "|cff00ff00green|r <bs>")
	eq(ns.Chat_Highlight("a || bs |Tpath:14|t", { "bs", "path" }, wrap), "a || <bs> |Tpath:14|t")
	eq(ns.Chat_Highlight("|cnPURE_RED_COLOR:red|r bs", { "bs", "red" }, wrap), "|cnPURE_RED_COLOR:<red>|r <bs>", "named color")
	eq(ns.Chat_Highlight("|Kq12|k bs", { "bs", "q12" }, wrap), "|Kq12|k <bs>", "protected name")
end)

test("Highlight: no words, no change", function()
	eq(ns.Chat_Highlight("hello", {}, wrap), "hello")
end)

test("ParseLabels", function()
	local labels = ns.Chat_ParseLabels("Trade=T, Services = Srv,bad, Guild=Gu,=x")
	eq(labels.trade, "T")
	eq(labels.services, "Srv")
	eq(labels.guild, "Gu")
	eq(labels.bad, nil)
	eq(next(ns.Chat_ParseLabels("")), nil, "empty")
	eq(next(ns.Chat_ParseLabels(nil)), nil, "nil")
end)

test("ChannelTag: every style", function()
	local labels = {}
	eq(ns.Chat_ChannelTag("full", "2", "Trade - City", "Trade", 2, labels), "2. Trade - City")
	eq(ns.Chat_ChannelTag("name", "2", "Trade - City", "Trade", 2, labels), "2. Trade")
	eq(ns.Chat_ChannelTag("numshort", "2", "Trade - City", "Trade", 2, labels), "2. T")
	eq(ns.Chat_ChannelTag("short", "2", "Trade - City", "Trade", 2, labels), "T")
	eq(ns.Chat_ChannelTag("number", "2", "Trade - City", "Trade", 2, labels), "2")
	eq(ns.Chat_ChannelTag("bogus", "2", "Trade - City", "Trade", 2, labels), "2. Trade", "unknown style = name")
end)

test("ChannelTag: custom labels and unknown channels", function()
	local labels = ns.Chat_ParseLabels("Trade=Tr, mychan=MC")
	eq(ns.Chat_ChannelTag("short", "2", "Trade - City", "Trade", 2, labels), "Tr")
	eq(ns.Chat_ChannelTag("name", "2", "Trade - City", "Trade", 2, labels), "2. Tr")
	eq(ns.Chat_ChannelTag("short", "5", "MyChan", nil, 0, labels), "MC", "by base name")
	eq(ns.Chat_ChannelTag("short", "6", "Raiders", nil, 0, {}), "Raiders", "unknown: base name")
	eq(ns.Chat_ChannelTag("short", "3", "Trade (Services) - City", "Services", 42, {}), "S")
end)

local globals = {
	CHAT_GUILD_GET = "|Hchannel:GUILD|h[Guild]|h %s: ",
	CHAT_OFFICER_GET = "|Hchannel:OFFICER|h[Officer]|h %s: ",
	CHAT_PARTY_GET = "|Hchannel:PARTY|h[Party]|h %s: ",
	CHAT_PARTY_LEADER_GET = "|Hchannel:PARTY|h[Party Leader]|h %s: ",
	CHAT_RAID_GET = "|Hchannel:RAID|h[Raid]|h %s: ",
	CHAT_RAID_LEADER_GET = "|Hchannel:RAID|h[Raid Leader]|h %s: ",
	CHAT_RAID_WARNING_GET = "[Raid Warning] %s: ",
	CHAT_INSTANCE_CHAT_GET = "|Hchannel:INSTANCE_CHAT|h[Instance]|h %s: ",
}
local function getGlobal(name)
	return globals[name]
end

test("GroupTags from the _GET globals", function()
	local tags, rw = ns.Chat_GroupTags(getGlobal)
	eq(tags["Guild"], "G")
	eq(tags["Party Leader"], "PL")
	eq(tags["Raid Leader"], "RL")
	eq(tags["Instance"], "I")
	eq(tags["Instance Leader"], nil, "missing global skipped")
	eq(rw, "Raid Warning")
end)

local function ctx(style, group, labels)
	local tags, rw = ns.Chat_GroupTags(getGlobal)
	return {
		style = style,
		labels = labels or {},
		group = group,
		groupTags = tags,
		raidWarning = rw,
		channelInfo = function(number)
			if number == "2" then
				return "Trade", 2
			end
		end,
	}
end

test("ShortenLine: numbered channel", function()
	local line = "|Hchannel:channel:2|h[2. Trade - City]|h |Hplayer:Thrall|h[Thrall]|h: LF BS"
	eq(ns.Chat_ShortenLine(line, ctx("numshort", true)), "|Hchannel:channel:2|h[2. T]|h |Hplayer:Thrall|h[Thrall]|h: LF BS")
	eq(ns.Chat_ShortenLine(line, ctx("full", true)), line, "full = unchanged")
end)

test("ShortenLine: guild and raid warning, group off", function()
	local line = "|Hchannel:GUILD|h[Guild]|h |Hplayer:Jaina|h[Jaina]|h: hi"
	eq(ns.Chat_ShortenLine(line, ctx("name", true)), "|Hchannel:GUILD|h[G]|h |Hplayer:Jaina|h[Jaina]|h: hi")
	eq(ns.Chat_ShortenLine(line, ctx("name", false)), line, "group off")
	eq(ns.Chat_ShortenLine(line, ctx("name", true, { guild = "Gu" })), "|Hchannel:GUILD|h[Gu]|h |Hplayer:Jaina|h[Jaina]|h: hi")
	eq(ns.Chat_ShortenLine("[Raid Warning] Jaina: stack", ctx("name", true)), "[RW] Jaina: stack")
	eq(ns.Chat_ShortenLine("12:00 [Raid Warning] Jaina: stack", ctx("name", true)), "12:00 [RW] Jaina: stack")
	eq(ns.Chat_ShortenLine("[12:00:01] [Raid Warning] Jaina: stack", ctx("name", true)), "[12:00:01] [RW] Jaina: stack")
	local said = "|Hchannel:GUILD|h[Guild]|h Jaina: type [Raid Warning] here"
	eq(ns.Chat_ShortenLine(said, ctx("name", true)), "|Hchannel:GUILD|h[G]|h Jaina: type [Raid Warning] here", "only as the line's tag")
end)

test("ShortenLine: leaves other lines alone", function()
	eq(ns.Chat_ShortenLine("You receive loot: [Thorium Bar].", ctx("short", true)), "You receive loot: [Thorium Bar].")
	local odd = "|Hchannel:WEIRD|h[Something]|h text"
	eq(ns.Chat_ShortenLine(odd, ctx("short", true)), odd, "unknown link target")
	local noprefix = "|Hchannel:channel:9|h[Odd]|h text"
	eq(ns.Chat_ShortenLine(noprefix, ctx("short", true)), noprefix, "no N. prefix")
end)

test("PlainLine: links, colors, textures and Battle.net names", function()
	eq(ns.Chat_PlainLine("|cffa335ee|Hitem:12345::::|h[Thunderfury]|h|r drops"), "[Thunderfury] drops")
	eq(ns.Chat_PlainLine("|Hplayer:Jaina-Realm:12|h[|cffff7c0aJaina|r]|h: hi"), "[Jaina]: hi", "colored name in a link")
	eq(ns.Chat_PlainLine("|HBNplayer:|Kq12|k:34:56|h[|Kq12|k]|h whispers: yo"), "[" .. ns.CHAT_BNET_NAME .. "] whispers: yo")
	eq(ns.Chat_PlainLine("{rt1} |TInterface\\TargetingFrame\\UI-RaidTargetingIcon_1:0|t go"), "{rt1}  go")
	eq(ns.Chat_PlainLine("|A:questlog-questtypeicon-daily:12:12|a Daily"), " Daily")
	eq(ns.Chat_PlainLine("|cnPURE_RED_COLOR:red|r text"), "red text", "named color")
	eq(ns.Chat_PlainLine("a || b ||cffffffff"), "a | b |cffffffff", "escaped bars stay")
	eq(ns.Chat_PlainLine("line one|nline two   "), "line one\nline two", "|n and trailing spaces")
end)

test("CleanLine: no timestamp, channel tag or name brackets", function()
	local line = "12:00 |Hchannel:channel:2|h[2. Trade - City]|h |Hplayer:Jaina-Realm:9:CHANNEL:2|h[Jaina]|h: WTS ore"
	eq(ns.Chat_CleanLine(line), "Jaina: WTS ore")
	eq(ns.Chat_CleanLine("[12:00:01] |Hchannel:GUILD|h[Guild]|h |Hplayer:Jaina|h[Jaina]|h: hi"), "Jaina: hi")
	eq(ns.Chat_CleanLine("03:15 PM You receive loot: |Hitem:1|h[Bar]|h."), "You receive loot: [Bar].")
	eq(ns.Chat_CleanLine("|HBNplayer:|Kq1|k:2:3|h[|Kq1|k]|h: yo"), ns.CHAT_BNET_NAME .. ": yo")
	eq(ns.Chat_CleanLine("[Tomte] 12:00 stays"), "[Tomte] 12:00 stays", "only a leading timestamp")
end)

test("CopyText: hidden lines, clean drops empty ones", function()
	local lines = { "|cff00ff00one|r", false, "|T1:0|t", "12:00 two" }
	eq(ns.Chat_CopyText(lines, false), "one\n" .. ns.CHAT_HIDDEN_LINE .. "\n\n12:00 two")
	eq(ns.Chat_CopyText(lines, true), "one\n" .. ns.CHAT_HIDDEN_LINE .. "\ntwo")
	eq(ns.Chat_CopyText({}, true), "")
end)

H.done()
