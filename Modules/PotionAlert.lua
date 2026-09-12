-- ════════════════════════════════════════════════════════════════
-- Part 10: Module — Potion Alert
-- (Shows a floating indicator when an endgame combat potion is
--  off cooldown, with configurable font/position/sound and
--  instance-type filters)
-- ════════════════════════════════════════════════════════════════

local _, addon = ...

-- ── Local constants ──────────────────────────────────────────

-- Endgame combat potion item IDs
local combatPotions = {
    212263, 212264, 212265,         -- The War Within: Tempered Potions
    241288, 241289,                 -- Midnight: Potion of Recklessness
    241292, 241293,                 -- Midnight: Draught of Rampant Abandon
    241296, 241297,                 -- Midnight: Potion of Zealotry
    241308, 241309,                 -- Midnight: Light's Potential
    245897, 245898,                 -- Midnight: Fleeting Light's Potential
    245900, 245901,                 -- Midnight: Fleeting Potion of Zealotry
    245902, 245903,                 -- Midnight: Fleeting Potion of Recklessness
}

-- ── Helper functions ─────────────────────────────────────────

-- True when a carried potion is off cooldown, false when none is, nil when
-- cooldown reads are secret-restricted (M+/raid/PvP) so the factory keeps
-- the current display state instead of comparing secret values.
local function ScanPotions()
    for _, itemID in ipairs(combatPotions) do
        local count = C_Item.GetItemCount(itemID)
        if addon:IsSecretValue(count) then return nil end
        if count and count > 0 then
            local start, duration = C_Container.GetItemCooldown(itemID)
            if addon:IsSecretValue(start) or addon:IsSecretValue(duration) then return nil end
            if start == 0 then return true end
        end
    end
    return false
end

-- Cooldown events rescan; everything else re-evaluates visibility.
local function RescanFilter(event)
    if event == "BAG_UPDATE_COOLDOWN" or event == "SPELL_UPDATE_COOLDOWN" then
        return "rescan"
    end
    return "evaluate"
end

-- ── Module lifecycle ─────────────────────────────────────────

local module = addon:CreateIndicatorAlert("PotionAlert", {
    dbKey = "potionAlert",
    frameName = "TFQoL_PotionAlertFrame",
    text = "Potion Ready",
    scanFn = ScanPotions,
    rescanEventFilter = RescanFilter,
    events = {
        "PLAYER_ENTERING_WORLD",
        "PLAYER_REGEN_DISABLED",
        "PLAYER_REGEN_ENABLED",
        "ENCOUNTER_END",
        "BAG_UPDATE_COOLDOWN",
        "SPELL_UPDATE_COOLDOWN",
    },
})

addon:RegisterModule("PotionAlert", module)
