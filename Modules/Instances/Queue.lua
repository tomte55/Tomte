local addonName, ns = ...

-- Instances: the queue plate and the holiday dungeon.
-- Queue plate: a small panel by Blizzard's queue eye (QueueStatusButton) with the time in queue, a role icon per
-- place in the group that lights up when it's filled (one icon and a count for roles with more than ROLE_ICONS
-- places, as in Raid Finder) and the average wait. Its own click-through frame anchored to the eye: nothing of
-- Blizzard's is changed.
-- Holiday dungeon: the first time Dungeon Finder opens in a session, select the holiday boss or Timewalking random
-- dungeon (LFDQueueFrame_SetType, what Blizzard's own type dropdown and LFDFrame_DisplayDungeonByID call). That
-- leaves LFDQueueFrame.type written by addon code; Find Group then joins from tainted code, which is fine because
-- JoinLFG, SetLFGDungeon and ClearAllLFGDungeons aren't protected (warcraft.wiki.gg World_of_Warcraft_API carries
-- no #protected or #hwevent on them). Picking a type in the dropdown yourself makes it Blizzard's again.

local ICON = 14 -- role icon size
local ICON_GAP = 1
local ROLE_GAP = 6 -- between roles
local ROLE_ICONS = 3 -- a role with more places shows one icon and "found/total"
local PAD = 6
local EYE_GAP = 2 -- between the eye and the plate
local TICK = 1 -- seconds between clock updates while queued
-- Blizzard's role icons (GetIconForRole, Blizzard's QueueStatusFrame uses it); these atlases if it's missing.
local FALLBACK_ATLAS = { TANK = "roleicon-tiny-tank", HEALER = "roleicon-tiny-healer", DAMAGER = "roleicon-tiny-dps" }

local UI = ns.UI
local events = ns.Instances_Events

local queueActive, holidayActive = false, false
local ring, ticker
local hooked = false
local holidayDone = false -- tried this session (whether or not a holiday dungeon was up)

local function Eye()
	return QueueStatusButton
end

-- Ring ------------------------------------------------------------------------------------------------------------

-- The plate's looks on f: the real plate's and the settings preview's (InstancesQueue_DrawSample below).
local function Dress(f)
	UI.Panel(f, { subtle = true })
	f.time = UI.Text(f, 13, "heading", "number")
	f.time:SetPoint("TOPLEFT", PAD, -PAD)
	f.diff = UI.Text(f, 10, "textMuted")
	f.diff:SetPoint("TOPLEFT", f.time, "BOTTOMLEFT", 0, -2)
	f.icons, f.counts = {}, {}
end

local function Build()
	ring = CreateFrame("Frame", nil, UIParent)
	ring:EnableMouse(false)
	ring:SetClampedToScreen(true)
	Dress(ring)
	ring:Hide()
end

local function Icon(f, i)
	local icon = f.icons[i]
	if not icon then
		icon = f:CreateTexture(nil, "ARTWORK")
		icon:SetSize(ICON, ICON)
		f.icons[i] = icon
	end
	return icon
end

local function Count(f, i)
	local count = f.counts[i]
	if not count then
		count = UI.Text(f, 10, "text", "number")
		f.counts[i] = count
	end
	return count
end

local function SetRoleIcon(icon, role, lit)
	local atlas = GetIconForRole and GetIconForRole(role, false) or FALLBACK_ATLAS[role]
	icon:SetAtlas(atlas)
	icon:SetDesaturated(not lit)
	icon:SetAlpha(lit and 1 or 0.35)
end

-- Sets up the role icons and counts for slots (Data.lua's Instances_RoleSlots). Returns the row's width and how
-- many icons and counts are in use, for Layout. f: the plate (Dress).
local function DrawRoles(f, slots)
	local x, nIcon, nCount = 0, 0, 0
	for _, slot in ipairs(slots or {}) do
		if x > 0 then
			x = x + ROLE_GAP
		end
		local many = slot.total > ROLE_ICONS
		for k = 1, many and 1 or slot.total do
			nIcon = nIcon + 1
			local icon = Icon(f, nIcon)
			icon.x = x -- placed by Layout, once the time's width is known
			SetRoleIcon(icon, slot.role, many and slot.found > 0 or k <= slot.found)
			icon:Show()
			x = x + ICON + ICON_GAP
		end
		if many then
			nCount = nCount + 1
			local count = Count(f, nCount)
			count:SetText(slot.found .. "/" .. slot.total)
			UI.SetTextRole(count, slot.found >= slot.total and "success" or "text")
			count.x = x + 1
			count:Show()
			x = x + 1 + math.ceil(count:GetUnboundedStringWidth())
		end
	end
	for i = nIcon + 1, #f.icons do
		f.icons[i]:Hide()
	end
	for i = nCount + 1, #f.counts do
		f.counts[i]:Hide()
	end
	return x, nIcon, nCount
end

-- Edit Mode can scale the micro menu the eye sits in, and dock it at the top of the screen: match the eye's scale,
-- and put the plate below the eye when it's in the top half (above it otherwise), so it stays on screen.
local function Fit(eye)
	ring:SetScale(eye:GetEffectiveScale() / UIParent:GetEffectiveScale())
	local _, y = eye:GetCenter()
	local below = (y and y * eye:GetEffectiveScale() > UIParent:GetHeight() * UIParent:GetEffectiveScale() / 2)
		and true or false
	ring:ClearAllPoints()
	if below then
		ring:SetPoint("TOP", eye, "BOTTOM", 0, -EYE_GAP)
	else
		ring:SetPoint("BOTTOM", eye, "TOP", 0, EYE_GAP)
	end
end

-- Sizes plate f around the time, the average and the role row (right of the time).
local function Layout(f, rolesW, nIcon, nCount)
	local timeW = math.ceil(f.time:GetUnboundedStringWidth())
	local diffW = f.diff:IsShown() and math.ceil(f.diff:GetUnboundedStringWidth()) or 0
	local left = math.max(timeW, diffW)
	local x0 = PAD + left + (rolesW > 0 and ROLE_GAP + 2 or 0)
	for i = 1, nIcon do
		local icon = f.icons[i]
		icon:ClearAllPoints()
		icon:SetPoint("LEFT", f, "TOPLEFT", x0 + icon.x, -PAD - ICON / 2)
	end
	for i = 1, nCount do
		local count = f.counts[i]
		count:ClearAllPoints()
		count:SetPoint("LEFT", f, "TOPLEFT", x0 + count.x, -PAD - ICON / 2)
	end
	local textH = f.time:GetStringHeight() + (diffW > 0 and 2 + f.diff:GetStringHeight() or 0)
	f:SetSize(x0 + rolesW + PAD, PAD * 2 + math.max(textH, rolesW > 0 and ICON or 0))
end

-- Fills plate f (Dress) for a queue entered elapsed seconds ago (InstancesRead_Queue's average, needs and totals).
local function Fill(f, elapsed, q)
	local time, diff, role = ns.Instances_WaitText(elapsed, q.average)
	f.time:SetText(time)
	f.diff:SetText(diff or "")
	f.diff:SetShown(diff ~= nil)
	UI.SetTextRole(f.diff, role or "textMuted")
	Layout(f, DrawRoles(f, ns.Instances_RoleSlots(q.needs, q.totals)))
end

-- The settings preview's made-up queue: a dungeon with the tank found, the healer and two damage places open.
local SAMPLE_ELAPSED = 252 -- seconds in queue
local SAMPLE_QUEUE = { average = 342, needs = { tank = 0, healer = 1, dps = 2 }, totals = { tank = 1, healer = 1, dps = 3 } }

-- The settings preview (Panel/Preview.lua): the plate for SAMPLE_QUEUE, drawn by Dress and Fill like the real one.
function ns.InstancesQueue_DrawSample(host)
	local f = host.plate
	if not f then
		f = CreateFrame("Frame", nil, host)
		f:SetPoint("TOPLEFT")
		Dress(f)
		host.plate = f
	end
	Fill(f, SAMPLE_ELAPSED, SAMPLE_QUEUE)
	return f:GetWidth(), f:GetHeight()
end

local function StopTicker()
	if ticker then
		ticker:Cancel()
		ticker = nil
	end
end

local function Update()
	local eye = Eye()
	local q = queueActive and eye and eye:IsVisible() and ns.InstancesRead_Queue()
	if not q then
		StopTicker()
		if ring then
			ring:Hide()
		end
		return
	end
	if not ring then
		Build()
	end
	ring:SetFrameStrata(eye:GetFrameStrata())
	ring:SetFrameLevel(eye:GetFrameLevel() + 10)
	Fit(eye)
	Fill(ring, q.queuedTime and (GetTime() - q.queuedTime) or 0, q)
	ring:Show()
	ticker = ticker or C_Timer.NewTicker(TICK, Update)
end

local QUEUE_EVENTS = { "LFG_UPDATE", "LFG_QUEUE_STATUS_UPDATE", "LFG_ROLE_CHECK_UPDATE", "LFG_PROPOSAL_SHOW",
	"LFG_PROPOSAL_FAILED", "LFG_PROPOSAL_SUCCEEDED", "GROUP_ROSTER_UPDATE", "PLAYER_ENTERING_WORLD" }
for _, event in ipairs(QUEUE_EVENTS) do
	events:On("queue", event, function()
		Update()
	end)
end

-- The eye shows and hides with Blizzard's queue state; hooks can't be undone, so they do nothing while off.
local function HookEye()
	local eye = Eye()
	if hooked or not eye then
		return
	end
	hooked = true
	eye:HookScript("OnShow", function()
		if queueActive then
			Update()
		end
	end)
	eye:HookScript("OnHide", function()
		if queueActive then
			Update()
		end
	end)
end

function ns.InstancesQueue_Toggle(on)
	if on == queueActive then
		return
	end
	queueActive = on
	if on then
		for _, event in ipairs(QUEUE_EVENTS) do
			events:Watch("queue", event)
		end
		HookEye()
	else
		for _, event in ipairs(QUEUE_EVENTS) do
			events:Unwatch("queue", event)
		end
	end
	Update()
end

-- Holiday dungeon ---------------------------------------------------------------------------------------------------

local function SelectHoliday()
	if not holidayActive or holidayDone or InCombatLockdown() then
		return
	end
	if not (LFDParentFrame and LFDParentFrame:IsShown() and LFDQueueFrame and LFDQueueFrame_SetType) then
		return
	end
	if GetNumRandomDungeons() == 0 then
		-- The list isn't in yet on the first open (Blizzard asks for it in LFDQueueFrame_OnShow).
		events:Watch("holiday", "LFG_UPDATE_RANDOM_INFO")
		return
	end
	holidayDone = true
	events:Unwatch("holiday", "LFG_UPDATE_RANDOM_INFO")
	local id = ns.Instances_PickHoliday(ns.InstancesRead_RandomDungeons())
	if id and LFDQueueFrame.type ~= id then
		LFDQueueFrame_SetType(id)
	end
end

events:On("holiday", "LFG_UPDATE_RANDOM_INFO", function()
	SelectHoliday()
end)

local holidayHooked = false
function ns.InstancesHoliday_Toggle(on)
	holidayActive = on
	if on then
		if not holidayHooked and LFDParentFrame then
			holidayHooked = true
			LFDParentFrame:HookScript("OnShow", SelectHoliday) -- does nothing while off (SelectHoliday checks)
		end
		SelectHoliday()
	else
		events:UnwatchAll("holiday")
	end
end

-- For /tomte instances why.
function ns.InstancesQueue_Why()
	local q = ns.InstancesRead_Queue()
	local lines = {}
	if q then
		local p = ns.Instances_QueueProgress(q.needs, q.totals)
		lines[#lines + 1] = ("queue: %s, %s formed, average wait %s"):format(tostring(q.name),
			p and ("%d%%"):format(p * 100) or "no roles", tostring(q.average))
	else
		lines[#lines + 1] = "queue: not queued"
	end
	local pick = ns.Instances_PickHoliday(ns.InstancesRead_RandomDungeons())
	lines[#lines + 1] = ("holiday dungeon: %s (%s this session)"):format(
		pick and tostring(GetLFGDungeonInfo(pick)) or "none up", holidayDone and "selected" or "not yet tried")
	return lines
end
