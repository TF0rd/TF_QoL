-- ════════════════════════════════════════════════════════════════
-- Part 12: Module — Item Upgrade Reminder
-- (Scans equipped items for zero-crest upgrade opportunities using
--  the high-watermark system, with configurable on-screen display,
--  font/position, and test mode)
-- ════════════════════════════════════════════════════════════════

local _, addon = ...
local module = {}
addon:RegisterModule("ItemUpgradeReminder", module)

local moduleEnabled  = false
local testModeActive = false

local frame = CreateFrame("Frame")

-- On-screen display frame
local displayFrame = CreateFrame("Frame", "TFQoL_ItemUpgradeReminderFrame", UIParent)
displayFrame:SetPoint("TOPLEFT", UIParent, "CENTER", 0, 150)
displayFrame:SetSize(16, 16)
displayFrame:Hide()

displayFrame.text = displayFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
displayFrame.text:SetPoint("TOPLEFT")
displayFrame.text:SetJustifyH("LEFT")
displayFrame.text:SetShadowOffset(0, 0)
displayFrame.text:SetShadowColor(0, 0, 0, 0)

local itemSlots = {
    INVSLOT_HEAD,
    INVSLOT_NECK,
    INVSLOT_SHOULDER,
    INVSLOT_CHEST,
    INVSLOT_WAIST,
    INVSLOT_LEGS,
    INVSLOT_FEET,
    INVSLOT_WRIST,
    INVSLOT_HAND,
    INVSLOT_FINGER1,
    INVSLOT_FINGER2,
    INVSLOT_TRINKET1,
    INVSLOT_TRINKET2,
    INVSLOT_BACK,
    INVSLOT_MAINHAND,
    INVSLOT_OFFHAND,
}

-- Bonus ID -> upgrade tier for Midnight Seasons 1-2. Tier keys are
-- season-suffixed because track caps differ between seasons.
-- To rebuild for a new season, fetch https://www.raidbots.com/static/data/live/bonuses.json
-- and run (e.g. with curl piped to python3 or in DevTools with $0 = <pre> containing JSON):
--   Object.values(data).filter(x => x.upgrade?.seasonId === <seasonId>)   -- 37 = Midnight S2
--     .reduce((acc, d) => { acc[d.id] = d.upgrade.name; return acc }, {})
-- NOTE: past seasons are stripped from that file once retired (S1 is already
-- gone), so capture the data while the season is current.
local bonusToTierMap = {
    -- Midnight Season 1 (retired; gear still upgrades flightstone-only, so keep mapped)
    [12704] = "ExplorerS1",   [12762] = "ExplorerS1",   [12763] = "ExplorerS1",   [12764] = "ExplorerS1",
    [12765] = "ExplorerS1",   [12766] = "ExplorerS1",   [12767] = "ExplorerS1",   [12768] = "ExplorerS1",
    [12769] = "AdventurerS1", [12770] = "AdventurerS1", [12771] = "AdventurerS1", [12772] = "AdventurerS1",
    [12773] = "AdventurerS1", [12774] = "AdventurerS1",
    [12777] = "VeteranS1",    [12778] = "VeteranS1",    [12779] = "VeteranS1",    [12780] = "VeteranS1",
    [12781] = "VeteranS1",    [12782] = "VeteranS1",
    [12785] = "ChampionS1",   [12786] = "ChampionS1",   [12787] = "ChampionS1",   [12788] = "ChampionS1",
    [12789] = "ChampionS1",   [12790] = "ChampionS1",
    [12793] = "HeroS1",       [12794] = "HeroS1",       [12795] = "HeroS1",       [12796] = "HeroS1",
    [12797] = "HeroS1",       [12798] = "HeroS1",
    [12801] = "MythS1",       [12802] = "MythS1",       [12803] = "MythS1",       [12804] = "MythS1",
    [12805] = "MythS1",       [12806] = "MythS1",
    -- Midnight Season 2 (no Explorer track this season)
    [12817] = "AdventurerS2", [12818] = "AdventurerS2", [12819] = "AdventurerS2", [12820] = "AdventurerS2",
    [12821] = "AdventurerS2", [12822] = "AdventurerS2",
    [12825] = "VeteranS2",    [12826] = "VeteranS2",    [12827] = "VeteranS2",    [12828] = "VeteranS2",
    [12829] = "VeteranS2",    [12830] = "VeteranS2",
    [12833] = "ChampionS2",   [12834] = "ChampionS2",   [12835] = "ChampionS2",   [12836] = "ChampionS2",
    [12837] = "ChampionS2",   [12838] = "ChampionS2",
    [12841] = "HeroS2",       [12842] = "HeroS2",       [12843] = "HeroS2",       [12844] = "HeroS2",
    [12845] = "HeroS2",       [12846] = "HeroS2",
    [12849] = "MythS2",       [12850] = "MythS2",       [12851] = "MythS2",       [12852] = "MythS2",
    [12853] = "MythS2",       [12854] = "MythS2",
}

-- Per-tier max ilvl, per season.
local tiers = {
    -- Midnight Season 1 (retired)
    AdventurerS1 = { max = 237 },
    VeteranS1    = { max = 250 },
    ChampionS1   = { max = 263 },
    ExplorerS1   = { max = 268 },
    HeroS1       = { max = 276 },
    MythS1       = { max = 289 },
    -- Midnight Season 2
    AdventurerS2 = { max = 282 },
    VeteranS2    = { max = 295 },
    ChampionS2   = { max = 308 },
    HeroS2       = { max = 321 },
    MythS2       = { max = 334 },
}

-- Items below this ilvl floor will never carry a Midnight Season 1 or 2
-- upgrade bonus ID. (S1 Adventurer 1/6 = 220 is the lower of the two floors.)
local LOWEST_TIER_MIN = 220 -- Adventurer 1/6

-- Crafted items have their own upgrade system and don't use the high-watermark path.
local craftedBonusIds = {
    [9365]  = true, -- Ingenuity Crafted
    [9366]  = true, -- Shadowflame Crafted
    [9498]  = true, -- Dream Crafted
    [10222] = true, -- Omen Crafted
    [10249] = true, -- Awakened Crafted
    [12040] = true, -- Fortune Crafted
    [12050] = true, -- Starlight Crafted
    [12066] = true, -- Radiance Crafted (Midnight Season 1)
    [13751] = true, -- Tidal Crafted (Midnight Season 2)
}

-- ── PRIVATE HELPERS ───────────────────────────────────────────

local function GetUpgradeTrack(bonusIds)
    for i = 1, #bonusIds do
        local id = tonumber(bonusIds[i])
        if craftedBonusIds[id] then return end
        local key = bonusToTierMap[id]
        if key then return tiers[key] end
    end
end

local function GetBonusIds(link)
    local itemString = string.match(link, "item:([%-?%d:]+)")
    if not itemString then return {} end

    local itemSplit = {}
    for v in string.gmatch(itemString, "(%d*:?)") do
        if v == ":" then
            itemSplit[#itemSplit + 1] = 0
        else
            itemSplit[#itemSplit + 1] = string.gsub(v, ":", "")
        end
    end

    local bonuses = {}
    local numBonuses = tonumber(itemSplit[13]) or 0
    for index = 1, numBonuses do
        bonuses[#bonuses + 1] = itemSplit[13 + index]
    end
    return bonuses
end

local PREFIX = "|cffcba6f7[TF QoL]|r "

local function DoUpgradeCheck()
    local lines = {}

    for i = 1, #itemSlots do
        local slot = itemSlots[i]
        local itemLoc = ItemLocation:CreateFromEquipmentSlot(slot)

        if itemLoc:IsValid() then
            local currentIlvl = C_Item.GetCurrentItemLevel(itemLoc)

            if currentIlvl >= LOWEST_TIER_MIN then
                local itemLink = C_Item.GetItemLink(itemLoc)

                if itemLink then
                    local upgradeTrack = GetUpgradeTrack(GetBonusIds(itemLink))

                    if upgradeTrack and currentIlvl < upgradeTrack.max then
                        local redundancySlot = slot == INVSLOT_OFFHAND
                            and Enum.ItemRedundancySlot.Offhand
                            or C_ItemUpgrade.GetHighWatermarkSlotForItem(C_Item.GetItemID(itemLoc))

                        if redundancySlot then
                            local charWatermark, accountWatermark =
                                C_ItemUpgrade.GetHighWatermarkForSlot(redundancySlot)

                            if charWatermark and accountWatermark then
                                local watermark = math.min(charWatermark, accountWatermark)
                                local targetIlvl = math.min(upgradeTrack.max, watermark)

                                if currentIlvl < targetIlvl then
                                    print(PREFIX .. format(
                                        "%s can be upgraded to %d for zero crests!",
                                        itemLink, targetIlvl))
                                    lines[#lines + 1] = format("Upgrade %s to %d for zero crests!", itemLink, targetIlvl)
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    local db = TFQoLDB.itemUpgradeReminder
    if db.showOnScreen then
        if #lines > 0 then
            displayFrame.text:SetText(table.concat(lines, "\n"))
            displayFrame:Show()
        else
            displayFrame:Hide()
        end
    else
        displayFrame:Hide()
    end
end

-- ── FONT / POSITION ───────────────────────────────────────────

function module:UpdateFont()
    local db = TFQoLDB.itemUpgradeReminder
    local flags = (TFQoLDB.global.slugRendering == true) and "OUTLINE,SLUG" or "OUTLINE"
    displayFrame.text:SetFont(addon:ResolveFont(db.fontFamily), db.fontSize, flags)
end

function module:UpdatePosition()
    addon:ApplyPosition(displayFrame, TFQoLDB.itemUpgradeReminder)
end

-- ── TEST MODE ─────────────────────────────────────────────────

function module:SetTestMode(enabled)
    testModeActive = enabled
    if enabled then
        displayFrame.text:SetText(
            "Upgrade |cff0070dd[Verdant Gladiator's Helm]|r to 268 for zero crests!\n" ..
            "Upgrade |cffa335ee[Spymistress's Wristwraps]|r to 263 for zero crests!")
        displayFrame:Show()
    else
        displayFrame:Hide()
        if moduleEnabled then DoUpgradeCheck() end
    end
end

function module:IsTestMode()
    return testModeActive
end

-- ── EVENT HANDLING ────────────────────────────────────────────

frame:SetScript("OnEvent", function(_, event, ...)
    if not moduleEnabled then return end

    if event == "PLAYER_ENTERING_WORLD" then
        local isInitialLogin, isReloadingUi = ...
        if not isInitialLogin and not isReloadingUi then return end
    end

    DoUpgradeCheck()
end)

-- ── MODULE LIFECYCLE ──────────────────────────────────────────

function module:OnEnable()
    moduleEnabled = true
    self:UpdateFont()
    self:UpdatePosition()
    frame:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
    frame:RegisterEvent("PLAYER_ENTERING_WORLD")
    -- Run immediately if we're already past the loading screen (module enabled mid-session).
    if IsLoggedIn() then
        DoUpgradeCheck()
    end
end

function module:OnDisable()
    moduleEnabled = false
    testModeActive = false
    frame:UnregisterAllEvents()
    displayFrame:Hide()
end
