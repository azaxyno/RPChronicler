-- RP Chronicler - Narrator.lua (0.6.4)
-- Quick Chronicle: a story written in game from the run's own timeline,
-- with no AI. Chapters follow the bosses in a dungeon or raid, and the
-- places on the road in the open world (3 to 6 by length). Each moment
-- becomes a sentence picked from small phrase banks, so two runs don't
-- read the same. It quotes only real in-character lines and the player's
-- [NOTE] thoughts, never shorthand or OOC chatter, and invents nothing.
-- The result has the same header, footer and Run ID as an AI story, so
-- the Story Book, the cover and StoryViewer.html show it unchanged. It is
-- clearly labeled, and a story from an AI replaces it.
-- Local only: it reads the saved run and adds no new data.
local _, ns = ...

local GOLD, PROSE, MUTED = "ffd100", "eceff1", "9e9e9e"
local PLACE, LOOT, BOSS = "40e0d0", "ffd700", "dc143c"
local SAY, PARTY, NPC, THOUGHT = "ffffff", "aaaaff", "fff0a0", "b39ddb"
local DANGER, GOOD = "ff5252", "66bb6a"

local function C(hex, s) return "|cff" .. hex .. tostring(s) .. "|r" end

-- =========================================================
-- Phrase banks. {who}, {foe}, {place}, {item} ... are filled in; each
-- bank is picked from by a seed made of the Run ID, so a story is the
-- same every time it is written, but two runs differ.
-- =========================================================
local BANK = {
    titleDungeon = { "A Chronicle of {place}", "Into {place}", "The Depths of {place}", "What Waited in {place}", "Through {place}" },
    titleWorld = { "Roads of {place}", "A Journal of {place}", "Days in {place}", "Across {place}", "Tracks through {place}" },
    chapterOpen = { "The Gathering", "At the Threshold", "Before the Dark", "The Way In" },
    chapterBoss = { "{foe}", "The Fall of {foe}", "Against {foe}", "Where {foe} Waited" },
    chapterEnd = { "The Way Out", "Embers and Spoils", "After the Last Fight", "Leaving {place}" },
    chapterPlace = { "{place}", "On to {place}", "The Road to {place}", "In {place}" },
    openDungeon = {
        "{party} gathered at the mouth of {place}, weapons ready and the air heavy with what lay below.",
        "The way into {place} opened before {party}, and one by one they stepped into the dark.",
        "{party} met at the edge of {place}. Nobody said much; everyone knew why they had come.",
    },
    openSolo = {
        "{who} set out into {place} with nothing but {their} gear and {their} nerve.",
        "{place} stretched out ahead, and {who} took the first step without looking back.",
        "The road into {place} was quiet when {who} began.",
    },
    openWorld = {
        "{who} took to the road in {place}.",
        "The day found {who} in {place}, the path ahead still unwritten.",
        "{place} lay open before {who}, and the journey began.",
    },
    newPlace = {
        "The road led on to {place}.",
        "Before long, {place} rose into view.",
        "{who} pressed on and reached {place}.",
        "The path turned, and {place} opened ahead.",
    },
    fights = {
        "Along the way they cut down {foes}.",
        "{foes} stood in the way and did not stand for long.",
        "The fighting was steady: {foes} fell one after another.",
        "Blades and spells cleared a path through {foes}.",
    },
    fightsSolo = {
        "Along the way {who} cut down {foes}.",
        "{foes} stood in the way and did not stand for long.",
        "{who} fought through {foes}.",
    },
    kill = {
        "{who} brought down {foe}.",
        "{foe} fell before {who}.",
        "{who} put an end to {foe}.",
    },
    engage = {
        "Then {foe} stood before them.",
        "At last they faced {foe}.",
        "{foe} rose to meet them.",
    },
    bossKill = {
        "{foe} fell, and the chamber went still.",
        "With a final blow, {foe} was defeated.",
        "{foe} crashed down, beaten at last.",
        "The fight ended with {foe} lying broken at their feet.",
    },
    attempts = {
        "It took {n} attempts before {foe} finally fell.",
        "{foe} threw them back {m} times before it fell.",
    },
    wipe = {
        "The party fell, every one of them, and had to find their way back.",
        "It went wrong all at once, and the whole party went down.",
        "Nobody was left standing; they rose again and returned to try once more.",
    },
    death = {
        "{who} fell before {foe}.",
        "{who} went down under the blows of {foe}.",
        "{who} did not survive the fight with {foe}.",
    },
    deathPlain = {
        "{who} fell.",
        "{who} went down and did not get up.",
        "{who} did not survive the fight.",
    },
    rez = {
        "{who} called {target} back to the fight.",
        "{who} brought {target} back from the brink of death.",
    },
    danger = {
        "{who} came within a breath of falling.",
        "For a moment it looked grim for {who}.",
    },
    saved = {
        "{who} was pulled back from the brink just in time.",
        "Help came for {who} at the last moment.",
    },
    level = {
        "{who} grew stronger and reached level {n}.",
        "Something settled in {who}: level {n}.",
        "{who} reached level {n}.",
    },
    quests = {
        "{who} saw {quests} through to the end.",
        "{quests}: done, and the road went on.",
        "{who} finished {quests}.",
    },
    questTaken = {
        "{who} took up {quests}.",
        "New work found {who}: {quests}.",
    },
    loot = {
        "{who} claimed {item}.",
        "{item} went to {who}.",
        "{who} came away with {item}.",
    },
    highlight = {
        "A moment worth remembering: {text}.",
        "{who} would remember this: {text}.",
    },
    -- a marked moment with no words of its own
    highlightPlain = {
        "{who} stopped for a moment in {place}, one {they} meant to remember.",
        "In {place}, {who} paused to take it all in.",
        "{who} lingered in {place} a while, fixing the moment in memory.",
    },
    -- a run too short to tell much
    brief = {
        "{who} spent only {dur} in {place} on this run.",
        "This run was short: {dur} in {place}.",
    },
    thought = {
        "{who} thought: {text}",
        "A thought rose in {who}: {text}",
        "{who} could not shake it: {text}",
    },
    say = {
        "{who} said, {text}",
        "{who} called out, {text}",
        "{who} spoke up: {text}",
    },
    npc = {
        "{who} cried out, {text}",
        "The voice of {who} echoed: {text}",
    },
    closeDungeon = {
        "With the last fight behind them, {party} turned back toward the light and parted ways, the story of {place} theirs to keep.",
        "The dust settled in {place}. {party} shared a last nod and went their separate roads.",
        "{party} left {place} tired, a little richer, and with a tale to tell.",
    },
    closeWorld = {
        "When the day ended, {who} had more road behind {them} than before, and more still ahead.",
        "{who} rested at last, the road of the day folded into memory.",
        "The journey was not over, but this part of it was. {who} looked ahead.",
    },
}

-- A tiny stable hash, so the same run always picks the same phrases
local function Seed(s)
    local h = 5381
    s = tostring(s or "")
    for i = 1, #s do h = (h * 33 + s:byte(i)) % 2147483647 end
    return h
end

local function Fill(s, t)
    return (s:gsub("{(%w+)}", function(k) return t[k] ~= nil and tostring(t[k]) or "" end))
end

-- Writer: picks from the banks in turn, one seed per run
local function NewWriter(seed)
    local w = { n = seed }
    -- {they} {them} {their}: your pronouns from the recorded sex
    w.pro = { they = "they", them = "them", their = "their" }
    function w.Pick(bankName, t)
        local bank = BANK[bankName]
        w.n = (w.n * 1103515245 + 12345) % 2147483648
        local line = bank[(w.n % #bank) + 1]
        t = t or {}
        for k, v in pairs(w.pro) do if t[k] == nil then t[k] = v end end
        return Fill(line, t)
    end
    return w
end

-- "Up" for the start of a sentence
local function Cap(s)
    s = tostring(s or "")
    local lead, first, rest = s:match("^(|c%x%x%x%x%x%x%x%x)(%a)(.*)$")
    if lead then return lead .. first:upper() .. rest end
    return (s:gsub("^%a", string.upper))
end

local function JoinList(list)
    if #list == 0 then return "" end
    if #list == 1 then return list[1] end
    return table.concat(list, ", ", 1, #list - 1) .. " and " .. list[#list]
end

-- =========================================================
-- Reading the timeline
-- =========================================================
local CHAT = { Party = PARTY, ["Party Leader"] = PARTY, Raid = PARTY, ["Raid Leader"] = PARTY, Instance = PARTY,
    ["Instance Leader"] = PARTY, Say = SAY, Yell = SAY }

-- Gamer shorthand and chatter that is never quoted (the story rules'
-- list): a line made of these words alone is skipped
local SHORTHAND = {}
for w in ("mb my bad sry sorry ty thx thanks thank you np gj gg wp lol lmao rofl brb afk inc ready rdy r ok okay k kk yes no ya yep nope mana oom need drink drinking wait sec pull pulling go omg wtf haha hah hi hey yo bye cya oops ofc pls plz idk ah oh hm hmm"):gmatch("%S+") do SHORTHAND[w] = true end

-- A chat line worth quoting: a real sentence said in character
local function InCharacter(msg)
    if type(msg) ~= "string" then return false end
    if ns.IsOocText and ns.IsOocText(msg) then return false end
    local words, plain = 0, 0
    for w in msg:lower():gmatch("[%a']+") do
        words = words + 1
        if not SHORTHAND[w] then plain = plain + 1 end
    end
    if words < 4 or plain < 3 or #msg < 18 then return false end
    -- a long run of capitals, many "?!" or digits reads as chatter
    if msg:find("%u%u%u%u") or msg:find("[%?!][%?!][%?!]") then return false end
    local digits = select(2, msg:gsub("%d", ""))
    return digits <= 2
end

-- One timeline line into an event: { kind, ... } or nil
local function Parse(line)
    line = ns.StripColors(tostring(line or ""))
    local body = line:match("^%[%d+:%d+:%d+%]%s*(.*)$") or line
    local began = body:match("^Adventure began in (.+)$")
    if began then return { kind = "begin", place = began } end
    local tag, rest = body:match("^%[([^%]]+)%]%s*(.*)$")
    if not tag then return nil end
    local base = tag:match("^([^|]-)%s*|") or tag
    base = base:gsub("%s+$", "")
    if tag == "BOSS ENGAGED" then return { kind = "engage", foe = rest } end
    if tag == "BOSS KILL" then return { kind = "bosskill", foe = rest } end
    if tag == "BOSS RESET" then return { kind = "reset", foe = rest } end
    if tag:match("^WIPE") then return { kind = "wipe" } end
    if tag == "DEATH" then
        local who, foe = rest:match("^(.-) died %(fighting ([^,%)]+)")
        return { kind = "death", who = who or rest:match("^(.-) died") or rest, foe = foe }
    end
    if tag == "REZ" then
        local who, target = rest:match("^(.-) resurrected (.+)$")
        if who then return { kind = "rez", who = who, target = target } end
        return nil
    end
    if tag == "DANGER" then return { kind = "danger", who = rest:match("^(.-) dropped to") } end
    if tag == "SAVED" then return { kind = "saved", who = rest:match("^(.-) was pulled") } end
    if tag == "FIGHT" then
        local foes = rest:match("^vs (.-) %(%d+s%)") or rest:match("^vs (.-) %-") or rest:match("^vs (.+)$")
        return foes and { kind = "fight", foes = foes } or nil
    end
    if tag == "FIGHTS" then
        local n, foe = rest:match("^(%d+)x (.-) %(")
        return foe and { kind = "fight", foes = foe, n = tonumber(n) } or nil
    end
    if tag == "KILL" then
        local who, foe = rest:match("^(.-) defeats (.-) %(")
        if not who then who, foe = rest:match("^(.-) defeats (.+)$") end
        return foe and { kind = "kill", who = who, foe = foe } or nil
    end
    if tag == "QUEST" then
        local done = rest:match("^Completed: (.+)$")
        if done then return { kind = "quest", name = done:gsub("%s*%(.-%)$", "") } end
        local took = rest:match("^Accepted: (.+)$")
        if took then return { kind = "questTaken", name = took:gsub("%s*%(.-%)$", "") } end
        local old = rest:match("^.- completed (.+)$")
        if old then return { kind = "quest", name = old } end
        return nil
    end
    if tag == "LEVEL" then
        local who, n = rest:match("^(.-) reached level (%d+)")
        return who and { kind = "level", who = who, n = n } or nil
    end
    if tag == "PLACE" then
        local p = rest:match("^Entered (.-) %(") or rest:match("^Travelled to (.-)%s*%(") or rest:match("^Travelled to (.+)$") or rest:match("^Entered (.+)$")
        return p and { kind = "place", place = p } or nil
    end
    if tag == "LOOT" then
        local who, item, src = rest:match("^(.-) received (.-) %((.-)%)$")
        if not who then who, item = rest:match("^(.-) received (.+)$") end
        if item then item = item:gsub("%s*[xX]%d+$", "") end
        return item and { kind = "loot", who = who, item = item, from = src } or nil
    end
    if tag == "MILESTONE" then return { kind = "milestone", text = rest } end
    if tag == "HIGHLIGHT" then return { kind = "highlight", text = rest } end
    if tag == "NOTE" then return { kind = "note", text = rest } end
    local shot = tag:match("^SHOT (%S+)$")
    if shot then return { kind = "shot", id = shot } end
    if tag == "NPC" then
        local who, msg = rest:match("^(.-): (.+)$")
        return who and { kind = "npc", who = who, text = msg } or nil
    end
    if CHAT[base] then
        local who, msg = rest:match("^(.-): (.+)$")
        return who and { kind = "chat", who = who, text = msg, color = CHAT[base] } or nil
    end
    return nil
end

-- =========================================================
-- Chapters
-- =========================================================
local function Segments(events, kind)
    local segs = {}
    local function New(title) local s = { events = {}, title = title } table.insert(segs, s) return s end
    if kind ~= "world" then
        local any = false
        for _, e in ipairs(events) do if e.kind == "bosskill" then any = true break end end
        if any then
            local cur = New({ open = true })
            for _, e in ipairs(events) do
                -- the picture and the loot of a boss kill stay in its chapter
                local prev = segs[#segs - 1]
                if #cur.events == 0 and prev and (e.kind == "shot" or e.kind == "loot") then cur = prev end
                table.insert(cur.events, e)
                if cur == prev then cur = segs[#segs] end
                if e.kind == "bosskill" then
                    cur.title = cur.title.open and { boss = e.foe, first = true } or { boss = e.foe }
                    cur = New({ close = true })
                end
            end
            -- nothing after the last boss: the closing words join its chapter
            if #cur.events == 0 then table.remove(segs) segs[#segs].closing = true else cur.closing = true end
            return segs
        end
    end
    -- the open world (or a dungeon with no boss): by place
    local cur = New({ place = nil })
    for _, e in ipairs(events) do
        if e.kind == "place" and #cur.events >= 3 then cur = New({ place = e.place }) end
        if e.kind == "place" and not cur.title.place then cur.title.place = e.place end
        table.insert(cur.events, e)
    end
    -- 3 to 6 chapters by length (fewer for a short run)
    local cap = math.max(1, math.min(6, math.floor(#events / 10) + 1))
    while #segs > cap do
        -- fold the smallest chapter into the one before it
        local small, at = math.huge, 2
        for i = 2, #segs do if #segs[i].events < small then small, at = #segs[i].events, i end end
        local into, from = segs[at - 1], segs[at]
        for _, e in ipairs(from.events) do table.insert(into.events, e) end
        into.title.also = into.title.also or from.title.place
        table.remove(segs, at)
    end
    segs[#segs].closing = true
    return segs
end

-- =========================================================
-- Writing one chapter
-- =========================================================
local MAX_QUOTES, MAX_SENTENCES = 2, 12

local function WriteChapter(seg, ctx, W)
    local out, sentences, quotes, npcQuotes = {}, 0, 0, 0
    local fightFoes, fightSeen = {}, {}
    local paragraph = {}
    local function Flush()
        if #paragraph > 0 then table.insert(out, C(PROSE, table.concat(paragraph, " "))) paragraph = {} end
    end
    local function Say(s)
        if sentences >= MAX_SENTENCES then return end
        sentences = sentences + 1
        table.insert(paragraph, Cap(s))
    end
    local function FlushFights()
        if #fightFoes == 0 then return end
        local names = {}
        for i = 1, math.min(3, #fightFoes) do table.insert(names, C(BOSS, fightFoes[i])) end
        if #fightFoes > 3 then table.insert(names, "more besides") end
        Say(W.Pick(ctx.solo and "fightsSolo" or "fights", { foes = JoinList(names), who = ctx.you }))
        fightFoes, fightSeen = {}, {}
    end
    local engaged, wipesHere, quests, taken, loots = {}, 0, {}, {}, {}
    for _, e in ipairs(seg.events) do
        local k = e.kind
        if k == "fight" then
            -- "Ragefire Trogg, Ragefire Shaman" -> each foe once
            for foe in tostring(e.foes):gmatch("[^,]+") do
                foe = foe:gsub("^%s+", ""):gsub("%s+$", ""):gsub("^%d+x%s*", "")
                if foe ~= "" and not fightSeen[foe] then
                    fightSeen[foe] = true
                    -- a streak reads "Earthborer after Earthborer"
                    table.insert(fightFoes, (e.n and e.n >= 3) and (foe .. "|r" .. C(PROSE, " after ") .. "|cff" .. BOSS .. foe) or foe)
                end
            end
        elseif k == "begin" then
            -- the opening words are written by the caller
        elseif k == "place" then
            if not seg.title.first and e.place ~= ctx.lastPlace then
                FlushFights()
                Say(W.Pick("newPlace", { place = C(PLACE, e.place), who = ctx.you }))
            end
            ctx.lastPlace = e.place
        elseif k == "engage" then
            FlushFights()
            engaged[e.foe] = (engaged[e.foe] or 0) + 1
            if engaged[e.foe] == 1 then Say(W.Pick("engage", { foe = C(BOSS, e.foe) })) end
        elseif k == "wipe" then
            FlushFights()
            wipesHere = wipesHere + 1
            Say(C(DANGER, W.Pick("wipe", {})))
        elseif k == "bosskill" then
            FlushFights()
            local tries = engaged[e.foe] or 1
            if tries > 1 then Say(W.Pick("attempts", { foe = C(BOSS, e.foe), n = tries, m = tries - 1 }))
            else Say(W.Pick("bossKill", { foe = C(BOSS, e.foe) })) end
        elseif k == "kill" then
            FlushFights()
            Say(W.Pick("kill", { who = e.who or ctx.you, foe = C(BOSS, e.foe) }))
        elseif k == "death" then
            FlushFights()
            if e.foe then Say(C(DANGER, W.Pick("death", { who = e.who, foe = e.foe })))
            else Say(C(DANGER, W.Pick("deathPlain", { who = e.who }))) end
        elseif k == "rez" then
            Say(C(GOOD, W.Pick("rez", { who = e.who, target = e.target })))
        elseif k == "danger" and e.who then
            if not ctx.dangerSaid then ctx.dangerSaid = true Say(W.Pick("danger", { who = e.who })) end
        elseif k == "saved" and e.who then
            if not ctx.savedSaid then ctx.savedSaid = true Say(C(GOOD, W.Pick("saved", { who = e.who }))) end
        elseif k == "level" then
            FlushFights()
            Say(W.Pick("level", { who = e.who, n = e.n }))
        elseif k == "quest" then
            table.insert(quests, e.name)
        elseif k == "questTaken" then
            table.insert(taken, e.name)
        elseif k == "loot" then
            table.insert(loots, e)
        elseif k == "milestone" then
            Say(e.text .. ".")
        elseif k == "highlight" then
            -- the same moment marked twice is told once; a mark with no
            -- words of its own ("Memorable moment in ...") becomes a
            -- sentence about the place
            local plainAt = tostring(e.text):match("^Memorable moment in (.+)$")
            local key = plainAt and ("@" .. plainAt) or tostring(e.text)
            if not ctx.highlights[key] then
                ctx.highlights[key] = true
                if plainAt then
                    local where = plainAt:gsub("%s+%-%s+.*$", "")
                    local sub = plainAt:match("%s+%-%s+(.+)$")
                    Say(W.Pick("highlightPlain", { who = ctx.you, place = C(PLACE, sub or where) }))
                else
                    Say(W.Pick("highlight", { who = ctx.you, text = e.text }))
                end
            end
        elseif k == "note" then
            FlushFights()
            Say(W.Pick("thought", { who = ctx.you, text = C(THOUGHT, e.text) }))
        elseif k == "chat" then
            if quotes < MAX_QUOTES and InCharacter(e.text) then
                quotes = quotes + 1
                FlushFights()
                Say(W.Pick("say", { who = e.who, text = C(e.color, "\"" .. e.text .. "\"") }))
            end
        elseif k == "npc" then
            if npcQuotes < 1 and InCharacter(e.text) then
                npcQuotes = npcQuotes + 1
                Say(W.Pick("npc", { who = C(BOSS, e.who), text = C(NPC, "\"" .. e.text .. "\"") }))
            end
        elseif k == "shot" then
            -- a picture marker on its own line, where it happened
            FlushFights()
            Flush()
            table.insert(out, "[Shot " .. e.id .. "]")
        end
    end
    FlushFights()
    if #quests > 0 then
        local q = {}
        for i = 1, math.min(4, #quests) do table.insert(q, C(GOLD, quests[i])) end
        if #quests > 4 then table.insert(q, (#quests - 4) .. " more") end
        Say(W.Pick("quests", { who = ctx.you, quests = JoinList(q) }))
    elseif #taken > 0 and ctx.kind == "world" then
        local q = {}
        for i = 1, math.min(2, #taken) do table.insert(q, C(GOLD, taken[i])) end
        Say(W.Pick("questTaken", { who = ctx.you, quests = JoinList(q) }))
    end
    for i = 1, math.min(3, #loots) do
        local l = loots[i]
        Say(W.Pick("loot", { who = l.who or ctx.you, item = C(LOOT, l.item) }))
    end
    Flush()
    return out
end

-- =========================================================
-- The whole story
-- =========================================================
function ns.BuildQuickChronicle(adv)
    if type(adv) ~= "table" then return nil end
    local events, lastKey = {}, nil
    for _, line in ipairs(type(adv.fullTimeline) == "table" and adv.fullTimeline or {}) do
        local ok, e = pcall(Parse, line)
        if ok and e then
            -- the same event twice in a row is told once
            local key = e.kind .. "|" .. tostring(e.text or e.foe or e.foes or e.name or e.place or e.item or e.who or e.id or "")
            if key ~= lastKey then table.insert(events, e) end
            lastKey = key
        end
    end
    local code = ns.RunCode and ns.RunCode(adv)
    local W = NewWriter(Seed(code or adv.startTime or adv.title))
    local kind = adv.kind == "world" and "world" or "dungeon"
    local place = adv.instanceName or adv.zone or adv.title or "the road"
    local roster = ns.MergedRoster and ns.MergedRoster(adv.participants) or {}
    local you = adv.char or (ns.PlayerName and ns.PlayerName()) or "the traveller"
    local names = {}
    for _, p in ipairs(roster) do table.insert(names, p.name) end
    if #names == 0 then names = { you } end
    local partyText = #names > 4 and (names[1] .. ", " .. names[2] .. " and their companions") or JoinList(names)
    -- the opening names you in full, the rest of the story by first name
    local ctx = { kind = kind, you = you:match("^(%S+)") or you, solo = #names <= 1, lastPlace = place, highlights = {} }
    -- your pronouns from the sex recorded for you (they/them when unknown)
    for _, p in ipairs(roster) do
        if p.name == you or (p.name and p.name:match("^(%S+)") == ctx.you and tonumber(p.sex)) then
            if tonumber(p.sex) == 2 then W.pro = { they = "he", them = "him", their = "his" }
            elseif tonumber(p.sex) == 3 then W.pro = { they = "she", them = "her", their = "her" } end
            if p.name == you then break end
        end
    end
    -- a run where next to nothing happened gets a short, honest entry
    local MINOR = { begin = true, place = true, shot = true, questTaken = true, fight = true }
    local told = 0
    for _, e in ipairs(events) do if not MINOR[e.kind] then told = told + 1 end end
    local durSec = tonumber(ns.GetRunDuration(adv)) or 0
    local brief = told == 0 or (told < 3 and durSec < 300)

    local out = {}
    local title = W.Pick(kind == "world" and "titleWorld" or "titleDungeon", { place = place })
    table.insert(out, C(GOLD, "Title: " .. title))
    -- header: place | duration | other places
    local others = {}
    for _, p in ipairs(type(adv.places) == "table" and adv.places or {}) do
        local n = type(p) == "table" and (p.name or p.place) or p
        if type(n) == "string" and n ~= place and #others < 3 then table.insert(others, n) end
    end
    local dur = ns.FormatDuration(ns.GetRunDuration(adv)):gsub(" 00s$", "")
    table.insert(out, C(MUTED, place .. " | " .. dur .. (#others > 0 and (" | " .. table.concat(others, ", ")) or "")))
    table.insert(out, C(MUTED, "Date: " .. tostring(adv.startDate or "-") .. (#names > 1 and (" | Party: " .. table.concat(names, ", ")) or "")))
    table.insert(out, C(MUTED, "Quick Chronicle (test feature), written by RP Chronicler without AI. For a full story, open the Full Log, tick Include AI instructions, click Copy for AI and paste it into any AI chat."))
    table.insert(out, "")

    if brief then
        table.insert(out, C(GOLD, "Chapter 1: " .. place))
        table.insert(out, C(PROSE, Cap(W.Pick("brief", { who = you, place = C(PLACE, place), dur = dur }))))
        for _, line in ipairs(WriteChapter({ events = events, title = { first = true } }, ctx, W)) do table.insert(out, line) end
        table.insert(out, C(PROSE, "Too little happened on this run for a longer tale. Record a longer run for a fuller one."))
        table.insert(out, "")
    end
    local segs = brief and {} or Segments(events, kind)
    for i, seg in ipairs(segs) do
        local t = seg.title
        local name
        if t.boss then name = W.Pick("chapterBoss", { foe = t.boss })
        elseif t.open then name = W.Pick("chapterOpen", { place = place })
        elseif t.close then name = W.Pick("chapterEnd", { place = place })
        else
            local p = t.place or (i == 1 and place) or nil
            name = p and W.Pick("chapterPlace", { place = p }) or "The Road On"
            if t.also and t.also ~= p then name = name .. " and " .. t.also end
        end
        table.insert(out, C(GOLD, "Chapter " .. i .. ": " .. name))
        if i == 1 then
            local opening
            if kind == "world" then opening = W.Pick("openWorld", { who = you, place = C(PLACE, place) })
            elseif ctx.solo then opening = W.Pick("openSolo", { who = you, place = C(PLACE, place) })
            else opening = W.Pick("openDungeon", { party = partyText, place = C(PLACE, place) }) end
            table.insert(out, C(PROSE, Cap(opening)))
        end
        for _, line in ipairs(WriteChapter(seg, ctx, W)) do table.insert(out, line) end
        if seg.closing then
            if kind == "world" then table.insert(out, C(PROSE, Cap(W.Pick("closeWorld", { who = you }))))
            else table.insert(out, C(PROSE, Cap(W.Pick("closeDungeon", { party = partyText, place = C(PLACE, place) })))) end
        end
        table.insert(out, "")
    end

    -- footer, as the story templates write it
    local deaths = 0
    for _, e in ipairs(events) do if e.kind == "death" then deaths = deaths + 1 end end
    local foot
    if kind == "world" then
        local parts = {}
        if (tonumber(adv.foesDefeated) or 0) > 0 then table.insert(parts, "Foes: " .. adv.foesDefeated) end
        if (tonumber(adv.questsDone) or 0) > 0 then table.insert(parts, "Quests: " .. adv.questsDone) end
        if tonumber(adv.levelStart) and tonumber(adv.levelEnd) and adv.levelEnd > adv.levelStart then
            table.insert(parts, "Levels: " .. adv.levelStart .. " -> " .. adv.levelEnd)
        end
        if deaths > 0 then table.insert(parts, "Deaths: " .. deaths) end
        foot = table.concat(parts, " | ")
    else
        local seen, n = {}, 0
        for _, b in ipairs(type(adv.bossKills) == "table" and adv.bossKills or {}) do
            if not seen[b] then seen[b] = true n = n + 1 end
        end
        foot = string.format("Bosses: %d | Wipes: %d | Deaths: %d", n, tonumber(adv.wipes) or 0, deaths)
    end
    if foot ~= "" then table.insert(out, C(MUTED, foot)) end
    if code then table.insert(out, C(MUTED, "Run ID: " .. code)) end
    return table.concat(out, "\n")
end

-- Writes the Quick Chronicle into the Story Book (replacing this run's
-- story, if it has one). Returns ok, storyId.
function ns.SaveQuickChronicle(adv)
    local text = ns.BuildQuickChronicle(adv)
    if not text then return false end
    local ok, id = ns.SetAdventureStory(adv.id, text)
    if ok then
        local st = ns.FindStory and ns.FindStory(id)
        if st then st.quick = true end
        ns.Debug("run", "quick chronicle written for " .. tostring(adv.title))
    end
    return ok, id
end
