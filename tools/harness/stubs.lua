-- generic forgiving stubs
local magicMT = {}
local function magic() return setmetatable({}, magicMT) end
local NUMERIC = { GetStringWidth=1, GetWidth=1, GetHeight=1, GetStringHeight=1, GetNumLines=1, GetLeft=1, GetTop=1, GetRight=1, GetBottom=1, GetEffectiveScale=1, GetScale=1, GetFrameLevel=1, GetNumPoints=1, GetCursorPosition=1, GetValue=1, GetAlpha=1 }
magicMT.__index = function(t, k)
  if k == "GetText" then return function(self) return rawget(self, "_text") or "" end end
  if k == "SetText" then return function(self, v) rawset(self, "_text", v) end end
  if k == "IsShown" or k == "IsVisible" then return function(self) return rawget(self, "_shown") or false end end
  if k == "Show" then return function(self) rawset(self, "_shown", true) end end
  if k == "Hide" then return function(self) rawset(self, "_shown", false) end end
  if k == "SetScript" then return function(self, ev, fn) local s = rawget(self, "_scripts") or {}; rawset(self, "_scripts", s); s[ev] = fn end end
  if k == "GetScript" then return function(self, ev) local s = rawget(self, "_scripts") or {}; return s[ev] end end
  if k == "HookScript" then return function(self, ev, fn) local s = rawget(self, "_scripts") or {}; rawset(self, "_scripts", s); local old = s[ev]; s[ev] = function(...) if old then old(...) end fn(...) end end end
  if k == "RegisterEvent" then return function(self, ev) local e = rawget(self, "_events") or {}; rawset(self, "_events", e); e[ev] = true; table.insert(ALL_EVENT_FRAMES, self) end end
  if k == "GetName" then return function(self) return rawget(self, "_name") end end
  if k == "GetObjectType" then return function() return "Frame" end end
  if k == "GetChecked" then return function(self) return rawget(self, "_checked") or false end end
  if k == "SetChecked" then return function(self, v) rawset(self, "_checked", v) end end
  if k == "SetSize" then return function(self, w, h) rawset(self, "_w", w); rawset(self, "_h", h) end end
  if k == "SetWidth" then return function(self, w) rawset(self, "_w", w) end end
  if k == "SetHeight" then return function(self, h) rawset(self, "_h", h) end end
  if k == "GetWidth" then return function(self) return rawget(self, "_w") or 100 end end
  if k == "GetHeight" then return function(self) return rawget(self, "_h") or 100 end end
  if k == "SetPoint" then return function(self, ...) local p = rawget(self, "_points") or {}; rawset(self, "_points", p); table.insert(p, { ... }) end end
  if k == "ClearAllPoints" then return function(self) rawset(self, "_points", {}) end end
  if k == "SetTexture" then return function(self, t) rawset(self, "_tex", t); return true end end
  if k == "SetVertexColor" then return function(self, ...) rawset(self, "_color", { ... }) end end
  if k == "SetFrameLevel" then return function(self, l) rawset(self, "_level", l) end end
  if NUMERIC[k] then return function() return 100 end end
  if k:match("^Is") or k:match("^Has") then return function() return false end end
  if type(k) == "string" and k:match("^[a-z_]") then return nil end
  return magic()
end
magicMT.__call = function() return magic() end
magicMT.__add = function() return 0 end
magicMT.__sub = function() return 0 end
magicMT.__mul = function() return 0 end
magicMT.__div = function() return 0 end
magicMT.__concat = function(a, b) return (type(a)=="table" and "" or tostring(a)) .. (type(b)=="table" and "" or tostring(b)) end
MAGIC = magic
ALL_EVENT_FRAMES = {}

function CreateFrame(kind, name, parent, template)
  local f = magic()
  rawset(f, "_name", name)
  if name then _G[name] = f end
  return f
end
UIParent = magic(); GameTooltip = magic(); WorldFrame = magic(); Minimap = magic()
UISpecialFrames = {}
SlashCmdList = {}
StaticPopupDialogs = {}
hooksecurefunc = function() end
NOW = 1795600000
function time(t) if t then return os.time(t) end return NOW end
date = os.date
function GetTime() return NOW - 1795000000 end
TIMERS = {}
C_Timer = { After = function(sec, fn) table.insert(TIMERS, fn) end, NewTicker = function() return magic() end, NewTimer = function() return magic() end }
function RunTimers() local t = TIMERS; TIMERS = {}; for _, fn in ipairs(t) do fn() end end
C_ChatInfo = { RegisterAddonMessagePrefix = function() return true end, SendAddonMessage = function() end }
function GetAddOnMetadata(a, k) if k == "Version" then return "0.6.4" end end
C_AddOns = { GetAddOnMetadata = GetAddOnMetadata }
function InCombatLockdown() return false end
function issecretvalue() return false end
function GetBuildInfo() return "1.60.1", "123", "", 16001 end
function UnitAffectingCombat() return false end
function IsControlKeyDown() return true end
function GetLocale() return "enUS" end
function GetCVar() return "jpeg" end
function SetCVar() end
function GetScreenWidth() return 1920 end
function GetScreenHeight() return 1080 end
function PlaySound() end
function GetInventoryItemLink() return nil end
function GetNumGroupMembers() local n=0 for k in pairs(UNITS) do if k:match("^party") then n=n+1 end end return n end
-- units
UNITS = {}
function UnitExists(u) return UNITS[u] ~= nil end
function UnitIsPlayer(u) return UNITS[u] ~= nil and not UNITS[u].npc end
function UnitName(u) local x = UNITS[u]; return x and x.short end
function UnitFullName(u) local x = UNITS[u]; return x and (x.full or x.short) end
UnitPVPName = nil
function UnitGUID(u) local x = UNITS[u]; return x and x.guid end
function UnitLevel(u) local x = UNITS[u]; return x and x.level or 0 end
function UnitClass(u) local x = UNITS[u]; if x then return x.class, x.class:upper() end end
function UnitRace(u) local x = UNITS[u]; if x and x.race then return x.raceName or "Race", x.raceName or "Race", x.race end return "Orc", "Orc", 2 end
function UnitSex(u) local x = UNITS[u]; if x and x.sex then return x.sex end return 2 end
function UnitGroupRolesAssigned(u) local x = UNITS[u]; return x and x.role or "NONE" end
function UnitIsVisible(u) local x = UNITS[u]; return x ~= nil and x.visible ~= false end
function UnitIsUnit(a, b) return a == b or (UNITS[a] and UNITS[b] and UNITS[a].guid == UNITS[b].guid) or false end
function UnitHealth() return 100 end
function UnitHealthMax() return 100 end
function UnitIsDead() return false end
function UnitIsDeadOrGhost() return false end
function UnitCanAttack() return false end
function UnitClassification() return "normal" end
function UnitIsConnected() return true end
function UnitPower() return 100 end
function UnitPowerMax() return 100 end
function UnitBuff() return nil end
function UnitAura() return nil end
function GetGuildInfo(u) return nil end
function IsInRaid() return false end
function IsInGroup() for k in pairs(UNITS) do if k:match("^party%d") then return true end end return false end
INSTANCE = nil  -- { name=, type=, id= }
ZONE = "Orgrimmar"
function IsInInstance() if INSTANCE then return true, INSTANCE.type end return false, "none" end
function GetInstanceInfo() if INSTANCE then return INSTANCE.name, INSTANCE.type, 1, "Normal", 5, 0, false, INSTANCE.id end return ZONE, "none", 0, "", 0, 0, false, 1 end
function GetRealZoneText() return ZONE end
function GetZoneText() return ZONE end
function GetSubZoneText() return "" end
function GetMinimapZoneText() return "" end
function GetSpecialization() return nil end
function GetShapeshiftForm() return 0 end
function GetMoney() return 0 end
print = function(...) local t = {} for i=1,select("#",...) do t[#t+1]=tostring(select(i,...)) end PRINTED = (PRINTED or "") .. table.concat(t, " ") .. "\n" end
-- unknown globals: nil (code guards APIs)

-- fires a game event at every frame that registered it
function Fire(ev, ...)
  local done = {}
  for _, f in ipairs(ALL_EVENT_FRAMES) do
    if not done[f] and rawget(f, "_events")[ev] then
      done[f] = true
      local s = rawget(f, "_scripts") and rawget(f, "_scripts").OnEvent
      if s then s(f, ev, ...) end
    end
  end
end

-- SavedVariables-style dump of a table
function Serialize(v, indent)
  indent = indent or ""
  local t = type(v)
  if t == "string" then return string.format("%q", v)
  elseif t == "number" or t == "boolean" then return tostring(v)
  elseif t ~= "table" then return "nil" end
  local keys = {}
  for k in pairs(v) do if type(k) == "string" or type(k) == "number" then table.insert(keys, k) end end
  table.sort(keys, function(a, b)
    if type(a) == type(b) then return a < b end
    return type(a) == "number"
  end)
  local out = { "{\n" }
  local inner = indent .. "\t"
  for _, k in ipairs(keys) do
    local key = type(k) == "number" and ("[" .. k .. "]") or ("[" .. string.format("%q", k) .. "]")
    table.insert(out, inner .. key .. " = " .. Serialize(v[k], inner) .. ",\n")
  end
  table.insert(out, indent .. "}")
  return table.concat(out)
end
