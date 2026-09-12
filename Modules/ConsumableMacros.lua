-- ════════════════════════════════════════════════════════════════
-- Module: ConsumableMacros (display name: "Macros")
-- Auto-updating macros for Health Potions and Drinks, plus the
-- Power Infusion target helper (/tf pi).
-- Ported from EnhanceQoL's Food/Health.lua + Food.lua systems.
-- Macro names: TFHealthPotion, TFDrink, TFSetPI, PI
-- ════════════════════════════════════════════════════════════════

local _, addon = ...
local module = {}

local HEALTH_MACRO_NAME = "TFHealthPotion"
local DRINK_MACRO_NAME  = "TFDrink"

local GetMacroInfo     = GetMacroInfo
local EditMacro        = EditMacro
local CreateMacro      = CreateMacro
local GetMacroIndexByName = GetMacroIndexByName
local GetNumMacros     = GetNumMacros
local UnitLevel        = UnitLevel
local UnitName         = UnitName
local UnitHealthMax    = UnitHealthMax
local UnitPowerMax     = UnitPowerMax
local UnitAffectingCombat = UnitAffectingCombat
local InCombatLockdown = InCombatLockdown
local GetTime          = GetTime
local abs              = math.abs

-- ── Forward declarations ──────────────────────────────────────

local eventFrame
local UpdateHealthMacro
local UpdateDrinkMacro

-- ════════════════════════════════════════════════════════════════
-- Part 1: Shared Helpers
-- ════════════════════════════════════════════════════════════════

-- ── Macro Management ──────────────────────────────────────────

local macroWarnings = {}

local function WarnMacroLimitReached(key, message)
    if not key or not message then return end
    if macroWarnings[key] then return end
    macroWarnings[key] = true
    print(message)
end

local function EnsureGlobalMacro(name, icon, body)
    if not name then return false end
    if GetMacroInfo(name) ~= nil then return true end
    if InCombatLockdown and InCombatLockdown() then return false end

    local globalMacros = select(1, GetNumMacros()) or 0
    local globalLimit = _G.MAX_ACCOUNT_MACROS or 120
    if globalMacros >= globalLimit then
        WarnMacroLimitReached(name, "TF QoL: Macro limit reached. Please free a slot for " .. name .. ".")
        return false
    end

    CreateMacro(name, icon or "INV_Misc_QuestionMark")
    if body and GetMacroInfo(name) ~= nil and not (InCombatLockdown and InCombatLockdown()) then
        EditMacro(name, name, nil, body)
    end
    return GetMacroInfo(name) ~= nil
end

-- ── Item Wrapper (newItem) ────────────────────────────────────

local function newItem(id, name, isSpell)
    local self = {}
    self.id = id
    self.name = name
    self.isSpell = isSpell

    function self.getId()
        if self.isSpell then
            if C_Spell and C_Spell.GetSpellName then return C_Spell.GetSpellName(self.id) end
            if GetSpellInfo then return select(1, GetSpellInfo(self.id)) end
            return nil
        end
        return "item:" .. self.id
    end

    function self.getName() return self.name end

    function self.getCount()
        if self.isSpell then return 1 end
        return C_Item.GetItemCount(self.id, false, false) or 0
    end

    return self
end

-- ── Preview helpers (GUI live state) ───────────────────────────

local QUESTION_MARK = "Interface\\Icons\\INV_Misc_QuestionMark"
local healthPreviewListeners = {}
local drinkPreviewListeners = {}

local function resolvePreviewEntry(id, isSpell, note)
    if not id then return nil end
    local entry = {
        id = id,
        isSpell = isSpell and true or false,
        note = note,
        name = nil,
        icon = QUESTION_MARK,
        count = nil,
    }

    if entry.isSpell then
        if C_Spell and C_Spell.GetSpellName then
            entry.name = C_Spell.GetSpellName(id)
        elseif GetSpellInfo then
            entry.name = select(1, GetSpellInfo(id))
        end
        if C_Spell and C_Spell.GetSpellTexture then
            entry.icon = C_Spell.GetSpellTexture(id) or QUESTION_MARK
        elseif GetSpellTexture then
            entry.icon = GetSpellTexture(id) or QUESTION_MARK
        end
        entry.name = entry.name or ("Spell " .. tostring(id))
    else
        if C_Item.RequestLoadItemDataByID then
            C_Item.RequestLoadItemDataByID(id)
        end
        entry.name = (C_Item.GetItemNameByID and C_Item.GetItemNameByID(id)) or nil
        if not entry.name and GetItemInfo then
            entry.name = GetItemInfo(id)
        end
        entry.icon = (C_Item.GetItemIconByID and C_Item.GetItemIconByID(id)) or QUESTION_MARK
        entry.count = C_Item.GetItemCount(id, false, false) or 0
        entry.name = entry.name or ("Item " .. tostring(id))
    end

    return entry
end

local function notifyPreviewListeners(listeners, entries)
    for _, cb in pairs(listeners) do
        pcall(cb, entries)
    end
end

-- ════════════════════════════════════════════════════════════════
-- Part 2: Health Potion Data & Logic
-- ════════════════════════════════════════════════════════════════

local HEALTHSTONE_ITEM_ID              = 5512
local DEMONIC_HEALTHSTONE_ITEM_ID      = 224464
local DEMONIC_HEALTHSTONE_TALENT_SPELL = 386689

local healthList = {
    -- Healthstones (Warlock)
    { key = "Healthstone",        id = HEALTHSTONE_ITEM_ID,         requiredLevel = 5,  healFunc = function(hp) return hp * 0.25 end, type = "stone" },
    { key = "DemonicHealthstone", id = DEMONIC_HEALTHSTONE_ITEM_ID, requiredLevel = 5,  healFunc = function(hp) return hp * 0.25 end, type = "stone" },

    -- Midnight
    { key = "RefreshingSerum3",      id = 241306, requiredLevel = 81, heal = 202377, type = "potion", isCombatPotion = true },
    { key = "RefreshingSerum2",      id = 241307, requiredLevel = 81, heal = 156095, type = "potion", isCombatPotion = true },
    -- Higher priority wins when multiple healing potions are available.
    { key = "PotentHealingPotion",       id = 258138, requiredLevel = 81, heal = 175000, type = "potion", priority = 10 },
    { key = "SilvermoonHealPot2",        id = 241305, requiredLevel = 81, heal = 205956, type = "potion", priority = 20 },
    { key = "SilvermoonHealPot1",        id = 241304, requiredLevel = 81, heal = 241303, type = "potion", priority = 20 },
    { key = "ConcentratedSilvermoonHealPot1", id = 271883, requiredLevel = 81, heal = 359499, type = "potion", priority = 30 },
    { key = "ConcentratedSilvermoonHealPot2", id = 271884, requiredLevel = 81, heal = 421200, type = "potion", priority = 30 },

    -- The War Within: Cavedweller's Delight
    { key = "CavedwellerDelight1", id = 212242, requiredLevel = 71, heal = 42000, type = "potion", isCombatPotion = true },
    { key = "CavedwellerDelight2", id = 212243, requiredLevel = 71, heal = 44500, type = "potion", isCombatPotion = true },
    { key = "CavedwellerDelight3", id = 212244, requiredLevel = 71, heal = 47000, type = "potion", isCombatPotion = true },

    -- The War Within: Invigorating Healing Potion
    { key = "InvigoratingHealPot1", id = 244835, requiredLevel = 71, heal = 62000, type = "potion" },
    { key = "InvigoratingHealPot2", id = 244838, requiredLevel = 71, heal = 67000, type = "potion" },
    { key = "InvigoratingHealPot3", id = 244839, requiredLevel = 71, heal = 72000, type = "potion" },

    -- Khaz Algar: Algari Healing Potion
    { key = "AlgariHealPot1", id = 211878, requiredLevel = 71, heal = 47400, type = "potion" },
    { key = "AlgariHealPot2", id = 211879, requiredLevel = 71, heal = 49800, type = "potion" },
    { key = "AlgariHealPot3", id = 211880, requiredLevel = 71, heal = 52200, type = "potion" },

    -- Dragonflight
    { key = "RefreshHealPot1a", id = 207023, requiredLevel = 70, heal = 32000, type = "potion" },
    { key = "RefreshHealPot2a", id = 207022, requiredLevel = 70, heal = 29000, type = "potion" },
    { key = "RefreshHealPot3a", id = 207021, requiredLevel = 70, heal = 26000, type = "potion" },
    { key = "RefreshHealPot1b", id = 191378, requiredLevel = 61, heal = 24000, type = "potion" },
    { key = "RefreshHealPot2b", id = 191379, requiredLevel = 61, heal = 27000, type = "potion" },
    { key = "RefreshHealPot3b", id = 191380, requiredLevel = 61, heal = 30000, type = "potion" },

    -- Shadowlands
    { key = "SpiritualHealPot", id = 171267, requiredLevel = 51, heal = 12000, type = "potion" },

    -- Battle for Azeroth
    { key = "CoastalHealPot",   id = 152615, requiredLevel = 40, heal = 8000,  type = "potion" },
    { key = "AbyssalHealPot",   id = 169451, requiredLevel = 40, heal = 16000, type = "potion" },

    -- Legion
    { key = "AncientHealPot",   id = 127834, requiredLevel = 40, heal = 6000,  type = "potion" },
    { key = "AgedHealPot",      id = 136569, requiredLevel = 40, heal = 6000,  type = "potion" },

    -- Warlords of Draenor
    { key = "HealingTonic",     id = 109223, requiredLevel = 35, heal = 3400,  type = "potion" },
    { key = "MasterHealPot",    id = 76097,  requiredLevel = 32, heal = 2200,  type = "potion" },
    { key = "MysticalHealPot",  id = 57191,  requiredLevel = 30, heal = 1000,  type = "potion" },

    -- Wrath of the Lich King
    { key = "RunicHealPot",     id = 33447,  requiredLevel = 27, heal = 1200,  type = "potion" },

    { key = "SurvivalHealPot",  id = 224021, requiredLevel = 5,  heal = 750,   type = "potion" },
}

-- Build combat potion lookup
local combatPotionByID = {}
for _, e in ipairs(healthList) do
    if e.id then combatPotionByID[e.id] = e.isCombatPotion == true end
end

-- ── Health filtering state ─────────────────────────────────────

local filteredHealth = {}
local lastHealthPlayerLevel, lastHealthMaxHP = nil, nil
local MAXHP_RECALC_DELTA = 0.05

local function wrapHealthItem(entry, maxHP)
    local obj = newItem(entry.id, nil, false)
    obj.requiredLevel = entry.requiredLevel or 1
    obj.type = entry.type or "potion"
    obj.key = entry.key
    obj.priority = entry.priority or 0
    if entry.healFunc then
        obj.heal = entry.healFunc(maxHP)
    else
        obj.heal = entry.heal or 0
    end
    return obj
end

local function updateAllowedHealth(force)
    local playerLevel = UnitLevel("player")
    local maxHP = UnitHealthMax("player") or 0

    -- Secret-wrapped reads (M+/raid/PvP instances) cannot feed healFunc
    -- arithmetic: keep the previous list instead of computing on secrets.
    if addon.IsSecretValue and addon:IsSecretValue(maxHP) then return end

    if not force then
        local levelChanged = playerLevel ~= lastHealthPlayerLevel
        local hpChanged = false
        if not lastHealthMaxHP or lastHealthMaxHP == 0 then
            hpChanged = true
        else
            local delta = abs(maxHP - lastHealthMaxHP) / lastHealthMaxHP
            hpChanged = delta >= MAXHP_RECALC_DELTA
        end
        if not levelChanged and not hpChanged then return end
    end

    lastHealthPlayerLevel = playerLevel
    lastHealthMaxHP = maxHP

    local filtered = {}
    for i = 1, #healthList do
        local e = healthList[i]
        if (e.requiredLevel or 1) <= playerLevel then
            local w = wrapHealthItem(e, maxHP)
            w._order = i
            filtered[#filtered + 1] = w
        end
    end

    if #filtered > 1 then
        table.sort(filtered, function(a, b)
            local aL, bL = a.requiredLevel or 0, b.requiredLevel or 0
            if aL ~= bL then return aL > bL end
            local aH, bH = a.heal or 0, b.heal or 0
            if aH ~= bH then return aH > bH end
            return (a._order or 999) < (b._order or 999)
        end)
    end

    filteredHealth = filtered
end

-- ── Health macro cooldown tracking ─────────────────────────────

local healthCooldownCache = {}

local function getHealthSpellCooldown(spellId)
    local cd = C_Spell.GetSpellCooldown(spellId)
    if not cd then return 0, 0 end
    local start = cd.startTime or 0
    local duration = cd.duration or 0
    return start, duration
end

local function healthCooldownRemaining(entry)
    if not entry then return math.huge end
    if entry.isSpell then
        local inBook = C_SpellBook.IsSpellInSpellBook(entry.id)
        if not inBook then return math.huge end
        local start, duration = getHealthSpellCooldown(entry.id)
        if addon.IsSecretValue and (addon:IsSecretValue(start) or addon:IsSecretValue(duration)) then return math.huge end
        if start == 0 or duration == 0 then return 0 end
        local remain = (start + duration) - GetTime()
        return remain > 0 and remain or 0
    end
    local itemID = entry.id
    if not itemID then return 0 end
    local start, duration = C_Item.GetItemCooldown(itemID)
    if addon.IsSecretValue and (addon:IsSecretValue(start) or addon:IsSecretValue(duration)) then return math.huge end
    if not start or start == 0 or not duration or duration == 0 then return 0 end
    local remain = (start + duration) - GetTime()
    return remain > 0 and remain or 0
end

-- ── Health macro build ─────────────────────────────────────────

-- Cached per talent configID: the C_Traits tree walk below is too
-- expensive to run per candidate inside selectHealthSequence().
local demonicTalentCache = {}

local function InvalidateDemonicTalentCache()
    demonicTalentCache = {}
end

local function hasDemonicTalent()
    if not C_ClassTalents or not C_Traits or not C_Traits.GetConfigInfo then return false end
    local configID = C_ClassTalents.GetActiveConfigID()
    if not configID then return false end
    local cached = demonicTalentCache[configID]
    if cached ~= nil then return cached end
    local result = false
    local cfg = C_Traits.GetConfigInfo(configID)
    if cfg and cfg.treeIDs and cfg.treeIDs[1] then
        local treeID = cfg.treeIDs[1]
        local nodes = C_Traits.GetTreeNodes(treeID) or {}
        for _, nodeID in ipairs(nodes) do
            local nodeInfo = C_Traits.GetNodeInfo(configID, nodeID)
            if nodeInfo and nodeInfo.activeEntry and (nodeInfo.ranksPurchased or 0) > 0 then
                local entryInfo = C_Traits.GetEntryInfo(configID, nodeInfo.activeEntry.entryID)
                if entryInfo and entryInfo.definitionID then
                    local def = C_Traits.GetDefinitionInfo(entryInfo.definitionID)
                    if def and def.spellID == DEMONIC_HEALTHSTONE_TALENT_SPELL then
                        result = true
                        break
                    end
                end
            end
        end
    end
    demonicTalentCache[configID] = result
    return result
end

local lastHealthMacroKey

-- Returns ordered candidates currently selected for TFHealthPotion.
local function selectHealthSequence()
    local db = addon.db and addon.db.consumableMacros
    if not db or not db.healthMacroEnabled then return {}, "disabled" end

    updateAllowedHealth(false)

    local bestByCategory = {}
    local bestRemainByCategory = {}

    local function assignBest(category, candidate)
        if not category or not candidate then return end
        local remain = healthCooldownRemaining(candidate)
        local current = bestByCategory[category]
        local currentRemain = bestRemainByCategory[category]
        local candidatePriority = candidate.priority or 0
        local currentPriority = current and (current.priority or 0) or 0
        if not current
            or candidatePriority > currentPriority
            or (candidatePriority == currentPriority and remain < currentRemain)
            or (candidatePriority == currentPriority and remain == currentRemain and (candidate.heal or 0) > (current.heal or 0)) then
            bestByCategory[category] = candidate
            bestRemainByCategory[category] = remain
        end
    end

    local _, class = UnitClass("player")
    local isWarlock = class == "WARLOCK"
    local includeHealthstone = db.includeHealthstone ~= false

    for _, item in ipairs(filteredHealth) do
        if item.getCount() > 0 then
            if item.type == "stone" then
                if includeHealthstone then
                    if isWarlock and hasDemonicTalent() then
                        local demonicCount = C_Item.GetItemCount(DEMONIC_HEALTHSTONE_ITEM_ID, false, false) or 0
                        if demonicCount > 0 then
                            local demonic = newItem(DEMONIC_HEALTHSTONE_ITEM_ID, nil, false)
                            demonic.type = "stone"
                            assignBest("stone", demonic)
                        else
                            assignBest("stone", item)
                        end
                    else
                        assignBest("stone", item)
                    end
                end
            elseif item.type == "potion" then
                local cat = combatPotionByID[item.id] and "combatpotion" or "potion"
                assignBest(cat, item)
            end
        end
    end

    local order = { "stone", "potion", "combatpotion" }
    local seqList = {}
    local macroEntries = {}
    local seen = {}

    for _, cat in ipairs(order) do
        local cand = bestByCategory[cat]
        if cand then
            local token = cand.getId()
            if token and not seen[token] then
                seqList[#seqList + 1] = token
                macroEntries[#macroEntries + 1] = cand
                seen[token] = true
            end
        end
    end

    while #seqList > 4 do
        table.remove(seqList)
        table.remove(macroEntries)
    end

    if #macroEntries == 0 then
        return {}, "empty"
    end
    return macroEntries, nil, seqList
end

local function buildHealthPreviewEntries(items)
    local entries = {}
    for i = 1, #items do
        local cand = items[i]
        local note
        if cand.type == "stone" then
            note = "Healthstone"
        elseif cand.type == "potion" and combatPotionByID[cand.id] then
            note = "Combat potion"
        elseif cand.type == "potion" then
            note = "Potion"
        end
        entries[#entries + 1] = resolvePreviewEntry(cand.id, cand.isSpell, note)
    end
    return entries
end

-- All eligible health consumables in fallback order, independent of the
-- compact castsequence selected by selectHealthSequence().
local function selectHealthInventory()
    local db = addon.db and addon.db.consumableMacros
    local includeHealthstone = db and db.includeHealthstone ~= false
    updateAllowedHealth(false)
    local items = {}
    for _, item in ipairs(filteredHealth) do
        if item.getCount() > 0 and (includeHealthstone or item.type ~= "stone") then
            items[#items + 1] = item
        end
    end
    table.sort(items, function(a, b)
        local aType = a.type == "stone" and 100 or (a.priority or 0)
        local bType = b.type == "stone" and 100 or (b.priority or 0)
        if aType ~= bType then return aType > bType end
        if (a.heal or 0) ~= (b.heal or 0) then return (a.heal or 0) > (b.heal or 0) end
        return (a._order or 999) < (b._order or 999)
    end)
    return items
end

local function buildHealthMacro()
    local db = addon.db and addon.db.consumableMacros
    if not db or not db.healthMacroEnabled then
        notifyPreviewListeners(healthPreviewListeners, {})
        return
    end

    local macroEntries, _, seqList = selectHealthSequence()
    notifyPreviewListeners(healthPreviewListeners, buildHealthPreviewEntries(selectHealthInventory()))

    local macroBody
    local key
    if seqList and #seqList >= 1 then
        local parts = { "#showtooltip" }
        parts[#parts + 1] = "/castsequence reset=combat " .. table.concat(seqList, ", ")
        macroBody = table.concat(parts, "\n")
        key = "seq:" .. table.concat(seqList, "|") .. "|combat"
    else
        macroBody = "#showtooltip"
        key = "empty"
    end

    if key ~= lastHealthMacroKey then
        if InCombatLockdown and InCombatLockdown() then return end
        if not GetMacroInfo(HEALTH_MACRO_NAME) and not EnsureGlobalMacro(HEALTH_MACRO_NAME, "INV_Misc_QuestionMark", "#showtooltip") then return end
        if GetMacroInfo(HEALTH_MACRO_NAME) then
            EditMacro(HEALTH_MACRO_NAME, HEALTH_MACRO_NAME, nil, macroBody)
        end
        lastHealthMacroKey = key
    end
end

UpdateHealthMacro = function(ignoreCombat)
    local db = addon.db and addon.db.consumableMacros
    if not db or not db.healthMacroEnabled then
        notifyPreviewListeners(healthPreviewListeners, {})
        return
    end
    if UnitAffectingCombat("player") and not ignoreCombat then
        -- Still refresh GUI preview; EditMacro is deferred to regen.
        notifyPreviewListeners(healthPreviewListeners, buildHealthPreviewEntries(selectHealthInventory()))
        return
    end
    if not EnsureGlobalMacro(HEALTH_MACRO_NAME, "INV_Misc_QuestionMark", "#showtooltip") then
        notifyPreviewListeners(healthPreviewListeners, buildHealthPreviewEntries(selectHealthInventory()))
        return
    end
    updateAllowedHealth(false)
    buildHealthMacro()
end

-- ════════════════════════════════════════════════════════════════
-- Part 3: Drink Data & Logic
-- ════════════════════════════════════════════════════════════════

-- isEarthen: computed on-demand inside updateAllowedDrinks()

local drinkList = {
    -- Special
    { key = "ConjureRefreshment", id = 190336, requiredLevel = 5,  mana = 0, isSpell = true },
    { key = "CandyBar",           id = 20390,  requiredLevel = 1,  mana = 225000 },
    { key = "CandyCorn",          id = 20389,  requiredLevel = 1,  mana = 225000 },
    { key = "ConjuredManaBun",    id = 113509, requiredLevel = 40, mana = 0, isMageFood = true, isEarthenFood = true },
    { key = "ConjuredManaFritter",id = 80618,  requiredLevel = 35, mana = 0, isMageFood = true, isEarthenFood = true },
    { key = "ConjuredManaPudding",id = 80610,  requiredLevel = 35, mana = 0, isMageFood = true, isEarthenFood = true },
    { key = "ConjuredManaCake",   id = 65499,  requiredLevel = 32, mana = 0, isMageFood = true, isEarthenFood = true },
    { key = "ConjuredManaStrudel",id = 43523,  requiredLevel = 30, mana = 0, isMageFood = true, isEarthenFood = true },
    { key = "ConjuredManaPie",    id = 43518,  requiredLevel = 28, mana = 0, isMageFood = true, isEarthenFood = true },
    { key = "ConjuredManaLollipop",id= 65517,  requiredLevel = 26, mana = 0, isMageFood = true, isEarthenFood = true },
    { key = "ConjuredManaCupcake",id = 65516,  requiredLevel = 23, mana = 0, isMageFood = true, isEarthenFood = true },
    { key = "ConjuredManaBrownie",id = 65515,  requiredLevel = 19, mana = 0, isMageFood = true, isEarthenFood = true },
    { key = "ConjuredManaCookie", id = 65500,  requiredLevel = 14, mana = 0, isMageFood = true, isEarthenFood = true },
    { key = "CrunchyRockCandy",   id = 228494, requiredLevel = 1,  mana = 3700000, isEarthenFood = true, earthenOnly = true },
    { key = "ManagiRoll",         id = 260255, requiredLevel = 80, mana = 0, isHealthOnly = true },
    { key = "QuietContemplation", id = 461063, requiredLevel = 1,  mana = 3700000, isEarthenFood = true, earthenOnly = true, isSpell = true },

    -- TWW / Midnight drinks
    { key = "MarinatedMaggots",    id = 226811, requiredLevel = 75, mana = 47724 },
    { key = "GorlocFinSoup",       id = 197847, requiredLevel = 10, mana = 53332 },
    { key = "SniffinSoup",         id = 204790, requiredLevel = 65, mana = 53332 },
    { key = "AzureLeywine",        id = 194684, requiredLevel = 10, mana = 62500 },
    { key = "BeetleJuice197854",   id = 205794, requiredLevel = 65, mana = 62500 },
    { key = "DeliciousDragonSpittle",id=197771, requiredLevel = 65, mana = 71428 },
    { key = "FreshlySqueezed",     id = 204729, requiredLevel = 65, mana = 62500 },
    { key = "EnchantedArgali",     id = 197854, requiredLevel = 10, mana = 53332 },
    { key = "ApexisAsiago",        id = 201419, requiredLevel = 10, mana = 53332 },
    { key = "BreakfastDraconic",   id = 197763, requiredLevel = 10, mana = 71428 },
    { key = "DracthyrWater",       id = 200305, requiredLevel = 10, mana = 50000 },
    { key = "CinderNectar",        id = 222744, requiredLevel = 68, mana = 53572 },
    { key = "PepInYourStep",       id = 222745, requiredLevel = 68, mana = 53572 },
    { key = "Magmalaid",           id = 227310, requiredLevel = 70, mana = 32000 },
    { key = "Titanshake",          id = 227309, requiredLevel = 70, mana = 32000 },
    { key = "QuicksilverSipper",   id = 227318, requiredLevel = 75, mana = 40000 },
    { key = "LavaCola",            id = 227317, requiredLevel = 75, mana = 40000 },
    { key = "ChalcociteLavaCake",  id = 227326, requiredLevel = 75, mana = 30000 },
    { key = "StoneSoup",           id = 227325, requiredLevel = 75, mana = 30000 },
    { key = "RockyRoad",           id = 227327, requiredLevel = 75, mana = 30000 },
    { key = "TarragonSoda",        id = 227315, requiredLevel = 70, mana = 32000 },
    { key = "Eggnog",              id = 227316, requiredLevel = 70, mana = 32000 },
    { key = "NerubarNectar",       id = 227324, requiredLevel = 75, mana = 40000 },
    { key = "MushroomTea",         id = 227323, requiredLevel = 75, mana = 40000 },
    { key = "MoleMole",            id = 227334, requiredLevel = 75, mana = 30000 },
    { key = "BorerBloodPudding",   id = 227335, requiredLevel = 75, mana = 30000 },
    { key = "SugarSlurry",         id = 227336, requiredLevel = 75, mana = 30000 },
    { key = "GallagioEspecial",    id = 236646, requiredLevel = 75, mana = 30000 },
    { key = "GlimmeringDelicacy",  id = 227333, requiredLevel = 75, mana = 30000 },
    { key = "ImitationCrabMeat",   id = 236680, requiredLevel = 75, mana = 30000 },
    { key = "Paincracker",         id = 236650, requiredLevel = 75, mana = 30000 },
    { key = "CoinAndKaja",         id = 236647, requiredLevel = 75, mana = 30000 },
    { key = "LowTownFizz",         id = 236633, requiredLevel = 75, mana = 30000 },
    { key = "LiquidGold",          id = 236681, requiredLevel = 75, mana = 30000 },
    { key = "LiquidNitro",         id = 236648, requiredLevel = 75, mana = 30000 },
    { key = "FewScrewsLoose",      id = 236649, requiredLevel = 75, mana = 30000 },
    { key = "SippingAether",       id = 227332, requiredLevel = 75, mana = 30000 },
    { key = "Afterglow",           id = 227312, requiredLevel = 70, mana = 32000 },
    { key = "BlessedBrew",         id = 227321, requiredLevel = 75, mana = 40000 },
    { key = "CherryBombs",         id = 232376, requiredLevel = 60, mana = 50000 },
    { key = "CoagulatedMilk",      id = 247699, requiredLevel = 75, mana = 30000 },
    { key = "CoffeeLightIce",      id = 227314, requiredLevel = 70, mana = 32000 },
    { key = "DeepFriedDevourer",   id = 247698, requiredLevel = 75, mana = 30000 },
    { key = "DelversWaterskin",    id = 224762, requiredLevel = 75, mana = 32000 },
    { key = "Digspresso",          id = 227311, requiredLevel = 70, mana = 32000 },
    { key = "GrizzlyHillsTrailMix",id = 226262, requiredLevel = 75, mana = 30000 },
    { key = "GrizzlyHillsSpring",  id = 226274, requiredLevel = 70, mana = 32000 },
    { key = "StarfruitPuree",      id = 227313, requiredLevel = 70, mana = 32000 },
    { key = "Koboldchino",         id = 227319, requiredLevel = 75, mana = 40000 },
    { key = "WickerWisps",         id = 227320, requiredLevel = 75, mana = 40000 },
    { key = "SanctifiedSasparilla",id = 227322, requiredLevel = 75, mana = 40000 },
    { key = "WaxFondue",           id = 227328, requiredLevel = 75, mana = 30000 },
    { key = "StillTwitchingGumbo", id = 227329, requiredLevel = 75, mana = 30000 },
    { key = "GrottochunkStew",     id = 227330, requiredLevel = 75, mana = 30000 },
    { key = "SaintsDelight",       id = 227331, requiredLevel = 75, mana = 30000 },
    { key = "SleuthsSip",          id = 232007, requiredLevel = 1,  mana = 1008 },
    { key = "MachosFishTacos",     id = 238896, requiredLevel = 80, mana = 30000 },
    { key = "Kafaccino",           id = 242693, requiredLevel = 1,  mana = 15000 },
    { key = "SniftedVoidEssence",  id = 247694, requiredLevel = 75, mana = 40000 },
    { key = "SparklingManaSupp",   id = 247695, requiredLevel = 75, mana = 40000 },
    { key = "PungentSmellingSalts",id = 247696, requiredLevel = 75, mana = 30000 },
    { key = "GenuineKareshiHoney", id = 247700, requiredLevel = 75, mana = 30000 },

    -- Midnight drinks (percent-based mana)
    { key = "PurifiedCordial",     id = 260258, requiredLevel = 80, mana = 0, manaPercent = 4, manaDuration = 20 },
    { key = "EverspringWater",     id = 260259, requiredLevel = 80, mana = 0, manaPercent = 4, manaDuration = 20 },
    { key = "SpringrunnerSparkling",id= 260260, requiredLevel = 85, mana = 0, manaPercent = 5, manaDuration = 20 },
    { key = "FairbreezeFeast",     id = 260262, requiredLevel = 90, mana = 0, manaPercent = 7, manaDuration = 20 },
    { key = "SilvermoonSoiree",    id = 260263, requiredLevel = 90, mana = 0, manaPercent = 7, manaDuration = 20 },
    { key = "BloomNectar",         id = 260261, requiredLevel = 85, mana = 0, manaPercent = 5, manaDuration = 20 },
    { key = "QuelDanásRations",    id = 260264, requiredLevel = 90, mana = 0, manaPercent = 7, manaDuration = 20 },
    { key = "DarkwellDraft",       id = 264984, requiredLevel = 80, mana = 0, manaPercent = 4, manaDuration = 20 },
    { key = "Dawnmosa",            id = 264985, requiredLevel = 80, mana = 0, manaPercent = 4, manaDuration = 20 },
    { key = "MagistersMead",       id = 264987, requiredLevel = 80, mana = 0, manaPercent = 4, manaDuration = 20 },
    { key = "SunwellShot",         id = 264983, requiredLevel = 80, mana = 0, manaPercent = 4, manaDuration = 20 },
    { key = "DragonhawkFlight",    id = 264989, requiredLevel = 80, mana = 0, manaPercent = 4, manaDuration = 20 },
    { key = "MidnightRefresh260282",id= 260282, requiredLevel = 80, mana = 0, manaPercent = 4, manaDuration = 20 },
    { key = "MidnightRefresh260283",id= 260283, requiredLevel = 80, mana = 0, manaPercent = 4, manaDuration = 20 },
    { key = "MidnightRefresh260284",id= 260284, requiredLevel = 85, mana = 0, manaPercent = 5, manaDuration = 20 },
    { key = "MidnightRefresh260285",id= 260285, requiredLevel = 85, mana = 0, manaPercent = 5, manaDuration = 20 },
    { key = "MidnightRefresh260286",id= 260286, requiredLevel = 90, mana = 0, manaPercent = 7, manaDuration = 20, sortRank = 1 },
    { key = "MidnightRefresh260287",id= 260287, requiredLevel = 90, mana = 0, manaPercent = 7, manaDuration = 20, sortRank = 1 },
    { key = "MidnightRefresh260288",id= 260288, requiredLevel = 90, mana = 0, manaPercent = 7, manaDuration = 20, sortRank = 1 },
    { key = "ArgentleafTea",       id = 242298, requiredLevel = 80, mana = 0, manaPercent = 8, manaDuration = 20 },
    { key = "AzerootTea",          id = 242301, requiredLevel = 80, mana = 0, manaPercent = 8, manaDuration = 20 },
    { key = "ManaLilyTea",         id = 242297, requiredLevel = 80, mana = 0, manaPercent = 8, manaDuration = 20 },
    { key = "SanguithornTea",      id = 242299, requiredLevel = 80, mana = 0, manaPercent = 8, manaDuration = 20 },
    { key = "TranquilityBloomTea", id = 242300, requiredLevel = 80, mana = 0, manaPercent = 8, manaDuration = 20 },
    { key = "RootJuice",           id = 260271, requiredLevel = 80, mana = 0, manaPercent = 4, manaDuration = 20 },
    { key = "CrispBluffBock",      id = 260272, requiredLevel = 80, mana = 0, manaPercent = 4, manaDuration = 20 },
    { key = "TeaOfMistsAndRain",   id = 260273, requiredLevel = 85, mana = 0, manaPercent = 5, manaDuration = 20 },
    { key = "DenshroomDeepRoast",  id = 260274, requiredLevel = 85, mana = 0, manaPercent = 5, manaDuration = 20 },
    { key = "MukleechCurry",       id = 260275, requiredLevel = 90, mana = 0, manaPercent = 7, manaDuration = 20 },
    { key = "Akilstew",            id = 260276, requiredLevel = 90, mana = 0, manaPercent = 7, manaDuration = 20 },
    { key = "SedgeCrawlerGumbo",   id = 260277, requiredLevel = 90, mana = 0, manaPercent = 7, manaDuration = 20 },
    { key = "PurifiedStormWater",  id = 260295, requiredLevel = 85, mana = 0, manaPercent = 5, manaDuration = 20 },
    { key = "ShadeleafTea",        id = 260296, requiredLevel = 85, mana = 0, manaPercent = 5, manaDuration = 20 },
    { key = "VoidfarersRespite",   id = 260297, requiredLevel = 90, mana = 0, manaPercent = 7, manaDuration = 20 },
    { key = "AstralApplePie",      id = 260298, requiredLevel = 90, mana = 0, manaPercent = 7, manaDuration = 20 },
    { key = "RoastedAbyssalEel",   id = 260299, requiredLevel = 90, mana = 0, manaPercent = 7, manaDuration = 20 },
    { key = "GoldengroveJuice",    id = 264981, requiredLevel = 80, mana = 0, manaPercent = 4, manaDuration = 20 },
    { key = "WineNot",             id = 264982, requiredLevel = 80, mana = 0, manaPercent = 4, manaDuration = 20 },
    { key = "FairbreezeFranciacorta",id=264990, requiredLevel = 80, mana = 0, manaPercent = 4, manaDuration = 20 },
    { key = "ConjuredTea",         id = 265099, requiredLevel = 80, mana = 0, manaPercent = 6, manaDuration = 20 },
    { key = "BuddingLight",        id = 265664, requiredLevel = 80, mana = 0, manaPercent = 4, manaDuration = 20 },
    { key = "ChanterelleShandy",   id = 265665, requiredLevel = 80, mana = 0, manaPercent = 4, manaDuration = 20 },
    { key = "WorldRootBeer",       id = 265666, requiredLevel = 80, mana = 0, manaPercent = 4, manaDuration = 20 },
    { key = "BrightClaw",          id = 265667, requiredLevel = 80, mana = 0, manaPercent = 4, manaDuration = 20 },
    { key = "VoidPort",            id = 260293, requiredLevel = 80, mana = 0, manaPercent = 4, manaDuration = 20 },
    { key = "VoidwyrmAbsinthe",    id = 260294, requiredLevel = 80, mana = 0, manaPercent = 4, manaDuration = 20 },

    -- Classic / older drinks
    { key = "RefreshingSpringWater",id= 159,    requiredLevel = 1,  mana = 0, manaPercent = 1, manaDuration = 20 },
    { key = "IceColdMilk",          id = 1179,  requiredLevel = 3,  mana = 0, manaPercent = 1, manaDuration = 20 },
    { key = "MelonJuice",           id = 1205,  requiredLevel = 7,  mana = 0, manaPercent = 1, manaDuration = 20 },
    { key = "SweetNectar",          id = 1708,  requiredLevel = 11, mana = 0, manaPercent = 1, manaDuration = 20 },
    { key = "MoonberryJuice",       id = 1645,  requiredLevel = 15, mana = 0, manaPercent = 2, manaDuration = 20 },
    { key = "MorningGloryDew",      id = 8766,  requiredLevel = 10, mana = 0, manaPercent = 2, manaDuration = 20 },
    { key = "FreshWater",           id = 58274, requiredLevel = 27, mana = 0, manaPercent = 3, manaDuration = 20 },
    { key = "HoneymintTea",         id = 33445, requiredLevel = 35, mana = 0, manaPercent = 3, manaDuration = 20 },
    { key = "PungentSealWhey",      id = 33444, requiredLevel = 25, mana = 0, manaPercent = 3, manaDuration = 20 },
    { key = "HighlandSpringWater",  id = 58257, requiredLevel = 32, mana = 0, manaPercent = 4, manaDuration = 20 },
    { key = "SparklingOasisWater",  id = 58256, requiredLevel = 30, mana = 0, manaPercent = 4, manaDuration = 20 },
    { key = "FilteredDraenicWater", id = 28399, requiredLevel = 10, mana = 0, manaPercent = 2, manaDuration = 20 },
    { key = "CoboCola",             id = 81923, requiredLevel = 35, mana = 0, manaPercent = 4, manaDuration = 20 },
    { key = "CarbonatedWater",      id = 81924, requiredLevel = 32, mana = 0, manaPercent = 4, manaDuration = 20 },
}

-- ── Drink sorting ──────────────────────────────────────────────

local function getDrinkManaValue(drink, maxMana)
    if not drink then return 0 end
    if drink.isMageFood then return maxMana end
    local percent = tonumber(drink.manaPercent)
    if percent and percent > 0 then
        local duration = tonumber(drink.manaDuration)
        if duration and duration > 0 then return maxMana * (percent * duration / 100) end
        return maxMana * (percent / 100)
    end
    return tonumber(drink.mana) or 0
end

local lastSortedMana = nil

local function sortDrinkList(maxMana)
    if lastSortedMana == maxMana then return end
    for i = 1, #drinkList do
        drinkList[i]._sortMana = getDrinkManaValue(drinkList[i], maxMana)
    end
    table.sort(drinkList, function(a, b)
        local mA, mB = a._sortMana or 0, b._sortMana or 0
        if mA ~= mB then return mA > mB end
        local rA = tonumber(a.sortRank) or 0
        local rB = tonumber(b.sortRank) or 0
        if rA ~= rB then return rA > rB end
        local lA = tonumber(a.requiredLevel) or 0
        local lB = tonumber(b.requiredLevel) or 0
        if lA ~= lB then return lA > lB end
        return (tonumber(a.id) or 0) < (tonumber(b.id) or 0)
    end)
    lastSortedMana = maxMana
end

-- ── Drink filtering ────────────────────────────────────────────

local filteredDrinks = {}

local function updateAllowedDrinks()
    local db = addon.db and addon.db.consumableMacros
    if not db then return end

    local playerLevel = UnitLevel("player")
    local maxMana = UnitPowerMax("player", Enum.PowerType.Mana) or 0
    if maxMana <= 0 then return end

    local _, race = UnitRace("player")
    local earthen = (race == "EarthenDwarf")

    sortDrinkList(maxMana)

    local filtered = {}
    local mageFoods = {}
    local _, playerClass = UnitClass("player")
    for i = 1, #drinkList do
        local drink = drinkList[i]
        local req = drink.requiredLevel
        local dMana = drink._sortMana or getDrinkManaValue(drink, maxMana)
        local isMageRefresh = drink.id == 190336 and playerClass == "MAGE"

        if req <= playerLevel then
            if not (earthen and not drink.isEarthenFood)
               and not (drink.earthenOnly and not earthen)
               and not drink.isHealthOnly
               and not (drink.isSpell and not C_SpellBook.IsSpellInSpellBook(drink.id))
            then
                local obj = newItem(drink.id, nil, drink.isSpell)
                obj._drinkData = drink
                if drink.isMageFood then
                    mageFoods[#mageFoods + 1] = obj
                else
                    filtered[#filtered + 1] = obj
                end
            end
        end
    end

    if db.preferMageFood == true and #mageFoods > 0 then
        -- Mage food first, best (highest level) at the head.
        for i = #mageFoods, 1, -1 do
            table.insert(filtered, 1, mageFoods[i])
        end
    elseif #mageFoods > 0 then
        for i = 1, #mageFoods do
            filtered[#filtered + 1] = mageFoods[i]
        end
    end

    filteredDrinks = filtered
end


local function unitHasMana()
    return (UnitPowerMax("player", Enum.PowerType.Mana) or 0) > 0
end

-- Returns all eligible drink items in descending mana-value order.
local function selectDrinkSequence()
    local db = addon.db and addon.db.consumableMacros
    if not db or not db.drinkMacroEnabled then return {}, "disabled" end
    if not unitHasMana() then return {}, "no_mana" end

    updateAllowedDrinks()

    local slots = {}
    for _, value in ipairs(filteredDrinks) do
        if value.getCount() > 0 then
            slots[#slots + 1] = {
                id = value.id,
                isSpell = value.isSpell and true or false,
                note = value.isSpell and "Spell" or "Drink",
            }
        end
    end

    if #slots == 0 then
        return {}, "empty"
    end
    return slots, nil
end

local function buildDrinkPreviewEntries(items)
    local entries = {}
    for i = 1, #items do
        local item = items[i]
        local note = item.note
        if not note then
            note = item.isSpell and "Spell" or "Drink"
        end
        entries[#entries + 1] = resolvePreviewEntry(item.id, item.isSpell, note)
    end
    return entries
end

-- All eligible mana-food consumables currently in the bags, in fallback order.
local function selectDrinkInventory()
    if not unitHasMana() then return {} end
    updateAllowedDrinks()
    local items = {}
    for _, item in ipairs(filteredDrinks) do
        if item.getCount() > 0 then
            items[#items + 1] = item
        end
    end
    return items
end

-- ── Drink macro build ──────────────────────────────────────────

local lastDrinkItemPlaced

local function buildDrinkMacro()
    local db = addon.db and addon.db.consumableMacros
    if not db or not db.drinkMacroEnabled then
        notifyPreviewListeners(drinkPreviewListeners, {})
        return
    end

    local slots = selectDrinkSequence()
    notifyPreviewListeners(drinkPreviewListeners, buildDrinkPreviewEntries(selectDrinkInventory()))

    local macroItems = {}
    for i = 1, #slots do
        local s = slots[i]
        if s.isSpell then
            macroItems[#macroItems + 1] = (C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(s.id))
                or (GetSpellInfo and select(1, GetSpellInfo(s.id)))
        else
            macroItems[#macroItems + 1] = "item:" .. s.id
        end
    end

    local foundItem = table.concat(macroItems, ", ")
    if foundItem == lastDrinkItemPlaced then return end
    if InCombatLockdown and InCombatLockdown() then return end
    if GetMacroInfo(DRINK_MACRO_NAME) == nil then return end

    local parts = { "#showtooltip" }
    if foundItem then
        parts[#parts + 1] = "/castsequence reset=combat " .. foundItem
    end

    EditMacro(DRINK_MACRO_NAME, DRINK_MACRO_NAME, nil, table.concat(parts, "\n"))
    lastDrinkItemPlaced = foundItem
end

UpdateDrinkMacro = function(ignoreCombat)
    local db = addon.db and addon.db.consumableMacros
    if not db or not db.drinkMacroEnabled then
        notifyPreviewListeners(drinkPreviewListeners, {})
        return
    end
    if UnitAffectingCombat("player") and not ignoreCombat then
        notifyPreviewListeners(drinkPreviewListeners, buildDrinkPreviewEntries(selectDrinkInventory()))
        return
    end
    if not unitHasMana() then
        notifyPreviewListeners(drinkPreviewListeners, {})
        return
    end
    if not EnsureGlobalMacro(DRINK_MACRO_NAME, "INV_Misc_QuestionMark", "#showtooltip") then
        notifyPreviewListeners(drinkPreviewListeners, buildDrinkPreviewEntries(selectDrinkInventory()))
        return
    end
    updateAllowedDrinks()
    buildDrinkMacro()
end

-- ════════════════════════════════════════════════════════════════
-- Part 3.5: Power Infusion Helper
-- ════════════════════════════════════════════════════════════════

-- The PI macro body is built in addon code so it can grow past the
-- 255-character macro text limit. The body is generated from a
-- user-editable template (set in the settings GUI) that uses {target}
-- as a placeholder for the baked player name. Run /tf pi (or the
-- TFSetPI macro) with a player targeted to bake that name in.
-- Cast priority: mouseover > saved target > self.
local PI_MACRO_NAME   = "PI"
local PI_TRIGGER_NAME = "TFSetPI"
local PI_ICON         = 135939 -- Power Infusion
local PI_TARGET_TOKEN = "{target}"

-- Built-in template, used when the user hasn't saved a custom one.
local DEFAULT_PI_TEMPLATE = table.concat({
    "/cast [@mouseover,help,nodead][@" .. PI_TARGET_TOKEN .. ",exists][@player] Power Infusion",
    "/use 13",
    "/cast Shadow Word: Madness",
}, "\n")

local piPreviewListeners = {}

local function notifyPIPreviewListeners(template)
    for _, cb in pairs(piPreviewListeners) do
        pcall(cb, template)
    end
end

-- The effective template: the user's saved template, or the built-in default.
local function GetPITemplate()
    local db = addon.db and addon.db.consumableMacros
    local t = db and db.piMacroTemplate
    if t and t ~= "" then return t end
    return DEFAULT_PI_TEMPLATE
end

-- Resolves the template for a concrete target name.
local function BuildPIMacroBody(targetName)
    return (GetPITemplate():gsub(PI_TARGET_TOKEN, function() return targetName or "player" end))
end

-- Writes a new body into the PI macro (creating it if missing).
local function WritePIMacroBody(body)
    if not body or body == "" then return end
    if InCombatLockdown() then return end
    local macroID = GetMacroIndexByName(PI_MACRO_NAME)
    if macroID ~= 0 then
        EditMacro(macroID, nil, nil, body)
    else
        CreateMacro(PI_MACRO_NAME, PI_ICON, body)
    end
end

local function SetPowerInfusionTarget()
    if InCombatLockdown() then return end
    local targetName = UnitName("target") or "player"
    local body = BuildPIMacroBody(targetName)
    WritePIMacroBody(body)
    notifyPIPreviewListeners(GetPITemplate())
    print("PI: " .. targetName)
end

local function UpdatePIMacro()
    local db = addon.db and addon.db.consumableMacros
    if not db or not db.piMacroEnabled then
        notifyPIPreviewListeners(nil)
        return
    end
    if InCombatLockdown() then return end
    -- Trigger macro: minimal body calling into the addon.
    EnsureGlobalMacro(PI_TRIGGER_NAME, PI_ICON, "/tf pi")
    -- Cast macro: only created when missing; /tf pi owns its body.
    if GetMacroIndexByName(PI_MACRO_NAME) == 0 then
        CreateMacro(PI_MACRO_NAME, PI_ICON, BuildPIMacroBody("player"))
    end
    notifyPIPreviewListeners(GetPITemplate())
end

-- ════════════════════════════════════════════════════════════════
-- Part 4: Event Handling
-- ════════════════════════════════════════════════════════════════

local pendingDrinkUpdate = false

local function OnEvent(self, event, arg1)
    local db = addon.db and addon.db.consumableMacros
    if not db then return end

    if event == "PLAYER_LOGIN" then
        if db.healthMacroEnabled then
            UpdateHealthMacro(false)
        end
        if db.drinkMacroEnabled then
            updateAllowedDrinks()
            UpdateDrinkMacro(false)
        end
        if db.piMacroEnabled then UpdatePIMacro() end
        return
    end

    if event == "PLAYER_REGEN_ENABLED" then
        if db.healthMacroEnabled then UpdateHealthMacro(true) end
        if db.drinkMacroEnabled then UpdateDrinkMacro(true) end
        if db.piMacroEnabled then UpdatePIMacro() end

    elseif event == "BAG_UPDATE_DELAYED" then
        if db.healthMacroEnabled then UpdateHealthMacro(false) end
        if db.drinkMacroEnabled and not pendingDrinkUpdate then
            pendingDrinkUpdate = true
            C_Timer.After(0.05, function()
                UpdateDrinkMacro(false)
                pendingDrinkUpdate = false
            end)
        end

    elseif event == "PLAYER_LEVEL_UP" then
        if not UnitAffectingCombat("player") then
            if db.healthMacroEnabled then UpdateHealthMacro(true) end
            if db.drinkMacroEnabled then
                updateAllowedDrinks()
                UpdateDrinkMacro(true)
            end
        end

    elseif event == "SPELLS_CHANGED" or event == "PLAYER_TALENT_UPDATE" then
        InvalidateDemonicTalentCache()
        if db.drinkMacroEnabled then
            updateAllowedDrinks()
            UpdateDrinkMacro(false)
        end
        if db.healthMacroEnabled then UpdateHealthMacro(false) end

    elseif event == "UNIT_MAXHEALTH" then
        if arg1 == "player" and not UnitAffectingCombat("player") then
            if db.healthMacroEnabled then UpdateHealthMacro(false) end
        end

    elseif event == "PLAYER_EQUIPMENT_CHANGED" then
        if db.healthMacroEnabled then UpdateHealthMacro(false) end
    end
end

-- ════════════════════════════════════════════════════════════════
-- Part 5: Module Lifecycle
-- ════════════════════════════════════════════════════════════════

function module:OnInitialize()
    eventFrame = CreateFrame("Frame")
    eventFrame:SetScript("OnEvent", OnEvent)
end

function module:OnEnable()
    eventFrame:RegisterEvent("PLAYER_LOGIN")
    eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    eventFrame:RegisterEvent("BAG_UPDATE_DELAYED")
    eventFrame:RegisterEvent("PLAYER_LEVEL_UP")
    eventFrame:RegisterEvent("SPELLS_CHANGED")
    eventFrame:RegisterEvent("PLAYER_TALENT_UPDATE")
    eventFrame:RegisterEvent("UNIT_MAXHEALTH")
    eventFrame:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
end

function module:OnDisable()
    eventFrame:UnregisterAllEvents()
    lastHealthMacroKey = nil
    lastDrinkItemPlaced = nil
    notifyPreviewListeners(healthPreviewListeners, {})
    notifyPreviewListeners(drinkPreviewListeners, {})
    notifyPIPreviewListeners(nil)
end

-- ════════════════════════════════════════════════════════════════
-- Part 6: Public API
-- ════════════════════════════════════════════════════════════════

function module:RefreshHealthMacro()
    lastHealthMacroKey = nil
    UpdateHealthMacro(false)
end

function module:RefreshDrinkMacro()
    lastDrinkItemPlaced = nil
    UpdateDrinkMacro(false)
end

function module:RefreshPIMacro()
    UpdatePIMacro()
end

-- Called by the /tf pi slash command and the TFSetPI macro.
function module:SetPowerInfusionTarget()
    SetPowerInfusionTarget()
end

-- Live preview API for the settings GUI (PI macro body textarea).
function module:GetPIMacroBody()
    return GetPITemplate()
end

-- Persist the user's edited template. The live PI macro is (re)baked on
-- the next /tf pi (or TFSetPI) run, which substitutes {target}.
function module:SetPIMacroBody(text)
    local db = addon.db and addon.db.consumableMacros
    if not db then return end
    db.piMacroTemplate = text or ""
    notifyPIPreviewListeners(GetPITemplate())
end

function module:RegisterPIPreviewListener(key, callback)
    if type(key) ~= "string" then return end
    piPreviewListeners[key] = callback
    if type(callback) == "function" then
        local ok, template = pcall(GetPITemplate)
        if ok then
            pcall(callback, template)
        end
    end
end

function module:UnregisterPIPreviewListener(key)
    if type(key) == "string" then piPreviewListeners[key] = nil end
end

-- Live preview API for the settings GUI.
function module:GetHealthMacroPreview()
    local db = addon.db and addon.db.consumableMacros
    if not db or not db.healthMacroEnabled then return {} end
    return buildHealthPreviewEntries(selectHealthInventory())
end

function module:GetDrinkMacroPreview()
    local db = addon.db and addon.db.consumableMacros
    if not db or not db.drinkMacroEnabled then return {} end
    return buildDrinkPreviewEntries(selectDrinkInventory())
end

function module:RegisterHealthPreviewListener(key, callback)
    if type(key) ~= "string" then return end
    healthPreviewListeners[key] = callback
    if type(callback) == "function" then
        local ok, entries = pcall(self.GetHealthMacroPreview, self)
        if ok then
            pcall(callback, entries)
        end
    end
end

function module:UnregisterHealthPreviewListener(key)
    if type(key) == "string" then
        healthPreviewListeners[key] = nil
    end
end

function module:RegisterDrinkPreviewListener(key, callback)
    if type(key) ~= "string" then return end
    drinkPreviewListeners[key] = callback
    if type(callback) == "function" then
        local ok, entries = pcall(self.GetDrinkMacroPreview, self)
        if ok then
            pcall(callback, entries)
        end
    end
end

function module:UnregisterDrinkPreviewListener(key)
    if type(key) == "string" then
        drinkPreviewListeners[key] = nil
    end
end

addon:RegisterModule("ConsumableMacros", module)