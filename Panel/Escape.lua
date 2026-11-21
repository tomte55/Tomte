local addonName, ns = ...

-- Widgets: Esc closes Tomte's windows one at a time, top first (UI.CloseOnEscape). The rest of the widget kit is
-- in Widgets.lua, Inputs.lua, Scroll.lua and Controls.lua.

local UI = ns.UI

-- Escape --------------------------------------------------------------------------------------------------------------

-- Esc closes the Tomte frame on top (the last one shown), one per press, so a dialog over the Tomte window closes on
-- its own. One dummy in UISpecialFrames stands for all of them: Blizzard's CloseSpecialWindows hides it, its OnHide
-- closes the top frame a frame later, and while more are open the dummy shows again. Works in combat, where a frame
-- can't take keyboard input. (RegisterGameMenuEscHandler would be the direct way, but registering a handler from addon
-- code taints the Esc chain.) Alt+Z and loss of control run CloseAllWindows too, and UIParent still counts as shown
-- a frame after Alt+Z (measured 12.1), so only a hide that came with Esc (ToggleGameMenu, the Esc binding) closes
-- anything; after the others the frames stay and come back with the UI.
local escapeOpen = {} -- shown frames in the order they were shown: the last one is on top
local escapeDummy
local escAt -- GetTime() of the last ToggleGameMenu (Esc): the same value in the frame the dummy hid means Esc hid it

-- Drops every frame that isn't shown any more from the list (also one hidden by code while UIParent was hidden,
-- whose OnHide never came).
local function EscapeForget()
	for i = #escapeOpen, 1, -1 do
		if not escapeOpen[i]:IsShown() then
			table.remove(escapeOpen, i)
		end
	end
end

local function EscapeListed(frame)
	for _, f in ipairs(escapeOpen) do
		if f == frame then
			return true
		end
	end
	return false
end

local function EscapeDummy()
	if escapeDummy then
		return escapeDummy
	end
	escapeDummy = CreateFrame("Frame", "TomteEscape", UIParent)
	escapeDummy:Hide()
	tinsert(UISpecialFrames, "TomteEscape")
	-- Only notes the press; Esc handling is Tomte's own, always on, so the hook never needs switching off. It runs
	-- after Blizzard's Esc chain, in the same frame as the dummy's OnHide; the close waits a frame for it.
	hooksecurefunc("ToggleGameMenu", function()
		escAt = GetTime()
	end)
	escapeDummy:SetScript("OnHide", function(self)
		-- Still shown: UIParent hid (Alt+Z, a cinematic), not Esc; the frames come back with it.
		if self:IsShown() then
			return
		end
		local hidAt = GetTime()
		C_Timer.After(0, function()
			EscapeForget()
			-- Esc closes the top frame; Alt+Z, the AFK screen or a loss of control keep them all.
			local top = escAt == hidAt and escapeOpen[#escapeOpen]
			if top then
				top:Hide() -- its OnHide takes it off the list
			end
			if #escapeOpen > 0 and not self:IsShown() then
				self:Show()
			end
		end)
	end)
	return escapeDummy
end

-- Esc closes frame, the last one shown first. Call it after the frame's own SetScript("OnShow"/"OnHide"): SetScript
-- drops hooks.
function UI.CloseOnEscape(frame)
	local dummy = EscapeDummy()
	frame:HookScript("OnShow", function(self)
		EscapeForget()
		-- Already listed: UIParent is back after Alt+Z or a cinematic; the frame keeps its place in the order.
		if not EscapeListed(self) then
			escapeOpen[#escapeOpen + 1] = self
		end
		dummy:Show()
	end)
	frame:HookScript("OnHide", function(self)
		-- Still shown: only UIParent hid, the frame comes back with it and stays on the list.
		if self:IsShown() then
			return
		end
		EscapeForget()
		if #escapeOpen == 0 then
			dummy:Hide()
		end
	end)
end
