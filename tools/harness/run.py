"""Mock harness: loads every toc file of RP Chronicler in Lua 5.1 (lupa)
with stubbed WoW APIs, then runs a scenario script.

    pip install lupa
    python tools/harness/run.py <scenario.lua> [addon folder]

The scenario sees the addon's table as NS and the helpers from stubs.lua
(UNITS, INSTANCE, ZONE, NOW, Fire, RunTimers)."""
import os, sys
import lupa.lua51 as L

here = os.path.dirname(os.path.abspath(__file__))
root = sys.argv[2] if len(sys.argv) > 2 else os.path.abspath(os.path.join(here, "..", ".."))
lua = L.LuaRuntime(unpack_returned_tuples=True)
lua.execute(open(os.path.join(here, "stubs.lua"), encoding="utf-8").read())
ns = lua.eval("{}")
lua.globals().NS = ns
lua.globals().ROOT = root
loader = lua.execute('return function(src, name) local f, err = loadstring(src, "@" .. name); if not f then error(err) end; return f end')
toc = open(os.path.join(root, "RPChronicler.toc"), encoding="utf-8").read().splitlines()
for line in toc:
    f = line.strip()
    if f.endswith(".lua"):
        loader(open(os.path.join(root, f), encoding="utf-8").read(), f)("RPChronicler", ns)
lua.execute(open(sys.argv[1], encoding="utf-8").read())
