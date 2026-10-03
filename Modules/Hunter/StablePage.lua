local addonName, ns = ...

-- Stable tab of the Hunter Pets entry in the panel. Top: a slowly turning model of the hovered pet (else
-- the clicked one, else the summoned one) with its name, family, spec and level. Below, a list: the Call Pet
-- slots, owned families (click to list their pets) and families from the tame log you haven't tamed yet
-- (click to list where you saw them).

local UI = ns.UI
local GOLD, WHITE, GREY, DIM = UI.GOLD, UI.WHITE, UI.GREY, UI.DIM
local GREEN = { 0.5, 0.88, 0.5 }
local PREVIEW_H = 128
local MODEL_W = 128
local ROW_H, HEADER_H = 20, 24
local SCROLL_STEP = 40
local INDENT = 14
local TURN_SPEED = 0.35 -- radians per second
local SLOT_LABEL = { "1", "2", "3", "4", "5", "B" } -- B = the BM bonus slot

local page
local summary
local expanded = {} -- ["owned:Wolf"] / ["seen:Bat"] = true, for this session
local hoveredPet, clickedPet
local rows, used = {}, 0
local Layout

local function PetLine(pet)
	local parts = {}
	if pet.family then
		parts[#parts + 1] = (pet.exotic and "Exotic " or "") .. pet.family
	end
	if pet.spec then
		parts[#parts + 1] = pet.spec
	end
	return table.concat(parts, "  -  ")
end

local function ShowPreview()
	local pet = hoveredPet or clickedPet
	if not pet then
		local snapshot = ns.Stable_Snapshot()
		local slot = ns.Stable_SummonedSlot() or 1
		pet = snapshot and snapshot.active and snapshot.active[slot]
	end
	local p = page.preview
	if not pet then
		p:Hide()
		return
	end
	p:Show()
	p.name:SetText(pet.name or "")
	p.info:SetText(PetLine(pet))
	local where = pet.slot and pet.slot <= #SLOT_LABEL and (pet.slot == 6 and "Bonus slot" or ("Call Pet " .. pet.slot)) or "Stabled"
	p.level:SetText(("Level %d   -   %s"):format(pet.level or 0, where))
	local ability = pet.specAbility and C_Spell.GetSpellName(pet.specAbility)
	p.ability:SetText(ability or "")
	if pet.displayID and pet.displayID ~= p.displayID then
		p.displayID = pet.displayID
		p.model:SetDisplayInfo(pet.displayID)
		p.model:SetPortraitZoom(0)
		p.facing = 0.5
		p.model:SetFacing(p.facing)
	end
	p.model:SetShown(pet.displayID ~= nil)
end

local function NewRow()
	local row = CreateFrame("Button", nil, page.content)
	row.hover = row:CreateTexture(nil, "BACKGROUND")
	row.hover:SetAllPoints()
	row.hover:SetColorTexture(1, 1, 1, 0.04)
	row.hover:Hide()
	row.toggle = UI.Text(row, 12, GREY)
	row.toggle:SetWidth(10)
	row.icon = row:CreateTexture(nil, "ARTWORK")
	row.icon:SetSize(16, 16)
	row.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	row.name = UI.Text(row, 12, WHITE)
	row.name:SetWordWrap(false)
	row.extra = UI.Text(row, 11, GREY)
	row.extra:SetJustifyH("RIGHT")
	row.extra:SetPoint("RIGHT", -6, 0)
	row.extra:SetWordWrap(false)
	row:SetScript("OnEnter", function(self)
		self.hover:SetShown(self.onClick ~= nil or self.pet ~= nil)
		if self.pet then
			hoveredPet = self.pet
			ShowPreview()
		end
	end)
	row:SetScript("OnLeave", function(self)
		self.hover:Hide()
		if self.pet and hoveredPet == self.pet then
			hoveredPet = nil
			ShowPreview()
		end
	end)
	row:SetScript("OnClick", function(self)
		if self.pet then
			clickedPet = self.pet
			ShowPreview()
		elseif self.onClick then
			self.onClick()
			Layout()
		end
	end)
	return row
end

local function Acquire(y, height)
	used = used + 1
	local row = rows[used] or NewRow()
	rows[used] = row
	row:ClearAllPoints()
	row:SetPoint("TOPLEFT", page.content, "TOPLEFT", 0, -y)
	row:SetPoint("RIGHT", page.content, "RIGHT")
	row:SetHeight(height)
	row.pet, row.onClick = nil, nil
	row.toggle:Hide()
	row.icon:Hide()
	row:Show()
	return row
end

local function Header(y, text)
	local row = Acquire(y, HEADER_H)
	row.name:ClearAllPoints()
	row.name:SetPoint("BOTTOMLEFT", 4, 5)
	row.name:SetPoint("RIGHT", row.extra, "LEFT", -8, 0)
	row.name:SetText(text:upper())
	row.name:SetTextColor(GREY[1], GREY[2], GREY[3])
	row.extra:SetText("")
	return HEADER_H
end

local function PetRow(y, indent, pet, label)
	local row = Acquire(y, ROW_H)
	row.pet = pet
	row.icon:ClearAllPoints()
	row.icon:SetPoint("LEFT", indent + 4, 0)
	row.icon:SetTexture(pet.icon)
	row.icon:Show()
	row.name:ClearAllPoints()
	row.name:SetPoint("LEFT", row.icon, "RIGHT", 8, 0)
	row.name:SetPoint("RIGHT", row.extra, "LEFT", -8, 0)
	row.name:SetText(label and (GREY_FONT_COLOR_CODE .. label .. "|r   " .. pet.name) or pet.name)
	local c = (clickedPet == pet) and GOLD or WHITE
	row.name:SetTextColor(c[1], c[2], c[3])
	row.extra:SetText(PetLine(pet))
	return ROW_H
end

local function GroupRow(y, key, name, extra, color)
	local row = Acquire(y, ROW_H)
	local open = expanded[key]
	row.onClick = function()
		expanded[key] = not open or nil
	end
	row.toggle:ClearAllPoints()
	row.toggle:SetPoint("LEFT", 4, 1)
	row.toggle:SetText(open and "-" or "+")
	row.toggle:Show()
	row.name:ClearAllPoints()
	row.name:SetPoint("LEFT", row.toggle, "RIGHT", 4, 0)
	row.name:SetPoint("RIGHT", row.extra, "LEFT", -8, 0)
	row.name:SetText(name)
	row.name:SetTextColor(color[1], color[2], color[3])
	row.extra:SetText(extra)
	return ROW_H, open
end

local function TextRow(y, indent, name, extra, color)
	local row = Acquire(y, ROW_H)
	row.name:ClearAllPoints()
	row.name:SetPoint("LEFT", indent + 4, 0)
	row.name:SetPoint("RIGHT", row.extra, "LEFT", -8, 0)
	row.name:SetText(name)
	row.name:SetTextColor(color[1], color[2], color[3])
	row.extra:SetText(extra or "")
	return ROW_H
end

local function UpdateThumb()
	local viewH, contentH = page.scroll:GetHeight(), page.content:GetHeight()
	if contentH <= viewH + 1 then
		page.thumb:Hide()
		return
	end
	local thumbH = math.max(viewH * viewH / contentH, 20)
	local offset = page.scroll:GetVerticalScroll() / (contentH - viewH) * (viewH - thumbH)
	page.thumb:SetHeight(thumbH)
	page.thumb:ClearAllPoints()
	page.thumb:SetPoint("TOPLEFT", page.scroll, "TOPRIGHT", 4, -offset)
	page.thumb:Show()
end

local function SetScroll(value)
	local maxScroll = math.max(page.content:GetHeight() - page.scroll:GetHeight(), 0)
	page.scroll:SetVerticalScroll(math.min(math.max(value, 0), maxScroll))
	UpdateThumb()
end

function Layout()
	if not summary or page.scroll:GetWidth() <= 1 then
		return
	end
	used = 0
	local y = 0
	local snapshot = ns.Stable_Snapshot()
	y = y + Header(y, "Call Pet")
	for slot = 1, #SLOT_LABEL do
		local pet = snapshot and snapshot.active and snapshot.active[slot]
		if pet then
			y = y + PetRow(y, 0, pet, SLOT_LABEL[slot])
		elseif slot <= 5 then
			y = y + TextRow(y, 0, GREY_FONT_COLOR_CODE .. SLOT_LABEL[slot] .. "|r   empty", nil, DIM)
		end
	end

	y = y + Header(y, ("Families  -  %d owned"):format(#summary.owned))
	for _, family in ipairs(summary.owned) do
		local key = "owned:" .. family.name
		local h, open = GroupRow(y, key, (family.exotic and "Exotic " or "") .. family.name, #family.pets .. (#family.pets == 1 and " pet" or " pets"), GOLD)
		y = y + h
		if open then
			for _, pet in ipairs(family.pets) do
				y = y + PetRow(y, INDENT, pet)
			end
		end
	end

	y = y + Header(y, ("Seen, not tamed  -  %d"):format(#summary.seenOnly))
	if #summary.seenOnly == 0 then
		y = y + TextRow(y, 0, "Hover beasts in the world to fill this list.", nil, DIM)
	end
	for _, family in ipairs(summary.seenOnly) do
		local key = "seen:" .. family.name
		local h, open = GroupRow(y, key, family.name, #family.creatures .. " seen", GREEN)
		y = y + h
		if open then
			for _, creature in ipairs(family.creatures) do
				y = y + TextRow(y, INDENT, creature.name, creature.zone, WHITE)
			end
		end
	end

	for i = used + 1, #rows do
		rows[i]:Hide()
	end
	page.content:SetHeight(math.max(y, 1))
	SetScroll(page.scroll:GetVerticalScroll())
end

local function Refresh()
	local snapshot = ns.Stable_Snapshot()
	summary = ns.Hunter_StableSummary(snapshot, ns.hunterDB.seen)
	page.empty:SetShown(snapshot == nil)
	if snapshot then
		page.summary:SetText(("%d pets   -   %d families   -   %d more seen"):format(summary.pets, #summary.owned, #summary.seenOnly))
	else
		page.summary:SetText("")
	end
	ShowPreview()
	Layout()
end

function ns.StablePage_Refresh()
	if page and page:IsVisible() then
		Refresh()
	end
end

local function Create(frame)
	page = frame
	local preview = CreateFrame("Frame", nil, page)
	preview:SetPoint("TOPLEFT", 0, 0)
	preview:SetPoint("RIGHT", -8, 0)
	preview:SetHeight(PREVIEW_H)
	page.preview = preview
	preview.model = CreateFrame("PlayerModel", nil, preview)
	preview.model:SetPoint("TOPLEFT")
	preview.model:SetSize(MODEL_W, PREVIEW_H)
	preview.facing = 0.5
	preview.model:SetScript("OnUpdate", function(self, dt)
		preview.facing = (preview.facing + dt * TURN_SPEED) % (2 * math.pi)
		self:SetFacing(preview.facing)
	end)
	preview.name = UI.Text(preview, 18, GOLD, ns.SCENE_TITLE_FONT)
	preview.name:SetPoint("TOPLEFT", preview.model, "TOPRIGHT", 10, -22)
	preview.name:SetPoint("RIGHT", -4, 0)
	preview.name:SetWordWrap(false)
	preview.info = UI.Text(preview, 12, WHITE)
	preview.info:SetPoint("TOPLEFT", preview.name, "BOTTOMLEFT", 0, -6)
	preview.info:SetPoint("RIGHT", -4, 0)
	preview.level = UI.Text(preview, 11, GREY)
	preview.level:SetPoint("TOPLEFT", preview.info, "BOTTOMLEFT", 0, -4)
	preview.ability = UI.Text(preview, 11, GREY)
	preview.ability:SetPoint("TOPLEFT", preview.level, "BOTTOMLEFT", 0, -4)

	page.summary = UI.Text(page, 11, GREY)
	page.summary:SetPoint("TOPLEFT", 8, -PREVIEW_H - 4)
	page.summary:SetPoint("RIGHT", -8, 0)
	local line = page:CreateTexture(nil, "ARTWORK")
	line:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.25)
	line:SetHeight(1)
	line:SetPoint("TOPLEFT", page.summary, "BOTTOMLEFT", 0, -6)
	line:SetPoint("RIGHT", -8, 0)

	page.empty = UI.Text(page, 12, GREY)
	page.empty:SetPoint("TOP", 0, -40)
	page.empty:SetWidth(280)
	page.empty:SetJustifyH("CENTER")
	page.empty:SetText("No pets read yet. Visit a stable master once (or /reload) so Tomte can see your pets.")

	page.scroll = CreateFrame("ScrollFrame", nil, page)
	page.scroll:SetPoint("TOPLEFT", line, "BOTTOMLEFT", -8, -4)
	page.scroll:SetPoint("BOTTOMRIGHT", -8, 0)
	page.scroll:EnableMouseWheel(true)
	page.content = CreateFrame("Frame", nil, page.scroll)
	page.content:SetSize(1, 1)
	page.scroll:SetScrollChild(page.content)
	page.scroll:SetScript("OnSizeChanged", function(self, width)
		page.content:SetWidth(width)
		Layout()
	end)
	page.scroll:SetScript("OnMouseWheel", function(self, delta)
		SetScroll(self:GetVerticalScroll() - delta * SCROLL_STEP)
	end)
	page.thumb = page:CreateTexture(nil, "OVERLAY")
	page.thumb:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.45)
	page.thumb:SetWidth(2)
	page.thumb:Hide()
end

ns.StablePage = {
	title = "Stable",
	Create = Create,
	Refresh = function()
		ns.Stable_Refresh() -- re-read in case the API answers here
		Refresh()
	end,
}
