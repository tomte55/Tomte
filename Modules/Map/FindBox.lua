local addonName, ns = ...

-- Tomte map: the search under the town markers button ("Find someone..." in its menu). Type a trainer, banker,
-- mailbox ... and the matches show nearest first, the ones outside your zone under their own heading; a click puts
-- your map pin on one and flies the map there. The search itself is the Find module's (Modules/Find: ns.Find_Search,
-- ns.Find_Pin), looked up when used; opened from Window.lua (TrackMenu).

local WIDTH = 300
local PAD = 8
local SEARCH_H = 22
local ROW_H = 30 -- two lines: who, and where
local HEADING_H = 18
local ICON = 16
local MAX_ROWS = 8 -- matches shown; the rest are further away
local LEVEL_UP = 10 -- frame levels above the button it hangs from

local UI = ns.UI

local box, search, empty
local slots = {} -- rows and headings, reused: { kind = "row" | "heading" }

-- Drawing --------------------------------------------------------------------------------------------------------------

local function Pick(r)
	box:Hide()
	if not ns.Find_Pin(r) then
		ns.Print("can't place a map pin there.")
	end
	if ns.MapWindow_ShowSpot then
		ns.MapWindow_ShowSpot(r.mapID, r.x, r.y, ns.Find_Label(r))
	end
end

local function Slot(i)
	local s = slots[i]
	if s then
		return s
	end
	s = CreateFrame("Button", nil, box)
	s:SetHeight(ROW_H)
	local hover = s:CreateTexture(nil, "HIGHLIGHT")
	hover:SetAllPoints()
	hover:SetColorTexture(UI.Color("hover"))
	s.hover = hover
	s.icon = s:CreateTexture(nil, "ARTWORK")
	s.icon:SetSize(ICON, ICON)
	s.icon:SetPoint("LEFT", 4, 0)
	s.who = UI.Text(s, 12, "text")
	s.who:SetPoint("TOPLEFT", 4 + ICON + 6, -3)
	s.who:SetPoint("RIGHT", -4, 0)
	s.who:SetWordWrap(false)
	s.where = UI.Text(s, 11, "textMuted")
	s.where:SetPoint("TOPLEFT", s.who, "BOTTOMLEFT", 0, -2)
	s.where:SetPoint("RIGHT", -4, 0)
	s.where:SetWordWrap(false)
	s:SetScript("OnClick", function(self)
		if self.row then
			Pick(self.row)
		end
	end)
	slots[i] = s
	return s
end

local function AsRow(s, r)
	s.row = r
	s:SetHeight(ROW_H)
	s:EnableMouse(true)
	s.hover:Show()
	s.icon:SetTexture(r.icon)
	s.icon:Show()
	s.who:ClearAllPoints()
	s.who:SetPoint("TOPLEFT", 4 + ICON + 6, -3)
	s.who:SetPoint("RIGHT", -4, 0)
	UI.SetTextRole(s.who, "text")
	s.who:SetText(r.name and r.title and ("%s %s"):format(r.name, UI.Wrap(r.title, "textMuted"))
		or r.name or r.kindName)
	-- Under the "Outside ..." heading the row needn't say so again.
	s.where:SetText((r.where:gsub("^outside [^:]*: ", "")))
	s.where:Show()
end

local function AsHeading(s, text)
	s.row = nil
	s:SetHeight(HEADING_H)
	s:EnableMouse(false)
	s.hover:Hide()
	s.icon:Hide()
	s.who:ClearAllPoints()
	s.who:SetPoint("LEFT", 4, -2)
	s.who:SetPoint("RIGHT", -4, 0)
	UI.SetTextRole(s.who, "heading")
	s.who:SetText(text)
	s.where:Hide()
end

local function Draw()
	if not box:IsShown() then
		return
	end
	local text = search:GetText() or ""
	local found, me = {}, nil
	if text:find("%S") then
		found, me = ns.Find_Search(text)
	end
	local used, y = 0, -(PAD + SEARCH_H + 6)
	local function Place(s)
		used = used + 1
		s:ClearAllPoints()
		s:SetPoint("TOPLEFT", PAD, y)
		s:SetPoint("RIGHT", -PAD, 0)
		s:Show()
		y = y - s:GetHeight()
	end
	local outside = false
	for i = 1, math.min(#found, MAX_ROWS) do
		local r = found[i]
		if not r.here and not outside then
			outside = true
			local s = Slot(used + 1)
			AsHeading(s, me and me.zone and ("Outside " .. me.zone) or "Outside your zone")
			Place(s)
		end
		local s = Slot(used + 1)
		AsRow(s, r)
		Place(s)
	end
	for i = used + 1, #slots do
		slots[i]:Hide()
		slots[i].row = nil
	end
	if #found == 0 then
		empty:SetText(text:find("%S") and "Nobody found. Try a title or what they do: tailor, banker, mage trainer."
			or "Who are you looking for? A trainer, banker, innkeeper, mailbox, repair ...")
		empty:Show()
		y = y - empty:GetStringHeight() - 4
	else
		empty:Hide()
		if #found > MAX_ROWS then
			y = y - 4
		end
	end
	box:SetHeight(-y + PAD)
end

-- Building -------------------------------------------------------------------------------------------------------------

local function Build(parent)
	box = CreateFrame("Frame", nil, parent)
	box:SetWidth(WIDTH)
	box:EnableMouse(true)
	box:Hide()
	UI.Panel(box, { toast = true })

	search = CreateFrame("EditBox", nil, box)
	search:SetHeight(SEARCH_H)
	search:SetPoint("TOPLEFT", PAD, -PAD)
	search:SetPoint("TOPRIGHT", -PAD, -PAD)
	search:SetAutoFocus(false)
	UI.SearchBoxClear(search)
	UI.SetFont(search, "body", 12)
	UI.SetTextRole(search, "text")
	search:SetTextInsets(UI.SearchTextX(), 8, 0, 0)
	UI.Border(search, "rule")
	search.placeholder = UI.Text(search, 12, "textFaint")
	search.placeholder:SetPoint("LEFT", UI.SearchTextX(), 0)
	search.placeholder:SetText("Find a trainer, banker, mailbox ...")
	local redraw = UI.Debounce(UI.SEARCH_DELAY, Draw)
	search:SetScript("OnTextChanged", function(self)
		self.placeholder:SetShown(self:GetText() == "")
		redraw()
	end)
	search:SetScript("OnEscapePressed", function()
		box:Hide()
	end)
	-- Enter takes the nearest, as the command does.
	search:SetScript("OnEnterPressed", function()
		Draw() -- the list may still wait for typing to pause
		for _, s in ipairs(slots) do
			if s:IsShown() and s.row then
				Pick(s.row)
				return
			end
		end
		search:ClearFocus()
	end)

	empty = UI.Text(box, 12, "textMuted")
	empty:SetPoint("TOPLEFT", PAD + 4, -(PAD + SEARCH_H + 8))
	empty:SetPoint("RIGHT", -PAD - 4, 0)
	empty:SetJustifyH("LEFT")

	box:SetScript("OnShow", function()
		search:SetFocus()
		Draw()
	end)
	box:SetScript("OnHide", function()
		search:ClearFocus()
	end)
	-- Closed with the map, so it doesn't come back by itself the next time the map opens.
	parent:HookScript("OnHide", function()
		box:Hide()
	end)
end

-- Window.lua's town markers menu: opens the search under button (or closes it when open). Says so while Find is off.
function ns.MapFind_Toggle(button)
	if not (ns.Find_IsOn and ns.Find_IsOn()) then
		ns.Print("Find is off: turn it on in the Tomte window (Travel > Find) to search for townsfolk.")
		return
	end
	if not box then
		Build(button:GetParent())
	end
	if box:IsShown() then
		box:Hide()
		return
	end
	box:ClearAllPoints()
	box:SetPoint("TOPRIGHT", button, "BOTTOMRIGHT", 0, -4)
	box:SetFrameLevel(button:GetFrameLevel() + LEVEL_UP)
	box:Show()
end
