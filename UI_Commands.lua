local ADDON_NAME, ns = ...
local UI = ns.UI

-- =========================================================
-- Keybinds (0.6.1): RP Chronicler sets one override binding itself, Ctrl+C
-- for the quick copy, and only while RP Copy and "Ctrl+C copies the scene"
-- are on. It is set only out of combat (never a protected call in combat).
-- Every other action has an entry in the game's own Key Bindings
-- (Bindings.xml), unbound until you pick a key there.
-- =========================================================
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
    -- When the hidden copy box already has focus, the keystroke goes to it and copies
    if UI.IsCtrlCCopy() then
        SetOverrideBindingClick(bindOwner, false, "CTRL-C", "RPChroniclerSilentCopyBtn")
    end
end

ns.On({ "PLAYER_LOGIN", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED" }, function(event)
    if event == "PLAYER_REGEN_DISABLED" then
        UI.DisarmCtrlCopy()
    else
        UI.UpdateOverrideBindings()
    end
end)
ns.Listen("setting", function(key)
    if key == "rpCopy" or key == "quickCtrlC" then UI.UpdateOverrideBindings() end
end)

-- =========================================================
-- Floating RP button (draggable; stays where you put it). 0.6.6 (Mor):
-- it shows the RP Chronicler logo, like the minimap button.
-- =========================================================
local miniBtn = UI.CreateSleekButton(UIParent, 34, 34, "", "gold")
miniBtn:SetPoint("CENTER", UIParent, "CENTER", -300, -180)
miniBtn:SetMovable(true)
miniBtn:EnableMouse(true)
miniBtn:RegisterForDrag("LeftButton")
miniBtn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
miniBtn:SetScript("OnDragStart", miniBtn.StartMoving)
-- 0.6.4: where you drop it is kept in the saved file
miniBtn:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local point, _, relPoint, x, y = self:GetPoint(1)
    if point and RPChroniclerDB then
        RPChroniclerDB.buttonPos = { point, relPoint or point, math.floor((x or 0) + 0.5), math.floor((y or 0) + 0.5) }
    end
end)
miniBtn:SetClampedToScreen(true)
UI.miniBtn = miniBtn
local function PlaceFloating()
    local p = RPChroniclerDB and RPChroniclerDB.buttonPos
    if type(p) == "table" and p[1] then
        miniBtn:ClearAllPoints()
        miniBtn:SetPoint(p[1], UIParent, p[2] or p[1], tonumber(p[3]) or 0, tonumber(p[4]) or 0)
    end
end

-- 0.6.5 (Mor): feature ideas and bug reports. An addon can't go online,
-- so this shows the link to copy. 0.6.6 (Mor): a small popup first, with
-- the issues link and the bug report as two separate choices; nothing is
-- selected until the player picks one.
ns.FEEDBACK_URL = "https://github.com/azaxyno/RPChronicler/issues/new/choose"
function UI.OpenFeedback()
    UI.ShowPrompt("|cffffd100Feedback and bug reports|r\n\n" ..
        "|cffb0bac5Ideas and bugs go to RP Chronicler's GitHub issues, or write a comment on its CurseForge page. " ..
        "For a bug, add the bug report (it holds no chat).|r",
        "Feedback", function()
            UI.AskLineCopy("|cffffd100Feedback link|r", ns.FEEDBACK_URL)
        end,
        "Copy bug report", function()
            UI.ShowCopyBox("|cffffd100Bug report|r",
                "|cffb0bac5Selected. Press Ctrl+C and paste it into your issue on GitHub.|r",
                ns.BuildDebugReport())
        end,
        "Close", nil)
end

-- Right-click menu (0.4.0): Start/Stop, Pause/Resume, Mark Moment, Story
-- Book, Clear logs. A plain frame, so it works in combat too.
do
    local menu = CreateFrame("Frame", "RPChroniclerIconMenu", UIParent, UI.BACKDROP)
    menu:SetSize(178, 10)
    menu:SetFrameStrata("FULLSCREEN_DIALOG")
    menu:Hide()
    -- 0.7.0 (Mor): the book look, a leather card with brass corners and
    -- a gold title (Story Book and Clear chat logs left the menu)
    UI.ApplyStoryTomeLook(menu)
    do
        local bg = menu:CreateTexture(nil, "BACKGROUND", nil, 1)
        bg:SetPoint("TOPLEFT", 1, -1)
        bg:SetPoint("BOTTOMRIGHT", -1, 1)
        bg:SetTexture(UI.ART .. "cover.png")
        bg:SetVertexColor(0.36, 0.16, 0.11)
        for _, c in ipairs({ { "TOPLEFT", 0, 1, 0, 1 }, { "TOPRIGHT", 1, 0, 0, 1 }, { "BOTTOMLEFT", 0, 1, 1, 0 }, { "BOTTOMRIGHT", 1, 0, 1, 0 } }) do
            local t = menu:CreateTexture(nil, "OVERLAY", nil, 7)
            t:SetTexture(UI.ART .. "corner.png")
            t:SetSize(16, 16)
            t:SetPoint(c[1], 0, 0)
            t:SetTexCoord(c[2], c[3], c[4], c[5])
        end
        local title = menu:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        title:SetPoint("TOP", 0, -8)
        pcall(title.SetFont, title, UI.GOLD_FONT, 13, "")
        title:SetText("|cffffd100RP Chronicler|r")
    end
    UI.iconMenu = menu

    local items = {
        { key = "run", fn = function() RPChronicler_ToggleRun() end },
        { key = "pause", fn = function() RPChronicler_ToggleRunPause() end },
        { key = "mark", label = "Mark Moment", fn = function() RPChronicler_MarkMoment() end },
        -- 0.5.0: straight to the live run's Full Log
        { key = "open", label = "Open current recording", fn = function()
            local run = ns.GetActiveAdventure()
            if run then UI.OpenRecording(run.id, "FULL") end
        end },
        -- 0.6.5: ideas and bug reports
        { key = "feedback", label = "Feedback / bug report", fn = function() UI.OpenFeedback() end },
        -- 0.6.4: minimap or floating, also from here (Options > General too)
        { key = "mode", fn = function()
            local float = ns.Get("iconMode") ~= "FLOAT"
            ns.Set("iconMode", float and "FLOAT" or "MINIMAP")
            if float then
                print("|cffffd100RP Chronicler|r |cff9aa5b4The RP button floats now: drag it anywhere, it stays there. (A minimap button collector may keep its copy until you restart the game.)|r")
            end
        end },
    }
    for i, it in ipairs(items) do
        local b = UI.CreateSleekButton(menu, 158, 20, it.label or "", it.key == "run" and "good" or nil)
        b:SetPoint("TOP", 0, -26 - (i - 1) * 22)
        b:SetScript("OnClick", function()
            menu:Hide()
            pcall(it.fn)
        end)
        it.btn = b
    end
    menu:SetHeight(32 + #items * 22)

    local function Refresh()
        local run = ns.GetActiveAdventure()
        local runBtn, pauseBtn, markBtn, openBtn = items[1].btn, items[2].btn, items[3].btn, items[4].btn
        if run then openBtn:Enable() else openBtn:Disable() end
        runBtn.accentStyle = run and "danger" or "good"
        runBtn.ApplyNormalLook()
        runBtn:SetText(run and "End adventure" or "Chronicle a new adventure")
        if run then pauseBtn:Enable() else pauseBtn:Disable() end
        pauseBtn:SetText((run and run.paused) and "Resume" or "Pause")
        if run and not run.paused then markBtn:Enable() else markBtn:Disable() end
        items[#items].btn:SetText(ns.Get("iconMode") == "FLOAT" and "Put button on minimap" or "Float the RP button")
    end

    -- anchor: the button that opened it (floating or minimap)
    function UI.ToggleIconMenu(anchor)
        if menu:IsShown() then menu:Hide() return end
        anchor = anchor or miniBtn
        menu.anchor = anchor
        Refresh()
        menu:ClearAllPoints()
        local y = anchor:GetBottom() or 0
        local x = anchor:GetLeft() or 0
        local right = x > ((GetScreenWidth and GetScreenWidth() or 1920) - 200)
        if y > 160 then
            menu:SetPoint(right and "TOPRIGHT" or "TOPLEFT", anchor, right and "BOTTOMRIGHT" or "BOTTOMLEFT", 0, -2)
        else
            menu:SetPoint(right and "BOTTOMRIGHT" or "BOTTOMLEFT", anchor, right and "TOPRIGHT" or "TOPLEFT", 0, 2)
        end
        menu.idle = 0
        menu:Show()
    end

    -- Closes a few seconds after the mouse leaves it
    menu:SetScript("OnUpdate", function(self, elapsed)
        if self:IsMouseOver() or (self.anchor and self.anchor:IsMouseOver()) then
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

-- Recording look (0.6.6, Mor): a red glow pulses around the logo while a
-- run records; paused dims the logo and shows a pause badge; idle is the
-- plain logo on the gold button.
do
    local logo = miniBtn:CreateTexture(nil, "ARTWORK")
    logo:SetPoint("TOPLEFT", 3, -3)
    logo:SetPoint("BOTTOMRIGHT", -3, 3)
    logo:SetTexture("Interface\\AddOns\\RPChronicler\\Media\\logo")

    -- the glow sits on its own frame behind the button, so the button's
    -- background can't cover it
    local glowF = CreateFrame("Frame", nil, UIParent)
    glowF:SetSize(72, 72)
    glowF:SetPoint("CENTER", miniBtn, "CENTER")
    glowF:SetFrameStrata(miniBtn:GetFrameStrata())
    glowF:SetFrameLevel(math.max(0, miniBtn:GetFrameLevel() - 1))
    glowF:Hide()
    local glow = glowF:CreateTexture(nil, "BACKGROUND")
    glow:SetAllPoints()
    glow:SetTexture("Interface\\AddOns\\RPChronicler\\Media\\Scene\\glow")
    glow:SetBlendMode("ADD")
    glow:SetVertexColor(1, 0.12, 0.10, 1)

    -- pause badge: two amber bars on a dark square, bottom right
    local badge = CreateFrame("Frame", nil, miniBtn)
    badge:SetSize(14, 14)
    badge:SetPoint("BOTTOMRIGHT", 4, -4)
    badge:SetFrameLevel(miniBtn:GetFrameLevel() + 3)
    local bbg = badge:CreateTexture(nil, "BACKGROUND")
    bbg:SetAllPoints()
    bbg:SetColorTexture(0.05, 0.05, 0.06, 0.92)
    for i = 1, 2 do
        local bar = badge:CreateTexture(nil, "ARTWORK")
        bar:SetColorTexture(1, 0.72, 0.30, 1)
        bar:SetSize(3, 8)
        bar:SetPoint("CENTER", (i == 1) and -2.5 or 2.5, 0)
    end
    badge:Hide()

    local state = nil
    local function Apply(newState)
        state = newState
        if newState == "rec" then
            logo:SetVertexColor(1, 1, 1)
            logo:SetDesaturated(false)
            badge:Hide()
            if miniBtn:IsShown() then glowF:Show() end
            miniBtn:SetBackdropColor(0.28, 0.06, 0.06, 0.96)
        elseif newState == "paused" then
            glowF:Hide()
            logo:SetDesaturated(true)
            logo:SetVertexColor(0.6, 0.6, 0.6)
            badge:Show()
            miniBtn:UnlockHighlight()
            miniBtn:SetBackdropBorderColor(1, 0.72, 0.30, 0.95)
        else
            glowF:Hide()
            badge:Hide()
            logo:SetDesaturated(false)
            logo:SetVertexColor(1, 1, 1)
            miniBtn:UnlockHighlight() -- restores the normal gold look
        end
    end
    miniBtn:HookScript("OnShow", function() if state == "rec" then glowF:Show() end end)
    miniBtn:HookScript("OnHide", function() glowF:Hide() end)

    miniBtn:HookScript("OnUpdate", function()
        local run = ns.GetActiveAdventure()
        local want = run and (run.paused and "paused" or "rec") or nil
        if want ~= state then Apply(want) end
        if state == "rec" then
            local a = math.abs(math.sin(GetTime() * 3))
            glow:SetAlpha(0.35 + 0.65 * a)
            if not miniBtn:IsMouseOver() then
                miniBtn:SetBackdropBorderColor(1, 0.25, 0.25, 0.55 + 0.4 * a)
            end
        end
    end)

    miniBtn:HookScript("OnEnter", function(self)
        if not GameTooltip then return end
        GameTooltip:SetOwner(self, "ANCHOR_TOPLEFT")
        GameTooltip:SetText("|cffffd100RP Chronicler|r", 1, 1, 1)
        local run = ns.GetActiveAdventure()
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
-- 0.6.4: the RP button on the minimap's edge (the default), like other
-- addons. Drag it around the minimap; Options > General > RP button
-- switches between it and the floating button. Same clicks, same menu,
-- same recording dot.
-- =========================================================
do
    -- Made only when it is shown: with the floating button chosen there is
    -- no minimap button at all, so a minimap button collector can't take it
    local mm
    local function MakeMinimapButton()
        mm = CreateFrame("Button", "RPChroniclerMinimapButton", Minimap or UIParent)
        mm:SetSize(31, 31)
        mm:SetFrameStrata("MEDIUM")
        mm:SetFrameLevel(8)
        mm:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        mm:RegisterForDrag("LeftButton")
        mm:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
        local bg = mm:CreateTexture(nil, "BACKGROUND")
        bg:SetSize(20, 20)
        bg:SetPoint("TOPLEFT", 7, -5)
        bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
        local icon = mm:CreateTexture(nil, "ARTWORK")
        icon:SetSize(20, 20)
        icon:SetPoint("TOPLEFT", 7, -5)
        icon:SetTexture("Interface\\AddOns\\RPChronicler\\Media\\logo")
        local border = mm:CreateTexture(nil, "OVERLAY")
        border:SetSize(53, 53)
        border:SetPoint("TOPLEFT")
        border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
        local dot = mm:CreateTexture(nil, "OVERLAY", nil, 2)
        dot:SetSize(9, 9)
        dot:SetPoint("CENTER", mm, "TOPRIGHT", -7, -7)
        dot:SetTexture(UI.ICONS.DOT)
        dot:Hide()
        UI.minimapBtn = mm

        -- Position: an angle around the minimap (degrees), kept in the saved file
        local function Place()
            local angle = math.rad(tonumber(RPChroniclerDB and RPChroniclerDB.minimapAngle) or 200)
            local r = ((Minimap and Minimap:GetWidth() or 140) / 2) + 6
            mm:ClearAllPoints()
            mm:SetPoint("CENTER", Minimap or UIParent, "CENTER", math.cos(angle) * r, math.sin(angle) * r)
        end
        mm:SetScript("OnDragStart", function(self)
            self:SetScript("OnUpdate", function()
                if not Minimap then return end
                local mx, my = Minimap:GetCenter()
                local cx, cy = GetCursorPosition()
                local s = Minimap:GetEffectiveScale() or 1
                if not (mx and my) then return end
                RPChroniclerDB.minimapAngle = math.floor(math.deg(math.atan2(cy / s - my, cx / s - mx)) + 0.5) % 360
                Place()
            end)
        end)
        mm:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
        mm:SetScript("OnClick", function(self, button)
            if button == "RightButton" then
                UI.ToggleIconMenu(self)
            else
                RPChronicler_Toggle()
            end
        end)
        -- its own tooltip (the floating button's hover look needs a backdrop,
        -- which this round button has none of)
        mm:SetScript("OnEnter", function(self)
            local run = ns.GetActiveAdventure and ns.GetActiveAdventure()
            local state = run and (run.paused and "|cffffb74dRecording paused|r" or "|cffff5252Recording|r") or nil
            if state then
                UI.Tooltip(self, "|cffffd100RP Chronicler|r", state, "Click: open. Right-click: menu.", "Drag: move around the minimap.")
            else
                UI.Tooltip(self, "|cffffd100RP Chronicler|r", "Click: open. Right-click: menu.", "Drag: move around the minimap.")
            end
        end)
        mm:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)

        -- the recording dot, as on the floating button
        local acc = 0
        local ticker = CreateFrame("Frame", nil, mm)
        ticker:SetScript("OnUpdate", function(_, elapsed)
            acc = acc + elapsed
            if acc < 0.05 then return end
            acc = 0
            local run = ns.GetActiveAdventure()
            if run and run.paused then
                dot:SetVertexColor(1, 0.72, 0.30, 1)
                dot:SetAlpha(1)
                dot:Show()
            elseif run then
                dot:SetVertexColor(1, 0.15, 0.15, 1)
                dot:SetAlpha(0.35 + 0.65 * math.abs(math.sin(GetTime() * 4)))
                dot:Show()
            else
                dot:Hide()
            end
        end)

        UI.PlaceMinimapButton = Place
    end

    -- Shows the button the player chose (Options > General > RP button,
    -- or the button's right-click menu)
    function UI.ApplyIconMode()
        local onMinimap = ns.Get("iconMode") ~= "FLOAT" and Minimap ~= nil
        if onMinimap then
            if not mm then MakeMinimapButton() end
            UI.PlaceMinimapButton()
            mm:Show()
            miniBtn:Hide()
        else
            if mm then mm:Hide() end
            PlaceFloating()
            miniBtn:Show()
        end
    end
    ns.On("PLAYER_LOGIN", function() UI.ApplyIconMode() end)
    ns.Listen("setting", function(key) if key == "iconMode" then UI.ApplyIconMode() end end)
end

-- =========================================================
-- 0.6.3: one entry in the game's own Options > AddOns, with a single
-- button that opens RP Chronicler's Options (no settings of its own)
-- =========================================================
do
    local panel = CreateFrame("Frame", "RPChroniclerBlizzOptions", UIParent)
    panel.name = "RP Chronicler"
    panel:Hide()
    local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("|cffffd100RP Chronicler|r |cff8f9ba8v" .. tostring(ns.VERSION or "") .. "|r")
    local sub = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
    sub:SetWidth(520)
    sub:SetJustifyH("LEFT")
    sub:SetText("|cffd8dee9Record your adventures and get them back as stories, and copy the live scene for your AI. " ..
        "Every setting lives in RP Chronicler's own window.|r")
    local open = UI.CreateSleekButton(panel, 200, 26, "Open RP Chronicler Options", "gold")
    open:SetPoint("TOPLEFT", sub, "BOTTOMLEFT", 0, -14)
    open:SetScript("OnClick", function()
        -- closing the game's Options is a panel change: only out of combat
        if not (InCombatLockdown and InCombatLockdown()) then
            if SettingsPanel and SettingsPanel.IsShown and SettingsPanel:IsShown() and HideUIPanel then pcall(HideUIPanel, SettingsPanel) end
        end
        UI.OpenOptionsPage(RPChroniclerDB and RPChroniclerDB.optionsPage or "GENERAL")
    end)
    local slash = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    slash:SetPoint("TOPLEFT", open, "BOTTOMLEFT", 0, -10)
    slash:SetText("|cff8f9ba8Or type /rp in chat, or click the RP button (on the minimap, or floating).|r")

    local ok = false
    if Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory then
        ok = pcall(function()
            local cat = Settings.RegisterCanvasLayoutCategory(panel, panel.name)
            Settings.RegisterAddOnCategory(cat)
            UI.blizzCategory = cat
        end)
    end
    if not ok then ns.Debug("info", "no Options > AddOns entry on this client") end
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
        -- 0.6.4: shows or hides whichever RP button you chose
        local b = (ns.Get("iconMode") ~= "FLOAT" and UI.minimapBtn) or miniBtn
        if b:IsShown() then b:Hide() else b:Show() end
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
        UI.OpenSetup(true)
    elseif low == "wipe" then
        UI.ShowPrompt("|cffff6b6bDelete ALL RP Chronicler data?|r\nEvery recording, story, companion and setting is removed, then the UI reloads. This cannot be undone.",
            "Delete everything", function() ns.WipeAllData() end, "Cancel", nil)
    elseif low == "feedback" or low == "bug" then
        UI.OpenFeedback()
    elseif low == "debug" then
        UI.ShowCopyBox("|cffffd100RP Chronicler debug report|r",
            "|cffb0bac5Select All, Ctrl+C, and paste it into your bug report. It holds no chat.|r",
            ns.BuildDebugReport())
    elseif low == "debug verbose" then
        -- 0.6.1: extra detail in the debug log, for this session only
        ns.debugVerbose = not ns.debugVerbose
        print("|cff00ff00[RP Chronicler]|r Verbose debug log " .. (ns.debugVerbose and "on until you log out or /reload." or "off."))
    elseif low == "debug clear" then
        ns.ClearDebugData()
        print("|cff00ff00[RP Chronicler]|r Debug log and saved error reports cleared.")
    elseif low == "note" or low:match("^note%s") then
        -- 0.6.3: the character's thought, into the Full Log at this moment
        local text = trimmed:match("^[Nn][Oo][Tt][Ee]%s+(.+)$")
        if not text then
            UI.AskStoryNote()
        else
            local ok, status = ns.RecordRunNote(text)
            print((ok and "|cff00ff00[RP Chronicler]|r " or "|cffffb74d[RP Chronicler]|r ") .. status)
            if ok then pcall(UI.RefreshRunViews) end
        end
    elseif low == "pause" or low == "resume" then
        local ok, status
        if low == "pause" then
            ok, status = ns.PauseAdventure()
        else
            ok, status = ns.ResumeAdventure()
        end
        print("|cff00ff00[RP Chronicler]|r " .. tostring(status))
        pcall(UI.RefreshRunViews)
    elseif low == "end" or low == "stop" then
        local saved = ns.GetActiveAdventure() and ns.EndAdventure("Ended Manually")
        print("|cff00ff00[RP Chronicler]|r " .. (saved and ("Saved adventure: " .. (saved.title or "Adventure")) or "No active adventure running."))
        pcall(UI.RefreshRunViews)
    elseif low == "diag" then
        for _, line in ipairs(ns.DiagnoseTarget()) do
            print("|cffffd100[RP Chronicler diag]|r " .. line)
        end
    elseif low:match("^mark") then
        local noteArg = trimmed:match("^mark%s+(.+)$")
        local ok, status = ns.MarkAdventureHighlight(noteArg)
        print("|cff00ff00[RP Chronicler]|r " .. status)
        if ok then
            ns.RequestScreenshot("mark", noteArg or "Marked moment")
        end
    else
        RPChronicler_Open(trimmed)
    end
end
