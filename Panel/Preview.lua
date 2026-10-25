local addonName, ns = ...

-- Setting previews: a card under a settings row's tooltip while the mouse is on the row, showing what the setting
-- changes. It's drawn live by the module's own drawing code with sample data, so it follows the theme, the font and
-- the module's other settings. An options row opts in with preview = function(host, get) -> width, height:
--   host: a frame of that preview function's own (the same one every time, so it can build into it once).
--   get(key): one of the module's settings by its options key ("extras.owned"). For the row's own key it's the choice
--     under the mouse (a segment, an item in the open dropdown list), else the saved value, so clicking a switch
--     changes the picture.
-- A preview of something that a switch turns on is ns.Preview_When(switchKey, fn): while that switch is off it has
-- nothing to show, and the card tries again with it (and the switches the row hangs on, and a switch row itself)
-- turned on, captioned "when on" (PanelLayout_PreviewOverrides in Layout.lua): a player deciding whether to turn
-- something on sees what it gives. Rows that change nothing visible get no preview.
--   choosing (third argument): true while the mouse is on one of the row's choices (a segment, a list item) rather
--     than on the row, so a preview can tell "show this choice" from "explain the row".
--   Returns the size it drew in host's units, or nil for nothing to show (the card stays hidden).
-- During the draw the same values sit in the module's db, so code that reads db (tooltip lines, shared helpers) draws
-- them too; the saved values go back right after, and no onChange runs.
-- Real size up to MAX_W x MAX_H, shrunk evenly past that (PanelLayout_PreviewScale in Layout.lua). Redrawn after each
-- change to the module's settings while it shows (a slider dragged, a switch clicked). Rows call in from
-- OptionRows.lua, on the module pages only: Edit Mode's settings dialog shows the real widget instead.

local MAX_W, MAX_H = 420, 340
local PAD = 10
local CAPTION_H = 18 -- the "Preview" line over the drawing
local GAP = 4 -- from the tooltip, the row or the dropdown list

local UI = ns.UI

local card
local hosts = {} -- [preview function] = its host frame
local needs = {} -- [a Preview_When function] = { key = the switch it needs, fn = the preview it wraps }
-- While the card shows: row (the settings row), value and has (the choice under the mouse, if any), label (that
-- choice's text) and anchor (the dropdown list's item it's beside, or nil).
local current

local function Build()
	card = CreateFrame("Frame", nil, UIParent)
	card:SetFrameStrata("TOOLTIP")
	card:SetClampedToScreen(true)
	card:EnableMouse(false)
	card:Hide()
	UI.Panel(card, { size = "small" })
	card.caption = UI.Text(card, 10, "textFaint", "label")
	card.caption:SetPoint("TOPLEFT", PAD, -PAD)
	card.stage = CreateFrame("Frame", nil, card)
	card.stage:SetPoint("TOPLEFT", PAD, -(PAD + CAPTION_H))
	card.stage:SetSize(1, 1)
end

-- The drawing is only a picture: nothing in it takes the mouse (a card clamped over the row would steal its hover).
local function NoMouse(frame)
	frame:EnableMouse(false)
	frame:EnableMouseWheel(false)
	for _, child in ipairs({ frame:GetChildren() }) do
		NoMouse(child)
	end
end

local function Place()
	card:ClearAllPoints()
	if current.anchor then
		card:SetPoint("TOPLEFT", current.anchor, "TOPRIGHT", GAP, 0)
		return
	end
	local row = current.row
	if GameTooltip:IsShown() and GameTooltip:GetOwner() == row then
		-- Under the tooltip, or over it when there's no room below (in screen pixels).
		local bottom = GameTooltip:GetBottom()
		local room = (bottom or 0) * GameTooltip:GetEffectiveScale() - (card:GetHeight() + GAP) * card:GetEffectiveScale()
		if room >= 0 then
			card:SetPoint("TOPLEFT", GameTooltip, "BOTTOMLEFT", 0, -GAP)
		else
			card:SetPoint("BOTTOMLEFT", GameTooltip, "TOPLEFT", 0, GAP)
		end
	else
		card:SetPoint("TOPLEFT", row, "TOPRIGHT", GAP, 0)
	end
end

local function Host(fn)
	local host = hosts[fn]
	if not host then
		host = CreateFrame("Frame", nil, card.stage)
		host:SetPoint("TOPLEFT")
		host:SetSize(1, 1)
		hosts[fn] = host
	end
	for _, h in pairs(hosts) do
		h:SetShown(h == host)
	end
	return host
end

local function ParentOf(module, key)
	for _, spec in ipairs(module.options or {}) do
		if spec.key == key then
			return spec.parent
		end
	end
	return nil
end

-- Puts overrides into module's db; returns what to put back.
local function Swap(module, overrides)
	local saved = {}
	for key, o in pairs(overrides) do
		local tbl, field = ns.OptionRows_Resolve(module, key)
		saved[key] = { value = tbl[field] }
		tbl[field] = o.value
	end
	return saved
end

-- The caption: the hovered choice, or "when on" when it shows switches that are off turned on.
local function Caption(forced)
	if current.label then
		return "Preview: " .. current.label
	end
	return forced and "Preview: when on" or "Preview"
end

-- One try at drawing spec's preview into host; forceOn: with what it needs turned on. Returns ok, width, height.
local function Try(host, spec, module, forceOn)
	local need = needs[spec.preview]
	local overrides = ns.PanelLayout_PreviewOverrides(spec.key, spec.type, current.value, current.has, function(key)
		return ParentOf(module, key)
	end, forceOn, need and need.key)
	local get = ns.PanelLayout_PreviewGetter(function(key)
		return ns.OptionRows_Get(module, key)
	end, overrides)
	local saved = Swap(module, overrides)
	local ok, w, h = xpcall(spec.preview, ns.errorHandler, host, get, current.has)
	Swap(module, saved)
	return ok and w and h and w > 0 and h > 0, w, h
end

local function Draw()
	local row = current.row
	local spec, module = row.spec, row.module
	local need = needs[spec.preview]
	local host = Host(need and need.fn or spec.preview)
	host:SetScale(1)
	-- Shown (unseen) while it draws: a tooltip in host only lays out its lines while it can be seen.
	card:SetAlpha(0)
	card:Show()
	local ok, w, h = Try(host, spec, module, false)
	local forced = false
	if not ok then
		forced = true
		ok, w, h = Try(host, spec, module, true)
	end
	-- Before anything below can fail: an unseen card must never catch clicks meant for the settings under it.
	NoMouse(host)
	card.caption:SetText(Caption(forced))
	if not ok then
		card:Hide()
		return
	end
	host:SetSize(w, h)
	local scale = ns.PanelLayout_PreviewScale(w, h, MAX_W, MAX_H)
	host:SetScale(scale)
	local width = math.max(w * scale, math.ceil(card.caption:GetUnboundedStringWidth()))
	card:SetSize(math.ceil(width) + 2 * PAD, math.ceil(h * scale) + CAPTION_H + 2 * PAD)
	Place()
	card:SetAlpha(1)
end

-- Sample tooltips ---------------------------------------------------------------------------------------------------

local tooltips = {} -- [host] = its sample tooltip

-- A tooltip of host's own for drawing a sample tooltip (an item's, with the lines addons add), owned by host and
-- placed at its top left. Fill it (SetItemByID, AddLine), then return ns.Preview_TooltipSize(tip). It's never the
-- real GameTooltip, and it's an addon frame: nothing Blizzard runs on it reaches Blizzard's own tooltips.
function ns.Preview_Tooltip(host)
	local tip = tooltips[host]
	if not tip then
		-- Named (the template names its lines from it, and other addons' tooltip post-calls run on this tooltip too;
		-- some look its lines up by name).
		local n = 0
		for _ in pairs(tooltips) do
			n = n + 1
		end
		tip = CreateFrame("GameTooltip", "TomtePreviewTooltip" .. (n + 1), host, "GameTooltipTemplate")
		-- The template refreshes itself when item data loads; the preview redraws instead (Preview_Refresh), sized
		-- to the new lines.
		tip:UnregisterEvent("TOOLTIP_DATA_UPDATE")
		-- Never drives Blizzard's shared comparison tooltips (Shift, or the alwaysCompareItems setting).
		tip.supportsItemComparison = false
		tooltips[host] = tip
	end
	tip:SetOwner(host, "ANCHOR_NONE")
	tip:ClearAllPoints()
	tip:SetPoint("TOPLEFT", host, "TOPLEFT")
	return tip
end

-- The preview fn of something switch key turns on: nothing while that switch is off, so the card shows it turned on
-- ("when on"). Rows under the same switch (a size slider) share fn's picture.
function ns.Preview_When(key, fn)
	local wrapped = function(host, get, choosing)
		if not get(key) then
			return nil
		end
		return fn(host, get, choosing)
	end
	needs[wrapped] = { key = key, fn = fn }
	return wrapped
end

-- A preview function that shows a screenshot: for what can't be drawn still with the module's own code (full-screen
-- scenes, Blizzard's frames). file: a name in Media/Previews/ (a PNG; a new one needs a full client restart), w, h:
-- the size it shows at.
function ns.Preview_Image(file, w, h)
	return function(host)
		local tex = host.image
		if not tex then
			tex = host:CreateTexture(nil, "ARTWORK")
			tex:SetPoint("TOPLEFT")
			host.image = tex
		end
		tex:SetTexture("Interface\\AddOns\\" .. addonName .. "\\Media\\Previews\\" .. file)
		tex:SetSize(w, h)
		return w, h
	end
end

-- Shows tip and returns its size in host's units for a preview function; nil when it has no lines.
function ns.Preview_TooltipSize(tip)
	if tip:NumLines() == 0 then
		tip:Hide()
		return nil
	end
	tip:Show()
	local scale = tip:GetScale()
	return tip:GetWidth() * scale, tip:GetHeight() * scale
end

-- Shows row's preview. has: value is the choice under the mouse (label its text); anchor: beside that frame (an item
-- in the open dropdown list) instead of under the row's tooltip.
function ns.Preview_Show(row, value, has, label, anchor)
	if not (row.spec and row.spec.preview) then
		return
	end
	if not card then
		Build()
	end
	current = { row = row, value = value, has = has, label = label, anchor = anchor }
	Draw()
end

-- Hides the card if it's row's (any row's when row is nil).
function ns.Preview_Hide(row)
	if card and current and (row == nil or current.row == row) then
		current = nil
		card:Hide()
	end
end

-- module's settings changed, or data a preview waited for came in: redraw the card if the mouse is on one of its
-- rows (also when the last draw had nothing to show yet).
function ns.Preview_Refresh(module)
	if card and current and current.row.module == module then
		Draw()
	end
end
