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

-- One read function per entry, so the line keeps its fill across Home's redraws.
local progressReads = setmetatable({}, { __mode = "k" })

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

	local function Block(b)
		local block = around.blocks[b]
		if not block then
			-- Heading band: a faint accent strip with a bar on the left, the name, and its counts on the right.
			-- Blocks whose entry has opensMap open the world map first (ns.MapTabs_Opener); the block's own click is its
			-- PostClick.
			block = CreateFrame("Button", nil, around, "InsecureActionButtonTemplate")
			ns.MapTabs_Opener(block, function(btn)
				return btn.entry.opensMap == true
			end)
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
			-- "Collect here: 5 mounts, 7 pets left" -> name in the band, counts on its right.
			local title = ns.HomeCall(bl.entry.title) or bl.entry.name
			local name, rest = title:match("^(.-):%s*(.+)$")
			block.text:SetText(name or title)
			block.text:SetWidth(block.text:GetUnboundedStringWidth() + 2)
			block.meta:SetText(rest or "")
			block:ClearAllPoints()
			block:SetPoint("TOPLEFT", 0, -y)
			block:SetPoint("RIGHT")
			block:Show()
			local read = ProgressRead(bl.entry)
			if read then
				block.progress:Track(read)
			else
				block.progress:Stop()
			end
			y = y + 30
			for i = 1, bl.rows do
				local item = bl.items[i]
				used = used + 1
				local row = Kit.PoolRow(self.rows, used, self, RowOpensMap)
				row:Set(item.icon, item.text, item.color, item.right, item.rightColor)
				row.onEnter = item.onEnter
				local entry = bl.entry
				row.opensMap = item.onClick == nil and entry.opensMap == true
				-- An item's own click (a waypoint, a summon), else the block's.
				row.onClick = item.onClick or function()
					onOpen(entry)
				end
				row:ClearAllPoints()
				row:SetPoint("TOPLEFT", 0, -y)
				row:SetPoint("RIGHT")
				y = y + ROW_H
			end
			y = y + 18
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
