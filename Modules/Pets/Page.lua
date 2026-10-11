local addonName, ns = ...

-- Pet Battles page of the Tomte window: four views behind buttons at the top. Tamers (every fight in the tamer
-- table, with your teams and the guide links), Teams (import Xu-Fu strategies, load, script, delete), Leveling (the
-- queue for the leveling slot) and Types (what each family hits hard and what hurts it).

local UI = ns.UI
local VIEWS = {
	{ key = "tamers", text = "Tamers" },
	{ key = "teams", text = "Teams" },
	{ key = "leveling", text = "Leveling" },
	{ key = "types", text = "Types" },
}
local ROW_H, TALL_H, HEADER_H = 22, 40, 28
local ICON = 26
local TOP = 30 -- below the view buttons
local MAX_ADD = 150 -- pets in the "add to the queue" list
local TIP_LINES = 18 -- strategy note lines in a team's tooltip before "..."
local NONE_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"

local db
local page
local views = {}

function ns.PetsPage_Init(moduleDB)
	db = moduleDB
end

local TipLine = UI.TipLine

-- Rows ---------------------------------------------------------------------------------------------------------

local function NewRow(parent)
	local row = CreateFrame("Button", nil, parent)
	row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	row.hover = row:CreateTexture(nil, "BACKGROUND")
	row.hover:SetAllPoints()
	row.hover:SetColorTexture(UI.Color("hover"))
	row.hover:Hide()
	row.line = row:CreateTexture(nil, "ARTWORK")
	row.line:SetHeight(1)
	row.line:SetPoint("BOTTOMLEFT", 8, 0)
	row.line:SetPoint("BOTTOMRIGHT", -8, 0)
	row.line:SetColorTexture(UI.RGBA("frame", 0.25))
	row.icons = {}
	for i = 1, 3 do
		local t = row:CreateTexture(nil, "ARTWORK")
		t:SetSize(ICON, ICON)
		t:SetTexCoord(0.08, 0.92, 0.08, 0.92)
		row.icons[i] = t
	end
	row.left = UI.Text(row, 12, "text")
	row.left:SetWordWrap(false)
	row.sub = UI.Text(row, 10, "textMuted")
	row.sub:SetWordWrap(false)
	row.right = UI.Text(row, 11, "textMuted")
	row.right:SetJustifyH("RIGHT")
	row.right:SetWordWrap(false)
	row.buttons = {}
	row:SetScript("OnEnter", function(self)
		if self.clickable then
			self.hover:Show()
		end
		if self.tip then
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			self.tip(GameTooltip)
			GameTooltip:Show()
		end
	end)
	row:SetScript("OnLeave", function(self)
		self.hover:Hide()
		GameTooltip:Hide()
	end)
	row:SetScript("OnClick", function(self, button)
		if self.onClick then
			self.onClick(button)
		end
	end)
	return row
end

local function RowButton(row, i)
	local b = row.buttons[i]
	if not b then
		b = UI.Button(row, 60, "")
		b:SetHeight(18)
		row.buttons[i] = b
	end
	return b
end

-- item = { kind = "header" | "row", text, sub, right, icons = { tex... }, grey = { [i] = true }, tall, tip(tt),
--   onClick(button), buttons = { { text, onClick, disabled, tip } } }
local function List(parent)
	local list = { rows = {}, used = 0 }
	list.scroll = UI.Scroll(parent)
	list.scroll:SetPoint("TOPLEFT", 0, -TOP)
	list.scroll:SetPoint("BOTTOMRIGHT", -8, 0)

	function list:Render(items, top)
		for i = 1, self.used do
			self.rows[i]:Hide()
		end
		self.used = 0
		local y = top or 0
		for _, item in ipairs(items) do
			self.used = self.used + 1
			local row = self.rows[self.used] or NewRow(self.scroll.content)
			self.rows[self.used] = row
			row:ClearAllPoints()
			row:SetPoint("TOPLEFT", 0, -y)
			row:SetPoint("RIGHT")
			row.tip, row.onClick = item.tip, item.onClick
			row.clickable = item.onClick ~= nil
			row:EnableMouse(item.onClick ~= nil or item.tip ~= nil or false)
			row.hover:Hide()
			for _, b in ipairs(row.buttons) do
				b:Hide()
			end
			row.left:ClearAllPoints()
			row.sub:ClearAllPoints()
			row.right:ClearAllPoints()
			local height
			if item.kind == "header" then
				height = HEADER_H
				for _, t in ipairs(row.icons) do
					t:Hide()
				end
				UI.SetFont(row.left, "body", 14)
				UI.SetTextRole(row.left, "heading")
				row.left:SetPoint("BOTTOMLEFT", 8, 6)
				row.left:SetPoint("RIGHT", row.right, "LEFT", -8, 0)
				row.right:SetPoint("BOTTOMRIGHT", -8, 7)
				row.line:Show()
				row.sub:SetText("")
			else
				height = item.tall and TALL_H or ROW_H
				row.line:Hide()
				local x = 12
				for i, t in ipairs(row.icons) do
					local tex = item.icons and item.icons[i]
					t:ClearAllPoints()
					if tex then
						local size = item.tall and ICON or 18
						t:SetSize(size, size)
						t:SetPoint("LEFT", x, 0)
						t:SetTexture(tex)
						local grey = item.grey and item.grey[i]
						t:SetDesaturated(grey)
						t:SetAlpha(grey and 0.5 or 1)
						t:Show()
						x = x + size + 4
					else
						t:Hide()
					end
				end
				x = x + 4
				UI.SetFont(row.left, "body", 12)
				UI.SetTextRole(row.left, item.role or "text")
				-- Buttons from the right.
				local rightEdge = -8
				for i = #(item.buttons or {}), 1, -1 do
					local spec = item.buttons[i]
					local b = RowButton(row, i)
					b.label:SetText(spec.text)
					b:SetWidth(math.max(math.ceil(b.label:GetUnboundedStringWidth()) + 18, 40))
					b:ClearAllPoints()
					b:SetPoint("RIGHT", rightEdge, 0)
					b:SetScript("OnClick", spec.onClick)
					b:SetEnabled(not spec.disabled)
					b:SetAlpha(spec.disabled and 0.4 or 1)
					b:SetScript("OnEnter", function(self)
						UI.SetBorderColor(self, "accent", 1)
						if spec.tip then
							GameTooltip:SetOwner(self, "ANCHOR_TOP")
							GameTooltip:SetText(spec.tip, 1, 1, 1, 1, true)
							GameTooltip:Show()
						end
					end)
					b:SetScript("OnLeave", function(self)
						UI.SetBorderColor(self, "frame", UI.BUTTON_RULE)
						GameTooltip:Hide()
					end)
					b:Show()
					rightEdge = rightEdge - b:GetWidth() - 4
				end
				row.right:SetPoint("RIGHT", rightEdge - 4, 0)
				if item.sub then
					row.left:SetPoint("TOPLEFT", x, -5)
					row.sub:SetPoint("TOPLEFT", row.left, "BOTTOMLEFT", 0, -2)
					row.sub:SetPoint("RIGHT", row.right, "LEFT", -8, 0)
				else
					row.left:SetPoint("LEFT", x, 0)
				end
				row.left:SetPoint("RIGHT", row.right, "LEFT", -8, 0)
				row.sub:SetText(item.sub or "")
			end
			row.left:SetText(item.text or "")
			row.right:SetText(item.right or "")
			row:SetHeight(height)
			row:Show()
			y = y + height
		end
		self.scroll:SetContentHeight(y)
	end

	return list
end

local function SearchBox(parent, placeholderText, onChange)
	local box = CreateFrame("EditBox", nil, parent)
	box:SetHeight(22)
	box:SetAutoFocus(false)
	UI.SetFont(box, "body", 12)
	UI.SetTextRole(box, "text")
	box:SetTextInsets(8, 8, 0, 0)
	UI.Surface(box, 0.35)
	local placeholder = UI.Text(box, 12, "textFaint")
	placeholder:SetPoint("LEFT", 8, 0)
	placeholder:SetText(placeholderText)
	local refresh = UI.Debounce(UI.SEARCH_DELAY, onChange)
	box:SetScript("OnTextChanged", function(self)
		placeholder:SetShown(self:GetText() == "")
		refresh()
	end)
	box:SetScript("OnEscapePressed", function(self)
		self:SetText("")
		self:ClearFocus()
	end)
	box:SetScript("OnEnterPressed", box.ClearFocus)
	function box:Query()
		return strtrim(self:GetText()):lower()
	end
	return box
end

-- Shared bits ------------------------------------------------------------------------------------------------

local function TeamTip(team)
	return function(tt)
		tt:SetText(team.name, UI.Color("heading"))
		local npcs = {}
		for _, npc in ipairs(team.npcs or {}) do
			npcs[#npcs + 1] = ns.PetsStore_NPCName(npc)
		end
		if #npcs > 0 then
			TipLine("For: " .. table.concat(npcs, ", "), "textMuted", true)
		end
		if team.notes and team.notes ~= "" then
			TipLine(" ")
			local lines = 0
			for line in ns.Pets_CleanNotes(team.notes):gmatch("[^\n]+") do
				lines = lines + 1
				if lines > TIP_LINES then
					TipLine("...", "textMuted")
					break
				end
				TipLine(line, "text", true)
			end
		end
		TipLine(" ")
		TipLine(team.script and "Has a script: Next move plays it in the fight." or "No script: follow the steps.",
			team.script and "success" or "textMuted", true)
	end
end

local function TeamIcons(team)
	local icons, grey = {}, {}
	local owned = {}
	for _, p in ipairs(ns.PetsJournal_Owned()) do
		owned[p.species] = true
	end
	for i = 1, 3 do
		local tag = team.pets[i]
		if tag.kind == "species" then
			local _, icon = C_PetJournal.GetPetInfoBySpeciesID(tag.species)
			icons[i] = icon or NONE_ICON
			grey[i] = not owned[tag.species]
		elseif tag.kind == "leveling" then
			icons[i] = "Interface\\Icons\\INV_Pet_BattlePetTraining"
		elseif tag.kind == "random" then
			icons[i] = "Interface\\Icons\\INV_Misc_Dice_01"
		else
			icons[i] = NONE_ICON
			grey[i] = true
		end
	end
	return icons, grey
end

local function LoadTeam(team)
	ns.PetsJournal_LoadAndReport(team, ns.PetsJournal_NextLeveling(db))
end

local function EditScript(team)
	ns.Dialog_Show({
		title = "Script: " .. team.name,
		hint = "Pet Battle Scripts language. Next move in the battle helper plays it, one action per press.",
		text = team.script or "",
		onSave = function(text)
			if text:match("%S") then
				local _, err = ns.PetScript_Build(text)
				if err then
					return err
				end
			end
			ns.PetsStore_SetScript(team.id, text)
			ns.PetsPage_Refresh()
		end,
	})
end

-- Tamers view ------------------------------------------------------------------------------------------------

local function TamersView(parent)
	local v = { frame = CreateFrame("Frame", nil, parent) }
	v.frame:SetAllPoints()
	v.search = SearchBox(v.frame, "Search tamers", function()
		ns.PetsPage_Refresh()
	end)
	v.search:SetPoint("TOPLEFT", 8, -TOP)
	v.search:SetWidth(220)
	v.note = UI.Text(v.frame, 11, "textMuted")
	v.note:SetPoint("LEFT", v.search, "RIGHT", 12, 0)
	v.note:SetPoint("RIGHT", -8, 0)
	v.note:SetText("Click a tamer for its Xu-Fu and Wowhead links.")
	v.list = List(v.frame)
	v.list.scroll:SetPoint("TOPLEFT", 0, -(TOP + 28))

	function v:Render()
		local query = self.search:Query()
		local bySection = {}
		for id, e in pairs(ns.PETS_ENCOUNTERS) do
			if query == "" or e.name:lower():find(query, 1, true) then
				bySection[e.section] = bySection[e.section] or {}
				table.insert(bySection[e.section], { id = id, e = e })
			end
		end
		local items = {}
		for _, section in ipairs(ns.PETS_SECTIONS) do
			local list = bySection[section.id]
			if list then
				table.sort(list, function(a, b)
					return a.e.name < b.e.name
				end)
				items[#items + 1] = { kind = "header", text = section.name,
					right = _G["EXPANSION_NAME" .. section.expansion] or "" }
				for _, entry in ipairs(list) do
					local e, id = entry.e, entry.id
					local teams, learned = 0, nil
					for _, npc in ipairs(e.npcs) do
						teams = teams + #ns.PetsStore_TeamsFor(npc)
						learned = learned or ns.PetsStore_Learned(npc)
					end
					local right = {}
					if learned and learned.types then
						local icons = {}
						for k, t in ipairs(learned.types) do
							icons[k] = ns.Pets_FamilyIcon(t, 13)
						end
						right[#right + 1] = table.concat(icons, "")
					end
					if teams > 0 then
						right[#right + 1] = UI.Wrap(teams == 1 and "1 team" or (teams .. " teams"), "success")
					end
					items[#items + 1] = {
						text = e.name,
						right = table.concat(right, "   "),
						onClick = function()
							ns.PetsGuides_ShowEncounter(id)
						end,
					}
				end
			end
		end
		if #items == 0 then
			items[1] = { text = UI.Wrap("No tamer matches.", "textMuted") }
		end
		self.list:Render(items)
	end
	return v
end

-- Teams view -------------------------------------------------------------------------------------------------

local function TeamsView(parent)
	local v = { frame = CreateFrame("Frame", nil, parent) }
	v.frame:SetAllPoints()
	local box = CreateFrame("Frame", nil, v.frame)
	box:SetPoint("TOPLEFT", 8, -TOP)
	box:SetPoint("RIGHT", -100, 0)
	box:SetHeight(54)
	UI.Surface(box)
	local scroll = UI.Scroll(box)
	scroll:SetPoint("TOPLEFT", 6, -4)
	scroll:SetPoint("BOTTOMRIGHT", -10, 4)
	local edit = CreateFrame("EditBox", nil, scroll.content)
	edit:SetMultiLine(true)
	edit:SetAutoFocus(false)
	edit:SetPoint("TOPLEFT")
	edit:SetPoint("RIGHT")
	UI.SetFont(edit, "body", 11)
	UI.SetTextRole(edit, "text")
	edit:SetScript("OnEscapePressed", edit.ClearFocus)
	edit:SetScript("OnTextChanged", function(self)
		v.placeholder:SetShown(self:GetText() == "")
		scroll:SetContentHeight(self:GetHeight())
	end)
	scroll.onWidthChanged = function(width)
		edit:SetWidth(width)
	end
	box:EnableMouse(true)
	box:SetScript("OnMouseDown", function()
		edit:SetFocus()
	end)
	v.placeholder = UI.Text(box, 11, "textFaint")
	v.placeholder:SetPoint("TOPLEFT", 8, -6)
	v.placeholder:SetPoint("RIGHT", -8, 0)
	v.placeholder:SetText("Paste strategies here: on a Xu-Fu strategy page, the \"Rematch string\" button. Several at once is fine.")
	v.edit = edit
	v.import = UI.Button(v.frame, 84, "Import")
	v.import:SetPoint("TOPLEFT", box, "TOPRIGHT", 8, 0)
	v.import:SetScript("OnClick", function()
		ns.PetsPage_Import(edit:GetText())
		edit:SetText("")
		edit:ClearFocus()
	end)
	v.status = UI.Text(v.frame, 11, "textMuted")
	v.status:SetPoint("TOPLEFT", box, "BOTTOMLEFT", 0, -4)
	v.status:SetPoint("RIGHT", -8, 0)
	v.status:SetWordWrap(false)
	v.list = List(v.frame)
	v.list.scroll:SetPoint("TOPLEFT", 0, -(TOP + 76))

	function v:Render()
		local items = {}
		local canChange, why = ns.PetsJournal_CanChange()
		for _, team in ipairs(ns.PetsStore_Teams()) do
			local icons, grey = TeamIcons(team)
			local npcNames, inUse = {}, false
			for _, npc in ipairs(team.npcs or {}) do
				npcNames[#npcNames + 1] = ns.PetsStore_NPCName(npc)
				local active = ns.PetsStore_TeamFor(npc)
				inUse = inUse or (active and active.id == team.id)
			end
			local author = ns.Pets_ParseAuthor(team.notes)
			local sub = table.concat(npcNames, ", ")
			if author then
				sub = sub .. UI.Wrap("   by " .. author, "textFaint")
			end
			local several = false
			for _, npc in ipairs(team.npcs or {}) do
				several = several or #ns.PetsStore_TeamsFor(npc) > 1
			end
			local buttons = {
				{ text = "Load", disabled = not canChange, tip = canChange and "Put this team in your pet journal."
					or ("Can't now: " .. why .. "."), onClick = function()
						LoadTeam(team)
						-- A short wait, presumably so the journal reads back the new loadout.
						C_Timer.After(0.3, ns.PetsPage_Refresh)
					end },
				{ text = "Script", tip = team.script and "See or edit its script." or "Add a script.",
					onClick = function()
						EditScript(team)
					end },
				{ text = "Delete", onClick = function()
					ns.PetsPage_ConfirmDelete(team)
				end },
			}
			if several and not inUse then
				table.insert(buttons, 1, { text = "Use", tip = "Use this team for its tamer (instead of the other one).",
					onClick = function()
						for _, npc in ipairs(team.npcs or {}) do
							ns.PetsStore_SetActive(npc, team.id)
						end
						ns.PetsPage_Refresh()
					end })
			end
			items[#items + 1] = {
				tall = true,
				text = team.name .. (team.script and UI.Wrap("  script", "accent") or "")
					.. ((several and inUse) and UI.Wrap("  in use", "success") or ""),
				sub = sub,
				icons = icons,
				grey = grey,
				tip = TeamTip(team),
				buttons = buttons,
			}
		end
		if #items == 0 then
			items[1] = { text = UI.Wrap("No strategies yet. Find a tamer on Xu-Fu's Pet Guides (the Tamers view has the links), copy a strategy's Rematch string and paste it above.", "textMuted") }
		end
		self.list:Render(items)
	end
	return v
end

function ns.PetsPage_Import(text)
	local teams, skipped = ns.Pets_ParseImport(text)
	for _, team in ipairs(teams) do
		ns.PetsStore_Add(team)
	end
	local msg
	if #teams == 0 then
		msg = UI.Wrap(skipped > 0 and "That isn't a team string. Use a strategy's \"Rematch string\" button on Xu-Fu."
			or "Nothing to import.", "warning")
	else
		msg = UI.Wrap(("Imported %d %s."):format(#teams, #teams == 1 and "strategy" or "strategies"), "success")
		if skipped > 0 then
			msg = msg .. UI.Wrap(("  %d line(s) skipped: not team strings."):format(skipped), "warning")
		end
		local errors = 0
		for _, team in ipairs(teams) do
			if team.script and select(2, ns.PetScript_Build(team.script)) then
				errors = errors + 1
			end
		end
		if errors > 0 then
			msg = msg .. UI.Wrap(("  %d script(s) can't run in Tomte; their steps still show."):format(errors), "warning")
		end
	end
	if views.teams then
		views.teams.status:SetText(msg)
	end
	ns.PetsPage_Refresh()
	return #teams, skipped
end

StaticPopupDialogs["TOMTE_PETS_DELETE_TEAM"] = {
	text = "Delete the strategy \"%s\"?",
	button1 = YES,
	button2 = NO,
	OnAccept = function(_, id)
		ns.PetsStore_Delete(id)
		ns.PetsPage_Refresh()
	end,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
}

function ns.PetsPage_ConfirmDelete(team)
	local dialog = StaticPopup_Show("TOMTE_PETS_DELETE_TEAM", team.name)
	if dialog then
		dialog.data = team.id
	end
end

-- Leveling view ----------------------------------------------------------------------------------------------

local function LevelingView(parent)
	local v = { frame = CreateFrame("Frame", nil, parent) }
	v.frame:SetAllPoints()
	v.state = UI.Text(v.frame, 12, "text")
	v.state:SetPoint("TOPLEFT", 8, -TOP - 4)
	v.state:SetPoint("RIGHT", -8, 0)
	v.state:SetWordWrap(false)
	v.search = SearchBox(v.frame, "Search your pets", function()
		ns.PetsPage_Refresh()
	end)
	v.search:SetWidth(220)
	v.list = List(v.frame)
	v.list.scroll:SetPoint("TOPLEFT", 0, -(TOP + 24))

	local function Move(i, d)
		local q = db.levelQueue
		local j = i + d
		if q[j] then
			q[i], q[j] = q[j], q[i]
			ns.PetsPage_Refresh()
		end
	end

	function v:Render()
		local lv = db.leveling
		self.state:SetText(lv.on and ("Leveling slot " .. lv.slot .. ": after each battle, a pet that reached 25 is swapped for the next one below.")
			or UI.Wrap("The leveling slot is off. Turn it on in Settings > Pet Battles to use this queue.", "warning"))
		local owned = ns.PetsJournal_Owned()
		local byGuid = {}
		for _, p in ipairs(owned) do
			byGuid[p.guid] = p
		end
		-- Shown as it is: pruning happens after battles (Journal.lua), never here, where the journal may still be
		-- loading.
		local queue = db.levelQueue
		local items = { { kind = "header", text = "Queue", right = #queue .. " pets" } }
		local queued = {}
		for i, guid in ipairs(queue) do
			local p = byGuid[guid]
			queued[guid] = true
			local done = p and p.level >= ns.PETS_MAX_LEVEL
			items[#items + 1] = {
				text = ("%d.  %s"):format(i, p and p.name or UI.Wrap("(not found)", "textMuted")),
				right = p and (done and UI.Wrap("25: done", "success") or ("level " .. p.level)) or "",
				icons = { p and p.icon or NONE_ICON },
				buttons = {
					{ text = "Up", disabled = i == 1, onClick = function()
						Move(i, -1)
					end },
					{ text = "Down", disabled = i == #queue, onClick = function()
						Move(i, 1)
					end },
					{ text = "Remove", onClick = function()
						table.remove(queue, i)
						ns.PetsPage_Refresh()
					end },
				},
			}
		end
		if #queue == 0 then
			items[#items + 1] = { text = UI.Wrap("Empty. Add pets below.", "textMuted") }
		end
		items[#items + 1] = { kind = "header", text = "Add pets" }
		local searchIndex = #items
		local query = self.search:Query()
		local candidates = {}
		for _, p in ipairs(owned) do
			if p.level < ns.PETS_MAX_LEVEL and not queued[p.guid]
				and (query == "" or p.name:lower():find(query, 1, true)) then
				candidates[#candidates + 1] = p
			end
		end
		table.sort(candidates, function(a, b)
			if a.level ~= b.level then
				return a.level > b.level
			end
			return a.name < b.name
		end)
		for i = 1, math.min(#candidates, MAX_ADD) do
			local p = candidates[i]
			items[#items + 1] = {
				text = p.name,
				right = ns.Pets_FamilyIcon(p.type, 13) .. "  level " .. p.level,
				icons = { p.icon },
				onClick = function()
					table.insert(db.levelQueue, p.guid)
					ns.PetsPage_Refresh()
				end,
				tip = function(tt)
					tt:SetText(p.name, UI.Color("heading"))
					TipLine("Click to add it to the queue.", "success")
				end,
			}
		end
		if #candidates == 0 then
			items[#items + 1] = { text = UI.Wrap("No battle pets under 25 match.", "textMuted") }
		end
		self.list:Render(items)
		-- The search box sits on the "Add pets" header.
		local y = 0
		for i = 1, searchIndex - 1 do
			y = y + ((items[i].kind == "header") and HEADER_H or ROW_H)
		end
		self.search:ClearAllPoints()
		self.search:SetParent(self.list.scroll.content)
		self.search:SetPoint("TOPRIGHT", self.list.scroll.content, "TOPRIGHT", -8, -y - 3)
		self.search:Show()
	end
	return v
end

-- Types view -------------------------------------------------------------------------------------------------

local function TypesView(parent)
	local v = { frame = CreateFrame("Frame", nil, parent) }
	v.frame:SetAllPoints()
	v.list = List(v.frame)

	function v:Render()
		local c = ns.Pets_Chart()
		local function Names(list)
			local out = {}
			for _, t in ipairs(list) do
				out[#out + 1] = ns.Pets_FamilyIcon(t, 13) .. " " .. ns.Pets_FamilyName(t)
			end
			return #out > 0 and table.concat(out, "  ") or "-"
		end
		local items = { { kind = "header", text = "Pet families",
			right = "Attacks of a type hit one family 50% harder and another a third weaker" } }
		for t = 1, #c do
			local hitsHard, hitsWeak = {}, {}
			for def = 1, #c do
				if c[t][def] > 1 then
					hitsHard[#hitsHard + 1] = def
				elseif c[t][def] < 1 then
					hitsWeak[#hitsWeak + 1] = def
				end
			end
			items[#items + 1] = {
				tall = true,
				text = ns.Pets_FamilyIcon(t, 18) .. "  " .. ns.Pets_FamilyName(t),
				sub = ("Its attacks: strong vs %s, weak vs %s.    It takes more from %s, less from %s."):format(
					Names(hitsHard), Names(hitsWeak), Names(ns.Pets_Strong(c, t)), Names(ns.Pets_Resists(c, t))),
			}
		end
		items[#items + 1] = { text = UI.Wrap("In a fight, the battle helper does this for you: it names the attack types that hit the enemy hard and the pet that fits best.", "textMuted") }
		self.list:Render(items)
	end
	return v
end

-- Page ---------------------------------------------------------------------------------------------------------

local MAKERS = { tamers = TamersView, teams = TeamsView, leveling = LevelingView, types = TypesView }

local function Layout()
	local view = db.view
	if not MAKERS[view] then
		view = "tamers"
		db.view = view
	end
	for _, b in ipairs(page.buttons) do
		UI.SetTextRole(b.label, b.key == view and "heading" or "textMuted")
		b.selected:SetShown(b.key == view)
	end
	if not views[view] then
		views[view] = MAKERS[view](page)
	end
	for key, v in pairs(views) do
		v.frame:SetShown(key == view)
	end
	views[view]:Render()
end

function ns.PetsPage_Refresh()
	if page and page:IsVisible() then
		Layout()
	end
end

function ns.PetsPage_SetView(key)
	db.view = key
	ns.PetsPage_Refresh()
end

-- Focus the import box (/tomte pets import).
function ns.PetsPage_FocusImport()
	ns.PetsPage_SetView("teams")
	if views.teams then
		views.teams.edit:SetFocus()
	end
end

ns.PetsPage = {
	title = "Pet Battles",
	Create = function(frame)
		page = frame
		page.buttons = {}
		local prev
		for _, view in ipairs(VIEWS) do
			local b = UI.Button(page, 80, view.text)
			b:SetWidth(math.max(math.ceil(b.label:GetUnboundedStringWidth()) + 22, 56))
			b.key = view.key
			b.selected = b:CreateTexture(nil, "ARTWORK")
			b.selected:SetColorTexture(UI.RGBA("accent", 0.9))
			b.selected:SetHeight(2)
			b.selected:SetPoint("BOTTOMLEFT", 4, 2)
			b.selected:SetPoint("BOTTOMRIGHT", -4, 2)
			b:SetScript("OnClick", function()
				ns.PetsPage_SetView(view.key)
			end)
			if prev then
				b:SetPoint("LEFT", prev, "RIGHT", 8, 0)
			else
				b:SetPoint("TOPLEFT", 8, 0)
			end
			prev = b
			page.buttons[#page.buttons + 1] = b
		end
	end,
	Refresh = function()
		Layout()
	end,
}
