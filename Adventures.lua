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
    end
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

        local note = ""
        if RPCopyDB and RPCopyDB.players then
            local pKey = ns.FindPlayerKey(fullName, true)
            if pKey and RPCopyDB.players[pKey] and RPCopyDB.players[pKey].note ~= "" then
                note = RPCopyDB.players[pKey].note
            end
        end

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
            guild = theirGuild,
            guildmate = isMate or nil,
        })
    end

    AddOrUpdateUnit("player")
    for i = 1, 4 do AddOrUpdateUnit("party" .. i) end
    if IsInRaid and IsInRaid() then
        for i = 1, 40 do AddOrUpdateUnit("raid" .. i) end
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
        story = "",
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
    }
    -- Persist the live run in SavedVariables so /reload or a disconnect can't lose it
    RPCopyDB.activeRun = activeRun

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
function ns.RecordAdventureLine(text)
    if not activeRun or activeRun.paused or not text or text == "" then return end
    PushTimeline(activeRun, PreciseStamp(), text)
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
    local line = who and ("[LOOT] " .. who .. " received " .. cleanItem .. src) or ("[LOOT] " .. cleanItem .. src)
    PushTimeline(activeRun, PreciseStamp(), line)
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

function ns.RecordAdventureScreenshot(filename)
    if not activeRun or activeRun.paused then return end
    activeRun.shots = activeRun.shots or {}
    table.insert(activeRun.shots, filename or ns.NowStamp())
    PushTimeline(activeRun, PreciseStamp(), "[SCREENSHOT] Captured moment")
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

local BOOK_FIELDS = { "title", "instance", "duration", "zone", "date", "party", "kills", "wipes", "deaths", "chapters" }

function ns.SetAdventureStory(advId, rawStoryText)
    ns.EnsureDB()
    -- Normalizes || -> |, strips code fences and Markdown, maps non-ASCII
    -- glyphs to ASCII, and auto-closes dangling color escapes (see Core.lua)
    local cleaned = ns.NormalizeStoryText(rawStoryText)
    local adv = ns.FindAdventure(advId)
    if not adv then return false end
    adv.story = cleaned

    -- Story Book details from the story's header and footer. Fields you
    -- edited by hand survive a re-import.
    local okMeta, meta = pcall(ns.ParseStoryMeta, cleaned)
    if not okMeta or type(meta) ~= "table" then meta = {} end
    local old = type(adv.book) == "table" and adv.book or {}
    local edited = type(old.edited) == "table" and old.edited or {}
    local book = { edited = edited, importedAt = time() }
    for _, k in ipairs(BOOK_FIELDS) do
        if edited[k] then book[k] = old[k] else book[k] = meta[k] end
    end
    adv.book = book
    if ns.Debug then
        ns.Debug("run", string.format("story imported for %s (%d chars, %d chapters)", tostring(adv.title), #cleaned, #(meta.chapters or {})))
    end
    return true
end

-- Edit one Story Book field by hand ("" clears it back to the run's data)
function ns.SetBookField(advId, field, value)
    local adv = ns.FindAdventure(advId)
    if not adv then return false end
    adv.book = type(adv.book) == "table" and adv.book or {}
    adv.book.edited = adv.book.edited or {}
    if value == nil or value == "" then
        adv.book[field] = nil
        adv.book.edited[field] = nil
    else
        if field == "kills" or field == "wipes" or field == "deaths" then value = tonumber(value) or value end
        adv.book[field] = value
        adv.book.edited[field] = true
    end
    return true
end

-- Removes the story (and its book details) but keeps the recording
function ns.DeleteAdventureStory(advId)
    local adv = ns.FindAdventure(advId)
    if not adv then return false end
    adv.story = ""
    adv.book = nil
    if ns.Debug then ns.Debug("run", "story deleted for " .. tostring(adv.title)) end
    return true
end

function ns.BuildAdventureSummary(adv)
    if not adv then
        return "|cff9e9e9eNo adventure selected. Enter a dungeon/raid or click 'Start Recording' above.|r"
    end

    local lines = {}
    local durSec = ns.GetRunDuration(adv)
    table.insert(lines, ns.ColorText("=== " .. (adv.title or "Adventure") .. " ===", ns.COLORS.gold))
    table.insert(lines, string.format("%s %s   |   %s %s   |   %s %s",
        ns.ColorText("Zone:", ns.COLORS.header), ns.ColorText(adv.zone or "Unknown", ns.COLORS.location),
        ns.ColorText("Date:", ns.COLORS.header), ns.ColorText(adv.startDate or "-", ns.COLORS.text),
        ns.ColorText("Duration:", ns.COLORS.header), ns.ColorText(ns.FormatDuration(durSec), ns.COLORS.text)))
    table.insert(lines, "")

    table.insert(lines, ns.ColorText("Party Roster:", ns.COLORS.gold))
    if adv.participants and #adv.participants > 0 then
        for _, p in ipairs(adv.participants) do
            local roleTag = ns.GetRoleTag(p.role, true)
            local nameColored = (p.classFile and p.classFile ~= "")
                and ns.ColorizeClass(p.name, p.classFile)
                or ns.ColorText(p.name, ns.COLORS.speaker)
            local meta = (p.level and p.level ~= "" and p.class and p.class ~= "")
                and string.format(" (Lvl %s %s)", p.level, p.class)
                or ""
            local noteStr = (p.note and p.note ~= "") and (" - " .. ns.ColorText(p.note, ns.COLORS.note)) or ""
            table.insert(lines, string.format("  %s %s%s%s", roleTag ~= "" and roleTag or "-", nameColored, meta, noteStr))
        end
    else
        table.insert(lines, "  " .. ns.ColorText("Solo run", ns.COLORS.muted))
    end
    table.insert(lines, "")

    table.insert(lines, string.format("%s %s    %s %s    %s %s",
        ns.ColorText("Boss/Elite Kills:", ns.COLORS.gold), ns.ColorText(tostring(#(adv.bossKills or {})), ns.COLORS.friendly),
        ns.ColorText("Wipes:", ns.COLORS.gold), ns.ColorText(tostring(adv.wipes or 0), ns.COLORS.combat),
        ns.ColorText("Deaths:", ns.COLORS.gold), ns.ColorText(tostring(adv.deaths or 0), ns.COLORS.death)))

    if adv.bossKills and #adv.bossKills > 0 then
        for _, b in ipairs(adv.bossKills) do
            local kind = (adv.bossInfo and type(adv.bossInfo[b]) == "table" and adv.bossInfo[b].kind) or "skull"
            local icon = ns.BossIcon and (ns.BossIcon(kind) .. " ") or ""
            table.insert(lines, "  - " .. icon .. ns.ColorText(b, ns.COLORS.boss))
        end
    end
    table.insert(lines, "")

    table.insert(lines, ns.ColorText("Notable Loot:", ns.COLORS.gold))
    if adv.keyLoot and #adv.keyLoot > 0 then
        for _, item in ipairs(adv.keyLoot) do
            local disp = type(item) == "table" and (item.colored or item.plain) or tostring(item)
            local looter = (type(item) == "table" and item.looter and item.looter ~= "") and (" -> " .. item.looter) or ""
            table.insert(lines, "  - " .. disp .. ns.ColorText(looter, ns.COLORS.muted))
        end
    else
        table.insert(lines, "  " .. ns.ColorText("None recorded", ns.COLORS.muted))
    end
    table.insert(lines, "")

    table.insert(lines, ns.ColorText("Bookmarked Highlights:", ns.COLORS.gold))
    if adv.highlights and #adv.highlights > 0 then
        for _, h in ipairs(adv.highlights) do
            table.insert(lines, "  * " .. ns.ColorText(h, ns.COLORS.npcText))
        end
    else
        table.insert(lines, "  " .. ns.ColorText("None (use '* Mark Moment' or /rp mark during a run)", ns.COLORS.muted))
    end

    return table.concat(lines, "\n")
end

-- Party members of a run who are saved companions with a non-empty note.
-- The live Companion book wins (notes can be edited after the run); the
-- note captured during the run is the fallback. You are never listed.
function ns.GetKnownCompanionNotes(adv)
    local list = {}
    if not adv or type(adv.participants) ~= "table" then return list end
    local selfFull = ns.GetUnitFullName and ns.GetUnitFullName("player") or nil
    local selfShort = ns.StripRealm(UnitName("player"))
    for _, p in ipairs(adv.participants) do
        local name = p.name or ""
        local low = name:lower()
        local isSelf = (selfFull and low == selfFull:lower()) or (selfShort and low == selfShort:lower())
        if name ~= "" and not isSelf then
            local note = ""
            local key = RPCopyDB and RPCopyDB.players and ns.FindPlayerKey(name, false)
            local entry = key and RPCopyDB.players[key]
            if type(entry) == "table" then
                note = (entry.note or ""):match("^%s*(.-)%s*$")
                if note == "" then note = (p.note or ""):match("^%s*(.-)%s*$") end
            end
            if note ~= "" then
                table.insert(list, { name = key or name, note = (ns.StripColors(note):gsub("[\r\n]+", " ")) })
            end
        end
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
    table.insert(out, string.format("Run type: %s | Zone: %s | Date: %s | Duration: %s | Wipes: %d | Deaths: %d",
        ns.GetRunKindLabel(adv), adv.zone or "Unknown", adv.startDate or "-", ns.FormatDuration(durSec), adv.wipes or 0, adv.deaths or 0))
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
            table.insert(out, string.format("- %s (Lvl %s %s%s)%s",
                p.name, (p.level and p.level ~= "") and p.level or "?", (p.class and p.class ~= "") and p.class or "Adventurer", rolePart, guildPart))
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
        local notable = adv.kills or {}
        local extra = (#notable > 0) and (" (notable: " .. table.concat(notable, ", ") .. ")") or ""
        table.insert(out, string.format("Foes defeated: %d%s", adv.foesDefeated, extra))
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
        if b or w or de then
            meta.kills = meta.kills or tonumber(b)
            meta.wipes = meta.wipes or tonumber(w)
            meta.deaths = meta.deaths or tonumber(de)
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
        chapters = b.chapters or {},
    }
    if info.instance ~= "" and info.title ~= info.instance and not info.title:find(info.instance, 1, true) then
        info.name = info.title .. " - " .. info.instance
    else
        info.name = info.title
    end
    return info
end

-- Story as clean plain text (no color codes or icons), for Discord or forums
function ns.GetStoryPlainText(adv)
    if not adv or not adv.story or adv.story == "" then return "" end
    local text = ns.NormalizeStoryText(adv.story)
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
