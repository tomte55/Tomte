local addonName, ns = ...

-- Expansion summary page in the Tomte window: the Great Vault, upgrade crests and raid kills (left), renown factions
-- and this week's open activities (right; one column on a narrow window). Everything comes from the Weekly board's
-- readers (ns.Weekly_ReadLive, ns.Weekly_ReadFactions, ns.WeeklyRaids_Read, ...), read each time it draws; the rows
-- come from Data.lua. Registered in Summary.lua.

local PAD = 8
local COL_GAP = 28
local TWO_COLUMNS = 760 -- content width from which the page is drawn in two columns
local SLOT_W, SLOT_H, SLOT_GAP = 64, 26, 6
local VAULT_ROW_H = 32
local LABEL_W = 84 -- the vault track's label in front of its slots
local QUESTION = "Interface\\Icons\\INV_Misc_QuestionMark"
local RAID_ICON = "Interface\\Icons\\INV_Misc_Head_Dragon_01"

local UI = ns.UI
local Kit = ns.HomeKit

local page, scroll, c -- c: the scroll content
local heads = {}
local vaultLabels, vaultSlots = {}, {} -- [track index], [track index][slot index]
local pools = { crests = {}, raids = {}, factions = {}, activities = {} }
local texts = {}

local function AtlasExists(name)
	return C_Texture.GetAtlasInfo(name) ~= nil
end

local function Heading(key)
	heads[key] = heads[key] or Kit.Heading(c)
	return heads[key]
end

local function Line(key, size, role)
	if not texts[key] then
		texts[key] = UI.Text(c, size, role)
		texts[key]:SetWordWrap(true)
		texts[key]:SetJustifyH("LEFT")
	end
	return texts[key]
end

-- Places a frame at x, y, w wide; returns the y below it.
local function Place(frame, x, y, w, h)
	frame:ClearAllPoints()
	frame:SetPoint("TOPLEFT", x, -y)
	frame:SetWidth(w)
	frame:Show()
	return y + h
end

local function PlaceText(fs, x, y, w, text, gap)
	if not text or text == "" then
		fs:Hide()
		return y
	end
	fs:SetText(text)
	fs:ClearAllPoints()
	fs:SetPoint("TOPLEFT", x, -y)
	fs:SetWidth(w)
	fs:Show()
	return y + fs:GetStringHeight() + (gap or 4)
end

local function OpenWeekly()
	ns.Panel_OpenPage("weekly")
end

-- Sections -------------------------------------------------------------------------------------------------------

local function RenderVault(x, y, w, vault, ready)
	Heading("vault"):Set("Great Vault", ("%d/%d slots"):format(vault.unlocked, vault.total))
	y = Place(heads.vault, x, y, w, 30) + 6
	y = PlaceText(Line("vaultReady", 13, "success"), x, y, w, ready and "Rewards are waiting in the Great Vault." or nil, 6)
	for t, row in ipairs(vault.rows) do
		local label = vaultLabels[t]
		if not label then
			label = UI.Text(c, 13, "text")
			label:SetJustifyH("LEFT")
			vaultLabels[t] = label
			vaultSlots[t] = {}
		end
		label:ClearAllPoints()
		label:SetPoint("LEFT", c, "TOPLEFT", x, -(y + SLOT_H / 2))
		label:SetWidth(LABEL_W)
		label:SetText(row.label)
		label:Show()
		for i, s in ipairs(row.slots) do
			local slot = vaultSlots[t][i]
			if not slot then
				slot = ns.WeeklySlot_Create(c, SLOT_W, SLOT_H, 12)
				vaultSlots[t][i] = slot
			end
			ns.WeeklySlot_Set(slot, { progress = s.progress or 0, threshold = s.threshold or 0, ilvl = s.ilvl },
				i == row.nextSlot, true)
			slot:ClearAllPoints()
			slot:SetPoint("TOPLEFT", x + LABEL_W + (i - 1) * (SLOT_W + SLOT_GAP), -y)
			slot:Show()
		end
		for i = #row.slots + 1, #vaultSlots[t] do
			vaultSlots[t][i]:Hide()
		end
		y = y + VAULT_ROW_H
	end
	for t = #vault.rows + 1, #vaultLabels do
		vaultLabels[t]:Hide()
		for _, slot in ipairs(vaultSlots[t]) do
			slot:Hide()
		end
	end
	if #vault.rows == 0 or vault.total == 0 then
		y = PlaceText(Line("vaultNone", 13, "textMuted"), x, y, w, "The Great Vault opens at max level.", 4)
	else
		Line("vaultNone", 13, "textMuted"):Hide()
	end
	return y + 14
end

local function RenderCrests(x, y, w, resources)
	local n = 0
	for _, r in ipairs(resources) do
		if r.crest then
			n = n + 1
			local row = Kit.PoolRow(pools.crests, n, c)
			row:Set(r.icon or QUESTION, r.name, r.dim and "textMuted" or "text", r.text)
			row.icon:SetDesaturated(r.dim == true)
			local id = r.id
			row.onEnter = function(self)
				GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
				GameTooltip:SetCurrencyByID(id)
				GameTooltip:Show()
			end
		end
	end
	Kit.HideFrom(pools.crests, n + 1)
	Heading("crests"):Set("Upgrade crests", nil)
	if n == 0 then
		heads.crests:Hide()
		return y
	end
	y = Place(heads.crests, x, y, w, 30) + 4
	for i = 1, n do
		y = Place(pools.crests[i], x, y, w, Kit.ROW_H)
	end
	return y + 14
end

local function RenderRaids(x, y, w, raids, worldBosses)
	local killed = 0
	for _, r in ipairs(raids) do
		killed = killed + (r.any and 1 or 0)
	end
	Heading("raids"):Set("Raids", #raids > 0 and ("%d of %d with kills"):format(killed, #raids) or nil,
		ns.Weekly_Active() and "Bosses" or nil, OpenWeekly)
	y = Place(heads.raids, x, y, w, 30) + 4
	local n = 0
	for _, r in ipairs(raids) do
		n = n + 1
		local row = Kit.PoolRow(pools.raids, n, c)
		row:Set(RAID_ICON, r.name, r.any and "text" or "textMuted", r.text, r.any and "success" or "textFaint")
		y = Place(row, x, y, w, Kit.ROW_H)
	end
	if #worldBosses > 0 then
		n = n + 1
		local row = Kit.PoolRow(pools.raids, n, c)
		row:Set(RAID_ICON, "World boss", "text", table.concat(worldBosses, ", "), "success")
		y = Place(row, x, y, w, Kit.ROW_H)
	end
	Kit.HideFrom(pools.raids, n + 1)
	if n == 0 then
		y = PlaceText(Line("raidsNone", 13, "textMuted"), x, y, w,
			ns.Weekly_NoDataText("raids", ns.ContentExpansion()), 4)
	else
		Line("raidsNone", 13, "textMuted"):Hide()
	end
	return y + 14
end

local function FactionTooltip(row, rec)
	local d = ns.Weekly_FactionDetail(rec)
	GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
	GameTooltip:SetText(d.title, UI.Color("text"))
	UI.TipLine(d.line1, "heading")
	if d.line2 ~= "" then
		UI.TipLine(d.line2, "textMuted")
	end
	if rec.max and rec.level and rec.level < rec.max then
		local rewards = C_MajorFactions.GetRenownRewardsForLevel(rec.id, rec.level + 1) or {}
		if #rewards > 0 then
			GameTooltip:AddLine(" ")
			UI.TipLine("Next rewards:", "text")
			for _, r in ipairs(rewards) do
				UI.TipLine(("|T%s:16|t %s"):format(r.icon or QUESTION, r.name or "?"), "heading")
			end
		end
	end
	GameTooltip:Show()
end

local function RenderFactions(x, y, w, factions)
	Heading("factions"):Set("Factions", #factions > 0 and tostring(#factions) or nil,
		ns.Weekly_Active() and "Reward tracks" or nil, OpenWeekly)
	y = Place(heads.factions, x, y, w, 30) + 4
	for i, f in ipairs(factions) do
		local rec = f.rec
		local d = ns.Weekly_FactionDetail(rec)
		local row = Kit.PoolRow(pools.factions, i, c)
		row:Set(QUESTION, d.title, f.waiting and "accent" or "text", d.line1, f.maxed and "heading" or "textMuted", d.line2)
		local atlas = ns.Weekly_FactionAtlas(rec.kit, AtlasExists)
		if atlas then
			row.icon:SetAtlas(atlas)
		else
			row.icon:SetTexture(QUESTION)
			row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
		end
		row.onEnter = function(self)
			FactionTooltip(self, rec)
		end
		y = Place(row, x, y, w, Kit.ROW2_H)
	end
	Kit.HideFrom(pools.factions, #factions + 1)
	if #factions == 0 then
		y = PlaceText(Line("factionsNone", 13, "textMuted"), x, y, w,
			"No renown factions unlocked for this character's expansion yet.", 4)
	else
		Line("factionsNone", 13, "textMuted"):Hide()
	end
	return y + 14
end

local function RenderActivities(x, y, w, acts)
	Heading("activities"):Set("This week", acts.done > 0 and ("%d done"):format(acts.done) or nil,
		ns.Weekly_Active() and "Weekly board" or nil, OpenWeekly)
	y = Place(heads.activities, x, y, w, 30) + 4
	local n, group = 0, nil
	for _, a in ipairs(acts.rows) do
		n = n + 1
		local row = Kit.PoolRow(pools.activities, n, c)
		-- The group only on its first row, in front of the activity.
		local text = a.text
		if a.group ~= "" and a.group ~= group then
			text = UI.Wrap(a.group .. ":", "textMuted") .. " " .. a.text
		end
		group = a.group
		row:Set(nil, text, "text", a.right, "textMuted")
		y = Place(row, x, y, w, Kit.ROW_H)
	end
	Kit.HideFrom(pools.activities, n + 1)
	local none
	if n == 0 then
		none = acts.done > 0 and "Everything tracked is done this week."
			or "Nothing tracked yet. Weekly quests show here once they've been in your quest log."
	end
	y = PlaceText(Line("activitiesNone", 13, "textMuted"), x, y, w, none, 4)
	return y + 14
end

-- Render ---------------------------------------------------------------------------------------------------------

-- What the page and the minimap tooltip read, gathered once per draw.
function ns.Summary_Read()
	local expansion = ns.ContentExpansion()
	local live = ns.Weekly_ReadLive()
	local resources = ns.Weekly_ReadResources(expansion)
	local crests = {}
	for _, r in ipairs(resources) do
		if r.crest then
			crests[#crests + 1] = r
		end
	end
	local factions = ns.Summary_Factions(ns.Weekly_ReadFactions())
	local waiting = 0
	for _, f in ipairs(factions) do
		waiting = waiting + (f.waiting and 1 or 0)
	end
	return {
		expansion = expansion, live = live, resources = resources, crests = crests, factions = factions,
		factionsWaiting = waiting, vault = ns.Summary_Vault(live.vault, ns.WEEKLY_TRACKS),
		vaultReady = live.vaultReady == true,
	}
end

local function Render()
	if not (page and page:IsVisible()) then
		return
	end
	local s = ns.Summary_Read()
	local width = math.max(c:GetWidth(), 320)
	local two = width >= TWO_COLUMNS
	local colW = two and math.floor((width - 2 * PAD - COL_GAP) / 2) or width - 2 * PAD
	local now = GetServerTime()
	local top = PlaceText(Line("intro", 13, "textMuted"), PAD, PAD, width - 2 * PAD,
		("%s · %s"):format(ns.ExpansionName(s.expansion),
			ns.Weekly_ResetText(C_DateAndTime.GetSecondsUntilWeeklyReset(), now) or "this week"), 10)

	local raids = ns.Summary_Raids(ns.WeeklyRaids_Read(s.expansion), ns.Weekly_RaidKilled, ns.WEEKLY_RAID_DIFFICULTIES)
	local model = ns.Weekly_ActivityModel(ns.Weekly_ReadCurated(s.expansion), ns.Weekly_LearnedQuests(),
		ns.Weekly_CurrentView() or { quests = {} }, true, nil)

	local y = RenderVault(PAD, top, colW, s.vault, s.vaultReady)
	y = RenderCrests(PAD, y, colW, s.resources)
	y = RenderRaids(PAD, y, colW, raids, ns.Summary_WorldBosses(s.live.lockouts))
	local x2, y2 = PAD, y
	if two then
		x2, y2 = PAD + colW + COL_GAP, top
	end
	y2 = RenderFactions(x2, y2, colW, s.factions)
	y2 = RenderActivities(x2, y2, colW, ns.Summary_Activities(model))
	scroll:SetContentHeight(math.max(y, y2) + PAD)
end

local refreshSoon = UI.Debounce(0.5, Render)

-- Redraw while it's shown (Summary.lua calls this on its events).
function ns.SummaryPage_Refresh()
	if page and page:IsVisible() then
		refreshSoon()
	end
end

function ns.SummaryPage_IsShown()
	return page ~= nil and page:IsVisible()
end

ns.SummaryPage = {
	title = "Expansion summary",
	Create = function(frame)
		page = frame
		scroll = UI.Scroll(page)
		scroll:SetPoint("TOPLEFT", 0, 0)
		scroll:SetPoint("BOTTOMRIGHT", -10, 0)
		c = scroll.content
		scroll.onWidthChanged = function()
			Render()
		end
		-- The panel only runs Refresh the first time; this covers reopening the panel on this page.
		page:HookScript("OnShow", function()
			RequestRaidInfo() -- answers with UPDATE_INSTANCE_INFO, which redraws
			Render()
		end)
	end,
	Refresh = function()
		RequestRaidInfo()
		Render()
	end,
}
