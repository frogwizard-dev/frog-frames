local _, ns = ...

-- The bars and the frame round each one, in three looks (ns.db.look):
--   "classic": a glossy fill (Media\Gloss.tga) in a dark bevelled frame with well rounded corners
--              (Media\Bezel.tga: a black outline, two dark grey lines lit along the top and a
--              black inner line, which curves in over the bar's corners to round the fill too);
--   "modern":  a plain fill with nothing round it but a 1px black edge;
--   "forever": the cooldown manager's bar fill, in our Forever-style frame (FrogLib's).
-- A bar (ns.CreateBar) is the fill and its track; a box (ns.CreateBox) is the frame round one.
-- The art is made by _tools\make_frogframes_art.py.

local WHITE = "Interface\\Buttons\\WHITE8X8"
local SPARK = "Interface\\CastingBar\\UI-CastingBar-Spark"
local MEDIA = "Interface\\AddOns\\FrogFrames\\Media\\"
local SMOOTH = Enum.StatusBarInterpolation and Enum.StatusBarInterpolation.ExponentialEaseOut
local IMMEDIATE = Enum.StatusBarInterpolation and Enum.StatusBarInterpolation.Immediate
local Borders = FrogLib.Borders

-- The classic frame's art, nine-sliced `slice` texels in from each edge, its lines `width` texels
-- deep, all outside the bar (so `slice - width` of each corner reaches in over the bar's corners).
-- Bars too thin for the big one's corners get the small one.
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
}

function ns.Look()
    return LOOKS[ns.db and ns.db.look] or LOOKS.classic
end

local function HasAtlas(name)
    return name and C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(name) ~= nil
end

-- Sizes in interface units, put on whole screen pixels so edges stay crisp at any scale.
function ns.Snap(v, px)
    return math.max(1, math.floor(v / px + 0.5)) * px
end

-- Screen pixels per texel of the classic and forever frames (frameThickness, 1 to 3).
local function Thick()
    return (ns.db and ns.db.frameThickness) or 1
end

-- How far a bar's frame reaches outside it, in `frame`'s units: the classic frame 4 texels, the
-- Forever frame 2, the modern edge 1 pixel.
function ns.BorderReach(frame)
    local border, px = ns.Look().border, FrogLib.Pixel(frame)
    if border == "bezel" then return BEZEL.width * Thick() * px end
    if border == "forever" then return 2 * Thick() * px end
    return px
end

-- From one bar's fill to the next one's (the health and power bars), in `frame`'s units: their
-- frames touch, the classic ones sharing all four of their lines (the lower one drawn on top).
function ns.BarGap(frame)
    local border, px = ns.Look().border, FrogLib.Pixel(frame)
    if border == "bezel" then return BEZEL.width * Thick() * px end
    if border == "forever" then return 4 * Thick() * px + px end
    return 3 * px
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
    local b = setmetatable({ bar = bar }, Bar)
    b.track = bar:CreateTexture(nil, "BACKGROUND")
    b.track:SetAllPoints()
    b.spark = bar:CreateTexture(nil, "OVERLAY", nil, 7)
    b.spark:SetTexture(SPARK)
    b.spark:SetBlendMode("ADD")
    b.spark:Hide()
    return b
end

-- A bar texture setting, made concrete: "general" (or nil) is the General page's choice, ""
-- the look's own. Returns a file, or nil and an atlas.
function ns.BarTexture(path)
    if path == nil or path == "general" then path = ns.db.texture end
    local look = ns.Look()
    if path and path ~= "" then return path end
    if look.atlas and HasAtlas(look.atlas) then return nil, look.atlas end
    if look.fallback and not FrogLib.Loaded("FrogUI") then return look.fallback end
    return look.texture
end

-- Shows a bar texture setting on a plain texture (the settings' preview swatches).
function ns.PaintBarTexture(tex, path)
    local file, atlas = ns.BarTexture(path)
    if atlas then tex:SetAtlas(atlas) else tex:SetTexture(file) end
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
    local t = look.track
    if look.border == "bezel" then
        -- The gloss, darkened: the empty part keeps the bar's shape.
        self.track:SetTexture(look.texture)
        self.track:SetVertexColor(t[1], t[2], t[3], t[4])
    else
        self.track:SetColorTexture(t[1], t[2], t[3], t[4])
    end
    local fill = self.bar:GetStatusBarTexture()
    self.spark:ClearAllPoints()
    self.spark:SetPoint("CENTER", fill, "RIGHT", 0, 0)
    local h = self.bar:GetHeight() or 10
    self.spark:SetSize(math.max(8, h * 1.6), h * 2.4)
    if self.color then self.bar:SetStatusBarColor(self.color[1], self.color[2], self.color[3]) end
end

function Bar:SetColor(r, g, b)
    local c = self.color
    if c and c[1] == r and c[2] == g and c[3] == b then return end
    self.color = { r, g, b }
    self.bar:SetStatusBarColor(r, g, b)
end

-- Values may be secret; StatusBar setters accept them directly.
function Bar:SetValues(value, max, instant)
    self.bar:SetMinMaxValues(0, max)
    self.bar:SetValue(value, instant and IMMEDIATE or SMOOTH)
end

function Bar:SetSpark(on)
    self.spark:SetShown(on)
end

------------------------------------------------------------------------------
-- Boxes: the look's frame round one bar
------------------------------------------------------------------------------

local Box = {}
Box.__index = Box

-- region: the bar to go round. The frame sits on a frame above it, so it's drawn over the fill.
function ns.CreateBox(region)
    local x = setmetatable({ region = region }, Box)
    x.overlay = CreateFrame("Frame", nil, region)
    x.overlay:SetAllPoints()
    x.overlay:SetFrameLevel(region:GetFrameLevel() + 5)
    x.bezel = {}
    for _, key in ipairs(KEYS) do
        local t = x.overlay:CreateTexture(nil, "OVERLAY", nil, 4)
        FrogLib.NoSnap(t)
        x.bezel[key] = t
    end
    x.forever = Borders.Forever(x.overlay, "OVERLAY", 5)
    x.edges = Borders.Edges(x.overlay, x.overlay, "OVERLAY", 6)
    return x
end

-- Lays eight textures out as a nine-slice of `art` round `region`: corners `slice` texels square,
-- `out` texels outside the region, t units per texel.
local function NineSlice(p, region, art, out, t)
    local m, o = art.slice * t, out * t
    local a, b = art.slice / art.size, (art.size - art.slice) / art.size
    p.tl:SetTexCoord(0, a, 0, a)
    p.t:SetTexCoord(a, b, 0, a)
    p.tr:SetTexCoord(b, 1, 0, a)
    p.l:SetTexCoord(0, a, a, b)
    p.r:SetTexCoord(b, 1, a, b)
    p.bl:SetTexCoord(0, a, b, 1)
    p.b:SetTexCoord(a, b, b, 1)
    p.br:SetTexCoord(b, 1, b, 1)
    for _, tex in pairs(p) do tex:ClearAllPoints() end
    p.tl:SetPoint("TOPLEFT", region, "TOPLEFT", -o, o)
    p.tr:SetPoint("TOPRIGHT", region, "TOPRIGHT", o, o)
    p.bl:SetPoint("BOTTOMLEFT", region, "BOTTOMLEFT", -o, -o)
    p.br:SetPoint("BOTTOMRIGHT", region, "BOTTOMRIGHT", o, -o)
    for _, key in ipairs({ "tl", "tr", "bl", "br" }) do p[key]:SetSize(m, m) end
    p.t:SetPoint("TOPLEFT", p.tl, "TOPRIGHT")
    p.t:SetPoint("BOTTOMRIGHT", p.tr, "BOTTOMLEFT")
    p.b:SetPoint("TOPLEFT", p.bl, "TOPRIGHT")
    p.b:SetPoint("BOTTOMRIGHT", p.br, "BOTTOMLEFT")
    p.l:SetPoint("TOPLEFT", p.tl, "BOTTOMLEFT")
    p.l:SetPoint("BOTTOMRIGHT", p.bl, "TOPRIGHT")
    p.r:SetPoint("TOPLEFT", p.tr, "BOTTOMLEFT")
    p.r:SetPoint("BOTTOMRIGHT", p.br, "TOPRIGHT")
end

-- The classic frame at a whole number of screen pixels per texel (like FrogLib's Forever frame),
-- the big art when the bar is tall enough for its corners, the small one otherwise.
function Box:PlaceBezel()
    local region = self.overlay
    local t = Thick() * FrogLib.Pixel(region)
    local h = region:GetHeight() or 0
    local art = h >= 2 * (BEZEL.slice - BEZEL.width) * t + t and BEZEL or BEZEL_SMALL
    if self.art ~= art then
        self.art = art
        for _, tex in pairs(self.bezel) do tex:SetTexture(art.file, nil, nil, "NEAREST") end
    end
    NineSlice(self.bezel, region, art, art.width, t)
end

function Box:Apply()
    local border = ns.Look().border
    for _, tex in pairs(self.bezel) do tex:SetShown(border == "bezel") end
    if border == "bezel" then self:PlaceBezel() end
    self.forever:SetShown(border == "forever")
    if border == "forever" then self.forever:Place(Thick()) end
    self.edges:SetShown(border == "edge")
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

-- Round `region`, `reach` units outside it (where the frame round it ends), on `parent` (a frame
-- below the bars, so only the light outside them shows).
function ns.CreateGlow(parent)
    local g = setmetatable({ parts = {} }, Glow)
    for _, key in ipairs(KEYS) do
        local t = parent:CreateTexture(nil, "BACKGROUND", nil, -7)
        t:SetTexture(GLOW.file)
        t:SetBlendMode("ADD")
        t:Hide()
        g.parts[key] = t
    end
    return g
end

function Glow:Place(region, reach)
    local t = FrogLib.Pixel(region)
    NineSlice(self.parts, region, GLOW, GLOW.out + reach / t, t)
end

function Glow:SetColor(r, g, b, a)
    for _, tex in pairs(self.parts) do tex:SetVertexColor(r, g, b, a or 1) end
end

function Glow:SetShown(on)
    for _, tex in pairs(self.parts) do tex:SetShown(on and true or false) end
end
