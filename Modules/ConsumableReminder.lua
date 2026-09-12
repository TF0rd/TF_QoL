-- ════════════════════════════════════════════════════════════════
-- Part 15: Module — Consumable Reminder
-- (Shows an on-screen reminder listing tracked consumables whose
--  combined bag count falls below a per-entry threshold, so you know
--  when to stock up on health potions, combat potions, food, etc.
--  Different ranks of the same consumable are counted together.)
-- ════════════════════════════════════════════════════════════════

local _, addon = ...
local module = {}
addon:RegisterModule("ConsumableReminder", module)

-- ── Local state ──────────────────────────────────────────────

local moduleEnabled  = false
local testModeActive = false

local QUESTION_MARK_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"

-- Item IDs with an outstanding name request (cleared on GET_ITEM_INFO_RECEIVED)
local pendingNameRequests = {}

local frame = CreateFrame("Frame")

-- On-screen display frame
local displayFrame = CreateFrame("Frame", "TFQoL_ConsumableReminderFrame", UIParent)
-- No hardcoded anchor here: position comes from TFQoLDB via UpdatePosition
-- on enable (Core.lua holds the defaults).
displayFrame:SetSize(16, 16)
displayFrame:Hide()

displayFrame.text = displayFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
displayFrame.text:SetPoint("TOPLEFT")
displayFrame.text:SetJustifyH("LEFT")
displayFrame.text:SetShadowOffset(0, 0)
displayFrame.text:SetShadowColor(0, 0, 0, 0)

-- ── Seed defaults ────────────────────────────────────────────

-- Seeded by the module (not Core.lua defaults): MergeDefaults only fills
-- missing keys, so Core-held entries would resurrect after the user deletes
-- them. Seeding on nil preserves an intentionally emptied list.
-- Each entry tracks a combined pool of item IDs (ranks of one consumable).
local SEED_ITEMS = {
    { itemIDs = { 241304, 241305 }, threshold = 20 }, -- Silvermoon Healing Potion (ranks 1-2)
    { itemIDs = { 241288, 241289 }, threshold = 20 }, -- Potion of Recklessness (ranks 1-2)
    { itemIDs = { 260262 },         threshold = 5 },  -- Fairbreeze Feast
}

local function GetDB()
    return TFQoLDB and TFQoLDB.consumableReminder
end

local function EnsureItems(db)
    if not db then return nil end
    if db.items == nil then
        db.items = {}
        for i, entry in ipairs(SEED_ITEMS) do
            local ids = {}
            for j, id in ipairs(entry.itemIDs) do ids[j] = id end
            db.items[i] = { itemIDs = ids, threshold = entry.threshold }
        end
    else
        -- Migration: pre-rank entries stored a single `itemID`.
        for _, entry in ipairs(db.items) do
            if type(entry) == "table" then
                if entry.itemID and type(entry.itemIDs) ~= "table" then
                    entry.itemIDs = { entry.itemID }
                    entry.itemID = nil
                elseif type(entry.itemIDs) ~= "table" then
                    entry.itemIDs = {}
                end
            end
        end
    end
    return db.items
end

-- ── Helpers ──────────────────────────────────────────────────

-- Silvermoon gating: the city spans several map phases across expansions
-- (original 110, later phases 1269/1954 per Wowpedia's UiMapID list, plus the
-- Midnight rebuild), so match the stable zone name OR any known map ID.
local SILVERMOON_ZONE_NAME = "Silvermoon City"
local SILVERMOON_MAP_IDS = { [110] = true, [1269] = true, [1954] = true }

local function IsInSilvermoon()
    if C_Map and C_Map.GetBestMapForUnit then
        local mapID = C_Map.GetBestMapForUnit("player")
        if mapID and SILVERMOON_MAP_IDS[mapID] then return true end
    end
    if GetZoneText and GetZoneText() == SILVERMOON_ZONE_NAME then return true end
    return false
end

local function GetBagCount(itemID)
    local count = C_Item.GetItemCount(itemID, false, false)
    if addon:IsSecretValue(count) then return nil end
    return count or 0
end

local function GetItemIcon(itemID)
    if C_Item.GetItemIconByID then
        return C_Item.GetItemIconByID(itemID)
    end
    return nil
end

-- Cached item name only (no server request).
local function PeekName(itemID)
    if C_Item.GetItemNameByID then
        local name = C_Item.GetItemNameByID(itemID)
        if name and name ~= "" then return name end
    elseif GetItemInfo then
        local name = GetItemInfo(itemID)
        if type(name) == "string" and name ~= "" then return name end
    end
    return nil
end

local function RequestName(itemID)
    -- Not cached yet: request it once; GET_ITEM_INFO_RECEIVED refreshes us.
    -- The pending flag avoids re-requesting on every bag event while uncached.
    if not pendingNameRequests[itemID] then
        pendingNameRequests[itemID] = true
        if C_Item.RequestLoadItemDataByID then
            C_Item.RequestLoadItemDataByID(itemID)
        end
    end
end

-- Strips rank suffixes ("Healing Potion R2", "Potion Rank 2") so ranks of
-- one consumable group under a single base name.
local function NormalizeName(name)
    if type(name) ~= "string" or name == "" then return nil end
    local base = name:gsub("%s+[Rr]%d+$", ""):gsub("%s+[Rr]ank%s+%d+$", "")
    if base == "" then return name end
    return base
end

-- Base name from the first cached rank, or nil when nothing cached yet.
local function EntryBaseName(entry)
    for _, id in ipairs(entry.itemIDs or {}) do
        local name = PeekName(id)
        if name then return NormalizeName(name) or name end
    end
    return nil
end

-- Display name for an entry (requests loads for uncached ranks).
local function GetDisplayName(entry)
    local base = EntryBaseName(entry)
    if base then return base end
    local ids = entry.itemIDs or {}
    if ids[1] then RequestName(ids[1]) end
    return "Item " .. tostring(ids[1])
end

-- Combined bag count across all ranks; nil when any rank is secret-locked
-- (caller skips the entry, same as the old single-ID behavior).
local function EntryCount(entry)
    local total = 0
    for _, id in ipairs(entry.itemIDs or {}) do
        local count = GetBagCount(id)
        if count == nil then return nil end
        total = total + count
    end
    return total
end

local function EntryHasID(entry, itemID)
    for _, id in ipairs(entry.itemIDs or {}) do
        if tonumber(id) == itemID then return true end
    end
    return false
end

-- Folds a newly-cached rank into an existing same-name entry, if any.
local function TryMergeRanks(itemID)
    local db = GetDB()
    if not db then return end
    local items = EnsureItems(db)
    if not items then return end
    local srcIndex = nil
    for i, entry in ipairs(items) do
        if EntryHasID(entry, itemID) then srcIndex = i break end
    end
    if not srcIndex then return end
    local name = PeekName(itemID)
    if not name then return end
    local base = NormalizeName(name) or name
    for i, entry in ipairs(items) do
        if i ~= srcIndex and EntryBaseName(entry) == base then
            for _, id in ipairs(items[srcIndex].itemIDs) do
                if not EntryHasID(entry, id) then
                    entry.itemIDs[#entry.itemIDs + 1] = id
                end
            end
            table.remove(items, srcIndex)
            AbsorbBagRanks(entry)
            return
        end
    end
    AbsorbBagRanks(items[srcIndex])
end

-- Pulls every same-named rank currently in the bags into the entry, so
-- tracking one rank tracks them all by default.
local function AbsorbBagRanks(entry)
    if not (C_Container and C_Container.GetContainerNumSlots and C_Container.GetContainerItemID) then return end
    local base = EntryBaseName(entry)
    if not base then return end
    for bag = 0, 4 do
        local slots = C_Container.GetContainerNumSlots(bag) or 0
        for slot = 1, slots do
            local id = C_Container.GetContainerItemID(bag, slot)
            if id then
                local name = PeekName(id)
                if name and (NormalizeName(name) or name) == base and not EntryHasID(entry, id) then
                    entry.itemIDs[#entry.itemIDs + 1] = id
                end
            end
        end
    end
end

-- Folds entries sharing a base name into the first one (heals saves from
-- before ranks grouped, and any double-adds). Keeps the first threshold.
local function MergeDuplicateBases(items)
    local seen = {}
    local i = 1
    while i <= #items do
        local entry = items[i]
        local base = EntryBaseName(entry)
        if base and seen[base] then
            local target = seen[base]
            for _, id in ipairs(entry.itemIDs or {}) do
                if not EntryHasID(target, id) then
                    target.itemIDs[#target.itemIDs + 1] = id
                end
            end
            table.remove(items, i)
        else
            if base then seen[base] = entry end
            i = i + 1
        end
    end
end

-- ── Core logic ───────────────────────────────────────────────

-- Minimum seconds between background-event refreshes.
local REFRESH_THROTTLE = 0.2
local lastRefresh = 0

local function Refresh(force)
    if not moduleEnabled or testModeActive then return end
    local db = GetDB()
    if not db then return end
    -- Silvermoon gate first: outside the city this is one zone check, then
    -- Hide and out — no counts, no text updates, nothing else runs.
    if db.onlySilvermoon and not IsInSilvermoon() then
        displayFrame:Hide()
        return
    end
    -- Coalesce event bursts (login item-info storms, rapid loot): background
    -- events wait out a short window, explicit actions pass force=true.
    local now = GetTime()
    if not force and (now - lastRefresh) < REFRESH_THROTTLE then return end
    lastRefresh = now
    local items = EnsureItems(db)
    if not items or #items == 0 then
        displayFrame:Hide()
        return
    end

    local lines = {}
    for _, entry in ipairs(items) do
        local threshold = tonumber(entry.threshold) or 1
        local count = EntryCount(entry)
        -- nil count means secret-locked: skip the entry, keep the rest.
        if count ~= nil and count < threshold then
            local icon = module:GetEntryIcon(entry)
            local prefix = (icon and ("|T" .. tostring(icon) .. ":14|t ")) or ""
            lines[#lines + 1] = format("%s%s  |cfff38ba8%d/%d|r",
                prefix, GetDisplayName(entry), count, threshold)
        end
    end

    if #lines > 0 then
        displayFrame.text:SetText(table.concat(lines, "\n"))
        displayFrame:Show()
    else
        displayFrame:Hide()
    end
end

-- ── Font / Position ──────────────────────────────────────────

function module:UpdateFont()
    addon:ApplyAlertFont(displayFrame.text, GetDB())
end

function module:UpdatePosition()
    addon:ApplyPosition(displayFrame, GetDB())
end

-- ── Test Mode ────────────────────────────────────────────────

function module:SetTestMode(enabled)
    testModeActive = enabled
    if enabled then
        self:UpdatePosition()
        displayFrame.text:SetText(
            "|T" .. QUESTION_MARK_ICON .. ":14|t Silvermoon Healing Potion  |cfff38ba83/20|r\n" ..
            "|T" .. QUESTION_MARK_ICON .. ":14|t Potion of Recklessness  |cfff38ba81/20|r")
        displayFrame:Show()
    else
        displayFrame:Hide()
        if moduleEnabled then Refresh() end
    end
end

function module:IsTestMode()
    return testModeActive
end

-- ── Event Handling ───────────────────────────────────────────

frame:SetScript("OnEvent", function(_, event, ...)
    if not moduleEnabled then return end

    if event == "PLAYER_ENTERING_WORLD" then
        local isInitialLogin, isReloadingUi = ...
        if not isInitialLogin and not isReloadingUi then return end
    elseif event == "GET_ITEM_INFO_RECEIVED" then
        local receivedID = ...
        if receivedID then
            pendingNameRequests[receivedID] = nil
            TryMergeRanks(receivedID)
        end
    end

    Refresh()
end)

-- ── Module Lifecycle ─────────────────────────────────────────

function module:OnInitialize()
    local db = GetDB()
    if not db then return end
    local items = EnsureItems(db)
    if not items then return end
    -- Heal pre-grouping saves: absorb bag ranks, then fold same-name rows.
    for _, entry in ipairs(items) do AbsorbBagRanks(entry) end
    MergeDuplicateBases(items)
end

function module:OnEnable()
    moduleEnabled = true
    self:UpdateFont()
    self:UpdatePosition()
    frame:RegisterEvent("BAG_UPDATE_DELAYED")
    frame:RegisterEvent("PLAYER_ENTERING_WORLD")
    frame:RegisterEvent("GET_ITEM_INFO_RECEIVED")
    frame:RegisterEvent("ZONE_CHANGED")
    frame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
    -- Run immediately if we're already past the loading screen (module enabled mid-session).
    if IsLoggedIn() then
        Refresh()
    end
end

function module:OnDisable()
    moduleEnabled = false
    testModeActive = false
    frame:UnregisterAllEvents()
    displayFrame:Hide()
end

-- ── Public API (used by the settings tab) ────────────────────

-- Immediate re-evaluation (location toggles, test hooks).
function module:ForceCheck()
    Refresh(true)
end

function module:GetItems()
    local db = GetDB()
    if not db then return {} end
    return EnsureItems(db) or {}
end

function module:GetItemIcon(itemID)
    return GetItemIcon(itemID)
end

function module:GetDisplayName(entry)
    return GetDisplayName(entry)
end

function module:PeekItemName(itemID)
    return PeekName(itemID)
end

function module:RequestItemName(itemID)
    RequestName(itemID)
end

function module:NormalizeName(name)
    return NormalizeName(name)
end

function module:GetEntryIcon(entry)
    for _, id in ipairs((entry or {}).itemIDs or {}) do
        local icon = GetItemIcon(id)
        if icon then return icon end
    end
    return nil
end

function module:FindItem(itemID)
    local db = GetDB()
    if not db then return nil end
    local items = EnsureItems(db)
    if not items then return nil end
    for index, entry in ipairs(items) do
        if EntryHasID(entry, itemID) then
            return index
        end
    end
    return nil
end

-- Adds an ID, folding it into an existing same-name entry when the name is
-- cached (ranks combine). Uncached IDs start their own entry and merge in
-- via GET_ITEM_INFO_RECEIVED once the name arrives. Returns true on success,
-- false when invalid or already tracked.
function module:AddItem(itemID, threshold)
    itemID = tonumber(itemID)
    threshold = math.floor(tonumber(threshold) or 20)
    if not itemID or itemID <= 0 then return false end
    if threshold < 1 then threshold = 1 end
    if threshold > 999 then threshold = 999 end
    local db = GetDB()
    if not db then return false end
    local items = EnsureItems(db)
    if not items then return false end
    if self:FindItem(itemID) then return false end
    local name = PeekName(itemID)
    if name then
        local base = NormalizeName(name) or name
        for _, entry in ipairs(items) do
            if EntryBaseName(entry) == base then
                entry.itemIDs[#entry.itemIDs + 1] = itemID
                AbsorbBagRanks(entry)
                MergeDuplicateBases(items)
                Refresh(true)
                return true
            end
        end
    else
        RequestName(itemID)
    end
    local entry = { itemIDs = { itemID }, threshold = threshold }
    items[#items + 1] = entry
    AbsorbBagRanks(entry)
    MergeDuplicateBases(items)
    Refresh(true)
    return true
end

function module:RemoveItem(index)
    local db = GetDB()
    if not db then return end
    local items = EnsureItems(db)
    if not items then return end
    index = tonumber(index)
    if index and items[index] then
        table.remove(items, index)
        Refresh(true)
    end
end

function module:SetThreshold(index, threshold)
    local db = GetDB()
    if not db then return end
    local items = EnsureItems(db)
    if not items then return end
    index = tonumber(index)
    threshold = math.floor(tonumber(threshold) or 1)
    if threshold < 1 then threshold = 1 end
    if threshold > 999 then threshold = 999 end
    if index and items[index] then
        items[index].threshold = threshold
        Refresh(true)
    end
end
