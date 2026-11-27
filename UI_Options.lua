local ADDON_NAME, ns = ...
local UI = ns.UI

-- =========================================================
-- Skill template modal (RP persona or adventure story)
-- =========================================================
local tpl = {}
do
    local f = CreateFrame("Frame", "RPChroniclerSkillTemplateFrame", UIParent, UI.BACKDROP)
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

    local scroll = CreateFrame("ScrollFrame", "RPChroniclerSkillTemplateScroll", boxBg, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 8, -8)
    scroll:SetPoint("BOTTOMRIGHT", -28, 8)

    local eb = CreateFrame("EditBox", "RPChroniclerSkillTemplateEditBox", scroll)
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
    if mode == "STORY" or mode == "ADVENTURE" then ns.MarkTemplateCopied() end
    if mode == "STORY" then
        tpl.title:SetText("|cffffd100Dungeon Story Template (press Ctrl+C to copy)|r")
        tpl.sub:SetText("|cffb0bac5Paste it into your AI once: one chapter per boss. Full Logs of dungeons start with 'use " .. ns.STORY_SKILLS.dungeon .. "'.|r")
        tpl.editBox:SetText(EscapeForEditBox(ns.DUNGEON_STORY_TEMPLATE))
    elseif mode == "ADVENTURE" then
        tpl.title:SetText("|cffffd100Adventure Story Template (press Ctrl+C to copy)|r")
        tpl.sub:SetText("|cffb0bac5Paste it into your AI once: open world, solo, by place and event. Those Full Logs start with 'use " .. ns.STORY_SKILLS.world .. "'.|r")
        tpl.editBox:SetText(EscapeForEditBox(ns.ADVENTURE_STORY_TEMPLATE))
    else
        tpl.title:SetText("|cffffd100Character RP Skill Template (press Ctrl+C to copy)|r")
        tpl.sub:SetText("|cffb0bac5A simple starter: fill in the <...> fields and make it your character before you paste it into your AI.|r")
        tpl.editBox:SetText(EscapeForEditBox(ns.GetRpSkillTemplate()))
    end
    tpl.frame:Show()
    tpl.editBox:SetFocus()
    tpl.editBox:HighlightText()
end

-- =========================================================
-- OPTIONS section (behind the gear): pages listed down the left.
-- 0.6.1: six pages built from ns.SETTINGS (Core.lua). Every row reads and
-- writes through ns.Get / ns.Set; the page code never edits saved data.
-- =========================================================
local view = UI.NewSection("OPTIONS", "The Binder's Desk", "Settings are saved for your whole account.")
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

-- rpCopy = true: the page only exists while RP Copy is on
local PAGE_ORDER = {
    { key = "GENERAL", label = "General" },
    { key = "SLICES", label = "Copy and Tabs", rpCopy = true },
    { key = "RECORDING", label = "Recording" },
    { key = "COMPANIONS", label = "Companions" },
    { key = "AI", label = "AI & Stories" },
    { key = "PRIVACY", label = "Privacy" },
}
-- Old page keys (saved as the last page you opened) land on their new page
local OLD_PAGES = { KEYS = "GENERAL", ADVENTURES = "RECORDING", FULLLOG = "RECORDING", SUMMARY = "RECORDING",
    STORIES = "AI", DEBUG = "PRIVACY" }

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

local function PageShown(item)
    return not item.rpCopy or ns.RpCopyOn()
end

local function LayoutNav()
    local i = 0
    -- 0.6.3: the nav is as wide as its longest label at the current font
    local need = 98
    for _, item in ipairs(PAGE_ORDER) do
        local b = O.navButtons[item.key]
        if b then need = math.max(need, UI.ButtonWidth(b)) end
    end
    need = math.min(need, 160)
    O.nav:SetWidth(need + 14)
    for _, item in ipairs(PAGE_ORDER) do
        local b = O.navButtons[item.key]
        if PageShown(item) then
            b:ClearAllPoints()
            b:SetPoint("TOP", 0, -8 - i * 28)
            b:SetWidth(need)
            b:Show()
            i = i + 1
        else
            b:Hide()
        end
    end
end

local function PageKey(key)
    key = OLD_PAGES[key] or key
    for _, item in ipairs(PAGE_ORDER) do
        if item.key == key then return PageShown(item) and key or "GENERAL" end
    end
    return "GENERAL"
end

function UI.RefreshOptionsPage()
    UI.EnsureOptions()
    local fn = O.refresh[PageKey(RPChroniclerDB.optionsPage)]
    if fn then fn() end
end

function UI.ShowOptionsPage(key)
    UI.EnsureOptions()
    key = PageKey(key)
    RPChroniclerDB.optionsPage = key
    LayoutNav()
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
    RPChroniclerDB.optionsPage = PageKey(key)
    if UI.frame:IsShown() then
        UI.ShowSection("OPTIONS")
    else
        RPChronicler_Open("", "OPTIONS")
    end
end

for _, item in ipairs(PAGE_ORDER) do
    local b = UI.CreateSleekButton(O.nav, 98, 24, item.label)
    b:SetScript("OnClick", function() UI.ShowOptionsPage(item.key) end)
    O.navButtons[item.key] = b
end
LayoutNav()

-- ---------------------------------------------------------
-- Rows bound to ns.SETTINGS keys
-- ---------------------------------------------------------
-- One row per setting: an ON/OFF button, a button that steps through the
-- choices, or a number box. defs: { key, label, tip, names = {choice = text}, after }
local function SettingRows(p, y, defs)
    local rows, buttons = {}, {}
    for i, d in ipairs(defs) do
        local s = ns.SETTING[d.key]
        local b = UI.CreateSleekButton(p, 250, 20, "")
        b:SetPoint("TOPLEFT", 0, y - (i - 1) * 24)
        b.tipTitle, b.tipText = "|cffffd100" .. d.label .. "|r", d.tip
        b:SetScript("OnClick", function()
            if s.choices then
                local idx = 1
                for ci, c in ipairs(s.choices) do if c == ns.Get(d.key) then idx = ci end end
                ns.Set(d.key, s.choices[(idx % #s.choices) + 1])
            else
                ns.Toggle(d.key)
            end
            if d.after then pcall(d.after) end
            UI.RefreshOptionsPage()
        end)
        rows[i] = { btn = b, def = d, setting = s }
        buttons[i] = b
    end
    return function()
        for _, r in ipairs(rows) do
            local v = ns.Get(r.def.key)
            if r.setting.choices then
                r.btn:SetText("|cffd8dee9" .. r.def.label .. ":|r |cffffd100" .. (r.def.names[v] or tostring(v)) .. "|r")
            else
                UI.SetToggleLook(r.btn, v and true or false, r.def.label .. ": ON", r.def.label .. ": OFF")
            end
            -- 0.6.3: at least 250 wide, wider when the label needs it
            if not r.fixedW then
                local maxW = math.max(250, math.floor(p:GetWidth() or 0))
                r.btn:SetWidth(math.min(maxW, math.max(250, UI.ButtonWidth(r.btn))))
            end
        end
    end, y - #defs * 24, buttons, rows
end

-- A number box for a number setting (its min and max come from ns.SETTINGS)
local function NumberRow(p, x, y, label, key, tip, boxW)
    local s = ns.SETTING[key]
    local lbl = UI.Label(p, label, "GameFontHighlightSmall")
    lbl:SetPoint("TOPLEFT", x, y - 4)
    local eb = CreateFrame("EditBox", "RPChroniclerOptNum_" .. key, p, "InputBoxTemplate")
    eb:SetSize(boxW or 44, 20)
    eb:SetPoint("TOPLEFT", x + 180, y)
    eb:SetAutoFocus(false)
    eb:SetNumeric(true)
    eb:SetMaxLetters(7)
    local function Commit(self)
        self:SetText(tostring(ns.Set(key, self:GetText()) or ns.Get(key)))
        self:ClearFocus()
    end
    eb:SetScript("OnEnterPressed", Commit)
    eb:SetScript("OnEditFocusLost", Commit)
    eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    eb:SetScript("OnEnter", function(self)
        UI.Tooltip(self, "|cffffd100" .. label .. "|r", (tip or "") .. string.format(" From %d to %d. Default %d.", s.min, s.max, s.default))
    end)
    eb:SetScript("OnLeave", UI.HideTooltip)
    return function() eb:SetText(tostring(ns.Get(key))) end, eb, lbl
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
        cb:SetPoint("TOPLEFT", col * (colW or 180), y - row * 18)
        local lbl = cb:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        lbl:SetPoint("LEFT", cb, "RIGHT", 2, 0)
        lbl:SetText(d.label)
        if d.tip then
            cb:SetScript("OnEnter", function(self) UI.Tooltip(self, "|cffffd100" .. d.label .. "|r", d.tip) end)
            cb:SetScript("OnLeave", UI.HideTooltip)
        end
        cb:SetScript("OnClick", function(self)
            local t = store()
            t[d.key] = self:GetChecked() and true or false
        end)
        checks[d.key] = cb
    end
    return function()
        local t = store()
        for key, cb in pairs(checks) do cb:SetChecked(t[key] ~= false) end
    end, y - half * 18
end
UI.OptionsCheckGrid = CheckGrid

-- 0.6.3: returns a layout function; the two buttons flow (UI.FlowRow)
-- and wrap under each other on a narrow page. It returns the height used.
local function TemplateButtons(p, y)
    local dBtn = UI.CreateSleekButton(p, 160, 24, "Dungeon Template", "gold")
    dBtn:SetIcon(UI.ICONS.STORY, 16)
    UI.SetButtonLabels(dBtn, "Dungeon Template", "Dungeon")
    dBtn:SetScript("OnClick", function() UI.OpenSkillTemplateModal("STORY") end)
    local aBtn = UI.CreateSleekButton(p, 150, 24, "Adventure Template", "gold")
    aBtn:SetIcon(UI.ICONS.STORY, 16)
    UI.SetButtonLabels(aBtn, "Adventure Template", "Adventure")
    aBtn:SetScript("OnClick", function() UI.OpenSkillTemplateModal("ADVENTURE") end)
    return function(width)
        return UI.FlowRow(p, { dBtn, aBtn }, nil, { y = -y, width = width, rowH = 24, gap = 6 })
    end
end

-- ---------------------------------------------------------
-- General: RP Copy and Ctrl+C
-- ---------------------------------------------------------
do
    local p = NewPage("GENERAL", "General")
    local rows, y = SettingRows(p, -24, {
        { key = "rpCopy", label = "RP Copy",
          tip = "The live scene copy: the Copy view, Ctrl+C, slice tabs, Nearby companions and the RP reply template. OFF: none of it runs and RP Chronicler keeps no chat for it. Recordings, companions and the Story Book still work.",
          after = function() LayoutNav() end },
        { key = "iconMode", label = "RP button", names = { MINIMAP = "On the minimap", FLOAT = "Floating" },
          tip = "On the minimap (default): the RP button sits on the minimap's edge; drag it around. Floating: the RP button you can drag anywhere on the screen. Both open the window on left-click and the recording menu on right-click." },
    })
    local copyRows, copyBtns
    copyRows, y, copyBtns = SettingRows(p, y - 6, {
        { key = "quickCtrlC", label = "Ctrl+C copies the scene",
          tip = "In the game world (no text box focused), Ctrl+C copies the last slice tab you used. OFF: Ctrl+C is left to the game.",
          after = function() UI.UpdateOverrideBindings() end },
        { key = "copyMode", label = "Ctrl+C style", names = { INSTANT = "Instant", BOX = "Copy box" },
          tip = "Instant: hold Ctrl a blink, press C, done. Copy box: Ctrl+C shows the snapshot selected in a small box; Ctrl+C there copies it. Copy box is the default. With Instant, a Ctrl+key you press after holding Ctrl a moment can be taken by the copy." },
        { key = "quickNote", label = "Ask for an instruction on Ctrl+C",
          tip = "Ctrl+C first opens a one-line box for a quick instruction to your AI (\"be flirty\", \"reply to Thrall\"). Type it and press Ctrl+C right there: the scene is copied with it as its [Instruction] line. Esc copies without one.",
          after = function() UI.SyncCopyChip() end },
    })
    local msgRefresh, msgBox, msgLabel = NumberRow(p, 0, y - 4, "Chat messages per source", "messages",
        "How many recent messages each chat source puts in a snapshot. Expand on the Copy view doubles it.")
    local off = Note(p, "", 0, y - 34)
    Note(p, "|cff8f9ba8Other shortcuts (open the window, add a companion, mark a moment, add a story note, start, pause or end a run) are in the game's own Esc > Options > Keybindings > AddOns > RP Chronicler. They have no keys until you set them.|r", 0, y - 64)
    local resetBtn = UI.CreateSleekButton(p, 150, 24, "Reset Window", "tool")
    resetBtn:SetPoint("TOPLEFT", 0, y - 118)
    resetBtn.tipTitle = "|cffffd100Reset Window|r"
    resetBtn.tipText = "Puts the window back to its default size in the middle of the screen."
    resetBtn:SetScript("OnClick", function() UI.ResetWindow() end)
    -- 0.6.5: feature ideas and bug reports (links to copy, plus the report)
    local fbBtn = UI.CreateSleekButton(p, 150, 24, "Feedback", "gold")
    fbBtn:SetPoint("LEFT", resetBtn, "RIGHT", 8, 0)
    fbBtn.tipTitle = "|cffffd100Feedback|r"
    fbBtn.tipText = "An idea or a bug? Shows where to send it, with a bug report (version and RP Chronicler's own saved errors, never chat) to paste in."
    fbBtn:SetScript("OnClick", function() UI.OpenFeedback() end)
    O.refresh.GENERAL = function()
        rows()
        copyRows()
        msgRefresh()
        off:SetText(ns.RpCopyOn() and "" or "|cffffb74dRP Copy is off: Ctrl+C, the Copy view and its chat buffers are not running.|r")
        -- 0.7.0 (Mor): Copy-only settings hide while RP Copy is off
        local on = ns.RpCopyOn()
        for _, b in ipairs(copyBtns) do if on then b:Show() else b:Hide() end end
        for _, x in ipairs({ msgBox, msgLabel }) do if on then x:Show() else x:Hide() end end
    end
end

-- ---------------------------------------------------------
-- Slice Tabs (RP Copy): every tab and its contents stay editable
-- ---------------------------------------------------------
do
    local p = NewPage("SLICES", "Copy and Tabs")
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

    local scroll = CreateFrame("ScrollFrame", "RPChroniclerOptListScroll", list, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 6, -6)
    scroll:SetPoint("BOTTOMRIGHT", -26, 6)
    scroll.scrollBarHideable = true
    local child = CreateFrame("Frame", nil, scroll)
    child:SetSize(98, 10)
    scroll:SetScrollChild(child)

    local ed = CreateFrame("Frame", nil, p)
    ed:SetPoint("TOPLEFT", list, "TOPRIGHT", 10, 0)
    ed:SetPoint("BOTTOMRIGHT", 0, 0)

    UI.Label(ed, "Tab name:"):SetPoint("TOPLEFT", 0, -2)
    S.name = CreateFrame("EditBox", "RPChroniclerOptTabName", ed, "InputBoxTemplate")
    S.name:SetSize(110, 20)
    S.name:SetPoint("TOPLEFT", 6, -16)
    S.name:SetAutoFocus(false)
    S.up = UI.CreateSleekButton(ed, 40, 20, "Up")
    S.up:SetPoint("TOPRIGHT", -44, -16)
    S.down = UI.CreateSleekButton(ed, 40, 20, "Down")
    S.down:SetPoint("TOPRIGHT", 0, -16)

    UI.Label(ed, "Skill Call (line 1, calls your AI skill):"):SetPoint("TOPLEFT", 0, -42)
    S.prefix = CreateFrame("EditBox", "RPChroniclerOptTabPrefix", ed, "InputBoxTemplate")
    S.prefix:SetHeight(20)
    S.prefix:SetPoint("TOPLEFT", 6, -56)
    S.prefix:SetPoint("TOPRIGHT", -2, -56)
    S.prefix:SetAutoFocus(false)
    Note(ed, "|cff8f9ba8Default: |cff69ccf0use|r |cff8f9ba8and your character's first name. Clear it to copy raw data only.|r", 0, -80)

    UI.Label(ed, "Included in this slice:"):SetPoint("TOPLEFT", 0, -100)
    -- The scene sections, then the chat sources (both lists live in Core.lua)
    local defs = {}
    for _, d in ipairs(ns.TAB_SECTIONS) do table.insert(defs, d) end
    for _, d in ipairs(ns.CHAT_SOURCES) do table.insert(defs, d) end
    local half = math.ceil(#defs / 2)
    for idx, d in ipairs(defs) do
        local cb = CreateFrame("CheckButton", "RPChroniclerOptCB_" .. d.key, ed, "UICheckButtonTemplate")
        cb:SetSize(20, 20)
        local col = (idx <= half) and 0 or 1
        local row = (idx <= half) and (idx - 1) or (idx - half - 1)
        cb:SetPoint("TOPLEFT", col * 112, -116 - row * 20)
        local lbl = cb:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        lbl:SetPoint("LEFT", cb, "RIGHT", 2, 0)
        lbl:SetWidth(90)
        lbl:SetJustifyH("LEFT")
        lbl:SetWordWrap(false)
        lbl:SetText(d.short or d.label)
        cb:SetScript("OnEnter", function(self) UI.Tooltip(self, "|cffffd100" .. d.label .. "|r", d.tip) end)
        cb:SetScript("OnLeave", UI.HideTooltip)
        S.checks[d.key] = cb
    end

    S.save = UI.CreateSleekButton(ed, 96, 22, "Save Tab", "gold")
    S.save:SetPoint("BOTTOMLEFT", 0, 2)
    S.del = UI.CreateSleekButton(ed, 88, 22, "Delete Tab", "danger")
    S.del:SetPoint("BOTTOMRIGHT", 0, 2)

    local function Selected()
        return ns.GetTabConfig(ns.state.selectedOptionTabId) or RPChroniclerDB.tabs[1]
    end

    local function Changed()
        UI.RebuildSliceTabs()
        UI.RefreshOptionsPage()
    end

    O.refresh.SLICES = function()
        local sel = Selected()
        ns.state.selectedOptionTabId = sel.id
        S.name:SetText(sel.label or "")
        S.prefix:SetText(ns.SkillCall(sel.prefix or ""))
        for key, cb in pairs(S.checks) do cb:SetChecked(sel[key] and true or false) end
        S.del.armedAt = nil
        S.del:SetText("Delete Tab")
        resetBtn.armedAt = nil
        resetBtn:SetText("Reset")
        for _, rb in ipairs(S.rows) do rb:Hide() end
        for idx, t in ipairs(RPChroniclerDB.tabs) do
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
        child:SetHeight(math.max(10, #RPChroniclerDB.tabs * 24))
    end

    S.save:SetScript("OnClick", function()
        local fields = { label = S.name:GetText(), prefix = S.prefix:GetText() }
        -- 0.6.5: left as this character's default, it stays per character
        local cur = Selected().prefix
        if cur == ns.DEFAULT_TRIGGER and (fields.prefix or ""):match("^%s*(.-)%s*$") == ns.SkillCall(cur) then fields.prefix = cur end
        for key, cb in pairs(S.checks) do fields[key] = cb:GetChecked() and true or false end
        local t = ns.SaveTab(Selected().id, fields)
        S.name:ClearFocus()
        S.prefix:ClearFocus()
        Changed()
        if t then UI.SetStatus("Saved slice tab '" .. t.label .. "'.", "good") end
    end)

    addBtn:SetScript("OnClick", function()
        ns.state.selectedOptionTabId = ns.AddTab()
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

    S.up:SetScript("OnClick", function() if ns.MoveTab(Selected().id, -1) then Changed() end end)
    S.down:SetScript("OnClick", function() if ns.MoveTab(Selected().id, 1) then Changed() end end)

    S.del:SetScript("OnClick", function(self)
        if #RPChroniclerDB.tabs <= 1 then
            UI.SetStatus("Keep at least one slice tab.", "error")
            return
        end
        if not self.armedAt or GetTime() - self.armedAt > 4 then
            self.armedAt = GetTime()
            self:SetText("|cffff6b6bSure?|r")
            return
        end
        local removed, why = ns.DeleteTab(Selected().id)
        if not removed then UI.SetStatus(why, "error") return end
        Changed()
        UI.SetStatus("Deleted slice tab '" .. (removed.label or "") .. "'.", "good")
    end)

    p:SetScript("OnHide", function()
        S.name:ClearFocus()
        S.prefix:ClearFocus()
    end)
end

-- ---------------------------------------------------------
-- Recording: when runs record, screenshots, and what the Full Log keeps
-- ---------------------------------------------------------
do
    local p = NewPage("RECORDING", "Recording")
    local rows, y = SettingRows(p, -24, {
        { key = "instanceRecord", label = "Dungeons",
          names = { ASK = "Ask on entry", AUTO = "Always record", OFF = "Never" },
          tip = "Ask on entry (default): entering a dungeon asks 'Start recording?'. Always record: the run starts by itself. Never: you start every run yourself. A dungeon run ends when you leave the dungeon. Raids: coming soon (TBA)." },
        { key = "partyGear", label = "Record party gear",
          tip = "On (default): while a run records, RP Chronicler inspects each party member once, out of combat and in range, like the game's own Inspect, and keeps the gear they wore with the run (on your PC only). Their character window then lists it and their model wears it. Off: nobody is inspected." },
        { key = "autoShots", label = "Auto-screenshots",
          names = { OFF = "Off", INSTANCE = "Dungeons", ALL = "Everywhere" },
          tip = "Screenshots on boss kills, level ups, new places and marked moments while a run records. Dungeons (default): open-world runs only take one when you Mark Moment. Your own Print Screen shots always join the run.",
},
        { key = "logDetail", label = "Log detail",
          names = { SHORT = "Short", NORMAL = "Normal", RICH = "Rich" },
          tip = "How much the Full Log keeps: Short for free AI plans, Rich for long paid ones. Sets the shortest fight logged and how many spells, NPC lines, timeline lines and screenshots a run keeps." },
    })
    UI.Label(p, "|cffd8dee9Full Log keeps:|r", "GameFontHighlightSmall"):SetPoint("TOPLEFT", 0, y - 6)
    local groupRefresh
    groupRefresh, y = CheckGrid(p, y - 22, ns.LOG_GROUPS, function() return RPChroniclerDB.logGroups end, "RPChroniclerOptLog_")
    Note(p, "|cff8f9ba8Open-world runs: click Start Recording in Adventures or use the RP icon's right-click menu. A run cut short by a logout or disconnect is saved as interrupted, never lost, and a /reload keeps recording. The Full Log never keeps OOC chat.|r", 0, y - 40)
    O.refresh.RECORDING = function()
        rows()
        groupRefresh()
    end
end

-- ---------------------------------------------------------
-- Companions
-- ---------------------------------------------------------
do
    local p = NewPage("COMPANIONS", "Companions")
    local rows, y, cBtns = SettingRows(p, -24, {
        { key = "knownPlayerBlocks", label = "[Known Player] blocks",
          tip = "Adds your notes on the people in the scene (up to 3, notes cut to 300 letters) to the snapshot you copy." },
        { key = "autoUpdateKnown", label = "Update companions from chat",
          tip = "Keeps a companion's level, class and latest chat up to date when they talk near you." },
        { key = "companionMenu", label = "Add as companion (right-click)",
          tip = "Adds 'Add as RP Chronicler companion' to the game's player right-click menu (where the game allows it)." },
        { key = "runCompanions", label = "Companions in the Full Log",
          tip = "Companions you chat with during a run are listed as Known companions in its Full Log, with their notes." },
    })
    Note(p, "|cff8f9ba8Per companion, the Include button in Companions picks Auto, Always or Never. Auto adds a companion when they are your target, in your group, on screen or in the copied chat.|r", 0, y - 10)
    O.refresh.COMPANIONS = function()
        rows()
        -- 0.7.0: [Known Player] blocks only serve the copy
        if ns.RpCopyOn() then cBtns[1]:Show() else cBtns[1]:Hide() end
    end
end

-- ---------------------------------------------------------
-- AI & Stories: the templates, reply length and the export tip
-- ---------------------------------------------------------
do
    local p = NewPage("AI", "AI & Stories")
    local rpPart = CreateFrame("Frame", nil, p)
    rpPart:SetPoint("TOPLEFT", 0, -22)
    rpPart:SetPoint("RIGHT", p, "RIGHT", 0, 0)
    rpPart:SetHeight(112)
    Note(rpPart,
        "|cffffd100Your character skill (one time)|r\n" ..
        "|cffd8dee9Copy the RP Template, fill in your character, and make it a Skill in Gemini, a Project in ChatGPT, or a Skill or Project in Claude. " ..
        "Name its trigger after your character (like |cff69ccf0" .. ns.SkillCall(ns.DEFAULT_TRIGGER) .. "|cffd8dee9, the Skill Call every tab uses unless you change it in Copy and Tabs).|r",
        0, -4)
    local rpBtn = UI.CreateSleekButton(rpPart, 130, 24, "RP Template", "gold")
    rpBtn:SetPoint("TOPLEFT", 0, -78)
    rpBtn:SetIcon(UI.ICONS.COPY, 16)
    rpBtn:SetScript("OnClick", function() UI.OpenSkillTemplateModal("RP") end)
    local lenRows, _, lenBtns = SettingRows(rpPart, -78, {
        { key = "rpReplyLength", label = "Replies", names = { SHORT = "Short", MEDIUM = "Medium", LONG = "Long" },
          tip = "How long the RP template asks replies to be. Short is like real chat (about 5 to 14 words). Copy the template again after changing it." },
    })
    -- the reply-length button sits next to the RP Template button
    -- 0.6.3: both flow on one row, or two on a narrow page
    lenBtns[1].fixedW = true
    lenBtns[1]:SetHeight(24)

    local stories = CreateFrame("Frame", nil, p)
    stories:SetPoint("RIGHT", p, "RIGHT", 0, 0)
    stories:SetHeight(346)
    -- 0.6.5: Include AI instructions adds the story rules, so the skill is optional
    Note(stories,
        "|cffffd100Your stories|r\n" ..
        "|cffd8dee9After a run, open its Full Log, tick |cffffd100Include AI instructions|cffd8dee9 and click |cffffd100Copy for AI|cffd8dee9. Paste it into any AI chat, copy the story back and Import it in the Story Book. " ..
        "|cff9aa5b4Advanced: use a skill.|cffd8dee9 Make a template below a skill in your AI (Dungeon: 'use " .. ns.STORY_SKILLS.dungeon .. "', Adventure: 'use " .. ns.STORY_SKILLS.world .. "') " ..
        "and copy the Full Log with Include AI instructions off.|r",
        0, 0)
    local tplLayout = TemplateButtons(stories, -86)
    local tipRows = SettingRows(stories, -120, {
        { key = "exportTip", label = "Tip line in the Library",
          tip = "One line under the Library's shelves: how unbound pages get their story, or how to read your stories with screenshots in StoryViewer.html." },
        { key = "storyCover", label = "Story scenes",
          tip = "Each story opens with its party: you in 3D in the gear from that run, companions near you as they are, everyone else as a shadow of their race, in front of a painting of the place. At each boss's chapter the party faces the boss, and after the kill you see it fall. Click anyone to see them up close with their items. Off: the book is only written pages (also if your client shows no models)." },
        { key = "standIns", label = "Likeness figures",
          tip = "On (default): someone in a story who is not near you is drawn as a likeness, their race in the outfit they wore (on a figure of your own sex; the game can't draw faces it never saw). A shared book's author can pick a face for it. Off: their race shadow." },
        { key = "bookMusic", label = "Dungeon music in the book",
          tip = "While a dungeon story's pages are open, the game's own music for that kind of dungeon plays (at your music volume). Off, or when Story scenes is off: the book is silent and the game's music goes on as usual." },
        { key = "bookPages", label = "Pages", names = { PARCHMENT = "Parchment", LIGHT = "Light parchment", NIGHT = "Night" },
          tip = "Parchment: warm paper pages, with the story's colors inked darker so they read on paper. Light parchment: the same, on brighter pages. Night: dark pages, with the colors as the story was written." },
        { key = "bookMotion", label = "Animations",
          tip = "The book opens from its front cover, turns its pages and closes to its cover; the plaque's rune ring turns and its wax seal pulses while you record. Off: everything happens at once and stands still." },
    })
    Note(stories, "|cff9aa5b4Which AI and which plan? See the README's Requirements section.|r", 0, -300)
    O.refresh.AI = function()
        stories:ClearAllPoints()
        stories:SetPoint("RIGHT", p, "RIGHT", 0, 0)
        if ns.RpCopyOn() then
            rpPart:Show()
            stories:SetPoint("TOPLEFT", 0, -140)
        else
            rpPart:Hide()
            stories:SetPoint("TOPLEFT", 0, -26)
        end
        lenRows()
        tipRows()
        local w = math.floor(p:GetWidth() or 0)
        if w > 50 then
            local h = UI.FlowRow(rpPart, { rpBtn, lenBtns[1] }, nil, { y = 78, width = w, rowH = 24, gap = 6 })
            rpPart:SetHeight(78 + h + 10)
            tplLayout(w)
            if ns.RpCopyOn() then
                stories:ClearAllPoints()
                stories:SetPoint("RIGHT", p, "RIGHT", 0, 0)
                stories:SetPoint("TOPLEFT", 0, -(22 + 78 + h + 10 + 6))
            end
        end
    end
end

-- ---------------------------------------------------------
-- Privacy: the disclaimer, what is captured, setup, debug report, wipe
-- ---------------------------------------------------------
do
    local p = NewPage("PRIVACY", "Privacy")
    local text = Note(p, ns.PRIVACY_TEXT, 0, -20)
    local capLabel = UI.Label(p, "|cffffd100Chat RP Chronicler keeps:|r", "GameFontHighlightSmall")
    local capHolder = CreateFrame("Frame", nil, p)
    capHolder:SetSize(360, 80)
    local refreshGrid = CheckGrid(capHolder, 0, ns.CAPTURE_TYPES, function() return RPChroniclerDB.capture end, "RPChroniclerOptCap_")
    -- 0.6.3: error reports kept in the saved file, and the update notice
    local privHolder = CreateFrame("Frame", nil, p)
    privHolder:SetSize(360, 76)
    local privRows = SettingRows(privHolder, 0, {
        { key = "keepErrors", label = "Keep error reports",
          tip = "Keeps RP Chronicler's own last 20 errors (with the addon and game version, never chat) in its saved file, so a bug report needs no second try. /rp debug shows them; /rp debug clear deletes them." },
        { key = "versionCheck", label = "Update notices",
          tip = "Sends only RP Chronicler's version number to your group and guild, through the game's addon messages, and tells you once when someone has a newer version. Nothing else is ever sent. OFF: nothing is sent or read." },
        { key = "storySharing", label = "Story sharing", names = { OFF = "Off", FRIENDS = "Friends, guild, group", ANYONE = "Anyone" },
          tip = "Who may offer you a story (a book's menu: Share with a friend). Off (default): offers are ignored. Friends, guild, group: only them. Anyone: any player. You are always asked first (Accept, Decline or Block), and a book carries only its text, party names, classes, races, outfits and boss names: never screenshots, chat or notes. Sending a book of yours works whatever this says." },
    })
    local btns = CreateFrame("Frame", nil, p)
    btns:SetSize(360, 60)
    local setupBtn = UI.CreateSleekButton(btns, 120, 24, "Setup Again", "gold")
    setupBtn.tipTitle = "|cffffd100Setup|r"
    setupBtn.tipText = "Shows the first-run setup again (/rp setup)."
    setupBtn:SetScript("OnClick", function() UI.OpenSetup(true) end)
    local reportBtn = UI.CreateSleekButton(btns, 120, 24, "Debug Report", "tool")
    reportBtn.tipTitle = "|cffffd100Debug Report|r"
    reportBtn.tipText = "RP Chronicler keeps a small debug log (its own errors, blocked actions, runs starting and ending; never chat). Copy it into a bug report. Same as /rp debug."
    reportBtn:SetScript("OnClick", function() SlashCmdList["RPCHRONICLER"]("debug") end)
    -- 0.7.0: who you blocked from offering you stories
    local blockBtn = UI.CreateSleekButton(btns, 120, 24, "Blocked Sharers", "tool")
    blockBtn.tipTitle = "|cffffd100Blocked sharers|r"
    blockBtn.tipText = "Players you blocked when they offered you a story. Their offers are ignored."
    blockBtn:SetScript("OnClick", function()
        local list = ns.ShareBlockedList()
        if #list == 0 then UI.SetStatus("Nobody is blocked.", "good") return end
        UI.ShowPrompt("|cffffd100Blocked from offering you stories:|r\n|cfff5e6c8" .. table.concat(list, ", ") .. "|r",
            "Unblock all", function() ns.ClearShareBlocks() UI.SetStatus("Nobody is blocked now.", "good") end, "Close", nil)
    end)
    local wipeBtn = UI.CreateSleekButton(btns, 120, 24, "Delete All Data", "danger")
    wipeBtn.tipTitle = "|cffff6b6bDelete all RP Chronicler data|r"
    wipeBtn.tipText = "Click twice. Deletes every recording, story, companion and setting, then reloads the UI (/rp wipe)."
    wipeBtn:SetScript("OnClick", function(self)
        if not self.armedAt or GetTime() - self.armedAt > 4 then
            self.armedAt = GetTime()
            self:SetText("|cffff6b6bSure?|r")
            return
        end
        self.armedAt = nil
        ns.WipeAllData()
    end)
    O.refresh.PRIVACY = function()
        ns.EnsureDB()
        -- the disclaimer wraps to the page width, so place the rest under it
        local h = math.floor((text:GetStringHeight() or 120) + 0.5)
        capLabel:ClearAllPoints()
        capLabel:SetPoint("TOPLEFT", 0, -26 - h)
        capHolder:ClearAllPoints()
        capHolder:SetPoint("TOPLEFT", 0, -42 - h)
        local gridBottom = 42 + h + math.ceil(#ns.CAPTURE_TYPES / 2) * 18 + 10
        privHolder:ClearAllPoints()
        privHolder:SetPoint("TOPLEFT", 0, -gridBottom)
        privHolder:SetWidth(math.max(250, math.floor(p:GetWidth() or 0)))
        privRows()
        btns:ClearAllPoints()
        btns:SetPoint("TOPLEFT", 0, -(gridBottom + 78))
        refreshGrid()
        wipeBtn.armedAt = nil
        wipeBtn:SetText("Delete All Data")
        -- 0.6.3: the three buttons flow and wrap with the page width
        local w = math.max(200, math.floor(p:GetWidth() or 0))
        btns:SetWidth(w)
        btns:SetHeight(UI.FlowRow(btns, { setupBtn, reportBtn, blockBtn, wipeBtn }, nil, { width = w, rowH = 24, gap = 6 }))
    end
end

UI.SetSectionOnShow("OPTIONS", function()
    UI.EnsureOptions()
    UI.ShowOptionsPage(RPChroniclerDB.optionsPage)
end)

UI.AddReflow(function()
    if view:IsShown() then UI.RefreshOptionsPage() end
end)
