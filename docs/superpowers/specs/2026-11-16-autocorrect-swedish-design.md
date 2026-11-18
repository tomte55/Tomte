# Autocorrect: Swedish too (2026-11-16)

## Why

The user chats in Swedish as well as English. Autocorrect only knew English, so Swedish words could be "fixed" into
English and Swedish typos were never fixed (words with å, ä, ö were skipped as not plain words).

## What (the user picked full Swedish support over "leave Swedish alone")

- A setting, **Swedish too** (`swedish`, off by default: friends who don't write Swedish keep the old behavior).
- A word that's right in either language is never changed, in any line.
- Each line is judged English or Swedish from the words typed before the current one (`Autocorrect_Language`): each
  word counts for the list where it's more common; å, ä, ö and Swedish words missing them count for Swedish; chat
  shorthand and a small "i" count for neither. Where the words don't tell (nothing typed yet, or even), the
  conversation does: the chat box's party, guild, whisper partner or channel, from the language of its last six
  messages, sent and received (session only; the user's idea). With neither: a fix needs a clear winner across both.
- Swedish lines: å, ä, ö put back (`AUTOCORRECT_SV_LETTERS`, generated: the plain spelling is a typo where the marked
  one is 20 times as common), a short-word typo table (`AUTOCORRECT_SV_TYPOS`), and a guess on letters, not bytes,
  with the Swedish keyboard's neighbours. English-only rules switch off there: "i" -> "I", apostrophes, English
  pairs and splits, English capitalized words.
- Left alone: compounds (two words of at least four letters, the second Swedish, the first maybe English or with a
  linking s; only a slip is fixed in one) and English game words with Swedish endings (questen, bossarna).

## Data

FrequencyWords (Hermit Dave, OpenSubtitles 2018 counts, CC BY-SA 4.0, one-way compatible with GPL-3.0), Swedish top
50,000, pinned to commit 0e18d96. `tools/autocorrect_swedish.py` writes `Modules/Autocorrect/WordsSwedish.lua`: five
bands on the English list's scale and the letter fixes. Subtitles are spoken language, close to chat.

## Approaches considered

1. Leave Swedish alone (a second known-word list only): smaller, offered first; the user chose full support.
2. Full support with per-line language (built).
3. Hunspell sv_SE: no frequencies, and expanding its affix rules needs a tool of its own; dropped.

## Code

Pure: `Swedish.lua` (letters, the list, language, compounds, endings, the guess), with Rules.lua and Line.lua
following `ctx.sv` / `ctx.lang`. English rules are unchanged with the setting off (tests/test_autocorrect*.lua).
Tests: tests/test_autocorrect_swedish.lua.
