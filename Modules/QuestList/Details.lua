local addonName, ns = ...

-- Quest list: a quest's details in Tomte's own window. What to do comes first (a checklist with counts and bars),
-- then the quest's text, then the rewards as tiles with Gear Check's pick among the choices; Spoken's Play button sits
-- in the header. Not Blizzard's quest details window: that one is a UI panel, and showing it from addon code taints the
-- panel manager, so the map opened next with M is tainted too (QuestList.lua's menu says more). Everything here is
-- read by quest ID; nothing of Blizzard's is selected, shown or changed. Rules (difficulty, progress) in Data.lua;
-- opened from the quest menu (QuestList.lua).

local WIDTH = 440
local MIN_H, MAX_H = 240, 600 -- the window grows to its content between these
local PAD = 16
local HEAD_ICON = 30 -- the quest's state icon in the header
local PLAY_SIZE = 22 -- Spoken's Play button in the header
local GAP = 14 -- between blocks
local CHECK = 14 -- an objective's box
local OBJ_PAD = 10 -- inside the checklist
local OBJ_GAP = 7
local BAR_H = 4
local TILE_H = 50
local TILE_ICON = 34
local TILE_GAP = 6
local TEXT_SPACING = 3 -- extra line spacing in the quest's text
local FOOT_H = 44
local HEADER_H = 58
local REFRESH_DELAY = 0.2 -- seconds: item and quest data arrive in bursts
local XP_BADGE_W, XP_BADGE_H = 22, 13
-- Gear Check's headline colors (Gear/Rules.lua's color keys) to theme roles, as on the reward card.
local COLOR_ROLES = { green = "success", yellow = "warning", grey = "textMuted", red = "danger", orange = "warning" }
local COIN_ICONS = {
	gold = "%s|TInterface\\MoneyFrame\\UI-GoldIcon:0:0:2:0|t",
	silver = "%s|TInterface\\MoneyFrame\\UI-SilverIcon:0:0:2:0|t",
	copper = "%s|TInterface\\MoneyFrame\\UI-CopperIcon:0:0:2:0|t",
}
local ICON_READY = "Interface\\GossipFrame\\ActiveQuestIcon" -- the yellow ? of a quest to hand in
local ICON_OPEN = "Interface\\GossipFrame\\IncompleteQuestIcon" -- the grey ? of one in progress
local ICON_CHECK = "Interface\\RaidFrame\\ReadyCheck-Ready"
local ICON_UNKNOWN = 134400 -- inv_misc_questionmark
local OFF_HAND_ONLY = { INVTYPE_WEAPONOFFHAND = true, INVTYPE_SHIELD = true, INVTYPE_HOLDABLE = true }

local UI = ns.UI
local events = ns.QuestList_Events
local OWNER = "details"

local win
local questID -- the quest shown
local pools = { text = {}, obj = {}, tile = {} } -- pooled pieces of the scroll content
local used

-- Reading -----------------------------------------------------------------------------------------------------------

-- Gear Check's verdicts for the choices, and which one it picks now or for later (Gear/Rewards.lua), when it's on.
local function JudgeChoices(choices)
	local ctx = ns.gearModule and ns.gearModule.active and ns.Gear_Context and ns.Gear_Context()
	if not ctx then
		return
	end
	for _, c in ipairs(choices) do
		if c.link then
			c.verdict = ns.Gear_Verdict(c.link, ctx)
			c.later = c.verdict and ns.GearForever_LaterText and ns.GearForever_LaterText(c.link, c.verdict)
			local _, _, _, equipLoc = C_Item.GetItemInfoInstant(c.link)
			c.offHandOnly = OFF_HAND_ONLY[equipLoc] or false
		end
	end
	local best = ns.GearRewards_Pick(choices)
	if best then
		choices[best].tag = "Best for you"
	else
		local later, text = ns.GearRewards_PickLater(choices, nil)
		if later then
			choices[later].tag = "For later"
			choices[later].tagText = text
		end
	end
end

local function Item(kind, i, name, texture, count, quality)
	local link = GetQuestLogItemLink(kind, i, questID)
	local sell = link and select(11, C_Item.GetItemInfo(link))
	return { link = link, name = name, texture = texture, count = count, quality = quality, sell = sell }
end

-- Everything the window shows: { title, level, complete, text, objectivesText, objectives, choices, items, spells,
-- xp, money }.
local function Read()
	local logIndex = C_QuestLog.GetLogIndexForQuestID(questID)
	if not logIndex then
		return nil
	end
	local info = C_QuestLog.GetInfo(logIndex) or {}
	local d = { title = info.title or C_QuestLog.GetTitleForQuestID(questID), level = info.level }
	d.complete = C_QuestLog.ReadyForTurnIn and C_QuestLog.ReadyForTurnIn(questID)
		or C_QuestLog.IsComplete(questID) or false
	d.text, d.objectivesText = GetQuestLogQuestText(logIndex)
	d.objectives = ns.QuestListRead_Objectives(questID)
	d.choices, d.items, d.spells = {}, {}, {}
	for i = 1, GetNumQuestLogChoices(questID) or 0 do
		local name, texture, count, quality = GetQuestLogChoiceInfo(i, questID)
		d.choices[#d.choices + 1] = Item("choice", i, name, texture, count, quality)
	end
	for i = 1, GetNumQuestLogRewards(questID) or 0 do
		local name, texture, count, quality = GetQuestLogRewardInfo(i, questID)
		d.items[#d.items + 1] = Item("reward", i, name, texture, count, quality)
	end
	local spellIDs = C_QuestInfoSystem and C_QuestInfoSystem.GetQuestRewardSpells
		and C_QuestInfoSystem.GetQuestRewardSpells(questID) or {}
	for _, spellID in ipairs(spellIDs) do
		local spell = C_Spell.GetSpellInfo(spellID)
		if spell then
			d.spells[#d.spells + 1] = { spellID = spellID, name = spell.name, texture = spell.iconID }
		end
	end
	d.xp = GetQuestLogRewardXP(questID)
	d.money = GetQuestLogRewardMoney(questID)
	if #d.choices > 1 then
		JudgeChoices(d.choices)
	end
	return d
end

-- Pieces --------------------------------------------------------------------------------------------------------------

local function Take(pool, make)
	used[pool] = (used[pool] or 0) + 1
	local piece = pool[used[pool]]
	if not piece then
		piece = make()
		pool[used[pool]] = piece
	end
	piece:Show()
	return piece
end

local function HideUnused()
	for _, pool in pairs(pools) do
		for i = (used[pool] or 0) + 1, #pool do
			pool[i]:Hide()
		end
	end
end

-- A wrapped text at x, y (from the content's top), `width` wide; returns the y below it.
local function Text(content, x, y, width, text, role, size, fontRole, spacing)
	local fs = Take(pools.text, function()
		local t = UI.Text(content, 12, "text", "body")
		t:SetJustifyH("LEFT")
		t:SetWordWrap(true)
		return t
	end)
	UI.SetFont(fs, fontRole or "body", size or 12)
	UI.SetTextRole(fs, role or "text")
	fs:SetSpacing(spacing or 0)
	fs:ClearAllPoints()
	fs:SetPoint("TOPLEFT", x, -y)
	fs:SetWidth(width)
	fs:SetText(text)
	return y + fs:GetStringHeight()
end

-- A block's name: sentence case in the title font, the theme's heading color.
local function Heading(content, y, width, text)
	return Text(content, 0, y, width, text, "heading", 13, "title") + 6
end

-- The checklist ---------------------------------------------------------------------------------------------------

local function MakeObjective(content)
	local o = CreateFrame("Frame", nil, content)
	o.box = CreateFrame("Frame", nil, o)
	o.box:SetSize(CHECK, CHECK)
	o.box:SetPoint("TOPLEFT", 0, -1)
	o.boxFill = o.box:CreateTexture(nil, "BACKGROUND")
	o.boxFill:SetAllPoints()
	UI.Border(o.box, "frame", 0.8)
	o.check = o.box:CreateTexture(nil, "OVERLAY")
	o.check:SetTexture(ICON_CHECK)
	o.check:SetPoint("CENTER", 1, 1)
	o.check:SetSize(CHECK + 4, CHECK + 4)
	o.label = UI.Text(o, 12, "text", "body")
	o.label:SetJustifyH("LEFT")
	o.label:SetWordWrap(true)
	o.label:SetPoint("TOPLEFT", o.box, "TOPRIGHT", 8, 0)
	o.count = UI.Text(o, 12, "text", "number")
	o.count:SetJustifyH("RIGHT")
	o.count:SetPoint("TOPRIGHT", 0, -1)
	o.bar = UI.Bar(o, BAR_H)
	o.bar:SetPoint("LEFT", o.label, "LEFT")
	o.bar:SetPoint("RIGHT", 0, 0)
	return o
end

-- One objective at y inside the checklist (x: its left inset, width: what's left); returns the y below it.
local function Objective(box, y, x, width, obj)
	local o = Take(pools.obj, function()
		return MakeObjective(box)
	end)
	o:SetParent(box)
	o:ClearAllPoints()
	o:SetPoint("TOPLEFT", x, -y)
	o:SetWidth(width)
	local done = obj.finished
	o.boxFill:SetColorTexture(UI.RGBA(done and "success" or "bg", done and 0.25 or 0.6))
	o.check:SetShown(done)
	UI.SetTextRole(o.label, done and "textMuted" or "text")
	o.label:SetText(obj.label)
	local counted = obj.need and obj.need > 1
	o.count:SetText(counted and ("%d/%d"):format(obj.have or 0, obj.need) or "")
	UI.SetTextRole(o.count, done and "success" or "heading")
	o.label:SetPoint("RIGHT", o.count, "LEFT", -8, 0)
	local h = math.max(o.label:GetStringHeight(), CHECK)
	if counted then
		o.bar:ClearAllPoints()
		o.bar:SetPoint("TOPLEFT", o.label, "BOTTOMLEFT", 0, -5)
		o.bar:SetPoint("RIGHT", 0, 0)
		o.bar:SetColorRole(done and "success" or nil)
		o.bar:SetValue(ns.QuestList_ObjectiveShare(obj) or 0)
		o.bar:Show()
		h = o.label:GetStringHeight() + 5 + BAR_H
	else
		o.bar:Hide()
	end
	o:SetHeight(h)
	return y + h
end

-- Rewards -------------------------------------------------------------------------------------------------------------

local function TileEnter(tile)
	local e = tile.entry
	if not e then
		return
	end
	GameTooltip:SetOwner(tile, "ANCHOR_RIGHT")
	if e.link then
		GameTooltip:SetHyperlink(e.link)
	elseif e.spellID then
		GameTooltip:SetSpellByID(e.spellID)
	end
	GameTooltip:Show()
end

local function MakeTile(content)
	local t = CreateFrame("Button", nil, content)
	t:SetHeight(TILE_H)
	UI.Surface(t, 0.3)
	t.pick = t:CreateTexture(nil, "BORDER")
	t.pick:SetPoint("TOPLEFT")
	t.pick:SetPoint("BOTTOMLEFT")
	t.pick:SetWidth(3)
	t.icon = t:CreateTexture(nil, "ARTWORK")
	t.icon:SetSize(TILE_ICON, TILE_ICON)
	t.icon:SetPoint("LEFT", 8, 0)
	t.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	-- The item's quality on the icon's edge (four 1px lines in the quality color).
	t.ring = CreateFrame("Frame", nil, t)
	t.ring:SetPoint("TOPLEFT", t.icon, -1, 1)
	t.ring:SetPoint("BOTTOMRIGHT", t.icon, 1, -1)
	UI.Border(t.ring, "frame", 1)
	t.count = UI.Text(t, 11, "text", "number")
	t.count:SetPoint("BOTTOMRIGHT", t.icon, "BOTTOMRIGHT", -1, 2)
	t.name = UI.Text(t, 12, "text", "body")
	t.name:SetPoint("TOPLEFT", t.icon, "TOPRIGHT", 8, -1)
	t.name:SetPoint("RIGHT", -8, 0)
	t.name:SetJustifyH("LEFT")
	t.name:SetWordWrap(false)
	t.sub = UI.Text(t, 11, "textMuted")
	t.sub:SetPoint("BOTTOMLEFT", t.icon, "BOTTOMRIGHT", 8, 1)
	t.sub:SetPoint("RIGHT", -8, 0)
	t.sub:SetJustifyH("LEFT")
	t.sub:SetWordWrap(false)
	t:SetScript("OnEnter", TileEnter)
	t:SetScript("OnLeave", GameTooltip_Hide)
	-- Shift-click links it in chat. No Ctrl-click try-on: the dressing room is a UI panel too.
	t:SetScript("OnClick", function(self)
		if IsShiftKeyDown() and self.entry and self.entry.link then
			UI.InsertLink(self.entry.link)
		end
	end)
	return t
end

-- What a tile says under the name: Gear Check's pick or verdict, else what it sells for.
local function TileSub(e)
	if e.tag then
		local after = e.tagText
		if not after and e.verdict then
			after = (ns.Gear_Headline(e.verdict))
		end
		return UI.Wrap(e.tag, "accent") .. (after and UI.Wrap("  " .. after, "textMuted") or "")
	elseif e.verdict then
		local headline, color = ns.Gear_Headline(e.verdict)
		return UI.Wrap(headline, COLOR_ROLES[color] or "textMuted")
	elseif e.spellID then
		return UI.Wrap("Spell", "textMuted")
	elseif e.sell and e.sell > 0 then
		return UI.Wrap("Sells for ", "textMuted") .. ns.Coins(e.sell, true, COIN_ICONS)
	end
	return ""
end

local function Tile(content, x, y, width, e)
	local t = Take(pools.tile, function()
		return MakeTile(content)
	end)
	t.entry = e
	t:ClearAllPoints()
	t:SetPoint("TOPLEFT", x, -y)
	t:SetWidth(width)
	t.icon:SetTexture(e.texture or ICON_UNKNOWN)
	t.count:SetText(e.count and e.count > 1 and e.count or "")
	local quality = e.quality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[e.quality]
	local name = e.name or RETRIEVING_ITEM_INFO
	t.name:SetText(quality and UI.Wrap(name, quality) or name)
	if quality then
		for _, edge in ipairs(t.ring.borderEdges) do
			edge:SetColorTexture(quality.r, quality.g, quality.b, 1)
		end
	else
		UI.SetBorderColor(t.ring, "frame", 1)
	end
	t.sub:SetText(TileSub(e))
	-- Gear Check's pick: an accent edge on the left and an accent rule around it.
	t.pick:SetColorTexture(UI.Color("accent"))
	t.pick:SetShown(e.tag ~= nil)
	UI.SetBorderColor(t, e.tag and "accent" or "frame", e.tag and 0.7 or 0.3)
end

-- A grid of tiles, two to a row (one alone takes the whole row); returns the y below it.
local function Tiles(content, y, width, list)
	if #list == 1 then
		Tile(content, 0, y, width, list[1])
		return y + TILE_H + TILE_GAP
	end
	local w = math.floor((width - TILE_GAP) / 2)
	for i, e in ipairs(list) do
		local col = (i - 1) % 2
		Tile(content, col * (w + TILE_GAP), y, w, e)
		if col == 1 or i == #list then
			y = y + TILE_H + TILE_GAP
		end
	end
	return y
end

-- Window ------------------------------------------------------------------------------------------------------------

local function Header(d)
	win.icon:SetTexture(d.complete and ICON_READY or ICON_OPEN)
	win.title:SetText(d.title or "?")
	local parts = {}
	if d.level and d.level > 0 then
		local role = ns.QuestList_DifficultyRole(d.level, UnitLevel("player"), GetQuestGreenRange and GetQuestGreenRange())
		parts[#parts + 1] = UI.Wrap(("Level %d"):format(d.level), role)
	end
	local progress = ns.QuestList_ProgressText(d.objectives, d.complete)
	if progress then
		parts[#parts + 1] = UI.Wrap(progress, d.complete and "success" or "textMuted")
	end
	win.sub:SetText(table.concat(parts, UI.Wrap("   /   ", "textFaint")))
	-- Spoken's Play button, when Spoken has a recording of this quest.
	local play = win.play
	if play == nil then
		play = ns.QuestListSpoken_Button(win, PLAY_SIZE) or false
		if play then
			play:SetPoint("TOPRIGHT", -PAD, -16)
		end
		win.play = play
	end
	local hasPlay = play and ns.QuestListSpoken_Bind(play, questID, d.title) or false
	win.title:SetPoint("RIGHT", hasPlay and play or win, hasPlay and "LEFT" or "RIGHT", hasPlay and -8 or -PAD, 0)
end

-- The checklist block: a sunken box with an accent edge. Returns the y below it.
local function Checklist(content, y, width, d)
	local box = win.checklist
	box:ClearAllPoints()
	box:SetPoint("TOPLEFT", 0, -y)
	box:SetWidth(width)
	local inner = width - OBJ_PAD * 2 - 3
	local iy = OBJ_PAD
	if #d.objectives > 0 then
		for i, obj in ipairs(d.objectives) do
			iy = Objective(box, iy, OBJ_PAD + 3, inner, obj)
			if i < #d.objectives then
				iy = iy + OBJ_GAP
			end
		end
	else
		-- No objectives the game counts (a talk-to or deliver quest): the quest's own summary, as one open item.
		iy = Objective(box, iy, OBJ_PAD + 3, inner, { label = d.objectivesText ~= "" and d.objectivesText or "?",
			finished = d.complete })
	end
	box:SetHeight(iy + OBJ_PAD)
	box:Show()
	return y + iy + OBJ_PAD
end

local function Rewards(content, y, width, d)
	local hasAny = #d.choices > 0 or #d.items > 0 or #d.spells > 0 or (d.xp or 0) > 0 or (d.money or 0) > 0
	if not hasAny then
		return y
	end
	y = Heading(content, y, width, "Rewards")
	if #d.choices > 0 then
		if #d.choices > 1 then
			y = Text(content, 0, y, width, "Pick one", "textMuted", 11) + 5
		end
		y = Tiles(content, y, width, d.choices)
	end
	local also = {}
	for _, e in ipairs(d.items) do
		also[#also + 1] = e
	end
	for _, e in ipairs(d.spells) do
		also[#also + 1] = e
	end
	if #also > 0 then
		if #d.choices > 0 then
			y = Text(content, 0, y + 2, width, "You also get", "textMuted", 11) + 5
		end
		y = Tiles(content, y, width, also)
	end
	-- Experience and money on one line: an XP badge, then the coins.
	local line = win.extras
	line:ClearAllPoints()
	line:SetPoint("TOPLEFT", 0, -(y + 2))
	local x = 0
	if (d.xp or 0) > 0 then
		line.badge:SetPoint("LEFT", 0, 0)
		line.badge:Show()
		line.xp:SetText(ns.Thousands(d.xp))
		line.xp:SetPoint("LEFT", line.badge, "RIGHT", 6, 0)
		line.xp:Show()
		x = XP_BADGE_W + 6 + line.xp:GetStringWidth() + 18
	else
		line.badge:Hide()
		line.xp:Hide()
	end
	if (d.money or 0) > 0 then
		line.money:SetText(ns.Coins(d.money, "exact", COIN_ICONS))
		line.money:ClearAllPoints()
		line.money:SetPoint("LEFT", x, 0)
		line.money:Show()
	else
		line.money:Hide()
	end
	local shown = (d.xp or 0) > 0 or (d.money or 0) > 0
	line:SetShown(shown)
	return shown and (y + 2 + 18) or y
end

local function Draw()
	local d = questID and Read()
	if not d then
		win:Hide()
		return
	end
	used = {}
	Header(d)
	local content = win.scroll.content
	local width = math.max(math.floor(win.scroll:GetWidth()), 200)
	content:SetWidth(width)
	local y = Checklist(content, 0, width, d) + GAP
	if d.text and d.text ~= "" then
		y = Text(content, 0, y, width, d.text, "textMuted", 12, "body", TEXT_SPACING) + GAP + 4
	end
	y = Rewards(content, y, width, d)
	HideUnused()
	content:SetHeight(math.max(y, 1))
	win.scroll:SetContentHeight(y)
	-- Grows to fit, so a short quest doesn't sit in a tall empty window.
	win:SetHeight(math.min(math.max(HEADER_H + y + FOOT_H + 8, MIN_H), MAX_H))
	win.share:SetEnabled(ns.QuestListParty_CanShare({ questID = questID }))
end

local drawSoon

local function Build()
	win = UI.Dialog("TomteQuestDetails", WIDTH, MIN_H, { y = 60 }) -- Escape closes it
	win.icon = win:CreateTexture(nil, "ARTWORK")
	win.icon:SetSize(HEAD_ICON, HEAD_ICON)
	win.icon:SetPoint("TOPLEFT", PAD - 4, -12)
	win.title = UI.Text(win, 16, "heading", "title")
	win.title:SetPoint("TOPLEFT", win.icon, "TOPRIGHT", 6, -1)
	win.title:SetPoint("RIGHT", -PAD, 0)
	win.title:SetJustifyH("LEFT")
	win.title:SetWordWrap(false)
	win.sub = UI.Text(win, 11, "textMuted")
	win.sub:SetPoint("TOPLEFT", win.title, "BOTTOMLEFT", 0, -4)
	local rule = UI.Hairline(win, WIDTH - PAD * 2, 0.6)
	rule:SetPoint("TOP", 0, -HEADER_H + 6)

	win.scroll = UI.Scroll(win)
	win.scroll:SetPoint("TOPLEFT", PAD, -HEADER_H)
	win.scroll:SetPoint("BOTTOMRIGHT", -PAD - 6, FOOT_H)
	win.scroll.onWidthChanged = function()
		if win:IsShown() then
			drawSoon()
		end
	end
	local content = win.scroll.content

	-- The checklist: a sunken box, an accent edge on its left (what to do now).
	win.checklist = CreateFrame("Frame", nil, content)
	UI.Surface(win.checklist, 0.35)
	local edge = win.checklist:CreateTexture(nil, "BORDER")
	edge:SetPoint("TOPLEFT")
	edge:SetPoint("BOTTOMLEFT")
	edge:SetWidth(3)
	edge:SetColorTexture(UI.Color("accent"))

	-- Experience and money.
	win.extras = CreateFrame("Frame", nil, content)
	win.extras:SetSize(WIDTH, 18)
	local badge = CreateFrame("Frame", nil, win.extras)
	badge:SetSize(XP_BADGE_W, XP_BADGE_H)
	local fill = badge:CreateTexture(nil, "BACKGROUND")
	fill:SetAllPoints()
	fill:SetColorTexture(UI.RGBA("info", 0.35))
	UI.Border(badge, "info", 0.8)
	local label = UI.Text(badge, 9, "text", "label")
	label:SetPoint("CENTER", 0, 0)
	label:SetText("XP")
	win.extras.badge = badge
	win.extras.xp = UI.Text(win.extras, 12, "text", "number")
	win.extras.money = UI.Text(win.extras, 12, "text", "number")

	win.close = UI.Button(win, 80, "Close")
	win.close:SetPoint("BOTTOMRIGHT", -PAD, 10)
	win.close:SetScript("OnClick", function()
		win:Hide()
	end)
	win.share = UI.Button(win, 110, "Share with party")
	win.share:SetPoint("BOTTOMLEFT", PAD, 10)
	win.share:SetScript("OnClick", function()
		ns.QuestListParty_Share({ questID = questID })
	end)

	win:HookScript("OnShow", function()
		events:Watch(OWNER, "QUEST_LOG_UPDATE")
		events:Watch(OWNER, "GET_ITEM_INFO_RECEIVED")
		events:Watch(OWNER, "QUEST_REMOVED")
	end)
	win:HookScript("OnHide", function()
		events:UnwatchAll(OWNER)
		questID = nil
	end)
end

drawSoon = UI.Debounce(REFRESH_DELAY, function()
	if win and win:IsShown() then
		Draw()
	end
end)

events:On(OWNER, "QUEST_LOG_UPDATE", drawSoon)
events:On(OWNER, "GET_ITEM_INFO_RECEIVED", drawSoon)
events:On(OWNER, "QUEST_REMOVED", function(_, removed)
	if removed == questID then
		win:Hide()
	end
end)

-- Shows the quest's details (again for the one already shown: it stays open).
function ns.QuestListDetails_Show(id)
	if not id then
		return
	end
	if not win then
		Build()
	end
	questID = id
	UI.PlaceDialog(win)
	win:Show()
	win.scroll:SetScroll(0)
	Draw()
end

-- The Quest list turned off.
function ns.QuestListDetails_Hide()
	if win then
		win:Hide()
	end
end
