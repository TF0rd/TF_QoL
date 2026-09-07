local _, addon = ...
local GUIFrame = addon.GUIFrame

GUIFrame:RegisterContent("BlizzardFrames", function(scrollChild, yOffset)
    local Theme = addon.Theme
    local mod = addon.modules["BlizzardFrames"]
    local db = TFQoLDB.blizzardFrames

    -- About
    yOffset = GUIFrame:AddAboutCard(scrollChild, yOffset, "About",
        "Hide Blizzard UI elements and reposition panel frames via click+drag. Drag overlays pass clicks through to the frame underneath — panels work normally while movable. CTRL+Scroll on a title bar to rescale, middle-click to reset.")

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

    local resetBtn = GUIFrame:AddActionButton(moverCard.content, "Reset All Positions", function()
        if mod then mod:ResetAllPositions() end
    end, 30)
    moverCard:AddRow(resetBtn, 30)

    moverCard:AddSpacing(2)
    moverCard:AddLabel("Restores all panels to their default positions and scales.")

    yOffset = yOffset + moverCard:GetContentHeight() + Theme.paddingLarge

    return yOffset
end)