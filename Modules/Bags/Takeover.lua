local addonName, ns = ...

-- Bags: takes over from Blizzard's bags while the module is on. Blizzard's container frames are parented to a hidden
-- frame instead of being stopped: Blizzard keeps opening and closing them as always (the bag keys, merchants, mail,
-- the bank, Esc through CloseAllBags' return value), they just can't be seen, and Tomte's window follows their state
-- (IsAnyBagOpen) after each of Blizzard's open and close functions. Blizzard moves its bag frames to a full-screen
-- frame and back (ContainerFrame_SetFullScreenFrame / _ClearFullScreenFrame in ContainerFrame.lua); that parent is
-- remembered as theirs and they go back under the hidden frame. Stop gives each frame the parent Blizzard last chose.
--
-- Auto open: windows that open the bags themselves (OpenAllBags(frame): merchant, mail, bank...) can be told not
-- to, and other windows (crafting, trade...) can open Tomte's window. Tomte never calls Blizzard's open or close
-- functions (from addon code they'd taint FRAME_THAT_OPENED_BAGS, which Esc's CloseAllWindows reads): it only shows
-- its own window, and closes by hiding Blizzard's (invisible) frames, which runs none of their scripts.

local SINGLE_FRAMES = 6 -- ContainerFrame1..6: the backpack, four bags and the reagent bag (NUM_CONTAINER_FRAMES)
-- Blizzard's functions that open or close bags, and what each means when it's the outermost call (post-hooks run
-- innermost first, so the last one to fire is the one the player's action called).
local INTENTS = {
	ToggleAllBags = "toggle", ToggleBackpack = "toggle", ToggleBag = "toggle",
	OpenAllBags = "open", OpenBackpack = "open", OpenBag = "open", OpenAllBagsMatchingContext = "open",
	CloseAllBags = "close", CloseBackpack = "close", CloseBag = "close",
}
-- Blizzard's functions that reparent its bag frames.
local REPARENTERS = { "ContainerFrame_SetFullScreenFrame", "ContainerFrame_ClearFullScreenFrame" }
-- Windows that open the bags themselves (OpenAllBags(self) in Blizzard's code) to their auto-open setting.
local BLIZZARD_OPENERS = {
	MerchantFrame = "vendor", MailFrame = "mail", BankFrame = "bank", AuctionHouseFrame = "auction",
	ScrappingMachineFrame = "scrapping", ItemInteractionFrame = "catalyst",
}
-- Enum.PlayerInteractionType values of the other windows that can open Tomte's bags.
local INTERACTIONS = { [10] = "guildbank", [53] = "upgrade" } -- GuildBanker, ItemUpgrade

local db
local active = false
local hooked = false
local hidden -- the hidden parent
local homes = {} -- [Blizzard bag frame] = the parent Blizzard gave it
local syncQueued = false
local intent -- "toggle" | "open" | "close": what the last of Blizzard's bag functions did
local suppress = false -- the next sync closes the bags: a window opened them whose auto open is off
local autoOpened = {} -- [setting key] = true: Tomte's window is open for that window, Blizzard's bags are closed
local events = CreateFrame("Frame")

local function Frames()
	local list = {}
	for i = 1, SINGLE_FRAMES do
		local f = _G["ContainerFrame" .. i]
		if f then
			list[#list + 1] = f
		end
	end
	if ContainerFrameCombinedBags then
		list[#list + 1] = ContainerFrameCombinedBags
	end
	return list
end

-- Blizzard's frames under the hidden parent, remembering any parent Blizzard set since.
local function HideAway()
	for _, f in ipairs(Frames()) do
		local parent = f:GetParent()
		if parent ~= hidden then
			homes[f] = parent
			f:SetParent(hidden)
		end
	end
end

-- Closes Blizzard's bags by hiding their frames. They're under the hidden parent, so they never become invisible and
-- none of their OnHide code runs (no taint); IsAnyBagOpen reads false afterwards.
local function CloseBlizzard()
	for _, f in ipairs(Frames()) do
		if f:IsShown() then
			f:Hide()
		end
	end
end

local function Sync()
	syncQueued = false
	local what = intent
	intent = nil
	if not active then
		return
	end
	if suppress then
		suppress = false
		CloseBlizzard()
	end
	local open = IsAnyBagOpen()
	if next(autoOpened) then
		if what == "toggle" and open then
			-- The bag key while the bags were open for another window: the player wants them closed.
			CloseBlizzard()
			open = false
		elseif not open and what ~= "close" then
			return -- nothing about Blizzard's bags changed: keep the window that's open for the other one
		end
		wipe(autoOpened)
	end
	if open then
		ns.BagsWindow_Show()
	else
		ns.BagsWindow_Hide()
	end
end

-- After Blizzard's own function has run (and anything it called): once per burst, on the next frame.
local function QueueSync()
	if active and not syncQueued then
		syncQueued = true
		C_Timer.After(0, Sync)
	end
end

-- OpenAllBags(frame) and OpenAllBagsMatchingContext(frame) say which window opened the bags.
local function OnOpenedBy(frame)
	local key = frame and frame.GetName and BLIZZARD_OPENERS[frame:GetName() or ""]
	if key and db.autoOpen[key] == false and not ns.BagsWindow_IsShown() then
		suppress = true
	end
end

local function Hook()
	if hooked then
		return
	end
	hooked = true
	for name, what in pairs(INTENTS) do
		if _G[name] then
			hooksecurefunc(name, function(frame)
				if not active then
					return
				end
				if what == "open" and (name == "OpenAllBags" or name == "OpenAllBagsMatchingContext") then
					OnOpenedBy(frame)
				end
				intent = what
				QueueSync()
			end)
		end
	end
	for _, name in ipairs(REPARENTERS) do
		if _G[name] then
			hooksecurefunc(name, function()
				if active then
					HideAway()
				end
			end)
		end
	end
	CharacterFrame:HookScript("OnShow", function()
		ns.BagsTakeover_WindowShown("character")
	end)
	CharacterFrame:HookScript("OnHide", function()
		ns.BagsTakeover_WindowHidden("character")
	end)
end

-- Auto open for the windows that don't open the bags themselves --------------------------------------------------

function ns.BagsTakeover_WindowShown(key)
	if active and db.autoOpen[key] and not ns.BagsWindow_IsShown() then
		autoOpened[key] = true
		ns.BagsWindow_Show()
	end
end

function ns.BagsTakeover_WindowHidden(key)
	if not (active and autoOpened[key]) then
		return
	end
	autoOpened[key] = nil
	if not next(autoOpened) and not IsAnyBagOpen() then
		ns.BagsWindow_Hide()
	end
end

events:SetScript("OnEvent", function(_, event, kind)
	if event == "TRADE_SKILL_SHOW" then
		ns.BagsTakeover_WindowShown("crafting")
	elseif event == "TRADE_SKILL_CLOSE" then
		ns.BagsTakeover_WindowHidden("crafting")
	elseif event == "SOCKET_INFO_UPDATE" then
		ns.BagsTakeover_WindowShown("socket")
	elseif event == "SOCKET_INFO_CLOSE" then
		ns.BagsTakeover_WindowHidden("socket")
	elseif event == "TRADE_SHOW" then
		ns.BagsTakeover_WindowShown("trade")
	elseif event == "TRADE_CLOSED" then
		ns.BagsTakeover_WindowHidden("trade")
	elseif event == "PLAYER_INTERACTION_MANAGER_FRAME_SHOW" and INTERACTIONS[kind] then
		ns.BagsTakeover_WindowShown(INTERACTIONS[kind])
	elseif event == "PLAYER_INTERACTION_MANAGER_FRAME_HIDE" and INTERACTIONS[kind] then
		ns.BagsTakeover_WindowHidden(INTERACTIONS[kind])
	end
end)

local WINDOW_EVENTS = {
	"TRADE_SKILL_SHOW", "TRADE_SKILL_CLOSE", "SOCKET_INFO_UPDATE", "SOCKET_INFO_CLOSE", "TRADE_SHOW", "TRADE_CLOSED",
	"PLAYER_INTERACTION_MANAGER_FRAME_SHOW", "PLAYER_INTERACTION_MANAGER_FRAME_HIDE",
}

-- API --------------------------------------------------------------------------------------------------------------

function ns.BagsTakeover_Init(moduleDB)
	db = moduleDB
end

-- The window's close button: Blizzard's bags closed too, so the bag key opens them again.
function ns.BagsTakeover_Close()
	wipe(autoOpened)
	CloseBlizzard()
	ns.BagsWindow_Hide()
end

function ns.BagsTakeover_Start()
	active = true
	Hook()
	hidden = hidden or CreateFrame("Frame")
	hidden:Hide()
	HideAway()
	for _, event in ipairs(WINDOW_EVENTS) do
		events:RegisterEvent(event)
	end
	Sync()
end

function ns.BagsTakeover_Stop()
	active = false
	events:UnregisterAllEvents()
	wipe(autoOpened)
	suppress = false
	ns.BagsWindow_Hide()
	for f, home in pairs(homes) do
		if f:GetParent() == hidden then
			f:SetParent(home)
		end
	end
	wipe(homes)
	-- Blizzard's bags that were open behind ours show again where Blizzard puts them.
	if UpdateContainerFrameAnchors then
		UpdateContainerFrameAnchors()
	end
end
