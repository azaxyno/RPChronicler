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

local RUN_KIND_LABEL = { dungeon = "Dungeon", raid = "Raid", world = "Open world adventure" }
function ns.GetRunKindLabel(adv)
    return RUN_KIND_LABEL[(adv and adv.kind) or "world"] or "Adventure"
end


local function PushTimeline(adv, stamp, entryText, force)
    if not adv then return end
    -- A paused run records nothing except its own pause/resume markers
    if adv.paused and not force then return end
    adv.lastSeen = time()
    adv.fullTimeline = adv.fullTimeline or {}
    local line = string.format("[%s] %s", stamp or PreciseStamp(), entryText)
    table.insert(adv.fullTimeline, line)
    local cap = ns.Limit("timelineMax")
    while #adv.fullTimeline > cap do
        table.remove(adv.fullTimeline, 1)
        adv.tlRemoved = (adv.tlRemoved or 0) + 1
    end
    -- A handle that survives trimming: the line's absolute position
    return (adv.tlRemoved or 0) + #adv.fullTimeline
end

-- 0.5.0: rewrites a timeline line in place (trash streaks, repeated loot).
-- Keeps the line's original time stamp. False when the line is gone.
local function UpdateTimeline(adv, handle, entryText)
    if not adv or not handle or not adv.fullTimeline then return false end
    local idx = handle - (adv.tlRemoved or 0)
    local old = adv.fullTimeline[idx]
    if not old then return false end
    local stamp = old:match("^(%[[^%]]*%])") or ("[" .. PreciseStamp() .. "]")
    adv.fullTimeline[idx] = stamp .. " " .. entryText
    adv.lastSeen = time()
    return true
end

function ns.SyncAdventureRoster()
    if not activeRun or activeRun.paused then return end
    activeRun.participants = activeRun.participants or {}

    local function AddOrUpdateUnit(unit)
        if not UnitExists(unit) or not UnitIsPlayer(unit) then return end
        local fullName = ns.GetUnitFullName(unit) or ns.StripRealm(UnitName(unit))
        if not fullName or fullName == "" then return end

        local lvl = ns.SafeNum(UnitLevel(unit))
        local lvlStr = (lvl and lvl > 0) and tostring(lvl) or ""
        local clsLoc, clsFile = UnitClass(unit)
        clsLoc = ns.SafeStr(clsLoc) or ""
        clsFile = ns.SafeStr(clsFile) or ""
        local role, guessed = ns.GetUnitRole(unit)
        role = role or "NONE"

        -- Guildmates: party members in your own guild
        local myGuild = ns.SafeStr(GetGuildInfo("player"))
        local theirGuild = ns.SafeStr(GetGuildInfo(unit))
        local isMate = unit ~= "player" and myGuild and theirGuild and myGuild ~= "" and myGuild == theirGuild or false

        -- 0.5.0: the run keeps its own copy of the companion's notes, so an
        -- old Full Log still reads right after the companion is deleted
        local note, comp = "", nil
        if RPChroniclerDB and RPChroniclerDB.players and unit ~= "player" then
            local pKey = ns.FindPlayerKey(fullName, true)
            comp = pKey and RPChroniclerDB.players[pKey]
            if comp and (comp.note or "") ~= "" then note = comp.note end
        end
        -- Pet: name plus species ("Snips (Crab, hunter pet)")
        local petUnit = (unit == "player" and "pet") or (unit:match("^party%d$") and ("partypet" .. unit:sub(6))) or (unit:match("^raid%d+$") and ("raidpet" .. unit:sub(5))) or nil
        local petDesc = petUnit and UnitExists(petUnit) and ns.GetPetDescriptor(petUnit) or nil

        for _, p in ipairs(activeRun.participants) do
            if p.name:lower() == fullName:lower() then
                if lvlStr ~= "" then p.level = lvlStr end
                if clsLoc ~= "" then p.class = clsLoc end
                if clsFile ~= "" then p.classFile = clsFile end
                -- An assigned role always wins; a guess only replaces another guess
                if role ~= "NONE" and (not guessed or p.roleGuessed == true or not p.role or p.role == "NONE") then
                    p.role = role
                    p.roleGuessed = guessed
                end
                if note ~= "" then p.note = note end
                if comp then
                    p.cid = comp.cid or p.cid
                    p.relationship = (comp.relationship or "") ~= "" and comp.relationship or p.relationship
                    p.tone = (comp.tone or "") ~= "" and comp.tone or p.tone
                end
                if petDesc then p.pet = petDesc end
                if theirGuild and theirGuild ~= "" then p.guild = theirGuild end
                if isMate then p.guildmate = true end
                return
            end
        end

        table.insert(activeRun.participants, {
            name = fullName,
            level = lvlStr,
            class = clsLoc,
            classFile = clsFile,
            role = role,
            roleGuessed = guessed,
            note = note,
            relationship = comp and comp.relationship or nil,
            tone = comp and comp.tone or nil,
            cid = comp and comp.cid or nil,
            pet = petDesc,
            guild = theirGuild,
            guildmate = isMate or nil,
        })
    end

    AddOrUpdateUnit("player")
    if IsInRaid and IsInRaid() then
        for i = 1, 40 do AddOrUpdateUnit("raid" .. i) end
    else
        for i = 1, 4 do AddOrUpdateUnit("party" .. i) end
    end
end

function ns.StartAdventure(customTitle, isAuto)
    ns.EnsureDB()
    if activeRun then
        ns.EndAdventure("Started New Adventure")
    end

    local zone = ns.GetCurrentWhere()
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
        instanceName = ns.SafeStr(GetRealZoneText()) or zone,
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
    }
    -- Persist the live run in SavedVariables so /reload or a disconnect can't lose it
    RPChroniclerDB.activeRun = activeRun
    ns.NoteRunPlace(ns.SafeStr(GetRealZoneText()) or zone)
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
    while #RPChroniclerDB.adventures > 40 do
        table.remove(RPChroniclerDB.adventures)
    end

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
    while #RPChroniclerDB.adventures > 40 do table.remove(RPChroniclerDB.adventures) end
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

local function RecordBossInfo(bossName, unit)
    if not activeRun or not bossName then return end
    activeRun.bossInfo = activeRun.bossInfo or {}
    if activeRun.bossInfo[bossName] then return end
    local units = unit and { unit } or { "boss1", "boss2", "boss3", "boss4", "boss5", "target", "focus" }
    for _, u in ipairs(units) do
        if UnitExists(u) and ns.SafeStr(UnitName(u)) == bossName then
            local cls = ns.SafeStr(UnitClassification(u)) or "normal"
            local lvl = ns.SafeNum(UnitLevel(u))
            activeRun.bossInfo[bossName] = { cls = cls, level = lvl or 0, kind = BossKind(cls, lvl) }
            return
        end
    end
end

function ns.RecordAdventureBossEngage(bossName, unit)
    if not activeRun or activeRun.paused or not bossName or bossName == "" then return end
    RecordBossInfo(bossName, unit)
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
        table.insert(activeRun.keyLoot, {
            colored = coloredLink or cleanItem,
            plain = cleanItem,
            looter = who or "",
            source = source,
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

-- 0.5.0: one shape for every shot { n, at, kind, description, zone }.
-- Returns false when the run's shot cap is reached (new shots stop).
function ns.RecordAdventureScreenshot(kind, description)
    if not activeRun or activeRun.paused then return false end
    activeRun.shots = activeRun.shots or {}
    local cap = ns.Limit("shotCap")
    if #activeRun.shots >= cap then return false end
    local n = #activeRun.shots + 1
    local desc = ns.SafeStr(description) or "Captured moment"
    table.insert(activeRun.shots, { n = n, at = time(), kind = kind or "manual", description = desc, zone = ns.GetCurrentWhere() })
    PushTimeline(activeRun, PreciseStamp(), string.format("[SHOT %d] %s", n, desc))
    return true
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
