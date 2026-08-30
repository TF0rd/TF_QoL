-- ════════════════════════════════════════════════════════════════
-- Tab: MountActions Settings
-- Keybind display + button to open WoW Key Bindings panel.
-- ════════════════════════════════════════════════════════════════

local _, addon = ...
local GUIFrame = addon.GUIFrame

local function FormatKeyForDisplay(key)
    if not key or key == "" then return "|cffF9E2AFNot Bound|r" end
    return key:gsub("-", "+")
end

GUIFrame:RegisterContent("MountActions", function(scrollChild, yOffset)
    local Theme = addon.Theme
    local module = addon.modules["MountActions"]
    local db = addon.db and addon.db.mountActions

    -- ── Module Header (enable toggle + overlay) ──────────────────

    local card = GUIFrame:CreateCard(scrollChild, "Mount Actions", yOffset)
    GUIFrame:AddModuleHeader(card, "MountActions")
    card:AddLabel("Bind keys to summon your Repair or Auction House mount.")
    yOffset = yOffset + card:GetContentHeight() + Theme.paddingLarge

    -- ── Keybinds (read-only display + Open Keybindings button) ───

    local kbCard = GUIFrame:CreateCard(scrollChild, "Keybinds", yOffset)

    -- Repair mount display
    local repairLabel = kbCard:AddLabel("Repair Mount: " .. FormatKeyForDisplay(module and module:GetRepairKey()))
    repairLabel:SetTextColor(Theme.textPrimary[1], Theme.textPrimary[2], Theme.textPrimary[3], 1)

    -- AH mount display
    local ahLabel = kbCard:AddLabel("Auction House Mount: " .. FormatKeyForDisplay(module and module:GetAHKey()))
    ahLabel:SetTextColor(Theme.textPrimary[1], Theme.textPrimary[2], Theme.textPrimary[3], 1)

    -- Open Keybindings button
    local openBtn = CreateFrame("Button", nil, kbCard.content, "BackdropTemplate")
    openBtn:SetHeight(28)
    openBtn:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    openBtn:SetBackdropColor(Theme.bgLight[1], Theme.bgLight[2], Theme.bgLight[3], 1)
    openBtn:SetBackdropBorderColor(Theme.border[1], Theme.border[2], Theme.border[3], 1)
    local btnText = openBtn:CreateFontString(nil, "OVERLAY")
    btnText:SetPoint("CENTER")
    addon:ApplyThemeFont(btnText, "small")
    btnText:SetText("Open Keybindings Settings")
    btnText:SetTextColor(Theme.accent[1], Theme.accent[2], Theme.accent[3], 1)
    openBtn:SetScript("OnEnter", function(self)
        self:SetBackdropBorderColor(Theme.accent[1], Theme.accent[2], Theme.accent[3], 1)
    end)
    openBtn:SetScript("OnLeave", function(self)
        self:SetBackdropBorderColor(Theme.border[1], Theme.border[2], Theme.border[3], 1)
    end)
    openBtn:SetScript("OnClick", function()
        if Settings and Settings.OpenToCategory and Settings.KEYBINDINGS_CATEGORY_ID then
            Settings.OpenToCategory(Settings.KEYBINDINGS_CATEGORY_ID, BINDING_HEADER_TFQoL)
        end
    end)
    kbCard:AddRow(openBtn, 28)

    kbCard:AddLabel("Set keybinds in WoW's Key Bindings panel (ESC > Options > Keybindings).")
    yOffset = yOffset + kbCard:GetContentHeight() + Theme.paddingLarge

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