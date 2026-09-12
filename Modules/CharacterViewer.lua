-- ════════════════════════════════════════════════════════════════════════════════
-- CharacterViewer — TF_QoL module that snapshots per-character data from the
-- WoW API (ilvl, Great Vault progress, currencies, gold) and renders a single
-- themed window with one row per known character. Drop-in replacement for the
-- retired Wowthing_Viewer standalone addon.
--
-- Data source: WoW API only. No dependency on WoWthing_Collector.
-- SavedVariables: TFQoLDB.characterViewer.chars[guid] = { ... }
-- Window: BackdropTemplate, Catppuccin Mocha theme, keybind-toggleable.
-- ════════════════════════════════════════════════════════════════════════════════

local _, addon                 = ...
local module                   = {}

-- ── Localized Globals ──────────────────────────────────────────────────────────

local C_CurrencyInfo           = C_CurrencyInfo
local C_WeeklyRewards          = C_WeeklyRewards
local C_PlayerInfo             = C_PlayerInfo
local UnitGUID                 = UnitGUID
local UnitName                 = UnitName
local UnitClass                = UnitClass
local GetRealmName             = GetRealmName
local GetInventoryItemLink     = GetInventoryItemLink
local GetDetailedItemLevelInfo = GetDetailedItemLevelInfo
local GetMoney                 = GetMoney
local GetTime                  = GetTime
local RAID_CLASS_COLORS        = RAID_CLASS_COLORS
local C_Timer                  = C_Timer
local InCombatLockdown         = InCombatLockdown
local time                     = time
local pairs                    = pairs
local ipairs                   = ipairs
local tinsert                  = tinsert
local BreakUpLargeNumbers      = BreakUpLargeNumbers
local GameTooltip              = GameTooltip
local tostring                 = tostring
local table_concat             = table.concat
local GetItemInfo              = GetItemInfo
local ITEM_QUALITY_COLORS      = ITEM_QUALITY_COLORS
local C_DateAndTime            = C_DateAndTime
local date                     = date
local RED_FONT_COLOR           = RED_FONT_COLOR
local GREEN_FONT_COLOR         = GREEN_FONT_COLOR
local WHITE_FONT_COLOR         = WHITE_FONT_COLOR
local C_Bank                   = C_Bank
local Enum_BankType_Account    = Enum and Enum.BankType and Enum.BankType.Account
local issecretvalue            = issecretvalue
local tonumber                 = tonumber

-- ════════════════════════════════════════════════════════════════════════════════
-- Part 1: Constants
-- ════════════════════════════════════════════════════════════════════════════════

-- Currency tracking. The WoW API exposes the full list the in-game Currency
-- tab uses via C_CurrencyInfo.GetCurrencyListInfo(index). The list is built
-- lazily on every call (the API can pick up new entries the player earns,
-- so a cached snapshot is wrong by definition). A separate function,
-- EnsureMidnightCurrencyIDs(), walks the category tree via
-- C_CurrencyInfo.GetPlayerCurrencyCategoryInfo and returns the set of
-- currency IDs that live under the "Midnight" category — that's the set
-- the Filters popover shows.
-- Find the slice of C_CurrencyInfo.GetCurrencyListInfo that lives under
-- the given top-level header name. The list is structured as:
--   [H] Header A (depth 0)
--     entry (depth 1)
--     entry (depth 1)
--     [H] Sub-header (depth 1)
--       entry (depth 2)
--   [H] Header B (depth 0)
--     ...
-- We find Header A's position, then take everything up to the next
-- depth-0 header. Returns a set keyed by currencyID, plus the list of
-- names in order for stable sorting in the popover.
local function CollectCurrencyIDsUnderHeader(headerName)
    local lower = headerName:lower()
    local result, ordered, seen = {}, {}, {}

    local function AddCurrency(id, name, icon)
        if id then
            local idKey = tostring(id)
            if not seen[idKey] then
                seen[idKey] = true
                result[idKey] = true
                ordered[#ordered + 1] = { id = idKey, name = name, icon = icon }
            end
        end
    end

    -- Since the 12.1 currency-tab rework, the list API is no longer a
    -- reliable representation of the expansion tree. Walk the documented
    -- category API first; it includes nested Midnight groups.
    local getCategory = C_CurrencyInfo and C_CurrencyInfo.GetPlayerCurrencyCategoryInfo
    if type(getCategory) == "function" then
        local visited = {}
        local function WalkCategory(categoryID)
            if not categoryID or visited[categoryID] then return end
            visited[categoryID] = true
            local ok, info = pcall(function()
                return C_CurrencyInfo.GetPlayerCurrencyCategoryInfo(categoryID, true)
            end)
            if not ok or type(info) ~= "table" then return end
            local isTarget = type(info.categoryName) == "string"
                and info.categoryName:lower() == lower
            if isTarget then
                for _, id in ipairs(info.currencyTypes or {}) do
                    local currency
                    local currencyOK
                    currencyOK, currency = pcall(function()
                        return C_CurrencyInfo.GetCurrencyInfo(id)
                    end)
                    if not currencyOK then currency = nil end
                    AddCurrency(id, currency and currency.name, currency and currency.iconFileID)
                end
            end
            for _, childID in ipairs(info.childCategories or {}) do
                WalkCategory(childID)
            end
        end
        WalkCategory(1)
        if #ordered > 0 then return result, ordered end
    end

    -- Compatibility fallback for clients that do not expose the category API.
    local okSize, size = pcall(function() return C_CurrencyInfo.GetCurrencyListSize() end)
    if type(size) ~= "number" then size = 0 end
    local entries = {}
    for i = 1, size do
        local infoOk, info = pcall(function() return C_CurrencyInfo.GetCurrencyListInfo(i) end)
        if infoOk and info then entries[#entries + 1] = info end
    end
    local startIdx
    for i, info in ipairs(entries) do
        if info.isHeader and (info.name or ""):lower() == lower then
            startIdx = i; break
        end
    end
    if not startIdx then return result, ordered end
    local endIdx = #entries
    for i = startIdx + 1, #entries do
        if entries[i].isHeader and (entries[i].currencyListDepth or 0) == 0 then
            endIdx = i - 1; break
        end
    end
    for i = startIdx, endIdx do
        local info = entries[i]
        if not info.isHeader then
            AddCurrency(info.currencyID, info.name, info.iconFileID)
        end
    end
    return result, ordered
end

-- The list of currencies the popover shows. Built from the Midnight
-- category and its nested groups in the current currency-tab API.
-- Cache invalidated on C_CURRENCY_DISPLAY_UPDATE so newly-unlocked
-- currencies get included.
local MIDNIGHT_CURRENCY_IDS = nil
local MIDNIGHT_CURRENCY_ORDERED = nil
local MIDNIGHT_CATALOG = nil
local function EnsureMidnightCurrencyIDs()
    if MIDNIGHT_CURRENCY_IDS then return MIDNIGHT_CURRENCY_IDS, MIDNIGHT_CURRENCY_ORDERED end
    local set, ordered = CollectCurrencyIDsUnderHeader("Midnight")
    MIDNIGHT_CURRENCY_IDS = set
    MIDNIGHT_CURRENCY_ORDERED = ordered
    return set, ordered
end
local function InvalidateMidnightCache()
    MIDNIGHT_CURRENCY_IDS = nil
    MIDNIGHT_CURRENCY_ORDERED = nil
    MIDNIGHT_CATALOG = nil
end

-- Dawncrest currencies are from the retired season and should not be shown.
local function IsDawncrestCurrency(name)
    return type(name) == "string" and name:lower():find("dawncrest", 1, true) ~= nil
end

-- Build the catalog of currencies to offer in the Filters popover. The
-- popover shows the player's actual currency entries (from the live list)
-- but only those that live under the "Midnight" header.
-- Returns: { [currencyID] = { name, depth, order } }
local function EnsureCurrencyCatalog()
    local catalog = MIDNIGHT_CATALOG
    if not catalog then
        local _, ordered = EnsureMidnightCurrencyIDs()
        catalog = {}
        for idx, entry in ipairs(ordered) do
            if not IsDawncrestCurrency(entry.name) then
                catalog[tostring(entry.id)] = {
                    name = entry.name,
                    order = idx,
                    icon = entry.icon,
                }
            end
        end
        -- The API can be cold during login. Do not cache an empty catalog;
        -- the next render/event gets another chance after Blizzard populates it.
        if #ordered > 0 then MIDNIGHT_CATALOG = catalog end
    end

    -- A zero-balance currency can be absent from the current character's
    -- live list. Keep definitions learned from saved data and explicitly
    -- tracked IDs so columns and filter rows remain available here.
    local db = addon.db and addon.db.characterViewer
    local tracked = {}
    local filters = db and db.filters and db.filters.currencies or {}
    for id, enabled in pairs(filters) do
        if enabled == true then tracked[tostring(id)] = true end
    end
    for _, id in ipairs(db and db.currencyOrder or {}) do
        tracked[tostring(id)] = true
    end
    for _, char in pairs(db and db.chars or {}) do
        for id, currency in pairs(char.currencies or {}) do
            id = tostring(id)
            tracked[id] = true
            if not catalog[id] and type(currency) == "table" and currency.name
                and not IsDawncrestCurrency(currency.name) then
                catalog[id] = {
                    name = currency.name,
                    icon = currency.icon,
                    order = math.huge,
                }
            end
        end
    end
    -- GetCurrencyInfo works by ID even when the current character has zero
    -- balance and the currency is omitted from its live list.
    for id in pairs(tracked) do
        if not catalog[id] then
            local ok, info = pcall(function()
                return C_CurrencyInfo.GetCurrencyInfo(tonumber(id))
            end)
            if ok and info and info.name and not IsDawncrestCurrency(info.name) then
                catalog[id] = {
                    name = info.name,
                    icon = info.iconFileID,
                    order = math.huge,
                }
            end
        end
    end
    return catalog
end

-- Inventory slots to average for ilvl. Skip 4 (shirt).
local ILVL_SLOTS = { 1, 2, 3, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17 }
local SLOT_NAMES = {
    [1] = "Head",
    [2] = "Neck",
    [3] = "Shoulder",
    [5] = "Chest",
    [6] = "Waist",
    [7] = "Legs",
    [8] = "Feet",
    [9] = "Wrist",
    [10] = "Hands",
    [11] = "Ring 1",
    [12] = "Ring 2",
    [13] = "Trinket 1",
    [14] = "Trinket 2",
    [15] = "Cloak",
    [16] = "Main Hand",
    [17] = "Off Hand",
}

-- Map our internal column name → C_WeeklyRewards Enum.WeeklyRewardChestThresholdType.
-- Built lazily inside ResolveVaultTypes() because the Enum is not available
-- at file-load time (Blizzard_WeeklyRewards is LoadOnDemand: 1).
local VAULT_TYPE = nil
local function ResolveVaultTypes()
    if VAULT_TYPE then return VAULT_TYPE end
    local E = Enum and Enum.WeeklyRewardChestThresholdType
    VAULT_TYPE = {
        raid  = E and E.Raid,
        mp    = E and E.Activities,
        world = E and E.World,
    }
    return VAULT_TYPE
end
local VAULT_DEBOUNCE = 30 -- seconds between full snapshots

-- Window layout
local TOGGLE_BTN     = "TFQoL_CharacterViewer_Toggle"
local TOGGLE_ACTION  = "CLICK " .. TOGGLE_BTN .. ":LeftButton"
local WINDOW_NAME    = "TFQoL_CharacterViewerFrame"
local WINDOW_W       = 720 -- initial size; auto-resized per render
local WINDOW_H       = 400
local WINDOW_W_MIN   = 400
local HEADER_H       = 32
local FOOTER_H       = 24
local BINDING_NAME   = "Toggle Character Viewer"

-- Window scale limits (slider range and SetScale clamp)
local SCALE_MIN      = 0.5
local SCALE_MAX      = 1.5

-- Gold coin icon (inline texture markup for FontStrings)
local GOLD_ICON = "|TInterface\\MoneyFrame\\UI-GoldIcon:14:14:0:0:0:0:0:0|t"

-- Table column layout (shared between header and rows).
-- COL_W and COL_NAME_W are now per-render computed from the widest
-- header + data string in each column (see BuildColumnHeader). The
-- values below are the *initial* widths used for the first frame
-- before measurement runs; subsequent renders replace them.
local COL_LEFT       = 8
local COL_GAP        = 4
local COL_PAD_X      = 12 -- extra horizontal padding inside a measured cell
-- Theme shortcuts
local function T() return addon.Theme end

-- ── Measurement probe (reused across renders to avoid frame leaks) ─────
local _probeFrame
local function GetProbeFrame()
    if not _probeFrame then
        _probeFrame = CreateFrame("Frame", nil, UIParent)
        _probeFrame:Hide()
        _probeFrame:SetSize(1, 1)
    else
        for _, child in ipairs({ _probeFrame:GetChildren() }) do
            child:SetParent(nil)
        end
    end
    return _probeFrame
end

-- ════════════════════════════════════════════════════════════════════════════════
-- Part 2: Binding Header + Toggle Button
-- (Standard WoW binding system. BINDING_NAME global is read from Bindings.xml
--  via the BINDING_HEADER_TFQoL category. Mirror it here for redundancy.)
-- ════════════════════════════════════════════════════════════════════════════════

_G["BINDING_NAME_" .. TOGGLE_ACTION] = BINDING_NAME

local toggleButton
local holder
local _pendingEnable = false -- true when OnEnable was deferred by combat lockdown

-- CharacterViewer is deliberately inert during combat lockdown. Building,
-- laying out, rendering, and SavedVariables mutation are work too.
local function IsLockedDown()
    return InCombatLockdown and InCombatLockdown() or false
end

local function BuildToggleButton()
    if IsLockedDown() then return end
    toggleButton = CreateFrame("Button", TOGGLE_BTN, UIParent, "SecureActionButtonTemplate")
    toggleButton:RegisterForClicks("AnyUp")
    toggleButton:SetSize(1, 1)
    toggleButton:SetAlpha(0)
    toggleButton:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", -100, -100)
    toggleButton:SetScript("OnClick", function()
        if IsLockedDown() then return end
        module:Toggle()
    end)
end

-- ════════════════════════════════════════════════════════════════════════════════
-- Part 3: Data Capture
-- (All WoW API reads, guarded for combat restrictions. Returns a fresh row.)
-- ════════════════════════════════════════════════════════════════════════════════

local function SafeApiCall(fn, ...)
    if type(fn) ~= "function" then return nil end
    -- Guard InCombatLockdown too: it can be nil at very early file-load
    -- time if the global hadn't been populated yet, which would otherwise
    -- raise "attempt to call a nil value" and break the whole file.
    if InCombatLockdown and InCombatLockdown() then return nil end
    local ok, result = pcall(fn, ...)
    if not ok then return nil end
    return result
end

local function ComputeIlvl()
    local sum, count = 0, 0
    for _, slot in ipairs(ILVL_SLOTS) do
        local link = SafeApiCall(function() return GetInventoryItemLink("player", slot) end)
        if link then
            local details = SafeApiCall(function() return GetDetailedItemLevelInfo(link) end)
            if details then
                -- GetDetailedItemLevelInfo returns either a number, a table, or nil.
                local ilvl = type(details) == "table" and details.currentItemLevel
                    or type(details) == "number" and details
                    or nil
                if ilvl and ilvl > 0 then
                    sum = sum + ilvl
                    count = count + 1
                end
            end
        end
    end
    if count == 0 then return 0 end
    return math.floor(sum / count + 0.5)
end

local function ReadMythicPlusScore()
    if not C_PlayerInfo or not C_PlayerInfo.GetPlayerMythicPlusRatingSummary then
        return 0
    end
    local summary = SafeApiCall(function()
        return C_PlayerInfo.GetPlayerMythicPlusRatingSummary("player")
    end)
    local score = summary and summary.currentSeasonScore
    if type(score) ~= "number" or (issecretvalue and issecretvalue(score)) then
        return 0
    end
    return score
end

-- Raider.IO's public GetScoreColor API uses its generated, season-specific
-- score tier table. Prefer it when available so this column stays visually
-- identical to Raider.IO without making it a required dependency.
local function GetMythicPlusScoreColor(score)
    if type(score) ~= "number" or score <= 0 then
        return T().textPrimary
    end
    local raiderIO = _G.RaiderIO
    if raiderIO and raiderIO.GetScoreColor then
        local ok, r, g, b = pcall(raiderIO.GetScoreColor, score)
        if ok and type(r) == "number" and type(g) == "number" and type(b) == "number" then
            return { r, g, b, 1 }
        end
    end
    -- Fallback for clients where Raider.IO is not installed or has not loaded.
    -- These are the current Raider.IO detailed-tier anchor colors.
    if score >= 3425 then return { 0.64, 0.21, 0.93, 1 } end
    if score >= 3100 then return { 0.00, 0.44, 0.87, 1 } end
    if score >= 2400 then return { 0.12, 1.00, 0.00, 1 } end
    return { 1.00, 1.00, 1.00, 1 }
end

-- Read all known currencies for the current character. The catalog of
-- currency IDs is established once via EnsureCurrencyCatalog(); quantity
-- and maxQuantity are read live from the API for each.
local function ReadCurrencies()
    local out = {}
    local catalog = EnsureCurrencyCatalog()
    for id in pairs(catalog) do
        local infoOk, info = pcall(function() return C_CurrencyInfo.GetCurrencyInfo(id) end)
        if infoOk and info then
            out[tostring(id)] = {
                name          = info.name,
                icon          = info.iconFileID,
                qty           = info.quantity or 0,
                max           = info.maxQuantity or 0,
                weekQty       = info.quantityEarnedThisWeek or 0,
                weekMax       = info.maxWeeklyQuantity or 0,
                canWeekly     = info.canEarnPerWeek or false,
                totalEarned   = info.totalEarned or 0,
                useTotalEarned= info.useTotalEarnedForMaxQty or false,
            }
        end
    end
    return out
end

-- Resolve the example item hyperlink for a completed vault activity.
-- GetExampleRewardItemHyperlinks(id) is documented MayReturnNothing and
-- only returns data once the server has pre-generated the reward items
-- for the player's vault (which it does on WEEKLY_REWARDS_UPDATE, after
-- the player has interacted with the vault UI at least once this session
-- or after a clearable delay). When the player has just logged in and
-- never opened the vault, that call returns nil — so for completed-but-
-- unlinked slots we fall back to iterating info.rewards[] and pulling
-- the item link from itemDBID via GetItemHyperlink. This mirrors the
-- ResolveWeeklyRewardItemLink approach EllesmereUI's GreatVault skin
-- uses (it's the only reliable fallback; the rewards table is populated
-- by GetActivities even when the example hyperlink is stale).
local function ResolveActivityLink(info)
    if not info then return nil end
    if C_WeeklyRewards and C_WeeklyRewards.GetExampleRewardItemHyperlinks and info.id then
        local ok, link = pcall(function()
            return C_WeeklyRewards.GetExampleRewardItemHyperlinks(info.id)
        end)
        if ok and link and link ~= "" then
            return link
        end
    end
    local rewards = info.rewards
    if type(rewards) ~= "table" then return nil end
    if not C_WeeklyRewards or not C_WeeklyRewards.GetItemHyperlink then return nil end
    for _, r in ipairs(rewards) do
        if r and r.itemDBID then
            local ok, link = pcall(function()
                return C_WeeklyRewards.GetItemHyperlink(r.itemDBID)
            end)
            if ok and link and link ~= "" then
                return link
            end
        end
    end
    return nil
end

-- Build a 3-element array per vault category. Each element tracks
-- progress, threshold, and the reward item level (if the slot is
-- completed). Matches the Wowthing web layout where completed slots
-- show their ilvl and incomplete slots show "N!" (remaining count).
local function ReadVault()
    local out = { raid = {}, mp = {}, world = {} }
    for _, k in ipairs({ "raid", "mp", "world" }) do
        for i = 1, 3 do out[k][i] = { progress = 0, threshold = 0, ilvl = nil } end
    end
    if not C_WeeklyRewards or not C_WeeklyRewards.GetActivities then return out end
    local activities = SafeApiCall(C_WeeklyRewards.GetActivities)
    if type(activities) ~= "table" then return out end

    local types = ResolveVaultTypes()
    for _, info in ipairs(activities) do
        for key, t in pairs(types) do
            if t and info.type == t then
                local idx = info.index
                if idx and idx >= 1 and idx <= 3 then
                    out[key][idx].progress  = info.progress or 0
                    out[key][idx].threshold = info.threshold or 0
                    if (info.progress or 0) >= (info.threshold or 0) and info.threshold > 0 then
                        local link = ResolveActivityLink(info)
                        if link then
                            local okIlvl, ilvl = pcall(function()
                                return GetDetailedItemLevelInfo(link)
                            end)
                            if okIlvl and type(ilvl) == "number" then
                                out[key][idx].ilvl = ilvl
                            end
                            -- Extract quality hex color from item link's |c prefix.
                            -- WoW links can use |cff or |Cff (case varies).
                            local hex = link:match("|[cC][fF][fF](%x%x%x%x%x%x)")
                            if hex then
                                out[key][idx].qColor = hex
                            else
                                -- Fallback: GetItemInfo for quality → hex
                                local okQ, quality = pcall(function()
                                    local _, _, q = GetItemInfo(link)
                                    return q
                                end)
                                if okQ and type(quality) == "number" then
                                    local qc = ITEM_QUALITY_COLORS[quality]
                                    if qc and qc.color then
                                        out[key][idx].qColor =
                                            qc.color:GenerateHexColor():sub(3)
                                    end
                                end
                            end
                        end
                    end
                end
                break
            end
        end
    end
    -- Check for unclaimed vault rewards (replaces slot display with "Choose!")
    if C_WeeklyRewards and C_WeeklyRewards.HasAvailableRewards then
        local okAR, ar = SafeApiCall(C_WeeklyRewards.HasAvailableRewards)
        if okAR and ar then out.availableRewards = true end
    end
    return out
end

local function SnapshotCurrent(force)
    if IsLockedDown() then return end
    local guid = SafeApiCall(UnitGUID, "player")
    if not guid then return end
    local db = addon.db and addon.db.characterViewer
    if not db then return end
    if not db.chars then db.chars = {} end
    local existing = db.chars[guid]

    -- Debounce: skip the full snapshot if we did one recently
    if not force and existing and existing.lastFullSnapshot
        and (time() - existing.lastFullSnapshot) < VAULT_DEBOUNCE then
        return
    end

    local now                   = time()
    local _, classFile, classID = UnitClass("player")
    local row                   = existing or {}
    row.name                    = UnitName("player") or row.name or "?"
    row.realm                   = GetRealmName() or ""
    row.class                   = classFile
    row.classID                 = classID

    -- The expensive bits
    row.ilvl                    = ComputeIlvl()
    row.mplus                   = ReadMythicPlusScore()
    -- Merge vault data: preserve existing ilvl/qColor when the fresh
    -- read didn't resolve them (item cache may be cold on login/relog,
    -- causing GetDetailedItemLevelInfo to fail and overwrite stored
    -- values with nil).
    local newVault = ReadVault()
    if existing and existing.vault then
        for _, key in ipairs({ "raid", "mp", "world" }) do
            for i = 1, 3 do
                local oldSlot = existing.vault[key] and existing.vault[key][i]
                local newSlot = newVault[key] and newVault[key][i]
                if oldSlot and newSlot then
                    if not newSlot.ilvl and oldSlot.ilvl then
                        newSlot.ilvl = oldSlot.ilvl
                    end
                    if not newSlot.qColor and oldSlot.qColor then
                        newSlot.qColor = oldSlot.qColor
                    end
                end
            end
        end
    end
    row.vault                   = newVault
    row.currencies              = ReadCurrencies()
    row.gold                    = math.floor((SafeApiCall(GetMoney) or 0) / 10000)
    row.lastSeen                = now
    row.lastFullSnapshot        = now

    db.chars[guid]              = row
end

-- Cheap field updates (no debounce)
local function UpdateGold()
    if IsLockedDown() then return end
    local guid = SafeApiCall(UnitGUID, "player")
    if not guid then return end
    local row = addon.db and addon.db.characterViewer
        and addon.db.characterViewer.chars
        and addon.db.characterViewer.chars[guid]
    if not row then return end
    row.gold = math.floor((SafeApiCall(GetMoney) or 0) / 10000)
    row.lastSeen = time()
end

-- ════════════════════════════════════════════════════════════════════════════════
-- Part 4: Window Frame (Catppuccin Mocha themed, sidebar-less)
-- ════════════════════════════════════════════════════════════════════════════════

-- Forward declaration: ResetSortState is defined in Part 5 but referenced
-- by the OnHide script set in Build() below.
local ResetSortState

module.UI = {}

local function BuildHeader(parent)
    local Theme = T()
    local header = CreateFrame("Frame", nil, parent)
    header:SetHeight(HEADER_H)
    header:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)
    header:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, 0)
    -- Plain texture for bg; the border overlay (created last) draws on top.
    local headerBg = header:CreateTexture(nil, "BACKGROUND")
    headerBg:SetAllPoints(header)
    headerBg:SetColorTexture(Theme.bgDark[1], Theme.bgDark[2], Theme.bgDark[3], Theme.bgDark[4])
    header:EnableMouse(true)
    header:RegisterForDrag("LeftButton")
    header:SetScript("OnDragStart", function(self)
        if IsLockedDown() then return end
        self:GetParent():StartMoving()
    end)
    header:SetScript("OnDragStop", function(self)
        if IsLockedDown() then return end
        local frame = self:GetParent()
        frame:StopMovingOrSizing()
        local point, _, rel, x, y = frame:GetPoint()
        local db = addon.db and addon.db.characterViewer
        if db then
            db.posPoint    = point
            db.posRelPoint = rel
            db.posX        = x
            db.posY        = y
        end
    end)

    local title = header:CreateFontString(nil, "OVERLAY")
    title:SetPoint("LEFT", header, "LEFT", Theme.paddingLarge, 0)
    addon:ApplyThemeFont(title, "large")
    title:SetTextColor(Theme.accent[1], Theme.accent[2], Theme.accent[3], 1)
    title:SetText("TF |cffFFFFFFQoL|r \226\128\162 Character Viewer")
    title:SetWordWrap(false)
    header.title = title

    -- Close button: uses the same atrocityCustomCrossv3.png texture as the
    -- main TF_QoL window for visual consistency (rotated +X, color hover).
    local close = CreateFrame("Button", nil, header)
    close:SetSize(22, 22)
    close:SetPoint("RIGHT", header, "RIGHT", -Theme.paddingSmall, 0)
    local closeTex = close:CreateTexture(nil, "ARTWORK")






    closeTex:SetAllPoints()
    closeTex:SetTexture("Interface\\AddOns\\TF_QoL\\Media\\GUITextures\\atrocityCustomCrossv3.png")
    closeTex:SetVertexColor(Theme.textSecondary[1], Theme.textSecondary[2], Theme.textSecondary[3], 1)
    closeTex:SetRotation(math.rad(45))
    close:SetNormalTexture(closeTex)
    close:SetScript("OnEnter", function()
        closeTex:SetVertexColor(Theme.accent[1], Theme.accent[2], Theme.accent[3], 1)
    end)
    close:SetScript("OnLeave", function()
        closeTex:SetVertexColor(Theme.textSecondary[1], Theme.textSecondary[2], Theme.textSecondary[3], 1)
    end)
    close:SetScript("OnClick", function()
        if IsLockedDown() then return end
        module.UI:Hide()
    end)
    header.close = close

    return header
end

-- Build the small "Filters" button in the header. Click opens a popover
-- with character + currency checkboxes. Created lazily from module.UI:Build()
-- so it can be re-anchored to the constructed header frame.
function module.UI:BuildFiltersButton(header)
    if IsLockedDown() then return end
    local Theme = T()

    -- Filters button: uses the custom aesPreviewAllIcon.png texture
    -- (added alongside the other TF_QoL media).
    local btn = CreateFrame("Button", nil, header)
    btn:SetSize(22, 22)
    btn:SetPoint("RIGHT", header.close, "LEFT", -Theme.paddingSmall, 0)
    local icon = btn:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints()
    icon:SetTexture("Interface\\AddOns\\TF_QoL\\Media\\GUITextures\\aesPreviewAllIcon.png")
    icon:SetVertexColor(Theme.textMuted[1], Theme.textMuted[2], Theme.textMuted[3], 1)
    btn.icon = icon
    btn:SetScript("OnEnter", function()
        icon:SetVertexColor(Theme.textPrimary[1], Theme.textPrimary[2], Theme.textPrimary[3], 1)
    end)
    btn:SetScript("OnLeave", function()
        icon:SetVertexColor(Theme.textMuted[1], Theme.textMuted[2], Theme.textMuted[3], 1)
    end)
    btn:SetScript("OnClick", function()
        if IsLockedDown() then return end
        module.UI:ToggleFilters()
    end)
    self.filtersButton = btn
end

-- Filters popover: 2-column checkbox list of (characters, currencies).
-- State lives in TFQoLDB.characterViewer.filters = { chars = {guid=true}, currencies = {id=true} }.
-- The currency list is built dynamically from the live C_CurrencyInfo
-- catalog, not a hardcoded map.
-- Width and height are set per-refresh by RefreshFiltersPopover (auto-
-- sized to fit the longest name in each column and the row count).
-- The actual column geometry is computed in LayoutColumns; the
-- constants here are placeholders so other modules reading this file
-- can still see the names.

function module.UI:BuildFiltersPopover()
    if IsLockedDown() then return nil end
    if self.filtersPopover then return self.filtersPopover end
    local Theme = T()

    local pv = CreateFrame("Frame", nil, self.frame, "BackdropTemplate")
    pv:SetSize(400, 300) -- initial size; FitFiltersPopover overwrites
    pv:SetPoint("TOPRIGHT", self.filtersButton, "BOTTOMRIGHT", 0, -4)
    -- Highest strata + high frame level so the popover draws above all
    -- sibling controls regardless of creation order.
    pv:SetFrameStrata("TOOLTIP")
    pv:SetToplevel(true)
    pv:SetFrameLevel(self.frame:GetFrameLevel() + 50)
    pv:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = Theme.borderSize,
    })
    -- One shade lighter than the main window's bgCrust so the popover
    -- reads as an elevated surface, not a void.
    pv:SetBackdropColor(Theme.bgDark[1], Theme.bgDark[2], Theme.bgDark[3], Theme.bgDark[4])
    pv:SetBackdropBorderColor(Theme.border[1], Theme.border[2], Theme.border[3], 1)
    pv:EnableMouse(true)
    pv:SetMovable(false)
    pv:Hide()

    local title = pv:CreateFontString(nil, "OVERLAY")
    title:SetPoint("TOPLEFT", pv, "TOPLEFT", Theme.paddingMedium, -Theme.paddingSmall)
    addon:ApplyThemeFont(title, "small")
    title:SetTextColor(Theme.secondaryAccent[1], Theme.secondaryAccent[2], Theme.secondaryAccent[3], 1)
    title:SetText("Filters")

    local close = CreateFrame("Button", nil, pv)
    close:SetSize(18, 18)
    close:SetPoint("TOPRIGHT", pv, "TOPRIGHT", -Theme.paddingSmall, -2)
    local cx = close:CreateFontString(nil, "OVERLAY")
    cx:SetAllPoints()
    addon:ApplyThemeFont(cx, "small")
    cx:SetText("X")
    cx:SetTextColor(Theme.textMuted[1], Theme.textMuted[2], Theme.textMuted[3], 1)
    close:SetScript("OnClick", function()
        if IsLockedDown() then return end
        pv:Hide()
    end)

    self._filterRows = {}
    self.filtersPopover = pv
    return pv
end

local function EnsureFiltersDb()
    local db = addon.db and addon.db.characterViewer
    if not db then return nil end
    if not db.filters then db.filters = { chars = {}, currencies = {} } end
    if not db.filters.chars then db.filters.chars = {} end
    if not db.filters.currencies then db.filters.currencies = {} end
    return db
end

-- Popover layout: two side-by-side columns.  Each side has a known
-- x-anchor so the chars and currencies can never overlap.
--
--   ┌─[popover]──────────────────────────────────┐
--   │ Filters (title)                       [X]  │
--   │                                            │
--   │  [☑] Teaford    │  [☐] Artisan Alchemist's  │
--   │                 │      145  [icon]          │
--   │  [☐] Tfpal      │  [☑] Brimming Arcana     │
--   │                 │      377  [icon]          │
--   └────────────────────────────────────────────┘
--
-- The two sections are independent (their own checkboxes + rows); the
-- visual split is just a vertical guide line down the middle. We use
-- the same y for both columns' first row, then advance each column's
-- y independently, so the popover is as tall as the taller column.
local FILTERS_CHECK_SIZE   = 18
local FILTERS_ROW_H        = 22
local FILTERS_HEADER_GAP   = 32 -- top-of-popover padding before rows start
local FILTERS_BOTTOM_PAD   = 12
local FILTERS_GAP_BTW_COLS = 16
local FILTERS_LEFT_PAD     = 12
local FILTERS_RIGHT_PAD    = 12
local FILTERS_ICON_SIZE    = 18
local FILTERS_NAME_PAD     = 6 -- gap between checkbox and name
local FILTERS_GAP_NAME_AMT = 8 -- gap between name and amount

-- Build a popover-styled checkbox that highlights (green) instead of
-- showing a tiny checkmark glyph. Returns the CheckButton; the caller
-- owns positioning and the OnClick handler.
local function MakeHighlightCheck(parent, x, y, current, onChange, Theme)
    local check = CreateFrame("CheckButton", nil, parent, "BackdropTemplate")
    check:SetSize(FILTERS_CHECK_SIZE, FILTERS_CHECK_SIZE)
    check:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    check:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    local function applyVisual()
        if check:GetChecked() then
            check:SetBackdropColor(Theme.success[1], Theme.success[2], Theme.success[3], 0.55)
            check:SetBackdropBorderColor(Theme.success[1], Theme.success[2], Theme.success[3], 1)
        else
            check:SetBackdropColor(Theme.bgLight[1], Theme.bgLight[2], Theme.bgLight[3], 1)
            check:SetBackdropBorderColor(Theme.border[1], Theme.border[2], Theme.border[3], 1)
        end
    end
    check:SetChecked(current)
    applyVisual()
    check:SetScript("OnClick", function(self)
        if IsLockedDown() then return end
        onChange(self:GetChecked())
        applyVisual()
    end)
    return check
end

-- Build a char row in the popover's left column.
-- Layout: [checkbox] [class-colored name]
local function AddCharRow(parent, y, charX, charInfo, current, onChange, Theme)
    local check = MakeHighlightCheck(parent, charX, y, current, onChange, Theme)

    -- Class color for the name (e.g. green Hunter, pink Mage).
    local cc = (charInfo.class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[charInfo.class])
        or Theme.textPrimary
    local fs = parent:CreateFontString(nil, "OVERLAY")
    fs:SetPoint("TOPLEFT", check, "TOPRIGHT", FILTERS_NAME_PAD, 0)
    addon:ApplyThemeFont(fs, "normal")
    fs:SetTextColor(cc.r, cc.g, cc.b, cc.a or 1)
    fs:SetText(charInfo.name or "?")
    fs:SetJustifyH("LEFT")
    fs:SetWordWrap(false)
    return { checkbox = check, label = fs }
end

-- Build a currency row in the popover's right column.
-- Layout (matches the in-game Currency tab):
--   [checkbox] [name] ............ [amount] [icon]
-- The amount and icon are vertically centered on the row (the previous
-- implementation anchored them to the top-right, which put them above
-- the name).
local function AddCurrencyRow(parent, y, curX, currencyID, name, current, onChange,
                              iconTexture, qtyText, r, g, b, Theme)
    local check = MakeHighlightCheck(parent, curX, y, current, onChange, Theme)

    local fs = parent:CreateFontString(nil, "OVERLAY")
    fs:SetPoint("TOPLEFT", check, "TOPRIGHT", FILTERS_NAME_PAD, 0)
    addon:ApplyThemeFont(fs, "normal")
    fs:SetTextColor(Theme.textPrimary[1], Theme.textPrimary[2], Theme.textPrimary[3], 1)
    fs:SetText(name)
    fs:SetJustifyH("LEFT")
    fs:SetWordWrap(false)

    local amount = parent:CreateFontString(nil, "OVERLAY")
    -- The amount is anchored to the checkbox's right edge (not the
    -- icon) and the icon is anchored to the checkbox's right edge (not
    -- the amount). This avoids the circular anchor that WoW rejects
    -- ("Cannot anchor to a region dependent on it"). The visual gap
    -- between amount and icon is produced by giving the amount a fixed
    -- width and putting the icon at a known offset.
    addon:ApplyThemeFont(amount, "normal")
    -- Color follows the in-game Currency tab's cap rule (red over-cap,
    -- gold at-cap, neutral otherwise). Pre-computed in the caller.
    amount:SetTextColor(r or Theme.textPrimary[1],
        g or Theme.textPrimary[2],
        b or Theme.textPrimary[3], 1)
    amount:SetText(qtyText)
    amount:SetJustifyH("RIGHT")
    amount:SetWordWrap(false)
    -- Reserve a fixed slot for the amount text. Sized in RefreshFiltersPopover
    -- once we've measured the widest qty/max sample across the column.
    amount:SetWidth(60) -- placeholder; resized by caller
    -- Anchor the amount's right edge to (icon's left edge), but to
    -- avoid a cycle, anchor to the CHECKBOX at a known x-offset that
    -- we'll re-set after the icon is placed. The simpler approach is
    -- to anchor the amount's right edge to a fixed x near the popover
    -- right side; the caller (RefreshFiltersPopover) re-anchors with
    -- the correct x once it knows the popover width.
    amount:SetPoint("RIGHT", check, "RIGHT", 0, 0)
    amount:SetPoint("TOP", check, "TOP", 0, 1) -- align with checkbox top

    -- Match the table headers: crop 6% total (3% per edge) and add a
    -- crisp 1px black keyline around the currency icon.
    local iconFrame = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    iconFrame:SetFrameLevel(parent:GetFrameLevel() + 2)
    iconFrame:SetSize(FILTERS_ICON_SIZE + 2, FILTERS_ICON_SIZE + 2)
    iconFrame:SetBackdrop({
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    iconFrame:SetBackdropBorderColor(0, 0, 0, 1)
    iconFrame:SetPoint("TOP", check, "TOP", 0, 1)
    -- Make the icon a child of the bordered frame. A texture created on
    -- the popover can sit underneath the frame's backdrop layer, leaving
    -- only the keyline visible.
    local icon = iconFrame:CreateTexture(nil, "ARTWORK")
    -- Keep the texture one pixel inside the frame so the backdrop keyline
    -- remains visible on every edge.
    icon:SetPoint("TOPLEFT", iconFrame, "TOPLEFT", 1, -1)
    icon:SetPoint("BOTTOMRIGHT", iconFrame, "BOTTOMRIGHT", -1, 1)
    icon:SetTexCoord(0.03, 0.97, 0.03, 0.97)
    -- The category API does not consistently include iconFileID. Resolve it
    -- again by currency ID; passing the normalized string directly can also
    -- return an incomplete record on patched clients.
    if not iconTexture and C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfo then
        local ok, info = pcall(function()
            return C_CurrencyInfo.GetCurrencyInfo(tonumber(currencyID))
        end)
        if ok and info then iconTexture = info.iconFileID end
    end
    if iconTexture then
        icon:SetTexture(tonumber(iconTexture) or iconTexture)
    end
    icon:Show()
    iconFrame:Show()

    -- Hover region: an invisible full-row button so the user can hover
    -- anywhere on the row to see the currency tooltip, like the in-game
    -- Currency tab. We use a Button (not CheckButton) so it doesn't
    -- interfere with the checkbox state. Width is set later (after we
    -- know the popover width) by RefreshFiltersPopover.
    local hit = CreateFrame("Button", nil, parent)
    hit:SetSize(100, FILTERS_ROW_H)
    hit:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, y)
    hit:EnableMouse(true)
    hit.currencyID = currencyID
    hit:SetScript("OnEnter", function(self)
        if not self.currencyID then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetCurrencyByID(self.currencyID)
    end)
    hit:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return { checkbox = check, label = fs, amount = amount, icon = icon, iconFrame = iconFrame, hit = hit }
end

-- Compute the right column's x-anchor and name-column width for the
-- popover, given the measured widths of both columns. Each column gets
-- its own x and its own name width; the popover is the wider of the
-- two plus a 1px vertical separator.
local function LayoutColumns(Theme, charNameW, curNameW)
    -- Left column: checkbox + name + (some right pad) — never overlaps right.
    -- Right column: checkbox + name + amount + icon + right pad.
    local leftColW  = FILTERS_LEFT_PAD + FILTERS_CHECK_SIZE + FILTERS_NAME_PAD
        + charNameW + FILTERS_LEFT_PAD
    local rightColW = FILTERS_LEFT_PAD + FILTERS_CHECK_SIZE + FILTERS_NAME_PAD
        + curNameW
        + FILTERS_GAP_NAME_AMT -- gap between name and amount
        + 60                   -- room for "999,999 / 999,999"
        + FILTERS_ICON_SIZE
        + FILTERS_RIGHT_PAD
    local totalW    = leftColW + FILTERS_GAP_BTW_COLS + rightColW
    return {
        charX  = FILTERS_LEFT_PAD,
        charW  = leftColW,
        curX   = leftColW + FILTERS_GAP_BTW_COLS + FILTERS_LEFT_PAD,
        totalW = totalW,
        sepX   = leftColW + FILTERS_GAP_BTW_COLS / 2,
    }
end

function module.UI:RefreshFiltersPopover()
    if IsLockedDown() then return end
    if not self.filtersPopover then return end
    if self._filterRows then
        for _, row in ipairs(self._filterRows) do
            if row.checkbox then
                row.checkbox:Hide(); row.checkbox:SetParent(nil)
            end
            if row.label then
                row.label:Hide(); row.label:SetParent(nil)
            end
            if row.amount then
                row.amount:Hide(); row.amount:SetParent(nil)
            end
            if row.icon then
                row.icon:Hide(); row.icon:SetParent(nil)
            end
            if row.iconFrame then
                row.iconFrame:Hide(); row.iconFrame:SetParent(nil)
            end
            if row.hit then
                row.hit:Hide(); row.hit:SetParent(nil)
            end
            if row.sep then
                row.sep:Hide(); row.sep:SetParent(nil)
            end
        end
    end
    self._filterRows = {}

    local Theme = T()
    local db = EnsureFiltersDb()
    if not db then return end

    local catalog = EnsureCurrencyCatalog()

    -- Build the left-column (chars) list, sorted alphabetically.
    local chars = {}
    for guid, row in pairs(db.chars or {}) do
        if type(row) == "table" then
            chars[#chars + 1] = { guid = guid, name = row.name or guid, class = row.class }
        end
    end
    table.sort(chars, function(a, b) return (a.name or "") < (b.name or "") end)

    -- Build the right-column (currencies) list, sorted by in-game order.
    local currencies = {}
    for id, entry in pairs(catalog) do
        currencies[#currencies + 1] = {
            id = id, name = entry.name, order = entry.order,
        }
    end
    table.sort(currencies, function(a, b) return (a.order or 0) < (b.order or 0) end)

    -- Cache currency info from the API once per refresh so we don't
    -- hammer the API for icon/qty/max for every row. Also pre-compute
    -- the qty/max text and the in-game cap color per row so the layout
    -- loop doesn't repeat the work.
    local infoCache = {}
    for _, c in ipairs(currencies) do
        local catalogEntry = catalog[tostring(c.id)] or {}
        local ok, info = pcall(function()
            return C_CurrencyInfo.GetCurrencyInfo(tonumber(c.id))
        end)
        if ok and info then
            local qty = info.quantity or 0
            local mx  = info.maxQuantity or 0
            -- Color rule (matches the in-game Currency tab):
            --   over-capped (qty > max and max > 0): red
            --   capped     (qty == max and max > 0): gold
            --   otherwise (or unbounded max):         textPrimary
            local r, g, b
            if mx > 0 and qty > mx then
                r, g, b = Theme.error[1], Theme.error[2], Theme.error[3]
            elseif mx > 0 and qty >= mx then
                r, g, b = Theme.yellow[1], Theme.yellow[2], Theme.yellow[3]
            else
                r, g, b = Theme.textPrimary[1], Theme.textPrimary[2], Theme.textPrimary[3]
            end
            local qtyText = mx > 0
                and (BreakUpLargeNumbers(qty) .. " / " .. BreakUpLargeNumbers(mx))
                or BreakUpLargeNumbers(qty)
            infoCache[c.id] = {
                icon = info.iconFileID or catalogEntry.icon,
                qty = qty,
                max = mx,
                qtyText = qtyText,
                r = r,
                g = g,
                b = b,
            }
        end
    end

    -- Measure the widest name in each column. Two throwaway FontStrings
    -- on a hidden parent: the same font the rows use, so widths match.
    local probe = GetProbeFrame()
    local nameProbe = probe:CreateFontString(nil, "OVERLAY")
    addon:ApplyThemeFont(nameProbe, "normal")
    nameProbe:SetWordWrap(false)
    local amtProbe = probe:CreateFontString(nil, "OVERLAY")
    addon:ApplyThemeFont(amtProbe, "normal")
    amtProbe:SetWordWrap(false)

    local maxCharName = 0
    for _, c in ipairs(chars) do
        nameProbe:SetText(c.name or "")
        local w = nameProbe:GetStringWidth() or 0
        if w > maxCharName then maxCharName = w end
    end
    local maxCurName = 0
    local maxAmt = 0
    for _, c in ipairs(currencies) do
        nameProbe:SetText(c.name or "")
        local w = nameProbe:GetStringWidth() or 0
        if w > maxCurName then maxCurName = w end
        local info = infoCache[c.id]
        amtProbe:SetText(info and info.qtyText or "0")
        local aw = amtProbe:GetStringWidth() or 0
        if aw > maxAmt then maxAmt = aw end
    end

    -- Compute the two-column popover geometry. We pass the measured
    -- widths; LayoutColumns returns x-anchors and the total width.
    local layout = LayoutColumns(Theme,
        math.ceil(maxCharName) + 4,
        math.ceil(maxCurName) + 4)
    -- The amount column in the right side needs `maxAmt` of horizontal
    -- space; widen the popover if needed.
    local amtSlot = 60 -- baseline reservation from LayoutColumns
    if maxAmt + 8 > amtSlot then
        layout.totalW = layout.totalW + (math.ceil(maxAmt) + 8 - amtSlot)
    end

    -- Vertical separator: a thin line between the two columns. Created
    -- once and reused.
    local sep = self.filtersPopover:CreateTexture(nil, "BACKGROUND")
    sep:SetWidth(Theme.borderSize)
    sep:SetPoint("TOPLEFT", self.filtersPopover, "TOPLEFT", layout.sepX, -8)
    sep:SetPoint("BOTTOMLEFT", self.filtersPopover, "BOTTOMLEFT", layout.sepX, 8)
    sep:SetColorTexture(Theme.borderSubtle[1], Theme.borderSubtle[2], Theme.borderSubtle[3], 0.7)

    -- Two parallel columns. Each gets its own y cursor so they're
    -- independent. The popover is as tall as the taller column.
    local yChar = -FILTERS_HEADER_GAP
    local yCur  = -FILTERS_HEADER_GAP
    -- Char rows (left column)
    for _, c in ipairs(chars) do
        local row = AddCharRow(self.filtersPopover, yChar, layout.charX, c,
            db.filters.chars[c.guid] ~= false,
            function(v)
                if IsLockedDown() then return end
                db.filters.chars[c.guid] = v; module.UI:Render()
            end,
            Theme)
        row.label:SetWidth(layout.charW - FILTERS_LEFT_PAD - FILTERS_CHECK_SIZE - FILTERS_NAME_PAD)
        self._filterRows[#self._filterRows + 1] = row
        yChar = yChar - FILTERS_ROW_H
    end
    if #chars == 0 then
        local fs = self.filtersPopover:CreateFontString(nil, "OVERLAY")
        fs:SetPoint("TOPLEFT", self.filtersPopover, "TOPLEFT", layout.charX + FILTERS_CHECK_SIZE + FILTERS_NAME_PAD,
            yChar)
        addon:ApplyThemeFont(fs, "normal")
        fs:SetTextColor(Theme.textMuted[1], Theme.textMuted[2], Theme.textMuted[3], 1)
        fs:SetText("(no characters yet)")
        fs:SetJustifyH("LEFT")
        fs:SetWordWrap(false)
        self._filterRows[#self._filterRows + 1] = { label = fs }
        yChar = yChar - FILTERS_ROW_H
    end

    -- Currency rows (right column)
    for _, c in ipairs(currencies) do
        local info = infoCache[c.id] or {
            icon = (catalog[tostring(c.id)] or {}).icon,
            qtyText = "0",
            r = Theme.textPrimary[1], g = Theme.textPrimary[2], b = Theme.textPrimary[3],
        }
        local row = AddCurrencyRow(self.filtersPopover, yCur, layout.curX, c.id, c.name,
            db.filters.currencies[tostring(c.id)] ~= false,
            function(v)
                if IsLockedDown() then return end
                db.filters.currencies[tostring(c.id)] = v; module.UI:Render()
            end,
            info.icon, info.qtyText, info.r, info.g, info.b, Theme)
        -- Width for the currency name slot: popover - curX - checkbox -
        -- name-pad - amount - icon - paddings.
        local amtW = math.max(maxAmt, 60)
        local rightSlot = layout.totalW
            - (layout.curX - layout.charX) -- offset to right col start
            - FILTERS_LEFT_PAD
            - FILTERS_RIGHT_PAD
            - FILTERS_GAP_NAME_AMT
            - FILTERS_ICON_SIZE
            - amtW - 4
        row.label:SetWidth(math.max(40, rightSlot))
        -- Re-anchor the amount and icon to the popover's right edge,
        -- so the column lines up exactly for every row. We avoid the
        -- circular anchor by anchoring both to the popover (parent),
        -- not to each other.
        row.amount:SetWidth(amtW)
        row.amount:ClearAllPoints()
        row.amount:SetPoint("TOPRIGHT", self.filtersPopover, "TOPRIGHT",
            -(FILTERS_RIGHT_PAD + FILTERS_ICON_SIZE + 4),
            yCur) -- same y as checkbox (top-aligned)
        -- The texture is parented to iconFrame; move only the bordered
        -- frame so the texture stays inside it.
        row.iconFrame:ClearAllPoints()
        row.iconFrame:SetPoint("TOPRIGHT", self.filtersPopover, "TOPRIGHT",
            -FILTERS_RIGHT_PAD, yCur) -- same y as checkbox
        self._filterRows[#self._filterRows + 1] = row
        yCur = yCur - FILTERS_ROW_H
    end

    -- Now that we know the popover width, set the hit region on every
    -- currency row. Each hit covers from the right column's x to the
    -- popover's right edge, so the user can hover the whole row.
    local hitLeftX = layout.curX - FILTERS_LEFT_PAD
    -- Walk through currency rows by their order in _filterRows
    -- (chars first, then currencies) and assign hit regions.
    local curIdx = 0
    for _, row in ipairs(self._filterRows) do

        if row.hit then

            curIdx = curIdx + 1

            local y = -FILTERS_HEADER_GAP - (curIdx - 1) * FILTERS_ROW_H

            row.hit:ClearAllPoints()

            row.hit:SetPoint("TOPLEFT", self.filtersPopover, "TOPLEFT", hitLeftX, y)

            row.hit:SetSize(layout.totalW - hitLeftX - FILTERS_RIGHT_PAD, FILTERS_ROW_H)
        end
    end

    -- Height: header gap + max of the two column heights + bottom pad.
    local leftRows  = math.max(#chars, 1)
    local rightRows = math.max(#currencies, 1)
    local nRows     = math.max(leftRows, rightRows)
    local popH      = math.max(
        FILTERS_HEADER_GAP + nRows * FILTERS_ROW_H + FILTERS_BOTTOM_PAD,
        120)

    self.filtersPopover:SetSize(layout.totalW, popH)
    self.filtersPopover._filterSep = sep
    self._filterRows[#self._filterRows + 1] = { sep = sep }
end

function module.UI:ToggleFilters()
    if IsLockedDown() then return end
    if not self.filtersPopover then self:BuildFiltersPopover() end
    self:RefreshFiltersPopover()
    if self.filtersPopover:IsShown() then
        self.filtersPopover:Hide()
    else
        self.filtersPopover:Show()
    end
end

-- ── Journalator Profit Tooltip ─────────────────────────────────────────────────
-- Custom Catppuccin Mocha themed tooltip replicating Journalator's minimap tooltip.
-- Shows Monthly/Weekly/Daily Profit (gold only, no silver/copper).
-- Uses Journalator.GetProfit + Journalator.Archiving at runtime; gracefully
-- degrades when Journalator is not installed or archive not yet loaded.

local function GetMonthPeriod()
    local origin = time()
    local resetTime = date("*t", origin - 24 * 60 * 60 + C_DateAndTime.GetSecondsUntilDailyReset())
    local d = date("*t")
    d.min = resetTime.min
    d.hour = resetTime.hour
    d.sec = resetTime.sec
    d.day = 1
    local result = time(d)
    if result > origin then
        d.month = d.month - 1
        if d.month < 1 then
            d.month = 12
            d.year = d.year - 1
        end
    end
    return origin - time(d)
end

local function GetWeekPeriod()
    return 7 * 24 * 60 * 60 - C_DateAndTime.GetSecondsUntilWeeklyReset()
end

local function GetDayPeriod()
    return 24 * 60 * 60 - C_DateAndTime.GetSecondsUntilDailyReset()
end

local function IsJournalatorAvailable()
    return Journalator ~= nil
        and type(Journalator.GetProfit) == "function"
        and type(Journalator.Archiving) == "table"
        and type(Journalator.Archiving.IsLoadedUpTo) == "function"
end

-- Format profit in copper as gold-only string (no silver/copper)
local function FormatProfitGold(profit)
    local gold = math.floor(math.abs(profit) / 10000)
    local str = BreakUpLargeNumbers(gold) .. GOLD_ICON
    if profit < 0 then str = "-" .. str end
    return str
end

local function GetProfitRaw(period)
    return Journalator.GetProfit(time() - period, time(), function(item)
        return not item.playerCheck or Journalator.CheckCharacter(item.playerCheck, item.source)
    end)
end

-- Custom themed tooltip frame (lazy-init, reused across hovers)
local GoldTooltip

local function GetGoldTooltip()
    if GoldTooltip then return GoldTooltip end
    local T = T()
    local tip = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    tip:SetSize(200, 100) -- non-zero before SetBackdrop so textures initialize
    tip:SetFrameStrata("TOOLTIP")
    tip:SetClampedToScreen(true)
    tip:Hide()
    tip:SetBackdrop({
        bgFile = "Interface\Buttons\WHITE8X8",
        edgeFile = "Interface\Buttons\WHITE8X8",
        edgeSize = T.borderSize,
    })
    tip:SetBackdropColor(T.bgDark[1], T.bgDark[2], T.bgDark[3], 0.97)
    tip:SetBackdropBorderColor(T.border[1], T.border[2], T.border[3], 1)
    -- Header FontString
    local header = tip:CreateFontString(nil, "OVERLAY")
    addon:ApplyThemeFont(header, "small")
    header:SetTextColor(T.secondaryAccent[1], T.secondaryAccent[2], T.secondaryAccent[3])
    header:SetPoint("TOPLEFT", tip, "TOPLEFT", T.paddingMedium, -T.paddingMedium)
    header:SetWordWrap(false)
    tip.header = header
    -- Three label/value rows
    tip.rows = {}
    for i = 1, 3 do
        local label = tip:CreateFontString(nil, "OVERLAY")
        addon:ApplyThemeFont(label, "small")
        label:SetTextColor(T.textSecondary[1], T.textSecondary[2], T.textSecondary[3])
        label:SetJustifyH("LEFT")
        label:SetWordWrap(false)
        local value = tip:CreateFontString(nil, "OVERLAY")
        addon:ApplyThemeFont(value, "small")
        value:SetJustifyH("RIGHT")
        value:SetWordWrap(false)
        tip.rows[i] = { label = label, value = value }
    end
    -- Note line (for "Open to see stats" / "Not installed")
    local note = tip:CreateFontString(nil, "OVERLAY")
    addon:ApplyThemeFont(note, "small")
    note:SetTextColor(T.textMuted[1], T.textMuted[2], T.textMuted[3])
    note:SetPoint("TOPLEFT", tip, "TOPLEFT", T.paddingMedium, -T.paddingMedium)
    note:SetWordWrap(false)
    tip.note = note
    GoldTooltip = tip
    return tip
end

local function ApplyTipBackdrop(tip)
    local T = T()
    tip:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = T.borderSize,
    })
    tip:SetBackdropColor(T.bgDark[1], T.bgDark[2], T.bgDark[3], 0.97)
    tip:SetBackdropBorderColor(T.border[1], T.border[2], T.border[3], 1)
end

local function ShowGoldTooltip(anchor)
    local T = T()
    local tip = GetGoldTooltip()
    tip:ClearAllPoints()
    tip:SetPoint("BOTTOMLEFT", anchor, "TOPRIGHT", 1, -1)

    if not IsJournalatorAvailable() then
        tip.header:Hide()
        for _, r in ipairs(tip.rows) do r.label:Hide(); r.value:Hide() end
        tip.note:SetText("Journalator not installed")
        tip.note:Show()
        tip:SetSize(
            tip.note:GetStringWidth() + T.paddingMedium * 2,
            T.paddingMedium * 2 + (tip.note:GetStringHeight() or 14)
        )
        ApplyTipBackdrop(tip)
        tip:Show()
        return
    end

    local startPoint = time() - math.max(GetMonthPeriod(), GetDayPeriod())
    if not Journalator.Archiving.IsLoadedUpTo(startPoint) then
        tip.header:Hide()
        for _, r in ipairs(tip.rows) do r.label:Hide(); r.value:Hide() end
        tip.note:SetText("Loading Journalator data...")
        tip.note:Show()
        tip:SetSize(
            tip.note:GetStringWidth() + T.paddingMedium * 2,
            T.paddingMedium * 2 + (tip.note:GetStringHeight() or 14)
        )
        ApplyTipBackdrop(tip)
        tip:Show()
        return
    end

    tip.note:Hide()
    tip.header:Show()
    tip.header:SetText("Journalator")

    local periods = {
        { label = "Monthly Profit", period = GetMonthPeriod() },
        { label = "Weekly Profit",  period = GetWeekPeriod()  },
        { label = "Daily Profit",   period = GetDayPeriod()   },
    }

    local maxLabelW = 0
    local maxValueW = 0
    for i, p in ipairs(periods) do
        local profit = GetProfitRaw(p.period)
        local profitStr = FormatProfitGold(profit)
        local row = tip.rows[i]
        row.label:SetText(p.label)
        row.value:SetText(profitStr)
        if profit < 0 then
            row.value:SetTextColor(T.error[1], T.error[2], T.error[3])
        else
            row.value:SetTextColor(T.success[1], T.success[2], T.success[3])
        end
        row.label:Show()
        row.value:Show()
        local lw = row.label:GetStringWidth() or 0
        local vw = row.value:GetStringWidth() or 0
        if lw > maxLabelW then maxLabelW = lw end
        if vw > maxValueW then maxValueW = vw end
    end

    local pad = T.paddingMedium
    local gap = 24
    local rowH = 14
    local colGap = 40
    local totalW = pad + maxLabelW + colGap + maxValueW + pad
    local headerH = rowH + 4
    local totalH = pad + headerH + #periods * rowH + pad

    tip.header:SetPoint("TOPLEFT", tip, "TOPLEFT", pad, -pad)
    for i, p in ipairs(periods) do
        local row = tip.rows[i]
        local y = pad + headerH + (i - 1) * rowH
        row.label:SetPoint("TOPLEFT", tip, "TOPLEFT", pad, -y)
        row.label:SetWidth(maxLabelW + colGap)
        row.value:SetPoint("TOPRIGHT", tip, "TOPRIGHT", -pad, -y)
        row.value:SetWidth(maxValueW + pad)
    end
    tip:SetSize(totalW, totalH)
    ApplyTipBackdrop(tip)
    tip:Show()
end

local function HideGoldTooltip()
    if GoldTooltip then GoldTooltip:Hide() end
end

-- Proactively request Journalator archive loading so data is ready on hover
local journalatorArchiveRequested = false
local function EnsureJournalatorArchiveLoaded()
    if journalatorArchiveRequested then return end
    if not IsJournalatorAvailable() then return end
    local startPoint = time() - math.max(GetMonthPeriod(), GetDayPeriod())
    if Journalator.Archiving.IsLoadedUpTo(startPoint) then
        journalatorArchiveRequested = true
        return
    end
    journalatorArchiveRequested = true
    Journalator.Archiving.LoadUpTo(0, function()
        -- Archive loaded; next hover will show data
    end)
end

-- Shared bind-label text (footer build + BINDINGS_LOADED refresh).
local function SetBindLabelText(label)
    local key = GetBindingKey(TOGGLE_ACTION) or ""
    label:SetText("Bind: " .. (key ~= "" and key or "Not bound"))
end

local function BuildFooter(parent)
    local Theme = T()
    local footer = CreateFrame("Frame", nil, parent)
    footer:SetHeight(FOOTER_H)
    footer:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", 0, 0)
    footer:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", 0, 0)
    -- Plain texture for bg; the border overlay (created last) draws on top.
    local footerBg = footer:CreateTexture(nil, "BACKGROUND")
    footerBg:SetAllPoints(footer)
    footerBg:SetColorTexture(Theme.bgDark[1], Theme.bgDark[2], Theme.bgDark[3], Theme.bgDark[4])

    local left = footer:CreateFontString(nil, "OVERLAY")
    left:SetPoint("LEFT", footer, "LEFT", Theme.paddingMedium, 0)
    addon:ApplyThemeFont(left, "small")
    left:SetTextColor(Theme.textMuted[1], Theme.textMuted[2], Theme.textMuted[3], 1)
    SetBindLabelText(left)
    left:SetWordWrap(false)
    footer.bindLabel = left

    -- Total gold: clickable, shows Journalator profit tooltip on hover
    local goldBtn = CreateFrame("Button", nil, footer)
    goldBtn:SetPoint("RIGHT", footer, "RIGHT", 0, 0)
    goldBtn:SetSize(140, FOOTER_H)
    goldBtn:EnableMouse(true)
    local right = goldBtn:CreateFontString(nil, "OVERLAY")
    right:SetPoint("RIGHT", goldBtn, "RIGHT", -Theme.paddingMedium, 0)
    addon:ApplyThemeFont(right, "small")
    right:SetTextColor(Theme.textMuted[1], Theme.textMuted[2], Theme.textMuted[3], 1)
    right:SetText("")
    right:SetWordWrap(false)
    goldBtn:SetFontString(right)
    goldBtn:SetScript("OnEnter", function(self)
        right:SetTextColor(Theme.textPrimary[1], Theme.textPrimary[2], Theme.textPrimary[3], 1)
        ShowGoldTooltip(self)
    end)
    goldBtn:SetScript("OnLeave", function()
        right:SetTextColor(Theme.textMuted[1], Theme.textMuted[2], Theme.textMuted[3], 1)
        HideGoldTooltip()
    end)
    goldBtn:SetScript("OnClick", function()
        if IsLockedDown() then return end
        if Journalator and type(Journalator.ToggleView) == "function" then
            Journalator.ToggleView()
        end
    end)
    footer.totalGoldLabel = right
    footer.totalGoldBtn = goldBtn

    -- Subtle separator at top of footer
    local sep = footer:CreateTexture(nil, "ARTWORK")
    sep:SetHeight(Theme.borderSize)
    sep:SetPoint("TOPLEFT", footer, "TOPLEFT", 0, 0)
    sep:SetPoint("TOPRIGHT", footer, "TOPRIGHT", 0, 0)
    sep:SetColorTexture(Theme.borderSubtle[1], Theme.borderSubtle[2], Theme.borderSubtle[3], 1)

    return footer
end

function module.UI:Build()
    if IsLockedDown() then return nil end
    if self.frame then return self.frame end
    local Theme = T()
    local db = addon.db and addon.db.characterViewer

    local frame = CreateFrame("Frame", WINDOW_NAME, UIParent, "BackdropTemplate")
    frame:SetSize(WINDOW_W, WINDOW_H)
    frame:SetScale((db and tonumber(db.scale)) or 1.0)
    frame:SetFrameStrata("DIALOG")
    frame:SetToplevel(true)
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:Hide()
    frame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = Theme.borderSize,
    })
    frame:SetBackdropColor(Theme.bgCrust[1], Theme.bgCrust[2], Theme.bgCrust[3], Theme.bgCrust[4])
    frame:SetBackdropBorderColor(Theme.border[1], Theme.border[2], Theme.border[3], 1)

    if db and db.posX and db.posY and db.posPoint then
        frame:SetPoint(db.posPoint, UIParent, db.posRelPoint or db.posPoint, db.posX, db.posY)
    else
        frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    end

    -- ESC closes the window
    tinsert(UISpecialFrames, WINDOW_NAME)

    -- Reset sort to default whenever the frame is hidden by any path
    -- (ESC key, close button, Toggle, module:OnDisable)
    frame:SetScript("OnHide", function() ResetSortState() end)

    local header = BuildHeader(frame)
    local footer = BuildFooter(frame)
    module.UI:BuildFiltersButton(header)

    -- Body host
    local body = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    body:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, Theme.borderSize)
    body:SetPoint("BOTTOMRIGHT", footer, "TOPRIGHT", 0, -Theme.borderSize)
    -- Body has its own backdrop with a top/bottom edge so the border is
    -- visible against the header/footer. The frame's left/right edges
    -- show through on the sides (the body is inset by 0 horizontally).
    -- Without these insets, the body's solid bg would be hidden under
    -- the frame's border on the sides, and the top/bottom would butt
    -- up against the header/footer with no border.
    -- Body has no border; the overlay frame (created last) draws the
    -- window border on top of everything.
    body:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
    })
    body:SetBackdropColor(Theme.bgMedium[1], Theme.bgMedium[2], Theme.bgMedium[3], Theme.bgMedium[4])
    body:EnableMouse(false)
    self.body = body

    -- Border overlay: drawn last so it renders ON TOP of header, body,
    -- and footer. In WoW, child frames always paint over parent backdrop
    -- edges, so the only way to get a visible border around the whole
    -- window is to draw it in a child frame that's created after
    -- everything else.
    local border = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    border:SetAllPoints(frame)
    border:SetBackdrop({
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = Theme.borderSize,
    })
    border:SetBackdropBorderColor(Theme.border[1], Theme.border[2], Theme.border[3], 1)
    border:SetFrameLevel(frame:GetFrameLevel() + 10)
    border:EnableMouse(false)

    self.frame = frame
    self.header = header
    self.footer = footer
    -- Fresh body host: drop any recycled row frames from a previous build.
    self._rowFrames = nil
    self._structSig = nil
    self._staticSig = nil
    return frame
end

-- ════════════════════════════════════════════════════════════════════════════════
-- Part 5: Render — table of characters
-- ════════════════════════════════════════════════════════════════════════════════

local function RelTime(ts)
    if not ts or ts == 0 then return "never" end
    local d = time() - ts
    if d < 60 then return "just now" end
    if d < 3600 then return math.floor(d / 60) .. "m ago" end
    if d < 86400 then return math.floor(d / 3600) .. "h ago" end
    if d < 86400 * 30 then return math.floor(d / 86400) .. "d ago" end
    return math.floor(d / 86400 / 30) .. "mo ago"
end

-- Hex color markup shared by the name-line builders below.
local function ColorHex(color)
    return string.format("%02x%02x%02x",
        color[1] * 255, color[2] * 255, color[3] * 255)
end

-- One-line row label: "Name - Realm · 1m ago" with the realm and timestamp
-- appended as muted text. Single source of truth for BuildCharRow and the
-- pre-render width measurement.
local function BuildNameLabelText(rowData)
    local Theme = T()
    local parts = { rowData.name or "?" }
    if rowData.realm and rowData.realm ~= "" then
        parts[#parts + 1] = "|cff" .. ColorHex(Theme.textMuted)
            .. "- " .. rowData.realm .. "|r"
    end
    local relText = RelTime(rowData.lastSeen)
    if relText and relText ~= "" then
        parts[#parts + 1] = "|cff" .. ColorHex(Theme.textSubtle)
            .. "· " .. relText .. "|r"
    end
    return table_concat(parts, " ")
end

-- ── Sort State ───────────────────────────────────────────────────────────
-- Runtime-only (not persisted). Reset to default (nil) on every Hide().
-- Cycle: clicking a column → desc → asc → default → desc → ...
local _sortKey = nil   -- nil = default (lastSeen desc), or a column key
local _sortDir = nil   -- "desc" or "asc" when _sortKey is set

-- Gold column key (forward-declared here so GetSortValue can reference it)
local COL_GOLD_KEY = "_gold"

function ResetSortState()
    _sortKey = nil
    _sortDir = nil
end

-- ── Currency Column Drag-Drop Reordering ────────────────────────────────
-- Runtime drag state (not persisted). The saved column order lives in
-- TFQoLDB.characterViewer.currencyOrder = { "id1", "id2", ... }.
-- Dragging a currency header inserts it before/after the target column
-- (based on which half of the target the cursor is on), shifting the
-- rest. A vertical edge highlight shows the insertion point.
local _draggingCurrencyID = nil
local _dropTargetCurrencyID = nil
local _dropInsertBefore = nil -- true = insert before target, false = after

-- Ensure currencyOrder exists in the DB. Returns the order list.
local function EnsureCurrencyOrder()
    local db = EnsureFiltersDb()
    if not db then return {} end
    if not db.currencyOrder then db.currencyOrder = {} end
    return db.currencyOrder
end

-- Get the display order index for a currency ID. Currencies not in the
-- saved order get appended at the end in their default catalog order.
local function GetCurrencyOrderIndex(currencyID)
    local order = EnsureCurrencyOrder()
    local idStr = tostring(currencyID)
    for i, id in ipairs(order) do
        if id == idStr then return i end
    end
    return math.huge -- not found → end
end

-- Ensure all visible currencies are in the order list, appended in
-- their current display order. This gives every visible currency a
-- finite order index so insert operations position correctly relative
-- to ALL visible columns, not just previously-reordered ones.
local function SyncCurrencyOrder(visibleIds)
    local order = EnsureCurrencyOrder()
    local inList = {}
    for _, id in ipairs(order) do inList[id] = true end
    for _, id in ipairs(visibleIds) do
        local idStr = tostring(id)
        if not inList[idStr] then
            order[#order + 1] = idStr
            inList[idStr] = true
        end
    end
end

-- Remove srcID from the order list and insert it before or after dstID.
-- Call SyncCurrencyOrder first to ensure dstID is in the list.
local function InsertCurrencyOrder(srcID, dstID, beforeDst)
    local order = EnsureCurrencyOrder()
    local strSrc, strDst = tostring(srcID), tostring(dstID)
    -- Remove src from its current position
    for i, id in ipairs(order) do
        if id == strSrc then
            table.remove(order, i)
            break
        end
    end
    -- Find dst's new position (after removal) and insert
    for i, id in ipairs(order) do
        if id == strDst then
            if beforeDst then
                table.insert(order, i, strSrc)
            else
                table.insert(order, i + 1, strSrc)
            end
            return
        end
    end
    -- dst not in list: append src to the end
    order[#order + 1] = strSrc
end

-- Extract a sortable value from a row for a given column key string.
local function GetSortValue(row, key)
    if not row then return 0 end
    if key == "name" then
        return row.name or ""
    elseif key == "ilvl" then
        return row.ilvl or 0
    elseif key == "mplus" then
        return row.mplus or 0
    elseif key == COL_GOLD_KEY then
        return row.gold or 0
    elseif key:match("^currency_") then
        local id = key:sub(10)
        local c = row.currencies and row.currencies[id]
        return c and c.qty or 0
    elseif key == "raid" or key == "mp" or key == "world" then
        local vault = row.vault and row.vault[key]
        if type(vault) ~= "table" then return 0 end
        local count = 0
        for _, s in ipairs(vault) do
            if type(s) == "table" and (s.progress or 0) >= (s.threshold or 0)
                and s.threshold and s.threshold > 0 then
                count = count + 1
            end
        end
        return count
    end
    return 0
end

local function SortRows(rows)
    if not _sortKey then
        -- Default sort: lastSeen descending (current character on top)
        table.sort(rows, function(a, b)
            if (a.lastSeen or 0) ~= (b.lastSeen or 0) then
                return (a.lastSeen or 0) > (b.lastSeen or 0)
            end
            return (a.name or "") < (b.name or "")
        end)
        return
    end
    local desc = _sortDir == "desc"
    table.sort(rows, function(a, b)
        local va = GetSortValue(a, _sortKey)
        local vb = GetSortValue(b, _sortKey)
        if va ~= vb then
            if desc then
                return va > vb
            else
                return va < vb
            end
        end
        return (a.name or "") < (b.name or "")
    end)
end

-- Sort indicator texture (collapse.tga: default = pointing down/v = descending,
-- rotated 180deg = pointing up/^ = ascending)
local SORT_TEX = "Interface\\AddOns\\TF_QoL\\Media\\GUITextures\\collapse.tga"
local SORT_TEX_SIZE = 12

-- Handle a column header click: cycle desc → asc → default.
local function HandleHeaderClick(sortKey)
    if _sortKey == sortKey then
        if _sortDir == "desc" then
            _sortDir = "asc"
        else
            _sortKey = nil
            _sortDir = nil
        end
    else
        _sortKey = sortKey
        _sortDir = "desc"
    end
    if module.UI and module.UI.frame and module.UI.frame:IsShown() then
        module.UI:Render()
    end
end


local function MakeFontString(parent, size, color, justify, text)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    addon:ApplyThemeFont(fs, size)
    if color then
        fs:SetTextColor(color[1], color[2], color[3], color[4] or 1)
    end

    if justify then fs:SetJustifyH(justify) end
    if text then fs:SetText(text) end
    fs:SetWordWrap(false)
    return fs
end


local function PaintRowBg(rowFrame, onHover)
    local Theme = T()
    local c = onHover and Theme.bgHover or Theme.bgDark
    local tex = rowFrame._bgTex
    if not tex then
        tex = rowFrame:CreateTexture(nil, "BACKGROUND")
        -- Inset by borderSize on left/right so the row bg doesn't
        -- paint over the body's border.  Top/bottom get a 1px inset
        -- to keep a thin gap between rows.
        tex:SetPoint("TOPLEFT", rowFrame, "TOPLEFT", Theme.borderSize, -1)

        tex:SetPoint("BOTTOMRIGHT", rowFrame, "BOTTOMRIGHT", -Theme.borderSize, 1)
        rowFrame._bgTex = tex
    end
    tex:SetColorTexture(c[1], c[2], c[3], c[4] or 1)
end

-- Layout for the fixed non-currency columns. Currency columns are
-- appended dynamically by BuildColumnHeader based on the user's
-- visible-currency filter.
local FIXED_COLUMNS  = {
    { key = "ilvl",  label = "Equip",   align = "CENTER", isVault = false },
    { key = "mplus", label = "M+",      align = "CENTER", isVault = false },
    { key = "raid",  label = "Raid",    align = "CENTER", isVault = true, vaultKey = "raid" },
    { key = "mp",    label = "Dungeon", align = "CENTER", isVault = true, vaultKey = "mp" },
    { key = "world", label = "World",   align = "CENTER", isVault = true, vaultKey = "world" },
}
local COL_GOLD_LABEL = "Gold"
local COL_GOLD_ALIGN = "LEFT"

-- RaiderIO M+ profile tooltip (row hover overlay)
-- Flags: MYTHIC_KEYSTONE(16) + PROFILE_TOOLTIP(128) + MOD_STICKY(8) +
-- SHOW_HEADER(1024) + SHOW_PADDING(512) + SHOW_NAME(4096).
local RIO_PROFILE_FLAGS       = 5784
local RIO_TIP_ANCHOR          = "ANCHOR_NONE"
local RIO_TIP_FALLBACK_ANCHOR = "ANCHOR_RIGHT"
local RIO_TIP_EDGE_OFFSET_X   = -1 -- tooltip sits just left of the window edge

-- Build the ordered list of numeric columns to render: fixed ilvl/vault
-- columns, then visible currency columns (sorted by display name), then
-- gold. Returned as a list of { key, label, align, currencyID? }.
-- Also seeds the filter DB on first call: every Midnight currency defaults
-- to hidden (user has to opt-in).
local function BuildNumericColumnList()
    local Theme = T()
    local cols = {}
    for _, c in ipairs(FIXED_COLUMNS) do
        cols[#cols + 1] = c
    end
    -- Currency columns from the live catalog, filtered to the ones the
    -- user has visible. Sorted by display name so the column order is
    -- stable across renders.
    local db = EnsureFiltersDb()
    local visibleFilter = db and db.filters and db.filters.currencies or nil
    local catalog = EnsureCurrencyCatalog()
    local trackedCurrencies = {}
    -- Preserve currency definitions learned on other characters. The live
    -- API may omit a zero-balance currency from the current character.
    if db and db.chars then
        for _, char in pairs(db.chars) do
            for id, currency in pairs(char.currencies or {}) do
                if type(currency) == "table" then
                    trackedCurrencies[id] = currency
                end
            end
        end
    end
    -- First-time init: seed every Midnight currency as hidden so the
    -- main viewer doesn't show all 21 columns by default. Only run
    -- this when we have a real db to write to; otherwise the seed goes
    -- into a throwaway local and the user's check-state never persists.
    if visibleFilter and next(visibleFilter) == nil then
        for id in pairs(catalog) do visibleFilter[tostring(id)] = false end
    end
    -- If we still have no visibleFilter (no db), default to empty so the
    -- loop below produces no columns — better than showing all 21 by accident.
    if not visibleFilter then visibleFilter = {} end
    local cur = {}
    for id, entry in pairs(catalog) do
        if visibleFilter[tostring(id)] ~= false then
            cur[#cur + 1] = {
                key        = "currency_" .. id,
                label      = entry.name,
                align      = "CENTER",
                currencyID = id,
                order      = entry.order,
                icon       = entry.icon,
            }
        end
    end
    table.sort(cur, function(a, b)
        local oa = GetCurrencyOrderIndex(a.currencyID)
        local ob = GetCurrencyOrderIndex(b.currencyID)
        if oa ~= ob then return oa < ob end
        return (a.order or 0) < (b.order or 0)
    end)
    for _, c in ipairs(cur) do cols[#cols + 1] = c end
    -- Gold last: header is just "Gold"; total is shown in footer
    local totalGold = 0
    local cvDb = addon.db and addon.db.characterViewer
    if cvDb and cvDb.chars then
        for _, c in pairs(cvDb.chars) do
            totalGold = totalGold + (c.gold or 0)
        end
    end
    cols[#cols + 1] = { key = COL_GOLD_KEY, label = COL_GOLD_LABEL, align = COL_GOLD_ALIGN }
    return cols, totalGold
end

local function BuildColumnHeader(parent, yOffset, widths, numericCols)
    local Theme = T()
    local headerH = 26
    local row = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    row:SetHeight(headerH)
    row:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -yOffset)
    row:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, -yOffset)
    row:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = Theme.borderSize,
    })
    row:SetBackdropColor(Theme.bgLight[1], Theme.bgLight[2], Theme.bgLight[3], Theme.bgLight[4])
    row:SetBackdropBorderColor(Theme.border[1], Theme.border[2], Theme.border[3], 1)

    -- borderSubtle separator at the bottom of the header (matches card header pattern)
    local sep = row:CreateTexture(nil, "ARTWORK")
    sep:SetHeight(Theme.borderSize)
    sep:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0)
    sep:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0, 0)
    sep:SetColorTexture(Theme.borderSubtle[1], Theme.borderSubtle[2], Theme.borderSubtle[3], 1)

    local cols = {
        { x = COL_LEFT, w = widths.name, align = "LEFT", label = "Character", sortKey = "name" },
    }

    local numX = COL_LEFT + widths.name + COL_GAP
    for i, nc in ipairs(numericCols) do
        local w = widths.numeric[i] or 36
        cols[#cols + 1] = {
            x = numX,
            w = w,
            align = nc.align,
            label = nc.label,
            currencyID = nc.currencyID,
            icon = nc.icon,
            sortKey = nc.key,
        }
        numX = numX + w + COL_GAP
    end

    -- Highlight the active sort column's header area
    local sortCol
    for _, c in ipairs(cols) do
        if _sortKey == c.sortKey and _sortDir then sortCol = c break end
    end
    if sortCol then
        local hl = row:CreateTexture(nil, "BACKGROUND")
        hl:SetPoint("TOPLEFT", row, "TOPLEFT", sortCol.x, 0)
        hl:SetPoint("BOTTOMRIGHT", row, "BOTTOMLEFT", sortCol.x + sortCol.w, 0)
        hl:SetColorTexture(Theme.bgHover[1], Theme.bgHover[2], Theme.bgHover[3], 0.5)
    end

    -- Helper: create a sort indicator texture next to an anchor element
    local function AddSortIndicator(parent, anchor, side)
        local ind = parent:CreateTexture(nil, "OVERLAY")
        ind:SetTexture(SORT_TEX)
        ind:SetSize(SORT_TEX_SIZE, SORT_TEX_SIZE)
        ind:SetVertexColor(Theme.accent[1], Theme.accent[2], Theme.accent[3], 1)
        ind:SetRotation(_sortDir == "asc" and math.pi or 0)
        if side == "LEFT" then
            ind:SetPoint("RIGHT", anchor, "LEFT", -2, 0)
        else
            ind:SetPoint("LEFT", anchor, "RIGHT", 2, 0)
        end
        return ind
    end

    -- Shared edge-highlight texture for drag-drop insertion point.
    -- A 2px vertical accent bar shown at the left or right edge of the
    -- target currency button, indicating where the dragged column will
    -- be inserted.
    local dropEdge = row:CreateTexture(nil, "OVERLAY")
    dropEdge:SetSize(2, headerH)
    dropEdge:SetColorTexture(Theme.accent[1], Theme.accent[2], Theme.accent[3], 1)
    dropEdge:Hide()

    -- Track currency buttons for OnUpdate hit-testing during drag
    local currencyBtns = {}

    for _, col in ipairs(cols) do
        local isActive = _sortKey == col.sortKey and _sortDir
        local labelColor = isActive and Theme.textPrimary or Theme.secondaryAccent

        if col.currencyID and col.icon then
            -- Currency column: Button for hover tooltip + click-to-sort +
            -- drag-to-reorder. On drag stop, the column is inserted before
            -- or after the target (based on cursor position at release).

            local btn = CreateFrame("Button", nil, row)
            btn:SetSize(col.w, headerH)
            btn:SetPoint("CENTER", row, "LEFT", col.x + col.w / 2, 0)
            btn:SetFrameLevel(row:GetFrameLevel() + 5)
            -- Give currency icons a small black keyline and crop 6% total
            -- (3% from each edge) so the art reads slightly larger.
            local iconFrame = CreateFrame("Frame", nil, btn, "BackdropTemplate")
            iconFrame:SetSize(20, 20)
            iconFrame:SetPoint("CENTER", btn, "CENTER", 0, 0)
            iconFrame:SetBackdrop({
                edgeFile = "Interface\\Buttons\\WHITE8X8",
                edgeSize = 1,
            })
            iconFrame:SetBackdropBorderColor(0, 0, 0, 1)
            local icon = iconFrame:CreateTexture(nil, "ARTWORK")
            icon:SetTexture(col.icon)
            icon:SetTexCoord(0.03, 0.97, 0.03, 0.97)
            icon:SetSize(18, 18)
            icon:SetPoint("CENTER", iconFrame, "CENTER", 0, 0)
            -- Sort indicator texture next to icon
            if isActive then
                AddSortIndicator(btn, icon, "RIGHT")
            end
            btn.currencyID = col.currencyID
            btn:SetScript("OnEnter", function(self)
                if not _draggingCurrencyID then
                    GameTooltip:SetOwner(self, "ANCHOR_TOP")
                    GameTooltip:SetCurrencyByID(self.currencyID)
                    GameTooltip:Show()
                end
            end)
            btn:SetScript("OnLeave", function()
                GameTooltip:Hide()
            end)
            btn:SetScript("OnClick", function()
                if IsLockedDown() then return end
                HandleHeaderClick(col.sortKey)
            end)
            -- Drag-to-reorder: register for left-button drag
            btn:RegisterForDrag("LeftButton")
            btn:SetScript("OnDragStart", function(self)
                if IsLockedDown() then return end
                _draggingCurrencyID = col.currencyID
                GameTooltip:Hide()
            end)
            btn:SetScript("OnDragStop", function(self)
                if IsLockedDown() then return end
                local srcID = _draggingCurrencyID
                local dstID = _dropTargetCurrencyID
                local before = _dropInsertBefore
                _draggingCurrencyID = nil
                _dropTargetCurrencyID = nil
                _dropInsertBefore = nil
                dropEdge:Hide()
                if srcID and dstID and srcID ~= dstID then
                    -- Sync all visible currencies into the order list
                    -- so every column has a finite index. Without this,
                    -- columns never manually reordered have math.huge
                    -- and the insert lands in the wrong position.
                    local visibleIds = {}
                    for _, cb in ipairs(currencyBtns) do
                        visibleIds[#visibleIds + 1] = cb.currencyID
                    end
                    SyncCurrencyOrder(visibleIds)
                    InsertCurrencyOrder(srcID, dstID, before)
                    module.UI:Render()
                end
            end)
            currencyBtns[#currencyBtns + 1] = btn
        else
            -- Non-currency column: text label (auto-width so indicator hugs text)

            -- Anchor point varies by alignment so text centers correctly
            local lbl = MakeFontString(row, "normal", labelColor, col.align, col.label)
            if col.align == "RIGHT" then
                lbl:SetPoint("RIGHT", row, "LEFT", col.x + col.w, 0)
            elseif col.align == "CENTER" then
                lbl:SetPoint("CENTER", row, "LEFT", col.x + col.w / 2, 0)
            else
                lbl:SetPoint("LEFT", row, "LEFT", col.x, 0)
            end
            -- Sort indicator texture beside text
            if isActive then
                local side = (col.align == "RIGHT") and "LEFT" or "RIGHT"
                AddSortIndicator(row, lbl, side)
            end
            -- Click-to-sort: Button overlay (FontStrings don't receive OnClick)
            local sortBtn = CreateFrame("Button", nil, row)
            sortBtn:SetPoint("TOPLEFT", row, "TOPLEFT", col.x, 0)
            sortBtn:SetSize(col.w, headerH)
            sortBtn:SetFrameLevel(row:GetFrameLevel() + 5)
            sortBtn:SetScript("OnClick", function()
                if IsLockedDown() then return end
                HandleHeaderClick(col.sortKey)
            end)
        end
    end

    -- OnUpdate: while dragging a currency column, hit-test all currency
    -- header buttons to find the drop target and which half of the button
    -- the cursor is on. Shows the edge highlight at the insertion point.
    -- When the cursor exits the currency column area entirely, snap to
    -- the nearest edge (before first or after last) so the user can
    -- always drop.
    row:SetScript("OnUpdate", function()
        -- Idle fast path: a single local nil-check per frame. Lockdown
        -- and cursor hit-testing below run only while a drag is active.
        if not _draggingCurrencyID then
            if dropEdge:IsShown() then dropEdge:Hide() end
            return
        end
        if IsLockedDown() then return end
        if #currencyBtns == 0 then return end
        -- GetCursorPosition() returns raw screen pixels; frame GetLeft()/
        -- GetRight()/GetCenter() return coordinates scaled by the frame's
        -- effective scale (UIParent scale × window scale). Divide by the
        -- button's effective scale to convert cursor to the same space.
        local scale = currencyBtns[1]:GetEffectiveScale()
        local cursorX = GetCursorPosition() / scale
        local firstBtn = currencyBtns[1]
        local lastBtn = currencyBtns[#currencyBtns]
        local leftEdge = firstBtn:GetLeft()
        local rightEdge = lastBtn:GetRight()
        if not leftEdge or not rightEdge then return end

        -- Cursor left of all currency columns → insert before first
        if cursorX < leftEdge then
            if firstBtn.currencyID ~= _draggingCurrencyID then
                _dropTargetCurrencyID = firstBtn.currencyID
                _dropInsertBefore = true
                dropEdge:ClearAllPoints()
                dropEdge:SetPoint("CENTER", firstBtn, "LEFT", 0, 0)
                dropEdge:Show()
            else
                _dropTargetCurrencyID = nil
                _dropInsertBefore = nil
                dropEdge:Hide()
            end
            return
        end

        -- Cursor right of all currency columns → insert after last
        if cursorX > rightEdge then
            if lastBtn.currencyID ~= _draggingCurrencyID then
                _dropTargetCurrencyID = lastBtn.currencyID
                _dropInsertBefore = false
                dropEdge:ClearAllPoints()
                dropEdge:SetPoint("CENTER", lastBtn, "RIGHT", 0, 0)
                dropEdge:Show()
            else
                _dropTargetCurrencyID = nil
                _dropInsertBefore = nil
                dropEdge:Hide()
            end
            return
        end

        -- Cursor within currency column area: find which button it's over
        for _, cb in ipairs(currencyBtns) do
            if cb:IsMouseOver() then
                if cb.currencyID ~= _draggingCurrencyID then
                    local cx = cb:GetCenter()
                    local insertBefore = cursorX < cx
                    _dropTargetCurrencyID = cb.currencyID
                    _dropInsertBefore = insertBefore
                    dropEdge:ClearAllPoints()
                    if insertBefore then
                        dropEdge:SetPoint("CENTER", cb, "LEFT", 0, 0)
                    else
                        dropEdge:SetPoint("CENTER", cb, "RIGHT", 0, 0)
                    end
                    dropEdge:Show()
                else
                    -- Over the source column itself: no drop target
                    _dropTargetCurrencyID = nil
                    _dropInsertBefore = nil
                    dropEdge:Hide()
                end
                return
            end
        end
    end)

    return row, headerH
end

-- Measure the widest text string that will appear in each column. Font
-- must already be applied (MakeFontString does this) for GetStringWidth
-- to be accurate.
local function MeasureString(fs, text)
    fs:SetText(text or "")
    return fs:GetStringWidth() or 0
end

-- Cap-progress color for a currency quantity cell: the closer-to-cap of
-- the weekly and seasonal progress. Shared by the full row builder and
-- the fast-path in-place refresh in Render.
local function CurrencyQtyColor(c, Theme)
    local qty            = c and c.qty or 0
    local weekQty        = c and c.weekQty or 0
    local weekMax        = c and c.weekMax or 0
    local canWeekly      = c and c.canWeekly or false
    local maxQty         = c and c.max or 0
    local totalEarned    = c and c.totalEarned or 0
    local useTotalEarned = c and c.useTotalEarned or false
    local weekPct = 0
    if canWeekly and weekMax > 0 then
        weekPct = (weekQty / weekMax) * 100
    end
    local capPct = 0
    if maxQty > 0 then
        if useTotalEarned then
            capPct = (totalEarned / maxQty) * 100
        else
            capPct = (qty / maxQty) * 100
        end
    end
    local percent = weekPct
    if capPct > percent then percent = capPct end
    --   >= 100  → currencyCap red (reached, even if partially spent)
    --   >= 50   → yellow (near cap)
    --   qty 0 and percent 0 → grey (none)
    --   otherwise → white
    if percent >= 100 then
        return Theme.currencyCap
    elseif percent >= 50 then
        return Theme.yellow
    elseif qty == 0 and percent == 0 then
        return Theme.textMuted
    end
    return Theme.textPrimary
end

local function BuildCharRow(parent, yOffset, rowData, widths, numericCols)
    local Theme = T()
    local rowH = 26
    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(rowH)
    row:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -yOffset)
    row:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, -yOffset)
    row:EnableMouse(true)
    row.rowData = rowData
    PaintRowBg(row, false)

    local sep = row:CreateTexture(nil, "ARTWORK")
    sep:SetHeight(1)
    sep:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0)
    sep:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0, 0)
    sep:SetColorTexture(Theme.borderSubtle[1], Theme.borderSubtle[2], Theme.borderSubtle[3], 0.5)

    -- Name cell: one line, "Name - Realm · 1m ago" with class color.
    -- Realm and time are appended as smaller, muted text on the same line.
    local cc = (rowData.class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[rowData.class])
        or Theme.textPrimary

    local labelText = BuildNameLabelText(rowData)

    local name = MakeFontString(row, "normal",
        { cc.r, cc.g, cc.b, 1 }, "LEFT", labelText)
    name:SetPoint("LEFT", row, "LEFT", 8, 0)
    name:SetWidth(widths.name)
    row.nameText = name

    -- Render each numeric column from the same column list used by the
    -- header so the row's cells line up under the right labels.
    local numX = COL_LEFT + widths.name + COL_GAP
    for i, nc in ipairs(numericCols) do
        local cell
        local w = widths.numeric[i] or 36
        if nc.key == "ilvl" then
            if rowData.ilvl and rowData.ilvl > 0 then
                local hex = addon:IlvlTierHex(rowData.ilvl) or "ffffff"
                cell = MakeFontString(row, "normal", Theme.textPrimary, "CENTER",
                    "|cff" .. hex .. tostring(rowData.ilvl) .. "|r")
            else
                cell = MakeFontString(row, "normal", Theme.textPrimary, "CENTER", "—")
            end
        elseif nc.key == "mplus" then
            local score = rowData.mplus or 0
            cell = MakeFontString(row, "normal", GetMythicPlusScoreColor(score), "CENTER",
                score > 0 and tostring(score) or "—")
        elseif nc.isVault and nc.vaultKey then
            local vault = rowData.vault
            local slots = vault and vault[nc.vaultKey]
            -- "Choose!" when vault has unclaimed rewards
            if vault and vault.availableRewards then
                cell = MakeFontString(row, "normal",
                    { Theme.yellow[1], Theme.yellow[2], Theme.yellow[3], 1 },
                    "CENTER", "Choose!")
            else
                local parts = {}
                local prevIncomplete = false
                if slots and type(slots) == "table" then
                    for _, s in ipairs(slots) do
                        if type(s) == "table" and (s.progress or 0) >= (s.threshold or 0)
                            and s.threshold and s.threshold > 0 then
                            -- Completed: ilvl colored by item quality
                            local hex = s.qColor or "ffffff"
                            parts[#parts + 1] = "|cff" .. hex
                                .. tostring(s.ilvl or "?") .. "|r"
                            prevIncomplete = false
                        elseif type(s) == "table" and s.threshold then
                            -- Incomplete: remaining + "!"
                            local remaining = s.threshold - (s.progress or 0)
                            if prevIncomplete then
                                -- Dim later incomplete slots (Wowthing .ugh)
                                parts[#parts + 1] = "|cffaaaaaa"
                                    .. remaining .. "!|r"
                            else
                                parts[#parts + 1] = remaining .. "!"
                            end
                            prevIncomplete = true
                        end
                    end
                end
                local txt = #parts > 0 and table_concat(parts, " ") or "—"
                cell = MakeFontString(row, "normal",
                    Theme.textMuted, "CENTER", txt)
            end
            -- Invisible Button overlay so OnClick fires (FontStrings
            -- inherit ScriptRegion's OnEnter/OnLeave but NOT OnClick or
            -- RegisterForClicks — those are Button-only). Click toggles
            -- the Great Vault via the same pattern EllesmereUIMinimap
            -- uses in its CreateGreatVaultBtn / ToggleGreatVault.
            local btn = CreateFrame("Button", nil, row)
            btn:SetPoint("CENTER", row, "LEFT", numX + w / 2, 0)
            btn:SetSize(w, rowH)
            btn:SetFrameLevel(row:GetFrameLevel() + 5)
            btn:EnableMouse(true)
            btn:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_TOP")
                GameTooltip:AddLine(
                    "|A:newplayertutorial-icon-mouse-leftbutton:16:16|a Open Great Vault",
                    0.651, 0.678, 0.784)
                GameTooltip:Show()
            end)
            btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
            btn:SetScript("OnClick", function()
                if InCombatLockdown() then return end
                local IsLoaded = (C_AddOns and C_AddOns.IsAddOnLoaded) or _G.IsAddOnLoaded
                local Load     = (C_AddOns and C_AddOns.LoadAddOn)     or _G.LoadAddOn
                if Load and IsLoaded and not IsLoaded("Blizzard_WeeklyRewards") then
                    Load("Blizzard_WeeklyRewards")
                end
                if _G.WeeklyRewardsFrame then
                    _G.WeeklyRewardsFrame:Show()
                end
                if module.UI then module.UI:Hide() end
            end)
        elseif nc.currencyID then
            local c = rowData.currencies and rowData.currencies[tostring(nc.currencyID)]
            local qty           = c and c.qty or 0
            local weekQty       = c and c.weekQty or 0
            local weekMax       = c and c.weekMax or 0
            local canWeekly     = c and c.canWeekly or false
            local maxQty        = c and c.max or 0
            local totalEarned   = c and c.totalEarned or 0
            local useTotalEarned= c and c.useTotalEarned or false
            -- Cap-progress percent across weekly and seasonal caps; take
            -- the closer-to-cap of the two. Red when EITHER is reached
            -- (≥100%), even after the character has spent some of the
            -- currency: for seasonal currencies (useTotalEarnedForMaxQty),
            -- totalEarned counts earned + spent, so a 22/22 season cap
            -- still shows red when the player holds only 18.
            --   >= 100  → currencyCap red
            --   >= 50   → yellow (near cap)
            --   qty 0 and percent 0 → grey (none)
            --   otherwise → white
            local color = CurrencyQtyColor(c, Theme)
            cell = MakeFontString(row, "normal",
                { color[1], color[2], color[3], 1 }, "CENTER", tostring(qty))
            -- Invisible Frame overlay so ANCHOR_TOP matches the vault
            -- button's height (26px). FontString alone is only ~14px tall
            -- and centered, so its top edge sits lower than the button's.
            -- Tooltip shows per-character values (not live player data):
            --   seasonal cap → "earned/max Name" (e.g. 22/22 Nebulous Voidcore)
            --   weekly cap   → "earned/max Name" (e.g. 8/10 Name)
            --   no cap       → "qty Name"        (e.g. 155 Hero Dawncrest)
            local tipText
            if useTotalEarned and maxQty > 0 then
                tipText = totalEarned .. "/" .. maxQty .. " " .. nc.label
            elseif canWeekly and weekMax > 0 then
                tipText = weekQty .. "/" .. weekMax .. " " .. nc.label
            else
                tipText = qty .. " " .. nc.label
            end
            local hit = CreateFrame("Frame", nil, row)
            hit:SetPoint("CENTER", row, "LEFT", numX + w / 2, 0)
            hit:SetSize(w, rowH)
            hit:EnableMouse(true)
            hit:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_TOP")
                GameTooltip:ClearLines()
                GameTooltip:AddLine(tipText,
                    Theme.textPrimary[1], Theme.textPrimary[2], Theme.textPrimary[3])
                GameTooltip:Show()
            end)
            hit:SetScript("OnLeave", function() GameTooltip:Hide() end)
        elseif nc.key == COL_GOLD_KEY then
            cell = MakeFontString(row, "normal",
                { Theme.yellow[1], Theme.yellow[2], Theme.yellow[3], 1 }, "LEFT",
                BreakUpLargeNumbers(rowData.gold or 0) .. GOLD_ICON)
        end
        if cell then
            local colX = numX + w / 2
            cell:SetPoint("CENTER", row, "LEFT", colX, 0)
            cell:SetWidth(w)
            row[nc.key] = cell
        end
        numX = numX + w + COL_GAP
    end

    -- RaiderIO M+ tooltip overlay: invisible Button covering the first
    -- 3 columns (name + Equip + M+). On hover, renders RaiderIO's extended
    -- M+ profile (per-dungeon key levels + scores with RaiderIO coloring)
    -- via RaiderIO.ShowProfile. Falls back to a plain score tooltip when
    -- RaiderIO is not installed or the character isn't in its database.
    -- Tooltip anchors to the window's left edge, vertically centered on
    -- the hovered row.
    if (rowData.mplus or 0) > 0 and row.mplus then
        local win = _G[WINDOW_NAME] or parent:GetParent()
        local btn = CreateFrame("Button", nil, row)
        btn:SetPoint("LEFT", row, "LEFT", 0, 0)
        btn:SetPoint("RIGHT", row.mplus, "RIGHT", 0, 0)
        btn:SetHeight(rowH)
        btn:SetFrameLevel(row:GetFrameLevel() + 5)
        btn:EnableMouse(true)
        btn:SetScript("OnEnter", function(self)
            PaintRowBg(row, true)
            local score = rowData.mplus or 0
            local RIO = _G.RaiderIO
            -- Position helper: anchor tooltip to the window's left edge,
            -- vertically centered on the hovered row.
            local function AnchorTip()
                if not win then return false end
                local _, rowCY = row:GetCenter()
                local _, winCY = win:GetCenter()
                if rowCY and winCY then
                    GameTooltip:ClearAllPoints()
                    GameTooltip:SetPoint("RIGHT", win, "LEFT", RIO_TIP_EDGE_OFFSET_X, rowCY - winCY)
                    return true
                end
                return false
            end
            if RIO and RIO.ShowProfile and rowData.name and rowData.realm then
                -- Renders the extended M+ profile (per-dungeon runs)
                -- without raid progress or footer. Flag breakdown lives
                -- on RIO_PROFILE_FLAGS above.
                -- Realm names in RaiderIO's DB are stored without spaces
                -- (e.g. "Area52"), so normalize.
                local realm = rowData.realm:gsub("%s", "")
                GameTooltip:SetOwner(self, RIO_TIP_ANCHOR)
                GameTooltip:ClearLines()
                local ok, success = pcall(RIO.ShowProfile, GameTooltip,
                    rowData.name, realm, RIO_PROFILE_FLAGS)
                if ok and success then
                    AnchorTip()
                    return
                end
                GameTooltip:Hide()
            end
            -- Fallback: plain score tooltip (RaiderIO not installed or
            -- character not found in its database)
            GameTooltip:SetOwner(self, RIO_TIP_ANCHOR)
            GameTooltip:ClearLines()
            GameTooltip:AddLine("Mythic+ Score", 1, 0.85, 0)
            local sc = GetMythicPlusScoreColor(score)
            GameTooltip:AddDoubleLine("Score", tostring(score),
                1, 1, 1, sc[1], sc[2], sc[3])
            if not AnchorTip() then
                GameTooltip:SetOwner(self, RIO_TIP_FALLBACK_ANCHOR)
            end
            GameTooltip:Show()
        end)
        btn:SetScript("OnLeave", function()
            PaintRowBg(row, false)
            GameTooltip:Hide()
        end)
    end

    -- Hover handlers
    row:SetScript("OnEnter", function(self) PaintRowBg(self, true) end)
    row:SetScript("OnLeave", function(self)
        if IsLockedDown() then return end
        PaintRowBg(self, false)
    end)

    return row, rowH
end

local function BuildEmptyState(parent, yOffset, msg)
    local Theme = T()
    local lbl = MakeFontString(parent, "normal", Theme.textMuted, "CENTER", msg)
    lbl:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -yOffset)
    lbl:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, -yOffset)
    lbl:SetHeight(40)
    return lbl, 40
end

-- Build the same kind of label string a character row would produce
-- (Name - Realm · time-ago) for a representative max-width estimate.
-- Realm is the longest realistic realm name; time-ago is the longest
-- timestamp we ever produce ("99d ago" / "99mo ago" / "just now" /
-- "never" — "just now" at fontSizeNormal is the longest by ~6px).
local function PreviewNameText(rowData)
    -- Cheap: reuse the exact styled string the rows render.
    return BuildNameLabelText(rowData)
end

-- Pre-render measurement: walk the column list and the character rows
-- once with throwaway FontStrings, and return:
--   { name = widest name column width,
--     numeric = { col1=, col2=, ... } widest per column,
--     total = sum of name + numerics + gaps for the window resize }
-- Used so the header and rows can be laid out at the right size on
-- the *first* paint, with no flash of misaligned columns.
local function MeasureColumnWidths(rows, numericCols)
    local Theme = T()
    -- Throwaway parent — not attached to anything visible. The fs is
    -- created on UIParent so font objects work; hidden.
    local hidden = GetProbeFrame()

    local function probe(sizeKey, color)
        local fs = hidden:CreateFontString(nil, "OVERLAY")
        addon:ApplyThemeFont(fs, sizeKey)
        if color then
            fs:SetTextColor(color[1], color[2], color[3], color[4] or 1)
        end
        fs:SetWordWrap(false)
        return fs
    end

    local nameFs   = probe("normal", Theme.textPrimary)
    local headerFs = probe("small", Theme.textMuted)

    -- Name column: longest styled name + realm + timestamp preview.
    local maxName  = MeasureString(headerFs, "Character")
    for _, r in ipairs(rows) do
        local w = MeasureString(nameFs, PreviewNameText(r))
        if w > maxName then maxName = w end
    end

    -- Numeric columns: widest header OR data sample, **per column**.
    -- The old code returned a single number and applied it to every
    -- column, which made "Brimming Arcana" / "1/3" the same width.
    local maxNum = {} -- 1-based: maxNum[i] = widest sample for column i
    for i = 1, #numericCols do maxNum[i] = 0 end
    -- Headers (small font):
    --   Text headers (Equip, Raid, Dungeon, World, Gold): measure the label.
    --   Icon headers (currencies): use 20px (18px icon + 4px padding) as min.
    for i, nc in ipairs(numericCols) do
        if nc.currencyID and nc.icon then
            if maxNum[i] < 20 then maxNum[i] = 20 end
        else
            local w = MeasureString(headerFs, nc.label)
            if w > maxNum[i] then maxNum[i] = w end
        end
    end
    -- Data samples (normal font, body color)

    for _, r in ipairs(rows) do
        for i, nc in ipairs(numericCols) do
            local sample
            if nc.key == "ilvl" then
                sample = r.ilvl and r.ilvl > 0 and tostring(r.ilvl) or "—"
            elseif nc.key == "mplus" then
                sample = r.mplus and r.mplus > 0 and tostring(r.mplus) or "—"
            elseif nc.isVault and nc.vaultKey then
                local slots = r.vault and r.vault[nc.vaultKey]
                local parts = {}
                if slots and type(slots) == "table" then
                    for _, s in ipairs(slots) do
                        if type(s) == "table" and (s.progress or 0) >= (s.threshold or 0) and s.threshold and s.threshold > 0 then
                            parts[#parts + 1] = s.ilvl and tostring(s.ilvl) or "?"
                        elseif type(s) == "table" and s.threshold then
                            parts[#parts + 1] = (s.threshold - (s.progress or 0)) .. "!"
                        end
                    end
                end
                sample = #parts > 0 and table_concat(parts, " ") or "—"
            elseif nc.currencyID then
                local c = r.currencies and r.currencies[tostring(nc.currencyID)]

                sample = tostring(c and c.qty or 0)
            elseif nc.key == COL_GOLD_KEY then
                sample = BreakUpLargeNumbers(r.gold or 0) .. GOLD_ICON
            end
            local w = MeasureString(nameFs, sample or "")

            if w > maxNum[i] then maxNum[i] = w end
        end
    end

    -- Round up + add horizontal padding, with a sane minimum per column
    -- so single-digit numbers don't collapse the column to nothing.
    local numeric = {}
    local total = math.max(math.ceil(maxName) + COL_PAD_X, 80)
    for i, nc in ipairs(numericCols) do
        local minW = (nc.isVault and nc.vaultKey) and 90 or 32
        numeric[i] = math.max(math.ceil(maxNum[i]) + COL_PAD_X, minW)
        total = total + numeric[i] + COL_GAP

    end
    total = total - COL_GAP -- no trailing gap after the last column

    return {
        name    = math.max(math.ceil(maxName) + COL_PAD_X, 80),
        numeric = numeric,
        total   = total,
    }
end

-- Set the window's width to fit all visible columns. Height is content-
-- driven from `bodyHeight` (computed in Render). Anchored to its
-- current screen position; only size changes, position is preserved.
-- Short-circuits when both dimensions are within 1px of the cached
-- values to avoid re-setting the same size on every render.
--
-- Right padding: the last column (currently gold, LEFT-anchored text)
-- sits flush against the right edge of the body if we size exactly to
-- `widths.total`. We add `COL_LEFT` more so the gold value has the
-- same left-side padding as the character name on the left.
local function FitWindowToContent(bodyHeight, totalTableWidth)
    if not module.UI or not module.UI.frame then return end
    local frame = module.UI.frame
    local desiredW = math.max(WINDOW_W_MIN, math.ceil(totalTableWidth) + COL_LEFT * 3)
    local desiredH = math.max(WINDOW_H, math.ceil(bodyHeight) + HEADER_H + FOOTER_H)
    if frame._lastW and math.abs(frame._lastW - desiredW) < 1
        and frame._lastH and math.abs(frame._lastH - desiredH) < 1 then
        return
    end
    frame:SetSize(desiredW, desiredH)
    frame._lastW = desiredW
    frame._lastH = desiredH
end

-- ── Render Recycling ─────────────────────────────────────────────────
-- A full Render destroys and recreates every row frame; PLAYER_MONEY and
-- CURRENCY_DISPLAY_UPDATE fire often but only change gold/currency
-- values. When the row set/order, column set/order, measured widths,
-- sort state, and all other values match the last full build, the
-- high-churn cells (gold, currency qty/color, name timestamps, footer
-- total) are refreshed in place instead.
local function VaultFingerprint(vault)
    if type(vault) ~= "table" then return "-" end
    local parts = { vault.availableRewards and "1" or "0" }
    for _, key in ipairs({ "raid", "mp", "world" }) do
        local slots = vault[key]
        if type(slots) == "table" then
            for _, s in ipairs(slots) do
                if type(s) == "table" then
                    parts[#parts + 1] = (s.progress or 0) .. "/" .. (s.threshold or 0)
                        .. "/" .. (s.ilvl or 0) .. "/" .. (s.qColor or "")
                else
                    parts[#parts + 1] = "-"
                end
            end
        else
            parts[#parts + 1] = "x"
        end
    end
    return table_concat(parts, ",")
end

-- Values the fast path does not rebuild (class/ilvl/score/vault need new
-- colors or widths when they change). Gold, currencies, and lastSeen are
-- excluded: UpdateGold bumps lastSeen on every PLAYER_MONEY, and the fast
-- path refreshes name timestamps alongside the gold/currency texts.
local function StaticValuesSig(rows)
    local parts = {}
    for _, r in ipairs(rows) do
        parts[#parts + 1] = (r.name or "?") .. "|" .. (r.realm or "") .. "|"
            .. (r.class or "") .. "|" .. (r.ilvl or 0) .. "|" .. (r.mplus or 0)
            .. "|" .. VaultFingerprint(r.vault)
    end
    return table_concat(parts, "\n")
end

local function StructureSig(rows, numericCols, widths)
    local parts = {}
    for _, r in ipairs(rows) do parts[#parts + 1] = r.guid or "?" end
    parts[#parts + 1] = "#"
    for _, nc in ipairs(numericCols) do parts[#parts + 1] = nc.key end
    parts[#parts + 1] = "#"
    parts[#parts + 1] = widths.name .. "/" .. widths.total
    for _, w in ipairs(widths.numeric) do parts[#parts + 1] = tostring(w) end
    parts[#parts + 1] = "#"
    parts[#parts + 1] = (_sortKey or "-") .. (_sortDir or "-")
    return table_concat(parts, ",")
end

-- In-place refresh of the high-churn value cells. Returns false if any
-- expected frame is missing (caller falls back to a full rebuild).
local function RefreshValueCells(self, rows, numericCols, totalGold)
    local Theme = T()
    local frames = self._rowFrames
    if type(frames) ~= "table" then return false end
    for _, rowData in ipairs(rows) do
        local frame = frames[rowData.guid]
        if not frame then return false end
        if frame.nameText then
            frame.nameText:SetText(BuildNameLabelText(rowData))
        end
        for _, nc in ipairs(numericCols) do
            if nc.key == COL_GOLD_KEY then
                local cell = frame[nc.key]
                if not cell then return false end
                cell:SetText(BreakUpLargeNumbers(rowData.gold or 0) .. GOLD_ICON)
            elseif nc.currencyID then
                local cell = frame[nc.key]
                if not cell then return false end
                local c = rowData.currencies and rowData.currencies[tostring(nc.currencyID)]
                local qty = c and c.qty or 0
                cell:SetText(tostring(qty))
                local color = CurrencyQtyColor(c, Theme)
                cell:SetTextColor(color[1], color[2], color[3], 1)
            end
        end
    end
    local warbankGold = (addon.db and addon.db.characterViewer and addon.db.characterViewer.warbankGold) or 0
    if self.footer and self.footer.totalGoldLabel then
        self.footer.totalGoldLabel:SetText(BreakUpLargeNumbers(totalGold + warbankGold) .. GOLD_ICON)
    end
    return true
end

function module.UI:Render()
    if IsLockedDown() then return end
    if not self.frame then self:Build() end
    local Theme = T()
    local body = self.body
    if not body then return end

    local db = addon.db and addon.db.characterViewer
    local chars = (db and db.chars) or {}
    local rows = {}
    for guid, row in pairs(chars) do
        if type(row) == "table" then
            row.guid = guid
            -- Apply char filter
            if not db.filters or not db.filters.chars or db.filters.chars[guid] ~= false then
                rows[#rows + 1] = row
            end
        end
    end

    local yOffset = 0
    -- Pre-measure with the actual row data so the header and rows line
    -- up on the first paint, then lay everything out.
    local numericCols, totalGold = BuildNumericColumnList()
    local widths = MeasureColumnWidths(rows, numericCols)
    SortRows(rows)

    -- Fast path: rows, columns, widths, and static values all match the
    -- last full build — refresh only the high-churn value cells in place.
    if self._rowFrames
        and StructureSig(rows, numericCols, widths) == self._structSig
        and StaticValuesSig(rows) == self._staticSig
        and RefreshValueCells(self, rows, numericCols, totalGold) then
        return
    end

    -- Clear existing children
    for _, child in ipairs({ body:GetChildren() }) do
        child:Hide()
        child:SetParent(nil)
    end
    self._rowFrames = {}

    local _, headerH = BuildColumnHeader(body, yOffset, widths, numericCols)
    yOffset = yOffset + headerH + 4

    if #rows == 0 then
        local _, eh = BuildEmptyState(body, yOffset,
            "No character data yet. Log in on a character with Character Viewer enabled.")
        yOffset = yOffset + eh
    else
        for _, rowData in ipairs(rows) do
            local rowFrame, rh = BuildCharRow(body, yOffset, rowData, widths, numericCols)
            self._rowFrames[rowData.guid] = rowFrame
            yOffset = yOffset + rh + 2
        end
    end

    body:SetHeight(yOffset + 8)
    FitWindowToContent(yOffset + 8, widths.total)

    -- Total gold in the bottom-right corner of the footer (characters + warbank)
    local warbankGold = (addon.db and addon.db.characterViewer and addon.db.characterViewer.warbankGold) or 0
    local displayGold = totalGold + warbankGold
    if self.footer and self.footer.totalGoldLabel then
        self.footer.totalGoldLabel:SetText(BreakUpLargeNumbers(displayGold) .. GOLD_ICON)
    end
    self._structSig = StructureSig(rows, numericCols, widths)
    self._staticSig = StaticValuesSig(rows)
end

-- ════════════════════════════════════════════════════════════════════════════════
-- Part 6: Show / Hide / Toggle
-- ════════════════════════════════════════════════════════════════════════════════

function module.UI:Show()
    if IsLockedDown() then return end
    if not self.frame then self:Build() end
    self:Render()
    self.frame:Show()
    EnsureJournalatorArchiveLoaded()
end

function module.UI:SetScale(scale)
    if IsLockedDown() then return end
    local db = addon.db and addon.db.characterViewer
    scale = math.max(SCALE_MIN, math.min(SCALE_MAX, tonumber(scale) or 1.0))
    if db then db.scale = scale end
    if self.frame then self.frame:SetScale(scale) end
end

function module.UI:Hide()
    if self.filtersPopover then self.filtersPopover:Hide() end
    if self.frame then self.frame:Hide() end
    ResetSortState()
end

function module.UI:Toggle()
    if IsLockedDown() then return end
    if not self.frame then
        self:Show()
    elseif self.frame:IsShown() then
        self:Hide()
    else
        self:Show()
    end
end

-- ════════════════════════════════════════════════════════════════════════════════
-- Part 7: Module Lifecycle
-- ════════════════════════════════════════════════════════════════════════════════

function module:Toggle() self.UI:Toggle() end

function module:Show() self.UI:Show() end

function module:Hide() self.UI:Hide() end

local function RefreshAfterChange()
    if IsLockedDown() then return end
    -- Cheap re-render if the window is open (PLAYER_MONEY etc.)
    if module.UI and module.UI.frame and module.UI.frame:IsShown() then
        module.UI:Render()
    end
end

function module:OnInitialize()
    if IsLockedDown() then return end
    holder = CreateFrame("Frame")
    holder:SetScript("OnEvent", function(_, event, arg1)
        if event == "PLAYER_REGEN_DISABLED" then
            -- Hide existing UI immediately; do not call the normal Hide path,
            -- which also resets persistent sort state.
            if module.UI.filtersPopover then module.UI.filtersPopover:Hide() end
            if module.UI.frame then module.UI.frame:Hide() end
            return
        end
        if event == "PLAYER_REGEN_ENABLED" then
            -- Retry an OnEnable that was deferred by combat lockdown.
            if _pendingEnable then module:OnEnable() end
            return
        end
        if IsLockedDown() then return end
        if event == "PLAYER_LOGIN" then
            SnapshotCurrent(true)

        elseif event == "PLAYER_ENTERING_WORLD" then
            -- Defer slightly so addon data has a chance to load. The callback
            -- must re-check lockdown; combat may begin during the delay.
            C_Timer.After(1, function()
                if IsLockedDown() then return end
                SnapshotCurrent(true)
            end)
        elseif event == "UNIT_INVENTORY_CHANGED" then
            -- Only react when the player's equipment changes
            if arg1 == "player" then
                SnapshotCurrent()
                RefreshAfterChange()
            end
        elseif event == "BINDINGS_LOADED" then
            -- Bindings may load after the footer was built; refresh the key text.
            local footer = module.UI and module.UI.footer
            if footer and footer.bindLabel then SetBindLabelText(footer.bindLabel) end
        elseif event == "WEEKLY_REWARDS_UPDATE" or event == "CHALLENGE_MODE_COMPLETED" then
            SnapshotCurrent(true)
            RefreshAfterChange()
        elseif event == "BANKFRAME_OPENED" then
            -- Capture warbank gold when the player visits the bank
            if C_Bank and Enum_BankType_Account then
                local ok, money = pcall(C_Bank.FetchDepositedMoney, Enum_BankType_Account)
                -- Nil-guard (not >0): an emptied warbank must overwrite the
                -- stored balance with 0 instead of keeping a stale value.
                if ok and money ~= nil and type(money) == "number" then
                    local db = addon.db and addon.db.characterViewer
                    if db then
                        db.warbankGold = math.floor(money / 10000)
                        RefreshAfterChange()
                    end
                end
            end
        elseif event == "PLAYER_MONEY" or event == "CURRENCY_DISPLAY_UPDATE" then
            InvalidateMidnightCache()
            UpdateGold()
            local db = addon.db and addon.db.characterViewer
            if db and db.chars then
                local guid = SafeApiCall(UnitGUID, "player")
                if guid and db.chars[guid] then
                    db.chars[guid].currencies = ReadCurrencies()
                end
            end
            RefreshAfterChange()

        end
    end)
    BuildToggleButton()
end

function module:OnEnable()
    -- The event holder may not exist if OnInitialize ran before this
    -- module was first enabled; retry it now (safe outside combat).
    if not holder then module:OnInitialize() end
    if IsLockedDown() then
        -- Combat lockdown: defer event registration and retry when
        -- combat ends instead of leaving the module inert.
        _pendingEnable = true
        if holder then holder:RegisterEvent("PLAYER_REGEN_ENABLED") end
        return
    end
    if not holder then return end
    _pendingEnable = false
    if not toggleButton then BuildToggleButton() end
    holder:UnregisterEvent("PLAYER_REGEN_ENABLED")
    holder:RegisterEvent("PLAYER_LOGIN")
    holder:RegisterEvent("PLAYER_ENTERING_WORLD")
    holder:RegisterEvent("PLAYER_REGEN_DISABLED")
    holder:RegisterEvent("UNIT_INVENTORY_CHANGED")
    holder:RegisterEvent("PLAYER_MONEY")
    holder:RegisterEvent("CURRENCY_DISPLAY_UPDATE")
    holder:RegisterEvent("WEEKLY_REWARDS_UPDATE")
    holder:RegisterEvent("CHALLENGE_MODE_COMPLETED")
    holder:RegisterEvent("BANKFRAME_OPENED")
    holder:RegisterEvent("BINDINGS_LOADED")
end

function module:OnDisable()
    if holder then holder:UnregisterAllEvents() end
    self:Hide()
end

addon:RegisterModule("CharacterViewer", module)
