local _, ns = ...

-- The bars and the frame round each one (ns.CreateBar: the fill and its track; ns.CreateBox: the
-- frame), in four looks: "classic" (a glossy fill in a dark bevelled frame with rounded corners),
-- "modern" (a plain fill, a 1px black edge), "forever" (the cooldown manager's fill in FrogLib's
-- Forever frame) and "stone" (in Classic's carved action bar stone). Art: make_frogframes_art.py.

local WHITE = "Interface\\Buttons\\WHITE8X8"
local SPARK = "Interface\\CastingBar\\UI-CastingBar-Spark"
local MEDIA = "Interface\\AddOns\\FrogFrames\\Media\\"
local SMOOTH = Enum.StatusBarInterpolation and Enum.StatusBarInterpolation.ExponentialEaseOut
local IMMEDIATE = Enum.StatusBarInterpolation and Enum.StatusBarInterpolation.Immediate
local Borders = FrogLib.Borders
local issecret = FrogLib.issecret

-- The classic frame's art (Bezel.tga: a black outline, two dark grey lines lit along the top and a
-- black inner line curving in over the bar's corners), nine-sliced `slice` texels in, its lines
-- `width` texels deep, all outside the bar. Bars too thin for the big one's corners get the small one.
local BEZEL = { file = MEDIA .. "Bezel.tga", size = 32, slice = 8, width = 4 }
local BEZEL_SMALL = { file = MEDIA .. "BezelSmall.tga", size = 16, slice = 6, width = 4 }
-- The glow: 32x32 texels, sliced 15 in, reaching 8 texels out from the frame's outline.
local GLOW = { file = MEDIA .. "Glow.tga", size = 32, slice = 15, out = 8 }
local KEYS = { "tl", "t", "tr", "l", "r", "bl", "b", "br" }

local LOOKS = {
    classic = { texture = MEDIA .. "Gloss.tga", border = "bezel", track = { 0.06, 0.06, 0.06, 0.9 } },
    -- A plain fill (FrogUI's Matte, or flat colour without FrogUI) and a 1px black edge.
    modern = { texture = "Interface\\AddOns\\FrogUI\\Media\\Bars\\Matte.tga", fallback = WHITE, border = "edge",
        track = { 0, 0, 0, 0.6 } },
    forever = { atlas = "UI-HUD-CoolDownManager-Bar", texture = "Interface\\TargetingFrame\\UI-StatusBar",
        border = "forever", track = { 0, 0, 0, 0.6 } },
    stone = { texture = "Interface\\TargetingFrame\\UI-StatusBar", border = "carved", track = { 0.05, 0.05, 0.05, 0.9 } },
}

function ns.Look()
    return LOOKS[ns.db and ns.db.look] or LOOKS.classic
end

-- Atlases don't come or go in a session: each is asked about once.
local atlases = {}
local function HasAtlas(name)
    local known = atlases[name]
    if known == nil then
        known = C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(name) ~= nil or false
        atlases[name] = known
    end
    return known
end

-- Sizes in interface units, put on whole screen pixels so edges stay crisp at any scale.
function ns.Snap(value, pixel)
    return math.max(1, math.floor(value / pixel + 0.5)) * pixel
end

-- Screen pixels per texel of the classic and forever frames (frameThickness, 1 to 3).
local function Thick()
    return (ns.db and ns.db.frameThickness) or 1
end

-- How far a bar's frame reaches outside it, in `frame`'s units: the classic and carved frames 4
-- texels, the Forever frame 2, the modern edge 1 pixel.
function ns.BorderReach(frame)
    local border, pixel = ns.Look().border, FrogLib.Pixel(frame)
    if border == "bezel" or border == "carved" then return BEZEL.width * Thick() * pixel end
    if border == "forever" then return 2 * Thick() * pixel end
    return pixel
end

-- From one bar's fill to the next one's (the health and power bars), in `frame`'s units: their
-- frames touch, the classic and carved ones sharing all four of their lines (the lower one on top).
function ns.BarGap(frame)
    local border, pixel = ns.Look().border, FrogLib.Pixel(frame)
    if border == "bezel" or border == "carved" then return BEZEL.width * Thick() * pixel end
    if border == "forever" then return 4 * Thick() * pixel + pixel end
    return 3 * pixel
end

------------------------------------------------------------------------------
-- Bars
------------------------------------------------------------------------------

local Bar = {}
Bar.__index = Bar

function ns.CreateBar(parent)
    local bar = CreateFrame("StatusBar", nil, parent)
    bar:SetStatusBarTexture(WHITE)
    bar:SetMinMaxValues(0, 1)
    bar:SetValue(0)
    local fill = setmetatable({ bar = bar }, Bar)
    fill.track = bar:CreateTexture(nil, "BACKGROUND")
    fill.track:SetAllPoints()
    return fill
end

-- A bar texture setting, made concrete: "general" (or nil) is the General page's choice, ""
-- the look's own. Returns a file, or nil and an atlas. Whether FrogUI is loaded is asked once (only
-- ever after log-in, when every addon is).
local frogUI
function ns.BarTexture(path)
    if path == nil or path == "general" then path = ns.db.texture end
    local look = ns.Look()
    if path and path ~= "" then return path end
    if look.atlas and HasAtlas(look.atlas) then return nil, look.atlas end
    if look.fallback then
        if frogUI == nil then frogUI = FrogLib.Loaded("FrogUI") and true or false end
        if not frogUI then return look.fallback end
    end
    return look.texture
end

-- Shows a bar texture setting on a plain texture (the settings' preview swatches).
function ns.PaintBarTexture(texture, path)
    local file, atlas = ns.BarTexture(path)
    if atlas then texture:SetAtlas(atlas) else texture:SetTexture(file) end
end

-- The fill: the frame's chosen texture (path: a bar texture setting, see ns.BarTexture), or the
-- look's own (an atlas where the client has it); the track (the empty part) in the look's dark.
-- Whatever the fill, the classic frame's inner line covers its corners, so it stays rounded.
function Bar:ApplyTexture(path)
    local look = ns.Look()
    local file, atlas = ns.BarTexture(path)
    if atlas then
        self.bar:SetStatusBarTexture(WHITE)
        self.bar:GetStatusBarTexture():SetAtlas(atlas)
    else
        self.bar:SetStatusBarTexture(file)
    end
    local track = look.track
    if look.border == "bezel" then
        -- The gloss, darkened: the empty part keeps the bar's shape.
        self.track:SetTexture(look.texture)
        self.track:SetVertexColor(track[1], track[2], track[3], track[4])
    else
        self.track:SetColorTexture(track[1], track[2], track[3], track[4])
    end
    local spark = self.spark
    if spark then
        spark:ClearAllPoints()
        spark:SetPoint("CENTER", self.bar:GetStatusBarTexture(), "RIGHT", 0, 0)
        local height = self.bar:GetHeight() or 10
        spark:SetSize(math.max(8, height * 1.6), height * 2.4)
    end
    if self.color then self.bar:SetStatusBarColor(self.color[1], self.color[2], self.color[3]) end
end

function Bar:SetColor(r, g, b)
    local color = self.color
    if not color then
        self.color = { r, g, b }
    elseif color[1] == r and color[2] == g and color[3] == b then
        return
    else
        color[1], color[2], color[3] = r, g, b
    end
    self.bar:SetStatusBarColor(r, g, b)
end

-- Values may be secret; StatusBar setters accept them directly. The maximum only when it changes (a
-- secret one every time, and the next plain one after it).
function Bar:SetValues(value, max, instant)
    if issecret(max) then
        self.max = nil
        self.bar:SetMinMaxValues(0, max)
    elseif max ~= self.max then
        self.max = max
        self.bar:SetMinMaxValues(0, max)
    end
    self.bar:SetValue(value, instant and IMMEDIATE or SMOOTH)
end

-- The spark at the fill's end (only the cast bar has one): made the first time it's wanted, placed by
-- ApplyTexture.
function Bar:SetSpark(on)
    if on and not self.spark then
        self.spark = self.bar:CreateTexture(nil, "OVERLAY", nil, 7)
        self.spark:SetTexture(SPARK)
        self.spark:SetBlendMode("ADD")
    end
    if self.spark then self.spark:SetShown(on) end
end

------------------------------------------------------------------------------
-- Boxes: the look's frame round one bar
------------------------------------------------------------------------------

local Box = {}
Box.__index = Box

-- region: the bar to go round. The frame sits on a frame above it, so it's drawn over the fill. Each
-- look's pieces are made the first time that look is put on (Apply): only one look ever shows.
function ns.CreateBox(region)
    local box = setmetatable({ region = region }, Box)
    box.overlay = CreateFrame("Frame", nil, region)
    box.overlay:SetAllPoints()
    box.overlay:SetFrameLevel(region:GetFrameLevel() + 5)
    return box
end

-- The classic frame at a whole number of screen pixels per texel (like FrogLib's Forever frame),
-- the big art when the bar is tall enough for its corners, the small one otherwise.
function Box:PlaceBezel()
    local region = self.overlay
    local unit = Thick() * FrogLib.Pixel(region)
    local height = region:GetHeight() or 0
    local art = height >= 2 * (BEZEL.slice - BEZEL.width) * unit + unit and BEZEL or BEZEL_SMALL
    if self.art ~= art then
        self.art = art
        for _, texture in pairs(self.bezel) do texture:SetTexture(art.file, nil, nil, "NEAREST") end
    end
    Borders.NineSlice(self.bezel, region, art, art.width, unit)
end

-- Put on again only when something it depends on has changed (the look, the thickness, the pixel size, and for
-- the classic frame which art fits): a layout asks every box each time.
function Box:Apply()
    local border = ns.Look().border
    local overlay = self.overlay
    local unit = Thick() * FrogLib.Pixel(overlay)
    local art = ""
    if border == "bezel" then
        art = (overlay:GetHeight() or 0) >= 2 * (BEZEL.slice - BEZEL.width) * unit + unit and "big" or "small"
    end
    if self.appliedBorder == border and self.appliedUnit == unit and self.appliedArt == art then return end
    self.appliedBorder, self.appliedUnit, self.appliedArt = border, unit, art
    if border == "bezel" and not self.bezel then
        self.bezel = {}
        for _, key in ipairs(KEYS) do
            local texture = overlay:CreateTexture(nil, "OVERLAY", nil, 4)
            FrogLib.NoSnap(texture)
            self.bezel[key] = texture
        end
    end
    if border == "forever" and not self.forever then self.forever = Borders.Forever(overlay, "OVERLAY", 5) end
    if border == "carved" and not self.carved then self.carved = Borders.Carved(overlay, "OVERLAY", 5) end
    if border == "edge" and not self.edges then self.edges = Borders.Edges(overlay, overlay, "OVERLAY", 6) end
    if self.bezel then
        for _, texture in pairs(self.bezel) do texture:SetShown(border == "bezel") end
    end
    if border == "bezel" then self:PlaceBezel() end
    if self.forever then self.forever:SetShown(border == "forever") end
    if border == "forever" then self.forever:Place(Thick()) end
    if self.carved then self.carved:SetShown(border == "carved") end
    if border == "carved" then self.carved:Place(Thick()) end
    if self.edges then self.edges:SetShown(border == "edge") end
    if border == "edge" then self.edges:Place(1, 0, { r = 0, g = 0, b = 0 }) end
end

function Box:SetShown(on)
    self.overlay:SetShown(on)
end

------------------------------------------------------------------------------
-- Glows: a soft light round a frame (resting, fighting, aggro), tinted
------------------------------------------------------------------------------

local Glow = {}
Glow.__index = Glow

-- On `parent`, a frame below the bars, so only the light outside them shows.
function ns.CreateGlow(parent)
    local glow = setmetatable({ parts = {} }, Glow)
    for _, key in ipairs(KEYS) do
        local texture = parent:CreateTexture(nil, "BACKGROUND", nil, -7)
        texture:SetTexture(GLOW.file)
        texture:SetBlendMode("ADD")
        texture:Hide()
        glow.parts[key] = texture
    end
    return glow
end

-- Round `region`, from `reach` units outside it (where the frame round it ends).
function Glow:Place(region, reach)
    local pixel = FrogLib.Pixel(region)
    Borders.NineSlice(self.parts, region, GLOW, GLOW.out + reach / pixel, pixel)
end

-- Both only touch the eight textures when something changed (they're asked on every update).
function Glow:SetColor(r, g, b, a)
    a = a or 1
    if self.r == r and self.g == g and self.b == b and self.a == a then return end
    self.r, self.g, self.b, self.a = r, g, b, a
    for _, texture in pairs(self.parts) do texture:SetVertexColor(r, g, b, a) end
end

function Glow:SetShown(on)
    on = on and true or false
    if self.shown == on then return end
    self.shown = on
    for _, texture in pairs(self.parts) do texture:SetShown(on) end
end
