-- ════════════════════════════════════════════════════════════════════════════════
-- OCETag tab — Oceanic realm group tagging configuration
-- ════════════════════════════════════════════════════════════════════════════════

local _, addon = ...
local GUIFrame = addon.GUIFrame

GUIFrame:RegisterContent("OCETag", function(scrollChild, yOffset)
    local Theme = addon.Theme

    -- ── About card ──────────────────────────────────────────────────────────

    yOffset = GUIFrame:AddAboutCard(scrollChild, yOffset, "About",
        "Flags Oceanic realm groups in the Premade Groups Finder with an |cFFFF4040[OCE]|r tag.")

    -- ── Module header ──────────────────────────────────────────────────────

    local card = GUIFrame:CreateCard(scrollChild, "OCE Group Tag", yOffset)
    GUIFrame:AddModuleHeader(card, "OCETag")
    yOffset = yOffset + card:GetContentHeight() + Theme.paddingLarge

    return yOffset
end)
