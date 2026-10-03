local addonName, ns = ...

-- Stable tab of the Hunter Pets entry in the panel. Left: a list of the Call Pet slots, owned families (click to
-- list their pets) and families from the tame log you haven't tamed yet (click to list where you saw them).
-- Right: a slowly turning model of the hovered pet or beast (else the clicked one, else the summoned pet) with
-- its details.

local UI = ns.UI
local GOLD, WHITE, GREY, DIM = UI.GOLD, UI.WHITE, UI.GREY, UI.DIM
local GREEN = { 0.5, 0.88, 0.5 }
local PREVIEW_W = 260
local MODEL_H = 240
local ROW_H, HEADER_H = 20, 24
local INDENT = 14
local TURN_SPEED = 0.35 -- radians per second
local DEFAULT_SCENE = 718 -- PetInfo.uiModelSceneID's default: Blizzard's pet model scene (camera + framing)
local PET_ACTOR = "pet" -- the actor tag in pet model scenes
local RETRY_LOOKUP = 0.5 -- seconds; a creature the client hasn't cached yet takes a moment to load
local SLOT_LABEL = { "1", "2", "3", "4", "5", "B" } -- B = the BM bonus slot
local GREY_CODE = "|cff9d9d9d"

local page
local summary
local expanded = {} -- ["owned:Wolf"] / ["seen:Bat"] = true, for this session
local hovered, clicked -- a pet, or a seen creature (has npcID)
local rows, used = {}, 0
local displayIDs = {} -- [npcID] = displayID, looked up this session
local Layout, ShowPreview

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

-- Seen creatures are rebuilt on every refresh, so they match by npcID.
local function IsClicked(entry)
	return clicked ~= nil and (clicked == entry or (entry.npcID ~= nil and clicked.npcID == entry.npcID))
end

-- Seen creatures only have an npcID; a tiny invisible PlayerModel turns it into a display ID. Returns nil while
-- the creature is still loading (the probe shows the preview again once it has the ID).
local function LookUpDisplayID(npcID)
	if displayIDs[npcID] then
		return displayIDs[npcID]
	end
	local probe = page.probe
	if probe.npcID ~= npcID then
		probe.npcID = npcID
		probe:SetCreature(npcID)
		C_Timer.After(RETRY_LOOKUP, function()
			if probe.npcID == npcID and page:IsVisible() then
				ShowPreview()
			end
		end)
	end
	local id = probe:GetDisplayInfo()
	if id and id > 0 then
		displayIDs[npcID] = id
		return id
	end
	return nil
end

-- Same setup as Blizzard's stable: the pet's model scene and its "pet" actor, which centres the model and
-- normalises its size. The scene/display pair is the key, so hovering back and forth doesn't reload it.
local function SetModel(p, sceneID, displayID)
	local key = displayID and (sceneID .. ":" .. displayID)
	if key == p.modelKey then
		return
	end
	p.modelKey = key
	p.actor = nil
	p.scene:SetShown(key ~= nil)
	if not key then
		return
	end
	p.scene:TransitionToModelSceneID(sceneID, CAMERA_TRANSITION_TYPE_IMMEDIATE, CAMERA_MODIFICATION_TYPE_DISCARD, true)
	local actor = p.scene:GetActorByTag(PET_ACTOR)
	if not actor then
		return
	end
	p.actor, p.baseYaw, p.turn = actor, actor:GetYaw(), 0
	-- The scene stands pets on its floor (centred only horizontally), so short pets sit low and tall ones reach
	-- the top. Centre the model on all axes and put that centre where the camera looks: the frame's middle.
	actor:SetUseCenterForOrigin(true, true, true)
	local camera = p.scene:GetActiveCamera()
	if camera then
		actor:SetPosition(camera:GetDerivedTarget())
	end
	actor:Hide()
	actor:SetOnModelLoadedCallback(function()
		actor:Show()
	end)
	actor:SetModelByCreatureDisplayID(displayID)
end

function ShowPreview()
	local entry = hovered or clicked
	if not entry then
		local snapshot = ns.Stable_Snapshot()
		local slot = ns.Stable_SummonedSlot() or 1
		entry = snapshot and snapshot.active and snapshot.active[slot]
	end
	local p = page.preview
	if not entry then
		p:Hide()
		return
	end
	p:Show()
	p.name:SetText(entry.name or "")
	if entry.npcID then
		p.info:SetText(entry.family or "")
		p.level:SetText(entry.zone and ("Seen in " .. entry.zone) or "")
		p.ability:SetText(entry.at and date("%d %b %Y", entry.at) or "")
		SetModel(p, DEFAULT_SCENE, LookUpDisplayID(entry.npcID))
		return
	end
	p.info:SetText(PetLine(entry))
	local where = entry.slot and entry.slot <= #SLOT_LABEL and (entry.slot == 6 and "Bonus slot" or ("Call Pet " .. entry.slot)) or "Stabled"
	p.level:SetText(("Level %d   -   %s"):format(entry.level or 0, where))
	local ability = entry.specAbility and C_Spell.GetSpellName(entry.specAbility)
	p.ability:SetText(ability or "")
	SetModel(p, entry.uiModelSceneID or DEFAULT_SCENE, entry.displayID)
end

local function NewRow()
	local row = CreateFrame("Button", nil, page.list.content)
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
		self.hover:SetShown(self.onClick ~= nil or self.entry ~= nil)
		if self.entry then
			hovered = self.entry
			ShowPreview()
		end
	end)
	row:SetScript("OnLeave", function(self)
		self.hover:Hide()
		if self.entry and hovered == self.entry then
			hovered = nil
			ShowPreview()
		end
	end)
	row:SetScript("OnClick", function(self)
		if self.entry then
			clicked = self.entry
			ShowPreview()
			Layout() -- the clicked row turns gold
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
	row:SetPoint("TOPLEFT", page.list.content, "TOPLEFT", 0, -y)
	row:SetPoint("RIGHT", page.list.content, "RIGHT")
	row:SetHeight(height)
	row.entry, row.onClick = nil, nil
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
	row.entry = pet
	row.icon:ClearAllPoints()
	row.icon:SetPoint("LEFT", indent + 4, 0)
	row.icon:SetTexture(pet.icon)
	row.icon:Show()
	row.name:ClearAllPoints()
	row.name:SetPoint("LEFT", row.icon, "RIGHT", 8, 0)
	row.name:SetPoint("RIGHT", row.extra, "LEFT", -8, 0)
	row.name:SetText(label and (GREY_CODE .. label .. "|r   " .. pet.name) or pet.name)
	local c = IsClicked(pet) and GOLD or WHITE
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

-- A beast from the tame log. Old entries saved without an npcID have no model to show.
local function CreatureRow(y, creature)
	local color = creature.npcID and (IsClicked(creature) and GOLD or WHITE) or GREY
	local h = TextRow(y, INDENT, creature.name, creature.zone, color)
	rows[used].entry = creature.npcID and creature or nil
	return h
end

function Layout()
	if not summary or page.list:GetWidth() <= 1 then
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
			y = y + TextRow(y, 0, GREY_CODE .. SLOT_LABEL[slot] .. "|r   empty", nil, DIM)
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
				y = y + CreatureRow(y, creature)
			end
		end
	end

	for i = used + 1, #rows do
		rows[i]:Hide()
	end
	page.list:SetContentHeight(y)
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

local function CreatePreview()
	local preview = CreateFrame("Frame", nil, page)
	preview:SetWidth(PREVIEW_W)
	preview.scene = CreateFrame("ModelScene", nil, preview, "NoCameraControlModelSceneMixinTemplate")
	preview.scene:SetPoint("TOPLEFT")
	preview.scene:SetPoint("TOPRIGHT")
	preview.scene:SetHeight(MODEL_H)
	preview.scene:HookScript("OnUpdate", function(_, dt)
		if preview.actor then
			preview.turn = (preview.turn + dt * TURN_SPEED) % (2 * math.pi)
			preview.actor:SetYaw(preview.baseYaw + preview.turn)
		end
	end)
	page.probe = CreateFrame("PlayerModel", nil, preview)
	page.probe:SetSize(1, 1)
	page.probe:SetPoint("TOPLEFT")
	page.probe:SetAlpha(0)
	page.probe:SetScript("OnModelLoaded", function(self)
		local id = self:GetDisplayInfo()
		if self.npcID and id and id > 0 and not displayIDs[self.npcID] then
			displayIDs[self.npcID] = id
			if page:IsVisible() then
				ShowPreview()
			end
		end
	end)
	local function Line(size, color, font, above, gap)
		local fs = UI.Text(preview, size, color, font)
		fs:SetPoint("TOP", above, "BOTTOM", 0, -gap)
		fs:SetPoint("LEFT", 8, 0)
		fs:SetPoint("RIGHT", -8, 0)
		fs:SetJustifyH("CENTER")
		fs:SetWordWrap(false)
		return fs
	end
	preview.name = Line(20, GOLD, ns.SCENE_TITLE_FONT, preview.scene, 8)
	preview.info = Line(13, WHITE, nil, preview.name, 8)
	preview.level = Line(12, GREY, nil, preview.info, 6)
	preview.ability = Line(12, GREY, nil, preview.level, 4)
	return preview
end

local function Create(frame)
	page = frame
	page.summary = UI.Text(page, 12, GREY)
	page.summary:SetPoint("TOPLEFT", 8, -2)
	page.summary:SetPoint("RIGHT", -8, 0)
	local line = page:CreateTexture(nil, "ARTWORK")
	line:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.25)
	line:SetHeight(1)
	line:SetPoint("TOPLEFT", page.summary, "BOTTOMLEFT", 0, -8)
	line:SetPoint("RIGHT", -8, 0)

	page.preview = CreatePreview()
	page.preview:SetPoint("TOPRIGHT", line, "BOTTOMRIGHT", 0, -12)
	page.preview:SetPoint("BOTTOMRIGHT", -8, 0)
	local divider = UI.VLine(page)
	divider:SetPoint("TOPRIGHT", page.preview, "TOPLEFT", -8, 0)
	divider:SetPoint("BOTTOMRIGHT", page.preview, "BOTTOMLEFT", -8, 0)

	page.list = UI.Scroll(page)
	page.list:SetPoint("TOPLEFT", line, "BOTTOMLEFT", -8, -8)
	page.list:SetPoint("BOTTOMRIGHT", page.preview, "BOTTOMLEFT", -24, 0)
	page.list.onWidthChanged = function()
		Layout()
	end

	page.empty = UI.Text(page, 12, GREY)
	page.empty:SetPoint("TOP", page.list, "TOP", 0, -40)
	page.empty:SetWidth(280)
	page.empty:SetJustifyH("CENTER")
	page.empty:SetWordWrap(true)
	page.empty:SetText("No pets read yet. Visit a stable master once (or /reload) so Tomte can see your pets.")
end

ns.StablePage = {
	title = "Stable",
	Create = Create,
	Refresh = function()
		ns.Stable_Refresh() -- re-read in case the API answers here
		Refresh()
	end,
}
