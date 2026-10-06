local addonName, ns = ...

-- Alts module: every character's snapshot (level, spec, item level, gold, zone, rest, professions) and their
-- recipes, so the Alts page can answer "who makes this, and do we have the materials?" and list the characters.
-- Data.lua holds the logic, Collect.lua reads the game, CraftTab.lua and RosterTab.lua draw the page's two tabs.
-- This file wires them up and adds "Crafted by" lines to item tooltips.

local UI = ns.UI
local GOLD, GREY = UI.GOLD, UI.GREY
local LABEL = "|cff66ccffAlts:|r "
local TAB_H = 22

local module, db
local page
local producers -- [itemID] = recipeIDs, for tooltips; rebuilt when recipes change

local function ShowTab(key)
	db.view = key
	page.craft:SetShown(key == "craft")
	page.roster:SetShown(key == "chars")
	page.list:SetShown(key == "list")
	page.chain:SetShown(key == "craft")
	for _, b in ipairs(page.tabs) do
		local on = b.key == key
		local c = on and GOLD or GREY
		b.text:SetTextColor(c[1], c[2], c[3])
		b.bar:SetShown(on)
	end
	page.chain.label:SetText(db.chain == "one" and "One step" or "Full chain")
	if key == "craft" then
		ns.AltsCraft_Refresh()
	elseif key == "list" then
		ns.AltsListTab_Refresh()
	else
		ns.AltsRoster_Refresh()
	end
end

-- The Alts page on one of its tabs ("craft", "list", "chars"), from the tracker.
function ns.Alts_ShowTab(key)
	if page and page:IsVisible() then
		ShowTab(key)
	else
		db.view = key
	end
end

local function CreateTab(parent, key, text)
	local b = CreateFrame("Button", nil, parent)
	b.key = key
	b:SetHeight(TAB_H)
	b.text = UI.Text(b, 13, GREY)
	b.text:SetPoint("BOTTOMLEFT", 0, 6)
	b.text:SetText(text)
	b:SetWidth(b.text:GetStringWidth())
	b.bar = b:CreateTexture(nil, "ARTWORK")
	b.bar:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 1)
	b.bar:SetHeight(2)
	b.bar:SetPoint("BOTTOMLEFT")
	b.bar:SetPoint("BOTTOMRIGHT")
	b:SetScript("OnClick", function(self)
		if db.view ~= self.key then
			PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
			ShowTab(self.key)
		end
	end)
	return b
end

local AltsPage = {
	title = "Alts",
	Create = function(frame)
		page = frame
		local bar = CreateFrame("Frame", nil, page)
		bar:SetPoint("TOPLEFT", 8, 0)
		bar:SetPoint("RIGHT", -8, 0)
		bar:SetHeight(TAB_H)
		local baseline = bar:CreateTexture(nil, "BACKGROUND")
		baseline:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.2)
		baseline:SetHeight(1)
		baseline:SetPoint("BOTTOMLEFT")
		baseline:SetPoint("BOTTOMRIGHT")
		page.tabs = { CreateTab(bar, "craft", "Crafting"), CreateTab(bar, "list", "Crafting list"),
			CreateTab(bar, "chars", "Characters") }
		page.tabs[1]:SetPoint("BOTTOMLEFT")
		page.tabs[2]:SetPoint("BOTTOMLEFT", page.tabs[1], "BOTTOMRIGHT", 20, 0)
		page.tabs[3]:SetPoint("BOTTOMLEFT", page.tabs[2], "BOTTOMRIGHT", 20, 0)
		-- Full chain / one step (the Crafting tab's plan depth).
		page.chain = UI.Button(bar, 100, "")
		page.chain:SetPoint("BOTTOMRIGHT", 0, 3)
		page.chain:SetScript("OnClick", function()
			db.chain = db.chain == "one" and "full" or "one"
			PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
			ShowTab("craft")
		end)
		page.chain:SetScript("OnEnter", function(self)
			UI.SetBorderColor(self, GOLD[1], GOLD[2], GOLD[3], 1)
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:SetText("Crafted materials")
			GameTooltip:AddLine("Full chain: work out every crafted material down to what you gather. One step: only the "
				.. "recipe's own materials and the crafts that make them.", 1, 1, 1, true)
			GameTooltip:Show()
		end)
		page.chain:SetScript("OnLeave", function(self)
			UI.SetBorderColor(self, GOLD[1], GOLD[2], GOLD[3], 0.45)
			GameTooltip:Hide()
		end)

		for _, key in ipairs({ "craft", "roster", "list" }) do
			local f = CreateFrame("Frame", nil, page)
			f:SetPoint("TOPLEFT", 8, -(TAB_H + 10))
			f:SetPoint("BOTTOMRIGHT", -8, 0)
			page[key] = f
		end
		ns.AltsCraft_Create(page.craft, db)
		ns.AltsRoster_Create(page.roster, db)
		ns.AltsListTab_Create(page.list)
		page:HookScript("OnShow", function()
			ns.AltsCollect_Request() -- this character's gold and zone are current
			ShowTab(db.view)
		end)
	end,
	Refresh = function()
		ShowTab(db.view)
	end,
}

function ns.Alts_Changed()
	ns.AltsRoster_Refresh()
end

function ns.Alts_RecipesChanged()
	producers = nil
	ns.AltsCraft_RecipesChanged()
	ns.AltsCraft_Refresh()
	ns.AltsRoster_Refresh()
end

-- Tooltip --------------------------------------------------------------------------------------------------

local function ProfName(c, base)
	local prof = c.profs and c.profs[base]
	return prof and prof.name or "?"
end

local function OnItem(tooltip, data)
	if not (module.active and db.tooltip and tooltip.AddLine and data) then
		return
	end
	local itemID = data.id
	if not itemID or (issecretvalue and issecretvalue(itemID)) or type(itemID) ~= "number" then
		return
	end
	producers = producers or ns.Alts_Producers(db.recipes)
	local ids = producers[itemID]
	if not ids then
		return
	end
	local learnableLine
	for _, id in ipairs(ids) do
		local recipe = db.recipes[id]
		local known, learnable = ns.Alts_Crafters(db.chars, recipe, id)
		if #known > 0 then
			local names = {}
			for i, c in ipairs(known) do
				if i > 3 then
					names[#names + 1] = "+" .. (#known - 3)
					break
				end
				names[#names + 1] = c.name
			end
			tooltip:AddLine(("%sCrafted by %s (%s)"):format(LABEL, table.concat(names, ", "), ProfName(known[1], recipe.base)),
				1, 1, 1, true)
			return
		elseif #learnable > 0 and not learnableLine then
			learnableLine = ("%s|cff9e9e9eLearnable by %s (%s)|r"):format(LABEL, learnable[1].name, ProfName(learnable[1], recipe.base))
		end
	end
	if learnableLine then
		tooltip:AddLine(learnableLine, 1, 1, 1, true)
	end
end

-- Commands -------------------------------------------------------------------------------------------------

local function Forget(name)
	name = strtrim(name or ""):lower()
	if name == "" then
		ns.Print("usage: /tomte alts forget <name>")
		return
	end
	for guid, c in pairs(db.chars) do
		if (c.name or ""):lower() == name then
			if guid == UnitGUID("player") then
				ns.Print("can't forget the character you're playing.")
				return
			end
			db.chars[guid] = nil
			ns.Print(("forgot %s."):format(c.name))
			ns.Alts_RecipesChanged()
			return
		end
	end
	ns.Print(("no character called %s."):format(name))
end

module = ns.RegisterModule({
	key = "alts",
	name = "Alts",
	category = "General",
	description = "Every character at a glance (level, spec, item level, gold, where they are, professions and unspent "
		.. "knowledge) and crafting across them: search a recipe to see who makes it, whether the account has the "
		.. "materials and where they are, and who crafts what in which order. A character's recipes are read when it "
		.. "opens its profession window.",
	enabledByDefault = true,
	uses = { { addon = "Syndicator", why = "item counts on every character and the Warband bank",
		without = "only this character's bags, bank and the Warband bank are counted" } },
	defaults = {
		chars = {},
		recipes = {},
		view = "craft",
		chain = "full",
		crafts = 1,
		roster = "compact",
		sort = "level",
		tooltip = true,
		filterChar = "all",
		filterProf = "all",
		filterShow = "learnable",
		haveMats = false,
		collapsed = {},
		sendMail = true,
		sendWarband = true,
		sendPlan = true,
		sendRules = "",
		sendGold = 0, -- gold to keep on each alt (0 = off)
		sendSubject = "Tomte",
		list = {}, -- crafting list: { { recipeID, crafts, added } }
		tracker = { shown = true, mode = "any", hideInCombat = true, locked = true, scale = 1 },
		listDone = "auto", -- auto | hand
		listMail = "exact", -- exact | stacks
		listBaganator = true,
		listPrice = true,
	},
	home = {
		ns.AltsHomeSection,
		{ kind = "page", key = "alts", order = 1, name = "Alts", icon = "Interface\\Icons\\Achievement_Character_Human_Male",
			page = AltsPage,
			summary = function()
				local n = 0
				for _ in pairs(db.chars) do
					n = n + 1
				end
				return ("%d character%s · %s"):format(n, n == 1 and "" or "s", ns.Alts_Gold(ns.Alts_TotalGold(db.chars)))
			end },
		{ kind = "next", key = "nextsend", name = "Materials for your alts", score = 40,
			description = "You carry materials another character crafts with: the mailbox and the bank have a \"For your alts\" panel.",
			candidates = function()
				local text = ns.AltsSend_Summary()
				if not text then
					return {}
				end
				return { { key = "alts:send", state = text, text = "Send " .. text,
					why = "At a mailbox (or the Warband bank), the \"For your alts\" panel sends them.",
					icon = "Interface\\Icons\\INV_Letter_15" } }
			end },
	},
	init = function(saved)
		db = saved
		ns.altsDB = saved
		TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, OnItem)
	end,
	toggle = function(active)
		if active then
			ns.AltsCollect_Start(db)
			ns.AltsSend_Start(db)
			ns.AltsList_Start(db)
		else
			ns.AltsCollect_Stop()
			ns.AltsSend_Stop()
			ns.AltsList_Stop()
		end
	end,
	options = {
		{ type = "checkbox", key = "tooltip", label = "\"Crafted by\" on item tooltips",
			tooltip = "Item tooltips say which of your characters crafts the item, or who could learn it." },
		{ type = "dropdown", key = "chain", label = "Crafted materials", onChange = function()
			ns.AltsCraft_Refresh()
		end, choices = function()
			return { { value = "full", text = "Full chain" }, { value = "one", text = "One step" } }
		end, tooltip = "How far the Crafting tab works out crafted materials: all the way down to what you gather, "
			.. "or only the recipe's own materials." },
		{ type = "header", label = "Send to alt" },
		{ type = "checkbox", key = "sendMail", label = "\"For your alts\" at the mailbox",
			tooltip = "Beside the mail frame: what you carry that another character crafts with (and you don't), grouped by who gets it. Attach fills the Send Mail tab, Send sends it (12 stacks a mail)." },
		{ type = "checkbox", key = "sendWarband", label = "\"Deposit for alts\" at the bank",
			tooltip = "At the bank, a button that puts those items into the Warband bank when they're allowed there." },
		{ type = "checkbox", key = "sendPlan", label = "Use the Crafting tab's plan",
			tooltip = "Materials for the recipe picked in the Crafting tab go to the character who crafts that step." },
		{ type = "input", key = "sendRules", label = "Always send", placeholder = "item ID or name = character, ...",
			tooltip = "Manual rules that win over the rest, e.g. \"210796 = Mira, mycobloom = Tolvan\". Separate them with commas." },
		{ type = "slider", key = "sendGold", label = "Keep gold on alts (thousands)", min = 0, max = 100, step = 1,
			format = function(v)
				return v == 0 and "off" or (v .. "k")
			end,
			tooltip = "At the mailbox, offer to top up characters below this much gold (from what you have above it). 0 = off." },
		{ type = "input", key = "sendSubject", label = "Mail subject", placeholder = "Tomte" },
		{ type = "header", label = "Crafting list" },
		{ type = "checkbox", key = "tracker.shown", label = "Craft tracker on screen", onChange = function()
			ns.AltsList_Refresh()
		end, tooltip = "The tracked crafts with what this character has to do for them: grab, mail, take from the Warband bank, buy, craft." },
		{ type = "dropdown", key = "tracker.mode", label = "Show the tracker", onChange = function()
			ns.AltsList_Refresh()
		end, choices = function()
			return { { value = "any", text = "While something is tracked" }, { value = "crafter", text = "Only on a crafter" } }
		end },
		{ type = "checkbox", key = "tracker.hideInCombat", label = "Hide the tracker in combat", onChange = function()
			ns.AltsList_Refresh()
		end },
		{ type = "checkbox", key = "tracker.locked", label = "Lock the tracker", onChange = function()
			ns.AltsList_Refresh()
		end, tooltip = "Unlocked, it shows (also when empty) and can be dragged." },
		{ type = "slider", key = "tracker.scale", label = "Tracker scale", min = 0.6, max = 1.6, step = 0.05,
			format = function(v)
				return ("%d%%"):format(v * 100 + 0.5)
			end, onChange = function()
				ns.AltsList_Refresh()
			end },
		{ type = "button", label = "Tracker position", text = "Reset", onClick = function()
			ns.AltsList_ResetPosition()
		end },
		{ type = "dropdown", key = "listDone", label = "Crafts come off the list", choices = function()
			return { { value = "auto", text = "When crafted" }, { value = "hand", text = "By hand" } }
		end, tooltip = "Each craft of a tracked recipe counts it down. When crafted: it leaves the list at 0." },
		{ type = "dropdown", key = "listMail", label = "Mail tracked crafts", choices = function()
			return { { value = "exact", text = "Exact amounts" }, { value = "stacks", text = "Whole stacks" } }
		end, tooltip = "Exact amounts split stacks so only what the craft needs is sent." },
		{ type = "checkbox", key = "listBaganator", label = "Mark items in Baganator", onChange = function()
			ns.AltsList_Changed()
		end, tooltip = "Items your to-do moves get a gold count on their icon in Baganator's bags and bank. In "
			.. "Baganator's settings (Icons), \"Tomte Crafting list\" has to be in a corner for it to show." },
		{ type = "checkbox", key = "listPrice", label = "Price missing materials", onChange = function()
			ns.AltsList_Changed()
		end, tooltip = "\"Get\" lines say what it costs (Gold & value)." },
	},
	commands = {
		{ "open", "open the Alts page", function()
			ns.Panel_OpenPage("alts")
		end },
		{ "forget", "forget a character: /tomte alts forget <name>", Forget },
		{ "why", "why Materials on hand keeps or drops a recipe: /tomte alts why <recipe>", function(text)
			ns.AltsCraft_Why(text)
		end },
		{ "list", "open the crafting list", function()
			db.view = "list"
			ns.Panel_OpenPage("alts")
			ns.Alts_ShowTab("list") -- the page may already be open on another tab (no OnShow then)
		end },
		{ "tracker", "show or hide the craft tracker", function()
			db.tracker.shown = not db.tracker.shown
			ns.AltsList_Refresh()
			ns.Print("craft tracker " .. (db.tracker.shown and "on." or "off."))
		end },
		{ "scan", "read the open profession window's recipes now (and say why not)", function()
			ns.AltsCollect_ScanNow()
		end },
	},
	fallbackCommand = { "", "open the Alts page", function()
		ns.Panel_OpenPage("alts")
	end, pattern = "^$" },
})
ns.altsModule = module
