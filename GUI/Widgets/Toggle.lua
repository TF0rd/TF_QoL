-- ════════════════════════════════════════════════════════════════════════════════════
-- Widget: Toggle/Checkbox (Animated slide toggle with checkmark/cross icons)
-- Usage: GUIFrame:CreateCheckbox(parent, labelText, initialState, onValueChanged)
-- ════════════════════════════════════════════════════════════════════════════════════

local _, addon = ...
local GUIFrame = addon.GUIFrame

local CreateFrame = CreateFrame
local C_Timer = C_Timer
local select = select
local math = math

-- ════════════════════════════════════════════════════════════════════════════════════
-- Part 1: Constants
-- ════════════════════════════════════════════════════════════════════════════════════

local TOGGLE_WIDTH = 48
local TOGGLE_HEIGHT = 24
local KNOB_SIZE = 22
local KNOB_PADDING = 1
local ANIM_DURATION = 0.18
local OFF_POSITION = KNOB_PADDING
local ON_POSITION = TOGGLE_WIDTH - KNOB_SIZE - KNOB_PADDING

local CHECK_TEX = "Interface\\AddOns\\TF_QoL\\Media\\GUITextures\\ok-iconBlack.tga"
local CROSS_TEX = "Interface\\AddOns\\TF_QoL\\Media\\GUITextures\\cross-small.png"

-- ════════════════════════════════════════════════════════════════════════════════════
-- Part 2: CreateCheckbox (Main factory — row with label, toggle track, animated knob)
-- ════════════════════════════════════════════════════════════════════════════════════

function GUIFrame:CreateCheckbox(parent, labelText, initialState, onValueChanged)
    local Theme = addon.Theme
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

    -- ── Toggle Track ────────────────────────────────────────────────────────────────

    local toggle = CreateFrame("Frame", nil, row, "BackdropTemplate")
    toggle:SetSize(TOGGLE_WIDTH, TOGGLE_HEIGHT)
    toggle:SetPoint("TOPLEFT", row, "TOPLEFT", 0, -14)
    toggle:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    toggle:SetBackdropColor(Theme.bgLight[1], Theme.bgLight[2], Theme.bgLight[3], 1)
    toggle:SetBackdropBorderColor(Theme.border[1], Theme.border[2], Theme.border[3], 1)

    -- ── Knob ────────────────────────────────────────────────────────────────────────

    local knob = CreateFrame("Frame", nil, toggle, "BackdropTemplate")
    knob:SetSize(KNOB_SIZE, KNOB_SIZE)
    knob:SetPoint("LEFT", toggle, "LEFT", OFF_POSITION, 0)
    knob:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1, insets = { left = -1, right = -1, top = 0, bottom = 0 } })
    knob:SetBackdropColor(0, 0, 0, 1)
    knob:SetBackdropBorderColor(Theme.border[1], Theme.border[2], Theme.border[3], 1)

    local knobTexture = knob:CreateTexture(nil, "ARTWORK")
    knobTexture:SetAllPoints()
    knobTexture:SetColorTexture(Theme.accent[1], Theme.accent[2], Theme.accent[3], 0.6)

    local checkmark = knob:CreateTexture(nil, "OVERLAY")
    checkmark:SetSize(KNOB_SIZE, KNOB_SIZE)
    checkmark:SetPoint("CENTER")
    checkmark:SetTexture(CHECK_TEX)
    checkmark:Hide()

    local crossmark = knob:CreateTexture(nil, "OVERLAY")
    crossmark:SetSize(KNOB_SIZE, KNOB_SIZE)
    crossmark:SetPoint("CENTER")
    crossmark:SetTexture(CROSS_TEX)
    crossmark:SetVertexColor(1, 1, 1, 0.8)
    crossmark:Hide()

    -- ── Animations ──────────────────────────────────────────────────────────────────

    local animGroup = knob:CreateAnimationGroup()
    local slideAnim = animGroup:CreateAnimation("Translation")
    slideAnim:SetDuration(ANIM_DURATION)
    slideAnim:SetSmoothing("OUT")

    local colorAnimGroup = toggle:CreateAnimationGroup()
    colorAnimGroup:SetLooping("NONE")
    local colorAnim = colorAnimGroup:CreateAnimation("Animation")
    colorAnim:SetDuration(ANIM_DURATION)

    -- ── State ───────────────────────────────────────────────────────────────────────

    local state = initialState or false
    local isAnimating = false
    local knobR, knobG, knobB, knobA = Theme.accent[1], Theme.accent[2], Theme.accent[3], 0.6
    local colorFrom, colorTo = {}, {}

    local function AnyAnimating()
        return animGroup:IsPlaying() or colorAnimGroup:IsPlaying()
    end

    local function UpdateIcons()
        if state then checkmark:Show() crossmark:Hide()
        else checkmark:Hide() crossmark:Show() end
    end

    colorAnimGroup:SetScript("OnUpdate", function(self)
        local p = self:GetProgress() or 0
        local r = colorFrom.bgR + (colorTo.bgR - colorFrom.bgR) * p
        local g = colorFrom.bgG + (colorTo.bgG - colorFrom.bgG) * p
        local b = colorFrom.bgB + (colorTo.bgB - colorFrom.bgB) * p
        toggle:SetBackdropColor(r, g, b, 1)
        local rT = colorFrom.knobR + (colorTo.knobR - colorFrom.knobR) * p
        local gT = colorFrom.knobG + (colorTo.knobG - colorFrom.knobG) * p
        local bT = colorFrom.knobB + (colorTo.knobB - colorFrom.knobB) * p
        local aT = colorFrom.knobA + (colorTo.knobA - colorFrom.knobA) * p
        knobTexture:SetColorTexture(rT, gT, bT, aT)
        knobR, knobG, knobB, knobA = rT, gT, bT, aT
    end)

    colorAnimGroup:SetScript("OnFinished", function()
        toggle:SetBackdropColor(colorTo.bgR, colorTo.bgG, colorTo.bgB, 1)
        knobTexture:SetColorTexture(colorTo.knobR, colorTo.knobG, colorTo.knobB, colorTo.knobA)
        knobR, knobG, knobB, knobA = colorTo.knobR, colorTo.knobG, colorTo.knobB, colorTo.knobA
        UpdateIcons()
    end)

    -- ── Color Update Logic ──────────────────────────────────────────────────────────

    local function UpdateColors(toState, instant)
        local T = addon.Theme
        UpdateIcons()
        if toState then
            label:SetTextColor(T.textPrimary[1], T.textPrimary[2], T.textPrimary[3], 1)
        else
            label:SetTextColor(T.textMuted[1], T.textMuted[2], T.textMuted[3], 1)
        end
        if instant then
            if toState then
                toggle:SetBackdropColor(T.accent[1] * 0.5, T.accent[2] * 0.5, T.accent[3] * 0.5, 1)
                knobTexture:SetColorTexture(T.accent[1], T.accent[2], T.accent[3], 1)
                knobR, knobG, knobB, knobA = T.accent[1], T.accent[2], T.accent[3], 1
            else
                toggle:SetBackdropColor(T.bgMedium[1], T.bgMedium[2], T.bgMedium[3], 1)
                knobTexture:SetColorTexture(T.accent[1], T.accent[2], T.accent[3], 0.4)
                knobR, knobG, knobB, knobA = T.accent[1], T.accent[2], T.accent[3], 0.4
            end
        else
            local T2 = addon.Theme
            colorAnimGroup:Stop()
            colorFrom.bgR, colorFrom.bgG, colorFrom.bgB = toggle:GetBackdropColor()
            colorFrom.knobR, colorFrom.knobG, colorFrom.knobB, colorFrom.knobA = knobR, knobG, knobB, knobA
            colorTo.bgR = toState and T2.accent[1] * 0.5 or T2.bgMedium[1]
            colorTo.bgG = toState and T2.accent[2] * 0.5 or T2.bgMedium[2]
            colorTo.bgB = toState and T2.accent[3] * 0.5 or T2.bgMedium[3]
            colorTo.knobR = T2.accent[1]
            colorTo.knobG = T2.accent[2]
            colorTo.knobB = T2.accent[3]
            colorTo.knobA = toState and 1 or 0.4
            colorAnimGroup:Play()
            UpdateIcons()
        end
    end

    -- ── AnimateToState ──────────────────────────────────────────────────────────────

    local function AnimateToState(toState, instant)
        if isAnimating and not instant then return end
        isAnimating = true
        state = toState
        local targetX = toState and ON_POSITION or OFF_POSITION
        local currentX = select(4, knob:GetPoint())
        local deltaX = targetX - (currentX or OFF_POSITION)
        if instant or math.abs(deltaX) < 1 then
            knob:ClearAllPoints()
            knob:SetPoint("LEFT", toggle, "LEFT", targetX, 0)
            UpdateColors(toState, true)
            isAnimating = false
        else
            UpdateColors(toState, false)
            animGroup:Stop()
            knob:ClearAllPoints()
            knob:SetPoint("LEFT", toggle, "LEFT", currentX, 0)
            slideAnim:SetOffset(deltaX, 0)
            animGroup:SetScript("OnFinished", function()
                knob:ClearAllPoints()
                knob:SetPoint("LEFT", toggle, "LEFT", targetX, 0)
                isAnimating = false
                UpdateIcons()
            end)
            animGroup:Play()
        end
    end

    AnimateToState(state, true)

    -- ── Click Button ────────────────────────────────────────────────────────────────

    local button = CreateFrame("Button", nil, toggle)
    button:SetAllPoints()
    button:RegisterForClicks("LeftButtonUp")
    button:SetScript("OnClick", function()
        if AnyAnimating() then return end
        local newState = not state
        AnimateToState(newState, false)
        if onValueChanged then
            C_Timer.After(ANIM_DURATION, function()
                onValueChanged(newState)
            end)
        end
    end)

    button:SetScript("OnEnter", function()
        local T = addon.Theme
        local brightness = 1.2
        knobTexture:SetColorTexture(T.accent[1] * brightness, T.accent[2] * brightness, T.accent[3] * brightness, state and 1 or 0.6)
        knobR, knobG, knobB, knobA = T.accent[1] * brightness, T.accent[2] * brightness, T.accent[3] * brightness, state and 1 or 0.6
    end)

    button:SetScript("OnLeave", function()
        local T = addon.Theme
        if state then
            knobTexture:SetColorTexture(T.accent[1], T.accent[2], T.accent[3], 1)
            knobR, knobG, knobB, knobA = T.accent[1], T.accent[2], T.accent[3], 1
        else
            knobTexture:SetColorTexture(T.accent[1], T.accent[2], T.accent[3], 0.4)
            knobR, knobG, knobB, knobA = T.accent[1], T.accent[2], T.accent[3], 0.4
        end
    end)

    -- ════════════════════════════════════════════════════════════════════════════════
    -- Part 3: Public API
    -- ════════════════════════════════════════════════════════════════════════════════

    toggle.SetValue = function(_, value, instant)
        if value ~= state then
            AnimateToState(value, instant)
            if onValueChanged and not instant then
                C_Timer.After(ANIM_DURATION, function() onValueChanged(value) end)
            end
        end
    end

    toggle.GetValue = function() return state end

    function row:SetEnabled(enabled)
        local alpha = enabled and 1 or addon.Theme.disabledAlpha
        toggle:SetAlpha(alpha)
        label:SetAlpha(alpha)
        button:EnableMouse(enabled)
    end

    function row:SetValue(value, instant)
        toggle:SetValue(value, instant)
    end

    function row:GetValue()
        return toggle:GetValue()
    end

    row.toggle = toggle
    return row
end