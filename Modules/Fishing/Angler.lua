local addonName, ns = ...

-- Fishing: Underlight Angler fix. The problem: the artifact window (Blizzard_ArtifactUI) shows a trait only when the
-- artifact's tier is at least the trait's tier (ArtifactPerksMixin:RefreshPowers compares C_ArtifactUI.GetArtifactTier
-- with each button's tier), and for the Underlight Angler the game reports tier 0, so its window opens with no
-- traits and no lines between them. The fix: after each RefreshPowers, while the Angler is shown with tier 0, its
-- tier 1 traits are shown and linked and the lines are drawn again (RefreshDependencies). Blizzard's API is never
-- replaced (that would taint every caller of C_ArtifactUI). Rules in Data.lua, registered in Fishing.lua.

local db
local active = false
local waiting, hooked = false, false

local function Fix(perks)
	if not (active and db and db.angler) then
		return
	end
	if not ns.Fishing_AnglerNeedsFix(C_ArtifactUI.GetArtifactItemID(), C_ArtifactUI.GetArtifactTier()) then
		return
	end
	local buttons = perks.powerIDToPowerButton
	if not buttons then
		return
	end
	for _, button in pairs(buttons) do
		if ns.Fishing_AnglerShowsTier(button:GetTier()) then
			button:Show()
			button:SetLinksEnabled(not button:IsFinal())
		end
	end
	perks:RefreshDependencies(C_ArtifactUI.GetPowers())
end

local function Hook()
	local perks = ArtifactFrame and ArtifactFrame.PerksTab
	if hooked or not (perks and perks.RefreshPowers) then
		return
	end
	hooked = true
	hooksecurefunc(perks, "RefreshPowers", Fix)
	if ArtifactFrame:IsShown() then
		Fix(perks)
	end
end

function ns.FishingAngler_Init(moduleDB)
	db = moduleDB
end

-- The artifact window is load-on-demand: hook it when it loads (or now). The hook can't be undone; it does nothing
-- while the module or the setting is off. Turned off with the window open, the traits stay until it refreshes.
function ns.FishingAngler_Toggle(on)
	active = on
	if not on then
		return
	end
	if hooked then
		local perks = ArtifactFrame and ArtifactFrame.PerksTab
		if perks and ArtifactFrame:IsShown() then
			Fix(perks)
		end
	elseif not waiting then
		waiting = true
		EventUtil.ContinueOnAddOnLoaded("Blizzard_ArtifactUI", Hook)
	end
end

function ns.FishingAngler_Apply()
	ns.FishingAngler_Toggle(active)
end
