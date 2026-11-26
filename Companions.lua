local ADDON_NAME, ns = ...

-- =========================================================
-- Companions (0.5.0): the people (and NPCs and companion pets) you RP with.
-- On Forever only "First Last" together is unique, so every lookup matches
-- the full name. A first name alone counts only when exactly one companion
-- has it, and a saved entry is never renamed behind your back.
--
-- An entry (RPChroniclerDB.players[name]):
--   cid, kind ("player", "npc", "pet"), note ("Who they are"), history
--   ("Our history"), relationship, tone, level, race, class, classFile,
--   guild, chatHistory (last 5), lastSeen, firstMet, firstMetPlace,
--   include ("auto", "always", "never")
-- =========================================================

-- Chat that may become a companion's "Latest Chat": scene chat only.
-- Trade, General, LFG, guild and OOC never do.
local CONVO_CHANNELS = { Say = true, Yell = true, Emote = true, Whisper = true, Party = true, Raid = true, Instance = true }

local function Trim(s) return ((s or ""):match("^%s*(.-)%s*$")) end
local function Low(s) return Trim(s):lower() end

local function FirstName(name)
    return (ns.SplitFullName(name or ""))
end

local function HasLast(name)
    local _, last = ns.SplitFullName(name or "")
    return last ~= ""
end

local function NewCid()
    return tostring(time and time() or 0) .. "_" .. tostring(math.random(1000, 9999))
end

-- Every unit worth looking at for a name: target, mouseover, focus, the
-- party and (in a raid) raid1-40
function ns.ForEachKnownUnit(fn)
    for _, u in ipairs({ "target", "mouseover", "focus", "party1", "party2", "party3", "party4" }) do
        if UnitExists(u) and fn(u) then return u end
    end
    if IsInRaid and IsInRaid() then
        for i = 1, 40 do
            local u = "raid" .. i
            if UnitExists(u) and fn(u) then return u end
        end
    end
    return nil
end

-- Companion key for a name, or nil. Full names match exactly (any case).
-- A first name alone matches only one companion who has it; a full name
-- also finds an old first-name-only entry when that entry is the only one.
function ns.CompanionByName(name)
    local players = RPChroniclerDB and RPChroniclerDB.players
    if type(name) ~= "string" or name == "" or not players then return nil end
    name = ns.StripHonorRank(Trim(name))
    if players[name] then return name end
    local low = name:lower()
    for k in pairs(players) do
        if k:lower() == low then return k end
    end
    local first = FirstName(name):lower()
    if first == "" then return nil end
    local hits, firstOnly = {}, nil
    for k in pairs(players) do
        if FirstName(k):lower() == first then
            table.insert(hits, k)
            if not HasLast(k) then firstOnly = k end
        end
    end
    if #hits ~= 1 then return nil end
    if not HasLast(name) then return hits[1] end
    -- "Bob Stone" finds a saved "Bob" (no last name) only if nobody else is Bob
    return firstOnly
end

-- Old name kept for the rest of the addon; the upgrade flag is ignored:
-- entries are never renamed automatically any more.
function ns.FindPlayerKey(name)
    return ns.CompanionByName(name)
end

-- The full name for a chat author. Chat often gives only a first name, so a
-- visible unit with that first name is used when exactly one has it, then a
-- companion with that first name. Otherwise the name is kept as it is.
function ns.ResolveCanonicalPlayerName(rawName)
    if type(rawName) ~= "string" or rawName == "" then return nil end
    local name = ns.StripHonorRank(Trim(rawName))
    if HasLast(name) then
        return ns.CompanionByName(name) or name
    end
    local low = name:lower()
    local found, count = nil, 0
    local seen = {}
    ns.ForEachKnownUnit(function(u)
        if UnitIsPlayer(u) then
            local short = ns.StripRealm(UnitName(u))
            if short and short:lower() == low then
                local full = ns.GetUnitFullName(u) or short
                if not seen[full:lower()] then
                    seen[full:lower()] = true
                    found, count = full, count + 1
                end
            end
        end
        return false
    end)
    if count == 1 then return ns.CompanionByName(found) or found end
    if count == 0 then
        local key = ns.CompanionByName(name)
        if key then return key end
    end
    return name
end

-- A visible unit for a companion (or any name)
function ns.FindVisibleUnitForPlayer(name)
    if type(name) ~= "string" or name == "" then return nil end
    local low = name:lower()
    local entry = RPChroniclerDB and RPChroniclerDB.players and RPChroniclerDB.players[name]
    local isPlayer = not entry or (entry.kind or "player") == "player"
    local firstOnly = not HasLast(name)
    local byFirst, firstCount = nil, 0
    local exact = ns.ForEachKnownUnit(function(u)
        if isPlayer ~= (UnitIsPlayer(u) and true or false) then return false end
        local full = isPlayer and ns.GetUnitFullName(u) or ns.SafeStr(UnitName(u))
        if full and full:lower() == low then return true end
        if firstOnly and isPlayer then
            local short = ns.StripRealm(UnitName(u))
            if short and short:lower() == low then byFirst, firstCount = u, firstCount + 1 end
        end
        return false
    end)
    if exact then return exact end
    if firstCount == 1 then return byFirst end
    return nil
end

function ns.GetPlayerClassFile(name)
    if not name or name == "" then return nil end
    if UnitExists("player") then
        local me = ns.GetUnitFullName("player")
        local meShort = ns.StripRealm(UnitName("player"))
        if (me and me:lower() == name:lower()) or (meShort and meShort:lower() == name:lower()) then
            local _, cf = UnitClass("player")
            return ns.SafeStr(cf)
        end
    end
    local u = ns.FindVisibleUnitForPlayer(name)
    if u and UnitIsPlayer(u) then
        local _, cf = UnitClass(u)
        cf = ns.SafeStr(cf)
        if cf then return cf end
    end
    local key = ns.CompanionByName(name)
    local e = key and RPChroniclerDB.players[key]
    if type(e) == "table" then return e.classFile or ns.ClassToken(e.class) end
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

-- Level, race, class (and token) and guild of a visible unit. A guild that
-- is not loaded yet reads as nil and never turns into "None" (0.4.0 bug).
function ns.CaptureVisibleUnitFields(unit, entry)
    if not UnitExists(unit) or not entry then return false end
    local lvl = ns.SafeNum(UnitLevel(unit))
    if lvl and lvl > 0 then entry.level = tostring(lvl) end
    if UnitIsPlayer(unit) then
        local r = ns.SafeStr(UnitRace(unit))
        if r and r ~= "" then entry.race = r end
        local c, cf = UnitClass(unit)
        c, cf = ns.SafeStr(c), ns.SafeStr(cf)
        if c and c ~= "" then entry.class = c end
        if cf and cf ~= "" then entry.classFile = cf end
        local g = ns.SafeStr(GetGuildInfo(unit))
        if g and g ~= "" then entry.guild = g end
    else
        -- 0.6.3: pets keep their family (Crab, Wolf ...), NPCs their type
        local t = ns.GetPetSpecies(unit)
        if t and t ~= "" and ((entry.race or "") == "" or entry.kind == "pet") then entry.race = t end
    end
    entry.lastSeen = ns.NowStamp()
    return true
end

local function NewEntry(kind)
    return {
        cid = NewCid(), kind = kind or "player",
        note = "", relationship = "", tone = "",
        level = "", race = "", class = "", classFile = nil, guild = "",
        chatHistory = {}, lastSeen = "", include = "auto",
        firstMet = ns.NowStamp(), firstMetPlace = ns.GetCurrentWhere(),
    }
end
ns.NewCompanionEntry = NewEntry

-- When companions talk, and (0.6.1) when they were last on screen: the
-- time, for the "Nearby companions" chip and the snapshot. Kept for this
-- session only, and only while RP Copy is on.
ns.companionChatAt = {}
ns.companionSeenAt = {}
ns.COMPANION_NOTE_MAX = 2000   -- letters in the one companion note
local SEEN_WINDOW = 300        -- seconds a companion stays "nearby"

-- Notes that a unit on screen (target, mouseover, nameplate) is a companion
function ns.NoteCompanionUnit(unit)
    if not ns.RpCopyOn() or not unit or not UnitExists(unit) then return end
    local key = ns.CompanionByName(ns.UnitCompanionName(unit))
    if key then ns.companionSeenAt[key] = GetTime() end
end

function ns.AppendConvoForPlayer(name, line)
    if not name or name == "" or name == "Unknown" then return end
    local canonical = ns.ResolveCanonicalPlayerName(name) or name
    local selfShort = ns.StripRealm(UnitName("player"))
    local selfFull = ns.GetUnitFullName("player") or selfShort
    if canonical == selfShort or canonical == selfFull then return end
    ns.logs.playerRecentChat[canonical] = ns.logs.playerRecentChat[canonical] or {}
    ns.PushBounded(ns.logs.playerRecentChat[canonical], line, ns.MAX_PLAYER_CHAT)

    local key = ns.CompanionByName(canonical)
    if not key then return end
    ns.companionChatAt[key] = GetTime()
    ns.NoteRunCompanion(key)
    if ns.Get("autoUpdateKnown") then
        local entry = RPChroniclerDB.players[key]
        entry.chatHistory = entry.chatHistory or {}
        ns.PushBounded(entry.chatHistory, line, ns.MAX_PLAYER_CHAT)
        entry.lastSeen = ns.NowStamp()
        local u = ns.FindVisibleUnitForPlayer(key)
        if u then ns.CaptureVisibleUnitFields(u, entry) end
    end
end

function ns.HandleConversationCapture(channelLabel, rawAuthor, cleanMsg, isOutgoingWhisper, whisperRecipient)
    if not CONVO_CHANNELS[channelLabel] then return end
    if ns.IsOocText(cleanMsg) or ns.IsOocText(channelLabel) then return end
    local selfShort = ns.StripRealm(UnitName("player")) or ""
    local selfFull = ns.GetUnitFullName("player") or selfShort
    local author = ns.StripRealm(rawAuthor) or "Unknown"
    local where = ns.GetCurrentWhere()

    if isOutgoingWhisper then
        local recip = ns.ResolveCanonicalPlayerName(ns.StripRealm(whisperRecipient))
        if recip then
            ns.AppendConvoForPlayer(recip, string.format("[Whisper | %s] %s: %s", where, selfFull, cleanMsg))
        end
        return
    end

    local isSelf = author ~= "Unknown" and (author == selfShort or author == selfFull)
    local hasTarget = UnitExists("target") and UnitIsPlayer("target")
    local targetFull = hasTarget and ns.GetUnitFullName("target") or nil
    local targetShort = hasTarget and ns.StripRealm(UnitName("target")) or nil

    if isSelf then
        local done = {}
        if targetFull and targetShort ~= selfShort then
            ns.AppendConvoForPlayer(targetFull, string.format("[%s | %s] %s: %s", channelLabel, where, selfFull, cleanMsg))
            done[targetFull:lower()] = true
        end
        if channelLabel == "Party" or channelLabel == "Instance" or channelLabel == "Raid" then
            ns.ForEachKnownUnit(function(u)
                if u:match("^party") or u:match("^raid") then
                    local full = UnitIsPlayer(u) and ns.GetUnitFullName(u)
                    if full and not done[full:lower()] and full ~= selfFull and ns.CompanionByName(full) then
                        done[full:lower()] = true
                        ns.AppendConvoForPlayer(full, string.format("[%s | %s] %s: %s", channelLabel, where, selfFull, cleanMsg))
                    end
                end
                return false
            end)
        end
        return
    end

    local isWhisper = channelLabel == "Whisper"
    local isTarget = hasTarget and (author == targetShort or author == targetFull)
    local speaker = isTarget and (targetFull or author) or ns.ResolveCanonicalPlayerName(author)
    if isWhisper or isTarget or ns.CompanionByName(speaker) then
        ns.AppendConvoForPlayer(speaker, string.format("[%s | %s] %s: %s", channelLabel, where, speaker, cleanMsg))
    end
end

-- Saves a player, NPC or companion pet. unit is optional (it fills the
-- details and tells the kind). Returns key, isNew.
function ns.SaveOrUpdatePlayer(name, unit)
    ns.EnsureDB()
    if not name or name == "" then return nil, false end
    local kind = "player"
    if unit and UnitExists(unit) and not UnitIsPlayer(unit) then
        local isPet = (UnitIsBattlePetCompanion and ns.SafeBool(UnitIsBattlePetCompanion(unit)) == true)
            or (UnitIsOtherPlayersBattlePet and ns.SafeBool(UnitIsOtherPlayersBattlePet(unit)) == true)
        kind = isPet and "pet" or "npc"
    end
    local canonical = (kind == "player") and ns.ResolveCanonicalPlayerName(name) or name
    local key = ns.CompanionByName(canonical)
    local isNew = key == nil
    key = key or canonical
    local entry = RPChroniclerDB.players[key] or NewEntry(kind)
    local u = unit or ns.FindVisibleUnitForPlayer(key)
    if u then ns.CaptureVisibleUnitFields(u, entry) end
    local buf = ns.logs.playerRecentChat[key] or ns.logs.playerRecentChat[canonical]
    if buf and #buf > 0 then
        entry.chatHistory = {}
        for _, line in ipairs(buf) do ns.PushBounded(entry.chatHistory, line, ns.MAX_PLAYER_CHAT) end
    end
    entry.lastSeen = ns.NowStamp()
    RPChroniclerDB.players[key] = entry
    -- 0.6.1: someone you just added from a unit is around you right now
    if u then ns.companionSeenAt[key] = GetTime() end
    ns.Notify("companionChanged", key)
    return key, isNew
end

-- A companion typed in by hand (Companions view). Returns key, or nil and why.
function ns.CreateCompanion(name, fields)
    ns.EnsureDB()
    name = Trim(name)
    if name == "" then return nil, "Type a name first." end
    for k in pairs(RPChroniclerDB.players) do
        if k:lower() == name:lower() then
            return nil, "A companion named " .. k .. " already exists. Pick them in the list to edit."
        end
    end
    local entry = NewEntry("player")
    RPChroniclerDB.players[name] = entry
    ns.UpdateCompanion(name, fields)
    return name
end

-- Saves the editable fields of a companion (relationship, tone, note)
function ns.UpdateCompanion(key, fields)
    local entry = RPChroniclerDB.players[key]
    if not entry then return false end
    fields = fields or {}
    if fields.relationship then entry.relationship = Trim(fields.relationship) end
    if fields.tone then entry.tone = Trim(fields.tone) end
    if fields.note then entry.note = Trim(fields.note):sub(1, ns.COMPANION_NOTE_MAX) end
    if fields.include then entry.include = fields.include end
    if (entry.lastSeen or "") == "" then entry.lastSeen = ns.NowStamp() end
    local u = ns.FindVisibleUnitForPlayer(key)
    if u then ns.CaptureVisibleUnitFields(u, entry) end
    ns.Notify("companionChanged", key)
    return true
end

function ns.DeleteCompanion(key)
    if not key or not RPChroniclerDB.players[key] then return false end
    RPChroniclerDB.players[key] = nil
    ns.companionSeenAt[key], ns.companionChatAt[key] = nil, nil
    ns.Notify("companionChanged", nil)
    return true
end

-- The companion a unit is (or the name to save it under)
function ns.UnitCompanionName(unit)
    if not UnitExists(unit) then return nil end
    if UnitIsPlayer(unit) then return ns.GetUnitFullName(unit) end
    return ns.SafeStr(UnitName(unit))
end

-- Renames a companion. Refuses a name another companion already has
-- (any case), so a rename never overwrites someone.
function ns.RenameCompanion(oldKey, newName)
    local players = RPChroniclerDB.players
    newName = Trim(newName)
    if newName == "" then return false, "Type a name first." end
    local entry = players[oldKey]
    for k in pairs(players) do
        if k ~= oldKey and k:lower() == newName:lower() then
            return false, "A companion named " .. k .. " already exists."
        end
    end
    if not entry then return false, "Pick a companion first." end
    if oldKey ~= newName then
        players[oldKey] = nil
        players[newName] = entry
        ns.companionSeenAt[newName], ns.companionSeenAt[oldKey] = ns.companionSeenAt[oldKey], nil
        ns.companionChatAt[newName], ns.companionChatAt[oldKey] = ns.companionChatAt[oldKey], nil
    end
    return true, newName
end

-- =========================================================
-- [Known Player] blocks for a snapshot. people: names that are really
-- in the snapshot (target, party, chat authors). A first name in plain
-- text never counts, so "Will", "Grace" or "Storm" in a sentence no
-- longer pull in a companion; a full name in the text still does.
-- =========================================================
local function ClipNote(text, max)
    text = ns.StripColors(text or ""):gsub("[\r\n]+", " ")
    text = Trim(text)
    if max and #text > max then text = text:sub(1, max - 3):gsub("%s+%S*$", "") .. "..." end
    return text
end
ns.ClipCompanionNote = ClipNote

function ns.GetKnownPlayerBlocks(people, bodyText)
    if not ns.Get("knownPlayerBlocks") then return {} end
    local players = RPChroniclerDB.players
    local haystack = ns.StripColors(bodyText or ""):lower()
    local picked, order = {}, {}
    local function Pick(key, rank)
        if key and players[key] and not picked[key] and (players[key].include or "auto") ~= "never" then
            picked[key] = rank
            table.insert(order, key)
        end
    end
    for key, e in pairs(players) do
        if type(e) == "table" and e.include == "always" then Pick(key, 0) end
    end
    for i, name in ipairs(people or {}) do Pick(ns.CompanionByName(name), i) end
    for key in pairs(players) do
        if HasLast(key) and #key >= 5 and haystack:find(key:lower(), 1, true) then Pick(key, 900) end
    end
    table.sort(order, function(a, b)
        if picked[a] ~= picked[b] then return picked[a] < picked[b] end
        return a < b
    end)

    local max, noteMax = ns.KNOWN_PLAYER_MAX, ns.KNOWN_NOTE_MAX
    local blocks = {}
    for _, key in ipairs(order) do
        if #blocks >= max then break end
        local d = players[key]
        local kind = d.kind or "player"
        local label = (kind == "npc" and "[Known NPC:") or (kind == "pet" and "[Known Pet:") or "[Known Player:"
        local cf = d.classFile or ns.ClassToken(d.class)
        local shown = cf and ns.ColorizeClass(key, cf) or ns.ColorText(key, ns.COLORS.speaker)
        if kind == "pet" then shown = ns.ColorText(ns.FormatPet(key, Trim(d.race) ~= "" and Trim(d.race) or nil), ns.COLORS.speaker) end
        local lines = { ns.ColorText(label, ns.COLORS.gold) .. " " .. shown .. ns.ColorText("]", ns.COLORS.gold) }
        local rel = {}
        if Trim(d.relationship) ~= "" then table.insert(rel, Trim(d.relationship)) end
        if Trim(d.tone) ~= "" then table.insert(rel, Trim(d.tone)) end
        if #rel > 0 then
            table.insert(lines, ns.ColorText("Relationship:", ns.COLORS.lootType) .. " " .. ns.ColorText(table.concat(rel, ", "), ns.COLORS.softWhite))
        end
        local who = ClipNote(d.note, noteMax)
        table.insert(lines, ns.ColorText("Who they are:", ns.COLORS.lootType) .. " "
            .. (who ~= "" and ns.ColorText(who, ns.COLORS.softWhite) or ns.ColorText("None", ns.COLORS.muted)))
        -- Skip chat lines the copy already shows, so nothing is pasted twice
        local fresh = {}
        for _, line in ipairs(type(d.chatHistory) == "table" and d.chatHistory or {}) do
            local plainLine = ns.StripColors(line or "")
            local msg = plainLine:match("^%[[^%]]*%]%s*[^:]+:%s*(.+)$") or plainLine
            msg = Trim(msg):lower()
            if msg ~= "" and not haystack:find(msg, 1, true) then table.insert(fresh, line) end
        end
        if #fresh > 0 then
            table.insert(lines, ns.ColorText("Latest Chat:", ns.COLORS.lootType))
            for _, line in ipairs(fresh) do table.insert(lines, ns.ColorText(line, ns.COLORS.text)) end
        end
        table.insert(blocks, table.concat(lines, "\n"))
    end
    return blocks
end

-- Companions around you right now: targeted, in the group, on a
-- nameplate, or seen (target, mouseover, nameplate, just added) or chatting
-- in the last 5 minutes. Returns a list of { key, why }.
function ns.NearbyCompanions()
    local out, seen = {}, {}
    if not ns.RpCopyOn() then return out end
    local function Add(key, why)
        if key and not seen[key] and RPChroniclerDB.players[key] then
            seen[key] = true
            table.insert(out, { key = key, why = why })
        end
    end
    local function UnitKey(u) return ns.CompanionByName(ns.UnitCompanionName(u)) end
    if UnitExists("target") then Add(UnitKey("target"), "targeted") end
    ns.ForEachGroupUnit(function(u)
        if UnitIsPlayer(u) then Add(UnitKey(u), "in your group") end
    end)
    for i = 1, 40 do
        local u = "nameplate" .. i
        if UnitExists(u) then
            local key = UnitKey(u)
            if key then ns.companionSeenAt[key] = GetTime(); Add(key, "nearby") end
        end
    end
    local now = GetTime()
    for key, at in pairs(ns.companionChatAt) do
        if now - at <= SEEN_WINDOW then Add(key, "chatting") end
    end
    for key, at in pairs(ns.companionSeenAt) do
        if now - at <= SEEN_WINDOW then Add(key, "seen nearby") end
    end
    table.sort(out, function(a, b) return a.key < b.key end)
    return out
end

ns.On({ "PLAYER_TARGET_CHANGED", "UPDATE_MOUSEOVER_UNIT", "NAME_PLATE_UNIT_ADDED" }, function(event, unit)
    if event == "PLAYER_TARGET_CHANGED" then unit = "target"
    elseif event == "UPDATE_MOUSEOVER_UNIT" then unit = "mouseover" end
    ns.NoteCompanionUnit(unit)
end)

-- Runs and stories you shared with a companion (by cid, then by name)
function ns.CompanionSharedAdventures(key)
    local e = RPChroniclerDB.players[key]
    if not e then return {} end
    local low = key:lower()
    local function IsThem(p)
        if type(p) ~= "table" then return false end
        if e.cid and p.cid == e.cid then return true end
        return (p.name or ""):lower() == low
    end
    local list, storyByRun = {}, {}
    for _, st in ipairs(RPChroniclerDB.stories or {}) do
        if st.runId then storyByRun[st.runId] = st end
    end
    local function Scan(adv)
        for _, p in ipairs(adv.participants or {}) do
            if IsThem(p) then return true end
        end
        for name, m in pairs(adv.metCompanions or {}) do
            if IsThem(m) or name:lower() == low then return true end
        end
        return false
    end
    local active = ns.GetActiveAdventure()
    if active and Scan(active) then table.insert(list, { title = active.title, date = active.startDate, runId = active.id, live = true }) end
    for _, adv in ipairs(RPChroniclerDB.adventures or {}) do
        if Scan(adv) then
            local st = storyByRun[adv.id]
            table.insert(list, { title = (st and st.book and st.book.title) or adv.title, date = adv.startDate, runId = adv.id, storyId = st and st.id })
        end
    end
    -- Stories whose recording was deleted still remember the party
    for _, st in ipairs(RPChroniclerDB.stories or {}) do
        local m = st -- a story keeps a copy of its run's details
        if not ns.FindAdventure(st.runId) then
            for _, p in ipairs(m.participants or {}) do
                if IsThem(p) then
                    table.insert(list, { title = (st.book and st.book.title) or m.title, date = m.startDate, storyId = st.id })
                    break
                end
            end
        end
    end
    return list
end

-- 0.5.0 migration: ids, class tokens, honor-rank and case duplicates merged
local function MergeInto(dst, src)
    local a, b = Trim(dst.note), Trim(src.note)
    if a == "" then dst.note = b elseif b ~= "" and a ~= b then dst.note = a .. " / " .. b end
    for _, f in ipairs({ "relationship", "tone", "level", "race", "class", "classFile", "guild" }) do
        if (dst[f] or "") == "" and (src[f] or "") ~= "" then dst[f] = src[f] end
    end
    if type(src.chatHistory) == "table" and #src.chatHistory > 0 and #(dst.chatHistory or {}) == 0 then
        dst.chatHistory = src.chatHistory
    end
end

function ns.MigrateCompanions()
    local players = RPChroniclerDB.players
    local keys = {}
    for k in pairs(players) do table.insert(keys, k) end
    table.sort(keys)
    for _, k in ipairs(keys) do
        local e = players[k]
        if type(e) == "table" then
            local base = ns.StripHonorRank(k)
            local target = base
            for other in pairs(players) do
                if other ~= k and other:lower() == base:lower() then target = other end
            end
            if target ~= k then
                if players[target] then MergeInto(players[target], e) else players[target] = e end
                players[k] = nil
            end
        end
    end
    for _, e in pairs(players) do
        if type(e) == "table" then
            e.cid = e.cid or NewCid()
            e.kind = e.kind or "player"
            e.relationship = e.relationship or ""
            e.tone = e.tone or ""
            e.include = e.include or "auto"
            e.classFile = e.classFile or ns.ClassToken(e.class)
            if e.guild == "None" then e.guild = "" end
            e.firstMet = e.firstMet or e.lastSeen or ""
        end
    end
end

-- 0.6.1: one companion note. "Our history" joins the end of "Who they
-- are" (in the Companion book and in the copies runs and stories keep).
local function MergeHistory(e)
    if type(e) ~= "table" or e.history == nil then return end
    local note, hist = Trim(e.note), Trim(e.history)
    if hist ~= "" and note ~= hist then e.note = (note ~= "" and (note .. " ") or "") .. hist end
    e.history = nil
end

function ns.MergeCompanionNotes()
    for _, e in pairs(RPChroniclerDB.players or {}) do MergeHistory(e) end
    local function Run(adv)
        if type(adv) ~= "table" then return end
        for _, p in ipairs(adv.participants or {}) do MergeHistory(p) end
        for _, m in pairs(adv.metCompanions or {}) do MergeHistory(m) end
    end
    for _, adv in ipairs(RPChroniclerDB.adventures or {}) do Run(adv) end
    Run(RPChroniclerDB.activeRun)
    for _, st in ipairs(RPChroniclerDB.stories or {}) do Run(st) end
end

-- =========================================================
-- "Add as RP Chronicler companion" in the game's own unit right-click menus.
-- Only where the modern Menu API exists; Options can hide the entry.
-- =========================================================
do
    local MENUS = { "MENU_UNIT_PLAYER", "MENU_UNIT_PARTY", "MENU_UNIT_RAID_PLAYER", "MENU_UNIT_FRIEND",
        "MENU_UNIT_TARGET", "MENU_UNIT_FOCUS" }
    local function Add(owner, root, ctx)
        if not ns.Get("companionMenu") or type(root) ~= "table" or not root.CreateButton then return end
        local unit = type(ctx) == "table" and ctx.unit or nil
        local name = (unit and ns.UnitCompanionName(unit)) or (type(ctx) == "table" and ns.SafeStr(ctx.name)) or nil
        if not name or name == "" then return end
        pcall(root.CreateDivider, root)
        root:CreateButton("|cffffd100Add as RP Chronicler companion|r", function()
            local key, isNew = ns.SaveOrUpdatePlayer(name, unit)
            if key then
                print("|cffffd100RP Chronicler|r " .. (isNew and "Added companion: " or "Updated companion: ") .. key)
                ns.Notify("companionAdded", key)
            end
        end)
    end
    if Menu and Menu.ModifyMenu then
        for _, tag in ipairs(MENUS) do pcall(Menu.ModifyMenu, tag, Add) end
        ns.companionMenuReady = true
    end
end

-- =========================================================
-- Pets (0.6.3): one format everywhere, "Name (Family)": a crab named
-- Snips reads "Snips (Crab)", a crab still named Crab reads "Crab (Crab)".
-- The family is what the pet is (Crab, Wolf, Imp ...); never a role like
-- "hunter pet".
-- =========================================================
function ns.GetPetSpecies(unit)
    unit = unit or "pet"
    if not UnitExists(unit) then return nil end
    local fam = UnitCreatureFamily and ns.SafeStr(UnitCreatureFamily(unit))
    if fam and fam ~= "" then return fam end
    -- Companion (battle) pets: their species name
    if UnitBattlePetSpeciesID and C_PetJournal and C_PetJournal.GetPetInfoBySpeciesID then
        local ok, sid = pcall(UnitBattlePetSpeciesID, unit)
        sid = ok and ns.SafeNum(sid) or nil
        if sid and sid > 0 then
            local ok2, sname = pcall(C_PetJournal.GetPetInfoBySpeciesID, sid)
            sname = ok2 and ns.SafeStr(sname) or nil
            if sname and sname ~= "" then return sname end
        end
    end
    local ctype = UnitCreatureType and ns.SafeStr(UnitCreatureType(unit))
    if ctype and ctype ~= "" then return ctype end
    return nil
end

-- "Name (Family)" from a name and a family (either may be missing)
function ns.FormatPet(name, family)
    name = (name and name ~= "") and name or family or "Pet"
    if family and family ~= "" then return name .. " (" .. family .. ")" end
    return name
end

-- Plain text (no colors); nil when there is no such unit
function ns.GetPetDescriptor(unit)
    unit = unit or "pet"
    if not UnitExists(unit) then return nil end
    return ns.FormatPet(ns.SafeStr(UnitName(unit)), ns.GetPetSpecies(unit))
end
