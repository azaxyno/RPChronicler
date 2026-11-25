# RPCopy Architecture & Module Reference (0.5.0)

This replaces the old "RPCopy v3.6 Architecture & Module Reference" PDF, which describes a single `UI.lua` and the retired 3.x versions.

## 1. What the addon does

RPCopy is a WoW: Forever addon (`## Interface: 16001`, alpha, MIT). It has three jobs:

1. **Copy the scene.** `Ctrl+C` puts a text snapshot of the current situation in the clipboard. The player pastes it into an AI that holds their character skill. Line 1 is the Skill Call (`[Skill Call] use aloria`) that triggers the skill.
2. **Remember companions.** It saves players, NPCs and pets with your notes (relationship, tone, "Who they are", "Our history") and their last 5 chat lines. A `[Known Player]` (or `[Known NPC]` / `[Known Pet]`) block is added when they are in the scene.
3. **Chronicle runs.** It records dungeons, raids and open-world adventures as a timestamped Full Log, which an AI storyteller skill (Dungeon/Raid Story or Adventure Story) turns into a colored story. The story is imported into the Story Book (its own section since 0.5.0) and read in game. Stories are stored apart from runs, so deleting a recording keeps its story.

It never sends chat and has no network access. All data lives in the account-wide SavedVariable `RPCopyDB`. A first-run setup (`UI_Setup.lua`) shows the privacy note and the recording choices.

## 2. Files and load order

Every file starts with `local ADDON_NAME, ns = ...` and shares `ns`. The UI files also share `local UI = ns.UI`, created by `UI_Shell.lua`. The order in `RPCopy.toc` matters:

| # | File | Role |
|---|---|---|
| 1 | `Core.lua` | Version, binding names, `RPCopyDB` defaults, `ns.TAB_FLAGS` / `ns.DEFAULT_TABS`, `ns.LOG_CATEGORIES` / `ns.LOG_LIMITS` / `ns.AI_MODELS` with `ns.LogOn(cat)` and `ns.Limit(key)`, `ns.SUMMARY_STATS` / `ns.SummaryOn`, `ns.CAPTURE_TYPES` / `ns.CaptureOn`, `ns.PRIVACY_TEXT`, `ns.WipeAllData`, `ns.COLORS` / `ns.CLASS_COLORS`, safe-value helpers, name and realm helpers, role guessing, log buffers, `NormalizeStoryText`, `EnsureDB` and migrations |
| 2 | `Debug.lua` | `ns.Debug(kind, msg)` ring buffer (200 lines in `RPCopyDB.debugLog`, pending until `ns.DebugReady()` at login, off when `debugEnabled == false` except errors and blocked actions), RPCopy-only `seterrorhandler` chain, `ADDON_ACTION_BLOCKED/FORBIDDEN`, `ns.BuildDebugReport()` (with Names and Quick copy lines) |
| 3 | `Companions.lua` | Companion records (`SaveOrUpdatePlayer(name, unit)`, `RenameCompanion`, `FindPlayerKey`), include modes, pet helpers (`GetPetKind`, `GetPetSpecies`, `GetPetDescriptor`), `UnitCompanionName`, `GetKnownPlayerBlocks(people, body)`, `CompanionSharedAdventures`, the "Add as RPCopy companion" right-click entry (`Menu.ModifyMenu`) |
| 4 | `Snapshot.lua` | Target, Party (raid1-40 too) and Status lines; `ns.BuildSnapshot` |
| 5 | `Adventures.lua` | Run state and lifecycle (restore, interrupted runs, resume, `DropActiveAdventure`), all `Record*` functions, timeline handles (`UpdateAdventureLine`), places and companions met, Summary by run type, Full Log builder, size and AI limit, story storage (`RPCopyDB.stories`), Story Book metadata (`ParseStoryMeta`, `GetBookInfo`, `GetBookStats`, `SetBookField`, `DeleteStory`, `GetStoryPlainText`), boss icons, `AutoColorStory` |
| 6 | `Screenshots.lua` | `ns.RequestScreenshot(kind, caption)`, and your own Print Screen shots on `SCREENSHOT_SUCCEEDED` |
| 7 | `Events.lua` | `RPCopyEventFrame` router, chat capture switches, chat and loot handling (loot source, quest items, coin), combat poller (also feeds the fight tracker), run trackers, `/rp diag` |
| 8 | `Chronicle.lua` | Fight tracker (`FightBegin`, `FightSeeUnit`, `FightNote*`, `FightNoteSpell`, `FightFlush` with trash streaks), kills and foe counts, PvP, quests, objectives and quest text, NPC filter (`ns.ChronicleNpc`), levels, places, skills, milestones, loot source (`ns.ClassifyLootSource`, `ns.IsQuestItem`), atmosphere, start-recording and interrupted-run prompts |
| 9 | `UI_Shell.lua` | `ns.UI`, `UI.EnsureOptions`, theme and widgets, main window `RPCopyFrame`, rail, sections, status line, resize (throttled reflow, sizing stop on mouse up or hide, on-screen clamp), toast, `UI.ShowPrompt`, `UI.ShowCopyBox`, `RPCopy_Open` / `RPCopy_Toggle` |
| 10 | `UI_Copy.lua` | Quick-copy engine, `RPCopy_QuickCopy`, `RPCopy_CaptureTarget`, COPY section, Nearby companions chip (`UI.RefreshNearbyChip`) |
| 11 | `UI_Companions.lua` | PLAYERS section: search, sort, editor (names, relationship, tone, two notes), include, capture, delete |
| 12 | `UI_Adventures.lua` | `RPCopy_StartRun` / `RPCopy_ToggleRun` / `RPCopy_ToggleRunPause` / `RPCopy_EndRun`, story import modal (`UI.OpenStoryImportModal(adv, st)`), ADVENTURES section (`UI.OpenRecording(advId, mode)`), size meter |
| 13 | `UI_StoryBook.lua` | The BOOK section with its own rail button: library, reader, export tip, Share, Details modal, Re-Import, Delete, jump to the recording (`UI.OpenStoryBook(storyId)`, `UI.RefreshStoryBook`) |
| 14 | `UI_Options.lua` | RP and two story templates, template modal, key capture modal, OPTIONS pages |
| 15 | `UI_Setup.lua` | First-run setup (`UI.OpenSetup(force)`): privacy note, recording and capture choices, copy mode, `SETUP_VERSION` |
| 16 | `UI_Commands.lua` | Hidden keybind buttons, `UI.UpdateOverrideBindings`, floating `[RP]` button with its right-click menu (`UI.ToggleIconMenu`) and recording state (`UI.RefreshRecordIcon`), `/rp` slash commands |
| | `Bindings.xml` | Key Bindings entries |
| | `Export_Stories.bat` | Batch + PowerShell exporter (section 12) |
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
| `players[name]` | `{ cid, kind (player/npc/pet), note ("Who they are"), history ("Our history"), relationship, tone, include (auto/always/never), level, race, class, classFile, guild, chatHistory (last 5), firstMet, firstMetPlace, lastSeen }` |
| `adventures` | Up to 40 finished runs, newest first |
| `stories[]` | Imported stories (0.5.0): `{ id, advId, text, book, ... }` plus a copy of the run's details at the top level (`CopyRunMeta`), so a story has the same shape as a run and outlives it |
| `activeRun` | The run being recorded, saved live so it survives `/reload` and disconnects |
| `knownBosses[name]` | Bosses fought before, so classic bosses without a skull are recognized |
| `autoUpdateKnown`, `autoScreenshots` | Toggles |
| `quickCtrlC`, `quickCopyKey` (`CTRL-C`), `copyMode` (`INSTANT` / `TWOPRESS`), `instantInCombat` | Quick copy |
| `quickCapture`, `captureTargetKey` (`SHIFT-C`), `markMomentKey`, `openWindowKey`, `runStartKey`, `runPauseKey`, `runEndKey` | RPCopy's own keybinds (`""` means unbound) |
| `lastSliceId`, `defaultMessages` (3), `expandMessages` (6) | Copy view |
| `frameW`, `frameH`, `frameX`, `frameY`, `optionsPage` | Window size and place, last Options page |
| `autoRecord`, `promptOnGroup`, `promptOnLogin`, `resumeAfterReload`, `iconState`, `sizeMeter` | Recording options (0.4.0) |
| `logCats[cat]`, `limits[key]`, `aiModel`, `aiCustomLimit` | Full Log categories (false = off), limits (clamped in EnsureDB), size meter AI |
| `summaryStats[key]`, `capture[key]` | Summary stats shown (0.5.0), chat kinds kept (0.5.0, false = off) |
| `setupVersion`, `wipedAt` | Last setup version seen (`UI_Setup.lua`), time of the last `/rp wipe` |
| `recordManualShots`, `knownPlayerBlocks`, `knownPlayerMax`, `knownNoteMax`, `companionMenu`, `nearbyChip`, `runCompanions` | Screenshot and companion options (0.5.0) |
| `autoColorStory`, `exportTip`, `exportImageDir`, `exportShotsDir`, `rpReplyLength` | Story, export and template options (0.5.0) |
| `debugLog`, `debugEnabled`, `debugVerbose` | Debug log and its switches |
| `migratedV32`, `migratedV031`, `migratedV040` | One-time migration flags |

Defaults and migrations:

- **`ns.EnsureDB`** (Core) runs everywhere. It fills defaults, converts old string-only player entries and old `info` strings, rebuilds missing `exportText`, and migrates tabs:
  - It adds `incOoc`, `incPartySay` and `incWorld` when missing.
  - It drops `incCombat`.
  - Once, behind `migratedV031`, it resets the built-in tabs' flags to the 0.3.1 defaults. Labels and prefixes are kept, and custom tabs aren't touched.
  - Once, behind `migratedV040`, it removes SMART, inserts missing WORLD and GUILD at their default places, and moves `lastSliceId` SMART to CHAT. `incGuild` is filled with false where missing.
  - It fills `logCats`, clamps `limits` and sets the 0.4.0 recording defaults.
  - 0.5.0: it fills `capture` and `summaryStats`, turns old string screenshots into `{ n, description }` tables, and `ns.MigrateStories` moves each old `run.story` into `RPCopyDB.stories`.
- **`UI.EnsureOptions`** (UI_Shell) fills the key and copy-mode defaults.

Session buffers (`ns.logs`) are in memory only and are cleared by `/reload`, `/rp clear` or right-clicking `[RP]`.

## 5. Copy snapshots and slice tabs

**Log buffers** (`ns.logs`, 25 entries each, via `ns.PushLog(tbl, line, author, chan)`). Each entry is `{ line, seq, author, chan }`, where `seq` is a global counter. Use `ns.LogLine(entry)` to read one, which also handles legacy strings.

| Buffer | Filled by |
|---|---|
| `social` | Say, yell, emote, whispers (in and out) |
| `party` | Party, raid, instance chat |
| `world` | Numbered channels (Trade, General, LFG) |
| `guild` | Guild and officer chat (0.4.0) |
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
| `incWorld` | world buffer |
| `incGuild` | guild buffer |

Built-in tabs (0.4.0): **CHAT** (direct, target, social), **WORLD** (world), **PARTY** (target, party, status, party say, party chat), **GUILD** (guild), **QUEST** (target, status, quest, NPC) and **LOOT** (party, status, loot). SMART was removed in 0.4.0. Each tab also has `id`, `label` and `prefix` (the Skill Call; empty means raw data only). Players edit all of this in Options > Slice Tabs.

**`ns.BuildSnapshot(tabId, note, expanded)`** builds the snapshot in this order:
1. `[Skill Call]`, `[Instruction]` and `[Location]`.
2. Direct, Target, Party, Status and Quest.
3. **One timeline:** the last `limit` entries of each included buffer (3, or 6 when expanded), deduplicated and sorted by `seq`. If the direct entry is in the timeline, it is tagged `[Direct]` there and the separate line is skipped.
4. `ns.GetKnownPlayerBlocks(people, body)`: `people` is the direct author, the target, party or raid members, timeline authors and whisper recipients. Companions set to Always are added too, Never are skipped, up to `knownPlayerMax`. A block has Relationship, Who they are, Our history (each cut at `knownNoteMax`) and a "Latest Chat" that skips lines already in the body.

## 6. Quick copy (UI_Copy.lua)

Addons can't write to the clipboard. The only route is a focused EditBox with the text highlighted, copied by the game's own Ctrl+C.

- The hidden box is `RPCopySilentArmBox`. `UI.ArmCtrlCopy` focuses it with the snapshot of `lastSliceId` selected, and `UI.DisarmCtrlCopy` releases it.
- **INSTANT mode:**
  - `RPCopyCtrlWatcher` arms after Ctrl has been held 0.25 s (`ARM_DELAY`).
  - `RPCopyKeyListener` uses `SetPropagateKeyboardInput(true)`, set once out of combat and enabled only if propagation is verified. It marks the hold as used when another key is pressed with Ctrl, so other Ctrl+key binds pass through.
  - It is off in combat unless `instantInCombat` is set.
- **0.5.0 fixes:** the box gets `ChatFontNormal` and no letter or byte limit; arming checks it really has focus and text, and logs the focused frame when not; the selection is re-applied while armed and just before the copy; a binding press while armed but unfocused re-arms instead of reporting a false copy. `/rp debug` shows the last copy attempt.
- **TWOPRESS mode, and any custom key:** the override binding `CTRL-C` -> `RPCopySilentCopyBtn` arms on the first press, and the second press copies. The binding is always set when the copy key is `CTRL-C`, so a fast Ctrl+C also works in INSTANT mode.

## 7. Adventures (Adventures.lua + Events.lua)

**Lifecycle:**
- `StartAdventure(title, isAuto)` starts a run. It ends any run already active, resets boss state and the run trackers, and saves `RPCopyDB.activeRun`.
- Auto runs start on `PLAYER_ENTERING_WORLD` in a party or raid instance when `autoRecord` is on. They end on leaving, unless paused. Entering a different dungeon starts a new run. Every run has `kind` = `dungeon`, `raid` or `world` (`ns.GetRunKindLabel`).
- `PauseAdventure` and `ResumeAdventure` work while paused: `PushTimeline` drops everything except forced lines.
- `RestoreSavedAdventure` runs at the first `PLAYER_ENTERING_WORLD`. Back within 120 s (and `resumeAfterReload` on): the run continues ("resumed" or "paused"). Otherwise the run is closed and saved with `interrupted = true`, `endTime` from `interruptedAt` (set at `PLAYER_LOGOUT` by `TouchActiveAdventure(true)`), and `ns.OfferInterruptedRun` asks to resume (`ns.ResumeInterruptedRun(id)`) or keep it.
- `ns.GetRunDuration(adv)` is the duration for live and ended runs (0.3.x showed 0m 00s for live ones).
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
| `kind`, `interrupted`, `interruptedAt`, `endTime` | Run type and interrupted state |
| `kills[]`, `foesDefeated`, `coin`, `skills[name] = {from, to}` | Notable kills, all kills, looted copper, skill-ups |
| `spellLines`, `npcLines` | Counts, capped by `ns.Limit("spellCap")` and `ns.Limit("npcCap")` |
| `keyLoot[]` | `{ colored, plain, looter, source }` |
| `participants[].guild`, `.guildmate` | Guild, and whether it is the player's guild |
| `fullTimeline[]`, `tlRemoved` | Max `ns.Limit("timelineMax")` lines (500); a line handle is `tlRemoved + index`, so a line can be updated in place (`ns.UpdateAdventureLine`) |
| `killCounts[name]`, `pvpKills`, `pvpDeaths`, `levelStart`, `levelEnd`, `questsDone`, `places[]`, `milestones[]`, `metCompanions[]` | 0.5.0 stats for the Summary, header and Story Book |
| `shots[]` | `{ n, at, kind, description, zone }`, capped by `shotCap` |
| `exportText` | The Full Log, built at end |
| `story`, `book` | Before 0.5.0 only: moved into `RPCopyDB.stories` by `ns.MigrateStories` |

**Timeline tags** (`[HH:MM:SS] ...`):

- Lifecycle: `[PAUSED]`, `[RESUMED]`, `[RELOAD]`.
- Fights (Chronicle): `[FIGHTS]` folds plain trash fights (no notable kill, death or boss) into one streak line, updated in place while the next one starts within 300 s. `[FIGHT]` one line per notable fight, with the spells used (`ns.FightNoteSpell`) and the outcome (defeated, it escaped, the party disengaged, you disengaged), written by `ns.FightFlush` when the poller sees the whole group out of combat (or on pause / end / logout). Skipped under `minFightSec` with no kill or death. `[COMBAT START]` / `[COMBAT END]` are gone and are filtered out of old runs' Full Logs.
- `[KILL]`: an enemy seen in the fight that reads as dead. Rares and rare elites always, elites only outside instances. Bosses are left to `[BOSS KILL]`.
- `[QUEST]`, `[QUEST TEXT]` (240 chars, `$N` / `$C` / `$R` filled), `[NPC]` (`ns.ChronicleNpc`: yells, boss emotes and named NPCs 8 s apart, other mob chatter one line per name per 3 minutes, de-duplicated for 10 minutes, `npcCap` per run; flee emotes go into the fight), `[LEVEL]`, `[PLACE]` (subzones, each at most every 5 minutes), `[SKILL]` (one line per skill per 10 minutes), `[MILESTONE]`, `[ATMOSPHERE]` (`GetGameTime`, `IsIndoors`; at start and on a new zone if the phase changed or 20 minutes passed).
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
- `[PVP]`: hostile players who die in the fight, and PvP deaths.
- `[QUEST] Objective done:` from `QUEST_LOG_UPDATE` / `UNIT_QUEST_LOG_CHANGED` (`ScanObjectives`, seeded at start so old objectives aren't logged).
- `[SHOT N]`: a screenshot with its caption (`ns.RecordAdventureScreenshot`).
- `[SPELL]`: since 0.5.0 only crowd control and big cooldowns; other party and pet casts in a fight go into its `[FIGHT]` line. In instances at most one per caster and spell every 30 s with a global gap of 1 s; in the open world 60 s and 3 s. `spellCap` per run. Auto Shot, Shoot and Attack are skipped.
- `[CC]`:
  - From `UNIT_AURA` on player and party1-4: a new harmful aura whose name matches a CC word list (polymorph, fear, stun, sap, sleep and so on).
  - From `UnitIsCharmed`: "is mind controlled!" and "breaks free".
- Pets:
  - `[PET]` when a pet is under 25% HP in combat (30 s cooldown) or comes back to life.
  - `[PET DEATH]` when it dies.
  - Tracked units: `pet` and `partypet1-4`, via `UNIT_HEALTH` and `UNIT_PET`.
- Other events: `[DEATH]` (yours from `PLAYER_DEAD`, party members' from `UNIT_HEALTH`, with the foe and last HP), `[WIPE #N]` (3 deaths in 45 s, or everyone dead), `[REZ]`, `[LOOT]` (green and better, and quest items, with the looter and source), `[NPC Emote]`, `[HIGHLIGHT]` (Mark Moment). Repeat loot of the same item by the same looter within 15 minutes updates one line with `xN`.
- Every kind checks `ns.LogOn(cat)`. OOC text (`(( ))`, `[OOC`, the word ooc) is never recorded (`ns.IsOocText`), and guild and world channels never go into a run.
- Chat lines are tagged with the fight, for example `[Party | vs Arugal 5% HP] Mira: OOM!`.

**Gating:**
- The combat poller (`Events.lua`, 0.4 s OnUpdate) runs only while a run records.
- The run trackers (spell, boss cast, CC, pet) run in every run type, with stricter spell throttles outside instances.
- Every tracker runs in `pcall` and reports its first error once in chat.

**Full Log** (`ns.BuildAdventureFullLog`), in order:
1. The trigger (`use story`, or `use adventure story` for world runs), then `[ADVENTURE: title]` and `Run type: ... | Zone | Date | Duration | Wipes | Deaths`, plus a note for interrupted runs.
2. The roster, with `<Guild> (guildmate)` and a "Guildmates in the party" line.
3. `Known companions:`: party members and companions met in the run (`metCompanions`) with notes, never you and never Include = Never (`ns.GetKnownCompanionNotes`). Pets are on the roster line.
4. World runs: Levels, Quests completed, Places (no Wipes). Bosses, "Foes defeated: N" by type, "Notable kills", Notable Loot `item -> Looter (source)`, Coin looted, Skill-ups, starred highlights.
5. A Screenshots list (`[Shot N] caption`) that the templates ask the AI to place.
6. The last `timelineMax` timeline lines.

`ns.GetFullLogSize(adv)` and `ns.GetAiLimit()` feed the size meter in Recordings.

**Summary** (`ns.BuildAdventureSummary`) is the in-game overview, by run type: zeros are hidden, each stat is gated by its `kinds` in `ns.SUMMARY_STATS` and by `ns.SummaryOn`. `ns.GetRunHeroStats` feeds the top bar.

## 8. Stories

**Pipeline:**
1. Copy the Full Log.
2. The AI, using the Dungeon/Raid Story (`wow-dungeon-raid-story`) or Adventure Story (`wow-open-world-story`) skill, writes a story with WoW color codes, a header (title; `instance | duration | zone`; `Date: | Party:`), `Chapter N:` lines and a footer (`Bosses: | Wipes: | Deaths:`).
3. Paste it into the Import modal and pick the run.
4. `ns.SetAdventureStory(advId, text)` stores it in `RPCopyDB.stories` (one per run, `ns.StoryForRun`), cleaned by `NormalizeStoryText` and, when `autoColorStory` is on, `ns.AutoColorStory`. It copies the run's details into the story and fills `st.book` from `ns.ParseStoryMeta` (which also reads foes, quests and levels). Fields edited by hand (`book.edited`) survive a re-import. When the run is gone, Re-Import uses `ns.SetStoryText(storyId, text)`.
5. The Story Book renders `ns.DecorateStoryBosses(NormalizeStoryText(text), st)` with `[Shot N]` markers stripped. `ns.GetBookInfo(st)` gives the details with run fallbacks and the entry name "title - instance"; `ns.GetBookStats(info)` the stats by kind. Share uses `ns.GetStoryPlainText`.

`AutoColorStory` colors plain prose only (it walks the escape codes): party in class colors, pets `80cbc4`, places `40e0d0`, foes `dc143c`, NPCs `fff0a0`, items in their link color. A first name alone is colored only when it is unique.

`DecorateStoryBosses`:
- It walks the text, skipping `|c..`, `|r`, `|T..|t`, `|A..|a` and `|H..|h` codes.
- It puts a boss icon before every recorded boss name: skull for a world boss or level ??, gold dragon for an elite, silver dragon for a rare. It uses atlas `nameplates-icon-elite-gold` / `-silver` when `C_Texture.GetAtlasInfo` knows them, else texture paths.
- Longest names are matched first, through placeholders.
- It also turns the old boss orange `|cffff8000` crimson.
- Runs from before 0.3.1 have no `bossInfo`, so their bosses get a skull.

**Templates** (`UI_Options.lua`, shown with `UI.OpenSkillTemplateModal`):
- The RP character skill template (0.5.0: a short chat-sized persona with 5 moods, per-channel rules and a personalize note; `<REPLY_LENGTH>` comes from `rpReplyLength` via `UI.GetRpSkillTemplate()`).
- Two story templates, built from `STORY_SHARED_RULES` plus a structure part each: Dungeon/Raid (one chapter per boss, mode `STORY`) and Adventure (open world, by place and event, mode `ADVENTURE`). The shared part has the tag list, guildmates, the Story Book header and footer, the color palette with gray Priests and crimson bosses, and WoW-safe formatting.
- When you add a Full Log tag, update the story template too.

## 9. UI (UI_*.lua)

- **Window `RPCopyFrame`:**
  - Default 680x490, minimum 600x450.
  - In `UISpecialFrames`, so Esc closes it.
  - Header: title, close button, gear (Options) and version badge.
  - Left rail (80 px): Copy, Companions, Adventures and Story Book, plus a REC / PAUSED chip.
  - Content area and a status line (`UI.SetStatus(msg, kind)`, shown for 8 s).
- **Sections:** `UI.NewSection(key, title, hint, onShow)` and `UI.ShowSection(key)`. The keys are COPY, PLAYERS, ADVENTURES, BOOK and OPTIONS (`ns.state.section`). Since 0.5.0 the Story Book is its own BOOK section; `UI.ShowAdventuresSub` is kept as a wrapper that calls `UI.OpenRecording` or `UI.OpenStoryBook`.
- **Resize:** `UI.PinTopLeft` runs before `StartSizing`. 0.5.0: the frame is `SetDontSavePosition` and `SetUserPlaced(false)` after a move, reflow is throttled to once a frame, `UI.StopSizing` also runs on hide and when the grip sees the mouse button up, and the saved place is clamped on screen. Size and place are saved. Right-clicking the grip calls `UI.ResetWindow`. `UI.AddReflow` callbacks re-layout views.
- **Widgets:**
  - `UI.CreateSleekButton(parent, w, h, text, style)` with styles gold, good, tool, danger and rail, plus `SetIcon` and `tipTitle` / `tipText`. Change `btn.accentStyle` then call `btn.ApplyNormalLook()` to recolor.
  - `UI.ShowPrompt(text, label1, fn1, label2, fn2, label3, fn3)` and `UI.ShowCopyBox(title, sub, text)`.
  - Theme helpers: `UI.ApplyDarkGlass`, `UI.ApplyPanelLook` and `UI.ApplyStoryTomeLook`. `UI.ICONS` holds the icon paths.
- **Options pages:** General, Keybinds, Slice Tabs, Recording (key `ADVENTURES`), Full Log (`FULLLOG`), Summary, Companions, Stories & Export (`STORIES`), AI Setup (`AI`), Privacy and Debug (`UI.OpenOptionsPage(key)`).
- **Floating `[RP]` button:** draggable. Left-click toggles the window and right-click opens the recording menu. While recording the label is red with a pulsing red dot and border; while paused it is dimmed (alpha 0.55) and amber. `iconState = false` turns that off. Mor wants it kept, and no minimap button.

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
| `book` / `stories` | Open the Story Book |
| `debug`, `debug clear` | Debug report in a copy box, or empty the log |
| `setup` / `privacy` | Show the first-run setup again |
| `wipe` | Delete all RPCopy data after a confirmation (`ns.WipeAllData`) |
| `clear` | Clear the session logs |
| `diag` | What RPCopy can read about your target |

Globals: `RPCopy_Open(note, section)`, `RPCopy_Toggle`, `RPCopy_QuickCopy`, `RPCopy_CaptureTarget`, `RPCopy_StartRun`, `RPCopy_ToggleRun`, `RPCopy_ToggleRunPause`, `RPCopy_EndRun`, `RPCopy_MarkMoment`.

## 11. Events and the Forever rules

- **Never register `COMBAT_LOG_EVENT_UNFILTERED`.** It is protected on this client, and registering it raises the "blocked from an action" popup. Everything comes from unit events and polling instead.
- **Main frame events:**
  - Login and world: `PLAYER_LOGIN`, `PLAYER_ENTERING_WORLD`, `ZONE_CHANGED_NEW_AREA`, `GROUP_ROSTER_UPDATE`, `PLAYER_TARGET_CHANGED`, `UPDATE_MOUSEOVER_UNIT`.
  - Combat: `PLAYER_REGEN_DISABLED`/`ENABLED`, `ENCOUNTER_START`/`END`, `UNIT_HEALTH`, `UNIT_POWER_UPDATE`, `UNIT_THREAT_*`.
  - Player: `PLAYER_LOGOUT`, `PLAYER_DEAD`, `PLAYER_LEVEL_UP`.
  - Chat: all `CHAT_MSG_*` chat, NPC, loot and money events.
  - Quests: `QUEST_DETAIL`/`PROGRESS`/`COMPLETE`/`ACCEPTED`/`TURNED_IN`.
- **Tracker frame events:** `UNIT_SPELLCAST_SUCCEEDED`/`START`/`CHANNEL_START`, `UNIT_AURA`, `UNIT_PET`, `UNIT_HEALTH`.
- **Chronicle frame events:** `PLAYER_ENTERING_WORLD`, `ZONE_CHANGED`/`_INDOORS`/`_NEW_AREA`, `PLAYER_LEVEL_UP`, `CHAT_MSG_SKILL`, `CHAT_MSG_SYSTEM`, `ACHIEVEMENT_EARNED`, `NEW_MOUNT_ADDED`, `NEW_PET_ADDED`, `UNIT_PET`, `UNIT_NAME_UPDATE`, `UNIT_SPELLCAST_SUCCEEDED` (player: gathering, Tame Beast, Dismiss Pet), `UNIT_HEALTH` (kills), `QUEST_DETAIL`/`COMPLETE`/`ACCEPTED`/`TURNED_IN`, `MERCHANT_*`, `MAIL_*`, `TRADE_*`, `LOOT_OPENED`/`CLOSED`, `GROUP_ROSTER_UPDATE`, `GROUP_JOINED`. Errors go to `ns.Debug("error", ...)`.
- **Debug frame events:** `ADDON_ACTION_BLOCKED`, `ADDON_ACTION_FORBIDDEN`.
- **Rules:**
  - Call `IsInInstance()` directly, never `IsInInstance and IsInInstance()`, because that keeps only the first return value.
  - Screenshots fade `UIParent` with `SetAlpha` instead of hiding it.
  - Make no protected calls in combat.

## 12. Export_Stories.bat

The file is a batch header followed by a PowerShell body.
- It reads `WTF\Account\*\SavedVariables\RPCopy.lua` with a small Lua table parser.
- For each story in `db.stories` (and legacy `run.story`, and runs with no story as Full Log only), it writes `<date> - <title>.html` (colored, with the same boss icons as HTML emoji spans), `.txt` and `- Full Log.txt`, plus an `index.html` with cover images, to `World of Warcraft\_forever_\RPCopy Stories\<account>\`.
- Screenshots (0.5.0): it reads `WoWScrnShot_MMDDYY_HHMMSS` files (folder: `RPCOPY_SHOTS`, then `exportShotsDir`, then `_forever_\Screenshots`) from 30 s before the run to 2 minutes after, matches recorded shots within 3 s for their number and caption, copies them with ~1280 px JPEG previews (System.Drawing) into `exportImageDir` or `images\`, and places them at `[Shot N]` markers, then by chapter title words, then by time, then in a gallery.
- It needs only Windows PowerShell. It can't be run in Claude's Linux sandbox, so changes need a test on Mor's PC.

## 13. Build, test, release

- **Locals check:** run `python tools/check_locals.py <file>.lua` on every changed file. Every main chunk is well under 200 (on 0.5.0 Chronicle.lua is the highest at 54, Events.lua 51, Adventures.lua 48).
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
- **Buffers:** the session logs hold 25 entries each and the timeline holds `timelineMax` lines (500 by default), all of them in the Full Log.
- **Kills and loot sources are best effort.** Without the combat log, a kill is an enemy seen in the fight that later reads as dead on target, focus, mouseover or a nameplate. Loot sources come from what window was open (loot, merchant, mail, trade, quest reward) and recent gathering or boss kills.
- **Weather** has no API on this client, so `[ATMOSPHERE]` holds only time of day and indoors / open sky.
- **Tags and releases.** Cloud sessions can't push tags or create releases.
