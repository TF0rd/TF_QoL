local _, addon = ...
addon.GUIFrame = addon.GUIFrame or {}
local GUIFrame = addon.GUIFrame

local pcall = pcall
local pairs = pairs
local CreateFrame = CreateFrame

local ADDON_NAME = "TF QoL"
local MEDIA = "Interface\\AddOns\\TF_QoL\\Media\\GUITextures\\"

-- ════════════════════════════════════════════════════════════════════════════════════
-- Part 1: State & SidebarConfig (Navigation sidebar item tree)
-- ════════════════════════════════════════════════════════════════════════════════════

GUIFrame.selectedTab = "modules"
GUIFrame.selectedSidebarItem = nil
GUIFrame.sidebarExpanded = GUIFrame.sidebarExpanded or {}
GUIFrame.SidebarConfig = {
    modules = {
        { id = "Home", type = "item", text = "Home" },
        {
            id = "alerts_section",
            type = "header",
            text = "• Alerts",
            defaultExpanded = true,
            items = {
                { id = "PotionAlert",   text = "Potion Alert" },
                { id = "LustAlert",     text = "Lust Alert" },
            }
        },
        {
            id = "qol_section",
            type = "header",
            text = "• QoL",
            defaultExpanded = true,
            items = {
                { id = "SharedActionBars", text = "Shared Action Bars" },
                { id = "OCETag",              text = "OCE Group Tag" },
                { id = "GroupJoinedReminder",  text = "Group Joined Reminder" },
                { id = "ItemUpgradeReminder", text = "Item Upgrade Reminder" },
                { id = "StealthIndicator",    text = "Stealth Indicator" },
                { id = "BlizzardFrames",      text = "Blizzard Frames" },
            }
        },
        {
            id = "keybindings_section",
            type = "header",
            text = "• Keybindings",
            defaultExpanded = true,
            items = {
                { id = "ActionBarToggle",     text = "Action Bar Toggle" },
                { id = "MountActions",        text = "Mount Actions" },
                { id = "ConsumableMacros",    text = "Macros" },
            }
        },
        {
            id = "tools_section",
            type = "header",
            text = "• Tools",
            defaultExpanded = true,
            items = {
                { id = "CVarBrowser", text = "CVar Browser" },
                { id = "CharacterViewer", text = "Character Viewer" },
                { id = "MuteSounds", text = "Mute Sounds" },
            }
        },
    }
}

-- ════════════════════════════════════════════════════════════════════════════════════
-- Part 2: Show / Hide / Toggle (Top-level frame lifecycle)
-- ════════════════════════════════════════════════════════════════════════════════════

function GUIFrame:Show()
    if not self.mainFrame then
        self:CreateMainFrame()
    end
    self:InitializeSidebarExpansion()
    self.mainFrame:Show()
    self:RefreshSidebarImmediate()
    self:SelectSidebarItem(self.selectedSidebarItem or "Home")
    addon.GUIOpen = true
end

function GUIFrame:Hide()
    if self.mainFrame then
        self.mainFrame:Hide()
    end
end

function GUIFrame:Toggle()
    if self.mainFrame and self.mainFrame:IsShown() then
        self:Hide()
    else
        self:Show()
    end
end

-- ════════════════════════════════════════════════════════════════════════════════════
-- Part 3: Main Frame (Top-level movable/resizable frame with border overlay)
-- ════════════════════════════════════════════════════════════════════════════════════

function GUIFrame:CreateMainFrame()
    if self.mainFrame then return self.mainFrame end

    local Theme = addon.Theme

    local frame = CreateFrame("Frame", "TFQoL_GUIFrame", UIParent, "BackdropTemplate")
    frame:SetSize(Theme.sidebarWidth + Theme.contentWidth, 900)
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, 50)
    frame:SetFrameStrata("DIALOG")
    frame:SetToplevel(true)
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:SetResizable(true)
    local fixedWidth = Theme.sidebarWidth + Theme.contentWidth
    frame:SetResizeBounds(fixedWidth, 400, fixedWidth, 2000)
    frame:EnableMouse(true)

    frame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = Theme.borderSize,
    })
    frame:SetBackdropColor(Theme.bgCrust[1], Theme.bgCrust[2], Theme.bgCrust[3], Theme.bgCrust[4])
    frame:SetBackdropBorderColor(Theme.border[1], Theme.border[2], Theme.border[3], 1)

    -- Overlay for dropdowns to render over scrollframes
    addon.GUIOverlay = CreateFrame("Frame", nil, UIParent)
    addon.GUIOverlay:SetAllPoints(UIParent)
    addon.GUIOverlay:SetFrameStrata("TOOLTIP")
    addon.GUIOverlay:SetFrameLevel(1)
    addon.GUIOverlay:EnableMouse(false)

    self:CreateHeader(frame)
    self:CreateFooter(frame)
    self:CreateContentArea(frame)
    self:CreateSidebar(frame)

    -- Border overlay (4-sided texture border)
    local borderFrame = CreateFrame("Frame", nil, frame)
    borderFrame:SetAllPoints(frame)
    borderFrame:SetFrameStrata("TOOLTIP")
    borderFrame:SetFrameLevel(frame:GetFrameLevel() + 100)
    for _, info in ipairs({
        { "TOPLEFT",     "TOPRIGHT",    "SetHeight", Theme.borderSize, "top" },
        { "BOTTOMLEFT",  "BOTTOMRIGHT", "SetHeight", Theme.borderSize, "bottom" },
        { "TOPLEFT",     "BOTTOMLEFT",  "SetWidth",  Theme.borderSize, "left" },
        { "TOPRIGHT",    "BOTTOMRIGHT", "SetWidth",  Theme.borderSize, "right" },
    }) do
        local t = borderFrame:CreateTexture(nil, "OVERLAY", nil, 7)
        t[info[3]](t, info[4])
        t:SetPoint(info[1], frame, info[1], 0, 0)
        t:SetPoint(info[2], frame, info[2], 0, 0)
        t:SetColorTexture(Theme.border[1], Theme.border[2], Theme.border[3], 1)
    end

    frame:SetScript("OnKeyDown", function(self, key)
        if key == "ESCAPE" then
            if not InCombatLockdown() then
                self:SetPropagateKeyboardInput(false)
            end
            GUIFrame:Hide()
        else
            if not InCombatLockdown() then
                self:SetPropagateKeyboardInput(true)
            end
        end
    end)
    frame:EnableKeyboard(true)

    frame:SetScript("OnHide", function()
        if addon.GUIOpen then
            for _, callback in pairs(GUIFrame.contentCleanupCallbacks) do pcall(callback) end
            GUIFrame:FireOnCloseCallbacks()
            addon.GUIOpen = false
        end
    end)

    frame:Hide()
    self.mainFrame = frame
    return frame
end

-- ════════════════════════════════════════════════════════════════════════════════════
-- Part 4: Header (Title bar with close/home buttons, drag-to-move)
-- ════════════════════════════════════════════════════════════════════════════════════

function GUIFrame:CreateHeader(parent)
    local Theme = addon.Theme
    local header = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    header:SetHeight(Theme.headerHeight)
    header:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)
    header:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, 0)
    header:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8" })
    header:SetBackdropColor(Theme.bgDark[1], Theme.bgDark[2], Theme.bgDark[3], Theme.bgDark[4])

    local bottomBorder = header:CreateTexture(nil, "BORDER")
    bottomBorder:SetHeight(Theme.borderSize)
    bottomBorder:SetPoint("BOTTOMLEFT", header, "BOTTOMLEFT", 0, 0)
    bottomBorder:SetPoint("BOTTOMRIGHT", header, "BOTTOMRIGHT", 0, 0)
    bottomBorder:SetColorTexture(Theme.border[1], Theme.border[2], Theme.border[3], 1)

    local titleText = header:CreateFontString(nil, "OVERLAY")
    titleText:SetPoint("LEFT", header, "LEFT", Theme.paddingLarge, 0)
    addon:ApplyThemeFont(titleText, "large")
    titleText:SetText("TF |cffFFFFFFQoL|r")
    titleText:SetTextColor(Theme.accent[1], Theme.accent[2], Theme.accent[3], 1)

    -- Close button
    local closeBtn = CreateFrame("Button", nil, header)
    closeBtn:SetSize(22, 22)
    closeBtn:SetPoint("RIGHT", header, "RIGHT", -6, 0)
    local closeTex = closeBtn:CreateTexture(nil, "ARTWORK")
    closeTex:SetAllPoints()
    closeTex:SetTexture(MEDIA .. "atrocityCustomCrossv3.png")
    closeTex:SetVertexColor(Theme.textSecondary[1], Theme.textSecondary[2], Theme.textSecondary[3], 1)
    closeTex:SetRotation(math.rad(45))
    closeBtn:SetNormalTexture(closeTex)
    closeBtn:SetScript("OnEnter", function() closeTex:SetVertexColor(Theme.accent[1], Theme.accent[2], Theme.accent[3], 1) end)
    closeBtn:SetScript("OnLeave", function() closeTex:SetVertexColor(Theme.textSecondary[1], Theme.textSecondary[2], Theme.textSecondary[3], 1) end)
    closeBtn:SetScript("OnClick", function() GUIFrame:Hide() end)

    -- Home button
    local homeBtn = CreateFrame("Button", nil, header)
    homeBtn:SetSize(18, 18)
    homeBtn:SetPoint("RIGHT", closeBtn, "LEFT", -8, 0)
    local homeTex = homeBtn:CreateTexture(nil, "ARTWORK")
    homeTex:SetAllPoints()
    homeTex:SetTexture(MEDIA .. "HomeButtonv2.png")
    homeTex:SetVertexColor(Theme.textSecondary[1], Theme.textSecondary[2], Theme.textSecondary[3], 1)
    homeBtn:SetNormalTexture(homeTex)
    homeBtn:SetScript("OnEnter", function() homeTex:SetVertexColor(Theme.accent[1], Theme.accent[2], Theme.accent[3], 1) end)
    homeBtn:SetScript("OnLeave", function() homeTex:SetVertexColor(Theme.textSecondary[1], Theme.textSecondary[2], Theme.textSecondary[3], 1) end)
    homeBtn:SetScript("OnClick", function() GUIFrame:SelectSidebarItem("Home") end)

    header:EnableMouse(true)
    header:RegisterForDrag("LeftButton")
    header:SetScript("OnDragStart", function() parent:StartMoving() end)
    header:SetScript("OnDragStop", function() parent:StopMovingOrSizing() end)

    parent.header = header
    return header
end

-- ════════════════════════════════════════════════════════════════════════════════════
-- Part 5: Footer (Version text + resize handle)
-- ════════════════════════════════════════════════════════════════════════════════════

function GUIFrame:CreateFooter(parent)
    local Theme = addon.Theme
    local footer = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    footer:SetHeight(Theme.footerHeight)
    footer:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", 0, 0)
    footer:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", 0, 0)
    footer:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    footer:SetBackdropColor(Theme.bgDark[1], Theme.bgDark[2], Theme.bgDark[3], 1)
    footer:SetBackdropBorderColor(Theme.border[1], Theme.border[2], Theme.border[3], 1)
    footer:SetFrameLevel(parent:GetFrameLevel() + 2)

    local versionText = footer:CreateFontString(nil, "OVERLAY")
    versionText:SetPoint("LEFT", footer, "LEFT", Theme.paddingMedium, 0)
    addon:ApplyThemeFont(versionText, "small")
    versionText:SetText(ADDON_NAME)
    versionText:SetTextColor(Theme.textMuted[1], Theme.textMuted[2], Theme.textMuted[3], 1)

    local handle = CreateFrame("Button", nil, parent)
    handle:SetSize(16, 16)
    handle:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -2, 2)
    handle:SetFrameLevel(parent:GetFrameLevel() + 10)
    local tex = handle:CreateTexture(nil, "OVERLAY")
    tex:SetAllPoints()
    tex:SetTexture(MEDIA .. "atrocityCustomResizeHandle23px.png")
    tex:SetVertexColor(Theme.textMuted[1], Theme.textMuted[2], Theme.textMuted[3], 0.6)
    handle:SetNormalTexture(tex)
    handle:SetScript("OnMouseDown", function(_, btn) if btn == "LeftButton" then parent:StartSizing("BOTTOM") end end)
    handle:SetScript("OnMouseUp", function() parent:StopMovingOrSizing() end)

    parent.footer = footer
    return footer
end

-- ════════════════════════════════════════════════════════════════════════════════════
-- Part 6: Content Area (Scrollable content region with auto-hiding scrollbar)
-- ════════════════════════════════════════════════════════════════════════════════════

function GUIFrame:CreateContentArea(parent)
    local Theme = addon.Theme
    local content = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    content:SetWidth(Theme.contentWidth)
    content:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, -Theme.headerHeight)
    content:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", 0, Theme.footerHeight)
    content:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8" })
    content:SetBackdropColor(Theme.bgMedium[1], Theme.bgMedium[2], Theme.bgMedium[3], Theme.bgMedium[4])

    local scrollFrame = CreateFrame("ScrollFrame", nil, content, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", content, "TOPLEFT", 0, 0)
    scrollFrame:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", 0, 0)

    if scrollFrame.ScrollBar then
        local sb = scrollFrame.ScrollBar
        sb:ClearAllPoints()
        sb:SetPoint("TOPRIGHT", content, "TOPRIGHT", -3, -Theme.paddingSmall - 12)
        sb:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", -3, Theme.paddingSmall + 12)
        sb:SetWidth(Theme.scrollbarWidth - 4)
        if sb.Background then sb.Background:Hide() end
        if sb.Top then sb.Top:Hide() end
        if sb.Middle then sb.Middle:Hide() end
        if sb.Bottom then sb.Bottom:Hide() end
        if sb.trackBG then sb.trackBG:Hide() end
        if sb.ScrollUpButton then sb.ScrollUpButton:Hide() end
        if sb.ScrollDownButton then sb.ScrollDownButton:Hide() end
        sb:SetAlpha(0)
    end

    local scrollChild = CreateFrame("Frame", nil, scrollFrame)
    scrollChild:SetHeight(1)
    scrollFrame:SetScrollChild(scrollChild)

    local scrollbarVisible = false
    local function UpdateScrollChildWidth()
        local w = Theme.contentWidth
        scrollChild:SetWidth(scrollbarVisible and (w - Theme.scrollbarWidth) or w)
    end

    local function UpdateScrollBarVisibility()
        if scrollFrame.ScrollBar then
            local needsScrollbar = scrollChild:GetHeight() > scrollFrame:GetHeight()
            scrollbarVisible = needsScrollbar
            scrollFrame.ScrollBar:SetAlpha(needsScrollbar and 1 or 0)
            UpdateScrollChildWidth()
        end
    end

    scrollFrame:HookScript("OnScrollRangeChanged", UpdateScrollBarVisibility)
    scrollChild:HookScript("OnSizeChanged", UpdateScrollBarVisibility)
    scrollFrame:HookScript("OnSizeChanged", UpdateScrollBarVisibility)
    UpdateScrollChildWidth()

    content.scrollFrame = scrollFrame
    content.scrollChild = scrollChild
    parent.content = content
    self.contentArea = content
    return content
end

-- ════════════════════════════════════════════════════════════════════════════════════
-- Part 7: Refresh Content (Re-build content area from current builder)
-- ════════════════════════════════════════════════════════════════════════════════════

function GUIFrame:RefreshContent()
    if not self.contentArea then return end
    if self.contentArea.scrollFrame then self.contentArea.scrollFrame:Show() end
    if GameTooltip and GameTooltip.Hide then GameTooltip:Hide() end

    -- Tear down previous tab: run cleanup delegates, close any open dropdown
    -- (its list lives on the overlay), then destroy content frames outright.
    for _, callback in pairs(self.contentCleanupCallbacks) do pcall(callback) end
    wipe(self.contentCleanupCallbacks)
    if self.activeDropdown and self.activeDropdown.closeDropdown then
        pcall(self.activeDropdown.closeDropdown, true)
        self.activeDropdown = nil
    end

    local scrollChild = self.contentArea.scrollChild
    for _, child in ipairs({ scrollChild:GetChildren() }) do
        if child.Destroy then
            child:Destroy()
        else
            child:Hide()
            child:SetParent(nil)
        end
    end
    for _, region in ipairs({ scrollChild:GetRegions() }) do
        if region:GetObjectType() == "FontString" or region:GetObjectType() == "Texture" then
            region:Hide()
        end
    end

    local itemId = self.selectedSidebarItem or "Home"
    local yOffset = addon.Theme.paddingMedium

    if self.ContentBuilders[itemId] then
        local ok, result = pcall(self.ContentBuilders[itemId], scrollChild, yOffset)
        if ok and result then
            yOffset = result
        elseif not ok then
            local stack = debugstack and debugstack(2, 3, 0) or ""
            stack = tostring(stack):gsub("%s+", " "):sub(1, 300)
            print("|cffff0000TF_QoL|r error building tab '" .. tostring(itemId) .. "': " .. tostring(result) .. " | " .. stack)
        end
    end

    scrollChild:SetHeight(yOffset + addon.Theme.paddingLarge)
end