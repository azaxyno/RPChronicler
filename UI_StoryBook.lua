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
B.list:SetWidth(180)
B.list:SetPoint("TOPLEFT", 0, 0)
B.list:SetPoint("BOTTOMLEFT", 0, 0)
UI.ApplyStoryTomeLook(B.list)

do
    local header = UI.Label(B.list, "|cffffd100Story Book|r")
    header:SetPoint("TOPLEFT", 10, -8)
end

-- 0.6.1: one Import button, in the list header (the empty Story Book has
-- its own), so it never shows twice
B.importBtn = UI.CreateSleekButton(B.list, 64, 18, "+ Import", "gold")
B.importBtn:SetPoint("TOPRIGHT", -6, -5)
B.importBtn.tipTitle = "|cffffd100Import Story from AI|r"
B.importBtn.tipText = "Paste the colored story your AI wrote and pick the run it belongs to."

B.listScroll = CreateFrame("ScrollFrame", "RPChroniclerBookListScroll", B.list, "UIPanelScrollFrameTemplate")
B.listScroll:SetPoint("TOPLEFT", 6, -28)
B.listScroll:SetPoint("BOTTOMRIGHT", -26, 8)
-- the scroll bar only shows when the list is longer than the pane
B.listScroll.scrollBarHideable = true
B.listChild = CreateFrame("Frame", nil, B.listScroll)
B.listChild:SetSize(146, 10)
B.listScroll:SetScrollChild(B.listChild)

B.listEmpty = B.list:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
B.listEmpty:SetPoint("TOPLEFT", 10, -30)
B.listEmpty:SetPoint("RIGHT", B.list, "RIGHT", -10, 0)
B.listEmpty:SetJustifyH("LEFT")
B.listEmpty:SetText("|cffb0a080No stories yet.|r")

-- Shows the list's scroll bar only when the cards do not fit
local function SyncListScrollBar(contentH)
    local bar = B.listScroll.ScrollBar or _G["RPChroniclerBookListScrollScrollBar"]
    if not bar then return end
    local fits = contentH <= (B.listScroll:GetHeight() or 0) + 1
    if fits then
        B.listScroll:SetVerticalScroll(0)
        bar:Hide()
    else
        bar:Show()
    end
end

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

B.shareBtn = UI.CreateSleekButton(B.right, 52, 22, "Share", "gold")
B.shareBtn.tipTitle = "|cffffd100Share|r"
B.shareBtn.tipText = "Copy the story as clean plain text, for Discord or a forum post."
B.editBtn = UI.CreateSleekButton(B.right, 56, 22, "Details")
B.editBtn.tipTitle = "|cffffd100Edit Details|r"
B.editBtn.tipText = "Rename the story, or change the instance, zone, duration, date or party shown here."
B.reimportBtn = UI.CreateSleekButton(B.right, 68, 22, "Re-Import")
B.reimportBtn.tipTitle = "|cffffd100Re-Import|r"
B.reimportBtn.tipText = "Replace this story with a new one. Details you edited by hand are kept."
B.recBtn = UI.CreateSleekButton(B.right, 40, 22, "Run", "tool")
B.recBtn.tipTitle = "|cffffd100Open the Run|r"
B.recBtn.tipText = "Open the run this story was written from (Summary and Full Log), while the recording still exists."
B.delBtn = UI.CreateSleekButton(B.right, 54, 22, "Delete", "danger")
B.delBtn.tipTitle = "|cffff6b6bDelete Story|r"
B.delBtn.tipText = "Click twice. Removes the story only; the recording stays."

-- 0.5.0: a dismissible tip on reading stories outside the game.
-- 0.6.2: it points to StoryViewer.html, carries "Copy for viewer" for a
-- story the game hasn't saved yet, and offers JPG when screenshots are TGA.
B.tip = CreateFrame("Frame", nil, B.right, UI.BACKDROP)
B.tip:SetHeight(58)
B.tip:SetPoint("TOPLEFT", 0, -102)
B.tip:SetPoint("TOPRIGHT", 0, -102)
UI.ApplyDarkGlass(B.tip, 0.10, 0.09, 0.06, 0.92, 0.60, 0.48, 0.22, 0.70)
do
    local t = B.tip:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    t:SetPoint("TOPLEFT", 8, -5)
    t:SetPoint("RIGHT", -30, 0)
    t:SetJustifyH("LEFT")
    t:SetJustifyV("TOP")
    B.tipText = t
    local x = UI.CreateSleekButton(B.tip, 20, 18, "x", "danger")
    x:SetPoint("TOPRIGHT", -5, -5)
    x.tipTitle = "|cffffd100Hide this tip|r"
    x.tipText = "Bring it back in Options > AI & Stories."
    x:SetScript("OnClick", function()
        ns.Set("exportTip", false)
        UI.RefreshStoryBook()
    end)
    B.viewerBtn = UI.CreateSleekButton(B.tip, 110, 18, "Copy for viewer", "gold")
    UI.SetButtonLabels(B.viewerBtn, "Copy for viewer", "Copy")
    B.viewerBtn.tipTitle = "|cffffd100Copy for viewer|r"
    B.viewerBtn.tipText = "For a story you imported this session: copy it with Ctrl+C and paste it into StoryViewer.html. Older stories are already there."
    -- 0.6.3: the path to StoryViewer.html, ready to paste into a browser
    B.pathBtn = UI.CreateSleekButton(B.tip, 84, 18, "Viewer path", "tool")
    UI.SetButtonLabels(B.pathBtn, "Viewer path", "Path")
    B.pathBtn.tipTitle = "|cffffd100Where is StoryViewer.html?|r"
    B.pathBtn.tipText = "Shows its path, ready to copy into your browser's address bar."
    B.pathBtn:SetScript("OnClick", function() UI.ShowViewerPath() end)
    B.jpgBtn = UI.CreateSleekButton(B.tip, 70, 18, "Use JPG", "tool")
    B.jpgBtn.tipTitle = "|cffffd100Save screenshots as JPG|r"
    B.jpgBtn.tipText = "Your game saves screenshots as TGA, which browsers can't show. This switches the game's screenshot format to JPG."
    B.jpgBtn:SetScript("OnClick", function()
        if ns.UseJpgScreenshots() then
            UI.SetStatus("Screenshots are now saved as JPG.", "good")
        else
            UI.SetStatus("Couldn't change the screenshot format. Leave combat and try again.", "error")
        end
        UI.RefreshStoryBook()
    end)
end

-- 0.6.3: Viewer path box. RP Chronicler can't know where the game is
-- installed, so it never shows a guessed path as yours: StoryViewer.html
-- shows its own address with a Copy button, you paste it here once, and
-- from then on this box hands it back, ready for the address bar.
do
    local f = CreateFrame("Frame", "RPChroniclerViewerPathFrame", UIParent, UI.BACKDROP)
    f:SetSize(580, 170)
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 80)
    f:SetFrameStrata("FULLSCREEN_DIALOG")
    f:EnableMouse(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:Hide()
    UI.ApplyStoryTomeLook(f)
    if type(UISpecialFrames) == "table" then table.insert(UISpecialFrames, "RPChroniclerViewerPathFrame") end
    local title = UI.Label(f, "|cffffd100Open StoryViewer.html in your browser|r", "GameFontNormal")
    title:SetPoint("TOPLEFT", 14, -12)
    local sub = UI.Label(f, "", "GameFontHighlightSmall")
    sub:SetPoint("TOPLEFT", 14, -30)
    sub:SetPoint("RIGHT", f, "RIGHT", -14, 0)
    sub:SetJustifyH("LEFT")
    sub:SetJustifyV("TOP")
    sub:SetWordWrap(true)
    sub:SetSpacing(2)
    local closeX = UI.CreateSleekButton(f, 22, 20, "x", "danger")
    closeX:SetPoint("TOPRIGHT", -8, -8)
    closeX:SetScript("OnClick", function() f:Hide() end)
    local eb = CreateFrame("EditBox", "RPChroniclerViewerPathBox", f, "InputBoxTemplate")
    eb:SetHeight(22)
    eb:SetPoint("BOTTOMLEFT", 20, 40)
    eb:SetPoint("BOTTOMRIGHT", -16, 40)
    eb:SetAutoFocus(false)
    eb:SetMaxLetters(260)
    eb:SetFontObject(ChatFontNormal)
    local hint = eb:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("LEFT", 2, 0)
    hint:SetText("Paste the address StoryViewer.html shows (Ctrl+V)")
    local example = UI.Label(f, "", "GameFontHighlightSmall")
    example:SetPoint("BOTTOMLEFT", eb, "TOPLEFT", -4, 4)
    example:SetPoint("RIGHT", f, "RIGHT", -14, 0)
    example:SetWordWrap(false)
    local function Sync()
        local has = (eb:GetText() or ""):match("%S") ~= nil
        if has then hint:Hide() else hint:Show() end
    end
    eb:SetScript("OnEscapePressed", function() f:Hide() end)
    eb:SetScript("OnEnterPressed", function(self)
        self:SetText(ns.StoryViewerPath())
        self:HighlightText()
    end)
    eb:SetScript("OnTextChanged", function(self, userInput)
        if userInput then ns.SetStoryViewerPath(self:GetText()) end
        Sync()
    end)
    eb:SetScript("OnEditFocusLost", function(self)
        -- show the browser-ready form of what was pasted
        local saved = ns.StoryViewerPath()
        if saved ~= "" and saved ~= self:GetText() then self:SetText(saved) end
    end)
    local clear = UI.CreateSleekButton(f, 70, 22, "Clear", "tool")
    clear:SetPoint("BOTTOMLEFT", 14, 10)
    clear.tipTitle = "|cffffd100Clear|r"
    clear.tipText = "Forget the saved address, to paste a new one."
    clear:SetScript("OnClick", function()
        ns.SetStoryViewerPath("")
        eb:SetText("")
        eb:SetFocus()
    end)
    local done = UI.CreateSleekButton(f, 70, 22, "Done", "gold")
    done:SetPoint("BOTTOMRIGHT", -14, 10)
    done:SetScript("OnClick", function() f:Hide() end)
    function UI.ShowViewerPath()
        local saved = ns.StoryViewerPath()
        if saved ~= "" then
            sub:SetText("|cffd7c4a3Press |cffffd100Ctrl+C|cffd7c4a3, paste it into your browser's address bar and press Enter. " ..
                "This is the address you pasted from StoryViewer.html; paste a new one if you moved the game.|r")
            example:SetText("|cff8f9ba8Your StoryViewer.html:|r")
        else
            sub:SetText("|cffd7c4a3First time: open your game folder, go to |cfff5e6c8_forever_\\Interface\\AddOns\\RPChronicler|cffd7c4a3 and double-click |cfff5e6c8StoryViewer.html|cffd7c4a3. " ..
                "The page shows its own address with a |cffffd100Copy|cffd7c4a3 button: paste it here once (Ctrl+V), and from then on this box gives it back to you.|r")
            example:SetText("|cff8f9ba8It looks like (example, yours may differ): " .. ns.VIEWER_PATH_EXAMPLE .. "|r")
        end
        f:SetHeight(math.max(150, 124 + math.ceil(sub:GetStringHeight() or 28)))
        eb:SetText(saved)
        Sync()
        f:Show()
        eb:SetFocus()
        eb:SetCursorPosition(0)
        eb:HighlightText()
    end
end

-- Fills the tip and sizes it to its text; returns its height
function UI.LayoutStoryTip()
    local text = "|cffffd100Read your stories with screenshots:|r |cffd7c4a3open |cfff5e6c8StoryViewer.html|cffd7c4a3 (Viewer path). " ..
        "Picking your |cfff5e6c8RPChronicler.lua|cffd7c4a3 there loads every story the game has saved, after you log out or switch characters. " ..
        "For one you imported just now, use Copy for viewer.|r"
    local jpgOk = ns.ScreenshotFormatOK()
    if not jpgOk then
        text = text .. "\n|cffff6b6bYour screenshots are TGA, which browsers can't show.|r"
    end
    B.tipText:SetText(text)
    if jpgOk then B.jpgBtn:Hide() else B.jpgBtn:Show() end
    -- 0.6.3: the buttons flow under the text and wrap when the pane is narrow
    local textH = math.ceil(B.tipText:GetStringHeight() or 30)
    local rowH = UI.FlowRow(B.tip, { B.viewerBtn, B.pathBtn, B.jpgBtn }, nil,
        { x = 8, y = textH + 10, width = (B.tip:GetWidth() or 300) - 16, rowH = 18 })
    local h = math.max(58, textH + 10 + rowH + 6)
    B.tip:SetHeight(h)
    return h
end

-- 0.6.3: the action row, the tip and the reader follow the pane's width
-- and the font size (UI.FlowRow): the row wraps instead of overlapping
function UI.LayoutStoryBook()
    if (B.right:GetWidth() or 0) < 50 then return end
    local rowH = UI.FlowRow(B.right, { B.shareBtn, B.editBtn, B.reimportBtn, B.recBtn }, { B.delBtn }, { y = 76 })
    local top = 76 + rowH + 4
    B.tip:ClearAllPoints()
    B.tip:SetPoint("TOPLEFT", 0, -top)
    B.tip:SetPoint("TOPRIGHT", 0, -top)
    if ns.Get("exportTip") then
        B.tip:Show()
        top = top + UI.LayoutStoryTip() + 4
    else
        B.tip:Hide()
    end
    B.readBg:ClearAllPoints()
    B.readBg:SetPoint("BOTTOMRIGHT", 0, 0)
    B.readBg:SetPoint("TOPLEFT", 0, -top)
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

    -- 0.6.3: the story's cover, above the text: your character (a 3D model
    -- dressed in the gear worn on that run) with the title and that gear
    B.cover = CreateFrame("Frame", nil, B.child, UI.BACKDROP)
    B.cover:SetPoint("TOPLEFT", 0, 0)
    B.cover:SetPoint("TOPRIGHT", 0, 0)
    B.cover:SetHeight(200)
    UI.ApplyDarkGlass(B.cover, 0.14, 0.10, 0.07, 0.65, 0.70, 0.55, 0.25, 0.55)
    B.cover:Hide()
    local okModel, model = pcall(CreateFrame, "DressUpModel", nil, B.cover)
    if okModel and model then
        model:SetSize(150, 188)
        model:SetPoint("LEFT", 6, 0)
        B.model = model
    end
    B.coverTitle = B.cover:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    B.coverTitle:SetPoint("TOPLEFT", 170, -16)
    B.coverTitle:SetPoint("RIGHT", -12, 0)
    B.coverTitle:SetJustifyH("LEFT")
    pcall(B.coverTitle.SetFont, B.coverTitle, "Fonts\\MORPHEUS.TTF", 20, "")
    B.coverGear = B.cover:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    B.coverGear:SetPoint("TOPLEFT", B.coverTitle, "BOTTOMLEFT", 0, -10)
    B.coverGear:SetPoint("RIGHT", -12, 0)
    B.coverGear:SetJustifyH("LEFT")
    B.coverGear:SetJustifyV("TOP")
    B.coverGear:SetSpacing(3)
end

-- 0.6.3: dresses the cover model in the run's gear. The model shows the
-- character you are playing, so it only appears on that character's own
-- stories. Every model call is guarded (some clients draw no models).
local function DressCover(st)
    local m = B.model
    if not m then return false end
    local ok = pcall(m.SetUnit, m, "player")
    if not ok then return false end
    pcall(m.Undress, m)
    for _, g in ipairs(type(st.gear) == "table" and st.gear or {}) do
        if type(g) == "table" and g.link then pcall(m.TryOn, m, g.link) end
    end
    pcall(m.SetFacing, m, 0.35)
    return true
end

-- Fills the cover; returns its height (0 when the story has none)
function UI.LayoutStoryCover(st, info)
    local gear = type(st.gear) == "table" and st.gear or {}
    if not ns.Get("storyCover") or #gear == 0 then
        B.cover:Hide()
        return 0
    end
    local mine = st.char and st.char == ns.PlayerName()
    local names = {}
    for _, g in ipairs(gear) do
        if g.name and (tonumber(g.q) or 0) >= 2 then
            local hex = ({ [2] = "1eff00", [3] = "0070dd", [4] = "a335ee", [5] = "ff8000" })[tonumber(g.q)] or "f5e6c8"
            table.insert(names, "|cff" .. hex .. g.name .. "|r")
        end
    end
    B.coverTitle:SetText("|cffffd100" .. info.name .. "|r")
    local who = st.char and ("|cffd7c4a3" .. st.char .. "|r") or "|cffd7c4a3You|r"
    local lines = { who .. " |cffb0a080wore on this run:|r" }
    if #names > 0 then
        for i = 1, math.min(#names, 9) do table.insert(lines, "  " .. names[i]) end
    else
        table.insert(lines, "  |cff9e9e9eplain traveling clothes|r")
    end
    B.coverGear:SetText(table.concat(lines, "\n"))
    local x = 12
    if mine and B.model then
        B.model:Show()
        x = 170
        if C_Timer and C_Timer.After then
            C_Timer.After(0, function() if B.cover:IsShown() then DressCover(st) end end)
        else
            DressCover(st)
        end
    elseif B.model then
        B.model:Hide()
    end
    B.coverTitle:ClearAllPoints()
    B.coverTitle:SetPoint("TOPLEFT", x, -16)
    B.coverTitle:SetPoint("RIGHT", -12, 0)
    local h = math.max(mine and B.model and 200 or 0, 16 + (B.coverTitle:GetStringHeight() or 20) + 10 + (B.coverGear:GetStringHeight() or 40) + 16)
    B.cover:SetHeight(math.ceil(h))
    B.cover:Show()
    return math.ceil(h) + 10
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
        "|cfff5e6c82. Copy the run:|r in Adventures open |cff69ccf0Full Log|r, click |cffffd100Select All|r, press |cffffd100Ctrl+C|r.\n" ..
        "|cfff5e6c83. Import:|r paste the log into your AI, copy its story, and click |cffffd100Import Story|r.\n\n" ..
        "|cff9aa5b4Which AI? See the Requirements section of the README.|r")

    -- 0.6.1: the buttons stack and stretch to the pane, so they always fit
    local iBtn = UI.CreateSleekButton(e, 100, 24, "Import Story", "good")
    iBtn:SetPoint("BOTTOMLEFT", 18, 14)
    iBtn:SetPoint("BOTTOMRIGHT", -18, 14)
    iBtn:SetScript("OnClick", function() UI.OpenStoryImportModal(nil) end)
    local aBtn = UI.CreateSleekButton(e, 100, 24, "Adventure Story Template", "gold")
    aBtn:SetPoint("BOTTOMLEFT", iBtn, "TOPLEFT", 0, 6)
    aBtn:SetPoint("BOTTOMRIGHT", iBtn, "TOPRIGHT", 0, 6)
    aBtn:SetScript("OnClick", function() UI.OpenSkillTemplateModal("ADVENTURE") end)
    local dBtn = UI.CreateSleekButton(e, 100, 24, "Dungeon/Raid Story Template", "gold")
    dBtn:SetPoint("BOTTOMLEFT", aBtn, "TOPLEFT", 0, 6)
    dBtn:SetPoint("BOTTOMRIGHT", aBtn, "TOPRIGHT", 0, 6)
    dBtn:SetScript("OnClick", function() UI.OpenSkillTemplateModal("STORY") end)
end

local function UpdateReaderHeight()
    local h = (B.text:GetStringHeight() or 200) + (B.coverH or 0)
    B.child:SetHeight(math.max(230, h + 32))
    B.scroll:UpdateScrollChildRect()
end

-- 0.6.3: small touches: a page-turn sound and a fade when you open
-- another story, and a soft glow on stories imported this session until
-- you open them. All guarded.
local function PageTurn()
    if PlaySound and SOUNDKIT and SOUNDKIT.IG_ABILITY_PAGE_TURN then pcall(PlaySound, SOUNDKIT.IG_ABILITY_PAGE_TURN) end
end
local function FadeIn(frame)
    if UIFrameFadeIn then pcall(UIFrameFadeIn, frame, 0.3, 0, 1) end
end
B.sessionStart = time and time() or 0
B.seen = {}
local function Glow(card, on)
    if on and not card.glow then
        local t = card:CreateTexture(nil, "BACKGROUND")
        t:SetPoint("TOPLEFT", -3, 3)
        t:SetPoint("BOTTOMRIGHT", 3, -3)
        t:SetTexture(UI.SOLID_TEX)
        t:SetVertexColor(1, 0.82, 0.30, 0.55)
        card.glow = t
        if card.CreateAnimationGroup then
            local ag = card:CreateAnimationGroup()
            local a = ag:CreateAnimation("Alpha")
            if a.SetFromAlpha then a:SetFromAlpha(0.15); a:SetToAlpha(0.9) end
            if a.SetDuration then a:SetDuration(0.9) end
            if a.SetTarget then pcall(a.SetTarget, a, t) end
            if ag.SetLooping then ag:SetLooping("BOUNCE") end
            card.glowAnim = ag
        end
    end
    if card.glow then
        if on then
            card.glow:Show()
            if card.glowAnim and not card.glowAnim:IsPlaying() then card.glowAnim:Play() end
        else
            card.glow:Hide()
            if card.glowAnim then card.glowAnim:Stop() end
        end
    end
end

local function MakeCard(parent)
    local card = CreateFrame("Button", nil, parent, UI.BACKDROP)
    card:SetSize(146, 44)
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
        Glow(card, (adv.importedAt or 0) >= B.sessionStart and not B.seen[adv.id] and not sel)
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
    SyncListScrollBar(#list * 48)
    if #list > 0 then B.listEmpty:Hide(); B.importBtn:Show() else B.listEmpty:Show(); B.importBtn:Hide() end

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
    local metaParts = { (info.instance ~= "" and info.instance) or ns.GetRunKindLabel(adv) }
    if info.zone ~= "" and info.zone ~= info.instance then table.insert(metaParts, info.zone) end
    table.insert(metaParts, info.duration)
    table.insert(metaParts, info.date)
    B.meta:SetText("|cffd7c4a3" .. table.concat(metaParts, "  -  ") .. "|r")
    B.party:SetText("|cffb0a080Party:|r |cfff5e6c8" .. ((info.party ~= "" and info.party) or "solo") .. "|r")
    B.stats:SetText(ns.GetBookStats(info))
    if ns.StoryRun(adv) then B.recBtn:Enable() else B.recBtn:Disable() end

    UI.LayoutStoryBook()
    B.seen[adv.id] = true
    for idx, card in ipairs(B.cards) do
        if card:IsShown() and list[idx] and list[idx].id == adv.id then Glow(card, false) end
    end

    local okCover, coverH = pcall(UI.LayoutStoryCover, adv, info)
    B.coverH = okCover and coverH or 0
    if not okCover then B.cover:Hide() end
    B.text:ClearAllPoints()
    B.text:SetPoint("TOPLEFT", B.child, "TOPLEFT", 2, -(2 + B.coverH))

    local shown = ns.NormalizeStoryText(adv.story)
    shown = ns.CleanStoryHeader(shown)
    -- 0.5.3: auto-color the stored text once (markers kept), so the
    -- exporter gets the same colors after a /reload
    if adv.autoColored ~= ns.AUTOCOLOR_VERSION then
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
        if B.shownId then PageTurn() end
        B.shownId = adv.id
        B.scroll:SetVerticalScroll(0)
        FadeIn(B.child)
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
B.viewerBtn:SetScript("OnClick", function()
    local st = CurrentBookRun()
    if not st then return end
    UI.ShowCopyBox("|cffffd100Copy for viewer:|r |cfff5e6c8" .. ns.GetBookInfo(st).name .. "|r",
        "|cffb0bac5Press Ctrl+C, then paste it into StoryViewer.html (Paste a story).|r",
        ns.BuildViewerText(st))
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
    UI.SetStatus("Story deleted. The recording is still in Adventures.", "good")
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
    if B.right:IsVisible() then UI.LayoutStoryBook() end
    local w = B.scroll:GetWidth()
    if w and w > 50 then
        B.child:SetWidth(w)
        B.text:SetWidth(w - 4)
        UpdateReaderHeight()
    end
end)
