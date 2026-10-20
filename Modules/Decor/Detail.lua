local addonName, ns = ...

-- Housing decor: the Decor page's preview pane. The selected decor's model in the catalog's own model scene, the way
-- the housing catalog previews it (Blizzard_HousingModelPreview: the entry's model file in its uiModelSceneID, in a
-- PanningModelSceneMixinTemplate: left-drag turns, right-drag moves, the wheel zooms), with its name, how many you
-- have, where it comes from and what a click on it does. Placed and filled by Page.lua; actions in Decor.lua.

local INFO_H = 200 -- the text and buttons under the model
local PAD = 12
local ACTOR_TAG = "decor" -- the actor the catalog's decor model scenes hold
local DEFAULT_SCENE = 1317 -- Constants.HousingCatalogConsts.HOUSING_CATALOG_DECOR_MODELSCENEID_DEFAULT, when missing
local EMPTY_ICON = 134249 -- inv_misc_lantern_01, the module's icon
local EMPTY_W = 230 -- the placeholder's text width
local DISC = 76 -- the placeholder's round icon
-- The action button's label per ns.Decor_ActionFor answer; the others get a line of text instead.
local ACTION_TEXT = { stop = "Stop tracking", track = "Track", waypoint = "Waypoint" }
local ACTION_TIPS = {
	stop = "Stop Blizzard's tracking of it.",
	track = "Track it with Blizzard's tracking: the objective tracker and the map lead you there.",
	waypoint = "A waypoint to %s, where Tomte saw them.",
}
local ACTION_NOTES = {
	learn = "Open %s's shop once and Tomte remembers where they stand for a waypoint.",
	none = "Blizzard's tracking can't lead to this one.",
}
local UI = ns.UI

local function DefaultScene()
	local consts = Constants and Constants.HousingCatalogConsts
	return consts and consts.HOUSING_CATALOG_DECOR_MODELSCENEID_DEFAULT or DEFAULT_SCENE
end

-- Loads the entry's model in a fresh camera (also the Reset button); false when it has none or the scene has no
-- decor actor. The pcalls: an unknown scene ID or model file errors inside Blizzard's mixin.
local function LoadModel(pane, e)
	if not e.asset then
		return false
	end
	local ok = pcall(pane.scene.TransitionToModelSceneID, pane.scene, e.sceneID or DefaultScene(),
		CAMERA_TRANSITION_TYPE_IMMEDIATE, CAMERA_MODIFICATION_TYPE_DISCARD, true)
	local actor = ok and pane.scene:GetActorByTag(ACTOR_TAG)
	if not actor then
		return false
	end
	if actor.SetPreferModelCollisionBounds then
		actor:SetPreferModelCollisionBounds(true)
	end
	return (pcall(actor.SetModelByFileID, actor, e.asset))
end

-- shown: the model is there. Else the placeholder: icon (a file ID), title and a line under it.
local function ShowModel(pane, shown, icon, title, sub)
	pane.scene:SetShown(shown)
	pane.reset:SetShown(shown)
	pane.hint:SetShown(shown)
	local empty = pane.empty
	empty:SetShown(not shown)
	if not shown then
		empty.icon:SetTexture(icon or EMPTY_ICON)
		empty.title:SetText(title)
		empty.sub:SetText(sub)
	end
end

local function SourceText(e)
	if not (e.raw and e.raw ~= "") then
		return UI.Wrap(e.line or ns.Decor_SourceWord(e.source), "textMuted")
	end
	return (ns.Decor_CleanSource(e.raw):gsub("\r?\n", "|n"))
end

local function ActionEnter(self)
	local pane = self:GetParent()
	local tip = ACTION_TIPS[pane.action]
	if not (tip and pane.entry) then
		return
	end
	GameTooltip:SetOwner(self, "ANCHOR_TOP")
	UI.TipLine(tip:format(pane.entry.vendor or "the vendor"), "text", true)
	GameTooltip:Show()
end

local function SetAction(pane, e)
	local action = ns.Decor_ActionFor(e)
	pane.action = action
	local text = ACTION_TEXT[action]
	pane.act:SetShown(text ~= nil)
	pane.actNote:SetShown(text == nil)
	if text then
		pane.act.label:SetText(text)
		UI.FitButton(pane.act, 90)
	else
		pane.actNote:SetText(ACTION_NOTES[action]:format(e.vendor or "the vendor"))
	end
	pane.link:SetShown(e.itemID ~= nil)
end

-- e: a catalog entry (Catalog.lua), or nil for "nothing selected". A new entry gets a fresh camera; the same entry
-- again (the page redrawing) keeps where you turned and zoomed it.
function ns.DecorDetail_Show(pane, e)
	pane.entry = e
	pane.info:SetShown(e ~= nil)
	if not e then
		pane.id = nil
		ShowModel(pane, false, nil, "Pick a decor",
			"Click one in the list to see it here. Drag to turn it, scroll to zoom.")
		return
	end
	if pane.id ~= e.id then
		pane.id = e.id
		pane.hasModel = LoadModel(pane, e)
	end
	ShowModel(pane, pane.hasModel, e.icon, "No model to show", "The housing catalog has no model for this one.")
	pane.name:SetText(e.name or "")
	local owned = e.owned or 0
	pane.owned:SetText(owned > 0 and UI.Wrap(("Collected: you have %d."):format(owned), "success")
		or UI.Wrap("Not collected yet.", "warning"))
	pane.source:SetText(SourceText(e))
	SetAction(pane, e)
end

function ns.DecorDetail_Create(parent)
	local pane = CreateFrame("Frame", nil, parent)
	UI.Surface(pane, 0.35)
	pane.info = CreateFrame("Frame", nil, pane)
	pane.info:SetPoint("BOTTOMLEFT")
	pane.info:SetPoint("BOTTOMRIGHT")
	pane.info:SetHeight(INFO_H)
	local rule = pane.info:CreateTexture(nil, "ARTWORK")
	rule:SetHeight(1)
	rule:SetPoint("TOPLEFT", PAD, 0)
	rule:SetPoint("TOPRIGHT", -PAD, 0)
	rule:SetColorTexture(UI.RGBA("frame", 0.35))

	pane.scene = CreateFrame("ModelScene", nil, pane, "PanningModelSceneMixinTemplate")
	pane.scene:SetPoint("TOPLEFT", 1, -1)
	pane.scene:SetPoint("BOTTOMRIGHT", pane.info, "TOPRIGHT", -1, 0)
	-- Placeholder while there's no model: a round icon on a soft disc, a title and a line, centered on the model's spot.
	local empty = CreateFrame("Frame", nil, pane)
	empty:SetSize(EMPTY_W, 1)
	empty:SetPoint("CENTER", pane.scene, "CENTER", 0, 20)
	empty.disc = empty:CreateTexture(nil, "BACKGROUND", nil, 1)
	empty.disc:SetSize(DISC, DISC)
	empty.disc:SetPoint("BOTTOM", empty, "CENTER", 0, 8)
	empty.disc:SetColorTexture(UI.RGBA("accent", 0.12))
	UI.CircleMask(empty.disc, empty)
	empty.icon = empty:CreateTexture(nil, "ARTWORK")
	empty.icon:SetSize(DISC - 24, DISC - 24)
	empty.icon:SetPoint("CENTER", empty.disc)
	empty.icon:SetAlpha(0.85)
	UI.CircleMask(empty.icon, empty)
	empty.title = UI.Text(empty, 15, "heading", "title")
	empty.title:SetPoint("TOP", empty, "CENTER", 0, -4)
	empty.title:SetWidth(EMPTY_W)
	empty.title:SetJustifyH("CENTER")
	empty.sub = UI.Text(empty, 12, "textMuted")
	empty.sub:SetPoint("TOP", empty.title, "BOTTOM", 0, -8)
	empty.sub:SetWidth(EMPTY_W)
	empty.sub:SetJustifyH("CENTER")
	empty.sub:SetSpacing(3)
	pane.empty = empty
	-- Above the model, so it never draws over them; the overlay itself takes no mouse, dragging reaches the scene.
	local overlay = CreateFrame("Frame", nil, pane)
	overlay:SetAllPoints(pane.scene)
	overlay:SetFrameLevel(pane.scene:GetFrameLevel() + 2)
	pane.hint = UI.Text(overlay, 10, "textFaint")
	pane.hint:SetPoint("BOTTOM", 0, 6)
	pane.hint:SetText("Drag to turn · right-drag to move · scroll to zoom")
	pane.reset = UI.Button(overlay, 60, "Reset")
	UI.FitButton(pane.reset, 50, 16)
	pane.reset:SetPoint("TOPRIGHT", -8, -8)
	pane.reset:SetScript("OnClick", function()
		if pane.entry then
			pane.hasModel = LoadModel(pane, pane.entry)
		end
	end)

	local info = pane.info
	pane.name = UI.Text(info, 15, "heading", "title")
	pane.name:SetPoint("TOPLEFT", PAD, -10)
	pane.name:SetPoint("TOPRIGHT", -PAD, -10)
	pane.name:SetJustifyH("LEFT")
	pane.name:SetMaxLines(2)
	pane.owned = UI.Text(info, 12, "text")
	pane.owned:SetPoint("TOPLEFT", pane.name, "BOTTOMLEFT", 0, -4)
	pane.owned:SetPoint("RIGHT", -PAD, 0)
	pane.owned:SetJustifyH("LEFT")
	pane.act = UI.Button(info, 90, "Track")
	pane.act:SetPoint("BOTTOMLEFT", PAD, 10)
	pane.act:HookScript("OnEnter", ActionEnter)
	pane.act:HookScript("OnLeave", GameTooltip_Hide)
	pane.act:SetScript("OnClick", function()
		if pane.entry then
			ns.Decor_ToggleTracking(pane.entry)
			ns.DecorPage_Refresh()
		end
	end)
	pane.link = UI.Button(info, 60, "Link")
	pane.link:SetPoint("BOTTOMRIGHT", -PAD, 10)
	pane.link:SetScript("OnClick", function()
		if pane.entry then
			ns.Decor_Link(pane.entry)
		end
	end)
	pane.actNote = UI.Text(info, 11, "textMuted")
	pane.actNote:SetPoint("BOTTOMLEFT", PAD, 12)
	pane.actNote:SetPoint("RIGHT", pane.link, "LEFT", -8, 0)
	pane.actNote:SetJustifyH("LEFT")
	pane.actNote:SetMaxLines(3)
	pane.source = UI.Text(info, 12, "text")
	pane.source:SetPoint("TOPLEFT", pane.owned, "BOTTOMLEFT", 0, -8)
	pane.source:SetPoint("BOTTOMRIGHT", -PAD, 56)
	pane.source:SetJustifyH("LEFT")
	pane.source:SetJustifyV("TOP")
	ns.DecorDetail_Show(pane, nil)
	return pane
end
