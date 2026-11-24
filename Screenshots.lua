-- Adapted from StoryTracker (MIT, Nine Point Labs)
-- v3.7.0 Fix: Use UIParent:SetAlpha(0/1) instead of UIParent:Hide()/Show()
-- to prevent ADDON_ACTION_BLOCKED errors on protected frames in combat.
local ADDON_NAME, ns = ...

local SHOT_DELAY = 0.75
local DEBOUNCE = 20
local LOADING_RETRY = 1
local LOADING_RETRIES = 10
local UI_RESTORE = 2.0
local MAX_SHOTS = 12

local pending, lastShotAt, loading, uiFaded = nil, nil, false, false

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

local function Capture(kind, description)
    if not RPCopyDB or not RPCopyDB.autoScreenshots then return end
    local run = ns.GetActiveAdventure and ns.GetActiveAdventure()
    if not run then return end
    lastShotAt = GetTime()
    run.shots = run.shots or {}
    ns.PushBounded(run.shots, {
        at = time(),
        kind = kind,
        description = description,
        zone = ns.GetCurrentWhere(),
    }, MAX_SHOTS)

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
    if not RPCopyDB or not RPCopyDB.autoScreenshots then
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
    if not RPCopyDB or not RPCopyDB.autoScreenshots then return end
    if not (ns.GetActiveAdventure and ns.GetActiveAdventure()) then return end
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

local shotFrame = CreateFrame("Frame")
for _, ev in ipairs({
    "SCREENSHOT_SUCCEEDED", "SCREENSHOT_FAILED",
    "PLAYER_REGEN_DISABLED", "LOADING_SCREEN_ENABLED", "LOADING_SCREEN_DISABLED",
}) do
    pcall(shotFrame.RegisterEvent, shotFrame, ev)
end

shotFrame:SetScript("OnEvent", function(_, event)
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
