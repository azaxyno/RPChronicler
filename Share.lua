local ADDON_NAME, ns = ...

-- =========================================================
-- Story sharing (0.7.0). A finished story can go to a friend who also has
-- RP Chronicler, through the game's own addon whispers (prefix RPCHRONB,
-- WHISPER only, never guild or group broadcasts), or as a share code the
-- player copies and the friend pastes into + Import.
--   * The friend is asked first (Accept / Decline / Block) and only gets
--     anything when storySharing allows the sender (Options > Privacy; friends,
--     guild and group by default).
--   * The book is a strict "@key value" text (never loadstring, only the
--     keys below, every value capped and cleaned), with an Adler-32
--     checksum; story text keeps only |cffXXXXXX and |r escapes.
--   * No screenshots, no Run ID link, no chat. Transfers live in memory:
--     60 s of silence, a logout or a disconnect drops them.
--   * Sends only outside instances and out of combat; a transfer pauses
--     while the game restricts addon messages and resumes after.
-- Messages (P1, space separated):
--   O id n sum proto src title   offer       Y id / N id reason   answer
--   D id i data                  one piece   E id                 end
--   M id i,j,k                   missing     G id / B id          got / bad
-- =========================================================
local PREFIX = "RPCHRONB"
local PROTO = "P1"
local PIECE = 200            -- data bytes per piece (message cap is 255)
local PACE = 0.25            -- one piece every 0.25 s = 4 a second
local TIMEOUT = 60           -- seconds of silence that end a transfer
local MAX_PAYLOAD = 65536
local MAX_PIECES = 200
local MAX_WAITING = 2        -- offers waiting for an answer at once
local OFFER_GAP = 60         -- one offer per sender per minute
local CAP = { title = 80, value = 120, party = 5, bosses = 40, items = 300, places = 200, looks = 6 }
ns.SHARE_CODE_TAG = "RPCHRONICLER-BOOK"
ns.SHARE_PROTO = PROTO

local registered = false
local out, inc = {}, {}      -- transfers: outgoing by id, incoming by sender#id
local waiting = {}           -- incoming offers not answered yet (in order)
local lastOffer = {}
local ticker
local seq = 0

local function Now() return (GetTime and GetTime()) or 0 end
local function Say(msg) print("|cffffd100RP Chronicler|r " .. msg) end
local function Gold(s) return "|cffffd100" .. tostring(s) .. "|r" end
local function Short(name) return ns.ShortName and ns.ShortName(name) or tostring(name or "?") end

-- =========================================================
-- Cleaning (the receiver trusts nothing it is sent)
-- =========================================================
-- Every escape is removed except colors (|cffXXXXXX) and |r: no icons
-- (|T |A), no links (|H, the shown text is kept), no |K, no grammar codes.
function ns.ShareClean(s, keepLines)
    s = tostring(s or ""):gsub("||", "|")
    s = s:gsub("|[Tt].-|t", ""):gsub("|A.-|a", ""):gsub("|K.-|k", "")
    s = s:gsub("|H.-|h(.-)|h", "%1")
    local outp, i, len = {}, 1, #s
    while i <= len do
        local c = s:sub(i, i)
        if c == "|" then
            local nx = s:sub(i + 1, i + 1)
            if (nx == "c" or nx == "C") and s:sub(i + 2, i + 9):match("^%x%x%x%x%x%x%x%x$") then
                outp[#outp + 1] = "|c" .. s:sub(i + 2, i + 9)
                i = i + 10
            elseif nx == "r" or nx == "R" then
                outp[#outp + 1] = "|r"
                i = i + 2
            else
                i = i + 1          -- a lone or unknown escape: drop the bar
            end
        else
            outp[#outp + 1] = c
            i = i + 1
        end
    end
    s = table.concat(outp)
    s = s:gsub("\r\n", "\n"):gsub("[%z\1-\9\11-\31\127]", "")
    if not keepLines then s = s:gsub("\n", " ") end
    return s
end

-- A plain one-line value: no escapes at all, capped
local function Plain(v, cap)
    local s = ns.ShareClean(v):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    s = s:gsub("^%s+", ""):gsub("%s+$", "")
    if #s > (cap or CAP.value) then s = s:sub(1, cap or CAP.value) end
    return s
end
local function Num(v, lo, hi)
    local n = tonumber(v)
    if not n or n ~= n then return nil end
    if lo and n < lo then return nil end
    if hi and n > hi then return nil end
    return n
end

-- Adler-32, as 8 hex digits
function ns.Adler32(s)
    local a, b = 1, 0
    for i = 1, #s do
        a = (a + s:byte(i)) % 65521
        b = (b + a) % 65521
    end
    return string.format("%08x", b * 65536 + a)
end

-- =========================================================
-- Packing: LibDeflate (embedded, zlib License) when present, else the
-- text with %XX escapes. "Z..." compressed, "U..." uncompressed.
-- =========================================================
local function LD()
    if ns.LibDeflate then return ns.LibDeflate end
    if LibStub and LibStub.GetLibrary then
        local ok, lib = pcall(LibStub.GetLibrary, LibStub, "LibDeflate", true)
        if ok then return lib end
    end
    return nil
end

function ns.SharePack(raw, forPrint)
    local L = not ns._shareNoDeflate and LD() or nil
    if L then
        local ok, z = pcall(L.CompressDeflate, L, raw, { level = 6 })
        if ok and z then
            local ok2, enc = pcall(forPrint and L.EncodeForPrint or L.EncodeForWoWAddonChannel, L, z)
            if ok2 and enc then return "Z" .. enc end
        end
    end
    return "U" .. raw:gsub("[%%%c|%s\128-\255]", function(c) return string.format("%%%02X", c:byte()) end)
end

function ns.ShareUnpack(data, forPrint)
    if type(data) ~= "string" then return nil end
    local tag, body = data:sub(1, 1), data:sub(2)
    if tag == "U" then
        return (body:gsub("%%(%x%x)", function(h) return string.char(tonumber(h, 16)) end))
    elseif tag == "Z" then
        local L = LD()
        if not L then return nil end
        local ok, z = pcall(forPrint and L.DecodeForPrint or L.DecodeForWoWAddonChannel, L, body)
        if not ok or not z then return nil end
        local ok2, raw = pcall(L.DecompressDeflate, L, z)
        if ok2 and type(raw) == "string" then return raw end
    end
    return nil
end

-- =========================================================
-- The book as text. Fields are joined by tabs (tabs never survive the
-- cleaning, so a value can't break out of its field). The story is last.
-- =========================================================
local function J(...)
    local t = { ... }
    for i = 1, select("#", ...) do t[i] = Plain(t[i] == nil and "" or t[i]) end
    return table.concat(t, "\t")
end
local function ItemString(link)
    return type(link) == "string" and link:match("(item:[%-%d:]+)") or nil
end

-- A look (0.7.0): { race, sex, class, slots = { [slot] = { a, s, i } } }
function ns.LookToText(look)
    if type(look) ~= "table" then return nil end
    local parts = {}
    for slot, v in pairs(type(look.slots) == "table" and look.slots or {}) do
        if Num(slot, 1, 30) and type(v) == "table" then
            parts[#parts + 1] = string.format("%d:%d:%d:%d", slot, Num(v.a, 0) or 0, Num(v.s, 0) or 0, Num(v.i, 0) or 0)
        end
    end
    table.sort(parts)
    return table.concat({ Num(look.race, 0, 999) or 0, Num(look.sex, 0, 3) or 0, Plain(look.class, 20), table.concat(parts, ",") }, "\t")
end
function ns.LookFromText(race, sex, class, slots)
    local look = { v = 1, race = Num(race, 1, 999), sex = Num(sex, 0, 3), class = Plain(class, 20), slots = {}, src = "shared" }
    if not look.race then return nil end
    local n = 0
    for s, a, sec, i in tostring(slots or ""):gmatch("(%d+):(%d+):(%d+):(%d+)") do
        s = Num(s, 1, 30)
        if s and n < 30 then
            look.slots[s] = { a = Num(a, 0, 1e7) or 0, s = Num(sec, 0, 1e7) or 0, i = Num(i, 0, 1e7) or 0 }
            n = n + 1
        end
    end
    return look
end

function ns.BuildSharePayload(st, opts)
    if type(st) ~= "table" or (st.story or "") == "" then return nil end
    opts = opts or {}
    local L = {}
    local function W(k, ...) L[#L + 1] = "@" .. k .. " " .. J(...) end
    local shared = type(st.shared) == "table" and st.shared or nil
    W("v", 1)
    W("app", ns.VERSION)
    W("from", shared and shared.author or st.char or ns.PlayerName())
    W("src", shared and shared.srcId or st.id)
    local info = ns.GetBookInfo and ns.GetBookInfo(st) or {}
    W("title", ns.StripColors(info.name or st.title or "Story"))
    if st.kind then W("kind", st.kind) end
    if st.zone then W("zone", st.zone) end
    if st.instanceName then W("inst", st.instanceName) end
    if st.ejInstance then W("ej", st.ejInstance) end
    if st.startDate then W("start", st.startDate) end
    if st.endDate then W("end", st.endDate) end
    if st.startTime then W("stime", st.startTime) end
    if st.endTime then W("etime", st.endTime) end
    if st.duration then W("dur", st.duration) end
    if st.char then W("char", st.char) end
    local items = 0
    local function Gear(idx, list)
        for _, g in ipairs(type(list) == "table" and list or {}) do
            local s = type(g) == "table" and ItemString(g.link)
            if s and items < CAP.items then
                items = items + 1
                W("g", idx, g.slot, s, g.q, g.name)
            end
        end
    end
    Gear(0, st.gear)
    for i, p in ipairs(type(st.participants) == "table" and st.participants or {}) do
        if i > CAP.party then break end
        if type(p) == "table" then
            W("p", i, p.name, p.classFile, p.class, p.race, p.raceName, p.sex, p.role, p.level)
            Gear(i, p.gear)
            local lt = ns.LookToText(p.look)
            if lt then L[#L + 1] = "@look " .. i .. "\t" .. lt end
        end
    end
    local lt = ns.LookToText(opts.look or st.look)
    if lt then L[#L + 1] = "@look 0\t" .. lt end
    local face = opts.face
    if not face and shared then
        for _, p in ipairs(type(st.participants) == "table" and st.participants or {}) do
            if type(p) == "table" and p.author and type(p.face) == "table" then face = p.face end
        end
    end
    if face and face.id then W("face", face.id, face.name) end
    local bi = type(st.bossInfo) == "table" and st.bossInfo or {}
    for i, b in ipairs(type(st.bossKills) == "table" and st.bossKills or {}) do
        if i > CAP.bosses then break end
        local info2 = type(bi[b]) == "table" and bi[b] or {}
        W("boss", b, info2.encounter, info2.cls, info2.level)
    end
    for i, pl in ipairs(type(st.places) == "table" and st.places or {}) do
        if i > CAP.places then break end
        if type(pl) == "string" then W("place", pl) end
    end
    L[#L + 1] = "@story"
    L[#L + 1] = ns.ShareClean(st.story, true)
    local raw = table.concat(L, "\n")
    if #raw > MAX_PAYLOAD then return nil, "big" end
    return raw
end

-- Each key the reader knows, and what it may hold. Unknown keys are skipped.
local function Fields(v) local t = {} for f in (v .. "\t"):gmatch("([^\t]*)\t") do t[#t + 1] = f end return t end
local READ = {
    v = function(d, f) d.v = Num(f[1]) end,
    app = function(d, f) d.app = Plain(f[1], 12) end,
    from = function(d, f) d.from = Plain(f[1], 60) end,
    src = function(d, f) d.src = Plain(f[1], 24) end,
    title = function(d, f) d.title = Plain(f[1], CAP.title) end,
    kind = function(d, f) local k = Plain(f[1], 10) if k == "dungeon" or k == "raid" or k == "world" then d.kind = k end end,
    zone = function(d, f) d.zone = Plain(f[1]) end,
    inst = function(d, f) d.instanceName = Plain(f[1]) end,
    ej = function(d, f) d.ejInstance = Num(f[1], 0, 1e7) end,
    start = function(d, f) d.startDate = Plain(f[1], 20) end,
    ["end"] = function(d, f) d.endDate = Plain(f[1], 20) end,
    stime = function(d, f) d.startTime = Num(f[1], 0) end,
    etime = function(d, f) d.endTime = Num(f[1], 0) end,
    dur = function(d, f) d.duration = Num(f[1], 0, 1e7) end,
    char = function(d, f) d.char = Plain(f[1], 60) end,
    p = function(d, f)
        local i = Num(f[1], 1, CAP.party)
        if not i or (f[2] or "") == "" then return end
        d.parts[i] = { name = Plain(f[2], 60), classFile = Plain(f[3], 20):upper():gsub("[^A-Z]", ""), class = Plain(f[4], 30),
            race = Num(f[5], 0, 999), raceName = Plain(f[6], 30), sex = Num(f[7], 0, 3), role = Plain(f[8], 10), level = Num(f[9], 0, 200) }
    end,
    g = function(d, f)
        local i, s = Num(f[1], 0, CAP.party), f[3] and f[3]:match("^item:[%-%d:]+$")
        if not i or not s or d.items >= CAP.items or #s > 120 then return end
        d.items = d.items + 1
        d.gear[i] = d.gear[i] or {}
        table.insert(d.gear[i], { slot = Num(f[2], 0, 30), link = s, q = Num(f[4], 0, 9), name = Plain(f[5], 60) })
    end,
    look = function(d, f)
        local i = Num(f[1], 0, CAP.party)
        if i then d.looks[i] = ns.LookFromText(f[2], f[3], f[4], f[5]) end
    end,
    face = function(d, f) d.face = { id = Num(f[1], 1, 1e7), name = Plain(f[2], 60) } if not d.face.id then d.face = nil end end,
    boss = function(d, f)
        local name = Plain(f[1], 60)
        if name == "" or #d.bosses >= CAP.bosses then return end
        table.insert(d.bosses, { name = name, encounter = Num(f[2], 0, 1e7), cls = Plain(f[3], 20), level = Num(f[4], -1, 200) })
    end,
    place = function(d, f)
        local name = Plain(f[1], 60)
        if name ~= "" and #d.places < CAP.places then table.insert(d.places, name) end
    end,
}

-- The book text back as a plain table, or nil and why
function ns.ReadSharePayload(raw)
    if type(raw) ~= "string" then return nil, "empty" end
    if #raw > MAX_PAYLOAD then return nil, "big" end
    local head, story = raw:match("^(.-)\n@story\n(.*)$")
    if not head then return nil, "nostory" end
    local d = { parts = {}, gear = {}, looks = {}, bosses = {}, places = {}, items = 0 }
    for line in (head .. "\n"):gmatch("([^\n]*)\n") do
        local k, v = line:match("^@(%l+) (.*)$")
        if k and READ[k] then pcall(READ[k], d, Fields(v)) end
    end
    if d.v ~= 1 then return nil, "version" end
    d.story = ns.ShareClean(story, true)
    if d.story:match("^%s*$") then return nil, "nostory" end
    -- party in order, no holes
    local parts = {}
    for i = 1, CAP.party do if d.parts[i] then parts[#parts + 1] = d.parts[i]; d.parts[i].idx = i end end
    d.parts = parts
    return d
end

-- =========================================================
-- Share codes: RPCHRONICLER-BOOK:1:<checksum>:<data>
-- =========================================================
function ns.BuildShareCode(st, opts)
    local raw, why = ns.BuildSharePayload(st, opts)
    if not raw then return nil, why end
    return ns.SHARE_CODE_TAG .. ":1:" .. ns.Adler32(raw) .. ":" .. ns.SharePack(raw, true)
end

function ns.IsShareCode(text)
    return type(text) == "string" and text:find(ns.SHARE_CODE_TAG .. ":", 1, true) ~= nil
end

-- Returns the book table, or nil and why
function ns.ReadShareCode(text)
    if not ns.IsShareCode(text) then return nil, "nocode" end
    local s = text:gsub("%s", "")
    local ver, sum, data = s:match("RPCHRONICLER%-BOOK:(%d+):(%x+):(.+)$")
    if not ver then return nil, "nocode" end
    if ver ~= "1" then return nil, "version" end
    if #data > MAX_PAYLOAD * 2 then return nil, "big" end
    local raw = ns.ShareUnpack(data, true)
    if not raw then return nil, "damaged" end
    if ns.Adler32(raw) ~= sum:lower() then return nil, "damaged" end
    return ns.ReadSharePayload(raw)
end

ns.SHARE_WHY = {
    big = "The story is too long to send.", nostory = "There is no story in it.", version = "It was made by a newer RP Chronicler. Update yours.",
    damaged = "The book arrived damaged (a piece is missing or changed).", nocode = "That is not a share code.", empty = "It is empty.",
}

-- =========================================================
-- Who may give you books
-- =========================================================
local function Setting() return ns.Get("storySharing") or "OFF" end

function ns.ShareBlocked(name)
    local list = RPChroniclerDB and RPChroniclerDB.shareBlocked
    return type(list) == "table" and list[Short(name)] and true or false
end
function ns.BlockSharer(name)
    ns.EnsureDB()
    RPChroniclerDB.shareBlocked = type(RPChroniclerDB.shareBlocked) == "table" and RPChroniclerDB.shareBlocked or {}
    RPChroniclerDB.shareBlocked[Short(name)] = true
    ns.Notify("setting", "shareBlocked")
end
function ns.ClearShareBlocks()
    if RPChroniclerDB then RPChroniclerDB.shareBlocked = {} end
    ns.Notify("setting", "shareBlocked")
end
function ns.ShareBlockedList()
    local t = {}
    for n in pairs(RPChroniclerDB and type(RPChroniclerDB.shareBlocked) == "table" and RPChroniclerDB.shareBlocked or {}) do t[#t + 1] = n end
    table.sort(t)
    return t
end

local function Try(fn, ...)
    if not fn then return nil end
    local ok, r = pcall(fn, ...)
    if not ok then return nil end
    return ns.SafeBool and ns.SafeBool(r) or r
end

-- Friends list, Battle.net friends, your guild and your group
function ns.IsFriendly(name)
    local short = Short(name)
    if Try(UnitInParty, short) or Try(UnitInRaid, short) then return true end
    if C_FriendList and C_FriendList.GetFriendInfo then
        local ok, info = pcall(C_FriendList.GetFriendInfo, short)
        if ok and info then return true end
        ok, info = pcall(C_FriendList.GetFriendInfo, name)
        if ok and info then return true end
    end
    if C_GuildInfo and Try(C_GuildInfo.MemberExistsByName, short) then return true end
    if BNGetNumFriends and C_BattleNet and C_BattleNet.GetFriendNumGameAccounts and C_BattleNet.GetFriendGameAccountInfo then
        local ok, n = pcall(BNGetNumFriends)
        for i = 1, (ok and tonumber(n) or 0) do
            local okc, c = pcall(C_BattleNet.GetFriendNumGameAccounts, i)
            for j = 1, (okc and tonumber(c) or 0) do
                local oki, gi = pcall(C_BattleNet.GetFriendGameAccountInfo, i, j)
                if oki and type(gi) == "table" and gi.characterName == short then return true end
            end
        end
    end
    return false
end

-- =========================================================
-- Sending and pacing
-- =========================================================
local function Register()
    if registered then return true end
    if not (C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix and C_ChatInfo.SendAddonMessage) then return false end
    registered = pcall(C_ChatInfo.RegisterAddonMessagePrefix, PREFIX) and true or false
    return registered
end

local function Send(msg, target)
    if ns._shareSend then return ns._shareSend(msg, target) end
    if not Register() then return end
    local ok = pcall(C_ChatInfo.SendAddonMessage, PREFIX, msg, "WHISPER", target)
    if not ok then ns.Debug("info", "share message not sent") end
end

-- The game restricts addon messages (Midnight lockdown, combat, encounters)
function ns.ShareRestricted()
    if ns._shareRestricted ~= nil then return ns._shareRestricted end
    if InCombatLockdown and InCombatLockdown() then return true end
    if C_ChatInfo and Try(C_ChatInfo.InChatMessagingLockdown) then return true end
    if Try(IsEncounterInProgress) then return true end
    return false
end
local function InInstance()
    if ns._shareInInstance ~= nil then return ns._shareInInstance end
    return Try(IsInInstance) and true or false
end

local function Busy() return next(out) ~= nil or next(inc) ~= nil end
local Tick
local function Wake()
    if ticker or ns._shareSend then return end
    if C_Timer and C_Timer.NewTicker then ticker = C_Timer.NewTicker(PACE, function() Tick() end) end
end
local function Sleep()
    if ticker and not Busy() then
        pcall(ticker.Cancel, ticker)
        ticker = nil
    end
end

local function NewId()
    seq = seq + 1
    local n = (math.random and math.random(0, 46655) or 0) * 100 + seq % 100
    return string.format("%x", n)
end

local function Fail(t, why)
    out[t.id] = nil
    Say(string.format("The courier faltered -- could not deliver your tome to %s.%s", Gold(Short(t.to)), why and (" " .. why) or ""))
    ns.Notify("shareChanged")
end

-- ok, why. Asks the friend first; the pieces go only after Accept.
function ns.ShareStoryWith(storyId, target, opts)
    local st = ns.FindStory(storyId)
    target = type(target) == "string" and target:gsub("^%s+", ""):gsub("%s+$", "") or ""
    if not st then return false, "No story." end
    if target == "" or target:find("[%s%c|]") then return false, "Type a character name (Name or Name-Realm)." end
    if Short(target) == Short(ns.PlayerName()) then return false, "That is you." end
    if InCombatLockdown and InCombatLockdown() then return false, "Leave combat first." end
    if InInstance() then return false, "Leave the dungeon first. Books are sent only in the open world and in cities." end
    local raw, why = ns.BuildSharePayload(st, opts)
    if not raw then return false, ns.SHARE_WHY[why] or "Could not make the book." end
    local data = ns.SharePack(raw, false)
    local pieces = {}
    for i = 1, #data, PIECE do pieces[#pieces + 1] = data:sub(i, i + PIECE - 1) end
    if #pieces > MAX_PIECES then return false, "The story is too long to send. Use Copy share code instead." end
    local id = NewId()
    local title = Plain(ns.StripColors((ns.GetBookInfo and ns.GetBookInfo(st).name) or st.title or "Story"), CAP.title)
    local src = Plain((type(st.shared) == "table" and st.shared.srcId) or st.id, 24)
    out[id] = { id = id, to = target, pieces = pieces, sum = ns.Adler32(raw), title = title, state = "ASK", last = Now(), rounds = 0, ends = 0 }
    Send(string.format("O %s %d %s %s %s %s", id, #pieces, out[id].sum, PROTO, src ~= "" and src or "-", title), target)
    Say(string.format("Asking %s to accept '%s'...", Gold(Short(target)), title))
    Wake()
    return true
end

local function Missing(t)
    local miss = {}
    for i = 1, t.n do
        if not t.pieces[i] then
            miss[#miss + 1] = i
            if #miss >= 40 then break end
        end
    end
    return miss
end

local function Finish(t)
    if t.done then Send("G " .. t.id, t.from) return end
    local data = table.concat(t.pieces)
    local raw = ns.ShareUnpack(data, false)
    local d, why
    if raw and ns.Adler32(raw) == t.sum then d, why = ns.ReadSharePayload(raw) else why = "damaged" end
    if not d then
        inc[t.key] = nil
        Send("B " .. t.id, t.from)
        Say(string.format("A book from %s could not be read. %s", Gold(Short(t.from)), ns.SHARE_WHY[why] or ""))
        return
    end
    local ok, id = ns.AddSharedStory(d, { author = t.from, via = "whisper", mode = t.mode })
    t.done = true
    t.last = Now()
    Send("G " .. t.id, t.from)
    if ok then
        Say(string.format("A gifted tome from %s has been placed upon your shelf: '%s'. Open your Library to read it.", Gold(Short(t.from)), d.title or "Story"))
        ns.Notify("shareReceived", id)
    end
end

-- Offers waiting for an answer: one prompt at a time
local AskNext
local function Answer(t, yes, mode)
    for i, w in ipairs(waiting) do if w == t then table.remove(waiting, i) break end end
    if yes and inc[t.key] then
        t.state, t.mode, t.last = "RECV", mode, Now()
        Send("Y " .. t.id, t.from)
    else
        inc[t.key] = nil
        Send("N " .. t.id .. " declined", t.from)
    end
    AskNext()
end
function AskNext()
    local t = waiting[1]
    if not t or t.asked then return end
    t.asked = true
    local prompt = ns._sharePrompt or function(...) ns.Notify("prompt", ...) end
    local who = Gold(Short(t.from))
    if ns.FindSharedStory and ns.FindSharedStory(t.from, t.src) then
        prompt(string.format("%s offers you a bound tale: '%s'.\nYou already have it. Replace your copy or keep both?", who, t.title),
            "Replace", function() Answer(t, true, "replace") end,
            "Keep both", function() Answer(t, true, "both") end,
            "Decline", function() Answer(t, false) end)
    else
        prompt(string.format("%s offers you a bound tale: '%s'. Will you place it on your shelf?", who, t.title),
            "Accept Tome", function() Answer(t, true) end,
            "Decline", function() Answer(t, false) end,
            "Block Scribe", function() ns.BlockSharer(t.from) Answer(t, false) end)
    end
end

local function HeardOffer(from, id, n, sum, proto, src, title)
    local key = from .. "#" .. id
    if inc[key] then return end
    if proto ~= PROTO then Send("N " .. id .. " proto", from) return end
    if Setting() == "FRIENDS" and not ns.IsFriendly(from) then Send("N " .. id .. " friends", from) return end
    n = Num(n, 1, MAX_PIECES)
    if not n or not sum:match("^%x%x%x%x%x%x%x%x$") then Send("N " .. id .. " big", from) return end
    local now = Now()
    if #waiting >= MAX_WAITING then Send("N " .. id .. " busy", from) return end
    if lastOffer[Short(from)] and now - lastOffer[Short(from)] < OFFER_GAP then Send("N " .. id .. " busy", from) return end
    lastOffer[Short(from)] = now
    local t = { key = key, id = id, from = from, n = n, sum = sum:lower(), src = src ~= "-" and Plain(src, 24) or nil,
        title = Plain(title, CAP.title), pieces = {}, got = 0, state = "ASK", last = now, asks = 0 }
    if t.title == "" then t.title = "Story" end
    inc[key] = t
    table.insert(waiting, t)
    Wake()
    AskNext()
end

local DECLINE = { declined = "They said no thanks.", proto = "Their RP Chronicler is a different version. Both of you need the latest.",
    friends = "They take books only from friends, guild and group.", busy = "They are busy with another book. Try again in a minute.", big = "The story is too long to send." }

function ns.ShareHeard(msg, sender)
    if type(msg) ~= "string" or type(sender) ~= "string" or sender == "" then return end
    local kind, id, rest = msg:match("^(%u) (%w+) ?(.*)$")
    if not kind then return end
    -- incoming book (only while sharing is on and the sender isn't blocked)
    if kind == "O" or kind == "D" or kind == "E" then
        if Setting() == "OFF" or ns.ShareBlocked(sender) then return end
        if kind == "O" then
            local n, sum, proto, src, title = rest:match("^(%d+) (%x+) (%w+) (%S+) ?(.*)$")
            if n then HeardOffer(sender, id, n, sum, proto, src, title) end
            return
        end
        local t = inc[sender .. "#" .. id]
        if not t or t.state ~= "RECV" then return end
        if ns.ShareRestricted() then t.last = Now() return end   -- ignored now, asked again later
        t.last = Now()
        if kind == "D" then
            local i, data = rest:match("^(%d+) (.+)$")
            i = Num(i, 1, t.n)
            if i and not t.pieces[i] and #data <= PIECE then
                t.pieces[i] = data
                t.got = t.got + 1
                if t.got == t.n then Finish(t) end
            end
        elseif t.done or t.got == t.n then
            Finish(t)
        else
            Send("M " .. id .. " " .. table.concat(Missing(t), ","), sender)
        end
        return
    end
    -- answers to a book you send
    local t = out[id]
    if not t or Short(t.to) ~= Short(sender) then return end
    t.last = Now()
    if kind == "Y" and t.state == "ASK" then
        t.state, t.queue = "SEND", {}
        for i = 1, #t.pieces do t.queue[i] = i end
        Say(string.format("Sealing the leather cover and dispatching your tome to %s...", Gold(Short(t.to))))
    elseif kind == "N" then
        out[id] = nil
        Say(string.format("%s did not take '%s'. %s", Gold(Short(t.to)), t.title, DECLINE[rest] or ""))
    elseif kind == "M" and t.state ~= "ASK" then
        -- while still sending, the missing pieces join the queue; after the
        -- end, each resend round counts (3 at most)
        if t.state == "WAIT" then
            if t.rounds >= 3 then Fail(t, "Too many pieces were lost on the way.") return end
            t.rounds = t.rounds + 1
        end
        local have = {}
        for _, q in ipairs(t.queue or {}) do have[q] = true end
        t.queue = t.queue or {}
        for i in rest:gmatch("(%d+)") do
            i = Num(i, 1, #t.pieces)
            if i and not have[i] then t.queue[#t.queue + 1] = i; have[i] = true end
        end
        t.state = "SEND"
    elseif kind == "G" then
        out[id] = nil
        Say(string.format("%s received '%s'.", Gold(Short(t.to)), t.title))
        ns.Notify("shareChanged")
    elseif kind == "B" then
        Fail(t, "The book arrived damaged.")
    end
    Sleep()
end

function Tick()
    local now = Now()
    for id, t in pairs(out) do
        if t.state == "SEND" then
            if ns.ShareRestricted() or InInstance() then
                t.last = now          -- paused: the timer waits too
            else
                local i = table.remove(t.queue, 1)
                if i then
                    Send(string.format("D %s %d %s", id, i, t.pieces[i]), t.to)
                    t.last = now
                end
                if #t.queue == 0 then
                    Send("E " .. id, t.to)
                    t.state, t.endAt, t.ends = "WAIT", now, 1
                end
            end
        elseif t.state == "WAIT" and now - (t.endAt or now) > 10 and t.ends < 3 then
            Send("E " .. id, t.to)
            t.endAt, t.ends = now, t.ends + 1
        end
        if out[id] and now - t.last > TIMEOUT then
            if t.state == "ASK" then
                out[id] = nil
                Say(string.format("No answer from %s. They need RP Chronicler 0.7.0 or newer with story sharing on (Options > Privacy), and to be online.", Gold(Short(t.to))))
            else
                Fail(t, "No answer for a minute.")
            end
        end
    end
    for key, t in pairs(inc) do
        if t.state == "RECV" and not t.done and t.got > 0 and now - t.last > 6 and t.asks < 3 and not ns.ShareRestricted() then
            t.asks, t.last = t.asks + 1, now
            Send("M " .. t.id .. " " .. table.concat(Missing(t), ","), t.from)
        end
        if ns.ShareRestricted() then t.last = now end   -- our own lockdown: wait
        -- once pieces flow, the sender may be paused by its own lockdown
        if now - t.last > (t.done and 15 or (t.got > 0 and TIMEOUT * 3) or TIMEOUT) then
            if t.state == "ASK" then
                for i, w in ipairs(waiting) do if w == t then table.remove(waiting, i) break end end
            elseif not t.done then
                Say(string.format("The book from %s stopped arriving and was dropped.", Gold(Short(t.from))))
            end
            inc[key] = nil
        end
    end
    Sleep()
end
ns.ShareTick = function() Tick() end
ns.ShareTransfers = function() return out, inc, waiting end

ns.On({ "PLAYER_LOGIN", "CHAT_MSG_ADDON" }, function(event, prefix, msg, channel, sender)
    if event == "PLAYER_LOGIN" then
        Register()
    elseif prefix == PREFIX and channel == "WHISPER" then
        local me = ns.StripRealm(UnitName and UnitName("player"))
        if me and ns.StripRealm(sender) == me then return end
        ns.ShareHeard(msg, sender)
    end
end)
