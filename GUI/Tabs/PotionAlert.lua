-- ════════════════════════════════════════════════════════════════════════════════
-- PotionAlert tab — combat potion reminder configuration
-- ════════════════════════════════════════════════════════════════════════════════

local _, addon = ...
local GUIFrame = addon.GUIFrame

GUIFrame:RegisterContent("PotionAlert", function(scrollChild, yOffset)
    local Theme = addon.Theme

    -- ── About card ──────────────────────────────────────────────────────────

    yOffset = GUIFrame:AddAboutCard(scrollChild, yOffset, "About",
        "Reminds you to use a combat potion when one is available.")

    -- ── Module header ──────────────────────────────────────────────────────

    local card = GUIFrame:CreateCard(scrollChild, "Potion Alert", yOffset)
    GUIFrame:AddModuleHeader(card, "PotionAlert")
    yOffset = yOffset + card:GetContentHeight() + Theme.paddingLarge

    -- ── Settings cards ──────────────────────────────────────────────────────

    yOffset = GUIFrame:AddModuleSettingsCards(scrollChild, yOffset,
        "potionAlert", { "visibility", "font", "position", "sound" })

    return yOffset
end)
