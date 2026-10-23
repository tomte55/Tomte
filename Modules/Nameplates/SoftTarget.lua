local addonName, ns = ...

-- Nameplates: the soft target's name. With the Interact key's target icons on, Blizzard puts a small icon over the
-- object (or NPC) the Interact key would use; this adds its name under that icon and a cast bar while you gather
-- or open it. Our own frame parented to that nameplate, nothing of Blizzard's changed. Module in Nameplates.lua.

local UNIT = "softinteract"
local WIDTH = 120
local BAR_HEIGHT = 4
local UI = ns.UI
local IsSecret = ns.IsSecret

local events = ns.Plates_Events
local owner = "softTarget"

local db, label
local active = false

local function CreateLabel()
	label = CreateFrame("Frame")
	label:SetSize(WIDTH, 30)
	label.name = label:CreateFontString(nil, "OVERLAY")
	label.name:SetPoint("TOP")
	label.name:SetWidth(WIDTH)
	label.name:SetWordWrap(false)
	label.bar = UI.Bar(label, BAR_HEIGHT)
	label.bar:SetWidth(WIDTH * 0.6)
	label.bar:Hide()
	label:Hide()
end

local function Hide()
	if label then
		label:SetScript("OnUpdate", nil)
		label.bar:Hide()
		label:Hide()
		label:ClearAllPoints()
		label:SetParent(nil)
		label.plate = nil
	end
end

-- The player's cast or channel, as start and end in milliseconds; nil when none or it can't be read.
local function PlayerCast()
	local name, _, _, startMs, endMs = UnitCastingInfo("player")
	local channel = false
	if not name then
		name, _, _, startMs, endMs = UnitChannelInfo("player")
		channel = true
	end
	if not name or IsSecret(startMs, endMs) then
		return nil
	end
	return startMs, endMs, channel
end

local function CastOnUpdate(self)
	local startMs, endMs, channel = PlayerCast()
	local f = startMs and ns.Plates_CastFraction(startMs, endMs, GetTime() * 1000, channel)
	if not f then
		self:SetScript("OnUpdate", nil)
		self.bar:Hide()
		return
	end
	self.bar:SetValue(f)
end

-- Cast bar: only out of combat, where a cast while the soft target is up is gathering, opening or using it.
local function UpdateCast()
	if not (label and label:IsShown()) then
		return
	end
	local inCombat = UnitAffectingCombat("player")
	if not db.softCast or IsSecret(inCombat) or inCombat or not PlayerCast() then
		label:SetScript("OnUpdate", nil)
		label.bar:Hide()
		return
	end
	label.bar:SetColorRole(nil)
	label.bar:Show()
	label:SetScript("OnUpdate", CastOnUpdate)
	CastOnUpdate(label)
end

local function Update()
	if not (active and db.softName and ns.Plates_Allowed()) or not UnitExists(UNIT) then
		Hide()
		return
	end
	local isObject = UnitIsGameObject(UNIT)
	local isPlayer = UnitIsPlayer(UNIT)
	if IsSecret(isObject, isPlayer) or isPlayer or not (isObject or db.softNPC) then
		Hide()
		return
	end
	local plate = ns.Plates_Plate(UNIT)
	local name = UnitName(UNIT)
	if not plate or IsSecret(name) or not name or name == "" then
		Hide()
		return
	end
	if not label then
		CreateLabel()
	end
	local unitFrame = plate.UnitFrame
	if label.plate ~= plate then
		label:SetParent(plate)
		label:SetFrameLevel(plate:GetFrameLevel() + 10)
		label:ClearAllPoints()
		local icon = unitFrame.SoftTargetFrame
		if icon then
			label:SetPoint("TOP", icon, "BOTTOM", 0, -2)
		else
			label:SetPoint("TOP", unitFrame, "CENTER", 0, 0)
		end
		label.plate = plate
	end
	label:SetScale(db.scale)
	UI.SetFont(label.name, "title", 12, "OUTLINE")
	UI.SetTextRole(label.name, "heading")
	label.name:SetText(name)
	-- Blizzard already writes the name on some plates: then only the cast bar.
	local blizzardName = unitFrame.name and unitFrame.name:IsShown()
	label.name:SetShown(not blizzardName)
	label.bar:ClearAllPoints()
	if blizzardName then
		label.bar:SetPoint("TOP", label, "TOP", 0, 0)
	else
		label.bar:SetPoint("TOP", label.name, "BOTTOM", 0, -2)
	end
	label:Show()
	UpdateCast()
end

-- The soft target changes before its nameplate shows: look again next frame too.
local function UpdateSoon()
	Update()
	C_Timer.After(0, function()
		if active then
			Update()
		end
	end)
end

events:On(owner, "PLAYER_SOFT_INTERACT_CHANGED", UpdateSoon)
events:On(owner, "PLAYER_ENTERING_WORLD", UpdateSoon)

events:On(owner, "NAME_PLATE_UNIT_ADDED", function(_, unit)
	if ns.Plates_SameUnit(unit, UNIT) then
		Update()
	end
end)

-- Any plate going away may be the one the name sits on (its unit token is already being cleared): look again.
events:On(owner, "NAME_PLATE_UNIT_REMOVED", function()
	if label and label.plate then
		Hide()
		UpdateSoon()
	end
end)

local CAST_EVENTS = {
	"UNIT_SPELLCAST_START", "UNIT_SPELLCAST_STOP", "UNIT_SPELLCAST_FAILED", "UNIT_SPELLCAST_INTERRUPTED",
	"UNIT_SPELLCAST_CHANNEL_START", "UNIT_SPELLCAST_CHANNEL_STOP", "UNIT_SPELLCAST_CHANNEL_UPDATE",
	"UNIT_SPELLCAST_DELAYED",
}
for _, event in ipairs(CAST_EVENTS) do
	events:On(owner, event, UpdateCast)
end

function ns.Plates_SoftStart(moduleDB)
	db = moduleDB
	active = true
	events:Watch(owner, "PLAYER_SOFT_INTERACT_CHANGED")
	events:Watch(owner, "PLAYER_ENTERING_WORLD")
	events:Watch(owner, "NAME_PLATE_UNIT_ADDED")
	events:Watch(owner, "NAME_PLATE_UNIT_REMOVED")
	for _, event in ipairs(CAST_EVENTS) do
		events:Watch(owner, event, "player")
	end
	Update()
end

function ns.Plates_SoftStop()
	active = false
	events:UnwatchAll(owner)
	Hide()
end

function ns.Plates_SoftRefresh()
	if active then
		Hide()
		Update()
	end
end
