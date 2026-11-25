local ADDON_NAME, ns = ...
local UI = ns.UI

-- =========================================================
-- Keybinds: override bindings that click hidden buttons.
-- Set only out of combat (never a protected call in combat).
-- The same actions are in the game's Key Bindings (Bindings.xml).
-- =========================================================
local function SilentButton(name, onClick)
    local b = CreateFrame("Button", name, UIParent)
    b:SetSize(1, 1)
    b:SetPoint("BOTTOMLEFT", 0, 0)
    b:SetScript("OnClick", onClick)
    return b
end

local function NotTyping()
    local focused = GetCurrentKeyBoardFocus and GetCurrentKeyBoardFocus()
    return not focused or focused == _G.RPChroniclerSilentArmBox
end

SilentButton("RPChroniclerSilentCaptureBtn", function() RPChronicler_CaptureTarget() end)
SilentButton("RPChroniclerSilentMarkBtn", function()
    if NotTyping() and RPChronicler_MarkMoment then RPChronicler_MarkMoment() end
end)
SilentButton("RPChroniclerSilentOpenBtn", function()
    if NotTyping() then RPChronicler_Toggle() end
end)
SilentButton("RPChroniclerSilentRunStartBtn", function()
    if NotTyping() then RPChronicler_StartRun() end
end)
SilentButton("RPChroniclerSilentRunPauseBtn", function()
    if NotTyping() then RPChronicler_ToggleRunPause() end
end)
SilentButton("RPChroniclerSilentRunEndBtn", function()
    if NotTyping() then RPChronicler_EndRun() end
end)

local KEY_TO_BUTTON = {
    { field = "markMomentKey", button = "RPChroniclerSilentMarkBtn" },
    { field = "openWindowKey", button = "RPChroniclerSilentOpenBtn" },
    { field = "runStartKey", button = "RPChroniclerSilentRunStartBtn" },
    { field = "runPauseKey", button = "RPChroniclerSilentRunPauseBtn" },
    { field = "runEndKey", button = "RPChroniclerSilentRunEndBtn" },
}

local bindOwner = CreateFrame("Frame", "RPChroniclerBindManagerFrame", UIParent)

function UI.UpdateOverrideBindings()
    if InCombatLockdown and InCombatLockdown() then
        UI.bindingsPending = true
        return
    end
    UI.bindingsPending = false
    UI.EnsureOptions()
    if ClearOverrideBindings then ClearOverrideBindings(bindOwner) end
    if not SetOverrideBindingClick then return end
    local db = RPChroniclerDB
    -- Quick Copy: Ctrl+C (both copy styles) or a custom key. When the hidden
    -- copy box already has focus, the keystroke goes to it and copies.
    if db.quickCtrlC and db.quickCopyKey and db.quickCopyKey ~= "" then
        SetOverrideBindingClick(bindOwner, false, db.quickCopyKey, "RPChroniclerSilentCopyBtn")
    end
    if db.quickCapture and db.captureTargetKey and db.captureTargetKey ~= "" then
        SetOverrideBindingClick(bindOwner, false, db.captureTargetKey, "RPChroniclerSilentCaptureBtn")
    end
    for _, kb in ipairs(KEY_TO_BUTTON) do
        local key = db[kb.field]
        if key and key ~= "" then
            SetOverrideBindingClick(bindOwner, false, key, kb.button)
        end
    end
end

bindOwner:RegisterEvent("PLAYER_LOGIN")
bindOwner:RegisterEvent("PLAYER_REGEN_DISABLED")
bindOwner:RegisterEvent("PLAYER_REGEN_ENABLED")
bindOwner:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_REGEN_DISABLED" then
        UI.DisarmCtrlCopy()
    else
        UI.UpdateOverrideBindings()
    end
end)

-- =========================================================
-- Floating [RP] button (draggable; stays where you put it)
-- =========================================================
local miniBtn = UI.CreateSleekButton(UIParent, 38, 22, "|cffffd100RP|r", "gold")
miniBtn:SetPoint("CENTER", UIParent, "CENTER", -300, -180)
miniBtn:SetMovable(true)
miniBtn:EnableMouse(true)
miniBtn:RegisterForDrag("LeftButton")
miniBtn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
miniBtn:SetScript("OnDragStart", miniBtn.StartMoving)
miniBtn:SetScript("OnDragStop", miniBtn.StopMovingOrSizing)
UI.miniBtn = miniBtn

-- Right-click menu (0.4.0): Start/Stop, Pause/Resume, Mark Moment, Story
-- Book, Clear logs. A plain frame, so it works in combat too.
do
    local menu = CreateFrame("Frame", "RPChroniclerIconMenu", UIParent, UI.BACKDROP)
    menu:SetSize(170, 10)
    menu:SetFrameStrata("FULLSCREEN_DIALOG")
    menu:Hide()
    UI.ApplyDarkGlass(menu, 0.05, 0.07, 0.10, 0.97, 0.82, 0.65, 0.30, 0.90)
    UI.iconMenu = menu

    local items = {
        { key = "run", fn = function() RPChronicler_ToggleRun() end },
        { key = "pause", fn = function() RPChronicler_ToggleRunPause() end },
        { key = "mark", label = "Mark Moment", fn = function() if RPChronicler_MarkMoment then RPChronicler_MarkMoment() end end },
        -- 0.5.0: straight to the live run's Full Log
        { key = "open", label = "Open current recording", fn = function()
            local run = ns.GetActiveAdventure and ns.GetActiveAdventure()
            if run and UI.OpenRecording then UI.OpenRecording(run.id, "FULL") end
        end },
        { key = "book", label = "Story Book", fn = function() if UI.OpenStoryBook then UI.OpenStoryBook() end end },
        { key = "clear", label = "Clear chat logs", fn = function()
            ns.ClearSessionLogs()
            print("|cff00ff00[RP Chronicler]|r All logs cleared.")
        end },
    }
    for i, it in ipairs(items) do
        local b = UI.CreateSleekButton(menu, 158, 20, it.label or "", it.key == "run" and "good" or nil)
        b:SetPoint("TOP", 0, -6 - (i - 1) * 22)
        b:SetScript("OnClick", function()
            menu:Hide()
            pcall(it.fn)
        end)
        it.btn = b
    end
    menu:SetHeight(12 + #items * 22)

    local function Refresh()
        local run = ns.GetActiveAdventure and ns.GetActiveAdventure()
        local runBtn, pauseBtn, markBtn, openBtn = items[1].btn, items[2].btn, items[3].btn, items[4].btn
        if run then openBtn:Enable() else openBtn:Disable() end
        runBtn.accentStyle = run and "danger" or "good"
        runBtn.ApplyNormalLook()
        runBtn:SetText(run and "Stop & Save" or "Start Recording")
        if run then pauseBtn:Enable() else pauseBtn:Disable() end
        pauseBtn:SetText((run and run.paused) and "Resume" or "Pause")
        if run and not run.paused then markBtn:Enable() else markBtn:Disable() end
    end

    function UI.ToggleIconMenu()
        if menu:IsShown() then menu:Hide() return end
        Refresh()
        menu:ClearAllPoints()
        local y = miniBtn:GetBottom() or 0
        if y > 160 then
            menu:SetPoint("TOPLEFT", miniBtn, "BOTTOMLEFT", 0, -2)
        else
            menu:SetPoint("BOTTOMLEFT", miniBtn, "TOPLEFT", 0, 2)
        end
        menu.idle = 0
        menu:Show()
    end

    -- Closes a few seconds after the mouse leaves it
    menu:SetScript("OnUpdate", function(self, elapsed)
        if self:IsMouseOver() or miniBtn:IsMouseOver() then
            self.idle = 0
        else
            self.idle = (self.idle or 0) + elapsed
            if self.idle > 2.5 then self:Hide() end
        end
    end)
end

miniBtn:SetScript("OnClick", function(_, button)
    if button == "RightButton" then
        UI.ToggleIconMenu()
    else
        RPChronicler_Toggle()
    end
end)

-- Recording indicator (Options > Recording can turn it off):
-- red label, pulsing red dot and border while a run records; dimmed with
-- an amber dot and border while paused; the normal gold look when idle.
do
    local dot = miniBtn:CreateTexture(nil, "OVERLAY")
    dot:SetSize(8, 8)
    dot:SetPoint("CENTER", miniBtn, "TOPRIGHT", -2, -2)
    dot:SetTexture(UI.ICONS.DOT)
    dot:Hide()

    local state, acc = nil, 0
    local function Apply(newState)
        state = newState
        miniBtn:SetAlpha(1)
        if newState == "rec" then
            dot:SetVertexColor(1, 0.15, 0.15, 1)
            dot:Show()
            miniBtn:SetText("|cffff4040RP|r")
            miniBtn:SetBackdropColor(0.28, 0.06, 0.06, 0.96)
        elseif newState == "paused" then
            dot:SetVertexColor(1, 0.72, 0.30, 1)
            dot:SetAlpha(1)
            dot:Show()
            miniBtn:SetText("|cffffb74dRP|r")
            miniBtn:UnlockHighlight()
            miniBtn:SetBackdropBorderColor(1, 0.72, 0.30, 0.95)
            miniBtn:SetAlpha(0.55)
        else
            dot:Hide()
            miniBtn:SetText("|cffffd100RP|r")
            miniBtn:UnlockHighlight() -- restores the normal gold look
        end
    end

    miniBtn:HookScript("OnUpdate", function(_, elapsed)
        acc = acc + elapsed
        local run = ns.GetActiveAdventure and ns.GetActiveAdventure()
        local want = run and (run.paused and "paused" or "rec") or nil
        if RPChroniclerDB and RPChroniclerDB.iconState == false then want = nil end
        if want ~= state then Apply(want) end
        if state == "rec" then
            local a = 0.55 + 0.45 * math.sin(GetTime() * 4)
            dot:SetAlpha(0.35 + 0.65 * math.abs(a))
            if acc >= 0.1 then
                acc = 0
                if not miniBtn:IsMouseOver() then
                    miniBtn:SetBackdropBorderColor(1, 0.25, 0.25, 0.55 + 0.4 * math.abs(a))
                end
            end
        end
    end)

    miniBtn:HookScript("OnEnter", function(self)
        if not GameTooltip then return end
        GameTooltip:SetOwner(self, "ANCHOR_TOPLEFT")
        GameTooltip:SetText("|cffffd100RP Chronicler|r", 1, 1, 1)
        local run = ns.GetActiveAdventure and ns.GetActiveAdventure()
        if run and run.paused then
            GameTooltip:AddLine("|cffffb74dRecording paused:|r " .. (run.title or "Adventure"), 1, 1, 1)
            GameTooltip:AddLine("/rp resume to continue", 0.7, 0.7, 0.7)
        elseif run then
            GameTooltip:AddLine("|cffff5252Recording:|r " .. (run.title or "Adventure"), 1, 1, 1)
            GameTooltip:AddLine("/rp pause to pause", 0.7, 0.7, 0.7)
        else
            GameTooltip:AddLine("Not recording an adventure", 0.7, 0.7, 0.7)
        end
        GameTooltip:AddLine("Left-click: open   Right-click: recording menu", 0.7, 0.7, 0.7)
        GameTooltip:Show()
    end)
    miniBtn:HookScript("OnLeave", function()
        if GameTooltip then GameTooltip:Hide() end
        state = "hover" -- re-apply the indicator colors after the hover look
    end)

    function UI.RefreshRecordIcon() state = "refresh" end
end

-- =========================================================
-- Slash commands
-- =========================================================
SLASH_RPCHRONICLER1 = "/rp"
SLASH_RPCHRONICLER2 = "/rpchronicler"
SlashCmdList["RPCHRONICLER"] = function(msg)
    local trimmed = (msg or ""):match("^%s*(.-)%s*$")
    local low = trimmed:lower()
    if low == "clear" then
        ns.ClearSessionLogs()
        print("|cff00ff00[RP Chronicler]|r All logs cleared.")
    elseif low == "quick" then
        RPChronicler_QuickCopy()
    elseif low == "capture" then
        RPChronicler_CaptureTarget()
    elseif low == "btn" then
        if miniBtn:IsShown() then miniBtn:Hide() else miniBtn:Show() end
    elseif low == "options" or low == "config" then
        UI.OpenOptionsPage(RPChroniclerDB and RPChroniclerDB.optionsPage or "GENERAL")
    elseif low == "companions" then
        RPChronicler_Open("", "PLAYERS")
    elseif low == "adventures" or low == "runs" then
        RPChronicler_Open("", "ADVENTURES")
    elseif low == "start" then
        RPChronicler_StartRun()
    elseif low == "book" or low == "stories" then
        UI.OpenStoryBook()
    elseif low == "setup" or low == "privacy" then
        if UI.OpenSetup then UI.OpenSetup(true) end
    elseif low == "wipe" then
        UI.ShowPrompt("|cffff6b6bDelete ALL RP Chronicler data?|r\nEvery recording, story, companion and setting is removed, then the UI reloads. This cannot be undone.",
            "Delete everything", function() ns.WipeAllData() end, "Cancel", nil)
    elseif low == "debug" then
        UI.ShowCopyBox("|cffffd100RP Chronicler debug report|r",
            "|cffb0bac5Select All, Ctrl+C, and paste it into your bug report. It holds no chat.|r",
            ns.BuildDebugReport and ns.BuildDebugReport() or "Debug module not loaded.")
    elseif low == "debug clear" then
        if RPChroniclerDB then RPChroniclerDB.debugLog = {} end
        print("|cff00ff00[RP Chronicler]|r Debug log cleared.")
    elseif low == "pause" or low == "resume" then
        local ok, status
        if low == "pause" then
            ok, status = ns.PauseAdventure and ns.PauseAdventure()
        else
            ok, status = ns.ResumeAdventure and ns.ResumeAdventure()
        end
        print("|cff00ff00[RP Chronicler]|r " .. tostring(status or "Adventures module not loaded."))
        if UI.RefreshRunViews then pcall(UI.RefreshRunViews) end
    elseif low == "end" or low == "stop" then
        local saved = ns.GetActiveAdventure() and ns.EndAdventure("Ended Manually")
        print("|cff00ff00[RP Chronicler]|r " .. (saved and ("Saved adventure: " .. (saved.title or "Adventure")) or "No active adventure running."))
        if UI.RefreshRunViews then pcall(UI.RefreshRunViews) end
    elseif low == "diag" then
        if ns.DiagnoseTarget then
            for _, line in ipairs(ns.DiagnoseTarget()) do
                print("|cffffd100[RP Chronicler diag]|r " .. line)
            end
        end
    elseif low:match("^mark") then
        local noteArg = trimmed:match("^mark%s+(.+)$")
        local ok, status = ns.MarkAdventureHighlight(noteArg)
        print("|cff00ff00[RP Chronicler]|r " .. status)
        if ok and ns.RequestScreenshot then
            ns.RequestScreenshot("mark", noteArg or "Marked moment")
        end
    else
        RPChronicler_Open(trimmed)
    end
end
