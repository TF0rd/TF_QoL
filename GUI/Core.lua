local _, addon = ...
addon.GUIFrame = addon.GUIFrame or {}
local GUIFrame = addon.GUIFrame

local type = type
local CreateFrame = CreateFrame
local tostring = tostring
local pcall = pcall
local table_insert = table.insert
local wipe = wipe
local pairs = pairs
local ipairs = ipairs

-- ════════════════════════════════════════════════════════════════════════════════════
-- Part 1: Content Registry (Register/Fire builders, cleanup, and close callbacks)
-- ════════════════════════════════════════════════════════════════════════════════════

GUIFrame.ContentBuilders = {}
GUIFrame.contentCleanupCallbacks = {}
GUIFrame.onCloseCallbacks = {}

function GUIFrame:RegisterContent(itemId, builderFunc)
    self.ContentBuilders[itemId] = builderFunc
end

function GUIFrame:RegisterContentCleanup(key, callback)
    if type(key) == "string" and type(callback) == "function" then
        self.contentCleanupCallbacks[key] = callback
    end
end

function GUIFrame:RegisterOnCloseCallback(key, callback)
    if type(key) == "string" and type(callback) == "function" then
        self.onCloseCallbacks[key] = callback
    end
end

function GUIFrame:FireOnCloseCallbacks()
    for _, callback in pairs(self.onCloseCallbacks) do
        pcall(callback)
    end
end

-- ════════════════════════════════════════════════════════════════════════════════════
-- Part 2: Card Widget (Bordered container with header, rows, labels, separators)
-- ════════════════════════════════════════════════════════════════════════════════════

function GUIFrame:CreateCard(parent, title, yOffset, width)
    local Theme = addon.Theme
    local card = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    card:EnableMouse(false)

    if width then
        card:SetWidth(width)
        card:SetPoint("TOPLEFT", parent, "TOPLEFT", Theme.paddingSmall, -(yOffset or 0) + Theme.paddingSmall)
    else
        card:SetPoint("TOPLEFT", parent, "TOPLEFT", Theme.paddingSmall, -(yOffset or 0) + Theme.paddingSmall)
        card:SetPoint("RIGHT", parent, "RIGHT", -Theme.paddingSmall, 0)
    end

    card:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = Theme.borderSize,
    })
    card:SetBackdropColor(Theme.bgDark[1], Theme.bgDark[2], Theme.bgDark[3], Theme.bgDark[4])
    card:SetBackdropBorderColor(Theme.border[1], Theme.border[2], Theme.border[3], Theme.border[4])

    card.contentHeight = 0
    card.rows = {}

    local headerHeight = 0
    if title and title ~= "" then
        headerHeight = 32
        local header = CreateFrame("Frame", nil, card, "BackdropTemplate")
        header:SetHeight(headerHeight)
        header:SetPoint("TOPLEFT", card, "TOPLEFT", 0, 0)
        header:SetPoint("TOPRIGHT", card, "TOPRIGHT", 0, 0)
        header:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            edgeSize = Theme.borderSize,
        })
        header:SetBackdropColor(Theme.bgLight[1], Theme.bgLight[2], Theme.bgLight[3], Theme.bgLight[4])
        header:SetBackdropBorderColor(Theme.border[1], Theme.border[2], Theme.border[3], Theme.border[4])
        card.header = header

        local titleText = header:CreateFontString(nil, "OVERLAY")
        titleText:SetPoint("LEFT", header, "LEFT", Theme.paddingMedium, 0)
        addon:ApplyThemeFont(titleText, "large")
        titleText:SetText(title)
        titleText:SetTextColor(Theme.secondaryAccent[1], Theme.secondaryAccent[2], Theme.secondaryAccent[3], 1)
        card.titleText = titleText
    end
    card.headerHeight = headerHeight

    -- borderSubtle separator between header and content
    if headerHeight > 0 then
        local headerSeparator = card:CreateTexture(nil, "ARTWORK")
        headerSeparator:SetHeight(Theme.borderSize)
        headerSeparator:SetPoint("TOPLEFT", card, "TOPLEFT", 0, -headerHeight)
        headerSeparator:SetPoint("TOPRIGHT", card, "TOPRIGHT", 0, -headerHeight)
        headerSeparator:SetColorTexture(Theme.borderSubtle[1], Theme.borderSubtle[2], Theme.borderSubtle[3], 1)
        card.headerSeparator = headerSeparator
    end

    local content = CreateFrame("Frame", nil, card, "BackdropTemplate")
    content:SetPoint("TOPLEFT", card, "TOPLEFT", Theme.paddingMedium, -headerHeight - Theme.paddingMedium)
    content:SetPoint("TOPRIGHT", card, "TOPRIGHT", -Theme.paddingMedium, -headerHeight - Theme.paddingMedium)
    content:SetHeight(1)
    content:EnableMouse(false)
    content:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8" })
    content:SetBackdropColor(Theme.bgMedium[1], Theme.bgMedium[2], Theme.bgMedium[3], Theme.bgMedium[4])
    card.content = content
    card.currentY = 0

    -- ── AddRow ──────────────────────────────────────────────────────────────────────

    function card:AddRow(widget, height, spacing)
        local T = addon.Theme
        height = height or widget:GetHeight() or 24
        spacing = spacing or T.paddingMedium
        widget:SetParent(self.content)
        widget:ClearAllPoints()
        widget:SetPoint("TOPLEFT", self.content, "TOPLEFT", 0, -self.currentY)
        widget:SetPoint("TOPRIGHT", self.content, "TOPRIGHT", 0, -self.currentY)
        self.currentY = self.currentY + height + spacing
        table_insert(self.rows, widget)
        self.content:SetHeight(self.currentY)
        self:UpdateHeight()
        return widget
    end

    -- ── AddLabel ────────────────────────────────────────────────────────────────────

    function card:AddLabel(text)
        local T = addon.Theme
        local label = self.content:CreateFontString(nil, "OVERLAY")
        label:SetPoint("TOPLEFT", self.content, "TOPLEFT", 0, -self.currentY)
        label:SetPoint("TOPRIGHT", self.content, "TOPRIGHT", 0, -self.currentY)
        label:SetJustifyH("LEFT")
        addon:ApplyThemeFont(label, "normal")
        label:SetText(text)
        label:SetTextColor(T.textMuted[1], T.textMuted[2], T.textMuted[3], 1)
        local height = label:GetStringHeight() or 14
        self.currentY = self.currentY + height + T.paddingSmall
        self.content:SetHeight(self.currentY)
        self:UpdateHeight()
        return label
    end

    -- ── AddSeparator ────────────────────────────────────────────────────────────────

    function card:AddSeparator()
        local T = addon.Theme
        local sep = self.content:CreateTexture(nil, "ARTWORK")
        sep:SetHeight(T.borderSize)
        sep:SetPoint("TOPLEFT", self.content, "TOPLEFT", 0, -self.currentY - T.paddingSmall)
        sep:SetPoint("TOPRIGHT", self.content, "TOPRIGHT", 0, -self.currentY - T.paddingSmall)
        sep:SetColorTexture(T.border[1], T.border[2], T.border[3], 0.5)
        self.currentY = self.currentY + T.borderSize + T.paddingSmall * 2
        self.content:SetHeight(self.currentY)
        self:UpdateHeight()
        return sep
    end

    -- ── AddSpacing ──────────────────────────────────────────────────────────────────

    function card:AddSpacing(amount)
        local T = addon.Theme
        amount = amount or T.paddingMedium
        self.currentY = self.currentY + amount
        self.content:SetHeight(self.currentY)
        self:UpdateHeight()
    end

    -- ── SetAccent ───────────────────────────────────────────────────────────────────

    local accentStripe = card:CreateTexture(nil, "OVERLAY")
    accentStripe:SetWidth(2)
    accentStripe:SetPoint("TOPLEFT", card, "TOPLEFT", 0, 0)
    accentStripe:SetPoint("BOTTOMLEFT", card, "BOTTOMLEFT", 0, 0)
    accentStripe:SetColorTexture(Theme.accent[1], Theme.accent[2], Theme.accent[3], 1)
    accentStripe:Hide()
    card._accentStripe = accentStripe

    function card:SetAccent(show)
        if show then
            self._accentStripe:Show()
        else
            self._accentStripe:Hide()
        end
    end

    -- ── UpdateHeight / GetContentHeight ─────────────────────────────────────────────

    function card:UpdateHeight()
        local T = addon.Theme
        local totalHeight = self.headerHeight + self.currentY + T.paddingMedium * 2
        self:SetHeight(totalHeight)
        self.contentHeight = totalHeight
    end

    function card:GetContentHeight()
        return self.contentHeight
    end

    function card:Reset()
        for _, row in ipairs(self.rows) do
            if row.Hide then row:Hide() end
            if row.SetParent then row:SetParent(nil) end
        end
        wipe(self.rows)
        self.currentY = 0
        self.contentHeight = 0
        self.content:SetHeight(1)
        local T = addon.Theme
        self:SetHeight(self.headerHeight + T.paddingMedium * 2)
    end

    card:UpdateHeight()
    return card
end

-- ════════════════════════════════════════════════════════════════════════════════════
-- Part 3: Row Widget (Horizontal layout with proportional children)
-- ════════════════════════════════════════════════════════════════════════════════════

function GUIFrame:CreateRow(parent, height)
    local Theme = addon.Theme
    height = height or 24
    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(height)
    row:EnableMouse(false)
    row.widgets = {}
    row.nextX = 0

    function row:AddWidget(widget, widthPct, spacing, xOffset, yOffset)
        local T = addon.Theme
        widthPct = widthPct or 0.5
        spacing = spacing or T.paddingSmall
        xOffset = xOffset or 0
        yOffset = yOffset or 0
        widget:SetParent(self)
        widget:ClearAllPoints()
        widget:SetPoint("TOPLEFT", self, "TOPLEFT", self.nextX + xOffset, yOffset)
        if not widget.explicitHeight then
            widget:SetHeight(height)
        end
        widget._widthPct = widthPct
        widget._spacing = spacing
        widget._xOffset = xOffset
        widget._yOffset = yOffset
        table_insert(self.widgets, widget)
        self.nextX = self.nextX + 10
    end

    row:SetScript("OnSizeChanged", function(self, width)
        local x = 0
        for _, widget in ipairs(self.widgets) do
            local widgetWidth = width * widget._widthPct - (widget._spacing or 0)
            widget:ClearAllPoints()
            widget:SetPoint("TOPLEFT", self, "TOPLEFT", x + (widget._xOffset or 0), widget._yOffset or 0)
            widget:SetWidth(widgetWidth)
            x = x + widgetWidth + (widget._spacing or addon.Theme.paddingSmall)
        end
    end)

    return row
end