local ADDON_NAME, ns = ...

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

-- Where the player is: "dungeon", "raid" or "world"
local function CurrentRunKind()
    local inInstance, instanceType = false, nil
    if IsInInstance then inInstance, instanceType = IsInInstance() end
    if inInstance and instanceType == "raid" then return "raid" end
    if inInstance and instanceType == "party" then return "dungeon" end
    return "world"
end

local function PushTimeline(adv, stamp, entryText, force)
    if not adv then return end
    -- A paused run records nothing except its own pause/resume markers
    if adv.paused and not force then return end
    adv.lastSeen = time()
    adv.fullTimeline = adv.fullTimeline or {}
    local line = string.format("[%s] %s", stamp or PreciseStamp(), entryText)
    table.insert(adv.fullTimeline, line)
    local cap = (ns.Limit and ns.Limit("timelineMax")) or 500
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
        local role, guessed = "NONE", false
        if ns.GetUnitRole then
            role, guessed = ns.GetUnitRole(unit)
        end

        -- Guildmates: party members in your own guild
        local myGuild = ns.SafeStr(GetGuildInfo("player"))
        local theirGuild = ns.SafeStr(GetGuildInfo(unit))
        local isMate = unit ~= "player" and myGuild and theirGuild and myGuild ~= "" and myGuild == theirGuild or false

        -- 0.5.0: the run keeps its own copy of the companion's notes, so an
        -- old Full Log still reads right after the companion is deleted
        local note, comp = "", nil
        if RPCopyDB and RPCopyDB.players and unit ~= "player" then
            local pKey = ns.FindPlayerKey(fullName, true)
            comp = pKey and RPCopyDB.players[pKey]
            if comp and (comp.note or "") ~= "" then note = comp.note end
        end
        -- Pet: name plus species ("Snips (Crab, hunter pet)")
        local petUnit = (unit == "player" and "pet") or (unit:match("^party%d$") and ("partypet" .. unit:sub(6))) or (unit:match("^raid%d+$") and ("raidpet" .. unit:sub(5))) or nil
        local petDesc = petUnit and ns.GetPetDescriptor and UnitExists(petUnit) and ns.GetPetDescriptor(petUnit) or nil

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
                    p.history = (comp.history or "") ~= "" and comp.history or p.history
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
            history = comp and comp.history or nil,
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
        kind = CurrentRunKind(),
        kills = {},          -- notable kills (elites, rares, bosses)
        foesDefeated = 0,    -- every kill, trash included
        coin = 0,            -- copper you looted during the run
        skills = {},         -- profession -> { from, to }
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
    RPCopyDB.activeRun = activeRun
    ns.NoteRunPlace(ns.SafeStr(GetRealZoneText()) or zone)
    local startSub = ns.SafeStr(GetSubZoneText())
    if startSub and startSub ~= "" then ns.NoteRunPlace(startSub) end

    ns.SyncAdventureRoster()
    if ns.ResetRunTrackers then ns.ResetRunTrackers() end
    if ns.ResetChronicle then pcall(ns.ResetChronicle) end
    PushTimeline(activeRun, PreciseStamp(), "Adventure began in " .. zone)
    if ns.RecordAtmosphere then pcall(ns.RecordAtmosphere, true) end
    if ns.Debug then ns.Debug("run", string.format("start %s (%s, %s)", title, activeRun.kind, isAuto and "auto" or "manual")) end
    return activeRun
end

function ns.EndAdventure(reason, endTime)
    if not activeRun then return nil end
    ns.EnsureDB()
    ns.SyncAdventureRoster()
    RPCopyDB.activeRun = nil
    activeRun.paused = false

    if ns.FightFlush then pcall(ns.FightFlush) end
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
        if ns.Debug then ns.Debug("run", "discarded a short auto run: " .. tostring(activeRun.title)) end
        activeRun = nil
        return nil
    end
    if ns.Debug then ns.Debug("run", string.format("end %s (%s, %s)", tostring(activeRun.title), reason or "Completed", ns.FormatDuration(dur))) end

    PushTimeline(activeRun, PreciseStamp(), "Adventure ended (" .. (reason or "Completed") .. ")")
    activeRun.exportText = ns.BuildAdventureFullLog(activeRun)

    table.insert(RPCopyDB.adventures, 1, activeRun)
    while #RPCopyDB.adventures > 40 do
        table.remove(RPCopyDB.adventures)
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
    if ns.FightFlush then pcall(ns.FightFlush) end
    if ns.Debug then ns.Debug("run", "paused") end
    return true, "Recording paused. Type /rp resume to continue."
end

function ns.ResumeAdventure()
    if not activeRun then return false, "No active adventure running." end
    if not activeRun.paused then return false, "Recording is not paused." end
    activeRun.paused = false
    PushTimeline(activeRun, PreciseStamp(), "[RESUMED] Recording resumed", true)
    if ns.Debug then ns.Debug("run", "resumed") end
    return true, "Recording resumed: " .. (activeRun.title or "Adventure")
end

-- Called once per session at the first PLAYER_ENTERING_WORLD.
-- Returns "resumed", "paused", "interrupted" or nil, plus the run.
--  * A /reload (back within 2 minutes) continues the run, as it was.
--  * After a logout or disconnect the run is closed and saved, marked
--    interrupted, so it is never lost. The UI then offers to resume it.
function ns.RestoreSavedAdventure()
    ns.EnsureDB()
    local saved = RPCopyDB.activeRun
    if type(saved) ~= "table" or activeRun then return nil end

    local gap = math.max(0, time() - (saved.lastSeen or saved.startTime or time()))
    saved.aggroHeld = saved.aggroHeld or {}
    saved.aggroSamples = saved.aggroSamples or 0
    saved.kind = saved.kind or "world"
    activeBossName, activeBossPct = nil, nil
    bossThresholdsHit, bossPullEngaged, vitalsCooldowns, brink = {}, {}, {}, {}
    lastHP, deadNow = {}, {}

    if gap <= RESUME_WINDOW and RPCopyDB.resumeAfterReload ~= false then
        activeRun = saved
        activeRun.reloads = (activeRun.reloads or 0) + 1
        activeRun.interruptedAt = nil
        if not saved.paused then
            PushTimeline(activeRun, PreciseStamp(), "[RELOAD] Recording continued after a " .. ns.FormatDuration(gap) .. " break", true)
        end
        if ns.Debug then ns.Debug("run", "continued after /reload: " .. tostring(saved.title)) end
        return saved.paused and "paused" or "resumed", saved
    end

    -- Close and keep it, marked interrupted
    RPCopyDB.activeRun = nil
    saved.paused = false
    saved.interrupted = true
    local lastSeen = saved.interruptedAt or saved.lastSeen or time()
    saved.endTime = lastSeen
    saved.duration = math.max(0, lastSeen - (saved.startTime or lastSeen))
    saved.endDate = saved.endDate ~= "" and saved.endDate or ns.NowStamp()
    PushTimeline(saved, PreciseStamp(), "Adventure ended (interrupted by a logout or disconnect)", true)
    saved.exportText = ns.BuildAdventureFullLog(saved)
    table.insert(RPCopyDB.adventures, 1, saved)
    while #RPCopyDB.adventures > 40 do table.remove(RPCopyDB.adventures) end
    if ns.Debug then ns.Debug("run", "closed an interrupted run: " .. tostring(saved.title)) end
    return "interrupted", saved
end

-- "Resume" on the interrupted-run prompt: the saved run becomes live again
function ns.ResumeInterruptedRun(runId)
    if activeRun then return false, "Another run is recording." end
    for i, adv in ipairs(RPCopyDB.adventures or {}) do
        if adv.id == runId then
            table.remove(RPCopyDB.adventures, i)
            activeRun = adv
            adv.interrupted = nil
            adv.duration = 0
            adv.endTime = nil
            adv.endDate = ""
            adv.lastSeen = time()
            adv.reloads = (adv.reloads or 0) + 1
            RPCopyDB.activeRun = adv
            if ns.ResetRunTrackers then ns.ResetRunTrackers() end
            PushTimeline(adv, PreciseStamp(), "[RESUMED] Recording resumed after a logout or disconnect", true)
            if ns.Debug then ns.Debug("run", "resumed an interrupted run: " .. tostring(adv.title)) end
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
        if ns.FightFlush then pcall(ns.FightFlush) end
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
    local e = RPCopyDB and RPCopyDB.players and RPCopyDB.players[key]
    if type(e) ~= "table" or RPCopyDB.runCompanions == false then return end
    activeRun.metCompanions = activeRun.metCompanions or {}
    local m = activeRun.metCompanions[key] or {}
    m.cid, m.note, m.history, m.relationship, m.tone = e.cid, e.note, e.history, e.relationship, e.tone
    m.kind = e.kind
    activeRun.metCompanions[key] = m
end

function ns.RecordAdventureAggroSwap(mobName, fromName, toName)
    if not activeRun or not mobName or not fromName or not toName then return end
    if ns.FightNoteAggro then ns.FightNoteAggro(mobName, fromName, toName) end
    if not ns.LogOn("aggro") then return end
    PushTimeline(activeRun, PreciseStamp(), string.format("[AGGRO] %s turns from %s to %s", mobName, fromName, toName))
end

-- 0.4.0: no more [COMBAT START] / [COMBAT END] pairs. Each fight becomes one
-- [FIGHT] line (Chronicle.lua) when the whole group has left combat.
function ns.RecordAdventureCombatState(inCombat)
    if not activeRun or activeRun.paused then return end
    if inCombat and ns.FightBegin then ns.FightBegin() end
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
        if RPCopyDB then
            RPCopyDB.knownBosses = RPCopyDB.knownBosses or {}
            RPCopyDB.knownBosses[bossName] = true
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

    local hpPct = ns.GetUnitHealthPct and ns.GetUnitHealthPct(unit)
    if hpPct and hpPct > 0 then lastHP[who] = hpPct end
    if hpPct then
        local hpKey = who .. "_HP"
        if hpPct > 0 and hpPct <= 10 and not brink[who] and (not vitalsCooldowns[hpKey] or (now - vitalsCooldowns[hpKey]) > 20) then
            vitalsCooldowns[hpKey] = now
            brink[who] = now
            if ns.FightNoteLow then ns.FightNoteLow(who) end
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
    if (not foe or foe == "") and ns.FightCurrentFoe then foe = ns.FightCurrentFoe() end
    if (not foe or foe == "") and activeBossName then foe = activeBossName end
    local parts = {}
    if foe and foe ~= "" then table.insert(parts, "fighting " .. foe) end
    local hp = lastHP[who] or lastHP[unitName or ""]
    if not hp and isSelf and ns.GetUnitFullName then hp = lastHP[ns.GetUnitFullName("player") or ""] end
    if hp then table.insert(parts, string.format("last seen at %d%% HP", hp)) end
    local cause = (#parts > 0) and (" (" .. table.concat(parts, ", ") .. ")") or ""
    lastHP[who] = nil
    if ns.FightNoteDeath then ns.FightNoteDeath(who, isSelf) end
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
    if RPCopyDB then
        RPCopyDB.knownBosses = RPCopyDB.knownBosses or {}
        RPCopyDB.knownBosses[bossName] = true
    end

    activeRun.bossKills = activeRun.bossKills or {}
    table.insert(activeRun.bossKills, bossName)
    PushTimeline(activeRun, PreciseStamp(), "[BOSS KILL] " .. bossName)
    if ns.NoteBossLootSource then ns.NoteBossLootSource(bossName) end
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
    if ns.FightNoteCoin then ns.FightNoteCoin(copper) end
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
    local cap = (ns.Limit and ns.Limit("shotCap")) or 40
    if #activeRun.shots >= cap then return false end
    local n = #activeRun.shots + 1
    local desc = ns.SafeStr(description) or "Captured moment"
    table.insert(activeRun.shots, { n = n, at = time(), kind = kind or "manual", description = desc, zone = ns.GetCurrentWhere() })
    if ns.LogOn("screenshots") then
        PushTimeline(activeRun, PreciseStamp(), string.format("[SHOT %d] %s", n, desc))
    end
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

function RPCopy_MarkMoment()
    local ok, status = ns.MarkAdventureHighlight(nil)
    print("|cff00ff00[RPCopy]|r " .. status)
    -- Marked moments also get a screenshot when Auto-Shots is on
    if ok and ns.RequestScreenshot then
        ns.RequestScreenshot("mark", "Marked moment")
    end
end

-- The run with this id: the live one or a saved one
function ns.FindAdventure(advId)
    if activeRun and activeRun.id == advId then return activeRun end
    for _, adv in ipairs((RPCopyDB and RPCopyDB.adventures) or {}) do
        if adv.id == advId then return adv end
    end
    return nil
end

local BOOK_FIELDS = { "title", "instance", "duration", "zone", "date", "party", "kills", "wipes", "deaths", "chapters",
    "foes", "quests", "levels" }

-- =========================================================
-- Stories (0.5.0): RPCopyDB.stories, kept apart from the recordings, so
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
    RPCopyDB.stories = type(RPCopyDB.stories) == "table" and RPCopyDB.stories or {}
    return RPCopyDB.stories
end

-- Newest import first
function ns.GetStories()
    if not RPCopyDB then return {} end
    local list = {}
    for _, st in ipairs(Stories()) do
        if type(st) == "table" and (st.story or "") ~= "" then table.insert(list, st) end
    end
    table.sort(list, function(x, y) return (x.importedAt or 0) > (y.importedAt or 0) end)
    return list
end

function ns.FindStory(id)
    if not id or not RPCopyDB then return nil end
    for _, st in ipairs(Stories()) do
        if st.id == id then return st end
    end
    return nil
end

-- The story written from a run, or nil
function ns.StoryForRun(runId)
    if not runId or not RPCopyDB then return nil end
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
    return meta
end

-- Imports (or re-imports) the story of a run. Returns true and the story id.
function ns.SetAdventureStory(advId, rawStoryText)
    ns.EnsureDB()
    -- Normalizes || -> |, strips code fences and Markdown, maps non-ASCII
    -- glyphs to ASCII, and auto-closes dangling color escapes (see Core.lua)
    local cleaned = ns.NormalizeStoryText(rawStoryText)
    local adv = ns.FindAdventure(advId)
    if not adv then return false end
    local st = ns.StoryForRun(adv.id)
    if not st then
        st = { id = NewStoryId(), runId = adv.id }
        table.insert(Stories(), 1, st)
    end
    CopyRunMeta(st, adv)
    if RPCopyDB.autoColorStory ~= false and ns.AutoColorStory then
        local ok, colored = pcall(ns.AutoColorStory, cleaned, st)
        if ok and type(colored) == "string" then cleaned = colored end
    end
    st.story = cleaned
    st.importedAt = time()
    adv.storyId = st.id
    local meta = ApplyBook(st, cleaned)
    if ns.Debug then
        ns.Debug("run", string.format("story imported for %s (%d chars, %d chapters)", tostring(adv.title), #cleaned, #(meta.chapters or {})))
    end
    return true, st.id
end

-- Re-import onto a story whose recording may be gone
function ns.SetStoryText(storyId, rawStoryText)
    local st = ns.FindStory(storyId)
    if not st then return false end
    local run = ns.StoryRun(st)
    if run then return ns.SetAdventureStory(run.id, rawStoryText) end
    local cleaned = ns.NormalizeStoryText(rawStoryText)
    if RPCopyDB.autoColorStory ~= false and ns.AutoColorStory then
        local ok, colored = pcall(ns.AutoColorStory, cleaned, st)
        if ok and type(colored) == "string" then cleaned = colored end
    end
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
            if ns.Debug then ns.Debug("run", "story deleted: " .. tostring(list[i].title)) end
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
-- RPCopyDB.stories with a copy of the run's details
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
    for _, adv in ipairs(RPCopyDB.adventures or {}) do Move(adv) end
    Move(RPCopyDB.activeRun)
    if moved > 0 and ns.Debug then ns.Debug("info", "moved " .. moved .. " stories into the Story Book") end
    return moved
end

-- 0.5.0: the Summary differs by run type. Dungeons and raids lead with the
-- roster, bosses and wipes; open world with levels, foes, quests and places.
-- Stats that are zero or empty are hidden, and each one has a switch in
-- Options > Summary (ns.SummaryOn).
local function StatShown(key, adv)
    if not ns.SummaryOn(key) then return false end
    for _, st in ipairs(ns.SUMMARY_STATS or {}) do
        if st.key == key then
            if st.kinds == "instance" then return adv.kind ~= "world" end
            if st.kinds == "world" then return adv.kind == "world" end
            return true
        end
    end
    return true
end

-- Foe name -> count, most first: "Windsong Crawler x14, Wind Hollow x6"
function ns.GetFoeBreakdown(adv, max)
    local list = {}
    for name, n in pairs((adv and adv.killCounts) or {}) do table.insert(list, { name = name, n = n }) end
    table.sort(list, function(x, y) if x.n ~= y.n then return x.n > y.n end return x.name < y.name end)
    local out, rest = {}, 0
    for i, f in ipairs(list) do
        if i <= (max or 6) then table.insert(out, f.n > 1 and (f.name .. " x" .. f.n) or f.name) else rest = rest + f.n end
    end
    if rest > 0 then table.insert(out, rest .. " more") end
    return table.concat(out, ", ")
end

-- The levels a run covered, or nil: "11 -> 13"
function ns.GetRunLevels(adv)
    local a, b = adv and tonumber(adv.levelStart), adv and tonumber(adv.levelEnd)
    if a and b and b > a then return a .. " -> " .. b, b - a end
    return nil, 0
end

-- The short hero stats for the top bar and the run card, by run type
function ns.GetRunHeroStats(adv)
    local out = {}
    if not adv then return out end
    local function Add(key, label, value)
        if value and value ~= 0 and value ~= "" and StatShown(key, adv) then table.insert(out, { label = label, value = value }) end
    end
    if adv.kind == "world" then
        Add("foes", "Foes", adv.foesDefeated or 0)
        local _, gained = ns.GetRunLevels(adv)
        Add("levels", "Levels", gained)
        Add("quests", "Quests", adv.questsDone or 0)
        Add("deaths", "Deaths", adv.deaths or 0)
        Add("shots", "Shots", #(adv.shots or {}))
    else
        Add("bosses", "Bosses", #(adv.bossKills or {}))
        Add("wipes", "Wipes", adv.wipes or 0)
        Add("deaths", "Deaths", adv.deaths or 0)
        Add("foes", "Foes", adv.foesDefeated or 0)
        Add("shots", "Shots", #(adv.shots or {}))
    end
    return out
end

function ns.BuildAdventureSummary(adv)
    if not adv then
        return "|cff9e9e9eNo adventure selected. Enter a dungeon/raid or click 'Start Recording' above.|r"
    end

    local lines = {}
    local G, T, M = ns.COLORS.gold, ns.COLORS.text, ns.COLORS.muted
    local function Head(label) table.insert(lines, ns.ColorText(label, G)) end
    local function Gap() table.insert(lines, "") end
    local durSec = ns.GetRunDuration(adv)
    table.insert(lines, ns.ColorText("=== " .. (adv.title or "Adventure") .. " ===", G))
    table.insert(lines, string.format("%s %s   |   %s %s   |   %s %s   |   %s",
        ns.ColorText("Zone:", ns.COLORS.header), ns.ColorText(adv.zone or "Unknown", ns.COLORS.location),
        ns.ColorText("Date:", ns.COLORS.header), ns.ColorText(adv.startDate or "-", T),
        ns.ColorText("Duration:", ns.COLORS.header), ns.ColorText(ns.FormatDuration(durSec), T),
        ns.ColorText(ns.GetRunKindLabel(adv), M)))
    Gap()

    local hero = {}
    for _, h in ipairs(ns.GetRunHeroStats(adv)) do
        table.insert(hero, ns.ColorText(h.label .. ":", G) .. " " .. ns.ColorText(tostring(h.value), ns.COLORS.friendly))
    end
    if #hero > 0 then
        table.insert(lines, table.concat(hero, "    "))
        Gap()
    end

    local parts = adv.participants or {}
    if StatShown("roster", adv) and (#parts > 1 or adv.kind ~= "world") then
        Head(adv.kind == "world" and "Companions on the road:" or "Party Roster:")
        if #parts > 0 then
            for _, p in ipairs(parts) do
                local roleTag = ns.GetRoleTag(p.role, true)
                local nameColored = (p.classFile and p.classFile ~= "") and ns.ColorizeClass(p.name, p.classFile) or ns.ColorText(p.name, ns.COLORS.speaker)
                local meta = (p.level and p.level ~= "" and p.class and p.class ~= "") and string.format(" (Lvl %s %s)", p.level, p.class) or ""
                local petStr = p.pet and (" " .. ns.ColorText("with " .. p.pet, ns.COLORS.lootType)) or ""
                local noteStr = (p.note and p.note ~= "") and (" - " .. ns.ColorText(p.note, ns.COLORS.note)) or ""
                table.insert(lines, string.format("  %s %s%s%s%s", roleTag ~= "" and roleTag or "-", nameColored, meta, petStr, noteStr))
            end
        else
            table.insert(lines, "  " .. ns.ColorText("Solo run", M))
        end
        Gap()
    elseif #parts == 1 and parts[1].pet and StatShown("roster", adv) then
        table.insert(lines, ns.ColorText("Pet:", G) .. " " .. ns.ColorText(parts[1].pet, ns.COLORS.lootType))
        Gap()
    end

    local lv = ns.GetRunLevels(adv)
    if lv and StatShown("levels", adv) then
        table.insert(lines, ns.ColorText("Levels gained:", G) .. " " .. ns.ColorText(lv, ns.COLORS.friendly))
    end
    if (adv.deaths or 0) > 0 and adv.kind == "world" and StatShown("deaths", adv) then
        table.insert(lines, ns.ColorText("Deaths:", G) .. " " .. ns.ColorText(tostring(adv.deaths), ns.COLORS.death))
    end
    if ((adv.pvpKills or 0) > 0 or (adv.pvpDeaths or 0) > 0) and StatShown("pvp", adv) then
        table.insert(lines, ns.ColorText("PvP:", G) .. " " .. ns.ColorText(string.format("%d kills, %d deaths", adv.pvpKills or 0, adv.pvpDeaths or 0), T))
    end
    if (adv.questsDone or 0) > 0 and StatShown("quests", adv) then
        table.insert(lines, ns.ColorText("Quests completed:", G) .. " " .. ns.ColorText(tostring(adv.questsDone), ns.COLORS.quest or T))
    end
    if (adv.coin or 0) > 0 and StatShown("coin", adv) then
        table.insert(lines, ns.ColorText("Coin looted:", G) .. " " .. ns.ColorText(ns.FormatCopper(adv.coin), ns.COLORS.gold))
    end
    if #(adv.shots or {}) > 0 and StatShown("shots", adv) then
        table.insert(lines, ns.ColorText("Screenshots:", G) .. " " .. ns.ColorText(tostring(#adv.shots), T))
    end

    if adv.kind ~= "world" and ((#(adv.bossKills or {}) > 0) or (adv.wipes or 0) > 0 or (adv.deaths or 0) > 0) then
        local bits = {}
        if StatShown("bosses", adv) and #(adv.bossKills or {}) > 0 then table.insert(bits, ns.ColorText("Boss/Elite Kills:", G) .. " " .. ns.ColorText(tostring(#adv.bossKills), ns.COLORS.friendly)) end
        if StatShown("wipes", adv) and (adv.wipes or 0) > 0 then table.insert(bits, ns.ColorText("Wipes:", G) .. " " .. ns.ColorText(tostring(adv.wipes), ns.COLORS.combat)) end
        if StatShown("deaths", adv) and (adv.deaths or 0) > 0 then table.insert(bits, ns.ColorText("Deaths:", G) .. " " .. ns.ColorText(tostring(adv.deaths), ns.COLORS.death)) end
        if #bits > 0 then table.insert(lines, table.concat(bits, "    ")) end
        if StatShown("bosses", adv) then
            for _, b in ipairs(adv.bossKills or {}) do
                local kind = (adv.bossInfo and type(adv.bossInfo[b]) == "table" and adv.bossInfo[b].kind) or "skull"
                local icon = ns.BossIcon and (ns.BossIcon(kind) .. " ") or ""
                table.insert(lines, "  - " .. icon .. ns.ColorText(b, ns.COLORS.boss))
            end
        end
    end
    Gap()

    if (adv.foesDefeated or 0) > 0 and StatShown("foes", adv) then
        Head(string.format("Foes defeated: %d", adv.foesDefeated))
        local fb = ns.GetFoeBreakdown(adv, 8)
        if fb ~= "" then table.insert(lines, "  " .. ns.ColorText(fb, ns.COLORS.hostile or T)) end
        Gap()
    end
    if #(adv.kills or {}) > 0 and StatShown("notable", adv) then
        Head("Named, elite and rare kills:")
        local seen, uniq = {}, {}
        for _, k in ipairs(adv.kills) do if not seen[k] then seen[k] = true table.insert(uniq, k) end end
        table.insert(lines, "  " .. ns.ColorText(table.concat(uniq, ", "), ns.COLORS.elite or T))
        Gap()
    end
    if adv.kind == "world" and #(adv.places or {}) > 1 and StatShown("places", adv) then
        Head("Places visited:")
        table.insert(lines, "  " .. ns.ColorText(table.concat(adv.places, ", "), ns.COLORS.location))
        Gap()
    end
    if StatShown("skills", adv) and type(adv.skills) == "table" then
        local sk = {}
        for name, v in pairs(adv.skills) do
            if type(v) == "table" and v.from and v.to and v.to > v.from then table.insert(sk, string.format("%s %d -> %d", name, v.from, v.to)) end
        end
        table.sort(sk)
        if #sk > 0 then
            Head("Skill-ups:")
            table.insert(lines, "  " .. ns.ColorText(table.concat(sk, ", "), T))
            Gap()
        end
    end
    if #(adv.milestones or {}) > 0 and StatShown("milestones", adv) then
        Head("Milestones:")
        for _, m in ipairs(adv.milestones) do table.insert(lines, "  - " .. ns.ColorText(m, ns.COLORS.npcText)) end
        Gap()
    end
    if #(adv.keyLoot or {}) > 0 and StatShown("loot", adv) then
        Head("Notable Loot:")
        for _, item in ipairs(adv.keyLoot) do
            local disp = type(item) == "table" and (item.colored or item.plain) or tostring(item)
            local looter = (type(item) == "table" and item.looter and item.looter ~= "") and (" -> " .. item.looter) or ""
            local src = (type(item) == "table" and item.source) and (" (" .. item.source .. ")") or ""
            table.insert(lines, "  - " .. disp .. ns.ColorText(looter .. src, M))
        end
        Gap()
    end
    -- Empty highlights show a hint only while the run still records
    local hasHl = #(adv.highlights or {}) > 0
    if StatShown("highlights", adv) and (hasHl or (adv.endDate or "") == "") then
        Head("Bookmarked Highlights:")
        if hasHl then
            for _, h in ipairs(adv.highlights) do table.insert(lines, "  * " .. ns.ColorText(h, ns.COLORS.npcText)) end
        else
            table.insert(lines, "  " .. ns.ColorText("None yet (use '* Mark Moment' or /rp mark during a run)", M))
        end
    end
    while lines[#lines] == "" do table.remove(lines) end
    return table.concat(lines, "\n")
end

-- Companions of a run (party members plus, in 0.5.0, companions you
-- chatted with) who have RP notes. The live Companion book wins, even when
-- you cleared a note on purpose; a companion who was deleted or renamed
-- falls back to the copy the run kept. You are never listed.
local function FindCompanionFor(name, cid)
    local players = RPCopyDB and RPCopyDB.players
    if not players then return nil end
    if cid then
        for k, e in pairs(players) do
            if type(e) == "table" and e.cid == cid then return k, e end
        end
    end
    local key = ns.FindPlayerKey(name, false)
    if key and players[key] then return key, players[key] end
    return nil
end

local function CleanNote(s)
    s = ((s or ""):match("^%s*(.-)%s*$"))
    return (ns.StripColors(s):gsub("[\r\n]+", " "))
end

function ns.GetKnownCompanionNotes(adv)
    local list = {}
    if not adv then return list end
    local selfFull = ns.GetUnitFullName and ns.GetUnitFullName("player") or nil
    local selfShort = ns.StripRealm(UnitName("player"))
    local seen = {}
    local function Add(name, copy)
        local low = (name or ""):lower()
        if name == "" or seen[low] then return end
        if (selfFull and low == selfFull:lower()) or (selfShort and low == selfShort:lower()) then return end
        seen[low] = true
        local key, entry = FindCompanionFor(name, copy.cid)
        if key then
            if seen["key:" .. key] then return end
            seen["key:" .. key] = true
        end
        local src = entry or copy
        if entry and (entry.include == "never") then return end
        local note, hist = CleanNote(src.note), CleanNote(src.history)
        local rel = {}
        if CleanNote(src.relationship) ~= "" then table.insert(rel, CleanNote(src.relationship)) end
        if CleanNote(src.tone) ~= "" then table.insert(rel, CleanNote(src.tone)) end
        if note ~= "" or hist ~= "" or #rel > 0 then
            local max = (RPCopyDB and RPCopyDB.knownNoteMax) or 300
            local parts = {}
            if #rel > 0 then table.insert(parts, table.concat(rel, ", ")) end
            if note ~= "" then table.insert(parts, ns.ClipCompanionNote and ns.ClipCompanionNote(note, max) or note) end
            if hist ~= "" then table.insert(parts, "history: " .. (ns.ClipCompanionNote and ns.ClipCompanionNote(hist, max) or hist)) end
            local kind = (entry and entry.kind) or copy.kind
            local shown = key or name
            if kind == "npc" then shown = shown .. " (NPC)" elseif kind == "pet" then shown = shown .. " (pet)" end
            table.insert(list, { name = shown, note = table.concat(parts, " - ") })
        end
    end
    for _, p in ipairs(adv.participants or {}) do Add(p.name or "", p) end
    if type(adv.metCompanions) == "table" then
        local keys = {}
        for k in pairs(adv.metCompanions) do table.insert(keys, k) end
        table.sort(keys)
        for _, k in ipairs(keys) do Add(k, adv.metCompanions[k]) end
    end
    return list
end

local function FormatCopper(c)
    c = math.floor(c or 0)
    local g, sv, cp = math.floor(c / 10000), math.floor((c % 10000) / 100), c % 100
    local parts = {}
    if g > 0 then table.insert(parts, g .. "g") end
    if sv > 0 then table.insert(parts, sv .. "s") end
    if cp > 0 or #parts == 0 then table.insert(parts, cp .. "c") end
    return table.concat(parts, " ")
end
ns.FormatCopper = FormatCopper

-- First line of the Full Log: the trigger of the matching story skill
function ns.GetStoryTrigger(adv)
    if adv and adv.kind == "world" then return "use adventure story" end
    return "use story"
end

function ns.BuildAdventureFullLog(adv)
    if not adv then
        return "No adventure selected."
    end

    local out = {}
    local durSec = ns.GetRunDuration(adv)
    table.insert(out, ns.GetStoryTrigger(adv))
    table.insert(out, "[ADVENTURE: " .. (adv.title or "Dungeon Run") .. "]")
    -- 0.5.0: open world has no wipes, so its header leaves them out
    local head = string.format("Run type: %s | Zone: %s | Date: %s | Duration: %s",
        ns.GetRunKindLabel(adv), adv.zone or "Unknown", adv.startDate or "-", ns.FormatDuration(durSec))
    if adv.kind ~= "world" then head = head .. string.format(" | Wipes: %d", adv.wipes or 0) end
    head = head .. string.format(" | Deaths: %d", adv.deaths or 0)
    table.insert(out, head)
    local lvText = ns.GetRunLevels(adv)
    local extra = {}
    if lvText then table.insert(extra, "Levels: " .. lvText) end
    if (adv.questsDone or 0) > 0 then table.insert(extra, "Quests completed: " .. adv.questsDone) end
    if adv.kind == "world" and #(adv.places or {}) > 1 and ns.LogOn("places") then table.insert(extra, "Places: " .. table.concat(adv.places, ", ")) end
    if #extra > 0 then table.insert(out, table.concat(extra, " | ")) end
    if adv.interrupted then
        table.insert(out, "Note: the recording was cut short by a logout or disconnect.")
    end
    table.insert(out, "")

    local mates = {}
    table.insert(out, "Roster:")
    if adv.participants and #adv.participants > 0 then
        for _, p in ipairs(adv.participants) do
            local rTag = ns.GetRoleTag(p.role, false)
            local rolePart = (rTag ~= "") and (", " .. rTag) or ""
            local guildPart = ""
            if ns.LogOn("guildmates") and p.guildmate and p.guild then
                guildPart = " <" .. p.guild .. "> (guildmate)"
                table.insert(mates, p.name)
            end
            local petPart = p.pet and (" - pet: " .. p.pet) or ""
            table.insert(out, string.format("- %s (Lvl %s %s%s)%s%s",
                p.name, (p.level and p.level ~= "") and p.level or "?", (p.class and p.class ~= "") and p.class or "Adventurer", rolePart, guildPart, petPart))
        end
    else
        table.insert(out, "- Solo Adventurer")
    end
    if #mates > 0 then
        table.insert(out, "Guildmates in the party: " .. table.concat(mates, ", "))
    end
    table.insert(out, "")

    -- Party members saved in the Companion book with an RP note, so the
    -- storyteller knows who they are. Nobody without a note is listed.
    local known = ns.GetKnownCompanionNotes(adv)
    if #known > 0 then
        table.insert(out, "Known companions:")
        for _, k in ipairs(known) do
            table.insert(out, "- " .. k.name .. ": " .. k.note)
        end
        table.insert(out, "")
    end

    if adv.bossKills and #adv.bossKills > 0 then
        table.insert(out, "Bosses & Elites Defeated: " .. table.concat(adv.bossKills, ", "))
    end
    if (adv.foesDefeated or 0) > 0 and ns.LogOn("kills") then
        local seenK, notable = {}, {}
        for _, k in ipairs(adv.kills or {}) do if not seenK[k] then seenK[k] = true table.insert(notable, k) end end
        local fb = ns.GetFoeBreakdown(adv, 8)
        local extra = (fb ~= "") and (" (" .. fb .. ")") or ""
        table.insert(out, string.format("Foes defeated: %d%s", adv.foesDefeated, extra))
        if #notable > 0 then table.insert(out, "Notable kills: " .. table.concat(notable, ", ")) end
    end
    if adv.keyLoot and #adv.keyLoot > 0 then
        local lootNames = {}
        for _, item in ipairs(adv.keyLoot) do
            local p = type(item) == "table" and item.plain or ns.StripColors(tostring(item))
            local w = ""
            if type(item) == "table" and item.looter and item.looter ~= "" then
                w = " -> " .. item.looter
            end
            if type(item) == "table" and item.source and ns.LogOn("lootSource") then
                w = w .. " (" .. item.source .. ")"
            end
            table.insert(lootNames, p .. w)
        end
        table.insert(out, "Notable Loot: " .. table.concat(lootNames, ", "))
    end
    if (adv.coin or 0) > 0 and ns.LogOn("loot") then
        table.insert(out, "Coin looted: " .. FormatCopper(adv.coin))
    end
    if ns.LogOn("skills") and type(adv.skills) == "table" then
        local sk = {}
        for name, v in pairs(adv.skills) do
            if type(v) == "table" and v.from and v.to and v.to > v.from then
                table.insert(sk, string.format("%s %d -> %d", name, v.from, v.to))
            end
        end
        table.sort(sk)
        if #sk > 0 then table.insert(out, "Skill-ups: " .. table.concat(sk, ", ")) end
    end
    if adv.highlights and #adv.highlights > 0 then
        table.insert(out, "")
        table.insert(out, "Starred Highlights:")
        for _, h in ipairs(adv.highlights) do
            local cleanH = ns.StripColors(h)
            if not ns.IsOocText(cleanH) then table.insert(out, "- " .. cleanH) end
        end
    end

    -- 0.5.0: numbered screenshots, so the story can place [Shot N] markers
    if ns.LogOn("screenshots") and #(adv.shots or {}) > 0 then
        table.insert(out, "")
        table.insert(out, "Screenshots (write [Shot N] where each fits the story):")
        for i, sh in ipairs(adv.shots) do
            if type(sh) == "table" then
                local stamp = sh.at and date and date("%H:%M:%S", sh.at) or "?"
                table.insert(out, string.format("- Shot %d at %s: %s", sh.n or i, stamp, ns.SafeStr(sh.description) or "moment"))
            end
        end
    end

    table.insert(out, "")
    table.insert(out, "Full Adventure Timeline:")
    local tl = adv.fullTimeline or {}
    local keep = (ns.Limit and ns.Limit("timelineMax")) or 450
    local startIdx = math.max(1, #tl - keep + 1)
    for i = startIdx, #tl do
        local cleanLine = ns.StripColors(tl[i])
        -- No out-of-character lines (OOC channel, (( )), [OOC], [OOC Note]),
        -- and old [COMBAT START] / [COMBAT END] pairs are left out
        if cleanLine and cleanLine ~= "" and not ns.IsOocText(cleanLine)
            and not cleanLine:find("[COMBAT START]", 1, true) and not cleanLine:find("[COMBAT END]", 1, true) then
            table.insert(out, cleanLine)
        end
    end

    return table.concat(out, "\n")
end

-- Size of the Full Log, for the size meter: characters and rough tokens
function ns.GetFullLogSize(adv)
    local text = ns.BuildAdventureFullLog(adv) or ""
    local chars = #text
    return chars, math.floor(chars / 4 + 0.5)
end

-- The comfortable paste size of the AI picked in Options, in characters
function ns.GetAiLimit()
    local key = RPCopyDB and RPCopyDB.aiModel or "GEMINI_FREE"
    for _, m in ipairs(ns.AI_MODELS or {}) do
        if m.key == key then
            if m.chars then return m.chars, m.label end
            return (RPCopyDB and RPCopyDB.aiCustomLimit) or 40000, m.label
        end
    end
    return 60000, "Gemini (free)"
end

-- =========================================================
-- Story Book: metadata parsed from an imported story
-- The templates ask the AI for:
--   line 1: the story title
--   line 2: <dungeon or region> | <duration> | <zone>
--   line 3 (optional): Date: ... | Party: ...
--   chapter headers "Chapter N: ..." and a footer line
--   "Bosses: N | Wipes: N | Deaths: N"
-- Anything missing falls back to the run's own data.
-- =========================================================
local function Trim(s) return (s or ""):match("^%s*(.-)%s*$") end

function ns.ParseStoryMeta(text)
    local meta = { chapters = {} }
    local plain = ns.StripColors(ns.NormalizeStoryText and ns.NormalizeStoryText(text or "") or (text or ""))
    plain = plain:gsub("|T.-|t", ""):gsub("|A.-|a", "")
    local lines = {}
    for line in (plain .. "\n"):gmatch("([^\n]*)\n") do
        line = Trim(line)
        if line ~= "" then table.insert(lines, line) end
    end
    if #lines == 0 then return meta end
    local first = lines[1]:gsub("^[Tt]itle:%s*", ""):gsub("^#+%s*", "")
    -- A long first line is prose, not a title
    if #first <= 90 and not first:lower():find("^use %a* ?story") then meta.title = first end
    local second = lines[2] or ""
    if second:find("|", 1, true) then
        local parts = {}
        for piece in (second .. "|"):gmatch("([^|]*)|") do table.insert(parts, Trim(piece)) end
        meta.instance = parts[1] ~= "" and parts[1] or nil
        meta.duration = parts[2] ~= "" and parts[2] or nil
        meta.zone = parts[3] ~= "" and parts[3] or nil
        -- 0.5.0: "Zephras Isle | 29m | Zephras Isle" - the zone said twice
        if meta.zone and meta.instance and meta.zone:lower() == meta.instance:lower() then meta.zone = nil end
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
        levels = b.levels or (adv and ns.GetRunLevels and ns.GetRunLevels(adv)) or "",
        chapters = b.chapters or {},
        kind = (adv and adv.kind) or "world",
    }
    if info.zone ~= "" and info.zone:lower() == (info.instance or ""):lower() then info.zone = "" end
    if info.instance ~= "" and info.title ~= info.instance and not info.title:find(info.instance, 1, true) then
        info.name = info.title .. " - " .. info.instance
    else
        info.name = info.title
    end
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
    return Trim(text) .. "\n\n(Chronicle recorded with RPCopy)"
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
-- time. RPCopy colors every later plain mention of the names it can verify
-- from the run: party (class colors), pets, places (teal), foes and bosses
-- (crimson), NPCs (pale yellow) and items (their quality color). Only
-- plain prose is touched; text the AI already colored is left alone.
-- Options > Stories & Export can turn it off.
-- =========================================================
local PROSE_HEX = { eceff1 = true, e0e0e0 = true, f5e6c8 = true, d7c4a3 = true, ffffff = false }
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
    local run = ns.StoryRun(st)
    for _, line in ipairs((run and run.fullTimeline) or {}) do
        local plain = ns.StripColors(line)
        local npc = plain:match("%[NPC[^%]]*%]%s*([^:]+):") or plain:match("%[QUEST%] [AC]%a+: .- from (.+)$")
            or plain:match("%[QUEST%] Completed: .- for (.+)$")
        if npc then Put(npc, NPC_HEX) end
    end
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
        end
    end
    return map
end

function ns.AutoColorStory(text, st)
    if type(text) ~= "string" or text == "" or type(st) ~= "table" then return text end
    local map = StoryNameColors(st)
    local names = {}
    for name in pairs(map) do table.insert(names, name) end
    if #names == 0 then return text end
    table.sort(names, function(a, b) return #a > #b end)

    local function ColorPlain(seg, cur)
        if cur and not PROSE_HEX[cur] then return seg end
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
