-- ════════════════════════════════════════════════════════════════════════════════
-- StealthIndicator tab — stealth detection text indicator configuration
-- ════════════════════════════════════════════════════════════════════════════════

local _, addon = ...
local GUIFrame = addon.GUIFrame

GUIFrame:RegisterContent("StealthIndicator", function(scrollChild, yOffset)
    local Theme = addon.Theme

    -- ── About card ──────────────────────────────────────────────────────────

    local aboutCard = GUIFrame:CreateCard(scrollChild, "About", yOffset)
    aboutCard:AddLabel("Displays a text indicator on screen when you are in stealth.")
    yOffset = yOffset + aboutCard:GetContentHeight() + Theme.paddingLarge

    -- ── Module header ──────────────────────────────────────────────────────

    local card = GUIFrame:CreateCard(scrollChild, "Stealth Indicator", yOffset)
    GUIFrame:AddModuleHeader(card, "StealthIndicator")
    yOffset = yOffset + card:GetContentHeight() + Theme.paddingLarge

    -- ── Settings cards ──────────────────────────────────────────────────────

    yOffset = GUIFrame:AddFontCard(scrollChild, yOffset, "stealthIndicator")
    yOffset = GUIFrame:AddPositionCard(scrollChild, yOffset, "stealthIndicator")

    return yOffset
end)
