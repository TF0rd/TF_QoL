-- ════════════════════════════════════════════════════════════════════════════════════
-- Widget: Dropdown (Scrollable dropdown with animations, pool, and scrollbar drag)
-- Usage: GUIFrame:CreateDropdown(parent, labelText, options, selected, callback)
-- ════════════════════════════════════════════════════════════════════════════════════

local _, addon = ...
local GUIFrame = addon.GUIFrame

local tostring = tostring
local CreateFrame = CreateFrame
local C_Timer = C_Timer
local math_max, math_min = math.max, math.min
local type = type
local table_insert, table_sort, table_remove = table.insert, table.sort, table.remove
local wipe = wipe
local IsMouseButtonDown = IsMouseButtonDown
local ipairs = ipairs
local pairs = pairs

-- ════════════════════════════════════════════════════════════════════════════════════
-- Part 1: Constants
-- ════════════════════════════════════════════════════════════════════════════════════

local DROPDOWN_HEIGHT = 24
local ITEM_HEIGHT = 24
local MAX_DROPDOWN_HEIGHT = 400
local ANIM_DURATION = 0.12
local ARROW_TEX = "Interface\\AddOns\\TF_QoL\\Media\\GUITextures\\collapse.tga"
local ARROW_SIZE = 16

local DROPDOWN_BACKDROP = { bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 }

-- ════════════════════════════════════════════════════════════════════════════════════
-- Part 2: Global Mouse-Up Detector (Closes dropdown on outside click release)
-- ════════════════════════════════════════════════════════════════════════════════════

local globalMouseChecker = CreateFrame("Frame", nil, UIParent)
globalMouseChecker:Hide()
globalMouseChecker.activeDropdown = nil
globalMouseChecker.wasMouseDown = false
globalMouseChecker:SetScript("OnUpdate", function(self)
    local row = self.activeDropdown
    if not row then self:Hide() return end
    if row._scrollHold then return end
    local isDown = IsMouseButtonDown("LeftButton")
    if self.wasMouseDown and not isDown then
        if row._dropdownList and row._dropdownButton then
            if not row._dropdownList:IsMouseOver() and not row._dropdownButton:IsMouseOver() then
                if row._closeDropdown then row._closeDropdown() end
            end
        end
    end
    self.wasMouseDown = isDown
end)

-- ════════════════════════════════════════════════════════════════════════════════════
-- Part 3: Item Button Pool (Acquire/Release helpers for dropdown option buttons)
-- ════════════════════════════════════════════════════════════════════════════════════

local itemButtonPool = {}

local function AcquireItemButton(parent)
    local btn = table_remove(itemButtonPool)
    if btn then btn:SetParent(parent) btn:Show() return btn end
    local Theme = addon.Theme
    btn = CreateFrame("Button", nil, parent)
    btn:SetHeight(ITEM_HEIGHT)
    local hoverBg = btn:CreateTexture(nil, "BACKGROUND")
    hoverBg:SetAllPoints()
    hoverBg:SetColorTexture(Theme.accentHover[1], Theme.accentHover[2], Theme.accentHover[3], Theme.accentHover[4] or 0.25)
    hoverBg:Hide()
    btn._hoverBg = hoverBg
    local btnText = btn:CreateFontString(nil, "OVERLAY")
    btnText:SetPoint("LEFT", btn, "LEFT", 8, 0)
    btnText:SetPoint("RIGHT", btn, "RIGHT", -8, 0)
    btnText:SetJustifyH("LEFT")
    addon:ApplyThemeFont(btnText, "normal")
    btn._text = btnText
    return btn
end

local function ReleaseItemButton(btn)
    btn:Hide()
    btn:SetParent(nil)
    btn:SetScript("OnClick", nil)
    btn:SetScript("OnEnter", nil)
    btn:SetScript("OnLeave", nil)
    btn._hoverBg:Hide()
    btn._itemValue = nil
    btn._itemText = nil
    btn._updateColor = nil
    table_insert(itemButtonPool, btn)
end

-- ════════════════════════════════════════════════════════════════════════════════════
-- Part 4: CreateDropdown (Main factory — row, label, button, list, scrollbar, anims)
-- ════════════════════════════════════════════════════════════════════════════════════

function GUIFrame:CreateDropdown(parent, labelText, options, selected, callback)
    local Theme = addon.Theme

    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(34)

    -- ── Label ───────────────────────────────────────────────────────────────────────

    local label = row:CreateFontString(nil, "OVERLAY")
    label:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 1)
    label:SetJustifyH("LEFT")
    addon:ApplyThemeFont(label, "small")
    label:SetText(labelText or "")
    label:SetTextColor(Theme.textMuted[1], Theme.textMuted[2], Theme.textMuted[3], 1)
    row.label = label

    -- ── Dropdown Button ─────────────────────────────────────────────────────────────

    local dropdownButton = CreateFrame("Button", nil, row, "BackdropTemplate")
    dropdownButton:SetHeight(DROPDOWN_HEIGHT)
    dropdownButton:SetPoint("TOPLEFT",  row, "TOPLEFT",  0, -14)
    dropdownButton:SetPoint("TOPRIGHT", row, "TOPRIGHT", 0, -14)
    dropdownButton:SetBackdrop(DROPDOWN_BACKDROP)
    dropdownButton:SetBackdropColor(Theme.bgLight[1], Theme.bgLight[2], Theme.bgLight[3], 1)
    dropdownButton:SetBackdropBorderColor(Theme.border[1], Theme.border[2], Theme.border[3], 1)

    local selectedText = dropdownButton:CreateFontString(nil, "OVERLAY")
    selectedText:SetPoint("LEFT",  dropdownButton, "LEFT",  Theme.paddingSmall, 0)
    selectedText:SetPoint("RIGHT", dropdownButton, "RIGHT", -24, 0)
    selectedText:SetJustifyH("LEFT")
    addon:ApplyThemeFont(selectedText, "normal")
    selectedText:SetTextColor(Theme.textPrimary[1], Theme.textPrimary[2], Theme.textPrimary[3], 1)
    dropdownButton.selectedText = selectedText

    local arrow = dropdownButton:CreateTexture(nil, "ARTWORK")
    arrow:SetSize(ARROW_SIZE, ARROW_SIZE)
    arrow:SetPoint("RIGHT", dropdownButton, "RIGHT", -Theme.paddingSmall, 0)
    arrow:SetTexture(ARROW_TEX)
    arrow:SetVertexColor(Theme.accent[1], Theme.accent[2], Theme.accent[3], 1)
    arrow:SetRotation(-math.pi / 2)

    -- ── Normalize Options ───────────────────────────────────────────────────────────

    local normalizedOptions = {}
    local orderedKeys = nil
    if type(options) == "table" then
        if options[1] and type(options[1]) == "table" and (options[1].value or options[1].key) then
            orderedKeys = {}
            for _, opt in ipairs(options) do
                local k = opt.value or opt.key
                normalizedOptions[k] = opt.text
                table_insert(orderedKeys, k)
            end
        elseif options[1] ~= nil and type(options[1]) == "string" then
            for _, v in ipairs(options) do normalizedOptions[v] = v end
        else
            for k, v in pairs(options) do normalizedOptions[k] = v end
        end
    end

    -- ── State ───────────────────────────────────────────────────────────────────────

    local isOpen = false
    local currentValue = selected
    local itemButtons = {}
    local itemsCreated = false
    local startHeight, targetHeight = 0, 0
    local scrollHold = false

    -- ── Dropdown List Frame (floats above everything) ───────────────────────────────

    local dropdownList = CreateFrame("Frame", nil, row, "BackdropTemplate")
    dropdownList:SetHeight(1)
    dropdownList:SetBackdrop(DROPDOWN_BACKDROP)
    dropdownList:SetBackdropColor(Theme.bgLight[1], Theme.bgLight[2], Theme.bgLight[3], 1)
    dropdownList:SetBackdropBorderColor(Theme.border[1], Theme.border[2], Theme.border[3], 1)
    dropdownList:SetFrameStrata("TOOLTIP")
    dropdownList:SetClipsChildren(true)
    dropdownList:Hide()

    local scrollFrame = CreateFrame("ScrollFrame", nil, dropdownList)
    scrollFrame:SetPoint("TOPLEFT",     dropdownList, "TOPLEFT",     0, 0)
    scrollFrame:SetPoint("BOTTOMRIGHT", dropdownList, "BOTTOMRIGHT", 0, 0)
    local scrollChild = CreateFrame("Frame", nil, scrollFrame)
    scrollFrame:SetScrollChild(scrollChild)

    -- ── Custom Scrollbar ────────────────────────────────────────────────────────────

    local SCROLLBAR_WIDTH = 8
    local scrollbarTrack = dropdownList:CreateTexture(nil, "BACKGROUND")
    scrollbarTrack:SetWidth(SCROLLBAR_WIDTH)
    scrollbarTrack:SetPoint("TOPRIGHT", dropdownList, "TOPRIGHT", -2, -2)
    scrollbarTrack:SetPoint("BOTTOMRIGHT", dropdownList, "BOTTOMRIGHT", -2, 2)
    scrollbarTrack:SetColorTexture(Theme.bgDark[1], Theme.bgDark[2], Theme.bgDark[3], 0.5)
    scrollbarTrack:Hide()

    local scrollbarThumb = CreateFrame("Frame", nil, dropdownList)
    scrollbarThumb:SetWidth(SCROLLBAR_WIDTH)
    scrollbarThumb:SetFrameStrata("TOOLTIP")
    scrollbarThumb.bg = scrollbarThumb:CreateTexture(nil, "ARTWORK")
    scrollbarThumb.bg:SetAllPoints()
    scrollbarThumb.bg:SetColorTexture(Theme.accent[1], Theme.accent[2], Theme.accent[3], 0.8)
    scrollbarThumb:Hide()

    local isDraggingThumb = false
    local dragStartY, dragStartScroll

    local function UpdateScrollbar()
        local contentHeight = scrollChild:GetHeight()
        local viewHeight = scrollFrame:GetHeight()
        if contentHeight <= viewHeight or viewHeight <= 0 then
            scrollbarTrack:Hide()
            scrollbarThumb:Hide()
            scrollFrame:SetPoint("BOTTOMRIGHT", dropdownList, "BOTTOMRIGHT", 0, 0)
            return
        end
        scrollbarTrack:Show()
        scrollbarThumb:Show()
        scrollFrame:SetPoint("BOTTOMRIGHT", dropdownList, "BOTTOMRIGHT", -(SCROLLBAR_WIDTH + 4), 0)
        scrollChild:SetWidth(scrollFrame:GetWidth())

        local trackHeight = scrollbarTrack:GetHeight()
        local thumbHeight = math_max(20, (viewHeight / contentHeight) * trackHeight)
        scrollbarThumb:SetHeight(thumbHeight)

        local maxScroll = contentHeight - viewHeight
        local scroll = scrollFrame:GetVerticalScroll()
        local ratio = scroll / maxScroll
        local maxThumbOffset = trackHeight - thumbHeight
        local thumbOffset = ratio * maxThumbOffset
        scrollbarThumb:SetPoint("TOPRIGHT", dropdownList, "TOPRIGHT", -2, -(2 + thumbOffset))
    end

    -- Thumb drag tracking frame
    local thumbDragFrame = CreateFrame("Frame", nil, UIParent)
    thumbDragFrame:Hide()
    thumbDragFrame:SetScript("OnUpdate", function()
        if not isDraggingThumb then return end
        local _, cursorY = GetCursorPosition()
        cursorY = cursorY / scrollbarThumb:GetEffectiveScale()
        local trackHeight = scrollbarTrack:GetHeight()
        local thumbHeight = scrollbarThumb:GetHeight()
        local maxThumbOffset = trackHeight - thumbHeight
        local deltaY = cursorY - dragStartY
        local deltaScroll = (deltaY / maxThumbOffset) * (scrollChild:GetHeight() - scrollFrame:GetHeight())
        scrollFrame:SetVerticalScroll(math_max(0, math_min(scrollChild:GetHeight() - scrollFrame:GetHeight(), dragStartScroll - deltaScroll)))
        UpdateScrollbar()
    end)

    scrollbarThumb:SetScript("OnMouseDown", function(self, button)
        if button == "LeftButton" then
            isDraggingThumb = true
            scrollHold = true
            row._scrollHold = true
            dragStartY = select(2, GetCursorPosition()) / self:GetEffectiveScale()
            dragStartScroll = scrollFrame:GetVerticalScroll()
            self.bg:SetColorTexture(Theme.accent[1], Theme.accent[2], Theme.accent[3], 1)
            thumbDragFrame:Show()
        end
    end)
    scrollbarThumb:SetScript("OnMouseUp", function(self)
        isDraggingThumb = false
        scrollHold = false
        row._scrollHold = false
        self.bg:SetColorTexture(Theme.accent[1], Theme.accent[2], Theme.accent[3], 0.8)
        thumbDragFrame:Hide()
    end)
    scrollbarThumb:SetScript("OnHide", function(self)
        isDraggingThumb = false
        scrollHold = false
        row._scrollHold = false
        self.bg:SetColorTexture(Theme.accent[1], Theme.accent[2], Theme.accent[3], 0.8)
        thumbDragFrame:Hide()
    end)
    scrollbarThumb:EnableMouse(true)

    scrollbarTrack:SetScript("OnMouseDown", function(self, button)
        if button == "LeftButton" then
            local thumbTop = scrollbarThumb:GetTop()
            local thumbBottom = scrollbarThumb:GetBottom()
            local _, cursorY = GetCursorPosition()
            cursorY = cursorY / dropdownList:GetEffectiveScale()
            local page = scrollFrame:GetHeight() * 0.8
            if cursorY > thumbTop then
                scrollFrame:SetVerticalScroll(math_max(0, scrollFrame:GetVerticalScroll() - page))
            elseif cursorY < thumbBottom then
                scrollFrame:SetVerticalScroll(math_min(scrollChild:GetHeight() - scrollFrame:GetHeight(), scrollFrame:GetVerticalScroll() + page))
            end
        end
    end)
    scrollbarTrack:EnableMouse(true)

    scrollFrame:HookScript("OnMouseWheel", function()
        UpdateScrollbar()
    end)

    -- ── Animations (height + arrow rotation + border hover) ─────────────────────────

    local animGroup = dropdownList:CreateAnimationGroup()
    local heightAnim = animGroup:CreateAnimation("Animation")
    heightAnim:SetDuration(ANIM_DURATION)

    local arrowAnimGroup = arrow:CreateAnimationGroup()
    local arrowRotation = arrowAnimGroup:CreateAnimation("Rotation")
    arrowRotation:SetDuration(ANIM_DURATION)
    arrowRotation:SetOrigin("CENTER", 0, 0)
    arrowRotation:SetSmoothing("IN_OUT")
    arrowAnimGroup:SetScript("OnFinished", function()
        arrow:SetRotation(isOpen and 0 or -math.pi / 2)
    end)

    animGroup:SetScript("OnUpdate", function(self)
        local p = self:GetProgress() or 0
        local smooth = p * p * (3 - 2 * p)
        dropdownList:SetHeight(startHeight + (targetHeight - startHeight) * smooth)
    end)
    animGroup:SetScript("OnFinished", function()
        dropdownList:SetHeight(targetHeight)
        if not isOpen then
            dropdownList:Hide()
            if dropdownList._logicalParent then
                dropdownList:SetParent(dropdownList._logicalParent)
                dropdownList._logicalParent = nil
            end
        else
            dropdownList:SetClipsChildren(true)
        end
    end)

    -- Border hover animation
    local hoverAnimGroup = dropdownButton:CreateAnimationGroup()
    hoverAnimGroup:CreateAnimation("Animation"):SetDuration(0.15)
    local hFrom = { r = Theme.border[1], g = Theme.border[2], b = Theme.border[3] }
    local hTo   = { r = Theme.border[1], g = Theme.border[2], b = Theme.border[3] }
    hoverAnimGroup:SetScript("OnUpdate", function(self)
        local p = self:GetProgress() or 0
        dropdownButton:SetBackdropBorderColor(
            hFrom.r + (hTo.r - hFrom.r) * p,
            hFrom.g + (hTo.g - hFrom.g) * p,
            hFrom.b + (hTo.b - hFrom.b) * p, 1)
    end)
    hoverAnimGroup:SetScript("OnFinished", function()
        dropdownButton:SetBackdropBorderColor(hTo.r, hTo.g, hTo.b, 1)
    end)

    local function SetBorderHover(hovered)
        hoverAnimGroup:Stop()
        local T = addon.Theme
        hFrom.r, hFrom.g, hFrom.b = dropdownButton:GetBackdropBorderColor()
        hTo.r = hovered and T.accent[1] or T.border[1]
        hTo.g = hovered and T.accent[2] or T.border[2]
        hTo.b = hovered and T.accent[3] or T.border[3]
        hoverAnimGroup:Play()
    end

    -- ── CloseDropdown ───────────────────────────────────────────────────────────────

    local function CloseDropdown(instant)
        if scrollHold or not isOpen then return end
        isOpen = false
        if instant then
            dropdownList:SetHeight(1)
            dropdownList:Hide()
            if dropdownList._logicalParent then
                dropdownList:SetParent(dropdownList._logicalParent)
                dropdownList._logicalParent = nil
            end
            arrow:SetRotation(-math.pi / 2)
            animGroup:Stop()
            arrowAnimGroup:Stop()
        else
            startHeight = dropdownList:GetHeight()
            targetHeight = 1
            arrowAnimGroup:Stop()
            arrowRotation:SetRadians(-math.pi / 2)
            arrowAnimGroup:Play()
            animGroup:Stop()
            animGroup:Play()
        end
        if globalMouseChecker.activeDropdown == row then
            globalMouseChecker.activeDropdown = nil
            globalMouseChecker:Hide()
        end
        if GUIFrame.activeDropdown == dropdownButton then
            GUIFrame.activeDropdown = nil
        end
    end

    -- ── UpdateScroll ────────────────────────────────────────────────────────────────

    local function UpdateScroll()
        local contentHeight = scrollChild:GetHeight()
        local sfHeight = scrollFrame:GetHeight()
        scrollFrame:SetVerticalScroll(0)
        scrollChild:SetWidth(scrollFrame:GetWidth())
        for _, btn in ipairs(itemButtons) do
            btn:ClearAllPoints()
            btn:SetPoint("TOPLEFT",  scrollChild, "TOPLEFT",  0, -(btn._index - 1) * ITEM_HEIGHT)
            btn:SetPoint("RIGHT",    scrollChild, "RIGHT",    0, 0)
        end
        UpdateScrollbar()
    end

    -- ── Create Item Buttons ─────────────────────────────────────────────────────────

    local function CreateItemButtons()
        for _, btn in ipairs(itemButtons) do ReleaseItemButton(btn) end
        wipe(itemButtons)
        local T = addon.Theme
        local sortedKeys = orderedKeys
        if not sortedKeys then
            sortedKeys = {}
            for k in pairs(normalizedOptions) do table_insert(sortedKeys, k) end
            table_sort(sortedKeys, function(a, b) return tostring(a) < tostring(b) end)
        end
        for i, key in ipairs(sortedKeys) do
            local displayText = normalizedOptions[key]
            local btn = AcquireItemButton(scrollChild)
            btn._itemValue = key
            btn._itemText  = displayText
            btn._index     = i
            btn._text:SetText(displayText or key)
            local function UpdateItemColor()
                if currentValue == btn._itemValue then
                    btn._text:SetTextColor(T.accent[1], T.accent[2], T.accent[3], 1)
                else
                    btn._text:SetTextColor(T.textSecondary[1], T.textSecondary[2], T.textSecondary[3], 1)
                end
            end
            btn._updateColor = UpdateItemColor
            UpdateItemColor()
            btn:SetScript("OnClick", function()
                currentValue = btn._itemValue
                selectedText:SetText(btn._itemText or btn._itemValue)
                for _, ib in ipairs(itemButtons) do if ib._updateColor then ib._updateColor() end end
                CloseDropdown(true)
                if callback then callback(btn._itemValue) end
            end)
            btn:SetScript("OnEnter", function()
                btn._hoverBg:Show()
                btn._text:SetTextColor(T.textPrimary[1], T.textPrimary[2], T.textPrimary[3], 1)
            end)
            btn:SetScript("OnLeave", function()
                btn._hoverBg:Hide()
                UpdateItemColor()
            end)
            btn:SetPoint("TOPLEFT",  scrollChild, "TOPLEFT",  0, -(i - 1) * ITEM_HEIGHT)
            btn:SetPoint("RIGHT",    scrollChild, "RIGHT",    0, 0)
            table_insert(itemButtons, btn)
        end
        scrollChild:SetHeight(#sortedKeys * ITEM_HEIGHT)
        itemsCreated = true
    end

    scrollFrame:EnableMouseWheel(true)
    scrollFrame:SetScript("OnMouseWheel", function(_, delta)
        scrollFrame:SetVerticalScroll(math_max(0,
            math_min(scrollChild:GetHeight() - scrollFrame:GetHeight(),
                scrollFrame:GetVerticalScroll() - delta * ITEM_HEIGHT)))
        UpdateScrollbar()
    end)

    -- ── ToggleDropdown (Open / Close) ───────────────────────────────────────────────

    local function ToggleDropdown()
        if isOpen then
            CloseDropdown()
        else
            if not itemsCreated then CreateItemButtons() end
            -- Close any other open dropdown
            if GUIFrame.activeDropdown and GUIFrame.activeDropdown ~= dropdownButton then
                if GUIFrame.activeDropdown.closeDropdown then
                    GUIFrame.activeDropdown.closeDropdown()
                end
            end
            GUIFrame.activeDropdown = dropdownButton

            dropdownList._logicalParent = dropdownList:GetParent()
            dropdownList:SetParent(addon.GUIOverlay)
            dropdownList:ClearAllPoints()
            dropdownList:SetPoint("TOPLEFT",  dropdownButton, "BOTTOMLEFT",  0, -2)
            dropdownList:SetPoint("TOPRIGHT", dropdownButton, "BOTTOMRIGHT", 0, -2)

            targetHeight = math_min(#itemButtons * ITEM_HEIGHT, MAX_DROPDOWN_HEIGHT)
            startHeight  = 1
            dropdownList:SetHeight(targetHeight)
            scrollChild:SetWidth(scrollFrame:GetWidth())
            UpdateScroll()
            dropdownList:Show()
            dropdownList:SetHeight(startHeight)
            isOpen = true

            arrowAnimGroup:Stop()
            arrowRotation:SetRadians(math.pi / 2)
            arrowAnimGroup:Play()
            animGroup:Stop()
            animGroup:Play()

            row._dropdownList   = dropdownList
            row._dropdownButton = dropdownButton
            row._closeDropdown  = CloseDropdown
            globalMouseChecker.activeDropdown = row
            globalMouseChecker.wasMouseDown   = false
            globalMouseChecker:Show()
        end
    end

    dropdownButton:SetScript("OnClick",  ToggleDropdown)
    dropdownButton:SetScript("OnEnter",  function() SetBorderHover(true) end)
    dropdownButton:SetScript("OnLeave",  function() SetBorderHover(false) end)
    dropdownButton:SetScript("OnHide",   function() CloseDropdown(true) end)
    dropdownList:SetScript("OnHide",     function() if isOpen then isOpen = false end end)

    if selected and normalizedOptions[selected] then
        selectedText:SetText(normalizedOptions[selected])
    elseif selected ~= nil then
        selectedText:SetText(tostring(selected))
    else
        selectedText:SetText("Select...")
    end

    -- ════════════════════════════════════════════════════════════════════════════════
    -- Part 5: Public API
    -- ════════════════════════════════════════════════════════════════════════════════

    function row:SetValue(value, silent)
        currentValue = value
        selectedText:SetText(normalizedOptions[value] or tostring(value))
        if itemsCreated then
            for _, btn in ipairs(itemButtons) do
                if btn._updateColor then btn._updateColor() end
            end
        end
        if callback and not silent then callback(value) end
    end

    function row:GetValue() return currentValue end

    function row:SetEnabled(enabled)
        if enabled then
            dropdownButton:Enable()
            dropdownButton:SetAlpha(1)
            label:SetAlpha(1)
        else
            dropdownButton:Disable()
            dropdownButton:SetAlpha(0.5)
            label:SetAlpha(0.5)
            if isOpen then CloseDropdown() end
        end
    end

    dropdownButton.closeDropdown = CloseDropdown
    row.dropdown = dropdownButton
    return row
end