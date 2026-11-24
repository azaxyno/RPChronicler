local ADDON_NAME, ns = ...

-- =========================================================
-- Safe Fallbacks if Adventures.lua is not yet loaded
-- =========================================================
if not ns.GetActiveAdventure then
    ns.GetActiveAdventure = function() return nil end
end
if not ns.GetAdventureIcon then
    ns.GetAdventureIcon = function() return "Interface\\Icons\\INV_Misc_Map_01" end
end
if not ns.StartAdventure then
    ns.StartAdventure = function() return { id = tostring(time()), title = "Run" } end
end
if not ns.EndAdventure then
    ns.EndAdventure = function() return nil end
end
if not ns.MarkAdventureHighlight then
    ns.MarkAdventureHighlight = function() return false, "Adventures module not loaded." end
end
if not RPCopy_MarkMoment then
    RPCopy_MarkMoment = function()
        local _, status = ns.MarkAdventureHighlight(nil)
        print("|cff00ff00[RPCopy]|r " .. status)
    end
end
if not ns.BuildAdventureSummary then
    ns.BuildAdventureSummary = function(adv)
        if not adv then return "No adventure selected." end
        return (adv.title or "Adventure") .. " (" .. (adv.zone or "Unknown") .. ")"
    end
end
if not ns.BuildAdventureFullLog then
    ns.BuildAdventureFullLog = function(adv)
        if not adv then return "No adventure selected." end
        return adv.exportText or "No timeline recorded."
    end
end
if not ns.SetAdventureStory then
    ns.SetAdventureStory = function(advId, rawStoryText)
        if ns.EnsureDB then ns.EnsureDB() end
        local cleaned = (rawStoryText or ""):match("^%s*(.-)%s*$")
        cleaned = cleaned:gsub("||", "|")
        cleaned = cleaned:gsub("^```[%w_-]*%s*\n?", ""):gsub("\n?```%s*$", "")
        cleaned = cleaned:gsub("★", "*")
        cleaned = cleaned:match("^%s*(.-)%s*$")

        local openCount = 0
        for _ in cleaned:gmatch("|c%x%x%x%x%x%x%x%x") do openCount = openCount + 1 end
        local closeCount = 0
        for _ in cleaned:gmatch("|r") do closeCount = closeCount + 1 end
        if openCount > closeCount then
            cleaned = cleaned .. string.rep("|r", openCount - closeCount)
        end

        local active = ns.GetActiveAdventure()
        if active and active.id == advId then
            active.story = cleaned
            return true
        end
        for _, adv in ipairs((RPCopyDB and RPCopyDB.adventures) or {}) do
            if adv.id == advId then
                adv.story = cleaned
                return true
            end
        end
        return false
    end
end

local RP_SKILL_TEMPLATE_TEXT = [[---
name: <character-name>-rp-<class>
description: Generate short, casual World of Warcraft roleplay responses for <Character Full Name> (<Faction> <Race> <Class>) inspired by <Persona Inspiration>. Use when the user uploads a WoW chat screenshot, mentions "<trigger>" (such as "use <trigger>"), or asks for <Class> RP replies in General, Say, Whisper, or Party chat.
---

# WoW RP <Faction> <Race> <Class> (<Persona Inspiration> Persona)

Generate short, casual in-character English roleplay replies for <Character Full Name>, a <personality summary> <Faction>-aligned <Race> <Class> in World of Warcraft, capturing the voice and quirks of <Persona Inspiration>.

## When to Use

- The user pastes an RPCopy context snapshot starting with `use <trigger>` (containing `[Location]`, `[Target]`, `[S]`, `[G]`, `[P]`, `[W]`, `[Loot]`, etc.) or uploads a WoW chat screenshot.
- The user mentions the trigger words `<trigger>` or `<surname>` (for example: "use <trigger>", "<trigger> reply").
- The user asks for quick in-character <Class> roleplay responses.

## Core Personality (5 Distinct Angles)

1. **Signature Quirk / Theatrical Angle**:
   - Frames ordinary moments with <Character Full Name>'s signature flair (e.g., dramatic titles, deadpan grand declarations, or noble poise), then drops right back into casual speech.
   - Invents overly dramatic names for ordinary beasts, spells, gear, or low-level mobs.

2. **Petty & Witty Banter**:
   - Invents grandiose lore excuses to dodge mundane chores, walking, or blame ("my keen senses are currently sealed for greater prey").
   - Turns trivial moments into playful rivalry and gets flustered if treated like a novice.

3. **Heart & Everyday Habits**:
   - Carries grounded adventurer habits into Azeroth (counting every copper, hating repair/reagent bills, hoarding free food, protecting loot rights).
   - Loyal to <Faction> and teammates, with a soft spot for <favorite thing/creatures>.

4. **Class / Companion / Lore Chaos (Option 4)**:
   - Obsessed with <class-specific gimmick: e.g., taming dangerous elites, forbidden arcane theory, questionable engineering>, giving them ridiculous names, and blaming accidental pulls on <pet/spells/fate>.

5. **Unhinged Overkill Mode (Option 5)**:
   - Over-the-top <Class> mode: eager to solve every minor problem by unloading big AoE/traps/cooldowns on the entire room, then immediately <Feign / Blink / Vanish / bubble> while the party handles the aggro.

## Channel Context & Formatting Rules

1. **No Channel Prefixes**: Never start replies with `/1`, `/p`, `/s`, `/w`, or `/y`. Output pure, copy-paste-ready text.
2. **Adapt to the Chat Channel Context**: Check `[G]`, `[P]`, `[S]`, `[W]`, `[Y]` tags and tailor RP accordingly.
3. **Always Output RP in English**: Write all 5 RP chat options in natural, casual lowercase English.
4. **Keep It Short**: 1-2 short sentences max per option so it fits fast-paced WoW chat.]]

local STORY_SKILL_TEMPLATE_TEXT = [[---
name: wow-adventure-story
description: Transform World of Warcraft dungeon, raid, or adventure logs from RPCopy into vivid, entertaining narrative stories formatted with WoW color escape codes (|cffRRGGBB...|r) for direct import into the RPCopy addon Story tab. Use when the user pastes an RPCopy adventure log, mentions "adventure story", "dungeon story", "create a story", "use story", or asks to turn a WoW run, party chat, wipes, or gameplay session into a colored in-game chronicle.
---

# WoW Adventure Storyteller (RPCopy Colored Chronicle)

Turn exported World of Warcraft adventure logs from RPCopy into rich, entertaining stories formatted with native WoW color escape codes (`|cffRRGGBB...|r`) so they can be pasted directly into RPCopy's Story tab and read cleanly in-game.

## When to Use

- The user pastes a full or partial RPCopy Adventure Log (containing `[ADVENTURE]`, roster, wipes, boss kills, loot, highlights, or timeline chat).
- The user uses a trigger such as `use story`, `adventure story`, or asks to generate a story from a dungeon, raid, or open-world session.

## Storytelling & Accuracy Principles

1. **Stay Faithful to the Log (No Invented Events or Fake Quotes)**: Build the narrative strictly from the real roster, bosses, HP/mana milestones, wipes, loot, and chat quotes recorded in the timeline. Use dramatic fantasy prose to describe the scenes, but never fabricate bosses, wipes, loot drops, or player quotes that do not appear in the log.
2. **Use Combat & HP Context from Timestamps**: Pay close attention to `[HH:MM:SS]` timestamps, `[BOSS HP]` milestones (such as `5% HP`), `[LOW MANA]`, `[DANGER]`, and combat tags on chat lines (such as `[Party | vs Boss 5% HP]`) so you accurately connect when someone panicked, asked for water, or celebrated relative to the fight.
3. **Do Not Limit What Happened**: Never compress the run into a dry summary or skip messy moments. Include everything that made the session memorable - wipes, ninja pulls, someone begging for conjured water, OOM panic, clutch heals, dramatic boss kills, and loot drops.
4. **Weave Real Quotes and Roles Naturally**: Use the roster's classes and roles (`[Tank]`, `[Healer]`, `[DPS]`) to give each party member a distinct presence, and embed their actual quotes from the timeline verbatim.

## RPCopy Color Palette (`|cffRRGGBB...|r`)

Color the output using WoW's native hex escape format (`|cffRRGGBBtext|r`) so the story renders vividly on RPCopy's warm dark-parchment reader:

- **Story Title & Chapter Headers**: `|cffffd100` (Gold)
- **Zone, Instance & Scene Subheaders**: `|cff40e0d0` (Teal) or `|cffb39ddb` (Lavender)
- **Main Narrative Prose**: `|cffeceff1` (Bright Off-White)
- **Player Names (Match WoW Class Color)**: Warrior `|cffC79C6E`, Paladin `|cffF58CBA`, Hunter `|cffABD473`, Rogue `|cffFFF569`, Priest `|cffFFFFFF`, Death Knight `|cffC41F3B`, Shaman `|cff0070DE`, Mage `|cff69CCF0`, Warlock `|cff9482C9`, Monk `|cff00FF96`, Druid `|cffFF7D0A`, Demon Hunter `|cffA330C9`, Evoker `|cff33937F`
- **Bosses & Elite Threats**: `|cffff8000` (Orange)
- **Wipes, Deaths & Danger**: `|cffff5252` (Red)
- **Victories, Clutch Saves & Healing**: `|cff66bb6a` (Green)
- **Notable Loot Drops**: `|cffffd700` (Loot Gold) or `|cffe066ff` (Epic Purple)
- **Quoted Party / Say Dialogue**: `|cffaaaaff` (Party Blue) or `|cffffffff` (Say White)
- **Footer Stats & Metadata**: `|cff9e9e9e` (Muted Gray)

## Formatting Rules for WoW Compatibility

1. **Single Copy-Paste Code Block**: Output the entire colored story inside one fenced code block (` ```text `) so the user can copy and paste it straight into RPCopy.
2. **Close Every Color Tag**: Always pair every `|cffRRGGBB` with a closing `|r`.
3. **Zero Markdown Inside the Code Block**: Never use `**bold**`, `*italics*`, `# headers`, or bullet symbols inside the WoW text block. Use WoW color tags and blank lines for structure.
4. **ASCII Characters Only**: Use standard ASCII punctuation (`-`, `'`, `"`, `*`) inside the code block so WoW fonts never render missing-glyph boxes.]]

-- =========================================================
-- Inject OOC Channel Logs into Snapshot When Tab Enables It
-- =========================================================
local origBuildSnapshot = ns.BuildSnapshot
ns.BuildSnapshot = function(filterId, note, isExpanded)
    local baseText = origBuildSnapshot and origBuildSnapshot(filterId, note, isExpanded) or ""
    local tabCfg = ns.GetTabConfig(filterId)
    if not tabCfg or not tabCfg.incOoc or not ns.logs.ooc or #ns.logs.ooc == 0 then
        return baseText
    end

    local limit = isExpanded and (RPCopyDB.expandMessages or 6) or (RPCopyDB.defaultMessages or 3)
    local slice = {}
    local startIdx = math.max(1, #ns.logs.ooc - limit + 1)
    for i = startIdx, #ns.logs.ooc do
        table.insert(slice, ns.logs.ooc[i])
    end
    local oocBlock = table.concat(slice, "\n")

    local kpPos = baseText:find("\n%[Known Player:", 1, true) or baseText:find("\n|cffffd100%[Known Player:", 1, true)
    if kpPos then
        return baseText:sub(1, kpPos - 1) .. "\n" .. oocBlock .. baseText:sub(kpPos)
    end
    return baseText .. "\n" .. oocBlock
end

local function EnsureUIOptions()
    ns.EnsureDB()
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
end

-- =========================================================
-- Dark-Glass & Warm Dark-Parchment Chronicle Theme Helpers
-- =========================================================
local SOLID_TEX = "Interface\\Buttons\\WHITE8x8"

local function ApplyDarkGlass(frame, bgR, bgG, bgB, bgA, brR, brG, brB, brA)
    if not frame or not frame.SetBackdrop then return end
    frame:SetBackdrop({
        bgFile = SOLID_TEX,
        edgeFile = SOLID_TEX,
        tile = false,
        edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 },
    })
    frame:SetBackdropColor(bgR or 0.06, bgG or 0.07, bgB or 0.10, bgA or 0.94)
    frame:SetBackdropBorderColor(brR or 0.72, brG or 0.58, brB or 0.28, brA or 0.45)
end

local function ApplyStoryTomeLook(frame)
    ApplyDarkGlass(frame, 0.09, 0.07, 0.05, 0.98, 0.86, 0.68, 0.30, 0.85)
end

local function CreateSleekButton(parent, width, height, text, accentStyle)
    local btn = CreateFrame("Button", nil, parent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    if width and height then btn:SetSize(width, height) end

    btn.accentStyle = accentStyle
    btn.isLocked = false
    btn.isDisabled = false

    local function ApplyNormalLook()
        if btn.isDisabled then
            ApplyDarkGlass(btn, 0.08, 0.09, 0.11, 0.70, 0.22, 0.24, 0.28, 0.50)
            btn.label:SetTextColor(0.45, 0.48, 0.52)
        elseif btn.isLocked then
            ApplyDarkGlass(btn, 0.22, 0.18, 0.09, 0.96, 0.90, 0.73, 0.32, 0.95)
            btn.label:SetTextColor(1.0, 0.86, 0.35)
        elseif btn.accentStyle == "gold" then
            ApplyDarkGlass(btn, 0.18, 0.15, 0.09, 0.94, 0.82, 0.65, 0.30, 0.85)
            btn.label:SetTextColor(0.98, 0.85, 0.40)
        elseif btn.accentStyle == "tool" then
            ApplyDarkGlass(btn, 0.10, 0.14, 0.20, 0.94, 0.36, 0.52, 0.74, 0.70)
            btn.label:SetTextColor(0.76, 0.88, 1.0)
        elseif btn.accentStyle == "danger" then
            ApplyDarkGlass(btn, 0.18, 0.08, 0.09, 0.90, 0.65, 0.24, 0.26, 0.70)
            btn.label:SetTextColor(1.0, 0.55, 0.55)
        else
            ApplyDarkGlass(btn, 0.11, 0.13, 0.17, 0.92, 0.28, 0.32, 0.40, 0.80)
            btn.label:SetTextColor(0.90, 0.92, 0.95)
        end
    end

    btn.label = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    btn.label:SetPoint("LEFT", 5, 0)
    btn.label:SetPoint("RIGHT", -5, 0)
    btn.label:SetJustifyH("CENTER")
    btn.label:SetWordWrap(false)

    function btn:SetText(str)
        self.label:SetText(str or "")
    end

    function btn:GetText()
        return self.label:GetText()
    end

    function btn:LockHighlight()
        self.isLocked = true
        ApplyNormalLook()
    end

    function btn:UnlockHighlight()
        self.isLocked = false
        ApplyNormalLook()
    end

    local origEnable = btn.Enable
    local origDisable = btn.Disable
    function btn:Enable()
        self.isDisabled = false
        if origEnable then origEnable(self) end
        ApplyNormalLook()
    end

    function btn:Disable()
        self.isDisabled = true
        if origDisable then origDisable(self) end
        ApplyNormalLook()
    end

    btn:SetScript("OnEnter", function(self)
        if self.isDisabled then return end
        self:SetBackdropBorderColor(0.92, 0.76, 0.35, 0.95)
        if not self.isLocked then
            if self.accentStyle == "tool" then
                self:SetBackdropColor(0.15, 0.21, 0.30, 0.98)
            else
                self:SetBackdropColor(0.16, 0.19, 0.25, 0.96)
            end
        end
    end)

    btn:SetScript("OnLeave", function()
        ApplyNormalLook()
    end)

    ApplyNormalLook()
    if text then btn:SetText(text) end
    return btn
end

-- =========================================================
-- Main UI Frame (Dark-Glass 680x490)
-- =========================================================
local copyFrame = CreateFrame("Frame", "RPCopyFrame", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
copyFrame:SetWidth(680)
copyFrame:SetHeight(490)
copyFrame:SetPoint("CENTER")
copyFrame:SetFrameStrata("DIALOG")
copyFrame:SetMovable(true)
copyFrame:EnableMouse(true)
copyFrame:RegisterForDrag("LeftButton")
copyFrame:SetScript("OnDragStart", copyFrame.StartMoving)
copyFrame:SetScript("OnDragStop", copyFrame.StopMovingOrSizing)
copyFrame:Hide()
ApplyDarkGlass(copyFrame, 0.05, 0.06, 0.08, 0.95, 0.78, 0.62, 0.28, 0.60)

-- Top Header Strip
local headerBar = CreateFrame("Frame", nil, copyFrame, BackdropTemplateMixin and "BackdropTemplate" or nil)
headerBar:SetHeight(28)
headerBar:SetPoint("TOPLEFT", 1, -1)
headerBar:SetPoint("TOPRIGHT", -1, -1)
ApplyDarkGlass(headerBar, 0.08, 0.10, 0.14, 0.98, 0.78, 0.62, 0.28, 0.30)

local titleText = headerBar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
titleText:SetPoint("LEFT", 12, 0)
titleText:SetText("|cffffd100RPCopy|r |cffd8dee9- Pick a Slice & Press Ctrl+C (Esc to Close)|r")

local verBadge = headerBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
verBadge:SetPoint("RIGHT", -34, 0)
verBadge:SetText("|cff8f9ba8v" .. (ns.VERSION or "3.7.1") .. "|r")

local closeBtn = CreateSleekButton(headerBar, 22, 20, "x", "danger")
closeBtn:SetPoint("RIGHT", -5, 0)
closeBtn:SetScript("OnClick", function() copyFrame:Hide() end)

local navDivider = copyFrame:CreateTexture(nil, "ARTWORK")
navDivider:SetWidth(1)
navDivider:SetHeight(22)
navDivider:SetTexture(SOLID_TEX)
navDivider:SetVertexColor(0.78, 0.62, 0.28, 0.45)

-- =========================================================
-- Toast Banner & Combat-Safe Keybinding System (No Protected Calls)
-- =========================================================
local copyToast = CreateFrame("Frame", "RPCopyToastFrame", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
copyToast:SetSize(330, 30)
copyToast:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 140)
copyToast:SetFrameStrata("FULLSCREEN_DIALOG")
copyToast:Hide()
ApplyDarkGlass(copyToast, 0.05, 0.07, 0.10, 0.96, 0.36, 0.72, 0.36, 0.90)

local copyToastText = copyToast:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
copyToastText:SetPoint("CENTER", 0, 0)
copyToastText:SetText("|cff5cb85cCopied snapshot to clipboard!|r")

copyToast:SetScript("OnUpdate", function(self, elapsed)
    if self.hideIn then
        self.hideIn = self.hideIn - elapsed
        if self.hideIn <= 0 then
            self.hideIn = nil
            self:Hide()
        end
    end
end)

local function ShowToast(msg, duration, borderR, borderG, borderB)
    copyToastText:SetText(msg or "")
    copyToast:SetBackdropBorderColor(borderR or 0.36, borderG or 0.72, borderB or 0.36, 0.92)
    copyToast.hideIn = duration or 2.0
    copyToast:Show()
end

local armEditBox = CreateFrame("EditBox", "RPCopySilentArmBox", UIParent)
armEditBox:SetSize(1, 1)
armEditBox:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", 2, 2)
armEditBox:SetAutoFocus(false)
armEditBox:SetMultiLine(true)
armEditBox:SetAlpha(0.01)
armEditBox:Hide()

local isArmed = false
local armedTabLabel = "Chat"
local armExpiresAt = 0

local function DisarmCtrlCopy()
    if isArmed then
        isArmed = false
        armExpiresAt = 0
        armEditBox:ClearFocus()
        armEditBox:Hide()
    end
end

local function ArmCtrlCopy()
    EnsureUIOptions()
    if InCombatLockdown and InCombatLockdown() then return false end
    if copyFrame:IsShown() then return false end

    local focused = GetCurrentKeyBoardFocus and GetCurrentKeyBoardFocus()
    if focused and focused ~= armEditBox then
        return false
    end

    local tabCfg = ns.GetTabConfig(RPCopyDB.lastSliceId)
    local tabId = (tabCfg and tabCfg.id) or "CHAT"
    armedTabLabel = (tabCfg and tabCfg.label) or "Chat"

    armEditBox:Show()
    armEditBox:SetText(ns.BuildSnapshot(tabId, "", false))
    armEditBox:SetFocus()
    armEditBox:HighlightText()
    isArmed = true
    armExpiresAt = GetTime() + 3.0
    return true
end

armEditBox:SetScript("OnUpdate", function()
    if isArmed and armExpiresAt > 0 and GetTime() > armExpiresAt then
        DisarmCtrlCopy()
    end
end)

armEditBox:SetScript("OnKeyDown", function(_, key)
    if not isArmed then return end
    if key == "C" and IsControlKeyDown() then
        ShowToast(string.format("|cffffd100Copied|r |cff69ccf0[%s]|r |cff5cb85cto clipboard!|r", armedTabLabel), 1.8, 0.36, 0.72, 0.36)
        if C_Timer and C_Timer.After then
            C_Timer.After(0.05, DisarmCtrlCopy)
        else
            DisarmCtrlCopy()
        end
    elseif key == "ESCAPE" then
        DisarmCtrlCopy()
    end
end)

armEditBox:SetScript("OnEscapePressed", DisarmCtrlCopy)
armEditBox:SetScript("OnEditFocusLost", function()
    isArmed = false
    armExpiresAt = 0
    armEditBox:Hide()
end)

local silentCopyBtn = CreateFrame("Button", "RPCopySilentCopyBtn", UIParent)
silentCopyBtn:SetSize(1, 1)
silentCopyBtn:SetPoint("BOTTOMLEFT", 0, 0)
silentCopyBtn:SetScript("OnClick", function()
    if InCombatLockdown and InCombatLockdown() then return end
    local focused = GetCurrentKeyBoardFocus and GetCurrentKeyBoardFocus()
    if focused and focused ~= armEditBox then return end

    if not isArmed then
        if ArmCtrlCopy() then
            local keyHint = (RPCopyDB and RPCopyDB.quickCopyKey) or "CTRL-C"
            ShowToast(string.format("|cffffd100Armed|r |cff69ccf0[%s]|r - Press |cffffd100%s|r again to copy!", armedTabLabel, keyHint), 2.5, 0.85, 0.68, 0.30)
        end
    else
        ShowToast(string.format("|cffffd100Copied|r |cff69ccf0[%s]|r |cff5cb85cto clipboard!|r", armedTabLabel), 1.8, 0.36, 0.72, 0.36)
        if C_Timer and C_Timer.After then
            C_Timer.After(0.05, DisarmCtrlCopy)
        else
            DisarmCtrlCopy()
        end
    end
end)

local LoadPlayerIntoEditor
local RefreshPlayersTab

function RPCopy_CaptureTarget()
    EnsureUIOptions()
    local focused = GetCurrentKeyBoardFocus and GetCurrentKeyBoardFocus()
    if focused then return end

    local targetName = nil
    if UnitExists("target") and UnitIsPlayer("target") then
        targetName = ns.GetUnitFullName("target")
    elseif UnitExists("mouseover") and UnitIsPlayer("mouseover") then
        targetName = ns.GetUnitFullName("mouseover")
    elseif ns.state.lastDirectAuthor then
        targetName = ns.state.lastDirectAuthor
    end

    if not targetName or targetName == "" then
        ShowToast("|cffff6b6bRPCopy:|r Target a player (or hover/whisper) first!", 2.0, 0.75, 0.28, 0.28)
        return
    end

    local key, isNew = ns.SaveOrUpdatePlayer(targetName)
    if key then
        local entry = RPCopyDB.players[key]
        local detail = ""
        if entry and entry.level ~= "" and entry.class ~= "" then
            detail = string.format(" |cff8f9ba8(Lvl %s %s)|r", entry.level, entry.class)
        end
        local prefix = isNew and "|cff5cb85cAdded Companion:|r " or "|cffffd100Updated Companion:|r "
        ShowToast(prefix .. "|cff69ccf0" .. key .. "|r" .. detail, 2.2, 0.36, 0.72, 0.36)

        if copyFrame:IsShown() and ns.state.activeFilter == "PLAYERS" and LoadPlayerIntoEditor and RefreshPlayersTab then
            LoadPlayerIntoEditor(key)
            RefreshPlayersTab()
        end
    end
end

local silentCaptureBtn = CreateFrame("Button", "RPCopySilentCaptureBtn", UIParent)
silentCaptureBtn:SetSize(1, 1)
silentCaptureBtn:SetPoint("BOTTOMLEFT", 0, 0)
silentCaptureBtn:SetScript("OnClick", function()
    RPCopy_CaptureTarget()
end)

-- Safe Override Binding Manager (NEVER calls SetPropagateKeyboardInput or modifies binds in combat)
local bindManagerFrame = CreateFrame("Frame", "RPCopyBindManagerFrame", UIParent)
bindManagerFrame:RegisterEvent("PLAYER_LOGIN")
bindManagerFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
bindManagerFrame:RegisterEvent("PLAYER_REGEN_ENABLED")

local function UpdateOverrideBindings()
    if InCombatLockdown and InCombatLockdown() then return end
    EnsureUIOptions()
    if ClearOverrideBindings then
        ClearOverrideBindings(bindManagerFrame)
    end
    if SetOverrideBindingClick then
        if RPCopyDB.quickCtrlC and RPCopyDB.quickCopyKey and RPCopyDB.quickCopyKey ~= "" then
            SetOverrideBindingClick(bindManagerFrame, false, RPCopyDB.quickCopyKey, "RPCopySilentCopyBtn")
        end
        if RPCopyDB.quickCapture and RPCopyDB.captureTargetKey and RPCopyDB.captureTargetKey ~= "" then
            SetOverrideBindingClick(bindManagerFrame, false, RPCopyDB.captureTargetKey, "RPCopySilentCaptureBtn")
        end
    end
end

bindManagerFrame:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_REGEN_DISABLED" then
        DisarmCtrlCopy()
    elseif event == "PLAYER_REGEN_ENABLED" or event == "PLAYER_LOGIN" then
        UpdateOverrideBindings()
    end
end)

function RPCopy_QuickCopy()
    EnsureUIOptions()
    if copyFrame:IsShown() then
        copyFrame:Hide()
    end
    if ArmCtrlCopy() then
        local keyHint = (RPCopyDB and RPCopyDB.quickCopyKey) or "CTRL-C"
        ShowToast(string.format("|cffffd100Ready:|r Press |cffffd100%s|r now for |cff69ccf0[%s]|r", keyHint, armedTabLabel), 2.5, 0.85, 0.68, 0.30)
    end
end

-- =========================================================
-- Reusable Skill Template Modal (RP Persona OR Adventure Story)
-- =========================================================
local templateFrame = CreateFrame("Frame", "RPCopySkillTemplateFrame", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
templateFrame:SetWidth(610)
templateFrame:SetHeight(460)
templateFrame:SetPoint("CENTER", UIParent, "CENTER", 20, -20)
templateFrame:SetFrameStrata("FULLSCREEN_DIALOG")
templateFrame:SetMovable(true)
templateFrame:EnableMouse(true)
templateFrame:RegisterForDrag("LeftButton")
templateFrame:SetScript("OnDragStart", templateFrame.StartMoving)
templateFrame:SetScript("OnDragStop", templateFrame.StopMovingOrSizing)
templateFrame:Hide()
ApplyDarkGlass(templateFrame, 0.05, 0.06, 0.08, 0.97, 0.78, 0.62, 0.28, 0.75)

local tplTitle = templateFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
tplTitle:SetPoint("TOPLEFT", 14, -12)
tplTitle:SetText("|cffffd100RPCopy - Skill Creator Template (Press Ctrl+C to Copy)|r")

local tplSubTitle = templateFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
tplSubTitle:SetPoint("TOPLEFT", 14, -28)
tplSubTitle:SetText("|cffb0bac5Paste this template into Gemini to generate the skill.|r")

local tplCloseX = CreateSleekButton(templateFrame, 22, 20, "x", "danger")
tplCloseX:SetPoint("TOPRIGHT", -8, -8)
tplCloseX:SetScript("OnClick", function() templateFrame:Hide() end)

local tplBoxBg = CreateFrame("Frame", nil, templateFrame, BackdropTemplateMixin and "BackdropTemplate" or nil)
tplBoxBg:SetPoint("TOPLEFT", 14, -48)
tplBoxBg:SetPoint("BOTTOMRIGHT", -14, 42)
ApplyDarkGlass(tplBoxBg, 0.07, 0.09, 0.12, 0.90, 0.24, 0.28, 0.36, 0.80)

local tplScroll = CreateFrame("ScrollFrame", "RPCopySkillTemplateScroll", tplBoxBg, "UIPanelScrollFrameTemplate")
tplScroll:SetPoint("TOPLEFT", 8, -8)
tplScroll:SetPoint("BOTTOMRIGHT", -28, 8)

local tplEditBox = CreateFrame("EditBox", "RPCopySkillTemplateEditBox", tplScroll)
tplEditBox:SetMultiLine(true)
tplEditBox:SetMaxLetters(0)
tplEditBox:SetFontObject(ChatFontNormal)
tplEditBox:SetWidth(540)
tplEditBox:SetHeight(350)
tplEditBox:SetAutoFocus(true)
tplScroll:SetScrollChild(tplEditBox)

local tplHighlightBtn = CreateSleekButton(templateFrame, 120, 22, "Highlight All", "gold")
tplHighlightBtn:SetPoint("BOTTOMLEFT", 14, 12)
tplHighlightBtn:SetScript("OnClick", function()
    tplEditBox:SetFocus()
    tplEditBox:HighlightText()
end)

local tplCloseBtn = CreateSleekButton(templateFrame, 90, 22, "Close")
tplCloseBtn:SetPoint("BOTTOMRIGHT", -14, 12)
tplCloseBtn:SetScript("OnClick", function()
    templateFrame:Hide()
end)

tplEditBox:SetScript("OnEscapePressed", function()
    templateFrame:Hide()
end)

local function OpenSkillTemplateModal(mode)
    if mode == "STORY" then
        tplTitle:SetText("|cffffd100RPCopy - WoW Adventure Story Skill Template (Press Ctrl+C to Copy)|r")
        tplSubTitle:SetText("|cffb0bac5Paste this template into Gemini once to create the 'wow-adventure-story' skill.|r")
        tplEditBox:SetText(STORY_SKILL_TEMPLATE_TEXT)
    else
        tplTitle:SetText("|cffffd100RPCopy - Character RP Skill Template (Press Ctrl+C to Copy)|r")
        tplSubTitle:SetText("|cffb0bac5Paste this template into Gemini to generate a character RP skill matching your trigger.|r")
        tplEditBox:SetText(RP_SKILL_TEMPLATE_TEXT)
    end
    templateFrame:Show()
    tplEditBox:SetFocus()
    tplEditBox:HighlightText()
end

-- =========================================================
-- Import Adventure Story Modal (Paste Colored LLM Story)
-- =========================================================
local RefreshAdventuresTab

local storyImportFrame = CreateFrame("Frame", "RPCopyStoryImportFrame", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
storyImportFrame:SetWidth(580)
storyImportFrame:SetHeight(420)
storyImportFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 10)
storyImportFrame:SetFrameStrata("FULLSCREEN_DIALOG")
storyImportFrame:SetMovable(true)
storyImportFrame:EnableMouse(true)
storyImportFrame:RegisterForDrag("LeftButton")
storyImportFrame:SetScript("OnDragStart", storyImportFrame.StartMoving)
storyImportFrame:SetScript("OnDragStop", storyImportFrame.StopMovingOrSizing)
storyImportFrame:Hide()
ApplyStoryTomeLook(storyImportFrame)

local impTitle = storyImportFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
impTitle:SetPoint("TOPLEFT", 14, -12)
impTitle:SetText("|cffffd100Import Adventure Chronicle (Paste Colored LLM Story)|r")

local impSubTitle = storyImportFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
impSubTitle:SetPoint("TOPLEFT", 14, -28)
impSubTitle:SetText("|cffd7c4a3Paste the full colored story below (Ctrl+V) and click Save Chronicle.|r")

local impCloseX = CreateSleekButton(storyImportFrame, 22, 20, "x", "danger")
impCloseX:SetPoint("TOPRIGHT", -8, -8)
impCloseX:SetScript("OnClick", function() storyImportFrame:Hide() end)

local impBoxBg = CreateFrame("Frame", nil, storyImportFrame, BackdropTemplateMixin and "BackdropTemplate" or nil)
impBoxBg:SetPoint("TOPLEFT", 14, -48)
impBoxBg:SetPoint("BOTTOMRIGHT", -14, 42)
ApplyDarkGlass(impBoxBg, 0.06, 0.05, 0.04, 0.96, 0.72, 0.56, 0.26, 0.75)

local impScroll = CreateFrame("ScrollFrame", "RPCopyStoryImportScroll", impBoxBg, "UIPanelScrollFrameTemplate")
impScroll:SetPoint("TOPLEFT", 8, -8)
impScroll:SetPoint("BOTTOMRIGHT", -28, 8)

local impEditBox = CreateFrame("EditBox", "RPCopyStoryImportEditBox", impScroll)
impEditBox:SetMultiLine(true)
impEditBox:SetMaxLetters(0)
impEditBox:SetFontObject(ChatFontNormal)
impEditBox:SetWidth(510)
impEditBox:SetHeight(310)
impEditBox:SetAutoFocus(true)
impScroll:SetScrollChild(impEditBox)

impEditBox:SetScript("OnTextChanged", function()
    impScroll:UpdateScrollChildRect()
end)

local impSaveBtn = CreateSleekButton(storyImportFrame, 136, 24, "Save Chronicle", "gold")
impSaveBtn:SetPoint("BOTTOMLEFT", 14, 11)

local impClearInputBtn = CreateSleekButton(storyImportFrame, 96, 24, "Clear Box")
impClearInputBtn:SetPoint("LEFT", impSaveBtn, "RIGHT", 6, 0)
impClearInputBtn:SetScript("OnClick", function()
    impEditBox:SetText("")
    impEditBox:SetFocus()
end)

local impCancelBtn = CreateSleekButton(storyImportFrame, 90, 24, "Cancel", "danger")
impCancelBtn:SetPoint("BOTTOMRIGHT", -14, 11)
impCancelBtn:SetScript("OnClick", function()
    storyImportFrame:Hide()
end)

impEditBox:SetScript("OnEscapePressed", function()
    storyImportFrame:Hide()
end)

local function OpenStoryImportModal(adv)
    if not adv then return end
    storyImportFrame.targetAdvId = adv.id
    impTitle:SetText("|cffffd100Import Chronicle:|r |cfff5e6c8" .. (adv.title or "Adventure") .. "|r")
    impEditBox:SetText("")
    storyImportFrame:Show()
    impEditBox:SetFocus()
end

impSaveBtn:SetScript("OnClick", function()
    local raw = impEditBox:GetText() or ""
    if raw:match("^%s*$") then
        titleText:SetText("|cffffd100RPCopy|r - Paste a story first before saving!")
        return
    end
    if storyImportFrame.targetAdvId and ns.SetAdventureStory(storyImportFrame.targetAdvId, raw) then
        ns.state.adventureViewMode = "STORY"
        storyImportFrame:Hide()
        RefreshAdventuresTab()
        titleText:SetText("|cffffd100RPCopy|r - Adventure chronicle saved to Story tab!")
    end
end)

-- =========================================================
-- VIEW 1: Export Slice View (Dynamic Tabs)
-- =========================================================
local sliceBoxBg = CreateFrame("Frame", nil, copyFrame, BackdropTemplateMixin and "BackdropTemplate" or nil)
sliceBoxBg:SetPoint("TOPLEFT", 14, -64)
sliceBoxBg:SetPoint("BOTTOMRIGHT", -14, 42)
ApplyDarkGlass(sliceBoxBg, 0.07, 0.09, 0.12, 0.90, 0.24, 0.28, 0.36, 0.80)

local scrollFrame = CreateFrame("ScrollFrame", "RPCopyScrollFrame", sliceBoxBg, "UIPanelScrollFrameTemplate")
scrollFrame:SetPoint("TOPLEFT", 8, -8)
scrollFrame:SetPoint("BOTTOMRIGHT", -28, 8)

local editBox = CreateFrame("EditBox", "RPCopyEditBox", scrollFrame)
editBox:SetMultiLine(true)
editBox:SetFontObject(ChatFontNormal)
editBox:SetWidth(610)
editBox:SetHeight(350)
editBox:SetAutoFocus(true)
scrollFrame:SetScrollChild(editBox)

local expandBtn

local function UpdateExpandButtonLabel()
    if not expandBtn then return end
    EnsureUIOptions()
    local defCnt = RPCopyDB.defaultMessages or 3
    local expCnt = RPCopyDB.expandMessages or 6
    if ns.state.isExpanded then
        expandBtn:SetText("Collapse (" .. defCnt .. ")")
        expandBtn:LockHighlight()
    else
        expandBtn:SetText("Expand (" .. expCnt .. ")")
        expandBtn:UnlockHighlight()
    end
end

local function RefreshBox()
    UpdateExpandButtonLabel()
    editBox:SetText(ns.BuildSnapshot(ns.state.activeFilter, ns.state.activeNote, ns.state.isExpanded))
    editBox:SetFocus()
    editBox:HighlightText()
end

-- =========================================================
-- VIEW 2: Companions Tab View (Saved People & RP Notes)
-- =========================================================
local playersView = CreateFrame("Frame", "RPCopyPlayersView", copyFrame)
playersView:SetPoint("TOPLEFT", 14, -62)
playersView:SetPoint("BOTTOMRIGHT", -14, 12)
playersView:Hide()

local pListPanel = CreateFrame("Frame", nil, playersView, BackdropTemplateMixin and "BackdropTemplate" or nil)
pListPanel:SetWidth(195)
pListPanel:SetPoint("TOPLEFT", 0, 0)
pListPanel:SetPoint("BOTTOMLEFT", 0, 0)
ApplyDarkGlass(pListPanel, 0.07, 0.09, 0.12, 0.90, 0.24, 0.28, 0.36, 0.80)

local pListHeader = pListPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
pListHeader:SetPoint("TOPLEFT", 10, -8)
pListHeader:SetText("|cffffd100Saved Companions|r")

local pListScroll = CreateFrame("ScrollFrame", "RPCopyPlayerListScroll", pListPanel, "UIPanelScrollFrameTemplate")
pListScroll:SetPoint("TOPLEFT", 6, -26)
pListScroll:SetPoint("BOTTOMRIGHT", -26, 6)

local pListChild = CreateFrame("Frame", nil, pListScroll)
pListChild:SetSize(160, 10)
pListScroll:SetScrollChild(pListChild)

local editorPanel = CreateFrame("Frame", nil, playersView)
editorPanel:SetPoint("TOPLEFT", pListPanel, "TOPRIGHT", 10, 0)
editorPanel:SetPoint("BOTTOMRIGHT", 0, 0)

local pFirstLbl = editorPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
pFirstLbl:SetPoint("TOPLEFT", 0, -4)
pFirstLbl:SetText("First Name:")

local pLastLbl = editorPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
pLastLbl:SetPoint("TOPLEFT", 126, -4)
pLastLbl:SetText("Last Name:")

local pAutoBtn = CreateSleekButton(editorPanel, 130, 20, "Auto-Update: ON")
pAutoBtn:SetPoint("TOPRIGHT", 0, -2)

local pFirstInput = CreateFrame("EditBox", "RPCopyPFirstInput", editorPanel, "InputBoxTemplate")
pFirstInput:SetSize(114, 22)
pFirstInput:SetPoint("TOPLEFT", 6, -22)
pFirstInput:SetAutoFocus(false)

local pLastInput = CreateFrame("EditBox", "RPCopyPLastInput", editorPanel, "InputBoxTemplate")
pLastInput:SetSize(312, 22)
pLastInput:SetPoint("TOPLEFT", 130, -22)
pLastInput:SetAutoFocus(false)

local pNoteLbl = editorPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
pNoteLbl:SetPoint("TOPLEFT", 0, -48)
pNoteLbl:SetText("Permanent RP Note (editable - never overwritten):")

local pNoteBg = CreateFrame("Frame", nil, editorPanel, BackdropTemplateMixin and "BackdropTemplate" or nil)
pNoteBg:SetHeight(56)
pNoteBg:SetPoint("TOPLEFT", 0, -64)
pNoteBg:SetPoint("TOPRIGHT", 0, -64)
ApplyDarkGlass(pNoteBg, 0.07, 0.09, 0.12, 0.92, 0.24, 0.28, 0.36, 0.80)

local pNoteInput = CreateFrame("EditBox", "RPCopyPNoteInput", pNoteBg)
pNoteInput:SetMultiLine(true)
pNoteInput:SetFontObject(ChatFontNormal)
pNoteInput:SetSize(432, 46)
pNoteInput:SetPoint("TOPLEFT", 6, -5)
pNoteInput:SetAutoFocus(false)

local roBox = CreateFrame("Frame", nil, editorPanel, BackdropTemplateMixin and "BackdropTemplate" or nil)
roBox:SetPoint("TOPLEFT", 0, -126)
roBox:SetPoint("BOTTOMRIGHT", 0, 30)
ApplyDarkGlass(roBox, 0.07, 0.09, 0.12, 0.85, 0.22, 0.25, 0.32, 0.75)

local roLevelText = roBox:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
roLevelText:SetPoint("TOPLEFT", 10, -8)
roLevelText:SetText("|cffffd100Level:|r -")

local roClassText = roBox:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
roClassText:SetPoint("TOPLEFT", 145, -8)
roClassText:SetText("|cffffd100Class:|r -")

local roRaceText = roBox:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
roRaceText:SetPoint("TOPLEFT", 10, -24)
roRaceText:SetWidth(425)
roRaceText:SetJustifyH("LEFT")
roRaceText:SetText("|cffffd100Race:|r -")

local roGuildText = roBox:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
roGuildText:SetPoint("TOPLEFT", 10, -40)
roGuildText:SetWidth(425)
roGuildText:SetJustifyH("LEFT")
roGuildText:SetText("|cffffd100Guild:|r -")

local roSeenText = roBox:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
roSeenText:SetPoint("TOPLEFT", 10, -56)
roSeenText:SetWidth(425)
roSeenText:SetJustifyH("LEFT")
roSeenText:SetText("|cffffd100Last Seen:|r -")

local roChatText = roBox:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
roChatText:SetPoint("TOPLEFT", 10, -74)
roChatText:SetWidth(425)
roChatText:SetHeight(165)
roChatText:SetJustifyH("LEFT")
roChatText:SetJustifyV("TOP")
roChatText:SetText("|cffffd100Latest Chat (max 5):|r None")

local pSmartCaptureBtn = CreateSleekButton(editorPanel, 140, 22, "Capture Target")
pSmartCaptureBtn:SetPoint("BOTTOMLEFT", 0, 2)

local pSaveBtn = CreateSleekButton(editorPanel, 140, 22, "Save Changes", "gold")
pSaveBtn:SetPoint("LEFT", pSmartCaptureBtn, "RIGHT", 6, 0)

local pDelBtn = CreateSleekButton(editorPanel, 120, 22, "Delete", "danger")
pDelBtn:SetPoint("LEFT", pSaveBtn, "RIGHT", 6, 0)

local pRowButtons = {}
LoadPlayerIntoEditor = function(key)
    ns.state.selectedPlayerKey = key
    local data = key and RPCopyDB.players[key]
    if data then
        local fName, lName = ns.SplitFullName(key)
        pFirstInput:SetText(fName)
        pLastInput:SetText(lName)
        pNoteInput:SetText(data.note or "")

        local lvlStr = (data.level and data.level ~= "") and data.level or "-"
        local clsStr = (data.class and data.class ~= "") and ns.ColorizeClass(data.class, data.class) or "-"
        local raceStr = (data.race and data.race ~= "") and data.race or "-"
        local guildStr = (data.guild and data.guild ~= "") and data.guild or "-"
        local seenStr = (data.lastSeen and data.lastSeen ~= "") and data.lastSeen or "Never"
        local chatStr = "None"
        if type(data.chatHistory) == "table" and #data.chatHistory > 0 then
            chatStr = "\n" .. table.concat(data.chatHistory, "\n")
        end

        roLevelText:SetText("|cffffd100Level:|r " .. lvlStr)
        roClassText:SetText("|cffffd100Class:|r " .. clsStr)
        roRaceText:SetText("|cffffd100Race:|r " .. raceStr)
        roGuildText:SetText("|cffffd100Guild:|r " .. guildStr)
        roSeenText:SetText("|cffffd100Last Seen:|r " .. seenStr)
        roChatText:SetText("|cffffd100Latest Chat (max 5):|r " .. chatStr)
    else
        pFirstInput:SetText("")
        pLastInput:SetText("")
        pNoteInput:SetText("")
        roLevelText:SetText("|cffffd100Level:|r -")
        roClassText:SetText("|cffffd100Class:|r -")
        roRaceText:SetText("|cffffd100Race:|r -")
        roGuildText:SetText("|cffffd100Guild:|r -")
        roSeenText:SetText("|cffffd100Last Seen:|r -")
        roChatText:SetText("|cffffd100Latest Chat (max 5):|r None")
    end
end

RefreshPlayersTab = function()
    EnsureUIOptions()
    pAutoBtn:SetText(RPCopyDB.autoUpdateKnown and "Auto-Update: ON" or "Auto-Update: OFF")
    for _, rb in ipairs(pRowButtons) do rb:Hide() end

    local sorted = {}
    for k in pairs(RPCopyDB.players) do table.insert(sorted, k) end
    table.sort(sorted, function(a, b) return a:lower() < b:lower() end)

    for idx, pName in ipairs(sorted) do
        local rb = pRowButtons[idx]
        if not rb then
            rb = CreateSleekButton(pListChild, 158, 22, pName)
            pRowButtons[idx] = rb
        end
        rb:SetPoint("TOPLEFT", 0, -(idx - 1) * 24)
        rb:SetText(pName)
        if ns.state.selectedPlayerKey == pName then rb:LockHighlight() else rb:UnlockHighlight() end
        rb:SetScript("OnClick", function()
            LoadPlayerIntoEditor(pName)
            RefreshPlayersTab()
        end)
        rb:Show()
    end
    pListChild:SetHeight(math.max(10, #sorted * 24))
end

pAutoBtn:SetScript("OnClick", function()
    EnsureUIOptions()
    RPCopyDB.autoUpdateKnown = not RPCopyDB.autoUpdateKnown
    RefreshPlayersTab()
end)

pSmartCaptureBtn:SetScript("OnClick", function()
    local targetName = nil
    if UnitExists("target") and UnitIsPlayer("target") then
        targetName = ns.GetUnitFullName("target")
    elseif ns.state.lastDirectAuthor then
        targetName = ns.state.lastDirectAuthor
    end
    if not targetName then
        titleText:SetText("|cffffd100RPCopy|r - Target a player (or get a whisper/say) first!")
        return
    end
    local key, isNew = ns.SaveOrUpdatePlayer(targetName)
    if key then
        titleText:SetText(isNew and ("|cffffd100RPCopy|r - Added companion: " .. key) or ("|cffffd100RPCopy|r - Updated companion: " .. key))
        LoadPlayerIntoEditor(key)
        RefreshPlayersTab()
    end
end)

pSaveBtn:SetScript("OnClick", function()
    EnsureUIOptions()
    local newName = ns.JoinFullName(pFirstInput:GetText(), pLastInput:GetText())
    if newName == "" then return end

    local existingData = (ns.state.selectedPlayerKey and RPCopyDB.players[ns.state.selectedPlayerKey]) or RPCopyDB.players[newName] or {}
    local updatedEntry = {
        note = (pNoteInput:GetText() or ""):match("^%s*(.-)%s*$"),
        level = existingData.level or "",
        race = existingData.race or "",
        class = existingData.class or "",
        guild = existingData.guild or "",
        chatHistory = existingData.chatHistory or {},
        lastSeen = (existingData.lastSeen and existingData.lastSeen ~= "") and existingData.lastSeen or ns.NowStamp(),
    }

    local visUnit = ns.FindVisibleUnitForPlayer(newName)
    if visUnit then ns.CaptureVisibleUnitFields(visUnit, updatedEntry) end

    if ns.state.selectedPlayerKey and ns.state.selectedPlayerKey ~= newName then
        RPCopyDB.players[ns.state.selectedPlayerKey] = nil
    end

    RPCopyDB.players[newName] = updatedEntry
    ns.state.selectedPlayerKey = newName
    titleText:SetText("|cffffd100RPCopy|r - Saved companion: " .. newName)
    LoadPlayerIntoEditor(newName)
    RefreshPlayersTab()
end)

pDelBtn:SetScript("OnClick", function()
    EnsureUIOptions()
    local nameToDel = ns.state.selectedPlayerKey or ns.JoinFullName(pFirstInput:GetText(), pLastInput:GetText())
    if nameToDel ~= "" and RPCopyDB.players[nameToDel] then
        RPCopyDB.players[nameToDel] = nil
        ns.state.selectedPlayerKey = nil
        LoadPlayerIntoEditor(nil)
        RefreshPlayersTab()
        titleText:SetText("|cffffd100RPCopy|r - Deleted " .. nameToDel)
    end
end)

-- =========================================================
-- VIEW 3: Adventures Tab View (Summary | Full Log | Story)
-- =========================================================
local adventuresView = CreateFrame("Frame", "RPCopyAdventuresView", copyFrame)
adventuresView:SetPoint("TOPLEFT", 14, -62)
adventuresView:SetPoint("BOTTOMRIGHT", -14, 12)
adventuresView:Hide()

local aListPanel = CreateFrame("Frame", nil, adventuresView, BackdropTemplateMixin and "BackdropTemplate" or nil)
aListPanel:SetWidth(232)
aListPanel:SetPoint("TOPLEFT", 0, 0)
aListPanel:SetPoint("BOTTOMLEFT", 0, 0)
ApplyDarkGlass(aListPanel, 0.07, 0.09, 0.12, 0.90, 0.24, 0.28, 0.36, 0.80)

local aListHeader = aListPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
aListHeader:SetPoint("TOPLEFT", 10, -8)
aListHeader:SetText("|cffffd100Recorded Adventures|r")

local aListScroll = CreateFrame("ScrollFrame", "RPCopyAdvListScroll", aListPanel, "UIPanelScrollFrameTemplate")
aListScroll:SetPoint("TOPLEFT", 6, -26)
aListScroll:SetPoint("BOTTOMRIGHT", -26, 6)

local aListChild = CreateFrame("Frame", nil, aListScroll)
aListChild:SetSize(196, 10)
aListScroll:SetScrollChild(aListChild)

local aRightPanel = CreateFrame("Frame", nil, adventuresView)
aRightPanel:SetPoint("TOPLEFT", aListPanel, "TOPRIGHT", 10, 0)
aRightPanel:SetPoint("BOTTOMRIGHT", 0, 0)

local heroCard = CreateFrame("Frame", nil, aRightPanel, BackdropTemplateMixin and "BackdropTemplate" or nil)
heroCard:SetHeight(64)
heroCard:SetPoint("TOPLEFT", 0, 0)
heroCard:SetPoint("TOPRIGHT", 0, 0)
ApplyDarkGlass(heroCard, 0.08, 0.10, 0.14, 0.95, 0.72, 0.58, 0.28, 0.55)

local heroIconFrame = CreateFrame("Frame", nil, heroCard, BackdropTemplateMixin and "BackdropTemplate" or nil)
heroIconFrame:SetSize(46, 46)
heroIconFrame:SetPoint("LEFT", 10, 0)
ApplyDarkGlass(heroIconFrame, 0.04, 0.05, 0.07, 1.0, 0.85, 0.68, 0.30, 0.80)

local heroIcon = heroIconFrame:CreateTexture(nil, "ARTWORK")
heroIcon:SetPoint("TOPLEFT", 2, -2)
heroIcon:SetPoint("BOTTOMRIGHT", -2, 2)
heroIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
heroIcon:SetTexture("Interface\\Icons\\INV_Misc_Map_01")

local heroTitle = heroCard:CreateFontString(nil, "OVERLAY", "GameFontNormal")
heroTitle:SetPoint("TOPLEFT", heroIconFrame, "TOPRIGHT", 10, -1)
heroTitle:SetPoint("TOPRIGHT", -10, -9)
heroTitle:SetJustifyH("LEFT")
heroTitle:SetWordWrap(false)
heroTitle:SetText("|cffffd100No Adventure Selected|r")

local heroMeta = heroCard:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
heroMeta:SetPoint("TOPLEFT", heroIconFrame, "TOPRIGHT", 10, -18)
heroMeta:SetPoint("TOPRIGHT", -10, -26)
heroMeta:SetJustifyH("LEFT")
heroMeta:SetWordWrap(false)
heroMeta:SetText("|cff9aa5b4Select a run on the left or start a new one|r")

local heroStats = heroCard:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
heroStats:SetPoint("TOPLEFT", heroIconFrame, "TOPRIGHT", 10, -34)
heroStats:SetPoint("TOPRIGHT", -10, -42)
heroStats:SetJustifyH("LEFT")
heroStats:SetWordWrap(false)
heroStats:SetText("")

local advSummaryBtn = CreateSleekButton(aRightPanel, 74, 22, "Summary")
advSummaryBtn:SetPoint("TOPLEFT", 0, -70)

local advFullBtn = CreateSleekButton(aRightPanel, 74, 22, "Full Log")
advFullBtn:SetPoint("LEFT", advSummaryBtn, "RIGHT", 4, 0)

local advStoryBtn = CreateSleekButton(aRightPanel, 74, 22, "Story")
advStoryBtn:SetPoint("LEFT", advFullBtn, "RIGHT", 4, 0)

local advDelBtn = CreateSleekButton(aRightPanel, 62, 22, "Delete", "danger")
advDelBtn:SetPoint("TOPRIGHT", 0, -70)

local advSelectAllBtn = CreateSleekButton(aRightPanel, 94, 22, "Highlight All", "gold")
advSelectAllBtn:SetPoint("RIGHT", advDelBtn, "LEFT", -4, 0)

local advReimportBtn = CreateSleekButton(aRightPanel, 108, 22, "Re-Import Story", "gold")
advReimportBtn:SetPoint("RIGHT", advDelBtn, "LEFT", -4, 0)
advReimportBtn:Hide()

local advBoxBg = CreateFrame("Frame", nil, aRightPanel, BackdropTemplateMixin and "BackdropTemplate" or nil)
advBoxBg:SetPoint("TOPLEFT", 0, -98)
advBoxBg:SetPoint("BOTTOMRIGHT", 0, 30)
ApplyDarkGlass(advBoxBg, 0.07, 0.09, 0.12, 0.90, 0.24, 0.28, 0.36, 0.80)

local advScroll = CreateFrame("ScrollFrame", "RPCopyAdvScroll", advBoxBg, "UIPanelScrollFrameTemplate")
advScroll:SetPoint("TOPLEFT", 8, -8)
advScroll:SetPoint("BOTTOMRIGHT", -26, 8)

local advEditBox = CreateFrame("EditBox", "RPCopyAdvEditBox", advScroll)
advEditBox:SetMultiLine(true)
advEditBox:SetMaxLetters(0)
advEditBox:SetFontObject(ChatFontNormal)
advEditBox:SetWidth(374)
advEditBox:SetHeight(240)
advEditBox:SetAutoFocus(false)
advScroll:SetScrollChild(advEditBox)

local storyBoxBg = CreateFrame("Frame", nil, aRightPanel, BackdropTemplateMixin and "BackdropTemplate" or nil)
storyBoxBg:SetPoint("TOPLEFT", 0, -98)
storyBoxBg:SetPoint("BOTTOMRIGHT", 0, 30)
storyBoxBg:Hide()
ApplyStoryTomeLook(storyBoxBg)

local storyInnerBorder = CreateFrame("Frame", nil, storyBoxBg, BackdropTemplateMixin and "BackdropTemplate" or nil)
storyInnerBorder:SetPoint("TOPLEFT", 5, -5)
storyInnerBorder:SetPoint("BOTTOMRIGHT", -5, 5)
ApplyDarkGlass(storyInnerBorder, 0.11, 0.08, 0.06, 0.82, 0.82, 0.65, 0.30, 0.50)

local storyEmptyPane = CreateFrame("Frame", nil, storyInnerBorder)
storyEmptyPane:SetAllPoints(storyInnerBorder)

local emptyBookIcon = storyEmptyPane:CreateTexture(nil, "ARTWORK")
emptyBookIcon:SetSize(36, 36)
emptyBookIcon:SetPoint("TOPLEFT", 16, -16)
emptyBookIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
emptyBookIcon:SetTexture("Interface\\Icons\\INV_Misc_Book_09")

local emptyHeading = storyEmptyPane:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
emptyHeading:SetPoint("TOPLEFT", emptyBookIcon, "TOPRIGHT", 10, -2)
emptyHeading:SetText("|cffffd100No Adventure Chronicle Yet|r")
pcall(emptyHeading.SetFont, emptyHeading, "Fonts\\FRIZQT__.TTF", 15, "")

local emptySubHeading = storyEmptyPane:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
emptySubHeading:SetPoint("TOPLEFT", emptyBookIcon, "TOPRIGHT", 10, -21)
emptySubHeading:SetText("|cffd7c4a3Turn this dungeon run's chatter, wipes, and loot into a colored Warcraft story.|r")

local emptyDivider = storyEmptyPane:CreateTexture(nil, "ARTWORK")
emptyDivider:SetHeight(1)
emptyDivider:SetPoint("TOPLEFT", 16, -60)
emptyDivider:SetPoint("TOPRIGHT", -16, -60)
emptyDivider:SetTexture(SOLID_TEX)
emptyDivider:SetVertexColor(0.82, 0.65, 0.30, 0.45)

local emptyStepsText = storyEmptyPane:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
emptyStepsText:SetPoint("TOPLEFT", 18, -70)
emptyStepsText:SetPoint("TOPRIGHT", -18, -70)
emptyStepsText:SetJustifyH("LEFT")
emptyStepsText:SetSpacing(5)
emptyStepsText:SetText(
    "|cffffd100How to Create & Import Your Adventure Story:|r\n" ..
    "|cfff5e6c81. First-Time Setup:|r Click |cffffd100Story Skill Template|r below and paste it into your AI assistant (like Gemini) to create the colored storyteller skill.\n" ..
    "|cfff5e6c82. Export Run Log:|r Switch to |cff69ccf0Full Log|r, click |cffffd100Highlight All|r, and press |cffffd100Ctrl+C|r to copy all party/say chatter, boss HP events, wipes, and loot.\n" ..
    "|cfff5e6c83. Import Chronicle:|r Paste the log into your AI assistant, copy its colored story, and click |cffffd100Import Story from LLM|r below!"
)

local emptyTemplateBtn = CreateSleekButton(storyEmptyPane, 175, 26, "Story Skill Template", "gold")
emptyTemplateBtn:SetPoint("BOTTOMLEFT", 18, 16)
emptyTemplateBtn:SetScript("OnClick", function()
    OpenSkillTemplateModal("STORY")
end)

local emptyImportBtn = CreateSleekButton(storyEmptyPane, 175, 26, "Import Story from LLM", "gold")
emptyImportBtn:SetPoint("LEFT", emptyTemplateBtn, "RIGHT", 10, 0)

local storyReadPane = CreateFrame("Frame", nil, storyInnerBorder)
storyReadPane:SetAllPoints(storyInnerBorder)
storyReadPane:Hide()

local storyScroll = CreateFrame("ScrollFrame", "RPCopyStoryReadScroll", storyReadPane, "UIPanelScrollFrameTemplate")
storyScroll:SetPoint("TOPLEFT", 14, -12)
storyScroll:SetPoint("BOTTOMRIGHT", -28, 12)

local storyScrollChild = CreateFrame("Frame", nil, storyScroll)
storyScrollChild:SetWidth(350)
storyScrollChild:SetHeight(240)
storyScroll:SetScrollChild(storyScrollChild)

local storyBodyText = storyScrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormal")
storyBodyText:SetPoint("TOPLEFT", 2, -2)
storyBodyText:SetWidth(346)
storyBodyText:SetJustifyH("LEFT")
storyBodyText:SetJustifyV("TOP")
storyBodyText:SetSpacing(5)
storyBodyText:SetTextColor(0.95, 0.92, 0.86)
storyBodyText:SetShadowOffset(1, -1)
storyBodyText:SetShadowColor(0, 0, 0, 0.95)
pcall(storyBodyText.SetFont, storyBodyText, "Fonts\\FRIZQT__.TTF", 13, "")

local advToggleRunBtn = CreateSleekButton(aRightPanel, 132, 22, "Start New Run", "gold")
advToggleRunBtn:SetPoint("BOTTOMLEFT", 0, 2)

local advMarkBtn = CreateSleekButton(aRightPanel, 124, 22, "* Mark Moment")
advMarkBtn:SetPoint("LEFT", advToggleRunBtn, "RIGHT", 5, 0)

local advShotsToggleBtn = CreateSleekButton(aRightPanel, 134, 22, "Auto-Shots: OFF")
advShotsToggleBtn:SetPoint("BOTTOMRIGHT", 0, 2)

local aRunCards = {}

local function CreateAdventureCard(parent)
    local card = CreateFrame("Button", nil, parent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    card:SetSize(196, 46)
    ApplyDarkGlass(card, 0.09, 0.11, 0.15, 0.92, 0.22, 0.25, 0.32, 0.85)

    card.accent = card:CreateTexture(nil, "OVERLAY")
    card.accent:SetWidth(3)
    card.accent:SetPoint("TOPLEFT", 1, -1)
    card.accent:SetPoint("BOTTOMLEFT", 1, 1)
    card.accent:SetTexture(SOLID_TEX)
    card.accent:SetVertexColor(0.90, 0.73, 0.32, 0)

    card.iconFrame = CreateFrame("Frame", nil, card, BackdropTemplateMixin and "BackdropTemplate" or nil)
    card.iconFrame:SetSize(34, 34)
    card.iconFrame:SetPoint("LEFT", 8, 0)
    ApplyDarkGlass(card.iconFrame, 0.04, 0.05, 0.07, 1.0, 0.45, 0.40, 0.26, 0.75)

    card.icon = card.iconFrame:CreateTexture(nil, "ARTWORK")
    card.icon:SetPoint("TOPLEFT", 1, -1)
    card.icon:SetPoint("BOTTOMRIGHT", -1, 1)
    card.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    card.titleLbl = card:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    card.titleLbl:SetPoint("TOPLEFT", card.iconFrame, "TOPRIGHT", 8, -2)
    card.titleLbl:SetPoint("TOPRIGHT", -6, -8)
    card.titleLbl:SetJustifyH("LEFT")
    card.titleLbl:SetWordWrap(false)

    card.subLbl = card:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    card.subLbl:SetPoint("TOPLEFT", card.iconFrame, "TOPRIGHT", 8, -18)
    card.subLbl:SetPoint("TOPRIGHT", -6, -24)
    card.subLbl:SetJustifyH("LEFT")
    card.subLbl:SetWordWrap(false)

    card:SetScript("OnEnter", function(self)
        self:SetBackdropBorderColor(0.90, 0.73, 0.32, 0.90)
        if not self.isSelected then
            self:SetBackdropColor(0.14, 0.17, 0.23, 0.96)
        end
    end)

    card:SetScript("OnLeave", function(self)
        if self.isSelected then
            self:SetBackdropColor(0.16, 0.14, 0.10, 0.96)
            self:SetBackdropBorderColor(0.88, 0.71, 0.30, 0.90)
        else
            self:SetBackdropColor(0.09, 0.11, 0.15, 0.92)
            self:SetBackdropBorderColor(0.22, 0.25, 0.32, 0.85)
        end
    end)

    return card
end

local function GetSelectedAdventureObject()
    local active = ns.GetActiveAdventure()
    if active and ns.state.selectedAdventureId == active.id then
        return active
    end
    for _, adv in ipairs(RPCopyDB.adventures or {}) do
        if adv.id == ns.state.selectedAdventureId then
            return adv
        end
    end
    if active then
        ns.state.selectedAdventureId = active.id
        return active
    end
    if RPCopyDB.adventures and RPCopyDB.adventures[1] then
        ns.state.selectedAdventureId = RPCopyDB.adventures[1].id
        return RPCopyDB.adventures[1]
    end
    return nil
end

local function UpdateHeroHeader(adv, isLive)
    if not adv then
        heroIcon:SetTexture("Interface\\Icons\\INV_Misc_Map_01")
        heroTitle:SetText("|cffffd100No Adventure Selected|r")
        heroMeta:SetText("|cff9aa5b4Enter a dungeon/raid or click 'Start New Run' below|r")
        heroStats:SetText("")
        return
    end

    heroIcon:SetTexture(ns.GetAdventureIcon(adv))
    local livePrefix = isLive and "|cff5cb85c[LIVE]|r " or ""
    local storyBadge = (adv.story and adv.story ~= "") and "  |cffffd100[Chronicle]|r" or ""
    heroTitle:SetText(livePrefix .. "|cffffd100" .. (adv.title or "Adventure") .. "|r" .. storyBadge)

    local durSec = adv.duration or (adv.startTime and (time() - adv.startTime) or 0)
    local reloadText = (adv.reloads and adv.reloads > 0) and string.format("  -  %d reload%s", adv.reloads, adv.reloads == 1 and "" or "s") or ""
    heroMeta:SetText(string.format("|cffb0bac5%s  -  %s  -  %s%s|r",
        adv.zone or "Unknown", adv.startDate or "-", ns.FormatDuration(durSec), reloadText))

    local kills = #(adv.bossKills or {})
    local wipes = adv.wipes or 0
    local deaths = adv.deaths or 0
    local shots = #(adv.shots or {})
    heroStats:SetText(string.format(
        "|cff8f9ba8Kills:|r |cff5cb85c%d|r    |cff8f9ba8Wipes:|r |cffff6b6b%d|r    |cff8f9ba8Deaths:|r |cffffb74d%d|r    |cff8f9ba8Shots:|r |cff69ccf0%d|r",
        kills, wipes, deaths, shots))
end

local optShotsToggleBtn
local optCtrlCToggleBtn
local barCtrlCToggleBtn
local optCopyBindBtn
local optCaptureToggleBtn
local optCaptureBindBtn

local function SyncToggleLabels()
    EnsureUIOptions()
    local shotsOn = RPCopyDB.autoScreenshots and true or false
    local shotsLbl = shotsOn and "|cff5cb85cAuto-Shots: ON|r" or "|cff9aa5b4Auto-Shots: OFF|r"
    if advShotsToggleBtn then
        advShotsToggleBtn:SetText(shotsLbl)
        if shotsOn then advShotsToggleBtn:LockHighlight() else advShotsToggleBtn:UnlockHighlight() end
    end
    if optShotsToggleBtn then
        optShotsToggleBtn:SetText(shotsLbl)
        if shotsOn then optShotsToggleBtn:LockHighlight() else optShotsToggleBtn:UnlockHighlight() end
    end

    local ccOn = RPCopyDB.quickCtrlC and true or false
    local copyKey = RPCopyDB.quickCopyKey or "CTRL-C"
    local barLbl = ccOn and string.format("|cff5cb85c%s Copy: ON|r", copyKey) or string.format("|cff9aa5b4%s Copy: OFF|r", copyKey)
    if barCtrlCToggleBtn then
        barCtrlCToggleBtn:SetText(barLbl)
        if ccOn then barCtrlCToggleBtn:LockHighlight() else barCtrlCToggleBtn:UnlockHighlight() end
    end
    if optCtrlCToggleBtn then
        optCtrlCToggleBtn:SetText(ccOn and "|cff5cb85cQuick Copy: ON|r" or "|cff9aa5b4Quick Copy: OFF|r")
        if ccOn then optCtrlCToggleBtn:LockHighlight() else optCtrlCToggleBtn:UnlockHighlight() end
    end
    if optCopyBindBtn then
        optCopyBindBtn:SetText("|cffffd100" .. copyKey .. "|r")
    end

    local capOn = RPCopyDB.quickCapture and true or false
    local capKey = RPCopyDB.captureTargetKey or "SHIFT-C"
    if optCaptureToggleBtn then
        optCaptureToggleBtn:SetText(capOn and "|cff5cb85cTarget Key: ON|r" or "|cff9aa5b4Target Key: OFF|r")
        if capOn then optCaptureToggleBtn:LockHighlight() else optCaptureToggleBtn:UnlockHighlight() end
    end
    if optCaptureBindBtn then
        optCaptureBindBtn:SetText("|cffffd100" .. capKey .. "|r")
    end
end

local function UpdateStoryScrollHeight()
    local h = storyBodyText:GetStringHeight() or 200
    storyScrollChild:SetHeight(math.max(230, h + 32))
    storyScroll:UpdateScrollChildRect()
end

RefreshAdventuresTab = function()
    EnsureUIOptions()
    SyncToggleLabels()

    local active = ns.GetActiveAdventure()
    if active then
        advToggleRunBtn:SetText("|cffff6b6bEnd & Save Run|r")
        advMarkBtn:Enable()
    else
        advToggleRunBtn:SetText("|cff5cb85cStart New Run|r")
        advMarkBtn:Disable()
    end

    for _, card in ipairs(aRunCards) do card:Hide() end
    local entries = {}
    if active then
        table.insert(entries, { adv = active, isLive = true })
    end
    for _, adv in ipairs(RPCopyDB.adventures or {}) do
        table.insert(entries, { adv = adv, isLive = false })
    end

    for idx, item in ipairs(entries) do
        local adv = item.adv
        local card = aRunCards[idx]
        if not card then
            card = CreateAdventureCard(aListChild)
            aRunCards[idx] = card
        end
        card:SetPoint("TOPLEFT", 0, -(idx - 1) * 50)
        card.icon:SetTexture(ns.GetAdventureIcon(adv))

        local prefix = item.isLive and "|cff5cb85c[LIVE]|r " or ""
        local bookStar = (adv.story and adv.story ~= "") and " |cffffd100*|r" or ""
        card.titleLbl:SetText(prefix .. "|cfff0f4f8" .. (adv.title or "Adventure") .. "|r" .. bookStar)

        local durSec = adv.duration or (adv.startTime and (time() - adv.startTime) or 0)
        local shotsCount = #(adv.shots or {})
        local shotBadge = (shotsCount > 0) and string.format(" - |cff69ccf0%d shot%s|r", shotsCount, shotsCount == 1 and "" or "s") or ""
        card.subLbl:SetText(string.format("|cff8f9ba8%s - %dk - %dw%s|r",
            ns.FormatDuration(durSec), #(adv.bossKills or {}), adv.wipes or 0, shotBadge))

        local selected = (ns.state.selectedAdventureId == adv.id)
        card.isSelected = selected
        if selected then
            card:SetBackdropColor(0.16, 0.14, 0.10, 0.96)
            card:SetBackdropBorderColor(0.88, 0.71, 0.30, 0.90)
            card.accent:SetVertexColor(item.isLive and 0.36 or 0.90, 0.73, 0.32, 1)
        else
            card:SetBackdropColor(0.09, 0.11, 0.15, 0.92)
            card:SetBackdropBorderColor(0.22, 0.25, 0.32, 0.85)
            card.accent:SetVertexColor(0.36, 0.72, 0.36, item.isLive and 0.85 or 0)
        end

        card:SetScript("OnClick", function()
            ns.state.selectedAdventureId = adv.id
            RefreshAdventuresTab()
        end)
        card:Show()
    end
    aListChild:SetHeight(math.max(10, #entries * 50))

    local selectedAdv = GetSelectedAdventureObject()
    local isSelectedLive = (active and selectedAdv and active.id == selectedAdv.id) or false
    UpdateHeroHeader(selectedAdv, isSelectedLive)

    local hasStory = selectedAdv and selectedAdv.story and selectedAdv.story ~= ""
    advStoryBtn:SetText(hasStory and "Story *" or "Story")

    local mode = ns.state.adventureViewMode or "SUMMARY"
    advSummaryBtn:UnlockHighlight()
    advFullBtn:UnlockHighlight()
    advStoryBtn:UnlockHighlight()

    if mode == "STORY" then
        advStoryBtn:LockHighlight()
        advBoxBg:Hide()
        advSelectAllBtn:Hide()
        storyBoxBg:Show()

        if selectedAdv then
            advReimportBtn:Show()
            advReimportBtn:SetText(hasStory and "Re-Import Story" or "Import Story")
            emptyImportBtn:Enable()
        else
            advReimportBtn:Hide()
            emptyImportBtn:Disable()
        end

        if hasStory then
            emptyHeading:SetText("|cffffd100No Adventure Chronicle Yet|r")
            storyEmptyPane:Hide()
            storyReadPane:Show()
            local renderText = (selectedAdv.story or ""):gsub("||", "|"):gsub("★", "*")
            storyBodyText:SetText(renderText)
            UpdateStoryScrollHeight()
            storyScroll:SetVerticalScroll(0)
            if C_Timer and C_Timer.After then
                C_Timer.After(0, UpdateStoryScrollHeight)
            end
        else
            storyReadPane:Hide()
            storyEmptyPane:Show()
            if not selectedAdv then
                emptyHeading:SetText("|cffffd100Select or Start an Adventure First|r")
            else
                emptyHeading:SetText("|cffffd100No Adventure Chronicle Yet|r")
            end
        end
    else
        storyBoxBg:Hide()
        advReimportBtn:Hide()
        advBoxBg:Show()
        advSelectAllBtn:Show()

        if mode == "FULL" then
            advFullBtn:LockHighlight()
            advEditBox:SetText(ns.BuildAdventureFullLog(selectedAdv))
        else
            advSummaryBtn:LockHighlight()
            advEditBox:SetText(ns.BuildAdventureSummary(selectedAdv))
        end
    end
end

advSummaryBtn:SetScript("OnClick", function()
    ns.state.adventureViewMode = "SUMMARY"
    RefreshAdventuresTab()
end)

advFullBtn:SetScript("OnClick", function()
    ns.state.adventureViewMode = "FULL"
    RefreshAdventuresTab()
end)

advStoryBtn:SetScript("OnClick", function()
    ns.state.adventureViewMode = "STORY"
    RefreshAdventuresTab()
end)

emptyImportBtn:SetScript("OnClick", function()
    local adv = GetSelectedAdventureObject()
    if adv then OpenStoryImportModal(adv) end
end)

advReimportBtn:SetScript("OnClick", function()
    local adv = GetSelectedAdventureObject()
    if adv then OpenStoryImportModal(adv) end
end)

advSelectAllBtn:SetScript("OnClick", function()
    advEditBox:SetFocus()
    advEditBox:HighlightText()
    titleText:SetText("|cffffd100RPCopy|r - Adventure text highlighted! Press Ctrl+C to copy.")
end)

advShotsToggleBtn:SetScript("OnClick", function()
    EnsureUIOptions()
    RPCopyDB.autoScreenshots = not RPCopyDB.autoScreenshots
    RefreshAdventuresTab()
    titleText:SetText(RPCopyDB.autoScreenshots
        and "|cffffd100RPCopy|r - Auto-Screenshots enabled for active runs."
        or "|cffffd100RPCopy|r - Auto-Screenshots disabled.")
end)

advToggleRunBtn:SetScript("OnClick", function()
    if ns.GetActiveAdventure() then
        local saved = ns.EndAdventure("Ended Manually")
        if saved then
            titleText:SetText("|cffffd100RPCopy|r - Saved adventure: " .. saved.title)
        end
    else
        local newRun = ns.StartAdventure(nil, false)
        ns.state.selectedAdventureId = newRun.id
        titleText:SetText("|cffffd100RPCopy|r - Recording adventure: " .. newRun.title)
    end
    RefreshAdventuresTab()
end)

advMarkBtn:SetScript("OnClick", function()
    local ok, msg = ns.MarkAdventureHighlight(nil)
    titleText:SetText("|cffffd100RPCopy|r - " .. msg)
    if ok then RefreshAdventuresTab() end
end)

advDelBtn:SetScript("OnClick", function()
    local active = ns.GetActiveAdventure()
    if active and ns.state.selectedAdventureId == active.id then
        titleText:SetText("|cffffd100RPCopy|r - End the live run before deleting it.")
        return
    end
    for i, adv in ipairs(RPCopyDB.adventures or {}) do
        if adv.id == ns.state.selectedAdventureId then
            table.remove(RPCopyDB.adventures, i)
            ns.state.selectedAdventureId = nil
            titleText:SetText("|cffffd100RPCopy|r - Adventure deleted.")
            RefreshAdventuresTab()
            return
        end
    end
end)

-- =========================================================
-- VIEW 4: Options & Tab Customizer View (with Keybindings)
-- =========================================================
local RebuildNavTabs
local SetActiveTab

local optionsView = CreateFrame("Frame", "RPCopyOptionsView", copyFrame)
optionsView:SetPoint("TOPLEFT", 14, -62)
optionsView:SetPoint("BOTTOMRIGHT", -14, 12)
optionsView:Hide()

-- Row 1: Global Message Limits, Auto-Shots & Reset Tabs
local optGlobalBar = CreateFrame("Frame", nil, optionsView, BackdropTemplateMixin and "BackdropTemplate" or nil)
optGlobalBar:SetHeight(30)
optGlobalBar:SetPoint("TOPLEFT", 0, 0)
optGlobalBar:SetPoint("TOPRIGHT", 0, 0)
ApplyDarkGlass(optGlobalBar, 0.07, 0.09, 0.12, 0.90, 0.24, 0.28, 0.36, 0.80)

local defMsgLbl = optGlobalBar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
defMsgLbl:SetPoint("LEFT", 8, 0)
defMsgLbl:SetText("Default Msgs:")

local defMsgInput = CreateFrame("EditBox", "RPCopyOptDefMsgs", optGlobalBar, "InputBoxTemplate")
defMsgInput:SetSize(26, 20)
defMsgInput:SetPoint("LEFT", defMsgLbl, "RIGHT", 4, 0)
defMsgInput:SetAutoFocus(false)

local expMsgLbl = optGlobalBar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
expMsgLbl:SetPoint("LEFT", defMsgInput, "RIGHT", 10, 0)
expMsgLbl:SetText("Expand Msgs:")

local expMsgInput = CreateFrame("EditBox", "RPCopyOptExpMsgs", optGlobalBar, "InputBoxTemplate")
expMsgInput:SetSize(26, 20)
expMsgInput:SetPoint("LEFT", expMsgLbl, "RIGHT", 4, 0)
expMsgInput:SetAutoFocus(false)

local saveLimitsBtn = CreateSleekButton(optGlobalBar, 52, 20, "Save")
saveLimitsBtn:SetPoint("LEFT", expMsgInput, "RIGHT", 6, 0)

optShotsToggleBtn = CreateSleekButton(optGlobalBar, 122, 20, "Auto-Shots: OFF")
optShotsToggleBtn:SetPoint("LEFT", saveLimitsBtn, "RIGHT", 10, 0)
optShotsToggleBtn:SetScript("OnClick", function()
    EnsureUIOptions()
    RPCopyDB.autoScreenshots = not RPCopyDB.autoScreenshots
    SyncToggleLabels()
    titleText:SetText(RPCopyDB.autoScreenshots
        and "|cffffd100RPCopy|r - Auto-Screenshots enabled for active runs."
        or "|cffffd100RPCopy|r - Auto-Screenshots disabled.")
end)

local resetTabsBtn = CreateSleekButton(optGlobalBar, 92, 20, "Reset Tabs", "danger")
resetTabsBtn:SetPoint("RIGHT", -6, 0)

-- Row 2: Keybindings Bar (Quick Copy & Capture Target)
local optKeybindBar = CreateFrame("Frame", nil, optionsView, BackdropTemplateMixin and "BackdropTemplate" or nil)
optKeybindBar:SetHeight(30)
optKeybindBar:SetPoint("TOPLEFT", 0, -34)
optKeybindBar:SetPoint("TOPRIGHT", 0, -34)
ApplyDarkGlass(optKeybindBar, 0.07, 0.09, 0.12, 0.90, 0.24, 0.28, 0.36, 0.80)

local kbQuickLbl = optKeybindBar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
kbQuickLbl:SetPoint("LEFT", 8, 0)
kbQuickLbl:SetText("|cffffd100Quick Copy:|r")

optCtrlCToggleBtn = CreateSleekButton(optKeybindBar, 108, 20, "Quick Copy: ON")
optCtrlCToggleBtn:SetPoint("LEFT", kbQuickLbl, "RIGHT", 6, 0)
optCtrlCToggleBtn:SetScript("OnClick", function()
    EnsureUIOptions()
    RPCopyDB.quickCtrlC = not RPCopyDB.quickCtrlC
    if not RPCopyDB.quickCtrlC then DisarmCtrlCopy() end
    UpdateOverrideBindings()
    SyncToggleLabels()
    titleText:SetText(RPCopyDB.quickCtrlC
        and "|cffffd100RPCopy|r - Quick Copy shortcut enabled!"
        or "|cffffd100RPCopy|r - Quick Copy shortcut disabled.")
end)

optCopyBindBtn = CreateSleekButton(optKeybindBar, 84, 20, "CTRL-C", "gold")
optCopyBindBtn:SetPoint("LEFT", optCtrlCToggleBtn, "RIGHT", 4, 0)

local kbCapLbl = optKeybindBar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
kbCapLbl:SetPoint("LEFT", optCopyBindBtn, "RIGHT", 14, 0)
kbCapLbl:SetText("|cffffd100Capture Target:|r")

optCaptureToggleBtn = CreateSleekButton(optKeybindBar, 110, 20, "Target Key: ON")
optCaptureToggleBtn:SetPoint("LEFT", kbCapLbl, "RIGHT", 6, 0)
optCaptureToggleBtn:SetScript("OnClick", function()
    EnsureUIOptions()
    RPCopyDB.quickCapture = not RPCopyDB.quickCapture
    UpdateOverrideBindings()
    SyncToggleLabels()
    titleText:SetText(RPCopyDB.quickCapture
        and "|cffffd100RPCopy|r - Target Capture shortcut enabled!"
        or "|cffffd100RPCopy|r - Target Capture shortcut disabled.")
end)

optCaptureBindBtn = CreateSleekButton(optKeybindBar, 84, 20, "SHIFT-C", "gold")
optCaptureBindBtn:SetPoint("LEFT", optCaptureToggleBtn, "RIGHT", 4, 0)

local resetKeysBtn = CreateSleekButton(optKeybindBar, 84, 20, "Reset Keys")
resetKeysBtn:SetPoint("RIGHT", -6, 0)
resetKeysBtn:SetScript("OnClick", function()
    EnsureUIOptions()
    RPCopyDB.quickCtrlC = true
    RPCopyDB.quickCopyKey = "CTRL-C"
    RPCopyDB.quickCapture = true
    RPCopyDB.captureTargetKey = "SHIFT-C"
    UpdateOverrideBindings()
    SyncToggleLabels()
    titleText:SetText("|cffffd100RPCopy|r - Reset shortcuts to CTRL-C and SHIFT-C.")
end)

-- Safe Key-Capture Overlay Frame (captures next key combo without protected calls)
local keyCaptureFrame = CreateFrame("Frame", "RPCopyKeyCaptureModal", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
keyCaptureFrame:SetSize(340, 82)
keyCaptureFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 40)
keyCaptureFrame:SetFrameStrata("FULLSCREEN_DIALOG")
keyCaptureFrame:Hide()
ApplyDarkGlass(keyCaptureFrame, 0.06, 0.08, 0.12, 0.98, 0.90, 0.73, 0.32, 0.95)

local kcTitle = keyCaptureFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
kcTitle:SetPoint("TOP", 0, -14)
kcTitle:SetText("|cffffd100Press Any Key Combination...|r")

local kcSub = keyCaptureFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
kcSub:SetPoint("TOP", 0, -36)
kcSub:SetText("|cffb0bac5(e.g. CTRL-C, SHIFT-C, ALT-R)  -  Press ESC to cancel|r")

local IGNORED_KEYS = {
    LSHIFT = true, RSHIFT = true,
    LCTRL = true, RCTRL = true,
    LALT = true, RALT = true,
    UNKNOWN = true,
}

local function StartKeyBindCapture(dbField, actionLabel)
    if InCombatLockdown and InCombatLockdown() then
        titleText:SetText("|cffffd100RPCopy|r - Cannot change keybindings during combat.")
        return
    end
    keyCaptureFrame.targetField = dbField
    kcTitle:SetText("|cffffd100Press Key for " .. actionLabel .. "...|r")
    keyCaptureFrame:Show()
end

keyCaptureFrame:SetScript("OnKeyDown", function(self, key)
    if not self:IsShown() then return end
    if key == "ESCAPE" then
        self:Hide()
        titleText:SetText("|cffffd100RPCopy|r - Keybind change cancelled.")
        return
    end
    if IGNORED_KEYS[key] then return end

    local combo = ""
    if IsAltKeyDown() then combo = combo .. "ALT-" end
    if IsControlKeyDown() then combo = combo .. "CTRL-" end
    if IsShiftKeyDown() then combo = combo .. "SHIFT-" end
    combo = combo .. key

    EnsureUIOptions()
    if self.targetField then
        RPCopyDB[self.targetField] = combo
    end
    self:Hide()
    UpdateOverrideBindings()
    SyncToggleLabels()
    titleText:SetText("|cffffd100RPCopy|r - Bound shortcut to |cff69ccf0" .. combo .. "|r!")
end)

optCopyBindBtn:SetScript("OnClick", function()
    StartKeyBindCapture("quickCopyKey", "Quick Copy")
end)

optCaptureBindBtn:SetScript("OnClick", function()
    StartKeyBindCapture("captureTargetKey", "Capture Target")
end)

-- Custom Tabs List & Editor (starts at -68 below the two top bars)
local oListPanel = CreateFrame("Frame", nil, optionsView, BackdropTemplateMixin and "BackdropTemplate" or nil)
oListPanel:SetWidth(195)
oListPanel:SetPoint("TOPLEFT", 0, -68)
oListPanel:SetPoint("BOTTOMLEFT", 0, 0)
ApplyDarkGlass(oListPanel, 0.07, 0.09, 0.12, 0.90, 0.24, 0.28, 0.36, 0.80)

local oListHeader = oListPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
oListHeader:SetPoint("TOPLEFT", 10, -8)
oListHeader:SetText("|cffffd100Custom Tabs|r")

local oAddTabBtn = CreateSleekButton(oListPanel, 54, 18, "+ New", "gold")
oAddTabBtn:SetPoint("TOPRIGHT", -6, -5)

local oListScroll = CreateFrame("ScrollFrame", "RPCopyOptListScroll", oListPanel, "UIPanelScrollFrameTemplate")
oListScroll:SetPoint("TOPLEFT", 6, -26)
oListScroll:SetPoint("BOTTOMRIGHT", -26, 6)

local oListChild = CreateFrame("Frame", nil, oListScroll)
oListChild:SetSize(160, 10)
oListScroll:SetScrollChild(oListChild)

local oEditorPanel = CreateFrame("Frame", nil, optionsView)
oEditorPanel:SetPoint("TOPLEFT", oListPanel, "TOPRIGHT", 10, 0)
oEditorPanel:SetPoint("BOTTOMRIGHT", 0, 0)

local oNameLbl = oEditorPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
oNameLbl:SetPoint("TOPLEFT", 0, -2)
oNameLbl:SetText("Tab Button Name:")

local oNameInput = CreateFrame("EditBox", "RPCopyOptTabName", oEditorPanel, "InputBoxTemplate")
oNameInput:SetSize(180, 20)
oNameInput:SetPoint("TOPLEFT", 6, -16)
oNameInput:SetAutoFocus(false)

local oMoveUpBtn = CreateSleekButton(oEditorPanel, 64, 20, "Move Up")
oMoveUpBtn:SetPoint("TOPRIGHT", -68, -16)

local oMoveDownBtn = CreateSleekButton(oEditorPanel, 64, 20, "Down")
oMoveDownBtn:SetPoint("TOPRIGHT", 0, -16)

local oPrefixLbl = oEditorPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
oPrefixLbl:SetPoint("TOPLEFT", 0, -42)
oPrefixLbl:SetText("Top Constant / Skill Trigger (Line 1):")

local oPrefixInput = CreateFrame("EditBox", "RPCopyOptTabPrefix", oEditorPanel, "InputBoxTemplate")
oPrefixInput:SetSize(436, 20)
oPrefixInput:SetPoint("TOPLEFT", 6, -56)
oPrefixInput:SetAutoFocus(false)

local oPrefixTip = oEditorPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
oPrefixTip:SetPoint("TOPLEFT", 0, -80)
oPrefixTip:SetWidth(442)
oPrefixTip:SetJustifyH("LEFT")
oPrefixTip:SetText("|cffffd100Tip:|r Default is |cff69ccf0use aloria|r. Change it for another character (e.g. |cff69ccf0use elaini|r), or clear it to export raw data.")

local oSourcesLbl = oEditorPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
oSourcesLbl:SetPoint("TOPLEFT", 0, -110)
oSourcesLbl:SetText("Included Context & Message Logs:")

local SOURCE_DEFS = {
    { key = "incDirect",    label = "Direct Msg (Last Whisper/Say)" },
    { key = "incTarget",    label = "Target Info" },
    { key = "incParty",     label = "Party Roster" },
    { key = "incStatus",    label = "My Status & Pet" },
    { key = "incQuest",     label = "Active Quest Info" },
    { key = "incCombat",    label = "Combat & Deaths" },
    { key = "incSocial",    label = "Social Chat (Say/Yell/W)" },
    { key = "incOoc",       label = "OOC Channel ([OOC])" },
    { key = "incPartyChat", label = "Party / Raid Chat" },
    { key = "incNpc",       label = "NPC Dialogue" },
    { key = "incLoot",      label = "Loot Log" },
}

local oCheckboxes = {}
for idx, sDef in ipairs(SOURCE_DEFS) do
    local cb = CreateFrame("CheckButton", "RPCopyOptCB_" .. sDef.key, oEditorPanel, "UICheckButtonTemplate")
    cb:SetSize(20, 20)
    local col = (idx <= 6) and 0 or 1
    local row = (idx <= 6) and (idx - 1) or (idx - 7)
    cb:SetPoint("TOPLEFT", col * 220, -126 - (row * 22))
    local lbl = cb:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    lbl:SetPoint("LEFT", cb, "RIGHT", 4, 0)
    lbl:SetText(sDef.label)
    oCheckboxes[sDef.key] = cb
end

local oSaveTabBtn = CreateSleekButton(oEditorPanel, 108, 22, "Save Tab", "gold")
oSaveTabBtn:SetPoint("BOTTOMLEFT", 0, 2)

local oDelTabBtn = CreateSleekButton(oEditorPanel, 94, 22, "Delete Tab", "danger")
oDelTabBtn:SetPoint("LEFT", oSaveTabBtn, "RIGHT", 5, 0)

local oStoryTplBtn = CreateSleekButton(oEditorPanel, 118, 22, "Story Template", "gold")
oStoryTplBtn:SetPoint("BOTTOMRIGHT", 0, 2)
oStoryTplBtn:SetScript("OnClick", function()
    OpenSkillTemplateModal("STORY")
end)

local oTemplateBtn = CreateSleekButton(oEditorPanel, 110, 22, "RP Template", "gold")
oTemplateBtn:SetPoint("RIGHT", oStoryTplBtn, "LEFT", -5, 0)
oTemplateBtn:SetScript("OnClick", function()
    OpenSkillTemplateModal("RP")
end)

local oRowButtons = {}
local function GetSelectedOptionTab()
    EnsureUIOptions()
    for idx, t in ipairs(RPCopyDB.tabs) do
        if t.id == ns.state.selectedOptionTabId then
            return t, idx
        end
    end
    ns.state.selectedOptionTabId = RPCopyDB.tabs[1].id
    return RPCopyDB.tabs[1], 1
end

local function LoadOptionTabIntoEditor(tabCfg)
    if not tabCfg then return end
    ns.state.selectedOptionTabId = tabCfg.id
    oNameInput:SetText(tabCfg.label or "")
    oPrefixInput:SetText(tabCfg.prefix or "")
    for _, sDef in ipairs(SOURCE_DEFS) do
        oCheckboxes[sDef.key]:SetChecked(tabCfg[sDef.key] and true or false)
    end
end

local function RefreshOptionsTab()
    EnsureUIOptions()
    SyncToggleLabels()
    defMsgInput:SetText(tostring(RPCopyDB.defaultMessages or 3))
    expMsgInput:SetText(tostring(RPCopyDB.expandMessages or 6))

    local selTab = GetSelectedOptionTab()
    LoadOptionTabIntoEditor(selTab)

    for _, rb in ipairs(oRowButtons) do rb:Hide() end
    for idx, t in ipairs(RPCopyDB.tabs) do
        local rb = oRowButtons[idx]
        if not rb then
            rb = CreateSleekButton(oListChild, 158, 22, t.label)
            oRowButtons[idx] = rb
        end
        rb:SetPoint("TOPLEFT", 0, -(idx - 1) * 24)
        rb:SetText(t.label)
        if ns.state.selectedOptionTabId == t.id then rb:LockHighlight() else rb:UnlockHighlight() end
        rb:SetScript("OnClick", function()
            ns.state.selectedOptionTabId = t.id
            RefreshOptionsTab()
        end)
        rb:Show()
    end
    oListChild:SetHeight(math.max(10, #RPCopyDB.tabs * 24))
end

saveLimitsBtn:SetScript("OnClick", function()
    EnsureUIOptions()
    local dVal = math.max(1, math.min(10, tonumber(defMsgInput:GetText()) or 3))
    local eVal = math.max(1, math.min(20, tonumber(expMsgInput:GetText()) or 6))
    RPCopyDB.defaultMessages = dVal
    RPCopyDB.expandMessages = eVal
    defMsgInput:SetText(tostring(dVal))
    expMsgInput:SetText(tostring(eVal))
    UpdateExpandButtonLabel()
    titleText:SetText(string.format("|cffffd100RPCopy|r - Saved limits (Default: %d, Expand: %d)", dVal, eVal))
end)

resetTabsBtn:SetScript("OnClick", function()
    ns.ResetDefaultTabs()
    RebuildNavTabs()
    RefreshOptionsTab()
    titleText:SetText("|cffffd100RPCopy|r - Reset slice tabs to defaults.")
end)

oAddTabBtn:SetScript("OnClick", function()
    EnsureUIOptions()
    local newId = "CUSTOM_" .. tostring(time()) .. "_" .. tostring(math.random(10, 99))
    local newTab = {
        id = newId,
        label = "Custom " .. tostring(#RPCopyDB.tabs + 1),
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
    }
    table.insert(RPCopyDB.tabs, newTab)
    ns.state.selectedOptionTabId = newId
    RebuildNavTabs()
    RefreshOptionsTab()
    titleText:SetText("|cffffd100RPCopy|r - Created new tab! Configure and click Save Tab.")
end)

oSaveTabBtn:SetScript("OnClick", function()
    local tabCfg = GetSelectedOptionTab()
    if not tabCfg then return end
    local newLbl = (oNameInput:GetText() or ""):match("^%s*(.-)%s*$")
    if newLbl ~= "" then tabCfg.label = newLbl end
    tabCfg.prefix = (oPrefixInput:GetText() or ""):match("^%s*(.-)%s*$")
    for _, sDef in ipairs(SOURCE_DEFS) do
        tabCfg[sDef.key] = oCheckboxes[sDef.key]:GetChecked() and true or false
    end
    RebuildNavTabs()
    RefreshOptionsTab()
    titleText:SetText("|cffffd100RPCopy|r - Saved tab settings for '" .. tabCfg.label .. "'!")
end)

oMoveUpBtn:SetScript("OnClick", function()
    local _, idx = GetSelectedOptionTab()
    if idx and idx > 1 then
        RPCopyDB.tabs[idx], RPCopyDB.tabs[idx - 1] = RPCopyDB.tabs[idx - 1], RPCopyDB.tabs[idx]
        RebuildNavTabs()
        RefreshOptionsTab()
    end
end)

oMoveDownBtn:SetScript("OnClick", function()
    local _, idx = GetSelectedOptionTab()
    if idx and idx < #RPCopyDB.tabs then
        RPCopyDB.tabs[idx], RPCopyDB.tabs[idx + 1] = RPCopyDB.tabs[idx + 1], RPCopyDB.tabs[idx]
        RebuildNavTabs()
        RefreshOptionsTab()
    end
end)

oDelTabBtn:SetScript("OnClick", function()
    EnsureUIOptions()
    if #RPCopyDB.tabs <= 1 then
        titleText:SetText("|cffffd100RPCopy|r - You must keep at least one slice tab.")
        return
    end
    local _, idx = GetSelectedOptionTab()
    if idx then
        local removed = table.remove(RPCopyDB.tabs, idx)
        ns.state.selectedOptionTabId = RPCopyDB.tabs[1].id
        if ns.state.activeFilter == removed.id then
            ns.state.activeFilter = RPCopyDB.tabs[1].id
        end
        RebuildNavTabs()
        RefreshOptionsTab()
        titleText:SetText("|cffffd100RPCopy|r - Deleted tab '" .. (removed.label or "") .. "'.")
    end
end)

-- =========================================================
-- Separated Navigation Bar: RP Slices (Left) | Tools (Right)
-- =========================================================
local bottomWidgets = {}
local sliceNavButtons = {}
local toolNavButtons = {}
local navButtonKeyMap = {}

local TOOL_TABS = {
    { key = "PLAYERS",    label = "Companions" },
    { key = "ADVENTURES", label = "Adventures" },
    { key = "OPTIONS",    label = "Options" },
}

local function ApplyContentTopOffset(topOffset)
    sliceBoxBg:ClearAllPoints()
    sliceBoxBg:SetPoint("TOPLEFT", 14, topOffset)
    sliceBoxBg:SetPoint("BOTTOMRIGHT", -14, 42)

    playersView:ClearAllPoints()
    playersView:SetPoint("TOPLEFT", 14, topOffset + 2)
    playersView:SetPoint("BOTTOMRIGHT", -14, 12)

    adventuresView:ClearAllPoints()
    adventuresView:SetPoint("TOPLEFT", 14, topOffset + 2)
    adventuresView:SetPoint("BOTTOMRIGHT", -14, 12)

    optionsView:ClearAllPoints()
    optionsView:SetPoint("TOPLEFT", 14, topOffset + 2)
    optionsView:SetPoint("BOTTOMRIGHT", -14, 12)
end

SetActiveTab = function(tabKey)
    ns.state.activeFilter = tabKey
    for key, btn in pairs(navButtonKeyMap) do
        if key == tabKey then btn:LockHighlight() else btn:UnlockHighlight() end
    end

    sliceBoxBg:Hide()
    playersView:Hide()
    adventuresView:Hide()
    optionsView:Hide()
    for _, w in ipairs(bottomWidgets) do w:Hide() end

    if tabKey == "PLAYERS" then
        editBox:ClearFocus()
        playersView:Show()
        titleText:SetText("|cffffd100RPCopy|r |cffd8dee9- Companions & RP Notes|r")
        if UnitExists("target") and UnitIsPlayer("target") then
            local tName = ns.GetUnitFullName("target")
            local k = ns.FindPlayerKey(tName, true)
            if k then
                if RPCopyDB.autoUpdateKnown then
                    ns.CaptureVisibleUnitFields("target", RPCopyDB.players[k])
                end
                LoadPlayerIntoEditor(k)
            end
        end
        RefreshPlayersTab()
    elseif tabKey == "ADVENTURES" then
        editBox:ClearFocus()
        adventuresView:Show()
        titleText:SetText("|cffffd100RPCopy|r |cffd8dee9- Adventures Chronicle & Story Reader|r")
        RefreshAdventuresTab()
    elseif tabKey == "OPTIONS" then
        editBox:ClearFocus()
        optionsView:Show()
        titleText:SetText("|cffffd100RPCopy|r |cffd8dee9- Addon Settings, Keybindings & Custom Tabs|r")
        RefreshOptionsTab()
    else
        RPCopyDB.lastSliceId = tabKey
        sliceBoxBg:Show()
        for _, w in ipairs(bottomWidgets) do w:Show() end
        SyncToggleLabels()
        titleText:SetText("|cffffd100RPCopy|r |cffd8dee9- Pick a Slice & Press Ctrl+C (Esc to Close)|r")
        RefreshBox()
    end
end

RebuildNavTabs = function()
    EnsureUIOptions()
    for _, b in ipairs(sliceNavButtons) do b:Hide() end
    for _, b in ipairs(toolNavButtons) do b:Hide() end
    navButtonKeyMap = {}

    local rightOffset = -14
    for idx = #TOOL_TABS, 1, -1 do
        local item = TOOL_TABS[idx]
        local btn = toolNavButtons[idx]
        if not btn then
            btn = CreateSleekButton(copyFrame, 76, 22, item.label, "tool")
            toolNavButtons[idx] = btn
        end
        local w = math.max(66, #item.label * 7 + 18)
        btn:ClearAllPoints()
        btn:SetWidth(w)
        btn:SetPoint("TOPRIGHT", rightOffset, -36)
        btn:SetText(item.label)
        btn:SetScript("OnClick", function()
            SetActiveTab(item.key)
        end)
        if ns.state.activeFilter == item.key then
            btn:LockHighlight()
        else
            btn:UnlockHighlight()
        end
        btn:Show()
        navButtonKeyMap[item.key] = btn
        rightOffset = rightOffset - w - 4
    end

    navDivider:ClearAllPoints()
    navDivider:SetPoint("TOPRIGHT", rightOffset - 6, -36)
    navDivider:Show()

    local maxSliceRight = copyFrame:GetWidth() + rightOffset - 16
    local curX = 14
    local curY = -36
    local rows = 1

    for idx, t in ipairs(RPCopyDB.tabs) do
        local btn = sliceNavButtons[idx]
        if not btn then
            btn = CreateSleekButton(copyFrame, 60, 22, t.label)
            sliceNavButtons[idx] = btn
        end
        local w = math.max(52, #t.label * 7 + 18)
        if (curX + w) > maxSliceRight and curX > 14 then
            curX = 14
            curY = curY - 25
            rows = rows + 1
        end
        btn:ClearAllPoints()
        btn:SetWidth(w)
        btn:SetPoint("TOPLEFT", curX, curY)
        btn:SetText(t.label)
        btn:SetScript("OnClick", function()
            SetActiveTab(t.id)
        end)
        if ns.state.activeFilter == t.id then
            btn:LockHighlight()
        else
            btn:UnlockHighlight()
        end
        btn:Show()
        navButtonKeyMap[t.id] = btn
        curX = curX + w + 4
    end

    ApplyContentTopOffset(rows > 1 and -91 or -66)
end

-- =========================================================
-- Bottom Action Bar for Slice Tabs
-- =========================================================
expandBtn = CreateSleekButton(copyFrame, 102, 22, "Expand (6)")
expandBtn:SetPoint("BOTTOMLEFT", 14, 12)
expandBtn:SetScript("OnClick", function()
    ns.state.isExpanded = not ns.state.isExpanded
    RefreshBox()
end)
table.insert(bottomWidgets, expandBtn)

barCtrlCToggleBtn = CreateSleekButton(copyFrame, 142, 22, "CTRL-C Copy: ON")
barCtrlCToggleBtn:SetPoint("LEFT", expandBtn, "RIGHT", 6, 0)
barCtrlCToggleBtn:SetScript("OnClick", function()
    EnsureUIOptions()
    RPCopyDB.quickCtrlC = not RPCopyDB.quickCtrlC
    if not RPCopyDB.quickCtrlC then DisarmCtrlCopy() end
    UpdateOverrideBindings()
    SyncToggleLabels()
    titleText:SetText(RPCopyDB.quickCtrlC
        and "|cffffd100RPCopy|r - Quick Copy shortcut enabled!"
        or "|cffffd100RPCopy|r - Quick Copy shortcut disabled.")
end)
table.insert(bottomWidgets, barCtrlCToggleBtn)

local clearBtn = CreateSleekButton(copyFrame, 94, 22, "Clear Logs", "danger")
clearBtn:SetPoint("BOTTOMRIGHT", -14, 12)
clearBtn:SetScript("OnClick", function()
    ns.ClearSessionLogs()
    RefreshBox()
end)
table.insert(bottomWidgets, clearBtn)

editBox:SetScript("OnEscapePressed", function() copyFrame:Hide() end)
editBox:SetScript("OnKeyDown", function(_, key)
    if key == "C" and IsControlKeyDown() then
        local f = ns.state.activeFilter
        if f ~= "PLAYERS" and f ~= "ADVENTURES" and f ~= "OPTIONS" and (not copyFrame.openedAt or (GetTime() - copyFrame.openedAt) > 0.25) then
            copyFrame.closeDelay = 0.15
        end
    end
end)

copyFrame:SetScript("OnUpdate", function(self, elapsed)
    if self.closeDelay then
        self.closeDelay = self.closeDelay - elapsed
        if self.closeDelay <= 0 then
            self.closeDelay = nil
            self:Hide()
        end
    end
end)

-- Draggable Mini [RP] Button (Dark-Glass Styled)
local miniBtn = CreateSleekButton(UIParent, 38, 22, "|cffffd100RP|r", "gold")
miniBtn:SetPoint("CENTER", UIParent, "CENTER", -300, -180)
miniBtn:SetMovable(true)
miniBtn:EnableMouse(true)
miniBtn:RegisterForDrag("LeftButton")
miniBtn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
miniBtn:SetScript("OnDragStart", miniBtn.StartMoving)
miniBtn:SetScript("OnDragStop", miniBtn.StopMovingOrSizing)
miniBtn:SetScript("OnClick", function(_, button)
    if button == "RightButton" then
        ns.ClearSessionLogs()
        print("|cff00ff00[RPCopy]|r All logs cleared.")
    else
        RPCopy_Toggle()
    end
end)

function RPCopy_Open(note)
    EnsureUIOptions()
    DisarmCtrlCopy()
    copyFrame.closeDelay = nil
    copyFrame.openedAt = GetTime()
    ns.state.activeNote = note or ""
    ns.state.isExpanded = false
    local firstTabId = (RPCopyDB.tabs[1] and RPCopyDB.tabs[1].id) or "SMART"
    RebuildNavTabs()
    copyFrame:Show()
    SetActiveTab(firstTabId)
end

function RPCopy_Toggle()
    if copyFrame:IsShown() then
        copyFrame:Hide()
    else
        RPCopy_Open("")
    end
end

SLASH_RPCOPY1 = "/rp"
SLASH_RPCOPY2 = "/rpcopy"
SlashCmdList["RPCOPY"] = function(msg)
    local trimmed = (msg or ""):match("^%s*(.-)%s*$")
    local low = trimmed:lower()
    if low == "clear" then
        ns.ClearSessionLogs()
        print("|cff00ff00[RPCopy]|r All logs cleared.")
        return
    elseif low == "quick" then
        RPCopy_QuickCopy()
        return
    elseif low == "capture" then
        RPCopy_CaptureTarget()
        return
    elseif low == "btn" then
        if miniBtn:IsShown() then miniBtn:Hide() else miniBtn:Show() end
        return
    elseif low:match("^mark") then
        local noteArg = trimmed:match("^mark%s+(.+)$")
        local _, status = ns.MarkAdventureHighlight(noteArg)
        print("|cff00ff00[RPCopy]|r " .. status)
        return
    end
    RPCopy_Open(trimmed)
end