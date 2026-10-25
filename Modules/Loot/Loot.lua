local addonName, ns = ...

-- Loot: auto loot shows up in the feed, looting by hand opens a loot window in one of three looks (Strips, Panel,
-- Tiles); fast loot, Take all, Blizzard's loot pop-ups replaced and the boss loot banner trimmed. This file holds the
-- loot session (the loot events, fast loot, when the window opens and what goes to the feed), the hand-over of
-- Blizzard's loot window, the settings and the module. Pure rules in Data.lua, slots read in Read.lua, shared
-- drawing in Parts.lua, the window in Window.lua and its looks in Look*.lua, the feed in Feed.lua, pop-ups, boss
-- banner, reputation and currency lines in Toasts.lua.
--
-- Blizzard's loot window (LootFrame) opens on LOOT_OPENED and closes on LOOT_CLOSED (Blizzard_UIPanels_Game
-- LootFrame.lua). While Loot is on, LootFrame stops listening to those two events, so it never opens; Stop gives
-- them back. Nothing of Blizzard's is hooked or replaced, so its code stays untainted. LootSlot needs no key press
-- (it isn't protected), so fast loot can take every slot as soon as LOOT_READY fires.

local OWNER = "loot"
local STUCK_DELAY = 1 -- seconds after the loot opens before auto-loot counts as done: what's left is stuck
local ERROR_DELAY = 0.1 -- after a loot error (bags full, roll pending), before looking at what's left
local RETRY_DELAY = 0.4 -- fast loot tries a slot again this long after it changed (area loot)
local MAX_RETRIES = 3 -- per loot window, so a slot that keeps failing can't flood the server
local MONEY_GRACE = 1 -- seconds after the loot closes in which money still counts (auto-loot can land it late)
local INFO_DELAY = 0.2 -- item data arrives in bursts: one redraw per burst
local LOOT_EVENTS = { "LOOT_READY", "LOOT_OPENED", "LOOT_SLOT_CLEARED", "LOOT_SLOT_CHANGED", "LOOT_CLOSED" }
local SESSION_EVENTS = { "UI_ERROR_MESSAGE", "PLAYER_MONEY", "GET_ITEM_INFO_RECEIVED" } -- while a loot is open
local BLIZZARD_EVENTS = { "LOOT_OPENED", "LOOT_CLOSED" } -- what Blizzard's loot window opens and closes on
local BINDING = "TOMTE_LOOT_TAKE_ALL"

local UI = ns.UI
local Readable = ns.Readable
local events = ns.Loot_Events

local module, db
-- The open loot window: { id, open, auto, entries (by slot), title, tried = { [slot] = true }, retries, money,
-- junk (folded junk waiting for the feed), displayed, windowShown, stuck }. Kept MONEY_GRACE after it closes.
local session
local sessions = 0 -- counts loot windows, so a late timer can tell its window from a newer one
local blizzardTaken = {} -- [event] = true: taken from LootFrame
local last = {} -- the last loot window's decisions, for /tomte loot why

-- Blizzard's loot window ------------------------------------------------------------------------------------------

-- Taken only while LootFrame is closed: an open one keeps its events, or it would never get its LOOT_CLOSED.
local function TakeBlizzardWindow(take)
	local frame = _G.LootFrame
	if not frame then
		return
	end
	for _, event in ipairs(BLIZZARD_EVENTS) do
		if take and not blizzardTaken[event] and not frame:IsShown() and frame:IsEventRegistered(event) then
			frame:UnregisterEvent(event)
			blizzardTaken[event] = true
		elseif not take and blizzardTaken[event] then
			frame:RegisterEvent(event)
			blizzardTaken[event] = nil
		end
	end
end

-- Another loot addon (ElvUI's loot, XLoot, Plumber ...) took LootFrame's events itself: its window shows the loot, so
-- Tomte opens none and doesn't fast loot (the feed lines still work).
local function OtherLootWindow()
	local frame = _G.LootFrame
	return frame ~= nil and not blizzardTaken.LOOT_OPENED and not frame:IsShown()
		and not frame:IsEventRegistered("LOOT_OPENED")
end

-- Session --------------------------------------------------------------------------------------------------------

-- An event's autoloot argument, nil when it can't be read.
local function Payload(value)
	if Readable(value) and type(value) == "boolean" then
		return value
	end
	return nil
end

-- payload: LOOT_READY's (or LOOT_OPENED's) autoloot, from Payload.
local function NewSession(payload)
	sessions = sessions + 1
	local cvar = C_CVar.GetCVarBool("autoLootDefault")
	local modifier = IsModifiedClick("AUTOLOOTTOGGLE")
	session = {
		id = sessions,
		open = true,
		other = OtherLootWindow(),
		auto = ns.Loot_ShouldAutoLoot(payload, cvar, modifier),
		entries = {},
		title = "Loot",
		tried = {},
		retries = 0,
		money = GetMoney(),
		junk = {},
	}
	last = { payload = payload, cvar = cvar, modifier = modifier, auto = session.auto, fast = db.fastLoot,
		look = db.look, other = session.other }
	for _, event in ipairs(SESSION_EVENTS) do
		events:Watch(OWNER, event)
	end
end

-- Reads every slot that isn't taken yet (a taken slot keeps what it held, so the window can still show it). A slot
-- that held something and reads empty now was emptied by fast loot before its LOOT_SLOT_CLEARED: it keeps what it held
-- too, and the loot closing marks it taken (SweepTaken).
local function Reread()
	local opts = ns.Loot_ReadOptions(db)
	local n = GetNumLootItems()
	for slot = 1, (Readable(n) and n or 0) do
		local old = session.entries[slot]
		if not (old and old.taken) then
			local e = ns.Loot_ReadSlot(slot, opts)
			if not (e.kind == "none" and old and old.kind ~= "none") then
				session.entries[slot] = e
			end
		end
	end
	session.title = db.extras.source and ns.Loot_ReadSource() or "Loot"
end

local function ShowWindow()
	if session.other then
		return
	end
	session.windowShown, last.shown = true, true
	last.items = 0
	for _, e in ipairs(session.entries) do
		last.items = last.items + (e.kind ~= "none" and 1 or 0)
	end
	ns.LootWindow_Show({ entries = session.entries, title = session.title, place = true })
end

local function Redraw()
	if session and session.windowShown and ns.LootWindow_Shown() then
		ns.LootWindow_Draw()
	end
end

-- Fast loot: every slot that can be taken, each once (LOOT_SLOT_CHANGED allows another try). Not while another addon
-- owns the loot window: taking the slots before its window reads them leaves it empty (seen with Plumber's).
local function FastPass()
	if not (session and session.open and session.auto and db.fastLoot) or session.other then
		return
	end
	for slot, e in ipairs(session.entries) do
		if e.kind ~= "none" and not e.taken and not e.locked and not session.tried[slot] then
			session.tried[slot] = true
			LootSlot(slot)
		end
	end
end

-- Auto loot: what it couldn't take (bags full, a roll, locked loot) opens the window.
local function CheckStuck(id)
	if not (session and session.id == id and session.open) or session.windowShown then
		return
	end
	if ns.Loot_Remaining(session.entries) > 0 then
		session.stuck, last.stuck = true, true
		Reread()
		ShowWindow()
	end
end

-- Whether this loot's taken slots go to the feed: always with auto loot, by hand while that setting is on.
local function Feeds(s)
	return ns.Loot_FeedsTaken(s.auto, db.feedManual)
end

-- A taken slot becomes a feed line. Money comes from PLAYER_MONEY (the amount), junk as one line when the loot
-- closes. A currency always goes through Toasts.lua, so its currency event doesn't show it a second time (nor at all
-- while hand-looted items stay out of the feed).
local function FeedTaken(s, e)
	if e.kind == "currency" then
		ns.LootToasts_LootCurrency(e, Feeds(s))
		return
	end
	if e.kind == "money" or not Feeds(s) then
		return
	end
	if db.extras.foldJunk and ns.Loot_IsJunk(e) then
		s.junk[#s.junk + 1] = e
		return
	end
	ns.LootFeed_PushEntry(e)
end

local function FlushJunk(s)
	if #s.junk == 0 then
		return
	end
	for _, line in ipairs(ns.Loot_Lines(s.junk, { foldJunk = true })) do
		if line.junk then
			ns.LootFeed_PushJunk(line)
		else
			ns.LootFeed_PushEntry(line.entry)
		end
	end
	s.junk = {}
end

-- The sounds Blizzard's loot window plays when it opens (it doesn't open now).
local function OpenSound(isFromItem)
	if isFromItem then
		PlaySound(SOUNDKIT.UI_CONTAINER_ITEM_OPEN)
	elseif IsFishingLoot() then
		PlaySound(SOUNDKIT.FISHING_REEL_IN)
	end
end

-- Events ----------------------------------------------------------------------------------------------------------

-- Opens the window when looting by hand; with auto loot, waits to see what's stuck. Once per loot.
local function Display(isFromItem)
	session.displayed = true
	OpenSound(isFromItem)
	if session.auto then
		local id = session.id
		C_Timer.After(STUCK_DELAY, function()
			CheckStuck(id)
		end)
	else
		ShowWindow()
	end
end

-- Measured in game: with fast loot every slot is taken before LOOT_OPENED, which then finds the loot empty (or never
-- comes), so with auto-loot the window opens here, from the slots as they were before fast loot took them.
events:On(OWNER, "LOOT_READY", function(_, autoloot)
	TakeBlizzardWindow(true) -- before LootFrame's LOOT_OPENED, which follows this event
	if session and session.open then
		return -- the same loot again
	end
	NewSession(Payload(autoloot))
	Reread()
	FastPass()
	if session.auto and ns.Loot_Remaining(session.entries) > 0 then
		Display(false)
	end
end)

events:On(OWNER, "LOOT_OPENED", function(_, autoLoot, isFromItem)
	local fresh = not (session and session.open) -- LOOT_READY didn't come first, or its loot already closed
	local n = GetNumLootItems()
	if fresh then
		-- Fast loot emptied it and the loot closed before this came: nothing new, so the window keeps showing what
		-- LOOT_READY read.
		if ns.Loot_Remaining(ns.Loot_ReadAll(ns.Loot_ReadOptions(db))) == 0 then
			CloseLoot()
			return
		end
		NewSession(Payload(autoLoot))
	end
	Reread()
	if fresh then
		FastPass()
	end
	if session.displayed then
		-- It fires again after a failed loot (bags full): only refresh. Looting again here would flood the server.
		Redraw()
		return
	end
	if Readable(n) and n == 0 then
		CloseLoot()
		return
	end
	Display(Readable(isFromItem) and isFromItem)
end)

local function Taken(s, e)
	e.taken = true
	ns.LootToasts_Note(e)
	FeedTaken(s, e)
end

events:On(OWNER, "LOOT_SLOT_CLEARED", function(_, slot)
	local e = session and Readable(slot) and session.entries[slot]
	if not e or e.taken or e.kind == "none" then
		return
	end
	Taken(session, e)
	Redraw()
end)

-- Fast loot can empty a slot without LOOT_SLOT_CLEARED (the window closes first). While the game still answers for
-- this loot, a slot that's empty now was taken. (LootSlotHasItem is false for coin, so coin asks the slot's type.)
-- Once the game no longer answers, auto-loot closing the loot means it took what it could: everything not locked.
local function SweepTaken(s)
	local n = GetNumLootItems()
	if not (Readable(n) and type(n) == "number" and n > 0) then
		if s.auto and not s.stuck then
			for _, e in ipairs(s.entries) do
				if e.kind ~= "none" and not e.taken and not e.locked then
					Taken(s, e)
				end
			end
		end
		return
	end
	for slot, e in ipairs(s.entries) do
		if slot <= n and e.kind ~= "none" and not e.taken then
			local slotType = GetLootSlotType(slot)
			local hasItem = LootSlotHasItem(slot)
			if Readable(slotType, hasItem) and (slotType == Enum.LootSlotType.None
				or (e.kind ~= "money" and not hasItem)) then
				Taken(s, e)
			end
		end
	end
end

events:On(OWNER, "LOOT_SLOT_CHANGED", function(_, slot)
	if not (session and session.open and Readable(slot)) then
		return
	end
	local e = session.entries[slot]
	if e and e.taken then
		return
	end
	local new = ns.Loot_ReadSlot(slot, ns.Loot_ReadOptions(db))
	if new.kind == "none" and e and e.kind ~= "none" then
		return -- emptied by fast loot: keeps what it held (as in Reread)
	end
	session.entries[slot] = new
	session.tried[slot] = nil
	Redraw()
	if db.fastLoot and session.auto and session.retries < MAX_RETRIES then
		session.retries = session.retries + 1
		local id = session.id
		C_Timer.After(RETRY_DELAY, function()
			if session and session.id == id then
				FastPass()
			end
		end)
	end
end)

events:On(OWNER, "LOOT_CLOSED", function()
	local s = session
	if not (s and s.open) then
		return -- it often fires twice
	end
	s.open = false
	SweepTaken(s)
	FlushJunk(s)
	if s.windowShown then
		ns.LootWindow_Closed()
	end
	C_Timer.After(MONEY_GRACE, function()
		if session == s then
			session = nil
			for _, event in ipairs(SESSION_EVENTS) do
				events:Unwatch(OWNER, event)
			end
		end
	end)
end)

events:On(OWNER, "UI_ERROR_MESSAGE", function()
	if session and session.open and not session.windowShown then
		local id = session.id
		C_Timer.After(ERROR_DELAY, function()
			CheckStuck(id)
		end)
	end
end)

events:On(OWNER, "PLAYER_MONEY", function()
	if not session then
		return
	end
	local now = GetMoney()
	local delta = now - session.money
	session.money = now
	if delta > 0 and Feeds(session) then
		ns.LootFeed_PushMoney(delta)
	end
end)

local rereadSoon = UI.Debounce(INFO_DELAY, function()
	if session and session.open then
		Reread()
		Redraw()
	end
end)
events:On(OWNER, "GET_ITEM_INFO_RECEIVED", rereadSoon)

-- Take all ----------------------------------------------------------------------------------------------------------

function ns.Loot_TakeAll()
	if not (module.active and session and session.open) then
		return
	end
	for _, slot in ipairs(ns.Loot_Takeable(session.entries)) do
		LootSlot(slot)
	end
end

-- The key binding (Bindings.xml) works in combat too. Not through ns.Binding_Add: that one says "Loot is off" on
-- every press while the module is off, and this key may be one players press for other things.
ns.bindings.LOOT_TAKE_ALL = function()
	ns.Loot_TakeAll()
end
BINDING_NAME_TOMTE_LOOT_TAKE_ALL = "Take all loot"

-- The take-all key while looting (Window.lua) is off in combat: PLAYER_REGEN_DISABLED comes just before the lockdown.
events:On(OWNER, "PLAYER_REGEN_DISABLED", function()
	ns.LootWindow_UpdateKeys(true)
end)
events:On(OWNER, "PLAYER_REGEN_ENABLED", function()
	ns.LootWindow_UpdateKeys()
end)

-- Start and stop ------------------------------------------------------------------------------------------------------

local function Start()
	for _, event in ipairs(LOOT_EVENTS) do
		events:Watch(OWNER, event)
	end
	events:Watch(OWNER, "PLAYER_REGEN_DISABLED")
	events:Watch(OWNER, "PLAYER_REGEN_ENABLED")
	-- Blizzard's window open right now (Loot turned on while looting) keeps its events until the next loot.
	TakeBlizzardWindow(true)
	ns.LootToasts_Apply()
end

local function Stop()
	events:UnwatchAll(OWNER)
	local open = session and session.open
	session = nil
	ns.LootWindow_Hide()
	if open then
		CloseLoot() -- Blizzard's window missed this loot's LOOT_OPENED: end it rather than leave it unseen
	end
	ns.LootFeed_Clear()
	ns.LootToasts_Apply() -- module.active is false by now: gives the pop-ups and the banner back
	TakeBlizzardWindow(false)
end

local function Relayout()
	ns.LootWindow_Relayout()
	ns.LootFeed_Relayout()
end

local function ResetPosition()
	ns.LootWindow_ResetPosition()
	ns.LootFeed_ResetPosition()
end

local function Preview()
	ns.LootWindow_Preview()
	ns.LootFeed_Preview(false)
end

local function Why()
	if not last.look then
		ns.Print("Loot: nothing looted since you logged in.")
		return
	end
	local function onOff(v)
		return v and "on" or "off"
	end
	local said = last.payload == nil and "unreadable" or onOff(last.payload)
	local shown = last.shown and ("shown (%s) with %d items"):format(last.look, last.items) or "not shown"
	local feed = last.auto and "the feed (auto loot)" or (db.feedManual and "the window and the feed"
		or "the window only")
	ns.Print(("Loot: last loot: auto-loot %s (game said %s; setting %s, auto-loot key %s); fast loot %s; shown in %s; "
		.. "window %s%s%s."):format(onOff(last.auto), said, onOff(last.cvar), last.modifier and "held" or "not held",
		onOff(last.fast), feed, shown, last.stuck and "; something was left, so the window opened" or "",
		last.other and "; another addon (Plumber, ElvUI, XLoot ...) owns the loot window, so Tomte showed none and"
			.. " left the looting to it" or ""))
end

-- Settings --------------------------------------------------------------------------------------------------------

local function Pct(v)
	return ("%d%%"):format(math.floor(v * 100 + 0.5))
end

local function Seconds(v)
	return v .. " s"
end

-- Settings previews (Panel/Preview.lua): the sample window, or the sample feed lines.
local function WindowPreview(host, get)
	return ns.LootWindow_DrawSample(host, get)
end

local function FeedPreview(host, get)
	return ns.LootFeed_DrawSample(host, get)
end

local function KeyStatus()
	local key = GetBindingKey(BINDING)
	if key then
		return GetBindingText(key), "success"
	end
	return "Not bound", "textMuted"
end

module = ns.RegisterModule({
	key = "loot",
	name = "Loot",
	category = "gear",
	icon = 133639, -- inv_misc_bag_10
	summary = "Auto loot slides into a feed; looting by hand opens a loot window in the look you pick.",
	description = "Replaces the game's loot window. With auto loot, what you get slides in as lines beside your character and fades; a window only opens when something can't be looted by itself (full bags, rolls, locked loot). Looting by hand opens a loot window in one of three looks: Strips (feed lines that stay until you take them), Panel (a framed window with an upgrade shown large) or Tiles (big icons, like a bag). Fast loot, a Take all key, owned counts, new appearances, prices, and Blizzard's loot pop-ups shown in the feed too.",
	enabledByDefault = true,
	replaces = {
		{ addon = "Plumber", why = "the loot window, fast loot and the boss loot banner" },
		{ addon = "EnhanceQoL", why = "fast loot" },
	},
	conflicts = {
		{ addon = "Plumber", why = "with Plumber's loot window on too you get two loot windows. Turn one off." },
		{ addon = "Leatrix_Plus", why = "its faster auto loot loots every slot as well. Turn one off." },
		{ addon = "ElvUI", why = "with ElvUI's loot window on, Tomte shows no window of its own (fast loot still works)." },
		{ addon = "XLoot", why = "XLoot's window shows the loot, so Tomte shows none (fast loot still works)." },
	},
	defaults = {
		look = "strips", -- the loot window when looting by hand: "strips" | "panel" | "tiles" (Look*.lua)
		feedManual = true, -- what you take by hand from the window also goes to the feed
		fastLoot = true,
		lootKey = "E", -- takes all while a loot window is open, out of combat: "E" | "SPACE" | "F" | "off"
		popups = true, -- replace Blizzard's loot pop-ups with feed lines
		banner = "blizzard", -- boss loot banner: "blizzard" (unchanged) | "solo" (hidden while solo) | "valuable"
		extras = {
			foldJunk = true,
			owned = true,
			newLook = true,
			repCurrency = true,
			verdict = true,
			value = true,
			source = false, -- the corpse's name as the window's title
		},
		fontSize = 12,
		bgAlpha = 0.55, -- as Almost Done's
		perPage = 6,
		growUp = false,
		fadeDelay = 5, -- seconds a feed line stays before it fades
		atMouse = false,
		-- Where Edit Mode put the window: its left edge, top and bottom in UIParent's coordinates (from its
		-- bottom-left corner). set = false: the default spot (Window.lua).
		window = { set = false, x = 0, top = 0, bottom = 0 },
		feed = { point = "CENTER", relPoint = "CENTER", x = 160, y = -40 }, -- Feed.lua's ResetPosition repeats it
	},
	init = function(moduleDB)
		db = moduleDB
		ns.LootParts_Init(db)
		ns.LootWindow_Init(db, module)
		ns.LootFeed_Init(db, module)
		ns.LootToasts_Init(db, module)
	end,
	toggle = function(active)
		if active then
			Start()
		else
			Stop()
		end
	end,
	commands = {
		{ "test", "show a sample loot window and feed lines", Preview },
		{ "why", "explain the last loot: auto loot, fast loot, feed or window", Why },
	},
	options = {
		{ type = "header", label = "Loot window" },
		{ type = "dropdown", key = "look", label = "Look", onChange = Relayout, preview = WindowPreview,
			choices = function()
				return {
					{ value = "strips", text = "Strips" },
					{ value = "panel", text = "Panel" },
					{ value = "tiles", text = "Tiles" },
				}
			end,
			tooltip = "The window that opens when you loot by hand (auto loot uses the feed). Strips: lines like the feed's that stay until you take them. Panel: a framed window, an upgrade or something rare shown large, the rest in rows with their prices. Tiles: big icons in a grid, like a bag; point at one to see its name." },
		{ type = "checkbox", key = "feedManual", label = "Show hand-looted items in the feed",
			tooltip = "What you take from the loot window also slides into the feed, so you see it was looted. Auto loot always uses the feed." },
		{ type = "checkbox", key = "fastLoot", label = "Fast loot",
			tooltip = "With auto loot on, take everything the moment the loot opens. Follows the game's auto loot setting and its auto loot key (hold it to loot by hand). Whatever can't be taken stays in the window." },
		{ type = "dropdown", key = "lootKey", label = "Take all key while looting", choices = function()
			return {
				{ value = "E", text = "E" },
				{ value = "SPACE", text = "Space" },
				{ value = "F", text = "F" },
				{ value = "off", text = "Off" },
			}
		end, onChange = function()
			ns.LootWindow_UpdateKeys()
		end,
			tooltip = "While the loot window is open and you're out of combat, this key takes everything. Every other key works as usual, and the key does its own job again once the loot closes." },
		{ type = "status", label = "Take all key binding", status = KeyStatus,
			tooltip = "A key that takes all loot at any time, in combat too: Key Bindings > Tomte > Take all loot. The window's Take all button does the same." },
		{ type = "checkbox", key = "popups", label = "Replace loot pop-ups", onChange = ns.LootToasts_Apply,
			tooltip = "Boss loot, bonus rolls, containers and rolls you win show as feed lines instead of Blizzard's pop-ups." },
		{ type = "dropdown", key = "banner", label = "Boss loot banner", onChange = ns.LootToasts_Apply,
			choices = function()
				return {
					{ value = "blizzard", text = "Unchanged" },
					{ value = "solo", text = "Hide solo" },
					{ value = "valuable", text = "Valuable" },
				}
			end,
			tooltip = "The loot part of Blizzard's banner after a boss. Hide solo: not when you're on your own. Valuable: only mounts, pets, toys, legendaries and set tokens, as feed lines." },

		{ type = "header", label = "Extras" },
		{ type = "checkbox", key = "extras.foldJunk", label = "Fold junk into one line", onChange = Relayout,
			preview = WindowPreview },
		{ type = "checkbox", key = "extras.owned", label = "How many you own", onChange = Relayout,
			preview = WindowPreview, tooltip = "In your bags, bank and warband bank. Not shown for gear." },
		{ type = "checkbox", key = "extras.newLook", label = "New appearance tag", onChange = Relayout,
			preview = WindowPreview, tooltip = "Gear with an appearance you haven't collected and can collect." },
		{ type = "checkbox", key = "extras.verdict", label = "Gear Check verdict", onChange = Relayout,
			preview = WindowPreview, tooltip = "Whether gear is an upgrade for you. Needs Gear Check on." },
		{ type = "checkbox", key = "extras.value", label = "Auction value", onChange = Relayout,
			preview = WindowPreview, tooltip = "What the stack is worth, from Gold & value (auction or vendor price). Without Gold & value: the vendor price." },
		{ type = "checkbox", key = "extras.source", label = "Where it came from", onChange = Relayout,
			preview = WindowPreview, tooltip = "The corpse's or object's name as the loot window's title, instead of \"Loot\"." },
		{ type = "checkbox", key = "extras.repCurrency", label = "Reputation and currency lines",
			onChange = ns.LootToasts_Apply, preview = FeedPreview,
			tooltip = "Feed lines for reputation and currency you gain." },

		{ type = "header", label = "Look" },
		{ type = "slider", key = "fontSize", label = "Font size", min = 10, max = 18, step = 1, onChange = Relayout,
			preview = WindowPreview },
		{ type = "slider", key = "bgAlpha", label = "Background opacity", min = 0, max = 1, step = 0.05, format = Pct,
			onChange = Relayout, preview = WindowPreview },
		{ type = "slider", key = "perPage", label = "Items per page", min = 3, max = 12, step = 1, onChange = Relayout,
			preview = WindowPreview },
		{ type = "slider", key = "fadeDelay", label = "Fade after", min = 1, max = 15, step = 1, format = Seconds,
			onChange = Relayout,
			tooltip = "How long a feed line stays before it fades." },
		{ type = "checkbox", key = "growUp", label = "Grow upward", onChange = Relayout, preview = FeedPreview,
			tooltip = "The window and the feed grow up from where they are instead of down." },
		{ type = "checkbox", key = "atMouse", label = "Open at the mouse", onChange = Relayout,
			tooltip = "Off: the window opens where Blizzard's Edit Mode put it." },
		{ type = "button", label = "Position", text = "Reset", onClick = ResetPosition,
			tooltip = "Move the window and the feed back to their first spot. Blizzard's Edit Mode moves them too." },
		{ type = "button", label = "Sample", text = "Show", onClick = Preview,
			tooltip = "A sample window and feed lines, to see the look." },
	},
})
