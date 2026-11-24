local ADDON_NAME, ns = ...
local UI = ns.UI

-- =========================================================
-- AI skill templates (pasted into Gemini / ChatGPT / Claude once)
-- =========================================================
local RP_SKILL_TEMPLATE_TEXT = [[---
name: <character-name>-rp-<class>
description: Generate short, casual World of Warcraft roleplay responses for <Character Full Name> (<Faction> <Race> <Class>) inspired by <Persona Inspiration>. Use when the user uploads a WoW chat screenshot, mentions "<trigger>" (such as "use <trigger>"), or asks for <Class> RP replies in General, Say, Whisper, or Party chat.
---

WOW RP <FACTION> <RACE> <CLASS> (<PERSONA INSPIRATION> PERSONA)

Generate short, casual in-character English roleplay replies for <Character Full Name>, a <personality summary> <Faction>-aligned <Race> <Class> in World of Warcraft, capturing the voice and quirks of <Persona Inspiration>.

WHEN TO USE

- The user pastes an RPCopy context snapshot starting with "[Skill Call] use <trigger>" (containing [Location], [Target], [S], [G], [P], [W], [Loot], etc.) or uploads a WoW chat screenshot.
- The user mentions the trigger words "<trigger>" or "<surname>" (for example: "use <trigger>", "<trigger> reply").
- The user asks for quick in-character <Class> roleplay responses.

CORE PERSONALITY (5 DISTINCT ANGLES)

1. Signature Quirk / Theatrical Angle:
   - Frames ordinary moments with <Character Full Name>'s signature flair (e.g., dramatic titles, deadpan grand declarations, or noble poise), then drops right back into casual speech.
   - Invents overly dramatic names for ordinary beasts, spells, gear, or low-level mobs.

2. Petty & Witty Banter:
   - Invents grandiose lore excuses to dodge mundane chores, walking, or blame ("my keen senses are currently sealed for greater prey").
   - Turns trivial moments into playful rivalry and gets flustered if treated like a novice.

3. Heart & Everyday Habits:
   - Carries grounded adventurer habits into Azeroth (counting every copper, hating repair/reagent bills, hoarding free food, protecting loot rights).
   - Loyal to <Faction> and teammates, with a soft spot for <favorite thing/creatures>.

4. Class / Companion / Lore Chaos (Option 4):
   - Obsessed with <class-specific gimmick: e.g., taming dangerous elites, forbidden arcane theory, questionable engineering>, giving them ridiculous names, and blaming accidental pulls on <pet/spells/fate>.

5. Unhinged Overkill Mode (Option 5):
   - Over-the-top <Class> mode: eager to solve every minor problem by unloading big AoE/traps/cooldowns on the entire room, then immediately <Feign / Blink / Vanish / bubble> while the party handles the aggro.

CHANNEL CONTEXT & FORMATTING RULES

1. No Channel Prefixes: Never start replies with /1, /p, /s, /w, or /y. Output pure, copy-paste-ready text.
2. Adapt to the Chat Channel Context: Check [G], [P], [S], [W], [Y] tags and tailor RP accordingly.
3. Always Output RP in English: Write all 5 RP chat options in natural, casual lowercase English.
4. Keep It Short: 1-2 short sentences max per option so it fits fast-paced WoW chat.
5. Follow the [Instruction] Line: If the snapshot has an [Instruction] line, it is the user's direction for these replies (tone, focus, who to answer, what to do). Follow it. It is not chat and never something a character said.]]

-- 0.4.0: two story skills share the same reading rules, color palette,
-- header and footer (Story Book parses them), so they are built from parts.
local STORY_SHARED_RULES = [[
READING THE LOG (HIDDEN CONTEXT)

1. Stay Faithful to the Log: build the story only from the real roster, places, foes, bosses, quests, loot, deaths and chat quotes in the log. Use rich fantasy prose for the scenes, but never invent bosses, kills, loot, quests, deaths or player quotes.
2. Header lines: "Run type:" says Dungeon, Raid or Open world adventure. The Roster gives each member's level, class and role ([Tank], [Healer], [DPS]). A member marked "<Guild> (guildmate)" shares the player's guild: treat them as old companions-in-arms of the same guild and mention the shared guild naturally once or twice. "Known companions:" lines are the player's own RP notes: let them shape how that character acts and talks, but never quote a note or invent a scene from it.
3. Timestamps, HP and mana are hidden context: [HH:MM:SS], [BOSS HP], [LOW MANA], [DANGER] and combat tags tell you order and intensity only. The story prose must NEVER mention clock times, durations, or any HP, mana or percent numbers. "at 4% HP" becomes "with the beast staggering on its last breath".
4. Tags and what they mean:
   [FIGHT] one line per fight: the foes, how long it took, who fled, who took aggro from whom, who got low, who fell, and how it ended.
   [KILL] an elite, rare or named foe defeated. Foes defeated: N in the header counts all foes, trash included.
   [BOSS ENGAGED] [BOSS KILL] [BOSS RESET] [WIPE #N] boss fights and wipes. [BOSS CAST] what a boss cast and at whom.
   [SPELL] party spells in combat (pets show as "Name (Owner's pet)"). [CC] mind control, fear, stun, polymorph. [AGGRO] a foe turning on someone else.
   [DANGER] near death, [SAVED] pulled back from the brink, [DEATH] a death with what they were fighting, [REZ] a resurrection.
   [PET] [PET DEATH] the party's pets. [MILESTONE] a new spell, pet, mount, achievement, reputation standing, hearthstone bind or flight path.
   [QUEST] quests accepted and completed, [QUEST TEXT] the quest giver's own words (quote them sparingly).
   [NPC] [NPC Emote] lines spoken by bosses and named NPCs. [LEVEL] a level up. [SKILL] a profession skill-up. [PLACE] a new place reached.
   [ATMOSPHERE] the time of day (dawn, morning, midday, afternoon, dusk, night) and indoors or open sky: use it to set the mood of the scene.
   [LOOT] an item with who got it and where it came from (crafted, from a foe, quest reward, bought, traded, mail, gathered). [HIGHLIGHT] a moment the player marked: give it a scene.
   Chat lines ([Party], [Say], [Emote], [Whisper]) are real quotes: weave them in verbatim.
5. Do not shrink the run into a dry summary. Messy moments (wipes, near deaths, panicked chat, lucky loot) are what make it memorable.
6. No Icons: never write |T or |A texture codes. RPCopy adds boss icons itself.

STORY BOOK HEADER AND FOOTER (REQUIRED, RPCopy reads them)

Line 1: the story title only, in gold, e.g. |cffffd100Shadows Over Pyrewood|r
Line 2: |cff9e9e9e<dungeon, raid or region> | <duration from the log header> | <zone>|r
Line 3: |cff9e9e9eDate: <date from the log header> | Party: <names, comma separated>|r
Then a blank line and the story. Start each chapter with a gold header line: |cffffd100Chapter 1: <chapter name>|r
Last line (footer): |cff9e9e9eBosses: <N> | Wipes: <N> | Deaths: <N>|r
The header and footer are the only place where the duration and the counts may appear.

RPCOPY COLOR PALETTE (|cffRRGGBB...|r)

- Title and chapter headers: |cffffd100 (Gold)
- Places and scene subheaders: |cff40e0d0 (Teal) or |cffb39ddb (Lavender)
- Narrative prose: |cffeceff1 (Bright Off-White)
- Player names in their class color: Warrior |cffC79C6E, Paladin |cffF58CBA, Hunter |cffABD473, Rogue |cffFFF569, Priest |cffC0C0C0 (gray, not white), Death Knight |cffC41F3B, Shaman |cff0070DE, Mage |cff69CCF0, Warlock |cff9482C9, Monk |cff00FF96, Druid |cffFF7D0A, Demon Hunter |cffA330C9, Evoker |cff33937F
- Bosses, elites and named foes: |cffdc143c (Crimson). Never use the Druid orange for a foe.
- Wipes, deaths and danger: |cffff5252 (Red)
- Victories, saves and healing: |cff66bb6a (Green)
- Loot: |cffffd700 (Loot Gold) or |cffe066ff (Epic Purple)
- Quoted dialogue: |cffaaaaff (Party Blue) or |cffffffff (Say White). NPC words: |cfffff0a0 (Pale Yellow)
- Header, footer and metadata: |cff9e9e9e (Muted Gray)

FORMATTING RULES FOR WOW

1. Output the whole colored story inside one fenced text code block, ready to paste into RPCopy (Adventures > Story Book > Import Story).
2. Close every color tag: pair each |cffRRGGBB with a closing |r.
3. No Markdown inside the code block: no asterisks, pound-sign headers or bullet symbols. Use color tags and blank lines.
4. ASCII only inside the code block (- ' " *), so WoW fonts never show missing-glyph boxes.
5. Before you answer, check the story prose for any timestamp, percent sign, or HP or mana number, and rewrite those sentences in-world.]]

local DUNGEON_STORY_TEMPLATE_TEXT = [[---
name: wow-dungeon-raid-story
description: Turn an RPCopy dungeon or raid Full Log into a vivid colored chronicle with one chapter per boss, formatted with WoW color codes (|cffRRGGBB...|r) for RPCopy's Story Book. Use when the user pastes an RPCopy log that starts with "use story" or says "Run type: Dungeon" or "Run type: Raid", or asks for a dungeon or raid story.
---

WOW DUNGEON AND RAID STORYTELLER (RPCOPY STORY BOOK)

Turn an RPCopy dungeon or raid Full Log into an entertaining, faithful group adventure, colored for RPCopy's in-game Story Book.

STRUCTURE

- A short opening chapter: the party gathers at the entrance (use [ATMOSPHERE] and the roster).
- One chapter per boss in the order of [BOSS ENGAGED] / [BOSS KILL] lines, named after the boss or the place. Trash fights between bosses ([FIGHT], [KILL]) belong to the chapter of the boss that follows them.
- Every wipe gets its moment: what went wrong, and how the party came back.
- A closing chapter: the last boss falls, the loot is shared, the party leaves.
- Give every party member a distinct voice and role, from the roster and their real chat quotes.
]] .. STORY_SHARED_RULES

local ADVENTURE_STORY_TEMPLATE_TEXT = [[---
name: wow-open-world-story
description: Turn an RPCopy open-world Full Log (solo or small group questing, travel, gathering, taming) into an introspective colored adventure story, formatted with WoW color codes (|cffRRGGBB...|r) for RPCopy's Story Book. Use when the user pastes an RPCopy log that starts with "use adventure story" or says "Run type: Open world adventure", or asks for an adventure story.
---

WOW OPEN WORLD STORYTELLER (RPCOPY STORY BOOK)

Turn an RPCopy open-world Full Log into a personal, introspective adventure told close to the player's character: what they saw, fought, found and felt on the road.

STRUCTURE

- Chapters follow places and events, not bosses: a new region or subzone ([PLACE]), a quest taken or finished ([QUEST]), a hard fight ([FIGHT] with a near death or a [KILL] of a named foe), a milestone ([LEVEL], [MILESTONE], a new pet or mount).
- Set each scene with the time of day from [ATMOSPHERE] and the place. The character may reflect on the road, their pet, their trade ([SKILL]) and the people they met.
- Quest givers' words ([QUEST TEXT]) and NPC lines may be quoted briefly, in their own voice.
- Ordinary trash fights become a line of travel color, not a scene. Elites, rares and near deaths get the drama.
- If the character travelled with others, give them presence from the roster and real chat quotes. Guildmates are old friends.
- A quiet closing: where the character rests, what they carry, what is still ahead.
]] .. STORY_SHARED_RULES

-- =========================================================
-- Skill template modal (RP persona or adventure story)
-- =========================================================
local tpl = {}
do
    local f = CreateFrame("Frame", "RPCopySkillTemplateFrame", UIParent, UI.BACKDROP)
    f:SetSize(610, 460)
    f:SetPoint("CENTER", UIParent, "CENTER", 20, -20)
    f:SetFrameStrata("FULLSCREEN_DIALOG")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:Hide()
    UI.ApplyDarkGlass(f, 0.05, 0.06, 0.08, 0.97, 0.78, 0.62, 0.28, 0.75)
    tpl.frame = f

    tpl.title = UI.Label(f, "", "GameFontNormal")
    tpl.title:SetPoint("TOPLEFT", 14, -12)
    tpl.sub = UI.Label(f, "", "GameFontHighlightSmall")
    tpl.sub:SetPoint("TOPLEFT", 14, -28)

    local closeX = UI.CreateSleekButton(f, 22, 20, "x", "danger")
    closeX:SetPoint("TOPRIGHT", -8, -8)
    closeX:SetScript("OnClick", function() f:Hide() end)

    local boxBg = CreateFrame("Frame", nil, f, UI.BACKDROP)
    boxBg:SetPoint("TOPLEFT", 14, -48)
    boxBg:SetPoint("BOTTOMRIGHT", -14, 42)
    UI.ApplyPanelLook(boxBg)

    local scroll = CreateFrame("ScrollFrame", "RPCopySkillTemplateScroll", boxBg, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 8, -8)
    scroll:SetPoint("BOTTOMRIGHT", -28, 8)

    local eb = CreateFrame("EditBox", "RPCopySkillTemplateEditBox", scroll)
    eb:SetMultiLine(true)
    eb:SetMaxLetters(0)
    eb:SetFontObject(ChatFontNormal)
    eb:SetWidth(540)
    eb:SetHeight(350)
    eb:SetAutoFocus(true)
    eb:SetScript("OnEscapePressed", function() f:Hide() end)
    scroll:SetScrollChild(eb)
    tpl.editBox = eb

    local hl = UI.CreateSleekButton(f, 120, 22, "Highlight All", "gold")
    hl:SetPoint("BOTTOMLEFT", 14, 12)
    hl:SetScript("OnClick", function()
        eb:SetFocus()
        eb:HighlightText()
    end)

    local closeBtn = UI.CreateSleekButton(f, 90, 22, "Close")
    closeBtn:SetPoint("BOTTOMRIGHT", -14, 12)
    closeBtn:SetScript("OnClick", function() f:Hide() end)
end

-- Escape '|' as '||' so the EditBox shows literal |cffRRGGBB codes instead of
-- rendering them as colors (unclosed codes would otherwise bleed across lines).
local function EscapeForEditBox(text)
    local escaped = (text or ""):gsub("|", "||")
    return escaped
end

-- mode: "STORY" (Dungeon/Raid Story), "ADVENTURE" (Adventure Story) or "RP"
function UI.OpenSkillTemplateModal(mode)
    if mode == "STORY" then
        tpl.title:SetText("|cffffd100Dungeon/Raid Story Template (press Ctrl+C to copy)|r")
        tpl.sub:SetText("|cffb0bac5Paste it into your AI once: one chapter per boss. Full Logs of dungeons and raids start with 'use story'.|r")
        tpl.editBox:SetText(EscapeForEditBox(DUNGEON_STORY_TEMPLATE_TEXT))
    elseif mode == "ADVENTURE" then
        tpl.title:SetText("|cffffd100Adventure Story Template (press Ctrl+C to copy)|r")
        tpl.sub:SetText("|cffb0bac5Paste it into your AI once: open world, solo, by place and event. Those Full Logs start with 'use adventure story'.|r")
        tpl.editBox:SetText(EscapeForEditBox(ADVENTURE_STORY_TEMPLATE_TEXT))
    else
        tpl.title:SetText("|cffffd100Character RP Skill Template (press Ctrl+C to copy)|r")
        tpl.sub:SetText("|cffb0bac5Paste this into your AI to build a character skill that matches your Skill Call.|r")
        tpl.editBox:SetText(EscapeForEditBox(RP_SKILL_TEMPLATE_TEXT))
    end
    tpl.frame:Show()
    tpl.editBox:SetFocus()
    tpl.editBox:HighlightText()
end

-- =========================================================
-- Key capture overlay (captures the next key combo, no protected calls)
-- =========================================================
local kc = {}
do
    local f = CreateFrame("Frame", "RPCopyKeyCaptureModal", UIParent, UI.BACKDROP)
    f:SetSize(360, 82)
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 40)
    f:SetFrameStrata("FULLSCREEN_DIALOG")
    -- OnKeyDown only fires on keyboard-enabled frames. The frame is hidden
    -- except while capturing, so it never swallows keys during normal play.
    if f.EnableKeyboard then f:EnableKeyboard(true) end
    f:Hide()
    UI.ApplyDarkGlass(f, 0.06, 0.08, 0.12, 0.98, 0.90, 0.73, 0.32, 0.95)
    kc.frame = f

    kc.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    kc.title:SetPoint("TOP", 0, -14)
    local sub = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    sub:SetPoint("TOP", 0, -36)
    sub:SetText("|cffb0bac5(e.g. SHIFT-C, ALT-R, CTRL-F5)  -  Press ESC to cancel|r")

    local IGNORED = { LSHIFT = true, RSHIFT = true, LCTRL = true, RCTRL = true, LALT = true, RALT = true, UNKNOWN = true }

    f:SetScript("OnKeyDown", function(self, key)
        if key == "ESCAPE" then
            self:Hide()
            UI.SetStatus("Keybind change cancelled.")
            return
        end
        if IGNORED[key] then return end
        local combo = ""
        if IsAltKeyDown() then combo = combo .. "ALT-" end
        if IsControlKeyDown() then combo = combo .. "CTRL-" end
        if IsShiftKeyDown() then combo = combo .. "SHIFT-" end
        combo = combo .. key

        UI.EnsureOptions()
        -- One key per action: free the combo from any other RPCopy action
        for _, field in ipairs({ "quickCopyKey", "captureTargetKey", "markMomentKey", "openWindowKey", "runStartKey", "runPauseKey", "runEndKey" }) do
            if field ~= self.targetField and RPCopyDB[field] == combo then
                RPCopyDB[field] = (field == "quickCopyKey") and "CTRL-C" or ""
            end
        end
        RPCopyDB[self.targetField] = combo
        self:Hide()
        if UI.UpdateOverrideBindings then UI.UpdateOverrideBindings() end
        if UI.RefreshOptionsPage then UI.RefreshOptionsPage() end
        UI.SetStatus("Bound " .. (self.actionLabel or "shortcut") .. " to " .. combo .. ".", "good")
    end)
end

local function StartKeyBindCapture(dbField, actionLabel)
    if InCombatLockdown and InCombatLockdown() then
        UI.SetStatus("Keybinds can't change during combat.", "error")
        return
    end
    kc.frame.targetField = dbField
    kc.frame.actionLabel = actionLabel
    kc.title:SetText("|cffffd100Press a key for " .. actionLabel .. "...|r")
    kc.frame:Show()
end

-- =========================================================
-- OPTIONS section (behind the gear): pages listed down the left
-- =========================================================
local view = UI.NewSection("OPTIONS", "Options", "Settings are saved for your whole account.")
local O = { pages = {}, navButtons = {}, refresh = {} }
UI.options = O

O.nav = CreateFrame("Frame", nil, view, UI.BACKDROP)
O.nav:SetWidth(112)
O.nav:SetPoint("TOPLEFT", 0, 0)
O.nav:SetPoint("BOTTOMLEFT", 0, 0)
UI.ApplyPanelLook(O.nav)

O.area = CreateFrame("Frame", nil, view)
O.area:SetPoint("TOPLEFT", O.nav, "TOPRIGHT", 12, -4)
O.area:SetPoint("BOTTOMRIGHT", 0, 0)

local PAGE_ORDER = {
    { key = "GENERAL", label = "General" },
    { key = "KEYS", label = "Keybinds" },
    { key = "SLICES", label = "Slice Tabs" },
    { key = "ADVENTURES", label = "Recording" },
    { key = "FULLLOG", label = "Full Log" },
    { key = "AI", label = "AI Setup" },
    { key = "DEBUG", label = "Debug" },
}

local function NewPage(key, heading)
    local p = CreateFrame("Frame", nil, O.area)
    p:SetAllPoints(O.area)
    p:Hide()
    local h = UI.Label(p, "|cffffd100" .. heading .. "|r", "GameFontNormal")
    h:SetPoint("TOPLEFT", 0, 0)
    O.pages[key] = p
    return p
end

local function Note(parent, text, x, y, width)
    local fs = UI.Label(parent, text, "GameFontHighlightSmall")
    fs:SetPoint("TOPLEFT", x, y)
    if width then
        fs:SetWidth(width)
    else
        fs:SetPoint("RIGHT", parent, "RIGHT", 0, 0)
    end
    fs:SetJustifyV("TOP")
    return fs
end

function UI.RefreshOptionsPage()
    UI.EnsureOptions()
    local fn = O.refresh[RPCopyDB.optionsPage]
    if fn then fn() end
end

function UI.ShowOptionsPage(key)
    UI.EnsureOptions()
    if not O.pages[key] then key = "GENERAL" end
    RPCopyDB.optionsPage = key
    for k, p in pairs(O.pages) do
        if k == key then p:Show() else p:Hide() end
    end
    for k, b in pairs(O.navButtons) do
        if k == key then b:LockHighlight() else b:UnlockHighlight() end
    end
    UI.RefreshOptionsPage()
end

function UI.OpenOptionsPage(key)
    UI.EnsureOptions()
    RPCopyDB.optionsPage = key
    if UI.frame:IsShown() then
        UI.ShowSection("OPTIONS")
    else
        RPCopy_Open("", "OPTIONS")
    end
end

for i, item in ipairs(PAGE_ORDER) do
    local b = UI.CreateSleekButton(O.nav, 98, 24, item.label)
    b:SetPoint("TOP", 0, -8 - (i - 1) * 28)
    b:SetScript("OnClick", function() UI.ShowOptionsPage(item.key) end)
    O.navButtons[item.key] = b
end

-- ---------------------------------------------------------
-- General
-- ---------------------------------------------------------
do
    local p = NewPage("GENERAL", "General")

    UI.Label(p, "Messages per log in a snapshot:"):SetPoint("TOPLEFT", 0, -28)
    UI.Label(p, "Normal"):SetPoint("TOPLEFT", 0, -50)
    local defInput = CreateFrame("EditBox", "RPCopyOptDefMsgs", p, "InputBoxTemplate")
    defInput:SetSize(30, 20)
    defInput:SetPoint("TOPLEFT", 52, -46)
    defInput:SetAutoFocus(false)
    defInput:SetNumeric(true)
    UI.Label(p, "Expanded"):SetPoint("TOPLEFT", 96, -50)
    local expInput = CreateFrame("EditBox", "RPCopyOptExpMsgs", p, "InputBoxTemplate")
    expInput:SetSize(30, 20)
    expInput:SetPoint("TOPLEFT", 160, -46)
    expInput:SetAutoFocus(false)
    expInput:SetNumeric(true)
    local saveBtn = UI.CreateSleekButton(p, 56, 20, "Save")
    saveBtn:SetPoint("TOPLEFT", 204, -46)
    saveBtn:SetScript("OnClick", function()
        local d = math.max(1, math.min(10, tonumber(defInput:GetText()) or 3))
        local e = math.max(1, math.min(20, tonumber(expInput:GetText()) or 6))
        RPCopyDB.defaultMessages, RPCopyDB.expandMessages = d, e
        defInput:SetText(tostring(d))
        expInput:SetText(tostring(e))
        defInput:ClearFocus()
        expInput:ClearFocus()
        UI.SetStatus(string.format("Saved: %d normal, %d expanded.", d, e), "good")
    end)

    local autoBtn = UI.CreateSleekButton(p, 190, 22, "")
    autoBtn:SetPoint("TOPLEFT", 0, -84)
    autoBtn:SetScript("OnClick", function()
        RPCopyDB.autoUpdateKnown = not RPCopyDB.autoUpdateKnown
        UI.RefreshOptionsPage()
    end)
    Note(p, "|cff8f9ba8Refresh a saved companion's level, guild and latest chat whenever you see or hear them. Your notes are never touched.|r", 0, -110)

    local resetWinBtn = UI.CreateSleekButton(p, 190, 22, "Reset Window Size & Place")
    resetWinBtn:SetPoint("TOPLEFT", 0, -150)
    resetWinBtn:SetScript("OnClick", function() UI.ResetWindow() end)

    local clearBtn = UI.CreateSleekButton(p, 190, 22, "Clear Session Logs", "danger")
    clearBtn:SetPoint("TOPLEFT", 0, -182)
    clearBtn:SetScript("OnClick", function(self)
        if not self.armedAt or GetTime() - self.armedAt > 4 then
            self.armedAt = GetTime()
            self:SetText("|cffff6b6bClick again to clear|r")
            return
        end
        self.armedAt = nil
        self:SetText("Clear Session Logs")
        ns.ClearSessionLogs()
        UI.SetStatus("Session logs cleared (companions and adventures are kept).", "good")
    end)
    Note(p, "|cff8f9ba8Empties the chat, party, loot and combat lines used by snapshots. Companions and adventures stay. Also /rp clear.|r", 0, -208)

    local about = Note(p, "", 0, -260)
    O.refresh.GENERAL = function()
        defInput:SetText(tostring(RPCopyDB.defaultMessages or 3))
        expInput:SetText(tostring(RPCopyDB.expandMessages or 6))
        UI.SetToggleLook(autoBtn, RPCopyDB.autoUpdateKnown, "Companion Auto-Update: ON", "Companion Auto-Update: OFF")
        clearBtn.armedAt = nil
        clearBtn:SetText("Clear Session Logs")
        about:SetText("|cff8f9ba8RPCopy v" .. (ns.VERSION or "?") .. " (alpha). Type /rp for the window, /rp help is in the README.|r")
    end
end

-- ---------------------------------------------------------
-- Keybinds
-- ---------------------------------------------------------
do
    local p = NewPage("KEYS", "Keybinds")
    local rows = {}

    local function KeyRow(y, label, field, toggleField, defaultKey)
        UI.Label(p, label):SetPoint("TOPLEFT", 0, y - 4)
        local keyBtn = UI.CreateSleekButton(p, 96, 20, "", "gold")
        keyBtn:SetPoint("TOPLEFT", 190, y)
        if keyBtn.RegisterForClicks then keyBtn:RegisterForClicks("LeftButtonUp", "RightButtonUp") end
        keyBtn:SetScript("OnClick", function(_, button)
            if button == "RightButton" then
                if defaultKey then
                    RPCopyDB[field] = defaultKey
                else
                    RPCopyDB[field] = ""
                end
                if UI.UpdateOverrideBindings then UI.UpdateOverrideBindings() end
                UI.RefreshOptionsPage()
                UI.SetStatus(label .. (defaultKey and (" reset to " .. defaultKey) or " key cleared") .. ".")
                return
            end
            StartKeyBindCapture(field, label)
        end)
        local row = { keyBtn = keyBtn, field = field }
        if toggleField then
            local t = UI.CreateSleekButton(p, 48, 20, "")
            t:SetPoint("TOPLEFT", 140, y)
            t:SetScript("OnClick", function()
                RPCopyDB[toggleField] = not RPCopyDB[toggleField]
                if not RPCopyDB[toggleField] and UI.DisarmCtrlCopy then UI.DisarmCtrlCopy() end
                if UI.UpdateOverrideBindings then UI.UpdateOverrideBindings() end
                UI.RefreshOptionsPage()
            end)
            row.toggle, row.toggleField = t, toggleField
        end
        table.insert(rows, row)
    end

    KeyRow(-28, "Quick Copy", "quickCopyKey", "quickCtrlC", "CTRL-C")

    UI.Label(p, "Ctrl+C copy style"):SetPoint("TOPLEFT", 0, -60)
    local modeBtn = UI.CreateSleekButton(p, 146, 20, "", "tool")
    modeBtn:SetPoint("TOPLEFT", 140, -56)
    modeBtn:SetScript("OnClick", function()
        RPCopyDB.copyMode = (RPCopyDB.copyMode == "INSTANT") and "TWOPRESS" or "INSTANT"
        if UI.DisarmCtrlCopy then UI.DisarmCtrlCopy() end
        UI.RefreshOptionsPage()
    end)
    local combatBtn = UI.CreateSleekButton(p, 140, 20, "")
    combatBtn:SetPoint("TOPLEFT", 292, -56)
    combatBtn.tipTitle = "|cffffd100Instant in combat|r"
    combatBtn.tipText = "OFF: in combat Ctrl+C is two-press, so Ctrl keybinds always work mid-fight."
    combatBtn:SetScript("OnClick", function()
        RPCopyDB.instantInCombat = not RPCopyDB.instantInCombat
        UI.RefreshOptionsPage()
    end)
    local modeNote = Note(p, "", 0, -80)

    KeyRow(-120, "Capture Target", "captureTargetKey", "quickCapture", "SHIFT-C")
    KeyRow(-146, "Mark Moment", "markMomentKey")
    KeyRow(-172, "Open / Close Window", "openWindowKey")
    KeyRow(-198, "Start Recording", "runStartKey")
    KeyRow(-224, "Pause / Resume Recording", "runPauseKey")
    KeyRow(-250, "End Recording", "runEndKey")

    Note(p, "|cff8f9ba8Left-click a key to change it, right-click to clear it. These actions are also listed in the game's Key Bindings under AddOns > RPCopy.|r", 0, -282)

    local resetBtn = UI.CreateSleekButton(p, 110, 22, "Reset All Keys", "danger")
    resetBtn:SetPoint("TOPLEFT", 0, -322)
    resetBtn:SetScript("OnClick", function()
        RPCopyDB.quickCtrlC, RPCopyDB.quickCopyKey = true, "CTRL-C"
        RPCopyDB.quickCapture, RPCopyDB.captureTargetKey = true, "SHIFT-C"
        RPCopyDB.copyMode, RPCopyDB.instantInCombat = "INSTANT", false
        for _, f in ipairs({ "markMomentKey", "openWindowKey", "runStartKey", "runPauseKey", "runEndKey" }) do
            RPCopyDB[f] = ""
        end
        if UI.UpdateOverrideBindings then UI.UpdateOverrideBindings() end
        UI.RefreshOptionsPage()
        UI.SetStatus("Keys reset: Ctrl+C copies, Shift+C captures, the rest are unbound.", "good")
    end)

    O.refresh.KEYS = function()
        for _, r in ipairs(rows) do
            local k = RPCopyDB[r.field] or ""
            r.keyBtn:SetText(k ~= "" and ("|cffffd100" .. k .. "|r") or "|cff9aa5b4Set Key|r")
            if r.toggle then UI.SetToggleLook(r.toggle, RPCopyDB[r.toggleField], "ON", "OFF") end
        end
        local isCtrlC = RPCopyDB.quickCopyKey == "CTRL-C"
        if RPCopyDB.copyMode == "INSTANT" then
            modeBtn:SetText("|cffc2d8ffInstant (hold Ctrl)|r")
        else
            modeBtn:SetText("|cffc2d8ffTwo-press|r")
        end
        UI.SetToggleLook(combatBtn, RPCopyDB.instantInCombat, "Instant in combat: ON", "Instant in combat: OFF")
        if not isCtrlC then
            modeNote:SetText("|cff8f9ba8Your Quick Copy key arms the copy; then press Ctrl+C to copy. Copy style only applies to CTRL-C.|r")
        elseif RPCopyDB.copyMode == "INSTANT" then
            modeNote:SetText("|cff8f9ba8Instant: hold Ctrl a moment, press C, done. Quick Ctrl+key combos still reach your keybinds. A very fast Ctrl+C asks for a second press.|r")
        else
            modeNote:SetText("|cff8f9ba8Two-press: Ctrl+C gets the snapshot ready, Ctrl+C again copies it. All other Ctrl keybinds always work.|r")
        end
    end
end

-- ---------------------------------------------------------
-- Slice tabs
-- ---------------------------------------------------------
do
    local p = NewPage("SLICES", "Slice Tabs")
    local S = { rows = {}, checks = {} }

    local list = CreateFrame("Frame", nil, p, UI.BACKDROP)
    list:SetWidth(132)
    list:SetPoint("TOPLEFT", 0, -24)
    list:SetPoint("BOTTOMLEFT", 0, 28)
    UI.ApplyPanelLook(list)

    local addBtn = UI.CreateSleekButton(p, 64, 22, "+ New", "gold")
    addBtn:SetPoint("BOTTOMLEFT", 0, 2)
    local resetBtn = UI.CreateSleekButton(p, 64, 22, "Reset", "danger")
    resetBtn:SetPoint("LEFT", addBtn, "RIGHT", 4, 0)
    resetBtn.tipTitle = "|cffff6b6bReset Tabs|r"
    resetBtn.tipText = "Click twice to restore the default slice tabs."

    local scroll = CreateFrame("ScrollFrame", "RPCopyOptListScroll", list, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 6, -6)
    scroll:SetPoint("BOTTOMRIGHT", -26, 6)
    local child = CreateFrame("Frame", nil, scroll)
    child:SetSize(98, 10)
    scroll:SetScrollChild(child)

    local ed = CreateFrame("Frame", nil, p)
    ed:SetPoint("TOPLEFT", list, "TOPRIGHT", 10, 0)
    ed:SetPoint("BOTTOMRIGHT", 0, 0)

    UI.Label(ed, "Tab name:"):SetPoint("TOPLEFT", 0, -2)
    S.name = CreateFrame("EditBox", "RPCopyOptTabName", ed, "InputBoxTemplate")
    S.name:SetSize(130, 20)
    S.name:SetPoint("TOPLEFT", 6, -16)
    S.name:SetAutoFocus(false)
    S.up = UI.CreateSleekButton(ed, 40, 20, "Up")
    S.up:SetPoint("TOPRIGHT", -44, -16)
    S.down = UI.CreateSleekButton(ed, 40, 20, "Down")
    S.down:SetPoint("TOPRIGHT", 0, -16)

    UI.Label(ed, "Skill Call (line 1, calls your AI skill):"):SetPoint("TOPLEFT", 0, -42)
    S.prefix = CreateFrame("EditBox", "RPCopyOptTabPrefix", ed, "InputBoxTemplate")
    S.prefix:SetHeight(20)
    S.prefix:SetPoint("TOPLEFT", 6, -56)
    S.prefix:SetPoint("TOPRIGHT", -2, -56)
    S.prefix:SetAutoFocus(false)
    Note(ed, "|cff8f9ba8e.g. |cff69ccf0use aloria|cff8f9ba8. Clear it to copy raw data only.|r", 0, -80)

    UI.Label(ed, "Included in this slice:"):SetPoint("TOPLEFT", 0, -100)
    local SOURCE_DEFS = {
        { key = "incDirect",    label = "Last whisper / say to you" },
        { key = "incTarget",    label = "Target info" },
        { key = "incParty",     label = "Party roster" },
        { key = "incStatus",    label = "Status, pet, deaths" },
        { key = "incQuest",     label = "Active quest" },
        { key = "incSocial",    label = "Say / yell / whispers" },
        { key = "incPartySay",  label = "Party members' say" },
        { key = "incPartyChat", label = "Party / raid chat" },
        { key = "incNpc",       label = "NPC dialogue" },
        { key = "incLoot",      label = "Loot (green and up)" },
        { key = "incOoc",       label = "OOC channel" },
        { key = "incWorld",     label = "World channels" },
        { key = "incGuild",     label = "Guild & officer chat" },
    }
    local SOURCE_TIPS = {
        incStatus = "Your level, HP, mana, combat state, pet, and deaths or level ups from the last 15 minutes.",
        incSocial = "Say, yell, emotes and whispers from everyone nearby.",
        incPartySay = "Say, yell and emotes, but only from you and your party members.",
        incLoot = "Green and better items, your own coin summed into one line. No gray items or roll spam.",
        incWorld = "General, Trade, LFG and other numbered channels. The OOC channel has its own switch.",
        incGuild = "Guild chat and officer chat.",
    }
    for idx, sDef in ipairs(SOURCE_DEFS) do
        local cb = CreateFrame("CheckButton", "RPCopyOptCB_" .. sDef.key, ed, "UICheckButtonTemplate")
        cb:SetSize(20, 20)
        local col = (idx <= 7) and 0 or 1
        local row = (idx <= 7) and (idx - 1) or (idx - 8)
        cb:SetPoint("TOPLEFT", col * 150, -116 - row * 20)
        local lbl = cb:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        lbl:SetPoint("LEFT", cb, "RIGHT", 2, 0)
        lbl:SetText(sDef.label)
        if SOURCE_TIPS[sDef.key] then
            cb.tipTitle, cb.tipText = sDef.label, SOURCE_TIPS[sDef.key]
            cb:SetScript("OnEnter", function(self)
                if not GameTooltip then return end
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetText(self.tipTitle, 1, 0.82, 0)
                GameTooltip:AddLine(self.tipText, 0.85, 0.85, 0.85, true)
                GameTooltip:Show()
            end)
            cb:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
        end
        S.checks[sDef.key] = cb
    end

    S.save = UI.CreateSleekButton(ed, 96, 22, "Save Tab", "gold")
    S.save:SetPoint("BOTTOMLEFT", 0, 2)
    S.del = UI.CreateSleekButton(ed, 88, 22, "Delete Tab", "danger")
    S.del:SetPoint("BOTTOMRIGHT", 0, 2)

    local function Selected()
        for idx, t in ipairs(RPCopyDB.tabs) do
            if t.id == ns.state.selectedOptionTabId then return t, idx end
        end
        ns.state.selectedOptionTabId = RPCopyDB.tabs[1].id
        return RPCopyDB.tabs[1], 1
    end

    local function Changed()
        if UI.RebuildSliceTabs then UI.RebuildSliceTabs() end
        UI.RefreshOptionsPage()
    end

    O.refresh.SLICES = function()
        local sel = Selected()
        S.name:SetText(sel.label or "")
        S.prefix:SetText(sel.prefix or "")
        for _, sDef in ipairs(SOURCE_DEFS) do
            S.checks[sDef.key]:SetChecked(sel[sDef.key] and true or false)
        end
        S.del.armedAt = nil
        S.del:SetText("Delete Tab")
        resetBtn.armedAt = nil
        resetBtn:SetText("Reset")
        for _, rb in ipairs(S.rows) do rb:Hide() end
        for idx, t in ipairs(RPCopyDB.tabs) do
            local rb = S.rows[idx]
            if not rb then
                rb = UI.CreateSleekButton(child, 96, 22, "")
                S.rows[idx] = rb
            end
            rb:SetPoint("TOPLEFT", 0, -(idx - 1) * 24)
            rb:SetText(t.label)
            if t.id == sel.id then rb:LockHighlight() else rb:UnlockHighlight() end
            rb:SetScript("OnClick", function()
                ns.state.selectedOptionTabId = t.id
                UI.RefreshOptionsPage()
            end)
            rb:Show()
        end
        child:SetHeight(math.max(10, #RPCopyDB.tabs * 24))
    end

    S.save:SetScript("OnClick", function()
        local t = Selected()
        local lbl = (S.name:GetText() or ""):match("^%s*(.-)%s*$")
        if lbl ~= "" then t.label = lbl end
        t.prefix = ((S.prefix:GetText() or ""):gsub("||", "|")):match("^%s*(.-)%s*$")
        for _, sDef in ipairs(SOURCE_DEFS) do
            t[sDef.key] = S.checks[sDef.key]:GetChecked() and true or false
        end
        S.name:ClearFocus()
        S.prefix:ClearFocus()
        Changed()
        UI.SetStatus("Saved slice tab '" .. t.label .. "'.", "good")
    end)

    addBtn:SetScript("OnClick", function()
        local newId = "CUSTOM_" .. tostring(time()) .. "_" .. tostring(math.random(10, 99))
        table.insert(RPCopyDB.tabs, {
            id = newId, label = "Custom " .. tostring(#RPCopyDB.tabs + 1), prefix = ns.DEFAULT_TRIGGER,
            incDirect = true, incTarget = true, incParty = false, incStatus = false, incQuest = false,
            incSocial = true, incPartySay = false, incOoc = false, incPartyChat = false, incNpc = false,
            incLoot = false, incWorld = false, incGuild = false,
        })
        ns.state.selectedOptionTabId = newId
        Changed()
        UI.SetStatus("New tab added. Set it up and click Save Tab.", "good")
    end)

    resetBtn:SetScript("OnClick", function(self)
        if not self.armedAt or GetTime() - self.armedAt > 4 then
            self.armedAt = GetTime()
            self:SetText("|cffff6b6bSure?|r")
            return
        end
        ns.ResetDefaultTabs()
        Changed()
        UI.SetStatus("Slice tabs reset to the defaults.", "good")
    end)

    S.up:SetScript("OnClick", function()
        local _, idx = Selected()
        if idx > 1 then
            RPCopyDB.tabs[idx], RPCopyDB.tabs[idx - 1] = RPCopyDB.tabs[idx - 1], RPCopyDB.tabs[idx]
            Changed()
        end
    end)

    S.down:SetScript("OnClick", function()
        local _, idx = Selected()
        if idx < #RPCopyDB.tabs then
            RPCopyDB.tabs[idx], RPCopyDB.tabs[idx + 1] = RPCopyDB.tabs[idx + 1], RPCopyDB.tabs[idx]
            Changed()
        end
    end)

    S.del:SetScript("OnClick", function(self)
        if #RPCopyDB.tabs <= 1 then
            UI.SetStatus("Keep at least one slice tab.", "error")
            return
        end
        if not self.armedAt or GetTime() - self.armedAt > 4 then
            self.armedAt = GetTime()
            self:SetText("|cffff6b6bSure?|r")
            return
        end
        local _, idx = Selected()
        local removed = table.remove(RPCopyDB.tabs, idx)
        ns.state.selectedOptionTabId = RPCopyDB.tabs[1].id
        if ns.state.activeFilter == removed.id then ns.state.activeFilter = RPCopyDB.tabs[1].id end
        if RPCopyDB.lastSliceId == removed.id then RPCopyDB.lastSliceId = RPCopyDB.tabs[1].id end
        Changed()
        UI.SetStatus("Deleted slice tab '" .. (removed.label or "") .. "'.", "good")
    end)

    p:SetScript("OnHide", function()
        S.name:ClearFocus()
        S.prefix:ClearFocus()
    end)
end

-- A list of ON/OFF buttons bound to RPCopyDB fields
local function ToggleRows(p, y, defs)
    local rows = {}
    for i, d in ipairs(defs) do
        local b = UI.CreateSleekButton(p, 230, 20, "")
        b:SetPoint("TOPLEFT", 0, y - (i - 1) * 24)
        b.tipTitle, b.tipText = "|cffffd100" .. d.label .. "|r", d.tip
        b:SetScript("OnClick", function()
            if d.invert then
                RPCopyDB[d.field] = (RPCopyDB[d.field] == false)
            else
                RPCopyDB[d.field] = not RPCopyDB[d.field]
            end
            if d.after then pcall(d.after) end
            UI.RefreshOptionsPage()
        end)
        rows[i] = { btn = b, def = d }
    end
    return function()
        for _, r in ipairs(rows) do
            local on = RPCopyDB[r.def.field]
            if r.def.invert then on = (on ~= false) end
            UI.SetToggleLook(r.btn, on and true or false, r.def.label .. ": ON", r.def.label .. ": OFF")
        end
    end
end

-- ---------------------------------------------------------
-- Recording
-- ---------------------------------------------------------
do
    local p = NewPage("ADVENTURES", "Recording")
    local refreshToggles = ToggleRows(p, -26, {
        { field = "autoRecord", invert = true, label = "Auto-record dungeons and raids",
          tip = "ON: a run starts by itself when you enter a dungeon or raid and ends when you leave. OFF: you start every run yourself." },
        { field = "promptOnGroup", invert = true, label = "Ask to record on group join",
          tip = "In the open world, joining a group asks 'Start recording?'." },
        { field = "promptOnLogin", label = "Ask to record on login",
          tip = "Asks 'Start recording?' a few seconds after you log in (solo, outside instances)." },
        { field = "resumeAfterReload", invert = true, label = "Keep recording after /reload",
          tip = "ON: a /reload or a short disconnect (under 2 minutes) continues the run. Longer breaks always save the run as interrupted and offer to resume it." },
        { field = "iconState", invert = true, label = "Recording colors on the RP icon",
          tip = "The floating RP icon turns red while recording and dims while paused.",
          after = function() if UI.RefreshRecordIcon then UI.RefreshRecordIcon() end end },
        { field = "autoScreenshots", label = "Auto-screenshots",
          tip = "Takes a screenshot on boss kills, level ups and marked moments while a run records." },
    })
    local status = Note(p, "", 0, -180)
    Note(p, "|cff8f9ba8Open-world runs: click Start Recording in Adventures, use the RP icon's right-click menu, or a keybind. A run cut short by a logout or disconnect is saved as interrupted, never lost.|r", 0, -206)
    local dBtn = UI.CreateSleekButton(p, 160, 24, "Dungeon/Raid Template", "gold")
    dBtn:SetPoint("TOPLEFT", 0, -254)
    dBtn:SetIcon(UI.ICONS.STORY, 16)
    dBtn:SetScript("OnClick", function() UI.OpenSkillTemplateModal("STORY") end)
    local aBtn = UI.CreateSleekButton(p, 150, 24, "Adventure Template", "gold")
    aBtn:SetPoint("LEFT", dBtn, "RIGHT", 6, 0)
    aBtn:SetIcon(UI.ICONS.STORY, 16)
    aBtn:SetScript("OnClick", function() UI.OpenSkillTemplateModal("ADVENTURE") end)
    O.refresh.ADVENTURES = function()
        refreshToggles()
        status:SetText(RPCopyDB.autoRecord ~= false
            and "|cff5cb85cDungeons and raids record by themselves.|r"
            or "|cffffb74dAuto-record is off: start dungeon and raid runs yourself.|r")
    end
end

-- ---------------------------------------------------------
-- Full Log: categories, limits, AI picker, size meter
-- ---------------------------------------------------------
do
    local p = NewPage("FULLLOG", "Full Log")
    Note(p, "|cff8f9ba8What goes into a run's Full Log. Off means RPCopy stops writing those lines (already recorded lines stay). OOC chat is never kept.|r", 0, -20)
    local CAT_TIPS = {
        fights = "One [FIGHT] line per fight: foes, length, flee, aggro swaps, who got low, outcome.",
        kills = "[KILL] lines for elites, rares and named foes, and the Foes defeated count.",
        chat = "Say, yell, emote, whisper and group chat. Guild and world channels never go in.",
        npcDialogue = "Boss and named NPC lines, and the quest giver's words. Throttled and capped.",
        lootSource = "Where an item came from: crafted, from a foe, quest reward, bought, traded, mail, gathered.",
        atmosphere = "Time of day and indoors / open sky at the start and on zone changes.",
        milestones = "New spells, pets, mounts, achievements, reputation, hearthstone bind, flight paths.",
    }
    local checks = {}
    local half = math.ceil(#ns.LOG_CATEGORIES / 2)
    for i, c in ipairs(ns.LOG_CATEGORIES) do
        local cb = CreateFrame("CheckButton", "RPCopyOptLog_" .. c.key, p, "UICheckButtonTemplate")
        cb:SetSize(18, 18)
        local col = (i <= half) and 0 or 1
        local row = (i <= half) and (i - 1) or (i - half - 1)
        cb:SetPoint("TOPLEFT", col * 210, -48 - row * 18)
        local lbl = cb:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        lbl:SetPoint("LEFT", cb, "RIGHT", 2, 0)
        lbl:SetText(c.label)
        cb:SetScript("OnClick", function(self)
            RPCopyDB.logCats[c.key] = self:GetChecked() and true or false
        end)
        if CAT_TIPS[c.key] then
            cb:SetScript("OnEnter", function(self) UI.Tooltip(self, "|cffffd100" .. c.label .. "|r", CAT_TIPS[c.key]) end)
            cb:SetScript("OnLeave", UI.HideTooltip)
        end
        checks[c.key] = cb
    end

    local y = -56 - half * 18
    local inputs = {}
    for i, d in ipairs(ns.LOG_LIMITS) do
        local col = (i - 1) % 2
        local row = math.floor((i - 1) / 2)
        local lbl = UI.Label(p, d.label, "GameFontHighlightSmall")
        lbl:SetPoint("TOPLEFT", col * 210, y - row * 24 - 4)
        local eb = CreateFrame("EditBox", "RPCopyOptLimit_" .. d.key, p, "InputBoxTemplate")
        eb:SetSize(40, 20)
        eb:SetPoint("TOPLEFT", col * 210 + 160, y - row * 24)
        eb:SetAutoFocus(false)
        eb:SetNumeric(true)
        eb:SetMaxLetters(4)
        local function Commit(self)
            local v = tonumber(self:GetText() or "") or d.default
            RPCopyDB.limits[d.key] = math.max(d.min, math.min(d.max, math.floor(v)))
            self:SetText(tostring(RPCopyDB.limits[d.key]))
            self:ClearFocus()
        end
        eb:SetScript("OnEnterPressed", Commit)
        eb:SetScript("OnEditFocusLost", Commit)
        eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
        eb:SetScript("OnEnter", function(self) UI.Tooltip(self, "|cffffd100" .. d.label .. "|r", string.format("From %d to %d. Default %d. Press Enter to save.", d.min, d.max, d.default)) end)
        eb:SetScript("OnLeave", UI.HideTooltip)
        inputs[d.key] = eb
    end

    y = y - math.ceil(#ns.LOG_LIMITS / 2) * 24 - 10
    UI.Label(p, "|cffffd100Your AI|r (sets the size meter)", "GameFontHighlightSmall"):SetPoint("TOPLEFT", 0, y - 4)
    local prev = UI.CreateSleekButton(p, 22, 20, "<")
    prev:SetPoint("TOPLEFT", 170, y)
    local aiLbl = UI.CreateSleekButton(p, 120, 20, "", "tool")
    aiLbl:SetPoint("LEFT", prev, "RIGHT", 4, 0)
    local nextB = UI.CreateSleekButton(p, 22, 20, ">")
    nextB:SetPoint("LEFT", aiLbl, "RIGHT", 4, 0)
    local function Step(delta)
        local idx = 1
        for i, m in ipairs(ns.AI_MODELS) do if m.key == RPCopyDB.aiModel then idx = i end end
        idx = ((idx - 1 + delta) % #ns.AI_MODELS) + 1
        RPCopyDB.aiModel = ns.AI_MODELS[idx].key
        UI.RefreshOptionsPage()
    end
    prev:SetScript("OnClick", function() Step(-1) end)
    nextB:SetScript("OnClick", function() Step(1) end)
    aiLbl:SetScript("OnClick", function() Step(1) end)
    aiLbl.tipTitle = "|cffffd100Your AI|r"
    aiLbl.tipText = "Free plans take shorter pastes than paid ones. See the README's Requirements section."

    local customLbl = UI.Label(p, "Custom limit (chars)", "GameFontHighlightSmall")
    customLbl:SetPoint("TOPLEFT", 0, y - 30)
    local customEb = CreateFrame("EditBox", "RPCopyOptAiCustom", p, "InputBoxTemplate")
    customEb:SetSize(64, 20)
    customEb:SetPoint("TOPLEFT", 176, y - 26)
    customEb:SetAutoFocus(false)
    customEb:SetNumeric(true)
    customEb:SetMaxLetters(7)
    local function CommitCustom(self)
        local v = tonumber(self:GetText() or "") or 40000
        RPCopyDB.aiCustomLimit = math.max(2000, math.min(2000000, math.floor(v)))
        self:SetText(tostring(RPCopyDB.aiCustomLimit))
        self:ClearFocus()
    end
    customEb:SetScript("OnEnterPressed", CommitCustom)
    customEb:SetScript("OnEditFocusLost", CommitCustom)
    customEb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

    local meterBtn = UI.CreateSleekButton(p, 170, 20, "")
    meterBtn:SetPoint("TOPLEFT", 260, y - 26)
    meterBtn.tipTitle = "|cffffd100Size meter|r"
    meterBtn.tipText = "Shows how big a Full Log is for your AI, with a warning when it is too long."
    meterBtn:SetScript("OnClick", function()
        RPCopyDB.sizeMeter = (RPCopyDB.sizeMeter == false)
        UI.RefreshOptionsPage()
    end)

    local resetBtn = UI.CreateSleekButton(p, 130, 20, "Reset Full Log", "danger")
    resetBtn:SetPoint("TOPLEFT", 0, y - 56)
    resetBtn.tipTitle = "|cffff6b6bReset Full Log settings|r"
    resetBtn.tipText = "Click twice: every category on, limits back to their defaults."
    resetBtn:SetScript("OnClick", function(self)
        if not self.armedAt or GetTime() - self.armedAt > 4 then
            self.armedAt = GetTime()
            self:SetText("|cffff6b6bSure?|r")
            return
        end
        self.armedAt = nil
        for _, c in ipairs(ns.LOG_CATEGORIES) do RPCopyDB.logCats[c.key] = true end
        for _, d in ipairs(ns.LOG_LIMITS) do RPCopyDB.limits[d.key] = d.default end
        UI.RefreshOptionsPage()
        UI.SetStatus("Full Log settings reset.", "good")
    end)

    O.refresh.FULLLOG = function()
        ns.EnsureDB()
        for key, cb in pairs(checks) do cb:SetChecked(RPCopyDB.logCats[key] ~= false) end
        for key, eb in pairs(inputs) do eb:SetText(tostring(ns.Limit(key))) end
        local _, label = ns.GetAiLimit()
        aiLbl:SetText(label)
        customEb:SetText(tostring(RPCopyDB.aiCustomLimit or 40000))
        if RPCopyDB.aiModel == "CUSTOM" then
            customEb:Show(); customLbl:Show()
        else
            customEb:Hide(); customLbl:Hide()
        end
        UI.SetToggleLook(meterBtn, RPCopyDB.sizeMeter ~= false, "Size meter: ON", "Size meter: OFF")
        resetBtn.armedAt = nil
        resetBtn:SetText("Reset Full Log")
    end
    p:SetScript("OnHide", function()
        for _, eb in pairs(inputs) do eb:ClearFocus() end
        customEb:ClearFocus()
    end)
end

-- ---------------------------------------------------------
-- AI setup
-- ---------------------------------------------------------
do
    local p = NewPage("AI", "AI Setup")
    Note(p,
        "|cffffd100Your character skill (one time)|r\n" ..
        "|cffd8dee91. Click RP Template and copy it with Ctrl+C.\n" ..
        "2. Paste it into your AI (Gemini, ChatGPT, Claude) and fill in your character.\n" ..
        "3. Use the skill's trigger (like |cff69ccf0use aloria|cffd8dee9) as the Skill Call in Slice Tabs.|r",
        0, -28)
    local rpBtn = UI.CreateSleekButton(p, 150, 24, "RP Template", "gold")
    rpBtn:SetPoint("TOPLEFT", 0, -104)
    rpBtn:SetIcon(UI.ICONS.COPY, 16)
    rpBtn:SetScript("OnClick", function() UI.OpenSkillTemplateModal("RP") end)

    Note(p,
        "|cffffd100Your storyteller skills (one time each)|r\n" ..
        "|cffd8dee91. Copy a story template and paste it into your AI to make the skill.\n" ..
        "   |cffffd100Dungeon/Raid Story|cffd8dee9: one chapter per boss (logs start with 'use story').\n" ..
        "   |cffffd100Adventure Story|cffd8dee9: open world, by place and event ('use adventure story').\n" ..
        "2. After a run, copy its Full Log, paste it into the AI, and import the story into the Story Book.\n" ..
        "|cff9aa5b4Which AI and which plan? See the README's Requirements section.|r",
        0, -146)
    local dBtn = UI.CreateSleekButton(p, 160, 24, "Dungeon/Raid Template", "gold")
    dBtn:SetPoint("TOPLEFT", 0, -246)
    dBtn:SetIcon(UI.ICONS.STORY, 16)
    dBtn:SetScript("OnClick", function() UI.OpenSkillTemplateModal("STORY") end)
    local aBtn = UI.CreateSleekButton(p, 150, 24, "Adventure Template", "gold")
    aBtn:SetPoint("LEFT", dBtn, "RIGHT", 6, 0)
    aBtn:SetIcon(UI.ICONS.STORY, 16)
    aBtn:SetScript("OnClick", function() UI.OpenSkillTemplateModal("ADVENTURE") end)
end

-- ---------------------------------------------------------
-- Debug
-- ---------------------------------------------------------
do
    local p = NewPage("DEBUG", "Debug")
    Note(p,
        "|cffd8dee9RPCopy keeps a small debug log (about 200 lines): its own Lua errors, blocked actions, and when runs start, pause, end or get a story. It never stores chat.\n\n" ..
        "Found a bug? Click |cffffd100Copy Debug Report|cffd8dee9 (or type |cff69ccf0/rp debug|cffd8dee9), press Ctrl+C, and paste it into your report. See 'Reporting bugs' in the README.|r",
        0, -28)
    local verbose = ToggleRows(p, -120, {
        { field = "debugVerbose", label = "Verbose debug log",
          tip = "Also logs extra detail. Leave it off unless you are chasing a bug." },
    })
    local reportBtn = UI.CreateSleekButton(p, 150, 24, "Copy Debug Report", "gold")
    reportBtn:SetPoint("TOPLEFT", 0, -156)
    reportBtn:SetScript("OnClick", function() SlashCmdList["RPCOPY"]("debug") end)
    local clearBtn = UI.CreateSleekButton(p, 120, 24, "Clear Debug Log", "danger")
    clearBtn:SetPoint("LEFT", reportBtn, "RIGHT", 6, 0)
    clearBtn:SetScript("OnClick", function()
        RPCopyDB.debugLog = {}
        UI.SetStatus("Debug log cleared.", "good")
        UI.RefreshOptionsPage()
    end)
    local count = Note(p, "", 0, -192)
    O.refresh.DEBUG = function()
        verbose()
        count:SetText(string.format("|cff8f9ba8%d lines in the debug log.|r", #(RPCopyDB.debugLog or {})))
    end
end

UI.SetSectionOnShow("OPTIONS", function()
    UI.EnsureOptions()
    UI.ShowOptionsPage(RPCopyDB.optionsPage)
end)
