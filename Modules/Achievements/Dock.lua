local addonName, ns = ...

-- Almost Done: the list docked to the right of the Achievements window. Two tabs: List (search, reward and sort
-- dropdowns, a filters menu, the threshold, the rows) and Metas (the big expansion metas and the metas you're close on; open one
-- to see its children). Hovering a row shows its tooltip beside the dock and, for mounts, pets and appearances, a
-- reward preview next to the tooltip. When closed, a small tab on the window's edge opens it again. Built the
-- first time the Achievements window shows.

local UI = ns.UI
local GOLD, WHITE, GREY, DIM = UI.GOLD, UI.WHITE, UI.GREY, UI.DIM
local GREEN = { 0.5, 0.88, 0.5 }
local TITLE_FONT = "Fonts\\MORPHEUS.TTF"
local WIDTH = 380
local ROW_H = 34
local META_ROW_H = 28
local INDENT = 16
local ICON = 24
local TOOLTIP_GAP = 18 -- from a row's right edge to the tooltip: past the scroll thumb and the dock's edge
local REWARD_FILTERS = {
	{ value = "any", text = "Any reward" },
	{ value = "reward", text = "Has a reward" },
	{ value = "new", text = "New rewards" },
	{ value = "mount", text = "Mounts" },
	{ value = "pet", text = "Pets" },
	{ value = "toy", text = "Toys" },
	{ value = "title", text = "Titles" },
	{ value = "appearance", text = "Appearances" },
	{ value = "decor", text = "Decor" },
}
local SORTS = {
	{ value = "percent", text = "Percent" },
	{ value = "steps", text = "Fewest steps" },
	{ value = "points", text = "Points" },
	{ value = "name", text = "Name" },
}

local dock, handle, waiter
local hooked = false
local tab = "list"
local searchText = ""
local clicked -- the last clicked record (List tab), shown in gold
local metaPath = {} -- meta IDs opened in the Metas tab, last = shown
local metaExpanded = {} -- [child meta id] = true
local listRows, metaRows = {}, {}

local function DB()
	return ns.achDB
end

local function Active()
	return ns.achModule.active
end

-- Preview (Panel/ModelPreview.lua) ------------------------------------------------------------------------

local function HidePreview()
	ns.ModelPreview_Hide(dock.preview)
end

-- After the row's tooltip is shown: the reward's model next to it, when it has one.
local function ShowPreview(record)
	local info = record and DB().preview and ns.Ach_RewardInfo(record)
	local model
	if info and (info.type == "mount" or info.type == "pet") then
		model = { sceneID = info.sceneID, displayID = info.displayID, selfMount = info.selfMount }
	elseif info and info.type == "appearance" and info.link then
		model = { link = info.link, key = "item:" .. info.itemID }
	end
	if model then
		model.name = info.name or record.reward
		model.sub = (ns.ACH_REWARD_NAMES[info.type] or "") .. (info.owned and "  -  |cff80e080owned|r" or "")
	end
	ns.ModelPreview_Show(dock.preview, model)
end

-- Tooltips and menus -----------------------------------------------------------------------------------------

local function AddExtraLines(record)
	local info = ns.Ach_RewardInfo(record)
	if info then
		local kind = ns.ACH_REWARD_NAMES[info.type] or "Reward"
		if info.owned then
			GameTooltip:AddLine(kind .. " already owned", 0.5, 0.5, 0.5)
		elseif info.type ~= "other" then
			GameTooltip:AddLine("New " .. kind:lower(), GREEN[1], GREEN[2], GREEN[3])
		end
	end
	local parents = ns.Ach_ParentsOf(record.id)
	for i = 1, math.min(#parents, 2) do
		local _, name = GetAchievementInfo(parents[i])
		if name then
			GameTooltip:AddLine("Part of: " .. name, GOLD[1], GOLD[2], GOLD[3])
		end
	end
	GameTooltip:AddLine("Click: open  -  Shift-click: link in chat  -  Right-click: pin, ignore", 0.5, 0.5, 0.5)
end

local function ShowAchievementTooltip(owner, id, record)
	local link = GetAchievementLink(id)
	if not link then
		return
	end
	GameTooltip:SetOwner(owner, "ANCHOR_NONE")
	GameTooltip:SetPoint("TOPLEFT", owner, "TOPRIGHT", TOOLTIP_GAP, 0)
	GameTooltip:SetHyperlink(link)
	if record then
		AddExtraLines(record)
	end
	GameTooltip:Show()
end

local Refresh, ShowMeta

local function RowMenu(owner, record)
	MenuUtil.CreateContextMenu(owner, function(_, root)
		root:CreateTitle(record.name)
		if ns.Ach_IsPinned(record.id) then
			root:CreateButton("Unpin", function()
				ns.Ach_Unpin(record.id)
			end)
		else
			root:CreateButton("Pin to the tracker", function()
				ns.Ach_Pin(record.id)
			end)
		end
		if ns.Ach_IsIgnored(record.id) then
			root:CreateButton("Stop ignoring", function()
				ns.Ach_SetIgnored(record.id, false)
			end)
		else
			root:CreateButton("Ignore", function()
				ns.Ach_SetIgnored(record.id, true)
			end)
		end
		local parents = ns.Ach_ParentsOf(record.id)
		for i = 1, math.min(#parents, 3) do
			local _, name = GetAchievementInfo(parents[i])
			if name then
				root:CreateButton("Show meta: " .. name, function()
					ShowMeta(parents[i])
				end)
			end
		end
	end)
end

-- Filters feed the tracker's fill too.
local function FiltersChanged()
	Refresh()
	ns.AchTracker_Refresh()
end

local function Toggle(tbl, key)
	return function()
		if tbl[key] == false then
			tbl[key] = nil
		else
			tbl[key] = false
		end
		FiltersChanged()
	end
end

local function FilterMenu(owner)
	local db = DB()
	MenuUtil.CreateContextMenu(owner, function(_, root)
		local tops, expansions = ns.Ach_FilterChoices()
		local categories = root:CreateButton("Categories")
		for _, top in ipairs(tops) do
			categories:CreateCheckbox(top, function()
				return db.categories[top] ~= false
			end, Toggle(db.categories, top))
		end
		local exp = root:CreateButton("Expansions")
		for _, e in ipairs(expansions) do
			exp:CreateCheckbox(e, function()
				return db.expansions[e] ~= false
			end, Toggle(db.expansions, e))
		end
		local function Radio(menu, key, value, text)
			menu:CreateRadio(text, function()
				return db[key] == value
			end, function()
				db[key] = value
				FiltersChanged()
			end)
		end
		local prof = root:CreateButton("Professions")
		Radio(prof, "professions", "mine", "My professions")
		Radio(prof, "professions", "all", "All")
		Radio(prof, "professions", "none", "None")
		local ev = root:CreateButton("World events")
		Radio(ev, "events", "running", "Running now")
		Radio(ev, "events", "all", "All")
		Radio(ev, "events", "none", "None")
		local scope = root:CreateButton("Completed means")
		for _, choice in ipairs({ { "account", "Done on the account" }, { "character", "Done by this character" } }) do
			scope:CreateRadio(choice[2], function()
				return db.scope == choice[1]
			end, function()
				if db.scope ~= choice[1] then
					db.scope = choice[1]
					ns.Ach_StartScan()
				end
			end)
		end
		root:CreateDivider()
		root:CreateCheckbox("Show ignored", function()
			return db.showIgnored
		end, function()
			db.showIgnored = not db.showIgnored
			FiltersChanged()
		end)
		root:CreateButton("Reset filters", function()
			wipe(db.categories)
			wipe(db.expansions)
			db.professions, db.events, db.reward = "mine", "running", "any"
			FiltersChanged()
		end)
	end)
end

-- List tab ----------------------------------------------------------------------------------------------------

local function NewListRow()
	local row = CreateFrame("Button", nil, dock.list.content)
	row:SetHeight(ROW_H)
	row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	row.hover = row:CreateTexture(nil, "BACKGROUND")
	row.hover:SetAllPoints()
	row.hover:SetColorTexture(1, 1, 1, 0.05)
	row.hover:Hide()
	row.pin = row:CreateTexture(nil, "ARTWORK")
	row.pin:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 1)
	row.pin:SetPoint("TOPLEFT", 0, -4)
	row.pin:SetPoint("BOTTOMLEFT", 0, 4)
	row.pin:SetWidth(2)
	row.icon = row:CreateTexture(nil, "ARTWORK")
	row.icon:SetSize(ICON, ICON)
	row.icon:SetPoint("LEFT", 8, 0)
	row.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	row.reward = row:CreateTexture(nil, "ARTWORK")
	row.reward:SetSize(16, 16)
	row.reward:SetPoint("RIGHT", -4, 0)
	row.reward:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	row.percent = UI.Text(row, 11, GREY)
	row.percent:SetPoint("TOPRIGHT", row.reward, "TOPLEFT", -8, 1)
	row.percent:SetJustifyH("RIGHT")
	row.name = UI.Text(row, 12, WHITE)
	row.name:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 8, 0)
	row.name:SetPoint("RIGHT", row.percent, "LEFT", -6, 0)
	row.name:SetWordWrap(false)
	row.track = row:CreateTexture(nil, "ARTWORK")
	row.track:SetColorTexture(1, 1, 1, 0.12)
	row.track:SetHeight(2)
	row.track:SetPoint("BOTTOMLEFT", row.icon, "BOTTOMRIGHT", 8, 2)
	row.track:SetPoint("RIGHT", row.reward, "LEFT", -8, 0)
	row.fill = row:CreateTexture(nil, "OVERLAY")
	row.fill:SetHeight(2)
	row.fill:SetPoint("LEFT", row.track, "LEFT")
	row:SetScript("OnEnter", function(self)
		self.hover:Show()
		ShowAchievementTooltip(self, self.record.id, self.record)
		ShowPreview(self.record)
	end)
	row:SetScript("OnLeave", function(self)
		self.hover:Hide()
		GameTooltip:Hide()
		HidePreview()
	end)
	row:SetScript("OnClick", function(self, button)
		local record = self.record
		if button == "RightButton" then
			RowMenu(self, record)
		elseif IsModifiedClick("CHATLINK") then
			ns.Ach_Link(record.id)
		else
			clicked = record
			ns.Ach_Open(record.id)
			Refresh()
		end
	end)
	return row
end

local function SetListRow(row, record)
	row.record = record
	local ignored = ns.Ach_IsIgnored(record.id)
	row.icon:SetTexture(record.icon)
	row.icon:SetDesaturated(ignored)
	row.name:SetText(record.name)
	local c = ignored and DIM or ((clicked and clicked.id == record.id) and GOLD or WHITE)
	row.name:SetTextColor(c[1], c[2], c[3])
	row.percent:SetText(ns.Ach_ProgressText(record, "  "))
	row.pin:SetShown(ns.Ach_IsPinned(record.id))
	local info = ns.Ach_RewardInfo(record)
	row.reward:SetShown(info ~= nil)
	if info then
		row.reward:SetTexture(ns.ACH_REWARD_ICONS[info.type])
		row.reward:SetDesaturated(info.owned)
		row.reward:SetAlpha(info.owned and 0.4 or 1)
	end
	local width = row.track:GetWidth()
	if width <= 1 then
		width = WIDTH - 60 - ICON
	end
	row.fill:SetWidth(math.max(width * math.min(record.percent, 100) / 100, 1))
	local fc = record.percent >= 100 and GREEN or GOLD
	row.fill:SetColorTexture(fc[1], fc[2], fc[3], 0.9)
end

local function RefreshList()
	local list = ns.Ach_List(searchText)
	local content = dock.list.content
	for i, record in ipairs(list) do
		local row = listRows[i] or NewListRow()
		listRows[i] = row
		row:ClearAllPoints()
		row:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -(i - 1) * ROW_H)
		row:SetPoint("RIGHT", content, "RIGHT")
		SetListRow(row, record)
		row:Show()
	end
	for i = #list + 1, #listRows do
		listRows[i]:Hide()
	end
	dock.list:SetContentHeight(#list * ROW_H)

	local progress = ns.Ach_ScanProgress()
	local empty = dock.empty
	empty:SetShown(#list == 0)
	if #list == 0 then
		if progress and not next(ns.Ach_Records()) then
			empty:SetText("Scanning your achievements...")
		else
			empty:SetText(("Nothing at %d%% or more with these filters."):format(DB().threshold))
		end
	end
	dock.count:SetText(("%s at %d%% or more"):format(#list == 1 and "1 achievement" or (#list .. " achievements"),
		DB().threshold))
	dock.status:SetText(progress and ("Scanning %d%%"):format(progress * 100) or "")
	dock.threshold:SetValue(DB().threshold)
	dock.rewardFilter:Refresh()
	dock.sortBy:Refresh()
end

-- Metas tab ---------------------------------------------------------------------------------------------------

local function NewMetaRow()
	local row = CreateFrame("Button", nil, dock.metas.content)
	row:SetHeight(META_ROW_H)
	row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	row.hover = row:CreateTexture(nil, "BACKGROUND")
	row.hover:SetAllPoints()
	row.hover:SetColorTexture(1, 1, 1, 0.05)
	row.hover:Hide()
	row.toggle = UI.Text(row, 12, GREY)
	row.toggle:SetWidth(10)
	row.icon = row:CreateTexture(nil, "ARTWORK")
	row.icon:SetSize(20, 20)
	row.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	row.extra = UI.Text(row, 11, GREY)
	row.extra:SetPoint("RIGHT", -6, 0)
	row.extra:SetJustifyH("RIGHT")
	row.name = UI.Text(row, 12, WHITE)
	row.name:SetPoint("LEFT", row.icon, "RIGHT", 8, 0)
	row.name:SetPoint("RIGHT", row.extra, "LEFT", -8, 0)
	row.name:SetWordWrap(false)
	row:SetScript("OnEnter", function(self)
		self.hover:SetShown(self.id ~= nil)
		if self.id then
			ShowAchievementTooltip(self, self.id, ns.Ach_Records()[self.id])
		end
	end)
	row:SetScript("OnLeave", function(self)
		self.hover:Hide()
		GameTooltip:Hide()
	end)
	row:SetScript("OnClick", function(self, button)
		if not self.id then
			return
		end
		if button == "RightButton" then
			local record = ns.Ach_Records()[self.id]
			if record then
				RowMenu(self, record)
			end
		elseif IsModifiedClick("CHATLINK") then
			ns.Ach_Link(self.id)
		elseif self.onClick then
			self.onClick()
		else
			ns.Ach_Open(self.id)
		end
	end)
	return row
end

local metaUsed = 0

local function MetaRow(y, indent, opts)
	metaUsed = metaUsed + 1
	local row = metaRows[metaUsed] or NewMetaRow()
	metaRows[metaUsed] = row
	row:ClearAllPoints()
	row:SetPoint("TOPLEFT", dock.metas.content, "TOPLEFT", 0, -y)
	row:SetPoint("RIGHT", dock.metas.content, "RIGHT")
	row.id, row.onClick = opts.id, opts.onClick
	row.toggle:ClearAllPoints()
	row.toggle:SetPoint("LEFT", indent + 2, 0)
	row.toggle:SetText(opts.toggle or "")
	row.icon:ClearAllPoints()
	row.icon:SetPoint("LEFT", indent + 14, 0)
	row.icon:SetShown(opts.icon ~= nil)
	row.icon:SetTexture(opts.icon)
	row.icon:SetDesaturated(opts.done == true)
	if opts.icon then
		row.name:SetPoint("LEFT", row.icon, "RIGHT", 8, 0)
	else
		row.name:SetPoint("LEFT", indent + 4, 0)
	end
	row.name:SetText(opts.text)
	local c = opts.color or WHITE
	row.name:SetTextColor(c[1], c[2], c[3])
	row.extra:SetText(opts.extra or "")
	row:Show()
	return META_ROW_H
end

local function Header(y, text)
	return MetaRow(y, 0, { text = ns.Spaced(text), color = GREY })
end

local function MetaExtra(node)
	return ("%d%%  %d/%d"):format(math.floor(node.metaPercent), node.metaDone, node.metaTotal)
end

local function ChildExtra(child)
	if child.completed then
		return "|cff80e080done|r"
	end
	if child.percent then
		return ns.Ach_ProgressText(child, "  ")
	end
	return ""
end

local function ChildRows(y, node, indent, depth)
	local h = 0
	for _, child in ipairs(node.children) do
		local key = child.id
		local open = metaExpanded[key]
		h = h + MetaRow(y + h, indent, {
			id = child.id, icon = child.icon, text = child.name, done = child.completed,
			color = child.completed and DIM or WHITE, extra = ChildExtra(child),
			toggle = child.isMeta and (open and "-" or "+") or nil,
			onClick = child.isMeta and function()
				metaExpanded[key] = not open or nil
				Refresh()
			end or nil,
		})
		if child.isMeta and open and depth < 4 then
			local sub = ns.Ach_MetaNode(child.id)
			if sub then
				h = h + ChildRows(y + h, sub, indent + INDENT, depth + 1)
			end
		end
	end
	return h
end

local function RefreshMetas()
	metaUsed = 0
	local y = 0
	local current = metaPath[#metaPath]
	dock.back:SetShown(current ~= nil)
	if current then
		local node = ns.Ach_MetaNode(current)
		if node then
			y = y + MetaRow(y, 0, { id = node.id, icon = node.icon, text = node.name, color = GOLD,
				extra = node.completed and "|cff80e080done|r" or MetaExtra(node) })
			if node.reward ~= "" then
				y = y + MetaRow(y, 0, { text = node.reward, color = GREEN })
			end
			y = y + ChildRows(y, node, 0, 1)
		end
	else
		y = y + Header(y, "Expansion metas")
		for _, root in ipairs(ns.Ach_MetaRoots()) do
			local _, name, _, completed, _, _, _, _, _, icon = GetAchievementInfo(root.id)
			if name then
				y = y + MetaRow(y, 0, { id = root.id, icon = icon, text = name, done = completed,
					color = completed and DIM or WHITE, extra = root.expansion, onClick = function()
						ShowMeta(root.id)
					end })
			end
		end
		local ids, count = ns.Ach_MetasOf(ns.Ach_List(""))
		if #ids > 0 then
			y = y + Header(y, "Metas you're close on")
		end
		for i = 1, math.min(#ids, 25) do
			local id = ids[i]
			local _, name, _, _, _, _, _, _, _, icon = GetAchievementInfo(id)
			if name then
				y = y + MetaRow(y, 0, { id = id, icon = icon, text = name,
					extra = count[id] == 1 and "1 listed" or (count[id] .. " listed"), onClick = function()
						ShowMeta(id)
					end })
			end
		end
	end
	for i = metaUsed + 1, #metaRows do
		metaRows[i]:Hide()
	end
	dock.metas:SetContentHeight(y)
	dock.count:SetText("")
	dock.status:SetText("")
end

-- Frame ---------------------------------------------------------------------------------------------------------

local function SetTab(which)
	tab = which
	dock.listTab:Set("List", which == "list")
	dock.metaTab:Set("Metas", which == "metas")
	dock.listView:SetShown(which == "list")
	dock.metaView:SetShown(which == "metas")
	Refresh()
end

function ShowMeta(id)
	if metaPath[#metaPath] ~= id then
		metaPath[#metaPath + 1] = id
	end
	SetTab("metas")
end

local function CreateTab(parent, text, which)
	local b = CreateFrame("Button", nil, parent)
	b:SetHeight(20)
	b.text = UI.Text(b, 13, GREY)
	b.text:SetPoint("BOTTOMLEFT", 0, 5)
	b.bar = b:CreateTexture(nil, "ARTWORK")
	b.bar:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 1)
	b.bar:SetHeight(2)
	b.bar:SetPoint("BOTTOMLEFT")
	b.bar:SetPoint("BOTTOMRIGHT")
	function b:Set(label, selected)
		self.selected = selected
		self.text:SetText(label)
		self:SetWidth(self.text:GetStringWidth())
		local c = selected and GOLD or GREY
		self.text:SetTextColor(c[1], c[2], c[3])
		self.bar:SetShown(selected)
	end
	b:SetScript("OnClick", function()
		if tab ~= which then
			PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
			SetTab(which)
		end
	end)
	b:Set(text, which == tab)
	return b
end

local function CreateSearch(parent)
	local box = CreateFrame("EditBox", nil, parent)
	box:SetHeight(22)
	box:SetAutoFocus(false)
	box:SetFont(STANDARD_TEXT_FONT, 12, "")
	box:SetTextColor(WHITE[1], WHITE[2], WHITE[3])
	box:SetTextInsets(8, 8, 0, 0)
	local bg = box:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints()
	bg:SetColorTexture(UI.BOX[1], UI.BOX[2], UI.BOX[3], UI.BOX[4])
	UI.Border(box, GOLD[1], GOLD[2], GOLD[3], 0.35)
	local placeholder = UI.Text(box, 12, DIM)
	placeholder:SetPoint("LEFT", 8, 0)
	placeholder:SetText("Search name, reward or step")
	box:SetScript("OnTextChanged", function(self)
		local text = self:GetText()
		placeholder:SetShown(text == "")
		searchText = strtrim(text)
		Refresh()
	end)
	box:SetScript("OnEscapePressed", function(self)
		self:SetText("")
		self:ClearFocus()
	end)
	box:SetScript("OnEnterPressed", box.ClearFocus)
	return box
end

local function CreateListView()
	local view = CreateFrame("Frame", nil, dock)
	view:SetPoint("TOPLEFT", dock.tabLine, "BOTTOMLEFT", 0, -8)
	view:SetPoint("BOTTOMRIGHT")
	dock.listView = view

	local search = CreateSearch(view)
	search:SetPoint("TOPLEFT", 0, 0)
	search:SetPoint("RIGHT", -14, 0)

	local reward = UI.Dropdown(view, 130)
	reward:SetPoint("TOPLEFT", search, "BOTTOMLEFT", 0, -8)

	local sortBy = UI.Dropdown(view, 120)
	sortBy:SetPoint("LEFT", reward, "RIGHT", 6, 0)

	local filters = UI.Button(view, 60, "Filters")
	filters:SetPoint("TOPRIGHT", search, "BOTTOMRIGHT", 0, -8)
	filters:SetScript("OnClick", FilterMenu)

	-- Threshold on its own row: label, a slider filling the middle, the value on the right.
	local label = UI.Text(view, 11, GREY)
	label:SetPoint("TOPLEFT", reward, "BOTTOMLEFT", 0, -12)
	label:SetText("Almost done at")
	local value = UI.Text(view, 11, WHITE)
	value:SetPoint("RIGHT", search, "RIGHT", 0, 0)
	value:SetPoint("TOP", label, "TOP")
	value:SetJustifyH("RIGHT")
	value:SetWidth(40)
	local slider = UI.Slider(view, 100)
	slider:SetPoint("LEFT", label, "RIGHT", 10, 0)
	slider:SetPoint("RIGHT", value, "LEFT", -10, 0)
	slider:SetMinMaxValues(50, 100)
	slider:SetValueStep(5)
	slider.valueText = value
	slider.format = function(v)
		return v .. "%"
	end
	slider.onChange = function(v)
		DB().threshold = v
		ns.Ach_RebuildWatch()
		Refresh()
		ns.AchTracker_Refresh()
	end
	dock.threshold = slider

	sortBy.getValue = function()
		return DB().sort
	end
	sortBy.setValue = function(v)
		DB().sort = v
		Refresh()
	end
	sortBy.choices = function()
		return SORTS
	end
	dock.sortBy = sortBy

	reward.getValue = function()
		return DB().reward
	end
	reward.setValue = function(v)
		DB().reward = v
		Refresh()
		ns.AchTracker_Refresh()
	end
	reward.choices = function()
		return REWARD_FILTERS
	end
	dock.rewardFilter = reward

	local list = UI.Scroll(view)
	list:SetPoint("TOPLEFT", search, "BOTTOMLEFT", -2, -64)
	list:SetPoint("BOTTOMRIGHT", -14, 12)
	list:SetScript("OnVerticalScroll", function()
		HidePreview()
	end)
	list.onWidthChanged = function()
		if dock:IsVisible() and tab == "list" then
			RefreshList()
		end
	end
	dock.list = list

	dock.empty = UI.Text(view, 12, GREY)
	dock.empty:SetPoint("TOP", list, "TOP", 0, -30)
	dock.empty:SetWidth(WIDTH - 60)
	dock.empty:SetJustifyH("CENTER")
	dock.empty:SetWordWrap(true)

	dock.preview = ns.ModelPreview_Create(dock)
end

local function CreateMetaView()
	local view = CreateFrame("Frame", nil, dock)
	view:SetPoint("TOPLEFT", dock.tabLine, "BOTTOMLEFT", 0, -8)
	view:SetPoint("BOTTOMRIGHT")
	view:Hide()
	dock.metaView = view
	local back = UI.Button(view, 60, "< Back")
	back:SetPoint("TOPLEFT")
	back:SetScript("OnClick", function()
		table.remove(metaPath)
		Refresh()
	end)
	dock.back = back
	local metas = UI.Scroll(view)
	metas:SetPoint("TOPLEFT", 0, -28)
	metas:SetPoint("BOTTOMRIGHT", -14, 12)
	dock.metas = metas
end

local function SetDockOpen(open)
	DB().dock.open = open
	ns.AchDock_Refresh()
end

local function Build()
	local parent = AchievementFrame
	dock = CreateFrame("Frame", nil, parent)
	dock:SetWidth(WIDTH)
	dock:SetPoint("TOPLEFT", parent, "TOPRIGHT", 2, 0)
	dock:SetPoint("BOTTOMLEFT", parent, "BOTTOMRIGHT", 2, 0)
	dock:EnableMouse(true)
	dock:SetFrameStrata(parent:GetFrameStrata())
	local bg = dock:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints()
	bg:SetColorTexture(UI.BG[1], UI.BG[2], UI.BG[3], UI.BG[4])
	UI.Border(dock, GOLD[1], GOLD[2], GOLD[3], 0.45)

	local title = UI.Text(dock, 18, GOLD, TITLE_FONT)
	title:SetPoint("TOPLEFT", 14, -12)
	title:SetText("Almost Done")
	local close = UI.Button(dock, 20, "x")
	close:SetPoint("TOPRIGHT", -8, -10)
	close:SetScript("OnClick", function()
		SetDockOpen(false)
	end)
	local settings = UI.Button(dock, 20, "")
	settings:SetPoint("RIGHT", close, "LEFT", -6, 0)
	local gear = settings:CreateTexture(nil, "ARTWORK")
	gear:SetSize(14, 14)
	gear:SetPoint("CENTER")
	gear:SetTexture(UI.GEAR)
	gear:SetTexCoord(0, 0.5, 0, 0.5)
	gear:SetVertexColor(GOLD[1], GOLD[2], GOLD[3])
	settings:HookScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:SetText("Almost Done settings", GOLD[1], GOLD[2], GOLD[3])
		GameTooltip:AddLine("Threshold, tracker, toasts.", 1, 1, 1)
		GameTooltip:Show()
	end)
	settings:HookScript("OnLeave", function()
		GameTooltip:Hide()
	end)
	settings:SetScript("OnClick", function()
		ns.Panel_OpenModule("ach")
	end)
	local rescan = UI.Button(dock, 58, "Rescan")
	rescan:SetPoint("RIGHT", settings, "LEFT", -6, 0)
	rescan:SetScript("OnClick", function()
		ns.Ach_StartScan()
	end)
	dock.status = UI.Text(dock, 11, GOLD)
	dock.status:SetPoint("RIGHT", rescan, "LEFT", -8, 0)
	dock.count = UI.Text(dock, 11, GREY)
	dock.count:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)

	dock.listTab = CreateTab(dock, "List", "list")
	dock.listTab:SetPoint("TOPLEFT", dock.count, "BOTTOMLEFT", 0, -8)
	dock.metaTab = CreateTab(dock, "Metas", "metas")
	dock.metaTab:SetPoint("BOTTOMLEFT", dock.listTab, "BOTTOMRIGHT", 18, 0)
	local tabLine = dock:CreateTexture(nil, "BACKGROUND")
	tabLine:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.2)
	tabLine:SetHeight(1)
	tabLine:SetPoint("TOPLEFT", dock.listTab, "BOTTOMLEFT", 0, 0)
	tabLine:SetPoint("RIGHT", -14, 0)
	dock.tabLine = tabLine

	CreateListView()
	CreateMetaView()
	dock:SetScript("OnShow", function()
		Refresh()
	end)
	dock:SetScript("OnHide", function()
		HidePreview()
		GameTooltip:Hide()
	end)

	-- Shown while the dock is closed: a narrow tab on the window's edge that opens it.
	handle = CreateFrame("Button", nil, parent)
	handle:SetSize(18, 64)
	handle:SetPoint("TOPLEFT", parent, "TOPRIGHT", 0, -60)
	local hbg = handle:CreateTexture(nil, "BACKGROUND")
	hbg:SetAllPoints()
	hbg:SetColorTexture(UI.BG[1], UI.BG[2], UI.BG[3], UI.BG[4])
	UI.Border(handle, GOLD[1], GOLD[2], GOLD[3], 0.45)
	local arrow = UI.Text(handle, 13, GOLD)
	arrow:SetPoint("CENTER", 1, 0)
	arrow:SetText(">")
	handle:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText("Almost Done", GOLD[1], GOLD[2], GOLD[3])
		GameTooltip:AddLine("Show near-complete achievements.", 1, 1, 1)
		GameTooltip:Show()
	end)
	handle:SetScript("OnLeave", function()
		GameTooltip:Hide()
	end)
	handle:SetScript("OnClick", function()
		SetDockOpen(true)
	end)
end

function Refresh()
	if not (dock and dock:IsVisible()) then
		return
	end
	if tab == "list" then
		RefreshList()
	else
		RefreshMetas()
	end
end

-- Scan progress in the header, without rebuilding the list.
function ns.AchDock_ScanStatus()
	if dock and dock:IsVisible() and tab == "list" then
		local progress = ns.Ach_ScanProgress()
		dock.status:SetText(progress and ("Scanning %d%%"):format(progress * 100) or "")
	end
end

-- Shows or hides the dock and the handle for the module's state and the open setting, then refreshes.
function ns.AchDock_Refresh()
	if not dock then
		return
	end
	local active = Active()
	local open = DB().dock.open
	dock:SetShown(active and open)
	handle:SetShown(active and not open)
	Refresh()
end

local function Hook()
	if hooked or not AchievementFrame then
		return
	end
	hooked = true
	Build()
	ns.AchDock_Refresh()
end

-- The Achievements window is load-on-demand: build when it loads (or now, if it already has).
function ns.AchDock_Init()
	if C_AddOns.IsAddOnLoaded("Blizzard_AchievementUI") then
		Hook()
		return
	end
	if waiter then
		return
	end
	waiter = CreateFrame("Frame")
	waiter:RegisterEvent("ADDON_LOADED")
	waiter:SetScript("OnEvent", function(self, _, name)
		if name == "Blizzard_AchievementUI" then
			self:UnregisterAllEvents()
			Hook()
		end
	end)
end
