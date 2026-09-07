-- ════════════════════════════════════════════════════════════════
-- Module: MountActions
-- Keybinds for Repair Mount and Auction House Mount.
-- Uses standard WoW bindings (like EnhanceQoL) — no override
-- bindings. Syncs with ESC > Key Bindings.
-- ════════════════════════════════════════════════════════════════

local _, addon = ...
local module = {}

local repairButton
local ahButton

local REPAIR_BUTTON_NAME = "TFQoL_RepairMountButton"
local AH_BUTTON_NAME     = "TFQoL_AuctionMountButton"
local REPAIR_BINDING     = "CLICK " .. REPAIR_BUTTON_NAME .. ":LeftButton"
local AH_BINDING         = "CLICK " .. AH_BUTTON_NAME .. ":LeftButton"

local REPAIR_MOUNT_SPELLS = { 457485, 122708, 61425, 61447 }
local AH_MOUNT_SPELLS     = { 264058, 465235 }

-- ── WoW Key Bindings UI registration ──────────────────────────
-- (BINDING_HEADER_TFQoL is set once in Core.lua; the BINDING_NAME lines
-- below label this module's bindings. Bindings.xml provides the category.)
_G["BINDING_NAME_CLICK " .. REPAIR_BUTTON_NAME .. ":LeftButton"] = "Repair Mount"
_G["BINDING_NAME_CLICK " .. AH_BUTTON_NAME .. ":LeftButton"]     = "Auction House Mount"

-- ════════════════════════════════════════════════════════════════
-- Part 1: Mount Helpers
-- ════════════════════════════════════════════════════════════════

local function getMountIdFromSource(sourceID)
    if not sourceID then return nil end
    if C_MountJournal and C_MountJournal.GetMountFromSpell then
        local mountID = C_MountJournal.GetMountFromSpell(sourceID)
        if mountID then return mountID end
    end
    if C_MountJournal and C_MountJournal.GetMountFromItem then
        local mountID = C_MountJournal.GetMountFromItem(sourceID)
        if mountID then return mountID end
    end
    return nil
end

local function isMountSpellUsable(spellID)
    if not spellID then return false end
    local mountID = getMountIdFromSource(spellID)
    if not mountID then return false end
    local _, _, _, _, isUsable, _, _, _, _, shouldHideOnChar, isCollected = C_MountJournal.GetMountInfoByID(mountID)
    if not isCollected or shouldHideOnChar then return false end
    if C_MountJournal.GetMountUsabilityByID then
        local usable = C_MountJournal.GetMountUsabilityByID(mountID, true)
        if usable ~= nil then isUsable = usable end
    end
    return isUsable == true
end

local function pickFirstUsable(spellList)
    for _, spellID in ipairs(spellList) do
        if isMountSpellUsable(spellID) then return spellID end
    end
    return nil
end

local function getSpellNameByID(spellID)
    if not spellID then return nil end
    local name
    if C_Spell and C_Spell.GetSpellName then name = C_Spell.GetSpellName(spellID) end
    if not name and GetSpellInfo then name = GetSpellInfo(spellID) end
    return name
end

local function getMountName(spellID)
    local name = getSpellNameByID(spellID)
    if name and name ~= "" then return name end
    local mountID = getMountIdFromSource(spellID)
    if mountID and C_MountJournal and C_MountJournal.GetMountInfoByID then
        local mountName = C_MountJournal.GetMountInfoByID(mountID)
        if mountName and mountName ~= "" then return mountName end
    end
    return nil
end

local function buildMountMacro(spellID)
    local name = getMountName(spellID)
    if not name or name == "" then return nil end
    local lines = {}
    local _, class = UnitClass("player")
    if class == "DRUID" then lines[#lines + 1] = "/cancelform [nocombat]" end
    -- Dracthyr visage
    if addon.db and addon.db.mountActions and addon.db.mountActions.dracthyrVisage then
        local raceTag = select(2, UnitRace("player"))
        if raceTag == "Dracthyr" then
            if C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID then
                local aura = C_UnitAuras.GetPlayerAuraBySpellID(372014)
                if aura == nil then
                    local visageName = getSpellNameByID(351239)
                    if visageName and visageName ~= "" then
                        lines[#lines + 1] = "/cast " .. visageName
                    end
                end
            end
        end
    end
    lines[#lines + 1] = "/cast " .. name
    return table.concat(lines, "\n")
end

-- ════════════════════════════════════════════════════════════════
-- Part 2: Secure Button Management
-- ════════════════════════════════════════════════════════════════

local function EnsureMountButton(name, spellList)
    local btn = _G[name]
    if not btn then
        btn = CreateFrame("Button", name, UIParent, "SecureActionButtonTemplate")
    end
    btn:RegisterForClicks("AnyDown")
    btn:SetAttribute("type", "macro")
    -- pressAndHoldAction removed: no effect on macro-type buttons
    btn._tfqolSpellList = spellList

    btn:SetScript("PreClick", function(self)
        if InCombatLockdown() then return end
        if IsMounted and IsMounted() then
            self:SetAttribute("macrotext1", "/dismount")
            self:SetAttribute("macrotext", "/dismount")
            return
        end
        local spellID = pickFirstUsable(self._tfqolSpellList)
        local macro = spellID and buildMountMacro(spellID) or nil
        if macro then
            self:SetAttribute("macrotext1", macro)
            self:SetAttribute("macrotext", macro)
        end
    end)

    return btn
end

-- ════════════════════════════════════════════════════════════════
-- Part 3: Events
-- ════════════════════════════════════════════════════════════════

local eventFrame

local function OnEvent(self, event, ...)
    if event == "BINDINGS_LOADED" then
        -- Binding table ready: sync SavedVariables from the standard
        -- bindings (e.g. keys restored from the saved binding set).
        local db = addon.db and addon.db.mountActions
        if db then
            local repairKey = GetBindingKey(REPAIR_BINDING)
            if repairKey and repairKey ~= "" then db.repairKeybind = repairKey end
            local ahKey = GetBindingKey(AH_BINDING)
            if ahKey and ahKey ~= "" then db.ahKeybind = ahKey end
        end
    end
end

-- ════════════════════════════════════════════════════════════════
-- Part 4: Module Lifecycle
-- ════════════════════════════════════════════════════════════════

function module:OnInitialize()
    eventFrame = CreateFrame("Frame")
    eventFrame:SetScript("OnEvent", OnEvent)
    -- Session-scoped: registered once here (not OnEnable) so the binding
    -- table is caught even if the module starts disabled.
    eventFrame:RegisterEvent("BINDINGS_LOADED")

    repairButton = EnsureMountButton(REPAIR_BUTTON_NAME, REPAIR_MOUNT_SPELLS)
    ahButton     = EnsureMountButton(AH_BUTTON_NAME, AH_MOUNT_SPELLS)
end

function module:OnEnable()
    repairButton = EnsureMountButton(REPAIR_BUTTON_NAME, REPAIR_MOUNT_SPELLS)
    ahButton = EnsureMountButton(AH_BUTTON_NAME, AH_MOUNT_SPELLS)
end

function module:OnDisable()
    -- BINDINGS_LOADED stays registered for the session (see OnInitialize).
    -- Clear stale macros so a lingering standard binding fires nothing.
    if repairButton then
        repairButton:SetScript("PreClick", nil)
        repairButton:SetAttribute("macrotext", "")
        repairButton:SetAttribute("macrotext1", "")
        repairButton:Hide()
    end
    if ahButton then
        ahButton:SetScript("PreClick", nil)
        ahButton:SetAttribute("macrotext", "")
        ahButton:SetAttribute("macrotext1", "")
        ahButton:Hide()
    end
end

-- ════════════════════════════════════════════════════════════════
-- Part 5: Public API (for GUI tab)
-- ════════════════════════════════════════════════════════════════

function module:GetRepairKey()
    local key = GetBindingKey(REPAIR_BINDING)
    if key and key ~= "" then return key end
    local db = addon.db and addon.db.mountActions
    return (db and db.repairKeybind) or ""
end

function module:SetRepairKey(key)
    if InCombatLockdown() then return end
    local oldKey = GetBindingKey(REPAIR_BINDING)
    if oldKey then SetBinding(oldKey, nil) end
    if key and key ~= "" then SetBinding(key, REPAIR_BINDING) end
    local db = addon.db and addon.db.mountActions
    if db then db.repairKeybind = key or "" end
    addon:SaveBindingsSafe()
end

function module:GetAHKey()
    local key = GetBindingKey(AH_BINDING)
    if key and key ~= "" then return key end
    local db = addon.db and addon.db.mountActions
    return (db and db.ahKeybind) or ""
end

function module:SetAHKey(key)
    if InCombatLockdown() then return end
    local oldKey = GetBindingKey(AH_BINDING)
    if oldKey then SetBinding(oldKey, nil) end
    if key and key ~= "" then SetBinding(key, AH_BINDING) end
    local db = addon.db and addon.db.mountActions
    if db then db.ahKeybind = key or "" end
    addon:SaveBindingsSafe()
end

addon:RegisterModule("MountActions", module)