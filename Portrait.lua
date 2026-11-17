local _, ns = ...

-- The round portrait beside a frame's bars, and what goes on it: a ring in the look's style, the
-- level badge on its lower outer edge, the elite / rare dragon (target and focus) and the hit text
-- (Blizzard's combat feedback). The picture is masked round; a 3D model can't be, so it sits in the
-- square inside the circle.

local issecret, Safe = FrogLib.issecret, FrogLib.Safe
local MEDIA = "Interface\\AddOns\\FrogFrames\\Media\\"
local DISC = MEDIA .. "CircleMask.tga"
-- Classic's ring: a near-black outline, a dark metal band lit from above, a thin dark-gold line and
-- a black inner edge shadowing the picture.
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

-- The dragons (FrogPlates' cut of the classic target frame's elite art, 128x128 texels): the
-- portrait's hole in them, the ring's outside edge, and how far the art reaches towards the bars.
local DRAGON = { size = 128, holeX = 51.5, holeY = 58.5, ringOut = 35, near = 44.5 }
local DRAGON_ART = { elite = MEDIA .. "DragonElite.tga", worldboss = MEDIA .. "DragonElite.tga",
    rare = MEDIA .. "DragonRare.tga", rareelite = MEDIA .. "DragonRareElite.tga" }

local Portrait = {}
Portrait.__index = Portrait

local function Disc(parent, layer, sublevel)
    local disc = parent:CreateTexture(nil, layer, nil, sublevel)
    disc:SetTexture(DISC)
    return disc
end

-- level: its frame level (before its parts are made, so they stack above it).
function ns.CreatePortrait(parent, level)
    local portrait = setmetatable({}, Portrait)
    local frame = CreateFrame("Frame", nil, parent)
    if level then frame:SetFrameLevel(level) end
    portrait.frame = frame
    -- A soft halo round the ring (the frame's glow), under everything; then the discs that make the
    -- modern and forever rings, and a dark disc the picture sits on.
    portrait.halo = frame:CreateTexture(nil, "BACKGROUND", nil, -8)
    portrait.halo:SetTexture(MEDIA .. "Halo.tga")
    portrait.halo:SetBlendMode("ADD")
    portrait.halo:SetPoint("CENTER")
    portrait.halo:Hide()
    portrait.outer = Disc(frame, "BACKGROUND", -6)
    portrait.rim = Disc(frame, "BACKGROUND", -5)
    portrait.inner = Disc(frame, "BACKGROUND", -4)
    portrait.back = Disc(frame, "BACKGROUND", -3)
    portrait.back:SetVertexColor(0.05, 0.05, 0.05, 1)
    for _, disc in ipairs({ portrait.outer, portrait.rim, portrait.inner, portrait.back }) do disc:SetPoint("CENTER") end

    portrait.pic = frame:CreateTexture(nil, "ARTWORK")
    portrait.pic:SetPoint("CENTER")
    portrait.mask = frame:CreateMaskTexture()
    portrait.mask:SetTexture(DISC, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    portrait.mask:SetAllPoints(portrait.pic)
    portrait.pic:AddMaskTexture(portrait.mask)

    -- Above the picture (and the 3D model, made the first time it's wanted: frame level + 1): the classic
    -- ring, the dragon, the badge and the hit text.
    portrait.top = CreateFrame("Frame", nil, frame)
    portrait.top:SetAllPoints()
    portrait.top:SetFrameLevel(frame:GetFrameLevel() + 3)
    portrait.ring = portrait.top:CreateTexture(nil, "ARTWORK")
    portrait.ring:SetTexture(RING)
    portrait.ring:SetAllPoints(frame)
    portrait.dragon = portrait.top:CreateTexture(nil, "BORDER")
    portrait.dragon:Hide()
    -- The level badge: Badge.tga in the classic look, a disc ring in the others.
    portrait.badge = CreateFrame("Frame", nil, portrait.top)
    portrait.badge:SetFrameLevel(portrait.top:GetFrameLevel() + 1)
    portrait.badgeArt = portrait.badge:CreateTexture(nil, "ARTWORK")
    portrait.badgeArt:SetAllPoints()
    portrait.badgeOuter = Disc(portrait.badge, "BORDER", 0)
    portrait.badgeOuter:SetAllPoints()
    portrait.badgeInner = Disc(portrait.badge, "BORDER", 1)
    portrait.badgeInner:SetPoint("CENTER")
    portrait.level = portrait.badge:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    portrait.level:SetPoint("CENTER", 0, 0)
    portrait.level:SetShadowOffset(1, -1)
    portrait.level:SetShadowColor(0, 0, 0, 1)
    return portrait
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
    local pixel = FrogLib.Pixel(self.frame)
    if look == "vanilla" then return 0 end
    if look == "classic" then return size / 2 * (1 - HOLE) end
    if look == "forever" then return 3 * (ns.db.frameThickness or 1) * pixel end
    return 2 * pixel
end

-- size: the outer diameter in units; side "left"/"right": which side of the bars; shiftX, shiftY:
-- the level badge's offset (the frame's settings).
function Portrait:Layout(size, side, shiftX, shiftY)
    local frame, look = self.frame, self:Look()
    self.size, self.side = size, side
    frame:SetSize(size, size)
    local pixel = FrogLib.Pixel(frame)
    local hole = size - 2 * self:Ring()
    -- Halo.tga's glow starts at 70% of its size and reaches 8 pixels or so past the ring.
    local halo = math.max(size / 0.7, size + 16 * pixel)
    self.halo:SetSize(halo, halo)
    -- The classic ring's black inner edge goes over the picture's edge; the disc rings are
    -- behind it, so there it's exactly the hole.
    local pic = look == "classic" and hole + 2 * pixel or hole
    self.pic:SetSize(pic, pic)
    self.back:SetSize(pic, pic)
    -- The model fills the square inside the circle.
    local inner = ns.Snap(hole * 0.72, pixel)
    self.modelSize = inner
    if self.model then self.model:SetSize(inner, inner) end

    self.ring:SetShown(look == "classic")
    local thick = (ns.db.frameThickness or 1) * pixel
    if look == "modern" then
        -- A plain dark ring with a black outline.
        self.outer:SetSize(size, size)
        self.outer:SetVertexColor(0, 0, 0, 1)
        self.rim:SetSize(size - 2 * pixel, size - 2 * pixel)
        self.rim:SetVertexColor(0.13, 0.13, 0.13, 1)
        self.outer:Show()
        self.rim:Show()
        self.inner:Hide()
    elseif look == "forever" then
        -- The Forever frame's three lines: a dark outline, a light metallic rim brighter at the
        -- top, and a dark inner line.
        self.outer:SetSize(size, size)
        self.outer:SetVertexColor(0.02, 0.02, 0.02, 1)
        self.rim:SetSize(size - 2 * thick, size - 2 * thick)
        self.rim:SetVertexColor(1, 1, 1, 1)
        if self.rim.SetGradient and CreateColor then
            pcall(self.rim.SetGradient, self.rim, "VERTICAL", CreateColor(0.42, 0.42, 0.46, 1), CreateColor(0.80, 0.80, 0.84, 1))
        end
        self.inner:SetSize(size - 4 * thick, size - 4 * thick)
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
    local badgeSize = ns.Snap(size * BADGE_SIZE, pixel)
    local out = side == "left" and -1 or 1
    self.badge:SetSize(badgeSize, badgeSize)
    self.badge:ClearAllPoints()
    self.badge:SetPoint("CENTER", frame, "CENTER", out * size * BADGE_X + (shiftX or 0), size * BADGE_Y + (shiftY or 0))
    self.badgeArt:SetTexture(BADGE)
    self.badgeArt:SetShown(look == "classic")
    self.badgeOuter:SetShown(look ~= "classic" and look ~= "vanilla")
    self.badgeInner:SetShown(look ~= "classic" and look ~= "vanilla")
    if look == "forever" then
        self.badgeOuter:SetVertexColor(0.62, 0.62, 0.66, 1)
    else
        self.badgeOuter:SetVertexColor(0, 0, 0, 1)
    end
    local line = look == "forever" and thick or pixel
    self.badgeInner:SetSize(badgeSize - 2 * line, badgeSize - 2 * line)
    self.badgeInner:SetVertexColor(0.06, 0.06, 0.06, 1)
    local levelSize = math.max(8, math.floor(badgeSize * 0.5 + 0.5))
    ns.SetFont(self.level, ns.db.font, levelSize, ns.db.outline)

    self:PlaceDragon()
    self.hitHeight = math.max(10, math.floor(size * 0.3))
    if self.hit then ns.SetFont(self.hit, ns.db.font, self.hitHeight, ns.db.outline) end
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
    local model = self.model
    model:ClearModel()
    model:SetUnit(unit)
    model:SetPortraitZoom(1)
    model:SetCamDistanceScale(1)
    model:SetPosition(0, 0, 0)
end

-- The 3D model, made the first time it's wanted (it's off to start).
function Portrait:BuildModel()
    local model = CreateFrame("PlayerModel", nil, self.frame)
    model:SetPoint("CENTER")
    model:SetSize(self.modelSize, self.modelSize)
    model:Hide()
    -- A model shown again starts blank: give it its unit back.
    model:SetScript("OnShow", function() if self.modelUnit then self:SetModel(self.modelUnit) end end)
    self.model = model
    return model
end

-- mode "3d", "class" or "2d"; unit nil for a sample (your own picture).
function Portrait:Set(unit, mode)
    local who = unit or "player"
    if mode == "3d" then
        -- Out of sight the game has no model to draw: the 2D picture instead.
        local visible = Safe(UnitIsVisible(who))
        if visible ~= false and Safe(UnitIsConnected(who)) ~= false then
            local model = self.model or self:BuildModel()
            self.pic:Hide()
            self.modelUnit = who
            if not model:IsShown() then
                model:Show() -- OnShow sets the unit
            else
                self:SetModel(who)
            end
            return
        end
    end
    self.modelUnit = nil
    if self.model then self.model:Hide() end
    self.pic:Show()
    if mode == "class" and Safe(UnitIsPlayer(who)) then
        local _, class = UnitClass(who)
        class = Safe(class)
        local coords = class and ((CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[class]) or CLASS_COORDS[class])
        if coords then
            self.pic:SetTexture(CLASS_ICONS)
            -- A little zoomed in: the icons have a rim of their own, which our ring replaces.
            local width, height = coords[2] - coords[1], coords[4] - coords[3]
            self.pic:SetTexCoord(coords[1] + width * 0.06, coords[2] - width * 0.06, coords[3] + height * 0.06,
                coords[4] - height * 0.06)
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
    local scale = self:DragonScale()
    local shiftX, shiftY = (DRAGON.size / 2 - DRAGON.holeX) * scale, (DRAGON.size / 2 - DRAGON.holeY) * scale
    local dragon = self.dragon
    dragon:ClearAllPoints()
    -- The art wraps round the portrait's right; on a portrait left of its bars it's mirrored.
    if self.side == "left" then
        dragon:SetPoint("CENTER", self.frame, "CENTER", -shiftX, -shiftY)
        dragon:SetTexCoord(1, 0, 0, 1)
    else
        dragon:SetPoint("CENTER", self.frame, "CENTER", shiftX, -shiftY)
        dragon:SetTexCoord(0, 1, 0, 1)
    end
    dragon:SetSize(DRAGON.size * scale, DRAGON.size * scale)
end

-- How far the dragon reaches from the portrait's centre towards the bars, in units.
function Portrait:DragonNear()
    return DRAGON.near * self:DragonScale()
end

-- classification: UnitClassification's (it may be secret; then there's no dragon). Returns
-- whether a dragon shows. Only a change is drawn (this runs on every update).
function Portrait:SetDragon(classification)
    local art = DRAGON_ART[Safe(classification) or ""]
    if art ~= self.dragonArt then
        self.dragonArt = art
        if art then self.dragon:SetTexture(art) end
        self.dragon:SetShown(art ~= nil)
    end
    return art ~= nil
end

------------------------------------------------------------------------------
-- Hit text: what Blizzard's player and pet frames show over the portrait (UNIT_COMBAT), here for
-- any frame that wants it. The amount is secret (always, since Forever 1.60.1.70938): then it's
-- printed engine-side and the flags stand in for the tests on it.
------------------------------------------------------------------------------

local FADE_IN, HOLD, FADE_OUT = 0.2, 0.7, 0.3
local WORDS = { IMMUNE = "IMMUNE", MISS = "MISS", DODGE = "DODGE", PARRY = "PARRY", BLOCK = "BLOCK",
    EVADE = "EVADE", RESIST = "RESIST", DEFLECT = "DEFLECT", ABSORB = "ABSORB", REFLECT = "REFLECT",
    INTERRUPT = "INTERRUPT" }

local function Word(key)
    local global = WORDS[key] and _G[WORDS[key]]
    return global or key
end

local function Amount(hit, amount)
    if issecret(amount) then
        pcall(hit.SetFormattedText, hit, "%d", amount)
    else
        hit:SetText(BreakUpLargeNumbers and BreakUpLargeNumbers(amount or 0) or tostring(amount or 0))
    end
end

-- A partly blocked hit: the damage in Blizzard's "%s (Block)", as %d so a secret amount goes the
-- engine-side way Amount's does; if the game won't take it, the bare number.
local BLOCKED = COMBAT_TEXT_BLOCK_REDUCED and (COMBAT_TEXT_BLOCK_REDUCED:gsub("%%s", "%%d"))

local function Blocked(hit, amount)
    if not (BLOCKED and pcall(hit.SetFormattedText, hit, BLOCKED, amount)) then Amount(hit, amount) end
end

-- The text, and its fade (run only while one is showing), made with the first hit (hit text is off to start).
function Portrait:BuildHit()
    local hit = self.top:CreateFontString(nil, "OVERLAY", "NumberFontNormalHuge")
    hit:SetPoint("CENTER")
    hit:Hide()
    if self.hitHeight then ns.SetFont(hit, ns.db.font, self.hitHeight, ns.db.outline) end
    self.hit = hit
    self.hitDriver = CreateFrame("Frame", nil, self.top)
    self.hitDriver:Hide()
    self.hitDriver:SetScript("OnUpdate", function() self:FadeHit() end)
    return hit
end

function Portrait:CombatEvent(event, flags, amount, school)
    event, flags, school = Safe(event), Safe(flags), Safe(school)
    if not event then return end
    local hit, height = self.hit or self:BuildHit(), self.hitHeight or 16
    local r, g, b = 1, 1, 1
    local scale = 1
    if event == "WOUND" then
        -- No damage: a secret amount can't be tested for 0, so there an ABSORB or BLOCK flag says it
        -- (a part block is BLOCK_REDUCED). The hit that breaks a shield may read Absorb too, but that's
        -- one hit a shield against every one it soaks. Not RESIST: partial resists are common.
        local zero
        if issecret(amount) then
            zero = flags == "ABSORB" or flags == "BLOCK"
        else
            zero = amount == 0
        end
        if not zero then
            if flags == "CRITICAL" or flags == "CRUSHING" then
                scale = 1.5
            elseif flags == "GLANCING" then
                scale = 0.75
            end
            if school and Enum.Damageclass and school ~= Enum.Damageclass.MaskPhysical then r, g, b = 1, 1, 0 end
            if flags == "BLOCK_REDUCED" then Blocked(hit, amount) else Amount(hit, amount) end
        elseif flags == "ABSORB" or flags == "BLOCK" or flags == "RESIST" then
            scale = 0.75
            hit:SetText(Word(flags))
        else
            hit:SetText(Word("MISS"))
        end
    elseif event == "HEAL" or event == "ENERGIZE" then
        if event == "HEAL" then r, g, b = 0, 1, 0 else r, g, b = 0.41, 0.8, 0.94 end
        if flags == "CRITICAL" then scale = 1.5 end
        Amount(hit, amount)
    elseif event == "IMMUNE" or event == "BLOCK" then
        scale = event == "IMMUNE" and 0.5 or 0.75
        hit:SetText(Word(event))
    else
        hit:SetText(Word(event))
    end
    pcall(hit.SetTextHeight, hit, height * scale)
    hit:SetTextColor(r, g, b)
    hit:SetAlpha(0)
    self.hitAlpha = 0
    hit:Show()
    self.hitStart = GetTime()
    self.hitDriver:Show()
end

-- Only this shows and hides the text; its opacity is written only when it changes (not through the hold).
function Portrait:FadeHit()
    local hit = self.hit
    if not self.hitStart then
        self.hitDriver:Hide()
        return
    end
    local since = GetTime() - self.hitStart
    local alpha
    if since < FADE_IN then
        alpha = since / FADE_IN
    elseif since < FADE_IN + HOLD then
        alpha = 1
    elseif since < FADE_IN + HOLD + FADE_OUT then
        alpha = 1 - (since - FADE_IN - HOLD) / FADE_OUT
    end
    if alpha then
        if alpha ~= self.hitAlpha then
            hit:SetAlpha(alpha)
            self.hitAlpha = alpha
        end
    else
        hit:Hide()
        self.hitStart = nil
        self.hitDriver:Hide()
    end
end
