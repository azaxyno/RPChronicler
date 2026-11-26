local ADDON_NAME, ns = ...
local UI = ns.UI

-- =========================================================
-- First-run setup (0.6.1 redesign): the logo, two privacy sentences and
-- a few simple choices, with one Start button.
-- Shown once after install, and again only when a later version adds a
-- new choice (each choice has a "since" setup version; only the new ones
-- are listed then). Never shown in combat: it waits until you leave
-- combat. Re-open with /rp setup or Options > Privacy.
-- Everything here can be changed later in Options.
-- =========================================================
local SETUP_VERSION = 4   -- 0.6.4: dungeons ask before recording, RP button
-- Mor (0.6.4): the setup stays basic, 4 choices at most (what to use,
-- dungeon recording, screenshots, RP button). Everything else that is on
-- by default (party gear, update notices, error reports) is named in one
-- line under the choices and switched in Options, never added here.
ns.SETUP_VERSION = SETUP_VERSION

local W = 440              -- frame width
local TEXT_W = W - 48      -- wrapped text width

-- "What do you want to use?" (0.6.1: the RP Copy master switch)
local USES = {
    { key = "COPY", label = "RP Copy", why = "Copy the live scene for your AI character." },
    { key = "STORIES", label = "Stories", why = "Record runs and keep the AI's stories." },
    { key = "BOTH", label = "Both", why = "Everything RP Chronicler does." },
}

-- Each choice: kind "use" (the three buttons above) or a switch with a
-- label, a one-line why, and how it reads and writes the settings.
local CHOICES = {
    { since = 2, kind = "use" },
    { since = 4, key = "instanceRecord", label = "Ask to record dungeons",
      why = "Entering a dungeon asks if you want to record it. The run ends when you leave. Raids: coming soon.",
      get = function() return ns.Get("instanceRecord") ~= "OFF" end,
      set = function(v)
          if not v then ns.Set("instanceRecord", "OFF")
          elseif ns.Get("instanceRecord") == "OFF" then ns.Set("instanceRecord", "ASK") end
      end },
    { since = 2, key = "shots", label = "Screenshots in dungeons",
      why = "On boss kills, level ups and moments you mark.",
      get = function() return ns.Get("autoShots") ~= "OFF" end,
      set = function(v)
          if not v then ns.Set("autoShots", "OFF")
          elseif ns.Get("autoShots") == "OFF" then ns.Set("autoShots", "INSTANCE") end
      end },
    -- 0.6.4: the RP button's place
    { since = 4, key = "iconMode", label = "RP button on the minimap", always = true,
      why = "Off: a floating RP button you can drag anywhere instead.",
      get = function() return ns.Get("iconMode") ~= "FLOAT" end,
      set = function(v) ns.Set("iconMode", v and "MINIMAP" or "FLOAT") end },
}

local S = { rows = {} }
UI.setup = S

local f = CreateFrame("Frame", "RPChroniclerSetupFrame", UIParent, UI.BACKDROP)
f:SetSize(W, 420)
f:SetPoint("CENTER", UIParent, "CENTER", 0, 30)
f:SetFrameStrata("FULLSCREEN_DIALOG")
f:SetMovable(true)
f:EnableMouse(true)
f:RegisterForDrag("LeftButton")
f:SetScript("OnDragStart", f.StartMoving)
f:SetScript("OnDragStop", f.StopMovingOrSizing)
f:SetClampedToScreen(true)
f:Hide()
UI.ApplyDarkGlass(f, 0.05, 0.06, 0.08, 0.98, 0.85, 0.68, 0.30, 0.90)
S.frame = f

S.logo = f:CreateTexture(nil, "ARTWORK")
S.logo:SetSize(96, 96)
S.logo:SetPoint("TOP", 0, -14)
S.logo:SetTexture("Interface\\AddOns\\RPChronicler\\Media\\logo")

S.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
S.title:SetPoint("TOP", S.logo, "BOTTOM", 0, -8)
S.title:SetWidth(TEXT_W)
S.title:SetJustifyH("CENTER")

S.privacy = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
S.privacy:SetPoint("TOP", S.title, "BOTTOM", 0, -8)
S.privacy:SetWidth(TEXT_W)
S.privacy:SetJustifyH("CENTER")
S.privacy:SetSpacing(2)
S.privacy:SetText("|cffd8dee9Everything stays on your PC: RP Chronicler has no internet access and never sends your chat, recordings or stories. " ..
    "They only leave when you paste them into your own AI.|r")

-- The "use" buttons
S.useHead = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
S.useHead:SetWidth(TEXT_W)
S.useHead:SetJustifyH("CENTER")
S.useHead:SetText("|cffffd100What do you want to use?|r")
S.useBtns = {}
S.useWhy = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
S.useWhy:SetWidth(TEXT_W)
S.useWhy:SetJustifyH("CENTER")
local USE_W = math.floor((TEXT_W - 12) / 3)
for i, u in ipairs(USES) do
    local b = UI.CreateSleekButton(f, USE_W, 26, u.label)
    b:SetScript("OnClick", function()
        S.use = u.key
        S.SyncUse()
    end)
    S.useBtns[i] = b
end

function S.SyncUse()
    for i, u in ipairs(USES) do
        local b = S.useBtns[i]
        if u.key == S.use then
            b:LockHighlight()
            b:SetText("|cffffd100" .. u.label .. "|r")
            S.useWhy:SetText("|cff8f9ba8" .. u.why .. "|r")
        else
            b:UnlockHighlight()
            b:SetText("|cffd8dee9" .. u.label .. "|r")
        end
    end
    -- recording switches mean nothing with RP Copy alone
    for _, row in ipairs(S.rows) do
        if row.btn:IsShown() then
            if S.use == "COPY" and not (row.choice and row.choice.always) then row.btn:Disable() else row.btn:Enable() end
        end
    end
end

S.later = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
S.later:SetWidth(TEXT_W)
S.later:SetJustifyH("CENTER")
S.later:SetText("|cff8f9ba8Also on, all kept on your PC: party gear (each member inspected once while you record), update notices (only the version number is sent) and error reports. Change any of this later in Options > Recording and Privacy.|r")

S.start = UI.CreateSleekButton(f, 160, 28, "Start", "good")
S.start:SetPoint("BOTTOM", 0, 14)

local function RowLook(row)
    UI.SetToggleLook(row.btn, row.on and true or false, row.choice.label .. ": ON", row.choice.label .. ": OFF")
end

local function TextH(fs, min)
    return math.max(min or 12, math.floor((fs:GetStringHeight() or min or 12) + 0.5))
end

-- 0.6.3: the setup widens when its labels need it (big fonts or UI
-- scale), so no button clips its text
S.measure = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
S.measure:Hide()
local function FitWidth(list)
    local need = 0
    for _, item in ipairs(list) do
        if item.label then
            S.measure:SetText(item.label .. ": OFF")
            need = math.max(need, (S.measure:GetStringWidth() or 0) + 20)
        end
    end
    for _, u in ipairs(USES) do
        S.measure:SetText(u.label)
        need = math.max(need, ((S.measure:GetStringWidth() or 0) + 20) * 3 + 12)
    end
    local textW = math.max(TEXT_W, math.min(760, math.ceil(need)))
    f:SetWidth(textW + 48)
    for _, fs in ipairs({ S.title, S.privacy, S.useHead, S.useWhy, S.later }) do fs:SetWidth(textW) end
    for _, r in ipairs(S.rows) do r.btn:SetWidth(textW); r.why:SetWidth(textW) end
    S.textW = textW
    return textW
end

-- Lays out the shown choices under the privacy text and sizes the frame
local function Layout(list)
    for _, r in ipairs(S.rows) do r.btn:Hide(); r.why:Hide() end
    local textW = FitWidth(list)
    local useW = math.floor((textW - 12) / 3)
    local y = -14 - 96 - 8 - TextH(S.title, 18) - 8 - TextH(S.privacy, 26) - 16
    local showUse = false
    for _, item in ipairs(list) do if item.kind == "use" then showUse = true end end
    if showUse then
        S.useHead:ClearAllPoints()
        S.useHead:SetPoint("TOP", 0, y)
        y = y - 20
        for i, b in ipairs(S.useBtns) do
            b:ClearAllPoints()
            b:SetWidth(useW)
            b:SetPoint("TOPLEFT", 24 + (i - 1) * (useW + 6), y)
            b:Show()
        end
        y = y - 30
        S.useWhy:ClearAllPoints()
        S.useWhy:SetPoint("TOP", 0, y)
        y = y - 22
        S.useHead:Show()
        S.useWhy:Show()
    else
        S.useHead:Hide()
        S.useWhy:Hide()
        for _, b in ipairs(S.useBtns) do b:Hide() end
    end
    local n = 0
    for _, item in ipairs(list) do
        if item.kind ~= "use" then
            n = n + 1
            local row = S.rows[n]
            if not row then
                row = { btn = UI.CreateSleekButton(f, textW, 22, ""), why = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall") }
                row.why:SetWidth(textW)
                row.why:SetJustifyH("LEFT")
                row.btn:SetScript("OnClick", function()
                    row.on = not row.on
                    RowLook(row)
                end)
                S.rows[n] = row
            end
            row.choice, row.on = item, item.get() and true or false
            row.btn:ClearAllPoints()
            row.btn:SetPoint("TOPLEFT", 24, y)
            row.why:ClearAllPoints()
            row.why:SetPoint("TOPLEFT", 26, y - 25)
            row.why:SetText("|cff8f9ba8" .. item.why .. "|r")
            row.btn:Show()
            row.why:Show()
            RowLook(row)
            y = y - 25 - TextH(row.why, 12) - 10
        end
    end
    S.later:ClearAllPoints()
    S.later:SetPoint("TOP", 0, y - 4)
    y = y - 4 - TextH(S.later, 12) - 12
    f:SetHeight(-y + 28 + 14)
    S.SyncUse()
end

local function Finish()
    if S.showUse then
        ns.Set("rpCopy", S.use ~= "STORIES")
    end
    for _, row in ipairs(S.rows) do
        if row.btn:IsShown() then
            -- RP Copy alone: no automatic recording and no screenshots
            local v = row.on
            if S.use == "COPY" and not row.choice.always then v = false end
            pcall(row.choice.set, v)
        end
    end
    RPChroniclerDB.setupVersion = SETUP_VERSION
    f:Hide()
    UI.SyncCopyChip()
    UI.UpdateOverrideBindings()
    print("|cffffd100RP Chronicler|r Setup saved. |cff9aa5b4Change it any time in Options (/rp setup shows this again).|r")
    -- 0.6.3: one next step for each thing you chose
    if S.use ~= "STORIES" and ns.RpCopyOn() then
        print("|cffffd100RP Chronicler|r |cff9aa5b4RP Copy, next:|r type /rp, open Options > AI & Stories, copy the RP Template into your AI as a character skill, and put its trigger in Options > Slice Tabs as the Skill Call. Then Ctrl+C copies the scene.")
    end
    if S.use ~= "COPY" then
        print("|cffffd100RP Chronicler|r |cff9aa5b4Stories, next:|r type /rp, open Adventures and press Start (dungeons ask when you enter). When the run ends, open its Full Log, tick Include AI instructions, click Copy for AI, paste it into any AI chat, then import the story it writes in the Story Book.")
    end
    ns.Debug("info", "setup saved (v" .. SETUP_VERSION .. ", use " .. tostring(S.use) .. ")")
end
S.start:SetScript("OnClick", Finish)

-- force: show every choice (from Options or /rp setup)
function UI.OpenSetup(force)
    ns.EnsureDB()
    if InCombatLockdown and InCombatLockdown() then
        S.waitForce = force
        S.waiting = true
        print("|cffffd100RP Chronicler|r Setup opens when you leave combat.")
        return
    end
    local seen = tonumber(RPChroniclerDB.setupVersion) or 0
    local list = {}
    S.showUse = false
    for _, c in ipairs(CHOICES) do
        if force or (c.since or 1) > seen then
            table.insert(list, c)
            if c.kind == "use" then S.showUse = true end
        end
    end
    if #list == 0 then return end
    S.use = ns.RpCopyOn() and "BOTH" or "STORIES"
    if seen < 1 or force then
        S.title:SetText("|cffffd100Welcome to RP Chronicler|r")
    else
        S.title:SetText("|cffffd100RP Chronicler " .. tostring(ns.VERSION) .. ": a few new choices|r")
    end
    if UI.frame:IsShown() then UI.frame:Hide() end
    f:Show()
    Layout(list)
end

ns.On({ "PLAYER_REGEN_ENABLED", "PLAYER_LOGIN" }, function(event)
    if event == "PLAYER_REGEN_ENABLED" then
        if S.waiting then
            S.waiting = false
            UI.OpenSetup(S.waitForce)
        end
    elseif C_Timer and C_Timer.After then
        C_Timer.After(5, function()
            ns.EnsureDB()
            if (tonumber(RPChroniclerDB.setupVersion) or 0) < SETUP_VERSION then UI.OpenSetup(false) end
        end)
    end
end)
