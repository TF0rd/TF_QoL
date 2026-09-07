-- ════════════════════════════════════════════════════════════════════════════════
-- StealthIndicator tab — stealth detection text indicator configuration
-- ════════════════════════════════════════════════════════════════════════════════

local _, addon = ...
local GUIFrame = addon.GUIFrame

GUIFrame:RegisterContent("StealthIndicator", function(scrollChild, yOffset)
    local Theme = addon.Theme

    -- ── About card ──────────────────────────────────────────────────────────

    yOffset = GUIFrame:AddAboutCard(scrollChild, yOffset, "About",
        "Displays a text indicator on screen when you are in stealth.")

    -- ── Module header ──────────────────────────────────────────────────────

    local card = GUIFrame:CreateCard(scrollChild, "Stealth Indicator", yOffset)
    GUIFrame:AddModuleHeader(card, "StealthIndicator")
    yOffset = yOffset + card:GetContentHeight() + Theme.paddingLarge

    -- ── Settings cards ──────────────────────────────────────────────────────

    yOffset = GUIFrame:AddModuleSettingsCards(scrollChild, yOffset,
        "stealthIndicator", { "font", "position" })

    return yOffset
end)
