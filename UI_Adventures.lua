local ADDON_NAME, ns = ...
local UI = ns.UI

-- =========================================================
-- Recording controls (buttons, keybinds and slash commands share these)
-- =========================================================
local function RefreshIfOpen()
    pcall(UI.RefreshRecordIcon)
    if UI.frame:IsShown() and ns.state.section == "ADVENTURES" then
        UI.RefreshAdventuresTab()
    elseif UI.frame:IsShown() and ns.state.section == "BOOK" then
        UI.RefreshStoryBook()
    end
end
UI.RefreshRunViews = RefreshIfOpen
-- 0.6.1: run code says ns.Notify("runChanged") and the views refresh
ns.Listen("runChanged", function() RefreshIfOpen() end)

local function Report(msg, kind)
    if UI.frame:IsShown() then
        UI.SetStatus(msg, kind)
    else
        local border = (kind == "error") and { 0.75, 0.28, 0.28 } or { 0.36, 0.72, 0.36 }
        UI.ShowToast("|cffffd100RP Chronicler:|r " .. msg, 2.4, border[1], border[2], border[3])
    end
end

function RPChronicler_StartRun()
    local run, why = ns.StartRun()
    if not run then
        Report(why or "Could not start recording.", "error")
        return
    end
    ns.state.selectedAdventureId = run.id
    Report("Recording adventure: " .. (run.title or "Adventure"), "good")
end

-- One toggle for Start / Stop (the button, the RP icon menu, keybinds)
function RPChronicler_ToggleRun()
    if ns.GetActiveAdventure() then RPChronicler_EndRun() else RPChronicler_StartRun() end
end

function RPChronicler_ToggleRunPause()
    if not ns.GetActiveAdventure() then
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

-- 0.6.3: a story note, the character's thought at this moment (/rp note,
-- the Note button and its key binding all come here)
function UI.AskStoryNote()
    local run = ns.GetActiveAdventure()
    if not run then
        Report("Start recording first: a note goes into a recording's Full Log.", "error")
        return
    end
    if run.paused then
        Report("Recording is paused. Resume it to add a note.", "error")
        return
    end
    UI.AskLine({
        title = "Story note",
        sub = "Your character's thought right now. It goes into the Full Log at this moment, and the story gives it to them as their inner voice.",
        placeholder = "e.g. Her warning still rings in my ears...",
        okText = "Add note",
        keys = "Enter: add   Esc: cancel",
        onAccept = function(text)
            if text == "" then return end
            local ok, msg = ns.RecordRunNote(text)
            Report(msg, ok and "good" or "error")
            if ok then RefreshIfOpen() end
        end,
    })
end
RPChronicler_StoryNote = UI.AskStoryNote

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
    local sub = UI.Label(f, "|cffd7c4a3Paste the colored story (Ctrl+V) and click Save to Story Book. The run is optional.|r", "GameFontHighlightSmall")
    sub:SetPoint("TOPLEFT", 14, -28)
    sub:SetPoint("RIGHT", f, "RIGHT", -36, 0)
    sub:SetJustifyH("LEFT")
    sub:SetWordWrap(false)

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
        -- 0.6.3: one import path; the run is optional (found by Run ID)
        local ok, storyId, linked = ns.ImportStory(raw, f.targetAdvId, f.targetStoryId)
        if ok then
            f:Hide()
            UI.OpenStoryBook(storyId)
            if linked then
                UI.SetStatus("Story saved to the Story Book, linked to " .. (linked.title or "its recording") .. ".", "good")
            else
                UI.SetStatus("Story saved to the Story Book (no linked recording).", "good")
            end
        else
            imp.title:SetText("|cffff6b6bCould not save this story.|r")
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

    -- 0.6.4: no AI? RP Chronicler writes a short chronicle of the picked
    -- run itself (Narrator.lua). A second click confirms replacing a story.
    local quickBtn = UI.CreateSleekButton(f, 160, 24, "Quick Chronicle (test)", "tool")
    quickBtn:SetPoint("RIGHT", cancelBtn, "LEFT", -6, 0)
    quickBtn.tipTitle = "|cffffd100Quick Chronicle|r |cffffb74d(test feature)|r"
    quickBtn.tipText = "A test feature: the writing is still rough. No AI? RP Chronicler writes a short chronicle of the run picked above from its own log: chapters, fights, quotes and your notes. A journal, not a novel. A story from your AI replaces it later."
    imp.quickBtn = quickBtn
    quickBtn:SetScript("OnClick", function(self)
        local adv = f.targetAdvId and ns.FindAdventure(f.targetAdvId)
        if not adv then
            imp.title:SetText("|cffff6b6bPick a run above first (use < and >).|r")
            return
        end
        if ns.RunHasStory(adv) and not self.armed then
            self.armed = true
            self:SetText("Replace story?")
            imp.title:SetText("|cffffb74dThis run has a story. Click again to replace it with a Quick Chronicle.|r")
            return
        end
        self.armed = false
        self:SetText("Quick Chronicle (test)")
        local ok, storyId = ns.SaveQuickChronicle(adv)
        if ok then
            f:Hide()
            UI.OpenStoryBook(storyId)
            UI.SetStatus("Quick Chronicle (test feature) written. For a full story, copy the Full Log for your AI.", "good")
        else
            imp.title:SetText("|cffff6b6bCould not write a Quick Chronicle for this run.|r")
        end
    end)
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

-- 0.6.3: the first choice links the story by the Run ID it carries (or
-- keeps it on its own); the others link it to one run you pick
local function ShowImportRun()
    local runs = AllRuns()
    -- Re-importing a story whose recording was deleted: no run to pick
    local st = imp.frame.targetStoryId and ns.FindStory(imp.frame.targetStoryId)
    if st and not ns.StoryRun(st) then
        imp.runLabel:SetText(string.format("|cfff5e6c8%s|r |cff9aa5b4- replaces this story|r", st.title or "Story"))
        imp.prev:Disable(); imp.next:Disable()
        return {}, 0
    end
    local idx = 0
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
        imp.runLabel:SetText("|cfff5e6c8Link automatically|r |cff9aa5b4- by the story's Run ID, or keep it without a recording|r")
    end
    if #runs > 0 then imp.prev:Enable(); imp.next:Enable() else imp.prev:Disable(); imp.next:Disable() end
    return runs, idx
end

local function StepImportRun(delta)
    local runs, idx = ShowImportRun()
    if #runs == 0 then return end
    idx = (idx + delta) % (#runs + 1)   -- 0 is "Link automatically"
    imp.frame.targetAdvId = runs[idx] and runs[idx].id or nil
    ShowImportRun()
end
imp.prev:SetScript("OnClick", function() StepImportRun(-1) end)
imp.next:SetScript("OnClick", function() StepImportRun(1) end)

-- adv: the run to import for (nil = the selected one); st: a story to replace
local function OpenStoryImportModal(adv, st)
    imp.frame.targetStoryId = st and st.id or nil
    if st and not adv then adv = ns.StoryRun(st) end
    imp.frame.targetAdvId = adv and adv.id or nil
    imp.title:SetText("|cffffd100Import Story from your AI|r")
    imp.quickBtn.armed = false
    imp.quickBtn:SetText("Quick Chronicle (test)")
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
UI.AddRailButton("ADVENTURES", "Adventures", UI.ICONS.ADVENTURES, "Record dungeon and open-world runs (raids: coming soon).")

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
UI.SetButtonLabels(A.runBtn, "Start Recording", "Start")

A.pauseBtn = UI.CreateSleekButton(A.recBar, 70, 22, "Pause")
A.pauseBtn:SetPoint("LEFT", A.runBtn, "RIGHT", 4, 0)

A.markBtn = UI.CreateSleekButton(A.recBar, 112, 22, "Mark Moment")
A.markBtn:SetPoint("LEFT", A.pauseBtn, "RIGHT", 4, 0)
A.markBtn:SetIcon(UI.ICONS.MARK, 16)
UI.SetButtonLabels(A.markBtn, "Mark Moment", "Mark")
A.markBtn.tipTitle = "|cffffd100Mark Moment|r"
A.markBtn.tipText = "Bookmark what just happened so the story gives it a scene. Also /rp mark <note>."

-- 0.6.3: a story note (your character's thought) at this moment
A.noteBtn = UI.CreateSleekButton(A.recBar, 60, 22, "Note")
A.noteBtn.tipTitle = "|cffffd100Story note|r"
A.noteBtn.tipText = "Write your character's thought at this moment. The story gives it to them as their inner voice. Also /rp note <text>."
A.noteBtn:SetScript("OnClick", function() UI.AskStoryNote() end)

A.recText = A.recBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
A.recText:SetPoint("TOPRIGHT", -8, -10)
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

-- 0.6.5 (Mor): runs sorted by type. The last tab you used is kept
-- (RPChroniclerDB.advFilter, not a setting). Raids: coming soon.
A.KIND_TABS = {
    { key = "all", label = "All" },
    { key = "world", label = "World", tip = "Open-world adventures." },
    { key = "dungeon", label = "Dgn", tip = "Dungeon runs." },
    { key = "raid", label = "Raid", tip = "Raids are coming soon (TBA).", soon = true },
}
A.kindBtns = {}
for i, t in ipairs(A.KIND_TABS) do
    local b = UI.CreateSleekButton(A.list, 40, 18, t.label, t.soon and nil or "tool")
    b:SetPoint("TOPLEFT", 6 + (i - 1) * 43, -26)
    b.tipTitle = "|cffffd100" .. (t.key == "all" and "All runs" or t.label) .. "|r"
    b.tipText = t.tip or "Every recording."
    b.kind = t.key
    if t.soon then b:Disable() end
    b:SetScript("OnClick", function()
        RPChroniclerDB.advFilter = t.key
        A.pickFirst = true
        UI.RefreshAdventuresTab()
    end)
    A.kindBtns[i] = b
end

A.listScroll = CreateFrame("ScrollFrame", "RPChroniclerAdvListScroll", A.list, "UIPanelScrollFrameTemplate")
A.listScroll:SetPoint("TOPLEFT", 6, -48)
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
    A.hero = hero
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
    A.heroIcon:SetTexture(UI.ICONS.ADVENTURES); A.heroIcon:SetTexCoord(ns.IconCoords(UI.ICONS.ADVENTURES))

    -- 0.6.3: the lines stack (the meta line may take two lines), and
    -- A.Layout sizes the hero to them
    local function HeroLine(template, below)
        local fs = hero:CreateFontString(nil, "OVERLAY", template)
        if below then
            fs:SetPoint("TOPLEFT", below, "BOTTOMLEFT", 0, -2)
        else
            fs:SetPoint("TOPLEFT", iconFrame, "TOPRIGHT", 10, -1)
        end
        fs:SetPoint("RIGHT", hero, "RIGHT", -10, 0)
        fs:SetJustifyH("LEFT")
        fs:SetWordWrap(false)
        return fs
    end
    A.heroTitle = HeroLine("GameFontNormal")
    A.heroMeta = HeroLine("GameFontHighlightSmall", A.heroTitle)
    A.heroMeta:SetWordWrap(true)
    if A.heroMeta.SetMaxLines then A.heroMeta:SetMaxLines(2) end
    A.heroStats = HeroLine("GameFontHighlightSmall", A.heroMeta)
end

-- 0.6.3: the Template button is gone (the story templates are in the
-- Story Book and Options > AI & Stories); A.Layout places this row
A.summaryBtn = UI.CreateSleekButton(A.right, 66, 22, "Summary")
A.fullBtn = UI.CreateSleekButton(A.right, 62, 22, "Full Log")
A.fullBtn.tipTitle = "|cffffd100Full Log|r"
A.fullBtn.tipText = "The whole run for your AI storyteller. Tick Include AI instructions, click Copy for AI, press Ctrl+C, and paste it into any AI chat."
A.storyBtn = UI.CreateSleekButton(A.right, 56, 22, "Story", "gold")
A.storyBtn.tipTitle = "|cffffd100Story|r"
-- 0.6.3: correct a wrong name before the story is written
-- 0.6.5: the run's editor (names, and the dungeon and roles)
A.fixBtn = UI.CreateSleekButton(A.right, 70, 22, "Edit run", "tool")
UI.SetButtonLabels(A.fixBtn, "Edit run", "Edit")
A.fixBtn.tipTitle = "|cffffd100Edit run|r"
A.fixBtn.tipText = "Fix this run before you copy the Full Log, even while it records: pick its dungeon, set a member's role, or replace a wrong name. The recording keeps the originals, so every change can be undone."

A.delBtn = UI.CreateSleekButton(A.right, 56, 22, "Delete", "danger")
A.delBtn.tipTitle = "|cffff6b6bDelete|r"
A.delBtn.tipText = "Click twice to delete this run."
A.selectAllBtn = UI.CreateSleekButton(A.right, 80, 22, "Select All", "gold")
UI.SetButtonLabels(A.selectAllBtn, "Select All", "All")
A.rowBottom = 94

-- Full Log size meter (Options > Full Log picks the AI and can hide it)
A.meter = CreateFrame("Button", nil, A.right)
A.meter:SetHeight(16)
A.meter:SetPoint("TOPLEFT", 2, -92)
A.meter:SetPoint("TOPRIGHT", -2, -92)
-- 0.6.5 (Mor): "Include AI instructions" (off by default, per run while
-- you look at it): the story rules go in front of the log, and the size
-- follows at once
A.rulesCheck = CreateFrame("CheckButton", "RPChroniclerAdvRulesCheck", A.meter, "UICheckButtonTemplate")
A.rulesCheck:SetSize(20, 20)
A.rulesCheck:SetPoint("LEFT", -2, 0)
A.rulesLbl = A.meter:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
A.rulesLbl:SetPoint("LEFT", A.rulesCheck, "RIGHT", 0, 0)
A.rulesLbl:SetText("|cffd8dee9Include AI instructions|r")
A.rulesCheck:SetScript("OnEnter", function(self)
    UI.Tooltip(self, "|cffffd100Include AI instructions|r",
        "Puts the story rules in front of the Full Log, so any AI chat writes the story from one paste.",
        "Leave it off if your AI already has the storyteller skill.")
end)
A.rulesCheck:SetScript("OnLeave", UI.HideTooltip)
A.rulesCheck:SetScript("OnClick", function(self)
    local adv = UI.GetSelectedAdventure and UI.GetSelectedAdventure()
    A.rulesFor = (self:GetChecked() and adv) and adv.id or nil
    UI.RefreshAdventuresTab()
end)
A.meterText = A.meter:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
A.meterText:SetPoint("LEFT", A.rulesLbl, "RIGHT", 10, 0)
A.meterText:SetPoint("RIGHT", A.meter, "RIGHT", 0, 0)
A.meterText:SetJustifyH("LEFT")
A.meterText:SetWordWrap(false)
A.meter:SetScript("OnEnter", function(self)
    UI.Tooltip(self, "|cffffd100Full Log size|r",
        "The length of what you copy. " .. math.floor(ns.LOG_SIZE_BASELINE / 1000) .. "k fits most free AI chats; paid ones can fit a lot more words.",
        "Too long? Pick a shorter Log detail in Options > Recording, or turn off busy groups.")
end)
A.meter:SetScript("OnLeave", UI.HideTooltip)
A.meter:SetScript("OnClick", function()
    UI.OpenOptionsPage("RECORDING")
end)
A.meter:Hide()

-- 0.6.3: the record bar, the hero and the button row follow the window
-- and font size (UI.FlowRow); what sits below them follows their height
function A.Layout()
    local barW = A.recBar:GetWidth() or 0
    if barW < 50 then return end
    local textW = math.ceil((A.recText:GetStringWidth() or 0) + 12)
    local reserve = math.max(60, math.min(textW, math.floor(barW * 0.4)))
    A.recText:SetWidth(reserve - 8)
    A.runBtn.extraW = A.runBtn.dot:IsShown() and 10 or 0
    local h = UI.FlowRow(A.recBar, { A.runBtn, A.pauseBtn, A.markBtn, A.noteBtn }, nil, { x = 4, y = 4, width = barW - 8 - reserve })
    A.recBar:SetHeight(h + 8)
    local heroH = 14 + (A.heroTitle:GetStringHeight() or 12) + (A.heroMeta:GetStringHeight() or 12) + (A.heroStats:GetStringHeight() or 12)
    heroH = math.max(60, math.ceil(heroH))
    A.hero:SetHeight(heroH)
    local rowH = UI.FlowRow(A.right, { A.summaryBtn, A.fullBtn, A.storyBtn, A.fixBtn }, { A.selectAllBtn, A.delBtn }, { y = heroH + 6 })
    A.rowBottom = heroH + 6 + rowH + 6
    A.meter:ClearAllPoints()
    A.meter:SetPoint("TOPLEFT", 2, -A.rowBottom + 2)
    A.meter:SetPoint("TOPRIGHT", -2, -A.rowBottom + 2)
    A.boxBg:ClearAllPoints()
    A.boxBg:SetPoint("BOTTOMRIGHT", 0, 0)
    A.boxBg:SetPoint("TOPLEFT", 0, -(A.rowBottom + (A.meter:IsShown() and 18 or 0)))
end

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
        A.heroIcon:SetTexture(UI.ICONS.ADVENTURES); A.heroIcon:SetTexCoord(ns.IconCoords(UI.ICONS.ADVENTURES))
        A.heroTitle:SetText("|cffffd100No Adventure Selected|r")
        A.heroMeta:SetText("|cff9aa5b4Enter a dungeon, or click Start Recording above.|r")
        A.heroStats:SetText("")
        return
    end
    A.heroIcon:SetTexture(ns.GetAdventureIcon(adv)); A.heroIcon:SetTexCoord(ns.IconCoords(ns.GetAdventureIcon(adv)))
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
        UI.SetButtonLabels(A.runBtn, "Stop & Save", "Stop")
        A.runBtn.dot:Hide()
        A.runBtn.label:SetPoint("LEFT", 5, 0)
        A.pauseBtn:Enable()
        if active.paused then
            A.pauseBtn:SetText("|cff5cb85cResume|r")
            A.pauseBtn:LockHighlight()
            A.markBtn:Disable()
            A.noteBtn:Disable()
            A.recText:SetText("|cffffb74dPaused:|r |cffd8dee9" .. (active.title or "Adventure") .. "|r")
        else
            A.pauseBtn:SetText("|cffffb74dPause|r")
            A.pauseBtn:UnlockHighlight()
            A.markBtn:Enable()
            A.noteBtn:Enable()
            local mins = math.floor(math.max(0, time() - (active.startTime or time())) / 60)
            A.recText:SetText(string.format("|cffff6b6bRecording:|r |cffd8dee9%s (%dm)|r", active.title or "Adventure", mins))
        end
    else
        A.runBtn.accentStyle = "good"
        A.runBtn.ApplyNormalLook()
        UI.SetButtonLabels(A.runBtn, "Start Recording", "Start")
        A.runBtn.dot:Show()
        A.runBtn.label:SetPoint("LEFT", 14, 0)
        A.pauseBtn:SetText("Pause")
        A.pauseBtn:UnlockHighlight()
        A.pauseBtn:Disable()
        A.markBtn:Disable()
        A.noteBtn:Disable()
        A.recText:SetText("|cff8f9ba8Not recording|r")
    end
end

function UI.RefreshAdventuresTab()
    UI.EnsureOptions()
    local active = ns.GetActiveAdventure()
    UpdateRecordBar(active)

    for _, card in ipairs(A.cards) do card:Hide() end
    local entries = {}
    local filter = RPChroniclerDB.advFilter or "all"
    local counts = { all = 0 }
    local function Add(adv, isLive)
        local k = adv.kind or "world"
        counts.all, counts[k] = counts.all + 1, (counts[k] or 0) + 1
        if filter == "all" or k == filter then table.insert(entries, { adv = adv, isLive = isLive }) end
    end
    if active then Add(active, true) end
    for _, adv in ipairs(RPChroniclerDB.adventures or {}) do Add(adv, false) end
    if A.pickFirst then
        A.pickFirst = nil
        local inList = false
        for _, e in ipairs(entries) do if e.adv.id == ns.state.selectedAdventureId then inList = true end end
        if not inList and entries[1] then ns.state.selectedAdventureId = entries[1].adv.id end
    end
    for _, b in ipairs(A.kindBtns) do
        if b.kind == filter then b:LockHighlight() else b:UnlockHighlight() end
        if b.kind ~= "raid" then
            b.tipText = (b.kind == "all" and "Every recording" or (b.kind == "world" and "Open-world adventures" or "Dungeon runs")) .. ": " .. (counts[b.kind] or 0) .. "."
        end
    end

    for idx, item in ipairs(entries) do
        local adv = item.adv
        local card = A.cards[idx]
        if not card then
            card = CreateAdventureCard(A.listChild)
            A.cards[idx] = card
        end
        card:SetPoint("TOPLEFT", 0, -(idx - 1) * 48)
        card.icon:SetTexture(ns.GetAdventureIcon(adv)); card.icon:SetTexCoord(ns.IconCoords(ns.GetAdventureIcon(adv)))
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
    if selected then A.storyBtn:Enable(); A.fixBtn:Enable() else A.storyBtn:Disable(); A.fixBtn:Disable() end
    local nFix = selected and type(selected.fixes) == "table" and #selected.fixes or 0
    UI.SetButtonLabels(A.fixBtn, nFix > 0 and ("Edit run (" .. nFix .. ")") or "Edit run", "Edit")
    if UI.fixNames and UI.fixNames:IsShown() then UI.RefreshFixNames() end
    A.summaryBtn:UnlockHighlight()
    A.fullBtn:UnlockHighlight()

    local mode = ns.state.adventureViewMode
    if mode ~= "FULL" then mode = "SUMMARY" end
    if mode == "FULL" then
        A.fullBtn:LockHighlight()
        -- 0.6.5: the box shows the log alone; Include AI instructions adds
        -- the story rules (until you switch runs or views)
        local withRules = selected and A.rulesFor == selected.id or false
        local text = ns.BuildAiText(selected, withRules)
        A.editBox:SetText(text)
        A.rulesCheck:SetChecked(withRules and true or false)
        UI.SetButtonLabels(A.selectAllBtn, "Copy for AI", "Copy")
        A.selectAllBtn.tipTitle = "|cffffd100Copy for AI|r"
        A.selectAllBtn.tipText = "Selects the Full Log (with the story rules when Include AI instructions is on). Press Ctrl+C, paste it into your AI, then Import the story it writes."
        if selected then
            -- 0.6.5: one fixed baseline; the meter counts what is copied
            local limit = ns.LOG_SIZE_BASELINE
            local chars = #text
            local pct = math.floor(chars * 100 / math.max(1, limit) + 0.5)
            local color = (pct > 100 and "ff6b6b") or (pct > 80 and "ffb74d") or "5cb85c"
            A.meterText:SetText(string.format("|cff8f9ba8Size:|r |cff%s%.1fk chars (%d%% of %dk).|r |cff8f9ba8%dk fits most free AI chats; paid ones can fit a lot more words.|r",
                color, chars / 1000, pct, math.floor(limit / 1000), math.floor(limit / 1000)))
            A.meter:Show()
        else
            A.meter:Hide()
        end
    else
        A.meter:Hide()
        UI.SetButtonLabels(A.selectAllBtn, "Select All", "All")
        A.selectAllBtn.tipTitle, A.selectAllBtn.tipText = nil, nil
        A.summaryBtn:LockHighlight()
        A.editBox:SetText(ns.BuildAdventureSummary(selected))
    end
    A.Layout()
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
        UI.OpenStoryBook(st and st.id or nil)
    else
        UI.OpenRecording(advId)
    end
end

local function SetMode(mode)
    A.rulesFor = nil
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
        UI.OpenStoryBook(st.id)
    else
        OpenStoryImportModal(adv)
    end
end)

UI.GetSelectedAdventure = GetSelectedAdventure

A.selectAllBtn:SetScript("OnClick", function()
    local adv = GetSelectedAdventure()
    local full = ns.state.adventureViewMode == "FULL" and adv
    -- 0.6.5: the checkbox above the box decides whether the rules go in
    local withRules = full and A.rulesFor == adv.id
    A.editBox:SetFocus()
    A.editBox:HighlightText()
    if withRules then
        UI.SetStatus("Full Log and story rules selected. Press Ctrl+C, paste it into any AI chat, then Import the story.", "good")
    elseif full then
        UI.SetStatus("Full Log selected (no AI instructions). Press Ctrl+C to copy it.", "good")
    else
        UI.SetStatus("Text selected. Press Ctrl+C to copy it.", "good")
    end
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
        ns.RequestScreenshot("mark", "Marked moment")
        UI.RefreshAdventuresTab()
    end
end)

A.delBtn:SetScript("OnClick", function(self)
    local active = ns.GetActiveAdventure()
    if active and ns.state.selectedAdventureId == active.id then
        UI.SetStatus("End the live run before deleting it.", "error")
        return
    end
    for _, adv in ipairs(RPChroniclerDB.adventures or {}) do
        if adv.id == ns.state.selectedAdventureId then
            if not self.armedAt or GetTime() - self.armedAt > 4 then
                self.armedAt = GetTime()
                self:SetText("|cffff6b6bSure?|r")
                local keeps = ns.RunHasStory(adv) and " Its story stays in the Story Book." or ""
                UI.SetStatus("Click Delete again to remove " .. (adv.title or "this run") .. "." .. keeps, "error")
                return
            end
            self.armedAt = nil
            local ok, why = ns.DeleteRun(adv.id)
            if not ok then UI.SetStatus(why, "error") return end
            ns.state.selectedAdventureId = nil
            UI.SetStatus("Recording deleted.", "good")
            UI.RefreshAdventuresTab()
            return
        end
    end
end)

-- =========================================================
-- Fix names (0.6.3): replace a wrong name in a run before the story is
-- written. The fixes are a list on the run (ns.AddRunFix); the recording
-- keeps every original name, so Undo brings it back.
-- =========================================================
do
    local f = CreateFrame("Frame", "RPChroniclerFixNamesFrame", UIParent, UI.BACKDROP)
    f:SetSize(480, 300)
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 20)
    f:SetFrameStrata("FULLSCREEN_DIALOG")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:SetClampedToScreen(true)
    f:Hide()
    UI.ApplyDarkGlass(f, 0.05, 0.06, 0.08, 0.97, 0.78, 0.62, 0.28, 0.85)
    if type(UISpecialFrames) == "table" then table.insert(UISpecialFrames, "RPChroniclerFixNamesFrame") end
    UI.fixNames = f
    local F = { chips = {}, rows = {} }

    F.roleRows = {}
    F.title = UI.Label(f, "", "GameFontNormal")
    F.title:SetPoint("TOPLEFT", 14, -12)
    F.title:SetPoint("RIGHT", -36, 0)
    F.title:SetWordWrap(false)
    F.sub = UI.Label(f, "|cffb0bac5Fix the run before you copy the Full Log, even while it records. The recording keeps the originals, so Undo brings them back.|r", "GameFontHighlightSmall")
    F.sub:SetPoint("TOPLEFT", 14, -30)
    F.sub:SetPoint("RIGHT", -14, 0)
    F.sub:SetWordWrap(true)
    local closeX = UI.CreateSleekButton(f, 22, 20, "x", "danger")
    closeX:SetPoint("TOPRIGHT", -8, -8)
    closeX:SetScript("OnClick", function() f:Hide() end)

    F.chipHead = UI.Label(f, "|cffd8dee9Names in this run (click one):|r", "GameFontHighlightSmall")
    F.chipBox = CreateFrame("Frame", nil, f)

    local function Box(label)
        local l = UI.Label(f, "|cffd8dee9" .. label .. "|r", "GameFontHighlightSmall")
        local eb = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
        eb:SetSize(180, 20)
        eb:SetAutoFocus(false)
        eb:SetMaxLetters(80)
        eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
        return l, eb
    end
    F.fromLbl, F.from = Box("Wrong name")
    F.toLbl, F.to = Box("Right name")
    F.save = UI.CreateSleekButton(f, 80, 22, "Replace", "gold")
    F.from:SetScript("OnTabPressed", function() F.to:SetFocus() end)
    F.to:SetScript("OnTabPressed", function() F.from:SetFocus() end)
    F.listHead = UI.Label(f, "", "GameFontHighlightSmall")
    F.done = UI.CreateSleekButton(f, 70, 22, "Done")
    F.done:SetScript("OnClick", function() f:Hide() end)

    local function Run() return f.advId and ns.FindAdventure(f.advId) end

    -- 0.6.5 (Mor): the dungeon, picked from a list (dungeon runs only)
    F.dunLbl = UI.Label(f, "", "GameFontHighlightSmall")
    F.dunLbl:SetWordWrap(false)
    F.dunBtn = UI.CreateSleekButton(f, 90, 20, "Change", "gold")
    F.dunUndo = UI.CreateSleekButton(f, 52, 20, "Undo", "danger")
    local pick = CreateFrame("Frame", nil, f, UI.BACKDROP)
    pick:SetFrameStrata("TOOLTIP")
    pick:SetClampedToScreen(true)
    pick:EnableMouse(true)
    pick:Hide()
    UI.ApplyDarkGlass(pick, 0.04, 0.05, 0.07, 0.98, 0.82, 0.65, 0.30, 0.90)
    F.pickBtns = {}
    local function ShowPick()
        if pick:IsShown() then pick:Hide() return end
        local list = ns.DungeonList()
        local cols = 2
        local rows = math.ceil(#list / cols)
        for _, b in ipairs(F.pickBtns) do b:Hide() end
        for i, d in ipairs(list) do
            local b = F.pickBtns[i]
            if not b then
                b = UI.CreateSleekButton(pick, 200, 18, "")
                F.pickBtns[i] = b
            end
            local c, r = math.floor((i - 1) / rows), (i - 1) % rows
            b:ClearAllPoints()
            b:SetPoint("TOPLEFT", 6 + c * 204, -6 - r * 20)
            b:SetText(d.name .. (d.levels and ("  |cff8f9ba8" .. d.levels .. "|r") or ""))
            b:SetScript("OnClick", function()
                pick:Hide()
                local adv = Run()
                if not adv then return end
                local ok, why = ns.SetRunDungeon(adv.id, d.name, d.ej)
                UI.SetStatus(ok and ("Dungeon set: " .. d.name .. ".") or why, ok and "good" or "error")
                UI.RefreshFixNames()
            end)
            b:Show()
        end
        pick:SetSize(12 + cols * 204, 12 + rows * 20)
        pick:ClearAllPoints()
        pick:SetPoint("TOPLEFT", F.dunBtn, "BOTTOMLEFT", 0, -2)
        pick:Show()
    end
    F.dunBtn:SetScript("OnClick", ShowPick)
    F.dunUndo:SetScript("OnClick", function()
        local adv = Run()
        if not adv then return end
        local ok, why = ns.SetRunDungeon(adv.id, nil)
        UI.SetStatus(ok and "The recorded dungeon is back." or why, ok and "good" or "error")
        UI.RefreshFixNames()
    end)
    f:HookScript("OnHide", function() pick:Hide() end)

    -- 0.6.5 (Mor): each member's role; only the roles their class can take
    F.roleHead = UI.Label(f, "|cffd8dee9Roles (a role you set wins over the game's):|r", "GameFontHighlightSmall")
    local ROLE_NAMES = { TANK = "Tank", HEALER = "Healer", DAMAGER = "Damage" }
    local function RoleRow(i)
        local r = F.roleRows[i]
        if r then return r end
        r = { name = UI.Label(f, "", "GameFontHighlightSmall"), btns = {} }
        r.name:SetWordWrap(false)
        for k = 1, 3 do r.btns[k] = UI.CreateSleekButton(f, 62, 18, "") end
        r.auto = UI.CreateSleekButton(f, 52, 18, "Undo", "danger")
        F.roleRows[i] = r
        return r
    end
    local function LayoutRoles(adv, y, W)
        for _, r in ipairs(F.roleRows) do
            r.name:Hide(); r.auto:Hide()
            for _, b in ipairs(r.btns) do b:Hide() end
        end
        local roster = ns.MergedRoster(adv.participants)
        F.roleHead:ClearAllPoints()
        F.roleHead:SetPoint("TOPLEFT", 14, -y)
        if #roster == 0 then F.roleHead:Hide() return y end
        F.roleHead:Show()
        y = y + 16
        for i, p in ipairs(roster) do
            if i > 10 then break end
            local r = RoleRow(i)
            local tok = ns.ClassToken(p.classFile) or ns.ClassToken(p.class)
            local color = tok and ns.CLASS_COLORS[tok] or "f5e6c8"
            r.name:ClearAllPoints()
            r.name:SetPoint("TOPLEFT", 18, -(y + 3))
            r.name:SetWidth(150)
            r.name:SetText("|cff" .. tostring(color) .. tostring(p.name) .. "|r")
            r.name:Show()
            local roles = ns.ClassRoles(tok)
            local x = 172
            if #roles <= 1 then
                local b = r.btns[1]
                b:ClearAllPoints()
                b:SetPoint("TOPLEFT", x, -y)
                b:SetText(ROLE_NAMES[roles[1] or "DAMAGER"] or "Damage")
                b:LockHighlight()
                b:Disable()
                b:Show()
            else
                for k, role in ipairs(roles) do
                    local b = r.btns[k]
                    b:Enable()
                    b:ClearAllPoints()
                    b:SetPoint("TOPLEFT", x + (k - 1) * 66, -y)
                    b:SetText(ROLE_NAMES[role])
                    if p.role == role then b:LockHighlight() else b:UnlockHighlight() end
                    b:SetScript("OnClick", function()
                        local ok, why = ns.SetMemberRole(adv.id, p.name, role)
                        UI.SetStatus(ok and (p.name .. " is " .. ROLE_NAMES[role] .. " now.") or why, ok and "good" or "error")
                        UI.RefreshFixNames()
                    end)
                    b:Show()
                end
                if p.roleByHand then
                    r.auto:ClearAllPoints()
                    r.auto:SetPoint("TOPLEFT", x + #roles * 66 + 4, -y)
                    r.auto:SetScript("OnClick", function()
                        ns.SetMemberRole(adv.id, p.name, nil)
                        UI.SetStatus("The recorded role is back for " .. p.name .. ".", "good")
                        UI.RefreshFixNames()
                    end)
                    r.auto:Show()
                end
            end
            y = y + 22
        end
        return y + 6
    end

    function UI.RefreshFixNames()
        local adv = Run()
        if not adv then f:Hide() return end
        F.title:SetText("|cffffd100Edit run:|r |cfff5e6c8" .. (adv.title or "Adventure") .. "|r")
        local W = f:GetWidth() - 28
        local y = 30 + math.ceil(F.sub:GetStringHeight() or 28) + 10
        if adv.kind ~= "world" then
            F.dunLbl:ClearAllPoints()
            F.dunLbl:SetPoint("TOPLEFT", 14, -(y + 3))
            F.dunLbl:SetPoint("RIGHT", f, "RIGHT", -170, 0)
            F.dunLbl:SetText("|cffd8dee9Dungeon:|r |cfff5e6c8" .. tostring(adv.instanceName or adv.zone or "?") .. "|r")
            F.dunBtn:ClearAllPoints()
            F.dunBtn:SetPoint("TOPRIGHT", -70, -y)
            F.dunUndo:ClearAllPoints()
            F.dunUndo:SetPoint("TOPRIGHT", -14, -y)
            F.dunLbl:Show(); F.dunBtn:Show()
            if adv.instanceRecorded then F.dunUndo:Show() else F.dunUndo:Hide() end
            y = y + 28
        else
            F.dunLbl:Hide(); F.dunBtn:Hide(); F.dunUndo:Hide()
        end
        y = LayoutRoles(adv, y, W)
        F.chipHead:ClearAllPoints()
        F.chipHead:SetPoint("TOPLEFT", 14, -y)
        y = y + 16
        local names = ns.RunNames(adv)
        for _, c in ipairs(F.chips) do c:Hide() end
        local list = {}
        for i, n in ipairs(names) do
            local c = F.chips[i]
            if not c then
                c = UI.CreateSleekButton(F.chipBox, 60, 18, "")
                c:SetScript("OnClick", function(self)
                    F.from:SetText(self.name)
                    F.to:SetText(self.name)
                    F.to:SetFocus()
                    F.to:HighlightText()
                end)
                F.chips[i] = c
            end
            c.name = n
            c:SetText(n)
            c:Show()
            list[i] = c
        end
        F.chipBox:ClearAllPoints()
        F.chipBox:SetPoint("TOPLEFT", 14, -y)
        F.chipBox:SetSize(W, 20)
        local chipH = (#list > 0) and UI.FlowRow(F.chipBox, list, nil, { width = W, rowH = 18, gap = 4 }) or 0
        if #list == 0 then F.chipHead:SetText("|cff8f9ba8No names recorded in this run yet.|r") else F.chipHead:SetText("|cffd8dee9Fix a name (click one):|r") end
        y = y + chipH + 12
        F.fromLbl:ClearAllPoints(); F.fromLbl:SetPoint("TOPLEFT", 14, -y)
        F.toLbl:ClearAllPoints(); F.toLbl:SetPoint("TOPLEFT", 214, -y)
        y = y + 14
        F.from:ClearAllPoints(); F.from:SetPoint("TOPLEFT", 20, -y)
        F.to:ClearAllPoints(); F.to:SetPoint("TOPLEFT", 220, -y)
        F.save:ClearAllPoints(); F.save:SetPoint("TOPLEFT", 410, -y)
        F.save:SetWidth(math.max(56, W - 396))
        y = y + 30
        local fixes = type(adv.fixes) == "table" and adv.fixes or {}
        F.listHead:ClearAllPoints()
        F.listHead:SetPoint("TOPLEFT", 14, -y)
        F.listHead:SetText(#fixes > 0 and "|cffd8dee9Fixes in this run:|r" or "|cff8f9ba8No fixes yet.|r")
        y = y + 16
        for _, r in ipairs(F.rows) do r.text:Hide(); r.undo:Hide() end
        for i, fx in ipairs(fixes) do
            if i > 10 then break end
            local r = F.rows[i]
            if not r then
                r = { text = UI.Label(f, "", "GameFontHighlightSmall"), undo = UI.CreateSleekButton(f, 52, 18, "Undo", "danger") }
                r.text:SetWordWrap(false)
                F.rows[i] = r
            end
            r.text:ClearAllPoints()
            r.text:SetPoint("TOPLEFT", 18, -(y + 3))
            r.text:SetPoint("RIGHT", f, "RIGHT", -76, 0)
            r.text:SetText("|cff9e9e9e" .. fx.from .. "|r  |cffd8dee9->|r  |cfff5e6c8" .. fx.to .. "|r")
            r.undo:ClearAllPoints()
            r.undo:SetPoint("TOPRIGHT", -14, -y)
            r.undo:SetScript("OnClick", function()
                ns.RemoveRunFix(adv.id, i)
                UI.SetStatus("Fix undone: " .. fx.from .. " is back.", "good")
                UI.RefreshFixNames()
            end)
            r.text:Show()
            r.undo:Show()
            y = y + 22
        end
        F.done:ClearAllPoints()
        F.done:SetPoint("BOTTOMRIGHT", -14, 10)
        f:SetHeight(y + 44)
    end

    F.save:SetScript("OnClick", function()
        local adv = Run()
        if not adv then return end
        local ok, why = ns.AddRunFix(adv.id, F.from:GetText(), F.to:GetText())
        if ok then
            UI.SetStatus("Fixed: the Full Log now says " .. ns.StripColors((F.to:GetText() or ""):gsub("||", "|")) .. ".", "good")
            F.from:SetText("")
            F.to:SetText("")
            F.from:ClearFocus()
            F.to:ClearFocus()
        else
            UI.SetStatus(why or "Could not save the fix.", "error")
        end
        UI.RefreshFixNames()
    end)
    F.to:SetScript("OnEnterPressed", function() F.save:Click() end)
    F.from:SetScript("OnEnterPressed", function() F.to:SetFocus() end)

    function UI.OpenFixNames(advId)
        f.advId = advId
        F.from:SetText("")
        F.to:SetText("")
        f:Show()
        UI.RefreshFixNames()
    end
end

A.fixBtn:SetScript("OnClick", function()
    local adv = GetSelectedAdventure()
    if adv then UI.OpenFixNames(adv.id) end
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
        A.Layout()
    end)
end

UI.AddReflow(function()
    if A.recView:IsVisible() then A.Layout() end
    local w = A.scroll:GetWidth()
    if w and w > 50 then A.editBox:SetWidth(w) end
end)
