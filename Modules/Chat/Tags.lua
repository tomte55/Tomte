local addonName, ns = ...

-- Channel Tags module: shorter tags in front of chat lines ("[2. Trade - City]" -> "[2. T]", "[Guild]" -> "[G]").
-- A message filter can't do it (the chat frame matches the channel by the length of its name), so after each chat
-- window's AddMessage (hooksecurefunc: replacing AddMessage would taint the rest of Blizzard's chat handler, which
-- then trips over secret whisper senders) the line just added is rewritten with TransformMessages, which Blizzard
-- offers addons as a secure barrier. Secret lines (chat lockdown: instances, encounters, M+, PvP) stay as they are.

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

-- The shortened line, or nil when there's nothing to change.
local function Shorten(line)
	local ok, short = pcall(ns.Chat_ShortenLine, line, ctx)
	if ok and type(short) == "string" and short ~= line then
		return short
	end
	return nil
end

local function MaxWindows()
	return (Constants and Constants.ChatFrameConstants and Constants.ChatFrameConstants.MaxChatWindows) or NUM_CHAT_WINDOWS or 10
end

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

local options = {
	{ type = "dropdown", key = "style", label = "Channel tags", onChange = OnChange, choices = function()
		return ns.CHAT_TAG_STYLES
	end, tooltip = "How numbered channels (General, Trade, Services, LookingForGroup, your own channels) show. Short names: Gen, T, S, LFG, LD; other channels keep their name." },
	{ type = "input", key = "labels", label = "Custom labels", placeholder = "Trade=Tr, Guild=Gu", onChange = OnChange,
		tooltip = "Your own short names, as Name=Label separated by commas. Name is the channel's name as chat shows it (Trade, Services, General, a custom channel) or a tag like Guild or Party." },
	{ type = "checkbox", key = "group", label = "Shorten guild, party and raid tags", onChange = OnChange,
		tooltip = "[Guild] -> [G], [Officer] -> [O], [Party] -> [P], [Party Leader] -> [PL], [Raid] -> [R], [Raid Leader] -> [RL], [Raid Warning] -> [RW], [Instance] -> [I], [Instance Leader] -> [IL].\n\nIn instances, encounters, M+ and PvP the game hides chat from addons, so tags show in full there." },
}

module = ns.RegisterModule({
	key = "chattags",
	name = "Channel Tags",
	category = "Chat",
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
