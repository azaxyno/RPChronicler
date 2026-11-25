local ADDON_NAME, ns = ...

-- =========================================================
-- Update notices (0.6.3). Addons can't go online, so this works between
-- players: RP Chronicler sends ONLY its version number ("V 0.6.3") to your
-- group and guild through the game's addon messages, and when someone
-- else's copy reports a newer version it prints one chat line per session.
-- Nothing recorded is ever sent. Options > Privacy > Update notices (and
-- the first-run setup) turns it off; then nothing is sent or read.
-- =========================================================
local PREFIX = "RPCHRON"
local SEND_GAP = 60        -- seconds between two sends to the same channel
local REPLY_GAP = 300      -- seconds between answering older copies on a channel
local lastSent = {}
local lastReply = {}
local told = false
local registered = false

-- "0.6.3" -> 0, 6, 3 (missing parts are 0); nil when it is no version
local function Parts(v)
    if type(v) ~= "string" then return nil end
    local a, b, c = v:match("^(%d+)%.(%d+)%.?(%d*)$")
    if not a then return nil end
    return tonumber(a), tonumber(b), tonumber(c) or 0
end

-- 1 when a is newer than b, -1 when older, 0 when the same (or unreadable)
function ns.CompareVersions(a, b)
    local a1, a2, a3 = Parts(a)
    local b1, b2, b3 = Parts(b)
    if not a1 or not b1 then return 0 end
    if a1 ~= b1 then return a1 > b1 and 1 or -1 end
    if a2 ~= b2 then return a2 > b2 and 1 or -1 end
    if a3 ~= b3 then return a3 > b3 and 1 or -1 end
    return 0
end

local function On()
    return ns.Get("versionCheck") ~= false
end

local function Register()
    if registered then return true end
    if not (C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix and C_ChatInfo.SendAddonMessage) then return false end
    local ok = pcall(C_ChatInfo.RegisterAddonMessagePrefix, PREFIX)
    registered = ok and true or false
    return registered
end

-- The group channel you are in right now, or nil
local function GroupChannel()
    if IsInGroup and LE_PARTY_CATEGORY_INSTANCE and IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then return "INSTANCE_CHAT" end
    if IsInRaid and IsInRaid() then return "RAID" end
    if IsInGroup and IsInGroup() then return "PARTY" end
    return nil
end

local function Send(channel, gap)
    if not channel or not On() or not Register() then return end
    local now = GetTime and GetTime() or 0
    if lastSent[channel] and (now - lastSent[channel]) < (gap or SEND_GAP) then return end
    lastSent[channel] = now
    -- the version number and nothing else
    local ok = pcall(C_ChatInfo.SendAddonMessage, PREFIX, "V " .. tostring(ns.VERSION or "?"), channel)
    if not ok then ns.Debug("info", "version notice not sent on " .. channel) end
end

function ns.SendVersion()
    if IsInGuild and IsInGuild() then Send("GUILD") end
    Send(GroupChannel())
end

local function Heard(msg, channel)
    local v = type(msg) == "string" and msg:match("^V (%d+%.%d+%.?%d*)$")
    if not v then return end
    local cmp = ns.CompareVersions(v, ns.VERSION)
    if cmp > 0 and not told then
        told = true
        print(string.format("|cffffd100RP Chronicler|r Version |cff5cb85c%s|r is available (you have %s). Update on CurseForge.", v, tostring(ns.VERSION)))
        ns.Debug("info", "newer version seen: " .. v)
    elseif cmp < 0 and (channel == "GUILD" or channel == "PARTY" or channel == "RAID" or channel == "INSTANCE_CHAT") then
        -- an older copy: let it hear about ours (rarely, never in a loop)
        local now = GetTime and GetTime() or 0
        if not lastReply[channel] or (now - lastReply[channel]) > REPLY_GAP then
            lastReply[channel] = now
            Send(channel, 0)
        end
    end
end

ns.On({ "PLAYER_LOGIN", "GROUP_ROSTER_UPDATE", "CHAT_MSG_ADDON" }, function(event, prefix, msg, channel, sender)
    if not On() then return end
    if event == "PLAYER_LOGIN" then
        Register()
        -- wait for the guild roster and the group to be known
        if C_Timer and C_Timer.After then C_Timer.After(20, function() pcall(ns.SendVersion) end) end
    elseif event == "GROUP_ROSTER_UPDATE" then
        Send(GroupChannel())
    elseif event == "CHAT_MSG_ADDON" and prefix == PREFIX then
        local me = ns.StripRealm(UnitName and UnitName("player"))
        if me and ns.StripRealm(sender) == me then return end
        Heard(msg, channel)
    end
end)

-- Turning it on in Options or the setup sends the version once
ns.Listen("setting", function(key, v)
    if key == "versionCheck" and v then pcall(ns.SendVersion) end
end)
