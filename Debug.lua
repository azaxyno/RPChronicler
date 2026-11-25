local ADDON_NAME, ns = ...

-- =========================================================
-- Debug log (0.4.0)
-- A ring buffer of about 200 lines in RPChroniclerDB.debugLog. It holds RP Chronicler's
-- own Lua errors, blocked-action events and lifecycle events (load,
-- recording start / pause / end, imports). It never stores chat text.
-- "/rp debug" shows it with version, client and settings for bug reports.
-- =========================================================
local MAX_LINES = 200
local MAX_ERRORS = 20  -- 0.6.3: RP Chronicler's own errors kept in the saved file
local MAX_CHECKS = 10  -- 0.6.3: client checks kept (one per login)
local pending = {}   -- lines logged before SavedVariables are loaded
local pendingErrors = {}
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

-- 0.6.3: errors are also kept on their own (last 20, repeats counted),
-- with the addon version and client build, so a bug report needs no
-- second try: "/rp debug" or the saved file already holds them.
-- Options > Privacy > Keep error reports turns this off.
local function KeepError(e)
    if not (ready and RPChroniclerDB) then
        if #pendingErrors < MAX_ERRORS then table.insert(pendingErrors, e) end
        return
    end
    if RPChroniclerDB.keepErrors == false then return end
    RPChroniclerDB.errors = type(RPChroniclerDB.errors) == "table" and RPChroniclerDB.errors or {}
    local list = RPChroniclerDB.errors
    for _, old in ipairs(list) do
        if old.msg == e.msg and old.v == e.v then
            old.n = (old.n or 1) + 1
            old.at = e.at
            return
        end
    end
    table.insert(list, e)
    while #list > MAX_ERRORS do table.remove(list, 1) end
end

-- kind: "info", "run", "error", "blocked", "copy", "verbose"
-- 0.6.1: the log is always on. "verbose" lines are kept only while
-- "/rp debug verbose" is on for this session (ns.debugVerbose).
function ns.Debug(kind, msg)
    if kind == "verbose" and not ns.debugVerbose then return end
    local text = tostring(msg or ""):gsub("[\r\n]+", " / ")
    if #text > 400 then text = text:sub(1, 400) .. "..." end
    Push(string.format("[%s] %s: %s", Stamp(), kind or "info", text))
    if kind == "error" or kind == "blocked" then
        KeepError({ at = Stamp(), v = tostring(ns.VERSION or "?"), build = ns.ClientBuild and ns.ClientBuild() or nil,
            kind = kind, msg = text:sub(1, 300), stack = ns.lastErrorStack, n = 1 })
        ns.lastErrorStack = nil
    end
end

-- Called once RPChroniclerDB is loaded (PLAYER_LOGIN): pending lines join the saved log
function ns.DebugReady()
    if ready then return end
    ready = true
    for _, line in ipairs(pending) do Push(line) end
    pending = {}
    for _, e in ipairs(pendingErrors) do KeepError(e) end
    pendingErrors = {}
end

-- 0.6.3: what this client offers RP Chronicler, saved once per login (last
-- 10), so a bug report shows which game functions were missing
local CHECKS = {
    { "Addon messages", function() return C_ChatInfo and C_ChatInfo.SendAddonMessage end },
    { "Options > AddOns", function() return Settings and Settings.RegisterCanvasLayoutCategory end },
    { "Character model", function() return CreateFrame and pcall(CreateFrame, "DressUpModel") end },
    { "Timers", function() return C_Timer and C_Timer.After end },
    { "Quest log", function() return C_QuestLog and C_QuestLog.GetQuestObjectives end },
    { "Item links", function() return GetInventoryItemLink end },
    { "Screenshots", function() return Screenshot end },
    { "Keyboard listener", function() return CreateFrame and pcall(function() return CreateFrame("Frame").SetPropagateKeyboardInput end) end },
    { "Secret values", function() return issecretvalue or canaccessvalue end },
    { "Right-click menu", function() return Menu and Menu.ModifyMenu end },
}
function ns.RunClientCheck()
    local missing = {}
    for _, c in ipairs(CHECKS) do
        local ok, has = pcall(c[2])
        if not ok or not has then table.insert(missing, c[1]) end
    end
    if not RPChroniclerDB or RPChroniclerDB.keepErrors == false then return missing end
    RPChroniclerDB.clientChecks = type(RPChroniclerDB.clientChecks) == "table" and RPChroniclerDB.clientChecks or {}
    local list = RPChroniclerDB.clientChecks
    table.insert(list, { at = Stamp(), v = tostring(ns.VERSION or "?"), build = ns.ClientBuild and ns.ClientBuild() or nil,
        missing = #missing > 0 and table.concat(missing, ", ") or "none" })
    while #list > MAX_CHECKS do table.remove(list, 1) end
    return missing
end

-- Forget the saved errors and checks (/rp debug clear)
function ns.ClearDebugData()
    if not RPChroniclerDB then return end
    RPChroniclerDB.debugLog = {}
    RPChroniclerDB.errors = {}
    RPChroniclerDB.clientChecks = {}
end

-- Lua errors: chain onto the current handler and only record ours.
-- The previous handler always runs, so BugSack and the default popup still work.
do
    local prev = geterrorhandler and geterrorhandler()
    if seterrorhandler and type(prev) == "function" then
        local ok = pcall(seterrorhandler, function(msg, ...)
            local text = tostring(msg or "")
            if text:find("RPChronicler", 1, true) then
                if debugstack then
                    local ok2, st = pcall(debugstack, 3, 6, 0)
                    if ok2 and type(st) == "string" then ns.lastErrorStack = st:gsub("Interface[\\/]AddOns[\\/]", ""):sub(1, 400) end
                end
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
    -- 0.6.3: errors kept across sessions, and the last client checks
    local errs = type(db.errors) == "table" and db.errors or {}
    add("")
    add(string.format("Saved errors (%d, newest last):", #errs))
    if #errs == 0 then add("(none)") end
    for _, e in ipairs(errs) do
        add(string.format("[%s] v%s, client %s, %dx: %s", tostring(e.at), tostring(e.v), tostring(e.build or "?"), e.n or 1, tostring(e.msg)))
        if e.stack then add("    " .. tostring(e.stack):gsub("\n", "\n    ")) end
    end
    local checks = type(db.clientChecks) == "table" and db.clientChecks or {}
    local last = checks[#checks]
    if last then add(string.format("Client check (%s, v%s, client %s): missing %s", tostring(last.at), tostring(last.v), tostring(last.build or "?"), tostring(last.missing))) end
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
