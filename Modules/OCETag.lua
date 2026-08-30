-- ════════════════════════════════════════════════════════════════
-- Part 8: Module — OCE Tag
-- (Tags OCE realm groups in the Premade Groups browser with a
--  red [OCE] prefix)
-- ════════════════════════════════════════════════════════════════

local _, addon = ...
local module = {}
addon:RegisterModule("OCETag", module)

-- The 12 OCE realms, pre-normalized (lowercase, punctuation stripped)
local OCE_REALMS = {
    amanthul    = true,
    barthilas   = true,
    caelestrasz = true,
    dathremar   = true,
    dreadmaul   = true,
    frostmourne = true,
    gundrak     = true,
    jubeithos   = true,
    khazgoroth  = true,
    nagrand     = true,
    saurfang    = true,
    thaurissan  = true,
}

local OCE_TAG = "|cFFFF4040[OCE]|r "

local moduleEnabled = false

-- ── PRIVATE HELPERS ───────────────────────────────────────────

local function NormalizeRealm(realm)
    return realm:lower():gsub("[%s%p]", "")
end

local function IsOCE(leaderName)
    if not leaderName then return false end
    local realm = leaderName:match("%-(.+)") or GetRealmName()
    return OCE_REALMS[NormalizeRealm(realm)] == true
end

local function OnSearchEntryUpdate(self)
    if not moduleEnabled then return end
    local info = C_LFGList.GetSearchResultInfo(self.resultID)
    if info and IsOCE(info.leaderName) then
        self.ActivityName:SetFormattedText("%s%s", OCE_TAG, self.ActivityName:GetText())
    end
end

-- ── MODULE LIFECYCLE ──────────────────────────────────────────

function module:OnInitialize()
    hooksecurefunc("LFGListSearchEntry_Update", OnSearchEntryUpdate)
end

function module:OnEnable()
    moduleEnabled = true
end

function module:OnDisable()
    moduleEnabled = false
end
