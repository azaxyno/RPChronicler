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
-- Size: the row fits up to five figures in the reader's width. 0.6.7
-- (Mor): the mouse wheel and + / - zoom around the figures, dragging
-- moves the camera any way (up to a face, down to the boots), and a click
-- on the scene or Enlarge opens the whole party side by side in a big
-- window. Nothing here is protected, so it is safe in combat, and models
-- are cleared when the scene hides.
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
-- texture's height (its feet stand at about 0.955). A live figure is
-- fitted to its own race's shadow, so you stand exactly as tall as a
-- shadow of your race would (measured from Media/Shadows).
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
local function NewSlot(parent, scene)
    local s = CreateFrame("Frame", nil, parent)
    s.scene = scene
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
    -- 0.6.4: click a figure for its card (level, looks, what they wore and
    -- won). 0.6.7: a drag that starts on a figure moves the camera instead.
    s:SetScript("OnMouseDown", function(self, button)
        if button == "LeftButton" and self.scene then self.scene:BeginDrag() end
    end)
    s:SetScript("OnMouseUp", function(self, button)
        if button ~= "LeftButton" then return end
        local moved = self.scene and self.scene:EndDrag()
        if not moved and self.onClick then UI.HideTooltip(); self.onClick(self) end
    end)
    return s
end

-- =========================================================
-- 0.6.7 (Mor's test): a live figure stands exactly as tall as its race's
-- shadow. Its ModelScene covers the figure box, and once the model has
-- loaded the camera is placed from the model's own bounding box: the feet
-- on the shadows' ground line, the head where the race's shadow has its
-- head. If the client can't measure the model, the camera the shadows
-- were captured with is used.
-- =========================================================
local FOV = 0.8

local function ApplyCam(s)
    local m, c = s.model, s.cam
    if not m or not c then return end
    local z = s.camZoom or 1
    -- closer in, and rising toward the face
    pcall(m.SetCameraPosition, m, c.d / z, 0, c.z + (c.head - c.z) * (1 - 1 / z) * 0.75)
end

local function FixedCamera(s)
    s.cam = { d = 5.5, z = 1.1, head = 1.7 }
    s.fixed, s.framed = true, true
    if s.fitW then
        s.model:ClearAllPoints()
        s.model:SetSize(s.fitW * CAP_W, s.fitH * CAP_H)
        s.model:SetPoint("TOPLEFT", s, "TOPLEFT", -s.fitW * CAP_X, 0)
    end
    ApplyCam(s)
    s.model:SetAlpha(1)
end

-- The model's feet and head heights, or nil while it isn't loaded
local function ModelHeight(a)
    if not a or not a.GetActiveBoundingBox then return nil end
    local ok, b1, b2, b3, t1, t2, t3 = pcall(a.GetActiveBoundingBox, a)
    if not ok or b1 == nil then return nil end
    local bz, tz
    if type(b1) == "table" or type(b1) == "userdata" then
        bz, tz = b1.z, b2 and b2.z
    else
        bz, tz = b3, t3
    end
    if type(bz) ~= "number" or type(tz) ~= "number" or tz - bz < 0.05 or tz - bz > 50 then return nil end
    return bz, tz
end

local function FrameActor(s)
    local m = s.model
    if not m or not m.actor or s.fixed then return false end
    local bz, tz = ModelHeight(m.actor)
    if not bz then return false end
    -- the box shows V world units from top to bottom; the model spans the
    -- share of it that the race's shadow spans in its texture
    local share = math.max(0.25, SHADOW_FEET - (s.fitTop or 0.2))
    local V = (tz - bz) / share
    s.cam = {
        d = (V / 2) / math.tan(FOV / 2),
        z = bz - (1 - SHADOW_FEET) * V + V / 2,
        head = tz - (tz - bz) * 0.08,
    }
    s.framed = true
    ApplyCam(s)
    m:SetAlpha(1)
    return true
end

-- A live model box for a slot, made the first time it is needed
local function SlotModel(s)
    if s.model ~= nil then return s.model or nil end
    s.model = false
    local ok, m = pcall(CreateFrame, "ModelScene", nil, s)
    if not ok or not m or not m.CreateActor then return nil end
    pcall(m.SetCameraNearClip, m, 0.1)
    pcall(m.SetCameraFarClip, m, 100)
    pcall(m.SetCameraFieldOfView, m, FOV)
    pcall(m.SetCameraPosition, m, 5.5, 0, 1.1)
    pcall(m.SetCameraOrientationByYawPitchRoll, m, math.pi, 0, 0)
    local okA, actor = pcall(m.CreateActor, m)
    if not okA or not actor then return nil end
    m.actor = actor
    m:EnableMouse(false)
    if m.EnableMouseWheel then pcall(m.EnableMouseWheel, m, false) end
    s.model = m
    pcall(actor.SetScript, actor, "OnModelLoaded", function() if not s.framed then FrameActor(s) end end)
    -- until the model is measured it stays invisible (no jump in size)
    m:SetScript("OnUpdate", function(self, elapsed)
        if s.framed then return end
        self.wait = (self.wait or 0) + (elapsed or 0)
        if not FrameActor(s) and self.wait > 2.5 then FixedCamera(s) end
    end)
    return m
end

local function ClearSlotModel(s)
    s.framed, s.fixed, s.cam = false, false, nil
    if s.model and s.model.actor then pcall(s.model.actor.ClearModel, s.model.actor) end
    if s.model then s.model:Hide() end
end

-- Draws a live model of unit; dressed in gear (the run's) when given.
-- False when this client can't.
local function ShowReal(s, unit, gear)
    local m = SlotModel(s)
    if not m then return false end
    local a = m.actor
    s.framed, s.fixed, s.cam = false, false, nil
    local ok = pcall(a.SetModelByUnit, a, unit, false, true, false, true)
    if not ok then return false end
    if gear and a.Undress then
        pcall(a.Undress, a)
        for _, g in ipairs(gear) do
            if type(g) == "table" and g.link then pcall(a.TryOn, a, g.link) end
        end
    end
    pcall(a.SetYaw, a, 0)
    m.wait = 0
    m:SetAlpha(0)
    m:Show()
    FrameActor(s)
    return true
end

-- 0.7.0: a dressed stand-in for someone who is not near you: their race in
-- the outfit they wore (look.slots appearances, else their gear links),
-- on a body of your own sex (the game can't draw the other sex from your
-- model). A book's author may carry a likeness they picked (an NPC face,
-- p.face): that model is undressed and dressed the same way where the
-- client allows. Every step is in a pcall; a refusal falls back to the
-- shadow. Returns "face", "standin" or false.
local function Dress(a, p)
    local look = type(p.look) == "table" and p.look or nil
    local dressed = false
    if a.Undress then pcall(a.Undress, a) end
    if look and type(look.slots) == "table" and a.SetItemTransmogInfo and ItemUtil and ItemUtil.CreateItemTransmogInfo then
        for slot, v in pairs(look.slots) do
            if type(v) == "table" and (v.a or 0) > 0 then
                local okI, info = pcall(ItemUtil.CreateItemTransmogInfo, v.a, v.s or 0, v.i or 0)
                if okI and info and pcall(a.SetItemTransmogInfo, a, info, slot) then dressed = true end
            end
        end
    end
    if not dressed and a.TryOn then
        for _, g in ipairs(type(p.gear) == "table" and p.gear or {}) do
            if type(g) == "table" and g.link and pcall(a.TryOn, a, g.link) then dressed = true end
        end
    end
    return dressed
end

local function ShowStandIn(s, p)
    if ns.Get("standIns") == false then return false end
    local look = type(p.look) == "table" and p.look or nil
    local race = tonumber((look and look.race) or p.race)
    local sex = tonumber((look and look.sex) or p.sex)
    if not race or not (look or type(p.gear) == "table" and #p.gear > 0) then return false end
    local m = SlotModel(s)
    if not m then return false end
    local a = m.actor
    s.framed, s.fixed, s.cam = false, false, nil
    local kind
    if type(p.face) == "table" and tonumber(p.face.id) and a.SetModelByCreatureDisplayID
        and pcall(a.SetModelByCreatureDisplayID, a, tonumber(p.face.id)) then
        kind = "face"
    else
        local mySex = ns.SafeNum(UnitSex and UnitSex("player"))
        if not sex or not mySex or sex ~= mySex then return false end
        if not pcall(a.SetModelByUnit, a, "player", false, true, false, true, false, race) then return false end
        kind = "standin"
    end
    Dress(a, p)
    pcall(a.SetYaw, a, 0)
    m.wait = 0
    m:SetAlpha(0)
    m:Show()
    FrameActor(s)
    return kind
end
UI.ShowStandIn = ShowStandIn
local STAND_TIP = { face = "The likeness they chose, in the outfit they wore. The game can't send a face.",
    standin = "A likeness: their race and the outfit they wore. Faces can't be recorded." }

-- Places the model box over the slot's figure box (w x h)
local function FitModel(s, w, h)
    if not s.model then return end
    s.fitW, s.fitH = w, h
    s.model:ClearAllPoints()
    if s.fixed then
        s.model:SetSize(w * CAP_W, h * CAP_H)
        s.model:SetPoint("TOPLEFT", s, "TOPLEFT", -w * CAP_X, 0)
    else
        s.model:SetAllPoints(s)
    end
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
local BOSS_UNKNOWN = "Its look isn't known: the game's journal doesn't have it and it isn't in RP Chronicler's list of bosses yet."

-- 0.6.8: poses, from the game's own animations (a model without one
-- stands): ready to fight, or the boss lying dead after the kill
local ANIM_STAND, ANIM_DEAD, ANIM_READY1H, ANIM_READYBOW, ANIM_READYSPELL = 0, 6, 26, 29, 51
local CASTERS = { MAGE = true, PRIEST = true, WARLOCK = true, SHAMAN = true, DRUID = true }
local function Pose(s, p, pose)
    local a = s.model and s.model.actor
    if not (a and a.SetAnimation) then return end
    local anim = ANIM_STAND
    if pose == "fight" then
        local cf = p and p.classFile or ""
        anim = (cf == "HUNTER" and ANIM_READYBOW) or (CASTERS[cf] and ANIM_READYSPELL) or ANIM_READY1H
    end
    pcall(a.SetAnimation, a, anim)
end

local function ShowBoss(slot, name, st, pose)
    slot.icon:Hide()
    if slot.bossModel == nil then
        local ok, m = pcall(CreateFrame, "PlayerModel", nil, slot)
        slot.bossModel = (ok and m) or false
        if slot.bossModel then slot.bossModel:SetAllPoints(slot) end
    end
    local m = slot.bossModel
    local shown = m and SetBossModel(m, st, name) or false
    if m then if shown then m:Show() else m:Hide() end end
    if shown and m.SetAnimation then
        local anim = (pose == "fall") and ANIM_DEAD or ((pose == "fight") and ANIM_READY1H or ANIM_STAND)
        pcall(m.SetAnimation, m, anim)
        -- again once the model has loaded (a new model starts standing)
        pcall(m.SetScript, m, "OnModelLoaded", function(self) pcall(self.SetAnimation, self, anim) end)
    end
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

-- parent: the frame it lives in. 0.6.7: the mouse wheel always zooms over
-- the scene. opts.spread: the figures stand side by side, none behind
-- another (the big window). opts.onBig: Enlarge, and a click on the scene.
function UI.CreateStoryScene(parent, opts)
    local self = setmetatable({ opts = opts or {}, zoom = 1, panX = 0, panY = 0, slots = {}, view = 1 }, Scene)
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
    self.zoomIn.tipTitle, self.zoomIn.tipText = "|cffffd100Zoom in|r", "Or the mouse wheel over the scene. Drag to move the camera."
    self.zoomOut.tipTitle, self.zoomOut.tipText = "|cffffd100Zoom out|r", self.zoomIn.tipText
    self.big.tipTitle = "|cffffd100" .. (opts and opts.bigText or "Enlarge") .. "|r"
    self.big.tipText = (opts and opts.bigTip) or "Shows the whole party side by side in a big window. Or click the scene."
    self.prev:SetScript("OnClick", function() self:Step(-1) end)
    self.next:SetScript("OnClick", function() self:Step(1) end)
    self.zoomIn:SetScript("OnClick", function() self:Zoom(0.25) end)
    self.zoomOut:SetScript("OnClick", function() self:Zoom(-0.25) end)
    self.big:SetScript("OnClick", function()
        if self.opts.onBig then self.opts.onBig(self) end
    end)

    f:EnableMouse(true)
    f:EnableMouseWheel(true)
    f:SetScript("OnMouseWheel", function(_, delta) self:Zoom(delta * 0.2) end)
    -- drag to move the camera (any way, while zoomed in); a click opens
    -- the big window
    f:SetScript("OnMouseDown", function(_, button)
        if button == "LeftButton" then self:BeginDrag() end
    end)
    f:SetScript("OnMouseUp", function(_, button)
        if button ~= "LeftButton" then return end
        if not self:EndDrag() and self.opts.onBig and not self.opts.spread then self.opts.onBig(self) end
    end)
    f:SetScript("OnUpdate", function(_, elapsed)
        if self.theme and ns.Get("bookMotion") then
            self.driftT = (self.driftT or 0) + (elapsed or 0)
            self.driftWait = (self.driftWait or 0) + (elapsed or 0)
            if self.driftWait > 0.05 then self.driftWait = 0 self:Drift(self.driftT) end
        end
        local d = self.drag
        if not d or d.stop then return end
        if IsMouseButtonDown and not IsMouseButtonDown("LeftButton") then d.stop = true return end
        local x, y = GetCursorPosition()
        local sc = f:GetEffectiveScale() or 1
        local dx, dy = x / sc - d.x, y / sc - d.y
        if not d.moved and dx * dx + dy * dy < 16 then return end
        d.moved = true
        self.panX, self.panY = d.px + dx, d.py + dy
        self:Layout()
    end)
    f:SetScript("OnHide", function() self:Release() end)
    f:SetScript("OnSizeChanged", function() self:Layout() self:Drift(self.driftT) end)
    f:SetScript("OnShow", function() if self.story then self:Refresh() end end)
    return self
end

-- Scenes of a story: the party (the cover). 0.6.8 (Mor): a boss scene
-- (at the boss's chapter) shows the party facing the boss, then, once
-- it was killed (or the run kept no kills), the boss fallen.
function Scene:Views()
    local b = self.bossName
    if not b then return { { kind = "party" } } end
    local out = { { kind = "boss", boss = b, pose = "fight" } }
    local kills = self.story and self.story.bossKills
    local killed = type(kills) ~= "table" or #kills == 0
    for _, k in ipairs(type(kills) == "table" and kills or {}) do if k == b then killed = true end end
    if killed then table.insert(out, { kind = "boss", boss = b, pose = "fall" }) end
    return out
end

function Scene:SetBoss(st, boss, view)
    self.bossName = boss
    self:SetStory(st, view)
end

function Scene:SetStory(st, view)
    self.story = st
    self.view = view or 1
    self.zoom, self.panX, self.panY = 1, 0, 0
    self:Refresh()
end

function Scene:Step(d)
    local n = #self:Views()
    self.view = ((self.view - 1 + d) % n) + 1
    self.panX, self.panY = 0, 0
    self:Refresh()
    if self.opts.onView then self.opts.onView(self.view) end
end

function Scene:Zoom(d)
    self.zoom = math.max(1, math.min(3, self.zoom + d))
    if self.zoom == 1 then self.panX, self.panY = 0, 0 end
    self:Layout()
end

function Scene:BeginDrag()
    local x, y = GetCursorPosition()
    local sc = self.frame:GetEffectiveScale() or 1
    self.drag = { x = (x or 0) / sc, y = (y or 0) / sc, px = self.panX, py = self.panY }
end

-- True when the press moved the camera (so it was no click)
function Scene:EndDrag()
    local d = self.drag
    self.drag = nil
    return d and d.moved or false
end

function Scene:Release()
    for _, s in ipairs(self.slots) do
        ClearSlotModel(s)
        if s.bossModel then pcall(s.bossModel.ClearModel, s.bossModel) end
    end
    self.drag = nil
end

local function Slot(self, i)
    local s = self.slots[i]
    if not s then
        s = NewSlot(self.stage, self)
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
    self.theme = nil
    if art and pcall(self.art.SetTexture, self.art, art) then
        self.art:SetTexCoord(0, 0.68, 0, 0.75)
        self.art:Show()
        self.veil:Show()
        return
    end
    -- 0.6.8: a painting of the kind of place (SceneData.lua), drifting
    -- slowly across while the scene is shown
    local theme = ns.SceneTheme and ns.SceneTheme(st)
    if theme and pcall(self.art.SetTexture, self.art, MEDIA .. "Scene\\bg_" .. theme .. ".png") then
        self.theme = theme
        self.art:Show()
        self.veil:Hide()
        self:Drift(0)
    else
        self.art:Hide()
        self.veil:Hide()
    end
end

-- The painting shows its middle and drifts left and right over about 40
-- seconds (still when Book animations is off)
local DRIFT_PERIOD = 40
function Scene:Drift(t)
    if not self.theme then return end
    local W, H = self.frame:GetWidth() or 0, self.frame:GetHeight() or 0
    if W < 2 or H < 2 then return end
    local vh = 0.9
    local fw = math.min(0.86, (W / H) / 2 * vh)
    if fw >= 0.86 then vh = 0.86 * 2 * H / W end
    local room = (1 - fw) / 2
    local u = room + math.sin((t or 0) * 2 * math.pi / DRIFT_PERIOD) * room * 0.8
    local v0 = (1 - vh) - 0.02
    self.art:SetTexCoord(u, u + fw, math.max(0, v0), math.max(0, v0) + vh)
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
        local unit = m.isYou and "player" or (p.name == ns.PlayerName() and "player") or NearUnit(p.name)
        local key = tostring((ns.ShadowTexture(p.race, p.sex))):match("([%w_]+)%.png$")
        s.fitTop = SHADOW_TOP[key or ""] or SHADOW_TOP.unknown
        local real = unit and ShowReal(s, unit, (m.isYou and st.gear) or (not m.isYou and p.gear) or nil)
        local stand = not real and ShowStandIn(s, p)
        if real or stand then
            s.shadow:Hide()
            Pose(s, p, v.pose)
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
                or (stand and STAND_TIP[stand]) or (s.unknown and "A shadow. This older run did not record their race, so it fills in when you next see them (in your group, as a target or under the mouse)."
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
        ShowBoss(s, v.boss, st, v.pose)
        s.tipText = s.tipText .. "\n|cff8f9ba8Click for what it dropped.|r"
        s.onClick = function(slot) UI.OpenFigure(st, { name = v.boss }, false, true) end
        s:Show()
        self.bossSlot = s
    end
    for i = #members + (v.kind == "boss" and 2 or 1), #self.slots do self.slots[i]:Hide() end
    self.label:SetText((v.pose == "fall" and ("|cffdc143c" .. v.boss .. "|r |cffd7c4a3falls|r"))
        or (v.kind == "boss" and ("|cffffd100The party|r |cffd7c4a3faces|r |cffdc143c" .. v.boss .. "|r"))
        or "|cffffd100The party|r")
    self.more:SetText(more > 0 and ("|cffd7c4a3and " .. more .. " more|r") or "")
    local multi = #views > 1
    if multi then self.prev:Show(); self.next:Show() else self.prev:Hide(); self.next:Hide() end
    self:Layout()
end

-- Positions the figures for the frame's size, zoom and camera.
-- 0.6.7 (Mor's test): the zoom grows the whole scene around the figures'
-- chests and the drag moves the camera any way, so a face or the boots
-- can be brought into view. Names stand under the figures, on two
-- staggered rows (first names when even that is tight) when the figures
-- stand close.
function Scene:Layout()
    local f = self.frame
    local W, H = f:GetWidth() or 0, f:GetHeight() or 0
    if W < 40 or H < 40 or not self.members then return end
    local n = #self.members
    local spread = self.opts.spread
    local bossW = self.bossSlot and math.floor(W * 0.36) or 0
    local partyW = W - bossW - 16
    local gap = spread and 1.08 or 0.62
    local figH = (H - 30 - 8) * 0.86
    local function RowWidth(h) local w = h * FIG_ASPECT return w + (n - 1) * w * gap end
    if n > 0 and RowWidth(figH) > partyW then figH = figH * partyW / RowWidth(figH) end
    local figW = figH * FIG_ASPECT
    local step = figW * gap
    local mode = (n <= 1 or step >= 112) and "each" or ((step * 2 >= 104) and "two" or "first")
    local ground = (mode == "each") and 18 or 30
    local rowW = n > 0 and (figW + (n - 1) * step) or 0
    local left = 8 + (partyW - rowW) / 2
    local center = (n + 1) / 2
    -- the camera
    local z = self.zoom or 1
    if z <= 1 then self.panX, self.panY = 0, 0 end
    local mx, my = W * z * 0.5, H * z * 0.6
    self.panX = math.max(-mx, math.min(mx, self.panX or 0))
    self.panY = math.max(-my, math.min(my, self.panY or 0))
    local cx, cy = W / 2, ground + figH * 0.62
    local function TX(x) return cx + (x - cx) * z + self.panX end
    local function TY(y) return cy + (y - cy) * z + self.panY end
    local groundY = TY(ground)
    for i, m in ipairs(self.members) do
        local s = self.slots[i]
        local d = math.abs(i - center)
        local scale = spread and 1 or (1 - d * 0.06)
        local h, w = figH * scale, figW * scale
        local x = left + (i - 1) * step + (figW - w) / 2
        local y = ground + (spread and 0 or d * figH * 0.05)
        local X, Y, ww, hh = TX(x), TY(y), w * z, h * z
        s:ClearAllPoints()
        s:SetSize(ww, hh)
        s:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", X, Y)
        s:SetFrameLevel((f:GetFrameLevel() or 1) + 10 - math.floor(d * 2))
        s.shadow:SetAllPoints(s)
        s.glow:ClearAllPoints()
        s.glow:SetSize(ww * 1.5, hh * 1.1)
        s.glow:SetPoint("CENTER", s, "CENTER", 0, -hh * 0.05)
        s.foot:ClearAllPoints()
        s.foot:SetSize(ww * 0.9, hh * 0.12)
        s.foot:SetPoint("CENTER", s, "BOTTOM", 0, hh * 0.04)
        FitModel(s, ww, hh)
        -- the name, in the class color
        local full = tostring(m.p.name)
        local text = (mode == "first") and (full:match("^(%S+)") or full) or full
        s.name:SetText(ns.RoleIconText(m.p) .. "|cff" .. Hex(s.rgb or ClassRGB(m.p)) .. text .. "|r")
        local row = (mode ~= "each" and i % 2 == 0) and 1 or 0
        s.name:ClearAllPoints()
        s.name:SetWidth(n <= 1 and math.max(60, W - 16) or math.max(56, step * z * ((mode == "each") and 1 or 2) - 4))
        s.name:SetPoint("TOP", f, "BOTTOMLEFT", X + ww / 2, groundY - 2 - row * 12)
        s.name:Show()
        -- far outside the stage: hidden
        local visible = (X + ww > 0) and (X < W) and (Y < H) and (Y + hh > -40)
        if visible then s:Show() else s:Hide() end
    end
    if self.bossSlot then
        local s = self.bossSlot
        local bw, bh = bossW * z, math.min(H - ground - 10, bossW * 1.3) * z
        s:ClearAllPoints()
        s:SetSize(bw, bh)
        s:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", TX(W - 8 - bossW), TY(ground))
        s:SetFrameLevel((f:GetFrameLevel() or 1) + 12)
        s.glow:ClearAllPoints()
        s.glow:SetSize(bw * 1.4, bh * 1.1)
        s.glow:SetPoint("CENTER", s, "CENTER", 0, 0)
        s.foot:ClearAllPoints()
        s.foot:SetSize(bw * 0.9, bh * 0.1)
        s.foot:SetPoint("CENTER", s, "BOTTOM", 0, bh * 0.04)
        s.name:ClearAllPoints()
        s.name:SetPoint("TOP", s, "BOTTOM", 0, -2)
        s.name:SetWidth(bw)
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
            fig.camZoom = z
            ApplyCam(fig)
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
            local key = tostring((ns.ShadowTexture(p.race, p.sex))):match("([%w_]+)%.png$")
            fig.fitTop = SHADOW_TOP[key or ""] or SHADOW_TOP.unknown
            fig.camZoom = ZOOM_START
            local real = unit and ShowReal(fig, unit, (isYou and st.gear) or (not isYou and p.gear) or nil)
            local stand = not real and not isBoss and ShowStandIn(fig, p)
            fig:SetSize(FIG_H * FIG_ASPECT, FIG_H)
            fig:ClearAllPoints()
            fig:SetPoint("BOTTOM", stage, "BOTTOM", 0, 8)
            if real or stand then
                FitModel(fig, fig:GetWidth(), fig:GetHeight())
                f.hint:SetText("|cff8f9ba8" .. (stand and "A likeness. " or "") .. "Drag to turn, wheel to zoom|r")
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
-- =========================================================
-- The big window (Enlarge, or a click on the scene): the whole party side
-- by side, each at full size (0.6.7, Mor), with the wheel zooming and
-- dragging moving the camera. It can be resized.
-- =========================================================
do
    local f = CreateFrame("Frame", "RPChroniclerSceneFrame", UIParent, UI.BACKDROP)
    f:SetSize(1000, 560)
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
    local hint = UI.Label(f, "|cff8f9ba8Mouse wheel: zoom. Drag: move the camera. Click someone to see them up close. Drag the corner to resize.|r", "GameFontHighlightSmall")
    hint:SetPoint("BOTTOMLEFT", 14, 10)
    local grip = CreateFrame("Button", nil, f)
    grip:SetSize(16, 16)
    grip:SetPoint("BOTTOMRIGHT", -4, 4)
    grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    grip:SetScript("OnMouseDown", function() f:StartSizing("BOTTOMRIGHT") end)
    grip:SetScript("OnMouseUp", function() f:StopMovingOrSizing() end)

    local scene = UI.CreateStoryScene(f, {
        spread = true, bigText = "Close", bigTip = "Back to the Story Book.",
        onBig = function() f:Hide() end,
    })
    scene.frame:SetPoint("TOPLEFT", 12, -38)
    scene.frame:SetPoint("BOTTOMRIGHT", -12, 30)
    f:SetScript("OnSizeChanged", function() scene:Layout() end)
    UI.bigScene = scene

    -- 0.6.8: boss = a boss scene (the party facing that boss)
    function UI.OpenBigScene(st, view, name, boss)
        title:SetText("|cffffd100" .. tostring(name or st.title or "Story") .. "|r")
        f:Show()
        scene:SetBoss(st, boss, view)
    end
end

-- =========================================================
-- 0.6.8 (Mor): the book's music. While a dungeon or raid story's pages
-- are open, the game's own music for that kind of place plays (one track
-- per story, picked from its id, at the player's music volume). Nothing
-- plays with Story scenes or Dungeon music off; StopMusic gives the
-- game's own music back when the book closes or turns to another story.
-- =========================================================
do
    local playing
    function UI.BookMusic(st)
        local list
        if type(st) == "table" and (st.kind == "dungeon" or st.kind == "raid")
            and ns.Get("storyCover") and ns.Get("bookMusic") and ns.SceneTheme then
            local t = ns.SCENE_THEMES[ns.SceneTheme(st) or ""]
            list = t and t.music
        end
        if not (list and #list > 0 and PlayMusic) then
            if playing and StopMusic then pcall(StopMusic) end
            playing = nil
            return
        end
        if playing == st.id then return end
        local n = 0
        for c in tostring(st.id):gmatch("%d") do n = n + tonumber(c) end
        pcall(PlayMusic, list[n % #list + 1])
        playing = st.id
    end
end
