local _, ns = ...
local Config = {}
ns.Config = Config

local W, H = 700, 640

-- Same control set as FrogTarget's settings window, each page in a scrolling frame and in
-- sections that open and close.

local function Label(parent, text, template)
    local fs = parent:CreateFontString(nil, "OVERLAY", template or "GameFontNormal")
    fs:SetText(text)
    return fs
end

local function Help(parent, text)
    local fs = Label(parent, text, "GameFontDisableSmall")
    fs:SetWidth(W - 90)
    fs:SetJustifyH("LEFT")
    return fs
end

local function Button(parent, text, w, h)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(w, h or 22)
    b:SetText(text)
    return b
end

local function Checkbox(parent, text, get, set)
    local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    cb:SetSize(24, 24)
    Label(cb, text, "GameFontHighlight"):SetPoint("LEFT", cb, "RIGHT", 4, 0)
    cb:SetChecked(get())
    cb:SetScript("OnShow", function(self) self:SetChecked(get()) end)
    cb:SetScript("OnClick", function(self)
        set(self:GetChecked() and true or false)
        ns.Refresh()
    end)
    return cb
end

local function Stepper(parent, text, min, max, step, get, set, fmt)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(380, 24)
    Label(f, text, "GameFontHighlight"):SetPoint("LEFT", 4, 0)
    local minus = Button(f, "-", 24)
    minus:SetPoint("LEFT", 250, 0)
    local val = Label(f, "", "GameFontHighlight")
    val:SetWidth(44)
    val:SetPoint("LEFT", minus, "RIGHT", 4, 0)
    local plus = Button(f, "+", 24)
    plus:SetPoint("LEFT", val, "RIGHT", 4, 0)
    local function refresh() val:SetText(fmt and string.format(fmt, get()) or get()) end
    local function change(d)
        if IsShiftKeyDown() then d = d * 10 end -- shift-click: ten steps at once
        local v = math.max(min, math.min(max, get() + d))
        set(math.floor(v / step + 0.5) * step)
        refresh()
        ns.Refresh()
    end
    minus:SetScript("OnClick", function() change(-step) end)
    plus:SetScript("OnClick", function() change(step) end)
    f:SetScript("OnShow", refresh)
    refresh()
    return f
end

local function Dropdown(parent, text, groups, get, set)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(500, 26)
    Label(f, text, "GameFontHighlight"):SetPoint("LEFT", 4, 0)
    local dd = CreateFrame("DropdownButton", nil, f, "WowStyle1DropdownTemplate")
    dd:SetWidth(230)
    dd:SetPoint("LEFT", 250, 0)
    dd:SetupMenu(function(_, root)
        local all, count = groups(), 0
        for _, group in ipairs(all) do count = count + #group.items end
        if count > 20 then root:SetScrollMode(20 * 20) end
        for _, group in ipairs(all) do
            if group.title then root:CreateTitle(group.title) end
            for _, item in ipairs(group.items) do
                root:CreateRadio(item.name, function() return get() == item.path end, function()
                    set(item.path)
                    ns.Refresh()
                end)
            end
        end
    end)
    return f
end

local function Options(...)
    local items = {}
    for i = 1, select("#", ...), 2 do
        local path, name = select(i, ...)
        items[#items + 1] = { path = path, name = name }
    end
    local groups = { { items = items } }
    return function() return groups end
end

local OUTLINES = Options("", "None", "OUTLINE", "Outline", "THICKOUTLINE", "Thick outline")
local LOOKS = Options("classic", "Classic (glossy, dark bevelled frames)", "modern", "Modern (flat, 1px edge)",
    "forever", "Forever (cooldown manager bars)")
local PORTRAITS = Options("2d", "Picture", "3d", "3D model (square, inside the ring)", "class", "Class icon (players)",
    "none", "None")
local HEALTH_COLORS = Options("class", "Class colour / reaction", "green", "Always green (Classic)")
local NAME_COLORS = Options("gold", "Gold, like the game's", "white", "White", "unit", "The health bar's colour")
local NAME_POS = Options("above", "Above the health bar", "inside", "On the health bar", "none", "Hidden")
local SIDES = Options("below", "Below the bars", "above", "Above the bars")
local PARTY_SIDES = Options("right", "Right of the frame", "left", "Left of the frame", "above", "Above the bars",
    "below", "Below the bars")
local AURA_MODES = Options("mine", "Only mine", "all", "Mine, then everyone else's")

local function ColorSwatch(parent, text, get, set)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(320, 24)
    Label(f, text, "GameFontHighlight"):SetPoint("LEFT", 4, 0)
    local sw = CreateFrame("Button", nil, f, "BackdropTemplate")
    sw:SetSize(40, 18)
    sw:SetPoint("LEFT", 250, 0)
    sw:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    sw:SetBackdropBorderColor(1, 1, 1, 0.6)
    local function refresh()
        local c = get()
        sw:SetBackdropColor(c.r, c.g, c.b, 1)
    end
    local function apply(r, g, b)
        set(r, g, b)
        refresh()
        ns.Refresh()
    end
    sw:SetScript("OnClick", function()
        local c = get()
        local r0, g0, b0 = c.r, c.g, c.b
        ColorPickerFrame:SetFrameStrata("FULLSCREEN_DIALOG")
        ColorPickerFrame:SetupColorPickerAndShow({
            r = r0, g = g0, b = b0,
            swatchFunc = function() apply(ColorPickerFrame:GetColorRGB()) end,
            cancelFunc = function() apply(r0, g0, b0) end,
        })
    end)
    refresh()
    return f
end

local function TextBox(parent, text, get, set)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(500, 26)
    Label(f, text, "GameFontHighlight"):SetPoint("LEFT", 4, 0)
    local eb = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
    eb:SetSize(220, 20)
    eb:SetPoint("LEFT", 256, 0)
    eb:SetAutoFocus(false)
    eb:SetText(get())
    eb:SetScript("OnShow", function(self) self:SetText(get()) end)
    eb:SetScript("OnTextChanged", function(self, userInput)
        if not userInput then return end
        set(self:GetText())
        ns.Refresh()
    end)
    eb:SetScript("OnEnterPressed", eb.ClearFocus)
    eb:SetScript("OnEscapePressed", eb.ClearFocus)
    return f
end

-- Lays controls out down a frame; the frame grows to fit them.
local function Placer(page)
    local y = 0
    return function(w, h, x)
        w:SetPoint("TOPLEFT", x or 0, -y)
        y = y + h
        page:SetHeight(y + 4)
    end
end

-- A small stepper for a pair on one row: a short label ("x", "y", "inset"), - value +.
local function Mini(parent, label, min, max, get, set)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(130, 24)
    local l = Label(f, label, "GameFontDisableSmall")
    l:SetPoint("LEFT", 0, 0)
    l:SetWidth(34)
    l:SetJustifyH("RIGHT")
    local minus = Button(f, "-", 20, 20)
    minus:SetPoint("LEFT", 38, 0)
    local val = Label(f, "", "GameFontHighlightSmall")
    val:SetWidth(36)
    val:SetPoint("LEFT", minus, "RIGHT", 2, 0)
    local plus = Button(f, "+", 20, 20)
    plus:SetPoint("LEFT", val, "RIGHT", 2, 0)
    local function refresh() val:SetText(get()) end
    local function change(d)
        if IsShiftKeyDown() then d = d * 10 end -- shift-click: ten steps at once
        set(math.max(min, math.min(max, get() + d)))
        refresh()
        ns.Refresh()
    end
    minus:SetScript("OnClick", function() change(-1) end)
    plus:SetScript("OnClick", function() change(1) end)
    f:SetScript("OnShow", refresh)
    refresh()
    return f
end

-- One row: a label and two small steppers side by side. a, b: { label, min, max, get, set }.
local function Pair(parent, text, a, b)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(500, 24)
    Label(f, text, "GameFontHighlight"):SetPoint("LEFT", 4, 0)
    Mini(f, a[1], a[2], a[3], a[4], a[5]):SetPoint("LEFT", 190, 0)
    if b then Mini(f, b[1], b[2], b[3], b[4], b[5]):SetPoint("LEFT", 330, 0) end
    return f
end

-- A key's x and y offsets on one row (right and up are +).
local function XY(parent, text, o, key, range)
    range = range or 40
    return Pair(parent, text,
        { "x", -range, range, function() return o[key .. "X"] end, function(v) o[key .. "X"] = v end },
        { "y", -range, range, function() return o[key .. "Y"] end, function(v) o[key .. "Y"] = v end })
end

-- A bar texture setting: "Use General's", "The look's own", then every bar texture FrogLib
-- knows (FrogUI's Frog bars when it's loaded), with a swatch showing the choice.
local function TextureChoice(parent, text, get, set, color, general)
    local swatch
    local function refresh()
        if swatch then
            ns.PaintBarTexture(swatch, get())
            swatch:SetVertexColor(color[1], color[2], color[3])
        end
    end
    local f = Dropdown(parent, text, function()
        local groups = ns.Media:List("statusbar")
        local first = { { name = "The look's own", path = "" } }
        if not general then table.insert(first, 1, { name = "Use General's", path = "general" }) end
        table.insert(groups, 1, { items = first })
        return groups
    end, get, function(v)
        set(v)
        refresh()
    end)
    swatch = f:CreateTexture(nil, "ARTWORK")
    swatch:SetSize(64, 12)
    swatch:SetPoint("LEFT", 490, 0)
    f:HookScript("OnShow", refresh)
    refresh()
    return f
end

------------------------------------------------------------------------------
-- Sections: a page of headers that open and close (click), each with its controls under it.
-- Which are open is kept per page in the saved settings (configOpen).
------------------------------------------------------------------------------

local PLUS, MINUS = "Interface\\Buttons\\UI-PlusButton-Up", "Interface\\Buttons\\UI-MinusButton-Up"

local function Sections(page, pageKey)
    local list = {}
    local saved = ns.db.configOpen
    saved[pageKey] = saved[pageKey] or {}
    local open = saved[pageKey]
    local function IsOpen(s)
        local v = open[s.key]
        if v == nil then return s.default end
        return v
    end
    local function Relayout()
        local y = 0
        for _, s in ipairs(list) do
            s.header:ClearAllPoints()
            s.header:SetPoint("TOPLEFT", 0, -y)
            y = y + 26
            local on = IsOpen(s)
            s.icon:SetTexture(on and MINUS or PLUS)
            s.body:SetShown(on)
            if on then
                s.body:ClearAllPoints()
                s.body:SetPoint("TOPLEFT", 0, -y)
                y = y + s.body:GetHeight() + 8
            end
        end
        page:SetHeight(y + 10)
    end
    -- Adds a section; returns its placer. defaultOpen: open until the user closes it.
    local function Add(key, title, defaultOpen)
        local s = { key = key, default = defaultOpen and true or false }
        local header = CreateFrame("Button", nil, page)
        header:SetSize(W - 70, 24)
        local bg = header:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(1, 1, 1, 0.06)
        local hl = header:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        hl:SetColorTexture(1, 0.82, 0, 0.08)
        s.icon = header:CreateTexture(nil, "ARTWORK")
        s.icon:SetSize(16, 16)
        s.icon:SetPoint("LEFT", 4, 0)
        Label(header, title):SetPoint("LEFT", s.icon, "RIGHT", 6, 0)
        header:SetScript("OnClick", function()
            open[s.key] = not IsOpen(s)
            Relayout()
        end)
        s.header = header
        s.body = CreateFrame("Frame", nil, page)
        s.body:SetSize(W - 70, 1)
        list[#list + 1] = s
        return Placer(s.body), s.body
    end
    return Add, Relayout
end

------------------------------------------------------------------------------
-- Pages
------------------------------------------------------------------------------

function Config:BuildGeneral(p)
    local db = ns.db
    local Add, Relayout = Sections(p, "general")
    local place, b = Add("frames", "Frames", true)
    place(Checkbox(b, "Unlock to move (drag the frames; samples show where there's no unit)",
        function() return not db.locked end, function(v) db.locked = not v end), 28)
    place(Help(b, "Drag the first party frame to move them all. Your pet, your target's target and the party's "
        .. "pets move with the frame they hang from; drag them to place them beside it. Release near the middle "
        .. "of the screen to centre a frame. /ff unlock and /ff lock work too."), 40, 4)

    place, b = Add("look", "Look", true)
    place(Dropdown(b, "Look", LOOKS, function() return db.look end, function(v) db.look = v end), 30)
    place(TextureChoice(b, "Bar texture (every frame)", function() return db.texture end,
        function(v) db.texture = v end, { 0.25, 0.8, 0.25 }, true), 30)
    place(Help(b, "Each frame can pick its own on its page (Look)."), 20, 4)
    place(Stepper(b, "Frame thickness (pixels per line)", 1, 3, 1, function() return db.frameThickness end,
        function(v) db.frameThickness = v end), 32)
    place(Dropdown(b, "Font", function() return ns.Media:List("font") end,
        function() return db.font end, function(v) db.font = v end), 30)
    place(Dropdown(b, "Font outline", OUTLINES, function() return db.outline end, function(v) db.outline = v end), 30)
    place(Dropdown(b, "Health bar colour", HEALTH_COLORS, function() return db.healthColor end,
        function(v) db.healthColor = v end), 30)
    place(Dropdown(b, "Name colour", NAME_COLORS, function() return db.nameColor end,
        function(v) db.nameColor = v end), 30)
    place(Checkbox(b, "Colour the level by difficulty, with a skull for bosses",
        function() return db.levelColor end, function(v) db.levelColor = v end), 28)
    place(Stepper(b, "Out of range opacity", 0.1, 1, 0.05, function() return db.rangeAlpha end,
        function(v) db.rangeAlpha = v end, "%.2f"), 28)

    place, b = Add("icons", "Icons", false)
    for _, def in ipairs({
        { "raid", "Raid target marks" },
        { "leader", "Group leader / assistant" },
        { "status", "Resting and in combat (your frame)" },
        { "pvp", "PvP flag (players)" },
    }) do
        local key = def[1]
        place(Checkbox(b, def[2], function() return db.icons[key] end, function(v) db.icons[key] = v end), 26)
    end
    place(Stepper(b, "Icon size", 8, 40, 1, function() return db.icons.size end, function(v) db.icons.size = v end), 28)

    local c = db.combo
    place, b = Add("combo", "Combo points (rogues, druids in cat form)", false)
    place(Checkbox(b, "Show combo points", function() return c.enabled end, function(v) c.enabled = v end), 26)
    place(Dropdown(b, "On", Options("target", "The target frame", "player", "Your frame"),
        function() return c.on end, function(v) c.on = v end), 30)
    place(Dropdown(b, "Where", SIDES, function() return c.side end, function(v) c.side = v end), 30)
    place(Stepper(b, "Height", 2, 20, 1, function() return c.height end, function(v) c.height = v end), 26)
    place(Stepper(b, "Gap between them (pixels)", 0, 20, 1, function() return c.spacing end,
        function(v) c.spacing = v end), 26)
    place(Pair(b, "Offset",
        { "x", -40, 40, function() return c.x end, function(v) c.x = v end },
        { "y", -40, 40, function() return c.y end, function(v) c.y = v end }), 26)
    place(ColorSwatch(b, "Colour", function() return c.color end,
        function(r, g, bl) c.color = { r = r, g = g, b = bl } end), 26)
    place(ColorSwatch(b, "Colour when full", function() return c.maxColor end,
        function(r, g, bl) c.maxColor = { r = r, g = g, b = bl } end), 26)
    Relayout()
end

local PARENTS = { pet = "From your frame", tot = "From the target frame", partypet = "From the party member" }

-- Every kind of frame's page, in sections: Frame, Size, Look, Position & offsets, Text, then its
-- cast bar, buffs & debuffs and extras where it has them.
function Config:BuildUnit(p, kind)
    local cfg = ns.db.units[kind]
    local o = cfg.offsets
    local c, a = cfg.cast, cfg.auras
    local Add, Relayout = Sections(p, kind)

    -- Frame: on or off, where, what it shows.
    local place, b = Add("frame", "Frame", true)
    place(Checkbox(b, "Show this frame (hides Blizzard's while it's on)",
        function() return cfg.enabled end, function(v) cfg.enabled = v end), 28)
    local reset = Button(b, "Reset position", 130)
    reset:SetScript("OnClick", function()
        local d = ns.defaults.units[kind]
        if d.point then cfg.point = ns.CopyOf(d.point) end
        if d.attach then cfg.attach = ns.CopyOf(d.attach) end
        ns.Refresh()
    end)
    place(reset, 30, 6)
    place(Dropdown(b, "Portrait", PORTRAITS, function() return cfg.portrait end, function(v) cfg.portrait = v end), 30)
    place(Dropdown(b, "Name", NAME_POS, function() return cfg.namePos end, function(v) cfg.namePos = v end), 30)
    place(Checkbox(b, "Long names run on over the portrait (name above the bars)",
        function() return cfg.nameFull end, function(v) cfg.nameFull = v end), 28)
    place(Checkbox(b, "Show the level (in a badge on the portrait)", function() return cfg.showLevel end,
        function(v) cfg.showLevel = v end), 26)
    place(Checkbox(b, "Fade while out of range", function() return cfg.fadeRange end,
        function(v) cfg.fadeRange = v end), 26)
    local fade = cfg.fade
    place(Checkbox(b, "Fade when idle: out of combat, health full, power at rest",
        function() return fade.enabled end, function(v) fade.enabled = v end), 26)
    place(Checkbox(b, "... and only with nothing targeted", function() return fade.noTarget end,
        function(v) fade.noTarget = v end), 26, 20)
    place(Stepper(b, "Faded opacity", 0, 1, 0.05, function() return fade.alpha end,
        function(v) fade.alpha = v end, "%.2f"), 28, 20)

    -- Size.
    place, b = Add("size", "Size", true)
    place(Stepper(b, "Scale", 0.5, 2, 0.05, function() return cfg.scale end, function(v) cfg.scale = v end, "%.2f"), 26)
    place(Stepper(b, "Bar width", 30, 400, 2, function() return cfg.width end, function(v) cfg.width = v end), 26)
    place(Stepper(b, "Health bar height", 4, 60, 1, function() return cfg.healthHeight end,
        function(v) cfg.healthHeight = v end), 26)
    place(Stepper(b, "Power bar height (0: none)", 0, 40, 1, function() return cfg.powerHeight end,
        function(v) cfg.powerHeight = v end), 26)
    place(Stepper(b, "Portrait size (across the ring)", 16, 140, 1, function() return cfg.portraitSize end,
        function(v) cfg.portraitSize = v end), 26)
    if c then
        place(Stepper(b, "Cast bar width (0: the bars')", 0, 400, 2, function() return c.width end,
            function(v) c.width = v end), 26)
        place(Stepper(b, "Cast bar height", 4, 40, 1, function() return c.height end,
            function(v) c.height = v end), 26)
    end
    if a then
        place(Stepper(b, "Debuff icon size", 10, 48, 1, function() return a.debuffs.size end,
            function(v) a.debuffs.size = v end), 26)
        if a.buffs then
            place(Stepper(b, "Buff icon size", 10, 48, 1, function() return a.buffs.size end,
                function(v) a.buffs.size = v end), 26)
        end
    end
    place(Help(b, "Shift-click + or - for ten steps at once."), 18, 4)

    -- Look: the bars' textures.
    place, b = Add("look", "Look", false)
    place(TextureChoice(b, "Health bar texture", function() return cfg.healthTexture end,
        function(v) cfg.healthTexture = v end, { 0.25, 0.8, 0.25 }), 30)
    place(TextureChoice(b, "Power bar texture", function() return cfg.powerTexture end,
        function(v) cfg.powerTexture = v end, { 0.2, 0.35, 1 }), 30)

    -- Position & offsets: one row each, x and y (right and up are +).
    place, b = Add("offsets", "Position & offsets", false)
    if cfg.attach then
        local at = cfg.attach
        place(Pair(b, PARENTS[kind],
            { "x", -300, 300, function() return at[3] end, function(v) at[3] = v end },
            { "y", -300, 300, function() return at[4] end, function(v) at[4] = v end }), 26)
    end
    if cfg.spacing then
        place(Pair(b, "Gap between frames", { "y", 0, 80, function() return cfg.spacing end,
            function(v) cfg.spacing = v end }), 26)
    end
    place(XY(b, "Portrait", o, "portrait"), 26)
    place(XY(b, "Bars", o, "bars"), 26)
    place(XY(b, "Name", o, "name"), 26)
    place(XY(b, "Level badge", o, "level"), 26)
    if cfg.restPos then place(XY(b, "Resting zzz", o, "rest"), 26) end
    for _, bar in ipairs({ { "health", "Health" }, { "power", "Power" } }) do
        place(XY(b, bar[2] .. " text, left", o, bar[1] .. "Left", 60), 26)
        place(XY(b, bar[2] .. " text, middle", o, bar[1], 60), 26)
        place(XY(b, bar[2] .. " text, right", o, bar[1] .. "Right", 60), 26)
    end
    if c then place(XY(b, "Cast bar", o, "cast"), 26) end
    if a then
        place(XY(b, "Debuffs", o, "debuffs"), 26)
        if a.buffs then place(XY(b, "Buffs", o, "buffs"), 26) end
    end
    if cfg.druidMana ~= nil then place(XY(b, "Druid mana bar", o, "druid"), 26) end
    place(Help(b, "Right and up are +. The portrait and the bars move on their own (the frame covers both); "
        .. "the name moves with the bars, the badge and icons with the portrait. Each part is nudged from "
        .. "the place its \"Where\" gives it."), 44, 4)

    -- Text.
    place, b = Add("text", "Text", false)
    place(Stepper(b, "Name size", 6, 24, 1, function() return cfg.nameSize end, function(v) cfg.nameSize = v end), 26)
    place(Stepper(b, "Bar text size", 6, 24, 1, function() return cfg.textSize end, function(v) cfg.textSize = v end), 26)
    for _, def in ipairs({
        { "healthLeft", "Health, left" }, { "health", "Health, middle" }, { "healthRight", "Health, right" },
        { "powerLeft", "Power, left" }, { "power", "Power, middle" }, { "powerRight", "Power, right" },
    }) do
        local key = def[1]
        place(TextBox(b, def[2], function() return cfg.text[key] end, function(v) cfg.text[key] = v end), 28)
    end
    place(Help(b, "Words: |cffffd100value|r, |cffffd100max|r, |cffffd100percent|r (|cffffd100percent.1|r for a "
        .. "decimal), |cffffd100name|r, |cffffd100level|r, |cffffd100class|r. On the power bar, value, max and percent are the "
        .. "power's. Leave empty to hide."), 40, 4)

    if c then
        place, b = Add("cast", "Cast bar", false)
        place(Checkbox(b, "Show its casts", function() return c.enabled end, function(v) c.enabled = v end), 26)
        place(Dropdown(b, "Where", SIDES, function() return c.side end, function(v) c.side = v end), 30)
        place(Dropdown(b, "On that side", Options("near", "Next to the bars", "beyond", "Beyond the buffs and debuffs"),
            function() return c.position end, function(v) c.position = v end), 30)
        place(Checkbox(b, "The spell's icon at its start", function() return c.icon end,
            function(v) c.icon = v end), 26)
        place(Checkbox(b, "The time left", function() return c.showTime end, function(v) c.showTime = v end), 26)
    end
    if a then self:BuildAuraRows(Add, a) end
    self:BuildExtras(Add, kind, cfg)
    Relayout()
end

-- The frame's own buffs and debuffs: two rows on the target and focus, the party's debuff row.
function Config:BuildAuraRows(Add, a)
    local party = a.buffs == nil
    local place, b = Add("auras", party and "Debuffs by each frame" or "Buffs & debuffs", false)
    place(Checkbox(b, "Show them", function() return a.enabled end, function(v) a.enabled = v end), 26)
    if not party then
        place(Dropdown(b, "Nearer the bars", Options("debuffs", "Debuffs, then buffs", "buffs", "Buffs, then debuffs"),
            function() return a.order end, function(v) a.order = v end), 30)
        place(Stepper(b, "Gap between rows", 0, 20, 1, function() return a.rowGap end,
            function(v) a.rowGap = v end), 26)
    end
    place(Checkbox(b, "Close up an empty row (what's beyond it moves in)",
        function() return a.fold end, function(v) a.fold = v end), 26)
    place(Checkbox(b, "Rounded icons, like the action bar buttons",
        function() return a.rounded end, function(v) a.rounded = v end), 26)
    place(Stepper(b, "Space between icons", 0, 12, 1, function() return a.spacing end,
        function(v) a.spacing = v end), 26)
    place(Help(b, "With timers below the icons, they keep far enough apart for the longest (\"59m\")."), 20, 4)
    local rows = party and { { "debuffs", "Debuffs" } } or { { "debuffs", "Debuffs" }, { "buffs", "Buffs" } }
    for _, row in ipairs(rows) do
        local r = a[row[1]]
        local x = 0
        if not party then
            place(Label(b, row[2], "GameFontNormalSmall"), 20, 4)
            place(Checkbox(b, "Show " .. row[2]:lower(), function() return r.enabled end,
                function(v) r.enabled = v end), 26, 12)
            x = 12
        end
        place(Dropdown(b, "Where", party and PARTY_SIDES or SIDES, function() return r.side end,
            function(v) r.side = v end), 30, x)
        if row[1] == "debuffs" then
            place(Dropdown(b, "Whose", AURA_MODES, function() return r.mode or "all" end,
                function(v) r.mode = v end), 30, x)
        end
        place(Checkbox(b, "Timers", function() return r.showTimer end,
            function(v) r.showTimer = v end), 26, x)
        place(Dropdown(b, "Timer", Options("icon", "On the icon", "below", "Below the icon"),
            function() return r.timerPos end, function(v) r.timerPos = v end), 30, x)
        place(Stepper(b, "Timer size (% of the icon)", 25, 70, 5, function() return r.timerScale end,
            function(v) r.timerScale = v end, "%d%%"), 26, x)
        place(Stepper(b, "Most shown", 1, party and 12 or 40, 1, function() return r.max end,
            function(v) r.max = v end), 26, x)
        place(Stepper(b, "Icons per row (0: one long row)", 0, 40, 1, function() return r.perRow end,
            function(v) r.perRow = v end), 28, x)
    end
end

local REST_POS = Options("portrait", "Top of the portrait", "badge", "Beside the level badge", "none", "Hidden")

-- What only some frames have: your druid mana, glows and resting icon; the dragon; the party's.
function Config:BuildExtras(Add, kind, cfg)
    if kind == "player" then
        local place, b = Add("extras", "Your frame", false)
        place(Dropdown(b, "Resting \"zzz\"", REST_POS, function() return cfg.restPos end,
            function(v) cfg.restPos = v end), 30)
        place(Checkbox(b, "Druids: your mana by the bars while in a form",
            function() return cfg.druidMana end, function(v) cfg.druidMana = v end), 26)
        place(Dropdown(b, "Where", SIDES, function() return cfg.druidManaSide end,
            function(v) cfg.druidManaSide = v end), 30, 20)
        place(Stepper(b, "Mana bar height", 2, 20, 1, function() return cfg.druidManaHeight end,
            function(v) cfg.druidManaHeight = v end), 26, 20)
        place(Checkbox(b, "A soft glow while resting (gold) or fighting (red)",
            function() return cfg.glow end, function(v) cfg.glow = v end), 26)
        place(Checkbox(b, "A soft glow, yellow to red, while you have aggro",
            function() return cfg.threat end, function(v) cfg.threat = v end), 26)
        place(Checkbox(b, "Hit text over the portrait (damage and heals taken)",
            function() return cfg.hitText end, function(v) cfg.hitText = v end), 26)
    elseif kind == "target" or kind == "focus" then
        local place, b = Add("extras", "Extras", false)
        place(Checkbox(b, "Elite and rare dragon round the portrait",
            function() return cfg.dragons end, function(v) cfg.dragons = v end), 26)
        place(Checkbox(b, "Hit text over the portrait (damage and heals taken)",
            function() return cfg.hitText end, function(v) cfg.hitText = v end), 26)
    elseif kind == "party" then
        local place, b = Add("extras", "Party", false)
        place(Checkbox(b, "Hide in a raid (like Blizzard's)", function() return cfg.hideInRaid end,
            function(v) cfg.hideInRaid = v end), 26)
        place(Checkbox(b, "A soft glow, yellow to red, while they have aggro", function() return cfg.threat end,
            function(v) cfg.threat = v end), 26)
        local pets = ns.db.units.partypet
        place(Checkbox(b, "Show their pets (set up on the Party pets page)", function() return pets.enabled end,
            function(v) pets.enabled = v end), 26)
    else
        local place, b = Add("extras", "Extras", false)
        place(Checkbox(b, "Hit text over the portrait (damage and heals taken)",
            function() return cfg.hitText end, function(v) cfg.hitText = v end), 26)
    end
end

-- A page in a scroll frame; returns the scrolling content to build on.
local function Page(f)
    local sf = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
    sf:SetPoint("TOPLEFT", 16, -64)
    sf:SetPoint("BOTTOMRIGHT", -34, 12)
    local child = CreateFrame("Frame", nil, sf)
    child:SetSize(W - 60, 10)
    sf:SetScrollChild(child)
    return sf, child
end

local TABS = {
    { "general", "General" }, { "player", "Player" }, { "pet", "Pet" }, { "target", "Target" },
    { "tot", "ToT" }, { "focus", "Focus" }, { "party", "Party" }, { "partypet", "Party pets" },
}

function Config:Build()
    local f = CreateFrame("Frame", "FrogFramesConfig", UIParent, "BasicFrameTemplateWithInset")
    f:SetSize(W, H)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    Label(f, "FrogFrames"):SetPoint("TOP", 0, -5)
    tinsert(UISpecialFrames, "FrogFramesConfig")
    self.frame = f

    local frames, pages, tabs = {}, {}, {}
    local function select(key)
        for k, sf in pairs(frames) do sf:SetShown(k == key) end
        for k, tab in pairs(tabs) do
            if k == key then tab:LockHighlight() else tab:UnlockHighlight() end
        end
    end
    local tabW = math.floor((W - 28) / #TABS)
    for i, def in ipairs(TABS) do
        local key = def[1]
        local tab = Button(f, def[2], tabW - 2)
        tab:SetPoint("TOPLEFT", 14 + (i - 1) * tabW, -30)
        tab:SetScript("OnClick", function() select(key) end)
        local fs = tab:GetFontString()
        if fs then fs:SetWordWrap(false) end
        tabs[key] = tab
        frames[key], pages[key] = Page(f)
    end
    self:BuildGeneral(pages.general)
    for _, kind in ipairs({ "player", "pet", "target", "tot", "focus", "party", "partypet" }) do
        self:BuildUnit(pages[kind], kind)
    end
    select("general")
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
