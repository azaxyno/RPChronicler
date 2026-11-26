local ADDON_NAME, ns = ...

-- =========================================================
-- RP Chronicler window shell (0.3.0)
-- The window is split into sections picked from a left rail:
--   Copy | Companions | Adventures, plus Options behind the gear.
-- Each section lives in its own UI_*.lua file. Shared pieces travel on
-- ns.UI so no single file gets near Lua 5.1's 200-local limit.
-- Load order: UI_Shell -> UI_Copy -> UI_Companions -> UI_Adventures
--             -> UI_Options -> UI_Commands
-- =========================================================
ns.UI = ns.UI or {}
local UI = ns.UI

UI.SOLID_TEX = "Interface\\Buttons\\WHITE8x8"
UI.BACKDROP = BackdropTemplateMixin and "BackdropTemplate" or nil

UI.ICONS = {
    COPY       = "Interface\\Icons\\INV_Scroll_03",
    PLAYERS    = "Interface\\Icons\\Spell_Holy_PrayerOfFortitude",
    ADVENTURES = "Interface\\Icons\\INV_Misc_Map_01",
    OPTIONS    = "Interface\\Icons\\INV_Misc_Gear_01",
    STORY      = "Interface\\Icons\\INV_Misc_Book_09",
    MARK       = "Interface\\Icons\\INV_Misc_Note_01",
    DOT        = "Interface\\CHARACTERFRAME\\TempPortraitAlphaMask",
}

-- 0.6.1: every setting and its default lives in ns.SETTINGS (Core.lua);
-- this only makes sure the saved data is ready
function UI.EnsureOptions()
    ns.EnsureDB()
    if type(RPChroniclerDB.optionsPage) ~= "string" then RPChroniclerDB.optionsPage = "GENERAL" end
end

-- =========================================================
-- Dark-glass theme helpers
-- =========================================================
function UI.ApplyDarkGlass(frame, bgR, bgG, bgB, bgA, brR, brG, brB, brA)
    if not frame or not frame.SetBackdrop then return end
    frame:SetBackdrop({
        bgFile = UI.SOLID_TEX,
        edgeFile = UI.SOLID_TEX,
        tile = false,
        edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 },
    })
    frame:SetBackdropColor(bgR or 0.06, bgG or 0.07, bgB or 0.10, bgA or 0.94)
    frame:SetBackdropBorderColor(brR or 0.72, brG or 0.58, brB or 0.28, brA or 0.45)
end

function UI.ApplyPanelLook(frame)
    UI.ApplyDarkGlass(frame, 0.07, 0.09, 0.12, 0.90, 0.24, 0.28, 0.36, 0.80)
end

function UI.ApplyStoryTomeLook(frame)
    UI.ApplyDarkGlass(frame, 0.09, 0.07, 0.05, 0.98, 0.86, 0.68, 0.30, 0.85)
end

function UI.Label(parent, text, template)
    local fs = parent:CreateFontString(nil, "OVERLAY", template or "GameFontNormalSmall")
    fs:SetJustifyH("LEFT")
    fs:SetText(text or "")
    return fs
end

function UI.Tooltip(owner, title, ...)
    if not GameTooltip then return end
    GameTooltip:SetOwner(owner, "ANCHOR_TOPLEFT")
    GameTooltip:SetText(title or "", 1, 1, 1)
    for i = 1, select("#", ...) do
        GameTooltip:AddLine((select(i, ...)), 0.82, 0.82, 0.82, true)
    end
    GameTooltip:Show()
end

function UI.HideTooltip()
    if GameTooltip then GameTooltip:Hide() end
end

function UI.CreateSleekButton(parent, width, height, text, accentStyle)
    local btn = CreateFrame("Button", nil, parent, UI.BACKDROP)
    if width and height then btn:SetSize(width, height) end

    btn.accentStyle = accentStyle
    btn.isLocked = false
    btn.isDisabled = false

    local function ApplyNormalLook()
        if btn.isDisabled then
            UI.ApplyDarkGlass(btn, 0.08, 0.09, 0.11, 0.70, 0.22, 0.24, 0.28, 0.50)
            btn.label:SetTextColor(0.45, 0.48, 0.52)
        elseif btn.isLocked then
            UI.ApplyDarkGlass(btn, 0.22, 0.18, 0.09, 0.96, 0.90, 0.73, 0.32, 0.95)
            btn.label:SetTextColor(1.0, 0.86, 0.35)
        elseif btn.accentStyle == "gold" then
            UI.ApplyDarkGlass(btn, 0.18, 0.15, 0.09, 0.94, 0.82, 0.65, 0.30, 0.85)
            btn.label:SetTextColor(0.98, 0.85, 0.40)
        elseif btn.accentStyle == "tool" then
            UI.ApplyDarkGlass(btn, 0.10, 0.14, 0.20, 0.94, 0.36, 0.52, 0.74, 0.70)
            btn.label:SetTextColor(0.76, 0.88, 1.0)
        elseif btn.accentStyle == "danger" then
            UI.ApplyDarkGlass(btn, 0.18, 0.08, 0.09, 0.90, 0.65, 0.24, 0.26, 0.70)
            btn.label:SetTextColor(1.0, 0.55, 0.55)
        elseif btn.accentStyle == "good" then
            UI.ApplyDarkGlass(btn, 0.08, 0.17, 0.10, 0.92, 0.30, 0.66, 0.36, 0.80)
            btn.label:SetTextColor(0.55, 0.92, 0.58)
        elseif btn.accentStyle == "rail" then
            UI.ApplyDarkGlass(btn, 0.07, 0.08, 0.11, 0.0, 0.28, 0.32, 0.40, 0.0)
            btn.label:SetTextColor(0.80, 0.84, 0.90)
        else
            UI.ApplyDarkGlass(btn, 0.11, 0.13, 0.17, 0.92, 0.28, 0.32, 0.40, 0.80)
            btn.label:SetTextColor(0.90, 0.92, 0.95)
        end
        if btn.icon then btn.icon:SetDesaturated(btn.isDisabled and true or false) end
    end
    btn.ApplyNormalLook = ApplyNormalLook

    btn.label = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    btn.label:SetPoint("LEFT", 5, 0)
    btn.label:SetPoint("RIGHT", -5, 0)
    btn.label:SetJustifyH("CENTER")
    btn.label:SetWordWrap(false)

    function btn:SetText(str) self.label:SetText(str or "") end
    function btn:GetText() return self.label:GetText() end

    -- Small icon on the left of the label
    function btn:SetIcon(texture, size)
        if not self.icon then
            self.icon = self:CreateTexture(nil, "ARTWORK")
            self.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        end
        local s = size or (self:GetHeight() - 6)
        self.icon:SetSize(s, s)
        self.icon:ClearAllPoints()
        self.icon:SetPoint("LEFT", 4, 0)
        self.icon:SetTexture(texture)
        self.label:ClearAllPoints()
        self.label:SetPoint("LEFT", self.icon, "RIGHT", 4, 0)
        self.label:SetPoint("RIGHT", -5, 0)
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
        -- 0.6.4: guarded, so a frame without a backdrop that borrows this
        -- handler can't raise an error
        if self.SetBackdropBorderColor then self:SetBackdropBorderColor(0.92, 0.76, 0.35, 0.95) end
        if not self.isLocked and self.SetBackdropColor then
            if self.accentStyle == "tool" then
                self:SetBackdropColor(0.15, 0.21, 0.30, 0.98)
            else
                self:SetBackdropColor(0.16, 0.19, 0.25, 0.96)
            end
        end
        if self.tipTitle then UI.Tooltip(self, self.tipTitle, self.tipText) end
    end)

    btn:SetScript("OnLeave", function()
        ApplyNormalLook()
        UI.HideTooltip()
    end)

    ApplyNormalLook()
    if text then btn:SetText(text) end
    return btn
end

-- =========================================================
-- Responsive rows (0.6.3): one helper lays out every row of buttons.
-- Each button is sized to its text (font and UI scale included). When a
-- row runs out of room its buttons switch to their short labels, then
-- the row wraps onto more lines, so buttons never overlap or clip at any
-- window or font size. Views call it from their refresh and on resize,
-- and anchor what sits below the row to the height it returns.
-- =========================================================
do
    local function TextWidth(fs)
        local w = fs.GetUnboundedStringWidth and fs:GetUnboundedStringWidth() or fs:GetStringWidth()
        return tonumber(w) or 0
    end

    -- Full and (optional) short label for a button in a flowing row
    function UI.SetButtonLabels(btn, full, short)
        btn.fullText, btn.shortText = full, short
        btn:SetText(btn.useShort and short or full)
    end

    -- The width a button needs for its current label (and icon)
    function UI.ButtonWidth(btn)
        local w = TextWidth(btn.label) + 16 + (btn.extraW or 0)
        if btn.icon and btn.icon:IsShown() then w = w + (btn.icon:GetWidth() or 0) + 4 end
        return math.max(btn.minW or 28, math.ceil(w))
    end

    local function Labels(list, short)
        for _, b in ipairs(list) do
            if b.fullText then
                b.useShort = short and b.shortText and true or false
                b:SetText(b.useShort and b.shortText or b.fullText)
            end
        end
    end

    local function Shown(list)
        local out = {}
        for _, b in ipairs(list or {}) do
            if b and b:IsShown() then table.insert(out, b) end
        end
        return out
    end

    local function Sum(list, gap)
        local t = 0
        for i, b in ipairs(list) do t = t + UI.ButtonWidth(b) + (i > 1 and gap or 0) end
        return t
    end

    -- parent: the frame the buttons sit in; left: buttons from the left
    -- edge; right: buttons kept together on the right edge. opts: x, y
    -- (offsets from parent's TOPLEFT), width (default: parent's), gap,
    -- rowH. Returns the height used.
    function UI.FlowRow(parent, left, right, opts)
        opts = opts or {}
        local gap, rowH = opts.gap or 4, opts.rowH or 22
        local x0, y0 = opts.x or 0, opts.y or 0
        local W = math.floor(opts.width or (parent:GetWidth() or 0))
        left, right = Shown(left), Shown(right)
        if W < 40 then W = 400 end
        Labels(left, false)
        Labels(right, false)
        local need = Sum(left, gap) + Sum(right, gap) + ((#left > 0 and #right > 0) and 12 or 0)
        if need > W then
            Labels(left, true)
            Labels(right, true)
        end
        local x, row = 0, 0
        local function Put(b, px, w)
            b:ClearAllPoints()
            b:SetPoint("TOPLEFT", parent, "TOPLEFT", x0 + px, -(y0 + row * (rowH + gap)))
            b:SetWidth(w)
            b:SetHeight(rowH)
        end
        for _, b in ipairs(left) do
            local w = math.min(UI.ButtonWidth(b), W)
            if x > 0 and x + w > W then row, x = row + 1, 0 end
            Put(b, x, w)
            x = x + w + gap
        end
        if #right > 0 then
            local rw = Sum(right, gap)
            if x > 0 and x + 8 + rw > W then row, x = row + 1, 0 end
            if rw <= W then
                local px = W - rw
                for _, b in ipairs(right) do
                    local w = UI.ButtonWidth(b)
                    Put(b, px, w)
                    px = px + w + gap
                end
            else
                x = 0
                for _, b in ipairs(right) do
                    local w = math.min(UI.ButtonWidth(b), W)
                    if x > 0 and x + w > W then row, x = row + 1, 0 end
                    Put(b, x, w)
                    x = x + w + gap
                end
            end
        end
        if #left == 0 and #right == 0 then return 0 end
        return (row + 1) * rowH + row * gap
    end
end

-- A two-state toggle button: label "Name: ON" / "Name: OFF"
function UI.SetToggleLook(btn, isOn, onText, offText)
    btn:SetText(isOn and ("|cff5cb85c" .. onText .. "|r") or ("|cff9aa5b4" .. offText .. "|r"))
    if isOn then btn:LockHighlight() else btn:UnlockHighlight() end
end

-- =========================================================
-- Main window
-- =========================================================
local RAIL_W = 92   -- 0.6.1: wide enough for "Companions" in full
UI.DEFAULT_W, UI.DEFAULT_H = 680, 490
UI.MIN_W, UI.MIN_H = 640, 460   -- 0.6.3: rows wrap, so nothing overlaps at this size

local copyFrame = CreateFrame("Frame", "RPChroniclerFrame", UIParent, UI.BACKDROP)
UI.frame = copyFrame
copyFrame:SetSize(UI.DEFAULT_W, UI.DEFAULT_H)
copyFrame:SetPoint("CENTER")
copyFrame:SetFrameStrata("DIALOG")
-- 0.6.4: always drawn over the quest tracker and other HUD frames, and
-- raised when clicked (the tracker showed through the Story Book cover)
copyFrame:SetFrameLevel(40)
if copyFrame.SetToplevel then copyFrame:SetToplevel(true) end
copyFrame:SetMovable(true)
copyFrame:EnableMouse(true)
copyFrame:RegisterForDrag("LeftButton")
copyFrame:Hide()
UI.ApplyDarkGlass(copyFrame, 0.05, 0.06, 0.08, 1.0, 0.78, 0.62, 0.28, 0.60)
-- ESC closes the window (the game hides frames listed in UISpecialFrames)
if type(UISpecialFrames) == "table" then
    table.insert(UISpecialFrames, "RPChroniclerFrame")
end

-- Pin the window by its top-left corner (also what stops the resize jump)
function UI.PinTopLeft()
    local left, top = copyFrame:GetLeft(), copyFrame:GetTop()
    if left and top then
        copyFrame:ClearAllPoints()
        copyFrame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
    end
    return left, top
end

function UI.SavePosition()
    local left, top = UI.PinTopLeft()
    if RPChroniclerDB and left and top then
        RPChroniclerDB.frameX, RPChroniclerDB.frameY = math.floor(left + 0.5), math.floor(top + 0.5)
    end
end

-- 0.5.0 (resize jumps): RP Chronicler saves the place itself, so the client's own
-- layout cache must not restore an older one on top of it
if copyFrame.SetDontSavePosition then pcall(copyFrame.SetDontSavePosition, copyFrame, true) end

copyFrame:SetScript("OnDragStart", function(self)
    if UI.sizing then return end
    self:StartMoving()
    UI.moving = true
end)
copyFrame:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    UI.moving = false
    if self.SetUserPlaced then pcall(self.SetUserPlaced, self, false) end
    UI.SavePosition()
end)

-- Header strip: title, version, gear, close
do
    local headerBar = CreateFrame("Frame", nil, copyFrame, UI.BACKDROP)
    headerBar:SetHeight(28)
    headerBar:SetPoint("TOPLEFT", 1, -1)
    headerBar:SetPoint("TOPRIGHT", -1, -1)
    UI.ApplyDarkGlass(headerBar, 0.08, 0.10, 0.14, 0.98, 0.78, 0.62, 0.28, 0.30)
    UI.header = headerBar

    UI.titleText = headerBar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    UI.titleText:SetPoint("LEFT", 12, 0)
    UI.titleText:SetText("|cffffd100RP Chronicler|r")

    local closeBtn = UI.CreateSleekButton(headerBar, 22, 20, "x", "danger")
    closeBtn:SetPoint("RIGHT", -5, 0)
    closeBtn:SetScript("OnClick", function() copyFrame:Hide() end)

    local gearBtn = UI.CreateSleekButton(headerBar, 26, 20, "")
    gearBtn:SetPoint("RIGHT", closeBtn, "LEFT", -6, 0)
    gearBtn.icon = gearBtn:CreateTexture(nil, "ARTWORK")
    gearBtn.icon:SetSize(16, 16)
    gearBtn.icon:SetPoint("CENTER", 0, 0)
    gearBtn.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    gearBtn.icon:SetTexture(UI.ICONS.OPTIONS)
    gearBtn.tipTitle = "|cffffd100Options|r"
    gearBtn.tipText = "Settings, keybinds, slice tabs and AI setup."
    gearBtn:SetScript("OnClick", function()
        if ns.state.section == "OPTIONS" then
            UI.ShowSection(UI.lastNonOptions or "COPY")
        else
            UI.ShowSection("OPTIONS")
        end
    end)
    UI.gearBtn = gearBtn

    local verBadge = headerBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    verBadge:SetPoint("RIGHT", gearBtn, "LEFT", -8, 0)
    verBadge:SetText("|cff8f9ba8v" .. (ns.VERSION or "0.6.4") .. "|r")
end

-- Left rail
do
    local rail = CreateFrame("Frame", nil, copyFrame, UI.BACKDROP)
    rail:SetWidth(RAIL_W)
    rail:SetPoint("TOPLEFT", 1, -29)
    rail:SetPoint("BOTTOMLEFT", 1, 1)
    UI.ApplyDarkGlass(rail, 0.07, 0.08, 0.11, 0.96, 0.78, 0.62, 0.28, 0.22)
    UI.rail = rail
    UI.railButtons = {}
end

UI.railOrder = {}

-- Stacks the shown rail buttons from the top (0.6.1: the Copy button is
-- hidden while RP Copy is off)
function UI.LayoutRail()
    local idx = 0
    for _, key in ipairs(UI.railOrder) do
        local btn = UI.railButtons[key]
        if btn.hiddenByFeature then
            btn:Hide()
        else
            btn:ClearAllPoints()
            btn:SetPoint("TOP", 0, -10 - idx * 58)
            btn:Show()
            idx = idx + 1
        end
    end
end

function UI.AddRailButton(key, label, icon, tip)
    local btn = UI.CreateSleekButton(UI.rail, RAIL_W - 10, 52, label, "rail")
    btn.label:ClearAllPoints()
    btn.label:SetPoint("BOTTOMLEFT", 1, 6)
    btn.label:SetPoint("BOTTOMRIGHT", -1, 6)
    btn.label:SetWordWrap(false)
    btn.icon = btn:CreateTexture(nil, "ARTWORK")
    btn.icon:SetSize(24, 24)
    btn.icon:SetPoint("TOP", 0, -6)
    btn.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    btn.icon:SetTexture(icon)
    btn.tipTitle = "|cffffd100" .. label .. "|r"
    btn.tipText = tip
    btn:SetScript("OnClick", function() UI.ShowSection(key) end)
    UI.railButtons[key] = btn
    table.insert(UI.railOrder, key)
    UI.LayoutRail()
    return btn
end

-- Recording chip at the bottom of the rail: visible from every section
do
    local chip = CreateFrame("Button", nil, UI.rail, UI.BACKDROP)
    chip:SetSize(RAIL_W - 14, 30)
    chip:SetPoint("BOTTOM", 0, 10)
    UI.ApplyDarkGlass(chip, 0.16, 0.06, 0.06, 0.92, 1, 0.32, 0.32, 0.85)
    chip.dot = chip:CreateTexture(nil, "OVERLAY")
    chip.dot:SetSize(8, 8)
    chip.dot:SetPoint("LEFT", 8, 0)
    chip.dot:SetTexture(UI.ICONS.DOT)
    chip.text = chip:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    chip.text:SetPoint("LEFT", chip.dot, "RIGHT", 5, 0)
    chip.text:SetPoint("RIGHT", -4, 0)
    chip.text:SetJustifyH("LEFT")
    chip:Hide()
    chip:SetScript("OnClick", function() UI.ShowSection("ADVENTURES") end)
    chip:SetScript("OnEnter", function(self)
        local run = ns.GetActiveAdventure()
        UI.Tooltip(self, "|cffffd100" .. ((run and run.title) or "Adventure") .. "|r",
            (run and run.paused) and "Recording paused." or "Recording this run.",
            "Click to open Adventures.")
    end)
    chip:SetScript("OnLeave", UI.HideTooltip)

    local acc = 1
    UI.rail:SetScript("OnUpdate", function(_, elapsed)
        acc = acc + elapsed
        if acc < 0.5 then return end
        acc = 0
        local run = ns.GetActiveAdventure()
        if not run then chip:Hide() return end
        local mins = math.floor(math.max(0, time() - (run.startTime or time())) / 60)
        if run.paused then
            chip.dot:SetVertexColor(1, 0.72, 0.30, 1)
            chip.text:SetText("|cffffb74dPAUSED|r")
            chip:SetBackdropBorderColor(1, 0.72, 0.30, 0.85)
        else
            chip.dot:SetVertexColor(1, 0.15, 0.15, 1)
            chip.text:SetText(string.format("|cffff6b6bREC|r |cffd8dee9%dm|r", mins))
            chip:SetBackdropBorderColor(1, 0.32, 0.32, 0.85)
        end
        chip:Show()
    end)
end

-- Content area (sections fill it) and the status line under it
do
    local content = CreateFrame("Frame", nil, copyFrame)
    content:SetPoint("TOPLEFT", UI.rail, "TOPRIGHT", 10, -8)
    content:SetPoint("BOTTOMRIGHT", copyFrame, "BOTTOMRIGHT", -12, 26)
    UI.content = content

    local status = copyFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    status:SetPoint("BOTTOMLEFT", UI.rail, "BOTTOMRIGHT", 10, 8)
    status:SetPoint("RIGHT", copyFrame, "RIGHT", -24, 0)
    status:SetJustifyH("LEFT")
    status:SetWordWrap(false)
    UI.statusText = status
end

-- Status line: messages show for a while, then the section's hint returns
function UI.SetStatus(msg, kind)
    local color = (kind == "error" and "ff6b6b") or (kind == "good" and "5cb85c") or "d8dee9"
    UI.statusText:SetText("|cff" .. color .. (msg or "") .. "|r")
    UI.statusUntil = GetTime() + 8
end

function UI.SetHint(msg)
    UI.hintText = msg or ""
    if not UI.statusUntil or GetTime() > UI.statusUntil then
        UI.statusText:SetText("|cff8f9ba8" .. UI.hintText .. "|r")
    end
end

-- =========================================================
-- Sections
-- =========================================================
UI.sections = {}

function UI.NewSection(key, title, hint, onShow)
    local f = CreateFrame("Frame", nil, UI.content)
    f:SetAllPoints(UI.content)
    f:Hide()
    UI.sections[key] = { frame = f, title = title, hint = hint, onShow = onShow }
    return f
end

function UI.SetSectionOnShow(key, fn)
    if UI.sections[key] then UI.sections[key].onShow = fn end
end

function UI.ShowSection(key)
    if key == "COPY" and not ns.RpCopyOn() then key = "ADVENTURES" end
    local sec = UI.sections[key]
    if not sec then return end
    ns.state.section = key
    if key ~= "OPTIONS" then UI.lastNonOptions = key end
    for k, s in pairs(UI.sections) do
        if k ~= key then s.frame:Hide() end
    end
    local changed = not sec.frame:IsShown()
    sec.frame:Show()
    -- 0.6.3: a short fade-in when you switch sections (guarded)
    if changed and UIFrameFadeIn then pcall(UIFrameFadeIn, sec.frame, 0.2, 0, 1) end
    for k, b in pairs(UI.railButtons) do
        if k == key then b:LockHighlight() else b:UnlockHighlight() end
    end
    if key == "OPTIONS" then UI.gearBtn:LockHighlight() else UI.gearBtn:UnlockHighlight() end
    UI.titleText:SetText("|cffffd100RP Chronicler|r |cff8f9ba8-|r |cffd8dee9" .. (sec.title or "") .. "|r")
    UI.statusUntil = nil
    UI.SetHint(sec.hint)
    if sec.onShow then sec.onShow() end
end

-- Close shortly after a copy so the game's own Ctrl+C finishes first
copyFrame:SetScript("OnUpdate", function(self, elapsed)
    if self.closeDelay then
        self.closeDelay = self.closeDelay - elapsed
        if self.closeDelay <= 0 then
            self.closeDelay = nil
            self:Hide()
        end
    end
    if UI.statusUntil and GetTime() > UI.statusUntil then
        UI.statusUntil = nil
        UI.statusText:SetText("|cff8f9ba8" .. (UI.hintText or "") .. "|r")
    end
end)

-- =========================================================
-- Resizable, remembered window
-- Drag the corner grip to resize; right-click it to reset size and place.
-- copyFrame is a plain (non-secure) frame, so this is safe in combat.
-- =========================================================
UI.reflowHooks = {}
function UI.AddReflow(fn) table.insert(UI.reflowHooks, fn) end

do
    local function MaxSize()
        local w = (UIParent and UIParent:GetWidth()) or 1600
        local h = (UIParent and UIParent:GetHeight()) or 1000
        return math.max(UI.MIN_W, math.floor(w - 40)), math.max(UI.MIN_H, math.floor(h - 40))
    end

    local function ApplyBounds()
        local mw, mh = MaxSize()
        if copyFrame.SetResizeBounds then
            copyFrame:SetResizeBounds(UI.MIN_W, UI.MIN_H, mw, mh)
        end
    end

    copyFrame:SetResizable(true)
    ApplyBounds()
    if copyFrame.SetClampedToScreen then copyFrame:SetClampedToScreen(true) end

    local function ReflowNow()
        for _, fn in ipairs(UI.reflowHooks) do pcall(fn) end
    end
    -- 0.5.0: OnSizeChanged fires for every pixel while you drag; lay the
    -- window out once per frame (and once more when the drag ends)
    local reflowFrame = CreateFrame("Frame")
    reflowFrame:Hide()
    reflowFrame:SetScript("OnUpdate", function(self)
        self:Hide()
        ReflowNow()
    end)
    local function Reflow() reflowFrame:Show() end
    UI.Reflow = ReflowNow

    local function ClampSize(w, h)
        local mw, mh = MaxSize()
        w = math.min(math.max(tonumber(w) or UI.DEFAULT_W, UI.MIN_W), mw)
        h = math.min(math.max(tonumber(h) or UI.DEFAULT_H, UI.MIN_H), mh)
        return math.floor(w), math.floor(h)
    end

    local function SaveSize()
        if not RPChroniclerDB then return end
        RPChroniclerDB.frameW, RPChroniclerDB.frameH = ClampSize(copyFrame:GetWidth(), copyFrame:GetHeight())
    end

    -- A saved place that is off screen now (another resolution or UI
    -- scale) is pulled back so the whole title bar can be reached
    local function ClampPlace(x, y, w, h)
        local sw = (UIParent and UIParent:GetWidth()) or 1600
        local sh = (UIParent and UIParent:GetHeight()) or 1000
        x = math.min(math.max(tonumber(x) or 0, 0), math.max(0, sw - w))
        y = math.min(math.max(tonumber(y) or sh, h), sh)
        return math.floor(x), math.floor(y)
    end

    local function StopSizing()
        if not UI.sizing then return end
        UI.sizing = false
        if copyFrame.SetUserPlaced then pcall(copyFrame.SetUserPlaced, copyFrame, false) end
        SaveSize()
        UI.SavePosition()
        ReflowNow()
    end
    UI.StopSizing = StopSizing

    copyFrame:HookScript("OnSizeChanged", Reflow)
    copyFrame:HookScript("OnHide", function()
        StopSizing()
        if UI.moving then
            copyFrame:StopMovingOrSizing()
            UI.moving = false
            UI.SavePosition()
        end
    end)
    copyFrame:HookScript("OnShow", function()
        ApplyBounds()
        local w, h = copyFrame:GetWidth(), copyFrame:GetHeight()
        if RPChroniclerDB and RPChroniclerDB.frameW and RPChroniclerDB.frameH then
            w, h = ClampSize(RPChroniclerDB.frameW, RPChroniclerDB.frameH)
            copyFrame:SetSize(w, h)
        end
        if RPChroniclerDB and RPChroniclerDB.frameX and RPChroniclerDB.frameY then
            local x, y = ClampPlace(RPChroniclerDB.frameX, RPChroniclerDB.frameY, w, h)
            RPChroniclerDB.frameX, RPChroniclerDB.frameY = x, y
            copyFrame:ClearAllPoints()
            copyFrame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x, y)
        end
        ReflowNow()
    end)

    function UI.ResetWindow()
        copyFrame:SetSize(UI.DEFAULT_W, UI.DEFAULT_H)
        copyFrame:ClearAllPoints()
        copyFrame:SetPoint("CENTER")
        if RPChroniclerDB then
            RPChroniclerDB.frameW, RPChroniclerDB.frameH = nil, nil
            RPChroniclerDB.frameX, RPChroniclerDB.frameY = nil, nil
        end
        ReflowNow()
        UI.SetStatus("Window size and position reset.", "good")
    end

    local grip = CreateFrame("Button", "RPChroniclerResizeGrip", copyFrame)
    grip:SetSize(14, 14)
    grip:SetPoint("BOTTOMRIGHT", -2, 2)
    grip:SetFrameLevel(copyFrame:GetFrameLevel() + 20)
    grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    grip:RegisterForClicks("RightButtonUp")
    -- 0.6.1: the window follows the cursor itself instead of the engine's
    -- StartSizing, which jumped (to the max size, or by the clamp offset)
    -- on the first frame. The top-left stays pinned; only the bottom-right
    -- corner moves, by exactly as far as the cursor moved.
    local drag
    local function Cursor()
        local x, y = GetCursorPosition()
        local scale = copyFrame:GetEffectiveScale() or 1
        return (x or 0) / scale, (y or 0) / scale
    end
    grip:SetScript("OnMouseDown", function(_, button)
        if button ~= "LeftButton" or UI.moving then return end
        UI.PinTopLeft()
        local cx, cy = Cursor()
        drag = { x = cx, y = cy, w = copyFrame:GetWidth(), h = copyFrame:GetHeight() }
        UI.sizing = true
    end)
    grip:SetScript("OnMouseUp", function(_, button)
        if button == "LeftButton" then drag = nil; StopSizing() end
    end)
    grip:SetScript("OnUpdate", function()
        if not UI.sizing or not drag then return end
        -- A release the grip never saw (mouse let go over another frame or
        -- outside the game) must not leave the window stuck to the cursor
        if IsMouseButtonDown and not IsMouseButtonDown("LeftButton") then
            drag = nil
            StopSizing()
            return
        end
        local cx, cy = Cursor()
        local w, h = ClampSize(drag.w + (cx - drag.x), drag.h + (drag.y - cy))
        if math.abs(w - copyFrame:GetWidth()) >= 1 or math.abs(h - copyFrame:GetHeight()) >= 1 then
            copyFrame:SetSize(w, h)
        end
    end)
    grip:SetScript("OnClick", function() UI.ResetWindow() end)
    grip:SetScript("OnEnter", function(self)
        UI.Tooltip(self, "|cffffd100Resize|r", "Drag to resize. Right-click to reset size and position.")
    end)
    grip:SetScript("OnLeave", UI.HideTooltip)
end

-- =========================================================
-- Toast banner (shown even when the window is closed)
-- =========================================================
do
    local toast = CreateFrame("Frame", "RPChroniclerToastFrame", UIParent, UI.BACKDROP)
    toast:SetSize(330, 30)
    toast:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 140)
    toast:SetFrameStrata("FULLSCREEN_DIALOG")
    toast:Hide()
    UI.ApplyDarkGlass(toast, 0.05, 0.07, 0.10, 0.96, 0.36, 0.72, 0.36, 0.90)

    local toastText = toast:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    toastText:SetPoint("CENTER", 0, 0)

    toast:SetScript("OnUpdate", function(self, elapsed)
        if self.hideIn then
            self.hideIn = self.hideIn - elapsed
            if self.hideIn <= 0 then
                self.hideIn = nil
                self:Hide()
            end
        end
    end)

    function UI.ShowToast(msg, duration, borderR, borderG, borderB)
        toastText:SetText(msg or "")
        toast:SetWidth(math.max(330, (toastText:GetStringWidth() or 300) + 30))
        toast:SetBackdropBorderColor(borderR or 0.36, borderG or 0.72, borderB or 0.36, 0.92)
        toast.hideIn = duration or 2.0
        toast:Show()
    end
end

-- =========================================================
-- Prompt (0.4.0): a small question box with up to three buttons, used for
-- "Start recording?" and the interrupted-run question. Never protected.
-- =========================================================
do
    local p = CreateFrame("Frame", "RPChroniclerPromptFrame", UIParent, UI.BACKDROP)
    p:SetSize(380, 112)
    p:SetPoint("TOP", UIParent, "TOP", 0, -170)
    p:SetFrameStrata("FULLSCREEN_DIALOG")
    p:SetMovable(true)
    p:EnableMouse(true)
    p:RegisterForDrag("LeftButton")
    p:SetScript("OnDragStart", p.StartMoving)
    p:SetScript("OnDragStop", p.StopMovingOrSizing)
    p:Hide()
    UI.ApplyDarkGlass(p, 0.05, 0.07, 0.10, 0.97, 0.82, 0.65, 0.30, 0.90)

    local text = p:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    text:SetPoint("TOPLEFT", 14, -14)
    text:SetPoint("TOPRIGHT", -14, -14)
    text:SetJustifyH("LEFT")
    text:SetJustifyV("TOP")
    text:SetSpacing(3)

    local btns = {}
    for i = 1, 3 do
        local b = UI.CreateSleekButton(p, 110, 24, "", i == 1 and "gold" or nil)
        if i == 1 then b:SetPoint("BOTTOMLEFT", 14, 12) else b:SetPoint("LEFT", btns[i - 1], "RIGHT", 6, 0) end
        b:SetScript("OnClick", function(self)
            p:Hide()
            if self.fn then pcall(self.fn) end
        end)
        btns[i] = b
    end

    -- UI.ShowPrompt(text, label1, fn1, label2, fn2, label3, fn3)
    function UI.ShowPrompt(msg, ...)
        text:SetText(msg or "")
        local args = { ... }
        for i = 1, 3 do
            local label, fn = args[i * 2 - 1], args[i * 2]
            if label then
                btns[i]:SetText(label)
                btns[i]:SetWidth(math.max(90, (btns[i].label:GetStringWidth() or 60) + 24))
                btns[i].fn = fn
                btns[i]:Show()
            else
                btns[i]:Hide()
            end
        end
        p:SetHeight(math.max(96, (text:GetStringHeight() or 30) + 60))
        p:Show()
    end
    UI.promptFrame = p
    -- 0.6.1: the recorder asks its questions through ns.Notify("prompt", ...)
    ns.Listen("prompt", UI.ShowPrompt)
end

-- =========================================================
-- Copy box (0.4.0): a read-only text box with Select All, for sharing a
-- story as plain text and for the /rp debug report
-- =========================================================
do
    local f = CreateFrame("Frame", "RPChroniclerCopyBoxFrame", UIParent, UI.BACKDROP)
    f:SetSize(560, 400)
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 20)
    f:SetFrameStrata("FULLSCREEN_DIALOG")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:Hide()
    UI.ApplyDarkGlass(f, 0.05, 0.06, 0.08, 0.97, 0.78, 0.62, 0.28, 0.80)
    if type(UISpecialFrames) == "table" then table.insert(UISpecialFrames, "RPChroniclerCopyBoxFrame") end

    local title = UI.Label(f, "", "GameFontNormal")
    title:SetPoint("TOPLEFT", 14, -12)
    local sub = UI.Label(f, "", "GameFontHighlightSmall")
    sub:SetPoint("TOPLEFT", 14, -28)
    sub:SetPoint("RIGHT", -40, 0)

    local closeX = UI.CreateSleekButton(f, 22, 20, "x", "danger")
    closeX:SetPoint("TOPRIGHT", -8, -8)
    closeX:SetScript("OnClick", function() f:Hide() end)

    local boxBg = CreateFrame("Frame", nil, f, UI.BACKDROP)
    boxBg:SetPoint("TOPLEFT", 14, -48)
    boxBg:SetPoint("BOTTOMRIGHT", -14, 42)
    UI.ApplyPanelLook(boxBg)

    local scroll = CreateFrame("ScrollFrame", "RPChroniclerCopyBoxScroll", boxBg, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 8, -8)
    scroll:SetPoint("BOTTOMRIGHT", -28, 8)
    local eb = CreateFrame("EditBox", "RPChroniclerCopyBoxEditBox", scroll)
    eb:SetMultiLine(true)
    eb:SetMaxLetters(0)
    eb:SetFontObject(ChatFontNormal)
    eb:SetWidth(490)
    eb:SetHeight(300)
    eb:SetAutoFocus(false)
    eb:SetScript("OnEscapePressed", function() f:Hide() end)
    -- Read-only: typing puts the text back
    eb:SetScript("OnTextChanged", function(self, userInput)
        if userInput and f.text then self:SetText(f.text); self:HighlightText() end
        scroll:UpdateScrollChildRect()
    end)
    scroll:SetScrollChild(eb)
    -- 0.5.1: a quick-copy box closes itself once Ctrl+C has copied
    eb:SetScript("OnKeyDown", function(self, key)
        if f.autoClose and key == "C" and IsControlKeyDown() then
            self:HighlightText()
            ns.Debug("copy", "copy box Ctrl+C: len " .. #(self:GetText() or ""))
            UI.ShowToast("|cffffd100Copied|r |cff5cb85cto clipboard!|r", 1.8, 0.36, 0.72, 0.36)
            f.autoClose = false
            if C_Timer and C_Timer.After then C_Timer.After(0.25, function() f:Hide() end) else f:Hide() end
        end
    end)

    local selBtn = UI.CreateSleekButton(f, 110, 24, "Select All", "gold")
    selBtn:SetPoint("BOTTOMLEFT", 14, 11)
    selBtn:SetScript("OnClick", function()
        eb:SetFocus()
        eb:HighlightText()
    end)
    local hint = UI.Label(f, "|cff9aa5b4Then press Ctrl+C to copy.|r", "GameFontHighlightSmall")
    hint:SetPoint("LEFT", selBtn, "RIGHT", 8, 0)
    local closeBtn = UI.CreateSleekButton(f, 80, 24, "Close", "danger")
    closeBtn:SetPoint("BOTTOMRIGHT", -14, 11)
    closeBtn:SetScript("OnClick", function() f:Hide() end)

    function UI.ShowCopyBox(titleText, subText, body, autoClose)
        f.text = body or ""
        f.autoClose = autoClose and true or false
        title:SetText(titleText or "|cffffd100RP Chronicler|r")
        sub:SetText(subText or "")
        eb:SetText(f.text)
        f:Show()
        eb:SetFocus()
        eb:HighlightText()
        eb:SetCursorPosition(0)
        eb:HighlightText()
    end
end

-- =========================================================
-- One-line question (0.6.3): a small box with one text line, used for
-- a story note (/rp note) and the Ctrl+C instruction for the AI.
-- UI.AskLine{ title, sub, placeholder, okText, onAccept(text), onEscape() }
-- Enter accepts (an empty line too); Esc calls onEscape, or just closes.
-- 0.6.4: the box lays out top-down from its help text (a two-line help
-- text no longer runs under the input), and UI.AskLineCopy(title, text)
-- turns the same small box into a copy step: the text is selected in a
-- compact box, Ctrl+C copies it and the box closes by itself.
-- =========================================================
do
    local f = CreateFrame("Frame", "RPChroniclerAskLineFrame", UIParent, UI.BACKDROP)
    f:SetSize(440, 104)
    f:SetPoint("TOP", UIParent, "TOP", 0, -200)
    f:SetFrameStrata("FULLSCREEN_DIALOG")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:SetClampedToScreen(true)
    f:Hide()
    UI.ApplyDarkGlass(f, 0.05, 0.07, 0.10, 0.97, 0.82, 0.65, 0.30, 0.90)

    local title = UI.Label(f, "", "GameFontNormal")
    title:SetPoint("TOPLEFT", 14, -12)
    title:SetPoint("RIGHT", -36, 0)
    local sub = UI.Label(f, "", "GameFontHighlightSmall")
    sub:SetPoint("TOPLEFT", 14, -30)
    sub:SetPoint("RIGHT", -14, 0)
    sub:SetWordWrap(true)
    local closeX = UI.CreateSleekButton(f, 22, 20, "x", "danger")
    closeX:SetPoint("TOPRIGHT", -8, -8)

    local eb = CreateFrame("EditBox", "RPChroniclerAskLineBox", f, "InputBoxTemplate")
    eb:SetHeight(22)
    eb:SetPoint("TOPLEFT", sub, "BOTTOMLEFT", 6, -8)
    eb:SetPoint("RIGHT", f, "RIGHT", -16, 0)
    eb:SetAutoFocus(false)
    eb:SetMaxLetters(240)
    local hint = eb:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("LEFT", 2, 0)

    local okBtn = UI.CreateSleekButton(f, 90, 22, "OK", "gold")
    okBtn:SetPoint("BOTTOMLEFT", 14, 10)
    local keys = UI.Label(f, "", "GameFontHighlightSmall")
    keys:SetPoint("LEFT", okBtn, "RIGHT", 8, 0)

    -- The copy step: a compact read-only box with the text selected
    local copyBg = CreateFrame("Frame", nil, f, UI.BACKDROP)
    copyBg:SetPoint("TOPLEFT", sub, "BOTTOMLEFT", 0, -8)
    copyBg:SetPoint("RIGHT", f, "RIGHT", -14, 0)
    copyBg:SetHeight(64)
    UI.ApplyPanelLook(copyBg)
    copyBg:Hide()
    local copyScroll = CreateFrame("ScrollFrame", "RPChroniclerAskLineCopyScroll", copyBg, "UIPanelScrollFrameTemplate")
    copyScroll:SetPoint("TOPLEFT", 6, -6)
    copyScroll:SetPoint("BOTTOMRIGHT", -26, 6)
    local copyEb = CreateFrame("EditBox", "RPChroniclerAskLineCopyBox", copyScroll)
    copyEb:SetMultiLine(true)
    copyEb:SetMaxLetters(0)
    if copyEb.SetMaxBytes then pcall(copyEb.SetMaxBytes, copyEb, 0) end
    copyEb:SetFontObject(ChatFontSmall or ChatFontNormal)
    copyEb:SetWidth(380)
    copyEb:SetHeight(200)
    copyEb:SetAutoFocus(false)
    copyScroll:SetScrollChild(copyEb)

    local opts
    local copyText
    local function Close() f:Hide() end
    local function Accept()
        local o = opts
        local text = ((eb:GetText() or ""):gsub("||", "|")):match("^%s*(.-)%s*$")
        f:Hide()
        if o and o.onAccept then pcall(o.onAccept, text) end
    end
    local function Escape()
        local o = opts
        f:Hide()
        if o and o.onEscape then pcall(o.onEscape) end
    end
    copyEb:SetScript("OnEscapePressed", Close)
    copyEb:SetScript("OnTextChanged", function(self, userInput)
        -- read-only: typing puts the text back
        if userInput and copyText then self:SetText(copyText); self:HighlightText() end
        copyScroll:UpdateScrollChildRect()
    end)
    copyEb:SetScript("OnKeyDown", function(self, key)
        if key == "C" and IsControlKeyDown() and copyText then
            self:HighlightText()
            ns.Debug("copy", "instruction popup Ctrl+C: len " .. #(self:GetText() or ""))
            UI.ShowToast("|cffffd100Copied|r |cff5cb85cto clipboard!|r", 1.8, 0.36, 0.72, 0.36)
            copyText = nil
            if C_Timer and C_Timer.After then C_Timer.After(0.25, Close) else Close() end
        end
    end)
    copyEb:SetScript("OnMouseUp", function(self) self:HighlightText() end)

    -- Height from the help text down: title, help, box, buttons
    local function FitHeight(boxH)
        f:SetHeight(30 + math.ceil(sub:GetStringHeight() or 14) + 8 + boxH + 10 + 22 + 10)
    end
    eb:SetScript("OnEnterPressed", Accept)
    eb:SetScript("OnEscapePressed", Escape)
    eb:SetScript("OnTextChanged", function(self)
        if (self:GetText() or "") == "" then hint:Show() else hint:Hide() end
    end)
    okBtn:SetScript("OnClick", function()
        if copyBg:IsShown() then
            copyEb:SetFocus()
            copyEb:HighlightText()
        else
            Accept()
        end
    end)
    closeX:SetScript("OnClick", Close)
    f:SetScript("OnHide", function()
        eb:ClearFocus()
        copyEb:ClearFocus()
        copyText = nil
    end)

    function UI.AskLine(o)
        opts = o or {}
        title:SetText("|cffffd100" .. (opts.title or "RP Chronicler") .. "|r")
        sub:SetText("|cffb0bac5" .. (opts.sub or "") .. "|r")
        hint:SetText(opts.placeholder or "")
        okBtn:SetText(opts.okText or "OK")
        okBtn:SetWidth(UI.ButtonWidth(okBtn))
        keys:SetText("|cff8f9ba8" .. (opts.keys or "Enter: OK   Esc: cancel") .. "|r")
        eb:SetText("")
        hint:Show()
        copyBg:Hide()
        eb:Show()
        copyText = nil
        f:Show()
        FitHeight(22)
        eb:SetFocus()
    end

    function UI.AskLineCopy(titleText, body)
        opts = {}
        copyText = body or ""
        title:SetText(titleText or "|cffffd100RP Chronicler|r")
        sub:SetText("|cffb0bac5Selected. Press |cffffd100Ctrl+C|cffb0bac5 to copy, and this closes by itself.|r")
        okBtn:SetText("Select all")
        okBtn:SetWidth(UI.ButtonWidth(okBtn))
        keys:SetText("|cff8f9ba8Ctrl+C: copy   Esc: close|r")
        eb:ClearFocus()
        eb:Hide()
        copyBg:Show()
        copyEb:SetWidth(math.max(200, (copyScroll:GetWidth() or 380)))
        copyEb:SetText(copyText)
        f:Show()
        FitHeight(64)
        copyEb:SetFocus()
        copyEb:SetCursorPosition(0)
        copyEb:HighlightText()
    end
    UI.askLine = f
end

-- =========================================================
-- Opening and closing
-- =========================================================
-- The section the window opens on: Copy, or Adventures while RP Copy is off
function UI.DefaultSection()
    return ns.RpCopyOn() and "COPY" or "ADVENTURES"
end

function RPChronicler_Open(note, section)
    UI.EnsureOptions()
    UI.DisarmCtrlCopy()
    copyFrame.closeDelay = nil
    copyFrame.openedAt = GetTime()
    ns.state.activeNote = note or ""
    ns.state.isExpanded = false
    copyFrame:Show()
    if section == "COPY" and not ns.RpCopyOn() then section = nil end
    UI.ShowSection(section or UI.DefaultSection())
end

function RPChronicler_Toggle()
    if copyFrame:IsShown() then
        copyFrame:Hide()
    else
        RPChronicler_Open("")
    end
end
