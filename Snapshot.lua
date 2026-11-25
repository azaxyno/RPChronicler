local ADDON_NAME, ns = ...

local function FormatHealthPercent(unit)
    local hp = ns.SafeNum(UnitHealth(unit))
    local hpMax = ns.SafeNum(UnitHealthMax(unit))
    if hp and hpMax and hpMax > 0 then
        local pct = math.floor((hp / hpMax) * 100)
        local hex = ns.COLORS.friendly
        if pct <= 25 then
            hex = ns.COLORS.hostile
        elseif pct <= 60 then
            hex = ns.COLORS.neutral
        end
        return ns.ColorText(pct .. "% HP", hex)
    end
    return nil
end

function ns.GetTargetLine()
    if not UnitExists("target") then
        return nil
    end

    local tName = ns.GetUnitFullName("target") or ns.StripRealm(UnitName("target")) or "Unknown"
    local isDead = UnitIsDeadOrGhost("target")
    local lvl = ns.SafeNum(UnitLevel("target"))
    local lvlStr = (lvl and lvl > 0) and ("Lvl " .. tostring(lvl)) or "Lvl ??"

    if UnitIsPlayer("target") then
        local race = ns.SafeStr(UnitRace("target")) or ""
        local clsLoc, clsFile = UnitClass("target")
        clsLoc = ns.SafeStr(clsLoc) or ""
        clsFile = ns.SafeStr(clsFile) or ""
        local guild = ns.SafeStr(GetGuildInfo("target"))
        local nameColored = (clsFile ~= "") and ns.ColorizeClass(tName, clsFile) or ns.ColorText(tName, ns.COLORS.speaker)

        local reactionHex = ns.COLORS.friendly
        if UnitCanAttack("player", "target") then
            reactionHex = ns.COLORS.hostile
        elseif not UnitIsFriend("player", "target") then
            reactionHex = ns.COLORS.neutral
        end

        local parts = { nameColored, "(" .. lvlStr }
        if race ~= "" then table.insert(parts, race) end
        if clsLoc ~= "" then table.insert(parts, ns.ColorizeClass(clsLoc, clsFile) .. ")") else parts[#parts] = parts[#parts] .. ")" end
        if guild and guild ~= "" then
            table.insert(parts, ns.ColorText("<" .. guild .. ">", ns.COLORS.guild))
        end

        if isDead then
            table.insert(parts, ns.ColorText("[Dead]", ns.COLORS.death))
        else
            local hpStr = FormatHealthPercent("target")
            if hpStr then table.insert(parts, "[" .. hpStr .. "]") end
            if UnitCanAttack("player", "target") then
                table.insert(parts, ns.ColorText("[Hostile]", reactionHex))
            end
        end

        return ns.ColorText("[Target]", ns.COLORS.header) .. " " .. table.concat(parts, " ")
    end

    local classification = ns.SafeStr(UnitClassification("target")) or "normal"
    local cType = ns.SafeStr(UnitCreatureType("target")) or ""
    local classTag = ""
    local nameHex = ns.COLORS.neutral

    if classification == "worldboss" or (lvl and lvl < 0) then
        classTag = " " .. ns.ColorText("[Boss]", ns.COLORS.boss)
        nameHex = ns.COLORS.boss
    elseif classification == "rareelite" then
        classTag = " " .. ns.ColorText("[Rare Elite]", ns.COLORS.rareelite)
        nameHex = ns.COLORS.rareelite
    elseif classification == "elite" then
        classTag = " " .. ns.ColorText("[Elite]", ns.COLORS.elite)
        nameHex = ns.COLORS.elite
    elseif classification == "rare" then
        classTag = " " .. ns.ColorText("[Rare]", ns.COLORS.rare)
        nameHex = ns.COLORS.rare
    end

    local reactionLabel = "Neutral"
    local reactionHex = ns.COLORS.neutral
    if UnitCanAttack("player", "target") then
        reactionLabel = "Hostile"
        reactionHex = ns.COLORS.hostile
        if nameHex == ns.COLORS.neutral then nameHex = ns.COLORS.hostile end
    elseif UnitIsFriend("player", "target") then
        reactionLabel = "Friendly"
        reactionHex = ns.COLORS.friendly
        if nameHex == ns.COLORS.neutral then nameHex = ns.COLORS.friendly end
    end

    local metaParts = { lvlStr }
    if cType ~= "" then table.insert(metaParts, cType) end
    local statusStr = isDead and ns.ColorText("[Dead]", ns.COLORS.death) or (FormatHealthPercent("target") and ("[" .. FormatHealthPercent("target") .. "]") or "")

    return string.format("%s %s (%s)%s %s %s",
        ns.ColorText("[Target]", ns.COLORS.header),
        ns.ColorText(tName, nameHex),
        table.concat(metaParts, " "),
        classTag,
        ns.ColorText("[" .. reactionLabel .. "]", reactionHex),
        statusStr):gsub("%s+$", "")
end

function ns.GetPartyLine()
    local members = {}
    local function AddMember(unit)
        if not UnitExists(unit) or not UnitIsPlayer(unit) then return end
        local name = ns.GetUnitFullName(unit) or ns.StripRealm(UnitName(unit))
        if not name or name == "" then return end

        local lvl = ns.SafeNum(UnitLevel(unit))
        local clsLoc, clsFile = UnitClass(unit)
        clsLoc = ns.SafeStr(clsLoc) or ""
        clsFile = ns.SafeStr(clsFile) or ""
        -- Assigned role, or a guess from forms, talents, aggro and class
        local role = ns.GetUnitRole and ns.GetUnitRole(unit) or "NONE"
        local roleTag = ns.GetRoleTag(role, false)

        local coloredName = (clsFile ~= "") and ns.ColorizeClass(name, clsFile) or ns.ColorText(name, ns.COLORS.speaker)
        local detail = {}
        if lvl and lvl > 0 then table.insert(detail, "L" .. lvl) end
        if clsLoc ~= "" then table.insert(detail, clsLoc) end
        if roleTag ~= "" then table.insert(detail, roleTag) end
        if UnitIsDeadOrGhost(unit) then table.insert(detail, ns.ColorText("Dead", ns.COLORS.death)) end

        if #detail > 0 then
            table.insert(members, coloredName .. " (" .. table.concat(detail, " ") .. ")")
        else
            table.insert(members, coloredName)
        end
    end

    -- 0.5.0: raid members count too (raid1-40, yourself left out)
    local inRaid = IsInRaid and IsInRaid()
    if inRaid then
        local me = ns.SafeStr(UnitName("player"))
        for i = 1, 40 do
            local u = "raid" .. i
            if UnitExists(u) and ns.SafeStr(UnitName(u)) ~= me then AddMember(u) end
        end
    else
        for i = 1, 4 do
            AddMember("party" .. i)
        end
    end

    if #members == 0 then
        return nil
    end
    return ns.ColorText(inRaid and "[Raid]" or "[Party]", ns.COLORS.header) .. " " .. table.concat(members, ", ")
end

function ns.GetStatusLine()
    local pName = ns.GetUnitFullName("player") or ns.StripRealm(UnitName("player")) or "Self"
    local lvl = ns.SafeNum(UnitLevel("player"))
    local clsLoc, clsFile = UnitClass("player")
    clsLoc = ns.SafeStr(clsLoc) or ""
    clsFile = ns.SafeStr(clsFile) or ""

    local parts = {}
    local whoStr = (clsFile ~= "") and ns.ColorizeClass(pName, clsFile) or ns.ColorText(pName, ns.COLORS.speaker)
    if lvl and lvl > 0 then
        whoStr = whoStr .. " (Lvl " .. lvl .. (clsLoc ~= "" and (" " .. clsLoc) or "") .. ")"
    end
    local myRole = ns.GetUnitRole and ns.GetUnitRole("player") or "NONE"
    local myRoleTag = ns.GetRoleTag(myRole, false)
    if myRoleTag ~= "" then whoStr = whoStr .. " " .. myRoleTag end
    table.insert(parts, whoStr)

    local inCombat = (UnitAffectingCombat and UnitAffectingCombat("player")) and true or false
    table.insert(parts, inCombat and ns.ColorText("[In Combat]", ns.COLORS.combat) or ns.ColorText("[Out of Combat]", ns.COLORS.friendly))

    local hpStr = FormatHealthPercent("player")
    if hpStr then table.insert(parts, hpStr) end

    local pType = UnitPowerType and ns.SafeNum(UnitPowerType("player"))
    if pType == 0 then
        local mp = ns.SafeNum(UnitPower("player", 0))
        local mpMax = ns.SafeNum(UnitPowerMax("player", 0))
        if mp and mpMax and mpMax > 0 then
            local mpPct = math.floor((mp / mpMax) * 100)
            table.insert(parts, ns.ColorText(mpPct .. "% Mana", ns.COLORS.mana))
        end
    end

    if UnitExists("pet") then
        -- 0.5.0: name plus species, e.g. "Snips (Crab, hunter pet)"
        local petInfo = (ns.GetPetDescriptor and ns.GetPetDescriptor("pet")) or ns.SafeStr(UnitName("pet")) or "Pet"
        if UnitIsDead("pet") then
            petInfo = petInfo .. " " .. ns.ColorText("[Dead]", ns.COLORS.death)
        else
            local petHp = FormatHealthPercent("pet")
            if petHp then petInfo = petInfo .. " (" .. petHp .. ")" end
            if GetPetHappiness then
                local ok, hap = pcall(GetPetHappiness)
                hap = ok and ns.SafeNum(hap) or nil
                if hap == 1 then
                    petInfo = petInfo .. " " .. ns.ColorText("[Unhappy]", ns.COLORS.hostile)
                elseif hap == 2 then
                    petInfo = petInfo .. " " .. ns.ColorText("[Content]", ns.COLORS.neutral)
                end
            end
        end
        table.insert(parts, ns.ColorText("Pet:", ns.COLORS.lootType) .. " " .. petInfo)
    end

    -- Deaths and level ups from the last 15 minutes (the old Combat section)
    local life = {}
    local logs = ns.logs.combat or {}
    for i = #logs, 1, -1 do
        local e = logs[i]
        if type(e) == "table" and e.at and (time() - e.at) <= 900 and #life < 2 then
            local mins = math.floor((time() - e.at) / 60)
            table.insert(life, e.line .. ns.ColorText(mins < 1 and " just now" or (" " .. mins .. "m ago"), ns.COLORS.muted))
        end
    end
    if #life > 0 then
        table.insert(parts, ns.ColorText("Recent:", ns.COLORS.lootType) .. " " .. table.concat(life, ", "))
    end

    return ns.ColorText("[Status]", ns.COLORS.header) .. " " .. table.concat(parts, " | ")
end

local SAY_LIKE = { Say = true, Yell = true, Emote = true }

-- Short names of you and your party members
local function GroupNames()
    local names = {}
    local me = ns.StripRealm(UnitName("player"))
    if me then names[me] = true end
    local prefix, count = "party", 4
    if IsInRaid and IsInRaid() then prefix, count = "raid", 40 end
    for i = 1, count do
        local u = prefix .. i
        if UnitExists(u) then
            local n = ns.StripRealm(UnitName(u))
            if n then names[n] = true end
        end
    end
    return names
end

-- The last `limit` entries of a buffer that pass `keep` (nil keeps all)
local function TakeRecent(out, buf, limit, keep)
    if type(buf) ~= "table" then return end
    local taken = 0
    for i = #buf, 1, -1 do
        if taken >= limit then break end
        local e = buf[i]
        if not keep or (type(e) == "table" and keep(e)) then
            table.insert(out, e)
            taken = taken + 1
        end
    end
end

-- All chat sources the tab includes, merged into one time-ordered list
local function BuildTimeline(tabCfg, limit)
    local picked = {}
    if tabCfg.incSocial then
        TakeRecent(picked, ns.logs.social, limit)
    elseif tabCfg.incPartySay then
        local group = GroupNames()
        TakeRecent(picked, ns.logs.social, limit, function(e)
            return e.author and group[e.author] and SAY_LIKE[e.chan] or false
        end)
    end
    if tabCfg.incPartyChat then TakeRecent(picked, ns.logs.party, limit) end
    if tabCfg.incNpc then TakeRecent(picked, ns.logs.npc, limit) end
    if tabCfg.incLoot then TakeRecent(picked, ns.logs.loot, limit) end
    if tabCfg.incOoc then TakeRecent(picked, ns.logs.ooc, limit) end
    if tabCfg.incWorld then TakeRecent(picked, ns.logs.world, limit) end
    if tabCfg.incGuild then TakeRecent(picked, ns.logs.guild, limit) end

    local seen, list = {}, {}
    for _, e in ipairs(picked) do
        if not seen[e] then
            seen[e] = true
            table.insert(list, e)
        end
    end
    table.sort(list, function(x, y)
        local sx = type(x) == "table" and x.seq or 0
        local sy = type(y) == "table" and y.seq or 0
        return sx < sy
    end)
    return list, seen
end

function ns.BuildSnapshot(filterId, note, isExpanded)
    ns.EnsureDB()
    local tabCfg = ns.GetTabConfig(filterId)
    local limit = isExpanded and (RPCopyDB.expandMessages or 6) or (RPCopyDB.defaultMessages or 3)

    local lines = {}
    -- 0.5.0: the people in this scene, most relevant first, for the
    -- [Known Player] blocks (no more matching every "Bob" in the text)
    local people, seenPeople = {}, {}
    local function AddPerson(name)
        name = ns.SafeStr(name)
        if name and name ~= "" and not seenPeople[name] then
            seenPeople[name] = true
            table.insert(people, name)
        end
    end
    if tabCfg and tabCfg.prefix and tabCfg.prefix ~= "" then
        -- Line 1 invokes the character skill in the AI, e.g. "[Skill Call] use aloria"
        table.insert(lines, ns.ColorText("[Skill Call]", ns.COLORS.header) .. " " .. tabCfg.prefix)
    end

    -- "/rp <text>" is a direction for the LLM (tone, focus, what to reply to),
    -- not something said in chat, so it goes right under the trigger line.
    local cleanNote = (note or ""):match("^%s*(.-)%s*$")
    if cleanNote ~= "" then
        table.insert(lines, ns.ColorText("[Instruction]", ns.COLORS.note) .. " " .. ns.ColorText(cleanNote, ns.COLORS.softWhite))
    end

    local where = ns.GetCurrentWhere()
    table.insert(lines, ns.ColorText("[Location]", ns.COLORS.header) .. " " .. ns.ColorText(where, ns.COLORS.location))

    if tabCfg then
        local timeline, inTimeline = BuildTimeline(tabCfg, limit)
        local direct = ns.state.lastDirectEntry
        -- The direct message is marked inside the timeline when it is there,
        -- so it is never copied twice.
        local directInline = tabCfg.incDirect and direct and inTimeline[direct]
        if tabCfg.incDirect and not directInline and ns.state.lastDirectMsg and ns.state.lastDirectMsg ~= "" then
            table.insert(lines, ns.ColorText("[Direct]", ns.COLORS.direct) .. " " .. ns.state.lastDirectMsg)
        end
        if tabCfg.incDirect and ns.state.lastDirectAuthor then AddPerson(ns.state.lastDirectAuthor) end

        if tabCfg.incTarget then
            local tLine = ns.GetTargetLine()
            if tLine then table.insert(lines, tLine) end
            if UnitExists("target") then AddPerson(ns.UnitCompanionName and ns.UnitCompanionName("target")) end
        end

        if tabCfg.incParty then
            local pLine = ns.GetPartyLine()
            if pLine then table.insert(lines, pLine) end
            local prefix, count = "party", 4
            if IsInRaid and IsInRaid() then prefix, count = "raid", 40 end
            for i = 1, count do
                local u = prefix .. i
                if UnitExists(u) then AddPerson(ns.UnitCompanionName and ns.UnitCompanionName(u)) end
            end
        end

        if tabCfg.incStatus then
            local sLine = ns.GetStatusLine()
            if sLine then table.insert(lines, sLine) end
        end

        if tabCfg.incQuest and ns.state.lastQuestInfo and ns.state.lastQuestInfo ~= "" then
            table.insert(lines, ns.ColorText("[Quest]", ns.COLORS.quest) .. " " .. ns.state.lastQuestInfo)
        end

        for i = #timeline, 1, -1 do
            local e = timeline[i]
            if type(e) == "table" then
                AddPerson(e.author)
                if e.to then AddPerson(e.to) end
            end
        end

        for _, e in ipairs(timeline) do
            local text = ns.LogLine(e)
            if directInline and e == direct then
                text = ns.ColorText("[Direct]", ns.COLORS.direct) .. " " .. text
            end
            table.insert(lines, text)
        end
    end

    local bodyText = table.concat(lines, "\n")
    local kpBlocks = ns.GetKnownPlayerBlocks(people, bodyText)
    if #kpBlocks > 0 then
        bodyText = bodyText .. "\n" .. table.concat(kpBlocks, "\n")
    end

    return bodyText
end
