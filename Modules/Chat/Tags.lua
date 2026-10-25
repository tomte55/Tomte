local addonName, ns = ...

-- Channel Tags module: shorter tags in front of chat lines ("[2. Trade - City]" -> "[2. T]", "[Guild]" -> "[G]").
-- A message filter can't do it (the chat frame matches the channel by the length of its name), so after each chat
-- window's AddMessage (hooksecurefunc: replacing AddMessage would taint the rest of Blizzard's chat handler, which
-- then trips over secret whisper senders) the line just added is rewritten with TransformMessages, which Blizzard
-- offers addons as a secure barrier. Secret lines (chat lockdown: instances, encounters, M+, PvP) stay as they are.

-- The settings preview's sample lines. Its channels answer for themselves rather than through C_ChatInfo: the
-- player's channel 2 may be anything.
local SAMPLE_CHANNELS = { -- [number] = { shortcut, zone channel ID }
	["1"] = { "General", 1 },
	["2"] = { "Trade", 2 },
}
local SAMPLE_LINES = {
	{ channel = "1", name = "General - Stormwind City", who = "Aldric", text = "Anyone seen the flight master?" },
	{ channel = "2", name = "Trade - City", who = "Mira", text = "WTS enchants, tips welcome" },
	{ chatType = "GUILD", who = "Kesha", text = "Raid at eight, bring flasks" },
	{ chatType = "PARTY", who = "Aldric", text = "ready" },
}
local LINE_GAP = 2
local FALLBACK_CHAT_SIZE = 14 -- when the chat window's font size can't be read

local UI = ns.UI

local module
local ctx = { labels = {}, groupTags = {} }
local wrapped = {} -- [frame] = true

local function Readable(value)
	return not canaccessvalue or canaccessvalue(value)
end

local function ChannelInfo(number)
	local info = C_ChatInfo.GetChannelInfoFromIdentifier(number)
	if info then
		return info.shortcut, info.zoneChannelID
	end
end
ctx.channelInfo = ChannelInfo

local function Rebuild()
	local db = module.db
	ctx.style = db.style
	ctx.group = db.group
	ctx.labels = ns.Chat_ParseLabels(db.labels)
	ctx.groupTags, ctx.raidWarning = ns.Chat_GroupTags(function(name)
		return _G[name]
	end)
end

-- The shortened line, or nil when there's nothing to change. The pcall is a guard: this runs on every chat line
-- from inside Blizzard's AddMessage, and a line format the parser didn't expect must not raise an error per message.
local function Shorten(line)
	local ok, short = pcall(ns.Chat_ShortenLine, line, ctx)
	if ok and type(short) == "string" and short ~= line then
		return short
	end
	return nil
end

local MaxWindows = ns.Chat_MaxWindows -- Chat/Tabs.lua

-- Runs after the window stored line. Rewrites that one entry (the first stored entry with exactly this text).
local function AfterAddMessage(frame, line)
	if not module.active or type(line) ~= "string" or not Readable(line) then
		return
	end
	if not line:find("[", 1, true) then
		return -- no tag: skip the history walk
	end
	local short = Shorten(line)
	if not short then
		return
	end
	local done = false
	frame:TransformMessages(function(message)
		if done or not Readable(message) or message ~= line then
			return false
		end
		done = true
		return true
	end, function(_, ...)
		return short, ...
	end)
end

-- Once per window; the hook does nothing while the module is off.
local function HookFrames()
	for i = 1, MaxWindows() do
		local frame = _G["ChatFrame" .. i]
		if frame and not wrapped[frame] and frame.AddMessage and frame.TransformMessages then
			wrapped[frame] = true
			hooksecurefunc(frame, "AddMessage", AfterAddMessage)
		end
	end
end

local function OnChange()
	if module.active then
		Rebuild()
	end
end

-- Settings preview: sample lines in Blizzard's own chat formats, shortened by the same Chat_ShortenLine the hook uses.

-- The line as the chat window gets it (the CHAT_<type>_GET formats), and its chat type for the color.
local function SampleLine(sample)
	local who = "|Hplayer:" .. sample.who .. "|h[" .. sample.who .. "]|h"
	if sample.channel then
		local tag = "|Hchannel:channel:" .. sample.channel .. "|h[" .. sample.channel .. ". " .. sample.name .. "]|h "
		return tag .. (CHAT_CHANNEL_GET or "%s: "):format(who) .. sample.text, "CHANNEL" .. sample.channel
	end
	local format = _G["CHAT_" .. sample.chatType .. "_GET"] or "%s: "
	return format:format(who) .. sample.text, sample.chatType
end

local function TagsPreview(host, get)
	local ctx = {
		style = get("style"),
		group = get("group"),
		labels = ns.Chat_ParseLabels(get("labels")),
		channelInfo = function(number)
			local c = SAMPLE_CHANNELS[number]
			if c then
				return c[1], c[2]
			end
		end,
	}
	ctx.groupTags, ctx.raidWarning = ns.Chat_GroupTags(function(name)
		return _G[name]
	end)
	local _, size = DEFAULT_CHAT_FRAME:GetFont()
	size = size or FALLBACK_CHAT_SIZE
	host.lines = host.lines or {}
	local width, y = 0, 0
	for i, sample in ipairs(SAMPLE_LINES) do
		local fs = host.lines[i]
		if not fs then
			fs = UI.Text(host, size, "text", "chat")
			host.lines[i] = fs
		end
		UI.SetFont(fs, "chat", size)
		local line, chatType = SampleLine(sample)
		fs:SetText(ns.Chat_ShortenLine(line, ctx))
		local info = ChatTypeInfo[chatType]
		if info then
			fs:SetTextColor(info.r, info.g, info.b)
		else
			UI.SetTextRole(fs, "text")
		end
		fs:ClearAllPoints()
		fs:SetPoint("TOPLEFT", 0, -y)
		width = math.max(width, math.ceil(fs:GetUnboundedStringWidth()))
		y = y + math.ceil(fs:GetStringHeight()) + LINE_GAP
	end
	return width, y - LINE_GAP
end

local options = {
	{ type = "header", label = "Tags" },
	{ type = "dropdown", key = "style", label = "Channel tags", onChange = OnChange, preview = TagsPreview,
		choices = function()
			return ns.CHAT_TAG_STYLES
		end, tooltip = "How numbered channels (General, Trade, Services, LookingForGroup, your own channels) show. Short names: Gen, T, S, LFG, LD; other channels keep their name." },
	{ type = "input", key = "labels", label = "Custom labels", placeholder = "Trade=Tr, Guild=Gu", onChange = OnChange,
		preview = TagsPreview, tooltip = "Your own short names, as Name=Label separated by commas. Name is the channel's name as chat shows it (Trade, Services, General, a custom channel) or a tag like Guild or Party." },
	{ type = "checkbox", key = "group", label = "Shorten guild, party and raid tags", onChange = OnChange,
		preview = TagsPreview, tooltip = "[Guild] -> [G], [Officer] -> [O], [Party] -> [P], [Party Leader] -> [PL], [Raid] -> [R], [Raid Leader] -> [RL], [Raid Warning] -> [RW], [Instance] -> [I], [Instance Leader] -> [IL].\n\nIn instances, encounters, M+ and PvP the game hides chat from addons, so tags show in full there." },
}

module = ns.RegisterModule({
	key = "chattags",
	name = "Channel Tags",
	category = "chat",
	icon = 237132, -- inv_inscription_papyrus
	summary = "Short channel tags like [T] and [G] in front of chat lines.",
	description = "Shorter tags in front of chat lines: [2. Trade - City] becomes [2. Trade], [T] or what you pick; [Guild] becomes [G].",
	enabledByDefault = false,
	keep = { "labels" },
	defaults = {
		style = "name",
		labels = "",
		group = true,
	},
	toggle = function(active)
		if active then
			Rebuild()
			HookFrames()
		end
	end,
	options = options,
})
