local ADDON_NAME, ns = ...

-- =========================================================
-- Game (0.6.1): the game reads several modules need, in one place, and
-- the one event router. Each read guards its API and goes through
-- ns.SafeStr / ns.SafeNum once, so a Forever client change has one place
-- to fix.
-- =========================================================

-- Health percent (0 to 100) that survives the modern engine: plain
-- numbers first, then UnitHealthPercent where it exists. nil when secret.
function ns.HealthPct(unit)
    if not unit or not UnitExists(unit) then return nil end
    local hp = ns.SafeNum(UnitHealth(unit))
    local hpMax = ns.SafeNum(UnitHealthMax(unit))
    if hp and hpMax and hpMax > 0 then
        return math.floor((hp / hpMax) * 100)
    end
    if UnitHealthPercent then
        local ok, v = pcall(UnitHealthPercent, unit)
        v = ok and ns.SafeNum(v) or nil
        if v then
            if v <= 1 and v ~= math.floor(v) then v = v * 100 end
            return math.floor(v)
        end
    end
    return nil
end

-- Where the player is: "dungeon", "raid" or "world", plus whether they
-- are inside any instance. IsInInstance is called on its own line: "a and
-- IsInInstance()" keeps only its first value, so the type would be lost.
function ns.InstanceKind()
    if not IsInInstance then return "world", false end
    local inside, instanceType = IsInInstance()
    if inside and instanceType == "raid" then return "raid", true end
    if inside and instanceType == "party" then return "dungeon", true end
    return "world", inside and true or false
end

-- Calls fn(unit) for every group member other than you: raid1-40 in a
-- raid (you left out), party1-4 otherwise
function ns.ForEachGroupUnit(fn)
    if IsInRaid and IsInRaid() then
        for i = 1, 40 do
            local u = "raid" .. i
            if UnitExists(u) and not (UnitIsUnit and UnitIsUnit(u, "player")) then fn(u) end
        end
    else
        for i = 1, 4 do
            local u = "party" .. i
            if UnitExists(u) then fn(u) end
        end
    end
end

-- Your own full name ("Aloria Sunwhisper"), or your short name
function ns.PlayerName()
    return ns.GetUnitFullName("player") or ns.StripRealm(UnitName("player")) or "You"
end

function ns.SpellName(id)
    if type(id) ~= "number" then return nil end
    if C_Spell and C_Spell.GetSpellName then
        local ok, n = pcall(C_Spell.GetSpellName, id)
        if ok and ns.SafeStr(n) then return ns.SafeStr(n) end
    end
    if GetSpellInfo then
        local ok, n = pcall(GetSpellInfo, id)
        if ok and ns.SafeStr(n) then return ns.SafeStr(n) end
    end
    return nil
end

-- =========================================================
-- Event router: ns.On(event or { events }, fn). One frame for the whole
-- addon; handlers run in the order they were added (toc load order), each
-- in a pcall, so one failing handler never stops the others and its error
-- lands in the debug log. fn(event, ...) gets the event name first.
-- =========================================================
do
    local frame = CreateFrame("Frame", "RPChroniclerEventFrame")
    local handlers = {}

    function ns.On(events, fn)
        if type(events) == "string" then events = { events } end
        for _, ev in ipairs(events) do
            if not handlers[ev] then
                handlers[ev] = {}
                pcall(frame.RegisterEvent, frame, ev)
            end
            table.insert(handlers[ev], fn)
        end
    end

    frame:SetScript("OnEvent", function(_, event, ...)
        for _, fn in ipairs(handlers[event] or {}) do
            local ok, err = pcall(fn, event, ...)
            if not ok then ns.Debug("error", event .. ": " .. tostring(err)) end
        end
    end)
end
