local addonName, ns = ...

-- Crafting list tracker: the on-screen list of tracked crafts with the to-do for the character you're on. While it
-- shows, a craft or step that joins fades in and what it pushes down glides (ns.EditMode_Reflow), and its height
-- eases, folding included (ns.EditMode_Fold, both in Core/EditMode.lua). The to-do and its cache are in List.lua,
-- the rules in ListData.lua.

local UI = ns.UI
local WIDTH = 300
local TITLE_H = 22
local HEAD_H = 20
local LINE_H = 15
local MAX_LINES = 6 -- per craft in the tracker
local SHARED_LINES = 8 -- in the block of steps several crafts share
local FOOT_H = 14 -- the "more below" line under a capped tracker
local MAX_SHARE = 0.6 -- of the screen's height the tracker grows to before it scrolls
local SCROLL_STEP = 40 -- per mouse wheel notch
local FILL_SECONDS = 0.5 -- a craft's progress line easing to its new length
local DEFAULT_POINT = { "TOPRIGHT", "TOPRIGHT", -40, -260 }
local LINE_COLORS = {
	grab = "text", collect = "text", take = "text", mail = "text", deposit = "text", fetch = "text", missing = "danger",
	craft = "accent", ready = "success", wait = "textMuted", other = "textMuted",
}
-- The settings preview's crafts when nothing is tracked: to-dos as ListData.lua builds them, plus their own head
-- (sample: the recipe's name, the crafter and its class file), as made-up recipes and characters aren't saved.
local SAMPLE = {
	{ entry = { crafts = 3 }, needed = 4, inPlace = 2,
		sample = { name = "Flask of Alchemical Chaos", crafter = "Mira", class = "MAGE" },
		lines = {
			{ kind = "grab", mine = true, text = "Grab 10 Mycobloom from bank" },
			{ kind = "mail", mine = true, text = "Mail 20 Luredrop to Mira" },
			{ kind = "wait", text = "Mira crafts Flask of Alchemical Chaos" },
		} },
	{ entry = { crafts = 1 }, needed = 1, inPlace = 1,
		sample = { name = "Charged Runeaxe", crafter = "Aldric", class = "PALADIN" },
		lines = {
			{ kind = "ready", mine = true, text = "Ready: craft Charged Runeaxe" },
		} },
}

local PARTIAL_NOTE = ns.ALTS_PARTIAL_NOTE

local db
local frame
local inCombat = false
local toggled = {} -- [list entry] = true (opened) | false (folded) by a click, for this session

local events = ns.Alts_Events
local RecipeName = ns.Alts_RecipeName -- Labels.lua

-- Tracker -------------------------------------------------------------------------------------------------------

local function SavePoint()
	db.tracker.point = UI.TopLeftPoint(frame)
end

local function Place()
	local p = db.tracker.point or DEFAULT_POINT
	frame:ClearAllPoints()
	frame:SetPoint(p[1], UIParent, p[2], p[3], p[4])
end

local SEARCHABLE = { grab = true, take = true, collect = true, fetch = true, mail = true, deposit = true }

-- Where a click on a material line finds it: Tomte's bags, else Baganator's, else nil.
local function SearchTarget()
	if ns.Bags_Active and ns.Bags_Active() then
		return "your bags"
	elseif SlashCmdList and SlashCmdList["Baganator"] and db.listBaganator then
		return "Baganator"
	end
	return nil
end

-- Tomte's bags (Modules/Bags) search for it by name, and its bank too while it's open. Baganator has no search API;
-- its slash command is the public way in ("/bgr search <text>", lower case). It opens the bags too, and an open bank
-- view highlights the matches.
function ns.AltsList_Search(itemID)
	local name = itemID and C_Item.GetItemNameByID(itemID)
	local target = SearchTarget()
	if not (name and target) then
		return false
	end
	if target == "your bags" then
		ns.BagsWindow_Find(name)
		return true
	end
	local ok = pcall(SlashCmdList["Baganator"], "search " .. name:lower())
	return ok
end

local function LineTooltip(owner, line)
	if not line.itemID then
		return
	end
	GameTooltip:SetOwner(owner, "ANCHOR_LEFT")
	GameTooltip:SetItemByID(line.itemID)
	local target = SEARCHABLE[line.kind] and SearchTarget()
	if target then
		GameTooltip:AddLine(" ")
		local r, g, b = UI.Color("accent")
		GameTooltip:AddLine("Click: find it in " .. target, r, g, b)
	end
	GameTooltip:Show()
end

local function OpenList()
	ns.Panel_OpenPage("alts")
	ns.Alts_ShowTab("list")
end

local function Block(f, i)
	local b = f.blocks[i]
	if b then
		return b
	end
	b = CreateFrame("Button", nil, f.content)
	b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	b.title = UI.Text(b, 13, "heading")
	b.title:SetPoint("TOPLEFT", 0, 0)
	b.title:SetPoint("RIGHT", -50, 0)
	b.title:SetWordWrap(false)
	b.crafter = UI.Text(b, 11, "textMuted")
	b.crafter:SetPoint("TOPRIGHT", 0, -1)
	b.crafter:SetJustifyH("RIGHT")
	b.track = b:CreateTexture(nil, "ARTWORK")
	b.track:SetColorTexture(1, 1, 1, 0.08)
	b.track:SetHeight(2)
	b.track:SetPoint("TOPLEFT", 0, -16)
	b.track:SetPoint("RIGHT")
	b.fill = b:CreateTexture(nil, "OVERLAY")
	b.fill:SetColorTexture(UI.RGBA("accent", 0.8))
	b.fill:SetHeight(2)
	b.fill:SetPoint("TOPLEFT", b.track, "TOPLEFT")
	b.lines = {}
	b:SetScript("OnClick", function(self, button)
		if button == "RightButton" then
			local todo = self.todo
			local entry = todo and todo.entry
			if entry then
				UI.ContextMenu(self, function(_, root)
					ns.AltsListTab_CrafterChoices(root, todo) -- ListTab.lua, loaded after this file
					root:CreateButton("Open the crafting list", OpenList)
					root:CreateButton("Remove from the list", function()
						ns.AltsList_Remove(entry.recipeID)
						ns.Print(("removed %s from the crafting list."):format(RecipeName(entry.recipeID)))
					end)
				end)
			end
		elseif self.foldable and self.todo and self.todo.entry then
			toggled[self.todo.entry] = not self.open
			ns.AltsList_Refresh()
		else
			OpenList()
		end
	end)
	b:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		local r, g, b = UI.Color("textMuted")
		if self.shared then
			GameTooltip:SetText("For several crafts", 1, 1, 1)
			GameTooltip:AddLine("Steps more than one craft below needs, added up. Click: the crafting list.", r, g, b, true)
		else
			GameTooltip:SetText(self.todo and RecipeName(self.todo.entry.recipeID) or "?", 1, 1, 1)
			local click = not self.foldable and "Click: the crafting list."
				or self.open and "Click: fold its steps away." or "Click: show its steps."
			GameTooltip:AddLine(click .. " Right-click: who crafts it, or remove it.", r, g, b, true)
		end
		GameTooltip:Show()
	end)
	b:SetScript("OnLeave", function()
		GameTooltip:Hide()
	end)
	f.blocks[i] = b
	return b
end

local function Line(b, i)
	local l = b.lines[i]
	if not l then
		l = CreateFrame("Frame", nil, b)
		l:SetHeight(LINE_H)
		l:EnableMouse(true)
		l.text = UI.Text(l, 11, "text")
		l.text:SetPoint("TOPLEFT", 8, -1)
		l.text:SetWidth(WIDTH - 28) -- fixed, so the wrapped height is known right after SetText
		l.text:SetJustifyH("LEFT")
		l.text:SetWordWrap(true)
		l.text:SetMaxLines(2) -- a long line wraps once instead of being cut off
		l:SetScript("OnEnter", function(self)
			LineTooltip(self, self.line)
		end)
		l:SetScript("OnLeave", function()
			GameTooltip:Hide()
		end)
		l:SetScript("OnMouseUp", function(self, button)
			local line = self.line
			if button == "LeftButton" and line and SEARCHABLE[line.kind] then
				if not InCombatLockdown() then
					ns.AltsList_Search(line.itemID)
				end
			elseif button == "LeftButton" or button == "RightButton" then
				b:Click(button) -- the line takes the mouse: the craft's own click (open the list, right-click remove)
			end
		end)
		b.lines[i] = l
	end
	l:Show()
	return l
end

-- The tracker's look on f: the panel, the title and the note (crafts go in f.blocks). Shared by the real tracker and
-- the settings preview.
local function Dress(f)
	f:SetSize(WIDTH, 60)
	UI.Panel(f, { alpha = 0.55, subtle = true })
	f.title = UI.Text(f, 10, "textMuted")
	f.title:SetPoint("TOPLEFT", 10, -6)
	f.title:SetText(ns.Spaced and ns.Spaced("Crafting list") or "CRAFTING LIST")
	-- The crafts sit on content, inside view under the title: a tracker taller than its cap (f.cap) scrolls content.
	f.view = CreateFrame("Frame", nil, f)
	f.view:SetClipsChildren(true)
	f.content = CreateFrame("Frame", nil, f.view)
	f.content:SetWidth(WIDTH)
	f.scroll = 0
	f.note = UI.Text(f.content, 10, "textMuted")
	f.note:SetWidth(WIDTH - 20)
	f.note:SetJustifyH("LEFT")
	f.note:SetWordWrap(true)
	f.footer = UI.Text(f, 10, "textMuted")
	f.footer:SetPoint("BOTTOMLEFT", 10, 4)
	f.footer:Hide()
	f.blocks = {}
end

-- Scrolls a capped tracker to f.scroll (kept in range) and says what's below.
local function Scrolled(f)
	local hidden = (f.contentH or 0) - (f.viewH or 0)
	f.scroll = math.max(0, math.min(f.scroll, math.max(hidden, 0)))
	f.content:ClearAllPoints()
	f.content:SetPoint("TOPLEFT", f.view, "TOPLEFT", 0, f.scroll)
	if hidden <= 0 then
		f.footer:Hide()
		return
	end
	local bottom, below = f.scroll + f.viewH, 0
	for _, b in ipairs(f.blocks) do
		if b:IsShown() and b.y >= bottom then
			below = below + 1
		end
	end
	local text = below > 0 and ("%d more below"):format(below) or (f.scroll < hidden and "More below" or "")
	f.footer:SetText(text)
	f.footer:Show()
end

local function OnWheel(view, delta)
	local f = view:GetParent()
	f.scroll = f.scroll - delta * SCROLL_STEP
	Scrolled(f)
end

-- A craft's title line and its crafter (name and class file, nil when nobody). The preview's sample crafts carry
-- their own (t.sample), as their recipes and characters aren't in the saved data.
local function CraftHead(t)
	if t.friend then
		return t.title, nil, nil -- a friend's request (Friends.lua): who it's for is in the title
	end
	local s = t.sample
	local label, crafter, class
	if s then
		label, crafter, class = s.name, s.crafter, s.class
	else
		label = ns.Alts_RecipeLabel(t.entry.recipeID, 15, t.entry.quality)
		local c = t.crafter and ns.altsDB.chars[t.crafter]
		crafter, class = c and c.name, c and c.class
	end
	return ("%s  %s"):format(label, UI.Wrap("x" .. t.entry.crafts, "textMuted")), crafter, class
end

-- A step line's key within its craft, to follow it across redraws: its kind and item or recipe (not its text, whose
-- counts change as things move), numbered when the same comes twice.
local function LineKey(line, seen)
	local key = ("%s:%s"):format(line.kind or "", tostring(line.itemID or line.recipeID or ""))
	seen[key] = (seen[key] or 0) + 1
	return key .. "#" .. seen[key]
end

-- Names in the shared steps, drawn like the to-do's own (List.lua's AltsList_Todos).
local SHARED_TEXT = {
	itemName = function(itemID, noRank)
		return ns.Alts_ItemLabel(itemID, 13, noRank)
	end,
	recipeName = function(recipeID, quality)
		return ns.Alts_RecipeLabel(recipeID, nil, quality)
	end,
	gold = function(copper)
		return ns.Alts_Price(copper)
	end,
}

-- Step lines on block b from line y down, at most max of them and then "+ n more". Returns the new y and how many
-- line frames show.
local function StepLines(b, lines, max, ly)
	local shown = 0
	local keys = {}
	for _, line in ipairs(lines) do
		if shown >= max then
			break
		end
		shown = shown + 1
		local l = Line(b, shown)
		l.line = line
		l.key, l.y = LineKey(line, keys), ly
		l:ClearAllPoints()
		l:SetPoint("TOPLEFT", 0, -ly)
		l:SetPoint("RIGHT")
		l.text:SetText(line.text)
		UI.SetTextRole(l.text, line.mine and (LINE_COLORS[line.kind] or "text") or "textMuted")
		local h = math.max(LINE_H, math.ceil(l.text:GetStringHeight()) + 3)
		l:SetHeight(h)
		ly = ly + h
	end
	if #lines > max then
		shown = shown + 1
		local l = Line(b, shown)
		l.line = {}
		l.key, l.y = "more", ly
		l:ClearAllPoints()
		l:SetPoint("TOPLEFT", 0, -ly)
		l:SetPoint("RIGHT")
		l.text:SetText(("+ %d more (the List tab has them all)"):format(#lines - max))
		UI.SetTextRole(l.text, "textMuted")
		l:SetHeight(LINE_H)
		ly = ly + LINE_H
	end
	for j = shown + 1, #b.lines do
		b.lines[j]:Hide()
	end
	b.shownLines = shown
	return ly
end

-- The block of steps several crafts share (Alts_TrackerShared), above the crafts.
local function SharedBlock(b, shared)
	b.todo, b.shared, b.foldable, b.open = nil, true, false, true
	b.title:SetText(UI.Wrap("For several crafts", "textMuted"))
	b.crafter:SetText("")
	b.track:Hide()
	b.fill:Hide()
	return StepLines(b, shared, SHARED_LINES, HEAD_H)
end

-- One craft: its title, crafter and progress, and its own steps while open. A folded craft with steps says so with a
-- "+" in front of its title.
local function CraftBlock(b, t, lines, open)
	b.todo, b.shared = t, false
	b.foldable, b.open = #lines > 0, open
	local title, crafter, class = CraftHead(t)
	b.title:SetText((b.foldable and not open and UI.Wrap("+ ", "textMuted") or "") .. title)
	local color = class and C_ClassColor.GetClassColor(class)
	b.crafter:SetText(crafter or (t.friend and "" or "nobody"))
	if color then
		b.crafter:SetTextColor(color.r, color.g, color.b)
	else
		UI.SetTextRole(b.crafter, "textMuted")
	end
	b.track:Show()
	b.fill:Show()
	-- The same craft's progress eases to its new length while the tracker shows; a block now showing another craft
	-- jumps.
	local width = math.max((WIDTH - 20) * ns.Alts_CraftProgress(t), 1)
	local fill = b.fill
	if b.fillOf == t.entry and b:IsVisible() and math.abs(fill:GetWidth() - width) >= 1 then
		local from = fill:GetWidth()
		UI.Tween(fill, "width", FILL_SECONDS, function(p)
			fill:SetWidth(UI.Lerp(from, width, p))
		end)
	else
		UI.TweenStop(fill, "width")
		fill:SetWidth(width)
	end
	b.fillOf = t.entry
	return StepLines(b, open and lines or {}, MAX_LINES, HEAD_H)
end

-- Lays the crafts out on f (built by Dress) and sizes it: the steps several crafts share first, then each craft with
-- its own steps, folded on a long list (Alts_TrackerOpen). Taller than f.cap (the real tracker; the settings preview
-- has none), it stops there and the mouse wheel scrolls. Each block and step line gets .key and .y for
-- ns.EditMode_Reflow.
local function Fill(f, todos)
	local blocks = f.blocks
	local shared, rest = ns.Alts_TrackerShared(todos, SHARED_TEXT)
	local open = ns.Alts_TrackerOpen(todos, rest, toggled)
	local y, n = 0, 0
	local function Put(b, key, height)
		b.key, b.y = key, y
		b:SetHeight(height)
		b:Show()
		y = y + height + 8
	end
	local function Next()
		n = n + 1
		local b = Block(f, n)
		b:ClearAllPoints()
		b:SetPoint("TOPLEFT", 10, -y)
		b:SetPoint("RIGHT", -10, 0)
		return b
	end
	if #shared > 0 then
		local b = Next()
		Put(b, "shared", SharedBlock(b, shared))
	end
	for i, t in ipairs(todos) do
		local b = Next()
		Put(b, t.entry or t, CraftBlock(b, t, rest[i], open[i]))
	end
	for i = n + 1, #blocks do
		blocks[i]:Hide()
	end
	f.shownBlocks = n
	if #todos == 0 then
		y = y + 18
	end
	-- "Get" lines without Syndicator may be on another character.
	if ns.AltsList_PartialCounts(todos) then
		f.note:ClearAllPoints()
		f.note:SetPoint("TOPLEFT", 10, -y)
		f.note:SetText(PARTIAL_NOTE)
		f.note:Show()
		y = y + math.ceil(f.note:GetStringHeight()) + 6
	else
		f.note:Hide()
	end
	f.contentH = y
	f.content:SetHeight(math.max(y, 1))
	local capped = f.cap and y > f.cap
	f.viewH = capped and f.cap or y
	f.view:ClearAllPoints()
	f.view:SetPoint("TOPLEFT", 0, -TITLE_H)
	f.view:SetPoint("BOTTOMRIGHT", 0, capped and FOOT_H + 4 or 4)
	f.view:EnableMouseWheel(capped and true or false)
	f.view:SetScript("OnMouseWheel", capped and OnWheel or nil)
	f:SetHeight(TITLE_H + f.viewH + (capped and FOOT_H or 0) + 4)
	Scrolled(f)
end

local Draw

local function Build()
	frame = CreateFrame("Frame", nil, UIParent)
	frame:SetFrameStrata("MEDIUM")
	frame:SetClampedToScreen(true)
	frame:SetMovable(true)
	frame:Hide()
	Dress(frame)
	local mover = CreateFrame("Frame", nil, frame)
	mover:SetAllPoints()
	mover:SetFrameLevel(frame:GetFrameLevel() + 10)
	mover:EnableMouse(true)
	mover:RegisterForDrag("LeftButton")
	mover:SetScript("OnDragStart", function()
		frame:StartMoving()
	end)
	mover:SetScript("OnDragStop", function()
		frame:StopMovingOrSizing()
		SavePoint()
	end)
	UI.Border(mover, "accent", 0.8)
	local hint = UI.Text(mover, 10, "accent")
	hint:SetPoint("TOPRIGHT", -26, -6) -- left of the collapse button
	hint:SetText("drag to move")
	frame.mover = mover
	frame.collapse = UI.CollapseButton(frame, function()
		return db.tracker.collapsed
	end, function()
		db.tracker.collapsed = not db.tracker.collapsed
		Draw(true)
	end)
end

-- The checks that don't need the to-do, so a hidden tracker never works it out.
local function MayShow()
	if not (ns.altsModule and ns.altsModule.active and db.tracker.shown) then
		return false
	end
	return not (db.tracker.hideInCombat and inCombat)
end

local function WantShown(todos)
	if not db.tracker.locked or ns.EditMode_Active() then
		return true
	end
	if #todos == 0 then
		return false
	end
	if db.tracker.mode == "crafter" then
		local me = UnitGUID("player")
		for _, t in ipairs(todos) do
			if t.crafter == me then
				return true
			end
		end
		return false
	end
	return true
end

-- The tracker's crafts and note, top down: what a fold fades.
local function FoldRegions()
	local list = {}
	for i, b in ipairs(frame.blocks) do
		list[i] = b
	end
	list[#list + 1] = frame.note
	return list
end

-- After a draw that shows the crafts: crafts and step lines that joined since the last one fade in and what moved
-- glides (only when the tracker showed them before too).
local function Reflow(live)
	local before = live and frame.spots
	local lineSpots = {}
	frame.spots = ns.EditMode_Reflow(frame.blocks, frame.shownBlocks, before or nil)
	for i = 1, frame.shownBlocks do
		local b = frame.blocks[i]
		lineSpots[b.key] = ns.EditMode_Reflow(b.lines, b.shownLines,
			before and before[b.key] ~= nil and frame.lineSpots and frame.lineSpots[b.key] or nil)
	end
	frame.lineSpots = lineSpots
end

-- fold: the minus was clicked (what folds away fades); any other draw only eases the height.
function Draw(fold)
	if not db then
		return
	end
	local todos = MayShow() and ns.AltsFriends_TrackerList() -- crafts, then mail steps for friends
	if not (todos and WantShown(todos)) then
		if frame then
			frame:Hide()
		end
		return
	end
	if not frame then
		Build()
		Place()
	end
	local before = ns.EditMode_FoldStart(frame, FoldRegions())
	local scale = db.tracker.scale or 1
	frame:SetScale(scale)
	-- The most the crafts take before they scroll, in the tracker's own units.
	frame.cap = math.floor(UIParent:GetHeight() * MAX_SHARE / scale) - TITLE_H - FOOT_H - 4
	frame.mover:SetShown(not db.tracker.locked and not ns.EditMode_Active())
	local collapsed = db.tracker.collapsed
	if collapsed then
		for _, b in ipairs(frame.blocks) do
			b:Hide()
		end
		frame.note:Hide()
		frame.footer:Hide()
		frame.view:EnableMouseWheel(false)
		frame:SetHeight(TITLE_H)
	else
		Fill(frame, todos)
	end
	ns.EditMode_FoldKeep(frame)
	frame:Show()
	ns.EditMode_Fold(frame, before, fold and FoldRegions() or {})
	if collapsed or not frame:IsVisible() then
		frame.spots, frame.lineSpots = nil, nil
	else
		Reflow(before.visible and not fold)
	end
end

function ns.AltsList_Refresh()
	Draw(false)
end

-- The settings preview (Panel/Preview.lua): the tracker with this character's to-do, or SAMPLE when nothing is
-- tracked, at the scale under the mouse. Drawn by Dress and Fill like the real one.
function ns.AltsList_DrawSample(host, get)
	local f = host.tracker
	if not f then
		f = CreateFrame("Frame", nil, host)
		f:SetPoint("TOPLEFT")
		Dress(f)
		host.tracker = f
	end
	local todos = ns.AltsList_Todos()
	Fill(f, #todos > 0 and todos or SAMPLE)
	local scale = get("tracker.scale") or 1
	f:SetScale(scale)
	return f:GetWidth() * scale, f:GetHeight() * scale
end

ns.EditMode_Register({
	name = "Crafting list",
	frame = function()
		return frame
	end,
	refresh = function()
		ns.AltsList_Refresh()
	end,
	saved = SavePoint,
	module = "alts",
	options = { "tracker.mode", "tracker.scale", "tracker.hideInCombat" },
	reset = function()
		ns.AltsList_ResetPosition()
	end,
})

function ns.AltsList_ResetPosition()
	db.tracker.point = nil
	if frame then
		Place()
	end
end

-- Events ----------------------------------------------------------------------------------------------------------

events:On("list", "PLAYER_REGEN_DISABLED", function()
	inCombat = true
	ns.AltsList_Refresh()
end)

events:On("list", "PLAYER_REGEN_ENABLED", function()
	inCombat = false
	ns.AltsList_Refresh()
end)

-- Watched with the crafting list's other events (owner "list", List.lua's AltsList_Start).
function ns.AltsTracker_Start(moduleDB)
	db = moduleDB
end

function ns.AltsTracker_Stop()
	if frame then
		frame:Hide()
	end
end
