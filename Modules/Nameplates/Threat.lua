local addonName, ns = ...

-- Nameplates: your threat as a number ("87%") under the right end of each enemy's health bar, solo or in a group, in the open
-- world and in instances. Blizzard's plates only tint the bar, and only in a group. Rules in Data.lua
-- (ns.Plates_Threat), module in Nameplates.lua.
--
-- The game may hide threat values from addons (SecretWhenUnitThreatValuesRestricted); on Forever it does for
-- nameplate tokens while the same mob as "target" stays readable. So a plate is read through target or focus when
-- it can be. Otherwise the hidden distance-scaled number is still written (a font string takes a hidden value) and
-- colored through a color curve, since a hidden value can't be compared.

local GAP = 3 -- between the health bar's bottom and the badge
local HEIGHT = 16
-- The narrowest badge, and the width of one showing a hidden number (at most "100%"). A badge's own text is never
-- measured: a font string that once held a hidden number reports its width as hidden too (measured on Forever:
-- math.ceil on it errored). Readable numbers, which can run to "7500%" on a tank's lead, are measured on a ruler.
local WIDTH = 40
local PAD_X = 5 -- room left and right of a measured number
local BG_ALPHA = 0.85
local UI = ns.UI
local IsSecret = ns.IsSecret

local events = ns.Plates_Events
local owner = "threat"

local db
local active = false
local labels = {} -- [unit token] = threat label on that unit's plate
local pool = {} -- released labels

-- Frames -------------------------------------------------------------------------------------------------------

-- A hidden font string that only ever holds readable text, set in the badges' font, to size a badge from.
local ruler

local function Measure(text)
	if not ruler then
		local holder = CreateFrame("Frame")
		holder:Hide()
		ruler = holder:CreateFontString(nil, "OVERLAY")
	end
	UI.SetFont(ruler, "number", 12, "OUTLINE")
	ruler:SetText(text)
	return math.max(WIDTH, math.ceil(ruler:GetUnboundedStringWidth()) + 2 * PAD_X)
end

local function Acquire(plate)
	local f = table.remove(pool)
	if not f then
		f = CreateFrame("Frame")
		f:SetSize(WIDTH, HEIGHT)
		f.bg = f:CreateTexture(nil, "BACKGROUND")
		f.bg:SetAllPoints()
		UI.Border(f, "frame")
		f.text = f:CreateFontString(nil, "OVERLAY")
		f.text:SetPoint("CENTER", 0, 0)
	end
	f:SetParent(plate)
	f:SetFrameLevel(plate:GetFrameLevel() + 10)
	f:SetScale(db.scale)
	-- Fonts and colors come from the theme each time a badge is placed, so a theme switch reaches them.
	UI.SetFont(f.text, "number", 12, "OUTLINE")
	local r, g, b = UI.Color("bg")
	f.bg:SetColorTexture(r, g, b, BG_ALPHA)
	local unitFrame = plate.UnitFrame
	-- Under the health bar's right end. Measured in game: right of the bar sits a boxed count of Blizzard's or
	-- another addon's, and above it the left-aligned name runs the full width, so long names collided.
	local bar = unitFrame.healthBar or unitFrame.HealthBarsContainer or unitFrame
	f:ClearAllPoints()
	f:SetPoint("TOPRIGHT", bar, "BOTTOMRIGHT", 0, -GAP)
	f:Show()
	return f
end

local function Release(unit)
	local f = labels[unit]
	if not f then
		return
	end
	labels[unit] = nil
	f:Hide()
	f:ClearAllPoints()
	f:SetParent(nil)
	pool[#pool + 1] = f
end

local function ReleaseAll()
	for unit in pairs(labels) do
		Release(unit)
	end
end

-- Reading ------------------------------------------------------------------------------------------------------

-- Whether you play a tank: the group role when one is set, else your specialization's role.
local function IsTank()
	if IsInGroup() then
		local role = UnitGroupRolesAssigned("player")
		if role and role ~= "NONE" then
			return role == "TANK"
		end
	end
	if C_SpecializationInfo and C_SpecializationInfo.GetSpecialization then
		local spec = C_SpecializationInfo.GetSpecialization()
		if spec then
			local role = select(5, C_SpecializationInfo.GetSpecializationInfo(spec))
			return role == "TANK"
		end
	end
	return false
end

-- The threat reading of you against a unit: a table for ns.Plates_Threat, or "secret" with the hidden scaled
-- percentage when the game hides it now.
local function ReadToken(unit)
	local tanking, status, scaled, raw = UnitDetailedThreatSituation("player", unit)
	if IsSecret(tanking, status, scaled, raw) then
		return "secret", scaled
	end
	local lead
	if tanking and UnitThreatPercentageOfLead then
		lead = UnitThreatPercentageOfLead("player", unit)
		if IsSecret(lead) then
			lead = nil
		end
	end
	return {
		tanking = tanking,
		status = status,
		raw = raw,
		lead = lead,
		tank = IsTank(),
		helper = IsInGroup() or UnitExists("pet"),
	}
end

-- Measured on Forever: threat asked through a nameplate token is hidden, the same mob asked as "target" is not. A
-- plate whose mob is also one of these tokens is read through it. Not mouseover or the soft target: those come and go
-- as you look around, and the number would jump between the two readings.
local ALIASES = { "target", "focus" }

local function Read(unit)
	local info, hidden = ReadToken(unit)
	if info ~= "secret" then
		return info
	end
	for _, alias in ipairs(ALIASES) do
		if ns.Plates_SameUnit(unit, alias) then
			local again = ReadToken(alias)
			if again ~= "secret" then
				return again
			end
		end
	end
	return info, hidden
end

-- A hidden reading can still be colored: a color curve turns the hidden status (0..3) into a color without Tomte
-- seeing it, as UnitBar.lua colors hidden health. One curve per set of roles and theme colors.
local curves = {} -- [cache key] = color curve

local function StatusCurve(roles)
	local key = ""
	for status = 0, 3 do
		key = key .. ns.Theme.Hex(roles[status])
	end
	local curve = curves[key]
	if not curve then
		curve = C_CurveUtil.CreateColorCurve()
		curve:SetType(Enum.LuaCurveType.Linear)
		for status = 0, 3 do
			curve:AddPoint(status, CreateColor(UI.Color(roles[status])))
		end
		curves[key] = curve
	end
	return curve
end

-- Colors a badge from the hidden status. False when the game won't allow it (the badge stays plain).
local function ColorHidden(f, unit)
	if not (C_CurveUtil and C_CurveUtil.CreateColorCurve) then
		return false
	end
	local curve = StatusCurve(ns.Plates_ThreatRoles(IsTank(), IsInGroup() or UnitExists("pet")))
	return pcall(function()
		local r, g, b = curve:Evaluate(UnitThreatSituation("player", unit)):GetRGB()
		f.text:SetTextColor(r, g, b)
		for _, edge in ipairs(f.borderEdges) do
			edge:SetColorTexture(r, g, b, 1)
		end
	end)
end

-- When even the curve is refused (measured on Forever): whether the mob is attacking you stands in for the status,
-- holding aggro (3) or not (0). nil when that is hidden too.
local function AggroRole(unit)
	local onMe = UnitIsUnit(unit .. "target", "player")
	if IsSecret(onMe) then
		return nil
	end
	return ns.Plates_ThreatRoles(IsTank(), IsInGroup() or UnitExists("pet"))[onMe and 3 or 0]
end

-- Per plate ----------------------------------------------------------------------------------------------------

local function Show(unit, plate)
	local f = labels[unit]
	if not f then
		f = Acquire(plate)
		labels[unit] = f
	end
	return f
end

local function UpdateUnit(unit)
	if not active or IsSecret(unit) then
		return
	end
	-- EllesmereUI Nameplates hides Blizzard's plate and draws its own, so a number placed on ours would float.
	local plate = db.threat and not ns.Ellesmere_Loaded("Nameplates") and ns.Plates_Plate(unit)
	local hostile = plate and UnitCanAttack("player", unit)
	-- A hidden answer (instances) counts as hostile: friendly plates there are protected and never get this far.
	if not plate or (not IsSecret(hostile) and not hostile) then
		Release(unit)
		return
	end
	local info, hidden = Read(unit)
	if info == "secret" then
		local f = Show(unit, plate)
		f:SetWidth(WIDTH)
		-- A hidden value can be written but not checked: a call the game rejects (nothing to show) hides the badge.
		if not pcall(f.text.SetFormattedText, f.text, "%.0f%%", hidden) then
			Release(unit)
			return
		end
		if not ColorHidden(f, unit) then
			local role = AggroRole(unit) or "text"
			UI.SetTextRole(f.text, role)
			UI.SetBorderColor(f, role == "text" and "frame" or role)
		end
		return
	end
	local shown = ns.Plates_Threat(info)
	if not shown then
		Release(unit)
		return
	end
	local f = Show(unit, plate)
	f.text:SetText(shown.text)
	f:SetWidth(Measure(shown.text))
	UI.SetTextRole(f.text, shown.role)
	UI.SetBorderColor(f, shown.role)
end

local function UpdateAll()
	if not active then
		return
	end
	for _, plate in ipairs(C_NamePlate.GetNamePlates()) do
		local unit = plate.UnitFrame and plate:GetUnit()
		if unit then
			UpdateUnit(unit)
		end
	end
end

-- Events -------------------------------------------------------------------------------------------------------

events:On(owner, "NAME_PLATE_UNIT_ADDED", function(_, unit)
	UpdateUnit(unit)
end)

events:On(owner, "NAME_PLATE_UNIT_REMOVED", function(_, unit)
	Release(unit)
end)

-- The plate's own token for a unit token (target, focus, nameplate3); nil when the unit has no plate. Events also
-- bring tokens like "targettarget", which GetNamePlateForUnit rejects with an error: only these few are asked.
local PLATE_ALIASES = { target = true, focus = true }

local function PlateToken(unit)
	if not unit or IsSecret(unit) then
		return nil
	end
	if unit:find("^nameplate%d+$") then
		return unit
	end
	if not PLATE_ALIASES[unit] then
		return nil
	end
	local plate = C_NamePlate.GetNamePlateForUnit(unit)
	local token = plate and not plate:IsForbidden() and plate.UnitFrame and plate:GetUnit()
	return token and not IsSecret(token) and token or nil
end

-- Fires whenever an enemy's threat list changes, for its tokens (which may be only target or focus).
events:On(owner, "UNIT_THREAT_LIST_UPDATE", function(_, unit)
	local token = PlateToken(unit)
	if token then
		UpdateUnit(token)
	end
end)

-- A mob turning to you or away recolors a badge read the hidden way (AggroRole).
events:On(owner, "UNIT_TARGET", function(_, unit)
	local token = PlateToken(unit)
	if token then
		UpdateUnit(token)
	end
end)

-- A plate that became or stopped being the target or focus switches between its two readings.
events:On(owner, "PLAYER_TARGET_CHANGED", UpdateAll)
events:On(owner, "PLAYER_FOCUS_CHANGED", UpdateAll)

-- Your own standing changed (aggro gained or lost), or who's there to hold aggro: every plate.
events:On(owner, "UNIT_THREAT_SITUATION_UPDATE", UpdateAll)
events:On(owner, "PLAYER_REGEN_ENABLED", UpdateAll)
events:On(owner, "PLAYER_REGEN_DISABLED", UpdateAll)
events:On(owner, "GROUP_ROSTER_UPDATE", UpdateAll)
events:On(owner, "PLAYER_ROLES_ASSIGNED", UpdateAll)
events:On(owner, "UNIT_PET", UpdateAll)
events:On(owner, "PLAYER_ENTERING_WORLD", UpdateAll)
events:On(owner, "PLAYER_SPECIALIZATION_CHANGED", UpdateAll) -- not on every client: watched with TryWatch

local EVENTS = {
	"NAME_PLATE_UNIT_ADDED", "NAME_PLATE_UNIT_REMOVED", "UNIT_THREAT_LIST_UPDATE", "UNIT_THREAT_SITUATION_UPDATE",
	"PLAYER_REGEN_ENABLED", "PLAYER_REGEN_DISABLED", "GROUP_ROSTER_UPDATE", "PLAYER_ROLES_ASSIGNED", "UNIT_PET",
	"PLAYER_ENTERING_WORLD", "PLAYER_TARGET_CHANGED", "UNIT_TARGET",
}

-- Called from Nameplates.lua with the module's db.
function ns.Plates_ThreatStart(moduleDB)
	db = moduleDB
	active = true
	for _, event in ipairs(EVENTS) do
		events:Watch(owner, event)
	end
	events:TryWatch(owner, "PLAYER_SPECIALIZATION_CHANGED")
	events:TryWatch(owner, "PLAYER_FOCUS_CHANGED")
	UpdateAll()
end

function ns.Plates_ThreatStop()
	active = false
	events:UnwatchAll(owner)
	ReleaseAll()
end

-- Settings changed: redraw every plate.
function ns.Plates_ThreatRefresh()
	if not active then
		return
	end
	ReleaseAll()
	UpdateAll()
end

-- What the game tells Tomte about your threat on your target (/tomte plates threat): lines for chat.
function ns.Plates_ThreatWhy(unit)
	local out = {}
	if not UnitExists(unit) then
		out[#out + 1] = "no target"
		return out
	end
	local token = PlateToken(unit)
	if token and token ~= unit then
		local hidden = ReadToken(token) == "secret"
		out[#out + 1] = ("through its nameplate (%s): %s"):format(token, hidden
			and "hidden (other plates show the distance-scaled number, colored through a curve)" or "readable")
	end
	local tanking, status, scaled, raw = UnitDetailedThreatSituation("player", unit)
	if IsSecret(tanking, status, scaled, raw) then
		out[#out + 1] = "threat values: hidden by the game here (shown as the distance-scaled number)"
		return out
	end
	out[#out + 1] = "threat values: readable"
	out[#out + 1] = ("tanking: %s, status: %s, scaled: %s, raw: %s"):format(tostring(tanking), tostring(status),
		tostring(scaled), tostring(raw))
	local info = ReadToken(unit)
	out[#out + 1] = ("tank role: %s, someone else to hold aggro: %s"):format(tostring(info.tank),
		tostring(info.helper))
	local shown = ns.Plates_Threat(info)
	out[#out + 1] = "shows: " .. (shown and (shown.text .. " (" .. shown.role .. ")") or "nothing")
	local plate = C_NamePlate.GetNamePlateForUnit(unit)
	if not plate then
		out[#out + 1] = "it has no nameplate"
	elseif plate:IsForbidden() then
		out[#out + 1] = "its nameplate is protected: the game keeps addons off it here"
	end
	return out
end
