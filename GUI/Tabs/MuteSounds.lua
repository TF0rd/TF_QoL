-- ════════════════════════════════════════════════════════════════════════════════
-- MuteSounds tab — mute preset game sounds and custom sound IDs
-- ════════════════════════════════════════════════════════════════════════════════

local _, addon = ...
local GUIFrame = addon.GUIFrame

GUIFrame:RegisterContent("MuteSounds", function(scrollChild, yOffset)
    local Theme = addon.Theme
    local mod = addon.modules["MuteSounds"]

    -- ── About card ──────────────────────────────────────────────────

    yOffset = GUIFrame:AddAboutCard(scrollChild, yOffset, "About",
        "Mute specific game sounds by sound file ID. Toggle preset categories or add custom sound IDs to mute. Changes apply immediately.")

    -- ── Module header (enable/disable toggle) ──────────────────────

    local headerCard = GUIFrame:CreateCard(scrollChild, "Mute Sounds", yOffset)
    GUIFrame:AddModuleHeader(headerCard, "MuteSounds")
    yOffset = yOffset + headerCard:GetContentHeight() + Theme.paddingLarge

    -- Bail out if the module table is unavailable (options below need it)
    if not mod or not mod.SoundCategories then
        local warnCard = GUIFrame:CreateCard(scrollChild, "Sounds", yOffset)
        warnCard:AddLabel("MuteSounds module is not loaded.")
        yOffset = yOffset + warnCard:GetContentHeight() + Theme.paddingLarge
        return yOffset
    end

    -- ── Preset sound categories ────────────────────────────────────
    -- Each category gets its own card with 3-column checkbox layout.

    local categoryOrder = { "mounts", "trinkets", "emotes" }
    local categoryLabels = {
        mounts = "Mounts",
        trinkets = "Trinkets",
        emotes = "Emotes",
    }

    for _, catName in ipairs(categoryOrder) do
        local entries = mod.SoundCategories[catName]
        if entries then
            local catCard = GUIFrame:CreateCard(scrollChild, categoryLabels[catName], yOffset)

            -- 3-column layout: pack checkboxes into rows of 3
            local colCount = 0
            local currentRow = nil
            local rowHeight = 36
            local rowWidgets = {}

            for _, entry in ipairs(entries) do
                if colCount == 0 then
                    currentRow = GUIFrame:CreateRow(catCard.content, rowHeight)
                    rowWidgets[#rowWidgets + 1] = currentRow
                end
                colCount = colCount + 1

                local isChecked = mod:IsEntryMuted(catName, entry.key)
                local checkRow = GUIFrame:CreateCheckbox(currentRow, entry.label,
                    isChecked,
                    function(val)
                        mod:SetEntryMuted(catName, entry.key, val)
                    end)
                currentRow:AddWidget(checkRow, 1 / 3)

                if colCount == 3 then
                    catCard:AddRow(currentRow, rowHeight)
                    colCount = 0
                    currentRow = nil
                end
            end

            -- Handle leftover partial row
            if currentRow then
                -- Fill remaining columns with empty frames for consistent spacing
                while colCount < 3 do
                    local spacer = CreateFrame("Frame", nil, currentRow)
                    spacer:SetHeight(rowHeight)
                    currentRow:AddWidget(spacer, 1 / 3)
                    colCount = colCount + 1
                end
                catCard:AddRow(currentRow, rowHeight)
            end

            yOffset = yOffset + catCard:GetContentHeight() + Theme.paddingLarge
        end
    end

    -- ── Custom sounds card ─────────────────────────────────────────
    -- Input box for adding custom sound IDs + list of custom sounds with remove buttons

    local customCard = GUIFrame:CreateCard(scrollChild, "Custom Sounds", yOffset)
    customCard:AddLabel("Add custom sound file IDs to mute. Enter a numeric sound ID and click Add.")

    local function doAdd(inputBox)
        local text = inputBox:GetText():gsub("%s", "")
        local soundId = tonumber(text)
        if soundId and soundId > 0 then
            if mod:AddCustomSound(soundId) then
                inputBox:SetText("")
                inputBox:ClearFocus()
                GUIFrame:RefreshContent()
            end
        end
    end

    -- ── Input row: backdrop frame + EditBox inside + Add button ──
    -- Manual layout with 4px left padding (matches Slider pattern)

    local inputHeight = 30
    local inputRow = CreateFrame("Frame", nil, customCard.content)
    inputRow:SetHeight(inputHeight)

    -- Backdrop container for the EditBox (Slider pattern)
    local inputContainer = CreateFrame("Frame", nil, inputRow, "BackdropTemplate")
    inputContainer:SetHeight(24)
    inputContainer:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    inputContainer:SetBackdropColor(Theme.bgLight[1], Theme.bgLight[2], Theme.bgLight[3], 1)
    inputContainer:SetBackdropBorderColor(Theme.border[1], Theme.border[2], Theme.border[3], 1)

    local inputBox = CreateFrame("EditBox", nil, inputContainer)
    inputBox:SetPoint("TOPLEFT", inputContainer, "TOPLEFT", 4, 0)
    inputBox:SetPoint("BOTTOMRIGHT", inputContainer, "BOTTOMRIGHT", -4, 0)
    inputBox:SetFontObject("GameFontNormal")
    inputBox:SetTextColor(Theme.textPrimary[1], Theme.textPrimary[2], Theme.textPrimary[3], 1)
    inputBox:SetJustifyH("LEFT")
    inputBox:SetAutoFocus(false)
    inputBox:SetMaxLetters(12)
    inputBox:SetNumeric(true)

    local placeholder = inputContainer:CreateFontString(nil, "OVERLAY")
    placeholder:SetPoint("LEFT", inputContainer, "LEFT", 6, 0)
    placeholder:SetFontObject("GameFontNormal")
    placeholder:SetText("Sound ID")
    placeholder:SetTextColor(Theme.textMuted[1], Theme.textMuted[2], Theme.textMuted[3], 0.5)

    inputBox:SetScript("OnEditFocusGained", function(self)
        self:HighlightText()
        placeholder:Hide()
    end)
    inputBox:SetScript("OnEditFocusLost", function(self)
        if self:GetText() == "" then
            placeholder:Show()
        end
    end)
    inputBox:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
    end)
    inputBox:SetScript("OnEnterPressed", function(self)
        doAdd(self)
    end)

    local addBtn = GUIFrame:AddActionButton(inputRow, "Add", function()
        doAdd(inputBox)
    end, 28)

    -- Manual layout: 4px left padding, input 65%, 4px gap, button 35% - 4px right padding
    inputContainer:SetPoint("TOPLEFT", inputRow, "TOPLEFT", 4, -3)
    addBtn:SetPoint("TOPLEFT", inputContainer, "TOPRIGHT", 4, -2)
    addBtn:SetPoint("TOPRIGHT", inputRow, "TOPRIGHT", -4, -1)

    customCard:AddRow(inputRow, inputHeight)
    customCard:AddSpacing(4)

    -- Custom sound list
    local customSounds = mod:GetCustomSounds()
    if #customSounds > 0 then
        customCard:AddLabel("Muted custom sound IDs:")
        for _, soundId in ipairs(customSounds) do
            local idLabel = customCard.content:CreateFontString(nil, "OVERLAY")
            addon:ApplyThemeFont(idLabel, "normal")
            idLabel:SetText(tostring(soundId))
            idLabel:SetTextColor(Theme.textPrimary[1], Theme.textPrimary[2], Theme.textPrimary[3], 1)
            idLabel:SetJustifyH("LEFT")

            local removeBtn = GUIFrame:AddActionButton(customCard.content, "Remove", function()
                mod:RemoveCustomSound(soundId)
                GUIFrame:RefreshContent()
            end, 22)

            local row = GUIFrame:CreateRow(customCard.content, 24)
            row:AddWidget(idLabel, 0.65)
            row:AddWidget(removeBtn, 0.35)
            customCard:AddRow(row, 28)
        end
    else
        customCard:AddLabel("No custom sounds added.")
    end

    yOffset = yOffset + customCard:GetContentHeight() + Theme.paddingLarge

    return yOffset
end)
