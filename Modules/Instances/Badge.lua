local addonName, ns = ...

-- Instances: the minimap difficulty badge. Readable text ("5 · H", "M+12", "D8", "LFR") on the minimap's rim, in place
-- of Blizzard's difficulty flag (MinimapCluster.InstanceDifficulty), and outside instances the difficulty you have
-- chosen ("H / M"), which a click changes (UI.ContextMenu). Blizzard's flag is only made invisible and click-through
-- (alpha 0, mouse off), never hidden or moved: Blizzard shows and hides its parts itself on every update, but never
-- touches the frame's alpha or mouse, so this holds and Stop puts both back. Text rules in Data.lua.

local PAD_X, HEIGHT = 6, 16
local UPDATE_DELAY = 0.25 -- seconds; Blizzard's own flag waits as long for the instance info to settle
-- Where the badge sits on a round minimap: on the rim, this many degrees counterclockwise from the right (45 = the
-- top-right, between the rim's top and right markers, clear of the addon buttons that gather on the left).
local RIM_ANGLE = 45
local SQUARE_INSET = 4 -- from the top-right corner of a square minimap (addons set GetMinimapShape)

local UI = ns.UI
local events = ns.Instances_Events
local D = ns.INSTANCES_DIFF

local db
local active = false
local badge
local blizzSaved -- { alpha, mouse = { [frame] = enabled } } while Blizzard's flag is made invisible

local function Blizzard()
	return MinimapCluster and MinimapCluster.InstanceDifficulty
end

-- Blizzard's flag -------------------------------------------------------------------------------------------------

local function BlizzardFrames(flag)
	local frames = { flag }
	for _, f in ipairs(flag.ContentModes or {}) do
		frames[#frames + 1] = f
	end
	return frames
end

local function HideBlizzard()
	local flag = Blizzard()
	if blizzSaved or not flag then
		return
	end
	blizzSaved = { alpha = flag:GetAlpha(), mouse = {} }
	for _, f in ipairs(BlizzardFrames(flag)) do
		blizzSaved.mouse[f] = f:IsMouseEnabled()
		f:EnableMouse(false)
	end
	flag:SetAlpha(0)
end

local function RestoreBlizzard()
	local flag = Blizzard()
	if not (blizzSaved and flag) then
		blizzSaved = nil
		return
	end
	for f, enabled in pairs(blizzSaved.mouse) do
		f:EnableMouse(enabled)
	end
	flag:SetAlpha(blizzSaved.alpha)
	blizzSaved = nil
end

-- Menu and tooltip ------------------------------------------------------------------------------------------------

local function Pick(kind, difficultyID)
	local ok, reason = ns.InstancesRead_SetDifficulty(kind, difficultyID)
	if not ok then
		ns.Print(reason)
	end
end

local function OpenMenu(owner)
	local ok, reason = ns.InstancesRead_CanChoose()
	if not ok then
		ns.Print(reason)
		return
	end
	UI.ContextMenu(owner, function(_, root)
		local dungeon, raid, legacy = ns.InstancesRead_Chosen()
		local function Add(title, kind, list, current)
			root:CreateTitle(title)
			for _, id in ipairs(list) do
				root:CreateRadio(ns.InstancesRead_DifficultyName(id), function(value)
					return value == current
				end, function(value)
					Pick(kind, value)
				end, id)
			end
		end
		Add("Dungeon difficulty", "dungeon", ns.INSTANCES_DUNGEON_CHOICES, dungeon)
		root:CreateDivider()
		Add("Raid difficulty", "raid", ns.INSTANCES_RAID_CHOICES, raid)
		root:CreateDivider()
		if raid == D.raidMythic then
			-- No size to pick (Blizzard's portrait menu greys it out): say why instead.
			root:CreateTitle("Old raids: set raids to Normal or Heroic")
			return
		end
		-- The legacy setting holds the size and heroic together (5 = 10 Heroic): the size is what's picked here.
		local size = legacy == D.raid10Heroic and D.raid10 or legacy == D.raid25Heroic and D.raid25 or legacy
		Add("Old raids (before Warlords)", "legacy", ns.INSTANCES_LEGACY_CHOICES, size)
	end)
end

local function ShowTooltip(self)
	local info = ns.InstancesRead_Current()
	GameTooltip:SetOwner(self, "ANCHOR_BOTTOMLEFT", 8, 8)
	if ns.Instances_BadgeText(info) and not ns.Instances_IsOutside(info.instanceType) then
		GameTooltip:SetText(info.name or "Instance", UI.Color("heading"))
		if info.difficultyName and info.difficultyName ~= "" then
			GameTooltip:AddLine(info.difficultyName, UI.RGB("text"))
		end
		if info.delveTier then
			GameTooltip:AddLine(("Delve tier %d"):format(info.delveTier), UI.RGB("text"))
		end
		if info.keystone and info.keystone > 0 then
			GameTooltip:AddLine(("Keystone level %d"):format(info.keystone), UI.RGB("text"))
		end
		if info.maxPlayers and info.maxPlayers > 0 and info.groupSize then
			GameTooltip:AddLine(("%d of %d players"):format(info.groupSize, info.maxPlayers), UI.RGB("textMuted"))
		end
		local save = info.instanceID and ns.Instances_SaveFor(ns.InstancesRead_Saves(info.instanceID), info.difficultyID)
		if info.instanceType == "party" or info.instanceType == "raid" then
			local text, role = ns.Instances_LockoutSummary(save)
			GameTooltip:AddLine(text, UI.RGB(role))
		end
		if InGuildParty and InGuildParty() then
			GameTooltip:AddLine("Guild group", UI.RGB("success"))
		end
	else
		local dungeon, raid, legacy = ns.InstancesRead_Chosen()
		GameTooltip:SetText("Difficulty", UI.Color("heading"))
		GameTooltip:AddDoubleLine("Dungeons", ns.InstancesRead_DifficultyName(dungeon), UI.RGB("textMuted"))
		GameTooltip:AddDoubleLine("Raids", ns.InstancesRead_DifficultyName(raid), UI.RGB("textMuted"))
		if raid == D.raidMythic then
			UI.TipLine(ns.INSTANCES_LEGACY_MYTHIC_REASON, "textMuted", true)
		elseif legacy then
			GameTooltip:AddDoubleLine("Old raids", ns.InstancesRead_DifficultyName(legacy), UI.RGB("textMuted"))
		end
		local ok, reason = ns.InstancesRead_CanChoose()
		GameTooltip:AddLine(" ")
		UI.TipLine(ok and "Click to change." or reason, ok and "success" or "textMuted", true)
	end
	GameTooltip:Show()
end

-- Badge -----------------------------------------------------------------------------------------------------------

-- On the minimap's rim (Blizzard's flag spot floats outside the 12.x minimap's corner). Placed on every update: the
-- minimap's size changes with Edit Mode.
local function Place()
	badge:ClearAllPoints()
	if GetMinimapShape and GetMinimapShape() == "SQUARE" then
		badge:SetPoint("TOPRIGHT", Minimap, "TOPRIGHT", -SQUARE_INSET, -SQUARE_INSET)
		return
	end
	local r, a = Minimap:GetWidth() / 2, math.rad(RIM_ANGLE)
	badge:SetPoint("CENTER", Minimap, "CENTER", r * math.cos(a), r * math.sin(a))
end

-- A badge's looks on b, and its text: the real badge's and the settings preview's (InstancesBadge_DrawSample below).
local function Dress(b)
	b:SetHeight(HEIGHT)
	UI.Panel(b, { subtle = true })
	b.text = UI.Text(b, 11, "text", "number")
	b.text:SetPoint("CENTER", 0, 0)
end

local function Paint(b, text, role)
	b.text:SetText(text)
	UI.SetTextRole(b.text, role)
	b:SetWidth(math.ceil(b.text:GetUnboundedStringWidth()) + 2 * PAD_X)
end

local function Build()
	badge = CreateFrame("Button", nil, Minimap)
	badge:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	Dress(badge)
	badge:SetScript("OnEnter", ShowTooltip)
	badge:SetScript("OnLeave", GameTooltip_Hide)
	badge:SetScript("OnClick", function(self)
		if not self.outside then
			return
		end
		GameTooltip_Hide()
		OpenMenu(self)
	end)
	badge:Hide()
end

local function Update()
	local flag = Blizzard()
	if not (active and flag) then
		return
	end
	if not badge then
		Build()
	end
	HideBlizzard() -- once per Start; does nothing while it's already invisible
	badge:SetFrameStrata(flag:GetFrameStrata())
	badge:SetFrameLevel(math.max(flag:GetFrameLevel(), Minimap:GetFrameLevel()) + 5)
	Place()
	local info = ns.InstancesRead_Current()
	local text, role = ns.Instances_BadgeText(info)
	-- Outside an instance (and in housing) the badge shows, and a click changes, the difficulty you've chosen; in a
	-- zone with a world tier it shows the tier instead and still opens the menu.
	badge.outside = ns.Instances_IsOutside(info.instanceType)
	if badge.outside and not text and db.badgeOutside then
		local dungeon, raid = ns.InstancesRead_Chosen()
		text, role = ns.Instances_OutsideText(dungeon, raid), "textMuted"
	end
	if not text then
		badge:Hide()
		return
	end
	Paint(badge, text, role)
	badge:Show()
	if GameTooltip:GetOwner() == badge then
		ShowTooltip(badge)
	end
end

local updateSoon = UI.Debounce(UPDATE_DELAY, Update)

-- The settings preview's made-up places (InstancesRead_Current's shape): a heroic dungeon, a keystone, a delve.
local SAMPLE_PLACES = {
	{ instanceType = "party", difficultyID = D.dungeonHeroic, groupSize = 5 },
	{ instanceType = "party", difficultyID = D.keystone, isChallengeMode = true, keystone = 12 },
	{ instanceType = "scenario", delveTier = 8 },
}
local SAMPLE_GAP = 6

-- The settings preview (Panel/Preview.lua): a row of badges as they read in sample places, then, when get answers
-- "Outside instances too" on, the one for the difficulty you've chosen. Drawn by Dress and Paint like the real one.
function ns.InstancesBadge_DrawSample(host, get)
	local list = {}
	for _, info in ipairs(SAMPLE_PLACES) do
		local text, role = ns.Instances_BadgeText(info)
		list[#list + 1] = { text = text, role = role }
	end
	if get("badgeOutside") then
		local dungeon, raid = ns.InstancesRead_Chosen()
		list[#list + 1] = { text = ns.Instances_OutsideText(dungeon, raid), role = "textMuted" }
	end
	host.badges = host.badges or {}
	local x = 0
	for i, entry in ipairs(list) do
		local b = host.badges[i]
		if not b then
			b = CreateFrame("Frame", nil, host)
			Dress(b)
			host.badges[i] = b
		end
		Paint(b, entry.text, entry.role)
		b:ClearAllPoints()
		b:SetPoint("TOPLEFT", x, 0)
		b:Show()
		x = x + b:GetWidth() + SAMPLE_GAP
	end
	for i = #list + 1, #host.badges do
		host.badges[i]:Hide()
	end
	return x - SAMPLE_GAP, HEIGHT
end

local EVENTS = {
	"PLAYER_ENTERING_WORLD", "PLAYER_DIFFICULTY_CHANGED", "UPDATE_INSTANCE_INFO", "GROUP_ROSTER_UPDATE",
	"PARTY_LEADER_CHANGED", "ZONE_CHANGED_NEW_AREA", "CHALLENGE_MODE_START", "CHALLENGE_MODE_COMPLETED",
	"SCENARIO_UPDATE",
}
-- Events this client may not have.
local OPTIONAL_EVENTS = { "INSTANCE_GROUP_SIZE_CHANGED", "ACTIVE_DELVE_DATA_UPDATE" }

for _, event in ipairs(EVENTS) do
	events:On("badge", event, function()
		updateSoon()
	end)
end
for _, event in ipairs(OPTIONAL_EVENTS) do
	events:On("badge", event, function()
		updateSoon()
	end)
end

function ns.InstancesBadge_Init(saved)
	db = saved
end

function ns.InstancesBadge_Refresh()
	if active then
		Update()
	end
end

function ns.InstancesBadge_Toggle(on)
	if on == active then
		return
	end
	active = on
	if on then
		for _, event in ipairs(EVENTS) do
			events:Watch("badge", event)
		end
		for _, event in ipairs(OPTIONAL_EVENTS) do
			events:TryWatch("badge", event)
		end
		HideBlizzard()
		Update()
	else
		events:UnwatchAll("badge")
		if badge then
			badge:Hide()
		end
		RestoreBlizzard()
	end
end

-- For /tomte instances why.
function ns.InstancesBadge_Why()
	local info = ns.InstancesRead_Current()
	local text = ns.Instances_BadgeText(info)
	return ("badge: %s (type %s, difficulty %s, group %s, keystone %s, delve tier %s, world tier %s); Blizzard's "
		.. "flag %s"):format(tostring(text), tostring(info.instanceType), tostring(info.difficultyID),
		tostring(info.groupSize), tostring(info.keystone), tostring(info.delveTier), tostring(info.worldTier),
		blizzSaved and "made invisible" or "as Blizzard left it")
end
