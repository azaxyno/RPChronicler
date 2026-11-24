local ADDON_NAME, ns = ...
local UI = ns.UI

-- =========================================================
-- Inject OOC channel logs into the snapshot when the slice enables it
-- =========================================================
do
    local origBuildSnapshot = ns.BuildSnapshot
    ns.BuildSnapshot = function(filterId, note, isExpanded)
        local baseText = origBuildSnapshot and origBuildSnapshot(filterId, note, isExpanded) or ""
        local tabCfg = ns.GetTabConfig(filterId)
        if not tabCfg or not tabCfg.incOoc or not ns.logs.ooc or #ns.logs.ooc == 0 then
            return baseText
        end
        local limit = isExpanded and (RPCopyDB.expandMessages or 6) or (RPCopyDB.defaultMessages or 3)
        local slice = {}
        for i = math.max(1, #ns.logs.ooc - limit + 1), #ns.logs.ooc do
            table.insert(slice, ns.logs.ooc[i])
        end
        local oocBlock = table.concat(slice, "\n")
        local kpPos = baseText:find("\n%[Known Player:", 1, true) or baseText:find("\n|cffffd100%[Known Player:", 1, true)
        if kpPos then
            return baseText:sub(1, kpPos - 1) .. "\n" .. oocBlock .. baseText:sub(kpPos)
        end
        return baseText .. "\n" .. oocBlock
    end
end

-- =========================================================
-- Quick Copy
-- WoW addons cannot write to the clipboard. The only way to copy is the
-- game's own Ctrl+C inside a focused EditBox with highlighted text.
--
-- INSTANT mode: hold Ctrl for a moment and an invisible EditBox takes focus
-- with the snapshot highlighted, so the C of your Ctrl+C copies on the FIRST
-- press. Quick Ctrl+<key> combos (pressed before the short delay) pass
-- straight through to your keybinds, and once you have pressed another key
-- with Ctrl in a hold, RPCopy stays out of the way until Ctrl is released.
-- In combat it switches to two-press unless "Instant in combat" is on.
--
-- TWO-PRESS mode: Ctrl+C arms the box, a second Ctrl+C copies (3s window).
-- Every other Ctrl combo always works.
-- Both modes bind Ctrl+C itself (an override binding set out of combat), so
-- a Ctrl+C that arrives before the box is armed arms it for a second press.
-- =========================================================
local ARM_DELAY = 0.25

local armEditBox = CreateFrame("EditBox", "RPCopySilentArmBox", UIParent)
armEditBox:SetSize(1, 1)
armEditBox:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", 2, 2)
armEditBox:SetAutoFocus(false)
armEditBox:SetMultiLine(true)
armEditBox:SetAlpha(0.01)
armEditBox:Hide()

local Q = { isArmed = false, mode = nil, label = "Chat", expiresAt = 0, ctrlDownAt = nil, holdUsed = false }
UI.quick = Q

local MODIFIER_KEYS = {
    LSHIFT = true, RSHIFT = true, LCTRL = true, RCTRL = true,
    LALT = true, RALT = true, LMETA = true, RMETA = true,
}

local function InCombat()
    return (InCombatLockdown and InCombatLockdown()) or false
end

function UI.IsCtrlCCopy()
    return RPCopyDB and RPCopyDB.quickCtrlC and RPCopyDB.quickCopyKey == "CTRL-C"
end

function UI.IsInstantCopyActive()
    if not UI.IsCtrlCCopy() or RPCopyDB.copyMode ~= "INSTANT" then return false end
    if InCombat() and not RPCopyDB.instantInCombat then return false end
    return true
end

function UI.DisarmCtrlCopy()
    if Q.isArmed then
        Q.isArmed = false
        Q.mode = nil
        Q.expiresAt = 0
        armEditBox:ClearFocus()
        armEditBox:Hide()
    end
end

function UI.ArmCtrlCopy(mode)
    UI.EnsureOptions()
    -- SetText/SetFocus on our own non-secure EditBox is not a protected
    -- action, so this is safe in combat (no blocked-action popup).
    if UI.frame:IsShown() then return false end
    local focused = GetCurrentKeyBoardFocus and GetCurrentKeyBoardFocus()
    if focused and focused ~= armEditBox then return false end

    local tabCfg = ns.GetTabConfig(RPCopyDB.lastSliceId)
    Q.label = (tabCfg and tabCfg.label) or "Chat"
    local ok, snap = pcall(ns.BuildSnapshot, (tabCfg and tabCfg.id) or "CHAT", "", false)
    if not ok or type(snap) ~= "string" then return false end

    armEditBox:Show()
    armEditBox:SetText(snap)
    armEditBox:SetFocus()
    armEditBox:HighlightText()
    Q.isArmed = true
    Q.mode = mode or "timed"
    Q.expiresAt = (Q.mode == "timed") and (GetTime() + 3.0) or 0
    return true
end

local function FinishCopy()
    UI.ShowToast(string.format("|cffffd100Copied|r |cff69ccf0[%s]|r |cff5cb85cto clipboard!|r", Q.label), 1.8, 0.36, 0.72, 0.36)
    -- Let the EditBox finish its native copy before focus is dropped
    if C_Timer and C_Timer.After then
        C_Timer.After(0.05, UI.DisarmCtrlCopy)
    else
        UI.DisarmCtrlCopy()
    end
end

armEditBox:SetScript("OnUpdate", function()
    if Q.isArmed and Q.mode == "timed" and Q.expiresAt > 0 and GetTime() > Q.expiresAt then
        UI.DisarmCtrlCopy()
    end
end)

armEditBox:SetScript("OnKeyDown", function(_, key)
    if not Q.isArmed then return end
    if key == "C" and IsControlKeyDown() then
        FinishCopy()
    elseif key == "ESCAPE" then
        UI.DisarmCtrlCopy()
    elseif Q.mode == "hold" and not MODIFIER_KEYS[key] then
        -- Ctrl+<another key>: get out of the way for the rest of this hold
        Q.holdUsed = true
        UI.DisarmCtrlCopy()
    end
end)

armEditBox:SetScript("OnEscapePressed", UI.DisarmCtrlCopy)
armEditBox:SetScript("OnEditFocusLost", function()
    Q.isArmed = false
    Q.mode = nil
    Q.expiresAt = 0
    armEditBox:Hide()
end)

-- Ctrl watcher (polls modifier state; no protected calls)
do
    local watcher = CreateFrame("Frame", "RPCopyCtrlWatcher", UIParent)
    watcher:SetScript("OnUpdate", function()
        if IsControlKeyDown() then
            local now = GetTime()
            if not Q.ctrlDownAt then
                Q.ctrlDownAt = now
                Q.holdUsed = false
            end
            if not Q.isArmed and not Q.holdUsed and (now - Q.ctrlDownAt) >= ARM_DELAY and UI.IsInstantCopyActive() then
                UI.ArmCtrlCopy("hold")
            end
        elseif Q.ctrlDownAt then
            Q.ctrlDownAt = nil
            Q.holdUsed = false
            if Q.isArmed and Q.mode == "hold" then
                if C_Timer and C_Timer.After then
                    C_Timer.After(0.05, function()
                        if Q.isArmed and Q.mode == "hold" and not IsControlKeyDown() then
                            UI.DisarmCtrlCopy()
                        end
                    end)
                else
                    UI.DisarmCtrlCopy()
                end
            end
        end
    end)

    -- Key listener: sees every key but passes ALL of them on to the game
    -- (propagation is switched on once, out of combat, and never toggled).
    -- It only notes "another key was pressed with Ctrl" so instant mode
    -- does not arm in the middle of your Ctrl+1, Ctrl+2... presses.
    local listener = CreateFrame("Frame", "RPCopyKeyListener", UIParent)
    listener:SetSize(1, 1)
    listener:SetPoint("BOTTOMLEFT", 0, 0)
    listener:SetScript("OnKeyDown", function(_, key)
        if Q.ctrlDownAt and not MODIFIER_KEYS[key] and key ~= "C" then
            Q.holdUsed = true
        end
    end)

    local function EnableListener()
        if listener.ready or InCombat() then return end
        if not (listener.EnableKeyboard and listener.SetPropagateKeyboardInput) then return end
        local ok = pcall(listener.SetPropagateKeyboardInput, listener, true)
        local propagates = ok
        if ok and listener.GetPropagateKeyboardInput then
            local ok2, val = pcall(listener.GetPropagateKeyboardInput, listener)
            propagates = ok2 and val and true or false
        end
        -- Only listen if every key is guaranteed to pass through
        if propagates then
            listener:EnableKeyboard(true)
            listener.ready = true
        end
    end

    listener:RegisterEvent("PLAYER_LOGIN")
    listener:RegisterEvent("PLAYER_REGEN_ENABLED")
    listener:SetScript("OnEvent", EnableListener)
end

-- Clicked by the Ctrl+C (or custom) override binding
do
    local silentCopyBtn = CreateFrame("Button", "RPCopySilentCopyBtn", UIParent)
    silentCopyBtn:SetSize(1, 1)
    silentCopyBtn:SetPoint("BOTTOMLEFT", 0, 0)
    silentCopyBtn:SetScript("OnClick", function()
        local focused = GetCurrentKeyBoardFocus and GetCurrentKeyBoardFocus()
        if focused and focused ~= armEditBox then return end
        if not Q.isArmed then
            if UI.ArmCtrlCopy("timed") then
                UI.ShowToast(string.format("|cffffd100Ready|r |cff69ccf0[%s]|r - press |cffffd100CTRL-C|r again to copy", Q.label), 2.5, 0.85, 0.68, 0.30)
            end
        else
            FinishCopy()
        end
    end)
end

function RPCopy_QuickCopy()
    UI.EnsureOptions()
    if UI.frame:IsShown() then UI.frame:Hide() end
    if UI.ArmCtrlCopy("timed") then
        UI.ShowToast(string.format("|cffffd100Ready:|r Press |cffffd100CTRL-C|r now for |cff69ccf0[%s]|r", Q.label), 2.5, 0.85, 0.68, 0.30)
    end
end

function RPCopy_CaptureTarget()
    UI.EnsureOptions()
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
        UI.ShowToast("|cffff6b6bRPCopy:|r Target a player (or hover/whisper) first!", 2.0, 0.75, 0.28, 0.28)
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
        UI.ShowToast(prefix .. "|cff69ccf0" .. key .. "|r" .. detail, 2.2, 0.36, 0.72, 0.36)
        if UI.frame:IsShown() and ns.state.section == "PLAYERS" and UI.OpenCompanion then
            UI.OpenCompanion(key)
        end
    end
end

-- =========================================================
-- COPY section: slice tabs, snapshot, expand, note for the AI
-- =========================================================
local view = UI.NewSection("COPY", "Copy for RP", "Pick a slice and press Ctrl+C to copy and close. Esc closes.")
UI.AddRailButton("COPY", "Copy", UI.ICONS.COPY, "The quick RP side: pick a slice, press Ctrl+C, paste into your AI.")

local C = { sliceButtons = {} }
UI.copy = C

C.strip = CreateFrame("Frame", nil, view)
C.strip:SetPoint("TOPLEFT", 0, 0)
C.strip:SetPoint("TOPRIGHT", 0, 0)
C.strip:SetHeight(24)

C.boxBg = CreateFrame("Frame", nil, view, UI.BACKDROP)
C.boxBg:SetPoint("TOPLEFT", C.strip, "BOTTOMLEFT", 0, -6)
C.boxBg:SetPoint("BOTTOMRIGHT", 0, 30)
UI.ApplyPanelLook(C.boxBg)

C.scroll = CreateFrame("ScrollFrame", "RPCopyScrollFrame", C.boxBg, "UIPanelScrollFrameTemplate")
C.scroll:SetPoint("TOPLEFT", 8, -8)
C.scroll:SetPoint("BOTTOMRIGHT", -28, 8)

C.editBox = CreateFrame("EditBox", "RPCopyEditBox", C.scroll)
C.editBox:SetMultiLine(true)
C.editBox:SetFontObject(ChatFontNormal)
C.editBox:SetWidth(500)
C.editBox:SetHeight(300)
C.editBox:SetAutoFocus(true)
C.scroll:SetScrollChild(C.editBox)

C.expandBtn = UI.CreateSleekButton(view, 96, 22, "Expand (6)")
C.expandBtn:SetPoint("BOTTOMLEFT", 0, 2)
C.expandBtn.tipTitle = "|cffffd100Expand|r"
C.expandBtn.tipText = "Show more recent messages in each log. Set the counts in Options."

C.chip = UI.CreateSleekButton(view, 118, 22, "Ctrl+C: Instant", "tool")
C.chip:SetPoint("BOTTOMRIGHT", 0, 2)
C.chip.tipTitle = "|cffffd100Quick Copy|r"
C.chip.tipText = "How Ctrl+C copies from the game world. Click to change it in Options > Keybinds."

C.noteBox = CreateFrame("EditBox", "RPCopyNoteInput", view, "InputBoxTemplate")
C.noteBox:SetHeight(20)
C.noteBox:SetPoint("LEFT", C.expandBtn, "RIGHT", 14, 0)
C.noteBox:SetPoint("RIGHT", C.chip, "LEFT", -10, 0)
C.noteBox:SetAutoFocus(false)
C.noteBox:SetMaxLetters(200)
C.notePlaceholder = C.noteBox:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
C.notePlaceholder:SetPoint("LEFT", 2, 0)
C.notePlaceholder:SetText("Instruction for the AI (Enter to add)")

function UI.UpdateExpandButtonLabel()
    UI.EnsureOptions()
    if ns.state.isExpanded then
        C.expandBtn:SetText("Collapse (" .. (RPCopyDB.defaultMessages or 3) .. ")")
        C.expandBtn:LockHighlight()
    else
        C.expandBtn:SetText("Expand (" .. (RPCopyDB.expandMessages or 6) .. ")")
        C.expandBtn:UnlockHighlight()
    end
end

function UI.SyncCopyChip()
    UI.EnsureOptions()
    if not RPCopyDB.quickCtrlC then
        C.chip:SetText("|cff9aa5b4Quick Copy: OFF|r")
    elseif RPCopyDB.quickCopyKey ~= "CTRL-C" then
        C.chip:SetText("|cffc2d8ff" .. RPCopyDB.quickCopyKey .. "|r")
    elseif RPCopyDB.copyMode == "INSTANT" then
        C.chip:SetText("|cffc2d8ffCtrl+C: Instant|r")
    else
        C.chip:SetText("|cffc2d8ffCtrl+C: Two-press|r")
    end
end

function UI.RefreshBox()
    UI.UpdateExpandButtonLabel()
    UI.SyncCopyChip()
    C.editBox:SetText(ns.BuildSnapshot(ns.state.activeFilter, ns.state.activeNote, ns.state.isExpanded))
    C.editBox:SetFocus()
    C.editBox:HighlightText()
end

function UI.SelectSlice(sliceId)
    local cfg = ns.GetTabConfig(sliceId)
    if not cfg then return end
    ns.state.activeFilter = cfg.id
    RPCopyDB.lastSliceId = cfg.id
    for _, b in ipairs(C.sliceButtons) do
        if b.sliceId == cfg.id then b:LockHighlight() else b:UnlockHighlight() end
    end
    UI.RefreshBox()
end

-- Lays the slice buttons out in rows that fit the section's width
function UI.RebuildSliceTabs()
    UI.EnsureOptions()
    for _, b in ipairs(C.sliceButtons) do b:Hide() end
    local maxW = math.max(200, (view:GetWidth() or 0) > 50 and view:GetWidth() or 560)
    local x, y, rows = 0, 0, 1
    for idx, t in ipairs(RPCopyDB.tabs) do
        local btn = C.sliceButtons[idx]
        if not btn then
            btn = UI.CreateSleekButton(C.strip, 60, 22, "")
            C.sliceButtons[idx] = btn
        end
        local w = math.max(52, #t.label * 7 + 18)
        if x + w > maxW and x > 0 then
            x, y, rows = 0, y - 25, rows + 1
        end
        btn:ClearAllPoints()
        btn:SetWidth(w)
        btn:SetPoint("TOPLEFT", x, y)
        btn:SetText(t.label)
        btn.sliceId = t.id
        btn:SetScript("OnClick", function() UI.SelectSlice(t.id) end)
        if ns.state.activeFilter == t.id then btn:LockHighlight() else btn:UnlockHighlight() end
        btn:Show()
        x = x + w + 4
    end
    C.strip:SetHeight(rows * 25 - 1)
end

C.expandBtn:SetScript("OnClick", function()
    ns.state.isExpanded = not ns.state.isExpanded
    UI.RefreshBox()
end)

C.chip:SetScript("OnClick", function()
    if UI.OpenOptionsPage then UI.OpenOptionsPage("KEYS") end
end)

local function ShowIf(region, cond)
    if cond then region:Show() else region:Hide() end
end

local function ApplyNote()
    local txt = (C.noteBox:GetText() or ""):gsub("||", "|"):match("^%s*(.-)%s*$")
    ns.state.activeNote = txt
    ShowIf(C.notePlaceholder, txt == "" and not C.noteBox:HasFocus())
    UI.RefreshBox()
end

C.noteBox:SetScript("OnEnterPressed", ApplyNote)
C.noteBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
C.noteBox:SetScript("OnEditFocusGained", function() C.notePlaceholder:Hide() end)
C.noteBox:SetScript("OnEditFocusLost", function()
    ShowIf(C.notePlaceholder, (C.noteBox:GetText() or "") == "")
end)

C.editBox:SetScript("OnEscapePressed", function() UI.frame:Hide() end)
C.editBox:SetScript("OnKeyDown", function(_, key)
    if key == "C" and IsControlKeyDown() and ns.state.section == "COPY" then
        local openedAt = UI.frame.openedAt
        if not openedAt or (GetTime() - openedAt) > 0.25 then
            UI.frame.closeDelay = 0.15
        end
    end
end)

UI.SetSectionOnShow("COPY", function()
    UI.EnsureOptions()
    local cfg = ns.GetTabConfig(RPCopyDB.lastSliceId)
    ns.state.activeFilter = cfg and cfg.id or ns.state.activeFilter
    C.noteBox:SetText(ns.state.activeNote or "")
    ShowIf(C.notePlaceholder, (ns.state.activeNote or "") == "")
    UI.RebuildSliceTabs()
    UI.RefreshBox()
end)

view:SetScript("OnHide", function()
    C.editBox:ClearFocus()
    C.noteBox:ClearFocus()
end)

UI.AddReflow(function()
    local w = C.scroll:GetWidth()
    if w and w > 50 then
        C.editBox:SetWidth(w)
        C.editBox:SetHeight(math.max(C.scroll:GetHeight() or 0, 100))
    end
    if view:IsShown() then UI.RebuildSliceTabs() end
end)
