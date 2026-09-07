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
    card:AddLabel("Use |cff" .. Theme.accentHex .. "/tf|r to open this window.")
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

    -- ── Module status card (driven by the shared ModuleCatalog) ─────────────

    local statusCard = GUIFrame:CreateCard(scrollChild, "Modules", yOffset)
    for i, group in ipairs(GUIFrame.ModuleGroups) do
        if i > 1 then statusCard:AddSpacing(6) end
        local headerLabel = statusCard:AddLabel(group.label)
        headerLabel:SetTextColor(Theme.secondaryAccent[1], Theme.secondaryAccent[2], Theme.secondaryAccent[3], 1)
        statusCard:AddSpacing(2)
        for _, m in ipairs(GUIFrame.ModuleCatalog) do
            if m.group == group.key then
                local enabled = addon:IsModuleEnabled(m.id)
                local color   = enabled and "|cff" .. Theme.successHex or "|cff" .. Theme.errorHex
                local status  = enabled and "Enabled" or "Disabled"
                statusCard:AddLabel("  " .. m.label .. "  " .. color .. status .. "|r")
                statusCard:AddSpacing(2)
            end
        end
    end
    yOffset = yOffset + statusCard:GetContentHeight() + Theme.paddingLarge

    return yOffset
end)
