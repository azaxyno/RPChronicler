local ADDON_NAME, ns = ...

-- =========================================================
-- Debug log (0.4.0)
-- A ring buffer of about 200 lines in RPChroniclerDB.debugLog. It holds RP Chronicler's
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
    if ready and RPChroniclerDB then
        RPChroniclerDB.debugLog = type(RPChroniclerDB.debugLog) == "table" and RPChroniclerDB.debugLog or {}
        local log = RPChroniclerDB.debugLog
        table.insert(log, line)
        while #log > MAX_LINES do table.remove(log, 1) end
    else
        table.insert(pending, line)
        while #pending > MAX_LINES do table.remove(pending, 1) end
    end
end

-- kind: "info", "run", "error", "blocked", "copy", "verbose"
-- 0.6.1: the log is always on. "verbose" lines are kept only while
-- "/rp debug verbose" is on for this session (ns.debugVerbose).
function ns.Debug(kind, msg)
    if kind == "verbose" and not ns.debugVerbose then return end
    local text = tostring(msg or ""):gsub("[\r\n]+", " / ")
    if #text > 400 then text = text:sub(1, 400) .. "..." end
    Push(string.format("[%s] %s: %s", Stamp(), kind or "info", text))
end

-- Called once RPChroniclerDB is loaded (PLAYER_LOGIN): pending lines join the saved log
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
            if text:find("RPChronicler", 1, true) then
                pcall(ns.Debug, "error", text)
            end
            return prev(msg, ...)
        end)
        if not ok then ns.Debug("info", "could not hook the error handler") end
    end
end

-- Blocked actions that name RP Chronicler
ns.On({ "ADDON_ACTION_BLOCKED", "ADDON_ACTION_FORBIDDEN" }, function(event, addon, func)
    if tostring(addon or "") == ADDON_NAME then
        ns.Debug("blocked", event .. " " .. tostring(func or "?"))
    end
end)

-- The text "/rp debug" shows
function ns.BuildDebugReport()
    local out = {}
    local function add(s) table.insert(out, s) end
    add("RP Chronicler debug report")
    add("Version: " .. tostring(ns.VERSION or "?"))
    if GetBuildInfo then
        local ok, ver, build, bdate, iface = pcall(GetBuildInfo)
        if ok then add(string.format("Client: %s (build %s, %s), interface %s", tostring(ver), tostring(build), tostring(bdate), tostring(iface))) end
    end
    if GetLocale then add("Locale: " .. tostring(GetLocale())) end
    local db = RPChroniclerDB or {}
    local set = {}
    for _, d in ipairs(ns.SETTINGS) do table.insert(set, d.key .. " " .. tostring(ns.Get(d.key))) end
    add("Settings: " .. table.concat(set, ", ") .. ", verbose " .. tostring(ns.debugVerbose and true or false))
    local off = {}
    for _, g in ipairs(ns.LOG_GROUPS) do
        if not (db.logGroups or {})[g.key] then table.insert(off, g.key) end
    end
    add("Full Log groups off: " .. (#off > 0 and table.concat(off, ", ") or "none"))
    local tabs = {}
    for _, t in ipairs(db.tabs or {}) do table.insert(tabs, tostring(t.id)) end
    add("Tabs: " .. table.concat(tabs, ", "))
    local run = ns.GetActiveAdventure()
    add(string.format("Saved runs: %d | Live run: %s | Companions: %d",
        #(db.adventures or {}), run and ((run.paused and "paused" or "recording") .. " (" .. (run.kind or "?") .. ")") or "none",
        (function() local n = 0 for _ in pairs(db.players or {}) do n = n + 1 end return n end)()))
    -- 0.5.0: what Forever actually hands us for names (Companions 2.0 check)
    local st = ns.state or {}
    local tName, tFull, tPvp = "-", "-", "-"
    if UnitExists and UnitExists("target") then
        tName = ns.SafeStr(UnitName and UnitName("target")) or "?"
        tFull = ns.SafeStr(ns.GetUnitFullName("target")) or "?"
        tPvp = ns.SafeStr(UnitPVPName and UnitPVPName("target")) or "?"
    end
    add(string.format("Names: last chat author raw [%s] | target UnitName [%s], full [%s], PVP name [%s]",
        tostring(st.lastRawAuthor or "-"), tostring(tName), tostring(tFull), tostring(tPvp)))
    local q = ns.UI and ns.UI.quick
    if q then
        add(string.format("Quick copy: quick %s, armed %s, last text length %s",
            tostring(ns.Get("quickCtrlC")), tostring(q.isArmed), tostring(q.textLen or 0)))
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
