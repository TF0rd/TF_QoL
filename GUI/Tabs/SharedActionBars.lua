-- ════════════════════════════════════════════════════════════════════════════════
-- SharedActionBars tab — per-spec bar lock configuration
-- ════════════════════════════════════════════════════════════════════════════════

local _, addon = ...
local GUIFrame = addon.GUIFrame

GUIFrame:RegisterContent("SharedActionBars", function(scrollChild, yOffset)
    local Theme = addon.Theme

    -- ── About card ──────────────────────────────────────────────────────────

    yOffset = GUIFrame:AddAboutCard(scrollChild, yOffset, "About",
        "Locks all talent loadouts to shared action bars, preventing per-spec bar layouts.")

    -- ── Module header ──────────────────────────────────────────────────────

    local card = GUIFrame:CreateCard(scrollChild, "Shared Action Bars", yOffset)
    GUIFrame:AddModuleHeader(card, "SharedActionBars")
    yOffset = yOffset + card:GetContentHeight() + Theme.paddingLarge

    return yOffset
end)
