local addonName, ns = ...

-- Talent guide (World of Warcraft: Forever only): paste a build from Method's talent calculator, and the talent
-- window marks the next talent of the build. Builds are saved per class, each character follows one. Tomte never
-- spends points. Pure rules in Data.lua, the tree in Read.lua, the marks in Marker.lua.
-- Design: docs/superpowers/specs/2026-11-22-tomte-talent-guide-design.md.

local REFRESH_DELAY = 0.05 -- seconds: gathers a burst of trait events, and lets the talent window lay out its buttons
local MAX_ROWS = 12 -- saved-build rows in settings
local CALCULATOR_URL = "https://www.method.gg/wow-forever/talent-calculator/%s"
local GUIDE_URL = "https://www.method.gg/wow-forever/wow-forever-%s-leveling-guide-and-talents"
local UI = ns.UI

local module, db
local decoded = {} -- [treeID .. "#" .. text] = build or false: decoding is the same until the tree changes

local function PlayerClass()
	local _, class = UnitClass("player")
	return class
end

local function ClassName(class)
	return LOCALIZED_CLASS_NAMES_MALE[class] or class
end

local function ClassBuilds(class)
	class = class or PlayerClass()
	db.builds[class] = db.builds[class] or {}
	return db.builds[class]
end

-- The build string this character follows, or nil.
local function CharText()
	local text = db.chars[UnitGUID("player")]
	return text ~= "" and text or nil
end

local function SavedName(text)
	for _, saved in ipairs(ClassBuilds()) do
		if saved.text == text then
			return saved.name
		end
	end
	return nil
end

local function Decode(text, tree)
	local key = tree.treeID .. "#" .. text
	if decoded[key] == nil then
		decoded[key] = ns.TalentGuide_Decode(text, tree.nodes) or false
	end
	return decoded[key] or nil
end

-- What the talent window and the toast show for a config: { build, name, nextStep, nextName, nextMax, missing,
-- off, done, marks, offMarks }, or nil without a build that fits.
function ns.TalentGuide_View(configID)
	if not (module and module.active) then
		return nil
	end
	local text = CharText()
	local tree = text and ns.TalentGuideRead_Tree(configID)
	local build = tree and #tree.nodes > 0 and Decode(text, tree)
	if not build then
		return nil
	end
	local current = tree.current
	local view = {
		build = build,
		name = SavedName(text) or ns.TalentGuide_Name(ns.TalentGuide_Tally(build, tree.treeOf, tree.trees),
			tree.treeNames),
		nextStep = ns.TalentGuide_Next(build, current),
		missing = ns.TalentGuide_Missing(build, current),
		off = ns.TalentGuide_OffBuild(build, current),
		early = ns.TalentGuide_Early(build, current),
		done = ns.TalentGuide_Done(build, current),
		marks = db.marks,
		offMarks = db.offMarks,
	}
	if view.nextStep then
		view.nextName = ns.TalentGuideRead_NodeName(tree.configID, view.nextStep.nodeID)
		view.nextMax = ns.TalentGuideRead_MaxRanks(tree.configID, view.nextStep.nodeID)
		view.canBuy = ns.TalentGuideRead_CanBuy(tree.configID, tree.treeID, view.nextStep.nodeID)
	end
	return view
end

-- For Leveling's "Talent points to spend" toast: "Next: Frostbite (2/3)", or nil.
function ns.TalentGuide_NextText()
	local view = ns.TalentGuide_View()
	local step = view and view.nextStep
	if not step then
		return nil
	end
	return ("Next: %s (%d/%d)"):format(view.nextName or "?", step.rank, view.nextMax or step.rank)
end

local refreshSoon = UI.Debounce(REFRESH_DELAY, function()
	ns.TalentGuideMarker_Refresh()
end)

-- Pasting ----------------------------------------------------------------------------------------------------------

local REASONS = {
	format = "That isn't a build string. In Method's calculator use Export String (not Copy URL), then paste it here.",
	tree = "That build doesn't fit your talent tree. Make it again in Method's calculator and export it once more.",
	order = "The point order in that string doesn't match its talents.",
}

local function Follow(text, name)
	db.chars[UnitGUID("player")] = text
	ns.Print(("talent guide: following %s."):format(UI.Wrap(name, "accent")))
	refreshSoon()
end

-- The dialog's Save: an error text, or nil when the build was saved.
local function SavePaste(text)
	text = (text or ""):gsub("%s", "")
	if text == "" then
		return "Paste a build string first."
	end
	local class, mine = ns.TalentGuide_StringClass(text), PlayerClass()
	if class and class ~= mine then
		return ("That's a %s build. Paste it on a %s."):format(ClassName(class), ClassName(class))
	end
	local tree = ns.TalentGuideRead_Tree()
	if not tree or #tree.nodes == 0 then
		return "Your talents haven't loaded yet. Try again in a moment."
	end
	local build, why = ns.TalentGuide_Decode(text, tree.nodes)
	if not build then
		return REASONS[why] or REASONS.format
	end
	local builds = ClassBuilds()
	local name = SavedName(text)
	if not name then
		name = ns.TalentGuide_Name(ns.TalentGuide_Tally(build, tree.treeOf, tree.trees), tree.treeNames)
		builds[#builds + 1] = { name = name, text = text }
	end
	Follow(text, name)
	if not build.order then
		ns.Print("this build has no point order, so every unfinished talent is marked. Click the talents in order in "
			.. "Method's calculator before exporting to get a next talent.")
	end
	ns.Panel_Refresh()
	return nil
end

local function Paste()
	if not ns.Module_RequireOn(module) then
		return
	end
	ns.Dialog_Show({
		title = "Paste a talent build",
		hint = "From Method's World of Warcraft: Forever talent calculator: click the talents in the order you want "
			.. "them, press Export String, then paste it here (Ctrl+V).",
		text = "",
		height = 200,
		onSave = SavePaste,
	})
end

-- One link per dialog, so Ctrl+C copies just that one.
local function ShowLink(title, hint, url)
	ns.Dialog_Show({
		title = title,
		hint = "Ctrl+C, then paste it in your browser. " .. hint,
		text = url:format(PlayerClass():lower()),
		readOnly = true,
	})
end

local function FindBuild()
	ShowLink("Method's levelling guide", "It lists the talents level by level: open the calculator next and click "
		.. "them in that order.", GUIDE_URL)
end

local function OpenCalculator()
	ShowLink("Method's talent calculator", "Click the talents in the order you'll take them, press Export String, "
		.. "then paste it in Tomte.", CALCULATOR_URL)
end

-- Whether this character follows a build (the talent window's line says so when it doesn't).
function ns.TalentGuide_Following()
	return db ~= nil and CharText() ~= nil
end

-- The Builds button's menu on the talent window (Marker.lua): pick a saved build, paste one, find one.
function ns.TalentGuide_FillMenu(root)
	root:CreateTitle("Talent builds")
	local current = CharText() or ""
	local function isSelected(text)
		return text == current
	end
	local function pick(text)
		db.chars[UnitGUID("player")] = text ~= "" and text or nil
		refreshSoon()
	end
	for _, saved in ipairs(ClassBuilds()) do
		root:CreateRadio(saved.name, isSelected, pick, saved.text)
	end
	root:CreateRadio("No build", isSelected, pick, "")
	root:CreateDivider()
	root:CreateButton("Paste a build...", Paste)
	root:CreateButton("Levelling guide link...", FindBuild)
	root:CreateButton("Talent calculator link...", OpenCalculator)
end

-- Commands ---------------------------------------------------------------------------------------------------------

local function SayNext()
	if not CharText() then
		ns.Print("talent guide: this character follows no build. /tomte talentguide paste")
		return
	end
	local view = ns.TalentGuide_View()
	if not view then
		ns.Print("talent guide: the build doesn't fit your talent tree (or your talents haven't loaded).")
	elseif view.nextStep then
		local step = view.nextStep
		ns.Print(("talent guide: %s, step %d: %s (%d/%d), level %d."):format(UI.Wrap(view.name, "accent"), step.step,
			view.nextName or "?", step.rank, view.nextMax or step.rank, step.level))
	elseif view.build.order then
		ns.Print(("talent guide: %s is done."):format(UI.Wrap(view.name, "accent")))
	else
		ns.Print(("talent guide: %s, %d of %d points (no point order)."):format(UI.Wrap(view.name, "accent"),
			view.done, view.build.points))
	end
end

-- Explains what Tomte reads of the tree: the first in-game check is that it lists the nodes Method's strings expect.
local function Scan()
	local tree = ns.TalentGuideRead_Tree()
	if not tree then
		ns.Print("talent guide: no talent config to read yet.")
		return
	end
	ns.Print(("config %d, tree %d, %d talents (Method's trees have 50 to 54), trees: %s"):format(tree.configID,
		tree.treeID, #tree.nodes, table.concat(tree.treeNames, ", ")))
	local first, last = tree.nodes[1], tree.nodes[#tree.nodes]
	ns.Print(("talent IDs %s to %s"):format(first and first.id or "-", last and last.id or "-"))
	local points = 0
	for _, rank in pairs(tree.current) do
		points = points + rank
	end
	ns.Print(("points placed: %d"):format(points))
	local text = CharText()
	if text then
		local build, why = ns.TalentGuide_Decode(text, tree.nodes)
		ns.Print(build and ("build: %d points, %s"):format(build.points, build.order and "with order" or "no order")
			or ("build doesn't decode: " .. tostring(why)))
	end
end

-- Settings rows ----------------------------------------------------------------------------------------------------

local function Builds()
	if not (db and UnitGUID("player")) then
		return {}
	end
	return ClassBuilds()
end

local function Forget(index)
	local builds = Builds()
	local saved = builds[index]
	if not saved then
		return
	end
	table.remove(builds, index)
	-- Characters of the class that followed it follow nothing now.
	for guid, text in pairs(db.chars) do
		if text == saved.text then
			db.chars[guid] = nil
		end
	end
	refreshSoon()
end

local savedRows = {}
for i = 1, MAX_ROWS do
	savedRows[i] = { type = "button", text = "Forget",
		label = function()
			local saved = Builds()[i]
			return saved and saved.name or ""
		end,
		shown = function()
			return Builds()[i] ~= nil
		end,
		confirm = "Forget this build? Characters following it will follow nothing.",
		onClick = function()
			Forget(i)
		end,
	}
end

local options = {
	{ type = "header", label = "Your build" },
	{ type = "button", label = "Paste a build", text = "Paste", onClick = Paste,
		tooltip = "A build string from Method's World of Warcraft: Forever talent calculator (Export String)." },
	{ type = "button", label = "Method's levelling guide", text = "Link", onClick = FindBuild,
		tooltip = "The guide for your class lists a build's talents level by level. Copy the link into your browser." },
	{ type = "button", label = "Method's talent calculator", text = "Link", onClick = OpenCalculator,
		tooltip = "Click the talents in order there and press Export String. Copy the link into your browser." },
	{ type = "dropdown", label = "This character follows",
		get = function()
			return CharText() or ""
		end,
		set = function(value)
			db.chars[UnitGUID("player")] = value ~= "" and value or nil
			refreshSoon()
		end,
		choices = function()
			local choices = { { value = "", text = "No build" } }
			for _, saved in ipairs(Builds()) do
				choices[#choices + 1] = { value = saved.text, text = saved.name }
			end
			return choices
		end },

	{ type = "header", label = "Talent window" },
	{ type = "checkbox", key = "marks", label = "Mark the next talent", onChange = refreshSoon,
		tooltip = "The next talent of your build glows, and a line under the trees says where you are." },
	{ type = "checkbox", key = "offMarks", label = "Mark points that went astray", parent = "marks",
		onChange = refreshSoon,
		tooltip = "An amber border on talents you put a point in before the build's order does, a red one on talents with more points than your build gives them." },

	{ type = "header", label = "Saved builds" },
	{ type = "status", label = "No builds for your class yet", status = function()
		return "", "textMuted"
	end, shown = function()
		return Builds()[1] == nil
	end },
}
for _, row in ipairs(savedRows) do
	options[#options + 1] = row
end

-- Events -----------------------------------------------------------------------------------------------------------

local events = CreateFrame("Frame")
events:SetScript("OnEvent", ns.Perf_WrapEvents(function()
	refreshSoon()
end))

local EVENTS = { "TRAIT_NODE_CHANGED", "TRAIT_CONFIG_UPDATED", "TRAIT_TREE_CURRENCY_INFO_UPDATED",
	"ACTIVE_TALENT_GROUP_CHANGED", "PLAYER_LEVEL_UP" }

-- The talent window loads on demand. Can't be unhooked: the marker does nothing while the module is off.
EventUtil.ContinueOnAddOnLoaded("Blizzard_PlayerSpells", function()
	local frame = PlayerSpellsFrame and PlayerSpellsFrame.TalentsFrame
	if frame then
		frame:HookScript("OnShow", refreshSoon)
		frame:HookScript("OnHide", ns.TalentGuideMarker_Hide)
	end
end)

module = ns.RegisterModule({
	key = "talentguide",
	name = "Talent guide",
	category = "class",
	icon = 237162, -- inv_inscription_scroll
	summary = "Follow a talent build from Method's calculator: the talent window marks your next talent.",
	description = "Paste a talent build string from Method's World of Warcraft: Forever talent calculator. The talent window then marks the next talent of the build, and talents you put points in that the build doesn't have. Builds are saved for your class, so your other characters of that class can follow them too. Tomte never spends points for you.",
	enabledByDefault = true,
	defaults = {
		marks = true,
		offMarks = true,
		builds = {}, -- [class file] = list of { name = "Frost 18/0/33", text = build string }
		chars = {}, -- [player GUID] = the build string this character follows
	},
	init = function(moduleDB)
		db = moduleDB
		ns.TalentGuideMarker_Init(module)
	end,
	toggle = function(active)
		if active then
			for _, event in ipairs(EVENTS) do
				events:RegisterEvent(event)
			end
			refreshSoon()
		else
			events:UnregisterAllEvents()
			ns.TalentGuideMarker_Hide()
		end
	end,
	commands = {
		{ "paste", "paste a talent build from Method's calculator", Paste },
		{ "next", "say the next talent of your build", SayNext },
		{ "guide", "the link to Method's levelling guide for your class", FindBuild },
		{ "calculator", "the link to Method's talent calculator for your class", OpenCalculator },
		{ debug = true, "scan", "show what Talent guide reads of your talent tree", Scan },
	},
	options = options,
})
