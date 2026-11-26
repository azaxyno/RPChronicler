local ADDON_NAME, ns = ...
local UI = ns.UI

-- =========================================================
-- THE OPEN BOOK (0.6.7, Mor): opening a story or a chronicle fills the
-- Story Book with an open book on a dark desk. A story's first page is
-- its title page (the party scene, title, place, date, run, party, tally
-- and its chapters); each chapter then starts on a new page, a boss's
-- panel at the top of the chapter that first names it. A chronicle opens
-- on its cover and contents, then its stories in order, each with its
-- own title page on a left-hand page.
--
-- Pages are measured, not scrolled: K.Paginate lays every item out with
-- the real fonts at the real page size (again after a resize), and
-- K.Render draws the two pages on show. Turn with the Previous / Next
-- arrows under the pages, the mouse wheel or Contents. The open, turn and close animations are Scale
-- and Alpha AnimationGroups (Options: Book animations); without them, or
-- on a client that lacks them, everything simply happens at once.
-- On parchment, story colors are inked darker so they read on paper
-- (Options: Pages = Night keeps them as written).
-- =========================================================
local B = UI.storyBook
local S = UI.shelf
local K = { at = 1, last = {} }
UI.book = K

local GOLD = "|cffffd100"
local BODY_FONT = "Fonts\\FRIZQT__.TTF"
local PAD_X, PAD_GUTTER, PAD_TOP, PAD_BOTTOM = 22, 30, 20, 30
local BORDER = 14       -- the leather around the pages
local SPACING = 3       -- between lines of a paragraph
local PARA_GAP = 6      -- between paragraphs

-- =========================================================
-- Ink: story colors darkened until they read on parchment
-- =========================================================
do
    local cache = {}
    local function Lin(c) return c <= 0.04045 and c / 12.92 or ((c + 0.055) / 1.055) ^ 2.4 end
    local function Srgb(c) return c <= 0.0031308 and 12.92 * c or 1.055 * c ^ (1 / 2.4) - 0.055 end
    function K.Ink(hex)
        hex = hex:lower()
        if cache[hex] then return cache[hex] end
        local r = Lin(tonumber(hex:sub(1, 2), 16) / 255)
        local g = Lin(tonumber(hex:sub(3, 4), 16) / 255)
        local b = Lin(tonumber(hex:sub(5, 6), 16) / 255)
        -- 0.6.7 (Mor's test): the first ink (luminance 0.07) read pale in
        -- game. Grays and near-whites (a story's body color) become the
        -- body ink; every other color is darkened to 0.035 and made a bit
        -- more saturated, so names stay colored but read like ink.
        local hi, lo = math.max(r, g, b), math.min(r, g, b)
        if hi <= 0 or (hi - lo) / hi < 0.22 then
            cache[hex] = "1c1208"
            return "1c1208"
        end
        r, g, b = r - lo * 0.6, g - lo * 0.6, b - lo * 0.6
        local lum = 0.2126 * r + 0.7152 * g + 0.0722 * b
        local k = lum > 0.035 and 0.035 / lum or 1
        local function C(v) return math.floor(Srgb(math.min(1, v * k)) * 255 + 0.5) end
        local out = string.format("%02x%02x%02x", C(r), C(g), C(b))
        cache[hex] = out
        return out
    end
end

function K.Night() return ns.Get("bookPages") == "NIGHT" end

-- Text in this page style: inked on parchment, as written at night
function K.Inked(text)
    if K.Night() or type(text) ~= "string" then return text end
    return (text:gsub("|c(%x%x)(%x%x%x%x%x%x)", function(a, hex) return "|c" .. a .. K.Ink(hex) end))
end

-- The colors of a page style
function K.Style()
    if K.Night() then
        return { body = { 0.93, 0.88, 0.78 }, head = "ffd100", muted = "b8a27a", shadow = 0.9, tex = "night" }
    end
    return { body = { 0.11, 0.07, 0.03 }, head = "5e1208", muted = "5a3a1a", shadow = 0, tex = "page" }
end

-- The color code still open at the end of `text` (to carry over a split)
local function OpenColor(text)
    local open, i = nil, 1
    while true do
        local s = text:find("|", i, true)
        if not s then break end
        local nx = text:sub(s + 1, s + 1)
        if nx == "c" and text:sub(s + 2, s + 9):match("^%x%x%x%x%x%x%x%x$") then
            open = text:sub(s, s + 9)
            i = s + 10
        elseif nx == "r" then
            open = nil
            i = s + 2
        else
            i = s + 1
        end
    end
    return open
end

-- =========================================================
-- The desk, the top bar and the book itself
-- =========================================================
do
    local f = CreateFrame("Frame", nil, B.root)
    f:SetAllPoints(B.root)
    f:SetFrameLevel((B.root:GetFrameLevel() or 1) + 20)
    f:EnableMouse(true)
    f:EnableMouseWheel(true)
    f:Hide()
    K.frame = f
    K.desk = f:CreateTexture(nil, "BACKGROUND")
    K.desk:SetAllPoints(f)
    K.desk:SetVertexColor(0.38, 0.36, 0.34)
    B.Vignette(f, 110, 0.95)
    f:SetScript("OnMouseWheel", function(_, delta) K.Wheel(delta) end)

    K.closeBtn = UI.CreateSleekButton(f, 100, 22, "< Close book", "gold")
    K.closeBtn:SetPoint("TOPLEFT", 12, -8)
    K.closeBtn.tipTitle = GOLD .. "Close book|r"
    K.closeBtn.tipText = "Closes the book and puts it back on the shelf."
    K.closeBtn:SetScript("OnClick", function() K.Close() end)

    K.menuBtn = UI.CreateSleekButton(f, 64, 22, "Book")
    K.menuBtn:SetPoint("TOPRIGHT", -12, -8)
    K.menuBtn.tipTitle = GOLD .. "Book|r"
    K.menuBtn.tipText = "Share, read outside the game, details, re-import and delete."
    K.tocBtn = UI.CreateSleekButton(f, 72, 22, "Contents")
    K.tocBtn:SetPoint("RIGHT", K.menuBtn, "LEFT", -6, 0)
    K.tocBtn.tipTitle = GOLD .. "Contents|r"
    K.tocBtn.tipText = "Back to the first pages: the cover and contents, or the story's title page."
    K.tocBtn:SetScript("OnClick", function() K.GoTo(1) end)
    K.pageText = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    K.pageText:SetPoint("RIGHT", K.tocBtn, "LEFT", -10, 0)
    K.pageText:SetJustifyH("RIGHT")

    K.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    K.title:SetPoint("LEFT", K.closeBtn, "RIGHT", 12, 0)
    K.title:SetPoint("RIGHT", K.pageText, "LEFT", -12, 0)
    K.title:SetJustifyH("CENTER")
    K.title:SetWordWrap(false)
    pcall(K.title.SetFont, K.title, B.TITLE_FONT, 17, "")
    K.title:SetShadowOffset(1, -2)
    K.title:SetShadowColor(0, 0, 0, 1)

    -- the book: leather cover, gold corners, two pages
    local tome = CreateFrame("Frame", nil, f)
    tome:SetPoint("TOPLEFT", 12, -38)
    tome:SetPoint("BOTTOMRIGHT", -12, 12)
    K.tome = tome
    K.leather = tome:CreateTexture(nil, "BACKGROUND")
    K.leather:SetAllPoints(tome)
    K.leather:SetTexture(B.Art("cover"))
    local shadow = tome:CreateTexture(nil, "BACKGROUND", nil, -2)
    shadow:SetTexture(UI.SOLID_TEX)
    shadow:SetVertexColor(0, 0, 0, 0.55)
    shadow:SetPoint("TOPLEFT", 4, -6)
    shadow:SetPoint("BOTTOMRIGHT", 6, -8)
    -- corners: one texture, turned by its coordinates
    local coords = { { "TOPLEFT", 0, 1, 0, 1 }, { "TOPRIGHT", 1, 0, 0, 1 }, { "BOTTOMLEFT", 0, 1, 1, 0 }, { "BOTTOMRIGHT", 1, 0, 1, 0 } }
    for _, c in ipairs(coords) do
        local t = tome:CreateTexture(nil, "OVERLAY", nil, 6)
        t:SetTexture(B.Art("corner"))
        t:SetSize(36, 36)
        t:SetPoint(c[1], 0, 0)
        t:SetTexCoord(c[2], c[3], c[4], c[5])
    end
    K.pages = {}
    for i = 1, 2 do
        local p = CreateFrame("Frame", nil, tome)
        p:SetFrameLevel((tome:GetFrameLevel() or 1) + 2)
        p.bg = p:CreateTexture(nil, "BACKGROUND")
        p.bg:SetAllPoints(p)
        p.num = p:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        p.num:SetPoint("BOTTOM", 0, 9)
        pcall(p.num.SetFont, p.num, B.TITLE_FONT, 11, "")
        p.fs, p.tex, p.links = {}, {}, {}
        K.pages[i] = p
    end
    -- 0.6.7 (Mor): clear arrows at the bottom of the pages (the dog-eared
    -- corners of the first build went unnoticed); the wheel still turns
    local function Arrow(d)
        local b = UI.CreateSleekButton(tome, 96, 22, d < 0 and "< Previous" or "Next >", "gold")
        b:SetFrameLevel((tome:GetFrameLevel() or 1) + 30)
        b.tipTitle = GOLD .. (d < 0 and "Previous page" or "Next page") .. "|r"
        b.tipText = "Or the mouse wheel over the book."
        b:SetScript("OnClick", function() K.Turn(d) end)
        return b
    end
    K.prevBtn, K.nextBtn = Arrow(-1), Arrow(1)

    -- a hidden FontString that measures text for the page layout
    K.measure = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    K.measure:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
    K.measure:SetAlpha(0)
    K.measure:SetJustifyH("LEFT")
end

-- Where the pages sit: two side by side, or one when the window is narrow
function K.Layout()
    local w = (K.tome:GetWidth() or 600) - 2 * BORDER
    local h = (K.tome:GetHeight() or 400) - 2 * BORDER
    K.single = w < 460
    local l, r = K.pages[1], K.pages[2]
    l:ClearAllPoints()
    r:ClearAllPoints()
    if K.single then
        l:SetPoint("TOPLEFT", BORDER, -BORDER)
        l:SetPoint("BOTTOMRIGHT", -BORDER, BORDER)
        r:Hide()
        K.pageW = w
    else
        l:SetPoint("TOPLEFT", BORDER, -BORDER)
        l:SetPoint("BOTTOMRIGHT", K.tome, "BOTTOM", 0, BORDER)
        r:SetPoint("TOPLEFT", K.tome, "TOP", 0, -BORDER)
        r:SetPoint("BOTTOMRIGHT", -BORDER, BORDER)
        r:Show()
        K.pageW = math.floor(w / 2)
    end
    K.pageH = h
    K.prevBtn:ClearAllPoints()
    K.prevBtn:SetPoint("BOTTOMLEFT", l, "BOTTOMLEFT", 10, 5)
    K.nextBtn:ClearAllPoints()
    K.nextBtn:SetPoint("BOTTOMRIGHT", K.single and l or r, "BOTTOMRIGHT", -10, 5)
    -- the text area of a page and its type size
    K.cw = K.pageW - PAD_X - PAD_GUTTER
    K.ch = K.pageH - PAD_TOP - PAD_BOTTOM
    K.size = 12 + (K.cw > 300 and 1 or 0) + (K.cw > 400 and 1 or 0) + (K.cw > 520 and 1 or 0)
    local style = K.Style()
    l.bg:SetTexture(B.Art(style.tex))
    r.bg:SetTexture(B.Art(style.tex))
    -- 0.6.7: parchment a shade deeper, so it never washes out to white
    local tone = K.Night() and 1 or 0.88
    l.bg:SetVertexColor(tone, tone * 0.97, tone * 0.92)
    r.bg:SetVertexColor(tone, tone * 0.97, tone * 0.92)
    l.bg:SetTexCoord(0, 1, 0, 1)
    r.bg:SetTexCoord(1, 0, 0, 1)
    -- page numbers in a faded ink
    local m = style.muted
    for _, p in ipairs(K.pages) do
        p.num:SetTextColor(tonumber(m:sub(1, 2), 16) / 255, tonumber(m:sub(3, 4), 16) / 255, tonumber(m:sub(5, 6), 16) / 255)
    end
end

-- The x where text starts on a page (the gutter side gets more room)
local function TextX(side)
    if K.single or side == 2 then return PAD_GUTTER end
    return PAD_X
end

-- =========================================================
-- Measuring
-- =========================================================
function K.Measure(text, size, font, width)
    local m = K.measure
    pcall(m.SetFont, m, font or BODY_FONT, size or K.size, "")
    m:SetSpacing(SPACING)
    m:SetWidth(width or K.cw)
    m:SetWordWrap(true)
    m:SetText(text or "")
    return math.ceil(m:GetStringHeight() or 0)
end

-- The longest start of `text` (whole words) that fits `avail` high, and
-- the rest; colors carry over the cut
function K.SplitToFit(text, avail)
    local words = {}
    for w in text:gmatch("%S+") do table.insert(words, w) end
    if #words < 2 then return nil, text end
    local lo, hi = 0, #words - 1
    while lo < hi do
        local mid = math.floor((lo + hi + 1) / 2)
        if K.Measure(table.concat(words, " ", 1, mid)) <= avail then lo = mid else hi = mid - 1 end
    end
    if lo == 0 then return nil, text end
    local head = table.concat(words, " ", 1, lo)
    local tail = table.concat(words, " ", lo + 1)
    local open = OpenColor(head)
    if open then head = head .. "|r"; tail = open .. tail end
    return head, tail
end

-- =========================================================
-- Paginating: the open book as a list of pages of placed items
-- =========================================================
local function PlainLower(line)
    return ns.StripColors(line or ""):gsub("|T.-|t", ""):gsub("|A.-|a", ""):lower():match("^%s*(.-)%s*$") or ""
end

-- A chapter heading: "Chapter 1: ...", or a Prologue / Epilogue line
function K.IsChapterHead(pl)
    local bare = pl:gsub("^#+%s*", "")
    if bare:match("^chapter%s") then return true end
    for _, w in ipairs({ "prologue", "epilogue", "interlude" }) do
        if bare == w or bare:match("^" .. w .. "%s*[:%-]") then return #bare <= 80 end
    end
    return false
end

-- The story's lines without its header (title, place line, date and
-- party) and its closing tally: the title page shows those
function K.StoryBody(st, info)
    local text = K.Inked(B.StoryText(st))
    local lines = {}
    for line in (text .. "\n"):gmatch("([^\n]*)\n") do table.insert(lines, line) end
    local want = PlainLower(info.name)
    local seen, i = 0, 1
    while i <= #lines and seen < 4 do
        local pl = PlainLower(lines[i])
        if pl ~= "" then
            seen = seen + 1
            local bare = pl:gsub("^#+%s*", "")
            -- line 1 is the title when it is the book's name, labeled, or
            -- a short line that is not a sentence
            -- 0.6.7: and a short place line under it ("Ragefire Chasm -
            -- Beneath Orgrimmar"), which used to fill a page of its own
            local head = K.IsChapterHead(pl)
            local header = not head and ((seen == 1 and (bare == want or pl:match("^title:") or pl:match("^@title")
                    or (#bare <= 100 and not bare:match("[%.!?\"]$"))))
                or (seen <= 3 and #bare <= 80 and not bare:match("[%.!?\":,;]$"))
                or pl:find(" | ", 1, true) or pl:match("^date:") or pl:match("^party:"))
            if not header then break end
            lines[i] = ""
        end
        i = i + 1
    end
    for j = #lines, math.max(1, #lines - 3), -1 do
        local pl = PlainLower(lines[j])
        if pl ~= "" then
            if pl:match("bosses") or (pl:find("|", 1, true) and (pl:match("wipes?:") or pl:match("deaths?:") or pl:match("foes") or pl:match("quests?"))) then
                lines[j] = ""
            end
            break
        end
    end
    -- chapters of paragraphs (one line is one paragraph)
    local chapters, cur = {}, nil
    for _, line in ipairs(lines) do
        local pl = PlainLower(line)
        if K.IsChapterHead(pl) then
            cur = { head = ns.StripColors(line):gsub("^%s*#+%s*", ""):match("^%s*(.-)%s*$"), paras = {} }
            table.insert(chapters, cur)
        elseif pl ~= "" then
            if not cur then
                cur = { paras = {} }
                table.insert(chapters, cur)
            end
            table.insert(cur.paras, line)
        end
    end
    return chapters, text
end

local function Add(page, item)
    table.insert(page.items, item)
    return item
end

-- A title page and the chapters of one story
function K.AddStory(pages, st, index, total)
    local info = ns.GetBookInfo(st)
    local style = K.Style()
    local H, W = K.ch, K.cw
    -- in two-page mode a story starts on a left-hand page
    if not K.single and #pages % 2 == 1 then
        local blank = { items = {}, storyId = st.id, blank = true }
        Add(blank, { type = "flourish", y = math.floor(H / 2) - 7, h = 14 })
        table.insert(pages, blank)
    end
    local page = { items = {}, storyId = st.id, titlePage = true }
    table.insert(pages, page)
    local y = 0
    local party = type(st.participants) == "table" and #st.participants > 0
    if ns.Get("storyCover") and party and UI.CreateStoryScene then
        local h = math.floor(math.max(110, math.min(230, H * 0.40)))
        Add(page, { type = "scene", story = st, y = y, h = h })
        y = y + h + 12
    else
        Add(page, { type = "icon", path = ns.GetAdventureIcon(st), y = y + 4, h = 52 })
        y = y + 64
    end
    if index then
        local t = "|cff" .. style.muted .. "Story " .. index .. " of " .. total .. "|r"
        local h = K.Measure(t, K.size - 1)
        Add(page, { type = "text", text = t, size = K.size - 1, center = true, y = y, h = h })
        y = y + h + 4
    end
    local tsize = K.cw > 260 and 21 or 17
    local title = "|cff" .. style.head .. ns.StripColors(info.name or "") .. "|r"
    local th = K.Measure(title, tsize, B.TITLE_FONT)
    Add(page, { type = "text", text = title, size = tsize, font = B.TITLE_FONT, center = true, y = y, h = th })
    y = y + th + 4
    local place = (info.instance ~= "" and info.instance) or info.zone or ""
    if info.zone ~= "" and info.zone ~= place then place = place .. ", " .. info.zone end
    if place ~= "" then
        local t = "|cff" .. style.muted .. place .. "|r"
        local h = K.Measure(t, K.size)
        Add(page, { type = "text", text = t, center = true, y = y, h = h })
        y = y + h + 4
    end
    Add(page, { type = "flourish", y = y + 2, h = 14 })
    y = y + 22
    local function Fact(label, value)
        return "|cff" .. style.muted .. label .. ":|r  " .. value
    end
    local facts = {}
    if (info.date or "") ~= "" then table.insert(facts, Fact("Date", info.date)) end
    table.insert(facts, Fact("Run", ns.GetRunKindLabel(st) .. ((info.duration or "") ~= "" and (", " .. info.duration) or "")))
    table.insert(facts, Fact("Party", (info.party ~= "" and info.party) or "solo"))
    local stats = ns.GetBookStats(info)
    if stats ~= "" then table.insert(facts, K.Inked(stats)) end
    if st.quick then table.insert(facts, "|cff" .. style.muted .. "A Quick Chronicle (test feature), written by RP Chronicler.|r") end
    local ft = table.concat(facts, "\n")
    local fh = K.Measure(ft, K.size - 1)
    Add(page, { type = "text", text = ft, size = K.size - 1, y = y, h = fh })
    y = y + fh + 12

    -- the story's pages; the chapter list on the title page fills in after
    local chapters = K.StoryBody(st, info)
    local bosses = (ns.Get("storyCover") and ns.StoryBosses) and ns.StoryBosses(st, st.story or "") or {}
    local bossAt, used = {}, {}
    for _, ch in ipairs(chapters) do
        for pi, para in ipairs(ch.paras) do
            local pl = PlainLower(para)
            for n, boss in ipairs(bosses) do
                if n <= 8 and not used[boss] and pl:find(boss:lower(), 1, true) then
                    used[boss] = true
                    ch.bossAt = ch.bossAt or {}
                    ch.bossAt[pi] = boss
                end
            end
        end
    end
    local listY, listRoom = y, H - y
    local starts = {}
    local cur, cy
    local function NewPage()
        cur = { items = {}, storyId = st.id }
        table.insert(pages, cur)
        cy = 0
    end
    local lineH = K.Measure("Ag", K.size) + 1
    for ci, ch in ipairs(chapters) do
        NewPage()
        starts[ci] = #pages
        if ch.head then
            local t = "|cff" .. style.head .. ch.head .. "|r"
            local h = K.Measure(t, K.size + 3, B.TITLE_FONT)
            Add(cur, { type = "text", text = t, size = K.size + 3, font = B.TITLE_FONT, center = true, y = cy, h = h })
            cy = cy + h + 2
            Add(cur, { type = "flourish", y = cy + 2, h = 14 })
            cy = cy + 22
        end
        for pi, para in ipairs(ch.paras) do
            local boss = ch.bossAt and ch.bossAt[pi]
            if boss and UI.CreateBossPanel then
                local bh = math.floor(math.max(110, math.min(170, H * 0.38)))
                if cy + bh > H and cy > 0 then NewPage() end
                Add(cur, { type = "boss", story = st, boss = boss, y = cy, h = bh })
                cy = cy + bh + 10
            end
            local t, guard = para, 0
            while t and guard < 50 do
                guard = guard + 1
                local h = K.Measure(t)
                if cy + h <= H or cy == 0 and h > H and K.SplitToFit(t, H) == nil then
                    Add(cur, { type = "text", text = t, y = cy, h = h })
                    cy = cy + h + PARA_GAP
                    t = nil
                elseif H - cy >= lineH * 2 then
                    local head, tail = K.SplitToFit(t, H - cy)
                    if head then
                        Add(cur, { type = "text", text = head, y = cy, h = K.Measure(head) })
                    end
                    NewPage()
                    t = tail
                else
                    NewPage()
                end
            end
        end
    end
    -- the end of the story
    if cur and cy + 30 <= H then
        Add(cur, { type = "flourish", y = cy + 8, h = 14 })
    end
    -- the chapter list on the title page, as far as it fits
    if #chapters > 0 and listRoom > lineH * 3 then
        local t = "|cff" .. style.muted .. "Chapters|r"
        Add(page, { type = "text", text = t, size = K.size - 1, y = listY, h = lineH })
        local ly = listY + lineH + 2
        for ci, ch in ipairs(chapters) do
            if ly + lineH + 4 > H then break end
            Add(page, { type = "link", text = ch.head or "Prologue", page = starts[ci], story = st, y = ly, h = lineH + 4 })
            ly = ly + lineH + 4
        end
    end
    return starts
end

-- The pages of the open book
function K.Paginate()
    local pages = {}
    local open = ns.state.bookOpen
    K.storyPage = {}
    if open.kind == "story" then
        local st = ns.FindStory(open.id)
        if st then
            K.storyPage[st.id] = 1
            K.AddStory(pages, st)
        end
    else
        local c = ns.FindChronicle(open.id)
        local style = K.Style()
        local stories = c and ns.ChronicleStories(c) or {}
        -- the cover page
        local cover = { items = {}, cover = true }
        table.insert(pages, cover)
        local H, y = K.ch, 0
        local tsize = K.cw > 260 and 24 or 19
        local title = "|cff" .. style.head .. (c and c.title or "") .. "|r"
        local th = K.Measure(title, tsize, B.TITLE_FONT)
        local cov = c and ns.ChronicleCover(c)
        local scene = cov and type(cov.participants) == "table" and #cov.participants > 0 and ns.Get("storyCover") and UI.CreateStoryScene
        y = math.floor(H * 0.08)
        Add(cover, { type = "text", text = title, size = tsize, font = B.TITLE_FONT, center = true, y = y, h = th })
        y = y + th + 4
        Add(cover, { type = "flourish", y = y + 2, h = 14 })
        y = y + 26
        if scene then
            local h = math.floor(math.max(110, math.min(240, H * 0.45)))
            Add(cover, { type = "scene", story = cov, y = y, h = h })
            y = y + h + 12
        end
        local first, last = stories[1], stories[#stories]
        local sub
        if first then
            local d1, d2 = (ns.GetBookInfo(first).date or ""):sub(1, 10), (ns.GetBookInfo(last).date or ""):sub(1, 10)
            sub = string.format("%d %s, %s", #stories, #stories == 1 and "story" or "stories",
                (d1 == d2 or d2 == "") and d1 or (d1 .. " to " .. d2))
        else
            sub = "An empty volume"
        end
        local st_ = "|cff" .. style.muted .. sub .. "|r"
        Add(cover, { type = "text", text = st_, center = true, y = y, h = K.Measure(st_) })
        -- the contents (more pages when it is long)
        local lineH = K.Measure("Ag", K.size) + 1
        local rowH = lineH + 6
        local perPage = math.max(3, math.floor((H - 50) / rowH))
        local nToc = math.max(1, math.ceil(#stories / perPage))
        local tocPages = {}
        for i = 1, nToc do
            local p = { items = {}, contents = true }
            table.insert(pages, p)
            tocPages[i] = p
            local head = "|cff" .. style.head .. "Contents|r"
            Add(p, { type = "text", text = head, size = K.size + 3, font = B.TITLE_FONT, center = true, y = 0, h = K.Measure(head, K.size + 3, B.TITLE_FONT) })
            Add(p, { type = "flourish", y = 24, h = 14 })
        end
        if #stories == 0 then
            local t = "|cff" .. style.muted .. "No stories yet. Open a story, then Book > Add to a chronicle puts it here.|r"
            Add(tocPages[1], { type = "text", text = t, y = 50, h = K.Measure(t) })
        end
        local rows = {}
        for i, st in ipairs(stories) do
            local p = tocPages[math.floor((i - 1) / perPage) + 1]
            local y2 = 50 + ((i - 1) % perPage) * rowH
            rows[i] = Add(p, { type = "link", text = i .. ".  " .. ns.StripColors(ns.GetBookInfo(st).name or ""), story = st,
                manage = true, index = i, count = #stories, cover = (cov == st), y = y2, h = rowH })
        end
        for i, st in ipairs(stories) do
            K.AddStory(pages, st, i, #stories)
            for n, pg in ipairs(pages) do
                if pg.storyId == st.id and pg.titlePage then K.storyPage[st.id] = n break end
            end
            rows[i].page = K.storyPage[st.id]
        end
    end
    K.list = pages
    return pages
end

-- =========================================================
-- Drawing a page
-- =========================================================
local function PoolFS(p, i)
    local fs = p.fs[i]
    if not fs then
        fs = p:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        fs:SetJustifyV("TOP")
        p.fs[i] = fs
    end
    return fs
end

local function PoolTex(p, i)
    local t = p.tex[i]
    if not t then
        t = p:CreateTexture(nil, "ARTWORK")
        p.tex[i] = t
    end
    return t
end

local function LinkEnter(self)
    self.hl:Show()
    if self.manage then
        for _, b in ipairs(self.tools) do b:Show() end
    end
    if self.story then B.StoryTip(self, self.story) end
end
local function LinkLeave(self)
    UI.HideTooltip()
    if self.IsMouseOver and self:IsMouseOver() then return end
    self.hl:Hide()
    for _, b in ipairs(self.tools) do b:Hide() end
end

local function PoolLink(p, i)
    local r = p.links[i]
    if r then return r end
    r = CreateFrame("Button", nil, p)
    r:SetFrameLevel(p:GetFrameLevel() + 5)
    r.hl = r:CreateTexture(nil, "BACKGROUND")
    r.hl:SetAllPoints(r)
    r.hl:SetTexture(UI.SOLID_TEX)
    r.hl:SetVertexColor(0.85, 0.62, 0.20, 0.16)
    r.hl:Hide()
    r.label = r:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    r.label:SetPoint("LEFT", 2, 0)
    r.label:SetJustifyH("LEFT")
    r.label:SetWordWrap(false)
    r.num = r:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    r.num:SetPoint("RIGHT", -2, 0)
    r.num:SetJustifyH("RIGHT")
    r.label:SetPoint("RIGHT", r.num, "LEFT", -8, 0)
    -- order and cover tools of a chronicle's contents, shown on hover
    r.tools = {}
    local function Tool(text, tip, fn)
        local b = UI.CreateSleekButton(r, 38, 16, text, "tool")
        b.tipTitle, b.tipText = GOLD .. text .. "|r", tip
        b:SetScript("OnClick", function() fn(r) end)
        b:HookScript("OnLeave", function() LinkLeave(r) end)
        b:Hide()
        table.insert(r.tools, b)
        return b
    end
    local out = Tool("Out", "Takes this story out of the chronicle. It stays in the Story Book.", function(x) ns.RemoveStoryFromChronicle(x.story.id) end)
    out:SetPoint("RIGHT", r.num, "LEFT", -6, 0)
    local cov = Tool("Cover", "Shows this story's party scene on the chronicle's cover.", function(x) ns.SetChronicleCover(ns.state.bookOpen.id, x.story.id) end)
    cov:SetPoint("RIGHT", out, "LEFT", -2, 0)
    local down = Tool("Down", "Moves this story one place later.", function(x) ns.MoveChronicleStory(x.story.id, 1) end)
    down:SetPoint("RIGHT", cov, "LEFT", -2, 0)
    local up = Tool("Up", "Moves this story one place earlier.", function(x) ns.MoveChronicleStory(x.story.id, -1) end)
    up:SetPoint("RIGHT", down, "LEFT", -2, 0)
    r.up, r.down, r.cov = up, down, cov
    r:SetScript("OnEnter", LinkEnter)
    r:SetScript("OnLeave", LinkLeave)
    r:SetScript("OnClick", function(self) if self.page then K.GoTo(self.page) end end)
    p.links[i] = r
    return r
end

-- Draws page `n` of the open book on side `side` (1 left, 2 right)
function K.DrawPage(side, n)
    local p = K.pages[side]
    local style = K.Style()
    for _, x in ipairs(p.fs) do x:Hide() end
    for _, x in ipairs(p.tex) do x:Hide() end
    for _, x in ipairs(p.links) do x:Hide() end
    -- the 3D scene and boss panel stay up when this page shows them
    -- again (hiding them would reload their models)
    local usedScene, usedBoss = false, false
    local function Finish()
        if p.scene and not usedScene then p.scene.frame:Hide() end
        if p.boss and not usedBoss then p.boss:Hide() end
    end
    local page = K.list and K.list[n]
    p.num:SetText(page and tostring(n) or "")
    if not page then return Finish() end
    if page.storyId then B.seen[page.storyId] = true end
    local x0, top = TextX(side), PAD_TOP
    local nfs, ntex, nlink = 0, 0, 0
    for _, it in ipairs(page.items) do
        if it.type == "text" then
            nfs = nfs + 1
            local fs = PoolFS(p, nfs)
            pcall(fs.SetFont, fs, it.font or BODY_FONT, it.size or K.size, "")
            fs:SetSpacing(SPACING)
            fs:SetWidth(K.cw)
            fs:SetWordWrap(true)
            fs:SetJustifyH(it.center and "CENTER" or "LEFT")
            fs:SetTextColor(style.body[1], style.body[2], style.body[3])
            fs:SetShadowOffset(style.shadow > 0 and 1 or 0, style.shadow > 0 and -1 or 0)
            fs:SetShadowColor(0, 0, 0, style.shadow)
            fs:ClearAllPoints()
            fs:SetPoint("TOPLEFT", p, "TOPLEFT", x0, -(top + it.y))
            fs:SetText(it.text)
            fs:Show()
        elseif it.type == "flourish" or it.type == "icon" then
            ntex = ntex + 1
            local t = PoolTex(p, ntex)
            t:ClearAllPoints()
            if it.type == "flourish" then
                t:SetTexture(B.Art("flourish"))
                t:SetTexCoord(0, 1, 0, 1)
                t:SetSize(math.min(160, K.cw * 0.6), 14)
                t:SetVertexColor(K.Night() and 1 or 0.75, K.Night() and 1 or 0.55, K.Night() and 1 or 0.30)
            else
                t:SetTexture(it.path)
                t:SetTexCoord(ns.IconCoords(it.path))
                t:SetSize(it.h, it.h)
                t:SetVertexColor(1, 1, 1)
            end
            t:SetPoint("TOP", p, "TOPLEFT", x0 + K.cw / 2, -(top + it.y))
            t:Show()
        elseif it.type == "link" then
            nlink = nlink + 1
            local r = PoolLink(p, nlink)
            r.story, r.page, r.manage = it.story, it.page, it.manage
            r:ClearAllPoints()
            r:SetPoint("TOPLEFT", p, "TOPLEFT", x0, -(top + it.y))
            r:SetSize(K.cw, it.h)
            for _, fs in ipairs({ r.label, r.num }) do
                pcall(fs.SetFont, fs, BODY_FONT, K.size, "")
                fs:SetTextColor(style.body[1], style.body[2], style.body[3])
                fs:SetShadowOffset(0, 0)
            end
            r.label:SetText(it.text)
            r.num:SetText(it.page and ("|cff" .. style.muted .. it.page .. "|r") or "")
            if it.manage then
                if it.index == 1 then r.up:Disable() else r.up:Enable() end
                if it.index == it.count then r.down:Disable() else r.down:Enable() end
                if it.cover then r.cov:Disable() else r.cov:Enable() end
            end
            r.hl:Hide()
            for _, b in ipairs(r.tools) do b:Hide() end
            r:Show()
        elseif it.type == "scene" and not K.noModels then
            if not p.scene then
                local ok, scene = pcall(UI.CreateStoryScene, p, {
                    bigTip = "Shows this scene in a big window, where you can zoom and look around.",
                    onWheel = function(delta) K.Wheel(delta) end,
                    onBig = function(sc) UI.OpenBigScene(sc.story, sc.view, ns.GetBookInfo(sc.story).name) end,
                })
                if ok and scene then
                    p.scene = scene
                    scene.frame:SetFrameLevel(p:GetFrameLevel() + 4)
                end
            end
            if p.scene then
                usedScene = true
                local sc = p.scene
                sc.frame:ClearAllPoints()
                sc.frame:SetPoint("TOPLEFT", p, "TOPLEFT", x0, -(top + it.y))
                sc.frame:SetSize(K.cw, it.h)
                if sc.story ~= it.story then
                    sc.frame:Show()
                    pcall(sc.SetStory, sc, it.story)
                elseif not sc.frame:IsShown() then
                    sc.frame:Show()
                end
            end
        elseif it.type == "boss" and not K.noModels then
            if not p.boss then
                local ok, panel = pcall(UI.CreateBossPanel, p)
                if ok and panel then
                    p.boss = panel
                    panel:SetFrameLevel(p:GetFrameLevel() + 4)
                end
            end
            if p.boss then
                usedBoss = true
                p.boss:ClearAllPoints()
                p.boss:SetPoint("TOPLEFT", p, "TOPLEFT", x0, -(top + it.y))
                p.boss:SetSize(K.cw, it.h)
                if p.boss.story ~= it.story or p.boss.boss ~= it.boss or not p.boss:IsShown() then
                    p.boss:Show()
                    pcall(p.boss.SetBoss, p.boss, it.story, it.boss)
                end
            end
        end
    end
    Finish()
end

-- Both pages, the corners and the page count
function K.Render(sides)
    local n = #(K.list or {})
    local l, r = K.pages[1], K.pages[2]
    if K.single then
        if not sides or sides[1] then K.DrawPage(1, K.at) end
        if K.at > 1 then K.prevBtn:Enable() else K.prevBtn:Disable() end
        if K.at < n then K.nextBtn:Enable() else K.nextBtn:Disable() end
        K.pageText:SetText("|cffd7c4a3" .. K.at .. " of " .. n .. "|r")
    else
        if not sides or sides[1] then K.DrawPage(1, K.at) end
        if not sides or sides[2] then K.DrawPage(2, K.at + 1) end
        if K.at > 1 then K.prevBtn:Enable() else K.prevBtn:Disable() end
        if K.at + 1 < n then K.nextBtn:Enable() else K.nextBtn:Disable() end
        K.pageText:SetText("|cffd7c4a3" .. K.at .. (K.at + 1 <= n and ("-" .. (K.at + 1)) or "") .. " of " .. n .. "|r")
    end
    if K.list and K.list[K.at] and K.list[K.at].storyId then ns.state.bookStoryId = K.list[K.at].storyId end
    K.last[K.Key()] = K.at
end

function K.Key()
    local o = ns.state.bookOpen or {}
    return tostring(o.kind) .. ":" .. tostring(o.id)
end

-- The first page shown when page `n` is wanted (a spread starts odd)
function K.SpreadOf(n)
    n = math.max(1, math.min(n, #(K.list or {})))
    if K.single then return n end
    return (n % 2 == 1) and n or (n - 1)
end

-- =========================================================
-- Animations (guarded; Options: Book animations)
-- =========================================================
do
    local function ScaleAnim(ag, fromX, fromY, toX, toY, dur, origin, smooth, order, delay)
        local a = ag:CreateAnimation("Scale")
        a:SetScaleFrom(fromX, fromY)
        a:SetScaleTo(toX, toY)
        a:SetDuration(dur)
        a:SetOrigin(origin, 0, 0)
        if smooth then a:SetSmoothing(smooth) end
        if order then a:SetOrder(order) end
        if delay then a:SetStartDelay(delay) end
        return a
    end
    local function AlphaAnim(ag, from, to, dur, order, delay)
        local a = ag:CreateAnimation("Alpha")
        a:SetFromAlpha(from)
        a:SetToAlpha(to)
        a:SetDuration(dur)
        if order then a:SetOrder(order) end
        if delay then a:SetStartDelay(delay) end
        return a
    end
    -- a sheet of paper (or leather) laid over part of the book
    local function Sheet(tex, flip)
        local s = CreateFrame("Frame", nil, K.tome)
        s:SetFrameLevel((K.tome:GetFrameLevel() or 1) + 40)
        s.bg = s:CreateTexture(nil, "ARTWORK")
        s.bg:SetAllPoints(s)
        s.bg:SetTexture(B.Art(tex))
        s.shade = s:CreateTexture(nil, "OVERLAY")
        s.shade:SetAllPoints(s)
        s.shade:SetTexture(B.Art("shade"))
        if flip then s.shade:SetTexCoord(1, 0, 0, 1) end
        s.shade:SetAlpha(0.55)
        s:Hide()
        return s
    end
    local ok = K.tome.CreateAnimationGroup and pcall(function()
        -- the book grows in, then its cover swings open
        K.tomeIn = K.tome:CreateAnimationGroup()
        AlphaAnim(K.tomeIn, 0, 1, 0.16)
        ScaleAnim(K.tomeIn, 0.90, 0.90, 1, 1, 0.22, "CENTER", "OUT")
        K.tomeOut = K.tome:CreateAnimationGroup()
        AlphaAnim(K.tomeOut, 1, 0, 0.16)
        ScaleAnim(K.tomeOut, 1, 1, 0.86, 0.86, 0.16, "CENTER", "IN")
        if K.tomeOut.SetToFinalAlpha then K.tomeOut:SetToFinalAlpha(true) end
        K.cover = Sheet("cover", false)
        K.cover.shade:SetAlpha(0.35)
        K.coverOpen = K.cover:CreateAnimationGroup()
        ScaleAnim(K.coverOpen, 1, 1, 0.02, 1, 0.24, "LEFT", "IN", nil, 0.10)
        K.coverClose = K.cover:CreateAnimationGroup()
        ScaleAnim(K.coverClose, 0.02, 1, 1, 1, 0.20, "LEFT", "OUT")
        -- a page turning: it folds to the spine on one side, opens on the
        -- other, then fades into the new page
        for i, origin in ipairs({ "RIGHT", "LEFT" }) do
            local s = Sheet("page", i == 1)
            s.fold = s:CreateAnimationGroup()
            ScaleAnim(s.fold, 1, 1, 0.02, 1, 0.15, origin, "IN")
            s.open = s:CreateAnimationGroup()
            ScaleAnim(s.open, 0.02, 1, 1, 1, 0.15, origin, "OUT")
            s.fade = s:CreateAnimationGroup()
            AlphaAnim(s.fade, 1, 0, 0.10)
            if s.fade.SetToFinalAlpha then s.fade:SetToFinalAlpha(true) end
            K["sheet" .. i] = s
        end
    end)
    K.canAnimate = ok and true or false
end

function K.Motion()
    return K.canAnimate and ns.Get("bookMotion") and true or false
end

-- Stops whatever is moving and shows the book as it should be
function K.Settle()
    for _, ag in ipairs({ K.tomeIn, K.coverOpen, K.coverClose,
        K.sheet1 and K.sheet1.fold, K.sheet1 and K.sheet1.open, K.sheet1 and K.sheet1.fade,
        K.sheet2 and K.sheet2.fold, K.sheet2 and K.sheet2.open, K.sheet2 and K.sheet2.fade }) do
        if ag and ag:IsPlaying() then ag:Stop() end
    end
    if K.cover then K.cover:Hide() end
    if K.sheet1 then K.sheet1:Hide(); K.sheet1:SetAlpha(1) end
    if K.sheet2 then K.sheet2:Hide(); K.sheet2:SetAlpha(1) end
    K.tome:SetAlpha(1)
    if K.busy or K.noModels then
        K.busy, K.noModels = nil, nil
        K.Render()
    end
end

-- a book hidden mid-animation (the window closed) never hears its
-- animation finish: settle it so it is never left half turned
K.frame:HookScript("OnHide", function() if K.busy then K.Settle() end end)

local function OnDone(ag, fn)
    ag:SetScript("OnFinished", fn)
end

-- the sheets cover one page each
local function PlaceSheets()
    for i = 1, 2 do
        local s = K["sheet" .. i]
        if s then
            s:ClearAllPoints()
            s:SetAllPoints(K.single and K.pages[1] or K.pages[i])
            s.bg:SetTexture(B.Art(K.Style().tex))
            s.bg:SetTexCoord(i == 2 and 1 or 0, i == 2 and 0 or 1, 0, 1)
        end
    end
end

-- Opens: the book grows in and its cover swings open over the right page
function K.PlayOpen()
    B.Sound("IG_SPELLBOOK_OPEN")
    if not K.Motion() then return end
    local r, g, b = B.BookColor(ns.state.bookOpen)
    K.cover.bg:SetVertexColor(r * 0.9, g * 0.9, b * 0.9)
    K.cover:ClearAllPoints()
    if K.single then
        K.cover:SetAllPoints(K.tome)
    else
        K.cover:SetPoint("TOPLEFT", K.tome, "TOP", 0, 0)
        K.cover:SetPoint("BOTTOMRIGHT", K.tome, "BOTTOMRIGHT", 0, 0)
    end
    K.busy, K.noModels, K.busySince = true, true, GetTime()
    K.Render()
    K.cover:Show()
    OnDone(K.coverOpen, function()
        K.cover:Hide()
        K.busy, K.noModels = nil, nil
        K.Render()
    end)
    K.tomeIn:Play()
    K.coverOpen:Play()
end

-- Closes: the cover folds back over the pages, the book shrinks away,
-- then the shelf
function K.Close()
    local function Done()
        K.Settle()
        ns.state.bookView = "SHELF"
        UI.RefreshStoryBook()
    end
    B.Sound("IG_SPELLBOOK_CLOSE")
    if K.menu then K.menu:Hide() end
    if not K.Motion() or not K.frame:IsVisible() then return Done() end
    K.Settle()
    K.busy, K.noModels, K.busySince = true, true, GetTime()
    K.Render()
    local r, g, b = B.BookColor(ns.state.bookOpen)
    K.cover.bg:SetVertexColor(r * 0.9, g * 0.9, b * 0.9)
    K.cover:ClearAllPoints()
    if K.single then
        K.cover:SetAllPoints(K.tome)
    else
        K.cover:SetPoint("TOPLEFT", K.tome, "TOP", 0, 0)
        K.cover:SetPoint("BOTTOMRIGHT", K.tome, "BOTTOMRIGHT", 0, 0)
    end
    K.cover:Show()
    OnDone(K.coverClose, function() K.tomeOut:Play() end)
    OnDone(K.tomeOut, function()
        K.cover:Hide()
        K.busy, K.noModels = nil, nil
        Done()
    end)
    K.coverClose:Play()
end

-- Turns to the spread of page `n`; dir 1 forward, -1 back
function K.Show(n, dir)
    local target = K.SpreadOf(n)
    if target == K.at then return end
    K.Settle()
    dir = dir or (target > K.at and 1 or -1)
    B.Sound("IG_ABILITY_PAGE_TURN")
    if not K.Motion() then
        K.at = target
        K.Render()
        return
    end
    PlaceSheets()
    local first, second = K.sheet2, K.sheet1      -- forward: the right page folds, the left opens
    local firstSide, secondSide = 2, 1
    if dir < 0 then first, second, firstSide, secondSide = K.sheet1, K.sheet2, 1, 2 end
    if K.single then first, second = (dir > 0) and K.sheet2 or K.sheet1, nil end
    K.busy, K.busySince = true, GetTime()
    K.at = target
    -- the side that folds away shows its new page at once
    K.Render(K.single and { true } or { [firstSide] = true })
    first:SetAlpha(1)
    first:Show()
    OnDone(first.fold, function()
        first:Hide()
        if not second then
            K.busy = nil
            K.Render()
            return
        end
        second:SetAlpha(1)
        second:Show()
        OnDone(second.open, function()
            K.Render({ [secondSide] = true })
            OnDone(second.fade, function()
                second:Hide()
                second:SetAlpha(1)
                K.busy = nil
            end)
            second.fade:Play()
        end)
        second.open:Play()
    end)
    first.fold:Play()
end

function K.Turn(d)
    if not K.list then return end
    local step = K.single and 1 or 2
    local target = K.at + d * step
    if target < 1 or target > #K.list then return end
    K.Show(target, d)
end

function K.GoTo(n)
    if K.menu then K.menu:Hide() end
    K.Show(n)
end

function K.Wheel(delta)
    -- a turn still moving takes the wheel only after a moment
    if K.busy and GetTime() - (K.busySince or 0) < 0.6 then return end
    K.Turn(delta < 0 and 1 or -1)
end

-- =========================================================
-- Showing the book (every Story Book refresh while it is open)
-- =========================================================
local function Signature()
    local o = ns.state.bookOpen
    local parts = { K.Key(), math.floor(K.tome:GetWidth() or 0), math.floor(K.tome:GetHeight() or 0),
        ns.Get("bookPages"), tostring(ns.Get("storyCover")) }
    local stories
    if o.kind == "chronicle" then
        local c = ns.FindChronicle(o.id)
        stories = c and ns.ChronicleStories(c) or {}
        table.insert(parts, c and (c.title .. tostring(c.color) .. tostring(c.cover)) or "")
    else
        stories = { ns.FindStory(o.id) }
    end
    for _, st in ipairs(stories) do
        local info = ns.GetBookInfo(st)
        table.insert(parts, st.id .. ":" .. #(st.story or "") .. ":" .. tostring(info.name) .. tostring(info.party) .. tostring(info.date))
    end
    return table.concat(parts, "|")
end

function B.ShowBook()
    local f = K.frame
    local wasShown = f:IsShown()
    f:Show()
    B.Tile(K.desk, B.Art("wall"), f:GetWidth() or 500, f:GetHeight() or 400, 256, 256)
    local r, g, b = B.BookColor(ns.state.bookOpen)
    K.leather:SetVertexColor(r, g, b)
    local o = ns.state.bookOpen
    local name
    if o.kind == "chronicle" then
        local c = ns.FindChronicle(o.id)
        name = c and c.title or ""
    else
        local st = ns.FindStory(o.id)
        name = st and ns.StripColors(ns.GetBookInfo(st).name or "") or ""
    end
    K.title:SetText(GOLD .. name .. "|r")
    K.Layout()
    local sig = Signature()
    local keyChanged = K.openKey ~= K.Key()
    local changed = sig ~= K.sig or not K.list
    if changed then
        -- keep the reader on the same page through a re-layout
        local keepStory, keepFirst = nil, nil
        if not keyChanged and K.list and K.list[K.at] then
            keepStory = K.list[K.at].storyId
            keepFirst = K.list[K.at].titlePage
        end
        K.Settle()
        K.Paginate()
        K.sig = sig
        if keyChanged then
            K.at = K.SpreadOf(K.last[K.Key()] or 1)
        elseif keepStory and K.storyPage[keepStory] then
            K.at = K.SpreadOf(keepFirst and K.storyPage[keepStory] or math.min(K.at, #K.list))
        else
            K.at = K.SpreadOf(math.min(K.at, #K.list))
        end
    end
    K.openKey = K.Key()
    -- a story asked for by name (an import, a Story button): its first page
    local jumped = false
    if B.jumpTo and K.storyPage[B.jumpTo] then
        local to = K.SpreadOf(K.storyPage[B.jumpTo])
        jumped = to ~= K.at
        K.at = to
    end
    B.jumpTo = nil
    -- sizes can settle a frame later on the first show: check once more
    if C_Timer and C_Timer.After and not K.recheck then
        K.recheck = true
        C_Timer.After(0, function()
            K.recheck = nil
            if K.frame:IsVisible() and ns.state.bookView == "BOOK" and Signature() ~= K.sig then B.ShowBook() end
        end)
    end
    if K.animateOpen or not wasShown then
        K.animateOpen = nil
        K.Settle()
        K.Render()
        K.PlayOpen()
    elseif (changed or jumped) and not K.busy then
        K.Render()
    end
end

function B.HideBook()
    if K.frame:IsShown() then K.Settle() end
    K.frame:Hide()
    if K.menu then K.menu:Hide() end
end

-- From the shelf: open a story or a chronicle as a book
function B.OpenBook(open)
    ns.state.bookView = "BOOK"
    ns.state.bookOpen = open
    K.animateOpen = true
    UI.RefreshStoryBook()
end

-- =========================================================
-- The Book menu: the story on these pages, and the chronicle
-- =========================================================
do
    local menu = CreateFrame("Frame", "RPChroniclerBookMenu", UIParent, UI.BACKDROP)
    menu:SetFrameStrata("FULLSCREEN_DIALOG")
    menu:SetSize(210, 10)
    menu:EnableMouse(true)
    menu:Hide()
    UI.ApplyDarkGlass(menu, 0.05, 0.06, 0.08, 0.97, 0.82, 0.65, 0.30, 0.90)
    if type(UISpecialFrames) == "table" then table.insert(UISpecialFrames, "RPChroniclerBookMenu") end
    K.menu = menu
    local rows, heads = {}, {}
    local function Row(i)
        local b = rows[i]
        if b then return b end
        b = UI.CreateSleekButton(menu, 198, 20, "")
        b.label:SetJustifyH("LEFT")
        rows[i] = b
        return b
    end
    local function Head(i)
        local h = heads[i]
        if h then return h end
        h = menu:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        h:SetJustifyH("LEFT")
        h:SetWidth(194)
        h:SetWordWrap(false)
        heads[i] = h
        return h
    end
    -- The story the reader is on (the left page's, else the right page's)
    function K.CurrentStory()
        local list = K.list or {}
        for _, n in ipairs({ K.at, K.at + 1 }) do
            local pg = list[n]
            if pg and pg.storyId then return ns.FindStory(pg.storyId) end
            if K.single then break end
        end
        return nil
    end
    function K.OpenMenu()
        for _, b in ipairs(rows) do b:Hide() end
        for _, h in ipairs(heads) do h:Hide() end
        local y, nr, nh = -6, 0, 0
        local function H(text)
            nh = nh + 1
            local h = Head(nh)
            h:ClearAllPoints()
            h:SetPoint("TOPLEFT", 8, y - 2)
            h:SetText(text)
            h:Show()
            y = y - 18
        end
        local function R(text, fn, style, disabled)
            nr = nr + 1
            local b = Row(nr)
            b.accentStyle = style
            b:SetText(text)
            b:SetScript("OnClick", function(self)
                menu:Hide()
                fn(self)
            end)
            if disabled then b:Disable() else b:Enable() end
            b:ClearAllPoints()
            b:SetPoint("TOPLEFT", 6, y)
            b:Show()
            y = y - 22
        end
        local st = K.CurrentStory()
        local open = ns.state.bookOpen
        if st then
            H("|cff8f9ba8This story:|r |cfff5e6c8" .. B.Cut(ns.StripColors(ns.GetBookInfo(st).name or ""), 24) .. "|r")
            if B.CHRONICLES then R("Add to a chronicle...", function() S.OpenChronicleMenu(K.menuBtn, st.id) end, "gold") end
            R("Share as plain text", function() B.Share(st) end)
            R("Read outside the game", function() UI.ShowViewerPath() end)
            R("Copy for viewer", function() B.CopyForViewer(st) end)
            if not ns.ScreenshotFormatOK() then R("Use JPG screenshots", function() B.UseJpg() end, "tool") end
            R("Edit details", function() UI.OpenStoryDetails(st) end)
            R("Re-import", function() B.ReImport(st) end)
            R("Open the run", function() B.OpenRun(st) end, nil, not ns.StoryRun(st))
            R("Delete story...", function() B.DeleteStory(st) end, "danger")
        end
        if B.CHRONICLES and open and open.kind == "chronicle" then
            local c = ns.FindChronicle(open.id)
            if c then
                if st then y = y - 4 end
                H("|cff8f9ba8This chronicle:|r |cfff5e6c8" .. B.Cut(c.title, 22) .. "|r")
                R("Rename", function()
                    UI.AskLine({
                        title = GOLD .. "Rename chronicle|r",
                        sub = "|cffb0bac5Now: " .. c.title .. " (up to " .. ns.CHRONICLE_TITLE_MAX .. " letters).|r",
                        placeholder = c.title,
                        okText = "Rename",
                        onAccept = function(text) ns.RenameChronicle(c.id, text) end,
                    })
                end)
                R("Change color", function() ns.CycleChronicleColor(c.id) end)
                local list = ns.GetChronicles()
                R("Move left on the shelf", function() ns.MoveChronicle(c.id, -1) end, nil, list[1] == c)
                R("Move right on the shelf", function() ns.MoveChronicle(c.id, 1) end, nil, list[#list] == c)
                R("Delete chronicle...", function()
                    UI.ShowPrompt("|cffffd100Delete the chronicle \"" .. c.title .. "\"?|r\n|cffd7c4a3Its stories stay on the shelf as loose stories.|r",
                        "|cffff6b6bDelete chronicle|r", function()
                            ns.DeleteChronicle(c.id)
                            ns.state.bookView = "SHELF"
                            UI.SetStatus("Chronicle deleted. Its stories are on the shelf as loose stories.", "good")
                            UI.RefreshStoryBook()
                        end,
                        "Keep it", nil)
                end, "danger")
            end
        end
        menu:SetHeight(-y + 6)
        menu:ClearAllPoints()
        menu:SetPoint("TOPRIGHT", K.menuBtn, "BOTTOMRIGHT", 0, -2)
        menu:Show()
    end
    K.menuBtn:SetScript("OnClick", function()
        if menu:IsShown() then menu:Hide() else K.OpenMenu() end
    end)
    B.root:HookScript("OnHide", function() menu:Hide() end)
end

UI.AddReflow(function()
    if K.frame:IsVisible() and ns.state.bookView == "BOOK" then B.ShowBook() end
end)
