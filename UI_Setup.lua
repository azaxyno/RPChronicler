local ADDON_NAME, ns = ...
local UI = ns.UI

-- =========================================================
-- First-run setup (0.5.0): a privacy note and the recording choices.
-- Shown once after install, and again only when a later version adds new
-- recording or capture features (each choice has a "since" setup
-- version; only the new ones are listed then). Never shown in combat:
-- it waits until you leave combat. Re-open with /rp setup or
-- Options > Privacy.
-- =========================================================
local SETUP_VERSION = 1
ns.SETUP_VERSION = SETUP_VERSION

local function Get(field, invert)
    local v = RPCopyDB[field]
    if invert then return v ~= false end
    return v and true or false
end

-- Each choice: label, one-line why, read and write of the saved value
local CHOICES = {
    { since = 1, label = "Auto-record dungeons and raids", why = "A run starts when you enter an instance and ends when you leave.",
      get = function() return Get("autoRecord", true) end, set = function(v) RPCopyDB.autoRecord = v end },
    { since = 1, label = "Ask to record in the open world", why = "Joining a group asks 'Start recording?'.",
      get = function() return Get("promptOnGroup", true) end, set = function(v) RPCopyDB.promptOnGroup = v end },
    { since = 1, label = "Auto screenshots", why = "Boss kills, level ups and marked moments during a run.",
      get = function() return Get("autoScreenshots") end, set = function(v) RPCopyDB.autoScreenshots = v end },
    { since = 1, label = "Add my own screenshots", why = "Your Print Screen shots join the run, with a caption.",
      get = function() return Get("recordManualShots", true) end, set = function(v) RPCopyDB.recordManualShots = v end },
    { since = 1, label = "Update companions from chat", why = "Level, class and latest chat of people you saved.",
      get = function() return Get("autoUpdateKnown") end, set = function(v) RPCopyDB.autoUpdateKnown = v end },
    { since = 1, label = "Debug log", why = "RPCopy's own errors and run events, never chat (/rp debug).",
      get = function() return Get("debugEnabled", true) end, set = function(v) RPCopyDB.debugEnabled = v end },
}
for _, c in ipairs(ns.CAPTURE_TYPES or {}) do
    local key = c.key
    table.insert(CHOICES, { since = 1, capture = true, label = c.label,
        why = (key == "whisper") and "Private messages to and from you." or nil,
        get = function() return RPCopyDB.capture[key] ~= false end,
        set = function(v) RPCopyDB.capture[key] = v end })
end

local S = { rows = {}, pending = {} }
UI.setup = S

local f = CreateFrame("Frame", "RPCopySetupFrame", UIParent, UI.BACKDROP)
f:SetSize(580, 470)
f:SetPoint("CENTER", UIParent, "CENTER", 0, 20)
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

S.title = UI.Label(f, "|cffffd100Welcome to RPCopy|r", "GameFontNormalLarge")
S.title:SetPoint("TOPLEFT", 16, -14)

S.privacy = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
S.privacy:SetPoint("TOPLEFT", 16, -40)
S.privacy:SetPoint("TOPRIGHT", -16, -40)
S.privacy:SetJustifyH("LEFT")
S.privacy:SetJustifyV("TOP")
S.privacy:SetSpacing(2)

S.choiceHead = UI.Label(f, "", "GameFontNormal")

S.copyBtn = UI.CreateSleekButton(f, 210, 20, "", "tool")
S.copyBtn.tipTitle = "|cffffd100Ctrl+C copy mode|r"
S.copyBtn.tipText = "Instant: hold Ctrl a moment and press C, one press copies. Two-press: Ctrl+C arms, a second Ctrl+C copies."
S.copyWhy = UI.Label(f, "|cff8f9ba8How Ctrl+C copies the scene in the game world.|r", "GameFontHighlightSmall")

S.later = UI.Label(f, "|cff8f9ba8You can change all of this later in Options > Privacy and Options > Recording.|r", "GameFontHighlightSmall")
S.later:SetPoint("BOTTOMLEFT", 16, 44)

S.accept = UI.CreateSleekButton(f, 130, 24, "Accept & Save", "good")
S.accept:SetPoint("BOTTOMLEFT", 16, 12)
S.skip = UI.CreateSleekButton(f, 150, 24, "Skip (keep defaults)")
S.skip:SetPoint("LEFT", S.accept, "RIGHT", 6, 0)

local function RowLook(row)
    local on = S.pending[row.idx]
    UI.SetToggleLook(row.btn, on and true or false, row.choice.label .. ": ON", row.choice.label .. ": OFF")
end

local function Layout(list)
    for _, r in ipairs(S.rows) do r.btn:Hide(); r.why:Hide() end
    local y = -40 - math.max(70, (S.privacy:GetStringHeight() or 60)) - 12
    S.choiceHead:ClearAllPoints()
    S.choiceHead:SetPoint("TOPLEFT", 16, y)
    S.choiceHead:SetText(#list > 0 and "|cffffd100Your choices|r" or "")
    y = y - 20
    local capCol = 0
    for i, item in ipairs(list) do
        local row = S.rows[i]
        if not row then
            row = { btn = UI.CreateSleekButton(f, 230, 20, ""), why = UI.Label(f, "", "GameFontHighlightSmall") }
            row.btn:SetScript("OnClick", function(self)
                S.pending[self.row.idx] = not S.pending[self.row.idx]
                RowLook(self.row)
            end)
            row.btn.row = row
            S.rows[i] = row
        end
        row.idx, row.choice = item.idx, item.choice
        row.btn:ClearAllPoints()
        row.why:ClearAllPoints()
        if item.choice.capture and not item.choice.why then
            -- chat types sit two to a line
            row.btn:SetWidth(262)
            row.btn:SetPoint("TOPLEFT", 16 + capCol * 274, y)
            capCol = capCol + 1
            if capCol > 1 then capCol, y = 0, y - 24 end
            row.why:SetText("")
        else
            if capCol > 0 then capCol, y = 0, y - 24 end
            row.btn:SetWidth(230)
            row.btn:SetPoint("TOPLEFT", 16, y)
            row.why:SetPoint("LEFT", row.btn, "RIGHT", 8, 0)
            row.why:SetPoint("RIGHT", f, "RIGHT", -16, 0)
            row.why:SetJustifyH("LEFT")
            row.why:SetWordWrap(false)
            row.why:SetText("|cff8f9ba8" .. (item.choice.why or "") .. "|r")
            y = y - 24
        end
        row.btn:Show()
        row.why:Show()
        RowLook(row)
    end
    if capCol > 0 then y = y - 24 end
    S.copyBtn:ClearAllPoints()
    S.copyBtn:SetPoint("TOPLEFT", 16, y)
    S.copyWhy:ClearAllPoints()
    S.copyWhy:SetPoint("LEFT", S.copyBtn, "RIGHT", 8, 0)
    if S.showCopy then S.copyBtn:Show(); S.copyWhy:Show(); y = y - 24 else S.copyBtn:Hide(); S.copyWhy:Hide() end
    f:SetHeight(math.max(260, -y + 80))
end

local function SyncCopyBtn()
    S.copyBtn:SetText(S.copyMode == "TWOPRESS" and "Ctrl+C: Two-press" or "Ctrl+C: Instant")
end
S.copyBtn:SetScript("OnClick", function()
    S.copyMode = (S.copyMode == "TWOPRESS") and "INSTANT" or "TWOPRESS"
    SyncCopyBtn()
end)

local function Finish(save)
    if save then
        for i, c in ipairs(CHOICES) do
            if S.pending[i] ~= nil then pcall(c.set, S.pending[i]) end
        end
        if S.showCopy and S.copyMode then RPCopyDB.copyMode = S.copyMode end
        if UI.SyncCopyChip then pcall(UI.SyncCopyChip) end
    end
    RPCopyDB.setupVersion = SETUP_VERSION
    f:Hide()
    print("|cffffd100RPCopy|r " .. (save and "Setup saved." or "Setup skipped, defaults kept.") .. " |cff9aa5b4Change it any time in Options > Privacy (/rp setup).|r")
    if ns.Debug then ns.Debug("info", "setup " .. (save and "saved" or "skipped") .. " (v" .. SETUP_VERSION .. ")") end
end
S.accept:SetScript("OnClick", function() Finish(true) end)
S.skip:SetScript("OnClick", function() Finish(false) end)

local waitFrame = CreateFrame("Frame")

-- force: show every choice (from Options or /rp setup)
function UI.OpenSetup(force)
    ns.EnsureDB()
    if InCombatLockdown and InCombatLockdown() then
        waitFrame.force = force
        waitFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
        print("|cffffd100RPCopy|r Setup opens when you leave combat.")
        return
    end
    local seen = tonumber(RPCopyDB.setupVersion) or 0
    local list = {}
    S.pending = {}
    for i, c in ipairs(CHOICES) do
        if force or (c.since or 1) > seen then
            S.pending[i] = c.get() and true or false
            table.insert(list, { idx = i, choice = c })
        end
    end
    S.showCopy = force or seen < 1
    S.copyMode = (RPCopyDB.copyMode == "TWOPRESS") and "TWOPRESS" or "INSTANT"
    SyncCopyBtn()
    S.title:SetText((seen < 1 or force) and "|cffffd100Welcome to RPCopy - privacy and setup|r" or "|cffffd100RPCopy - new recording options|r")
    S.privacy:SetText(ns.PRIVACY_TEXT or "")
    if UI.frame and UI.frame:IsShown() then UI.frame:Hide() end
    f:Show()
    Layout(list)
end

waitFrame:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_REGEN_ENABLED" then
        self:UnregisterEvent("PLAYER_REGEN_ENABLED")
        UI.OpenSetup(self.force)
    elseif event == "PLAYER_LOGIN" then
        if C_Timer and C_Timer.After then
            C_Timer.After(5, function()
                ns.EnsureDB()
                if (tonumber(RPCopyDB.setupVersion) or 0) < SETUP_VERSION then UI.OpenSetup(false) end
            end)
        end
    end
end)
waitFrame:RegisterEvent("PLAYER_LOGIN")
