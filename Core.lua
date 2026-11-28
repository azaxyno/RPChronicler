local ADDON_NAME, ns = ...

local GetAddOnMetadata = C_AddOns and C_AddOns.GetAddOnMetadata

ns.VERSION = (GetAddOnMetadata and GetAddOnMetadata(ADDON_NAME, "Version")) or "0.7.1"

BINDING_HEADER_RPCHRONICLER = "RP Chronicler"
BINDING_NAME_RPCHRONICLER_OPEN = "Toggle RP Chronicler Window"
BINDING_NAME_RPCHRONICLER_QUICK = "Quick Copy (Last Used Slice)"
BINDING_NAME_RPCHRONICLER_CAPTURE = "Capture / Update Target Companion"
BINDING_NAME_RPCHRONICLER_MARK = "Bookmark Adventure Moment"
BINDING_NAME_RPCHRONICLER_RUN_START = "Start Recording an Adventure"
BINDING_NAME_RPCHRONICLER_RUN_PAUSE = "Pause / Resume Recording"
BINDING_NAME_RPCHRONICLER_RUN_END = "End & Save Recording"
BINDING_NAME_RPCHRONICLER_NOTE = "Add a Story Note (character's thought)"

ns.MAX_LINES = 25
ns.MAX_PLAYER_CHAT = 5

ns.DEFAULT_TRIGGER = "use my-character"

-- 0.6.5 (Mor): a tab whose Skill Call was never changed calls the skill
-- after the character you play: "use aloria" (first name, lowercase).
-- Tabs are account-wide, so this is worked out per character and the
-- saved value stays the placeholder; a Skill Call you typed is kept.
function ns.SkillCall(prefix)
    if prefix ~= ns.DEFAULT_TRIGGER then return prefix end
    local name = ns.PlayerName and ns.PlayerName() or nil
    local first = type(name) == "string" and name:match("^([^%s%-]+)") or nil
    if not first or first == "" or first == "You" then return prefix end
    return "use " .. first:lower()
end

-- 0.6.0: the story skills' names (the "name:" line of the two story
-- templates in UI_Options.lua). The Full Log's first line is "use <name>".
ns.STORY_SKILLS = { dungeon = "wow-dungeon-raid-story", world = "wow-open-world-story" }

-- What a slice tab can hold (0.6.1: one list for the snapshot and the
-- Slice Tabs page). Every tab can turn each one on or off in
-- Options > Slice Tabs.
-- Sections: lines of their own at the top of the snapshot.
ns.TAB_SECTIONS = {
    { key = "incDirect", short = "Line to you", label = "Last whisper / say to you" },
    { key = "incTarget", short = "Target", label = "Target info" },
    { key = "incParty",  short = "Party roster", label = "Party roster" },
    { key = "incStatus", short = "Status", label = "Status, pet, deaths",
      tip = "Your level, HP, mana, combat state, pet, and deaths or level ups from the last 15 minutes." },
    { key = "incQuest",  short = "Quest", label = "Active quest" },
}
-- Chat sources: merged into one time-ordered timeline. buffer: the ns.logs
-- buffer it reads; filter: an optional filter in Snapshot.lua; unless: a
-- flag that already includes this source.
ns.CHAT_SOURCES = {
    { key = "incSocial",    buffer = "social", short = "Say / whisper", label = "Say / yell / whispers",
      tip = "Say, yell, emotes and whispers from everyone nearby." },
    { key = "incPartySay",  buffer = "social", short = "Party's say", label = "Party members' say", filter = "partySay", unless = "incSocial",
      tip = "Say, yell and emotes, but only from you and your party members." },
    { key = "incPartyChat", buffer = "party",  short = "Party chat", label = "Party / raid chat" },
    { key = "incNpc",       buffer = "npc",    short = "NPC lines", label = "NPC dialogue" },
    { key = "incLoot",      buffer = "loot",   short = "Loot", label = "Loot (green and up)",
      tip = "Green and better items, your own coin summed into one line. No gray items or roll spam." },
    { key = "incOoc",       buffer = "ooc",    short = "OOC channel", label = "OOC channel" },
    { key = "incWorld",     buffer = "world",  short = "World chat", label = "World channels",
      tip = "General, Trade, LFG and other numbered channels. The OOC channel has its own switch." },
    { key = "incGuild",     buffer = "guild",  short = "Guild chat", label = "Guild & officer chat", tip = "Guild chat and officer chat." },
}
ns.TAB_FLAGS = {}
for _, d in ipairs(ns.TAB_SECTIONS) do table.insert(ns.TAB_FLAGS, d.key) end
for _, d in ipairs(ns.CHAT_SOURCES) do table.insert(ns.TAB_FLAGS, d.key) end

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
    -- (0.6.5: no Target or Status lines by default; Slice Tabs can add them)
    Tab("PARTY", "Party", { incParty = true, incPartySay = true, incPartyChat = true }),
    -- Guild: guild and officer chat
    Tab("GUILD", "Guild", { incGuild = true }),
    Tab("QUEST", "Quest", { incTarget = true, incStatus = true, incQuest = true, incNpc = true }),
    Tab("LOOT", "Loot", { incParty = true, incStatus = true, incLoot = true }),
}

-- =========================================================
-- Full Log groups (0.6.1): each line kind ("category") belongs to one of
-- six groups, and each group has one switch in Options > Recording.
-- Line kinds that are not in any group are never written.
-- =========================================================
ns.LOG_GROUPS = {
    { key = "combat", label = "Fights and kills", cats = { "fights", "fightStreaks", "kills", "aggro", "spells", "cc", "pets" },
      tip = "One line per fight (easy trash fights folded into one), elite and named kills, aggro swaps, big spells, crowd control and pets." },
    { key = "bosses", label = "Bosses and danger", cats = { "bossCasts", "danger" },
      tip = "What bosses cast and at whom, near deaths and saves. Boss pulls, kills and wipes are always kept." },
    { key = "quests", label = "Quests and NPCs", cats = { "quests", "questObjectives", "npcDialogue" },
      tip = "Quests accepted and done, objectives, and what quest givers, bosses and named NPCs say." },
    { key = "travel", label = "Travel and progress", cats = { "levels", "places", "milestones" },
      tip = "Level ups, new places, and milestones: new spells, pets, mounts, achievements and reputation." },
    { key = "loot", label = "Loot and gear", cats = { "loot", "lootSource", "gear" },
      tip = "Green and better items, who got them and where they came from, and the gear you and your party wore on the run." },
    { key = "chat", label = "Group chat", cats = { "chat", "guildmates" },
      tip = "Say, yell, emotes, whispers and group chat, and which party members are your guildmates. Guild and world channels and OOC never go in." },
    -- 0.6.3: what you type with /rp note (or the Note button) during a run
    { key = "notes", label = "Your notes", cats = { "notes" },
      tip = "Your character's thoughts that you add with /rp note or the Note button while a run records." },
}
ns.LOG_CAT_GROUP = {}
for _, g in ipairs(ns.LOG_GROUPS) do
    for _, c in ipairs(g.cats) do ns.LOG_CAT_GROUP[c] = g.key end
end

-- The Full Log's tags, with the meaning the story templates give the AI.
-- The templates' tag list is built from this table (Templates.lua), so a
-- tag added here is explained to the AI too.
ns.LOG_TAGS = {
    { tag = "[FIGHT]", text = "one line per fight: the foes, how long it took, the abilities used (\"used Arcane Shot; Snips: Claw\"), who fled, who took aggro from whom, who got low, who fell, and how it ended." },
    { tag = "[FIGHTS]", text = "a streak of easy fights against the same foe folded into one line (\"14x Windsong Crawler\"): give it a sentence of travel color, not a scene each." },
    { tag = "[KILL]", text = "an elite, rare or named foe defeated. Foes defeated: N in the header counts all foes, trash included." },
    { tag = "[BOSS ENGAGED] [BOSS KILL] [BOSS RESET] [WIPE #N]", text = "boss fights and wipes. The [BOSS KILL] and [BOSS RESET] lines carry the fight itself: how long it lasted, who fell, who was pulled back from the brink, who cried for healing or mana, crowd control on the party, the moves used, and \"won on the 2nd attempt\" after a wipe. Boss yells ([NPC] lines) around them are the boss's own voice." },
    { tag = "[BOSS CAST]", text = "what a boss cast and at whom." },
    { tag = "[SPELL]", text = "a big cooldown or crowd control cast." },
    { tag = "[CC]", text = "mind control, fear, stun, polymorph." },
    { tag = "[AGGRO]", text = "a foe turning on someone else." },
    { tag = "[DANGER] [SAVED] [DEATH] [REZ]", text = "near death, pulled back from the brink (a potion, a shield or another last-ditch move: they were close to dying), a death with what they were fighting, a resurrection." },
    { tag = "[PET] [PET DEATH]", text = "the party's pets. Every pet shows as \"Name (Family)\": \"Snips (Crab)\" means a crab named Snips. Always call the pet by its name and write it as the creature it is (\"Snips the crab\"). \"Crab (Crab)\" is a crab that is simply named Crab." },
    { tag = "[MILESTONE]", text = "a new spell, pet, mount, achievement or reputation standing." },
    { tag = "[QUEST]", text = "quests accepted and completed." },
    { tag = "[QUEST TEXT]", text = "the quest giver's own words (quote them sparingly)." },
    { tag = "[NPC] [NPC Emote]", text = "lines spoken by bosses and named NPCs." },
    { tag = "[LEVEL]", text = "a level up." },
    { tag = "[PLACE]", text = "a new place reached." },
    { tag = "[LOOT]", text = "an item with who got it and where it came from (crafted, from a foe, quest reward, bought, traded, mail, gathered)." },
    { tag = "[HIGHLIGHT]", text = "a moment the player marked: give it a scene." },
    { tag = "[NOTE]", text = "the player's character's own thought or feeling at that moment, typed by the player: their inner voice. Weave it in as what they think or feel right there (never as spoken dialogue), and let it color the scene." },
    { tag = "[SHOT ID]", text = "a screenshot taken at that moment, with its ID (e.g. [SHOT TPX8OK-2]); the \"Screenshots\" list in the header gives every ID and what was happening. Pick only the pictures that fit the story (a few of many is fine, skip the rest) and put each marker on its own line where it fits best, copied exactly with its full ID, e.g. [Shot TPX8OK-2] (each ID once, in story order), plain and outside any color code: close every |c...|r before it. A marker changes nothing else: after it, keep coloring every name exactly as before. RP Chronicler hides the markers in game and the story viewer shows the pictures there." },
    { tag = "[Party] [Say] [Emote] [Whisper]", text = "real chat quotes: weave them in verbatim." },
}

-- Log detail (0.6.1): one picker sets every Full Log limit
ns.LOG_DETAIL = {
    SHORT  = { minFightSec = 8, spellCap = 40,  npcCap = 20,  timelineMax = 250,  shotCap = 20 },
    NORMAL = { minFightSec = 4, spellCap = 120, npcCap = 60,  timelineMax = 500,  shotCap = 40 },
    RICH   = { minFightSec = 2, spellCap = 250, npcCap = 150, timelineMax = 1000, shotCap = 80 },
}

-- [Known Player] blocks: at most this many per copy, notes cut to this length
ns.KNOWN_PLAYER_MAX = 3
ns.KNOWN_NOTE_MAX = 300

-- =========================================================
-- Settings (0.6.1): every saved setting is defined once, here. EnsureDB
-- fills in defaults and clamps values from this list, Options builds its
-- rows from it, and code reads and writes through ns.Get / ns.Set.
-- A setting exists only if it is a privacy or recording choice, players
-- genuinely want different things, or it works around a client problem.
--   bool: default true/false; num: min, max; choice: choices
-- =========================================================
ns.SETTINGS = {
    { key = "rpCopy",            default = true,       label = "RP Copy (live scene copy)" },
    -- 0.6.4: the RP button on the minimap (default) or floating
    { key = "iconMode",          default = "MINIMAP",  choices = { "MINIMAP", "FLOAT" } },
    { key = "quickCtrlC",        default = true,       label = "Ctrl+C copies the scene" },
    { key = "copyMode",          default = "BOX",      choices = { "INSTANT", "BOX" } },
    { key = "messages",          default = 3,          min = 1, max = 10 },
    -- 0.6.4: entering a dungeon or raid asks first (was autoRecord and
    -- promptOnGroup)
    { key = "instanceRecord",    default = "ASK",      choices = { "ASK", "AUTO", "OFF" } },
    -- 0.6.4 (Mor): inspect each party member once while recording, for
    -- the gear they wore (local only, can be turned off)
    { key = "partyGear",         default = true,       label = "Record party gear" },
    { key = "autoShots",         default = "INSTANCE", choices = { "OFF", "INSTANCE", "ALL" } },
    { key = "logDetail",         default = "NORMAL",   choices = { "SHORT", "NORMAL", "RICH" } },
    { key = "knownPlayerBlocks", default = true,       label = "[Known Player] blocks" },
    { key = "autoUpdateKnown",   default = true,       label = "Update companions from chat" },
    { key = "companionMenu",     default = true,       label = "Add as companion (right-click)" },
    { key = "runCompanions",     default = true,       label = "Companions in the Full Log" },
    { key = "rpReplyLength",     default = "SHORT",    choices = { "SHORT", "MEDIUM", "LONG" } },
    -- 0.6.3: Ctrl+C first asks for a one-line instruction for the AI
    { key = "quickNote",         default = false,      label = "Ask for an instruction on Ctrl+C" },
    -- 0.6.3: the 3D character on a story's cover (some clients draw no models)
    { key = "storyCover",        default = true,       label = "Story scenes" },
    -- 0.7.0: people not near you as a likeness (race and outfit) instead of a shadow
    { key = "standIns",          default = true,       label = "Likeness figures" },
    -- 0.6.3: RP Chronicler's own errors are kept in the saved file
    { key = "keepErrors",        default = true,       label = "Keep error reports" },
    -- 0.6.3: send only the version number to your group and guild
    { key = "versionCheck",      default = true,       label = "Update notices" },
    -- 0.7.0: who may offer you a story (Share.lua); you are asked every time
    { key = "storySharing",      default = "FRIENDS",      choices = { "OFF", "FRIENDS", "ANYONE" } },
    -- 0.6.7: the open book's pages: parchment (story colors inked darker
    -- so they read on paper) or night (dark pages, the colors as written)
    { key = "bookPages",         default = "PARCHMENT", choices = { "PARCHMENT", "LIGHT", "NIGHT" } },
    -- 0.6.7: the book opens, turns its pages and closes with short animations
    { key = "bookMotion",        default = true,       label = "Book animations" },
    -- 0.6.8: a dungeon story's own music plays softly while its book is open
    { key = "bookMusic",         default = true,       label = "Dungeon music in the book" },
    -- The viewer tip (0.6.7: one line on the shelf), hidden once you close it
    { key = "exportTip",         default = true },
    -- Not a switch (0.6.3): StoryViewer.html's address, pasted once by you
    -- from the page itself (an addon can't see where the game is installed)
    { key = "viewerPath",        default = "", text = true },
}
ns.SETTING = {}
for _, d in ipairs(ns.SETTINGS) do ns.SETTING[d.key] = d end

-- Settings removed in 0.6.1 (the slim-down). They are cleared once, so
-- anyone who changed them gets the default behavior back.
ns.REMOVED_SETTINGS = {
    "quickCopyKey", "quickCapture", "captureTargetKey", "markMomentKey", "openWindowKey",
    "runStartKey", "runPauseKey", "runEndKey", "instantInCombat", "defaultMessages", "expandMessages",
    "promptOnLogin", "resumeAfterReload", "iconState", "sizeMeter", "debugVerbose", "debugEnabled",
    "recordManualShots", "autoColorStory", "knownPlayerMax", "knownNoteMax", "nearbyChip",
    "exportImageDir", "exportShotsDir", "aiModel", "aiCustomLimit", "summaryStats", "logCats", "limits",
    "autoScreenshots", "worldAutoShots",
    -- 0.6.5: the Full Log shows the log alone and Copy for AI adds the
    -- story rules, so the skill switch and the per-player size went
    "aiHasSkill", "logWarnChars",
}

-- 0.6.5: the size meter's one fixed baseline (fits most free AI chats)
ns.LOG_SIZE_BASELINE = 80000

local function Coerce(d, v)
    if d.text then
        return type(v) == "string" and v:sub(1, 260) or d.default
    elseif d.choices then
        for _, c in ipairs(d.choices) do if c == v then return v end end
        return d.default
    elseif d.min then
        v = tonumber(v)
        if not v then return d.default end
        return math.max(d.min, math.min(d.max, math.floor(v)))
    end
    if v == nil then return d.default end
    return v and true or false
end

function ns.Get(key)
    local d = ns.SETTING[key]
    local v = RPChroniclerDB and RPChroniclerDB[key]
    if v == nil and d then return d.default end
    return v
end

-- Listeners (0.6.1): data code says "something changed", the UI listens,
-- so recorder code never calls the UI itself
ns.listeners = {}
function ns.Listen(what, fn)
    ns.listeners[what] = ns.listeners[what] or {}
    table.insert(ns.listeners[what], fn)
end
function ns.Notify(what, ...)
    for _, fn in ipairs(ns.listeners[what] or {}) do
        local ok, err = pcall(fn, ...)
        if not ok then ns.Debug("error", "listener " .. tostring(what) .. ": " .. tostring(err)) end
    end
end

function ns.Set(key, v)
    local d = ns.SETTING[key]
    if not d or not RPChroniclerDB then return nil end
    v = Coerce(d, v)
    RPChroniclerDB[key] = v
    ns.Notify("setting", key, v)
    return v
end

-- Flips a true/false setting and returns the new value
function ns.Toggle(key)
    return ns.Set(key, not ns.Get(key))
end

-- The whole live RP Copy feature (Copy view, Ctrl+C, the chat it keeps)
function ns.RpCopyOn()
    return ns.Get("rpCopy") ~= false
end

-- Chat types RP Chronicler captures (Options > Privacy and the first-run setup)
ns.CAPTURE_TYPES = {
    { key = "say",     label = "Say, yell and emotes" },
    { key = "whisper", label = "Whispers" },
    { key = "group",   label = "Party and raid chat", tip = "Party, raid and instance chat." },
    { key = "guild",   label = "Guild and officer chat" },
    { key = "world",   label = "World channels", tip = "General, Trade, LFG and the other numbered channels." },
    { key = "npc",     label = "NPC dialogue" },
}

function ns.CaptureOn(key)
    local c = RPChroniclerDB and RPChroniclerDB.capture
    return not c or c[key] ~= false
end

-- The privacy note (first-run setup and Options > Privacy). Plain ASCII.
ns.PRIVACY_TEXT =
    "|cffd8dee9RP Chronicler stores everything on your PC, in your WoW SavedVariables. It has no internet access and never sends your chat, recordings or notes anywhere, and a story only to the friend you share it with. " ..
    "No account, email or real-world personal data is collected.\n" ..
    "RP Copy (one switch) keeps recent chat in memory for the live copy. Recording (only while a run is on) keeps a Full Log with in-character chat (never OOC), the notes you type with /rp note, the gear you wore, your party's race and sex (for their shadows in the story scene) and, unless you turn Record party gear off, the gear they wore (RP Chronicler inspects each member once, out of combat, like the game's own Inspect). " ..
    "Screenshots go to your normal WoW Screenshots folder. Error reports (RP Chronicler's own errors, never chat) are kept in the saved file for bug reports. Each of these can be turned off in Options.\n" ..
    "Update notices: RP Chronicler sends only its version number to your group and guild, through the game, so you hear when a newer one exists. No network, no recorded data. Turn it off in Options > Privacy.\n" ..
    "Story sharing: when you share a story, RP Chronicler sends that one book (its text, title, dates, party names, classes, races, gear and looks, and boss names; never screenshots, chat or notes) to the one friend you name, as addon whispers through the game. A book offered to you (by default only from friends, guild and group) arrives only if you press Accept. Options > Privacy > Story sharing turns it off.\n" ..
    "StoryViewer.html (in the addon folder, and the same page online) runs only in your browser and reads only the files you choose. It uploads nothing.\n" ..
    "Chat and log text only leave your PC if YOU paste them into your own AI tool, and that tool's own privacy terms apply then.\n" ..
    "You can delete everything at any time with |cff69ccf0/rp wipe|cffd8dee9 (or by deleting RPChronicler.lua in your SavedVariables folder).|r"

-- /rp wipe and Options > Privacy: forget everything, then reload
function ns.WipeAllData()
    if InCombatLockdown and InCombatLockdown() then
        print("|cffffd100RP Chronicler|r Leave combat first, then try again.")
        return false
    end
    ns.DropActiveAdventure()
    RPChroniclerDB = {}
    ns._dbChecked = nil
    ns.EnsureDB()
    RPChroniclerDB.wipedAt = time and time() or 0
    print("|cffffd100RP Chronicler|r All RP Chronicler data deleted. Reloading...")
    if ReloadUI then ReloadUI() end
    return true
end

-- Is a Full Log line kind on? Its group's switch decides; kinds in no
-- group (cut in 0.6.1) are never written.
function ns.LogOn(cat)
    local g = ns.LOG_CAT_GROUP[cat]
    if not g then return false end
    local groups = RPChroniclerDB and RPChroniclerDB.logGroups
    return not groups or groups[g] ~= false
end

-- A Full Log limit from the Log detail picker
function ns.Limit(key)
    local preset = ns.LOG_DETAIL[ns.Get("logDetail")] or ns.LOG_DETAIL.NORMAL
    return preset[key] or 0
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

-- SavedVariables replace this once the game loads them; EnsureDB fills
-- in every default from ns.SETTINGS
RPChroniclerDB = RPChroniclerDB or {}

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

-- 0.6.6: a plain true/false, or nil when the client hides the value as
-- secret (comparing a secret boolean throws an error on the modern client).
function ns.SafeBool(val)
    if val == nil or ns.IsSecret(val) then return nil end
    return val and true or false
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

-- A game format string ("%s receives loot: %s.", also numbered as in
-- "%1$s") as an anchored Lua pattern: each %s or %d becomes a capture and
-- every other character matches itself.
function ns.FormatToPattern(fmt)
    if type(fmt) ~= "string" then return nil end
    local out, i, n = { "^" }, 1, #fmt
    while i <= n do
        local c = fmt:sub(i, i)
        local num, conv = fmt:match("^%%(%d*%$?)([sd])", i)
        if conv then
            out[#out + 1] = (conv == "d") and "(%d+)" or "(.+)"
            i = i + #num + 2
        elseif fmt:sub(i, i + 1) == "%%" then
            out[#out + 1] = "%%"
            i = i + 2
        else
            if c:find("^[%^%$%(%)%%%.%[%]%*%+%-%?]") then c = "%" .. c end
            out[#out + 1] = c
            i = i + 1
        end
    end
    out[#out + 1] = "$"
    return table.concat(out)
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


-- 0.7.0 (Mor): a small icon before a name in the party scene: the role
-- they had, else the one role their class can take, else their class's
-- icon, else nothing (never a broken square)
local ROLE_TEX = {
    TANK = "|TInterface\\LFGFrame\\UI-LFG-ICON-PORTRAITROLES:%d:%d:0:0:64:64:0:19:22:41|t",
    HEALER = "|TInterface\\LFGFrame\\UI-LFG-ICON-PORTRAITROLES:%d:%d:0:0:64:64:20:39:1:20|t",
    DAMAGER = "|TInterface\\LFGFrame\\UI-LFG-ICON-PORTRAITROLES:%d:%d:0:0:64:64:20:39:22:41|t",
}
function ns.RoleIconText(p, size)
    size = size or 11
    if type(p) ~= "table" then return "" end
    local role = ROLE_TEX[p.role or ""] and p.role
    local cf = tostring(p.classFile or ""):upper()
    if not role and ns.ClassRoles and cf ~= "" then
        local list = ns.ClassRoles(cf)
        if #list == 1 then role = list[1] end
    end
    if role then return string.format(ROLE_TEX[role], size, size) .. " " end
    local c = type(CLASS_ICON_TCOORDS) == "table" and CLASS_ICON_TCOORDS[cf]
    if c then
        return string.format("|TInterface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES:%d:%d:0:0:256:256:%d:%d:%d:%d|t ",
            size, size, c[1] * 256, c[2] * 256, c[3] * 256, c[4] * 256)
    end
    return ""
end

-- 0.7.0: a name without its realm ("Morai-Realm" -> "Morai")
function ns.ShortName(full)
    return (tostring(full or ""):gsub("%-[^%-]*$", ""))
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

    local isPlayer = UnitIsUnit and ns.SafeBool(UnitIsUnit(unit, "player")) == true
    local guess = (isPlayer and PlayerFormRole()) or AuraRole(unit)
    if not guess and isPlayer then guess = PlayerTalentRole(classFile) end

    -- Behavior: a tank-capable class that keeps holding enemies' attention
    if not guess and CAN_TANK[classFile] then
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
    -- 0.6.1: these buffers only serve the live RP Copy; with it off,
    -- no scene chat is kept at all
    if not ns.RpCopyOn() then return end
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

-- =========================================================
-- Slice tab data (0.6.1): the Slice Tabs page changes tabs only through
-- these. Tabs and everything in them stay fully editable.
-- =========================================================
local function TabIndex(tabId)
    for idx, t in ipairs(RPChroniclerDB.tabs) do
        if t.id == tabId then return idx, t end
    end
    return nil
end

-- A new custom tab (chat and the line to you, like the Chat tab). Returns its id.
function ns.AddTab()
    ns.EnsureDB()
    local t = { id = "CUSTOM_" .. tostring(time()) .. "_" .. tostring(math.random(10, 99)),
        label = "Custom " .. tostring(#RPChroniclerDB.tabs + 1), prefix = ns.DEFAULT_TRIGGER }
    for _, k in ipairs(ns.TAB_FLAGS) do t[k] = false end
    t.incDirect, t.incTarget, t.incSocial = true, true, true
    table.insert(RPChroniclerDB.tabs, t)
    return t.id
end

-- Saves a tab's name, Skill Call and flags. fields: label, prefix, and flag = true/false
function ns.SaveTab(tabId, fields)
    local _, t = TabIndex(tabId)
    if not t then return nil end
    local lbl = ((fields.label or ""):gsub("||", "|")):match("^%s*(.-)%s*$")
    if lbl ~= "" then t.label = lbl end
    if fields.prefix ~= nil then t.prefix = ((fields.prefix or ""):gsub("||", "|")):match("^%s*(.-)%s*$") end
    for _, k in ipairs(ns.TAB_FLAGS) do
        if fields[k] ~= nil then t[k] = fields[k] and true or false end
    end
    return t
end

-- Moves a tab up (-1) or down (+1)
function ns.MoveTab(tabId, delta)
    local idx = TabIndex(tabId)
    local to = idx and idx + delta
    local tabs = RPChroniclerDB.tabs
    if not idx or to < 1 or to > #tabs then return false end
    tabs[idx], tabs[to] = tabs[to], tabs[idx]
    return true
end

-- Deletes a tab (one always stays). Returns the removed tab, or nil and why.
function ns.DeleteTab(tabId)
    local tabs = RPChroniclerDB.tabs
    if #tabs <= 1 then return nil, "Keep at least one slice tab." end
    local idx = TabIndex(tabId)
    if not idx then return nil, "Pick a tab first." end
    local removed = table.remove(tabs, idx)
    if ns.state.activeFilter == removed.id then ns.state.activeFilter = tabs[1].id end
    if RPChroniclerDB.lastSliceId == removed.id then RPChroniclerDB.lastSliceId = tabs[1].id end
    if ns.state.selectedOptionTabId == removed.id then ns.state.selectedOptionTabId = tabs[1].id end
    return removed
end

-- The full check runs once per RPChroniclerDB table (it also runs migrations and
-- rebuilds old Full Logs). Later calls return at once: EnsureDB is called
-- on every copy, and a slow copy was one lead in the 0.4.0 Ctrl+C bug.
function ns.EnsureDB()
    if RPChroniclerDB and ns._dbChecked == RPChroniclerDB then return end
    RPChroniclerDB = RPChroniclerDB or {}
    RPChroniclerDB.players = RPChroniclerDB.players or {}
    RPChroniclerDB.adventures = RPChroniclerDB.adventures or {}
    -- 0.6.1: the slim-down. Merged settings keep your choice; removed
    -- ones are cleared, so their default behavior comes back.
    if not RPChroniclerDB.migratedV061 then
        local db = RPChroniclerDB
        if db.defaultMessages ~= nil and db.messages == nil then db.messages = db.defaultMessages end
        if db.copyMode == "TWOPRESS" then db.copyMode = "INSTANT" end
        if db.autoScreenshots ~= nil and db.autoShots == nil then
            db.autoShots = (db.autoScreenshots and (db.worldAutoShots and "ALL" or "INSTANCE")) or "OFF"
        end
        if type(db.logCats) == "table" and db.logGroups == nil then
            -- a group stays on while any of its old categories was on
            db.logGroups = {}
            for _, g in ipairs(ns.LOG_GROUPS) do
                local on = false
                for _, c in ipairs(g.cats) do if db.logCats[c] ~= false then on = true end end
                db.logGroups[g.key] = on
            end
        end
        pcall(ns.MergeCompanionNotes)
        for _, k in ipairs(ns.REMOVED_SETTINGS) do db[k] = nil end
        db.migratedV061 = true
    end
    -- 0.6.4: "Auto-record dungeons and raids" became Ask / Always / Never.
    -- Off stays off; on becomes Ask. The group-join prompt is gone.
    if not RPChroniclerDB.migratedV064 then
        local db = RPChroniclerDB
        if db.autoRecord == false and db.instanceRecord == nil then db.instanceRecord = "OFF" end
        db.autoRecord, db.promptOnGroup = nil, nil
        db.migratedV064 = true
    end
    if not RPChroniclerDB.migratedV065 then
        RPChroniclerDB.aiHasSkill, RPChroniclerDB.logWarnChars = nil, nil
    end
    -- 0.6.5: the Party tab lost its default Target and Status lines (once;
    -- a player can switch them back on in Slice Tabs)
    if not RPChroniclerDB.migratedV065 then
        for _, t in ipairs(type(RPChroniclerDB.tabs) == "table" and RPChroniclerDB.tabs or {}) do
            if t.id == "PARTY" then t.incTarget, t.incStatus = false, false end
        end
        RPChroniclerDB.migratedV065 = true
    end
    for _, d in ipairs(ns.SETTINGS) do
        RPChroniclerDB[d.key] = Coerce(d, RPChroniclerDB[d.key])
    end
    if not RPChroniclerDB.lastSliceId or RPChroniclerDB.lastSliceId == "" then
        RPChroniclerDB.lastSliceId = "CHAT"
    end

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

    RPChroniclerDB.logGroups = type(RPChroniclerDB.logGroups) == "table" and RPChroniclerDB.logGroups or {}
    for _, g in ipairs(ns.LOG_GROUPS) do
        if RPChroniclerDB.logGroups[g.key] == nil then RPChroniclerDB.logGroups[g.key] = true end
    end
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
        if (not adv.exportText or adv.exportText == "") then
            adv.exportText = ns.BuildAdventureFullLog(adv)
        end
    end

    -- 0.5.0 migrations live with their modules: companions (Companions.lua)
    -- and stories moving out of the recordings (Stories.lua)
    if not RPChroniclerDB.migratedV050 then
        pcall(ns.MigrateCompanions)
        pcall(ns.MigrateStories)
        RPChroniclerDB.migratedV050 = true
    end
    -- 0.6.3: link stories imported without a Run ID to their recording
    if ns.RelinkStories and not ns.storiesRelinked then
        ns.storiesRelinked = true
        pcall(ns.RelinkStories)
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
    ns._dbChecked = RPChroniclerDB
end
