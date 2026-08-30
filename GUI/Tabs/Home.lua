-- ════════════════════════════════════════════════════════════════════════════════
-- Home tab — overview of addon, test mode, global settings, and module status
-- ════════════════════════════════════════════════════════════════════════════════

local _, addon = ...
local GUIFrame = addon.GUIFrame

GUIFrame:RegisterContent("Home", function(scrollChild, yOffset)
    local Theme = addon.Theme

    -- ── About card ──────────────────────────────────────────────────────────

    local card = GUIFrame:CreateCard(scrollChild, "TF QoL", yOffset)
    card:AddLabel("Enable modules individually using the sidebar. Each module has its own settings for font, position, visibility, and sound.")
    card:AddSpacing(4)
    card:AddLabel("Use |cff" .. string.format("%02x%02x%02x",
        math.floor(Theme.accent[1]*255), math.floor(Theme.accent[2]*255), math.floor(Theme.accent[3]*255))
        .. "/tf|r to open this window.")
    yOffset = yOffset + card:GetContentHeight() + Theme.paddingLarge

    -- ── Test mode card ──────────────────────────────────────────────────────

    local testCard = GUIFrame:CreateCard(scrollChild, "Test Mode", yOffset)
    local testRow = GUIFrame:CreateCheckbox(testCard.content, "Enable Test Mode",
        addon:IsAnyTestModeActive(),
        function(val) addon:SetGlobalTestMode(val) end)
    testCard:AddRow(testRow, 36)
    testCard:AddLabel("Previews all enabled alert modules so you can adjust positioning and font.")
    yOffset = yOffset + testCard:GetContentHeight() + Theme.paddingLarge

    -- ── Global settings card ────────────────────────────────────────────────

    local globalCard = GUIFrame:CreateCard(scrollChild, "Global Settings", yOffset)
    local slugRow = GUIFrame:CreateCheckbox(globalCard.content, "Slug Font Rendering",
        TFQoLDB.global.slugRendering == true,
        function(val)
            TFQoLDB.global.slugRendering = val
            for _, mod in pairs(addon.modules) do
                if mod.UpdateFont then mod:UpdateFont() end
            end
        end)
    globalCard:AddRow(slugRow, 36)
    globalCard:AddLabel("Applies slug rendering to all module fonts.\nMay improve readability on some displays.")

    globalCard:AddSpacing(4)
    local fontOptions = { "None" }
    for _, name in ipairs(addon:GetLSMFonts()) do
        fontOptions[#fontOptions + 1] = name
    end
    local fontRow = GUIFrame:CreateDropdown(globalCard.content, "Global Font Family",
        fontOptions, TFQoLDB.global.fontFamily or "None",
        function(val)
            TFQoLDB.global.fontFamily = (val ~= "None") and val or nil
            for _, mod in pairs(addon.modules) do
                if mod.UpdateFont then mod:UpdateFont() end
            end
        end)
    globalCard:AddRow(fontRow, 36)
    globalCard:AddLabel("Overrides font family for all modules.\nSet to None to use per-module settings.")
    yOffset = yOffset + globalCard:GetContentHeight() + Theme.paddingLarge

    -- ── Module status card ──────────────────────────────────────────────────

    local statusCard = GUIFrame:CreateCard(scrollChild, "Modules", yOffset)
    local groups = {
        {
            header = "Alerts",
            modules = {
                { id = "PotionAlert",   label = "Potion Alert" },
                { id = "LustAlert",     label = "Lust Alert" },
            },
        },
        {
            header = "QoL",
            modules = {
                { id = "SharedActionBars", label = "Shared Action Bars" },
                { id = "OCETag",              label = "OCE Group Tag" },
                { id = "GroupJoinedReminder",  label = "Group Joined Reminder" },
                { id = "ItemUpgradeReminder", label = "Item Upgrade Reminder" },
                { id = "StealthIndicator",    label = "Stealth Indicator" },
                { id = "BlizzardFrames",      label = "Blizzard Frames" },
            },
        },
        {
            header = "Keybindings",
            modules = {
                { id = "ActionBarToggle",     label = "Action Bar Toggle" },
                { id = "MountActions",        label = "Mount Actions" },
                { id = "ConsumableMacros",    label = "Macros" },
            },
        },
        {
            header = "Tools",
            modules = {
                { id = "CVarBrowser",         label = "CVar Browser" },
                { id = "CharacterViewer",     label = "Character Viewer" },
                { id = "MuteSounds",          label = "Mute Sounds" },
            },
        },
    }
    for i, group in ipairs(groups) do
        if i > 1 then statusCard:AddSpacing(6) end
        local headerLabel = statusCard:AddLabel(group.header)
        headerLabel:SetTextColor(Theme.secondaryAccent[1], Theme.secondaryAccent[2], Theme.secondaryAccent[3], 1)
        statusCard:AddSpacing(2)
        for _, m in ipairs(group.modules) do
            local enabled = addon:IsModuleEnabled(m.id)
            local color   = enabled and "|cff4DCC66" or "|cffE64D4D"
            local status  = enabled and "Enabled" or "Disabled"
            statusCard:AddLabel("  " .. m.label .. "  " .. color .. status .. "|r")
            statusCard:AddSpacing(2)
        end
    end
    yOffset = yOffset + statusCard:GetContentHeight() + Theme.paddingLarge

    return yOffset
end)