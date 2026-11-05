local addonName, ns = ...

-- Trading Post: a "Buy what you can afford" button in Blizzard's Trading Post window, next to Leave. It opens a list
-- of everything you don't have, cheapest first, with what your Tender covers ticked; a click on an item leaves it
-- out or picks it instead, and Buy sends the ticked ones to the server as one cart (C_PerksProgram.RequestCartCheckout,
-- what Blizzard's own cart does). The plan is ns.TradingPost_BuyPlan (Data.lua); refreshed from TradingPost.lua.

local WIDTH = 440
local PAD = 18
local LIST_ROWS = 10 -- rows shown before the list scrolls
local CHECK_W = 24 -- the tick box column left of each row's icon
local BUTTON_H = 32
local BUTTON_GAP = 16 -- between Blizzard's Leave button and ours

local UI = ns.UI
local Kit = ns.HomeKit

local button, dialog
local rows = {}
local choice = {} -- [perksVendorItemID] = "skip" | "want", the clicks in the list, kept while the vendor is open
local plan

local function Plan()
	local shop = ns.TradingPost_Shop()
	return ns.TradingPost_BuyPlan(shop and shop.items, ns.TradingPost_State().tender, choice)
end

-- Blizzard's window ignores UIParent's scale: ours match the rest of Tomte's.
local function MatchScale(frame)
	frame:SetIgnoreParentScale(true)
	frame:SetScale(UIParent:GetEffectiveScale())
end

-- The list --------------------------------------------------------------------------------------------------------

local function Toggle(it)
	if plan.chosen[it] then
		choice[it.id] = "skip"
	elseif (it.price or 0) <= ns.TradingPost_State().tender then
		choice[it.id] = "want"
	else
		return
	end
	UI.Sound(choice[it.id] == "want" and "on" or "off")
	ns.TradingPostBuy_Refresh()
end

local function RowTooltip(row, it)
	GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
	if it.itemID and it.itemID > 0 then
		GameTooltip:SetItemByID(it.itemID)
	else
		GameTooltip:SetText(it.name, UI.Color("heading"))
	end
	GameTooltip:AddLine(" ")
	GameTooltip:AddLine(("%s · %s Tender"):format(ns.TradingPost_CategoryWord(it.category), ns.Thousands(it.price)),
		UI.RGB("textMuted"))
	if plan.chosen[it] then
		UI.TipLine("Click: leave it out", "accent")
	elseif (it.price or 0) > ns.TradingPost_State().tender then
		UI.TipLine("Costs more than your Tender", "warning")
	else
		UI.TipLine("Click: buy this one, cheaper ones make room", "accent")
	end
	GameTooltip:Show()
end

local function Row(i)
	local row = Kit.PoolRow(rows, i, dialog.scroll.content)
	if not row.check then
		row.check = UI.Checkbox(row)
		row.check:SetPoint("RIGHT", row, "LEFT", -6, 0)
	end
	return row
end

local function Render()
	plan = Plan()
	local s = ns.TradingPost_State()
	local width = dialog.scroll:GetWidth()
	for i, it in ipairs(plan.list) do
		local row = Row(i)
		local on = plan.chosen[it]
		local fits = (it.price or 0) <= s.tender
		row:Set(it.icon, it.name, on and "text" or "textFaint", ns.Thousands(it.price),
			on and "accent" or (fits and "textMuted" or "textFaint"))
		row:SetPoint("TOPLEFT", CHECK_W, -(i - 1) * Kit.ROW_H)
		row:SetWidth(math.max(width - CHECK_W - 10, 1))
		row.check:SetChecked(on)
		row.check:SetEnabled(on or fits)
		row.check:SetScript("OnClick", function()
			Toggle(it)
		end)
		row.onClick = function()
			Toggle(it)
		end
		row.onEnter = function(self)
			RowTooltip(self, it)
		end
	end
	Kit.HideFrom(rows, #plan.list + 1)
	dialog.scroll:SetContentHeight(#plan.list * Kit.ROW_H)

	local n = #plan.picked
	dialog.summary:SetText(("%d of the %d you don't have, for %s of your %s Tender"):format(n, #plan.list,
		ns.Thousands(plan.total), ns.Thousands(s.tender)))
	dialog.buy.label:SetText(n > 0 and ("Buy %d"):format(n) or "Nothing to buy")
	UI.FitButton(dialog.buy, 90, 24)
	dialog.buy:SetEnabled(n > 0)
	dialog.buy:SetAlpha(n > 0 and 1 or 0.4)
end

local function Close()
	if dialog and dialog:IsShown() then
		dialog:Hide()
	end
end

local function Buy()
	local ids = {}
	for i, it in ipairs(plan.picked) do
		ids[i] = it.id
	end
	if #ids == 0 then
		return
	end
	UI.Sound("confirm")
	ns.Print(("buying %d %s for %s Trader's Tender."):format(#ids, #ids == 1 and "item" or "items",
		ns.Thousands(plan.total)))
	C_PerksProgram.RequestCartCheckout(ids) -- in a click: a hardware event
	Close()
end

local function BuildDialog()
	dialog = UI.Dialog(nil, WIDTH, nil, { parent = PerksProgramFrame, escape = false })
	dialog:SetFrameStrata("FULLSCREEN_DIALOG")
	dialog.title = UI.Text(dialog, 15, "heading", "title")
	dialog.title:SetPoint("TOPLEFT", PAD, -PAD)
	dialog.title:SetText("Buy what your Tender covers")
	dialog.summary = UI.Text(dialog, 12, "textMuted")
	dialog.summary:SetPoint("TOPLEFT", dialog.title, "BOTTOMLEFT", 0, -6)
	dialog.hint = UI.Text(dialog, 11, "textFaint")
	dialog.hint:SetPoint("TOPLEFT", dialog.summary, "BOTTOMLEFT", 0, -4)
	dialog.hint:SetWidth(WIDTH - 2 * PAD)
	dialog.hint:SetJustifyH("LEFT")
	dialog.hint:SetText("Cheapest first. Click an item to leave it out, or to buy it instead of cheaper ones.")
	dialog.scroll = UI.Scroll(dialog)
	dialog.scroll:SetPoint("TOPLEFT", dialog.hint, "BOTTOMLEFT", 0, -12)
	dialog.scroll:SetSize(WIDTH - 2 * PAD, LIST_ROWS * Kit.ROW_H)
	dialog.cancel = UI.Button(dialog, 90, CANCEL)
	dialog.cancel:SetHeight(24)
	dialog.cancel:SetPoint("BOTTOMRIGHT", -PAD, 14)
	dialog.cancel:SetScript("OnClick", function()
		UI.Sound("close")
		Close()
	end)
	dialog.buy = UI.Button(dialog, 90, "Buy")
	dialog.buy:SetHeight(24)
	dialog.buy:SetPoint("RIGHT", dialog.cancel, "LEFT", -8, 0)
	dialog.buy:SetScript("OnClick", Buy)
	dialog:SetHeight(PAD + 15 + 6 + 12 + 4 + 11 + 12 + LIST_ROWS * Kit.ROW_H + 16 + 24 + 14)
	-- Esc closes the list, not the Trading Post under it; other keys go on to Blizzard's window. Keyboard input
	-- can't be claimed in combat (Panel/Confirm.lua does the same).
	dialog:SetScript("OnKeyDown", function(self, key)
		if InCombatLockdown() then
			return
		end
		self:SetPropagateKeyboardInput(key ~= "ESCAPE")
		if key == "ESCAPE" then
			Close()
		end
	end)
end

local function Open()
	if not dialog then
		BuildDialog()
	end
	MatchScale(dialog)
	dialog:Show()
	dialog:Raise()
	if not InCombatLockdown() then
		dialog:EnableKeyboard(true)
		dialog:SetPropagateKeyboardInput(true)
	end
	Render()
end

-- The button ------------------------------------------------------------------------------------------------------

local function BuildButton()
	local leave = PerksProgramFrame.FooterFrame.LeaveButton
	button = UI.Button(PerksProgramFrame.FooterFrame, 200, "")
	button:SetHeight(BUTTON_H)
	button:SetFrameLevel(leave:GetFrameLevel())
	button:SetPoint("LEFT", leave, "RIGHT", BUTTON_GAP, 0)
	button:SetScript("OnClick", function()
		UI.Sound("open")
		Open()
	end)
	local enter = button:GetScript("OnEnter")
	button:SetScript("OnEnter", function(self)
		enter(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:SetText("Tomte: buy what you can afford", UI.Color("heading"))
		UI.TipLine("Lists what you don't have, cheapest first, with what your Tender covers ticked. You choose, then "
			.. "buy them all in one go.", "textMuted", true)
		GameTooltip:Show()
	end)
	local leaveScript = button:GetScript("OnLeave")
	button:SetScript("OnLeave", function(self)
		leaveScript(self)
		GameTooltip:Hide()
	end)
end

-- After every read (TradingPost.lua): the button's count, and the list if it's open.
function ns.TradingPostBuy_Refresh()
	if not (ns.TradingPost_AtVendor() and PerksProgramFrame and PerksProgramFrame:IsShown()) then
		wipe(choice)
		Close()
		if button then
			button:Hide()
		end
		return
	end
	if not button then
		BuildButton()
	end
	plan = Plan()
	local n = #plan.picked
	button.label:SetText(("Buy %d you can afford"):format(n))
	UI.FitButton(button, 200, 32)
	MatchScale(button)
	button:SetShown(n > 0 or (dialog and dialog:IsShown()))
	if dialog and dialog:IsShown() then
		Render()
	end
end

function ns.TradingPostBuy_Stop()
	wipe(choice)
	Close()
	if button then
		button:Hide()
	end
end
