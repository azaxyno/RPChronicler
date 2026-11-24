# RPCopy Architecture & Module Reference (0.3.1)

This replaces the old "RPCopy v3.6 Architecture & Module Reference" PDF, which describes a single `UI.lua` and the retired 3.x versions.

## 1. What the addon does

RPCopy is a WoW: Forever addon (`## Interface: 16001`, alpha, MIT). It has three jobs:

1. **Copy the scene.** `Ctrl+C` puts a text snapshot of the current situation in the clipboard. The player pastes it into an AI that holds their character skill. Line 1 is the Skill Call (`[Skill Call] use aloria`) that triggers the skill.
2. **Remember companions.** It saves players with your RP note and their last 5 chat lines. A `[Known Player]` block is added whenever they show up in a snapshot.
3. **Chronicle runs.** It records dungeons and raids as a timestamped Full Log, which the AI storyteller skill turns into a colored story. The story is imported back and read in game.

It never sends chat. All data lives in the account-wide SavedVariable `RPCopyDB`.

## 2. Files and load order

Every file starts with `local ADDON_NAME, ns = ...` and shares `ns`. The UI files also share `local UI = ns.UI`, created by `UI_Shell.lua`. The order in `RPCopy.toc` matters:

| # | File | Role |
|---|---|---|
| 1 | `Core.lua` | Version, binding names, `RPCopyDB` defaults, `ns.TAB_FLAGS` / `ns.DEFAULT_TABS`, `ns.COLORS` / `ns.CLASS_COLORS`, safe-value helpers, name and realm helpers, role guessing, log buffers, companions, `NormalizeStoryText`, `EnsureDB` and migrations |
| 2 | `Snapshot.lua` | Target, Party and Status lines; `ns.BuildSnapshot` |
| 3 | `Adventures.lua` | Run state and lifecycle, all `Record*` functions, Summary and Full Log builders, story storage, boss icons |
| 4 | `Screenshots.lua` | `ns.RequestScreenshot(kind, caption)` |
| 5 | `Events.lua` | `RPCopyEventFrame` router, chat and loot handling, combat poller, run trackers, `/rp diag` |
| 6 | `UI_Shell.lua` | `ns.UI`, `UI.EnsureOptions`, theme and widgets, main window `RPCopyFrame`, rail, sections, status line, resize, toast, `RPCopy_Open` / `RPCopy_Toggle` |
| 7 | `UI_Copy.lua` | Quick-copy engine, `RPCopy_QuickCopy`, `RPCopy_CaptureTarget`, COPY section |
| 8 | `UI_Companions.lua` | PLAYERS section (list and note editor) |
| 9 | `UI_Adventures.lua` | `RPCopy_StartRun` / `RPCopy_ToggleRunPause` / `RPCopy_EndRun`, story import modal, ADVENTURES section, Story reader |
| 10 | `UI_Options.lua` | Skill templates, template modal, key capture modal, OPTIONS section pages |
| 11 | `UI_Commands.lua` | Hidden keybind buttons, `UI.UpdateOverrideBindings`, floating `[RP]` button, `/rp` slash commands |
| | `Bindings.xml` | Key Bindings entries |
| | `Export_Stories.bat` | Batch + PowerShell exporter (section 10) |
| | `tools/check_locals.py` | Counts active locals per function (Lua 5.1 limit of 200) |

Other folders: `docs/` (screenshots and this file), `tools/`, and `.pkgmeta` (CurseForge packager). None of them ship in the release zip.

## 3. Shared helpers (Core.lua)

- **Safe values:** `ns.IsSecret`, `ns.SafeStr`, `ns.SafeNum`. On the modern engine some unit values are "secret", and comparing or concatenating them errors. Always pass unit API results through these.
- **Text:** `ColorText(text, hex)`, `StripColors`, `CleanText` (removes links and colors), `CleanChatKeepColors`, `NormalizeGlyphs` (non-ASCII to ASCII), and `NormalizeStoryText` (`||` to `|`, strips code fences and Markdown, closes open color tags).
- **Names:** `StripRealm`, `SplitFullName`, `JoinFullName`, `GetUnitFullName` (a "First Last" name from UnitFullName, the PvP title name or the tooltip, else the plain name), `ResolveCanonicalPlayerName`, `FindPlayerKey(name, allowFirstNameUpgrade)`.
- **Roles:** `GetUnitRole(unit)` returns the role and whether it was guessed. The guess comes from the assigned role, then forms and stances, talents, aggro share, then class. `GetRoleTag(role, useIcon)` formats it.
- **Time:** `NowStamp`, `TimeOnlyStamp`, `FormatDuration`.
- **Colors:**
  - `ns.COLORS` has the UI and log colors. `boss` is crimson `dc143c`.
  - `ns.CLASS_COLORS` holds the class colors, with Priest gray `C0C0C0` so it reads on the parchment.
  - `ColorizeClass` uses these.

## 4. Saved data (`RPCopyDB`)

| Key | Contents |
|---|---|
| `tabs` | Slice tabs (section 5) |
| `players[name]` | `{ note, level, race, class, guild, chatHistory (last 5), lastSeen }` |
| `adventures` | Up to 40 finished runs, newest first |
| `activeRun` | The run being recorded, saved live so it survives `/reload` and disconnects |
| `knownBosses[name]` | Bosses fought before, so classic bosses without a skull are recognized |
| `autoUpdateKnown`, `autoScreenshots` | Toggles |
| `quickCtrlC`, `quickCopyKey` (`CTRL-C`), `copyMode` (`INSTANT` / `TWOPRESS`), `instantInCombat` | Quick copy |
| `quickCapture`, `captureTargetKey` (`SHIFT-C`), `markMomentKey`, `openWindowKey`, `runStartKey`, `runPauseKey`, `runEndKey` | RPCopy's own keybinds (`""` means unbound) |
| `lastSliceId`, `defaultMessages` (3), `expandMessages` (6) | Copy view |
| `frameW`, `frameH`, `frameX`, `frameY`, `optionsPage` | Window size and place, last Options page |
| `migratedV32`, `migratedV031` | One-time migration flags |

Defaults and migrations:

- **`ns.EnsureDB`** (Core) runs everywhere. It fills defaults, converts old string-only player entries and old `info` strings, rebuilds missing `exportText`, and migrates tabs:
  - It adds `incOoc`, `incPartySay` and `incWorld` when missing.
  - It drops `incCombat`.
  - Once, behind `migratedV031`, it resets the built-in tabs' flags to the 0.3.1 defaults. Labels and prefixes are kept, and custom tabs aren't touched.
- **`UI.EnsureOptions`** (UI_Shell) fills the key and copy-mode defaults.

Session buffers (`ns.logs`) are in memory only and are cleared by `/reload`, `/rp clear` or right-clicking `[RP]`.

## 5. Copy snapshots and slice tabs

**Log buffers** (`ns.logs`, 25 entries each, via `ns.PushLog(tbl, line, author, chan)`). Each entry is `{ line, seq, author, chan }`, where `seq` is a global counter. Use `ns.LogLine(entry)` to read one, which also handles legacy strings.

| Buffer | Filled by |
|---|---|
| `social` | Say, yell, emote, whispers (in and out) |
| `party` | Party, raid, instance chat |
| `world` | Guild and numbered channels (Trade, General, LFG) |
| `ooc` | A channel named OOC (split off from social or world in `PushLog`) |
| `npc` | NPC say, yell, emote and whisper; boss emotes |
| `loot` | Filtered loot (below) |
| `combat` | Your deaths and level ups, with `at = time()`, read by the Status line |
| `playerRecentChat` | Per-player convo lines, which feed `players[].chatHistory` |

The state used by snapshots:
- `ns.state.lastDirectMsg` / `lastDirectEntry` / `lastDirectAuthor`: the last say or whisper from someone else.
- `ns.state.lastQuestInfo`: the single quest line.
- `ns.state.activeNote`: the `/rp <instruction>` text.

**Loot filter** (Events.lua):
- Items are kept when they are green or better, or when the quality is unknown. Lines with no item link, such as currency, are kept.
- Roll chatter ("has selected", "passed on", "Roll - N") is dropped. "won" lines are kept.
- `CHAT_MSG_MONEY`, which is always your own coin, is summed into one entry that updates in place: "You picked up X (N pickups)". A pickup more than 2 minutes after the last one starts a new line.

**Tab flags** (`ns.TAB_FLAGS`):

| Flag | Section |
|---|---|
| `incDirect` | `[Direct]` last say or whisper to you |
| `incTarget` | `[Target]` line |
| `incParty` | `[Party]` roster |
| `incStatus` | `[Status]`: level, role, combat, HP, mana, pet, and "Recent:" deaths and level ups from the last 15 minutes |
| `incQuest` | One `[Quest]` line |
| `incSocial` | social buffer |
| `incPartySay` | say, yell and emotes from you and party members only (ignored when `incSocial` is on) |
| `incPartyChat` | party buffer |
| `incNpc` | npc buffer |
| `incLoot` | loot buffer |
| `incOoc` | ooc buffer |
| `incWorld` | world buffer (off in every default tab) |

Built-in tabs: **SMART** (direct, target, party, status, social, party chat, NPC), **CHAT** (direct, target, social), **PARTY** (target, party, status, party say, party chat), **QUEST** (target, status, quest, NPC) and **LOOT** (party, status, loot). Each tab also has `id`, `label` and `prefix` (the Skill Call; empty means raw data only). Players edit all of this in Options > Slice Tabs.

**`ns.BuildSnapshot(tabId, note, expanded)`** builds the snapshot in this order:
1. `[Skill Call]`, `[Instruction]` and `[Location]`.
2. Direct, Target, Party, Status and Quest.
3. **One timeline:** the last `limit` entries of each included buffer (3, or 6 when expanded), deduplicated and sorted by `seq`. If the direct entry is in the timeline, it is tagged `[Direct]` there and the separate line is skipped.
4. `ns.GetKnownPlayerBlocks(body)`: one block per saved companion named in the body. A block's "Latest Chat" skips lines whose message is already in the body.

## 6. Quick copy (UI_Copy.lua)

Addons can't write to the clipboard. The only route is a focused EditBox with the text highlighted, copied by the game's own Ctrl+C.

- The hidden box is `RPCopySilentArmBox`. `UI.ArmCtrlCopy` focuses it with the snapshot of `lastSliceId` selected, and `UI.DisarmCtrlCopy` releases it.
- **INSTANT mode:**
  - `RPCopyCtrlWatcher` arms after Ctrl has been held 0.25 s (`ARM_DELAY`).
  - `RPCopyKeyListener` uses `SetPropagateKeyboardInput(true)`, set once out of combat and enabled only if propagation is verified. It marks the hold as used when another key is pressed with Ctrl, so other Ctrl+key binds pass through.
  - It is off in combat unless `instantInCombat` is set.
- **TWOPRESS mode, and any custom key:** the override binding `CTRL-C` -> `RPCopySilentCopyBtn` arms on the first press, and the second press copies. The binding is always set when the copy key is `CTRL-C`, so a fast Ctrl+C also works in INSTANT mode.

## 7. Adventures (Adventures.lua + Events.lua)

**Lifecycle:**
- `StartAdventure(title, isAuto)` starts a run. It ends any run already active, resets boss state and the run trackers, and saves `RPCopyDB.activeRun`.
- Auto runs start on `PLAYER_ENTERING_WORLD` in a party or raid instance. They end on leaving, unless paused. Entering a different dungeon starts a new run.
- `PauseAdventure` and `ResumeAdventure` work while paused: `PushTimeline` drops everything except forced lines.
- `RestoreSavedAdventure` runs at the first `PLAYER_ENTERING_WORLD`. The run resumes if you're back within 120 s or in the same instance; otherwise it comes back paused.
- `EndAdventure(reason)` saves the run into `adventures` (max 40). An auto run under 30 s with no activity is discarded.

**Run fields:**

| Field | Contents |
|---|---|
| `id`, `title`, `zone`, `instanceName`, `isAuto`, `paused` | Identity and state |
| `startTime`, `startDate`, `endDate`, `duration`, `lastSeen`, `reloads` | Timing |
| `participants[]` | `{ name, level, class, classFile, role, roleGuessed, note }` |
| `wipes`, `deaths`, `bossKills[]`, `keyLoot[]`, `highlights[]`, `shots[]` | Counts and lists |
| `bossInfo[name]` | `{ cls, level, kind }`, where kind is `skull`, `elite` or `rare` |
| `aggroHeld`, `aggroSamples` | Aggro share used for role guesses |
| `spellLines` | Count of `[SPELL]` lines, capped at 200 |
| `fullTimeline[]` | Max 500 lines |
| `exportText` | The Full Log, built at end |
| `story` | The imported story |

**Timeline tags** (`[HH:MM:SS] ...`):

- Lifecycle: `[PAUSED]`, `[RESUMED]`, `[RELOAD]`.
- Combat: `[COMBAT START]`, `[COMBAT END]`.
- Bosses:
  - `[BOSS ENGAGED]`.
  - `[BOSS HP]` at 50, 20 and 5%.
  - `[BOSS RESET]`: the whole group left combat while the boss lived.
  - `[BOSS KILL]`: from `ENCOUNTER_END` success or a dead boss unit, deduplicated for 30 s.
  - `[BOSS CAST]`: from boss1-5, target, focus or a nameplate, with a 12 s cooldown per boss and spell. A START is logged as "begins casting". An instant SUCCEEDED is logged as "casts", unless its START was logged.
- `[AGGRO]`: an enemy's target moved between party members (4 s cooldown per mob, 1.5 s global).
- Party health:
  - `[DANGER]`: a party member is under 10% HP in combat.
  - `[SAVED]`: they are back at 40% or more and alive. This can also happen after combat.
  - `[LOW MANA]`: 8% or less.
- `[SPELL]`: party casts in combat, at most one per person and spell every 30 s, a global gap of 1 s, and 200 per run. Auto Shot, Shoot and Attack are skipped.
- `[CC]`:
  - From `UNIT_AURA` on player and party1-4: a new harmful aura whose name matches a CC word list (polymorph, fear, stun, sap, sleep and so on).
  - From `UnitIsCharmed`: "is mind controlled!" and "breaks free".
- Pets:
  - `[PET]` when a pet is under 25% HP in combat (30 s cooldown) or comes back to life.
  - `[PET DEATH]` when it dies.
  - Tracked units: `pet` and `partypet1-4`, via `UNIT_HEALTH` and `UNIT_PET`.
- Other events: `[DEATH]`, `[WIPE #N]` (3 deaths in 45 s, or everyone dead), `[REZ]`, `[LOOT]` (green and better, with the looter), `[NPC Emote]`, `[HIGHLIGHT]` (Mark Moment) and `[SCREENSHOT]`.
- Chat lines are tagged with the fight, for example `[Party | vs Arugal 5% HP] Mira: OOM!`.

**Gating:**
- The combat poller (`Events.lua`, 0.4 s OnUpdate) runs only while a run records.
- The run trackers (spell, boss cast, CC, pet) also require being inside an instance.
- Every tracker runs in `pcall` and reports its first error once in chat.

**Full Log** (`ns.BuildAdventureFullLog`), in order:
1. `use story`, then `[ADVENTURE: title]` and a stats line.
2. The roster.
3. `Known companions:`: only party members saved in the Companion book with a note, never you (`ns.GetKnownCompanionNotes`).
4. Bosses, loot and starred highlights.
5. The last 450 timeline lines.

**Summary** (`ns.BuildAdventureSummary`) is the in-game overview. Its boss kill list has icons.

## 8. Stories

**Pipeline:**
1. Copy the Full Log.
2. The AI, using the `wow-adventure-story` skill, writes a story with WoW color codes.
3. Paste it into the Import modal.
4. `ns.SetAdventureStory` stores it, cleaned by `NormalizeStoryText`.
5. The Story reader renders `ns.DecorateStoryBosses(NormalizeStoryText(story), run)`.

`DecorateStoryBosses`:
- It walks the text, skipping `|c..`, `|r`, `|T..|t`, `|A..|a` and `|H..|h` codes.
- It puts a boss icon before every recorded boss name: skull for a world boss or level ??, gold dragon for an elite, silver dragon for a rare. It uses atlas `nameplates-icon-elite-gold` / `-silver` when `C_Texture.GetAtlasInfo` knows them, else texture paths.
- Longest names are matched first, through placeholders.
- It also turns the old boss orange `|cffff8000` crimson.
- Runs from before 0.3.1 have no `bossInfo`, so their bosses get a skull.

**Templates** (`UI_Options.lua`, shown with `UI.OpenSkillTemplateModal`):
- The RP character skill template.
- The story skill template. It has rules for staying faithful to the log, keeping timestamps and percentages hidden, the Known companions block, the fight tags, no icon codes, a color palette with gray Priests and crimson bosses, and WoW-safe formatting.
- When you add a Full Log tag, update the story template too.

## 9. UI (UI_*.lua)

- **Window `RPCopyFrame`:**
  - Default 680x490, minimum 600x450.
  - In `UISpecialFrames`, so Esc closes it.
  - Header: title, close button, gear (Options) and version badge.
  - Left rail (80 px): Copy, Companions and Adventures, plus a REC / PAUSED chip.
  - Content area and a status line (`UI.SetStatus(msg, kind)`, shown for 8 s).
- **Sections:** `UI.NewSection(key, title, hint, onShow)` and `UI.ShowSection(key)`. The keys are COPY, PLAYERS, ADVENTURES and OPTIONS (`ns.state.section`).
- **Resize:** `UI.PinTopLeft` runs before `StartSizing`, which fixes the old jump. Size and place are saved. Right-clicking the grip calls `UI.ResetWindow`. `UI.AddReflow` callbacks re-layout views.
- **Widgets:**
  - `UI.CreateSleekButton(parent, w, h, text, style)` with styles gold, danger and rail, plus `SetIcon` and `tipTitle` / `tipText`.
  - Theme helpers: `UI.ApplyDarkGlass`, `UI.ApplyPanelLook` and `UI.ApplyStoryTomeLook`. `UI.ICONS` holds the icon paths.
- **Options pages:** General, Keybinds, Slice Tabs, Adventures and AI Setup (`UI.OpenOptionsPage(key)`).
- **Floating `[RP]` button:** draggable. Left-click toggles the window and right-click clears logs. It shows a pulsing red dot while recording and amber while paused. Mor wants it kept, and no minimap button.

## 10. Keybindings and commands

**Key Bindings** (`Bindings.xml`, labels in Core):

| Binding | Action |
|---|---|
| `RPCOPY_OPEN` | Toggle the window |
| `RPCOPY_QUICK` | Quick copy |
| `RPCOPY_CAPTURE` | Capture the target as a companion |
| `RPCOPY_MARK` | Mark Moment |
| `RPCOPY_RUN_START` | Start recording |
| `RPCOPY_RUN_PAUSE` | Pause or resume recording |
| `RPCOPY_RUN_END` | End and save recording |

RPCopy's own keys (Options > Keybinds) are override bindings that click hidden buttons: `RPCopySilentCopyBtn`, `RPCopySilentCaptureBtn`, `RPCopySilentMarkBtn`, `RPCopySilentOpenBtn`, `RPCopySilentRunStartBtn`, `RPCopySilentRunPauseBtn` and `RPCopySilentRunEndBtn`. `UI.UpdateOverrideBindings` sets them only out of combat. It sets `bindingsPending` and re-applies on `PLAYER_REGEN_ENABLED`, and it also runs at `PLAYER_LOGIN`.

**Slash commands** (`/rp`, `/rpcopy`):

| Command | Action |
|---|---|
| (none) or `<instruction>` | Open the window, optionally with an AI instruction |
| `quick` | Quick copy |
| `capture` | Capture the target as a companion |
| `mark [note]` | Mark Moment |
| `start`, `pause`, `resume`, `end` / `stop` | Record a run |
| `options` / `config`, `companions`, `adventures` / `runs` | Open that view |
| `btn` | Show or hide the `[RP]` button |
| `clear` | Clear the session logs |
| `diag` | What RPCopy can read about your target |

Globals: `RPCopy_Open(note, section)`, `RPCopy_Toggle`, `RPCopy_QuickCopy`, `RPCopy_CaptureTarget`, `RPCopy_StartRun`, `RPCopy_ToggleRunPause`, `RPCopy_EndRun`, `RPCopy_MarkMoment`.

## 11. Events and the Forever rules

- **Never register `COMBAT_LOG_EVENT_UNFILTERED`.** It is protected on this client, and registering it raises the "blocked from an action" popup. Everything comes from unit events and polling instead.
- **Main frame events:**
  - Login and world: `PLAYER_LOGIN`, `PLAYER_ENTERING_WORLD`, `ZONE_CHANGED_NEW_AREA`, `GROUP_ROSTER_UPDATE`, `PLAYER_TARGET_CHANGED`, `UPDATE_MOUSEOVER_UNIT`.
  - Combat: `PLAYER_REGEN_DISABLED`/`ENABLED`, `ENCOUNTER_START`/`END`, `UNIT_HEALTH`, `UNIT_POWER_UPDATE`, `UNIT_THREAT_*`.
  - Player: `PLAYER_LOGOUT`, `PLAYER_DEAD`, `PLAYER_LEVEL_UP`.
  - Chat: all `CHAT_MSG_*` chat, NPC, loot and money events.
  - Quests: `QUEST_DETAIL`/`PROGRESS`/`COMPLETE`/`ACCEPTED`/`TURNED_IN`.
- **Tracker frame events:** `UNIT_SPELLCAST_SUCCEEDED`/`START`/`CHANNEL_START`, `UNIT_AURA`, `UNIT_PET`, `UNIT_HEALTH`.
- **Rules:**
  - Call `IsInInstance()` directly, never `IsInInstance and IsInInstance()`, because that keeps only the first return value.
  - Screenshots fade `UIParent` with `SetAlpha` instead of hiding it.
  - Make no protected calls in combat.

## 12. Export_Stories.bat

The file is a batch header followed by a PowerShell body.
- It reads `WTF\Account\*\SavedVariables\RPCopy.lua` with a small Lua table parser.
- For each run, it writes `<date> - <title>.html` (colored, with the same boss icons as HTML emoji spans), `.txt` and `- Full Log.txt`, plus an `index.html`, to `World of Warcraft\_forever_\RPCopy Stories\<account>\`.
- It needs only Windows PowerShell. It can't be run in Claude's Linux sandbox, so changes need a test on Mor's PC.

## 13. Build, test, release

- **Locals check:** run `python tools/check_locals.py <file>.lua` on every changed file. Every main chunk is 50 or under (Events.lua is the highest at 50, on 0.3.1).
- **Smoke test** (cloud sessions): a lupa (Lua 5.1) mock of the WoW API. It loads the toc files in order, fires login, clicks every button and fires chat, loot and run events.
- **Release:**
  1. Bump the version in 4 places.
  2. Update README.
  3. Commit as azaxyno with no AI attribution, after Mor approves.
  4. Push main.
  5. Tag `vX.Y.Z` and publish a GitHub pre-release with notes (intro, What's new, Fixes, Install) and `RPCopy-vX.Y.Z.zip`. The zip holds `RPCopy/` with the toc, .lua files, Bindings.xml, README.md, LICENSE, CREDITS.md and Export_Stories.bat.
- **CurseForge:** the same zip, type Alpha, game version Forever 1.60.1. Set the project ID in the toc once the project exists. Upload steps: `RPCopy-docs/CurseForge-upload.md` in the project files.

## 14. Known limits

- **Secret values.** Values the client marks secret, such as health, names or auras, are skipped silently. `/rp diag` shows what is readable.
- **Boss detection** is heuristic for classic bosses without a skull: a big elite in an instance, or a boss you've fought before. Wipes are guessed from deaths.
- **Throttled tags.** `[SPELL]` is throttled and capped, so not every cast appears. CC detection is by aura name (English client) and mind control.
- **Boss icons:**
  - Old runs show a skull for every boss.
  - A possessive or longer mob name that starts with the boss name ("Arugal's Voidwalker") also gets an icon.
- **Buffers:** the session logs hold 25 entries each and the timeline holds 500 lines. The Full Log includes the last 450.
- **Tags and releases.** Cloud sessions can't push tags or create releases.
