local ADDON_NAME, ns = ...
local UI = ns.UI

-- =========================================================
-- Quick Copy
-- WoW addons cannot write to the clipboard. The only way to copy is the
-- game's own Ctrl+C inside a focused EditBox with highlighted text.
--
-- INSTANT mode: hold Ctrl for a moment and an invisible EditBox takes focus
-- with the snapshot highlighted, so the C of your Ctrl+C copies on the FIRST
-- press. Quick Ctrl+<key> combos (pressed before the short delay) pass
-- straight through to your keybinds, and once you have pressed another key
-- with Ctrl in a hold, RP Chronicler stays out of the way until Ctrl is released.
--
-- BOX mode: Ctrl+C shows the snapshot selected in a small visible box.
-- Ctrl+C is bound itself (an override binding set out of combat), so a
-- Ctrl+C that arrives before the box is armed arms it for a second press.
-- 0.6.1: the two-press style and "instant in combat" were removed, and
-- none of this runs while RP Copy is off (ns.RpCopyOn).
-- =========================================================
-- 0.5.1: 0.1s (was 0.25s). Most people press Ctrl and C almost together,
-- and a slower arm made Instant ask for a second press.
local ARM_DELAY = 0.1
-- 0.5.0: a longer grace before focus is dropped, so the client has finished
-- its native copy of the highlighted text (0.05s was too short on some PCs).
local DISARM_DELAY = 0.25

local armEditBox = CreateFrame("EditBox", "RPChroniclerSilentArmBox", UIParent)
-- 0.5.1: a real size. A 1x1 multi-line box lays out no text on the modern
-- client, so nothing is selected and Ctrl+C copies nothing. The box is
-- still invisible (alpha), sits behind everything and takes no mouse.
armEditBox:SetSize(400, 200)
armEditBox:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", 2, 2)
armEditBox:SetFrameStrata("BACKGROUND")
armEditBox:SetAutoFocus(false)
armEditBox:SetMultiLine(true)
if armEditBox.EnableMouse then armEditBox:EnableMouse(false) end
armEditBox:SetAlpha(0.01)
-- 0.5.0 (Ctrl+C fix): an EditBox with no font cannot hold or copy text on the
-- modern client, and the default letter cap can cut a long snapshot.
if armEditBox.SetFontObject and ChatFontNormal then pcall(armEditBox.SetFontObject, armEditBox, ChatFontNormal) end
if armEditBox.SetMaxLetters then pcall(armEditBox.SetMaxLetters, armEditBox, 0) end
if armEditBox.SetMaxBytes then pcall(armEditBox.SetMaxBytes, armEditBox, 0) end
-- 0.6.3 (gray bars while holding Ctrl): alpha alone did not hide the
-- selection highlight on the modern client, so the highlighted lines
-- showed as gray bars over the chat. Text and highlight are fully
-- transparent now; the text is still there, selected, for the copy.
if armEditBox.SetHighlightColor then pcall(armEditBox.SetHighlightColor, armEditBox, 0, 0, 0, 0) end
if armEditBox.SetTextColor then pcall(armEditBox.SetTextColor, armEditBox, 1, 1, 1, 0) end
if armEditBox.SetShadowColor then pcall(armEditBox.SetShadowColor, armEditBox, 0, 0, 0, 0) end
if armEditBox.SetTextInsets then pcall(armEditBox.SetTextInsets, armEditBox, 0, 0, 0, 0) end
armEditBox:Hide()

local Q = { isArmed = false, mode = nil, label = "Chat", expiresAt = 0, ctrlDownAt = nil, holdUsed = false, textLen = 0 }
UI.quick = Q

local MODIFIER_KEYS = {
    LSHIFT = true, RSHIFT = true, LCTRL = true, RCTRL = true,
    LALT = true, RALT = true, LMETA = true, RMETA = true,
}

local function InCombat()
    return (InCombatLockdown and InCombatLockdown()) or false
end

local function CopyLog(kind, msg)
    ns.Debug(kind, msg)
end

local function FocusName()
    local f = GetCurrentKeyBoardFocus and GetCurrentKeyBoardFocus()
    if not f then return "none" end
    local ok, n = pcall(f.GetName, f)
    return (ok and n) or "unnamed"
end

function UI.IsCtrlCCopy()
    return RPChroniclerDB ~= nil and ns.RpCopyOn() and ns.Get("quickCtrlC")
end

function UI.IsInstantCopyActive()
    -- 0.6.3: with the instruction popup on, Ctrl+C asks first, so the
    -- hidden box never arms on a Ctrl hold
    return UI.IsCtrlCCopy() and ns.Get("copyMode") == "INSTANT" and not ns.Get("quickNote")
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

-- Builds the quick-copy text. Errors go to the debug log (they were silent
-- before 0.5.0), and secret values never reach the EditBox.
function UI.BuildQuickCopyText(sliceId)
    local ok, snap = pcall(ns.BuildSnapshot, sliceId or "CHAT", "", false)
    if not ok then
        CopyLog("error", "Quick copy: snapshot failed: " .. tostring(snap))
        UI.ShowToast("|cffff6b6bRP Chronicler:|r the snapshot failed to build. See /rp debug.", 3.0, 0.75, 0.28, 0.28)
        return nil
    end
    if type(snap) ~= "string" or (ns.IsSecret(snap)) then
        CopyLog("error", "Quick copy: snapshot was not plain text")
        return nil
    end
    if snap == "" then snap = "[RP Chronicler] (nothing to copy yet)" end
    return snap
end

-- 0.5.1 "Copy box" style (and the fallback when the hidden box cannot arm):
-- the snapshot, selected, in a small visible box. Ctrl+C there copies it
-- and the box closes itself.
function UI.ShowQuickCopyBox(reason)
    UI.EnsureOptions()
    if UI.frame:IsShown() then UI.frame:Hide() end
    local tabCfg = ns.GetTabConfig(RPChroniclerDB.lastSliceId)
    Q.label = (tabCfg and tabCfg.label) or "Chat"
    local snap = UI.BuildQuickCopyText(tabCfg and tabCfg.id)
    if not snap then return false end
    UI.DisarmCtrlCopy()
    CopyLog("copy", "copy box shown (" .. (reason or "style") .. "): len " .. #snap)
    UI.ShowCopyBox("|cffffd100RP Chronicler|r |cff69ccf0[" .. Q.label .. "]|r",
        "|cff9aa5b4Selected. Press|r |cffffd100Ctrl+C|r |cff9aa5b4to copy, it closes by itself.|r", snap, true)
    return true
end

-- 0.6.3: the instruction popup (Options > General, off by default).
-- Ctrl+C asks for a one-line instruction for the AI; Enter (or Esc)
-- shows the snapshot selected, with the instruction as its [Instruction]
-- line, and Ctrl+C there copies it, like the Copy box style.
function UI.ShowQuickNotePopup()
    UI.EnsureOptions()
    if UI.frame:IsShown() then UI.frame:Hide() end
    UI.DisarmCtrlCopy()
    local tabCfg = ns.GetTabConfig(RPChroniclerDB.lastSliceId)
    Q.label = (tabCfg and tabCfg.label) or "Chat"
    local function CopyWith(note)
        local ok, snap = pcall(ns.BuildSnapshot, tabCfg and tabCfg.id or "CHAT", note or "", false)
        if not ok or type(snap) ~= "string" or ns.IsSecret(snap) then
            CopyLog("error", "Quick copy (instruction): snapshot failed: " .. tostring(snap))
            UI.ShowToast("|cffff6b6bRP Chronicler:|r the snapshot failed to build. See /rp debug.", 3.0, 0.75, 0.28, 0.28)
            return
        end
        CopyLog("copy", "instruction popup: len " .. #snap .. ((note or "") ~= "" and ", with instruction" or ""))
        UI.ShowCopyBox("|cffffd100RP Chronicler|r |cff69ccf0[" .. Q.label .. "]|r",
            "|cff9aa5b4Selected. Press|r |cffffd100Ctrl+C|r |cff9aa5b4to copy, it closes by itself.|r", snap, true)
    end
    UI.AskLine({
        title = "Instruction for the AI  |cff69ccf0[" .. Q.label .. "]|r",
        sub = "A quick direction for this reply, like \"be flirty\" or \"reply to Thrall\". Leave it empty for none.",
        placeholder = "Type an instruction, or just press Enter",
        okText = "Copy",
        keys = "Enter: copy   Esc: copy without it",
        onAccept = function(text) CopyWith(text) end,
        onEscape = function() CopyWith("") end,
    })
    return true
end

function UI.ArmCtrlCopy(mode)
    UI.EnsureOptions()
    -- SetText/SetFocus on our own non-secure EditBox is not a protected
    -- action, so this is safe in combat (no blocked-action popup).
    if UI.frame:IsShown() then return false end
    local focused = GetCurrentKeyBoardFocus and GetCurrentKeyBoardFocus()
    if focused and focused ~= armEditBox then return false end

    local tabCfg = ns.GetTabConfig(RPChroniclerDB.lastSliceId)
    Q.label = (tabCfg and tabCfg.label) or "Chat"
    local snap = UI.BuildQuickCopyText(tabCfg and tabCfg.id)
    if not snap then return false end

    armEditBox:Show()
    armEditBox:SetText(snap)
    armEditBox:SetFocus()
    armEditBox:SetCursorPosition(0)
    armEditBox:HighlightText()
    Q.isArmed = true
    Q.mode = mode or "timed"
    Q.expiresAt = (Q.mode == "timed") and (GetTime() + 3.0) or 0
    local got = armEditBox:GetText() or ""
    Q.textLen = #got
    local hasFocus = armEditBox:HasFocus() and true or false
    CopyLog("verbose", string.format("copy armed %s: len %d (built %d), focus %s", Q.mode, Q.textLen, #snap, tostring(hasFocus)))
    if not hasFocus or Q.textLen == 0 then
        CopyLog("copy", string.format("arm problem: len %d of %d, focus %s, focused frame %s", Q.textLen, #snap, tostring(hasFocus), FocusName()))
    end
    return hasFocus and Q.textLen > 0
end

local function DisarmLater()
    if C_Timer and C_Timer.After then
        C_Timer.After(DISARM_DELAY, UI.DisarmCtrlCopy)
    else
        UI.DisarmCtrlCopy()
    end
end

local function FinishCopy(via)
    -- Highlight once more right before the native copy reads it
    armEditBox:HighlightText()
    CopyLog("copy", string.format("copy via %s: len %d, focus %s, focused frame %s", via or "?", #(armEditBox:GetText() or ""), tostring(armEditBox:HasFocus() and true or false), FocusName()))
    UI.ShowToast(string.format("|cffffd100Copied|r |cff69ccf0[%s]|r |cff5cb85cto clipboard!|r", Q.label), 1.8, 0.36, 0.72, 0.36)
    Q.copying = true
    -- Let the EditBox finish its native copy before focus is dropped
    DisarmLater()
end

armEditBox:SetScript("OnUpdate", function(self)
    if not Q.isArmed then return end
    if Q.mode == "timed" and Q.expiresAt > 0 and GetTime() > Q.expiresAt then
        UI.DisarmCtrlCopy()
        return
    end
    -- Keep the whole text highlighted while armed (a click or a cursor move
    -- would otherwise leave nothing selected for the native copy)
    if not Q.copying then self:HighlightText() end
end)

armEditBox:SetScript("OnKeyDown", function(_, key)
    if not Q.isArmed then return end
    if key == "C" and IsControlKeyDown() then
        FinishCopy("box")
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
    if Q.isArmed and not Q.copying then
        CopyLog("copy", "armed box lost focus to " .. FocusName())
    end
    Q.isArmed = false
    Q.copying = false
    Q.mode = nil
    Q.expiresAt = 0
    armEditBox:Hide()
end)

-- Ctrl watcher (polls modifier state; no protected calls)
do
    local watcher = CreateFrame("Frame", "RPChroniclerCtrlWatcher", UIParent)
    watcher:SetScript("OnUpdate", function()
        if not UI.IsCtrlCCopy() then return end
        if IsControlKeyDown() then
            local now = GetTime()
            if not Q.ctrlDownAt then
                Q.ctrlDownAt = now
                Q.holdUsed = false
            end
            if not Q.isArmed and not Q.holdUsed and (now - Q.ctrlDownAt) >= ARM_DELAY and UI.IsInstantCopyActive() then
                if not UI.ArmCtrlCopy("hold") then
                    -- Do not rebuild the snapshot every frame of this hold
                    Q.holdUsed = true
                end
            end
        elseif Q.ctrlDownAt then
            Q.ctrlDownAt = nil
            Q.holdUsed = false
            if Q.isArmed and Q.mode == "hold" and not Q.copying then
                if C_Timer and C_Timer.After then
                    C_Timer.After(DISARM_DELAY, function()
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
    local listener = CreateFrame("Frame", "RPChroniclerKeyListener", UIParent)
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
    local silentCopyBtn = CreateFrame("Button", "RPChroniclerSilentCopyBtn", UIParent)
    silentCopyBtn:SetSize(1, 1)
    silentCopyBtn:SetPoint("BOTTOMLEFT", 0, 0)
    silentCopyBtn:SetScript("OnClick", function()
        local focused = GetCurrentKeyBoardFocus and GetCurrentKeyBoardFocus()
        if focused and focused ~= armEditBox then return end
        -- 0.5.0: this button only fires when the key did NOT reach a focused
        -- box. If we think we are armed but the box has no focus, the native
        -- copy cannot have happened, so never claim "Copied": re-arm instead.
        if Q.isArmed and not armEditBox:HasFocus() then
            CopyLog("copy", "binding fired while armed but unfocused (focused frame " .. FocusName() .. "); re-arming")
            Q.isArmed = false
        end
        if ns.Get("quickNote") then
            UI.ShowQuickNotePopup()
        elseif ns.Get("copyMode") == "BOX" then
            UI.ShowQuickCopyBox("style")
        elseif not Q.isArmed then
            if UI.ArmCtrlCopy("timed") then
                if UI.IsInstantCopyActive() then
                    -- Instant mode, but C came before the hold armed the box
                    CopyLog("copy", "instant: Ctrl+C came before the hold armed; asking for a second press")
                    UI.ShowToast(string.format("|cffffd100Ready|r |cff69ccf0[%s]|r - Ctrl+C again. |cff9aa5b4Tip: hold Ctrl a blink before C for one press.|r", Q.label), 3.0, 0.85, 0.68, 0.30)
                else
                    UI.ShowToast(string.format("|cffffd100Ready|r |cff69ccf0[%s]|r - press |cffffd100CTRL-C|r again to copy", Q.label), 2.5, 0.85, 0.68, 0.30)
                end
            elseif not (GetCurrentKeyBoardFocus and GetCurrentKeyBoardFocus() and GetCurrentKeyBoardFocus() ~= armEditBox) then
                -- The hidden box could not take the text: use the visible one
                UI.ShowQuickCopyBox("fallback")
            end
        else
            FinishCopy("binding")
        end
    end)
end

function RPChronicler_QuickCopy()
    UI.EnsureOptions()
    if not ns.RpCopyOn() then
        print("|cffffd100RP Chronicler|r RP Copy is off. Turn it on in Options > General.")
        return
    end
    if UI.frame:IsShown() then UI.frame:Hide() end
    if ns.Get("quickNote") then
        UI.ShowQuickNotePopup()
    elseif ns.Get("copyMode") == "BOX" then
        UI.ShowQuickCopyBox("style")
    elseif UI.ArmCtrlCopy("timed") then
        UI.ShowToast(string.format("|cffffd100Ready:|r Press |cffffd100CTRL-C|r now for |cff69ccf0[%s]|r", Q.label), 2.5, 0.85, 0.68, 0.30)
    else
        UI.ShowQuickCopyBox("fallback")
    end
end

function RPChronicler_CaptureTarget()
    UI.EnsureOptions()
    local focused = GetCurrentKeyBoardFocus and GetCurrentKeyBoardFocus()
    if focused then return end

    -- 0.5.0: players, NPCs and companion pets can all be companions
    local targetName, unit = nil, nil
    if UnitExists("target") and not (UnitIsUnit and UnitIsUnit("target", "player")) then
        targetName, unit = ns.UnitCompanionName("target"), "target"
    elseif UnitExists("mouseover") and UnitIsPlayer("mouseover") then
        targetName, unit = ns.GetUnitFullName("mouseover"), "mouseover"
    elseif ns.state.lastDirectAuthor then
        targetName = ns.state.lastDirectAuthor
    end

    if not targetName or targetName == "" then
        UI.ShowToast("|cffff6b6bRP Chronicler:|r Target someone (or hover/whisper) first!", 2.0, 0.75, 0.28, 0.28)
        return
    end

    local key, isNew = ns.SaveOrUpdatePlayer(targetName, unit)
    if key then
        local entry = RPChroniclerDB.players[key]
        local detail = ""
        if entry and entry.level ~= "" and entry.class ~= "" then
            detail = string.format(" |cff8f9ba8(Lvl %s %s)|r", entry.level, entry.class)
        end
        local prefix = isNew and "|cff5cb85cAdded Companion:|r " or "|cffffd100Updated Companion:|r "
        UI.ShowToast(prefix .. "|cff69ccf0" .. key .. "|r" .. detail, 2.2, 0.36, 0.72, 0.36)
        if UI.frame:IsShown() and ns.state.section == "PLAYERS" then UI.OpenCompanion(key) end
    end
end

-- =========================================================
-- COPY section: slice tabs, snapshot, expand, note for the AI
-- =========================================================
local view = UI.NewSection("COPY", "Copy for RP", "Pick a slice and press Ctrl+C to copy and close. Esc closes.")
UI.AddRailButton("COPY", "Copy", UI.ICONS.COPY, "The quick RP side: pick a slice, press Ctrl+C, paste into your AI.")

-- 0.6.1: RP Copy can be switched off as a whole (Options > General, or the
-- first-run setup). Then the Copy button leaves the rail and the window
-- opens on Adventures.
function UI.SyncRpCopy()
    UI.railButtons.COPY.hiddenByFeature = not ns.RpCopyOn()
    UI.LayoutRail()
    if not ns.RpCopyOn() and ns.state.section == "COPY" and UI.frame:IsShown() then UI.ShowSection("ADVENTURES") end
end
ns.On("PLAYER_LOGIN", function() UI.SyncRpCopy() end)
ns.Listen("setting", function(key) if key == "rpCopy" then UI.SyncRpCopy() end end)

local C = { sliceButtons = {} }
UI.copy = C

C.strip = CreateFrame("Frame", nil, view)
C.strip:SetPoint("TOPLEFT", 0, 0)
C.strip:SetPoint("TOPRIGHT", 0, 0)
C.strip:SetHeight(24)

C.boxBg = CreateFrame("Frame", nil, view, UI.BACKDROP)
C.boxBg:SetPoint("TOPLEFT", C.strip, "BOTTOMLEFT", 0, -6)
C.boxBg:SetPoint("BOTTOMRIGHT", 0, 52)

-- 0.5.0: "Nearby companions": targeted, in your group, on screen or
-- chatting lately. Click to open the first one's notes.
C.nearby = CreateFrame("Button", nil, view)
C.nearby:SetHeight(18)
C.nearby:SetPoint("BOTTOMLEFT", 0, 30)
C.nearby:SetPoint("BOTTOMRIGHT", 0, 30)
C.nearbyText = C.nearby:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
C.nearbyText:SetAllPoints(C.nearby)
C.nearbyText:SetJustifyH("LEFT")
C.nearbyText:SetWordWrap(false)
C.nearby:SetScript("OnEnter", function(self)
    local lines = {}
    for _, n in ipairs(self.list or {}) do table.insert(lines, n.key .. " |cff8f9ba8(" .. n.why .. ")|r") end
    if #lines > 0 then
        UI.Tooltip(self, "|cffffd100Nearby companions|r", table.concat(lines, "\n"), "Click to open the first one in Companions.")
    else
        UI.Tooltip(self, "|cffffd100Nearby companions|r", "Nobody right now.",
            "Companions you target, group with, see on screen or chat with show up here.")
    end
end)
C.nearby:SetScript("OnLeave", UI.HideTooltip)
C.nearby:SetScript("OnClick", function(self)
    local first = self.list and self.list[1]
    if first then
        UI.ShowSection("PLAYERS")
        UI.OpenCompanion(first.key)
    end
end)

function UI.RefreshNearbyChip()
    local list = ns.NearbyCompanions()
    C.nearby.list = list
    if #list == 0 then
        C.nearbyText:SetText("|cff8f9ba8Nearby companions: none|r")
        return
    end
    local names = {}
    for i, n in ipairs(list) do
        if i > 4 then break end
        local e = RPChroniclerDB.players[n.key]
        local cf = e and (e.classFile or ns.ClassToken(e.class))
        table.insert(names, cf and ns.ColorizeClass(n.key, cf) or ("|cff80d8ff" .. n.key .. "|r"))
    end
    local more = (#list > 4) and (" |cff8f9ba8+" .. (#list - 4) .. "|r") or ""
    C.nearbyText:SetText("|cffffd100Nearby companions:|r " .. table.concat(names, ", ") .. more)
end
UI.ApplyPanelLook(C.boxBg)

C.scroll = CreateFrame("ScrollFrame", "RPChroniclerScrollFrame", C.boxBg, "UIPanelScrollFrameTemplate")
C.scroll:SetPoint("TOPLEFT", 8, -8)
C.scroll:SetPoint("BOTTOMRIGHT", -28, 8)

C.editBox = CreateFrame("EditBox", "RPChroniclerEditBox", C.scroll)
C.editBox:SetMultiLine(true)
C.editBox:SetFontObject(ChatFontNormal)
C.editBox:SetWidth(500)
C.editBox:SetHeight(300)
C.editBox:SetAutoFocus(true)
C.scroll:SetScrollChild(C.editBox)

C.expandBtn = UI.CreateSleekButton(view, 96, 22, "Expand (6)")
C.expandBtn:SetPoint("BOTTOMLEFT", 0, 2)
C.expandBtn.tipTitle = "|cffffd100Expand|r"
C.expandBtn.tipText = "Show twice as many recent messages from each chat source. Set the count in Options > General."

C.chip = UI.CreateSleekButton(view, 118, 22, "Ctrl+C: Instant", "tool")
C.chip:SetPoint("BOTTOMRIGHT", 0, 2)
C.chip.tipTitle = "|cffffd100Quick Copy|r"
C.chip.tipText = "How Ctrl+C copies from the game world. Click to change it in Options > General."

C.noteBox = CreateFrame("EditBox", "RPChroniclerNoteInput", view, "InputBoxTemplate")
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
        UI.SetButtonLabels(C.expandBtn, "Collapse (" .. ns.Get("messages") .. ")", "Less")
        C.expandBtn:LockHighlight()
    else
        UI.SetButtonLabels(C.expandBtn, "Expand (" .. (ns.Get("messages") * 2) .. ")", "More")
        C.expandBtn:UnlockHighlight()
    end
end

function UI.SyncCopyChip()
    UI.EnsureOptions()
    if not ns.Get("quickCtrlC") then
        UI.SetButtonLabels(C.chip, "|cff9aa5b4Quick Copy: OFF|r", "|cff9aa5b4Off|r")
    elseif ns.Get("quickNote") then
        UI.SetButtonLabels(C.chip, "|cffc2d8ffCtrl+C: Ask first|r", "|cffc2d8ffAsk|r")
    elseif ns.Get("copyMode") == "INSTANT" then
        UI.SetButtonLabels(C.chip, "|cffc2d8ffCtrl+C: Instant|r", "|cffc2d8ffInstant|r")
    else
        UI.SetButtonLabels(C.chip, "|cffc2d8ffCtrl+C: Copy box|r", "|cffc2d8ffBox|r")
    end
end

-- 0.6.3: the bottom row (Expand, the instruction box, the Ctrl+C chip)
-- sizes its buttons to their text and uses short labels when the
-- instruction box would get too narrow
function UI.LayoutCopyBottom()
    local W = view:GetWidth() or 0
    if W < 50 then return end
    for _, short in ipairs({ false, true }) do
        for _, b in ipairs({ C.expandBtn, C.chip }) do
            b.useShort = short
            if b.fullText then b:SetText(short and b.shortText or b.fullText) end
            b:SetWidth(UI.ButtonWidth(b))
        end
        if W - C.expandBtn:GetWidth() - C.chip:GetWidth() - 24 >= 140 then break end
    end
end

function UI.RefreshBox()
    UI.UpdateExpandButtonLabel()
    UI.SyncCopyChip()
    UI.LayoutCopyBottom()
    pcall(UI.RefreshNearbyChip)
    local ok, snap = pcall(ns.BuildSnapshot, ns.state.activeFilter, ns.state.activeNote, ns.state.isExpanded)
    if not ok then
        ns.Debug("error", "Copy view: snapshot failed: " .. tostring(snap))
        snap = "[RP Chronicler] The snapshot failed to build. Type /rp debug and send the report."
    end
    C.editBox:SetText(type(snap) == "string" and snap or "")
    C.editBox:SetFocus()
    C.editBox:HighlightText()
end

function UI.SelectSlice(sliceId)
    local cfg = ns.GetTabConfig(sliceId)
    if not cfg then return end
    ns.state.activeFilter = cfg.id
    RPChroniclerDB.lastSliceId = cfg.id
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
    for idx, t in ipairs(RPChroniclerDB.tabs) do
        local btn = C.sliceButtons[idx]
        if not btn then
            btn = UI.CreateSleekButton(C.strip, 60, 22, "")
            C.sliceButtons[idx] = btn
        end
        btn:SetText(t.label)
        -- 0.6.3: sized to the label as the game draws it (font and scale)
        local w = math.min(maxW, math.max(52, UI.ButtonWidth(btn)))
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
    UI.OpenOptionsPage("GENERAL")
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
    local cfg = ns.GetTabConfig(RPChroniclerDB.lastSliceId)
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
    if view:IsShown() then UI.RebuildSliceTabs(); UI.LayoutCopyBottom() end
end)
