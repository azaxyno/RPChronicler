local ADDON_NAME, ns = ...

-- =========================================================
-- Runs (0.6.1, split out of Adventures.lua): a run's life (start, pause,
-- resume, end, restore after /reload) and every Record* function that
-- writes its timeline. The Summary and Full Log are in RunReport.lua,
-- stories in Stories.lua.
-- =========================================================

local activeRun = nil
local recentDeathTimes = {}
local lastWipeTime = 0
local lastBossKillName = ""
local lastBossKillTime = 0
local lastSpokenTimelineLine = nil

-- Combat & Encounter Telemetry State
local activeBossName = nil
local activeBossPct = nil
local bossThresholdsHit = {}
local vitalsCooldowns = {}
local bossPullEngaged = {}
local brink = {} -- party member -> time they dropped under 10% HP
local lastHP = {} -- party member -> last health percent seen above 0
local deadNow = {} -- party member -> true while dead (death lines for party1-4)
local lootRepeat = {} -- looter|item -> the timeline line to update with xN

local RESUME_WINDOW = 120 -- seconds: a run seen this recently resumes after /reload or disconnect

local ZONE_ICONS = {
    { pattern = "scarlet",     icon = "Interface\\Icons\\INV_Helmet_52" },
    { pattern = "deadmines",   icon = "Interface\\Icons\\INV_Misc_Coin_02" },
    { pattern = "shadowfang",  icon = "Interface\\Icons\\INV_Misc_Bone_01" },
    { pattern = "stockade",    icon = "Interface\\Icons\\INV_Misc_Key_03" },
    { pattern = "gnomeregan",  icon = "Interface\\Icons\\INV_Misc_Gear_01" },
    { pattern = "razorfen",    icon = "Interface\\Icons\\INV_Misc_Horn_01" },
    { pattern = "maraudon",    icon = "Interface\\Icons\\INV_Misc_Gem_Emerald_01" },
    { pattern = "zulfarrak",   icon = "Interface\\Icons\\INV_Sword_39" },
    { pattern = "zul'farrak",  icon = "Interface\\Icons\\INV_Sword_39" },
    { pattern = "stratholme",  icon = "Interface\\Icons\\Spell_Holy_HolyBolt" },
    { pattern = "scholomance", icon = "Interface\\Icons\\INV_Misc_Book_09" },
    { pattern = "blackrock",   icon = "Interface\\Icons\\Spell_Fire_LavaSpawn" },
    { pattern = "molten",      icon = "Interface\\Icons\\Spell_Fire_Fire" },
    { pattern = "onyxia",      icon = "Interface\\Icons\\INV_Misc_Head_Dragon_01" },
    { pattern = "wailing",     icon = "Interface\\Icons\\INV_Misc_Scale_08" },
    { pattern = "ragefire",    icon = "Interface\\Icons\\Spell_Fire_SoulBurn" },
    { pattern = "uldaman",     icon = "Interface\\Icons\\INV_Misc_StoneTablet_01" },
    { pattern = "sunken",      icon = "Interface\\Icons\\INV_Misc_MonsterScales_07" },
    { pattern = "dire maul",   icon = "Interface\\Icons\\INV_Crown_01" },
}

local function PreciseStamp()
    return (date and date("%H:%M:%S")) or ns.TimeOnlyStamp()
end

function ns.GetAdventureIcon(adv)
    if not adv then return "Interface\\Icons\\INV_Misc_Map_01" end
    local hay = ((adv.zone or "") .. " " .. (adv.title or "")):lower()
    for _, item in ipairs(ZONE_ICONS) do
        if hay:find(item.pattern, 1, true) then
            return item.icon
        end
    end
    return "Interface\\Icons\\INV_Misc_Map_01"
end

function ns.GetActiveAdventure()
    return activeRun
end

-- /rp wipe: forget the live run without saving it
function ns.DropActiveAdventure()
    activeRun = nil
end

function ns.GetActiveBossName()
    return activeBossName
end

-- Seconds a run has lasted: stored for ended runs, live for the active one.
-- (0.3.x showed "0m 00s" for live runs because duration starts at 0.)
function ns.GetRunDuration(adv)
    if not adv then return 0 end
    if adv.duration and adv.duration > 0 then return adv.duration end
    if adv.startTime then
        return math.max(0, (adv.endTime or time()) - adv.startTime)
    end
    return 0
end

-- Keeps the 40 newest runs. 0.6.3: says so in chat when a run goes,
-- naming it, so a run with no story yet is never lost without a word
-- (its story, if imported, stays in the Story Book).
local RUN_CAP = 40
function ns.TrimRuns()
    local list = RPChroniclerDB and RPChroniclerDB.adventures
    if type(list) ~= "table" then return end
    while #list > RUN_CAP do
        local old = table.remove(list)
        local hasStory = false
        for _, st in pairs(RPChroniclerDB.stories or {}) do
            if type(st) == "table" and old and st.runId == old.id then hasStory = true break end
        end
        if old and not hasStory and not old.story then
            print(string.format("|cffffd100RP Chronicler|r Your oldest run (%s, %s) had no story and was removed to keep the newest %d.",
                tostring(old.title or "Adventure"), tostring(old.startDate or "?"), RUN_CAP))
        end
        ns.Debug("run", "run cap: removed " .. tostring(old and old.title))
    end
end

local RUN_KIND_LABEL = { dungeon = "Dungeon", raid = "Raid", world = "Open world adventure" }
function ns.GetRunKindLabel(adv)
    return RUN_KIND_LABEL[(adv and adv.kind) or "world"] or "Adventure"
end


-- 0.6.3: story lines a full timeline never drops (bosses, wipes, deaths,
-- quests, levels, places, shots, notes, highlights, pauses, and the run's
-- first and last lines). Over the cap, the oldest other line goes instead
-- (chat, fight details, loot, HP warnings), so a chatty run keeps its
-- beginning.
local KEEP_TAGS = { "BOSS ENGAGED", "BOSS KILL", "BOSS RESET", "WIPE", "DEATH", "QUEST", "LEVEL", "PLACE",
    "SHOT", "NOTE", "HIGHLIGHT", "MILESTONE", "PAUSED", "RESUMED", "RELOAD" }
local function KeepLine(line)
    local body = tostring(line):gsub("^%[[^%]]*%]%s*", "")
    if body:find("^Adventure began") or body:find("^Adventure ended") then return true end
    local tag = body:match("^%[([%u ]+)")
    if not tag then return false end
    for _, t in ipairs(KEEP_TAGS) do
        if tag == t or tag:sub(1, #t + 1) == t .. " " or tag:find("^" .. t .. " #") then return true end
    end
    return false
end
-- The line each live handle points at (this session only), so a handle
-- still finds its line after a line before or after it was dropped
local handleLine = setmetatable({}, { __mode = "k" })

local function PushTimeline(adv, stamp, entryText, force)
    if not adv then return end
    -- A paused run records nothing except its own pause/resume markers
    if adv.paused and not force then return end
    adv.lastSeen = time()
    adv.fullTimeline = adv.fullTimeline or {}
    local tl = adv.fullTimeline
    local line = string.format("[%s] %s", stamp or PreciseStamp(), entryText)
    table.insert(tl, line)
    local cap = ns.Limit("timelineMax")
    while #tl > cap do
        local drop
        for i = 1, #tl - 1 do
            if not KeepLine(tl[i]) then drop = i break end
        end
        -- every line is a story line: drop the oldest after the first
        table.remove(tl, drop or 2)
        adv.tlRemoved = (adv.tlRemoved or 0) + 1
    end
    -- A handle that survives trimming: the line's absolute position
    local handle = (adv.tlRemoved or 0) + #tl
    handleLine[adv] = handleLine[adv] or {}
    handleLine[adv][handle] = line
    return handle
end

-- 0.5.0: rewrites a timeline line in place (trash streaks, repeated loot).
-- Keeps the line's original time stamp. False when the line is gone.
local function UpdateTimeline(adv, handle, entryText)
    if not adv or not handle or not adv.fullTimeline then return false end
    local idx = handle - (adv.tlRemoved or 0)
    local want = handleLine[adv] and handleLine[adv][handle]
    if want and adv.fullTimeline[idx] ~= want then
        -- a line was dropped after this one: look a little further on
        idx = nil
        for i = math.max(1, handle - (adv.tlRemoved or 0)), #adv.fullTimeline do
            if adv.fullTimeline[i] == want then idx = i break end
        end
        if not idx then handleLine[adv][handle] = nil return false end
    end
    local old = idx and adv.fullTimeline[idx]
    if not old then return false end
    local stamp = old:match("^(%[[^%]]*%])") or ("[" .. PreciseStamp() .. "]")
    adv.fullTimeline[idx] = stamp .. " " .. entryText
    if handleLine[adv] then handleLine[adv][handle] = adv.fullTimeline[idx] end
    adv.lastSeen = time()
    return true
end

-- =========================================================
-- Party roster (0.6.4). Each group member is one entry, found again by
-- their GUID or name. A member only joins the roster once you have seen
-- them near you during the run (inside the instance for a dungeon or
-- raid), so someone invited by mistake and removed, or who never zoned
-- in, is left out. Members in the group for under a minute in all are
-- dropped when the run ends. The role kept is the one each member ended
-- the run with (people fix their roles mid-run), unless they held it only
-- briefly; then it is the role they held longest.
-- =========================================================
local ROSTER_MIN_SECS = 60    -- shorter group time: dropped at the end
local ROLE_FINAL_SECS = 120   -- a last role held this long wins

local function FirstOf(name)
    return (tostring(name or ""):match("^(%S+)") or ""):lower()
end
local function HasLastName(name)
    return tostring(name or ""):find("%S%s+%S") ~= nil
end

-- The entry for this member in list, or nil. "Morai" and "Morai Galeclaw"
-- are one member when nobody else in the list is a Morai: first names
-- repeat on Forever, only first and last name together are unique.
local function FindMember(list, guid, name)
    local low = name:lower()
    for _, p in ipairs(list) do
        if guid and p.guid == guid then return p end
    end
    for _, p in ipairs(list) do
        if (p.name or ""):lower() == low and not (guid and p.guid and p.guid ~= guid) then return p end
    end
    local first, hit, hits = FirstOf(name), nil, 0
    for _, p in ipairs(list) do
        if FirstOf(p.name) == first and not (guid and p.guid and p.guid ~= guid) then
            hit, hits = p, hits + 1
        end
    end
    if hits == 1 and (not HasLastName(name) or not HasLastName(hit.name)) then return hit end
    return nil
end

-- Seen near you: you, or a member your client can see (about 100 yards),
-- and for a dungeon or raid only while you are inside it
local function MemberHere(unit, run)
    if unit == "player" then return true end
    if run.kind ~= "world" then
        local _, inside = ns.InstanceKind()
        if not inside then return false end
    end
    if not UnitIsVisible then return true end
    local ok, vis = pcall(UnitIsVisible, unit)
    return ok and vis == true
end

-- Adds the time since the last check to the member's current role
local function CountRoleTime(p, now)
    if p.roleNow and p.roleAt then
        p.roleTime = p.roleTime or {}
        p.roleTime[p.roleNow] = (p.roleTime[p.roleNow] or 0) + math.max(0, now - p.roleAt)
    end
    p.roleAt = now
end

-- The role to show: the last assigned one while it is held (live) or if
-- it was held long enough, else the assigned one held longest, else the
-- guess
local function ChooseRole(p, final)
    local times = p.roleTime or {}
    local last = p.roleLast
    if last and ((not final and p.roleNow == last) or (times[last] or 0) >= ROLE_FINAL_SECS) then
        p.role, p.roleGuessed = last, false
        return
    end
    local best, bestT = nil, -1
    for r, t in pairs(times) do
        if t > bestT then best, bestT = r, t end
    end
    best = best or last
    if best then
        p.role, p.roleGuessed = best, false
    elseif p.guessRole then
        p.role, p.roleGuessed = p.guessRole, true
    end
end

-- Adds the time since the last check to the member's group time
local function CountGroupTime(p, now, inGroup)
    if p.inGroup and p.groupAt then
        p.groupSecs = (p.groupSecs or 0) + math.max(0, now - p.groupAt)
    end
    p.inGroup = inGroup or nil
    p.groupAt = inGroup and now or nil
end

function ns.SyncAdventureRoster()
    if not activeRun or activeRun.paused then return end
    local run = activeRun
    run.participants = run.participants or {}
    run.candidates = run.candidates or {}
    local now = time()
    local seen = {}

    local function AddOrUpdateUnit(unit)
        if not UnitExists(unit) or not UnitIsPlayer(unit) then return end
        local fullName = ns.GetUnitFullName(unit) or ns.StripRealm(UnitName(unit))
        if not fullName or fullName == "" then return end
        local guid = UnitGUID and ns.SafeStr(UnitGUID(unit)) or nil

        local p = FindMember(run.participants, guid, fullName)
        if not p then
            p = FindMember(run.candidates, guid, fullName)
            if not p then
                p = { name = fullName }
                table.insert(run.candidates, p)
            end
            -- a candidate joins the roster once seen near you
            if MemberHere(unit, run) then
                for i, c in ipairs(run.candidates) do
                    if c == p then table.remove(run.candidates, i) break end
                end
                table.insert(run.participants, p)
                ns.Debug("run", "roster: " .. fullName)
            end
        end
        seen[p] = true
        -- "Morai" becomes "Morai Galeclaw" once the full name is known
        if HasLastName(fullName) and not HasLastName(p.name) then p.name = fullName end
        p.guid = p.guid or guid

        local lvl = ns.SafeNum(UnitLevel(unit))
        if lvl and lvl > 0 then p.level = tostring(lvl) end
        -- 0.6.4: race and sex, for their shadow in the story scenes
        if UnitRace then
            local okR, raceName, _, raceID = pcall(UnitRace, unit)
            raceID = okR and ns.SafeNum(raceID) or nil
            raceName = okR and ns.SafeStr(raceName) or nil
            if raceID then p.race = raceID end
            if raceName and raceName ~= "" then p.raceName = raceName end
        end
        if UnitSex then
            local okS, sex = pcall(UnitSex, unit)
            sex = okS and ns.SafeNum(sex) or nil
            if sex == 2 or sex == 3 then p.sex = sex end
        end
        local clsLoc, clsFile = UnitClass(unit)
        clsLoc = ns.SafeStr(clsLoc) or ""
        clsFile = ns.SafeStr(clsFile) or ""
        if clsLoc ~= "" then p.class = clsLoc end
        if clsFile ~= "" then p.classFile = clsFile end

        local role, guessed = ns.GetUnitRole(unit)
        CountRoleTime(p, now)
        if role and role ~= "NONE" and not guessed then
            p.roleNow, p.roleLast = role, role
        else
            p.roleNow = nil
            if role and role ~= "NONE" then p.guessRole = role end
        end
        ChooseRole(p)
        p.role = p.role or "NONE"
        if p.roleGuessed == nil then p.roleGuessed = guessed end

        -- Guildmates: party members in your own guild
        local myGuild = ns.SafeStr(GetGuildInfo("player"))
        local theirGuild = ns.SafeStr(GetGuildInfo(unit))
        if theirGuild and theirGuild ~= "" then p.guild = theirGuild end
        if unit ~= "player" and myGuild and theirGuild and myGuild ~= "" and myGuild == theirGuild then p.guildmate = true end

        -- 0.5.0: the run keeps its own copy of the companion's notes, so an
        -- old Full Log still reads right after the companion is deleted
        if RPChroniclerDB and RPChroniclerDB.players and unit ~= "player" then
            local pKey = ns.FindPlayerKey(p.name, true)
            local comp = pKey and RPChroniclerDB.players[pKey]
            if comp then
                if (comp.note or "") ~= "" then p.note = comp.note end
                p.cid = comp.cid or p.cid
                p.relationship = (comp.relationship or "") ~= "" and comp.relationship or p.relationship
                p.tone = (comp.tone or "") ~= "" and comp.tone or p.tone
            end
        end
        p.note = p.note or ""
        -- Pet: "Name (Family)", e.g. "Snips (Crab)"
        local petUnit = (unit == "player" and "pet") or (unit:match("^party%d$") and ("partypet" .. unit:sub(6))) or (unit:match("^raid%d+$") and ("raidpet" .. unit:sub(5))) or nil
        local petDesc = petUnit and UnitExists(petUnit) and ns.GetPetDescriptor(petUnit) or nil
        if petDesc then p.pet = petDesc end
    end

    AddOrUpdateUnit("player")
    if IsInRaid and IsInRaid() then
        for i = 1, 40 do AddOrUpdateUnit("raid" .. i) end
    else
        for i = 1, 4 do AddOrUpdateUnit("party" .. i) end
    end
    if ns.InspectPartyGear then ns.InspectPartyGear() end
    -- group time, and the role clock stops for members who left
    for _, list in ipairs({ run.participants, run.candidates }) do
        for _, p in ipairs(list) do
            CountGroupTime(p, now, seen[p])
            if not seen[p] then
                CountRoleTime(p, now)
                p.roleNow = nil
            end
        end
    end
end

-- Run end: closes the clocks, drops members who were in the group under
-- a minute (never you), and clears the working fields (groupSecs stays,
-- so a resumed run keeps counting)
-- 0.6.4: a roster as it should read, for runs and stories recorded
-- before the fix: "Morai" folds into "Morai Galeclaw" when only one Morai
-- is listed, and a name listed twice is listed once. Returns new tables;
-- the saved roster is unchanged.
function ns.MergedRoster(list)
    local out, byName = {}, {}
    for _, p in ipairs(type(list) == "table" and list or {}) do
        if type(p) == "table" and type(p.name) == "string" and p.name ~= "" then
            local low = p.name:lower()
            local e = byName[low]
            if not e then
                e = {}
                for k, v in pairs(p) do e[k] = v end
                byName[low] = e
                table.insert(out, e)
            else
                for k, v in pairs(p) do if e[k] == nil then e[k] = v end end
            end
        end
    end
    for i = #out, 1, -1 do
        local p = out[i]
        if not HasLastName(p.name) then
            local first, hit, hits = FirstOf(p.name), nil, 0
            for _, q in ipairs(out) do
                if q ~= p and HasLastName(q.name) and FirstOf(q.name) == first then hit, hits = q, hits + 1 end
            end
            if hits == 1 then
                for k, v in pairs(p) do if hit[k] == nil or hit[k] == "" then hit[k] = v end end
                table.remove(out, i)
            end
        end
    end
    return out
end

-- 0.6.4: race and sex for people already in your runs and stories. Older
-- runs never recorded them, so their shadows were unknown; when you see
-- that player again (group, target, mouseover) the gap is filled in.
local learned = {}
function ns.LearnLooks(unit)
    if not unit or not UnitExists(unit) or not UnitIsPlayer(unit) or not UnitRace or not UnitSex then return end
    local full = ns.GetUnitFullName and ns.GetUnitFullName(unit)
    if not full or full == "" or learned[full] then return end
    local okR, raceName, _, raceID = pcall(UnitRace, unit)
    local okS, sex = pcall(UnitSex, unit)
    raceID, sex = okR and ns.SafeNum(raceID) or nil, okS and ns.SafeNum(sex) or nil
    if not raceID or not (sex == 2 or sex == 3) then return end
    raceName = okR and ns.SafeStr(raceName) or nil
    learned[full] = true
    local low, first = full:lower(), FirstOf(full)
    local function Fill(list)
        if type(list) ~= "table" then return end
        -- a short name counts only when no other "<first> <last>" is listed
        local others = 0
        for _, p in ipairs(list) do
            if type(p) == "table" and HasLastName(p.name) and FirstOf(p.name) == first and (p.name or ""):lower() ~= low then others = others + 1 end
        end
        for _, p in ipairs(list) do
            if type(p) == "table" and not p.race and type(p.name) == "string" then
                local n = p.name:lower()
                if n == low or (others == 0 and not HasLastName(p.name) and FirstOf(p.name) == first) then
                    p.race, p.sex, p.raceName = raceID, sex, p.raceName or raceName
                end
            end
        end
    end
    local db = RPChroniclerDB or {}
    for _, adv in ipairs(type(db.adventures) == "table" and db.adventures or {}) do Fill(adv.participants) end
    for _, st in ipairs(type(db.stories) == "table" and db.stories or {}) do Fill(st.participants) end
    if activeRun then Fill(activeRun.participants) end
end

local function FinishRoster(run)
    local now = time()
    local kept = {}
    for _, p in ipairs(run.participants or {}) do
        CountGroupTime(p, now, false)
        CountRoleTime(p, now)
        p.roleNow = nil
        ChooseRole(p, true)
        p.role = p.role or "NONE"
        local me = p.name == run.char or (p.guid and UnitGUID and p.guid == ns.SafeStr(UnitGUID("player")))
        if me or p.groupSecs == nil or p.groupSecs >= ROSTER_MIN_SECS then
            table.insert(kept, p)
        else
            ns.Debug("run", "roster: dropped " .. tostring(p.name) .. " (" .. tostring(p.groupSecs or 0) .. "s in group)")
        end
        p.guid, p.roleNow, p.roleAt, p.roleLast, p.roleTime = nil, nil, nil, nil, nil
        p.guessRole, p.inGroup, p.groupAt = nil, nil, nil
    end
    run.participants = kept
    run.candidates = nil
end

-- =========================================================
-- 0.6.4 (Mor): Record party gear. While a run records, each party member
-- is inspected once (the game's own Inspect), out of combat and in range,
-- one at a time every few seconds, and the gear they wore is kept on
-- their roster entry. Never while the player's own Inspect window is
-- open; ClearInspectPlayer after each. Off (partyGear) = nobody inspected.
-- =========================================================
do
    local busy, scheduled = nil, false
    local tries = {}
    local STEP, WAIT = 3, 4
    local Step
    local function Later(sec)
        if scheduled or not (C_Timer and C_Timer.After) then return end
        scheduled = true
        C_Timer.After(sec, function() scheduled = false Step() end)
    end
    local function InspectOpen() return InspectFrame and InspectFrame.IsShown and InspectFrame:IsShown() end
    local function UnitOf(name)
        local hit
        ns.ForEachGroupUnit(function(u) if not hit and ns.GetUnitFullName(u) == name then hit = u end end)
        return hit
    end
    local function Done()
        if busy and ClearInspectPlayer and not InspectOpen() then pcall(ClearInspectPlayer) end
        busy = nil
        Later(STEP)
    end
    Step = function()
        local run = activeRun
        if busy or not run or run.paused or not ns.Get("partyGear") or not NotifyInspect then return end
        if (InCombatLockdown and InCombatLockdown()) or InspectOpen() then Later(STEP) return end
        local me = ns.PlayerName()
        for _, p in ipairs(run.participants or {}) do
            if p.name ~= me and not p.gear and (tries[p.name] or 0) < 3 then
                local u = UnitOf(p.name)
                local can = u and CanInspect and select(2, pcall(CanInspect, u, false))
                local near = u and (not CheckInteractDistance or select(2, pcall(CheckInteractDistance, u, 1)))
                if can and near then
                    tries[p.name] = (tries[p.name] or 0) + 1
                    busy = { p = p, unit = u, guid = UnitGUID and ns.SafeStr(UnitGUID(u)) }
                    local token = busy
                    if not pcall(NotifyInspect, u) then busy = nil Later(STEP) return end
                    C_Timer.After(WAIT, function() if busy == token then Done() end end)
                    return
                end
            end
        end
        -- someone may come into range later
        for _, p in ipairs(run.participants or {}) do
            if p.name ~= me and not p.gear and (tries[p.name] or 0) < 3 then Later(10) return end
        end
    end
    ns.On("INSPECT_READY", function(_, guid)
        if not busy or (busy.guid and guid and ns.SafeStr(guid) ~= busy.guid) then return end
        local token = busy
        -- item links can trail the event by a moment
        C_Timer.After(0.5, function()
            if busy ~= token then return end
            if ns.GetUnitFullName(token.unit) == token.p.name then
                local gear = ns.UnitGear(token.unit)
                if #gear > 0 then
                    token.p.gear = gear
                    ns.Debug("run", "party gear: " .. token.p.name .. " (" .. #gear .. ")")
                end
            end
            Done()
        end)
    end)
    function ns.InspectPartyGear()
        if activeRun and ns.Get("partyGear") then Later(STEP) end
    end
    function ns.ResetPartyGearTries() tries = {} end
end

function ns.StartAdventure(customTitle, isAuto)
    ns.EnsureDB()
    ns.ResetPartyGearTries()
    if activeRun then
        ns.EndAdventure("Started New Adventure")
    end

    -- 0.6.4: inside an instance the run is named after it, never after
    -- the zone text (which can still say Orgrimmar in Ragefire Chasm)
    local instName, instID = ns.InstanceInfo()
    local zone = instName or ns.GetCurrentWhere()
    local title = (customTitle and customTitle ~= "") and customTitle or zone
    recentDeathTimes = {}
    lastWipeTime = 0
    lastBossKillName = ""
    lastBossKillTime = 0
    lastSpokenTimelineLine = nil
    activeBossName = nil
    activeBossPct = nil
    bossThresholdsHit = {}
    vitalsCooldowns = {}
    bossPullEngaged = {}
    brink = {}
    deadNow = {}

    activeRun = {
        id = tostring(time()) .. "_" .. tostring(math.random(100, 999)),
        code = ns.MakeRunCode(time()),   -- 0.6.3: the Run ID the story carries back
        title = title,
        zone = zone,
        isAuto = isAuto and true or false,
        startTime = time(),
        startDate = ns.NowStamp(),
        endDate = "",
        duration = 0,
        participants = {},
        wipes = 0,
        deaths = 0,
        bossKills = {},
        keyLoot = {},
        highlights = {},
        fullTimeline = {},
        shots = {},
        reloads = 0,
        instanceName = instName or ns.SafeStr(GetRealZoneText()) or zone,
        instanceID = instID,
        ejInstance = instName and ns.JournalInstance() or nil, -- 0.6.4: scene backdrop
        lastSeen = time(),
        paused = false,
        aggroHeld = {},
        aggroSamples = 0,
        kind = (ns.InstanceKind()),
        kills = {},          -- notable kills (elites, rares, bosses)
        foesDefeated = 0,    -- every kill, trash included
        coin = 0,            -- copper you looted during the run
        bossInfo = {},
        -- 0.5.0: open-world summary stats
        killCounts = {},     -- foe name -> kills
        levelStart = ns.SafeNum(UnitLevel("player")),
        questsDone = 0,
        places = {},
        milestones = {},
        pvpKills = 0,
        pvpDeaths = 0,
        -- 0.6.3: who recorded it, what they wore (story cover and Full
        -- Log) and which addon and client made it (version stamp)
        char = ns.PlayerName(),
        gear = ns.EquippedGear(),
        addonVersion = ns.VERSION,
        clientBuild = ns.ClientBuild(),
    }
    -- Persist the live run in SavedVariables so /reload or a disconnect can't lose it
    RPChroniclerDB.activeRun = activeRun
    ns.NoteRunPlace(instName or ns.SafeStr(GetRealZoneText()) or zone)
    local startSub = ns.SafeStr(GetSubZoneText())
    if startSub and startSub ~= "" then ns.NoteRunPlace(startSub) end

    ns.SyncAdventureRoster()
    ns.ResetRunTrackers()
    pcall(ns.ResetChronicle)
    PushTimeline(activeRun, PreciseStamp(), "Adventure began in " .. zone)
    ns.Debug("run", string.format("start %s (%s, %s)", title, activeRun.kind, isAuto and "auto" or "manual"))
    return activeRun
end

function ns.EndAdventure(reason, endTime)
    if not activeRun then return nil end
    ns.EnsureDB()
    ns.SyncAdventureRoster()
    FinishRoster(activeRun)
    RPChroniclerDB.activeRun = nil
    activeRun.paused = false

    pcall(ns.FightFlush)
    local dur = math.max(0, (endTime or time()) - (activeRun.startTime or time()))
    activeRun.duration = dur
    activeRun.endTime = endTime or time()
    activeRun.endDate = ns.NowStamp()

    local hasActivity = (#(activeRun.bossKills or {}) > 0)
        or (#(activeRun.keyLoot or {}) > 0)
        or ((activeRun.wipes or 0) > 0)
        or (#(activeRun.highlights or {}) > 0)
        or (#(activeRun.fullTimeline or {}) > 2)

    if activeRun.isAuto and dur < 30 and not hasActivity then
        ns.Debug("run", "discarded a short auto run: " .. tostring(activeRun.title))
        activeRun = nil
        return nil
    end
    ns.Debug("run", string.format("end %s (%s, %s)", tostring(activeRun.title), reason or "Completed", ns.FormatDuration(dur)))

    PushTimeline(activeRun, PreciseStamp(), "Adventure ended (" .. (reason or "Completed") .. ")")
    activeRun.exportText = ns.BuildAdventureFullLog(activeRun)

    table.insert(RPChroniclerDB.adventures, 1, activeRun)
    ns.TrimRuns()

    local saved = activeRun
    activeRun = nil
    activeBossName = nil
    activeBossPct = nil
    bossThresholdsHit = {}
    bossPullEngaged = {}
    return saved
end

-- =========================================================
-- Pause / Resume and restoring a run after /reload or disconnect
-- =========================================================
function ns.IsAdventurePaused()
    return activeRun and activeRun.paused and true or false
end

function ns.PauseAdventure()
    if not activeRun then return false, "No active adventure running." end
    if activeRun.paused then return false, "Recording is already paused." end
    PushTimeline(activeRun, PreciseStamp(), "[PAUSED] Recording paused", true)
    activeRun.paused = true
    pcall(ns.FightFlush)
    ns.Debug("run", "paused")
    return true, "Recording paused. Type /rp resume to continue."
end

function ns.ResumeAdventure()
    if not activeRun then return false, "No active adventure running." end
    if not activeRun.paused then return false, "Recording is not paused." end
    activeRun.paused = false
    PushTimeline(activeRun, PreciseStamp(), "[RESUMED] Recording resumed", true)
    ns.Debug("run", "resumed")
    return true, "Recording resumed: " .. (activeRun.title or "Adventure")
end

-- Called once per session at the first PLAYER_ENTERING_WORLD.
-- Returns "resumed", "paused", "interrupted" or nil, plus the run.
--  * A /reload (back within 2 minutes) continues the run, as it was.
--  * After a logout or disconnect the run is closed and saved, marked
--    interrupted, so it is never lost. The UI then offers to resume it.
function ns.RestoreSavedAdventure()
    ns.EnsureDB()
    local saved = RPChroniclerDB.activeRun
    if type(saved) ~= "table" or activeRun then return nil end

    local gap = math.max(0, time() - (saved.lastSeen or saved.startTime or time()))
    saved.aggroHeld = saved.aggroHeld or {}
    saved.aggroSamples = saved.aggroSamples or 0
    saved.kind = saved.kind or "world"
    activeBossName, activeBossPct = nil, nil
    bossThresholdsHit, bossPullEngaged, vitalsCooldowns, brink = {}, {}, {}, {}
    lastHP, deadNow = {}, {}

    if gap <= RESUME_WINDOW then
        activeRun = saved
        activeRun.reloads = (activeRun.reloads or 0) + 1
        activeRun.interruptedAt = nil
        if not saved.paused then
            PushTimeline(activeRun, PreciseStamp(), "[RELOAD] Recording continued after a " .. ns.FormatDuration(gap) .. " break", true)
        end
        ns.Debug("run", "continued after /reload: " .. tostring(saved.title))
        return saved.paused and "paused" or "resumed", saved
    end

    -- Close and keep it, marked interrupted
    RPChroniclerDB.activeRun = nil
    saved.paused = false
    saved.interrupted = true
    local lastSeen = saved.interruptedAt or saved.lastSeen or time()
    saved.endTime = lastSeen
    saved.duration = math.max(0, lastSeen - (saved.startTime or lastSeen))
    saved.endDate = saved.endDate ~= "" and saved.endDate or ns.NowStamp()
    PushTimeline(saved, PreciseStamp(), "Adventure ended (interrupted by a logout or disconnect)", true)
    saved.exportText = ns.BuildAdventureFullLog(saved)
    table.insert(RPChroniclerDB.adventures, 1, saved)
    ns.TrimRuns()
    ns.Debug("run", "closed an interrupted run: " .. tostring(saved.title))
    return "interrupted", saved
end

-- "Resume" on the interrupted-run prompt: the saved run becomes live again
function ns.ResumeInterruptedRun(runId)
    if activeRun then return false, "Another run is recording." end
    for i, adv in ipairs(RPChroniclerDB.adventures or {}) do
        if adv.id == runId then
            table.remove(RPChroniclerDB.adventures, i)
            activeRun = adv
            adv.interrupted = nil
            adv.duration = 0
            adv.endTime = nil
            adv.endDate = ""
            adv.lastSeen = time()
            adv.reloads = (adv.reloads or 0) + 1
            RPChroniclerDB.activeRun = adv
            ns.ResetRunTrackers()
            PushTimeline(adv, PreciseStamp(), "[RESUMED] Recording resumed after a logout or disconnect", true)
            ns.Debug("run", "resumed an interrupted run: " .. tostring(adv.title))
            return true, "Recording resumed: " .. (adv.title or "Adventure")
        end
    end
    return false, "That run is gone."
end

function ns.TouchActiveAdventure(isLogout)
    if activeRun and not activeRun.paused then activeRun.lastSeen = time() end
    if activeRun and isLogout then
        -- Saved with the run, in case this is a logout and not a /reload
        activeRun.interruptedAt = time()
        activeRun.lastSeen = time()
        pcall(ns.FightFlush)
    end
end

-- =========================================================
-- Aggro bookkeeping (fed by the combat poller in Events.lua)
-- =========================================================
function ns.RecordAdventureAggroSample(holderName)
    if not activeRun or activeRun.paused or not holderName then return end
    activeRun.aggroHeld = activeRun.aggroHeld or {}
    activeRun.aggroHeld[holderName] = (activeRun.aggroHeld[holderName] or 0) + 1
    activeRun.aggroSamples = (activeRun.aggroSamples or 0) + 1
end

function ns.GetAggroShare(name)
    if not activeRun or not name or not activeRun.aggroHeld then return 0, 0 end
    local total = activeRun.aggroSamples or 0
    if total <= 0 then return 0, 0 end
    local low = name:lower()
    local mine = 0
    for k, v in pairs(activeRun.aggroHeld) do
        local kLow = k:lower()
        if kLow == low or ns.SplitFullName(kLow) == low then mine = mine + v end
    end
    return mine / total, total
end

-- Generic timeline line from the Events.lua trackers ([SPELL], [BOSS CAST],
-- [CC], [PET] ...). They do their own throttling.
-- Returns a handle for ns.UpdateAdventureLine.
function ns.RecordAdventureLine(text)
    if not activeRun or activeRun.paused or not text or text == "" then return end
    if text:find("^%[MILESTONE%]") then
        activeRun.milestones = activeRun.milestones or {}
        if #activeRun.milestones < 30 then table.insert(activeRun.milestones, (text:gsub("^%[MILESTONE%]%s*", ""))) end
    end
    return PushTimeline(activeRun, PreciseStamp(), text)
end

function ns.UpdateAdventureLine(handle, text)
    if not activeRun or activeRun.paused or not text or text == "" then return false end
    return UpdateTimeline(activeRun, handle, text)
end

-- Places visited during the run, in order (for the Summary and the story)
function ns.NoteRunPlace(name)
    if not activeRun or activeRun.paused or not name or name == "" then return end
    activeRun.places = activeRun.places or {}
    for _, p in ipairs(activeRun.places) do if p == name then return end end
    if #activeRun.places < 40 then table.insert(activeRun.places, name) end
end

-- Companions you chatted with during the run (open world has no roster)
function ns.NoteRunCompanion(key)
    if not activeRun or activeRun.paused or not key then return end
    local e = RPChroniclerDB and RPChroniclerDB.players and RPChroniclerDB.players[key]
    if type(e) ~= "table" or not ns.Get("runCompanions") then return end
    activeRun.metCompanions = activeRun.metCompanions or {}
    local m = activeRun.metCompanions[key] or {}
    m.cid, m.note, m.relationship, m.tone = e.cid, e.note, e.relationship, e.tone
    m.kind = e.kind
    activeRun.metCompanions[key] = m
end

function ns.RecordAdventureAggroSwap(mobName, fromName, toName)
    if not activeRun or not mobName or not fromName or not toName then return end
    ns.FightNoteAggro(mobName, fromName, toName)
    if not ns.LogOn("aggro") then return end
    PushTimeline(activeRun, PreciseStamp(), string.format("[AGGRO] %s turns from %s to %s", mobName, fromName, toName))
end

-- 0.4.0: no more [COMBAT START] / [COMBAT END] pairs. Each fight becomes one
-- [FIGHT] line (Chronicle.lua) when the whole group has left combat.
function ns.RecordAdventureCombatState(inCombat)
    if not activeRun or activeRun.paused then return end
    if inCombat then ns.FightBegin() end
end

-- The whole group has left combat, so the pull is over. A boss that is still
-- alive means a wipe, reset or evade: its HP milestones start fresh next pull.
function ns.EndAdventureBossPull()
    if activeRun and activeBossName and bossPullEngaged[activeBossName] then
        PushTimeline(activeRun, PreciseStamp(), "[BOSS RESET] " .. activeBossName .. " survived the pull")
    end
    activeBossName = nil
    activeBossPct = nil
    bossThresholdsHit = {}
    bossPullEngaged = {}
end

function ns.ResetAdventureBossMilestones(bossName)
    if bossName then
        bossThresholdsHit[bossName] = nil
        bossPullEngaged[bossName] = nil
    else
        bossThresholdsHit = {}
        bossPullEngaged = {}
    end
end

-- Boss look for the Story reader icons: skull (worldboss or level ??),
-- gold dragon (elite), silver dragon (rare). Read once per boss per run.
local function BossKind(cls, lvl)
    if cls == "worldboss" or (lvl and lvl < 0) then return "skull" end
    if cls == "rare" or cls == "rareelite" then return "rare" end
    if cls == "elite" then return "elite" end
    return "skull"
end

-- 0.6.4: also the boss's NPC id (from its GUID) and the encounter id,
-- so the Story Book can show the boss in its story scene
local function NpcIdOf(unit)
    local guid = UnitGUID and ns.SafeStr(UnitGUID(unit))
    local id = guid and guid:match("^%a+%-%d+%-%d+%-%d+%-%d+%-(%d+)%-")
    return tonumber(id)
end

-- 0.6.4: what each boss looks like, kept across runs
-- (RPChroniclerDB.bossLooks[name] = { npc, display }), so older stories
-- can show a boss you meet again.
function ns.RememberBossLooks(name, npc, display)
    if type(name) ~= "string" or name == "" or not (npc or display) or type(RPChroniclerDB) ~= "table" then return end
    RPChroniclerDB.bossLooks = RPChroniclerDB.bossLooks or {}
    local e = RPChroniclerDB.bossLooks[name] or {}
    e.npc, e.display = e.npc or npc, e.display or display
    RPChroniclerDB.bossLooks[name] = e
end

-- A boss you target or point at: remembered when it is a boss of one of
-- your runs and its look is not known yet
local bossSeen = {}
function ns.LearnBossLooks(unit)
    if not unit or not UnitExists(unit) or UnitIsPlayer(unit) then return end
    local name = ns.SafeStr(UnitName(unit))
    if not name or bossSeen[name] or type(RPChroniclerDB) ~= "table" then return end
    local looks = RPChroniclerDB.bossLooks and RPChroniclerDB.bossLooks[name]
    if looks and looks.display then bossSeen[name] = true return end
    if not (RPChroniclerDB.knownBosses and RPChroniclerDB.knownBosses[name]) then return end
    bossSeen[name] = true
    ns.RememberBossLooks(name, NpcIdOf(unit), ns.UnitDisplayId(unit))
end

local function RecordBossInfo(bossName, unit, encounterID)
    if not activeRun or not bossName then return end
    activeRun.bossInfo = activeRun.bossInfo or {}
    local info = activeRun.bossInfo[bossName]
    if info and info.npc and (info.encounter or not encounterID) then return end
    if info and encounterID then info.encounter = info.encounter or encounterID end
    local units = unit and { unit } or { "boss1", "boss2", "boss3", "boss4", "boss5", "target", "focus" }
    for _, u in ipairs(units) do
        if UnitExists(u) and ns.SafeStr(UnitName(u)) == bossName then
            if not info then
                local cls = ns.SafeStr(UnitClassification(u)) or "normal"
                local lvl = ns.SafeNum(UnitLevel(u))
                info = { cls = cls, level = lvl or 0, kind = BossKind(cls, lvl) }
                activeRun.bossInfo[bossName] = info
            end
            info.npc = info.npc or NpcIdOf(u)
            -- 0.6.4: its look, so the story scene can show it later
            info.display = info.display or ns.UnitDisplayId(u)
            ns.RememberBossLooks(bossName, info.npc, info.display)
            break
        end
    end
    if not info and encounterID then
        activeRun.bossInfo[bossName] = { cls = "worldboss", level = 0, kind = "boss", encounter = encounterID }
    end
end

function ns.RecordAdventureBossEngage(bossName, unit, encounterID)
    if not activeRun or activeRun.paused or not bossName or bossName == "" then return end
    RecordBossInfo(bossName, unit, ns.SafeNum(encounterID))
    if not bossPullEngaged[bossName] then
        bossPullEngaged[bossName] = true
        activeBossPct = 100
        bossThresholdsHit[bossName] = {}
        PushTimeline(activeRun, PreciseStamp(), "[BOSS ENGAGED] " .. bossName)
        -- Remember confirmed bosses so later runs recognize them right away
        if RPChroniclerDB then
            RPChroniclerDB.knownBosses = RPChroniclerDB.knownBosses or {}
            RPChroniclerDB.knownBosses[bossName] = true
        end
    end
    activeBossName = bossName
end

function ns.RecordAdventureBossHP(bossName, pct)
    local safePct = ns.SafeNum(pct)
    if not activeRun or activeRun.paused or not bossName or bossName == "" or not safePct then return end
    safePct = math.floor(safePct)
    activeBossName = bossName
    activeBossPct = safePct
    bossThresholdsHit[bossName] = bossThresholdsHit[bossName] or {}
    local hit = bossThresholdsHit[bossName]

    if safePct <= 50 and safePct > 20 and not hit[50] then
        hit[50] = true
        PushTimeline(activeRun, PreciseStamp(), string.format("[BOSS HP] %s at %d%% HP", bossName, safePct))
    elseif safePct <= 20 and safePct > 5 and not hit[20] then
        hit[20] = true
        PushTimeline(activeRun, PreciseStamp(), string.format("[BOSS HP] %s dropped to %d%% HP!", bossName, safePct))
    elseif safePct <= 5 and safePct > 0 and not hit[5] then
        hit[5] = true
        PushTimeline(activeRun, PreciseStamp(), string.format("[BOSS HP] %s critical at %d%% HP!", bossName, safePct))
    end
end

function ns.GetAdventureCombatTag()
    if not (UnitAffectingCombat and UnitAffectingCombat("player")) then
        return nil
    end
    if activeBossName and activeBossPct then
        return string.format("vs %s %d%% HP", activeBossName, activeBossPct)
    elseif activeBossName then
        return "vs " .. activeBossName
    elseif UnitExists("target") and UnitCanAttack("player", "target") and not UnitIsDead("target") then
        local tName = ns.SafeStr(UnitName("target"))
        local hp = ns.SafeNum(UnitHealth("target"))
        local hpMax = ns.SafeNum(UnitHealthMax("target"))
        if tName and hp and hpMax and hpMax > 0 then
            return string.format("vs %s %d%% HP", tName, math.floor((hp / hpMax) * 100))
        elseif tName then
            return "vs " .. tName
        end
    end
    return "In Combat"
end

-- Last health percent seen for a name (used for [DEATH] context)
function ns.GetLastHP(name)
    return name and lastHP[name] or nil
end

function ns.RecordAdventureUnitVitals(unit)
    if not activeRun or activeRun.paused or not UnitExists(unit) or not UnitIsPlayer(unit) then return end
    local who = ns.GetUnitFullName(unit) or ns.StripRealm(UnitName(unit))
    if not who or who == "" then return end
    if UnitIsDeadOrGhost(unit) then
        brink[who] = nil -- not saved
        -- Party members' deaths (your own come from PLAYER_DEAD)
        if unit ~= "player" and not deadNow[who] and UnitIsDead(unit) then
            deadNow[who] = true
            ns.RecordAdventureDeath(who, false)
        end
        return
    end
    deadNow[who] = nil
    -- A recovery after the fight still counts as saved; new danger needs combat
    if not brink[who] and not (UnitAffectingCombat and UnitAffectingCombat("player")) then return end
    local now = GetTime()

    local hpPct = ns.HealthPct(unit)
    if hpPct and hpPct > 0 then lastHP[who] = hpPct end
    if hpPct then
        local hpKey = who .. "_HP"
        if hpPct > 0 and hpPct <= 10 and not brink[who] and (not vitalsCooldowns[hpKey] or (now - vitalsCooldowns[hpKey]) > 20) then
            vitalsCooldowns[hpKey] = now
            brink[who] = now
            ns.FightNoteLow(who)
            if ns.LogOn("danger") then
                PushTimeline(activeRun, PreciseStamp(), string.format("[DANGER] %s dropped to %d%% HP!", who, hpPct))
            end
        elseif brink[who] and hpPct >= 40 then
            -- Back from the brink: someone healed, shielded or pulled them out
            brink[who] = nil
            if ns.LogOn("danger") then
                PushTimeline(activeRun, PreciseStamp(), string.format("[SAVED] %s was pulled back from the brink (%d%% HP)", who, hpPct))
            end
        end
    end

    local pType = UnitPowerType and ns.SafeNum(UnitPowerType(unit))
    if pType == 0 then
        local mp = ns.SafeNum(UnitPower(unit, 0))
        local mpMax = ns.SafeNum(UnitPowerMax(unit, 0))
        if mp and mpMax and mpMax > 0 then
            local mpPct = math.floor((mp / mpMax) * 100)
            local mpKey = who .. "_MP"
            if mpPct <= 8 and (not vitalsCooldowns[mpKey] or (now - vitalsCooldowns[mpKey]) > 45) then
                vitalsCooldowns[mpKey] = now
                if ns.LogOn("danger") then
                    PushTimeline(activeRun, PreciseStamp(), string.format("[LOW MANA] %s at %d%% mana!", who, mpPct))
                end
            end
        end
    end
end

function ns.RecordAdventureDeath(unitName, isSelf, killerInfo)
    if not activeRun or activeRun.paused then return end
    local who = ns.ResolveCanonicalPlayerName(ns.StripRealm(unitName)) or "Unknown"
    activeRun.deaths = (activeRun.deaths or 0) + 1
    -- Context without the combat log: what the fight was against and the
    -- last health seen before the death
    local foe = killerInfo
    if (not foe or foe == "") then foe = ns.FightCurrentFoe() end
    if (not foe or foe == "") and activeBossName then foe = activeBossName end
    local parts = {}
    if foe and foe ~= "" then table.insert(parts, "fighting " .. foe) end
    local hp = lastHP[who] or lastHP[unitName or ""]
    if not hp and isSelf then hp = lastHP[ns.GetUnitFullName("player") or ""] end
    if hp then table.insert(parts, string.format("last seen at %d%% HP", hp)) end
    local cause = (#parts > 0) and (" (" .. table.concat(parts, ", ") .. ")") or ""
    lastHP[who] = nil
    ns.FightNoteDeath(who, isSelf)
    PushTimeline(activeRun, PreciseStamp(), "[DEATH] " .. who .. " died" .. cause)

    local now = GetTime()
    table.insert(recentDeathTimes, now)
    while #recentDeathTimes > 0 and (now - recentDeathTimes[1]) > 45 do
        table.remove(recentDeathTimes, 1)
    end

    local allDead = UnitIsDeadOrGhost("player")
    for i = 1, 4 do
        local u = "party" .. i
        if UnitExists(u) and not UnitIsDeadOrGhost(u) then
            allDead = false
            break
        end
    end

    if (now - lastWipeTime) > 60 and (#recentDeathTimes >= 3 or (allDead and GetNumGroupMembers and GetNumGroupMembers() > 1)) then
        lastWipeTime = now
        recentDeathTimes = {}
        activeRun.wipes = (activeRun.wipes or 0) + 1
        local wipeBoss = activeBossName and (" on " .. activeBossName) or ""
        PushTimeline(activeRun, PreciseStamp(), string.format("[WIPE #%d] Party wiped%s in %s", activeRun.wipes, wipeBoss, ns.GetCurrentWhere()))
        if activeBossName then
            bossThresholdsHit[activeBossName] = {}
        end
    end
end

function ns.RecordAdventureRez(casterName, targetName)
    if not activeRun or activeRun.paused or not targetName then return end
    local who = ns.ResolveCanonicalPlayerName(ns.StripRealm(targetName)) or targetName
    local by = casterName and ns.ResolveCanonicalPlayerName(ns.StripRealm(casterName)) or nil
    if by and by ~= "" then
        PushTimeline(activeRun, PreciseStamp(), string.format("[REZ] %s resurrected %s", by, who))
    else
        PushTimeline(activeRun, PreciseStamp(), string.format("[REZ] %s was resurrected", who))
    end
end

function ns.RecordAdventureBossKill(bossName)
    if not activeRun or activeRun.paused or not bossName or bossName == "" then return end
    local now = GetTime()
    if bossName:lower() == lastBossKillName:lower() and (now - lastBossKillTime) < 30 then
        return
    end
    lastBossKillName = bossName
    lastBossKillTime = now
    if activeBossName and activeBossName:lower() == bossName:lower() then
        activeBossName = nil
        activeBossPct = nil
    end
    bossThresholdsHit[bossName] = nil
    bossPullEngaged[bossName] = nil
    if RPChroniclerDB then
        RPChroniclerDB.knownBosses = RPChroniclerDB.knownBosses or {}
        RPChroniclerDB.knownBosses[bossName] = true
    end

    activeRun.bossKills = activeRun.bossKills or {}
    table.insert(activeRun.bossKills, bossName)
    PushTimeline(activeRun, PreciseStamp(), "[BOSS KILL] " .. bossName)
    ns.NoteBossLootSource(bossName)
    return true
end

-- source: "crafted", "from Arugal", "quest reward", "bought", "traded",
-- "mail", "gathered (Mining)", "won roll", "looted" ... or nil.
-- isNotable: green or better (goes into the Notable Loot header too).
function ns.RecordAdventureLoot(coloredLink, plainText, looter, source, isNotable)
    if not activeRun or activeRun.paused then return end
    local cleanItem = plainText or ns.CleanText(coloredLink) or ""
    if cleanItem == "" then return end
    local who = looter and ns.ResolveCanonicalPlayerName(ns.StripRealm(looter)) or nil
    if not ns.LogOn("lootSource") then source = nil end

    if isNotable ~= false then
        activeRun.keyLoot = activeRun.keyLoot or {}
        -- 0.6.4: quality, icon and kind, for the item's look in the story
        local d = ns.ItemDetails(coloredLink) or {}
        table.insert(activeRun.keyLoot, {
            colored = coloredLink or cleanItem,
            plain = cleanItem,
            looter = who or "",
            source = source,
            q = ns.ItemQuality(coloredLink),
            icon = d.icon, cls = d.cls, sub = d.sub,
        })
    end
    if not ns.LogOn("loot") then return end
    local src = source and (" (" .. source .. ")") or ""
    -- 0.5.0: the same item again (6x Crawler Meat) updates one line with xN
    local base, qty = cleanItem:match("^(.-)%s*[xX](%d+)$")
    base, qty = base or cleanItem, tonumber(qty) or 1
    local key = (who or "") .. "|" .. base
    local rep = lootRepeat[key]
    if rep and rep.run == activeRun.id and (time() - rep.at) < 900 then
        rep.n, rep.at = rep.n + qty, time()
        local text = (who and ("[LOOT] " .. who .. " received " .. base) or ("[LOOT] " .. base)) .. " x" .. rep.n .. rep.src
        if UpdateTimeline(activeRun, rep.handle, text) then return end
    end
    local line = who and ("[LOOT] " .. who .. " received " .. cleanItem .. src) or ("[LOOT] " .. cleanItem .. src)
    local h = PushTimeline(activeRun, PreciseStamp(), line)
    lootRepeat[key] = { run = activeRun.id, handle = h, n = qty, at = time(), src = src }
end

-- Coin you looted, summed for the run (and per fight by the fight tracker)
function ns.RecordAdventureCoin(copper)
    if not activeRun or activeRun.paused or not copper or copper <= 0 then return end
    activeRun.coin = (activeRun.coin or 0) + copper
    ns.FightNoteCoin(copper)
end

-- Out-of-character chatter never goes into the story log
function ns.IsOocText(text)
    if not text or text == "" then return false end
    local low = text:lower()
    if low:find("((", 1, true) or low:find("))", 1, true) then return true end
    if low:find("%[ooc") or low:find("^%s*ooc[%s:%-]") or low:find("%f[%a]ooc%f[%A]") then return true end
    return false
end

function ns.RecordAdventureChat(channelLabel, speaker, cleanMsg, isEmote)
    if not activeRun or activeRun.paused or not cleanMsg or cleanMsg == "" then return end
    if ns.IsOocText(cleanMsg) or ns.IsOocText(channelLabel) then return end
    local isNpc = isEmote or channelLabel == "NPC"
    if isNpc and not ns.LogOn("npcDialogue") then return end
    if not isNpc and not ns.LogOn("chat") then return end
    if isEmote then
        -- NPC emotes already name the NPC ("Hungry Bandit attempts to run away in fear!")
        PushTimeline(activeRun, PreciseStamp(), string.format("[%s] %s", channelLabel or "Emote", cleanMsg))
        return
    end
    local who = ns.ResolveCanonicalPlayerName(ns.StripRealm(speaker)) or "Unknown"
    local combatTag = ns.GetAdventureCombatTag()
    local tagStr = combatTag and string.format("%s | %s", channelLabel or "Chat", combatTag) or (channelLabel or "Chat")
    local entry = string.format("[%s] %s: %s", tagStr, who, cleanMsg)
    lastSpokenTimelineLine = entry
    PushTimeline(activeRun, PreciseStamp(), entry)
end

-- =========================================================
-- Run IDs (0.6.3): every recording has a short, stable ID (its start
-- time in base 36, e.g. "TPX8OK"). The Full Log header shows it, the AI
-- copies it into the story's last line, and import links the story to
-- its recording by it. Shots get run-qualified IDs ("TPX8OK-2"), so a
-- marker always points at the right run's picture.
-- =========================================================
local B36 = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ"
function ns.MakeRunCode(t)
    t = math.floor(tonumber(t) or time())
    local s = ""
    repeat
        local d = t % 36
        s = B36:sub(d + 1, d + 1) .. s
        t = math.floor(t / 36)
    until t <= 0
    return s
end

-- The run's ID; older runs get the same one from their start time
function ns.RunCode(adv)
    if type(adv) ~= "table" then return nil end
    if type(adv.code) == "string" and adv.code ~= "" then return adv.code end
    if tonumber(adv.startTime) then return ns.MakeRunCode(adv.startTime) end
    return nil
end

function ns.ShotId(adv, sh, i)
    return (ns.RunCode(adv) or "RUN") .. "-" .. tostring((type(sh) == "table" and sh.n) or i or 1)
end

-- The game's own file name for a shot taken at this time, without the
-- extension: WoWScrnShot_MMDDYY_HHMMSS in the computer's local time
function ns.ShotFileStem(at)
    if not date or not at then return nil end
    local ok, s = pcall(date, "%m%d%y_%H%M%S", math.floor(at))
    return ok and s and ("WoWScrnShot_" .. s) or nil
end

-- The live or saved run with this Run ID (any case)
function ns.FindAdventureByCode(code)
    if type(code) ~= "string" or code == "" then return nil end
    code = code:upper()
    if activeRun and ns.RunCode(activeRun) == code then return activeRun end
    for _, adv in ipairs((RPChroniclerDB and RPChroniclerDB.adventures) or {}) do
        if ns.RunCode(adv) == code then return adv end
    end
    return nil
end

-- 0.5.0: one shape for every shot { n, at, kind, description, zone }.
-- 0.6.3: plus file, the game's file name for it.
-- Returns false when the run's shot cap is reached (new shots stop).
function ns.RecordAdventureScreenshot(kind, description)
    if not activeRun or activeRun.paused then return false end
    activeRun.shots = activeRun.shots or {}
    local cap = ns.Limit("shotCap")
    if #activeRun.shots >= cap then return false end
    local n = #activeRun.shots + 1
    local desc = ns.SafeStr(description) or "Captured moment"
    local now = time()
    local sh = { n = n, at = now, file = ns.ShotFileStem(now), kind = kind or "manual", description = desc, zone = ns.GetCurrentWhere() }
    table.insert(activeRun.shots, sh)
    PushTimeline(activeRun, PreciseStamp(), string.format("[SHOT %s] %s", ns.ShotId(activeRun, sh), desc))
    return true
end

-- The game saved the shot RP Chronicler asked for: keep the time it was
-- really written, so the file name matches exactly
function ns.ConfirmLastShot()
    local list = activeRun and activeRun.shots
    local sh = list and list[#list]
    if not sh or not sh.at or (time() - sh.at) > 6 then return end
    sh.at = time()
    sh.file = ns.ShotFileStem(sh.at)
end

function ns.MarkAdventureHighlight(customNote)
    if not activeRun then
        return false, "No active adventure running."
    end
    if activeRun.paused then
        return false, "Recording is paused. Type /rp resume first."
    end
    local text = (customNote and customNote ~= "") and customNote or lastSpokenTimelineLine or ("Memorable moment in " .. ns.GetCurrentWhere())
    activeRun.highlights = activeRun.highlights or {}
    local stamped = string.format("[%s] %s", PreciseStamp(), text)
    table.insert(activeRun.highlights, stamped)
    PushTimeline(activeRun, PreciseStamp(), "[HIGHLIGHT] " .. text)
    return true, "Bookmarked moment: " .. text
end

-- 0.6.3: /rp note: the character's own thought, at this moment, as one
-- [NOTE] line (the story AI reads it as their inner voice)
function ns.RecordRunNote(text)
    text = tostring(text or ""):gsub("||", "|"):gsub("[\r\n]+", " "):match("^%s*(.-)%s*$")
    text = ns.StripColors(text)
    if text == "" then return false, "Type the thought too: /rp note I can still hear her warning." end
    if not activeRun then return false, "No adventure is recording, so there is nowhere to put the note." end
    if activeRun.paused then return false, "Recording is paused. Resume it first." end
    if not ns.LogOn("notes") then return false, "Notes are off in Options > Recording (Your notes)." end
    if #text > 300 then text = text:sub(1, 300) end
    PushTimeline(activeRun, PreciseStamp(), "[NOTE] " .. text)
    activeRun.noteCount = (activeRun.noteCount or 0) + 1
    return true, "Note added to the story log: " .. text
end

-- =========================================================
-- Fixing a run (0.6.3): replace a wrong name (a player, boss, foe,
-- companion or pet) before writing the story. The recording itself is
-- never changed: the fixes are a list applied to the Summary, the Full
-- Log and the story's copy of the run, so every fix can be undone.
-- =========================================================
local function EscapePattern(str)
    return (str:gsub("[%(%)%.%%%+%-%*%?%[%]%^%$]", "%%%0"))
end

-- One fixed name pattern: whole words only, so "Rat" never changes "Pirate"
local function FixPattern(from)
    local p = EscapePattern(from)
    if from:sub(1, 1):match("%w") then p = "%f[%w]" .. p end
    if from:sub(-1):match("%w") then p = p .. "%f[%W]" end
    return p
end

function ns.ApplyRunFixes(adv, text)
    if type(text) ~= "string" or type(adv) ~= "table" or type(adv.fixes) ~= "table" then return text end
    for _, fx in ipairs(adv.fixes) do
        if type(fx) == "table" and type(fx.from) == "string" and fx.from ~= "" and type(fx.to) == "string" then
            text = text:gsub(FixPattern(fx.from), (fx.to:gsub("%%", "%%%%")))
        end
    end
    return text
end

-- A single name with the run's fixes applied
function ns.FixedName(adv, name)
    if type(name) ~= "string" then return name end
    return ns.ApplyRunFixes(adv, name)
end

-- Adds a fix. Returns true, or false and why.
function ns.AddRunFix(advId, from, to)
    local adv = ns.FindAdventure(advId)
    if not adv then return false, "Pick a recording first." end
    from = tostring(from or ""):gsub("||", "|"):match("^%s*(.-)%s*$")
    to = tostring(to or ""):gsub("||", "|"):match("^%s*(.-)%s*$")
    from, to = ns.StripColors(from), ns.StripColors(to)
    if from == "" or to == "" then return false, "Type the wrong name and the right one." end
    if from == to then return false, "The new name is the same as the old one." end
    adv.fixes = type(adv.fixes) == "table" and adv.fixes or {}
    for _, fx in ipairs(adv.fixes) do
        if fx.from == from then
            fx.to = to
            ns.Notify("runChanged", adv)
            return true
        end
    end
    if #adv.fixes >= 30 then return false, "A run keeps at most 30 fixes." end
    table.insert(adv.fixes, { from = from, to = to })
    if adv.exportText then adv.exportText = ns.BuildAdventureFullLog(adv) end
    ns.Notify("runChanged", adv)
    return true
end

-- Undoes a fix: the recorded name comes back
function ns.RemoveRunFix(advId, idx)
    local adv = ns.FindAdventure(advId)
    if not adv or type(adv.fixes) ~= "table" or not adv.fixes[idx] then return false end
    table.remove(adv.fixes, idx)
    if adv.exportText then adv.exportText = ns.BuildAdventureFullLog(adv) end
    ns.Notify("runChanged", adv)
    return true
end

-- The names in a run that may need a fix: party, pets, bosses, named
-- foes and companions met, most important first (no duplicates)
function ns.RunNames(adv)
    local out, seen = {}, {}
    local function Add(n)
        n = type(n) == "string" and n:match("^%s*(.-)%s*$") or nil
        if n and n ~= "" and not seen[n:lower()] and #out < 24 then
            seen[n:lower()] = true
            table.insert(out, n)
        end
    end
    if type(adv) ~= "table" then return out end
    for _, p in ipairs(adv.participants or {}) do
        Add(p.name)
        if type(p.pet) == "string" then Add(p.pet:match("^(.-)%s*%(") or p.pet) end
    end
    for _, b in ipairs(adv.bossKills or {}) do Add(b) end
    for _, k in ipairs(adv.kills or {}) do Add(k) end
    local met = {}
    for k in pairs(type(adv.metCompanions) == "table" and adv.metCompanions or {}) do table.insert(met, k) end
    table.sort(met)
    for _, k in ipairs(met) do Add(k) end
    local foes = {}
    for k, n in pairs(type(adv.killCounts) == "table" and adv.killCounts or {}) do table.insert(foes, { k = k, n = n }) end
    table.sort(foes, function(x, y) if x.n ~= y.n then return x.n > y.n end return x.k < y.k end)
    for _, f in ipairs(foes) do Add(f.k) end
    return out
end

-- A story keeps its own copy of the run: give that copy the fixed names
-- (boss icons and the party line read them)
function ns.FixRunCopy(st)
    if type(st) ~= "table" or type(st.fixes) ~= "table" or #st.fixes == 0 then return end
    local function F(n) return ns.ApplyRunFixes(st, n) end
    for _, p in ipairs(st.participants or {}) do p.name = F(p.name); if p.pet then p.pet = F(p.pet) end end
    for i, b in ipairs(st.bossKills or {}) do st.bossKills[i] = F(b) end
    for i, k in ipairs(st.kills or {}) do st.kills[i] = F(k) end
    if type(st.bossInfo) == "table" then
        local info = {}
        for k, v in pairs(st.bossInfo) do info[F(k)] = v end
        st.bossInfo = info
    end
    st.title = F(st.title)
end

function RPChronicler_MarkMoment()
    local ok, status = ns.MarkAdventureHighlight(nil)
    print("|cff00ff00[RP Chronicler]|r " .. status)
    -- Marked moments also get a screenshot when Auto-Shots is on
    if ok then
        ns.RequestScreenshot("mark", "Marked moment")
    end
end

-- The run with this id: the live one or a saved one
function ns.FindAdventure(advId)
    if activeRun and activeRun.id == advId then return activeRun end
    for _, adv in ipairs((RPChroniclerDB and RPChroniclerDB.adventures) or {}) do
        if adv.id == advId then return adv end
    end
    return nil
end

-- Deletes a saved recording (never the live one). Its story stays in the
-- Story Book. Returns true, or false and why.
function ns.DeleteRun(advId)
    local active = ns.GetActiveAdventure()
    if active and active.id == advId then return false, "End the live run before deleting it." end
    for i, adv in ipairs(RPChroniclerDB.adventures or {}) do
        if adv.id == advId then
            table.remove(RPChroniclerDB.adventures, i)
            adv.storyId = nil
            ns.Debug("run", "deleted run " .. tostring(adv.title))
            ns.Notify("runChanged")
            return true
        end
    end
    return false, "Pick a recording first."
end

-- The one way to start a run by hand (button, keybind, menu, prompt).
-- Returns the run, or nil and why.
function ns.StartRun()
    local active = ns.GetActiveAdventure()
    if active then return nil, "Already recording " .. (active.title or "an adventure") .. ". End it first." end
    local run = ns.StartAdventure(nil, false)
    if run then ns.Notify("runChanged", run) end
    return run
end
