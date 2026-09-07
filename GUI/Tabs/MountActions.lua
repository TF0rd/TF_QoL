-- ════════════════════════════════════════════════════════════════
-- Tab: MountActions Settings
-- Keybind display + button to open WoW Key Bindings panel.
-- ════════════════════════════════════════════════════════════════

local _, addon = ...
local GUIFrame = addon.GUIFrame

GUIFrame:RegisterContent("MountActions", function(scrollChild, yOffset)
    local Theme = addon.Theme
    local module = addon.modules["MountActions"]
    local db = TFQoLDB.mountActions

    -- ── Module Header (enable toggle + overlay) ──────────────────

    local card = GUIFrame:CreateCard(scrollChild, "Mount Actions", yOffset)
    GUIFrame:AddModuleHeader(card, "MountActions")
    card:AddLabel("Bind keys to summon your Repair or Auction House mount.")
    yOffset = yOffset + card:GetContentHeight() + Theme.paddingLarge

    -- ── Keybinds (read-only display + Open Keybindings button) ───

    yOffset = GUIFrame:AddKeybindCard(scrollChild, yOffset, "Keybinds", {
        { label = "Repair Mount",        key = module and module:GetRepairKey() },
        { label = "Auction House Mount", key = module and module:GetAHKey() },
    })

    -- ── Options ─────────────────────────────────────────────────

    if db then
        local optCard = GUIFrame:CreateCard(scrollChild, "Options", yOffset)

        local visageToggle = GUIFrame:CreateCheckbox(optCard.content, "Dracthyr: Switch to Visage before mounting", db.dracthyrVisage or false, function(val)
            db.dracthyrVisage = val
        end)
        optCard:AddRow(visageToggle, 28)

        yOffset = yOffset + optCard:GetContentHeight() + Theme.paddingLarge
    end

    return yOffset
end)
