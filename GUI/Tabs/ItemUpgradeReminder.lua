-- ════════════════════════════════════════════════════════════════════════════════
-- ItemUpgradeReminder tab — upgradeable item notification configuration
-- ════════════════════════════════════════════════════════════════════════════════

local _, addon = ...
local GUIFrame = addon.GUIFrame

GUIFrame:RegisterContent("ItemUpgradeReminder", function(scrollChild, yOffset)
    local Theme = addon.Theme

    -- ── About card ──────────────────────────────────────────────────────────

    local aboutCard = GUIFrame:CreateCard(scrollChild, "About", yOffset)
    aboutCard:AddLabel("Prints a chat message for each equipped item that can be upgraded to a higher item level for gold only (no crests required), based on your character's and account's high-watermark for that slot.")
    yOffset = yOffset + aboutCard:GetContentHeight() + Theme.paddingLarge

    -- ── Module header with custom setting ──────────────────────────────────

    local card = GUIFrame:CreateCard(scrollChild, "Item Upgrade Reminder", yOffset)
    GUIFrame:AddModuleHeader(card, "ItemUpgradeReminder")

    local onScreenRow = GUIFrame:CreateCheckbox(card.content, "Show on Screen",
        TFQoLDB.itemUpgradeReminder.showOnScreen == true,
        function(val)
            TFQoLDB.itemUpgradeReminder.showOnScreen = val
            local mod = addon.modules["ItemUpgradeReminder"]
            if mod and mod.IsTestMode and mod:IsTestMode() then return end
            local frame = _G["TFQoL_ItemUpgradeReminderFrame"]
            if frame and not val then frame:Hide() end
        end)
    card:AddRow(onScreenRow, 36)

    yOffset = yOffset + card:GetContentHeight() + Theme.paddingLarge

    -- ── Settings cards ──────────────────────────────────────────────────────

    yOffset = GUIFrame:AddFontCard(scrollChild, yOffset, "itemUpgradeReminder")
    yOffset = GUIFrame:AddPositionCard(scrollChild, yOffset, "itemUpgradeReminder")

    return yOffset
end)
