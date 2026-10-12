local _, ns = ...
local Combo = {}
ns.Combo = Combo

------------------------------------------------------------------------------
-- Combo points: a row of pips under (or over: combo.side) the target's bars (or yours: combo.on),
-- each pip a little bar in the frames' look.
-- From PersonalResourceTweaks' Combo.lua. Forever has no class resource bar of its own, so the
-- pips are drawn from the same numbers Blizzard's target frame uses: GetComboPoints("player",
-- "target") out of UnitPowerMax's combo points. Rogues always; druids only in cat form.
--
-- The count may be a secret value, so it's never compared: each pip is a status bar running
-- from i - 1 to i, handed the count as its value, which the game fills (count >= i) or leaves
-- empty (count <= i - 1). The colour at max works the same way: a second bar on every pip,
-- from max - 1 to max, fills only when you have them all.
------------------------------------------------------------------------------

local C = FrogLib.Combo -- who has them, how many, the count (FrogLib's Combo.lua)

local holder
local pips = {}
local count = 0

-- Whether this character has combo points at all (the row's room under the bars is kept for
-- them even out of cat form, so nothing below jumps with every shift).
local HasPoints = C.Has

-- Whether the row goes on this kind of frame ("player" or "target").
function Combo:On(kind)
    local cfg = ns.db and ns.db.combo
    return cfg ~= nil and cfg.enabled and cfg.on == kind and HasPoints() and ns.db.units[kind].enabled
end

-- Rogues always; druids in cat form (the form with energy), or anyone with points while unlocked.
local function Wanted()
    return not ns.db.locked or C.Active()
end

local MaxPoints = C.Max

-- Your points on your target, as the target frame counts them. May be secret: widgets only.
local function Points()
    if not ns.db.locked then return 3 end -- a sample, while unlocked
    return C.Points()
end

local function MakePip(i)
    local pip = CreateFrame("Frame", nil, holder)
    pip.box = ns.CreateBox(pip)
    pip.fill = ns.CreateBar(pip)
    pip.fill.bar:SetAllPoints()
    pip.fill.bar:SetMinMaxValues(i - 1, i)
    pip.maxFill = ns.CreateBar(pip)
    pip.maxFill.bar:SetAllPoints()
    pip.maxFill.track:Hide()
    pip.maxFill.bar:SetFrameLevel(pip.fill.bar:GetFrameLevel() + 1)
    pips[i] = pip
    return pip
end

------------------------------------------------------------------------------
-- On a vanilla frame (Unit.lua): 1.x's own combo points instead, round its portrait. Each a
-- socket (Interface\ComboFrame\ComboPoint, its first 0.375 drawn 12 x 16) with the lit
-- point in it (the next 0.1875, 8 x 16, 2 in), lit through FrogLib.Combo.Lit (the count may be
-- secret). Where 1.x put them (ComboFrame.xml): each point's top right from its combo frame,
-- which sits 44 in from the frame's right end and 9 down.
------------------------------------------------------------------------------

local ORB = "Interface\\ComboFrame\\ComboPoint"
local ORBS = { { -39, 7 }, { -26.5, 8 }, { -14, 7 }, { -2.5, 1.5 }, { 6.5, -7 } }
local ORB_FRAME_X, ORB_FRAME_Y = 232 - 44, -9
local orbs = {}

local function Vanilla(owner)
    return owner and owner.vanillaArt and owner.vanillaArt:IsShown() or false
end

local function MakeOrb(i, owner)
    local o = CreateFrame("Frame", nil, owner.content)
    o:SetSize(12, 12)
    o.socket = o:CreateTexture(nil, "BACKGROUND")
    o.socket:SetTexture(ORB)
    o.socket:SetTexCoord(0, 0.375, 0, 1)
    o.socket:SetSize(12, 16)
    o.socket:SetPoint("TOPLEFT")
    o.lit = o:CreateTexture(nil, "ARTWORK")
    o.lit:SetTexture(ORB)
    o.lit:SetTexCoord(0.375, 0.5625, 0, 1)
    o.lit:SetSize(8, 16)
    o.lit:SetPoint("TOPLEFT", 2, 0)
    orbs[i] = o
    return o
end

local function HideOrbs()
    for _, o in pairs(orbs) do o:Hide() end
end

local function LayoutOrbs(owner)
    for i = 1, #ORBS do
        local o = orbs[i] or MakeOrb(i, owner)
        o:SetParent(owner.content)
        o:SetFrameLevel(owner.vanillaArt:GetFrameLevel() + 1)
        local right, top = ORB_FRAME_X + ORBS[i][1], ORB_FRAME_Y + ORBS[i][2]
        o:ClearAllPoints()
        o:SetPoint("CENTER", owner.root, "TOPLEFT", owner:VX(right - 6), top - 6)
        o:SetShown(i <= count and Wanted())
    end
end

-- How tall the pips are (inside their frames), in the owner frame's units; none on a vanilla
-- frame (its points go round the portrait).
function Combo:PipHeight(owner)
    if Vanilla(owner) then return 0 end
    return ns.Snap(ns.db.combo.height, owner.geo.px)
end

function Combo:Layout()
    local cfg = ns.db.combo
    local owner = ns.frames and ns.frames[cfg.on]
    if not (holder and count > 0 and owner and owner.geo and owner.comboY and self:On(cfg.on)) then
        if holder then holder:Hide() end
        HideOrbs()
        return
    end
    if Vanilla(owner) then
        holder:Hide()
        LayoutOrbs(owner)
        self:Update()
        return
    end
    HideOrbs()
    local g = owner.geo
    holder:SetParent(owner.content)
    holder:SetFrameLevel(owner.stack:GetFrameLevel() + 1)
    local px = g.px
    local reachPx = math.floor(g.reach / px + 0.5)
    local step = cfg.spacing + 2 * reachPx -- from one pip's edge to the next one's, in pixels
    local full = math.floor((owner.aroundW or g.W) / px + 0.5)
    local room = full - (count - 1) * step
    local each = math.max(1, math.floor(room / count))
    local extra = math.max(0, room - each * count)
    local h = ns.Snap(cfg.height, px)
    holder:ClearAllPoints()
    -- Above or below the bars (Unit.lua), nudged by combo.x / combo.y.
    holder:SetPoint("TOPLEFT", owner.stack, "TOPLEFT", (owner.aroundX or 0) + (cfg.x or 0), owner.comboY + (cfg.y or 0))
    holder:SetSize(full * px, h)
    local x = 0
    for i = 1, count do
        local pip = pips[i]
        local w = each + (i <= extra and 1 or 0)
        pip:ClearAllPoints()
        pip:SetPoint("TOPLEFT", holder, "TOPLEFT", x * px, 0)
        pip:SetSize(w * px, h)
        pip.box:Apply()
        pip.fill:ApplyTexture()
        pip.maxFill:ApplyTexture()
        pip.fill:SetColor(cfg.color.r, cfg.color.g, cfg.color.b)
        pip.maxFill:SetColor(cfg.maxColor.r, cfg.maxColor.g, cfg.maxColor.b)
        pip.maxFill.bar:SetMinMaxValues(count - 1, count)
        x = x + w + step
    end
    holder:SetShown(Wanted())
    self:Update()
end

-- Lights the pips: the count straight into each one's status bar.
function Combo:Update()
    if orbs[1] and orbs[1]:IsShown() then
        local points = Points()
        for i = 1, math.min(count, #ORBS) do
            local o = orbs[i]
            if not pcall(o.lit.SetAlpha, o.lit, C.Lit(points, i, count)) then o.lit:SetAlpha(0) end
        end
    end
    if not (holder and holder:IsShown()) then return end
    local points = Points()
    for i = 1, count do
        pips[i].fill.bar:SetValue(points)
        pips[i].maxFill.bar:SetValue(points)
    end
end

function Combo:Apply()
    if not HasPoints() then return end
    if not holder then holder = CreateFrame("Frame", nil, UIParent) end
    count = MaxPoints()
    for i = 1, count do
        local pip = pips[i] or MakePip(i)
        pip:Show()
    end
    for i = count + 1, #pips do pips[i]:Hide() end
    self:Layout()
end

function Combo:Init()
    if not HasPoints() then return end
    -- A form or the max changed: whether it shows, and how many pips.
    C.Watch(function() Combo:Update() end, function() Combo:Apply() end)
end
