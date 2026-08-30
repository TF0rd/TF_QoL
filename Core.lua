-- ════════════════════════════════════════════════════════════════
-- Part 1: Core Module
-- (Addon bootstrap, SavedVariables defaults, module registration,
--  DB migration, and addon lifecycle)
-- ════════════════════════════════════════════════════════════════

local addonName, addon = ...
addon.modules = {}

-- ── SavedVariables defaults ──────────────────────────────────

local defaultDB = {
    modules = {
        ["SharedActionBars"] = false,
        ["PotionAlert"] = false,
        ["LustAlert"] = false,
        ["StealthIndicator"] = false,
        ["OCETag"] = false,
        ["GroupJoinedReminder"] = false,
        ["ItemUpgradeReminder"] = false,
        ["CVarBrowser"] = true,
        ["ActionBarToggle"] = false,
        ["BlizzardFrames"] = false,
        ["MountActions"] = false,
        ["ConsumableMacros"] = false,
        ["CharacterViewer"] = true,
        ["MuteSounds"] = false,
    },
    -- ── Global settings ─────────────────────────────────────
    global = {
        slugRendering = false,
    },
    -- ── Potion Alert defaults ───────────────────────────────
    potionAlert = {
        fontSize = 16,
        fontFamily = STANDARD_TEXT_FONT,
        onlyCombat = false,
        showInDungeons = false,
        showInRaids = false,
        showInOpenWorld = false,
        posX = 0,
        posY = -70,
        anchorFrameType = "UIPARENT",
        anchorFrame = "",
        selfPoint = "CENTER",
        anchorPoint = "CENTER",
        playSound = false,
        soundName = "None",
    },
    -- ── Lust Alert defaults ─────────────────────────────────
    lustAlert = {
        fontSize = 16,
        fontFamily = STANDARD_TEXT_FONT,
        onlyCombat = false,
        showInDungeons = false,
        showInRaids = false,
        showInOpenWorld = false,
        posX = 0,
        posY = -100,
        anchorFrameType = "UIPARENT",
        anchorFrame = "",
        selfPoint = "CENTER",
        anchorPoint = "CENTER",
        playSound = false,
        soundName = "None",
        onlyIfHasLust = false,
    },
    -- ── Stealth Indicator defaults ──────────────────────────
    stealthIndicator = {
        fontSize = 14,
        fontFamily = STANDARD_TEXT_FONT,
        posX = 0,
        posY = 25,
        anchorFrameType = "UIPARENT",
        anchorFrame = "",
        selfPoint = "CENTER",
        anchorPoint = "CENTER",
    },
    -- ── Item Upgrade Reminder defaults ──────────────────────
    itemUpgradeReminder = {
        showOnScreen = false,
        fontSize = 16,
        fontFamily = STANDARD_TEXT_FONT,
        posX = 250,
        posY = 150,
        anchorFrameType = "UIPARENT",
        anchorFrame = "",
        selfPoint = "TOPLEFT",
        anchorPoint = "CENTER",
    },
    -- ── Action Bar Toggle defaults ──────────────────────────
    actionBarToggle = {
        keybind = "",
        bars = {
            Bar1 = true,
            Bar2 = true,
            Bar3 = true,
            Bar4 = true,
            Bar5 = true,
            Bar6 = true,
            Bar7 = true,
            Bar8 = true,
        },
        includePetBar = false,
        includeStanceBar = false,
        hidden = false,
    },
    -- ── Blizzard Frames defaults ────────────────────────────
    blizzardFrames = {
        hideMicroMenu = true,
        hideBagsBar = true,
        moverEnabled = false,
        moverFrames = {},
        moverPositions = {},
        moverScales = {},
    },
    -- ── CVar Browser defaults ───────────────────────────────
    cvarBrowser = {
        modifiedCVars = {},
    },
    -- ── Mount Actions defaults ──────────────────────────────
    mountActions = {
        repairKeybind = "",
        ahKeybind = "",
        dracthyrVisage = false,
    },
    -- ── Consumable Macros defaults ─────────────────────────
    consumableMacros = {
        healthMacroEnabled = false,
        includeHealthstone = true,
        drinkMacroEnabled = false,
        preferMageFood = true,
        piMacroEnabled = false,
        piMacroTemplate = "",
    },
    -- ── Character Viewer defaults ──────────────────────────
    characterViewer = {
        keybind = "",
        width = 720,
        height = 400,
        scale = 1.0,
        posPoint = "CENTER",
        posRelPoint = "CENTER",
        posX = 0,
        posY = 0,
        warbankGold = 0,
        chars = {},
        filters = { chars = {}, currencies = {} },
        currencyOrder = {},
    },
    -- ── Mute Sounds defaults ────────────────────────────────
    muteSounds = {
        mounts = {},
        trinkets = {},
        emotes = {},
        customSounds = {},
    },
}

-- ── Helper: DeepCopy ─────────────────────────────────────────

-- Deep-copy a table recursively (needed so SavedVariables don't alias defaultDB)
local function DeepCopy(orig)
    local copy
    if type(orig) == "table" then
        copy = {}
        for k, v in next, orig, nil do
            copy[DeepCopy(k)] = DeepCopy(v)
        end
        setmetatable(copy, DeepCopy(getmetatable(orig)))
    else
        copy = orig
    end
    return copy
end

-- ── Module Registration ──────────────────────────────────────

function addon:RegisterModule(name, moduleTable)
    self.modules[name] = moduleTable
end

-- ── Module State Queries ─────────────────────────────────────

function addon:IsModuleEnabled(name)
    if not self.db then return false end
    return self.db.modules[name]
end

-- ── Shared Position Application ─────────────────────────────

-- Anchors a frame from a module's saved position settings. `db` is the module's
-- settings table (TFQoLDB.<key>). Honors anchorFrameType ("UIPARENT"/"SCREEN"/"FRAME"),
-- selfPoint/anchorPoint (9-point), and posX/posY offsets.
function addon:ApplyPosition(frame, db)
    if not frame or not db then return end

    local parent = UIParent
    if (db.anchorFrameType or "UIPARENT") == "FRAME" and db.anchorFrame and db.anchorFrame ~= "" then
        local custom = _G[db.anchorFrame]
        if custom then parent = custom end
    end

    frame:ClearAllPoints()
    frame:SetPoint(db.selfPoint or "CENTER", parent, db.anchorPoint or "CENTER", db.posX or 0, db.posY or 0)
end

-- ── Module State Management ──────────────────────────────────

function addon:SetModuleEnabled(name, enabled)
    if not self.db then return end
    self.db.modules[name] = enabled

    local module = self.modules[name]
    if module then
        if enabled and module.OnEnable then
            module:OnEnable()
        elseif not enabled and module.OnDisable then
            module:OnDisable()
        end
    end
end

-- ── Global Test Mode Management ──────────────────────────────

function addon:SetGlobalTestMode(enabled)
    for name, module in pairs(self.modules) do
        if self:IsModuleEnabled(name) and module.SetTestMode then
            module:SetTestMode(enabled)
        end
    end
end

function addon:IsAnyTestModeActive()
    for name, module in pairs(self.modules) do
        if self:IsModuleEnabled(name) and module.IsTestMode and module:IsTestMode() then
            return true
        end
    end
    return false
end

-- ── Font Resolution ──────────────────────────────────────────

-- Resolves a font family name to a file path via LibSharedMedia, falling back to STANDARD_TEXT_FONT.
-- If a global font override is set (TFQoLDB.global.fontFamily), it takes precedence over `family`.
function addon:ResolveFont(family)
    local fontPath = STANDARD_TEXT_FONT
    local effective = self.db and self.db.global and self.db.global.fontFamily or family
    if effective then
        local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
        if LSM then
            fontPath = LSM:Fetch("font", effective) or fontPath
        elseif effective:find("\\\\") or effective:find("/") or effective:find("%.") then
            fontPath = effective
        end
    end
    return fontPath
end

function addon:GetLSMFonts()
    local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
    if LSM then return LSM:List("font") end
    return { STANDARD_TEXT_FONT }
end

-- ── ADDON_LOADED Event ───────────────────────────────────────

local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:SetScript("OnEvent", function(self, event, ...)
    if event == "ADDON_LOADED" then
        local loadedAddon = ...
        if loadedAddon == addonName then
            self:UnregisterEvent("ADDON_LOADED")

            -- Initialize DB
            if not TFQoLDB then
                TFQoLDB = DeepCopy(defaultDB)
            else
                -- Migration: ensure any new modules added to defaultDB are enabled by default
                for name, enabled in pairs(defaultDB.modules) do
                    if TFQoLDB.modules[name] == nil then
                        TFQoLDB.modules[name] = enabled
                    end
                end
                -- Remove stale modules no longer in defaultDB
                for name, _ in pairs(TFQoLDB.modules) do
                    if defaultDB.modules[name] == nil then
                        TFQoLDB.modules[name] = nil
                    end
                end

                -- Ensure all sub-tables exist and fill in any missing fields within them
                for key, defaultValue in pairs(defaultDB) do
                    if key ~= "modules" then
                        if not TFQoLDB[key] then
                            TFQoLDB[key] = DeepCopy(defaultValue)
                        elseif type(defaultValue) == "table" then
                            for field, fieldDefault in pairs(defaultValue) do
                                if TFQoLDB[key][field] == nil then
                                    TFQoLDB[key][field] = fieldDefault
                                end
                            end
                            -- Remove stale fields from sub-tables
                            for field, _ in pairs(TFQoLDB[key]) do
                                if defaultValue[field] == nil then
                                    TFQoLDB[key][field] = nil
                                end
                            end
                        end
                    end
                end
                -- Remove stale top-level keys no longer in defaultDB
                for key, _ in pairs(TFQoLDB) do
                    if defaultDB[key] == nil then
                        TFQoLDB[key] = nil
                    end
                end
            end

            addon.db = TFQoLDB

            -- Initialize modules
            for name, module in pairs(addon.modules) do
                if module.OnInitialize then
                    module:OnInitialize()
                end

                if addon:IsModuleEnabled(name) then
                    if module.OnEnable then
                        module:OnEnable()
                    end
                end
            end
        end
    end
end)