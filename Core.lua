local ADDON_NAME, ns = ...

local GetAddOnMetadata = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata

ns.VERSION = (GetAddOnMetadata and GetAddOnMetadata(ADDON_NAME, "Version")) or "0.6.0"

BINDING_HEADER_RPCHRONICLER = "RP Chronicler"
BINDING_NAME_RPCHRONICLER_OPEN = "Toggle RP Chronicler Window"
BINDING_NAME_RPCHRONICLER_QUICK = "Quick Copy (Last Used Slice)"
BINDING_NAME_RPCHRONICLER_CAPTURE = "Capture / Update Target Companion"
BINDING_NAME_RPCHRONICLER_MARK = "Bookmark Adventure Moment"
BINDING_NAME_RPCHRONICLER_RUN_START = "Start Recording an Adventure"
BINDING_NAME_RPCHRONICLER_RUN_PAUSE = "Pause / Resume Recording"
BINDING_NAME_RPCHRONICLER_RUN_END = "End & Save Recording"

ns.MAX_LINES = 25
ns.MAX_PLAYER_CHAT = 5

ns.DEFAULT_TRIGGER = "use aloria"

-- 0.6.0: the story skills' names (the "name:" line of the two story
-- templates in UI_Options.lua). The Full Log's first line is "use <name>".
ns.STORY_SKILLS = { dungeon = "wow-dungeon-raid-story", world = "wow-open-world-story" }

-- Section flags of a slice tab. Every tab can turn each one on or off in
-- Options > Slice Tabs. Chat sources are merged into one time-ordered timeline.
ns.TAB_FLAGS = {
    "incDirect", "incTarget", "incParty", "incStatus", "incQuest",
    "incSocial", "incPartySay", "incPartyChat", "incNpc", "incLoot", "incOoc", "incWorld", "incGuild",
}

local function Tab(id, label, on)
    local t = { id = id, label = label, prefix = ns.DEFAULT_TRIGGER }
    for _, k in ipairs(ns.TAB_FLAGS) do t[k] = on[k] and true or false end
    return t
end

ns.DEFAULT_TABS = {
    -- Chat: local RP (say, emotes, whispers); the direct line is marked inside the timeline
    Tab("CHAT", "Chat", { incDirect = true, incTarget = true, incStatus = true, incSocial = true }),
    -- World: General, Trade, LFG and other numbered channels (the OOC channel is kept apart)
    Tab("WORLD", "World", { incStatus = true, incWorld = true }),
    -- Party: your group only (party chat plus say/emotes from party members)
    Tab("PARTY", "Party", { incTarget = true, incParty = true, incStatus = true,
        incPartySay = true, incPartyChat = true }),
    -- Guild: guild and officer chat
    Tab("GUILD", "Guild", { incGuild = true }),
    Tab("QUEST", "Quest", { incTarget = true, incStatus = true, incQuest = true, incNpc = true }),
    Tab("LOOT", "Loot", { incParty = true, incStatus = true, incLoot = true }),
}

-- Full Log categories. Each one has its own switch in Options > Full Log.
ns.LOG_CATEGORIES = {
    { key = "fights",      label = "Fights (one line each)" },
    { key = "fightStreaks", label = "Fold repeated trash fights" },
    { key = "kills",       label = "Kills of elites, rares, bosses" },
    { key = "aggro",       label = "Aggro swaps" },
    { key = "danger",      label = "Near deaths and saves" },
    { key = "spells",      label = "Party spells" },
    { key = "bossCasts",   label = "Boss casts" },
    { key = "cc",          label = "Crowd control" },
    { key = "pets",        label = "Pets" },
    { key = "quests",      label = "Quests accepted and done" },
    { key = "questObjectives", label = "Quest objectives done" },
    { key = "npcDialogue", label = "NPC and quest dialogue" },
    { key = "levels",      label = "Level ups" },
    { key = "places",      label = "Subzone changes" },
    { key = "skills",      label = "Profession skill-ups" },
    { key = "milestones",  label = "Milestones" },
    { key = "loot",        label = "Loot and coin" },
    { key = "lootSource",  label = "Where loot came from" },
    { key = "atmosphere",  label = "Atmosphere (time of day)" },
    { key = "guildmates",  label = "Guildmates in the party" },
    { key = "chat",        label = "Party and say chat" },
    { key = "screenshots", label = "Screenshot list (for export)" },
}

-- Editable limits (Options > Full Log)
ns.LOG_LIMITS = {
    { key = "minFightSec", label = "Shortest fight to log (sec)", default = 4, min = 0, max = 60 },
    { key = "spellCap",    label = "Spell lines per run",         default = 120, min = 0, max = 400 },
    { key = "npcCap",      label = "NPC dialogue lines per run",  default = 60, min = 0, max = 300 },
    { key = "timelineMax", label = "Timeline lines kept per run",  default = 500, min = 100, max = 1500 },
    { key = "shotCap",     label = "Screenshots kept per run",     default = 40, min = 0, max = 200 },
}

-- AI picker for the Full Log size meter: a comfortable paste size in
-- characters (about 4 characters per token). Each leaves room for the
-- skill's instructions and the story it writes. Checked November 2026:
-- free Gemini has a 32K token context, free ChatGPT about 27K, paid
-- ChatGPT about 54K, paid Gemini and Claude up to 1M.
ns.AI_MODELS = {
    { key = "GEMINI_FREE",  label = "Gemini (free)",       chars = 80000 },
    { key = "GEMINI_PAID",  label = "Gemini (paid)",       chars = 300000 },
    { key = "CHATGPT_FREE", label = "ChatGPT (free)",      chars = 50000 },
    { key = "CHATGPT_PAID", label = "ChatGPT (paid)",      chars = 150000 },
    { key = "CLAUDE_FREE",  label = "Claude (free)",       chars = 100000 },
    { key = "CLAUDE_PAID",  label = "Claude (paid)",       chars = 400000 },
    { key = "CUSTOM",       label = "Custom limit",        chars = nil },
}

-- Run Summary stats (Recordings > Summary and the top bar). Each one has a
-- switch in Options > Summary. kinds: which run types show it.
ns.SUMMARY_STATS = {
    { key = "roster",     label = "Party roster",            kinds = "all" },
    { key = "bosses",     label = "Boss kills",              kinds = "instance" },
    { key = "wipes",      label = "Wipes",                   kinds = "instance" },
    { key = "deaths",     label = "Deaths",                  kinds = "all" },
    { key = "levels",     label = "Levels gained",           kinds = "all" },
    { key = "foes",       label = "Foes defeated",           kinds = "all" },
    { key = "notable",    label = "Named, elite, rare kills", kinds = "all" },
    { key = "pvp",        label = "PvP kills and deaths",    kinds = "all" },
    { key = "quests",     label = "Quests completed",        kinds = "all" },
    { key = "places",     label = "Zones and places visited", kinds = "world" },
    { key = "skills",     label = "Skill-ups",               kinds = "all" },
    { key = "milestones", label = "Milestones",              kinds = "all" },
    { key = "loot",       label = "Notable loot",            kinds = "all" },
    { key = "coin",       label = "Coin earned",             kinds = "all" },
    { key = "shots",      label = "Screenshots",             kinds = "all" },
    { key = "highlights", label = "Highlights",              kinds = "all" },
}

function ns.SummaryOn(key)
    local c = RPChroniclerDB and RPChroniclerDB.summaryStats
    return not c or c[key] ~= false
end

-- Chat types RP Chronicler captures (Options > Privacy and the first-run setup)
ns.CAPTURE_TYPES = {
    { key = "say",     label = "Say, yell and emotes" },
    { key = "whisper", label = "Whispers" },
    { key = "group",   label = "Party, raid and instance chat" },
    { key = "guild",   label = "Guild and officer chat" },
    { key = "world",   label = "World channels (General, Trade, LFG)" },
    { key = "npc",     label = "NPC dialogue" },
}

function ns.CaptureOn(key)
    local c = RPChroniclerDB and RPChroniclerDB.capture
    return not c or c[key] ~= false
end

-- The privacy note (first-run setup and Options > Privacy). Plain ASCII.
ns.PRIVACY_TEXT =
    "|cffd8dee9RP Chronicler stores everything on your PC, in your WoW SavedVariables. It has no internet access and sends nothing anywhere. " ..
    "No account, email or real-world personal data is collected.\n" ..
    "Chat and log text only leave your PC if YOU paste them into your own AI tool, and that tool's own privacy terms apply then.\n" ..
    "You can delete everything at any time with |cff69ccf0/rp wipe|cffd8dee9 (or by deleting RPChronicler.lua in your SavedVariables folder).|r"

-- /rp wipe and Options > Privacy: forget everything, then reload
function ns.WipeAllData()
    if InCombatLockdown and InCombatLockdown() then
        print("|cffffd100RP Chronicler|r Leave combat first, then try again.")
        return false
    end
    if ns.DropActiveAdventure then ns.DropActiveAdventure() end
    RPChroniclerDB = {}
    ns._dbChecked = nil
    ns.EnsureDB()
    RPChroniclerDB.wipedAt = time and time() or 0
    print("|cffffd100RP Chronicler|r All RP Chronicler data deleted. Reloading...")
    if ReloadUI then ReloadUI() end
    return true
end

function ns.LogOn(cat)
    local c = RPChroniclerDB and RPChroniclerDB.logCats
    return not c or c[cat] ~= false
end

function ns.Limit(key)
    local l = RPChroniclerDB and RPChroniclerDB.limits
    local v = l and tonumber(l[key])
    if v then return v end
    for _, d in ipairs(ns.LOG_LIMITS) do
        if d.key == key then return d.default end
    end
    return 0
end

local function CloneDefaultTabs()
    local copy = {}
    for _, t in ipairs(ns.DEFAULT_TABS) do
        local item = {}
        for k, v in pairs(t) do item[k] = v end
        table.insert(copy, item)
    end
    return copy
end

RPChroniclerDB = RPChroniclerDB or {
    players = {},
    adventures = {},
    autoUpdateKnown = true,
    autoScreenshots = false,
    worldAutoShots = false, -- 0.5.1: auto shots only in dungeons and raids
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
    world = {},
    guild = {},
    playerRecentChat = {},
}

ns.state = {
    lastDirectMsg = nil,
    lastDirectAuthor = nil,
    lastQuestInfo = nil,
    activeFilter = "CHAT",
    activeNote = "",
    isExpanded = false,
    selectedPlayerKey = nil,
    selectedAdventureId = nil,
    adventureViewMode = "SUMMARY",
    selectedOptionTabId = "CHAT",
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
    boss         = "dc143c", -- crimson, not the Druid orange
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
    PRIEST      = "C0C0C0", -- gray, so it reads on the light story parchment
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

-- Class token ("HUNTER") from a token or an English class name. Other
-- client languages store the token itself (0.5.0), so colors always work.
function ns.ClassToken(cls)
    if type(cls) ~= "string" or cls == "" then return nil end
    local key = cls:upper():gsub("%s+", "")
    if ns.CLASS_COLORS[key] then return key end
    if LOCALIZED_CLASS_NAMES_MALE then
        for token, loc in pairs(LOCALIZED_CLASS_NAMES_MALE) do
            if loc == cls then return token end
        end
    end
    if LOCALIZED_CLASS_NAMES_FEMALE then
        for token, loc in pairs(LOCALIZED_CLASS_NAMES_FEMALE) do
            if loc == cls then return token end
        end
    end
    return nil
end

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

-- Honor rank titles that UnitPVPName puts in front of a name. They are
-- never part of a companion's name ("Private Aloria" is Aloria).
ns.HONOR_RANKS = {
    "Grand Marshal", "Field Marshal", "Marshal", "Commander", "Lieutenant Commander",
    "Knight-Champion", "Knight-Captain", "Knight-Lieutenant", "Knight", "Sergeant Major",
    "Master Sergeant", "Sergeant", "Corporal", "Private",
    "High Warlord", "Warlord", "General", "Lieutenant General", "Champion", "Centurion",
    "Legionnaire", "Blood Guard", "Stone Guard", "First Sergeant", "Senior Sergeant",
    "Grunt", "Scout",
}
table.sort(ns.HONOR_RANKS, function(a, b) return #a > #b end)

function ns.StripHonorRank(name)
    if type(name) ~= "string" then return name end
    for _, r in ipairs(ns.HONOR_RANKS) do
        if #name > #r + 1 and name:sub(1, #r + 1) == r .. " " then
            return (name:sub(#r + 2):match("^%s*(.-)%s*$"))
        end
    end
    return name
end

function ns.GetUnitFullName(unit)
    if not UnitExists(unit) then return nil end
    if UnitFullName then
        local ok, raw = pcall(UnitFullName, unit)
        local n = ok and ns.StripRealm(raw) or nil
        if n then n = ns.StripHonorRank(n) end
        if n and n:find("%s") then return n end
    end
    if UnitPVPName then
        local ok, raw = pcall(UnitPVPName, unit)
        local pvp = ok and ns.StripRealm(raw) or nil
        -- "Private Aloria" is a rank title, not a last name
        if pvp then pvp = ns.StripHonorRank(pvp) end
        if pvp and pvp:find("%s") then return pvp end
    end
    local base = ns.StripRealm(UnitName(unit))
    if base and GameTooltip and GameTooltip:IsShown() and GameTooltipTextLeft1 then
        local tip1 = ns.SafeStr(GameTooltipTextLeft1:GetText())
        if tip1 then
            local escapedBase = base:gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1")
            local fullFromTip = ns.StripHonorRank(tip1):match("^(" .. escapedBase .. "%s+%S+)")
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
    local key = ns.ClassToken(classFile) or ""
    local hex = ns.CLASS_COLORS[key]
    if hex then
        return "|cff" .. hex .. text .. "|r"
    end
    return text
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

-- =========================================================
-- Role fallback: when UnitGroupRolesAssigned says NONE, guess
-- Tank / Healer / DPS from forms and stances, the player's own
-- talents, who holds aggro in fights, and finally the class.
-- Every API is guarded; secret values are ignored.
-- =========================================================
local ROLE_AURAS = {
    ["Bear Form"] = "TANK", ["Dire Bear Form"] = "TANK",
    ["Defensive Stance"] = "TANK", ["Righteous Fury"] = "TANK",
    ["Shadowform"] = "DAMAGER", ["Cat Form"] = "DAMAGER", ["Moonkin Form"] = "DAMAGER",
    ["Berserker Stance"] = "DAMAGER",
    ["Tree of Life"] = "HEALER",
}

-- Classic talent tab order -> role
local TALENT_TAB_ROLES = {
    WARRIOR = { "DAMAGER", "DAMAGER", "TANK" },
    PALADIN = { "HEALER", "TANK", "DAMAGER" },
    PRIEST  = { "HEALER", "HEALER", "DAMAGER" },
    SHAMAN  = { "DAMAGER", "DAMAGER", "HEALER" },
    DRUID   = { "DAMAGER", "DAMAGER", "HEALER" },
    DEATHKNIGHT = { "TANK", "DAMAGER", "DAMAGER" },
}

local CLASS_DEFAULT_ROLE = {
    WARRIOR = "TANK", PALADIN = "HEALER", PRIEST = "HEALER", SHAMAN = "HEALER",
    DRUID = "HEALER", HUNTER = "DAMAGER", ROGUE = "DAMAGER", MAGE = "DAMAGER",
    WARLOCK = "DAMAGER", DEATHKNIGHT = "TANK", MONK = "DAMAGER",
    DEMONHUNTER = "DAMAGER", EVOKER = "DAMAGER",
}

local CAN_TANK = { WARRIOR = true, PALADIN = true, DRUID = true, DEATHKNIGHT = true, MONK = true, DEMONHUNTER = true }

local function AuraRole(unit)
    for i = 1, 40 do
        local name
        if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
            local ok, data = pcall(C_UnitAuras.GetAuraDataByIndex, unit, i, "HELPFUL")
            if not ok or type(data) ~= "table" then break end
            name = ns.SafeStr(data.name)
        elseif UnitBuff then
            local ok, n = pcall(UnitBuff, unit, i)
            if not ok or n == nil then break end
            name = ns.SafeStr(n)
        else
            break
        end
        if name and ROLE_AURAS[name] then return ROLE_AURAS[name] end
    end
    return nil
end

local function PlayerFormRole()
    if not (GetNumShapeshiftForms and GetShapeshiftFormInfo) then return nil end
    local okN, num = pcall(GetNumShapeshiftForms)
    if not okN or type(num) ~= "number" then return nil end
    for i = 1, num do
        local ok, _, active, _, spellID = pcall(GetShapeshiftFormInfo, i)
        if ok and active == true and type(spellID) == "number" then
            local sName
            if C_Spell and C_Spell.GetSpellName then
                local okS, n = pcall(C_Spell.GetSpellName, spellID)
                sName = okS and ns.SafeStr(n) or nil
            elseif GetSpellInfo then
                local okS, n = pcall(GetSpellInfo, spellID)
                sName = okS and ns.SafeStr(n) or nil
            end
            if sName and ROLE_AURAS[sName] then return ROLE_AURAS[sName] end
        end
    end
    return nil
end

local function PlayerTalentRole(classFile)
    -- Modern spec API first
    if GetSpecialization and GetSpecializationRole then
        local ok, spec = pcall(GetSpecialization)
        if ok and type(spec) == "number" and spec > 0 then
            local okR, r = pcall(GetSpecializationRole, spec)
            r = okR and ns.SafeStr(r) or nil
            if r == "TANK" or r == "HEALER" or r == "DAMAGER" then return r end
        end
    end
    -- Classic talent trees: the tab with the most points decides
    local map = TALENT_TAB_ROLES[classFile or ""]
    if not map or not GetNumTalentTabs or not GetTalentTabInfo then return nil end
    local okN, tabs = pcall(GetNumTalentTabs)
    if not okN or type(tabs) ~= "number" then return nil end
    local bestTab, bestPts = nil, 0
    for t = 1, math.min(tabs, 3) do
        local r = { pcall(GetTalentTabInfo, t) }
        if r[1] then
            -- Classic returns (name, icon, points, ...); newer returns (id, name, desc, icon, points, ...)
            local pts = (type(r[4]) == "number" and r[4]) or (type(r[6]) == "number" and r[6]) or 0
            if pts > bestPts then bestTab, bestPts = t, pts end
        end
    end
    if bestTab and bestPts >= 5 then return map[bestTab] end
    return nil
end

-- Returns role ("TANK"/"HEALER"/"DAMAGER") and whether it was guessed.
function ns.GetUnitRole(unit)
    if not unit or not UnitExists(unit) then return "NONE", false end
    if UnitGroupRolesAssigned then
        local ok, r = pcall(UnitGroupRolesAssigned, unit)
        r = ok and ns.SafeStr(r) or nil
        if r == "TANK" or r == "HEALER" or r == "DAMAGER" then return r, false end
    end
    local _, classFile = UnitClass(unit)
    classFile = ns.SafeStr(classFile) or ""

    local isPlayer = UnitIsUnit and UnitIsUnit(unit, "player") == true
    local guess = (isPlayer and PlayerFormRole()) or AuraRole(unit)
    if not guess and isPlayer then guess = PlayerTalentRole(classFile) end

    -- Behavior: a tank-capable class that keeps holding enemies' attention
    if not guess and CAN_TANK[classFile] and ns.GetAggroShare then
        local share, samples = ns.GetAggroShare(ns.StripRealm(UnitName(unit)))
        if samples and samples >= 6 and share >= 0.4 then guess = "TANK" end
    end

    guess = guess or CLASS_DEFAULT_ROLE[classFile] or "DAMAGER"
    return guess, true
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

-- Log entries are tables: { line = colored text, seq = global order,
-- author = short name or nil, chan = channel label or nil }. The sequence
-- number lets the snapshot merge several buffers into one timeline.
ns.logSeq = 0
function ns.PushLog(tbl, line, author, chan)
    if not line or line == "" then return end
    -- A "secret" value in a line would make the whole snapshot secret
    if ns.IsSecret(line) or ns.IsSecret(author) then return end
    ns.logSeq = ns.logSeq + 1
    local entry = { line = line, seq = ns.logSeq, author = author, chan = chan }
    if (tbl == ns.logs.social or tbl == ns.logs.world) and IsOocLine(line) then
        ns.logs.ooc = ns.logs.ooc or {}
        ns.PushBounded(ns.logs.ooc, entry, ns.MAX_LINES)
        return entry
    end
    ns.PushBounded(tbl, entry, ns.MAX_LINES)
    return entry
end

-- Text of a log entry (entries pushed before 0.3.1 were plain strings)
function ns.LogLine(entry)
    if type(entry) == "table" then return entry.line end
    return entry
end

function ns.ClearSessionLogs()
    ns.logs.social = {}
    ns.logs.ooc = {}
    ns.logs.party = {}
    ns.logs.loot = {}
    ns.logs.combat = {}
    ns.logs.npc = {}
    ns.logs.world = {}
    ns.logs.guild = {}
    ns.state.lastDirectMsg = nil
    ns.state.lastDirectEntry = nil
    ns.state.lastLife = nil
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
    RPChroniclerDB.tabs = CloneDefaultTabs()
    RPChroniclerDB.migratedV32 = true
    ns.state.selectedOptionTabId = RPChroniclerDB.tabs[1].id
    ns.state.activeFilter = RPChroniclerDB.tabs[1].id
    RPChroniclerDB.lastSliceId = RPChroniclerDB.tabs[1].id
end

function ns.GetTabConfig(tabId)
    ns.EnsureDB()
    for _, t in ipairs(RPChroniclerDB.tabs) do
        if t.id == tabId then return t end
    end
    return RPChroniclerDB.tabs[1]
end

-- The full check runs once per RPChroniclerDB table (it also runs migrations and
-- rebuilds old Full Logs). Later calls return at once: EnsureDB is called
-- on every copy, and a slow copy was one lead in the 0.4.0 Ctrl+C bug.
function ns.EnsureDB()
    if RPChroniclerDB and ns._dbChecked == RPChroniclerDB then return end
    RPChroniclerDB = RPChroniclerDB or {}
    RPChroniclerDB.players = RPChroniclerDB.players or {}
    RPChroniclerDB.adventures = RPChroniclerDB.adventures or {}
    if RPChroniclerDB.autoUpdateKnown == nil then
        RPChroniclerDB.autoUpdateKnown = true
    end
    if RPChroniclerDB.autoScreenshots == nil then
        RPChroniclerDB.autoScreenshots = false
    end
    if RPChroniclerDB.quickCtrlC == nil then
        RPChroniclerDB.quickCtrlC = true
    end
    if not RPChroniclerDB.quickCopyKey or RPChroniclerDB.quickCopyKey == "" then
        RPChroniclerDB.quickCopyKey = "CTRL-C"
    end
    if RPChroniclerDB.quickCapture == nil then
        RPChroniclerDB.quickCapture = true
    end
    if not RPChroniclerDB.captureTargetKey or RPChroniclerDB.captureTargetKey == "" then
        RPChroniclerDB.captureTargetKey = "SHIFT-C"
    end
    if not RPChroniclerDB.lastSliceId or RPChroniclerDB.lastSliceId == "" then
        RPChroniclerDB.lastSliceId = "CHAT"
    end
    RPChroniclerDB.defaultMessages = math.max(1, math.min(10, tonumber(RPChroniclerDB.defaultMessages) or 3))
    RPChroniclerDB.expandMessages = math.max(1, math.min(20, tonumber(RPChroniclerDB.expandMessages) or 6))

    if type(RPChroniclerDB.tabs) ~= "table" or #RPChroniclerDB.tabs == 0 then
        RPChroniclerDB.tabs = CloneDefaultTabs()
        RPChroniclerDB.migratedV32 = true
    else
        for idx, t in ipairs(RPChroniclerDB.tabs) do
            t.id = t.id or ("CUSTOM_" .. tostring(idx) .. "_" .. tostring(time()))
            t.label = (t.label and t.label ~= "") and t.label or ("Tab " .. idx)
            if t.incOoc == nil then
                t.incOoc = false
            end
            if t.incPartySay == nil then t.incPartySay = false end
            if t.incWorld == nil then t.incWorld = false end
            -- 0.3.1: deaths and level ups moved into the Status line
            t.incCombat = nil
            if not RPChroniclerDB.migratedV32 and (t.prefix == nil or t.prefix == "") then
                t.prefix = ns.DEFAULT_TRIGGER
            else
                t.prefix = t.prefix or ""
            end
        end
        RPChroniclerDB.migratedV32 = true
        -- 0.3.1 gave the built-in tabs new contents (Smart = everything nearby,
        -- Party = group focus). Update them once; names and Skill Calls stay.
        if not RPChroniclerDB.migratedV031 then
            for _, def in ipairs(ns.DEFAULT_TABS) do
                for _, t in ipairs(RPChroniclerDB.tabs) do
                    if t.id == def.id then
                        for _, k in ipairs(ns.TAB_FLAGS) do t[k] = def[k] end
                    end
                end
            end
        end
    end
    RPChroniclerDB.migratedV031 = true
    -- 0.4.0: Smart is gone; World and Guild are new built-in tabs
    if not RPChroniclerDB.migratedV040 then
        for i = #RPChroniclerDB.tabs, 1, -1 do
            if RPChroniclerDB.tabs[i].id == "SMART" then table.remove(RPChroniclerDB.tabs, i) end
        end
        for idx, def in ipairs(ns.DEFAULT_TABS) do
            local found = false
            for _, t in ipairs(RPChroniclerDB.tabs) do
                if t.id == def.id then found = true end
            end
            if not found then
                local item = {}
                for k, v in pairs(def) do item[k] = v end
                table.insert(RPChroniclerDB.tabs, math.min(idx, #RPChroniclerDB.tabs + 1), item)
            end
        end
        if RPChroniclerDB.lastSliceId == "SMART" then RPChroniclerDB.lastSliceId = "CHAT" end
        RPChroniclerDB.migratedV040 = true
    end
    for _, t in ipairs(RPChroniclerDB.tabs) do
        if t.incGuild == nil then t.incGuild = false end
    end

    -- 0.4.0 settings: Full Log categories, limits, recording behaviour
    RPChroniclerDB.logCats = type(RPChroniclerDB.logCats) == "table" and RPChroniclerDB.logCats or {}
    for _, c in ipairs(ns.LOG_CATEGORIES) do
        if RPChroniclerDB.logCats[c.key] == nil then RPChroniclerDB.logCats[c.key] = true end
    end
    RPChroniclerDB.limits = type(RPChroniclerDB.limits) == "table" and RPChroniclerDB.limits or {}
    for _, d in ipairs(ns.LOG_LIMITS) do
        local v = tonumber(RPChroniclerDB.limits[d.key]) or d.default
        RPChroniclerDB.limits[d.key] = math.max(d.min, math.min(d.max, math.floor(v)))
    end
    local defaults = {
        autoRecord = true,        -- dungeons and raids record by themselves
        promptOnGroup = true,     -- open world: ask "Start recording?" when you join a group
        promptOnLogin = false,    -- open world: ask at login
        resumeAfterReload = true, -- a /reload continues the run without asking
        iconState = true,         -- the [RP] button shows the recording state
        sizeMeter = true,         -- Full Log size meter
        debugVerbose = false,     -- extra lines in the debug log
        -- 0.5.0
        debugEnabled = true,      -- the debug log itself
        recordManualShots = true, -- your own Print Screen shots join the run
        autoColorStory = true,    -- color plain names in an imported story
        exportTip = true,         -- the export tip in the Story Book
        knownPlayerBlocks = true, -- [Known Player] blocks in snapshots
        knownPlayerMax = 3,       -- at most this many blocks
        knownNoteMax = 300,       -- characters of each note in a block
        companionMenu = true,     -- "Add as RP Chronicler companion" in unit menus
        nearbyChip = true,        -- "Nearby companions" chip in the Copy view
        runCompanions = true,     -- companions who chat in a run are Known companions
        rpReplyLength = "SHORT",  -- RP template: SHORT, MEDIUM or LONG
        exportImageDir = "",      -- Export_Stories.bat: where images go ("" = next to the pages)
        exportShotsDir = "",      -- Export_Stories.bat: the game's Screenshots folder ("" = auto)
    }
    for k, v in pairs(defaults) do
        if RPChroniclerDB[k] == nil then RPChroniclerDB[k] = v end
    end
    RPChroniclerDB.knownPlayerMax = math.max(0, math.min(10, math.floor(tonumber(RPChroniclerDB.knownPlayerMax) or 3)))
    RPChroniclerDB.knownNoteMax = math.max(40, math.min(1000, math.floor(tonumber(RPChroniclerDB.knownNoteMax) or 300)))
    RPChroniclerDB.summaryStats = type(RPChroniclerDB.summaryStats) == "table" and RPChroniclerDB.summaryStats or {}
    RPChroniclerDB.capture = type(RPChroniclerDB.capture) == "table" and RPChroniclerDB.capture or {}
    for _, c in ipairs(ns.CAPTURE_TYPES) do
        if RPChroniclerDB.capture[c.key] == nil then RPChroniclerDB.capture[c.key] = true end
    end
    RPChroniclerDB.stories = type(RPChroniclerDB.stories) == "table" and RPChroniclerDB.stories or {}
    -- 0.5.0: the Status line is back in Chat and World (it lived in Smart)
    if not RPChroniclerDB.migratedV050 then
        for _, t in ipairs(RPChroniclerDB.tabs) do
            if t.id == "CHAT" or t.id == "WORLD" then t.incStatus = true end
        end
    end
    if type(RPChroniclerDB.aiModel) ~= "string" then RPChroniclerDB.aiModel = "GEMINI_FREE" end
    RPChroniclerDB.aiCustomLimit = math.max(1000, tonumber(RPChroniclerDB.aiCustomLimit) or 40000)

    for k, v in pairs(RPChroniclerDB.players) do
        if type(v) == "string" then
            RPChroniclerDB.players[k] = {
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

    for _, adv in ipairs(RPChroniclerDB.adventures or {}) do
        adv.shots = adv.shots or {}
        -- 0.5.0: every shot is a numbered table
        for i, sh in ipairs(adv.shots) do
            if type(sh) ~= "table" then adv.shots[i] = { n = i, description = "Captured moment" }
            elseif not sh.n then sh.n = i end
        end
        adv.reloads = adv.reloads or 0
        if (not adv.exportText or adv.exportText == "") and ns.BuildAdventureFullLog then
            adv.exportText = ns.BuildAdventureFullLog(adv)
        end
    end

    -- 0.5.0 migrations live with their modules: companions (Companions.lua)
    -- and stories moving out of the recordings (Adventures.lua)
    if not RPChroniclerDB.migratedV050 and ns.MigrateCompanions and ns.MigrateStories then
        pcall(ns.MigrateCompanions)
        pcall(ns.MigrateStories)
        RPChroniclerDB.migratedV050 = true
    end
    -- 0.6.0: saved Full Logs call the story skill by its name
    if not RPChroniclerDB.migratedV060 then
        for _, adv in ipairs(RPChroniclerDB.adventures or {}) do
            local log = adv.exportText
            if type(log) == "string" then
                local skill = (adv.kind == "world") and ns.STORY_SKILLS.world or ns.STORY_SKILLS.dungeon
                adv.exportText = log:gsub("^use adventure story\n", "use " .. skill .. "\n", 1):gsub("^use story\n", "use " .. skill .. "\n", 1)
            end
        end
        RPChroniclerDB.migratedV060 = true
    end
    if ns.BuildAdventureFullLog and ns.MigrateStories then ns._dbChecked = RPChroniclerDB end
end


-- =========================================================
-- 0.6.0: RPCopy was renamed RP Chronicler. WoW only loads the SavedVariables
-- of the addon that declares them, from a file named after that addon, so
-- the old data (RPCopyDB in SavedVariables\RPCopy.lua) is only readable
-- while the old RPCopy addon is still installed. The toc lists RPCopy under
-- OptionalDeps, so when it is there it loads first and RPCopyDB is filled
-- in before our ADDON_LOADED. We then copy it once into RPChroniclerDB,
-- turn the old addon off for next time and ask for a /reload. RPCopy.lua is
-- left untouched as a backup.
-- =========================================================
do
    local OLD_ADDON = "RPCopy"
    local function DeepCopy(v, seen)
        if type(v) ~= "table" then return v end
        seen = seen or {}
        if seen[v] then return seen[v] end
        local out = {}
        seen[v] = out
        for k, x in pairs(v) do out[DeepCopy(k, seen)] = DeepCopy(x, seen) end
        return out
    end
    local function IsEmpty(db)
        if type(db) ~= "table" then return true end
        if db.migratedFromRPCopy or db.wipedAt then return false end
        for _, k in ipairs({ "players", "adventures", "stories" }) do
            if type(db[k]) == "table" and next(db[k]) ~= nil then return false end
        end
        return true
    end
    local function OldLoaded()
        local f = (C_AddOns and C_AddOns.IsAddOnLoaded) or IsAddOnLoaded
        if not f then return false end
        local ok, loaded = pcall(f, OLD_ADDON)
        return ok and loaded and true or false
    end
    local function DisableOld()
        local f = (C_AddOns and C_AddOns.DisableAddOn) or DisableAddOn
        if not f then return end
        pcall(f, OLD_ADDON)
        local me = UnitName and UnitName("player")
        if me then pcall(f, OLD_ADDON, me) end
    end

    -- Returns true when data was copied
    function ns.MigrateFromRPCopy(force)
        local old = _G.RPCopyDB
        if type(old) ~= "table" or next(old) == nil then return false end
        if not force and not IsEmpty(RPChroniclerDB) then return false end
        local copy = DeepCopy(old)
        copy.migratedFromRPCopy = time and time() or 0
        RPChroniclerDB = copy
        ns._dbChecked = nil
        return true
    end

    local f = CreateFrame("Frame")
    f:RegisterEvent("ADDON_LOADED")
    f:SetScript("OnEvent", function(self, _, name)
        if name ~= ADDON_NAME then return end
        self:UnregisterEvent("ADDON_LOADED")
        local ok, copied = pcall(ns.MigrateFromRPCopy)
        -- The 0.6.0 zip ships an RPCopy folder with no code (data only). The
        -- full old addon defines RPCopy_Toggle; then a /reload is needed so
        -- the two do not run side by side.
        local oldCode = type(_G.RPCopy_Toggle) == "function"
        local after = oldCode and "|cffffd100Type /reload now|r, then delete the old folder |cffeceff1Interface\\AddOns\\RPCopy|r."
            or "You can delete the old folder |cffeceff1Interface\\AddOns\\RPCopy|r."
        if ok and copied then
            DisableOld()
            ns.loginNotice = "|cffffd100RP Chronicler|r |cff5cb85cRPCopy is now RP Chronicler.|r Your companions, recordings, stories and settings were copied over, and the old RPCopy entry is turned off. " .. after
        elseif OldLoaded() and not (RPChroniclerDB and RPChroniclerDB.migratedFromRPCopy) then
            -- Both addons hold data: never overwrite, let the player choose
            ns.loginNotice = "|cffffd100RP Chronicler|r The old |cffeceff1RPCopy|r addon is loaded and both have saved data. " ..
                "To replace your RP Chronicler data with the RPCopy data, type |cffffd100/rp import rpcopy|r. Otherwise turn RPCopy off in the AddOns list and delete its folder."
        elseif OldLoaded() then
            DisableOld()
            ns.loginNotice = "|cffffd100RP Chronicler|r Your RPCopy data was already moved, so the old |cffeceff1RPCopy|r entry is turned off now. " .. after
        end
    end)
end
