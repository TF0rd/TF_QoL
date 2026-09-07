-- ════════════════════════════════════════════════════════════════
-- Part 3: Settings (Slash command and GUI toggle)
-- (Registers /tf slash command and auto-disables test mode when
--  the GUI window is closed)
-- ════════════════════════════════════════════════════════════════

local _, addon = ...

-- Open the custom GUI with /tf or /tfqol
SLASH_TF1 = "/tf"
SLASH_TF2 = "/tfqol"
SlashCmdList["TF"] = function(msg)
    msg = (msg or ""):lower():match("^%s*(.-)%s*$")
    if msg == "char" then
        if addon:IsModuleEnabled("CharacterViewer") then
            addon.modules.CharacterViewer:Toggle()
        end
    elseif msg == "pi" then
        -- Power Infusion helper (Macros module): bake target into PI macro.
        if addon:IsModuleEnabled("ConsumableMacros") then
            addon.modules.ConsumableMacros:SetPowerInfusionTarget()
        end
    elseif msg == "" then
        if addon.GUIFrame then
            addon.GUIFrame:Toggle()
        end
    else
        print("|cffffd200TF QoL:|r Unknown command '" .. msg .. "'. Available commands:")
        print("  /tf — Open settings")
        print("  /tf char — Toggle Character Viewer")
        print("  /tf pi — Set Power Infusion target")
    end
end

-- Auto-disable test mode when the GUI window is closed
if addon.GUIFrame and addon.GUIFrame.RegisterOnCloseCallback then
    addon.GUIFrame:RegisterOnCloseCallback("autoDisableTestMode", function()
        if addon:IsAnyTestModeActive() then
            addon:SetGlobalTestMode(false)
        end
    end)
end
