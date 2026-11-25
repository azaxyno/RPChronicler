local ADDON_NAME, ns = ...
local UI = ns.UI

-- =========================================================
-- Recording controls (buttons, keybinds and slash commands share these)
-- =========================================================
local function RefreshIfOpen()
    if UI.RefreshRecordIcon then pcall(UI.RefreshRecordIcon) end
    if UI.frame:IsShown() and ns.state.section == "ADVENTURES" and UI.RefreshAdventuresTab then
        UI.RefreshAdventuresTab()
    elseif UI.frame:IsShown() and ns.state.section == "BOOK" and UI.RefreshStoryBook then
        UI.RefreshStoryBook()
    end
end
UI.RefreshRunViews = RefreshIfOpen

local function Report(msg, kind)
    if UI.frame:IsShown() then
        UI.SetStatus(msg, kind)
    else
        local border = (kind == "error") and { 0.75, 0.28, 0.28 } or { 0.36, 0.72, 0.36 }
        UI.ShowToast("|cffffd100RP Chronicler:|r " .. msg, 2.4, border[1], border[2], border[3])
    end
end

function RPChronicler_StartRun()
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

UI.StartRunFromUI = function() RPChronicler_StartRun() end

-- One toggle for Start / Stop (the button, the RP icon menu, keybinds)
function RPChronicler_ToggleRun()
    if ns.GetActiveAdventure() then RPChronicler_EndRun() else RPChronicler_StartRun() end
end

function RPChronicler_ToggleRunPause()
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

function RPChronicler_EndRun()
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
    local f = CreateFrame("Frame", "RPChroniclerStoryImportFrame", UIParent, UI.BACKDROP)
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
    local sub = UI.Label(f, "|cffd7c4a3Pick the run, paste the colored story (Ctrl+V) and click Save to Story Book.|r", "GameFontHighlightSmall")
    sub:SetPoint("TOPLEFT", 14, -28)

    -- Run selector: < Run name >
    imp.prev = UI.CreateSleekButton(f, 22, 20, "<")
    imp.prev:SetPoint("TOPLEFT", 14, -46)
    imp.next = UI.CreateSleekButton(f, 22, 20, ">")
    imp.next:SetPoint("TOPRIGHT", -14, -46)
    imp.runLabel = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    imp.runLabel:SetPoint("LEFT", imp.prev, "RIGHT", 8, 0)
    imp.runLabel:SetPoint("RIGHT", imp.next, "LEFT", -8, 0)
    imp.runLabel:SetJustifyH("CENTER")
    imp.runLabel:SetWordWrap(false)

    local closeX = UI.CreateSleekButton(f, 22, 20, "x", "danger")
    closeX:SetPoint("TOPRIGHT", -8, -8)
    closeX:SetScript("OnClick", function() f:Hide() end)

    local boxBg = CreateFrame("Frame", nil, f, UI.BACKDROP)
    boxBg:SetPoint("TOPLEFT", 14, -72)
    boxBg:SetPoint("BOTTOMRIGHT", -14, 42)
    UI.ApplyDarkGlass(boxBg, 0.06, 0.05, 0.04, 0.96, 0.72, 0.56, 0.26, 0.75)

    local scroll = CreateFrame("ScrollFrame", "RPChroniclerStoryImportScroll", boxBg, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 8, -8)
    scroll:SetPoint("BOTTOMRIGHT", -28, 8)

    local eb = CreateFrame("EditBox", "RPChroniclerStoryImportEditBox", scroll)
    eb:SetMultiLine(true)
    eb:SetMaxLetters(0)
    eb:SetFontObject(ChatFontNormal)
    eb:SetWidth(510)
    eb:SetHeight(286)
    eb:SetAutoFocus(true)
    scroll:SetScrollChild(eb)
    eb:SetScript("OnTextChanged", function() scroll:UpdateScrollChildRect() end)
    eb:SetScript("OnEscapePressed", function() f:Hide() end)
    imp.editBox = eb

    local saveBtn = UI.CreateSleekButton(f, 136, 24, "Save to Story Book", "gold")
    saveBtn:SetPoint("BOTTOMLEFT", 14, 11)
    saveBtn:SetScript("OnClick", function()
        local raw = eb:GetText() or ""
        if raw:match("^%s*$") then
            imp.title:SetText("|cffff6b6bPaste a story first before saving!|r")
            return
        end
        local ok, storyId
        if f.targetStoryId and not ns.FindAdventure(f.targetAdvId or "") then
            ok, storyId = ns.SetStoryText(f.targetStoryId, raw)
        elseif f.targetAdvId then
            ok, storyId = ns.SetAdventureStory(f.targetAdvId, raw)
        end
        if ok then
            f:Hide()
            if UI.OpenStoryBook then UI.OpenStoryBook(storyId) end
            UI.SetStatus("Story saved to the Story Book.", "good")
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

-- Every run you can attach a story to: the live one first, then saved ones
local function AllRuns()
    local list = {}
    local active = ns.GetActiveAdventure()
    if active then table.insert(list, active) end
    for _, adv in ipairs(RPChroniclerDB.adventures or {}) do table.insert(list, adv) end
    return list
end
UI.AllRuns = AllRuns

local function ShowImportRun()
    local runs = AllRuns()
    -- Re-importing a story whose recording was deleted: no run to pick
    local st = imp.frame.targetStoryId and ns.FindStory(imp.frame.targetStoryId)
    if st and not ns.StoryRun(st) then
        imp.runLabel:SetText(string.format("|cfff5e6c8%s|r |cff9aa5b4- replaces this story (its recording was deleted)|r", st.title or "Story"))
        imp.prev:Disable(); imp.next:Disable()
        return {}, 0
    end
    local idx = 1
    for i, adv in ipairs(runs) do
        if adv.id == imp.frame.targetAdvId then idx = i end
    end
    local adv = runs[idx]
    imp.frame.targetAdvId = adv and adv.id or nil
    if adv then
        local has = ns.RunHasStory(adv) and "  |cffffb74d(has a story: saving replaces it)|r" or ""
        imp.runLabel:SetText(string.format("|cfff5e6c8%s|r |cff9aa5b4- %s - %s (%d of %d)|r%s",
            adv.title or "Adventure", ns.GetRunKindLabel(adv), adv.startDate or "-", idx, #runs, has))
    else
        imp.runLabel:SetText("|cffff6b6bNo recorded runs yet. Record one first.|r")
    end
    if #runs > 1 then imp.prev:Enable(); imp.next:Enable() else imp.prev:Disable(); imp.next:Disable() end
    return runs, idx
end

local function StepImportRun(delta)
    local runs, idx = ShowImportRun()
    if #runs == 0 then return end
    idx = ((idx - 1 + delta) % #runs) + 1
    imp.frame.targetAdvId = runs[idx].id
    ShowImportRun()
end
imp.prev:SetScript("OnClick", function() StepImportRun(-1) end)
imp.next:SetScript("OnClick", function() StepImportRun(1) end)

-- adv: the run to import for (nil = the selected one); st: a story to replace
local function OpenStoryImportModal(adv, st)
    imp.frame.targetStoryId = st and st.id or nil
    if st and not adv then adv = ns.StoryRun(st) end
    imp.frame.targetAdvId = adv and adv.id or (ns.state.selectedAdventureId)
    imp.title:SetText("|cffffd100Import Story from your AI|r")
    imp.editBox:SetText("")
    ShowImportRun()
    imp.frame:Show()
    imp.editBox:SetFocus()
end
UI.OpenStoryImportModal = OpenStoryImportModal

-- =========================================================
-- ADVENTURES section: record bar, run list, Summary | Full Log | Story
-- =========================================================
-- 0.5.0: Adventures holds the recordings only; the Story Book is its own
-- section right below it (UI_StoryBook.lua)
local view = UI.NewSection("ADVENTURES", "Adventures", "Your recorded runs: Summary, Full Log for your AI, and a link to each story.")
UI.AddRailButton("ADVENTURES", "Adventures", UI.ICONS.ADVENTURES, "Record dungeon, raid and open-world runs.")

local A = { cards = {} }
UI.adventures = A

A.recView = CreateFrame("Frame", nil, view)
A.recView:SetPoint("TOPLEFT", 0, 0)
A.recView:SetPoint("BOTTOMRIGHT", 0, 0)

-- Record bar
A.recBar = CreateFrame("Frame", nil, A.recView, UI.BACKDROP)
A.recBar:SetHeight(30)
A.recBar:SetPoint("TOPLEFT", 0, 0)
A.recBar:SetPoint("TOPRIGHT", 0, 0)
UI.ApplyDarkGlass(A.recBar, 0.08, 0.10, 0.14, 0.95, 0.72, 0.58, 0.28, 0.45)

A.runBtn = UI.CreateSleekButton(A.recBar, 122, 22, "Start Recording", "good")
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
A.list = CreateFrame("Frame", nil, A.recView, UI.BACKDROP)
A.list:SetWidth(190)
A.list:SetPoint("TOPLEFT", A.recBar, "BOTTOMLEFT", 0, -6)
A.list:SetPoint("BOTTOMLEFT", 0, 0)
UI.ApplyPanelLook(A.list)

do
    local header = UI.Label(A.list, "|cffffd100Recordings|r")
    header:SetPoint("TOPLEFT", 10, -8)
end

A.listScroll = CreateFrame("ScrollFrame", "RPChroniclerAdvListScroll", A.list, "UIPanelScrollFrameTemplate")
A.listScroll:SetPoint("TOPLEFT", 6, -26)
A.listScroll:SetPoint("BOTTOMRIGHT", -26, 6)
A.listChild = CreateFrame("Frame", nil, A.listScroll)
A.listChild:SetSize(156, 10)
A.listScroll:SetScrollChild(A.listChild)

-- Right panel
A.right = CreateFrame("Frame", nil, A.recView)
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
A.tplBtn = UI.CreateSleekButton(A.right, 70, 22, "Template", "tool")
A.tplBtn:SetPoint("LEFT", A.fullBtn, "RIGHT", 4, 0)
A.tplBtn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
A.tplBtn.tipTitle = "|cffffd100Story Template|r"
A.storyBtn = UI.CreateSleekButton(A.right, 56, 22, "Story", "gold")
A.storyBtn:SetPoint("LEFT", A.tplBtn, "RIGHT", 4, 0)
A.storyBtn.tipTitle = "|cffffd100Story|r"

A.delBtn = UI.CreateSleekButton(A.right, 56, 22, "Delete", "danger")
A.delBtn:SetPoint("TOPRIGHT", 0, -66)
A.delBtn.tipTitle = "|cffff6b6bDelete|r"
A.delBtn.tipText = "Click twice to delete this run."
A.selectAllBtn = UI.CreateSleekButton(A.right, 80, 22, "Select All", "gold")
A.selectAllBtn:SetPoint("RIGHT", A.delBtn, "LEFT", -4, 0)

-- Full Log size meter (Options > Full Log picks the AI and can hide it)
A.meter = CreateFrame("Button", nil, A.right)
A.meter:SetHeight(16)
A.meter:SetPoint("TOPLEFT", 2, -92)
A.meter:SetPoint("TOPRIGHT", -2, -92)
A.meterText = A.meter:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
A.meterText:SetAllPoints(A.meter)
A.meterText:SetJustifyH("LEFT")
A.meterText:SetWordWrap(false)
A.meter:SetScript("OnEnter", function(self)
    UI.Tooltip(self, "|cffffd100Full Log size|r",
        "How much of your AI's paste room this log uses. Pick your AI in Options > Full Log.",
        "Too long? Turn off busy categories there, lower the limits, or use a paid plan.",
        "README: see the Requirements section for free vs paid plans.")
end)
A.meter:SetScript("OnLeave", UI.HideTooltip)
A.meter:SetScript("OnClick", function()
    if UI.OpenOptionsPage then UI.OpenOptionsPage("FULLLOG") end
end)
A.meter:Hide()

-- Summary / Full Log text box
A.boxBg = CreateFrame("Frame", nil, A.right, UI.BACKDROP)
A.boxBg:SetPoint("TOPLEFT", 0, -94)
A.boxBg:SetPoint("BOTTOMRIGHT", 0, 0)
UI.ApplyPanelLook(A.boxBg)

A.scroll = CreateFrame("ScrollFrame", "RPChroniclerAdvScroll", A.boxBg, "UIPanelScrollFrameTemplate")
A.scroll:SetPoint("TOPLEFT", 8, -8)
A.scroll:SetPoint("BOTTOMRIGHT", -26, 8)
A.editBox = CreateFrame("EditBox", "RPChroniclerAdvEditBox", A.scroll)
A.editBox:SetMultiLine(true)
A.editBox:SetMaxLetters(0)
A.editBox:SetFontObject(ChatFontNormal)
A.editBox:SetWidth(340)
A.editBox:SetHeight(240)
A.editBox:SetAutoFocus(false)
A.editBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
A.scroll:SetScrollChild(A.editBox)

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
    for _, adv in ipairs(RPChroniclerDB.adventures or {}) do
        if adv.id == ns.state.selectedAdventureId then return adv end
    end
    if active then
        ns.state.selectedAdventureId = active.id
        return active
    end
    if RPChroniclerDB.adventures and RPChroniclerDB.adventures[1] then
        ns.state.selectedAdventureId = RPChroniclerDB.adventures[1].id
        return RPChroniclerDB.adventures[1]
    end
    return nil
end

local function UpdateHero(adv, isLive)
    if not adv then
        A.heroIcon:SetTexture(UI.ICONS.ADVENTURES)
        A.heroTitle:SetText("|cffffd100No Adventure Selected|r")
        A.heroMeta:SetText("|cff9aa5b4Enter a dungeon or raid, or click Start Recording above|r")
        A.heroStats:SetText("")
        return
    end
    A.heroIcon:SetTexture(ns.GetAdventureIcon(adv))
    local livePrefix = isLive and (adv.paused and "|cffffb74d[PAUSED]|r " or "|cffff5252[REC]|r ") or ""
    local storyBadge = ns.RunHasStory(adv) and "  |cffffd100[Story]|r" or ""
    A.heroTitle:SetText(livePrefix .. "|cffffd100" .. (adv.title or "Adventure") .. "|r" .. storyBadge)
    local durSec = ns.GetRunDuration(adv)
    local interrupted = adv.interrupted and "  -  |cffffb74dinterrupted|r|cffb0bac5" or ""
    local reloads = (adv.reloads and adv.reloads > 0) and string.format("  -  %d reload%s", adv.reloads, adv.reloads == 1 and "" or "s") or ""
    A.heroMeta:SetText(string.format("|cffb0bac5%s  -  %s  -  %s  -  %s%s%s|r",
        ns.GetRunKindLabel(adv), adv.zone or "Unknown", adv.startDate or "-", ns.FormatDuration(durSec), reloads, interrupted))
    -- 0.5.0: the stats fit the run type, and zeros are hidden
    local HEX = { Bosses = "5cb85c", Foes = "5cb85c", Wipes = "ff6b6b", Deaths = "ffb74d", Shots = "69ccf0", Levels = "69ccf0", Quests = "ffd100" }
    local bits = {}
    for _, h in ipairs(ns.GetRunHeroStats(adv)) do
        table.insert(bits, string.format("|cff8f9ba8%s:|r |cff%s%s|r", h.label, HEX[h.label] or "eceff1", tostring(h.value)))
    end
    A.heroStats:SetText(#bits > 0 and table.concat(bits, "   ") or "|cff8f9ba8Nothing counted yet|r")
end

local function UpdateRecordBar(active)
    if active then
        A.runBtn.accentStyle = "danger"
        A.runBtn.ApplyNormalLook()
        A.runBtn:SetText("Stop & Save")
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
        A.runBtn.accentStyle = "good"
        A.runBtn.ApplyNormalLook()
        A.runBtn:SetText("Start Recording")
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
    for _, adv in ipairs(RPChroniclerDB.adventures or {}) do
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
        local bookStar = ns.RunHasStory(adv) and " |cffffd100*|r" or ""
        card.titleLbl:SetText(prefix .. "|cfff0f4f8" .. (adv.title or "Adventure") .. "|r" .. bookStar)
        local durSec = ns.GetRunDuration(adv)
        local kindShort = (adv.kind == "raid" and "Raid") or (adv.kind == "dungeon" and "Dgn") or "World"
        local extra
        if adv.kind == "world" then
            extra = string.format("%d foes", adv.foesDefeated or 0)
            local _, gained = ns.GetRunLevels(adv)
            if gained > 0 then extra = extra .. " - +" .. gained .. " lvl" end
        else
            extra = string.format("%dk - %dw", #(adv.bossKills or {}), adv.wipes or 0)
        end
        card.subLbl:SetText(string.format("|cff8f9ba8%s - %s - %s|r", kindShort, ns.FormatDuration(durSec), extra))

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

    local hasStory = selected and ns.RunHasStory(selected)
    A.storyBtn:SetText(hasStory and "Story *" or "Story")
    A.storyBtn.tipText = hasStory and "Open this run's story in the Story Book." or "Import a story for this run from your AI."
    if selected then A.storyBtn:Enable() else A.storyBtn:Disable() end
    local isWorld = not selected or selected.kind == "world"
    A.tplBtn.tipText = (isWorld and "Opens the |cffffd100Adventure Story|r template (open world, solo)." or "Opens the |cffffd100Dungeon/Raid Story|r template (one chapter per boss).")
        .. "\nRight-click for the other one. Paste it into your AI once to make the storyteller skill."
    A.summaryBtn:UnlockHighlight()
    A.fullBtn:UnlockHighlight()

    local mode = ns.state.adventureViewMode
    if mode ~= "FULL" then mode = "SUMMARY" end
    A.boxBg:ClearAllPoints()
    A.boxBg:SetPoint("BOTTOMRIGHT", 0, 0)
    if mode == "FULL" then
        A.fullBtn:LockHighlight()
        local text = ns.BuildAdventureFullLog(selected)
        A.editBox:SetText(text)
        local meterOn = selected and RPChroniclerDB.sizeMeter ~= false
        if meterOn then
            local limit, label = ns.GetAiLimit()
            local chars = #text
            local tokens = math.floor(chars / 4 + 0.5)
            local pct = math.floor(chars * 100 / math.max(1, limit) + 0.5)
            local color = (pct > 100 and "ff6b6b") or (pct > 80 and "ffb74d") or "5cb85c"
            local warn = (pct > 100) and ("  |cffff6b6bToo long for " .. label .. ": trim it in Options > Full Log|r") or ("  |cff8f9ba8for " .. label .. "|r")
            A.meterText:SetText(string.format("|cff8f9ba8Size:|r |cff%s%.1fk chars (~%.1fk tokens), %d%%|r%s",
                color, chars / 1000, tokens / 1000, pct, warn))
            A.meter:Show()
            A.boxBg:SetPoint("TOPLEFT", 0, -112)
        else
            A.meter:Hide()
            A.boxBg:SetPoint("TOPLEFT", 0, -94)
        end
    else
        A.meter:Hide()
        A.boxBg:SetPoint("TOPLEFT", 0, -94)
        A.summaryBtn:LockHighlight()
        A.editBox:SetText(ns.BuildAdventureSummary(selected))
    end
end

-- Opens Adventures on a run. mode: "SUMMARY" or "FULL" (nil keeps it)
function UI.OpenRecording(advId, mode)
    if advId then ns.state.selectedAdventureId = advId end
    if mode then ns.state.adventureViewMode = mode end
    if not UI.frame:IsShown() then
        RPChronicler_Open("", "ADVENTURES")
    elseif ns.state.section ~= "ADVENTURES" then
        UI.ShowSection("ADVENTURES")
    else
        UI.RefreshAdventuresTab()
    end
end

-- Old name (0.4.0 had sub-tabs): "BOOK" opens the Story Book section
function UI.ShowAdventuresSub(sub, advId)
    if sub == "BOOK" then
        local st = advId and ns.StoryForRun(advId)
        if UI.OpenStoryBook then UI.OpenStoryBook(st and st.id or nil) end
    else
        UI.OpenRecording(advId)
    end
end

local function SetMode(mode)
    ns.state.adventureViewMode = mode
    UI.RefreshAdventuresTab()
end
A.summaryBtn:SetScript("OnClick", function() SetMode("SUMMARY") end)
A.fullBtn:SetScript("OnClick", function() SetMode("FULL") end)

-- Story: jump to this run's story, or import one
A.storyBtn:SetScript("OnClick", function()
    local adv = GetSelectedAdventure()
    if not adv then return end
    local st = ns.StoryForRun(adv.id)
    if st then
        if UI.OpenStoryBook then UI.OpenStoryBook(st.id) end
    else
        OpenStoryImportModal(adv)
    end
end)

-- The template that fits the run type; right-click for the other
A.tplBtn:SetScript("OnClick", function(_, button)
    local adv = GetSelectedAdventure()
    local isWorld = not adv or adv.kind == "world"
    if button == "RightButton" then isWorld = not isWorld end
    if UI.OpenSkillTemplateModal then UI.OpenSkillTemplateModal(isWorld and "ADVENTURE" or "STORY") end
end)
UI.GetSelectedAdventure = GetSelectedAdventure

A.selectAllBtn:SetScript("OnClick", function()
    A.editBox:SetFocus()
    A.editBox:HighlightText()
    UI.SetStatus("Text selected. Press Ctrl+C to copy it.", "good")
end)

A.runBtn:SetScript("OnClick", function()
    RPChronicler_ToggleRun()
    UI.RefreshAdventuresTab()
end)
A.pauseBtn:SetScript("OnClick", function()
    RPChronicler_ToggleRunPause()
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
    for i, adv in ipairs(RPChroniclerDB.adventures or {}) do
        if adv.id == ns.state.selectedAdventureId then
            if not self.armedAt or GetTime() - self.armedAt > 4 then
                self.armedAt = GetTime()
                self:SetText("|cffff6b6bSure?|r")
                local keeps = ns.RunHasStory(adv) and " Its story stays in the Story Book." or ""
                UI.SetStatus("Click Delete again to remove " .. (adv.title or "this run") .. "." .. keeps, "error")
                return
            end
            self.armedAt = nil
            table.remove(RPChroniclerDB.adventures, i)
            if ns.Debug then ns.Debug("run", "deleted run " .. tostring(adv.title)) end
            ns.state.selectedAdventureId = nil
            adv.storyId = nil
            UI.SetStatus("Recording deleted.", "good")
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
end)
