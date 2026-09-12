-- ════════════════════════════════════════════════════════════════
-- Tab: ConsumableMacros Settings ("Macros")
-- Toggle and configure Health Potion, Drink, and Power Infusion macros.
-- Right column shows live macro composition (icon / name / count).
-- ════════════════════════════════════════════════════════════════

local _, addon = ...
local GUIFrame = addon.GUIFrame

local MAX_PREVIEW_ROWS = 3
local PREVIEW_ROW_H = 24
local PREVIEW_GAP = 2
local MORE_LABEL_H = 18
local QUESTION_MARK = "Interface\\Icons\\INV_Misc_QuestionMark"

local function CreateMacroPreviewPanel(parent, title)
    local Theme = addon.Theme
    local panel = CreateFrame("Frame", nil, parent)
    panel:SetHeight(PREVIEW_ROW_H * MAX_PREVIEW_ROWS + PREVIEW_GAP * (MAX_PREVIEW_ROWS - 1) + MORE_LABEL_H + 20)

    local header = panel:CreateFontString(nil, "OVERLAY")
    header:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, 0)
    header:SetPoint("TOPRIGHT", panel, "TOPRIGHT", 0, 0)
    header:SetJustifyH("LEFT")
    addon:ApplyThemeFont(header, "small")
    header:SetText(title or "Current Macro")
    header:SetTextColor(Theme.secondaryAccent[1], Theme.secondaryAccent[2], Theme.secondaryAccent[3], 1)

    local emptyLabel = panel:CreateFontString(nil, "OVERLAY")
    emptyLabel:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -8)
    emptyLabel:SetPoint("TOPRIGHT", header, "BOTTOMRIGHT", 0, -8)
    emptyLabel:SetJustifyH("LEFT")
    addon:ApplyThemeFont(emptyLabel, "small")
    emptyLabel:SetText("No items in macro")
    emptyLabel:SetTextColor(Theme.textMuted[1], Theme.textMuted[2], Theme.textMuted[3], 1)

    local moreLabel = panel:CreateFontString(nil, "OVERLAY")
    moreLabel:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, -(PREVIEW_ROW_H * MAX_PREVIEW_ROWS + PREVIEW_GAP * MAX_PREVIEW_ROWS + 2))
    moreLabel:SetPoint("TOPRIGHT", panel, "TOPRIGHT", 0, -(PREVIEW_ROW_H * MAX_PREVIEW_ROWS + PREVIEW_GAP * MAX_PREVIEW_ROWS + 2))
    moreLabel:SetJustifyH("LEFT")
    addon:ApplyThemeFont(moreLabel, "small")
    moreLabel:SetTextColor(Theme.textMuted[1], Theme.textMuted[2], Theme.textMuted[3], 1)
    moreLabel:Hide()

    local rows = {}
    for i = 1, MAX_PREVIEW_ROWS do
        local row = CreateFrame("Button", nil, panel)
        row:SetHeight(PREVIEW_ROW_H)
        row:EnableMouse(true)
        row:RegisterForClicks()
        if i == 1 then
            row:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -6)
            row:SetPoint("TOPRIGHT", header, "BOTTOMRIGHT", 0, -6)
        else
            row:SetPoint("TOPLEFT", rows[i - 1], "BOTTOMLEFT", 0, -PREVIEW_GAP)
            row:SetPoint("TOPRIGHT", rows[i - 1], "BOTTOMRIGHT", 0, -PREVIEW_GAP)
        end

        local iconBorder = CreateFrame("Frame", nil, row, "BackdropTemplate")
        iconBorder:SetSize(PREVIEW_ROW_H - 4, PREVIEW_ROW_H - 4)
        iconBorder:SetPoint("LEFT", row, "LEFT", 0, 0)
        iconBorder:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            edgeSize = 1,
        })
        iconBorder:SetBackdropColor(Theme.bgLight[1], Theme.bgLight[2], Theme.bgLight[3], 1)
        iconBorder:SetBackdropBorderColor(Theme.border[1], Theme.border[2], Theme.border[3], 1)

        local icon = iconBorder:CreateTexture(nil, "ARTWORK")
        icon:SetPoint("TOPLEFT", iconBorder, "TOPLEFT", 1, -1)
        icon:SetPoint("BOTTOMRIGHT", iconBorder, "BOTTOMRIGHT", -1, 1)
        icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        icon:SetTexture(QUESTION_MARK)
        row.icon = icon

        local nameText = row:CreateFontString(nil, "OVERLAY")
        nameText:SetPoint("LEFT", iconBorder, "RIGHT", 8, 0)
        nameText:SetPoint("RIGHT", row, "RIGHT", -48, 0)
        nameText:SetJustifyH("LEFT")
        nameText:SetWordWrap(false)
        addon:ApplyThemeFont(nameText, "normal")
        nameText:SetTextColor(Theme.textPrimary[1], Theme.textPrimary[2], Theme.textPrimary[3], 1)
        row.nameText = nameText

        local countText = row:CreateFontString(nil, "OVERLAY")
        countText:SetPoint("RIGHT", row, "RIGHT", 0, 0)
        countText:SetJustifyH("RIGHT")
        addon:ApplyThemeFont(countText, "normal")
        countText:SetTextColor(Theme.accent[1], Theme.accent[2], Theme.accent[3], 1)
        row.countText = countText

        row:SetScript("OnEnter", function(self)
            if not self.entry then return end
            iconBorder:SetBackdropBorderColor(Theme.accent[1], Theme.accent[2], Theme.accent[3], 1)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            local ok = false
            if self.entry.isSpell then
                if GameTooltip.SetSpellByID then
                    ok = pcall(GameTooltip.SetSpellByID, GameTooltip, self.entry.id)
                end
            else
                if GameTooltip.SetItemByID then
                    ok = pcall(GameTooltip.SetItemByID, GameTooltip, self.entry.id)
                end
                if not ok and GameTooltip.SetHyperlink then
                    ok = pcall(GameTooltip.SetHyperlink, GameTooltip, "item:" .. self.entry.id)
                end
            end
            if ok then
                GameTooltip:Show()
            else
                GameTooltip:Hide()
            end
        end)
        row:SetScript("OnLeave", function()
            iconBorder:SetBackdropBorderColor(Theme.border[1], Theme.border[2], Theme.border[3], 1)
            GameTooltip:Hide()
        end)

        row:Hide()
        rows[i] = row
    end

    function panel:SetEntries(entries)
        entries = entries or {}
        local n = #entries
        if n == 0 then
            emptyLabel:Show()
            moreLabel:Hide()
            for i = 1, MAX_PREVIEW_ROWS do
                rows[i].entry = nil
                rows[i]:Hide()
            end
            return
        end

        emptyLabel:Hide()
        if n > MAX_PREVIEW_ROWS then
            moreLabel:SetText("… and " .. (n - MAX_PREVIEW_ROWS) .. " more")
            moreLabel:Show()
        else
            moreLabel:Hide()
        end
        for i = 1, MAX_PREVIEW_ROWS do
            local row = rows[i]
            local e = entries[i]
            if e then
                row.entry = e
                row.icon:SetTexture(e.icon or QUESTION_MARK)
                local label = e.name or "?"
                row.nameText:SetText(i .. ".  " .. label)
                if e.isSpell then
                    row.countText:SetText("")
                else
                    row.countText:SetText(tostring(e.count or 0))
                end
                row:Show()
            else
                row.entry = nil
                row:Hide()
            end
        end
    end

    return panel
end

local function CreatePIMacroEditorPanel(parent, title)
    local Theme = addon.Theme
    local panel = CreateFrame("Frame", nil, parent)
    panel:SetHeight(140)

    local header = panel:CreateFontString(nil, "OVERLAY")
    header:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, 0)
    header:SetPoint("TOPRIGHT", panel, "TOPRIGHT", 0, 0)
    header:SetJustifyH("LEFT")
    addon:ApplyThemeFont(header, "small")
    header:SetText(title or "PI Macro")
    header:SetTextColor(Theme.secondaryAccent[1], Theme.secondaryAccent[2], Theme.secondaryAccent[3], 1)

    local container = CreateFrame("Frame", nil, panel, "BackdropTemplate")
    container:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -6)
    container:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", 0, 0)
    container:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    container:SetBackdropColor(Theme.bgLight[1], Theme.bgLight[2], Theme.bgLight[3], 1)
    container:SetBackdropBorderColor(Theme.border[1], Theme.border[2], Theme.border[3], 1)

    local editBox = CreateFrame("EditBox", nil, container)
    editBox:SetPoint("TOPLEFT", container, "TOPLEFT", 6, -4)
    editBox:SetPoint("BOTTOMRIGHT", container, "BOTTOMRIGHT", -6, 4)
    editBox:SetFontObject("GameFontNormal")
    editBox:SetTextColor(Theme.textPrimary[1], Theme.textPrimary[2], Theme.textPrimary[3], 1)
    editBox:SetJustifyH("LEFT")
    editBox:SetJustifyV("TOP")
    editBox:SetMultiLine(true)
    editBox:SetAutoFocus(false)
    editBox:SetTextInsets(0, 0, 0, 0)

    local onChangeCallback
    editBox:SetScript("OnEditFocusLost", function(self)
        if onChangeCallback then onChangeCallback(self:GetText()) end
    end)
    editBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

    function panel:SetBody(text)
        if editBox:HasFocus() then return end
        editBox:SetText(text or "")
    end

    function panel:SetOnChange(cb)
        onChangeCallback = cb
    end

    function panel:SetEnabled(enabled)
        if enabled then
            panel:SetAlpha(1)
            editBox:EnableMouse(true)
            editBox:SetTextColor(Theme.textPrimary[1], Theme.textPrimary[2], Theme.textPrimary[3], 1)
        else
            editBox:ClearFocus()
            editBox:EnableMouse(false)
            editBox:SetTextColor(Theme.textMuted[1], Theme.textMuted[2], Theme.textMuted[3], 1)
            panel:SetAlpha(Theme.disabledAlpha)
        end
    end

    return panel
end

local function CreateSplitMacroCard(scrollChild, title, yOffset, buildLeft, buildRight)
    local Theme = addon.Theme
    local card = GUIFrame:CreateCard(scrollChild, title, yOffset)

    -- Single full-width host row; left controls + right preview live inside it.
    local host = CreateFrame("Frame", nil, card.content)
    host:SetHeight(1)

    local leftCol = CreateFrame("Frame", nil, host)
    leftCol:SetPoint("TOPLEFT", host, "TOPLEFT", 0, 0)
    leftCol:SetPoint("BOTTOMLEFT", host, "BOTTOMLEFT", 0, 0)
    leftCol:SetWidth(1)

    local rightCol = CreateFrame("Frame", nil, host)
    rightCol:SetPoint("TOPRIGHT", host, "TOPRIGHT", 0, 0)
    rightCol:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT", 0, 0)
    rightCol:SetWidth(1)

    local divider = host:CreateTexture(nil, "ARTWORK")
    divider:SetWidth(1)
    divider:SetColorTexture(Theme.border[1], Theme.border[2], Theme.border[3], 0.45)

    local leftY = 0
    local function addLeft(widget, height, spacing)
        height = height or widget:GetHeight() or 36
        spacing = spacing or Theme.paddingMedium
        widget:SetParent(leftCol)
        widget:ClearAllPoints()
        widget:SetPoint("TOPLEFT", leftCol, "TOPLEFT", 0, -leftY)
        widget:SetPoint("TOPRIGHT", leftCol, "TOPRIGHT", -Theme.paddingMedium, -leftY)
        leftY = leftY + height + spacing
        return widget
    end

    local function addLeftLabel(text, height)
        height = height or 40
        local label = leftCol:CreateFontString(nil, "OVERLAY")
        label:SetPoint("TOPLEFT", leftCol, "TOPLEFT", 0, -leftY)
        label:SetPoint("TOPRIGHT", leftCol, "TOPRIGHT", -Theme.paddingMedium, -leftY)
        label:SetJustifyH("LEFT")
        label:SetWordWrap(true)
        addon:ApplyThemeFont(label, "normal")
        label:SetTextColor(Theme.textMuted[1], Theme.textMuted[2], Theme.textMuted[3], 1)
        label:SetText(text)
        leftY = leftY + height + Theme.paddingSmall
        return label
    end

    local leftApi = { AddRow = function(_, w, h, s) return addLeft(w, h, s) end, AddLabel = function(_, text, h) return addLeftLabel(text, h) end, content = leftCol }
    buildLeft(leftApi, leftCol)

    local preview = buildRight(rightCol)
    preview:SetParent(rightCol)
    preview:ClearAllPoints()
    preview:SetPoint("TOPLEFT", rightCol, "TOPLEFT", Theme.paddingMedium, 0)
    preview:SetPoint("TOPRIGHT", rightCol, "TOPRIGHT", 0, 0)

    local layingOut = false
    local function layout()
        if layingOut then return end
        local w = host:GetWidth() or 0
        if w <= 1 then return end
        layingOut = true
        local leftW = math.floor(w * 0.55)
        leftCol:SetWidth(leftW)
        rightCol:SetWidth(w - leftW - 1)
        divider:ClearAllPoints()
        divider:SetPoint("TOPLEFT", host, "TOPLEFT", leftW, 0)
        divider:SetPoint("BOTTOMLEFT", host, "BOTTOMLEFT", leftW, 0)

        local h = math.max(leftY, preview:GetHeight() or 0, 1)
        if math.abs((host:GetHeight() or 0) - h) > 0.5 then
            host:SetHeight(h)
        end
        -- Host is the only card row — keep card content height in sync.
        card.currentY = h
        card.content:SetHeight(h)
        card:UpdateHeight()
        layingOut = false
    end

    local initialH = math.max(leftY, preview:GetHeight() or 0, 1)
    host:SetHeight(initialH)
    card:AddRow(host, initialH, 0)
    host:SetScript("OnSizeChanged", layout)
    C_Timer.After(0, layout)
    layout()

    return card, preview, layout
end

GUIFrame:RegisterContent("ConsumableMacros", function(scrollChild, yOffset)
    local Theme = addon.Theme
    local db = TFQoLDB.consumableMacros
    if not db then return yOffset end

    local module = addon.modules["ConsumableMacros"]

    -- Forward-declare sub-option widgets so callbacks can reference them
    local healthstoneToggle
    local preferMage
    local healthPreview, drinkPreview
    local piEditor
    local refreshHealthPreview, refreshDrinkPreview, refreshPIBody

    -- ── Module Header (enable toggle + overlay) ──────────────────

    local headerCard = GUIFrame:CreateCard(scrollChild, "Macros", yOffset)
    GUIFrame:AddModuleHeader(headerCard, "ConsumableMacros")
    headerCard:AddLabel("Auto-updating macros for Health Potions and Drinks, plus a Power Infusion target helper. Macros update when you loot, level up, or change spec.")
    yOffset = yOffset + headerCard:GetContentHeight() + Theme.paddingLarge

    -- ── Health Potion Macro Card ─────────────────────────────────

    local healthCard
    healthCard, healthPreview = CreateSplitMacroCard(
        scrollChild,
        "Health Potion Macro",
        yOffset,
        function(left)
            local healthToggle = GUIFrame:CreateCheckbox(left.content,
                "Enable Health Potion Macro (TFHealthPotion)", db.healthMacroEnabled,
                function(val)
                    db.healthMacroEnabled = val
                    healthstoneToggle:SetEnabled(val)
                    if module then
                        if val then
                            module:RefreshHealthMacro()
                        else
                            refreshHealthPreview({})
                        end
                    end
                end)
            left:AddRow(healthToggle, 36)

            healthstoneToggle = GUIFrame:CreateCheckbox(left.content,
                "Include Healthstone", db.includeHealthstone,
                function(val)
                    db.includeHealthstone = val
                    if module then module:RefreshHealthMacro() end
                end)
            left:AddRow(healthstoneToggle, 36)

            healthstoneToggle:SetEnabled(db.healthMacroEnabled)
        end,
        function(parent)
            return CreateMacroPreviewPanel(parent, "Eligible Consumable Order")
        end
    )
    yOffset = yOffset + healthCard:GetContentHeight() + Theme.paddingLarge

    -- ── Drink Macro Card ─────────────────────────────────────────

    local drinkCard
    drinkCard, drinkPreview = CreateSplitMacroCard(
        scrollChild,
        "Drink Macro",
        yOffset,
        function(left)
            local drinkToggle = GUIFrame:CreateCheckbox(left.content,
                "Enable Drink Macro (TFDrink)", db.drinkMacroEnabled,
                function(val)
                    db.drinkMacroEnabled = val
                    preferMage:SetEnabled(val)
                    if module then
                        if val then
                            module:RefreshDrinkMacro()
                        else
                            refreshDrinkPreview({})
                        end
                    end
                end)
            left:AddRow(drinkToggle, 36)

            preferMage = GUIFrame:CreateCheckbox(left.content,
                "Prefer Mage Food", db.preferMageFood,
                function(val)
                    db.preferMageFood = val
                    if module then module:RefreshDrinkMacro() end
                end)
            left:AddRow(preferMage, 36)

            preferMage:SetEnabled(db.drinkMacroEnabled)

        end,
        function(parent)
            return CreateMacroPreviewPanel(parent, "Eligible Consumable Order")
        end
    )
    yOffset = yOffset + drinkCard:GetContentHeight() + Theme.paddingLarge

    -- ── Power Infusion Macro Card ─────────────────────────────────

    local piCard
    piCard, piEditor = CreateSplitMacroCard(
        scrollChild,
        "Power Infusion Macro",
        yOffset,
        function(left)
            local piToggle = GUIFrame:CreateCheckbox(left.content,
                "Enable Power Infusion Helper (TFSetPI)", db.piMacroEnabled or false,
                function(val)
                    db.piMacroEnabled = val
                    if piEditor then piEditor:SetEnabled(val) end
                    if module then module:RefreshPIMacro() end
                end)
            left:AddRow(piToggle, 36, Theme.paddingLarge)
            left:AddLabel("Target a player and run |cff89b4fa/tf pi|r (or press TFSetPI) to bake their name into your PI macro: mouseover > that player > you. |cff89b4fa{target}|r in the body is replaced with that name.", 60)
        end,
        function(parent)
            return CreatePIMacroEditorPanel(parent, "PI Macro Body")
        end
    )
    piEditor:SetOnChange(function(text)
        if module then module:SetPIMacroBody(text) end
    end)
    piEditor:SetEnabled(db.piMacroEnabled or false)
    yOffset = yOffset + piCard:GetContentHeight() + Theme.paddingLarge

    -- ── Live preview wiring ──────────────────────────────────────

    refreshHealthPreview = function(entries)
        if healthPreview then healthPreview:SetEntries(entries) end
    end
    refreshDrinkPreview = function(entries)
        if drinkPreview then drinkPreview:SetEntries(entries) end
    end
    refreshPIBody = function(body)
        if piEditor then piEditor:SetBody(body or "") end
    end

    if module then
        module:RegisterHealthPreviewListener("gui", refreshHealthPreview)
        module:RegisterDrinkPreviewListener("gui", refreshDrinkPreview)
        module:RegisterPIPreviewListener("gui", refreshPIBody)
    else
        refreshHealthPreview({})
        refreshDrinkPreview({})
        refreshPIBody("")
    end

    GUIFrame:RegisterContentCleanup("ConsumableMacros", function()
        if module then
            module:UnregisterHealthPreviewListener("gui")
            module:UnregisterDrinkPreviewListener("gui")
            module:UnregisterPIPreviewListener("gui")
        end
    end)

    return yOffset
end)
