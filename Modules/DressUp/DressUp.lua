local addonName, ns = ...

-- Dressing room: Blizzard's dressing room (DressUpFrame), bigger and with extras. It opens at a share
-- of the screen's height (only its scale changes, applied on every show and size change: Blizzard sets its size when
-- it maximizes or minimizes), with a slot bar along the bottom of the model (Slots.lua) and a toolbar on its right
-- (Tools.lua: undress, target's outfit, item list). Everything is hooked (HookScript, hooksecurefunc) and talks only
-- to the model's actor: no Blizzard function is replaced or called, so the window stays untainted.
-- Design: docs/superpowers/specs/2026-10-12-tomte-showcase-gear-menu-design.md ("Dressing room").

local OWNER = "dressup"
local CHECK_EVERY = 0.1 -- seconds between size checks while the window is open
-- The window's full (maximized) height, Blizzard's DressUpFrames.xml. The scale always comes from it: minimized the
-- window is shorter (423), and scaling that to the same share of the screen made it far too big. Blizzard minimizes
-- it on its own when it doesn't fit beside other windows, often on the first open.
local FULL_HEIGHT, FULL_WIDTH = 545, 450
local FIT_MARGIN = 0.98

-- The biggest scale at which Blizzard still lets the full window open: DressUpFrame_Show minimizes it when
-- CanShowRightUIPanel fails (RIGHT_OFFSET + scaled width incl. the outfit details panel's extraWidth past
-- GetMaxUIPanelsWidth, Blizzard_UIParentPanelManager). Too big, and it flipped between full and minimized on every
-- other open. Only Blizzard's read-only getters are used; nil when they're missing.
local function WidthFit(frame)
	if not (GetMaxUIPanelsWidth and GetUIPanelLayoutAttribute) then
		return nil
	end
	-- The panel's extra width is a frame attribute (GetUIPanelAttribute is local to Blizzard's file).
	local ok, room, extra = pcall(function()
		return GetMaxUIPanelsWidth() - GetUIPanelLayoutAttribute("RIGHT_OFFSET"),
			tonumber(frame:GetAttribute("UIPanelLayout-extraWidth")) or 0
	end)
	if not ok or type(room) ~= "number" or room <= 0 then
		return nil
	end
	return room / (FULL_WIDTH + extra) * FIT_MARGIN
end

-- Measured only while the window is closed: open, it takes a panel slot itself and the free room shrinks by its
-- own width (a big window measured a small fit and the other way round, every other open). Blizzard's own check
-- runs before the show too.
local closedFit
local function MeasureFit()
	if DressUpFrame and not DressUpFrame:IsShown() then
		closedFit = WidthFit(DressUpFrame)
	end
end

local module, db
local hooked = false
local events = ns.DressUp_Events -- Slots.lua's

local function Apply()
	local frame = DressUpFrame
	if not frame then
		return
	end
	local scale = 1
	if module.active then
		scale = ns.DressUp_FitScale(db.height, math.max(FULL_HEIGHT, frame:GetHeight()), UIParent:GetHeight())
		MeasureFit()
		local fit = closedFit
		if fit then
			scale = math.max(1, math.min(scale, fit))
		end
	end
	-- Only the scale: calling the panel manager from here would taint it (it also places protected panels).
	if math.abs(frame:GetScale() - scale) > 0.001 then
		if db and db.debug then
			ns.Print(("dressing room: height %.0f, screen %.0f, scale %.3f -> %.3f"):format(frame:GetHeight(),
				UIParent:GetHeight(), frame:GetScale(), scale))
		end
		frame:SetScale(scale)
	end
end

-- While the window is open its size is checked a few times a second: on the first open Blizzard lays it out (and
-- may scale it to fit) after our OnShow, in an order that differs from later opens.
local watcher
local function Watch()
	if watcher or not DressUpFrame then
		return
	end
	watcher = CreateFrame("Frame", nil, DressUpFrame)
	local t = 0
	watcher:SetScript("OnUpdate", function(_, elapsed)
		t = t + elapsed
		if t >= CHECK_EVERY then
			t = 0
			if module.active then
				Apply()
			end
		end
	end)
end

local function UpdateExtras()
	local on = module.active
	ns.DressUpBar.Update(on and db.slots)
	ns.DressUpTools.Update(on and db.tools)
end

local function Hook()
	local frame = DressUpFrame
	if hooked or not frame then
		return
	end
	hooked = true
	Watch()
	Apply() -- before its first show, so the panel manager places it at our scale
	frame:HookScript("OnShow", function(self)
		if db.debug then
			local mm = self.MaximizeMinimizeFrame
			ns.Print(("dressing room shown: height %.0f, scale %.3f, minimized %s, width fit %s, extra %s"):format(
				self:GetHeight(), self:GetScale(), tostring(mm and mm:IsMinimized()), tostring(closedFit),
				tostring(self:GetAttribute("UIPanelLayout-extraWidth"))))
			C_Timer.After(0.3, function()
				ns.Print(("  0.3 s later: height %.0f, scale %.3f, minimized %s, on screen %.0f x %.0f"):format(
					self:GetHeight(), self:GetScale(), tostring(mm and mm:IsMinimized()),
					self:GetWidth() * self:GetScale(), self:GetHeight() * self:GetScale()))
			end)
		end
		Apply()
		ns.DressUpBar.Reset()
		UpdateExtras()
		-- The player actor is set up right after the show, and on the first open Blizzard lays the window out
		-- (maximized size) after OnShow: measure again once it has settled.
		C_Timer.After(0, function()
			Apply()
			UpdateExtras()
		end)
		C_Timer.After(0.1, Apply)
	end)
	frame:HookScript("OnHide", function()
		UpdateExtras()
		-- Once the panel manager has let go of its slot.
		C_Timer.After(0, function()
			MeasureFit()
			Apply()
		end)
	end)
	frame:HookScript("OnSizeChanged", function(self)
		if self:IsShown() then
			Apply()
		end
	end)
	-- Player, mount or pet: the extras are for the player model only.
	hooksecurefunc(frame, "SetMode", UpdateExtras)
	frame.ModelScene:HookScript("OnDressModel", function(...)
		if module.active then
			ns.DressUpBar.OnDressModel(...)
		end
	end)
	if frame.ResetButton then
		frame.ResetButton:HookScript("OnClick", function()
			ns.DressUpBar.Reset()
		end)
	end
end

events:On(OWNER, "PLAYER_ENTERING_WORLD", function()
	Hook()
	Apply()
end)

local function Percent(v)
	return ("%d%%"):format(math.floor(v * 100 + 0.5))
end

module = ns.RegisterModule({
	key = "dressup",
	name = "Dressing room",
	category = "gear",
	icon = 135030, -- inv_shirt_white_01
	summary = "A bigger dressing room with a slot bar and outfit tools.",
	description = "The dressing room (Ctrl-click an item) opens bigger, with a slot bar under the model (click a "
		.. "piece to hide it, Shift-click to link it) and buttons to undress, show your target's outfit and list the "
		.. "outfit with where each piece comes from.",
	enabledByDefault = true,
	defaults = {
		height = 0.8,
		slots = true,
		tools = true,
		ownBody = false,
		debug = false, -- chat lines when the dressing room's size is set (hidden /tomte dressup debug)
	},
	noShare = { "debug" }, -- a debug switch: not in settings strings (Core/Profile.lua)
	init = function(saved)
		db = saved
		ns.DressUpTools.Init(saved)
	end,
	toggle = function(active)
		if active then
			events:Watch(OWNER, "PLAYER_ENTERING_WORLD")
			Hook()
		else
			events:UnwatchAll(OWNER)
		end
		Apply()
		UpdateExtras()
	end,
	commands = {
		{ "debug", "chat lines when the dressing room's size is set", function()
			db.debug = not db.debug
			ns.Print("Dressing room debug " .. (db.debug and "on" or "off") .. ".")
		end, hidden = true },
	},
	options = {
		{ type = "header", label = "Dressing room" },
		{ type = "slider", key = "height", label = "Size", min = 0.5, max = 0.95, step = 0.05, format = Percent,
			tooltip = "How much of your screen's height the dressing room takes.", onChange = Apply },
		{ type = "checkbox", key = "slots", label = "Slot bar", onChange = UpdateExtras,
			tooltip = "A button per slot under the model: hover for the item, click to hide or show it, Shift-click to "
				.. "link it." },
		{ type = "checkbox", key = "tools", label = "Toolbar", onChange = UpdateExtras,
			tooltip = "Undress, Target's outfit and Item list buttons on the right of the model." },
		{ type = "checkbox", key = "ownBody", label = "Target's outfit on your character", parent = "tools",
			tooltip = "Target's outfit dresses your own character instead of the target's." },
	},
})
