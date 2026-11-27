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
local STORY_META = { "code", "title", "zone", "instanceName", "kind", "startDate", "endDate", "startTime", "endTime",
    "participants", "bossKills", "bossInfo", "wipes", "deaths", "foesDefeated", "killCounts", "kills", "shots",
    "places", "levelStart", "levelEnd", "questsDone", "coin", "keyLoot", "highlights", "metCompanions",
    "pvpKills", "pvpDeaths", "skills", "milestones", "lastSeen",
    -- 0.6.3: the cover (who and what they wore), name fixes, version stamp
    "char", "gear", "fixes", "addonVersion", "clientBuild",
    -- 0.6.4: the story scene (dungeon art)
    "ejInstance" }

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
    -- 0.6.3: the story's copy of the run reads the fixed names
    if ns.FixRunCopy then pcall(ns.FixRunCopy, st) end
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
    local cleaned = ns.CleanStoryHeader(ns.StripRunIdLine(ns.NormalizeStoryText(rawStoryText)))
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
    st.quick = nil   -- 0.6.4: a story from an AI replaces a Quick Chronicle
    st.importedAt = time()
    st.importedWith = ns.VERSION
    adv.storyId = st.id
    local meta = ApplyBook(st, cleaned)
    ns.Debug("run", string.format("story imported for %s (%d chars, %d chapters)", tostring(meta.title or adv.title), #cleaned, #(meta.chapters or {})))
    return true, st.id
end

-- =========================================================
-- Run ID in the story (0.6.3): the AI ends the story with "Run ID: X".
-- Import links the story by it; the line itself is not kept in the text.
-- =========================================================
function ns.ReadStoryRunCode(text)
    local plain = ns.StripColors(tostring(text or "")):gsub("||", "|")
    local code
    for c in plain:gmatch("[Rr][Uu][Nn]%s*[Ii][Dd]%s*:%s*%[?([%w]+)") do code = c end
    return code and code:upper() or nil
end

function ns.StripRunIdLine(text)
    if type(text) ~= "string" then return text end
    local out = {}
    for line in (text .. "\n"):gmatch("([^\n]*)\n") do
        if not ns.StripColors(line):match("^%s*[Rr][Uu][Nn]%s*[Ii][Dd]%s*:") then table.insert(out, line) end
    end
    while #out > 0 and ns.StripColors(out[#out]):match("^%s*$") do table.remove(out) end
    return table.concat(out, "\n")
end

-- The story already saved with this Run ID (its recording may be gone)
local function StoryByCode(code)
    if not code then return nil end
    for _, st in ipairs(Stories()) do
        if (st.story or "") ~= "" and ns.RunCode(st) == code then return st end
    end
    return nil
end

-- One way in for every import. The recording is found from the story's
-- Run ID, else the run the player picked (advId); with neither, the story
-- is kept on its own (no recording needed). storyId: a story to replace.
-- Returns ok, storyId, linked (the run it was linked to, or nil).
function ns.ImportStory(rawStoryText, advId, storyId)
    ns.EnsureDB()
    if type(rawStoryText) ~= "string" or rawStoryText:match("^%s*$") then return false end
    local code = ns.ReadStoryRunCode(ns.NormalizeStoryText(rawStoryText))
    local target = storyId and ns.FindStory(storyId) or nil
    local adv = (target and ns.StoryRun(target)) or (advId and ns.FindAdventure(advId))
        or (code and ns.FindAdventureByCode(code)) or nil
    if adv then
        local ok, id = ns.SetAdventureStory(adv.id, rawStoryText)
        return ok, id, ok and adv or nil
    end
    -- 0.6.3: no Run ID (older template): the run that started at the
    -- story's "Date:" (the header copies it from the Full Log)
    if not code and not target then
        adv = ns.FindAdventureByDate(ns.ParseStoryMeta(ns.NormalizeStoryText(rawStoryText)).date)
        if adv then
            local ok, id = ns.SetAdventureStory(adv.id, rawStoryText)
            return ok, id, ok and adv or nil
        end
    end
    target = target or StoryByCode(code)
    if target then
        local ok, id = ns.SetStoryText(target.id, rawStoryText)
        return ok, id, nil
    end
    -- Unlinked: a story with no recording behind it
    local st = { id = NewStoryId(), code = code }
    table.insert(Stories(), 1, st)
    local cleaned = ns.CleanStoryHeader(ns.StripRunIdLine(ns.NormalizeStoryText(rawStoryText)))
    local ok, colored = pcall(ns.AutoColorStory, cleaned, st)
    if ok and type(colored) == "string" then cleaned = colored; st.autoColored = ns.AUTOCOLOR_VERSION end
    st.story = cleaned
    st.importedAt = time()
    st.importedWith = ns.VERSION
    local meta = ApplyBook(st, cleaned)
    st.title = meta.title or "Story"
    st.zone = meta.zone or meta.instance
    st.startDate = meta.date
    ns.Debug("run", string.format("story imported without a recording (%d chars)", #cleaned))
    return true, st.id, nil
end

-- The one run (live or saved) that started at this "YYYY-MM-DD HH:MM", or nil
function ns.FindAdventureByDate(stamp)
    stamp = type(stamp) == "string" and stamp:match("(%d%d%d%d%-%d%d%-%d%d %d%d:%d%d)") or nil
    if not stamp then return nil end
    local found
    local function Check(adv)
        if type(adv) == "table" and adv.startDate == stamp then
            if found then found = false else found = found == nil and adv or found end
        end
    end
    Check(ns.GetActiveAdventure and ns.GetActiveAdventure())
    for _, adv in ipairs((RPChroniclerDB and RPChroniclerDB.adventures) or {}) do Check(adv) end
    return found or nil
end

-- 0.6.3: stories imported unlinked (no Run ID, older template) get their
-- title from the first line and their recording from the header date.
-- Runs at login; a story already linked or renamed by hand is left alone.
function ns.RelinkStories()
    for _, st in ipairs(Stories()) do
        if type(st) == "table" and (st.story or "") ~= "" then
            local book = type(st.book) == "table" and st.book or nil
            local okMeta, meta = pcall(ns.ParseStoryMeta, st.story)
            meta = okMeta and meta or {}
            if book and not book.title and not (book.edited or {}).title and meta.title then
                book.title = meta.title
            end
            if not st.runId then
                local adv = ns.FindAdventureByDate(meta.date)
                if adv and not ns.StoryForRun(adv.id) then
                    CopyRunMeta(st, adv)
                    st.runId = adv.id
                    adv.storyId = st.id
                end
            end
        end
    end
end

-- Re-import onto a story whose recording may be gone
function ns.SetStoryText(storyId, rawStoryText)
    local st = ns.FindStory(storyId)
    if not st then return false end
    local run = ns.StoryRun(st)
    if run then return ns.SetAdventureStory(run.id, rawStoryText) end
    local cleaned = ns.StripRunIdLine(ns.NormalizeStoryText(rawStoryText))
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
            -- 0.6.6: it leaves its chronicle too
            if ns.RemoveStoryFromChronicle then ns.RemoveStoryFromChronicle(storyId) end
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
            local plain = Trim(ns.StripColors(line)):gsub("^#+%s*", "")
            if plain:match("^[Tt]itle:") then
                line = line:gsub("[Tt]itle:%s*", "", 1)
                done = true
            elseif plain:match("^@[Tt]itle") then
                line = line:gsub("@[Tt]itle:?%s*", "", 1)
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
    -- 0.6.3: a story from an older template has no "Title:" label; when
    -- line 2 is the "<place> | <duration> | <zone>" header, line 1 is the title
    if not titleAt and #lines >= 2 and lines[2]:find("|", 1, true)
        and not lines[1]:find("|", 1, true) and not lines[1]:match("^[Cc]hapter%s") and #lines[1] <= 120 then
        meta.title = lines[1]:gsub("^#+%s*", ""):gsub("^@[Tt]itle:?%s*", "")
        titleAt = 1
    end
    -- 0.6.4: "@title ..." or a heading line ("# ...", or a short first line
    -- that isn't a sentence or a chapter) is the title too, so a story
    -- whose AI dropped the "Title:" label never takes the zone's name
    if not titleAt then
        local first = lines[1]
        local t = first:match("^@[Tt]itle:?%s*(.-)%s*$") or first:match("^#+%s*(.-)%s*$")
        if not t and #first <= 100 and not first:find("|", 1, true) and not first:match("^[Cc]hapter%s")
            and not first:match("[%.!?\"]$") and not first:lower():match("^%a+ ?%a*:%s") then
            t = first
        end
        if t and t ~= "" then meta.title = t:sub(1, 120); titleAt = 1 end
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
    -- 0.6.5: each member once ("Morai" and "Morai Galeclaw" are one)
    local partyNames = {}
    local roster = ns.MergedRoster and ns.MergedRoster((adv and adv.participants) or {}) or ((adv and adv.participants) or {})
    for _, p in ipairs(roster) do table.insert(partyNames, p.name) end
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
    -- 0.6.5: a dungeon or raid saved before the instance name was
    -- recorded was named after the city at its entrance (Orgrimmar): its
    -- first boss tells the real place (Ragefire Chasm)
    if adv and info.kind ~= "world" and (info.instance == "" or info.instance == adv.zone) then
        local real
        for i, boss in ipairs(type(adv.bossKills) == "table" and adv.bossKills or {}) do
            if real or i > 4 or not ns.JournalInstanceOfBoss then break end
            real = ns.JournalInstanceOfBoss(boss)
        end
        if real and real ~= "" then
            if info.zone == "" then info.zone = info.instance end
            info.instance = real
        end
    end
    -- an old book's party line kept the duplicates: merge it the same way
    -- (a short name goes when exactly one full name starts with it)
    if b.party then
        local names, firsts = {}, {}
        for n in tostring(b.party):gmatch("[^,]+") do
            n = Trim(n)
            if n ~= "" then table.insert(names, n) end
        end
        for _, n in ipairs(names) do
            local f = n:match("^(%S+)%s+%S")
            if f then firsts[f] = (firsts[f] or 0) + 1 end
        end
        local keep, seen = {}, {}
        for _, n in ipairs(names) do
            if not seen[n] and not (not n:find("%s") and firsts[n] == 1) then table.insert(keep, n) end
            seen[n] = true
        end
        info.party = table.concat(keep, ", ")
    end
    if info.zone ~= "" and info.zone:lower() == (info.instance or ""):lower() then info.zone = "" end
    info.name = info.title
    return info
end

-- 0.5.0: "[Shot 3]" markers place screenshots in the exported page; the
-- reader and the plain text leave them out
function ns.StripShotMarkers(text)
    -- [Shot 3] (before 0.6.3) and [Shot TPX8OK-3]
    text = (text or ""):gsub("%s*%[[Ss][Hh][Oo][Tt]%s*[%w]*%-?%d+%]", "")
    return text
end

-- 0.6.2: "Copy for viewer". The game writes SavedVariables only at logout,
-- so a story imported this session isn't on disk yet. This text carries it
-- to StoryViewer.html by copy and paste: "@key value" lines, then "@story"
-- and the story itself (colors and [Shot N] markers kept).
local function OneLine(v)
    return (tostring(v or ""):gsub("[\r\n]+", " "))
end

function ns.BuildViewerText(st)
    if type(st) ~= "table" or not st.story then return "" end
    local info = ns.GetBookInfo(st)
    local out = { "RP Chronicler story for StoryViewer.html (paste it there)" }
    local function Put(key, v)
        if v ~= nil and v ~= "" then table.insert(out, "@" .. key .. " " .. OneLine(v)) end
    end
    Put("title", info.name)
    Put("zone", info.instance ~= "" and info.instance or info.zone)
    Put("date", info.date)
    Put("start", st.startTime and math.floor(st.startTime))
    local endT = st.endTime
    if not endT and st.startTime and (tonumber(st.duration) or 0) > 0 then endT = st.startTime + st.duration end
    Put("end", endT and math.floor(endT))
    Put("duration", tonumber(st.duration) and math.floor(st.duration))
    -- 0.6.3: the Run ID, and each shot as "<ID> <time> <file name> <caption>"
    Put("run", ns.RunCode(st))
    Put("version", st.importedWith or st.addonVersion)
    for i, sh in ipairs(st.shots or {}) do
        if type(sh) == "table" and sh.at then
            local file = sh.file or ns.ShotFileStem(sh.at) or "-"
            Put("shot", ns.ShotId(st, sh, i) .. " " .. math.floor(sh.at) .. " " .. file .. " " .. OneLine(sh.description))
        end
    end
    for name, kind in pairs(ns.GetRunBossKinds(st)) do Put("boss", kind .. " " .. name) end
    -- 0.6.4: items as "<quality> <class> <subclass> <name>", for colors and icons
    for name, it in pairs(ns.RunItems(st)) do
        Put("item", (it.q or 1) .. " " .. (it.cls or -1) .. " " .. (it.sub or -1) .. " " .. name)
    end
    -- 0.6.3: the run's key moments for the viewer's timeline
    local run = ns.StoryRun(st)
    for _, line in ipairs(ns.TimelineMarks(run)) do Put("mark", line) end
    table.insert(out, "@story")
    table.insert(out, (tostring(st.story):gsub("||", "|")))
    -- Pipes doubled, so the copy box shows the color codes as text and the
    -- clipboard keeps them (the viewer turns || back into |)
    return (table.concat(out, "\n"):gsub("|", "||"))
end

-- 0.6.3: StoryViewer.html's address, to paste into a browser. An addon
-- can't see where the game is installed, so RP Chronicler never guesses:
-- StoryViewer.html shows its own address with a Copy button, the player
-- pastes it into the Viewer path box once, and it is kept from then on.
-- A Windows path (E:\World of Warcraft\...) is turned into the
-- browser-ready form ("file:///E:/World%20of%20Warcraft/...").
-- 0.6.4: the same page, hosted on GitHub Pages for players who'd rather
-- not look for the addon folder. It runs only in the browser, reads only
-- the files the player picks and uploads nothing (its CSP blocks every
-- network request).
ns.HOSTED_VIEWER_URL = "https://azaxyno.github.io/RPChronicler/StoryViewer.html"
ns.VIEWER_PATH_EXAMPLE = "file:///C:/Program%20Files%20(x86)/World%20of%20Warcraft/_forever_/Interface/AddOns/RPChronicler/StoryViewer.html"
function ns.ViewerUrl(path)
    path = tostring(path or ""):gsub("[\r\n]", ""):match("^%s*(.-)%s*$")
    if path == "" then return "" end
    if path:match("^%a:[\\/]") then
        path = "file:///" .. path:gsub("\\", "/")
    elseif path:match("^\\\\") then
        path = "file:" .. path:gsub("\\", "/")
    end
    if path:match("^file:") then path = path:gsub(" ", "%%20") end
    return path
end
-- The saved address, or "" when the player hasn't pasted one yet
function ns.StoryViewerPath()
    local p = ns.Get("viewerPath")
    return (type(p) == "string" and p:match("%S")) and ns.ViewerUrl(p) or ""
end
function ns.SetStoryViewerPath(path)
    return ns.Set("viewerPath", ns.ViewerUrl(path))
end

-- 0.6.3: the key moments of a run (bosses, wipes, deaths, fights, shots,
-- levels, quests, places, notes) as "HH:MM:SS [TAG] text" lines, for the
-- Story Viewer's timeline. At most 300.
local MARK_TAGS = { "BOSS ENGAGED", "BOSS KILL", "BOSS RESET", "WIPE", "DEATH", "FIGHT", "KILL", "SHOT", "LEVEL",
    "QUEST", "PLACE", "NOTE", "HIGHLIGHT", "MILESTONE", "LOOT" }
function ns.TimelineMarks(run)
    local out = {}
    if type(run) ~= "table" then return out end
    for _, line in ipairs(run.fullTimeline or {}) do
        local stamp, tag = tostring(line):match("^%[(%d%d:%d%d:%d%d)%]%s*%[([%u ]+)")
        if stamp and tag then
            for _, t in ipairs(MARK_TAGS) do
                if tag == t or tag:sub(1, #t + 1) == t .. " " then
                    local text = ns.ApplyRunFixes(run, ns.StripColors(tostring(line):sub(12)))
                    table.insert(out, stamp .. " " .. text:sub(1, 160))
                    break
                end
            end
        end
        if #out >= 300 then break end
    end
    return out
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

-- =========================================================
-- 0.6.4: items in stories. Every item the run looted or that you wore
-- shows in the reader with its icon and its quality color (gray, white,
-- green, blue, purple, orange), found by its name, so an item never looks
-- like a name or a place. The AI only has to write the name as the log
-- does.
-- =========================================================
ns.QUALITY_HEX = { [0] = "9d9d9d", [1] = "ffffff", [2] = "1eff00", [3] = "0070dd", [4] = "a335ee", [5] = "ff8000", [6] = "e6cc80" }

-- { name = { q, icon, cls, sub } } for a run or story
function ns.RunItems(adv)
    local items = {}
    if type(adv) ~= "table" then return items end
    local function Add(name, e)
        name = type(name) == "string" and name:gsub("%s*[xX]%d+$", ""):match("^%s*(.-)%s*$") or nil
        if not name or #name < 4 or type(e) ~= "table" then return end
        local link = e.colored or e.link
        local q = tonumber(e.q)
        if not q and type(link) == "string" then q = ns.ItemQuality(link) end
        -- runs from before 0.6.4 kept only the link: ask the game for the rest
        local icon, cls, sub = e.icon, tonumber(e.cls), tonumber(e.sub)
        if not icon and type(link) == "string" then
            local d = ns.ItemDetails(link)
            if d then icon, cls, sub = d.icon, d.cls, d.sub end
        end
        if not items[name] or (q or 0) > (items[name].q or 0) then
            items[name] = { q = q, icon = icon, cls = cls, sub = sub }
        end
    end
    for _, e in ipairs(type(adv.keyLoot) == "table" and adv.keyLoot or {}) do Add(e.plain, e) end
    for _, g in ipairs(type(adv.gear) == "table" and adv.gear or {}) do Add(g.name, g) end
    return items
end

-- 0.6.4: what one member of a story wore and won, for the scene's popup:
-- { worn = { item... }, won = { item... } }, item = { name, q, icon, from }.
-- Only your own gear is known (other players are never inspected); loot
-- is everyone's. A boss gives the loot that came from it.
-- 0.6.5: a loot entry that counts as won gear: green or better, a weapon
-- or armor (class 2 or 4; unknown class falls back to quality alone), and
-- looted or won, not crafted, bought, given or gathered
local NOT_WON = { "^crafted", "^quest", "^bought", "^mail", "^traded", "^gathered", "^received" }
function ns.IsWonGear(e)
    local link = e.colored or e.link
    local q = tonumber(e.q) or (type(link) == "string" and ns.ItemQuality(link)) or nil
    if not q or q < 2 then return false end
    local cls = tonumber(e.cls)
    if not cls and type(link) == "string" then
        local d = ns.ItemDetails(link)
        cls = d and tonumber(d.cls)
    end
    if cls and cls ~= 2 and cls ~= 4 then return false end
    local src = tostring(e.source or ""):lower()
    for _, pat in ipairs(NOT_WON) do
        if src:find(pat) then return false end
    end
    return true
end

function ns.MemberItems(st, name, isBoss)
    local res = { worn = {}, won = {} }
    if type(st) ~= "table" or type(name) ~= "string" then return res end
    local function Item(e, nm, from)
        local link = e.colored or e.link
        local d = (not e.icon and type(link) == "string") and ns.ItemDetails(link) or nil
        local q = tonumber(e.q) or (type(link) == "string" and ns.ItemQuality(link)) or nil
        return { name = nm, q = q, icon = e.icon or (d and d.icon), from = from }
    end
    local low, first = name:lower(), (name:match("^(%S+)") or ""):lower()
    local function Same(who)
        who = tostring(who or ""):lower()
        if who == "" then return false end
        return who == low or (not who:find("%s") and who == first) or (not low:find("%s") and (who:match("^(%S+)") or "") == low)
    end
    local worn = (not isBoss and st.char and Same(st.char)) and st.gear or nil
    -- 0.6.4: a party member's gear, from Record party gear
    if not isBoss and not worn then
        for _, p in ipairs(type(st.participants) == "table" and st.participants or {}) do
            if type(p) == "table" and type(p.gear) == "table" and Same(p.name) then worn = p.gear break end
        end
    end
    for _, g in ipairs(type(worn) == "table" and worn or {}) do
        if type(g) == "table" and g.name then table.insert(res.worn, Item(g, g.name)) end
    end
    -- 0.6.5 (Mor): only real wins (a won roll or loot that went to them),
    -- only gear (weapons and armor), green and better, each drop once
    local wonAt = {}
    for _, e in ipairs(type(st.keyLoot) == "table" and st.keyLoot or {}) do
        if type(e) == "table" and e.plain and ns.IsWonGear(e) then
            local src = tostring(e.source or "")
            local key = tostring(e.looter or ""):lower() .. "|" .. tostring(e.plain):lower()
            local it
            if isBoss then
                if src:lower() == ("from " .. low) then it = Item(e, e.plain, e.looter) end
            elseif Same(e.looter) then
                it = Item(e, e.plain, src ~= "" and src or nil)
            end
            if it then
                local had = wonAt[key]
                if not had then
                    table.insert(res.won, it)
                    wonAt[key] = it
                elseif src == "won roll" and not isBoss then
                    had.from = src
                end
            end
        end
    end
    return res
end

local function Escape(s) return (s:gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1")) end

function ns.DecorateStoryItems(text, adv)
    if type(text) ~= "string" or text == "" then return text end
    local items = ns.RunItems(adv)
    local names = {}
    for n in pairs(items) do table.insert(names, n) end
    if #names == 0 then return text end
    table.sort(names, function(a, b) return #a > #b end)
    local looks = {}
    -- Longest names first, through placeholders, so "Crossbow" never
    -- re-matches inside "Barbaric Crossbow"
    for idx, name in ipairs(names) do
        local it = items[name]
        local hex = ns.QUALITY_HEX[it.q or 1] or "ffffff"
        local icon = it.icon and ("|T" .. tostring(it.icon) .. ":14:14:0:-1|t") or ""
        looks[idx] = icon .. "|cff" .. hex .. name .. "|r"
        local pat, mark = Escape(name), "\001" .. idx .. "\002"
        -- a name in its own color span: the span becomes the item's look
        text = text:gsub("|c%x%x%x%x%x%x%x%x" .. pat .. "|r", mark)
        text = text:gsub("%f[%w]" .. pat .. "%f[^%w]", mark)
    end
    return (text:gsub("\001(%d+)\002", function(i) return looks[tonumber(i)] end))
end

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


-- 0.6.4: how to show a boss of a story: its display ID (recorded when
-- you fought it, remembered from another run, or from the Encounter
-- Journal), else its creature ID. Returns display, npc (either may be nil).
function ns.BossLooks(st, name)
    if type(name) ~= "string" then return nil, nil end
    local info = type(st) == "table" and type(st.bossInfo) == "table" and st.bossInfo[name] or nil
    local cache = type(RPChroniclerDB) == "table" and RPChroniclerDB.bossLooks and RPChroniclerDB.bossLooks[name] or nil
    local display = (type(info) == "table" and tonumber(info.display)) or (cache and tonumber(cache.display)) or nil
    local npc = (type(info) == "table" and tonumber(info.npc)) or (cache and tonumber(cache.npc)) or nil
    -- 0.6.8: the journal by the fight's encounter ID or the boss's name
    -- (the game hides creatures inside dungeons, so a look recorded from
    -- the unit is rare), then the built-in list (SceneData.lua)
    if not display and ns.JournalBossDisplay then
        local enc = (type(info) == "table" and tonumber(info.encounter)) or (cache and tonumber(cache.encounter)) or nil
        local jd, jn = ns.JournalBossDisplay(name, enc)
        display, npc = jd, npc or jn
    end
    local known = ns.BOSS_LOOKS and ns.BOSS_LOOKS[name]
    if known then display, npc = display or known[2], npc or known[1] end
    return display, npc
end

-- 0.6.4: the bosses a story tells of, in the order it first names them:
-- { "Oggleflint", ... }. A recorded kill the story leaves out is not one
-- of them; a boss fought as an encounter is, even with no kill recorded.
function ns.StoryBosses(st, text)
    local list = {}
    if type(st) ~= "table" then return list end
    text = text or st.story
    local plain = type(text) == "string" and ns.StripColors(text):lower() or nil
    local found, seen = {}, {}
    local function Add(b)
        if type(b) ~= "string" or b == "" or seen[b] then return end
        seen[b] = true
        local at = plain and plain:find(b:lower(), 1, true)
        if plain and not at then return end
        table.insert(found, { name = b, at = at or (#found + 1) })
    end
    for _, b in ipairs(type(st.bossKills) == "table" and st.bossKills or {}) do Add(b) end
    for b, info in pairs(type(st.bossInfo) == "table" and st.bossInfo or {}) do
        if type(info) == "table" and info.encounter then Add(b) end
    end
    table.sort(found, function(a, b) return a.at < b.at end)
    for _, f in ipairs(found) do table.insert(list, f.name) end
    return list
end

-- =========================================================
-- Chronicles (0.6.6, Mor): volumes of stories on the Story Book's shelf,
-- for example the whole road of an alt you level with a friend.
-- RPChroniclerDB.chronicles = { { id, title, color, cover, stories = { story ids } } }
-- A story sits in at most one chronicle; the rest stand loose on the
-- shelf. Deleting a chronicle never deletes its stories. Changed only
-- through these functions, which say so with ns.Notify("chronicleChanged").
-- =========================================================
ns.CHRONICLE_TITLE_MAX = 32
-- cover colors (r, g, b), picked in turn for new volumes
ns.CHRONICLE_COLORS = {
    { 0.50, 0.12, 0.12 }, { 0.12, 0.26, 0.48 }, { 0.14, 0.38, 0.18 }, { 0.46, 0.32, 0.10 },
    { 0.34, 0.16, 0.44 }, { 0.10, 0.38, 0.40 }, { 0.28, 0.28, 0.30 }, { 0.52, 0.24, 0.08 },
}

local function Chronicles()
    RPChroniclerDB.chronicles = type(RPChroniclerDB.chronicles) == "table" and RPChroniclerDB.chronicles or {}
    return RPChroniclerDB.chronicles
end

local function CleanTitle(title)
    local t = tostring(title or ""):gsub("||", "|"):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("[%c|]", " ")
    t = t:match("^%s*(.-)%s*$") or ""
    if #t > ns.CHRONICLE_TITLE_MAX then t = t:sub(1, ns.CHRONICLE_TITLE_MAX):match("^(.-)%s*$") end
    return t
end

local function Changed(id)
    ns.Notify("chronicleChanged", id)
end

-- Every chronicle in shelf order; story ids whose story is gone are dropped
function ns.GetChronicles()
    if not RPChroniclerDB then return {} end
    local list = Chronicles()
    for _, c in ipairs(list) do
        c.stories = type(c.stories) == "table" and c.stories or {}
        for i = #c.stories, 1, -1 do
            if not ns.FindStory(c.stories[i]) then table.remove(c.stories, i) end
        end
        if c.cover and not ns.FindStory(c.cover) then c.cover = nil end
    end
    return list
end

function ns.FindChronicle(id)
    for _, c in ipairs(ns.GetChronicles()) do
        if c.id == id then return c end
    end
    return nil
end

-- The chronicle a story is in, and its place there
function ns.ChronicleOf(storyId)
    for _, c in ipairs(ns.GetChronicles()) do
        for i, sid in ipairs(c.stories) do
            if sid == storyId then return c, i end
        end
    end
    return nil
end

-- The chronicle's stories, in its order
function ns.ChronicleStories(c)
    local out = {}
    for _, sid in ipairs((c and c.stories) or {}) do
        local st = ns.FindStory(sid)
        if st then out[#out + 1] = st end
    end
    return out
end

-- Stories in no chronicle, oldest first (they stand at the shelf's end)
function ns.LooseStories()
    local inBook = {}
    for _, c in ipairs(ns.GetChronicles()) do
        for _, sid in ipairs(c.stories) do inBook[sid] = true end
    end
    local out = {}
    for _, st in ipairs(ns.GetStories()) do
        if not inBook[st.id] then table.insert(out, 1, st) end
    end
    return out
end

-- The story whose party scene is on the cover: the chosen one, else the first
function ns.ChronicleCover(c)
    if not c then return nil end
    return (c.cover and ns.FindStory(c.cover)) or ns.ChronicleStories(c)[1]
end

function ns.CreateChronicle(title)
    if not RPChroniclerDB then return nil end
    local list = Chronicles()
    local t = CleanTitle(title)
    if t == "" then t = "Chronicle " .. (#list + 1) end
    RPChroniclerDB.chronicleSeq = (tonumber(RPChroniclerDB.chronicleSeq) or 0) + 1
    local c = { id = "C" .. RPChroniclerDB.chronicleSeq .. "-" .. tostring(time and time() or 0), title = t,
        color = ((#list) % #ns.CHRONICLE_COLORS) + 1, stories = {} }
    table.insert(list, c)
    Changed(c.id)
    return c
end

function ns.RenameChronicle(id, title)
    local c = ns.FindChronicle(id)
    local t = CleanTitle(title)
    if not c or t == "" then return false end
    c.title = t
    Changed(id)
    return true
end

-- Next cover color
function ns.CycleChronicleColor(id)
    local c = ns.FindChronicle(id)
    if not c then return end
    c.color = ((tonumber(c.color) or 1) % #ns.CHRONICLE_COLORS) + 1
    Changed(id)
end

function ns.SetChronicleCover(id, storyId)
    local c = ns.FindChronicle(id)
    if not c then return end
    c.cover = storyId
    Changed(id)
end

-- Removes the volume; its stories go back to the loose pile
function ns.DeleteChronicle(id)
    local list = Chronicles()
    for i = #list, 1, -1 do
        if list[i].id == id then table.remove(list, i) end
    end
    Changed(id)
end

-- Moves a volume left (-1) or right (+1) on the shelf
function ns.MoveChronicle(id, delta)
    local list = Chronicles()
    for i, c in ipairs(list) do
        if c.id == id then
            local j = i + delta
            if j >= 1 and j <= #list then list[i], list[j] = list[j], list[i]; Changed(id) end
            return
        end
    end
end

-- A story leaves any other chronicle and joins this one at the end
function ns.AddStoryToChronicle(storyId, id)
    local c = ns.FindChronicle(id)
    if not c or not ns.FindStory(storyId) then return false end
    local old = ns.ChronicleOf(storyId)
    if old == c then return true end
    if old then ns.RemoveStoryFromChronicle(storyId) end
    table.insert(c.stories, storyId)
    Changed(id)
    return true
end

function ns.RemoveStoryFromChronicle(storyId)
    local c, i = ns.ChronicleOf(storyId)
    if not c then return end
    table.remove(c.stories, i)
    if c.cover == storyId then c.cover = nil end
    Changed(c.id)
end

-- Moves a story up (-1) or down (+1) in its chronicle's contents
function ns.MoveChronicleStory(storyId, delta)
    local c, i = ns.ChronicleOf(storyId)
    if not c then return end
    local j = i + delta
    if j < 1 or j > #c.stories then return end
    c.stories[i], c.stories[j] = c.stories[j], c.stories[i]
    Changed(c.id)
end

-- The story before (-1) or after (+1) this one in its chronicle
function ns.ChronicleNeighbor(storyId, delta)
    local c, i = ns.ChronicleOf(storyId)
    if not c then return nil end
    local sid = c.stories[i + delta]
    return sid and ns.FindStory(sid) or nil
end

-- Stories whose title, place, party or date holds every word of the search
function ns.SearchStories(text)
    local words = {}
    for w in tostring(text or ""):lower():gmatch("%S+") do words[#words + 1] = w end
    if #words == 0 then return {} end
    local out = {}
    for _, st in ipairs(ns.GetStories()) do
        local info = ns.GetBookInfo(st)
        local c = ns.ChronicleOf(st.id)
        local hay = table.concat({ ns.StripColors(info.name or info.title or ""), info.instance or "", info.zone or "",
            info.party or "", info.date or "", c and c.title or "" }, " "):lower()
        local all = true
        for _, w in ipairs(words) do
            if not hay:find(w, 1, true) then all = false; break end
        end
        if all then out[#out + 1] = st end
    end
    return out
end

-- =========================================================
-- 0.7.0 SHELVES (Mor): the Library's planks. "Finished tales" and
-- "Waiting for their story" (the recordings with no story yet, drawn as
-- unbound pages) are the defaults; players rename them, add their own,
-- and move stories between story shelves. Deleting a shelf puts its
-- stories back on Finished tales, so nothing is lost. Gifts (stories
-- friends shared) is made the first time one arrives.
-- RPChroniclerDB.shelves = { { id, name, runs = true? } ... } in order,
-- st.shelf = shelf id. Changes say ns.Notify("shelfChanged").
-- =========================================================
do
    ns.SHELF_NAME_MAX = 32
    ns.DEFAULT_SHELVES = {
        { id = "tales", name = "Finished tales" },
        { id = "waiting", name = "Waiting for their story", runs = true },
    }
    ns.GIFT_SHELF = { id = "gifts", name = "Gifts" }
    local FIXED = { tales = true, waiting = true }

    local function Clean(name)
        local t = tostring(name or ""):gsub("||", "|"):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("[%c|]", " ")
        t = t:match("^%s*(.-)%s*$") or ""
        if #t > ns.SHELF_NAME_MAX then t = t:sub(1, ns.SHELF_NAME_MAX):match("^(.-)%s*$") end
        return t
    end

    -- Every shelf in order; the two defaults are always there
    function ns.GetShelves()
        if not RPChroniclerDB then return {} end
        local list = type(RPChroniclerDB.shelves) == "table" and RPChroniclerDB.shelves or {}
        RPChroniclerDB.shelves = list
        for _, d in ipairs(ns.DEFAULT_SHELVES) do
            local have = false
            for _, s in ipairs(list) do if s.id == d.id then have = true end end
            if not have then table.insert(list, { id = d.id, name = d.name, runs = d.runs }) end
        end
        return list
    end

    function ns.FindShelf(id)
        for _, s in ipairs(ns.GetShelves()) do
            if s.id == id then return s end
        end
        return nil
    end

    -- The story shelf a story stands on (an unknown or missing one: tales)
    function ns.StoryShelf(st)
        local s = st and st.shelf and ns.FindShelf(st.shelf)
        if s and not s.runs then return s.id end
        return "tales"
    end

    function ns.CreateShelf(name)
        local n = Clean(name)
        if n == "" then return nil, "Give the shelf a name." end
        local list = ns.GetShelves()
        if #list >= 12 then return nil, "The Library holds 12 shelves at most." end
        local s = { id = "sh" .. tostring(time()) .. tostring(math.random(100, 999)), name = n }
        table.insert(list, s)
        ns.Notify("shelfChanged", s.id)
        return s
    end

    -- The gifts shelf, made when the first gift arrives (renamable and
    -- deletable like any shelf of the player's)
    function ns.EnsureGiftShelf()
        local s = ns.FindShelf(ns.GIFT_SHELF.id)
        if s then return s end
        s = { id = ns.GIFT_SHELF.id, name = ns.GIFT_SHELF.name }
        table.insert(ns.GetShelves(), s)
        ns.Notify("shelfChanged", s.id)
        return s
    end

    function ns.RenameShelf(id, name)
        local s = ns.FindShelf(id)
        local n = Clean(name)
        if not s or n == "" then return false end
        s.name = n
        ns.Notify("shelfChanged", id)
        return true
    end

    function ns.CanDeleteShelf(id)
        return ns.FindShelf(id) ~= nil and not FIXED[id]
    end

    -- Its stories go back to Finished tales
    function ns.DeleteShelf(id)
        if not ns.CanDeleteShelf(id) then return false end
        local list = ns.GetShelves()
        for i = #list, 1, -1 do
            if list[i].id == id then table.remove(list, i) end
        end
        for _, st in ipairs(ns.GetStories()) do
            if st.shelf == id then st.shelf = nil end
        end
        ns.Notify("shelfChanged", id)
        return true
    end

    function ns.MoveShelf(id, delta)
        local list = ns.GetShelves()
        for i, s in ipairs(list) do
            if s.id == id then
                local j = i + delta
                if j < 1 or j > #list then return false end
                list[i], list[j] = list[j], list[i]
                ns.Notify("shelfChanged", id)
                return true
            end
        end
        return false
    end

    function ns.MoveStoryToShelf(storyId, shelfId)
        local st = ns.FindStory(storyId)
        local s = ns.FindShelf(shelfId)
        if not st or not s or s.runs then return false end
        st.shelf = (shelfId ~= "tales") and shelfId or nil
        ns.Notify("shelfChanged", shelfId)
        return true
    end

    -- The stories on one story shelf, newest first
    function ns.ShelfStories(shelfId)
        local out = {}
        for _, st in ipairs(ns.GetStories()) do
            if ns.StoryShelf(st) == shelfId then out[#out + 1] = st end
        end
        return out
    end

    -- Saved recordings with no story yet (the unbound pages), newest first
    function ns.RunsWithoutStory()
        local out = {}
        for _, adv in ipairs((RPChroniclerDB and RPChroniclerDB.adventures) or {}) do
            if type(adv) == "table" and adv ~= ns.GetActiveAdventure() and not ns.RunHasStory(adv) then out[#out + 1] = adv end
        end
        return out
    end
end
