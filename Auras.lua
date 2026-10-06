local _, ns = ...
local Auras = {}
Auras.__index = Auras

-- Status effects on a unit frame, in rows: debuffs (yours, then everyone else's) and buffs under
-- the target and focus, a short debuff row beside each party member. From FrogTarget's
-- Auras.lua. Each row is one of 12.1's AuraContainers: the engine picks and draws the auras, so
-- it keeps working where addons can't read aura data. Lessons carried over from
-- PersonalResourceTweaks: position a container before setting it up (moving it means building
-- it again), never anchor anything to it, and size the buttons ourselves (the engine makes them
-- 0x0). How many auras there are can be secret, so each row is given room for one line.
--   local a = ns.NewAuras(unit, settings) -- settings(): the frame's auras table (rounded, spacing)
--   a:Apply(parent, specs)   -- specs[row] = { cfg =, anchor =, x =, y =, shown =, point =,
--                            --   grow = "RIGHT" / "LEFT", up = true (wraps upwards) }
-- x, y: where the row's corner (point: TOPLEFT, TOPRIGHT, or BOTTOM... for a row that wraps
-- upwards) goes, from the anchor's top left. A row is one long line up to `max`, or wraps after
-- cfg.perRow icons, its lines stacking away from the frame.
--   a:Preview(parent, specs, on), a:HasAny(row, cfg), a:UnitChanged()
-- row is "debuffs" or "buffs"; cfg its settings (enabled, mode, size, max, perRow, showTimer,
-- timerPos "icon" (on the icon's bottom edge) or "below" (under it), timerScale).

local SORT = AuraContainerSortMethod and AuraContainerSortMethod.Default
local SORT_DIR = AuraContainerSortDirection and AuraContainerSortDirection.Normal
local TIMER_HEIGHT = 12 -- the timer printed under each icon

local A = FrogLib.Auras -- the rows' building blocks (FrogLib's Auras.lua)

-- Whether a row's timers go under its icons (rather than on them).
function ns.AuraTimerBelow(cfg)
    return cfg.showTimer and cfg.timerPos == "below"
end

-- How tall one line of a row is: its icons, and the timers when they're under them.
function ns.AuraRowHeight(cfg)
    return cfg.size + (ns.AuraTimerBelow(cfg) and TIMER_HEIGHT or 0)
end

-- The timer's and stack count's font size: timerScale per cent of the icon (40 to start), 7 at least.
function ns.AuraTimerSize(cfg)
    return math.max(7, math.floor(cfg.size * (cfg.timerScale or 40) / 100 + 0.5))
end

-- The gap between icons: the row's spacing; with the timers under the icons, widened so the
-- longest ("59m") clears the next one's. On the icons they fit inside, so it stays as set.
function ns.AuraSpacing(cfg, all)
    local sp = all.spacing or 2
    if ns.AuraTimerBelow(cfg) then sp = math.max(sp, math.ceil(ns.AuraTimerSize(cfg) * 2.6) - cfg.size + 2) end
    return sp
end

-- Where a button's timer and stack count go: the timer centred along the icon's bottom edge,
-- inside it, or under it; the count top right, or bottom right with the timer elsewhere.
local function PlaceTexts(button, duration, stack, cfg)
    duration:ClearAllPoints()
    stack:ClearAllPoints()
    if ns.AuraTimerBelow(cfg) or not cfg.showTimer then
        duration:SetPoint("TOP", button, "BOTTOM", 0, -1)
        stack:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -1, 1)
    else
        duration:SetPoint("BOTTOM", button, "BOTTOM", 0, 1)
        stack:SetPoint("TOPRIGHT", button, "TOPRIGHT", -1, -1)
    end
end

-- How many icons go on a line: perRow, or all of them (max) on one long line.
function ns.AuraPerLine(cfg)
    local n = cfg.perRow or 0
    if n <= 0 or n > cfg.max then return cfg.max end
    return n
end

-- How many lines `count` icons take, and how tall they are together.
function ns.AuraLines(cfg, count)
    local per = ns.AuraPerLine(cfg)
    return math.max(1, math.ceil(math.min(count, cfg.max) / per))
end

function ns.AuraBlockHeight(cfg, all, lines)
    return lines * ns.AuraRowHeight(cfg) + (lines - 1) * ns.AuraSpacing(cfg, all)
end

-- Rounded icons (the action bars' shape) or square ones: FrogLib's Auras.Shape.
local Shape = A.Shape

local function StyleButton(d)
    local cfg, db = d.cfg, ns.db
    if d.size ~= cfg.size and pcall(d.button.SetSize, d.button, cfg.size, cfg.size) then
        d.size = cfg.size
    end
    local size = ns.AuraTimerSize(cfg)
    -- Outlined (whatever the frames' outline), with a shadow: readable over any icon.
    ns.Media:SetFont(d.stack, db.font, size, "OUTLINE")
    ns.Media:SetFont(d.duration, db.font, size, "OUTLINE")
    d.duration:SetShown(cfg.showTimer)
    PlaceTexts(d.button, d.duration, d.stack, cfg)
end

-- styled: the row's list of styled buttons, restyled when the settings change.
local function MakeInit(styled, cfg, harmful, rounded)
    return function(button)
        local d = A.InitButton(button, { border = harmful and { 0.75, 0.12, 0.08 } or nil, rounded = rounded,
            shadow = true, seconds = true, style = function(new)
                new.cfg = cfg
                StyleButton(new)
            end })
        table.insert(styled, d)
    end
end

-- How many samples a row shows.
function ns.AuraSampleCount(row, cfg)
    return math.min(cfg.max, row == "buffs" and 8 or 6)
end

local function Layout(cfg, spacing)
    -- Extra line spacing leaves room for the timer printed under each icon.
    return { elementWidth = cfg.size, elementHeight = cfg.size, elementSpacing = spacing,
        lineSpacing = spacing + (ns.AuraTimerBelow(cfg) and TIMER_HEIGHT or 0) }
end

function ns.NewAuras(unit, settings)
    return setmetatable({
        unit = unit,
        settings = settings,
        -- Per row: its container, what it was built with, its group keys and its styled buttons.
        rows = { debuffs = { styled = {} }, buffs = { styled = {} } },
        samples = { debuffs = {}, buffs = {} },
    }, Auras)
end

local function Filter(row, cfg)
    if row == "buffs" then return "HELPFUL" end
    return cfg.mode == "mine" and "HARMFUL|PLAYER" or "HARMFUL"
end

-- How many auras the unit has for a row (up to its max), or nil when the game won't say.
function Auras:Count(row, cfg)
    if not UnitExists(self.unit) then return 0 end
    for i = 1, cfg.max do
        local ok, aura = pcall(C_UnitAuras.GetAuraDataByIndex, self.unit, i, Filter(row, cfg))
        if not ok or ns.issecret(aura) then return nil end
        if aura == nil then return i - 1 end
    end
    return cfg.max
end

-- Whether the unit has any auras for a row. How many there are can be secret, but whether there
-- are any isn't: the first one's data comes back, or nothing does.
function Auras:HasAny(row, cfg)
    if not UnitExists(self.unit) then return false end
    local ok, aura = pcall(C_UnitAuras.GetAuraDataByIndex, self.unit, 1, Filter(row, cfg))
    -- Can't tell: keep the row open.
    if not ok or ns.issecret(aura) then return true end
    return aura ~= nil
end

local function Signature(spec, rounded)
    local cfg = spec.cfg
    return table.concat({ cfg.mode or "", cfg.max, spec.x, spec.y, tostring(rounded),
        tostring(spec.anchor), spec.point or "TOPLEFT", spec.grow or "RIGHT", tostring(spec.up) }, "|")
end

function Auras:Build(row, parent, spec)
    local r, cfg = self.rows[row], spec.cfg
    A.Release(r.container)
    r.container = nil
    local c = A.NewContainer(parent)
    if not c then return end

    -- A row on the left of its frame starts at its right end and grows leftwards; a row above
    -- the frame starts at its bottom and wraps upwards.
    local point = spec.point or "TOPLEFT"
    c:SetPoint(point, spec.anchor, "TOPLEFT", spec.x, spec.y)
    A.Flow(c, point, spec.grow == "LEFT" and "LEFT" or "RIGHT", spec.up and "UP" or "DOWN")

    wipe(r.styled)
    r.keys = {}
    local all = self.settings()
    local layout = Layout(cfg, ns.AuraSpacing(cfg, all))
    local function add(key, filter, harmful)
        local ok2, err = pcall(c.AddAuraGroup, c, key, filter, {
            maxFrameCount = cfg.max, sortMethod = SORT, sortDirection = SORT_DIR,
            initializeFrame = MakeInit(r.styled, cfg, harmful, all.rounded), layout = layout,
        })
        if ok2 then r.keys[#r.keys + 1] = key else ns.Print("Couldn't set up status effects:", err) end
    end
    if row == "debuffs" then
        -- Yours first, then everyone else's.
        add("mine", "HARMFUL|PLAYER", true)
        if cfg.mode ~= "mine" then add("others", "HARMFUL|!PLAYER", true) end
    else
        add("buffs", "HELPFUL", false)
    end
    c:SetUnit(self.unit)
    c:UpdateAllAuras()
    r.container = c
    r.signature = Signature(spec, all.rounded)
end

-- specs[row]: where each row goes and whether it shows; a row with no spec is hidden (and isn't
-- built until it's wanted).
function Auras:Apply(parent, specs)
    local all = self.settings()
    for row, r in pairs(self.rows) do
        local spec = specs[row]
        if spec and spec.shown and (not r.container or r.signature ~= Signature(spec, all.rounded)) then
            self:Build(row, parent, spec)
        end
        local c = r.container
        if c then
            if spec then
                local sp = ns.AuraSpacing(spec.cfg, all)
                local layout = Layout(spec.cfg, sp)
                for _, key in ipairs(r.keys) do pcall(c.SetAuraGroupLayout, c, key, layout) end
                -- A line holds perRow icons, or all of them: it isn't cut at the bars' width.
                local per = ns.AuraPerLine(spec.cfg)
                A.SetLineSize(c, per * (spec.cfg.size + sp) - sp + 0.4)
                for _, d in ipairs(r.styled) do
                    d.cfg = spec.cfg
                    pcall(StyleButton, d)
                end
            end
            c:SetShown(spec ~= nil and spec.shown and not self.previewing)
        end
    end
end

------------------------------------------------------------------------------
-- While unlocked: pretend auras in each row where the real ones go (the real ones hidden), so
-- the layout can be judged without a unit that has any. Laid out as the real ones would be:
-- wrapping after perRow, upwards for a row above the frame.
------------------------------------------------------------------------------

local SAMPLES = {
    -- Debuffs in the colours of what can remove them: none (red), magic, poison, curse, disease.
    debuffs = {
        { icon = "Interface\\Icons\\Ability_Warrior_Sunder", time = "24s", stack = "3", color = { 0.8, 0.1, 0.1 } },
        { icon = "Interface\\Icons\\Spell_Shadow_ShadowWordPain", time = "18s", color = { 0.2, 0.6, 1 } },
        { icon = "Interface\\Icons\\Spell_Nature_CorrosiveBreath", time = "12s", stack = "2", color = { 0, 0.6, 0 } },
        { icon = "Interface\\Icons\\Spell_Shadow_CurseOfTounges", time = "2m", color = { 0.6, 0, 1 } },
        { icon = "Interface\\Icons\\Spell_Shadow_CallofBone", time = "9s", color = { 0.6, 0.4, 0 } },
        { icon = "Interface\\Icons\\Ability_Gouge", time = "4s", color = { 0.8, 0.1, 0.1 } },
    },
    -- Enough for a long row, with the longest timers ("59m") side by side.
    buffs = {
        { icon = "Interface\\Icons\\Spell_Holy_PowerWordShield", time = "25s" },
        { icon = "Interface\\Icons\\Spell_Nature_Rejuvenation", time = "9s" },
        { icon = "Interface\\Icons\\Spell_Holy_WordFortitude", time = "59m" },
        { icon = "Interface\\Icons\\Spell_Nature_Regeneration", time = "59m" },
        { icon = "Interface\\Icons\\Spell_Holy_MagicalSentry", time = "59m" },
        { icon = "Interface\\Icons\\Spell_Nature_LightningShield", time = "9m" },
        { icon = "Interface\\Icons\\Spell_Holy_SealOfWisdom", time = "1h" },
        { icon = "Interface\\Icons\\Spell_Nature_Thorns", time = "45s" },
    },
}

function Auras:Sample(parent, row, i)
    local s = self.samples[row][i]
    local rounded = self.settings().rounded
    -- A sample's shape is fixed when it's made, like a real icon's: remade if the shape changed.
    if s and s.rounded == rounded then return s end
    if s then s:Hide() end
    s = CreateFrame("Frame", nil, parent)
    s.border = s:CreateTexture(nil, "BACKGROUND")
    s.border:SetAllPoints()
    s.icon = s:CreateTexture(nil, "ARTWORK")
    s.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    Shape(s.icon, s.border, s, nil, rounded)
    s.rounded = rounded
    s.stack = s:CreateFontString(nil, "OVERLAY")
    s.duration = s:CreateFontString(nil, "OVERLAY")
    for _, fs in ipairs({ s.stack, s.duration }) do
        fs:SetShadowOffset(1, -1)
        fs:SetShadowColor(0, 0, 0, 1)
    end
    self.samples[row][i] = s
    return s
end

function Auras:Preview(parent, specs, on)
    local db = ns.db
    self.previewing = on
    for row, r in pairs(self.rows) do
        local spec = specs[row]
        if r.container then r.container:SetShown(spec ~= nil and spec.shown and not on) end
        local show = on and spec ~= nil and spec.shown
        for i, d in ipairs(SAMPLES[row]) do
            local s = self:Sample(parent, row, i)
            local fits = show and i <= spec.cfg.max
            if fits then
                local cfg = spec.cfg
                local size, fontSize = cfg.size, ns.AuraTimerSize(cfg)
                local sp = ns.AuraSpacing(cfg, self.settings())
                local per = ns.AuraPerLine(cfg)
                local col, line = (i - 1) % per, math.floor((i - 1) / per)
                local across = col * (size + sp)
                local away = line * (ns.AuraRowHeight(cfg) + sp)
                s:SetSize(size, size)
                s:ClearAllPoints()
                local x = spec.grow == "LEFT" and spec.x - across or spec.x + across
                local y = spec.up and spec.y + away or spec.y - away
                s:SetPoint(spec.point or "TOPLEFT", spec.anchor, "TOPLEFT", x, y)
                s.icon:SetTexture(d.icon)
                if row == "debuffs" then
                    s.border:SetColorTexture(d.color[1], d.color[2], d.color[3], 1)
                else
                    s.border:SetColorTexture(0, 0, 0, 1)
                end
                ns.Media:SetFont(s.stack, db.font, fontSize, "OUTLINE")
                ns.Media:SetFont(s.duration, db.font, fontSize, "OUTLINE")
                PlaceTexts(s, s.duration, s.stack, cfg)
                s.stack:SetText(d.stack or "")
                s.duration:SetText(cfg.showTimer and d.time or "")
            end
            s:SetShown(fits)
        end
    end
end

-- The containers are bound to a unit token ("target", "party1"); a new unit needs a fresh parse.
function Auras:UnitChanged()
    for _, r in pairs(self.rows) do
        if r.container then pcall(r.container.UpdateAllAuras, r.container) end
    end
end
