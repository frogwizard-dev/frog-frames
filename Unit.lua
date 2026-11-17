local _, ns = ...

-- One unit frame: a round portrait with the level badge on its edge, health and power bars tucked in
-- behind its ring, the name above, its icons, and for some kinds a cast bar, auras, combo points, your
-- druid mana or a glow. `root` is a secure unit button, sized and shown out of combat only (Apply);
-- everything drawn is on a plain child (`content`), so it can change any time. Secret values: widgets.

local Unit = {}
Unit.__index = Unit

local issecret, Safe = FrogLib.issecret, FrogLib.Safe
local MANA = (Enum.PowerType and Enum.PowerType.Mana) or 0
local CastKit, Color, Icons, Secure = FrogLib.Cast, FrogLib.Color, FrogLib.Icons, FrogLib.Secure
local Shadowed = FrogLib.Text.Shadowed

local SLOTS = { "Left", "", "Right" } -- the text slots on a bar: healthLeft, health, healthRight
-- Each bar's text settings, slot by slot (asked on every update: not put together each time).
local TEXT_KEYS = { health = {}, power = {}, druid = {} }
for bar, keys in pairs(TEXT_KEYS) do
    for i, slot in ipairs(SLOTS) do keys[i] = bar .. slot end
end
local DRUID_SAMPLE = { value = 70, max = 100, percent = 70 } -- the druid mana bar's text while unlocked, out of form
local CAST_COLOR = { 1, 0.72, 0.3 }

-- Kept from events rather than asked on every update: resting or not, and in a fight or not
-- (from PLAYER_REGEN_*, set by whichever frame hears it first, before any of them looks at its fade).
local resting, fighting = false, false

-- Your class, read once (it never changes in a session).
local playerClass
function ns.PlayerClass()
    if not playerClass then
        local _, class = UnitClass("player")
        playerClass = Safe(class)
        if not playerClass then return nil end
    end
    return playerClass
end
local PlayerClass = ns.PlayerClass

-- A class with mana (one that can't be read counts as one).
local function ManaUser()
    local class = PlayerClass()
    return class ~= "WARRIOR" and class ~= "ROGUE"
end

------------------------------------------------------------------------------
-- Colours
------------------------------------------------------------------------------

local GREEN = { r = 0.1, g = 0.8, b = 0.1 }
local GREY = { r = 0.5, g = 0.5, b = 0.5 }
local REACTION = {
    hostile = { r = 0.85, g = 0.2, b = 0.15 },
    neutral = { r = 0.95, g = 0.85, b = 0.3 },
    friendly = { r = 0.25, g = 0.8, b = 0.25 },
}

-- The health bar's colour: tapped and offline grey; then (healthColor "class") players in their
-- class colour and everyone else by how they feel about you (friendly when the game won't say),
-- or always green ("green"). Anything the game keeps secret falls through to the next rule.
local HEALTH_RULES = {
    class = { tapped = GREY, offline = GREY, class = true, hostile = REACTION.hostile,
        neutral = REACTION.neutral, friendly = REACTION.friendly, fallback = REACTION.friendly },
    green = { tapped = GREY, offline = GREY, fallback = GREEN },
}

local function HealthColor(unit)
    return Color.Unit(unit, HEALTH_RULES[ns.db.healthColor] or HEALTH_RULES.class)
end

-- The name's colour, written only when it changes (every health update asks for it).
local function NameColour(text, r, g, b)
    if text.ffR == r and text.ffG == g and text.ffB == b then return end
    text.ffR, text.ffG, text.ffB = r, g, b
    text:SetTextColor(r, g, b)
end

-- The content's opacity, only when it changes (this runs a few times a second); a secret answer is the game's to
-- set, after which the next plain one is always written.
local function RangeAlpha(content, alpha)
    if content.ffAlpha == alpha then return end
    content:SetAlpha(alpha)
    content.ffAlpha = alpha
end

------------------------------------------------------------------------------
-- Samples, shown while unlocked where there's no unit
------------------------------------------------------------------------------

local SAMPLE_PARTY = {
    { name = "Thrall", class = "SHAMAN" }, { name = "Jaina", class = "MAGE" },
    { name = "Uther", class = "PALADIN" }, { name = "Rexxar", class = "HUNTER" },
}

local function Sample(kind, index)
    local sample = { level = "60", value = 76, max = 100, percent = 76, color = REACTION.friendly }
    if kind == "target" then
        sample.name, sample.level, sample.color, sample.classification = "Hogger", "11", REACTION.hostile, "elite"
    elseif kind == "focus" then
        sample.name, sample.color, sample.classification = "Training Dummy", REACTION.neutral, "rare"
    elseif kind == "tot" then
        sample.name = UnitName("player") or "You"
    elseif kind == "pet" then
        sample.name = "Wolf"
    elseif kind == "partypet" then
        sample.name = "Imp"
    elseif kind == "party" then
        local member = SAMPLE_PARTY[index or 1]
        sample.name = member.name
        local r, g, b = Color.Class(member.class)
        if r then sample.color = { r = r, g = g, b = b } end
    end
    sample.power = { name = sample.name, level = sample.level, value = 62, max = 100, percent = 62 }
    return sample
end

local function Text(parent, justify)
    local text = Shadowed(parent)
    text:SetWordWrap(false)
    if justify then text:SetJustifyH(justify) end
    return text
end

------------------------------------------------------------------------------
-- Build
------------------------------------------------------------------------------

-- def: { key = "party2", kind = "party", unit = "party2", index = 2, side = "left",
--        parent = "party1" (attached frames), event = "PLAYER_TARGET_CHANGED", poll = true }
function ns.NewUnitFrame(def)
    local unitFrame = setmetatable({}, Unit)
    for key, value in pairs(def) do unitFrame[key] = value end
    unitFrame.sample = Sample(unitFrame.kind, unitFrame.index)
    -- Its settings: the saved table is changed in place, never replaced, so it's looked up once.
    unitFrame.settings = ns.db.units[unitFrame.kind]
    -- A pet's frame (yours, a party member's): its power is left out of "idle". Focus refills in a
    -- few seconds and ticks on even when full (the game may hide it, so it never seems to settle).
    unitFrame.petLike = unitFrame.kind == "pet" or unitFrame.kind == "partypet"
    -- The idle rule's options, filled in each time it's asked (FadeOpts).
    unitFrame.fadeOpts = { editMode = true, ignorePower = unitFrame.petLike }
    unitFrame.partyUnit = unitFrame.unit:find("^party") ~= nil
    return unitFrame
end

function Unit:Enabled()
    local units = ns.db.units
    if not units[self.kind].enabled then return false end
    if self.kind == "partypet" then return units.party.enabled end
    return true
end

function Unit:Build()
    local name = "FrogFrames" .. self.key:gsub("^%l", string.upper)
    self.name = name
    local root = CreateFrame("Button", name, UIParent, "SecureUnitButtonTemplate")
    root:SetFrameStrata("LOW")
    root:SetAttribute("unit", self.unit)
    root:RegisterForClicks("AnyUp")
    root:SetMovable(true)
    root:RegisterForDrag("LeftButton")
    -- Right-click: the unit menu, through a hidden button (FrogLib.Secure; clicks set in Apply).
    Secure.MenuButton(root, name .. "Menu")
    root:SetScript("OnDragStart", function() self:DragStart() end)
    root:SetScript("OnDragStop", function() self:DragStop() end)
    root:SetScript("OnEnter", function(frame)
        self:Tooltip(frame)
        self.hover = true
        self:UpdateFade()
    end)
    root:SetScript("OnLeave", function(frame)
        if GameTooltip:IsOwned(frame) then GameTooltip:Hide() end
        self.hover = nil
        self:UpdateFade()
    end)
    root:Hide()
    -- Shown by the unit watch: a new unit (or the same one back) needs drawing in full. rootShown: whether it's on
    -- screen, for the checks made on every event and poll (reading a field costs nothing; asking the frame does).
    -- How its range is kept follows too.
    root:HookScript("OnShow", function()
        self.rootShown = true
        self:Update(true)
        self:WatchRange()
        ns.UpdateTicker()
    end)
    root:HookScript("OnHide", function()
        self.rootShown = false
        self:WatchRange()
        ns.UpdateTicker()
    end)
    -- Click-casting addons (Clique and the like) pick frames up from here.
    ClickCastFrames = ClickCastFrames or {}
    ClickCastFrames[root] = true
    self.root = root

    -- The idle fade's frame, then everything drawn (which the range fade dims), so the two fades
    -- multiply and neither touches the secure frame. Back in an eighth of a second, out in half.
    local fader = CreateFrame("Frame", nil, root)
    fader:SetAllPoints()
    self.fader = fader
    self.fade = FrogLib.Idle.NewFader(fader, { speedIn = 8, speedOut = 2 })
    self.idle = FrogLib.Idle.NewWatcher({
        unit = self.unit,
        onUpdate = function() self:UpdateFade() end,
        enabled = function() return self.settings.fade.enabled end,
    })
    local content = CreateFrame("Frame", nil, fader)
    content:SetAllPoints()
    self.content = content

    -- The bars: `stack` spans the health bar's fill to the power bar's; each bar has its own frame.
    local stack = CreateFrame("Frame", nil, content)
    stack:SetFrameLevel(content:GetFrameLevel() + 2)
    self.stack = stack
    self.health = ns.CreateBar(stack)
    self.power = ns.CreateBar(stack)
    -- The power bar's frame over the health bar's where they share their lines.
    self.power.bar:SetFrameLevel(self.health.bar:GetFrameLevel() + 1)
    self.healthBox = ns.CreateBox(self.health.bar)
    self.powerBox = ns.CreateBox(self.power.bar)
    -- Text over the bars and their border.
    local words = CreateFrame("Frame", nil, stack)
    words:SetAllPoints(content)
    words:SetFrameLevel(stack:GetFrameLevel() + 16) -- above the portrait (+10) and its badge (+14): the level is here
    self.words = words
    self.nameText = Text(words)
    self.levelText = Text(words)
    self.texts = { health = {}, power = {} }
    for _, bar in ipairs({ "health", "power" }) do
        for _, slot in ipairs(SLOTS) do
            local justify = slot == "Left" and "LEFT" or slot == "Right" and "RIGHT" or "CENTER"
            self.texts[bar][slot] = Text(words, justify)
        end
    end

    -- The soft glow round the bars' frames (threat, resting, fighting): under the bars, so only
    -- the light outside them shows. The portrait gets a halo to match (Portrait.lua). Only the kinds
    -- with a setting for it have one.
    local settings = self.settings
    if settings.threat ~= nil or settings.glow ~= nil then self.glow = ns.CreateGlow(stack) end

    -- In front of the bars, whose ends tuck in behind its ring: above both bars' frames (the
    -- power bar's sits at stack + 7; a tie would leave the order to chance).
    self.portrait = ns.CreatePortrait(content, stack:GetFrameLevel() + 10)

    -- Icons over the portrait.
    local icons = CreateFrame("Frame", nil, content)
    icons:SetAllPoints()
    icons:SetFrameLevel(stack:GetFrameLevel() + 20) -- above the portrait's ring and badge
    self.icons = {
        raid = Text(icons),
        leader = icons:CreateTexture(nil, "OVERLAY"),
        status = icons:CreateTexture(nil, "OVERLAY"), -- in combat (yours)
        pvp = icons:CreateTexture(nil, "OVERLAY"),
    }
    if self.kind == "player" then self.rest = self:BuildRest(icons) end
    -- The group role (tank, healer, damage): your frame and the party's.
    if self.kind == "player" or self.kind == "party" then self.icons.role = icons:CreateTexture(nil, "OVERLAY") end
    -- A hunter's pet's happiness: the game's own faces.
    if self.kind == "pet" then self.icons.happiness = icons:CreateTexture(nil, "OVERLAY") end
    self.iconLayer = icons

    -- Your druid mana: only a druid's (or anyone's whose class can't be read yet). The cast bar and the
    -- five-second rule are made once they're switched on (RegisterEvents).
    if settings.druidMana ~= nil and (PlayerClass() or "DRUID") == "DRUID" then self:BuildDruidMana() end
    if settings.healPredict ~= nil then self:BuildPredict() end
    if settings.auras ~= nil then
        self.auras = ns.NewAuras(self.unit, function() return self.settings.auras end)
        self.empty = { debuffs = false, buffs = false }
        self.counts = {} -- how many each row has, when the game says (for wrapped rows' height)
    end
    -- What hangs off the bars goes on from these (LayoutAround), kept for the frame.
    self.edge, self.last = {}, {}
    if self.unit == "player" then self.isMe = true end
    content:SetScript("OnEvent", function(_, event, ...) self:OnEvent(event, ...) end)
end

-- Marks the frame while unlocked: a tint and its name (made the first time it's unlocked).
function Unit:BuildTint()
    local icons, root = self.iconLayer, self.root
    self.tint = icons:CreateTexture(nil, "BACKGROUND")
    self.tint:SetPoint("TOPLEFT", root, "TOPLEFT", -3, 3)
    self.tint:SetPoint("BOTTOMRIGHT", root, "BOTTOMRIGHT", 3, -3)
    self.tint:SetColorTexture(0.3, 0.6, 1, 0.18)
    self.label = Text(icons)
    self.label:SetPoint("BOTTOM", root, "TOP", 0, 2)
    self.label:SetTextColor(0.5, 0.8, 1)
    self.label:SetText(ns.KindName(self.kind) .. (self.index and (" " .. self.index) or ""))
end

-- Resting: Blizzard's own animated "zzz" (its player frame's flipbook, 42 frames in 1.5 seconds),
-- or the old static resting icon where the client hasn't got it.
local REST_ATLAS = "UI-HUD-UnitFrame-Player-Rest-Flipbook"
local STATE_ICON = "Interface\\CharacterFrame\\UI-StateIcon"

function Unit:BuildRest(parent)
    local rest = CreateFrame("Frame", nil, parent)
    rest:SetFrameLevel(parent:GetFrameLevel() + 1)
    rest.texture = rest:CreateTexture(nil, "OVERLAY")
    rest.texture:SetAllPoints()
    local animated = C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(REST_ATLAS) ~= nil
    if animated then
        animated = pcall(function()
            rest.texture:SetAtlas(REST_ATLAS)
            local group = rest:CreateAnimationGroup()
            group:SetLooping("REPEAT")
            local book = group:CreateAnimation("FlipBook")
            book:SetTarget(rest.texture)
            book:SetDuration(1.5)
            book:SetFlipBookRows(7)
            book:SetFlipBookColumns(6)
            book:SetFlipBookFrames(42)
            book:SetFlipBookFrameWidth(0)
            book:SetFlipBookFrameHeight(0)
            book:SetSmoothing("NONE")
            rest.anim = group
        end)
    end
    if not animated then
        rest.anim = nil
        rest.texture:SetTexture(STATE_ICON)
        rest.texture:SetTexCoord(0, 0.5, 0, 0.421875)
    end
    rest.animated = animated
    rest:Hide()
    rest.ffShown = false
    return rest
end

-- Shown or hidden only when that changes (this runs on every update of your frame); while it shows, its
-- animation is started again if it stopped (a hidden region's can).
function Unit:ShowRest(on)
    local rest = self.rest
    if not rest then return end
    on = on and true or false
    if rest.ffShown ~= on then
        rest.ffShown = on
        rest:SetShown(on)
        if not on and rest.anim then rest.anim:Stop() end
    end
    if on and rest.anim and not rest.anim:IsPlaying() then rest.anim:Play() end
end

-- Your mana while a druid form shows rage or energy: a thin bar of its own under the stack.
function Unit:BuildDruidMana()
    local holder = CreateFrame("Frame", nil, self.content)
    holder:SetFrameLevel(self.stack:GetFrameLevel())
    self.druidBox = ns.CreateBox(holder)
    self.druid = ns.CreateBar(holder)
    self.druid.bar:SetAllPoints()
    self.druid:SetColor(Color.Power(nil, "MANA"))
    self.druidHolder = holder
    -- Its text, as the other bars' (druidLeft, druid, druidRight), over its frame.
    local words = CreateFrame("Frame", nil, holder)
    words:SetAllPoints()
    words:SetFrameLevel(holder:GetFrameLevel() + 8)
    self.texts.druid = {}
    for _, slot in ipairs(SLOTS) do
        local justify = slot == "Left" and "LEFT" or slot == "Right" and "RIGHT" or "CENTER"
        self.texts.druid[slot] = Text(words, justify)
    end
    holder:Hide()
end

-- The five-second rule on whichever bar shows your mana (the power bar, or the druid mana bar in a
-- form): a thin strip under it (as XIVPlayer's) fills across the five seconds, FrogLib.FSR saying when.
-- Made when it's first switched on, for a class with mana.
local RULE = FrogLib.FSR.RULE

function Unit:BuildRule()
    local rule = FrogLib.FSR.NewStrip(self.content, 0.6)
    -- Above the bars' frames and the vanilla art (stack + 12), under the words (stack + 16).
    rule:SetFrameLevel(self.stack:GetFrameLevel() + 13)
    local r, g, b = Color.Power(nil, "MANA")
    rule:SetColor(r + (1 - r) * 0.55, g + (1 - g) * 0.55, b + (1 - b) * 0.55, 0.95)
    -- While it shows, each frame only fills it on: which bar it's under is chosen when that can change (the
    -- power's kind, the druid bar, the settings, a layout, the rule starting or running out).
    rule:SetScript("OnUpdate", function()
        local left = self.fsr:Left()
        if left and rule.ffShown and rule.bar and self.settings.manaRule then
            rule:SetLeft(left)
        else
            self:UpdateRule()
        end
    end)
    self.rule = rule
    self.fsr = FrogLib.FSR.NewWatcher(function() self:UpdateRule() end)
    self.fsr:Listen()
end

function Unit:UpdateRule()
    local rule = self.rule
    if not rule then return end
    local settings, bar = self.settings, nil
    if settings.manaRule and self.shownUnit ~= false then
        if (settings.powerHeight > 0 or self:Vanilla()) and Safe(UnitPowerType("player")) == MANA then
            bar = self.power.bar
        elseif self.druidShown then
            bar = self.druid.bar
        end
    end
    local left = self.fsr:Left()
    -- Unlocked: a sample, to see where it sits.
    if not left and not ns.db.locked then left = RULE * 0.4 end
    -- Asked on every power change: hidden once, not again each time (only this shows or hides it).
    if not (bar and left) then
        if rule.ffShown ~= false then
            rule:Hide()
            rule.ffShown = false
        end
        return
    end
    if rule.bar ~= bar then
        -- Under the bar: on the vanilla art's rim, or over the bottom line of the bar's frame.
        rule.bar = bar
        local pixel = FrogLib.Pixel(bar)
        rule:Place(bar, pixel, pixel)
    end
    rule:SetLeft(left)
    rule.ffShown = true
end

-- Heal prediction on the health bar: your incoming heals (bright green), everyone else's (darker
-- green) and damage shields (white), FrogLib.Predict's, shared with XIVPlayer's gauge.
local PREDICT_SAMPLE = { mine = 12, others = 8, shield = 6 } -- of 100, while unlocked

function Unit:BuildPredict()
    self.predict = FrogLib.Predict.New(self.health.bar)
end

function Unit:UpdatePredict()
    local prediction = self.predict
    if not prediction then return end
    local unit = self.shownUnit
    local on = self.settings.healPredict and unit ~= false
    if on ~= self.predictShown then
        self.predictShown = on
        prediction:SetShown(on)
    end
    if not on then return end
    if unit then
        prediction:Update(unit)
    else
        prediction:SetValues(100, PREDICT_SAMPLE)
    end
end

-- The cast bar by the frame: FrogLib's cast line, with the spell's icon in a frame of its own at its
-- start, the spell name on the bar's left and the time left on its right. Made when it's first switched on.
local SAMPLE_CAST = 2.5 -- seconds a sample cast takes, over and over
local SAMPLE_ICON = "Interface\\Icons\\Spell_Shadow_ShadowBolt"

function Unit:BuildCast()
    local holder = CreateFrame("Frame", nil, self.content)
    holder:SetFrameLevel(self.stack:GetFrameLevel())
    local box = ns.CreateBox(holder)
    local gauge = ns.CreateBar(holder)
    gauge.bar:SetAllPoints()
    gauge:SetColor(CAST_COLOR[1], CAST_COLOR[2], CAST_COLOR[3])
    gauge:SetSpark(true)
    local top = CreateFrame("Frame", nil, holder)
    top:SetAllPoints()
    top:SetFrameLevel(holder:GetFrameLevel() + 8)
    local cast = { holder = holder, box = box, gauge = gauge, bar = gauge.bar }
    cast.label = Text(top, "LEFT")
    cast.label:SetPoint("LEFT", holder, "LEFT", 4, 0)
    cast.time = Text(top, "RIGHT")
    cast.time:SetPoint("RIGHT", holder, "RIGHT", -4, 0)
    cast.label:SetPoint("RIGHT", cast.time, "LEFT", -4, 0)
    cast.iconFrame = CreateFrame("Frame", nil, holder)
    cast.icon = cast.iconFrame:CreateTexture(nil, "ARTWORK")
    cast.icon:SetAllPoints()
    cast.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    cast.iconBox = ns.CreateBox(cast.iconFrame)
    -- What's on it, as FrogLib decides (see UpdateCast); unlocked, a sample cast fills over and over.
    local castSettings = self.settings.cast
    cast.driver = CastKit.NewLine({
        bar = gauge.bar, gauge = gauge, label = cast.label, time = cast.time, icon = cast.icon, holder = holder,
        showTime = function() return castSettings.showTime end,
        refresh = function() self:UpdateCast() end, -- a hold is over
        sample = { label = "Shadow Bolt", icon = SAMPLE_ICON, loop = SAMPLE_CAST },
    })
    holder:Hide()
    self.cast = cast
end

-- An aura row that's on and wraps: how many it has decides its height.
local function Wraps(row)
    return row ~= nil and row.enabled and ns.AuraLines(row, row.max) > 1
end

-- The unit's name, level, faction, connection or classification: drawn again (as Update(false)).
local UPDATE_EVENTS = { "UNIT_NAME_UPDATE", "UNIT_LEVEL", "UNIT_FACTION", "UNIT_CONNECTION", "UNIT_CLASSIFICATION_CHANGED" }
-- Anything that can change who a unit is, or the icons on every frame.
local WORLD_EVENTS = { "PLAYER_ENTERING_WORLD", "GROUP_ROSTER_UPDATE", "PARTY_LEADER_CHANGED", "RAID_TARGET_UPDATE" }

-- Only the events the frame's settings use, the parts they feed made the first time it's on: run on every change
-- of settings, in combat too (none of it is protected). Your target's target gets none (Frames.lua polls it).
function Unit:RegisterEvents()
    local content, unit, settings, db = self.content, self.unit, self.settings, ns.db
    local enabled = self:Enabled()
    -- Switched off in a fight, it stays on screen (the watch can't change then): it listens on until the fight
    -- ends, when the waiting Refresh comes round again.
    if not enabled and self.listening and InCombatLockdown() then return end
    self.listening = enabled
    content:UnregisterAllEvents()
    self.rangeEvent = nil
    fighting = InCombatLockdown() and true or false -- in case no frame was listening when it changed
    if enabled then
        if settings.cast and settings.cast.enabled and not self.cast then self:BuildCast() end
        if settings.manaRule and not self.rule and ManaUser() then self:BuildRule() end
        local function OnUnit(event, who) return pcall(content.RegisterUnitEvent, content, event, who or unit) end
        local function OnWorld(event) return pcall(content.RegisterEvent, content, event) end
        local fade = settings.fade
        if not self.poll then
            OnUnit("UNIT_HEALTH")
            OnUnit("UNIT_MAXHEALTH")
            if self.predict and settings.healPredict then
                OnUnit("UNIT_HEAL_PREDICTION")
                OnUnit("UNIT_ABSORB_AMOUNT_CHANGED")
            end
            -- Power: the power bar, your druid mana (your power events cover every kind), the rule, a fade that
            -- counts it. UNIT_POWER_FREQUENT has every change; with UNIT_POWER_UPDATE too each was handled twice.
            if settings.powerHeight > 0 or (self.druid and settings.druidMana) or (self.rule and settings.manaRule)
                or (fade.enabled and not self.petLike) then
                if not OnUnit("UNIT_POWER_FREQUENT") then OnUnit("UNIT_POWER_UPDATE") end
                OnUnit("UNIT_MAXPOWER")
                OnUnit("UNIT_DISPLAYPOWER")
            end
            for _, event in ipairs(UPDATE_EVENTS) do OnUnit(event) end
            OnUnit("UNIT_FLAGS")
            if settings.portrait ~= "none" then
                OnUnit("UNIT_PORTRAIT_UPDATE")
                OnUnit("UNIT_MODEL_CHANGED")
                -- A picture painted during a loading screen gets none, and only this repaints it (as Blizzard's own).
                OnWorld("PORTRAITS_UPDATED")
            end
            if settings.hitText then OnUnit("UNIT_COMBAT") end
            if settings.threat then OnUnit("UNIT_THREAT_SITUATION_UPDATE") end
            -- Rows that fold, or wrap (how many there are sets their height), are looked at again as auras change.
            local auras = settings.auras
            if self.auras and auras.enabled and (auras.fold or Wraps(auras.debuffs) or Wraps(auras.buffs)) then
                OnUnit("UNIT_AURA")
            end
            if self.icons.happiness and db.icons.happiness then OnUnit("UNIT_HAPPINESS") end
            if self.cast and settings.cast.enabled then
                for _, event in ipairs(CastKit.EVENTS) do OnUnit(event) end
            end
            -- The event's unit is the owner: you for "pet", partyN for "partypetN".
            if self.unit == "pet" then OnUnit("UNIT_PET", "player") end
            if self.kind == "partypet" then OnUnit("UNIT_PET", "party" .. self.index) end
        else
            -- Your target's target: a new one is drawn the moment your target changes theirs.
            OnUnit("UNIT_TARGET", "target")
        end
        for _, event in ipairs(WORLD_EVENTS) do OnWorld(event) end
        if self.kind == "player" then OnWorld("PLAYER_UPDATE_RESTING") end
        if self.kind == "player" or fade.enabled or settings.fadeRange then
            OnWorld("PLAYER_REGEN_ENABLED")
            OnWorld("PLAYER_REGEN_DISABLED")
        end
        if self.druid and settings.druidMana then OnWorld("UPDATE_SHAPESHIFT_FORM") end
        if db.icons.pvp then OnWorld("PLAYER_FLAGS_CHANGED") end
        if self.icons.role then OnWorld("PLAYER_ROLES_ASSIGNED") end
        if self.event then OnWorld(self.event) end
        if self.event ~= "PLAYER_TARGET_CHANGED" and fade.enabled and fade.noTarget then
            OnWorld("PLAYER_TARGET_CHANGED") -- the idle fade's "no target"
        end
        -- Your level changes the colour of everyone else's.
        if settings.showLevel and not OnWorld("PLAYER_LEVEL_CHANGED") then OnWorld("PLAYER_LEVEL_UP") end
    end
    -- Switched off in a fight, what these drew is cleared now (their events are gone).
    if not settings.fadeRange then RangeAlpha(content, 1) end
    if self.cast and not (enabled and settings.cast.enabled) then self.cast.holder:Hide() end
    self:WatchRange()
end

-- Party frames hear of their range from the game while they're on screen (as Blizzard's raid frames do; it does
-- extra work for every frame listening); every other frame's is polled (Polled).
function Unit:WatchRange()
    if self.kind ~= "party" then return end
    local want = self.rootShown and self.settings.fadeRange or false
    if want == (self.rangeEvent or false) then return end
    if want then
        self.rangeEvent = pcall(self.content.RegisterUnitEvent, self.content, "UNIT_IN_RANGE_UPDATE", self.unit)
        self:UpdateRange() -- (switched on in a fight, someone already out of range sends nothing)
    else
        self.rangeEvent = nil
        self.content:UnregisterEvent("UNIT_IN_RANGE_UPDATE")
    end
end

-- Whether the ticker (Frames.lua) needs this frame: your target's target, or a range only a poll can tell (the
-- game's group check; anyone else's distance, out of combat only, as it's blocked in combat).
function Unit:Polled()
    if not self.rootShown then return false end
    if self.poll then return true end
    if not self.settings.fadeRange or self.rangeEvent or self.isMe then return false end
    return self.grouped or not fighting
end

-- Events that only redraw numbers come in bursts (a power tick sends two, a new debuff three, health and max
-- health together): each is noted, and the frame is drawn once after the events, before the game draws the
-- screen. The driver only runs while something is waiting.
local waiting = {} -- [unit frame] = true
local queued = false
local flusher = CreateFrame("Frame")
flusher:Hide()
flusher:SetScript("OnUpdate", function(self)
    self:Hide()
    queued = false
    for unitFrame in pairs(waiting) do
        waiting[unitFrame] = nil
        unitFrame:Flush()
    end
end)

-- what: "health", "power", "display" (its kind too), "predict", "aura", "flags" (health, its colour and the
-- icons), "update" (everything, as Update(false)) or "full" (a new unit, as Update(true)).
function Unit:Mark(what)
    local dirty = self.dirty
    if not dirty then
        dirty = {}
        self.dirty = dirty
    end
    dirty[what] = true
    waiting[self] = true
    if not queued then
        queued = true
        flusher:Show()
    end
end

function Unit:Flush()
    local dirty = self.dirty
    if not dirty or not next(dirty) then return end
    local full, update, flags, health, predict, aura = dirty.full, dirty.update, dirty.flags, dirty.health,
        dirty.predict, dirty.aura
    local display = dirty.display
    local power = dirty.power or display
    wipe(dirty)
    if not self.rootShown then return end
    if full or update then
        self:Update(full) -- health and power with the rest
    else
        if health or flags then
            self:UpdateHealth(false, flags)
        elseif predict then
            self:UpdatePredict()
        end
        if power then self:UpdatePower(false, display) end
        if flags then
            if self.vanillaShown then self:VanillaNameColour(self.shownUnit) end
            self:UpdateIcons()
            self:UpdateGlow()
        end
    end
    -- What Changed does for each, the fade looked at once for all. A pet's power is no part of its fade.
    if self.petLike then power = nil end
    if health or power then
        if self.settings.fade.enabled then
            if health then self.idle:Changed("health") end
            if power then self.idle:Changed("power") end
        end
        self:UpdateFade()
        if health then self.fade:Replay() end
    elseif flags and not (full or update) then
        self:UpdateFade()
    end
    if aura and not full then self:CheckEmpty() end
end

-- What each event does (only the events a frame's settings use are registered: RegisterEvents).
local function Mark(what) return function(self) self:Mark(what) end end
local function RedrawIcons(self) self:UpdateIcons() end
local function RedrawPortrait(self) self:UpdatePortrait() end

-- A fight starting or ending: the glow and the icons with it, the fade, and which ranges need polling.
local function Regen(self, event)
    fighting = event == "PLAYER_REGEN_DISABLED"
    self:UpdateGlow()
    self:UpdateIcons()
    if fighting then
        self:UpdateFade()
        -- Anyone's distance can't be told in a fight, so out of the group they count as in range (InRange).
        if self.settings.fadeRange and self.shownUnit and not self.grouped then RangeAlpha(self.content, 1) end
    else
        -- Health and power start ticking back: wait for them to settle.
        self:Changed("health")
        self:Changed("power")
    end
    ns.UpdateTicker()
end

local HANDLERS = {
    UNIT_HEALTH = Mark("health"), UNIT_MAXHEALTH = Mark("health"),
    UNIT_HEAL_PREDICTION = Mark("predict"), UNIT_ABSORB_AMOUNT_CHANGED = Mark("predict"),
    UNIT_POWER_FREQUENT = Mark("power"), UNIT_POWER_UPDATE = Mark("power"), UNIT_MAXPOWER = Mark("power"),
    UNIT_DISPLAYPOWER = Mark("display"),
    UNIT_AURA = Mark("aura"),
    -- UNIT_FLAGS comes often in a fight: only what flags change (combat, tapped, PvP...).
    UNIT_FLAGS = Mark("flags"),
    UNIT_NAME_UPDATE = Mark("update"), UNIT_LEVEL = Mark("update"), UNIT_FACTION = Mark("update"),
    UNIT_CONNECTION = Mark("update"), UNIT_CLASSIFICATION_CHANGED = Mark("update"), PLAYER_LEVEL_CHANGED = Mark("update"),
    PLAYER_LEVEL_UP = function(self) C_Timer.After(0, function() self:Mark("update") end) end, -- once the level is in
    PLAYER_ENTERING_WORLD = Mark("full"), UNIT_PET = Mark("full"),
    UNIT_HAPPINESS = RedrawIcons, RAID_TARGET_UPDATE = RedrawIcons, PARTY_LEADER_CHANGED = RedrawIcons,
    PLAYER_FLAGS_CHANGED = RedrawIcons, PLAYER_ROLES_ASSIGNED = RedrawIcons,
    UNIT_PORTRAIT_UPDATE = RedrawPortrait, UNIT_MODEL_CHANGED = RedrawPortrait, PORTRAITS_UPDATED = RedrawPortrait,
    UNIT_COMBAT = function(self, _, _, ...)
        if self.portraitShown then self.portrait:CombatEvent(...) end
    end,
    UNIT_THREAT_SITUATION_UPDATE = function(self)
        self:UpdateGlow()
        self:UpdateIcons()
        self:UpdateFade()
    end,
    PLAYER_UPDATE_RESTING = function(self)
        resting = IsResting()
        self:UpdateGlow()
        self:UpdateIcons()
        self:UpdateFade()
    end,
    PLAYER_REGEN_ENABLED = Regen, PLAYER_REGEN_DISABLED = Regen,
    UPDATE_SHAPESHIFT_FORM = function(self) self:UpdatePower(false) end,
    PLAYER_TARGET_CHANGED = function(self) self:UpdateFade() end, -- the idle fade's "no target"
    -- Who's in the group: the party's frames can be someone else now (once a frame, as these come in bursts);
    -- the rest only have their group icons and range to look at again.
    GROUP_ROSTER_UPDATE = function(self)
        if self.partyUnit then return self:Mark("full") end
        self:UpdateIcons()
        if self.shownUnit then self:CheckGroup() end
        self:UpdateFade()
    end,
    UNIT_IN_RANGE_UPDATE = function(self) self:UpdateRange() end, -- (its payload is secret)
    UNIT_TARGET = Mark("full"), -- (a target switching targets sends these in bursts)
}
-- (A channel's stop says who interrupted it, fourth after the unit.)
for _, event in ipairs(CastKit.EVENTS) do
    HANDLERS[event] = function(self, _, _, _, _, interruptedBy) self:UpdateCast(event, interruptedBy) end
end

function Unit:OnEvent(event, ...)
    if not self.rootShown then
        -- Off screen (Alt+Z too), a fight starting or ending is still noted: the fade and the poll go by it.
        if event == "PLAYER_REGEN_DISABLED" or event == "PLAYER_REGEN_ENABLED" then
            fighting = event == "PLAYER_REGEN_DISABLED"
        end
        return
    end
    -- A new target or focus: drawn in full at once.
    if event == self.event then
        self:Update(true)
        self:UpdateFade()
        return
    end
    local handler = HANDLERS[event]
    if handler then handler(self, event, ...) end
end

------------------------------------------------------------------------------
-- Clicks, tooltips and moving
------------------------------------------------------------------------------

function Unit:Tooltip(frame)
    GameTooltip_SetDefaultAnchor(GameTooltip, frame)
    if not ns.db.locked then
        GameTooltip:SetText("FrogFrames: " .. ns.KindName(self.kind))
        GameTooltip:AddLine("Drag to move. Lock again in /ff.", 1, 1, 1)
        GameTooltip:Show()
        return
    end
    GameTooltip:SetUnit(self.unit)
    GameTooltip:Show()
end

-- The frame that moves when this one is dragged: the first party frame for the party (the rest
-- hang under it); otherwise this one.
function Unit:Mover()
    if self.kind == "party" then return ns.frames.party1 end
    return self
end

function Unit:DragStart()
    if ns.db.locked or InCombatLockdown() then return end
    local mover = self:Mover()
    mover.root:StartMoving()
    if not mover.parent then FrogLib.Grid:Track(mover.root) end
    mover.moving = true
end

function Unit:DragStop()
    local mover = self:Mover()
    if not mover.moving then return end
    mover.moving = nil
    local root = mover.root
    root:StopMovingOrSizing()
    pcall(root.SetUserPlaced, root, false)
    FrogLib.Grid:Track(nil)
    local settings = mover.settings
    if mover.parent then
        -- Attached frames keep their place relative to the frame they hang from.
        local parent = ns.frames[mover.parent]
        local parentRoot = parent.root
        local scale, parentScale = root:GetEffectiveScale(), parentRoot:GetEffectiveScale()
        local x = root:GetLeft() - parentRoot:GetLeft() * parentScale / scale
        local y = root:GetTop() - parentRoot:GetTop() * parentScale / scale
        local shiftX, shiftY = mover:Shift("TOPLEFT")
        local parentShiftX, parentShiftY = parent:Shift("TOPLEFT")
        settings.attach = { "TOPLEFT", "TOPLEFT", math.floor(x - shiftX + parentShiftX + 0.5),
            math.floor(y - shiftY + parentShiftY + 0.5) }
    else
        -- Centred exactly when let go near the middle of the screen (FrogLib's Grid.lua).
        local point, relativePoint, x, y = FrogLib.Grid:Snap(root)
        local shiftX, shiftY = mover:Shift(point)
        settings.point = { point, "UIParent", relativePoint, x - shiftX, y - shiftY }
    end
    ns.Refresh()
end

------------------------------------------------------------------------------
-- Apply: size, place, clicks and visibility (out of combat only), then the layout
------------------------------------------------------------------------------

-- The frame (`root`, what's clicked) covers the portrait and the bars wherever their offsets put
-- them; saved places are for its "home" box, where the two sit with no offsets.
local POINTS = {
    TOPLEFT = { 0, 0 }, TOP = { 0.5, 0 }, TOPRIGHT = { 1, 0 }, LEFT = { 0, 0.5 }, CENTER = { 0.5, 0.5 },
    RIGHT = { 1, 0.5 }, BOTTOMLEFT = { 0, 1 }, BOTTOM = { 0.5, 1 }, BOTTOMRIGHT = { 1, 1 },
}

-- How far the frame's `point` is from the home box's, in the frame's units (x right, y up).
function Unit:Shift(point)
    local box = self.box
    local fractions = POINTS[point] or POINTS.CENTER
    if not box then return 0, 0 end
    local used, home = box.used, box.home -- { left, top, right, bottom }, down from the home box's top left
    local across = (used[1] + fractions[1] * (used[3] - used[1])) - (home[1] + fractions[1] * (home[3] - home[1]))
    local down = (used[2] + fractions[2] * (used[4] - used[2])) - (home[2] + fractions[2] * (home[4] - home[2]))
    return across, -down
end

function Unit:Place()
    local root, settings = self.root, self.settings
    root:ClearAllPoints()
    local function Anchor(point, relativeTo, relativeFrame, relativePoint, x, y)
        local shiftX, shiftY = self:Shift(point)
        local relativeX, relativeY = 0, 0
        if relativeFrame then relativeX, relativeY = relativeFrame:Shift(relativePoint) end
        root:SetPoint(point, relativeTo, relativePoint, x + shiftX - relativeX, y + shiftY - relativeY)
    end
    if self.kind == "party" and self.index > 1 then
        local previous = ns.frames["party" .. (self.index - 1)]
        Anchor("TOPLEFT", previous.root, previous, "BOTTOMLEFT", 0, -settings.spacing)
    elseif self.parent then
        local attach, parent = settings.attach, ns.frames[self.parent]
        Anchor(attach[1], parent.root, parent, attach[2], attach[3], attach[4])
    else
        local point = settings.point
        Anchor(point[1], UIParent, nil, point[3], point[4], point[5])
    end
    root:SetClampedToScreen(self.parent == nil and self.kind ~= "party")
end

-- Shown by the game while the unit exists; the party (and their pets) not in a raid, if set so.
function Unit:Watch()
    local root = self.root
    UnregisterUnitWatch(root)
    if UnregisterStateDriver then UnregisterStateDriver(root, "visibility") end
    if not self:Enabled() then
        root:Hide()
        return
    end
    if not ns.db.locked then
        root:Show() -- samples where there's no unit
        return
    end
    if (self.kind == "party" or self.kind == "partypet") and ns.db.units.party.hideInRaid and RegisterStateDriver then
        RegisterStateDriver(root, "visibility", "[group:raid] hide; [@" .. self.unit .. ",exists] show; hide")
    else
        RegisterUnitWatch(root)
    end
end

function Unit:Apply()
    local root, db = self.root, ns.db
    root:SetScale(self.settings.scale)
    self:Layout()
    self:Place()
    -- Clicks: left-click targets, right-click opens the unit menu; off while unlocked, so the
    -- frames can be dragged.
    Secure.SetClicks(root, db.locked and self.name .. "Menu")
    if not db.locked and not self.tint then self:BuildTint() end
    if self.tint then
        self.tint:SetShown(not db.locked)
        self.label:SetShown(not db.locked)
    end
    -- Drawn again if it stays on screen (one the watch shows here is drawn as it shows).
    local wasShown = self.rootShown
    self:Watch()
    if wasShown and self.rootShown then self:Update(true) end
    self:UpdateFade(true)
end

------------------------------------------------------------------------------
-- Layout
------------------------------------------------------------------------------

local function Round(value, pixel) return math.floor(value / pixel + 0.5) * pixel end

------------------------------------------------------------------------------
-- The vanilla frame (settings.vanilla): Blizzard's own 1.x art, our bars, portrait, name and level in
-- its holes as 1.x laid them out (VANILLA_SPECS, in its texels drawn 1:1), mirrored for frames facing
-- the other way. The big target frame for yours, the target and the focus (its name box tinted by
-- reaction, the elite and rare art round special targets); the small ones for the pet, ToT and party.
------------------------------------------------------------------------------

local ART = "Interface\\TargetingFrame\\"
local VANILLA_BAR = ART .. "UI-StatusBar"
local VANILLA_NAME_BACK = ART .. "UI-TargetingFrame-LevelBackground"
-- The large health bar over the name box (vanillaThick): our own cut of the art without the divider.
local THICK = "Interface\\AddOns\\FrogFrames\\Media\\VanillaThick"
local SPECIAL = { elite = "-Elite", worldboss = "-Elite", rare = "-Rare", rareelite = "-Rare-Elite" }
-- Each art: its file, drawn width x height from its coords; the side its portrait is on; and in its
-- texels: health and power { x, y, width, height }, the portrait { centre x, centre y, across }, the
-- level's centre (none: no level), and the name (box: its box, centred; else an anchor and { x, y }).
-- The level's ring: an ellipse fitted to its gold rim, centred at (178, 66) on the frame; the digits
-- half a texel lower, as they draw a little high.
local BIG = {
    file = ART .. "UI-TargetingFrame", width = 232, height = 100, coords = { 0.09375, 1, 0, 0.78125 }, portraitSide = "right",
    health = { 7, 41, 119, 12 }, power = { 7, 52, 119, 12 }, portrait = { 158, 44, 64 }, level = { 178, 66.5 },
    box = { 7, 22, 119, 19 }, special = true,
    -- The large health bar: over the name box too, the name above the frame.
    thickHealth = { 7, 22, 119, 31 }, thickName = { "BOTTOM", 66.5, -19 },
}
local VANILLA_SPECS = {
    player = BIG, target = BIG, focus = BIG,
    pet = { file = ART .. "UI-SmallTargetingFrame", width = 128, height = 48, coords = { 0, 1, 0, 0.75 },
        portraitSide = "left", health = { 47, 22, 69, 8 }, power = { 47, 29, 69, 8 }, portrait = { 25.5, 24.5, 37 },
        name = { "BOTTOMLEFT", 51, -19 } },
    tot = { file = ART .. "UI-TargetofTargetFrame", width = 93, height = 45, coords = { 0.015625, 0.7265625, 0, 0.703125 },
        portraitSide = "left", health = { 45, 15, 46, 7 }, power = { 45, 23, 46, 7 }, portrait = { 22.5, 22.5, 35 },
        name = { "TOPLEFT", 45, -31 } },
    party = { file = ART .. "UI-PartyFrame", width = 128, height = 48, coords = { 0, 1, 0, 0.75 }, portraitSide = "left",
        health = { 47, 12, 70, 7 }, power = { 47, 20, 70, 7 }, portrait = { 25.5, 24.5, 37 },
        name = { "BOTTOMLEFT", 49, -8 } },
}
-- Your druid mana bar in the big art's bar slot: its left end (x 26-34, rows 50-66, the bar 5 in
-- from its left and 2 down), mirrored at the right, the middle stretched.
local DRUID_SLOT = { left = 26, right = 34, top = 50, bottom = 66, inX = 5, inY = 2, bar = 12 }

function Unit:Vanilla()
    return VANILLA_SPECS[self.kind] ~= nil and self.settings.vanilla and true or false
end

-- x across the art, for this frame's side: the art mirrored when the frame's portrait is on the
-- other side from the art's.
function Unit:VX(x, width)
    local spec = VANILLA_SPECS[self.kind]
    local portraitSide = self.side == "left" and "left" or "right"
    if portraitSide ~= spec.portraitSide then return spec.width - x - (width or 0) end
    return x
end

function Unit:VMirrored()
    local spec = VANILLA_SPECS[self.kind]
    return (self.side == "left" and "left" or "right") ~= spec.portraitSide
end

function Unit:BuildVanilla()
    local art = CreateFrame("Frame", nil, self.content)
    art:SetAllPoints(self.root)
    -- Over the bars and the portrait's picture, under the words.
    art:SetFrameLevel(self.stack:GetFrameLevel() + 12)
    art.texture = art:CreateTexture(nil, "ARTWORK")
    art.texture:SetAllPoints()
    self.vanillaArt = art
    -- The name's box, under the bars.
    self.vanillaNameBack = self.content:CreateTexture(nil, "BACKGROUND")
    self.vanillaNameBack:SetTexture(VANILLA_NAME_BACK)
end

-- The art for this unit: the big frame's elite, rare or rare elite version for special targets
-- (the classification may be secret: read safely), its large-health cut if set; mirrored or not.
-- Written only when that changes (this runs on every update).
function Unit:VanillaArt(classification)
    local art = self.vanillaArt
    if not art then return end
    local spec = VANILLA_SPECS[self.kind]
    local suffix = (spec.special and self.kind ~= "player") and SPECIAL[Safe(classification) or ""] or ""
    local thick = spec.thickHealth and self.settings.vanillaThick and true or false
    local mirrored = self:VMirrored()
    if art.ffSuffix == suffix and art.ffThick == thick and art.ffMirrored == mirrored then return end
    art.ffSuffix, art.ffThick, art.ffMirrored = suffix, thick, mirrored
    if thick then
        art.texture:SetTexture(THICK .. suffix:gsub("-", ""))
    else
        art.texture:SetTexture(spec.file .. suffix)
    end
    local coords = spec.coords
    if mirrored then
        art.texture:SetTexCoord(coords[2], coords[1], coords[3], coords[4])
    else
        art.texture:SetTexCoord(coords[1], coords[2], coords[3], coords[4])
    end
end

local function TintBySelection(texture, unit)
    texture:SetVertexColor(UnitSelectionColor(unit))
end

-- The name box tinted by the unit's reaction, as 1.x did (the big frame, not on yours).
function Unit:VanillaNameColour(unit)
    local back = self.vanillaNameBack
    if not back then return end
    local spec = VANILLA_SPECS[self.kind]
    local on = spec.box and self.kind ~= "player" and not self.settings.vanillaThick and true or false
    if back.ffShown ~= on then
        back.ffShown = on
        back:SetShown(on)
    end
    if not on then return end
    if unit and pcall(TintBySelection, back, unit) then return end
    back:SetVertexColor(1, 0, 0)
end

-- Your druid mana bar in the art's bar slot (its ends cut from the big art), Classic's texture.
function Unit:VanillaDruid(on)
    if not self.druid then return end
    local holder = self.druidHolder
    local caps = self.druidCaps
    if on and not caps then
        caps = {}
        local frame = CreateFrame("Frame", nil, holder)
        frame:SetAllPoints()
        frame:SetFrameLevel(holder:GetFrameLevel() + 6)
        for i = 1, 3 do
            caps[i] = frame:CreateTexture(nil, "ARTWORK")
            caps[i]:SetTexture(BIG.file)
        end
        caps.frame = frame
        self.druidCaps = caps
    end
    if caps then caps.frame:SetShown(on and true or false) end
    if self.druidBox then self.druidBox:SetShown(not on) end
    if not on then return end
    local slot = DRUID_SLOT
    local scale = (holder:GetHeight() or slot.bar) / slot.bar
    if not (scale > 0) then scale = 1 end
    local capWidth, capHeight = (slot.right - slot.left) * scale, (slot.bottom - slot.top) * scale
    local coordLeft, coordRight = slot.left / 256, slot.right / 256
    local coordTop, coordBottom = slot.top / 128, slot.bottom / 128
    local left, middle, right = caps[1], caps[2], caps[3]
    left:ClearAllPoints()
    left:SetPoint("TOPLEFT", holder, "TOPLEFT", -slot.inX * scale, slot.inY * scale)
    left:SetSize(capWidth, capHeight)
    left:SetTexCoord(coordLeft, coordRight, coordTop, coordBottom)
    right:ClearAllPoints()
    right:SetPoint("TOPRIGHT", holder, "TOPRIGHT", slot.inX * scale, slot.inY * scale)
    right:SetSize(capWidth, capHeight)
    right:SetTexCoord(coordRight, coordLeft, coordTop, coordBottom)
    -- The middle: a slice past the left end, stretched between them.
    middle:ClearAllPoints()
    middle:SetPoint("TOPLEFT", left, "TOPRIGHT")
    middle:SetPoint("BOTTOMRIGHT", right, "BOTTOMLEFT")
    middle:SetTexCoord(coordRight, (slot.right + 60) / 256, coordTop, coordBottom)
    self.druid:ApplyTexture(self.settings.vanillaTextures and self.settings.powerTexture or VANILLA_BAR)
    self.druid.track:SetColorTexture(0, 0, 0, 0.5)
end

-- The cast bar in the vanilla frame: yours in 1.x's player cast bar frame (UI-CastingBar-Border, its
-- top 28 above a 195 x 13 bar), the others in Classic's small one (opening x 36-221, rows 27-37);
-- stretched to the bar, Classic's texture, the icon clear of its left end (edge: that end's x).
local CAST_FRAMES = {
    big = { file = "Interface\\CastingBar\\UI-CastingBar-Border", x = -30.5, y = 28, barWidth = 195, barHeight = 13, edge = 23 },
    small = { file = "Interface\\CastingBar\\UI-CastingBar-Border-Small", x = -36, y = 27, barWidth = 185, barHeight = 10,
        edge = 28 },
}

function Unit:VanillaCast(on)
    local cast = self.cast
    if not cast then return end
    if on and not cast.vanillaFrame then
        local frame = CreateFrame("Frame", nil, cast.holder)
        frame:SetAllPoints()
        frame:SetFrameLevel(cast.holder:GetFrameLevel() + 6)
        cast.vanillaBorder = frame:CreateTexture(nil, "ARTWORK")
        cast.vanillaFrame = frame
    end
    if cast.vanillaFrame then cast.vanillaFrame:SetShown(on) end
    -- Our own frames round the bar and icon out of sight.
    cast.box:SetShown(not on)
    cast.iconBox:SetShown(not on)
    if not on then return end
    local art = self.kind == "player" and CAST_FRAMES.big or CAST_FRAMES.small
    local scaleX = (cast.holder:GetWidth() or art.barWidth) / art.barWidth
    local scaleY = (cast.holder:GetHeight() or art.barHeight) / art.barHeight
    cast.vanillaBorder:SetTexture(art.file)
    cast.vanillaBorder:ClearAllPoints()
    cast.vanillaBorder:SetPoint("TOPLEFT", cast.holder, "TOPLEFT", art.x * scaleX, art.y * scaleY)
    cast.vanillaBorder:SetSize(256 * scaleX, 64 * scaleY)
    cast.gauge:ApplyTexture(self.settings.vanillaTextures and nil or VANILLA_BAR)
    cast.gauge.track:SetColorTexture(0, 0, 0, 0.5)
    cast.iconFrame:ClearAllPoints()
    cast.iconFrame:SetPoint("RIGHT", cast.holder, "LEFT", (art.x + art.edge) * scaleX - 3, 0)
end

function Unit:LayoutVanilla()
    local settings, db = self.settings, ns.db
    local offsets = settings.offsets
    local root = self.root
    local pixel = FrogLib.Pixel(root)
    local spec = VANILLA_SPECS[self.kind]
    if not self.vanillaArt then self:BuildVanilla() end
    self.vanillaArt:Show()
    self.vanillaShown = true
    local artWidth, artHeight = spec.width, spec.height
    if not InCombatLockdown() then root:SetSize(artWidth, artHeight) end
    self.box = { home = { 0, 0, artWidth, artHeight }, used = { 0, 0, artWidth, artHeight } }
    local thick = spec.thickHealth and settings.vanillaThick

    -- The bars in the art's slots (the large health bar over the name box too).
    local healthSlot, powerSlot = thick and spec.thickHealth or spec.health, spec.power
    local width = healthSlot[3]
    local barsX = self:VX(healthSlot[1], width)
    local stack = self.stack
    stack:ClearAllPoints()
    stack:SetPoint("TOPLEFT", root, "TOPLEFT", barsX, -healthSlot[2])
    stack:SetSize(width, powerSlot[2] + powerSlot[4] - healthSlot[2])
    local healthBar, powerBar = self.health.bar, self.power.bar
    healthBar:ClearAllPoints()
    healthBar:SetPoint("TOPLEFT", stack, "TOPLEFT", 0, 0)
    healthBar:SetSize(width, healthSlot[4])
    powerBar:ClearAllPoints()
    powerBar:SetPoint("TOPLEFT", stack, "TOPLEFT", 0, -(powerSlot[2] - healthSlot[2]))
    powerBar:SetSize(powerSlot[3], powerSlot[4])
    powerBar:SetShown(true)
    self.health:ApplyTexture(settings.vanillaTextures and settings.healthTexture or VANILLA_BAR)
    self.power:ApplyTexture(settings.vanillaTextures and settings.powerTexture or VANILLA_BAR)
    for _, bar in ipairs({ self.health, self.power }) do bar.track:SetColorTexture(0, 0, 0, 0.5) end
    self.healthBox:SetShown(false)
    self.powerBox:SetShown(false)

    -- The portrait's picture in the ring; the level in the small ring (the big frame).
    local portrait = self.portrait
    portrait.vanilla = true
    local diameter = spec.portrait[3]
    self.portraitShown = settings.portrait ~= "none"
    portrait.frame:SetShown(self.portraitShown)
    portrait:Layout(diameter, self.side, 0, 0)
    portrait.badge:SetShown(false)
    portrait.frame:ClearAllPoints()
    portrait.frame:SetPoint("CENTER", root, "TOPLEFT", self:VX(spec.portrait[1]), -spec.portrait[2])
    local levelText = self.levelText
    levelText:ClearAllPoints()
    if spec.level then
        ns.SetFont(levelText, db.font, 10, db.outline)
        -- Nudged by its own offsets (vanillaLevelX / Y, any fraction; right and up are +).
        levelText:SetPoint("CENTER", root, "TOPLEFT", self:VX(spec.level[1]) + (settings.vanillaLevelX or 0),
            -spec.level[2] + (settings.vanillaLevelY or 0))
        levelText:SetTextColor(1, 0.82, 0)
    end
    levelText:SetShown(spec.level ~= nil and settings.showLevel)
    self.levelAbove = spec.level ~= nil and settings.showLevel

    -- The name: centred in its box (or above the frame with the large health bar), or by the bars.
    local nameText = self.nameText
    ns.SetNameFont(nameText, db.font, settings.nameSize, db.outline)
    nameText:ClearAllPoints()
    nameText:SetWordWrap(false)
    NameColour(nameText, 1, 0.82, 0)
    local nameBack = self.vanillaNameBack
    if spec.box and not thick then
        local box = spec.box
        nameBack:ClearAllPoints()
        nameBack:SetPoint("TOPLEFT", root, "TOPLEFT", self:VX(box[1], box[3]), -box[2])
        nameBack:SetSize(box[3], box[4])
        nameText:SetPoint("CENTER", root, "TOPLEFT", self:VX(box[1], box[3]) + box[3] / 2 + offsets.nameX,
            -(box[2] + box[4] / 2) + offsets.nameY)
        nameText:SetWidth(box[3] - 7)
        nameText:SetJustifyH("CENTER")
    elseif thick then
        local place = spec.thickName
        nameText:SetPoint(place[1], root, "TOPLEFT", self:VX(place[2]) + offsets.nameX, place[3] + offsets.nameY)
        nameText:SetWidth(0)
        nameText:SetJustifyH("CENTER")
    else
        local place = spec.name
        local point = place[1]
        if self:VMirrored() then point = point:gsub("LEFT", "RIGHT") end
        nameText:SetPoint(point, root, "TOPLEFT", self:VX(place[2]) + offsets.nameX, place[3] + offsets.nameY)
        nameText:SetWidth(0)
        nameText:SetJustifyH(point:find("RIGHT") and "RIGHT" or "LEFT")
    end
    self.nameShown = settings.namePos ~= "none"
    nameText:SetShown(self.nameShown)
    self.nameSlot = nil

    -- The bars' text slots, as on any frame, no taller than their bar.
    for bar, barFrame in pairs({ health = healthBar, power = powerBar }) do
        local height = bar == "health" and healthSlot[4] or powerSlot[4]
        for _, slot in ipairs(SLOTS) do
            local text = self.texts[bar][slot]
            ns.SetFont(text, db.font, math.max(6, math.min(settings.textSize, height)), db.outline)
            text:ClearAllPoints()
            local nudgeX, nudgeY = offsets[bar .. slot .. "X"] or 0, offsets[bar .. slot .. "Y"] or 0
            local anchor = slot == "Left" and "LEFT" or slot == "Right" and "RIGHT" or "CENTER"
            text:SetPoint(anchor, barFrame, anchor, nudgeX + (anchor == "LEFT" and 2 or anchor == "RIGHT" and -2 or 0), nudgeY)
        end
    end

    -- What hangs off the frame goes clear of the art: above the name, below its frame.
    local reach = 3
    local above = thick and (healthSlot[2] - 2) or (spec.box and (healthSlot[2] - spec.box[2] - reach) or (settings.nameSize + 2))
    self.geo = { width = width, stackHeight = powerSlot[2] + powerSlot[4] - healthSlot[2], reach = reach, pixel = pixel,
        portrait = diameter, ring = 0, nameHeight = math.max(0, above), clear = 0,
        portraitY = spec.portrait[2] - healthSlot[2], left = barsX, right = artWidth - barsX - width }
    if self.glow then self.glow:Place(stack, reach) end
    local unit = self.unit and UnitExists(self.unit) and self.unit or nil
    self:VanillaArt(unit and UnitClassification(unit) or nil)
    self:VanillaNameColour(unit)
    self:LayoutIcons()
    self:LayoutAround()
    self:VanillaDruid(self.druidHolder ~= nil)
end

-- Sizes and places everything inside the frame, and the frame to fit (the frame only when it's
-- allowed: out of combat), on whole screen pixels. The bars are centred on the portrait.
function Unit:Layout()
    if self:Vanilla() then return self:LayoutVanilla() end
    -- Back from the vanilla frame: its art away, our frames and the portrait's ring back.
    if self.vanillaArt then
        self.vanillaArt:Hide()
        self.vanillaNameBack:Hide()
        self.vanillaNameBack.ffShown = false
        self.healthBox:SetShown(true)
        self.powerBox:SetShown(true)
        self.portrait.vanilla = nil
        self:VanillaDruid(false)
        self:VanillaCast(false)
    end
    self.vanillaShown = false
    local settings, db = self.settings, ns.db
    local offsets = settings.offsets
    local root = self.root
    local pixel = FrogLib.Pixel(root)
    local function Snap(value) return ns.Snap(value, pixel) end
    local reach = ns.BorderReach(root) -- each bar's frame, outside it
    local gap = ns.BarGap(root)        -- from the health bar's fill to the power bar's

    local width = Snap(settings.width)
    local healthHeight = Snap(settings.healthHeight)
    local powerHeight = settings.powerHeight > 0 and Snap(settings.powerHeight) or 0
    local stackHeight = healthHeight + (powerHeight > 0 and gap + powerHeight or 0)
    local blockHeight = stackHeight + 2 * reach

    -- The portrait and its ring.
    local portrait = self.portrait
    local diameter = settings.portrait ~= "none" and Snap(settings.portraitSize) or 0
    self.portraitShown = diameter > 0
    portrait.frame:SetShown(diameter > 0)
    local ring = 0
    if diameter > 0 then
        portrait:Layout(diameter, self.side, offsets.levelX, offsets.levelY)
        ring = portrait:Ring()
    end
    -- Without a portrait the level goes above the bars, at the far end from the name.
    local levelAbove = settings.showLevel and diameter == 0
    local nameHeight = (settings.namePos == "above" or levelAbove) and Round(settings.nameSize + 3, pixel) or 0

    -- Up and down from the portrait's centre (or the bars' middle): the frame reaches from the
    -- portrait's top or the name's, whichever is higher, to the lower of the two bottoms.
    local topY = math.min(-diameter / 2, -blockHeight / 2 - nameHeight)
    local bottomY = math.max(diameter / 2, blockHeight / 2)
    local homeHeight = Round(bottomY - topY, pixel)
    -- Where the bars' frames start: behind the ring.
    local tuck = diameter > 0 and diameter - ring - pixel or 0
    local homeWidth = tuck + width + 2 * reach

    -- The home places (no offsets), down from the home box's top left; then each moved by its own
    -- offset (right and up are +).
    local portraitY = Round(-topY, pixel)
    local portraitX = self.side == "left" and diameter / 2 or homeWidth - diameter / 2
    local stackX = self.side == "left" and tuck + reach or reach
    local stackY = Round(portraitY - blockHeight / 2 + reach, pixel)
    portraitX, portraitY = portraitX + Round(offsets.portraitX, pixel), portraitY - Round(offsets.portraitY, pixel)
    stackX, stackY = stackX + Round(offsets.barsX, pixel), stackY - Round(offsets.barsY, pixel)

    -- The frame: what the portrait and the bars (with the name over them) cover.
    local boxLeft, boxTop = stackX - reach, stackY - reach - nameHeight
    local boxRight, boxBottom = stackX + width + reach, stackY + stackHeight + reach
    if diameter > 0 then
        boxLeft, boxTop = math.min(boxLeft, portraitX - diameter / 2), math.min(boxTop, portraitY - diameter / 2)
        boxRight, boxBottom = math.max(boxRight, portraitX + diameter / 2), math.max(boxBottom, portraitY + diameter / 2)
    end
    boxLeft, boxTop = Round(boxLeft, pixel), Round(boxTop, pixel)
    boxRight, boxBottom = Round(boxRight, pixel), Round(boxBottom, pixel)
    self.box = { home = { 0, 0, homeWidth, homeHeight }, used = { boxLeft, boxTop, boxRight, boxBottom } }
    if not InCombatLockdown() then root:SetSize(boxRight - boxLeft, boxBottom - boxTop) end

    local stack = self.stack
    stack:ClearAllPoints()
    stack:SetPoint("TOPLEFT", root, "TOPLEFT", Round(stackX - boxLeft, pixel), -(stackY - boxTop))
    stack:SetSize(width, stackHeight)
    if diameter > 0 then
        portrait.frame:ClearAllPoints()
        portrait.frame:SetPoint("CENTER", root, "TOPLEFT", Round(portraitX - boxLeft, pixel), -(portraitY - boxTop))
    end
    -- On a frame that can show the elite dragon, how much of the bars' portrait end it may reach
    -- over: the name, and what hangs above and below the bars, stop short of it.
    local clear = 0
    if settings.dragons and diameter > 0 then
        -- From the portrait's centre to the bars' near end.
        local near = self.side == "left" and stackX - portraitX or portraitX - (stackX + width)
        clear = math.max(0, Round(portrait:DragonNear() - near + 2 * pixel, pixel))
    end
    self.geo = { width = width, stackHeight = stackHeight, reach = reach, pixel = pixel, portrait = diameter, ring = ring,
        nameHeight = nameHeight, clear = clear,
        portraitY = portraitY - stackY, -- the portrait's centre, down from the stack's top
        left = Round(stackX - boxLeft, pixel), right = Round(boxRight - stackX - width, pixel) } -- either side of the stack

    -- Health on top, power under it, each in its frame.
    local healthBar, powerBar = self.health.bar, self.power.bar
    healthBar:ClearAllPoints()
    healthBar:SetPoint("TOPLEFT", stack, "TOPLEFT", 0, 0)
    healthBar:SetSize(width, healthHeight)
    powerBar:ClearAllPoints()
    powerBar:SetShown(powerHeight > 0)
    if powerHeight > 0 then
        powerBar:SetPoint("TOPLEFT", stack, "TOPLEFT", 0, -(healthHeight + gap))
        powerBar:SetSize(width, powerHeight)
    end
    self.health:ApplyTexture(settings.healthTexture)
    self.power:ApplyTexture(settings.powerTexture)
    self.healthBox:Apply()
    self.powerBox:Apply()

    -- The name: above the health bar at the portrait's end ("above"), on the bar at that end ("inside",
    -- in place of that end's text), or not at all. The level: the badge, or above the bars' far end.
    local near, far = "LEFT", "RIGHT"
    if self.side == "right" then near, far = "RIGHT", "LEFT" end
    local sign = near == "LEFT" and 1 or -1
    local nameText, levelText = self.nameText, self.levelText
    ns.SetNameFont(nameText, db.font, settings.nameSize, db.outline)
    ns.SetFont(levelText, db.font, settings.nameSize, db.outline)
    nameText:ClearAllPoints()
    levelText:ClearAllPoints()
    nameText:SetJustifyH(near)
    local levelRoom = levelAbove and math.floor(settings.nameSize * 2.2) or 0
    if settings.namePos == "inside" then
        nameText:SetPoint(near, healthBar, near, 4 * sign + offsets.nameX, offsets.nameY)
        nameText:SetWidth(math.max(10, width * 0.55))
        NameColour(nameText, 1, 1, 1)
    else
        nameText:SetPoint("BOTTOM" .. near, healthBar, "TOP" .. near, sign * (1 + clear) + offsets.nameX,
            reach + pixel + offsets.nameY)
        -- Cut short at the bars' end, or (nameFull) as long as it is, over the portrait.
        nameText:SetWidth(settings.nameFull and 0 or math.max(10, width - levelRoom - clear - 2))
        nameText:SetWordWrap(false)
        NameColour(nameText, 1, 0.82, 0)
    end
    self.nameShown = settings.namePos == "above" or settings.namePos == "inside"
    nameText:SetShown(self.nameShown)
    levelText:SetPoint("BOTTOM" .. far, healthBar, "TOP" .. far, -sign + offsets.levelX, reach + pixel + offsets.levelY)
    levelText:SetShown(levelAbove)
    self.levelAbove = levelAbove
    portrait.badge:SetShown(diameter > 0 and settings.showLevel)
    portrait.level:SetTextColor(1, 0.82, 0)
    -- The bar's end the name sits on, when it's inside.
    self.nameSlot = settings.namePos == "inside" and (near == "LEFT" and "Left" or "Right") or nil

    -- The bars' text slots: each at its end of the bar (or the middle), moved by its own offsets
    -- (healthLeftX, healthX, healthRightX ... and the Ys); the power bar's no taller than the bar.
    for bar, barFrame in pairs({ health = healthBar, power = powerBar }) do
        local size = settings.textSize
        if bar == "power" then size = math.max(6, math.min(size, settings.powerHeight + 1)) end
        for _, slot in ipairs(SLOTS) do
            local text = self.texts[bar][slot]
            ns.SetFont(text, db.font, size, db.outline)
            text:ClearAllPoints()
            local nudgeX, nudgeY = offsets[bar .. slot .. "X"] or 0, offsets[bar .. slot .. "Y"] or 0
            local anchor = slot == "Left" and "LEFT" or slot == "Right" and "RIGHT" or "CENTER"
            text:SetPoint(anchor, barFrame, anchor, nudgeX, nudgeY)
        end
    end

    -- The glow starts at the bars' frames' outline.
    if self.glow then self.glow:Place(stack, reach) end

    self:LayoutIcons()
    self:LayoutAround()
end

-- Icons round the portrait (or the outer end of the bars, with no portrait): the raid mark on its
-- top, the leader's crown at its upper outer edge, the PvP badge beside it, combat (yours) below.
function Unit:LayoutIcons()
    local size = ns.db.icons.size
    local icons, portrait, geo = self.icons, self.portrait, self.geo
    local out = self.side == "left" and -1 or 1 -- away from the bars
    local outer = self.side == "left" and "LEFT" or "RIGHT"
    for _, icon in pairs(icons) do icon:ClearAllPoints() end
    icons.leader:SetSize(size, size)
    icons.status:SetSize(size * 1.2, size * 1.2)
    icons.pvp:SetSize(size * 1.6, size * 1.6)
    if icons.role then icons.role:SetSize(size, size) end
    if self.portraitShown then
        local portraitFrame, diameter = portrait.frame, geo.portrait
        icons.raid:SetPoint("CENTER", portraitFrame, "TOP", 0, 0)
        icons.leader:SetPoint("CENTER", portraitFrame, "CENTER", -out * diameter * 0.30, diameter * 0.41)
        icons.status:SetPoint("CENTER", portraitFrame, "CENTER", -out * diameter * 0.08, -diameter * 0.46)
        icons.pvp:SetPoint("CENTER", portraitFrame, "CENTER", out * (diameter * 0.5 + size * 0.55), diameter * 0.06)
        -- The role: at the portrait's lower edge, on the bars' side (the level badge is on the other).
        if icons.role then icons.role:SetPoint("CENTER", portraitFrame, "CENTER", -out * diameter * 0.38, -diameter * 0.36) end
        -- The pet's happiness: at the portrait's top outer corner, sized to the portrait.
        if icons.happiness then
            local offsets = self.settings.offsets
            icons.happiness:SetSize(diameter * 0.5, diameter * 0.5)
            icons.happiness:SetPoint("CENTER", portraitFrame, "CENTER", out * diameter * 0.38 + (offsets.happinessX or 0),
                diameter * 0.38 + (offsets.happinessY or 0))
        end
    else
        local stack = self.stack
        icons.raid:SetPoint("CENTER", stack, outer, out * (geo.reach + size * 0.6), 0)
        icons.leader:SetPoint("CENTER", stack, "TOP" .. outer, 0, geo.reach)
        icons.status:SetPoint("CENTER", stack, "BOTTOM" .. outer, 0, 0)
        icons.pvp:SetPoint("CENTER", stack, outer, out * (geo.reach + size * 1.4), 0)
        if icons.role then icons.role:SetPoint("CENTER", stack, "TOP" .. outer, -out * size, geo.reach) end
        if icons.happiness then
            local offsets = self.settings.offsets
            icons.happiness:SetSize(size, size)
            icons.happiness:SetPoint("CENTER", stack, "TOP" .. outer, (offsets.happinessX or 0),
                geo.reach + (offsets.happinessY or 0))
        end
    end
    -- Resting (yours): at the portrait's top outer corner, or beside the level badge, nudged by
    -- the rest offsets.
    local rest = self.rest
    if rest then
        local settings = self.settings
        local offsets = settings.offsets
        local diameter = geo.portrait > 0 and geo.portrait or 40
        local restSize = math.max(12, diameter * (rest.animated and 0.5 or 0.36))
        rest:SetSize(restSize, restSize)
        rest:ClearAllPoints()
        if not self.portraitShown then
            rest:SetPoint("BOTTOM" .. outer, self.stack, "TOP" .. outer, offsets.restX, geo.reach + offsets.restY)
        elseif settings.restPos == "badge" then
            rest:SetPoint("CENTER", portrait.frame, "CENTER", -out * diameter * 0.08 + offsets.restX,
                -diameter * 0.46 + offsets.restY)
        else
            rest:SetPoint("CENTER", portrait.frame, "CENTER", out * diameter * 0.36 + offsets.restX,
                diameter * 0.38 + offsets.restY)
        end
    end
end

-- What hangs off the bars, each above or below them, nearest first: your druid mana, the combo points,
-- the cast bar "next to the bars", the aura rows, the cast bar "beyond" them. Laid out again when a row
-- empties or fills, or the druid bar comes or goes; they stop short of where an elite dragon reaches.
local function Side(value) return value == "above" and "above" or "below" end
local ORDERS = { buffs = { "buffs", "debuffs" }, debuffs = { "debuffs", "buffs" } }
local ROW_OFFSETS = { debuffs = { "debuffsX", "debuffsY" }, buffs = { "buffsX", "buffsY" } }

-- Places a thing `height` tall on a side, after what went there before in this layout (boxed things have a
-- frame round them). y is up from the stack's top. Returns the y of its top (inside its frame).
function Unit:Put(side, height, boxed, aura)
    local edge, last, geo = self.edge, self.last, self.geo
    local space = (aura and last[side] == "aura") and (self.settings.auras.rowGap or 4) or (aura and 4 or 3)
    local frame = boxed and geo.reach or 0
    local y
    if side == "above" then
        local bottom = edge.above + space
        y = bottom + frame + height
        edge.above = bottom + height + 2 * frame
    else
        local topEdge = edge.below - space
        y = topEdge - frame
        edge.below = topEdge - height - 2 * frame
    end
    last[side] = aura and "aura" or "box"
    return Round(y, geo.pixel)
end

function Unit:PlaceCast(x, height)
    local holder, settings = self.cast.holder, self.settings
    holder:ClearAllPoints()
    holder:SetPoint("TOPLEFT", self.stack, "TOPLEFT", x + settings.offsets.castX,
        self:Put(Side(settings.cast.side), height, true) + settings.offsets.castY)
end

-- Places an aura row on a side via Put: below, its top; above, its bottom line's bottom (it wraps upwards from
-- there, the timers under each line). Its lines: the samples' while unlocked, the unit's auras when the game says
-- how many, else room for all of them (a row that wraps only takes more than one line then).
function Unit:PutRow(spec, side, rowSettings, row)
    local count = self.counts[row] or rowSettings.max
    if not ns.db.locked then count = ns.AuraSampleCount(row, rowSettings) end
    local height = ns.AuraBlockHeight(rowSettings, self.settings.auras, ns.AuraLines(rowSettings, count))
    local top = self:Put(side, height, false, true)
    if side == "above" then
        spec.up = true
        spec.point = spec.point == "TOPRIGHT" and "BOTTOMRIGHT" or "BOTTOMLEFT"
        spec.y = top - height + (ns.AuraRowHeight(rowSettings) - rowSettings.size) -- above the timers, when they're under
    else
        spec.y = top
    end
end

-- A row's spec for Auras:Apply: the same table each layout, set out afresh.
local function Spec(specs, row, rowSettings, anchor, shown)
    local spec = specs[row]
    if not spec then
        spec = {}
        specs[row] = spec
    end
    spec.cfg, spec.anchor, spec.shown, spec.point, spec.grow = rowSettings, anchor, shown, "TOPLEFT", "RIGHT"
    spec.up, spec.x, spec.y = nil, 0, 0
    return spec
end

function Unit:LayoutAround()
    local settings, db, geo = self.settings, ns.db, self.geo
    local offsets = settings.offsets
    if not geo then return end
    local stack, reach, pixel = self.stack, geo.reach, geo.pixel
    local vanilla = self.vanillaShown
    if self.rule then self.rule.bar = nil end -- the rule's strip placed afresh, at the new pixel size

    -- Each side's edge, from which the next thing goes: below, under the bars' frames; above, over the name;
    -- and what went last on each side ("aura" or "box"), for the gap to the next.
    local edge, last = self.edge, self.last
    edge.below, edge.above = -(geo.stackHeight + reach), reach + geo.nameHeight
    last.below, last.above = nil, nil
    -- Across: from x, `width` wide (the bars' width, less what the dragon may cover at the portrait's end).
    local clear = geo.clear
    local x, width = 0, geo.width - clear
    if self.side == "left" then x = clear end
    self.aroundX, self.aroundWidth = x, width

    -- Each part's size, frame, texture and fonts only change with the settings (and the pixel size): styled
    -- again only then, not on every fold of an aura row.
    if self.druid then
        local height = ns.Snap(settings.druidManaHeight, pixel)
        local holder = self.druidHolder
        -- Its text at its own size (druidTextSize; 0: the bar text's, no taller than the bar), at
        -- its ends and middle.
        local size = (settings.druidTextSize or 0) > 0 and settings.druidTextSize
            or math.max(6, math.min(settings.textSize, settings.druidManaHeight + 1))
        if ns.Changed(holder, width, height, pixel, size, db.look, db.texture, db.frameThickness, db.font,
            db.outline, settings.powerTexture, settings.vanillaTextures, vanilla) then
            holder:SetSize(width, height)
            self.druidBox:Apply()
            self.druid:ApplyTexture(settings.powerTexture)
            -- In the vanilla frame: the art's bar slot round it.
            if vanilla then self:VanillaDruid(true) end
            for _, slot in ipairs(SLOTS) do
                local text = self.texts.druid[slot]
                ns.SetFont(text, db.font, size, db.outline)
                text:ClearAllPoints()
                local anchor = slot == "Left" and "LEFT" or slot == "Right" and "RIGHT" or "CENTER"
                text:SetPoint(anchor, holder, anchor, slot == "Left" and 2 or slot == "Right" and -2 or 0, 0)
            end
        end
        if self.druidShown then
            holder:ClearAllPoints()
            holder:SetPoint("TOPLEFT", stack, "TOPLEFT", x + offsets.druidX,
                self:Put(Side(settings.druidManaSide), height, true) + offsets.druidY)
        end
    end

    self.comboY = nil
    if ns.Combo:On(self.kind) then
        self.comboY = self:Put(Side(db.combo.side), ns.Combo:PipHeight(self), true)
    end

    -- The frame's own cast bar (target, focus; yours once it's switched on).
    local cast, castSettings = self.cast, settings.cast
    local castOn, castHeight, iconWidth
    if cast then
        castOn = castSettings.enabled
        castHeight = ns.Snap(castSettings.height or 11, pixel)
        -- Its width: the bars' (width 0) or its own, the icon (in its frame) at its start.
        local castWidth = (castSettings.width or 0) > 0 and ns.Snap(castSettings.width, pixel) or width
        iconWidth = castSettings.icon and castHeight + 2 * reach + 2 * pixel or 0
        local holderWidth, iconX = math.max(pixel * 10, castWidth - iconWidth), -(2 * reach + 2 * pixel)
        local textSize = math.max(8, settings.textSize)
        if ns.Changed(cast, holderWidth, castHeight, iconX, castSettings.icon, db.look, db.texture,
            db.frameThickness, db.font, db.outline, textSize, settings.vanillaTextures, vanilla) then
            cast.holder:SetSize(holderWidth, castHeight)
            cast.iconFrame:SetSize(castHeight, castHeight)
            cast.iconFrame:ClearAllPoints()
            cast.iconFrame:SetPoint("TOPRIGHT", cast.holder, "TOPLEFT", iconX, 0)
            cast.iconFrame:SetShown(castSettings.icon and true or false)
            cast.iconBox:Apply()
            cast.box:Apply()
            cast.gauge:ApplyTexture()
            ns.SetFont(cast.label, db.font, textSize, db.outline)
            ns.SetFont(cast.time, db.font, textSize, db.outline)
            -- In the vanilla frame: Classic's small cast bar frame round it.
            self:VanillaCast(vanilla)
        end
        if castOn and castSettings.position ~= "beyond" then self:PlaceCast(x + iconWidth, castHeight) end
    end

    if self.auras then
        local auras = settings.auras -- the frame's own aura settings
        local specs = self.auraSpecs or {}
        self.auraSpecs = specs
        if self.kind == "party" then
            -- The party's debuffs go on any side.
            local debuffs = auras.debuffs
            local shown = auras.enabled and debuffs.enabled and (not db.locked or not (auras.fold and self.empty.debuffs))
            local spec = Spec(specs, "debuffs", debuffs, stack, shown)
            if debuffs.side == "left" then
                spec.point, spec.grow = "TOPRIGHT", "LEFT"
                local badge = 0
                if self.portraitShown and self.side == "left" then
                    local _, outwards = self.portrait:BadgeReach()
                    badge = math.max(0, outwards)
                end
                spec.x = -(geo.left + badge + 4)
                spec.y = -math.floor((geo.stackHeight - debuffs.size) / 2)
            elseif debuffs.side == "above" or debuffs.side == "below" then
                spec.x = x
                self:PutRow(spec, debuffs.side, debuffs, "debuffs")
            else
                spec.x = geo.width + geo.right + 4
                spec.y = -math.floor((geo.stackHeight - debuffs.size) / 2)
            end
            spec.x, spec.y = spec.x + offsets.debuffsX, spec.y + offsets.debuffsY
        else
            for _, row in ipairs(ORDERS[auras.order] or ORDERS.debuffs) do
                local rowSettings = auras[row]
                local shown = auras.enabled and rowSettings.enabled and (not db.locked or not (auras.fold and self.empty[row]))
                local spec = Spec(specs, row, rowSettings, stack, shown)
                spec.x = x
                if shown then self:PutRow(spec, Side(rowSettings.side), rowSettings, row) end
                local keys = ROW_OFFSETS[row]
                spec.x, spec.y = spec.x + offsets[keys[1]], spec.y + offsets[keys[2]]
            end
        end
        self.auras:Apply(self.content, specs)
        self.auras:Preview(self.content, specs, not db.locked)
    end

    if castOn and castSettings.position == "beyond" then self:PlaceCast(x + iconWidth, castHeight) end
    -- The combo points, on the frame they go by (a change of settings lays them out from ns.Combo:Apply).
    if self.kind == db.combo.on then ns.Combo:Layout() end
end

-- After a change of unit or of its auras: lays them out again if a row has opened or closed.
-- Also when a row that wraps gains or loses a line. A row that's off can't do either.
function Unit:CheckEmpty()
    if not self.auras or not self.auraSpecs then return end
    local relayout, auras = false, self.settings.auras
    for row in pairs(self.empty) do
        local spec = self.auraSpecs[row]
        if spec and auras.enabled and spec.cfg.enabled then
            local now = not self.auras:HasAny(row, spec.cfg)
            if now ~= self.empty[row] then
                self.empty[row] = now
                if auras.fold then relayout = true end
            end
            -- A row that wraps: how many it has decides its height. One that can't wrap is always one line, so
            -- its auras needn't be counted (up to a call per aura, on every change).
            if Wraps(spec.cfg) then
                local count = self.auras:Count(row, spec.cfg)
                local before = self.counts[row] or spec.cfg.max
                self.counts[row] = count
                if ns.AuraLines(spec.cfg, count or spec.cfg.max) ~= ns.AuraLines(spec.cfg, before) then relayout = true end
            end
        end
    end
    if relayout then self:LayoutAround() end
end

------------------------------------------------------------------------------
-- Updates
------------------------------------------------------------------------------

-- The unit to draw: the real one, or nil for a sample (unlocked, no unit). false: nothing.
function Unit:Shown()
    local exists = UnitExists(self.unit)
    if issecret(exists) or exists then return self.unit end
    if not ns.db.locked and self:Enabled() then return nil end
    return false
end

-- same: the poll for a unit with no events of its own (your target's target) found the same unit as before, so
-- what can't change for it (its name, its elite or rare art, its icons but a PvP flag) is left as it is.
function Unit:Update(full, same)
    if not self.rootShown then return end
    local unit = self:Shown()
    if unit == false then return end
    self.shownUnit = unit
    local settings, sample = self.settings, self.sample
    if full then
        if self.poll then
            local guid = unit and UnitGUID(unit)
            if issecret(guid) then self.guid = nil else self.guid = guid end
            self.lastFull = GetTime()
        end
        if unit then self:CheckGroup() end
        if self.rest then resting = IsResting() end
    end

    self:UpdateHealth(full, true)
    self:UpdatePower(full, true)

    -- Name and level (in the badge, or above the bars with no portrait).
    local fake = not unit and sample or nil
    if same then
        -- (the name's as it was)
    elseif self.nameShown then
        ns.SetUnitText(self.nameText, "name", unit, fake)
    else
        self.nameText:Hide()
    end
    local vanilla = self.vanillaShown
    if vanilla then
        if settings.showLevel then ns.SetUnitText(self.levelText, "level", unit, fake) end
    elseif settings.showLevel and self.portraitShown then
        ns.SetUnitText(self.portrait.level, "level", unit, fake)
    elseif self.levelAbove then
        ns.SetUnitText(self.levelText, "level", unit, fake)
    end

    if full then self:UpdatePortrait() end
    -- The dragon round an elite's or rare's portrait (the vanilla frame's is in its art); the same unit's stays.
    if same then
        -- (as it was)
    elseif vanilla then
        self.dragonShown = false
        if settings.dragons ~= nil then self.portrait:SetDragon(nil) end
        local classification = sample.classification
        if unit then classification = UnitClassification(unit) end
        self:VanillaArt(classification)
        self:VanillaNameColour(unit)
    elseif self.portraitShown and settings.dragons then
        -- The classification may be secret: handed on untested (SetDragon reads it safely).
        local classification = sample.classification
        if unit then classification = UnitClassification(unit) end
        self.dragonShown = self.portrait:SetDragon(classification)
    elseif settings.dragons ~= nil then
        self.dragonShown = self.portrait:SetDragon(nil)
    end
    -- Raid marks and the group's leader and roles have events of their own; a PvP flag on your target's target hasn't.
    if not same or ns.db.icons.pvp then self:UpdateIcons() end
    self:UpdateGlow()
    self:UpdateRange()
    -- Whether it's idle now: a unit that turns up already at rest (a pet summoned at full health
    -- and focus) sends no health or power change to look again on.
    self:UpdateFade()
    if full then
        if self.cast then self:UpdateCast() end
        if self.auras then
            self.auras:UnitChanged()
            self:CheckEmpty()
        end
    end
end

-- Who the unit is to you, for the range check: you (always in range), or in your group (the game's group
-- range check). Kept from full updates and roster changes, not asked on every poll. A change redraws the range
-- at once, as the frame may leave the poll with it (someone leaving the group in a fight).
function Unit:CheckGroup()
    local unit = self.unit
    if unit == "player" then return end -- (always you)
    local isMe = Safe(UnitIsUnit(unit, "player")) and true or false
    local grouped = (self.partyUnit or Safe(UnitInParty(unit)) or Safe(UnitInRaid(unit))) and true or false
    if isMe == self.isMe and grouped == self.grouped then return end
    self.isMe, self.grouped = isMe, grouped
    self:UpdateRange()
    ns.UpdateTicker()
end

local HEALTH_VALUES = {} -- what was read for the health bar, for its text (ns.SetUnitText's values)

-- recolour: the bar's colour and the offline state are worked out again; else kept from the last time (what they
-- come from arrives with UNIT_FACTION, UNIT_FLAGS, UNIT_CONNECTION and new units, which all recolour).
function Unit:UpdateHealth(instant, recolour)
    local unit = self.shownUnit
    if unit == false then return end
    local settings, sample, texts = self.settings, self.sample, self.texts.health
    local r, g, b = self.healthR, self.healthG, self.healthB
    local values
    if unit then
        local value, max = UnitHealth(unit), UnitHealthMax(unit)
        self.health:SetValues(value, max, instant)
        if recolour or not r then r, g, b = HealthColor(unit) end
        values = HEALTH_VALUES
        values.value, values.max = value, max
    else
        self.health:SetValues(sample.value, sample.max, true)
        local color = ns.db.healthColor == "green" and GREEN or sample.color
        r, g, b = color.r, color.g, color.b
    end
    self.healthR, self.healthG, self.healthB = r, g, b
    self.health:SetColor(r, g, b)
    self:UpdatePredict()
    -- The name above the bars: gold like the game's, white, or in the health bar's colour.
    if settings.namePos == "above" then
        local mode = ns.db.nameColor
        if mode == "unit" then
            NameColour(self.nameText, r + (1 - r) * 0.25, g + (1 - g) * 0.25, b + (1 - b) * 0.25)
        elseif mode == "white" then
            NameColour(self.nameText, 1, 1, 1)
        else
            NameColour(self.nameText, 1, 0.82, 0)
        end
    end

    -- Dead, a ghost or offline: said in the middle of the bar instead of the numbers.
    local status
    if unit then
        if recolour or self.offline == nil then self.offline = Safe(UnitIsConnected(unit)) == false end
        if self.offline then
            status = PLAYER_OFFLINE or "Offline"
        elseif Safe(UnitIsDeadOrGhost(unit)) then
            status = Safe(UnitIsGhost(unit)) and (GHOST or "Ghost") or (DEAD or "Dead")
        end
    end
    local keys = TEXT_KEYS.health
    for i, slot in ipairs(SLOTS) do
        local text = texts[slot]
        if status then
            if slot == "" then
                text:SetText(status)
                text:Show()
                text.ffHidden = nil
            else
                ns.HideText(text)
            end
        elseif slot == self.nameSlot then
            ns.HideText(text) -- the name is there
        else
            ns.SetUnitText(text, settings.text[keys[i]], unit, not unit and sample or nil, nil, nil, values)
        end
    end
    if values then values.value, values.max = nil, nil end
end

-- Druids in a form: whether the form's rage or energy is showing instead of mana.
local function InForm()
    if PlayerClass() ~= "DRUID" then return false end
    local kind = Safe(UnitPowerType("player"))
    return kind ~= nil and kind ~= MANA
end

-- recolour: the power's kind may have changed (UNIT_DISPLAYPOWER, a new unit): its colour, and which bar the
-- five-second rule goes under, are worked out again.
function Unit:UpdatePower(instant, recolour)
    local unit = self.shownUnit
    if unit == false then return end
    local settings, sample, texts = self.settings, self.sample, self.texts.power
    if settings.powerHeight > 0 then
        if unit then
            self.power:SetValues(UnitPower(unit), UnitPowerMax(unit), instant)
        else
            self.power:SetValues(sample.power.value, sample.power.max, true)
        end
        if recolour then self.power:SetColor(Color.Power(unit)) end
        local keys = TEXT_KEYS.power
        for i, slot in ipairs(SLOTS) do
            ns.SetUnitText(texts[slot], settings.text[keys[i]], unit, not unit and sample.power or nil, true)
        end
    else
        for _, slot in ipairs(SLOTS) do ns.HideText(texts[slot]) end
    end

    if self.druid then
        -- Unlocked, a druid sees it in any form, so it can be placed.
        local inForm = InForm()
        local druidSample = not ns.db.locked and PlayerClass() == "DRUID"
        local show = settings.druidMana and ((unit ~= nil and inForm) or druidSample)
        if show and inForm then
            self.druid:SetValues(UnitPower("player", MANA), UnitPowerMax("player", MANA), instant)
        elseif show then
            self.druid:SetValues(70, 100, true)
        end
        -- Its text: your mana's (the words' power is mana, whatever the form shows).
        local keys = TEXT_KEYS.druid
        for i, slot in ipairs(SLOTS) do
            local text = self.texts.druid[slot]
            if show then
                ns.SetUnitText(text, settings.text[keys[i]], inForm and "player" or nil,
                    not inForm and DRUID_SAMPLE or nil, true, MANA)
            else
                ns.HideText(text)
            end
        end
        if show ~= self.druidShown then
            self.druidShown = show
            self.druidHolder:SetShown(show)
            self:LayoutAround()
            recolour = true -- the rule may go under it now, or no longer
        end
    end
    if recolour then self:UpdateRule() end
end

function Unit:UpdatePortrait()
    if not self.portraitShown then return end
    local unit = self.shownUnit
    if unit == false then return end
    self.portrait:Set(unit, self.settings.portrait)
end

-- Raid marks (FrogLib.Icons: which mark can be secret, so it's written into text), leader,
-- resting / fighting (you), PvP. unit nil: samples. Each icon's art is written only when it changes
-- (ffArt: what's on it), as this runs on every update.
local PVP_COORDS = { 0.08, 0.58, 0.045, 0.545 } -- the PvP badges sit in the corner of a larger file
local STATE = "Interface\\CharacterFrame\\UI-StateIcon"
local LEADER, ASSISTANT = "Interface\\GroupFrame\\UI-Group-LeaderIcon", "Interface\\GroupFrame\\UI-Group-AssistantIcon"

local function ShowRaid(text, unit, size)
    if not unit then return Icons.SetRaidMark(text, 1, size) end -- the sample: a star
    return Icons.RaidMark(text, unit, size)
end

local function ShowLeader(texture, unit)
    local file
    if not unit or Safe(UnitIsGroupLeader(unit)) then
        file = LEADER
    elseif Safe(UnitIsGroupAssistant(unit)) then
        file = ASSISTANT
    end
    if not file then return false end
    if texture.ffArt ~= file then
        texture.ffArt = file
        texture:SetTexture(file)
    end
    return true
end

local function ShowStatus(texture)
    if not Safe(UnitAffectingCombat("player")) then return false end
    if texture.ffArt ~= STATE then
        texture.ffArt = STATE
        texture:SetTexture(STATE)
        texture:SetTexCoord(0.5, 1, 0, 0.484375)
    end
    return true
end

local function ShowPvP(texture, unit)
    local file
    if Safe(UnitIsPVPFreeForAll(unit)) then
        file = "Interface\\TargetingFrame\\UI-PVP-FFA"
    elseif Safe(UnitIsPVP(unit)) then
        local faction = Safe(UnitFactionGroup(unit))
        if faction == "Horde" or faction == "Alliance" then file = "Interface\\TargetingFrame\\UI-PVP-" .. faction end
    end
    if not file then return false end
    if texture.ffArt ~= file then
        texture.ffArt = file
        texture:SetTexture(file)
        texture:SetTexCoord(PVP_COORDS[1], PVP_COORDS[2], PVP_COORDS[3], PVP_COORDS[4])
    end
    return true
end

-- The group role: the group finder's own role icons; in a raid with no role, a main tank or main
-- assist's mark instead. Samples while unlocked (the party: a tank, a healer, then damage).
local ROLE_ATLAS = { TANK = "groupfinder-icon-role-large-tank", HEALER = "groupfinder-icon-role-large-heal",
    DAMAGER = "groupfinder-icon-role-large-dps" }
local SAMPLE_ROLES = { "TANK", "HEALER", "DAMAGER", "DAMAGER" }
local roleAtlases = {} -- [atlas] = whether the client has it (asked once each)

local function ShowRole(texture, unit, kind, index)
    local role
    if unit then
        role = Safe(UnitGroupRolesAssigned(unit))
    elseif not ns.db.locked then
        role = kind == "party" and SAMPLE_ROLES[index or 1] or "DAMAGER"
    end
    if role == "DAMAGER" and not ns.db.icons.roleDamage then role = nil end
    local atlas = ROLE_ATLAS[role or ""]
    if atlas then
        local known = roleAtlases[atlas]
        if known == nil then
            known = C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(atlas) ~= nil or false
            roleAtlases[atlas] = known
        end
        if known then
            if texture.ffArt ~= atlas then
                texture.ffArt = atlas
                texture:SetTexCoord(0, 1, 0, 1)
                texture:SetAtlas(atlas)
            end
            return true
        end
    end
    if unit and IsInRaid() and GetPartyAssignment then
        local file
        if Safe(GetPartyAssignment("MAINTANK", unit)) then
            file = "Interface\\GroupFrame\\UI-Group-MainTankIcon"
        elseif Safe(GetPartyAssignment("MAINASSIST", unit)) then
            file = "Interface\\GroupFrame\\UI-Group-MainAssistIcon"
        end
        if file then
            if texture.ffArt ~= file then
                texture.ffArt = file
                texture:SetTexture(file)
                texture:SetTexCoord(0, 1, 0, 1)
            end
            return true
        end
    end
    return false
end

-- An icon shown or hidden only when that changes (this runs on every update; only it shows or hides them).
local function Toggle(icon, on)
    on = on and true or false
    if icon.ffShown == on then return end
    icon:SetShown(on)
    icon.ffShown = on
end

function Unit:UpdateIcons()
    local unit = self.shownUnit
    if unit == false then return end
    local iconSettings, icons = ns.db.icons, self.icons
    local size = iconSettings.size
    Toggle(icons.raid, iconSettings.raid and ShowRaid(icons.raid, unit, size))
    local leader = iconSettings.leader and (unit ~= nil or self.kind == "party" and self.index == 1)
    Toggle(icons.leader, leader and ShowLeader(icons.leader, unit))
    local status = iconSettings.status and self.kind == "player" and ShowStatus(icons.status)
    Toggle(icons.status, status)
    if self.rest then
        local shown = resting or not ns.db.locked -- a sample while unlocked, to place it
        self:ShowRest(iconSettings.status and self.settings.restPos ~= "none" and shown and not status)
    end
    -- Players only: faction guards are flagged too, and a badge on every guard is noise.
    Toggle(icons.pvp, iconSettings.pvp and unit ~= nil and Safe(UnitIsPlayer(unit)) and ShowPvP(icons.pvp, unit))
    if icons.happiness then
        Toggle(icons.happiness, iconSettings.happiness and self:ShowHappiness(unit))
    end
    if icons.role then
        Toggle(icons.role, iconSettings.role and ShowRole(icons.role, unit, self.kind, self.index))
    end
end

-- A hunter's pet only (FrogLib.Unit: others have no happiness), in the game's own faces; a
-- happy sample while unlocked.
function Unit:ShowHappiness(unit)
    local happiness
    if unit then happiness = FrogLib.Unit.PetHappiness() end
    if not happiness and unit == nil and not ns.db.locked then happiness = 3 end
    local atlas = FrogLib.Unit.HAPPINESS_ATLAS[happiness]
    if not atlas then return false end
    local texture = self.icons.happiness
    if texture.ffArt ~= atlas then
        texture.ffArt = atlas
        texture:SetAtlas(atlas)
    end
    return true
end

-- The soft glow round the bars and the portrait: threat (player, party: yellow to red while
-- enemies are on them), and on your own frame, if wanted, gold while resting and red while fighting.
-- Only those kinds have one.
function Unit:UpdateGlow()
    local glow = self.glow
    if not glow then return end
    local settings, unit = self.settings, self.shownUnit
    local r, g, b, a
    if unit and settings.threat then
        local status = Safe(UnitThreatSituation(unit))
        if status and status > 0 and GetThreatStatusColor then
            r, g, b = GetThreatStatusColor(status)
            a = 0.85
        end
    end
    if not r and unit and settings.glow then
        if Safe(UnitAffectingCombat("player")) then
            r, g, b, a = 1, 0.15, 0.1, 0.6
        elseif resting then
            r, g, b, a = 1, 0.82, 0.2, 0.5
        end
    end
    glow:SetShown(r ~= nil)
    if r then glow:SetColor(r, g, b, a) end
    -- The halo only when it changes: this runs on every update.
    local halo = self.portrait.halo
    local haloShown = r ~= nil and self.portraitShown and true or false
    if r and (halo.ffR ~= r or halo.ffG ~= g or halo.ffB ~= b or halo.ffA ~= a) then
        halo:SetVertexColor(r, g, b, a)
        halo.ffR, halo.ffG, halo.ffB, halo.ffA = r, g, b, a
    end
    if halo.ffShown ~= haloShown then
        halo:SetShown(haloShown)
        halo.ffShown = haloShown
    end
end

-- Out of range (fadeRange): group members by the game's group range check, anyone else by the follow
-- distance, out of combat only (CheckInteractDistance is blocked in combat). Secret answers: the game's.
-- Who the unit is to you is kept by CheckGroup.
function Unit:InRange()
    if self.isMe then return true end
    local unit = self.unit
    if self.grouped and UnitInRange then
        local inRange, checked = UnitInRange(unit)
        if issecret(inRange) then return inRange end
        if issecret(checked) or checked then return inRange end
        return true -- not checked: elsewhere in the world, or you
    end
    if CheckInteractDistance and not InCombatLockdown() then
        local ok, near = pcall(CheckInteractDistance, unit, 4)
        if ok and (issecret(near) or near ~= nil) then return near end
    end
    return true
end

function Unit:UpdateRange()
    local content = self.content
    if not self.shownUnit or not self.settings.fadeRange then
        RangeAlpha(content, 1)
        return
    end
    local near = self:InRange()
    if issecret(near) then
        content.ffAlpha = nil
        if not (content.SetAlphaFromBoolean and pcall(content.SetAlphaFromBoolean, content, near, 1, ns.db.rangeAlpha)) then
            content:SetAlpha(1)
        end
    else
        RangeAlpha(content, near and 1 or ns.db.rangeAlpha)
    end
end

------------------------------------------------------------------------------
-- The cast bar (target, focus)
------------------------------------------------------------------------------

function Unit:UpdateCast(event, interruptedBy)
    local cast = self.cast
    if not cast then return end
    local unit = self.shownUnit
    if not self.settings.cast.enabled or unit == false then
        cast.holder:Hide()
        return
    end
    -- unit nil: a sample (unlocked, nobody there).
    cast.driver:Update(unit, event, not ns.db.locked, interruptedBy)
end

------------------------------------------------------------------------------
-- Fade when idle (fade): FrogLib.Idle's rule, as Personal Resource Tweaks fades its display; only the
-- fader (a plain child) changes, never the secure frame
------------------------------------------------------------------------------

-- The idle rule's options for this frame (one table, filled in each time).
function Unit:FadeOpts(unit)
    local opts, fade = self.fadeOpts, self.settings.fade
    opts.unit, opts.noTarget, opts.hover, opts.unlocked = unit, fade.noTarget, self.hover, not ns.db.locked
    return opts
end

-- force: set the opacity at once (a change of settings, unlocking). In a fight nothing is idle, so the rule
-- isn't asked; shown with nothing to change, nothing is done.
function Unit:UpdateFade(force)
    local fade, unit, fader = self.settings.fade, self.shownUnit, self.fade
    local idle, secret = false, false
    if fade.enabled and unit and not fighting then
        local _
        idle, _, secret = self.idle:Evaluate(self:FadeOpts(unit))
    elseif not force and fader.target == 1 and not fader.gate then
        return
    end
    fader:SetGate((idle and secret) and unit or nil)
    fader:Set(idle and fade.alpha or 1, force and "now" or nil)
end

-- /ff idle: whether this frame counts as idle now, and if not why; what its fade is doing.
function Unit:IdleReport()
    local fade, unit = self.settings.fade, self.shownUnit
    local idle, why, secret = false, "fade when idle is off", false
    if fade.enabled then
        if not unit then
            why = "no unit (a sample)"
        else
            idle, why, secret = self.idle:Evaluate(self:FadeOpts(unit))
        end
    end
    local fader = self.fade
    local alpha = self.fader:GetAlpha()
    ns.Print(string.format("%s (%s): %s%s; fading to %s, now %s, frame %s%s.", self.key, tostring(unit),
        idle and "idle" or "not idle", why and (": " .. why) or "", tostring(fader.target),
        string.format("%.2f", fader.now or -1), issecret(alpha) and "hidden by the game" or string.format("%.2f", alpha),
        fader.gate and (", through the full-health gate on " .. fader.gate) or ""))
end

-- A change to health or power: note it (when the frame fades), show the frame, and look again once things have
-- been quiet long enough to settle. A health change under the gate plays the fade again.
function Unit:Changed(kind)
    if self.settings.fade.enabled then self.idle:Changed(kind) end
    self:UpdateFade()
    if kind == "health" then self.fade:Replay() end
end

if EventRegistry then
    local function All()
        for _, frame in ipairs(ns.frameList or {}) do frame:UpdateFade() end
    end
    EventRegistry:RegisterCallback("EditMode.Enter", All, ns)
    EventRegistry:RegisterCallback("EditMode.Exit", All, ns)
end
