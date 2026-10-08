local addonName, ns = ...

-- Weekly board, Activities tab: this week's activities grouped (a short hand-kept list, then learned weekly quests by
-- their quest log header) with "Hide completed", and a Resources list (crests, then the expansion's currencies).
-- Logic in ActivityData.lua.

local UI = ns.UI
local WHITE, GREY = UI.WHITE, UI.GREY
local SIDE_W = 240
local RES_H = 22

local function Completed(id, account)
	if account and C_QuestLog.IsQuestFlaggedCompletedOnAccount then
		return C_QuestLog.IsQuestFlaggedCompletedOnAccount(id)
	end
	return C_QuestLog.IsQuestFlaggedCompleted(id)
end

-- The hand-kept list with this week's state filled in.
local function ReadCurated()
	local out = {}
	for _, g in ipairs(ns.WEEKLY_ACTIVITIES[GetExpansionLevel()] or {}) do
		local entries = {}
		for _, e in ipairs(g.entries) do
			local item = { label = e.label }
			if e.flags then
				local n = 0
				for _, id in ipairs(e.flags) do
					if Completed(id) then
						n = n + 1
					end
				end
				item.n, item.of = n, #e.flags
			elseif e.questLine then
				-- This week's quest of the line: the one done, else the one in the log.
				item.state = "open"
				for _, id in ipairs(C_QuestLine.GetQuestLineQuests(e.questLine) or {}) do
					if Completed(id) then
						item.state, item.title = "done", C_QuestLog.GetTitleForQuestID(id)
						break
					elseif C_QuestLog.IsOnQuest(id) then
						item.state, item.title = "progress", C_QuestLog.GetTitleForQuestID(id)
					end
				end
			else
				item.state = Completed(e.quest, e.account) and "done"
					or (C_QuestLog.IsOnQuest(e.quest) and "progress" or "open")
			end
			entries[#entries + 1] = item
		end
		out[#out + 1] = { group = g.group, entries = entries }
	end
	return out
end

-- Resources: { { name, icon, text, dim } }, crests first.
local function ReadResources()
	local list = {}
	local function Add(id, crest)
		local info = C_CurrencyInfo.GetCurrencyInfo(id)
		if not (info and info.name and info.name ~= "") then
			return
		end
		if not crest and not info.discovered and (info.quantity or 0) == 0 then
			return
		end
		local text = tostring(info.quantity or 0)
		if crest then
			local have, cap = ns.Weekly_CurrencyProgress({ qty = info.quantity, earnedWeek = info.quantityEarnedThisWeek,
				weeklyCap = info.maxWeeklyQuantity, total = info.totalEarned, seasonCap = info.maxQuantity,
				useTotal = info.useTotalEarnedForMaxQty })
			text = cap and ("%d  |cff9e9e9e%d/%d|r"):format(info.quantity or 0, have, cap) or text
		end
		list[#list + 1] = { name = info.name, icon = info.iconFileID, text = text, dim = (info.quantity or 0) == 0 }
	end
	for _, id in ipairs(ns.WEEKLY_CRESTS) do
		Add(id, true)
	end
	for _, id in ipairs(ns.WEEKLY_RESOURCES[GetExpansionLevel()] or {}) do
		Add(id, false)
	end
	return list
end

function ns.WeeklyActivitiesView(parent)
	local Kit = ns.HomeKit
	local view = { res = {} }
	view.scroll = UI.Scroll(parent)
	local c = view.scroll.content

	view.resHead = Kit.Heading(c)
	view.resHead:SetPoint("TOPLEFT", 8, -8)
	view.resHead:SetWidth(SIDE_W - 16)
	view.resHead:Set("Resources")

	view.hide = UI.Checkbox(c)
	view.hide.label = UI.Text(c, 12, GREY)
	view.hide.label:SetPoint("LEFT", view.hide, "RIGHT", 6, 0)
	view.hide.onChange = function(on)
		ns.weeklyDB.hideCompleted = on
		ns.WeeklyBoard_Refresh()
	end

	view.listFrame = CreateFrame("Frame", nil, c)
	view.rows = ns.WeeklyRows(view.listFrame)

	local function ResRow(i)
		local row = view.res[i]
		if not row then
			row = CreateFrame("Frame", nil, c)
			row:SetSize(SIDE_W - 16, RES_H)
			row.icon = row:CreateTexture(nil, "ARTWORK")
			row.icon:SetSize(18, 18)
			row.icon:SetPoint("RIGHT", 0, 0)
			row.text = row:CreateFontString(nil, "OVERLAY")
			row.text:SetFont(Kit.NARROW_FONT, 14, "")
			row.text:SetPoint("RIGHT", row.icon, "LEFT", -6, 0)
			row.name = UI.Text(row, 12, WHITE)
			row.name:SetPoint("LEFT", 0, 0)
			row.name:SetPoint("RIGHT", row.text, "LEFT", -8, 0)
			row.name:SetWordWrap(false)
			view.res[i] = row
		end
		row:Show()
		return row
	end

	function view:Render(width)
		width = math.max(width or 0, 500)
		-- Resources (left).
		for _, row in ipairs(self.res) do
			row:Hide()
		end
		local y = 8 + 38
		for i, r in ipairs(ReadResources()) do
			local row = ResRow(i)
			row:ClearAllPoints()
			row:SetPoint("TOPLEFT", 8, -y)
			row.icon:SetTexture(r.icon)
			row.icon:SetDesaturated(r.dim)
			row.text:SetText(r.text)
			row.name:SetText(r.name)
			local col = r.dim and GREY or WHITE
			row.name:SetTextColor(col[1], col[2], col[3])
			row.text:SetTextColor(col[1], col[2], col[3])
			y = y + RES_H
		end
		local leftBottom = y

		-- Activities (right).
		local v = ns.Weekly_CurrentView()
		local x = SIDE_W + 24
		local model = ns.Weekly_ActivityModel(ReadCurated(), ns.weeklyDB.quests, v or { quests = {} },
			ns.weeklyDB.hideCompleted)
		self.hide:ClearAllPoints()
		self.hide:SetPoint("TOPLEFT", x + 8, -16)
		self.hide:SetChecked(ns.weeklyDB.hideCompleted)
		self.hide.label:SetText(("Hide completed (%d)"):format(model.hidden))
		local items = {}
		for _, g in ipairs(model.groups) do
			if g.title ~= "" then
				items[#items + 1] = { kind = "header", text = g.title }
			end
			for _, item in ipairs(g.items) do
				items[#items + 1] = item
			end
		end
		self.listFrame:ClearAllPoints()
		self.listFrame:SetPoint("TOPLEFT", x, -36)
		self.listFrame:SetWidth(width - x - 8)
		local h = self.rows:Render(items)
		self.listFrame:SetHeight(math.max(h, 1))
		self.scroll:SetContentHeight(math.max(leftBottom, 36 + h) + 16)
	end

	return view
end
