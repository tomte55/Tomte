local addonName, ns = ...

-- Recipe rows: short marks at the right end of the rows in the game's profession window recipe list (retail and
-- Forever both use ProfessionsFrame), from any module: Gear Check's upgrade (Modules/Gear/Recipes.lua), Alts' crafting
-- list count (Modules/Alts/ProfButton.lua). Blizzard's rows are tagged from the list's ScrollBox callback, never
-- replaced, and nothing is written on them. The callback can't be removed: a module that is off answers nil.

local MARK_SIZE = 11
local MARK_GAP = 4 -- pixels between marks, and between the last one and the row's right edge (or its lock icon)
local LABEL_PAD = 10 -- as Blizzard's ProfessionsRecipeListRecipeMixin:Init leaves after the name
local REFRESH_DELAY = 0.2 -- seconds: changes come in bursts (an equip fires several events)

local UI = ns.UI

local providers = {} -- { { key, order, fn } } by order, lowest at the right end
local marks = {} -- [Blizzard's recipe row] = { [key] = our font string }
local owner = {} -- our handle on the ScrollBox callback
local hooked = false

local function ScrollBox()
	local page = ProfessionsFrame and ProfessionsFrame.CraftingPage
	return page and page.RecipeList and page.RecipeList.ScrollBox
end

local function Recipe(row)
	local node = row.GetElementData and row:GetElementData()
	local data = node and node.GetData and node:GetData()
	return data and data.recipeInfo
end

-- Blizzard sizes the name to fit beside the craftable count and lock icon; this does the same with the marks' width.
local function FitLabel(row, marksWidth)
	local label = row.Label
	if not label then
		return
	end
	local used = marksWidth + LABEL_PAD + (row.SkillUps and row.SkillUps:GetWidth() or 0)
	if row.LockedIcon and row.LockedIcon:IsShown() then
		used = used + row.LockedIcon:GetWidth()
	end
	if row.Count and row.Count:IsShown() then
		used = used + row.Count:GetStringWidth()
	end
	label:SetWidth(row:GetWidth())
	label:SetWidth(math.max(0, math.min(row:GetWidth() - used, label:GetStringWidth())))
end

local function Mark(row, key)
	local own = marks[row]
	if not own then
		own = {}
		marks[row] = own
	end
	if not own[key] then
		own[key] = UI.Text(row, MARK_SIZE, "text", "number")
		own[key]:SetJustifyH("RIGHT")
	end
	return own[key]
end

local function Apply(row)
	local recipe = Recipe(row)
	local own = marks[row]
	local hadMarks = false
	if own then
		for _, mark in pairs(own) do
			hadMarks = hadMarks or mark:IsShown()
			mark:Hide()
		end
	end
	local anchor, point = row, "RIGHT"
	if row.LockedIcon and row.LockedIcon:IsShown() then
		anchor, point = row.LockedIcon, "LEFT"
	end
	local width = 0
	for _, p in ipairs(providers) do
		local text, role
		if recipe then
			text, role = p.fn(recipe)
		end
		if text then
			local mark = Mark(row, p.key)
			mark:ClearAllPoints()
			mark:SetPoint("RIGHT", anchor, point, -MARK_GAP, 0)
			mark:SetText(text)
			mark:SetTextColor(UI.Color(role or "text"))
			mark:Show()
			anchor, point = mark, "LEFT"
			width = width + mark:GetStringWidth() + MARK_GAP
		end
	end
	if width > 0 or hadMarks then
		FitLabel(row, width)
	end
end

local function RefreshNow()
	local box = ScrollBox()
	if box and box:IsVisible() then
		box:ForEachFrame(Apply)
	end
end

local refreshSoon = UI.Debounce(REFRESH_DELAY, RefreshNow)

-- Draws every visible row's marks again (a provider's answers changed). Cheap while the window is closed.
function ns.RecipeRows_Refresh()
	if hooked then
		refreshSoon()
	end
end

local function Hook()
	local box = ScrollBox()
	if hooked or not box then
		return
	end
	hooked = true
	ScrollUtil.AddInitializedFrameCallback(box, function(_, row)
		Apply(row) -- category headers and dividers share the ScrollBox: Recipe() is nil for them
	end, owner)
	RefreshNow()
end

-- fn(recipeInfo) returns text and a theme color role, or nil for no mark (and always nil while its module is off).
-- order: lower sits further right. Called once per key, at file load.
function ns.RecipeRows_Add(key, order, fn)
	providers[#providers + 1] = { key = key, order = order, fn = fn }
	table.sort(providers, function(a, b)
		return a.order < b.order
	end)
	EventUtil.ContinueOnAddOnLoaded("Blizzard_Professions", Hook)
end
