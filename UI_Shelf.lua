local ADDON_NAME, ns = ...
local UI = ns.UI

-- =========================================================
-- CHRONICLES SHELF (0.6.6, Mor): the Story Book opens on a bookshelf.
-- Each Chronicle is a volume (title, color, a story's party scene on its
-- cover, a table of contents); stories in no chronicle stand as thin loose
-- books at the end. A search box finds stories by title, place, party
-- member or date. Opening a volume plays a short book-opening animation
-- with the game's book sound; reading a story uses the reader of
-- UI_StoryBook.lua, which gets Shelf, Chronicle and Prev/Next buttons.
-- Saved data changes only through the chronicle functions in Stories.lua.
-- =========================================================
local B = UI.storyBook
local S = {}
UI.shelf = S

local SPINE_W, SPINE_H, LOOSE_W, LOOSE_H, ROW_H, GAP = 34, 132, 20, 108, 156, 5
local GOLD = "|cffffd100"

local function Sound(name)
    if PlaySound and SOUNDKIT and SOUNDKIT[name] then pcall(PlaySound, SOUNDKIT[name]) end
end

-- One line, cut with "..." to fit `n` letters
local function Cut(text, n)
    text = tostring(text or "")
    if #text <= n then return text end
    return text:sub(1, n - 2):match("^(.-)%s*$") .. "..."
end

-- Letters stacked top to bottom for a spine (FontStrings can't turn)
local function Stack(text, n)
    local t = Cut(ns.StripColors(text or ""):upper(), n)
    local out = {}
    for i = 1, #t do
        local ch = t:sub(i, i)
        out[#out + 1] = (ch == " ") and "" or ch
    end
    return table.concat(out, "\n")
end

local function Color(c)
    local col = ns.CHRONICLE_COLORS[tonumber(c and c.color) or 1] or ns.CHRONICLE_COLORS[1]
    return col[1], col[2], col[3]
end

-- Date, place, run type, party and length of a story, for tooltips
local function StoryTip(owner, st)
    local info = ns.GetBookInfo(st)
    local words = 0
    for _ in ns.StripColors(st.story or ""):gmatch("%S+") do words = words + 1 end
    local place = (info.instance ~= "" and info.instance) or info.zone or ""
    UI.Tooltip(owner, GOLD .. ns.StripColors(info.name or info.title or "") .. "|r",
        (info.date or "") .. (place ~= "" and ("  -  " .. place) or ""),
        ns.GetRunKindLabel(st) .. "  -  " .. (info.duration or ""),
        "Party: " .. ((info.party ~= "" and info.party) or "solo"),
        string.format("%d words, %d chapters", words, #(info.chapters or {})))
end

-- Which view the Story Book shows: SHELF, VOLUME or READ
local function View()
    return ns.state.bookView or "SHELF"
end

local function OpenStory(st)
    if not st then return end
    ns.state.bookStoryId = st.id
    ns.state.bookView = "READ"
    UI.RefreshStoryBook()
end

-- A full-size page over the Story Book section
local function Overlay()
    local f = CreateFrame("Frame", nil, B.root, UI.BACKDROP)
    f:SetAllPoints(B.root)
    f:SetFrameLevel((B.root:GetFrameLevel() or 1) + 60)
    f:EnableMouse(true)
    UI.ApplyStoryTomeLook(f)
    f:Hide()
    return f
end

-- =========================================================
-- The shelf
-- =========================================================
do
    local f = Overlay()
    S.shelfFrame = f
    local title = UI.Label(f, GOLD .. "Your shelf|r", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 12, -10)
    local sub = UI.Label(f, "|cffb0a080Your chronicles, then the loose stories. Click a volume to open it.|r", "GameFontHighlightSmall")
    sub:SetPoint("TOPLEFT", 12, -30)
    sub:SetPoint("RIGHT", f, "RIGHT", -12, 0)

    S.newBtn = UI.CreateSleekButton(f, 112, 20, "+ New chronicle", "gold")
    S.newBtn:SetPoint("TOPRIGHT", -10, -8)
    S.newBtn.tipTitle = GOLD .. "New chronicle|r"
    S.newBtn.tipText = "A volume for stories that belong together, like the road of an alt you level with a friend."
    S.importBtn = UI.CreateSleekButton(f, 64, 20, "+ Import")
    S.importBtn:SetPoint("RIGHT", S.newBtn, "LEFT", -6, 0)
    S.importBtn:SetScript("OnClick", function() UI.OpenStoryImportModal(nil) end)

    -- search: title, place, party member, date or chronicle
    local box = CreateFrame("EditBox", "RPChroniclerShelfSearch", f, "InputBoxTemplate")
    box:SetSize(150, 20)
    box:SetPoint("RIGHT", S.importBtn, "LEFT", -10, 0)
    box:SetAutoFocus(false)
    box:SetMaxLetters(40)
    local hint = box:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("LEFT", 2, 0)
    hint:SetText("Search stories")
    box:SetScript("OnEscapePressed", function(self) self:SetText(""); self:ClearFocus() end)
    box:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    box:SetScript("OnTextChanged", function(self)
        local t = (self:GetText() or ""):gsub("||", "|")
        if t ~= "" then hint:Hide() else hint:Show() end
        S.query = t
        S.RefreshShelf()
    end)
    box:SetScript("OnEnter", function(self)
        UI.Tooltip(self, GOLD .. "Search|r", "Finds stories by title, place, party member, date or chronicle, on every shelf.")
    end)
    box:SetScript("OnLeave", UI.HideTooltip)
    S.search = box

    local scroll = CreateFrame("ScrollFrame", "RPChroniclerShelfScroll", f, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 10, -52)
    scroll:SetPoint("BOTTOMRIGHT", -30, 10)
    local child = CreateFrame("Frame", nil, scroll)
    child:SetSize(400, 10)
    scroll:SetScrollChild(child)
    S.scroll, S.child = scroll, child
    S.spines, S.loose, S.planks, S.rows = {}, {}, {}, {}

    S.emptyText = UI.Label(child, "", "GameFontHighlight")
    S.emptyText:SetPoint("TOPLEFT", 6, -8)
    S.emptyText:SetPoint("RIGHT", child, "RIGHT", -6, 0)
    S.emptyText:SetWordWrap(true)
end

-- A spine on the shelf; `loose` spines are thin and parchment colored
local function MakeSpine(loose)
    local b = CreateFrame("Button", nil, S.child, UI.BACKDROP)
    b:SetSize(loose and LOOSE_W or SPINE_W, loose and LOOSE_H or SPINE_H)
    b.text = b:CreateFontString(nil, "OVERLAY", loose and "GameFontHighlightSmall" or "GameFontNormalSmall")
    b.text:SetPoint("CENTER", 0, 0)
    b.text:SetJustifyH("CENTER")
    if b.text.SetSpacing then b.text:SetSpacing(-1) end
    if not loose then
        for i = 1, 2 do
            local band = b:CreateTexture(nil, "ARTWORK")
            band:SetTexture(UI.SOLID_TEX)
            band:SetVertexColor(1, 0.82, 0.25, 0.75)
            band:SetHeight(2)
            band:SetPoint("LEFT", 4, 0)
            band:SetPoint("RIGHT", -4, 0)
            band:SetPoint(i == 1 and "TOP" or "BOTTOM", 0, i == 1 and -9 or 9)
        end
    end
    -- lifts on hover, like a book pulled from the shelf
    b:SetScript("OnEnter", function(self)
        if self.x then self:SetPoint("BOTTOMLEFT", S.child, "TOPLEFT", self.x, self.y + 8) end
        if self.chr then
            UI.Tooltip(self, GOLD .. self.chr.title .. "|r",
                string.format("%d %s", #self.chr.stories, #self.chr.stories == 1 and "story" or "stories"), "Click to open.")
        elseif self.story then
            StoryTip(self, self.story)
        end
    end)
    b:SetScript("OnLeave", function(self)
        if self.x then self:SetPoint("BOTTOMLEFT", S.child, "TOPLEFT", self.x, self.y) end
        UI.HideTooltip()
    end)
    return b
end

-- A search result row
local function MakeRow(parent)
    local r = CreateFrame("Button", nil, parent, UI.BACKDROP)
    r:SetHeight(34)
    UI.ApplyDarkGlass(r, 0.12, 0.09, 0.06, 0.92, 0.40, 0.31, 0.16, 0.85)
    r.icon = r:CreateTexture(nil, "ARTWORK")
    r.icon:SetSize(26, 26)
    r.icon:SetPoint("LEFT", 5, 0)
    r.title = r:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    r.title:SetPoint("TOPLEFT", r.icon, "TOPRIGHT", 6, 0)
    r.title:SetPoint("RIGHT", -6, 0)
    r.title:SetJustifyH("LEFT")
    r.title:SetWordWrap(false)
    r.sub = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.sub:SetPoint("TOPLEFT", r.icon, "TOPRIGHT", 6, -14)
    r.sub:SetPoint("RIGHT", -6, 0)
    r.sub:SetJustifyH("LEFT")
    r.sub:SetWordWrap(false)
    r:SetScript("OnEnter", function(self)
        self:SetBackdropBorderColor(0.90, 0.73, 0.32, 0.95)
        if self.story then StoryTip(self, self.story) end
    end)
    r:SetScript("OnLeave", function(self)
        self:SetBackdropBorderColor(0.40, 0.31, 0.16, 0.85)
        UI.HideTooltip()
    end)
    r:SetScript("OnClick", function(self) OpenStory(self.story) end)
    return r
end

local function Plank(i, y, w)
    local p = S.planks[i]
    if not p then
        p = S.child:CreateTexture(nil, "BACKGROUND")
        p:SetTexture(UI.SOLID_TEX)
        p:SetVertexColor(0.29, 0.20, 0.12, 1)
        S.planks[i] = p
    end
    p:ClearAllPoints()
    p:SetPoint("TOPLEFT", S.child, "TOPLEFT", 0, y)
    p:SetSize(w, 9)
    p:Show()
end

function S.RefreshShelf()
    local w = math.max(200, (S.scroll:GetWidth() or 400) - 4)
    S.child:SetWidth(w)
    for _, x in ipairs(S.spines) do x:Hide() end
    for _, x in ipairs(S.loose) do x:Hide() end
    for _, x in ipairs(S.planks) do x:Hide() end
    for _, x in ipairs(S.rows) do x:Hide() end
    S.emptyText:Hide()

    -- search results instead of the shelf
    if S.query and S.query:match("%S") then
        local found = ns.SearchStories(S.query)
        for i, st in ipairs(found) do
            local r = S.rows[i] or MakeRow(S.child)
            S.rows[i] = r
            local info = ns.GetBookInfo(st)
            local c = ns.ChronicleOf(st.id)
            r.story = st
            r:ClearAllPoints()
            r:SetPoint("TOPLEFT", 0, -(i - 1) * 38)
            r:SetPoint("RIGHT", S.child, "RIGHT", 0, 0)
            local icon = ns.GetAdventureIcon(st)
            r.icon:SetTexture(icon)
            r.icon:SetTexCoord(ns.IconCoords(icon))
            r.title:SetText("|cfff5e6c8" .. ns.StripColors(info.name or info.title or "") .. "|r")
            local place = (info.instance ~= "" and info.instance) or info.zone or ""
            r.sub:SetText("|cffb0a080" .. place .. "  -  " .. (info.date or "") ..
                (c and ("  -  in " .. c.title) or "") .. "|r")
            r:Show()
        end
        if #found == 0 then
            S.emptyText:SetText("|cffb0a080No story matches \"" .. S.query .. "\".|r")
            S.emptyText:Show()
        end
        S.child:SetHeight(math.max(10, #found * 38))
        return
    end

    -- the shelf: volumes, then loose stories, in rows that wrap
    local x, row, n, nl = 6, 0, 0, 0
    local function Place(b, bw, bh)
        if x + bw > w - 6 and x > 6 then
            x, row = 6, row + 1
        end
        local base = -(row * ROW_H) - SPINE_H - 14
        b.x, b.y = x, base
        b:ClearAllPoints()
        b:SetPoint("BOTTOMLEFT", S.child, "TOPLEFT", x, base)
        b:Show()
        x = x + bw + GAP
    end
    for _, c in ipairs(ns.GetChronicles()) do
        n = n + 1
        local b = S.spines[n] or MakeSpine(false)
        S.spines[n] = b
        b.chr, b.story = c, nil
        local r, g, bl = Color(c)
        UI.ApplyDarkGlass(b, r, g, bl, 1, math.min(1, r + 0.35), math.min(1, g + 0.30), math.min(1, bl + 0.20), 0.9)
        b.text:SetText("|cfff5e6c8" .. Stack(c.title, 11) .. "|r")
        b:SetScript("OnClick", function() S.OpenVolume(c.id) end)
        Place(b, SPINE_W, SPINE_H)
    end
    for _, st in ipairs(ns.LooseStories()) do
        nl = nl + 1
        local b = S.loose[nl] or MakeSpine(true)
        S.loose[nl] = b
        b.chr, b.story = nil, st
        UI.ApplyDarkGlass(b, 0.80, 0.72, 0.55, 1, 0.55, 0.45, 0.28, 0.9)
        b.text:SetText("|cff3a2a14" .. Stack(ns.GetBookInfo(st).name or "", 8) .. "|r")
        b:SetScript("OnClick", function() OpenStory(st) end)
        Place(b, LOOSE_W, LOOSE_H)
    end
    local rows = (n + nl > 0) and (row + 1) or 0
    for i = 1, rows do Plank(i, -((i - 1) * ROW_H) - SPINE_H - 14, w) end
    if n + nl == 0 then
        S.emptyText:SetText("|cffb0a080No stories yet. Import the story your AI wrote with + Import.|r")
        S.emptyText:Show()
    elseif n == 0 then
        S.emptyText:SetText("")
    end
    S.child:SetHeight(math.max(10, rows * ROW_H + 10))
end

-- =========================================================
-- A volume: the cover (left page) and the table of contents (right page)
-- =========================================================
do
    local f = Overlay()
    S.volFrame = f
    S.backBtn = UI.CreateSleekButton(f, 64, 20, "< Shelf", "gold")
    S.backBtn:SetPoint("TOPLEFT", 10, -8)
    S.backBtn:SetScript("OnClick", function() S.ShowShelf() end)
    S.volTitle = UI.Label(f, "", "GameFontNormalLarge")
    S.volTitle:SetPoint("LEFT", S.backBtn, "RIGHT", 10, 0)
    S.volTitle:SetPoint("RIGHT", f, "RIGHT", -300, 0)
    S.volTitle:SetWordWrap(false)

    S.delBtn = UI.CreateSleekButton(f, 54, 20, "Delete", "danger")
    S.delBtn:SetPoint("TOPRIGHT", -10, -8)
    S.delBtn.tipTitle = "|cffff6b6bDelete chronicle|r"
    S.delBtn.tipText = "Removes the volume. Its stories stay in the Story Book as loose stories."
    S.colorBtn = UI.CreateSleekButton(f, 50, 20, "Color")
    S.colorBtn:SetPoint("RIGHT", S.delBtn, "LEFT", -6, 0)
    S.renameBtn = UI.CreateSleekButton(f, 60, 20, "Rename")
    S.renameBtn:SetPoint("RIGHT", S.colorBtn, "LEFT", -6, 0)
    S.leftBtn = UI.CreateSleekButton(f, 22, 20, "<", "tool")
    S.leftBtn:SetPoint("RIGHT", S.renameBtn, "LEFT", -10, 0)
    S.leftBtn.tipTitle = GOLD .. "Move on the shelf|r"
    S.leftBtn.tipText = "Moves this volume one place left on the shelf."
    S.rightBtn = UI.CreateSleekButton(f, 22, 20, ">", "tool")
    S.rightBtn:SetPoint("LEFT", S.leftBtn, "RIGHT", 2, 0)
    S.rightBtn.tipTitle = GOLD .. "Move on the shelf|r"
    S.rightBtn.tipText = "Moves this volume one place right on the shelf."
    S.leftBtn:ClearAllPoints()
    S.leftBtn:SetPoint("RIGHT", S.renameBtn, "LEFT", -32, 0)

    -- the open book: two pages
    S.book = CreateFrame("Frame", nil, f)
    S.book:SetPoint("TOPLEFT", 10, -36)
    S.book:SetPoint("BOTTOMRIGHT", -10, 10)
    local function Page()
        local p = CreateFrame("Frame", nil, S.book, UI.BACKDROP)
        UI.ApplyDarkGlass(p, 0.16, 0.12, 0.08, 1, 0.55, 0.42, 0.20, 0.9)
        return p
    end
    S.leftPage, S.rightPage = Page(), Page()
    S.leftPage:SetPoint("TOPLEFT", 0, 0)
    S.leftPage:SetPoint("BOTTOMRIGHT", S.book, "BOTTOM", -2, 0)
    S.rightPage:SetPoint("TOPLEFT", S.book, "TOP", 2, 0)
    S.rightPage:SetPoint("BOTTOMRIGHT", 0, 0)

    -- the cover: a colored band, the cover story's party scene, the title
    S.coverBand = S.leftPage:CreateTexture(nil, "BACKGROUND", nil, 1)
    S.coverBand:SetTexture(UI.SOLID_TEX)
    S.coverBand:SetPoint("TOPLEFT", 1, -1)
    S.coverBand:SetPoint("BOTTOMRIGHT", -1, 1)
    S.coverTitle = S.leftPage:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    S.coverTitle:SetPoint("LEFT", 14, 0)
    S.coverTitle:SetPoint("RIGHT", -14, 0)
    S.coverTitle:SetJustifyH("CENTER")
    S.coverTitle:SetWordWrap(true)
    if S.coverTitle.SetMaxLines then S.coverTitle:SetMaxLines(2) end
    S.coverSub = S.leftPage:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    S.coverSub:SetPoint("TOP", S.coverTitle, "BOTTOM", 0, -6)
    S.coverSub:SetPoint("LEFT", 14, 0)
    S.coverSub:SetPoint("RIGHT", -14, 0)
    S.coverSub:SetJustifyH("CENTER")

    -- the contents
    local head = UI.Label(S.rightPage, GOLD .. "Contents|r", "GameFontNormal")
    head:SetPoint("TOPLEFT", 12, -10)
    S.tocHint = UI.Label(S.rightPage, "", "GameFontHighlightSmall")
    S.tocHint:SetPoint("TOPLEFT", 12, -28)
    S.tocHint:SetPoint("RIGHT", S.rightPage, "RIGHT", -12, 0)
    S.tocHint:SetWordWrap(true)
    S.tocScroll = CreateFrame("ScrollFrame", "RPChroniclerShelfTocScroll", S.rightPage, "UIPanelScrollFrameTemplate")
    S.tocScroll:SetPoint("TOPLEFT", 8, -46)
    S.tocScroll:SetPoint("BOTTOMRIGHT", -28, 8)
    S.toc = CreateFrame("Frame", nil, S.tocScroll)
    S.toc:SetSize(200, 10)
    S.tocScroll:SetScrollChild(S.toc)
    S.tocRows = {}

    -- the book-opening animation: the volume swings open from its spine
    if f.CreateAnimationGroup then
        local ag = f:CreateAnimationGroup()
        local ok = pcall(function()
            local sc = ag:CreateAnimation("Scale")
            if sc.SetScaleFrom then sc:SetScaleFrom(0.15, 1); sc:SetScaleTo(1, 1) else sc:SetScale(1, 1) end
            sc:SetOrigin("LEFT", 0, 0)
            sc:SetDuration(0.28)
            sc:SetSmoothing("OUT")
            local al = ag:CreateAnimation("Alpha")
            al:SetFromAlpha(0)
            al:SetToAlpha(1)
            al:SetDuration(0.22)
        end)
        if ok then S.openAnim = ag end
    end
end

local function TocRow(i)
    local r = S.tocRows[i]
    if r then return r end
    r = CreateFrame("Button", nil, S.toc, UI.BACKDROP)
    r:SetHeight(24)
    UI.ApplyDarkGlass(r, 0.10, 0.08, 0.05, 0.6, 0.40, 0.31, 0.16, 0.5)
    r.out = UI.CreateSleekButton(r, 30, 18, "Out", "danger")
    r.out:SetPoint("RIGHT", -3, 0)
    r.out.tipTitle = "|cffff6b6bTake out|r"
    r.out.tipText = "Takes this story out of the volume. It stays in the Story Book."
    r.down = UI.CreateSleekButton(r, 34, 18, "Down", "tool")
    r.down:SetPoint("RIGHT", r.out, "LEFT", -2, 0)
    r.up = UI.CreateSleekButton(r, 26, 18, "Up", "tool")
    r.up:SetPoint("RIGHT", r.down, "LEFT", -2, 0)
    r.cover = UI.CreateSleekButton(r, 40, 18, "Cover")
    r.cover:SetPoint("RIGHT", r.up, "LEFT", -2, 0)
    r.cover.tipTitle = GOLD .. "Cover|r"
    r.cover.tipText = "Shows this story's party scene on the volume's cover."
    r.label = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.label:SetPoint("LEFT", 6, 0)
    r.label:SetPoint("RIGHT", r.cover, "LEFT", -4, 0)
    r.label:SetJustifyH("LEFT")
    r.label:SetWordWrap(false)
    r:SetScript("OnEnter", function(self)
        self:SetBackdropBorderColor(0.90, 0.73, 0.32, 0.95)
        if self.story then StoryTip(self, self.story) end
    end)
    r:SetScript("OnLeave", function(self)
        self:SetBackdropBorderColor(0.40, 0.31, 0.16, 0.5)
        UI.HideTooltip()
    end)
    r:SetScript("OnClick", function(self) OpenStory(self.story) end)
    r.up:SetScript("OnClick", function() ns.MoveChronicleStory(r.story.id, -1) end)
    r.down:SetScript("OnClick", function() ns.MoveChronicleStory(r.story.id, 1) end)
    r.out:SetScript("OnClick", function() ns.RemoveStoryFromChronicle(r.story.id) end)
    r.cover:SetScript("OnClick", function() ns.SetChronicleCover(S.volId, r.story.id) end)
    S.tocRows[i] = r
    return r
end

local function CoverScene()
    if S.scene or not UI.CreateStoryScene then return S.scene end
    local ok, scene = pcall(UI.CreateStoryScene, S.leftPage, {
        bigTip = "Shows this scene in a big window, where you can zoom and look around.",
        onBig = function(sc) UI.OpenBigScene(sc.story, sc.view, S.coverTitle:GetText()) end,
    })
    if not ok or not scene then return nil end
    S.scene = scene
    scene.frame:SetPoint("TOPLEFT", 10, -10)
    scene.frame:SetPoint("TOPRIGHT", -10, -10)
    return scene
end

function S.RefreshVolume()
    local c = ns.FindChronicle(S.volId)
    if not c then S.ShowShelf() return end
    local r, g, b = Color(c)
    S.volTitle:SetText(GOLD .. c.title .. "|r")
    S.coverBand:SetVertexColor(r, g, b, 0.55)
    S.coverTitle:SetText(GOLD .. c.title .. "|r")
    local stories = ns.ChronicleStories(c)
    local first, last = stories[1], stories[#stories]
    if first then
        local d1, d2 = ns.GetBookInfo(first).date or "", ns.GetBookInfo(last).date or ""
        d1, d2 = d1:sub(1, 10), d2:sub(1, 10)
        S.coverSub:SetText(string.format("|cffd7c4a3%d %s  -  %s|r", #stories, #stories == 1 and "story" or "stories",
            (d1 == d2 or d2 == "") and d1 or (d1 .. " to " .. d2)))
    else
        S.coverSub:SetText("|cffd7c4a3An empty volume|r")
    end
    -- the party scene of the cover story, when it has a party
    local cov = ns.ChronicleCover(c)
    local scene = cov and type(cov.participants) == "table" and #cov.participants > 0 and ns.Get("storyCover") and CoverScene()
    local pageH = S.leftPage:GetHeight() or 300
    if scene then
        local h = math.floor(math.max(120, math.min(pageH * 0.6, 240)))
        scene.frame:SetHeight(h)
        scene.frame:Show()
        if scene.story ~= cov then pcall(scene.SetStory, scene, cov) else pcall(scene.Refresh, scene) end
        S.coverTitle:ClearAllPoints()
        S.coverTitle:SetPoint("TOPLEFT", 14, -(h + 24))
        S.coverTitle:SetPoint("RIGHT", -14, 0)
    else
        if S.scene then S.scene.frame:Hide() end
        S.coverTitle:ClearAllPoints()
        S.coverTitle:SetPoint("LEFT", 14, 10)
        S.coverTitle:SetPoint("RIGHT", -14, 10)
    end

    -- contents
    for _, row in ipairs(S.tocRows) do row:Hide() end
    local w = math.max(160, (S.tocScroll:GetWidth() or 220) - 2)
    S.toc:SetWidth(w)
    for i, st in ipairs(stories) do
        local row = TocRow(i)
        row.story = st
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", 0, -(i - 1) * 27)
        row:SetWidth(w)
        row.label:SetText(string.format("|cffd7c4a3%d.|r |cfff5e6c8%s|r", i, ns.StripColors(ns.GetBookInfo(st).name or "")))
        if i == 1 then row.up:Disable() else row.up:Enable() end
        if i == #stories then row.down:Disable() else row.down:Enable() end
        if cov == st then row.cover:Disable() else row.cover:Enable() end
        row:Show()
    end
    S.toc:SetHeight(math.max(10, #stories * 27))
    S.tocHint:SetText(#stories == 0
        and "|cffb0a080Open a story and click Chronicle to put it in this volume.|r"
        or "|cffb0a080Click a story to read it. Up and Down set the order.|r")
    local list = ns.GetChronicles()
    if list[1] == c then S.leftBtn:Disable() else S.leftBtn:Enable() end
    if list[#list] == c then S.rightBtn:Disable() else S.rightBtn:Enable() end
end

-- =========================================================
-- Views
-- =========================================================
local function ShowOverlay(which)
    S.shelfFrame:SetShown(which == "SHELF")
    S.volFrame:SetShown(which == "VOLUME")
    if which == "READ" then
        B.list:Show()
    else
        B.list:Hide()
        B.right:Hide()
        B.empty:Hide()
    end
end

function S.ShowShelf()
    ns.state.bookView = "SHELF"
    ShowOverlay("SHELF")
    S.RefreshShelf()
end

function S.OpenVolume(id)
    ns.state.bookView = "VOLUME"
    S.volId = id
    S.delBtn.armedAt = nil
    S.delBtn:SetText("Delete")
    ShowOverlay("VOLUME")
    S.RefreshVolume()
    Sound("IG_SPELLBOOK_OPEN")
    if S.openAnim then S.openAnim:Stop(); S.openAnim:Play() end
end

-- New chronicle: a name (at most 32 letters), then opened
S.newBtn:SetScript("OnClick", function()
    UI.AskLine({
        title = GOLD .. "New chronicle|r",
        sub = "|cffb0bac5A name for the volume (up to " .. ns.CHRONICLE_TITLE_MAX .. " letters).|r",
        placeholder = "The Road of Two Heroes",
        okText = "Create",
        onAccept = function(text)
            local c = ns.CreateChronicle(text)
            if c then S.OpenVolume(c.id) end
        end,
    })
end)
S.renameBtn:SetScript("OnClick", function()
    local c = ns.FindChronicle(S.volId)
    if not c then return end
    UI.AskLine({
        title = GOLD .. "Rename chronicle|r",
        sub = "|cffb0bac5Now: " .. c.title .. " (up to " .. ns.CHRONICLE_TITLE_MAX .. " letters).|r",
        placeholder = c.title,
        okText = "Rename",
        onAccept = function(text) ns.RenameChronicle(c.id, text) end,
    })
end)
S.colorBtn:SetScript("OnClick", function() ns.CycleChronicleColor(S.volId) end)
S.leftBtn:SetScript("OnClick", function() ns.MoveChronicle(S.volId, -1) end)
S.rightBtn:SetScript("OnClick", function() ns.MoveChronicle(S.volId, 1) end)
S.delBtn:SetScript("OnClick", function(self)
    if not self.armedAt or GetTime() - self.armedAt > 4 then
        self.armedAt = GetTime()
        self:SetText("|cffff6b6bSure?|r")
        UI.SetStatus("Click Delete again to remove this volume. Its stories stay in the Story Book.", "error")
        return
    end
    self.armedAt = nil
    ns.DeleteChronicle(S.volId)
    UI.SetStatus("Chronicle deleted. Its stories are on the shelf as loose stories.", "good")
    S.ShowShelf()
end)

-- =========================================================
-- The reader's buttons: back to the shelf, Chronicle, Prev and Next
-- =========================================================
do
    S.shelfBtn = UI.CreateSleekButton(B.right, 52, 22, "Shelf", "gold")
    S.shelfBtn.tipTitle = GOLD .. "Shelf|r"
    S.shelfBtn.tipText = "Back to your chronicles and loose stories."
    S.shelfBtn:SetScript("OnClick", function()
        local c = ns.ChronicleOf(ns.state.bookStoryId)
        if c then S.OpenVolume(c.id) else S.ShowShelf() end
    end)
    S.chrBtn = UI.CreateSleekButton(B.right, 76, 22, "Chronicle")
    S.chrBtn.tipTitle = GOLD .. "Chronicle|r"
    S.chrBtn.tipText = "Put this story in a volume, or take it out."
    S.prevBtn = UI.CreateSleekButton(B.right, 44, 22, "< Prev", "tool")
    S.nextBtn = UI.CreateSleekButton(B.right, 44, 22, "Next >", "tool")
    S.prevBtn:SetScript("OnClick", function() OpenStory(ns.ChronicleNeighbor(ns.state.bookStoryId, -1)) end)
    S.nextBtn:SetScript("OnClick", function() OpenStory(ns.ChronicleNeighbor(ns.state.bookStoryId, 1)) end)
    B.rowLeft = { S.shelfBtn, S.prevBtn, S.nextBtn, S.chrBtn, B.shareBtn, B.editBtn, B.reimportBtn, B.recBtn }

    -- the Chronicle menu: every volume, a new one, take out
    local menu = CreateFrame("Frame", "RPChroniclerChronicleMenu", UIParent, UI.BACKDROP)
    menu:SetFrameStrata("FULLSCREEN_DIALOG")
    menu:SetSize(200, 10)
    menu:EnableMouse(true)
    menu:Hide()
    UI.ApplyDarkGlass(menu, 0.05, 0.07, 0.10, 0.97, 0.82, 0.65, 0.30, 0.90)
    if type(UISpecialFrames) == "table" then table.insert(UISpecialFrames, "RPChroniclerChronicleMenu") end
    local items = {}
    local function Item(i)
        local b = items[i]
        if b then return b end
        b = UI.CreateSleekButton(menu, 188, 20, "")
        b:SetPoint("TOPLEFT", 6, -6 - (i - 1) * 22)
        b:HookScript("OnClick", function() menu:Hide() end)
        items[i] = b
        return b
    end
    function S.OpenChronicleMenu(anchor)
        local sid = ns.state.bookStoryId
        if not sid then return end
        local cur = ns.ChronicleOf(sid)
        local n = 0
        for _, b in ipairs(items) do b:Hide() end
        for _, c in ipairs(ns.GetChronicles()) do
            n = n + 1
            local b = Item(n)
            local mark = (c == cur) and "|cff5cb85c(in it)|r " or ""
            b:SetText(mark .. "|cfff5e6c8" .. Cut(c.title, 26) .. "|r")
            b:SetScript("OnClick", function() ns.AddStoryToChronicle(sid, c.id) end)
            b:Show()
        end
        n = n + 1
        local nb = Item(n)
        nb:SetText(GOLD .. "+ New chronicle...|r")
        nb:SetScript("OnClick", function()
            UI.AskLine({
                title = GOLD .. "New chronicle|r",
                sub = "|cffb0bac5A name for the volume (up to " .. ns.CHRONICLE_TITLE_MAX .. " letters). This story goes in first.|r",
                placeholder = "The Road of Two Heroes",
                okText = "Create",
                onAccept = function(text)
                    local c = ns.CreateChronicle(text)
                    if c then ns.AddStoryToChronicle(sid, c.id) end
                end,
            })
        end)
        nb:Show()
        if cur then
            n = n + 1
            local ob = Item(n)
            ob:SetText("|cffff8a8aTake out of " .. Cut(cur.title, 18) .. "|r")
            ob:SetScript("OnClick", function() ns.RemoveStoryFromChronicle(sid) end)
            ob:Show()
        end
        menu:SetHeight(12 + n * 22)
        menu:ClearAllPoints()
        menu:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -2)
        menu:Show()
    end
    S.chrBtn:SetScript("OnClick", function(self)
        if menu:IsShown() then menu:Hide() else S.OpenChronicleMenu(self) end
    end)
    B.root:HookScript("OnHide", function() menu:Hide() end)
end

-- Shows Prev/Next only inside a chronicle
local function SyncReaderButtons()
    local sid = ns.state.bookStoryId
    local c = sid and ns.ChronicleOf(sid)
    S.prevBtn:SetShown(c and true or false)
    S.nextBtn:SetShown(c and true or false)
    if c then
        if ns.ChronicleNeighbor(sid, -1) then S.prevBtn:Enable() else S.prevBtn:Disable() end
        if ns.ChronicleNeighbor(sid, 1) then S.nextBtn:Enable() else S.nextBtn:Disable() end
        S.chrBtn:SetText("|cfff5e6c8" .. Cut(c.title, 14) .. "|r")
    else
        S.chrBtn:SetText("Chronicle")
    end
    S.chrBtn:SetWidth(math.max(76, (S.chrBtn.label:GetStringWidth() or 60) + 16))
end

-- Every Story Book refresh goes through the current view
do
    local readerRefresh = UI.RefreshStoryBook
    function UI.RefreshStoryBook(...)
        local view = View()
        if view == "READ" or #ns.GetStories() == 0 and #ns.GetChronicles() == 0 then
            S.shelfFrame:Hide()
            S.volFrame:Hide()
            B.list:Show()
            readerRefresh(...)
            SyncReaderButtons()
            if B.right:IsShown() then UI.LayoutStoryBook() end
        elseif view == "VOLUME" and ns.FindChronicle(S.volId) then
            ShowOverlay("VOLUME")
            S.RefreshVolume()
        else
            S.ShowShelf()
        end
    end
end

ns.Listen("chronicleChanged", function()
    if UI.frame:IsShown() and ns.state.section == "BOOK" then UI.RefreshStoryBook() end
end)

UI.AddReflow(function()
    if S.shelfFrame:IsVisible() then S.RefreshShelf() end
    if S.volFrame:IsVisible() then S.RefreshVolume() end
end)
