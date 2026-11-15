local addonName, ns = ...

-- Dungeon journal: the lists: every dungeon grouped by your level (a bar of its range, your quests, upgrades and
-- wanted items there), and in a dungeon the quest list (Before you go first) or the boss list on the left. Shared
-- through ns.DJKit (Read.lua); laid out by Page.lua.

local LEVEL_BAR_W = 150 -- the level bar on a dungeon row
local LEVEL_BAR_H = 4
local MAX_LEVEL = 60 -- the bar's right end
local NO_MAX_SPAN = 8 -- a dungeon with no known top level: its band runs this far, dimmed

local UI = ns.UI
local Kit = ns.HomeKit
local J = ns.DJKit
local S = J.state

-- The level bar on a dungeon row: the range as a band on a 1-60 track, a tick where you are. The row's right-hand
-- text (the range as numbers) moves left of it. d nil: hidden.
function J.LevelBar(row, d, level)
	if not d then
		if row.levelTrack then
			row.levelTrack:Hide()
			row.levelBand:Hide()
			row.levelYou:Hide()
			row.right:ClearAllPoints()
			row.right:SetPoint("RIGHT", 0, 0)
		end
		return
	end
	if not row.levelTrack then
		row.levelTrack = row:CreateTexture(nil, "ARTWORK")
		row.levelTrack:SetSize(LEVEL_BAR_W, LEVEL_BAR_H)
		row.levelTrack:SetPoint("RIGHT", -4, 0)
		row.levelBand = row:CreateTexture(nil, "ARTWORK", nil, 1)
		row.levelBand:SetHeight(LEVEL_BAR_H)
		row.levelYou = row:CreateTexture(nil, "ARTWORK", nil, 2)
		row.levelYou:SetSize(2, LEVEL_BAR_H + 8)
	end
	local function X(lvl)
		return LEVEL_BAR_W * (math.min(math.max(lvl, 1), MAX_LEVEL) - 1) / (MAX_LEVEL - 1)
	end
	row.levelTrack:SetColorTexture(UI.RGBA("rule"))
	row.levelTrack:Show()
	if d.min then
		local top = d.max or (d.min + NO_MAX_SPAN)
		row.levelBand:SetColorTexture(UI.RGBA("accent", d.max and 1 or 0.5))
		row.levelBand:ClearAllPoints()
		row.levelBand:SetPoint("LEFT", row.levelTrack, "LEFT", X(d.min), 0)
		row.levelBand:SetWidth(math.max(X(top) - X(d.min), 2))
		row.levelBand:Show()
	else
		row.levelBand:Hide()
	end
	row.levelYou:SetColorTexture(UI.RGBA("text"))
	row.levelYou:ClearAllPoints()
	row.levelYou:SetPoint("CENTER", row.levelTrack, "LEFT", X(level), 0)
	row.levelYou:Show()
	row.right:ClearAllPoints()
	row.right:SetPoint("RIGHT", row.levelTrack, "LEFT", -12, 0)
end

-- Opening a dungeon -----------------------------------------------------------------------------------------------------

-- Opens d; hit (ns.DJ_Hit) puts it on what a search found. Without one it opens on the quests when you have any there,
-- else the bosses.
function J.Open(d, hit)
	S.inst, S.pick, S.mark = d, nil, nil
	local ctx = J.Context()
	S.tab = #ns.DJ_Quests(d, ctx.side, ctx.class, false) > 0 and "quests" or "bosses"
	if hit and hit.tab then
		S.tab, S.mark = hit.tab, hit.item
		if hit.quest then
			S.pick = { quest = hit.quest }
		elseif hit.boss or hit.extra then
			S.pick = { boss = hit.boss or { extra = true } }
		end
	end
	J.page.left:SetVerticalScroll(0)
	J.page.right:SetVerticalScroll(0)
	J.scrollToMark = S.mark ~= nil
	J.Layout()
end

-- The left lists --------------------------------------------------------------------------------------------------------

-- The lists are built again on every layout, so the picked entry is matched by the quest or boss it holds (the rares
-- and trash entry and Before you go are new each time too: matched by their flags).
local function IsPicked(entry)
	local pick = S.pick
	if not pick then
		return false
	elseif entry.prep then
		return pick.prep == true
	elseif entry.quest then
		return pick.quest == entry.quest
	end
	return pick.boss == entry.boss or (pick.boss ~= nil and pick.boss.extra and entry.boss.extra) or false
end

-- Marks the row and, when it's the picked one, keeps this layout's entry as the pick (a search's stand-in has no wing).
local function MarkPicked(row, entry)
	local picked = IsPicked(entry)
	if picked then
		S.pick = entry
	end
	J.Mark(row, picked)
	return picked
end

local function Pick(row)
	S.pick, S.mark = row.entry, nil
	UI.Sound("pick")
	J.page.right:SetVerticalScroll(0)
	J.Layout()
end

local function HasNamedWings()
	local inst = S.inst
	return #inst.wings > 1 or inst.wings[1].name ~= nil
end

function J.DrawQuestList(width)
	local c = J.page.left.content
	local inst = S.inst
	local ctx = J.Context()
	local list = ns.DJ_Quests(inst, ctx.side, ctx.class, J.DB().otherSide)
	local y = J.PAD
	-- Before you go, first.
	local prep = 0
	for _, g in ipairs(ns.DJ_Prep(inst, ctx)) do
		prep = prep + #g.list
	end
	if #list > 0 then
		local entry = { prep = true }
		if not S.pick and prep > 0 then
			S.pick = entry
		end
		local row = J.ListRow(y, width)
		row.entry, row.onClick = entry, Pick
		local picked = MarkPicked(row, entry)
		row:Set(nil, "Before you go", picked and "heading" or (prep > 0 and "accent" or "textMuted"), nil, nil,
			prep == 0 and "Nothing to pick up" or (prep == 1 and "1 quest to pick up" or ("%d quests to pick up"):format(prep)))
		y = y + Kit.ROW2_H + 4
	end
	local lastWing
	local named = HasNamedWings()
	for _, entry in ipairs(list) do
		if named and entry.wing ~= lastWing then
			lastWing = entry.wing
			y = J.Label(c, y, width, entry.wing.name or inst.name)
		end
		S.pick = S.pick or entry
		local q = entry.quest
		local state = ns.DJ_QuestState(q, ctx)
		local row = J.ListRow(y, width)
		row.entry, row.onClick = entry, Pick
		local picked = MarkPicked(row, entry)
		row:Set(nil, J.QuestTitle(q), picked and "heading" or (state == "other" and "textFaint" or "text"),
			J.STATE_TEXT[state], J.STATE_COLOR[state], q.lvl and ("From level %d"):format(q.lvl) or "")
		y = y + Kit.ROW2_H
	end
	if #list == 0 then
		local others = #ns.DJ_Quests(inst, ctx.side, ctx.class, true)
		if others > 0 then
			y = J.Text(c, y, width, ("No %s quests here. Turn on Other side's quests to see the %d others."):format(
				J.SideName(ctx.side), others), "textMuted", 12)
		else
			y = J.Text(c, y, width, "No quests known for this dungeon yet.", "textMuted", 12)
		end
	end
	return y
end

function J.DrawBossList(width)
	local c = J.page.left.content
	local inst = S.inst
	local list = ns.DJ_Bosses(inst)
	local y, lastWing = J.PAD, nil
	local named = HasNamedWings()
	for _, entry in ipairs(list) do
		if named and entry.wing and entry.wing ~= lastWing then
			lastWing = entry.wing
			y = J.Label(c, y, width, entry.wing.name or inst.name)
		elseif named and entry.boss.extra then
			y = J.Label(c, y, width, "Elsewhere") -- not the last wing's: rares and trash from the whole dungeon
		end
		S.pick = S.pick or entry
		local row = J.ListRow(y, width)
		row.entry, row.onClick = entry, Pick
		local picked = MarkPicked(row, entry)
		local n = #entry.boss.loot
		row:Set(nil, entry.boss.name, picked and "heading" or (entry.boss.extra and "textMuted" or "text"),
			n > 0 and tostring(n) or nil, "textFaint")
		if J.WantedIn(entry.boss.loot) > 0 then
			J.RowStar(row)
		end
		y = y + Kit.ROW_H
	end
	if #list == 0 then
		y = J.Text(c, y, width, "No bosses known for this dungeon yet.", "textMuted", 12)
	end
	return y
end

-- The dungeon list ------------------------------------------------------------------------------------------------------

local function OpenRow(row)
	UI.Sound("nav")
	J.Open(row.inst, ns.DJ_Hit(row.inst, J.page.search:GetText(), J.KnownName))
end

-- The row's second line: your quests there, then (for dungeons right for your level) upgrades, then wanted items.
local function RowLine(d, ctx, countUpgrades)
	local quests = ns.DJ_Quests(d, ctx.side, ctx.class, false)
	local n, done = #quests, 0
	for _, entry in ipairs(quests) do
		if ctx.done(entry.quest.id) then
			done = done + 1
		end
	end
	local parts = {}
	if n == 0 then
		parts[1] = ("No %s quests"):format(J.SideName(ctx.side))
	elseif done == n then
		parts[1] = n == 1 and "Its quest is done" or ("All %d quests done"):format(n)
	elseif done > 0 then
		parts[1] = ("%d of %d quests done"):format(done, n)
	else
		parts[1] = n == 1 and "1 quest for you" or ("%d quests for you"):format(n)
	end
	local upgrades = countUpgrades and J.Upgrades(d)
	if upgrades and upgrades > 0 then
		parts[#parts + 1] = upgrades == 1 and "1 upgrade" or ("%d upgrades"):format(upgrades)
	end
	local wanted = J.WantedIn(J.Loot(d))
	if wanted > 0 then
		parts[#parts + 1] = ("%d wanted"):format(wanted)
	end
	return table.concat(parts, ", "), wanted > 0
end

local function RangeText(d)
	if not d.min then
		return nil
	end
	return d.max and ("%d-%d"):format(d.min, d.max) or ("%d+"):format(d.min)
end

function J.DrawDungeons(width)
	local c = J.page.left.content
	local ctx = J.Context()
	local text = J.page.search:GetText()
	local found = {}
	for _, d in ipairs(J.List()) do
		if ns.DJ_Matches(d, text, J.KnownName) then
			found[#found + 1] = d
		end
	end
	local y = J.PAD
	for _, group in ipairs(ns.DJ_Groups(found, ctx.level)) do
		local n = #group.list
		y = J.Label(c, y, width, group.name, n == 1 and "1 dungeon" or ("%d dungeons"):format(n))
		for _, d in ipairs(group.list) do
			local row = J.ListRow(y, width)
			row.inst, row.onClick = d, OpenRow
			local line, wanted = RowLine(d, ctx, group.key == "now")
			row:Set(nil, d.name, group.key == "past" and "textMuted" or "text", RangeText(d), "textMuted", line)
			J.LevelBar(row, d, ctx.level)
			if wanted then
				J.RowStar(row)
			end
			y = y + Kit.ROW2_H
		end
	end
	if #found == 0 then
		y = J.Text(c, y, width, "No dungeon has a boss, quest or item by that name. Right-click the search box to "
			.. "clear it.", "textMuted", 12)
	end
	return y
end
