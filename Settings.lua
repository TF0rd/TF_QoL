-- ════════════════════════════════════════════════════════════════
-- Part 2: Settings (Slash command and GUI toggle)
-- (Registers /tf slash command and auto-disables test mode when
--  the GUI window is closed)
-- ════════════════════════════════════════════════════════════════

local _, addon = ...

-- Open the custom GUI with /tf
SLASH_TF1 = "/tf"
SlashCmdList["TF"] = function(msg)
    msg = (msg or ""):match("^%s*(.-)%s*$")
    if msg == "char" then
        if addon:IsModuleEnabled("CharacterViewer") then
            addon.modules.CharacterViewer:Toggle()
        end
    elseif msg == "pi" then
        -- Power Infusion helper (Macros module): bake target into PI macro.
        if addon:IsModuleEnabled("ConsumableMacros") then
            addon.modules.ConsumableMacros:SetPowerInfusionTarget()
        end
    else
        addon.GUIFrame:Toggle()
    end
end

-- Auto-disable test mode when the GUI window is closed
addon.GUIFrame:RegisterOnCloseCallback("autoDisableTestMode", function()
    if addon:IsAnyTestModeActive() then
        addon:SetGlobalTestMode(false)
    end
end)
