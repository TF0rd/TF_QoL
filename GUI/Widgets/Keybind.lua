-- ════════════════════════════════════════════════════════════════════════════════════
-- Widget: Keybind Capture (Label + click-to-capture button + clear button)
-- Usage: GUIFrame:CreateKeybind(parent, label, currentKey, onChange, ...)
-- ════════════════════════════════════════════════════════════════════════════════════

local _, addon = ...
local GUIFrame = addon.GUIFrame

-- ════════════════════════════════════════════════════════════════════════════════════
-- Part 1: Display Helpers
-- ════════════════════════════════════════════════════════════════════════════════════

local function FormatKeyForDisplay(key)
    if not key or key == "" then return "|cff888888Not Bound|r" end
    return key:gsub("-", "+")
end

local MODIFIER_KEYS = {
    LSHIFT = true, RSHIFT = true,
    LCTRL = true,  RCTRL = true,
    LALT = true,   RALT = true,
}

-- ════════════════════════════════════════════════════════════════════════════════════
-- Part 2: CreateKeybind (Row with label, keybind button, and clear button)
-- ════════════════════════════════════════════════════════════════════════════════════

function GUIFrame:CreateKeybind(parent, label, currentKey, onChange, onCaptureStart, onCaptureEnd)
    local Theme = addon.Theme
    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(36)

    -- ── Label ───────────────────────────────────────────────────────────────────────

    local labelStr = row:CreateFontString(nil, "OVERLAY")
    labelStr:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 1)
    labelStr:SetJustifyH("LEFT")
    addon:ApplyThemeFont(labelStr, "small")
    labelStr:SetText(label or "")
    labelStr:SetTextColor(Theme.textSecondary[1], Theme.textSecondary[2], Theme.textSecondary[3], 1)
    row.label = labelStr

    -- ── Keybind Button ──────────────────────────────────────────────────────────────

    local button = CreateFrame("Button", nil, row, "BackdropTemplate")
    button:SetHeight(24)
    button:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0)
    button:SetWidth(160)
    button:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    button:SetBackdropColor(Theme.bgLight[1], Theme.bgLight[2], Theme.bgLight[3], 1)
    button:SetBackdropBorderColor(Theme.border[1], Theme.border[2], Theme.border[3], 1)
    button:EnableMouse(true)
    button:RegisterForClicks("AnyUp")

    local btnText = button:CreateFontString(nil, "OVERLAY")
    btnText:SetPoint("CENTER")
    addon:ApplyThemeFont(btnText, "small")
    btnText:SetTextColor(Theme.blue[1], Theme.blue[2], Theme.blue[3], 1)

    local isListening = false

    -- ── Internal State Management ───────────────────────────────────────────────────

    local function UpdateDisplay()
        btnText:SetText(FormatKeyForDisplay(currentKey))
    end

    local function SetListening(listening)
        isListening = listening
        if listening then
            btnText:SetText("|cffFFD700Press a key...|r")
            button:SetBackdropColor(Theme.accent[1] * 0.3, Theme.accent[2] * 0.3, Theme.accent[3] * 0.3, 1)
            button:SetBackdropBorderColor(Theme.accent[1], Theme.accent[2], Theme.accent[3], 1)
            button:EnableKeyboard(true)
            if onCaptureStart then onCaptureStart() end
        else
            UpdateDisplay()
            button:SetBackdropColor(Theme.bgLight[1], Theme.bgLight[2], Theme.bgLight[3], 1)
            button:SetBackdropBorderColor(Theme.border[1], Theme.border[2], Theme.border[3], 1)
            button:EnableKeyboard(false)
            if onCaptureEnd then onCaptureEnd() end
        end
    end

    -- ── Keyboard Capture ────────────────────────────────────────────────────────────

    button:SetScript("OnKeyDown", function(self, key)
        if not isListening then
            self:SetPropagateKeyboardInput(true)
            return
        end
        -- Consume all key events while listening
        self:SetPropagateKeyboardInput(false)

        -- Escape cancels without changing
        if key == "ESCAPE" then
            SetListening(false)
            return
        end

        -- Ignore modifier-only key presses
        if MODIFIER_KEYS[key] then return end

        -- Build the binding string
        local binding = ""
        if IsShiftKeyDown() then binding = binding .. "SHIFT-" end
        if IsControlKeyDown() then binding = binding .. "CTRL-" end
        if IsAltKeyDown() then binding = binding .. "ALT-" end
        binding = binding .. key

        currentKey = binding
        SetListening(false)
        if onChange then onChange(binding) end
    end)

    -- Click to start / stop listening
    button:SetScript("OnClick", function()
        if isListening then
            SetListening(false)
        else
            SetListening(true)
        end
    end)

    button:SetScript("OnEnter", function(self)
        if not isListening then
            self:SetBackdropBorderColor(Theme.accent[1], Theme.accent[2], Theme.accent[3], 1)
        end
    end)
    button:SetScript("OnLeave", function(self)
        if not isListening then
            self:SetBackdropBorderColor(Theme.border[1], Theme.border[2], Theme.border[3], 1)
        end
    end)

    -- ── Clear Button (✕) ───────────────────────────────────────────────────────────

    local clearBtn = CreateFrame("Button", nil, row, "BackdropTemplate")
    clearBtn:SetSize(24, 24)
    clearBtn:SetPoint("LEFT", button, "RIGHT", 4, 0)
    clearBtn:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    clearBtn:SetBackdropColor(Theme.bgLight[1], Theme.bgLight[2], Theme.bgLight[3], 1)
    clearBtn:SetBackdropBorderColor(Theme.border[1], Theme.border[2], Theme.border[3], 1)

    local clearText = clearBtn:CreateFontString(nil, "OVERLAY")
    clearText:SetPoint("CENTER")
    addon:ApplyThemeFont(clearText, "small")
    clearText:SetText("\195\151")  -- UTF-8 for ✕
    clearText:SetTextColor(Theme.textMuted[1], Theme.textMuted[2], Theme.textMuted[3], 1)

    clearBtn:SetScript("OnClick", function()
        if isListening then SetListening(false) end
        currentKey = ""
        UpdateDisplay()
        if onChange then onChange("") end
    end)
    clearBtn:SetScript("OnEnter", function(self)
        self:SetBackdropBorderColor(Theme.accent[1], Theme.accent[2], Theme.accent[3], 1)
    end)
    clearBtn:SetScript("OnLeave", function(self)
        self:SetBackdropBorderColor(Theme.border[1], Theme.border[2], Theme.border[3], 1)
    end)

    -- Initial display
    UpdateDisplay()

    -- ════════════════════════════════════════════════════════════════════════════════
    -- Part 3: Public API
    -- ════════════════════════════════════════════════════════════════════════════════

    row.SetValue = function(_, key)
        currentKey = key
        if not isListening then UpdateDisplay() end
    end
    row.GetValue = function() return currentKey end

    row.keybindButton = button
    row.clearButton = clearBtn
    return row
end