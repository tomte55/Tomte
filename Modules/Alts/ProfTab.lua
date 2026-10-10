local addonName, ns = ...

-- Alts page, Profession gear tab: each character's tool and accessories per profession (item level, from what was
-- worn when they were last played) and the best tool or accessory somebody can craft for each, when it's an upgrade.
-- Click a profession to open that craft in the Crafting tab. Logic in ProfGear.lua and Data.lua.

local UI = ns.UI
local CHAR_H, PROF_H = 26, 40
local function None() -- built when used: the theme is chosen on ADDON_LOADED
	return UI.Wrap("none", "textFaint")
end

local tab, db
local charRows, profRows = {}, {}

local function ClassName(c)
	local color = c.class and C_ClassColor.GetClassColor(c.class)
	return color and color:WrapTextInColorCode(c.name or "?") or (c.name or "?")
end

-- "[Name] 590" with the item's link (rarity color), "..." while its item level loads.
local function ItemText(w)
	return ("%s %s"):format(w.link, UI.Wrap(w.ilvl and tostring(w.ilvl) or "...", "text"))
end

local function WornText(worn, base)
	local tool, accs = nil, {}
	for _, w in ipairs(worn) do
		if w.base == base then
			if w.kind == "tool" then
				tool = w
			else
				accs[#accs + 1] = w
			end
		end
	end
	local parts = { UI.Wrap("Tool", "textMuted") .. " " .. (tool and ItemText(tool) or None()) }
	local slots = ns.Alts_ProfSlots(base, "acc")
	local accTexts = {}
	for i = 1, slots do
		accTexts[i] = accs[i] and ItemText(accs[i]) or None()
	end
	parts[2] = ("%s %s"):format(UI.Wrap(slots == 1 and "Accessory" or "Accessories", "textMuted"), table.concat(accTexts, ", "))
	return table.concat(parts, "     "), tool, accs
end

local function RecipeText(id, best)
	local recipe = db.recipes[id]
	local _, who = ns.Alts_RecipeStatus(db.chars, recipe, id)
	local gain = best.mark == "empty" and "free slot" or best.mark == "sure" and ("+%d"):format(best.gain)
		or ("up to +%d"):format(best.gain)
	local role = best.mark == "top" and "warning" or "success"
	local by = who and who[1] and (" by " .. (who[1].name or "?")) or ""
	return ("%s %s%s"):format(recipe.name or "?", UI.Wrap("(" .. gain .. ")", role), by ~= "" and UI.Wrap(by, "textMuted") or "")
end

local function CreateCharRow(parent)
	local row = CreateFrame("Frame", nil, parent)
	row:SetHeight(CHAR_H)
	row.name = UI.Text(row, 13, "text")
	row.name:SetPoint("BOTTOMLEFT", 4, 4)
	row.note = UI.Text(row, 11, "textMuted")
	row.note:SetPoint("LEFT", row.name, "RIGHT", 10, 0)
	row.line = row:CreateTexture(nil, "ARTWORK")
	row.line:SetColorTexture(UI.RGBA("frame", 0.2))
	row.line:SetHeight(1)
	row.line:SetPoint("BOTTOMLEFT")
	row.line:SetPoint("BOTTOMRIGHT")
	return row
end

local function ShowProfTooltip(row)
	local c, base = row.char, row.base
	GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
	GameTooltip:SetText(("%s · %s"):format(c.name or "?", row.profName), 1, 1, 1)
	local tr, tg, tb = UI.Color("text")
	for _, w in ipairs(row.items) do
		GameTooltip:AddLine(" ")
		GameTooltip:AddDoubleLine(w.link, w.ilvl and ("item level %d"):format(w.ilvl) or "loading", 1, 1, 1, 1, 1, 1)
		for _, line in ipairs(ns.AltsItem_StatLines(w.link)) do
			GameTooltip:AddLine("   " .. line, tr, tg, tb)
		end
	end
	for _, b in ipairs(row.best) do
		local recipe = db.recipes[b.best.recipeID]
		GameTooltip:AddLine(" ")
		local hr, hg, hb = UI.Color("heading")
		GameTooltip:AddLine(("Better %s: %s"):format(b.kind == "tool" and "tool" or "accessory", recipe.name or "?"), hr, hg, hb)
		local ilvl = b.best.quality and ("Item level %d at quality %d"):format(b.best.hi, b.best.quality)
			or ("Item level %d-%d by quality"):format(b.best.lo, b.best.hi)
		GameTooltip:AddLine(("%s: %s."):format(ilvl, ns.AltsProf_UpgradeText(b.best)), 1, 1, 1, true)
		local _, link = ns.Alts_QualityLinks(recipe, b.best.quality)
		for _, line in ipairs(ns.AltsItem_StatLines(link)) do
			GameTooltip:AddLine("   " .. line .. (b.best.quality and "" or " (highest quality)"), tr, tg, tb)
		end
	end
	GameTooltip:AddLine(" ")
	local mr, mg, mb = UI.Color("textMuted")
	GameTooltip:AddLine("Item level only: the stats are shown, not compared. Optional reagents can raise a craft's item level.",
		mr, mg, mb, true)
	if #row.best > 0 then
		GameTooltip:AddLine("Click: open it in the Crafting tab", mr, mg, mb)
	end
	GameTooltip:Show()
end

local function CreateProfRow(parent)
	local row = CreateFrame("Button", nil, parent)
	row:SetHeight(PROF_H)
	row.bg = row:CreateTexture(nil, "BACKGROUND")
	row.bg:SetAllPoints()
	row.bg:SetColorTexture(UI.Color("hover"))
	row.bg:Hide()
	row.icon = row:CreateTexture(nil, "ARTWORK")
	row.icon:SetSize(16, 16)
	row.icon:SetPoint("TOPLEFT", 14, -4)
	row.prof = UI.Text(row, 12, "heading")
	row.prof:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
	row.prof:SetWidth(110)
	row.prof:SetWordWrap(false)
	row.gear = UI.Text(row, 12, "text")
	row.gear:SetPoint("LEFT", row.prof, "RIGHT", 8, 0)
	row.gear:SetPoint("RIGHT", -6, 0)
	row.gear:SetWordWrap(false)
	row.better = UI.Text(row, 11, "textMuted")
	row.better:SetPoint("TOPLEFT", row.gear, "BOTTOMLEFT", 0, -5)
	row.better:SetPoint("RIGHT", -6, 0)
	row.better:SetWordWrap(false)
	row:SetScript("OnEnter", function(self)
		self.bg:Show()
		ShowProfTooltip(self)
	end)
	row:SetScript("OnLeave", function(self)
		self.bg:Hide()
		GameTooltip:Hide()
	end)
	row:SetScript("OnClick", function(self)
		local first = self.best[1]
		if first then
			PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
			ns.AltsCraft_Open(first.best.recipeID, self.char.guid == UnitGUID("player") and "me" or self.char.guid)
		end
	end)
	return row
end

-- A character's professions with gear slots, by name (main ones first).
local function GearProfs(c)
	local list = {}
	for _, secondary in ipairs({ false, true }) do
		for _, prof in ipairs(ns.Alts_Profs(c, secondary)) do
			if ns.Alts_ProfSlots(prof.base, "tool") > 0 then
				list[#list + 1] = prof
			end
		end
	end
	return list
end

local function Layout()
	local content = tab.scroll.content
	local y, nChar, nProf = 0, 0, 0
	for _, c in ipairs(ns.Alts_Roster(db.chars, "name", UnitGUID("player"))) do
		local profs = GearProfs(c)
		if #profs > 0 then
			nChar = nChar + 1
			local row = charRows[nChar] or CreateCharRow(content)
			charRows[nChar] = row
			row.name:SetText(ClassName(c))
			row.note:SetText(c.profGear and "" or "profession gear not read yet: log in on them once")
			row:ClearAllPoints()
			row:SetPoint("TOPLEFT", 0, -y)
			row:SetPoint("RIGHT")
			row:Show()
			y = y + CHAR_H + 2
			local worn = c.profGear and ns.AltsProf_Worn(c) or {}
			for _, prof in ipairs(profs) do
				nProf = nProf + 1
				local pr = profRows[nProf] or CreateProfRow(content)
				profRows[nProf] = pr
				pr.char, pr.base, pr.profName = c, prof.base, prof.name or "?"
				pr.icon:SetTexture(prof.icon or 134400)
				pr.prof:SetText(prof.name or "?")
				local text, tool, accs = WornText(worn, prof.base)
				pr.gear:SetText(c.profGear and text or UI.Wrap("-", "textFaint"))
				pr.best = {}
				local parts = {}
				for _, kind in ipairs({ "tool", "acc" }) do
					local best = c.profGear and ns.AltsProf_BestCraft(c, prof.base, kind)
					if best then
						pr.best[#pr.best + 1] = { kind = kind, best = best }
						parts[#parts + 1] = ("%s: %s"):format(kind == "tool" and "Tool" or "Accessory", RecipeText(best.recipeID, best))
					end
				end
				pr.better:SetText(#parts > 0 and ("Craft a better one: " .. table.concat(parts, "   ·   "))
					or (c.profGear and UI.Wrap("Nothing better that anyone can craft", "textFaint") or ""))
				local items = {}
				if tool then
					items[1] = tool
				end
				for _, a in ipairs(accs) do
					items[#items + 1] = a
				end
				pr.items = items
				pr:ClearAllPoints()
				pr:SetPoint("TOPLEFT", 0, -y)
				pr:SetPoint("RIGHT")
				pr:Show()
				y = y + PROF_H
			end
			y = y + 8
		end
	end
	for i = nChar + 1, #charRows do
		charRows[i]:Hide()
	end
	for i = nProf + 1, #profRows do
		profRows[i]:Hide()
	end
	tab.scroll:SetContentHeight(y)
	tab.hint:SetShown(nChar == 0)
end

function ns.AltsProfTab_Create(frame, altsDB)
	tab, db = frame, altsDB
	-- Compare at: the "Compare crafted gear at" setting.
	tab.quality = UI.Dropdown(tab, 180)
	tab.quality:SetPoint("TOPRIGHT", -8, -4)
	tab.quality.getValue = function()
		return db.gearQuality
	end
	tab.quality.setValue = function(value)
		db.gearQuality = value
		ns.Alts_GearQualityChanged()
	end
	tab.quality.choices = ns.Alts_GearQualityChoices
	tab.quality:HookScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText("Compare crafted gear at")
		GameTooltip:AddLine("The crafting quality you expect to make. Every quality shows the range: green is an upgrade "
			.. "even at the lowest, yellow only at the higher ones. Also the \"Gear for\" marks and Next up.", 1, 1, 1, true)
		GameTooltip:Show()
	end)
	tab.quality:HookScript("OnLeave", GameTooltip_Hide)
	tab.qualityLabel = UI.Text(tab, 12, "textMuted")
	tab.qualityLabel:SetPoint("RIGHT", tab.quality, "LEFT", -8, 0)
	tab.qualityLabel:SetText("Compare crafts at")
	tab.scroll = UI.Scroll(tab)
	tab.scroll:SetPoint("TOPLEFT", 0, -32)
	tab.scroll:SetPoint("BOTTOMRIGHT", -8, 0)
	tab.hint = UI.Text(tab, 12, "textMuted")
	tab.hint:SetPoint("TOPLEFT", 4, -36)
	tab.hint:SetPoint("RIGHT", -8, 0)
	tab.hint:SetWordWrap(true)
	tab.hint:SetText("No character with a profession yet. Log in on each one once; Tomte reads their professions and the "
		.. "tool and accessories they wear.")
end

function ns.AltsProfTab_Refresh()
	if tab and tab:IsVisible() then
		tab.quality:Refresh()
		Layout()
	end
end
