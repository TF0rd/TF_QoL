-- ════════════════════════════════════════════════════════════════════════════════════
-- Widget: Slider (Horizontal slider with steppers, value editbox, and thumb animation)
-- Usage: GUIFrame:CreateSlider(parent, labelText, min, max, step, value, callback)
-- ════════════════════════════════════════════════════════════════════════════════════

local _, addon = ...
local GUIFrame = addon.GUIFrame

local tonumber = tonumber
local tostring = tostring
local CreateFrame = CreateFrame
local C_Timer = C_Timer
local math_floor, math_max, math_min = math.floor, math.max, math.min
local GetTime = GetTime

-- ════════════════════════════════════════════════════════════════════════════════════
-- Part 1: Constants
-- ════════════════════════════════════════════════════════════════════════════════════

local STEPPER_TEX = "Interface\\AddOns\\TF_QoL\\Media\\GUITextures\\collapse.tga"

-- ════════════════════════════════════════════════════════════════════════════════════
-- Part 2: CreateSlider (Main factory — row with label, track, thumb, steppers, editbox)
-- ════════════════════════════════════════════════════════════════════════════════════

function GUIFrame:CreateSlider(parent, labelText, min, max, step, value, callback)
    local Theme = addon.Theme
    min   = tonumber(min)   or 0
    max   = tonumber(max)   or 100
    step  = tonumber(step)  or 1
    value = tonumber(value) or min

    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(36)

    -- ── Label ───────────────────────────────────────────────────────────────────────

    local label = row:CreateFontString(nil, "OVERLAY")
    label:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 1)
    label:SetJustifyH("LEFT")
    addon:ApplyThemeFont(label, "small")
    label:SetText(labelText or "")
    label:SetTextColor(Theme.textMuted[1], Theme.textMuted[2], Theme.textMuted[3], 1)
    row.label = label

    -- ── Slider Background Track ─────────────────────────────────────────────────────

    local sliderBG = CreateFrame("Frame", nil, row, "BackdropTemplate")
    sliderBG:SetHeight(8)
    sliderBG:SetPoint("TOPLEFT",  row, "TOPLEFT",  68, -22)
    sliderBG:SetPoint("TOPRIGHT", row, "TOPRIGHT", -18, -22)
    sliderBG:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    sliderBG:SetBackdropColor(Theme.bgLight[1], Theme.bgLight[2], Theme.bgLight[3], 1)
    sliderBG:SetBackdropBorderColor(Theme.border[1], Theme.border[2], Theme.border[3], 1)
    sliderBG:EnableMouse(false)

    -- ── Slider ──────────────────────────────────────────────────────────────────────

    local slider = CreateFrame("Slider", nil, row, "BackdropTemplate")
    slider:SetHeight(8)
    slider:SetPoint("TOPLEFT",  row, "TOPLEFT",  77, -22)
    slider:SetPoint("TOPRIGHT", row, "TOPRIGHT", -27, -22)
    slider:SetOrientation("HORIZONTAL")
    slider:SetMinMaxValues(min, max)
    slider:SetValueStep(step)
    slider:SetObeyStepOnDrag(true)
    slider:SetValue(value)
    slider:SetHitRectInsets(-9, -9, -5, -5)
    slider:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    slider:SetBackdropColor(0, 0, 0, 0)
    slider:SetBackdropBorderColor(0, 0, 0, 0)

    -- ── Fill Bar ────────────────────────────────────────────────────────────────────

    local fill = slider:CreateTexture(nil, "ARTWORK")
    fill:SetHeight(6)
    fill:SetPoint("LEFT", sliderBG, "LEFT", 1, 0)
    fill:SetColorTexture(Theme.peach[1], Theme.peach[2], Theme.peach[3], 1)

    -- ── Thumb ───────────────────────────────────────────────────────────────────────

    local thumbFrameBG = CreateFrame("Frame", nil, slider, "BackdropTemplate")
    thumbFrameBG:SetSize(19, 12)
    thumbFrameBG:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    thumbFrameBG:SetBackdropColor(Theme.bgDark[1], Theme.bgDark[2], Theme.bgDark[3], 1)
    thumbFrameBG:SetBackdropBorderColor(0, 0, 0, 1)

    local thumbFrame = CreateFrame("Frame", nil, slider, "BackdropTemplate")
    thumbFrame:SetSize(19, 12)
    thumbFrame:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    thumbFrame:SetBackdropColor(Theme.textSecondary[1], Theme.textSecondary[2], Theme.textSecondary[3], 0.6)
    thumbFrame:SetBackdropBorderColor(Theme.accent[1], Theme.accent[2], Theme.accent[3], 0.3)

    local thumb = slider:CreateTexture(nil, "ARTWORK")
    thumb:SetColorTexture(0, 0, 0, 0)
    slider:SetThumbTexture(thumb)

    local function UpdateThumbPosition()
        local w = slider:GetWidth()
        if not w or w <= 0 then return end
        local minVal, maxVal = slider:GetMinMaxValues()
        if maxVal == minVal then return end
        local pct = (slider:GetValue() - minVal) / (maxVal - minVal)
        local thumbX = pct * w
        thumbFrameBG:ClearAllPoints()
        thumbFrameBG:SetPoint("CENTER", slider, "LEFT", thumbX, 0)
        thumbFrame:ClearAllPoints()
        thumbFrame:SetPoint("CENTER", slider, "LEFT", thumbX, 0)
    end

    -- ── Thumb Hover / Drag Animation ────────────────────────────────────────────────

    local hoverAnimGroup = slider:CreateAnimationGroup()
    hoverAnimGroup:CreateAnimation("Animation"):SetDuration(0.18)
    local bFrom, bTo = {}, {}
    local thumbR, thumbG, thumbB, thumbA = Theme.textSecondary[1], Theme.textSecondary[2], Theme.textSecondary[3], 0.6

    local function AnimateThumbColor(toHover, toDrag)
        hoverAnimGroup:Stop()
        bFrom.r, bFrom.g, bFrom.b, bFrom.a = thumbR, thumbG, thumbB, thumbA
        if toDrag then
            bTo.r, bTo.g, bTo.b, bTo.a = Theme.accent[1], Theme.accent[2], Theme.accent[3], 1
        elseif toHover then
            bTo.r, bTo.g, bTo.b, bTo.a = Theme.textSecondary[1], Theme.textSecondary[2], Theme.textSecondary[3], 1
        else
            bTo.r, bTo.g, bTo.b, bTo.a = Theme.textSecondary[1], Theme.textSecondary[2], Theme.textSecondary[3], 0.6
        end
        hoverAnimGroup:Play()
    end

    hoverAnimGroup:SetScript("OnUpdate", function(self)
        local p = self:GetProgress() or 0
        local r = bFrom.r + (bTo.r - bFrom.r) * p
        local g = bFrom.g + (bTo.g - bFrom.g) * p
        local b = bFrom.b + (bTo.b - bFrom.b) * p
        local a = bFrom.a + (bTo.a - bFrom.a) * p
        thumbFrame:SetBackdropColor(r, g, b, a)
        thumbR, thumbG, thumbB, thumbA = r, g, b, a
    end)
    hoverAnimGroup:SetScript("OnFinished", function()
        thumbFrame:SetBackdropColor(bTo.r, bTo.g, bTo.b, bTo.a)
        thumbR, thumbG, thumbB, thumbA = bTo.r, bTo.g, bTo.b, bTo.a
    end)

    -- ── Steppers (Left / Right) ─────────────────────────────────────────────────────

    local stepperSize = 20

    local leftStepper = CreateFrame("Button", nil, row)
    leftStepper:SetSize(stepperSize, stepperSize)
    leftStepper:SetPoint("RIGHT", sliderBG, "LEFT", 0, 0)
    local leftIcon = leftStepper:CreateTexture(nil, "ARTWORK")
    leftIcon:SetAllPoints()
    leftIcon:SetTexture(STEPPER_TEX)
    leftIcon:SetVertexColor(Theme.textSecondary[1], Theme.textSecondary[2], Theme.textSecondary[3], 1)
    leftIcon:SetRotation(math.rad(-90))
    leftStepper:SetScript("OnClick", function()
        local minVal = slider:GetMinMaxValues()
        slider:SetValue(math_max(minVal, slider:GetValue() - step))
    end)
    leftStepper:SetScript("OnEnter", function() leftIcon:SetVertexColor(Theme.accent[1], Theme.accent[2], Theme.accent[3], 1) end)
    leftStepper:SetScript("OnLeave", function() leftIcon:SetVertexColor(Theme.textSecondary[1], Theme.textSecondary[2], Theme.textSecondary[3], 1) end)

    local rightStepper = CreateFrame("Button", nil, row)
    rightStepper:SetSize(stepperSize, stepperSize)
    rightStepper:SetPoint("LEFT", sliderBG, "RIGHT", 0, 0)
    local rightIcon = rightStepper:CreateTexture(nil, "ARTWORK")
    rightIcon:SetAllPoints()
    rightIcon:SetTexture(STEPPER_TEX)
    rightIcon:SetVertexColor(Theme.textSecondary[1], Theme.textSecondary[2], Theme.textSecondary[3], 1)
    rightIcon:SetRotation(math.rad(90))
    rightStepper:SetScript("OnClick", function()
        local _, maxVal = slider:GetMinMaxValues()
        slider:SetValue(math_min(maxVal, slider:GetValue() + step))
    end)
    rightStepper:SetScript("OnEnter", function() rightIcon:SetVertexColor(Theme.accent[1], Theme.accent[2], Theme.accent[3], 1) end)
    rightStepper:SetScript("OnLeave", function() rightIcon:SetVertexColor(Theme.textSecondary[1], Theme.textSecondary[2], Theme.textSecondary[3], 1) end)

    -- ── Value EditBox ───────────────────────────────────────────────────────────────

    local valueContainer = CreateFrame("Frame", nil, slider, "BackdropTemplate")
    valueContainer:SetSize(48, 24)
    valueContainer:SetPoint("RIGHT", leftStepper, "LEFT", 0, 0)
    valueContainer:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    valueContainer:SetBackdropColor(Theme.bgMedium[1], Theme.bgMedium[2], Theme.bgMedium[3], 1)
    valueContainer:SetBackdropBorderColor(Theme.border[1], Theme.border[2], Theme.border[3], 1)

    local valueEdit = CreateFrame("EditBox", nil, valueContainer)
    valueEdit:SetPoint("TOPLEFT", 0, 0)
    valueEdit:SetPoint("BOTTOMRIGHT", 0, 0)
    valueEdit:SetFontObject("GameFontNormal")
    valueEdit:SetTextColor(Theme.textPrimary[1], Theme.textPrimary[2], Theme.textPrimary[3], 1)
    valueEdit:SetJustifyH("CENTER")
    valueEdit:SetAutoFocus(false)
    valueEdit:SetText(tostring(value))
    row.valueEdit = valueEdit

    -- ── Slider Event Handlers ───────────────────────────────────────────────────────

    local isUpdating = false
    local throttleDelay = 0.1
    local lastUpdate = 0

    local function UpdateFill()
        local val = slider:GetValue()
        local minVal, maxVal = slider:GetMinMaxValues()
        if maxVal == minVal then return end
        local pct = (val - minVal) / (maxVal - minVal)
        fill:SetWidth(math_max(1, (slider:GetWidth() - 2) * pct))
        if not isUpdating then
            isUpdating = true
            valueEdit:SetText(tostring(math_floor(val * 100 + 0.5) / 100))
            isUpdating = false
        end
    end

    slider:SetScript("OnValueChanged", function(self, val)
        UpdateFill()
        UpdateThumbPosition()
        local t = GetTime()
        if t - lastUpdate < throttleDelay then return end
        lastUpdate = t
        if callback then callback(val) end
    end)
    slider:SetScript("OnSizeChanged", function() UpdateFill(); UpdateThumbPosition() end)

    local function ApplyEditBoxValue()
        local num = tonumber(valueEdit:GetText())
        if num then
            local minVal, maxVal = slider:GetMinMaxValues()
            isUpdating = true
            slider:SetValue(math_max(minVal, math_min(maxVal, num)))
            isUpdating = false
        else
            UpdateFill()
        end
    end

    valueEdit:SetScript("OnEnterPressed", function(self) self:ClearFocus() ApplyEditBoxValue() end)
    valueEdit:SetScript("OnEscapePressed", function(self) self:ClearFocus() UpdateFill() end)
    valueEdit:SetScript("OnEditFocusLost",  function(self) ApplyEditBoxValue() self:HighlightText(0, 0) end)
    valueEdit:SetScript("OnEditFocusGained", function(self)
        valueContainer:SetBackdropBorderColor(Theme.accent[1], Theme.accent[2], Theme.accent[3], 1)
        self:HighlightText()
    end)
    valueEdit:SetScript("OnEnter", function() valueContainer:SetBackdropBorderColor(Theme.accent[1], Theme.accent[2], Theme.accent[3], 1) end)
    valueEdit:SetScript("OnLeave", function()
        if not valueEdit:HasFocus() then
            valueContainer:SetBackdropBorderColor(Theme.border[1], Theme.border[2], Theme.border[3], 1)
        end
    end)

    -- ── Drag / Hover ────────────────────────────────────────────────────────────────

    local curDrag = false
    slider:SetScript("OnMouseDown", function(_, btn)
        if btn == "LeftButton" then
            hoverAnimGroup:Stop()
            thumbFrame:SetBackdropColor(Theme.accent[1], Theme.accent[2], Theme.accent[3], 1)
            thumbR, thumbG, thumbB, thumbA = Theme.accent[1], Theme.accent[2], Theme.accent[3], 1
            curDrag = true
        end
    end)
    slider:SetScript("OnMouseUp", function(self, btn)
        if btn == "LeftButton" then
            curDrag = false
            AnimateThumbColor(self:IsMouseOver(), false)
        end
    end)
    slider:SetScript("OnEnter", function(self) if not curDrag then AnimateThumbColor(true, false) end end)
    slider:SetScript("OnLeave", function(self) if not curDrag then AnimateThumbColor(false, false) end end)

    C_Timer.After(0, function() UpdateFill(); UpdateThumbPosition() end)

    -- ════════════════════════════════════════════════════════════════════════════════
    -- Part 3: Public API
    -- ════════════════════════════════════════════════════════════════════════════════

    function row:SetValue(val) slider:SetValue(val) end
    function row:GetValue() return slider:GetValue() end
    function row:SetEnabled(enabled)
        if enabled then
            row:SetAlpha(1)
            slider:EnableMouse(true)
            valueEdit:EnableMouse(true)
            leftStepper:EnableMouse(true)
            rightStepper:EnableMouse(true)
        else
            row:SetAlpha(0.4)
            slider:EnableMouse(false)
            valueEdit:EnableMouse(false)
            leftStepper:EnableMouse(false)
            rightStepper:EnableMouse(false)
        end
    end

    row.slider = slider
    return row
end