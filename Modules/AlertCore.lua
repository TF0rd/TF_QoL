-- ════════════════════════════════════════════════════════════════
-- Shared: Indicator Alert Factory (AlertCore)
-- (Builds Potion/Lust-style floating text alerts: frame setup,
--  slug-aware font, saved-position anchoring, instance-filter ladder,
--  rescan state machine, test mode, and sound-on-transition)
-- ════════════════════════════════════════════════════════════════

local _, addon = ...

-- ── Shared Font Helper ───────────────────────────────────────

-- Applies a module's saved font family/size to a FontString, honoring the
-- global slug-rendering flag. Single copy shared by all alert modules.
function addon:ApplyAlertFont(fontString, db)
    if not fontString or not db then return end
    local slug = TFQoLDB and TFQoLDB.global and TFQoLDB.global.slugRendering == true
    local flags = slug and "OUTLINE,SLUG" or "OUTLINE"
    fontString:SetFont(self:ResolveFont(db.fontFamily), db.fontSize, flags)
end

-- ── Secret-Value Probe ───────────────────────────────────────

-- True when `v` is a secret value (cooldown/aura data is secret-wrapped in
-- M+, raid, and PvP instances); false when secrets are unsupported or the
-- value is readable. Guards every comparison so restricted reads skip the
-- scan instead of throwing.
function addon:IsSecretValue(v)
    return issecretvalue and issecretvalue(v) or false
end

-- ── Private Helpers ──────────────────────────────────────────

-- Plays the module's configured alert sound, if any.
local function PlayAlertSound(db)
    if not db then return end
    if not (db.playSound and db.soundName and db.soundName ~= "None") then return end
    local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
    if not LSM then return end
    local path = LSM:Fetch("sound", db.soundName)
    if path then PlaySoundFile(path, "Master") end
end

-- ── Indicator Alert Factory ──────────────────────────────────

-- Creates a floating text-alert module. `opts` fields:
--   dbKey             TFQoLDB key with font/position/sound/visibility settings
--   frameName         global frame name (e.g. "TFQoL_PotionAlertFrame")
--   text              indicator text shown when the alert fires
--   textColor         { r, g, b } (defaults to neon green #1EFF00)
--   scanFn            () -> true (show) / false (hide) / nil (secret-locked, keep state)
--   shouldBeActiveFn  (event) -> false to force-hide, anything else to continue (optional)
--   rescanEventFilter (event, unit) -> "rescan" / "evaluate" / "ignore" / nil (= "evaluate")
--   events            event names registered on enable
--   unitEvents        { { event = ..., unit = ... } } registered via RegisterUnitEvent
--   defaultPoint      optional creation-time anchor { point, relativePoint, x, y };
--                     indicator modules omit this and rely on the Core.lua DB
--                     defaults applied through UpdatePosition on enable.
function addon:CreateIndicatorAlert(name, opts)
    local module = {}
    local color = opts.textColor or { 0.1176, 1.0, 0.0 }

    -- ── Local state ──────────────────────────────────────────
    local frame = CreateFrame("Frame", opts.frameName, UIParent)
    frame:SetSize(16, 16)
    frame:Hide()

    frame.text = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    frame.text:SetPoint("CENTER")
    frame.text:SetTextColor(color[1], color[2], color[3], 1.0)
    frame.text:SetText(opts.text or name)
    frame.text:SetShadowOffset(0, 0)
    frame.text:SetShadowColor(0, 0, 0, 0)

    -- No initial SetPoint here: position comes from TFQoLDB via UpdatePosition
    -- on enable (Core.lua holds the defaults), so there is exactly one source
    -- of truth for default positions.
    if opts.defaultPoint then
        frame:SetPoint(opts.defaultPoint.point or "CENTER",
            UIParent, opts.defaultPoint.relativePoint or "CENTER",
            opts.defaultPoint.x or 0, opts.defaultPoint.y or 0)
    end

    local eventFrame = CreateFrame("Frame")
    local rescanActive = false
    local testMode     = false
    local enabled      = false

    -- ── Core logic ───────────────────────────────────────────

    -- Runs scanFn and shows/hides the frame, playing the alert sound on a
    -- hidden-to-shown transition. A nil result means secret-locked: keep state.
    local function Scan()
        if testMode then return end
        local shouldShow = opts.scanFn()
        if shouldShow == nil then return end
        if shouldShow then
            if not frame:IsVisible() then
                PlayAlertSound(TFQoLDB[opts.dbKey])
            end
            frame:Show()
        else
            frame:Hide()
        end
    end

    -- Instance-type / combat visibility ladder shared by all indicator alerts.
    local function ShouldBeActive(event)
        local db = TFQoLDB[opts.dbKey]
        if not db then return false end
        if opts.shouldBeActiveFn and opts.shouldBeActiveFn(event) == false then return false end

        local inCombat = InCombatLockdown() or (event == "PLAYER_REGEN_DISABLED")
        if db.onlyCombat == true and not inCombat then return false end

        local inInstance, instanceType = IsInInstance()
        if instanceType == "party" and not (db.showInDungeons == true) then return false end
        if instanceType == "raid" and not (db.showInRaids == true) then return false end
        if (not inInstance or instanceType == "scenario") and not (db.showInOpenWorld == true) then return false end

        return true
    end

    local function EvaluateState(event)
        if testMode then return end
        if ShouldBeActive(event) then
            rescanActive = true
            Scan()
        else
            rescanActive = false
            frame:Hide()
        end
    end

    -- ── Event handling ───────────────────────────────────────

    local function OnEvent(_, event, unit)
        local disposition
        if opts.rescanEventFilter then
            disposition = opts.rescanEventFilter(event, unit)
        end
        if disposition == "rescan" then
            if rescanActive then Scan() end
        elseif disposition == "evaluate" or disposition == nil then
            EvaluateState(event)
        end
        -- "ignore" (or any other value) drops the event entirely.
    end

    -- ── Font / position ──────────────────────────────────────

    function module:UpdateFont()
        addon:ApplyAlertFont(frame.text, TFQoLDB[opts.dbKey])
    end

    function module:UpdatePosition()
        addon:ApplyPosition(frame, TFQoLDB[opts.dbKey])
    end

    -- ── Test mode ────────────────────────────────────────────

    function module:SetTestMode(on)
        testMode = on and true or false
        if testMode then
            self:UpdatePosition()
            frame:Show()
        else
            frame:Hide()
            EvaluateState()
        end
    end

    function module:IsTestMode()
        return testMode
    end

    function module:ForceCheck()
        if not enabled then return end
        EvaluateState()
    end

    -- ── Module lifecycle ─────────────────────────────────────

    function module:OnEnable()
        self:UpdateFont()
        self:UpdatePosition()
        for _, ev in ipairs(opts.events or {}) do
            eventFrame:RegisterEvent(ev)
        end
        for _, ue in ipairs(opts.unitEvents or {}) do
            eventFrame:RegisterUnitEvent(ue.event, ue.unit)
        end
        eventFrame:SetScript("OnEvent", OnEvent)
        enabled = true
        EvaluateState()
    end

    function module:OnDisable()
        enabled = false
        eventFrame:UnregisterAllEvents()
        frame:Hide()
        rescanActive = false
        testMode = false
    end

    return module
end
