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

local issecret, Safe = ns.issecret, ns.Safe
local POINTS = (Enum.PowerType and Enum.PowerType.ComboPoints) or 4
local MAX_PIPS = 10

local holder
local pips = {}
local count = 0

-- Whether this character has combo points at all (the row's room under the bars is kept for
-- them even out of cat form, so nothing below jumps with every shift).
local function HasPoints()
    local _, class = UnitClass("player")
    return class == "ROGUE" or class == "DRUID"
end

-- Whether the row goes on this kind of frame ("player" or "target").
function Combo:On(kind)
    local cfg = ns.db and ns.db.combo
    return cfg ~= nil and cfg.enabled and cfg.on == kind and HasPoints() and ns.db.units[kind].enabled
end

-- Rogues always; druids in cat form (the form with energy), or anyone with points while unlocked.
local function Wanted()
    local _, class = UnitClass("player")
    if class == "ROGUE" or not ns.db.locked then return true end
    local _, token = UnitPowerType("player")
    return Safe(token) == "ENERGY"
end

local function MaxPoints()
    local max = UnitPowerMax("player", POINTS)
    if issecret(max) or not max or max <= 0 then return 5 end
    return math.min(max, MAX_PIPS)
end

-- Your points on your target, as the target frame counts them. May be secret: widgets only.
local function Points()
    if not ns.db.locked then return 3 end -- a sample, while unlocked
    if GetComboPoints then return GetComboPoints("player", "target") end
    return UnitPower("player", POINTS)
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

-- How tall the pips are (inside their frames), in the owner frame's units.
function Combo:PipHeight(owner)
    return ns.Snap(ns.db.combo.height, owner.geo.px)
end

function Combo:Layout()
    local cfg = ns.db.combo
    local owner = ns.frames and ns.frames[cfg.on]
    if not (holder and count > 0 and owner and owner.geo and owner.comboY and self:On(cfg.on)) then
        if holder then holder:Hide() end
        return
    end
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
    local ev = CreateFrame("Frame")
    ev:RegisterEvent("PLAYER_TARGET_CHANGED")
    ev:RegisterEvent("UPDATE_SHAPESHIFT_FORM")
    ev:RegisterUnitEvent("UNIT_POWER_FREQUENT", "player")
    ev:RegisterUnitEvent("UNIT_POWER_UPDATE", "player")
    ev:RegisterUnitEvent("UNIT_MAXPOWER", "player")
    ev:RegisterUnitEvent("UNIT_DISPLAYPOWER", "player")
    ev:SetScript("OnEvent", function(_, event)
        if event == "PLAYER_TARGET_CHANGED" or event == "UNIT_POWER_FREQUENT" or event == "UNIT_POWER_UPDATE" then
            Combo:Update()
        else
            -- A form or the max changed: whether it shows, and how many pips.
            Combo:Apply()
        end
    end)
end
