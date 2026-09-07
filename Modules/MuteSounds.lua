-- ════════════════════════════════════════════════════════════════
-- Module — Mute Sounds
-- (Mutes specific game sound file IDs via MuteSoundFile/UnmuteSoundFile)
-- ════════════════════════════════════════════════════════════════

local _, addon = ...
local module = {}

-- ── Sound file data (from EnhanceQoL) ──────────────────────
-- Each entry: { label = "Display Name", sounds = { id, id, ... } }
-- The db key for each entry is derived from the category + index:
--   muteSounds.mounts.<key> = true/false
--   muteSounds.trinkets.<key> = true/false
--   muteSounds.emotes.<key> = true/false

module.SoundCategories = {
    mounts = {
        {
            key = "pterodactyl",
            label = "Pterodactyl",
            sounds = {
                838877, 838879, 838881, 838883, 838885, 838887,
                838903, 838905, 838907, 838909, 838911, 838913,
                838915, 838917, 838919, 838921,
            },
        },
        {
            key = "banlu",
            label = "Ban Lu (Monk Mount)",
            sounds = {
                1593212, 1593213, 1593214, 1593215, 1593216, 1593217,
                1593218, 1593219, 1593220, 1593221, 1593222, 1593223,
                1593224, 1593225, 1593226, 1593227, 1593228, 1593229,
                1593230, 1593231, 1593232, 1593233, 1593234, 1593235,
                1593236,
            },
        },
        {
            key = "grand_expedition_yak",
            label = "Grand Expedition Yak",
            sounds = {
                -- Cousin Slowhands greetings
                640336, 640338, 640340,
                -- Cousin Slowhands farewells
                640314, 640316, 640318, 640320,
                -- Mystic Birdhat greetings
                640180, 640182, 640184,
                -- Mystic Birdhat farewells
                640158, 640160, 640162, 640164,
            },
        },
        {
            key = "peafowl",
            label = "Peafowl",
            sounds = {
                5546937, 5546939, 5546941, 5546943,
            },
        },
        {
            key = "wonderwing_20",
            label = "Wonderwing 2.0",
            sounds = {
                2148660, 2148661, 2148662, 2148663, 2148664,
            },
        },
        {
            key = "mount_chopper",
            label = "Chopper",
            sounds = {
                569859, 569858, 569855, 569857, 569863, 569856,
                569860, 569862, 569861, 569854, 569845, 569852,
                598736, 598745, 598748, 568252,
            },
        },
        {
            key = "mount_mimiron_head",
            label = "Mimiron's Head",
            sounds = {
                555364, 595097, 595100, 595103,
            },
        },
        {
            key = "mount_the_dreadwake",
            label = "The Dreadwake",
            sounds = {
                -- Horn
                566064,
                -- Bell
                1838477,
                -- WaterSplash Dismount
                2066773, 2066774, 2066775, 2066776, 2066777,
                -- WaterSplash Mount
                2066768, 2066769, 2066770, 2066771, 2066772,
            },
        },
        {
            key = "mount_storm_gryphon",
            label = "Storm Gryphon",
            sounds = {
                -- Mount
                5356559, 5356561, 5356563, 5356565, 5356567, 5356569, 5356571,
                -- Thunder
                3088094,
                -- Mountspecial
                5357752, 5357769, 5357771, 5357773, 5357775,
            },
        },
        {
            key = "mount_g99_breakneck",
            label = "G-99 Breakneck",
            sounds = {
                -- Movement
                2431461, 2431464, 2431465,
                -- Summon
                1487173, 1487174, 1487175, 1487176, 1487177,
                1487178, 1487179, 1487180, 1487181, 1487182,
                -- Engine start
                1659508, 1659509, 1659510, 1659511,
                -- Gear shift broken
                2138705,
                -- Engine running
                6254769, 6382128, 6382130, 6382181, 6382183,
                6382185, 6382187, 6382189, 6382191, 6382193,
                -- Drifting
                6654849, 6654851, 6654853, 6654855, 6654857,
                6654859, 6654861, 6654863, 6654865, 6654867,
            },
        },
        {
            key = "groveglider",
            label = "Groveglider",
            sounds = {
                7476917, 7476919, 7476921, 7476923, 7476925,
                7476927, 7476929, 7476931, 7476933, 7476935,
                7476937, 7476939, 7476941, 7477075, 7477077,
                7477079, 7477081, 7477083, 7477085, 7477087,
                7477089, 7477091, 7477093, 7477095, 7477097,
                7477099, 7477101, 7477103, 7477105, 7477107,
                7477109, 7477111, 7477113, 7477115, 7477117,
                7477119, 7477121, 7484609, 7484612, 7484615,
                7484618, 7484621, 7484627, 7484629, 7484632,
                7484635, 7484638, 7484641, 7484643,
            },
        },
    },
    trinkets = {
        {
            key = "gaze_of_the_alnseer",
            label = "Gaze of the Alnseer",
            sounds = {
                2144789, 2144790, 2144791,
            },
        },
    },
    emotes = {
        {
            key = "train",
            label = "Train Emote",
            sounds = {
                -- Orc
                541239, 541157,
                -- Undead
                542600, 542526,
                -- Tauren
                542896, 542818,
                -- Troll
                543093, 543085,
                -- Blood Elf
                539203, 539219, 1306531, 1313588,
                -- Goblin
                542017, 541769,
                -- Nightborne
                1732405, 1732030,
                -- Highmountain Tauren
                1730908, 1730534,
                -- Mag'har Orc
                1951458, 1951457,
                -- Zandalari Troll
                1903522, 1903049,
                -- Vulpera
                3106717, 3106252,
                -- Pandaren
                630296, 630298, 636621,
                -- Dracthyr
                4737561, 4738601, 4741007, 4739531,
                -- Earthen
                6021052, 6021067,
                -- Human
                540734, 540535,
                -- Dwarf
                539881, 539802,
                -- Night Elf
                540947, 540870, 1304872, 1316209,
                -- Gnome
                540275, 540271,
                -- Draenei
                539730, 539516,
                -- Worgen
                541601, 542206, 541463, 542035,
                -- Void Elf
                1733163, 1732785,
                -- Lightforged Draenei
                1731656, 1731282,
                -- Dark Iron Dwarf
                1902543, 1902030,
                -- Kul Tiran Human
                2491898, 2531204,
                -- Mechagnome
                3107182, 3107651,
            },
        },
        {
            key = "meerahs_jukebox",
            label = "Meerah's Jukebox",
            sounds = {
                3169894,
            },
        },
    },
}

-- ── Build flat lookup: soundId -> list of { cat, key } refs ──────
-- This lets us know if a sound should stay muted when toggling categories.
-- The { cat, key } pair is stored at build time so callers never re-parse
-- a concatenated key string per lookup.
local soundToKeys = {}
for catName, entries in pairs(module.SoundCategories) do
    for _, entry in ipairs(entries) do
        for _, soundId in ipairs(entry.sounds) do
            if not soundToKeys[soundId] then
                soundToKeys[soundId] = {}
            end
            soundToKeys[soundId][#soundToKeys[soundId] + 1] = { cat = catName, key = entry.key }
        end
    end
end

-- ── Localize API ──────────────────────────────────────────

local MuteSoundFile = MuteSoundFile
local UnmuteSoundFile = UnmuteSoundFile

-- ── Mute/Unmute helpers ────────────────────────────────────

local function IsSoundMutedByAny(soundId, db, excludeCat, excludeKey)
    local refs = soundToKeys[soundId]
    if not refs then return false end
    for _, ref in ipairs(refs) do
        if ref.cat ~= excludeCat or ref.key ~= excludeKey then
            local cat = db[ref.cat]
            if cat and cat[ref.key] == true then
                return true
            end
        end
    end
    return false
end

local function ApplySoundState(soundId, muted)
    if muted then
        MuteSoundFile(soundId)
    else
        UnmuteSoundFile(soundId)
    end
end

local function ToggleEntry(catName, entry, shouldMute)
    local db = TFQoLDB.muteSounds
    for _, soundId in ipairs(entry.sounds) do
        if shouldMute then
            ApplySoundState(soundId, true)
        else
            -- Only unmute if no other enabled entry also references this sound
            if not IsSoundMutedByAny(soundId, db, catName, entry.key) then
                ApplySoundState(soundId, false)
            end
        end
    end
end

local function ToggleCustomSound(soundId, shouldMute)
    ApplySoundState(soundId, shouldMute)
end

-- ── Apply all muted sounds from saved state ─────────────────

local function ApplyAllMutedSounds()
    local db = TFQoLDB.muteSounds
    if not db then return end

    -- Preset categories
    for catName, entries in pairs(module.SoundCategories) do
        for _, entry in ipairs(entries) do
            if db[catName] and db[catName][entry.key] == true then
                for _, soundId in ipairs(entry.sounds) do
                    ApplySoundState(soundId, true)
                end
            end
        end
    end

    -- Custom sounds
    if db.customSounds then
        for _, soundId in ipairs(db.customSounds) do
            ApplySoundState(soundId, true)
        end
    end
end

-- ── Public API (used by GUI tab) ────────────────────────────

function module:GetCategories()
    return module.SoundCategories
end

function module:IsEntryMuted(catName, key)
    local db = TFQoLDB.muteSounds
    local cat = db and db[catName]
    if not cat then return false end
    return cat[key] == true
end

function module:SetEntryMuted(catName, key, muted)
    local db = TFQoLDB.muteSounds
    db[catName] = db[catName] or {}
    db[catName][key] = muted or nil

    -- Find the entry and toggle it
    for _, entry in ipairs(module.SoundCategories[catName] or {}) do
        if entry.key == key then
            ToggleEntry(catName, entry, muted)
            return
        end
    end
end

function module:GetCustomSounds()
    local db = TFQoLDB.muteSounds
    return db.customSounds or {}
end

function module:AddCustomSound(soundId)
    soundId = tonumber(soundId)
    if not soundId or soundId <= 0 then return false end

    local db = TFQoLDB.muteSounds
    db.customSounds = db.customSounds or {}

    -- Check for duplicates
    for _, existingId in ipairs(db.customSounds) do
        if existingId == soundId then return false end
    end

    db.customSounds[#db.customSounds + 1] = soundId
    ToggleCustomSound(soundId, true)
    return true
end

function module:RemoveCustomSound(soundId)
    soundId = tonumber(soundId)
    if not soundId then return end

    local db = TFQoLDB.muteSounds
    if not db.customSounds then return end

    for i, existingId in ipairs(db.customSounds) do
        if existingId == soundId then
            table.remove(db.customSounds, i)
            -- Only unmute if no preset also mutes this sound
            if not soundToKeys[soundId] or not IsSoundMutedByAny(soundId, db) then
                ApplySoundState(soundId, false)
            end
            return
        end
    end
end

-- ── Module Lifecycle ────────────────────────────────────────

function module:OnInitialize()
    -- Category tables are initialized via Core.lua defaults
    -- This ensures missing fields are migrated in for existing saves
    local db = TFQoLDB.muteSounds
    for catName, _ in pairs(module.SoundCategories) do
        if not db[catName] then db[catName] = {} end
    end
    if not db.customSounds then db.customSounds = {} end
end

function module:OnEnable()
    ApplyAllMutedSounds()
end

function module:OnDisable()
    -- Unmute everything this module manages, UNCONDITIONALLY. A per-entry
    -- muted-by-other check here is wrong: disable must never leave shared
    -- sounds muted behind.
    local seen = {}
    for _, entries in pairs(module.SoundCategories) do
        for _, entry in ipairs(entries) do
            for _, soundId in ipairs(entry.sounds) do
                if not seen[soundId] then
                    seen[soundId] = true
                    ApplySoundState(soundId, false)
                end
            end
        end
    end

    -- Custom sounds
    local db = TFQoLDB.muteSounds
    if db and db.customSounds then
        for _, soundId in ipairs(db.customSounds) do
            if not seen[soundId] then
                seen[soundId] = true
                ApplySoundState(soundId, false)
            end
        end
    end
end

addon:RegisterModule("MuteSounds", module)
