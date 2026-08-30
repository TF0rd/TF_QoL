local _, addon = ...
local GUIFrame = addon.GUIFrame

local math = math
local C_Timer = C_Timer
local ipairs = ipairs
local CreateFrame = CreateFrame
local CreateColor = CreateColor
local wipe = wipe
local table = table

-- ════════════════════════════════════════════════════════════════════════════════════
-- Part 1: Constants & Pool State
-- ════════════════════════════════════════════════════════════════════════════════════

local headerHeight = 32
local itemHeight = 28

GUIFrame.sidebarHeaderPool = {}
GUIFrame.staticSidebarItemPool = {}
GUIFrame.sidebarExpanded = GUIFrame.sidebarExpanded or {}
GUIFrame.sidebarRefreshPending = false

local ARROW_TEX = "Interface\\AddOns\\TF_QoL\\Media\\GUITextures\\collapse.tga"
local ARROW_SIZE = 16

-- ════════════════════════════════════════════════════════════════════════════════════
-- Part 2: Section Headers (Pooled collapse/expand header buttons with arrow animations)
-- ════════════════════════════════════════════════════════════════════════════════════

function GUIFrame:ReleaseSectionHeaders()
    for _, header in ipairs(self.sidebarHeaderPool or {}) do
        header.inUse = false
        header:Hide()
        header:ClearAllPoints()
    end
end

function GUIFrame:CreateSectionHeader()
    local Theme = addon.Theme
    local header = CreateFrame("Button", nil, UIParent)
    header:SetHeight(headerHeight)
    header:EnableMouse(true)
    header:RegisterForClicks("LeftButtonUp")

    local background = header:CreateTexture(nil, "ARTWORK")
    background:SetAllPoints()
    background:SetColorTexture(1, 1, 1, 1)
    background:SetGradient("HORIZONTAL", CreateColor(0.3, 0.3, 0.3, 0.25), CreateColor(0.3, 0.3, 0.3, 0))
    background:Hide()
    header.background = background

    local selectedOverlay = header:CreateTexture(nil, "ARTWORK")
    selectedOverlay:SetTexture("Interface\\Buttons\\WHITE8X8")
    selectedOverlay:SetBlendMode("ADD")
    selectedOverlay:SetVertexColor(Theme.selectedBg[1], Theme.selectedBg[2], Theme.selectedBg[3], Theme.selectedBg[4] or 0.25)
    selectedOverlay:SetAllPoints()
    selectedOverlay:Hide()
    header.selectedOverlay = selectedOverlay

    local selectedBar = header:CreateTexture(nil, "OVERLAY")
    selectedBar:SetWidth(3)
    selectedBar:SetPoint("TOPLEFT", header, "TOPLEFT", 0, 0)
    selectedBar:SetPoint("BOTTOMLEFT", header, "BOTTOMLEFT", 0, 0)
    selectedBar:SetColorTexture(Theme.accent[1], Theme.accent[2], Theme.accent[3], 1)
    selectedBar:Hide()
    header.selectedBar = selectedBar

    local label = header:CreateFontString(nil, "OVERLAY")
    label:SetPoint("LEFT", header, "LEFT", Theme.paddingSmall, 0)
    addon:ApplyThemeFont(label, "large")
    label:SetTextColor(Theme.secondaryAccent[1], Theme.secondaryAccent[2], Theme.secondaryAccent[3], 1)
    label:SetShadowColor(0, 0, 0, 0)
    label:SetJustifyH("LEFT")
    label:SetWordWrap(false)
    header.label = label

    local arrow = header:CreateTexture(nil, "OVERLAY")
    arrow:SetSize(ARROW_SIZE, ARROW_SIZE)
    arrow:SetPoint("RIGHT", header, "RIGHT", -Theme.paddingSmall, 0)
    arrow:SetTexture(ARROW_TEX)
    arrow:SetVertexColor(Theme.secondaryAccent[1], Theme.secondaryAccent[2], Theme.secondaryAccent[3], 1)
    header.arrow = arrow

    local arrowAnimGroup = arrow:CreateAnimationGroup()
    local arrowRotation = arrowAnimGroup:CreateAnimation("Rotation")
    arrowRotation:SetDuration(0.18)
    arrowRotation:SetOrigin("CENTER", 0, 0)
    arrowRotation:SetSmoothing("IN_OUT")
    header.arrowAnimGroup = arrowAnimGroup
    header.arrowRotation = arrowRotation

    header.AnimateArrowOpen = function(self)
        if self.isExpanded then return end
        self.arrowAnimGroup:Stop()
        self.arrowRotation:SetRadians(math.pi / 2)
        self.isExpanded = true
        self.arrowAnimGroup:Play()
    end

    header.AnimateArrowClose = function(self)
        if not self.isExpanded then return end
        self.arrowAnimGroup:Stop()
        self.arrowRotation:SetRadians(-math.pi / 2)
        self.isExpanded = false
        self.arrowAnimGroup:Play()
    end

    arrowAnimGroup:SetScript("OnFinished", function()
        arrow:SetRotation(header.isExpanded and 0 or -math.pi / 2)
    end)

    header.SetArrowState = function(self, expanded)
        self.arrowAnimGroup:Stop()
        self.isExpanded = expanded
        self.arrow:SetRotation(expanded and 0 or -math.pi / 2)
    end

    header:SetScript("OnEnter", function(self)
        if not self.isExpanded then background:Show() end
    end)
    header:SetScript("OnLeave", function(self)
        if not self.isExpanded then background:Hide() end
    end)
    header:SetScript("OnClick", function(self)
        GUIFrame:ToggleSection(self.sectionId)
    end)

    return header
end

function GUIFrame:GetSectionHeader()
    for _, header in ipairs(self.sidebarHeaderPool) do
        if not header.inUse then
            header.inUse = true
            header:Show()
            return header
        end
    end
    local header = self:CreateSectionHeader()
    header.inUse = true
    table.insert(self.sidebarHeaderPool, header)
    return header
end

-- ── Sidebar Expansion State ────────────────────────────────────────────────────────

local initSidebar = false
function GUIFrame:InitializeSidebarExpansion()
    if initSidebar then return end
    wipe(self.sidebarExpanded)
    local config = self.SidebarConfig[self.selectedTab]
    if not config then return end
    for _, section in ipairs(config) do
        if section.type == "header" and section.defaultExpanded then
            self.sidebarExpanded[section.id] = true
        end
    end
    initSidebar = true
end

-- ── Configure & Toggle ─────────────────────────────────────────────────────────────

function GUIFrame:ConfigureSectionHeader(header, config, yOffset, isExpanded)
    local Theme = addon.Theme
    local scrollChild = self.sidebar.scrollChild
    header:SetParent(scrollChild)
    header:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", Theme.paddingSmall, -yOffset)
    header:SetPoint("TOPRIGHT", scrollChild, "TOPRIGHT", -Theme.paddingSmall, -yOffset)
    header.sectionId = config.id
    header.label:SetText(config.text or "")
    header.label:SetTextColor(Theme.secondaryAccent[1], Theme.secondaryAccent[2], Theme.secondaryAccent[3], 1)
    header.arrow:SetVertexColor(Theme.secondaryAccent[1], Theme.secondaryAccent[2], Theme.secondaryAccent[3], 1)
    header.isExpanded = isExpanded
    C_Timer.After(0.05, function() header:SetArrowState(isExpanded) end)
    header.background:Hide()
    return header
end

function GUIFrame:ToggleSection(sectionId)
    if self.sidebarExpanded[sectionId] then
        local header = self:GetHeaderBySectionId(sectionId)
        if header then header:AnimateArrowClose() end
        self.sidebarExpanded[sectionId] = nil
    else
        local header = self:GetHeaderBySectionId(sectionId)
        if header then header:AnimateArrowOpen() end
        self.sidebarExpanded[sectionId] = true
    end
    C_Timer.After(0.01, function()
        self:RefreshSidebar()
        self:RefreshContent()
    end)
end

function GUIFrame:GetHeaderBySectionId(sectionId)
    for _, header in ipairs(self.sidebarHeaderPool) do
        if header.inUse and header.sectionId == sectionId then return header end
    end
end

-- ════════════════════════════════════════════════════════════════════════════════════
-- Part 3: Static Sidebar Items (Pooled clickable navigation items)
-- ════════════════════════════════════════════════════════════════════════════════════

function GUIFrame:ReleaseStaticSidebarItems()
    for _, item in ipairs(self.staticSidebarItemPool) do
        item.inUse = false
        item:Hide()
        item:ClearAllPoints()
        item.id = nil
        item.selectedOverlay:Hide()
        item.selectedBar:Hide()
    end
end

function GUIFrame:CreateStaticSidebarItem()
    local Theme = addon.Theme
    local r, g, b = Theme.accent[1], Theme.accent[2], Theme.accent[3]
    local item = CreateFrame("Button", nil, UIParent)
    item:SetHeight(itemHeight)
    item:EnableMouse(true)
    item:RegisterForClicks("LeftButtonUp")

    local background = item:CreateTexture(nil, "ARTWORK")
    background:SetAllPoints()
    background:SetColorTexture(1, 1, 1, 1)
    background:SetGradient("HORIZONTAL", CreateColor(r, g, b, 0.25), CreateColor(r, g, b, 0))
    background:Hide()
    item.background = background

    local selectedOverlay = item:CreateTexture(nil, "ARTWORK")
    selectedOverlay:SetAllPoints()
    selectedOverlay:SetColorTexture(1, 1, 1, 1)
    selectedOverlay:SetGradient("HORIZONTAL", CreateColor(r, g, b, 0.25), CreateColor(r, g, b, 0))
    selectedOverlay:Hide()
    item.selectedOverlay = selectedOverlay

    local selectedBar = item:CreateTexture(nil, "OVERLAY")
    selectedBar:SetWidth(1)
    selectedBar:SetPoint("TOPLEFT", item, "TOPLEFT", 0, 5)
    selectedBar:SetPoint("BOTTOMLEFT", item, "BOTTOMLEFT", 0, -7)
    selectedBar:SetColorTexture(Theme.accent[1], Theme.accent[2], Theme.accent[3], 1)
    selectedBar:Hide()
    item.selectedBar = selectedBar

    local label = item:CreateFontString(nil, "OVERLAY")
    label:SetPoint("LEFT", item, "LEFT", 12, 0)
    label:SetPoint("RIGHT", item, "RIGHT", -Theme.paddingSmall, 0)
    addon:ApplyThemeFont(label, "normal")
    label:SetShadowColor(0, 0, 0, 0)
    label:SetJustifyH("LEFT")
    label:SetWordWrap(false)
    item.label = label

    item:SetScript("OnEnter", function(self)
        if self.id ~= GUIFrame.selectedSidebarItem then
            background:Show()
            self.label:SetTextColor(Theme.textPrimary[1], Theme.textPrimary[2], Theme.textPrimary[3], 1)
        end
    end)
    item:SetScript("OnLeave", function(self)
        if self.id ~= GUIFrame.selectedSidebarItem then
            background:Hide()
            self.label:SetTextColor(Theme.textSecondary[1], Theme.textSecondary[2], Theme.textSecondary[3], 1)
        end
    end)
    item:SetScript("OnClick", function(self, button)
        if button == "LeftButton" then GUIFrame:SelectSidebarItem(self.id) end
    end)

    return item
end

function GUIFrame:GetStaticSidebarItem()
    for _, item in ipairs(self.staticSidebarItemPool) do
        if not item.inUse then
            item.inUse = true
            item:Show()
            return item
        end
    end
    local item = self:CreateStaticSidebarItem()
    item.inUse = true
    table.insert(self.staticSidebarItemPool, item)
    return item
end

-- ════════════════════════════════════════════════════════════════════════════════════
-- Part 4: Sidebar Frame (Left-side navigation panel with scroll)
-- ════════════════════════════════════════════════════════════════════════════════════

function GUIFrame:CreateSidebar(parent)
    local Theme = addon.Theme
    local sidebar = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    sidebar:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -Theme.headerHeight)
    sidebar:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", 0, Theme.footerHeight)
    sidebar:SetPoint("RIGHT", parent.content, "LEFT", 0, 0)
    sidebar:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8" })
    sidebar:SetBackdropColor(Theme.bgDark[1], Theme.bgDark[2], Theme.bgDark[3], Theme.bgDark[4])

    local rightBorder = sidebar:CreateTexture(nil, "BORDER")
    rightBorder:SetWidth(Theme.borderSize)
    rightBorder:SetPoint("TOPRIGHT", sidebar, "TOPRIGHT", 0, 0)
    rightBorder:SetPoint("BOTTOMRIGHT", sidebar, "BOTTOMRIGHT", 0, 0)
    rightBorder:SetColorTexture(Theme.border[1], Theme.border[2], Theme.border[3], 1)

    local scrollFrame = CreateFrame("ScrollFrame", nil, sidebar, "UIPanelScrollFrameTemplate")
    scrollFrame:SetFrameLevel(sidebar:GetFrameLevel() + 5)
    scrollFrame:SetPoint("TOPLEFT", sidebar, "TOPLEFT", 0, -Theme.paddingSmall)
    scrollFrame:SetPoint("BOTTOMRIGHT", sidebar, "BOTTOMRIGHT", -Theme.borderSize, Theme.paddingSmall)
    scrollFrame:SetClipsChildren(true)

    if scrollFrame.ScrollBar then
        local sb = scrollFrame.ScrollBar
        sb:SetAlpha(0)
        sb:EnableMouse(false)
    end

    local scrollChild = CreateFrame("Frame", nil, scrollFrame)
    scrollChild:SetWidth(Theme.sidebarWidth - Theme.borderSize)
    scrollChild:SetHeight(1)
    scrollChild:SetFrameLevel(scrollFrame:GetFrameLevel() + 1)
    scrollFrame:SetScrollChild(scrollChild)

    sidebar.scrollFrame = scrollFrame
    sidebar.scrollChild = scrollChild
    parent.sidebar = sidebar
    self.sidebar = sidebar
    return sidebar
end

-- ════════════════════════════════════════════════════════════════════════════════════
-- Part 5: Selection & Refresh (Item selection, sidebar rebuild, page navigation)
-- ════════════════════════════════════════════════════════════════════════════════════

function GUIFrame:SelectSidebarItem(itemId)
    self.selectedSidebarItem = itemId
    local Theme = addon.Theme
    for _, item in ipairs(self.staticSidebarItemPool) do
        if item.inUse then
            if item.id == itemId then
                item.selectedOverlay:Show()
                item.background:Hide()
                item.label:SetTextColor(Theme.accent[1], Theme.accent[2], Theme.accent[3], 1)
            else
                item.selectedOverlay:Hide()
                item.background:Hide()
                item.label:SetTextColor(Theme.textSecondary[1], Theme.textSecondary[2], Theme.textSecondary[3], 1)
            end
        end
    end
    self:RefreshContent()
end

function GUIFrame:RefreshSidebar()
    if self.sidebarRefreshPending then return end
    self.sidebarRefreshPending = true
    C_Timer.After(0.05, function()
        self.sidebarRefreshPending = false
        self:RefreshSidebarImmediate()
    end)
end

function GUIFrame:RefreshSidebarImmediate()
    if not self.sidebar then return end
    self:ReleaseStaticSidebarItems()
    self:ReleaseSectionHeaders()
    local Theme = addon.Theme
    local scrollChild = self.sidebar.scrollChild
    local config = self.SidebarConfig[self.selectedTab]
    if not config then scrollChild:SetHeight(1) return end

    local yOffset = Theme.paddingSmall
    for _, sectionConfig in ipairs(config) do
        if sectionConfig.type == "item" then
            local item = self:GetStaticSidebarItem()
            item:SetParent(scrollChild)
            item:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", Theme.paddingSmall, -yOffset)
            item:SetPoint("TOPRIGHT", scrollChild, "TOPRIGHT", -Theme.paddingSmall, -yOffset)
            item.id = sectionConfig.id
            item.label:SetText(sectionConfig.text or "")
            item.selectedBar:Hide()
            if sectionConfig.id == self.selectedSidebarItem then
                item.selectedOverlay:Show()
                item.label:SetTextColor(Theme.accent[1], Theme.accent[2], Theme.accent[3], 1)
            else
                item.selectedOverlay:Hide()
                item.label:SetTextColor(Theme.textSecondary[1], Theme.textSecondary[2], Theme.textSecondary[3], 1)
            end
            yOffset = yOffset + itemHeight + 2
        elseif sectionConfig.type == "header" then
            local isExpanded = self.sidebarExpanded[sectionConfig.id]
            local header = self:GetSectionHeader()
            self:ConfigureSectionHeader(header, sectionConfig, yOffset, isExpanded)
            yOffset = yOffset + headerHeight
            if isExpanded and sectionConfig.items then
                for _, itemConfig in ipairs(sectionConfig.items) do
                    local item = self:GetStaticSidebarItem()
                    item:SetParent(scrollChild)
                    item:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", Theme.paddingSmall + 8, -yOffset)
                    item:SetPoint("TOPRIGHT", scrollChild, "TOPRIGHT", -Theme.paddingSmall, -yOffset)
                    item.id = itemConfig.id
                    item.label:SetText(itemConfig.text or "")
                    item.selectedBar:Show()
                    if itemConfig.id == self.selectedSidebarItem then
                        item.selectedOverlay:Show()
                        item.label:SetTextColor(Theme.accent[1], Theme.accent[2], Theme.accent[3], 1)
                    else
                        item.selectedOverlay:Hide()
                        item.label:SetTextColor(Theme.textSecondary[1], Theme.textSecondary[2], Theme.textSecondary[3], 1)
                    end
                    yOffset = yOffset + itemHeight + 2
                end
            end
            yOffset = yOffset + 2
        end
    end
    scrollChild:SetHeight(yOffset + Theme.paddingSmall)
end

function GUIFrame:OpenPage(itemId)
    self:Show()
    self:SelectSidebarItem(itemId)
end