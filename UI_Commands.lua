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
    return not focused or focused == _G.RPCopySilentArmBox
end

SilentButton("RPCopySilentCaptureBtn", function() RPCopy_CaptureTarget() end)
SilentButton("RPCopySilentMarkBtn", function()
    if NotTyping() and RPCopy_MarkMoment then RPCopy_MarkMoment() end
end)
SilentButton("RPCopySilentOpenBtn", function()
    if NotTyping() then RPCopy_Toggle() end
end)
SilentButton("RPCopySilentRunStartBtn", function()
    if NotTyping() then RPCopy_StartRun() end
end)
SilentButton("RPCopySilentRunPauseBtn", function()
    if NotTyping() then RPCopy_ToggleRunPause() end
end)
SilentButton("RPCopySilentRunEndBtn", function()
    if NotTyping() then RPCopy_EndRun() end
end)

local KEY_TO_BUTTON = {
    { field = "markMomentKey", button = "RPCopySilentMarkBtn" },
    { field = "openWindowKey", button = "RPCopySilentOpenBtn" },
    { field = "runStartKey", button = "RPCopySilentRunStartBtn" },
    { field = "runPauseKey", button = "RPCopySilentRunPauseBtn" },
    { field = "runEndKey", button = "RPCopySilentRunEndBtn" },
}

local bindOwner = CreateFrame("Frame", "RPCopyBindManagerFrame", UIParent)

function UI.UpdateOverrideBindings()
    if InCombatLockdown and InCombatLockdown() then
        UI.bindingsPending = true
        return
    end
    UI.bindingsPending = false
    UI.EnsureOptions()
    if ClearOverrideBindings then ClearOverrideBindings(bindOwner) end
    if not SetOverrideBindingClick then return end
    local db = RPCopyDB
    -- Quick Copy: Ctrl+C (both copy styles) or a custom key. When the hidden
    -- copy box already has focus, the keystroke goes to it and copies.
    if db.quickCtrlC and db.quickCopyKey and db.quickCopyKey ~= "" then
        SetOverrideBindingClick(bindOwner, false, db.quickCopyKey, "RPCopySilentCopyBtn")
    end
    if db.quickCapture and db.captureTargetKey and db.captureTargetKey ~= "" then
        SetOverrideBindingClick(bindOwner, false, db.captureTargetKey, "RPCopySilentCaptureBtn")
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
miniBtn:SetScript("OnClick", function(_, button)
    if button == "RightButton" then
        ns.ClearSessionLogs()
        print("|cff00ff00[RPCopy]|r All logs cleared.")
    else
        RPCopy_Toggle()
    end
end)
UI.miniBtn = miniBtn

-- Recording indicator: pulsing red dot + red border while a run records,
-- steady amber dot + amber border while paused, nothing when idle.
do
    local dot = miniBtn:CreateTexture(nil, "OVERLAY")
    dot:SetSize(8, 8)
    dot:SetPoint("CENTER", miniBtn, "TOPRIGHT", -2, -2)
    dot:SetTexture(UI.ICONS.DOT)
    dot:Hide()

    local state, acc = nil, 0
    local function Apply(newState)
        state = newState
        if newState == "rec" then
            dot:SetVertexColor(1, 0.15, 0.15, 1)
            dot:Show()
        elseif newState == "paused" then
            dot:SetVertexColor(1, 0.72, 0.30, 1)
            dot:SetAlpha(1)
            dot:Show()
            miniBtn:SetBackdropBorderColor(1, 0.72, 0.30, 0.95)
        else
            dot:Hide()
            miniBtn:UnlockHighlight() -- restores the normal gold look
        end
    end

    miniBtn:HookScript("OnUpdate", function(_, elapsed)
        acc = acc + elapsed
        local run = ns.GetActiveAdventure and ns.GetActiveAdventure()
        local want = run and (run.paused and "paused" or "rec") or nil
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
        GameTooltip:SetText("|cffffd100RPCopy|r", 1, 1, 1)
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
        GameTooltip:AddLine("Left-click: open   Right-click: clear logs", 0.7, 0.7, 0.7)
        GameTooltip:Show()
    end)
    miniBtn:HookScript("OnLeave", function()
        if GameTooltip then GameTooltip:Hide() end
        state = nil -- re-apply the indicator colors after the hover look
    end)
end

-- =========================================================
-- Slash commands
-- =========================================================
SLASH_RPCOPY1 = "/rp"
SLASH_RPCOPY2 = "/rpcopy"
SlashCmdList["RPCOPY"] = function(msg)
    local trimmed = (msg or ""):match("^%s*(.-)%s*$")
    local low = trimmed:lower()
    if low == "clear" then
        ns.ClearSessionLogs()
        print("|cff00ff00[RPCopy]|r All logs cleared.")
    elseif low == "quick" then
        RPCopy_QuickCopy()
    elseif low == "capture" then
        RPCopy_CaptureTarget()
    elseif low == "btn" then
        if miniBtn:IsShown() then miniBtn:Hide() else miniBtn:Show() end
    elseif low == "options" or low == "config" then
        UI.OpenOptionsPage(RPCopyDB and RPCopyDB.optionsPage or "GENERAL")
    elseif low == "companions" then
        RPCopy_Open("", "PLAYERS")
    elseif low == "adventures" or low == "runs" then
        RPCopy_Open("", "ADVENTURES")
    elseif low == "start" then
        RPCopy_StartRun()
    elseif low == "pause" or low == "resume" then
        local ok, status
        if low == "pause" then
            ok, status = ns.PauseAdventure and ns.PauseAdventure()
        else
            ok, status = ns.ResumeAdventure and ns.ResumeAdventure()
        end
        print("|cff00ff00[RPCopy]|r " .. tostring(status or "Adventures module not loaded."))
        if UI.frame:IsShown() and ns.state.section == "ADVENTURES" then pcall(UI.RefreshAdventuresTab) end
    elseif low == "end" or low == "stop" then
        local saved = ns.GetActiveAdventure() and ns.EndAdventure("Ended Manually")
        print("|cff00ff00[RPCopy]|r " .. (saved and ("Saved adventure: " .. (saved.title or "Adventure")) or "No active adventure running."))
        if UI.frame:IsShown() and ns.state.section == "ADVENTURES" then pcall(UI.RefreshAdventuresTab) end
    elseif low == "diag" then
        if ns.DiagnoseTarget then
            for _, line in ipairs(ns.DiagnoseTarget()) do
                print("|cffffd100[RPCopy diag]|r " .. line)
            end
        end
    elseif low:match("^mark") then
        local noteArg = trimmed:match("^mark%s+(.+)$")
        local ok, status = ns.MarkAdventureHighlight(noteArg)
        print("|cff00ff00[RPCopy]|r " .. status)
        if ok and ns.RequestScreenshot then
            ns.RequestScreenshot("mark", noteArg or "Marked moment")
        end
    else
        RPCopy_Open(trimmed)
    end
end
