local addonName, ns = ...

-- Home's hero: the current character in 3D (drag to turn) with its name, item level, gold, durability and location
-- (each a button: a tooltip with more, and a click while the module behind it is on), and the quick actions
-- (module.home entries of kind "quick") under it. Exports ns.PanelHome_CreateHero and ns.PanelHome_HERO_W for
-- Home.lua; the kit is HomeKit.lua.

local UI = ns.UI
local Kit = ns.HomeKit
local SetColor, TipLine, PAD = Kit.SetColor, Kit.TipLine, Kit.PAD
local DISPLAY_FONT, NARROW_FONT = Kit.DISPLAY_FONT, Kit.NARROW_FONT

local HERO_W = 290
ns.PanelHome_HERO_W = HERO_W
-- The facts follow these while the hero shows.
local LIVE_EVENTS = { "PLAYER_MONEY", "PLAYER_AVG_ITEM_LEVEL_UPDATE", "UPDATE_INVENTORY_DURABILITY" }
local DRAG_PIXELS_PER_RADIAN = 90 -- cursor pixels a drag moves for one radian of turn
-- The model turns a little toward the cursor while it's over the window: at most this far either side of where it
-- rests (radians), at full motion and at subtle motion.
local LOOK_RANGE = 0.35
local LOOK_RANGE_SUBTLE = 0.15
local LOOK_SPEED = 3 -- share of the remaining turn eased per second
local LOOK_EPSILON = 0.001 -- radians: close enough to land
local CLICK_SLOP = 5 -- cursor pixels a press may move and still count as a click, not a drag
-- What a click on the model plays, picked at random: animation IDs (AnimationData) Wave, Cheer, Laugh, Salute.
local EMOTES = { 67, 68, 70, 113 }
local STAND_ANIM = 0
-- Back to standing after this long even if the model never reports the emote finished (one with no such animation).
local EMOTE_MAX_SECONDS = 5

local function DurabilityText(percent)
	return percent .. "%"
end

-- Hero: the current character ------------------------------------------------------------------------------

local function Durability()
	local slots = {}
	for slot = INVSLOT_FIRST_EQUIPPED, INVSLOT_LAST_EQUIPPED do
		local cur, max = GetInventoryItemDurability(slot)
		if cur and max and max > 0 then
			slots[#slots + 1] = { slot = slot, cur = cur, max = max }
		end
	end
	local lowest = ns.Durability_Summary(slots)
	return lowest and math.floor(lowest * 100 + 0.5) or nil
end

local function ModuleOn(key)
	local module = ns.modulesByKey[key]
	return module ~= nil and module.active
end

local Signed = ns.SignedGold

local function TipPair(tip, left, right, role)
	local lr, lg, lb = UI.Color("textMuted")
	local r, g, b = UI.Color(role or "text")
	tip:AddDoubleLine(left, right, lr, lg, lb, r, g, b)
end

local Secret = ns.IsSecret

local function Capitalized(text)
	return (text:gsub("^%l", string.upper))
end

-- The hero's facts. tooltip(GameTooltip) adds the lines under the label; click runs while clickable() is true (the
-- module behind it is on), and only then does the tooltip end with clickText.
local FACTS = {
	{
		label = "Item level",
		tooltip = function(tip)
			local overall, equipped = GetAverageItemLevel()
			TipPair(tip, "Equipped", ("%.1f"):format(equipped or 0))
			TipPair(tip, "Overall", ("%.1f"):format(overall or 0))
			if ModuleOn("gear") then
				local worn = ns.GearItems_Equipped()
				local text = worn and ns.Gear_AuditText(ns.Gear_Audit(worn))
				if text then
					TipLine(tip, Capitalized(text), "danger")
				end
			end
		end,
		clickable = function()
			return ModuleOn("gear")
		end,
		clickText = "Click: character pane with Gear Check",
		click = function()
			if InCombatLockdown() then
				ns.Print_Combat("open the character pane")
				return
			end
			ns.Panel_Hide()
			ns.GearSheet_Open()
		end,
	},
	{
		label = "Gold",
		-- This session's change (by source while Session recap books it), loot worth (Gold & value), every
		-- character's gold and the Warband bank (Alts) and what they carry (Gold & value with Alts).
		tooltip = function(tip)
			local session = ns.Session_Current()
			local net = GetMoney() - (session.money or GetMoney())
			TipPair(tip, "This session", Signed(net), net < 0 and "danger" or "heading")
			if ModuleOn("recap") and net ~= 0 then
				for i, src in ipairs(ns.Recap_GoldSources(session.gold, net)) do
					if i > 4 then
						break
					end
					TipPair(tip, "   " .. ns.RECAP_SOURCE_NAMES[src.source], Signed(src.amount), "textMuted")
				end
			end
			local loot = ns.Value_SessionLootText and ns.Value_SessionLootText(session)
			if loot then
				TipLine(tip, Capitalized(loot), "textMuted")
			end
			if ModuleOn("alts") and ns.altsDB then
				TipPair(tip, "Account total", ns.Alts_Gold(ns.Alts_TotalGold(ns.altsDB.chars, ns.altsDB.warbandMoney)), "heading")
				local worth = ns.Value_AccountWorth and ns.Value_AccountWorth(ns.altsDB.chars)
				if worth then
					TipPair(tip, "Carried value (bags and banks)", ns.Alts_Gold(worth), "heading")
				end
			end
		end,
		clickable = function()
			local entry = ns.homeByKey.sessions
			return entry ~= nil and ns.HomeEntryVisible(entry)
		end,
		clickText = "Click: Sessions",
		click = function()
			ns.Panel_OpenPage("sessions")
		end,
	},
	{
		label = "Durability",
		tooltip = function(tip)
			local worst = ns.Durability_WorstSlots(3)
			if #worst == 0 then
				TipLine(tip, "Nothing equipped has durability.", "textMuted")
			end
			local r, g, b = UI.Color("text")
			for _, w in ipairs(worst) do
				tip:AddDoubleLine(w.text, w.percent, r, g, b, r, g, b)
			end
		end,
		clickable = function()
			return ModuleOn("dura")
		end,
		clickText = "Click: every item's durability in chat",
		click = function()
			ns.Durability_List()
		end,
	},
	{
		label = "Location",
		tooltip = function(tip)
			TipPair(tip, "Zone", GetZoneText())
			if GetSubZoneText() ~= "" then
				TipPair(tip, "Subzone", GetSubZoneText())
			end
			local mapID = C_Map.GetBestMapForUnit("player")
			local pos = mapID and C_Map.GetPlayerMapPosition(mapID, "player")
			if pos and not Secret(pos.x) then
				local info = C_Map.GetMapInfo(mapID)
				TipPair(tip, info and info.name or "Map", ("%.1f, %.1f"):format(pos.x * 100, pos.y * 100))
			end
		end,
		-- The click opens the map through ns.MapTabs_Opener; this only steps the window aside once it's open.
		opensMap = true,
		clickText = "Click: world map",
		click = function()
			if WorldMapFrame:IsShown() then
				ns.Panel_Hide()
			elseif InCombatLockdown() then
				ns.Print_Combat("open the map")
			end
		end,
	},
}

local function FactClickable(fact)
	return fact.click ~= nil and (not fact.clickable or ns.HomeCall(fact.clickable) == true)
end

local function FactEnter(self)
	self.bg:Show()
	local fact = self.fact
	GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
	GameTooltip:SetText(fact.label, UI.Color("heading"))
	ns.HomeCall(fact.tooltip, GameTooltip)
	if FactClickable(fact) then
		TipLine(GameTooltip, fact.clickText, "accent")
	end
	ns.MapTabs_CombatTip(self)
	GameTooltip:Show()
end

-- Model life -------------------------------------------------------------------------------------------------------

-- The frame on UIParent that holds frame: the Tomte window.
local function Window(frame)
	local parent = frame:GetParent()
	while parent and parent ~= UIParent do
		frame, parent = parent, parent:GetParent()
	end
	return frame
end

local function LookRange()
	local level = UI.MotionLevel()
	if level == "full" then
		return LOOK_RANGE
	elseif level == "subtle" then
		return LOOK_RANGE_SUBTLE
	end
	return 0
end

-- Where the cursor is across the window, from -1 (half a window left of the model) to 1, or nil off the window.
local function CursorLean(model)
	local window = Window(model)
	if not window:IsMouseOver() then
		return nil
	end
	local center = model:GetCenter()
	local half = window:GetWidth() * window:GetEffectiveScale() / 2
	if not center or half <= 0 then
		return nil
	end
	local x = GetCursorPosition()
	return math.max(-1, math.min(1, (x - center * model:GetEffectiveScale()) / half))
end

local function SetShownFacing(model, facing)
	if model.shown ~= facing then
		model.shown = facing
		model:SetFacing(facing)
	end
end

-- Runs while the model shows (and while it's dragged): a drag turns it and its resting facing; otherwise it eases
-- toward the cursor. With no idle turning (Motion off) it stops itself once it's back at rest.
local function ModelTick(self, elapsed)
	if self.dragX then
		local x = GetCursorPosition()
		self.facing = self.facing + (x - self.dragX) / DRAG_PIXELS_PER_RADIAN
		self.dragX = x
		SetShownFacing(self, self.facing)
		return
	end
	local range = LookRange()
	local target = self.facing
	if range > 0 then
		-- After a drag the cursor is still on the model, right where the drag left it: wait until it leaves before
		-- following again, so letting go doesn't swing the character off where it was put.
		if self.lookPaused and not self:IsMouseOver() then
			self.lookPaused = nil
		end
		local lean = not self.lookPaused and CursorLean(self)
		if lean then
			target = self.facing + lean * range
		end
	end
	local shown = self.shown or target
	local eased = shown + (target - shown) * math.min(elapsed * LOOK_SPEED, 1)
	if math.abs(target - eased) < LOOK_EPSILON then
		eased = target
	end
	SetShownFacing(self, eased)
	if range == 0 and eased == target then
		self:SetScript("OnUpdate", nil)
	end
end
local ModelTickTimed = ns.Perf_Wrap(ModelTick, "OnUpdate")

local function EmoteDone(model)
	model:SetScript("OnAnimFinished", nil)
	model.emoting = nil
	model:SetAnimation(STAND_ANIM)
end

-- A friendly emote, not the same one twice in a row; back to standing when it's done.
local function Emote(model)
	if model.emoting or UI.MotionLevel() == "off" then
		return
	end
	local i = math.random(#EMOTES)
	if EMOTES[i] == model.lastEmote then
		i = i % #EMOTES + 1
	end
	model.lastEmote = EMOTES[i]
	local token = {}
	model.emoting = token
	model:SetAnimation(EMOTES[i])
	-- As Blizzard's talking head model does (TalkingHeadUI.lua): the model reports when the animation has played.
	model:SetScript("OnAnimFinished", EmoteDone)
	C_Timer.After(EMOTE_MAX_SECONDS, function()
		if model.emoting == token then
			EmoteDone(model)
		end
	end)
end

function ns.PanelHome_CreateHero(parent, onOpen)
	local hero = CreateFrame("Frame", nil, parent)
	hero:SetWidth(HERO_W)

	-- Stage: the model on a faint floor.
	local stage = CreateFrame("Frame", nil, hero)
	stage:SetPoint("TOPLEFT", 16, -16)
	stage:SetPoint("TOPRIGHT", -16, -16)
	local well = stage:CreateTexture(nil, "BACKGROUND", nil, -1)
	well:SetAllPoints()
	well:SetColorTexture(UI.Color("frameDark"))
	UI.Border(stage, "frame", 0.22)
	-- A faint floor under the feet; the rest of the stage is the window itself.
	local floor = stage:CreateTexture(nil, "BACKGROUND")
	floor:SetColorTexture(1, 1, 1, 1)
	floor:SetPoint("BOTTOMLEFT", 0, 34)
	floor:SetPoint("BOTTOMRIGHT", 0, 34)
	floor:SetHeight(90)
	floor:SetGradient("VERTICAL", UI.ColorObject("accent", 0.08), UI.ColorObject("accent", 0))
	floor:SetShown(ns.Theme.HasOrnaments()) -- in Blizzard's gold it reads as a muddy band behind the name

	local model = CreateFrame("PlayerModel", nil, stage)
	model:SetPoint("TOPLEFT", 10, -6)
	model:SetPoint("BOTTOMRIGHT", -10, 34)
	model:EnableMouse(true)
	-- facing is where it rests (a drag moves it); shown is where it's drawn, a little toward the cursor (ModelTick).
	model.facing = 0.35
	model.shown = model.facing
	model:SetScript("OnMouseDown", function(self)
		local x, y = GetCursorPosition()
		self.dragX, self.downX, self.downY = x, x, y
		self:SetScript("OnUpdate", ModelTickTimed)
	end)
	model:SetScript("OnMouseUp", function(self, button)
		local x, y = GetCursorPosition()
		local click = self.downX and math.abs(x - self.downX) < CLICK_SLOP and math.abs(y - self.downY) < CLICK_SLOP
		self.dragX, self.downX, self.downY = nil, nil, nil
		if not click then
			self.lookPaused = true
		elseif button == "LeftButton" then
			Emote(self)
		end
	end)
	-- SetUnit reloads the model (it blinks, and the character floated up into place every time the window opened), so
	-- only when it isn't there yet or the character's looks changed. The model is kept while the window is closed.
	-- blend = false: no blend from the previous model's pose and place.
	model:SetKeepModelOnHide(true)
	model.needsUnit = true
	function model:Load()
		if self.needsUnit or not self:GetModelFileID() then
			self.needsUnit = false
			-- The reload starts the model standing: an emote that was playing is over.
			self:SetScript("OnAnimFinished", nil)
			self.emoting = nil
			self:SetUnit("player", false)
			self:SetFacing(self.shown)
		end
	end
	model:SetScript("OnShow", function(self)
		-- Loaded on show if it needs it (a model set while hidden may not render), whichever runs first, this or
		-- Refresh.
		self:Load()
		self:SetScript("OnUpdate", ModelTickTimed)
	end)
	model:SetScript("OnHide", function(self)
		-- Back at rest and standing for the next open; nothing runs while it's hidden.
		self:SetScript("OnUpdate", nil)
		self.dragX, self.downX, self.downY, self.lookPaused = nil, nil, nil, nil
		SetShownFacing(self, self.facing)
		if self.emoting then
			EmoteDone(self)
		end
	end)
	-- Set now too: the hero starts shown, so the first OnShow may never come. OnUpdate doesn't run while it's hidden.
	model:SetScript("OnUpdate", ModelTickTimed)
	model:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
	model:RegisterUnitEvent("UNIT_MODEL_CHANGED", "player")
	model:SetScript("OnEvent", ns.Perf_WrapEvents(function(self)
		self.needsUnit = true
		if self:IsVisible() then
			self:Load()
		end
	end))
	hero.model = model
	UI.FadeModel(model) -- fades with the window and with Home's arrival (Motion.lua)

	hero.name = UI.Text(stage, 34, "heading", DISPLAY_FONT)
	hero.name:SetPoint("BOTTOMLEFT", 6, 2)
	hero.name:SetPoint("BOTTOMRIGHT", -6, 2)
	hero.name:SetJustifyH("CENTER")
	hero.name:SetWordWrap(false)
	hero.name:SetShadowOffset(2, -2)
	hero.stage = stage

	hero.who = UI.Text(hero, 13, "textMuted")
	hero.who:SetPoint("TOP", stage, "BOTTOM", 0, -4)
	hero.who:SetJustifyH("CENTER")

	-- Each fact is a button (placed in Layout) with the faint row highlight on hover.
	hero.facts = {}
	for i, fact in ipairs(FACTS) do
		-- Facts with opensMap open the world map first (ns.MapTabs_Opener); the fact's own click is its PostClick.
		local b = CreateFrame("Button", nil, hero, "InsecureActionButtonTemplate")
		ns.MapTabs_Opener(b, function(self)
			return self.fact.opensMap == true
		end, true)
		b:SetHeight(21)
		b.fact = fact
		b.bg = b:CreateTexture(nil, "BACKGROUND")
		b.bg:SetAllPoints()
		b.bg:SetColorTexture(UI.Color("hover"))
		b.bg:Hide()
		local l = UI.Text(b, 13, "textMuted")
		l:SetText(fact.label)
		l:SetPoint("BOTTOMLEFT", 4, 3)
		local v = b:CreateFontString(nil, "OVERLAY")
		UI.SetFont(v, NARROW_FONT, 15)
		v:SetShadowOffset(1, -1)
		v:SetJustifyH("RIGHT")
		v:SetPoint("BOTTOMRIGHT", -4, 3)
		v:SetPoint("BOTTOMLEFT", l, "BOTTOMRIGHT", 10, 0)
		b:SetScript("OnEnter", FactEnter)
		b:SetScript("OnLeave", function(self)
			self.bg:Hide()
			GameTooltip:Hide()
		end)
		b:SetScript("PostClick", function(self)
			if FactClickable(self.fact) then
				UI.Sound("nav")
				GameTooltip:Hide()
				ns.HomeCall(self.fact.click)
			end
		end)
		hero.facts[i] = { button = b, label = l, value = v }
	end

	hero.actions = {}
	function hero:Layout(height)
		-- Bottom up: actions, facts, who line; the stage takes what's left.
		local quicks = ns.HomeEntries("quick")
		local y = 18
		for i = #quicks, 1, -1 do
			local entry = quicks[i]
			local b = self.actions[i]
			if not b then
				b = UI.Button(self, 100, "")
				b:SetHeight(24)
				b.label:ClearAllPoints()
				b.label:SetPoint("LEFT", 10, 0)
				b.label:SetJustifyH("LEFT")
				SetColor(b.label, "text")
				b:SetScript("OnMouseDown", function(btn)
					btn.label:SetPoint("LEFT", 11, -1)
				end)
				b:SetScript("OnMouseUp", function(btn)
					btn.label:SetPoint("LEFT", 10, 0)
				end)
				UI.SetBorderColor(b, "frame", 0.2)
				b:SetScript("OnLeave", function(btn)
					UI.SetBorderColor(btn, "frame", 0.2)
				end)
				b.count = UI.Text(b, 12, "accent", NARROW_FONT)
				b.count:SetPoint("RIGHT", -10, 0)
				b:SetScript("OnClick", function(btn)
					onOpen(btn.entry)
				end)
				self.actions[i] = b
			end
			local count = ns.HomeCall(entry.count)
			count = type(count) == "number" and count > 0 and count or nil
			-- A count that moved while the button shows (same action, not a redraw for another) pops.
			local popCount = b.entry == entry and b.shownCount ~= count and count ~= nil and b.count:IsVisible()
			b.entry, b.shownCount = entry, count
			b.label:SetText(entry.name)
			b.count:SetText(count and tostring(count) or "")
			if popCount then
				UI.Pop(b.count, 0.3)
			end
			b:ClearAllPoints()
			b:SetPoint("BOTTOMLEFT", PAD, y)
			b:SetPoint("BOTTOMRIGHT", -PAD, y)
			b:Show()
			y = y + 30
		end
		for i = #quicks + 1, #self.actions do
			self.actions[i]:Hide()
		end
		y = y + 8
		for i = #self.facts, 1, -1 do
			local b = self.facts[i].button
			b:ClearAllPoints()
			b:SetPoint("BOTTOMLEFT", PAD - 4, y - 3)
			b:SetPoint("BOTTOMRIGHT", -(PAD - 4), y - 3)
			y = y + 21
		end
		self.who:ClearAllPoints()
		self.who:SetPoint("BOTTOMLEFT", PAD, y + 6)
		self.who:SetPoint("BOTTOMRIGHT", -PAD, y + 6)
		self.stage:SetHeight(math.max(height - y - 46, 120))
	end

	function hero:Refresh()
		local class = select(2, UnitClass("player"))
		local color = class and C_ClassColor.GetClassColor(class)
		self.name:SetText(UnitName("player"))
		if color then
			self.name:SetTextColor(color.r, color.g, color.b)
		else
			SetColor(self.name, "heading")
		end
		local spec
		local index = C_SpecializationInfo.GetSpecialization()
		if index and index > 0 then
			spec = select(2, C_SpecializationInfo.GetSpecializationInfo(index))
		end
		self.who:SetText(("Level %d %s%s"):format(UnitLevel("player"), UnitRace("player") or "", spec and (", " .. spec) or ""))
		self:RefreshFacts()
		self.model:Load()
		self:Layout(self:GetHeight())
	end

	-- The facts' values; numbers run to a new value while the hero shows, and gold floats what it gained or lost.
	function hero:RefreshFacts()
		local facts = self.facts
		local _, equipped = GetAverageItemLevel()
		if equipped then
			Kit.Count(facts[1].value, math.floor(equipped), tostring)
		else
			UI.CountTo(facts[1].value, "?", tostring)
		end
		Kit.Count(facts[2].value, GetMoney(), ns.Alts_Gold, facts[2].label, Kit.GoldDelta)
		local dura = Durability()
		Kit.Count(facts[3].value, dura or 100, DurabilityText)
		facts[4].value:SetText(GetSubZoneText() ~= "" and GetSubZoneText() or GetZoneText())
		for i, f in ipairs(facts) do
			SetColor(f.value, i == 2 and "heading" or "text")
		end
		if dura and dura < 30 then
			SetColor(facts[3].value, "danger")
		end
	end

	-- Gold, item level and durability follow the game while the hero shows (Home itself redraws only when opened or
	-- when a module asks). Registered for good: the hero starts shown, so an OnShow wouldn't come for the first time.
	for _, event in ipairs(LIVE_EVENTS) do
		hero:RegisterEvent(event)
	end
	hero:SetScript("OnEvent", ns.Perf_WrapEvents(function(self)
		if self:IsVisible() then
			self:RefreshFacts()
		end
	end))

	hero:SetScript("OnSizeChanged", function(self, _, height)
		self:Layout(height)
	end)
	return hero
end
