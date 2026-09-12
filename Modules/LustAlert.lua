-- ════════════════════════════════════════════════════════════════
-- Part 11: Module — Lust Alert
-- (Shows a floating indicator when no bloodlust-equivalent debuff
--  is active on the player, with configurable font/position/sound,
--  class filter, and instance-type filters)
-- ════════════════════════════════════════════════════════════════

local _, addon = ...

-- ── Local constants ──────────────────────────────────────────

-- Lust-family debuff IDs
local lustDebuffs = {
    57723,  -- Exhaustion (Heroism)
    57724,  -- Sated (Bloodlust)
    80354,  -- Temporal Displacement (Time Warp)
    160455, -- Fatigued (Primal Rage - older)
    264689, -- Fatigued (Primal Rage)
    390435, -- Exhaustion (Fury of the Aspects)
}

-- Classes that have a bloodlust-equivalent ability:
--   Shaman: Bloodlust / Heroism
--   Mage: Time Warp
--   Hunter: Primal Rage (Beast Mastery, via pet)
--   Evoker: Fury of the Aspects
local LUST_CLASSES = { SHAMAN = true, MAGE = true, HUNTER = true, EVOKER = true }
local playerClass = select(2, UnitClass("player"))

-- ── Helper functions ─────────────────────────────────────────

-- True when no lust debuff is active (alert should show).
local function ScanLust()
    for _, spellID in ipairs(lustDebuffs) do
        if C_UnitAuras.GetPlayerAuraBySpellID(spellID) then
            return false
        end
    end
    return true
end

-- Extra visibility gate: class filter.
local function LustGate()
    local db = TFQoLDB.lustAlert
    if db and db.onlyIfHasLust and not LUST_CLASSES[playerClass] then return false end
end

-- UNIT_AURA rescans (ignoring secret/non-player units); all else re-evaluates.
local function RescanFilter(event, unit)
    if event == "UNIT_AURA" then
        -- unit can be a secret value when auras are restricted; guard the
        -- comparison (we only registered UNIT_AURA for "player").
        if addon:IsSecretValue(unit) or unit ~= "player" then return "ignore" end
        return "rescan"
    end
    return "evaluate"
end

-- ── Module lifecycle ─────────────────────────────────────────

local module = addon:CreateIndicatorAlert("LustAlert", {
    dbKey = "lustAlert",
    frameName = "TFQoL_LustAlertFrame",
    text = "Lust Available",
    scanFn = ScanLust,
    shouldBeActiveFn = LustGate,
    rescanEventFilter = RescanFilter,
    events = {
        "PLAYER_ENTERING_WORLD",
        "PLAYER_REGEN_DISABLED",
        "PLAYER_REGEN_ENABLED",
        "ENCOUNTER_END",
    },
    unitEvents = {
        { event = "UNIT_AURA", unit = "player" },
    },
})

addon:RegisterModule("LustAlert", module)
