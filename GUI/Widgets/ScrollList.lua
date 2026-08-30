-- ════════════════════════════════════════════════════════════════════════════════════
-- Widget: ScrollList (Virtual-scrolling list with sortable column headers)
-- Ported from AdvancedInterfaceOptions/semlib/widgets.lua
-- Usage: addon:CreateScrollList(parent, w, h, cols)
-- ════════════════════════════════════════════════════════════════════════════════════

local _, addon = ...

-- ════════════════════════════════════════════════════════════════════════════════════
-- Part 1: Locals
-- ════════════════════════════════════════════════════════════════════════════════════

local floor  = math.floor
local min    = math.min
local max    = math.max
local ceil   = math.ceil
local strlen = strlen
local strsub = strsub
local gsub   = gsub

-- ════════════════════════════════════════════════════════════════════════════════════
-- Part 2: Internal Helpers
-- ════════════════════════════════════════════════════════════════════════════════════

-- ── Create a FontString for a cell ──────────────────────────────────────────────────

local function localCreateString(parent, text, width, justify)
    local str = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmallLeft")
    str:SetText(text or "")
    str:SetWordWrap(false)
    str:SetNonSpaceWrap(true)
    str:SetHeight(10)
    str:SetMaxLines(2)
    if width then str:SetWidth(width) end
    if justify then str:SetJustifyH(justify) end
    return str
end

-- ── Update visible slot contents from items table ───────────────────────────────────

local function updatescroll(scroll)
    for line = 1, scroll.slots do
        local lineoffset = line + scroll.value
        if lineoffset <= scroll.itemcount then
            local mousedOver = scroll.slot[line]:IsMouseOver()
            if mousedOver then
                local OnLeave = scroll.slot[line]:GetScript("OnLeave")
                if OnLeave then OnLeave(scroll.slot[line]) end
            end

            scroll.slot[line].value = scroll.items[lineoffset][1]
            scroll.slot[line].offset = lineoffset
            for i, col in ipairs(scroll.slot[line].cols) do
                col.item = scroll.items[lineoffset][i + 1]
                col:SetText(scroll.items[lineoffset][i + 1])
                col.id = i
            end

            if mousedOver then
                local OnEnter = scroll.slot[line]:GetScript("OnEnter")
                if OnEnter then OnEnter(scroll.slot[line]) end
            end
            scroll.slot[line]:Show()
        else
            scroll.slot[line].value = nil
            scroll.slot[line]:Hide()
        end
    end

    local scrollbar = scroll.scrollbar
    if scroll.value == scroll.minValue then
        scrollbar.ScrollUpButton:Disable()
    else
        scrollbar.ScrollUpButton:Enable()
    end
    if scroll.value >= scroll.maxValue then
        scrollbar.ScrollDownButton:Disable()
    else
        scrollbar.ScrollDownButton:Enable()
    end
end

-- ── Apply scripts to all slots ──────────────────────────────────────────────────────

local function scrollscripts(scroll, scripts)
    for k, v in pairs(scripts) do
        scroll.scripts[k] = v
    end
    for line = 1, scroll.slots do
        for k, v in pairs(scroll.scripts) do
            scroll.slot[line]:SetScript(k, v)
        end
    end
end

-- ── Normalize text for sorting (strip color codes, pad numbers) ─────────────────────

local function normalize(str)
    str = str and gsub(str, "|c........", "") or ""
    return str
        :gsub("(%d+)", function(d)
            local lenF = strlen(d)
            return lenF < 10 and (strsub("0000000000", lenF + 1) .. d) or d
        end)
        :gsub("%W", "")
        :lower()
end

-- ── Sort items by column (toggle ascending/descending) ──────────────────────────────

local function sortItems(scroll, col)
    if not col then
        if scroll.sortCol then
            col = scroll.sortCol
            if scroll.sortUp then
                table.sort(scroll.items, function(a, b)
                    local x, y = normalize(a[col]), normalize(b[col])
                    if x ~= y then return x < y else return a[1] < b[1] end
                end)
            else
                table.sort(scroll.items, function(a, b)
                    local x, y = normalize(a[col]), normalize(b[col])
                    if x ~= y then return x > y else return a[1] > b[1] end
                end)
            end
        end
    else
        if col ~= scroll.sortCol then
            scroll.sortUp = nil
            scroll.sortCol = col
        end
        if scroll.sortUp then
            table.sort(scroll.items, function(a, b)
                local x, y = normalize(a[col]), normalize(b[col])
                if x ~= y then return x > y else return normalize(a[1]) > normalize(b[1]) end
            end)
            scroll.sortUp = false
        else
            table.sort(scroll.items, function(a, b)
                local x, y = normalize(a[col]), normalize(b[col])
                if x ~= y then return x < y else return normalize(a[1]) < normalize(b[1]) end
            end)
            scroll.sortUp = true
        end
    end
    scroll:Update()
end

-- ── Set items and reset scroll position ─────────────────────────────────────────────

local function setscrolllist(scroll, items)
    scroll.items = items
    scroll.itemcount = #items
    scroll.stepValue = min(ceil(scroll.slots / 2), max(floor(scroll.itemcount / scroll.slots), 1))
    scroll.maxValue  = max(scroll.itemcount - scroll.slots, 0)
    scroll.value     = scroll.value <= scroll.maxValue and scroll.value or scroll.maxValue

    scroll.scrollbar:SetMinMaxValues(0, scroll.maxValue)
    scroll.scrollbar:SetValue(scroll.value)
    scroll.scrollbar:SetValueStep(scroll.stepValue)

    sortItems(scroll)
    scroll:Update()
end

-- ── Handle mouse wheel scroll ───────────────────────────────────────────────────────

local function scroll(self, arg1)
    local oldValue = self.value
    if self.maxValue > self.minValue then
        if (self.value > self.minValue and self.value < self.maxValue)
            or (self.value == self.minValue and arg1 == -1)
            or (self.value == self.maxValue and arg1 == 1)
        then
            local newval = self.value - arg1 * self.stepValue
            if     newval <= self.maxValue and newval >= self.minValue then self.value = newval
            elseif newval > self.maxValue  then self.value = self.maxValue
            elseif newval < self.minValue  then self.value = self.minValue
            end
        elseif self.value < self.minValue then
            self.value = self.minValue
        elseif self.value > self.maxValue then
            self.value = self.maxValue
        end
        if self.value ~= oldValue then self:Update() end
    end
    if oldValue ~= self.value then self.scrollbar:SetValue(self.value) end
end

-- ════════════════════════════════════════════════════════════════════════════════════
-- Part 3: CreateScrollList (Main factory — virtual scrolling list with columns)
-- cols: array of { name, width [, justify] }
-- ════════════════════════════════════════════════════════════════════════════════════

function addon:CreateScrollList(parent, w, h, cols)
    local Theme = addon.Theme

    local frame = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    frame:SetSize(w, h)
    frame:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = Theme.borderSize,
    })
    frame:SetBackdropColor(Theme.bgDark[1], Theme.bgDark[2], Theme.bgDark[3], Theme.bgDark[4])
    frame:SetBackdropBorderColor(Theme.border[1], Theme.border[2], Theme.border[3], 1)

    frame.scripts   = {}
    frame.selected  = nil
    frame.items     = {}
    frame.itemcount = 0
    frame.minValue  = 0
    frame.itemheight = 15
    frame.slots     = floor((frame:GetHeight() - 10) / frame.itemheight)
    frame.slot      = {}
    frame.stepValue = min(frame.slots, max(floor(frame.itemcount / frame.slots), 1))
    frame.maxValue  = max(frame.itemcount - frame.slots, 0)
    frame.value     = frame.minValue

    frame:EnableMouseWheel(true)
    frame:SetScript("OnMouseWheel", scroll)

    frame.Update    = updatescroll
    frame.SetItems  = setscrolllist
    frame.SortBy    = sortItems
    frame.SetScripts = scrollscripts

    -- ── Scrollbar Background Textures ─────────────────────────────────────────────

    local scrollUpBg = frame:CreateTexture(nil, nil, nil, 1)
    scrollUpBg:SetTexture([[Interface\ClassTrainerFrame\UI-ClassTrainer-ScrollBar]])
    scrollUpBg:SetPoint("TOPRIGHT", 0, -2)
    scrollUpBg:SetTexCoord(0, 0.46875, 0.0234375, 0.9609375)
    scrollUpBg:SetSize(30, 120)

    local scrollDownBg = frame:CreateTexture(nil, nil, nil, 1)
    scrollDownBg:SetTexture([[Interface\ClassTrainerFrame\UI-ClassTrainer-ScrollBar]])
    scrollDownBg:SetPoint("BOTTOMRIGHT", 0, 1)
    scrollDownBg:SetTexCoord(0.53125, 1, 0.03125, 1)
    scrollDownBg:SetSize(30, 123)

    local scrollMidBg = frame:CreateTexture(nil, nil, nil, 2)
    scrollMidBg:SetTexture([[Interface\PaperDollInfoFrame\UI-Character-ScrollBar]], nil, "REPEAT")
    scrollMidBg:SetTexCoord(0, 0.44, 0.75, 0.98)
    scrollMidBg:SetPoint("TOPLEFT",     scrollUpBg,   "BOTTOMLEFT",  1,  2)
    scrollMidBg:SetPoint("BOTTOMRIGHT", scrollDownBg, "TOPRIGHT",   -1, -2)

    local scrollbar = CreateFrame("Slider", nil, frame, "UIPanelScrollBarTemplate")
    scrollbar:SetPoint("TOP",    scrollUpBg,   2, -18)
    scrollbar:SetPoint("BOTTOM", scrollDownBg, 2,  18)
    scrollbar.ScrollUpButton:SetScript("OnClick",   function() scroll(frame,  1) end)
    scrollbar.ScrollDownButton:SetScript("OnClick", function() scroll(frame, -1) end)
    scrollbar:SetScript("OnValueChanged", function(self, value)
        frame.value = floor(value)
        frame:Update()
    end)
    frame.scrollbar = scrollbar

    -- ── Column Headers ───────────────────────────────────────────────────────────

    local padding = 4
    frame.cols = {}
    local offset = 0
    for i, colTbl in ipairs(cols) do
        local name, width, justify = colTbl[1], colTbl[2], colTbl[3]
        local col = CreateFrame("Button", nil, frame)
        col:SetNormalFontObject("GameFontHighlightSmallLeft")
        col:SetHighlightFontObject("GameFontNormalSmallLeft")
        col:SetPoint("BOTTOMLEFT", frame, "TOPLEFT", 8 + offset, 0)
        col:SetSize(width, 18)
        col:SetText(name)
        col:GetFontString():SetAllPoints()
        if justify then
            col:GetFontString():SetJustifyH(justify)
            col.justify = justify
        end
        col.offset = offset
        col.width  = width
        offset = offset + width + padding
        frame.cols[i] = col

        col:SetScript("OnClick", function()
            frame:SortBy(i + 1)
        end)
    end

    -- ── Row Slots (virtual scrolling pool) ───────────────────────────────────────

    for slot = 1, frame.slots do
        local f = CreateFrame("Frame", nil, frame)
        f.cols = {}

        local bg = f:CreateTexture()
        bg:SetAllPoints()
        bg:SetColorTexture(Theme.accentHover[1], Theme.accentHover[2], Theme.accentHover[3], Theme.accentHover[4])
        bg:Hide()
        f.bg = bg

        f:EnableMouse(true)
        f:SetWidth(frame:GetWidth() - 38)
        f:SetHeight(frame.itemheight)

        for i, col in ipairs(frame.cols) do
            local str = localCreateString(f, "x")
            str:SetPoint("LEFT", col.offset, 0)
            str:SetWidth(col.width)
            if col.justify then str:SetJustifyH(col.justify) end
            f.cols[i] = str
        end

        frame.slot[slot] = f
        if slot > 1 then
            f:SetPoint("TOPLEFT", frame.slot[slot - 1], "BOTTOMLEFT")
        else
            f:SetPoint("TOPLEFT", frame, "TOPLEFT", 8, -8)
        end
    end

    frame:Update()
    return frame
end
