# RPCopy

**AI roleplay context snapshots and colored adventure chronicles for World of Warcraft: Forever.**

RPCopy turns what happens around your character into clean, clipboard-ready text for an AI roleplay partner or storyteller. It does two things:

1. **Roleplay snapshots.** You press `Ctrl+C` out of combat, and RPCopy copies a compact "slice" of the scene: who you're talking to, your target, party, status, quest, and recent chat. You paste it into your AI chat, and the AI answers in character with full context.
2. **Adventure chronicles.** RPCopy records dungeon and raid runs automatically as a timestamped log of bosses, HP milestones, deaths, wipes, loot, and quotes. You export the log to an AI, paste the colored story it writes back into the game, and read it in a parchment-style Chronicle viewer.

- **Version:** 3.7.1 (interface `16001`)
- **Saved variables:** `RPCopyDB` (account-wide)
- **License:** MIT

---

## Features

### Roleplay snapshot slices
- **Silent `Ctrl+C` quick copy.** When you're out of combat, `Ctrl+C` copies the active slice without opening the window, and a small toast confirms it. The override is released in combat, so your normal keybinds are never touched during fights.
- **Slice tabs.** The built-in slices are **Smart**, **Chat**, **Party**, **Quest** and **Loot**. You can add custom tabs, each with its own trigger prefix (for example `use <trigger>`) and its own set of sections:
  - Direct message (last whisper or say)
  - Target info
  - Party roster
  - My status and pet
  - Active quest info
  - Combat and deaths
  - Social chat (say, yell, whisper)
  - OOC channel (`[OOC]`)
  - Party and raid chat
  - NPC dialogue
  - Loot log
- **One-time OOC note.** `/rp <note>` opens the window and adds your note to the snapshot.

### Companions directory
- **Capture players.** Target, hover or whisper a player and press the **Capture** keybind (or `/rp capture`) to save their level, race, class and guild.
- **Your notes are kept.** Each companion has a permanent note that auto-capture never overwrites, plus a rolling history of their last 5 chat lines. Companion notes are added to snapshots and adventure logs.

### Adventure runs and chronicles
- **Automatic runs.** A run starts automatically when you enter a dungeon or raid and ends when you leave. You can also start one manually anywhere with **Start New Run**.
- **`[HH:MM:SS]` timeline.** The timeline records these tags:
  - `[BOSS ENGAGED]` when a boss is pulled
  - `[BOSS HP]` at 50%, 20% and 5%
  - `[COMBAT START]` and `[COMBAT END]`
  - `[DANGER]` at 14% HP or less, and `[LOW MANA]` at 8% mana or less (each has a per-player cooldown)
  - `[DEATH]` with the killing spell
  - `[WIPE #N]` when 3 or more players die within 45 seconds
  - `[REZ]` for resurrections
  - `[LOOT]` for Uncommon or better drops
- **Fight context on chat.** Chat lines are tagged with the fight they happened in, for example `[Party | vs Boss 20% HP]`, so the AI knows exactly when each line was said.
- **Bookmarks.** **Mark Moment** (keybind, or `/rp mark [note]`) stars the latest line, or your note, as a highlight.
- **Full Log export.** Gives you a `use story` block with run metadata, the party roster with roles and RP notes, boss kills, loot, highlights, and up to 250 timeline lines.
- **Import Story.** Paste the AI's colored chronicle back in, and the Story reader renders it with WoW color codes. Pasted `||` pipes are fixed automatically, Markdown fences are stripped, and unclosed colors are closed.
- **Archive.** Up to 40 runs are kept in `RPCopyDB.adventures`.

### Auto screenshots (optional)
When you turn this on in Options, RPCopy takes a screenshot at key moments, such as a boss kill, a level-up, a new zone or a quest. The UI is faded out during the shot instead of hidden, so no protected-frame errors happen in combat. Screenshots are debounced and capped at 12 per run.

### Built-in AI skill templates
The **Options** and **Story** views include copyable prompt templates for two AI skills: a character roleplay skill (`<character>-rp-<class>`) and the `wow-adventure-story` chronicle writer. The story skill is told to stick to what's in the log, with no invented bosses, loot or quotes, and to output plain ASCII text with closed `|cffRRGGBB...|r` color tags that WoW can render.

---

## Slash commands

| Command | What it does |
|---|---|
| `/rp` or `/rpcopy` | Open the RPCopy window |
| `/rp <note>` | Open the window and add a one-time OOC note to the snapshot |
| `/rp quick` | Quick-copy the last used slice |
| `/rp capture` | Capture or update your target (or mouseover, or last whisperer) as a companion |
| `/rp mark [note]` | Bookmark the latest timeline line, or your note, in the active run |
| `/rp clear` | Clear all session chat, combat, NPC and loot buffers |
| `/rp btn` | Show or hide the draggable floating `[RP]` button (right-click it to clear logs) |

## Keybindings

Set these in **Esc > Key Bindings > AddOns > RPCopy (RP Context & Chronicle)**:

| Binding | Action |
|---|---|
| Toggle RPCopy Window | Open or close the main window |
| Quick Copy (Last Used Slice) | Same as `/rp quick` |
| Capture / Update Target Companion | Same as `/rp capture` |
| Bookmark Adventure Moment | Same as `/rp mark` |

---

## Installation

1. Download this repository: **Code > Download ZIP**, or `git clone https://github.com/azaxyno/RPCopy.git`.
2. Put the folder in your AddOns directory and make sure it's named exactly `RPCopy`:
   ```
   World of Warcraft\_forever_\Interface\AddOns\RPCopy\RPCopy.toc
   ```
3. Restart the game, or type `/reload`, and enable **RPCopy** on the character select AddOns screen.
4. Type `/rp` to open the window.

## Typical workflows

**Roleplay with an AI**
1. Talk to someone in game, or target them.
2. Press `Ctrl+C` out of combat, or use `/rp quick`.
3. Paste into your AI chat, where your character skill is loaded, and let it answer in character.

**Write a dungeon chronicle**
1. Run a dungeon. Logging starts and stops by itself.
2. Open **Adventures**, select the run, and switch to **Full Log**, then copy it.
3. Paste it into an AI that has the `wow-adventure-story` skill, which you can copy from the Story view.
4. Copy the AI's single fenced reply and click **Import Story**, then paste it in. Read it in the **Story** tab.

---

## Architecture

All files share the addon's private namespace (`local ADDON_NAME, ns = ...`). WoW loads them in the order listed in `RPCopy.toc`, and that order matters:

| # | File | Role | Key functions |
|---|---|---|---|
| 1 | `Core.lua` | Database setup and migration, default tabs, colors, class and role formatting, log ring buffers, companion lookup, `NormalizeStoryText` | `EnsureDB`, `CleanText`, `ColorText`, `ColorizeClass`, `GetRoleTag`, `PushLog`, `SaveOrUpdatePlayer`, `FindPlayerKey` |
| 2 | `Snapshot.lua` | Builds roleplay snapshot text from the active slice's settings | `BuildSnapshot`, `GetTabConfig`, `ResetDefaultTabs`, `HandleConversationCapture`, `ClearSessionLogs` |
| 3 | `Adventures.lua` | Run lifecycle, timeline telemetry, Full Log export, story storage | `StartAdventure`, `EndAdventure`, `RecordAdventureBossHP`, `RecordAdventureChat`, `BuildAdventureFullLog`, `SetAdventureStory`, `MarkAdventureHighlight` |
| 4 | `Screenshots.lua` | Debounced, combat-safe automatic screenshots | `RequestScreenshot` |
| 5 | `Events.lua` | Central event dispatcher (chat, combat log, unit health and power, loot, instance changes) that routes to `ns.*` | internal `RPCopyEventFrame` |
| 6 | `UI.lua` | 680x490 main window, slice tabs, Companions / Adventures / Options views, Story reader, import modals, `Ctrl+C` override, slash commands | `RPCopy_Open`, `RPCopy_Toggle`, `RPCopy_QuickCopy`, `RPCopy_CaptureTarget` |
| | `Bindings.xml` | Keybinding definitions | |

### Saved data (`RPCopyDB`)

| Key | Contents |
|---|---|
| `tabs` | Your slice tabs (label, trigger prefix, section toggles) |
| `players[name]` | Companions: your note, level, race, class, guild, last seen, last 5 chat lines |
| `adventures` | Up to 40 runs: zone, dates, duration, party, wipes, deaths, boss kills, loot, highlights, timeline (300 lines max), screenshots, export text, story |
| `quickCtrlC`, `autoScreenshots` | Feature toggles |

Session buffers (`ns.logs`: social, party, OOC, NPC, combat, loot; 25 lines each) live only in memory and are cleared on `/reload` or `/rp clear`.

---

## WoW: Forever compatibility notes

- The addon targets the WoW: Forever client (`## Interface: 16001`). APIs that don't exist on every client, such as `C_*` namespaces, `IsInInstance` and encounter events, are checked before they're called, so a missing API turns a feature off instead of throwing a Lua error.
- `IsInInstance()` is called directly and both of its return values are used. Writing `IsInInstance and IsInInstance()` would keep only the first value and break dungeon and raid detection.
- WoW fonts can't draw Unicode symbols such as stars, arrows or smart quotes, so all in-game text is plain ASCII. Colors use `|cffRRGGBB...|r` escape codes only, never Markdown.
- Text pasted into WoW edit boxes turns `|` into `||`. `ns.NormalizeStoryText` converts it back, strips code fences, and closes any open color tags before the story is rendered.
- Screenshots fade `UIParent` with `SetAlpha` instead of hiding it, which avoids `ADDON_ACTION_BLOCKED` in combat.

## Credits

The recording and event-engine techniques are adapted from [StoryTracker](https://github.com/ninepointlabs/wow-storytracker-addon) by Nine Point Labs (MIT). See [CREDITS.md](CREDITS.md).

## License

MIT, see [LICENSE](LICENSE).
