local addonName, ns = ...

-- Friend crafting: the Crafting tab's "Friends who craft it" rows (in the selected recipe's detail, CraftDetail.lua)
-- and the small dialog that asks one of them for the craft: how many, and whether you mail the materials. The request
-- itself is sent by Friends.lua (ns.AltsFriends_Ask).

local ROW_H = 24
local HEADER_H = 26
local DIALOG_W, DIALOG_H = 360, 196
local MAX_AMOUNT = 200 -- as FriendsData.lua's MAX_AMOUNT

local UI = ns.UI
local ClassName = ns.AltsCraft_ClassName -- CraftTab.lua

local header
local rows = {}
local dialog

-- The dialog ----------------------------------------------------------------------------------------------------

local function SetAmount(n)
	dialog.amount = math.min(math.max(math.floor(n or 1), 1), MAX_AMOUNT)
	dialog.count:SetText(tostring(dialog.amount))
end

local function Build()
	dialog = UI.Dialog(nil, DIALOG_W, DIALOG_H)
	dialog.title = UI.Text(dialog, 16, "heading")
	dialog.title:SetPoint("TOPLEFT", 16, -14)
	dialog.title:SetPoint("RIGHT", -16, 0)
	dialog.title:SetWordWrap(false)
	dialog.recipe = UI.Text(dialog, 13, "text")
	dialog.recipe:SetPoint("TOPLEFT", dialog.title, "BOTTOMLEFT", 0, -8)
	dialog.recipe:SetPoint("RIGHT", -16, 0)
	dialog.recipe:SetWordWrap(false)

	local label = UI.Text(dialog, 12, "textMuted")
	label:SetPoint("TOPLEFT", dialog.recipe, "BOTTOMLEFT", 0, -16)
	label:SetText("How many")
	local minus = UI.Button(dialog, 22, "-")
	minus:SetHeight(22)
	minus:SetPoint("LEFT", label, "RIGHT", 12, 0)
	dialog.count = UI.Text(dialog, 13, "text", "number")
	dialog.count:SetPoint("LEFT", minus, "RIGHT", 6, 0)
	dialog.count:SetWidth(36)
	local plus = UI.Button(dialog, 22, "+")
	plus:SetHeight(22)
	plus:SetPoint("LEFT", dialog.count, "RIGHT", 6, 0)
	minus:SetScript("OnClick", function()
		SetAmount(dialog.amount - 1)
	end)
	plus:SetScript("OnClick", function()
		SetAmount(dialog.amount + 1)
	end)

	dialog.mats = UI.Segmented(dialog)
	dialog.mats:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 0, -16)
	dialog.mats.choices = function()
		return { { value = "mail", text = "I'll mail the materials" }, { value = "theirs", text = "Use your materials" } }
	end
	dialog.mats.getValue = function()
		return dialog.withMats and "mail" or "theirs"
	end
	dialog.mats.setValue = function(value)
		dialog.withMats = value == "mail"
		dialog.mats:Refresh()
	end

	local ask = UI.Button(dialog, 90, "Ask")
	ask:SetHeight(24)
	ask:SetPoint("BOTTOMRIGHT", -16, 14)
	ask:SetScript("OnClick", function()
		UI.Sound("confirm")
		ns.AltsFriends_Ask(dialog.crafter, dialog.recipeID, dialog.amount, dialog.withMats)
		dialog:Hide()
	end)
	local cancel = UI.Button(dialog, 90, CANCEL)
	cancel:SetHeight(24)
	cancel:SetPoint("RIGHT", ask, "LEFT", -8, 0)
	cancel:SetScript("OnClick", function()
		dialog:Hide()
	end)
end

-- Opens the ask dialog for a friend's character (a merged character: name, realm, friend = { tag, online }).
function ns.AltsAsk_Show(crafter, recipeID, recipe)
	if not dialog then
		Build()
	end
	UI.PlaceDialog(dialog)
	dialog.crafter, dialog.recipeID = crafter, recipeID
	dialog.title:SetText(("Ask %s to craft"):format(ClassName(crafter)))
	dialog.recipe:SetText(ns.AltsCraft_RecipeName(recipe))
	dialog.withMats = true
	SetAmount(1)
	dialog.mats:Refresh()
	dialog:Show()
end

-- The rows in the detail ------------------------------------------------------------------------------------------

local function Tip(row)
	GameTooltip:SetOwner(row.ask, "ANCHOR_RIGHT")
	GameTooltip:SetText(("Ask %s"):format(row.crafter.name or "?"), 1, 1, 1)
	GameTooltip:AddLine(row.crafter.friend.online and "They're online: they get it right away."
		or "They're offline: the request waits and goes out the next time you're both online. You can mail the "
		.. "materials now.", nil, nil, nil, true)
	GameTooltip:Show()
end

local function CreateRow(parent)
	local row = CreateFrame("Frame", nil, parent)
	row:SetHeight(ROW_H)
	row.name = UI.Text(row, 12, "text")
	row.name:SetPoint("LEFT", 4, 0)
	row.ask = UI.Button(row, 70, "Ask")
	row.ask:SetHeight(20)
	row.ask:SetPoint("RIGHT", -4, 0)
	row.name:SetPoint("RIGHT", row.ask, "LEFT", -8, 0)
	row.name:SetWordWrap(false)
	row.ask:SetScript("OnClick", function()
		ns.AltsAsk_Show(row.crafter, row.recipeID, row.recipe)
	end)
	row.ask:HookScript("OnEnter", function()
		Tip(row)
	end)
	row.ask:HookScript("OnLeave", GameTooltip_Hide)
	return row
end

-- Draws "Friends who craft it" at y in the detail's content for the friends' characters among who (the recipe's
-- crafters, merged), each with Ask. Returns the y below them (y unchanged when no friend knows it).
function ns.AltsAsk_DrawFriends(content, y, who, recipeID)
	for _, row in ipairs(rows) do
		row:Hide()
	end
	if header then
		header:Hide()
	end
	local friends = {}
	for _, c in ipairs(who) do
		if c.friend then
			friends[#friends + 1] = c
		end
	end
	if #friends == 0 then
		return y
	end
	table.sort(friends, function(a, b)
		if a.friend.online ~= b.friend.online then
			return a.friend.online
		end
		return (a.name or "") < (b.name or "")
	end)
	header = header or UI.Text(content, 11, "textMuted")
	header:SetText("Friends who craft it")
	header:ClearAllPoints()
	header:SetPoint("TOPLEFT", 4, -(y + 10))
	header:Show()
	y = y + HEADER_H
	local _, recipes = ns.AltsFriends_Merged(ns.altsDB.chars, ns.altsDB.recipes)
	for i, c in ipairs(friends) do
		local row = rows[i] or CreateRow(content)
		rows[i] = row
		row.crafter, row.recipeID, row.recipe = c, recipeID, recipes[recipeID]
		-- Offline: when their recipes last arrived, the last time we know they were on.
		local seen = not c.friend.online and c.friend.seen
			and UI.Wrap(("seen %s"):format(ns.AgoText(time() - c.friend.seen)), "textFaint")
		row.name:SetText(ClassName(c) .. (seen and ("  " .. seen) or ""))
		row:ClearAllPoints()
		row:SetPoint("TOPLEFT", 0, -y)
		row:SetPoint("RIGHT")
		row:Show()
		y = y + ROW_H
	end
	return y + 4
end
