# RPCopy working rules

- **Bump the version on every change.** Edit `## Version` in `RPCopy.toc` (the chat banner and window badge read it), the fallback strings in `Core.lua` (`ns.VERSION`) and `UI.lua` (`verBadge`), and the Version line in `README.md`.
  - The addon is in alpha. Versioning restarted at 0.1.0 (the old 3.x tags were retired); stay below 1.0.0 until Mor says otherwise.
  - Small fix: patch bump, e.g. 0.1.0 -> 0.1.1.
  - Big update: minor bump, e.g. 0.1.x -> 0.2.0.
- Keep the toc load order: Core -> Snapshot -> Adventures -> Screenshots -> Events -> UI.
- The Forever client (Interface 16001) runs on the modern engine. Guard APIs, never register `COMBAT_LOG_EVENT_UNFILTERED`, and make no protected calls in combat. If a "blocked from an action" popup appears, read `..\..\..\Logs\taint.log`.
- No non-ASCII glyphs or Markdown in FontStrings or EditBoxes. Use `|cffRRGGBB...|r` codes, and normalize `||` to `|` on pasted text.
- Lua 5.1 caps a function at 200 *active* locals, and locals inside a top-level `do ... end` still count while that block runs. `UI.lua`'s main chunk peaks at about 187 (0.1.0); going over stops the whole file loading ("main function has more than 200 local variables"). Put new UI code in a `do ... end` block or on a table, keep block-local counts small, and run `python tools/check_locals.py UI.lua` before every commit (no Lua interpreter is installed here).
- In Git Bash heredocs on this machine, `\\` collapses to `\`. Write files containing backslashes with the Write/Edit tools, not heredocs.
- Keep `README.md` in step with user-visible changes.
- Commit only after Mor approves. Mor pushes.
- azaxyno is the only author and contributor. Never add `Co-Authored-By: Claude`, `Claude-Session:` or any other AI attribution to commits, tags or releases.
- Every pushed version gets a tag `vX.Y.Z` and a GitHub Release (pre-release while in alpha). The release notes have a short intro, a "What's new" list of user-visible changes since the last release, "Fixes", and install steps. Attach `RPCopy-vX.Y.Z.zip`, which holds an `RPCopy/` folder with only the addon files (toc, .lua, Bindings.xml, README.md, LICENSE, CREDITS.md, Export_Stories.bat). Leave out docs, tools, .claude, backup, CLAUDE.md and the PDF.
