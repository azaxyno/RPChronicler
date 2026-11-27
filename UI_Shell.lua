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
    ADVENTURES = "Interface\\AddOns\\RPChronicler\\Media\\Icons\\tab_adventures.png", -- 0.6.6: our spyglass, used nowhere else (0.6.7: with .png)
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
-- 0.7.0 (the Library look): every panel is warm leather and brass. The
-- old cool blue-greys are turned to the same darkness in brown here, so
-- every view takes the new look without its own colors changing.
function UI.Warm(r, g, b)
    if not (r and g and b) or b <= r then return r, g, b end
    local l = (r + g + b) / 3
    return math.min(1, l * 1.32), l, l * 0.68
end

function UI.ApplyDarkGlass(frame, bgR, bgG, bgB, bgA, brR, brG, brB, brA)
    if not frame or not frame.SetBackdrop then return end
    bgR, bgG, bgB = UI.Warm(bgR or 0.06, bgG or 0.07, bgB or 0.10)
    brR, brG, brB = UI.Warm(brR or 0.72, brG or 0.58, brB or 0.28)
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
            self:SetBackdropColor(0.26, 0.19, 0.11, 0.97)
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
UI.DEFAULT_W, UI.DEFAULT_H = 720, 520
UI.MIN_W, UI.MIN_H = 660, 480   -- 0.6.3: rows wrap, so nothing overlaps at this size (0.7.0: taller header)

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

-- =========================================================
-- 0.7.0: the tome frame. Leather over the whole window, brass corners,
-- a header with the title and the chronicle plaque, and bookmark
-- ribbons down the left instead of the old rail.
-- =========================================================
UI.ART = "Interface\\AddOns\\RPChronicler\\Media\\Book\\"
UI.GOLD_FONT = "Fonts\\MORPHEUS.TTF"
do
    local leather = copyFrame:CreateTexture(nil, "BACKGROUND", nil, -6)
    leather:SetPoint("TOPLEFT", 1, -1)
    leather:SetPoint("BOTTOMRIGHT", -1, 1)
    if not pcall(leather.SetTexture, leather, UI.ART .. "cover.png", "REPEAT", "REPEAT") then
        leather:SetTexture(UI.ART .. "cover.png")
    end
    leather:SetVertexColor(0.36, 0.16, 0.11)
    UI.leather = leather
    local coords = { { "TOPLEFT", 0, 1, 0, 1 }, { "TOPRIGHT", 1, 0, 0, 1 }, { "BOTTOMLEFT", 0, 1, 1, 0 }, { "BOTTOMRIGHT", 1, 0, 1, 0 } }
    for _, c in ipairs(coords) do
        local t = copyFrame:CreateTexture(nil, "OVERLAY", nil, 7)
        t:SetTexture(UI.ART .. "corner.png")
        t:SetSize(30, 30)
        t:SetPoint(c[1], 0, 0)
        t:SetTexCoord(c[2], c[3], c[4], c[5])
    end
end

-- Header strip: title, the plaque, version and close
UI.HEADER_H = 44
do
    local headerBar = CreateFrame("Frame", nil, copyFrame, UI.BACKDROP)
    headerBar:SetHeight(UI.HEADER_H)
    headerBar:SetPoint("TOPLEFT", 1, -1)
    headerBar:SetPoint("TOPRIGHT", -1, -1)
    UI.ApplyDarkGlass(headerBar, 0.16, 0.08, 0.05, 0.55, 0.78, 0.62, 0.28, 0.35)
    UI.header = headerBar

    UI.titleText = headerBar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    UI.titleText:SetPoint("TOPLEFT", 16, -9)
    pcall(UI.titleText.SetFont, UI.titleText, UI.GOLD_FONT, 15, "")
    UI.titleText:SetShadowOffset(1, -1)
    UI.titleText:SetText("|cffffd100RP CHRONICLER|r")
    UI.subTitle = headerBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    UI.subTitle:SetPoint("TOPLEFT", UI.titleText, "BOTTOMLEFT", 0, -2)
    UI.subTitle:SetText("|cffb09a70BETA|r")

    local closeBtn = UI.CreateSleekButton(headerBar, 22, 20, "x", "danger")
    closeBtn:SetPoint("RIGHT", -10, 0)
    closeBtn:SetScript("OnClick", function() copyFrame:Hide() end)
    UI.closeBtn = closeBtn

    local verBadge = headerBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    verBadge:SetPoint("RIGHT", closeBtn, "LEFT", -8, 0)
    verBadge:SetText("|cff8f7f68v" .. (ns.VERSION or "0.7.0") .. "|r")
end

-- The chronicle plaque: "Start a new recording" over "Chronicle a new
-- adventure". While a run records: a pulsing wax seal, its name and time.
-- Click starts, or ends the run (after asking); right-click pauses.
do
    local plq = CreateFrame("Button", nil, UI.header)
    plq:SetSize(290, 32)
    plq:SetPoint("CENTER", 0, -4)
    plq:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    plq.bg = plq:CreateTexture(nil, "BACKGROUND")
    plq.bg:SetAllPoints(plq)
    plq.bg:SetTexture(UI.ART .. "plaque.png")
    plq.tab = plq:CreateTexture(nil, "BORDER")
    plq.tab:SetTexture(UI.SOLID_TEX)
    plq.tab:SetVertexColor(0.16, 0.09, 0.05, 1)
    plq.tab:SetSize(150, 11)
    plq.tab:SetPoint("BOTTOM", plq, "TOP", 0, -4)
    plq.over = plq:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    plq.over:SetPoint("CENTER", plq.tab, "CENTER", 0, 0)
    pcall(plq.over.SetFont, plq.over, "Fonts\\FRIZQT__.TTF", 8, "")
    plq.ring = plq:CreateTexture(nil, "ARTWORK")
    plq.ring:SetTexture(UI.ART .. "ring.png")
    plq.ring:SetSize(26, 26)
    plq.ring:SetPoint("LEFT", 6, 0)
    plq.quill = plq:CreateTexture(nil, "OVERLAY")
    plq.quill:SetTexture(UI.ART .. "quill.png")
    plq.quill:SetVertexColor(0.30, 0.16, 0.08)
    plq.quill:SetSize(18, 18)
    plq.quill:SetPoint("CENTER", plq.ring, "CENTER", 0, 0)
    plq.seal = plq:CreateTexture(nil, "OVERLAY")
    plq.seal:SetTexture(UI.ART .. "seal.png")
    plq.seal:SetVertexColor(0.85, 0.12, 0.10)
    plq.seal:SetSize(24, 24)
    plq.seal:SetPoint("CENTER", plq.ring, "CENTER", 0, 0)
    plq.seal:Hide()
    plq.text = plq:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    plq.text:SetPoint("LEFT", plq.ring, "RIGHT", 6, 0)
    plq.text:SetPoint("RIGHT", -8, 0)
    plq.text:SetJustifyH("CENTER")
    plq.text:SetWordWrap(false)
    pcall(plq.text.SetFont, plq.text, UI.GOLD_FONT, 14, "")
    UI.plaque = plq

    -- looping motion (guarded; behind the Animations switch): the rune
    -- ring turns, the seal pulses
    if plq.CreateAnimationGroup then
        pcall(function()
            local spin = plq:CreateAnimationGroup()
            local r = spin:CreateAnimation("Rotation")
            r:SetDegrees(-360)
            r:SetDuration(18)
            r:SetTarget(plq.ring)
            spin:SetLooping("REPEAT")
            plq.spin = spin
            local pulse = plq:CreateAnimationGroup()
            local a = pulse:CreateAnimation("Alpha")
            a:SetFromAlpha(1)
            a:SetToAlpha(0.45)
            a:SetDuration(0.9)
            a:SetTarget(plq.seal)
            pulse:SetLooping("BOUNCE")
            plq.pulse = pulse
            if ns.WatchAnim then ns.WatchAnim(spin, "plaque ring") ns.WatchAnim(pulse, "plaque seal") end
        end)
    end
    local function Loop(ag, on)
        if not ag then return end
        if on and ns.Get("bookMotion") then
            if not ag:IsPlaying() then ag:Play() end
        elseif ag:IsPlaying() then
            ag:Stop()
        end
    end

    function UI.RefreshPlaque()
        local run = ns.GetActiveAdventure()
        if not run then
            plq.over:SetText("|cffe8c66aSTART A NEW RECORDING|r")
            plq.text:SetText("|cff4a2a12Chronicle a new adventure|r")
            plq.seal:Hide()
            plq.quill:Show()
            Loop(plq.pulse, false)
            Loop(plq.spin, true)
            return
        end
        local secs = math.max(0, time() - (run.startTime or time()))
        local clock = string.format("%d:%02d", math.floor(secs / 3600), math.floor(secs / 60) % 60)
        local name = tostring(run.title or "Adventure")
        if #name > 22 then name = name:sub(1, 20) .. "..." end
        plq.quill:Hide()
        plq.seal:Show()
        Loop(plq.spin, false)
        if run.paused then
            plq.over:SetText("|cffffb74dPAUSED - RIGHT-CLICK TO RESUME|r")
            plq.text:SetText("|cff6a4a20The quill rests: " .. name .. "|r")
            plq.seal:SetAlpha(0.6)
            Loop(plq.pulse, false)
        else
            plq.over:SetText("|cffff8a8aEND ADVENTURE|r")
            plq.text:SetText("|cff5a1a10Chronicling: " .. name .. "  " .. clock .. "|r")
            Loop(plq.pulse, true)
        end
    end

    plq:SetScript("OnClick", function(_, button)
        local run = ns.GetActiveAdventure()
        if button == "RightButton" then
            if run and RPChronicler_ToggleRunPause then RPChronicler_ToggleRunPause() end
        elseif not run then
            if RPChronicler_StartRun then RPChronicler_StartRun() end
        else
            UI.ShowPrompt("|cffffd100End this adventure?|r\n|cffd7c4a3" .. tostring(run.title or "") ..
                " is saved to your Journal, waiting for its story.|r",
                "|cffff8a8aEnd adventure|r", function() if RPChronicler_EndRun then RPChronicler_EndRun() end end,
                "Keep recording", nil)
        end
        UI.RefreshPlaque()
    end)
    plq:SetScript("OnEnter", function(self)
        self.bg:SetVertexColor(1, 0.95, 0.80)
        local run = ns.GetActiveAdventure()
        if run then
            UI.Tooltip(self, "|cffffd100" .. tostring(run.title or "Adventure") .. "|r",
                run.paused and "The quill rests. Recording paused." or "The enchanted quill is writing down your deeds.",
                "Click: end the adventure (asks first). Right-click: pause or resume.")
        else
            UI.Tooltip(self, "|cffffd100Chronicle a new adventure|r",
                "Starts recording here and now. Dungeons ask by themselves when you enter (Options > Recording).")
        end
    end)
    plq:SetScript("OnLeave", function(self)
        self.bg:SetVertexColor(1, 1, 1)
        UI.HideTooltip()
    end)
    local acc = 1
    plq:SetScript("OnUpdate", function(_, elapsed)
        acc = acc + elapsed
        if acc < 1 then return end
        acc = 0
        UI.RefreshPlaque()
    end)
    ns.Listen("runChanged", function() UI.RefreshPlaque() end)
    ns.Listen("setting", function(key) if key == "bookMotion" then UI.RefreshPlaque() end end)
end

-- =========================================================
-- Ribbons (0.7.0): bookmark ribbons down the left replace the rail.
-- Library, Journal and Companions hang from the top; Copy and the brass
-- key (Options) from the bottom. Each view adds its own with
-- UI.AddRailButton; UI.RIBBONS sets its place, color and name.
-- =========================================================
local RAIL_W = 78
UI.RIBBONS = {
    BOOK       = { order = 1, tint = { 0.66, 0.14, 0.12 } },
    ADVENTURES = { order = 2, tint = { 0.18, 0.40, 0.22 } },
    PLAYERS    = { order = 3, tint = { 0.16, 0.28, 0.52 } },
    COPY       = { order = 2, bottom = true, tint = { 0.40, 0.20, 0.52 } },
    OPTIONS    = { order = 1, bottom = true, tint = { 0.46, 0.34, 0.16 }, short = true },
}
do
    local rail = CreateFrame("Frame", nil, copyFrame)
    rail:SetWidth(RAIL_W)
    rail:SetPoint("TOPLEFT", 6, -(UI.HEADER_H + 1))
    rail:SetPoint("BOTTOMLEFT", 6, 6)
    UI.rail = rail
    UI.railButtons = {}
    local line = rail:CreateTexture(nil, "BACKGROUND")
    line:SetTexture(UI.SOLID_TEX)
    line:SetVertexColor(0.78, 0.62, 0.28, 0.25)
    line:SetPoint("TOPRIGHT", 0, 0)
    line:SetPoint("BOTTOMRIGHT", 0, 0)
    line:SetWidth(1)
end

UI.railOrder = {}

local function RibbonLook(btn, on)
    local t = btn.tint or { 0.5, 0.5, 0.5 }
    local k = on and 1.25 or 0.85
    btn.cloth:SetVertexColor(math.min(1, t[1] * k), math.min(1, t[2] * k), math.min(1, t[3] * k))
    btn.label:SetTextColor(on and 1 or 0.90, on and 0.88 or 0.80, on and 0.50 or 0.62)
end

-- Stacks the shown ribbons: top ones down from the header, bottom ones
-- up from the floor. The open view's ribbon hangs longer.
function UI.LayoutRail()
    local tops, bottoms = {}, {}
    for _, key in ipairs(UI.railOrder) do
        local btn = UI.railButtons[key]
        if btn.hiddenByFeature then
            btn:Hide()
        else
            table.insert(btn.bottom and bottoms or tops, btn)
        end
    end
    table.sort(tops, function(a, b) return a.order < b.order end)
    table.sort(bottoms, function(a, b) return a.order < b.order end)
    local y = 0
    for _, btn in ipairs(tops) do
        btn:ClearAllPoints()
        btn:SetPoint("TOP", UI.rail, "TOP", -2, -y)
        btn:SetHeight(btn.isOpen and btn.baseH + 10 or btn.baseH)
        btn:Show()
        y = y + btn.baseH + 6
    end
    y = 0
    for _, btn in ipairs(bottoms) do
        btn:ClearAllPoints()
        btn:SetPoint("BOTTOM", UI.rail, "BOTTOM", -2, y)
        btn:SetHeight(btn.isOpen and btn.baseH + 6 or btn.baseH)
        btn:Show()
        y = y + btn.baseH + 8
    end
end

function UI.AddRailButton(key, label, icon, tip)
    local spec = UI.RIBBONS[key] or { order = 9 }
    local btn = CreateFrame("Button", nil, UI.rail)
    btn.baseH = spec.short and 40 or 70
    btn:SetSize(RAIL_W - 12, btn.baseH)
    btn.order, btn.bottom, btn.tint = spec.order, spec.bottom, spec.tint
    btn.cloth = btn:CreateTexture(nil, "BACKGROUND")
    btn.cloth:SetAllPoints(btn)
    btn.cloth:SetTexture(UI.ART .. "ribbon.png")
    btn.icon = btn:CreateTexture(nil, "ARTWORK")
    btn.icon:SetSize(22, 22)
    btn.icon:SetPoint("TOP", 0, spec.short and -7 or -8)
    btn.icon:SetTexCoord(ns.IconCoords(icon))
    btn.icon:SetTexture(icon)
    btn.label = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    btn.label:SetPoint("TOP", btn.icon, "BOTTOM", 0, -3)
    btn.label:SetWidth(RAIL_W - 14)
    btn.label:SetWordWrap(false)
    pcall(btn.label.SetFont, btn.label, "Fonts\\FRIZQT__.TTF", 9, "")
    btn.label:SetShadowOffset(1, -1)
    btn.label:SetText(spec.short and "" or label)
    btn.tipTitle = "|cffffd100" .. label .. "|r"
    btn.tipText = tip
    function btn:LockHighlight() self.isOpen = true; RibbonLook(self, true) end
    function btn:UnlockHighlight() self.isOpen = false; RibbonLook(self, false) end
    btn:SetScript("OnEnter", function(self)
        RibbonLook(self, true)
        UI.Tooltip(self, self.tipTitle, self.tipText)
    end)
    btn:SetScript("OnLeave", function(self)
        RibbonLook(self, self.isOpen)
        UI.HideTooltip()
    end)
    btn:SetScript("OnClick", function()
        if key == "OPTIONS" and ns.state.section == "OPTIONS" then
            UI.ShowSection(UI.lastNonOptions or UI.DefaultSection())
        else
            UI.ShowSection(key)
        end
    end)
    RibbonLook(btn, false)
    UI.railButtons[key] = btn
    table.insert(UI.railOrder, key)
    UI.LayoutRail()
    return btn
end

-- the brass key opens Options (its view is built in UI_Options.lua)
UI.gearBtn = UI.AddRailButton("OPTIONS", "Options", UI.ART .. "key.png",
    "The Binder's Desk: settings, privacy, keybinds and AI setup.")
UI.gearBtn.icon:SetVertexColor(1, 0.84, 0.45)

-- Content area (sections fill it) and the status line under it
do
    local content = CreateFrame("Frame", nil, copyFrame)
    UI.content = content
    local status = copyFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    status:SetPoint("BOTTOMLEFT", UI.rail, "BOTTOMRIGHT", 10, 4)
    status:SetPoint("RIGHT", copyFrame, "RIGHT", -24, 0)
    status:SetJustifyH("LEFT")
    status:SetWordWrap(false)
    UI.statusText = status
end

-- 0.7.0 book mode: an open book fills the window. The header and the
-- ribbons step aside (the book's own "< Back to the Library" returns).
function UI.SetBookMode(on)
    on = on and true or false
    if UI.bookMode == on and UI.content:GetNumPoints() > 0 then return end
    UI.bookMode = on
    local c = UI.content
    c:ClearAllPoints()
    if on then
        UI.header:Hide()
        UI.rail:Hide()
        UI.statusText:Hide()
        c:SetPoint("TOPLEFT", copyFrame, "TOPLEFT", 8, -8)
        c:SetPoint("BOTTOMRIGHT", copyFrame, "BOTTOMRIGHT", -8, 8)
    else
        local fade = ns.Get("bookMotion") and UIFrameFadeIn
        UI.header:Show()
        UI.rail:Show()
        UI.statusText:Show()
        if fade then pcall(fade, UI.header, 0.25, 0, 1) pcall(fade, UI.rail, 0.25, 0, 1) end
        c:SetPoint("TOPLEFT", UI.rail, "TOPRIGHT", 10, -8)
        c:SetPoint("BOTTOMRIGHT", copyFrame, "BOTTOMRIGHT", -12, 22)
    end
end
UI.SetBookMode(false)

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
    if key == "COPY" and not ns.RpCopyOn() then key = "BOOK" end
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
    UI.LayoutRail()
    if key ~= "BOOK" then UI.SetBookMode(false) end
    UI.subTitle:SetText("|cffb09a70BETA  -  " .. string.upper(sec.title or "") .. "|r")
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
    -- 0.6.5: set when Ctrl in the instruction line switched to the copy
    -- step; any other key than C then goes back to the line (Ctrl+V,
    -- Ctrl+A ... keep working there)
    local backTo
    copyEb:SetScript("OnKeyDown", function(self, key)
        if backTo and key ~= "C" and key ~= "LCTRL" and key ~= "RCTRL" then
            local b = backTo
            backTo = nil
            UI.AskLine(b.opts)
            eb:SetText(b.text)
            eb:SetCursorPosition(#b.text)
            return
        end
        if key == "C" and IsControlKeyDown() and copyText then
            backTo = nil
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
    -- 0.6.5 (Mor): Ctrl in the instruction line selects the whole copy
    -- right away (instruction included), so the C of Ctrl+C copies it: one
    -- Ctrl+C, no Enter and no second press. An addon can't write to the
    -- clipboard; the game copies the selected text itself.
    eb:SetScript("OnKeyDown", function(self, key)
        if (key ~= "LCTRL" and key ~= "RCTRL") or not (opts and opts.ctrlCopy) then return end
        local text = ((self:GetText() or ""):gsub("||", "|")):match("^%s*(.-)%s*$")
        local ok, body, head = pcall(opts.ctrlCopy, text)
        if not ok or type(body) ~= "string" then return end
        local keep = { opts = opts, text = self:GetText() or "" }
        UI.AskLineCopy(head, body)
        backTo = keep
    end)
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
        backTo = nil
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
        backTo = nil
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

-- the leather repeats at its own size instead of stretching
UI.AddReflow(function()
    local w, h = copyFrame:GetWidth() or 700, copyFrame:GetHeight() or 500
    UI.leather:SetTexCoord(0, math.max(1, w / 256), 0, math.max(1, h / 256))
end)

-- =========================================================
-- Opening and closing
-- =========================================================
-- 0.7.0: the Library is home (the RP button and /rp open on it)
function UI.DefaultSection()
    return "BOOK"
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

-- =========================================================
-- 0.7.0 (Mor): a menu closes when you click anywhere outside it (and
-- outside the button that opened it, which toggles it itself)
-- =========================================================
do
    local open = {}
    function UI.CloseOnOutsideClick(menu, anchor)
        if menu then open[menu] = anchor or true end
    end
    ns.On("GLOBAL_MOUSE_DOWN", function()
        for m, anchor in pairs(open) do
            if not m:IsShown() then
                open[m] = nil
            elseif not m:IsMouseOver() and not (type(anchor) == "table" and anchor.IsMouseOver and anchor:IsMouseOver()) then
                m:Hide()
                open[m] = nil
            end
        end
    end)
end
