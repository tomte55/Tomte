local addonName, ns = ...

-- Pet Battles: the Guides window. One row per guide link (Xu-Fu encounter pages, Wowhead), each with what the fight
-- is for and a Copy button: WoW can't open a browser or write the clipboard, so Copy selects that one link and
-- Ctrl+C copies it. A pet battle world quest up next to you marks its link "Active now" and puts it first.
-- On UIParent like every window, so it shows over the Tomte window (Pet Battles page). While a dialogue addon
-- (DialogueUI, Immersion) hides UIParent at a tamer it goes on WorldFrame instead (see Show).

local UI = ns.UI
local WIDTH = 460
local PAD = 14
local ROW_H = 58
-- The header's heights, top down: title offset, title line, gap, (the hint's own height), gap before the first row.
local TITLE_TOP, TITLE_H, HINT_GAP, LIST_GAP = 12, 16, 4, 12
local NEAR_YARDS = 60 -- a pet battle world quest's map pin sits on its tamer

local KIND_NOTE = {
	wq = "World quest: win with any team.",
	family = "Achievement: win each fight with pets of one family.",
	tradingpost = "Trading Post: a Traveler's Log task, only in months that have it. Check its pet rule.",
}

local popup

-- Is a pet battle world quest up within NEAR_YARDS of the player? Talking to its tamer puts you on its pin.
local function WorldQuestNearby()
	local petBattle = Enum.QuestTagType and Enum.QuestTagType.PetBattle
	local mapID = C_Map.GetBestMapForUnit("player")
	local pos = mapID and C_Map.GetPlayerMapPosition(mapID, "player")
	if not (petBattle and pos) then
		return false
	end
	local width, height = C_Map.GetMapWorldSize(mapID)
	if not (width and width > 0 and height and height > 0) then
		return false
	end
	for _, info in ipairs(C_TaskQuest.GetQuestsOnMap(mapID) or {}) do
		local tag = info.questID and C_QuestLog.GetQuestTagInfo(info.questID)
		if tag and tag.worldQuestType == petBattle and info.x and info.y then
			local dx, dy = (info.x - pos.x) * width, (info.y - pos.y) * height
			if dx * dx + dy * dy <= NEAR_YARDS * NEAR_YARDS then
				return true
			end
		end
	end
	return false
end

local function Hide()
	if popup then
		popup:Hide()
	end
end

local function Row(i)
	local row = popup.rows[i]
	if row then
		return row
	end
	row = CreateFrame("Frame", nil, popup)
	row:SetHeight(ROW_H)
	row.label = UI.Text(row, 12, "heading")
	row.label:SetPoint("TOPLEFT")
	row.badge = UI.Text(row, 11, "success", "label")
	row.badge:SetPoint("LEFT", row.label, "RIGHT", 8, 0)
	row.badge:SetText("Active now")
	row.note = UI.Text(row, 11, "textMuted")
	row.note:SetPoint("TOPLEFT", row.label, "BOTTOMLEFT", 0, -2)
	row.note:SetPoint("RIGHT")
	row.note:SetWordWrap(false)

	row.copy = UI.Button(row, 64, "Copy")
	row.copy:SetPoint("BOTTOMRIGHT")
	local box = CreateFrame("Frame", nil, row)
	box:SetPoint("BOTTOMLEFT")
	box:SetPoint("RIGHT", row.copy, "LEFT", -6, 0)
	box:SetHeight(20)
	UI.Surface(box)
	local edit = CreateFrame("EditBox", nil, box)
	edit:SetPoint("TOPLEFT", 6, 0)
	edit:SetPoint("BOTTOMRIGHT", -6, 0)
	edit:SetAutoFocus(false)
	UI.SetFont(edit, "number", 11)
	edit:SetTextColor(UI.Color("text"))
	edit:SetScript("OnTextChanged", function(self, userInput)
		if userInput then -- read-only
			self:SetText(row.url)
			self:HighlightText()
		end
	end)
	edit:SetScript("OnEditFocusGained", function(self)
		self:HighlightText()
		row.copy.label:SetText("Ctrl+C")
	end)
	edit:SetScript("OnEditFocusLost", function(self)
		self:HighlightText(0, 0)
		row.copy.label:SetText("Copy")
	end)
	edit:SetScript("OnEscapePressed", Hide)
	-- Ctrl+C copies the link, then the window closes (a frame later, so the copy happens first).
	edit:SetScript("OnKeyDown", function(_, key)
		if key == "C" and IsControlKeyDown() then
			C_Timer.After(0, Hide)
		end
	end)
	row.edit = edit
	row.copy:SetScript("OnClick", function()
		edit:SetFocus()
		edit:HighlightText()
	end)
	popup.rows[i] = row
	return row
end

local function Build()
	popup = UI.Dialog("TomtePetsGuides", WIDTH, nil, { y = 120 }) -- Escape closes it
	popup.title = UI.Text(popup, 14, "heading", "title")
	popup.title:SetPoint("TOPLEFT", PAD, -TITLE_TOP)
	popup.hint = UI.Text(popup, 11, "textMuted")
	popup.hint:SetPoint("TOPLEFT", popup.title, "BOTTOMLEFT", 0, -HINT_GAP)
	popup.hint:SetPoint("RIGHT", -PAD, 0)
	popup.hint:SetJustifyH("LEFT")
	popup.hint:SetText("Copy a link, then press Ctrl+C and paste it in your browser.")
	popup.footer = UI.Text(popup, 11, "textMuted")
	popup.footer:SetPoint("BOTTOMLEFT", PAD, 14)
	popup.footer:SetPoint("RIGHT", -110, 0)
	popup.footer:SetJustifyH("LEFT")
	popup.footer:SetText("On Xu-Fu, a strategy's \"Rematch string\" button gives a team: paste it in Pet Battles > Teams (/tomte pets import).")
	popup.close = UI.Button(popup, 80, "Close")
	popup.close:SetPoint("BOTTOMRIGHT", -PAD, 10)
	popup.close:SetScript("OnClick", Hide)
	popup.rows = {}
end

-- links = { { label, note, url, active } }, in order.
local function Show(title, links)
	if not popup then
		Build()
	end
	-- WorldFrame's children draw under all of UIParent, so WorldFrame only while UIParent is hidden, scaled to
	-- UIParent's size there. SetParent can carry the parent's strata over, so it's set again.
	if UIParent:IsShown() then
		popup:SetParent(UIParent)
		popup:SetScale(1)
	else
		popup:SetParent(WorldFrame)
		popup:SetScale(UIParent:GetEffectiveScale() / WorldFrame:GetEffectiveScale())
	end
	popup:SetFrameStrata("DIALOG")
	popup.title:SetText(title or "")
	local y = TITLE_TOP + TITLE_H + HINT_GAP + popup.hint:GetStringHeight() + LIST_GAP
	for i, link in ipairs(links) do
		local row = Row(i)
		row:ClearAllPoints()
		row:SetPoint("TOPLEFT", PAD, -y)
		row:SetPoint("RIGHT", -PAD, 0)
		row.url = link.url
		row.label:SetText(link.label)
		row.badge:SetShown(link.active == true)
		row.note:SetText(link.note or "")
		row.edit:SetText(link.url)
		row.edit:SetCursorPosition(0)
		row.edit:ClearFocus()
		row:Show()
		y = y + ROW_H + 10
	end
	for i = #links + 1, #popup.rows do
		popup.rows[i]:Hide()
	end
	popup:SetHeight(y + popup.footer:GetStringHeight() + 30)
	popup:Show()
	if popup.rows[1] and links[1] and links[1].active then -- the one to use: selected, ready for Ctrl+C
		popup.rows[1].edit:SetFocus()
	end
end

local function XufuLink(encounterID, sectionID, active)
	local section = ns.PetsStore_Section(sectionID)
	return {
		label = "Xu-Fu: " .. (section and section.name or "strategies"),
		note = section and KIND_NOTE[section.kind] or "Strategies for this fight.",
		url = ns.Pets_XufuURL(encounterID),
		active = active and section ~= nil and section.kind == "wq" or nil,
	}
end

local function WowheadLink(npc)
	return { label = "Wowhead", note = "Where the tamer is, and comments. Not a strategy.", url = ns.Pets_WowheadURL(npc) }
end

-- Active ones first, the rest in the table's order (newest expansion first).
local function ActiveFirst(links)
	local out = {}
	for _, l in ipairs(links) do
		if l.active then
			out[#out + 1] = l
		end
	end
	for _, l in ipairs(links) do
		if not l.active then
			out[#out + 1] = l
		end
	end
	return out
end

-- From the tamer card: you're standing at the tamer, so a pet battle world quest pin here is this tamer's.
function ns.PetsGuides_ShowNPC(npc)
	local nearby = WorldQuestNearby()
	local links = {}
	for _, e in ipairs(ns.PetsStore_Encounters(npc)) do
		links[#links + 1] = XufuLink(e.id, e.section, nearby)
	end
	links = ActiveFirst(links)
	links[#links + 1] = WowheadLink(npc)
	Show(ns.PetsStore_NPCName(npc), links)
end

-- From the Pet Battles page's tamer list: one encounter, maybe anywhere in the world.
function ns.PetsGuides_ShowEncounter(id)
	local e = ns.PETS_ENCOUNTERS[id]
	if not e then
		return
	end
	local links = { XufuLink(id, e.section, false) }
	for _, npc in ipairs(e.npcs) do
		links[#links + 1] = WowheadLink(npc)
	end
	Show(e.name, links)
end
