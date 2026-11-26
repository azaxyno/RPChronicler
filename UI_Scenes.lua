local ADDON_NAME, ns = ...
local UI = ns.UI

-- =========================================================
-- Story scenes (0.6.4): the party of a story, standing together on a
-- misty backdrop at the top of the story's cover, and facing each boss
-- in that boss's scene.
--
-- Each member is shown exactly as they are, or as a shadow (Mor's rule):
--  * Real: a live 3D model, only while that player is near you (the game
--    can only draw another player's real look while they are visible).
--    You are always Real on your own stories, in the gear from the run.
--  * Shadow: a black cut-out of their race and sex (Media\Shadows), with
--    a soft glow in their class color. Never a stand-in with a wrong
--    face, hair, body or gender.
-- Every figure is drawn at the same scale, so a gnome stands smaller than
-- a tauren, and Real models use the camera the shadows were made with.
--
-- Size: the row fits up to five figures in the reader's width. Ctrl +
-- mouse wheel zooms on the cover (plain wheel still scrolls the story),
-- Enlarge opens the scene in its own big window where the wheel zooms
-- and dragging pans. Nothing here is protected, so it is safe in combat,
-- and models are cleared when the scene hides.
-- =========================================================
local MEDIA = "Interface\\AddOns\\RPChronicler\\Media\\"
local SHADOW_FILE = {
    [1] = "human", [2] = "orc", [3] = "dwarf", [4] = "nightelf", [5] = "undead", [6] = "tauren",
    [7] = "gnome", [8] = "troll", [9] = "goblin", [10] = "bloodelf", [11] = "draenei", [22] = "worgen",
    [95] = "skyborne_highorder", [96] = "skyborne_windshaper",
}
-- The cut-outs: the figure box is 196x256 inside a 256x256 texture
local TEX_L, TEX_R = 30 / 256, 226 / 256
local FIG_ASPECT = 196 / 256
-- The capture box around that crop (Real models use the same camera)
local CAP_W, CAP_H = 716 / 596, 896 / 780     -- capture size / crop size
local CAP_X = 60 / 596                        -- crop left inside the capture
local MAX_MEMBERS = 5
-- 0.6.7 (Mor's test): where each shadow's head is, as a share of the
-- texture's height (its feet stand at about 0.955). A live figure in the
-- party scene is fitted to its own race's shadow, so you stand exactly as
-- tall as a shadow of your race would (measured from Media/Shadows).
local SHADOW_TOP = {
    f_bloodelf = 0.305, f_draenei = 0.156, f_dwarf = 0.441, f_gnome = 0.531, f_goblin = 0.484,
    f_human = 0.316, f_nightelf = 0.191, f_orc = 0.242, f_skyborne_highorder = 0.312,
    f_skyborne_windshaper = 0.312, f_tauren = 0.039, f_troll = 0.156, f_undead = 0.332, f_worgen = 0.133,
    m_bloodelf = 0.250, m_draenei = 0.078, m_dwarf = 0.430, m_gnome = 0.562, m_goblin = 0.488,
    m_human = 0.266, m_nightelf = 0.145, m_orc = 0.223, m_skyborne_highorder = 0.234,
    m_skyborne_windshaper = 0.230, m_tauren = 0.0, m_troll = 0.176, m_undead = 0.355, m_worgen = 0.129,
    unknown = 0.152,
}
local SHADOW_FEET = 0.955
local DRESS_FILL = 0.86     -- how much of a model box a full-body model fills

-- Class colors, as in the story palette (Priest gray, never white)
local CLASS_RGB = {
    WARRIOR = { 0.78, 0.61, 0.43 }, PALADIN = { 0.96, 0.55, 0.73 }, HUNTER = { 0.67, 0.83, 0.45 },
    ROGUE = { 1.00, 0.96, 0.41 }, PRIEST = { 0.75, 0.75, 0.75 }, SHAMAN = { 0.00, 0.44, 0.87 },
    MAGE = { 0.41, 0.80, 0.94 }, WARLOCK = { 0.58, 0.51, 0.79 }, DRUID = { 1.00, 0.49, 0.04 },
    DEATHKNIGHT = { 0.77, 0.12, 0.23 }, MONK = { 0.00, 1.00, 0.59 }, DEMONHUNTER = { 0.64, 0.19, 0.79 },
    EVOKER = { 0.20, 0.58, 0.50 },
}
local ROLE_ORDER = { TANK = 1, HEALER = 2, DAMAGER = 3 }

local function ClassRGB(p)
    return CLASS_RGB[tostring(p and p.classFile or ""):upper()] or { 0.85, 0.80, 0.70 }
end

local function Hex(rgb)
    return string.format("%02x%02x%02x", math.floor(rgb[1] * 255), math.floor(rgb[2] * 255), math.floor(rgb[3] * 255))
end

-- 0.6.4: an older run that never recorded someone's race and sex gets a
-- blurred, raceless figure, never another race's outline (Mor's rule)
function ns.ShadowTexture(race, sex)
    local file = SHADOW_FILE[tonumber(race) or 0]
    sex = tonumber(sex)
    if not file or (sex ~= 2 and sex ~= 3) then return MEDIA .. "Shadows\\unknown.png", true end
    return MEDIA .. "Shadows\\" .. ((sex == 3) and "f_" or "m_") .. file .. ".png"
end

-- The unit for a member who is near you right now (visible), or nil
local function NearUnit(name)
    if type(name) ~= "string" or name == "" then return nil end
    local low = name:lower()
    local function Match(u)
        if not UnitExists(u) or not UnitIsPlayer(u) then return false end
        local full = ns.GetUnitFullName(u)
        if not full or full:lower() ~= low then return false end
        if not UnitIsVisible then return true end
        local ok, vis = pcall(UnitIsVisible, u)
        return ok and vis == true
    end
    local u = ns.ForEachKnownUnit and ns.ForEachKnownUnit(Match)
    if u then return u end
    for i = 1, 40 do
        local np = "nameplate" .. i
        if UnitExists(np) and Match(np) then return np end
    end
    return nil
end

-- The story's members for the scene: you in the middle when it is your
-- story, then tank, healer and damage dealers around you
local function SceneMembers(st)
    local me = st.char and st.char == ns.PlayerName()
    -- 0.6.4: one figure per person, also for stories recorded before the
    -- roster fix ("Morai" and "Morai Galeclaw")
    local list = ns.MergedRoster(st.participants)
    local total = #list
    local you
    for i, p in ipairs(list) do
        if st.char and p.name == st.char then you = table.remove(list, i) break end
    end
    table.sort(list, function(a, b)
        local ra, rb = ROLE_ORDER[a.role or ""] or 4, ROLE_ORDER[b.role or ""] or 4
        if ra ~= rb then return ra < rb end
        return (a.name or "") < (b.name or "")
    end)
    while #list > MAX_MEMBERS - (you and 1 or 0) do table.remove(list) end
    local out = {}
    for _, p in ipairs(list) do table.insert(out, { p = p }) end
    if you then table.insert(out, math.floor(#out / 2) + 1, { p = you, isYou = me }) end
    local more = math.max(0, total - #out)
    return out, more
end

-- =========================================================
-- One figure slot: glow, shadow or live model, and a name
-- =========================================================
local function NewSlot(parent)
    local s = CreateFrame("Frame", nil, parent)
    s.glow = s:CreateTexture(nil, "BACKGROUND", nil, 2)
    s.glow:SetTexture(MEDIA .. "Scene\\glow.png")
    s.glow:SetBlendMode("BLEND")
    s.foot = s:CreateTexture(nil, "BACKGROUND", nil, 3)
    s.foot:SetTexture(MEDIA .. "Scene\\glow.png")
    s.foot:SetVertexColor(0, 0, 0, 0.75)
    s.shadow = s:CreateTexture(nil, "ARTWORK")
    s.shadow:SetTexCoord(TEX_L, TEX_R, 0, 1)
    s.icon = s:CreateTexture(nil, "ARTWORK", nil, 1)
    s.name = s:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    s.name:SetWordWrap(false)
    s.name:SetShadowOffset(1, -1)
    s.name:SetShadowColor(0, 0, 0, 1)
    s:EnableMouse(true)
    s:SetScript("OnEnter", function(self)
        if self.tipTitle then UI.Tooltip(self, self.tipTitle, self.tipText) end
    end)
    s:SetScript("OnLeave", function() UI.HideTooltip() end)
    -- 0.6.4: click a figure for its card (level, looks, what they wore and won)
    s:SetScript("OnMouseUp", function(self, button)
        if button == "LeftButton" and self.onClick then UI.HideTooltip(); self.onClick(self) end
    end)
    return s
end

-- A live model box for a slot, made the first time it is needed. A
-- ModelScene with the shadows' camera keeps every race at its true size;
-- it is larger than the slot (the capture box around the cut-out).
local function SlotModel(s)
    if s.model ~= nil then return s.model or nil end
    s.model = false
    -- 0.6.7: the party scene uses a dressing-room model, which frames the
    -- whole figure in its box; FitModel sizes that box to the shadow
    if s.useDress then
        local ok, m = pcall(CreateFrame, "DressUpModel", nil, s)
        if not ok or not m or not m.SetUnit then ok, m = pcall(CreateFrame, "PlayerModel", nil, s) end
        if not ok or not m or not m.SetUnit then return nil end
        m.dress = true
        m:EnableMouse(false)
        s.model = m
        return m
    end
    local ok, m = pcall(CreateFrame, "ModelScene", nil, s)
    if not ok or not m or not m.CreateActor then return nil end
    pcall(m.SetCameraNearClip, m, 0.1)
    pcall(m.SetCameraFarClip, m, 100)
    pcall(m.SetCameraFieldOfView, m, 0.8)
    pcall(m.SetCameraPosition, m, 5.5, 0, 1.1)
    pcall(m.SetCameraOrientationByYawPitchRoll, m, math.pi, 0, 0)
    local okA, actor = pcall(m.CreateActor, m)
    if not okA or not actor then return nil end
    m.actor = actor
    m:EnableMouse(false)
    s.model = m
    return m
end

local function ClearSlotModel(s)
    if s.model and s.model.dress then pcall(s.model.ClearModel, s.model) end
    if s.model and s.model.actor then pcall(s.model.actor.ClearModel, s.model.actor) end
    if s.model then s.model:Hide() end
end

-- Draws a live model of unit; dressed in gear (the run's) when given.
-- False when this client can't.
local function ShowReal(s, unit, gear)
    local m = SlotModel(s)
    if not m then return false end
    if m.dress then
        if not pcall(m.SetUnit, m, unit) then return false end
        if gear and m.Undress and m.TryOn then
            pcall(m.Undress, m)
            for _, g in ipairs(gear) do
                if type(g) == "table" and g.link then pcall(m.TryOn, m, g.link) end
            end
        end
        if m.SetPortraitZoom then pcall(m.SetPortraitZoom, m, 0) end
        if m.SetCamDistanceScale then pcall(m.SetCamDistanceScale, m, 1) end
        if m.SetFacing then pcall(m.SetFacing, m, 0) end
        m:Show()
        return true
    end
    local a = m.actor
    local ok = pcall(a.SetModelByUnit, a, unit, false, true, false, true)
    if not ok then return false end
    if gear and a.Undress then
        pcall(a.Undress, a)
        for _, g in ipairs(gear) do
            if type(g) == "table" and g.link then pcall(a.TryOn, a, g.link) end
        end
    end
    pcall(a.SetYaw, a, 0)
    m:Show()
    if UIFrameFadeIn then pcall(UIFrameFadeIn, m, 0.4, 0, 1) end
    return true
end

-- Places the model box over the slot's figure box (w x h)
local function FitModel(s, w, h)
    if not s.model then return end
    if s.model.dress then
        -- the box around where this race's shadow would stand
        local top, feet = h * (s.fitTop or 0.2), h * SHADOW_FEET
        local boxH = (feet - top) / DRESS_FILL
        s.model:ClearAllPoints()
        s.model:SetSize(math.max(w, boxH * 0.8), boxH)
        s.model:SetPoint("CENTER", s, "TOPLEFT", w / 2, -(top + feet) / 2)
        return
    end
    local mw, mh = w * CAP_W, h * CAP_H
    s.model:ClearAllPoints()
    s.model:SetSize(mw, mh)
    s.model:SetPoint("TOPLEFT", s, "TOPLEFT", -w * CAP_X, 0)
end

-- =========================================================
-- The boss box: a model of the boss when the game can draw it, else its
-- icon, always with a crimson glow
-- =========================================================
-- 0.6.4: puts a story's boss into a PlayerModel: its display ID (recorded
-- in the fight, remembered from a later meeting, or from the Encounter
-- Journal), else its creature ID. True when a model was set.
local function SetBossModel(m, st, name)
    if not m then return false end
    pcall(m.ClearModel, m)
    local display, npc = ns.BossLooks(st, name)
    local shown = false
    if display and m.SetDisplayInfo then shown = pcall(m.SetDisplayInfo, m, display) end
    if not shown and npc and m.SetCreature then shown = pcall(m.SetCreature, m, npc) end
    if shown then pcall(m.SetFacing, m, -0.5) end
    return shown
end
UI.SetBossModel = SetBossModel
local BOSS_UNKNOWN = "Its look isn't known yet: target it or point at it the next time you meet it, and it appears here."

local function ShowBoss(slot, name, st)
    slot.icon:Hide()
    if slot.bossModel == nil then
        local ok, m = pcall(CreateFrame, "PlayerModel", nil, slot)
        slot.bossModel = (ok and m) or false
        if slot.bossModel then slot.bossModel:SetAllPoints(slot) end
    end
    local m = slot.bossModel
    local shown = m and SetBossModel(m, st, name) or false
    if m then if shown then m:Show() else m:Hide() end end
    if not shown then
        slot.icon:SetTexture("Interface\\TargetingFrame\\UI-TargetingFrame-Skull")
        slot.icon:ClearAllPoints()
        slot.icon:SetSize(64, 64)
        slot.icon:SetPoint("CENTER", slot, "CENTER", 0, 10)
        slot.icon:Show()
    end
    slot.tipTitle = "|cffdc143c" .. name .. "|r"
    slot.tipText = shown and "Boss" or ("Boss. " .. BOSS_UNKNOWN)
end

-- =========================================================
-- The scene object
-- =========================================================
local Scene = {}
Scene.__index = Scene

-- parent: the frame it lives in. opts.wheelZoom: plain wheel zooms
-- (the big window); otherwise Ctrl + wheel zooms and the plain wheel is
-- handed to opts.onWheel (the story's scroll).
function UI.CreateStoryScene(parent, opts)
    local self = setmetatable({ opts = opts or {}, zoom = 1, pan = 0, slots = {}, view = 1 }, Scene)
    local f = CreateFrame("Frame", nil, parent, UI.BACKDROP)
    self.frame = f
    UI.ApplyDarkGlass(f, 0.10, 0.09, 0.08, 1.0, 0.70, 0.55, 0.25, 0.70)
    if f.SetClipsChildren then pcall(f.SetClipsChildren, f, true) end
    self.mist = f:CreateTexture(nil, "BACKGROUND", nil, -6)
    self.mist:SetPoint("TOPLEFT", 1, -1)
    self.mist:SetPoint("BOTTOMRIGHT", -1, 1)
    self.mist:SetTexture(MEDIA .. "Scene\\mist.png")
    self.art = f:CreateTexture(nil, "BACKGROUND", nil, -5)
    self.art:SetAllPoints(self.mist)
    self.art:Hide()
    self.veil = f:CreateTexture(nil, "BACKGROUND", nil, -4)
    self.veil:SetAllPoints(self.mist)
    self.veil:SetTexture(MEDIA .. "Scene\\mist.png")
    self.veil:SetAlpha(0.45)
    self.veil:Hide()
    self.stage = CreateFrame("Frame", nil, f)
    self.stage:SetAllPoints(f)
    -- 0.6.4: the words and buttons sit on their own layer above the
    -- figures (a big boss used to cover the buttons and swallow clicks)
    self.top = CreateFrame("Frame", nil, f)
    self.top:SetAllPoints(f)
    local top = self.top
    top:SetFrameLevel((f:GetFrameLevel() or 1) + 30)

    self.label = top:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    self.label:SetPoint("TOPLEFT", 8, -6)
    self.label:SetShadowOffset(1, -1)
    self.label:SetShadowColor(0, 0, 0, 1)
    self.more = top:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    self.more:SetPoint("TOPLEFT", self.label, "BOTTOMLEFT", 0, -2)
    -- the names in class colors along the ground, when the figures stand
    -- too close for a name under each one
    self.legend = top:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    self.legend:SetPoint("BOTTOMLEFT", 8, 4)
    self.legend:SetPoint("BOTTOMRIGHT", -8, 4)
    self.legend:SetJustifyH("CENTER")
    self.legend:SetShadowOffset(1, -1)
    self.legend:SetShadowColor(0, 0, 0, 1)

    -- view controls: previous / next scene, zoom, enlarge
    self.prev = UI.CreateSleekButton(top, 22, 18, "<", "tool")
    self.next = UI.CreateSleekButton(top, 22, 18, ">", "tool")
    self.zoomIn = UI.CreateSleekButton(top, 22, 18, "+", "tool")
    self.zoomOut = UI.CreateSleekButton(top, 22, 18, "-", "tool")
    self.big = UI.CreateSleekButton(top, 64, 18, opts and opts.bigText or "Enlarge", "tool")
    self.big:SetPoint("TOPRIGHT", -6, -5)
    self.zoomIn:SetPoint("RIGHT", self.big, "LEFT", -4, 0)
    self.zoomOut:SetPoint("RIGHT", self.zoomIn, "LEFT", -2, 0)
    self.next:SetPoint("RIGHT", self.zoomOut, "LEFT", -8, 0)
    self.prev:SetPoint("RIGHT", self.next, "LEFT", -2, 0)
    self.prev.tipTitle, self.prev.tipText = "|cffffd100Previous scene|r", "The party, then each boss of the story."
    self.next.tipTitle, self.next.tipText = "|cffffd100Next scene|r", "The party, then each boss of the story."
    self.zoomIn.tipTitle, self.zoomIn.tipText = "|cffffd100Zoom in|r", (opts and opts.wheelZoom) and "Or the mouse wheel. Drag to look around." or "Or Ctrl + mouse wheel over the scene. Drag to look around."
    self.zoomOut.tipTitle, self.zoomOut.tipText = "|cffffd100Zoom out|r", self.zoomIn.tipText
    self.big.tipTitle = "|cffffd100" .. (opts and opts.bigText or "Enlarge") .. "|r"
    self.big.tipText = (opts and opts.bigTip) or "Shows this scene in a big window."
    self.prev:SetScript("OnClick", function() self:Step(-1) end)
    self.next:SetScript("OnClick", function() self:Step(1) end)
    self.zoomIn:SetScript("OnClick", function() self:Zoom(0.25) end)
    self.zoomOut:SetScript("OnClick", function() self:Zoom(-0.25) end)
    self.big:SetScript("OnClick", function()
        if self.opts.onBig then self.opts.onBig(self) end
    end)

    f:EnableMouse(true)
    f:EnableMouseWheel(true)
    f:SetScript("OnMouseWheel", function(_, delta)
        if self.opts.wheelZoom or (IsControlKeyDown and IsControlKeyDown()) then
            self:Zoom(delta * 0.15)
        elseif self.opts.onWheel then
            self.opts.onWheel(delta)
        end
    end)
    -- drag to look around while zoomed in
    f:SetScript("OnMouseDown", function(_, button)
        if button ~= "LeftButton" or self.zoom <= 1 then return end
        local x = GetCursorPosition()
        self.dragFrom, self.dragPan = x / (f:GetEffectiveScale() or 1), self.pan
    end)
    f:SetScript("OnMouseUp", function() self.dragFrom = nil end)
    f:SetScript("OnUpdate", function()
        if not self.dragFrom then return end
        if IsMouseButtonDown and not IsMouseButtonDown("LeftButton") then self.dragFrom = nil return end
        local x = GetCursorPosition() / (f:GetEffectiveScale() or 1)
        self.pan = self.dragPan + (x - self.dragFrom)
        self:Layout()
    end)
    f:SetScript("OnHide", function() self:Release() end)
    f:SetScript("OnSizeChanged", function() self:Layout() end)
    f:SetScript("OnShow", function() if self.story then self:Refresh() end end)
    return self
end

-- Scenes of a story: 1 = the party, then one per boss killed
-- Scenes of a story: the party. 0.6.4 (Mor): each boss has its own
-- panel at its chapter in the story text (UI.CreateBossPanel), so the
-- cover shows the party alone.
function Scene:Views()
    return { { kind = "party" } }
end

function Scene:SetStory(st, view)
    self.story = st
    self.view = view or 1
    self.zoom, self.pan = 1, 0
    self:Refresh()
end

function Scene:Step(d)
    local n = #self:Views()
    self.view = ((self.view - 1 + d) % n) + 1
    self.pan = 0
    self:Refresh()
    if self.opts.onView then self.opts.onView(self.view) end
end

function Scene:Zoom(d)
    self.zoom = math.max(1, math.min(2.5, self.zoom + d))
    if self.zoom == 1 then self.pan = 0 end
    self:Layout()
end

function Scene:Release()
    for _, s in ipairs(self.slots) do
        ClearSlotModel(s)
        if s.bossModel then pcall(s.bossModel.ClearModel, s.bossModel) end
    end
    self.dragFrom = nil
end

local function Slot(self, i)
    local s = self.slots[i]
    if not s then
        s = NewSlot(self.stage)
        s.useDress = true
        self.slots[i] = s
    end
    return s
end

-- Picks the backdrop: the dungeon's journal art under a veil of mist,
-- else the mist alone
function Scene:Backdrop()
    local st = self.story
    local art
    if st and st.ejInstance and EJ_GetInstanceInfo then
        local ok, _, _, bg = pcall(EJ_GetInstanceInfo, st.ejInstance)
        if ok and bg and bg ~= 0 and bg ~= "" then art = bg end
    end
    if art and pcall(self.art.SetTexture, self.art, art) then
        self.art:SetTexCoord(0, 0.68, 0, 0.75)
        self.art:Show()
        self.veil:Show()
    else
        self.art:Hide()
        self.veil:Hide()
    end
end

-- Fills the slots for the current view (who is Real, who is a shadow)
function Scene:Refresh()
    local st = self.story
    if not st then return end
    self:Release()
    local views = self:Views()
    if self.view > #views then self.view = 1 end
    local v = views[self.view]
    self:Backdrop()
    local members, more = SceneMembers(st)
    self.members = members
    for i, m in ipairs(members) do
        local s = Slot(self, i)
        local p = m.p
        local rgb = ClassRGB(p)
        s.rgb = rgb
        s.glow:SetVertexColor(rgb[1], rgb[2], rgb[3], 0.85)
        s.name:SetText("|cff" .. Hex(rgb) .. tostring(p.name) .. "|r")
        local unit = m.isYou and "player" or NearUnit(p.name)
        local key = tostring((ns.ShadowTexture(p.race, p.sex))):match("([%w_]+)%.png$")
        s.fitTop = SHADOW_TOP[key or ""] or SHADOW_TOP.unknown
        local real = unit and ShowReal(s, unit, (m.isYou and st.gear) or (not m.isYou and p.gear) or nil)
        if real then
            s.shadow:Hide()
        else
            ClearSlotModel(s)
            local tex, unknown = ns.ShadowTexture(p.race, p.sex)
            s.shadow:SetTexture(tex)
            s.unknown = unknown
            s.shadow:SetVertexColor(0.02, 0.02, 0.03, 1)
            s.shadow:Show()
        end
        s.icon:Hide()
        if s.bossModel then s.bossModel:Hide() end
        local role = ({ TANK = "Tank", HEALER = "Healer", DAMAGER = "DPS" })[p.role or ""]
        s.onClick = function(slot) UI.OpenFigure(st, p, m.isYou) end
        s.tipTitle = "|cff" .. Hex(rgb) .. tostring(p.name) .. "|r"
        s.tipText = string.format("%s%s%s\n%s",
            p.level and p.level ~= "" and ("Level " .. p.level .. " ") or "", p.class or "",
            role and (" (" .. role .. ")") or "",
            real and (m.isYou and "You, in the gear you wore on this run." or "Shown as they are: they are near you now.")
                or (s.unknown and "A shadow. This older run did not record their race, so it fills in when you next see them (in your group, as a target or under the mouse)."
                or "A shadow: the game can only show another player as they are while they are near you.")) ..
            "\n|cff8f9ba8Click to see them up close, with their items.|r"
        s:Show()
    end
    -- the boss of a boss scene
    self.bossSlot = nil
    if v.kind == "boss" then
        local s = Slot(self, #members + 1)
        s.shadow:Hide()
        s.name:SetText("|cffdc143c" .. v.boss .. "|r")
        s.glow:SetVertexColor(0.86, 0.08, 0.24, 0.9)
        ClearSlotModel(s)
        ShowBoss(s, v.boss, st)
        s.tipText = s.tipText .. "\n|cff8f9ba8Click for what it dropped.|r"
        s.onClick = function(slot) UI.OpenFigure(st, { name = v.boss }, false, true) end
        s:Show()
        self.bossSlot = s
    end
    for i = #members + (v.kind == "boss" and 2 or 1), #self.slots do self.slots[i]:Hide() end
    local names = {}
    for _, m in ipairs(members) do
        table.insert(names, "|cff" .. Hex(ClassRGB(m.p)) .. tostring(m.p.name) .. "|r")
    end
    self.legendText = table.concat(names, "  ")
    self.label:SetText(v.kind == "boss" and ("|cffffd100The party|r |cffd7c4a3faces|r |cffdc143c" .. v.boss .. "|r")
        or "|cffffd100The party|r")
    self.more:SetText(more > 0 and ("|cffd7c4a3and " .. more .. " more|r") or "")
    local multi = #views > 1
    if multi then self.prev:Show(); self.next:Show() else self.prev:Hide(); self.next:Hide() end
    self:Layout()
end

-- Positions the figures for the frame's size, zoom and pan
function Scene:Layout()
    local f = self.frame
    local W, H = f:GetWidth() or 0, f:GetHeight() or 0
    if W < 40 or H < 40 or not self.members then return end
    local n = #self.members
    local bossW = self.bossSlot and math.floor(W * 0.36) or 0
    local partyW = W - bossW - 16
    -- figure height: a bit under the scene's height (mist above the
    -- tallest), shrunk until the row fits
    local ground = 20
    local figH = (H - ground - 8) * 0.84
    local function RowWidth(h) local w = h * FIG_ASPECT return w + (n - 1) * w * 0.58 end
    if n > 0 and RowWidth(figH) > partyW then figH = figH * partyW / RowWidth(figH) end
    figH = figH * self.zoom
    local figW = figH * FIG_ASPECT
    local step = figW * 0.58
    local rowW = n > 0 and (figW + (n - 1) * step) or 0
    -- panning stays inside the zoomed row
    local spare = math.max(0, rowW - partyW)
    self.pan = math.max(-spare / 2 - bossW, math.min(spare / 2, self.pan))
    local left = 8 + (partyW - rowW) / 2 + self.pan
    local center = (n + 1) / 2
    -- a name under each figure only when there is room for it
    local nameEach = step >= 118
    self.legend:SetText(nameEach and "" or (self.legendText or ""))
    self.legend:ClearAllPoints()
    self.legend:SetPoint("BOTTOMLEFT", 8, 4)
    self.legend:SetPoint("BOTTOMRIGHT", -(8 + bossW), 4)
    for i, m in ipairs(self.members) do
        local s = self.slots[i]
        local d = math.abs(i - center)
        local scale = 1 - d * 0.06
        local h, w = figH * scale, figW * scale
        local x = left + (i - 1) * step + (figW - w) / 2
        local y = ground + d * figH * 0.05
        s:ClearAllPoints()
        s:SetSize(w, h)
        s:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", x, y)
        s:SetFrameLevel((f:GetFrameLevel() or 1) + 10 - math.floor(d * 2))
        s.shadow:SetAllPoints(s)
        s.glow:ClearAllPoints()
        s.glow:SetSize(w * 1.5, h * 1.1)
        s.glow:SetPoint("CENTER", s, "CENTER", 0, -h * 0.05)
        s.foot:ClearAllPoints()
        s.foot:SetSize(w * 0.9, h * 0.12)
        s.foot:SetPoint("CENTER", s, "BOTTOM", 0, h * 0.04)
        FitModel(s, w, h)
        s.name:ClearAllPoints()
        s.name:SetPoint("TOP", s, "BOTTOM", 0, -2)
        s.name:SetWidth(math.max(40, step))
        if nameEach then s.name:Show() else s.name:Hide() end
        -- far outside the stage while zoomed: hidden (models don't clip)
        local visible = (x + w > 0) and (x < W)
        if visible then s:Show() else s:Hide() end
    end
    if self.bossSlot then
        local s = self.bossSlot
        local bh = math.min(H - ground - 10, bossW * 1.3) * math.min(self.zoom, 1.6)
        s:ClearAllPoints()
        s:SetSize(bossW, bh)
        s:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -8 + self.pan, ground)
        s:SetFrameLevel((f:GetFrameLevel() or 1) + 12)
        s.glow:ClearAllPoints()
        s.glow:SetSize(bossW * 1.4, bh * 1.1)
        s.glow:SetPoint("CENTER", s, "CENTER", 0, 0)
        s.foot:ClearAllPoints()
        s.foot:SetSize(bossW * 0.9, bh * 0.1)
        s.foot:SetPoint("CENTER", s, "BOTTOM", 0, bh * 0.04)
        s.name:ClearAllPoints()
        s.name:SetPoint("TOP", s, "BOTTOM", 0, -2)
        s.name:SetWidth(bossW)
        s.name:Show()
    end
    -- words and buttons above every figure and model
    local fl = f:GetFrameLevel() or 1
    self.top:SetFrameLevel(fl + 30)
    for _, b in ipairs({ self.prev, self.next, self.zoomIn, self.zoomOut, self.big }) do b:SetFrameLevel(fl + 31) end
end

-- =========================================================
-- 0.6.4 (Mor): click a figure and its own small window opens: the
-- figure enlarged (you or someone near you in 3D, drag to turn them;
-- everyone else as their shadow), who they were on this run, and their
-- items. Your own gear is known; other players' gear never is
-- (with Record party gear, inspected once per run), and what they won.
-- A boss shows its model and what it dropped.
-- =========================================================
do
    local f, title, info, body, stage, fig, glow, bossModel, skull
    local MAX_ITEMS = 12
    local FIG_H, TEXT_W = 232, 330 - 28
    -- 0.6.4 (Mor): zoom with the wheel or the + and - buttons. It opens
    -- zoomed in a little, so the figure fills the stage.
    local ZOOM_START, ZOOM_MIN, ZOOM_MAX = 1.35, 0.8, 3.0
    local function ApplyZoom()
        local z = stage.zoom or ZOOM_START
        if fig.model and fig.model:IsShown() then
            -- the camera moves in and rises toward the face
            pcall(fig.model.SetCameraPosition, fig.model, 5.5 / z, 0, 1.1 + (z - 1) * 0.22)
        end
        if fig.shadow:IsShown() then
            -- the cut-out grows, its head kept near the top of the stage
            fig:SetSize(FIG_H * FIG_ASPECT * z, FIG_H * z)
            fig:ClearAllPoints()
            fig:SetPoint("BOTTOM", stage, "BOTTOM", 0, 240 - FIG_H * z)
        end
        if bossModel and bossModel:IsShown() and bossModel.SetCamDistanceScale then
            pcall(bossModel.SetCamDistanceScale, bossModel, 1 / z)
        end
    end
    local function Zoom(step)
        stage.zoom = math.max(ZOOM_MIN, math.min(ZOOM_MAX, (stage.zoom or ZOOM_START) + step))
        ApplyZoom()
    end
    local function ItemLine(it, extra)
        local hex = ns.QUALITY_HEX[tonumber(it.q) or 1] or "ffffff"
        local icon = it.icon and ("|T" .. tostring(it.icon) .. ":16:16:0:0|t ") or ""
        return icon .. "|cff" .. hex .. tostring(it.name) .. "|r" .. (extra and extra ~= "" and (" |cff8f9ba8" .. extra .. "|r") or "")
    end
    local function List(lines, items, extraOf)
        for i, it in ipairs(items) do
            if i > MAX_ITEMS then
                table.insert(lines, "|cff8f9ba8and " .. (#items - MAX_ITEMS) .. " more|r")
                break
            end
            table.insert(lines, ItemLine(it, extraOf(it)))
        end
    end

    local function Make()
        f = CreateFrame("Frame", "RPChroniclerFigureFrame", UIParent, UI.BACKDROP)
        f:SetSize(330, 520)
        f:SetPoint("CENTER", UIParent, "CENTER", 260, 10)
        f:SetFrameStrata("FULLSCREEN_DIALOG")
        f:SetToplevel(true)
        f:SetFrameLevel(60)
        f:SetMovable(true)
        f:EnableMouse(true)
        f:RegisterForDrag("LeftButton")
        f:SetScript("OnDragStart", f.StartMoving)
        f:SetScript("OnDragStop", f.StopMovingOrSizing)
        f:SetClampedToScreen(true)
        UI.ApplyStoryTomeLook(f)
        if type(UISpecialFrames) == "table" then table.insert(UISpecialFrames, "RPChroniclerFigureFrame") end
        title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        title:SetPoint("TOPLEFT", 14, -12)
        title:SetPoint("RIGHT", -36, 0)
        title:SetJustifyH("LEFT")
        title:SetWordWrap(false)
        pcall(title.SetFont, title, "Fonts\\MORPHEUS.TTF", 18, "")
        local x = UI.CreateSleekButton(f, 22, 20, "x", "danger")
        x:SetPoint("TOPRIGHT", -8, -8)
        x:SetScript("OnClick", function() f:Hide() end)

        -- the figure, on the scenes' misty backdrop
        stage = CreateFrame("Frame", nil, f, UI.BACKDROP)
        stage:SetPoint("TOPLEFT", 12, -38)
        stage:SetPoint("TOPRIGHT", -12, -38)
        stage:SetHeight(250)
        UI.ApplyDarkGlass(stage, 0.10, 0.09, 0.08, 1.0, 0.70, 0.55, 0.25, 0.70)
        if stage.SetClipsChildren then pcall(stage.SetClipsChildren, stage, true) end
        local mist = stage:CreateTexture(nil, "BACKGROUND", nil, -6)
        mist:SetPoint("TOPLEFT", 1, -1)
        mist:SetPoint("BOTTOMRIGHT", -1, 1)
        mist:SetTexture(MEDIA .. "Scene\\mist.png")
        glow = stage:CreateTexture(nil, "BACKGROUND", nil, 2)
        glow:SetTexture(MEDIA .. "Scene\\glow.png")
        glow:SetBlendMode("BLEND")
        glow:SetPoint("CENTER", stage, "CENTER", 0, -6)
        fig = CreateFrame("Frame", nil, stage)
        fig:SetSize(FIG_H * FIG_ASPECT, FIG_H)
        fig:SetPoint("BOTTOM", stage, "BOTTOM", 0, 8)
        fig.shadow = fig:CreateTexture(nil, "ARTWORK")
        fig.shadow:SetAllPoints(fig)
        fig.shadow:SetTexCoord(TEX_L, TEX_R, 0, 1)
        local okB, bm = pcall(CreateFrame, "PlayerModel", nil, stage)
        bossModel = okB and bm or nil
        if bossModel then bossModel:SetPoint("TOPLEFT", 4, -4) bossModel:SetPoint("BOTTOMRIGHT", -4, 4) end
        skull = stage:CreateTexture(nil, "ARTWORK", nil, 1)
        skull:SetSize(80, 80)
        skull:SetPoint("CENTER", stage, "CENTER", 0, 10)
        skull:SetTexture("Interface\\TargetingFrame\\UI-TargetingFrame-Skull")
        -- drag the figure to turn it
        stage:EnableMouse(true)
        stage:SetScript("OnMouseDown", function(self, button)
            if button ~= "LeftButton" then return end
            self.dragX, self.yaw0 = GetCursorPosition(), self.yaw or 0
        end)
        stage:SetScript("OnMouseUp", function(self) self.dragX = nil end)
        stage:SetScript("OnUpdate", function(self)
            if not self.dragX then return end
            if IsMouseButtonDown and not IsMouseButtonDown("LeftButton") then self.dragX = nil return end
            self.yaw = self.yaw0 + (GetCursorPosition() - self.dragX) * 0.012
            if fig.model and fig.model.actor and fig.model:IsShown() then pcall(fig.model.actor.SetYaw, fig.model.actor, self.yaw) end
            if bossModel and bossModel:IsShown() then pcall(bossModel.SetFacing, bossModel, -0.5 + self.yaw) end
        end)
        f.stage = stage
        stage:EnableMouseWheel(true)
        stage:SetScript("OnMouseWheel", function(_, delta) Zoom(delta * 0.15) end)
        local zIn = UI.CreateSleekButton(stage, 22, 20, "+", "tool")
        zIn:SetPoint("TOPRIGHT", -6, -6)
        zIn:SetFrameLevel(stage:GetFrameLevel() + 10)
        zIn.tipTitle, zIn.tipText = "|cffffd100Zoom in|r", "Or the mouse wheel over the picture."
        zIn:SetScript("OnClick", function() Zoom(0.25) end)
        local zOut = UI.CreateSleekButton(stage, 22, 20, "-", "tool")
        zOut:SetPoint("RIGHT", zIn, "LEFT", -4, 0)
        zOut:SetFrameLevel(stage:GetFrameLevel() + 10)
        zOut.tipTitle, zOut.tipText = "|cffffd100Zoom out|r", zIn.tipText
        zOut:SetScript("OnClick", function() Zoom(-0.25) end)
        local hint = stage:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        hint:SetPoint("BOTTOMRIGHT", -6, 4)
        hint:SetShadowOffset(1, -1)
        f.hint = hint

        info = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        info:SetPoint("TOPLEFT", stage, "BOTTOMLEFT", 2, -8)
        info:SetWidth(TEXT_W)
        info:SetJustifyH("LEFT")
        body = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        body:SetPoint("TOPLEFT", info, "BOTTOMLEFT", 0, -8)
        body:SetWidth(TEXT_W)
        body:SetJustifyH("LEFT")
        body:SetJustifyV("TOP")
        body:SetSpacing(4)
        f:SetScript("OnHide", function()
            if fig.model then ClearSlotModel(fig) end
            if bossModel then pcall(bossModel.ClearModel, bossModel) end
        end)
        f:Hide()
    end

    function UI.OpenFigure(st, p, isYou, isBoss)
        if type(st) ~= "table" or type(p) ~= "table" or not p.name then return end
        if not f then Make() end
        local lines = {}
        local items = ns.MemberItems(st, p.name, isBoss)
        stage.yaw, stage.zoom = 0, ZOOM_START
        if fig.model then ClearSlotModel(fig) end
        fig.shadow:Hide()
        skull:Hide()
        if bossModel then bossModel:Hide() end
        if isBoss then
            title:SetText("|cffdc143c" .. tostring(p.name) .. "|r")
            glow:SetVertexColor(0.86, 0.08, 0.24, 0.9)
            glow:SetSize(300, 260)
            local shown = bossModel and SetBossModel(bossModel, st, p.name)
            if shown then bossModel:Show() else skull:Show() end
            f.hint:SetText(shown and "|cff8f9ba8Drag to turn, wheel to zoom|r" or "")
            info:SetText(shown and "|cffd7c4a3Boss|r" or ("|cffd7c4a3Boss.|r |cff8f9ba8" .. BOSS_UNKNOWN .. "|r"))
            table.insert(lines, "|cffffd100Dropped|r")
            if #items.won > 0 then
                List(lines, items.won, function(it) return it.from and it.from ~= "" and ("to " .. it.from) or nil end)
            else
                table.insert(lines, "|cff8f9ba8No notable loot was recorded from it.|r")
            end
        else
            local rgb = ClassRGB(p)
            title:SetText("|cff" .. Hex(rgb) .. tostring(p.name) .. "|r")
            glow:SetVertexColor(rgb[1], rgb[2], rgb[3], 0.85)
            glow:SetSize(260, 280)
            local unit = isYou and "player" or NearUnit(p.name)
            local real = unit and ShowReal(fig, unit, (isYou and st.gear) or (not isYou and p.gear) or nil)
            fig:SetSize(FIG_H * FIG_ASPECT, FIG_H)
            fig:ClearAllPoints()
            fig:SetPoint("BOTTOM", stage, "BOTTOM", 0, 8)
            if real then
                FitModel(fig, fig:GetWidth(), fig:GetHeight())
                f.hint:SetText("|cff8f9ba8Drag to turn, wheel to zoom|r")
            else
                local tex, unknown = ns.ShadowTexture(p.race, p.sex)
                fig.shadow:SetTexture(tex)
                fig.shadow:SetVertexColor(0.02, 0.02, 0.03, 1)
                fig.shadow:Show()
                f.hint:SetText(unknown and "|cff8f9ba8Race not recorded yet|r" or "|cff8f9ba8Shown as they are only when near you|r")
            end
            local looks = ns.LooksText(p)
            local role = ({ TANK = "Tank", HEALER = "Healer", DAMAGER = "Damage" })[p.role or ""]
            local who = {}
            if p.level and p.level ~= "" then table.insert(who, "Level " .. p.level) end
            if looks ~= "" then table.insert(who, looks) end
            if p.class and p.class ~= "" then table.insert(who, p.class) end
            info:SetText("|cffd7c4a3" .. (#who > 0 and table.concat(who, " ") or "Adventurer") .. (role and (", " .. role) or "") .. "|r"
                .. (p.pet and ("\n|cff80cbc4with " .. tostring(p.pet) .. "|r") or ""))
            table.insert(lines, "|cffffd100Wore on this run|r")
            if #items.worn > 0 then List(lines, items.worn, function() return nil end)
            elseif isYou then table.insert(lines, "|cff8f9ba8Not recorded for this run.|r")
            elseif ns.Get("partyGear") then
                table.insert(lines, "|cff8f9ba8Not recorded: they were never in Inspect range out of combat on this run (or it was recorded before 0.6.4).|r")
            else
                table.insert(lines, "|cff8f9ba8Not recorded: Record party gear is off (Options > Recording).|r")
            end
            table.insert(lines, " ")
            table.insert(lines, "|cffffd100Won on this run|r")
            if #items.won > 0 then List(lines, items.won, function(it) return it.from end)
            else table.insert(lines, "|cff8f9ba8No notable loot recorded.|r") end
        end
        ApplyZoom()
        body:SetText(table.concat(lines, "\n"))
        -- a line count backs up the measured heights (a FontString can
        -- report 0 before its first layout)
        local infoH = math.max(info:GetStringHeight() or 0, 16)
        local bodyH = math.max(body:GetStringHeight() or 0, (#lines + 1) * 16)
        local h = 38 + 250 + 8 + infoH + 8 + bodyH + 18
        f:SetHeight(math.max(360, math.min(760, math.ceil(h))))
        f:Show()
        f:Raise()
    end
end

-- =========================================================
-- 0.6.4 (Mor): a boss's own panel at its chapter in the story text: its
-- model (or a skull while its look is unknown) on the misty backdrop, in
-- a crimson glow. Click it to see the boss up close with what it dropped.
-- The model loads only while the panel is shown.
-- =========================================================
function UI.CreateBossPanel(parent)
    local p = CreateFrame("Frame", nil, parent, UI.BACKDROP)
    p:SetHeight(170)
    p.isBossPanel = true
    UI.ApplyDarkGlass(p, 0.10, 0.09, 0.08, 1.0, 0.70, 0.55, 0.25, 0.70)
    if p.SetClipsChildren then pcall(p.SetClipsChildren, p, true) end
    local mist = p:CreateTexture(nil, "BACKGROUND", nil, -6)
    mist:SetPoint("TOPLEFT", 1, -1)
    mist:SetPoint("BOTTOMRIGHT", -1, 1)
    mist:SetTexture(MEDIA .. "Scene\\mist.png")
    local glow = p:CreateTexture(nil, "BACKGROUND", nil, 2)
    glow:SetTexture(MEDIA .. "Scene\\glow.png")
    glow:SetBlendMode("BLEND")
    glow:SetVertexColor(0.86, 0.08, 0.24, 0.9)
    glow:SetSize(260, 190)
    glow:SetPoint("CENTER", p, "CENTER", 0, -4)
    local okM, m = pcall(CreateFrame, "PlayerModel", nil, p)
    m = okM and m or nil
    if m then m:SetPoint("TOPLEFT", 4, -4) m:SetPoint("BOTTOMRIGHT", -4, 18) m:EnableMouse(false) end
    local skull = p:CreateTexture(nil, "ARTWORK")
    skull:SetSize(56, 56)
    skull:SetPoint("CENTER", p, "CENTER", 0, 8)
    skull:SetTexture("Interface\\TargetingFrame\\UI-TargetingFrame-Skull")
    local name = p:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    name:SetPoint("BOTTOM", p, "BOTTOM", 0, 5)
    name:SetShadowOffset(1, -1)
    name:SetShadowColor(0, 0, 0, 1)
    p:EnableMouse(true)
    p:SetScript("OnEnter", function(self)
        UI.Tooltip(self, "|cffdc143c" .. tostring(self.boss) .. "|r",
            self.shown and "Click to see it up close, with what it dropped." or (BOSS_UNKNOWN .. " Click for what it dropped."))
    end)
    p:SetScript("OnLeave", function() UI.HideTooltip() end)
    p:SetScript("OnMouseUp", function(self, button)
        if button == "LeftButton" and self.story then UI.HideTooltip() UI.OpenFigure(self.story, { name = self.boss }, false, true) end
    end)
    local function Load(self)
        if not self.story or not self.boss then return end
        self.shown = m and SetBossModel(m, self.story, self.boss) or false
        if m then if self.shown then m:Show() else m:Hide() end end
        if self.shown then skull:Hide() else skull:Show() end
    end
    p:SetScript("OnShow", Load)
    p:SetScript("OnHide", function() if m then pcall(m.ClearModel, m) end end)
    function p:SetBoss(st, boss)
        self.story, self.boss = st, boss
        name:SetText("|cffdc143c" .. tostring(boss) .. "|r")
        if self:IsShown() then Load(self) end
    end
    return p
end

-- =========================================================
-- The big window (Enlarge): the same scene, much bigger, with the wheel
-- zooming and dragging to look around. It can be resized.
-- =========================================================
do
    local f = CreateFrame("Frame", "RPChroniclerSceneFrame", UIParent, UI.BACKDROP)
    f:SetSize(900, 520)
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 20)
    f:SetFrameStrata("FULLSCREEN_DIALOG")
    f:SetMovable(true)
    f:SetResizable(true)
    if f.SetResizeBounds then pcall(f.SetResizeBounds, f, 520, 320, 1600, 1000) end
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:SetClampedToScreen(true)
    f:Hide()
    UI.ApplyStoryTomeLook(f)
    if type(UISpecialFrames) == "table" then table.insert(UISpecialFrames, "RPChroniclerSceneFrame") end
    local title = UI.Label(f, "", "GameFontNormal")
    title:SetPoint("TOPLEFT", 14, -12)
    title:SetPoint("RIGHT", -40, 0)
    pcall(title.SetFont, title, "Fonts\\MORPHEUS.TTF", 18, "")
    local closeX = UI.CreateSleekButton(f, 22, 20, "x", "danger")
    closeX:SetPoint("TOPRIGHT", -8, -8)
    closeX:SetScript("OnClick", function() f:Hide() end)
    local hint = UI.Label(f, "|cff8f9ba8Mouse wheel: zoom. Drag: look around. Drag the corner to resize.|r", "GameFontHighlightSmall")
    hint:SetPoint("BOTTOMLEFT", 14, 10)
    local grip = CreateFrame("Button", nil, f)
    grip:SetSize(16, 16)
    grip:SetPoint("BOTTOMRIGHT", -4, 4)
    grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    grip:SetScript("OnMouseDown", function() f:StartSizing("BOTTOMRIGHT") end)
    grip:SetScript("OnMouseUp", function() f:StopMovingOrSizing() end)

    local scene = UI.CreateStoryScene(f, {
        wheelZoom = true, bigText = "Close", bigTip = "Back to the Story Book.",
        onBig = function() f:Hide() end,
    })
    scene.frame:SetPoint("TOPLEFT", 12, -38)
    scene.frame:SetPoint("BOTTOMRIGHT", -12, 30)
    f:SetScript("OnSizeChanged", function() scene:Layout() end)
    UI.bigScene = scene

    function UI.OpenBigScene(st, view, name)
        title:SetText("|cffffd100" .. tostring(name or st.title or "Story") .. "|r")
        f:Show()
        scene:SetStory(st, view)
    end
end
