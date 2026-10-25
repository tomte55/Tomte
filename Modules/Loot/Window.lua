local addonName, ns = ...

-- Loot: the loot window that opens when you loot by hand (and when auto loot leaves something behind). This file is
-- the window itself: where it opens (at the mouse or where Edit Mode put it, growing down or up), Escape, the Take all
-- key while looting, paging, closing it (which ends the loot, as the game's window does) and the sample Edit Mode
-- shows. What's inside is drawn by the chosen look (LookStrips.lua, LookPanel.lua, LookTiles.lua), each registered
-- in ns.LootLooks; the shared pieces are in Parts.lua, the lines in Data.lua, the loot session in Loot.lua.
--
-- A look is { Build(host) -> view, Draw(view, ctx) -> width, height }. view.root is the look's frame on host; Draw
-- lays it out from ctx = { entries, title, size (font size), bgAlpha, perPage, foldJunk, extras (the extras'
-- switches), page, live (the loot is open: pieces loot when clicked), preview, keyText (Take all's key or nil), canTake, actions = { Loot(entries),
-- TakeAll(), Close(), Turn(delta) } } and writes the page it showed back as ctx.page and ctx.pages. A look draws
-- from ctx alone (and the extras through Parts.lua), so it can be drawn into any frame with sample loot.

local DEFAULT_LOOK = "strips"
-- Where the window opens until Edit Mode moves it: its top-left corner (grow down) or bottom-left (grow up),
-- from the middle of the screen.
local DEFAULT_X, DEFAULT_TOP, DEFAULT_BOTTOM = 180, 160, -160
local MOUSE_OFFSET = 20 -- the window's corner from the cursor, so the cursor sits on the first piece
-- What Edit Mode (and /tomte loot test) shows.
local PREVIEW = {
	{ slot = 1, kind = "money", name = "12 Gold 40 Silver", quantity = 0 },
	{ slot = 2, kind = "item", name = "Sample blade", quality = 4, icon = 135274, quantity = 1, classID = 2, -- sword_04
		subType = "Swords", newLook = true, value = 1250000, verdict = { text = "Upgrade +4.2%: equip it",
		role = "success", upgrade = true } },
	{ slot = 3, kind = "item", name = "Sample cloth", quality = 1, icon = 132889, quantity = 5, classID = 7, -- linen
		subType = "Cloth", owned = 40, value = 2400 },
	{ slot = 4, kind = "item", name = "Broken tooth", quality = 0, quantity = 2, sell = 35 },
	{ slot = 5, kind = "item", name = "Torn pelt", quality = 0, icon = 134366, quantity = 1, sell = 120 }, -- pelt_wolf
}

local UI = ns.UI

ns.LootLooks = {} -- [key] = a look, registered by LookStrips.lua, LookPanel.lua, LookTiles.lua

local db, module
local frame
local views = {} -- [look key] = the look's view, built on first use
-- entries: the slots shown; open: the loot is open in the game (pieces can loot); preview: Edit Mode's sample.
local state = { entries = {}, page = 1, pages = 1, title = "Loot", look = DEFAULT_LOOK, open = false, preview = false }

local function Turn(delta)
	if state.pages > 1 then
		state.page = state.page + delta
		ns.LootWindow_Draw()
	end
end

-- The settings preview's pieces do nothing (Preview.lua keeps the mouse off them anyway).
local function Nothing()
end
local SAMPLE_ACTIONS = { Loot = Nothing, TakeAll = Nothing, Close = Nothing, Turn = Nothing }

-- What the pieces do when clicked.
local ACTIONS = {
	Loot = function(entries)
		for _, e in ipairs(entries) do
			if not e.taken and not e.locked then
				LootSlot(e.slot)
			end
		end
	end,
	TakeAll = function()
		ns.Loot_TakeAll()
	end,
	Close = function()
		ns.LootWindow_Hide()
	end,
	Turn = Turn,
}

-- Escape and keys ---------------------------------------------------------------------------------------------------

local escapeQuiet = false -- the Escape stand-in is being hidden by code, not by Escape

local function SetEscape(on)
	local escape = frame and frame.escape
	if not escape then
		return
	end
	if on then
		escape:Show()
	elseif escape:IsShown() then
		escapeQuiet = true
		escape:Hide()
		escapeQuiet = false
	end
end

-- The keyboard is on only while a loot is open in the window, a key is chosen, Loot is on and you're out of combat.
-- combat: called from PLAYER_REGEN_DISABLED, which comes just before the lockdown starts.
function ns.LootWindow_UpdateKeys(combat)
	if not frame then
		return
	end
	combat = combat or InCombatLockdown()
	local want = not combat and state.open and not state.preview and frame:IsShown() and db.lootKey ~= "off"
		and module ~= nil and module.active
	if want then
		frame:SetPropagateKeyboardInput(true)
		frame:EnableKeyboard(true)
	else
		frame:EnableKeyboard(false)
		if not combat then
			frame:SetPropagateKeyboardInput(true)
		end
	end
end

-- Window --------------------------------------------------------------------------------------------------------

local function Build()
	frame = CreateFrame("Frame", nil, UIParent)
	frame:SetSize(280, 100)
	frame:SetFrameStrata("HIGH")
	frame:SetClampedToScreen(true)
	frame:SetMovable(true)
	frame:EnableMouse(true)
	frame:EnableMouseWheel(true)
	frame:Hide()
	frame:SetScript("OnMouseWheel", function(_, delta)
		Turn(-delta)
	end)

	-- Closing the window (x, Escape) ends the loot, as the game's window does; not when only UIParent hid (Alt+Z).
	frame:SetScript("OnHide", function(self)
		if self:IsShown() then
			return
		end
		GameTooltip_Hide()
		local wasOpen = state.open and not state.preview
		state.open, state.preview = false, false
		SetEscape(false)
		ns.LootWindow_UpdateKeys()
		if wasOpen then
			CloseLoot()
		end
	end)

	-- Escape: a stand-in frame on Tomte's Escape list, shown while the window can loot (or shows the sample).
	frame.escape = CreateFrame("Frame", nil, UIParent)
	frame.escape:Hide()
	frame.escape:SetScript("OnHide", function(self)
		if self:IsShown() or escapeQuiet then
			return
		end
		ns.LootWindow_Hide() -- Escape hid it
	end)
	UI.CloseOnEscape(frame.escape)

	-- The take-all key while looting: only that key is kept from the game, every other key goes on as usual.
	-- SetPropagateKeyboardInput can't be called from addon code in combat (10.1.5), so in combat the keyboard is off
	-- and every key passes (UpdateKeys).
	frame:SetScript("OnKeyDown", function(self, key)
		if InCombatLockdown() then
			return
		end
		local take = state.open and not state.preview and key == db.lootKey
		self:SetPropagateKeyboardInput(not take)
		if take then
			ns.Loot_TakeAll()
		end
	end)
end

local function Place()
	frame:ClearAllPoints()
	local corner = db.growUp and "BOTTOMLEFT" or "TOPLEFT"
	if db.atMouse and not ns.EditMode_Active() and not state.preview then
		local x, y = GetCursorPosition()
		local scale = frame:GetEffectiveScale()
		x, y = x / scale - MOUSE_OFFSET, y / scale
		frame:SetPoint(corner, UIParent, "BOTTOMLEFT", x, db.growUp and (y - MOUSE_OFFSET) or (y + MOUSE_OFFSET))
		return
	end
	local p = db.window
	if p.set then
		frame:SetPoint(corner, UIParent, "BOTTOMLEFT", p.x, db.growUp and p.bottom or p.top)
	else
		frame:SetPoint(corner, UIParent, "CENTER", DEFAULT_X, db.growUp and DEFAULT_BOTTOM or DEFAULT_TOP)
	end
end

local function SavePosition()
	local left, top, bottom = frame:GetLeft(), frame:GetTop(), frame:GetBottom()
	if not (left and top and bottom) then
		return
	end
	local p = db.window
	p.x, p.top, p.bottom, p.set = left, top, bottom, true
	Place()
end

-- The chosen look, built on first use; the others' frames hide.
local function CurrentView()
	local key = ns.LootLooks[db.look] and db.look or DEFAULT_LOOK
	if not views[key] then
		local view = ns.LootLooks[key].Build(frame)
		view.root:SetAllPoints(frame)
		views[key] = view
	end
	for k, view in pairs(views) do
		view.root:SetShown(k == key)
	end
	return ns.LootLooks[key], views[key]
end

function ns.LootWindow_Draw()
	if not frame then
		return
	end
	local live = state.open and not state.preview
	local ctx = {
		entries = state.entries,
		title = state.title,
		size = db.fontSize,
		bgAlpha = db.bgAlpha,
		perPage = db.perPage,
		foldJunk = db.extras.foldJunk,
		extras = db.extras,
		page = state.page,
		live = live,
		preview = state.preview,
		keyText = ns.LootParts_TakeKeyText(),
		canTake = state.preview or (live and #ns.Loot_Takeable(state.entries) > 0),
		actions = ACTIONS,
	}
	local look, view = CurrentView()
	local w, h = look.Draw(view, ctx)
	state.page, state.pages = ctx.page or 1, ctx.pages or 1
	frame:SetSize(w, h)
	SetEscape(state.open or state.preview)
end

-- API for Loot.lua ------------------------------------------------------------------------------------------------

-- s = { entries, title, place (true: a new loot window, place it again) }.
function ns.LootWindow_Show(s)
	if not frame then
		Build()
	end
	local fresh = not frame:IsShown() or s.place
	state.entries, state.title = s.entries, s.title or "Loot"
	state.open, state.preview = true, false
	if fresh then
		state.page = 1
		Place()
	end
	ns.LootWindow_Draw()
	frame:Show()
	ns.LootWindow_UpdateKeys()
end

function ns.LootWindow_Shown()
	return frame ~= nil and frame:IsShown() and not state.preview
end

-- The loot closed: the window goes with it.
function ns.LootWindow_Closed()
	if frame and frame:IsShown() and not state.preview then
		frame:Hide()
	end
end

function ns.LootWindow_Hide()
	if frame then
		frame:Hide()
	end
end

-- Settings changed: redraw (and place again unless it opens at the mouse).
function ns.LootWindow_Relayout()
	if frame and frame:IsShown() then
		if not db.atMouse or state.preview then
			Place()
		end
		ns.LootWindow_Draw()
	end
end

function ns.LootWindow_ResetPosition()
	db.window.set = false
	ns.LootWindow_Relayout()
end

-- The sample window: in Edit Mode, and from /tomte loot test (until closed).
local function ShowPreview()
	if not frame then
		Build()
	end
	state.entries, state.title = PREVIEW, "Sample corpse"
	state.open, state.preview, state.page = false, true, 1
	Place()
	ns.LootWindow_Draw()
	frame:Show()
end
ns.LootWindow_Preview = ShowPreview

local function RefreshPreview()
	if not db then
		return
	end
	local want = ns.EditMode_Active() and module and module.active
	if want and not ns.LootWindow_Shown() then
		ShowPreview()
	elseif not want and frame and state.preview then
		frame:Hide()
	end
end

ns.EditMode_Register({
	name = "Loot window",
	frame = function()
		return module and module.active and frame or nil
	end,
	refresh = RefreshPreview,
	saved = SavePosition,
	module = "loot",
	options = { "look", "fontSize", "bgAlpha", "perPage", "growUp", "atMouse" },
	reset = function()
		ns.LootWindow_ResetPosition()
	end,
})

-- The sample window drawn into host for a settings preview (Preview.lua), in the look and settings get(key) answers.
-- Each look is built into host once. Returns its width and height.
function ns.LootWindow_DrawSample(host, get)
	host.lootViews = host.lootViews or {}
	local key = ns.LootLooks[get("look")] and get("look") or DEFAULT_LOOK
	if not host.lootViews[key] then
		local view = ns.LootLooks[key].Build(host)
		view.root:SetAllPoints(host)
		host.lootViews[key] = view
	end
	for k, view in pairs(host.lootViews) do
		view.root:SetShown(k == key)
	end
	local ctx = {
		entries = PREVIEW,
		title = get("extras.source") and "Sample corpse" or "Loot",
		size = get("fontSize"),
		bgAlpha = get("bgAlpha"),
		perPage = get("perPage"),
		foldJunk = get("extras.foldJunk"),
		extras = db.extras,
		page = 1,
		live = false,
		preview = true,
		keyText = ns.LootParts_TakeKeyText(get("lootKey")),
		canTake = true,
		actions = SAMPLE_ACTIONS,
	}
	return ns.LootLooks[key].Draw(host.lootViews[key], ctx)
end

function ns.LootWindow_Init(moduleDB, lootModule)
	db, module = moduleDB, lootModule
end
