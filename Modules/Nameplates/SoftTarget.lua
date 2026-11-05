local addonName, ns = ...

-- Nameplates: the soft target's name. With the Interact key's target icons on, Blizzard puts a small icon over the
-- object (or NPC) the Interact key would use; this adds its name under that icon and a cast bar while you gather
-- or open it. Our own frame parented to that nameplate, nothing of Blizzard's changed. Module in Nameplates.lua.

local UNIT = "softinteract"
local WIDTH = 120
local BAR_HEIGHT = 4
-- Blizzard's soft target icon on a plate (Blizzard_NamePlates.xml, live 12.1): 24 square, its bottom 8 below the
-- unit frame's top. The game fills it with the cursor the Interact key would show (SetUnitCursorTexture).
local ICON_SIZE = 24
local ICON_DROP = 8
local SAMPLE_GAP = 16 -- between the preview's two samples
local SAMPLE_CAST = 0.6 -- how far the preview's cast bar has run
-- The settings preview's samples: a herb you'd gather and a character you'd talk to (made-up names), with the icons
-- the game shows over them: the cursor art without its arrow (Interface/Cursor/Crosshair, file IDs from the
-- community listfile).
local SAMPLES = {
	{ name = "Duskbloom", cursor = 4675631 }, -- crosshair/gatherherbs
	{ name = "Mira Ashvale", cursor = 4675660, npc = true }, -- crosshair/speak
}
local UI = ns.UI
local IsSecret = ns.IsSecret

local events = ns.Plates_Events
local owner = "softTarget"

local db, label
local active = false

local function NewLabel()
	local l = CreateFrame("Frame")
	l:SetSize(WIDTH, 30)
	l.name = l:CreateFontString(nil, "OVERLAY")
	l.name:SetPoint("TOP")
	l.name:SetWidth(WIDTH)
	l.name:SetWordWrap(false)
	l.bar = UI.Bar(l, BAR_HEIGHT)
	l.bar:SetWidth(WIDTH * 0.6)
	l.bar:Hide()
	l:Hide()
	return l
end

-- Hangs label l under the soft target icon Blizzard puts on unitFrame (the real plate's or the settings preview's).
local function Attach(l, plate, unitFrame)
	l:SetParent(plate)
	l:SetFrameLevel(plate:GetFrameLevel() + 10)
	l:ClearAllPoints()
	local icon = unitFrame.SoftTargetFrame
	if icon then
		l:SetPoint("TOP", icon, "BOTTOM", 0, -2)
	else
		l:SetPoint("TOP", unitFrame, "CENTER", 0, 0)
	end
end

-- The name, or only the cast bar's place when Blizzard already writes the name on the plate.
local function Fill(l, name, blizzardName, scale)
	l:SetScale(scale)
	UI.SetFont(l.name, "title", 12, "OUTLINE")
	UI.SetTextRole(l.name, "heading")
	l.name:SetText(name)
	l.name:SetShown(not blizzardName)
	l.bar:ClearAllPoints()
	if blizzardName then
		l.bar:SetPoint("TOP", l, "TOP", 0, 0)
	else
		l.bar:SetPoint("TOP", l.name, "BOTTOM", 0, -2)
	end
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
local CastOnUpdateTimed = ns.Perf_Wrap(CastOnUpdate, "OnUpdate")

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
	label:SetScript("OnUpdate", CastOnUpdateTimed)
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
		label = NewLabel()
	end
	local unitFrame = plate.UnitFrame
	if label.plate ~= plate then
		Attach(label, plate, unitFrame)
		label.plate = plate
	end
	-- Blizzard already writes the name on some object plates: then only the cast bar. Not trusted for characters: on a
	-- friendly NPC's plate its name reports shown, visible and opaque while nothing shows on screen (measured 12.1.5).
	Fill(label, name, isObject and unitFrame.name and unitFrame.name:IsShown(), db.scale)
	label:Show()
	UpdateCast()
end

-- /tomte plates soft: each step Update takes for what the Interact key would use now, and where it stops.
function ns.Plates_SoftWhy()
	local function Show(v)
		if IsSecret(v) then
			return "secret"
		end
		return tostring(v)
	end
	local allowed, why = ns.Plates_Allowed()
	ns.Print(("Interact name: module %s, setting %s, allowed %s%s, also characters %s."):format(Show(active),
		Show(db and db.softName), Show(allowed), why and (" (" .. why .. ")") or "", Show(db and db.softNPC)))
	local exists = UnitExists(UNIT)
	print(("  softinteract: exists %s, object %s, player %s, name %s"):format(Show(exists),
		Show(UnitIsGameObject(UNIT)), Show(UnitIsPlayer(UNIT)), Show(UnitName(UNIT))))
	local plate = C_NamePlate.GetNamePlateForUnit(UNIT)
	local unitFrame = plate and not plate:IsForbidden() and plate.UnitFrame
	print(("  nameplate: %s%s"):format(plate and "yes" or "none", plate and plate:IsForbidden() and " (forbidden)"
		or (plate and not plate.UnitFrame and " (no unit frame)" or "")))
	if unitFrame then
		local n = unitFrame.name
		print(("  Blizzard's name on it: shown %s, visible %s, alpha %s, text %s"):format(Show(n and n:IsShown()),
			Show(n and n:IsVisible()), Show(n and n:GetAlpha() * unitFrame:GetEffectiveAlpha()), Show(n and n:GetText())))
		print(("  soft target icon: %s"):format(unitFrame.SoftTargetFrame and Show(unitFrame.SoftTargetFrame:IsVisible())
			or "none"))
	end
	print(("  Tomte's label: %s, name shown %s, text %s"):format(label and Show(label:IsVisible()) or "none",
		Show(label and label.name:IsShown()), Show(label and label.name:GetText())))
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

-- Settings preview ----------------------------------------------------------------------------------------------

-- An object's plate shows nothing of its own but the soft target icon: a bare unit frame with that icon, and a
-- label of its own put on by the same code as on a real plate.
local function MockPlate(parent, sample)
	local plate = CreateFrame("Frame", nil, parent)
	plate:SetSize(WIDTH, 1)
	plate.SoftTargetFrame = CreateFrame("Frame", nil, plate)
	plate.SoftTargetFrame:SetSize(ICON_SIZE, ICON_SIZE)
	plate.SoftTargetFrame:SetPoint("BOTTOM", plate, "TOP", 0, -ICON_DROP)
	plate.SoftTargetFrame.Icon = plate.SoftTargetFrame:CreateTexture(nil, "ARTWORK")
	plate.SoftTargetFrame.Icon:SetAllPoints()
	plate.SoftTargetFrame.Icon:SetTexture(sample.cursor)
	plate.label = NewLabel()
	Attach(plate.label, plate, plate)
	return plate
end

-- Settings preview (Panel/Preview.lua): the soft target icon over a herb (and over a character with npc), the name
-- under it and the cast bar part-way when cast. opts = { scale, name, cast, npc } (the settings). Returns the size in
-- host units, or nil when nothing would show.
function ns.Plates_DrawSoftSample(host, opts)
	if not opts.name then
		return nil
	end
	local root = host.softSample
	if not root then
		root = CreateFrame("Frame", nil, host)
		root:SetPoint("TOPLEFT")
		root:SetSize(1, 1)
		root.plates = {}
		for i, sample in ipairs(SAMPLES) do
			root.plates[i] = MockPlate(root, sample)
		end
		host.softSample = root
	end
	local x, height = 0, 0
	for i, sample in ipairs(SAMPLES) do
		local plate = root.plates[i]
		local shown = opts.npc or not sample.npc
		plate:SetShown(shown)
		if shown then
			local l = plate.label
			Fill(l, sample.name, false, opts.scale)
			l.bar:SetShown(opts.cast and not sample.npc)
			l.bar:SetColorRole(nil)
			l.bar:SetValue(SAMPLE_CAST)
			l:Show()
			-- The label is WIDTH wide at its scale; the icon sits centered over it.
			local w = math.max(WIDTH * opts.scale, ICON_SIZE)
			plate:ClearAllPoints()
			plate:SetPoint("TOP", root, "TOPLEFT", x + w / 2, -(ICON_SIZE - ICON_DROP))
			local below = 2 + l.name:GetStringHeight() + (l.bar:IsShown() and 2 + BAR_HEIGHT or 0)
			height = math.max(height, ICON_SIZE + below * opts.scale)
			x = x + w + SAMPLE_GAP
		end
	end
	return x - SAMPLE_GAP, math.ceil(height)
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
