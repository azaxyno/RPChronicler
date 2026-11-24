# RPCopy working rules

- **Bump the version on every change.** Edit `## Version` in `RPCopy.toc` (the chat banner and window badge read it), the fallback strings in `Core.lua` (`ns.VERSION`) and `UI.lua` (`verBadge`), and the Version line in `README.md`.
  - Small fix: patch bump, e.g. 3.7.1 -> 3.7.2.
  - Big update: minor bump, e.g. 3.7.x -> 3.8.0.
- Keep the toc load order: Core -> Snapshot -> Adventures -> Screenshots -> Events -> UI.
- The Forever client (Interface 16001) runs on the modern engine. Guard APIs, never register `COMBAT_LOG_EVENT_UNFILTERED`, and make no protected calls in combat. If a "blocked from an action" popup appears, read `..\..\..\Logs\taint.log`.
- No non-ASCII glyphs or Markdown in FontStrings or EditBoxes. Use `|cffRRGGBB...|r` codes, and normalize `||` to `|` on pasted text.
- Lua 5.1 caps a function at 200 *active* locals, and locals inside a top-level `do ... end` still count while that block runs. `UI.lua`'s main chunk peaks at about 187 (3.9.1); going over stops the whole file loading ("main function has more than 200 local variables"). Put new UI code in a `do ... end` block or on a table, keep block-local counts small, and run `python tools/check_locals.py UI.lua` before every commit (no Lua interpreter is installed here).
- In Git Bash heredocs on this machine, `\\` collapses to `\`. Write files containing backslashes with the Write/Edit tools, not heredocs.
- Keep `README.md` in step with user-visible changes.
- Commit only after Mor approves. Mor pushes.
