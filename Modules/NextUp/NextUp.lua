local addonName, ns = ...

-- Next up: a short ranked list on Home of the best things to do right now (vault rewards waiting, a rare up that
-- drops something you're missing, low durability, full Concentration, a world quest worth doing, ...). It only ranks
-- what other modules already know: each source is a module.home entry of kind "next" with
-- candidates(now) -> { { key, text, why, icon, right, state, bonus, onClick, stay } }. Ranking in Data.lua.

local UI = ns.UI
local GOLD, WHITE, GREY = UI.GOLD, UI.WHITE, UI.GREY
local HEAD_H = 40

local module, db
local dismissed = {} -- [candidate key] = state | true, this session only

local function Sources()
	local list = {}
	for _, m in ipairs(ns.modules) do
		for _, entry in ipairs(m.home or {}) do
			if entry.kind == "next" then
				list[#list + 1] = entry
			end
		end
	end
	return list
end

-- The ranked candidates of every visible source.
function ns.NextUp_Current(limit)
	local lists = {}
	local now = GetServerTime()
	for _, entry in ipairs(ns.HomeEntries("next")) do
		if db.sources[entry.key] ~= false then
			lists[#lists + 1] = { source = entry.key, score = entry.score, items = ns.HomeCall(entry.candidates, now) or {} }
		end
	end
	return ns.NextUp_Rank(lists, {
		enabled = db.sources, priority = db.priority, dismissed = dismissed, mode = db.dismiss, limit = limit or db.rows,
		perSource = db.perSource,
	})
end

local function Run(c)
	if not c.onClick then
		return
	end
	PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
	if not c.stay then
		ns.Panel_Hide()
	end
	c.onClick()
end

local function SourceName(key)
	local entry = ns.homeByKey[key]
	return entry and entry.name or key
end

local function Tooltip(row, c)
	GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
	GameTooltip:SetText(c.text, 1, 1, 1, 1, true)
	if c.why and c.why ~= "" then
		GameTooltip:AddLine(c.why, GOLD[1], GOLD[2], GOLD[3], true)
	end
	GameTooltip:AddLine(" ")
	if c.onClick then
		GameTooltip:AddLine(c.hint or "Click to start", GREY[1], GREY[2], GREY[3])
	end
	GameTooltip:AddLine("Right-click: not now", GREY[1], GREY[2], GREY[3])
	GameTooltip:AddLine("From " .. SourceName(c.source), GREY[1], GREY[2], GREY[3])
	GameTooltip:Show()
end

-- Home section ---------------------------------------------------------------------------------------------------

local function Create(frame, Kit)
	frame.heading = Kit.Heading(frame)
	frame.heading:SetPoint("TOPLEFT")
	frame.heading:SetPoint("TOPRIGHT")
	frame.rows = {}
	frame.Kit = Kit
	frame.none = UI.Text(frame, 13, GREY)
	frame.none:SetPoint("TOPLEFT", 0, -HEAD_H)
	frame.none:SetPoint("RIGHT")
	frame.none:SetText("Nothing pressing.")
end

-- Returns the height it used.
local function Refresh(frame)
	local Kit = frame.Kit
	local list = ns.NextUp_Current()
	frame.heading:Set("Next up")
	-- The action on the first line, the reason in grey under it; all rows one height so columns line up.
	local twoLines = false
	for _, c in ipairs(list) do
		if c.why and c.why ~= "" then
			twoLines = true
		end
	end
	local rowH = twoLines and Kit.ROW2_H or Kit.ROW_H
	local strip = db.placement == "strip"
	-- Two columns in the strip when it's wide enough.
	local cols = strip and frame:GetWidth() >= 760 and 2 or 1
	-- As many rows as the room Home gives (it can be short under Your characters).
	local fit = math.max(math.floor((frame:GetHeight() - HEAD_H) / rowH), 1) * cols
	for i = #list, fit + 1, -1 do
		list[i] = nil
	end
	local n = #list
	local colW = (frame:GetWidth() - (cols - 1) * 24) / cols
	local perCol = math.ceil(n / cols)
	for i, c in ipairs(list) do
		local row = Kit.PoolRow(frame.rows, i, frame)
		row:Set(c.icon, c.text, c.color or WHITE, c.right, c.rightColor, twoLines and (c.why or "") or nil)
		row.onClick = c.onClick and function()
			Run(c)
		end or function() end
		row.onRightClick = function()
			dismissed[c.key] = ns.NextUp_DismissValue(c)
			PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF)
			ns.Panel_Refresh()
		end
		row.onEnter = function(self)
			Tooltip(self, c)
		end
		local col = math.floor((i - 1) / perCol)
		local line = (i - 1) % perCol
		row:ClearAllPoints()
		row:SetPoint("TOPLEFT", col * (colW + 24), -(HEAD_H + line * rowH))
		row:SetWidth(colW)
	end
	Kit.HideFrom(frame.rows, n + 1)
	frame.none:SetShown(n == 0)
	if n == 0 then
		return HEAD_H + 18
	end
	return HEAD_H + perCol * rowH
end

local Section = {
	kind = "section", slot = "next", key = "nextsection", Create = Create, Refresh = Refresh,
	shown = function()
		return db.home
	end,
	place = function()
		return db.placement
	end,
}

-- Minimap button tooltip lines (Minimap.lua asks).
function ns.NextUp_TooltipLines()
	if not (module and module.active and db.minimap) then
		return nil
	end
	local lines = {}
	for _, c in ipairs(ns.NextUp_Current(3)) do
		lines[#lines + 1] = c.text
	end
	return lines
end

-- Options: one checkbox and a priority slider per source, built when the panel shows them.
local function BuildOptions()
	local options = {
		{ type = "checkbox", key = "home", label = "Show on Home" },
		{ type = "dropdown", key = "placement", label = "Placement", choices = function()
			return { { value = "characters", text = "Under Your characters" }, { value = "column", text = "Right column" },
				{ value = "strip", text = "Strip under This week" } }
		end, tooltip = "Under the character list (it goes to the right column when there are too many characters to fit), "
			.. "on top of the right column (above Around you), or across Home under This week." },
		{ type = "slider", key = "rows", label = "Rows", min = 3, max = 8, step = 1 },
		{ type = "slider", key = "perSource", label = "Most from one source", min = 1, max = 8, step = 1,
			tooltip = "So one source (say, achievements) can't fill the whole list." },
		{ type = "dropdown", key = "dismiss", label = "\"Not now\" lasts", choices = function()
			return { { value = "login", text = "Until next login" }, { value = "change", text = "Until it changes" } }
		end, tooltip = "Right-click hides a suggestion. Until it changes: it comes back when it's about something "
			.. "else (another rare, a lower durability, another character's Concentration)." },
		{ type = "checkbox", key = "minimap", label = "On the minimap button tooltip",
			tooltip = "The top three suggestions under the minimap button's tooltip." },
		{ type = "header", label = "Sources and priority" },
	}
	for _, entry in ipairs(Sources()) do
		options[#options + 1] = { type = "checkbox", key = "sources." .. entry.key, label = entry.name,
			tooltip = entry.description }
		options[#options + 1] = { type = "slider", key = "priority." .. entry.key, label = "    Priority", min = 0,
			max = 100, step = 5,
			tooltip = "Higher comes first. Default " .. (entry.score or 50) .. "." }
	end
	options[#options + 1] = { type = "button", label = "Priorities", text = "Reset", onClick = function()
		for _, entry in ipairs(Sources()) do
			db.priority[entry.key] = entry.score or 50
		end
		module.options = BuildOptions()
		ns.Panel_Refresh()
	end }
	return options
end

module = ns.RegisterModule({
	key = "next",
	name = "Next up",
	category = "General",
	description = "A short list on Home of the best things to do right now: Great Vault rewards waiting, a rare up that "
		.. "drops something you're missing, low durability, full Concentration, world quests worth doing, a vault slot "
		.. "one activity away, achievements one step from done and open knowledge sources. Click one to start it, "
		.. "right-click for \"not now\".",
	enabledByDefault = true,
	defaults = {
		home = true,
		placement = "characters",
		rows = 5,
		perSource = 2,
		dismiss = "login",
		minimap = false,
		sources = {}, -- [entry key] = false when off
		priority = {}, -- [entry key] = 0-100
	},
	home = { Section },
	init = function(saved)
		db = saved
		-- "Under Your characters" became the default after the first build; move the old default over once.
		if not db.placedUnderChars then
			db.placedUnderChars = true
			if db.placement == "column" then
				db.placement = "characters"
			end
		end
		-- Every module file has loaded by now, so every source is registered; fill in what's new.
		for _, entry in ipairs(Sources()) do
			if db.sources[entry.key] == nil then
				db.sources[entry.key] = true
			end
			if db.priority[entry.key] == nil then
				db.priority[entry.key] = entry.score or 50
			end
		end
		module.options = BuildOptions()
	end,
	options = {},
	commands = {
		{ "list", "print what Next up suggests now", function()
			local list = ns.NextUp_Current()
			if #list == 0 then
				ns.Print("nothing pressing.")
			end
			for i, c in ipairs(list) do
				ns.Print(("%d. %s |cff9e9e9e(%s, %d)|r"):format(i, c.text, SourceName(c.source), c.score))
			end
		end },
		{ "reset", "bring back everything you hid with \"not now\"", function()
			wipe(dismissed)
			ns.Print("Next up shows everything again.")
			ns.Panel_Refresh()
		end },
	},
})
