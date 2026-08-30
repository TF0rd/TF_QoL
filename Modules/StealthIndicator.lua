-- ════════════════════════════════════════════════════════════════
-- Part 5: Module — Stealth Indicator
-- (Shows a floating "Stealth" text when the player is stealthed,
--  with configurable font/position and test mode)
-- ════════════════════════════════════════════════════════════════

local _, addon = ...
local module = {}

local frame = CreateFrame("Frame", "TFQoL_StealthIndicatorFrame", UIParent)
frame:SetPoint("CENTER", 0, 25)
frame:SetSize(12, 12)
frame:Hide()

frame.text = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
frame.text:SetPoint("CENTER")
frame.text:SetText("Stealth")
frame.text:SetTextColor(1, 1, 1)
frame.text:SetShadowOffset(0, 0)
frame.text:SetShadowColor(0, 0, 0, 0)

local testModeActive = false

local eventFrame = CreateFrame("Frame")

-- ── FONT RENDERING ────────────────────────────────────────────

function module:UpdateFont()
    local db = TFQoLDB.stealthIndicator
    local flags = (TFQoLDB.global.slugRendering == true) and "OUTLINE,SLUG" or "OUTLINE"
    frame.text:SetFont(addon:ResolveFont(db.fontFamily), db.fontSize, flags)
end

-- ── POSITION ──────────────────────────────────────────────────

function module:UpdatePosition()
    addon:ApplyPosition(frame, TFQoLDB.stealthIndicator)
end

-- ── TEST MODE ─────────────────────────────────────────────────

function module:SetTestMode(enabled)
    testModeActive = enabled
    if enabled then
        frame:Show()
    else
        if not IsStealthed() then
            frame:Hide()
        end
    end
end

function module:IsTestMode()
    return testModeActive
end

-- ── DISPLAY LOGIC ─────────────────────────────────────────────

local function UpdateDisplay()
    if testModeActive then return end
    if IsStealthed() then
        frame:Show()
    else
        frame:Hide()
    end
end

-- ── EVENT HANDLING ────────────────────────────────────────────

local function OnEvent()
    UpdateDisplay()
end

-- ── MODULE LIFECYCLE ──────────────────────────────────────────

function module:OnEnable()
    self:UpdateFont()
    self:UpdatePosition()
    eventFrame:RegisterEvent("UPDATE_STEALTH")
    eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    eventFrame:SetScript("OnEvent", OnEvent)
    UpdateDisplay()
end

function module:OnDisable()
    eventFrame:UnregisterAllEvents()
    frame:Hide()
    testModeActive = false
end

addon:RegisterModule("StealthIndicator", module)
