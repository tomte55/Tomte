local addonName, ns = ...

-- Tooltip extras, choice windows: under Blizzard's choice window (PlayerChoiceFrame), how many you own of the token
-- it takes (Data/<Expansion>/Tips.lua "choices") and of each option's reward. Started and stopped from Tips.lua;
-- the module's one event bus lives here.

local MAX_ENTRIES = 6 -- token plus rewards; a window with more options lists the first ones
local GAP = 8 -- pixels between the choice window and the strip
local PAD = 8
local OWNER = "choice"

local UI = ns.UI
local IsSecret = ns.IsSecret
local Icon = ns.Tips_Icon

local events = ns.NewEvents()
ns.Tips_Events = events

local db
local enabled = false
local strip

local function CreateStrip()
	strip = CreateFrame("Frame", nil, UIParent)
	UI.Panel(strip, { subtle = true })
	strip.text = UI.Text(strip, 12, "text", "body")
	strip.text:SetPoint("TOPLEFT", PAD, -PAD)
	strip.text:SetJustifyH("LEFT")
	strip:Hide()
end

local function WatchWhileShown(on)
	for _, event in ipairs({ "BAG_UPDATE_DELAYED", "CURRENCY_DISPLAY_UPDATE", "ITEM_DATA_LOAD_RESULT" }) do
		if on then
			events:Watch(OWNER, event)
		else
			events:Unwatch(OWNER, event)
		end
	end
end

local function Hide()
	if strip and strip:IsShown() then
		strip:Hide()
		WatchWhileShown(false)
	end
end

local function Lines()
	local info = C_PlayerChoice.GetCurrentPlayerChoiceInfo()
	if not info or IsSecret(info.choiceID) then
		return {}
	end
	local token = ns.Tips_Data("choices")[info.choiceID]
	local lines = {}
	for _, entry in ipairs(ns.Tips_ChoiceEntries(info.options, token, MAX_ENTRIES)) do
		local name, have, icon = ns.Tips_Entry(entry.kind, entry.id)
		if name then
			lines[#lines + 1] = Icon(icon) .. ns.Tips_CountText(name, have)
		elseif entry.kind == "item" then
			C_Item.RequestLoadItemDataByID(entry.id) -- ITEM_DATA_LOAD_RESULT refreshes
		end
	end
	return lines
end

local function Refresh()
	local frame = PlayerChoiceFrame -- Blizzard_PlayerChoice loads on demand: looked up each time
	if not (enabled and db.choice and frame and frame:IsShown()) then
		Hide()
		return
	end
	local lines = Lines()
	if #lines == 0 then
		Hide()
		return
	end
	if not strip then
		CreateStrip()
	end
	-- A child of the choice window, so it hides with it however it closes.
	strip:SetParent(frame)
	strip:ClearAllPoints()
	strip:SetPoint("TOP", frame, "BOTTOM", 0, -GAP)
	strip.text:SetText(UI.Wrap("You have", "textMuted") .. "\n" .. table.concat(lines, "\n"))
	strip:SetSize(strip.text:GetStringWidth() + PAD * 2, strip.text:GetStringHeight() + PAD * 2)
	if not strip:IsShown() then
		strip:Show()
		WatchWhileShown(true)
	end
end

-- The choice window builds itself on the same event: look a frame later, once it's shown.
local function RefreshSoon()
	C_Timer.After(0, Refresh)
end

events:On(OWNER, "PLAYER_CHOICE_UPDATE", RefreshSoon)
events:On(OWNER, "PLAYER_CHOICE_CLOSE", Hide)
events:On(OWNER, "BAG_UPDATE_DELAYED", Refresh)
events:On(OWNER, "CURRENCY_DISPLAY_UPDATE", Refresh)
events:On(OWNER, "ITEM_DATA_LOAD_RESULT", Refresh)

function ns.TipsChoice_Start(moduleDB)
	db = moduleDB
	enabled = true
	events:Watch(OWNER, "PLAYER_CHOICE_UPDATE")
	events:Watch(OWNER, "PLAYER_CHOICE_CLOSE")
	Refresh()
end

function ns.TipsChoice_Stop()
	enabled = false
	Hide()
	events:UnwatchAll(OWNER)
end

ns.TipsChoice_Refresh = Refresh
