local addonName, ns = ...

-- Quests: the medal you've earned on each skyriding race course, shown on the timekeeper's gossip options. Your
-- times come from the "Race Times" aura you get at a race start (read in Read.lua, parsed and matched to the
-- course options in Data.lua); each medal is drawn over the option's icon in Blizzard's gossip window, on a
-- texture of our own. The marks follow the window's list as it draws its buttons (scroll box callbacks), and a
-- pooled button that no longer shows a course loses its mark. DialogueUI's window isn't marked. Started and
-- stopped by Quests.lua.

local OWNER = "medals"
local RETRY = 0.25 -- seconds: the aura's tooltip text can be partial at first
local TRIES = 3
local MEDAL_SIZE = 16 -- the size of a gossip option's icon

local events = ns.Quests_Events

local db
local enabled = false
local timer, tries
local overlays = {} -- [gossip option button] = our medal texture
local marks = {} -- [option orderIndex] = medal atlas, for the open gossip window
local callbacks -- the scroll box callbacks' owner, once registered

local function HideAll()
	for _, tex in pairs(overlays) do
		tex:Hide()
	end
end

-- The medal for one button of Blizzard's gossip list, or none.
local function Mark(button, elementData)
	local info = enabled and elementData and elementData.buttonType == GOSSIP_BUTTON_TYPE_OPTION and elementData.info
	local atlas = info and marks[info.orderIndex]
	local tex = overlays[button]
	if not atlas then
		if tex then
			tex:Hide()
		end
		return
	end
	if not tex then
		tex = button:CreateTexture(nil, "OVERLAY")
		tex:SetSize(MEDAL_SIZE, MEDAL_SIZE)
		overlays[button] = tex
	end
	tex:ClearAllPoints()
	tex:SetPoint("CENTER", button.Icon or button, button.Icon and "CENTER" or "LEFT", 0, 0)
	tex:SetAtlas(atlas)
	tex:Show()
end

-- The scroll box of Blizzard's gossip window.
local function GossipList()
	local panel = GossipFrame and GossipFrame.GreetingPanel
	return panel and panel.ScrollBox
end

-- Registered once and kept: with the module off they find no marks (Mark checks enabled) and only hide ours.
local function Listen(box)
	if callbacks or not (box and ScrollUtil) then
		return
	end
	callbacks = {}
	ScrollUtil.AddInitializedFrameCallback(box, function(_, button, elementData)
		Mark(button, elementData)
	end, callbacks)
	ScrollUtil.AddReleasedFrameCallback(box, function(_, button)
		local tex = overlays[button]
		if tex then
			tex:Hide()
		end
	end, callbacks)
end

-- Works out the marks and puts them on the buttons already shown.
local function Apply()
	wipe(marks)
	local box = GossipList()
	Listen(box)
	local lines = ns.QuestsRead_RaceAura()
	if lines and box and GossipFrame:IsShown() then
		local medals, titles = ns.Quests_RaceMedals(lines)
		local options = ns.QuestsRead_GossipOptions()
		for i, atlas in pairs(ns.Quests_RaceMedalOptions(medals, titles, options)) do
			marks[options[i].orderIndex] = atlas
		end
	end
	if box then
		box:ForEachFrame(function(button)
			Mark(button, button.GetElementData and button:GetElementData())
		end)
	end
end

local function Cancel()
	if timer then
		timer:Cancel()
		timer = nil
	end
end

local function Try()
	timer = nil
	if not db.raceMedals then
		return
	end
	Apply()
	tries = tries + 1
	if tries < TRIES then -- again even when read: the text fills in over a few moments
		timer = C_Timer.NewTimer(RETRY, Try)
	end
end

local function Clear()
	Cancel()
	wipe(marks)
	HideAll()
end

events:On(OWNER, "GOSSIP_SHOW", function()
	Clear()
	if db.raceMedals then
		tries = 0
		timer = C_Timer.NewTimer(0, Try) -- after Blizzard's gossip window has filled its list
	end
end)

events:On(OWNER, "GOSSIP_CLOSED", Clear)

function ns.QuestsMedals_Start(moduleDB)
	db = moduleDB
	enabled = true
	events:Watch(OWNER, "GOSSIP_SHOW")
	events:Watch(OWNER, "GOSSIP_CLOSED")
end

function ns.QuestsMedals_Stop()
	enabled = false
	events:UnwatchAll(OWNER)
	Clear()
end
