# Autocorrect: design

2026-11-12. A new Chat-group module that fixes the player's chat message while they type it.

## Intent

Typos in chat are a small, constant irritation. The user saw a Forever-only addon ("Autocorrect Forever", shown in a
Reddit post with screenshots and a short video) that fixes words as you type and shows a small note above the chat box
with an undo on Backspace. They want the same quality-of-life feature in Tomte, on both retail and Forever, "as good as
it can be". We build our own: no code, word lists or curated tables are taken from that addon (Tomte is public and
GPL-3.0; see CLAUDE.md, Sharing).

Success: a friend turns it on, types normally, and their chat comes out clean without ever fighting the addon. A
correction that is wrong is rare, obvious and undone with one key.

## Goals

The module fixes, while typing:

| Kind | Example typed | Sent |
| --- | --- | --- |
| Spelling | `i wnat to recieve teh letter tommorow` | `I want to receive the letter tomorrow` |
| Any misspelling with one clear nearest word | `thinkk`, `winnning`, `stareing`, `kontest` | `think`, `winning`, `staring`, `contest` |
| Apostrophes | `dont worry, im sure hes fine` | `Don't worry, I'm sure he's fine` |
| Capitals | `hello there. how are you today` | `Hello there. How are you today` (and lone `i` -> `I`) |
| Names | `meet me in stormwind near old town` | `Meet me in Stormwind near Old Town` |
| Word pairs | `your late, we could of left by now` | `You're late, we could have left by now` |
| Tidying | `we went tothe the the inn` | `We went to the inn` (run-together words split, repeated words dropped) |

- **When a word is fixed:** when it is finished, i.e. the player types a space or punctuation after it. A word still
  being typed is never touched. Just before the message is sent (Enter), the last word gets the same pass, using
  Blizzard's `EventRegistry` event `"ChatFrame.OnEditBoxPreSendText"` (retail, `Blizzard_ChatFrameBase/Shared/
  ChatFrameEditBox.lua`; check what Forever's UI source offers and fall back to a hook on the edit box's send path).
- **The note:** after a fix, a small one-line note sits just above the chat edit box's left edge:
  `thinkk > think   Backspace undoes` (typed word, arrow, fix, faint hint). Theme colours and fonts (`UI.Text`, roles),
  not a copy of the other addon's look. It stays until the next fix replaces it, and hides when the message is sent,
  the edit box closes, or the player moves on to a new word (Backspace no longer undoes at that point).
- **Undo:** Backspace immediately after a fix puts back the word exactly as typed (and the space/punctuation that
  triggered it stays where it was). What's remembered (decided):
  - Word fixes (spelling, guesses, apostrophes, names, word pairs) are remembered **per pair**, typed text -> fix
    (`teh -> the`, `stormwind -> Stormwind`, `could of -> could have`), lowercased typed side. An undone pair is saved
    and never made again; the typed word may still get a different fix.
  - Tidying is remembered too: a split by the typed word (`tothe -> to the`), a doubled word by the pair
    (`the the -> the`).
  - Capitals at a sentence start are undone once only and not remembered: they depend on the sentence, not the word.
- **Commands:** `/tomte autocorrect keep <word>` protects a word for good; `/tomte autocorrect add <typo> <fix>` adds a
  correction of the player's own; plus `list`/`forget` to manage both, and a `why <word>` debug command that explains
  what it would do with a word and why.
- **Left alone, always:** slash commands (any line starting with `/`), item/spell/quest links and any `|` escape, web
  addresses, numbers and words with digits (`2h`, `ilvl540`), ALL-CAPS words (`LFG`, `AFK`, `WTS`), chat shorthand and
  dialect (`lol`, `brb`, `gg`, `ty`, `sooo`, `nothin'`, `goin`), and names of people (see below).
- **Settings** (module `options`): on/off per kind (spelling, apostrophes, capitals, names, word pairs, tidying),
  show the note, and buttons to clear the "kept" words and the player's own corrections.

## Non-goals

- No red squiggles or underlines in the edit box (the edit box can't draw them reliably; the note is the feedback).
- No grammar checking beyond the fixed word pairs, no rewriting style, no translating.
- Other languages than English. The module is English only, like Tomte.
- Fixing other people's chat. Only the player's own outgoing text in the chat edit box.
- Mail, the community/Battle.net chat box and other text fields: only the chat frames' edit boxes.

## Anti-goals (would make it a failure even if it works)

- Changing a word when unsure. When two candidates are about as good, or the word is unknown but plausible (a name, a
  slang word, a made-up guild term), leave it. A missed typo is far better than a wrong "fix".
- Mangling names: friends', guildmates', party members', the player's own characters, NPCs and places the dictionary
  doesn't know.
- Ever touching or breaking a slash command, macro text, link or a secure command.
- Any lag while typing, any Lua error, or any taint that breaks Blizzard's chat (see Constraints).
- Fighting the player: a word they undid comes back again.

## Constraints

- Both clients: retail 12.1.5 and Forever 1.60.1 (add to `tools/forever_list.lua`; edit box APIs through
  `Core/Compat.lua` where they differ).
- `enabledByDefault = false`: it changes what the player sends.
- Midnight: our own edit box text isn't a secret value, but check anything read from chat with `ns.IsSecret` /
  `canaccessvalue`.
- **Taint (retail), from EllesmereUIChat's in-game findings** (`_forever_\Interface\AddOns\EllesmereUIChat\
  EUI_Chat_EditBox.lua`, comments around lines 52-75 and 265-320; read only, never copy):
  - Once addon code has set the edit box's text, Blizzard's `SendText` is a tainted caller of
    `C_ChatInfo.SendChatMessage`. During chat messaging lockdown (`C_ChatInfo.InChatMessagingLockdown()`: boss
    encounters, Mythic+, PvP matches) such a message is silently dropped.
  - A `HookScript("OnTextChanged")` on a Blizzard chat edit box runs inside `Deactivate`'s `SetText("")`, right before
    Blizzard writes the box's `chatType`. That taints every later send, even untouched ones. **So: no `OnTextChanged`
    hook.** Drive fixes from hooks that only fire on real key presses (`OnChar`, `OnKeyDown`), plus the
    `EventRegistry` callbacks.
  - **During chat lockdown Autocorrect does nothing** (decided: a dropped raid message is far worse than a typo). The
    note shows a quiet "Autocorrect paused in combat chat" the first time the edit box opens in lockdown. Corrections
    resume when lockdown ends.
  - All of this must be measured in game on retail before release: a corrected `/s`, `/p` and whisper outside
    lockdown, an untouched message and a corrected-then-paused one inside a lockdown (e.g. a dungeon boss), and secure
    slash commands still working.
- Text that Autocorrect sets itself never triggers another fix.
- All chat edit boxes, including ones created later (new chat windows, temporary whisper windows).
- Memory and speed: the word list ships as a pure data file; building the lookup set happens on `toggle(true)` (lazy,
  freed on stop), not at load. Fixing a word must stay well under a millisecond on a normal word.
- Code shape per CLAUDE.md: pure files first, unit-tested; one module folder.

## Decided

- Folder `Modules/Autocorrect/`, module key `autocorrect`, name "Autocorrect", category `chat`.
- **Word list:** our own, generated by a tool in `tools/` from **SCOWL** (Spell Checker Oriented Word Lists, Kevin
  Atkinson; permissive licence, GPL-compatible; credit in README and the generated file's header). Around the SCOWL
  size-50 English list (roughly 30-50k words), American plus British spellings both accepted. The SCOWL size level of
  each word is kept as its commonness, used to rank candidates.
- **Known typos and fixes:** a hand-written table (ours) of common misspellings, apostrophe words and word pairs. It
  always wins over guessing.
- **Guessing:** for a word not in the dictionary, not protected and not shorthand: generate candidates within edit
  distance 1 (delete, insert, replace, swap of neighbours), and distance 2 only for longer words; rank by distance,
  then commonness, then a keyboard-neighbour bonus. Fix only when the best candidate clearly beats the next one.
  Otherwise leave it.
- **Names:** a hand-kept list of place names (zones, cities, districts like Old Town) per expansion through
  `ns.Content_Register`-style data or a pure table, plus names the client can tell us at runtime. People's names
  (friends, guild, group, the player's alts) are never corrected; a capitalised word mid-sentence that the dictionary
  doesn't know is treated as a name and left alone.
- **The undo memory and the player's own words** are saved in `TomteDB.autocorrect` (account-wide):
  `refused = {}` ([typed lowercase] = { [fix] = true }), `keep = {}` ([word lowercase] = true), `own = {}`
  ([typo lowercase] = fix). `list`/`forget` and the settings' clear buttons cover all three.

## Left to the builder

- The exact data format of the word list (one long string split on enable, a trie, length-bucketed tables), as long as
  load cost and memory are reasonable and it's measured.
- How the last-word pass on send works on Forever.
- How runtime names are gathered (map names, friend/guild/group rosters) and kept up to date.
- The exact "clearly beats" threshold, tuned with tests of real typos.
- Note position and fade, within "small, one line, above the edit box's left edge, theme colours".
- Splitting run-together words: only when both halves are common words and the joined form isn't a word.
- The shorthand/dialect list and the known-typo list contents (ours, written fresh).
- README, CHANGELOG and tests per CLAUDE.md's new-module checklist.
