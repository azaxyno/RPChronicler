local ADDON_NAME, ns = ...
local UI = ns.UI

-- =========================================================
-- COMPANIONS section (0.5.0, Companions 2.0): the people, NPCs and
-- companion pets you RP with. Full First + Last names, relationship and
-- tone, two notes ("Who they are", "Our history"), an Include switch
-- (Auto / Always / Never), first met, shared adventures, search and sort.
-- =========================================================
local view = UI.NewSection("PLAYERS", "Companions", "Your notes on people go into snapshots and Full Logs whenever they are in the scene.")
UI.AddRailButton("PLAYERS", "Companions", UI.ICONS.PLAYERS, "People you RP with and your notes about them.")

local P = { rows = {} }
UI.companions = P

local NOTE_MAX = 1000
local INCLUDE_ORDER = { "auto", "always", "never" }
local INCLUDE_LABEL = { auto = "Include: Auto", always = "Include: Always", never = "Include: Never" }
local SORTS = { "NAME", "SEEN", "MET" }
local SORT_LABEL = { NAME = "A-Z", SEEN = "Seen", MET = "Met" }

local function Trim(s) return ((s or ""):gsub("||", "|"):match("^%s*(.-)%s*$")) end

-- List on the left: search, sort, names
P.list = CreateFrame("Frame", nil, view, UI.BACKDROP)
P.list:SetWidth(156)
P.list:SetPoint("TOPLEFT", 0, 0)
P.list:SetPoint("BOTTOMLEFT", 0, 0)
UI.ApplyPanelLook(P.list)

do
    local header = UI.Label(P.list, "|cffffd100Companions|r")
    header:SetPoint("TOPLEFT", 10, -8)
end

P.search = CreateFrame("EditBox", "RPCopyPSearch", P.list, "InputBoxTemplate")
P.search:SetSize(92, 20)
P.search:SetPoint("TOPLEFT", 12, -26)
P.search:SetAutoFocus(false)
P.search:SetMaxLetters(40)
P.searchHint = P.search:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
P.searchHint:SetPoint("LEFT", 2, 0)
P.searchHint:SetText("Search")

P.sortBtn = UI.CreateSleekButton(P.list, 42, 20, "A-Z", "tool")
P.sortBtn:SetPoint("LEFT", P.search, "RIGHT", 4, 0)
P.sortBtn.tipTitle = "|cffffd100Sort|r"
P.sortBtn.tipText = "A-Z by name, Seen (last seen first) or Met (first met first)."

P.listScroll = CreateFrame("ScrollFrame", "RPCopyPlayerListScroll", P.list, "UIPanelScrollFrameTemplate")
P.listScroll:SetPoint("TOPLEFT", 6, -52)
P.listScroll:SetPoint("BOTTOMRIGHT", -26, 6)

P.listChild = CreateFrame("Frame", nil, P.listScroll)
P.listChild:SetSize(122, 10)
P.listScroll:SetScrollChild(P.listChild)

-- Editor on the right
P.editor = CreateFrame("Frame", nil, view)
P.editor:SetPoint("TOPLEFT", P.list, "TOPRIGHT", 10, 0)
P.editor:SetPoint("BOTTOMRIGHT", 0, 0)

local function Input(name, y, x, rightPad, maxLetters)
    local eb = CreateFrame("EditBox", name, P.editor, "InputBoxTemplate")
    eb:SetHeight(20)
    eb:SetPoint("TOPLEFT", x, y)
    eb:SetAutoFocus(false)
    eb:SetMaxLetters(maxLetters or 60)
    eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    return eb
end

do
    UI.Label(P.editor, "First name", "GameFontHighlightSmall"):SetPoint("TOPLEFT", 0, -2)
    UI.Label(P.editor, "Last name / title", "GameFontHighlightSmall"):SetPoint("TOPLEFT", 120, -2)
    UI.Label(P.editor, "Relationship", "GameFontHighlightSmall"):SetPoint("TOPLEFT", 0, -42)
    UI.Label(P.editor, "Tone", "GameFontHighlightSmall"):SetPoint("TOPLEFT", 160, -42)
end

P.firstInput = Input("RPCopyPFirstInput", -16, 6)
P.firstInput:SetWidth(104)
P.lastInput = Input("RPCopyPLastInput", -16, 126)
P.lastInput:SetPoint("RIGHT", P.editor, "RIGHT", -2, 0)
P.relInput = Input("RPCopyPRelInput", -56, 6, nil, 40)
P.relInput:SetWidth(144)
P.toneInput = Input("RPCopyPToneInput", -56, 166, nil, 40)
P.toneInput:SetPoint("RIGHT", P.editor, "RIGHT", -2, 0)
P.relInput.tip = "Rival, mentor, best friend, guildmate ..."

-- A scrolling note box with a letter cap
local function NoteBox(label, y, name)
    local lbl = UI.Label(P.editor, label, "GameFontHighlightSmall")
    lbl:SetPoint("TOPLEFT", 0, y)
    local count = P.editor:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    count:SetPoint("TOPRIGHT", P.editor, "TOPRIGHT", -4, y)
    local bg = CreateFrame("Frame", nil, P.editor, UI.BACKDROP)
    bg:SetHeight(50)
    bg:SetPoint("TOPLEFT", 0, y - 14)
    bg:SetPoint("TOPRIGHT", 0, y - 14)
    UI.ApplyDarkGlass(bg, 0.07, 0.09, 0.12, 0.92, 0.24, 0.28, 0.36, 0.80)
    local scroll = CreateFrame("ScrollFrame", name .. "Scroll", bg, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 6, -5)
    scroll:SetPoint("BOTTOMRIGHT", -26, 5)
    local eb = CreateFrame("EditBox", name, scroll)
    eb:SetMultiLine(true)
    eb:SetFontObject(ChatFontNormal)
    eb:SetMaxLetters(NOTE_MAX)
    eb:SetWidth(300)
    eb:SetHeight(40)
    eb:SetAutoFocus(false)
    eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    eb:SetScript("OnTextChanged", function(self)
        count:SetText(string.format("%d / %d", #(self:GetText() or ""), NOTE_MAX))
        scroll:UpdateScrollChildRect()
    end)
    if ScrollingEdit_OnCursorChanged then
        eb:SetScript("OnCursorChanged", ScrollingEdit_OnCursorChanged)
        eb:SetScript("OnUpdate", function(self, elapsed)
            if ScrollingEdit_OnUpdate then pcall(ScrollingEdit_OnUpdate, self, elapsed, scroll) end
        end)
    end
    bg:EnableMouse(true)
    bg:SetScript("OnMouseDown", function() eb:SetFocus() end)
    scroll:SetScrollChild(eb)
    eb.bg, eb.scroll = bg, scroll
    return eb
end

P.noteInput = NoteBox("|cffffd100Who they are|r |cff8f9ba8(personality, looks, voice)|r", -82, "RPCopyPNoteInput")
P.historyInput = NoteBox("|cffffd100Our history|r |cff8f9ba8(what you went through together)|r", -150, "RPCopyPHistoryInput")

P.info = CreateFrame("Frame", nil, P.editor, UI.BACKDROP)
P.info:SetPoint("TOPLEFT", 0, -220)
P.info:SetPoint("BOTTOMRIGHT", 0, 28)
UI.ApplyDarkGlass(P.info, 0.07, 0.09, 0.12, 0.85, 0.22, 0.25, 0.32, 0.75)

local function InfoLine(y)
    local fs = P.info:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    fs:SetPoint("TOPLEFT", 8, y)
    fs:SetPoint("RIGHT", P.info, "RIGHT", -8, 0)
    fs:SetJustifyH("LEFT")
    fs:SetWordWrap(false)
    return fs
end

P.whoText = InfoLine(-6)
P.guildText = InfoLine(-20)
P.metText = InfoLine(-34)
P.sharedText = InfoLine(-48)
P.chatText = P.info:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
P.chatText:SetPoint("TOPLEFT", 8, -62)
P.chatText:SetPoint("BOTTOMRIGHT", -8, 4)
P.chatText:SetJustifyH("LEFT")
P.chatText:SetJustifyV("TOP")

P.captureBtn = UI.CreateSleekButton(P.editor, 70, 22, "Capture")
P.captureBtn:SetPoint("BOTTOMLEFT", 0, 2)
P.captureBtn.tipTitle = "|cffffd100Capture Target|r"
P.captureBtn.tipText = "Save or update who you target: a player, an NPC or a companion pet (or who last whispered you). Shortcut: Shift+C from the world."

P.saveBtn = UI.CreateSleekButton(P.editor, 58, 22, "Save", "gold")
P.saveBtn:SetPoint("LEFT", P.captureBtn, "RIGHT", 4, 0)

P.includeBtn = UI.CreateSleekButton(P.editor, 112, 22, "Include: Auto", "tool")
P.includeBtn:SetPoint("LEFT", P.saveBtn, "RIGHT", 4, 0)
P.includeBtn.tipTitle = "|cffffd100Include in snapshots|r"
P.includeBtn.tipText = "Auto: when they are your target, in your group or in the copied chat. Always: in every snapshot. Never: never, and not in Full Logs."

P.delBtn = UI.CreateSleekButton(P.editor, 56, 22, "Delete", "danger")
P.delBtn:SetPoint("BOTTOMRIGHT", 0, 2)
P.delBtn.tipTitle = "|cffff6b6bDelete|r"
P.delBtn.tipText = "Click twice to delete this companion. Old Full Logs keep the notes they were recorded with."

local function V(x, fallback) return (x and x ~= "") and x or fallback end

local function SetInfo(key, data)
    if not data then
        P.whoText:SetText("|cff8f9ba8Type a name and click Save, or target someone and click Capture.|r")
        P.guildText:SetText("")
        P.metText:SetText("")
        P.sharedText:SetText("")
        P.chatText:SetText("")
        return
    end
    local cls = data.classFile or ns.ClassToken(data.class)
    local kind = (data.kind == "npc" and "NPC") or (data.kind == "pet" and "Companion pet") or nil
    local bits = {}
    if V(data.level) then table.insert(bits, "Lvl " .. data.level) end
    if V(data.race) then table.insert(bits, data.race) end
    if V(data.class) then table.insert(bits, cls and ns.ColorizeClass(data.class, cls) or data.class) end
    if kind then table.insert(bits, "|cffb39ddb" .. kind .. "|r") end
    P.whoText:SetText("|cffffd100Who:|r " .. (#bits > 0 and table.concat(bits, " ") or "-"))
    P.guildText:SetText("|cffffd100Guild:|r " .. V(data.guild, "-") .. "   |cffffd100Last seen:|r " .. V(data.lastSeen, "never"))
    local met = V(data.firstMet, "-")
    if V(data.firstMetPlace) then met = met .. " in " .. data.firstMetPlace end
    P.metText:SetText("|cffffd100First met:|r " .. met)
    local shared = ns.CompanionSharedAdventures(key)
    local names = {}
    for i, sa in ipairs(shared) do
        if i > 4 then break end
        table.insert(names, (sa.storyId and "|cffffd100*|r" or "") .. (sa.title or "Adventure"))
    end
    local more = (#shared > 4) and (" and " .. (#shared - 4) .. " more") or ""
    P.sharedText:SetText("|cffffd100Shared adventures:|r " .. (#names > 0 and (table.concat(names, ", ") .. more) or "none yet"))
    local chat = "none"
    if type(data.chatHistory) == "table" and #data.chatHistory > 0 then
        chat = "\n" .. table.concat(data.chatHistory, "\n")
    end
    P.chatText:SetText("|cffffd100Latest chat:|r " .. chat)
end

local function SyncInclude(data)
    local inc = (data and data.include) or "auto"
    P.includeBtn:SetText(INCLUDE_LABEL[inc] or INCLUDE_LABEL.auto)
    if data then P.includeBtn:Enable() else P.includeBtn:Disable() end
end

function UI.LoadPlayerIntoEditor(key)
    ns.state.selectedPlayerKey = key
    P.delBtn.armedAt = nil
    P.delBtn:SetText("Delete")
    local data = key and RPCopyDB.players[key]
    local fName, lName = "", ""
    if data then fName, lName = ns.SplitFullName(key) end
    P.firstInput:SetText(fName)
    P.lastInput:SetText(lName)
    P.relInput:SetText(data and data.relationship or "")
    P.toneInput:SetText(data and data.tone or "")
    P.noteInput:SetText(data and data.note or "")
    P.historyInput:SetText(data and data.history or "")
    SetInfo(key, data)
    SyncInclude(data)
end

local function SortKey(data, mode)
    if mode == "SEEN" then return tostring(data.lastSeen or "") end
    if mode == "MET" then return tostring(data.firstMet or "") end
    return ""
end

function UI.RefreshPlayersTab()
    UI.EnsureOptions()
    for _, rb in ipairs(P.rows) do rb:Hide() end
    local mode = ns.state.companionSort or "NAME"
    P.sortBtn:SetText(SORT_LABEL[mode] or "A-Z")
    local q = Trim(P.search:GetText()):lower()
    local sorted = {}
    for k, data in pairs(RPCopyDB.players) do
        if type(data) == "table" then
            local hay = (k .. " " .. (data.relationship or "") .. " " .. (data.guild or "")):lower()
            if q == "" or hay:find(q, 1, true) then table.insert(sorted, k) end
        end
    end
    table.sort(sorted, function(a, b)
        if mode ~= "NAME" then
            local ka, kb = SortKey(RPCopyDB.players[a], mode), SortKey(RPCopyDB.players[b], mode)
            if ka ~= kb then
                if mode == "SEEN" then return ka > kb end
                return ka < kb
            end
        end
        return a:lower() < b:lower()
    end)

    for idx, pName in ipairs(sorted) do
        local rb = P.rows[idx]
        if not rb then
            rb = UI.CreateSleekButton(P.listChild, 120, 22, "")
            P.rows[idx] = rb
        end
        rb:SetPoint("TOPLEFT", 0, -(idx - 1) * 24)
        local data = RPCopyDB.players[pName]
        local hasNote = (data.note or "") ~= "" or (data.history or "") ~= ""
        local tag = (data.kind == "npc" and " |cffb39ddb(NPC)|r") or (data.kind == "pet" and " |cffb39ddb(pet)|r") or ""
        rb:SetText(pName .. tag .. (hasNote and " |cffff80ab*|r" or ""))
        if ns.state.selectedPlayerKey == pName then rb:LockHighlight() else rb:UnlockHighlight() end
        rb:SetScript("OnClick", function()
            UI.LoadPlayerIntoEditor(pName)
            UI.RefreshPlayersTab()
        end)
        rb:Show()
    end
    P.listChild:SetHeight(math.max(10, #sorted * 24))
    if next(RPCopyDB.players) == nil then
        UI.SetHint("No companions yet. Target someone and click Capture (or press Shift+C in the world, or right-click a player).")
    end
end

function UI.OpenCompanion(key)
    UI.LoadPlayerIntoEditor(key)
    UI.RefreshPlayersTab()
end

P.search:SetScript("OnTextChanged", function(self)
    if (self:GetText() or "") == "" and not self:HasFocus() then P.searchHint:Show() else P.searchHint:Hide() end
    UI.RefreshPlayersTab()
end)
P.search:SetScript("OnEditFocusGained", function() P.searchHint:Hide() end)
P.search:SetScript("OnEditFocusLost", function(self)
    if (self:GetText() or "") == "" then P.searchHint:Show() end
end)
P.search:SetScript("OnEscapePressed", function(self)
    self:SetText("")
    self:ClearFocus()
end)

P.sortBtn:SetScript("OnClick", function()
    local idx = 1
    for i, k in ipairs(SORTS) do if k == (ns.state.companionSort or "NAME") then idx = i end end
    ns.state.companionSort = SORTS[(idx % #SORTS) + 1]
    UI.RefreshPlayersTab()
end)

P.includeBtn:SetScript("OnClick", function()
    local key = ns.state.selectedPlayerKey
    local data = key and RPCopyDB.players[key]
    if not data then return end
    local idx = 1
    for i, k in ipairs(INCLUDE_ORDER) do if k == (data.include or "auto") then idx = i end end
    data.include = INCLUDE_ORDER[(idx % #INCLUDE_ORDER) + 1]
    SyncInclude(data)
end)

P.captureBtn:SetScript("OnClick", function()
    local name, unit
    if UnitExists("target") then
        name, unit = ns.UnitCompanionName("target"), "target"
    elseif ns.state.lastDirectAuthor then
        name = ns.state.lastDirectAuthor
    end
    if not name then
        UI.SetStatus("Target someone (or get a whisper/say) first.", "error")
        return
    end
    local key, isNew = ns.SaveOrUpdatePlayer(name, unit)
    if key then
        UI.SetStatus((isNew and "Added companion: " or "Updated companion: ") .. key, "good")
        UI.OpenCompanion(key)
    end
end)

P.saveBtn:SetScript("OnClick", function()
    UI.EnsureOptions()
    local newName = ns.JoinFullName(Trim(P.firstInput:GetText()), Trim(P.lastInput:GetText()))
    if newName == "" then
        UI.SetStatus("Type a name first.", "error")
        return
    end
    local sel = ns.state.selectedPlayerKey
    local entry = sel and RPCopyDB.players[sel]
    if entry then
        -- A rename never overwrites another companion (any case)
        local ok, res = ns.RenameCompanion(sel, newName)
        if not ok then
            UI.SetStatus(res, "error")
            return
        end
        newName = res
    else
        for k in pairs(RPCopyDB.players) do
            if k:lower() == newName:lower() then
                UI.SetStatus("A companion named " .. k .. " already exists. Pick them in the list to edit.", "error")
                return
            end
        end
        entry = ns.NewCompanionEntry("player")
        RPCopyDB.players[newName] = entry
    end
    entry.relationship = Trim(P.relInput:GetText())
    entry.tone = Trim(P.toneInput:GetText())
    entry.note = Trim(P.noteInput:GetText()):sub(1, NOTE_MAX)
    entry.history = Trim(P.historyInput:GetText()):sub(1, NOTE_MAX)
    if (entry.lastSeen or "") == "" then entry.lastSeen = ns.NowStamp() end
    local visUnit = ns.FindVisibleUnitForPlayer(newName)
    if visUnit then ns.CaptureVisibleUnitFields(visUnit, entry) end
    UI.SetStatus("Saved companion: " .. newName, "good")
    UI.OpenCompanion(newName)
end)

P.delBtn:SetScript("OnClick", function(self)
    UI.EnsureOptions()
    local nameToDel = ns.state.selectedPlayerKey
    if not nameToDel or not RPCopyDB.players[nameToDel] then return end
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
    local k = UnitExists("target") and ns.CompanionByName(ns.UnitCompanionName("target"))
    if k then
        if RPCopyDB.autoUpdateKnown then ns.CaptureVisibleUnitFields("target", RPCopyDB.players[k]) end
        UI.LoadPlayerIntoEditor(k)
    elseif ns.state.selectedPlayerKey and RPCopyDB.players[ns.state.selectedPlayerKey] then
        UI.LoadPlayerIntoEditor(ns.state.selectedPlayerKey)
    else
        UI.LoadPlayerIntoEditor(nil)
    end
    UI.RefreshPlayersTab()
end)

view:SetScript("OnHide", function()
    for _, eb in ipairs({ P.firstInput, P.lastInput, P.relInput, P.toneInput, P.noteInput, P.historyInput, P.search }) do
        eb:ClearFocus()
    end
end)

UI.AddReflow(function()
    for _, eb in ipairs({ P.noteInput, P.historyInput }) do
        local w = eb.scroll:GetWidth()
        if w and w > 50 then eb:SetWidth(w) end
    end
end)
