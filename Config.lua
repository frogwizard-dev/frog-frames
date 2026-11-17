local _, ns = ...
local Config = {}
ns.Config = Config

local WIDTH, HEIGHT = 700, 640

-- The controls are FrogLib's (UI.lua); every change calls ns.Refresh().
local UI = FrogLib.UI.Kit({ column = 250, dropWidth = 230, helpWidth = WIDTH - 90, refresh = function() ns.Refresh() end })
local Label, Button, Checkbox, Stepper, Dropdown, Options, ColorSwatch, TextBox, Pair, XY, Help =
    UI.Label, UI.Button, UI.Checkbox, UI.Stepper, UI.Dropdown, UI.Options, UI.ColorSwatch, UI.TextBox, UI.Pair,
    UI.XY, UI.Help

local LOOKS = Options("classic", "Classic (glossy, dark bevelled frames)", "modern", "Modern (flat, 1px edge)",
    "forever", "Forever (cooldown manager bars)", "stone", "Stone (Classic action bar's carved frame)")
local PORTRAITS = Options("2d", "Picture", "3d", "3D model (square, inside the ring)", "class", "Class icon (players)",
    "none", "None")
local HEALTH_COLORS = Options("class", "Class colour / reaction", "green", "Always green (Classic)")
local NAME_COLORS = Options("gold", "Gold, like the game's", "white", "White", "unit", "The health bar's colour")
local NAME_POS = Options("above", "Above the health bar", "inside", "On the health bar", "none", "Hidden")
local SIDES = Options("below", "Below the bars", "above", "Above the bars")
local PARTY_SIDES = Options("right", "Right of the frame", "left", "Left of the frame", "above", "Above the bars",
    "below", "Below the bars")
local AURA_MODES = Options("mine", "Only mine", "all", "Mine, then everyone else's")

-- A bar texture setting (settings[key]): "Use General's", "The look's own", then every bar texture
-- FrogLib knows (FrogUI's Frog bars when it's loaded), with a swatch showing the choice.
local function TextureChoice(parent, text, settings, key, color, general)
    local swatch
    local function Show()
        if swatch then
            ns.PaintBarTexture(swatch, settings[key])
            swatch:SetVertexColor(color[1], color[2], color[3])
        end
    end
    local control = Dropdown(parent, text, function()
        local groups = ns.Media:List("statusbar")
        local first = { { name = "The look's own", path = "" } }
        if not general then table.insert(first, 1, { name = "Use General's", path = "general" }) end
        table.insert(groups, 1, { items = first })
        return groups
    end, function() return settings[key] end, function(value)
        settings[key] = value
        Show()
    end)
    swatch = control:CreateTexture(nil, "ARTWORK")
    swatch:SetSize(64, 12)
    swatch:SetPoint("LEFT", 490, 0)
    control:HookScript("OnShow", Show)
    Show()
    return control
end

-- A page of headers that open and close (click), each with its controls under it; which are open is
-- kept per page in the saved settings (configOpen).
local function Sections(page, pageKey)
    local saved = ns.db.configOpen
    saved[pageKey] = saved[pageKey] or {}
    return UI.Sections(page, saved[pageKey], WIDTH - 70)
end

------------------------------------------------------------------------------
-- Pages
------------------------------------------------------------------------------

function Config:BuildGeneral(page)
    local db = ns.db
    local Add, Relayout = Sections(page, "general")
    local place, body = Add("frames", "Frames", true)
    place(Checkbox(body, "Unlock to move (drag the frames; samples show where there's no unit)",
        function() return not db.locked end, function(value) db.locked = not value end), 28)
    place(Help(body, "Drag the first party frame to move them all. Your pet, your target's target and the party's "
        .. "pets move with the frame they hang from; drag them to place them beside it. Release near the middle "
        .. "of the screen to centre a frame. /ff unlock and /ff lock work too."), 40, 4)

    place, body = Add("look", "Look", true)
    place(Dropdown(body, "Look", LOOKS, db, "look"), 30)
    place(TextureChoice(body, "Bar texture (every frame)", db, "texture", { 0.25, 0.8, 0.25 }, true), 30)
    place(Help(body, "Each frame can pick its own on its page (Look)."), 20, 4)
    place(Stepper(body, "Frame thickness (pixels per line)", 1, 3, 1, db, "frameThickness"), 32)
    place(Dropdown(body, "Font", function() return ns.Media:List("font") end, db, "font"), 30)
    place(Dropdown(body, "Font outline", UI.OUTLINES, db, "outline"), 30)
    place(Dropdown(body, "Health bar colour", HEALTH_COLORS, db, "healthColor"), 30)
    place(Dropdown(body, "Name colour", NAME_COLORS, db, "nameColor"), 30)
    place(Checkbox(body, "Colour the level by difficulty, with a skull for bosses", db, "levelColor"), 28)
    place(Stepper(body, "Out of range opacity", 0.1, 1, 0.05, db, "rangeAlpha", "%.2f"), 28)

    place, body = Add("icons", "Icons", false)
    for _, entry in ipairs({
        { "raid", "Raid target marks" },
        { "leader", "Group leader / assistant" },
        { "role", "Group role: tank, healer, damage (your frame and the party's)" },
        { "roleDamage", "...damage too (off: only tanks and healers)" },
        { "status", "Resting and in combat (your frame)" },
        { "pvp", "PvP flag (players)" },
        { "happiness", "A hunter's pet's happiness (its frame)" },
    }) do
        place(Checkbox(body, entry[2], db.icons, entry[1]), 26)
    end
    place(Stepper(body, "Icon size", 8, 40, 1, db.icons, "size"), 28)

    local combo = db.combo
    place, body = Add("combo", "Combo points (rogues, druids in cat form)", false)
    place(Checkbox(body, "Show combo points", combo, "enabled"), 26)
    place(Dropdown(body, "On", Options("target", "The target frame", "player", "Your frame"), combo, "on"), 30)
    place(Dropdown(body, "Where", SIDES, combo, "side"), 30)
    place(Stepper(body, "Height", 2, 20, 1, combo, "height"), 26)
    place(Stepper(body, "Gap between them (pixels)", 0, 20, 1, combo, "spacing"), 26)
    place(Pair(body, "Offset", { "x", -40, 40, combo, "x" }, { "y", -40, 40, combo, "y" }), 26)
    place(ColorSwatch(body, "Colour", combo, "color"), 26)
    place(ColorSwatch(body, "Colour when full", combo, "maxColor"), 26)
    Relayout()
end

local PARENTS = { pet = "From your frame", tot = "From the target frame", partypet = "From the party member" }

-- Every kind of frame's page, in sections: Frame, Place, Vanilla frame, Fading, Size, Look, Fine
-- nudges, Text, then its cast bar, buffs & debuffs and extras where it has them.
function Config:BuildUnit(page, kind)
    local settings = ns.db.units[kind]
    local offsets = settings.offsets
    local cast, auras = settings.cast, settings.auras
    local Add, Relayout = Sections(page, kind)

    -- Frame: on or off, and what it shows.
    local place, body = Add("frame", "Frame", true)
    place(Checkbox(body, "Show this frame (hides Blizzard's while it's on)", settings, "enabled"), 30)
    place(Dropdown(body, "Portrait", PORTRAITS, settings, "portrait"), 30)
    place(Dropdown(body, "Name", NAME_POS, settings, "namePos"), 30)
    place(Checkbox(body, "Long names run on over the portrait (name above the bars)", settings, "nameFull"), 26, 20)
    place(Checkbox(body, "Show the level (in a badge on the portrait)", settings, "showLevel"), 26)

    -- Place: where it is, typed (any fraction): from its anchor on the screen, or from the frame it
    -- hangs from. Looked up each time: dragging the frame or a reset saves a new place.
    place, body = Add("place", "Place", true)
    local function Where() return settings.attach or settings.point end
    local first = settings.attach and 3 or 4
    if settings.attach then place(Label(body, PARENTS[kind], "GameFontHighlightSmall"), 20, 4) end
    for i, axis in ipairs({ "Position across (right +)", "Position up (+)" }) do
        local index = first + i - 1
        place(TextBox(body, axis, function() return tostring(Where()[index] or 0) end, function(value)
            local number = tonumber(value)
            if number then
                Where()[index] = number
                ns.Refresh()
            end
        end), 28)
    end
    if settings.spacing then
        place(Stepper(body, "Gap between frames", 0, 80, 1, settings, "spacing"), 28)
    end
    local reset = Button(body, "Reset position", 130)
    reset:SetScript("OnClick", function()
        local defaults = ns.defaults.units[kind]
        if defaults.point then settings.point = FrogLib.Util.Copy(defaults.point) end
        if defaults.attach then settings.attach = FrogLib.Util.Copy(defaults.attach) end
        ns.Refresh()
    end)
    place(reset, 30, 6)

    -- The vanilla frame: Blizzard's 1.x art.
    if kind ~= "partypet" then
        local big = kind == "player" or kind == "target" or kind == "focus"
        place, body = Add("vanilla", "Vanilla frame", settings.vanilla and true or false)
        place(Checkbox(body, "Vanilla frame: Blizzard's own 1.x art (its own sizes; Scale still applies)",
            settings, "vanilla"), 26)
        if big then
            place(Checkbox(body, "Large health bar (over the name box; the name above)", settings, "vanillaThick"), 26, 20)
        end
        place(Checkbox(body, "This frame's own bar textures (off: Classic's)", settings, "vanillaTextures"), 28, 20)
        -- The level's nudge in the vanilla frame, typed (any fraction: 1.25, -0.5).
        if big then
            for _, axis in ipairs({ { "X", "Level nudge across (right +)" }, { "Y", "Level nudge up (+)" } }) do
                local key = "vanillaLevel" .. axis[1]
                place(TextBox(body, axis[2], function() return tostring(settings[key] or 0) end, function(value)
                    local number = tonumber(value)
                    if number then settings[key] = number end
                end), 28, 20)
            end
        end
    end

    -- Fading.
    place, body = Add("fading", "Fading", false)
    place(Checkbox(body, "Fade while out of range", settings, "fadeRange"), 26)
    local fade = settings.fade
    place(Checkbox(body, "Fade when idle: out of combat, health full, power at rest", fade, "enabled"), 26)
    place(Checkbox(body, "Only with nothing targeted", fade, "noTarget"), 26, 20)
    place(Stepper(body, "Faded opacity", 0, 1, 0.05, fade, "alpha", "%.2f"), 28, 20)

    -- Size.
    place, body = Add("size", "Size", true)
    place(Stepper(body, "Scale", 0.5, 2, 0.05, settings, "scale", "%.2f"), 26)
    place(Stepper(body, "Bar width", 30, 400, 2, settings, "width"), 26)
    place(Stepper(body, "Health bar height", 4, 60, 1, settings, "healthHeight"), 26)
    place(Stepper(body, "Power bar height (0: none)", 0, 40, 1, settings, "powerHeight"), 26)
    place(Stepper(body, "Portrait size (across the ring)", 16, 140, 1, settings, "portraitSize"), 26)
    if cast then
        place(Stepper(body, "Cast bar width (0: the bars')", 0, 400, 2, cast, "width"), 26)
        place(Stepper(body, "Cast bar height", 4, 40, 1, cast, "height"), 26)
    end
    if auras then
        place(Stepper(body, "Debuff icon size", 10, 48, 1, auras.debuffs, "size"), 26)
        if auras.buffs then
            place(Stepper(body, "Buff icon size", 10, 48, 1, auras.buffs, "size"), 26)
        end
    end
    place(Help(body, "Shift-click + or - for ten steps at once."), 18, 4)

    -- Look: the bars' textures.
    place, body = Add("look", "Look", false)
    place(TextureChoice(body, "Health bar texture", settings, "healthTexture", { 0.25, 0.8, 0.25 }), 30)
    place(TextureChoice(body, "Power bar texture", settings, "powerTexture", { 0.2, 0.35, 1 }), 30)
    if settings.healPredict ~= nil then
        place(Checkbox(body, "Incoming heals (yours brighter) and shields on the health bar", settings, "healPredict"), 26)
    end

    -- Fine nudges: each part, x and y (right and up are +).
    place, body = Add("offsets", "Fine nudges", false)
    place(XY(body, "Portrait", offsets, "portrait"), 26)
    place(XY(body, "Bars", offsets, "bars"), 26)
    place(XY(body, "Name", offsets, "name"), 26)
    place(XY(body, "Level badge", offsets, "level"), 26)
    if settings.restPos then place(XY(body, "Resting zzz", offsets, "rest"), 26) end
    if kind == "pet" then place(XY(body, "Happiness face", offsets, "happiness"), 26) end
    for _, bar in ipairs({ { "health", "Health" }, { "power", "Power" } }) do
        place(XY(body, bar[2] .. " text, left", offsets, bar[1] .. "Left", 60), 26)
        place(XY(body, bar[2] .. " text, middle", offsets, bar[1], 60), 26)
        place(XY(body, bar[2] .. " text, right", offsets, bar[1] .. "Right", 60), 26)
    end
    if cast then place(XY(body, "Cast bar", offsets, "cast"), 26) end
    if auras then
        place(XY(body, "Debuffs", offsets, "debuffs"), 26)
        if auras.buffs then place(XY(body, "Buffs", offsets, "buffs"), 26) end
    end
    if settings.druidMana ~= nil then place(XY(body, "Druid mana bar", offsets, "druid"), 26) end
    place(Help(body, "Right and up are +. The portrait and the bars move on their own (the frame covers both); "
        .. "the name moves with the bars, the badge and icons with the portrait. Each part is nudged from "
        .. "the place its \"Where\" gives it."), 44, 4)

    -- Text.
    place, body = Add("text", "Text", false)
    place(Stepper(body, "Name size", 6, 24, 1, settings, "nameSize"), 26)
    place(Stepper(body, "Bar text size", 6, 24, 1, settings, "textSize"), 26)
    for _, entry in ipairs({
        { "healthLeft", "Health, left" }, { "health", "Health, middle" }, { "healthRight", "Health, right" },
        { "powerLeft", "Power, left" }, { "power", "Power, middle" }, { "powerRight", "Power, right" },
    }) do
        place(TextBox(body, entry[2], settings.text, entry[1]), 28)
    end
    -- Your frame's druid mana bar.
    if settings.druidMana ~= nil then
        for _, entry in ipairs({ { "druidLeft", "Druid mana, left" }, { "druid", "Druid mana, middle" },
            { "druidRight", "Druid mana, right" } }) do
            place(TextBox(body, entry[2], settings.text, entry[1]), 28)
        end
    end
    place(Help(body, "Words: |cffffd100value|r, |cffffd100max|r, |cffffd100percent|r (|cffffd100percent.1|r for a "
        .. "decimal), |cffffd100name|r, |cffffd100level|r, |cffffd100class|r. On the power bar, value, max and percent are the "
        .. "power's; on the druid mana bar, your mana's. Leave empty to hide."), 40, 4)

    if cast then
        place, body = Add("cast", "Cast bar", false)
        place(Checkbox(body, "Show its casts", cast, "enabled"), 26)
        place(Dropdown(body, "Where", SIDES, cast, "side"), 30)
        place(Dropdown(body, "On that side", Options("near", "Next to the bars", "beyond", "Beyond the buffs and debuffs"),
            cast, "position"), 30)
        place(Checkbox(body, "The spell's icon at its start", cast, "icon"), 26)
        place(Checkbox(body, "The time left", cast, "showTime"), 26)
    end
    if auras then self:BuildAuraRows(Add, auras) end
    self:BuildExtras(Add, kind, settings)
    Relayout()
end

-- The frame's own buffs and debuffs: two rows on the target and focus, the party's debuff row.
function Config:BuildAuraRows(Add, auras)
    local party = auras.buffs == nil
    local place, body = Add("auras", party and "Debuffs by each frame" or "Buffs & debuffs", false)
    place(Checkbox(body, "Show them", auras, "enabled"), 26)
    if not party then
        place(Dropdown(body, "Nearer the bars", Options("debuffs", "Debuffs, then buffs", "buffs", "Buffs, then debuffs"),
            auras, "order"), 30)
        place(Stepper(body, "Gap between rows", 0, 20, 1, auras, "rowGap"), 26)
    end
    place(Checkbox(body, "Close up an empty row (what's beyond it moves in)", auras, "fold"), 26)
    place(Checkbox(body, "Rounded icons, like the action bar buttons", auras, "rounded"), 26)
    place(Stepper(body, "Space between icons", 0, 12, 1, auras, "spacing"), 26)
    place(Help(body, "With timers below the icons, they keep far enough apart for the longest (\"59m\")."), 20, 4)
    local rows = party and { { "debuffs", "Debuffs" } } or { { "debuffs", "Debuffs" }, { "buffs", "Buffs" } }
    for _, row in ipairs(rows) do
        local rowSettings = auras[row[1]]
        local x = 0
        if not party then
            place(Label(body, row[2], "GameFontNormalSmall"), 20, 4)
            place(Checkbox(body, "Show " .. row[2]:lower(), rowSettings, "enabled"), 26, 12)
            x = 12
        end
        place(Dropdown(body, "Where", party and PARTY_SIDES or SIDES, rowSettings, "side"), 30, x)
        if row[1] == "debuffs" then
            place(Dropdown(body, "Whose", AURA_MODES, rowSettings, "mode"), 30, x)
        end
        place(Checkbox(body, "Timers", rowSettings, "showTimer"), 26, x)
        place(Dropdown(body, "Timer", Options("icon", "On the icon", "below", "Below the icon"), rowSettings, "timerPos"), 30, x)
        place(Stepper(body, "Timer size (% of the icon)", 25, 70, 5, rowSettings, "timerScale", "%d%%"), 26, x)
        place(Stepper(body, "Most shown", 1, party and 12 or 40, 1, rowSettings, "max"), 26, x)
        place(Stepper(body, "Icons per row (0: one long row)", 0, 40, 1, rowSettings, "perRow"), 28, x)
    end
end

local REST_POS = Options("portrait", "Top of the portrait", "badge", "Beside the level badge", "none", "Hidden")

-- What only some frames have: your druid mana, glows and resting icon; the dragon; the party's.
function Config:BuildExtras(Add, kind, settings)
    if kind == "player" then
        local place, body = Add("druid", "Druid mana (in a form)", false)
        place(Checkbox(body, "Your mana by the bars while in a form", settings, "druidMana"), 26)
        place(Dropdown(body, "Where", SIDES, settings, "druidManaSide"), 30, 20)
        place(Stepper(body, "Mana bar height", 2, 20, 1, settings, "druidManaHeight"), 26, 20)
        place(Stepper(body, "Mana text size (0 = fit the bar)", 0, 20, 1, settings, "druidTextSize"), 26, 20)
        place(Help(body, "Its text and nudge are under Text and Fine nudges."), 18, 4)

        place, body = Add("extras", "Your frame", false)
        place(Checkbox(body, "Five-second rule: a strip on your mana bar until regen starts again", settings, "manaRule"), 26)
        place(Dropdown(body, "Resting \"zzz\"", REST_POS, settings, "restPos"), 30)
        place(Checkbox(body, "A soft glow while resting (gold) or fighting (red)", settings, "glow"), 26)
        place(Checkbox(body, "A soft glow, yellow to red, while you have aggro", settings, "threat"), 26)
        place(Checkbox(body, "Hit text over the portrait (damage and heals taken)", settings, "hitText"), 26)
    elseif kind == "target" or kind == "focus" then
        local place, body = Add("extras", "Extras", false)
        place(Checkbox(body, "Elite and rare dragon round the portrait", settings, "dragons"), 26)
        place(Checkbox(body, "Hit text over the portrait (damage and heals taken)", settings, "hitText"), 26)
    elseif kind == "party" then
        local place, body = Add("extras", "Party", false)
        place(Checkbox(body, "Hide in a raid (like Blizzard's)", settings, "hideInRaid"), 26)
        place(Checkbox(body, "A soft glow, yellow to red, while they have aggro", settings, "threat"), 26)
        place(Checkbox(body, "Show their pets (set up on the Party pets page)", ns.db.units.partypet, "enabled"), 26)
    else
        local place, body = Add("extras", "Extras", false)
        place(Checkbox(body, "Hit text over the portrait (damage and heals taken)", settings, "hitText"), 26)
    end
end

-- Each page scrolls; the tabs share the width out.
function Config:Build()
    local pages = { { "general", "General", function(page) self:BuildGeneral(page) end } }
    for _, entry in ipairs({ { "player", "Player" }, { "pet", "Pet" }, { "target", "Target" }, { "tot", "ToT" },
        { "focus", "Focus" }, { "party", "Party" }, { "partypet", "Party pets" } }) do
        local kind = entry[1]
        pages[#pages + 1] = { kind, entry[2], function(page) self:BuildUnit(page, kind) end }
    end
    self.frame = UI.Window("FrogFramesConfig", "FrogFrames", WIDTH, HEIGHT, pages, { fitTabs = true, scroll = true })
end

function Config:Toggle()
    if not ns.db then return end
    if not self.frame then
        self:Build()
        self.frame:Show()
        return
    end
    self.frame:SetShown(not self.frame:IsShown())
end

-- Its entry in the game's Options > AddOns list (FrogLib's Options.lua).
FrogLib.Options.Add("FrogFrames", ns, {
    open = function()
        if not (Config.frame and Config.frame:IsShown()) then Config:Toggle() end
    end,
    commands = {
        { "/ff", "open or close the settings (also /frogframes)" },
        { "/ff unlock", "unlock the frames to move them (/ff lock to lock them again)" },
    },
})
