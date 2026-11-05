local addonName, ns = ...

-- The first-run picker: on a new install (TomteDB.setup.state == "pending", Core.lua) a window asks which preset
-- to start with. /tomte setup opens it any time. Presets and their rules: Core/Setup.lua. Existing users never get
-- it by surprise (settings migration 2 marks them done).

local UI = ns.UI
local W, H = 660, 620
local PAD = 16
local CARD_W = (W - PAD * 2 - 12) / 2
local CARD_H = 172
local WIDE_H = 90 -- Everything: across the window, room for its text to wrap once
local FIRST_RUN_DELAY = 3 -- seconds after PLAYER_ENTERING_WORLD before the first-run picker tries to show
local BUSY_RETRY = 5 -- seconds between tries while a cinematic or movie plays

local frame, selected, fromCommand

local function SetSelected(key)
	selected = key
	for _, card in ipairs(frame.cards) do
		if card.key == key then
			UI.BorderTo(card, "accent", 1)
		else
			UI.BorderTo(card, "frame", 0.35)
		end
	end
end

local function Done()
	ns.db.setup.state = "done"
end

local function UseThis()
	if InCombatLockdown() then
		ns.Print_Combat("apply a preset")
		UI.Shake(frame)
		return
	end
	local preset = ns.Setup_Preset(selected)
	local plan = preset and ns.Setup_Plan(selected, ns.modules)
	if not plan then
		return
	end
	ns.Setup_Apply(ns.db, plan, ns.modules)
	Done()
	ns.db.setup.preset = selected
	frame:Hide()
	-- Counted after applying: the modules a preset leaves alone (SETUP_UNTOUCHED) may be on too; blocked ones (another
	-- class's) don't run.
	local on = 0
	for _, module in ipairs(ns.modules) do
		if not module.alwaysOn and ns.ModuleWanted(module) then
			on = on + 1
		end
	end
	ns.Print(("%s set up: %d modules on. /tomte setup to change it."):format(preset.name, on))
	if ns.Panel_IsShown() then
		ns.Panel_Refresh()
	end
end

local function ChooseMyself()
	Done()
	frame:Hide()
	-- The settings list, on the Tomte window's own page: ns.modules[1] is "window" because Panel/Window.lua is the
	-- first file in Tomte.toc that registers a module.
	ns.Panel_OpenModule(ns.modules[1].key)
end

-- "Whispers, Mentions, Friends Online and Group Alerts": the modules no preset switches unless it names them.
local function UntouchedNames()
	local names = {}
	for _, key in ipairs(ns.SETUP_UNTOUCHED) do
		local module = ns.modulesByKey[key]
		names[#names + 1] = module and module.name or key
	end
	if #names < 2 then
		return names[1] or ""
	end
	return table.concat(names, ", ", 1, #names - 1) .. " and " .. names[#names]
end

local function CreateCard(parent, preset)
	local card = CreateFrame("Button", nil, parent)
	card:SetSize(CARD_W, CARD_H)
	card.key = preset.key
	UI.Surface(card)
	card.name = UI.Text(card, 14, "heading", "title")
	card.name:SetPoint("TOPLEFT", 10, -10)
	card.match = UI.Text(card, 11, "success")
	card.match:SetPoint("TOPRIGHT", -10, -12)
	card.match:SetText("matches your setup now")
	card.text = UI.Text(card, 13, "text")
	card.text:SetPoint("TOPLEFT", card.name, "BOTTOMLEFT", 0, -6)
	card.text:SetPoint("RIGHT", -10, 0)
	card.text:SetJustifyH("LEFT")
	card.on = UI.Text(card, 12, "textMuted")
	card.on:SetPoint("TOPLEFT", card.text, "BOTTOMLEFT", 0, -6)
	card.on:SetPoint("RIGHT", -10, 0)
	card.on:SetPoint("BOTTOM", 0, 8)
	card.on:SetJustifyH("LEFT")
	card.on:SetJustifyV("TOP")
	card.on:SetWordWrap(true)
	card.name:SetText(preset.name)
	card.text:SetText(preset.text)
	card:SetScript("OnClick", function(self)
		if selected ~= self.key then
			UI.Sound("pick")
		end
		SetSelected(self.key)
	end)
	card:SetScript("OnDoubleClick", function(self)
		SetSelected(self.key)
		UseThis()
	end)
	card:SetScript("OnEnter", function(self)
		if selected ~= self.key then
			UI.BorderTo(self, "accent", 0.6)
		end
	end)
	card:SetScript("OnLeave", function(self)
		if selected ~= self.key then
			UI.BorderTo(self, "frame", 0.35)
		end
	end)
	return card
end

local function Build()
	frame = UI.Dialog("TomteSetup", W, H) -- Escape closes it (counts as Skip on the first run)

	local title = UI.Text(frame, 18, "heading", "title")
	title:SetPoint("TOPLEFT", PAD, -PAD)
	title:SetText("Welcome to Tomte")
	local line = UI.Text(frame, 12, "textMuted")
	line:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
	line:SetText("Pick what you want. You can change every module later.")

	frame.cards = {}
	for i, preset in ipairs(ns.SETUP_PRESETS) do
		local card = CreateCard(frame, preset)
		local col, row = (i - 1) % 2, math.floor((i - 1) / 2)
		if preset.all then
			col = 0
			card:SetSize(W - PAD * 2, WIDE_H)
		end
		card:SetPoint("TOPLEFT", PAD + col * (CARD_W + 12), -70 - row * (CARD_H + 12))
		frame.cards[i] = card
	end

	local foot = UI.Text(frame, 11, "textMuted")
	foot:SetPoint("BOTTOMLEFT", PAD, 40)
	foot:SetPoint("RIGHT", -PAD, 0)
	foot:SetJustifyH("LEFT")
	foot:SetText("Hunter Pets, Pet Health and Rogue Poisons only wake up on that class. Whispers, Mentions, Friends "
		.. "Online and Group Alerts stay as they are unless a preset names them. Settings inside modules don't change.")

	local skip = UI.Button(frame, 80, "Skip")
	skip:SetPoint("BOTTOMRIGHT", -PAD, 14)
	skip:SetScript("OnClick", function()
		frame:Hide() -- OnHide does the rest on the first run
	end)
	local mine = UI.Button(frame, 120, "Choose myself")
	mine:SetPoint("RIGHT", skip, "LEFT", -8, 0)
	mine:SetScript("OnClick", ChooseMyself)
	local use = UI.Button(frame, 100, "Use this")
	use:SetPoint("RIGHT", mine, "LEFT", -8, 0)
	use:SetScript("OnClick", UseThis)

	-- Skip, Esc or a reload-free close while the first run is still open: defaults stay. Not when only UIParent
	-- hid (Alt+Z, a cinematic): the frame is still shown then and comes back with it.
	frame:HookScript("OnHide", function(self)
		if self:IsShown() then
			return
		end
		if ns.db.setup.state == "pending" then
			Done()
			ns.Print("Tomte keeps everything on. Change it any time with /tomte setup.")
		end
	end)
end

local function Show()
	if not frame then
		Build()
	end
	local pick
	for _, card in ipairs(frame.cards) do
		local names = ns.Setup_OnNames(card.key, ns.modules)
		if ns.Setup_Preset(card.key).all then
			card.on:SetText(("Turns on: the %d modules that start on. %s stay as they are."):format(#names,
				UntouchedNames()))
		else
			card.on:SetText("Turns on: " .. table.concat(names, ", "))
		end
		local matches = fromCommand and ns.Setup_Matches(card.key, ns.modules)
		card.match:SetShown(matches)
		if matches and not pick then
			pick = card.key
		end
	end
	local saved = ns.db.setup.preset
	SetSelected(pick or (ns.Setup_Preset(saved or "") and saved) or "everything")
	if not frame:IsShown() then
		frame:Show()
		UI.Appear(frame)
		UI.EnterUpRows(frame.cards)
	end
end

-- /tomte setup and the Run setup button.
function ns.SetupUI_Show()
	if InCombatLockdown() then
		ns.Print_Combat("run setup")
		return
	end
	fromCommand = true
	Show()
end

-- First run ------------------------------------------------------------------------------------------------------

local events = CreateFrame("Frame")
events:SetScript("OnEvent", ns.Perf_WrapEvents(function(self, event, ...)
	self[event](self, ...)
end))
events:RegisterEvent("PLAYER_ENTERING_WORLD")

local function Busy()
	return ns.AnyCinematicState() ~= nil
		or (CinematicFrame and CinematicFrame:IsShown())
		or (MovieFrame and MovieFrame:IsShown())
end

local function TryShow()
	if not (ns.db and ns.db.setup.state == "pending") or (frame and frame:IsShown()) then
		return
	end
	if InCombatLockdown() then
		events:RegisterEvent("PLAYER_REGEN_ENABLED")
		return
	end
	if Busy() then
		C_Timer.After(BUSY_RETRY, TryShow)
		return
	end
	fromCommand = false
	Show()
end

function events:PLAYER_ENTERING_WORLD()
	self:UnregisterEvent("PLAYER_ENTERING_WORLD")
	if ns.db and ns.db.setup.state == "pending" then
		-- A few seconds in, not on the first frame: lets the world settle after the loading screen and gives a
		-- cinematic that starts right after login (a new character's intro) time to show, so Busy() sees it.
		C_Timer.After(FIRST_RUN_DELAY, TryShow)
	end
end

function events:PLAYER_REGEN_ENABLED()
	self:UnregisterEvent("PLAYER_REGEN_ENABLED")
	TryShow()
end
