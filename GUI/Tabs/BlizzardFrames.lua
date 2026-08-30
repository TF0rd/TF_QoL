local _, addon = ...
local GUIFrame = addon.GUIFrame

-- Reusable button helper (not in TabHelpers because it's specific to this module)
local function CreateActionButton(parent, text, onClick)
    local Theme = addon.Theme
    local btn = CreateFrame("Button", nil, parent, "BackdropTemplate")
    btn:SetHeight(30)
    btn:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    btn:SetBackdropColor(Theme.accent[1] * 0.3, Theme.accent[2] * 0.3, Theme.accent[3] * 0.3, 1)
    btn:SetBackdropBorderColor(Theme.accent[1], Theme.accent[2], Theme.accent[3], 1)
    btn:EnableMouse(true)
    btn:RegisterForClicks("LeftButtonUp")

    local label = btn:CreateFontString(nil, "OVERLAY")
    label:SetPoint("CENTER")
    addon:ApplyThemeFont(label, "small")
    label:SetText(text)
    label:SetTextColor(Theme.accent[1], Theme.accent[2], Theme.accent[3], 1)

    btn:SetScript("OnEnter", function(self)
        self:SetBackdropColor(Theme.accent[1] * 0.5, Theme.accent[2] * 0.5, Theme.accent[3] * 0.5, 1)
        label:SetTextColor(1, 1, 1, 1)
    end)
    btn:SetScript("OnLeave", function(self)
        self:SetBackdropColor(Theme.accent[1] * 0.3, Theme.accent[2] * 0.3, Theme.accent[3] * 0.3, 1)
        label:SetTextColor(Theme.accent[1], Theme.accent[2], Theme.accent[3], 1)
    end)
    btn:SetScript("OnClick", function()
        if onClick then onClick() end
    end)

    return btn
end

GUIFrame:RegisterContent("BlizzardFrames", function(scrollChild, yOffset)
    local Theme = addon.Theme
    local mod = addon.modules["BlizzardFrames"]
    local db = TFQoLDB.blizzardFrames

    -- About
    local aboutCard = GUIFrame:CreateCard(scrollChild, "About", yOffset)
    aboutCard:AddLabel("Hide Blizzard UI elements and reposition panel frames via click+drag. Drag overlays pass clicks through to the frame underneath — panels work normally while movable. CTRL+Scroll on a title bar to rescale, middle-click to reset.")
    yOffset = yOffset + aboutCard:GetContentHeight() + Theme.paddingLarge

    -- Enable / module header
    local card = GUIFrame:CreateCard(scrollChild, "Blizzard Frames", yOffset)
    GUIFrame:AddModuleHeader(card, "BlizzardFrames")
    yOffset = yOffset + card:GetContentHeight() + Theme.paddingLarge

    -- ── Element hiding ──────────────────────────────────────────

    local elemCard = GUIFrame:CreateCard(scrollChild, "Elements to Hide", yOffset)

    local microRow = GUIFrame:CreateCheckbox(elemCard.content, "Micro Menu",
        db.hideMicroMenu ~= false,
        function(val)
            db.hideMicroMenu = val
            if mod then mod:UpdateElements() end
        end)
    elemCard:AddRow(microRow, 36)

    local bagsRow = GUIFrame:CreateCheckbox(elemCard.content, "Bag Bar",
        db.hideBagsBar ~= false,
        function(val)
            db.hideBagsBar = val
            if mod then mod:UpdateElements() end
        end)
    elemCard:AddRow(bagsRow, 36)

    elemCard:AddLabel("Hidden while the module is enabled.")
    yOffset = yOffset + elemCard:GetContentHeight() + Theme.paddingLarge

    -- ── Frame Mover ─────────────────────────────────────────────

    local moverCard = GUIFrame:CreateCard(scrollChild, "Frame Mover", yOffset)

    local enableRow = GUIFrame:CreateCheckbox(moverCard.content, "Enable Frame Mover",
        db.moverEnabled == true,
        function(val)
            db.moverEnabled = val
            if mod then mod:RefreshMover() end
        end)
    moverCard:AddRow(enableRow, 36)

    moverCard:AddLabel("Click and drag any Blizzard panel to reposition it.\nPositions and scales are saved between sessions. Panels remain fully functional while movable.")
    moverCard:AddSpacing(4)
    moverCard:AddLabel("CTRL + Scroll on a panel's title bar to rescale it (0.5x–2.0x).\nMiddle-click a panel's title bar to reset its position and scale.")
    moverCard:AddSpacing(6)

    local resetBtn = CreateActionButton(moverCard.content, "Reset All Positions", function()
        if mod then mod:ResetAllPositions() end
    end)
    moverCard:AddRow(resetBtn, 30)

    moverCard:AddSpacing(2)
    moverCard:AddLabel("Restores all panels to their default positions and scales.")

    yOffset = yOffset + moverCard:GetContentHeight() + Theme.paddingLarge

    return yOffset
end)