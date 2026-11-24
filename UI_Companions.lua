local ADDON_NAME, ns = ...
local UI = ns.UI

-- =========================================================
-- COMPANIONS section: saved people and your permanent RP notes
-- =========================================================
local view = UI.NewSection("PLAYERS", "Companions", "Notes here go into every snapshot and story that mentions this person.")
UI.AddRailButton("PLAYERS", "Companions", UI.ICONS.PLAYERS, "People you RP with and your notes about them.")

local P = { rows = {} }
UI.companions = P

-- List on the left
P.list = CreateFrame("Frame", nil, view, UI.BACKDROP)
P.list:SetWidth(170)
P.list:SetPoint("TOPLEFT", 0, 0)
P.list:SetPoint("BOTTOMLEFT", 0, 0)
UI.ApplyPanelLook(P.list)

do
    local header = UI.Label(P.list, "|cffffd100Saved Companions|r")
    header:SetPoint("TOPLEFT", 10, -8)
end

P.listScroll = CreateFrame("ScrollFrame", "RPCopyPlayerListScroll", P.list, "UIPanelScrollFrameTemplate")
P.listScroll:SetPoint("TOPLEFT", 6, -26)
P.listScroll:SetPoint("BOTTOMRIGHT", -26, 6)

P.listChild = CreateFrame("Frame", nil, P.listScroll)
P.listChild:SetSize(136, 10)
P.listScroll:SetScrollChild(P.listChild)

-- Editor on the right
P.editor = CreateFrame("Frame", nil, view)
P.editor:SetPoint("TOPLEFT", P.list, "TOPRIGHT", 10, 0)
P.editor:SetPoint("BOTTOMRIGHT", 0, 0)

do
    local first = UI.Label(P.editor, "First Name:")
    first:SetPoint("TOPLEFT", 0, -4)
    local last = UI.Label(P.editor, "Last Name / Title:")
    last:SetPoint("TOPLEFT", 118, -4)
    local note = UI.Label(P.editor, "Permanent RP Note (yours, never overwritten):")
    note:SetPoint("TOPLEFT", 0, -48)
end

P.firstInput = CreateFrame("EditBox", "RPCopyPFirstInput", P.editor, "InputBoxTemplate")
P.firstInput:SetSize(104, 22)
P.firstInput:SetPoint("TOPLEFT", 6, -22)
P.firstInput:SetAutoFocus(false)

P.lastInput = CreateFrame("EditBox", "RPCopyPLastInput", P.editor, "InputBoxTemplate")
P.lastInput:SetHeight(22)
P.lastInput:SetPoint("TOPLEFT", 122, -22)
P.lastInput:SetPoint("TOPRIGHT", -2, -22)
P.lastInput:SetAutoFocus(false)

P.noteBg = CreateFrame("Frame", nil, P.editor, UI.BACKDROP)
P.noteBg:SetHeight(56)
P.noteBg:SetPoint("TOPLEFT", 0, -64)
P.noteBg:SetPoint("TOPRIGHT", 0, -64)
UI.ApplyDarkGlass(P.noteBg, 0.07, 0.09, 0.12, 0.92, 0.24, 0.28, 0.36, 0.80)

P.noteInput = CreateFrame("EditBox", "RPCopyPNoteInput", P.noteBg)
P.noteInput:SetMultiLine(true)
P.noteInput:SetFontObject(ChatFontNormal)
P.noteInput:SetSize(380, 46)
P.noteInput:SetPoint("TOPLEFT", 6, -5)
P.noteInput:SetAutoFocus(false)
P.noteInput:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

P.info = CreateFrame("Frame", nil, P.editor, UI.BACKDROP)
P.info:SetPoint("TOPLEFT", 0, -126)
P.info:SetPoint("BOTTOMRIGHT", 0, 30)
UI.ApplyDarkGlass(P.info, 0.07, 0.09, 0.12, 0.85, 0.22, 0.25, 0.32, 0.75)

local function InfoLine(x, y)
    local fs = P.info:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    fs:SetPoint("TOPLEFT", x, y)
    fs:SetJustifyH("LEFT")
    return fs
end

P.levelText = InfoLine(10, -8)
P.classText = InfoLine(145, -8)
P.raceText = InfoLine(10, -24)
P.guildText = InfoLine(10, -40)
P.seenText = InfoLine(10, -56)
P.chatText = InfoLine(10, -74)
P.chatText:SetJustifyV("TOP")

P.captureBtn = UI.CreateSleekButton(P.editor, 128, 22, "Capture Target")
P.captureBtn:SetPoint("BOTTOMLEFT", 0, 2)
P.captureBtn.tipTitle = "|cffffd100Capture Target|r"
P.captureBtn.tipText = "Save or update the player you target (or who last whispered you). Shortcut: Shift+C from the world."

P.saveBtn = UI.CreateSleekButton(P.editor, 116, 22, "Save Changes", "gold")
P.saveBtn:SetPoint("LEFT", P.captureBtn, "RIGHT", 6, 0)

P.delBtn = UI.CreateSleekButton(P.editor, 76, 22, "Delete", "danger")
P.delBtn:SetPoint("BOTTOMRIGHT", 0, 2)
P.delBtn.tipTitle = "|cffff6b6bDelete|r"
P.delBtn.tipText = "Click twice to delete this companion."

local function SetInfo(data)
    local function v(x, fallback) return (x and x ~= "") and x or fallback end
    if data then
        P.levelText:SetText("|cffffd100Level:|r " .. v(data.level, "-"))
        P.classText:SetText("|cffffd100Class:|r " .. ((data.class and data.class ~= "") and ns.ColorizeClass(data.class, data.class) or "-"))
        P.raceText:SetText("|cffffd100Race:|r " .. v(data.race, "-"))
        P.guildText:SetText("|cffffd100Guild:|r " .. v(data.guild, "-"))
        P.seenText:SetText("|cffffd100Last Seen:|r " .. v(data.lastSeen, "Never"))
        local chat = "None"
        if type(data.chatHistory) == "table" and #data.chatHistory > 0 then
            chat = "\n" .. table.concat(data.chatHistory, "\n")
        end
        P.chatText:SetText("|cffffd100Latest Chat (max 5):|r " .. chat)
    else
        P.levelText:SetText("|cffffd100Level:|r -")
        P.classText:SetText("|cffffd100Class:|r -")
        P.raceText:SetText("|cffffd100Race:|r -")
        P.guildText:SetText("|cffffd100Guild:|r -")
        P.seenText:SetText("|cffffd100Last Seen:|r -")
        P.chatText:SetText("|cffffd100Latest Chat (max 5):|r None")
    end
end

function UI.LoadPlayerIntoEditor(key)
    ns.state.selectedPlayerKey = key
    P.delBtn.armedAt = nil
    P.delBtn:SetText("Delete")
    local data = key and RPCopyDB.players[key]
    if data then
        local fName, lName = ns.SplitFullName(key)
        P.firstInput:SetText(fName)
        P.lastInput:SetText(lName)
        P.noteInput:SetText(data.note or "")
    else
        P.firstInput:SetText("")
        P.lastInput:SetText("")
        P.noteInput:SetText("")
    end
    SetInfo(data)
end

function UI.RefreshPlayersTab()
    UI.EnsureOptions()
    for _, rb in ipairs(P.rows) do rb:Hide() end
    local sorted = {}
    for k in pairs(RPCopyDB.players) do table.insert(sorted, k) end
    table.sort(sorted, function(a, b) return a:lower() < b:lower() end)

    for idx, pName in ipairs(sorted) do
        local rb = P.rows[idx]
        if not rb then
            rb = UI.CreateSleekButton(P.listChild, 134, 22, "")
            P.rows[idx] = rb
        end
        rb:SetPoint("TOPLEFT", 0, -(idx - 1) * 24)
        local data = RPCopyDB.players[pName]
        local hasNote = type(data) == "table" and data.note and data.note ~= ""
        rb:SetText(pName .. (hasNote and " |cffff80ab*|r" or ""))
        if ns.state.selectedPlayerKey == pName then rb:LockHighlight() else rb:UnlockHighlight() end
        rb:SetScript("OnClick", function()
            UI.LoadPlayerIntoEditor(pName)
            UI.RefreshPlayersTab()
        end)
        rb:Show()
    end
    P.listChild:SetHeight(math.max(10, #sorted * 24))
    if #sorted == 0 then
        UI.SetHint("No companions yet. Target a player and click Capture Target (or press Shift+C in the world).")
    end
end

function UI.OpenCompanion(key)
    UI.LoadPlayerIntoEditor(key)
    UI.RefreshPlayersTab()
end

P.captureBtn:SetScript("OnClick", function()
    local targetName = nil
    if UnitExists("target") and UnitIsPlayer("target") then
        targetName = ns.GetUnitFullName("target")
    elseif ns.state.lastDirectAuthor then
        targetName = ns.state.lastDirectAuthor
    end
    if not targetName then
        UI.SetStatus("Target a player (or get a whisper/say) first.", "error")
        return
    end
    local key, isNew = ns.SaveOrUpdatePlayer(targetName)
    if key then
        UI.SetStatus((isNew and "Added companion: " or "Updated companion: ") .. key, "good")
        UI.OpenCompanion(key)
    end
end)

P.saveBtn:SetScript("OnClick", function()
    UI.EnsureOptions()
    local newName = ns.JoinFullName(P.firstInput:GetText(), P.lastInput:GetText())
    if newName == "" then
        UI.SetStatus("Type a name first.", "error")
        return
    end
    local sel = ns.state.selectedPlayerKey
    local existing = (sel and RPCopyDB.players[sel]) or RPCopyDB.players[newName] or {}
    local updated = {
        note = ((P.noteInput:GetText() or ""):gsub("||", "|")):match("^%s*(.-)%s*$"),
        level = existing.level or "",
        race = existing.race or "",
        class = existing.class or "",
        guild = existing.guild or "",
        chatHistory = existing.chatHistory or {},
        lastSeen = (existing.lastSeen and existing.lastSeen ~= "") and existing.lastSeen or ns.NowStamp(),
    }
    local visUnit = ns.FindVisibleUnitForPlayer(newName)
    if visUnit then ns.CaptureVisibleUnitFields(visUnit, updated) end
    if sel and sel ~= newName then RPCopyDB.players[sel] = nil end
    RPCopyDB.players[newName] = updated
    UI.SetStatus("Saved companion: " .. newName, "good")
    UI.OpenCompanion(newName)
end)

P.delBtn:SetScript("OnClick", function(self)
    UI.EnsureOptions()
    local nameToDel = ns.state.selectedPlayerKey or ns.JoinFullName(P.firstInput:GetText(), P.lastInput:GetText())
    if nameToDel == "" or not RPCopyDB.players[nameToDel] then return end
    if not self.armedAt or GetTime() - self.armedAt > 4 then
        self.armedAt = GetTime()
        self:SetText("|cffff6b6bSure?|r")
        UI.SetStatus("Click Delete again to remove " .. nameToDel .. ".", "error")
        return
    end
    RPCopyDB.players[nameToDel] = nil
    UI.LoadPlayerIntoEditor(nil)
    UI.RefreshPlayersTab()
    UI.SetStatus("Deleted " .. nameToDel, "good")
end)

UI.SetSectionOnShow("PLAYERS", function()
    if UnitExists("target") and UnitIsPlayer("target") then
        local k = ns.FindPlayerKey(ns.GetUnitFullName("target"), true)
        if k then
            if RPCopyDB.autoUpdateKnown then ns.CaptureVisibleUnitFields("target", RPCopyDB.players[k]) end
            UI.LoadPlayerIntoEditor(k)
        end
    elseif ns.state.selectedPlayerKey and RPCopyDB.players[ns.state.selectedPlayerKey] then
        UI.LoadPlayerIntoEditor(ns.state.selectedPlayerKey)
    else
        UI.LoadPlayerIntoEditor(nil)
    end
    UI.RefreshPlayersTab()
end)

view:SetScript("OnHide", function()
    P.firstInput:ClearFocus()
    P.lastInput:ClearFocus()
    P.noteInput:ClearFocus()
end)

UI.AddReflow(function()
    local w = P.info:GetWidth()
    if w and w > 50 then
        P.raceText:SetWidth(w - 20)
        P.guildText:SetWidth(w - 20)
        P.seenText:SetWidth(w - 20)
        P.chatText:SetWidth(w - 20)
        P.chatText:SetHeight(math.max(60, (P.info:GetHeight() or 240) - 84))
    end
    w = P.noteBg:GetWidth()
    if w and w > 50 then P.noteInput:SetWidth(w - 12) end
end)
