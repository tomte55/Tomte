local addonName, ns = ...

-- Friend sharing page in the Tomte window: every Battle.net friend seen running Tomte with Friend sharing on, what
-- they gave you, a Block switch and Forget, and a strip when one of them runs a newer Tomte. Rows come from
-- ns.Share_Friends, the strip from ns.Share_NewestFriendVersion (Share.lua).

local UI = ns.UI
local ROW_H = 40
local PAD = 8
local STRIP_H = 34 -- the "newer Tomte" strip

local page
local rows, used = {}, 0

local function NewRow()
	local row = CreateFrame("Frame", nil, page.scroll.content)
	row:SetHeight(ROW_H)
	row.forget = UI.Button(row, 64, "Forget")
	row.forget:SetPoint("RIGHT", -6, 0)
	row.forget:SetScript("OnClick", function(self)
		ns.Share_Forget(self:GetParent().tag)
	end)
	row.block = UI.Checkbox(row)
	row.block:SetPoint("RIGHT", row.forget, "LEFT", -60, 0)
	row.block.onChange = function(on)
		ns.Share_SetBlocked(row.tag, on)
	end
	row.blockLabel = UI.Text(row, 12, "textMuted")
	row.blockLabel:SetPoint("LEFT", row.block, "RIGHT", 6, 0)
	row.blockLabel:SetText("Block")
	row.name = UI.Text(row, 13, "heading")
	row.name:SetPoint("TOPLEFT", PAD, -4)
	row.name:SetPoint("RIGHT", row.block, "LEFT", -12, 0)
	row.name:SetWordWrap(false)
	row.detail = UI.Text(row, 11, "textMuted")
	row.detail:SetPoint("TOPLEFT", row.name, "BOTTOMLEFT", 0, -3)
	row.detail:SetPoint("RIGHT", row.block, "LEFT", -12, 0)
	row.detail:SetWordWrap(false)
	return row
end

local function Detail(f)
	local parts = {}
	if f.character then
		parts[#parts + 1] = f.character
	end
	if f.version then
		parts[#parts + 1] = "Tomte " .. f.version
	end
	if f.seen then
		parts[#parts + 1] = "seen " .. ns.Ago(time() - f.seen) .. " ago"
	end
	parts[#parts + 1] = #f.gave > 0 and ("gave you " .. table.concat(f.gave, ", ")) or "nothing new from them yet"
	return table.concat(parts, "  ·  ")
end

-- "A newer Tomte is out" strip at the top while a friend runs a newer version; the list moves down under it.
local function NewerStrip()
	local version, who = ns.Share_NewestFriendVersion()
	page.newer:SetShown(version ~= nil)
	page.scroll:ClearAllPoints()
	page.scroll:SetPoint("TOPLEFT", 8, version and -(STRIP_H + PAD) or 0)
	page.scroll:SetPoint("BOTTOMRIGHT", -8, 0)
	if version then
		page.newer.text:SetText(("A newer Tomte is out: %s %s"):format(UI.Wrap(version, "accent"),
			UI.Wrap("(" .. who .. " has it, you have " .. ns.VERSION .. ")", "textMuted")))
	end
end

local function Layout()
	for i = 1, used do
		rows[i]:Hide()
	end
	used = 0
	NewerStrip()
	local list = ns.Share_Friends()
	page.none:SetShown(#list == 0)
	local y = 0
	for _, f in ipairs(list) do
		used = used + 1
		local row = rows[used] or NewRow()
		rows[used] = row
		row.tag = f.tag
		row:SetPoint("TOPLEFT", 0, -y)
		row:SetPoint("RIGHT")
		row.name:SetText(f.name)
		row.detail:SetText(Detail(f))
		row.block:SetChecked(f.blocked)
		row:Show()
		y = y + ROW_H
	end
	page.scroll:SetContentHeight(y)
end

function ns.SharePage_Refresh()
	if page and page:IsVisible() then
		Layout()
	end
end

ns.SharePage = {
	title = "Friend sharing",
	Create = function(frame)
		page = frame
		page.scroll = UI.Scroll(page)
		page.scroll:SetPoint("TOPLEFT", 8, 0)
		page.scroll:SetPoint("BOTTOMRIGHT", -8, 0)
		page.none = UI.Text(page, 12, "textMuted")
		page.none:SetPoint("TOPLEFT", 16, -4)
		page.none:SetPoint("RIGHT", -16, 0)
		page.none:SetText("No friends seen yet. Friends show up here once they're online in WoW with Tomte and Friend sharing turned on. Both of you need a Tomte version with Friend sharing.")
		local newer = CreateFrame("Frame", nil, page)
		newer:SetHeight(STRIP_H)
		newer:SetPoint("TOPLEFT", 8, 0)
		newer:SetPoint("TOPRIGHT", -8, 0)
		UI.Panel(newer, { size = "small" })
		newer.get = UI.Button(newer, 90, "Get link")
		newer.get:SetPoint("RIGHT", -6, 0)
		newer.get:SetScript("OnClick", ns.Share_ShowDownload)
		newer.text = UI.Text(newer, 12, "text")
		newer.text:SetPoint("LEFT", 10, 0)
		newer.text:SetPoint("RIGHT", newer.get, "LEFT", -10, 0)
		newer.text:SetJustifyH("LEFT")
		newer.text:SetWordWrap(false)
		newer:Hide()
		page.newer = newer
	end,
	Refresh = Layout,
}
