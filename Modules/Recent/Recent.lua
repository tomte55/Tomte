local addonName, ns = ...

-- Recent: every toast and banner Tomte shows also goes into a feed (Toast.lua and Banner.lua call ns.Recent_Note),
-- so one you missed while tabbed out, fighting or in a cinematic can be read later. A page in the Home rail with a
-- quick action that counts what's new, or a block on Home. Entries are saved (account-wide, each with its
-- character); their click actions only last for this session. Logic in Data.lua.

local UI = ns.UI
local GOLD, WHITE, GREY, DIM = UI.GOLD, UI.WHITE, UI.GREY, UI.DIM
local ROW_H = 42
local BLOCK_ROW_H = 24
local BLOCK_ROWS = 4
local HEAD_H = 40

-- Owners with a checkbox under "Include" (anything else is always included).
local OWNERS = {
	{ "whispers", "Whispers" }, { "mentions", "Mentions" }, { "friends", "Friends online" },
	{ "gear", "Gear upgrades" }, { "ach", "Almost Done" }, { "collect", "Collect here" }, { "wq", "World quests" },
	{ "weekly", "Concentration" }, { "dura", "Durability" }, { "vendor", "Vendor" }, { "recap", "Session recap" },
	{ "moments", "Moments (banners)" }, { "hunter", "Hunter pet check (banners)" }, { "pet", "Pet health (banners)" },
}
local SKIP = { toast = true } -- the "Toast position" sample

local module, db
local actions = setmetatable({}, { __mode = "k" }) -- [entry] = onClick, this session only
local page

local function Secret(value)
	return issecretvalue ~= nil and issecretvalue(value)
end

local function Who()
	local _, class = UnitClass("player")
	return { guid = UnitGUID("player"), char = UnitName("player"), class = class }
end

local function Visible()
	return ns.Recent_Visible(db.entries, db.scope, UnitGUID("player"), db.include)
end

local function Unseen()
	return ns.Recent_Unseen(Visible(), db.seenAt)
end

local function UpdateDot()
	if ns.Minimap_SetDot then
		ns.Minimap_SetDot(module.active and db.dot and Unseen() > 0)
	end
end

local function MarkSeen()
	db.seenAt = GetServerTime()
	UpdateDot()
end

function ns.Recent_Note(spec, banner)
	if not (module and module.active) or SKIP[spec.owner] then
		return
	end
	local ok, err = pcall(function()
		local entry = ns.Recent_FromSpec(spec, Who(), GetServerTime(), Secret, banner)
		ns.Recent_Add(db.entries, entry, db.max, 10)
		if spec.onClick then
			actions[entry] = spec.onClick
		end
	end)
	if not ok then
		ns.errorHandler(err)
		return
	end
	if page and page:IsVisible() then
		page.Refresh()
		MarkSeen()
	else
		UpdateDot()
	end
end

local function Run(entry)
	local action = actions[entry]
	if not action then
		return
	end
	PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
	ns.Panel_Hide()
	action("LeftButton")
end

local function ColorHex(c)
	return ("%02x%02x%02x"):format(c[1] * 255, c[2] * 255, c[3] * 255)
end

local function SetIcon(texture, e)
	if e.iconAtlas then
		texture:SetAtlas(e.iconAtlas)
	else
		texture:SetTexture(e.icon or ns.ICON)
	end
end

local function Tooltip(row, e)
	GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
	GameTooltip:SetText(e.title or e.label or "?", 1, 1, 1, 1, true)
	if e.text then
		GameTooltip:AddLine(e.text, GREY[1], GREY[2], GREY[3], true)
	end
	GameTooltip:AddLine(" ")
	GameTooltip:AddLine(("%s, %s ago"):format(e.char or "?", ns.Recent_Ago(GetServerTime() - e.at)), DIM[1] * 2, DIM[2] * 2, DIM[3] * 2)
	if actions[e] then
		GameTooltip:AddLine("Click: same as clicking the toast", GOLD[1], GOLD[2], GOLD[3])
	end
	GameTooltip:Show()
end

-- Page ------------------------------------------------------------------------------------------------------------

local function CreateRow(parent)
	local row = CreateFrame("Button", nil, parent)
	row:SetHeight(ROW_H)
	row.bg = row:CreateTexture(nil, "BACKGROUND")
	row.bg:SetAllPoints()
	row.bg:SetColorTexture(1, 1, 1, 0.04)
	row.bg:Hide()
	row.bar = row:CreateTexture(nil, "ARTWORK")
	row.bar:SetPoint("TOPLEFT", 0, -4)
	row.bar:SetPoint("BOTTOMLEFT", 0, 4)
	row.bar:SetWidth(2)
	row.icon = row:CreateTexture(nil, "ARTWORK")
	row.icon:SetSize(28, 28)
	row.icon:SetPoint("LEFT", 10, 0)
	row.ago = row:CreateFontString(nil, "OVERLAY")
	row.ago:SetFont(ns.HomeKit.NARROW_FONT, 13, "")
	row.ago:SetPoint("TOPRIGHT", -4, -6)
	row.ago:SetJustifyH("RIGHT")
	row.title = UI.Text(row, 13, WHITE)
	row.title:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 10, 1)
	row.title:SetPoint("RIGHT", row.ago, "LEFT", -10, 0)
	row.title:SetWordWrap(false)
	row.text = UI.Text(row, 12, GREY)
	row.text:SetPoint("TOPLEFT", row.title, "BOTTOMLEFT", 0, -3)
	row.text:SetPoint("RIGHT", -4, 0)
	row.text:SetWordWrap(false)
	row:SetScript("OnEnter", function(self)
		self.bg:Show()
		Tooltip(self, self.entry)
	end)
	row:SetScript("OnLeave", function(self)
		self.bg:Hide()
		GameTooltip:Hide()
	end)
	row:SetScript("OnClick", function(self)
		Run(self.entry)
	end)
	return row
end

local function SetRow(row, e, now)
	row.entry = e
	SetIcon(row.icon, e)
	local accent = e.accent or GOLD
	row.bar:SetColorTexture(accent[1], accent[2], accent[3], 0.9)
	local label = e.label and ("|cff%s%s|r  "):format(ColorHex(accent), e.label) or ""
	local count = (e.count or 1) > 1 and ("  |cff9e9e9ex%d|r"):format(e.count) or ""
	row.title:SetText(label .. (e.title or "") .. count)
	local text = (e.text or ""):gsub("\n", "  ")
	if db.scope ~= "char" and e.guid ~= UnitGUID("player") and e.char then
		text = ("%s  |cff666666(%s)|r"):format(text, e.char)
	end
	row.text:SetText(text)
	row.ago:SetText(ns.Recent_Ago(now - e.at))
	row.ago:SetTextColor(GREY[1], GREY[2], GREY[3])
	local live = actions[e] ~= nil
	row.icon:SetDesaturated(not live)
	row.title:SetAlpha(live and 1 or 0.7)
end

local function DayOf(t)
	return date("%Y%j", t)
end

local RecentPage = {
	title = "Recent",
	Create = function(frame)
		page = frame
		frame.clear = UI.Button(frame, 70, "Clear")
		frame.clear:SetPoint("TOPRIGHT", -8, 4)
		frame.clear:SetScript("OnClick", function()
			local dialog = StaticPopup_Show("TOMTE_CONFIRM", "Clear the Recent list?")
			if dialog then
				dialog.data = function()
					wipe(db.entries)
					frame.Refresh()
					UpdateDot()
				end
			end
		end)
		frame.info = UI.Text(frame, 12, GREY)
		frame.info:SetPoint("TOPLEFT", 8, 0)
		frame.info:SetPoint("RIGHT", frame.clear, "LEFT", -12, 0)
		frame.scroll = UI.Scroll(frame)
		frame.scroll:SetPoint("TOPLEFT", 0, -30)
		frame.scroll:SetPoint("BOTTOMRIGHT", -10, 0)
		frame.rows, frame.headers = {}, {}
		frame.none = UI.Text(frame.scroll.content, 13, GREY)
		frame.none:SetPoint("TOPLEFT", 8, -8)
		frame.none:SetText("Nothing yet. Toasts and banners show up here after they've been on screen.")
		function frame.Refresh()
			local list = Visible()
			local now = GetServerTime()
			frame.info:SetText(("%d entr%s · %s"):format(#list, #list == 1 and "y" or "ies",
				db.scope == "char" and "this character" or "all characters"))
			local content = frame.scroll.content
			local y, h, lastGroup = 0, 0, nil
			for i, e in ipairs(list) do
				local group = ns.Recent_Group(e.at, now, DayOf)
				if group ~= lastGroup then
					lastGroup = group
					h = h + 1
					local head = frame.headers[h]
					if not head then
						head = UI.Text(content, 14, GOLD, ns.HomeKit.DISPLAY_FONT)
						frame.headers[h] = head
					end
					head:SetText(group)
					head:ClearAllPoints()
					head:SetPoint("TOPLEFT", 8, -(y + 8))
					head:Show()
					y = y + 30
				end
				local row = frame.rows[i]
				if not row then
					row = CreateRow(content)
					frame.rows[i] = row
				end
				SetRow(row, e, now)
				row:ClearAllPoints()
				row:SetPoint("TOPLEFT", 0, -y)
				row:SetPoint("RIGHT")
				row:Show()
				y = y + ROW_H
			end
			for i = #list + 1, #frame.rows do
				frame.rows[i]:Hide()
			end
			for i = h + 1, #frame.headers do
				frame.headers[i]:Hide()
			end
			frame.none:SetShown(#list == 0)
			frame.scroll:SetContentHeight(y)
		end
		frame:HookScript("OnShow", MarkSeen)
	end,
	Refresh = function(frame)
		frame.Refresh()
		MarkSeen()
	end,
}

-- Home block (setting "Show as: Block on Home") --------------------------------------------------------------------

local function CreateBlock(frame, Kit)
	frame.Kit = Kit
	frame.heading = Kit.Heading(frame)
	frame.heading:SetPoint("TOPLEFT")
	frame.heading:SetPoint("TOPRIGHT")
	frame.rows = {}
end

local function RefreshBlock(frame)
	local Kit = frame.Kit
	local list = Visible()
	local unseen = ns.Recent_Unseen(list, db.seenAt)
	frame.heading:Set("Recent", unseen > 0 and (unseen .. " new") or nil, "Clear", function()
		wipe(db.entries)
		ns.Panel_Refresh()
	end)
	local now = GetServerTime()
	local n = math.min(#list, BLOCK_ROWS)
	for i = 1, n do
		local e = list[i]
		local row = Kit.PoolRow(frame.rows, i, frame)
		local accent = e.accent or GOLD
		local text = ("|cff%s%s|r %s"):format(ColorHex(accent), e.title or e.label or "", (e.text or ""):gsub("\n", "  "))
		row:Set(e.icon, text, WHITE, ns.Recent_Ago(now - e.at))
		if e.iconAtlas then
			row.icon:SetAtlas(e.iconAtlas)
			row.icon:Show()
		end
		row.onClick = actions[e] and function()
			Run(e)
		end or nil
		row.onEnter = function(self)
			Tooltip(self, e)
		end
		row:ClearAllPoints()
		row:SetPoint("TOPLEFT", 0, -(HEAD_H + (i - 1) * BLOCK_ROW_H))
		row:SetPoint("RIGHT")
	end
	Kit.HideFrom(frame.rows, n + 1)
	MarkSeen()
	if n == 0 then
		return 0 -- nothing to show: no block
	end
	return HEAD_H + n * BLOCK_ROW_H
end

-- Options ---------------------------------------------------------------------------------------------------------

local function BuildOptions()
	local options = {
		{ type = "dropdown", key = "show", label = "Show as", choices = function()
			return { { value = "page", text = "Page + quick action" }, { value = "block", text = "Block on Home" } }
		end, tooltip = "A Recent page in the rail with a quick action that counts what's new, or the newest few on Home "
			.. "(right column)." },
		{ type = "dropdown", key = "scope", label = "Whose", choices = function()
			return { { value = "account", text = "All characters" }, { value = "char", text = "This character" } }
		end },
		{ type = "checkbox", key = "keep", label = "Keep after reload",
			tooltip = "Saved entries come back after a reload or the next login (greyed out: their click only works in the session they came from)." },
		{ type = "slider", key = "max", label = "Entries kept", min = 20, max = 100, step = 10 },
		{ type = "checkbox", key = "dot", label = "Dot on the minimap button", onChange = UpdateDot,
			tooltip = "A dot on Tomte's minimap button while there's something you haven't seen." },
		{ type = "header", label = "Include" },
		{ type = "checkbox", key = "include.banners", label = "Banners",
			tooltip = "Title-card banners (Moments, pet checks, repair warnings), not just toasts." },
	}
	for _, o in ipairs(OWNERS) do
		options[#options + 1] = { type = "checkbox", key = "include." .. o[1], label = o[2] }
	end
	return options
end

local function Defaults()
	local include = { banners = true }
	for _, o in ipairs(OWNERS) do
		include[o[1]] = true
	end
	return {
		entries = {},
		seenAt = 0,
		show = "page",
		scope = "account",
		keep = true,
		max = 50,
		dot = false,
		include = include,
	}
end

module = ns.RegisterModule({
	key = "recent",
	name = "Recent",
	category = "General",
	description = "Every toast and banner Tomte shows also goes into a Recent list, so one you missed (tabbed out, in "
		.. "a fight, in a cinematic) can be read later and clicked like the toast.",
	enabledByDefault = true,
	defaults = Defaults(),
	keep = { "seenAt" }, -- collected data: a settings reset keeps it
	home = {
		{ kind = "page", key = "recentpage", order = 6, name = "Recent", icon = "Interface\\Icons\\INV_Letter_15",
			page = RecentPage,
			shown = function()
				return db.show == "page"
			end,
			summary = function()
				local n = Unseen()
				return n > 0 and (n .. " new") or "Nothing new"
			end },
		{ kind = "quick", key = "recentquick", order = 0, name = "Recent",
			open = function()
				ns.Panel_OpenPage("recentpage")
			end,
			count = Unseen,
			shown = function()
				return db.show == "page"
			end },
		{ kind = "section", slot = "recent", key = "recentsection", Create = CreateBlock, Refresh = RefreshBlock,
			shown = function()
				return db.show == "block"
			end },
	},
	init = function(saved)
		db = saved
		if not db.keep then
			wipe(db.entries)
		end
		module.options = BuildOptions()
	end,
	toggle = function(active)
		UpdateDot()
	end,
	options = {},
	commands = {
		{ "open", "open the Recent page", function()
			ns.Panel_OpenPage("recentpage")
		end },
		{ "clear", "clear the list", function()
			wipe(db.entries)
			UpdateDot()
			ns.Print("Recent cleared.")
		end },
	},
})
