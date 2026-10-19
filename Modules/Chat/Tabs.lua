local addonName, ns = ...

-- Chat Tabs module: the busy channels (Trade, Services, ...) in their own chat tab. The main window keeps them
-- (Trade Filter then shows only matches there) or drops them. The game saves chat windows per character and keeps
-- them after the addon is gone, so turning the module off (or "Restore my chat") undoes exactly what Tomte did:
-- closes the tab if Tomte opened it (an existing tab with the same name is borrowed: only the channels Tomte added
-- come out again), and gives the main window back every channel Tomte took from it.
-- Channels are recognized by zone channel ID, the way Blizzard's chat frame does (zoneChannelList), since the saved
-- name can differ from the shortcut.

local LOGIN_SETTLE = 1 -- seconds after the first loading screen before the tab is looked for

local module
local pending -- an Apply waiting for combat to end
local restored -- "Restore my chat" this session: don't set the tab up again until the module is turned on again
local worldReady = false

local events = ns.NewEvents() -- owners "login" (once, at file load) and "tabs" (while the module is on)

-- Records were keyed like this before 1.16 (ns.Chat_TabsRecord moves this character's to its GUID).
local function OldCharacterKey()
	return (UnitName("player") or "?") .. "-" .. (GetNormalizedRealmName() or "?")
end

-- This character's record: { index, name, created, added = { [zoneID] = name }, removed = { [zoneID] = name } },
-- or nil (create = make one).
local function State(create)
	local guid = UnitGUID("player")
	local state = ns.Chat_TabsRecord(module.db.windows, guid, OldCharacterKey())
	if not state then
		if not create then
			return nil
		end
		state = {}
		module.db.windows[guid] = state
	end
	state.added = state.added or {}
	state.removed = state.removed or {}
	return state
end

-- How many chat windows the client has. Also used by Chat/Tags.lua (loads after this file).
local function MaxWindows()
	return Constants.ChatFrameConstants.MaxChatWindows
end
ns.Chat_MaxWindows = MaxWindows

local function FirstFreeIndex()
	return C_ChatInfo.GetNumReservedChatWindows() + 1
end

local function WindowName(index)
	return (GetChatWindowInfo(index))
end

-- The name a frame has this channel under, or nil.
local function ChannelName(frame, zoneID, shortcut)
	local names = frame.channelList or {}
	for i, id in pairs(frame.zoneChannelList or {}) do
		if id == zoneID and names[i] then
			return names[i]
		end
	end
	local wanted = shortcut and shortcut:lower()
	for _, name in pairs(names) do
		if type(name) == "string" and name:lower() == wanted then
			return name
		end
	end
	return nil
end

local function TabName()
	local name = strtrim(module.db.tabName or "")
	return name ~= "" and name or "Trade"
end

-- The tab's window, or nil. A window Tomte opened is found by its index even when the player renamed it; a borrowed
-- one must still have its name. Never one of the reserved windows (General, Combat Log).
local function SavedFrame(state)
	local index = state and state.index
	if not (index and index >= FirstFreeIndex() and FCF_IsChatWindowIndexActive(index)) then
		return nil
	end
	local current = WindowName(index)
	if state.created or current == state.name or current == TabName() then
		return FCF_GetChatFrameByID(index)
	end
	return nil
end

-- An open window that already has the tab's name: borrowed instead of opening a second one.
local function FrameByName(name)
	for i = FirstFreeIndex(), MaxWindows() do
		if FCF_IsChatWindowIndexActive(i) and WindowName(i) == name then
			return FCF_GetChatFrameByID(i), i
		end
	end
	return nil
end

local function Apply()
	if not module.active or restored or not worldReady then
		return
	end
	if InCombatLockdown() then
		pending = true
		events:Watch("tabs", "PLAYER_REGEN_ENABLED")
		return
	end
	local name = TabName()
	module.db.tabName = name
	local state = State(true)
	local frame = SavedFrame(state)
	if not frame then
		state.added, state.created = {}, nil
		local index
		frame, index = FrameByName(name)
		if not frame then
			frame, index = FCF_OpenNewWindow(name, true)
			if not frame then
				ns.Print("Chat Tabs: all chat windows are in use. Close one and type /reload.")
				return
			end
			state.created = true
		end
		state.index = index or frame:GetID()
		state.name = name
	end
	if state.created and state.name ~= name then -- renamed in the options (a rename in Blizzard's menu is kept)
		FCF_SetWindowName(frame, name)
		state.name = name
	end

	local main = DEFAULT_CHAT_FRAME
	local remove = module.db.mainWindow == "remove"
	for _, channel in ipairs(ns.CHAT_CHANNELS) do
		local id = channel.id
		local shortcut = C_ChatInfo.GetChannelShortcutForChannelID(id)
		local wanted = module.db.channels[channel.key]
		local inTab = ChannelName(frame, id, shortcut)
		if wanted and not inTab and shortcut and shortcut ~= "" then
			frame:AddChannel(shortcut)
			state.added[id] = shortcut
		elseif not wanted and inTab and (state.created or state.added[id]) then
			frame:RemoveChannel(inTab)
			state.added[id] = nil
		end
		if main and main ~= frame then
			local inMain = ChannelName(main, id, shortcut)
			if wanted and remove then
				if inMain then
					main:RemoveChannel(inMain)
					state.removed[id] = inMain
				end
			elseif state.removed[id] then
				if not inMain then
					main:AddChannel(state.removed[id])
				end
				state.removed[id] = nil
			end
		end
	end
end

-- Undo what Tomte did for this character. Chat windows aren't protected: works in combat too.
local function Restore()
	local state = State(false)
	if not state then
		return
	end
	local frame = SavedFrame(state)
	if frame and frame ~= DEFAULT_CHAT_FRAME then
		if state.created then
			FCF_Close(frame)
		else
			for id, name in pairs(state.added) do
				local current = ChannelName(frame, id, name)
				if current then
					frame:RemoveChannel(current)
				end
			end
		end
	end
	local main = DEFAULT_CHAT_FRAME
	if main then
		for id, name in pairs(state.removed) do
			if not ChannelName(main, id, name) then
				main:AddChannel(name)
			end
		end
	end
	module.db.windows[UnitGUID("player")] = nil
	module.db.windows[OldCharacterKey()] = nil
end

-- The tab's chat frame while the module is on (Trade Filter leaves it unfiltered), or nil. Also before this
-- session's first Apply: the tab from last time already gets messages.
function ns.ChatTabs_Frame()
	if not (module and module.active) or restored then
		return nil
	end
	return SavedFrame(State(false))
end

-- Chat windows get their saved names and channels around the first loading screen; looking earlier could miss the
-- tab and open a second one. One second after it is safe.
events:On("login", "PLAYER_ENTERING_WORLD", function(self)
	self:UnwatchAll("login")
	C_Timer.After(LOGIN_SETTLE, function()
		worldReady = true
		Apply()
	end)
end)
events:Watch("login", "PLAYER_ENTERING_WORLD")

events:On("tabs", "PLAYER_REGEN_ENABLED", function(self)
	self:Unwatch("tabs", "PLAYER_REGEN_ENABLED")
	if pending then
		pending = false
		Apply()
	end
end)

local function Activate()
	restored = false
	Apply() -- before the world is ready the login watch does it
end

local function Deactivate()
	events:UnwatchAll("tabs")
	pending = false
	Restore()
end

local function OnChange()
	Apply()
end

local MAIN_CHOICES = {
	{ value = "keep", text = "Keep them" },
	{ value = "remove", text = "Remove them" },
}

local options = {
	{ type = "input", key = "tabName", label = "Tab name", placeholder = "Trade", onChange = OnChange,
		tooltip = "Renaming here renames the tab. If you already have a tab with this name, Tomte uses it and only adds channels to it." },
	{ type = "header", label = "Channels in the tab" },
}
for _, channel in ipairs(ns.CHAT_CHANNELS) do
	options[#options + 1] = { type = "checkbox", key = "channels." .. channel.key, label = channel.label, onChange = OnChange }
end
options[#options + 1] = { type = "header", label = "Main window" }
options[#options + 1] = { type = "dropdown", key = "mainWindow", label = "These channels in the main window",
	onChange = OnChange, choices = function()
		return MAIN_CHOICES
	end, tooltip = "Keep them: the main window still gets them, and with Trade Filter on it shows only messages with your keywords there while the tab shows everything.\n\nRemove them: they only show in the tab." }
options[#options + 1] = { type = "button", label = "Undo Tomte's chat changes", text = "Restore my chat",
	confirm = "Close Tomte's chat tab and give the main window its channels back?", onClick = function()
		Restore()
		restored = true
		ns.Print("Chat Tabs: chat restored. Turn the module off to keep it that way, or it sets the tab up again at your next login.")
	end, tooltip = "Turning this module off does the same." }

module = ns.RegisterModule({
	key = "chattabs",
	name = "Chat Tabs",
	category = "social",
	icon = 2056011, -- ui_chat
	summary = "Trade and other busy channels get a chat tab of their own.",
	description = "Moves Trade and other busy channels into their own chat tab. Turning it off puts your chat back.",
	enabledByDefault = false,
	keep = { "tabName" },
	defaults = {
		tabName = "Trade",
		channels = { trade = true, services = true, general = false, lfg = false, defense = false },
		mainWindow = "keep",
		-- [player GUID] = what Tomte changed for that character, see State(); "Name-Realm" keys from before 1.16 until
		-- that character logs in
		windows = {},
	},
	toggle = function(active)
		if active then
			Activate()
		else
			Deactivate()
		end
	end,
	commands = {
		{ "restore", "close the tab and give the main window its channels back", function()
			Restore()
			restored = true
			ns.Print("Chat Tabs: chat restored.")
		end },
	},
	options = options,
})
