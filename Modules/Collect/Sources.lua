local addonName, ns = ...

-- Collect here: clickable sources. In the Mount Journal and the housing decor catalog, the achievement an item's
-- source text names becomes a link: hover for its tooltip, click to open it in the achievements window, Shift-click
-- to link it in chat. Names are matched to achievements through an index built once, on first need, riding the
-- shared achievement walk (Achievements/Walk.lua, which leaves out Feats of Strength and Legacy) plus the guild
-- categories. The hooks go in once Blizzard's windows load (Collect.lua passes ADDON_LOADED on) and do nothing while
-- Collect is off. The text itself is built in Data.lua (ns.Collect_LinkAchievements).

local WALK_KEY = "collectsources"
local CHAIN_GUARD = 30 -- steps along one achievement chain, against a loop
local COLLECTIONS = "Blizzard_Collections"
local DASHBOARD = "Blizzard_HousingDashboard"

local UI = ns.UI

local active = false
local index -- [lower-case achievement name] = achievementID, once built
local pending -- the index being built
local waiting = {} -- [fontString] = true: shown with an achievement line before the index was ready
local changed = {} -- [fontString] = { raw, text }: source text we replaced (put back when Collect turns off)
local hookedMounts, hookedDecor = false, false
local decorFrame, decorHyperlinks -- the catalog's text container, and its hyperlink setting before we changed it

-- Index ----------------------------------------------------------------------------------------------------------

local function AddName(list, id)
	local _, name = GetAchievementInfo(id)
	if name and name ~= "" then
		local key = name:lower()
		list[key] = list[key] or id
	end
end

-- A category lists one achievement per chain: the others are reached along it.
local function AddChain(list, id)
	AddName(list, id)
	local prev, steps = GetPreviousAchievement(id), 0
	while prev and steps < CHAIN_GUARD do
		AddName(list, prev)
		prev, steps = GetPreviousAchievement(prev), steps + 1
	end
	local nextID = GetNextAchievement(id)
	steps = 0
	while nextID and steps < CHAIN_GUARD do
		AddName(list, nextID)
		nextID, steps = GetNextAchievement(nextID), steps + 1
	end
end

-- Guild achievements aren't in the walk (GetCategoryList is the character's): a few hundred, read at once.
local function AddGuild(list)
	for _, categoryID in ipairs(GetGuildCategoryList() or {}) do
		for i = 1, GetCategoryNumAchievements(categoryID) or 0 do
			local id = GetAchievementInfo(categoryID, i)
			if id then
				AddChain(list, id)
			end
		end
	end
end

local Refresh

local function IndexFinished()
	index, pending = pending or {}, nil
	if active then
		Refresh()
	end
end

local function StartIndex()
	if index or pending or not active then
		return
	end
	pending = {}
	AddGuild(pending)
	ns.AchWalk_Join(WALK_KEY, {
		visit = function(id)
			AddChain(pending, id)
		end,
		finish = IndexFinished,
	})
end

local function Lookup(name)
	return index and index[name]
end

-- Links ------------------------------------------------------------------------------------------------------------

-- The achievement's link around the name as written, without the brackets chat links have.
local function Link(id, name)
	local link = GetAchievementLink(id)
	local data = link and link:match("|H(achievement:[^|]+)|h")
	if not data then
		return name
	end
	return UI.Wrap("|H" .. data .. "|h" .. name .. "|h", "accent")
end

-- Links the achievement in a source font string, or waits for the index when the text names one.
local function Apply(fs)
	if not (active and fs and fs:IsShown()) then
		return
	end
	local raw = fs:GetText()
	local mine = changed[fs]
	if not raw or raw == "" or (mine and raw == mine.text) then
		return
	end
	changed[fs] = nil
	if not index then
		local named = false
		ns.Collect_LinkAchievements(raw, function()
			named = true
		end, Link)
		if named then
			waiting[fs] = true
			StartIndex()
		end
		return
	end
	local text, count = ns.Collect_LinkAchievements(raw, Lookup, Link)
	if count > 0 then
		changed[fs] = { raw = raw, text = text }
		fs:SetText(text)
	end
end

function Refresh()
	for fs in pairs(waiting) do
		Apply(fs)
	end
	wipe(waiting)
end

-- Through the Achievements module's opener (Achievements.lua): it won't load the window's addon in combat.
local function OpenAchievement(id)
	ns.Ach_Open(id)
end

-- Mount Journal --------------------------------------------------------------------------------------------------

local function MountSource()
	return MountJournal and MountJournal.MountDisplay and MountJournal.MountDisplay.InfoButton
		and MountJournal.MountDisplay.InfoButton.Source
end

-- The info button is Blizzard's inline hyperlink frame: it already shows the link's tooltip and, on click, the
-- achievement's link tooltip (Shift: links it in chat). A plain click opens the achievement instead.
local function MountLinkClick(_, link, _, button)
	local id = active and link and tonumber(link:match("^achievement:(%d+)"))
	if id and button == "LeftButton" and not IsModifierKeyDown() then
		if ItemRefTooltip then
			ItemRefTooltip:Hide()
		end
		OpenAchievement(id)
	end
end

local function MountLinkEnter(_, link)
	if active and link and link:match("^achievement:") and GameTooltip:IsShown() then
		UI.TipLine("Click: open the achievement", "textMuted")
		GameTooltip:Show()
	end
end

local function HookMounts()
	local fs = MountSource()
	if hookedMounts or not fs or not MountJournal_UpdateMountDisplay then
		return
	end
	hookedMounts = true
	hooksecurefunc("MountJournal_UpdateMountDisplay", function()
		Apply(MountSource())
	end)
	local button = MountJournal.MountDisplay.InfoButton
	button:HookScript("OnHyperlinkClick", MountLinkClick)
	button:HookScript("OnHyperlinkEnter", MountLinkEnter)
end

-- Decor catalog ----------------------------------------------------------------------------------------------------

-- The catalog's preview text has no hyperlink handling of its own: ours shows the tooltip, opens or links.
local function DecorLinkEnter(self, link)
	if not (active and link and link:match("^achievement:")) then
		return
	end
	GameTooltip:SetOwner(self, "ANCHOR_CURSOR_RIGHT")
	GameTooltip:SetHyperlink(link)
	UI.TipLine("Click: open the achievement. Shift-click: link it in chat.", "textMuted")
	GameTooltip:Show()
end

local function DecorLinkLeave()
	if active then
		GameTooltip:Hide()
	end
end

local function DecorLinkClick(_, link, _, button)
	local id = active and link and tonumber(link:match("^achievement:(%d+)"))
	if not id or button ~= "LeftButton" then
		return
	end
	if IsModifiedClick("CHATLINK") then
		UI.InsertLink(GetAchievementLink(id))
	else
		OpenAchievement(id)
	end
end

local function DecorPreview()
	local dashboard = HousingDashboardFrame
	return dashboard and dashboard.CatalogContent and dashboard.CatalogContent.PreviewFrame
end

local function SetDecorHyperlinks(on)
	if not decorFrame then
		return
	end
	if on then
		decorFrame:SetHyperlinksEnabled(true)
	elseif decorHyperlinks ~= nil then
		decorFrame:SetHyperlinksEnabled(decorHyperlinks)
	end
end

local function HookDecor()
	local preview = DecorPreview()
	local container = preview and preview.TextContainer
	if hookedDecor or not (container and container.SourceInfo and preview.PreviewCatalogEntryInfo) then
		return
	end
	hookedDecor = true
	decorFrame = container
	decorHyperlinks = container:GetHyperlinksEnabled()
	hooksecurefunc(preview, "PreviewCatalogEntryInfo", function(self)
		Apply(self.TextContainer.SourceInfo)
	end)
	container:HookScript("OnHyperlinkEnter", DecorLinkEnter)
	container:HookScript("OnHyperlinkLeave", DecorLinkLeave)
	container:HookScript("OnHyperlinkClick", DecorLinkClick)
	SetDecorHyperlinks(active)
end

-- Module ----------------------------------------------------------------------------------------------------------

local function HookLoaded()
	if C_AddOns.IsAddOnLoaded(COLLECTIONS) then
		HookMounts()
	end
	if C_AddOns.IsAddOnLoaded(DASHBOARD) then
		HookDecor()
	end
end

-- Collect.lua's ADDON_LOADED: Blizzard's journals load on demand.
function ns.CollectSources_AddonLoaded(name)
	if active and (name == COLLECTIONS or name == DASHBOARD) then
		HookLoaded()
	end
end

function ns.CollectSources_Toggle(on)
	active = on and true or false
	if active then
		HookLoaded()
		SetDecorHyperlinks(true)
		Apply(MountSource())
		local preview = DecorPreview()
		Apply(preview and preview.TextContainer and preview.TextContainer.SourceInfo)
		return
	end
	ns.AchWalk_Leave(WALK_KEY)
	pending, index = nil, nil
	wipe(waiting)
	-- Put Blizzard's text back where ours is still showing.
	for fs, mine in pairs(changed) do
		if fs:GetText() == mine.text then
			fs:SetText(mine.raw)
		end
	end
	wipe(changed)
	SetDecorHyperlinks(false)
end
