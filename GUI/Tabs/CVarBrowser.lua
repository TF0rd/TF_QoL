-- ════════════════════════════════════════════════════════════════════════════════
-- CVarBrowser tab — browse and modify all game CVars
-- ════════════════════════════════════════════════════════════════════════════════

local _, addon = ...
local GUIFrame = addon.GUIFrame

-- ── Localize API ───────────────────────────────────────────────────────────

local C_CVar_GetCVarInfo = C_CVar.GetCVarInfo
local C_CVar_SetCVar     = C_CVar.SetCVar
local C_Timer_NewTimer   = C_Timer.NewTimer
local strmatch           = strmatch
local tinsert            = tinsert
local wipe               = wipe
local format             = format

-- ── File-level CVar state ──────────────────────────────────────────────────
-- Lives here (not in the builder closure) so the SetCVar/ConsoleExec hooks
-- below can do a debounced full rebuild — or a single-row refresh when the
-- changed key is known — without rebuilding the tab.

local CVarList      = {}
local CVarTable     = {}
local FilteredTable = {}

local activeListFrame   = nil
local activeFilterBox   = nil
local refreshDebounce   = nil
local REFRESH_DELAY     = 0.2

local function BuildCVarList()
    wipe(CVarList)
    local commands = ConsoleGetAllCommands()
    for _, info in ipairs(commands) do
        if info.commandType == 0
        and info.category  ~= 0
        and info.category  ~= 8
        and not info.command:lower():find("debug")
        then
            CVarList[info.command] = { description = info.help or "" }
        end
    end
end

local function GetPrettyCVar(cvar)
    local value, default = C_CVar_GetCVarInfo(cvar)
    if not default or not value then return "", "", true end
    local isFloat = strmatch(value, "^-?%d+%.%d+$")
    if isFloat then
        value = format("%.2f", value):gsub("%.?0+$", "")
    end
    local isDefault = (tonumber(value) and tonumber(default))
        and (value - default == 0)
        or  (value == default)
    return value, default, isDefault
end

local function RefreshCVarList()
    wipe(CVarTable)
    BuildCVarList()
    for cvar, tbl in pairs(CVarList) do
        local value, default, isDefault = GetPrettyCVar(cvar)
        if not (type(value) == "string" and (value:byte(2) == 1 or value:byte(1) == 2)) then
            tinsert(CVarTable, {
                cvar,
                cvar,
                tbl.description or "",
                isDefault and value or ("|cffff0000" .. value .. "|r"),
            })
        end
    end
end

-- ── Filter ─────────────────────────────────────────────────────────────────

local function Literalize(str)
    return str:gsub("[%(%)%.%%%+%-%*%?%[%]%^%$]", "%%%1")
end

local function UnCase(c)
    return "[" .. strlower(c) .. strupper(c) .. "]"
end

local function ApplyFilter()
    if not activeListFrame then return end
    local text = activeFilterBox and activeFilterBox:GetText() or ""
    if text == "" then
        activeListFrame:SetItems(CVarTable)
    else
        local pattern = Literalize(text):gsub("%a", UnCase)
        wipe(FilteredTable)
        for i = 1, #CVarTable do
            local row = CVarTable[i]
            for j = 2, #row - 1 do
                local _, replacements = row[j]:gsub(pattern, "")
                if replacements > 0 then
                    local newrow = { row[1], [#row] = row[#row] }
                    for k = 2, #row - 1 do
                        newrow[k] = row[k]:gsub(pattern, "|cffff0000%1|r")
                    end
                    tinsert(FilteredTable, newrow)
                    break
                end
            end
        end
        activeListFrame:SetItems(FilteredTable)
    end
end

-- ── Debounced refresh + single-row fast path ───────────────────────────────

local function RefreshSingleRow(cvar)
    if not activeListFrame or not cvar or cvar == "" then return false end
    for _, row in ipairs(CVarTable) do
        if row[1] == cvar then
            local value, default, isDefault = GetPrettyCVar(cvar)
            row[4] = isDefault and value or ("|cffff0000" .. value .. "|r")
            ApplyFilter()
            return true
        end
    end
    return false
end

local function RequestCVarRefresh(changedKey)
    if not activeListFrame then return end
    if changedKey and RefreshSingleRow(changedKey) then return end
    if refreshDebounce then refreshDebounce:Cancel() end
    refreshDebounce = C_Timer_NewTimer(REFRESH_DELAY, function()
        refreshDebounce = nil
        if activeListFrame and activeListFrame:IsVisible() then
            RefreshCVarList()
            ApplyFilter()
        end
    end)
end

-- Refresh live when CVars change while the browser is visible
hooksecurefunc("SetCVar", function(cvar) RequestCVarRefresh(cvar) end)
hooksecurefunc("ConsoleExec", function(cmd)
    RequestCVarRefresh(cmd and cmd:match("^(%S+)") or nil)
end)

-- Hide the inline editor when entering combat
local combatGuard = CreateFrame("Frame")
combatGuard:RegisterEvent("PLAYER_REGEN_DISABLED")

-- ════════════════════════════════════════════════════════════════════════════════
-- RegisterContent callback
-- ════════════════════════════════════════════════════════════════════════════════

GUIFrame:RegisterContent("CVarBrowser", function(scrollChild, yOffset)
    local Theme = addon.Theme
    local cvarModule = addon.modules["CVarBrowser"]

    -- ── About card ──────────────────────────────────────────────────────────

    yOffset = GUIFrame:AddAboutCard(scrollChild, yOffset, "CVar Browser",
        "Browse and modify all game CVars. Values shown in red are non-default. Hover a row for details; double-click a value to edit it.")

    -- ── Filter card (themed bgDark background matching the list) ────────────

    local filterCard = CreateFrame("Frame", nil, scrollChild, "BackdropTemplate")
    filterCard:SetPoint("TOPLEFT",  scrollChild, "TOPLEFT",  Theme.paddingSmall, -yOffset + Theme.paddingSmall)
    filterCard:SetPoint("TOPRIGHT", scrollChild, "TOPRIGHT", -Theme.paddingSmall, -yOffset + Theme.paddingSmall)
    filterCard:SetHeight(Theme.paddingSmall + 20 + Theme.paddingSmall)
    filterCard:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = Theme.borderSize,
    })
    filterCard:SetBackdropColor(Theme.bgDark[1], Theme.bgDark[2], Theme.bgDark[3], Theme.bgDark[4])
    filterCard:SetBackdropBorderColor(Theme.border[1], Theme.border[2], Theme.border[3], 1)

    local filterLabel = filterCard:CreateFontString(nil, "OVERLAY")
    addon:ApplyThemeFont(filterLabel, "small")
    filterLabel:SetText("Search:")
    filterLabel:SetTextColor(Theme.textMuted[1], Theme.textMuted[2], Theme.textMuted[3], 1)
    filterLabel:SetPoint("LEFT", filterCard, "LEFT", Theme.paddingMedium, 0)

    local FilterBox = CreateFrame("EditBox", nil, filterCard, "InputBoxTemplate")
    FilterBox:SetHeight(20)
    FilterBox:SetPoint("LEFT",  filterLabel, "RIGHT", 6, 0)
    FilterBox:SetPoint("RIGHT", filterCard,  "RIGHT", -Theme.paddingSmall, 0)
    FilterBox:SetAutoFocus(false)
    FilterBox:SetMaxLetters(100)
    FilterBox:SetScript("OnEscapePressed", function(self)
        self:SetAutoFocus(false)
        self:ClearFocus()
    end)
    FilterBox:SetScript("OnEnterPressed", function(self)
        self:SetAutoFocus(false)
        self:ClearFocus()
    end)
    FilterBox:SetScript("OnEditFocusGained", function(self)
        self:SetAutoFocus(true)
        self:HighlightText()
    end)

    -- 28px card + 18px column-header overhang + 4px gap = 50px total advance
    yOffset = yOffset + 50

    -- ── List frame — height fills the remaining content area ───────────────

    local listWidth   = Theme.contentWidth - Theme.paddingMedium * 2 - Theme.scrollbarWidth
    local areaHeight  = math.floor(GUIFrame.contentArea:GetHeight())
    -- Subtract paddingLarge so scrollChild:SetHeight == contentArea height -> outer scrollbar hidden
    local listHeight  = math.max(200, areaHeight - yOffset - Theme.paddingSmall - Theme.paddingLarge)

    local ListFrame = GUIFrame:CreateScrollList(scrollChild, listWidth, listHeight,
        { { "Name", 185 }, { "Description", 235, "LEFT" }, { "Value", 90, "RIGHT" } })
    ListFrame:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", Theme.paddingMedium, -yOffset)

    yOffset = yOffset + listHeight + Theme.paddingLarge

    -- Refresh this tab whenever the window is resized (registered once)
    if not GUIFrame._cvarBrowserResizeHook then
        GUIFrame._cvarBrowserResizeHook = true
        local resizeTimer
        GUIFrame.contentArea:HookScript("OnSizeChanged", function()
            if GUIFrame.selectedSidebarItem ~= "CVarBrowser" then return end
            if resizeTimer then resizeTimer:Cancel() end
            resizeTimer = C_Timer.NewTimer(0.05, function()
                resizeTimer = nil
                GUIFrame:RefreshContent()
            end)
        end)
    end

    -- Publish live refs for the file-level refresh delegates
    activeListFrame = ListFrame
    activeFilterBox = FilterBox

    FilterBox:SetScript("OnTextChanged", ApplyFilter)

    RefreshCVarList()
    ListFrame:SetItems(CVarTable)
    ListFrame:SortBy(2)

    -- ── Inline CVar editor ──────────────────────────────────────────────────

    local CVarInputBoxBlocker = CreateFrame("Frame", nil, ListFrame)
    CVarInputBoxBlocker:SetFrameStrata("FULLSCREEN_DIALOG")
    CVarInputBoxBlocker:Hide()
    CVarInputBoxBlocker:EnableMouse(true)
    CVarInputBoxBlocker:EnableMouseWheel(true)
    CVarInputBoxBlocker:SetScript("OnMouseWheel", function() end)
    CVarInputBoxBlocker:SetAllPoints(ListFrame)

    local blackout = CVarInputBoxBlocker:CreateTexture(nil, "BACKGROUND")
    blackout:SetAllPoints()
    blackout:SetColorTexture(0, 0, 0, 0.2)

    local CVarInputBox = CreateFrame("EditBox", nil, CVarInputBoxBlocker, "InputBoxTemplate")
    CVarInputBox:Hide()
    CVarInputBox:SetSize(100, 20)
    CVarInputBox:SetJustifyH("RIGHT")
    CVarInputBox:SetTextInsets(5, 10, 0, 0)

    CVarInputBoxBlocker:SetScript("OnMouseDown", function()
        CVarInputBox:ClearFocus()
    end)

    CVarInputBox:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
        self:Hide()
    end)
    CVarInputBox:SetScript("OnEnterPressed", function(self)
        if InCombatLockdown() then
            print("|cff" .. Theme.errorHex .. "TF_QoL|r CVars cannot be modified in combat.")
            return
        end
        C_CVar_SetCVar(self.cvar, self:GetText() or "")
        self:Hide()
        RequestCVarRefresh(self.cvar)
    end)
    CVarInputBox:SetScript("OnHide", function(self)
        CVarInputBoxBlocker:Hide()
        if self.str then self.str:Show() end
    end)
    CVarInputBox:SetScript("OnEditFocusLost", function(self)
        self:Hide()
        FilterBox:SetFocus()
    end)

    -- Wire combat guard to the current input box instance
    combatGuard:SetScript("OnEvent", function()
        if CVarInputBox:IsVisible() then
            CVarInputBox:Hide()
        end
    end)

    -- ── Row scripts ─────────────────────────────────────────────────────────

    local LastClickTime = 0
    ListFrame:SetScripts({
        OnEnter = function(self)
            if self.value and self.value ~= "" then
                local cvarInfo = CVarList[self.value]
                local _, defaultValue = C_CVar_GetCVarInfo(self.value)
                GameTooltip:SetOwner(self, "ANCHOR_TOPLEFT")
                GameTooltip:AddLine(self.value, 1, 1, 1, false)
                if cvarInfo and cvarInfo.description and cvarInfo.description ~= "" then
                    GameTooltip:AddLine(" ")
                    GameTooltip:AddLine(cvarInfo.description, 1, 1, 1, true)
                end
                if defaultValue then
                    GameTooltip:AddDoubleLine("Default:", defaultValue, 0.2, 1, 0.6, 0.2, 1, 0.6)
                end
                local modifiedBy = cvarModule and cvarModule:GetModifiedCVars()[self.value:lower()]
                if modifiedBy then
                    GameTooltip:AddDoubleLine("Last Modified By:", modifiedBy, 1, 0, 0, 1, 0, 0)
                end
                GameTooltip:Show()
            end
            self.bg:Show()
        end,
        OnLeave = function(self)
            GameTooltip:Hide()
            self.bg:Hide()
        end,
        OnMouseDown = function(self)
            local now = GetTime()
            if now - LastClickTime <= 0.2 then
                if CVarInputBox.str then CVarInputBox.str:Show() end
                self.cols[#self.cols]:Hide()
                CVarInputBox.str  = self.cols[#self.cols]
                CVarInputBox.cvar = self.value
                CVarInputBox.row  = self
                CVarInputBox:SetPoint("RIGHT", self)
                local value = GetPrettyCVar(self.value)
                CVarInputBox:SetText(value or "")
                CVarInputBox:HighlightText()
                CVarInputBoxBlocker:Show()
                CVarInputBox:Show()
                CVarInputBox:SetFocus()
            else
                LastClickTime = now
            end
        end,
    })

    -- ── Cleanup ─────────────────────────────────────────────────────────────

    -- Clear the live refs (and any pending debounced rebuild) on teardown
    GUIFrame:RegisterContentCleanup("CVarBrowser", function()
        activeListFrame = nil
        activeFilterBox = nil
        if refreshDebounce then
            refreshDebounce:Cancel()
            refreshDebounce = nil
        end
    end)

    return yOffset
end)
