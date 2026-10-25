local addonName, ns = ...

-- Options for the panel's module page, built from a module's options schema as cards: each `header` row starts a
-- card (rows before the first header share an untitled one), dealt into one or two columns by width (Layout.lua).
-- The rows come from OptionRows.lua; cards are pooled and rebuilt per module. The reset buttons sit under the cards
-- as quiet links. Schema extras read here: parent = "<key>" (indented and dimmed while that option is off), shown()
-- (hides the row; re-checked after every change on the page).

local UI = ns.UI
local CARD_TITLE_H = 30
local CARD_PAD = 8 -- above the first row of an untitled card and under the last row
local CARD_INSET = 6 -- row edges inside a card
local INDENT = 16 -- rows with a parent
local GAP = 14 -- between cards and columns
local MIN_COLUMN = 360 -- narrowest card in two columns: a long label beside a 150 px control
local MAX_CARD = 540 -- widest card: past this a switch ends up far from its label
local FOOTER_H = 34
local DIMMED = 0.45

local parent -- the options scroll's content frame
local scrollFrame
local used = {}
local cardPool, cards = {}, {}
local links = {}
local builtFor -- module whose options are built
local builtVisibility -- ns.PanelLayout_Visibility of builtFor's options when they were built

local function IsParent(module, key)
	for _, spec in ipairs(module.options or {}) do
		if spec.parent == key then
			return true
		end
	end
	return false
end

-- Rebuilds module's options when rows hang on what just changed: a parent option (rows dim or light up) or a shown()
-- that answers differently now. After the switch has finished sliding: a rebuild would cut its animation short.
local function RebuildIfChanged(module, key)
	if builtFor ~= module or not scrollFrame then
		return
	end
	if not (key and IsParent(module, key)) and ns.PanelLayout_Visibility(module.options) == builtVisibility then
		return
	end
	local scroll = scrollFrame
	C_Timer.After(UI.SWITCH_SECONDS, function()
		if builtFor == module and scroll:IsVisible() then
			ns.PanelOptions_Build(scroll, module)
		end
	end)
end
ns.OptionRows_OnChange(RebuildIfChanged)

local function HideTooltip()
	GameTooltip:Hide()
end

-- Cards -------------------------------------------------------------------------------------------------------

local function AcquireCard()
	local card = table.remove(cardPool)
	if not card then
		card = CreateFrame("Frame", nil, parent)
		UI.Surface(card, 0.35)
		card.title = UI.Text(card, 11, "accent", "label")
		card.title:SetPoint("TOPLEFT", 14, -11)
		card.title:SetPoint("RIGHT", -14, 0)
		card.title:SetWordWrap(false)
	end
	card:Show()
	cards[#cards + 1] = card
	return card
end

-- Reset links under the cards ---------------------------------------------------------------------------------

local function Link(i)
	local b = links[i]
	if b then
		return b
	end
	b = CreateFrame("Button", nil, parent)
	b:SetHeight(18)
	b.text = UI.Text(b, 12, "textMuted")
	b.text:SetPoint("RIGHT")
	b.line = b:CreateTexture(nil, "ARTWORK")
	b.line:SetColorTexture(UI.Color("textFaint"))
	b.line:SetHeight(1)
	b.line:SetPoint("TOPLEFT", b.text, "BOTTOMLEFT", 0, -1)
	b.line:SetPoint("TOPRIGHT", b.text, "BOTTOMRIGHT", 0, -1)
	b:SetScript("OnEnter", function(self)
		UI.SetTextRole(self.text, "accent")
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:SetText(self.spec.label, 1, 1, 1)
		GameTooltip:AddLine(self.spec.tooltip, nil, nil, nil, true)
		GameTooltip:Show()
	end)
	b:SetScript("OnLeave", function(self)
		UI.SetTextRole(self.text, "textMuted")
		HideTooltip()
	end)
	b:SetScript("OnClick", function(self)
		ns.Confirm_Show(self.spec.confirm, self.spec.onClick)
	end)
	links[i] = b
	return b
end

-- Reset links under every module's own options. Both reload the UI: modules keep state in closures.
local function ResetSpecs(module)
	local specs = {}
	if not module.defaults then
		return specs
	end
	local kept = "\n\nKept: what Tomte collected (history, alt data, flight times, tame log, caches) and lists you "
		.. "built (favorites, pins, hidden entries). Your UI reloads."
	specs[1] = { label = "Reset " .. module.name .. " to defaults",
		confirm = "Reset " .. module.name .. "'s settings to their defaults?" .. kept,
		onClick = function()
			ns.ResetModuleSettings(module)
			C_UI.Reload() -- needs a hardware event: the popup's Yes click is one
		end,
		tooltip = "Puts this module's settings back to how they start. Collected data and your lists stay." }
	if module.key == "window" then -- the Tomte window's page is the general one
		specs[2] = { label = "Reset all Tomte settings",
			confirm = "Reset every Tomte setting to its default, including which modules are on and where the window "
				.. "sits?" .. kept,
			onClick = function()
				ns.ResetAll()
				C_UI.Reload() -- needs a hardware event: the popup's Yes click is one
			end,
			tooltip = "Every module's settings, which modules are on, and the window's size and place back to "
				.. "defaults. Collected data and your lists stay." }
	end
	return specs
end

-- Layout ------------------------------------------------------------------------------------------------------

local shownLinks = 0

-- The cards a module's options make: a header starts one, rows before the first header get an untitled one, and a
-- section whose rows are all hidden (shown()) makes none. { title, specs }
local function Sections(module)
	local sections, section = {}, nil
	for _, spec in ipairs(module.options or {}) do
		if not spec.shown or spec.shown() then -- shown: optional function, false hides the row for now
			if spec.type == "header" then
				section = { title = spec.label, specs = {} }
				sections[#sections + 1] = section
			else
				if not section then
					section = { specs = {} }
					sections[#sections + 1] = section
				end
				section.specs[#section.specs + 1] = spec
			end
		end
	end
	local cardsOnly = {}
	for _, sec in ipairs(sections) do
		if #sec.specs > 0 then
			cardsOnly[#cardsOnly + 1] = sec
		end
	end
	return cardsOnly
end

-- How wide module's cards end up in width (the header lines its switch up with their right edge).
function ns.PanelOptions_Width(module, width)
	local count = #Sections(module)
	if count == 0 then
		return width
	end
	local _, _, cardsW = ns.PanelLayout_Cards(width, GAP, MIN_COLUMN, MAX_CARD, count)
	return cardsW
end

-- Places the built cards for the content width and sizes the scroll content.
local function Layout(width)
	if #cards == 0 and shownLinks == 0 then
		scrollFrame:SetContentHeight(1) -- every row hidden for now: no leftover height from the last module
		return
	end
	local columns, cardW, cardsW = ns.PanelLayout_Cards(width, GAP, MIN_COLUMN, MAX_CARD, #cards)
	local heights = {}
	for i, card in ipairs(cards) do
		heights[i] = card.height
	end
	local places, total = ns.PanelLayout_Deal(heights, columns, GAP)
	for i, card in ipairs(cards) do
		local place = places[i]
		card:ClearAllPoints()
		card:SetPoint("TOPLEFT", parent, "TOPLEFT", (place.column - 1) * (cardW + GAP), -place.y)
		card:SetWidth(cardW)
	end
	-- The links end at the cards' right edge.
	local x = 0
	for i = shownLinks, 1, -1 do
		local b = links[i]
		b:ClearAllPoints()
		b:SetPoint("TOPRIGHT", parent, "TOPLEFT", (#cards > 0 and cardsW or width) - x - 4, -(total + 12))
		x = x + b:GetWidth() + 20
	end
	scrollFrame:SetContentHeight(total + (shownLinks > 0 and FOOTER_H or 8))
end

function ns.PanelOptions_Release()
	-- Taken out of `used` first: hiding a focused input saves it, and that save can rebuild the options from inside
	-- this loop (a parent option, an onChange that refreshes the panel).
	local released = used
	used = {}
	for _, row in ipairs(released) do
		ns.OptionRows_Release(row)
		row:SetParent(parent)
	end
	local releasedCards = cards
	cards = {}
	for _, card in ipairs(releasedCards) do
		card:Hide()
		card:ClearAllPoints()
		cardPool[#cardPool + 1] = card
	end
	for _, b in ipairs(links) do
		b:Hide()
	end
	shownLinks = 0
end

local Build -- forward declaration
local building = false

-- Builds module's options into scroll.content (a UI.Scroll). Rebuilding the same module keeps the scroll offset.
function ns.PanelOptions_Build(scroll, module)
	if building then
		-- Asked again from inside a build (an input saving as it's hidden): once this one is done.
		C_Timer.After(0, function()
			if not building and builtFor == module and scroll:IsVisible() then
				ns.PanelOptions_Build(scroll, module)
			end
		end)
		return
	end
	building = true
	-- An error in a module's choices() or label() still reaches BugSack, and the guard comes off either way.
	xpcall(Build, ns.errorHandler, scroll, module)
	building = false
end

function Build(scroll, module)
	parent = scroll.content
	scrollFrame = scroll
	local keepScroll = builtFor == module and scroll:GetVerticalScroll() or 0
	ns.PanelOptions_Release()
	builtFor = module
	builtVisibility = ns.PanelLayout_Visibility(module.options)

	for _, sec in ipairs(Sections(module)) do
		local card = AcquireCard()
		card.title:SetText(sec.title and sec.title:upper() or "")
		card.title:SetShown(sec.title ~= nil)
		local y = sec.title and CARD_TITLE_H or CARD_PAD
		for i, spec in ipairs(sec.specs) do
			local row = ns.OptionRows_Acquire(spec.type, card)
			used[#used + 1] = row
			local indent = spec.parent and INDENT or 0
			row:SetPoint("TOPLEFT", card, "TOPLEFT", CARD_INSET + indent, -y)
			row:SetPoint("RIGHT", card, "RIGHT", -CARD_INSET, 0)
			row.rule:SetShown(i > 1 and not spec.parent)
			row:SetAlpha(spec.parent and not ns.OptionRows_Get(module, spec.parent) and DIMMED or 1)
			ns.OptionRows_Setup(row, module, spec)
			y = y + row:GetHeight()
		end
		card.height = y + CARD_PAD
		card:SetHeight(card.height)
	end

	for i, spec in ipairs(ResetSpecs(module)) do
		local b = Link(i)
		b.spec = spec
		b.text:SetText(spec.label)
		b:SetWidth(b.text:GetStringWidth())
		b:Show()
		shownLinks = i
	end

	scroll.onWidthChanged = Layout
	Layout(scroll:GetWidth())
	scroll:SetScroll(keepScroll)
end
