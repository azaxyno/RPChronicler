local ADDON_NAME, ns = ...

-- =========================================================
-- Debug log (0.4.0)
-- A ring buffer of about 200 lines in RPCopyDB.debugLog. It holds RPCopy's
-- own Lua errors, blocked-action events and lifecycle events (load,
-- recording start / pause / end, imports). It never stores chat text.
-- "/rp debug" shows it with version, client and settings for bug reports.
-- =========================================================
local MAX_LINES = 200
local pending = {}   -- lines logged before SavedVariables are loaded
local ready = false

local function Stamp()
    return (date and date("%Y-%m-%d %H:%M:%S")) or tostring(time and time() or "")
end

local function Push(line)
    if ready and RPCopyDB then
        RPCopyDB.debugLog = type(RPCopyDB.debugLog) == "table" and RPCopyDB.debugLog or {}
        local log = RPCopyDB.debugLog
        table.insert(log, line)
        while #log > MAX_LINES do table.remove(log, 1) end
    else
        table.insert(pending, line)
        while #pending > MAX_LINES do table.remove(pending, 1) end
    end
end

-- kind: "info", "run", "error", "blocked", "copy", "verbose"
-- 0.5.0: Options > Debug can switch the log off (errors are still kept).
function ns.Debug(kind, msg)
    if kind == "verbose" and not (RPCopyDB and RPCopyDB.debugVerbose) then return end
    if RPCopyDB and RPCopyDB.debugEnabled == false and kind ~= "error" and kind ~= "blocked" then return end
    local text = tostring(msg or ""):gsub("[\r\n]+", " / ")
    if #text > 400 then text = text:sub(1, 400) .. "..." end
    Push(string.format("[%s] %s: %s", Stamp(), kind or "info", text))
end

-- Called once RPCopyDB is loaded (PLAYER_LOGIN): pending lines join the saved log
function ns.DebugReady()
    if ready then return end
    ready = true
    for _, line in ipairs(pending) do Push(line) end
    pending = {}
end

-- Lua errors: chain onto the current handler and only record ours.
-- The previous handler always runs, so BugSack and the default popup still work.
do
    local prev = geterrorhandler and geterrorhandler()
    if seterrorhandler and type(prev) == "function" then
        local ok = pcall(seterrorhandler, function(msg, ...)
            local text = tostring(msg or "")
            if text:find("RPCopy", 1, true) then
                pcall(ns.Debug, "error", text)
            end
            return prev(msg, ...)
        end)
        if not ok then ns.Debug("info", "could not hook the error handler") end
    end
end

-- Blocked actions that name RPCopy
do
    local f = CreateFrame("Frame")
    pcall(f.RegisterEvent, f, "ADDON_ACTION_BLOCKED")
    pcall(f.RegisterEvent, f, "ADDON_ACTION_FORBIDDEN")
    f:SetScript("OnEvent", function(_, event, addon, func)
        if tostring(addon or "") == ADDON_NAME then
            ns.Debug("blocked", event .. " " .. tostring(func or "?"))
        end
    end)
end

-- The text "/rp debug" shows
function ns.BuildDebugReport()
    local out = {}
    local function add(s) table.insert(out, s) end
    add("RPCopy debug report")
    add("Version: " .. tostring(ns.VERSION or "?"))
    if GetBuildInfo then
        local ok, ver, build, bdate, iface = pcall(GetBuildInfo)
        if ok then add(string.format("Client: %s (build %s, %s), interface %s", tostring(ver), tostring(build), tostring(bdate), tostring(iface))) end
    end
    if GetLocale then add("Locale: " .. tostring(GetLocale())) end
    local db = RPCopyDB or {}
    add(string.format("Settings: copy %s, instant in combat %s, auto-record %s, group prompt %s, login prompt %s, resume after reload %s, verbose %s",
        tostring(db.copyMode), tostring(db.instantInCombat), tostring(db.autoRecord), tostring(db.promptOnGroup),
        tostring(db.promptOnLogin), tostring(db.resumeAfterReload), tostring(db.debugVerbose)))
    local off = {}
    for k, v in pairs(db.logCats or {}) do
        if v == false then table.insert(off, k) end
    end
    table.sort(off)
    add("Full Log categories off: " .. (#off > 0 and table.concat(off, ", ") or "none"))
    local tabs = {}
    for _, t in ipairs(db.tabs or {}) do table.insert(tabs, tostring(t.id)) end
    add("Tabs: " .. table.concat(tabs, ", "))
    local run = ns.GetActiveAdventure and ns.GetActiveAdventure()
    add(string.format("Saved runs: %d | Live run: %s | Companions: %d",
        #(db.adventures or {}), run and ((run.paused and "paused" or "recording") .. " (" .. (run.kind or "?") .. ")") or "none",
        (function() local n = 0 for _ in pairs(db.players or {}) do n = n + 1 end return n end)()))
    -- 0.5.0: what Forever actually hands us for names (Companions 2.0 check)
    local st = ns.state or {}
    local tName, tFull, tPvp = "-", "-", "-"
    if UnitExists and UnitExists("target") then
        tName = ns.SafeStr and ns.SafeStr(UnitName and UnitName("target")) or "?"
        tFull = ns.SafeStr and ns.SafeStr(ns.GetUnitFullName and ns.GetUnitFullName("target")) or "?"
        tPvp = ns.SafeStr and ns.SafeStr(UnitPVPName and UnitPVPName("target")) or "?"
    end
    add(string.format("Names: last chat author raw [%s] | target UnitName [%s], full [%s], PVP name [%s]",
        tostring(st.lastRawAuthor or "-"), tostring(tName), tostring(tFull), tostring(tPvp)))
    local q = ns.UI and ns.UI.quick
    if q then
        add(string.format("Quick copy: key %s, quick %s, armed %s, last text length %s",
            tostring(db.quickCopyKey), tostring(db.quickCtrlC), tostring(q.isArmed), tostring(q.textLen or 0)))
    end
    add("")
    add("Log (oldest first):")
    local log = (ready and db.debugLog) or pending
    if type(log) ~= "table" or #log == 0 then
        add("(empty)")
    else
        for _, line in ipairs(log) do add(line) end
    end
    return table.concat(out, "\n")
end

ns.Debug("info", "files loaded")
