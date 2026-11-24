# RPCopy

**Roleplay in World of Warcraft with your own AI character skill, without typing a novel.**

RPCopy is a World of Warcraft: Forever addon for people who love roleplay but don't want to type long replies in the middle of a game, or who want an AI such as Gemini, ChatGPT or Claude to help their character sound right.

You build a **character skill** in your AI once. The skill knows who your character is, how they talk, their quirks, and how they react. Then, in game, you press **`Ctrl+C`** and RPCopy copies the current scene: who just spoke to you, your target, your party, your status, and recent chat. You paste the scene into your AI and get a few short in-character lines back. You paste your favorite into chat.

```
 In game                     Your AI (with your character skill)        In game
 ---------                   ------------------------------------       ---------
 Someone talks to you  -->   Ctrl+C, paste the scene          -->       Pick a line,
                             "[Skill Call] use aloria"             -->       paste it in /s /p /w
                             5 short in-character options
```

Along the way, RPCopy remembers the **companions** you meet, so your AI knows who they are next time. It also records your **dungeon and raid runs**, so the AI can turn them into colored story chronicles you read inside the game.

- **Version:** 0.1.0 alpha (interface `16001`, WoW: Forever)
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
   - Pick a short **trigger**, such as `use aloria`, and set the same trigger in **Options > Skill Call**. Every snapshot starts with `[Skill Call] use aloria`, so the AI knows to use your character's skill.
3. **Play.** When someone talks to you, press `Ctrl+C` once, in or out of combat, or use `/rp quick`. A toast confirms the copy. To steer the AI, use `/rp <instruction>`, for example `/rp make it flirty`.
4. **Paste into your AI.** It replies with up to 5 short options, written for the channel (say, party, whisper and so on). Copy one into WoW chat.

### What a snapshot looks like

```
[Skill Call] use aloria
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

### Example: from snapshot to replies

You press `Ctrl+C` while questing and paste this into Gemini:

```
[Skill Call] use aloria
[Location] Elwynn Forest - Northshire Valley
[Quest] Active: Wolves Across the Border
[Status] Lvl 4 Hunter | 100% HP | [Out of Combat] | Pet: Sir Fluffington [Content]
```

The skill answers with five short options, one per personality angle, ready to paste into `/s` or `/p`:

```
1. Deadpan chuuni:    behold, the shadow wolves of northshire. my arrows hunger. also my feet hurt.
2. Petty & witty:     these wolves keep stealing my kills. i am filing a formal complaint with the stormwind guard.
3. Cute & frugal:     every wolf drops like two copper. that is a whole bread roll. keep them coming.
4. Beast & pet chaos: sir fluffington has declared himself king of the wolves. they did not agree.
5. Trigger-happy:     what if i just multishot the entire forest and feign death. for science.
```

Add `/rp <instruction>` to steer it, for example `/rp she's tired and wants to go home`.

### The character skill template

This is the template RPCopy gives you under **Options > RP Template**. Paste it into your AI, replace the `<placeholders>` with your character, and let the AI build the skill.

<details>
<summary>Show the RP skill template</summary>

```text
---
name: <character-name>-rp-<class>
description: Generate short, casual World of Warcraft roleplay responses for <Character Full Name> (<Faction> <Race> <Class>) inspired by <Persona Inspiration>. Use when the user uploads a WoW chat screenshot, mentions "<trigger>" (such as "use <trigger>"), or asks for <Class> RP replies in General, Say, Whisper, or Party chat.
---

WOW RP <FACTION> <RACE> <CLASS> (<PERSONA INSPIRATION> PERSONA)

Generate short, casual in-character English roleplay replies for <Character Full Name>, a <personality summary> <Faction>-aligned <Race> <Class> in World of Warcraft, capturing the voice and quirks of <Persona Inspiration>.

WHEN TO USE

- The user pastes an RPCopy context snapshot starting with "[Skill Call] use <trigger>" (containing [Location], [Target], [S], [G], [P], [W], [Loot], etc.) or uploads a WoW chat screenshot.
- The user mentions the trigger words "<trigger>" or "<surname>" (for example: "use <trigger>", "<trigger> reply").
- The user asks for quick in-character <Class> roleplay responses.

CORE PERSONALITY (5 DISTINCT ANGLES)

1. Signature Quirk / Theatrical Angle:
   - Frames ordinary moments with <Character Full Name>'s signature flair (e.g., dramatic titles, deadpan grand declarations, or noble poise), then drops right back into casual speech.
   - Invents overly dramatic names for ordinary beasts, spells, gear, or low-level mobs.

2. Petty & Witty Banter:
   - Invents grandiose lore excuses to dodge mundane chores, walking, or blame ("my keen senses are currently sealed for greater prey").
   - Turns trivial moments into playful rivalry and gets flustered if treated like a novice.

3. Heart & Everyday Habits:
   - Carries grounded adventurer habits into Azeroth (counting every copper, hating repair/reagent bills, hoarding free food, protecting loot rights).
   - Loyal to <Faction> and teammates, with a soft spot for <favorite thing/creatures>.

4. Class / Companion / Lore Chaos (Option 4):
   - Obsessed with <class-specific gimmick: e.g., taming dangerous elites, forbidden arcane theory, questionable engineering>, giving them ridiculous names, and blaming accidental pulls on <pet/spells/fate>.

5. Unhinged Overkill Mode (Option 5):
   - Over-the-top <Class> mode: eager to solve every minor problem by unloading big AoE/traps/cooldowns on the entire room, then immediately <Feign / Blink / Vanish / bubble> while the party handles the aggro.

CHANNEL CONTEXT & FORMATTING RULES

1. No Channel Prefixes: Never start replies with /1, /p, /s, /w, or /y. Output pure, copy-paste-ready text.
2. Adapt to the Chat Channel Context: Check [G], [P], [S], [W], [Y] tags and tailor RP accordingly.
3. Always Output RP in English: Write all 5 RP chat options in natural, casual lowercase English.
4. Keep It Short: 1-2 short sentences max per option so it fits fast-paced WoW chat.
5. Follow the [Instruction] Line: If the snapshot has an [Instruction] line, it is the user's direction for these replies (tone, focus, who to answer, what to do). Follow it. It is not chat and never something a character said.
```

</details>

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

Loot lines are colored the way the game colors them: item names by quality (gray, white, green, blue, purple, orange), money in gold, silver and copper colors, and the rest of the line in a soft teal.

Give the AI a one-time instruction with `/rp <instruction>`, for example `/rp make it flirty` or `/rp reply to Thrall only`. It goes at the top of the snapshot as `[Instruction]`, so the AI follows it instead of treating it as chat.

---

## Adventures: dungeon and raid stories

RPCopy also works as a quiet chronicler. The point of recording a run is to capture all the context a storyteller needs: who was there, which bosses fell, who died, what dropped, and what everyone said in the middle of each fight. RPCopy packs that into one log that's ready to send straight to your AI. The AI writes a full story from it. You import the story back onto that run, where it's saved, and read it in game as a colorful chronicle.

The flow is:

1. **Play the run.** RPCopy logs it automatically.
2. **Copy the Full Log** from the run in the Adventures view.
3. **Paste it into your AI** with the `wow-adventure-story` skill. The skill's template is in the Story view. The AI returns a story written with WoW color codes.
4. **Import Story** on the same run. The story is saved with that run.
5. **Read it in game** in the Story reader, with gold chapter titles, class-colored party names and orange bosses. Drag the grip in the window's bottom-right corner to make it bigger and see more of the story at once. Right-click the grip to reset the size.

![The in-game Story reader showing a colored Shadowfang Keep chapter](docs/story-viewer.png)

How it works:

- **Automatic logging** starts when you enter a dungeon or raid and stops when you leave. You can also start a run manually anywhere.
- **Timestamped `[HH:MM:SS]` timeline** with these tags:
  - `[BOSS ENGAGED]` when a boss is pulled
  - `[BOSS HP]` at 50%, 20% and 5%
  - `[DANGER]` at low HP, and `[LOW MANA]` at low mana
  - `[DEATH]` for your own deaths
  - `[WIPE #N]`
  - `[REZ]` for resurrections
  - `[LOOT]` for Uncommon or better drops
- **Fight context on chat.** Chat is tagged with the fight it happened in, for example `[Party | vs Boss 5% HP] Healer: OOM!!`, so the story knows exactly when someone panicked.
- **Mark Moment.** Set a key in **Options > Mark Moment** (or use the WoW keybinding or `/rp mark [note]`) to star a moment as a highlight. With Auto-Shots on, it also takes a screenshot.
- **Full Log** export, then **Import Story**. Copy the log into an AI that has the `wow-adventure-story` skill (its template is in the Story view). Paste the colored chronicle back, and read it in the in-game **Story** reader. The story skill is told to use only what's in the log: no invented bosses, loot or quotes.
- **Auto screenshots** (turn on **Auto-Shots**) at key moments during a run: every boss kill, marked moments, level-ups, quests and new zones. Boss kills and marks always get a shot; the others are spaced at least 20 seconds apart. Boss kills are detected from the encounter end, or from the boss dying on your target or boss frame. Shots are combat-safe and capped per run.
- Up to 40 runs are archived.

---

## Slash commands

| Command | What it does |
|---|---|
| `/rp` or `/rpcopy` | Open the RPCopy window |
| `/rp <instruction>` | Open the window with a one-time instruction for the AI added to the snapshot |
| `/rp quick` | Quick-copy the last used slice |
| `/rp capture` | Save or update your target (or mouseover, or last whisperer) as a companion |
| `/rp mark [note]` | Bookmark the latest moment, or your note, in the active run |
| `/rp clear` | Clear the session chat, combat, NPC and loot buffers |
| (window) | Drag the bottom-right grip to resize the RPCopy window, right-click it to reset. The size is saved. |
| `/rp btn` | Show or hide the draggable floating `[RP]` button (right-click it to clear logs) |

## Keybindings

The **Options** keybinding bar sets RPCopy's own shortcuts: **Quick Copy** (`Ctrl+C`), **Target** capture (`Shift+C`) and **Mark Moment** (no key until you set one; right-click to clear). Click a key button and press the combo you want. Avoid Ctrl combos for Target and Mark, since instant `Ctrl+C` takes the keyboard while Ctrl is held.

You can also set these in **Esc > Key Bindings > AddOns > RPCopy (RP Context & Chronicle)**:

| Binding | Action |
|---|---|
| Toggle RPCopy Window | Open or close the main window |
| Quick Copy (Last Used Slice) | Same as `/rp quick` |
| Capture / Update Target Companion | Same as `/rp capture` |
| Bookmark Adventure Moment | Same as `/rp mark` |

Silent quick copy (`Ctrl+C` by default) copies on the first press, in or out of combat, without stopping your character. WoW addons can't write to the clipboard directly, so when you press Ctrl down RPCopy briefly focuses a hidden box with the snapshot selected, and your own Ctrl+C copies it. The box lets go as soon as you press C, press any other key or release Ctrl. While Ctrl is held, other Ctrl+key shortcuts won't fire. If you set a custom key in Options, it uses two presses: your key arms the copy, then Ctrl+C copies. You can also turn it off in Options.

---

## Installation

1. Download `RPCopy-vX.Y.Z.zip` from the latest [Release](https://github.com/azaxyno/RPCopy/releases) and unzip it into your AddOns folder. Or clone the repository: `git clone https://github.com/azaxyno/RPCopy.git`.
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
- The Forever client runs on the modern engine, where `COMBAT_LOG_EVENT_UNFILTERED` is Blizzard-only. Registering it shows the "blocked from an action only available to the Blizzard UI" popup on every load, so RPCopy skips it when `issecretvalue` exists. Boss kills come from `ENCOUNTER_END` and your own deaths from `PLAYER_DEAD`. If that popup ever shows up, `Logs/taint.log` in the game folder names the file and line.
- **Versioning.** Bump `## Version` in `RPCopy.toc` with every change: a patch bump (0.1.0 to 0.1.1) for small fixes, a minor bump (0.1 to 0.2) for big updates. RPCopy is in alpha, so versions stay below 1.0. The chat banner on load reads it, so you can tell at a glance which build is running. Each version is tagged and published as a GitHub Release with a downloadable zip.

---

## Credits

The recording and event-engine techniques are adapted from [StoryTracker](https://github.com/ninepointlabs/wow-storytracker-addon) by Nine Point Labs (MIT). See [CREDITS.md](CREDITS.md).

## License

MIT, see [LICENSE](LICENSE).
