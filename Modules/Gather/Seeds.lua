local addonName, ns = ...

-- Gathering: the Resilient Seeds button (Midnight). Herbalists plant Resilient Seeds in Rich Soil spots; pointing the
-- mouse at a Rich Soil spot with seeds in your bags shows a row of secure item buttons, one per seed you hold, and a
-- click plants that seed. The row goes away GATHER_SOIL_LINGER seconds after you last pointed at soil, after a
-- plant, on a zone change or in combat. Off by default (the button acts).
-- Rich Soil is told by its game object ID, never by its name: the IDs come from the content data
-- (Data/Midnight/Seeds.lua) and from db.soil, learned when a plant cast succeeds right after pointing at an object
-- (ns.Gather_SoilLearn). So the very first plant in a client without known IDs is done from the bags.
-- Rules in Data.lua, registered in Gather.lua.

local SIZE = 36 -- button size in pixels
local GAP = 6
local MAX_SEEDS = 4 -- buttons made up front (the Midnight list has four seeds)
local BAR_NAME = "TomteSeedBar"
local BUTTON_NAME = "TomteSeedButton"
local TOOLTIP_HINT = "Rich Soil: Tomte's seed button is up"
local TOOLTIP_NONE = "Rich Soil: no Resilient Seeds in your bags"

local UI = ns.UI
local Secret = ns.IsSecret
local events = ns.Gather_Events
local OWNER = "seeds"

local db, module
local running = false
local holder
local buttons = {}
local lastObject -- { id, at, map }: the object the mouse pointed at last
local soilAt -- GetTime() when Rich Soil was last pointed at
local hideTimer

local function Readable(v)
	return v ~= nil and not Secret(v)
end

local function Content()
	return ns.Content_Get(ns.ContentExpansion(), "seeds")
end

local function MapID()
	local map = C_Map.GetBestMapForUnit("player")
	return Readable(map) and map or nil
end

local function IsHerbalist()
	local first, second = GetProfessions()
	for _, index in ipairs({ first or false, second or false }) do
		if index and select(7, GetProfessionInfo(index)) == ns.GATHER_SKILL_LINES.herbalism then
			return true
		end
	end
	return false
end

-- The seeds you hold, in the content's order: { { item, spell, count } }.
local function Held(content)
	local list = {}
	for _, seed in ipairs(content and content.items or {}) do
		local count = C_Item.GetItemCount(seed.item)
		if count and count > 0 then
			list[#list + 1] = { item = seed.item, spell = seed.spell, count = count }
		end
	end
	return list
end

-- Buttons ------------------------------------------------------------------------------------------------------------

local function ButtonOnEnter(self)
	if not self.itemID then
		return
	end
	GameTooltip:SetOwner(self, "ANCHOR_TOP")
	GameTooltip:SetItemByID(self.itemID)
	GameTooltip:Show()
end

local function ApplyLayout()
	local f = db.seeds.frame
	holder:ClearAllPoints()
	holder:SetPoint(f.point, UIParent, f.relPoint, f.x, f.y)
end

-- The holder is protected (SecureFrameTemplate) because a protected button can't be anchored to an ordinary frame,
-- so it, its buttons' layout and their show/hide are out of combat only. Made on first need, out of combat.
local function Create()
	holder = CreateFrame("Frame", BAR_NAME, UIParent, "SecureFrameTemplate")
	holder:SetSize(SIZE, SIZE)
	holder:SetMovable(true)
	holder:SetClampedToScreen(true)
	holder:SetFrameStrata("MEDIUM")
	holder:Hide()
	for i = 1, MAX_SEEDS do
		local button = CreateFrame("Button", BUTTON_NAME .. i, holder, "SecureActionButtonTemplate")
		button:SetSize(SIZE, SIZE)
		button:SetPoint("LEFT", holder, "LEFT", (i - 1) * (SIZE + GAP), 0)
		-- Clicked by mouse only (no binding): SecureActionButton_OnClick runs a real mouse press on the up click
		-- whatever useOnKeyDown says, so up clicks, as the Decor house rows.
		button:RegisterForClicks("AnyUp")
		button:SetAttribute("useOnKeyDown", false)
		button.icon = button:CreateTexture(nil, "ARTWORK")
		button.icon:SetAllPoints()
		button.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
		UI.Border(button, "frame", 0.8)
		button:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
		button.count = UI.Text(button, 11, "text", "number")
		button.count:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -2, 2)
		button:SetScript("OnEnter", ButtonOnEnter)
		button:SetScript("OnLeave", GameTooltip_Hide)
		button:Hide()
		buttons[i] = button
	end
	ApplyLayout()
end

-- Sets the buttons to the seeds held (attributes and shown buttons: out of combat only).
local function Fill(held)
	for i, button in ipairs(buttons) do
		local seed = held[i]
		if seed then
			button.itemID = seed.item
			button:SetAttribute("type", "item")
			button:SetAttribute("item", "item:" .. seed.item)
			button.icon:SetTexture(C_Item.GetItemIconByID(seed.item))
			button.count:SetText(seed.count)
			button:Show()
		else
			button.itemID = nil
			button:SetAttribute("type", nil)
			button:Hide()
		end
	end
	holder:SetWidth(math.max(1, #held) * (SIZE + GAP) - GAP)
end

-- Edit Mode shows the row with every seed of the list as a preview.
local function Preview(content)
	local list = {}
	for _, seed in ipairs(content and content.items or {}) do
		list[#list + 1] = { item = seed.item, spell = seed.spell, count = C_Item.GetItemCount(seed.item) or 0 }
	end
	return list
end

local function Wanted(content, held)
	return ns.Gather_SeedsShown({
		on = running, herbalist = IsHerbalist(), onMap = content.maps[MapID() or 0] == true, held = #held,
		soilAt = soilAt, now = GetTime(),
	})
end

local function Update()
	if InCombatLockdown() then
		return
	end
	local content = Content()
	local editMode = ns.EditMode_Active() and running
	if not content then
		if holder then
			holder:Hide()
		end
		return
	end
	local held = Held(content)
	local show = Wanted(content, held)
	if not (show or editMode) then
		if holder then
			holder:Hide()
		end
		return
	end
	if not holder then
		Create()
	end
	Fill(show and held or Preview(content))
	holder:Show()
end

local function ScheduleHide()
	if hideTimer then
		hideTimer:Cancel()
	end
	hideTimer = C_Timer.NewTimer(ns.GATHER_SOIL_LINGER + 0.5, function()
		hideTimer = nil
		Update()
	end)
end

-- Tooltips -----------------------------------------------------------------------------------------------------------

-- World object tooltips: remember what the mouse points at; on Rich Soil, show the row and say so on the tooltip.
-- A tooltip post-call can't be removed: it does nothing while the seed button is off.
local function OnObject(tooltip, data)
	if not running or not data then
		return
	end
	local id = data.id
	if not (Readable(id) and type(id) == "number") and Readable(data.guid) then
		local _, fromGUID = ns.Gather_ParseGUID(data.guid)
		id = fromGUID
	end
	if not (Readable(id) and type(id) == "number") then
		return
	end
	local content = Content()
	if not content then
		return
	end
	local map = MapID()
	lastObject = { id = id, at = GetTime(), map = map }
	if not (map and content.maps[map] and ns.Gather_IsSoil(id, content.soil, db.soil)) then
		return
	end
	soilAt = GetTime()
	local held = Held(content)
	if tooltip.AddLine then
		tooltip:AddLine(UI.Wrap(#held > 0 and TOOLTIP_HINT or TOOLTIP_NONE, #held > 0 and "accent" or "textMuted"))
	end
	Update()
	ScheduleHide()
end

-- Events -------------------------------------------------------------------------------------------------------------

local function Forget()
	soilAt = nil
	if hideTimer then
		hideTimer:Cancel()
		hideTimer = nil
	end
end

events:On(OWNER, "UNIT_SPELLCAST_SUCCEEDED", function(_, unit, _, spellID)
	local content = Content()
	if unit ~= "player" or not Readable(spellID) or not content
		or not ns.Gather_SeedForSpell(content.items, spellID) then
		return
	end
	local learned = ns.Gather_SoilLearn(lastObject, GetTime(), content.maps)
	if learned and not ns.Gather_IsSoil(learned, content.soil, db.soil) then
		db.soil[learned] = true
		ns.Print(("learned a Rich Soil spot (object %d): the seed button shows there from now on."):format(learned))
	end
	-- The spot is used up: the row goes until the next one is pointed at.
	Forget()
	Update()
end)
events:On(OWNER, "BAG_UPDATE_DELAYED", Update)
events:On(OWNER, "ZONE_CHANGED_NEW_AREA", function()
	Forget()
	Update()
end)
events:On(OWNER, "PLAYER_ENTERING_WORLD", function()
	Forget()
	Update()
end)
events:On(OWNER, "SKILL_LINES_CHANGED", Update)
-- Fires just before combat lockdown starts: the last moment the protected row may hide.
events:On(OWNER, "PLAYER_REGEN_DISABLED", function()
	Forget()
	if holder then
		holder:Hide()
	end
end)
events:On(OWNER, "PLAYER_REGEN_ENABLED", function()
	Update()
	if not running then
		-- Watched only to hide the row after a stop that fell in combat (GatherSeeds_Apply).
		events:UnwatchAll(OWNER)
	end
end)

local EVENTS = { "BAG_UPDATE_DELAYED", "ZONE_CHANGED_NEW_AREA", "PLAYER_ENTERING_WORLD", "SKILL_LINES_CHANGED",
	"PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED" }

-- Start / stop -------------------------------------------------------------------------------------------------------

function ns.GatherSeeds_Init(moduleDB, owner)
	db, module = moduleDB, owner
	TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Object, OnObject)
end

-- Runs while the module is on and the setting is. A hide that falls in combat waits for PLAYER_REGEN_ENABLED, so
-- that event stays watched until the row is down.
function ns.GatherSeeds_Apply()
	local want = module.active and db.seeds.on and true or false
	if want == running then
		Update()
		return
	end
	running = want
	if want then
		events:Watch(OWNER, "UNIT_SPELLCAST_SUCCEEDED", "player")
		for _, event in ipairs(EVENTS) do
			events:Watch(OWNER, event)
		end
	else
		events:UnwatchAll(OWNER)
		Forget()
		lastObject = nil
		if holder and holder:IsShown() then
			if InCombatLockdown() then
				events:Watch(OWNER, "PLAYER_REGEN_ENABLED")
			else
				holder:Hide()
			end
		end
	end
	Update()
end

function ns.GatherSeeds_Relayout()
	if holder and not InCombatLockdown() then
		ApplyLayout()
	end
end

function ns.GatherSeeds_ResetPosition()
	local f = db.seeds.frame
	f.point, f.relPoint, f.x, f.y = "CENTER", "CENTER", 0, -120
	ns.GatherSeeds_Relayout()
end

-- /tomte gather soil: what the mouse pointed at last and the Rich Soil spots known.
function ns.GatherSeeds_Info()
	local content = Content()
	if not content then
		ns.Print("seed button: only in Midnight content.")
		return
	end
	if lastObject then
		ns.Print(("last object pointed at: %d (%ds ago, map %s)%s"):format(lastObject.id,
			math.floor(GetTime() - lastObject.at), tostring(lastObject.map),
			ns.Gather_IsSoil(lastObject.id, content.soil, db.soil) and ", Rich Soil" or ""))
	else
		ns.Print("no object pointed at yet" .. (running and "." or " (the seed button is off)."))
	end
	local ids = {}
	for id in pairs(content.soil) do
		ids[#ids + 1] = id .. " (Tomte's list)"
	end
	for id in pairs(db.soil) do
		if not content.soil[id] then
			ids[#ids + 1] = id .. " (learned)"
		end
	end
	ns.Print("Rich Soil objects: " .. (#ids > 0 and table.concat(ids, ", ") or "none yet (plant a seed from your bags once)"))
end

ns.EditMode_Register({
	name = "Seed button",
	frame = function()
		return running and holder or nil
	end,
	refresh = function()
		Update()
	end,
	saved = function()
		local point, _, relPoint, x, y = holder:GetPoint()
		local f = db.seeds.frame
		f.point, f.relPoint, f.x, f.y = point, relPoint, x, y
	end,
})
