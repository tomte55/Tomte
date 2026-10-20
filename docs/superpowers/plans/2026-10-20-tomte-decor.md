# Housing decor: plan

Spec: `docs/superpowers/specs/2026-10-20-tomte-decor-design.md`.

- [x] Step 1: research the housing catalog, tracking and model APIs (wow-ui-source live, warcraft.wiki.gg).
- [x] Step 2: `Modules/Decor/Data.lua` (pure: source classification through `ns.Collect_ParseSource`, owned count,
  filter, sections, counts, vendors here, texts) with `tests/test_decor.lua`.
- [x] Step 3: `Catalog.lua`: one catalog searcher, chunked entry reads (3 ms per frame), retry when the results
  callback stays silent, single-entry update, stop clears everything.
- [x] Step 4: `Preview.lua` (decor model card) and `Page.lua` (filter, search, sections, rows, tooltip, click to track,
  shift-click to link).
- [x] Step 5: `Decor.lua`: events while active (housing events via pcall), tooltip post-call once (inert while off),
  Blizzard tracking, Next up / Around you / page entries, `open`, `scan`, `why`, options.
- [x] Step 6: all tests, `luac -l` globals check on each new file.
- [ ] Step 7 (overseer): TOC lines after `Modules/Collect/Collect.lua`, `lua Tomte/tools/bugfiles.lua`, README row and
  commands, layout entry.
- [ ] Step 8: user tests in game (without Midnight now, with Midnight later); CHANGELOG line after that.
