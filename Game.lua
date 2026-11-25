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
    return nil
end

-- The client's version and build, for the version stamp on runs and
-- stories ("1.60.1 (12345)"), or nil
function ns.ClientBuild()
    if not GetBuildInfo then return nil end
    local ok, ver, build = pcall(GetBuildInfo)
    if not ok then return nil end
    return tostring(ver or "?") .. " (" .. tostring(build or "?") .. ")"
end

-- An item link's quality (0 gray .. 5 legendary) and name. Links are
-- "|cffRRGGBB|Hitem:...|h[Name]|h|r" or, on newer clients, "|cnIQ3:...".
local QUALITY_HEX = { ["9d9d9d"] = 0, ["ffffff"] = 1, ["1eff00"] = 2, ["0070dd"] = 3, ["a335ee"] = 4, ["ff8000"] = 5 }
function ns.ItemQuality(link)
    if type(link) ~= "string" then return nil end
    local iq = link:match("|cnIQ(%d):")
    if iq then return tonumber(iq) end
    local hex = link:match("|c%x%x(%x%x%x%x%x%x)")
    return hex and QUALITY_HEX[hex:lower()] or nil
end
function ns.ItemName(link)
    return type(link) == "string" and link:match("|h%[(.-)%]|h") or nil
end

-- 0.6.3: what you wear right now, for the story cover (the model tries
-- it on) and the Full Log: { { slot, link, name, q }, ... }. Shirt and
-- tabard are kept for the cover; only green and better go in the log.
local GEAR_SLOTS = { 1, 2, 3, 15, 5, 4, 19, 9, 10, 6, 7, 8, 11, 12, 13, 14, 16, 17, 18 }
function ns.EquippedGear()
    local out = {}
    if not GetInventoryItemLink then return out end
    for _, slot in ipairs(GEAR_SLOTS) do
        local ok, link = pcall(GetInventoryItemLink, "player", slot)
        link = ok and ns.SafeStr(link) or nil
        if link and link:find("item:", 1, true) then
            table.insert(out, { slot = slot, link = link, name = ns.ItemName(link), q = ns.ItemQuality(link) })
        end
    end
    return out
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
