local ADDON, ns = ...

-- FrogFrames: Classic-style unit frames for you, your pet, your target and its target, your focus
-- and your party (and their pets): a round portrait with the level in a badge on its edge, health
-- and power bars tucked in behind its ring, the name above. Unit.lua draws one; Frames.lua makes
-- them all. Settings per kind of frame live under units.<kind>; the look, font and icons at the top.

-- A frame's cast bar: shown or not; below or above the bars (side), next to them or beyond the auras
-- there (position "near" / "beyond"); the time left and the spell's icon; its size (width 0: the bars').
local function CastDefaults(height)
    return { enabled = true, side = "below", position = "near", showTime = true, icon = true, width = 0, height = height }
end

-- A frame's status effects, in rows (as FrogTarget's): debuffs (mode: yours, then everyone else's, or
-- only yours) and buffs, each below or above the bars (side). order: which row is nearer the bars.
local function AuraDefaults()
    return {
        -- fold: an empty row closes up, the rows beyond it moving in; rounded: like the action buttons.
        enabled = true, order = "debuffs", spacing = 2, rowGap = 4, rounded = true, fold = true,
        -- perRow: icons on a line before it wraps (0: one long line, up to max). timerPos "icon" (inside
        -- its bottom edge) or "below" (under it, the icons spaced to fit); timerScale: % of the icon.
        debuffs = { enabled = true, side = "below", mode = "all", size = 24, max = 12, perRow = 0,
            showTimer = true, timerPos = "icon", timerScale = 40 },
        buffs = { enabled = true, side = "below", size = 22, max = 12, perRow = 0,
            showTimer = true, timerPos = "icon", timerScale = 40 },
    }
end

-- No text on the bars (the small frames).
local function NoText()
    return { healthLeft = "", health = "", healthRight = "", powerLeft = "", power = "", powerRight = "" }
end

-- The settings every kind of frame has, with `own` over them. Sizes are in interface units, put on
-- whole pixels. text: templates for the three slots on each bar.
local function UnitDefaults(own)
    local defaults = {
        enabled = true,
        -- Blizzard's own 1.x frame art (Unit.lua's vanilla frame; not the party's pets): vanillaThick, a
        -- large health bar over the name box; vanillaTextures, the frame's own bar textures, not Classic's.
        vanilla = false, vanillaThick = false, vanillaTextures = false,
        vanillaLevelX = 0, vanillaLevelY = 0, -- the vanilla frame's level, nudged (any fraction)
        scale = 1,
        width = 112,            -- the bars' width (the portrait is beside them)
        healthHeight = 24,
        powerHeight = 10,       -- 0: no power bar
        -- "2d" (the game's picture), "3d" (a model; it can't be cut round, so it sits in the
        -- square inside the ring), "class" (the class icon; NPCs fall back to "2d") or "none".
        portrait = "2d",
        portraitSize = 56,      -- across the ring
        -- The name: "above" the health bar, "inside" it (at the portrait's end), or "none".
        namePos = "above",
        nameFull = true,        -- above: a long name runs on over the portrait rather than being cut short
        showLevel = true,       -- in a badge on the portrait's edge (above the bars without one)
        nameSize = 10,
        textSize = 10,
        text = { healthLeft = "", health = "value / max", healthRight = "", powerLeft = "", power = "percent", powerRight = "",
            druidLeft = "", druid = "", druidRight = "" }, -- druid: your druid mana bar's (the player frame)
        hitText = false,        -- damage and heals floating over the portrait (Blizzard's combat feedback)
        fadeRange = false,      -- fade while out of range
        -- Nudges in interface units, right and up +: the portrait, the bars, each text slot (the end ones
        -- 4 in from their ends), the name, badge, resting icon, and each part hanging off the frame.
        offsets = {
            portraitX = 0, portraitY = 0, barsX = 0, barsY = 0,
            healthLeftX = 4, healthLeftY = 0, healthX = 0, healthY = 0, healthRightX = -4, healthRightY = 0,
            powerLeftX = 4, powerLeftY = 0, powerX = 0, powerY = 0, powerRightX = -4, powerRightY = 0,
            nameX = 0, nameY = 0, levelX = 0, levelY = 0, restX = 0, restY = 0,
            castX = 0, castY = 0, debuffsX = 0, debuffsY = 0, buffsX = 0, buffsY = 0, druidX = 0, druidY = 0,
            happinessX = 0, happinessY = 0, -- the pet's happiness face
        },
        -- The bars' textures: "general" (the General page's), "" (the look's own) or a file.
        healthTexture = "general",
        powerTexture = "general",
        -- Fade when idle: out of combat, health full, power at rest and (noTarget) nothing
        -- targeted, to `alpha`.
        fade = { enabled = false, alpha = 0, noTarget = true },
    }
    for key, value in pairs(own) do defaults[key] = value end
    return defaults
end

ns.defaults = {
    locked = true,
    configOpen = {}, -- which sections of each settings page are open (Config.lua)
    -- The look: "classic", "modern", "forever" or "stone". texture "" uses the look's own bar texture.
    look = "classic",
    texture = "",
    frameThickness = 1, -- the classic and forever frames: screen pixels per pixel of their art (1 to 3)
    font = "Fonts\\FRIZQT__.TTF",
    outline = "OUTLINE",
    -- "class": players in their class colour, NPCs by reaction (hostile red, neutral yellow,
    -- friendly green); "green": always green, like the original game. Tapped enemies are grey.
    healthColor = "class",
    -- The name above the bars: "gold" (like the game's), "white" or "unit" (the health colour).
    nameColor = "gold",
    levelColor = true, -- the level coloured by difficulty, a skull when it's too high to show
    rangeAlpha = 0.45, -- how faded a frame is while its unit is out of range
    icons = { raid = true, leader = true, status = true, pvp = false, happiness = true, size = 16,
        role = true, roleDamage = true }, -- role: the group role (or main tank / assist) on your frame and the party's
    -- Combo points: a row of pips by the player's or the target's bars (on: "player"/"target"),
    -- below or above them (side).
    combo = { enabled = true, on = "target", side = "below", height = 6, spacing = 1, x = 0, y = 0,
        color = { r = 1, g = 0.82, b = 0.1 }, maxColor = { r = 1, g = 0.35, b = 0.1 } },
    units = {
        player = UnitDefaults({
            point = { "TOPLEFT", "UIParent", "TOPLEFT", 24, -28 },
            druidMana = true,   -- your mana by the bars while a druid form shows rage or energy
            druidManaHeight = 6,
            druidTextSize = 0,  -- its text's size (0: the bar text's, no taller than the bar)
            manaRule = true,    -- the five-second rule: a strip along whichever bar shows your mana
            healPredict = true, -- incoming heals (yours, others') and shields on the health bar
            -- Your own cast bar (off to start; Blizzard's stays): in a vanilla frame, 1.x's player cast bar.
            cast = (function() local cast = CastDefaults(13); cast.enabled = false; cast.side = "below"; return cast end)(),
            druidManaSide = "below",
            glow = false,       -- a soft light round the frame while resting (gold) or fighting (red)
            -- Resting "zzz": "portrait" (its top outer corner), "badge" (beside the level badge)
            -- or "none".
            restPos = "portrait",
            fade = { enabled = true, alpha = 0, noTarget = true },
            threat = true,      -- ... and yellow to red while enemies are on you
        }),
        pet = UnitDefaults({
            attach = { "TOPLEFT", "BOTTOMLEFT", 40, -12 }, -- from the player frame
            width = 64, healthHeight = 10, powerHeight = 5, portraitSize = 30,
            showLevel = false, nameSize = 9, textSize = 8, text = NoText(),
            fade = { enabled = true, alpha = 0, noTarget = true }, -- with your own frame
            healPredict = true,
        }),
        target = UnitDefaults({
            point = { "TOPLEFT", "UIParent", "TOPLEFT", 290, -28 },
            text = { healthLeft = "", health = "value / max", healthRight = "", powerLeft = "", power = "", powerRight = "" },
            fadeRange = true,
            cast = CastDefaults(11),
            auras = AuraDefaults(),
            dragons = true,     -- the elite / rare dragon round the portrait
        }),
        tot = UnitDefaults({
            attach = { "LEFT", "RIGHT", 40, 0 }, -- from the target frame
            width = 64, healthHeight = 10, powerHeight = 5, portraitSize = 30,
            showLevel = false, nameSize = 9, textSize = 8, text = NoText(),
        }),
        focus = UnitDefaults({
            point = { "TOPLEFT", "UIParent", "TOPLEFT", 290, -250 },
            width = 96, healthHeight = 18, powerHeight = 8, portraitSize = 48, textSize = 9,
            text = { healthLeft = "", health = "value / max", healthRight = "", powerLeft = "", power = "", powerRight = "" },
            fadeRange = true,
            cast = CastDefaults(10), auras = AuraDefaults(), dragons = true,
        }),
        party = UnitDefaults({
            point = { "TOPLEFT", "UIParent", "TOPLEFT", 24, -190 },
            width = 84, healthHeight = 14, powerHeight = 6, portraitSize = 40, nameSize = 9, textSize = 8,
            text = { healthLeft = "", health = "percent", healthRight = "", powerLeft = "", power = "", powerRight = "" },
            fadeRange = true,
            spacing = 26,       -- between one party frame and the next
            healPredict = true, -- incoming heals and shields on the health bar
            hideInRaid = true,  -- Blizzard's party frames go in a raid too
            threat = true,
            -- A short row of debuffs by each frame: side "right", "left", "above" or "below".
            auras = {
                enabled = true, spacing = 2, rounded = true, fold = true,
                debuffs = { enabled = true, side = "right", mode = "all", size = 18, max = 4, perRow = 0,
                    showTimer = false, timerPos = "icon", timerScale = 40 },
            },
        }),
        partypet = UnitDefaults({
            enabled = false,
            -- One thin bar with the pet's name on it, to fit in the gap under each party frame.
            attach = { "TOPLEFT", "BOTTOMLEFT", 44, -3 }, -- from each party frame
            width = 60, healthHeight = 9, powerHeight = 0, portrait = "none", portraitSize = 20,
            namePos = "inside", showLevel = false, nameSize = 8, textSize = 8, text = NoText(),
            fadeRange = true,
            healPredict = true,
        }),
    },
}

ns.Print = FrogLib.Util.Printer("FrogFrames", "66dd66")
-- The bar textures and fonts the settings offer, and setting a font safely (FrogLib's Media).
ns.Media = FrogLib.Media.New()

-- A font set only when it isn't already the one asked for: layouts run on every fold of an aura row, and
-- Media's SetFont does real work each time. A drop shadow's offset follows the pixel size, so it's set every time.
function ns.SetFont(fontString, path, size, outline)
    if outline ~= "SHADOW" and fontString.ffFont == path and fontString.ffSize == size
        and fontString.ffOutline == outline then return end
    fontString.ffFont, fontString.ffSize, fontString.ffOutline = path, size, outline
    ns.Media:SetFont(fontString, path, size, outline)
end

-- The same for a name: through a font family, so names in other scripts draw.
function ns.SetNameFont(fontString, path, size, outline)
    if outline ~= "SHADOW" and fontString.ffFont == path and fontString.ffSize == size
        and fontString.ffOutline == outline then return end
    fontString.ffFont, fontString.ffSize, fontString.ffOutline = path, size, outline
    ns.Media:SetNameFont(fontString, path, size, outline)
end

-- Whether any of the values differ from the ones `owner` was last styled with (noting them if so): the styling
-- in a layout is done again only when what it's made from has changed.
function ns.Changed(owner, ...)
    local last = owner.ffStyle
    if not last then
        last = {}
        owner.ffStyle = last
    end
    local changed = false
    for i = 1, select("#", ...) do
        local value = select(i, ...)
        if last[i] ~= value then
            last[i] = value
            changed = true
        end
    end
    return changed
end

local CopyDefaults = FrogLib.Util.CopyDefaults

------------------------------------------------------------------------------
-- Text templates
------------------------------------------------------------------------------

-- A font string from a template for a unit (FrogLib.Unit's words: name, level, class, value, max,
-- percent...). fake: the words' values for a sample; power: value, max and percent are the unit's
-- power (of `kind`); values: what was read for the bar a moment ago ({ value, max }), so it isn't
-- asked for again. Values may be secret: only ever formatted engine-side by SetFormattedText.
local textOptions = {}
local blank = {} -- [template] = whether it has nothing to show (asked once per template)

-- Hides a font string once: it's asked on every update, and a hidden one stays hidden until it's shown again
-- (by a template with words in it, or by the health bar's status, which clears the mark).
function ns.HideText(fontString)
    if fontString.ffHidden then return end
    fontString:Hide()
    fontString.ffHidden = true
end

function ns.SetUnitText(fontString, template, unit, fake, power, kind, values)
    local empty = type(template) ~= "string" or blank[template]
    if empty == nil then
        empty = not template:find("%S")
        blank[template] = empty
    end
    if empty then
        ns.HideText(fontString)
        return
    end
    fontString.ffHidden = nil
    textOptions.fake, textOptions.power, textOptions.kind, textOptions.values = fake or nil, power, kind, values
    textOptions.levelColor = ns.db.levelColor
    textOptions.classColor = true
    FrogLib.Unit.SetText(fontString, template, unit, textOptions)
end

------------------------------------------------------------------------------
-- Applying settings
------------------------------------------------------------------------------

-- Unit frames are protected: their size, place and visibility can't change in combat. A change
-- made then (from the settings, or a new look) waits for the end of the fight.
local pending, told
function ns.Refresh()
    if not ns.ready then return end
    -- What each frame listens to (and the parts that need it) follows at once, even in combat: none of it is
    -- protected.
    for _, frame in ipairs(ns.frameList) do frame:RegisterEvents() end
    ns.UpdateTicker()
    if InCombatLockdown() then
        pending = true
        if not told then
            told = true
            ns.Print("the change will show when you leave combat.")
        end
        return
    end
    pending, told = nil, nil
    ns.ApplyAll()
end

-- FrogTarget's target bar (always on while FrogTarget is) and focus bar draw the same units as
-- ours: said once a session, so you know why there are two.
local warned
function ns.CheckFrogTarget()
    if warned or not FrogLib.Loaded("FrogTarget") then return end
    local units, frogTarget = ns.db.units, _G.FrogTargetDB
    local both = {}
    if units.target.enabled then both[#both + 1] = "target" end
    if units.focus.enabled and type(frogTarget) == "table" and type(frogTarget.focus) == "table"
        and frogTarget.focus.enabled then
        both[#both + 1] = "focus"
    end
    if #both > 0 then
        warned = true
        ns.Print("FrogTarget is showing your " .. table.concat(both, " and ")
            .. " too. Switch one of them off (FrogFrames: /ff; FrogTarget: /ft) if you only want one.")
    end
end

-- Settings saved by an earlier build, brought up to date, a step for each version.
local Merge = FrogLib.Util.Merge -- source's values over target's

function ns.Migrate(db)
    local version = db.version
    if not version then return end
    local units = type(db.units) == "table" and db.units or {}
    if version < 2 then
        -- 0.1's first test build had a name strip and one box round the bars: its frames take
        -- the new shape's sizes (keeping where they are, whether they're on and their scale), and
        -- its cast bar places get their new names.
        local SHAPE = { "width", "healthHeight", "powerHeight", "portrait", "portraitSize", "nameSize",
            "textSize", "text", "showLevel" }
        for kind, saved in pairs(units) do
            if type(saved) == "table" and ns.defaults.units[kind] then
                for _, key in ipairs(SHAPE) do saved[key] = nil end
                saved.nameHeight, saved.bigHealth = nil, nil
            end
        end
        db.nameStrip, db.borderColor = nil, nil
        if type(db.cast) == "table" then
            db.cast.position = db.cast.position == "auras" and "beyond" or "near"
        end
        if type(db.combo) == "table" then db.combo.spacing = nil end
    end
    if version < 3 then
        -- The first redesign's test build: a bar texture picked in 0.1's first build hid the new
        -- look's glossy fill, so the look's own comes back; the resting glow is off now; the cast
        -- bar's height became each frame's own.
        db.texture = nil
        if type(units.player) == "table" then units.player.glow = nil end
        if type(db.cast) == "table" then db.cast.height = nil end
    end
    if version < 4 then
        -- The cast bar and the auras were shared by the target and focus: each gets its own copy
        -- of what was set, so nothing moves; the party's debuff row joins its own auras.
        local cast = type(db.cast) == "table" and db.cast or {}
        local auras = type(db.auras) == "table" and db.auras or {}
        db.units = units
        for _, kind in ipairs({ "target", "focus" }) do
            if type(units[kind]) ~= "table" then units[kind] = {} end
            local saved = units[kind]
            local ownCast = {}
            Merge(cast, ownCast)
            if type(saved.cast) == "boolean" then ownCast.enabled = saved.cast end
            ownCast.width, ownCast.height = saved.castWidth, saved.castHeight
            saved.cast, saved.castWidth, saved.castHeight = ownCast, nil, nil
            local ownAuras = {}
            Merge(auras, ownAuras)
            if type(saved.auras) == "boolean" then ownAuras.enabled = saved.auras end
            saved.auras = ownAuras
        end
        local party = units.party
        if type(party) == "table" and type(party.debuffs) == "table" then
            party.auras = { spacing = auras.spacing, rounded = auras.rounded, fold = auras.fold, debuffs = {} }
            Merge(party.debuffs, party.auras.debuffs)
            party.debuffs = nil
        end
        db.cast, db.auras = nil, nil
    end
    if version < 5 then
        -- The gap between the portrait and the bars became the bars' own left / right offset
        -- (away from the portrait: right for frames with it on the left, left for the others).
        for kind, saved in pairs(units) do
            local offsets = type(saved) == "table" and saved.offsets
            if type(offsets) == "table" and offsets.gap then
                local mirrored = kind == "target" or kind == "focus"
                offsets.barsX = (offsets.barsX or 0) + (mirrored and -offsets.gap or offsets.gap)
                offsets.gap = nil
            end
        end
    end
    if version < 6 then
        -- Each bar had one inset for its end texts and one up/down for all three: each text has
        -- its own x and y now, set to the same places.
        for _, saved in pairs(units) do
            local offsets = type(saved) == "table" and saved.offsets
            if type(offsets) == "table" then
                for _, bar in ipairs({ "health", "power" }) do
                    local pad, y = offsets[bar .. "Pad"], offsets[bar .. "TextY"]
                    if pad ~= nil or y ~= nil then
                        pad, y = pad or 4, y or 0
                        offsets[bar .. "LeftX"], offsets[bar .. "RightX"], offsets[bar .. "X"] = pad, -pad, 0
                        offsets[bar .. "LeftY"], offsets[bar .. "Y"], offsets[bar .. "RightY"] = y, y, y
                    end
                    offsets[bar .. "Pad"], offsets[bar .. "TextY"] = nil, nil
                end
            end
        end
    end
    if version < 7 then
        -- Bigger icons and closer together (their timers went onto them): where the old
        -- defaults are still set, the new ones; sizes and spacing that were changed stay.
        local OLD = { target = { 22, 18 }, focus = { 22, 18 }, party = { 16 } }
        local NEW = { target = { 24, 22 }, focus = { 24, 22 }, party = { 18 } }
        for kind, old in pairs(OLD) do
            local auras = type(units[kind]) == "table" and units[kind].auras
            if type(auras) == "table" then
                local rows = { auras.debuffs, auras.buffs }
                for i, size in ipairs(old) do
                    local row = rows[i]
                    if type(row) == "table" and row.size == size then row.size = NEW[kind][i] end
                end
                if auras.spacing == 3 then auras.spacing = 2 end
            end
        end
    end
    if version < 8 then
        -- The pet's frame fades when idle too, like your own (it was left out).
        local fade = type(units.pet) == "table" and units.pet.fade
        if type(fade) == "table" then fade.enabled = true end
    end
end

-- UI scale: the pixel sizes change. A window being resized sends a stream of these: applied once a frame.
local scaleQueued
local function ScaleChanged()
    scaleQueued = nil
    ns.Refresh()
end

local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:RegisterEvent("PLAYER_LOGIN")
loader:RegisterEvent("PLAYER_REGEN_ENABLED")
loader:RegisterEvent("PLAYER_REGEN_DISABLED")
loader:RegisterEvent("UI_SCALE_CHANGED")
loader:RegisterEvent("DISPLAY_SIZE_CHANGED")
loader:SetScript("OnEvent", function(_, event, addonName)
    if event == "ADDON_LOADED" then
        if addonName ~= ADDON then return end
        loader:UnregisterEvent("ADDON_LOADED")
        FrogFramesDB = FrogFramesDB or {}
        local db = FrogFramesDB
        ns.Migrate(db)
        ns.Migrate = nil -- never needed again
        CopyDefaults(ns.defaults, db)
        db.version = 8
        ns.db = db
    elseif event == "PLAYER_LOGIN" or (event == "PLAYER_REGEN_ENABLED" and not ns.ready and ns.db) then
        loader:UnregisterEvent("PLAYER_LOGIN")
        -- The frames are secure: made out of combat (a reload mid-fight waits for its end).
        if InCombatLockdown() then return end
        ns.BuildAll()
        ns.ready = true
        ns.Refresh()
        C_Timer.After(3, ns.CheckFrogTarget)
    elseif event == "PLAYER_REGEN_DISABLED" then
        -- Unlocked frames show samples and can't be dragged in combat: lock them as it starts
        -- (this runs a moment before the lockdown does, so the frames can still be changed).
        if ns.ready and not ns.db.locked then
            ns.db.locked = true
            ns.ApplyAll()
            ns.Print("locked the frames for the fight.")
        end
    elseif event == "PLAYER_REGEN_ENABLED" then
        if pending then ns.Refresh() end
    elseif ns.ready and not scaleQueued then
        scaleQueued = true
        C_Timer.After(0, ScaleChanged)
    end
end)

SLASH_FROGFRAMES1 = "/ff"
SLASH_FROGFRAMES2 = "/frogframes"
SlashCmdList.FROGFRAMES = function(input)
    local command = strtrim((input or ""):lower())
    if command == "unlock" or command == "lock" or command == "move" then
        if InCombatLockdown() then
            ns.Print("frames can't be moved in combat.")
            return
        end
        ns.db.locked = command == "lock" or (command == "move" and not ns.db.locked)
        ns.Refresh()
        ns.Print(ns.db.locked and "frames locked." or "frames unlocked: drag them to move (samples show where there's no unit).")
        return
    end
    if command == "idle" then
        for _, frame in ipairs(ns.frameList or {}) do
            if frame.root:IsShown() then frame:IdleReport() end
        end
        return
    end
    ns.Config:Toggle()
end

function FrogFrames_OnCompartmentClick()
    ns.Config:Toggle()
end
