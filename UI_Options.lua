local ADDON_NAME, ns = ...
local UI = ns.UI

-- =========================================================
-- AI skill templates (pasted into Gemini / ChatGPT / Claude once)
-- =========================================================
-- 0.5.0: a shorter, chat-sized persona template. <REPLY_LENGTH> is filled
-- in from Options > AI Setup (short, medium or long).
local RP_SKILL_TEMPLATE_TEXT = [[---
name: <character-name>-rp-<class>
description: Generate short, lively World of Warcraft: Forever roleplay responses for a <gender> <Faction> <Race> <Class> (<Character Full Name>) inspired by <Persona Inspiration>. Use when the user pastes an RPCopy snapshot or a WoW chat screenshot for <First Name>, mentions <trigger> or <surname> (such as "use <trigger>"), or asks for <Class> RP replies in General, Guild, Say, Party or Whisper chat.
---

STARTER TEMPLATE: personalize it. Replace every <...> field, and make it yours: personality, backstory, voice, quirks, the 5 moods and how your character talks. The more of your character is in here, the better the replies. Delete this paragraph when you are done.

WOW FOREVER RP: <FACTION> <RACE> <CLASS> (<CHARACTER FULL NAME>)

Generate 5 short, natural, in-character English chat replies for <Character Full Name>, a <three or four personality words> <Faction> <Race> <Class> in World of Warcraft: Forever, inspired by <Persona Inspiration>.

WHEN TO USE

- The user pastes an RPCopy snapshot that starts with "[Skill Call] use <trigger>" (with [Location], [Target], [Status], chat lines and maybe [Known Player] blocks), or uploads a WoW chat screenshot for <First Name>.
- The user includes triggers like "use <trigger>", "<trigger>" or "<surname>".
- The user asks for quick in-character <Class> responses in any WoW chat channel.

VOICE AND PERSONALITY

<First Name> feels alive because <she/he/they> actually reacts to what people are saying in chat instead of reciting catchphrases. <Describe the core of the voice in one or two sentences: the kind of humor, the attitude, what flips their mood.>

- React to the room first: engage directly with the specific joke, quest, monster or player in the log. Never force <Class> buzzwords into every line if they do not fit the conversation.
- Never repeat stock catchphrases: no canned openers like "i am <name>, the great...", and never reuse the same pet, spell or gear joke across turns. Invent fresh angles every time.
- Casual WoW chat rhythm: natural lowercase without stiff punctuation. <REPLY_LENGTH>
- Vary the length across the 5 options: some are a few words, one may run a little longer when the moment calls for it.
- [Known Player] blocks are the user's own notes on the people in the scene (relationship, who they are, shared history). Let them shape how <First Name> talks to that person, but never quote a note.
- If the snapshot has an [Instruction] line, it is the user's direction for these replies (tone, focus, who to answer). Follow it. It is not chat and never something a character said.

THE 5 RESPONSE ANGLES

Give 5 distinct options, one per mood, labeled with the mood:

1. <mood 1 name>: <one line on what this mood does, e.g. delivers an overly grand verdict on an ordinary situation, completely straight-faced>
2. <mood 2 name>: <e.g. quick snark, competitive pride, or a ridiculous excuse to save face>
3. <mood 3 name>: <e.g. counts every copper, eyes free food or loot, or shows a soft spot for allies>
4. <mood 4 name>: <a class or companion angle, e.g. blames the pet, a spell gone wrong, or questionable engineering>
5. <mood 5 name>: <e.g. casually escalates a minor problem into maximum collateral damage, then plans a quick exit>

CHANNEL AND FORMATTING RULES

- No channel prefixes: never start lines with /1, /g, /p, /s or /w. Output pure copy-paste-ready text.
- Match the channel:
  - [General] / [Guild]: zone or guild chatter. Keep it conversational and skip physical actions that distant players cannot see.
  - [Party]: teammate banter aware of pulls, mana breaks, loot and group survival.
  - [Say]: face to face. A standalone WoW emote (/shrug, /sigh, /giggle, /ponder) may go on its own line when it fits.
  - [Whisper]: a direct one-on-one reply tailored to the sender.
- Clean text: keep at least 4 options free of *action* asterisks (at most 1 brief *action*, only if it sharpens the joke). Always write in English.

EXAMPLES (replace them with lines in your character's own voice)

Input: [1. General] [Kaelen]: anyone seen the rare tiger spawn near the ridge?

1. <mood 1>: that beast and i have unfinished business, stay back
2. <mood 2>: even if i did, why would i hand over my own prey?
3. <mood 3>: if it drops decent leather, i'm helping you look
4. <mood 4>: you mean my future best friend? don't you dare
5. <mood 5>: just pull the whole ridge and i'll sort out the survivors

Input: [Party] [Thorgar]: who just pulled the entire patrol

1. <mood 1>: destiny demanded a true test of our strength
2. <mood 2>: my aim slipped, partly your fault for standing there
3. <mood 3>: bright side, more pockets to loot if we live
4. <mood 4>: my pet made an executive decision
5. <mood 5>: i'm vanishing in three seconds, good luck everyone]]

local RP_REPLY_LENGTH = {
    SHORT = "Keep every option punchy: one short sentence or chat fragment (most about 5 to 14 words), never two sentences and never long comma-spliced speeches.",
    MEDIUM = "Keep options chat-sized: one sentence each (about 10 to 20 words), never a paragraph.",
    LONG = "Options may be one or two sentences (up to about 30 words) when the scene is slower, but stay chat-sized.",
}

function UI.GetRpSkillTemplate()
    local key = (RPCopyDB and RPCopyDB.rpReplyLength) or "SHORT"
    local text = RP_SKILL_TEMPLATE_TEXT:gsub("<REPLY_LENGTH>", (RP_REPLY_LENGTH[key] or RP_REPLY_LENGTH.SHORT):gsub("%%", "%%%%"))
    return text
end

-- 0.4.0: two story skills share the same reading rules, color palette,
-- header and footer (Story Book parses them), so they are built from parts.
local STORY_SHARED_RULES = [[
READING THE LOG (HIDDEN CONTEXT)

1. Stay Faithful to the Log: build the story only from the real roster, places, foes, bosses, quests, loot, deaths and chat quotes in the log. Use rich fantasy prose for the scenes, but never invent bosses, kills, loot, quests, deaths or player quotes.
2. Header lines: "Run type:" says Dungeon, Raid or Open world adventure. The Roster gives each member's level, class and role ([Tank], [Healer], [DPS]). A member marked "<Guild> (guildmate)" shares the player's guild: treat them as old companions-in-arms of the same guild and mention the shared guild naturally once or twice. "Known companions:" lines are the player's own RP notes: let them shape how that character acts and talks, but never quote a note or invent a scene from it.
3. Timestamps, HP and mana are hidden context: [HH:MM:SS], [BOSS HP], [LOW MANA], [DANGER] and combat tags tell you order and intensity only. The story prose must NEVER mention clock times, durations, or any HP, mana or percent numbers. "at 4% HP" becomes "with the beast staggering on its last breath".
4. Tags and what they mean:
   [FIGHT] one line per fight: the foes, how long it took, the abilities used ("used Arcane Shot; Snips: Claw"), who fled, who took aggro from whom, who got low, who fell, and how it ended. [FIGHTS] a streak of easy fights against the same foe folded into one line ("14x Windsong Crawler"): give it a sentence of travel color, not a scene each.
   [KILL] an elite, rare or named foe defeated. Foes defeated: N in the header counts all foes, trash included.
   [BOSS ENGAGED] [BOSS KILL] [BOSS RESET] [WIPE #N] boss fights and wipes. [BOSS CAST] what a boss cast and at whom.
   [SPELL] a big cooldown or crowd control cast. [CC] mind control, fear, stun, polymorph. [AGGRO] a foe turning on someone else.
   [DANGER] near death, [SAVED] pulled back from the brink, [DEATH] a death with what they were fighting, [REZ] a resurrection.
   [PET] [PET DEATH] the party's pets. Pets show as "Name (Species, Owner's hunter pet)", e.g. "Snips (Crab, ...)": Snips is the pet's own name and a crab is what it is. Always call the pet by its name and write it as the creature it is ("Snips, her crab"); when name and species are the same ("Crab (Crab, ...)") the pet is simply named Crab. [MILESTONE] a new spell, pet, mount, achievement, reputation standing, hearthstone bind or flight path.
   [QUEST] quests accepted and completed, [QUEST TEXT] the quest giver's own words (quote them sparingly).
   [NPC] [NPC Emote] lines spoken by bosses and named NPCs. [LEVEL] a level up. [SKILL] a profession skill-up. [PLACE] a new place reached.
   [ATMOSPHERE] the time of day (dawn, morning, midday, afternoon, dusk, night) and indoors or open sky: use it to set the mood of the scene.
   [LOOT] an item with who got it and where it came from (crafted, from a foe, quest reward, bought, traded, mail, gathered). [HIGHLIGHT] a moment the player marked: give it a scene.
   [SHOT N] a screenshot taken at that moment; the "Screenshots" list in the header numbers them. Put the marker [Shot N] on its own line in the story where that picture fits best (each number once, in order). RPCopy hides the markers in game and the exporter shows the pictures there.
   Chat lines ([Party], [Say], [Emote], [Whisper]) are real quotes: weave them in verbatim.
5. Do not shrink the run into a dry summary. Messy moments (wipes, near deaths, panicked chat, lucky loot) are what make it memorable.
6. No Icons: never write |T or |A texture codes. RPCopy adds boss icons itself.

STORY BOOK HEADER AND FOOTER (REQUIRED, RPCopy reads them)

Line 1: the story title only, in gold, e.g. |cffffd100Shadows Over Pyrewood|r
Line 2: |cff9e9e9e<dungeon, raid or region> | <duration from the log header> | <zone or the places visited>|r (never the same name twice: if the zone is the region, list the main places instead)
Line 3: |cff9e9e9eDate: <date from the log header> | Party: <names, comma separated>|r
Then a blank line and the story. Start each chapter with a gold header line: |cffffd100Chapter 1: <chapter name>|r
Last line (footer), dungeon or raid: |cff9e9e9eBosses: <N> | Wipes: <N> | Deaths: <N>|r
Last line (footer), open world: |cff9e9e9eFoes: <N> | Quests: <N> | Levels: <from> -> <to> | Deaths: <N>|r and leave out any part that is zero or missing.
The header and footer are the only place where the duration and the counts may appear.

RPCOPY COLOR PALETTE (|cffRRGGBB...|r)

COLOR EVERY MENTION, IN EVERY CHAPTER: each time a player, pet, place, foe, NPC or item is named, wrap it in its color, not only the first time. Chapter 5 must be as colorful as chapter 1. After a colored name, go back to the prose color.

- Title and chapter headers: |cffffd100 (Gold)
- Places and scene subheaders: |cff40e0d0 (Teal) or |cffb39ddb (Lavender)
- Narrative prose: |cffeceff1 (Bright Off-White)
- Player names in their class color: Warrior |cffC79C6E, Paladin |cffF58CBA, Hunter |cffABD473, Rogue |cffFFF569, Priest |cffC0C0C0 (gray, not white), Death Knight |cffC41F3B, Shaman |cff0070DE, Mage |cff69CCF0, Warlock |cff9482C9, Monk |cff00FF96, Druid |cffFF7D0A, Demon Hunter |cffA330C9, Evoker |cff33937F
- Pets: |cff80cbc4 (Sea Green)
- Bosses, elites, named foes and every foe type ("Windsong Crawler"): |cffdc143c (Crimson). Never use the Druid orange for a foe.
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
        tpl.sub:SetText("|cffb0bac5A simple starter: fill in the <...> fields and make it your character before you paste it into your AI.|r")
        tpl.editBox:SetText(EscapeForEditBox(UI.GetRpSkillTemplate()))
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
    { key = "SUMMARY", label = "Summary" },
    { key = "COMPANIONS", label = "Companions" },
    { key = "STORIES", label = "Stories & Export" },
    { key = "AI", label = "AI Setup" },
    { key = "PRIVACY", label = "Privacy" },
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
        local nextMode = { INSTANT = "TWOPRESS", TWOPRESS = "BOX", BOX = "INSTANT" }
        RPCopyDB.copyMode = nextMode[RPCopyDB.copyMode] or "INSTANT"
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
        elseif RPCopyDB.copyMode == "BOX" then
            modeBtn:SetText("|cffc2d8ffCopy box|r")
        else
            modeBtn:SetText("|cffc2d8ffTwo-press|r")
        end
        UI.SetToggleLook(combatBtn, RPCopyDB.instantInCombat, "Instant in combat: ON", "Instant in combat: OFF")
        if not isCtrlC then
            modeNote:SetText("|cff8f9ba8Your Quick Copy key arms the copy; then press Ctrl+C to copy. Copy style only applies to CTRL-C.|r")
        elseif RPCopyDB.copyMode == "BOX" then
            modeNote:SetText("|cff8f9ba8Copy box: Ctrl+C shows the snapshot selected in a small box. Press Ctrl+C there to copy, and it closes by itself. The safest style if the others do not copy.|r")
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
        { field = "recordManualShots", invert = true, label = "Add my own screenshots to runs",
          tip = "Your Print Screen shots during a run join its screenshot list with a caption, so Export_Stories.bat can place them in the story." },
    })
    local status = Note(p, "", 0, -204)
    Note(p, "|cff8f9ba8Open-world runs: click Start Recording in Adventures, use the RP icon's right-click menu, or a keybind. A run cut short by a logout or disconnect is saved as interrupted, never lost.|r", 0, -230)
    local dBtn = UI.CreateSleekButton(p, 160, 24, "Dungeon/Raid Template", "gold")
    dBtn:SetPoint("TOPLEFT", 0, -278)
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

-- A grid of check boxes bound to a table of booleans (missing = on)
local function CheckGrid(p, y, defs, store, prefix, colW)
    local checks = {}
    local half = math.ceil(#defs / 2)
    for i, d in ipairs(defs) do
        local cb = CreateFrame("CheckButton", prefix .. d.key, p, "UICheckButtonTemplate")
        cb:SetSize(18, 18)
        local col = (i <= half) and 0 or 1
        local row = (i <= half) and (i - 1) or (i - half - 1)
        cb:SetPoint("TOPLEFT", col * (colW or 210), y - row * 18)
        local lbl = cb:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        lbl:SetPoint("LEFT", cb, "RIGHT", 2, 0)
        lbl:SetText(d.label)
        cb:SetScript("OnClick", function(self)
            local t = store()
            t[d.key] = self:GetChecked() and true or false
            if d.after then pcall(d.after) end
        end)
        checks[d.key] = cb
    end
    return function()
        local t = store()
        for key, cb in pairs(checks) do cb:SetChecked(t[key] ~= false) end
    end, y - half * 18
end
UI.OptionsCheckGrid = CheckGrid

-- A number box bound to an RPCopyDB field
local function NumberBox(p, x, y, label, field, lo, hi, default, tip)
    UI.Label(p, label, "GameFontHighlightSmall"):SetPoint("TOPLEFT", x, y - 4)
    local eb = CreateFrame("EditBox", "RPCopyOptNum_" .. field, p, "InputBoxTemplate")
    eb:SetSize(44, 20)
    eb:SetPoint("TOPLEFT", x + 170, y)
    eb:SetAutoFocus(false)
    eb:SetNumeric(true)
    eb:SetMaxLetters(4)
    local function Commit(self)
        local v = tonumber(self:GetText() or "") or default
        RPCopyDB[field] = math.max(lo, math.min(hi, math.floor(v)))
        self:SetText(tostring(RPCopyDB[field]))
        self:ClearFocus()
    end
    eb:SetScript("OnEnterPressed", Commit)
    eb:SetScript("OnEditFocusLost", Commit)
    eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    eb:SetScript("OnEnter", function(self) UI.Tooltip(self, "|cffffd100" .. label .. "|r", (tip or "") .. string.format(" From %d to %d. Default %d.", lo, hi, default)) end)
    eb:SetScript("OnLeave", UI.HideTooltip)
    return function() eb:SetText(tostring(RPCopyDB[field] or default)) end, eb
end

-- ---------------------------------------------------------
-- Summary (0.5.0): which stats the run Summary and top bar show
-- ---------------------------------------------------------
do
    local p = NewPage("SUMMARY", "Summary")
    Note(p, "|cff8f9ba8What the Summary of a recording shows. Stats that are zero are always hidden. Bosses and wipes only show for dungeons and raids, places only for the open world.|r", 0, -20)
    local refreshGrid = CheckGrid(p, -56, ns.SUMMARY_STATS, function() return RPCopyDB.summaryStats end, "RPCopyOptSum_")
    O.refresh.SUMMARY = function()
        ns.EnsureDB()
        refreshGrid()
    end
end

-- ---------------------------------------------------------
-- Companions (0.5.0)
-- ---------------------------------------------------------
do
    local p = NewPage("COMPANIONS", "Companions")
    local toggles = ToggleRows(p, -24, {
        { field = "knownPlayerBlocks", invert = true, label = "[Known Player] blocks",
          tip = "Adds your notes on the people in the scene to the snapshot you copy." },
        { field = "autoUpdateKnown", label = "Update companions from chat",
          tip = "Keeps a companion's level, class and latest chat up to date when they talk near you." },
        { field = "companionMenu", invert = true, label = "Add as companion (right-click)",
          tip = "Adds 'Add as RPCopy companion' to the game's player right-click menu (where the game allows it). Takes effect after /reload." },
        { field = "nearbyChip", invert = true, label = "Nearby companions on Copy",
          tip = "Shows companions you target, group with or chat with, at the bottom of the Copy view." },
        { field = "runCompanions", invert = true, label = "Companions in the Full Log",
          tip = "Companions you chat with during a run are listed as Known companions in its Full Log, with their notes." },
    })
    local maxRefresh = NumberBox(p, 0, -152, "Known Player blocks per copy", "knownPlayerMax", 0, 10, 3,
        "How many companion blocks one snapshot can have.")
    local noteRefresh = NumberBox(p, 0, -178, "Note length in a block", "knownNoteMax", 40, 1000, 300,
        "Longer notes are cut at a sentence or word.")
    Note(p, "|cff8f9ba8Per companion, the Include button in Companions picks Auto, Always or Never. Auto adds a companion when they are your target, in your group, or in the copied chat.|r", 0, -210)
    O.refresh.COMPANIONS = function()
        toggles()
        maxRefresh()
        noteRefresh()
    end
end

-- ---------------------------------------------------------
-- Stories & Export (0.5.0)
-- ---------------------------------------------------------
do
    local p = NewPage("STORIES", "Stories & Export")
    local toggles = ToggleRows(p, -24, {
        { field = "autoColorStory", invert = true, label = "Auto-color imported stories",
          tip = "On import, names the AI left plain are colored from the run: party in class colors, pets, places, foes, NPCs and items." },
        { field = "exportTip", invert = true, label = "Export tip in the Story Book",
          tip = "Shows how to make HTML pages with screenshots using Export_Stories.bat." },
    })
    Note(p, "|cff8f9ba8Export_Stories.bat (in the RPCopy AddOns folder) reads these after a /reload or logout. Leave a box empty for the default.|r", 0, -80)
    local function PathBox(y, label, field, tip)
        UI.Label(p, label, "GameFontHighlightSmall"):SetPoint("TOPLEFT", 0, y - 4)
        local eb = CreateFrame("EditBox", "RPCopyOptPath_" .. field, p, "InputBoxTemplate")
        eb:SetHeight(20)
        eb:SetPoint("TOPLEFT", 150, y)
        eb:SetPoint("RIGHT", p, "RIGHT", -8, 0)
        eb:SetAutoFocus(false)
        eb:SetMaxLetters(260)
        local function Commit(self)
            local v = (self:GetText() or ""):gsub("||", "|"):match("^%s*(.-)%s*$")
            RPCopyDB[field] = v
            self:ClearFocus()
        end
        eb:SetScript("OnEnterPressed", Commit)
        eb:SetScript("OnEditFocusLost", Commit)
        eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
        eb:SetScript("OnEnter", function(self) UI.Tooltip(self, "|cffffd100" .. label .. "|r", tip) end)
        eb:SetScript("OnLeave", UI.HideTooltip)
        return function() eb:SetText(RPCopyDB[field] or "") end
    end
    local r1 = PathBox(-112, "Image folder", "exportImageDir",
        "Where the exporter copies screenshots for the pages. Empty: an 'images' folder next to the HTML.")
    local r2 = PathBox(-140, "Screenshots folder", "exportShotsDir",
        "Where WoW saves screenshots. Empty: found by itself (the _forever_\\Screenshots folder).")
    Note(p, "|cff8f9ba8How to export: /reload or log out so the game saves your stories, then double-click Export_Stories.bat in Interface\\AddOns\\RPCopy. The pages open from the RPCopy Stories folder it makes in _forever_.|r", 0, -176)
    local dBtn = UI.CreateSleekButton(p, 160, 24, "Dungeon/Raid Template", "gold")
    dBtn:SetPoint("TOPLEFT", 0, -236)
    dBtn:SetIcon(UI.ICONS.STORY, 16)
    dBtn:SetScript("OnClick", function() UI.OpenSkillTemplateModal("STORY") end)
    local aBtn = UI.CreateSleekButton(p, 150, 24, "Adventure Template", "gold")
    aBtn:SetPoint("LEFT", dBtn, "RIGHT", 6, 0)
    aBtn:SetIcon(UI.ICONS.STORY, 16)
    aBtn:SetScript("OnClick", function() UI.OpenSkillTemplateModal("ADVENTURE") end)
    O.refresh.STORIES = function()
        toggles()
        r1()
        r2()
    end
end

-- ---------------------------------------------------------
-- Privacy (0.5.0): the disclaimer, what is captured, setup and wipe
-- ---------------------------------------------------------
do
    local p = NewPage("PRIVACY", "Privacy")
    Note(p, (ns.PRIVACY_TEXT or "") .. "\n|cffffd100Chat RPCopy keeps:|r", 0, -20)
    local refreshGrid = CheckGrid(p, -164, ns.CAPTURE_TYPES, function() return RPCopyDB.capture end, "RPCopyOptCap_")
    local setupBtn = UI.CreateSleekButton(p, 150, 24, "Open Setup Again", "gold")
    setupBtn:SetPoint("TOPLEFT", 0, -230)
    setupBtn.tipTitle = "|cffffd100Setup|r"
    setupBtn.tipText = "Shows the first-run disclaimer and setup choices again (/rp setup)."
    setupBtn:SetScript("OnClick", function() if UI.OpenSetup then UI.OpenSetup(true) end end)
    local wipeBtn = UI.CreateSleekButton(p, 150, 24, "Delete All Data", "danger")
    wipeBtn:SetPoint("LEFT", setupBtn, "RIGHT", 6, 0)
    wipeBtn.tipTitle = "|cffff6b6bDelete all RPCopy data|r"
    wipeBtn.tipText = "Click twice. Deletes every recording, story, companion and setting, then reloads the UI (/rp wipe)."
    wipeBtn:SetScript("OnClick", function(self)
        if not self.armedAt or GetTime() - self.armedAt > 4 then
            self.armedAt = GetTime()
            self:SetText("|cffff6b6bSure? Click again|r")
            return
        end
        self.armedAt = nil
        if ns.WipeAllData then ns.WipeAllData() end
    end)
    O.refresh.PRIVACY = function()
        ns.EnsureDB()
        refreshGrid()
        wipeBtn.armedAt = nil
        wipeBtn:SetText("Delete All Data")
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
        "2. It is a simple starter: fill in your character (personality, backstory, voice, quirks, moods, how they talk). The more of you in it, the better the replies.\n" ..
        "3. Make it a Skill in Gemini, a Project in ChatGPT, or a Skill or Project in Claude.\n" ..
        "4. Use the skill's trigger (like |cff69ccf0use aloria|cffd8dee9) as the Skill Call in Slice Tabs.|r",
        0, -28)
    local rpBtn = UI.CreateSleekButton(p, 150, 24, "RP Template", "gold")
    rpBtn:SetPoint("TOPLEFT", 0, -104)
    rpBtn:SetIcon(UI.ICONS.COPY, 16)
    rpBtn:SetScript("OnClick", function() UI.OpenSkillTemplateModal("RP") end)
    local LENGTHS = { "SHORT", "MEDIUM", "LONG" }
    local LEN_LABEL = { SHORT = "Replies: Short", MEDIUM = "Replies: Medium", LONG = "Replies: Long" }
    local lenBtn = UI.CreateSleekButton(p, 130, 24, "", "tool")
    lenBtn:SetPoint("LEFT", rpBtn, "RIGHT", 6, 0)
    lenBtn.tipTitle = "|cffffd100Reply length|r"
    lenBtn.tipText = "How long the RP template asks replies to be. Short is like real chat (about 5 to 14 words). Copy the template again after changing it."
    lenBtn:SetScript("OnClick", function()
        local idx = 1
        for i, k in ipairs(LENGTHS) do if k == RPCopyDB.rpReplyLength then idx = i end end
        RPCopyDB.rpReplyLength = LENGTHS[(idx % #LENGTHS) + 1]
        lenBtn:SetText(LEN_LABEL[RPCopyDB.rpReplyLength])
    end)
    O.refresh.AI = function() lenBtn:SetText(LEN_LABEL[RPCopyDB.rpReplyLength or "SHORT"] or LEN_LABEL.SHORT) end

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
        { field = "debugEnabled", invert = true, label = "Debug log",
          tip = "OFF: only RPCopy's own errors and blocked actions are kept." },
        { field = "debugVerbose", label = "Verbose debug log",
          tip = "Also logs extra detail (every quick copy, for example). Leave it off unless you are chasing a bug." },
    })
    local reportBtn = UI.CreateSleekButton(p, 150, 24, "Copy Debug Report", "gold")
    reportBtn:SetPoint("TOPLEFT", 0, -180)
    reportBtn:SetScript("OnClick", function() SlashCmdList["RPCOPY"]("debug") end)
    local clearBtn = UI.CreateSleekButton(p, 120, 24, "Clear Debug Log", "danger")
    clearBtn:SetPoint("LEFT", reportBtn, "RIGHT", 6, 0)
    clearBtn:SetScript("OnClick", function()
        RPCopyDB.debugLog = {}
        UI.SetStatus("Debug log cleared.", "good")
        UI.RefreshOptionsPage()
    end)
    local count = Note(p, "", 0, -216)
    O.refresh.DEBUG = function()
        verbose()
        count:SetText(string.format("|cff8f9ba8%d lines in the debug log.|r", #(RPCopyDB.debugLog or {})))
    end
end

UI.SetSectionOnShow("OPTIONS", function()
    UI.EnsureOptions()
    UI.ShowOptionsPage(RPCopyDB.optionsPage)
end)
