local addonName, ns = ...

-- Loot: the pieces the feed (Feed.lua) and the loot window's looks (Look*.lua) draw with, so they look like one
-- thing: the text of an entry and its extras, the feed's strip (a thin bar in the item's quality color, the icon, the
-- name and the extras on a dark strip that fades out to the right), the quality frame around an icon, flat text
-- buttons and the Take all keycap. Lines come from Data.lua.

local BASE_FONT = 12 -- the font size the sizes below are drawn for; other sizes scale them
local BAR_W = 2 -- the strip's quality bar on the left edge
local ICON_GAP, DETAIL_GAP = 6, 8 -- after the bar and the icon; between the name and the extras
local TAIL = 48 -- the strip runs on past the text this far while it fades out
local STRIP_ALPHA = 0.85 -- the strip's darkest point, times the Background opacity
local CAP_PAD = 4 -- around the key in a keycap
local BUTTON_H = 20
local BINDING = "TOMTE_LOOT_TAKE_ALL"
local MONEY_ICON = 133784 -- inv_misc_coin_01
local JUNK_ICON = 133718 -- inv_misc_bone_01
local COIN_ICONS = {
	gold = "%s|TInterface\\MoneyFrame\\UI-GoldIcon:0:0:2:0|t",
	silver = "%s|TInterface\\MoneyFrame\\UI-SilverIcon:0:0:2:0|t",
	copper = "%s|TInterface\\MoneyFrame\\UI-CopperIcon:0:0:2:0|t",
}

local UI = ns.UI

local db

ns.LOOT_MONEY_ICON = MONEY_ICON
ns.LOOT_JUNK_ICON = JUNK_ICON

-- Text ----------------------------------------------------------------------------------------------------------

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

-- Data.lua's detail options from the extras. verdictMode: "tag" (rows, feed) or "full" (the Panel's featured item).
-- value = false leaves the price out (the Panel shows it on its own).
function ns.Loot_DetailOpts(verdictMode, value)
	local x = db.extras
	return { newLook = x.newLook, owned = x.owned, value = x.value and value ~= false,
		verdict = x.verdict and verdictMode or nil }
end

-- The entry's icon, or the coin or the junk bone.
function ns.LootParts_Icon(e)
	return e.icon or (e.kind == "money" and MONEY_ICON) or JUNK_ICON
end

-- What a line (Data.lua's Loot_Lines) shows: { icon, name, detail (colored strings), quality, role (a strip's bar
-- without a quality: coin is gold, as in the feed), money, entry }.
-- verdictMode as for Loot_DetailOpts; value = false leaves the price out of the detail.
function ns.LootParts_LineText(line, verdictMode, value)
	if line.junk then
		return {
			icon = line.icon or JUNK_ICON,
			name = UI.Wrap(ns.Loot_JunkName(line.quantity), ITEM_QUALITY_COLORS[0] or "textMuted"),
			detail = value ~= false and ns.Loot_PartsText(ns.Loot_JunkDetails(line, ns.Loot_DetailOpts())) or "",
			quality = 0,
		}
	end
	local e = line.entry
	return {
		icon = ns.LootParts_Icon(e),
		name = ns.Loot_NameText(e),
		detail = ns.Loot_PartsText(ns.Loot_Details(e, ns.Loot_DetailOpts(verdictMode or "tag", value))),
		quality = e.kind ~= "money" and e.quality or nil,
		role = e.kind == "money" and "warning" or nil,
		money = e.kind == "money",
		entry = e,
	}
end

-- Lines in the window -------------------------------------------------------------------------------------------
-- A look's clickable piece (a strip, a row, a tile) keeps its line in self.line and the look's context in
-- self.ctx = { live (the loot is open and can be taken), actions = { Loot(entries), TakeAll(), Close(), Turn(delta) } }.

-- A click loots what the line stands for; a modified click (Shift, Ctrl) links or previews the item.
function ns.LootParts_Click(self)
	local line, ctx = self.line, self.ctx
	if not (line and ctx) then
		return
	end
	local entries = ns.Loot_LineEntries(line)
	if IsModifiedClick() then
		local link = entries[1].link
		if link then
			HandleModifiedItemClick(link)
		end
		return
	end
	if ctx.live then
		ctx.actions.Loot(entries)
	end
end

-- The game's tooltip for the line's slot while the loot is open, else from its link; folded junk lists its items.
function ns.LootParts_Tooltip(self)
	local line, ctx = self.line, self.ctx
	if not line then
		return
	end
		-- A piece wider than what it shows (a strip fading out) opens the tooltip beside its text: self.tipAnchor.
	if self.tipAnchor then
		GameTooltip:SetOwner(self, "ANCHOR_NONE")
		GameTooltip:SetPoint("LEFT", self.tipAnchor, "RIGHT", 16, 0)
	else
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
	end
	if line.junk then
		GameTooltip:AddLine(ns.Loot_JunkName(line.quantity), UI.RGB("heading"))
		for _, e in ipairs(line.junk) do
			UI.TipLine(ns.Loot_NameText(e))
		end
		GameTooltip:Show()
		return
	end
	local e = line.entry
	local live = ctx and ctx.live
	if live and not e.taken and e.kind == "item" then
		GameTooltip:SetLootItem(e.slot)
	elseif live and not e.taken and e.kind == "currency" then
		GameTooltip:SetLootCurrency(e.slot)
	elseif e.link then
		GameTooltip:SetHyperlink(e.link)
	else
		GameTooltip:Hide()
		return
	end
	GameTooltip:Show()
end

-- Prev, "page/pages", next. pager:Set(ctx, size) shows it when there's more than one page and returns its width
-- (0 when hidden).
function ns.LootParts_Pager(parent)
	local pager = CreateFrame("Frame", nil, parent)
	pager.prev = ns.LootParts_FlatButton(pager, "<", BASE_FONT)
	pager.next = ns.LootParts_FlatButton(pager, ">", BASE_FONT)
	pager.text = UI.Text(pager, BASE_FONT - 1, "textMuted", "number")
	pager.prev:SetPoint("LEFT")
	pager.text:SetPoint("LEFT", pager.prev, "RIGHT", 2, 0)
	pager.next:SetPoint("LEFT", pager.text, "RIGHT", 2, 0)
	pager.prev:SetScript("OnClick", function(self)
		pager.ctx.actions.Turn(-1)
	end)
	pager.next:SetScript("OnClick", function(self)
		pager.ctx.actions.Turn(1)
	end)
	function pager:Set(ctx, size)
		self.ctx = ctx
		if (ctx.pages or 1) <= 1 then
			self:Hide()
			return 0
		end
		UI.SetFont(self.text, "number", size - 1)
		self.text:SetText(ctx.page .. "/" .. ctx.pages)
		self.prev:SetEnabled(ctx.page > 1)
		self.next:SetEnabled(ctx.page < ctx.pages)
		local w = self.prev:GetWidth() + self.next:GetWidth() + math.ceil(self.text:GetUnboundedStringWidth()) + 4
		self:SetSize(w, BUTTON_H)
		self:Show()
		return w
	end
	return pager
end

-- Strip ---------------------------------------------------------------------------------------------------------

-- Adds the strip's pieces to frame f: f.bg, f.bar, f.icon, f.text, f.detail.
function ns.LootParts_Strip(f)
	f.bg = f:CreateTexture(nil, "BACKGROUND")
	f.bg:SetAllPoints()
	f.bg:SetColorTexture(1, 1, 1, 1) -- colored by the gradient (FillStrip)
	f.bar = f:CreateTexture(nil, "ARTWORK")
	f.bar:SetPoint("TOPLEFT")
	f.bar:SetPoint("BOTTOMLEFT")
	f.bar:SetWidth(BAR_W)
	f.icon = f:CreateTexture(nil, "ARTWORK")
	f.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	f.icon:SetPoint("LEFT", BAR_W + ICON_GAP - 2, 0)
	f.text = UI.Text(f, BASE_FONT, "text")
	f.text:SetWordWrap(false)
	f.detail = UI.Text(f, BASE_FONT - 1, "textMuted")
	f.detail:SetWordWrap(false)
	f.detail:SetPoint("LEFT", f.text, "RIGHT", DETAIL_GAP, 0)
end

-- The bar's color: the item's quality, else the spec's role (reputation, honor), else the accent.
local function SetBarColor(f, spec)
	local q = spec.quality and ITEM_QUALITY_COLORS[spec.quality]
	if q then
		f.bar:SetColorTexture(q.r, q.g, q.b, 1)
	else
		f.bar:SetColorTexture(UI.Color(spec.role or "accent"))
	end
end

-- Fills a strip. spec = { icon, text, detail (both colored strings), quality (the bar's color) or role }.
-- iconSize: default size + 6. Returns the width the strip needs: the text's, up to maxW, plus the fading tail.
function ns.LootParts_FillStrip(f, spec, size, bgAlpha, maxW, iconSize)
	iconSize = iconSize or size + 6
	f.bg:SetGradient("HORIZONTAL", UI.ColorObject("bg", bgAlpha * STRIP_ALPHA), UI.ColorObject("bg", 0))
	SetBarColor(f, spec)
	f.icon:SetSize(iconSize, iconSize)
	f.icon:SetTexture(spec.icon)
	f.icon:SetShown(spec.icon ~= nil)
	f.text:ClearAllPoints()
	if spec.icon then
		f.text:SetPoint("LEFT", f.icon, "RIGHT", ICON_GAP, 0)
	else
		f.text:SetPoint("LEFT", BAR_W + ICON_GAP, 0)
	end
	UI.SetFont(f.text, "body", size)
	UI.SetFont(f.detail, "body", size - 1)
	f.text:SetText(spec.text or "")
	f.detail:SetText(spec.detail or "")
	local left = BAR_W + ICON_GAP + (spec.icon and iconSize + ICON_GAP or 0)
	local detailW = (spec.detail and spec.detail ~= "") and DETAIL_GAP + math.ceil(f.detail:GetUnboundedStringWidth())
		or 0
	-- A long name gives way first, so the extras stay readable within maxW.
	local nameW = math.min(math.ceil(f.text:GetUnboundedStringWidth()), maxW - TAIL - left - detailW)
	f.text:SetWidth(math.max(nameW, 1))
	return left + nameW + detailW + TAIL
end

-- Icons and buttons ---------------------------------------------------------------------------------------------

-- The frame texture behind an icon: the quality color, or the theme's frame color for coin and anything without one.
function ns.LootParts_IconFrame(tex, quality, isMoney)
	local q = not isMoney and quality and ITEM_QUALITY_COLORS[quality]
	if q then
		tex:SetColorTexture(q.r, q.g, q.b, 1)
	else
		tex:SetColorTexture(UI.Color("frame"))
	end
end

-- A button that is only its text: idle role (default muted), the heading color under the mouse.
function ns.LootParts_FlatButton(parent, text, size, idle)
	local b = CreateFrame("Button", nil, parent)
	idle = idle or "textMuted"
	b.idle = idle
	b.label = UI.Text(b, size or BASE_FONT - 1, idle, "label")
	b.label:SetPoint("CENTER")
	b.label:SetText(text)
	b:SetSize(math.ceil(b.label:GetUnboundedStringWidth()) + 8, BUTTON_H)
	b:SetScript("OnEnter", function(self)
		UI.SetTextRole(self.label, "heading")
	end)
	b:SetScript("OnLeave", function(self)
		UI.SetTextRole(self.label, self:IsEnabled() and self.idle or "textFaint")
	end)
	b:SetScript("OnEnable", function(self)
		UI.SetTextRole(self.label, self.idle)
	end)
	b:SetScript("OnDisable", function(self)
		UI.SetTextRole(self.label, "textFaint")
	end)
	return b
end

-- A small keycap: cap:SetKey(text, size) shows it (nil hides it) and returns its width (0 when hidden).
function ns.LootParts_Keycap(parent)
	local cap = CreateFrame("Frame", nil, parent)
	cap.fill = UI.Surface(cap, 0.6)
	cap.text = UI.Text(cap, BASE_FONT - 2, "textMuted", "number")
	cap.text:SetPoint("CENTER", 0, 0)
	function cap:SetKey(key, size)
		if not key then
			self:Hide()
			return 0
		end
		size = size or BASE_FONT
		UI.SetFont(self.text, "number", size - 2)
		self.text:SetText(key)
		local h = size + 2
		self:SetSize(math.max(math.ceil(self.text:GetUnboundedStringWidth()) + 2 * CAP_PAD, h), h)
		self.fill:SetColorTexture(UI.Color("surface"))
		self:Show()
		return self:GetWidth()
	end
	return cap
end

-- The key shown on Take all: the key that takes all while looting, else the key binding; nil without either.
function ns.LootParts_TakeKeyText()
	local key = db.lootKey ~= "off" and db.lootKey or GetBindingKey(BINDING)
	return key and GetBindingText(key) or nil
end

-- Take all's tooltip, for every look's button.
function ns.LootParts_TakeAllTooltip(owner)
	GameTooltip:SetOwner(owner, "ANCHOR_TOP")
	GameTooltip:AddLine("Take all", UI.RGB("heading"))
	if db.lootKey ~= "off" then
		UI.TipLine("Key while looting: " .. GetBindingText(db.lootKey), "textMuted")
	end
	local key = GetBindingKey(BINDING)
	if key then
		UI.TipLine("Key binding: " .. GetBindingText(key), "textMuted")
	end
	GameTooltip:Show()
end

function ns.LootParts_Init(moduleDB)
	db = moduleDB
end
