local addonName, ns = ...

-- Whisper inbox: the message pane. Messages as chat bubbles (theirs left, yours right in an accent tint, the time
-- under each, links clickable) with a divider between days and a NEW divider where the unread ones began. The
-- session's "In instance" conversation holds secret messages, which can be shown but not measured, so it keeps a
-- plain line list. Built by Inbox.lua (ns.InboxMessages_Create).

local UI = ns.UI
local MAX_SHARE = 0.72 -- a bubble is at most this share of the pane's width
local PAD_X, PAD_Y = 10, 6
local TIME_H = 13 -- the time line under a bubble's text
local GAP = 4 -- between bubbles
local DIVIDER_H = 28
local TEXT_SIZE = 13

local function Clock(at)
	local t = date("*t", at)
	return ns.AFK_ClockText(t.hour, t.min, C_CVar.GetCVarBool("timeMgrUseMilitaryTime"))
end

-- Links in their item quality's color (accent for every other kind of link). The quality comes from the item string
-- ("item:123:..."; the bare "|H...|h[Sword]|h" isn't a link the API reads), so bonus IDs that raise it count. An
-- item that isn't cached yet is accent until it loads: onPending(itemID) is called for it.
local function PaintLinks(text, onPending)
	return ns.Social_ColorLinks(text, function(kind, link)
		if kind == "item" then
			local itemString = link:match("^|H(item:[^|]*)|h")
			local quality = itemString and C_Item.GetItemQualityByID(itemString)
			if quality then
				local r, g, b = C_Item.GetItemQualityColor(quality)
				return UI.Wrap(link, { r, g, b })
			end
			local itemID = tonumber(itemString and itemString:match("^item:(%d+)"))
			if itemID then
				onPending(itemID)
			end
		end
		return UI.Wrap(link, "accent")
	end)
end

-- Sets a bubble's text, and sets it again once each uncached item in it has loaded (if it still shows that text).
local function SetBubbleText(b, text)
	b.raw = text
	b.text:SetText(PaintLinks(text, function(itemID)
		Item:CreateFromItemID(itemID):ContinueOnItemLoad(function()
			if b.raw == text then
				b.text:SetText(PaintLinks(text, function() end))
			end
		end)
	end))
end

-- Bubbles ---------------------------------------------------------------------------------------------------------

local function CreateBubble(parent)
	local b = CreateFrame("Frame", nil, parent)
	b.bg = b:CreateTexture(nil, "BACKGROUND")
	b.bg:SetAllPoints()
	UI.Border(b, "frame", 0.5)
	b.text = UI.Text(b, TEXT_SIZE, "text", "chat")
	b.text:SetPoint("TOPLEFT", PAD_X, -PAD_Y)
	b.text:SetWordWrap(true)
	b.text:SetJustifyH("LEFT")
	b.time = UI.Text(b, 10, "textFaint", "number")
	b.time:SetPoint("BOTTOMRIGHT", -PAD_X, PAD_Y - 2)
	b:EnableMouse(true) -- for the links (the wheel still reaches the scroll: bubbles don't take it)
	b:SetHyperlinksEnabled(true)
	b:SetScript("OnHyperlinkClick", function(_, link, text, button)
		SetItemRef(link, text, button)
	end)
	b:SetScript("OnHyperlinkEnter", function(self, link)
		GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
		local ok = pcall(GameTooltip.SetHyperlink, GameTooltip, link) -- not every link kind has a tooltip
		if ok then
			GameTooltip:Show()
		else
			GameTooltip:Hide()
		end
	end)
	b:SetScript("OnHyperlinkLeave", GameTooltip_Hide)
	return b
end

local function CreateDivider(parent)
	local d = CreateFrame("Frame", nil, parent)
	d:SetHeight(DIVIDER_H)
	d.text = UI.Text(d, 11, "textFaint")
	d.text:SetPoint("CENTER", 0, -2)
	d.left = d:CreateTexture(nil, "ARTWORK")
	d.left:SetHeight(1)
	d.left:SetPoint("LEFT", 0, -2)
	d.left:SetPoint("RIGHT", d.text, "LEFT", -10, 0)
	d.right = d:CreateTexture(nil, "ARTWORK")
	d.right:SetHeight(1)
	d.right:SetPoint("LEFT", d.text, "RIGHT", 10, 0)
	d.right:SetPoint("RIGHT", 0, -2)
	return d
end

-- Paints a divider as a day ("Saturday 10 October") or the NEW line.
local function SetDivider(d, text, isNew)
	d.text:SetText(text)
	UI.SetTextRole(d.text, isNew and "accent" or "textFaint")
	local r, g, b = UI.Color(isNew and "accent" or "rule")
	local a = isNew and 0.6 or 0.8
	d.left:SetColorTexture(r, g, b, a)
	d.right:SetColorTexture(r, g, b, a)
end

-- Pane ------------------------------------------------------------------------------------------------------------

-- pane:Show(convo, newIndex) draws convo (nil = nothing), with the NEW divider before message newIndex. The caller
-- anchors pane.frame.
function ns.InboxMessages_Create(parent)
	local pane = { items = {}, bubbles = {}, dividers = {} }
	local frame = CreateFrame("Frame", nil, parent)
	pane.frame = frame

	local scroll = UI.Scroll(frame)
	scroll:SetPoint("TOPLEFT")
	scroll:SetPoint("BOTTOMRIGHT", -10, 0)
	pane.scroll = scroll

	-- Secret messages: a plain line list, as the chat frame shows them.
	local lines = CreateFrame("ScrollingMessageFrame", nil, frame)
	lines:SetAllPoints()
	lines:SetFontObject(ChatFontNormal)
	lines:SetJustifyH("LEFT")
	lines:SetFading(false)
	lines:SetMaxLines(200)
	lines:SetInsertMode("BOTTOM")
	lines:EnableMouseWheel(true)
	lines:SetScript("OnMouseWheel", function(self, delta)
		if delta > 0 then
			self:ScrollUp()
		else
			self:ScrollDown()
		end
	end)
	lines:Hide()
	pane.lines = lines

	-- Lays the built items out for width; returns the NEW divider's y (or nil).
	local function Layout(width)
		if width <= 2 * PAD_X + 40 then
			return nil -- not sized yet: the width change lays it out
		end
		local content = scroll.content
		local maxW = math.floor(width * MAX_SHARE)
		local y, newY = 4, nil
		for _, item in ipairs(pane.items) do
			local f = item.frame
			f:ClearAllPoints()
			if item.kind == "divider" then
				f:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
				f:SetWidth(width)
				if item.isNew then
					newY = y
				end
				y = y + DIVIDER_H
			else
				local text = f.text
				text:SetWidth(maxW - 2 * PAD_X)
				local w = math.min(math.ceil(text:GetUnboundedStringWidth()) + 1, maxW - 2 * PAD_X)
				text:SetWidth(w)
				local bubbleW = math.max(w, math.ceil(f.time:GetUnboundedStringWidth())) + 2 * PAD_X
				local h = math.ceil(text:GetStringHeight()) + TIME_H + 2 * PAD_Y
				f:SetSize(bubbleW, h)
				if item.out then
					f:SetPoint("TOPRIGHT", content, "TOPLEFT", width, -y)
				else
					f:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
				end
				y = y + h + GAP
			end
		end
		scroll:SetContentHeight(y + 4)
		return newY
	end

	-- Where the view opens: at the NEW divider, else at the bottom. Kept through re-layouts (the first one comes when
	-- the pane gets its width) until you scroll yourself.
	local follow = false
	local function Follow(newY)
		if newY then
			scroll:SetScroll(newY - 8)
		else
			scroll:SetScroll(math.huge)
		end
	end
	local function StopFollowing()
		follow = false
	end
	scroll:HookScript("OnMouseWheel", StopFollowing)
	scroll.thumb:HookScript("OnMouseDown", StopFollowing)

	scroll.onWidthChanged = function(width)
		if #pane.items > 0 then
			local newY = Layout(width)
			if follow then
				Follow(newY)
			end
		end
	end

	local function Clear()
		for _, b in ipairs(pane.bubbles) do
			b:Hide()
		end
		for _, d in ipairs(pane.dividers) do
			d:Hide()
		end
		wipe(pane.items)
	end

	local function ShowLines(convo)
		scroll:Hide()
		lines:Show()
		lines:Clear()
		local lastDay
		for _, m in ipairs(convo.messages) do
			local day = date("%Y-%m-%d", m.at)
			if day ~= lastDay then
				lastDay = day
				lines:AddMessage(" ")
				local r, g, b = UI.Color("textFaint")
				lines:AddMessage(date("%A %d %B", m.at), r, g, b)
			end
			local r, g, b = UI.Color("text")
			-- format and AddMessage take secrets (the sender and text). The pcall is a guard in case one of them
			-- refuses a secret after all: that line is skipped instead of breaking the whole redraw.
			pcall(lines.AddMessage, lines, ("%s  %s: %s"):format(UI.Wrap(Clock(m.at), "textFaint"), m.sender, m.text),
				r, g, b)
		end
		lines:AddMessage(" ")
		local r, g, b = UI.Color("textFaint")
		lines:AddMessage("Whispers in instances are hidden from addons: kept until you log out, reply goes to the last one.",
			r, g, b)
		lines:ScrollToBottom()
	end

	function pane:Show(convo, newIndex)
		Clear()
		if not convo then
			lines:Hide()
			scroll:Hide()
			return
		end
		if convo.restricted then
			ShowLines(convo)
			return
		end
		lines:Hide()
		scroll:Show()
		local content = scroll.content
		local nb, nd = 0, 0
		local function Divider(text, isNew)
			nd = nd + 1
			local d = self.dividers[nd] or CreateDivider(content)
			self.dividers[nd] = d
			SetDivider(d, text, isNew)
			d:Show()
			self.items[#self.items + 1] = { kind = "divider", frame = d, isNew = isNew }
		end
		local lastDay
		for i, m in ipairs(convo.messages) do
			local day = date("%Y-%m-%d", m.at)
			if day ~= lastDay then
				lastDay = day
				Divider(date("%A %d %B", m.at))
			end
			if i == newIndex then
				Divider(ns.Spaced("New"), true)
			end
			nb = nb + 1
			local b = self.bubbles[nb] or CreateBubble(content)
			self.bubbles[nb] = b
			SetBubbleText(b, m.text)
			b.time:SetText(Clock(m.at))
			-- Faint tints, the same in every theme: a light wash for theirs, the accent for yours.
			if m.out then
				b.bg:SetColorTexture(UI.RGBA("accent", 0.1))
				UI.SetBorderColor(b, "accent", 0.3)
			else
				b.bg:SetColorTexture(UI.RGBA("text", 0.06))
				UI.SetBorderColor(b, "frame", 0.35)
			end
			b:Show()
			self.items[#self.items + 1] = { kind = "bubble", frame = b, out = m.out }
		end
		follow = true
		Follow(Layout(scroll:GetWidth()))
	end

	return pane
end
