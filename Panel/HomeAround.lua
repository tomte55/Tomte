local addonName, ns = ...

-- Home's "Around you": every entry of kind "around" as an accent heading (it opens the world map) with a few rows.
-- Exports ns.PanelHome_CreateAround for Home.lua; the kit is HomeKit.lua.

local UI = ns.UI
local Kit = ns.HomeKit
local SetColor = Kit.SetColor
local ROW_H = Kit.ROW_H

-- Around you: map entries as headed lists ------------------------------------------------------------------

-- A row without its own click opens its block's tab, so it opens the world map first like the block does.
local function RowOpensMap(row)
	return row.opensMap == true
end

-- The tooltip of a row whose entry gives no onEnter: its text, and what a click does (the item's hint, else the
-- block's click).
local function RowTooltip(row, item, entry)
	GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
	GameTooltip:SetText(item.text or entry.name, UI.Color("heading"))
	local hint = item.hint
	if not hint and not item.onClick then
		hint = "Click: " .. (entry.openText or "Opens the world map on this tab"):gsub("^Opens", "open")
	end
	if hint then
		UI.TipLine(hint, "accent")
	end
	ns.MapTabs_CombatTip(row)
	GameTooltip:Show()
end

-- One read function per entry, so the line keeps its fill across Home's redraws.
local progressReads = setmetatable({}, { __mode = "k" })
local wasReading = setmetatable({}, { __mode = "k" }) -- [entry] = true while its line showed on the last redraw
local lastRows = setmetatable({}, { __mode = "k" }) -- [entry] = rows it showed on the last redraw

local function ProgressRead(entry)
	if not entry.progress then
		return nil
	end
	local read = progressReads[entry]
	if not read then
		read = function()
			return ns.HomeCall(entry.progress)
		end
		progressReads[entry] = read
	end
	return read
end

function ns.PanelHome_CreateAround(parent, onOpen)
	local around = CreateFrame("Frame", nil, parent)
	around:SetClipsChildren(true) -- a first block taller than a short column is cut off at the bottom
	around.heading = Kit.Heading(around)
	around.heading:SetPoint("TOPLEFT")
	around.heading:SetPoint("TOPRIGHT")
	around.blocks = {}
	around.rows = {}

	local placed = {} -- blocks and rows in layout order, from the last Refresh
	local function Place(frame, y)
		frame:ClearAllPoints()
		frame:SetPoint("TOPLEFT", 0, -y)
		frame:SetPoint("RIGHT")
		placed[#placed + 1] = frame
	end

	local function Block(b)
		local block = around.blocks[b]
		if not block then
			-- Heading band: a faint accent strip with a bar on the left, the name, and its counts on the right.
			-- Blocks whose entry has opensMap open the world map first (ns.MapTabs_Opener); the block's own click is its
			-- PostClick.
			block = CreateFrame("Button", nil, around, "InsecureActionButtonTemplate")
			ns.MapTabs_Opener(block, function(btn)
				return btn.entry ~= nil and btn.entry.opensMap == true
			end, true)
			block:SetHeight(24)
			block.bg = block:CreateTexture(nil, "BACKGROUND")
			block.bg:SetAllPoints()
			block.bg:SetColorTexture(UI.RGBA("accent", 0.08))
			block.bar = block:CreateTexture(nil, "ARTWORK")
			block.bar:SetColorTexture(UI.RGBA("accent", 0.9))
			block.bar:SetPoint("TOPLEFT")
			block.bar:SetPoint("BOTTOMLEFT")
			block.bar:SetWidth(2)
			-- Along the band's bottom edge while the entry is still reading (its progress()).
			block.progress = UI.ProgressLine(block)
			block.progress:SetPoint("BOTTOMLEFT", block.bar, "BOTTOMRIGHT")
			block.progress:SetPoint("BOTTOMRIGHT")
			block.text = UI.Text(block, 14, "accent")
			block.text:SetPoint("LEFT", 10, 0)
			block.text:SetWordWrap(false)
			block.meta = UI.Text(block, 12, "textMuted")
			block.meta:SetPoint("RIGHT", -8, 0)
			block.meta:SetJustifyH("RIGHT")
			block.meta:SetPoint("LEFT", block.text, "RIGHT", 12, 0)
			block.meta:SetWordWrap(false)
			block:SetScript("OnEnter", function(btn)
				SetColor(btn.text, "text")
				btn.bg:SetColorTexture(UI.RGBA("accent", 0.16))
				GameTooltip:SetOwner(btn, "ANCHOR_RIGHT")
				GameTooltip:SetText(btn.entry.openText or "Opens the world map on this tab", UI.Color("text"))
				ns.MapTabs_CombatTip(btn)
				GameTooltip:Show()
			end)
			block:SetScript("OnLeave", function(btn)
				SetColor(btn.text, "accent")
				btn.bg:SetColorTexture(UI.RGBA("accent", 0.08))
				GameTooltip:Hide()
			end)
			block:SetScript("PostClick", function(btn)
				onOpen(btn.entry)
			end)
			around.blocks[b] = block
		end
		return block
	end

	-- Blocks with rows only; each gets at least two rows, the rest of the column goes to them in order (an entry's
	-- maxRows caps it).
	function around:Refresh()
		local zone = GetZoneText()
		self.heading:Set("Around you", zone ~= "" and zone or nil)
		local height = self:GetHeight()
		local blocks = {}
		for _, entry in ipairs(ns.HomeEntries("around")) do
			local items = ns.HomeCall(entry.items, entry.maxRows or 12) or {}
			if #items > 0 or entry.keepEmpty then
				blocks[#blocks + 1] = { entry = entry, items = items, rows = 0 }
			end
		end
		local free = math.floor((height - 40 - #blocks * 48) / ROW_H)
		for pass = 1, 2 do
			for _, bl in ipairs(blocks) do
				local cap = pass == 1 and math.min(#bl.items, 2) or #bl.items
				local add = math.max(math.min(cap - bl.rows, free), 0)
				bl.rows, free = bl.rows + add, free - add
			end
		end
		for _, bl in ipairs(blocks) do
			if bl.rows < #bl.items then
				bl.items = ns.HomeCall(bl.entry.items, bl.rows) or {}
				bl.rows = math.min(bl.rows, #bl.items)
			end
		end
		local y, used, shown = 40, 0, 0
		wipe(placed)
		local opens, opensFrom = 0, nil -- a block that just finished: its rows' height, and what slides below it
		for b, bl in ipairs(blocks) do
			if y + 30 + (bl.rows > 0 and ROW_H or 0) > height then
				if b > 1 then
					break
				end
				-- Too short even for the first block: its band anyway (clipped), with the rows that fit, so the
				-- column isn't blank.
				bl.rows = math.max(math.min(bl.rows, math.floor((height - y - 30) / ROW_H)), 0)
			end
			shown = b
			local block = Block(b)
			block.entry = bl.entry
			ns.MapTabs_OpenerSync(block)
			-- "Collect here: 5 mounts, 7 pets left" -> name in the band, counts on its right.
			local title = ns.HomeCall(bl.entry.title) or bl.entry.name
			local name, rest = title:match("^(.-):%s*(.+)$")
			block.text:SetText(name or title)
			block.text:SetWidth(block.text:GetUnboundedStringWidth() + 2)
			block.meta:SetText(rest or "")
			Place(block, y)
			block:Show()
			local read = ProgressRead(bl.entry)
			local reading = read ~= nil and block.progress:Track(read)
			if not read then
				block.progress:Stop()
			end
			-- Done reading since the last redraw: the counts and the new rows fade in (the name stays), and the rows'
			-- space opens smoothly.
			local arrived = wasReading[bl.entry] and not reading
			wasReading[bl.entry] = reading or nil
			if arrived then
				UI.FadeIn(block.meta)
			end
			local grows = arrived and (bl.rows - (lastRows[bl.entry] or 0)) * ROW_H or 0
			lastRows[bl.entry] = bl.rows
			local firstRow = used + 1
			y = y + 30
			for i = 1, bl.rows do
				local item = bl.items[i]
				used = used + 1
				local row = Kit.PoolRow(self.rows, used, self, RowOpensMap)
				row:Set(item.icon, item.text, item.color, item.right, item.rightColor)
				row.onEnter = item.onEnter
				local entry = bl.entry
				row.opensMap = item.onClick == nil and entry.opensMap == true
				ns.MapTabs_OpenerSync(row)
				if not item.onEnter then
					row.onEnter = function(r)
						RowTooltip(r, item, entry)
					end
				end
				-- An item's own click (a waypoint, a summon), else the block's.
				row.onClick = item.onClick or function()
					onOpen(entry)
				end
				Place(row, y)
				y = y + ROW_H
			end
			if arrived then
				UI.FadeInRows(self.rows, firstRow, used, UI.FADE_SPREAD)
			end
			if grows > 0 and not opensFrom then
				opens, opensFrom = grows, #placed + 1
			end
			y = y + 18
		end
		-- Everything below the block that opened slides down into place.
		if opensFrom then
			UI.SlideDown(placed, opensFrom, #placed, opens)
		end
		for b = shown + 1, #self.blocks do
			self.blocks[b]:Hide()
		end
		Kit.HideFrom(self.rows, used + 1)
		self.none:SetShown(#blocks == 0)
	end
	around.none = UI.Text(around, 13, "textMuted")
	around.none:SetPoint("TOPLEFT", 0, -40)
	around.none:SetPoint("RIGHT")
	around.none:SetWordWrap(true)
	around.none:SetText("Nothing around you right now.")
	return around
end
