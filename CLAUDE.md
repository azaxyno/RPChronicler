# RPCopy working rules

- **Bump the version on every change.** Edit `## Version` in `RPCopy.toc` (the chat banner and window badge read it), the fallback strings in `Core.lua` (`ns.VERSION`) and `UI.lua` (`verBadge`), and the Version line in `README.md`.
  - Small fix: patch bump, e.g. 3.7.1 -> 3.7.2.
  - Big update: minor bump, e.g. 3.7.x -> 3.8.0.
- Keep the toc load order: Core -> Snapshot -> Adventures -> Screenshots -> Events -> UI.
- The Forever client (Interface 16001) runs on the modern engine. Guard APIs, never register `COMBAT_LOG_EVENT_UNFILTERED`, and make no protected calls in combat. If a "blocked from an action" popup appears, read `..\..\..\Logs\taint.log`.
- No non-ASCII glyphs or Markdown in FontStrings or EditBoxes. Use `|cffRRGGBB...|r` codes, and normalize `||` to `|` on pasted text.
- Keep `README.md` in step with user-visible changes.
- Commit only after Mor approves. Mor pushes.
