# RP Chronicler (formerly RPCopy)

A WoW: Forever addon (Interface 16001, alpha, MIT). It copies the current RP scene (`Ctrl+C`) as a text "snapshot" for the player's AI character skill. It keeps notes on companions, records dungeon, raid and open-world runs as a timestamped Full Log for an AI storyteller, and keeps the imported colored stories in an in-game Story Book. It never sends chat. Full module reference: `docs/ARCHITECTURE.md` (internal: untracked by git since 0.6.0, kept locally and in the project files; never publish it). Player docs: `README.md`.

## Working rules

- **Bump the version on every change.** Edit `## Version` in `RPChronicler.toc` (the chat banner and window badge read it), the fallback strings in `Core.lua` (`ns.VERSION`) and `UI_Shell.lua` (`verBadge`), and the Version line in `README.md`.
  - The addon is in alpha. Versioning restarted at 0.1.0 (the old 3.x tags were retired); stay below 1.0.0 until Mor says otherwise.
  - Small fix: patch bump, e.g. 0.1.0 -> 0.1.1.
  - Big update: minor bump, e.g. 0.1.x -> 0.2.0.
- Keep the toc load order: Core -> Debug -> Companions -> Snapshot -> Adventures -> Screenshots -> Events -> Chronicle -> UI_Shell -> UI_Copy -> UI_Companions -> UI_Adventures -> UI_StoryBook -> UI_Options -> UI_Setup -> UI_Commands. UI_Shell must load first among the UI files (it creates `ns.UI`). Since 0.5.0 UI_StoryBook builds its own BOOK section and rail button, and UI_Setup must load after UI_Options (it reads `ns.CAPTURE_TYPES` and opens from Options > Privacy).
- Every new recording or capture feature goes into the first-run setup (`CHOICES` in `UI_Setup.lua` with a `since` = the bumped `SETUP_VERSION`), `ns.PRIVACY_TEXT`, the README Privacy section and the CurseForge description.
- Every feature, Full Log category, prompt, indicator and default must have a switch or setting in Options (Mor's standing rule). New Full Log line kinds get a key in `ns.LOG_CATEGORIES` and check `ns.LogOn(key)`; new limits go in `ns.LOG_LIMITS` and are read with `ns.Limit(key)`. The Full Log stays rich but short (one meaningful line over many raw ones) and never keeps OOC.
- The Forever client runs on the modern engine. Guard APIs, never register `COMBAT_LOG_EVENT_UNFILTERED`, and make no protected calls in combat (`SetOverrideBindingClick` only out of combat). Read unit values through `ns.SafeStr` / `ns.SafeNum`, because values can be "secret". If a "blocked from an action" popup appears, read `..\..\..\Logs\taint.log`.
- No non-ASCII glyphs or Markdown in FontStrings or EditBoxes. Use `|cffRRGGBB...|r` codes, and normalize `||` to `|` on pasted text.
- Lua 5.1 caps a function at 200 *active* locals, and locals inside a top-level `do ... end` still count while that block runs. Going over stops the whole file loading ("main function has more than 200 local variables"). The old `UI.lua` hit about 187, so in 0.3.0 it was split into the `UI_*.lua` files, which share the `ns.UI` table. Every file's main chunk is well under the limit (on 0.5.0 `Chronicle.lua` is the highest at 54, `Events.lua` 51). Put new UI code in the file it belongs to, in a `do ... end` block or on `UI`, and run `python tools/check_locals.py <file>.lua` on every changed file before every commit (no Lua interpreter is installed on Mor's machine).
- In Git Bash heredocs on this machine, `\\` collapses to `\`. Write files containing backslashes with the Write/Edit tools, not heredocs.
- Keep `README.md` in step with user-visible changes, and `docs/ARCHITECTURE.md` in step with structural ones.
- Commit only after Mor approves. Mor pushes.
- azaxyno is the only author and contributor. Never add `Co-Authored-By: Claude`, `Claude-Session:` or any other AI attribution to commits, tags or releases.
- Every pushed version gets a tag `vX.Y.Z` and a GitHub Release (pre-release while in alpha). The release notes have a short intro, a "What's new" list of user-visible changes since the last release, "Fixes", and install steps. Attach `RPChronicler-vX.Y.Z.zip`, which holds an `RPChronicler/` folder with only the addon files (toc, .lua, Bindings.xml, README.md, LICENSE, CREDITS.md, Export_Stories.bat) Leave out docs, tools, .claude, backup, CLAUDE.md and PDFs.
  - Claude's cloud sessions can push branches but not tags or releases. Mor publishes the release from a `releases/new?tag=vX.Y.Z&target=main&prerelease=1` link, with the notes and zip that Claude prepares.
  - CurseForge: upload `RPChronicler-vX.Y.Z-curseforge.zip` (the same without Export_Stories.bat; the in-game tips point to the GitHub releases for it) as **Alpha** for game version Forever 1.60.1. `.pkgmeta` (package-as RPChronicler) is ready for the packager. Once the project exists, turn the commented `# ## X-Curse-Project-ID: 000000` line in the toc into a real `## X-Curse-Project-ID: <id>`.

## Map (details in docs/ARCHITECTURE.md, local only)

| File | Role |
|---|---|
| `Core.lua` | `RPChroniclerDB` defaults and `ns.EnsureDB` migrations, `ns.TAB_FLAGS` / `ns.DEFAULT_TABS`, `ns.LOG_CATEGORIES` / `ns.LOG_LIMITS` / `ns.AI_MODELS`, `ns.SUMMARY_STATS`, `ns.CAPTURE_TYPES`, `ns.PRIVACY_TEXT`, `ns.WipeAllData`, colors, safe-value helpers, roles, log buffers (`ns.PushLog`), `NormalizeStoryText` |
| `Companions.lua` | Companion records (players, NPCs, pets), rename, include mode, pet kind and species, `[Known Player]` blocks, the right-click "Add as RP Chronicler companion" entry |
| `Debug.lua` | `ns.Debug` ring buffer (no chat), RP Chronicler-only error hook, blocked actions, `ns.BuildDebugReport` for `/rp debug` |
| `Snapshot.lua` | `ns.BuildSnapshot(tabId, note, expanded)`: Skill Call, Instruction, Location, Direct, Target, Party, Status, Quest, then one time-ordered chat timeline, then companion blocks |
| `Adventures.lua` | Run lifecycle (interrupted runs, resume) and every `Record*` function, timeline, Summary by run type, Full Log and its size, story storage (`RPChroniclerDB.stories`, independent of runs) and Story Book metadata, boss icons (`DecorateStoryBosses`), `AutoColorStory` |
| `Screenshots.lua` | `ns.RequestScreenshot`: debounced, combat-safe, capped per run; your own Print Screen shots join the run |
| `Events.lua` | Event router to `ns.*`, chat buffers, loot filter and sources, combat poller (boss HP, pull end, aggro, fight enemies), run trackers (spell, boss cast, CC, pet) |
| `Chronicle.lua` | `[FIGHT]` / `[FIGHTS]` streak tracker, kills, PvP, quest objectives, quests, NPC filter, levels, places, skills, milestones, loot source, atmosphere, start-recording and interrupted-run prompts |
| `UI_Shell.lua` | `ns.UI`, option defaults, theme and widget helpers, prompt and copy boxes, main window: rail, gear, sections, status line, resize, saved position |
| `UI_Copy.lua` | Copy view and the quick-copy engine (Instant / Two-press Ctrl+C) |
| `UI_Companions.lua` | Companions view |
| `UI_Adventures.lua` | Adventures view (`UI.OpenRecording`): record bar (one Start/Stop toggle), run list, size meter, story import with a run selector |
| `UI_StoryBook.lua` | Story Book section (`UI.OpenStoryBook`): library, reader, export tip, Share, Details, Re-Import, Delete |
| `UI_Options.lua` | Options pages (General, Keybinds, Slice Tabs, Recording, Full Log, Summary, Companions, Stories & Export, AI Setup, Privacy, Debug), RP and two story templates, key capture |
| `UI_Setup.lua` | First-run privacy note and setup choices (`UI.OpenSetup`, `/rp setup`) |
| `UI_Commands.lua` | Keybind override buttons, floating `[RP]` button (right-click menu, recording state), `/rp` commands |
| `Bindings.xml` | The 7 Key Bindings entries |
| `Export_Stories.bat` | Windows PowerShell exporter: SavedVariables to HTML and text, with screenshots placed in the stories |

Key facts that are easy to get wrong:

- Log entries are tables `{ line, seq, author, chan }` (use `ns.LogLine`). The buffers are social, party, npc, loot, ooc, world (numbered channels), guild (guild and officer) and combat (deaths and level ups, read by Status).
- A slice tab is `{ id, label, prefix, inc* }`, with flags from `ns.TAB_FLAGS`. Built-in ids are CHAT, WORLD, PARTY, GUILD, QUEST and LOOT (SMART was removed in 0.4.0). Migrations run once in `ns.EnsureDB` behind `migratedV32` / `migratedV031` / `migratedV040` flags.
- Runs have `kind` (dungeon, raid, world). The Full Log's first line calls the story skill by name: `use wow-dungeon-raid-story` or `use wow-open-world-story`. The names live in `ns.STORY_SKILLS` (Core.lua) and feed both the Full Log and the templates' `name:` lines, so they stay in sync. Old saved logs were rewritten once behind `migratedV060`.
- Stories live in `RPChroniclerDB.stories` (since 0.5.0), each with a copy of its run's details, so deleting a run keeps the story. `adv.story` is legacy and migrated by `ns.MigrateStories`.
- Story colors: class colors, but Priest is gray `C0C0C0` and bosses are crimson `dc143c`. The two story templates live in `UI_Options.lua` (shared part `STORY_SHARED_RULES`) and must match the Full Log tags and the Story Book header/footer that `ns.ParseStoryMeta` reads.
- 0.6.0 renamed RPCopy to RP Chronicler everywhere: folder and toc `RPChronicler`, title "RP Chronicler", SavedVariables `RPChroniclerDB`, globals and frames `RPChronicler*`, bindings `RPCHRONICLER_*`, slash `/rp` and `/rpchronicler`. RPCopy had no other users, so there is no data migration from it (Mor moved Mor's own SavedVariables by hand).
- Mor asked to keep the floating `[RP]` button and not add a minimap button.
- Testing: there is no game here. Use a lupa (Lua 5.1) mock harness to load every toc file, click every button and fire events. PowerShell can't be run here, so `Export_Stories.bat` changes are untested until Mor runs them.
