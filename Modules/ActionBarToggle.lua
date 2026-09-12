local _, addon = ...
local module = {}

local isHidden = false
local barFrames = {}
local holder
local toggleButton
local BUTTON_NAME = "TFQoL_ActionBarToggle"
local BINDING_ACTION = "CLICK " .. BUTTON_NAME .. ":LeftButton"

-- ── WoW Key Bindings UI registration ──────────────────────────
-- (BINDING_HEADER_TFQoL is set once in Core.lua; the BINDING_NAME line
-- below labels this module's binding. Bindings.xml provides the category.)
_G["BINDING_NAME_CLICK " .. BUTTON_NAME .. ":LeftButton"] = "Toggle Action Bars"

-- ── Bar configuration ─────────────────────────────────────────

local BAR_CONFIGS = {
    { barKey = "Bar1", eab = "EABBar_MainBar", norsken = "NRSKNUI_Bar1_Container", blizz = { "MainActionBar", "MainMenuBar" } },
    { barKey = "Bar2", eab = "EABBar_Bar2",    norsken = "NRSKNUI_Bar2_Container", blizz = { "MultiBarBottomLeft" } },
    { barKey = "Bar3", eab = "EABBar_Bar3",    norsken = "NRSKNUI_Bar3_Container", blizz = { "MultiBarBottomRight" } },
    { barKey = "Bar4", eab = "EABBar_Bar4",    norsken = "NRSKNUI_Bar4_Container", blizz = { "MultiBarRight" } },
    { barKey = "Bar5", eab = "EABBar_Bar5",    norsken = "NRSKNUI_Bar5_Container", blizz = { "MultiBarLeft" } },
    { barKey = "Bar6", eab = "EABBar_Bar6",    norsken = "NRSKNUI_Bar6_Container", blizz = { "MultiBar5" } },
    { barKey = "Bar7", eab = "EABBar_Bar7",    norsken = "NRSKNUI_Bar7_Container", blizz = { "MultiBar6" } },
    { barKey = "Bar8", eab = "EABBar_Bar8",    norsken = "NRSKNUI_Bar8_Container", blizz = { "MultiBar7" } },
}

local OPTIONAL_MAP = {
    includePetBar    = { eab = "EABBar_PetBar",    norsken = "NRSKNUI_PetBar_Container",    blizz = "PetActionBarFrame" },
    includeStanceBar = { eab = "EABBar_StanceBar", norsken = "NRSKNUI_StanceBar_Container", blizz = "StanceBarFrame" },
}

local PET_BAR_CLASSES = {
    HUNTER = true,
    WARLOCK = true,
    DEATHKNIGHT = true,
}

local ipairs = ipairs
local pairs = pairs
local C_Timer = C_Timer

-- ── Shared hide-on-show tracker ────────────────────────────────
-- (Also used by BlizzardFrames.lua, loaded later per the .toc order.
-- Hooks OnShow exactly once per frame; re-hides while `shouldHide`
-- returns true. Returning false skips the hide, e.g. to defer in combat.)

function addon:HookHideOnShow(frame, shouldHide)
    if not frame or frame._tfqolHideHooked then return end
    frame:HookScript("OnShow", function(self)
        if shouldHide and shouldHide(self) then
            self:Hide()
        end
    end)
    frame._tfqolHideHooked = true
end

-- ── Class / form checks ────────────────────────────────────────

local function HasPetBarClass()
    local _, class = UnitClass("player")
    return PET_BAR_CLASSES[class] == true
end

local function HasStanceForms()
    return GetNumShapeshiftForms() > 0
end

-- ── Bar collection ──────────────────────────────────────────────

local function CollectBarFrames()
    barFrames = {}

    local db = addon.db and addon.db.actionBarToggle
    local hasEAB = _G["EABBar_MainBar"] ~= nil
    local hasNorskenUI = _G["NRSKNUI_Bar1_Container"] ~= nil

    for _, cfg in ipairs(BAR_CONFIGS) do
        local enabled = not db or not db.bars or db.bars[cfg.barKey] ~= false
        if enabled then
            local frame
            if hasEAB and cfg.eab then
                frame = _G[cfg.eab]
            elseif hasNorskenUI then
                frame = _G[cfg.norsken]
            else
                for _, name in ipairs(cfg.blizz) do
                    frame = _G[name]
                    if frame then break end
                end
            end
            if frame then
                barFrames[#barFrames + 1] = frame
            end
        end
    end

    if db then
        if db.includePetBar and HasPetBarClass() then
            local name
            if hasEAB and OPTIONAL_MAP.includePetBar.eab then
                name = OPTIONAL_MAP.includePetBar.eab
            elseif hasNorskenUI then
                name = OPTIONAL_MAP.includePetBar.norsken
            else
                name = OPTIONAL_MAP.includePetBar.blizz
            end
            local frame = _G[name]
            if frame then barFrames[#barFrames + 1] = frame end
        end
        if db.includeStanceBar and HasStanceForms() then
            local name
            if hasEAB and OPTIONAL_MAP.includeStanceBar.eab then
                name = OPTIONAL_MAP.includeStanceBar.eab
            elseif hasNorskenUI then
                name = OPTIONAL_MAP.includeStanceBar.norsken
            else
                name = OPTIONAL_MAP.includeStanceBar.blizz
            end
            local frame = _G[name]
            if frame then barFrames[#barFrames + 1] = frame end
        end
    end
end

-- ── Visibility helpers ──────────────────────────────────────────

local pendingBarState = nil
local pendingBindingApply = false

local function SetBarsHidden(hidden)
    if InCombatLockdown() then
        pendingBarState = hidden
        return
    end
    pendingBarState = nil
    for _, frame in ipairs(barFrames) do
        if hidden then
            frame:Hide()
        else
            frame:Show()
        end
    end
end

local function ToggleBars()
    if not addon:IsModuleEnabled("ActionBarToggle") then return end
    isHidden = not isHidden
    SetBarsHidden(isHidden)
    local db = addon.db and addon.db.actionBarToggle
    if db then db.hidden = isHidden end
end

local function HookBarFrames()
    for _, frame in ipairs(barFrames) do
        addon:HookHideOnShow(frame, function()
            if isHidden and addon:IsModuleEnabled("ActionBarToggle") then
                if InCombatLockdown() then
                    pendingBarState = true
                    return false
                end
                return true
            end
            return false
        end)
    end
end

-- ── State enforcement ───────────────────────────────────────────

local function EnforceState()
    if not addon:IsModuleEnabled("ActionBarToggle") then return end
    CollectBarFrames()
    HookBarFrames()
    if isHidden then
        SetBarsHidden(true)
    end
end

-- ── Binding management ─────────────────────────────────────────

--- Resolve the effective key: prefer WoW's standard binding, fall back to SavedVariables.
local function ResolveKey()
    local wowKey = GetBindingKey(BINDING_ACTION)
    if wowKey and wowKey ~= "" then return wowKey end
    local db = addon.db and addon.db.actionBarToggle
    return (db and db.keybind ~= "" and db.keybind) or ""
end

--- Apply the override binding from the resolved key.
local function ApplyOverrideBinding()
    if not holder then return end
    if InCombatLockdown() then
        pendingBindingApply = true
        return
    end
    pendingBindingApply = false
    local key = ResolveKey()
    ClearOverrideBindings(holder)
    if key ~= "" then
        SetOverrideBindingClick(holder, false, key, BUTTON_NAME)
    end
end

--- Read the current keybinding from WoW's standard binding system.
function module:GetCurrentKey()
    local key = GetBindingKey(BINDING_ACTION)
    if key and key ~= "" then return key end
    -- Fall back to SavedVariables (for first-time migration or if standard binding is empty)
    local db = addon.db and addon.db.actionBarToggle
    return (db and db.keybind) or ""
end

--- Restore the standard binding from SavedVariables (used on enable and
--- once the binding table is ready, so a disable-cycle never drops the key).
local function RestoreStandardBinding()
    if InCombatLockdown() then return end
    if not addon:IsModuleEnabled("ActionBarToggle") then return end
    local db = addon.db and addon.db.actionBarToggle
    local key = db and db.keybind or ""
    if key ~= "" and not GetBindingKey(BINDING_ACTION) then
        SetBinding(key, BINDING_ACTION)
    end
end

--- Set a keybinding. Writes to both the standard system (for Key Bindings UI sync)
--- and SavedVariables (as fallback). Also applies the override binding immediately.
function module:SetKeybind(key)
    if InCombatLockdown() then return end

    -- Update standard binding (syncs with Key Bindings UI)
    local oldKey = GetBindingKey(BINDING_ACTION)
    if oldKey then SetBinding(oldKey, nil) end
    if key and key ~= "" then
        SetBinding(key, BINDING_ACTION)
    end

    -- Update SavedVariables before applying, so ApplyOverrideBinding resolves the new key
    local db = addon.db and addon.db.actionBarToggle
    if db then db.keybind = key or "" end
    addon:SaveBindingsSafe()

    ApplyOverrideBinding()
end

--- Temporarily suspend the override binding during keybind capture.
function module:SuspendBinding()
    if holder and not InCombatLockdown() then ClearOverrideBindings(holder) end
end

--- Restore the override binding after a cancelled keybind capture.
function module:RestoreBinding()
    ApplyOverrideBinding()
end

-- ── Events ──────────────────────────────────────────────────────

local function OnEvent(self, event, ...)
    if event == "BINDINGS_LOADED" then
        -- Binding table ready: restore the standard key (if a disable-cycle
        -- cleared it) and apply the override binding.
        RestoreStandardBinding()
        ApplyOverrideBinding()

    elseif event == "PLAYER_ENTERING_WORLD" then
        EnforceState()
        -- Re-apply override binding (safety net after loading screens)
        ApplyOverrideBinding()

    elseif event == "UPDATE_BINDINGS" then
        -- WoW changed bindings — sync our saved key and re-apply override
        local db = addon.db and addon.db.actionBarToggle
        if db then
            local wowKey = GetBindingKey(BINDING_ACTION)
            if wowKey and wowKey ~= "" then
                db.keybind = wowKey
            end
        end
        ApplyOverrideBinding()

    elseif event == "PLAYER_REGEN_ENABLED" then
        if pendingBarState ~= nil then
            SetBarsHidden(pendingBarState)
        end
        if pendingBindingApply then
            ApplyOverrideBinding()
        end
        -- A disable mid-combat keeps this event to flush pending state;
        -- drop it once done so nothing lingers while disabled.
        if not addon:IsModuleEnabled("ActionBarToggle") then
            holder:UnregisterAllEvents()
        end

    elseif event == "PLAYER_SPECIALIZATION_CHANGED"
        or event == "UPDATE_SHAPESHIFT_FORMS"
        or event == "UNIT_PET" then
        -- Spec swap, form change, or pet summon/desummon can add or remove
        -- pet/stance bars. Re-collect frames so the toggle includes them.
        if event == "UNIT_PET" and select(1, ...) ~= "player" then return end
        C_Timer.After(0.1, EnforceState)

    elseif event == "UPDATE_VEHICLE_ACTIONBAR"
        or event == "UNIT_EXITED_VEHICLE"
        or event == "PLAYER_MOUNT_DISPLAY_CHANGED" then
        if isHidden then
            C_Timer.After(0.1, function() SetBarsHidden(true) end)
        end
    end
end

-- ── Module lifecycle ────────────────────────────────────────────

function module:OnInitialize()
    holder = CreateFrame("Frame", "TFQoL_ABTHolder", UIParent)
    holder:Show()
    holder:SetScript("OnEvent", OnEvent)
    -- Session-scoped: registered once here (not OnEnable) so the binding
    -- table is caught even if the module starts disabled.
    holder:RegisterEvent("BINDINGS_LOADED")

    toggleButton = CreateFrame("Button", BUTTON_NAME, UIParent, "SecureActionButtonTemplate")
    toggleButton:RegisterForClicks("AnyUp")
    toggleButton:SetScript("OnClick", function()
        if addon:IsModuleEnabled("ActionBarToggle") then ToggleBars() end
    end)
end

function module:OnEnable()
    local db = addon.db and addon.db.actionBarToggle
    isHidden = db and db.hidden or false

    CollectBarFrames()
    HookBarFrames()
    RestoreStandardBinding()
    if isHidden then SetBarsHidden(true) end

    holder:RegisterEvent("PLAYER_ENTERING_WORLD")
    holder:RegisterEvent("UPDATE_BINDINGS")
    holder:RegisterEvent("UPDATE_VEHICLE_ACTIONBAR")
    holder:RegisterEvent("UNIT_EXITED_VEHICLE")
    holder:RegisterEvent("PLAYER_MOUNT_DISPLAY_CHANGED")
    holder:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
    holder:RegisterEvent("UPDATE_SHAPESHIFT_FORMS")
    holder:RegisterEvent("UNIT_PET")
    holder:RegisterEvent("PLAYER_REGEN_ENABLED")

    -- Hook Blizzard's MultiActionBar_Update to re-hide after it shows bars
    if not module._multiBarHooked then
        hooksecurefunc("MultiActionBar_Update", function()
            if isHidden and addon:IsModuleEnabled("ActionBarToggle") then
                C_Timer.After(0, function()
                    CollectBarFrames()
                    HookBarFrames()
                    SetBarsHidden(true)
                end)
            end
        end)
        module._multiBarHooked = true
    end

    -- Repeating ticker: enforce bar visibility every 1s for the first 10s
    local tickCount = 0
    local ticker
    ticker = C_Timer.NewTicker(1, function()
        tickCount = tickCount + 1
        if tickCount >= 10 or not addon:IsModuleEnabled("ActionBarToggle") then
            ticker:Cancel()
            return
        end
        EnforceState()
        ApplyOverrideBinding()
    end)
end

function module:OnDisable()
    isHidden = false
    SetBarsHidden(false)
    if InCombatLockdown() then
        -- No binding changes allowed in combat: drop any deferred apply so
        -- nothing re-arms after combat while disabled.
        pendingBindingApply = false
    elseif holder then
        ClearOverrideBindings(holder)
        -- Clear the standard binding so the key goes inert while disabled
        -- (restored from db.keybind on the next enable / BINDINGS_LOADED).
        local boundKey = GetBindingKey(BINDING_ACTION)
        if boundKey then SetBinding(boundKey, nil) end
        addon:SaveBindingsSafe()
    end
    if pendingBarState ~= nil then
        -- Disabled mid-combat with a deferred show/hide: keep
        -- PLAYER_REGEN_ENABLED so the pending state still flushes (its
        -- handler unregisters itself once done).
        holder:UnregisterAllEvents()
        holder:RegisterEvent("PLAYER_REGEN_ENABLED")
    else
        holder:UnregisterAllEvents()
    end
end

-- ── Public API ──────────────────────────────────────────────────

function module:UpdateBars()
    CollectBarFrames()
    HookBarFrames()
end

addon:RegisterModule("ActionBarToggle", module)