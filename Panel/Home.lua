local addonName, ns = ...

-- The panel's Home view and the rail beside every view but Settings. Home shows real content instead of
-- launcher tiles:
--   hero     the current character in 3D (drag to turn) with its name, item level, gold, durability and location,
--            and the quick actions (module.home entries of kind "quick") under it
--   week     a module section in slot "week" across the top (Weekly board)
--   columns  a section in slot "characters" (Alts) on the left, and "Around you" on the right: every entry of kind
--            "around" as a blue heading (it opens the world map) with a few rows
-- Sections draw themselves (entry.Create/Refresh) with the kit below; "around" entries only return data. The hero
-- column hides when the window is narrow. Everything is read again each time Home is shown.

local UI = ns.UI
local GOLD, WHITE, GREY, DIM = UI.GOLD, UI.WHITE, UI.GREY, UI.DIM
local MAP_BLUE = { 0.56, 0.78, 1 }
local DISPLAY_FONT = "Fonts\\MORPHEUS.TTF"
local NARROW_FONT = "Fonts\\ARIALN.TTF"

local HERO_W, HERO_MIN_CONTENT = 290, 620 -- the hero hides when the content would get narrower than this
local WEEK_H = 168
local PAD = 22
local ROW_H = 24
local RAIL_ROW_H, RAIL_HEADER_H = 24, 30
ns.RAIL_W = 170
ns.MAP_BLUE = MAP_BLUE

-- A module's summary/count/shown/items: errors go to BugSack and count as "nothing".
function ns.HomeCall(fn, ...)
	if not fn then
		return nil
	end
	local ok, value = xpcall(fn, function(err)
		return ns.errorHandler(err)
	end, ...)
	if ok then
		return value
	end
	return nil
end

local function SetIcon(texture, entry)
	if entry.atlas then
		texture:SetAtlas(entry.atlas)
	else
		texture:SetTexture(entry.icon or ns.ICON)
	end
end

local function SetColor(fs, c)
	fs:SetTextColor(c[1], c[2], c[3])
end

-- Pixel-exact sizes: fractional widths drop 1 px borders.
local function Snap(value)
	return math.floor(value + 0.5)
end

-- Kit for sections --------------------------------------------------------------------------------------------

local Kit = {}
ns.HomeKit = Kit
Kit.DISPLAY_FONT, Kit.NARROW_FONT = DISPLAY_FONT, NARROW_FONT

-- Section heading: title (display font), meta (grey, after the title) and an optional link on the right.
-- heading:Set(title, meta, linkText, onLink, linkColor)
function Kit.Heading(parent)
	local h = CreateFrame("Frame", nil, parent)
	h:SetHeight(30)
	h.title = UI.Text(h, 22, GOLD, DISPLAY_FONT)
	h.title:SetPoint("BOTTOMLEFT", 0, 4)
	h.meta = UI.Text(h, 12, GREY)
	h.meta:SetPoint("BOTTOMLEFT", h.title, "BOTTOMRIGHT", 12, 3)
	h.link = CreateFrame("Button", nil, h)
	h.link:SetPoint("BOTTOMRIGHT", 0, 6)
	h.link:SetHeight(16)
	h.link.text = UI.Text(h.link, 12, GOLD)
	h.link.text:SetPoint("RIGHT")
	h.link:SetScript("OnEnter", function(self)
		SetColor(self.text, WHITE)
	end)
	h.link:SetScript("OnLeave", function(self)
		SetColor(self.text, self.color)
	end)
	h.link:SetScript("OnClick", function(self)
		PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
		self.onClick()
	end)
	function h:Set(title, meta, linkText, onLink, linkColor)
		self.title:SetText(title or "")
		self.meta:SetText(meta or "")
		self.link:SetShown(linkText ~= nil)
		if linkText then
			self.link.text:SetText(linkText)
			self.link.color = linkColor or GOLD
			SetColor(self.link.text, self.link.color)
			self.link:SetWidth(self.link.text:GetStringWidth())
			self.link.onClick = onLink
		end
	end
	return h
end

-- List row: icon, text and right-aligned text (narrow font). row:Set(icon, text, color, right, rightColor)
-- Optional row.onClick / row.onEnter(row).
function Kit.Row(parent)
	local row = CreateFrame("Button", nil, parent)
	row:SetHeight(ROW_H)
	row.bg = row:CreateTexture(nil, "BACKGROUND")
	row.bg:SetAllPoints()
	row.bg:SetColorTexture(1, 1, 1, 0.04)
	row.bg:Hide()
	row.icon = row:CreateTexture(nil, "ARTWORK")
	row.icon:SetSize(20, 20)
	row.icon:SetPoint("LEFT", 0, 0)
	row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	row.right = row:CreateFontString(nil, "OVERLAY")
	row.right:SetFont(NARROW_FONT, 14, "")
	row.right:SetShadowOffset(1, -1)
	row.right:SetPoint("RIGHT", 0, 0)
	row.right:SetJustifyH("RIGHT")
	row.text = UI.Text(row, 13, WHITE)
	row.text:SetPoint("LEFT", row.icon, "RIGHT", 8, 0)
	row.text:SetPoint("RIGHT", row.right, "LEFT", -10, 0)
	row.text:SetWordWrap(false)
	row:SetScript("OnEnter", function(self)
		if self.onClick then
			self.bg:Show()
		end
		if self.onEnter then
			self.onEnter(self)
		end
	end)
	row:SetScript("OnLeave", function(self)
		self.bg:Hide()
		GameTooltip:Hide()
	end)
	row:SetScript("OnClick", function(self)
		if self.onClick then
			self.onClick(self)
		end
	end)
	function row:Set(icon, text, color, right, rightColor)
		self.icon:SetShown(icon ~= nil)
		if icon then
			self.icon:SetTexture(icon)
		end
		self.text:ClearAllPoints()
		if icon then
			self.text:SetPoint("LEFT", self.icon, "RIGHT", 8, 0)
		else
			self.text:SetPoint("LEFT", 0, 0)
		end
		self.text:SetPoint("RIGHT", self.right, "LEFT", -10, 0)
		self.text:SetText(text or "")
		SetColor(self.text, color or WHITE)
		self.right:SetText(right or "")
		SetColor(self.right, rightColor or GREY)
		self.right:SetWidth(math.min(self.right:GetUnboundedStringWidth() + 2, 160))
	end
	return row
end

-- Rows kept per owner: Rows(pool, i, parent) gives the i-th row, creating it the first time.
function Kit.PoolRow(pool, i, parent)
	local row = pool[i]
	if not row then
		row = Kit.Row(parent)
		pool[i] = row
	end
	row.onClick, row.onEnter = nil, nil
	row:Show()
	return row
end

function Kit.HideFrom(pool, first)
	for i = first, #pool do
		pool[i]:Hide()
	end
end

-- Hairlines ------------------------------------------------------------------------------------------------

local function HLine(parent)
	local t = parent:CreateTexture(nil, "ARTWORK")
	t:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.18)
	t:SetHeight(1)
	return t
end

local function VLine(parent)
	local t = parent:CreateTexture(nil, "ARTWORK")
	t:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.18)
	t:SetWidth(1)
	return t
end

-- Hero: the current character ------------------------------------------------------------------------------

local function Durability()
	local slots = {}
	for slot = INVSLOT_FIRST_EQUIPPED, INVSLOT_LAST_EQUIPPED do
		local cur, max = GetInventoryItemDurability(slot)
		if cur and max and max > 0 then
			slots[#slots + 1] = { slot = slot, cur = cur, max = max }
		end
	end
	local lowest = ns.Durability_Summary(slots)
	return lowest and math.floor(lowest * 100 + 0.5) or nil
end

local function CreateHero(parent, onOpen)
	local hero = CreateFrame("Frame", nil, parent)
	hero:SetWidth(HERO_W)

	-- Stage: the model on a faint floor.
	local stage = CreateFrame("Frame", nil, hero)
	stage:SetPoint("TOPLEFT", 16, -16)
	stage:SetPoint("TOPRIGHT", -16, -16)
	local well = stage:CreateTexture(nil, "BACKGROUND", nil, -1)
	well:SetAllPoints()
	well:SetColorTexture(0.05, 0.05, 0.06, 1)
	UI.Border(stage, GOLD[1], GOLD[2], GOLD[3], 0.22)
	-- A faint floor under the feet; the rest of the stage is the window itself.
	local floor = stage:CreateTexture(nil, "BACKGROUND")
	floor:SetColorTexture(1, 1, 1, 1)
	floor:SetPoint("BOTTOMLEFT", 0, 34)
	floor:SetPoint("BOTTOMRIGHT", 0, 34)
	floor:SetHeight(90)
	floor:SetGradient("VERTICAL", CreateColor(GOLD[1], GOLD[2], GOLD[3], 0.08), CreateColor(GOLD[1], GOLD[2], GOLD[3], 0))

	local model = CreateFrame("PlayerModel", nil, stage)
	model:SetPoint("TOPLEFT", 10, -6)
	model:SetPoint("BOTTOMRIGHT", -10, 34)
	model:EnableMouse(true)
	model.facing = 0.35
	model:SetScript("OnMouseDown", function(self)
		self.dragX = GetCursorPosition()
	end)
	model:SetScript("OnMouseUp", function(self)
		self.dragX = nil
	end)
	model:SetScript("OnUpdate", function(self)
		if self.dragX then
			local x = GetCursorPosition()
			self.facing = self.facing + (x - self.dragX) / 90
			self.dragX = x
			self:SetFacing(self.facing)
		end
	end)
	hero.model = model

	hero.name = UI.Text(stage, 40, GOLD, DISPLAY_FONT)
	hero.name:SetPoint("BOTTOMLEFT", 6, 2)
	hero.name:SetPoint("BOTTOMRIGHT", -6, 2)
	hero.name:SetJustifyH("CENTER")
	hero.name:SetWordWrap(false)
	hero.name:SetShadowOffset(2, -2)
	hero.stage = stage

	hero.who = UI.Text(hero, 13, GREY)
	hero.who:SetPoint("TOP", stage, "BOTTOM", 0, -4)
	hero.who:SetJustifyH("CENTER")

	hero.facts = {}
	for i, label in ipairs({ "Item level", "Gold", "Durability", "Location" }) do
		local l = UI.Text(hero, 13, GREY)
		l:SetText(label)
		local v = hero:CreateFontString(nil, "OVERLAY")
		v:SetFont(NARROW_FONT, 15, "")
		v:SetShadowOffset(1, -1)
		v:SetJustifyH("RIGHT")
		l:SetPoint("TOPLEFT", hero.who, "BOTTOMLEFT", 0, 0) -- placed in Layout
		hero.facts[i] = { label = l, value = v }
	end

	hero.actions = {}
	function hero:Layout(height)
		-- Bottom up: actions, facts, who line; the stage takes what's left.
		local quicks = ns.HomeEntries("quick")
		local y = 18
		for i = #quicks, 1, -1 do
			local entry = quicks[i]
			local b = self.actions[i]
			if not b then
				b = UI.Button(self, 100, "")
				b:SetHeight(24)
				b.label:ClearAllPoints()
				b.label:SetPoint("LEFT", 10, 0)
				b.label:SetJustifyH("LEFT")
				SetColor(b.label, WHITE)
				b:SetScript("OnMouseDown", function(btn)
					btn.label:SetPoint("LEFT", 11, -1)
				end)
				b:SetScript("OnMouseUp", function(btn)
					btn.label:SetPoint("LEFT", 10, 0)
				end)
				UI.SetBorderColor(b, GOLD[1], GOLD[2], GOLD[3], 0.2)
				b:SetScript("OnLeave", function(btn)
					UI.SetBorderColor(btn, GOLD[1], GOLD[2], GOLD[3], 0.2)
				end)
				b.count = UI.Text(b, 12, GOLD)
				b.count:SetPoint("RIGHT", -10, 0)
				b:SetScript("OnClick", function(btn)
					onOpen(btn.entry)
				end)
				self.actions[i] = b
			end
			b.entry = entry
			b.label:SetText(entry.name)
			local count = ns.HomeCall(entry.count)
			b.count:SetText(type(count) == "number" and count > 0 and tostring(count) or "")
			b:ClearAllPoints()
			b:SetPoint("BOTTOMLEFT", PAD, y)
			b:SetPoint("BOTTOMRIGHT", -PAD, y)
			b:Show()
			y = y + 30
		end
		for i = #quicks + 1, #self.actions do
			self.actions[i]:Hide()
		end
		y = y + 8
		for i = #self.facts, 1, -1 do
			local f = self.facts[i]
			f.label:ClearAllPoints()
			f.label:SetPoint("BOTTOMLEFT", PAD, y)
			f.value:ClearAllPoints()
			f.value:SetPoint("BOTTOMRIGHT", -PAD, y)
			f.value:SetPoint("BOTTOMLEFT", f.label, "BOTTOMRIGHT", 10, 0)
			y = y + 21
		end
		self.who:ClearAllPoints()
		self.who:SetPoint("BOTTOMLEFT", PAD, y + 6)
		self.who:SetPoint("BOTTOMRIGHT", -PAD, y + 6)
		self.stage:SetHeight(math.max(height - y - 46, 120))
	end

	function hero:Refresh()
		local class = select(2, UnitClass("player"))
		local color = class and C_ClassColor.GetClassColor(class)
		self.name:SetText(UnitName("player"))
		if color then
			self.name:SetTextColor(color.r, color.g, color.b)
		else
			SetColor(self.name, GOLD)
		end
		local spec
		local index = C_SpecializationInfo.GetSpecialization()
		if index and index > 0 then
			spec = select(2, C_SpecializationInfo.GetSpecializationInfo(index))
		end
		self.who:SetText(("Level %d %s%s"):format(UnitLevel("player"), UnitRace("player") or "", spec and (", " .. spec) or ""))
		local _, equipped = GetAverageItemLevel()
		local values = {
			equipped and tostring(math.floor(equipped)) or "?",
			ns.Alts_Gold and ns.Alts_Gold(GetMoney()) or GetCoinTextureString(GetMoney()),
			(Durability() or 100) .. "%",
			GetSubZoneText() ~= "" and GetSubZoneText() or GetZoneText(),
		}
		for i, f in ipairs(self.facts) do
			f.value:SetText(values[i])
			SetColor(f.value, i == 2 and GOLD or WHITE)
		end
		local dura = Durability()
		if dura and dura < 30 then
			SetColor(self.facts[3].value, { 1, 0.45, 0.35 })
		end
		self.model:SetUnit("player")
		self.model:SetFacing(self.model.facing)
		self:Layout(self:GetHeight())
	end

	hero:SetScript("OnSizeChanged", function(self, _, height)
		self:Layout(height)
	end)
	return hero
end

-- Around you: map entries as headed lists ------------------------------------------------------------------

local function CreateAround(parent, onOpen)
	local around = CreateFrame("Frame", nil, parent)
	around.heading = Kit.Heading(around)
	around.heading:SetPoint("TOPLEFT")
	around.heading:SetPoint("TOPRIGHT")
	around.blocks = {}
	around.rows = {}

	local function Block(b)
		local block = around.blocks[b]
		if not block then
			-- Heading band: a faint blue strip with a bar on the left, the name, and its counts on the right.
			block = CreateFrame("Button", nil, around)
			block:SetHeight(24)
			block.bg = block:CreateTexture(nil, "BACKGROUND")
			block.bg:SetAllPoints()
			block.bg:SetColorTexture(MAP_BLUE[1], MAP_BLUE[2], MAP_BLUE[3], 0.08)
			block.bar = block:CreateTexture(nil, "ARTWORK")
			block.bar:SetColorTexture(MAP_BLUE[1], MAP_BLUE[2], MAP_BLUE[3], 0.9)
			block.bar:SetPoint("TOPLEFT")
			block.bar:SetPoint("BOTTOMLEFT")
			block.bar:SetWidth(2)
			block.text = UI.Text(block, 14, MAP_BLUE)
			block.text:SetPoint("LEFT", 10, 0)
			block.text:SetWordWrap(false)
			block.meta = UI.Text(block, 12, GREY)
			block.meta:SetPoint("RIGHT", -8, 0)
			block.meta:SetJustifyH("RIGHT")
			block.meta:SetPoint("LEFT", block.text, "RIGHT", 12, 0)
			block.meta:SetWordWrap(false)
			block:SetScript("OnEnter", function(btn)
				SetColor(btn.text, WHITE)
				btn.bg:SetColorTexture(MAP_BLUE[1], MAP_BLUE[2], MAP_BLUE[3], 0.16)
				GameTooltip:SetOwner(btn, "ANCHOR_RIGHT")
				GameTooltip:SetText("Opens the world map on this tab", 1, 1, 1)
				GameTooltip:Show()
			end)
			block:SetScript("OnLeave", function(btn)
				SetColor(btn.text, MAP_BLUE)
				btn.bg:SetColorTexture(MAP_BLUE[1], MAP_BLUE[2], MAP_BLUE[3], 0.08)
				GameTooltip:Hide()
			end)
			block:SetScript("OnClick", function(btn)
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
				break
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
			y = y + 30
			for i = 1, bl.rows do
				local item = bl.items[i]
				used = used + 1
				local row = Kit.PoolRow(self.rows, used, self)
				row:Set(item.icon, item.text, item.color, item.right, item.rightColor)
				row.onEnter = item.onEnter
				local entry = bl.entry
				row.onClick = function()
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
	around.none = UI.Text(around, 13, GREY)
	around.none:SetPoint("TOPLEFT", 0, -40)
	around.none:SetPoint("RIGHT")
	around.none:SetWordWrap(true)
	around.none:SetText("Nothing to collect, no world quests and no teleports ready here.")
	return around
end

-- Home view ------------------------------------------------------------------------------------------------

-- onOpen(entry) runs when a quick action or a map block is clicked.
function ns.PanelHome_Create(parent, onOpen)
	local home = CreateFrame("Frame", nil, parent)
	home.hero = CreateHero(home, onOpen)
	home.heroLine = VLine(home)
	home.content = CreateFrame("Frame", nil, home)
	home.weekLine = HLine(home.content)
	home.colLine = VLine(home.content)
	home.around = CreateAround(home.content, onOpen)
	home.sections = {} -- [entry] = frame
	home.empty = UI.Text(home.content, 13, GREY)
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
		local week, chars = byslot.week, byslot.characters
		local hasAround = #ns.HomeEntries("around") > 0

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
		self.weekLine:SetShown(week ~= nil and (chars ~= nil or hasAround))
		self.weekLine:ClearAllPoints()
		self.weekLine:SetPoint("TOPLEFT", 12, -top)
		self.weekLine:SetPoint("TOPRIGHT", -12, -top)

		local colTop = top + 18
		local colH = height - colTop - 16
		local both = chars ~= nil and hasAround
		local colW = both and Snap((cw - 1) / 2) or cw
		if chars then
			local frame = Section(chars)
			frame:ClearAllPoints()
			frame:SetPoint("TOPLEFT", PAD, -colTop)
			frame:SetSize(colW - 2 * PAD, colH)
			frame:SetShown(not frame.failed)
			if not frame.failed then
				ns.HomeCall(chars.Refresh, frame)
			end
		end
		self.colLine:SetShown(both)
		self.colLine:ClearAllPoints()
		self.colLine:SetPoint("TOPLEFT", colW, -(top + 12))
		self.colLine:SetPoint("BOTTOMLEFT", colW, 12)
		self.around:SetShown(hasAround)
		if hasAround then
			local x = both and colW + 1 or 0
			self.around:ClearAllPoints()
			self.around:SetPoint("TOPLEFT", x + PAD, -colTop)
			self.around:SetSize((both and cw - colW - 1 or cw) - 2 * PAD, colH)
			self.around:Refresh()
		end
		self.empty:SetShown(not (week or chars or hasAround))
	end

	-- Size changes come every frame while the window is dragged bigger; refresh once they settle.
	home:SetScript("OnSizeChanged", function(self)
		if self:IsVisible() and not self.resizePending then
			self.resizePending = true
			C_Timer.After(0.15, function()
				self.resizePending = false
				if self:IsVisible() then
					self:Refresh()
				end
			end)
		end
	end)
	return home
end

-- Rail -----------------------------------------------------------------------------------------------------

local function CreateRailRow(parent, onSelect)
	local row = CreateFrame("Button", nil, parent)
	row:SetHeight(RAIL_ROW_H)
	row.bg = row:CreateTexture(nil, "BACKGROUND")
	row.bg:SetAllPoints()
	row.bg:SetColorTexture(1, 1, 1, 0.05)
	row.bar = row:CreateTexture(nil, "ARTWORK")
	row.bar:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 1)
	row.bar:SetPoint("TOPLEFT")
	row.bar:SetPoint("BOTTOMLEFT")
	row.bar:SetWidth(2)
	row.icon = row:CreateTexture(nil, "ARTWORK")
	row.icon:SetSize(16, 16)
	row.icon:SetPoint("LEFT", 12, 0)
	row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	row.text = UI.Text(row, 13, WHITE)
	row.text:SetPoint("LEFT", row.icon, "RIGHT", 8, 0)
	row.text:SetPoint("RIGHT", -6, 0)
	row.text:SetWordWrap(false)
	row:SetScript("OnEnter", function(self)
		self.bg:Show()
		local entry = self.entry
		if entry then
			local summary = ns.HomeCall(entry.summary)
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:SetText(entry.name, GOLD[1], GOLD[2], GOLD[3])
			if type(summary) == "string" and summary ~= "" then
				GameTooltip:AddLine(summary, 1, 1, 1)
			end
			if entry.kind == "map" then
				GameTooltip:AddLine("Opens the world map on this tab", MAP_BLUE[1], MAP_BLUE[2], MAP_BLUE[3])
			end
			GameTooltip:Show()
		end
	end)
	row:SetScript("OnLeave", function(self)
		self.bg:SetShown(self.selected)
		GameTooltip:Hide()
	end)
	row:SetScript("OnClick", function(self)
		onSelect(self.entry)
	end)
	return row
end

-- onSelect(entry) runs on a click; entry is nil for the Home row.
function ns.PanelRail_Create(parent, onSelect)
	local rail = CreateFrame("Frame", nil, parent)
	rail:SetWidth(ns.RAIL_W)
	local bg = rail:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints()
	bg:SetColorTexture(0, 0, 0, 0.25)
	rail.rows = {}
	rail.header = UI.Text(rail, 12, DIM)
	rail.header:SetText("On the world map")

	local function Row(i)
		local row = rail.rows[i]
		if not row then
			row = CreateRailRow(rail, onSelect)
			rail.rows[i] = row
		end
		return row
	end

	local function Place(row, entry, y, selected)
		row.entry = entry
		row.selected = selected
		if entry then
			SetIcon(row.icon, entry)
			row.text:SetText(entry.name)
		else
			row.icon:SetTexture(ns.ICON)
			row.text:SetText("Home")
		end
		local c = selected and GOLD or (entry and entry.kind == "map" and MAP_BLUE or WHITE)
		SetColor(row.text, c)
		row.bar:SetShown(selected)
		row.bg:SetShown(selected or row:IsMouseOver())
		row:ClearAllPoints()
		row:SetPoint("TOPLEFT", rail, "TOPLEFT", 0, -y)
		row:SetPoint("RIGHT", rail, "RIGHT")
		row:Show()
	end

	-- selected: the open page's entry, or nil on Home.
	function rail:Refresh(selected)
		local n, y = 1, 10
		Place(Row(1), nil, y, selected == nil)
		y = y + RAIL_ROW_H + 6
		for _, entry in ipairs(ns.HomeEntries("page")) do
			n = n + 1
			Place(Row(n), entry, y, entry == selected)
			y = y + RAIL_ROW_H
		end
		local maps = ns.HomeEntries("map")
		self.header:SetShown(#maps > 0)
		if #maps > 0 then
			self.header:ClearAllPoints()
			self.header:SetPoint("TOPLEFT", 12, -(y + 14))
			y = y + RAIL_HEADER_H
			for _, entry in ipairs(maps) do
				n = n + 1
				Place(Row(n), entry, y, false)
				y = y + RAIL_ROW_H
			end
		end
		for i = n + 1, #self.rows do
			self.rows[i]:Hide()
		end
	end

	return rail
end
