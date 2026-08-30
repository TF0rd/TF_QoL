-- ════════════════════════════════════════════════════════════════
-- Part 10: Module — Potion Alert
-- (Shows a floating indicator when an endgame combat potion is
--  off cooldown, with configurable font/position/sound and
--  instance-type filters)
-- ════════════════════════════════════════════════════════════════

local _, addon = ...
local module = {}

local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)

local frame = CreateFrame("Frame", "TFQoL_PotionAlertFrame", UIParent)
frame:SetPoint("CENTER", 0, -70)
frame:SetSize(16, 16)
frame:Hide()

frame.text = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
frame.text:SetPoint("CENTER")
frame.text:SetTextColor(0.1176, 1.0, 0.0, 1.0) -- #1EFF00
frame.text:SetText("Potion Ready")
frame.text:SetShadowOffset(0, 0)
frame.text:SetShadowColor(0, 0, 0, 0)

-- Endgame combat potion item IDs
local combatPotions = {
    212263, 212264, 212265,         -- The War Within: Tempered Potions
    241288, 241289,                 -- Midnight: Potion of Recklessness
    241292, 241293,                 -- Midnight: Draught of Rampant Abandon
    241296, 241297,                 -- Midnight: Potion of Zealotry
    241308, 241309,                 -- Midnight: Light's Potential
    245897, 245898,                 -- Midnight: Fleeting Light's Potential
    245900, 245901,                 -- Midnight: Fleeting Potion of Zealotry
    245902, 245903,                 -- Midnight: Fleeting Potion of Recklessness
}

local cooldownEventsActive = false
local testModeActive       = false
local moduleEnabled        = false

local eventFrame = CreateFrame("Frame")

-- ── PRIVATE HELPERS ───────────────────────────────────────────

local function ShouldBeActive(event)
    local db = TFQoLDB.potionAlert

    local inCombat = InCombatLockdown() or (event == "PLAYER_REGEN_DISABLED")
    if (db.onlyCombat == true) and not inCombat then return false end

    local inInstance, instanceType = IsInInstance()
    if instanceType == "party" and not (db.showInDungeons == true) then return false end
    if instanceType == "raid"  and not (db.showInRaids    == true) then return false end
    if (not inInstance or instanceType == "scenario") and not (db.showInOpenWorld == true) then return false end

    return true
end

local function ScanPotionCooldowns()
    if testModeActive then return end

    for _, itemID in ipairs(combatPotions) do
        local count = C_Item.GetItemCount(itemID)
        if count and count > 0 then
            local start = C_Container.GetItemCooldown(itemID)
            if start == 0 then
                if not frame:IsVisible() then
                    local db = TFQoLDB.potionAlert
                    if db.playSound and db.soundName and db.soundName ~= "None" and LSM then
                        local path = LSM:Fetch("sound", db.soundName)
                        if path then PlaySoundFile(path, "Master") end
                    end
                end
                frame:Show()
                return
            end
        end
    end
    frame:Hide()
end

local function EvaluateState(event)
    if testModeActive then return end

    if ShouldBeActive(event) then
        cooldownEventsActive = true
        ScanPotionCooldowns()
    else
        cooldownEventsActive = false
        frame:Hide()
    end
end

-- ── FONT RENDERING ────────────────────────────────────────────

function module:UpdateFont()
    local db = TFQoLDB.potionAlert
    local flags = (TFQoLDB.global.slugRendering == true) and "OUTLINE,SLUG" or "OUTLINE"
    frame.text:SetFont(addon:ResolveFont(db.fontFamily), db.fontSize, flags)
end

-- ── POSITION ──────────────────────────────────────────────────

function module:UpdatePosition()
    addon:ApplyPosition(frame, TFQoLDB.potionAlert)
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

local function OnEvent(_, event)
    if event == "BAG_UPDATE_COOLDOWN" or event == "SPELL_UPDATE_COOLDOWN" then
        if cooldownEventsActive then ScanPotionCooldowns() end
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
    eventFrame:RegisterEvent("BAG_UPDATE_COOLDOWN")
    eventFrame:RegisterEvent("SPELL_UPDATE_COOLDOWN")
    eventFrame:SetScript("OnEvent", OnEvent)
    moduleEnabled = true
    EvaluateState()
end

function module:OnDisable()
    moduleEnabled = false
    eventFrame:UnregisterAllEvents()
    frame:Hide()
    cooldownEventsActive = false
    testModeActive = false
end

addon:RegisterModule("PotionAlert", module)
