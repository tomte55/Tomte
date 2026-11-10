local addonName, ns = ...

-- Quest list: Spoken's Play button on each quest. Spoken (the Forever voice-over addon) hooks Blizzard's objective
-- tracker for its Play buttons, and that tracker is hidden while the Quest list is on, so the list draws its own.
-- Spoken's public API (Spoken/API.lua) has no call for binding a button to a quest; the binding lives in
-- Spoken_Quests' QuestOverlayUI, reached through the VoiceOver table Spoken_Quests' Environment.lua exposes. This file
-- makes the same calls Spoken's own tracker hook makes (Spoken_Quests/Compatibility.lua, "Play on the objective
-- tracker's quests"), and nothing else of Spoken's. Every field is checked and every call goes through pcall: when a
-- Spoken update moves any of it, the buttons hide and /tomte questlist why names what was missing.

local BOX, SIZE = "QuestLog-icon-ticksquare", 14 -- the quest log's checkbox, as Spoken's tracker button draws it
local OVERLAY_CALLS = { "BindPlayButton", "SetPlayButtonState", "FollowQueue", "ShowsTrackerButton" }

local broken -- why the buttons can't be made (a Spoken version we don't fit), once found
local listener -- called when Spoken's queue changes, while the list is on
local callbackHandle
local lastBind = {} -- [questID] = what the last Bind did with its button (for /tomte questlist why)

local function Loaded()
	return C_AddOns.IsAddOnLoaded("Spoken") and C_AddOns.IsAddOnLoaded("Spoken_Quests")
end

-- Spoken_Quests' QuestOverlayUI, or nil and why not.
local function Overlay()
	local env = rawget(_G, "VoiceOver")
	local ui = type(env) == "table" and rawget(env, "QuestOverlayUI")
	if type(ui) ~= "table" then
		return nil, "Spoken_Quests' QuestOverlayUI is missing"
	end
	for _, name in ipairs(OVERLAY_CALLS) do
		if type(ui[name]) ~= "function" then
			return nil, "Spoken_Quests' QuestOverlayUI has no " .. name
		end
	end
	return ui
end

local function Player()
	local spoken = rawget(_G, "Spoken")
	if type(spoken) ~= "table" or type(spoken.IsCompatible) ~= "function" then
		return nil, "Spoken's API is missing"
	end
	local ok, compatible = pcall(spoken.IsCompatible, spoken, 1)
	if not (ok and compatible) then
		return nil, "Spoken's API version changed"
	end
	if type(spoken.DressBoxButton) ~= "function" then
		return nil, "Spoken has no DressBoxButton"
	end
	return spoken
end

-- Whether Spoken and its quest part are installed (whatever their version).
function ns.QuestListSpoken_Installed()
	return Loaded()
end

-- true when Play buttons can be drawn; else false and why (nil when Spoken simply isn't installed).
function ns.QuestListSpoken_Status()
	if not Loaded() then
		return false, nil
	end
	if broken then
		return false, broken
	end
	local spoken, why = Player()
	if not spoken then
		return false, why
	end
	local ui, why2 = Overlay()
	if not ui then
		return false, why2
	end
	return true
end

-- A Play button on parent, dressed as Spoken's tracker button; nil when that can't be done.
function ns.QuestListSpoken_Button(parent)
	if not ns.QuestListSpoken_Status() then
		return nil
	end
	local spoken, ui = Player(), Overlay()
	local b = CreateFrame("Button", nil, parent)
	b:SetSize(SIZE, SIZE)
	b:SetHitRectInsets(1, 1, 1, 1)
	local ok, err = pcall(spoken.DressBoxButton, spoken, b)
	if ok then
		ok, err = pcall(b.SetBox, b, BOX, SIZE, SIZE)
	end
	if not ok then
		broken = "Spoken's button didn't dress: " .. tostring(err)
		b:Hide()
		return nil
	end
	-- Its glyph follows the queue (Play, Stop, Replay), as Spoken's own stop-and-replay buttons do.
	b.setPlayState = ui.FollowQueue
	return b
end

-- Points b at questID. Hides it (and returns false) when Spoken has no line for the quest, its tracker buttons are off
-- in Spoken's settings, or the call fails.
function ns.QuestListSpoken_Bind(b, questID, title)
	local ui, missing = Overlay()
	if not ui then
		lastBind[questID] = missing
		b:Hide()
		return false
	end
	local ok, shows = pcall(ui.ShowsTrackerButton, ui, questID)
	if not (ok and shows) then
		lastBind[questID] = ok and "no recording, or tracker buttons off in Spoken" or ("error: " .. tostring(shows))
		b:Hide()
		return false
	end
	if b.questID ~= questID then
		b.soundData = nil
		local err
		ok, err = pcall(ui.BindPlayButton, ui, b, questID, title or "", "Tomte's quest list")
		if not ok then
			lastBind[questID] = "bind failed: " .. tostring(err)
			b:Hide()
			return false
		end
	end
	b:Show()
	pcall(ui.SetPlayButtonState, ui, b)
	lastBind[questID] = ("shown, %dx%d, alpha %.2f"):format(b:GetWidth(), b:GetHeight(), b:GetEffectiveAlpha())
	return true
end

-- For /tomte questlist why: what the last draw did with questID's Play button, or nil if it had none to draw.
function ns.QuestListSpoken_Why(questID)
	return lastBind[questID]
end

-- The quest whose line Spoken is reading right now, or nil.
function ns.QuestListSpoken_Speaking()
	local spoken = rawget(_G, "Spoken")
	if type(spoken) ~= "table" or type(spoken.GetNowPlaying) ~= "function" then
		return nil
	end
	local ok, clip = pcall(spoken.GetNowPlaying, spoken)
	return ok and type(clip) == "table" and clip.questID or nil
end

-- fn runs whenever Spoken's queue changes (a line starts, stops or is queued), until QuestListSpoken_Stop.
function ns.QuestListSpoken_Start(fn)
	listener = fn
	local spoken = rawget(_G, "Spoken")
	if callbackHandle or not Loaded() or type(spoken) ~= "table" or type(spoken.RegisterCallback) ~= "function" then
		return
	end
	local ok, handle = pcall(spoken.RegisterCallback, spoken, "AUDIO_CHANGED", function()
		if listener then
			listener()
		end
	end)
	callbackHandle = ok and handle or nil
end

function ns.QuestListSpoken_Stop()
	listener = nil
	local spoken = rawget(_G, "Spoken")
	if callbackHandle and type(spoken) == "table" and type(spoken.UnregisterCallback) == "function" then
		pcall(spoken.UnregisterCallback, spoken, callbackHandle)
	end
	callbackHandle = nil
end
