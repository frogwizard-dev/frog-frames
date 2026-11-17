local ADDON, ns = ...

-- Every frame FrogFrames draws, made at login (secure frames are best made out of combat; the party's
-- pets, off to start, the first time they're switched on) and laid out again whenever a setting
-- changes. Attached frames (your pet, your target's target, the party's pets) hang from another frame
-- and move with it; the party frames stack under the first.

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

-- Whether a frame is wanted at all (a party pet's needs the party's on too).
local function Wanted(def)
    local units = ns.db.units
    return units[def.kind].enabled and (def.kind ~= "partypet" or units.party.enabled)
end

local function Build(def)
    local frame = ns.NewUnitFrame(def)
    frame:Build()
    ns.frames[def.key] = frame
    ns.frameList[#ns.frameList + 1] = frame
    return frame
end

-- Its events are registered by the ns.Refresh that follows.
function ns.BuildAll()
    for _, def in ipairs(DEFS) do
        if def.kind ~= "partypet" or Wanted(def) then Build(def) end
    end
end

-- Blizzard's frames for the kinds that are on, hidden (FrogLib's Hider). Kept out: what hangs under the
-- player frame (its PlayerBottomManagedFrameContainer), and while ours are off, the target's target and
-- the combo points (the target frame's children). The raid-style party and raid frames aren't touched.
local function HideBlizzard()
    local units, db = ns.db.units, ns.db
    local Set = FrogLib.Hider.Set
    Set(ADDON, "PlayerFrame", units.player.enabled, { keep = { "PlayerBottomManagedFrameContainer" } })
    Set(ADDON, "PetFrame", units.pet.enabled)
    local keep = {}
    if not units.tot.enabled then keep[#keep + 1] = "TargetFrameToT" end
    if not db.combo.enabled then keep[#keep + 1] = "ComboFrame" end
    Set(ADDON, "TargetFrame", units.target.enabled, { keep = keep })
    Set(ADDON, "TargetFrameToT", units.tot.enabled)
    Set(ADDON, "FocusFrame", units.focus.enabled)
    Set(ADDON, "PartyFrame", units.party.enabled)
end

-- Everything, from the settings. Only out of combat (Core.lua's ns.Refresh sees to that).
function ns.ApplyAll()
    for _, def in ipairs(DEFS) do
        if not ns.frames[def.key] and Wanted(def) then Build(def):RegisterEvents() end
    end
    for _, frame in ipairs(ns.frameList) do frame:Apply() end
    ns.Combo:Apply()
    FrogLib.Grid:SetShown(not ns.db.locked, "FrogFrames")
    HideBlizzard()
    ns.CheckFrogTarget()
end

-- Range and your target's target, a few times a second, for the frames that need it (Unit:Polled). The game's own
-- timer, so nothing runs in the frames between, and only while a frame needs it.
local issecret, GetTime, UnitGUID = FrogLib.issecret, GetTime, UnitGUID
local ticker

local function Tick()
    for _, frame in ipairs(ns.frameList) do
        if frame.ticked then
            if frame.poll then
                -- A new unit is drawn in full (its portrait too); the same one updated. Who it is can be secret:
                -- then UNIT_TARGET says when it changes (Unit.lua), and its picture is looked at once a second.
                local guid = UnitGUID(frame.unit)
                if issecret(guid) then
                    frame:Update(false, true)
                    if GetTime() - (frame.lastFull or 0) > 1 then
                        frame.lastFull = GetTime()
                        frame:UpdatePortrait()
                    end
                else
                    local full = guid ~= frame.guid
                    frame:Update(full, not full)
                end
            else
                frame:UpdateRange()
            end
        end
    end
end

-- Run whenever a frame may have started or stopped needing it (shown, hidden, settings, combat, who its unit is).
function ns.UpdateTicker()
    local any = false
    for _, frame in ipairs(ns.frameList) do
        frame.ticked = frame:Polled()
        any = any or frame.ticked
    end
    if any and not ticker then
        ticker = C_Timer.NewTicker(0.2, Tick)
    elseif ticker and not any then
        ticker:Cancel()
        ticker = nil
    end
end
