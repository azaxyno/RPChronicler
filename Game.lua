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

-- The instance you are in (0.6.4): its name and id from GetInstanceInfo,
-- or nil outside an instance. The zone text can still name the city
-- around the entrance (Orgrimmar for Ragefire Chasm), the instance info
-- can't.
function ns.InstanceInfo()
    local _, inside = ns.InstanceKind()
    if not inside or not GetInstanceInfo then return nil end
    local ok, name, _, _, _, _, _, _, id = pcall(GetInstanceInfo)
    if not ok then return nil end
    name = ns.SafeStr(name)
    if not name or name == "" then return nil end
    return name, ns.SafeNum(id)
end

-- 0.6.4: the Dungeon Journal id of the instance you are in, or nil
function ns.JournalInstance()
    if not (EJ_GetInstanceForMap and C_Map and C_Map.GetBestMapForUnit) then return nil end
    local okM, mapID = pcall(C_Map.GetBestMapForUnit, "player")
    mapID = okM and ns.SafeNum(mapID) or nil
    if not mapID then return nil end
    local okJ, id = pcall(EJ_GetInstanceForMap, mapID)
    id = okJ and ns.SafeNum(id) or nil
    return (id and id > 0) and id or nil
end

-- 0.6.4: the creature display ID of a unit (a boss), read through a
-- hidden model, so its story scene can show it later with no target.
-- nil when the client can't tell.
local probe
function ns.UnitDisplayId(unit)
    if not unit or not UnitExists(unit) then return nil end
    if probe == nil then
        local ok, m = pcall(CreateFrame, "PlayerModel", nil, UIParent)
        probe = (ok and m and m.GetDisplayInfo) and m or false
        if probe then probe:SetSize(1, 1) probe:SetPoint("TOPLEFT", UIParent, "BOTTOMRIGHT", 10, -10) probe:Hide() end
    end
    if not probe then return nil end
    if not pcall(probe.SetUnit, probe, unit) then return nil end
    local ok, id = pcall(probe.GetDisplayInfo, probe)
    pcall(probe.ClearModel, probe)
    id = ok and ns.SafeNum(id) or nil
    return (id and id > 0) and id or nil
end

-- 0.6.4: a boss's display ID from the Encounter Journal, by its
-- encounter ID or by the dungeon's and the boss's names (older runs kept
-- neither). Every call guarded; the journal's tier is put back after.
local ejCache = {}
function ns.JournalBossDisplay(instanceName, bossName, encounterID)
    if not EJ_GetCreatureInfo then return nil end
    local key = tostring(instanceName) .. "|" .. tostring(bossName) .. "|" .. tostring(encounterID)
    if ejCache[key] ~= nil then return ejCache[key] or nil end
    local function Creature(enc)
        local ok, _, _, _, _, display = pcall(EJ_GetCreatureInfo, 1, enc)
        display = ok and ns.SafeNum(display) or nil
        return (display and display > 0) and display or nil
    end
    local found = encounterID and Creature(encounterID) or nil
    if not found and type(instanceName) == "string" and type(bossName) == "string"
        and EJ_GetNumTiers and EJ_SelectTier and EJ_GetInstanceByIndex and EJ_GetEncounterInfoByIndex then
        local okT, oldTier = pcall(EJ_GetCurrentTier)
        local okN, tiers = pcall(EJ_GetNumTiers)
        local wantI, wantB = instanceName:lower(), bossName:lower()
        for t = 1, (okN and tonumber(tiers) or 0) do
            if found then break end
            pcall(EJ_SelectTier, t)
            for _, raid in ipairs({ false, true }) do
                if found then break end
                for i = 1, 200 do
                    local ok, id, name = pcall(EJ_GetInstanceByIndex, i, raid)
                    if not ok or not id then break end
                    if type(name) == "string" and name:lower() == wantI then
                        for j = 1, 40 do
                            local okE, eName, _, encID = pcall(EJ_GetEncounterInfoByIndex, j, id)
                            if not okE or not eName then break end
                            if eName:lower() == wantB then found = Creature(encID) break end
                        end
                        break
                    end
                end
            end
        end
        if okT and oldTier then pcall(EJ_SelectTier, oldTier) end
    end
    ejCache[key] = found or false
    return found
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

-- 0.6.4: an item's id, icon, class and subclass (weapon, armor ... and
-- which kind), for its icon and color in stories. nil when unknown.
function ns.ItemDetails(link)
    if type(link) ~= "string" then return nil end
    local id = tonumber(link:match("item:(%d+)"))
    if not id then return nil end
    local d = { id = id }
    if C_Item and C_Item.GetItemInfoInstant then
        local ok, _, _, _, _, icon, classID, subID = pcall(C_Item.GetItemInfoInstant, id)
        if ok then
            d.icon = ns.SafeNum(icon) or ns.SafeStr(icon)
            d.cls, d.sub = ns.SafeNum(classID), ns.SafeNum(subID)
        end
    end
    return d
end

-- 0.6.3: what you wear right now, for the story cover (the model tries
-- it on) and the Full Log: { { slot, link, name, q }, ... }. Shirt and
-- tabard are kept for the cover; only green and better go in the log.
local GEAR_SLOTS = { 1, 2, 3, 15, 5, 4, 19, 9, 10, 6, 7, 8, 11, 12, 13, 14, 16, 17, 18 }
-- 0.6.4: any unit (another player only right after an inspect)
function ns.UnitGear(unit)
    local out = {}
    if not GetInventoryItemLink then return out end
    for _, slot in ipairs(GEAR_SLOTS) do
        local ok, link = pcall(GetInventoryItemLink, unit, slot)
        link = ok and ns.SafeStr(link) or nil
        if link and link:find("item:", 1, true) then
            local d = ns.ItemDetails(link) or {}
            table.insert(out, { slot = slot, link = link, name = ns.ItemName(link), q = ns.ItemQuality(link),
                icon = d.icon, cls = d.cls, sub = d.sub })
        end
    end
    return out
end
function ns.EquippedGear() return ns.UnitGear("player") end

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
