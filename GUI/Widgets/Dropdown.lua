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
-- Part 4: Module-Level Builders (each takes the shared state table `s`)
-- ════════════════════════════════════════════════════════════════════════════════════

-- ── Normalize the flexible `options` shapes into { map, orderedKeys } ───────────────

local function NormalizeOptions(options)
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
    return normalizedOptions, orderedKeys
end

-- ── Floating list frame + scrollframe/scrollchild ───────────────────────────────────

local function BuildList(s)
    local Theme = addon.Theme
    local dropdownList = CreateFrame("Frame", nil, s.row, "BackdropTemplate")
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

    s.dropdownList = dropdownList
    s.scrollFrame = scrollFrame
    s.scrollChild = scrollChild
end

-- ── Custom scrollbar (track + draggable thumb + paging) ─────────────────────────────

local function BuildScrollbar(s)
    local Theme = addon.Theme
    local dropdownList, scrollFrame, scrollChild = s.dropdownList, s.scrollFrame, s.scrollChild
    local SCROLLBAR_WIDTH = 8
    s.scrollbarWidth = SCROLLBAR_WIDTH

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

    s.scrollbarTrack = scrollbarTrack
    s.scrollbarThumb = scrollbarThumb
    s.isDraggingThumb = false

    function s.UpdateScrollbar()
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
        if not s.isDraggingThumb then return end
        local _, cursorY = GetCursorPosition()
        cursorY = cursorY / scrollbarThumb:GetEffectiveScale()
        local trackHeight = scrollbarTrack:GetHeight()
        local thumbHeight = scrollbarThumb:GetHeight()
        local maxThumbOffset = trackHeight - thumbHeight
        local deltaY = cursorY - s.dragStartY
        local deltaScroll = (deltaY / maxThumbOffset) * (scrollChild:GetHeight() - scrollFrame:GetHeight())
        scrollFrame:SetVerticalScroll(math_max(0, math_min(scrollChild:GetHeight() - scrollFrame:GetHeight(), s.dragStartScroll - deltaScroll)))
        s.UpdateScrollbar()
    end)

    scrollbarThumb:SetScript("OnMouseDown", function(self, button)
        if button == "LeftButton" then
            s.isDraggingThumb = true
            s.scrollHold = true
            s.row._scrollHold = true
            s.dragStartY = select(2, GetCursorPosition()) / self:GetEffectiveScale()
            s.dragStartScroll = scrollFrame:GetVerticalScroll()
            self.bg:SetColorTexture(Theme.accent[1], Theme.accent[2], Theme.accent[3], 1)
            thumbDragFrame:Show()
        end
    end)
    scrollbarThumb:SetScript("OnMouseUp", function(self)
        s.isDraggingThumb = false
        s.scrollHold = false
        s.row._scrollHold = false
        self.bg:SetColorTexture(Theme.accent[1], Theme.accent[2], Theme.accent[3], 0.8)
        thumbDragFrame:Hide()
    end)
    scrollbarThumb:SetScript("OnHide", function(self)
        s.isDraggingThumb = false
        s.scrollHold = false
        s.row._scrollHold = false
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
        s.UpdateScrollbar()
    end)
end

-- ── Animations (list height + arrow rotation + button border hover) ─────────────────

local function BuildAnimations(s)
    local Theme = addon.Theme
    local dropdownList, dropdownButton, arrow = s.dropdownList, s.dropdownButton, s.arrow

    local animGroup = dropdownList:CreateAnimationGroup()
    local heightAnim = animGroup:CreateAnimation("Animation")
    heightAnim:SetDuration(ANIM_DURATION)

    local arrowAnimGroup = arrow:CreateAnimationGroup()
    local arrowRotation = arrowAnimGroup:CreateAnimation("Rotation")
    arrowRotation:SetDuration(ANIM_DURATION)
    arrowRotation:SetOrigin("CENTER", 0, 0)
    arrowRotation:SetSmoothing("IN_OUT")
    arrowAnimGroup:SetScript("OnFinished", function()
        arrow:SetRotation(s.isOpen and 0 or -math.pi / 2)
    end)

    animGroup:SetScript("OnUpdate", function(self)
        local p = self:GetProgress() or 0
        local smooth = p * p * (3 - 2 * p)
        dropdownList:SetHeight(s.startHeight + (s.targetHeight - s.startHeight) * smooth)
    end)
    animGroup:SetScript("OnFinished", function()
        dropdownList:SetHeight(s.targetHeight)
        if not s.isOpen then
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

    function s.SetBorderHover(hovered)
        hoverAnimGroup:Stop()
        local T = addon.Theme
        hFrom.r, hFrom.g, hFrom.b = dropdownButton:GetBackdropBorderColor()
        hTo.r = hovered and T.accent[1] or T.border[1]
        hTo.g = hovered and T.accent[2] or T.border[2]
        hTo.b = hovered and T.accent[3] or T.border[3]
        hoverAnimGroup:Play()
    end

    s.animGroup = animGroup
    s.arrowAnimGroup = arrowAnimGroup
    s.arrowRotation = arrowRotation
end

-- ── Option rows (pooled item buttons, scroll layout, open/close/toggle) ────────────

local function BuildRows(s)
    local scrollFrame, scrollChild = s.scrollFrame, s.scrollChild

    function s.UpdateScroll()
        s.scrollChild:SetWidth(scrollFrame:GetWidth())
        for _, btn in ipairs(s.itemButtons) do
            btn:ClearAllPoints()
            btn:SetPoint("TOPLEFT",  scrollChild, "TOPLEFT",  0, -(btn._index - 1) * ITEM_HEIGHT)
            btn:SetPoint("RIGHT",    scrollChild, "RIGHT",    0, 0)
        end
        s.UpdateScrollbar()
    end

    function s.CreateItemButtons()
        for _, btn in ipairs(s.itemButtons) do ReleaseItemButton(btn) end
        wipe(s.itemButtons)
        local T = addon.Theme
        local sortedKeys = s.orderedKeys
        if not sortedKeys then
            sortedKeys = {}
            for k in pairs(s.normalizedOptions) do table_insert(sortedKeys, k) end
            table_sort(sortedKeys, function(a, b) return tostring(a) < tostring(b) end)
        end
        for i, key in ipairs(sortedKeys) do
            local displayText = s.normalizedOptions[key]
            local btn = AcquireItemButton(scrollChild)
            btn._itemValue = key
            btn._itemText  = displayText
            btn._index     = i
            btn._text:SetText(displayText or key)
            local function UpdateItemColor()
                if s.currentValue == btn._itemValue then
                    btn._text:SetTextColor(T.accent[1], T.accent[2], T.accent[3], 1)
                else
                    btn._text:SetTextColor(T.textSecondary[1], T.textSecondary[2], T.textSecondary[3], 1)
                end
            end
            btn._updateColor = UpdateItemColor
            UpdateItemColor()
            btn:SetScript("OnClick", function()
                s.currentValue = btn._itemValue
                s.selectedText:SetText(btn._itemText or btn._itemValue)
                for _, ib in ipairs(s.itemButtons) do if ib._updateColor then ib._updateColor() end end
                s.CloseDropdown(true)
                if s.callback then s.callback(btn._itemValue) end
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
            table_insert(s.itemButtons, btn)
        end
        scrollChild:SetHeight(#sortedKeys * ITEM_HEIGHT)
        s.itemsCreated = true
    end

    scrollFrame:EnableMouseWheel(true)
    scrollFrame:SetScript("OnMouseWheel", function(_, delta)
        scrollFrame:SetVerticalScroll(math_max(0,
            math_min(scrollChild:GetHeight() - scrollFrame:GetHeight(),
                scrollFrame:GetVerticalScroll() - delta * ITEM_HEIGHT)))
        s.UpdateScrollbar()
    end)

    function s.CloseDropdown(instant)
        if s.scrollHold or not s.isOpen then return end
        s.isOpen = false
        local dropdownList = s.dropdownList
        if instant then
            dropdownList:SetHeight(1)
            dropdownList:Hide()
            if dropdownList._logicalParent then
                dropdownList:SetParent(dropdownList._logicalParent)
                dropdownList._logicalParent = nil
            end
            s.arrow:SetRotation(-math.pi / 2)
            s.animGroup:Stop()
            s.arrowAnimGroup:Stop()
        else
            s.startHeight = dropdownList:GetHeight()
            s.targetHeight = 1
            s.arrowAnimGroup:Stop()
            s.arrowRotation:SetRadians(-math.pi / 2)
            s.arrowAnimGroup:Play()
            s.animGroup:Stop()
            s.animGroup:Play()
        end
        if globalMouseChecker.activeDropdown == s.row then
            globalMouseChecker.activeDropdown = nil
            globalMouseChecker:Hide()
        end
        if GUIFrame.activeDropdown == s.dropdownButton then
            GUIFrame.activeDropdown = nil
        end
    end

    function s.ToggleDropdown()
        if s.isOpen then
            s.CloseDropdown()
        else
            if not s.itemsCreated then s.CreateItemButtons() end
            -- Close any other open dropdown
            if GUIFrame.activeDropdown and GUIFrame.activeDropdown ~= s.dropdownButton then
                if GUIFrame.activeDropdown.closeDropdown then
                    GUIFrame.activeDropdown.closeDropdown()
                end
            end
            GUIFrame.activeDropdown = s.dropdownButton

            local dropdownList = s.dropdownList
            dropdownList._logicalParent = dropdownList:GetParent()
            dropdownList:SetParent(addon.GUIOverlay)
            dropdownList:ClearAllPoints()
            dropdownList:SetPoint("TOPLEFT",  s.dropdownButton, "BOTTOMLEFT",  0, -2)
            dropdownList:SetPoint("TOPRIGHT", s.dropdownButton, "BOTTOMRIGHT", 0, -2)

            s.targetHeight = math_min(#s.itemButtons * ITEM_HEIGHT, MAX_DROPDOWN_HEIGHT)
            s.startHeight  = 1
            dropdownList:SetHeight(s.targetHeight)
            scrollChild:SetWidth(s.scrollFrame:GetWidth())
            s.UpdateScroll()
            dropdownList:Show()
            dropdownList:SetHeight(s.startHeight)
            s.isOpen = true

            s.arrowAnimGroup:Stop()
            s.arrowRotation:SetRadians(math.pi / 2)
            s.arrowAnimGroup:Play()
            s.animGroup:Stop()
            s.animGroup:Play()

            s.row._dropdownList   = dropdownList
            s.row._dropdownButton = s.dropdownButton
            s.row._closeDropdown  = s.CloseDropdown
            globalMouseChecker.activeDropdown = s.row
            globalMouseChecker.wasMouseDown   = false
            globalMouseChecker:Show()
        end
    end
end

-- ════════════════════════════════════════════════════════════════════════════════════
-- Part 5: CreateDropdown (Main factory — wires the builders above)
-- ════════════════════════════════════════════════════════════════════════════════════

function GUIFrame:CreateDropdown(parent, labelText, options, selected, callback)
    local Theme = addon.Theme

    -- ── Shared state ────────────────────────────────────────────────────────────────

    local s = {
        callback = callback,
        isOpen = false,
        currentValue = selected,
        itemButtons = {},
        itemsCreated = false,
        startHeight = 0,
        targetHeight = 0,
        scrollHold = false,
    }

    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(34)
    s.row = row

    -- ── Label ───────────────────────────────────────────────────────────────────────

    local label = row:CreateFontString(nil, "OVERLAY")
    label:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 1)
    label:SetJustifyH("LEFT")
    addon:ApplyThemeFont(label, "small")
    label:SetText(labelText or "")
    label:SetTextColor(Theme.textMuted[1], Theme.textMuted[2], Theme.textMuted[3], 1)
    row.label = label
    s.label = label

    -- ── Dropdown Button ─────────────────────────────────────────────────────────────

    local dropdownButton = CreateFrame("Button", nil, row, "BackdropTemplate")
    dropdownButton:SetHeight(DROPDOWN_HEIGHT)
    dropdownButton:SetPoint("TOPLEFT",  row, "TOPLEFT",  0, -14)
    dropdownButton:SetPoint("TOPRIGHT", row, "TOPRIGHT", 0, -14)
    dropdownButton:SetBackdrop(DROPDOWN_BACKDROP)
    dropdownButton:SetBackdropColor(Theme.bgLight[1], Theme.bgLight[2], Theme.bgLight[3], 1)
    dropdownButton:SetBackdropBorderColor(Theme.border[1], Theme.border[2], Theme.border[3], 1)
    s.dropdownButton = dropdownButton

    local selectedText = dropdownButton:CreateFontString(nil, "OVERLAY")
    selectedText:SetPoint("LEFT",  dropdownButton, "LEFT",  Theme.paddingSmall, 0)
    selectedText:SetPoint("RIGHT", dropdownButton, "RIGHT", -24, 0)
    selectedText:SetJustifyH("LEFT")
    addon:ApplyThemeFont(selectedText, "normal")
    selectedText:SetTextColor(Theme.textPrimary[1], Theme.textPrimary[2], Theme.textPrimary[3], 1)
    dropdownButton.selectedText = selectedText
    s.selectedText = selectedText

    local arrow = dropdownButton:CreateTexture(nil, "ARTWORK")
    arrow:SetSize(ARROW_SIZE, ARROW_SIZE)
    arrow:SetPoint("RIGHT", dropdownButton, "RIGHT", -Theme.paddingSmall, 0)
    arrow:SetTexture(ARROW_TEX)
    arrow:SetVertexColor(Theme.accent[1], Theme.accent[2], Theme.accent[3], 1)
    arrow:SetRotation(-math.pi / 2)
    s.arrow = arrow

    -- ── Builders ────────────────────────────────────────────────────────────────────

    s.normalizedOptions, s.orderedKeys = NormalizeOptions(options)
    BuildList(s)
    BuildScrollbar(s)
    BuildAnimations(s)
    BuildRows(s)

    dropdownButton:SetScript("OnClick",  function() s.ToggleDropdown() end)
    dropdownButton:SetScript("OnEnter",  function() s.SetBorderHover(true) end)
    dropdownButton:SetScript("OnLeave",  function() s.SetBorderHover(false) end)
    dropdownButton:SetScript("OnHide",   function() s.CloseDropdown(true) end)
    s.dropdownList:SetScript("OnHide",   function() if s.isOpen then s.isOpen = false end end)

    if selected and s.normalizedOptions[selected] then
        selectedText:SetText(s.normalizedOptions[selected])
    elseif selected ~= nil then
        selectedText:SetText(tostring(selected))
    else
        selectedText:SetText("Select...")
    end

    -- ════════════════════════════════════════════════════════════════════════════════
    -- Part 6: Public API
    -- ════════════════════════════════════════════════════════════════════════════════

    function row:SetValue(value, silent)
        s.currentValue = value
        selectedText:SetText(s.normalizedOptions[value] or tostring(value))
        if s.itemsCreated then
            for _, btn in ipairs(s.itemButtons) do
                if btn._updateColor then btn._updateColor() end
            end
        end
        if callback and not silent then callback(value) end
    end

    function row:GetValue() return s.currentValue end

    function row:SetEnabled(enabled)
        local alpha = enabled and 1 or addon.Theme.disabledAlpha
        if enabled then
            dropdownButton:Enable()
        else
            dropdownButton:Disable()
            if s.isOpen then s.CloseDropdown() end
        end
        dropdownButton:SetAlpha(alpha)
        label:SetAlpha(alpha)
    end

    dropdownButton.closeDropdown = function(...) return s.CloseDropdown(...) end
    row.dropdown = dropdownButton
    return row
end
