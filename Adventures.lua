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

local function PushTimeline(adv, stamp, entryText)
    if not adv then return end
    adv.fullTimeline = adv.fullTimeline or {}
    local line = string.format("[%s] %s", stamp or PreciseStamp(), entryText)
    table.insert(adv.fullTimeline, line)
    while #adv.fullTimeline > 300 do
        table.remove(adv.fullTimeline, 1)
    end
end

function ns.SyncAdventureRoster()
    if not activeRun then return end
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
        local role = UnitGroupRolesAssigned and ns.SafeStr(UnitGroupRolesAssigned(unit)) or "NONE"
        role = role or "NONE"

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
                if role ~= "NONE" then p.role = role end
                if note ~= "" then p.note = note end
                return
            end
        end

        table.insert(activeRun.participants, {
            name = fullName,
            level = lvlStr,
            class = clsLoc,
            classFile = clsFile,
            role = role,
            note = note,
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
    }

    ns.SyncAdventureRoster()
    PushTimeline(activeRun, PreciseStamp(), "Adventure began in " .. zone)
    return activeRun
end

function ns.EndAdventure(reason)
    if not activeRun then return nil end
    ns.EnsureDB()
    ns.SyncAdventureRoster()

    local dur = math.max(0, time() - (activeRun.startTime or time()))
    activeRun.duration = dur
    activeRun.endDate = ns.NowStamp()

    local hasActivity = (#(activeRun.bossKills or {}) > 0)
        or (#(activeRun.keyLoot or {}) > 0)
        or ((activeRun.wipes or 0) > 0)
        or (#(activeRun.highlights or {}) > 0)
        or (#(activeRun.fullTimeline or {}) > 2)

    if activeRun.isAuto and dur < 30 and not hasActivity then
        activeRun = nil
        return nil
    end

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
    return saved
end

function ns.RecordAdventureCombatState(inCombat)
    if not activeRun then return end
    if inCombat then
        local targetHint = ""
        if UnitExists("target") and UnitCanAttack("player", "target") and not UnitIsDead("target") then
            local tName = ns.SafeStr(UnitName("target"))
            if tName and tName ~= "" then
                targetHint = " (Target: " .. tName .. ")"
            end
        end
        PushTimeline(activeRun, PreciseStamp(), "[COMBAT START]" .. targetHint)
    else
        activeBossName = nil
        activeBossPct = nil
        PushTimeline(activeRun, PreciseStamp(), "[COMBAT END]")
    end
end

function ns.RecordAdventureBossEngage(bossName)
    if not activeRun or not bossName or bossName == "" then return end
    if activeBossName ~= bossName then
        activeBossName = bossName
        activeBossPct = 100
        bossThresholdsHit[bossName] = bossThresholdsHit[bossName] or {}
        PushTimeline(activeRun, PreciseStamp(), "[BOSS ENGAGED] " .. bossName)
    end
end

function ns.RecordAdventureBossHP(bossName, pct)
    local safePct = ns.SafeNum(pct)
    if not activeRun or not bossName or bossName == "" or not safePct then return end
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

function ns.RecordAdventureUnitVitals(unit)
    if not activeRun or not UnitExists(unit) or not UnitIsPlayer(unit) or UnitIsDeadOrGhost(unit) then return end
    if not (UnitAffectingCombat and UnitAffectingCombat("player")) then return end

    local who = ns.GetUnitFullName(unit) or ns.StripRealm(UnitName(unit))
    if not who or who == "" then return end
    local now = GetTime()

    local hp = ns.SafeNum(UnitHealth(unit))
    local hpMax = ns.SafeNum(UnitHealthMax(unit))
    if hp and hpMax and hpMax > 0 then
        local hpPct = math.floor((hp / hpMax) * 100)
        local hpKey = who .. "_HP"
        if hpPct > 0 and hpPct <= 14 and (not vitalsCooldowns[hpKey] or (now - vitalsCooldowns[hpKey]) > 25) then
            vitalsCooldowns[hpKey] = now
            PushTimeline(activeRun, PreciseStamp(), string.format("[DANGER] %s dropped to %d%% HP!", who, hpPct))
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
                PushTimeline(activeRun, PreciseStamp(), string.format("[LOW MANA] %s at %d%% mana!", who, mpPct))
            end
        end
    end
end

function ns.RecordAdventureDeath(unitName, isSelf, killerInfo)
    if not activeRun then return end
    local who = ns.ResolveCanonicalPlayerName(ns.StripRealm(unitName)) or "Unknown"
    activeRun.deaths = (activeRun.deaths or 0) + 1
    local cause = (killerInfo and killerInfo ~= "") and (" (" .. killerInfo .. ")") or ""
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
    end
end

function ns.RecordAdventureRez(casterName, targetName)
    if not activeRun or not targetName then return end
    local who = ns.ResolveCanonicalPlayerName(ns.StripRealm(targetName)) or targetName
    local by = casterName and ns.ResolveCanonicalPlayerName(ns.StripRealm(casterName)) or nil
    if by and by ~= "" then
        PushTimeline(activeRun, PreciseStamp(), string.format("[REZ] %s resurrected %s", by, who))
    else
        PushTimeline(activeRun, PreciseStamp(), string.format("[REZ] %s was resurrected", who))
    end
end

function ns.RecordAdventureBossKill(bossName)
    if not activeRun or not bossName or bossName == "" then return end
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

    activeRun.bossKills = activeRun.bossKills or {}
    table.insert(activeRun.bossKills, bossName)
    PushTimeline(activeRun, PreciseStamp(), "[BOSS KILL] " .. bossName)
end

function ns.RecordAdventureLoot(coloredLink, plainText, looter)
    if not activeRun then return end
    local cleanItem = plainText or ns.CleanText(coloredLink) or ""
    if cleanItem == "" then return end
    local who = looter and ns.ResolveCanonicalPlayerName(ns.StripRealm(looter)) or nil

    activeRun.keyLoot = activeRun.keyLoot or {}
    table.insert(activeRun.keyLoot, {
        colored = coloredLink or cleanItem,
        plain = cleanItem,
        looter = who or "",
    })
    local line = who and ("[LOOT] " .. who .. " received " .. cleanItem) or ("[LOOT] " .. cleanItem)
    PushTimeline(activeRun, PreciseStamp(), line)
end

function ns.RecordAdventureChat(channelLabel, speaker, cleanMsg)
    if not activeRun or not cleanMsg or cleanMsg == "" then return end
    local who = ns.ResolveCanonicalPlayerName(ns.StripRealm(speaker)) or "Unknown"
    local combatTag = ns.GetAdventureCombatTag()
    local tagStr = combatTag and string.format("%s | %s", channelLabel or "Chat", combatTag) or (channelLabel or "Chat")
    local entry = string.format("[%s] %s: %s", tagStr, who, cleanMsg)
    lastSpokenTimelineLine = entry
    PushTimeline(activeRun, PreciseStamp(), entry)
end

function ns.RecordAdventureScreenshot(filename)
    if not activeRun then return end
    activeRun.shots = activeRun.shots or {}
    table.insert(activeRun.shots, filename or ns.NowStamp())
    PushTimeline(activeRun, PreciseStamp(), "[SCREENSHOT] Captured moment")
end

function ns.MarkAdventureHighlight(customNote)
    if not activeRun then
        return false, "No active adventure running."
    end
    local text = (customNote and customNote ~= "") and customNote or lastSpokenTimelineLine or ("Memorable moment in " .. ns.GetCurrentWhere())
    activeRun.highlights = activeRun.highlights or {}
    local stamped = string.format("[%s] %s", PreciseStamp(), text)
    table.insert(activeRun.highlights, stamped)
    PushTimeline(activeRun, PreciseStamp(), "[HIGHLIGHT] " .. text)
    return true, "Bookmarked moment: " .. text
end

function RPCopy_MarkMoment()
    local _, status = ns.MarkAdventureHighlight(nil)
    print("|cff00ff00[RPCopy]|r " .. status)
end

function ns.SetAdventureStory(advId, rawStoryText)
    ns.EnsureDB()
    local cleaned = (rawStoryText or ""):match("^%s*(.-)%s*$")

    -- WoW EditBox doubles pasted '|' into '||' when pasting via Ctrl+V
    cleaned = cleaned:gsub("||", "|")

    -- Strip surrounding markdown code fences if copied from LLM output
    cleaned = cleaned:gsub("^```[%w_-]*%s*\n?", ""):gsub("\n?```%s*$", "")
    cleaned = cleaned:match("^%s*(.-)%s*$")

    -- Normalize non-ASCII star glyphs to clean ASCII '*' so classic fonts never render '[]'
    cleaned = cleaned:gsub("★", "*")

    -- Auto-close any dangling |cffRRGGBB color escape sequence
    local openCount = 0
    for _ in cleaned:gmatch("|c%x%x%x%x%x%x%x%x") do openCount = openCount + 1 end
    local closeCount = 0
    for _ in cleaned:gmatch("|r") do closeCount = closeCount + 1 end
    if openCount > closeCount then
        cleaned = cleaned .. string.rep("|r", openCount - closeCount)
    end

    if activeRun and activeRun.id == advId then
        activeRun.story = cleaned
        return true
    end
    for _, adv in ipairs(RPCopyDB.adventures or {}) do
        if adv.id == advId then
            adv.story = cleaned
            return true
        end
    end
    return false
end

function ns.BuildAdventureSummary(adv)
    if not adv then
        return "|cff9e9e9eNo adventure selected. Enter a dungeon/raid or click 'Start New Run' below.|r"
    end

    local lines = {}
    local durSec = adv.duration or (adv.startTime and (time() - adv.startTime) or 0)
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
            table.insert(lines, "  - " .. ns.ColorText(b, ns.COLORS.boss))
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

function ns.BuildAdventureFullLog(adv)
    if not adv then
        return "No adventure selected."
    end

    local out = {}
    local durSec = adv.duration or (adv.startTime and (time() - adv.startTime) or 0)
    table.insert(out, "use story")
    table.insert(out, "[ADVENTURE: " .. (adv.title or "Dungeon Run") .. "]")
    table.insert(out, string.format("Zone: %s | Date: %s | Duration: %s | Wipes: %d | Deaths: %d",
        adv.zone or "Unknown", adv.startDate or "-", ns.FormatDuration(durSec), adv.wipes or 0, adv.deaths or 0))
    table.insert(out, "")

    table.insert(out, "Roster:")
    if adv.participants and #adv.participants > 0 then
        for _, p in ipairs(adv.participants) do
            local rTag = ns.GetRoleTag(p.role, false)
            local rolePart = (rTag ~= "") and (", " .. rTag) or ""
            local notePart = (p.note and p.note ~= "") and (" | RP Note: " .. p.note) or ""
            table.insert(out, string.format("- %s (Lvl %s %s%s)%s",
                p.name, p.level ~= "" and p.level or "?", p.class ~= "" and p.class or "Adventurer", rolePart, notePart))
        end
    else
        table.insert(out, "- Solo Adventurer")
    end
    table.insert(out, "")

    if adv.bossKills and #adv.bossKills > 0 then
        table.insert(out, "Bosses & Elites Defeated: " .. table.concat(adv.bossKills, ", "))
    end
    if adv.keyLoot and #adv.keyLoot > 0 then
        local lootNames = {}
        for _, item in ipairs(adv.keyLoot) do
            local p = type(item) == "table" and item.plain or ns.StripColors(tostring(item))
            local w = (type(item) == "table" and item.looter and item.looter ~= "") and (" (" .. item.looter .. ")") or ""
            table.insert(lootNames, p .. w)
        end
        table.insert(out, "Notable Loot: " .. table.concat(lootNames, ", "))
    end
    if adv.highlights and #adv.highlights > 0 then
        table.insert(out, "")
        table.insert(out, "Starred Highlights:")
        for _, h in ipairs(adv.highlights) do
            local cleanH = ns.StripColors(h)
            table.insert(out, "- " .. cleanH)
        end
    end

    table.insert(out, "")
    table.insert(out, "Full Adventure Timeline:")
    local tl = adv.fullTimeline or {}
    local startIdx = math.max(1, #tl - 249)
    for i = startIdx, #tl do
        local cleanLine = ns.StripColors(tl[i])
        if cleanLine and cleanLine ~= "" then
            table.insert(out, cleanLine)
        end
    end

    return table.concat(out, "\n")
end