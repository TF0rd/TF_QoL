-- ════════════════════════════════════════════════════════════════════════════════
-- PotionAlert tab — combat potion reminder configuration
-- ════════════════════════════════════════════════════════════════════════════════

local _, addon = ...
local GUIFrame = addon.GUIFrame

GUIFrame:RegisterContent("PotionAlert", function(scrollChild, yOffset)
    local Theme = addon.Theme

    -- ── About card ──────────────────────────────────────────────────────────

    local aboutCard = GUIFrame:CreateCard(scrollChild, "About", yOffset)
    aboutCard:AddLabel("Reminds you to use a combat potion when one is available.")
    yOffset = yOffset + aboutCard:GetContentHeight() + Theme.paddingLarge

    -- ── Module header ──────────────────────────────────────────────────────

    local card = GUIFrame:CreateCard(scrollChild, "Potion Alert", yOffset)
    GUIFrame:AddModuleHeader(card, "PotionAlert")
    yOffset = yOffset + card:GetContentHeight() + Theme.paddingLarge

    -- ── Settings cards ──────────────────────────────────────────────────────

    yOffset = GUIFrame:AddVisibilityCard(scrollChild, yOffset, "potionAlert")
    yOffset = GUIFrame:AddFontCard(scrollChild, yOffset, "potionAlert")
    yOffset = GUIFrame:AddPositionCard(scrollChild, yOffset, "potionAlert")
    yOffset = GUIFrame:AddSoundCard(scrollChild, yOffset, "potionAlert")

    return yOffset
end)
