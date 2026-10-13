# Plan: Friend sharing round 2 (update notice, gathering nodes)

Spec: `docs/superpowers/specs/2026-10-13-tomte-sharing-update-nodes-design.md`. Built inline, tests first for the
pure parts.

1. `Modules/Share/Protocol.lua`: `ns.Share_NewerVersion` + cases in `tests/test_share_protocol.lua`.
2. `Modules/Share/Share.lua`: optional `set.active`; save the friend's revision after an import and skip requests
   for a revision already imported; update notice (toast, chat line, `toldVersion`, `ns.Share_NewestFriendVersion`,
   `ns.Share_ShowDownload`); `sets.nodes` default and options row.
3. `Modules/Share/Page.lua`: the "newer Tomte" strip with a "Get link" button.
4. `Modules/Gather/Nodes.lua` (pure, after Data.lua): pack/unpack, grid merge, add, export, import, revision,
   counts. `tests/test_gather_nodes.lua` first.
5. `Modules/Gather/Detect.lua`: position and main item on the gather payload (mining/herbalism only).
6. `Modules/Gather/MapPins.lua` (UI, before Gather.lua): pooled canvas pins, hooks, tooltip.
7. `Modules/Gather/Gather.lua`: record nodes, defaults, options, `nodes` command, Share registration.
8. TOC lines, `lua Tomte/tools/bugfiles.lua`, all tests, `luac -l` global check, README rows, future-ideas note.
9. Report to the user with the in-game checklist; no commit before they confirm in game.
