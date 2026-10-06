local ADDON, ns = ...

-- Every frame FrogFrames draws, made once at login (secure frames are best made out of combat)
-- and laid out again whenever a setting changes. Attached frames (your pet, your target's
-- target, the party's pets) hang from another frame and move with it; the party frames stack
-- under the first.

-- In the order they're applied: a frame before the ones that hang from it.
local DEFS = {
    { key = "player", kind = "player", unit = "player", side = "left" },
    { key = "pet", kind = "pet", unit = "pet", side = "left", parent = "player" },
    { key = "target", kind = "target", unit = "target", side = "right", event = "PLAYER_TARGET_CHANGED" },
    -- Your target's target has no events of its own: it's checked a few times a second.
    { key = "tot", kind = "tot", unit = "targettarget", side = "left", parent = "target",
        event = "PLAYER_TARGET_CHANGED", poll = true },
    { key = "focus", kind = "focus", unit = "focus", side = "right", event = "PLAYER_FOCUS_CHANGED" },
}
for i = 1, 4 do
    DEFS[#DEFS + 1] = { key = "party" .. i, kind = "party", unit = "party" .. i, index = i, side = "left" }
end
for i = 1, 4 do
    DEFS[#DEFS + 1] = { key = "partypet" .. i, kind = "partypet", unit = "partypet" .. i, index = i, side = "left",
        parent = "party" .. i }
end

local NAMES = { player = "Player", pet = "Pet", target = "Target", tot = "Target of target", focus = "Focus",
    party = "Party", partypet = "Party pet" }
function ns.KindName(kind) return NAMES[kind] or kind end

ns.frames = {}
ns.frameList = {}

function ns.BuildAll()
    for _, def in ipairs(DEFS) do
        local u = ns.NewUnitFrame(def)
        u:Build()
        ns.frames[def.key] = u
        ns.frameList[#ns.frameList + 1] = u
    end
    ns.Combo:Init()
    ns.StartTicker()
end

-- Blizzard's frames for the kinds that are on, hidden (FrogLib's Hider). Children with a life of their
-- own stay out: the frames that hang under the player frame (the pet frame and the totem timers,
-- in its PlayerBottomManagedFrameContainer; the pet frame is hidden on its own while ours is on),
-- and, while ours for them are off, the target's target and the combo points (children of the
-- target frame). The raid-style party frames and the raid frames aren't touched.
local function HideBlizzard()
    local u, db = ns.db.units, ns.db
    local Set = FrogLib.Hider.Set
    Set(ADDON, "PlayerFrame", u.player.enabled, { keep = { "PlayerBottomManagedFrameContainer" } })
    Set(ADDON, "PetFrame", u.pet.enabled)
    local keep = {}
    if not u.tot.enabled then keep[#keep + 1] = "TargetFrameToT" end
    if not db.combo.enabled then keep[#keep + 1] = "ComboFrame" end
    Set(ADDON, "TargetFrame", u.target.enabled, { keep = keep })
    Set(ADDON, "TargetFrameToT", u.tot.enabled)
    Set(ADDON, "FocusFrame", u.focus.enabled)
    Set(ADDON, "PartyFrame", u.party.enabled)
end

-- Everything, from the settings. Only out of combat (Core.lua's ns.Refresh sees to that).
function ns.ApplyAll()
    for _, u in ipairs(ns.frameList) do u:Apply() end
    ns.Combo:Apply()
    FrogLib.Grid:SetShown(not ns.db.locked, "FrogFrames")
    HideBlizzard()
    ns.CheckFrogTarget()
end

-- Range and your target's target, a few times a second, for the frames that are showing.
function ns.StartTicker()
    local ticker = CreateFrame("Frame")
    local elapsed = 0
    ticker:SetScript("OnUpdate", function(_, dt)
        elapsed = elapsed + dt
        if elapsed < 0.2 then return end
        elapsed = 0
        for _, u in ipairs(ns.frameList) do
            if u.root:IsShown() then
                if u.poll then
                    -- A new unit is drawn in full (its portrait too); the same one just updated.
                    -- Who it is can be secret: then in full once a second.
                    local guid = UnitGUID(u.unit)
                    local full
                    if ns.issecret(guid) then
                        full = GetTime() - (u.lastFull or 0) > 1
                    else
                        full = guid ~= u.guid
                    end
                    u:Update(full)
                elseif u:Cfg().fadeRange then
                    u:UpdateRange()
                end
            end
        end
    end)
end
