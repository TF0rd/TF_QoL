-- ════════════════════════════════════════════════════════════════════════════════
-- TabHelpers — shared GUI helpers used by alert module tabs
-- ════════════════════════════════════════════════════════════════════════════════

local _, addon = ...
local GUIFrame = addon.GUIFrame

-- ── Local helpers ─────────────────────────────────────────────────────────

local function GetLSMFonts()
    return addon:GetLSMFonts()
end

local function GetLSMSounds()
    local list = { "None" }
    local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
    if LSM then
        for _, name in ipairs(LSM:List("sound")) do
            if name ~= "None" then table.insert(list, name) end
        end
    end
    return list
end

-- ════════════════════════════════════════════════════════════════════════════════
-- Part 1: Module header — enable + test-mode toggles with disabled overlay
-- ════════════════════════════════════════════════════════════════════════════════

-- Adds enable + test-mode toggles side by side (or enable alone if no test mode).
-- Also creates a dim overlay covering all content below the header card when disabled.
function GUIFrame:AddModuleHeader(card, moduleName)
    local Theme = addon.Theme
    local mod = addon.modules[moduleName]
    local scrollChild = card:GetParent()

    local function SetOverlayEnabled(overlay, enabled)
        if enabled then overlay:Hide() else overlay:Show() end
    end

    local function UpdateTitleColor(enabled)
        if card.titleText then
            local T = addon.Theme
            if enabled then
                card.titleText:SetTextColor(T.secondaryAccent[1], T.secondaryAccent[2], T.secondaryAccent[3], 1)
            else
                card.titleText:SetTextColor(T.textMuted[1], T.textMuted[2], T.textMuted[3], 1)
            end
        end
    end
    UpdateTitleColor(addon:IsModuleEnabled(moduleName))

    local enableRow = GUIFrame:CreateCheckbox(card.content, "Enable",
        addon:IsModuleEnabled(moduleName),
        function(val)
            addon:SetModuleEnabled(moduleName, val)
            if card._disableOverlay then
                SetOverlayEnabled(card._disableOverlay, val)
            end
            UpdateTitleColor(val)
        end)

    if mod and mod.SetTestMode then
        local testRow = GUIFrame:CreateCheckbox(card.content, "Test Mode",
            mod.IsTestMode and mod:IsTestMode() or false,
            function(val) if mod.SetTestMode then mod:SetTestMode(val) end end)
        testRow.label:SetTextColor(Theme.yellow[1], Theme.yellow[2], Theme.yellow[3], 1)
        local row = GUIFrame:CreateRow(card.content, 36)
        row:AddWidget(enableRow, 0.5)
        row:AddWidget(testRow, 0.5)
        card:AddRow(row, 36)
    else
        card:AddRow(enableRow, 36)
    end

    -- Overlay covers everything below this card in the scroll child
    local overlay = CreateFrame("Frame", nil, scrollChild)
    overlay:SetPoint("TOPLEFT",     card,        "BOTTOMLEFT",  0, -Theme.paddingSmall)
    overlay:SetPoint("BOTTOMRIGHT", scrollChild, "BOTTOMRIGHT", 0, 0)
    overlay:SetFrameLevel(card:GetFrameLevel() + 50)
    overlay:EnableMouse(true)

    local tex = overlay:CreateTexture(nil, "BACKGROUND")
    tex:SetAllPoints()
    tex:SetColorTexture(Theme.bgDark[1], Theme.bgDark[2], Theme.bgDark[3], 0.7)

    card._disableOverlay = overlay
    SetOverlayEnabled(overlay, addon:IsModuleEnabled(moduleName))

    return enableRow
end

-- ════════════════════════════════════════════════════════════════════════════════
-- Part 2: Font card — font size + font family side by side
-- ════════════════════════════════════════════════════════════════════════════════

function GUIFrame:AddFontCard(scrollChild, yOffset, dbKey)
    local Theme = addon.Theme
    local db = TFQoLDB[dbKey]
    local mod = addon.modules[dbKey:gsub("^%l", string.upper)]

    local card = GUIFrame:CreateCard(scrollChild, "Font", yOffset)

    local sizeRow = GUIFrame:CreateSlider(card.content, "Size", 8, 72, 1, db.fontSize,
        function(val)
            TFQoLDB[dbKey].fontSize = val
            if mod and mod.UpdateFont then mod:UpdateFont() end
        end)

    local fontRow = GUIFrame:CreateDropdown(card.content, "Family", GetLSMFonts(), db.fontFamily,
        function(val)
            TFQoLDB[dbKey].fontFamily = val
            if mod and mod.UpdateFont then mod:UpdateFont() end
        end)

    local row = GUIFrame:CreateRow(card.content, 36)
    row:AddWidget(sizeRow, 0.5)
    row:AddWidget(fontRow, 0.5)
    card:AddRow(row, 36)

    if TFQoLDB.global and TFQoLDB.global.fontFamily then
        card:AddLabel("Global font override active"):SetTextColor(
            Theme.textMuted[1], Theme.textMuted[2], Theme.textMuted[3], 1)
    end

    yOffset = yOffset + card:GetContentHeight() + Theme.paddingLarge
    return yOffset
end

-- ════════════════════════════════════════════════════════════════════════════════
-- Part 3: Position card — anchor type, 9-point anchors, and X/Y offsets
-- ════════════════════════════════════════════════════════════════════════════════

local ANCHOR_FRAME_TYPES = {
    { value = "SCREEN",   text = "Screen Center" },
    { value = "UIPARENT", text = "Screen (UIParent)" },
    { value = "FRAME",    text = "Select Frame" },
}

local ANCHOR_POINTS = {
    { value = "TOPLEFT",     text = "Top Left" },
    { value = "TOP",         text = "Top" },
    { value = "TOPRIGHT",    text = "Top Right" },
    { value = "LEFT",        text = "Left" },
    { value = "CENTER",      text = "Center" },
    { value = "RIGHT",       text = "Right" },
    { value = "BOTTOMLEFT",  text = "Bottom Left" },
    { value = "BOTTOM",      text = "Bottom" },
    { value = "BOTTOMRIGHT", text = "Bottom Right" },
}

-- Themed single-line text input (backdrop + EditBox), used for the custom frame name.
local function CreateTextInput(parent, placeholderText, value, onChange)
    local Theme = addon.Theme
    local inputRow = CreateFrame("Frame", nil, parent)
    inputRow:SetHeight(30)

    local container = CreateFrame("Frame", nil, inputRow, "BackdropTemplate")
    container:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    container:SetBackdropColor(Theme.bgLight[1], Theme.bgLight[2], Theme.bgLight[3], 1)
    container:SetBackdropBorderColor(Theme.border[1], Theme.border[2], Theme.border[3], 1)

    local editBox = CreateFrame("EditBox", nil, container)
    editBox:SetPoint("TOPLEFT", container, "TOPLEFT", 6, 0)
    editBox:SetPoint("BOTTOMRIGHT", container, "BOTTOMRIGHT", -6, 0)
    editBox:SetFontObject("GameFontNormal")
    editBox:SetTextColor(Theme.textPrimary[1], Theme.textPrimary[2], Theme.textPrimary[3], 1)
    editBox:SetJustifyH("LEFT")
    editBox:SetAutoFocus(false)
    editBox:SetText(value or "")

    local placeholder = container:CreateFontString(nil, "OVERLAY")
    placeholder:SetPoint("LEFT", container, "LEFT", 8, 0)
    placeholder:SetFontObject("GameFontNormal")
    placeholder:SetText(placeholderText or "")
    placeholder:SetTextColor(Theme.textMuted[1], Theme.textMuted[2], Theme.textMuted[3], 0.5)

    local function UpdatePlaceholder()
        if editBox:GetText() == "" then placeholder:Show() else placeholder:Hide() end
    end

    editBox:SetScript("OnEditFocusGained", function(self) self:HighlightText() placeholder:Hide() end)
    editBox:SetScript("OnEditFocusLost", function(self)
        UpdatePlaceholder()
        if onChange then onChange(self:GetText()) end
    end)
    editBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    editBox:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)

    container:SetPoint("TOPLEFT", inputRow, "TOPLEFT", 4, -3)
    container:SetPoint("TOPRIGHT", inputRow, "TOPRIGHT", -4, -3)
    container:SetHeight(24)

    inputRow.editBox = editBox
    UpdatePlaceholder()
    return inputRow
end

function GUIFrame:AddPositionCard(scrollChild, yOffset, dbKey)
    local Theme = addon.Theme
    local db = TFQoLDB[dbKey]
    local mod = addon.modules[dbKey:gsub("^%l", string.upper)]

    local function set(key, value)
        TFQoLDB[dbKey][key] = value
        if mod and mod.UpdatePosition then mod:UpdatePosition() end
    end

    local card = GUIFrame:CreateCard(scrollChild, "Position", yOffset)

    -- Anchored To (Screen / UIParent / custom frame)
    local anchorTypeRow = GUIFrame:CreateDropdown(card.content, "Anchored To", ANCHOR_FRAME_TYPES,
        db.anchorFrameType or "UIPARENT",
        function(val)
            set("anchorFrameType", val)
            GUIFrame:RefreshContent()
        end)
    card:AddRow(anchorTypeRow, 34)

    -- Custom frame name input (only shown for "Select Frame")
    if (db.anchorFrameType or "UIPARENT") == "FRAME" then
        local frameInput = CreateTextInput(card.content, "Frame Name", db.anchorFrame or "",
            function(text) set("anchorFrame", text) end)
        card:AddRow(frameInput, 30)
    end

    -- Anchor From / Anchor To (9-point pickers)
    local fromRow = GUIFrame:CreateDropdown(card.content, "Anchor From", ANCHOR_POINTS,
        db.selfPoint or "CENTER",
        function(val) set("selfPoint", val) end)
    local toRow = GUIFrame:CreateDropdown(card.content, "Anchor To", ANCHOR_POINTS,
        db.anchorPoint or "CENTER",
        function(val) set("anchorPoint", val) end)
    local anchorRow = GUIFrame:CreateRow(card.content, 34)
    anchorRow:AddWidget(fromRow, 0.5)
    anchorRow:AddWidget(toRow, 0.5)
    card:AddRow(anchorRow, 34)

    -- X/Y offsets
    local xRow = GUIFrame:CreateSlider(card.content, "Offset X", -500, 500, 1, db.posX,
        function(val) set("posX", val) end)
    local yRow = GUIFrame:CreateSlider(card.content, "Offset Y", -500, 500, 1, db.posY,
        function(val) set("posY", val) end)
    local offsetRow = GUIFrame:CreateRow(card.content, 36)
    offsetRow:AddWidget(xRow, 0.5)
    offsetRow:AddWidget(yRow, 0.5)
    card:AddRow(offsetRow, 36)

    yOffset = yOffset + card:GetContentHeight() + Theme.paddingLarge
    return yOffset
end

-- ════════════════════════════════════════════════════════════════════════════════
-- Part 4: Sound card — play-sound toggle + sound name dropdown
-- ════════════════════════════════════════════════════════════════════════════════

function GUIFrame:AddSoundCard(scrollChild, yOffset, dbKey)
    local Theme = addon.Theme
    local db = TFQoLDB[dbKey]

    local card = GUIFrame:CreateCard(scrollChild, "Sound", yOffset)

    local soundToggleRow = GUIFrame:CreateCheckbox(card.content, "Play Sound on Alert",
        db.playSound == true,
        function(val) TFQoLDB[dbKey].playSound = val end)
    card:AddRow(soundToggleRow, 36)

    local soundRow = GUIFrame:CreateDropdown(card.content, "Sound File", GetLSMSounds(), db.soundName or "None",
        function(val)
            TFQoLDB[dbKey].soundName = val
            if val ~= "None" then
                local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
                if LSM then
                    local path = LSM:Fetch("sound", val)
                    if path then PlaySoundFile(path, "Master") end
                end
            end
        end)
    card:AddRow(soundRow, 34)

    yOffset = yOffset + card:GetContentHeight() + Theme.paddingLarge
    return yOffset, card
end

-- ════════════════════════════════════════════════════════════════════════════════
-- Part 5: Visibility card — instance/combat visibility toggles in 2-column layout
-- ════════════════════════════════════════════════════════════════════════════════

function GUIFrame:AddVisibilityCard(scrollChild, yOffset, dbKey)
    local Theme = addon.Theme
    local db = TFQoLDB[dbKey]

    local function ForceCheck()
        local modName = dbKey:gsub("^%l", string.upper)
        local mod = addon.modules[modName]
        if mod and mod.ForceCheck then mod:ForceCheck() end
    end

    local card = GUIFrame:CreateCard(scrollChild, "Visibility", yOffset)

    local function MakeCheck(label, key)
        return GUIFrame:CreateCheckbox(card.content, label, db[key] == true,
            function(val) TFQoLDB[dbKey][key] = val; ForceCheck() end)
    end

    -- Row 1: Dungeons | Raids
    local dungeonCheck = MakeCheck("Dungeons",      "showInDungeons")
    local raidCheck    = MakeCheck("Raids",         "showInRaids")
    local row1 = GUIFrame:CreateRow(card.content, 36)
    row1:AddWidget(dungeonCheck, 0.5)
    row1:AddWidget(raidCheck, 0.5)
    card:AddRow(row1, 36)

    -- Row 2: Open World | Only in Combat
    local openWorldCheck = MakeCheck("Open World",    "showInOpenWorld")
    local combatCheck    = MakeCheck("Only in Combat","onlyCombat")
    local row2 = GUIFrame:CreateRow(card.content, 36)
    row2:AddWidget(openWorldCheck, 0.5)
    row2:AddWidget(combatCheck, 0.5)
    card:AddRow(row2, 36)

    yOffset = yOffset + card:GetContentHeight() + Theme.paddingLarge
    return yOffset
end