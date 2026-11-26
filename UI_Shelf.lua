local ADDON_NAME, ns = ...
local UI = ns.UI

-- =========================================================
-- THE SHELF (0.6.6, redrawn in 0.6.7, Mor): the Story Book opens on a
-- room with a bookshelf. Chronicles stand on the top shelf as leather
-- volumes in their own color; stories in no chronicle stand below as
-- thinner books, colored by their run type. Each spine has gold bands and
-- a title plate (Media/Book, drawn by tools/book/make_book_art.py). New
-- stories glow until opened. A search box finds stories by title, place,
-- party member or date. Clicking a book opens it (UI_Book.lua).
-- Saved data changes only through the chronicle functions in Stories.lua.
-- =========================================================
local B = UI.storyBook
local S = {}
UI.shelf = S

local ART = "Interface\\AddOns\\RPChronicler\\Media\\Book\\"
local GLOW = "Interface\\AddOns\\RPChronicler\\Media\\Scene\\glow.png"
local GOLD = "|cffffd100"
local LABEL_H, BOOK_MAX_H, PLANK_H, ROW_GAP, GAP = 20, 166, 16, 14, 3
B.TITLE_FONT = "Fonts\\MORPHEUS.TTF"

function B.Art(name) return ART .. name .. ".png" end

-- A small stable number from a story or chronicle id (heights, shades)
function B.Hash(s)
    local h = 7
    s = tostring(s or "")
    for i = 1, #s do h = (h * 31 + s:byte(i)) % 100003 end
    return h
end

-- Leather colors of loose stories, by run type
local KIND_COLORS = {
    world = { { 0.14, 0.38, 0.18 }, { 0.10, 0.38, 0.40 }, { 0.30, 0.36, 0.14 } },
    dungeon = { { 0.50, 0.12, 0.12 }, { 0.40, 0.24, 0.14 }, { 0.46, 0.32, 0.10 } },
    raid = { { 0.34, 0.16, 0.44 }, { 0.40, 0.12, 0.30 } },
}

-- The color a book is bound in: its chronicle's color, or one by run
-- type for a loose story. Lifted for the grey leather it tints.
function B.BookColor(open)
    local col
    if open and open.kind == "chronicle" then
        local c = ns.FindChronicle(open.id)
        col = ns.CHRONICLE_COLORS[tonumber(c and c.color) or 1] or ns.CHRONICLE_COLORS[1]
    else
        local st = open and ns.FindStory(open.id)
        local set = KIND_COLORS[(st and st.kind) or "world"] or KIND_COLORS.world
        col = set[(B.Hash(open and open.id) % #set) + 1]
    end
    return math.min(1, col[1] * 1.7), math.min(1, col[2] * 1.7), math.min(1, col[3] * 1.7)
end

function B.Sound(name)
    if PlaySound and SOUNDKIT and SOUNDKIT[name] then pcall(PlaySound, SOUNDKIT[name]) end
end

-- One line, cut with "..." to fit `n` letters
function B.Cut(text, n)
    text = tostring(text or "")
    if #text <= n then return text end
    return text:sub(1, n - 2):match("^(.-)%s*$") .. "..."
end
local Cut = B.Cut

-- Date, place, run type, party and length of a story, for tooltips
function B.StoryTip(owner, st)
    local info = ns.GetBookInfo(st)
    local words = 0
    for _ in ns.StripColors(st.story or ""):gmatch("%S+") do words = words + 1 end
    local place = (info.instance ~= "" and info.instance) or info.zone or ""
    UI.Tooltip(owner, GOLD .. ns.StripColors(info.name or info.title or "") .. "|r",
        (info.date or "") .. (place ~= "" and ("  -  " .. place) or ""),
        ns.GetRunKindLabel(st) .. "  -  " .. (info.duration or ""),
        "Party: " .. ((info.party ~= "" and info.party) or "solo"),
        string.format("%d words, %d chapters", words, #(info.chapters or {})),
        "|cff8f9ba8Click to open the book.|r")
end

-- A texture that repeats instead of stretching (guarded: some clients
-- take no wrap modes, then it stretches)
function B.Tile(tex, path, w, h, tw, th)
    local ok = pcall(tex.SetTexture, tex, path, "REPEAT", "REPEAT")
    if not ok then tex:SetTexture(path) end
    if ok and w and h then
        tex:SetTexCoord(0, math.max(1, w / tw), 0, math.max(1, h / th))
    end
end

-- Darkens the edges of a frame (shade.png turned to each side)
function B.Vignette(f, size, alpha)
    local c = {
        { "LEFT", 0, 1, 0, 1 }, { "RIGHT", 1, 0, 0, 1 },
    }
    for _, e in ipairs(c) do
        local t = f:CreateTexture(nil, "BORDER")
        t:SetTexture(B.Art("shade"))
        t:SetTexCoord(e[2], e[3], e[4], e[5])
        t:SetPoint("TOP" .. e[1], 0, 0)
        t:SetPoint("BOTTOM" .. e[1], 0, 0)
        t:SetWidth(size)
        t:SetAlpha(alpha)
    end
    -- top and bottom: the gradient turned a quarter
    local top = f:CreateTexture(nil, "BORDER")
    top:SetTexture(B.Art("shade"))
    top:SetTexCoord(0, 0, 1, 0, 0, 1, 1, 1)
    top:SetPoint("TOPLEFT", 0, 0)
    top:SetPoint("TOPRIGHT", 0, 0)
    top:SetHeight(size * 0.6)
    top:SetAlpha(alpha)
    local bottom = f:CreateTexture(nil, "BORDER")
    bottom:SetTexture(B.Art("shade"))
    bottom:SetTexCoord(1, 0, 0, 0, 1, 1, 0, 1)
    bottom:SetPoint("BOTTOMLEFT", 0, 0)
    bottom:SetPoint("BOTTOMRIGHT", 0, 0)
    bottom:SetHeight(size * 0.6)
    bottom:SetAlpha(alpha)
end

-- Can this client turn text? (FontString:SetRotation; tested once, so a
-- client without it gets flat titles in the gold plate)
do
    local probe = UIParent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    B.canRotate = probe.SetRotation and pcall(probe.SetRotation, probe, math.pi / 2) and true or false
    probe:Hide()
end

-- =========================================================
-- The room: boards behind, shelves, a header and a one-line viewer tip
-- =========================================================
do
    local f = CreateFrame("Frame", nil, B.root)
    f:SetAllPoints(B.root)
    f:SetFrameLevel((B.root:GetFrameLevel() or 1) + 20)
    f:EnableMouse(true)
    f:Hide()
    S.frame = f
    local wall = f:CreateTexture(nil, "BACKGROUND")
    wall:SetAllPoints(f)
    wall:SetVertexColor(0.85, 0.85, 0.85)
    S.wall = wall
    B.Vignette(f, 90, 0.85)

    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 14, -10)
    pcall(title.SetFont, title, B.TITLE_FONT, 20, "")
    title:SetShadowOffset(1, -2)
    title:SetShadowColor(0, 0, 0, 1)
    title:SetText(GOLD .. "Your shelf|r")

    S.newBtn = UI.CreateSleekButton(f, 112, 20, "+ New chronicle", "gold")
    S.newBtn:SetPoint("TOPRIGHT", -12, -10)
    S.newBtn.tipTitle = GOLD .. "New chronicle|r"
    S.newBtn.tipText = "A volume for stories that belong together, like the road of an alt you level with a friend."
    S.importBtn = UI.CreateSleekButton(f, 64, 20, "+ Import")
    if B.CHRONICLES then
        S.importBtn:SetPoint("RIGHT", S.newBtn, "LEFT", -6, 0)
    else
        S.newBtn:Hide()
        S.importBtn:SetPoint("TOPRIGHT", -12, -10)
    end
    S.importBtn.tipTitle = GOLD .. "Import Story|r"
    S.importBtn.tipText = "Paste a colored story and pick the run it belongs to."
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
        S.Refresh()
    end)
    box:SetScript("OnEnter", function(self)
        UI.Tooltip(self, GOLD .. "Search|r", B.CHRONICLES and "Finds stories by title, place, party member, date or chronicle, on every shelf." or "Finds stories by title, place, party member or date.")
    end)
    box:SetScript("OnLeave", UI.HideTooltip)
    S.search = box

    -- 0.6.7: the viewer tip is one line here (it was a box in the reader)
    local tip = CreateFrame("Frame", nil, f, UI.BACKDROP)
    tip:SetHeight(24)
    tip:SetPoint("BOTTOMLEFT", 12, 10)
    tip:SetPoint("BOTTOMRIGHT", -12, 10)
    UI.ApplyDarkGlass(tip, 0.05, 0.04, 0.03, 0.85, 0.45, 0.34, 0.16, 0.8)
    local tt = tip:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    tt:SetPoint("LEFT", 8, 0)
    tt:SetPoint("RIGHT", -30, 0)
    tt:SetJustifyH("LEFT")
    tt:SetWordWrap(false)
    tt:SetText(GOLD .. "Read with screenshots:|r |cffd7c4a3open a book, then Book > Read outside the game (StoryViewer.html).|r")
    local x = UI.CreateSleekButton(tip, 20, 18, "x", "danger")
    x:SetPoint("RIGHT", -3, 0)
    x.tipTitle = GOLD .. "Hide this tip|r"
    x.tipText = "Bring it back in Options > AI & Stories."
    x:SetScript("OnClick", function()
        ns.Set("exportTip", false)
        S.Refresh()
    end)
    S.tip = tip

    local scroll = CreateFrame("ScrollFrame", "RPChroniclerShelfScroll", f, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 10, -40)
    scroll:SetPoint("BOTTOMRIGHT", -30, 10)
    scroll.scrollBarHideable = true
    local child = CreateFrame("Frame", nil, scroll)
    child:SetSize(400, 10)
    scroll:SetScrollChild(child)
    S.scroll, S.child = scroll, child
    S.spines, S.planks, S.labels, S.rows = {}, {}, {}, {}

    S.emptyText = child:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    S.emptyText:SetPoint("TOPLEFT", 6, -8)
    S.emptyText:SetPoint("RIGHT", child, "RIGHT", -6, 0)
    S.emptyText:SetJustifyH("LEFT")
    S.emptyText:SetWordWrap(true)
end

-- =========================================================
-- A book on the shelf
-- =========================================================
local function SpineEnter(self)
    if self.x then self:SetPoint("BOTTOMLEFT", S.child, "TOPLEFT", self.x, self.y + 8) end
    self.leather:SetVertexColor(math.min(1, self.r * 1.2), math.min(1, self.g * 1.2), math.min(1, self.b * 1.2))
    if self.open.kind == "chronicle" then
        local c = ns.FindChronicle(self.open.id)
        if not c then return end
        local stories = ns.ChronicleStories(c)
        UI.Tooltip(self, GOLD .. c.title .. "|r",
            string.format("%d %s", #stories, #stories == 1 and "story" or "stories"),
            "|cff8f9ba8Click to open the book.|r")
    else
        local st = ns.FindStory(self.open.id)
        if st then B.StoryTip(self, st) end
    end
end

local function SpineLeave(self)
    if self.x then self:SetPoint("BOTTOMLEFT", S.child, "TOPLEFT", self.x, self.y) end
    self.leather:SetVertexColor(self.r, self.g, self.b)
    UI.HideTooltip()
end

local function MakeSpine()
    local b = CreateFrame("Button", nil, S.child)
    b.glow = b:CreateTexture(nil, "BACKGROUND")
    b.glow:SetTexture(GLOW)
    b.glow:SetPoint("TOPLEFT", -14, 14)
    b.glow:SetPoint("BOTTOMRIGHT", 14, -6)
    b.glow:SetVertexColor(1, 0.82, 0.30, 0.9)
    b.glow:Hide()
    if b.CreateAnimationGroup then
        local ag = b:CreateAnimationGroup()
        local ok = pcall(function()
            local a = ag:CreateAnimation("Alpha")
            a:SetFromAlpha(0.25)
            a:SetToAlpha(1)
            a:SetDuration(0.9)
            a:SetTarget(b.glow)
            ag:SetLooping("BOUNCE")
        end)
        if ok then b.glowAnim = ag end
    end
    b.leather = b:CreateTexture(nil, "ARTWORK", nil, 1)
    b.leather:SetAllPoints(b)
    b.leather:SetTexture(B.Art("leather"))
    b.trim = b:CreateTexture(nil, "ARTWORK", nil, 3)
    b.trim:SetAllPoints(b)
    b.trim:SetTexture(B.Art("trim"))
    -- a thin dark line between neighbors
    b.edge = b:CreateTexture(nil, "ARTWORK", nil, 4)
    b.edge:SetTexture(UI.SOLID_TEX)
    b.edge:SetVertexColor(0, 0, 0, 0.55)
    b.edge:SetPoint("TOPLEFT", 0, 0)
    b.edge:SetPoint("BOTTOMLEFT", 0, 0)
    b.edge:SetWidth(1)
    b.title = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    b.title:SetShadowOffset(1, -1)
    b.title:SetShadowColor(0, 0, 0, 1)
    b.title:SetJustifyH("CENTER")
    b.icon = b:CreateTexture(nil, "OVERLAY")
    b.icon:SetSize(14, 14)
    b.icon:SetPoint("BOTTOM", 0, 7)
    b:SetScript("OnEnter", SpineEnter)
    b:SetScript("OnLeave", SpineLeave)
    b:SetScript("OnClick", function(self)
        UI.HideTooltip()
        if B.OpenBook then B.OpenBook(self.open) end
    end)
    return b
end

-- The title along the spine (turned), or flat in the plate when the
-- client can't turn text
local function SpineTitle(b, text, w, h)
    local fs = b.title
    text = ns.StripColors(text or "")
    fs:ClearAllPoints()
    if B.canRotate then
        local len = math.floor(h * 0.46) - 6
        pcall(fs.SetFont, fs, B.TITLE_FONT, w >= 44 and 12 or 10, "")
        fs:SetWordWrap(false)
        fs:SetWidth(len)
        fs:SetText(text)
        local n = #text
        while n > 4 and (fs:GetStringWidth() or 0) > len do
            n = n - 1
            fs:SetText(Cut(text, n))
        end
        fs:SetPoint("CENTER", b, "CENTER", 0, 0)
        pcall(fs.SetRotation, fs, math.pi / 2)
    else
        pcall(fs.SetFont, fs, "Fonts\\FRIZQT__.TTF", 8, "")
        fs:SetWordWrap(true)
        if fs.SetMaxLines then fs:SetMaxLines(5) end
        fs:SetWidth(w - 14)
        fs:SetText(Cut(text, 40))
        fs:SetPoint("CENTER", b, "CENTER", 0, 0)
    end
    fs:SetTextColor(0.98, 0.89, 0.66)
end

local function Glow(b, on)
    if on then
        b.glow:Show()
        if b.glowAnim and not b.glowAnim:IsPlaying() then b.glowAnim:Play() end
    else
        b.glow:Hide()
        if b.glowAnim then b.glowAnim:Stop() end
    end
end

-- A search result row
local function MakeRow(parent)
    local r = CreateFrame("Button", nil, parent, UI.BACKDROP)
    r:SetHeight(34)
    UI.ApplyDarkGlass(r, 0.08, 0.06, 0.04, 0.92, 0.40, 0.31, 0.16, 0.85)
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
        if self.story then B.StoryTip(self, self.story) end
    end)
    r:SetScript("OnLeave", function(self)
        self:SetBackdropBorderColor(0.40, 0.31, 0.16, 0.85)
        UI.HideTooltip()
    end)
    r:SetScript("OnClick", function(self) UI.OpenStoryBook(self.story.id) end)
    return r
end

local function Plank(i, y, w)
    local p = S.planks[i]
    if not p then
        p = S.child:CreateTexture(nil, "ARTWORK", nil, 5)
        p.shadow = S.child:CreateTexture(nil, "ARTWORK", nil, 4)
        p.shadow:SetTexture(B.Art("shade"))
        p.shadow:SetTexCoord(0, 0, 1, 0, 0, 1, 1, 1)
        p.shadow:SetVertexColor(1, 1, 1, 0.9)
        S.planks[i] = p
    end
    p:ClearAllPoints()
    p:SetPoint("TOPLEFT", S.child, "TOPLEFT", 0, y)
    p:SetSize(w, PLANK_H)
    B.Tile(p, B.Art("wood"), w, PLANK_H, 512, PLANK_H)
    p.shadow:ClearAllPoints()
    p.shadow:SetPoint("TOPLEFT", p, "BOTTOMLEFT", 0, 0)
    p.shadow:SetPoint("TOPRIGHT", p, "BOTTOMRIGHT", 0, 0)
    p.shadow:SetHeight(12)
    p:Show()
    p.shadow:Show()
end

local function Label(i, y, text)
    local l = S.labels[i]
    if not l then
        l = S.child:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        l:SetShadowOffset(1, -1)
        l:SetShadowColor(0, 0, 0, 1)
        l:SetJustifyH("LEFT")
        S.labels[i] = l
    end
    l:ClearAllPoints()
    l:SetPoint("TOPLEFT", S.child, "TOPLEFT", 6, y)
    l:SetPoint("RIGHT", S.child, "RIGHT", -6, 0)
    l:SetText(text)
    l:Show()
end

-- =========================================================
-- Fills the shelf (or the search results)
-- =========================================================
function S.Refresh()
    if not S.frame:IsShown() then return end
    local fw, fh = S.frame:GetWidth() or 500, S.frame:GetHeight() or 400
    B.Tile(S.wall, B.Art("wall"), fw, fh, 256, 256)
    S.scroll:ClearAllPoints()
    S.scroll:SetPoint("TOPLEFT", 10, -40)
    if ns.Get("exportTip") then
        S.tip:Show()
        S.scroll:SetPoint("BOTTOMRIGHT", -30, 40)
    else
        S.tip:Hide()
        S.scroll:SetPoint("BOTTOMRIGHT", -30, 10)
    end
    local w = math.max(200, (S.scroll:GetWidth() or 400) - 4)
    S.child:SetWidth(w)
    for _, x in ipairs(S.spines) do x:Hide() end
    for _, x in ipairs(S.planks) do x:Hide(); x.shadow:Hide() end
    for _, x in ipairs(S.labels) do x:Hide() end
    for _, x in ipairs(S.rows) do x:Hide() end
    S.emptyText:Hide()

    -- search results instead of the shelf
    if S.query and S.query:match("%S") then
        local found = ns.SearchStories(S.query)
        for i, st in ipairs(found) do
            local r = S.rows[i] or MakeRow(S.child)
            S.rows[i] = r
            local info = ns.GetBookInfo(st)
            local c = B.CHRONICLES and ns.ChronicleOf(st.id)
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
            S.emptyText:SetText("|cffd7c4a3No story matches \"" .. S.query .. "\".|r")
            S.emptyText:Show()
        end
        S.child:SetHeight(math.max(10, #found * 38))
        return
    end

    -- the shelf: chronicles on top, loose stories below, rows that wrap
    local nSpine, nPlank, nLabel, y = 0, 0, 0, 0
    local function Group(label, items)
        nLabel = nLabel + 1
        Label(nLabel, -y, label)
        local x, base = 8, y + LABEL_H + BOOK_MAX_H
        local function NewRow()
            nPlank = nPlank + 1
            Plank(nPlank, -base, w)
        end
        NewRow()
        for _, it in ipairs(items) do
            if x + it.w > w - 8 and x > 8 then
                x = 8
                base = base + PLANK_H + ROW_GAP + BOOK_MAX_H
                NewRow()
            end
            nSpine = nSpine + 1
            local b = S.spines[nSpine] or MakeSpine()
            S.spines[nSpine] = b
            b.open = it.open
            b.r, b.g, b.b = B.BookColor(it.open)
            b:SetSize(it.w, it.h)
            b.leather:SetVertexColor(b.r, b.g, b.b)
            SpineTitle(b, it.title, it.w, it.h)
            if it.icon then
                b.icon:SetTexture(it.icon)
                b.icon:SetTexCoord(ns.IconCoords(it.icon))
                b.icon:Show()
            else
                b.icon:Hide()
            end
            Glow(b, it.new)
            b.x, b.y = x, -base
            b:ClearAllPoints()
            b:SetPoint("BOTTOMLEFT", S.child, "TOPLEFT", x, -base)
            b:Show()
            x = x + it.w + GAP
        end
        y = base + PLANK_H + ROW_GAP + 6
        return #items
    end

    local vols, loose = {}, {}
    for _, c in ipairs(B.CHRONICLES and ns.GetChronicles() or {}) do
        local stories = ns.ChronicleStories(c)
        local new = false
        for _, st in ipairs(stories) do if B.IsNew(st) then new = true end end
        table.insert(vols, { open = { kind = "chronicle", id = c.id }, title = c.title, new = new,
            w = 44 + math.min(6, #stories) * 3, h = 140 + (B.Hash(c.id) % 24) })
    end
    for _, st in ipairs(B.CHRONICLES and ns.LooseStories() or ns.GetStories()) do
        table.insert(loose, { open = { kind = "story", id = st.id }, title = ns.GetBookInfo(st).name, new = B.IsNew(st),
            w = 32 + (B.Hash(st.id) % 7), h = 120 + (B.Hash(st.id .. "h") % 26) })
    end
    if B.CHRONICLES then
        Group("|cffc8b48cCHRONICLES|r" .. (#vols == 0 and "   |cff8f9ba8None yet: + New chronicle makes a volume for stories that belong together.|r" or ""), vols)
        if #loose > 0 then Group("|cffc8b48cLOOSE STORIES|r", loose) end
    else
        Group("|cffc8b48cYOUR STORIES|r   |cff8f9ba8Newest first. Click a book to open it.|r", loose)
    end
    S.child:SetHeight(math.max(10, y))
end

function B.ShowShelf()
    S.frame:Show()
    S.Refresh()
end

function B.HideShelf()
    S.frame:Hide()
end

-- =========================================================
-- New chronicle: a name (at most 32 letters), then its book opens
-- =========================================================
function S.NewChronicle(storyId)
    UI.AskLine({
        title = GOLD .. "New chronicle|r",
        sub = "|cffb0bac5A name for the volume (up to " .. ns.CHRONICLE_TITLE_MAX .. " letters)." ..
            (storyId and " This story goes in first." or "") .. "|r",
        placeholder = "The Road of Two Heroes",
        okText = "Create",
        onAccept = function(text)
            local c = ns.CreateChronicle(text)
            if not c then return end
            if storyId then
                ns.AddStoryToChronicle(storyId, c.id)
            elseif B.OpenBook then
                B.OpenBook({ kind = "chronicle", id = c.id })
            end
        end,
    })
end
S.newBtn:SetScript("OnClick", function() S.NewChronicle(nil) end)

-- =========================================================
-- The chronicle menu: every volume, a new one, take out (the book's
-- "Add to a chronicle" opens it)
-- =========================================================
do
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
    function S.OpenChronicleMenu(anchor, sid)
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
        nb:SetScript("OnClick", function() S.NewChronicle(sid) end)
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
        menu:SetPoint("TOPRIGHT", anchor, "BOTTOMRIGHT", 0, -2)
        menu:Show()
    end
    B.root:HookScript("OnHide", function() menu:Hide() end)
end

ns.Listen("chronicleChanged", function()
    if UI.frame:IsShown() and ns.state.section == "BOOK" then UI.RefreshStoryBook() end
end)

UI.AddReflow(function()
    if S.frame:IsVisible() then S.Refresh() end
end)
