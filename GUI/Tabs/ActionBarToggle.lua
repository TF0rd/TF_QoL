local _, addon = ...
local GUIFrame = addon.GUIFrame

local BAR_LABELS = {
    { key = "Bar1", label = "Action Bar 1" },
    { key = "Bar2", label = "Action Bar 2" },
    { key = "Bar3", label = "Action Bar 3" },
    { key = "Bar4", label = "Action Bar 4" },
    { key = "Bar5", label = "Action Bar 5" },
    { key = "Bar6", label = "Action Bar 6" },
    { key = "Bar7", label = "Action Bar 7" },
    { key = "Bar8", label = "Action Bar 8" },
}

-- Classes that permanently have a pet action bar
local PET_BAR_CLASSES = {
    HUNTER = true,
    WARLOCK = true,
    DEATHKNIGHT = true,
}

GUIFrame:RegisterContent("ActionBarToggle", function(scrollChild, yOffset)
    local Theme = addon.Theme
    local mod = addon.modules["ActionBarToggle"]
    local db = TFQoLDB.actionBarToggle

    -- About
    yOffset = GUIFrame:AddAboutCard(scrollChild, yOffset, "About",
        "Toggle visibility of action bars with a keybind. Great for screenshots, cinematics, or a cleaner UI.")

    -- Enable / module header
    local card = GUIFrame:CreateCard(scrollChild, "Action Bar Toggle", yOffset)
    GUIFrame:AddModuleHeader(card, "ActionBarToggle")
    yOffset = yOffset + card:GetContentHeight() + Theme.paddingLarge

    -- Keybind (read-only display + button to open WoW Key Bindings)
    local currentKey = mod and mod:GetCurrentKey() or db.keybind or ""
    yOffset = GUIFrame:AddKeybindCard(scrollChild, yOffset, "Keybind",
        { { label = "Toggle Key", key = currentKey } })

    -- Bar selection (2-column grid)
    local barCard = GUIFrame:CreateCard(scrollChild, "Bars to Toggle", yOffset)

    for i = 1, #BAR_LABELS, 2 do
        local left = BAR_LABELS[i]
        local right = BAR_LABELS[i + 1]

        local leftCheck = GUIFrame:CreateCheckbox(barCard.content, left.label,
            db.bars and db.bars[left.key] ~= false,
            function(val)
                if not db.bars then db.bars = {} end
                db.bars[left.key] = val
                if mod then mod:UpdateBars() end
            end)

        if right then
            local rightCheck = GUIFrame:CreateCheckbox(barCard.content, right.label,
                db.bars and db.bars[right.key] ~= false,
                function(val)
                    if not db.bars then db.bars = {} end
                    db.bars[right.key] = val
                    if mod then mod:UpdateBars() end
                end)
            local row = GUIFrame:CreateRow(barCard.content, 36)
            row:AddWidget(leftCheck, 0.5)
            row:AddWidget(rightCheck, 0.5)
            barCard:AddRow(row, 36)
        else
            barCard:AddRow(leftCheck, 36)
        end
    end

    yOffset = yOffset + barCard:GetContentHeight() + Theme.paddingLarge

    -- Additional bars (pet / stance) -- only show for relevant classes
    local _, playerClass = UnitClass("player")
    local showPetBar = PET_BAR_CLASSES[playerClass] == true
    local showStanceBar = GetNumShapeshiftForms() > 0

    if showPetBar or showStanceBar then
        local optCard = GUIFrame:CreateCard(scrollChild, "Additional Bars", yOffset)

        if showPetBar then
            local petRow = GUIFrame:CreateCheckbox(optCard.content, "Include Pet Bar",
                db.includePetBar == true,
                function(val)
                    db.includePetBar = val
                    if mod then mod:UpdateBars() end
                end)
            optCard:AddRow(petRow, 36)
        end

        if showStanceBar then
            local stanceRow = GUIFrame:CreateCheckbox(optCard.content, "Include Stance Bar",
                db.includeStanceBar == true,
                function(val)
                    db.includeStanceBar = val
                    if mod then mod:UpdateBars() end
                end)
            optCard:AddRow(stanceRow, 36)
        end

        yOffset = yOffset + optCard:GetContentHeight() + Theme.paddingLarge
    end

    return yOffset
end)