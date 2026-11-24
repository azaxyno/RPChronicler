local ADDON_NAME, ns = ...

local lastKillerByVictim = {}
local recentLoggedDeaths = {}
local lastCapturedQuestTitle = ""

local RARE_PLUS_HEX = {
    ["1eff00"] = true, -- Uncommon
    ["0070dd"] = true, -- Rare
    ["a335ee"] = true, -- Epic
    ["ff8000"] = true, -- Legendary
    ["e6cc80"] = true, -- Heirloom / Artifact
}

local function IsBossUnit(unit)
    if not UnitExists(unit) then return false end
    local cls = ns.SafeStr(UnitClassification(unit))
    local lvl = ns.SafeNum(UnitLevel(unit))
    return (cls == "worldboss") or (lvl ~= nil and lvl < 0)
end

local function CheckInstanceAdventureState(isInitialLogin)
    ns.EnsureDB()
    local inInstance, instanceType = IsInInstance and IsInInstance()
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

local function HandleLootMessage(rawMsg, rawAuthor)
    local safeMsg = ns.SafeStr(rawMsg)
    if not safeMsg or safeMsg == "" then return end

    local cleanPlain = ns.CleanText(safeMsg) or ""
    local keepColored = ns.CleanChatKeepColors(safeMsg) or cleanPlain
    local looter = ns.StripRealm(rawAuthor)
    if not looter or looter == "" then
        looter = cleanPlain:match("^([^%s]+)%s+receives loot:")
            or cleanPlain:match("^([^%s]+)%s+won:")
            or ns.GetUnitFullName("player")
            or ns.StripRealm(UnitName("player"))
            or "Player"
    end

    local line = ns.ColorText("[Loot]", ns.COLORS.lootTag) .. " " .. keepColored
    ns.PushLog(ns.logs.loot, line)

    for hex, itemLink in safeMsg:gmatch("(|c%x%x(%x%x%x%x%x%x)|Hitem:.-|h%[.-%]|h|r)") do
        if RARE_PLUS_HEX[hex:lower()] and ns.RecordAdventureLoot then
            local itemPlain = ns.CleanText(itemLink)
            ns.RecordAdventureLoot(itemLink, itemPlain, looter)
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

for _, ev in ipairs(EVENTS) do
    pcall(eventFrame.RegisterEvent, eventFrame, ev)
end

eventFrame:SetScript("OnEvent", function(_, event, ...)
    if event == "PLAYER_LOGIN" then
        ns.EnsureDB()
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
            if ns.RecordAdventureBossKill then
                ns.RecordAdventureBossKill(bName)
            end
            if ns.RequestScreenshot then
                ns.RequestScreenshot("boss", "Defeated " .. bName)
            end
        end
    elseif event == "UNIT_HEALTH" then
        local unit = ...
        if not unit then return end
        if unit == "target" or unit:match("^boss%d+$") then
            if UnitExists(unit) and UnitCanAttack("player", unit) and not UnitIsDead(unit) then
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
