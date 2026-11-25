local ADDON_NAME, ns = ...
local UI = ns.UI

-- =========================================================
-- STORY BOOK (0.5.0: its own section, right below Adventures)
-- A library of every imported story: a large reader, the details parsed
-- from the story (title, instance, duration, zone, date, party, stats,
-- chapters), Share as plain text, Edit Details, Re-Import, Delete and a
-- jump to the recording while it still exists. Stories live in
-- RPChroniclerDB.stories, so deleting a recording never deletes its story.
-- =========================================================
local B = { cards = {} }
UI.storyBook = B
local root = UI.NewSection("BOOK", "Story Book", "The stories your AI wrote from your runs.")
UI.AddRailButton("BOOK", "Story Book", UI.ICONS.STORY, "Read, share and edit the stories your AI wrote from your runs.")

local function StoryList()
    return ns.GetStories()
end

local function SelectedStory(list)
    for _, st in ipairs(list) do
        if st.id == ns.state.bookStoryId then return st end
    end
    if list[1] then ns.state.bookStoryId = list[1].id end
    return list[1]
end

-- Opens the Story Book, on a story when given
function UI.OpenStoryBook(storyId)
    if storyId then ns.state.bookStoryId = storyId end
    if not UI.frame:IsShown() then
        RPChronicler_Open("", "BOOK")
    elseif ns.state.section ~= "BOOK" then
        UI.ShowSection("BOOK")
    else
        UI.RefreshStoryBook()
    end
end

-- Left: the library
B.list = CreateFrame("Frame", nil, root, UI.BACKDROP)
B.list:SetWidth(200)
B.list:SetPoint("TOPLEFT", 0, 0)
B.list:SetPoint("BOTTOMLEFT", 0, 0)
UI.ApplyStoryTomeLook(B.list)

do
    local header = UI.Label(B.list, "|cffffd100Story Book|r")
    header:SetPoint("TOPLEFT", 10, -8)
end

B.importBtn = UI.CreateSleekButton(B.list, 180, 22, "Import Story from AI", "gold")
B.importBtn:SetPoint("BOTTOM", 0, 8)
B.importBtn:SetIcon(UI.ICONS.STORY, 14)
B.importBtn.tipTitle = "|cffffd100Import Story from AI|r"
B.importBtn.tipText = "Paste the colored story your AI wrote and pick the run it belongs to."

B.listScroll = CreateFrame("ScrollFrame", "RPChroniclerBookListScroll", B.list, "UIPanelScrollFrameTemplate")
B.listScroll:SetPoint("TOPLEFT", 6, -26)
B.listScroll:SetPoint("BOTTOMRIGHT", -26, 36)
B.listChild = CreateFrame("Frame", nil, B.listScroll)
B.listChild:SetSize(166, 10)
B.listScroll:SetScrollChild(B.listChild)

-- Right: header, tools, reader
B.right = CreateFrame("Frame", nil, root)
B.right:SetPoint("TOPLEFT", B.list, "TOPRIGHT", 10, 0)
B.right:SetPoint("BOTTOMRIGHT", 0, 0)

B.head = CreateFrame("Frame", nil, B.right, UI.BACKDROP)
B.head:SetHeight(70)
B.head:SetPoint("TOPLEFT", 0, 0)
B.head:SetPoint("TOPRIGHT", 0, 0)
UI.ApplyStoryTomeLook(B.head)

do
    local function HeadLine(template, y, size)
        local fs = B.head:CreateFontString(nil, "OVERLAY", template)
        fs:SetPoint("TOPLEFT", 10, y)
        fs:SetPoint("RIGHT", -10, 0)
        fs:SetJustifyH("LEFT")
        fs:SetWordWrap(false)
        if size then pcall(fs.SetFont, fs, "Fonts\\FRIZQT__.TTF", size, "") end
        return fs
    end
    B.title = HeadLine("GameFontNormalLarge", -7, 15)
    B.meta = HeadLine("GameFontHighlightSmall", -27)
    B.party = HeadLine("GameFontHighlightSmall", -40)
    B.stats = HeadLine("GameFontHighlightSmall", -53)
end

B.shareBtn = UI.CreateSleekButton(B.right, 56, 22, "Share", "gold")
B.shareBtn:SetPoint("TOPLEFT", 0, -76)
B.shareBtn.tipTitle = "|cffffd100Share|r"
B.shareBtn.tipText = "Copy the story as clean plain text, for Discord or a forum post."
B.editBtn = UI.CreateSleekButton(B.right, 58, 22, "Details")
B.editBtn:SetPoint("LEFT", B.shareBtn, "RIGHT", 4, 0)
B.editBtn.tipTitle = "|cffffd100Edit Details|r"
B.editBtn.tipText = "Change the title, instance, zone, duration, date or party shown here."
B.reimportBtn = UI.CreateSleekButton(B.right, 72, 22, "Re-Import")
B.reimportBtn:SetPoint("LEFT", B.editBtn, "RIGHT", 4, 0)
B.reimportBtn.tipTitle = "|cffffd100Re-Import|r"
B.reimportBtn.tipText = "Replace this story with a new one. Details you edited by hand are kept."
B.recBtn = UI.CreateSleekButton(B.right, 74, 22, "Recording", "tool")
B.recBtn:SetPoint("LEFT", B.reimportBtn, "RIGHT", 4, 0)
B.recBtn.tipTitle = "|cffffd100Recording|r"
B.recBtn.tipText = "Open the run this story was written from (Summary and Full Log), while the recording still exists."
B.delBtn = UI.CreateSleekButton(B.right, 56, 22, "Delete", "danger")
B.delBtn:SetPoint("TOPRIGHT", 0, -76)
B.delBtn.tipTitle = "|cffff6b6bDelete Story|r"
B.delBtn.tipText = "Click twice. Removes the story only; the recording stays."

-- 0.5.0: a dismissible tip on making HTML pages outside the game
B.tip = CreateFrame("Frame", nil, B.right, UI.BACKDROP)
B.tip:SetHeight(58)
B.tip:SetPoint("TOPLEFT", 0, -102)
B.tip:SetPoint("TOPRIGHT", 0, -102)
UI.ApplyDarkGlass(B.tip, 0.10, 0.09, 0.06, 0.92, 0.60, 0.48, 0.22, 0.70)
do
    local t = B.tip:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    t:SetPoint("TOPLEFT", 8, -5)
    t:SetPoint("BOTTOMRIGHT", -30, 5)
    t:SetJustifyH("LEFT")
    t:SetJustifyV("TOP")
    t:SetText("|cffffd100Web pages with screenshots:|r |cffd7c4a3get |cfff5e6c8Export_Stories.bat|cffd7c4a3 from |cfff5e6c8github.com/azaxyno/RPChronicler/releases|cffd7c4a3 " ..
        "(CurseForge downloads leave it out) and put it in Interface\\AddOns\\RPChronicler. /reload or log out so the game saves your stories, then double-click it. " ..
        "The pages appear in the |cfff5e6c8RP Chronicler Stories|cffd7c4a3 folder of _forever_.|r")
    local x = UI.CreateSleekButton(B.tip, 20, 18, "x", "danger")
    x:SetPoint("TOPRIGHT", -5, -5)
    x.tipTitle = "|cffffd100Hide this tip|r"
    x.tipText = "Bring it back in Options > Stories & Export."
    x:SetScript("OnClick", function()
        RPChroniclerDB.exportTip = false
        UI.RefreshStoryBook()
    end)
end

-- The reader (warm parchment)
B.readBg = CreateFrame("Frame", nil, B.right, UI.BACKDROP)
B.readBg:SetPoint("TOPLEFT", 0, -104)
B.readBg:SetPoint("BOTTOMRIGHT", 0, 0)
UI.ApplyStoryTomeLook(B.readBg)

do
    local inner = CreateFrame("Frame", nil, B.readBg, UI.BACKDROP)
    inner:SetPoint("TOPLEFT", 5, -5)
    inner:SetPoint("BOTTOMRIGHT", -5, 5)
    UI.ApplyDarkGlass(inner, 0.11, 0.08, 0.06, 0.82, 0.82, 0.65, 0.30, 0.50)

    B.scroll = CreateFrame("ScrollFrame", "RPChroniclerBookReadScroll", inner, "UIPanelScrollFrameTemplate")
    B.scroll:SetPoint("TOPLEFT", 14, -12)
    B.scroll:SetPoint("BOTTOMRIGHT", -28, 12)
    B.child = CreateFrame("Frame", nil, B.scroll)
    B.child:SetSize(320, 240)
    B.scroll:SetScrollChild(B.child)

    B.text = B.child:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    B.text:SetPoint("TOPLEFT", 2, -2)
    B.text:SetWidth(316)
    B.text:SetJustifyH("LEFT")
    B.text:SetJustifyV("TOP")
    B.text:SetSpacing(5)
    B.text:SetTextColor(0.95, 0.92, 0.86)
    B.text:SetShadowOffset(1, -1)
    B.text:SetShadowColor(0, 0, 0, 0.95)
    pcall(B.text.SetFont, B.text, "Fonts\\FRIZQT__.TTF", 14, "")
end

-- Empty state: how to make a story
B.empty = CreateFrame("Frame", nil, root, UI.BACKDROP)
B.empty:SetPoint("TOPLEFT", B.list, "TOPRIGHT", 10, 0)
B.empty:SetPoint("BOTTOMRIGHT", 0, 0)
UI.ApplyStoryTomeLook(B.empty)
B.empty:Hide()

do
    local e = B.empty
    local book = e:CreateTexture(nil, "ARTWORK")
    book:SetSize(36, 36)
    book:SetPoint("TOPLEFT", 16, -16)
    book:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    book:SetTexture(UI.ICONS.STORY)

    local heading = e:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    heading:SetPoint("TOPLEFT", book, "TOPRIGHT", 10, -2)
    heading:SetPoint("RIGHT", e, "RIGHT", -16, 0)
    heading:SetJustifyH("LEFT")
    heading:SetText("|cffffd100Your Story Book is empty|r")
    pcall(heading.SetFont, heading, "Fonts\\FRIZQT__.TTF", 15, "")

    local subHeading = e:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    subHeading:SetPoint("TOPLEFT", book, "TOPRIGHT", 10, -21)
    subHeading:SetPoint("TOPRIGHT", e, "TOPRIGHT", -16, -37)
    subHeading:SetJustifyH("LEFT")
    subHeading:SetText("|cffd7c4a3Turn a recorded run into a colored Warcraft story.|r")

    local steps = e:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    steps:SetPoint("TOPLEFT", 18, -70)
    steps:SetPoint("TOPRIGHT", -18, -70)
    steps:SetJustifyH("LEFT")
    steps:SetSpacing(4)
    steps:SetText(
        "|cffffd100How to make a story:|r\n" ..
        "|cfff5e6c81. One time:|r copy a story template below into your AI and make the storyteller skill.\n" ..
        "   |cffffd100Dungeon/Raid Story|r for instance runs, |cffffd100Adventure Story|r for the open world.\n" ..
        "|cfff5e6c82. Copy the run:|r in Recordings open |cff69ccf0Full Log|r, click |cffffd100Select All|r, press |cffffd100Ctrl+C|r.\n" ..
        "|cfff5e6c83. Import:|r paste the log into your AI, copy its story, and click |cffffd100Import Story|r.\n\n" ..
        "|cff9aa5b4Which AI? See the Requirements section of the README.|r")

    local dBtn = UI.CreateSleekButton(e, 150, 24, "Dungeon/Raid Template", "gold")
    dBtn:SetPoint("BOTTOMLEFT", 18, 14)
    dBtn:SetScript("OnClick", function() if UI.OpenSkillTemplateModal then UI.OpenSkillTemplateModal("STORY") end end)
    local aBtn = UI.CreateSleekButton(e, 140, 24, "Adventure Template", "gold")
    aBtn:SetPoint("LEFT", dBtn, "RIGHT", 6, 0)
    aBtn:SetScript("OnClick", function() if UI.OpenSkillTemplateModal then UI.OpenSkillTemplateModal("ADVENTURE") end end)
    local iBtn = UI.CreateSleekButton(e, 110, 24, "Import Story", "good")
    iBtn:SetPoint("LEFT", aBtn, "RIGHT", 6, 0)
    iBtn:SetScript("OnClick", function() UI.OpenStoryImportModal(nil) end)
end

local function UpdateReaderHeight()
    local h = B.text:GetStringHeight() or 200
    B.child:SetHeight(math.max(230, h + 32))
    B.scroll:UpdateScrollChildRect()
end

local function MakeCard(parent)
    local card = CreateFrame("Button", nil, parent, UI.BACKDROP)
    card:SetSize(166, 44)
    UI.ApplyDarkGlass(card, 0.12, 0.09, 0.06, 0.92, 0.40, 0.31, 0.16, 0.85)
    card.icon = card:CreateTexture(nil, "ARTWORK")
    card.icon:SetSize(30, 30)
    card.icon:SetPoint("LEFT", 7, 0)
    card.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    card.titleLbl = card:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    card.titleLbl:SetPoint("TOPLEFT", card.icon, "TOPRIGHT", 6, -1)
    card.titleLbl:SetPoint("RIGHT", -4, 0)
    card.titleLbl:SetJustifyH("LEFT")
    card.titleLbl:SetWordWrap(false)
    card.subLbl = card:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    card.subLbl:SetPoint("TOPLEFT", card.icon, "TOPRIGHT", 6, -16)
    card.subLbl:SetPoint("RIGHT", -4, 0)
    card.subLbl:SetJustifyH("LEFT")
    card.subLbl:SetWordWrap(false)
    card:SetScript("OnEnter", function(self)
        self:SetBackdropBorderColor(0.90, 0.73, 0.32, 0.95)
        if self.info then UI.Tooltip(self, "|cffffd100" .. self.info.name .. "|r", self.info.date, self.info.party) end
    end)
    card:SetScript("OnLeave", function(self)
        UI.HideTooltip()
        if self.isSelected then
            self:SetBackdropBorderColor(0.90, 0.73, 0.32, 0.95)
        else
            self:SetBackdropBorderColor(0.40, 0.31, 0.16, 0.85)
        end
    end)
    return card
end

function UI.RefreshStoryBook()
    local list = StoryList()
    for _, c in ipairs(B.cards) do c:Hide() end
    for idx, adv in ipairs(list) do
        local card = B.cards[idx]
        if not card then
            card = MakeCard(B.listChild)
            B.cards[idx] = card
        end
        local info = ns.GetBookInfo(adv)
        card.info = info
        card:SetPoint("TOPLEFT", 0, -(idx - 1) * 48)
        card.icon:SetTexture(ns.GetAdventureIcon(adv))
        card.titleLbl:SetText("|cfff5e6c8" .. info.title .. "|r")
        card.subLbl:SetText("|cffb0a080" .. ((info.instance ~= "" and info.instance) or ns.GetRunKindLabel(adv)) .. " - " .. (info.date or "") .. "|r")
        local sel = (adv.id == ns.state.bookStoryId)
        card.isSelected = sel
        if sel then
            card:SetBackdropColor(0.22, 0.16, 0.08, 0.96)
            card:SetBackdropBorderColor(0.90, 0.73, 0.32, 0.95)
        else
            card:SetBackdropColor(0.12, 0.09, 0.06, 0.92)
            card:SetBackdropBorderColor(0.40, 0.31, 0.16, 0.85)
        end
        card:SetScript("OnClick", function()
            ns.state.bookStoryId = adv.id
            B.delBtn.armedAt = nil
            UI.RefreshStoryBook()
        end)
        card:Show()
    end
    B.listChild:SetHeight(math.max(10, #list * 48))

    local adv = SelectedStory(list)
    if not adv then
        B.right:Hide()
        B.empty:Show()
        return
    end
    B.empty:Hide()
    B.right:Show()
    B.delBtn:SetText("Delete")
    -- Re-check the selection highlight now the default pick is known
    for idx, card in ipairs(B.cards) do
        if card:IsShown() and list[idx] and list[idx].id == adv.id and not card.isSelected then
            card.isSelected = true
            card:SetBackdropColor(0.22, 0.16, 0.08, 0.96)
            card:SetBackdropBorderColor(0.90, 0.73, 0.32, 0.95)
        end
    end

    local info = ns.GetBookInfo(adv)
    B.title:SetText("|cffffd100" .. info.name .. "|r")
    local metaParts = { ns.GetRunKindLabel(adv) }
    if info.zone ~= "" and info.zone ~= info.instance then table.insert(metaParts, info.zone) end
    table.insert(metaParts, info.duration)
    table.insert(metaParts, info.date)
    B.meta:SetText("|cffd7c4a3" .. table.concat(metaParts, "  -  ") .. "|r")
    B.party:SetText("|cffb0a080Party:|r |cfff5e6c8" .. ((info.party ~= "" and info.party) or "solo") .. "|r")
    B.stats:SetText(ns.GetBookStats(info))
    if ns.StoryRun(adv) then B.recBtn:Enable() else B.recBtn:Disable() end

    B.readBg:ClearAllPoints()
    B.readBg:SetPoint("BOTTOMRIGHT", 0, 0)
    if RPChroniclerDB.exportTip ~= false then
        B.tip:Show()
        B.readBg:SetPoint("TOPLEFT", 0, -164)
    else
        B.tip:Hide()
        B.readBg:SetPoint("TOPLEFT", 0, -104)
    end

    local shown = ns.NormalizeStoryText(adv.story)
    if ns.CleanStoryHeader then shown = ns.CleanStoryHeader(shown) end
    -- 0.5.3: auto-color the stored text once (markers kept), so the
    -- exporter gets the same colors after a /reload
    if RPChroniclerDB.autoColorStory ~= false and ns.AutoColorStory and adv.autoColored ~= ns.AUTOCOLOR_VERSION then
        local ok, colored = pcall(ns.AutoColorStory, shown, adv)
        if ok and type(colored) == "string" then
            shown = colored
            adv.story = colored
            adv.autoColored = ns.AUTOCOLOR_VERSION
        end
    end
    shown = ns.StripShotMarkers(shown)
    -- 0.5.2: an open-world story written with an old template ends with a
    -- dungeon footer of zeros; hide that line (the stats are shown above)
    if adv.kind == "world" then
        shown = shown:gsub("\n[^\n]*Bosses:%s*0%s*|*%s*Wipes:%s*0[^\n]*%s*$", "")
    end
    B.text:SetText(ns.DecorateStoryBosses(shown, adv))
    UpdateReaderHeight()
    if B.shownId ~= adv.id then
        B.shownId = adv.id
        B.scroll:SetVerticalScroll(0)
    end
    if C_Timer and C_Timer.After then C_Timer.After(0, UpdateReaderHeight) end
end

local function CurrentBookRun()
    return SelectedStory(StoryList())
end

B.importBtn:SetScript("OnClick", function()
    UI.OpenStoryImportModal(nil)
end)
B.reimportBtn:SetScript("OnClick", function()
    local st = CurrentBookRun()
    if st then UI.OpenStoryImportModal(nil, st) end
end)
B.recBtn:SetScript("OnClick", function()
    local run = ns.StoryRun(CurrentBookRun())
    if run then UI.OpenRecording(run.id, "SUMMARY") end
end)
B.shareBtn:SetScript("OnClick", function()
    local adv = CurrentBookRun()
    if not adv then return end
    local info = ns.GetBookInfo(adv)
    local header = info.name .. "\n" .. table.concat({ ns.GetRunKindLabel(adv), info.duration, info.date }, " | ") .. "\n\n"
    UI.ShowCopyBox("|cffffd100Share:|r |cfff5e6c8" .. info.name .. "|r",
        "|cffb0bac5Plain text with no color codes, ready for Discord or a forum.|r",
        header .. ns.GetStoryPlainText(adv))
end)
B.delBtn:SetScript("OnClick", function(self)
    local adv = CurrentBookRun()
    if not adv then return end
    if not self.armedAt or GetTime() - self.armedAt > 4 then
        self.armedAt = GetTime()
        self:SetText("|cffff6b6bSure?|r")
        UI.SetStatus("Click Delete again to remove this story. The recording stays.", "error")
        return
    end
    self.armedAt = nil
    ns.DeleteStory(adv.id)
    ns.state.bookStoryId = nil
    UI.SetStatus("Story deleted. The recording is still in Recordings.", "good")
    UI.RefreshStoryBook()
end)

-- =========================================================
-- Edit Details modal
-- =========================================================
do
    local FIELDS = {
        { key = "title", label = "Title" },
        { key = "instance", label = "Dungeon / region" },
        { key = "zone", label = "Zone" },
        { key = "duration", label = "Duration" },
        { key = "date", label = "Date" },
        { key = "party", label = "Party" },
    }
    local f = CreateFrame("Frame", "RPChroniclerBookDetailsFrame", UIParent, UI.BACKDROP)
    f:SetSize(420, 70 + #FIELDS * 28)
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 30)
    f:SetFrameStrata("FULLSCREEN_DIALOG")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:Hide()
    UI.ApplyStoryTomeLook(f)

    local title = UI.Label(f, "|cffffd100Story Details|r", "GameFontNormal")
    title:SetPoint("TOPLEFT", 14, -12)
    local hint = UI.Label(f, "|cff9aa5b4Empty a box to use the run's own data again.|r", "GameFontHighlightSmall")
    hint:SetPoint("TOPLEFT", 14, -28)

    local boxes = {}
    for i, fd in ipairs(FIELDS) do
        local lbl = UI.Label(f, "|cffd7c4a3" .. fd.label .. "|r", "GameFontHighlightSmall")
        lbl:SetPoint("TOPLEFT", 14, -50 - (i - 1) * 28)
        local bg = CreateFrame("Frame", nil, f, UI.BACKDROP)
        bg:SetSize(270, 22)
        bg:SetPoint("TOPLEFT", 130, -46 - (i - 1) * 28)
        UI.ApplyDarkGlass(bg, 0.06, 0.05, 0.04, 0.96, 0.72, 0.56, 0.26, 0.75)
        local eb = CreateFrame("EditBox", nil, bg)
        eb:SetPoint("TOPLEFT", 6, -2)
        eb:SetPoint("BOTTOMRIGHT", -6, 2)
        eb:SetAutoFocus(false)
        eb:SetFontObject(ChatFontNormal)
        eb:SetMaxLetters(160)
        eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
        eb:SetScript("OnTabPressed", function()
            local nextBox = boxes[(i % #FIELDS) + 1]
            if nextBox then nextBox:SetFocus() end
        end)
        boxes[i] = eb
    end

    local save = UI.CreateSleekButton(f, 90, 24, "Save", "gold")
    save:SetPoint("BOTTOMLEFT", 14, 12)
    local cancel = UI.CreateSleekButton(f, 80, 24, "Cancel", "danger")
    cancel:SetPoint("BOTTOMRIGHT", -14, 12)
    cancel:SetScript("OnClick", function() f:Hide() end)

    save:SetScript("OnClick", function()
        local adv = f.advId and ns.FindStory(f.advId)
        if adv then
            local before = ns.GetBookInfo(adv)
            for i, fd in ipairs(FIELDS) do
                local v = (boxes[i]:GetText() or ""):gsub("||", "|"):match("^%s*(.-)%s*$")
                if v ~= tostring(before[fd.key] or "") then ns.SetBookField(adv.id, fd.key, v) end
            end
        end
        f:Hide()
        UI.RefreshStoryBook()
        UI.SetStatus("Story details saved.", "good")
    end)

    B.editBtn:SetScript("OnClick", function()
        local adv = CurrentBookRun()
        if not adv then return end
        f.advId = adv.id
        local info = ns.GetBookInfo(adv)
        for i, fd in ipairs(FIELDS) do boxes[i]:SetText(tostring(info[fd.key] or "")) end
        f:Show()
        boxes[1]:SetFocus()
    end)
end

UI.SetSectionOnShow("BOOK", function() UI.RefreshStoryBook() end)
root:SetScript("OnHide", function() UI.HideTooltip() end)

UI.AddReflow(function()
    local w = B.scroll:GetWidth()
    if w and w > 50 then
        B.child:SetWidth(w)
        B.text:SetWidth(w - 4)
        UpdateReaderHeight()
    end
end)
