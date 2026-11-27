-- 0.7.0 story sharing: one addon copy wired back to itself. What "we" send
-- to Bob comes back as sent BY Bob, so the same copy plays both ends:
-- the offer, the answer, the pieces and the receipt all go through
-- ns.ShareHeard. A filter can drop, repeat or shuffle messages.
dofile(ROOT .. "/tools/fixture/RPChronicler.lua")
Fire("ADDON_LOADED", "RPChronicler"); Fire("PLAYER_LOGIN"); RunTimers()
local fails = 0
local function Check(name, cond) io.write(cond and "ok   " or "FAIL ", name, "\n") if not cond then fails = fails + 1 end end

local wire, filter = {}, nil
NS._shareSend = function(msg, target) table.insert(wire, { msg = msg, from = target }) end
local prompts = {}
NS._sharePrompt = function(text, l1, f1, l2, f2, l3, f3) table.insert(prompts, { text = text, l1 = l1, f1 = f1, l2 = l2, f2 = f2, l3 = l3, f3 = f3 }) end
NS._shareInInstance = false
NS._shareRestricted = false

local function Pump(steps)
  for _ = 1, steps or 2000 do
    local batch = wire; wire = {}
    if filter then batch = filter(batch) end
    for _, m in ipairs(batch) do NS.ShareHeard(m.msg, m.from) end
    NOW = NOW + 0.25
    NS.ShareTick()
    local o, i = NS.ShareTransfers()
    if #wire == 0 and next(o) == nil and next(i) == nil then return end
  end
end
local function Count() return #NS.GetStories() end
local function Gifts() local n = 0 for _, st in ipairs(NS.GetStories()) do if st.shared then n = n + 1 end end return n end

local st = NS.GetStories()[1]
st.story = st.story .. "\nA bad icon |TInterface\\Icons\\Spell_Fire:0|t and a link |Hitem:19019|h[Thunderfury]|h and |Kq1|k and |cffff0000red|r\1."

-- looks: yours on the story, one on a party member, a picked face
st.look = { v = 1, race = 2, sex = 2, class = "WARRIOR", slots = { [1] = { a = 1234, s = 0, i = 0 }, [5] = { a = 777, s = 12, i = 0 } } }
if st.participants and st.participants[1] then st.participants[1].look = { v = 1, race = 8, sex = 3, class = "MAGE", slots = { [5] = { a = 99, s = 0, i = 0 } } } end
local lraw = NS.BuildSharePayload(st, { face = { id = 4242, name = "Guard" } })
local ld = NS.ReadSharePayload(lraw)
Check("looks travel", ld and ld.looks[0] and ld.looks[0].slots[5].a == 777 and ld.looks[0].slots[5].s == 12 and ld.face and ld.face.id == 4242)
Check("bad look dropped", (function() local x = NS.ReadSharePayload("@v 1\n@look 0\tabc\t2\tX\t1:2:3:4\n@story\nHi") return x and x.looks[0] == nil end)())
io.write("payload with looks: ", #lraw, " bytes\n")

-- payload round trip and cleaning
local raw = NS.BuildSharePayload(st)
local d = NS.ReadSharePayload(raw)
Check("payload reads back", d and d.story and #d.parts >= 1)
Check("icons, links and control chars removed", d and not d.story:find("|T", 1, true) and not d.story:find("|H", 1, true) and not d.story:find("|K", 1, true) and not d.story:find("\1", 1, true) and d.story:find("[Thunderfury]", 1, true) ~= nil)
Check("colors kept", d and d.story:find("|cffff0000red|r", 1, true) ~= nil)
Check("bad keys and caps", (function()
  local x = NS.ReadSharePayload("@v 1\n@evil os.exit()\n@title " .. string.rep("a", 500) .. "\n@kind nope\n@g 0\t1\tnotanitem\n@story\nHi")
  return x and #x.title == 80 and x.kind == nil and x.items == 0 and x.evil == nil
end)())
Check("no story refused", NS.ReadSharePayload("@v 1\n@title x") == nil)
Check("too big refused", NS.ReadSharePayload("@v 1\n@story\n" .. string.rep("x", 70000)) == nil)

-- share codes, compressed and not
local code = NS.BuildShareCode(st, { face = { id = 4242, name = "Guard" } })
Check("code made", code and code:find("^RPCHRONICLER%-BOOK:1:%x+:Z") ~= nil)
local wrapped = code:sub(1, 60) .. "\n  " .. code:sub(61)
Check("wrapped code reads", NS.ReadShareCode(wrapped) ~= nil)
Check("changed code refused", NS.ReadShareCode(code:sub(1, -6) .. "abcde") == nil)
NS._shareNoDeflate = true
local ucode = NS.BuildShareCode(st)
NS._shareNoDeflate = nil
Check("uncompressed code reads", ucode:find(":U") and NS.ReadShareCode(ucode) ~= nil)
io.write("code sizes: deflate ", #code, ", plain ", #ucode, ", payload ", #raw, "\n")

-- sharing off: the offer is ignored
NS.Set("storySharing", "OFF")
local before = Count()
NS.ShareStoryWith(st.id, "Bob-Realm")
Pump(400)
Check("off: nothing arrives, no prompt", Count() == before and #prompts == 0)
NOW = NOW + 120

-- a clean transfer
NS.Set("storySharing", "ANYONE")
NS.ShareStoryWith(st.id, "Bob-Realm")
Pump(3)
Check("asked first", #prompts == 1 and prompts[1].l1 == "Accept Tome")
prompts[1].f1(); prompts = {}
Pump()
Check("clean transfer arrives", Count() == before + 1 and Gifts() == 1)
local g; for _, x in ipairs(NS.GetStories()) do if x.shared then g = x end end
io.write("gift: ", tostring(g and g.shared.author), " ", tostring(g and g.shelf), " ", tostring(g and g.runId), "\n")
Check("gift fields", g.shared and g.shared.author == "Bob-Realm" and g.shelf == "gifts" and not g.runId and NS.FindShelf("gifts") ~= nil)
Check("gift text clean", not g.story:find("|T", 1, true))
NOW = NOW + 120

-- lost, repeated and shuffled pieces
local n = 0
filter = function(b)
  local outb = {}
  for _, m in ipairs(b) do
    n = n + 1
    if m.msg:sub(1, 1) == "D" and n % 3 == 0 then -- lost
    elseif m.msg:sub(1, 1) == "D" and n % 5 == 0 then table.insert(outb, m); table.insert(outb, 1, m) -- repeated, early
    else table.insert(outb, m) end
  end
  return outb
end
NS.ShareStoryWith(st.id, "Bob-Realm")
Pump(3)
Check("repeat asks replace or keep both", #prompts == 1 and prompts[1].l1 == "Replace")
prompts[1].f1(); prompts = {}
Pump()
Check("lossy transfer arrives (replaced)", Count() == before + 1 and Gifts() == 1)
filter = nil
NOW = NOW + 120

-- damaged piece: checksum catches it
filter = function(b)
  for _, m in ipairs(b) do
    if m.msg:match("^D %w+ 2 ") then m.msg = m.msg:sub(1, -3) .. "zz" end
  end
  return b
end
NS.ShareStoryWith(st.id, "Bob-Realm")
Pump(3); prompts[1].f2(); prompts = {}   -- keep both
Pump()
Check("damaged book refused", Gifts() == 1)
filter = nil
NOW = NOW + 120

-- lockdown pauses the sender, then it goes on
NS.ShareStoryWith(st.id, "Bob-Realm")
Pump(3); prompts[1].f2(); prompts = {}
NS._shareRestricted = true
Pump(400)
local o = NS.ShareTransfers()
Check("paused in lockdown", next(o) ~= nil)
NS._shareRestricted = false
Pump()
Check("resumes after lockdown", Gifts() == 2)
NOW = NOW + 120

-- block (a new book: the repeat prompt has no Block button)
for _, x in ipairs(NS.GetStories()) do if x.shared then x.shared.srcId = "old" end end
NS.ShareStoryWith(st.id, "Bob-Realm")
Pump(3); prompts[1].f3(); prompts = {}
Pump()
Check("blocked", NS.ShareBlocked("Bob") and Gifts() == 2)
NOW = NOW + 120
NS.ShareStoryWith(st.id, "Bob-Realm")
Pump(400)
Check("blocked sender ignored", #prompts == 0)
NS.ClearShareBlocks()

-- the receiver goes away mid-transfer (logout): it times out
NOW = NOW + 120
NS.ShareStoryWith(st.id, "Bob-Realm")
Pump(3); prompts[1].f2(); prompts = {}
filter = function() return {} end
Pump(400)
local o2, i2 = NS.ShareTransfers()
Check("silence drops the transfer", next(o2) == nil and next(i2) == nil and Gifts() == 2)
filter = nil

-- in an instance: refused
NS._shareInInstance = true
Check("no sending in a dungeon", not NS.ShareStoryWith(st.id, "Bob-Realm"))
NS._shareInInstance = false

-- names: first and last name, junk, not online
local c = NS.ShareCandidates("Morai Galeclaw")
Check("first name is tried first", c[1] == "Morai" and c[2] == "MoraiGaleclaw")
Check("realm kept", NS.ShareCandidates("Morai Galeclaw-Some Realm")[1] == "Morai-SomeRealm")
Check("empty refused", not NS.ShareStoryWith(st.id, "  "))
NOW = NOW + 120
filter = function() return {} end
NS.ShareStoryWith(st.id, "dsjfls")
Fire("CHAT_MSG_SYSTEM", "No player named 'dsjfls' is currently playing.")
local o3 = NS.ShareTransfers()
Check("not online: dropped at once", next(o3) == nil and PRINTED:find("No player named", 1, true) ~= nil)
NS.ShareStoryWith(st.id, "Ghost")
Pump(60)
local o4 = NS.ShareTransfers()
Check("no addon: ping times out", next(o4) == nil and PRINTED:find("did not answer", 1, true) ~= nil)
filter = nil
Check("people list", type(NS.SharePeople()) == "table")

-- the code path saves a gift too
local okc, idc = NS.AddSharedStory(NS.ReadShareCode(code), { via = "code" })
Check("share code import", okc and NS.FindStory(idc).shared.via == "code")
local gs = NS.FindStory(idc)
local author; for _, p in ipairs(gs.participants) do if p.author then author = p end end
Check("author entry carries look and face", author and author.look and author.look.race == 2 and author.face and author.face.id == 4242)
NS.UI.OpenStoryBook(idc); RunTimers()
local okm, errm = pcall(NS.UI.book.OpenMenu)
Check("book menu opens on a gift", okm)
if not okm then io.write(tostring(errm), "\n") end
Check("look from a transmog list", NS.LookFromList({ [1] = { appearanceID = 5 }, [3] = { appearanceID = 0 } }, 2, 2, "WARRIOR", "self").slots[1].a == 5)
Check("re-shared gift keeps the face", NS.ReadSharePayload(NS.BuildSharePayload(gs)).face ~= nil)

io.write(fails == 0 and "SHARE OK\n" or ("SHARE FAILS " .. fails .. "\n"))
for _, l in ipairs((RPChroniclerDB and RPChroniclerDB.debugLog) or {}) do
  if l:find("error") then io.write("DEBUG: ", l, "\n") end
end
