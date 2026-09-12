local _, addon = ...
local module = {}

-- ════════════════════════════════════════════════════════════════
-- Part 1: Element Hiding (Micro Menu, Bags)
-- ════════════════════════════════════════════════════════════════

local trackedFrames = {}
local updating = false

local ELEMENT_MAP = {
    hideMicroMenu = { "MicroMenu" },
    hideBagsBar   = { "BagsBar" },
}

local function CollectHideFrames()
    trackedFrames = {}
    local db = addon.db and addon.db.blizzardFrames
    if not db then return end
    for settingName, frameNames in pairs(ELEMENT_MAP) do
        if db[settingName] then
            for _, name in ipairs(frameNames) do
                local frame = _G[name]
                if frame then
                    trackedFrames[#trackedFrames + 1] = frame; break
                end
            end
        end
    end
end

local function SetFramesHidden(hidden)
    for _, frame in ipairs(trackedFrames) do
        if hidden then frame:Hide() else frame:Show() end
    end
end

local function HookHideFrames()
    for _, frame in ipairs(trackedFrames) do
        -- Shared tracker (defined in ActionBarToggle.lua, loaded earlier
        -- per the .toc): hooks OnShow once; re-hides while enabled.
        addon:HookHideOnShow(frame, function()
            return not updating and addon:IsModuleEnabled("BlizzardFrames")
        end)
    end
end

function module:UpdateElements()
    updating = true
    for _, frame in ipairs(trackedFrames) do frame:Show() end
    updating = false
    CollectHideFrames()
    HookHideFrames()
    SetFramesHidden(true)
end

-- ════════════════════════════════════════════════════════════════
-- Part 2: Frame Mover (title-bar drag, matches EnhanceQoL)
-- ════════════════════════════════════════════════════════════════

local MOVABLE_PANELS = {
    -- System
    "SettingsPanel", "GameMenuFrame", "ChatConfigFrame", "HelpFrame",
    "AddonList", "MacroFrame", "SplashFrame", "CatalogShopFrame",
    "EventToastManagerFrame", "TimeManagerFrame",
    -- Character
    "CharacterFrame", "InspectFrame", "DressUpFrame",
    "PlayerSpellsFrame", "AchievementFrame", "CollectionsJournal",
    "ArtifactFrame", "PlayerChoiceFrame", "ItemInteractionFrame",
    -- Activities
    "PVEFrame", "PVPMatchResults", "EncounterJournal",
    "CommunitiesFrame", "FriendsFrame", "CalendarFrame",
    "ReadyCheckFrame", "WeeklyRewardsFrame", "RaidInfoFrame",
    "ExpansionLandingPage", "GarrisonCapacitiveDisplayFrame",
    "GarrisonLandingPage", "MajorFactionRenownFrame",
    "ChallengesKeystoneFrame",
    -- World
    "WorldMapFrame", "BattlefieldMapFrame", "FlightMapFrame",
    "QuestFrame", "GossipFrame", "ClassTrainerFrame",
    -- Bags & Vendors
    "ContainerFrameCombinedBags", "BankFrame",
    "MerchantFrame", "AuctionHouseFrame", "MailFrame", "OpenMailFrame",
    "ItemUpgradeFrame", "ItemSocketingFrame", "CurrencyTransferMenu",
    "ProfessionsFrame", "ProfessionsBookFrame", "ProfessionsCustomerOrdersFrame",
    -- Popups
    "StaticPopup1", "StaticPopup2", "StaticPopup3", "StaticPopup4",
}
module.MOVABLE_PANELS = MOVABLE_PANELS

local InCombatLockdown = InCombatLockdown
local hookedMovers = {}
local hookedPanels = {}
local pendingRestore = {}
local pendingPropagate = {}

local SCALE_MIN, SCALE_MAX, SCALE_STEP = 0.5, 2.0, 0.1

-- ── Shared reset helper ────────────────────────────────────────
-- (Middle-click reset, DisableDrag, and ResetAllPositions all funnel here.)

local function ResetFrameToDefault(frame)
    if not frame then return end
    frame._tfqolMoving = true
    frame:ClearAllPoints()
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    frame._tfqolMoving = nil
    if frame._tfqolScaled and frame._tfqolOrigScale then
        frame._tfqolScaling = true
        frame:SetScale(frame._tfqolOrigScale)
        frame._tfqolScaling = nil
        frame._tfqolScaled = nil
    end
end

local function SavePos(name, point, x, y)
    local db = addon.db and addon.db.blizzardFrames
    if not db then return end
    if not db.moverPositions then db.moverPositions = {} end
    db.moverPositions[name] = { point = point, x = x, y = y }
end

local function GetSavedPos(name)
    local db = addon.db and addon.db.blizzardFrames
    return db and db.moverPositions and db.moverPositions[name]
end

local function ClearPos(name)
    local db = addon.db and addon.db.blizzardFrames
    if db and db.moverPositions then db.moverPositions[name] = nil end
end

-- Scale persistence: stored as a multiplier (0.5–2.0). SetPoint offsets are
-- frame-local units, so when a frame's scale changes we re-apply the saved
-- position to keep it visually in place. The anchor point itself stays at the
-- same screen coordinate during a live rescale, so no manual offset math is
-- needed at scroll-time — only on restore when both scale and position are
-- applied from SavedVariables.
local function SaveScale(name, scale)
    local db = addon.db and addon.db.blizzardFrames
    if not db then return end
    if not db.moverScales then db.moverScales = {} end
    db.moverScales[name] = scale
end

local function GetSavedScale(name)
    local db = addon.db and addon.db.blizzardFrames
    return db and db.moverScales and db.moverScales[name]
end

local function ClearScale(name)
    local db = addon.db and addon.db.blizzardFrames
    if db and db.moverScales then db.moverScales[name] = nil end
end

local function ApplyScale(frame, name)
    local scale = GetSavedScale(name)
    if scale and scale ~= 1 then
        frame._tfqolScaling = true
        frame:SetScale(scale)
        frame._tfqolScaling = nil
        frame._tfqolScaled = true
    end
end

local function ApplyPos(frame, name)
    local pos = GetSavedPos(name)
    if not pos then return end
    if InCombatLockdown() and frame.IsProtected and frame:IsProtected() then
        pendingRestore[frame] = name
        return
    end
    frame._tfqolMoving = true
    frame:ClearAllPoints()
    frame:SetPoint(pos.point, UIParent, pos.point, pos.x, pos.y)
    frame._tfqolMoving = nil
end

-- Hook a panel's SetPoint/SetScale exactly once per session. The hook bodies
-- are gated on the mover setting + module state, so Enable/Disable only
-- create and destroy drag overlays — hooks never pile up and never fire
-- while the mover is off.
local function HookPanelOnce(name)
    if hookedPanels[name] then return end
    local frame = _G[name]
    if not frame then return end
    if frame.IsForbidden and frame:IsForbidden() then return end
    hookedPanels[name] = true

    -- Prevent Blizzard from re-anchoring our moved frames
    hooksecurefunc(frame, "SetPoint", function(self)
        if self._tfqolMoving or self._tfqolDrag then return end
        local db = addon.db and addon.db.blizzardFrames
        if not (db and db.moverEnabled) then return end
        if not addon:IsModuleEnabled("BlizzardFrames") then return end
        local pos = GetSavedPos(name)
        if not pos then return end
        if InCombatLockdown() and self.IsProtected and self:IsProtected() then
            pendingRestore[self] = name
            return
        end
        ApplyPos(self, name)
    end)

    -- Re-assert the user's scale whenever Blizzard (or anything) changes it
    -- in place. Some windows rescale themselves on state changes with no
    -- hide/show to fire the OnShow restore. Only re-assert for frames the
    -- user has actually scaled; guarded so our own re-scale can't recurse.
    hooksecurefunc(frame, "SetScale", function(self, scale)
        if self._tfqolScaling then return end
        local db = addon.db and addon.db.blizzardFrames
        if not (db and db.moverEnabled) then return end
        if not addon:IsModuleEnabled("BlizzardFrames") then return end
        local saved = GetSavedScale(name)
        if saved and math.abs(scale - saved) > 0.005 then
            if not (InCombatLockdown() and self.IsProtected and self:IsProtected()) then
                ApplyScale(self, name)
            end
        end
    end)
end

local function EnableDrag(name)
    local frame = _G[name]
    if not frame then return end
    if frame.IsForbidden and frame:IsForbidden() then return end
    HookPanelOnce(name)
    if hookedMovers[name] then
        -- Overlay already active: just re-apply saved state.
        ApplyPos(frame, name)
        ApplyScale(frame, name)
        return
    end

    local movable = frame.IsMovable and frame:IsMovable() or false
    local clamped = frame.IsClampedToScreen and frame:IsClampedToScreen() or false

    -- Make frame movable (must happen out of combat for protected frames)
    if not (InCombatLockdown() and frame.IsProtected and frame:IsProtected()) then
        frame:SetMovable(true)
        frame:SetClampedToScreen(true)
    end

    -- Create overlay on title bar only: captures drag while passing clicks/hovers through
    local overlay = CreateFrame("Frame", nil, frame)
    overlay:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    overlay:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
    overlay:SetHeight(28)
    overlay:SetFrameLevel(frame:GetFrameLevel() + 5)
    overlay:EnableMouse(true)
    overlay:RegisterForDrag("LeftButton")
    if not InCombatLockdown() then
        if overlay.SetPropagateMouseClicks then overlay:SetPropagateMouseClicks(true) end
        if overlay.SetPropagateMouseMotion then overlay:SetPropagateMouseMotion(true) end
    else
        pendingPropagate[#pendingPropagate + 1] = overlay
    end

    overlay:SetScript("OnDragStart", function()
        if InCombatLockdown() and frame.IsProtected and frame:IsProtected() then return end
        frame._tfqolDrag = true
        frame:StartMoving()
    end)

    overlay:SetScript("OnDragStop", function()
        if not frame._tfqolDrag then return end
        frame._tfqolDrag = nil
        frame:StopMovingOrSizing()
        local point, _, _, x, y = frame:GetPoint()
        if point and x and y then SavePos(name, point, x, y) end
    end)

    -- CTRL+Scroll to rescale (only while hovering the title bar overlay)
    overlay:EnableMouseWheel(true)
    overlay:SetScript("OnMouseWheel", function(_, delta)
        if not IsControlKeyDown() then return end
        if InCombatLockdown() and frame.IsProtected and frame:IsProtected() then return end
        local cur = GetSavedScale(name) or frame:GetScale()
        local new = math.floor((cur + SCALE_STEP * delta) * 100 + 0.5) / 100
        if new < SCALE_MIN then new = SCALE_MIN elseif new > SCALE_MAX then new = SCALE_MAX end
        if math.abs(new - cur) < 0.005 then return end
        frame._tfqolScaling = true
        frame:SetScale(new)
        frame._tfqolScaling = nil
        frame._tfqolScaled = true
        SaveScale(name, new)
    end)

    -- Middle-click on title bar resets this window's position and scale
    overlay:SetScript("OnMouseDown", function(_, button)
        if button ~= "MiddleButton" then return end
        if InCombatLockdown() and frame.IsProtected and frame:IsProtected() then return end
        ClearPos(name)
        ClearScale(name)
        ResetFrameToDefault(frame)
    end)

    frame._tfqolMoverOverlay = overlay
    frame._tfqolMoverDefaults = { movable = movable, clamped = clamped }
    frame._tfqolOrigScale = frame:GetScale()
    hookedMovers[name] = { frame = frame, overlay = overlay }

    -- Apply saved position and scale
    ApplyPos(frame, name)
    ApplyScale(frame, name)
end

local function DisableDrag(name)
    local data = hookedMovers[name]
    if not data then return end
    local frame = data.frame

    if data.overlay then
        data.overlay:Hide()
        data.overlay:SetParent(nil)
    end

    if frame then
        if not (InCombatLockdown() and frame.IsProtected and frame:IsProtected()) then
            local d = frame._tfqolMoverDefaults
            if d then
                if frame.SetMovable then frame:SetMovable(d.movable) end
                if frame.SetClampedToScreen then frame:SetClampedToScreen(d.clamped) end
            end
            -- Reset to default position/scale (only touches moved/scaled
            -- panels; permanent hooks stay installed but gated off).
            if GetSavedPos(name) or frame._tfqolScaled then
                ResetFrameToDefault(frame)
            end
        end
        frame._tfqolMoverOverlay = nil
        frame._tfqolMoverDefaults = nil
        frame._tfqolOrigScale = nil
    end

    hookedMovers[name] = nil
    if frame then pendingRestore[frame] = nil end
end

local function RefreshMover()
    local db = addon.db and addon.db.blizzardFrames
    if not db then return end
    local moverOn = db.moverEnabled and addon:IsModuleEnabled("BlizzardFrames")
    for _, name in ipairs(MOVABLE_PANELS) do
        if moverOn then
            EnableDrag(name)
        else
            DisableDrag(name)
        end
    end
end

-- ════════════════════════════════════════════════════════════════
-- Part 3: Module Lifecycle
-- ════════════════════════════════════════════════════════════════

local eventFrame = CreateFrame("Frame")
eventFrame:SetScript("OnEvent", function(self, event, arg1)
    if event == "PLAYER_ENTERING_WORLD" then
        CollectHideFrames()
        HookHideFrames()
        SetFramesHidden(true)
        RefreshMover()
    elseif event == "PLAYER_REGEN_ENABLED" then
        for frame, name in pairs(pendingRestore) do
            pendingRestore[frame] = nil
            if frame then
                ApplyPos(frame, name)
                ApplyScale(frame, name)
            end
        end
        for _, ol in ipairs(pendingPropagate) do
            if ol then
                if ol.SetPropagateMouseClicks then ol:SetPropagateMouseClicks(true) end
                if ol.SetPropagateMouseMotion then ol:SetPropagateMouseMotion(true) end
            end
        end
        pendingPropagate = {}
    elseif event == "ADDON_LOADED" then
        RefreshMover()
    end
end)

function module:OnEnable()
    CollectHideFrames()
    HookHideFrames()
    SetFramesHidden(true)

    eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    eventFrame:RegisterEvent("ADDON_LOADED")

    RefreshMover()
end

function module:OnDisable()
    SetFramesHidden(false)
    for _, name in ipairs(MOVABLE_PANELS) do
        DisableDrag(name)
    end
    eventFrame:UnregisterAllEvents()
end

function module:RefreshMover() RefreshMover() end

function module:ResetAllPositions()
    local db = addon.db and addon.db.blizzardFrames
    if db then
        db.moverPositions = {}
        db.moverScales = {}
    end
    for _, name in ipairs(MOVABLE_PANELS) do
        local data = hookedMovers[name]
        if data and data.frame then
            ResetFrameToDefault(data.frame)
        end
    end
end

addon:RegisterModule("BlizzardFrames", module)