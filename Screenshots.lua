-- Adapted from StoryTracker (MIT, Nine Point Labs)
-- v3.7.0 Fix: Use UIParent:SetAlpha(0/1) instead of UIParent:Hide()/Show()
-- to prevent ADDON_ACTION_BLOCKED errors on protected frames in combat.
local ADDON_NAME, ns = ...

local SHOT_DELAY = 0.75
local DEBOUNCE = 20
local LOADING_RETRY = 1
local LOADING_RETRIES = 10
local UI_RESTORE = 2.0
local OWN_WINDOW = 6   -- seconds: a SCREENSHOT_SUCCEEDED this soon after our own shot is ours

local pending, lastShotAt, loading, uiFaded = nil, nil, false, false
local ownShotAt = nil

-- When two moments land inside the delay, the bigger one labels the shot.
local PRIORITY = { story = 1, newzone = 2, quest = 3, mark = 4, levelup = 5, boss = 6 }

-- Boss kills and manual Mark Moment always get a shot, even right after
-- another one (the 20s debounce only thins out routine zone/quest shots).
local ALWAYS_SHOOT = { boss = true, mark = true }

local function InCombat()
    return (InCombatLockdown and InCombatLockdown())
        or (UnitAffectingCombat and UnitAffectingCombat("player")) or false
end

local function RestoreUI()
    if uiFaded and UIParent then
        uiFaded = false
        pcall(UIParent.SetAlpha, UIParent, 1)
    end
end

-- 0.6.1: one setting, autoShots: OFF (none), INSTANCE (dungeons and raids,
-- plus Mark Moment anywhere, since that is your own choice) or ALL
local function ShotsOn()
    return ns.Get("autoShots") ~= "OFF"
end

local function Capture(kind, description)
    if not ShotsOn() then return end
    local run = ns.GetActiveAdventure()
    if not run then return end
    if run.kind == "world" and kind ~= "mark" and ns.Get("autoShots") ~= "ALL" then return end
    -- 0.5.0: the per-run cap (Options > Full Log limits) stops new shots
    -- instead of dropping the oldest ones
    if not ns.RecordAdventureScreenshot(kind, description) then return end
    lastShotAt = GetTime()
    ownShotAt = GetTime()

    local function Fire()
        pcall(Screenshot)
        if C_Timer and C_Timer.After then
            C_Timer.After(UI_RESTORE, RestoreUI)
        else
            RestoreUI()
        end
    end

    -- SetAlpha(0) hides UI visuals without calling protected Hide() on UIParent
    if UIParent and not InCombat() then
        uiFaded = true
        pcall(UIParent.SetAlpha, UIParent, 0)
        if C_Timer and C_Timer.After then
            C_Timer.After(0.1, Fire)
        else
            Fire()
        end
    else
        Fire()
    end
end

local function FirePending(tries)
    local p = pending
    if not p then return end
    if not ShotsOn() then
        pending = nil
        return
    end
    if loading and tries < LOADING_RETRIES then
        if C_Timer and C_Timer.After then
            C_Timer.After(LOADING_RETRY, function() FirePending(tries + 1) end)
        end
        return
    end
    pending = nil
    if loading then return end
    if not ALWAYS_SHOOT[p.kind] and lastShotAt and (GetTime() - lastShotAt) < DEBOUNCE then return end
    Capture(p.kind, p.description)
end

function ns.RequestScreenshot(kind, description)
    if not ShotsOn() then return end
    if not (ns.GetActiveAdventure()) then return end
    if not ALWAYS_SHOOT[kind] and lastShotAt and (GetTime() - lastShotAt) < DEBOUNCE then return end
    if pending then
        if (PRIORITY[kind] or 0) > (PRIORITY[pending.kind] or 0) then
            pending.kind, pending.description = kind, description
        end
        return
    end
    pending = { kind = kind, description = description }
    if C_Timer and C_Timer.After then
        C_Timer.After(SHOT_DELAY, function() FirePending(0) end)
    end
end

-- 0.5.0: your own Print Screen shots join the run too (with a caption),
-- so the exporter can place them in the story
local function OnManualShot()
    if ownShotAt and (GetTime() - ownShotAt) < OWN_WINDOW then
        ownShotAt = nil
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
        loading = true
        RestoreUI()
    elseif event == "LOADING_SCREEN_DISABLED" then
        loading = false
    else
        if event ~= "PLAYER_REGEN_DISABLED" then
            loading = false
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
