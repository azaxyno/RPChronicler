local ADDON_NAME, ns = ...
local UI = ns.UI

-- =========================================================
-- Recording controls (buttons, keybinds and slash commands share these)
-- =========================================================
local function RefreshIfOpen()
    if UI.frame:IsShown() and ns.state.section == "ADVENTURES" and UI.RefreshAdventuresTab then
        UI.RefreshAdventuresTab()
    end
end

local function Report(msg, kind)
    if UI.frame:IsShown() then
        UI.SetStatus(msg, kind)
    else
        local border = (kind == "error") and { 0.75, 0.28, 0.28 } or { 0.36, 0.72, 0.36 }
        UI.ShowToast("|cffffd100RPCopy:|r " .. msg, 2.4, border[1], border[2], border[3])
    end
end

function RPCopy_StartRun()
    local active = ns.GetActiveAdventure()
    if active then
        Report("Already recording " .. (active.title or "an adventure") .. ". End it first.", "error")
        return
    end
    local run = ns.StartAdventure(nil, false)
    if run then
        ns.state.selectedAdventureId = run.id
        Report("Recording adventure: " .. (run.title or "Adventure"), "good")
    end
    RefreshIfOpen()
end

function RPCopy_ToggleRunPause()
    if not ns.GetActiveAdventure() or not ns.PauseAdventure then
        Report("No adventure is recording.", "error")
        return
    end
    local ok, msg
    if ns.IsAdventurePaused() then
        ok, msg = ns.ResumeAdventure()
    else
        ok, msg = ns.PauseAdventure()
    end
    Report(msg or "", ok and "good" or "error")
    RefreshIfOpen()
end

function RPCopy_EndRun()
    if not ns.GetActiveAdventure() then
        Report("No adventure is recording.", "error")
        return
    end
    local saved = ns.EndAdventure("Ended Manually")
    if saved then
        ns.state.selectedAdventureId = saved.id
        Report("Saved adventure: " .. (saved.title or "Adventure"), "good")
    else
        Report("Run was too short to keep, so it was not saved.", "error")
    end
    RefreshIfOpen()
end

-- =========================================================
-- Import Adventure Story modal (paste the colored LLM story)
-- =========================================================
local imp = {}
do
    local f = CreateFrame("Frame", "RPCopyStoryImportFrame", UIParent, UI.BACKDROP)
    f:SetSize(580, 420)
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 10)
    f:SetFrameStrata("FULLSCREEN_DIALOG")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:Hide()
    UI.ApplyStoryTomeLook(f)
    imp.frame = f

    imp.title = UI.Label(f, "|cffffd100Import Adventure Chronicle|r", "GameFontNormal")
    imp.title:SetPoint("TOPLEFT", 14, -12)
    local sub = UI.Label(f, "|cffd7c4a3Paste the full colored story below (Ctrl+V) and click Save Chronicle.|r", "GameFontHighlightSmall")
    sub:SetPoint("TOPLEFT", 14, -28)

    local closeX = UI.CreateSleekButton(f, 22, 20, "x", "danger")
    closeX:SetPoint("TOPRIGHT", -8, -8)
    closeX:SetScript("OnClick", function() f:Hide() end)

    local boxBg = CreateFrame("Frame", nil, f, UI.BACKDROP)
    boxBg:SetPoint("TOPLEFT", 14, -48)
    boxBg:SetPoint("BOTTOMRIGHT", -14, 42)
    UI.ApplyDarkGlass(boxBg, 0.06, 0.05, 0.04, 0.96, 0.72, 0.56, 0.26, 0.75)

    local scroll = CreateFrame("ScrollFrame", "RPCopyStoryImportScroll", boxBg, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 8, -8)
    scroll:SetPoint("BOTTOMRIGHT", -28, 8)

    local eb = CreateFrame("EditBox", "RPCopyStoryImportEditBox", scroll)
    eb:SetMultiLine(true)
    eb:SetMaxLetters(0)
    eb:SetFontObject(ChatFontNormal)
    eb:SetWidth(510)
    eb:SetHeight(310)
    eb:SetAutoFocus(true)
    scroll:SetScrollChild(eb)
    eb:SetScript("OnTextChanged", function() scroll:UpdateScrollChildRect() end)
    eb:SetScript("OnEscapePressed", function() f:Hide() end)
    imp.editBox = eb

    local saveBtn = UI.CreateSleekButton(f, 136, 24, "Save Chronicle", "gold")
    saveBtn:SetPoint("BOTTOMLEFT", 14, 11)
    saveBtn:SetScript("OnClick", function()
        local raw = eb:GetText() or ""
        if raw:match("^%s*$") then
            imp.title:SetText("|cffff6b6bPaste a story first before saving!|r")
            return
        end
        if f.targetAdvId and ns.SetAdventureStory(f.targetAdvId, raw) then
            ns.state.adventureViewMode = "STORY"
            f:Hide()
            if UI.RefreshAdventuresTab then UI.RefreshAdventuresTab() end
            UI.SetStatus("Chronicle saved to the Story tab.", "good")
        end
    end)

    local clearBtn = UI.CreateSleekButton(f, 96, 24, "Clear Box")
    clearBtn:SetPoint("LEFT", saveBtn, "RIGHT", 6, 0)
    clearBtn:SetScript("OnClick", function()
        eb:SetText("")
        eb:SetFocus()
    end)

    local cancelBtn = UI.CreateSleekButton(f, 90, 24, "Cancel", "danger")
    cancelBtn:SetPoint("BOTTOMRIGHT", -14, 11)
    cancelBtn:SetScript("OnClick", function() f:Hide() end)
end

local function OpenStoryImportModal(adv)
    if not adv then return end
    imp.frame.targetAdvId = adv.id
    imp.title:SetText("|cffffd100Import Chronicle:|r |cfff5e6c8" .. (adv.title or "Adventure") .. "|r")
    imp.editBox:SetText("")
    imp.frame:Show()
    imp.editBox:SetFocus()
end

-- =========================================================
-- ADVENTURES section: record bar, run list, Summary | Full Log | Story
-- =========================================================
local view = UI.NewSection("ADVENTURES", "Adventures", "Runs record by themselves in dungeons and raids. Full Log is what you paste into your AI.")
UI.AddRailButton("ADVENTURES", "Adventures", UI.ICONS.ADVENTURES, "Record dungeon and raid runs and read their stories.")

local A = { cards = {} }
UI.adventures = A

-- Record bar
A.recBar = CreateFrame("Frame", nil, view, UI.BACKDROP)
A.recBar:SetHeight(30)
A.recBar:SetPoint("TOPLEFT", 0, 0)
A.recBar:SetPoint("TOPRIGHT", 0, 0)
UI.ApplyDarkGlass(A.recBar, 0.08, 0.10, 0.14, 0.95, 0.72, 0.58, 0.28, 0.45)

A.runBtn = UI.CreateSleekButton(A.recBar, 122, 22, "Start New Run", "gold")
A.runBtn:SetPoint("LEFT", 4, 0)
A.runBtn.dot = A.runBtn:CreateTexture(nil, "OVERLAY")
A.runBtn.dot:SetSize(8, 8)
A.runBtn.dot:SetPoint("LEFT", 8, 0)
A.runBtn.dot:SetTexture(UI.ICONS.DOT)
A.runBtn.dot:SetVertexColor(1, 0.2, 0.2, 1)

A.pauseBtn = UI.CreateSleekButton(A.recBar, 70, 22, "Pause")
A.pauseBtn:SetPoint("LEFT", A.runBtn, "RIGHT", 4, 0)

A.markBtn = UI.CreateSleekButton(A.recBar, 112, 22, "Mark Moment")
A.markBtn:SetPoint("LEFT", A.pauseBtn, "RIGHT", 4, 0)
A.markBtn:SetIcon(UI.ICONS.MARK, 16)
A.markBtn.tipTitle = "|cffffd100Mark Moment|r"
A.markBtn.tipText = "Bookmark what just happened so the story gives it a scene. Also /rp mark <note>."

A.recText = A.recBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
A.recText:SetPoint("LEFT", A.markBtn, "RIGHT", 10, 0)
A.recText:SetPoint("RIGHT", -8, 0)
A.recText:SetJustifyH("RIGHT")
A.recText:SetWordWrap(false)

-- Run list
A.list = CreateFrame("Frame", nil, view, UI.BACKDROP)
A.list:SetWidth(190)
A.list:SetPoint("TOPLEFT", A.recBar, "BOTTOMLEFT", 0, -6)
A.list:SetPoint("BOTTOMLEFT", 0, 0)
UI.ApplyPanelLook(A.list)

do
    local header = UI.Label(A.list, "|cffffd100Recorded Adventures|r")
    header:SetPoint("TOPLEFT", 10, -8)
end

A.listScroll = CreateFrame("ScrollFrame", "RPCopyAdvListScroll", A.list, "UIPanelScrollFrameTemplate")
A.listScroll:SetPoint("TOPLEFT", 6, -26)
A.listScroll:SetPoint("BOTTOMRIGHT", -26, 6)
A.listChild = CreateFrame("Frame", nil, A.listScroll)
A.listChild:SetSize(156, 10)
A.listScroll:SetScrollChild(A.listChild)

-- Right panel
A.right = CreateFrame("Frame", nil, view)
A.right:SetPoint("TOPLEFT", A.list, "TOPRIGHT", 10, 0)
A.right:SetPoint("BOTTOMRIGHT", 0, 0)

do
    local hero = CreateFrame("Frame", nil, A.right, UI.BACKDROP)
    hero:SetHeight(60)
    hero:SetPoint("TOPLEFT", 0, 0)
    hero:SetPoint("TOPRIGHT", 0, 0)
    UI.ApplyDarkGlass(hero, 0.08, 0.10, 0.14, 0.95, 0.72, 0.58, 0.28, 0.55)

    local iconFrame = CreateFrame("Frame", nil, hero, UI.BACKDROP)
    iconFrame:SetSize(42, 42)
    iconFrame:SetPoint("LEFT", 9, 0)
    UI.ApplyDarkGlass(iconFrame, 0.04, 0.05, 0.07, 1.0, 0.85, 0.68, 0.30, 0.80)

    A.heroIcon = iconFrame:CreateTexture(nil, "ARTWORK")
    A.heroIcon:SetPoint("TOPLEFT", 2, -2)
    A.heroIcon:SetPoint("BOTTOMRIGHT", -2, 2)
    A.heroIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    A.heroIcon:SetTexture(UI.ICONS.ADVENTURES)

    local function HeroLine(template, y)
        local fs = hero:CreateFontString(nil, "OVERLAY", template)
        fs:SetPoint("TOPLEFT", iconFrame, "TOPRIGHT", 10, y)
        fs:SetPoint("RIGHT", -10, 0)
        fs:SetJustifyH("LEFT")
        fs:SetWordWrap(false)
        return fs
    end
    A.heroTitle = HeroLine("GameFontNormal", -1)
    A.heroMeta = HeroLine("GameFontHighlightSmall", -17)
    A.heroStats = HeroLine("GameFontHighlightSmall", -31)
end

A.summaryBtn = UI.CreateSleekButton(A.right, 66, 22, "Summary")
A.summaryBtn:SetPoint("TOPLEFT", 0, -66)
A.fullBtn = UI.CreateSleekButton(A.right, 62, 22, "Full Log")
A.fullBtn:SetPoint("LEFT", A.summaryBtn, "RIGHT", 4, 0)
A.fullBtn.tipTitle = "|cffffd100Full Log|r"
A.fullBtn.tipText = "The whole run for your AI storyteller. Click Select All, then Ctrl+C."
A.storyBtn = UI.CreateSleekButton(A.right, 62, 22, "Story")
A.storyBtn:SetPoint("LEFT", A.fullBtn, "RIGHT", 4, 0)

A.delBtn = UI.CreateSleekButton(A.right, 56, 22, "Delete", "danger")
A.delBtn:SetPoint("TOPRIGHT", 0, -66)
A.delBtn.tipTitle = "|cffff6b6bDelete|r"
A.delBtn.tipText = "Click twice to delete this run."
A.selectAllBtn = UI.CreateSleekButton(A.right, 80, 22, "Select All", "gold")
A.selectAllBtn:SetPoint("RIGHT", A.delBtn, "LEFT", -4, 0)
A.reimportBtn = UI.CreateSleekButton(A.right, 104, 22, "Re-Import Story", "gold")
A.reimportBtn:SetPoint("RIGHT", A.delBtn, "LEFT", -4, 0)
A.reimportBtn:Hide()

-- Summary / Full Log text box
A.boxBg = CreateFrame("Frame", nil, A.right, UI.BACKDROP)
A.boxBg:SetPoint("TOPLEFT", 0, -94)
A.boxBg:SetPoint("BOTTOMRIGHT", 0, 0)
UI.ApplyPanelLook(A.boxBg)

A.scroll = CreateFrame("ScrollFrame", "RPCopyAdvScroll", A.boxBg, "UIPanelScrollFrameTemplate")
A.scroll:SetPoint("TOPLEFT", 8, -8)
A.scroll:SetPoint("BOTTOMRIGHT", -26, 8)
A.editBox = CreateFrame("EditBox", "RPCopyAdvEditBox", A.scroll)
A.editBox:SetMultiLine(true)
A.editBox:SetMaxLetters(0)
A.editBox:SetFontObject(ChatFontNormal)
A.editBox:SetWidth(340)
A.editBox:SetHeight(240)
A.editBox:SetAutoFocus(false)
A.editBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
A.scroll:SetScrollChild(A.editBox)

-- Story reader (warm parchment) with an empty-state guide
A.storyBg = CreateFrame("Frame", nil, A.right, UI.BACKDROP)
A.storyBg:SetPoint("TOPLEFT", 0, -94)
A.storyBg:SetPoint("BOTTOMRIGHT", 0, 0)
A.storyBg:Hide()
UI.ApplyStoryTomeLook(A.storyBg)

do
    local inner = CreateFrame("Frame", nil, A.storyBg, UI.BACKDROP)
    inner:SetPoint("TOPLEFT", 5, -5)
    inner:SetPoint("BOTTOMRIGHT", -5, 5)
    UI.ApplyDarkGlass(inner, 0.11, 0.08, 0.06, 0.82, 0.82, 0.65, 0.30, 0.50)

    local empty = CreateFrame("Frame", nil, inner)
    empty:SetAllPoints(inner)
    A.emptyPane = empty

    local book = empty:CreateTexture(nil, "ARTWORK")
    book:SetSize(36, 36)
    book:SetPoint("TOPLEFT", 16, -16)
    book:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    book:SetTexture(UI.ICONS.STORY)

    A.emptyHeading = empty:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    A.emptyHeading:SetPoint("TOPLEFT", book, "TOPRIGHT", 10, -2)
    A.emptyHeading:SetPoint("RIGHT", empty, "RIGHT", -16, 0)
    A.emptyHeading:SetJustifyH("LEFT")
    A.emptyHeading:SetWordWrap(false)
    pcall(A.emptyHeading.SetFont, A.emptyHeading, "Fonts\\FRIZQT__.TTF", 15, "")

    -- Two anchors give it the panel's width, so it wraps instead of overflowing
    local subHeading = empty:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    subHeading:SetPoint("TOPLEFT", book, "TOPRIGHT", 10, -21)
    subHeading:SetPoint("TOPRIGHT", empty, "TOPRIGHT", -16, -37)
    subHeading:SetJustifyH("LEFT")
    subHeading:SetJustifyV("TOP")
    subHeading:SetWordWrap(true)
    if subHeading.SetMaxLines then subHeading:SetMaxLines(2) end
    subHeading:SetText("|cffd7c4a3Turn this run's chatter, wipes, and loot into a colored Warcraft story.|r")

    local divider = empty:CreateTexture(nil, "ARTWORK")
    divider:SetHeight(1)
    divider:SetPoint("TOPLEFT", 16, -66)
    divider:SetPoint("TOPRIGHT", -16, -66)
    divider:SetTexture(UI.SOLID_TEX)
    divider:SetVertexColor(0.82, 0.65, 0.30, 0.45)

    local steps = empty:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    steps:SetPoint("TOPLEFT", 18, -76)
    steps:SetPoint("TOPRIGHT", -18, -76)
    steps:SetJustifyH("LEFT")
    steps:SetSpacing(4)
    steps:SetText(
        "|cffffd100How to make the story:|r\n" ..
        "|cfff5e6c81. One time:|r click |cffffd100Story Template|r, paste it into your AI (like Gemini) and create the storyteller skill.\n" ..
        "|cfff5e6c82. Copy the run:|r open |cff69ccf0Full Log|r, click |cffffd100Select All|r and press |cffffd100Ctrl+C|r.\n" ..
        "|cfff5e6c83. Import:|r paste the log into your AI, copy its colored story, and click |cffffd100Import Story|r.")

    local tplBtn = UI.CreateSleekButton(empty, 140, 24, "Story Template", "gold")
    tplBtn:SetPoint("BOTTOMLEFT", 18, 14)
    tplBtn:SetIcon(UI.ICONS.STORY, 16)
    tplBtn:SetScript("OnClick", function()
        if UI.OpenSkillTemplateModal then UI.OpenSkillTemplateModal("STORY") end
    end)

    A.emptyImportBtn = UI.CreateSleekButton(empty, 140, 24, "Import Story", "gold")
    A.emptyImportBtn:SetPoint("LEFT", tplBtn, "RIGHT", 8, 0)

    local read = CreateFrame("Frame", nil, inner)
    read:SetAllPoints(inner)
    read:Hide()
    A.readPane = read

    A.storyScroll = CreateFrame("ScrollFrame", "RPCopyStoryReadScroll", read, "UIPanelScrollFrameTemplate")
    A.storyScroll:SetPoint("TOPLEFT", 14, -12)
    A.storyScroll:SetPoint("BOTTOMRIGHT", -28, 12)
    A.storyChild = CreateFrame("Frame", nil, A.storyScroll)
    A.storyChild:SetSize(320, 240)
    A.storyScroll:SetScrollChild(A.storyChild)

    A.storyText = A.storyChild:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    A.storyText:SetPoint("TOPLEFT", 2, -2)
    A.storyText:SetWidth(316)
    A.storyText:SetJustifyH("LEFT")
    A.storyText:SetJustifyV("TOP")
    A.storyText:SetSpacing(5)
    A.storyText:SetTextColor(0.95, 0.92, 0.86)
    A.storyText:SetShadowOffset(1, -1)
    A.storyText:SetShadowColor(0, 0, 0, 0.95)
    pcall(A.storyText.SetFont, A.storyText, "Fonts\\FRIZQT__.TTF", 13, "")
end

local function UpdateStoryScrollHeight()
    local h = A.storyText:GetStringHeight() or 200
    A.storyChild:SetHeight(math.max(230, h + 32))
    A.storyScroll:UpdateScrollChildRect()
end

local function CreateAdventureCard(parent)
    local card = CreateFrame("Button", nil, parent, UI.BACKDROP)
    card:SetSize(156, 44)
    UI.ApplyDarkGlass(card, 0.09, 0.11, 0.15, 0.92, 0.22, 0.25, 0.32, 0.85)

    card.accent = card:CreateTexture(nil, "OVERLAY")
    card.accent:SetWidth(3)
    card.accent:SetPoint("TOPLEFT", 1, -1)
    card.accent:SetPoint("BOTTOMLEFT", 1, 1)
    card.accent:SetTexture(UI.SOLID_TEX)
    card.accent:SetVertexColor(0.90, 0.73, 0.32, 0)

    card.icon = card:CreateTexture(nil, "ARTWORK")
    card.icon:SetSize(30, 30)
    card.icon:SetPoint("LEFT", 8, 0)
    card.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    card.titleLbl = card:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    card.titleLbl:SetPoint("TOPLEFT", card.icon, "TOPRIGHT", 6, -1)
    card.titleLbl:SetPoint("RIGHT", -4, 0)
    card.titleLbl:SetJustifyH("LEFT")
    card.titleLbl:SetWordWrap(false)

    card.subLbl = card:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    card.subLbl:SetPoint("TOPLEFT", card.icon, "TOPRIGHT", 6, -16)
    card.subLbl:SetPoint("RIGHT", -4, 0)
    card.subLbl:SetJustifyH("LEFT")
    card.subLbl:SetWordWrap(false)

    card:SetScript("OnEnter", function(self)
        self:SetBackdropBorderColor(0.90, 0.73, 0.32, 0.90)
        if not self.isSelected then self:SetBackdropColor(0.14, 0.17, 0.23, 0.96) end
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

local function GetSelectedAdventure()
    local active = ns.GetActiveAdventure()
    if active and ns.state.selectedAdventureId == active.id then return active end
    for _, adv in ipairs(RPCopyDB.adventures or {}) do
        if adv.id == ns.state.selectedAdventureId then return adv end
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

local function UpdateHero(adv, isLive)
    if not adv then
        A.heroIcon:SetTexture(UI.ICONS.ADVENTURES)
        A.heroTitle:SetText("|cffffd100No Adventure Selected|r")
        A.heroMeta:SetText("|cff9aa5b4Enter a dungeon or raid, or click Start New Run above|r")
        A.heroStats:SetText("")
        return
    end
    A.heroIcon:SetTexture(ns.GetAdventureIcon(adv))
    local livePrefix = isLive and (adv.paused and "|cffffb74d[PAUSED]|r " or "|cffff5252[REC]|r ") or ""
    local storyBadge = (adv.story and adv.story ~= "") and "  |cffffd100[Chronicle]|r" or ""
    A.heroTitle:SetText(livePrefix .. "|cffffd100" .. (adv.title or "Adventure") .. "|r" .. storyBadge)
    local durSec = adv.duration or (adv.startTime and (time() - adv.startTime) or 0)
    local reloads = (adv.reloads and adv.reloads > 0) and string.format("  -  %d reload%s", adv.reloads, adv.reloads == 1 and "" or "s") or ""
    A.heroMeta:SetText(string.format("|cffb0bac5%s  -  %s  -  %s%s|r",
        adv.zone or "Unknown", adv.startDate or "-", ns.FormatDuration(durSec), reloads))
    A.heroStats:SetText(string.format(
        "|cff8f9ba8Kills:|r |cff5cb85c%d|r   |cff8f9ba8Wipes:|r |cffff6b6b%d|r   |cff8f9ba8Deaths:|r |cffffb74d%d|r   |cff8f9ba8Shots:|r |cff69ccf0%d|r",
        #(adv.bossKills or {}), adv.wipes or 0, adv.deaths or 0, #(adv.shots or {})))
end

local function UpdateRecordBar(active)
    if active then
        A.runBtn:SetText("|cffff6b6bEnd & Save Run|r")
        A.runBtn.dot:Hide()
        A.runBtn.label:SetPoint("LEFT", 5, 0)
        A.pauseBtn:Enable()
        if active.paused then
            A.pauseBtn:SetText("|cff5cb85cResume|r")
            A.pauseBtn:LockHighlight()
            A.markBtn:Disable()
            A.recText:SetText("|cffffb74dPaused:|r |cffd8dee9" .. (active.title or "Adventure") .. "|r")
        else
            A.pauseBtn:SetText("|cffffb74dPause|r")
            A.pauseBtn:UnlockHighlight()
            A.markBtn:Enable()
            local mins = math.floor(math.max(0, time() - (active.startTime or time())) / 60)
            A.recText:SetText(string.format("|cffff6b6bRecording:|r |cffd8dee9%s (%dm)|r", active.title or "Adventure", mins))
        end
    else
        A.runBtn:SetText("|cff5cb85cStart New Run|r")
        A.runBtn.dot:Show()
        A.runBtn.label:SetPoint("LEFT", 14, 0)
        A.pauseBtn:SetText("Pause")
        A.pauseBtn:UnlockHighlight()
        A.pauseBtn:Disable()
        A.markBtn:Disable()
        A.recText:SetText("|cff8f9ba8Not recording|r")
    end
end

function UI.RefreshAdventuresTab()
    UI.EnsureOptions()
    local active = ns.GetActiveAdventure()
    UpdateRecordBar(active)

    for _, card in ipairs(A.cards) do card:Hide() end
    local entries = {}
    if active then table.insert(entries, { adv = active, isLive = true }) end
    for _, adv in ipairs(RPCopyDB.adventures or {}) do
        table.insert(entries, { adv = adv, isLive = false })
    end

    for idx, item in ipairs(entries) do
        local adv = item.adv
        local card = A.cards[idx]
        if not card then
            card = CreateAdventureCard(A.listChild)
            A.cards[idx] = card
        end
        card:SetPoint("TOPLEFT", 0, -(idx - 1) * 48)
        card.icon:SetTexture(ns.GetAdventureIcon(adv))
        local prefix = item.isLive and (adv.paused and "|cffffb74d[P]|r " or "|cffff5252[REC]|r ") or ""
        local bookStar = (adv.story and adv.story ~= "") and " |cffffd100*|r" or ""
        card.titleLbl:SetText(prefix .. "|cfff0f4f8" .. (adv.title or "Adventure") .. "|r" .. bookStar)
        local durSec = adv.duration or (adv.startTime and (time() - adv.startTime) or 0)
        card.subLbl:SetText(string.format("|cff8f9ba8%s - %dk - %dw|r",
            ns.FormatDuration(durSec), #(adv.bossKills or {}), adv.wipes or 0))

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
            A.delBtn.armedAt = nil
            UI.RefreshAdventuresTab()
        end)
        card:Show()
    end
    A.listChild:SetHeight(math.max(10, #entries * 48))

    local selected = GetSelectedAdventure()
    UpdateHero(selected, (active and selected and active.id == selected.id) or false)
    A.delBtn:SetText("Delete")

    local hasStory = selected and selected.story and selected.story ~= ""
    A.storyBtn:SetText(hasStory and "Story *" or "Story")
    A.summaryBtn:UnlockHighlight()
    A.fullBtn:UnlockHighlight()
    A.storyBtn:UnlockHighlight()

    local mode = ns.state.adventureViewMode or "SUMMARY"
    if mode == "STORY" then
        A.storyBtn:LockHighlight()
        A.boxBg:Hide()
        A.selectAllBtn:Hide()
        A.storyBg:Show()
        if selected then
            A.reimportBtn:Show()
            A.reimportBtn:SetText(hasStory and "Re-Import Story" or "Import Story")
            A.emptyImportBtn:Enable()
        else
            A.reimportBtn:Hide()
            A.emptyImportBtn:Disable()
        end
        if hasStory then
            A.emptyPane:Hide()
            A.readPane:Show()
            -- Re-normalize on render so stories saved by older versions display cleanly
            A.storyText:SetText(ns.NormalizeStoryText(selected.story))
            UpdateStoryScrollHeight()
            A.storyScroll:SetVerticalScroll(0)
            if C_Timer and C_Timer.After then C_Timer.After(0, UpdateStoryScrollHeight) end
        else
            A.readPane:Hide()
            A.emptyPane:Show()
            A.emptyHeading:SetText(selected and "|cffffd100No Chronicle Yet|r" or "|cffffd100Select or Start an Adventure First|r")
        end
    else
        A.storyBg:Hide()
        A.reimportBtn:Hide()
        A.boxBg:Show()
        A.selectAllBtn:Show()
        if mode == "FULL" then
            A.fullBtn:LockHighlight()
            A.editBox:SetText(ns.BuildAdventureFullLog(selected))
        else
            A.summaryBtn:LockHighlight()
            A.editBox:SetText(ns.BuildAdventureSummary(selected))
        end
    end
end

local function SetMode(mode)
    ns.state.adventureViewMode = mode
    UI.RefreshAdventuresTab()
end
A.summaryBtn:SetScript("OnClick", function() SetMode("SUMMARY") end)
A.fullBtn:SetScript("OnClick", function() SetMode("FULL") end)
A.storyBtn:SetScript("OnClick", function() SetMode("STORY") end)

local function ImportForSelected()
    local adv = GetSelectedAdventure()
    if adv then OpenStoryImportModal(adv) end
end
A.emptyImportBtn:SetScript("OnClick", ImportForSelected)
A.reimportBtn:SetScript("OnClick", ImportForSelected)

A.selectAllBtn:SetScript("OnClick", function()
    A.editBox:SetFocus()
    A.editBox:HighlightText()
    UI.SetStatus("Text selected. Press Ctrl+C to copy it.", "good")
end)

A.runBtn:SetScript("OnClick", function()
    if ns.GetActiveAdventure() then RPCopy_EndRun() else RPCopy_StartRun() end
    UI.RefreshAdventuresTab()
end)
A.pauseBtn:SetScript("OnClick", function()
    RPCopy_ToggleRunPause()
    UI.RefreshAdventuresTab()
end)
A.markBtn:SetScript("OnClick", function()
    local ok, msg = ns.MarkAdventureHighlight(nil)
    UI.SetStatus(msg, ok and "good" or "error")
    if ok then
        if ns.RequestScreenshot then ns.RequestScreenshot("mark", "Marked moment") end
        UI.RefreshAdventuresTab()
    end
end)

A.delBtn:SetScript("OnClick", function(self)
    local active = ns.GetActiveAdventure()
    if active and ns.state.selectedAdventureId == active.id then
        UI.SetStatus("End the live run before deleting it.", "error")
        return
    end
    for i, adv in ipairs(RPCopyDB.adventures or {}) do
        if adv.id == ns.state.selectedAdventureId then
            if not self.armedAt or GetTime() - self.armedAt > 4 then
                self.armedAt = GetTime()
                self:SetText("|cffff6b6bSure?|r")
                UI.SetStatus("Click Delete again to remove " .. (adv.title or "this run") .. ".", "error")
                return
            end
            self.armedAt = nil
            table.remove(RPCopyDB.adventures, i)
            ns.state.selectedAdventureId = nil
            UI.SetStatus("Adventure deleted.", "good")
            UI.RefreshAdventuresTab()
            return
        end
    end
end)

UI.SetSectionOnShow("ADVENTURES", UI.RefreshAdventuresTab)

view:SetScript("OnHide", function() A.editBox:ClearFocus() end)

-- Keep the record bar's timer fresh while the section is open
do
    local acc = 0
    A.recBar:SetScript("OnUpdate", function(_, elapsed)
        acc = acc + elapsed
        if acc < 5 then return end
        acc = 0
        UpdateRecordBar(ns.GetActiveAdventure())
    end)
end

UI.AddReflow(function()
    local w = A.scroll:GetWidth()
    if w and w > 50 then A.editBox:SetWidth(w) end
    w = A.storyScroll:GetWidth()
    if w and w > 50 then
        A.storyChild:SetWidth(w)
        A.storyText:SetWidth(w - 4)
        UpdateStoryScrollHeight()
    end
end)
