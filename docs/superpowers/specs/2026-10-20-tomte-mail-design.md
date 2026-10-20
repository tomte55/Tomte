# Mail (`mail`): design

2026-10-20. Part of the addon round (`2026-10-20-tomte-addon-round-overview.md`, module 1). Postal has no Midnight
update planned; this module covers the parts of it friends use most. Every decision below marked "(Claude's call)"
was handed to Claude by the user ("pick sensible defaults, we tweak after").

## Intent

At a mailbox: one click empties the inbox of gold and items without touching letters that need a decision (cash on
delivery, GM letters), and tells you what came in (gold, Auction House sales, purchases, expired and cancelled
auctions, outbids). On the Send tab: pick one of your own characters or someone you mailed lately instead of typing.

## Goals

- "Open all" on the inbox: gold and items letter by letter, paced like Blizzard's own, never COD or GM letters.
- Gold only (Shift-click, or a setting that makes it the default and Shift the other way).
- Auction House letters only (setting): players' letters are left for you to read. (Claude's call: Postal had it,
  and it's the most common reason to not want "everything".)
- Bags full: items are left, gold is still taken, the summary says so.
- Summary at the end: chat line (`ns.Print`), a card (`ns.Toast_Show`, so Recent gets it too) and a session recap
  note (`ns.Session_Note("mail", ...)`). Gold through `ns.Price`.
- Send tab: a picker button next to the To box (`UI.ContextMenu`) with "Mailed lately" (last 5 recipients per
  character) and "Your characters" (both factions, realms mail reaches).
- Fully off when disabled: Blizzard's Open All back, Tomte's buttons hidden, no events, the SendMail hook inert.

## Non-goals

- No auto-open on MAIL_SHOW (button-driven only; nothing happens on its own).
- No paying COD letters, no returning or deleting letters, no bulk sending, no mail forwarding rules.
- No "Open next" one-press mode: not needed (see API findings).
- No key binding (nothing to press outside the mail frame).

## Defaults

On by default (`enabledByDefault = true`): nothing happens without a click. Settings: Open all button on, gold only
off, Auction House only off, summary in chat on, summary card on, character picker on.

## API findings (verified 2026-10-20)

- **Blizzard has its own Open All in 12.1.** `Blizzard_MailFrame/MailFrame.xml` defines `OpenAllMail`
  (UIPanelButtonTemplate, `OpenAllMailMixin`) in `InboxFrame`, anchored CENTER to BOTTOM (-21, 114), 120x24.
  `MailFrame.lua` (live branch, https://github.com/Gethe/wow-ui-source/blob/live/Interface/AddOns/Blizzard_MailFrame/MailFrame.lua):
  OnUpdate loop, `OPEN_ALL_MAIL_MIN_DELAY = 0.15` s between takes and then waits while `C_Mail.IsCommandPending()`;
  skips GM letters and COD letters; takes `TakeInboxMoney` first then `TakeInboxItem` from slot `ATTACHMENTS_MAX`
  down; remembers item IDs from `MAIL_FAILED` and skips them; **stops completely when
  `C_Container.CalculateTotalNumberOfFreeBagSlots() == 0`** (gold in later letters is left); no gold-only mode, no
  AH-only mode, no summary. It calls `C_Mail.SetOpeningAll(true/false)` around its run (undocumented effect; wiki page
  is a stub).
  - Decision (Claude's call): improve rather than duplicate. While the module and "Open all button" are on, Blizzard's
    button is hidden (its OnHide stops any run of its own) and Tomte's button sits in the same spot; Blizzard's comes
    back when the setting or module turns off. Tomte copies Blizzard's pacing and skip rules and adds gold only, AH
    only, gold-after-bags-full and the summary. Tomte does not call `C_Mail.SetOpeningAll` (effect unknown).
  - Blizzard never shows or hides `OpenAllMail` itself, so the hide stays until Tomte undoes it.
- **No hardware event needed.** https://warcraft.wiki.gg/wiki/API_TakeInboxMoney and
  https://warcraft.wiki.gg/wiki/API_TakeInboxItem carry no `#hwevent`/restricted tag; Blizzard's own loop calls them
  from OnUpdate; Patch 12.0.0, 12.0.5, 12.0.7, 12.1.0 and 12.1.5 API change pages mention nothing about mail. So the
  button runs a paced loop (a `C_Timer` ticker only while running), not "Open next". `AutoLootMailItem` has no wiki
  page and isn't used. `SendMail` is `{{restrictedapi|noscript}}` (protected from /run only); Tomte only hooks it.
- `GetInboxHeaderInfo(i)` -> `..., sender, subject, money, CODAmount, daysLeft, hasItem, ..., isGM`
  (https://warcraft.wiki.gg/wiki/API_GetInboxHeaderInfo). `GetInboxItem(i, slot)` -> `name, itemID, ...`.
  `HasInboxItem(i, slot)` has no wiki page; used exactly as Blizzard's MailFrame.lua uses it.
- **AH letter kinds.** `GetInboxInvoiceInfo(i)` (https://warcraft.wiki.gg/wiki/API_GetInboxInvoiceInfo) returns
  invoiceType `"seller"` (sold), `"buyer"` (won), `"seller_temp_invoice"` (sale pending, no gold yet) or nil. Expired,
  cancelled and outbid letters have no invoice: they are matched by subject against Blizzard's localized globals
  (enUS values from Ketho/BlizzardInterfaceResources live GlobalStrings): `AUCTION_EXPIRED_MAIL_SUBJECT`
  ("Auction expired: %s"), `AUCTION_REMOVED_MAIL_SUBJECT` ("Auction canceled: %s"), `AUCTION_OUTBID_MAIL_SUBJECT`
  ("Outbid on %s"), `AUCTION_SOLD_MAIL_SUBJECT`, `AUCTION_WON_MAIL_SUBJECT`, `AUCTION_INVOICE_MAIL_SUBJECT`. Formats
  are turned into anchored Lua patterns (`%s` and positional `%1$s`), so every client language works.
- Inbox refills: the inbox shows at most 50 letters; Blizzard's `InboxFrame_Update` calls `MailFrame_RefreshInbox`
  (throttled by `C_Mail.CanCheckInbox`, about once a minute) when fewer than 50 show and more wait. Tomte waits up to
  70 s for them while the button says "Stop".
- `MAIL_FAILED(itemID?)`, `MAIL_SEND_SUCCESS`, `MAIL_SHOW`, `MAIL_CLOSED`, `MAIL_INBOX_UPDATE` from
  `MailInfoDocumentation.lua`. `UnitFactionGroup("player")` -> "Alliance" / "Horde" / "Neutral".
- Secret values: the mail API returns plain values (its `SecretArguments = "AllowedWhenUntainted"` only concerns
  secret arguments, which Tomte never passes). Taking mail isn't protected; nothing here depends on combat.

## How Open all works

Each tick (0.15 s, a ticker that exists only during a run): read the inbox, tally emptied letters, pick the next
step (`ns.Mail_NextStep`), decide (`ns.Mail_Decide`: wait while a command is pending or within 0.15 s of the last
take; take; wait for more mail; done).

- Step order: letters in inbox order; gold first, then items from the last slot down. Skipped: COD, GM, players'
  letters when AH only, items when gold only, item IDs the server refused (`MAIL_FAILED`), stuck steps.
- Bags full: item steps are passed over while gold continues; the run notes `bagsFull`.
- Stuck guard: the same step sent 5 times while the inbox signature (letters, gold, items) didn't change is skipped.
  A repeated step key alone isn't enough: two identical sale letters share a key.
- Tally: letters with something left to take are counted by kind before and after each tick; drops are opened
  letters (new mail arriving only raises counts). The gold total is `GetMoney()` at the end minus at the start.
- End: summary title "1,234g from 18 letters", detail "5 sold, 2 won, 3 expired, 1 cancelled, 2 outbid, 5 other",
  note "4 left: bags full, 2 cash on delivery". Stopped by hand, by closing the mailbox or by turning the module off:
  the summary still shows if anything was taken.

## Send tab picker

A small "v" button right of the To box opens a `UI.ContextMenu`: "Mailed lately" (this character's last 5
recipients, from a `hooksecurefunc("SendMail")` recorded on `MAIL_SEND_SUCCESS`, so the Alts module's sends count
too) and "Your characters" in class colors. Picking fills the To box and moves focus to Subject.

- The character list: every character the Alts module knows (`ns.Alts_Characters()`, added for this), merged with
  Mail's own small roster (`db.chars[guid] = { name, realm, faction, class, recent }`, filled whenever a character
  logs in with the module on) so the picker still works with Alts off. Changed after the first in-game test: the
  roster alone left the list empty until each character had logged in with Mail. Realms come from the Alts module's existing `ns.Alts_MailRealms`,
  `ns.Alts_Reachable` and `ns.Alts_MailName` (looked up at call time; own realm only without them).
- Both factions: your own characters on the same or a connected realm can mail each other across factions
  (https://warcraft.wiki.gg/wiki/Mail). Only unchosen "Neutral" Pandaren are left out.

## Settings (group `professions`)

Inbox: Open all button; Gold only by default; Only Auction House letters; Summary in chat; Summary card.
Send: Character picker.

## Commands

- `/tomte mail open`: at a mailbox, open all (again: stop).
- `/tomte mail gold`: at a mailbox, take only the gold.
- `/tomte mail why`: at a mailbox, list each letter, its kind and what Open all does with it.

## Test plan (in game)

1. `/reload`, open a mailbox with some letters. The inbox shows Tomte's themed "Open all" button where Blizzard's
   was; Blizzard's "Open All" is gone. Hover: tooltip explains click and Shift-click.
2. `/tomte mail why`: one line per letter with sender, subject, kind (sold/won/expired/cancelled/outbid/other) and
   "take ..." or why it's left. Check AH letters get the right kind.
3. Click Open all: the label turns "Stop", letters empty one by one at about Blizzard's speed, no errors. At the end:
   a chat line "Tomte: mail: 123g from 9 letters (3 sold, ...)." and a card with the same. With the Session recap on,
   the recap lists a "Mail: ..." entry.
4. A COD letter (send one from an alt with COD) stays in the inbox; the summary notes "1 cash on delivery".
5. Shift-click with gold and item letters: only gold is taken, item letters stay; summary says "N left: items, gold
   only".
6. Fill your bags to 0 free slots, then Open all with gold and item letters: gold is taken, items stay, summary says
   "N left: bags full".
7. Click Stop mid-run: it stops at once with a summary of what was taken. Close the mailbox mid-run: same.
8. Settings > Mail: turn "Open all button" off: Blizzard's Open All is back at once (mailbox open). Turn the module off:
   same, and the picker is gone. Turn it on again: Tomte's button is back.
9. Send tab: click "v" next to To. After logging in on an alt (either faction) on this or a connected realm (with
   Tomte), it's listed in its class color; pick it: the To box fills, focus moves to Subject. Send a mail to anyone;
   reopen the menu: they're under "Mailed lately".
10. BugSack: no errors through all of the above, also with `/console loadDeprecationFallbacks 0`.
