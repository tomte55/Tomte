# Friend Crafting Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** On Forever, see what friends can craft on the Alts Crafting tab, ask them for a craft, and move materials and the
finished item by mail with one click per step; Friend sharing and the Forever theme become Forever's defaults.

**Architecture:** Friend sharing (`Modules/Share/`) gains per-friend data sets (imported per sender, never relayed) and
direct messages to one friend. Alts registers a `crafts` set (each player's characters and recipes) and sends craft
requests as direct messages. Pure rules live in a new `Modules/Alts/FriendsData.lua`; the game side in
`Modules/Alts/Friends.lua`; the mailbox block in `Modules/Alts/FriendMail.lua`; the Requests section in
`Modules/Alts/RequestsSection.lua`. `Send.lua` (817 lines), `List.lua` (987) and `ListTab.lua` (814) only get small calls.

**Tech Stack:** WoW Lua (Forever 1.60.1, Interface 16001; retail 12.1.5 must keep loading), plain-Lua unit tests run with
Lua 5.1 (`tests/harness.lua`).

**Spec:** `docs/superpowers/specs/2026-11-07-tomte-friend-crafting-design.md`

## Global Constraints

- CLAUDE.md applies to every file: first line `local addonName, ns = ...`, header comment, tabs, about 120 columns, no
  numeric colors or `|cff` literals, `UI.*` widgets, `ns.Confirm_Show` for yes/no, no settings UI by hand.
- Edit Lua with Edit/Write only (CRLF, double backslashes).
- Friend sharing on by default **on Forever only**: `enabledByDefault = ns.FOREVER == true`. Retail keeps migration 11's default.
- Existing Forever profiles get `share` switched on once by a migration (presets wrote `false`); retail profiles untouched.
- A friend's `crafts` data and requests are never relayed to other friends.
- Only friends' characters mail can reach show: same faction (unknown faction counts as reachable) and
  `ns.Alts_Reachable(c, ns.Alts_MailRealms())`.
- Requests follow the `crafts` switch on both sides; a blocked friend sends and gets nothing.
- Nothing happens without a click: Attach, then Send, as the mailbox panel does today.
- Names in tests and docs: Aldric, Kesha, Mira.
- After TOC changes: `lua Tomte/tools/forevertoc.lua` then `lua Tomte/tools/bugfiles.lua`.
- All tests from the AddOns folder: `for t in Tomte/tests/test_*.lua; do lua "$t" >/dev/null 2>&1 || echo "FAIL $t"; done`.
- No commit before the user has checked the step in game (memory: batch in-game checks; one combined test list, then
  per-task commits).

## Review Focus

1. **A friend runs an older Tomte** that doesn't know `M`/`X` messages or the `crafts` set: requests must stay
   `waiting`, never error, never spam. (Task 2: unknown kinds already rejected; Task 6: resend at most once per hello.)
2. **The same request arrives twice** (resend after a lost `got`): the crafter must not get two toasts or two list
   entries. (Task 4 test: applying `ask` to an existing ID is a no-op.)
3. **A friend's character not on your realm/faction**: never offered to ask, never in the mailbox block. (Task 4 test.)
4. **Recipe or item names containing the payload separators** (`;`, `,`, `:`, `=`, `^`, `|`): export must strip them so
   import never misreads a record. (Task 4 test.)
5. **Friends' crafting switched off, or Friend sharing off**: nothing friend-related shows or sends, and turning it back
   on mid-session works. (Task 6/7 in-game checks; Task 2 test that a not-shared set's `M` is answered with `X`.)

---

### Task 1: Forever theme by default on Forever

**Files:**
- Modify: `Panel/Window.lua:378` (the `theme` default)
- Modify: `Core/Core.lua:212-214` (fallback and order)
- Modify: `Core/Migrations.lua` (append migration 16)
- Test: `tests/test_migrations.lua`

**Interfaces:**
- Produces: migration 16 (theme), so Task 3's migration is 17.

- [ ] **Step 1: Write the failing tests** in `tests/test_migrations.lua`:

```lua
test("Forever theme: a Forever profile on the old default moves to the Forever theme", function()
	ns.FOREVER = true
	local db = { schema = 15, window = { theme = "blizzard" } }
	ns.RunMigrations(db, ns.MIGRATIONS)
	eq(db.window.theme, "forever")
	ns.FOREVER = nil
end)

test("Forever theme: a theme picked by hand and retail profiles stay", function()
	ns.FOREVER = true
	local db = { schema = 15, window = { theme = "void" } }
	ns.RunMigrations(db, ns.MIGRATIONS)
	eq(db.window.theme, "void")
	ns.FOREVER = nil
	db = { schema = 15, window = { theme = "blizzard" } }
	ns.RunMigrations(db, ns.MIGRATIONS)
	eq(db.window.theme, "blizzard", "retail keeps its default")
	db = { schema = 15 }
	ns.RunMigrations(db, ns.MIGRATIONS)
	eq(db.window, nil, "a fresh install has nothing to move")
end)
```

- [ ] **Step 2: Run** `lua Tomte/tests/test_migrations.lua` — expect the first test to FAIL (theme stays "blizzard").
- [ ] **Step 3: Implement.** Migration 16 in `Core/Migrations.lua`: on `ns.FOREVER`, a `db.window.theme` equal to
  `"blizzard"` (the old default every profile saved) becomes `"forever"`; comment says why (theme defaults are saved, so
  "never chose" can't be told apart; the user decided Forever starts on its own theme). `Panel/Window.lua`: default
  `theme = ns.FOREVER and "forever" or ns.Theme.DEFAULT`. `Core/Core.lua`: run `ns.RunMigrations` before
  `ns.Theme.Apply`, and apply `db.window.theme or (ns.FOREVER and "forever" or nil)`; keep the "before anything draws"
  comment true (migrations draw nothing).
- [ ] **Step 4: Run all tests** — all pass.
- [ ] **Step 5: In game (user):** on Forever with the theme on Blizzard, `/reload` → Tomte's window is in the Forever
  theme. Retail unchanged.

### Task 2: Friend sharing: per-friend sets, direct messages, refusals

**Files:**
- Modify: `Modules/Share/Protocol.lua` (new kinds `M`, `X`)
- Modify: `Modules/Share/Share.lua` (per-friend sets, `ns.Share_Send`, `ns.Share_Online`, callbacks)
- Modify: `Modules/Share/Roster.lua` (look up by BattleTag)
- Test: `tests/test_share_protocol.lua`

**Interfaces:**
- Produces (Protocol, pure):
  - `ns.Share_BuildMessage(key, text) -> string` = `"1^M^<key>^<text>"`; `#text` must be ≤ `ns.SHARE_CHUNK`.
  - `ns.Share_BuildRefusal(key, id) -> string` = `"1^X^<key>^<id>"`.
  - `ns.Share_Parse` returns `{ type = "M", set, text }` and `{ type = "X", set, id }`.
  - `ns.Share_MessageID(text) -> string|nil`: the text before the first `;`.
- Produces (Share.lua): set fields (all optional) `perFriend = true`, `import(payload, tag)`,
  `message(tag, text)`, `refused(tag, id)`, `greeted(tag)`; functions `ns.Share_Send(tag, key, text) -> boolean`
  (false when that friend isn't reachable now or the set isn't shared) and `ns.Share_Online(tag) -> characterName|nil`.

- [ ] **Step 1: Failing tests** in `tests/test_share_protocol.lua`:

```lua
test("direct message round trip", function()
	local msg = ns.Share_Parse(ns.Share_BuildMessage("crafts", "k1;ask;123"))
	eq(msg.type, "M")
	eq(msg.set, "crafts")
	eq(msg.text, "k1;ask;123")
	eq(ns.Share_MessageID(msg.text), "k1")
end)

test("refusal round trip", function()
	local msg = ns.Share_Parse(ns.Share_BuildRefusal("crafts", "k1"))
	eq(msg.type, "X")
	eq(msg.set, "crafts")
	eq(msg.id, "k1")
	eq(ns.Share_Parse("1^X^crafts^"), nil, "a refusal needs an ID")
end)
```

- [ ] **Step 2: Run** `lua Tomte/tests/test_share_protocol.lua` — FAIL (functions missing).
- [ ] **Step 3: Implement Protocol.lua** builders and parse cases (set key `%l+`, ID `[^;%^]+`).
- [ ] **Step 4: Implement Share.lua:**
  - `OnHello`: for a `perFriend` set, ask when `rev ~= (row.sets[key] and row.sets[key].rev)` (its own revision is not
    compared); then call `set.greeted(friend.tag)` for each shared set that has it.
  - `OnData`: pass `friend.tag` as `import`'s second argument (existing sets ignore it).
  - New `M` handler: shared → `set.message(friend.tag, msg.text)`; not shared → queue
    `ns.Share_BuildRefusal(key, ns.Share_MessageID(msg.text))` back (no ID: drop). `X` handler: shared →
    `set.refused(friend.tag, msg.id)`.
  - `ns.Share_Send`: find the friend's gameAccountID by tag (`ns.Share_RosterFind(tag)` added to Roster.lua), refuse
    when blocked or not shared, queue the message, return true.
  - `ns.Share_Online(tag)`: the roster's character for that tag, or nil.
  - The `ns.Share_Register` comment documents the new fields.
- [ ] **Step 5: Run all tests** — pass.

### Task 3: Friend sharing on by default on Forever

**Files:**
- Modify: `Modules/Share/Share.lua` (`enabledByDefault`, description lists recipes)
- Modify: `Core/Migrations.lua` (append migration 17)
- Test: `tests/test_migrations.lua`

- [ ] **Step 1: Failing tests:**

```lua
test("Friend sharing: switched on once for Forever profiles, presets' off included", function()
	ns.FOREVER = true
	local db = { schema = 16, enabled = { share = false } }
	ns.RunMigrations(db, ns.MIGRATIONS)
	eq(db.enabled.share, true)
	ns.FOREVER = nil
	db = { schema = 16, enabled = { share = false } }
	ns.RunMigrations(db, ns.MIGRATIONS)
	eq(db.enabled.share, false, "retail keeps it")
	db = { schema = 16 }
	ns.RunMigrations(db, ns.MIGRATIONS)
	eq(db.enabled, nil, "fresh install: the module default decides")
end)
```

- [ ] **Step 2: Run** — FAIL.
- [ ] **Step 3: Implement** migration 17 (comment: the user's decision, presets wrote `false`, hand-picked off is switched
  on too) and `enabledByDefault = ns.FOREVER == true`. Description adds "your characters' professions and recipes, so
  friends can see what you craft".
- [ ] **Step 4: Run all tests** — pass.

### Task 4: Friend crafting rules (pure)

**Files:**
- Create: `Modules/Alts/FriendsData.lua` (pure; TOC after `Modules/Alts/ListData.lua`)
- Test: `tests/test_alts_friends.lua`

**Interfaces:**
- Payload: records `;`-terminated. `c<name>,<realm>,<faction A|H|>,<class>,<level>;` starts a character;
  `p<base>,<skill>,<max>=<recipeID>.<recipeID>...;` a profession of the last character;
  `r<recipeID>,<itemID>,<base>,<name>=<itemID>:<qty>.<itemID>:<qty>...;` a recipe (once per recipe). Names and realms
  have `;,:=.^|` replaced by spaces.
- Produces:
  - `ns.AltsFriends_Export(chars, recipes) -> payload`: every character with `profs`, sorted by name, recipes sorted by ID.
  - `ns.AltsFriends_Import(payload) -> data|nil, reason` with `data = { chars = { { name, realm, faction, class, level,
    profs = { [base] = { skill, max, known = { [id] = true } } } } }, recipes = { [id] = { item, base, name,
    reagents = { { items = { itemID }, qty } } } } }`.
  - `ns.AltsFriends_Merge(chars, recipes, friends, opts) -> chars2, recipes2`: copies; adds each reachable friend
    character under key `"friend:" .. tag .. ":" .. name .. "-" .. realm` with `friend = { tag, online, seen }`, and
    friend recipes missing locally (`friend = true`). `friends = { [tag] = { at, data } }`,
    `opts = { faction, realms, online = { [tag] = true } }`. Your own characters are never changed.
  - `ns.AltsFriends_Reachable(c, faction, realms) -> boolean`.
  - `ns.AltsFriends_NewRequest(fields) -> req` with `state = "waiting"`; `ns.AltsFriends_Apply(req, event) -> boolean`
    for events `sent`, `got`, `accepted`, `declined`, `made`, `done`, `cancel` along
    waiting→sent→(got)→accepted|declined, accepted→made→done, any open state→cancel; illegal ones return false.
  - `ns.AltsFriends_EncodeAsk(req) -> text` = `"<id>;ask;<recipeID>;<itemID>;<amount>;<mats 0|1>;<crafter>;<asker>;<askerRealm>"`,
    `ns.AltsFriends_EncodeAnswer(id, event) -> text` = `"<id>;<event>"`,
    `ns.AltsFriends_Decode(text) -> { id, kind, ... }|nil`.
  - `ns.AltsFriends_Materials(recipe, amount) -> { { itemID, count } }`.

- [ ] **Step 1: Failing tests** (`tests/test_alts_friends.lua`, loads `Modules/Alts/FriendsData.lua`):
  - export → import round trip: Mira (realm "Argent Dawn", faction "H", 1 profession, 2 recipes) comes back equal,
    reagents included.
  - a recipe named `"Bolt; of, Cloth:=|^."` imports as `"Bolt  of  Cloth"` with spaces collapsed or kept (either is
    fine) and the next record still reads.
  - garbage payload → `nil, reason`.
  - Merge: Kesha's character on another faction or unreachable realm is absent; a reachable one is present with
    `friend.tag == "Kesha#1234"` and `friend.online == true` when in `opts.online`; your own character table is
    the same table contents as before (no field added).
  - Apply: `ask`-made request starts `waiting`; `sent`, `got`, `accepted`, `made`, `done` succeed in order; `accepted`
    on a `done` request returns false; `cancel` works from `waiting` and `accepted`, not from `done`.
  - Encode/Decode round trip for ask and answer; decoding an unknown kind returns nil.
  - Materials: recipe with reagents `{ {items={2318},qty=8}, {items={783},qty=1} }` × 2 → 16 and 2.
- [ ] **Step 2: Run** `lua Tomte/tests/test_alts_friends.lua` — FAIL (file missing).
- [ ] **Step 3: Implement** `Modules/Alts/FriendsData.lua`; add the TOC line; run `forevertoc.lua` and `bugfiles.lua`.
- [ ] **Step 4: Run all tests** — pass; `luac -l` globals check on the new file.

### Task 5: Alts registers the `crafts` set and stores friends

**Files:**
- Create: `Modules/Alts/Friends.lua` (TOC before `Modules/Alts/Alts.lua`)
- Modify: `Modules/Alts/Alts.lua` (defaults, options row, init/toggle calls)
- Modify: `Modules/Alts/Collect.lua` (`ReadBasics` stores `c.faction = UnitFactionGroup("player")`; recipe scan end
  and skill change call `ns.AltsFriends_Changed()`)

**Interfaces:**
- Consumes: Task 2 set fields, Task 4 export/import/merge.
- Produces: `ns.AltsFriends_Start(db)`, `ns.AltsFriends_Stop()`, `ns.AltsFriends_Changed()`,
  `ns.AltsFriends_Merged(chars, recipes) -> chars, recipes` (unchanged tables when friends' crafting is off),
  `ns.AltsFriends_Online(tag) -> boolean`.
- Saved: `friendCrafts = {}, -- [BattleTag] = { at, data } (FriendsData.lua's import)`, `friendsShow = true`,
  `requests = {}, -- [id] = request (FriendsData.lua)`.

- [ ] **Step 1: Implement** registration in `init` (as Flight does): key `crafts`, label "Recipes", `perFriend = true`,
  `count(n, adj)` → "n characters' recipes", `export` from `ns.altsDB.chars/recipes`, `revision` = a hash of the payload
  (reuse how Flight's ShareData computes its revision), `import(payload, tag)` replaces `friendCrafts[tag]` and returns
  the number of characters, `active()` → Alts module active. `Changed` calls `ns.Share_Changed("crafts")`.
- [ ] **Step 2: Options row** in Alts: checkbox `friendsShow`, label "Friends' crafting", tooltip "Show what your
  friends' characters can craft on the Crafting tab. Needs Friend sharing; friends' characters show when mail can reach them."
- [ ] **Step 3: Run all tests**; `luac -l` globals check.

### Task 6: Crafting tab shows friends and asks them

**Files:**
- Modify: `Modules/Alts/CraftResults.lua` (search on merged tables, character choices, "Friends' crafting" checkbox beside
  Materials on hand)
- Modify: `Modules/Alts/CraftTab.lua` (`Names`: a friend's character as "Name (Kesha)", online dot via `UI.Wrap(..., "success")`
  or "last seen" via `ns.Ago`)
- Modify: `Modules/Alts/CraftDetail.lua` (an "Ask <name> to craft" button per friend crafter who knows the selected recipe)
- Create: `Modules/Alts/AskDialog.lua` (TOC after `CraftDetail.lua`)

**Interfaces:**
- Consumes: `ns.AltsFriends_Merged`, `ns.AltsFriends_Ask(friendChar, recipeID, amount, mats)` (Task 7).
- Produces: `ns.AltsAsk_Show(friendChar, recipeID)`.

- [ ] **Step 1:** `LayoutResults` and `CharChoices` use `ns.AltsFriends_Merged(S.db.chars, S.db.recipes)`; your characters
  first, then friends' as "Name (Kesha)". The material plan (`CraftDetail`, `PlanData`) keeps using `S.db.chars` only.
- [ ] **Step 2:** "Friends' crafting" checkbox (same build as Materials on hand) writes `friendsShow` and relayouts.
- [ ] **Step 3:** detail: a friend's recipe that isn't known locally shows its item (name, icon, tooltip) and the reagents
  from the friend's data; each friend crafter gets "Ask <name> to craft".
- [ ] **Step 4:** `AskDialog.lua`: `UI.Dialog` with the recipe label, amount `- n +` (1 to 200), `UI.Segmented`
  "I'll mail the materials" / "Use your materials", and an Ask button calling `ns.AltsFriends_Ask`.
- [ ] **Step 5: Run all tests**; globals check on changed files.

### Task 7: Requests: send, receive, answer, list

**Files:**
- Modify: `Modules/Alts/Friends.lua` (requests: `ns.AltsFriends_Ask`, message/refused/greeted handlers, answers)
- Create: `Modules/Alts/RequestsSection.lua` (TOC before `ListTab.lua`)
- Modify: `Modules/Alts/ListTab.lua` (one call to draw the section at the top; height added)

**Interfaces:**
- Produces: `ns.AltsFriends_Requests() -> { req }` sorted open first, newest first; `ns.AltsFriends_Answer(id, event)`;
  `ns.AltsRequests_Draw(parent, y, width) -> y`.

- [ ] **Step 1:** `Ask` creates the request (`ns.AltsFriends_NewRequest`, ID `tostring(time()) .. "-" .. random 4 digits`),
  stores it, tries `ns.Share_Send`; success → `sent`. `greeted(tag)` resends that friend's `waiting` (and `sent` without
  `got`) requests, once per hello.
- [ ] **Step 2:** `message(tag, text)`: decode; `ask` → new request with `mine = false`, answer `got`, toast
  "Aldric asks for 1 Light Leather Reagent Bag" (`ns.Toast_Show`, owner "alts"); an `ask` whose ID exists only answers
  `got` again. Answers update the request via `Apply`; `refused` marks it `declined` with note "not taking requests".
- [ ] **Step 3:** Requests section: one row per request: recipe label, who, state in words ("Waiting for Kesha to come
  online", "Sent", "Accepted", "Made", "Done", "Declined"); buttons by side and state: theirs open → Accept / Decline
  (Accept also `ns.AltsList_Add(recipeID, amount)`); yours open → Cancel (`ns.Confirm_Show`); finished → Clear.
- [ ] **Step 4:** Crafter side: when the bags hold `amount` of the item for an accepted request, it becomes `made`
  (checked on `BAG_UPDATE_DELAYED` while there are accepted requests).
- [ ] **Step 5: Run all tests.**

### Task 8: Mailbox block for friends

**Files:**
- Create: `Modules/Alts/FriendMail.lua` (TOC after `Send.lua`)
- Modify: `Modules/Alts/Send.lua` (export the dock as `ns.AltsSend_Dock()`; nothing else)

**Interfaces:**
- Consumes: requests, `ns.AltsFriends_Materials`, `ns.Alts_NextMail`, `ns.Alts_MailName`.

- [ ] **Step 1:** at `MAIL_SHOW`, groups: for your open requests with mats → "For Kesha: materials for 2 Light Leather
  Reagent Bag" (exactly the materials from your bags); for their `made` requests → "For Aldric: Light Leather Reagent Bag".
  Anchored under the Send dock when shown, else beside the mail frame.
- [ ] **Step 2:** Attach fills recipient (the friend character's mail name) and subject "Tomte: craft request";
  Send uses `SendMail`; `MAIL_SEND_SUCCESS` for an item group marks the request `done` and sends the answer.
- [ ] **Step 3: Run all tests**; globals check.

### Task 9: Docs and release notes

**Files:** `README.md` (Alts row, Friend sharing row, Forever theme default), `CHANGELOG.md` Unreleased.

- [ ] **Step 1:** README rows in player wording; CHANGELOG under New: "**Alts:** on Forever, see what your friends can
  craft, ask them for a craft and mail materials and the item with one click each." and Improved: "**Friend sharing:**
  on by default on Forever." / "**Tomte:** the Forever theme is the default on Forever."
- [ ] **Step 2:** All tests; one combined in-game test list for the user (below); commits per task after their check.

## In-game check (one list for the user, after Task 8)

Needs a friend on Forever with this Tomte:
1. `/reload`: Forever theme; Friend sharing on (Settings).
2. `/tomte share list` shows the friend (proves Battle.net game data works on Forever; if not, stop: the spec's fallback
   transport, addon whispers, becomes a new task).
3. Crafting tab: the friend's characters and recipes appear; the toggle hides them.
4. Ask an online friend: toast on their side, Accept, it appears on their Crafting list.
5. Ask while the friend is offline: "Waiting for …"; it arrives when they log in.
6. Mailbox: materials group on your side, item group on theirs once crafted; Send marks it Done on both sides.
7. Friend sharing off, or Friends' crafting off: nothing shows or sends.
