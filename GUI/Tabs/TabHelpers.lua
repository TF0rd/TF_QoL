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

-- ════════════════════════════════════════════════════════════════════════════════
-- Part 6: Module Catalog (Single source for sidebar sections + Home status)
-- ════════════════════════════════════════════════════════════════════════════════

-- Section order/grouping shared by the sidebar and the Home tab.
GUIFrame.ModuleGroups = {
    { key = "alerts",      id = "alerts_section",      text = "• Alerts",      label = "Alerts" },
    { key = "qol",         id = "qol_section",         text = "• QoL",         label = "QoL" },
    { key = "keybindings", id = "keybindings_section", text = "• Keybindings", label = "Keybindings" },
    { key = "tools",       id = "tools_section",       text = "• Tools",       label = "Tools" },
}

-- One entry per module tab. `settings` names map to the Add*Card helpers
-- above (visibility / font / position / sound); tabs with bespoke layouts
-- leave it nil and build their own cards.
GUIFrame.ModuleCatalog = {
    { id = "PotionAlert",         label = "Potion Alert",          group = "alerts",
      title = "Potion Alert",     dbKey = "potionAlert",
      settings = { "visibility", "font", "position", "sound" },
      about = "Reminds you to use a combat potion when one is available." },
    { id = "LustAlert",           label = "Lust Alert",            group = "alerts",
      title = "Lust Alert",       dbKey = "lustAlert",
      settings = { "visibility", "font", "position", "sound" },
      about = "Displays an alert when Bloodlust, Heroism, Time Warp, or an equivalent haste effect becomes active." },
    { id = "SharedActionBars",    label = "Shared Action Bars",    group = "qol",
      title = "Shared Action Bars",
      about = "Locks all talent loadouts to shared action bars, preventing per-spec bar layouts." },
    { id = "OCETag",              label = "OCE Group Tag",         group = "qol",
      title = "OCE Group Tag",
      about = "Flags Oceanic realm groups in the Premade Groups Finder with an |cFFFF4040[OCE]|r tag." },
    { id = "GroupJoinedReminder", label = "Group Joined Reminder", group = "qol",
      title = "Group Joined Reminder",
      about = "Prints a chat message when you join a Mythic+ or Mythic raid group via the Premade Groups Finder." },
    { id = "ItemUpgradeReminder", label = "Item Upgrade Reminder", group = "qol",
      title = "Item Upgrade Reminder", dbKey = "itemUpgradeReminder",
      settings = { "font", "position" },
      about = "Prints a chat message for each equipped item that can be upgraded to a higher item level for gold only (no crests required), based on your character's and account's high-watermark for that slot." },
    { id = "StealthIndicator",    label = "Stealth Indicator",     group = "qol",
      title = "Stealth Indicator", dbKey = "stealthIndicator",
      settings = { "font", "position" },
      about = "Displays a text indicator on screen when you are in stealth." },
    { id = "BlizzardFrames",      label = "Blizzard Frames",       group = "qol",
      title = "Blizzard Frames",
      about = "Hide Blizzard UI elements and reposition panel frames via click+drag." },
    { id = "ActionBarToggle",     label = "Action Bar Toggle",     group = "keybindings",
      title = "Action Bar Toggle",
      about = "Toggle visibility of action bars with a keybind. Great for screenshots, cinematics, or a cleaner UI." },
    { id = "MountActions",        label = "Mount Actions",         group = "keybindings",
      title = "Mount Actions",
      about = "Bind keys to summon your Repair or Auction House mount." },
    { id = "ConsumableMacros",    label = "Macros",                group = "keybindings",
      title = "Macros",
      about = "Auto-updating macros for Health Potions and Drinks, plus a Power Infusion target helper." },
    { id = "CVarBrowser",         label = "CVar Browser",          group = "tools",
      title = "CVar Browser",
      about = "Browse and modify all game CVars. Values shown in red are non-default." },
    { id = "CharacterViewer",     label = "Character Viewer",      group = "tools",
      title = "Character Viewer",
      about = "Snapshots current character on login. Shows ilvl, Great Vault, currencies, and gold for all known characters." },
    { id = "MuteSounds",          label = "Mute Sounds",           group = "tools",
      title = "Mute Sounds",
      about = "Mute specific game sounds by sound file ID. Toggle preset categories or add custom sound IDs to mute. Changes apply immediately." },
}

-- Rebuild the sidebar tree from the catalog so Sidebar + Home stay in sync.
GUIFrame.SidebarConfig = (function()
    local config = { modules = { { id = "Home", type = "item", text = "Home" } } }
    for _, group in ipairs(GUIFrame.ModuleGroups) do
        local items = {}
        for _, mod in ipairs(GUIFrame.ModuleCatalog) do
            if mod.group == group.key then
                items[#items + 1] = { id = mod.id, text = mod.label }
            end
        end
        config.modules[#config.modules + 1] = {
            id = group.id, type = "header", text = group.text,
            defaultExpanded = true, items = items,
        }
    end
    return config
end)()

-- ════════════════════════════════════════════════════════════════════════════════
-- Part 7: Shared Cards (About, keybind display, action button, settings sets)
-- ════════════════════════════════════════════════════════════════════════════════

-- ── FormatKeyDisplay ─────────────────────────────────────────────────────

function GUIFrame:FormatKeyDisplay(key)
    if not key or key == "" then
        return "|cff" .. addon.Theme.yellowHex .. "Not Bound|r"
    end
    return (key:gsub("-", "+"))
end

-- ── AddAboutCard ─────────────────────────────────────────────────────────

function GUIFrame:AddAboutCard(scrollChild, yOffset, title, text)
    local Theme = addon.Theme
    local card = GUIFrame:CreateCard(scrollChild, title or "About", yOffset)
    card:AddLabel(text or "")
    return yOffset + card:GetContentHeight() + Theme.paddingLarge
end

-- ── AddActionButton ──────────────────────────────────────────────────────

function GUIFrame:AddActionButton(parent, text, onClick, height)
    local Theme = addon.Theme
    local btn = CreateFrame("Button", nil, parent, "BackdropTemplate")
    btn:SetHeight(height or 28)
    btn:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    btn:SetBackdropColor(Theme.accent[1] * 0.3, Theme.accent[2] * 0.3, Theme.accent[3] * 0.3, 1)
    btn:SetBackdropBorderColor(Theme.accent[1], Theme.accent[2], Theme.accent[3], 1)
    btn:EnableMouse(true)
    btn:RegisterForClicks("LeftButtonUp")

    local label = btn:CreateFontString(nil, "OVERLAY")
    label:SetPoint("CENTER")
    addon:ApplyThemeFont(label, "small")
    label:SetText(text)
    label:SetTextColor(Theme.accent[1], Theme.accent[2], Theme.accent[3], 1)

    btn:SetScript("OnEnter", function(self)
        self:SetBackdropColor(Theme.accent[1] * 0.5, Theme.accent[2] * 0.5, Theme.accent[3] * 0.5, 1)
        label:SetTextColor(1, 1, 1, 1)
    end)
    btn:SetScript("OnLeave", function(self)
        self:SetBackdropColor(Theme.accent[1] * 0.3, Theme.accent[2] * 0.3, Theme.accent[3] * 0.3, 1)
        label:SetTextColor(Theme.accent[1], Theme.accent[2], Theme.accent[3], 1)
    end)
    btn:SetScript("OnClick", function()
        if onClick then onClick() end
    end)

    return btn
end

-- ── AddKeybindCard ───────────────────────────────────────────────────────
-- entries: array of { label, key }; read-only display plus a guarded
-- button that opens WoW's Key Bindings panel.

function GUIFrame:AddKeybindCard(scrollChild, yOffset, title, entries, helpText)
    local Theme = addon.Theme
    local card = GUIFrame:CreateCard(scrollChild, title or "Keybind", yOffset)
    for _, entry in ipairs(entries or {}) do
        local line = card:AddLabel((entry.label or "Key") .. ": " .. GUIFrame:FormatKeyDisplay(entry.key))
        line:SetTextColor(Theme.textPrimary[1], Theme.textPrimary[2], Theme.textPrimary[3], 1)
    end
    local openBtn = GUIFrame:AddActionButton(card.content, "Open Keybindings Settings", function()
        if InCombatLockdown() then
            print("|cff" .. Theme.errorHex .. "TF_QoL|r Keybindings cannot be opened in combat.")
            return
        end
        if Settings and Settings.OpenToCategory and Settings.KEYBINDINGS_CATEGORY_ID then
            Settings.OpenToCategory(Settings.KEYBINDINGS_CATEGORY_ID, BINDING_HEADER_TFQoL)
        end
    end, 28)
    card:AddRow(openBtn, 28)
    card:AddLabel(helpText or "Set keybinds in WoW's Key Bindings panel (ESC > Options > Keybindings).")
    return yOffset + card:GetContentHeight() + Theme.paddingLarge
end

-- ── AddModuleSettingsCards ───────────────────────────────────────────────
-- Data-driven settings set: names map to the Part 2-5 card builders.

local SETTINGS_CARD_METHODS = {
    visibility = "AddVisibilityCard",
    font       = "AddFontCard",
    position   = "AddPositionCard",
    sound      = "AddSoundCard",
}

function GUIFrame:AddModuleSettingsCards(scrollChild, yOffset, dbKey, cards)
    for _, name in ipairs(cards or {}) do
        local method = SETTINGS_CARD_METHODS[name]
        if method and self[method] then
            yOffset = self[method](self, scrollChild, yOffset, dbKey)
        end
    end
    return yOffset
end