local ADDON_NAME, ns = ...

local GetAddOnMetadata = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata

ns.VERSION = (GetAddOnMetadata and GetAddOnMetadata(ADDON_NAME, "Version")) or "3.9.0"

BINDING_HEADER_RPCOPY = "RPCopy (RP Context & Chronicle)"
BINDING_NAME_RPCOPY_OPEN = "Toggle RPCopy Window"
BINDING_NAME_RPCOPY_QUICK = "Quick Copy (Last Used Slice)"
BINDING_NAME_RPCOPY_CAPTURE = "Capture / Update Target Companion"
BINDING_NAME_RPCOPY_MARK = "Bookmark Adventure Moment"

ns.MAX_LINES = 25
ns.MAX_PLAYER_CHAT = 5

ns.DEFAULT_TRIGGER = "use aloria"

ns.DEFAULT_TABS = {
    {
        id = "SMART",
        label = "Smart",
        prefix = ns.DEFAULT_TRIGGER,
        incDirect = true,
        incTarget = true,
        incParty = true,
        incStatus = true,
        incQuest = false,
        incCombat = true,
        incSocial = false,
        incOoc = false,
        incPartyChat = false,
        incNpc = false,
        incLoot = false,
    },
    {
        id = "CHAT",
        label = "Chat",
        prefix = ns.DEFAULT_TRIGGER,
        incDirect = true,
        incTarget = true,
        incParty = false,
        incStatus = false,
        incQuest = false,
        incCombat = false,
        incSocial = true,
        incOoc = false,
        incPartyChat = false,
        incNpc = false,
        incLoot = false,
    },
    {
        id = "PARTY",
        label = "Party",
        prefix = ns.DEFAULT_TRIGGER,
        incDirect = false,
        incTarget = true,
        incParty = true,
        incStatus = true,
        incQuest = false,
        incCombat = true,
        incSocial = false,
        incOoc = false,
        incPartyChat = true,
        incNpc = false,
        incLoot = false,
    },
    {
        id = "QUEST",
        label = "Quest",
        prefix = ns.DEFAULT_TRIGGER,
        incDirect = false,
        incTarget = true,
        incParty = false,
        incStatus = true,
        incQuest = true,
        incCombat = false,
        incSocial = false,
        incOoc = false,
        incPartyChat = false,
        incNpc = true,
        incLoot = false,
    },
    {
        id = "LOOT",
        label = "Loot",
        prefix = ns.DEFAULT_TRIGGER,
        incDirect = false,
        incTarget = false,
        incParty = true,
        incStatus = true,
        incQuest = false,
        incCombat = false,
        incSocial = false,
        incOoc = false,
        incPartyChat = false,
        incNpc = false,
        incLoot = true,
    },
}

local function CloneDefaultTabs()
    local copy = {}
    for _, t in ipairs(ns.DEFAULT_TABS) do
        local item = {}
        for k, v in pairs(t) do item[k] = v end
        table.insert(copy, item)
    end
    return copy
end

RPCopyDB = RPCopyDB or {
    players = {},
    adventures = {},
    autoUpdateKnown = true,
    autoScreenshots = false,
    quickCtrlC = true,
    quickCopyKey = "CTRL-C",
    quickCapture = true,
    captureTargetKey = "SHIFT-C",
    lastSliceId = "CHAT",
    defaultMessages = 3,
    expandMessages = 6,
    migratedV32 = true,
    tabs = CloneDefaultTabs(),
}

ns.logs = {
    social = {},
    ooc = {},
    party = {},
    loot = {},
    combat = {},
    npc = {},
    playerRecentChat = {},
}

ns.state = {
    lastDirectMsg = nil,
    lastDirectAuthor = nil,
    lastQuestInfo = nil,
    activeFilter = "SMART",
    activeNote = "",
    isExpanded = false,
    selectedPlayerKey = nil,
    selectedAdventureId = nil,
    adventureViewMode = "SUMMARY",
    selectedOptionTabId = "SMART",
}

ns.resumedAt = nil

ns.COLORS = {
    gold         = "ffd100",
    header       = "69ccf0",
    location     = "40e0d0",
    instance     = "b39ddb",
    direct       = "ffb74d",
    hostile      = "ff4d4d",
    neutral      = "ffd54f",
    friendly     = "66bb6a",
    boss         = "ff8000",
    rareelite    = "e066ff",
    elite        = "ffa726",
    rare         = "4fc3f7",
    say          = "ffffff",
    yell         = "ff4040",
    whisper      = "ff80ff",
    party        = "aaaaff",
    instanceChat = "ff7f00",
    raid         = "ff7f00",
    guild        = "40ff40",
    channel      = "ffc0c0",
    emote        = "ff7e40",
    npc          = "ffd27f",
    npcName      = "ffb74d",
    npcText      = "fff59d",
    speaker      = "80d8ff",
    text         = "eceff1",
    lootTag      = "ffd700",
    lootType     = "80cbc4",
    currency     = "ffe082",
    coinGold     = "ffd700",
    coinSilver   = "c7c7cf",
    coinCopper   = "eda55f",
    combat       = "ff5252",
    death        = "ff8a80",
    kill         = "ffa726",
    quest        = "ffdf00",
    mana         = "42a5f5",
    note         = "ff80ab",
    muted        = "9e9e9e",
    softWhite    = "e0e0e0",
}

ns.CLASS_COLORS = {
    WARRIOR     = "C79C6E",
    PALADIN     = "F58CBA",
    HUNTER      = "ABD473",
    ROGUE       = "FFF569",
    PRIEST      = "FFFFFF",
    DEATHKNIGHT = "C41F3B",
    SHAMAN      = "0070DE",
    MAGE        = "69CCF0",
    WARLOCK     = "9482C9",
    MONK        = "00FF96",
    DRUID       = "FF7D0A",
    DEMONHUNTER = "A330C9",
    EVOKER      = "33937F",
}

local KNOWN_CLASSES = {
    "Death Knight", "Demon Hunter", "Warrior", "Paladin", "Hunter",
    "Rogue", "Priest", "Shaman", "Mage", "Warlock", "Monk", "Druid", "Evoker"
}

function ns.IsSecret(val)
    if val == nil then return false end
    if issecretvalue and issecretvalue(val) then return true end
    if canaccessvalue and not canaccessvalue(val) then return true end
    return false
end

function ns.SafeStr(val)
    if val == nil or ns.IsSecret(val) then return nil end
    return tostring(val)
end

function ns.SafeNum(val)
    if val == nil or ns.IsSecret(val) then return nil end
    if type(val) == "number" then return val end
    return nil
end

function ns.ColorText(text, hex)
    if not text or text == "" then return "" end
    if not hex or hex == "" then return text end
    return "|cff" .. hex .. text .. "|r"
end

-- NOTE: Always return a single string (never let gsub's 2nd count return value leak)
function ns.StripColors(text)
    if not text or text == "" then return "" end
    local stripped = tostring(text):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    return stripped
end

function ns.StripRealm(name)
    local s = ns.SafeStr(name)
    if not s or s == "" then return nil end
    return s:match("^([^%-]+)") or s
end

function ns.SplitFullName(fullName)
    local clean = (fullName or ""):match("^%s*(.-)%s*$")
    local first, last = clean:match("^(%S+)%s+(.+)$")
    if first then
        return first, last
    end
    return clean, ""
end

function ns.JoinFullName(first, last)
    local f = (first or ""):match("^%s*(.-)%s*$")
    local l = (last or ""):match("^%s*(.-)%s*$")
    if f ~= "" and l ~= "" then
        return f .. " " .. l
    end
    return f ~= "" and f or l
end

function ns.GetUnitFullName(unit)
    if not UnitExists(unit) then return nil end
    if UnitFullName then
        local ok, raw = pcall(UnitFullName, unit)
        local n = ok and ns.StripRealm(raw) or nil
        if n and n:find("%s") then return n end
    end
    if UnitPVPName then
        local ok, raw = pcall(UnitPVPName, unit)
        local pvp = ok and ns.StripRealm(raw) or nil
        if pvp and pvp:find("%s") then return pvp end
    end
    local base = ns.StripRealm(UnitName(unit))
    if base and GameTooltip and GameTooltip:IsShown() and GameTooltipTextLeft1 then
        local tip1 = ns.SafeStr(GameTooltipTextLeft1:GetText())
        if tip1 then
            local escapedBase = base:gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1")
            local fullFromTip = tip1:match("(" .. escapedBase .. "%s+%S+)")
            if fullFromTip then return fullFromTip end
        end
    end
    return base
end

function ns.GetCurrentWhere()
    local zone = ns.SafeStr(GetRealZoneText()) or ns.SafeStr(GetZoneText()) or "Unknown"
    local sub = ns.SafeStr(GetSubZoneText())
    return (sub and sub ~= "" and sub ~= zone) and (zone .. " - " .. sub) or zone
end

function ns.CleanText(msg)
    local s = ns.SafeStr(msg)
    if not s or s == "" then return nil end
    local cleaned = s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|H.-|h(.-)|h", "%1")
    return cleaned
end

function ns.CleanChatKeepColors(msg)
    local s = ns.SafeStr(msg)
    if not s or s == "" then return nil end
    local cleaned = s:gsub("|H.-|h(.-)|h", "%1")
    return cleaned
end

-- =========================================================
-- Story / Pasted Text Normalizer (WoW font + EditBox safe)
-- Byte escapes keep this source file pure ASCII.
-- =========================================================
local GLYPH_MAP = {
    { "\226\152\133", "*" },   -- black star
    { "\226\152\134", "*" },   -- white star
    { "\226\128\148", "-" },   -- em dash
    { "\226\128\147", "-" },   -- en dash
    { "\226\128\152", "'" },   -- left single quote
    { "\226\128\153", "'" },   -- right single quote / apostrophe
    { "\226\128\156", "\"" },  -- left double quote
    { "\226\128\157", "\"" },  -- right double quote
    { "\226\128\166", "..." }, -- ellipsis
    { "\226\128\162", "-" },   -- bullet
    { "\226\134\146", "->" },  -- right arrow
    { "\194\160", " " },       -- non-breaking space
}

function ns.NormalizeGlyphs(text)
    local s = tostring(text or "")
    for _, pair in ipairs(GLYPH_MAP) do
        s = s:gsub(pair[1], pair[2])
    end
    return s
end

-- Cleans LLM output for display: || -> |, code fences, Markdown, glyphs,
-- and auto-closes dangling |cffRRGGBB escapes. Always returns one string.
function ns.NormalizeStoryText(raw)
    local s = (tostring(raw or "")):match("^%s*(.-)%s*$")

    -- WoW EditBox doubles pasted '|' into '||'
    s = s:gsub("||", "|")

    -- Surrounding Markdown code fences
    s = s:gsub("^```[%w_-]*%s*\n?", "")
    s = s:gsub("\n?```%s*$", "")

    -- Inline Markdown: **bold**, __bold__, `code`
    s = s:gsub("%*%*(.-)%*%*", "%1")
    s = s:gsub("__(.-)__", "%1")
    s = s:gsub("`([^`\n]*)`", "%1")
    s = s:gsub("%*%*", "")

    -- Line-start Markdown: # headers and > quotes
    s = s:gsub("^#+%s*", ""):gsub("\n#+%s*", "\n")
    s = s:gsub("^>%s?", ""):gsub("\n>%s?", "\n")

    s = ns.NormalizeGlyphs(s)
    s = s:match("^%s*(.-)%s*$")

    local openCount, closeCount = 0, 0
    for _ in s:gmatch("|c%x%x%x%x%x%x%x%x") do openCount = openCount + 1 end
    for _ in s:gmatch("|r") do closeCount = closeCount + 1 end
    if openCount > closeCount then
        s = s .. string.rep("|r", openCount - closeCount)
    end
    return s
end

function ns.FormatToPattern(fmt)
    if type(fmt) ~= "string" then return nil end
    local p = fmt:gsub("%%%d?%$?s", "\001"):gsub("%%%d?%$?d", "\002")
    p = p:gsub("[%(%)%.%%%+%-%*%?%[%]%^%$]", "%%%0")
    p = p:gsub("\001", "(.+)"):gsub("\002", "(%%d+)")
    return "^" .. p .. "$"
end

function ns.NowStamp()
    return (date and date("%Y-%m-%d %H:%M")) or "Unknown"
end

function ns.TimeOnlyStamp()
    return (date and date("%H:%M")) or "--:--"
end

function ns.FormatDuration(seconds)
    seconds = math.max(0, math.floor(seconds or 0))
    local mins = math.floor(seconds / 60)
    local secs = seconds % 60
    if mins >= 60 then
        return string.format("%dh %dm", math.floor(mins / 60), mins % 60)
    end
    return string.format("%dm %02ds", mins, secs)
end

function ns.ColorizeClass(text, classFile)
    if not text or text == "" then return "" end
    local key = (classFile or ""):upper():gsub("%s+", "")
    local hex = ns.CLASS_COLORS[key]
    if hex then
        return "|cff" .. hex .. text .. "|r"
    end
    return text
end

function ns.GetPlayerClassFile(name)
    if not name or name == "" then return nil end
    local targetFirst = ns.SplitFullName(name):lower()
    local units = { "player", "target", "mouseover", "party1", "party2", "party3", "party4" }
    for _, u in ipairs(units) do
        if UnitExists(u) and UnitIsPlayer(u) then
            local uFull = ns.GetUnitFullName(u)
            local uFirst = ns.StripRealm(UnitName(u))
            if (uFull and uFull:lower() == name:lower()) or (uFirst and uFirst:lower() == targetFirst) then
                local _, classFile = UnitClass(u)
                return ns.SafeStr(classFile)
            end
        end
    end
    if RPCopyDB and RPCopyDB.players then
        local key = ns.FindPlayerKey(name, false)
        if key and RPCopyDB.players[key] and RPCopyDB.players[key].class and RPCopyDB.players[key].class ~= "" then
            return RPCopyDB.players[key].class
        end
    end
    return nil
end

function ns.FormatSpeakerTag(name)
    local who = name or "Unknown"
    local classFile = ns.GetPlayerClassFile(who)
    if classFile then
        return "[" .. ns.ColorizeClass(who, classFile) .. "]"
    end
    return "[" .. ns.ColorText(who, ns.COLORS.speaker) .. "]"
end

function ns.GetRoleTag(role, useIcon)
    if role == "TANK" then
        return useIcon and "|TInterface\\LFGFrame\\UI-LFG-ICON-PORTRAITROLES:14:14:0:0:64:64:0:19:22:41|t |cff5bc0de[Tank]|r" or "[Tank]"
    elseif role == "HEALER" then
        return useIcon and "|TInterface\\LFGFrame\\UI-LFG-ICON-PORTRAITROLES:14:14:0:0:64:64:20:39:1:20|t |cff5cb85c[Healer]|r" or "[Healer]"
    elseif role == "DAMAGER" then
        return useIcon and "|TInterface\\LFGFrame\\UI-LFG-ICON-PORTRAITROLES:14:14:0:0:64:64:20:39:22:41|t |cffff6b6b[DPS]|r" or "[DPS]"
    end
    return ""
end

function ns.PushBounded(tbl, item, maxLen)
    table.insert(tbl, item)
    while #tbl > maxLen do
        table.remove(tbl, 1)
    end
end

local function IsOocLine(line)
    local plain = ns.StripColors(line or "")
    return plain:match("^%[%d*%.?%s*OOC") ~= nil
end

function ns.PushLog(tbl, line)
    if not line or line == "" then return end
    if tbl == ns.logs.social and IsOocLine(line) then
        ns.logs.ooc = ns.logs.ooc or {}
        ns.PushBounded(ns.logs.ooc, line, ns.MAX_LINES)
        return
    end
    ns.PushBounded(tbl, line, ns.MAX_LINES)
end

function ns.ClearSessionLogs()
    ns.logs.social = {}
    ns.logs.ooc = {}
    ns.logs.party = {}
    ns.logs.loot = {}
    ns.logs.combat = {}
    ns.logs.npc = {}
    ns.state.lastDirectMsg = nil
    ns.state.lastDirectAuthor = nil
    ns.state.lastQuestInfo = nil
    ns.state.activeNote = ""
end

local function ParseLegacyInfo(infoStr)
    local lvl, race, class, guild = "", "", "", ""
    if not infoStr or infoStr == "" then return lvl, race, class, guild end
    lvl = infoStr:match("Lvl%s+(%d+)") or ""
    guild = infoStr:match("Guild:%s*<([^>]+)>") or ""
    for part in infoStr:gmatch("[^|]+") do
        local p = part:match("^%s*(.-)%s*$")
        if not p:match("^Lvl%s+") and not p:match("^Guild:") then
            local matchedClass = nil
            for _, cls in ipairs(KNOWN_CLASSES) do
                if p:sub(-#cls):lower() == cls:lower() then
                    matchedClass = p:sub(-#cls)
                    race = p:sub(1, #p - #cls):match("^%s*(.-)%s*$") or ""
                    class = matchedClass
                    break
                end
            end
            if not matchedClass then race = p end
        end
    end
    return lvl, race, class, guild
end

function ns.ResetDefaultTabs()
    RPCopyDB.tabs = CloneDefaultTabs()
    RPCopyDB.migratedV32 = true
    ns.state.selectedOptionTabId = RPCopyDB.tabs[1].id
    ns.state.activeFilter = RPCopyDB.tabs[1].id
    RPCopyDB.lastSliceId = RPCopyDB.tabs[1].id
end

function ns.GetTabConfig(tabId)
    ns.EnsureDB()
    for _, t in ipairs(RPCopyDB.tabs) do
        if t.id == tabId then return t end
    end
    return RPCopyDB.tabs[1]
end

function ns.EnsureDB()
    RPCopyDB = RPCopyDB or {}
    RPCopyDB.players = RPCopyDB.players or {}
    RPCopyDB.adventures = RPCopyDB.adventures or {}
    if RPCopyDB.autoUpdateKnown == nil then
        RPCopyDB.autoUpdateKnown = true
    end
    if RPCopyDB.autoScreenshots == nil then
        RPCopyDB.autoScreenshots = false
    end
    if RPCopyDB.quickCtrlC == nil then
        RPCopyDB.quickCtrlC = true
    end
    if not RPCopyDB.quickCopyKey or RPCopyDB.quickCopyKey == "" then
        RPCopyDB.quickCopyKey = "CTRL-C"
    end
    if RPCopyDB.quickCapture == nil then
        RPCopyDB.quickCapture = true
    end
    if not RPCopyDB.captureTargetKey or RPCopyDB.captureTargetKey == "" then
        RPCopyDB.captureTargetKey = "SHIFT-C"
    end
    if not RPCopyDB.lastSliceId or RPCopyDB.lastSliceId == "" then
        RPCopyDB.lastSliceId = "CHAT"
    end
    RPCopyDB.defaultMessages = math.max(1, math.min(10, tonumber(RPCopyDB.defaultMessages) or 3))
    RPCopyDB.expandMessages = math.max(1, math.min(20, tonumber(RPCopyDB.expandMessages) or 6))

    if type(RPCopyDB.tabs) ~= "table" or #RPCopyDB.tabs == 0 then
        RPCopyDB.tabs = CloneDefaultTabs()
        RPCopyDB.migratedV32 = true
    else
        for idx, t in ipairs(RPCopyDB.tabs) do
            t.id = t.id or ("CUSTOM_" .. tostring(idx) .. "_" .. tostring(time()))
            t.label = (t.label and t.label ~= "") and t.label or ("Tab " .. idx)
            if t.incOoc == nil then
                t.incOoc = false
            end
            if not RPCopyDB.migratedV32 and (t.prefix == nil or t.prefix == "") then
                t.prefix = ns.DEFAULT_TRIGGER
            else
                t.prefix = t.prefix or ""
            end
        end
        RPCopyDB.migratedV32 = true
    end

    for k, v in pairs(RPCopyDB.players) do
        if type(v) == "string" then
            RPCopyDB.players[k] = {
                note = v, level = "", race = "", class = "", guild = "",
                chatHistory = {}, lastSeen = "",
            }
        elseif type(v) == "table" then
            if v.info and v.info ~= "" and (not v.level or v.level == "") and (not v.class or v.class == "") then
                local l, r, c, g = ParseLegacyInfo(v.info)
                v.level, v.race, v.class, v.guild = l, r, c, g
            end
            v.info = nil
            v.level = v.level or ""
            v.race = v.race or ""
            v.class = v.class or ""
            v.guild = v.guild or ""
            v.note = v.note or ""
            if type(v.chatHistory) ~= "table" then
                v.chatHistory = {}
                if v.lastChat and v.lastChat ~= "" then
                    table.insert(v.chatHistory, v.lastChat)
                end
            end
            v.lastChat = nil
            v.lastSeen = v.lastSeen or ""
        end
    end

    for _, adv in ipairs(RPCopyDB.adventures or {}) do
        adv.shots = adv.shots or {}
        adv.reloads = adv.reloads or 0
        adv.story = adv.story or ""
        if (not adv.exportText or adv.exportText == "") and ns.BuildAdventureFullLog then
            adv.exportText = ns.BuildAdventureFullLog(adv)
        end
    end
end

function ns.FindPlayerKey(name, allowFirstNameUpgrade)
    if not name or name == "" or not RPCopyDB or not RPCopyDB.players then return nil end
    if RPCopyDB.players[name] then return name end

    local low = name:lower()
    for k in pairs(RPCopyDB.players) do
        if k:lower() == low then return k end
    end

    local inFirst, inLast = ns.SplitFullName(name)
    local inFirstLow = inFirst:lower()
    if inFirstLow ~= "" then
        for k in pairs(RPCopyDB.players) do
            local kFirst, kLast = ns.SplitFullName(k)
            if kFirst:lower() == inFirstLow then
                if allowFirstNameUpgrade and kLast == "" and inLast ~= "" then
                    RPCopyDB.players[name] = RPCopyDB.players[k]
                    RPCopyDB.players[k] = nil
                    return name
                end
                if inLast == "" then return k end
            end
        end
    end
    return nil
end

function ns.ResolveCanonicalPlayerName(rawName)
    if not rawName or rawName == "" then return nil end
    local savedKey = ns.FindPlayerKey(rawName, true)
    if savedKey then return savedKey end

    local rawFirstLow = ns.SplitFullName(rawName):lower()
    local units = { "target", "mouseover", "party1", "party2", "party3", "party4" }
    for _, u in ipairs(units) do
        if UnitExists(u) and UnitIsPlayer(u) then
            local uFirst = ns.StripRealm(UnitName(u))
            if uFirst and uFirst:lower() == rawFirstLow then
                return ns.GetUnitFullName(u) or rawName
            end
        end
    end
    return rawName
end

function ns.CaptureVisibleUnitFields(unit, entry)
    if not UnitExists(unit) or not UnitIsPlayer(unit) then return false end
    local lvl = ns.SafeNum(UnitLevel(unit))
    if lvl and lvl > 0 then
        entry.level = tostring(lvl)
    end
    local r = ns.SafeStr(UnitRace(unit))
    if r and r ~= "" then entry.race = r end
    local c = ns.SafeStr(UnitClass(unit))
    if c and c ~= "" then entry.class = c end
    local g = ns.SafeStr(GetGuildInfo(unit))
    if g and g ~= "" then
        entry.guild = g
    elseif g == nil then
        entry.guild = "None"
    end
    entry.lastSeen = ns.NowStamp()
    return true
end

function ns.FindVisibleUnitForPlayer(name)
    if not name or name == "" then return nil end
    local targetFirst = ns.SplitFullName(name):lower()
    local units = { "target", "mouseover", "party1", "party2", "party3", "party4" }
    for _, u in ipairs(units) do
        if UnitExists(u) and UnitIsPlayer(u) then
            local uFull = ns.GetUnitFullName(u)
            local uFirst = ns.StripRealm(UnitName(u))
            if (uFull and uFull:lower() == name:lower()) or (uFirst and uFirst:lower() == targetFirst) then
                return u
            end
        end
    end
    return nil
end

function ns.AppendConvoForPlayer(otherPlayerRaw, formattedConvoLine)
    if not otherPlayerRaw or otherPlayerRaw == "" or otherPlayerRaw == "Unknown" then return end
    local canonical = ns.ResolveCanonicalPlayerName(otherPlayerRaw)
    local selfFirst = ns.StripRealm(UnitName("player"))
    local selfFull = ns.GetUnitFullName("player") or selfFirst
    if canonical == selfFirst or canonical == selfFull then return end

    ns.logs.playerRecentChat[canonical] = ns.logs.playerRecentChat[canonical] or {}
    ns.PushBounded(ns.logs.playerRecentChat[canonical], formattedConvoLine, ns.MAX_PLAYER_CHAT)

    if RPCopyDB and RPCopyDB.autoUpdateKnown then
        local existingKey = ns.FindPlayerKey(canonical, true)
        if existingKey and RPCopyDB.players[existingKey] then
            local entry = RPCopyDB.players[existingKey]
            entry.chatHistory = entry.chatHistory or {}
            ns.PushBounded(entry.chatHistory, formattedConvoLine, ns.MAX_PLAYER_CHAT)
            entry.lastSeen = ns.NowStamp()
            local visUnit = ns.FindVisibleUnitForPlayer(existingKey)
            if visUnit then
                ns.CaptureVisibleUnitFields(visUnit, entry)
            end
        end
    end
end

function ns.HandleConversationCapture(channelLabel, rawAuthor, cleanMsg, isOutgoingWhisper, whisperRecipient)
    local selfFirst = ns.StripRealm(UnitName("player")) or ""
    local selfFull = ns.GetUnitFullName("player") or selfFirst
    local authorShort = ns.StripRealm(rawAuthor) or "Unknown"
    local where = ns.GetCurrentWhere()

    if isOutgoingWhisper then
        local recip = ns.ResolveCanonicalPlayerName(ns.StripRealm(whisperRecipient))
        if recip then
            ns.AppendConvoForPlayer(recip, string.format("[Whisper | %s] %s: %s", where, selfFull, cleanMsg))
        end
        return
    end

    local isSelf = (authorShort ~= "Unknown") and (authorShort == selfFirst or authorShort == selfFull)
    local hasPlayerTarget = UnitExists("target") and UnitIsPlayer("target")
    local targetFull = hasPlayerTarget and ns.GetUnitFullName("target") or nil
    local targetFirst = hasPlayerTarget and ns.StripRealm(UnitName("target")) or nil

    if isSelf then
        local recordedKeys = {}
        if targetFull and targetFirst ~= selfFirst then
            ns.AppendConvoForPlayer(targetFull, string.format("[%s | %s] %s: %s", channelLabel, where, selfFull, cleanMsg))
            recordedKeys[targetFull:lower()] = true
        end
        if channelLabel == "Party" or channelLabel == "Instance" or channelLabel == "Raid" then
            for i = 1, 4 do
                local u = "party" .. i
                if UnitExists(u) and UnitIsPlayer(u) then
                    local pFull = ns.GetUnitFullName(u)
                    if pFull and not recordedKeys[pFull:lower()] and ns.FindPlayerKey(pFull, true) then
                        ns.AppendConvoForPlayer(pFull, string.format("[%s | %s] %s: %s", channelLabel, where, selfFull, cleanMsg))
                        recordedKeys[pFull:lower()] = true
                    end
                end
            end
        end
    else
        local isWhisperIn = (channelLabel == "Whisper")
        local isCurrentTarget = hasPlayerTarget and (authorShort == targetFirst or authorShort == targetFull)
        local isSavedPlayer = (ns.FindPlayerKey(authorShort, true) ~= nil)

        if isWhisperIn or isCurrentTarget or isSavedPlayer then
            local speakerFull = isCurrentTarget and (targetFull or authorShort) or ns.ResolveCanonicalPlayerName(authorShort)
            ns.AppendConvoForPlayer(speakerFull, string.format("[%s | %s] %s: %s", channelLabel, where, speakerFull, cleanMsg))
        end
    end
end

function ns.SaveOrUpdatePlayer(name)
    ns.EnsureDB()
    if not name or name == "" then return nil, false end
    local canonical = ns.ResolveCanonicalPlayerName(name)
    local existingKey = ns.FindPlayerKey(canonical, true)
    local isNew = (existingKey == nil)
    local key = existingKey or canonical
    local entry = RPCopyDB.players[key] or {
        note = "", level = "", race = "", class = "", guild = "",
        chatHistory = {}, lastSeen = "",
    }

    local visUnit = ns.FindVisibleUnitForPlayer(key)
    if visUnit then
        ns.CaptureVisibleUnitFields(visUnit, entry)
    end

    local buf = ns.logs.playerRecentChat[key] or ns.logs.playerRecentChat[canonical] or ns.logs.playerRecentChat[ns.SplitFullName(key)]
    if buf and #buf > 0 then
        entry.chatHistory = {}
        for _, line in ipairs(buf) do
            ns.PushBounded(entry.chatHistory, line, ns.MAX_PLAYER_CHAT)
        end
    end
    entry.lastSeen = ns.NowStamp()

    RPCopyDB.players[key] = entry
    return key, isNew
end

function ns.GetKnownPlayerBlocks(searchBlob)
    if not RPCopyDB or not RPCopyDB.players then return {} end
    local haystack = ns.StripColors(searchBlob or ""):lower()
    if haystack == "" then return {} end

    local matchedKeys = {}
    for savedName, data in pairs(RPCopyDB.players) do
        if type(data) == "table" then
            local fullLow = savedName:lower()
            local firstLow = ns.SplitFullName(savedName):lower()
            local matched = haystack:find(fullLow, 1, true) ~= nil
            if not matched and #firstLow >= 3 then
                matched = haystack:find("%f[%a]" .. firstLow .. "%f[%A]") ~= nil
            end
            if matched then
                table.insert(matchedKeys, savedName)
            end
        end
    end

    table.sort(matchedKeys)
    local blocks = {}
    for _, savedName in ipairs(matchedKeys) do
        local data = RPCopyDB.players[savedName]
        local displayName = (data.class and data.class ~= "")
            and ns.ColorizeClass(savedName, data.class)
            or ns.ColorText(savedName, ns.COLORS.speaker)
        local noteVal = (data.note and data.note ~= "")
            and ns.ColorText(data.note, ns.COLORS.softWhite)
            or ns.ColorText("None", ns.COLORS.muted)

        local blockLines = {
            ns.ColorText("[Known Player:", ns.COLORS.gold) .. " " .. displayName .. ns.ColorText("]", ns.COLORS.gold),
            ns.ColorText("Note:", ns.COLORS.lootType) .. " " .. noteVal,
        }

        if type(data.chatHistory) == "table" and #data.chatHistory > 0 then
            table.insert(blockLines, ns.ColorText("Latest Chat:", ns.COLORS.lootType))
            for _, line in ipairs(data.chatHistory) do
                table.insert(blockLines, ns.ColorText(line, ns.COLORS.text))
            end
        else
            table.insert(blockLines, ns.ColorText("Latest Chat:", ns.COLORS.lootType) .. " " .. ns.ColorText("None", ns.COLORS.muted))
        end

        table.insert(blocks, table.concat(blockLines, "\n"))
    end
    return blocks
end