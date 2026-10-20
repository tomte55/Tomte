# Mail: plan

2026-10-20. Spec: `docs/superpowers/specs/2026-10-20-tomte-mail-design.md`.

## Files

- `Modules/Mail/Data.lua` (pure): subject patterns, letter classification, skip rules, next step, counts and
  tally, tick decision, inbox signature and stuck guard, summary text, recipient filtering, recent recipients.
- `Modules/Mail/Mail.lua` (main): inbox reader, Open all run (ticker while running), inbox button standing in for
  Blizzard's Open All, Send tab picker, events, SendMail hook, module registration (options, commands).
- `tests/test_mail.lua`: tests for every function in Data.lua.

## Tasks

1. Verify APIs (wiki, Blizzard MailFrame.lua live, GlobalStrings) and write the spec. Done.
2. Data.lua and tests/test_mail.lua, test first. Done.
3. Mail.lua: reader, run loop, summary (chat, card, recap note). Done.
4. Inbox button and Blizzard Open All hide/restore; picker on the Send tab. Done.
5. Options, commands, toggle off undoes everything. Done.
6. All tests, `luac -l` globals check. Done.
7. Overseer: TOC lines (Data.lua then Mail.lua), `lua Tomte/tools/bugfiles.lua`, README row and commands; optional
   Recap label for the "mail" note kind.
8. User tests in game (spec's test plan); CHANGELOG line and commit after that.
