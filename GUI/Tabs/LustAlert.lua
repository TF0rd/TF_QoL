-- ════════════════════════════════════════════════════════════════════════════════
-- LustAlert tab — Bloodlust/Heroism alert configuration
-- ════════════════════════════════════════════════════════════════════════════════

local _, addon = ...
local GUIFrame = addon.GUIFrame

GUIFrame:RegisterContent("LustAlert", function(scrollChild, yOffset)
    local Theme = addon.Theme

    -- ── About card ──────────────────────────────────────────────────────────

    local aboutCard = GUIFrame:CreateCard(scrollChild, "About", yOffset)
    aboutCard:AddLabel("Displays an alert when Bloodlust, Heroism, Time Warp, or an equivalent haste effect becomes active.")
    yOffset = yOffset + aboutCard:GetContentHeight() + Theme.paddingLarge

    -- ── Module header with unique setting ──────────────────────────────────

    local card = GUIFrame:CreateCard(scrollChild, "Lust Alert", yOffset)
    GUIFrame:AddModuleHeader(card, "LustAlert")

    -- "Only if has lust" is specific to this module
    local mod = addon.modules["LustAlert"]
    local onlyLustRow = GUIFrame:CreateCheckbox(card.content, "Only Show if Class Has Lust",
        TFQoLDB.lustAlert.onlyIfHasLust == true,
        function(val)
            TFQoLDB.lustAlert.onlyIfHasLust = val
            if mod and mod.ForceCheck then mod:ForceCheck() end
        end)
    card:AddRow(onlyLustRow, 36)

    yOffset = yOffset + card:GetContentHeight() + Theme.paddingLarge

    -- ── Settings cards ──────────────────────────────────────────────────────

    yOffset = GUIFrame:AddVisibilityCard(scrollChild, yOffset, "lustAlert")
    yOffset = GUIFrame:AddFontCard(scrollChild, yOffset, "lustAlert")
    yOffset = GUIFrame:AddPositionCard(scrollChild, yOffset, "lustAlert")
    yOffset = GUIFrame:AddSoundCard(scrollChild, yOffset, "lustAlert")

    return yOffset
end)
