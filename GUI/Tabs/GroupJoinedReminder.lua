-- ════════════════════════════════════════════════════════════════════════════════
-- GroupJoinedReminder tab — Mythic+/raid join notification configuration
-- ════════════════════════════════════════════════════════════════════════════════

local _, addon = ...
local GUIFrame = addon.GUIFrame

GUIFrame:RegisterContent("GroupJoinedReminder", function(scrollChild, yOffset)
    local Theme = addon.Theme

    -- ── About card ──────────────────────────────────────────────────────────

    yOffset = GUIFrame:AddAboutCard(scrollChild, yOffset, "About",
        "Prints a chat message when you join a Mythic+ or Mythic raid group via the Premade Groups Finder.")

    -- ── Module header ──────────────────────────────────────────────────────

    local card = GUIFrame:CreateCard(scrollChild, "Group Joined Reminder", yOffset)
    GUIFrame:AddModuleHeader(card, "GroupJoinedReminder")
    yOffset = yOffset + card:GetContentHeight() + Theme.paddingLarge

    return yOffset
end)
