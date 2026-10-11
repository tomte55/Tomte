local addonName, ns = ...

-- Gathering run tracker: a small widget while a run is on (and in Edit Mode, with sample numbers when there's no
-- run). Time, nodes and nodes per hour, value and gold per hour, the three biggest items with their rank icon,
-- finds, skill and knowledge. Minimized it's one line. Hidden in instances and pet battles. Moved in Edit Mode.

local UI = ns.UI
local WIDTH = 260
local PAD = 10
local LINE_H = 16
local ITEM_ROWS = 3
local DEFAULT_POINT = { "TOPRIGHT", "TOPRIGHT", -260, -230 }
local TIER_ATLAS = "Professions-ChatIcon-Quality-Tier%d"

local db
local frame
local elapsed = 0

local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(self, event, ...)
	self[event](self, ...)
end)

function ns.GatherTracker_Init(saved)
	db = saved
	for _, event in ipairs({ "PET_BATTLE_OPENING_START", "PET_BATTLE_CLOSE", "PLAYER_ENTERING_WORLD" }) do
		events:RegisterEvent(event)
	end
end

---------------------------------------------------------------------------------------------------------------
-- Item labels (the page uses them too)

-- A gathered reagent's rank as the game's icon ("" without a rank).
function ns.Gather_RankMarkup(itemID, rank, size)
	if not rank then
		return ""
	end
	size = size or 14
	local ok, info = pcall(C_TradeSkillUI.GetItemReagentQualityInfo, itemID)
	for _, atlas in ipairs({ ok and type(info) == "table" and info.iconChat or false, TIER_ATLAS:format(rank) }) do
		if atlas and C_Texture.GetAtlasInfo(atlas) then
			return CreateAtlasMarkup(atlas, size, size)
		end
	end
	return UI.Wrap("R" .. rank, "textMuted")
end

-- Name in its rarity color (the item's name loads later when it isn't cached yet: the link's name until then).
function ns.Gather_ItemName(itemID, link)
	local name = itemID and C_Item.GetItemNameByID(itemID)
	if not name and link then
		name = link:match("%[(.-)%]")
	end
	name = name or ("item " .. tostring(itemID))
	local quality = itemID and C_Item.GetItemQualityByID(itemID)
	if not quality then
		return name
	end
	local color = ITEM_QUALITY_COLORS[quality]
	return color and color.color:WrapTextInColorCode(name) or name
end

function ns.Gather_ItemIcon(itemID, size)
	local icon = itemID and C_Item.GetItemIconByID(itemID)
	return icon and ("|T%s:%d:%d:0:0:64:64:5:59:5:59|t "):format(icon, size, size) or ""
end

---------------------------------------------------------------------------------------------------------------
-- Frame

local function SavePoint()
	db.tracker.point = UI.TopLeftPoint(frame)
end

local function Place()
	local p = db.tracker.point or DEFAULT_POINT
	frame:ClearAllPoints()
	frame:SetPoint(p[1], UIParent, p[2], p[3], p[4])
end

local function Line(role, font)
	local fs = UI.Text(frame, 11, role or "text", font)
	fs:SetWordWrap(false)
	fs:SetJustifyH("LEFT")
	return fs
end

local function Build()
	frame = CreateFrame("Frame", nil, UIParent)
	frame:SetSize(WIDTH, 60)
	frame:SetFrameStrata("MEDIUM")
	frame:SetClampedToScreen(true)
	frame:SetMovable(true)
	frame:Hide()
	UI.Panel(frame, { alpha = 0.55, subtle = true })

	frame.icon = frame:CreateTexture(nil, "ARTWORK")
	frame.icon:SetSize(16, 16)
	frame.icon:SetPoint("TOPLEFT", PAD, -7)
	frame.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

	frame.endButton = UI.Button(frame, 38, "End")
	frame.endButton:SetHeight(16)
	frame.endButton:SetPoint("TOPRIGHT", -26, -6)
	frame.endButton:SetScript("OnClick", function()
		ns.Gather_End("manual")
	end)
	frame.endButton:HookScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		GameTooltip:SetText("End this run", 1, 1, 1)
		GameTooltip:Show()
	end)
	frame.endButton:HookScript("OnLeave", function()
		GameTooltip:Hide()
	end)

	frame.time = UI.Text(frame, 12, "text", "number")
	frame.time:SetJustifyH("RIGHT")
	frame.time:SetPoint("RIGHT", frame.endButton, "LEFT", -8, 0)
	frame.title = UI.Text(frame, 12, "heading", "title")
	frame.title:SetWordWrap(false)
	frame.title:SetPoint("LEFT", frame.icon, "RIGHT", 6, 0)
	frame.title:SetPoint("RIGHT", frame.time, "LEFT", -6, 0)

	frame.nodes = Line("text", "number")
	frame.value = Line("text", "number")
	frame.value:SetJustifyH("RIGHT")
	frame.items = {}
	for i = 1, ITEM_ROWS do
		frame.items[i] = Line("text")
	end
	frame.finds = Line("accent")
	frame.progress = Line("textMuted")

	frame.collapse = UI.CollapseButton(frame, function()
		return db.tracker.collapsed
	end, function()
		db.tracker.collapsed = not db.tracker.collapsed
		ns.GatherTracker_Refresh()
	end)

	frame:SetScript("OnUpdate", function(_, dt)
		elapsed = elapsed + dt
		if elapsed >= 1 then
			elapsed = 0
			ns.GatherTracker_Tick()
		end
	end)
end

---------------------------------------------------------------------------------------------------------------
-- Content

-- A made-up run for Edit Mode when no run is on.
local function SampleRun()
	local now = GetServerTime()
	local run = ns.Gather_NewRun("preview", now - 1930, {})
	for i = 1, 42 do
		ns.Gather_AddGather(run, { at = now - 1930 + i * 45, kind = "mining", sources = { "GameObject-0-0-0-0-1-" .. i } })
	end
	ns.Gather_AddItem(run, { itemID = 210930, count = 86, unit = 3000, rank = 2, kind = "mining" })
	ns.Gather_AddItem(run, { itemID = 210936, count = 31, unit = 4000, rank = 1, kind = "mining" })
	ns.Gather_AddItem(run, { itemID = 213610, count = 12, unit = 1500, kind = "mining" })
	run.skill[2881] = { from = 92, to = 95 }
	run.knowledge[2881] = { last = 4, gained = 2 }
	return run
end

local function TopItems(run, n)
	local list = {}
	for key, e in pairs(run.items or {}) do
		list[#list + 1] = { key = key, e = e }
	end
	table.sort(list, function(a, b)
		if a.e.v ~= b.e.v then
			return a.e.v > b.e.v
		end
		return a.e.n > b.e.n
	end)
	local top = {}
	for i = 1, math.min(n, #list) do
		top[i] = list[i]
	end
	return top
end

local function FindsText(run)
	local parts = {}
	for i = #run.finds, math.max(#run.finds - 2, 1), -1 do
		local f = run.finds[i]
		if f.kind == "item" then
			parts[#parts + 1] = ns.Gather_ItemName(f.itemID, f.link)
		else
			parts[#parts + 1] = "knowledge drop"
		end
	end
	if #parts == 0 then
		return nil
	end
	return "Finds: " .. table.concat(parts, " · ")
end

local function ProfName(line)
	for _, p in ipairs(ns.GatherDetect_Profs and ns.GatherDetect_Profs() or {}) do
		if (p.def and p.def.child) == line or p.base == line then
			return p.name
		end
	end
	return nil
end

-- "Mining 92 -> 95 (+3) · +2 knowledge", only what moved.
function ns.Gather_ProgressText(run, sample)
	local parts = {}
	for line, s in pairs(run.skill or {}) do
		if s.to and s.from and s.to > s.from then
			parts[#parts + 1] = ("%s %d -> %d (+%d)"):format(sample and "Mining" or ProfName(line) or "Skill", s.from, s.to,
				s.to - s.from)
		end
	end
	local gained = 0
	for _, k in pairs(run.knowledge or {}) do
		gained = gained + (k.gained or 0)
	end
	if gained > 0 then
		parts[#parts + 1] = ("+%d knowledge"):format(gained)
	end
	if #parts == 0 then
		return nil
	end
	return table.concat(parts, " · ")
end

local function Shown()
	if not (db and db.tracker.shown and ns.gatherModule and ns.gatherModule.active) then
		return false
	end
	if ns.EditMode_Active() then
		return true
	end
	if not db.run then
		return false
	end
	if C_PetBattles and C_PetBattles.IsInBattle() then
		return false
	end
	return not IsInInstance()
end

-- Places a full-width line at y and returns the y below it.
local function PlaceLine(fs, y)
	fs:ClearAllPoints()
	fs:SetPoint("TOPLEFT", PAD, -y)
	fs:SetPoint("RIGHT", -PAD, 0)
	fs:Show()
	return y + LINE_H
end

local current, currentSample

function ns.GatherTracker_Tick()
	if not (frame and current) then
		return
	end
	local live = not currentSample
	local n = ns.Gather_Numbers(current, GetServerTime(), live)
	local clock = ns.Gather_DurationText(n.duration)
	if db.tracker.collapsed then
		local perHour = n.valuePerHour and (ns.Gather_Money(n.valuePerHour) .. "/h") or (n.nodesPerHour .. "/h")
		frame.title:SetText(("%d nodes · %s"):format(n.nodes, perHour))
	end
	frame.time:SetText(clock)
end

function ns.GatherTracker_Refresh()
	if not Shown() then
		if frame then
			frame:Hide()
		end
		current = nil
		return
	end
	if not frame then
		Build()
		Place()
	end
	local run, sample = db.run, false
	if not run then
		run, sample = SampleRun(), true
	end
	current, currentSample = run, sample
	local n = ns.Gather_Numbers(run, GetServerTime(), not sample)
	frame.icon:SetTexture(ns.GATHER_KIND_ICONS[n.mainKind or "mining"])
	frame.endButton:SetShown(not sample)

	for _, fs in ipairs({ frame.nodes, frame.value, frame.finds, frame.progress }) do
		fs:Hide()
	end
	for _, fs in ipairs(frame.items) do
		fs:Hide()
	end

	if db.tracker.collapsed then
		frame:SetHeight(30)
		ns.GatherTracker_Tick()
		frame:Show()
		return
	end
	frame.title:SetText(ns.Gather_RunTitle(n.mainKind))
	local y = 28
	frame.nodes:ClearAllPoints()
	frame.nodes:SetPoint("TOPLEFT", PAD, -y)
	frame.nodes:SetText(("%d %s · %d/h"):format(n.nodes, n.nodes == 1 and "node" or "nodes", n.nodesPerHour))
	frame.nodes:Show()
	frame.value:ClearAllPoints()
	frame.value:SetPoint("TOPRIGHT", -PAD, -y)
	if n.value then
		frame.value:SetText(("%s · %s/h"):format(ns.Gather_Money(n.value), ns.Gather_Money(n.valuePerHour)))
		UI.SetTextRole(frame.value, "text")
	else
		frame.value:SetText("no prices")
		UI.SetTextRole(frame.value, "textMuted")
	end
	frame.value:Show()
	y = y + LINE_H + 2
	for i, item in ipairs(TopItems(run, ITEM_ROWS)) do
		local e, itemID = item.e, type(item.key) == "number" and item.key or nil
		local fs = frame.items[i]
		fs:SetText(("%s%s %s  %s"):format(ns.Gather_ItemIcon(itemID, 14), ns.Gather_ItemName(itemID, e.link),
			ns.Gather_RankMarkup(itemID, e.rank, 14), UI.Wrap("x" .. e.n, "textMuted")))
		y = PlaceLine(fs, y)
	end
	local finds = FindsText(run)
	if finds then
		frame.finds:SetText(finds)
		y = PlaceLine(frame.finds, y)
	end
	local progress = ns.Gather_ProgressText(run, sample)
	if progress then
		frame.progress:SetText(progress)
		y = PlaceLine(frame.progress, y)
	end
	frame:SetHeight(y + 6)
	ns.GatherTracker_Tick()
	frame:Show()
end

function ns.GatherTracker_ResetPosition()
	db.tracker.point = nil
	if frame then
		Place()
	end
end

function events:PET_BATTLE_OPENING_START()
	ns.GatherTracker_Refresh()
end
events.PET_BATTLE_CLOSE = events.PET_BATTLE_OPENING_START
events.PLAYER_ENTERING_WORLD = events.PET_BATTLE_OPENING_START

ns.EditMode_Register({
	name = "Gathering run",
	frame = function()
		return frame
	end,
	refresh = function()
		ns.GatherTracker_Refresh()
	end,
	saved = SavePoint,
})
