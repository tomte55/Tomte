# Quiet Chat (2026-11-13)

First step of a UI overhaul: the chat window stays out of sight until there is something to read or you use it.
Mockups were made in the brainstorm (directions A "Ghost", B "Ticker", C "Tomte panel"); the user picked A's idle
behavior with a light awake look (row 2 of the combined mockup: a soft shadow, Tomte type), plus an unread chip.

## Behavior

- **Idle** (mouse away, not typing): no background, border, tabs, side buttons or edit box frame. Only chat lines
  that are still fresh show, floating over the world; they fade on Blizzard's line timer, which the module shortens
  ("Lines stay for", default 30 s, restored on stop).
- **Unread chip**: while idle, a small chip at the bottom left names the docked tabs with unread whispers and how
  many ("Whispers 2"). It follows Blizzard's tab alert (FCF_StartAlertFlash / FCF_StopAlertFlash), which fires per
  whisper in a hidden tab and stops when the tab is shown.
- **Awake** (Blizzard's own hover fade-in, or any chat edit box focused): a soft shadow from the left edge, tabs as
  plain text in the theme's label font (selected in the heading color with an accent underline, others muted,
  whisper tabs keep Blizzard's color, unread count beside the name) and a hairline to type on (accent while
  typing). Older lines come back (ResetAllFadeTimes).
- **Side buttons** (friends, channels, chat menu, voice) stay hidden even when awake (the user's first test: they
  read as Blizzard clutter). Friends, Chat channels and Emotes and languages are added to the chat tab's right-click
  menu (Menu.ModifyMenu); without that API they fade with the chat instead.
- The shadow is a soft-edged rectangle cut from Media/Showcase/Glow.tga in nine slices (a gradient texture showed as
  a hard box in game), with a long feather on the right.
- Fade in 0.15 s, out 2 s (Blizzard's CHAT_FRAME_FADE_TIME / CHAT_FRAME_FADE_OUT_TIME).
- Optional outline on chat text (`textOutline`, off by default: in game the outline made dark blue lines hard to
  read). The game's outline is always solid black, so the softer help is `lineBacking` (on by default): while
  asleep, a soft shadow fitted to the lines still showing. Blizzard's ScrollingMessageFrame is Lua: each drawn line
  is a font string in `frame.visibleLines` whose alpha is its fade, so the backing is anchored to the top and bottom
  shown lines, as wide as the widest (the frame's width for wrapped lines or a secret width) and as strong as the
  strongest; it's read every 0.05 s only while lines show (pure rule: ns.Chat_ShadowSpan). An earlier version
  guessed from line times and drew the wrong size after a hover.
- Both shadows keep their feathers outside what they cover (text, tabs, type line, scroll bar), so nothing sits on a
  fading edge; asleep and awake shadows crossfade with the wake, never stacking.

## How (decided)

- Restyle Blizzard's chat frames, never replace them: chat handling, other addons and taint stay as they are.
- Background and border textures (CHAT_FRAME_TEXTURES) are hidden: Blizzard only fades the shown ones.
- Docked tabs fade through GeneralDockManager's alpha (Blizzard never sets it). Tab art is set to alpha 0, the tab
  text gets the theme font.
- The edit box is never hooked by script (Autocorrect's taint findings): focus comes from the EventRegistry
  callbacks ChatFrame.OnEditBoxFocusGained/Lost; its border textures go to alpha 0 and Tomte's hairline is a frame of
  its own anchored under it.
- Hooks (hooksecurefunc, can't be undone, do nothing while off): FCF_FadeInChatFrame, FCF_FadeOutChatFrame,
  FCFTab_UpdateColors, FCF_StartAlertFlash, FCF_StopAlertFlash, FCF_OpenTemporaryWindow,
  FCF_SetChatWindowFontSize.
- Stays off (blocked) while EllesmereUI Chat, MelloUI Chat, Prat, Chattynator or Glass is loaded: they style chat.
- Off by default (it changes how chat looks). Category `chat`, key `quietchat`.

## Left for later

- Undocked chat windows lose their background too, but keep Blizzard's tab fade (no shadow of their own).
- The fuller Tomte panel look (direction C) if the light look reads badly in play.
