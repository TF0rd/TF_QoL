-- ════════════════════════════════════════════════════════════════
-- Part 9: Module — Shared Action Bars
-- (Automatically enforces Shared Action Bars on all talent
--  configurations by listening to Trait Config events)
-- ════════════════════════════════════════════════════════════════

local _, addon = ...
local module = {}

local frame = CreateFrame("Frame")

-- ── EVENT HANDLING ────────────────────────────────────────────

local function OnEvent(self, event, ...)
    if event == "TRAIT_CONFIG_CREATED" then
        local configInfo = ...
        if configInfo and configInfo.ID then
            C_ClassTalents.SetUsesSharedActionBars(configInfo.ID, true)
        end
    elseif event == "TRAIT_CONFIG_UPDATED" then
        local configID = ...
        if configID then
            local configInfo = C_Traits.GetConfigInfo(configID)
            -- Only set if currently false to prevent event loops
            if configInfo and not configInfo.usesSharedActionBars then
                C_ClassTalents.SetUsesSharedActionBars(configID, true)
            end
        end
    end
end

-- ── MODULE LIFECYCLE ──────────────────────────────────────────

function module:OnEnable()
    frame:RegisterEvent("TRAIT_CONFIG_CREATED")
    frame:RegisterEvent("TRAIT_CONFIG_UPDATED")
    frame:SetScript("OnEvent", OnEvent)
end

function module:OnDisable()
    frame:UnregisterAllEvents()
end

addon:RegisterModule("SharedActionBars", module)
