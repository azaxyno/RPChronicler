local ADDON_NAME, ns = ...
local UI = ns.UI

-- =========================================================
-- STORY BOOK (0.5.0: its own section, right below Adventures)
-- 0.6.7: the section is a room with a bookshelf (UI_Shelf.lua) and an
-- open book that fills the window (UI_Book.lua). This file keeps what
-- both share: opening the section, the empty Story Book, the story text
-- as the book shows it, and the story actions (Share, Copy for viewer,
-- Details, Re-Import, Run, Delete) that the book's menu calls. Stories
-- live in RPChroniclerDB.stories, so deleting a recording never deletes
-- its story.
-- =========================================================
local B = {}
UI.storyBook = B
-- 0.6.7 (Mor): Chronicles are hidden for now: the shelf holds stories
-- only and every story opens as its own book. Saved chronicles are kept
-- (RPChroniclerDB.chronicles), just not shown; true brings them back.
B.CHRONICLES = false
local root = UI.NewSection("BOOK", "Library", "Your tales, and the pages still waiting for their story.")
B.root = root
UI.AddRailButton("BOOK", "Library", UI.ICONS.STORY, "Your shelves: finished tales, gifts, and the recordings still waiting for their story.")

-- Stories imported this session glow on the shelf until opened
B.sessionStart = time and time() or 0
B.seen = {}
function B.IsNew(st)
    return st and (st.importedAt or 0) >= B.sessionStart and not B.seen[st.id] or false
end

-- What the section shows: the shelf, or an open book. ns.state.bookOpen
-- is { kind = "story" | "chronicle", id = ... }.
-- With a story it opens that story's book (its chronicle's book when it
-- is in one, at the story's first page); without one, the shelf.
function UI.OpenStoryBook(storyId)
    if storyId and ns.FindStory(storyId) then
        -- 0.6.7 (Mor): chronicles are hidden for now, so a story always
        -- opens as its own book
        local c = B.CHRONICLES and ns.ChronicleOf(storyId)
        ns.state.bookView = "BOOK"
        ns.state.bookOpen = c and { kind = "chronicle", id = c.id } or { kind = "story", id = storyId }
        ns.state.bookStoryId = storyId
        B.jumpTo = storyId
    else
        ns.state.bookView = "SHELF"
    end
    if not UI.frame:IsShown() then
        RPChronicler_Open("", "BOOK")
    elseif ns.state.section ~= "BOOK" then
        UI.ShowSection("BOOK")
    else
        UI.RefreshStoryBook()
    end
end

-- The story text as the book shows it: colored once (and saved, so the
-- exporter gets the same colors), boss and item marks added, screenshot
-- markers out
function B.StoryText(st)
    local shown = ns.CleanStoryHeader(ns.NormalizeStoryText(st.story or ""))
    -- 0.5.3: auto-color the stored text once (markers kept)
    if st.autoColored ~= ns.AUTOCOLOR_VERSION then
        local ok, colored = pcall(ns.AutoColorStory, shown, st)
        if ok and type(colored) == "string" then
            shown = colored
            st.story = colored
            st.autoColored = ns.AUTOCOLOR_VERSION
        end
    end
    shown = ns.StripShotMarkers(shown)
    local ok, decorated = pcall(function() return ns.DecorateStoryItems(ns.DecorateStoryBosses(shown, st), st) end)
    return ok and decorated or shown
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
    -- 0.6.4: the online copy of the same page (shown to copy, never saved
    -- as your path)
    local online = UI.CreateSleekButton(f, 110, 22, "Online viewer", "tool")
    online:SetPoint("LEFT", clear, "RIGHT", 8, 0)
    online.tipTitle = "|cffffd100Online viewer|r"
    online.tipText = "The same StoryViewer page on the web, for when you can't find the addon folder. It runs only in your browser, reads only the files you pick and uploads nothing."
    online:SetScript("OnClick", function()
        eb:SetText(ns.HOSTED_VIEWER_URL)
        example:SetText("|cff8f9ba8Online copy (same page, nothing is uploaded). Press Ctrl+C:|r")
        Sync()
        eb:SetFocus()
        eb:SetCursorPosition(0)
        eb:HighlightText()
    end)
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


-- Empty state: how to make a story (no story and no chronicle yet)
B.empty = CreateFrame("Frame", nil, root, UI.BACKDROP)
B.empty:SetAllPoints(root)
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
    heading:SetText("|cffffd100Your Library is empty|r")
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
        "|cfff5e6c80. Record:|r click |cffffd100Chronicle a new adventure|r at the top, or enter a dungeon.\n" ..
        "|cfff5e6c81. Copy the run:|r in the Journal open |cff69ccf0Full Log|r, tick |cffffd100Include AI instructions|r, click |cffffd100Copy for AI|r, press |cffffd100Ctrl+C|r.\n" ..
        "|cfff5e6c82. Ask your AI:|r paste it into any AI chat. The story rules come with it.\n" ..
        "|cfff5e6c83. Import:|r copy the story it writes and click |cffffd100Import Story|r.\n" ..
        "|cff9aa5b4No AI? Import Story > Quick Chronicle (a test feature) writes a short one for you.|r\n\n" ..
        "|cff9aa5b4Advanced: use a skill. Make a template below a skill in your AI and copy the Full Log with Include AI instructions off (Options > AI & Stories). Which AI? See the README's Requirements.|r")

    -- 0.6.1: the buttons stack and stretch to the pane, so they always fit
    local iBtn = UI.CreateSleekButton(e, 100, 24, "Import Story", "good")
    iBtn:SetPoint("BOTTOMLEFT", 18, 14)
    iBtn:SetPoint("BOTTOMRIGHT", -18, 14)
    iBtn:SetScript("OnClick", function() UI.OpenStoryImportModal(nil) end)
    local aBtn = UI.CreateSleekButton(e, 100, 24, "Adventure Story Template", "gold")
    aBtn:SetPoint("BOTTOMLEFT", iBtn, "TOPLEFT", 0, 6)
    aBtn:SetPoint("BOTTOMRIGHT", iBtn, "TOPRIGHT", 0, 6)
    aBtn:SetScript("OnClick", function() UI.OpenSkillTemplateModal("ADVENTURE") end)
    local dBtn = UI.CreateSleekButton(e, 100, 24, "Dungeon Story Template", "gold")
    dBtn:SetPoint("BOTTOMLEFT", aBtn, "TOPLEFT", 0, 6)
    dBtn:SetPoint("BOTTOMRIGHT", aBtn, "TOPRIGHT", 0, 6)
    dBtn:SetScript("OnClick", function() UI.OpenSkillTemplateModal("STORY") end)
end

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

    function UI.OpenStoryDetails(adv)
        if not adv then return end
        f.advId = adv.id
        local info = ns.GetBookInfo(adv)
        for i, fd in ipairs(FIELDS) do boxes[i]:SetText(tostring(info[fd.key] or "")) end
        f:Show()
        boxes[1]:SetFocus()
    end
end

-- =========================================================
-- Story actions (the open book's menu calls these)
-- =========================================================
function B.Share(st)
    if not st then return end
    local info = ns.GetBookInfo(st)
    local header = info.name .. "\n" .. table.concat({ ns.GetRunKindLabel(st), info.duration, info.date }, " | ") .. "\n\n"
    UI.ShowCopyBox("|cffffd100Share:|r |cfff5e6c8" .. info.name .. "|r",
        "|cffb0bac5Plain text with no color codes, ready for Discord or a forum.|r",
        header .. ns.GetStoryPlainText(st))
end

-- 0.6.2: a story imported this session isn't in the saved file yet, so
-- StoryViewer.html gets it by paste
function B.CopyForViewer(st)
    if not st then return end
    UI.ShowCopyBox("|cffffd100Copy for viewer:|r |cfff5e6c8" .. ns.GetBookInfo(st).name .. "|r",
        "|cffb0bac5Press Ctrl+C, then paste it into StoryViewer.html (Paste a story).|r",
        ns.BuildViewerText(st))
end

function B.UseJpg()
    if ns.UseJpgScreenshots() then
        UI.SetStatus("Screenshots are now saved as JPG.", "good")
    else
        UI.SetStatus("Couldn't change the screenshot format. Leave combat and try again.", "error")
    end
end

function B.ReImport(st)
    if st then UI.OpenStoryImportModal(nil, st) end
end

function B.OpenRun(st)
    local run = st and ns.StoryRun(st)
    if run then UI.OpenRecording(run.id, "SUMMARY") end
end

-- Asks first; the recording stays
function B.DeleteStory(st)
    if not st then return end
    local name = ns.StripColors(ns.GetBookInfo(st).name or "")
    UI.ShowPrompt("|cffffd100Delete \"" .. name .. "\"?|r\n|cffd7c4a3Only the story goes; its recording stays in Adventures.|r",
        "|cffff6b6bDelete story|r", function()
            ns.DeleteStory(st.id)
            if ns.state.bookStoryId == st.id then ns.state.bookStoryId = nil end
            local open = ns.state.bookOpen
            if open and open.kind == "story" and open.id == st.id then ns.state.bookView = "SHELF" end
            UI.SetStatus("Story deleted. The recording is still in Adventures.", "good")
            UI.RefreshStoryBook()
        end,
        "Keep it", nil)
end

-- =========================================================
-- Which view shows. UI_Shelf.lua and UI_Book.lua fill in B.ShowShelf and
-- B.ShowBook; every refresh of the section comes through here.
-- =========================================================
function UI.RefreshStoryBook()
    -- 0.6.4: skill users hear once a session when the story rules changed
    local notice = not B.noticeShown and ns.TemplateNotice()
    if notice then B.noticeShown = true; UI.SetStatus(notice, "warn") end
    -- 0.7.0: the empty page only on a fresh Library (no story, no run)
    if #ns.GetStories() == 0 and #ns.RunsWithoutStory() == 0 and not (B.CHRONICLES and #ns.GetChronicles() > 0) then
        if B.HideBook then B.HideBook() end
        if B.HideShelf then B.HideShelf() end
        UI.SetBookMode(false)
        B.empty:Show()
        return
    end
    B.empty:Hide()
    local open = ns.state.bookOpen
    local exists = open and ((open.kind == "story" and ns.FindStory(open.id)) or (B.CHRONICLES and open.kind == "chronicle" and ns.FindChronicle(open.id)))
    if ns.state.bookView == "BOOK" and exists and B.ShowBook then
        if B.HideShelf then B.HideShelf() end
        UI.SetBookMode(true)
        B.ShowBook()
    else
        ns.state.bookView = "SHELF"
        if B.HideBook then B.HideBook() end
        UI.SetBookMode(false)
        if B.ShowShelf then B.ShowShelf() end
    end
end

UI.SetSectionOnShow("BOOK", function() UI.RefreshStoryBook() end)
root:SetScript("OnHide", function() UI.HideTooltip() end)
