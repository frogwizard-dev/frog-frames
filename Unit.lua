local _, ns = ...

-- One unit frame: a round portrait with the level badge on its edge, and tucked in behind its
-- ring a health bar and a thinner power bar, each in its own frame, the name above them; its
-- icons; and for some kinds of frame a cast bar, auras, combo points, your druid mana or a glow,
-- each above or below the bars. Frames.lua makes one for each unit (ns.NewUnitFrame) and drives
-- them.
--
-- The frame itself (`root`) is a secure unit button: click to target, right-click for the unit
-- menu, shown and hidden by the game as its unit comes and goes (RegisterUnitWatch). It can only
-- be sized, placed and shown out of combat, so that's all done in Apply, which Core.lua holds
-- back until a fight ends. Everything drawn is on a plain child (`content`), so it can change
-- at any time: values, colours, icons, the range fade, and what hangs under the bars.
-- Values the game may keep secret (health, power, names, levels, raid marks, range, threat) only
-- ever go into widgets: status bars, SetFormattedText, SetAlphaFromBoolean.

local Unit = {}
Unit.__index = Unit

local issecret, Safe = ns.issecret, ns.Safe
local MANA = (Enum.PowerType and Enum.PowerType.Mana) or 0
-- Reading casts and when the cast bar shows (FrogLib.Cast), the idle fade's rule (FrogLib.Idle),
-- the colours (FrogLib.Color), raid marks (FrogLib.Icons) and the click buttons (FrogLib.Secure)
-- are shared with Frog Wizard's other add-ons.
local Cast, Color, Icons, Secure = FrogLib.Cast, FrogLib.Color, FrogLib.Icons, FrogLib.Secure

local SLOTS = { "Left", "", "Right" } -- the text slots on a bar: healthLeft, health, healthRight
local CAST_COLOR = { 1, 0.72, 0.3 }
local CAST_LOCKED = { 0.6, 0.6, 0.6 }

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

------------------------------------------------------------------------------
-- Samples, shown while unlocked where there's no unit
------------------------------------------------------------------------------

local SAMPLE_PARTY = {
    { name = "Thrall", class = "SHAMAN" }, { name = "Jaina", class = "MAGE" },
    { name = "Uther", class = "PALADIN" }, { name = "Rexxar", class = "HUNTER" },
}

local function Sample(kind, index)
    local s = { level = "60", value = 76, max = 100, percent = 76, color = REACTION.friendly }
    if kind == "target" then
        s.name, s.level, s.color, s.classification = "Hogger", "11", REACTION.hostile, "elite"
    elseif kind == "focus" then
        s.name, s.color, s.classification = "Training Dummy", REACTION.neutral, "rare"
    elseif kind == "tot" then
        s.name = UnitName("player") or "You"
    elseif kind == "pet" then
        s.name = "Wolf"
    elseif kind == "partypet" then
        s.name = "Imp"
    elseif kind == "party" then
        local p = SAMPLE_PARTY[index or 1]
        s.name = p.name
        local r, g, b = Color.Class(p.class)
        if r then s.color = { r = r, g = g, b = b } end
    end
    s.power = { name = s.name, level = s.level, value = 62, max = 100, percent = 62 }
    return s
end

local function Text(parent, justify)
    -- A default font up front: SetText errors on a FontString with none, and the configured
    -- font is only applied later in Layout.
    local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    fs:SetShadowOffset(1, -1)
    fs:SetShadowColor(0, 0, 0, 0.9)
    fs:SetWordWrap(false)
    if justify then fs:SetJustifyH(justify) end
    return fs
end

------------------------------------------------------------------------------
-- Build
------------------------------------------------------------------------------

-- def: { key = "party2", kind = "party", unit = "party2", index = 2, side = "left",
--        parent = "party1" (attached frames), event = "PLAYER_TARGET_CHANGED", poll = true }
function ns.NewUnitFrame(def)
    local u = setmetatable({}, Unit)
    for k, v in pairs(def) do u[k] = v end
    u.sample = Sample(u.kind, u.index)
    return u
end

function Unit:Cfg()
    return ns.db.units[self.kind]
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
    -- Shown by the unit watch: a new unit (or the same one back) needs drawing in full.
    root:HookScript("OnShow", function() self:Update(true) end)
    root:Hide()
    -- Click-casting addons (Clique and the like) pick frames up from here.
    ClickCastFrames = ClickCastFrames or {}
    ClickCastFrames[root] = true
    self.root = root

    -- The idle fade's frame, then everything drawn (which the range fade dims): two frames, so
    -- the two fades multiply, and neither touches the secure frame. While the unit's health is
    -- secret, the idle fade's opacity is worked out by the game from it (FrogLib's full-health
    -- gate), so the frame only fades at full health.
    local fader = CreateFrame("Frame", nil, root)
    fader:SetAllPoints()
    self.fader = fader
    -- Back in an eighth of a second, out in half.
    self.fade = FrogLib.Idle.NewFader(fader, { speedIn = 8, speedOut = 2 })
    self.idle = FrogLib.Idle.NewWatcher({
        unit = self.unit,
        onUpdate = function() self:UpdateFade() end,
        enabled = function()
            local fade = self:Cfg().fade
            return fade and fade.enabled
        end,
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
    -- the light outside them shows. The portrait gets a halo to match (Portrait.lua).
    self.glow = ns.CreateGlow(stack)

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
    self.iconLayer = icons

    -- Marks the frame while unlocked: a tint and its name.
    self.tint = icons:CreateTexture(nil, "BACKGROUND")
    self.tint:SetPoint("TOPLEFT", root, "TOPLEFT", -3, 3)
    self.tint:SetPoint("BOTTOMRIGHT", root, "BOTTOMRIGHT", 3, -3)
    self.tint:SetColorTexture(0.3, 0.6, 1, 0.18)
    self.label = Text(icons)
    self.label:SetPoint("BOTTOM", root, "TOP", 0, 2)
    self.label:SetTextColor(0.5, 0.8, 1)

    local cfg = self:Cfg()
    if cfg.druidMana ~= nil then self:BuildDruidMana() end
    if cfg.cast ~= nil then self:BuildCast() end
    if cfg.auras ~= nil then
        self.auras = ns.NewAuras(self.unit, function() return self:Cfg().auras end)
        self.empty = { debuffs = false, buffs = false }
        self.counts = {} -- how many each row has, when the game says (for wrapped rows' height)
    end
    self:RegisterEvents()
end

-- Resting: Blizzard's own animated "zzz" (its player frame's flipbook, 42 frames in 1.5 seconds),
-- or the old static resting icon where the client hasn't got it.
local REST_ATLAS = "UI-HUD-UnitFrame-Player-Rest-Flipbook"
local STATE_ICON = "Interface\\CharacterFrame\\UI-StateIcon"

function Unit:BuildRest(parent)
    local f = CreateFrame("Frame", nil, parent)
    f:SetFrameLevel(parent:GetFrameLevel() + 1)
    f.tex = f:CreateTexture(nil, "OVERLAY")
    f.tex:SetAllPoints()
    local animated = C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(REST_ATLAS) ~= nil
    if animated then
        animated = pcall(function()
            f.tex:SetAtlas(REST_ATLAS)
            local group = f:CreateAnimationGroup()
            group:SetLooping("REPEAT")
            local book = group:CreateAnimation("FlipBook")
            book:SetTarget(f.tex)
            book:SetDuration(1.5)
            book:SetFlipBookRows(7)
            book:SetFlipBookColumns(6)
            book:SetFlipBookFrames(42)
            book:SetFlipBookFrameWidth(0)
            book:SetFlipBookFrameHeight(0)
            book:SetSmoothing("NONE")
            f.anim = group
        end)
    end
    if not animated then
        f.anim = nil
        f.tex:SetTexture(STATE_ICON)
        f.tex:SetTexCoord(0, 0.5, 0, 0.421875)
    end
    f.animated = animated
    f:Hide()
    return f
end

function Unit:ShowRest(on)
    local f = self.rest
    if not f then return end
    f:SetShown(on)
    if f.anim then
        if on and not f.anim:IsPlaying() then
            f.anim:Play()
        elseif not on then
            f.anim:Stop()
        end
    end
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
    holder:Hide()
end

-- The cast bar by the frame: FrogTarget's, with the spell's icon in a frame of its own at its
-- start, the spell name on the bar's left and the time left on its right.
local SAMPLE_CAST = 2.5 -- seconds a sample cast takes, over and over
local SAMPLE_ICON = "Interface\\Icons\\Spell_Shadow_ShadowBolt"

function Unit:BuildCast()
    local holder = CreateFrame("Frame", nil, self.content)
    holder:SetFrameLevel(self.stack:GetFrameLevel())
    local box = ns.CreateBox(holder)
    local g = ns.CreateBar(holder)
    g.bar:SetAllPoints()
    g:SetColor(CAST_COLOR[1], CAST_COLOR[2], CAST_COLOR[3])
    g:SetSpark(true)
    local top = CreateFrame("Frame", nil, holder)
    top:SetAllPoints()
    top:SetFrameLevel(holder:GetFrameLevel() + 8)
    local c = { holder = holder, box = box, gauge = g, bar = g.bar }
    c.label = Text(top, "LEFT")
    c.label:SetPoint("LEFT", holder, "LEFT", 4, 0)
    c.time = Text(top, "RIGHT")
    c.time:SetPoint("RIGHT", holder, "RIGHT", -4, 0)
    c.label:SetPoint("RIGHT", c.time, "LEFT", -4, 0)
    c.iconFrame = CreateFrame("Frame", nil, holder)
    c.icon = c.iconFrame:CreateTexture(nil, "ARTWORK")
    c.icon:SetAllPoints()
    c.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    c.iconBox = ns.CreateBox(c.iconFrame)
    -- What's on it, as FrogLib's driver decides (see UpdateCast).
    c.driver = Cast.NewDriver({
        show = function(info)
            Cast.Fill(c.bar, info)
            c.label:SetText(info.text)
            Cast.SetIcon(c.icon, info.texture) -- the icon can be secret too
            if Cast.Locked(info) then
                c.gauge:SetColor(CAST_LOCKED[1], CAST_LOCKED[2], CAST_LOCKED[3])
            else
                c.gauge:SetColor(CAST_COLOR[1], CAST_COLOR[2], CAST_COLOR[3])
            end
            c.holder:Show()
        end,
        -- Held briefly in red so an interrupt is seen.
        hold = function(event)
            c.bar:SetMinMaxValues(0, 1)
            c.bar:SetValue(1)
            c.gauge:SetColor(0.85, 0.2, 0.15)
            c.label:SetText(event == "UNIT_SPELLCAST_FAILED" and FAILED or INTERRUPTED)
        end,
        -- Unlocked: a sample cast, filling over and over, so its place and look can be judged
        -- (unless there's a real one).
        sample = function()
            c.bar:SetMinMaxValues(0, 1)
            c.gauge:SetColor(CAST_COLOR[1], CAST_COLOR[2], CAST_COLOR[3])
            c.label:SetText("Shadow Bolt")
            c.icon:SetTexture(SAMPLE_ICON)
            c.holder:Show()
        end,
        hide = function() c.holder:Hide() end,
        refresh = function() self:UpdateCast() end, -- a hold is over
    })
    -- The time left can be secret, so it only goes straight into SetFormattedText. A sample
    -- (unlocked) fills over and over.
    g.bar:SetScript("OnUpdate", function(bar)
        if c.driver.sample then
            local left = SAMPLE_CAST - GetTime() % SAMPLE_CAST
            bar:SetValue(1 - left / SAMPLE_CAST)
            if self:Cfg().cast.showTime then c.time:SetFormattedText("%.1f", left) else c.time:SetText("") end
            return
        end
        if not self:Cfg().cast.showTime or c.driver.holdUntil then
            c.time:SetText("")
            return
        end
        Cast.ShowTime(bar, c.time)
    end)
    holder:Hide()
    self.cast = c
end

local HEALTH_EVENTS = { UNIT_HEALTH = true, UNIT_MAXHEALTH = true }
local POWER_EVENTS = { UNIT_POWER_UPDATE = true, UNIT_POWER_FREQUENT = true, UNIT_MAXPOWER = true, UNIT_DISPLAYPOWER = true }
local UNIT_EVENTS = { "UNIT_NAME_UPDATE", "UNIT_LEVEL", "UNIT_FACTION", "UNIT_FLAGS", "UNIT_CONNECTION",
    "UNIT_CLASSIFICATION_CHANGED", "UNIT_PORTRAIT_UPDATE", "UNIT_MODEL_CHANGED", "UNIT_COMBAT",
    "UNIT_THREAT_SITUATION_UPDATE", "UNIT_AURA" }
-- Anything that can change who a unit is, or the icons on every frame.
local WORLD_EVENTS = { "PLAYER_ENTERING_WORLD", "GROUP_ROSTER_UPDATE", "PARTY_LEADER_CHANGED", "RAID_TARGET_UPDATE",
    "UNIT_PET", "PLAYER_UPDATE_RESTING", "PLAYER_REGEN_ENABLED", "PLAYER_REGEN_DISABLED", "UPDATE_SHAPESHIFT_FORM",
    "PLAYER_FLAGS_CHANGED" }

function Unit:RegisterEvents()
    local f, unit = self.content, self.unit
    local function try(fn, ...) pcall(fn, f, ...) end
    for e in pairs(HEALTH_EVENTS) do try(f.RegisterUnitEvent, e, unit) end
    -- Your power events come for every kind of power: the druid mana bar follows them too.
    for e in pairs(POWER_EVENTS) do try(f.RegisterUnitEvent, e, unit) end
    for _, e in ipairs(UNIT_EVENTS) do try(f.RegisterUnitEvent, e, unit) end
    for _, e in ipairs(WORLD_EVENTS) do try(f.RegisterEvent, e) end
    try(f.RegisterEvent, "PLAYER_TARGET_CHANGED") -- the idle fade's "no target"
    if self.event then try(f.RegisterEvent, self.event) end
    if self.cast then
        for _, e in ipairs(Cast.EVENTS) do try(f.RegisterUnitEvent, e, unit) end
    end
    f:SetScript("OnEvent", function(_, event, arg1, ...) self:OnEvent(event, arg1, ...) end)
end

function Unit:OnEvent(event, arg1, ...)
    if not self.root:IsShown() then return end
    if HEALTH_EVENTS[event] then
        self:UpdateHealth(false)
        self:Changed("health")
    elseif POWER_EVENTS[event] then
        self:UpdatePower(false)
        self:Changed("power")
    elseif event == "PLAYER_TARGET_CHANGED" and event ~= self.event then
        self:UpdateFade()
    elseif event:find("^UNIT_SPELLCAST") then
        self:UpdateCast(event)
    elseif event == "UNIT_AURA" then
        self:CheckEmpty()
    elseif event == "UNIT_COMBAT" then
        if self:Cfg().hitText and self.portraitShown then self.portrait:CombatEvent(...) end
    elseif event == "UNIT_THREAT_SITUATION_UPDATE" or event == "PLAYER_UPDATE_RESTING"
        or event == "PLAYER_REGEN_ENABLED" or event == "PLAYER_REGEN_DISABLED" then
        self:UpdateGlow()
        self:UpdateIcons()
        if event == "PLAYER_REGEN_ENABLED" then
            -- Health and power start ticking back: wait for them to settle.
            self:Changed("health")
            self:Changed("power")
        else
            self:UpdateFade()
        end
    elseif event == "UNIT_PORTRAIT_UPDATE" or event == "UNIT_MODEL_CHANGED" then
        self:UpdatePortrait()
    elseif event == "UNIT_PET" then
        -- arg1 is the owner: you for "pet", partyN for "partypetN".
        local owner = self.unit == "pet" and "player" or self.kind == "partypet" and ("party" .. self.index)
        if owner and arg1 == owner then
            self:Update(true)
        end
    elseif event == "UPDATE_SHAPESHIFT_FORM" then
        if self.druid then self:UpdatePower(false) end
    elseif event == "RAID_TARGET_UPDATE" or event == "PARTY_LEADER_CHANGED" or event == "PLAYER_FLAGS_CHANGED" then
        self:UpdateIcons()
    elseif event == "PLAYER_ENTERING_WORLD" or event == "GROUP_ROSTER_UPDATE" or event == self.event then
        self:Update(true)
        self:UpdateFade()
    else
        self:Update(false)
    end
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
    local m = self:Mover()
    m.root:StartMoving()
    if not m.parent then FrogLib.Grid:Track(m.root) end
    m.moving = true
end

function Unit:DragStop()
    local m = self:Mover()
    if not m.moving then return end
    m.moving = nil
    local root = m.root
    root:StopMovingOrSizing()
    pcall(root.SetUserPlaced, root, false)
    FrogLib.Grid:Track(nil)
    local cfg = m:Cfg()
    if m.parent then
        -- Attached frames keep their place relative to the frame they hang from.
        local parent = ns.frames[m.parent]
        local p = parent.root
        local s, ps = root:GetEffectiveScale(), p:GetEffectiveScale()
        local x = root:GetLeft() - p:GetLeft() * ps / s
        local y = root:GetTop() - p:GetTop() * ps / s
        local sx, sy = m:Shift("TOPLEFT")
        local px, py = parent:Shift("TOPLEFT")
        cfg.attach = { "TOPLEFT", "TOPLEFT", math.floor(x - sx + px + 0.5), math.floor(y - sy + py + 0.5) }
    else
        -- Centred exactly when let go near the middle of the screen (FrogLib's Grid.lua).
        local p, rp, x, y = FrogLib.Grid:Snap(root)
        local sx, sy = m:Shift(p)
        cfg.point = { p, "UIParent", rp, x - sx, y - sy }
    end
    ns.Refresh()
end

------------------------------------------------------------------------------
-- Apply: size, place, clicks and visibility (out of combat only), then the layout
------------------------------------------------------------------------------

-- The frame (`root`, what's clicked) covers the portrait and the bars wherever their offsets put
-- them. Saved places are for its "home" box, where the two sit with no offsets, so moving the
-- portrait or the bars doesn't move the rest. Shift(point): how far the frame's `point` is from
-- the home box's, in the frame's units (x right, y up).
local POINTS = {
    TOPLEFT = { 0, 0 }, TOP = { 0.5, 0 }, TOPRIGHT = { 1, 0 }, LEFT = { 0, 0.5 }, CENTER = { 0.5, 0.5 },
    RIGHT = { 1, 0.5 }, BOTTOMLEFT = { 0, 1 }, BOTTOM = { 0.5, 1 }, BOTTOMRIGHT = { 1, 1 },
}
function Unit:Shift(point)
    local b = self.box
    local f = POINTS[point] or POINTS.CENTER
    if not b then return 0, 0 end
    local u, h = b.used, b.home -- { left, top, right, bottom }, down from the home box's top left
    local dx = (u[1] + f[1] * (u[3] - u[1])) - (h[1] + f[1] * (h[3] - h[1]))
    local dy = (u[2] + f[2] * (u[4] - u[2])) - (h[2] + f[2] * (h[4] - h[2]))
    return dx, -dy
end

function Unit:Place()
    local root, cfg = self.root, self:Cfg()
    root:ClearAllPoints()
    local function Set(point, rel, relUnit, relPoint, x, y)
        local sx, sy = self:Shift(point)
        local rx, ry = 0, 0
        if relUnit then rx, ry = relUnit:Shift(relPoint) end
        root:SetPoint(point, rel, relPoint, x + sx - rx, y + sy - ry)
    end
    if self.kind == "party" and self.index > 1 then
        local prev = ns.frames["party" .. (self.index - 1)]
        Set("TOPLEFT", prev.root, prev, "BOTTOMLEFT", 0, -cfg.spacing)
    elseif self.parent then
        local a, parent = cfg.attach, ns.frames[self.parent]
        Set(a[1], parent.root, parent, a[2], a[3], a[4])
    else
        local p = cfg.point
        Set(p[1], UIParent, nil, p[3], p[4], p[5])
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
    root:SetScale(self:Cfg().scale)
    self:Layout()
    self:Place()
    -- Clicks: left-click targets, right-click opens the unit menu; off while unlocked, so the
    -- frames can be dragged.
    Secure.SetClicks(root, db.locked and self.name .. "Menu")
    self.tint:SetShown(not db.locked)
    self.label:SetShown(not db.locked)
    self.label:SetText(ns.KindName(self.kind) .. (self.index and (" " .. self.index) or ""))
    self:Watch()
    if root:IsShown() then self:Update(true) end
    self:UpdateFade(true)
end

------------------------------------------------------------------------------
-- Layout
------------------------------------------------------------------------------

local function Round(v, px) return math.floor(v / px + 0.5) * px end

-- Sizes and places everything inside the frame, and the frame to fit (the frame only when it's
-- allowed: out of combat). Everything on whole screen pixels. The bars are centred on the
-- portrait, their frames starting just under its ring; the name sits above the health bar.
function Unit:Layout()
    local cfg, db = self:Cfg(), ns.db
    local o = cfg.offsets
    local root = self.root
    local px = FrogLib.Pixel(root)
    local function S(v) return ns.Snap(v, px) end
    local reach = ns.BorderReach(root) -- each bar's frame, outside it
    local gap = ns.BarGap(root)        -- from the health bar's fill to the power bar's

    local W = S(cfg.width)
    local H1 = S(cfg.healthHeight)
    local H2 = cfg.powerHeight > 0 and S(cfg.powerHeight) or 0
    local stackH = H1 + (H2 > 0 and gap + H2 or 0)
    local blockH = stackH + 2 * reach

    -- The portrait and its ring.
    local p = self.portrait
    local D = cfg.portrait ~= "none" and S(cfg.portraitSize) or 0
    self.portraitShown = D > 0
    p.frame:SetShown(D > 0)
    local ring = 0
    if D > 0 then
        p:Layout(D, self.side, o.levelX, o.levelY)
        ring = p:Ring()
    end
    -- Without a portrait the level goes above the bars, at the far end from the name.
    local levelAbove = cfg.showLevel and D == 0
    local nameH = (cfg.namePos == "above" or levelAbove) and Round(cfg.nameSize + 3, px) or 0

    -- Up and down from the portrait's centre (or the bars' middle): the frame reaches from the
    -- portrait's top or the name's, whichever is higher, to the lower of the two bottoms.
    local top = math.min(-D / 2, -blockH / 2 - nameH)
    local bottom = math.max(D / 2, blockH / 2)
    local homeH = Round(bottom - top, px)
    -- Where the bars' frames start: just behind the ring.
    local tuck = D > 0 and D - ring - px or 0
    local homeW = tuck + W + 2 * reach

    -- The home places (no offsets), down from the home box's top left; then each moved by its own
    -- offset (right and up are +).
    local cy = Round(-top, px) -- the portrait's centre
    local cx = self.side == "left" and D / 2 or homeW - D / 2
    local stackX = self.side == "left" and tuck + reach or reach
    local stackY = Round(cy - blockH / 2 + reach, px)
    cx, cy = cx + Round(o.portraitX, px), cy - Round(o.portraitY, px)
    stackX, stackY = stackX + Round(o.barsX, px), stackY - Round(o.barsY, px)

    -- The frame: what the portrait and the bars (with the name over them) cover.
    local l, t = stackX - reach, stackY - reach - nameH
    local r, b = stackX + W + reach, stackY + stackH + reach
    if D > 0 then
        l, t = math.min(l, cx - D / 2), math.min(t, cy - D / 2)
        r, b = math.max(r, cx + D / 2), math.max(b, cy + D / 2)
    end
    l, t, r, b = Round(l, px), Round(t, px), Round(r, px), Round(b, px)
    self.box = { home = { 0, 0, homeW, homeH }, used = { l, t, r, b } }
    if not InCombatLockdown() then root:SetSize(r - l, b - t) end

    local stack = self.stack
    stack:ClearAllPoints()
    stack:SetPoint("TOPLEFT", root, "TOPLEFT", Round(stackX - l, px), -(stackY - t))
    stack:SetSize(W, stackH)
    if D > 0 then
        p.frame:ClearAllPoints()
        p.frame:SetPoint("CENTER", root, "TOPLEFT", Round(cx - l, px), -(cy - t))
    end
    -- On a frame that can show the elite dragon, how much of the bars' portrait end it may reach
    -- over: the name, and what hangs above and below the bars, stop short of it.
    local clear = 0
    if cfg.dragons and D > 0 then
        -- From the portrait's centre to the bars' near end.
        local near = self.side == "left" and stackX - cx or cx - (stackX + W)
        clear = math.max(0, Round(p:DragonNear() - near + 2 * px, px))
    end
    self.geo = { W = W, stackH = stackH, reach = reach, px = px, P = D, ring = ring, nameH = nameH, clear = clear,
        pcy = cy - stackY, -- the portrait's centre, down from the stack's top
        left = Round(stackX - l, px), right = Round(r - stackX - W, px) } -- the frame either side of the stack

    -- Health on top, power under it, each in its frame.
    local hb, pb = self.health.bar, self.power.bar
    hb:ClearAllPoints()
    hb:SetPoint("TOPLEFT", stack, "TOPLEFT", 0, 0)
    hb:SetSize(W, H1)
    pb:ClearAllPoints()
    pb:SetShown(H2 > 0)
    if H2 > 0 then
        pb:SetPoint("TOPLEFT", stack, "TOPLEFT", 0, -(H1 + gap))
        pb:SetSize(W, H2)
    end
    self.health:ApplyTexture(cfg.healthTexture)
    self.power:ApplyTexture(cfg.powerTexture)
    self.healthBox:Apply()
    self.powerBox:Apply()

    -- The name: above the health bar at the portrait's end (namePos "above"), on the bar at that
    -- end ("inside", in place of that end's text), or not at all. The level: in the badge, or
    -- above the bars' far end with no portrait.
    local near, far = "LEFT", "RIGHT"
    if self.side == "right" then near, far = "RIGHT", "LEFT" end
    local sign = near == "LEFT" and 1 or -1
    local nt, lt = self.nameText, self.levelText
    ns.Media:SetFont(nt, db.font, cfg.nameSize, db.outline)
    ns.Media:SetFont(lt, db.font, cfg.nameSize, db.outline)
    nt:ClearAllPoints()
    lt:ClearAllPoints()
    nt:SetJustifyH(near)
    local levelRoom = levelAbove and math.floor(cfg.nameSize * 2.2) or 0
    if cfg.namePos == "inside" then
        nt:SetPoint(near, hb, near, 4 * sign + o.nameX, o.nameY)
        nt:SetWidth(math.max(10, W * 0.55))
        nt:SetTextColor(1, 1, 1)
    else
        nt:SetPoint("BOTTOM" .. near, hb, "TOP" .. near, sign * (1 + clear) + o.nameX, reach + px + o.nameY)
        -- Cut short at the bars' end, or (nameFull) as long as it is, over the portrait.
        nt:SetWidth(cfg.nameFull and 0 or math.max(10, W - levelRoom - clear - 2))
        nt:SetWordWrap(false)
        nt:SetTextColor(1, 0.82, 0)
    end
    self.nameShown = cfg.namePos == "above" or cfg.namePos == "inside"
    nt:SetShown(self.nameShown)
    lt:SetPoint("BOTTOM" .. far, hb, "TOP" .. far, -sign + o.levelX, reach + px + o.levelY)
    lt:SetShown(levelAbove)
    self.levelAbove = levelAbove
    p.badge:SetShown(D > 0 and cfg.showLevel)
    p.level:SetTextColor(1, 0.82, 0)
    -- The bar's end the name sits on, when it's inside.
    self.nameSlot = cfg.namePos == "inside" and (near == "LEFT" and "Left" or "Right") or nil

    -- The bars' text slots.
    for bar, b in pairs({ health = hb, power = pb }) do
        local size = cfg.textSize
        -- The power bar's text no taller than the bar.
        if bar == "power" then size = math.max(6, math.min(size, cfg.powerHeight + 1)) end
        -- Each slot at its end of the bar (or the middle), moved by its own offsets (healthLeftX,
        -- healthX, healthRightX ... and the Ys; right and up are +).
        for _, slot in ipairs(SLOTS) do
            local fs = self.texts[bar][slot]
            ns.Media:SetFont(fs, db.font, size, db.outline)
            fs:ClearAllPoints()
            local dx, dy = o[bar .. slot .. "X"] or 0, o[bar .. slot .. "Y"] or 0
            local at = slot == "Left" and "LEFT" or slot == "Right" and "RIGHT" or "CENTER"
            fs:SetPoint(at, b, at, dx, dy)
        end
    end

    -- The glow starts at the bars' frames' outline.
    self.glow:Place(stack, reach)

    self:LayoutIcons()
    self:LayoutAround()
end

-- Icons round the portrait (or the outer end of the bars, with no portrait): the raid mark on
-- its top, the leader's crown at its upper outer edge, the PvP badge beside it, resting or
-- fighting (yours) at its bottom. The level badge is at its lower outer edge (Portrait.lua).
function Unit:LayoutIcons()
    local size = ns.db.icons.size
    local icons, p, g = self.icons, self.portrait, self.geo
    local out = self.side == "left" and -1 or 1 -- away from the bars
    local outer = self.side == "left" and "LEFT" or "RIGHT"
    for _, t in pairs(icons) do t:ClearAllPoints() end
    icons.leader:SetSize(size, size)
    icons.status:SetSize(size * 1.2, size * 1.2)
    icons.pvp:SetSize(size * 1.6, size * 1.6)
    if self.portraitShown then
        local f, D = p.frame, g.P
        icons.raid:SetPoint("CENTER", f, "TOP", 0, 0)
        icons.leader:SetPoint("CENTER", f, "CENTER", -out * D * 0.30, D * 0.41)
        icons.status:SetPoint("CENTER", f, "CENTER", -out * D * 0.08, -D * 0.46)
        icons.pvp:SetPoint("CENTER", f, "CENTER", out * (D * 0.5 + size * 0.55), D * 0.06)
    else
        local s = self.stack
        icons.raid:SetPoint("CENTER", s, outer, out * (g.reach + size * 0.6), 0)
        icons.leader:SetPoint("CENTER", s, "TOP" .. outer, 0, g.reach)
        icons.status:SetPoint("CENTER", s, "BOTTOM" .. outer, 0, 0)
        icons.pvp:SetPoint("CENTER", s, outer, out * (g.reach + size * 1.4), 0)
    end
    -- Resting (yours): at the portrait's top outer corner, or beside the level badge, nudged by
    -- the rest offsets.
    local rest = self.rest
    if rest then
        local cfg, o = self:Cfg(), self:Cfg().offsets
        local D = g.P > 0 and g.P or 40
        local zs = math.max(12, D * (rest.animated and 0.5 or 0.36))
        rest:SetSize(zs, zs)
        rest:ClearAllPoints()
        if not self.portraitShown then
            rest:SetPoint("BOTTOM" .. outer, self.stack, "TOP" .. outer, o.restX, g.reach + o.restY)
        elseif cfg.restPos == "badge" then
            rest:SetPoint("CENTER", p.frame, "CENTER", -out * D * 0.08 + o.restX, -D * 0.46 + o.restY)
        else
            rest:SetPoint("CENTER", p.frame, "CENTER", out * D * 0.36 + o.restX, D * 0.38 + o.restY)
        end
    end
end

-- What hangs off the bars, each above or below them (its own setting), nearest first: your
-- druid mana (player), the combo points (on the frame they're set to show on), the cast bar when
-- it's "next to the bars", the buff and debuff rows (in their order, nearest first), and the cast
-- bar when it's "beyond the auras". Below, they start under the bars' frames; above, over the
-- name. On a frame that can show the elite dragon they stop short of where it reaches over the
-- bars' end, so they clear it whether it's there or not. The party's debuffs go on any side.
-- Laid out again when a row of auras empties or fills, or the druid bar comes or goes.
function Unit:LayoutAround()
    local cfg, db, g = self:Cfg(), ns.db, self.geo
    local o = cfg.offsets
    if not g then return end
    local stack, reach, px = self.stack, g.reach, g.px

    -- y is up from the stack's top; each side's edge, from which the next thing goes.
    local edge = { below = -(g.stackH + reach), above = reach + g.nameH }
    -- Across: from x, w wide (the bars' width, less what the dragon may cover at the portrait's end).
    local clear = g.clear
    local x, w = 0, g.W - clear
    if self.side == "left" then x = clear end
    self.aroundX, self.aroundW = x, w
    local last = {} -- what went last on each side ("aura" or "box"), for the gap to the next
    -- Places a thing h tall on a side; boxed things have a frame round them. Returns the y of
    -- its top (inside its frame).
    local function Put(side, h, boxed, aura)
        local space = (aura and last[side] == "aura") and (cfg.auras.rowGap or 4) or (aura and 4 or 3)
        local frame = boxed and reach or 0
        local y
        if side == "above" then
            local bottom = edge.above + space
            y = bottom + frame + h
            edge.above = bottom + h + 2 * frame
        else
            local topEdge = edge.below - space
            y = topEdge - frame
            edge.below = topEdge - h - 2 * frame
        end
        last[side] = aura and "aura" or "box"
        return Round(y, px)
    end
    local function Side(v) return v == "above" and "above" or "below" end

    if self.druid then
        local h = ns.Snap(cfg.druidManaHeight, px)
        local holder = self.druidHolder
        holder:SetSize(w, h)
        self.druidBox:Apply()
        self.druid:ApplyTexture(cfg.powerTexture)
        if self.druidShown then
            holder:ClearAllPoints()
            holder:SetPoint("TOPLEFT", stack, "TOPLEFT", x + o.druidX, Put(Side(cfg.druidManaSide), h, true) + o.druidY)
        end
    end

    self.comboY = nil
    if ns.Combo and ns.Combo:On(self.kind) then
        self.comboY = Put(Side(db.combo.side), ns.Combo:PipHeight(self), true)
    end

    -- The frame's own cast bar settings (target, focus).
    local c, cc = self.cast, cfg.cast
    local castOn = c and cc.enabled
    local castSide = cc and Side(cc.side)
    local castH = c and ns.Snap(cc.height or 11, px)
    -- Its width: the bars' (width 0) or its own, the icon (in its frame) at its start.
    local castW = (c and (cc.width or 0) > 0) and ns.Snap(cc.width, px) or w
    local iconW = (c and cc.icon) and castH + 2 * reach + 2 * px or 0
    if c then
        c.holder:SetSize(math.max(px * 10, castW - iconW), castH)
        c.iconFrame:SetSize(castH, castH)
        c.iconFrame:ClearAllPoints()
        c.iconFrame:SetPoint("TOPRIGHT", c.holder, "TOPLEFT", -(2 * reach + 2 * px), 0)
        c.iconFrame:SetShown(cc.icon and true or false)
        c.iconBox:Apply()
        c.box:Apply()
        c.gauge:ApplyTexture()
        ns.Media:SetFont(c.label, db.font, math.max(8, cfg.textSize), db.outline)
        ns.Media:SetFont(c.time, db.font, math.max(8, cfg.textSize), db.outline)
    end
    local function PlaceCast()
        c.holder:ClearAllPoints()
        c.holder:SetPoint("TOPLEFT", stack, "TOPLEFT", x + iconW + o.castX, Put(castSide, castH, true) + o.castY)
    end
    if castOn and cc.position ~= "beyond" then PlaceCast() end

    if self.auras then
        local specs, a = {}, cfg.auras -- the frame's own aura settings
        -- A row's lines: the samples' while unlocked, the unit's auras when the game says how
        -- many, else room for all of them (a row that wraps only takes more than one line then).
        local function Lines(row, rc)
            local n = self.counts[row] or rc.max
            if not db.locked then n = ns.AuraSampleCount(row, rc) end
            return ns.AuraLines(rc, n)
        end
        -- Places a row on a side via Put: below, its top; above, its bottom line's bottom (it
        -- wraps upwards from there, the timers under each line).
        local function Row(spec, side, rc, row)
            local h = ns.AuraBlockHeight(rc, a, Lines(row, rc))
            local top = Put(side, h, false, true)
            if side == "above" then
                spec.up = true
                spec.point = spec.point == "TOPRIGHT" and "BOTTOMRIGHT" or "BOTTOMLEFT"
                spec.y = top - h + (ns.AuraRowHeight(rc) - rc.size) -- above the timers, when they're under
            else
                spec.y = top
            end
        end
        if self.kind == "party" then
            local d = a.debuffs
            local shown = a.enabled and d.enabled and (not db.locked or not (a.fold and self.empty.debuffs))
            local spec = { cfg = d, anchor = stack, shown = shown, point = "TOPLEFT", grow = "RIGHT" }
            if d.side == "left" then
                spec.point, spec.grow = "TOPRIGHT", "LEFT"
                local badge = 0
                if self.portraitShown and self.side == "left" then
                    local _, outwards = self.portrait:BadgeReach()
                    badge = math.max(0, outwards)
                end
                spec.x = -(g.left + badge + 4)
                spec.y = -math.floor((g.stackH - d.size) / 2)
            elseif d.side == "above" or d.side == "below" then
                spec.x = x
                Row(spec, d.side, d, "debuffs")
            else
                spec.x = g.W + g.right + 4
                spec.y = -math.floor((g.stackH - d.size) / 2)
            end
            spec.x, spec.y = spec.x + o.debuffsX, spec.y + o.debuffsY
            specs.debuffs = spec
        else
            local order = a.order == "buffs" and { "buffs", "debuffs" } or { "debuffs", "buffs" }
            for _, row in ipairs(order) do
                local rc = a[row]
                local shown = a.enabled and rc.enabled and (not db.locked or not (a.fold and self.empty[row]))
                local spec = { cfg = rc, anchor = stack, x = x, y = 0, shown = shown,
                    point = "TOPLEFT", grow = "RIGHT" }
                if shown then Row(spec, Side(rc.side), rc, row) end
                spec.x, spec.y = spec.x + o[row .. "X"], spec.y + o[row .. "Y"]
                specs[row] = spec
            end
        end
        self.auraSpecs = specs
        self.auras:Apply(self.content, specs)
        self.auras:Preview(self.content, specs, not db.locked)
    end

    if castOn and cc.position == "beyond" then PlaceCast() end
    if ns.Combo then ns.Combo:Layout() end
end

-- After a change of unit or of its auras: lays them out again if a row has opened or closed.
-- Also when a row that wraps gains or loses a line.
function Unit:CheckEmpty()
    if not self.auras or not self.auraSpecs then return end
    local relayout = false
    for row in pairs(self.empty) do
        local spec = self.auraSpecs[row]
        local now = spec ~= nil and not self.auras:HasAny(row, spec.cfg)
        if now ~= self.empty[row] then
            self.empty[row] = now
            if self:Cfg().auras.fold then relayout = true end
        end
        if spec then
            local count = self.auras:Count(row, spec.cfg)
            local before = self.counts[row] or spec.cfg.max
            self.counts[row] = count
            if ns.AuraLines(spec.cfg, count or spec.cfg.max) ~= ns.AuraLines(spec.cfg, before) then relayout = true end
        end
    end
    if relayout then self:LayoutAround() end
end

------------------------------------------------------------------------------
-- Updates
------------------------------------------------------------------------------

-- The unit to draw: the real one, or nil for a sample (unlocked, no unit). false: nothing.
function Unit:Shown()
    local e = UnitExists(self.unit)
    if issecret(e) or e then return self.unit end
    if not ns.db.locked and self:Enabled() then return nil end
    return false
end

function Unit:Update(full)
    if not self.root:IsShown() or not ns.db then return end
    local unit = self:Shown()
    if unit == false then return end
    self.shownUnit = unit
    local cfg, s = self:Cfg(), self.sample
    if full then
        local guid = unit and UnitGUID(unit)
        if issecret(guid) then self.guid = nil else self.guid = guid end
        self.lastFull = GetTime()
    end

    self:UpdateHealth(full)
    self:UpdatePower(full)

    -- Name and level (in the badge, or above the bars with no portrait).
    local fake = not unit and s or nil
    if self.nameShown then ns.SetUnitText(self.nameText, "name", unit, fake) else self.nameText:Hide() end
    if cfg.showLevel and self.portraitShown then
        ns.SetUnitText(self.portrait.level, "level", unit, fake)
    elseif self.levelAbove then
        ns.SetUnitText(self.levelText, "level", unit, fake)
    end

    if full then self:UpdatePortrait() end
    -- The dragon round an elite's or rare's portrait.
    if self.portraitShown and cfg.dragons then
        -- The classification may be secret: handed on untested (SetDragon reads it safely).
        local classification = s.classification
        if unit then classification = UnitClassification(unit) end
        self.dragonShown = self.portrait:SetDragon(classification)
    elseif cfg.dragons ~= nil then
        self.dragonShown = self.portrait:SetDragon(nil)
    end
    self:UpdateIcons()
    self:UpdateGlow()
    self:UpdateRange()
    if full then
        if self.cast then self:UpdateCast() end
        if self.auras then
            self.auras:UnitChanged()
            self:CheckEmpty()
        end
    end
end

function Unit:UpdateHealth(instant)
    local unit = self.shownUnit
    if unit == false then return end
    local cfg, s, t = self:Cfg(), self.sample, self.texts.health
    local r, g, b
    if unit then
        self.health:SetValues(UnitHealth(unit), UnitHealthMax(unit), instant)
        r, g, b = HealthColor(unit)
    else
        self.health:SetValues(s.value, s.max, true)
        local c = ns.db.healthColor == "green" and GREEN or s.color
        r, g, b = c.r, c.g, c.b
    end
    self.health:SetColor(r, g, b)
    -- The name above the bars: gold like the game's, white, or in the health bar's colour.
    if cfg.namePos == "above" then
        local mode = ns.db.nameColor
        if mode == "unit" then
            self.nameText:SetTextColor(r + (1 - r) * 0.25, g + (1 - g) * 0.25, b + (1 - b) * 0.25)
        elseif mode == "white" then
            self.nameText:SetTextColor(1, 1, 1)
        else
            self.nameText:SetTextColor(1, 0.82, 0)
        end
    end

    -- Dead, a ghost or offline: said in the middle of the bar instead of the numbers.
    local status
    if unit then
        if Safe(UnitIsConnected(unit)) == false then
            status = PLAYER_OFFLINE or "Offline"
        elseif Safe(UnitIsGhost(unit)) then
            status = GHOST or "Ghost"
        elseif Safe(UnitIsDead(unit)) then
            status = DEAD or "Dead"
        end
    end
    for _, slot in ipairs(SLOTS) do
        local fs = t[slot]
        if status then
            if slot == "" then
                fs:SetText(status)
                fs:Show()
            else
                fs:Hide()
            end
        elseif slot == self.nameSlot then
            fs:Hide() -- the name is there
        else
            ns.SetUnitText(fs, cfg.text["health" .. slot], unit, not unit and s or nil)
        end
    end
end

-- Druids in a form: whether the form's rage or energy is showing instead of mana.
local function InForm()
    local _, class = UnitClass("player")
    if class ~= "DRUID" then return false end
    local kind = Safe(UnitPowerType("player"))
    return kind ~= nil and kind ~= MANA
end

function Unit:UpdatePower(instant)
    local unit = self.shownUnit
    if unit == false then return end
    local cfg, s, t = self:Cfg(), self.sample, self.texts.power
    if cfg.powerHeight > 0 then
        if unit then
            self.power:SetValues(UnitPower(unit), UnitPowerMax(unit), instant)
        else
            self.power:SetValues(s.power.value, s.power.max, true)
        end
        self.power:SetColor(Color.Power(unit))
        for _, slot in ipairs(SLOTS) do
            ns.SetUnitText(t[slot], cfg.text["power" .. slot], unit, not unit and s.power or nil, true)
        end
    else
        for _, slot in ipairs(SLOTS) do t[slot]:Hide() end
    end

    if self.druid then
        -- Unlocked, a druid sees it in any form, so it can be placed.
        local _, class = UnitClass("player")
        local sample = not ns.db.locked and class == "DRUID"
        local show = cfg.druidMana and ((unit ~= nil and InForm()) or sample)
        if show and InForm() then
            self.druid:SetValues(UnitPower("player", MANA), UnitPowerMax("player", MANA), instant)
        elseif show then
            self.druid:SetValues(70, 100, true)
        end
        if show ~= self.druidShown then
            self.druidShown = show
            self.druidHolder:SetShown(show)
            self:LayoutAround()
        end
    end
end

function Unit:UpdatePortrait()
    if not self.portraitShown then return end
    local unit = self.shownUnit
    if unit == false then return end
    self.portrait:Set(unit, self:Cfg().portrait)
end

-- Raid marks (FrogLib.Icons: which mark can be secret, so it's written into text), leader,
-- resting / fighting (you), PvP. unit nil: samples.
local PVP_COORDS = { 0.08, 0.58, 0.045, 0.545 } -- the PvP badges sit in the corner of a larger file
local STATE = "Interface\\CharacterFrame\\UI-StateIcon"

local function ShowRaid(fs, unit, size)
    if not unit then return Icons.SetRaidMark(fs, 1, size) end -- the sample: a star
    return Icons.RaidMark(fs, unit, size)
end

local function ShowLeader(tex, unit)
    if not unit then
        tex:SetTexture("Interface\\GroupFrame\\UI-Group-LeaderIcon")
        return true
    end
    if Safe(UnitIsGroupLeader(unit)) then
        tex:SetTexture("Interface\\GroupFrame\\UI-Group-LeaderIcon")
        return true
    elseif Safe(UnitIsGroupAssistant(unit)) then
        tex:SetTexture("Interface\\GroupFrame\\UI-Group-AssistantIcon")
        return true
    end
    return false
end

local function ShowStatus(tex)
    if Safe(UnitAffectingCombat("player")) then
        tex:SetTexture(STATE)
        tex:SetTexCoord(0.5, 1, 0, 0.484375)
        return true
    end
    return false
end

local function ShowPvP(tex, unit)
    local file
    if Safe(UnitIsPVPFreeForAll(unit)) then
        file = "Interface\\TargetingFrame\\UI-PVP-FFA"
    elseif Safe(UnitIsPVP(unit)) then
        local faction = Safe(UnitFactionGroup(unit))
        if faction == "Horde" or faction == "Alliance" then file = "Interface\\TargetingFrame\\UI-PVP-" .. faction end
    end
    if not file then return false end
    tex:SetTexture(file)
    tex:SetTexCoord(PVP_COORDS[1], PVP_COORDS[2], PVP_COORDS[3], PVP_COORDS[4])
    return true
end

function Unit:UpdateIcons()
    local unit = self.shownUnit
    if unit == false then return end
    local cfg, icons = ns.db.icons, self.icons
    local size = cfg.size
    icons.raid:SetShown(cfg.raid and ShowRaid(icons.raid, unit, size) or false)
    local leader = cfg.leader and (unit ~= nil or self.kind == "party" and self.index == 1)
    icons.leader:SetShown(leader and ShowLeader(icons.leader, unit) or false)
    icons.status:SetShown(cfg.status and self.kind == "player" and ShowStatus(icons.status) or false)
    if self.rest then
        local resting = IsResting() or not ns.db.locked -- a sample while unlocked, to place it
        self:ShowRest(cfg.status and self:Cfg().restPos ~= "none" and resting and not icons.status:IsShown())
    end
    -- Players only: faction guards are flagged too, and a badge on every guard is noise.
    icons.pvp:SetShown(cfg.pvp and unit ~= nil and Safe(UnitIsPlayer(unit)) and ShowPvP(icons.pvp, unit) or false)
end

-- The soft glow round the bars and the portrait: threat (player, party: yellow to red while
-- enemies are on them), and on your own frame, if wanted, gold while resting and red while fighting.
function Unit:UpdateGlow()
    local cfg, unit = self:Cfg(), self.shownUnit
    local r, g, b, a
    if unit and cfg.threat then
        local status = Safe(UnitThreatSituation(unit))
        if status and status > 0 and GetThreatStatusColor then
            r, g, b = GetThreatStatusColor(status)
            a = 0.85
        end
    end
    if not r and unit and cfg.glow then
        if Safe(UnitAffectingCombat("player")) then
            r, g, b, a = 1, 0.15, 0.1, 0.6
        elseif IsResting() then
            r, g, b, a = 1, 0.82, 0.2, 0.5
        end
    end
    if r then
        self.glow:SetColor(r, g, b, a)
        self.portrait.halo:SetVertexColor(r, g, b, a)
    end
    self.glow:SetShown(r ~= nil)
    self.portrait.halo:SetShown(r ~= nil and self.portraitShown)
end

-- Out of range: faded (fadeRange). Group members (and their pets) by the game's group range
-- check, anyone else by the follow distance (about 28 yards), but only out of combat: in combat
-- CheckInteractDistance is protected (calling it is blocked even inside pcall), so then they
-- simply count as in range. Either answer may be secret: it's then handed to
-- SetAlphaFromBoolean as it is.
local function InRange(unit)
    if Safe(UnitIsUnit(unit, "player")) then return true end
    local grouped = Safe(UnitInParty(unit)) or Safe(UnitInRaid(unit)) or unit:find("^party")
    if grouped and UnitInRange then
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
    local unit = self.shownUnit
    local content = self.content
    if not unit or not self:Cfg().fadeRange then
        content:SetAlpha(1)
        return
    end
    local near = InRange(unit)
    if issecret(near) then
        if not (content.SetAlphaFromBoolean and pcall(content.SetAlphaFromBoolean, content, near, 1, ns.db.rangeAlpha)) then
            content:SetAlpha(1)
        end
    else
        content:SetAlpha(near and 1 or ns.db.rangeAlpha)
    end
end

------------------------------------------------------------------------------
-- The cast bar (target, focus)
------------------------------------------------------------------------------

function Unit:UpdateCast(event)
    local c = self.cast
    if not c then return end
    local unit = self.shownUnit
    if not self:Cfg().cast.enabled or unit == false then
        c.holder:Hide()
        return
    end
    -- unit nil: a sample (unlocked, nobody there).
    c.driver:Update(unit, event, not ns.db.locked)
end

------------------------------------------------------------------------------
-- Fade when idle (fade): FrogLib's rule (FrogLib.Idle), as PersonalResourceTweaks fades its
-- display. Out of combat, at full health, with the power at rest (rage empty, mana or energy
-- full) and, optionally, no target, the frame fades to fade.alpha; anything else brings it
-- straight back: combat, damage, a power change, a target, the mouse over it, unlocking, Edit
-- Mode. Power the game keeps secret can't be compared with its maximum, so it's watched instead:
-- out of combat it ticks until it's full or empty and then stops, so a few quiet seconds mean it
-- has settled. Health the game keeps secret goes through FrogLib's full-health gate: the game
-- reads it, and the frame only fades at full health. Only the fader (a plain child) changes,
-- never the secure frame.
------------------------------------------------------------------------------

-- force: set the opacity at once (a change of settings, unlocking).
function Unit:UpdateFade(force)
    if not self.fade or not ns.db then return end
    local fade, unit = self:Cfg().fade, self.shownUnit
    local idle, secret = false, false
    if fade and fade.enabled and unit then
        local _
        idle, _, secret = self.idle:Evaluate({ unit = unit, noTarget = fade.noTarget, hover = self.hover,
            unlocked = not ns.db.locked, editMode = true })
    end
    self.fade:SetGate((idle and secret) and unit or nil)
    self.fade:Set(idle and fade.alpha or 1, force and "now" or nil)
end

-- A change to health or power: note it, show the frame, and look again once things have been
-- quiet long enough to settle. A health change while the gate decides plays the fade again, so
-- it fades smoothly once the game sees full health.
function Unit:Changed(kind)
    self.idle:Changed(kind)
    self:UpdateFade()
    if kind == "health" then self.fade:Replay() end
end

if EventRegistry then
    local function All()
        for _, u in ipairs(ns.frameList or {}) do u:UpdateFade() end
    end
    EventRegistry:RegisterCallback("EditMode.Enter", All, ns)
    EventRegistry:RegisterCallback("EditMode.Exit", All, ns)
end
