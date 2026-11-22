local addonName, ns = ...

-- Alts: an "Add to list" button in the game's profession window (retail and Forever both use ProfessionsFrame), left
-- of the selected recipe's Track Recipe checkbox. It puts the recipe on the crafting list (List.lua's AltsList_Add) with the
-- number in the window's count box. Recipes on the list get their crafts left ("x3") at the end of their row in the
-- recipe list (Panel/RecipeRows.lua), left of Gear Check's upgrade mark. Started and stopped by Alts.lua.

local WIDTH = 80
local TRACK_GAP = 8 -- between the button and the Track Recipe checkbox on its right
local ROW_ORDER = 2 -- left of Gear Check's mark (Modules/Gear/Recipes.lua, order 1)

local UI = ns.UI

local events = ns.Alts_Events
local OWNER = "profbutton"
local button
local active = false

-- The page the button sits on: Blizzard_Professions loads on demand, so it's there from the first TRADE_SKILL_SHOW.
local function Page()
	return ProfessionsFrame and ProfessionsFrame.CraftingPage
end

-- Only your own profession: a linked, guild or NPC window shows recipes you can't make here.
local function OwnWindow()
	local T = C_TradeSkillUI
	return not ((T.IsTradeSkillLinked and T.IsTradeSkillLinked()) or (T.IsTradeSkillGuild and T.IsTradeSkillGuild())
		or (T.IsNPCCrafting and T.IsNPCCrafting()))
end

local function Count(page)
	local box = page.CreateMultipleInputBox
	local n = box and box.GetValue and box:GetValue()
	return math.max(tonumber(n) or 1, 1)
end

local function Add()
	local page = Page()
	local info = page and page.SchematicForm:GetRecipeInfo()
	if not (info and info.recipeID) then
		return
	end
	if not info.learned then
		ns.Print("learn this recipe first: the crafting list plans crafts someone knows.")
		return
	end
	ns.AltsList_Add(info.recipeID, Count(page))
end

local function OnEnter(self)
	GameTooltip:SetOwner(self, "ANCHOR_TOP")
	GameTooltip:SetText("Add to crafting list")
	UI.TipLine("Puts this recipe on Tomte's crafting list, as many times as the number beside Create.", "textMuted", true)
	GameTooltip:Show()
end

-- Made on first need. A child of the favorite star, so it shows and hides with it (only for a recipe you could
-- favorite), but placed left of Track Recipe: beside the star it covered a long recipe name (seen in game).
local function Ensure()
	local form = Page() and Page().SchematicForm
	local star = form and form.FavoriteButton
	local track = form and form.TrackRecipeCheckbox
	if button or not (star and track) then
		return
	end
	button = UI.Button(star, WIDTH, "Add to list")
	button:SetPoint("RIGHT", track, "LEFT", -TRACK_GAP, 0)
	button:SetScript("OnClick", Add)
	-- Hooked: UI.Button's own OnEnter and OnLeave draw its hover.
	button:HookScript("OnEnter", OnEnter)
	button:HookScript("OnLeave", GameTooltip_Hide)
end

local function Apply()
	Ensure()
	if button then
		button:SetShown(active and OwnWindow())
	end
end

events:On(OWNER, "TRADE_SKILL_SHOW", Apply)

-- Crafts left on the crafting list for a recipe row, as "x3".
ns.RecipeRows_Add("craftlist", ROW_ORDER, function(recipe)
	if not active then
		return nil
	end
	local left = 0
	for _, entry in ipairs(ns.altsDB.list) do
		if entry.recipeID == recipe.recipeID then
			left = left + (entry.crafts or 0)
		end
	end
	if left <= 0 then
		return nil
	end
	return "x" .. left, "accent"
end)

-- Every add, remove and finished craft goes through AltsList_Changed (List.lua). Never undone: the mark answers nil
-- while Alts is off.
hooksecurefunc(ns, "AltsList_Changed", ns.RecipeRows_Refresh)

function ns.AltsProfButton_Start()
	active = true
	events:Watch(OWNER, "TRADE_SKILL_SHOW")
	if Page() then
		Apply()
	end
	ns.RecipeRows_Refresh()
end

function ns.AltsProfButton_Stop()
	active = false
	events:UnwatchAll(OWNER)
	if button then
		button:Hide()
	end
	ns.RecipeRows_Refresh()
end
