local ADDON_NAME, ns = ...

local lastKillerByVictim = {}
local recentLoggedDeaths = {}
local lastCapturedQuestTitle = ""

local function IsBossUnit(unit)
    if not UnitExists(unit) then return false end
    if unit:match("^boss%d+$") then return true end
    local cls = ns.SafeStr(UnitClassification(unit))
    local lvl = ns.SafeNum(UnitLevel(unit))
    if (cls == "worldboss") or (lvl ~= nil and lvl < 0) then return true end
    local name = ns.SafeStr(UnitName(unit))
    if name and RPChroniclerDB and RPChroniclerDB.knownBosses and RPChroniclerDB.knownBosses[name] then return true end
    local activeBoss = ns.GetActiveBossName and ns.GetActiveBossName()
    if name and activeBoss and activeBoss == name then return true end
    -- Classic dungeon bosses are plain elites (no skull, often no boss frames).
    -- Inside an instance, an elite with several times your max health counts.
    if cls == "elite" or cls == "rareelite" then
        local inInstance = IsInInstance and IsInInstance()
        if inInstance then
            local hpMax = ns.SafeNum(UnitHealthMax(unit))
            local myMax = ns.SafeNum(UnitHealthMax("player"))
            if hpMax and myMax and myMax > 0 and hpMax >= myMax * 4 then return true end
        end
    end
    return false
end
ns.IsBossUnit = IsBossUnit

-- Health percent that survives the modern engine: plain numbers first, then
-- UnitHealthPercent where it exists. Returns nil when the value is secret.
local function GetUnitHealthPct(unit)
    local hp = ns.SafeNum(UnitHealth(unit))
    local hpMax = ns.SafeNum(UnitHealthMax(unit))
    if hp and hpMax and hpMax > 0 then
        return math.floor((hp / hpMax) * 100)
    end
    if UnitHealthPercent then
        local ok, v = pcall(UnitHealthPercent, unit)
        v = ok and ns.SafeNum(v) or nil
        if v then
            if v <= 1 and v ~= math.floor(v) then v = v * 100 end
            return math.floor(v)
        end
    end
    return nil
end
ns.GetUnitHealthPct = GetUnitHealthPct

local function CheckInstanceAdventureState(isInitialLogin)
    ns.EnsureDB()
    -- NOTE: "IsInInstance and IsInInstance()" would truncate to ONE return value,
    -- leaving instanceType nil forever. Call it explicitly to keep both values.
    local inInstance, instanceType = false, nil
    if IsInInstance then
        inInstance, instanceType = IsInInstance()
    end
    local isDungeonOrRaid = inInstance and (instanceType == "party" or instanceType == "raid")
    local active = ns.GetActiveAdventure and ns.GetActiveAdventure()

    if isDungeonOrRaid then
        local zoneName = ns.SafeStr(GetRealZoneText()) or ns.GetCurrentWhere()
        if not active then
            -- Options > Recording: "Auto-record dungeons and raids" (on by default)
            if ns.StartAdventure and RPChroniclerDB.autoRecord ~= false then
                ns.StartAdventure(zoneName, true)
            end
        else
            local zoneName2 = ns.SafeStr(GetRealZoneText())
            if active.isAuto and zoneName2 and active.instanceName and zoneName2 ~= active.instanceName then
                -- A different dungeon than the run we were recording
                ns.EndAdventure("Entered " .. zoneName2)
                ns.StartAdventure(zoneName2, true)
            elseif ns.SyncAdventureRoster then
                ns.SyncAdventureRoster()
            end
        end
    else
        -- A paused run stays put until you resume or end it
        if active and active.isAuto and not active.paused and ns.EndAdventure then
            ns.EndAdventure("Left Instance")
        end
    end
end

local restoredThisSession = false
local function RestoreRunOnce()
    if restoredThisSession then return end
    restoredThisSession = true
    if not ns.RestoreSavedAdventure then return end
    local result, run = ns.RestoreSavedAdventure()
    local title = run and run.title or "Adventure"
    if result == "resumed" then
        print("|cffffd100RP Chronicler|r |cff5cb85cStill recording|r |cffeceff1" .. title .. "|r |cff9aa5b4(restored after reload)|r")
    elseif result == "paused" then
        print("|cffffd100RP Chronicler|r |cffffb74dRecording paused|r |cffeceff1" .. title .. "|r |cff9aa5b4- type /rp resume to continue or /rp end to save it|r")
    elseif result == "interrupted" then
        print("|cffffd100RP Chronicler|r |cffffb74dSaved your last run|r |cffeceff1" .. title .. "|r |cff9aa5b4(cut short by a logout or disconnect)|r")
        if ns.OfferInterruptedRun then
            if C_Timer and C_Timer.After then
                C_Timer.After(3, function() ns.OfferInterruptedRun(run) end)
            else
                ns.OfferInterruptedRun(run)
            end
        end
    end
end

-- 0.5.0: chat capture per type (first-run setup, Options > Privacy)
local CAPTURE_OF = {
    Say = "say", Yell = "say", Emote = "say", Whisper = "whisper", ["To"] = "whisper",
    Party = "group", Raid = "group", Instance = "group", ["Raid Warning"] = "group",
    Guild = "guild", Officer = "guild", Channel = "world",
}

local function HandlePlayerChat(channelLabel, colorHex, rawMsg, rawAuthor, rawChannelName)
    local capKey = CAPTURE_OF[channelLabel]
    if capKey and ns.CaptureOn and not ns.CaptureOn(capKey) then return end
    local cleanMsg = ns.CleanText(rawMsg)
    if not cleanMsg or cleanMsg == "" then return end
    if not (ns.IsSecret and ns.IsSecret(rawAuthor)) then
        ns.state.lastRawAuthor = tostring(rawAuthor or "")
    end

    local author = ns.StripRealm(rawAuthor) or "Unknown"
    local speakerTag = ns.FormatSpeakerTag(author)
    local chanPrefix = channelLabel
    if rawChannelName then
        local cName = ns.SafeStr(rawChannelName)
        if cName and cName ~= "" then
            chanPrefix = cName
        end
    end

    local line = string.format("%s %s: %s",
        ns.ColorText("[" .. chanPrefix .. "]", colorHex),
        speakerTag,
        ns.ColorText(cleanMsg, ns.COLORS.text))

    -- World channels and guild get their own buffer, so busy trade or
    -- guild chat never pushes nearby RP out of the say/emote buffer.
    local entry
    if channelLabel == "Party" or channelLabel == "Raid" or channelLabel == "Instance" then
        entry = ns.PushLog(ns.logs.party, line, author, channelLabel)
    elseif channelLabel == "Guild" or channelLabel == "Officer" then
        entry = ns.PushLog(ns.logs.guild, line, author, channelLabel)
    elseif channelLabel == "Channel" then
        entry = ns.PushLog(ns.logs.world, line, author, channelLabel)
    else
        entry = ns.PushLog(ns.logs.social, line, author, channelLabel)
    end

    local selfFirst = ns.StripRealm(UnitName("player")) or ""
    if author ~= "Unknown" and author ~= selfFirst then
        if channelLabel == "Whisper" or channelLabel == "Say" then
            ns.state.lastDirectAuthor = ns.ResolveCanonicalPlayerName(author)
            ns.state.lastDirectMsg = line
            ns.state.lastDirectEntry = entry
        end
    end

    if ns.HandleConversationCapture then
        ns.HandleConversationCapture(channelLabel, author, cleanMsg, false, nil)
    end
    -- Only scene chat goes into a run: say, yell, emote, whisper and group
    -- chat. Guild and world channels (General, Trade, LFG, OOC) stay out.
    if ns.RecordAdventureChat and channelLabel ~= "Channel" and channelLabel ~= "Guild" and channelLabel ~= "Officer" then
        ns.RecordAdventureChat(chanPrefix, author, cleanMsg)
    end
end

local function HandleNpcChat(kindLabel, rawMsg, rawAuthor, isEmote, event)
    if ns.CaptureOn and not ns.CaptureOn("npc") then return end
    local cleanMsg = ns.CleanText(rawMsg)
    if not cleanMsg or cleanMsg == "" then return end
    local npcName = ns.SafeStr(rawAuthor) or "NPC"

    -- Monster emotes arrive as "%s attempts to run away in fear!"
    if cleanMsg:find("%s", 1, true) then
        cleanMsg = cleanMsg:gsub("%%s", (npcName:gsub("%%", "%%%%")))
        isEmote = true
    elseif isEmote and not cleanMsg:find(npcName, 1, true) then
        cleanMsg = npcName .. ": " .. cleanMsg
    end

    local line
    if isEmote then
        line = ns.ColorText("[NPC Emote]", ns.COLORS.npc) .. " " .. ns.ColorText(cleanMsg, ns.COLORS.npcText)
    else
        line = string.format("%s %s: %s",
            ns.ColorText("[" .. kindLabel .. "]", ns.COLORS.npc),
            ns.ColorText(npcName, ns.COLORS.npcName),
            ns.ColorText(cleanMsg, ns.COLORS.npcText))
    end

    ns.PushLog(ns.logs.npc, line, npcName, "NPC")
    -- Runs keep boss and named NPC lines only (throttled, de-duplicated);
    -- flee emotes become part of the [FIGHT] line
    if ns.ChronicleNpc and not ns.ChronicleNpc(npcName, cleanMsg, event) then return end
    if ns.RecordAdventureChat then
        if isEmote then
            ns.RecordAdventureChat("NPC Emote", npcName, cleanMsg, true)
        else
            ns.RecordAdventureChat(kindLabel, npcName, cleanMsg)
        end
    end
end

-- Item quality colors (index = quality). Used when a loot link carries the
-- modern "|cnIQ4:" color tag or no color at all, so lines never render white.
local QUALITY_HEX = {
    [0] = "9d9d9d", -- Poor
    [1] = "ffffff", -- Common
    [2] = "1eff00", -- Uncommon
    [3] = "0070dd", -- Rare
    [4] = "a335ee", -- Epic
    [5] = "ff8000", -- Legendary
    [6] = "e6cc80", -- Artifact
    [7] = "00ccff", -- Heirloom
}
local HEX_TO_QUALITY = {}
for q, hex in pairs(QUALITY_HEX) do HEX_TO_QUALITY[hex] = q end

-- Returns quality number (or nil) and the hex color to draw the link in.
local function ResolveLinkColor(colorTag, linkData, fullLink)
    local q = tonumber((colorTag or ""):match("^nIQ(%d)"))
    local hex = (colorTag or ""):match("^ff(%x%x%x%x%x%x)")
    if hex then hex = hex:lower() end
    if not q and hex then q = HEX_TO_QUALITY[hex] end
    local linkType = (linkData or ""):match("^(%a+):")
    if not q and linkType == "item" then
        local itemId = tonumber(linkData:match("^item:(%d+)"))
        if itemId and C_Item and C_Item.GetItemQualityByID then
            local ok, res = pcall(C_Item.GetItemQualityByID, itemId)
            if ok and type(res) == "number" then q = res end
        end
        if not q and GetItemInfo then
            local ok, _, _, res = pcall(GetItemInfo, fullLink)
            if ok and type(res) == "number" then q = res end
        end
    end
    if q and QUALITY_HEX[q] then
        return q, QUALITY_HEX[q]
    end
    if linkType == "currency" then
        return nil, hex or ns.COLORS.currency
    end
    return nil, hex or QUALITY_HEX[1]
end

local MONEY_WORDS = {
    gold = "coinGold", g = "coinGold",
    silver = "coinSilver", s = "coinSilver",
    copper = "coinCopper", c = "coinCopper",
}

-- Colors a plain text run: coin amounts get gold/silver/copper colors,
-- everything else the soft loot-text color.
local function ColorLootPlain(seg)
    if not seg or seg == "" then return "" end
    local out, last = {}, 1
    for s, num, unit, e in seg:gmatch("()(%d+)%s*(%a+)()") do
        local key = MONEY_WORDS[unit:lower()]
        if key then
            table.insert(out, ns.ColorText(seg:sub(last, s - 1), ns.COLORS.lootType))
            table.insert(out, ns.ColorText(num .. " " .. unit, ns.COLORS[key]))
            last = e
        end
    end
    table.insert(out, ns.ColorText(seg:sub(last), ns.COLORS.lootType))
    return table.concat(out)
end

-- Rebuilds a CHAT_MSG_LOOT / CHAT_MSG_MONEY line with per-quality item colors
-- and coin colors. Returns the colored line plus a list of found items.
local function BuildLootLine(safeMsg)
    local s = safeMsg
    -- Coin icons -> words, so the copied text reads cleanly for the AI
    s = s:gsub("(%d+)%s*|T[^|]-UI%-GoldIcon[^|]-|t", "%1 Gold")
    s = s:gsub("(%d+)%s*|T[^|]-UI%-SilverIcon[^|]-|t", "%1 Silver")
    s = s:gsub("(%d+)%s*|T[^|]-UI%-CopperIcon[^|]-|t", "%1 Copper")
    s = s:gsub("|T.-|t", "")

    local links, items = {}, {}
    local function Capture(full, colorTag, linkData, name)
        local q, hex = ResolveLinkColor(colorTag, linkData, full)
        local colored = ns.ColorText("[" .. name .. "]", hex)
        table.insert(links, colored)
        if (linkData or ""):match("^item:") then
            table.insert(items, { colored = colored, plain = "[" .. name .. "]", quality = q, link = full })
        end
        return "\001" .. #links .. "\002"
    end
    s = s:gsub("(|c([^|]*)|H([^|]*)|h%[([^%]]*)%]|h|r)", Capture)
    s = s:gsub("(|H([^|]*)|h%[([^%]]*)%]|h)", function(full, linkData, name)
        return Capture(full, "", linkData, name)
    end)

    -- Drop any leftover color codes before re-coloring the plain parts
    s = s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|cn[^:|]*:", ""):gsub("|r", "")

    local out, last = {}, 1
    for a, idx, b in s:gmatch("()\001(%d+)\002()") do
        table.insert(out, ColorLootPlain(s:sub(last, a - 1)))
        table.insert(out, links[tonumber(idx)] or "")
        last = b
    end
    table.insert(out, ColorLootPlain(s:sub(last)))
    return table.concat(out), items
end

-- Roll chatter ("X has selected Greed for", "Need Roll - 54 for", "passed on")
-- says nothing the AI needs. Who WON an item is kept.
local ROLL_SPAM = {
    "has selected", "have selected", "passed on", "automatically passed",
    "roll %- %d+", "rolls? %d+", "is not eligible", "you have selected",
}
local function IsRollSpam(plain)
    local low = (plain or ""):lower()
    if low:find(" won:", 1, true) or low:find(" won ", 1, true) then return false end
    for _, pat in ipairs(ROLL_SPAM) do
        if low:find(pat) then return true end
    end
    return false
end

-- Coin you pick up is summed into one [Loot] line instead of a line per corpse.
-- A pickup more than 2 minutes after the last one starts a new line.
local coinSum = { copper = 0, count = 0, at = 0, entry = nil }
local function ParseCopper(msg)
    local s = (msg or ""):gsub("|T[^|]-UI%-GoldIcon[^|]-|t", " Gold"):gsub("|T[^|]-UI%-SilverIcon[^|]-|t", " Silver")
        :gsub("|T[^|]-UI%-CopperIcon[^|]-|t", " Copper")
    s = ns.StripColors(s)
    local g = tonumber(s:match("(%d+)%s*[Gg]old")) or 0
    local sv = tonumber(s:match("(%d+)%s*[Ss]ilver")) or 0
    local c = tonumber(s:match("(%d+)%s*[Cc]opper")) or 0
    return g * 10000 + sv * 100 + c
end
local function FormatCoin(copper)
    local g = math.floor(copper / 10000)
    local sv = math.floor((copper % 10000) / 100)
    local c = copper % 100
    local parts = {}
    if g > 0 then table.insert(parts, ns.ColorText(g .. " Gold", ns.COLORS.coinGold)) end
    if sv > 0 then table.insert(parts, ns.ColorText(sv .. " Silver", ns.COLORS.coinSilver)) end
    if c > 0 or #parts == 0 then table.insert(parts, ns.ColorText(c .. " Copper", ns.COLORS.coinCopper)) end
    return table.concat(parts, " ")
end
local function AddCoinPickup(msg)
    local copper = ParseCopper(msg)
    if copper <= 0 then return end
    local now = GetTime()
    local last = ns.logs.loot[#ns.logs.loot]
    if coinSum.entry and last == coinSum.entry and (now - coinSum.at) <= 120 then
        coinSum.copper = coinSum.copper + copper
        coinSum.count = coinSum.count + 1
    else
        coinSum.copper, coinSum.count = copper, 1
        coinSum.entry = ns.PushLog(ns.logs.loot, "-", nil, "Loot")
    end
    coinSum.at = now
    local pickups = coinSum.count > 1 and (" " .. ns.ColorText("(" .. coinSum.count .. " pickups)", ns.COLORS.lootType)) or ""
    coinSum.entry.line = ns.ColorText("[Loot]", ns.COLORS.lootTag) .. " " .. ns.ColorText("You picked up ", ns.COLORS.lootType)
        .. FormatCoin(coinSum.copper) .. pickups
    -- Keep it at the end of the timeline order
    ns.logSeq = ns.logSeq + 1
    coinSum.entry.seq = ns.logSeq
end

local function HandleLootMessage(rawMsg, rawAuthor, isMoney)
    local safeMsg = ns.SafeStr(rawMsg)
    if not safeMsg or safeMsg == "" then return end

    local cleanPlain = ns.CleanText(safeMsg) or ""
    local looter = ns.StripRealm(rawAuthor)
    if not looter or looter == "" then
        looter = cleanPlain:match("^([^%s]+)%s+receives loot:")
            or cleanPlain:match("^([^%s]+)%s+won:")
            or ns.GetUnitFullName("player")
            or ns.StripRealm(UnitName("player"))
            or "Player"
    end

    local ok, coloredLine, items = pcall(BuildLootLine, safeMsg)
    if not ok or not coloredLine or coloredLine == "" then
        coloredLine = ns.ColorText(cleanPlain, ns.COLORS.lootType)
        items = {}
    end

    -- Copy log: green and better items, your own coin (summed), and no roll spam
    local keep = #(items or {}) == 0 -- currency and other non-item lines stay
    for _, item in ipairs(items or {}) do
        if item.quality == nil or item.quality >= 2 then keep = true end
    end
    if isMoney then
        AddCoinPickup(safeMsg)
        if ns.RecordAdventureCoin then ns.RecordAdventureCoin(ParseCopper(safeMsg)) end
    elseif keep and not IsRollSpam(cleanPlain) then
        local line = ns.ColorText("[Loot]", ns.COLORS.lootTag) .. " " .. coloredLine
        ns.PushLog(ns.logs.loot, line, looter, "Loot")
    end

    -- Runs: green and better (also in the Notable Loot header) and quest
    -- items, each with where it came from
    if isMoney or not ns.RecordAdventureLoot or IsRollSpam(cleanPlain) then return end
    local selfName = ns.StripRealm(UnitName("player"))
    local isSelf = (ns.StripRealm(looter) == selfName) or cleanPlain:find("^You ") ~= nil
    local source = ns.ClassifyLootSource and ns.ClassifyLootSource(cleanPlain, isSelf) or nil
    for _, item in ipairs(items or {}) do
        if item.quality and item.quality >= 2 then
            ns.RecordAdventureLoot(item.colored, item.plain, looter, source, true)
        elseif ns.IsQuestItem and ns.IsQuestItem(item.link) then
            ns.RecordAdventureLoot(item.colored, item.plain, looter, source and ("quest item, " .. source) or "quest item", false)
        end
    end
end

local function CaptureQuestContext(prefixLabel, questID)
    local title = nil
    if questID and C_QuestLog and C_QuestLog.GetTitleForQuestID then
        local ok, qTitle = pcall(C_QuestLog.GetTitleForQuestID, questID)
        title = ok and ns.SafeStr(qTitle) or nil
    end
    if (not title or title == "") and GetTitleText then
        local ok, qTitle = pcall(GetTitleText)
        title = ok and ns.SafeStr(qTitle) or nil
    end
    if not title or title == "" then return end

    lastCapturedQuestTitle = title
    -- One quest line only: the snapshot's [Quest] line reads this. Quest
    -- lines are no longer copied into the NPC buffer as well.
    ns.state.lastQuestInfo = string.format("%s: %s", prefixLabel, title)
end

local eventFrame = CreateFrame("Frame", "RPChroniclerEventFrame")
local EVENTS = {
    "PLAYER_LOGIN",
    "PLAYER_ENTERING_WORLD",
    "ZONE_CHANGED_NEW_AREA",
    "GROUP_ROSTER_UPDATE",
    "PLAYER_TARGET_CHANGED",
    "UPDATE_MOUSEOVER_UNIT",
    "PLAYER_REGEN_DISABLED",
    "PLAYER_REGEN_ENABLED",
    "ENCOUNTER_START",
    "ENCOUNTER_END",
    "UNIT_HEALTH",
    "UNIT_POWER_UPDATE",
    "UNIT_THREAT_SITUATION_UPDATE",
    "UNIT_THREAT_LIST_UPDATE",
    "PLAYER_LOGOUT",
    "PLAYER_DEAD",
    "PLAYER_LEVEL_UP",
    "CHAT_MSG_SAY",
    "CHAT_MSG_YELL",
    "CHAT_MSG_EMOTE",
    "CHAT_MSG_TEXT_EMOTE",
    "CHAT_MSG_WHISPER",
    "CHAT_MSG_WHISPER_INFORM",
    "CHAT_MSG_PARTY",
    "CHAT_MSG_PARTY_LEADER",
    "CHAT_MSG_RAID",
    "CHAT_MSG_RAID_LEADER",
    "CHAT_MSG_RAID_WARNING",
    "CHAT_MSG_INSTANCE_CHAT",
    "CHAT_MSG_INSTANCE_CHAT_LEADER",
    "CHAT_MSG_GUILD",
    "CHAT_MSG_OFFICER",
    "CHAT_MSG_CHANNEL",
    "CHAT_MSG_MONSTER_SAY",
    "CHAT_MSG_MONSTER_YELL",
    "CHAT_MSG_MONSTER_EMOTE",
    "CHAT_MSG_MONSTER_WHISPER",
    "CHAT_MSG_RAID_BOSS_EMOTE",
    "CHAT_MSG_RAID_BOSS_WHISPER",
    "CHAT_MSG_LOOT",
    "CHAT_MSG_MONEY",
    "QUEST_DETAIL",
    "QUEST_PROGRESS",
    "QUEST_COMPLETE",
    "QUEST_ACCEPTED",
    "QUEST_TURNED_IN",
}

-- The Forever client runs on the modern (secret-values) engine, where
-- COMBAT_LOG_EVENT_UNFILTERED is protected. Registering it from an addon
-- raises ADDON_ACTION_FORBIDDEN ("blocked from an action only available to
-- the Blizzard UI"), so RP Chronicler never registers it. Boss HP, pull ends and
-- aggro come from the combat poller below; boss kills from ENCOUNTER_END
-- and dead units; your own deaths from PLAYER_DEAD.
ns.combatLogAvailable = false

for _, ev in ipairs(EVENTS) do
    pcall(eventFrame.RegisterEvent, eventFrame, ev)
end

-- =========================================================
-- Combat poller (no combat log needed)
--  * live [BOSS HP] milestones from boss / target / focus / party targets
--  * pull end: the whole group out of combat -> boss milestones reset
--  * [AGGRO] when an enemy's target moves from one party member to another
-- Plain frame + OnUpdate: never touches protected functions.
-- =========================================================
do
    local POLL_EVERY = 0.4
    local PULL_END_GRACE = 2.5
    local AGGRO_MOB_COOLDOWN = 4
    local AGGRO_GLOBAL_COOLDOWN = 1.5

    local poller = CreateFrame("Frame")
    local acc = 0
    local groupInCombat = false
    local lastCombatSeen = 0
    local mobTargets = {}   -- mob key -> { name = holder, t = time }
    local mobSwapAt = {}    -- mob key -> last logged swap time
    local lastSwapLog = 0
    local seen = {}

    local function ClearTable(t)
        for k in pairs(t) do t[k] = nil end
    end

    local BOSS_UNITS = { "boss1", "boss2", "boss3", "boss4", "boss5", "target", "focus",
        "party1target", "party2target", "party3target", "party4target" }

    local function IsTrue(v)
        return v == true and not ns.IsSecret(v)
    end

    local function AnyGroupInCombat()
        if UnitAffectingCombat and IsTrue(UnitAffectingCombat("player")) then return true end
        for i = 1, 4 do
            local u = "party" .. i
            if UnitExists(u) and UnitAffectingCombat and IsTrue(UnitAffectingCombat(u)) then return true end
        end
        return false
    end

    -- Name of the party member (or party pet) a unit token points at, else nil
    local function GroupHolderName(u)
        if not UnitExists(u) or not UnitIsUnit then return nil end
        local function Is(other)
            local ok, r = pcall(UnitIsUnit, u, other)
            return ok and IsTrue(r)
        end
        if Is("player") then return ns.StripRealm(UnitName("player")) end
        if Is("pet") then return ns.SafeStr(UnitName("pet")) end
        for i = 1, 4 do
            if Is("party" .. i) then return ns.StripRealm(UnitName("party" .. i)) end
            if Is("partypet" .. i) then return ns.SafeStr(UnitName("partypet" .. i)) end
        end
        return nil
    end

    local function DisplayName(short)
        if not short then return nil end
        return (ns.ResolveCanonicalPlayerName and ns.ResolveCanonicalPlayerName(short)) or short
    end

    local function PollBossHP()
        if not ns.RecordAdventureBossHP then return end
        ClearTable(seen)
        local activeBoss = ns.GetActiveBossName and ns.GetActiveBossName()
        for _, u in ipairs(BOSS_UNITS) do
            if activeBoss and UnitExists(u) and UnitIsDead(u) and not UnitIsPlayer(u)
                and ns.SafeStr(UnitName(u)) == activeBoss then
                -- The boss died on someone's target or a boss frame (kills are de-duplicated)
                if ns.RecordAdventureBossKill and ns.RecordAdventureBossKill(activeBoss) and ns.RequestScreenshot then
                    ns.RequestScreenshot("boss", "Defeated " .. activeBoss)
                end
                activeBoss = nil
            elseif UnitExists(u) and not UnitIsDead(u) and UnitCanAttack("player", u) and not UnitIsPlayer(u) and IsBossUnit(u) then
                local bName = ns.SafeStr(UnitName(u))
                if bName and not seen[bName] then
                    seen[bName] = true
                    if ns.RecordAdventureBossEngage then ns.RecordAdventureBossEngage(bName, u) end
                    local pct = GetUnitHealthPct(u)
                    if pct then ns.RecordAdventureBossHP(bName, pct) end
                end
            end
        end
    end

    local function ScanMob(u, now)
        if ns.FightSeeUnit then ns.FightSeeUnit(u) end
        if not UnitExists(u) or UnitIsPlayer(u) or UnitIsDead(u) then return end
        if not UnitCanAttack("player", u) then return end
        if UnitAffectingCombat and not IsTrue(UnitAffectingCombat(u)) then return end
        local mobName = ns.SafeStr(UnitName(u))
        if not mobName then return end
        local key = (UnitGUID and ns.SafeStr(UnitGUID(u))) or (mobName .. ":" .. u)
        if seen[key] then return end
        seen[key] = true

        local holder = GroupHolderName(u .. "target")
        if not holder then return end -- fleeing, stunned or targeting nobody: keep the last holder
        if ns.RecordAdventureAggroSample then ns.RecordAdventureAggroSample(DisplayName(holder)) end

        local prev = mobTargets[key]
        mobTargets[key] = { name = holder, t = now }
        if prev and prev.name ~= holder then
            if (now - (mobSwapAt[key] or 0)) >= AGGRO_MOB_COOLDOWN and (now - lastSwapLog) >= AGGRO_GLOBAL_COOLDOWN then
                mobSwapAt[key] = now
                lastSwapLog = now
                if ns.RecordAdventureAggroSwap then
                    ns.RecordAdventureAggroSwap(mobName, DisplayName(prev.name), DisplayName(holder))
                end
            end
        end
    end

    local function PollAggro(now)
        ClearTable(seen)
        ScanMob("target", now)
        ScanMob("focus", now)
        ScanMob("mouseover", now)
        for i = 1, 4 do ScanMob("party" .. i .. "target", now) end
        for i = 1, 5 do ScanMob("boss" .. i, now) end
        for i = 1, 40 do
            local u = "nameplate" .. i
            if UnitExists(u) then ScanMob(u, now) end
        end
    end

    local function Tick()
        local run = ns.GetActiveAdventure and ns.GetActiveAdventure()
        if not run or run.paused then
            groupInCombat = false
            return
        end
        local now = GetTime()
        if AnyGroupInCombat() then
            if ns.FightBegin then ns.FightBegin() end
            groupInCombat = true
            lastCombatSeen = now
            PollBossHP()
            PollAggro(now)
        elseif groupInCombat and (now - lastCombatSeen) >= PULL_END_GRACE then
            groupInCombat = false
            ClearTable(mobTargets)
            ClearTable(mobSwapAt)
            if ns.EndAdventureBossPull then ns.EndAdventureBossPull() end
            if ns.FightFlush then ns.FightFlush() end
        end
    end

    poller:SetScript("OnUpdate", function(_, elapsed)
        acc = acc + elapsed
        if acc < POLL_EVERY then return end
        acc = 0
        local ok, err = pcall(Tick)
        if not ok and not poller.reported then
            poller.reported = true
            if ns.Debug then ns.Debug("error", "combat poller: " .. tostring(err)) end
            print("|cffffd100RP Chronicler|r |cffff6b6bcombat poller error:|r " .. tostring(err) .. " |cff9aa5b4(/rp debug for a report)|r")
        end
    end)

    -- Threat events just make the next poll happen right away
    function ns.PollCombatSoon()
        acc = POLL_EVERY
    end

    -- /rp diag: what RP Chronicler can read about your target on this client
    function ns.DiagnoseTarget()
        local out = {}
        local u = "target"
        if not UnitExists(u) then
            table.insert(out, "No target. Target an enemy (ideally a boss) and run /rp diag again.")
        else
            local name = ns.SafeStr(UnitName(u)) or "(secret)"
            local cls = ns.SafeStr(UnitClassification(u)) or "(secret)"
            local lvl = ns.SafeNum(UnitLevel(u))
            local pct = GetUnitHealthPct(u)
            table.insert(out, string.format("Target: %s | class: %s | level: %s", name, cls, lvl and tostring(lvl) or "(secret)"))
            table.insert(out, "Health readable: " .. (pct and (pct .. "%") or "NO (secret or missing)"))
            table.insert(out, "Counts as boss: " .. (IsBossUnit(u) and "yes" or "no"))
            local holder = GroupHolderName(u .. "target")
            table.insert(out, "Its target: " .. (holder or (ns.SafeStr(UnitName(u .. "target")) or "none")))
        end
        local role, guessed = "NONE", false
        if ns.GetUnitRole then role, guessed = ns.GetUnitRole("player") end
        table.insert(out, "Your role: " .. role .. (guessed and " (guessed)" or " (assigned)"))
        table.insert(out, "Boss frames: " .. (UnitExists("boss1") and "yes" or "none now")
            .. " | threat API: " .. (UnitDetailedThreatSituation and "yes" or "no")
            .. " | UnitHealthPercent: " .. (UnitHealthPercent and "yes" or "no"))
        return out
    end

    -- PLAYER_REGEN_* hooks (called from the main handler)
    function ns.NoteCombatStarted()
        groupInCombat = true
        lastCombatSeen = GetTime()
        acc = POLL_EVERY
    end
end

eventFrame:SetScript("OnEvent", function(_, event, ...)
    if event == "PLAYER_LOGIN" then
        ns.EnsureDB()
        if ns.DebugReady then ns.DebugReady() end
        if ns.Debug then ns.Debug("info", "login, version " .. tostring(ns.VERSION or "?")) end
        -- Version banner, read from the toc's ## Version field (see Core.lua)
        print(string.format("|cffffd100RP Chronicler|r |cff69ccf0v%s|r |cff9aa5b4loaded - /rp to open|r", tostring(ns.VERSION or "?")))
        if ns.loginNotice then print(ns.loginNotice) end
    elseif event == "PLAYER_ENTERING_WORLD" then
        -- Zone info is reliable here, so a saved run is restored at the first one
        RestoreRunOnce()
        CheckInstanceAdventureState()
    elseif event == "PLAYER_LOGOUT" then
        if ns.TouchActiveAdventure then ns.TouchActiveAdventure(true) end
    elseif event == "UNIT_THREAT_SITUATION_UPDATE" or event == "UNIT_THREAT_LIST_UPDATE" then
        if ns.PollCombatSoon then ns.PollCombatSoon() end
    elseif event == "ZONE_CHANGED_NEW_AREA" then
        if ns.RequestScreenshot then
            ns.RequestScreenshot("newzone", ns.GetCurrentWhere())
        end
    elseif event == "GROUP_ROSTER_UPDATE" then
        if ns.SyncAdventureRoster then
            ns.SyncAdventureRoster()
        end
    elseif event == "PLAYER_TARGET_CHANGED" or event == "UPDATE_MOUSEOVER_UNIT" then
        local unit = (event == "PLAYER_TARGET_CHANGED") and "target" or "mouseover"
        if UnitExists(unit) and UnitIsPlayer(unit) and RPChroniclerDB and RPChroniclerDB.autoUpdateKnown then
            local fullName = ns.GetUnitFullName(unit)
            local key = fullName and ns.FindPlayerKey(fullName, true)
            if key and RPChroniclerDB.players[key] then
                ns.CaptureVisibleUnitFields(unit, RPChroniclerDB.players[key])
            end
        elseif event == "PLAYER_TARGET_CHANGED" and UnitExists("target") and UnitCanAttack("player", "target") and not UnitIsDead("target") then
            if IsBossUnit("target") and UnitAffectingCombat and UnitAffectingCombat("player") then
                local bName = ns.SafeStr(UnitName("target"))
                if bName and ns.RecordAdventureBossEngage then
                    ns.RecordAdventureBossEngage(bName, "target")
                end
            end
        end
    elseif event == "PLAYER_REGEN_DISABLED" then
        -- No "[Combat] Entered combat" line: the [Status] line already says
        -- In Combat / Out of Combat, and the extra lines crowded the slices.
        if ns.RecordAdventureCombatState then
            ns.RecordAdventureCombatState(true)
        end
        if ns.NoteCombatStarted then ns.NoteCombatStarted() end
        if UnitExists("target") and IsBossUnit("target") and UnitCanAttack("player", "target") then
            local bName = ns.SafeStr(UnitName("target"))
            if bName and ns.RecordAdventureBossEngage then
                ns.RecordAdventureBossEngage(bName, "target")
            end
        end
    elseif event == "PLAYER_REGEN_ENABLED" then
        if ns.RecordAdventureCombatState then
            ns.RecordAdventureCombatState(false)
        end
    elseif event == "ENCOUNTER_START" then
        local _, encounterName = ...
        local bName = ns.SafeStr(encounterName)
        if bName and ns.RecordAdventureBossEngage then
            ns.RecordAdventureBossEngage(bName)
        end
    elseif event == "ENCOUNTER_END" then
        local _, encounterName, _, _, success = ...
        local bName = ns.SafeStr(encounterName)
        if bName and success == 1 then
            local recorded = ns.RecordAdventureBossKill and ns.RecordAdventureBossKill(bName)
            if recorded and ns.RequestScreenshot then
                ns.RequestScreenshot("boss", "Defeated " .. bName)
            end
        elseif bName and ns.EndAdventureBossPull then
            -- Wipe or reset: the next attempt logs its milestones again
            ns.EndAdventureBossPull()
        end
    elseif event == "UNIT_HEALTH" then
        local unit = ...
        if not unit then return end
        if unit == "target" or unit:match("^boss%d+$") then
            if UnitExists(unit) and UnitIsDead(unit) then
                -- Boss-kill fallback now that the combat log is off-limits:
                -- a dead boss frame, skull/worldboss, or the boss we were fighting.
                local bName = ns.SafeStr(UnitName(unit))
                local activeBoss = ns.GetActiveBossName and ns.GetActiveBossName()
                local isBoss = unit:match("^boss%d+$") or IsBossUnit(unit)
                    or (bName and activeBoss and activeBoss:lower() == bName:lower())
                if bName and isBoss and ns.RecordAdventureBossKill then
                    if ns.RecordAdventureBossKill(bName) and ns.RequestScreenshot then
                        ns.RequestScreenshot("boss", "Defeated " .. bName)
                    end
                end
            elseif UnitExists(unit) and UnitCanAttack("player", unit) then
                if IsBossUnit(unit) then
                    local bName = ns.SafeStr(UnitName(unit))
                    local pct = GetUnitHealthPct(unit)
                    if bName and pct then
                        if ns.RecordAdventureBossEngage and UnitAffectingCombat and UnitAffectingCombat("player") then
                            ns.RecordAdventureBossEngage(bName, unit)
                        end
                        if ns.RecordAdventureBossHP then
                            ns.RecordAdventureBossHP(bName, pct)
                        end
                    end
                end
            end
        elseif unit == "player" or unit:match("^party%d+$") then
            if ns.RecordAdventureUnitVitals then
                ns.RecordAdventureUnitVitals(unit)
            end
        end
    elseif event == "UNIT_POWER_UPDATE" then
        local unit = ...
        if unit == "player" or (unit and unit:match("^party%d+$")) then
            if ns.RecordAdventureUnitVitals then
                ns.RecordAdventureUnitVitals(unit)
            end
        end
    elseif event == "PLAYER_DEAD" then
        local selfName = ns.StripRealm(UnitName("player")) or "Player"
        local now = GetTime()
        if not recentLoggedDeaths[selfName] or (now - recentLoggedDeaths[selfName]) > 3 then
            recentLoggedDeaths[selfName] = now
            if ns.RecordAdventureDeath then
                ns.RecordAdventureDeath(selfName, true, lastKillerByVictim[selfName])
            end
            local e = ns.PushLog(ns.logs.combat, ns.ColorText("died", ns.COLORS.death))
            if e then e.at = time() end
        end
    elseif event == "PLAYER_LEVEL_UP" then
        local newLevel = ns.SafeNum((...))
        if newLevel then
            local e = ns.PushLog(ns.logs.combat, ns.ColorText("reached level " .. newLevel, ns.COLORS.gold))
            if e then e.at = time() end
            if ns.RequestScreenshot then
                ns.RequestScreenshot("levelup", "Reached Level " .. newLevel)
            end
        end
    elseif event == "CHAT_MSG_SAY" then
        local msg, author = ...
        HandlePlayerChat("Say", ns.COLORS.say, msg, author)
    elseif event == "CHAT_MSG_YELL" then
        local msg, author = ...
        HandlePlayerChat("Yell", ns.COLORS.yell, msg, author)
    elseif event == "CHAT_MSG_EMOTE" or event == "CHAT_MSG_TEXT_EMOTE" then
        local msg, author = ...
        HandlePlayerChat("Emote", ns.COLORS.emote, msg, author)
    elseif event == "CHAT_MSG_WHISPER" then
        local msg, author = ...
        HandlePlayerChat("Whisper", ns.COLORS.whisper, msg, author)
    elseif event == "CHAT_MSG_WHISPER_INFORM" then
        local msg, recipient = ...
        local cleanMsg = ns.CleanText(msg)
        if ns.CaptureOn and not ns.CaptureOn("whisper") then cleanMsg = nil end
        if cleanMsg and cleanMsg ~= "" then
            local selfName = ns.StripRealm(UnitName("player")) or "Me"
            local recipClean = ns.StripRealm(recipient) or "Unknown"
            local line = string.format("%s To [%s]: %s",
                ns.ColorText("[Whisper]", ns.COLORS.whisper),
                ns.ColorText(recipClean, ns.COLORS.speaker),
                ns.ColorText(cleanMsg, ns.COLORS.text))
            local wEntry = ns.PushLog(ns.logs.social, line, selfName, "Whisper")
            if type(wEntry) == "table" then wEntry.to = recipClean end
            if ns.HandleConversationCapture then
                ns.HandleConversationCapture("Whisper", selfName, cleanMsg, true, recipClean)
            end
            if ns.RecordAdventureChat then
                ns.RecordAdventureChat("Whisper -> " .. recipClean, selfName, cleanMsg)
            end
        end
    elseif event == "CHAT_MSG_PARTY" or event == "CHAT_MSG_PARTY_LEADER" then
        local msg, author = ...
        HandlePlayerChat("Party", ns.COLORS.party, msg, author)
    elseif event == "CHAT_MSG_RAID" or event == "CHAT_MSG_RAID_LEADER" or event == "CHAT_MSG_RAID_WARNING" then
        local msg, author = ...
        HandlePlayerChat("Raid", ns.COLORS.raid, msg, author)
    elseif event == "CHAT_MSG_INSTANCE_CHAT" or event == "CHAT_MSG_INSTANCE_CHAT_LEADER" then
        local msg, author = ...
        HandlePlayerChat("Instance", ns.COLORS.instanceChat, msg, author)
    elseif event == "CHAT_MSG_GUILD" then
        local msg, author = ...
        HandlePlayerChat("Guild", ns.COLORS.guild, msg, author)
    elseif event == "CHAT_MSG_OFFICER" then
        local msg, author = ...
        HandlePlayerChat("Officer", ns.COLORS.guild, msg, author)
    elseif event == "CHAT_MSG_CHANNEL" then
        local msg, author, _, channelName = ...
        HandlePlayerChat("Channel", ns.COLORS.channel, msg, author, channelName)
    elseif event == "CHAT_MSG_MONSTER_SAY" or event == "CHAT_MSG_MONSTER_YELL" or event == "CHAT_MSG_MONSTER_EMOTE" or event == "CHAT_MSG_MONSTER_WHISPER" or event == "CHAT_MSG_RAID_BOSS_EMOTE" or event == "CHAT_MSG_RAID_BOSS_WHISPER" then
        local msg, author = ...
        local isEmote = (event == "CHAT_MSG_MONSTER_EMOTE" or event == "CHAT_MSG_RAID_BOSS_EMOTE")
        HandleNpcChat("NPC", msg, author, isEmote, event)
    elseif event == "CHAT_MSG_LOOT" or event == "CHAT_MSG_MONEY" then
        local msg, author = ...
        HandleLootMessage(msg, author, event == "CHAT_MSG_MONEY")
    elseif event == "QUEST_DETAIL" or event == "QUEST_PROGRESS" or event == "QUEST_COMPLETE" then
        CaptureQuestContext("Active Quest")
    elseif event == "QUEST_ACCEPTED" then
        local arg1, arg2 = ...
        local qId = ns.SafeNum(arg2) or ns.SafeNum(arg1)
        CaptureQuestContext("Accepted Quest", qId)
    elseif event == "QUEST_TURNED_IN" then
        local qId = ns.SafeNum((...))
        CaptureQuestContext("Completed Quest", qId)
        if ns.RequestScreenshot and lastCapturedQuestTitle ~= "" then
            ns.RequestScreenshot("quest", "Completed: " .. lastCapturedQuestTitle)
        end
    end
end)

-- =========================================================
-- Extra run telemetry, still without the combat log (0.3.1):
--  * [SPELL]      spells your party casts in combat (UNIT_SPELLCAST_SUCCEEDED)
--  * [BOSS CAST]  what a boss casts (boss1-5, target, focus, nameplates)
--  * [CC]         party members charmed, feared, stunned, polymorphed ...
--  * [PET]        pets badly hurt, dying and coming back
-- Only while a run records inside a dungeon or raid. Every tracker is
-- throttled, wrapped in pcall, and skips values the client hides as secret.
-- =========================================================
do
    local tracker = CreateFrame("Frame")
    for _, ev in ipairs({ "UNIT_SPELLCAST_SUCCEEDED", "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_CHANNEL_START",
        "UNIT_AURA", "UNIT_PET", "UNIT_HEALTH" }) do
        pcall(tracker.RegisterEvent, tracker, ev)
    end

    local T = {
        GROUP = { player = true, party1 = true, party2 = true, party3 = true, party4 = true },
        PETS = { pet = "player", partypet1 = "party1", partypet2 = "party2", partypet3 = "party3", partypet4 = "party4" },
        SKIP_SPELLS = { ["Auto Shot"] = true, ["Shoot"] = true, ["Attack"] = true, ["Auto Attack"] = true },
        SPELL_UNIT_CD = 30, SPELL_GAP = 1.0, WORLD_SPELL_CD = 60, WORLD_SPELL_GAP = 3.0,
        BOSS_CAST_CD = 12,
        BIG_CD = { ["bestial wrath"] = true, ["rapid fire"] = true, ["recklessness"] = true, ["shield wall"] = true,
            ["last stand"] = true, ["avenging wrath"] = true, ["divine shield"] = true, ["lay on hands"] = true,
            ["divine intervention"] = true, ["icy veins"] = true, ["arcane power"] = true, ["combustion"] = true,
            ["evocation"] = true, ["ice block"] = true, ["innervate"] = true, ["tranquility"] = true, ["rebirth"] = true,
            ["bloodlust"] = true, ["heroism"] = true, ["power infusion"] = true, ["adrenaline rush"] = true,
            ["blade flurry"] = true, ["evasion"] = true, ["vanish"] = true, ["feign death"] = true, ["death wish"] = true,
            ["barkskin"] = true, ["metamorphosis"] = true, ["soulstone resurrection"] = true, ["fear ward"] = true,
            ["mana tide totem"] = true, ["reincarnation"] = true, ["shadowfiend"] = true, ["guardian spirit"] = true },
        spellAt = {}, lastSpell = 0, bossCastAt = {}, bossStartAt = {},
        cc = {}, charmed = {}, auraScanAt = {}, pets = {},
        CC_WORDS = { "polymorph", "fear", "psychic scream", "intimidating shout", "howl of terror", "death coil",
            "sap", "gouge", "blind", "kidney shot", "cheap shot", "hammer of justice", "repentance", "hibernate",
            "entangling roots", "frost nova", "freezing trap", "scatter shot", "wyvern sting", "seduction",
            "banish", "mind control", "hex", "cyclone", "bash", "war stomp", "concussion blow", "stun",
            "sleep", "knockdown", "terrify", "horror", "petrify", "silence", "shackle", "charm", "dominat",
            "paralyz", "frozen", "freeze", "web", "net", "trance", "sheep" },
    }

    -- 0.4.0: open-world runs are tracked too, with stricter throttles.
    -- Returns the run and whether it is inside a dungeon or raid.
    local function Recording()
        local run = ns.GetActiveAdventure and ns.GetActiveAdventure()
        if not run or run.paused then return nil end
        local inInstance = false
        if IsInInstance then inInstance = IsInInstance() and true or false end
        return run, inInstance
    end

    local function ShortName(unit)
        local n = ns.StripRealm(UnitName(unit))
        if not n or n == "" then return nil end
        return (ns.ResolveCanonicalPlayerName and ns.ResolveCanonicalPlayerName(n)) or n
    end

    local function SpellName(spellID)
        local id = ns.SafeNum(spellID)
        if not id then return nil end
        if C_Spell and C_Spell.GetSpellName then
            local ok, n = pcall(C_Spell.GetSpellName, id)
            if ok then return ns.SafeStr(n) end
        end
        if GetSpellInfo then
            local ok, n = pcall(GetSpellInfo, id)
            if ok then return ns.SafeStr(n) end
        end
        return nil
    end

    local function GroupInCombat()
        if UnitAffectingCombat and UnitAffectingCombat("player") == true then return true end
        for i = 1, 4 do
            local u = "party" .. i
            if UnitExists(u) and UnitAffectingCombat and UnitAffectingCombat(u) == true then return true end
        end
        return false
    end

    local function TargetSuffix(unit, word)
        local tu = unit .. "target"
        if not UnitExists(tu) or (UnitIsUnit and UnitIsUnit(tu, unit) == true) then return "" end
        local n = ns.SafeStr(UnitName(tu))
        return n and (" " .. word .. " " .. ns.StripRealm(n)) or ""
    end

    -- [SPELL] party casts, pets included
    local function OnPartySpell(run, unit, spellID, inInstance)
        if not GroupInCombat() or not ns.LogOn("spells") then return end
        local who, short
        if T.PETS[unit] then
            local petName, owner = ns.SafeStr(UnitName(unit)), ShortName(T.PETS[unit])
            who = petName and owner and string.format("%s (%s's pet)", petName, owner)
            short = petName
        else
            who = ShortName(unit)
            short = who
        end
        local spell = SpellName(spellID)
        if not who or not spell or T.SKIP_SPELLS[spell] then return end
        -- 0.5.0: abilities fold into the [FIGHT] line ("used Arcane Shot;
        -- Snips: Claw"). Only crowd control and big cooldowns stand alone.
        local low = spell:lower()
        local notable = T.BIG_CD[low] or false
        if not notable then
            for _, w in ipairs(T.CC_WORDS) do
                if low:find("%f[%a]" .. w) then notable = true break end
            end
        end
        local folded = ns.FightNoteSpell and ns.FightNoteSpell(unit == "player" and "you" or short, spell)
        if folded and not notable then return end
        local now = GetTime()
        local key = who .. ":" .. spell
        local cd = inInstance and T.SPELL_UNIT_CD or T.WORLD_SPELL_CD
        local gap = inInstance and T.SPELL_GAP or T.WORLD_SPELL_GAP
        if (now - (T.spellAt[key] or 0)) < cd or (now - T.lastSpell) < gap then return end
        run.spellLines = run.spellLines or 0
        if run.spellLines >= ns.Limit("spellCap") then return end
        run.spellLines = run.spellLines + 1
        T.spellAt[key] = now
        T.lastSpell = now
        ns.RecordAdventureLine(string.format("[SPELL] %s casts %s%s", who, spell, TargetSuffix(unit, "on")))
    end

    -- [BOSS CAST]
    local function OnBossCast(unit, spellID, started)
        if not ns.LogOn("bossCasts") then return end
        if UnitIsPlayer(unit) or not UnitCanAttack("player", unit) then return end
        local bName = ns.SafeStr(UnitName(unit))
        if not bName then return end
        local activeBoss = ns.GetActiveBossName and ns.GetActiveBossName()
        if bName ~= activeBoss and not (ns.IsBossUnit and ns.IsBossUnit(unit)) then return end
        local spell = SpellName(spellID)
        if not spell or T.SKIP_SPELLS[spell] then return end
        local now = GetTime()
        local key = bName .. ":" .. spell
        if not started and (now - (T.bossStartAt[key] or 0)) < 6 then return end -- its START was logged
        if (now - (T.bossCastAt[key] or 0)) < T.BOSS_CAST_CD then return end
        T.bossCastAt[key] = now
        if started then T.bossStartAt[key] = now end
        local verb = started and "begins casting" or "casts"
        ns.RecordAdventureLine(string.format("[BOSS CAST] %s %s %s%s", bName, verb, spell, TargetSuffix(unit, "at")))
    end

    local function IsCC(name)
        local low = name:lower()
        for _, w in ipairs(T.CC_WORDS) do
            if low:find("%f[%a]" .. w) then return true end
        end
        return false
    end

    local function HarmfulAuraName(unit, i)
        if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
            local ok, d = pcall(C_UnitAuras.GetAuraDataByIndex, unit, i, "HARMFUL")
            if not ok or not d then return nil end
            return ns.SafeStr(d.name) or false
        elseif UnitDebuff then
            local ok, n = pcall(UnitDebuff, unit, i)
            if not ok or n == nil then return nil end
            return ns.SafeStr(n) or false
        end
        return nil
    end

    -- [CC] on a party member: new crowd control auras and mind control
    local function OnGroupAura(unit)
        if not ns.LogOn("cc") then return end
        local who = ShortName(unit)
        if not who then return end
        local now = GetTime()
        if (now - (T.auraScanAt[unit] or 0)) < 0.3 then return end
        T.auraScanAt[unit] = now

        local charmed = UnitIsCharmed and UnitIsCharmed(unit) == true
        if charmed and not T.charmed[who] then
            ns.RecordAdventureLine(string.format("[CC] %s is mind controlled!", who))
        elseif not charmed and T.charmed[who] then
            ns.RecordAdventureLine(string.format("[CC] %s breaks free", who))
        end
        T.charmed[who] = charmed or nil

        local now_cc = {}
        for i = 1, 40 do
            local n = HarmfulAuraName(unit, i)
            if n == nil then break end
            if n and IsCC(n) then now_cc[n] = true end
        end
        local had = T.cc[who] or {}
        for n in pairs(now_cc) do
            if not had[n] then
                ns.RecordAdventureLine(string.format("[CC] %s is hit by %s", who, n))
            end
        end
        T.cc[who] = now_cc
    end

    -- [PET] badly hurt, died, back again
    local function OnPet(unit)
        if not ns.LogOn("pets") then return end
        local ownerUnit = T.PETS[unit]
        local owner = ownerUnit and ShortName(ownerUnit)
        if not owner then return end
        local st = T.pets[owner] or {}
        T.pets[owner] = st
        if not UnitExists(unit) then return end
        local petName = ns.SafeStr(UnitName(unit))
        if not petName then return end
        -- 0.5.0: name plus species, so "Crab" is never just a word
        local species = ns.GetPetSpecies and ns.GetPetSpecies(unit)
        local kind = (unit == "pet" and ns.GetPetKind) and ns.GetPetKind("pet") or "pet"
        local label = string.format("%s (%s%s's %s)", petName, species and (species .. ", ") or "", owner, kind)
        local dead = UnitIsDead(unit) == true
        if dead and not st.dead then
            ns.RecordAdventureLine(string.format("[PET DEATH] %s died", label))
        elseif not dead and st.dead and st.name == petName then
            ns.RecordAdventureLine(string.format("[PET] %s is back on its feet", label))
        elseif not dead and GroupInCombat() then
            local pct = ns.GetUnitHealthPct and ns.GetUnitHealthPct(unit)
            local now = GetTime()
            if pct and pct > 0 and pct <= 25 and (now - (st.lowAt or 0)) > 30 then
                st.lowAt = now
                ns.RecordAdventureLine(string.format("[PET] %s is badly hurt (%d%% HP)", label, pct))
            end
        end
        st.dead, st.name = dead, petName
    end

    local function Handle(event, unit, a2, a3)
        if type(unit) ~= "string" then return end
        local run, inInstance = Recording()
        if not run then return end
        if event == "UNIT_SPELLCAST_SUCCEEDED" then
            if T.GROUP[unit] or T.PETS[unit] then
                OnPartySpell(run, unit, a3, inInstance)
            else
                OnBossCast(unit, a3, false)
            end
        elseif event == "UNIT_SPELLCAST_START" or event == "UNIT_SPELLCAST_CHANNEL_START" then
            if not T.GROUP[unit] and not T.PETS[unit] then OnBossCast(unit, a3, true) end
        elseif event == "UNIT_AURA" then
            if T.GROUP[unit] then OnGroupAura(unit) end
        elseif event == "UNIT_HEALTH" then
            if T.PETS[unit] then OnPet(unit) end
        elseif event == "UNIT_PET" then
            local petUnit = (unit == "player") and "pet" or (unit:match("^party(%d)$") and ("partypet" .. unit:match("^party(%d)$")))
            if petUnit then OnPet(petUnit) end
        end
    end

    tracker:SetScript("OnEvent", function(_, event, unit, a2, a3)
        local ok, err = pcall(Handle, event, unit, a2, a3)
        if not ok and not tracker.reported then
            tracker.reported = true
            if ns.Debug then ns.Debug("error", "run tracker: " .. tostring(err)) end
            print("|cffffd100RP Chronicler|r |cffff6b6brun tracker error:|r " .. tostring(err))
        end
    end)

    -- A new run starts with clean tracker state
    function ns.ResetRunTrackers()
        T.spellAt, T.bossCastAt, T.bossStartAt = {}, {}, {}
        T.cc, T.charmed, T.pets = {}, {}, {}
        T.lastSpell = 0
    end
end
