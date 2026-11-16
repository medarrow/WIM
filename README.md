# WIM - WoW Instant Messenger (tabbed fork)

Gives whispers an instant-messenger feel on the 1.12 (vanilla) client. This version puts every conversation in **one window with a tab per conversation**, and is tuned so that switching tabs stays smooth with many conversations open.

> **Fork notice:** this is a continuation of [me0wg4ming/WIM](https://github.com/me0wg4ming/WIM), a TurtleWoW fork of WIM. That repository's page is gone (404), so it could not be forked on GitHub; this repository was started from a local copy of it instead. The original WIM was written by Pazza, with later refactoring by shirsig.

## What's new

**1.3.9**
- Auto-close: a conversation can close itself after SurpriseMe sends its invite reply (`/wim` -> General), or when a whisper you send matches a filter set to **Close**. Chats you have typed in are kept open by default. See [Auto-closing conversations](#auto-closing-conversations).
- New filter action **No Popup**: matching whispers are shown in their conversation but never open the window or switch tabs. See [Filter actions](#filter-actions).
- Fixed: editing a Block filter showed it as Ignore (and saved it as Ignore on OK).
- Fixed: an empty checkbox showed on the General options page under pfUI.

**1.3.8** - The Tabs options page is skinned when pfUI skins the options window.

**1.3.7** - The Tabs page sliders show their value instead of "Test".

**1.3.6** - Fixed the frame drop whenever a conversation window was shown or a tab was switched. Windows come to the front when clicked or opened with `/w` / `/r`. Added `/wim profile`.

**1.3.5** - First release of this fork: tabbed window, Tabs options page, and the performance work and fixes listed [below](#performance-and-fixes-in-this-fork).

The full history is in game under `/wim help`, and each version is on the [releases page](https://github.com/medarrow/WIM/releases).

## Installation

1. Download the latest `WIM-x.y.z.zip` from the [releases page](https://github.com/medarrow/WIM/releases), or use **Code -> Download ZIP**.
2. Extract it into `Interface\AddOns` so that the folder is named exactly `WIM` (rename it if it was extracted as `WIM-main`).
3. Restart the game, or log out to the character screen and back in.

Type `/wim` in game to open the options.

## Slash commands

| Command | What it does |
| --- | --- |
| `/wim` | Open the options window |
| `/wim history` | Open the history viewer |
| `/wim help` | Show the help / change log window |
| `/wim reset` | Reset all options (including tab options) to their defaults |
| `/wim reset filters` | Restore the default filters |
| `/wim clear history` | Delete all recorded history |
| `/wimdebug` | Toggle debug output for the WHO queue |
| `/wim profile` | Toggle timing output for every conversation window that is shown |

## Tabbed window

All whisper conversations share one window instead of a separate window each.

- **Left-click a tab** to switch conversation (the edit box gets focus; each tab keeps its own half-typed message)
- **Right-click a tab** to close that conversation (same as Shift+click on the window's X)
- **X button / Escape** hides the whole tabbed window; conversations stay open and the minimap menu / new whispers bring it back
- A new whisper while the window is open on another tab **does not steal the view** - its tab flashes instead (and the minimap icon flashes). Replying with `/r`, `/w name`, or sending a whisper from a conversation does switch to it
- "Show New Messages" (minimap right-click / keybinding) opens the oldest unread tab; "Show All" reopens the window on the current tab
- Tabs wrap onto extra rows when there are more than fit the window width
- Dragging the window moves all tabs together and remembers the position (this is the same as the "default spawn" position in options)
- The "Window cascade" option no longer does anything (there is only one window)

If the tab strip doesn't line up with your skin, adjust `WIM_TAB_OFFSET_X` and `WIM_TAB_OFFSET_Y` at the top of `WIM_Tabs.lua`.

### Tab options (`/wim` -> "Tabs" page)

Changes apply live.

- **Colors** - Back / Border / Text colour for each tab state: *Selected*, *Unread* and *Idle*. The Unread row also has a *Flash* colour used while the tab flashes.
- **Flash tabs that have unread messages** - master switch for flashing. With it off, unread tabs just keep their static Unread colours.
- **Flash text / Flash border** - choose what alternates with the Flash colour (text by default; border is optional).
- **Flash interval (ms)** - time between flash toggles, 100-2000 ms (default 500).
- **Hide tabs while only one chat is open** - the strip only appears once there are two or more conversations.
- **Focus the message box when switching tabs** - when on (default), clicking a tab, picking a conversation from the icon menu, or jumping to the next unread conversation puts the keyboard cursor in that conversation's message box. Automatic switches (closing a tab, incoming messages) never take focus either way.
- **Idle tab opacity** - background opacity of tabs that aren't selected or unread (default 75%).
- **Tab width / Tab height** - size of each tab (60-160 x 16-40).
- **Reset Tab Options** - restores every tab setting to its default.

Settings are saved in `WIM_Data.tabs`; missing values are filled in automatically, so existing saved variables keep working.

## Auto-closing conversations

Handy on raid nights, when every "inv" whisper opens a tab. A whisper **you send** can close its conversation:

- **SurpriseMe's invite reply** (`/wim` -> General -> "Close a chat after SurpriseMe's invite reply", off by default). WIM reads the reply text from SurpriseMe's own settings (`SurpriseMeDB.responseMessage`), so changing it in SurpriseMe needs no setup here. Does nothing without SurpriseMe.
- **A filter set to "Close"** (`/wim` -> Filters -> Add/Edit). Works with any addon or a phrase you type yourself. Like the other filters it is a case-insensitive Lua pattern, so `OwO7` also matches "OwO7 see you"; use `^OwO7$` to match only the exact message. Needs "Enable filtering" on. Incoming whispers never trigger it.

When a conversation is auto-closed, the whisper is not shown but is still saved to history. No tab is opened if there wasn't one already. If that conversation's whisper had opened the window by itself, the window is put away again. Its pending `/who` lookup is dropped.

**Don't auto-close chats you have typed in** (General, on by default): once you have sent a whisper of your own in a conversation, it is kept open and the auto-reply is shown in it as usual.

## Filter actions

`/wim` -> Filters. Each keyword or phrase (a case-insensitive Lua pattern) gets one action:

| Action | What it does |
| --- | --- |
| Ignore | WIM leaves the whisper alone; it goes to the normal chat frame only |
| Block | The whisper is hidden everywhere |
| Close (when sent) | A whisper you send closes its conversation (see above) |
| No Popup | The whisper is shown in its conversation as usual, but never opens the window or switches tabs; an incoming one leaves the tab flagged as unread. Works in both directions |

## pfUI

pfUI skins WIM's windows but only knows the option pages of the original WIM. When pfUI has skinned the options window, WIM skins its own Tabs page and the auto-close checkboxes to match, using pfUI's helpers. This happens once, the first time the options window is opened, and does nothing without pfUI.

## Performance and fixes in this fork

- Showing a conversation window (and so every tab switch) no longer stalls the game: the windows are not `toplevel` any more, which took the client 80-240 ms per show in a heavily modded UI. They come to the front when clicked or opened with `/w` / `/r` instead.
- Switching tabs, incoming messages and flash ticks only update the tab buttons that actually changed, instead of rebuilding the whole strip. Fitted tab names are cached.
- A flash tick only re-colours unread tabs.
- The shortcut bar of a conversation is set up once per window rather than on every show.
- The per-frame update no longer allocates memory while there is nothing to look up.
- The minimap icon stops flashing once an unread conversation has been read by clicking its tab, and after the last unread conversation is closed.
- A message arriving on the tab you are looking at no longer marks it as unread.
- `/wim reset` copies the defaults instead of sharing them, also resets the tab options, and re-applies size and scale to open windows.
- `/who` results go back to the chat frame after a WIM lookup times out.
- A missing `popUpdate` setting is now filled in correctly.
- Editing a filter whose action is Block no longer shows it as Ignore in the dialog.

## Inherited from the TurtleWoW fork

- **30s WHO cooldown** (TurtleWoW limit); GMs skip it
- **GM detection** - shows the Blizzard icon, a `<GM>` tag and a "Game Master" label
- **Messages display immediately** - WHO info loads asynchronously
- **Removed the "Block Low Level" option** (incompatible with cross-faction whispers)
- **Debug mode** - `/wimdebug`

## Building a package

From the repository root:

```bash
git archive --format=zip --prefix=WIM/ -o dist/WIM-1.3.9.zip HEAD
```

The zip contains a single `WIM` folder ready to extract into `Interface\AddOns`.

## License

The changes made in this repository are released under the [MIT License](LICENSE). WIM itself was created by Pazza and later modified by shirsig and me0wg4ming; credit for the original addon belongs to them.
