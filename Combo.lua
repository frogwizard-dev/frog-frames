local _, ns = ...
local Combo = {}
ns.Combo = Combo

------------------------------------------------------------------------------
-- Combo points: a row of pips under (or over: combo.side) the target's bars (or yours: combo.on),
-- each a little bar in the frames' look, from Personal Resource Tweaks' Combo.lua. The count may be
-- secret, so each pip is a status bar from i - 1 to i handed the count (FrogLib.Combo); the colour
-- at max is a second bar on every pip, from max - 1 to max.
------------------------------------------------------------------------------

local ComboKit = FrogLib.Combo
local issecret = FrogLib.issecret

local holder
local pips = {}
local count = 0
-- Kept here rather than asked of the frames: whether the pips and the vanilla points show, and the count last
-- drawn (a plain one: the same count again isn't drawn again; a secret one always is).
local holderShown, orbsShown, lastPoints = false, false, nil

-- Whether this character has combo points at all (the row's room under the bars is kept for
-- them even out of cat form, so nothing below jumps with every shift). The class never changes:
-- asked until it can be read, then kept.
local hasPoints
local function HasPoints()
    if hasPoints == nil then
        if not ns.PlayerClass() then return false end
        hasPoints = ComboKit.Has()
    end
    return hasPoints
end

-- Whether the row goes on this kind of frame ("player" or "target").
function Combo:On(kind)
    local settings = ns.db and ns.db.combo
    return settings ~= nil and settings.enabled and settings.on == kind and HasPoints() and ns.db.units[kind].enabled
end

-- Rogues always; druids in cat form (the form with energy), or anyone with points while unlocked.
local function Wanted()
    return not ns.db.locked or ComboKit.Active()
end

local MaxPoints = ComboKit.Max

-- Your points on your target, as the target frame counts them. May be secret: widgets only.
local function Points()
    if not ns.db.locked then return 3 end -- a sample, while unlocked
    return ComboKit.Points()
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

local function ShowHolder(on)
    on = on and true or false
    if holderShown == on then return end
    holderShown, lastPoints = on, nil
    holder:SetShown(on)
end

------------------------------------------------------------------------------
-- On a vanilla frame (Unit.lua): 1.x's own combo points round its portrait (ComboFrame.xml's places:
-- each point's top right from its combo frame, 44 in from the frame's right end and 9 down). Each a
-- socket (Interface\ComboFrame\ComboPoint, its first 0.375, 12 x 16) with the lit point in it.
------------------------------------------------------------------------------

local ORB = "Interface\\ComboFrame\\ComboPoint"
local ORBS = { { -39, 7 }, { -26.5, 8 }, { -14, 7 }, { -2.5, 1.5 }, { 6.5, -7 } }
local ORB_FRAME_X, ORB_FRAME_Y = 232 - 44, -9
local orbs = {}

local function Vanilla(owner)
    return owner and owner.vanillaShown or false
end

local function MakeOrb(i, owner)
    local orb = CreateFrame("Frame", nil, owner.content)
    orb:SetSize(12, 12)
    orb.socket = orb:CreateTexture(nil, "BACKGROUND")
    orb.socket:SetTexture(ORB)
    orb.socket:SetTexCoord(0, 0.375, 0, 1)
    orb.socket:SetSize(12, 16)
    orb.socket:SetPoint("TOPLEFT")
    -- The lit point: the next 0.1875 of the file, 8 x 16, 2 in; lit through FrogLib.Combo.Lit.
    orb.lit = orb:CreateTexture(nil, "ARTWORK")
    orb.lit:SetTexture(ORB)
    orb.lit:SetTexCoord(0.375, 0.5625, 0, 1)
    orb.lit:SetSize(8, 16)
    orb.lit:SetPoint("TOPLEFT", 2, 0)
    orbs[i] = orb
    return orb
end

local function HideOrbs()
    if not orbsShown then return end
    for _, orb in pairs(orbs) do orb:Hide() end
    orbsShown, lastPoints = false, nil
end

local function LayoutOrbs(owner)
    local shown = Wanted()
    for i = 1, #ORBS do
        local orb = orbs[i] or MakeOrb(i, owner)
        orb:SetParent(owner.content)
        orb:SetFrameLevel(owner.vanillaArt:GetFrameLevel() + 1)
        local right, top = ORB_FRAME_X + ORBS[i][1], ORB_FRAME_Y + ORBS[i][2]
        orb:ClearAllPoints()
        orb:SetPoint("CENTER", owner.root, "TOPLEFT", owner:VX(right - 6), top - 6)
        orb:SetShown(i <= count and shown)
    end
    orbsShown, lastPoints = count >= 1 and shown, nil
end

-- How tall the pips are (inside their frames), in the owner frame's units; none on a vanilla
-- frame (its points go round the portrait).
function Combo:PipHeight(owner)
    if Vanilla(owner) then return 0 end
    return ns.Snap(ns.db.combo.height, owner.geo.pixel)
end

function Combo:Layout()
    local settings = ns.db.combo
    local owner = ns.frames and ns.frames[settings.on]
    if not (holder and count > 0 and owner and owner.geo and owner.comboY and self:On(settings.on)) then
        if holder then ShowHolder(false) end
        HideOrbs()
        return
    end
    if Vanilla(owner) then
        ShowHolder(false)
        LayoutOrbs(owner)
        self:Update()
        return
    end
    HideOrbs()
    local geo = owner.geo
    if holder.ffOwner ~= owner then
        holder.ffOwner = owner
        holder:SetParent(owner.content)
        holder:SetFrameLevel(owner.stack:GetFrameLevel() + 1)
    end
    local pixel = geo.pixel
    local reachPixels = math.floor(geo.reach / pixel + 0.5)
    local step = settings.spacing + 2 * reachPixels -- from one pip's edge to the next one's, in pixels
    local full = math.floor((owner.aroundWidth or geo.width) / pixel + 0.5)
    local height = ns.Snap(settings.height, pixel)
    holder:ClearAllPoints()
    -- Above or below the bars (Unit.lua), nudged by combo.x / combo.y.
    holder:SetPoint("TOPLEFT", owner.stack, "TOPLEFT", (owner.aroundX or 0) + (settings.x or 0), owner.comboY + (settings.y or 0))
    -- The pips themselves only when what they're made from has changed (this runs on every layout of the frame).
    local color, maxColor, db = settings.color, settings.maxColor, ns.db
    if ns.Changed(holder, count, full, step, height, pixel, db.look, db.texture, db.frameThickness,
        color.r, color.g, color.b, maxColor.r, maxColor.g, maxColor.b) then
        local room = full - (count - 1) * step
        local each = math.max(1, math.floor(room / count))
        local extra = math.max(0, room - each * count)
        holder:SetSize(full * pixel, height)
        local x = 0
        for i = 1, count do
            local pip = pips[i]
            local pipWidth = each + (i <= extra and 1 or 0)
            pip:ClearAllPoints()
            pip:SetPoint("TOPLEFT", holder, "TOPLEFT", x * pixel, 0)
            pip:SetSize(pipWidth * pixel, height)
            pip.box:Apply()
            pip.fill:ApplyTexture()
            pip.maxFill:ApplyTexture()
            pip.fill:SetColor(color.r, color.g, color.b)
            pip.maxFill:SetColor(maxColor.r, maxColor.g, maxColor.b)
            pip.maxFill.bar:SetMinMaxValues(count - 1, count)
            x = x + pipWidth + step
        end
        lastPoints = nil
    end
    ShowHolder(Wanted())
    self:Update()
end

-- Lights the pips: the count straight into each one's status bar.
function Combo:Update()
    if not (orbsShown or holderShown) then return end
    local points = Points()
    if issecret(points) then
        lastPoints = nil
    elseif points == lastPoints then
        return
    else
        lastPoints = points
    end
    if orbsShown then
        for i = 1, math.min(count, #ORBS) do
            local orb = orbs[i]
            if not pcall(orb.lit.SetAlpha, orb.lit, ComboKit.Lit(points, i, count)) then orb.lit:SetAlpha(0) end
        end
    end
    if holderShown then
        for i = 1, count do
            pips[i].fill.bar:SetValue(points)
            pips[i].maxFill.bar:SetValue(points)
        end
    end
end

function Combo:Apply()
    -- Nothing is made, nor listened to, until combo points are first switched on.
    if not (HasPoints() and (ns.db.combo.enabled or holder)) then return end
    if not holder then
        holder = CreateFrame("Frame", nil, UIParent)
        holder:Hide()
        -- Power events come two to a change (FrogLib's watch hears both kinds): the pips are drawn once, after
        -- them, before the screen is.
        local updater = CreateFrame("Frame")
        updater:Hide()
        updater:SetScript("OnUpdate", function(self)
            self:Hide()
            Combo:Update()
        end)
        -- A form or the max changed: whether it shows, and how many pips.
        ComboKit.Watch(function() updater:Show() end, function() Combo:Apply() end)
    end
    count = MaxPoints()
    for i = 1, count do
        local pip = pips[i] or MakePip(i)
        pip:Show()
    end
    for i = count + 1, #pips do pips[i]:Hide() end
    lastPoints = nil
    self:Layout()
end
