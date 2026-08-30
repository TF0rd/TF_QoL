-- ════════════════════════════════════════════════════════════════
-- Part 11: Module — Lust Alert
-- (Shows a floating indicator when no bloodlust-equivalent debuff
--  is active on the player, with configurable font/position/sound,
--  class filter, and instance-type filters)
-- ════════════════════════════════════════════════════════════════

local _, addon = ...
local module = {}

local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)

local frame = CreateFrame("Frame", "TFQoL_LustAlertFrame", UIParent)
frame:SetPoint("CENTER", 0, -100)
frame:SetSize(16, 16)
frame:Hide()

frame.text = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
frame.text:SetPoint("CENTER")
frame.text:SetTextColor(0.1176, 1.0, 0.0, 1.0) -- #1EFF00 (Neon Green)
frame.text:SetText("Lust Available")
frame.text:SetShadowOffset(0, 0)
frame.text:SetShadowColor(0, 0, 0, 0)

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

local auraEventsActive = false
local testModeActive   = false
local moduleEnabled    = false

local eventFrame = CreateFrame("Frame")

-- ── PRIVATE HELPERS ───────────────────────────────────────────

local function ShouldBeActive(event)
    local db = TFQoLDB.lustAlert

    if db.onlyIfHasLust and not LUST_CLASSES[playerClass] then return false end

    local inCombat = InCombatLockdown() or (event == "PLAYER_REGEN_DISABLED")
    if (db.onlyCombat == true) and not inCombat then return false end

    local inInstance, instanceType = IsInInstance()
    if instanceType == "party" and not (db.showInDungeons == true) then return false end
    if instanceType == "raid"  and not (db.showInRaids    == true) then return false end
    if (not inInstance or instanceType == "scenario") and not (db.showInOpenWorld == true) then return false end

    return true
end

local function HasLustDebuff()
    for _, spellID in ipairs(lustDebuffs) do
        if C_UnitAuras.GetPlayerAuraBySpellID(spellID) then
            return true
        end
    end
    return false
end

local function ScanLustDebuffs()
    if testModeActive then return end

    if HasLustDebuff() then
        frame:Hide()
    else
        if not frame:IsVisible() then
            local db = TFQoLDB.lustAlert
            if db.playSound and db.soundName and db.soundName ~= "None" and LSM then
                local path = LSM:Fetch("sound", db.soundName)
                if path then PlaySoundFile(path, "Master") end
            end
        end
        frame:Show()
    end
end

local function EvaluateState(event)
    if testModeActive then return end

    if ShouldBeActive(event) then
        auraEventsActive = true
        ScanLustDebuffs()
    else
        auraEventsActive = false
        frame:Hide()
    end
end

-- ── FONT RENDERING ────────────────────────────────────────────

function module:UpdateFont()
    local db = TFQoLDB.lustAlert
    local flags = (TFQoLDB.global.slugRendering == true) and "OUTLINE,SLUG" or "OUTLINE"
    frame.text:SetFont(addon:ResolveFont(db.fontFamily), db.fontSize, flags)
end

-- ── POSITION ──────────────────────────────────────────────────

function module:UpdatePosition()
    addon:ApplyPosition(frame, TFQoLDB.lustAlert)
end

-- ── TEST MODE ─────────────────────────────────────────────────

function module:SetTestMode(enabled)
    testModeActive = enabled
    if enabled then
        frame:Show()
    else
        frame:Hide()
        EvaluateState()
    end
end

function module:IsTestMode()
    return testModeActive
end

-- ── EVENT HANDLING ────────────────────────────────────────────

local function OnEvent(_, event, unit)
    if event == "UNIT_AURA" then
        if not auraEventsActive then return end
        -- 12.1: unitTarget can be a secret value when auras are restricted;
        -- guard the comparison (and we only registered UNIT_AURA for "player").
        if (issecretvalue and issecretvalue(unit)) or unit ~= "player" then return end
        -- Don't parse updateInfo — its aura data can be secret values in 12.1
        -- (comparisons/indexing throw). A full re-scan via GetPlayerAuraBySpellID
        -- is cheap and secret-safe.
        ScanLustDebuffs()
    else
        EvaluateState(event)
    end
end

function module:ForceCheck()
    if not moduleEnabled then return end
    EvaluateState()
end

-- ── MODULE LIFECYCLE ──────────────────────────────────────────

function module:OnEnable()
    self:UpdateFont()
    self:UpdatePosition()
    eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    eventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
    eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    eventFrame:RegisterEvent("ENCOUNTER_END")
    eventFrame:RegisterUnitEvent("UNIT_AURA", "player")
    eventFrame:SetScript("OnEvent", OnEvent)
    moduleEnabled = true
    EvaluateState()
end

function module:OnDisable()
    moduleEnabled = false
    eventFrame:UnregisterAllEvents()
    frame:Hide()
    auraEventsActive = false
    testModeActive = false
end

addon:RegisterModule("LustAlert", module)
