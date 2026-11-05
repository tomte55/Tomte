local addonName, ns = ...

-- Buff reminders: the icon strip, one icon per missing buff with a tooltip that names it. A plain frame, no click
-- action, so nothing here is protected; Buffs.lua still hides it in combat (the reminder is for before the pull).
-- Moved by Blizzard's Edit Mode (registered in Buffs.lua).

local SIZE, GAP = 34, 4
local MAX_ICONS = 5 -- one per check in ns.BUFFS_CHECKS
local BORDER = 2 -- the colored border reaches this far outside each icon
local TITLE_H = 18 -- room above the icons for the "Missing buffs" title (11 pt plus its 4 px gap)
local UI = ns.UI

local holder

-- item = { icon = file ID or path, title, lines = { { text, role } }, role = border color role }
local function IconOnEnter(self)
	local item = self.item
	if not item then
		return
	end
	GameTooltip:SetOwner(self, "ANCHOR_TOP")
	GameTooltip:SetText(item.title, UI.RGB("heading"))
	for _, line in ipairs(item.lines or {}) do
		GameTooltip:AddLine(line[1], UI.RGB(line[2] or "text"))
	end
	GameTooltip:Show()
end

local function CreateIcon(strip, i)
	local icons = strip.icons
	local b = CreateFrame("Frame", nil, strip)
	b:SetSize(SIZE, SIZE)
	if i == 1 then
		b:SetPoint("TOPLEFT", strip, "TOPLEFT", 0, 0)
	else
		b:SetPoint("LEFT", icons[i - 1], "RIGHT", GAP, 0)
	end
	b:EnableMouse(true)
	b.border = b:CreateTexture(nil, "BACKGROUND")
	b.border:SetPoint("TOPLEFT", -2, 2)
	b.border:SetPoint("BOTTOMRIGHT", 2, -2)
	b.border:SetColorTexture(1, 1, 1)
	b.icon = b:CreateTexture(nil, "ARTWORK")
	b.icon:SetAllPoints()
	b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	b.count = b:CreateFontString(nil, "OVERLAY")
	UI.SetFont(b.count, "number", 12)
	b.count:SetShadowOffset(1, -1)
	b.count:SetPoint("BOTTOMRIGHT", -2, 2)
	b:SetScript("OnEnter", IconOnEnter)
	b:SetScript("OnLeave", GameTooltip_Hide)
	icons[i] = b
	return b
end

-- The title and the icons, into strip: the real one, or a settings preview's (DrawSample).
local function Build(strip)
	strip:SetSize(SIZE, SIZE)
	strip.title = strip:CreateFontString(nil, "OVERLAY")
	UI.SetFont(strip.title, "title", 11)
	strip.title:SetShadowOffset(1, -1)
	strip.title:SetPoint("BOTTOMLEFT", strip, "TOPLEFT", 0, 4)
	strip.title:SetText("Missing buffs")
	strip.icons = {}
	for i = 1, MAX_ICONS do
		CreateIcon(strip, i)
	end
	return strip
end

local function Create()
	holder = CreateFrame("Frame", "TomteBuffStrip", UIParent)
	holder:SetMovable(true)
	holder:SetClampedToScreen(true)
	holder:SetFrameStrata("MEDIUM")
	Build(holder)
	holder:Hide()
end

-- Shows items on strip; returns how many. Colors are read here, so a theme switch reaches them on the next refresh.
local function Fill(strip, items)
	UI.SetTextRole(strip.title, "heading")
	local n = math.min(#items, MAX_ICONS)
	for i = 1, MAX_ICONS do
		local b, item = strip.icons[i], items[i]
		b.item = item
		if item and i <= n then
			b.icon:SetTexture(item.icon)
			b.border:SetVertexColor(UI.Color(item.role or "warning"))
			b.count:SetText(item.count or "")
			UI.SetTextRole(b.count, "text")
			b:Show()
		else
			b:Hide()
		end
	end
	strip:SetSize(math.max(n, 1) * (SIZE + GAP) - GAP, SIZE)
	return n
end

function ns.Buffs_StripFrame()
	return holder
end

-- frame = { point, relPoint, x, y }, scale: the saved layout.
function ns.Buffs_StripLayout(frame, scale)
	if not holder then
		Create()
	end
	holder:ClearAllPoints()
	holder:SetPoint(frame.point, UIParent, frame.relPoint, frame.x, frame.y)
	holder:SetScale(scale)
end

-- Shows these items (hides the strip when there are none).
function ns.Buffs_StripShow(items)
	if not holder then
		Create()
	end
	holder:SetShown(Fill(holder, items) > 0)
end

-- Settings preview (Panel/Preview.lua): items on a strip of host's own at this scale, title included. Returns its
-- size in host units.
function ns.Buffs_DrawSample(host, items, scale)
	local strip = host.strip
	if not strip then
		strip = Build(CreateFrame("Frame", nil, host))
		host.strip = strip
	end
	strip:SetScale(scale)
	strip:ClearAllPoints()
	strip:SetPoint("TOPLEFT", BORDER, -TITLE_H)
	Fill(strip, items)
	local w = math.max(strip:GetWidth(), math.ceil(strip.title:GetUnboundedStringWidth()))
	return (w + 2 * BORDER) * scale, (TITLE_H + SIZE + BORDER) * scale
end

function ns.Buffs_StripHide()
	if holder then
		holder:Hide()
	end
end
