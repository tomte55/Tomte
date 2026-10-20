local addonName, ns = ...

-- Buff reminders: the icon strip, one icon per missing buff with a tooltip that names it. A plain frame, no click
-- action, so nothing here is protected; Buffs.lua still hides it in combat (the reminder is for before the pull).
-- Moved by Blizzard's Edit Mode (registered in Buffs.lua).

local SIZE, GAP = 34, 4
local MAX_ICONS = 5 -- one per check in ns.BUFFS_CHECKS
local UI = ns.UI

local holder
local icons = {}

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

local function CreateIcon(i)
	local b = CreateFrame("Frame", nil, holder)
	b:SetSize(SIZE, SIZE)
	if i == 1 then
		b:SetPoint("TOPLEFT", holder, "TOPLEFT", 0, 0)
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

local function Create()
	holder = CreateFrame("Frame", "TomteBuffStrip", UIParent)
	holder:SetSize(SIZE, SIZE)
	holder:SetMovable(true)
	holder:SetClampedToScreen(true)
	holder:SetFrameStrata("MEDIUM")
	holder.title = holder:CreateFontString(nil, "OVERLAY")
	UI.SetFont(holder.title, "title", 11)
	holder.title:SetShadowOffset(1, -1)
	holder.title:SetPoint("BOTTOMLEFT", holder, "TOPLEFT", 0, 4)
	holder.title:SetText("Missing buffs")
	for i = 1, MAX_ICONS do
		CreateIcon(i)
	end
	holder:Hide()
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

-- Shows these items (hides the strip when there are none). Colors are read here, so a theme switch reaches them
-- on the next refresh.
function ns.Buffs_StripShow(items)
	if not holder then
		Create()
	end
	UI.SetTextRole(holder.title, "heading")
	local n = math.min(#items, MAX_ICONS)
	for i = 1, MAX_ICONS do
		local b, item = icons[i], items[i]
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
	holder:SetSize(math.max(n, 1) * (SIZE + GAP) - GAP, SIZE)
	holder:SetShown(n > 0)
end

function ns.Buffs_StripHide()
	if holder then
		holder:Hide()
	end
end
