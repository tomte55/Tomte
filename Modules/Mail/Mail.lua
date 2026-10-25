local addonName, ns = ...

-- Mail: an "Open all" button on the inbox that takes gold and items letter by letter (never cash on delivery or GM
-- letters, gold only with Shift, Auction House letters only as a setting, gold still taken when the bags are full)
-- and ends with a summary: gold and Auction House sold/won/expired/cancelled/outbid letters, in chat, as a card and
-- in the session recap. On the Send tab, a button next to the To box picks one of your characters or someone you
-- mailed lately. Blizzard's mail frames are hooked, never replaced: while the module is on, Tomte's button stands in
-- for Blizzard's Open All, which comes back when it's off. Pure rules in Data.lua.

local OWNER = "mail"
local ICON = 133471 -- inv_letter_15
-- Seconds between takes, and how often the run looks again: Blizzard's own Open All (MailFrame.lua,
-- OPEN_ALL_MAIL_MIN_DELAY) waits 0.15 s and then for C_Mail.IsCommandPending to clear.
local MIN_DELAY = 0.15
local TICK = 0.15
-- Seconds to wait for more letters when the server holds more than the inbox shows: Blizzard's mail frame checks
-- again at most once a minute (C_Mail.CanCheckInbox) once the inbox has room.
local MAX_WAIT = 70
local INBOX_MAX = 50 -- letters the inbox shows at once (MAX_INBOX_SIZE in MailFrame.lua)
local STUCK_TRIES = 5 -- the same take sent this often without the inbox changing: skip it
local RECENT_MAX = 5 -- recipients remembered per character
local ATTACH_MAX = 16 -- ATTACHMENTS_MAX_RECEIVE
-- The summary card's settings preview: a made-up run (money in copper, letters by kind, as ns.Mail_Summary takes).
local SAMPLE_RUN = { money = 48215000, opened = { sold = 9, won = 2, expired = 1 }, left = 0, cod = 0 }
local UI = ns.UI

local module, db
local openButton, picker, hidBlizzard
local run -- while Open all runs: see Start
local patterns
local sentTo -- the recipient of the mail on its way, until MAIL_SEND_SUCCESS or MAIL_FAILED

local function MailOpen()
	return MailFrame and MailFrame:IsShown()
end

local function CharDB()
	local guid = UnitGUID("player")
	local char = db.chars[guid]
	if not char then
		char = { recent = {} }
		db.chars[guid] = char
	end
	return char
end

-- What the picker needs to offer this character on your other characters.
local function RecordMe()
	local char = CharDB()
	char.name = UnitName("player")
	char.realm = GetNormalizedRealmName() or char.realm
	char.faction = UnitFactionGroup("player") or char.faction
	char.class = select(2, UnitClass("player"))
end

-- Reading the inbox -------------------------------------------------------------------------------------------

local function Patterns()
	patterns = patterns or ns.Mail_SubjectPatterns({
		expired = AUCTION_EXPIRED_MAIL_SUBJECT,
		cancelled = AUCTION_REMOVED_MAIL_SUBJECT,
		outbid = AUCTION_OUTBID_MAIL_SUBJECT,
		sold = AUCTION_SOLD_MAIL_SUBJECT,
		won = AUCTION_WON_MAIL_SUBJECT,
		pending = AUCTION_INVOICE_MAIL_SUBJECT,
	})
	return patterns
end

local function ReadLetters()
	local letters = {}
	for i = 1, GetInboxNumItems() do
		local _, _, sender, subject, money, cod, _, itemCount, _, _, _, _, isGM = GetInboxHeaderInfo(i)
		local letter = { index = i, sender = sender, subject = subject, money = money or 0, cod = cod or 0,
			isGM = isGM, invoiceType = GetInboxInvoiceInfo(i), items = {} }
		if itemCount and itemCount > 0 then
			for slot = 1, ATTACH_MAX do
				if HasInboxItem(i, slot) then
					local _, itemID, _, _, _, _, isCurrency = GetInboxItem(i, slot)
					letter.items[#letter.items + 1] = { slot = slot, itemID = itemID or 0, currency = isCurrency }
				end
			end
		end
		letter.class = ns.Mail_Classify(letter, Patterns())
		letters[i] = letter
	end
	return letters
end

local function MoreOnServer()
	local shown, total = GetInboxNumItems()
	return (total or 0) > shown and shown < INBOX_MAX
end

-- Open all ----------------------------------------------------------------------------------------------------

local function ModeOpts(r)
	return { goldOnly = r.goldOnly, ahOnly = r.ahOnly }
end

local function StepOpts(r)
	return { goldOnly = r.goldOnly, ahOnly = r.ahOnly, failed = r.failed, skip = r.skip,
		freeSlots = C_Container.CalculateTotalNumberOfFreeBagSlots() }
end

local function IdleText()
	return db.goldOnly and "Take gold" or "Open all"
end

local function UpdateButton()
	if openButton then
		openButton.label:SetText(run and "Stop" or IdleText())
	end
end

-- The summary card from ns.Mail_Summary's title, detail and note. sample: a settings preview (kept out of Recent).
local function SummarySpec(title, detail, note, sample)
	local text = detail
	if note ~= "" then
		text = (text ~= "" and (text .. "\n") or "") .. note
	end
	return { owner = OWNER, label = "Mail", title = title, text = text, icon = ICON,
		mergeKey = "mail:summary", test = sample or nil }
end

-- Settings preview (Panel/Preview.lua): a made-up run, worded by the real summary code.
local function SummaryPreview(host)
	local title, detail, note = ns.Mail_Summary(SAMPLE_RUN, ns.Price)
	return ns.Toast_DrawSample(host, SummarySpec(title, detail, note, true), 1)
end

local function Report(r, letters, stopped)
	local counts = ns.Mail_Counts(letters, ModeOpts(r))
	ns.Mail_Tally(r.opened, r.prev, counts)
	local left, cod = 0, 0 -- left: letters still holding gold or items (a gold-only run leaves the items)
	for _, n in pairs(ns.Mail_Counts(letters, { ahOnly = r.ahOnly })) do
		left = left + n
	end
	for _, letter in ipairs(letters) do
		if letter.cod > 0 then
			cod = cod + 1
		end
	end
	local money = math.max(GetMoney() - r.startMoney, 0)
	local title, detail, note = ns.Mail_Summary({ money = money, opened = r.opened, left = left, cod = cod,
		bagsFull = r.bagsFull, goldOnly = r.goldOnly }, ns.Price)
	local any = money > 0 or next(r.opened) ~= nil
	if stopped and not any then
		return
	end
	if db.summary.chat then
		local line = "mail: " .. title
		if detail ~= "" then
			line = line .. " (" .. detail .. ")"
		end
		if note ~= "" then
			line = line .. ". " .. note
		end
		ns.Print(line .. ".")
	end
	if not any then
		return
	end
	if db.summary.toast then
		ns.Toast_Show(SummarySpec(title, detail, note))
	end
	local auction = false
	for kind in pairs(r.opened) do
		auction = auction or ns.Mail_IsAuction(kind)
	end
	if money > 0 or auction then
		ns.Session_Note("mail", { title = "Mail: " .. title, icon = ICON, detail = detail })
	end
end

-- stopped: the player stopped it, the mailbox closed or the module went off (no "Nothing to take" then).
local function Finish(stopped)
	local r = run
	if not r then
		return
	end
	run = nil
	r.ticker:Cancel()
	UpdateButton()
	Report(r, ReadLetters(), stopped)
end

local function Tick()
	local r = run
	if not r then
		return
	end
	if not (module.active and MailOpen()) then
		Finish(true)
		return
	end
	local letters = ReadLetters()
	local counts = ns.Mail_Counts(letters, ModeOpts(r))
	ns.Mail_Tally(r.opened, r.prev, counts)
	r.prev = counts
	local step, full = ns.Mail_NextStep(letters, StepOpts(r))
	r.bagsFull = r.bagsFull or full
	local now = GetTime()
	local action = ns.Mail_Decide({
		pending = C_Mail.IsCommandPending(),
		sinceLast = r.lastAt and (now - r.lastAt),
		minDelay = MIN_DELAY,
		step = step,
		more = MoreOnServer(),
		waited = r.waitStart and (now - r.waitStart) or 0,
		maxWait = MAX_WAIT,
	})
	if action == "take" then
		r.waitStart = nil
		local sig = ns.Mail_Signature(letters)
		if step.key == r.lastKey and sig == r.lastSig then
			r.tries = r.tries + 1
			if ns.Mail_Stuck(r.tries, STUCK_TRIES) then
				r.skip[step.key] = true
				r.lastKey = nil
				return
			end
		else
			r.lastKey, r.lastSig, r.tries = step.key, sig, 1
		end
		if step.kind == "money" then
			TakeInboxMoney(step.index)
		else
			TakeInboxItem(step.index, step.slot)
		end
		r.lastAt = now
	elseif action == "more" then
		r.waitStart = r.waitStart or now
	elseif action == "done" then
		Finish(false)
	end
end

local function OpenAll(goldOnly)
	if not MailOpen() then
		ns.Print("open a mailbox first.")
		return
	end
	if run then
		Finish(true)
	end
	local r = { goldOnly = goldOnly, ahOnly = db.ahOnly, startMoney = GetMoney(), opened = {}, failed = {}, skip = {},
		tries = 0 }
	r.prev = ns.Mail_Counts(ReadLetters(), ModeOpts(r))
	r.ticker = C_Timer.NewTicker(TICK, Tick)
	run = r
	UpdateButton()
	Tick()
end

-- Shift-click does the other of the "Gold only by default" setting.
local function Toggle()
	if run then
		Finish(true)
	else
		OpenAll((IsShiftKeyDown() and true or false) ~= db.goldOnly)
	end
end

-- Inbox button ------------------------------------------------------------------------------------------------

local function OpenButtonOnEnter(self)
	GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
	GameTooltip:SetText(run and "Stop opening mail" or IdleText(), UI.Color("heading"))
	if run then
		GameTooltip:AddLine("Click to stop. A summary follows.", UI.RGB("textMuted"))
	else
		GameTooltip:AddLine(db.goldOnly and "Takes the gold from every letter and leaves the items."
			or "Takes gold and items from every letter, one at a time.", UI.RGB("text"))
		GameTooltip:AddLine("Leaves cash on delivery and GM letters"
			.. (db.ahOnly and ", and letters from players." or "."), UI.RGB("textMuted"))
		GameTooltip:AddLine(db.goldOnly and "Shift-click: gold and items." or "Shift-click: gold only.",
			UI.RGB("success"))
	end
	GameTooltip:Show()
end

local function CreateOpenButton()
	openButton = UI.Button(InboxFrame, 120, IdleText())
	openButton:SetHeight(24)
	openButton:SetPoint("CENTER", OpenAllMail, "CENTER")
	openButton:SetScript("OnClick", Toggle)
	openButton:HookScript("OnEnter", OpenButtonOnEnter)
	openButton:HookScript("OnLeave", GameTooltip_Hide)
end

-- Send tab picker ---------------------------------------------------------------------------------------------

local function MailName(c)
	if ns.Alts_MailName then
		return ns.Alts_MailName(c, GetNormalizedRealmName())
	end
	return c.name
end

-- Realms mail reaches (the Alts module's connected-realm list); only your own when that isn't there.
local function Reachable(c)
	local realms = ns.Alts_MailRealms and ns.Alts_MailRealms()
	if realms and ns.Alts_Reachable then
		return ns.Alts_Reachable(c, realms)
	end
	return c.realm == GetNormalizedRealmName()
end

-- Your characters: everyone the Alts module knows (most are there long before Mail saw them log in), plus Mail's
-- own roster for when Alts is off. Mail's entry wins for a character both know: it has the faction.
local function Recipients()
	local chars = {}
	for guid, c in pairs(ns.Alts_Characters and ns.Alts_Characters() or {}) do
		chars[guid] = c
	end
	for guid, c in pairs(db.chars) do
		chars[guid] = c
	end
	return ns.Mail_Recipients(chars, { guid = UnitGUID("player") }, Reachable, MailName)
end

local function Pick(name)
	if not (module.active and SendMailNameEditBox) then
		return
	end
	SendMailNameEditBox:SetText(name)
	SendMailSubjectEditBox:SetFocus()
end

local function FillMenu(_, root)
	local me = (UnitName("player") or ""):lower()
	local recent = {}
	for _, name in ipairs(CharDB().recent) do
		if name:lower() ~= me then
			recent[#recent + 1] = name
		end
	end
	if #recent > 0 then
		root:CreateTitle("Mailed lately")
		for _, name in ipairs(recent) do
			root:CreateButton(name, Pick, name)
		end
	end
	local chars = Recipients()
	if #chars > 0 then
		if #recent > 0 then
			root:CreateDivider()
		end
		root:CreateTitle("Your characters")
		for _, c in ipairs(chars) do
			root:CreateButton(UI.ClassColored(c.name, c.class), Pick, c.name)
		end
	end
	if #recent == 0 and #chars == 0 then
		root:CreateTitle("No characters yet: log in on your alts once")
	end
end

local function PickerOnEnter(self)
	GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
	GameTooltip:SetText("Send to", UI.Color("heading"))
	GameTooltip:AddLine("Your other characters this mail reaches, and who you mailed lately.", UI.RGB("text"))
	GameTooltip:Show()
end

-- The picker sits inside the right end of the To box: right of the box is Blizzard's "Postage:" text. The box's
-- right text inset grows by this much while the picker shows, so a long name doesn't run under it.
local PICKER_SIZE = 16
local PICKER_INSET = 18
local baseInsets -- the To box's own text insets, put back when the picker hides

local function SetPickerInset(on)
	local box = SendMailNameEditBox
	if on and not baseInsets then
		baseInsets = { box:GetTextInsets() }
		local l, r, t, b = unpack(baseInsets)
		box:SetTextInsets(l, r + PICKER_INSET, t, b)
	elseif not on and baseInsets then
		box:SetTextInsets(unpack(baseInsets))
		baseInsets = nil
	end
end

local function CreatePicker()
	picker = UI.Button(SendMailFrame, PICKER_SIZE, "v")
	picker:SetHeight(PICKER_SIZE)
	picker:SetPoint("RIGHT", SendMailNameEditBox, "RIGHT", -2, 0)
	picker:SetFrameLevel(SendMailNameEditBox:GetFrameLevel() + 2)
	picker:SetScript("OnClick", function(self)
		UI.ContextMenu(self, FillMenu)
	end)
	picker:HookScript("OnEnter", PickerOnEnter)
	picker:HookScript("OnLeave", GameTooltip_Hide)
end

-- Shows Tomte's pieces on Blizzard's mail frame while the module and their settings are on, and puts Blizzard's
-- Open All back otherwise. Blizzard's frames only exist once the mail frame has loaded.
local function ApplyFrames()
	local inbox = module.active and db.inbox and OpenAllMail ~= nil
	if inbox and not openButton then
		CreateOpenButton()
	end
	if openButton then
		openButton:SetShown(inbox)
		UpdateButton()
	end
	if inbox and not hidBlizzard then
		OpenAllMail:Hide() -- its OnHide stops a run of Blizzard's own
		hidBlizzard = true
	elseif not inbox and hidBlizzard then
		OpenAllMail:Show()
		hidBlizzard = false
	end

	local send = module.active and db.picker and SendMailNameEditBox ~= nil
	if send and not picker then
		CreatePicker()
	end
	if picker then
		picker:SetShown(send)
		SetPickerInset(send)
	end
end

-- Remembers who a mail went to; hooksecurefunc can't be undone, so it does nothing while the module is off.
local function OnSendMail(recipient)
	if module.active then
		sentTo = recipient
	end
end

-- Why: what Open all would do with each letter --------------------------------------------------------------

local SKIP_WORDS = { cod = "cash on delivery: left", gm = "GM letter: left", notAuction = "from a player: left",
	empty = "nothing to take" }

local function Why()
	if not MailOpen() then
		ns.Print("open a mailbox first.")
		return
	end
	local letters = ReadLetters()
	local opts = { goldOnly = db.goldOnly, ahOnly = db.ahOnly }
	local shown, total = GetInboxNumItems()
	ns.Print(("%d letters in the inbox (%d on the server). Free bag slots: %d. %s%s"):format(shown, total or shown,
		C_Container.CalculateTotalNumberOfFreeBagSlots(), db.goldOnly and "Gold only." or "Gold and items.",
		db.ahOnly and " Auction House letters only." or ""))
	for _, letter in ipairs(letters) do
		local skip = ns.Mail_Skip(letter, opts)
		local what = skip and SKIP_WORDS[skip]
			or ("take " .. (letter.money > 0 and ns.Price(letter.money) or "")
				.. (letter.money > 0 and #letter.items > 0 and not opts.goldOnly and " + " or "")
				.. ((#letter.items > 0 and not opts.goldOnly) and (#letter.items .. " items") or ""))
		ns.Print(("%d. %s, \"%s\" (%s): %s"):format(letter.index, letter.sender or "?", letter.subject or "",
			letter.class, what))
	end
end

-- Events ------------------------------------------------------------------------------------------------------

local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(self, event, ...)
	self[event](self, ...)
end)

function events:PLAYER_ENTERING_WORLD()
	RecordMe()
end

function events:MAIL_SHOW()
	RecordMe()
	ApplyFrames()
end

function events:MAIL_CLOSED()
	Finish(true)
end

-- The server refused an attachment (unique, bags full): Open all passes over that item from now on.
function events:MAIL_FAILED(itemID)
	sentTo = nil
	if run and itemID then
		run.failed[itemID] = true
	end
end

function events:MAIL_SEND_SUCCESS()
	if sentTo then
		local char = CharDB()
		char.recent = ns.Mail_Remember(char.recent, sentTo, RECENT_MAX)
		sentTo = nil
	end
end

local EVENTS = { "PLAYER_ENTERING_WORLD", "MAIL_SHOW", "MAIL_CLOSED", "MAIL_FAILED", "MAIL_SEND_SUCCESS" }
local hooked

local function Start()
	for _, event in ipairs(EVENTS) do
		events:RegisterEvent(event)
	end
	if not hooked then
		hooksecurefunc("SendMail", OnSendMail)
		hooked = true
	end
	if UnitGUID("player") then
		RecordMe()
	end
	ApplyFrames()
end

local function Stop()
	events:UnregisterAllEvents()
	Finish(true)
	sentTo = nil
	ns.Toast_Clear(OWNER)
	ApplyFrames() -- module.active is false by now: hides Tomte's buttons, brings Blizzard's Open All back
end

local function RequireMailbox(fn)
	return function()
		if MailOpen() then
			fn()
		else
			ns.Print("open a mailbox first.")
		end
	end
end

module = ns.RegisterModule({
	key = "mail",
	name = "Mail",
	category = "professions",
	icon = ICON,
	summary = "Open all your mail in one click, with a summary, and send to your alts quickly.",
	description = "An Open all button on the inbox that takes gold and items letter by letter (never cash on delivery), then sums up the gold and your Auction House sales, purchases, expired and cancelled auctions and outbids. On the Send tab, a button next to the To box lists your other characters and who you mailed lately.",
	enabledByDefault = true,
	toasts = true,
	defaults = {
		inbox = true,
		goldOnly = false,
		ahOnly = false,
		summary = { chat = true, toast = true },
		picker = true,
		chars = {}, -- [player GUID] = { name, realm, faction, class, recent = { recipient names, newest first } }
	},
	init = function(moduleDB)
		db = moduleDB
	end,
	toggle = function(active)
		if active then
			Start()
		else
			Stop()
		end
	end,
	commands = {
		{ "open", "at a mailbox: open all mail (again: stop)", RequireMailbox(function()
			if run then
				Finish(true)
			else
				OpenAll(db.goldOnly)
			end
		end) },
		{ "gold", "at a mailbox: take only the gold from your mail", RequireMailbox(function()
			OpenAll(true)
		end) },
		{ "why", "at a mailbox: list each letter and what Open all does with it", Why },
	},
	options = {
		{ type = "header", label = "Inbox" },
		{ type = "checkbox", key = "inbox", label = "Open all button", onChange = ApplyFrames,
			tooltip = "Stands in for Blizzard's Open All button on the inbox: takes gold and items one letter at a time, never cash on delivery, keeps taking gold when your bags are full, and sums it up at the end." },
		{ type = "checkbox", key = "goldOnly", label = "Gold only by default", onChange = ApplyFrames,
			parent = "inbox", tooltip = "A click takes only gold and leaves the items. Shift-click takes everything." },
		{ type = "checkbox", key = "ahOnly", label = "Only Auction House letters", parent = "inbox",
			tooltip = "Leave letters from players for you to open yourself." },
		{ type = "checkbox", key = "summary.chat", label = "Summary in chat", parent = "inbox" },
		{ type = "checkbox", key = "summary.toast", label = "Summary card", parent = "inbox",
			preview = ns.Preview_When("summary.toast", SummaryPreview),
			tooltip = "A card with the gold and the Auction House letters when Open all is done." },

		{ type = "header", label = "Send" },
		{ type = "checkbox", key = "picker", label = "Character picker", onChange = ApplyFrames,
			tooltip = "A button next to the To box lists your other characters this mail reaches (this realm and connected realms, both factions) and who you mailed lately. A character shows up once you've logged in on it." },
	},
})
