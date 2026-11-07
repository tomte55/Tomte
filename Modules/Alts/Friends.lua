local addonName, ns = ...

-- Friend crafting: Alts' side of Friend sharing. Registers the per-friend "crafts" set (your characters' professions
-- and recipes; each friend's kept under their BattleTag in db.friendCrafts and never passed on), merges friends'
-- reachable characters into the Crafting tab's search, and runs craft requests between friends (sent as Friend
-- sharing's direct messages, kept in db.requests). Rules and formats in FriendsData.lua; the Requests section is
-- RequestsSection.lua, the mailbox block FriendMail.lua. Spec: docs/superpowers/specs/2026-11-07-tomte-friend-crafting-design.md.

local SET = "crafts"
local OWNER = "friends" -- this file's owner on Alts' event bus
local LABEL = "Craft request"
local ICON = "Interface\\Icons\\INV_Misc_Note_01"

local db
local active = false
local events = ns.Alts_Events -- Collect.lua

local function Refresh()
	if ns.AltsCraft_Refresh then
		ns.AltsCraft_Refresh()
	end
	if ns.AltsListTab_Refresh then
		ns.AltsListTab_Refresh()
	end
	if ns.AltsList_Refresh then
		ns.AltsList_Refresh() -- the tracker's mail steps for friends
	end
end

local function ShortName(tag)
	return tag and tag:match("^[^#]+") or tag or "?"
end

-- The crafts set ------------------------------------------------------------------------------------------------

-- The payload is built again only after your crafting changed: Friend sharing asks for its revision in every hello.
local exported
local function Export()
	exported = exported or ns.AltsFriends_Export(db.chars, db.recipes)
	return exported
end

-- Whether friends' crafting runs: Alts on, on Forever (retail characters know thousands of recipes, too much to send
-- to every friend after each skill point), and Friend sharing sharing the crafts set.
local function Sharing()
	return active and ns.FOREVER == true and ns.Share_Sharing ~= nil and ns.Share_Sharing(SET)
end
ns.AltsFriends_Sharing = Sharing

local function Import(payload, tag)
	local data, reason = ns.AltsFriends_Import(payload)
	if not data then
		return nil, reason
	end
	db.friendCrafts[tag] = { at = time(), data = data }
	Refresh()
	return #data.chars
end

-- Your characters' crafting changed (a recipe scan, a skill): friends hear of it on the next hello (debounced there).
function ns.AltsFriends_Changed()
	exported = nil
	if active and ns.Share_Changed then
		ns.Share_Changed(SET)
	end
end

-- Whether a friend is in the game right now with Friend sharing on (their recipes are shown either way).
function ns.AltsFriends_Online(tag)
	return ns.Share_Online ~= nil and ns.Share_Online(tag) ~= nil
end

-- Your characters and recipes with friends' reachable characters added (FriendsData.lua's merge), or yours unchanged
-- while friends' crafting is hidden, off, or nobody has shared any. Blocked friends are left out.
function ns.AltsFriends_Merged(chars, recipes)
	if not (Sharing() and db.friendsShow and next(db.friendCrafts)) then
		return chars, recipes
	end
	local friends, online = {}, {}
	for tag, entry in pairs(db.friendCrafts) do
		if not ns.Share_IsBlocked(tag) then
			friends[tag] = entry
			online[tag] = ns.AltsFriends_Online(tag) or nil
		end
	end
	local realms, realmKey = ns.AltsFriends_Realms()
	return ns.AltsFriends_Merge(chars, recipes, friends,
		{ faction = UnitFactionGroup("player"), realms = realms, realmKey = realmKey, online = online })
end

-- The realms a friend's character must be on for mail to reach it, and the key they're compared by. Retail: the
-- connected realms (ns.Alts_MailRealms). Forever: your realm without its server number (AltsFriends_ForeverRealm),
-- as friends on one ruleset play together from numbered servers (seen in game: Realm5PvE and Realm3PvE). Mail there
-- goes to the character's full name, first name and surname (Alts_MailName).
function ns.AltsFriends_Realms()
	if ns.FOREVER then
		local mine = GetNormalizedRealmName()
		if not mine or mine == "" then
			return nil, ns.AltsFriends_ForeverRealm
		end
		return { [ns.AltsFriends_ForeverRealm(mine)] = true }, ns.AltsFriends_ForeverRealm
	end
	return ns.Alts_MailRealms(), nil
end

-- A recipe by ID: yours, or one a friend shared.
function ns.AltsFriends_Recipe(recipeID)
	local r = db.recipes[recipeID]
	if r then
		return r
	end
	for _, entry in pairs(db.friendCrafts) do
		r = entry.data and entry.data.recipes and entry.data.recipes[recipeID]
		if r then
			return r
		end
	end
	return nil
end

-- /tomte alts friends: what each friend shared and why each of their characters is shown or not.
function ns.AltsFriends_Why()
	local faction, realm = UnitFactionGroup("player"), GetNormalizedRealmName()
	ns.Print(("friends' crafting: %s; you are %s on %s."):format(Sharing() and "on" or "off (Friend sharing, its "
		.. "Professions and recipes switch, or not on Forever)", tostring(faction), tostring(realm)))
	if not next(db.friendCrafts) then
		print("  No friend has shared their crafting yet.")
		return
	end
	local realms, realmKey = ns.AltsFriends_Realms()
	for tag, entry in pairs(db.friendCrafts) do
		local data = entry.data or {}
		print(("  %s%s: %d characters, received %s."):format(ShortName(tag),
			ns.Share_IsBlocked(tag) and " (blocked)" or "", #(data.chars or {}), ns.AgoText(time() - (entry.at or 0))))
		for _, c in ipairs(data.chars or {}) do
			local why = ns.AltsFriends_Reachable(c, faction, realms, realmKey) and "shown"
				or ((c.faction ~= "" and c.faction ~= (faction or ""):sub(1, 1)) and "hidden: other faction"
					or "hidden: a realm your mail doesn't reach (on Forever: another ruleset)")
			local n = 0
			for _, p in pairs(c.profs or {}) do
				for _ in pairs(p.known or {}) do
					n = n + 1
				end
			end
			print(("    %s (%s, %s): %d recipes, %s"):format(c.name, c.realm ~= "" and c.realm or "?",
				c.faction ~= "" and c.faction or "?", n, why))
		end
	end
end

-- What needs a mail for the requests, only to friends this character's mail reaches (FriendsData.lua's MailGroups);
-- none while friends' crafting is off. The mailbox block (FriendMail.lua) and the crafting list tracker show them.
function ns.AltsFriends_MailGroupsNow()
	if not Sharing() then
		return {}
	end
	local recipes = {}
	for _, req in pairs(db.requests) do
		recipes[req.recipeID] = ns.AltsFriends_Recipe(req.recipeID)
	end
	local realms, realmKey = ns.AltsFriends_Realms()
	return ns.AltsFriends_MailGroups(db.requests, recipes,
		{ faction = UnitFactionGroup("player"), realms = realms, realmKey = realmKey })
end

-- The crafting list tracker's blocks for them: "Mail 1 Camp Tent to Dead" once you've made a friend's craft.
function ns.AltsFriends_TrackerTodos()
	return ns.AltsFriends_Todos(ns.AltsFriends_MailGroupsNow(), {
		me = UnitGUID("player"),
		itemName = function(itemID)
			return ns.Alts_ItemLabel(itemID, 13, true)
		end,
		recipeName = function(req)
			return ns.AltsFriends_RecipeName(req)
		end,
	})
end

-- What the crafting list tracker shows: your crafts (List.lua's to-do), then the mail steps for friends.
function ns.AltsFriends_TrackerList()
	local list = {}
	for _, t in ipairs(ns.AltsList_Todos()) do
		list[#list + 1] = t
	end
	for _, t in ipairs(ns.AltsFriends_TrackerTodos()) do
		list[#list + 1] = t
	end
	return list
end

-- A friend stopped sharing their crafting (or was forgotten): their characters leave your Crafting tab.
local function Withdrawn(tag)
	if db.friendCrafts[tag] then
		db.friendCrafts[tag] = nil
		Refresh()
	end
end

-- Requests -------------------------------------------------------------------------------------------------------

local OUTBOX_TRIES = 5 -- hellos an answer is sent again on; answers can be dropped when the friend goes offline

local function RecipeName(req)
	local r = ns.AltsFriends_Recipe(req.recipeID)
	return r and r.name or req.name or ("recipe " .. tostring(req.recipeID))
end

-- Sends what a request still owes its friend: your ask until it's been delivered, and your latest answer. Quietly
-- does nothing while the friend can't be reached. A queued message can still be dropped (the friend logs off), so the
-- answer is sent again on their next hellos too (greeted); requests only move forward, so a repeat changes nothing.
local function Deliver(req)
	if req.mine and (req.state == "waiting" or req.state == "sent") then
		if ns.Share_Send(req.friend, SET, ns.AltsFriends_EncodeAsk(req)) and req.state == "waiting" then
			ns.AltsFriends_Apply(req, "sent")
		end
	end
	if req.outbox and ns.Share_Send(req.friend, SET, ns.AltsFriends_EncodeAnswer(req.id, req.outbox)) then
		req.outboxTries = (req.outboxTries or 0) + 1
		if req.outboxTries >= OUTBOX_TRIES then
			req.outbox, req.outboxTries = nil, nil
		end
	end
	if req.hidden and not req.outbox then
		db.requests[req.id] = nil -- cleared, and nothing left to tell
	end
end

local function NewID()
	return ("%d-%04d"):format(time(), math.random(0, 9999))
end

-- Asks a friend's character (a merged one: name, realm, friend = { tag }) for amount crafts of a recipe; mats: you mail
-- the materials. The request is kept and sent now, or when you're both online.
function ns.AltsFriends_Ask(crafter, recipeID, amount, mats)
	local recipe = ns.AltsFriends_Recipe(recipeID) or {}
	local req = ns.AltsFriends_NewRequest({ id = NewID(), mine = true, friend = crafter.friend.tag,
		recipeID = recipeID, itemID = recipe.item, name = recipe.name, amount = amount, mats = mats,
		crafter = crafter.name, crafterRealm = crafter.realm, crafterFaction = crafter.faction, asker = ns.Alts_PlayerFullName() or UnitName("player"),
		askerRealm = GetNormalizedRealmName(), askerFaction = UnitFactionGroup("player"), at = time() })
	db.requests[req.id] = req
	Deliver(req)
	ns.Print(("asked %s (%s) for %d %s%s."):format(crafter.name or "?", ShortName(req.friend), amount,
		req.name or "?", req.state == "waiting" and ": it goes out when you're both online" or ""))
	Refresh()
end

-- Moves one of the requests on by your own answer (accepted, declined, made, done, cancel) and tells the friend.
-- Accepting puts the craft on your crafting list.
function ns.AltsFriends_Answer(id, event)
	local req = db.requests[id]
	if not (req and ns.AltsFriends_Apply(req, event)) then
		return
	end
	if event == "accepted" and ns.AltsList_Add then
		ns.AltsList_Add(req.recipeID, req.amount)
	end
	req.outbox, req.outboxTries = event, nil
	Deliver(req)
	Refresh()
end

-- Takes a request that's over (done, declined or cancelled) off the list. It's kept out of sight until its last answer
-- has gone out, so a friend's resent ask still counts as the same request.
function ns.AltsFriends_Clear(id)
	local req = db.requests[id]
	if req and not ns.AltsFriends_Open(req) then
		req.hidden = true
		if not req.outbox then
			db.requests[id] = nil
		end
		Refresh()
	end
end

-- Every request on the list, open ones first, newest first: { req }. None while friends' crafting is off.
function ns.AltsFriends_Requests()
	local list = {}
	for _, req in pairs(Sharing() and db.requests or {}) do
		if not req.hidden then
			list[#list + 1] = req
		end
	end
	table.sort(list, function(a, b)
		local x, y = ns.AltsFriends_Open(a), ns.AltsFriends_Open(b)
		if x ~= y then
			return x
		end
		return (a.at or 0) > (b.at or 0)
	end)
	return list
end

function ns.AltsFriends_RecipeName(req)
	return RecipeName(req)
end

-- Home --------------------------------------------------------------------------------------------------------

local function OpenRequests()
	ns.Panel_OpenPage("alts")
	ns.Alts_ShowTab("list")
end
ns.AltsFriends_OpenRequests = OpenRequests

-- How many requests need you: a friend's asks to answer, and crafts or materials to mail. 0 while it's off.
function ns.AltsFriends_HomeCount()
	if not Sharing() then
		return 0
	end
	return #ns.AltsFriends_Awaiting(db.requests) + #ns.AltsFriends_MailGroupsNow()
end

-- Home's Next up: each of them, a click opens the Crafting list tab with its Craft requests.
function ns.AltsFriends_NextUp()
	local list = {}
	if not Sharing() then
		return list
	end
	for _, req in ipairs(ns.AltsFriends_Awaiting(db.requests)) do
		list[#list + 1] = { key = "craftreq:ask:" .. req.id, state = req.state, onClick = OpenRequests,
			text = ("%s asks for %d %s"):format(req.asker or ShortName(req.friend), req.amount or 1, RecipeName(req)),
			why = "A friend's craft request: Accept or Decline it on the Crafting list tab.",
			icon = req.itemID and C_Item.GetItemIconByID(req.itemID) or ICON }
	end
	for _, g in ipairs(ns.AltsFriends_MailGroupsNow()) do
		local name = RecipeName(g.req)
		list[#list + 1] = { key = ("craftreq:%s:%s"):format(g.kind, g.req.id), onClick = OpenRequests,
			text = g.kind == "item" and ("Mail %s to %s"):format(name, g.to.name or "?")
				or ("Mail the materials for %s to %s"):format(name, g.to.name or "?"),
			why = "At a mailbox, the \"For your friends\" block attaches it.", icon = "Interface\\Icons\\INV_Letter_15" }
	end
	return list
end

local function OnMessage(tag, text)
	local msg = ns.AltsFriends_Decode(text)
	if not msg then
		return
	end
	if msg.kind == "ask" then
		local req, new = ns.AltsFriends_TakeAsk(db.requests, msg, tag, time())
		local mine = db.recipes[req.recipeID]
		req.name = req.name or (mine and mine.name)
		ns.Share_Send(tag, SET, ns.AltsFriends_EncodeAnswer(req.id, "got"))
		if new then
			ns.Toast_Show({ owner = "alts", label = LABEL, accent = "accent", icon = ICON,
				title = ("%s (%s)"):format(req.asker ~= "" and req.asker or "?", ShortName(tag)),
				text = ("asks %s for %d %s%s."):format(req.crafter or "you", req.amount, RecipeName(req),
					req.mats and ", and mails the materials" or ", with your materials"),
				hold = 10, onClick = OpenRequests })
		end
	else
		local req = db.requests[msg.id]
		if req and req.friend == tag and ns.AltsFriends_Apply(req, msg.kind) and req.mine and msg.kind == "done" then
			-- Your craft is in the mail: their Tomte saw it go (FriendMail.lua's Send).
			ns.Toast_Show({ owner = "alts", label = LABEL, accent = "success", icon = ICON,
				title = ("%s (%s)"):format(req.crafter or "?", ShortName(tag)),
				text = ("mailed you %d %s. Check your mailbox."):format(req.amount or 1, RecipeName(req)), hold = 10 })
		end
	end
	Refresh()
end

local function OnRefused(tag, id)
	local req = db.requests[id]
	if req and req.friend == tag and req.mine then
		req.note = "not taking requests"
		ns.AltsFriends_Apply(req, "declined")
		Refresh()
	end
end

-- A friend said hello: whatever is still owed to them goes out now (once per hello).
local function OnGreeted(tag)
	for _, req in pairs(db.requests) do
		if req.friend == tag then
			Deliver(req)
		end
	end
	Refresh()
end

-- A request you accepted is made once your bags hold what it asked for.
events:On(OWNER, "BAG_UPDATE_DELAYED", function()
	if not Sharing() then
		return
	end
	for id, req in pairs(db.requests) do
		if not req.mine and req.state == "accepted" and (req.itemID or 0) > 0
			and C_Item.GetItemCount(req.itemID) >= ns.AltsFriends_ItemCount(req, db.recipes[req.recipeID]) then
			ns.AltsFriends_Answer(id, "made")
		end
	end
end)

-- Start and stop -------------------------------------------------------------------------------------------------

-- From Alts' init: the set is registered once (Friend sharing loads after Alts, but every file is loaded by now).
function ns.AltsFriends_Init(moduleDB)
	db = moduleDB
	if not ns.Share_Register then
		return
	end
	ns.Share_Register({
		key = SET,
		label = "Recipes",
		perFriend = true,
		count = function(n, adjective)
			return n .. (adjective and (" " .. adjective) or "") .. (n == 1 and " character's recipes" or " characters' recipes")
		end,
		export = Export,
		revision = function()
			return ns.AltsFriends_Revision(Export())
		end,
		import = Import,
		active = function()
			return active and ns.FOREVER == true -- Forever only: see Sharing
		end,
		message = OnMessage,
		refused = OnRefused,
		greeted = OnGreeted,
		withdrawn = Withdrawn,
	})
end

function ns.AltsFriends_Start()
	active = true
	events:Watch(OWNER, "BAG_UPDATE_DELAYED")
	ns.AltsFriends_Changed()
end

function ns.AltsFriends_Stop()
	active = false
	events:Unwatch(OWNER, "BAG_UPDATE_DELAYED")
end
