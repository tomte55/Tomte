# Autocorrect Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or
> superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A new Chat-group module, `autocorrect`, that fixes the player's chat line as they type, with a note above the
edit box and Backspace undo, on retail and Forever.

**Architecture:** A generated word list (`Words.lua`, from SCOWL by a Python tool) and hand-written tables (`Data.lua`)
feed two pure files: `Rules.lua` decides what to do with one word, `Line.lua` applies it to the edit box's text and
cursor and builds the undo. `Note.lua` draws the note; `Autocorrect.lua` hooks the chat edit boxes (key-press hooks
and `EventRegistry` callbacks only), owns the db, settings and commands.

**Tech Stack:** Lua 5.1 (WoW), Python 3 for the word-list tool, plain-Lua tests with `tests/harness.lua`.

**Spec:** `docs/superpowers/specs/2026-11-12-autocorrect-design.md`

## Global Constraints

- Retail 12.1.5 and Forever 1.60.1; `Modules/Autocorrect/` added to `tools/forever_list.lua` keep list.
- `enabledByDefault = false`, `category = "chat"`, key `autocorrect`, name "Autocorrect".
- **No `HookScript("OnTextChanged")`** and no hooks on temp whisper edit boxes (chat frames above `NUM_CHAT_WINDOWS`):
  both taint Blizzard's chat (EllesmereUIChat's in-game findings, spec Constraints). Only `OnChar` / `OnKeyDown`
  hooks on `ChatFrame1EditBox`..`ChatFrame<NUM_CHAT_WINDOWS>EditBox` and `EventRegistry` callbacks
  (`ChatFrame.OnEditBoxPreSendText`, `ChatFrame.OnEditBoxHide`; both exist on retail `live` and the `forever` branch).
- Nothing during chat lockdown: `C_ChatInfo.InChatMessagingLockdown()` (if present), `GetCVarBool(
  "addonChatRestrictionsForced")`, or an active challenge mode.
- Lines starting with `/` are never touched; nor words inside a link (`|H...|h`), with `|`, digits, URLs, ALL CAPS
  (2+ letters), non-ASCII letters, a trailing apostrophe, an end-of-word elongation (`sooo`, `yesss`), shorthand, kept
  words, people's names.
- Hand tables are written fresh; nothing copied from "Autocorrect Forever". SCOWL credited (README Credits, the
  generated file's header, the tool's header).
- CRLF line endings; Lua edited with Edit/Write only. Colours/fonts by theme role only.
- Saved: `TomteDB.autocorrect` = `kinds = { spelling, apostrophes, capitals, names, pairs, tidying }` (all true),
  `note = true`, `refused = {}` ([typed lower] = { [fix] = true }), `keep = {}` ([word lower] = true),
  `own = {}` ([typo lower] = fix).

## Review Focus

1. A name of a friend, guildmate, group member or the player's own character typed in lowercase mid-sentence (`ask
   kesha`): left alone, never guessed into a dictionary word. Test in Task 2 (`names are never guessed`).
2. A word typed right after an item link (`[Linen Cloth] pls`), and a word inside the link's text: the one after is
   fixed, the link is byte-for-byte unchanged. Test in Task 3 (`link stays intact`).
3. Backspace pressed after the player moved the cursor or typed more since the fix: normal Backspace, no undo. Test in
   Task 3 (`undo only right after`).
4. Very long garbage words (`asdfghjklqwerty`) and long lines: no guess, under 5 ms. Test in Task 2 (`garbage is left
   and fast`).
5. A two-word place name split by the pair pass while the first word was already fixed alone (`old` stays a word, then
   `town` makes `Old Town`); undo of the pair restores both words as typed. Test in Task 3 (`pair undo`).

---

### Task 1: Word list tool and generated `Words.lua`

**Files:**
- Create: `tools/autocorrect_words.py`
- Create (generated): `Modules/Autocorrect/Words.lua`

**Interfaces:**
- Produces: `ns.AUTOCORRECT_WORDS = { [level] = "word\nword\n..." }` for levels 10, 20, 35, 40, 50, 55, 60 (english +
  american + british words of that SCOWL size, lowercase-only ASCII words, no duplicates across levels, the lowest
  level wins); `ns.AUTOCORRECT_UPPER = "English\nMonday\n..."` (english/american/british `upper` lists up to 50, ASCII,
  single words); `ns.AUTOCORRECT_CONTRACTIONS = "don't\nI'm\n..."` (english-contractions up to 50).

- [ ] **Step 1:** Write the tool: `python -I tools/autocorrect_words.py <scowl-2020.12.07/final> Modules/Autocorrect/Words.lua`.
  Header comment: source URL (`https://downloads.sourceforge.net/project/wordlist/SCOWL/2020.12.07/scowl-2020.12.07.tar.gz`),
  SCOWL's copyright notice verbatim, "generated, don't edit". Input files are ISO-8859-1. Output CRLF, one long string
  per level (long-bracket strings, `[==[ ... ]==]`), first line `local addonName, ns = ...`.
- [ ] **Step 2:** Run it; check the file loads with `lua -e 'local ns={} loadfile("Tomte/Modules/Autocorrect/Words.lua")("Tomte",ns) ...'`
  and the counts per level are printed by the tool (expect about 80k words through 50, about 100k through 60).
- [ ] Commit together with Task 2 (the tool's output is only used there).

### Task 2: `Data.lua` and `Rules.lua` (one word)

**Files:**
- Create: `Modules/Autocorrect/Data.lua`, `Modules/Autocorrect/Rules.lua`
- Test: `tests/test_autocorrect.lua`

**Interfaces:**
- `Data.lua` produces (hand-written, ours): `ns.AUTOCORRECT_TYPOS` ([typo] = fix, ~300 common English misspellings
  incl. `teh`, `recieve`, `tommorow`, `wnat`, `definately`, `seperate`), `ns.AUTOCORRECT_APOSTROPHES` ([bare] = with
  apostrophe: `dont`, `cant`, `wont`, `im`, `ive`, `youre`, `theyre`, `thats`, `whats`, `hes`, `shes`, `didnt`,
  `doesnt`, `isnt`, `wasnt`, `arent`, `werent`, `havent`, `hasnt`, `wouldnt`, `couldnt`, `shouldnt`, `youll`, `youve`,
  `theyll`, `theyve`, `weve`, `wouldve`, `couldve`, `shouldve`, `theres`, `wheres`, `whos`, `aint`; never `ill`, `its`,
  `were`, `well`, `hell`, `shell`, `lets`, `id`), `ns.AUTOCORRECT_PAIRS` (list of `{ first, second, fix1, fix2 }`
  matched case-insensitively on the two last words: `could of`/`would of`/`should of`/`must of` -> `have`, `your`
  + `late|welcome|right|wrong|not|going|so|too|the best` -> `you're`, `ill` + common verbs (`be`, `meet`, `see`, `go`,
  `do`, `get`, `have`, `try`, `take`, `make`, `need`, `come`, `wait`, `brb`) -> `I'll`, `its` + `been|a|an|not|the|so|ok|okay|fine|just|going|time|over|all` -> `it's`, `alot` handled as a typo -> `a lot`), `ns.AUTOCORRECT_DOUBLES_OK` (`had had`, `that that`, `bye bye`, `ha ha`, `very very`, `so so`, `no no`, `go go`, `really really`),
  `ns.AUTOCORRECT_SHORTHAND` (set: `lol`, `lmao`, `brb`, `afk`, `gg`, `ty`, `thx`, `np`, `pls`, `plz`, `omg`, `idk`,
  `imo`, `btw`, `ok`, `k`, `kk`, `gz`, `grats`, `wb`, `gl`, `hf`, `lfg`, `lfm`, `wts`, `wtb`, `ilvl`, `dps`, `tank`,
  `heals`, `mats`, `xp`, `rep`, `inc`, `oom`, `cc`, `aoe`, `dot`, `buff`, `nerf`, `goin`, `nothin`, `somethin`, `u`,
  `ur`, `ya`, `yeah`, `yep`, `nope`, `nah`, `hmm`, `heh`, `haha`, `hehe`, `ugh`, `wow`, `nvm`, `irl`, `tbh`, `ffs`,
  `wtf`, `rofl`, `tho`, `cya`, `gn`, `gm`, `sry`, `mb`, `w/e`, `boe`, `bop`, `ah`, `rdy`, `r`, `y`, `n`, `m`, `x`),
  `ns.AUTOCORRECT_PLACES` (list of proper place names, single and multi-word, Azeroth's main cities, districts and
  zones across expansions: `Stormwind`, `Old Town`, `Trade District`, `Orgrimmar`, `Ironforge`, `Darnassus`,
  `Undercity`, `Thunder Bluff`, `Silvermoon`, `Exodar`, `Shattrath`, `Dalaran`, `Booty Bay`, `Gadgetzan`, `Valdrakken`,
  `Dornogal`, `Elwynn Forest`, `Westfall`, `Durotar`, `Ashenvale`, `Stranglethorn`, `Tanaris`, `Winterspring`, ...),
  `ns.AUTOCORRECT_KEYS` (QWERTY rows for the keyboard-neighbour bonus).
- `Rules.lua` produces:
  - `ns.Autocorrect_NewDict(words, upper, contractions) -> dict` with `dict.level[word] = level`,
    `dict.upper[lower] = Proper`, `dict.contraction[bare lower] = with apostrophe` (from SCOWL, only where the bare form
    isn't a word and isn't in the never list).
  - `ns.Autocorrect_Skip(word) -> bool` (all the "left alone" word rules of Global Constraints except people/keep).
  - `ns.Autocorrect_Word(word, ctx) -> fix|nil, kind|nil, reason` where `ctx = { dict, kinds, own, keep, refused,
    names, places, sentenceStart }`; `names[lower] = true` (people), `places[lower] = Proper` (single words; multi-word
    places are the pair pass's). Order: skip / keep / people -> own -> typos -> apostrophes -> places & upper ->
    dictionary hit (nothing) -> split -> guess. A capitalised word that isn't at `sentenceStart` and isn't in the
    dictionary is a name: nothing. Every fix keeps the typed word's leading capital. A refused pair is never returned.
    `reason` is a short player-wording string for `why`.
  - `ns.Autocorrect_Guess(word, dict) -> fix|nil` (lowercase in, lowercase out): words of 4+ letters only; distance 1
    candidates (delete, insert, replace, adjacent swap); distance 2 only for 6+ letters (edits of the distance-1
    deletes and swaps, bounded); candidates only from levels <= 50. Score: distance, minus 0.5 for an adjacent swap, a
    doubled/tripled-letter delete or a keyboard-neighbour replace; tie-break by level. Return the best only if it beats
    the runner-up by at least one score step or one SCOWL level band; else nil.
  - `ns.Autocorrect_Split(word, dict) -> "left right"|nil`: both halves level <= 35, each 2+ letters (or `a`), the
    joined word not a word; only when exactly one split qualifies.

- [ ] **Step 1: Write the failing tests** in `tests/test_autocorrect.lua` (loads Words, Data, Rules; builds the real
  dict once). Assertions (word -> expected):
  - typos: `teh`->`the`, `recieve`->`receive`, `tommorow`->`tomorrow`, `wnat`->`want`, `Teh`->`The`
  - guesses: `thinkk`->`think`, `winnning`->`winning`, `stareing`->`staring`, `kontest`->`contest`,
    `fountian`->`fountain`
  - apostrophes: `dont`->`don't`, `im`->`I'm`, `hes`->`he's`, `Dont`->`Don't`; `ill`, `its`, `were`, `well` -> nil
  - capitals/names: `i`->`I`, `stormwind`->`Stormwind`, `english`->`English`; `will` -> nil
  - split: `tothe`->`to the`, `alot`->`a lot`
  - left alone (nil): `lol`, `brb`, `gg`, `sooo`, `yesss`, `nothin'`, `goin`, `LFG`, `AFK`, `2h`, `ilvl540`,
    `www.wowhead.com`, `http://x.y`, `café`, `Aldric` (mid-sentence), `kesha` with `names.kesha = true`,
    `teh` with `keep.teh = true`, `teh` with `refused.teh = { the = true }`
  - own: `own.wtv = "whatever"` -> `wtv`->`whatever`
  - kinds: `kinds.spelling = false` -> `teh` nil; `kinds.apostrophes = false` -> `dont` nil
  - `names are never guessed`: `names.kesha`; `kesha` -> nil; `Kesha` mid-sentence -> nil
  - `garbage is left and fast`: `asdfghjklqwerty` -> nil, and 200 `Autocorrect_Word` calls on mixed words take < 1 s
    (`os.clock`), single worst case < 5 ms on average.
- [ ] **Step 2:** `lua Tomte/tests/test_autocorrect.lua` -> FAIL (files missing).
- [ ] **Step 3:** Write `Data.lua` and `Rules.lua` (pure, header per CLAUDE.md).
- [ ] **Step 4:** Tests pass; tune `Guess` thresholds against them, not the other way round.
- [ ] **Step 5:** Commit `Autocorrect: word list and word rules` (no TOC yet; files unused by the addon until Task 4).

### Task 3: `Line.lua` (the edit box line)

**Files:**
- Create: `Modules/Autocorrect/Line.lua`
- Test: `tests/test_autocorrect_line.lua`

**Interfaces:**
- Consumes: `ns.Autocorrect_Word`, `ns.AUTOCORRECT_PAIRS`, `ns.AUTOCORRECT_DOUBLES_OK`, `ctx` as in Task 2 plus
  `ctx.places2[lower "a b"] = "A B"` (multi-word places).
- Produces:
  - `ns.Autocorrect_Finish(text, cursor, ctx, atEnd) -> newText, newCursor, change|nil`. `cursor` is a byte offset just
    after the boundary character the player typed (or the end of text when `atEnd`, the send pass, which has no
    boundary). Looks at the word ending right before the boundary: line skip (`/`), link check, then in order pairs
    (with the word before), doubled word, the word itself, sentence-start capital. `change = { kind, typed, fix,
    from, to, before, after }` where `before`/`after` are the full line texts (for undo and the note's
    `typed > fix`; for a pair `typed`/`fix` show both words).
  - `ns.Autocorrect_Undo(text, cursor, change) -> newText, newCursor | nil` returns the line as typed with the cursor
    where it was before the fix, only if `text == change.after` and the cursor equals the one Finish returned.
  - `ns.Autocorrect_LineSkipped(text) -> bool`.
- [ ] **Step 1: Failing tests** (`tests/test_autocorrect_line.lua`), each `Finish` on text with cursor at the end:
  - `"pass me teh "` -> `"pass me the "`, change typed `teh` fix `the`
  - `"hello there. how "` -> `"hello there. How "`; first word of a line `"hello "` -> `"Hello "`
  - `"we could of "` -> `"we could have "`; `"your late "` -> `"you're late "`; `"ill meet "` -> `"I'll meet "`
  - `"near old town,"` -> `"near Old Town,"`
  - `"to the the "` -> `"to the "`; `"bye bye "` unchanged
  - `"/who teh "` unchanged; `"/w Kesha teh "` unchanged
  - `link stays intact`: `"|cff9d9d9d|Hitem:2589::::::::80:::::|h[Linen Cloth]|h|r pls teh "` -> only `teh` fixed; a
    line with an open `|H` before the word -> unchanged
  - send pass: `Finish("see you tommorow", 16, ctx, true)` -> `"see you tomorrow"`
  - `undo only right after`: Undo of the `teh` change on its `after` text returns `"pass me teh "` and cursor 12;
    Undo with a different text or cursor -> nil
  - `pair undo`: `"near old town,"` then Undo -> `"near old town,"` as typed
- [ ] **Step 2:** Run -> FAIL. **Step 3:** Implement. **Step 4:** Run -> PASS.
- [ ] **Step 5:** Commit `Autocorrect: line rules and undo`.

### Task 4: Module, note, hooks, settings, commands, docs

**Files:**
- Create: `Modules/Autocorrect/Note.lua`, `Modules/Autocorrect/Autocorrect.lua`
- Modify: `Tomte.toc` (after `Modules/Chat/Copy.lua`: Words, Data, Rules, Line, Note, Autocorrect), 
  `tools/forever_list.lua` (keep `"Modules/Autocorrect/"`), then `lua Tomte/tools/forevertoc.lua` and
  `lua Tomte/tools/bugfiles.lua`; `README.md` (module row, commands, Layout, Credits: SCOWL), `CHANGELOG.md`
  (Unreleased, `### New`: `- **Autocorrect (new module):** ...`), `.gitattributes` not needed (tool under tools/).

**Interfaces:**
- `Note.lua` produces `ns.AutocorrectNote_Show(editBox, typed, fix)`, `ns.AutocorrectNote_Paused(editBox)`,
  `ns.AutocorrectNote_Hide()`. One frame, created lazily, `UI.Panel`-style dark surface, `UI.Text` in `body` font;
  text `typed > fix` then `Backspace undoes` in `textFaint`; anchored `BOTTOMLEFT` to the edit box's `TOPLEFT` (+2 y),
  parent UIParent, strata of the edit box + 1 level. Paused text: "Autocorrect paused in combat chat".
- `Autocorrect.lua`:
  - `defaults` as in Global Constraints. `init`, `toggle(active)`: on start build the dict (once per session, kept
    while active, dropped on stop with `collectgarbage` left to the game), gather names; register events
    `FRIENDLIST_UPDATE`, `GUILD_ROSTER_UPDATE`, `GROUP_ROSTER_UPDATE`, `BN_FRIEND_INFO_CHANGED` (retail only) to refresh
    names (debounced with `UI.Debounce`); on stop unregister, hide the note, clear pending.
  - People: friends (`C_FriendList.GetNumFriends`/`GetFriendInfoByIndex`), guild (`GetNumGuildMembers`/
    `GetGuildRosterInfo`), group (`UnitName` over `party1..4` / `raid1..40`), the player; names with realm cut at `-`;
    check `ns.IsSecret` on every name. Places: `ns.AUTOCORRECT_PLACES` plus, once per session, names of zone/city maps
    from `C_Map.GetMapChildrenInfo(<cosmic or world root>, Enum.UIMapType.Zone, true)` (pcall: may be missing); words
    that are dictionary words in lowercase are not added as single-word places.
  - Hooks, once, on `_G["ChatFrame" .. i .. "EditBox"]` for `i = 1, NUM_CHAT_WINDOWS`: `HookScript("OnChar", fn)`,
    `HookScript("OnKeyDown", fn)`; both return at once unless `module.active`. OnChar: if the char is a boundary
    (space or one of `.,!?;:)"`), not restricted, line not skipped: `Finish`, then `SetText` + `SetCursorPosition`, keep
    `pending = { box, change, text, cursor }`, show the note (if `db.note`). Any other OnChar clears `pending` and hides
    the note. OnKeyDown `BACKSPACE` with `pending` for this box and `Undo` non-nil: set the text to the undone line
    with one extra character placed before the cursor so the box's own Backspace (which runs after OnKeyDown) removes
    it; remember the refusal for word kinds (spelling, apostrophes, names, pairs) in `db.refused`; hide the note.
    **Measure in game**; if the box acts before OnKeyDown on a client, fall back to `C_Timer.After(0, ...)` setting the
    undone line (comment the measurement either way).
  - `EventRegistry:RegisterCallback("ChatFrame.OnEditBoxPreSendText", fn, OWNER)`: if active, not restricted and the
    box is one of ours: `Finish(text, #text, ctx, true)` and `SetText` the result. `"ChatFrame.OnEditBoxHide"`: hide
    note, clear pending. Unregister both on stop.
  - Restricted: show `ns.AutocorrectNote_Paused` once per lockdown when a boundary char is typed; do nothing else.
  - Options: header "Fixes": checkboxes `kinds.spelling` ("Spelling", tooltip "Common typos, and words with one clear
    nearest match: teh, recieve, kontest."), `kinds.apostrophes` ("Apostrophes": dont, im), `kinds.capitals`
    ("Capitals": start of a sentence, i), `kinds.names` ("Place names": stormwind, old town), `kinds.pairs` ("Word
    pairs": could of, your late), `kinds.tidying` ("Tidying": the the, tothe); header "Note": `note` ("Show what was
    fixed", tooltip about Backspace); header "Your words": buttons "Clear kept words" / "Clear your corrections" /
    "Clear undone fixes" with `confirm`.
  - Commands: `keep <word>`, `add <typo> <fix>`, `forget <word>` (from keep, own and refused), `list`, `why <word>`.
  - `icon`: a file ID checked to exist (e.g. `INV_Inscription_Scroll` family; check warcraft.wiki.gg / the client),
    `summary`: "Fixes typos in your chat as you type; Backspace undoes a fix.", `description`, `uses`/`conflicts`:
    none known.
- [ ] **Step 1:** Write `Note.lua`, `Autocorrect.lua`, TOC and Forever list; regenerate Forever TOC and BugFiles.
- [ ] **Step 2:** `luac -l` globals check on every new file; all tests green
  (`for t in Tomte/tests/test_*.lua; do lua "$t" >/dev/null 2>&1 || echo "FAIL $t"; done`).
- [ ] **Step 3:** README, CHANGELOG.
- [ ] **Step 4:** In-game test list for the user (retail and Forever): typing fixes, note, Backspace undo, Enter on the
  last word, `/who teh`, item link line, whisper and party, a boss fight / M+ (paused note, message arrives), turning
  the module off mid-session.
- [ ] **Step 5:** Commit only after the user confirms in game: `Autocorrect (new module): fixes your chat as you type`.
