local addonName, ns = ...

-- Weekly board, Raids tab: the content expansion's raids, each boss with four dots (LFR, Normal, Heroic, Mythic)
-- filled when killed this week. The raid list is the Encounter Journal's tier for the expansion (read once per
-- session, out of combat and not while Blizzard's journal is open, the selected tier restored afterwards), else
-- `raids` in Data/<Expansion>/Weekly.lua. The Encounter Journal API is global state: bosses are read once per
-- session, only when this tab shows, with the journal's difficulty restored and Blizzard's journal kept from
-- reacting meanwhile (as Plumber does).

local UI = ns.UI
local GOLD, WHITE, GREY, DIM = UI.GOLD, UI.WHITE, UI.GREY, UI.DIM
local GREEN = { 0.45, 0.85, 0.45 }
local RAID_H, BOSS_H, DOT, COL_W = 30, 24, 10, 52
local CIRCLE = "Interface\\CHARACTERFRAME\\TempPortraitAlphaMask"

local raids = {} -- [expansion] = the full read, once per session
local partial, partialAt = {}, {} -- an incomplete read, kept a few seconds so redraws don't touch the journal each time
local journal = {} -- [expansion] = the journal tier's raid IDs (oldest first, world bosses left out), false: can't
local source = {} -- [expansion] = "journal" | "table", for /tomte data
local RETRY = 5

local function MuteJournal()
	local frame = EncounterJournal
	if not frame then
		return
	end
	frame:UnregisterEvent("EJ_LOOT_DATA_RECIEVED")
	frame:UnregisterEvent("EJ_DIFFICULTY_UPDATE")
	C_Timer.After(0, function()
		frame:RegisterEvent("EJ_LOOT_DATA_RECIEVED")
		frame:RegisterEvent("EJ_DIFFICULTY_UPDATE")
	end)
end

-- The journal tier's raids: a list, false when the game has no such tier, nil when it can't be read right now.
-- Tier = expansion + 1 (GetEJTierDataTableID in Blizzard_EncounterJournal: The War Within 10 is tier 11).
-- World bosses are listed as a raid of each tier; they have no dungeon map (dungeonAreaMapID 0) and are left out.
local function ReadJournalTier(expansion)
	if journal[expansion] ~= nil then
		return journal[expansion]
	end
	if not (EJ_GetCurrentTier and EJ_SelectTier and EJ_GetNumTiers and EJ_GetInstanceByIndex) then
		journal[expansion] = false
		return false
	end
	if InCombatLockdown() or (EncounterJournal and EncounterJournal:IsShown()) then
		return nil
	end
	local tier = expansion + 1
	local tiers = EJ_GetNumTiers() or 0
	if tiers == 0 then
		return nil -- the journal isn't ready yet (early in the login): read it again later
	end
	if tier > tiers then
		journal[expansion] = false
		return false
	end
	local before = EJ_GetCurrentTier()
	local ids = {}
	local ok = pcall(function()
		EJ_SelectTier(tier)
		local i = 1
		local id, _, _, _, _, _, _, areaMap = EJ_GetInstanceByIndex(i, true)
		while id do
			if (areaMap or 0) ~= 0 then
				ids[#ids + 1] = id
			end
			i = i + 1
			id, _, _, _, _, _, _, areaMap = EJ_GetInstanceByIndex(i, true)
		end
	end)
	if before and before ~= tier then
		EJ_SelectTier(before)
	end
	if ok and #ids == 0 then
		return nil -- tiers are known before their instances load: read it again later
	end
	journal[expansion] = ok and ids or false
	return journal[expansion]
end

-- The expansion's raids with their bosses, and where the list came from ("journal" or "table").
local function ReadRaids(expansion)
	if not expansion then
		return {}, "table"
	end
	if raids[expansion] then
		return raids[expansion], source[expansion]
	end
	if partial[expansion] and GetTime() - partialAt[expansion] < RETRY then
		return partial[expansion], source[expansion]
	end
	local list, complete = {}, true
	MuteJournal()
	local fromJournal = ReadJournalTier(expansion)
	complete = fromJournal ~= nil -- read the journal tier later (in combat, or Blizzard's journal is open)
	local ids = ns.Weekly_RaidOrder(fromJournal or nil, ns.Content_Get(expansion, "raids"))
	source[expansion] = fromJournal and #fromJournal > 0 and "journal" or "table"
	local before = EJ_GetDifficulty()
	EJ_SetDifficulty(14) -- EJ_GetEncounterInfoByIndex returns nil without a difficulty set
	for _, jid in ipairs(ids) do
		local name, _, _, _, _, _, _, _, _, mapID = EJ_GetInstanceInfo(jid)
		if name then
			local bosses = {}
			local i = 1
			local bossName, _, journalEncounterID, _, _, _, encounterID = EJ_GetEncounterInfoByIndex(i, jid)
			while journalEncounterID do
				bosses[#bosses + 1] = { name = bossName, encounterID = encounterID }
				i = i + 1
				bossName, _, journalEncounterID, _, _, _, encounterID = EJ_GetEncounterInfoByIndex(i, jid)
			end
			complete = complete and #bosses > 0
			list[#list + 1] = { id = jid, name = name, mapID = mapID, bosses = bosses }
		else
			complete = false
		end
	end
	if before then
		EJ_SetDifficulty(before)
	end
	-- Journal data can be missing right after login; only keep a full read.
	if complete then
		raids[expansion] = list
	else
		partial[expansion], partialAt[expansion] = list, GetTime()
	end
	return list, source[expansion]
end
ns.WeeklyRaids_Read = ReadRaids

local function IsKilled(mapID, encounterID, difficultyID)
	return mapID ~= nil and encounterID ~= nil and C_RaidLocks.IsEncounterComplete(mapID, encounterID, difficultyID) == true
end

function ns.WeeklyRaidsView(parent)
	local Kit = ns.HomeKit
	local view = { rows = {}, heads = {} }
	view.scroll = UI.Scroll(parent)
	local c = view.scroll.content

	view.none = UI.Text(c, 13, GREY)
	view.none:SetPoint("TOPLEFT", 16, -16)

	-- Column labels over the dots.
	for d, diff in ipairs(ns.WEEKLY_RAID_DIFFICULTIES) do
		local head = UI.Text(c, 12, GREY)
		head:SetJustifyH("CENTER")
		head:SetWidth(COL_W)
		head:SetText(diff.name)
		view.heads[d] = head
	end

	local function Row(i)
		local row = view.rows[i]
		if not row then
			row = CreateFrame("Button", nil, c)
			row.bg = row:CreateTexture(nil, "BACKGROUND")
			row.bg:SetAllPoints()
			row.hover = row:CreateTexture(nil, "BACKGROUND")
			row.hover:SetAllPoints()
			row.hover:SetColorTexture(1, 1, 1, 0.05)
			row.hover:Hide()
			row.name = UI.Text(row, 13, WHITE)
			row.name:SetPoint("LEFT", 12, 0)
			row.name:SetWordWrap(false)
			row.cells = {}
			for d = 1, #ns.WEEKLY_RAID_DIFFICULTIES do
				local x = -((#ns.WEEKLY_RAID_DIFFICULTIES - d) * COL_W) - 8
				local dot = row:CreateTexture(nil, "ARTWORK")
				dot:SetTexture(CIRCLE)
				dot:SetSize(DOT, DOT)
				dot:SetPoint("CENTER", row, "RIGHT", x - COL_W / 2, 0)
				local text = row:CreateFontString(nil, "OVERLAY")
				text:SetFont(Kit.NARROW_FONT, 14, "")
				text:SetPoint("CENTER", row, "RIGHT", x - COL_W / 2, 0)
				row.cells[d] = { dot = dot, text = text }
			end
			row.name:SetPoint("RIGHT", row, "RIGHT", -(#ns.WEEKLY_RAID_DIFFICULTIES * COL_W) - 16, 0)
			row:SetScript("OnEnter", function(self)
				self.hover:SetShown(self.raidID ~= nil)
			end)
			row:SetScript("OnLeave", function(self)
				self.hover:Hide()
			end)
			row:SetScript("OnClick", function(self)
				if self.raidID then
					ns.weeklyDB.raidCollapsed[self.raidID] = not ns.weeklyDB.raidCollapsed[self.raidID] or nil
					PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
					ns.WeeklyBoard_Refresh()
				end
			end)
			view.rows[i] = row
		end
		row:Show()
		return row
	end

	function view:Render(width)
		width = math.max(width or 0, 500)
		for _, row in ipairs(self.rows) do
			row:Hide()
		end
		local expansion = ns.ContentExpansion()
		local items = ns.Weekly_RaidModel(ReadRaids(expansion), IsKilled, ns.weeklyDB.raidCollapsed)
		self.none:SetText(ns.Weekly_NoDataText("raids", expansion))
		self.none:SetShown(#items == 0)
		local right = width - 16
		local n = #ns.WEEKLY_RAID_DIFFICULTIES
		for d, head in ipairs(self.heads) do
			head:ClearAllPoints()
			head:SetPoint("TOP", c, "TOPLEFT", right - 8 - (n - d) * COL_W - COL_W / 2, -10)
			head:SetShown(#items > 0)
		end
		local y = 30
		for i, item in ipairs(items) do
			local row = Row(i)
			local raid = item.kind == "raid"
			row:ClearAllPoints()
			row:SetPoint("TOPLEFT", raid and 8 or 20, -y)
			row:SetPoint("RIGHT", c, "LEFT", right, 0)
			row:SetHeight(raid and RAID_H or BOSS_H)
			row.bg:SetColorTexture(1, 1, 1, raid and 0.06 or 0.02)
			row.raidID = raid and item.id or nil
			row:EnableMouse(raid)
			row.name:SetFont(STANDARD_TEXT_FONT, raid and 14 or 12, "")
			row.name:SetText(raid and ((item.collapsed and "+  " or "-  ") .. item.name) or item.name)
			local col = raid and GOLD or WHITE
			row.name:SetTextColor(col[1], col[2], col[3])
			for d, cell in ipairs(row.cells) do
				cell.dot:SetShown(not raid)
				cell.text:SetShown(raid)
				if raid then
					cell.text:SetText(item.totals[d])
					cell.text:SetTextColor(GREY[1], GREY[2], GREY[3])
				else
					local killed = item.dots[d]
					local c2 = killed and GREEN or DIM
					cell.dot:SetVertexColor(c2[1], c2[2], c2[3], killed and 1 or 0.6)
				end
			end
			y = y + (raid and RAID_H + 4 or BOSS_H + 2)
		end
		self.scroll:SetContentHeight(y + 16)
	end

	return view
end
