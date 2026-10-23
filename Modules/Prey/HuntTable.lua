local addonName, ns = ...

-- Prey: the Hunt Table. Blizzard's table is an adventure map (CovenantMissionFrame.MapTab, Blizzard_GarrisonUI) whose
-- hunts are plain quest offer pins. Each prey pin gets a small difficulty label, a dot when the target is still
-- missing from its achievement, and those plus this week's count in its tooltip. Pins are Blizzard's (pooled and
-- reused), so the label is our own child frame and the tooltip a HookScript, both idle while the module or the
-- setting is off. Rules in Data.lua, registered in Prey.lua.

local PIN_TEMPLATE = "AdventureMap_QuestOfferPinTemplate"
local DOT = "Interface\\CHARACTERFRAME\\TempPortraitAlphaMask"
local DIFFICULTY_ROLES = { "text", "warning", "danger" } -- Normal, Hard, Nightmare

local UI = ns.UI
local events = ns.Prey_Events
local OWNER = "hunttable"

local running = false
local badges = setmetatable({}, { __mode = "k" }) -- [pin] = our label frame
local hooked = setmetatable({}, { __mode = "k" }) -- [pin] = true once its OnEnter is hooked
local indexDef, index -- Prey_Index of the def it was built from

local function Enabled()
	return running and ns.Prey_HuntTableOn()
end

local function Index(def)
	if def ~= indexDef then
		indexDef, index = def, ns.Prey_Index(def)
	end
	return index
end

local function Entry(pin)
	local def = ns.Prey_Def()
	local e = def and pin.questID and Index(def)[pin.questID]
	return e, def
end

local function Needed(e)
	return not ns.PreyRead_CriteriaDone(e.achievement, e.criteria)
end

local function WeekRow(def, difficulty)
	for _, row in ipairs(ns.PreyRead_Week(def, (ns.PreyRead_Rank(def)))) do
		if row.index == difficulty then
			return row
		end
	end
	return nil
end

local function OnEnter(pin)
	if not Enabled() then
		return
	end
	local e, def = Entry(pin)
	if not e then
		return
	end
	GameTooltip:AddLine(" ")
	for _, line in ipairs(ns.Prey_PinLines(def, e, WeekRow(def, e.difficulty), Needed(e))) do
		UI.TipLine(line.text, line.role)
	end
	GameTooltip:Show()
end

local function Badge(pin)
	local b = badges[pin]
	if not b then
		b = CreateFrame("Frame", nil, pin)
		b:SetSize(1, 1)
		b:SetPoint("TOP", pin, "BOTTOM", 0, 2)
		b.text = UI.Text(b, 10, "text")
		b.text:SetPoint("TOP")
		b.text:SetShadowOffset(1, -1)
		b.dot = b:CreateTexture(nil, "OVERLAY")
		b.dot:SetTexture(DOT)
		b.dot:SetSize(8, 8)
		b.dot:SetPoint("BOTTOMLEFT", pin, "TOPRIGHT", -6, -6)
		badges[pin] = b
	end
	return b
end

local function Decorate()
	local map = CovenantMissionFrame and CovenantMissionFrame.MapTab
	if not (map and map.EnumeratePinsByTemplate and map:IsVisible()) then
		return
	end
	local on = Enabled()
	for pin in map:EnumeratePinsByTemplate(PIN_TEMPLATE) do
		local e, def = nil, nil
		if on then
			e, def = Entry(pin)
		end
		if e then
			if not hooked[pin] then
				hooked[pin] = true
				pin:HookScript("OnEnter", OnEnter)
			end
			local b = Badge(pin)
			local d = def.difficulties[e.difficulty]
			b.text:SetText(d and d.name or "")
			UI.SetTextRole(b.text, DIFFICULTY_ROLES[e.difficulty] or "text")
			b.dot:SetVertexColor(UI.RGBA("accent", 1))
			b.dot:SetShown(Needed(e))
			b:Show()
		elseif badges[pin] then
			badges[pin]:Hide()
		end
	end
end

local function DecorateSoon()
	-- After Blizzard's own handler for the same event has placed the pins.
	C_Timer.After(0, Decorate)
end

local function HideAll()
	for _, b in pairs(badges) do
		b:Hide()
	end
end

for _, event in ipairs({ "ADVENTURE_MAP_OPEN", "ADVENTURE_MAP_UPDATE_POIS", "ADVENTURE_MAP_QUEST_UPDATE" }) do
	events:On(OWNER, event, DecorateSoon)
end

-- The setting changed (Prey.lua): labels on or off on a table that's open.
function ns.PreyHunt_Refresh()
	if Enabled() then
		DecorateSoon()
	else
		HideAll()
	end
end

function ns.PreyHunt_Start()
	running = true
	for _, event in ipairs({ "ADVENTURE_MAP_OPEN", "ADVENTURE_MAP_UPDATE_POIS", "ADVENTURE_MAP_QUEST_UPDATE" }) do
		events:Watch(OWNER, event)
	end
	DecorateSoon()
end

function ns.PreyHunt_Stop()
	running = false
	events:UnwatchAll(OWNER)
	HideAll()
end
