-- RP Chronicler screenshots: one shot per story moment, never in a way
-- that touches protected frames. The interface is faded with
-- UIParent:SetAlpha (never Hide/Show), so combat can't block it.
local ADDON_NAME, ns = ...

local SHOT_DELAY = 0.75     -- seconds between the moment and the shot
local DEBOUNCE = 20         -- routine shots are at least this far apart
local LOADING_RETRY = 1     -- while a loading screen shows, look again this often
local LOADING_WAIT = 10     -- ... and give up after this many seconds
local UI_RESTORE = 2.0
local OWN_WINDOW = 6        -- seconds: a SCREENSHOT_SUCCEEDED this soon after our own shot is ours

-- The shot waiting for its moment, and the shot state
local S = { want = nil, lastAt = nil, ownAt = nil, loading = false, faded = false }

-- When two moments land inside the delay, the higher rank names the shot.
local RANK = { story = 1, newzone = 2, quest = 3, mark = 4, levelup = 5, boss = 6 }

-- Boss kills and manual Mark Moment always get a shot, even right after
-- another one (the debounce only thins out routine zone/quest shots).
local ALWAYS_SHOOT = { boss = true, mark = true }

local function InCombat()
    if InCombatLockdown and InCombatLockdown() then return true end
    return UnitAffectingCombat ~= nil and ns.SafeBool(UnitAffectingCombat("player")) == true
end

local function TooSoon(kind)
    if ALWAYS_SHOOT[kind] or not S.lastAt then return false end
    return (GetTime() - S.lastAt) < DEBOUNCE
end

local function After(sec, fn)
    if C_Timer and C_Timer.After then C_Timer.After(sec, fn) else fn() end
end

local function RestoreUI()
    if S.faded and UIParent then
        S.faded = false
        pcall(UIParent.SetAlpha, UIParent, 1)
    end
end

-- 0.6.1: one setting, autoShots: OFF (none), INSTANCE (dungeons and raids,
-- plus Mark Moment anywhere, since that is your own choice) or ALL
local function ShotsOn()
    return ns.Get("autoShots") ~= "OFF"
end

local function Snap()
    pcall(Screenshot)
    After(UI_RESTORE, RestoreUI)
end

local function Capture(kind, description)
    if not ShotsOn() then return end
    local run = ns.GetActiveAdventure()
    if not run then return end
    if run.kind == "world" and kind ~= "mark" and ns.Get("autoShots") ~= "ALL" then return end
    -- 0.5.0: the per-run cap (Options > Full Log limits) stops new shots
    -- instead of dropping the oldest ones
    if not ns.RecordAdventureScreenshot(kind, description) then return end
    S.lastAt, S.ownAt = GetTime(), GetTime()
    -- out of combat the interface fades for a clean picture; in combat
    -- the shot is taken as it is
    if UIParent and not InCombat() then
        S.faded = true
        pcall(UIParent.SetAlpha, UIParent, 0)
        After(0.1, Snap)
    else
        Snap()
    end
end

-- Runs SHOT_DELAY after the first moment: waits out a loading screen
-- (up to LOADING_WAIT), then takes the best moment's shot.
local function Flush()
    local w = S.want
    if not w then return end
    if not ShotsOn() then S.want = nil; return end
    if S.loading then
        if GetTime() < w.giveUpAt and C_Timer and C_Timer.After then
            C_Timer.After(LOADING_RETRY, Flush)
        else
            S.want = nil
        end
        return
    end
    S.want = nil
    if TooSoon(w.kind) then return end
    Capture(w.kind, w.text)
end

function ns.RequestScreenshot(kind, description)
    if not ShotsOn() then return end
    if not (ns.GetActiveAdventure()) then return end
    if TooSoon(kind) then return end
    local rank = RANK[kind] or 0
    local w = S.want
    if w then
        if rank > w.rank then w.kind, w.text, w.rank = kind, description, rank end
        return
    end
    S.want = { kind = kind, text = description, rank = rank, giveUpAt = GetTime() + SHOT_DELAY + LOADING_WAIT }
    if C_Timer and C_Timer.After then C_Timer.After(SHOT_DELAY, Flush) end
end

-- 0.5.0: your own Print Screen shots join the run too (with a caption),
-- so the exporter can place them in the story
local function OnManualShot()
    if S.ownAt and (GetTime() - S.ownAt) < OWN_WINDOW then
        S.ownAt = nil
        if ns.ConfirmLastShot then ns.ConfirmLastShot() end
        return
    end
    local run = ns.GetActiveAdventure()
    if not run or run.paused then return end
    local foe = ns.FightCurrentFoe()
    local where = ns.GetCurrentWhere()
    local caption = foe and string.format("Fighting %s in %s", foe, where) or ("A view of " .. where)
    ns.RecordAdventureScreenshot("manual", caption)
end

ns.On({
    "SCREENSHOT_SUCCEEDED", "SCREENSHOT_FAILED",
    "PLAYER_REGEN_DISABLED", "LOADING_SCREEN_ENABLED", "LOADING_SCREEN_DISABLED",
}, function(event)
    if event == "SCREENSHOT_SUCCEEDED" then pcall(OnManualShot) end
    if event == "LOADING_SCREEN_ENABLED" then
        S.loading = true
        RestoreUI()
    elseif event == "LOADING_SCREEN_DISABLED" then
        S.loading = false
    else
        if event ~= "PLAYER_REGEN_DISABLED" then
            S.loading = false
        end
        RestoreUI()
    end
end)

-- 0.6.2: StoryViewer.html shows JPG and PNG. The game can also save TGA
-- (the screenshotFormat setting), which no browser can show.
local function GetShotFormat()
    local ok, v
    if C_CVar and C_CVar.GetCVar then ok, v = pcall(C_CVar.GetCVar, "screenshotFormat") end
    if not ok and GetCVar then ok, v = pcall(GetCVar, "screenshotFormat") end
    if not ok then v = nil end
    return type(v) == "string" and v:lower() or nil
end

-- true when the viewer can show the game's screenshots (unknown counts as yes)
function ns.ScreenshotFormatOK()
    local f = GetShotFormat()
    return f == nil or f == "" or f == "jpg" or f == "jpeg" or f == "png"
end

-- Switches the game's screenshots to JPG (the player clicks for this)
function ns.UseJpgScreenshots()
    if InCombat() then return false end
    local ok
    if C_CVar and C_CVar.SetCVar then ok = pcall(C_CVar.SetCVar, "screenshotFormat", "jpeg") end
    if not ok and SetCVar then ok = pcall(SetCVar, "screenshotFormat", "jpeg") end
    return ok and ns.ScreenshotFormatOK() or false
end
