local addonName, ns = ...

-- The board's "This week" view: a Great Vault band (three slot boxes per track and what the next slot needs) over two
-- columns, To do (weekly quests, open knowledge sources) and Progress (crests, lockouts). Side by side when
-- the page is wide enough, else stacked; all in one scroll. Draws Data.lua's Weekly_BoardModel.

local UI = ns.UI
local SLOT_W, SLOT_H, SLOT_GAP = 72, 30, 8
local LABEL_W = 110
local HEAD_H = 34 -- a Kit heading and the gap under it
local BANNER_H = 32
local COL_GAP = 40
local TWO_COLUMNS = 760

function ns.WeeklyWeekView(parent)
	local Kit = ns.HomeKit
	local view = {}
	view.scroll = UI.Scroll(parent)
	local c = view.scroll.content

	view.banner = CreateFrame("Frame", nil, c)
	view.banner:SetHeight(BANNER_H)
	local bg = view.banner:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints()
	bg:SetColorTexture(UI.RGBA("accent", 0.14))
	UI.Border(view.banner, "accent", 0.5)
	view.banner.text = UI.Text(view.banner, 14, "heading")
	view.banner.text:SetPoint("LEFT", 12, 0)
	view.banner.text:SetText("Great Vault rewards waiting: open it before you queue")

	view.vaultHead = Kit.Heading(c)
	view.tracks = {}
	for t = 1, #ns.WEEKLY_TRACKS do
		local track = { slots = {} }
		track.label = UI.Text(c, 14, "text")
		for i = 1, 3 do
			track.slots[i] = ns.WeeklySlot_Create(c, SLOT_W, SLOT_H, 15)
		end
		track.note = UI.Text(c, 13, "textMuted")
		view.tracks[t] = track
	end
	view.vaultNone = UI.Text(c, 13, "textMuted")
	view.vaultNone:SetText("No vault data yet. It fills in a moment after login.")

	view.divider = c:CreateTexture(nil, "ARTWORK")
	view.divider:SetHeight(1)
	view.divider:SetColorTexture(UI.RGBA("frame", 0.18))
	view.colLine = c:CreateTexture(nil, "ARTWORK")
	view.colLine:SetWidth(1)
	view.colLine:SetColorTexture(UI.RGBA("frame", 0.18))

	local function Column()
		local col = { head = Kit.Heading(c), frame = CreateFrame("Frame", nil, c) }
		col.rows = ns.WeeklyRows(col.frame)
		return col
	end
	view.todo, view.progress = Column(), Column()

	-- Places a column at x, y with width w; returns its height.
	local function PlaceColumn(col, title, items, x, y, w)
		col.head:ClearAllPoints()
		col.head:SetPoint("TOPLEFT", x + 8, -y)
		col.head:SetWidth(w - 16)
		col.head:Set(title)
		col.frame:ClearAllPoints()
		col.frame:SetPoint("TOPLEFT", x, -(y + HEAD_H))
		col.frame:SetWidth(w)
		local h = col.rows:Render(items)
		col.frame:SetHeight(math.max(h, 1))
		return HEAD_H + h
	end

	function view:Render(model, width)
		width = math.max(width or 0, 300)
		local y = 8
		self.banner:SetShown(model.vaultReady == true)
		if model.vaultReady then
			self.banner:ClearAllPoints()
			self.banner:SetPoint("TOPLEFT", 8, -y)
			self.banner:SetPoint("RIGHT", c, "RIGHT", -8, 0)
			y = y + BANNER_H + 12
		end

		self.vaultHead:ClearAllPoints()
		self.vaultHead:SetPoint("TOPLEFT", 8, -y)
		self.vaultHead:SetWidth(width - 16)
		self.vaultHead:Set("Great Vault")
		y = y + HEAD_H + 4
		for t, track in ipairs(self.tracks) do
			local row = model.vault[t]
			local shown = row ~= nil
			track.label:SetShown(shown)
			track.note:SetShown(shown)
			for i, slot in ipairs(track.slots) do
				slot:SetShown(shown)
				if shown then
					slot:ClearAllPoints()
					slot:SetPoint("TOPLEFT", 8 + LABEL_W + (i - 1) * (SLOT_W + SLOT_GAP), -y)
					ns.WeeklySlot_Set(slot, row.slots[i], i == row.nextSlot, true)
				end
			end
			if shown then
				track.label:ClearAllPoints()
				track.label:SetPoint("LEFT", track.slots[1], "LEFT", -LABEL_W, 0)
				track.label:SetText(row.label)
				track.note:ClearAllPoints()
				track.note:SetPoint("LEFT", track.slots[3], "RIGHT", 20, 0)
				track.note:SetText(row.note)
				UI.SetTextRole(track.note, row.done and "accent" or "textMuted")

				y = y + SLOT_H + SLOT_GAP
			end
		end
		self.vaultNone:SetShown(#model.vault == 0)
		if #model.vault == 0 then
			self.vaultNone:ClearAllPoints()
			self.vaultNone:SetPoint("TOPLEFT", 16, -y)
			y = y + 24
		end

		y = y + 10
		self.divider:ClearAllPoints()
		self.divider:SetPoint("TOPLEFT", 8, -y)
		self.divider:SetPoint("RIGHT", c, "RIGHT", -8, 0)
		y = y + 14

		local todo = model.todo
		if #todo == 0 then
			todo = { { kind = "row", left = "Nothing left to do this week.", state = "done" } }
		end
		local two = width >= TWO_COLUMNS
		local colW = two and math.floor((width - COL_GAP) / 2) or width
		local h1 = PlaceColumn(self.todo, "To do", todo, 0, y, colW)
		local bottom
		self.colLine:SetShown(two and #model.progress > 0)
		if #model.progress == 0 then
			self.progress.head:Hide()
			self.progress.rows:Clear()
			bottom = y + h1
		elseif two then
			self.progress.head:Show()
			local h2 = PlaceColumn(self.progress, "Progress", model.progress, colW + COL_GAP, y, colW)
			bottom = y + math.max(h1, h2)
			self.colLine:ClearAllPoints()
			self.colLine:SetPoint("TOPLEFT", colW + COL_GAP / 2, -(y + 4))
			self.colLine:SetHeight(math.max(h1, h2) - 4)
		else
			self.progress.head:Show()
			local y2 = y + h1 + 20
			bottom = y2 + PlaceColumn(self.progress, "Progress", model.progress, 0, y2, width)
		end
		self.scroll:SetContentHeight(bottom + 16)
	end

	return view
end
