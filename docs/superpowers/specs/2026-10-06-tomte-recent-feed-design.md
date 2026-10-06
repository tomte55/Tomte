# Tomte: Recent feed

Date: 2026-10-06. Agreed with the user: choices are settings with defaults rather than fixed decisions.

## Goal

Tomte sends a lot of toasts (whispers, mentions, friends, upgrades, rares, Concentration, durability, achievements,
world quests, vendor summaries). A toast missed while tabbed out, in a fight or in a cinematic is gone for good.
**Recent** keeps the last toasts in a list you can come back to, with the same click actions.

## How entries get in

Every `ns.Toast_Show(spec)` (Social/Toast.lua) also calls `ns.Feed_Add(spec)`, so no module needs changing.
Banners (`ns.Banner_Show`: Moments, durability, hunter pet checks, pet health) are added too, without a click.

Entry: `{ at, owner, label, title, text, icon, iconAtlas, accent, onClick, count }`.

- `mergeKey` merges like the toast does (the entry's count goes up and moves to the top).
- **Secret text**: a whisper or mention shown during chat lockdown has secret text (`spec.secret`). It can't be
  stored or compared. The entry keeps the title (sender) and shows "(message hidden in combat)" instead; the
  Whispers inbox already has the real text once lockdown ends.
- Pinned toasts (`Toast_Pin`, e.g. "While you were away") are added once, when pinned.

## Storage

- In memory: the last 50 entries with their `onClick`.
- Saved (`TomteDB.feed[guid]`, last 30): text-only copies without closures. After a reload or login they show
  dimmed with no click. This also covers "what happened before my disconnect".

## Where it shows

- A **Recent** page in the Home rail, order after Alts: newest first, grouped "Today" / "Earlier", each row with
  icon, title, text, module label (in its accent color) and "5m ago". Click runs the action (only for this
  session's entries). A "Clear" button.
- A quick action in the hero column, "Recent", with the count of entries added while the Tomte window was closed
  ("unseen").
- Optional: a small unread dot on the minimap button when something was added while you were AFK or in combat.

## Options (module "Recent", category General, on by default)

| Setting | Choices | Default |
|---|---|---|
| Show as | Rail page + quick action / Block on Home (right column, under Next up) | Rail page + quick action |
| Scope | This character / Whole account (character name on each row) | Whole account |
| Include | a checkbox per toast owner (whispers, mentions, friends, loot/upgrades, achievements, collect, world quests, Concentration, durability, vendor) and one for banners | all on |
| Keep after reload | on/off | on |
| Entries kept | 20-100 | 50 |
| Dot on minimap button | on/off | off |

## Testing

- Plain Lua: add/merge/cap, unseen count, the saved copy dropping closures and secret text.
- In game: get a whisper in combat, check the entry; reload and check the saved rows are dimmed.
