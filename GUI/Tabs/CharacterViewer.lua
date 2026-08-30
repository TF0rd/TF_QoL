-- ════════════════════════════════════════════════════════════════════════════════
-- CharacterViewer tab — settings for the per-character snapshot viewer
-- (Module enable/disable + keybind display + data management actions)
-- ════════════════════════════════════════════════════════════════════════════════

local _, addon = ...
local GUIFrame = addon.GUIFrame

local function FormatKeyForDisplay(key)
    if not key or key == "" then return "|cffF9E2AFNot Bound|r" end
    return key:gsub("-", "+")
end

local TOGGLE_ACTION = "CLICK TFQoL_CharacterViewer_Toggle:LeftButton"

GUIFrame:RegisterContent("CharacterViewer", function(scrollChild, yOffset)
    local Theme = addon.Theme

    -- ── About card ──────────────────────────────────────────────────────────
    local aboutCard = GUIFrame:CreateCard(scrollChild, "About", yOffset)
    aboutCard:AddLabel(
        "Snapshots current character on login. Shows ilvl, Great Vault, currencies, and gold for all known characters.")
    yOffset = yOffset + aboutCard:GetContentHeight() + Theme.paddingLarge

    -- ── Module header (enable + test-mode-disabled module overlay) ──────────
    local headerCard = GUIFrame:CreateCard(scrollChild, "Character Viewer", yOffset)
    GUIFrame:AddModuleHeader(headerCard, "CharacterViewer")
    yOffset = yOffset + headerCard:GetContentHeight() + Theme.paddingLarge

    -- ── Window card ─────────────────────────────────────────────────────────
    local windowCard = GUIFrame:CreateCard(scrollChild, "Window", yOffset)
    local cvdb = TFQoLDB.characterViewer
    local scaleRow = GUIFrame:CreateSlider(windowCard.content, "Window Scale", 0.5, 1.5, 0.05,
        cvdb.scale or 1.0,
        function(value)
            local characterViewer = addon.modules and addon.modules.CharacterViewer
            if characterViewer and characterViewer.UI then
                characterViewer.UI:SetScale(value)
            end
        end)
    windowCard:AddRow(scaleRow, 36)
    windowCard:AddLabel("Adjust the Character Viewer popup size without changing its layout.")
    yOffset = yOffset + windowCard:GetContentHeight() + Theme.paddingLarge

    -- ── Keybind card ────────────────────────────────────────────────────────
    local currentKey = GetBindingKey(TOGGLE_ACTION) or ""
    local kbCard = GUIFrame:CreateCard(scrollChild, "Keybind", yOffset)

    local keyLabel = kbCard:AddLabel("Toggle Key: " .. FormatKeyForDisplay(currentKey))
    keyLabel:SetTextColor(Theme.textPrimary[1], Theme.textPrimary[2], Theme.textPrimary[3], 1)
    kbCard._keyLabel = keyLabel

    local openBtn = CreateFrame("Button", nil, kbCard.content, "BackdropTemplate")
    openBtn:SetHeight(28)
    openBtn:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    openBtn:SetBackdropColor(Theme.bgLight[1], Theme.bgLight[2], Theme.bgLight[3], 1)
    openBtn:SetBackdropBorderColor(Theme.border[1], Theme.border[2], Theme.border[3], 1)
    local btnText = openBtn:CreateFontString(nil, "OVERLAY")
    btnText:SetPoint("CENTER")
    addon:ApplyThemeFont(btnText, "small")
    btnText:SetText("Open Keybindings Settings")
    btnText:SetTextColor(Theme.accent[1], Theme.accent[2], Theme.accent[3], 1)
    openBtn:SetScript("OnEnter", function(self)
        self:SetBackdropBorderColor(Theme.accent[1], Theme.accent[2], Theme.accent[3], 1)
    end)
    openBtn:SetScript("OnLeave", function(self)
        self:SetBackdropBorderColor(Theme.border[1], Theme.border[2], Theme.border[3], 1)
    end)
    openBtn:SetScript("OnClick", function()
        if Settings and Settings.OpenToCategory and Settings.KEYBINDINGS_CATEGORY_ID then
            Settings.OpenToCategory(Settings.KEYBINDINGS_CATEGORY_ID, BINDING_HEADER_TFQoL)
        end
    end)
    kbCard:AddRow(openBtn, 28)

    kbCard:AddLabel("Set keybinds in WoW's Key Bindings panel (ESC > Options > Keybindings).")
    yOffset = yOffset + kbCard:GetContentHeight() + Theme.paddingLarge

    -- ── Data card ───────────────────────────────────────────────────────────
    local dataCard = GUIFrame:CreateCard(scrollChild, "Stored Data", yOffset)

    local countLabel = dataCard:AddLabel("Tracked characters: 0")
    local db = TFQoLDB.characterViewer
    if db and db.chars then
        local n = 0
        for _ in pairs(db.chars) do n = n + 1 end
        countLabel:SetText("Tracked characters: " .. tostring(n))
    end
    dataCard:AddLabel("Each character is recorded on login. Last-seen timestamps show freshness.")

    local characterOptions = {}
    if db and db.chars then
        for guid, char in pairs(db.chars) do
            characterOptions[#characterOptions + 1] = { value = guid, text = char.name or guid }
        end
        table.sort(characterOptions, function(a, b) return a.text < b.text end)
    end
    local selectedGUID = characterOptions[1] and characterOptions[1].value
    local characterRow = GUIFrame:CreateDropdown(dataCard.content, "Character", characterOptions,
        selectedGUID, function(value)
            dataCard._selectedGUID = value
        end)
    dataCard:AddRow(characterRow, 34)
    dataCard._selectedGUID = selectedGUID

    local clearBtn = CreateFrame("Button", nil, dataCard.content, "BackdropTemplate")
    clearBtn:SetHeight(28)
    clearBtn:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    clearBtn:SetBackdropColor(Theme.bgLight[1], Theme.bgLight[2], Theme.bgLight[3], 1)
    clearBtn:SetBackdropBorderColor(Theme.border[1], Theme.border[2], Theme.border[3], 1)
    local clearText = clearBtn:CreateFontString(nil, "OVERLAY")
    clearText:SetPoint("CENTER")
    addon:ApplyThemeFont(clearText, "small")
    clearText:SetText("Clear Selected Character Data")
    clearText:SetTextColor(Theme.error[1], Theme.error[2], Theme.error[3], 1)
    clearBtn:SetScript("OnEnter", function(self)
        self:SetBackdropBorderColor(Theme.error[1], Theme.error[2], Theme.error[3], 1)
    end)
    clearBtn:SetScript("OnLeave", function(self)
        self:SetBackdropBorderColor(Theme.border[1], Theme.border[2], Theme.border[3], 1)
    end)
    clearBtn:SetScript("OnClick", function()
        local guid = dataCard._selectedGUID
        if TFQoLDB.characterViewer and guid and TFQoLDB.characterViewer.chars[guid] then
            TFQoLDB.characterViewer.chars[guid] = nil
            clearText:SetText("Character data cleared.")
            local n = 0
            for _ in pairs(TFQoLDB.characterViewer.chars) do n = n + 1 end
            countLabel:SetText("Tracked characters: " .. tostring(n))
        elseif not guid then
            clearText:SetText("No character data to clear.")
        end
    end)
    dataCard:AddRow(clearBtn, 28)

    yOffset = yOffset + dataCard:GetContentHeight() + Theme.paddingLarge

    return yOffset
end)
