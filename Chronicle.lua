local ADDON_NAME, ns = ...

-- =========================================================
-- Chronicle (0.4.0): the story-level lines of a run, for every run type
-- (open world, dungeon, raid). Never uses the combat log.
--  * [FIGHT]      one line per fight: foes, length, flee, aggro swaps,
--                 who got low, who fell, outcome
--  * [KILL]       elites, rares and named foes (trash is only counted)
--  * [QUEST]      accepted and completed, plus trimmed quest-giver text
--  * [NPC]        boss and named NPC lines (filtered in ns.ChronicleNpc)
--  * [LEVEL]      level ups      * [PLACE]   subzone changes
--  * [SKILL]      profession skill-ups, summarized
--  * [MILESTONE]  new spells, pets, mounts, achievements, reputation,
--                 hearthstone bind, flight paths
--  * [ATMOSPHERE] time of day at the start and on zone changes
--  * loot sources ("crafted", "from Arugal", "quest reward", ...)
-- Each kind has its own switch in Options > Full Log (ns.LogOn).
-- =========================================================

local C = {
    fight = nil,          -- the fight in progress
    killSeen = {},        -- unit key -> true once counted
    enemySeen = {},       -- unit key -> enemy info while the fight lasts
    ctx = {},             -- loot context: merchant, mail, trade, loot window ...
    lastSub = nil, subAt = {},
    lastZone = nil,
    atmoAt = 0, atmoPhase = nil,
    skillLineAt = {},
    quest = {},           -- pending quest text from the quest window
    questDone = {},       -- title -> time logged
    npcAt = {}, npcSaid = {},
    petName = nil, tameAt = 0,
    streak = nil,         -- 0.5.0: the trash streak being folded into one line
    subPending = nil,     -- the subzone waiting to settle
    objDone = {}, objSeeded = false, objPending = false,
}

local function Run()
    local run = ns.GetActiveAdventure and ns.GetActiveAdventure()
    if not run or run.paused then return nil end
    return run
end

local function Line(cat, text)
    if cat and not ns.LogOn(cat) then return end
    if ns.RecordAdventureLine then return ns.RecordAdventureLine(text) end
end

local function Later(sec, fn)
    if C_Timer and C_Timer.After then C_Timer.After(sec, fn) else fn() end
end

local function Clock(t)
    return (date and t) and date("%H:%M", t) or "?"
end

local function Me()
    local n = ns.StripRealm(UnitName("player")) or "You"
    return (ns.ResolveCanonicalPlayerName and ns.ResolveCanonicalPlayerName(n)) or n
end

local function InInstance()
    if not IsInInstance then return false end
    local inside = IsInInstance()
    return inside and true or false
end

local function Trim(s, max)
    s = tostring(s or ""):gsub("[\r\n]+", " "):gsub("%s%s+", " ")
    s = s:match("^%s*(.-)%s*$")
    if max and #s > max then
        local cut = s:sub(1, max)
        -- end on a sentence or a word
        local dot = cut:match("^(.*[%.!%?])%s")
        s = (dot and #dot > max * 0.5) and dot or (cut:match("^(.*)%s") or cut) .. "..."
    end
    return s
end
C.Trim = Trim

local function Pattern(globalName)
    local fmt = _G[globalName]
    return type(fmt) == "string" and ns.FormatToPattern(fmt) or nil
end

local function Times(n)
    if n == 1 then return "once" elseif n == 2 then return "twice" end
    return n .. " times"
end

-- =========================================================
-- Fights
-- =========================================================
local function UnitKey(u)
    local guid = UnitGUID and ns.SafeStr(UnitGUID(u))
    if guid then return guid end
    local n = ns.SafeStr(UnitName(u))
    return n and (n .. ":" .. u) or nil
end

local function EnemyKind(u)
    local cls = ns.SafeStr(UnitClassification(u)) or "normal"
    if ns.IsBossUnit and ns.IsBossUnit(u) then return "boss" end
    if cls == "worldboss" then return "boss" end
    if cls == "rareelite" then return "rare elite" end
    if cls == "rare" then return "rare" end
    if cls == "elite" then return "elite" end
    return "normal"
end

function ns.FightBegin()
    if C.fight or not Run() then return end
    C.fight = {
        start = GetTime(), enemies = {}, order = {}, swaps = {}, low = {}, fell = {},
        kills = 0, killNames = {}, fled = 0, coin = 0,
        spells = {}, spellOrder = {},
    }
    C.enemySeen = {}
    if UnitExists("target") then ns.FightSeeUnit("target") end
end

local function AddEnemy(name, kind)
    local f = C.fight
    if not f or not name then return end
    local e = f.enemies[name]
    if not e then
        e = { count = 0, kind = kind }
        f.enemies[name] = e
        table.insert(f.order, name)
    end
    e.count = e.count + 1
end

local function NoteKill(name, kind, u)
    local run = Run()
    if not run then return end
    run.foesDefeated = (run.foesDefeated or 0) + 1
    run.killCounts = run.killCounts or {}
    run.killCounts[name] = (run.killCounts[name] or 0) + 1
    local f = C.fight
    if f then
        f.kills = f.kills + 1
        f.killNames[name] = (f.killNames[name] or 0) + 1
    end
    if kind == "boss" then return end -- [BOSS KILL] covers it
    local notable = (kind == "rare" or kind == "rare elite") or (kind == "elite" and not InInstance())
    if notable then
        run.kills = run.kills or {}
        if #run.kills < 60 then table.insert(run.kills, name) end
        local who = (u == "target" or not IsInGroup or not IsInGroup()) and Me() or "the party"
        Line("kills", string.format("[KILL] %s defeats %s (%s)", who, name, kind))
    end
end

-- Called by the combat poller for every unit token it looks at, and on
-- UNIT_HEALTH: living enemies join the fight, dead ones count as kills.
function ns.FightSeeUnit(u)
    if not UnitExists(u) then return end
    local key = UnitKey(u)
    if not key then return end
    if UnitIsPlayer(u) then
        -- 0.5.0: an enemy player who dies in your fight counts as a PvP kill
        if C.fight and UnitIsDead(u) and UnitCanAttack("player", u) and not C.killSeen[key] then
            C.killSeen[key] = true
            local run = Run()
            if run then
                run.pvpKills = (run.pvpKills or 0) + 1
                local who = ns.GetUnitFullName and ns.GetUnitFullName(u) or ns.SafeStr(UnitName(u))
                if who then Line("kills", string.format("[PVP] %s defeats %s", Me(), who)) end
            end
        end
        return
    end
    local name = ns.SafeStr(UnitName(u))
    if not name then return end
    if UnitIsDead(u) then
        local info = C.enemySeen[key]
        if info and not C.killSeen[key] then
            C.killSeen[key] = true
            NoteKill(name, info.kind, u)
        end
        return
    end
    if not C.fight or C.enemySeen[key] then return end
    if not UnitCanAttack("player", u) then return end
    if UnitAffectingCombat and UnitAffectingCombat(u) ~= true then return end
    local kind = EnemyKind(u)
    C.enemySeen[key] = { name = name, kind = kind }
    AddEnemy(name, kind)
end

function ns.FightNoteAggro(mobName, fromName, toName)
    local f = C.fight
    if not f or not fromName or not toName then return end
    local s = string.format("%s took aggro from %s", toName, fromName)
    for _, v in ipairs(f.swaps) do if v == s then return end end
    if #f.swaps < 3 then table.insert(f.swaps, s) end
end

function ns.FightNoteLow(who)
    local f = C.fight
    if not f or not who then return end
    for _, v in ipairs(f.low) do if v == who then return end end
    table.insert(f.low, who)
end

function ns.FightNoteDeath(who, isSelf)
    local f = C.fight
    if not f or not who then return end
    table.insert(f.fell, who)
    if isSelf then
        f.selfDied = true
        local run = Run()
        if run and UnitExists("target") and UnitIsPlayer("target") and UnitCanAttack("player", "target") then
            run.pvpDeaths = (run.pvpDeaths or 0) + 1
        end
    end
end

-- 0.5.0: abilities used in the fight, for the [FIGHT] line. Returns true
-- when the spell was folded (so no standalone [SPELL] line is needed).
function ns.FightNoteSpell(who, spell)
    local f = C.fight
    if not f or not who or not spell or not ns.LogOn("fights") then return false end
    local list = f.spells[who]
    if not list then
        if #f.spellOrder >= 4 then return true end
        list = {}
        f.spells[who] = list
        table.insert(f.spellOrder, who)
    end
    for _, sp in ipairs(list) do if sp == spell then return true end end
    if #list < 4 then table.insert(list, spell) end
    return true
end

local function SpellText(spells, order)
    local parts = {}
    for _, who in ipairs(order) do
        local list = spells[who]
        if list and #list > 0 then
            if who == "you" then
                table.insert(parts, 1, "used " .. table.concat(list, ", "))
            else
                table.insert(parts, who .. ": " .. table.concat(list, ", "))
            end
        end
    end
    return table.concat(parts, "; ")
end

function ns.FightNoteCoin(copper)
    if C.fight then C.fight.coin = C.fight.coin + (copper or 0) end
end

function ns.FightFled(npcName)
    if not C.fight then ns.FightBegin() end
    local f = C.fight
    if not f then return end
    f.fled = f.fled + 1
    f.fledName = npcName
end

-- The main foe: the strongest, then the first seen
local FOE_RANK = { boss = 5, ["rare elite"] = 4, rare = 3, elite = 2, normal = 1 }
local function MainFoe(f)
    local best, bestRank = nil, 0
    for _, name in ipairs(f.order) do
        local r = FOE_RANK[f.enemies[name].kind] or 1
        if r > bestRank then best, bestRank = name, r end
    end
    return best
end

function ns.FightCurrentFoe()
    local f = C.fight
    local foe = f and MainFoe(f)
    if foe then return foe end
    return UnitExists("target") and UnitCanAttack("player", "target") and ns.SafeStr(UnitName("target")) or nil
end

local function FoeList(f)
    local parts = {}
    local main = MainFoe(f)
    if main then
        local e = f.enemies[main]
        table.insert(parts, (e.count > 1) and (e.count .. " " .. main) or main)
    end
    local others = 0
    for _, name in ipairs(f.order) do
        if name ~= main then
            if #parts < 3 then
                local e = f.enemies[name]
                table.insert(parts, (e.count > 1) and (e.count .. " " .. name) or name)
            else
                others = others + f.enemies[name].count
            end
        end
    end
    local text = table.concat(parts, ", ")
    if others > 0 then text = text .. " and " .. others .. " more" end
    return text ~= "" and text or nil
end

-- Writes the [FIGHT] line for the fight that just ended
function ns.FightFlush()
    local f = C.fight
    C.fight = nil
    if not f then return end
    -- Last look for kills (the final blow often lands as combat drops)
    pcall(function()
        for _, u in ipairs({ "target", "focus", "mouseover" }) do
            if UnitExists(u) and UnitIsDead(u) then
                C.fight = f
                ns.FightSeeUnit(u)
                C.fight = nil
            end
        end
    end)
    C.enemySeen = {}
    if not Run() or not ns.LogOn("fights") then return end
    local dur = math.floor(GetTime() - f.start + 0.5)
    local foes = FoeList(f)
    if not foes and f.fledName then foes = f.fledName end
    if dur < ns.Limit("minFightSec") and f.kills == 0 and #f.fell == 0 then return end
    if not foes and f.kills == 0 and #f.fell == 0 then return end

    local run = Run()
    local main = MainFoe(f)
    local now = time()
    -- 0.5.0: plain trash fights against the same foe fold into one line
    -- that is updated in place: "[FIGHTS] 14x Windsong Crawler (20:07-20:15)"
    local plain = main and f.kills > 0 and #f.order == 1 and f.enemies[main].kind == "normal"
        and #f.swaps == 0 and #f.low == 0 and #f.fell == 0
    if plain and ns.LogOn("fightStreaks") then
        local sk = C.streak
        if sk and sk.foe == main and sk.run == run.id and (now - sk.last) <= 300 then
            sk.kills = sk.kills + f.kills
            sk.seen = sk.seen + f.enemies[main].count
            sk.fled = sk.fled + ((f.fled > 0) and 1 or 0)
            sk.coin = sk.coin + f.coin
            sk.last = now
            for _, who in ipairs(f.spellOrder) do
                for _, sp in ipairs(f.spells[who]) do
                    sk.spells[who] = sk.spells[who] or {}
                    if not sk.spells[who][sp] then
                        sk.spells[who][sp] = true
                        sk.spellList[who] = sk.spellList[who] or {}
                        if #sk.spellList[who] < 4 then table.insert(sk.spellList[who], sp) end
                        local known = false
                        for _, w in ipairs(sk.spellOrder) do if w == who then known = true end end
                        if not known and #sk.spellOrder < 4 then table.insert(sk.spellOrder, who) end
                    end
                end
            end
            local tail = {}
            table.insert(tail, (sk.kills >= sk.seen) and "all defeated" or string.format("defeated %d of %d", sk.kills, sk.seen))
            if sk.fled > 0 then table.insert(tail, sk.fled .. " fled briefly") end
            local st = SpellText(sk.spellList, sk.spellOrder)
            if st ~= "" then table.insert(tail, st) end
            if sk.coin > 0 and ns.LogOn("loot") then table.insert(tail, "looted " .. ns.FormatCopper(sk.coin)) end
            local text = string.format("[FIGHTS] %dx %s (%s-%s) - %s", sk.seen, main, Clock(sk.first), Clock(now), table.concat(tail, " - "))
            if ns.UpdateAdventureLine and ns.UpdateAdventureLine(sk.handle, text) then return end
        end
    end

    local bits = {}
    local spellText = SpellText(f.spells, f.spellOrder)
    if spellText ~= "" then table.insert(bits, spellText) end
    if f.fled > 0 then table.insert(bits, (f.fledName and (f.fledName .. " ") or "") .. "fled " .. Times(f.fled)) end
    for _, s in ipairs(f.swaps) do table.insert(bits, s) end
    if #f.low > 0 then table.insert(bits, table.concat(f.low, ", ") .. " got low") end
    if #f.fell > 0 then table.insert(bits, table.concat(f.fell, ", ") .. " fell") end
    if f.coin > 0 and ns.LogOn("loot") then table.insert(bits, "looted " .. ns.FormatCopper(f.coin)) end

    local outcome
    if f.selfDied and f.kills == 0 then
        outcome = "defeat"
    elseif f.kills > 0 then
        outcome = (f.kills > 1) and ("defeated " .. f.kills .. " foes") or "defeated"
    elseif f.fled > 0 then
        outcome = "it escaped"
    elseif IsInGroup and IsInGroup() then
        outcome = "the party disengaged"
    else
        outcome = "you disengaged"
    end
    table.insert(bits, outcome)
    local handle = Line(nil, string.format("[FIGHT] vs %s (%ds) - %s", foes or "unknown foes", dur, table.concat(bits, " - ")))
    if plain and handle then
        local sl, so = {}, {}
        for _, who in ipairs(f.spellOrder) do
            table.insert(so, who)
            sl[who] = {}
            for _, sp in ipairs(f.spells[who]) do table.insert(sl[who], sp) end
        end
        local seenSp = {}
        for who, list in pairs(sl) do
            seenSp[who] = {}
            for _, sp in ipairs(list) do seenSp[who][sp] = true end
        end
        C.streak = { foe = main, run = run.id, handle = handle, first = now - dur, last = now,
            kills = f.kills, seen = f.enemies[main].count, fled = (f.fled > 0) and 1 or 0, coin = f.coin,
            spells = seenSp, spellList = sl, spellOrder = so }
    else
        C.streak = nil
    end
end

-- =========================================================
-- Atmosphere: time of day and indoors/outdoors (no weather API exists
-- on this client, so weather is left to the storyteller)
-- =========================================================
local function DayPhase(h)
    if h >= 5 and h < 7 then return "Dawn" end
    if h >= 7 and h < 11 then return "Morning" end
    if h >= 11 and h < 14 then return "Midday" end
    if h >= 14 and h < 18 then return "Afternoon" end
    if h >= 18 and h < 21 then return "Dusk" end
    return "Night"
end

function ns.RecordAtmosphere(force)
    if not Run() or not ns.LogOn("atmosphere") then return end
    local h, m
    if GetGameTime then
        local ok, gh, gm = pcall(GetGameTime)
        if ok then h, m = ns.SafeNum(gh), ns.SafeNum(gm) end
    end
    if not h then return end
    local phase = DayPhase(h)
    local now = GetTime()
    if not force and phase == C.atmoPhase and (now - C.atmoAt) < 1200 then return end
    C.atmoPhase, C.atmoAt = phase, now
    local where = ns.GetCurrentWhere()
    local inside = ""
    if IsIndoors then
        local ok, v = pcall(IsIndoors)
        if ok and v == true then inside = ", indoors" elseif ok and v == false then inside = ", under the open sky" end
    end
    if InInstance() then inside = "" end
    Line(nil, string.format("[ATMOSPHERE] %s (%02d:%02d server time) in %s%s", phase, h, m or 0, where, inside))
end

-- =========================================================
-- Places, levels, skills, milestones
-- =========================================================
local function OnZone(newArea)
    if not Run() then return end
    local zone = ns.SafeStr(GetRealZoneText()) or ns.SafeStr(GetZoneText())
    local sub = ns.SafeStr(GetSubZoneText())
    local now = GetTime()
    if newArea and zone and zone ~= C.lastZone then
        local first = C.lastZone == nil
        C.lastZone = zone
        C.lastSub = sub
        if not first then
            if ns.NoteRunPlace then ns.NoteRunPlace(zone) end
            Line("places", "[PLACE] Travelled to " .. zone)
            ns.RecordAtmosphere(false)
        end
        return
    end
    if sub and sub ~= "" and sub ~= zone and sub ~= C.lastSub then
        C.lastSub = sub
        -- 0.5.0: a subzone must hold for 20s (no Lake <-> Highlands ping-pong)
        -- and is logged again at most every 10 minutes
        local token = {}
        C.subPending = token
        Later(20, function()
            if C.subPending ~= token then return end
            C.subPending = nil
            if not Run() or ns.SafeStr(GetSubZoneText()) ~= sub then return end
            local t = GetTime()
            if (t - (C.subAt[sub] or -9999)) < 600 then return end
            C.subAt[sub] = t
            if ns.NoteRunPlace then ns.NoteRunPlace(sub) end
            Line("places", string.format("[PLACE] Entered %s (%s)", sub, zone or "?"))
        end)
    elseif sub == "" or sub == zone then
        C.lastSub = sub
    end
end

local function OnSkill(msg)
    local run = Run()
    if not run then return end
    local pat = Pattern("SKILL_RANK_UP")
    local skill, rank
    if pat then skill, rank = msg:match(pat) end
    if not skill then skill, rank = msg:match("[Yy]our skill in (.+) has increased to (%d+)") end
    rank = tonumber(rank)
    if not skill or not rank then return end
    run.skills = run.skills or {}
    local s = run.skills[skill]
    if not s then
        s = { from = rank - 1, to = rank }
        run.skills[skill] = s
    end
    s.to = rank
    if not ns.LogOn("skills") then return end
    local now = GetTime()
    local last = C.skillLineAt[skill]
    if not last or (now - last.at) >= 600 then
        Line(nil, string.format("[SKILL] %s %d -> %d", skill, last and last.rank or (rank - 1), rank))
        C.skillLineAt[skill] = { at = now, rank = rank }
    end
end

local SYSTEM_MILESTONES = {
    { g = "ERR_LEARN_SPELL_S",     fmt = "%s learned a new spell: %s" },
    { g = "ERR_LEARN_ABILITY_S",   fmt = "%s learned a new ability: %s" },
    { g = "ERR_LEARN_RECIPE_S",    fmt = "%s learned a new recipe: %s" },
    { g = "ERR_DEATHBIND_SUCCESS_S", fmt = "%s bound the hearthstone to %s" },
    { g = "ERR_NEWTAXIPATH",       fmt = "%s discovered a new flight path%s" },
    { g = "FACTION_STANDING_CHANGED", fmt = "%s is now %s with %s" },
}

local function OnSystem(msg)
    if not Run() or not ns.LogOn("milestones") then return end
    for _, m in ipairs(SYSTEM_MILESTONES) do
        local pat = Pattern(m.g)
        if pat then
            local a, b = msg:match(pat)
            if a or msg:match(pat) then
                if m.g == "ERR_NEWTAXIPATH" then
                    local where = ns.SafeStr(GetSubZoneText())
                    a = (where and where ~= "") and (" at " .. where) or ""
                end
                if m.g == "FACTION_STANDING_CHANGED" then
                    Line(nil, "[MILESTONE] " .. string.format(m.fmt, Me(), a or "?", b or "?"))
                else
                    Line(nil, "[MILESTONE] " .. string.format(m.fmt, Me(), a or ""))
                end
                return
            end
        end
    end
end

local function OnPetChange()
    if not Run() then return end
    local name = UnitExists("pet") and ns.SafeStr(UnitName("pet")) or nil
    local now = GetTime()
    if name and (now - C.tameAt) < 20 and name ~= C.petName then
        C.tameAt = 0
        local species = ns.GetPetSpecies and ns.GetPetSpecies("pet")
        Line("milestones", string.format("[MILESTONE] %s tamed a new pet: %s%s", Me(), name, species and (" (" .. species .. ")") or ""))
    end
    C.petName = name or C.petName
end

local function OnPetName()
    if not Run() then return end
    local name = UnitExists("pet") and ns.SafeStr(UnitName("pet")) or nil
    if name and C.petName and name ~= C.petName and name ~= (UNKNOWNOBJECT or "Unknown") then
        Line("milestones", string.format("[MILESTONE] %s renamed a pet: %s is now %s", Me(), C.petName, name))
    end
    C.petName = name or C.petName
end

local GATHER_SPELLS = { ["Mining"] = "Mining", ["Herb Gathering"] = "Herbalism", ["Skinning"] = "Skinning",
    ["Fishing"] = "Fishing", ["Disenchant"] = "Disenchanting", ["Pick Lock"] = "lockpicking",
    ["Opening"] = "opened", ["Pick Pocket"] = "pickpocketed" }

local function OnPlayerSpell(spellName)
    if not spellName then return end
    local now = GetTime()
    if GATHER_SPELLS[spellName] then
        C.ctx.gather, C.ctx.gatherAt = GATHER_SPELLS[spellName], now
    elseif spellName == "Tame Beast" then
        C.tameAt = now
    elseif spellName == "Dismiss Pet" and C.petName and Run() then
        Line("milestones", string.format("[MILESTONE] %s dismissed %s", Me(), C.petName))
    elseif spellName == "Abandon Pet" and C.petName and Run() then
        Line("milestones", string.format("[MILESTONE] %s released %s into the wild", Me(), C.petName))
        C.petName = nil
    end
end

local function OnAchievement(id)
    if not Run() or not GetAchievementInfo then return end
    local ok, _, name = pcall(GetAchievementInfo, id)
    name = ok and ns.SafeStr(name) or nil
    if name then Line("milestones", string.format("[MILESTONE] %s earned the achievement %s", Me(), name)) end
end

local function OnNewMount(mountID)
    if not Run() then return end
    local name
    if C_MountJournal and C_MountJournal.GetMountInfoByID then
        local ok, n = pcall(C_MountJournal.GetMountInfoByID, mountID)
        name = ok and ns.SafeStr(n) or nil
    end
    Line("milestones", string.format("[MILESTONE] %s gained a new mount%s", Me(), name and (": " .. name) or ""))
end

local function OnNewPet(petID)
    if not Run() then return end
    local name
    if C_PetJournal and C_PetJournal.GetPetInfoByPetID then
        local ok, _, custom, _, _, _, _, _, species = pcall(C_PetJournal.GetPetInfoByPetID, petID)
        if ok then name = ns.SafeStr(custom) or ns.SafeStr(species) end
    end
    Line("milestones", string.format("[MILESTONE] %s gained a new companion pet%s", Me(), name and (": " .. name) or ""))
end

-- =========================================================
-- Quests: accepted and completed, plus the quest giver's words
-- =========================================================
local function QuestTitle(questID)
    if questID and C_QuestLog and C_QuestLog.GetTitleForQuestID then
        local ok, t = pcall(C_QuestLog.GetTitleForQuestID, questID)
        t = ok and ns.SafeStr(t) or nil
        if t and t ~= "" then return t end
    end
    if GetTitleText then
        local ok, t = pcall(GetTitleText)
        t = ok and ns.SafeStr(t) or nil
        if t and t ~= "" then return t end
    end
    return nil
end

local function NpcName()
    local n = UnitExists("npc") and ns.SafeStr(UnitName("npc")) or nil
    return n
end

local function GrabQuestText(fn)
    if not fn then return nil end
    local ok, t = pcall(fn)
    t = ok and ns.SafeStr(t) or nil
    if not t or t == "" then return nil end
    t = t:gsub("%$[Nn]", Me()):gsub("%$[Cc]", ns.SafeStr(UnitClass("player")) or "adventurer")
        :gsub("%$[Rr]", ns.SafeStr(UnitRace("player")) or "traveller"):gsub("%$[Gg]([^:;]*):([^;]*);", "%1")
    return Trim(t, 240)
end

local function OnQuestWindow(isReward)
    local title = QuestTitle()
    if not title then return end
    C.quest = {
        title = title, npc = NpcName(), at = GetTime(),
        text = GrabQuestText(isReward and GetRewardText or GetQuestText), reward = isReward,
    }
    if isReward then C.ctx.questAt = GetTime() end
end

local function OnQuestAccepted(questID)
    if not Run() then return end
    local title = QuestTitle(questID) or (C.quest and C.quest.title)
    if not title then return end
    local key = "A:" .. title
    if C.questDone[key] and (GetTime() - C.questDone[key]) < 60 then return end
    C.questDone[key] = GetTime()
    local q = C.quest or {}
    local from = (q.title == title and q.npc) and (" from " .. q.npc) or ""
    Line("quests", string.format("[QUEST] Accepted: %s%s", title, from))
    if q.title == title and q.text and not q.reward and ns.LogOn("npcDialogue") then
        Line("quests", string.format("[QUEST TEXT] %s: \"%s\"", q.npc or "Quest giver", q.text))
    end
end

local function OnQuestTurnedIn(questID)
    C.ctx.questAt = GetTime()
    if not Run() then return end
    local q = C.quest or {}
    local title = QuestTitle(questID) or q.title
    if not title then return end
    local key = "C:" .. title
    if C.questDone[key] and (GetTime() - C.questDone[key]) < 60 then return end
    C.questDone[key] = GetTime()
    local to = (q.title == title and q.npc) and (" for " .. q.npc) or ""
    local run = Run()
    run.questsDone = (run.questsDone or 0) + 1
    Line("quests", string.format("[QUEST] Completed: %s%s", title, to))
    if q.title == title and q.text and q.reward and ns.LogOn("npcDialogue") then
        Line("quests", string.format("[QUEST TEXT] %s: \"%s\"", q.npc or "Quest giver", q.text))
    end
end

-- 0.5.0: one line when a quest objective is done (not per kill tick).
-- The first scan of a run only learns what is already done.
local function ScanObjectives()
    C.objPending = false
    if not Run() or not C_QuestLog or not C_QuestLog.GetNumQuestLogEntries or not C_QuestLog.GetInfo
        or not C_QuestLog.GetQuestObjectives then return end
    local seed = not C.objSeeded
    local okN, num = pcall(C_QuestLog.GetNumQuestLogEntries)
    num = okN and ns.SafeNum(num) or nil
    if not num then return end
    for i = 1, num do
        local ok, info = pcall(C_QuestLog.GetInfo, i)
        if ok and type(info) == "table" and not info.isHeader and info.questID then
            local okO, objs = pcall(C_QuestLog.GetQuestObjectives, info.questID)
            if okO and type(objs) == "table" then
                for j, o in ipairs(objs) do
                    local k = tostring(info.questID) .. ":" .. j
                    local done = (type(o) == "table" and o.finished) and true or false
                    local before = C.objDone[k]
                    C.objDone[k] = done
                    if done and before == false and not seed and ns.LogOn("questObjectives") then
                        local what = Trim(ns.SafeStr(o.text) or "", 80)
                        Line("quests", string.format("[QUEST] Objective done: %s%s", ns.SafeStr(info.title) or "a quest", what ~= "" and (" - " .. what) or ""))
                    end
                end
            end
        end
    end
    C.objSeeded = true
end

local function QueueObjectiveScan()
    if C.objPending or not Run() then return end
    C.objPending = true
    Later(1.5, function() pcall(ScanObjectives) end)
end

-- =========================================================
-- NPC dialogue filter: bosses and named NPCs, throttled and de-duplicated.
-- Returns true when the line should go into the run timeline. Flee emotes
-- are folded into the [FIGHT] line instead.
-- =========================================================
function ns.ChronicleNpc(npcName, msg, event)
    local run = Run()
    if not run then return false end
    local low = (msg or ""):lower()
    if low:find("run away", 1, true) or low:find("flees", 1, true) or low:find("attempts to flee", 1, true) then
        ns.FightFled(npcName)
        return false
    end
    if not ns.LogOn("npcDialogue") then return false end
    if (run.npcLines or 0) >= ns.Limit("npcCap") then return false end
    local now = GetTime()
    local said = (npcName or "") .. "|" .. low
    if C.npcSaid[said] and (now - C.npcSaid[said]) < 600 then return false end

    local loud = event == "CHAT_MSG_MONSTER_YELL" or event == "CHAT_MSG_RAID_BOSS_EMOTE"
        or event == "CHAT_MSG_RAID_BOSS_WHISPER" or event == "CHAT_MSG_MONSTER_WHISPER"
    local boss = (RPCopyDB and RPCopyDB.knownBosses and RPCopyDB.knownBosses[npcName or ""])
        or (ns.GetActiveBossName and ns.GetActiveBossName() == npcName)
    local named = boss or (UnitExists("target") and ns.SafeStr(UnitName("target")) == npcName)
        or (UnitExists("npc") and ns.SafeStr(UnitName("npc")) == npcName)
        or (C.quest and C.quest.npc == npcName)
    if not loud and not named then
        -- Plain mob chatter: at most one line per NPC name every 3 minutes
        if (now - (C.npcAt[npcName or ""] or -999)) < 180 then return false end
    elseif (now - (C.npcAt[npcName or ""] or -999)) < 8 then
        return false
    end
    C.npcAt[npcName or ""] = now
    C.npcSaid[said] = now
    run.npcLines = (run.npcLines or 0) + 1
    return true
end

-- =========================================================
-- Loot source: where an item came from
-- =========================================================
local LOOT_PATTERNS = {}
local function LootPatterns()
    if LOOT_PATTERNS.ready then return LOOT_PATTERNS end
    LOOT_PATTERNS.ready = true
    LOOT_PATTERNS.created = Pattern("LOOT_ITEM_CREATED_SELF")
    LOOT_PATTERNS.createdMulti = Pattern("LOOT_ITEM_CREATED_SELF_MULTIPLE")
    LOOT_PATTERNS.pushed = Pattern("LOOT_ITEM_PUSHED_SELF")
    LOOT_PATTERNS.pushedMulti = Pattern("LOOT_ITEM_PUSHED_SELF_MULTIPLE")
    LOOT_PATTERNS.won = Pattern("LOOT_ROLL_WON")
    LOOT_PATTERNS.youWon = Pattern("LOOT_ROLL_YOU_WON")
    return LOOT_PATTERNS
end

local function Recent(at, sec) return at and (GetTime() - at) <= sec end

-- plainMsg: the loot line without colors or link codes. Returns a short
-- source such as "crafted", "from Arugal", "quest reward" or nil.
function ns.ClassifyLootSource(plainMsg, isSelf)
    local p = LootPatterns()
    local msg = plainMsg or ""
    local low = msg:lower()
    if (p.created and msg:match(p.created)) or (p.createdMulti and msg:match(p.createdMulti)) or low:find("^you create") then
        return "crafted"
    end
    if (p.won and msg:match(p.won)) or (p.youWon and msg:match(p.youWon)) or low:find(" won:", 1, true) then
        return "won roll"
    end
    local pushed = (p.pushed and msg:match(p.pushed)) or (p.pushedMulti and msg:match(p.pushedMulti)) or low:find("^you receive item")
    if isSelf then
        if C.ctx.loot or Recent(C.ctx.lootAt, 2) then
            if C.ctx.lootGather then return "gathered (" .. C.ctx.lootGather .. ")" end
            if C.ctx.lootFrom then return "from " .. C.ctx.lootFrom end
            return "looted"
        end
        if Recent(C.ctx.questAt, 4) then return "quest reward" end
        if C.ctx.merchant then return "bought" end
        if C.ctx.mail then return "mail" end
        if C.ctx.trade or Recent(C.ctx.tradeAt, 4) then return "traded" end
        if pushed then return "received" end
    end
    if Recent(C.ctx.killAt, 90) and C.ctx.killName then return "from " .. C.ctx.killName end
    return nil
end

function ns.NoteBossLootSource(bossName)
    C.ctx.killName, C.ctx.killAt = bossName, GetTime()
end

local function OnLootOpened()
    C.ctx.loot, C.ctx.lootAt = true, GetTime()
    C.ctx.lootGather, C.ctx.lootFrom = nil, nil
    if Recent(C.ctx.gatherAt, 6) then
        C.ctx.lootGather = C.ctx.gather
    elseif UnitExists("target") and UnitIsDead("target") and not UnitIsPlayer("target") then
        C.ctx.lootFrom = ns.SafeStr(UnitName("target"))
    end
end

-- Quest items: item class 12 (Quest)
function ns.IsQuestItem(link)
    if not link then return false end
    if C_Item and C_Item.GetItemInfoInstant then
        local ok, _, itemType, _, _, _, classID = pcall(C_Item.GetItemInfoInstant, link)
        if ok and (classID == 12 or itemType == "Quest") then return true end
    elseif GetItemInfoInstant then
        local ok, _, itemType, _, _, _, classID = pcall(GetItemInfoInstant, link)
        if ok and (classID == 12 or itemType == "Quest") then return true end
    end
    return false
end

-- =========================================================
-- Prompts: start recording on group join or login, and the
-- interrupted-run question after a logout or disconnect
-- =========================================================
local function Prompt(text, b1, f1, b2, f2)
    if ns.UI and ns.UI.ShowPrompt then
        ns.UI.ShowPrompt(text, b1, f1, b2, f2)
    else
        print("|cffffd100RPCopy|r " .. text)
    end
end

local function OfferStart(reason)
    if Run() or (ns.GetActiveAdventure and ns.GetActiveAdventure()) or InInstance() then return end
    Prompt("|cffffd100RPCopy|r " .. reason .. "\nStart recording an adventure?", "Start recording", function()
        if ns.UI and ns.UI.StartRunFromUI then ns.UI.StartRunFromUI() else ns.StartAdventure(nil, false) end
    end, "Not now", nil)
end

function ns.OfferInterruptedRun(run)
    if not run then return end
    Prompt(string.format("|cffffd100RPCopy|r Your run |cffeceff1%s|r was cut short by a logout or disconnect. It is saved.\nResume recording it, or keep it as it is?",
        tostring(run.title or "Adventure")), "Resume", function()
        local ok, msg = ns.ResumeInterruptedRun(run.id)
        print("|cffffd100RPCopy|r " .. tostring(msg))
        if ns.UI and ns.UI.RefreshAdventuresTab then pcall(ns.UI.RefreshAdventuresTab) end
        if ns.UI and ns.UI.RefreshRecordIcon then pcall(ns.UI.RefreshRecordIcon) end
    end, "Keep saved", nil)
end

local function After(sec, fn)
    if C_Timer and C_Timer.After then C_Timer.After(sec, fn) else fn() end
end

-- =========================================================
-- Events
-- =========================================================
do
    local f = CreateFrame("Frame")
    local EV = {
        "PLAYER_ENTERING_WORLD", "ZONE_CHANGED", "ZONE_CHANGED_INDOORS", "ZONE_CHANGED_NEW_AREA",
        "PLAYER_LEVEL_UP", "CHAT_MSG_SKILL", "CHAT_MSG_SYSTEM", "ACHIEVEMENT_EARNED", "NEW_MOUNT_ADDED",
        "NEW_PET_ADDED", "UNIT_PET", "UNIT_NAME_UPDATE", "UNIT_SPELLCAST_SUCCEEDED", "UNIT_HEALTH",
        "QUEST_DETAIL", "QUEST_COMPLETE", "QUEST_ACCEPTED", "QUEST_TURNED_IN",
        "MERCHANT_SHOW", "MERCHANT_CLOSED", "MAIL_SHOW", "MAIL_CLOSED", "TRADE_SHOW", "TRADE_CLOSED",
        "LOOT_OPENED", "LOOT_CLOSED", "GROUP_ROSTER_UPDATE", "GROUP_JOINED",
        "QUEST_LOG_UPDATE", "UNIT_QUEST_LOG_CHANGED",
    }
    for _, ev in ipairs(EV) do pcall(f.RegisterEvent, f, ev) end

    local wasGrouped = nil
    local loginChecked = false

    local function Handle(event, a1, a2, a3)
        if event == "UNIT_HEALTH" then
            if C.fight and type(a1) == "string" and (a1 == "target" or a1 == "focus" or a1:match("^nameplate%d+$")) then
                ns.FightSeeUnit(a1)
            end
        elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
            if a1 == "player" then
                local id = ns.SafeNum(a3)
                local name = id and ((C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(id)) or (GetSpellInfo and GetSpellInfo(id)))
                OnPlayerSpell(ns.SafeStr(name))
            end
        elseif event == "ZONE_CHANGED" or event == "ZONE_CHANGED_INDOORS" then
            OnZone(false)
        elseif event == "ZONE_CHANGED_NEW_AREA" then
            OnZone(true)
        elseif event == "PLAYER_ENTERING_WORLD" then
            C.lastZone = ns.SafeStr(GetRealZoneText())
            C.lastSub = ns.SafeStr(GetSubZoneText())
            C.petName = UnitExists("pet") and ns.SafeStr(UnitName("pet")) or nil
            if wasGrouped == nil then wasGrouped = (IsInGroup and IsInGroup()) and true or false end
            if not loginChecked then
                loginChecked = true
                After(4, function()
                    if RPCopyDB and RPCopyDB.promptOnLogin and not (IsInGroup and IsInGroup()) then
                        OfferStart("Welcome back.")
                    end
                end)
            end
        elseif event == "GROUP_ROSTER_UPDATE" or event == "GROUP_JOINED" then
            local grouped = (IsInGroup and IsInGroup()) and true or false
            if grouped and wasGrouped == false and RPCopyDB and RPCopyDB.promptOnGroup ~= false then
                After(1.5, function() OfferStart("You joined a group.") end)
            end
            wasGrouped = grouped
        elseif event == "PLAYER_LEVEL_UP" then
            local lvl = ns.SafeNum(a1)
            local run = Run()
            if lvl and run then
                run.levelEnd = lvl
                if not run.levelStart then run.levelStart = lvl - 1 end
                Line("levels", string.format("[LEVEL] %s reached level %d", Me(), lvl))
            end
        elseif event == "CHAT_MSG_SKILL" then
            local msg = ns.SafeStr(a1)
            if msg then OnSkill(msg) end
        elseif event == "CHAT_MSG_SYSTEM" then
            local msg = ns.SafeStr(a1)
            if msg then OnSystem(msg) end
        elseif event == "ACHIEVEMENT_EARNED" then
            OnAchievement(a1)
        elseif event == "NEW_MOUNT_ADDED" then
            OnNewMount(a1)
        elseif event == "NEW_PET_ADDED" then
            OnNewPet(a1)
        elseif event == "UNIT_PET" then
            if a1 == "player" then OnPetChange() end
        elseif event == "UNIT_NAME_UPDATE" then
            if a1 == "pet" then OnPetName() end
        elseif event == "QUEST_DETAIL" then
            OnQuestWindow(false)
        elseif event == "QUEST_COMPLETE" then
            OnQuestWindow(true)
        elseif event == "QUEST_ACCEPTED" then
            OnQuestAccepted(ns.SafeNum(a2) or ns.SafeNum(a1))
        elseif event == "QUEST_TURNED_IN" then
            OnQuestTurnedIn(ns.SafeNum(a1))
        elseif event == "MERCHANT_SHOW" then C.ctx.merchant = true
        elseif event == "MERCHANT_CLOSED" then C.ctx.merchant = false
        elseif event == "MAIL_SHOW" then C.ctx.mail = true
        elseif event == "MAIL_CLOSED" then C.ctx.mail = false
        elseif event == "TRADE_SHOW" then C.ctx.trade = true
        elseif event == "TRADE_CLOSED" then C.ctx.trade, C.ctx.tradeAt = false, GetTime()
        elseif event == "LOOT_OPENED" then OnLootOpened()
        elseif event == "LOOT_CLOSED" then C.ctx.loot, C.ctx.lootAt = false, GetTime()
        elseif event == "QUEST_LOG_UPDATE" or (event == "UNIT_QUEST_LOG_CHANGED" and a1 == "player") then
            QueueObjectiveScan()
        end
    end

    f:SetScript("OnEvent", function(_, event, a1, a2, a3)
        local ok, err = pcall(Handle, event, a1, a2, a3)
        if not ok then
            if ns.Debug then ns.Debug("error", "chronicle " .. event .. ": " .. tostring(err)) end
        end
    end)
end

-- A new run starts with a clean chronicle
function ns.ResetChronicle()
    C.fight, C.killSeen, C.enemySeen = nil, {}, {}
    C.atmoAt, C.atmoPhase = 0, nil
    C.skillLineAt, C.questDone, C.npcAt, C.npcSaid = {}, {}, {}, {}
    C.subAt = {}
    C.streak, C.subPending = nil, nil
    C.objDone, C.objSeeded, C.objPending = {}, false, false
    QueueObjectiveScan()
    C.lastZone = ns.SafeStr(GetRealZoneText())
    C.lastSub = ns.SafeStr(GetSubZoneText())
    -- the place a run starts in is already known: no [PLACE] for a quick return
    if C.lastSub and C.lastSub ~= "" then C.subAt[C.lastSub] = GetTime() end
end

ns.ChronicleState = C -- for the test harness
