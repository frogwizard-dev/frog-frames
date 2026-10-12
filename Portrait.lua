local _, ns = ...

-- The round portrait beside a frame's bars, and what goes on it: a ring in the look's style, the
-- level badge on its lower outer edge, the elite / rare dragon (target and focus) and the hit
-- text (Blizzard's combat feedback).
--   local p = ns.CreatePortrait(parent, level)
--   p:Layout(size, side)   -- outer diameter in units; side "left"/"right": which side of the bars
--   p:Set(unit, mode)      -- mode "3d", "class", "2d"; unit nil = a sample (your own)
--   p:Ring()               -- how thick the ring is, in units
--   p:SetDragon(classification), p:CombatEvent(...), p.badge / p.level
-- Classic: our own ring (Media\Ring.tga: a near-black outline, a dark metal band lit from above,
-- a thin dark-gold line and a black inner edge shadowing the picture) and badge (Media\Badge.tga).
-- Modern and forever: rings made of discs (the circle mask as a plain texture, tinted) stacked
-- behind the picture. The picture is masked round (Media\CircleMask.tga); 2D portraits come
-- round from the game already. A 3D model can't be masked, so it sits in the square inside the
-- circle.

local issecret, Safe = ns.issecret, ns.Safe
local MEDIA = "Interface\\AddOns\\FrogFrames\\Media\\"
local DISC = MEDIA .. "CircleMask.tga"
local RING = MEDIA .. "Ring.tga"
local BADGE = MEDIA .. "Badge.tga"
local HOLE = 53 / 64 -- Ring.tga's hole, as a share of its size (make_frogframes_art.py's RING_HOLE)
local CLASS_ICONS = "Interface\\TargetingFrame\\UI-Classes-Circles"
local CLASS_COORDS = {
    WARRIOR = { 0, 0.25, 0, 0.25 }, MAGE = { 0.25, 0.49609375, 0, 0.25 },
    ROGUE = { 0.49609375, 0.7421875, 0, 0.25 }, DRUID = { 0.7421875, 0.98828125, 0, 0.25 },
    HUNTER = { 0, 0.25, 0.25, 0.5 }, SHAMAN = { 0.25, 0.49609375, 0.25, 0.5 },
    PRIEST = { 0.49609375, 0.7421875, 0.25, 0.5 }, WARLOCK = { 0.7421875, 0.98828125, 0.25, 0.5 },
    PALADIN = { 0, 0.25, 0.5, 0.75 },
}
-- Where the level badge sits, from the portrait's centre, in diameters (lower, on the outer side),
-- and its size.
local BADGE_X, BADGE_Y, BADGE_SIZE = 0.37, -0.36, 0.40

-- The dragons (Media\Dragon*.tga, FrogPlates' cut of the classic target frame's elite art,
-- 128x128 texels): the portrait's hole in them, the ring's outside edge (about 35 texels from the
-- hole's centre in the original art) and how far the art reaches from the hole's centre across
-- the portrait's other side (towards the bars).
local MEDIA_DRAGON = MEDIA
local DRAGON = { size = 128, holeX = 51.5, holeY = 58.5, ringOut = 35, near = 44.5 }
local DRAGON_ART = { elite = "DragonElite", worldboss = "DragonElite", rare = "DragonRare", rareelite = "DragonRareElite" }

local Portrait = {}
Portrait.__index = Portrait

local function Disc(parent, layer, sublevel)
    local t = parent:CreateTexture(nil, layer, nil, sublevel)
    t:SetTexture(DISC)
    return t
end

-- level: its frame level (before its parts are made, so they stack above it).
function ns.CreatePortrait(parent, level)
    local p = setmetatable({}, Portrait)
    local f = CreateFrame("Frame", nil, parent)
    if level then f:SetFrameLevel(level) end
    p.frame = f
    -- Behind the picture: the discs that make the modern and forever rings, then a dark disc
    -- the picture sits on.
    -- A soft halo round the ring (the frame's glow), under everything.
    p.halo = f:CreateTexture(nil, "BACKGROUND", nil, -8)
    p.halo:SetTexture(MEDIA .. "Halo.tga")
    p.halo:SetBlendMode("ADD")
    p.halo:SetPoint("CENTER")
    p.halo:Hide()
    p.outer = Disc(f, "BACKGROUND", -6)
    p.rim = Disc(f, "BACKGROUND", -5)
    p.inner = Disc(f, "BACKGROUND", -4)
    p.back = Disc(f, "BACKGROUND", -3)
    p.back:SetVertexColor(0.05, 0.05, 0.05, 1)
    for _, t in ipairs({ p.outer, p.rim, p.inner, p.back }) do t:SetPoint("CENTER") end

    p.pic = f:CreateTexture(nil, "ARTWORK")
    p.pic:SetPoint("CENTER")
    p.mask = f:CreateMaskTexture()
    p.mask:SetTexture(DISC, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    p.mask:SetAllPoints(p.pic)
    p.pic:AddMaskTexture(p.mask)

    p.model = CreateFrame("PlayerModel", nil, f)
    p.model:SetPoint("CENTER")
    p.model:Hide()
    -- A model shown again starts blank: give it its unit back.
    p.model:SetScript("OnShow", function() if p.modelUnit then p:SetModel(p.modelUnit) end end)

    -- Above the picture: the classic ring, the dragon, the badge and the hit text.
    p.top = CreateFrame("Frame", nil, f)
    p.top:SetAllPoints()
    p.top:SetFrameLevel(p.model:GetFrameLevel() + 2)
    p.ring = p.top:CreateTexture(nil, "ARTWORK")
    p.ring:SetTexture(RING)
    p.ring:SetAllPoints(f)
    p.dragon = p.top:CreateTexture(nil, "BORDER")
    p.dragon:Hide()
    -- The level badge: Badge.tga in the classic look, a disc ring in the others.
    p.badge = CreateFrame("Frame", nil, p.top)
    p.badge:SetFrameLevel(p.top:GetFrameLevel() + 1)
    p.badgeArt = p.badge:CreateTexture(nil, "ARTWORK")
    p.badgeArt:SetAllPoints()
    p.badgeOuter = Disc(p.badge, "BORDER", 0)
    p.badgeOuter:SetAllPoints()
    p.badgeInner = Disc(p.badge, "BORDER", 1)
    p.badgeInner:SetPoint("CENTER")
    p.level = p.badge:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    p.level:SetPoint("CENTER", 0, 0)
    p.level:SetShadowOffset(1, -1)
    p.level:SetShadowColor(0, 0, 0, 1)
    p.hit = p.top:CreateFontString(nil, "OVERLAY", "NumberFontNormalHuge")
    p.hit:SetPoint("CENTER")
    p.hit:Hide()
    p.top:SetScript("OnUpdate", function() p:FadeHit() end)
    return p
end

-- The portrait's look: the stone frames wear the classic ring.
function ns.PortraitLook()
    local look = ns.db.look
    return look == "stone" and "classic" or look
end

-- This portrait's look: "vanilla" in a vanilla frame (its art has the ring), else the frames'.
function Portrait:Look()
    return self.vanilla and "vanilla" or ns.PortraitLook()
end

-- How thick the ring is, in units: the picture shows inside it.
function Portrait:Ring()
    local look, size = self:Look(), self.size or 0
    local px = FrogLib.Pixel(self.frame)
    if look == "vanilla" then return 0 end
    if look == "classic" then return size / 2 * (1 - HOLE) end
    if look == "forever" then return 3 * (ns.db.frameThickness or 1) * px end
    return 2 * px
end

-- dx, dy: the level badge's offset (the frame's settings).
function Portrait:Layout(size, side, dx, dy)
    local f, look = self.frame, self:Look()
    self.size, self.side = size, side
    f:SetSize(size, size)
    local px = FrogLib.Pixel(f)
    local hole = size - 2 * self:Ring()
    -- Halo.tga's glow starts at 70% of its size and reaches 8 pixels or so past the ring.
    local halo = math.max(size / 0.7, size + 16 * px)
    self.halo:SetSize(halo, halo)
    -- The classic ring's black inner edge goes over the picture's edge; the disc rings are
    -- behind it, so there it's exactly the hole.
    local pic = look == "classic" and hole + 2 * px or hole
    self.pic:SetSize(pic, pic)
    self.back:SetSize(pic, pic)
    -- The model fills the square inside the circle.
    local inner = ns.Snap(hole * 0.72, px)
    self.model:SetSize(inner, inner)

    self.ring:SetShown(look == "classic")
    local t = (ns.db.frameThickness or 1) * px
    if look == "modern" then
        -- A plain dark ring with a black outline.
        self.outer:SetSize(size, size)
        self.outer:SetVertexColor(0, 0, 0, 1)
        self.rim:SetSize(size - 2 * px, size - 2 * px)
        self.rim:SetVertexColor(0.13, 0.13, 0.13, 1)
        self.outer:Show()
        self.rim:Show()
        self.inner:Hide()
    elseif look == "forever" then
        -- The Forever frame's three lines: a dark outline, a light metallic rim brighter at the
        -- top, and a dark inner line.
        self.outer:SetSize(size, size)
        self.outer:SetVertexColor(0.02, 0.02, 0.02, 1)
        self.rim:SetSize(size - 2 * t, size - 2 * t)
        self.rim:SetVertexColor(1, 1, 1, 1)
        if self.rim.SetGradient and CreateColor then
            pcall(self.rim.SetGradient, self.rim, "VERTICAL", CreateColor(0.42, 0.42, 0.46, 1), CreateColor(0.80, 0.80, 0.84, 1))
        end
        self.inner:SetSize(size - 4 * t, size - 4 * t)
        self.inner:SetVertexColor(0.08, 0.08, 0.08, 1)
        self.outer:Show()
        self.rim:Show()
        self.inner:Show()
    else
        self.outer:Hide()
        self.rim:Hide()
        self.inner:Hide()
    end

    -- The badge, on the lower outer edge.
    local b = ns.Snap(size * BADGE_SIZE, px)
    local out = side == "left" and -1 or 1
    self.badge:SetSize(b, b)
    self.badge:ClearAllPoints()
    self.badge:SetPoint("CENTER", f, "CENTER", out * size * BADGE_X + (dx or 0), size * BADGE_Y + (dy or 0))
    self.badgeArt:SetTexture(BADGE)
    self.badgeArt:SetShown(look == "classic")
    self.badgeOuter:SetShown(look ~= "classic" and look ~= "vanilla")
    self.badgeInner:SetShown(look ~= "classic" and look ~= "vanilla")
    if look == "forever" then
        self.badgeOuter:SetVertexColor(0.62, 0.62, 0.66, 1)
    else
        self.badgeOuter:SetVertexColor(0, 0, 0, 1)
    end
    self.badgeInner:SetSize(b - 2 * (look == "forever" and t or px), b - 2 * (look == "forever" and t or px))
    self.badgeInner:SetVertexColor(0.06, 0.06, 0.06, 1)
    local levelSize = math.max(8, math.floor(b * 0.5 + 0.5))
    ns.Media:SetFont(self.level, ns.db.font, levelSize, ns.db.outline)

    self:PlaceDragon()
    self.hitHeight = math.max(10, math.floor(size * 0.3))
    ns.Media:SetFont(self.hit, ns.db.font, self.hitHeight, ns.db.outline)
end

-- How far the badge reaches past the portrait's edge, below and outwards, in units.
function Portrait:BadgeReach()
    local size = self.size or 0
    return size * (-BADGE_Y + BADGE_SIZE / 2) - size / 2, size * (BADGE_X + BADGE_SIZE / 2) - size / 2
end

------------------------------------------------------------------------------
-- The picture
------------------------------------------------------------------------------

function Portrait:SetModel(unit)
    local m = self.model
    m:ClearModel()
    m:SetUnit(unit)
    m:SetPortraitZoom(1)
    m:SetCamDistanceScale(1)
    m:SetPosition(0, 0, 0)
end

-- mode "3d", "class" or "2d"; unit nil for a sample (your own picture).
function Portrait:Set(unit, mode)
    local who = unit or "player"
    if mode == "3d" then
        -- Out of sight the game has no model to draw: the 2D picture instead.
        local visible = Safe(UnitIsVisible(who))
        if visible ~= false and Safe(UnitIsConnected(who)) ~= false then
            self.pic:Hide()
            self.modelUnit = who
            if not self.model:IsShown() then
                self.model:Show() -- OnShow sets the unit
            else
                self:SetModel(who)
            end
            return
        end
    end
    self.modelUnit = nil
    self.model:Hide()
    self.pic:Show()
    if mode == "class" and Safe(UnitIsPlayer(who)) then
        local _, class = UnitClass(who)
        class = Safe(class)
        local coords = class and ((CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[class]) or CLASS_COORDS[class])
        if coords then
            self.pic:SetTexture(CLASS_ICONS)
            -- A little zoomed in: the icons have a rim of their own, which our ring replaces.
            local w, h = coords[2] - coords[1], coords[4] - coords[3]
            self.pic:SetTexCoord(coords[1] + w * 0.06, coords[2] - w * 0.06, coords[3] + h * 0.06, coords[4] - h * 0.06)
            return
        end
    end
    self.pic:SetTexCoord(0, 1, 0, 1)
    SetPortraitTexture(self.pic, who)
end

------------------------------------------------------------------------------
-- The dragon: elite (gold), rare (silver) or rare elite (silver, winged); world bosses gold
------------------------------------------------------------------------------

function Portrait:DragonScale()
    return (self.size or 0) / 2 / DRAGON.ringOut -- units per texel
end

function Portrait:PlaceDragon()
    local s = self:DragonScale()
    local dx, dy = (DRAGON.size / 2 - DRAGON.holeX) * s, (DRAGON.size / 2 - DRAGON.holeY) * s
    local d = self.dragon
    d:ClearAllPoints()
    -- The art wraps round the portrait's right; on a portrait left of its bars it's mirrored.
    if self.side == "left" then
        d:SetPoint("CENTER", self.frame, "CENTER", -dx, -dy)
        d:SetTexCoord(1, 0, 0, 1)
    else
        d:SetPoint("CENTER", self.frame, "CENTER", dx, -dy)
        d:SetTexCoord(0, 1, 0, 1)
    end
    d:SetSize(DRAGON.size * s, DRAGON.size * s)
end

-- How far the dragon reaches from the portrait's centre towards the bars, in units.
function Portrait:DragonNear()
    return DRAGON.near * self:DragonScale()
end

-- classification: UnitClassification's (it may be secret; then there's no dragon). Returns
-- whether a dragon shows.
function Portrait:SetDragon(classification)
    local art = DRAGON_ART[Safe(classification) or ""]
    if art then self.dragon:SetTexture(MEDIA_DRAGON .. art .. ".tga") end
    self.dragon:SetShown(art ~= nil)
    return art ~= nil
end

------------------------------------------------------------------------------
-- Hit text: what Blizzard's player and pet frames show over the portrait (UNIT_COMBAT), here for
-- any frame that wants it. The amount can be secret: then it's printed engine-side and the
-- tests on it are skipped.
------------------------------------------------------------------------------

local FADE_IN, HOLD, FADE_OUT = 0.2, 0.7, 0.3
local WORDS = { IMMUNE = "IMMUNE", MISS = "MISS", DODGE = "DODGE", PARRY = "PARRY", BLOCK = "BLOCK",
    EVADE = "EVADE", RESIST = "RESIST", DEFLECT = "DEFLECT", ABSORB = "ABSORB", REFLECT = "REFLECT",
    INTERRUPT = "INTERRUPT" }

local function Word(key)
    local global = WORDS[key] and _G[WORDS[key]]
    return global or key
end

local function Amount(fs, amount)
    if issecret(amount) then
        pcall(fs.SetFormattedText, fs, "%d", amount)
    else
        fs:SetText(BreakUpLargeNumbers and BreakUpLargeNumbers(amount or 0) or tostring(amount or 0))
    end
end

function Portrait:CombatEvent(event, flags, amount, school)
    event, flags, school = Safe(event), Safe(flags), Safe(school)
    if not event then return end
    local fs, height = self.hit, self.hitHeight or 16
    local r, g, b = 1, 1, 1
    local scale = 1
    if event == "WOUND" then
        local zero = not issecret(amount) and amount == 0
        if not zero then
            if flags == "CRITICAL" or flags == "CRUSHING" then
                scale = 1.5
            elseif flags == "GLANCING" then
                scale = 0.75
            end
            if school and Enum.Damageclass and school ~= Enum.Damageclass.MaskPhysical then r, g, b = 1, 1, 0 end
            Amount(fs, amount)
        elseif flags == "ABSORB" or flags == "BLOCK" or flags == "RESIST" then
            scale = 0.75
            fs:SetText(Word(flags))
        else
            fs:SetText(Word("MISS"))
        end
    elseif event == "HEAL" or event == "ENERGIZE" then
        if event == "HEAL" then r, g, b = 0, 1, 0 else r, g, b = 0.41, 0.8, 0.94 end
        if flags == "CRITICAL" then scale = 1.5 end
        Amount(fs, amount)
    elseif event == "IMMUNE" or event == "BLOCK" then
        scale = event == "IMMUNE" and 0.5 or 0.75
        fs:SetText(Word(event))
    else
        fs:SetText(Word(event))
    end
    pcall(fs.SetTextHeight, fs, height * scale)
    fs:SetTextColor(r, g, b)
    fs:SetAlpha(0)
    fs:Show()
    self.hitStart = GetTime()
end

function Portrait:FadeHit()
    local fs = self.hit
    if not (self.hitStart and fs:IsShown()) then return end
    local t = GetTime() - self.hitStart
    if t < FADE_IN then
        fs:SetAlpha(t / FADE_IN)
    elseif t < FADE_IN + HOLD then
        fs:SetAlpha(1)
    elseif t < FADE_IN + HOLD + FADE_OUT then
        fs:SetAlpha(1 - (t - FADE_IN - HOLD) / FADE_OUT)
    else
        fs:Hide()
        self.hitStart = nil
    end
end
