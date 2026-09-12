-- ════════════════════════════════════════════════════════════════════════════════
-- ConsumableReminder tab — low-stock consumable reminder configuration
-- ════════════════════════════════════════════════════════════════════════════════

local _, addon = ...
local GUIFrame = addon.GUIFrame

local QUESTION_MARK = "Interface\\Icons\\INV_Misc_QuestionMark"

-- One tracked entry = one row: item (icon + name) in column 1,
-- warn-below slider in column 2, Remove in column 3. A muted header row
-- labels the columns, so sliders carry no per-row label and rows show no
-- counts (the on-screen reminder is where counts live).
local ENTRY_H = 30
local ICON_SIZE = 22

-- New entries warn below this until adjusted in the Tracked Items list.
local DEFAULT_THRESHOLD = 20

-- Accepts a plain item ID, an item link, or text containing "item:12345".
local function ParseItemInput(text)
    if not text then return nil end
    text = text:gsub("^%s+", ""):gsub("%s+$", "")
    if text == "" then return nil end
    local fromLink = text:match("item:(%d+)")
    if fromLink then return tonumber(fromLink) end
    return tonumber(text)
end

-- ── Item linking into the Add box ─────────────────────────────
-- Two paths: shift+click (works with default bags via ChatEdit_InsertLink;
-- bag addons like Baganator route shift+clicks to chat themselves, so the
-- hook below never fires for them) and drag-and-drop (addon-agnostic:
-- drag the item from any bag UI onto the box).

local linkBox, linkPlaceholder = nil, nil
local linkHookInstalled = false

local function InstallLinkHook()
    if linkHookInstalled then return end
    if type(hooksecurefunc) ~= "function" then return end
    if type(ChatEdit_InsertLink) ~= "function" then return end
    linkHookInstalled = true
    hooksecurefunc("ChatEdit_InsertLink", function(linkText)
        if type(linkText) == "string" and linkText ~= ""
            and linkBox and linkBox.HasFocus and linkBox:HasFocus() then
            linkBox:Insert(linkText)
            if linkPlaceholder then linkPlaceholder:Hide() end
        end
    end)
end

-- ── Name truncation ───────────────────────────────────────────────
-- Long item names must never push past their column, so the name is trimmed
-- with "…" to its measured width whenever layout runs.

local function FitName(ref)
    if not ref or not ref.label then return end
    local avail = ref.label:GetWidth() or 0
    if avail <= 4 then return end
    ref.label:SetText(ref.full)
    if ref.label:GetStringWidth() <= avail then return end
    local text = ref.full
    local len = #text
    while len > 0 do
        local b = text:byte(len)
        if b >= 128 and b < 192 then
            -- UTF-8 continuation byte: step back without testing a split char
            len = len - 1
        else
            ref.label:SetText(text:sub(1, len) .. "…")
            if ref.label:GetStringWidth() <= avail then return end
            len = len - 1
        end
    end
    ref.label:SetText("…")
end

-- One entry row: [icon + truncated name] [compact slider] [Remove].
local function BuildEntryRow(parent, mod, Theme, entry, index)
    local threshold = tonumber(entry.threshold) or DEFAULT_THRESHOLD
    local row = GUIFrame:CreateRow(parent, ENTRY_H)

    -- Column 1: icon + name (name truncates at the column edge).
    local itemBlock = CreateFrame("Frame", nil, row)

    local iconBorder = CreateFrame("Frame", nil, itemBlock, "BackdropTemplate")
    iconBorder:SetSize(ICON_SIZE, ICON_SIZE)
    iconBorder:SetPoint("TOPLEFT", itemBlock, "TOPLEFT", 0, -4)
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
    icon:SetTexture(mod:GetEntryIcon(entry) or QUESTION_MARK)

    local fullName = mod:GetDisplayName(entry)
    local nameText = itemBlock:CreateFontString(nil, "OVERLAY")
    nameText:SetPoint("LEFT", iconBorder, "RIGHT", 6, 0)
    nameText:SetPoint("RIGHT", itemBlock, "RIGHT", 0, 0)
    nameText:SetJustifyH("LEFT")
    nameText:SetWordWrap(false)
    addon:ApplyThemeFont(nameText, "normal")
    nameText:SetText(fullName)
    nameText:SetTextColor(Theme.textPrimary[1], Theme.textPrimary[2], Theme.textPrimary[3], 1)

    -- Column 2: compact warn-below slider (no label; see the header row).
    local warnSlider = GUIFrame:CreateSlider(row, "", 1, 200, 1, threshold,
        function(val) mod:SetThreshold(index, val) end, true)

    -- Column 3: Remove.
    local removeBtn = GUIFrame:AddActionButton(row, "Remove", function()
        mod:RemoveItem(index)
        GUIFrame:RefreshContent()
    end, 28)
    removeBtn.explicitHeight = true

    row:AddWidget(itemBlock, 0.48)
    row:AddWidget(warnSlider, 0.32)
    row:AddWidget(removeBtn, 0.20, nil, 0, -1)

    -- Refit the name whenever the row is (re)sized; also once now in case
    -- layout already ran.
    local nameRef = { label = nameText, full = fullName }
    row:HookScript("OnSizeChanged", function() FitName(nameRef) end)
    FitName(nameRef)

    return row
end

-- Muted "Item | Warn Below" header over the entry columns.
local function BuildHeaderRow(parent, Theme)
    local row = GUIFrame:CreateRow(parent, 16)
    local function Header(text)
        local fs = parent:CreateFontString(nil, "OVERLAY")
        fs:SetJustifyH("LEFT")
        addon:ApplyThemeFont(fs, "small")
        fs:SetText(text)
        fs:SetTextColor(Theme.textMuted[1], Theme.textMuted[2], Theme.textMuted[3], 1)
        return fs
    end
    row:AddWidget(Header("Item"), 0.48)
    row:AddWidget(Header("Warn Below"), 0.32)
    row:AddWidget(Header(""), 0.20)
    return row
end

-- Untracked consumables currently in the player's bags as dropdown options,
-- grouped by rank (icon + base name, alphabetical, uncached names last).
-- This is the primary add path: it needs no shift+click or drag cooperation
-- from whatever bag addon is installed.
local CONSUMABLE_CLASS = (Enum and Enum.ItemClass and Enum.ItemClass.Consumable) or 0

-- Consumables only (potions, flasks, food, etc.), by locale-safe numeric
-- class ID. Unknown items (classID nil, not yet seen this session) are
-- included optimistically rather than hidden.
local function IsConsumableOrUnknown(itemID)
    if type(GetItemInfoInstant) ~= "function" then return true end
    local _, _, _, _, _, classID = GetItemInfoInstant(itemID)
    return classID == nil or classID == CONSUMABLE_CLASS
end
-- Cached name only (requests a load when missing, for next time).
local function PeekBagName(mod, itemID)
    local name = mod:PeekItemName(itemID)
    if type(name) == "string" and name ~= "" then return name end
    mod:RequestItemName(itemID)
    return nil
end

local function ScanBagOptions(mod)
    local ids = {}
    if C_Container and C_Container.GetContainerNumSlots and C_Container.GetContainerItemID then
        for bag = 0, 4 do
            local slots = C_Container.GetContainerNumSlots(bag) or 0
            for slot = 1, slots do
                local id = C_Container.GetContainerItemID(bag, slot)
                if id and not ids[id] and not mod:FindItem(id) then
                    ids[id] = true
                end
            end
        end
    end
    -- Group ranks under one option: value is the colon-joined rank IDs,
    -- so picking it tracks every rank at once.
    local groups, singles = {}, {}
    for id in pairs(ids) do
        if IsConsumableOrUnknown(id) then
            local name = PeekBagName(mod, id)
            local base = name and mod:NormalizeName(name) or nil
            if base then
                local g = groups[base]
                if not g then
                    g = { ids = {}, icon = nil }
                    groups[base] = g
                end
                g.ids[#g.ids + 1] = id
                if not g.icon then g.icon = mod:GetItemIcon(id) end
            else
                singles[#singles + 1] = id
            end
        end
    end
    local list = {}
    for base, g in pairs(groups) do
        table.sort(g.ids)
        local label = base
        if #g.ids > 1 then
            label = label .. string.format("  |cff808080(%d ranks)|r", #g.ids)
        end
        list[#list + 1] = {
            value = table.concat(g.ids, ":"),
            sortKey = base,
            text = string.format("|T%s:14|t %s", g.icon or QUESTION_MARK, label),
        }
    end
    for _, id in ipairs(singles) do
        list[#list + 1] = {
            value = tostring(id),
            sortKey = "~~" .. tostring(id),
            text = string.format("|T%s:14|t Item %s", QUESTION_MARK, tostring(id)),
        }
    end
    table.sort(list, function(a, b) return a.sortKey < b.sortKey end)
    return list
end

GUIFrame:RegisterContent("ConsumableReminder", function(scrollChild, yOffset)
    local Theme = addon.Theme
    local mod = addon.modules["ConsumableReminder"]

    -- ── About card ──────────────────────────────────────────────────

    yOffset = GUIFrame:AddAboutCard(scrollChild, yOffset, "About",
        "Shows an on-screen reminder listing each tracked consumable whose bag count falls below its threshold, so you know when to stock up on health potions, combat potions, food, and more. Different ranks of the same consumable are counted together, and counts update automatically as your bags change.")

    -- ── Module header (with location toggle) ────────────────────────

    local card = GUIFrame:CreateCard(scrollChild, "Consumable Reminder", yOffset)
    GUIFrame:AddModuleHeader(card, "ConsumableReminder")

    -- "Only in Silvermoon" lives here, same as Lust Alert's extra option.
    local silverRow = GUIFrame:CreateCheckbox(card.content, "Only show in Silvermoon City",
        TFQoLDB.consumableReminder.onlySilvermoon == true,
        function(val)
            TFQoLDB.consumableReminder.onlySilvermoon = val
            if mod and mod.ForceCheck then mod:ForceCheck() end
        end)
    card:AddRow(silverRow, 36)

    yOffset = yOffset + card:GetContentHeight() + Theme.paddingLarge

    -- Bail out if the module table is unavailable (options below need it)
    if not mod or not mod.GetItems then
        local warnCard = GUIFrame:CreateCard(scrollChild, "Tracked Items", yOffset)
        warnCard:AddLabel("ConsumableReminder module is not loaded.")
        yOffset = yOffset + warnCard:GetContentHeight() + Theme.paddingLarge
        return yOffset
    end

    -- ── Add Item card ───────────────────────────────────────────────
    -- Input + Add share one multi-column row (CreateRow distributes real
    -- widths). New entries warn below 20; adjust per item below.

    local addCard = GUIFrame:CreateCard(scrollChild, "Add Item", yOffset)
    addCard:AddLabel("Pick a consumable from your bags, or enter one manually below. Different ranks of the same consumable combine into one entry; new entries warn below 20.")

    -- Primary path: dropdown of what's actually in the bags.
    local bagOptions = ScanBagOptions(mod)
    if #bagOptions > 0 then
        local bagDropdown = GUIFrame:CreateDropdown(addCard.content, "From bags",
            bagOptions, nil,
            function(value)
                -- Grouped value: every rank ID, colon-joined. The first add
                -- absorbs the rest from the bags; the loop covers banked ranks.
                local added = false
                for idStr in tostring(value):gmatch("(%d+)") do
                    if mod:AddItem(tonumber(idStr), DEFAULT_THRESHOLD) then
                        added = true
                    end
                end
                if added then
                    GUIFrame:RefreshContent()
                end
            end)
        addCard:AddRow(bagDropdown, 34)
    else
        addCard:AddLabel("No untracked items in your bags — enter one manually below.")
    end

    local function doAdd(inputBox, placeholder)
        local itemID = ParseItemInput(inputBox:GetText())
        if itemID and itemID > 0 then
            if mod:AddItem(itemID, DEFAULT_THRESHOLD) then
                inputBox:SetText("")
                inputBox:ClearFocus()
                placeholder:Show()
                GUIFrame:RefreshContent()
            end
        end
    end

    local inputRow = GUIFrame:CreateRow(addCard.content, 30)

    local inputContainer = CreateFrame("Frame", nil, inputRow, "BackdropTemplate")
    inputContainer:SetHeight(24)
    inputContainer.explicitHeight = true
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

    local placeholder = inputContainer:CreateFontString(nil, "OVERLAY")
    placeholder:SetPoint("LEFT", inputContainer, "LEFT", 6, 0)
    placeholder:SetFontObject("GameFontNormal")
    placeholder:SetText("Item ID, link, drag, or shift+click")
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
    inputBox:SetScript("OnTextChanged", function(self)
        if self:GetText() == "" then
            placeholder:Show()
        else
            placeholder:Hide()
        end
    end)
    inputBox:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
    end)
    inputBox:SetScript("OnEnterPressed", function(self)
        doAdd(self, placeholder)
    end)
    -- Drag-and-drop: works when the bag UI puts the item on the game cursor
    -- (default bags). Bag addons with custom drag handling may not.
    inputBox:SetScript("OnReceiveDrag", function(self)
        local cursorType, cursorID = GetCursorInfo()
        if cursorType == "item" and cursorID then
            self:SetText(tostring(cursorID))
            ClearCursor()
        end
    end)

    -- Route shift+clicked item links into this box while it has focus.
    linkBox, linkPlaceholder = inputBox, placeholder
    InstallLinkHook()

    local addBtn = GUIFrame:AddActionButton(inputRow, "Add", function()
        doAdd(inputBox, placeholder)
    end, 28)
    addBtn.explicitHeight = true

    inputRow:AddWidget(inputContainer, 0.62)
    inputRow:AddWidget(addBtn, 0.38)
    addCard:AddRow(inputRow, 30)

    yOffset = yOffset + addCard:GetContentHeight() + Theme.paddingLarge

    -- ── Tracked Items card ──────────────────────────────────────────

    local trackCard = GUIFrame:CreateCard(scrollChild, "Tracked Items", yOffset)
    local items = mod:GetItems()
    if #items == 0 then
        trackCard:AddLabel("Nothing tracked yet — add your first consumable above.")
    else
        trackCard:AddRow(BuildHeaderRow(trackCard.content, Theme), 16)
        -- Display order: ascending by lowest item ID. The sort is
        -- display-only — rows keep their real indices so remove and
        -- threshold callbacks still hit the right entry.
        local order = {}
        for index in ipairs(items) do order[#order + 1] = index end
        local function LowestID(entry)
            local low
            for _, id in ipairs(entry.itemIDs or {}) do
                id = tonumber(id)
                if id and (not low or id < low) then low = id end
            end
            return low or math.huge
        end
        table.sort(order, function(a, b) return LowestID(items[a]) < LowestID(items[b]) end)
        for _, index in ipairs(order) do
            trackCard:AddRow(BuildEntryRow(trackCard.content, mod, Theme, items[index], index), ENTRY_H)
        end
    end

    yOffset = yOffset + trackCard:GetContentHeight() + Theme.paddingLarge

    -- ── Settings cards ──────────────────────────────────────────────

    yOffset = GUIFrame:AddModuleSettingsCards(scrollChild, yOffset,
        "consumableReminder", { "font", "position" })

    return yOffset
end)
