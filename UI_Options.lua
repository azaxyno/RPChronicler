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

local STORY_SKILL_TEMPLATE_TEXT = [[---
name: wow-adventure-story
description: Transform World of Warcraft dungeon, raid, or adventure logs from RPCopy into vivid, entertaining narrative stories formatted with WoW color escape codes (|cffRRGGBB...|r) for direct import into the RPCopy addon Story tab. Use when the user pastes an RPCopy adventure log, mentions "adventure story", "dungeon story", "create a story", "use story", or asks to turn a WoW run, party chat, wipes, or gameplay session into a colored in-game chronicle.
---

WOW ADVENTURE STORYTELLER (RPCOPY COLORED CHRONICLE)

Turn exported World of Warcraft adventure logs from RPCopy into rich, entertaining stories formatted with native WoW color escape codes (|cffRRGGBB...|r) so they can be pasted directly into RPCopy's Story tab and read cleanly in-game.

WHEN TO USE

- The user pastes a full or partial RPCopy Adventure Log (containing [ADVENTURE], roster, wipes, boss kills, loot, highlights, or timeline chat).
- The user uses a trigger such as "use story" or "adventure story", or asks to generate a story from a dungeon, raid, or open-world session.

STORYTELLING & ACCURACY PRINCIPLES

1. Stay Faithful to the Log (No Invented Events or Fake Quotes): Build the narrative strictly from the real roster, bosses, HP/mana milestones, wipes, loot, and chat quotes recorded in the timeline. Use dramatic fantasy prose to describe the scenes, but never fabricate bosses, wipes, loot drops, or player quotes that do not appear in the log.
2. Use Timestamps & HP as Hidden Context Only: The [HH:MM:SS] timestamps, [BOSS HP] milestones, [LOW MANA], [DANGER], [AGGRO] lines and combat tags on chat lines (such as [Party | vs Boss 5% HP]) tell you the order and intensity of events, so you can connect when someone panicked, asked for water, or celebrated relative to the fight. Use them only to understand the run. The story itself must NEVER mention clock times, timestamps, durations in minutes or seconds, or any HP, mana or health percentages or numbers. Turn them into in-world prose instead: "at 4% HP" becomes "with the beast staggering on its last breath", "7% mana" becomes "her mana all but spent", "at 20:14" becomes "as they stepped inside".
3. Do Not Limit What Happened: Never compress the run into a dry summary or skip messy moments. Include everything that made the session memorable - wipes, ninja pulls, someone begging for conjured water, OOM panic, clutch heals, dramatic boss kills, and loot drops.
4. Weave Real Quotes and Roles Naturally: Use the roster's classes and roles ([Tank], [Healer], [DPS]) to give each party member a distinct presence, and embed their actual quotes from the timeline verbatim.
5. Use the Known Companions Block: If the log has a "Known companions:" block, each line is the user's own RP note about a party member (who they are, their personality, their history with the user's character). Let those notes shape how that character acts, talks and is described, and reflect any relationship the note mentions. The notes are background, not events: never invent a scene from a note, and never quote a note as dialogue. Party members without a note get no invented backstory.
6. Read the Fight Tags: [SPELL] lines are spells the party cast in combat (a clutch heal, a taunt, a big cooldown). [BOSS CAST] lines are what a boss cast and at whom. [CC] lines mean a party member was mind controlled, feared, stunned or polymorphed. [DANGER] means someone dropped near death, and a [SAVED] line after it means they were pulled back from the brink: give those moments a beat in the story. [PET], [PET DEATH] lines follow the party's pets. Turn these into scenes, but only for what the tags actually say, and never name a spell the log doesn't show.
7. No Icons: Never write |T or |A texture codes. RPCopy adds the boss icons itself.

RPCOPY COLOR PALETTE (|cffRRGGBB...|r)

Color the output using WoW's native hex escape format (|cffRRGGBBtext|r) so the story renders vividly on RPCopy's warm dark-parchment reader:

- Story Title & Chapter Headers: |cffffd100 (Gold)
- Zone, Instance & Scene Subheaders: |cff40e0d0 (Teal) or |cffb39ddb (Lavender)
- Main Narrative Prose: |cffeceff1 (Bright Off-White)
- Player Names (Match WoW Class Color): Warrior |cffC79C6E, Paladin |cffF58CBA, Hunter |cffABD473, Rogue |cffFFF569, Priest |cffC0C0C0 (gray, not white), Death Knight |cffC41F3B, Shaman |cff0070DE, Mage |cff69CCF0, Warlock |cff9482C9, Monk |cff00FF96, Druid |cffFF7D0A, Demon Hunter |cffA330C9, Evoker |cff33937F
- Bosses & Elite Threats: |cffdc143c (Crimson). Never use the Druid orange for a boss.
- Wipes, Deaths & Danger: |cffff5252 (Red)
- Victories, Clutch Saves & Healing: |cff66bb6a (Green)
- Notable Loot Drops: |cffffd700 (Loot Gold) or |cffe066ff (Epic Purple)
- Quoted Party / Say Dialogue: |cffaaaaff (Party Blue) or |cffffffff (Say White)
- Footer Stats & Metadata: |cff9e9e9e (Muted Gray)

FORMATTING RULES FOR WOW COMPATIBILITY

1. Single Copy-Paste Code Block: Output the entire colored story inside one fenced text code block so the user can copy and paste it straight into RPCopy.
2. Close Every Color Tag: Always pair every |cffRRGGBB with a closing |r.
3. Zero Markdown Inside the Code Block: Never use bold or italic asterisks, pound-sign headers, or bullet symbols inside the WoW text block. Use WoW color tags and blank lines for structure.
4. ASCII Characters Only: Use standard ASCII punctuation (- ' " *) inside the code block so WoW fonts never render missing-glyph boxes.
5. No Out-of-Character Numbers: Before you answer, check the story for any timestamp (such as 20:14 or 20:14:07), any percent sign, and any HP or mana number, and rewrite those sentences in-world. The footer may list boss kills, wipes and deaths, but no times or percentages.]]

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

function UI.OpenSkillTemplateModal(mode)
    if mode == "STORY" then
        tpl.title:SetText("|cffffd100Adventure Story Skill Template (press Ctrl+C to copy)|r")
        tpl.sub:SetText("|cffb0bac5Paste this into your AI once to create the 'wow-adventure-story' skill.|r")
        tpl.editBox:SetText(EscapeForEditBox(STORY_SKILL_TEMPLATE_TEXT))
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
    { key = "ADVENTURES", label = "Adventures" },
    { key = "AI", label = "AI Setup" },
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
        { key = "incWorld",     label = "World channels, guild" },
    }
    local SOURCE_TIPS = {
        incStatus = "Your level, HP, mana, combat state, pet, and deaths or level ups from the last 15 minutes.",
        incSocial = "Say, yell, emotes and whispers from everyone nearby.",
        incPartySay = "Say, yell and emotes, but only from you and your party members.",
        incLoot = "Green and better items, your own coin summed into one line. No gray items or roll spam.",
        incWorld = "Trade, General, LFG and guild chat. Off by default so it doesn't crowd out RP.",
    }
    for idx, sDef in ipairs(SOURCE_DEFS) do
        local cb = CreateFrame("CheckButton", "RPCopyOptCB_" .. sDef.key, ed, "UICheckButtonTemplate")
        cb:SetSize(20, 20)
        local col = (idx <= 6) and 0 or 1
        local row = (idx <= 6) and (idx - 1) or (idx - 7)
        cb:SetPoint("TOPLEFT", col * 150, -116 - row * 21)
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
            incLoot = false, incWorld = false,
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

-- ---------------------------------------------------------
-- Adventures
-- ---------------------------------------------------------
do
    local p = NewPage("ADVENTURES", "Adventures")
    local shotsBtn = UI.CreateSleekButton(p, 170, 22, "")
    shotsBtn:SetPoint("TOPLEFT", 0, -28)
    shotsBtn:SetScript("OnClick", function()
        RPCopyDB.autoScreenshots = not RPCopyDB.autoScreenshots
        UI.RefreshOptionsPage()
    end)
    Note(p, "|cff8f9ba8Takes a screenshot on boss kills, level ups and marked moments while a run records.|r", 0, -56)
    Note(p, "|cff8f9ba8Runs start by themselves when you enter a dungeon or raid and end when you leave. Use Start New Run in Adventures (or a keybind) to record anywhere else.|r", 0, -92)
    local storyBtn = UI.CreateSleekButton(p, 150, 24, "Story Template", "gold")
    storyBtn:SetPoint("TOPLEFT", 0, -140)
    storyBtn:SetIcon(UI.ICONS.STORY, 16)
    storyBtn:SetScript("OnClick", function() UI.OpenSkillTemplateModal("STORY") end)
    O.refresh.ADVENTURES = function()
        UI.SetToggleLook(shotsBtn, RPCopyDB.autoScreenshots, "Auto-Screenshots: ON", "Auto-Screenshots: OFF")
    end
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
        "|cffffd100Your storyteller skill (one time)|r\n" ..
        "|cffd8dee91. Click Story Template and copy it.\n" ..
        "2. Paste it into your AI to create the 'wow-adventure-story' skill.\n" ..
        "3. After a run, copy its Full Log, paste it into the AI, and import the story.|r",
        0, -146)
    local storyBtn = UI.CreateSleekButton(p, 150, 24, "Story Template", "gold")
    storyBtn:SetPoint("TOPLEFT", 0, -222)
    storyBtn:SetIcon(UI.ICONS.STORY, 16)
    storyBtn:SetScript("OnClick", function() UI.OpenSkillTemplateModal("STORY") end)
end

UI.SetSectionOnShow("OPTIONS", function()
    UI.EnsureOptions()
    UI.ShowOptionsPage(RPCopyDB.optionsPage)
end)
