local addonName, ns = ...

-- Loot: the loot window, in the List style (compact rows) or the Card style (where the loot came from on top, the
-- best item large with Gear Check's verdict, the rest as rows). The Feed style only opens it for loot that can't be
-- taken by itself. A click on a row loots it; Take all and the pages sit at the bottom. It opens at the mouse or
-- where Edit Mode put it, and grows down or up from there. After auto-loot it stays a moment, showing what you got,
-- then fades. Lines come from Data.lua; the loot session (events, fast loot) lives in Loot.lua. Also the text
-- helpers the feed (Feed.lua) shares.

local BASE_FONT = 12 -- the font size the widths below are drawn for; other sizes scale them
local LIST_W, CARD_W = 280, 320
local ICON_EDGE = 1 -- the quality-colored frame around a row's icon
local RULE_ALPHA = 0.5 -- the hairlines between rows and above the footer
local HOVER_GLOW = 0.22 -- a row's accent glow under the mouse, at its left edge
local CAP_PAD = 4 -- around the key in the Take all keycap
local PAD = 8
local ROW_EXTRA = 12 -- row height over the font size
local ROW_GAP = 2
local BEST_ICON = 36
local CLOSE_W = 18
local PAGE_W = 20
local FOOTER_H = 20
local GAP = 6
local TAKEN_ALPHA = 0.45 -- rows already looted
local FADE_TIME = 0.6 -- seconds the window takes to fade after auto-loot
local HOVER_WAIT = 1 -- seconds between checks while the mouse keeps a fading window
-- Where the window opens until Edit Mode moves it: its top-left corner (grow down) or bottom-left (grow up),
-- from the middle of the screen.
local DEFAULT_X, DEFAULT_TOP, DEFAULT_BOTTOM = 180, 160, -160
local MOUSE_OFFSET = 20 -- the window's corner from the cursor, so the cursor sits on the first row
local MONEY_ICON = 133784 -- inv_misc_coin_01
local JUNK_ICON = 133718 -- inv_misc_bone_01
local COIN_ICONS = {
	gold = "%s|TInterface\\MoneyFrame\\UI-GoldIcon:0:0:2:0|t",
	silver = "%s|TInterface\\MoneyFrame\\UI-SilverIcon:0:0:2:0|t",
	copper = "%s|TInterface\\MoneyFrame\\UI-CopperIcon:0:0:2:0|t",
}
-- What Edit Mode (and /tomte loot test) shows.
local PREVIEW = {
	{ slot = 1, kind = "money", name = "12 Gold 40 Silver", icon = MONEY_ICON, quantity = 0 },
	{ slot = 2, kind = "item", name = "Sample blade", quality = 4, icon = 135274, quantity = 1, classID = 2, -- sword_04
		newLook = true, value = 1250000, verdict = { text = "Upgrade +4.2%: equip it", role = "success",
		upgrade = true } },
	{ slot = 3, kind = "item", name = "Sample cloth", quality = 1, icon = 132889, quantity = 5, classID = 7, -- linen
		owned = 40, value = 2400 },
	{ slot = 4, kind = "item", name = "Broken tooth", quality = 0, icon = JUNK_ICON, quantity = 2, sell = 35 },
	{ slot = 5, kind = "item", name = "Torn pelt", quality = 0, icon = 134366, quantity = 1, sell = 120 }, -- pelt_wolf
}

local UI = ns.UI

local db, module
local frame, panel, lingerTimer
local rows = {}
-- entries: the slots shown; open: the loot window is open in the game (rows can loot); preview: Edit Mode's sample.
local state = { entries = {}, page = 1, pages = 1, title = "Loot", style = "list", open = false, preview = false }

-- Text helpers (also the feed's) ---------------------------------------------------------------------------------

-- The entry's name in its quality color, with the count after it.
function ns.Loot_NameText(e)
	local name = e.name or (e.link and e.link:match("%[(.-)%]")) or RETRIEVING_ITEM_INFO
	local color = e.kind ~= "money" and e.quality and ITEM_QUALITY_COLORS[e.quality]
	local text = color and UI.Wrap(name, color) or name
	local count = ns.Loot_QuantityText(e.quantity)
	if count ~= "" then
		text = text .. " " .. UI.Wrap(count, "textMuted")
	end
	return text
end

-- Data.lua's { text, role } parts as one colored string.
function ns.Loot_PartsText(parts)
	local out = {}
	for i, p in ipairs(parts) do
		out[i] = UI.Wrap(p.text, p.role)
	end
	return table.concat(out, "  ")
end

function ns.Loot_MoneyText(copper)
	return ns.Coins(copper, true, COIN_ICONS)
end

-- Data.lua's detail options from the extras. verdictMode: "tag" (rows, feed) or "full" (the Card's best item).
function ns.Loot_DetailOpts(verdictMode)
	local x = db.extras
	return { newLook = x.newLook, owned = x.owned, value = x.value, verdict = x.verdict and verdictMode or nil }
end

ns.LOOT_MONEY_ICON = MONEY_ICON

-- Rows ----------------------------------------------------------------------------------------------------------------

local function LineEntries(line)
	return ns.Loot_LineEntries(line)
end

local function RowClick(self)
	local line = self.line
	if not line or state.preview then
		return
	end
	local entries = LineEntries(line)
	if IsModifiedClick() then
		local link = entries[1].link
		if link then
			HandleModifiedItemClick(link)
		end
		return
	end
	if not state.open then
		return
	end
	for _, e in ipairs(entries) do
		if not e.taken and not e.locked then
			LootSlot(e.slot)
		end
	end
end

local function RowEnter(self)
	local line = self.line
	if not line then
		return
	end
	GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
	if line.junk then
		GameTooltip:AddLine(ns.Loot_JunkName(line.quantity), UI.RGB("heading"))
		for _, e in ipairs(line.junk) do
			UI.TipLine(ns.Loot_NameText(e))
		end
		GameTooltip:Show()
		return
	end
	local e = line.entry
	if state.open and not state.preview and not e.taken and e.kind == "item" then
		GameTooltip:SetLootItem(e.slot)
	elseif state.open and not state.preview and not e.taken and e.kind == "currency" then
		GameTooltip:SetLootCurrency(e.slot)
	elseif e.link then
		GameTooltip:SetHyperlink(e.link)
	else
		GameTooltip:Hide()
		return
	end
	GameTooltip:Show()
end

local function RowLeave()
	GameTooltip:Hide()
end

-- A row: the icon framed in the item's quality color and a hairline under it; under the mouse an accent glow from the
-- left edge, with a thin accent bar, says it can be clicked.
local function NewRowButton()
	local row = CreateFrame("Button", nil, frame)
	row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	row.iconFrame = row:CreateTexture(nil, "ARTWORK", nil, -1)
	row.icon = row:CreateTexture(nil, "ARTWORK")
	row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	row.iconFrame:SetPoint("TOPLEFT", row.icon, -ICON_EDGE, ICON_EDGE)
	row.iconFrame:SetPoint("BOTTOMRIGHT", row.icon, ICON_EDGE, -ICON_EDGE)
	row.rule = UI.Hairline(row, LIST_W, RULE_ALPHA, "rule")
	row.rule:SetPoint("BOTTOMLEFT", 0, -ROW_GAP / 2)
	row.rule:SetPoint("BOTTOMRIGHT", 0, -ROW_GAP / 2)
	row.hl = row:CreateTexture(nil, "HIGHLIGHT")
	row.hl:SetAllPoints()
	row.hl:SetColorTexture(1, 1, 1, 1) -- colored by the gradient
	row.hl:SetGradient("HORIZONTAL", UI.ColorObject("accent", HOVER_GLOW), UI.ColorObject("accent", 0))
	row.hlBar = row:CreateTexture(nil, "HIGHLIGHT")
	row.hlBar:SetPoint("TOPLEFT")
	row.hlBar:SetPoint("BOTTOMLEFT")
	row.hlBar:SetWidth(2)
	row.hlBar:SetColorTexture(UI.Color("accent"))
	row:SetScript("OnClick", RowClick)
	row:SetScript("OnEnter", RowEnter)
	row:SetScript("OnLeave", RowLeave)
	return row
end

local function Row(i)
	local row = rows[i]
	if row then
		return row
	end
	row = NewRowButton()
	row.name = UI.Text(row, BASE_FONT, "text")
	row.name:SetWordWrap(false)
	row.detail = UI.Text(row, BASE_FONT - 1, "textMuted")
	row.detail:SetJustifyH("RIGHT")
	row.detail:SetWordWrap(false)
	rows[i] = row
	return row
end

-- The icon's frame: the quality color, or the theme's frame color for coin and anything without a quality.
local function SetIconFrame(row, quality, isMoney)
	local q = not isMoney and quality and ITEM_QUALITY_COLORS[quality]
	if q then
		row.iconFrame:SetColorTexture(q.r, q.g, q.b, 1)
	else
		row.iconFrame:SetColorTexture(UI.Color("frame"))
	end
end

local function SetRow(row, line, rowH, size)
	row.line = line
	row:SetHeight(rowH)
	row.icon:SetSize(rowH - 6, rowH - 6)
	row.icon:ClearAllPoints()
	row.icon:SetPoint("LEFT", 4, 0)
	UI.SetFont(row.name, "body", size)
	UI.SetFont(row.detail, "body", size - 1)
	local taken, locked
	if line.junk then
		row.icon:SetTexture(line.icon or JUNK_ICON)
		row.name:SetText(UI.Wrap(ns.Loot_JunkName(line.quantity), ITEM_QUALITY_COLORS[0] or "textMuted"))
		row.detail:SetText(ns.Loot_PartsText(ns.Loot_JunkDetails(line, ns.Loot_DetailOpts())))
		taken = line.taken
		SetIconFrame(row, 0)
	else
		local e = line.entry
		SetIconFrame(row, e.quality, e.kind == "money")
		row.icon:SetTexture(e.icon or (e.kind == "money" and MONEY_ICON) or JUNK_ICON)
		row.name:SetText(ns.Loot_NameText(e))
		row.detail:SetText(ns.Loot_PartsText(ns.Loot_Details(e, ns.Loot_DetailOpts("tag"))))
		taken, locked = e.taken, e.locked
	end
	row.detail:ClearAllPoints()
	row.detail:SetPoint("RIGHT", row, "RIGHT", -2, 0)
	row.name:ClearAllPoints()
	row.name:SetPoint("LEFT", row.icon, "RIGHT", 7, 0)
	row.name:SetPoint("RIGHT", row.detail, "LEFT", -6, 0)
	row.icon:SetDesaturated(taken == true or locked == true)
	row:SetAlpha(taken and TAKEN_ALPHA or 1)
	row:Show()
end

-- The Card's best item: a large icon, the name, Gear Check's verdict and the other extras under it.
local function BuildBest()
	local best = NewRowButton()
	best.name = UI.Text(best, BASE_FONT + 2, "heading")
	best.name:SetWordWrap(false)
	best.verdict = UI.Text(best, BASE_FONT, "text")
	best.verdict:SetWordWrap(false)
	best.detail = UI.Text(best, BASE_FONT - 1, "textMuted")
	best.detail:SetWordWrap(false)
	frame.best = best
end

local function SetBest(e, size)
	local best = frame.best
	local iconSize = math.floor(BEST_ICON * size / BASE_FONT)
	best.line = { entry = e }
	best.icon:SetSize(iconSize, iconSize)
	best.icon:ClearAllPoints()
	best.icon:SetPoint("TOPLEFT", 4, -4)
	best.icon:SetTexture(e.icon or JUNK_ICON)
	SetIconFrame(best, e.quality, e.kind == "money")
	best.icon:SetDesaturated(e.taken == true or e.locked == true)
	UI.SetFont(best.name, "body", size + 2)
	UI.SetFont(best.verdict, "body", size)
	UI.SetFont(best.detail, "body", size - 1)
	best.name:ClearAllPoints()
	best.name:SetPoint("TOPLEFT", best.icon, "TOPRIGHT", 8, 0)
	best.name:SetPoint("RIGHT", best, "RIGHT", -2, 0)
	best.name:SetText(ns.Loot_NameText(e))
	local verdict = db.extras.verdict and e.verdict
	best.verdict:SetText(verdict and UI.Wrap(verdict.text, verdict.role) or "")
	best.verdict:ClearAllPoints()
	best.verdict:SetPoint("TOPLEFT", best.name, "BOTTOMLEFT", 0, -3)
	best.verdict:SetPoint("RIGHT", best, "RIGHT", -2, 0)
	local opts = ns.Loot_DetailOpts()
	best.detail:SetText(ns.Loot_PartsText(ns.Loot_Details(e, opts)))
	best.detail:ClearAllPoints()
	best.detail:SetPoint("TOPLEFT", verdict and best.verdict or best.name, "BOTTOMLEFT", 0, -3)
	best.detail:SetPoint("RIGHT", best, "RIGHT", -2, 0)
	local textH = best.name:GetStringHeight() + 3 + best.detail:GetStringHeight()
		+ (verdict and (3 + best.verdict:GetStringHeight()) or 0)
	best:SetHeight(math.max(iconSize, textH) + 8)
	best:SetAlpha(e.taken and TAKEN_ALPHA or 1)
	best:Show()
	return best:GetHeight()
end

-- Window ----------------------------------------------------------------------------------------------------------

-- A button that is only its text, for the borderless look Almost Done has: idle role (default muted), the heading color
-- under the mouse.
local function FlatButton(parent, text, size, idle)
	local b = CreateFrame("Button", nil, parent)
	idle = idle or "textMuted"
	b.label = UI.Text(b, size or BASE_FONT - 1, idle, "label")
	b.label:SetPoint("CENTER")
	b.label:SetText(text)
	b:SetSize(math.ceil(b.label:GetUnboundedStringWidth()) + 8, FOOTER_H)
	b:SetScript("OnEnter", function(self)
		UI.SetTextRole(self.label, "heading")
	end)
	b:SetScript("OnLeave", function(self)
		UI.SetTextRole(self.label, self:IsEnabled() and idle or "textFaint")
	end)
	b:SetScript("OnEnable", function(self)
		UI.SetTextRole(self.label, idle)
	end)
	b:SetScript("OnDisable", function(self)
		UI.SetTextRole(self.label, "textFaint")
	end)
	return b
end

local escapeQuiet = false -- the Escape stand-in is being hidden by code, not by Escape

local function SetEscape(on)
	local escape = frame and frame.escape
	if not escape then
		return
	end
	if on then
		escape:Show()
	elseif escape:IsShown() then
		escapeQuiet = true
		escape:Hide()
		escapeQuiet = false
	end
end

-- The keyboard is on only while a loot is open in the window, a key is chosen, Loot is on and you're out of combat.
-- combat: called from PLAYER_REGEN_DISABLED, which comes just before the lockdown starts.
function ns.LootWindow_UpdateKeys(combat)
	if not frame then
		return
	end
	combat = combat or InCombatLockdown()
	local want = not combat and state.open and not state.preview and frame:IsShown() and db.lootKey ~= "off"
		and module ~= nil and module.active
	if want then
		frame:SetPropagateKeyboardInput(true)
		frame:EnableKeyboard(true)
	else
		frame:EnableKeyboard(false)
		if not combat then
			frame:SetPropagateKeyboardInput(true)
		end
	end
end

local function Turn(delta)
	if state.pages > 1 then
		state.page = state.page + delta
		ns.LootWindow_Draw()
	end
end

local function Build()
	frame = CreateFrame("Frame", nil, UIParent)
	frame:SetSize(LIST_W, 100)
	frame:SetFrameStrata("HIGH")
	frame:SetClampedToScreen(true)
	frame:SetMovable(true)
	frame:EnableMouse(true)
	frame:EnableMouseWheel(true)
	frame:Hide()
	panel = UI.Panel(frame, { alpha = db.bgAlpha, subtle = true })

	frame.label = UI.Text(frame, BASE_FONT - 2, "textMuted", "label")
	frame.title = UI.Text(frame, BASE_FONT, "heading", "title")
	frame.title:SetWordWrap(false)
	frame.close = FlatButton(frame, "x", BASE_FONT)
	frame.close:SetSize(CLOSE_W, CLOSE_W)
	frame.close:SetPoint("TOPRIGHT", -PAD + 4, -PAD + 4)
	frame.close:SetScript("OnClick", function()
		ns.LootWindow_Hide()
	end)
	frame.empty = UI.Text(frame, BASE_FONT, "textMuted")

	frame.take = FlatButton(frame, "Take all", BASE_FONT, "accent")
	frame.take.label:ClearAllPoints()
	frame.take.label:SetPoint("LEFT", 0, 0)
	-- The key that takes all while looting, as a small keycap after the text.
	frame.take.cap = CreateFrame("Frame", nil, frame.take)
	UI.Surface(frame.take.cap, 0.6)
	frame.take.capText = UI.Text(frame.take.cap, BASE_FONT - 2, "textMuted", "number")
	frame.take.capText:SetPoint("CENTER", 0, 0)
	frame.footRule = UI.Hairline(frame, LIST_W, RULE_ALPHA, "rule")
	frame.take:SetScript("OnClick", function()
		ns.Loot_TakeAll()
	end)
	frame.take:HookScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:AddLine("Take all", UI.RGB("heading"))
		if db.lootKey ~= "off" then
			UI.TipLine("Key while looting: " .. GetBindingText(db.lootKey), "textMuted")
		end
		local key = GetBindingKey("TOMTE_LOOT_TAKE_ALL")
		if key then
			UI.TipLine("Key binding: " .. GetBindingText(key), "textMuted")
		end
		GameTooltip:Show()
	end)
	frame.take:HookScript("OnLeave", GameTooltip_Hide)
	frame.prev = FlatButton(frame, "<", BASE_FONT)
	frame.prev:SetWidth(PAGE_W)
	frame.prev:SetScript("OnClick", function()
		Turn(-1)
	end)
	frame.next = FlatButton(frame, ">", BASE_FONT)
	frame.next:SetWidth(PAGE_W)
	frame.next:SetScript("OnClick", function()
		Turn(1)
	end)
	frame.pageText = UI.Text(frame, BASE_FONT - 1, "textMuted", "number")

	frame:SetScript("OnMouseWheel", function(_, delta)
		Turn(-delta)
	end)

	local fade = frame:CreateAnimationGroup()
	local alpha = fade:CreateAnimation("Alpha")
	alpha:SetFromAlpha(1)
	alpha:SetToAlpha(0)
	alpha:SetDuration(FADE_TIME)
	fade:SetToFinalAlpha(true)
	fade:SetScript("OnFinished", function()
		frame:Hide()
		frame:SetAlpha(1)
	end)
	frame.fade = fade

	-- Closing the window (x, Escape) ends the loot, as the game's window does; not when only UIParent hid (Alt+Z).
	frame:SetScript("OnHide", function(self)
		if self:IsShown() then
			return
		end
		GameTooltip_Hide()
		local wasOpen = state.open and not state.preview
		state.open, state.preview = false, false
		SetEscape(false)
		ns.LootWindow_UpdateKeys()
		if wasOpen then
			CloseLoot()
		end
	end)

	-- Escape: a stand-in frame on Tomte's Escape list, shown only while the window can loot (or shows the sample),
	-- so a window that only lingers after auto-loot never takes an Escape press.
	frame.escape = CreateFrame("Frame", nil, UIParent)
	frame.escape:Hide()
	frame.escape:SetScript("OnHide", function(self)
		if self:IsShown() or escapeQuiet then
			return
		end
		ns.LootWindow_Hide() -- Escape hid it
	end)
	UI.CloseOnEscape(frame.escape)

	-- The take-all key while looting: only that key is kept from the game, every other key goes on as usual.
	-- SetPropagateKeyboardInput can't be called from addon code in combat (10.1.5), so in combat the keyboard is off
	-- and every key passes (UpdateKeys).
	frame:SetScript("OnKeyDown", function(self, key)
		if InCombatLockdown() then
			return
		end
		local take = state.open and not state.preview and key == db.lootKey
		self:SetPropagateKeyboardInput(not take)
		if take then
			ns.Loot_TakeAll()
		end
	end)
	BuildBest()
end

-- Whether a click or the mouse wheel reaches the window: not while it only lingers after the loot closed (it lets
-- clicks through to the world; IsMouseOver still keeps it from fading).
local function SetInteractive(on)
	frame:EnableMouse(on)
	frame:EnableMouseWheel(on)
	for _, b in ipairs({ frame.best, frame.close, frame.take, frame.prev, frame.next }) do
		b:EnableMouse(on)
	end
	for _, row in ipairs(rows) do
		row:EnableMouse(on)
	end
end

local function ApplyLook()
	panel:SetAlpha(db.bgAlpha)
	if frame.Center then -- the Blizzard theme's tooltip fill keeps its own alpha: fade the fill only
		frame.Center:SetAlpha(db.bgAlpha)
	end
end

local function Place()
	frame:ClearAllPoints()
	local corner = db.growUp and "BOTTOMLEFT" or "TOPLEFT"
	if db.atMouse and not ns.EditMode_Active() and not state.preview then
		local x, y = GetCursorPosition()
		local scale = frame:GetEffectiveScale()
		x, y = x / scale - MOUSE_OFFSET, y / scale
		frame:SetPoint(corner, UIParent, "BOTTOMLEFT", x, db.growUp and (y - MOUSE_OFFSET) or (y + MOUSE_OFFSET))
		return
	end
	local p = db.window
	if p.set then
		frame:SetPoint(corner, UIParent, "BOTTOMLEFT", p.x, db.growUp and p.bottom or p.top)
	else
		frame:SetPoint(corner, UIParent, "CENTER", DEFAULT_X, db.growUp and DEFAULT_BOTTOM or DEFAULT_TOP)
	end
end

local function SavePosition()
	local left, top, bottom = frame:GetLeft(), frame:GetTop(), frame:GetBottom()
	if not (left and top and bottom) then
		return
	end
	local p = db.window
	p.x, p.top, p.bottom, p.set = left, top, bottom, true
	Place()
end

local function DrawHeader(size)
	local card = state.style == "card"
	local y = PAD
	frame.label:ClearAllPoints()
	frame.title:ClearAllPoints()
	local showSource = db.extras.source
	if card then
		UI.SetFont(frame.label, "label", size - 2)
		frame.label:SetText(ns.Spaced("Loot"))
		frame.label:SetPoint("TOPLEFT", PAD, -y)
		frame.label:Show()
		y = y + frame.label:GetStringHeight() + 3
	else
		frame.label:Hide()
	end
	if showSource or not card then
		-- The Card's title is larger, under its label.
		UI.SetFont(frame.title, "title", card and size + 2 or size)
		frame.title:SetText(showSource and state.title or "Loot")
		frame.title:SetPoint("TOPLEFT", PAD, -y)
		frame.title:SetPoint("RIGHT", frame.close, "LEFT", -4, 0)
		frame.title:Show()
		y = y + math.max(frame.title:GetStringHeight(), card and 0 or CLOSE_W - 4)
	else
		frame.title:Hide()
		y = math.max(y, PAD + CLOSE_W - 4)
	end
	return y + GAP
end

-- Take all's keycap: the key that takes all while looting, else the key binding; no cap without either.
local function SetTakeKey()
	local take = frame.take
	local key = db.lootKey ~= "off" and db.lootKey or GetBindingKey("TOMTE_LOOT_TAKE_ALL")
	local labelW = math.ceil(take.label:GetUnboundedStringWidth())
	if not key then
		take.cap:Hide()
		take:SetWidth(labelW + 4)
		return
	end
	take.capText:SetText(GetBindingText(key))
	local capW = math.max(math.ceil(take.capText:GetUnboundedStringWidth()) + 2 * CAP_PAD, FOOTER_H - 6)
	take.cap:SetSize(capW, FOOTER_H - 6)
	take.cap:ClearAllPoints()
	take.cap:SetPoint("LEFT", take.label, "RIGHT", 6, 0)
	take.cap:Show()
	take:SetWidth(labelW + 6 + capW)
end

local function DrawFooter(y)
	local takeable = state.open and not state.preview and #ns.Loot_Takeable(state.entries) > 0
	local paged = state.pages > 1
	frame.take:SetShown(takeable or state.preview)
	frame.prev:SetShown(paged)
	frame.next:SetShown(paged)
	frame.pageText:SetShown(paged)
	frame.footRule:SetShown(takeable or paged or state.preview)
	if not (takeable or paged or state.preview) then
		return y
	end
	frame.footRule:ClearAllPoints()
	frame.footRule:SetPoint("TOPLEFT", PAD, -y)
	frame.footRule:SetPoint("TOPRIGHT", -PAD, -y)
	y = y + GAP
	SetTakeKey()
	frame.take:ClearAllPoints()
	frame.take:SetPoint("TOPLEFT", PAD, -y)
	frame.next:ClearAllPoints()
	frame.next:SetPoint("TOPRIGHT", -PAD, -y)
	frame.pageText:ClearAllPoints()
	frame.pageText:SetPoint("RIGHT", frame.next, "LEFT", -4, 0)
	frame.pageText:SetText(state.page .. "/" .. state.pages)
	frame.prev:ClearAllPoints()
	frame.prev:SetPoint("RIGHT", frame.pageText, "LEFT", -4, 0)
	frame.prev:SetEnabled(state.page > 1)
	frame.next:SetEnabled(state.page < state.pages)
	return y + FOOTER_H + GAP
end

function ns.LootWindow_Draw()
	if not frame then
		return
	end
	local size = db.fontSize
	local card = state.style == "card"
	local rowH = size + ROW_EXTRA
	frame:SetWidth(math.floor((card and CARD_W or LIST_W) * size / BASE_FONT))
	ApplyLook()
	local y = DrawHeader(size)

	local bestIndex = card and ns.Loot_BestIndex(state.entries)
	local best = bestIndex and state.entries[bestIndex]
	if best then
		frame.best:ClearAllPoints()
		frame.best:SetPoint("TOPLEFT", PAD, -y)
		frame.best:SetPoint("RIGHT", -PAD, 0)
		y = y + SetBest(best, size) + GAP
	else
		frame.best:Hide()
	end

	local lines = ns.Loot_Lines(state.entries, { foldJunk = db.extras.foldJunk, skip = best })
	local shown, page, pages = ns.Loot_Page(lines, db.perPage, state.page)
	state.page, state.pages = page, pages
	for i, line in ipairs(shown) do
		local row = Row(i)
		row:ClearAllPoints()
		row:SetPoint("TOPLEFT", PAD, -y)
		row:SetPoint("RIGHT", -PAD, 0)
		SetRow(row, line, rowH, size)
		row.rule:SetShown(i < #shown) -- the footer has its own rule
		y = y + rowH + ROW_GAP
	end
	for i = #shown + 1, #rows do
		rows[i]:Hide()
		rows[i].line = nil
	end
	if #shown == 0 and not best then
		UI.SetFont(frame.empty, "body", size)
		frame.empty:ClearAllPoints()
		frame.empty:SetPoint("TOPLEFT", PAD, -y)
		frame.empty:SetText("Nothing left")
		frame.empty:Show()
		y = y + frame.empty:GetStringHeight() + GAP
	else
		frame.empty:Hide()
		y = y + GAP - ROW_GAP
	end
	y = DrawFooter(y)
	frame:SetHeight(y + PAD - GAP)
	local live = state.open or state.preview
	SetInteractive(live)
	SetEscape(live)
end

local function CancelLinger()
	if lingerTimer then
		lingerTimer:Cancel()
		lingerTimer = nil
	end
	if frame then
		frame.fade:Stop()
		frame:SetAlpha(1)
	end
end

local function FadeOut()
	lingerTimer = nil
	if not frame:IsShown() then
		return
	end
	if frame:IsMouseOver() then
		lingerTimer = C_Timer.NewTimer(HOVER_WAIT, FadeOut)
		return
	end
	frame.fade:Play()
end

-- API for Loot.lua ------------------------------------------------------------------------------------------------

-- s = { entries, title, style = "list" | "card", place (true: a new loot window, place it again) }.
function ns.LootWindow_Show(s)
	if not frame then
		Build()
	end
	CancelLinger()
	local fresh = not frame:IsShown() or s.place
	state.entries, state.title, state.style = s.entries, s.title or "Loot", s.style
	state.open, state.preview = true, false
	if fresh then
		state.page = 1
		Place()
	end
	ns.LootWindow_Draw()
	frame:Show()
	ns.LootWindow_UpdateKeys()
end

function ns.LootWindow_Shown()
	return frame ~= nil and frame:IsShown() and not state.preview
end

-- The loot closed: rows can't loot any more. With linger (after auto-loot) the window shows what you got for the fade
-- delay, then fades (a mouse over it keeps it); otherwise it closes now.
function ns.LootWindow_Closed(linger)
	if not (frame and frame:IsShown()) or state.preview then
		return
	end
	state.open = false
	if not linger then
		frame:Hide()
		return
	end
	ns.LootWindow_UpdateKeys()
	ns.LootWindow_Draw()
	CancelLinger()
	lingerTimer = C_Timer.NewTimer(db.fadeDelay, FadeOut)
end

function ns.LootWindow_Hide()
	CancelLinger()
	if frame then
		frame:Hide()
	end
end

-- Settings changed: redraw (and place again unless it opens at the mouse).
function ns.LootWindow_Relayout()
	if frame and frame:IsShown() then
		if not db.atMouse or state.preview then
			Place()
		end
		ns.LootWindow_Draw()
	end
end

function ns.LootWindow_ResetPosition()
	db.window.set = false
	ns.LootWindow_Relayout()
end

-- The sample window: in Edit Mode, and from /tomte loot test (until closed).
local function ShowPreview()
	if not frame then
		Build()
	end
	CancelLinger()
	state.entries, state.title, state.style = PREVIEW, "Sample corpse", db.style == "card" and "card" or "list"
	state.open, state.preview, state.page = false, true, 1
	Place()
	ns.LootWindow_Draw()
	frame:Show()
end
ns.LootWindow_Preview = ShowPreview

local function RefreshPreview()
	if not db then
		return
	end
	local want = ns.EditMode_Active() and module and module.active
	if want and not ns.LootWindow_Shown() then
		ShowPreview()
	elseif not want and frame and state.preview then
		frame:Hide()
	end
end

ns.EditMode_Register({
	name = "Loot window",
	frame = function()
		return module and module.active and frame or nil
	end,
	refresh = RefreshPreview,
	saved = SavePosition,
})

function ns.LootWindow_Init(moduleDB, lootModule)
	db, module = moduleDB, lootModule
end
