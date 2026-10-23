local addonName, ns = ...

-- Quests: the Talking Head (the NPC portrait that talks during quests). "Hide" keeps only the voice (and, if
-- wanted, the line in chat); "Text only" shows the line as a plain subtitle instead of Blizzard's frame, and can
-- also drop lines in instances or from world quests. While either is chosen, Blizzard's frame stops listening for
-- new lines (its TALKINGHEAD_REQUESTED is unregistered) and the voice is played here; Stop gives the event back.
-- What a line becomes is decided in Data.lua; started and stopped by Quests.lua.

local OWNER = "talkinghead"
local WIDTH = 560
local PAD = 10
local BACKGROUND_ALPHA = 0.6 -- a soft backing so the line reads over bright ground
local MIN_HOLD = 4 -- seconds a line stays at least (lines without a voice report no duration)
local FADE = 0.4 -- seconds
-- A world quest's talking heads often start a moment before or after you accept or finish it.
local WORLD_QUEST_WINDOW = 10 -- seconds
local SOUND_CHANNEL = "Talking Head"
-- What Edit Mode shows.
local PREVIEW_NAME, PREVIEW_TEXT = "Kesha", "The camp is quiet tonight. Too quiet, if you ask me."

local UI = ns.UI
local IsSecret = ns.IsSecret
local events = ns.Quests_Events

local db
local enabled = false
local taken = false -- Blizzard's frame has its TALKINGHEAD_REQUESTED unregistered by us
local blizzardListened -- whether it was registered before we took it
local frame, holdTimer
local voHandle
local worldQuestUntil = 0
local conversationIsWorldQuest = false

-- Subtitle ------------------------------------------------------------------------------------------------------

local function Build()
	frame = CreateFrame("Frame", nil, UIParent)
	frame:SetSize(WIDTH, 60)
	frame:SetFrameStrata("MEDIUM")
	frame:SetClampedToScreen(true)
	frame:SetMovable(true)
	frame:Hide()
	UI.Panel(frame, { subtle = true, alpha = BACKGROUND_ALPHA })
	frame.name = UI.Text(frame, 13, "heading", "title")
	frame.name:SetPoint("TOP", frame, "TOP", 0, -PAD)
	frame.name:SetJustifyH("CENTER")
	frame.text = UI.Text(frame, db.thSize, "text")
	frame.text:SetPoint("TOP", frame.name, "BOTTOM", 0, -4)
	frame.text:SetWidth(WIDTH - 2 * PAD)
	frame.text:SetJustifyH("CENTER")

	frame.fadeIn = frame:CreateAnimationGroup()
	local a = frame.fadeIn:CreateAnimation("Alpha")
	a:SetFromAlpha(0)
	a:SetToAlpha(1)
	a:SetDuration(FADE)
	frame.fadeIn:SetToFinalAlpha(true)
	frame.fadeOut = frame:CreateAnimationGroup()
	a = frame.fadeOut:CreateAnimation("Alpha")
	a:SetFromAlpha(1)
	a:SetToAlpha(0)
	a:SetDuration(FADE)
	frame.fadeOut:SetToFinalAlpha(true)
	frame.fadeOut:SetScript("OnFinished", function()
		frame:Hide()
	end)
end

local function Place()
	local p = db.thFrame
	frame:ClearAllPoints()
	frame:SetPoint(p.point, UIParent, p.relPoint, p.x, p.y)
end

local function CancelHold()
	if holdTimer then
		holdTimer:Cancel()
		holdTimer = nil
	end
end

local function FadeOut()
	CancelHold()
	if frame and frame:IsShown() and not frame.fadeOut:IsPlaying() then
		frame.fadeIn:Stop()
		frame.fadeOut:Play()
	end
end

local function HideNow()
	CancelHold()
	if frame then
		frame.fadeIn:Stop()
		frame.fadeOut:Stop()
		frame:Hide()
	end
end

local function SetLine(name, text)
	frame.name:SetText(name or "")
	UI.SetFont(frame.text, "body", db.thSize)
	frame.text:SetText(text or "")
	frame:SetHeight(frame.name:GetStringHeight() + 4 + frame.text:GetStringHeight() + 2 * PAD)
end

local function ShowLine(name, text, duration)
	if not frame then
		Build()
	end
	Place()
	SetLine(name, text)
	frame.fadeOut:Stop()
	if not frame:IsShown() then
		frame:SetAlpha(0)
		frame:Show()
		frame.fadeIn:Play()
	end
	CancelHold()
	holdTimer = C_Timer.NewTimer(math.max(duration or 0, MIN_HOLD), FadeOut)
end

-- Lines -----------------------------------------------------------------------------------------------------------

local function StopVoice()
	if voHandle then
		StopSound(voHandle)
		voHandle = nil
	end
end

-- True while the player is in a world quest or bonus objective area (those quests sit in the log only there).
local function InTaskArea()
	for i = 1, C_QuestLog.GetNumQuestLogEntries() do
		local info = C_QuestLog.GetInfo(i)
		if info and not info.isHeader and info.isTask then
			return true
		end
	end
	return false
end

local function ChatLine(name, text)
	if not (db.thChat and text and text ~= "") then
		return
	end
	local who = name and name ~= "" and (UI.Wrap(name, "heading") .. ": ") or ""
	DEFAULT_CHAT_FRAME:AddMessage(who .. UI.Wrap(text, "text"))
end

local function OnRequested()
	local displayInfo, _, vo, duration, lineNumber, _, name, text = C_TalkingHead.GetCurrentLineInfo()
	if IsSecret(displayInfo, vo, duration, lineNumber, name, text) or not displayInfo or displayInfo == 0 then
		return
	end
	StopVoice()
	if vo and vo ~= 0 then
		local ok, handle = PlaySound(vo, SOUND_CHANNEL, true, true)
		voHandle = ok and handle or nil
	end
	if lineNumber == 0 then
		conversationIsWorldQuest = GetTime() < worldQuestUntil or InTaskArea()
	end
	local ctx = { inInstance = IsInInstance() and true or false, worldQuest = conversationIsWorldQuest }
	local rules = { hideInInstance = db.thHideInstance, hideWorldQuest = db.thHideWorldQuest }
	local action = ns.Quests_TalkingHeadAction(db.talkingHead, ctx, rules)
	if action == "text" then
		ShowLine(name, text, duration)
	else
		HideNow()
		ChatLine(name, text)
	end
end

local function OnQuestEvent(questID)
	if IsSecret(questID) or type(questID) ~= "number" then
		return
	end
	if C_QuestLog.IsWorldQuest(questID) or C_QuestLog.IsQuestTask(questID) then
		worldQuestUntil = GetTime() + WORLD_QUEST_WINDOW
	end
end

events:On(OWNER, "TALKINGHEAD_REQUESTED", OnRequested)
events:On(OWNER, "TALKINGHEAD_CLOSE", FadeOut)
events:On(OWNER, "LOADING_SCREEN_ENABLED", function()
	StopVoice()
	HideNow()
end)
events:On(OWNER, "SOUNDKIT_FINISHED", function(_, handle)
	if handle == voHandle then
		voHandle = nil
	end
end)
events:On(OWNER, "QUEST_ACCEPTED", function(_, questID)
	OnQuestEvent(questID)
end)
events:On(OWNER, "QUEST_TURNED_IN", function(_, questID)
	OnQuestEvent(questID)
end)

local EVENTS = {
	"TALKINGHEAD_REQUESTED", "TALKINGHEAD_CLOSE", "LOADING_SCREEN_ENABLED", "SOUNDKIT_FINISHED", "QUEST_ACCEPTED",
	"QUEST_TURNED_IN",
}

-- Blizzard's frame ------------------------------------------------------------------------------------------------

local function Take()
	if taken or not TalkingHeadFrame then
		return
	end
	taken = true
	blizzardListened = TalkingHeadFrame:IsEventRegistered("TALKINGHEAD_REQUESTED")
	TalkingHeadFrame:UnregisterEvent("TALKINGHEAD_REQUESTED")
end

local function GiveBack()
	if not taken then
		return
	end
	taken = false
	if blizzardListened then
		TalkingHeadFrame:RegisterEvent("TALKINGHEAD_REQUESTED")
	end
end

local function StopAll()
	events:UnwatchAll(OWNER)
	StopVoice()
	HideNow()
	GiveBack()
end

-- Applies the setting: called on start and when it changes.
function ns.QuestsTalkingHead_Apply()
	if not (enabled and db.talkingHead ~= "off") then
		StopAll()
		return
	end
	Take()
	for _, event in ipairs(EVENTS) do
		events:Watch(OWNER, event)
	end
end

function ns.QuestsTalkingHead_Start(moduleDB)
	db = moduleDB
	enabled = true
	ns.QuestsTalkingHead_Apply()
end

function ns.QuestsTalkingHead_Stop()
	enabled = false
	StopAll()
end

-- Edit Mode and settings ------------------------------------------------------------------------------------------

local function Preview()
	if not frame then
		if not (enabled and db.talkingHead == "text") then
			return
		end
		Build()
	end
	if ns.EditMode_Active() and enabled and db.talkingHead == "text" then
		Place()
		SetLine(PREVIEW_NAME, PREVIEW_TEXT)
		CancelHold()
		frame.fadeOut:Stop()
		frame:SetAlpha(1)
		frame:Show()
	elseif not holdTimer then
		HideNow()
	end
end

ns.EditMode_Register({
	name = "Talking Head text",
	frame = function()
		return frame
	end,
	refresh = Preview,
	saved = function()
		local point, _, relPoint, x, y = frame:GetPoint()
		db.thFrame.point, db.thFrame.relPoint, db.thFrame.x, db.thFrame.y = point, relPoint, x, y
	end,
})

-- The same position as the thFrame default in Quests.lua.
function ns.QuestsTalkingHead_ResetPosition()
	if not db then
		return
	end
	db.thFrame.point, db.thFrame.relPoint, db.thFrame.x, db.thFrame.y = "BOTTOM", "BOTTOM", 0, 200
	if frame then
		Place()
	end
end

-- Shows a sample line for a few seconds (the settings' "Test" button).
function ns.QuestsTalkingHead_Test()
	if not enabled then
		ns.Print("Quests is off.")
		return
	end
	ShowLine(PREVIEW_NAME, PREVIEW_TEXT, MIN_HOLD)
end
