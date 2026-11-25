local ADDON_NAME, ns = ...

-- =========================================================
-- Run report (0.6.1, split out of Adventures.lua): the Summary of a run,
-- its companions' notes and the Full Log for the AI storyteller.
-- =========================================================

-- The Summary differs by run type. Dungeons and raids lead with the
-- roster, bosses and wipes; open world with levels, foes, quests and
-- places. Stats that are zero or empty are hidden. 0.6.1: one fixed
-- Summary (the per-stat switches were removed).
local INSTANCE_ONLY = { bosses = true, wipes = true }
local WORLD_ONLY = { places = true }
local function StatShown(key, adv)
    if INSTANCE_ONLY[key] then return adv.kind ~= "world" end
    if WORLD_ONLY[key] then return adv.kind == "world" end
    return true
end

-- Foe name -> count, most first: "Windsong Crawler x14, Wind Hollow x6"
function ns.GetFoeBreakdown(adv, max)
    local list = {}
    for name, n in pairs((adv and adv.killCounts) or {}) do table.insert(list, { name = name, n = n }) end
    table.sort(list, function(x, y) if x.n ~= y.n then return x.n > y.n end return x.name < y.name end)
    local out, rest = {}, 0
    for i, f in ipairs(list) do
        if i <= (max or 6) then table.insert(out, f.n > 1 and (f.name .. " x" .. f.n) or f.name) else rest = rest + f.n end
    end
    if rest > 0 then table.insert(out, rest .. " more") end
    return table.concat(out, ", ")
end

-- The levels a run covered, or nil: "11 -> 13"
function ns.GetRunLevels(adv)
    local a, b = adv and tonumber(adv.levelStart), adv and tonumber(adv.levelEnd)
    if a and b and b > a then return a .. " -> " .. b, b - a end
    return nil, 0
end

-- The short hero stats for the top bar and the run card, by run type
function ns.GetRunHeroStats(adv)
    local out = {}
    if not adv then return out end
    local function Add(key, label, value)
        if value and value ~= 0 and value ~= "" and StatShown(key, adv) then table.insert(out, { label = label, value = value }) end
    end
    if adv.kind == "world" then
        Add("foes", "Foes", adv.foesDefeated or 0)
        local _, gained = ns.GetRunLevels(adv)
        Add("levels", "Levels", gained)
        Add("quests", "Quests", adv.questsDone or 0)
        Add("deaths", "Deaths", adv.deaths or 0)
        Add("shots", "Shots", #(adv.shots or {}))
    else
        Add("bosses", "Bosses", #(adv.bossKills or {}))
        Add("wipes", "Wipes", adv.wipes or 0)
        Add("deaths", "Deaths", adv.deaths or 0)
        Add("foes", "Foes", adv.foesDefeated or 0)
        Add("shots", "Shots", #(adv.shots or {}))
    end
    return out
end

function ns.BuildAdventureSummary(adv)
    if not adv then
        return "|cff9e9e9eNo adventure selected. Enter a dungeon/raid or click 'Start Recording' above.|r"
    end

    local lines = {}
    local G, T, M = ns.COLORS.gold, ns.COLORS.text, ns.COLORS.muted
    local function Head(label) table.insert(lines, ns.ColorText(label, G)) end
    local function Gap() table.insert(lines, "") end
    local durSec = ns.GetRunDuration(adv)
    table.insert(lines, ns.ColorText("=== " .. (adv.title or "Adventure") .. " ===", G))
    table.insert(lines, string.format("%s %s   |   %s %s   |   %s %s   |   %s",
        ns.ColorText("Zone:", ns.COLORS.header), ns.ColorText(adv.zone or "Unknown", ns.COLORS.location),
        ns.ColorText("Date:", ns.COLORS.header), ns.ColorText(adv.startDate or "-", T),
        ns.ColorText("Duration:", ns.COLORS.header), ns.ColorText(ns.FormatDuration(durSec), T),
        ns.ColorText(ns.GetRunKindLabel(adv), M)))
    Gap()

    local hero = {}
    for _, h in ipairs(ns.GetRunHeroStats(adv)) do
        table.insert(hero, ns.ColorText(h.label .. ":", G) .. " " .. ns.ColorText(tostring(h.value), ns.COLORS.friendly))
    end
    if #hero > 0 then
        table.insert(lines, table.concat(hero, "    "))
        Gap()
    end

    local parts = adv.participants or {}
    if StatShown("roster", adv) and (#parts > 1 or adv.kind ~= "world") then
        Head(adv.kind == "world" and "Companions on the road:" or "Party Roster:")
        if #parts > 0 then
            for _, p in ipairs(parts) do
                local roleTag = ns.GetRoleTag(p.role, true)
                local nameColored = (p.classFile and p.classFile ~= "") and ns.ColorizeClass(p.name, p.classFile) or ns.ColorText(p.name, ns.COLORS.speaker)
                local meta = (p.level and p.level ~= "" and p.class and p.class ~= "") and string.format(" (Lvl %s %s)", p.level, p.class) or ""
                local petStr = p.pet and (" " .. ns.ColorText("with " .. p.pet, ns.COLORS.lootType)) or ""
                local noteStr = (p.note and p.note ~= "") and (" - " .. ns.ColorText(p.note, ns.COLORS.note)) or ""
                table.insert(lines, string.format("  %s %s%s%s%s", roleTag ~= "" and roleTag or "-", nameColored, meta, petStr, noteStr))
            end
        else
            table.insert(lines, "  " .. ns.ColorText("Solo run", M))
        end
        Gap()
    elseif #parts == 1 and parts[1].pet and StatShown("roster", adv) then
        table.insert(lines, ns.ColorText("Pet:", G) .. " " .. ns.ColorText(parts[1].pet, ns.COLORS.lootType))
        Gap()
    end

    local lv = ns.GetRunLevels(adv)
    if lv and StatShown("levels", adv) then
        table.insert(lines, ns.ColorText("Levels gained:", G) .. " " .. ns.ColorText(lv, ns.COLORS.friendly))
    end
    if (adv.deaths or 0) > 0 and adv.kind == "world" and StatShown("deaths", adv) then
        table.insert(lines, ns.ColorText("Deaths:", G) .. " " .. ns.ColorText(tostring(adv.deaths), ns.COLORS.death))
    end
    if ((adv.pvpKills or 0) > 0 or (adv.pvpDeaths or 0) > 0) and StatShown("pvp", adv) then
        table.insert(lines, ns.ColorText("PvP:", G) .. " " .. ns.ColorText(string.format("%d kills, %d deaths", adv.pvpKills or 0, adv.pvpDeaths or 0), T))
    end
    if (adv.questsDone or 0) > 0 and StatShown("quests", adv) then
        table.insert(lines, ns.ColorText("Quests completed:", G) .. " " .. ns.ColorText(tostring(adv.questsDone), ns.COLORS.quest or T))
    end
    if #(adv.shots or {}) > 0 and StatShown("shots", adv) then
        table.insert(lines, ns.ColorText("Screenshots:", G) .. " " .. ns.ColorText(tostring(#adv.shots), T))
    end

    if adv.kind ~= "world" and ((#(adv.bossKills or {}) > 0) or (adv.wipes or 0) > 0 or (adv.deaths or 0) > 0) then
        local bits = {}
        if StatShown("bosses", adv) and #(adv.bossKills or {}) > 0 then table.insert(bits, ns.ColorText("Boss/Elite Kills:", G) .. " " .. ns.ColorText(tostring(#adv.bossKills), ns.COLORS.friendly)) end
        if StatShown("wipes", adv) and (adv.wipes or 0) > 0 then table.insert(bits, ns.ColorText("Wipes:", G) .. " " .. ns.ColorText(tostring(adv.wipes), ns.COLORS.combat)) end
        if StatShown("deaths", adv) and (adv.deaths or 0) > 0 then table.insert(bits, ns.ColorText("Deaths:", G) .. " " .. ns.ColorText(tostring(adv.deaths), ns.COLORS.death)) end
        if #bits > 0 then table.insert(lines, table.concat(bits, "    ")) end
        if StatShown("bosses", adv) then
            for _, b in ipairs(adv.bossKills or {}) do
                local kind = (adv.bossInfo and type(adv.bossInfo[b]) == "table" and adv.bossInfo[b].kind) or "skull"
                local icon = ns.BossIcon and (ns.BossIcon(kind) .. " ") or ""
                table.insert(lines, "  - " .. icon .. ns.ColorText(b, ns.COLORS.boss))
            end
        end
    end
    Gap()

    if (adv.foesDefeated or 0) > 0 and StatShown("foes", adv) then
        Head(string.format("Foes defeated: %d", adv.foesDefeated))
        local fb = ns.GetFoeBreakdown(adv, 8)
        if fb ~= "" then table.insert(lines, "  " .. ns.ColorText(fb, ns.COLORS.hostile or T)) end
        Gap()
    end
    if #(adv.kills or {}) > 0 and StatShown("notable", adv) then
        Head("Named, elite and rare kills:")
        local seen, uniq = {}, {}
        for _, k in ipairs(adv.kills) do if not seen[k] then seen[k] = true table.insert(uniq, k) end end
        table.insert(lines, "  " .. ns.ColorText(table.concat(uniq, ", "), ns.COLORS.elite or T))
        Gap()
    end
    if adv.kind == "world" and #(adv.places or {}) > 1 and StatShown("places", adv) then
        Head("Places visited:")
        table.insert(lines, "  " .. ns.ColorText(table.concat(adv.places, ", "), ns.COLORS.location))
        Gap()
    end
    if #(adv.milestones or {}) > 0 and StatShown("milestones", adv) then
        Head("Milestones:")
        for _, m in ipairs(adv.milestones) do table.insert(lines, "  - " .. ns.ColorText(m, ns.COLORS.npcText)) end
        Gap()
    end
    if #(adv.keyLoot or {}) > 0 and StatShown("loot", adv) then
        Head("Notable Loot:")
        for _, item in ipairs(adv.keyLoot) do
            local disp = type(item) == "table" and (item.colored or item.plain) or tostring(item)
            local looter = (type(item) == "table" and item.looter and item.looter ~= "") and (" -> " .. item.looter) or ""
            local src = (type(item) == "table" and item.source) and (" (" .. item.source .. ")") or ""
            table.insert(lines, "  - " .. disp .. ns.ColorText(looter .. src, M))
        end
        Gap()
    end
    -- Empty highlights show a hint only while the run still records
    local hasHl = #(adv.highlights or {}) > 0
    if StatShown("highlights", adv) and (hasHl or (adv.endDate or "") == "") then
        Head("Bookmarked Highlights:")
        if hasHl then
            for _, h in ipairs(adv.highlights) do table.insert(lines, "  * " .. ns.ColorText(h, ns.COLORS.npcText)) end
        else
            table.insert(lines, "  " .. ns.ColorText("None yet (use '* Mark Moment' or /rp mark during a run)", M))
        end
    end
    while lines[#lines] == "" do table.remove(lines) end
    -- 0.6.3: names fixed by the player (Fix names) read fixed here too
    return ns.ApplyRunFixes(adv, table.concat(lines, "\n"))
end

-- Companions of a run (party members plus, in 0.5.0, companions you
-- chatted with) who have RP notes. The live Companion book wins, even when
-- you cleared a note on purpose; a companion who was deleted or renamed
-- falls back to the copy the run kept. You are never listed.
local function FindCompanionFor(name, cid)
    local players = RPChroniclerDB and RPChroniclerDB.players
    if not players then return nil end
    if cid then
        for k, e in pairs(players) do
            if type(e) == "table" and e.cid == cid then return k, e end
        end
    end
    local key = ns.FindPlayerKey(name, false)
    if key and players[key] then return key, players[key] end
    return nil
end

local function CleanNote(s)
    s = ((s or ""):match("^%s*(.-)%s*$"))
    return (ns.StripColors(s):gsub("[\r\n]+", " "))
end

function ns.GetKnownCompanionNotes(adv)
    local list = {}
    if not adv then return list end
    local selfFull = ns.GetUnitFullName("player")
    local selfShort = ns.StripRealm(UnitName("player"))
    local seen = {}
    local function Add(name, copy)
        local low = (name or ""):lower()
        if name == "" or seen[low] then return end
        if (selfFull and low == selfFull:lower()) or (selfShort and low == selfShort:lower()) then return end
        seen[low] = true
        local key, entry = FindCompanionFor(name, copy.cid)
        if key then
            if seen["key:" .. key] then return end
            seen["key:" .. key] = true
        end
        local src = entry or copy
        if entry and (entry.include == "never") then return end
        local note = CleanNote(src.note)
        local rel = {}
        if CleanNote(src.relationship) ~= "" then table.insert(rel, CleanNote(src.relationship)) end
        if CleanNote(src.tone) ~= "" then table.insert(rel, CleanNote(src.tone)) end
        if note ~= "" or #rel > 0 then
            local max = ns.KNOWN_NOTE_MAX
            local parts = {}
            if #rel > 0 then table.insert(parts, table.concat(rel, ", ")) end
            if note ~= "" then table.insert(parts, ns.ClipCompanionNote(note, max)) end
            local kind = (entry and entry.kind) or copy.kind
            local shown = key or name
            if kind == "npc" then shown = shown .. " (NPC)" elseif kind == "pet" then shown = shown .. " (pet)" end
            table.insert(list, { name = shown, note = table.concat(parts, " - ") })
        end
    end
    for _, p in ipairs(adv.participants or {}) do Add(p.name or "", p) end
    if type(adv.metCompanions) == "table" then
        local keys = {}
        for k in pairs(adv.metCompanions) do table.insert(keys, k) end
        table.sort(keys)
        for _, k in ipairs(keys) do Add(k, adv.metCompanions[k]) end
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

-- 0.6.3: how long the story should be. A long open-world run with many
-- quests must not become ten chapters: the header gives the AI a cap.
function ns.StoryChapterCap(adv)
    if not adv then return nil end
    local mins = ns.GetRunDuration(adv) / 60
    if adv.kind == "world" then
        if mins < 20 then return 3 elseif mins < 45 then return 4 elseif mins < 90 then return 5 end
        return 6
    end
    local bosses = #(adv.bossKills or {})
    if bosses > 6 then return 8 end
    return nil
end

-- 0.6.3: quest objectives of a quest finished later in the run add
-- nothing to its "Completed" line, so the Full Log leaves them out
local function FinishedQuests(tl)
    local done = {}
    for _, line in ipairs(tl) do
        local rest = type(line) == "string" and line:match("%[QUEST%] Completed: (.+)$")
        if rest then
            done[rest] = true
            local short = rest:match("^(.-) for .+$")
            if short then done[short] = true end
        end
    end
    return done
end
local function FoldedObjective(line, done)
    local rest = line:match("%[QUEST%] Objective done: (.+)$")
    if not rest then return false end
    for title in pairs(done) do
        if rest == title or rest:sub(1, #title + 3) == title .. " - " then return true end
    end
    return false
end

-- 0.6.3: the green and better gear the player wore, by name
local function GearLine(adv)
    local names = {}
    for _, g in ipairs(type(adv.gear) == "table" and adv.gear or {}) do
        if type(g) == "table" and g.name and (tonumber(g.q) or 0) >= 2 and #names < 10 then table.insert(names, g.name) end
    end
    return #names > 0 and table.concat(names, ", ") or nil
end

-- First line of the Full Log: the trigger of the matching story skill
function ns.GetStoryTrigger(adv)
    if adv and adv.kind == "world" then return "use " .. ns.STORY_SKILLS.world end
    return "use " .. ns.STORY_SKILLS.dungeon
end

function ns.BuildAdventureFullLog(adv)
    if not adv then
        return "No adventure selected."
    end

    local out = {}
    local durSec = ns.GetRunDuration(adv)
    table.insert(out, ns.GetStoryTrigger(adv))
    table.insert(out, "[ADVENTURE: " .. (adv.title or "Dungeon Run") .. "]")
    -- 0.5.0: open world has no wipes, so its header leaves them out
    local head = string.format("Run type: %s | Zone: %s | Date: %s | Duration: %s",
        ns.GetRunKindLabel(adv), adv.zone or "Unknown", adv.startDate or "-", ns.FormatDuration(durSec))
    if adv.kind ~= "world" then head = head .. string.format(" | Wipes: %d", adv.wipes or 0) end
    head = head .. string.format(" | Deaths: %d", adv.deaths or 0)
    table.insert(out, head)
    -- 0.6.3: the Run ID, which the story repeats on its last line
    local code = ns.RunCode(adv)
    if code then table.insert(out, "Run ID: " .. code) end
    local lvText = ns.GetRunLevels(adv)
    local extra = {}
    if lvText then table.insert(extra, "Levels: " .. lvText) end
    if (adv.questsDone or 0) > 0 then table.insert(extra, "Quests completed: " .. adv.questsDone) end
    if adv.kind == "world" and #(adv.places or {}) > 1 and ns.LogOn("places") then table.insert(extra, "Places: " .. table.concat(adv.places, ", ")) end
    if #extra > 0 then table.insert(out, table.concat(extra, " | ")) end
    if adv.interrupted then
        table.insert(out, "Note: the recording was cut short by a logout or disconnect.")
    end
    local cap = ns.StoryChapterCap(adv)
    if cap then
        table.insert(out, string.format("Story length: %d chapters at most. Group related quests and events into one chapter, sum up routine ones in a line or two, and keep the scenes for the moments that matter.", cap))
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
            local petPart = p.pet and (" - pet: " .. p.pet) or ""
            table.insert(out, string.format("- %s (Lvl %s %s%s)%s%s",
                p.name, (p.level and p.level ~= "") and p.level or "?", (p.class and p.class ~= "") and p.class or "Adventurer", rolePart, guildPart, petPart))
        end
    else
        table.insert(out, "- Solo Adventurer")
    end
    if #mates > 0 then
        table.insert(out, "Guildmates in the party: " .. table.concat(mates, ", "))
    end
    local gear = ns.LogOn("gear") and GearLine(adv)
    if gear then
        table.insert(out, "Wearing (" .. (adv.char or "the player") .. "): " .. gear)
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
        local seenK, notable = {}, {}
        for _, k in ipairs(adv.kills or {}) do if not seenK[k] then seenK[k] = true table.insert(notable, k) end end
        local fb = ns.GetFoeBreakdown(adv, 8)
        local extra = (fb ~= "") and (" (" .. fb .. ")") or ""
        table.insert(out, string.format("Foes defeated: %d%s", adv.foesDefeated, extra))
        if #notable > 0 then table.insert(out, "Notable kills: " .. table.concat(notable, ", ")) end
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
    if adv.highlights and #adv.highlights > 0 then
        table.insert(out, "")
        table.insert(out, "Starred Highlights:")
        for _, h in ipairs(adv.highlights) do
            local cleanH = ns.StripColors(h)
            if not ns.IsOocText(cleanH) then table.insert(out, "- " .. cleanH) end
        end
    end

    -- 0.5.0: numbered screenshots, so the story can place [Shot N] markers.
    -- 0.6.3: each with its run-qualified ID; the AI picks the ones that fit
    if #(adv.shots or {}) > 0 then
        table.insert(out, "")
        table.insert(out, "Screenshots (pick only the ones that fit the story and copy the marker exactly):")
        for i, sh in ipairs(adv.shots) do
            if type(sh) == "table" then
                local stamp = sh.at and date and date("%H:%M:%S", sh.at) or "?"
                table.insert(out, string.format("- [Shot %s] at %s: %s", ns.ShotId(adv, sh, i), stamp, ns.SafeStr(sh.description) or "moment"))
            end
        end
    end

    table.insert(out, "")
    table.insert(out, "Full Adventure Timeline:")
    local tl = adv.fullTimeline or {}
    local keep = ns.Limit("timelineMax")
    local startIdx = math.max(1, #tl - keep + 1)
    local finished = FinishedQuests(tl)
    for i = startIdx, #tl do
        local cleanLine = ns.StripColors(tl[i])
        if cleanLine and FoldedObjective(cleanLine, finished) then cleanLine = nil end
        -- Lines from before 0.6.3 say "[SHOT 2]": give them the full ID
        if cleanLine and code then cleanLine = cleanLine:gsub("%[SHOT (%d+)%]", "[SHOT " .. code .. "-%1]") end
        -- No out-of-character lines (OOC channel, (( )), [OOC], [OOC Note]),
        -- and old [COMBAT START] / [COMBAT END] pairs are left out
        if cleanLine and cleanLine ~= "" and not ns.IsOocText(cleanLine)
            and not cleanLine:find("[COMBAT START]", 1, true) and not cleanLine:find("[COMBAT END]", 1, true) then
            table.insert(out, cleanLine)
        end
    end

    -- 0.6.3: names fixed by the player; the recording itself is unchanged
    return ns.ApplyRunFixes(adv, table.concat(out, "\n"))
end

-- Size of the Full Log, for the size meter: characters and rough tokens
function ns.GetFullLogSize(adv)
    local text = ns.BuildAdventureFullLog(adv) or ""
    local chars = #text
    return chars, math.floor(chars / 4 + 0.5)
end
