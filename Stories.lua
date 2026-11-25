local ADDON_NAME, ns = ...

-- =========================================================
-- Stories (0.6.1, split out of Adventures.lua): story storage
-- (RPChroniclerDB.stories), the Story Book details read from a story,
-- boss icons in the reader and auto-color on import. The story templates
-- the AI follows are in Templates.lua.
-- =========================================================
local BOOK_FIELDS = { "title", "instance", "duration", "zone", "date", "party", "kills", "wipes", "deaths", "chapters",
    "foes", "quests", "levels" }

-- =========================================================
-- Stories (0.5.0): RPChroniclerDB.stories, kept apart from the recordings, so
-- deleting a recording never deletes its story. Each story keeps its own
-- copy of the run's details (title, zone, roster, bosses, shots ...) at
-- its top level, so every helper that reads a run reads a story too.
--   { id, runId, story, book, importedAt, title, zone, kind, ... }
-- =========================================================
local STORY_META = { "title", "zone", "instanceName", "kind", "startDate", "endDate", "startTime", "endTime",
    "participants", "bossKills", "bossInfo", "wipes", "deaths", "foesDefeated", "killCounts", "kills", "shots",
    "places", "levelStart", "levelEnd", "questsDone", "coin", "keyLoot", "highlights", "metCompanions",
    "pvpKills", "pvpDeaths", "skills", "milestones", "lastSeen" }

local function DeepCopy(v, depth)
    if type(v) ~= "table" then return v end
    depth = depth or 0
    if depth > 6 then return nil end
    local t = {}
    for k, x in pairs(v) do t[k] = DeepCopy(x, depth + 1) end
    return t
end

local function CopyRunMeta(st, adv)
    for _, k in ipairs(STORY_META) do
        if adv[k] ~= nil then st[k] = DeepCopy(adv[k]) end
    end
    st.duration = ns.GetRunDuration(adv)
end

local function Stories()
    RPChroniclerDB.stories = type(RPChroniclerDB.stories) == "table" and RPChroniclerDB.stories or {}
    return RPChroniclerDB.stories
end

-- Newest import first
function ns.GetStories()
    if not RPChroniclerDB then return {} end
    local list = {}
    for _, st in ipairs(Stories()) do
        if type(st) == "table" and (st.story or "") ~= "" then table.insert(list, st) end
    end
    table.sort(list, function(x, y) return (x.importedAt or 0) > (y.importedAt or 0) end)
    return list
end

function ns.FindStory(id)
    if not id or not RPChroniclerDB then return nil end
    for _, st in ipairs(Stories()) do
        if st.id == id then return st end
    end
    return nil
end

-- The story written from a run, or nil
function ns.StoryForRun(runId)
    if not runId or not RPChroniclerDB then return nil end
    for _, st in ipairs(Stories()) do
        if st.runId == runId and (st.story or "") ~= "" then return st end
    end
    return nil
end

function ns.RunHasStory(adv)
    return adv and ns.StoryForRun(adv.id) ~= nil or false
end

-- The recording a story came from, if it still exists
function ns.StoryRun(st)
    return st and st.runId and ns.FindAdventure(st.runId) or nil
end

local function NewStoryId()
    return "s" .. tostring(time()) .. "_" .. tostring(math.random(100, 999))
end

local function ApplyBook(st, cleaned)
    local okMeta, meta = pcall(ns.ParseStoryMeta, cleaned)
    if not okMeta or type(meta) ~= "table" then meta = {} end
    local old = type(st.book) == "table" and st.book or {}
    local edited = type(old.edited) == "table" and old.edited or {}
    local book = { edited = edited, importedAt = time() }
    for _, k in ipairs(BOOK_FIELDS) do
        if edited[k] then book[k] = old[k] else book[k] = meta[k] end
    end
    st.book = book
    -- 0.6.1: the "Title:" label is for RP Chronicler; the reader shows the title alone
    if meta.title then st.story = ns.StripTitleLabel(st.story) end
    return meta
end

-- Imports (or re-imports) the story of a run. Returns true and the story id.
function ns.SetAdventureStory(advId, rawStoryText)
    ns.EnsureDB()
    -- Normalizes || -> |, strips code fences and Markdown, maps non-ASCII
    -- glyphs to ASCII, and auto-closes dangling color escapes (see Core.lua)
    local cleaned = ns.CleanStoryHeader(ns.NormalizeStoryText(rawStoryText))
    local adv = ns.FindAdventure(advId)
    if not adv then return false end
    local st = ns.StoryForRun(adv.id)
    if not st then
        st = { id = NewStoryId(), runId = adv.id }
        table.insert(Stories(), 1, st)
    end
    CopyRunMeta(st, adv)
    local ok, colored = pcall(ns.AutoColorStory, cleaned, st)
    if ok and type(colored) == "string" then cleaned = colored; st.autoColored = ns.AUTOCOLOR_VERSION end
    st.story = cleaned
    st.importedAt = time()
    adv.storyId = st.id
    local meta = ApplyBook(st, cleaned)
    ns.Debug("run", string.format("story imported for %s (%d chars, %d chapters)", tostring(meta.title or adv.title), #cleaned, #(meta.chapters or {})))
    return true, st.id
end

-- Re-import onto a story whose recording may be gone
function ns.SetStoryText(storyId, rawStoryText)
    local st = ns.FindStory(storyId)
    if not st then return false end
    local run = ns.StoryRun(st)
    if run then return ns.SetAdventureStory(run.id, rawStoryText) end
    local cleaned = ns.NormalizeStoryText(rawStoryText)
    local ok, colored = pcall(ns.AutoColorStory, cleaned, st)
    if ok and type(colored) == "string" then cleaned = colored; st.autoColored = ns.AUTOCOLOR_VERSION end
    st.story = cleaned
    st.importedAt = time()
    ApplyBook(st, cleaned)
    return true, st.id
end

-- Edit one Story Book field by hand ("" clears it back to the run's data)
function ns.SetBookField(storyId, field, value)
    local st = ns.FindStory(storyId)
    if not st then return false end
    st.book = type(st.book) == "table" and st.book or {}
    st.book.edited = st.book.edited or {}
    if value == nil or value == "" then
        st.book[field] = nil
        st.book.edited[field] = nil
    else
        if field == "kills" or field == "wipes" or field == "deaths" then value = tonumber(value) or value end
        st.book[field] = value
        st.book.edited[field] = true
    end
    return true
end

function ns.DeleteStory(storyId)
    local list = Stories()
    for i = #list, 1, -1 do
        if list[i].id == storyId then
            local run = ns.StoryRun(list[i])
            if run then run.storyId = nil end
            ns.Debug("run", "story deleted: " .. tostring(list[i].title))
            table.remove(list, i)
            return true
        end
    end
    return false
end

-- Old name: removes the story of a run (the recording stays)
function ns.DeleteAdventureStory(advId)
    local st = ns.StoryForRun(advId)
    return st and ns.DeleteStory(st.id) or false
end

-- 0.5.0 migration: stories that lived inside their runs move to
-- RPChroniclerDB.stories with a copy of the run's details
function ns.MigrateStories()
    local list = Stories()
    local moved = 0
    local function Move(adv)
        if type(adv) ~= "table" then return end
        if type(adv.story) == "string" and adv.story ~= "" and not ns.StoryForRun(adv.id) then
            local st = { id = NewStoryId() .. "_" .. moved, runId = adv.id, story = adv.story, book = adv.book,
                importedAt = (type(adv.book) == "table" and adv.book.importedAt) or adv.lastSeen or time() }
            CopyRunMeta(st, adv)
            table.insert(list, st)
            adv.storyId = st.id
            moved = moved + 1
        end
        adv.story = nil
        adv.book = nil
    end
    for _, adv in ipairs(RPChroniclerDB.adventures or {}) do Move(adv) end
    Move(RPChroniclerDB.activeRun)
    if moved > 0 then ns.Debug("info", "moved " .. moved .. " stories into the Story Book") end
    return moved
end

-- =========================================================
-- Story Book: metadata parsed from an imported story
-- The templates ask the AI for:
--   line 1: "Title: <story title>" (0.6.1: the AI names the story; the
--           addon reads this line and never guesses a title from prose)
--   line 2: <dungeon or region> | <duration> | <zone>
--   line 3 (optional): Date: ... | Party: ...
--   chapter headers "Chapter N: ..." and a footer line
--   "Bosses: N | Wipes: N | Deaths: N"
-- Anything missing falls back to the run's own data.
-- =========================================================
local function Trim(s) return (s or ""):match("^%s*(.-)%s*$") end

-- 0.6.0: the story's own line 2 sometimes repeats the place
-- ("Zephras Isle - Valanaar | 17m 18s | Zephras Isle - Valanaar"). Drop the
-- last part when the first part already names it. Colors are kept.
function ns.CleanStoryHeader(text)
    if type(text) ~= "string" or text == "" then return text end
    local lines, seen, idx = {}, 0, nil
    for line in (text .. "\n"):gmatch("([^\n]*)\n") do
        table.insert(lines, line)
        if not idx and Trim(ns.StripColors(line)) ~= "" then
            seen = seen + 1
            if seen == 2 then idx = #lines end
        end
    end
    if not idx then return text end
    local line = lines[idx]
    local s1, e1 = line:find("%s+|%s+")
    if not s1 then return text end
    local s2, e2 = line:find("%s+|%s+", e1 + 1)
    if not s2 or line:find("%s+|%s+", e2 + 1) then return text end
    local last, tail = line:sub(e2 + 1), ""
    while last:find("|r%s*$") do
        last = last:gsub("|r%s*$", "", 1)
        tail = tail .. "|r"
    end
    local first = Trim(ns.StripColors(line:sub(1, s1 - 1))):lower()
    last = Trim(ns.StripColors(last)):lower()
    if last == "" or not first:find(last, 1, true) then return text end
    lines[idx] = line:sub(1, s2 - 1) .. tail
    return table.concat(lines, "\n")
end

-- Drops the "Title: " label from the first "Title:" line (colors kept)
function ns.StripTitleLabel(text)
    if type(text) ~= "string" then return text end
    local out, n, done = {}, 0, false
    for line in (text .. "\n"):gmatch("([^\n]*)\n") do
        if not done and n < 3 and Trim(ns.StripColors(line)) ~= "" then
            n = n + 1
            if Trim(ns.StripColors(line)):gsub("^#+%s*", ""):match("^[Tt]itle:") then
                line = line:gsub("[Tt]itle:%s*", "", 1)
                done = true
            end
        end
        table.insert(out, line)
    end
    if out[#out] == "" and text:sub(-1) ~= "\n" then table.remove(out) end
    return table.concat(out, "\n")
end

function ns.ParseStoryMeta(text)
    local meta = { chapters = {} }
    local plain = ns.StripColors(ns.NormalizeStoryText(text or ""))
    plain = plain:gsub("|T.-|t", ""):gsub("|A.-|a", "")
    local lines = {}
    for line in (plain .. "\n"):gmatch("([^\n]*)\n") do
        line = Trim(line)
        if line ~= "" then table.insert(lines, line) end
    end
    if #lines == 0 then return meta end
    -- 0.6.1: the title is the "Title:" line in the first three lines. A
    -- story without one keeps the run's title (the player can rename it).
    local titleAt
    for i = 1, math.min(3, #lines) do
        local t = lines[i]:gsub("^#+%s*", ""):match("^[Tt]itle:%s*(.-)%s*$")
        if t and t ~= "" then meta.title = t:sub(1, 120); titleAt = i; break end
    end
    local second = lines[(titleAt or 1) + 1] or ""
    if second:find("|", 1, true) then
        local parts = {}
        for piece in (second .. "|"):gmatch("([^|]*)|") do table.insert(parts, Trim(piece)) end
        meta.instance = parts[1] ~= "" and parts[1] or nil
        meta.duration = parts[2] ~= "" and parts[2] or nil
        meta.zone = parts[3] ~= "" and parts[3] or nil
        -- 0.5.0: "Zephras Isle | 29m | Zephras Isle" - the zone said twice
        if meta.zone and meta.instance and meta.instance:lower():find(meta.zone:lower(), 1, true) then meta.zone = nil end
    end
    for i = 2, math.min(#lines, 6) do
        local d = lines[i]:match("[Dd]ate:%s*([^|]+)")
        if d then meta.date = Trim(d) end
        local party = lines[i]:match("[Pp]arty:%s*([^|]+)")
        if party then meta.party = Trim(party) end
    end
    for _, line in ipairs(lines) do
        if line:match("^[Cc]hapter%s+[%w]+") then
            table.insert(meta.chapters, line)
        end
    end
    for i = #lines, math.max(1, #lines - 4), -1 do
        local line = lines[i]:lower()
        local b = line:match("boss[%w%s]-:%s*(%d+)") or line:match("bosses[%w%s]-:%s*(%d+)")
        local w = line:match("wipes?:%s*(%d+)")
        local de = line:match("deaths?:%s*(%d+)")
        local fo = line:match("foes[%w%s]-:%s*(%d+)")
        local qu = line:match("quests?[%w%s]-:%s*(%d+)")
        local lv = line:match("levels?[%w%s]-:%s*([%d%s%->]+%d)")
        if b or w or de or fo or qu or lv then
            meta.kills = meta.kills or tonumber(b)
            meta.wipes = meta.wipes or tonumber(w)
            meta.deaths = meta.deaths or tonumber(de)
            meta.foes = meta.foes or tonumber(fo)
            meta.quests = meta.quests or tonumber(qu)
            meta.levels = meta.levels or (lv and Trim(lv))
        end
    end
    return meta
end

-- Book fields with fallbacks to the run's data. Edited fields win.
function ns.GetBookInfo(adv)
    local b = (adv and type(adv.book) == "table") and adv.book or {}
    local partyNames = {}
    for _, p in ipairs((adv and adv.participants) or {}) do table.insert(partyNames, p.name) end
    local info = {
        title = b.title or (adv and adv.title) or "Untitled Story",
        instance = b.instance or (adv and (adv.instanceName or adv.zone)) or "",
        zone = b.zone or (adv and adv.zone) or "",
        duration = b.duration or ns.FormatDuration(ns.GetRunDuration(adv)),
        date = b.date or (adv and adv.startDate) or "",
        party = b.party or table.concat(partyNames, ", "),
        kills = b.kills or #((adv and adv.bossKills) or {}),
        wipes = b.wipes or (adv and adv.wipes) or 0,
        deaths = b.deaths or (adv and adv.deaths) or 0,
        foes = b.foes or (adv and adv.foesDefeated) or 0,
        quests = b.quests or (adv and adv.questsDone) or 0,
        levels = b.levels or (adv and ns.GetRunLevels(adv)) or "",
        chapters = b.chapters or {},
        kind = (adv and adv.kind) or "world",
    }
    if info.zone ~= "" and info.zone:lower() == (info.instance or ""):lower() then info.zone = "" end
    info.name = info.title
    return info
end

-- 0.5.0: "[Shot 3]" markers place screenshots in the exported page; the
-- reader and the plain text leave them out
function ns.StripShotMarkers(text)
    text = (text or ""):gsub("%s*%[[Ss]hot%s*%d+%]", "")
    return text
end

-- The stats line of a story, by run type, with zeros hidden
function ns.GetBookStats(info)
    local bits = {}
    local function Add(label, v, hex)
        if v and v ~= 0 and v ~= "" and v ~= "0" then table.insert(bits, "|cffb0a080" .. label .. ":|r |cff" .. hex .. tostring(v) .. "|r") end
    end
    if info.kind == "world" then
        Add("Foes", info.foes, "5cb85c")
        Add("Quests", info.quests, "ffd100")
        Add("Levels", info.levels, "69ccf0")
        Add("Deaths", info.deaths, "ffb74d")
    else
        Add("Bosses", info.kills, "5cb85c")
        Add("Wipes", info.wipes, "ff6b6b")
        Add("Deaths", info.deaths, "ffb74d")
    end
    Add("Chapters", #(info.chapters or {}), "f5e6c8")
    return table.concat(bits, "   ")
end

-- Story as clean plain text (no color codes or icons), for Discord or forums
function ns.GetStoryPlainText(adv)
    if not adv or not adv.story or adv.story == "" then return "" end
    local text = ns.StripShotMarkers(ns.NormalizeStoryText(adv.story))
    text = text:gsub("|T.-|t", ""):gsub("|A.-|a", ""):gsub("|H.-|h(.-)|h", "%1")
    text = ns.StripColors(text):gsub("|n", "\n"):gsub("||", "|")
    text = text:gsub("\n\n\n+", "\n\n")
    return Trim(text) .. "\n\n(Chronicle recorded with RP Chronicler)"
end

-- =========================================================
-- Boss icons in the Story reader: a skull, gold dragon or silver dragon
-- before every recorded boss name (from the classification read at engage).
-- Old stories also get the old orange boss color turned crimson.
-- =========================================================
local BOSS_ICON_TEX = {
    skull = "|TInterface\\TargetingFrame\\UI-TargetingFrame-Skull:14:14:0:-1|t",
    elite = "|TInterface\\Tooltips\\EliteNameplateIcon:14:14:0:-1|t",
    rare = "|TInterface\\Tooltips\\EliteNameplateIcon:14:14:0:-1:64:64:0:64:0:64:200:200:215|t",
}
local BOSS_ICON_ATLAS = { elite = "nameplates-icon-elite-gold", rare = "nameplates-icon-elite-silver" }

local function BossIcon(kind)
    local atlas = BOSS_ICON_ATLAS[kind]
    if atlas and C_Texture and C_Texture.GetAtlasInfo then
        local ok, info = pcall(C_Texture.GetAtlasInfo, atlas)
        if ok and info then return "|A:" .. atlas .. ":14:14:0:-1|a" end
    end
    return BOSS_ICON_TEX[kind] or BOSS_ICON_TEX.skull
end
ns.BossIcon = BossIcon

-- Boss name -> "skull" / "elite" / "rare" for a run
function ns.GetRunBossKinds(adv)
    local kinds = {}
    if not adv then return kinds end
    for _, b in ipairs(adv.bossKills or {}) do kinds[b] = "skull" end
    for name, info in pairs(adv.bossInfo or {}) do
        if type(info) == "table" then kinds[name] = info.kind or "skull" end
    end
    return kinds
end

local function EscapePattern(s)
    return (s:gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%0"))
end

function ns.DecorateStoryBosses(text, adv)
    if not text or text == "" then return text end
    text = text:gsub("|c[fF][fF][fF][fF]8000", "|cffdc143c")
    local kinds = ns.GetRunBossKinds(adv)
    local names = {}
    for name in pairs(kinds) do
        if #name >= 3 then table.insert(names, name) end
    end
    if #names == 0 then return text end
    table.sort(names, function(a, b) return #a > #b end)

    local icons = {}
    local function DecoratePlain(seg)
        -- Longest names first, through placeholders, so "Arugal" never
        -- re-matches inside "Arugal's Voidwalker"
        for idx, name in ipairs(names) do
            seg = seg:gsub("%f[%w]" .. EscapePattern(name) .. "%f[^%w]", function()
                icons[idx] = icons[idx] or (BossIcon(kinds[name]) .. " " .. name)
                return "\001" .. idx .. "\002"
            end)
        end
        return (seg:gsub("\001(%d+)\002", function(i) return icons[tonumber(i)] end))
    end

    -- Walk the text, decorating only the plain parts between escape codes
    local out, i, n, segStart = {}, 1, #text, 1
    while i <= n do
        local j
        if text:byte(i) == 124 then -- "|"
            local nx = text:sub(i + 1, i + 1)
            if nx == "c" and text:sub(i + 2, i + 9):match("^%x%x%x%x%x%x%x%x$") then
                j = i + 9
            elseif nx == "r" then
                j = i + 1
            elseif nx == "T" or nx == "A" or nx == "H" then
                local term = (nx == "T") and "|t" or ((nx == "A") and "|a" or "|h")
                local e = text:find(term, i + 2, true)
                j = e and (e + 1) or n
            end
        end
        if j then
            table.insert(out, DecoratePlain(text:sub(segStart, i - 1)))
            table.insert(out, text:sub(i, j))
            i = j + 1
            segStart = i
        else
            i = i + 1
        end
    end
    table.insert(out, DecoratePlain(text:sub(segStart)))
    return table.concat(out)
end

-- =========================================================
-- Auto-color on import (0.5.0): the AI often colors a name only the first
-- time. RP Chronicler colors every later plain mention of the names it can verify
-- from the run: party (class colors), pets, places (teal), foes and bosses
-- (crimson), NPCs (pale yellow) and items (their quality color). Only
-- plain prose is touched; text the AI already colored is left alone.
-- Options > Stories & Export can turn it off.
-- =========================================================
-- Bump when the coloring improves: stories colored by an older version
-- are colored again once when the Story Book shows them.
ns.AUTOCOLOR_VERSION = 2
local PROSE_HEX = { eceff1 = true, e0e0e0 = true, f5e6c8 = true, d7c4a3 = true }

-- 0.5.2: any light, nearly gray color counts as prose (the AI often wraps
-- whole paragraphs in white or cream), so names inside it get colored too.
-- Priest gray C0C0C0 and darker grays stay names.
local function IsProseHex(hex)
    if not hex then return true end
    if PROSE_HEX[hex] then return true end
    local r, g, b = tonumber(hex:sub(1, 2), 16), tonumber(hex:sub(3, 4), 16), tonumber(hex:sub(5, 6), 16)
    if not (r and g and b) then return false end
    local lo, hi = math.min(r, g, b), math.max(r, g, b)
    return lo >= 0xD0 and (hi - lo) <= 0x30
end

-- NPC names from a run's timeline: speakers, quest givers and quest text.
-- Cached on the story, so they survive deleting the recording.
local function StoryNpcNames(st)
    local run = ns.StoryRun(st)
    if run and type(run.fullTimeline) == "table" then
        local seen, list = {}, {}
        for _, line in ipairs(run.fullTimeline) do
            local plain = ns.StripColors(type(line) == "table" and (line.line or "") or tostring(line or ""))
            local npc = plain:match("%[NPC[^%]]*%]%s*([^:]+):") or plain:match("%[QUEST TEXT%]%s*([^:]+):")
                or plain:match("%[QUEST%] Accepted: .- from (.+)$") or plain:match("%[QUEST%] Completed: .- for (.+)$")
            if npc then
                npc = npc:match("^%s*(.-)%s*$")
                if npc ~= "" and npc ~= "Quest giver" and not seen[npc] then
                    seen[npc] = true
                    table.insert(list, npc)
                end
            end
        end
        st.npcNames = list
    end
    return type(st.npcNames) == "table" and st.npcNames or {}
end
local PET_HEX, PLACE_HEX, FOE_HEX, NPC_HEX = "80cbc4", "40e0d0", "dc143c", "fff0a0"

local function StoryNameColors(st)
    local map = {}
    local function Put(name, hex, force)
        name = ns.SafeStr(name)
        if not name then return end
        name = name:match("^%s*(.-)%s*$")
        if #name < 3 or not hex then return end
        if force or not map[name] then map[name] = hex end
    end
    -- Places first, so a person or foe with the same name wins
    local function Place(where)
        where = ns.SafeStr(where)
        if not where then return end
        for piece in (where .. " - "):gmatch("(.-) %- ") do Put(piece, PLACE_HEX) end
    end
    Place(st.zone)
    Place(st.instanceName)
    for _, p in ipairs(st.places or {}) do Place(p) end
    for name in pairs(st.killCounts or {}) do Put(name, FOE_HEX, true) end
    for _, name in ipairs(st.kills or {}) do Put(name, FOE_HEX, true) end
    for _, name in ipairs(st.bossKills or {}) do Put(name, FOE_HEX, true) end
    for name, m in pairs(st.metCompanions or {}) do
        if type(m) == "table" and m.kind == "npc" then Put(name, NPC_HEX, true) end
    end
    for _, npc in ipairs(StoryNpcNames(st)) do Put(npc, NPC_HEX) end
    for _, item in ipairs(st.keyLoot or {}) do
        if type(item) == "table" and item.colored then
            local hex = item.colored:match("|c%x%x(%x%x%x%x%x%x)")
            local name = ns.StripColors(item.colored):gsub("|H.-|h", ""):gsub("|h", ""):match("%[(.-)%]") or item.plain
            if hex and name then Put(name, hex:lower(), true) end
        end
    end
    -- People last: they always win. First names too, when only one has it.
    local firstCount = {}
    for _, p in ipairs(st.participants or {}) do
        local first = ns.SplitFullName(p.name or "")
        if first ~= "" then firstCount[first] = (firstCount[first] or 0) + 1 end
    end
    for _, p in ipairs(st.participants or {}) do
        local hex = ns.CLASS_COLORS[ns.ClassToken(p.classFile) or ns.ClassToken(p.class) or ""]
        if hex then
            Put(p.name, hex, true)
            local first = ns.SplitFullName(p.name or "")
            if first ~= "" and firstCount[first] == 1 then Put(first, hex, true) end
        end
        if p.pet then
            local petName = p.pet:match("^(.-)%s*%(") or p.pet
            Put(petName, PET_HEX, true)
            -- the species too ("her Crab"); capitalized only, so "crab meat" stays plain
            local species = p.pet:match("%(([^,%)]+)")
            if species and species:match("^%u") then Put(species, PET_HEX) end
        end
    end
    return map
end

function ns.AutoColorStory(text, st)
    if type(text) ~= "string" or text == "" or type(st) ~= "table" then return text end
    local map = StoryNameColors(st)
    -- 0.5.2: a name the AI colored once is colored everywhere, in that color
    for hex, inner in text:gmatch("|c%x%x(%x%x%x%x%x%x)([^|]-)|r") do
        hex = hex:lower()
        inner = inner:match("^%s*(.-)%s*$")
        if not IsProseHex(hex) and hex ~= "ffd100" and #inner >= 3 and #inner <= 40 and not inner:find("[%d:%.,!?\"]")
            and inner:match("^%u") and select(2, inner:gsub("%S+", "")) <= 4 and not map[inner] then
            map[inner] = hex
        end
    end
    -- A party member's first name followed by a surname ("Aloria Sunwhisper")
    for _, p in ipairs(st.participants or {}) do
        local first = ns.SplitFullName(p.name or "")
        local hex = first ~= "" and map[first]
        if hex then
            for full in text:gmatch("%f[%w](" .. EscapePattern(first) .. " %u%l+)%f[^%w]") do
                if not map[full] then map[full] = hex end
            end
        end
    end
    local names = {}
    for name in pairs(map) do table.insert(names, name) end
    if #names == 0 then return text end
    table.sort(names, function(a, b) return #a > #b end)

    local function ColorPlain(seg, cur)
        if not IsProseHex(cur) then return seg end
        local held = {}
        for idx, name in ipairs(names) do
            seg = seg:gsub("%f[%w]" .. EscapePattern(name) .. "%f[^%w]", function()
                held[idx] = "|cff" .. map[name] .. name .. "|r" .. (cur and ("|cff" .. cur) or "")
                return "\001" .. idx .. "\002"
            end)
        end
        return (seg:gsub("\001(%d+)\002", function(i) return held[tonumber(i)] end))
    end

    local out, i, n, segStart, cur = {}, 1, #text, 1, nil
    while i <= n do
        local j, newCur, isColor
        if text:byte(i) == 124 then -- "|"
            local nx = text:sub(i + 1, i + 1)
            if nx == "c" and text:sub(i + 2, i + 9):match("^%x%x%x%x%x%x%x%x$") then
                j, newCur, isColor = i + 9, text:sub(i + 4, i + 9):lower(), true
            elseif nx == "r" then
                j, isColor = i + 1, true
            elseif nx == "T" or nx == "A" or nx == "H" then
                local term = (nx == "T") and "|t" or ((nx == "A") and "|a" or "|h")
                local e = text:find(term, i + 2, true)
                j = e and (e + 1) or n
                if nx == "H" then
                    -- a link: skip through its visible text and closing |h
                    local e2 = text:find("|h", (e or i) + 2, true)
                    j = e2 and (e2 + 1) or j
                end
            end
        end
        if j then
            table.insert(out, ColorPlain(text:sub(segStart, i - 1), cur))
            table.insert(out, text:sub(i, j))
            if isColor then cur = newCur end
            i = j + 1
            segStart = i
        else
            i = i + 1
        end
    end
    table.insert(out, ColorPlain(text:sub(segStart), cur))
    return table.concat(out)
end

