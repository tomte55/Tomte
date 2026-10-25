-- Tomte Probe: a throwaway dev addon for launch day on World of Warcraft: Forever (2026-11-04). /tomteprobe shows,
-- ready to copy, what this client is (build, Interface number, project) and which of the APIs Tomte guards for
-- Forever exist. It doesn't need Tomte (whose Forever TOC can't load until we know the client's TOC suffix).
-- See docs/superpowers/specs/2026-10-25-tomte-forever-design.md. Lives in tools/, never in the release zip.

-- Every name the Forever spec marks uncertain or missing, or that a launch-set guard checks. Dotted names are
-- looked up from _G.
local NAMES = {
	{ "Foundation", {
		"C_AddOns", "C_AddOns.GetAddOnMetadata", "GetAddOnMetadata", "EventRegistry", "NineSliceUtil",
		"EditModeManagerFrame", "Settings", "Settings.RegisterCanvasLayoutCategory", "C_EncodingUtil",
		"C_SpecializationInfo", "C_SpecializationInfo.GetSpecialization", "GetLFGMode", "GetMaxBattlefieldID",
		"GetAverageItemLevel", "C_Item", "C_Item.GetCurrentItemLevel", "ItemLocation",
		"C_Spell", "C_Spell.GetSpellName", "C_SpellBook", "C_SpellBook.IsSpellKnown", "IsSpellKnown",
		"C_EventUtils", "C_EventUtils.IsEventValid", "EventUtil", "EventUtil.ContinueOnAddOnLoaded",
		"C_Texture.GetAtlasInfo", "C_DateAndTime.GetSecondsUntilDailyReset",
		"C_DateAndTime.GetSecondsUntilWeeklyReset", "C_TooltipInfo", "TooltipDataProcessor", "C_UI.Reload",
		"C_ClassColor", "issecretvalue", "C_RestrictedActions",
	} },
	{ "Chat", {
		"ChatFrameUtil", "ChatFrame_SendTell", "ChatFrame_SendBNetTell", "ChatFrame_ReplyTell", "ChatFrame_OpenChat",
		"ChatEdit_InsertLink", "ChatFrame_AddMessageEventFilter", "ChatFrame_RemoveMessageEventFilter",
		"C_ChatInfo", "C_ChatInfo.SendChatMessage", "SendChatMessage", "C_ChatInfo.InChatMessagingLockdown",
		"C_ChatInfo.GetNumReservedChatWindows", "C_ChatInfo.GetChannelShortcutForChannelID",
		"C_ChatInfo.GetChannelInfoFromIdentifier", "Menu", "Menu.ModifyMenu", "GetProfessions", "GetProfessionInfo",
		"GetNumSkillLines", "GetSkillLineInfo", "TRADE_SKILLS", "C_BattleNet", "C_BattleNet.SendGameData",
		"C_FriendList",
	} },
	{ "Map and travel", {
		"QuestMapFrame", "QuestLogMicroButton", "WorldMapFrame", "C_Map", "C_Map.SetUserWaypoint",
		"C_Map.CanSetUserWaypointOnMap", "UiMapPoint", "C_SuperTrack", "C_Navigation", "C_TaxiMap",
		"C_TaxiMap.GetAllTaxiNodes", "C_TaxiMap.GetTaxiNodesForMap", "C_TaxiMap.ShouldMapShowTaxiNodes",
		"GetTaxiMapID", "Enum.FlightPathFaction", "Enum.FlightPathState", "TaxiNodeGetType",
	} },
	{ "Items and vendors", {
		"C_Container", "C_Container.UseContainerItem", "C_Container.GetBagSlotFlag", "Enum.BagSlotFlags",
		"C_Container.GetBackpackSellJunkDisabled", "C_MerchantFrame", "C_MerchantFrame.SellAllJunkItems",
		"C_MerchantFrame.GetItemInfo", "GetMerchantItemInfo", "C_TransmogCollection", "C_ToyBox", "PlayerHasToy",
		"C_MountJournal", "C_PetBattles", "C_CurrencyInfo", "C_CurrencyInfo.GetCurrencyInfoFromLink",
		"CurrencyContainerUtil", "Enum.LootSlotType", "ContainerFrameSettingsManager", "BackpackTokenFrame",
	} },
	{ "Quests and social", {
		"C_QuestLog", "C_QuestLog.GetInfo", "C_QuestLog.GetLogIndexForQuestID", "C_QuestLog.IsQuestFlaggedCompleted",
		"C_QuestLog.IsQuestFlaggedCompletedOnAccount", "C_QuestLog.UnitIsRelatedToActiveQuest",
		"C_QuestLog.IsWorldQuest", "C_QuestLog.IsQuestTask", "C_QuestLog.ReadyForTurnIn",
		"C_QuestLog.GetTitleForQuestID", "GetQuestLogTitle", "QuestIsDaily", "QuestIsWeekly",
		"AcknowledgeAutoAcceptQuest", "C_GossipInfo", "C_SummonInfo", "GetSummonConfirmTimeLeft",
		"UnitWidgetSet", "C_NamePlate", "SoftTargetFrame", "C_TalkingHead", "TalkingHeadFrame",
		"C_PlayerInteractionManager", "Enum.PlayerInteractionType", "C_VignetteInfo", "C_PvP.GetZonePVPInfo",
	} },
}

local EVENTS = {
	"LFG_PROPOSAL_SHOW", "VIGNETTES_UPDATED", "VIGNETTE_MINIMAP_UPDATED", "EDIT_MODE_LAYOUTS_UPDATED",
	"TRADE_SKILL_LIST_UPDATE", "PLAYER_INTERACTION_MANAGER_FRAME_SHOW", "QUEST_TURNED_IN", "BN_CHAT_MSG_ADDON",
	"CHAT_MSG_COMMUNITIES_CHANNEL", "MERCHANT_SHOW", "TAXIMAP_OPENED", "LOOT_READY",
}

local ATLASES = { "editmode-actionbar-highlight-NineSlice-Corner" }

local function Lookup(name)
	local value = _G
	for part in name:gmatch("[^%.]+") do
		if type(value) ~= "table" then
			return nil
		end
		value = value[part]
	end
	return value
end

local scratch
local function EventKnown(event)
	if C_EventUtils and C_EventUtils.IsEventValid then
		return C_EventUtils.IsEventValid(event)
	end
	scratch = scratch or CreateFrame("Frame")
	local ok = pcall(scratch.RegisterEvent, scratch, event)
	if ok then
		scratch:UnregisterEvent(event)
	end
	return ok
end

local function Report()
	local out = {}
	local function Add(line)
		out[#out + 1] = line
	end
	local version, build, date, interface = GetBuildInfo()
	Add(("Build %s (%s, %s), Interface %s"):format(tostring(version), tostring(build), tostring(date),
		tostring(interface)))
	Add("WOW_PROJECT_ID " .. tostring(WOW_PROJECT_ID))
	local expansion = GetExpansionLevel and GetExpansionLevel()
	Add("GetExpansionLevel " .. tostring(expansion))
	if expansion and GetMaxLevelForExpansionLevel then
		Add("Max level " .. tostring(GetMaxLevelForExpansionLevel(expansion)))
	end
	Add("Realm " .. tostring(GetRealmName and GetRealmName()))
	for _, group in ipairs(NAMES) do
		Add("")
		Add("== " .. group[1])
		local missing = {}
		for _, name in ipairs(group[2]) do
			if Lookup(name) == nil then
				missing[#missing + 1] = name
			end
		end
		Add(("present %d of %d"):format(#group[2] - #missing, #group[2]))
		Add("missing: " .. (#missing > 0 and table.concat(missing, ", ") or "none"))
	end
	Add("")
	Add("== Events")
	for _, event in ipairs(EVENTS) do
		Add(event .. " " .. (EventKnown(event) and "yes" or "NO"))
	end
	Add("")
	Add("== Atlases")
	for _, atlas in ipairs(ATLASES) do
		local known = C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(atlas)
		Add(atlas .. " " .. (known and "yes" or "NO"))
	end
	Add("")
	Add("== Chat channels (number, name)")
	local channels = { GetChannelList() }
	for i = 1, #channels, 3 do
		Add(tostring(channels[i]) .. " " .. tostring(channels[i + 1]))
	end
	if GetNumSkillLines then
		Add("")
		Add("== Skill lines (headers in [])")
		for i = 1, GetNumSkillLines() do
			local name, isHeader = GetSkillLineInfo(i)
			Add(isHeader and ("[" .. tostring(name) .. "]") or ("  " .. tostring(name)))
		end
	end
	return table.concat(out, "\n")
end

local window
local function Show()
	if not window then
		window = CreateFrame("Frame", "TomteProbeFrame", UIParent, "BasicFrameTemplateWithInset")
		window:SetSize(560, 480)
		window:SetPoint("CENTER")
		window:SetMovable(true)
		window:EnableMouse(true)
		window:RegisterForDrag("LeftButton")
		window:SetScript("OnDragStart", window.StartMoving)
		window:SetScript("OnDragStop", window.StopMovingOrSizing)
		window.title = window:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		window.title:SetPoint("TOP", 0, -5)
		window.title:SetText("Tomte Probe: Ctrl+A, Ctrl+C, paste it to Claude")
		local scroll = CreateFrame("ScrollFrame", nil, window, "UIPanelScrollFrameTemplate")
		scroll:SetPoint("TOPLEFT", 12, -30)
		scroll:SetPoint("BOTTOMRIGHT", -32, 12)
		local box = CreateFrame("EditBox", nil, scroll)
		box:SetMultiLine(true)
		box:SetAutoFocus(false)
		box:SetFontObject(ChatFontNormal)
		box:SetWidth(510)
		box:SetScript("OnEscapePressed", function()
			window:Hide()
		end)
		scroll:SetScrollChild(box)
		window.box = box
		tinsert(UISpecialFrames, "TomteProbeFrame")
	end
	window.box:SetText(Report())
	window:Show()
	window.box:SetFocus()
	window.box:HighlightText()
end

SLASH_TOMTEPROBE1 = "/tomteprobe"
SlashCmdList.TOMTEPROBE = Show
