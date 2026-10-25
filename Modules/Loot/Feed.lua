local addonName, ns = ...

-- Loot: the feed, lines that slide in beside your character and fade after the fade delay: what auto loot took (and
-- what you take by hand, while that setting is on), and the lines that stand in for Blizzard's loot pop-ups,
-- valuable boss loot, reputation and currency (Toasts.lua). Not clickable, so it never takes a click meant for the world. Placed where Edit Mode put it;
-- grows down or up. Text helpers and the strip each line is drawn as are in Parts.lua.
-- A line: a thin bar in the item's quality color, the icon, the name, the extras smaller after it, on a dark strip
-- that fades out to the right, so it reads over the world without a box around it.

local FEED_MAX = 8 -- lines at once; a new one past this sends the oldest away
local BASE_FONT = 12
local LINE_W = 400 -- the widest a line gets; each line fits its text up to this
local LINE_EXTRA = 10 -- line height over the font size
local GAP = 3
local SLIDE = 16 -- pixels a line slides in from
local SLIDE_TIME = 0.25
local FADE_TIME = 0.8
local PULSE, PULSE_ALPHA = 0.5, 0.35 -- seconds and strength of a merged line's flash
local COUNT_TIME = 0.6 -- seconds a merged line's number takes to count up to its new total
-- What Edit Mode shows.
local PREVIEW = {
	{ icon = 135274, name = "Sample blade", quality = 4, detail = { { text = "Upgrade", role = "success" } } },
	{ icon = 132889, name = "Sample cloth", quality = 1, count = 5,
		detail = { { text = "40 owned", role = "textMuted" } } },
	{ icon = 236681, text = "+250 Sample faction", role = "success" }, -- achievement_reputation_01
}

local UI = ns.UI

local db, module
local holder
local lines = {} -- shown, oldest first
local pool = {}
local previewing = false -- Edit Mode's sample lines are up

local function LineHeight()
	return db.fontSize + LINE_EXTRA
end

-- A line sliding in sits this far left of its place (eases out). The slide moves the line's anchor each frame
-- rather than through a Translation animation, which let the strip and the icon and text drift apart while moving.
local function SlideX(f)
	if not f.slide then
		return 0
	end
	local p = math.min(f.slide / SLIDE_TIME, 1)
	return -SLIDE * (1 - p) ^ 2
end

local function Place(f)
	f:ClearAllPoints()
	f:SetPoint(f.at, holder, f.at, SlideX(f), f.atY)
end

local function Layout()
	local h = LineHeight()
	holder:SetSize(LINE_W * db.fontSize / BASE_FONT, h)
	for i, f in ipairs(lines) do
		f:SetSize(math.min(holder:GetWidth(), f.width or holder:GetWidth()), h)
		if db.growUp then
			f.at, f.atY = "BOTTOMLEFT", (i - 1) * (h + GAP)
		else
			f.at, f.atY = "TOPLEFT", -(i - 1) * (h + GAP)
		end
		Place(f)
	end
end

local function Release(f)
	f.inAnim:Stop()
	f.outAnim:Stop()
	f.pulse:Stop()
	f:SetScript("OnUpdate", nil)
	f:Hide()
	f.mergeKey, f.entry, f.copper, f.counting, f.slide = nil, nil, nil, nil, nil
	for i, shown in ipairs(lines) do
		if shown == f then
			table.remove(lines, i)
			break
		end
	end
	pool[#pool + 1] = f
	Layout()
end

local function CreateLine()
	local f = CreateFrame("Frame", nil, holder)
	f:EnableMouse(false)
	ns.LootParts_Strip(f)
	-- Merged: the line flashes in the accent, as a merged whisper toast does.
	f.flash = f:CreateTexture(nil, "BORDER")
	f.flash:SetAllPoints()
	f.flash:SetColorTexture(UI.Color("accent"))
	f.flash:SetAlpha(0)
	f.pulse = f.flash:CreateAnimationGroup()
	local glow = f.pulse:CreateAnimation("Alpha")
	glow:SetFromAlpha(PULSE_ALPHA)
	glow:SetToAlpha(0)
	glow:SetDuration(PULSE)
	glow:SetSmoothing("OUT")
	f.pulse:SetToFinalAlpha(true)

	-- In: fade in while the line slides into place (Tick).
	f.inAnim = f:CreateAnimationGroup()
	local show = f.inAnim:CreateAnimation("Alpha")
	show:SetFromAlpha(0)
	show:SetToAlpha(1)
	show:SetDuration(SLIDE_TIME)

	-- Out: wait the fade delay, then fade.
	f.outAnim = f:CreateAnimationGroup()
	f.outAnim:SetToFinalAlpha(true)
	f.fade = f.outAnim:CreateAnimation("Alpha")
	f.fade:SetFromAlpha(1)
	f.fade:SetToAlpha(0)
	f.fade:SetDuration(FADE_TIME)

	f.inAnim:SetScript("OnFinished", function()
		if not f.static then
			f.fade:SetStartDelay(db.fadeDelay)
			f.outAnim:Play()
		end
	end)
	f.outAnim:SetScript("OnFinished", function()
		Release(f)
	end)
	return f
end

local function Fill(f, spec)
	local size = db.fontSize
	f.static = spec.static
	f:SetAlpha(1)
	f.width = ns.LootParts_FillStrip(f, spec, size, db.bgAlpha, LINE_W * size / BASE_FONT)
end

local function Build()
	holder = CreateFrame("Frame", nil, UIParent)
	holder:SetFrameStrata("MEDIUM")
	holder:SetMovable(true)
	holder:SetClampedToScreen(true)
	holder:EnableMouse(false)
	local p = db.feed
	holder:SetPoint(p.point, UIParent, p.relPoint, p.x, p.y)
	Layout()
end

-- spec = { icon, text, detail (both colored strings), quality (the bar's color) or role (the bar's color without a
-- quality), static (stays until cleared: Edit Mode), mergeKey (a line still up with the same key takes this one) }.
-- Returns the line.

-- A line still up (fading or not) with this merge key.
local function FindMerge(key)
	if not key then
		return nil
	end
	for _, f in ipairs(lines) do
		if f.mergeKey == key then
			return f
		end
	end
	return nil
end

-- A merged line's number counts up from the old total to the new one (spec.count = { from, to, text = fn(n) }).
-- A number on the way can be wider than the total (gold: "1g 87s 43c" before "2g 64s"), so the line widens to fit
-- it instead of cutting it short.
local function CountStep(f, elapsed)
	local c = f.counting
	c.t = c.t + elapsed
	local p = math.min(c.t / COUNT_TIME, 1)
	p = 1 - (1 - p) ^ 3 -- eases out: fast, then settling on the total
	f.text:SetText(c.text(math.floor(c.from + (c.to - c.from) * p + 0.5)))
	local need = math.ceil(f.text:GetUnboundedStringWidth()) - f.text:GetWidth()
	if need > 0 then
		f.text:SetWidth(f.text:GetWidth() + need)
		f.width = f.width + need
		f:SetWidth(math.min(holder:GetWidth(), f.width))
	end
	if p >= 1 then
		f.counting = nil
	end
end

-- Per frame while a line slides in or counts up; off once neither is going.
local function Tick(f, elapsed)
	if f.slide then
		f.slide = f.slide + elapsed
		if f.slide >= SLIDE_TIME then
			f.slide = nil
		end
		Place(f)
	end
	if f.counting then
		CountStep(f, elapsed)
	end
	if not (f.slide or f.counting) then
		f:SetScript("OnUpdate", nil)
	end
end

-- A merged line: new text (counting up to it), flashes, and its fade delay starts again.
local function Merge(f, spec)
	Fill(f, spec)
	Layout()
	local count = spec.count
	if count and count.to > count.from then
		f.counting = { from = count.from, to = count.to, text = count.text, t = 0 }
		f.text:SetText(count.text(count.from))
		f:SetScript("OnUpdate", Tick)
	end
	f.pulse:Stop()
	f.pulse:Play()
	if not (f.static or f.inAnim:IsPlaying()) then -- still sliding in: the slide's end starts the fade
		f.outAnim:Stop()
		f:SetAlpha(1)
		f.fade:SetStartDelay(db.fadeDelay)
		f.outAnim:Play()
	end
	return f
end

function ns.LootFeed_Push(spec)
	if not (module and module.active) then
		return nil
	end
	if not holder then
		Build()
	end
	local same = FindMerge(spec.mergeKey)
	if same then
		return Merge(same, spec)
	end
	if #lines >= FEED_MAX then
		Release(lines[1])
	end
	local f = table.remove(pool) or CreateLine()
	Fill(f, spec)
	f.mergeKey = spec.mergeKey
	f.slide = 0
	lines[#lines + 1] = f
	Layout()
	f:Show()
	f:SetScript("OnUpdate", Tick)
	f.inAnim:Play()
	return f
end

-- What makes two entries the same line: the item (gear by its link, its item level and stats can differ), the
-- currency. Nil: never merged.
local function EntryKey(e)
	if e.kind == "currency" and e.currencyID then
		return "c:" .. e.currencyID
	elseif e.kind == "item" and e.link then
		return ns.Loot_IsGear(e) and ("l:" .. e.link) or ("i:" .. (e.itemID or e.link))
	end
	return nil
end

-- An entry (Read.lua) as a feed line, with the extras that are on; suffix: more colored text after it. The same
-- item again while its line is up adds to that line's count (a suffix, a won roll, stays its own line).
function ns.LootFeed_PushEntry(e, suffix)
	local key = not suffix and EntryKey(e) or nil
	local same = FindMerge(key)
	local count
	if same and same.entry then
		local merged = {}
		for k, v in pairs(e) do
			merged[k] = v -- the new read: its owned count is the current one
		end
		local from = math.max(same.entry.quantity or 1, 1)
		merged.quantity = from + math.max(e.quantity or 1, 1)
		e = merged
		count = { from = from, to = merged.quantity, text = function(n)
			local shown = {}
			for k, v in pairs(merged) do
				shown[k] = v
			end
			shown.quantity = n
			return ns.Loot_NameText(shown)
		end }
	end
	local detail = ns.Loot_PartsText(ns.Loot_Details(e, ns.Loot_DetailOpts("tag")))
	if suffix then
		detail = detail ~= "" and (detail .. "  " .. suffix) or suffix
	end
	local f = ns.LootFeed_Push({ icon = e.icon, text = ns.Loot_NameText(e), detail = detail, quality = e.quality,
		mergeKey = key, count = count })
	if f then
		f.entry = e
	end
end

function ns.LootFeed_PushMoney(copper)
	local same = FindMerge("money")
	local count
	if same and same.copper then
		count = { from = same.copper, to = same.copper + copper, text = ns.Loot_MoneyText }
		copper = copper + same.copper
	end
	local f = ns.LootFeed_Push({ icon = ns.LOOT_MONEY_ICON, text = ns.Loot_MoneyText(copper), role = "warning",
		mergeKey = "money", count = count })
	if f then
		f.copper = copper
	end
end

-- Folded junk from one loot window.
function ns.LootFeed_PushJunk(line)
	ns.LootFeed_Push({
		icon = line.icon,
		quality = 0,
		text = UI.Wrap(ns.Loot_JunkName(line.quantity), ITEM_QUALITY_COLORS[0] or "textMuted"),
		detail = ns.Loot_PartsText(ns.Loot_JunkDetails(line, ns.Loot_DetailOpts())),
	})
end

function ns.LootFeed_Clear()
	previewing = false
	for i = #lines, 1, -1 do
		Release(lines[i])
	end
end

function ns.LootFeed_Relayout()
	if holder then
		Layout()
	end
end

function ns.LootFeed_ResetPosition()
	local p = db.feed
	p.point, p.relPoint, p.x, p.y = "CENTER", "CENTER", 160, -40 -- the `feed` default in Loot.lua
	if holder then
		holder:ClearAllPoints()
		holder:SetPoint(p.point, UIParent, p.relPoint, p.x, p.y)
	end
end

-- Edit Mode -------------------------------------------------------------------------------------------------------

local function SampleSpec(p)
	local text = p.text
	if not text then
		text = ns.Loot_NameText({ kind = "item", name = p.name, quality = p.quality, quantity = p.count })
	end
	return { icon = p.icon, text = text, detail = p.detail and ns.Loot_PartsText(p.detail), quality = p.quality,
		role = p.role }
end

-- Sample lines, kept until Edit Mode closes (also /tomte loot test, where they fade like real ones).
function ns.LootFeed_Preview(static)
	for _, p in ipairs(PREVIEW) do
		local spec = SampleSpec(p)
		spec.static = static
		ns.LootFeed_Push(spec)
	end
end

-- Sample line i of a settings preview, drawn still into host. Returns its width.
local function DrawSampleLine(host, i, p, size, h, growUp, bgAlpha)
	local f = host.feedLines[i]
	if not f then
		f = CreateFrame("Frame", nil, host)
		ns.LootParts_Strip(f)
		host.feedLines[i] = f
	end
	local w = ns.LootParts_FillStrip(f, SampleSpec(p), size, bgAlpha, LINE_W * size / BASE_FONT)
	f:SetSize(w, h)
	f:ClearAllPoints()
	if growUp then
		f:SetPoint("BOTTOMLEFT", 0, (i - 1) * (h + GAP))
	else
		f:SetPoint("TOPLEFT", 0, -(i - 1) * (h + GAP))
	end
	f:Show()
	return w
end

-- The sample lines drawn still into host for a settings preview (Preview.lua), with the settings get(key) answers:
-- the oldest at the top, or at the bottom when the feed grows upward; the reputation line only while those lines are
-- on. Returns their width and height.
function ns.LootFeed_DrawSample(host, get)
	host.feedLines = host.feedLines or {}
	local size, growUp = get("fontSize"), get("growUp")
	local h = size + LINE_EXTRA
	local width, i = 0, 0
	for _, p in ipairs(PREVIEW) do
		if not p.text or get("extras.repCurrency") then
			i = i + 1
			width = math.max(width, DrawSampleLine(host, i, p, size, h, growUp, get("bgAlpha")))
		end
	end
	for n = i + 1, #host.feedLines do
		host.feedLines[n]:Hide()
	end
	return width, i * (h + GAP) - GAP
end

local function RefreshPreview()
	if not db then
		return
	end
	local want = ns.EditMode_Active() and module and module.active
	if want and not previewing then
		ns.LootFeed_Preview(true)
		previewing = true
	elseif not want and previewing then
		ns.LootFeed_Clear()
	end
end

ns.EditMode_Register({
	name = "Loot feed",
	frame = function()
		if not (db and module and module.active) then
			return nil
		end
		if not holder then
			Build()
		end
		return holder
	end,
	refresh = RefreshPreview,
	saved = function()
		local p, at = db.feed, UI.TopLeftPoint(holder)
		p.point, p.relPoint, p.x, p.y = at[1], at[2], at[3], at[4]
	end,
	module = "loot",
	options = { "fontSize", "bgAlpha", "growUp", "fadeDelay", "extras.repCurrency" },
	reset = function()
		ns.LootFeed_ResetPosition()
	end,
})

function ns.LootFeed_Init(moduleDB, lootModule)
	db, module = moduleDB, lootModule
end
