local _, ns = ...
local Auras = {}
Auras.__index = Auras

-- Status effects on a unit frame, in rows: debuffs (yours, then everyone else's) and buffs by the
-- target and focus, a short debuff row beside each party member. Each row is one of 12.1's
-- AuraContainers (FrogLib.Auras), so it keeps working where addons can't read aura data. How many
-- auras there are can be secret, so a row is given room for one line unless the game says.

local issecret = FrogLib.issecret
local AuraKit = FrogLib.Auras
local SORT = AuraContainerSortMethod and AuraContainerSortMethod.Default
local SORT_DIR = AuraContainerSortDirection and AuraContainerSortDirection.Normal
local TIMER_HEIGHT = 12 -- the timer printed under each icon

-- A row's settings (row: "debuffs" or "buffs"): enabled, mode, size, max, perRow, showTimer,
-- timerPos ("icon": on its bottom edge; "below": under it) and timerScale.

-- Whether a row's timers go under its icons (rather than on them).
function ns.AuraTimerBelow(settings)
    return settings.showTimer and settings.timerPos == "below"
end

-- How tall one line of a row is: its icons, and the timers when they're under them.
function ns.AuraRowHeight(settings)
    return settings.size + (ns.AuraTimerBelow(settings) and TIMER_HEIGHT or 0)
end

-- The timer's and stack count's font size: timerScale per cent of the icon (40 to start), 7 at least.
function ns.AuraTimerSize(settings)
    return math.max(7, math.floor(settings.size * (settings.timerScale or 40) / 100 + 0.5))
end

-- The gap between icons: the row's spacing; with the timers under the icons, widened so the
-- longest ("59m") clears the next one's. On the icons they fit inside, so it stays as set.
function ns.AuraSpacing(settings, all)
    local spacing = all.spacing or 2
    if ns.AuraTimerBelow(settings) then
        spacing = math.max(spacing, math.ceil(ns.AuraTimerSize(settings) * 2.6) - settings.size + 2)
    end
    return spacing
end

-- Where a button's timer and stack count go: the timer centred along the icon's bottom edge,
-- inside it, or under it; the count top right, or bottom right with the timer elsewhere.
local function PlaceTexts(button, duration, stack, settings)
    duration:ClearAllPoints()
    stack:ClearAllPoints()
    if ns.AuraTimerBelow(settings) or not settings.showTimer then
        duration:SetPoint("TOP", button, "BOTTOM", 0, -1)
        stack:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -1, 1)
    else
        duration:SetPoint("BOTTOM", button, "BOTTOM", 0, 1)
        stack:SetPoint("TOPRIGHT", button, "TOPRIGHT", -1, -1)
    end
end

-- How many icons go on a line: perRow, or all of them (max) on one long line.
function ns.AuraPerLine(settings)
    local perRow = settings.perRow or 0
    if perRow <= 0 or perRow > settings.max then return settings.max end
    return perRow
end

-- How many lines `count` icons take, and how tall they are together.
function ns.AuraLines(settings, count)
    local perLine = ns.AuraPerLine(settings)
    return math.max(1, math.ceil(math.min(count, settings.max) / perLine))
end

function ns.AuraBlockHeight(settings, all, lines)
    return lines * ns.AuraRowHeight(settings) + (lines - 1) * ns.AuraSpacing(settings, all)
end

-- Rounded icons (the action bars' shape) or square ones: FrogLib's Auras.Shape.
local Shape = AuraKit.Shape

local function StyleButton(parts)
    local settings, db = parts.cfg, ns.db
    if parts.size ~= settings.size and pcall(parts.button.SetSize, parts.button, settings.size, settings.size) then
        parts.size = settings.size
    end
    local size = ns.AuraTimerSize(settings)
    -- Outlined (whatever the frames' outline), with a shadow: readable over any icon.
    ns.SetFont(parts.stack, db.font, size, "OUTLINE")
    ns.SetFont(parts.duration, db.font, size, "OUTLINE")
    parts.duration:SetShown(settings.showTimer)
    PlaceTexts(parts.button, parts.duration, parts.stack, settings)
end

-- styled: the row's list of styled buttons, restyled when the settings change.
local function MakeInit(styled, settings, harmful, rounded)
    return function(button)
        local parts = AuraKit.InitButton(button, { border = harmful and { 0.75, 0.12, 0.08 } or nil, rounded = rounded,
            shadow = true, seconds = true, style = function(new)
                new.cfg = settings
                StyleButton(new)
            end })
        table.insert(styled, parts)
    end
end

-- How many samples a row shows.
function ns.AuraSampleCount(row, settings)
    return math.min(settings.max, row == "buffs" and 8 or 6)
end

local function Layout(settings, spacing)
    -- Extra line spacing leaves room for the timer printed under each icon.
    return { elementWidth = settings.size, elementHeight = settings.size, elementSpacing = spacing,
        lineSpacing = spacing + (ns.AuraTimerBelow(settings) and TIMER_HEIGHT or 0) }
end

-- settings(): the frame's auras table (rounded, spacing).
function ns.NewAuras(unit, settings)
    return setmetatable({
        unit = unit,
        settings = settings,
        -- Per row: its container (on a holder, which is what moves), what it was built with, its group keys
        -- and its styled buttons.
        rows = { debuffs = { styled = {} }, buffs = { styled = {} } },
        samples = { debuffs = {}, buffs = {} },
    }, Auras)
end

local function Filter(row, settings)
    if row == "buffs" then return "HELPFUL" end
    return settings.mode == "mine" and "HARMFUL|PLAYER" or "HARMFUL"
end

-- How many auras the unit has for a row (up to its max), or nil when the game won't say.
function Auras:Count(row, settings)
    if not UnitExists(self.unit) then return 0 end
    for i = 1, settings.max do
        local ok, aura = pcall(C_UnitAuras.GetAuraDataByIndex, self.unit, i, Filter(row, settings))
        if not ok or issecret(aura) then return nil end
        if aura == nil then return i - 1 end
    end
    return settings.max
end

-- Whether the unit has any auras for a row. How many there are can be secret, but whether there
-- are any isn't: the first one's data comes back, or nothing does.
function Auras:HasAny(row, settings)
    if not UnitExists(self.unit) then return false end
    local ok, aura = pcall(C_UnitAuras.GetAuraDataByIndex, self.unit, 1, Filter(row, settings))
    -- Can't tell: keep the row open.
    if not ok or issecret(aura) then return true end
    return aura ~= nil
end

-- Whether the row's container was built as the spec asks: only these need a new one. Where it goes doesn't,
-- as that's its holder's place.
local function Built(state, spec, rounded)
    return state.mode == spec.cfg.mode and state.max == spec.cfg.max and state.rounded == rounded
        and state.point == (spec.point or "TOPLEFT") and state.grow == spec.grow and state.up == spec.up
end

-- The holder's top left at the spec's place (the container's corner is pinned to it), moved only when that changes.
local function PlaceHolder(state, spec)
    if state.x == spec.x and state.y == spec.y and state.anchor == spec.anchor then return end
    state.x, state.y, state.anchor = spec.x, spec.y, spec.anchor
    state.holder:ClearAllPoints()
    state.holder:SetPoint("TOPLEFT", spec.anchor, "TOPLEFT", spec.x, spec.y)
end

-- spec = { cfg, anchor, x, y, shown, point, grow = "RIGHT" / "LEFT", up = true (wraps upwards) }: the
-- row's corner (point) goes x, y from the anchor's top left; it wraps after perRow, away from the frame.
function Auras:Build(row, parent, spec)
    local state, settings = self.rows[row], spec.cfg
    AuraKit.Release(state.container)
    state.container = nil
    local container = AuraKit.NewContainer(parent)
    if not container then return end
    -- A container can't move once it's set up, but what it's pinned to can: a plain 1x1 frame, so a row that
    -- only moves (another row folding or opening) keeps its container.
    if not state.holder then
        state.holder = CreateFrame("Frame", nil, parent)
        state.holder:SetSize(1, 1)
        state.holder:Hide() -- only something to pin to: placed all the same
    end
    PlaceHolder(state, spec)

    -- A row on the left of its frame starts at its right end and grows leftwards; a row above
    -- the frame starts at its bottom and wraps upwards.
    local point = spec.point or "TOPLEFT"
    container:SetPoint(point, state.holder, "TOPLEFT", 0, 0)
    AuraKit.Flow(container, point, spec.grow == "LEFT" and "LEFT" or "RIGHT", spec.up and "UP" or "DOWN")

    wipe(state.styled)
    state.keys = {}
    local all = self.settings()
    local layout = Layout(settings, ns.AuraSpacing(settings, all))
    local function Add(key, filter, harmful)
        local ok, message = pcall(container.AddAuraGroup, container, key, filter, {
            maxFrameCount = settings.max, sortMethod = SORT, sortDirection = SORT_DIR,
            initializeFrame = MakeInit(state.styled, settings, harmful, all.rounded), layout = layout,
        })
        if ok then state.keys[#state.keys + 1] = key else ns.Print("Couldn't set up status effects:", message) end
    end
    if row == "debuffs" then
        -- Yours first, then everyone else's.
        Add("mine", "HARMFUL|PLAYER", true)
        if settings.mode ~= "mine" then Add("others", "HARMFUL|!PLAYER", true) end
    else
        Add("buffs", "HELPFUL", false)
    end
    container:SetUnit(self.unit)
    container:UpdateAllAuras()
    state.container = container
    state.mode, state.max, state.rounded = settings.mode, settings.max, all.rounded
    state.point, state.grow, state.up = point, spec.grow, spec.up
    state.ffStyle = nil -- styled afresh by Apply
end

-- specs[row]: where each row goes and whether it shows; a row with no spec is hidden (and isn't
-- built until it's wanted).
function Auras:Apply(parent, specs)
    local all = self.settings()
    for row, state in pairs(self.rows) do
        local spec = specs[row]
        if spec and spec.shown then
            if not state.container or not Built(state, spec, all.rounded) then
                self:Build(row, parent, spec)
            else
                PlaceHolder(state, spec)
            end
        end
        local container = state.container
        if container then
            local settings = spec and spec.cfg
            local spacing = settings and ns.AuraSpacing(settings, all)
            local perLine = settings and ns.AuraPerLine(settings)
            -- Its layout and buttons only when what they're made from has changed (setting a layout has the
            -- engine lay out every button again).
            if settings and ns.Changed(state, settings.size, spacing, settings.timerScale, settings.showTimer,
                settings.timerPos, perLine, ns.db.font) then
                local layout = Layout(settings, spacing)
                for _, key in ipairs(state.keys) do pcall(container.SetAuraGroupLayout, container, key, layout) end
                -- A line holds perRow icons, or all of them: it isn't cut at the bars' width.
                AuraKit.SetLineSize(container, perLine * (settings.size + spacing) - spacing + 0.4)
                for _, parts in ipairs(state.styled) do
                    parts.cfg = settings
                    pcall(StyleButton, parts)
                end
            end
            container:SetShown(spec ~= nil and spec.shown and not self.previewing)
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
    local sample = self.samples[row][i]
    local rounded = self.settings().rounded
    -- A sample's shape is fixed when it's made, like a real icon's: remade if the shape changed.
    if sample and sample.rounded == rounded then return sample end
    if sample then sample:Hide() end
    sample = CreateFrame("Frame", nil, parent)
    sample.border = sample:CreateTexture(nil, "BACKGROUND")
    sample.border:SetAllPoints()
    sample.icon = sample:CreateTexture(nil, "ARTWORK")
    sample.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    Shape(sample.icon, sample.border, sample, nil, rounded)
    sample.rounded = rounded
    sample.stack = sample:CreateFontString(nil, "OVERLAY")
    sample.duration = sample:CreateFontString(nil, "OVERLAY")
    for _, text in ipairs({ sample.stack, sample.duration }) do
        text:SetShadowOffset(1, -1)
        text:SetShadowColor(0, 0, 0, 1)
    end
    self.samples[row][i] = sample
    return sample
end

-- The samples are made the first time the frames are unlocked; locked again, they're hidden once (Apply already
-- shows the containers as they should be while locked).
function Auras:Preview(parent, specs, on)
    local db = ns.db
    self.previewing = on
    if not (on or self.previewed) then return end
    self.previewed = on
    for row, state in pairs(self.rows) do
        local spec = specs[row]
        if state.container then state.container:SetShown(spec ~= nil and spec.shown and not on) end
        local show = on and spec ~= nil and spec.shown
        for i, example in ipairs(SAMPLES[row]) do
            local fits = show and i <= spec.cfg.max
            local sample = fits and self:Sample(parent, row, i) or self.samples[row][i]
            if fits then
                local settings = spec.cfg
                local size, fontSize = settings.size, ns.AuraTimerSize(settings)
                local spacing = ns.AuraSpacing(settings, self.settings())
                local perLine = ns.AuraPerLine(settings)
                local column, line = (i - 1) % perLine, math.floor((i - 1) / perLine)
                local across = column * (size + spacing)
                local away = line * (ns.AuraRowHeight(settings) + spacing)
                sample:SetSize(size, size)
                sample:ClearAllPoints()
                local x = spec.grow == "LEFT" and spec.x - across or spec.x + across
                local y = spec.up and spec.y + away or spec.y - away
                sample:SetPoint(spec.point or "TOPLEFT", spec.anchor, "TOPLEFT", x, y)
                sample.icon:SetTexture(example.icon)
                if row == "debuffs" then
                    sample.border:SetColorTexture(example.color[1], example.color[2], example.color[3], 1)
                else
                    sample.border:SetColorTexture(0, 0, 0, 1)
                end
                ns.SetFont(sample.stack, db.font, fontSize, "OUTLINE")
                ns.SetFont(sample.duration, db.font, fontSize, "OUTLINE")
                PlaceTexts(sample, sample.duration, sample.stack, settings)
                sample.stack:SetText(example.stack or "")
                sample.duration:SetText(settings.showTimer and example.time or "")
            end
            if sample then sample:SetShown(fits) end
        end
    end
end

-- The containers are bound to a unit token ("target", "party1"); a new unit needs a fresh parse.
function Auras:UnitChanged()
    for _, state in pairs(self.rows) do
        if state.container then pcall(state.container.UpdateAllAuras, state.container) end
    end
end
