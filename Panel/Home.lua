local addonName, ns = ...

-- The panel's Home view. Home's parts:
--   hero     the current character in 3D (drag to turn) with its name, item level, gold, durability and location
--            (each a button: a tooltip with more, and a click while the module behind it is on), and the quick
--            actions (module.home entries of kind "quick") under it (HomeHero.lua)
--   week     a module section in slot "week" across the top (Weekly board)
--   next     a section in slot "next" (Next up): a strip under the week, under the character list, or on top of the
--            right column, by its place() and the room there is
--   columns  a section in slot "characters" (Alts) on the left; on the right, sections in slots "recent" (Recent)
--            and "events" (Holidays) stacked over "Around you": every entry of kind "around" as an accent heading
--            (it opens the world map) with a few rows (HomeAround.lua)
-- Sections draw themselves (entry.Create/Refresh) with the kit (HomeKit.lua); "around" entries only return data. The
-- hero column hides when the window is narrow. Everything is read again each time Home is shown. The rail beside the
-- views is Rail.lua.

local UI = ns.UI
local Kit = ns.HomeKit
local Snap, PAD = Kit.Snap, Kit.PAD
local HLine, VLine = Kit.HLine, Kit.VLine
local CreateHero, CreateAround = ns.PanelHome_CreateHero, ns.PanelHome_CreateAround

local HERO_W, HERO_MIN_CONTENT = ns.PanelHome_HERO_W, 620 -- the hero hides when the content would get narrower than this
local WEEK_H = 168
local NEXT_UNDER_MIN = 40 + 2 * Kit.ROW2_H -- Next up's heading and two rows: less room under the characters, it moves right
local RESIZE_DELAY = 0.15 -- seconds between Home layouts while the window is resized

-- ns.HomeCall (Core/Modules.lua): a module's summary/count/shown/items; errors go to BugSack and count as "nothing".

-- Home view ------------------------------------------------------------------------------------------------

-- onOpen(entry) runs when a quick action or a map block is clicked.
function ns.PanelHome_Create(parent, onOpen)
	local home = CreateFrame("Frame", nil, parent)
	home.hero = CreateHero(home, onOpen)
	home.heroLine = VLine(home)
	home.content = CreateFrame("Frame", nil, home)
	home.weekLine = HLine(home.content)
	home.nextLine = HLine(home.content)
	home.colLine = VLine(home.content)
	home.around = CreateAround(home.content, onOpen)
	home.sections = {} -- [entry] = frame
	-- Shown when no module adds a section or an "Around you" block. Its text names a few of the modules that do,
	-- not all of them.
	home.empty = UI.Text(home.content, 13, "textMuted")
	home.empty:SetPoint("TOPLEFT", PAD, -PAD)
	home.empty:SetPoint("RIGHT", -PAD, 0)
	home.empty:SetWordWrap(true)
	home.empty:SetText("Nothing to show here yet: turn on Weekly board, Alts, Collect here, World quests or Teleports in Settings.")

	local function Section(entry)
		local frame = home.sections[entry]
		if not frame then
			frame = CreateFrame("Frame", nil, home.content)
			local ok = xpcall(entry.Create, function(err)
				return ns.errorHandler(err)
			end, frame, Kit)
			frame.failed = not ok
			home.sections[entry] = frame
		end
		return frame
	end

	function home:Refresh()
		local width, height = Snap(self:GetWidth()), Snap(self:GetHeight())
		if width <= 1 then
			return
		end
		local showHero = width - HERO_W >= HERO_MIN_CONTENT
		self.hero:SetShown(showHero)
		self.heroLine:SetShown(showHero)
		self.content:ClearAllPoints()
		if showHero then
			self.hero:ClearAllPoints()
			self.hero:SetPoint("TOPLEFT")
			self.hero:SetPoint("BOTTOMLEFT")
			self.heroLine:ClearAllPoints()
			self.heroLine:SetPoint("TOPLEFT", HERO_W, -12)
			self.heroLine:SetPoint("BOTTOMLEFT", HERO_W, 12)
			self.content:SetPoint("TOPLEFT", HERO_W + 1, 0)
			self.hero:Refresh()
		else
			self.content:SetPoint("TOPLEFT")
		end
		self.content:SetPoint("BOTTOMRIGHT")
		local cw = Snap(width - (showHero and HERO_W + 1 or 0))

		-- Which sections are there.
		local byslot = {}
		for _, entry in ipairs(ns.HomeEntries("section")) do
			byslot[entry.slot] = byslot[entry.slot] or entry
		end
		for entry, frame in pairs(self.sections) do
			if byslot[entry.slot] ~= entry then
				frame:Hide()
			end
		end
		local week, chars, nextUp = byslot.week, byslot.characters, byslot.next
		local hasAround = #ns.HomeEntries("around") > 0
		-- "next" (Next up) goes under the character list, across under the week strip, or on top of the right column.
		local nextStrip = nextUp and ns.HomeCall(nextUp.place) == "strip"

		local top = 0
		if week then
			local frame = Section(week)
			frame:ClearAllPoints()
			frame:SetPoint("TOPLEFT", PAD, -16)
			frame:SetSize(cw - 2 * PAD, WEEK_H - 24)
			frame:SetShown(not frame.failed)
			local wanted = not frame.failed and ns.HomeCall(week.Refresh, frame)
			-- The section may ask for less room (a short strip below max level).
			top = type(wanted) == "number" and math.min(wanted + 24, WEEK_H) or WEEK_H
			frame:SetHeight(top - 24)
		end
		self.weekLine:SetShown(week ~= nil and (chars ~= nil or hasAround or nextUp ~= nil))
		self.weekLine:ClearAllPoints()
		self.weekLine:SetPoint("TOPLEFT", 12, -top)
		self.weekLine:SetPoint("TOPRIGHT", -12, -top)

		self.nextLine:Hide()
		if nextUp and nextStrip then
			local frame = Section(nextUp)
			local y = top + (week and 14 or 16)
			frame:ClearAllPoints()
			frame:SetPoint("TOPLEFT", PAD, -y)
			frame:SetSize(cw - 2 * PAD, height / 2)
			frame:SetShown(not frame.failed)
			local wanted = not frame.failed and ns.HomeCall(nextUp.Refresh, frame)
			local h = type(wanted) == "number" and wanted or 0
			frame:SetHeight(math.max(h, 1))
			top = y + h + 6
			self.nextLine:SetShown(chars ~= nil or hasAround)
			self.nextLine:ClearAllPoints()
			self.nextLine:SetPoint("TOPLEFT", 12, -top)
			self.nextLine:SetPoint("TOPRIGHT", -12, -top)
		end

		local colTop = top + 18
		local colH = height - colTop - 16
		-- Next up under the character list (between it and the footer) when there's room for a heading and two rows,
		-- else on top of the right column.
		local nextUnder = nextUp ~= nil and chars ~= nil and not nextStrip and ns.HomeCall(nextUp.place) == "characters"
		local hasRight = hasAround or byslot.recent ~= nil or byslot.events ~= nil or (nextUp ~= nil and not nextStrip and not nextUnder)
		local both = chars ~= nil and hasRight
		local colW = both and Snap((cw - 1) / 2) or cw
		if chars then
			local frame = Section(chars)
			frame:ClearAllPoints()
			frame:SetPoint("TOPLEFT", PAD, -colTop)
			frame:SetSize(colW - 2 * PAD, colH)
			frame:SetShown(not frame.failed)
			local used = not frame.failed and ns.HomeCall(chars.Refresh, frame)
			local room = type(used) == "number" and colH - used - 18 - (frame.footH or 0) - 12 or 0
			if nextUnder and (room >= NEXT_UNDER_MIN or not hasRight) then
				local nf = Section(nextUp)
				nf:ClearAllPoints()
				nf:SetPoint("TOPLEFT", PAD, -(colTop + (used or 0) + 18))
				nf:SetSize(colW - 2 * PAD, math.max(room, 1))
				nf:SetShown(not nf.failed)
				local wanted = not nf.failed and ns.HomeCall(nextUp.Refresh, nf)
				nf:SetHeight(math.max(type(wanted) == "number" and math.min(wanted, room) or 0, 1))
			else
				nextUnder = false
			end
		end
		-- Sections stacked on top of the right column, above Around you.
		local stack = {}
		if nextUp and not nextStrip and not nextUnder then
			stack[#stack + 1] = nextUp
		end
		if byslot.recent then
			stack[#stack + 1] = byslot.recent
		end
		if byslot.events then
			stack[#stack + 1] = byslot.events
		end
		self.colLine:SetShown(both)
		self.colLine:ClearAllPoints()
		self.colLine:SetPoint("TOPLEFT", colW, -(top + 12))
		self.colLine:SetPoint("BOTTOMLEFT", colW, 12)
		local x = both and colW + 1 or 0
		local rightW = (both and cw - colW - 1 or cw) - 2 * PAD
		local aroundTop = colTop
		for _, entry in ipairs(stack) do
			local frame = Section(entry)
			local room = colH - (aroundTop - colTop)
			frame:ClearAllPoints()
			frame:SetPoint("TOPLEFT", x + PAD, -aroundTop)
			frame:SetSize(rightW, math.max(room, 1))
			frame:SetShown(not frame.failed)
			local wanted = not frame.failed and ns.HomeCall(entry.Refresh, frame)
			local h = type(wanted) == "number" and math.min(wanted, room) or 0
			frame:SetHeight(math.max(h, 1))
			if h <= 0 then
				frame:Hide()
			end
			aroundTop = aroundTop + h + (h > 0 and 14 or 0)
		end
		self.around:SetShown(hasAround)
		if hasAround then
			self.around:ClearAllPoints()
			self.around:SetPoint("TOPLEFT", x + PAD, -aroundTop)
			self.around:SetSize(rightW, math.max(colH - (aroundTop - colTop), 1))
			self.around:Refresh()
		end
		self.empty:SetShown(not (week or chars or hasAround or nextUp or byslot.recent or byslot.events))
	end

	-- Size changes come every frame while the window is dragged bigger: refresh at most every RESIZE_DELAY seconds
	-- (a full Home layout per frame is too much, and a short wait still feels live). The timer reads the size when it
	-- fires, so the last size is always drawn.
	home:SetScript("OnSizeChanged", function(self)
		if self:IsVisible() and not self.resizePending then
			self.resizePending = true
			C_Timer.After(RESIZE_DELAY, function()
				self.resizePending = false
				if self:IsVisible() then
					self:Refresh()
				end
			end)
		end
	end)
	return home
end
