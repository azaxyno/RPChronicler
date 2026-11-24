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

Along the way, RPCopy remembers the **companions** you meet, so your AI knows who they are next time. It also records your **dungeon and raid runs** and your **open-world adventures**, so the AI can turn them into colored stories you keep in an in-game **Story Book**.

- **Version:** 0.4.0 alpha (interface `16001`, WoW: Forever)
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
   The rail on the left of the window switches between **Copy**, **Companions** and **Adventures**. The **gear** at the top right opens **Options**.
2. **Create your character skill** (one time):
   - Click the **gear** at the top right of the window, open **AI Setup**, and click **RP Template**. Copy the template with `Ctrl+C`.
   - Paste it into Gemini, ChatGPT or Claude (see [Requirements](#requirements) for which plan and how to build a skill). Fill in your character: name, faction, race, class, personality, quirks and inspiration. Let the AI build the skill.
   - Pick a short **trigger**, such as `use aloria`, and enter it as the **Skill Call** of your slice in **Options > Slice Tabs**. Every snapshot starts with `[Skill Call] use aloria`, so the AI knows to use your character's skill.
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

## Requirements

RPCopy itself is free and runs inside the game. You also need an AI chat that can keep a reusable set of instructions (a "skill"). Gemini, ChatGPT and Claude all work.

**The one hard requirement: a place to save the skill.** Each of these has one on its free plan:

| AI | Where the skill lives |
|---|---|
| **Google Gemini** | A **Gem**: Gems > New Gem, paste the template as its instructions |
| **ChatGPT** | A **Project**: New project, paste the template into its instructions |
| **Claude** | A **Project** (paste the template into its instructions) or a **Skill** |

If your AI or plan has none of these, you can still paste the template at the start of a new chat each time. It works, it's just more steps.

**Which model?** The model matters more than the plan. Fast, light models are fine for the short RP replies. For stories, use the strongest model your AI offers (its "pro" or "thinking" model). These models follow the color rules better, keep the whole run in mind and write better prose. Free plans often give only limited access to those models, and their shorter context can cut off a long dungeon log. If a story comes out short or forgets the start of the run, switch to a stronger model, or trim the Full Log in **Options > Full Log**. The **size meter** above each Full Log shows whether it fits the AI you picked there.

**Building a skill (one time each):**

1. In RPCopy, open the gear > **AI Setup** and copy a template: **RP Template** for your character, **Dungeon/Raid Story** and **Adventure Story** for the storyteller.
2. In your AI, make a Gem (Gemini), a Project (ChatGPT or Claude) or a Skill (Claude), and paste the template as its instructions. For the RP template, ask the AI to fill in your character first.
3. Open a chat inside that Gem or Project and paste what RPCopy copied. The first line (`use aloria`, `use story`, `use adventure story`) tells the AI which skill to use.

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
| **Chat** | Conversations nearby: the message to you, your target, say, yell, emotes and whispers |
| **World** | General, Trade, LFG and other numbered channels (never the OOC channel) |
| **Party** | Your group only: party and raid chat, say and emotes from party members, the roster and status |
| **Guild** | Guild chat and officer chat |
| **Quest** | Questing flavor: your active quest, your target and NPC dialogue |
| **Loot** | Reacting to drops: green and better items and your coin, summed |

You can change what every tab copies, built-in ones included, in **Options > Slice Tabs**, and add **custom tabs** with their own Skill Call. The sections are: last whisper or say to you, target info, party roster, status (with your pet, and deaths or level ups from the last 15 minutes), active quest, say / yell / whispers, say and emotes from party members only, party and raid chat, NPC dialogue, loot, the OOC channel, world channels, and guild and officer chat. `Ctrl+C` always copies the slice you used last.

How the copy reads:

- **One timeline.** All the chat sections a tab includes are merged into one list in the order things happened, so the AI sees who said what, and when.
- **No repeats.** When the message to you is already in the timeline, it is marked `[Direct]` there instead of being copied twice. A companion's "Latest Chat" leaves out lines the copy already shows. There is one quest line only.
- **World chat stays out of the way.** Trade, General and LFG have their own buffer, and guild chat has another, so busy channels never push nearby RP out. They have their own **World** and **Guild** tabs, and you can add **World channels** or **Guild & officer chat** to any tab.
- **Clean loot.** Green and better items, and who won them, are kept. Gray items and roll messages ("has selected Greed", "passed on") are left out, and the coin you pick up is summed into one line, such as `You picked up 2 Gold 2 Silver 8 Copper (3 pickups)`.

When you update to 0.4.0, the old **Smart** tab is removed (Ctrl+C then copies **Chat**), and **World** and **Guild** are added. Your other tabs, Skill Calls and custom tabs aren't touched.

Loot lines are colored the way the game colors them: item names by quality (gray, white, green, blue, purple, orange), money in gold, silver and copper colors, and the rest of the line in a soft teal.

Give the AI a one-time instruction with `/rp <instruction>`, for example `/rp make it flirty` or `/rp reply to Thrall only`. It goes at the top of the snapshot as `[Instruction]`, so the AI follows it instead of treating it as chat.

---

## Adventures: recordings and the Story Book

RPCopy also works as a quiet chronicler. Recording a run captures what a storyteller needs: who was there, where you went, what you fought, who nearly died, what dropped and where it came from, the quests you took, and what everyone said. RPCopy packs that into one **Full Log** that's ready to paste into your AI. The AI writes a story from it, you import it, and it lands in the **Story Book**.

Adventures has two tabs at the top:

- **Recordings:** the record bar, every recorded run, its **Summary** and **Full Log**, the story **Template** for that kind of run, and a **Story** button that jumps to the run's story (or imports one).
- **Story Book:** every run that has a story, with a large reader. Each entry is named from the story, for example *Shadows Over Pyrewood - Shadowfang Keep*, and shows its dungeon or region, zone, duration, date, party, bosses, wipes, deaths and chapters. **Share** copies the story as clean plain text for Discord or a forum. **Details** lets you edit any of those fields. **Re-Import** replaces the story (your edited details stay), **Delete** removes the story but keeps the recording, and **Recording** jumps back to the run.

The flow is:

1. **Play.** Dungeons and raids record by themselves (you can turn that off in **Options > Recording**). In the open world, click **Start Recording**, use the `[RP]` icon's right-click menu, or a keybind. Joining a group asks whether to start recording, and you can turn that question off, or turn on the same question at login.
2. **Copy the Full Log** in Recordings: click **Select All**, then `Ctrl+C`. The first line is the skill trigger: `use story` for dungeons and raids, `use adventure story` for the open world. The **size meter** above it shows whether it fits your AI.
3. **Paste it into your AI** with the matching storyteller skill. There are two templates (gear > **AI Setup**, or **Template** in Recordings, right-click for the other one):
   - **Dungeon/Raid Story:** one chapter per boss, the whole party in it.
   - **Adventure Story:** solo or open world, introspective, with chapters by place and event.
   Both write a header (title, then `dungeon or region | duration | zone`, then date and party) and a footer (`Bosses | Wipes | Deaths`) that the Story Book reads, and both use the same colors: class colors (Priests in gray), crimson bosses, gold titles.
4. **Import Story:** in the Story Book (or with **Story** in Recordings) pick the run, paste the colored story, and save.
5. **Read it in game,** with gold chapter titles, class-colored party names and crimson bosses. Each boss name gets an icon: a skull for a boss, a gold dragon for an elite and a silver dragon for a rare. Drag the grip in the window's bottom-right corner to make the reader bigger.

![The in-game Story reader showing a colored Shadowfang Keep chapter](docs/story-viewer.png)

How recording works:

- **One Start / Stop button.** It's green when you can start and turns red (**Stop & Save**) while a run records. **Pause** and **Mark Moment** sit next to it. Each also has a key in **Options > Keybinds**, and `/rp start`, `/rp pause`, `/rp resume`, `/rp end`.
- **The `[RP]` icon.** Left-click opens the window. Right-click opens a small menu: Start Recording or Stop & Save, Pause or Resume, Mark Moment, Story Book, Clear chat logs. While a run records, the icon turns red with a pulsing dot; while paused it dims and turns amber. You can turn the colors off in **Options > Recording**.
- **Never lost.** The live run is saved as you play. After a `/reload` or a short disconnect (back within 2 minutes) it simply continues. After a logout or a longer disconnect it is closed and saved, marked **interrupted**, and the next login asks whether to **resume** it or **keep** it as it is.
- **Pause and Resume.** A paused run records nothing until you resume it, and it isn't ended when you leave the instance.
- **Rich but short.** The Full Log aims for one meaningful line instead of many raw ones, and it never keeps out-of-character chat: `(( ))`, `[OOC]`, the OOC channel and OOC notes stay out, and so do guild and world channels.
- **Timestamped `[HH:MM:SS]` timeline** with these tags:
  - `[FIGHT]` one line per fight, for example `[FIGHT] vs Bandit Highwayman (12s) - Bandit Highwayman fled twice - Grakk took aggro from Aloria - defeated`. Very short fights with no kill or death are skipped.
  - `[KILL]` for elites, rares and named foes, for example `[KILL] Aloria defeats Bandit Highwayman (elite)`. Trash is counted in the header as **Foes defeated**.
  - `[BOSS ENGAGED]`, `[BOSS HP]` at 50%, 20% and 5%, `[BOSS RESET]`, `[BOSS KILL]`, `[BOSS CAST]`, `[WIPE #N]`
  - `[AGGRO]` when an enemy turns from one party member to another
  - `[DANGER]` under 10% HP, `[SAVED]` when pulled back, `[LOW MANA]`
  - `[DEATH]` with what you were fighting and your last health, for example `[DEATH] Aloria died (fighting Hogger, last seen at 5% HP)`, and `[REZ]`
  - `[SPELL]` party spells in combat, pets included (`Fluffy (Aloria's pet)`), `[CC]` crowd control, `[PET]` and `[PET DEATH]`. In the open world they are throttled harder than in dungeons.
  - `[QUEST]` quests accepted and completed (no objective spam), and `[QUEST TEXT]` the quest giver's words, trimmed
  - `[NPC]` and `[NPC Emote]` lines from bosses and named NPCs, throttled and de-duplicated. Flee emotes become part of the `[FIGHT]` line.
  - `[LEVEL]` level ups, `[PLACE]` new subzones, `[SKILL]` profession skill-ups (`Mining 74 -> 75`, also summed in the header)
  - `[MILESTONE]` a new spell, a tamed, renamed or dismissed pet, a new companion pet or mount, an achievement, a new reputation standing, a hearthstone bind, a new flight path
  - `[LOOT]` quest items and green or better items, with where they came from: crafted, from a named foe, quest reward, bought, traded, mail or gathered. Coin is summed into **Coin looted** in the header.
  - `[ATMOSPHERE]` the time of day (dawn to night, from the server clock) and indoors or open sky, at the start and on zone changes. The game has no weather API, so weather is left to the storyteller.
  - `[HIGHLIGHT]` moments you marked
- **Header.** The Full Log starts with the run type (Dungeon, Raid or Open world adventure), zone, date, duration, wipes and deaths, the roster with roles and guild (`Grakk <Iron Oath> (guildmate)` for members of your guild), Known companions, bosses, foes defeated, notable loot with sources, coin and skill-ups.
- **Everything is a switch.** **Options > Full Log** has a checkbox for every kind of line, editable limits (shortest fight, spell lines, NPC lines and timeline lines per run), the AI picker for the size meter, and the size meter itself. **Options > Recording** has auto-record, the prompts, resume after reload, the icon colors and auto-screenshots.
- **Roles always shown.** When nobody picked a role, RPCopy guesses Tank, Healer or DPS from forms, stances, talents, who holds aggro, and finally the class.
- **Fight context on chat.** Chat is tagged with the fight it happened in, for example `[Party | vs Boss 5% HP] Healer: OOM!!`.
- **Export stories to files.** Double-click `Export_Stories.bat` in the RPCopy folder. It writes every saved run to `World of Warcraft\_forever_\RPCopy Stories\`: the story as a colored web page and as plain text, the Full Log, and an `index.html`. It needs only Windows PowerShell. The game saves your data on `/reload` or logout, so do one of those first.
- **Auto screenshots** (Options > Recording) on boss kills, marked moments, level-ups, quests and new zones. Combat-safe and capped per run.
- Up to 40 runs are archived.

---

## Slash commands

| Command | What it does |
|---|---|
| `/rp` or `/rpcopy` | Open the RPCopy window |
| `/rp <instruction>` | Open the window with a one-time instruction for the AI added to the snapshot |
| `/rp start` | Start recording an adventure |
| `/rp book` | Open the Story Book |
| `/rp debug` | Open the debug report to copy into a bug report (`/rp debug clear` empties the log) |
| `/rp options` | Open Options (also `/rp config`) |
| `/rp companions` / `/rp adventures` | Open the window on that view |
| `/rp quick` | Quick-copy the last used slice |
| `/rp capture` | Save or update your target (or mouseover, or last whisperer) as a companion |
| `/rp mark [note]` | Bookmark the latest moment, or your note, in the active run |
| `/rp pause` / `/rp resume` | Pause or resume recording the active run |
| `/rp end` | End and save the active run |
| `/rp diag` | Print what RPCopy can read about your target (boss detection, health, its target) and your guessed role. Handy when boss HP lines don't show up |
| `/rp clear` | Clear the session chat, combat, NPC and loot buffers |
| (window) | Drag the title bar to move the window and the bottom-right grip to resize it. Right-click the grip to reset size and place. Both are saved. Press `Esc` to close it. |
| `/rp btn` | Show or hide the draggable floating `[RP]` button (right-click it for the recording menu) |

## Keybindings

Click the **gear** and open **Keybinds** to set RPCopy's own shortcuts. Click a key button and press the combo you want. Right-click a key button to clear it (or reset it to its default).

| Keybind | Default |
|---|---|
| Quick Copy | `Ctrl+C` |
| Capture Target | `Shift+C` |
| Mark Moment | none |
| Open / Close Window | none |
| Start Recording | none |
| Pause / Resume Recording | none |
| End Recording | none |

You can also set these in **Esc > Key Bindings > AddOns > RPCopy (RP Context & Chronicle)**:

| Binding | Action |
|---|---|
| Toggle RPCopy Window | Open or close the main window |
| Quick Copy (Last Used Slice) | Same as `/rp quick` |
| Capture / Update Target Companion | Same as `/rp capture` |
| Bookmark Adventure Moment | Same as `/rp mark` |
| Start Recording an Adventure | Same as `/rp start` |
| Pause / Resume Recording | Same as `/rp pause` and `/rp resume` |
| End & Save Recording | Same as `/rp end` |

### How Ctrl+C copying works

WoW addons can't write to the clipboard directly. RPCopy puts the snapshot, selected, in a hidden box, and your own `Ctrl+C` copies it. There are two copy styles in **Options > Keybinds**:

- **Instant** (default). Hold Ctrl for a moment and RPCopy gets the box ready, so `Ctrl+C` copies on the first press. Your other Ctrl shortcuts (`Ctrl+1`, `Ctrl+Q` and so on) still work: RPCopy only takes `Ctrl+C`, and lets every other key pass through to the game. If you press `Ctrl+C` very fast, it gets the box ready and a second `Ctrl+C` copies.
- **Two-press.** The first `Ctrl+C` gets the box ready, the second copies. Ctrl is never watched.

In combat, Instant switches to two-press so nothing interferes with your keys, unless you turn on **Instant in combat**. A custom Quick Copy key always works as two-press: your key gets the box ready, then `Ctrl+C` copies. You can also turn Quick Copy off.

---

## Reporting bugs

RPCopy keeps a small debug log (about 200 lines) in its saved data: its own Lua errors, "blocked action" events, and when runs start, pause, end or get a story. It never stores chat.

1. Type `/rp debug` (or gear > **Debug** > **Copy Debug Report**). A box opens with your RPCopy version, the game client and interface, your locale, a summary of your settings and the log.
2. Click **Select All**, press `Ctrl+C`, and paste it into a [GitHub issue](https://github.com/azaxyno/RPCopy/issues) along with what you were doing.
3. Chasing something odd? Turn on **Verbose debug log** in gear > **Debug**, reproduce it, and copy the report again.

If the game shows a "blocked from an action" popup, `Logs\taint.log` in your game folder names the file and line. Attach it too.

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
| 1 | `Core.lua` | Database setup and migration, default tabs, Full Log categories and limits, AI picker sizes, colors, class and role formatting, log ring buffers, companion lookup, `NormalizeStoryText` | `EnsureDB`, `LogOn`, `Limit`, `PushLog`, `SaveOrUpdatePlayer`, `GetKnownPlayerBlocks` |
| 2 | `Debug.lua` | Debug log ring buffer, RPCopy-only error hook, blocked-action events, the `/rp debug` report | `Debug`, `DebugReady`, `BuildDebugReport` |
| 3 | `Snapshot.lua` | Builds snapshot text from the active slice's settings | `BuildSnapshot`, `GetTabConfig`, `ResetDefaultTabs`, `ClearSessionLogs` |
| 4 | `Adventures.lua` | Run lifecycle, interrupted runs, timeline telemetry, Full Log export, size, story storage and Story Book metadata | `StartAdventure`, `EndAdventure`, `RestoreSavedAdventure`, `BuildAdventureFullLog`, `SetAdventureStory`, `ParseStoryMeta`, `GetBookInfo` |
| 5 | `Screenshots.lua` | Debounced, combat-safe automatic screenshots | `RequestScreenshot` |
| 6 | `Events.lua` | Central event dispatcher (chat, unit health and power, threat, loot, instance changes), the combat poller for boss HP, pull ends and aggro, and the spell, boss cast, CC and pet trackers | internal `RPCopyEventFrame` |
| 7 | `Chronicle.lua` | Story-level lines for every run type: fights, kills, quests, NPC filter, levels, places, skills, milestones, loot sources, atmosphere, and the start-recording prompts | `FightBegin`, `FightFlush`, `ClassifyLootSource`, `RecordAtmosphere`, `ChronicleNpc` |
| 8 | `UI_Shell.lua` | Shared `ns.UI` table, option defaults, theme and button helpers, prompt and copy boxes, the main window | `UI.NewSection`, `UI.ShowSection`, `UI.ShowPrompt`, `UI.ShowCopyBox`, `RPCopy_Open` |
| 9 | `UI_Copy.lua` | Copy view, quick-copy engine | `RPCopy_QuickCopy`, `RPCopy_CaptureTarget` |
| 10 | `UI_Companions.lua` | Companions view | `UI.RefreshPlayersTab`, `UI.OpenCompanion` |
| 11 | `UI_Adventures.lua` | Adventures view: Recordings and Story Book tabs, record bar, run list, size meter, story import | `RPCopy_ToggleRun`, `UI.ShowAdventuresSub`, `UI.OpenStoryImportModal` |
| 12 | `UI_StoryBook.lua` | Story Book: library, reader, Share, Details, Re-Import, Delete | `UI.RefreshStoryBook` |
| 13 | `UI_Options.lua` | Options pages (General, Keybinds, Slice Tabs, Recording, Full Log, AI Setup, Debug), the RP and two story templates, key capture | `UI.OpenOptionsPage`, `UI.OpenSkillTemplateModal` |
| 14 | `UI_Commands.lua` | Keybind override buttons, floating `[RP]` button and its menu, slash commands | `UI.UpdateOverrideBindings`, `UI.ToggleIconMenu` |
| | `Bindings.xml` | Keybinding definitions | |

### Saved data (`RPCopyDB`)

| Key | Contents |
|---|---|
| `tabs` | Your slice tabs (label, trigger, section toggles) |
| `players[name]` | Companions: your note, level, race, class, guild, last seen, last 5 chat lines |
| `adventures` | Up to 40 runs: run type, zone, dates, duration, party (with guild), wipes, deaths, boss kills and boss types (for the icons), notable kills, foes defeated, loot with sources, coin, skill-ups, highlights, timeline, screenshots, export text, story and its Story Book details (`book`) |
| `activeRun` | The run being recorded right now (with its paused state), so it survives `/reload` and disconnects |
| `knownBosses` | Names of bosses you've fought, so classic bosses without a skull are recognized next time |
| `quickCtrlC`, `autoScreenshots`, `copyMode`, `instantInCombat` | Feature toggles and the copy style |
| `autoRecord`, `promptOnGroup`, `promptOnLogin`, `resumeAfterReload`, `iconState`, `sizeMeter` | Recording options |
| `logCats`, `limits`, `aiModel`, `aiCustomLimit` | Full Log categories, limits and the AI picked for the size meter |
| `debugLog`, `debugVerbose` | The debug log (about 200 lines, no chat) and its verbose switch |
| `quickCopyKey`, `captureTargetKey`, `markMomentKey`, `openWindowKey`, `runStartKey`, `runPauseKey`, `runEndKey` | Your RPCopy keybinds |
| `frameW`, `frameH`, `frameX`, `frameY`, `optionsPage` | Window size, place and the last Options page |

Session buffers (`ns.logs`) live only in memory and are cleared on `/reload` or `/rp clear`.

### WoW: Forever compatibility notes

- The addon targets the WoW: Forever client (`## Interface: 16001`). APIs that don't exist on every client are checked before they're called, so a missing API turns a feature off instead of throwing a Lua error.
- `IsInInstance()` is called directly and both of its return values are used. Writing `IsInInstance and IsInInstance()` would keep only the first value and break dungeon and raid detection.
- WoW fonts can't draw Unicode symbols such as stars, arrows or smart quotes, so all in-game text is plain ASCII. Colors use `|cffRRGGBB...|r` escape codes only, never Markdown.
- Text pasted into WoW edit boxes turns `|` into `||`. `ns.NormalizeStoryText` converts it back, strips code fences, and closes any open color tags before the story is rendered.
- Screenshots fade `UIParent` with `SetAlpha` instead of hiding it, which avoids `ADDON_ACTION_BLOCKED` in combat.
- The Forever client runs on the modern engine, where `COMBAT_LOG_EVENT_UNFILTERED` is Blizzard-only. Registering it shows the "blocked from an action only available to the Blizzard UI" popup on every load, so RPCopy never registers it. A light poller (a plain frame, no protected calls) reads boss HP from `boss1-5`, `target`, `focus` and `partyNtarget`, ends pulls when the whole group leaves combat, and tracks aggro from each enemy's target (target, party targets and nameplates). Boss kills come from `ENCOUNTER_END` or a dead boss unit, and your own deaths from `PLAYER_DEAD`. Party spells, boss casts, crowd control and pets come from `UNIT_SPELLCAST_*`, `UNIT_AURA`, `UNIT_PET` and `UNIT_HEALTH` while a run records (with stricter throttles in the open world). Kills come from enemies seen in the fight that later read as dead. Values the client hides as "secret" are skipped instead of erroring; `/rp diag` shows what is readable. If that popup ever shows up, `Logs/taint.log` in the game folder names the file and line.
- **Versioning.** Bump `## Version` in `RPCopy.toc` with every change: a patch bump (0.1.0 to 0.1.1) for small fixes, a minor bump (0.1 to 0.2) for big updates. RPCopy is in alpha, so versions stay below 1.0. The chat banner on load reads it, so you can tell at a glance which build is running. Each version is tagged and published as a GitHub Release with a downloadable zip.

---

## Credits

The recording and event-engine techniques are adapted from [StoryTracker](https://github.com/ninepointlabs/wow-storytracker-addon) by Nine Point Labs (MIT). See [CREDITS.md](CREDITS.md).

## License

MIT, see [LICENSE](LICENSE).
