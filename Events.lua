local ADDON_NAME, ns = ...

local lastKillerByVictim = {}
local recentLoggedDeaths = {}
local lastCapturedQuestTitle = ""

local function IsBossUnit(unit)
    if not UnitExists(unit) then return false end
    local cls = ns.SafeStr(UnitClassification(unit))
    local lvl = ns.SafeNum(UnitLevel(unit))
    return (cls == "worldboss") or (lvl ~= nil and lvl < 0)
end

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
            if ns.StartAdventure then
                ns.StartAdventure(zoneName, true)
            end
        else
            if not isInitialLogin then
                active.reloads = (active.reloads or 0) + 1
            end
            if ns.SyncAdventureRoster then
                ns.SyncAdventureRoster()
            end
        end
    else
        if active and active.isAuto and ns.EndAdventure then
            ns.EndAdventure("Left Instance")
        end
    end
end

local function HandlePlayerChat(channelLabel, colorHex, rawMsg, rawAuthor, rawChannelName)
    local cleanMsg = ns.CleanText(rawMsg)
    if not cleanMsg or cleanMsg == "" then return end

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

    if channelLabel == "Party" or channelLabel == "Raid" or channelLabel == "Instance" then
        ns.PushLog(ns.logs.party, line)
    else
        ns.PushLog(ns.logs.social, line)
    end

    local selfFirst = ns.StripRealm(UnitName("player")) or ""
    if author ~= "Unknown" and author ~= selfFirst then
        if channelLabel == "Whisper" or channelLabel == "Say" then
            ns.state.lastDirectAuthor = ns.ResolveCanonicalPlayerName(author)
            ns.state.lastDirectMsg = line
        end
    end

    if ns.HandleConversationCapture then
        ns.HandleConversationCapture(channelLabel, author, cleanMsg, false, nil)
    end
    if ns.RecordAdventureChat then
        ns.RecordAdventureChat(chanPrefix, author, cleanMsg)
    end
end

local function HandleNpcChat(kindLabel, rawMsg, rawAuthor)
    local cleanMsg = ns.CleanText(rawMsg)
    if not cleanMsg or cleanMsg == "" then return end
    local npcName = ns.StripRealm(rawAuthor) or "NPC"

    local line = string.format("%s %s: %s",
        ns.ColorText("[" .. kindLabel .. "]", ns.COLORS.npc),
        ns.ColorText(npcName, ns.COLORS.npcName),
        ns.ColorText(cleanMsg, ns.COLORS.npcText))

    ns.PushLog(ns.logs.npc, line)
    if ns.RecordAdventureChat then
        ns.RecordAdventureChat(kindLabel, npcName, cleanMsg)
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
            table.insert(items, { colored = colored, plain = "[" .. name .. "]", quality = q })
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

local function HandleLootMessage(rawMsg, rawAuthor)
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

    local line = ns.ColorText("[Loot]", ns.COLORS.lootTag) .. " " .. coloredLine
    ns.PushLog(ns.logs.loot, line)

    -- Uncommon (green) and better go into the adventure's key loot list
    for _, item in ipairs(items or {}) do
        if item.quality and item.quality >= 2 and ns.RecordAdventureLoot then
            ns.RecordAdventureLoot(item.colored, item.plain, looter)
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
    ns.state.lastQuestInfo = string.format("%s: %s", prefixLabel, title)
    ns.PushLog(ns.logs.npc, ns.ColorText("[Quest]", ns.COLORS.quest) .. " " .. ns.ColorText(ns.state.lastQuestInfo, ns.COLORS.npcText))
end

local function ProcessCombatLog()
    if not CombatLogGetCurrentEventInfo then return end
    local _, subEvent, _, _, sourceName, _, _, _, destName, destFlags = CombatLogGetCurrentEventInfo()

    subEvent = ns.SafeStr(subEvent)
    if not subEvent then return end
    local srcClean = ns.StripRealm(sourceName)
    local dstClean = ns.StripRealm(destName)

    if dstClean and (subEvent == "SWING_DAMAGE" or subEvent == "SPELL_DAMAGE" or subEvent == "SPELL_PERIODIC_DAMAGE" or subEvent == "RANGE_DAMAGE" or subEvent == "ENVIRONMENTAL_DAMAGE") then
        local spellName = nil
        if subEvent == "SWING_DAMAGE" then
            spellName = "Melee"
        elseif subEvent == "ENVIRONMENTAL_DAMAGE" then
            spellName = ns.SafeStr(select(12, CombatLogGetCurrentEventInfo())) or "Environment"
        else
            spellName = ns.SafeStr(select(13, CombatLogGetCurrentEventInfo()))
        end
        if srcClean and spellName then
            lastKillerByVictim[dstClean] = srcClean .. "'s " .. spellName
        elseif srcClean then
            lastKillerByVictim[dstClean] = srcClean
        elseif spellName then
            lastKillerByVictim[dstClean] = spellName
        end
    elseif subEvent == "SPELL_RESURRECT" and dstClean then
        if ns.RecordAdventureRez then
            ns.RecordAdventureRez(srcClean, dstClean)
        end
    elseif subEvent == "UNIT_DIED" and dstClean then
        local isPlayerVictim = false
        if type(destFlags) == "number" and COMBATLOG_OBJECT_TYPE_PLAYER and COMBATLOG_OBJECT_AFFILIATION_MINE and COMBATLOG_OBJECT_AFFILIATION_PARTY and COMBATLOG_OBJECT_AFFILIATION_RAID then
            local isPlayerObj = bit.band(destFlags, COMBATLOG_OBJECT_TYPE_PLAYER) > 0
            local groupMask = bit.bor(COMBATLOG_OBJECT_AFFILIATION_MINE, COMBATLOG_OBJECT_AFFILIATION_PARTY, COMBATLOG_OBJECT_AFFILIATION_RAID)
            local isGroupObj = bit.band(destFlags, groupMask) > 0
            isPlayerVictim = isPlayerObj and isGroupObj
        end

        if isPlayerVictim then
            local now = GetTime()
            if not recentLoggedDeaths[dstClean] or (now - recentLoggedDeaths[dstClean]) > 3 then
                recentLoggedDeaths[dstClean] = now
                local selfName = ns.StripRealm(UnitName("player"))
                if ns.RecordAdventureDeath then
                    ns.RecordAdventureDeath(dstClean, dstClean == selfName, lastKillerByVictim[dstClean])
                end
                ns.PushLog(ns.logs.combat, ns.ColorText("[Death]", ns.COLORS.death) .. " " .. dstClean .. " died")
            end
        else
            local activeBoss = ns.GetActiveBossName and ns.GetActiveBossName()
            local isCurrentTargetBoss = UnitExists("target") and (ns.StripRealm(UnitName("target")) == dstClean) and IsBossUnit("target")
            if (activeBoss and activeBoss:lower() == dstClean:lower()) or isCurrentTargetBoss then
                if ns.RecordAdventureBossKill then
                    ns.RecordAdventureBossKill(dstClean)
                end
                if ns.RequestScreenshot then
                    ns.RequestScreenshot("boss", "Defeated " .. dstClean)
                end
            end
        end
    end
end

local eventFrame = CreateFrame("Frame", "RPCopyEventFrame")
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
    "COMBAT_LOG_EVENT_UNFILTERED",
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
-- the Blizzard UI") on every load, and pcall cannot suppress that popup.
-- Boss kills still come from ENCOUNTER_END and your own deaths from PLAYER_DEAD.
local PROTECTED_EVENTS = {}
if issecretvalue then
    PROTECTED_EVENTS["COMBAT_LOG_EVENT_UNFILTERED"] = true
end
ns.combatLogAvailable = not PROTECTED_EVENTS["COMBAT_LOG_EVENT_UNFILTERED"]

for _, ev in ipairs(EVENTS) do
    if not PROTECTED_EVENTS[ev] then
        pcall(eventFrame.RegisterEvent, eventFrame, ev)
    end
end

eventFrame:SetScript("OnEvent", function(_, event, ...)
    if event == "PLAYER_LOGIN" then
        ns.EnsureDB()
        -- Version banner, read from the toc's ## Version field (see Core.lua)
        print(string.format("|cffffd100RPCopy|r |cff69ccf0v%s|r |cff9aa5b4loaded - /rp to open|r", tostring(ns.VERSION or "?")))
        CheckInstanceAdventureState(true)
    elseif event == "PLAYER_ENTERING_WORLD" then
        local isInitialLogin = ...
        CheckInstanceAdventureState(isInitialLogin)
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
        if UnitExists(unit) and UnitIsPlayer(unit) and RPCopyDB and RPCopyDB.autoUpdateKnown then
            local fullName = ns.GetUnitFullName(unit)
            local key = fullName and ns.FindPlayerKey(fullName, true)
            if key and RPCopyDB.players[key] then
                ns.CaptureVisibleUnitFields(unit, RPCopyDB.players[key])
            end
        elseif event == "PLAYER_TARGET_CHANGED" and UnitExists("target") and UnitCanAttack("player", "target") and not UnitIsDead("target") then
            if IsBossUnit("target") and UnitAffectingCombat and UnitAffectingCombat("player") then
                local bName = ns.SafeStr(UnitName("target"))
                if bName and ns.RecordAdventureBossEngage then
                    ns.RecordAdventureBossEngage(bName)
                end
            end
        end
    elseif event == "PLAYER_REGEN_DISABLED" then
        ns.PushLog(ns.logs.combat, ns.ColorText("[Combat]", ns.COLORS.combat) .. " Entered combat")
        if ns.RecordAdventureCombatState then
            ns.RecordAdventureCombatState(true)
        end
        if UnitExists("target") and IsBossUnit("target") and UnitCanAttack("player", "target") then
            local bName = ns.SafeStr(UnitName("target"))
            if bName and ns.RecordAdventureBossEngage then
                ns.RecordAdventureBossEngage(bName)
            end
        end
    elseif event == "PLAYER_REGEN_ENABLED" then
        ns.PushLog(ns.logs.combat, ns.ColorText("[Combat]", ns.COLORS.friendly) .. " Left combat")
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
                if unit:match("^boss%d+$") or IsBossUnit(unit) then
                    local bName = ns.SafeStr(UnitName(unit))
                    local hp = ns.SafeNum(UnitHealth(unit))
                    local hpMax = ns.SafeNum(UnitHealthMax(unit))
                    if bName and hp and hpMax and hpMax > 0 then
                        if ns.RecordAdventureBossEngage and UnitAffectingCombat and UnitAffectingCombat("player") then
                            ns.RecordAdventureBossEngage(bName)
                        end
                        if ns.RecordAdventureBossHP then
                            ns.RecordAdventureBossHP(bName, math.floor((hp / hpMax) * 100))
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
    elseif event == "COMBAT_LOG_EVENT_UNFILTERED" then
        pcall(ProcessCombatLog)
    elseif event == "PLAYER_DEAD" then
        local selfName = ns.StripRealm(UnitName("player")) or "Player"
        local now = GetTime()
        if not recentLoggedDeaths[selfName] or (now - recentLoggedDeaths[selfName]) > 3 then
            recentLoggedDeaths[selfName] = now
            if ns.RecordAdventureDeath then
                ns.RecordAdventureDeath(selfName, true, lastKillerByVictim[selfName])
            end
            ns.PushLog(ns.logs.combat, ns.ColorText("[Death]", ns.COLORS.death) .. " You died")
        end
    elseif event == "PLAYER_LEVEL_UP" then
        local newLevel = ns.SafeNum((...))
        if newLevel then
            ns.PushLog(ns.logs.combat, ns.ColorText("[Level Up]", ns.COLORS.gold) .. " Reached level " .. newLevel)
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
        if cleanMsg and cleanMsg ~= "" then
            local selfName = ns.StripRealm(UnitName("player")) or "Me"
            local recipClean = ns.StripRealm(recipient) or "Unknown"
            local line = string.format("%s To [%s]: %s",
                ns.ColorText("[Whisper]", ns.COLORS.whisper),
                ns.ColorText(recipClean, ns.COLORS.speaker),
                ns.ColorText(cleanMsg, ns.COLORS.text))
            ns.PushLog(ns.logs.social, line)
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
    elseif event == "CHAT_MSG_CHANNEL" then
        local msg, author, _, channelName = ...
        HandlePlayerChat("Channel", ns.COLORS.channel, msg, author, channelName)
    elseif event == "CHAT_MSG_MONSTER_SAY" or event == "CHAT_MSG_MONSTER_YELL" or event == "CHAT_MSG_MONSTER_EMOTE" or event == "CHAT_MSG_MONSTER_WHISPER" or event == "CHAT_MSG_RAID_BOSS_EMOTE" or event == "CHAT_MSG_RAID_BOSS_WHISPER" then
        local msg, author = ...
        HandleNpcChat("NPC", msg, author)
    elseif event == "CHAT_MSG_LOOT" or event == "CHAT_MSG_MONEY" then
        local msg, author = ...
        HandleLootMessage(msg, author)
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
