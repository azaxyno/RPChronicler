# RPCopy

**Roleplay in World of Warcraft with your own AI character skill, without typing a novel.**

RPCopy is a World of Warcraft: Forever addon for people who love roleplay but don't want to type long replies in the middle of a game, or who want an AI such as Gemini, ChatGPT or Claude to help their character sound right.

You build a **character skill** in your AI once. The skill knows who your character is, how they talk, their quirks, and how they react. Then, in game, you press **`Ctrl+C`** and RPCopy copies the current scene: who just spoke to you, your target, your party, your status, and recent chat. You paste the scene into your AI and get a few short in-character lines back. You paste your favorite into chat.

```
 In game                     Your AI (with your character skill)        In game
 ---------                   ------------------------------------       ---------
 Someone talks to you  -->   Ctrl+C, paste the scene          -->       Pick a line,
                             "use aloria" + scene              -->       paste it in /s /p /w
                             5 short in-character options
```

Along the way, RPCopy remembers the **companions** you meet, so your AI knows who they are next time. It also records your **dungeon and raid runs**, so the AI can turn them into colored story chronicles you read inside the game.

- **Version:** 3.7.1 (interface `16001`, WoW: Forever)
- **Saved variables:** `RPCopyDB` (account-wide)
- **License:** MIT

---

## Why RPCopy

- **RP without the typing.** In a busy party or a fast whisper exchange, you don't have time to write a good reply. One key gives your AI the whole context, and you get lines that fit.
- **Your character, consistently.** The AI skill holds your character's personality, voice, faction, class habits and running jokes, so every reply sounds like the same person.
- **Context the AI can't see.** An AI can't see your screen. RPCopy hands it what matters: where you are, who you're talking to and what they said, whether you're in combat, your HP, your pet, your party, and your quest.
- **You stay in control.** RPCopy never sends chat for you. It only copies text out. You choose what to say and paste it yourself.
- **It helps, it doesn't replace you.** Use it to polish a line, get unstuck, write in better English, or keep a character's voice when you're tired. Ignore it when you'd rather improvise.

---

## Quick start

1. **Install** the addon (see [Installation](#installation)) and type `/rp` in game.
2. **Create your character skill** (one time):
   - Open **Options** and click the **RP Template** button. Copy the template with `Ctrl+C`.
   - Paste it into Gemini (or any AI that supports custom skills, Gems, GPTs or projects). Fill in your character: name, faction, race, class, personality, quirks and inspiration. Let the AI build the skill.
   - Pick a short **trigger**, such as `use aloria`, and set the same trigger in **Options > Top Constant / Skill Trigger**. Every snapshot starts with that line, so the AI knows to use your character's skill.
3. **Play.** When someone talks to you, press `Ctrl+C` out of combat, or use `/rp quick`. A toast confirms the copy.
4. **Paste into your AI.** It replies with up to 5 short options, written for the channel (say, party, whisper and so on). Copy one into WoW chat.

### What a snapshot looks like

```
use aloria
[Location] The Barrens - Crossroads
[Direct] [W] Thrallgar: you look lost, need a hand with those raptors?
[Target] Thrallgar - Lvl 14 Orc Warrior [Friendly] [100%]
[Party] Aloria (Hunter) [DPS], Thrallgar (Warrior) [Tank]
[Status] Lvl 14 Hunter | 82% HP | [Out of Combat] | Pet: Sir Fluffington [Content]
[Known Player: Thrallgar]
Note: met him in Durotar, loud, owes me 5 silver
Latest Chat:
[W] Thrallgar: you look lost, need a hand with those raptors?
```

The `[Known Player]` block is added automatically because Thrallgar is a saved companion (see below).

### What the character skill gives you

The built-in template guides the AI to write a skill with:
- A **core personality** built from five angles: a signature quirk, witty banter, everyday habits, class and lore chaos, and an over-the-top "overkill" mode, so you get variety and not the same line five times.
- **Channel awareness.** It reads the `[S]`, `[P]`, `[W]`, `[G]` and `[Y]` tags and fits the tone to the channel.
- **WoW-ready output.** Replies are 1 to 2 short sentences each, with no `/s` or `/p` prefixes, ready to paste.

You can keep several characters. Give each one its own skill and trigger (for example `use aloria` and `use elaini`), and switch the trigger in Options, or make a separate slice tab per character.

---

## Companions: context that remembers people

The more your AI knows about who you're talking to, the better the replies get.

- **Capture** a player: target, hover or whisper them, then press the **Capture** keybind or type `/rp capture`. RPCopy saves their level, race, class and guild, and keeps their last 5 chat lines.
- **Write your own note** for each companion in the **Companions** view, for example "rival hunter, always steals my skinning nodes" or "sweet healer, calls me 'boss'". Auto-capture never overwrites your notes.
- **Automatic context.** Whenever a saved companion's name appears in a snapshot, their note and latest chat are added as a `[Known Player]` block. Your AI remembers your history together without you explaining it again.

---

## Slice tabs: copy the right amount of context

Each tab is a "slice", meaning a preset of what goes into the snapshot. The built-in slices are:

| Tab | Best for |
|---|---|
| **Smart** | Everyday RP: direct message, target, party, status, recent combat |
| **Chat** | Conversations: say, yell and whisper history |
| **Party** | Group banter: party and raid chat plus the roster |
| **Quest** | Questing flavor: your active quest |
| **Loot** | Reacting to drops |

You can add **custom tabs** with their own trigger and any mix of these sections: direct message, target info, party roster, status and pet, active quest, combat and deaths, social chat, OOC channel, party and raid chat, NPC dialogue, and loot log. `Ctrl+C` always copies the slice you used last.

Add a one-time out-of-character note with `/rp <note>`, for example `/rp make it flirty`. It's sent to the AI as `[OOC Note]`.

---

## Adventures: dungeon and raid stories

RPCopy also works as a quiet chronicler. It records your runs so an AI can write them up as a story afterwards.

- **Automatic logging** starts when you enter a dungeon or raid and stops when you leave. You can also start a run manually anywhere.
- **Timestamped `[HH:MM:SS]` timeline** with these tags:
  - `[BOSS ENGAGED]` when a boss is pulled
  - `[BOSS HP]` at 50%, 20% and 5%
  - `[DANGER]` at low HP, and `[LOW MANA]` at low mana
  - `[DEATH]` with the killing spell
  - `[WIPE #N]`
  - `[REZ]` for resurrections
  - `[LOOT]` for Uncommon or better drops
- **Fight context on chat.** Chat is tagged with the fight it happened in, for example `[Party | vs Boss 5% HP] Healer: OOM!!`, so the story knows exactly when someone panicked.
- **Mark Moment.** The keybind or `/rp mark [note]` stars a moment as a highlight.
- **Full Log** export, then **Import Story**. Copy the log into an AI that has the `wow-adventure-story` skill (its template is in the Story view). Paste the colored chronicle back, and read it in the in-game **Story** reader. The story skill is told to use only what's in the log: no invented bosses, loot or quotes.
- **Optional auto screenshots** at key moments, such as boss kills, level-ups and new zones. These are combat-safe and capped per run.
- Up to 40 runs are archived.

---

## Slash commands

| Command | What it does |
|---|---|
| `/rp` or `/rpcopy` | Open the RPCopy window |
| `/rp <note>` | Open the window with a one-time OOC note added to the snapshot |
| `/rp quick` | Quick-copy the last used slice |
| `/rp capture` | Save or update your target (or mouseover, or last whisperer) as a companion |
| `/rp mark [note]` | Bookmark the latest moment, or your note, in the active run |
| `/rp clear` | Clear the session chat, combat, NPC and loot buffers |
| `/rp btn` | Show or hide the draggable floating `[RP]` button (right-click it to clear logs) |

## Keybindings

Set these in **Esc > Key Bindings > AddOns > RPCopy (RP Context & Chronicle)**:

| Binding | Action |
|---|---|
| Toggle RPCopy Window | Open or close the main window |
| Quick Copy (Last Used Slice) | Same as `/rp quick` |
| Capture / Update Target Companion | Same as `/rp capture` |
| Bookmark Adventure Moment | Same as `/rp mark` |

Silent quick copy (`Ctrl+C` by default) works out of combat. You can change the key or turn it off in Options. In combat it's released automatically, so your normal keybinds are never affected.

---

## Installation

1. Download this repository: **Code > Download ZIP**, or `git clone https://github.com/azaxyno/RPCopy.git`.
2. Put the folder in your AddOns directory and make sure it's named exactly `RPCopy`:
   ```
   World of Warcraft\_forever_\Interface\AddOns\RPCopy\RPCopy.toc
   ```
3. Restart the game, or type `/reload`, and enable **RPCopy** on the character select AddOns screen.
4. Type `/rp`.

---

## For developers

### Architecture

All files share the addon's private namespace (`local ADDON_NAME, ns = ...`). WoW loads them in the order listed in `RPCopy.toc`, and that order matters:

| # | File | Role | Key functions |
|---|---|---|---|
| 1 | `Core.lua` | Database setup and migration, default tabs and trigger, colors, class and role formatting, log ring buffers, companion lookup, `NormalizeStoryText` | `EnsureDB`, `CleanText`, `ColorText`, `PushLog`, `SaveOrUpdatePlayer`, `GetKnownPlayerBlocks` |
| 2 | `Snapshot.lua` | Builds snapshot text from the active slice's settings | `BuildSnapshot`, `GetTabConfig`, `ResetDefaultTabs`, `HandleConversationCapture`, `ClearSessionLogs` |
| 3 | `Adventures.lua` | Run lifecycle, timeline telemetry, Full Log export, story storage | `StartAdventure`, `EndAdventure`, `RecordAdventureBossHP`, `RecordAdventureChat`, `BuildAdventureFullLog`, `SetAdventureStory`, `MarkAdventureHighlight` |
| 4 | `Screenshots.lua` | Debounced, combat-safe automatic screenshots | `RequestScreenshot` |
| 5 | `Events.lua` | Central event dispatcher (chat, combat log, unit health and power, loot, instance changes) that routes to `ns.*` | internal `RPCopyEventFrame` |
| 6 | `UI.lua` | Main window, slice tabs, Companions / Adventures / Options views, Story reader, skill template and import modals, `Ctrl+C` override, slash commands | `RPCopy_Open`, `RPCopy_Toggle`, `RPCopy_QuickCopy`, `RPCopy_CaptureTarget` |
| | `Bindings.xml` | Keybinding definitions | |

### Saved data (`RPCopyDB`)

| Key | Contents |
|---|---|
| `tabs` | Your slice tabs (label, trigger, section toggles) |
| `players[name]` | Companions: your note, level, race, class, guild, last seen, last 5 chat lines |
| `adventures` | Up to 40 runs: zone, dates, duration, party, wipes, deaths, boss kills, loot, highlights, timeline, screenshots, export text, story |
| `quickCtrlC`, `autoScreenshots` | Feature toggles |

Session buffers (`ns.logs`) live only in memory and are cleared on `/reload` or `/rp clear`.

### WoW: Forever compatibility notes

- The addon targets the WoW: Forever client (`## Interface: 16001`). APIs that don't exist on every client are checked before they're called, so a missing API turns a feature off instead of throwing a Lua error.
- `IsInInstance()` is called directly and both of its return values are used. Writing `IsInInstance and IsInInstance()` would keep only the first value and break dungeon and raid detection.
- WoW fonts can't draw Unicode symbols such as stars, arrows or smart quotes, so all in-game text is plain ASCII. Colors use `|cffRRGGBB...|r` escape codes only, never Markdown.
- Text pasted into WoW edit boxes turns `|` into `||`. `ns.NormalizeStoryText` converts it back, strips code fences, and closes any open color tags before the story is rendered.
- Screenshots fade `UIParent` with `SetAlpha` instead of hiding it, which avoids `ADDON_ACTION_BLOCKED` in combat.

---

## Credits

The recording and event-engine techniques are adapted from [StoryTracker](https://github.com/ninepointlabs/wow-storytracker-addon) by Nine Point Labs (MIT). See [CREDITS.md](CREDITS.md).

## License

MIT, see [LICENSE](LICENSE).
