-- ════════════════════════════════════════════════════════════════
-- Part 6: Module — CVar Browser
-- (Tracks modified CVars by hooking SetCVar / ConsoleExec; commits
--  traces to SavedVariables once the DB is available)
-- ════════════════════════════════════════════════════════════════

local _, addon = ...
local module = {}

-- Localize frequently used globals
local C_CVar_GetCVar     = C_CVar.GetCVar
local C_CVar_GetCVarInfo = C_CVar.GetCVarInfo

-- ── CVar Modification Tracking ────────────────────────────────
-- Hooks are set at file load (before SavedVariables), traces stored in TempTraces
-- until OnInitialize commits them to the DB.

local SVLoaded   = false
local TempTraces = {}   -- [cvar:lower()] = { source = "path:line", value = "val" }

local function CVarExists(cvar)
    local v = C_CVar_GetCVarInfo(cvar)
    return v ~= nil and v ~= ""
end

local function TraceCVar(cvar, value, ...)
    if not CVarExists(cvar) then return end

    local trace = debugstack(2)
    local source, lineNum = trace:match('"@([^"]+)"%]:(%d+)')
    if not source then
        source, lineNum = trace:match("in function <([^:%[>]+):(%d+)>")
        if not source then
            source  = trace
            lineNum = "(unhandled exception)"
        end
    end

    -- Ignore hooks originating from TF_QoL itself or WoW's CvarUtil wrappers
    if source and not (
        source:lower():find("[\\\\/]tf_qol[\\\\/]")
        or source:lower():find("[_\\\\/]sharedxmlbase[\\\\/]cvarutil%.lua")
        or source:lower():find("[_\\\\/]sharedxml[\\\\/]cvarutil%.lua")
        or source:lower():find("[_\\\\/]sharedxml[\\\\/]classiccvarutil%.lua")
    ) then
        local realValue = C_CVar_GetCVar(cvar)
        local entry     = source .. ":" .. lineNum
        if SVLoaded then
            TFQoLDB.cvarBrowser.modifiedCVars[cvar:lower()] = entry
        else
            TempTraces[cvar:lower()] = { source = entry, value = realValue }
        end
    end
end

-- Hook both the legacy global and the C_ namespace version
hooksecurefunc("SetCVar", TraceCVar)
if C_CVar and C_CVar.SetCVar then
    hooksecurefunc(C_CVar, "SetCVar", TraceCVar)
end
hooksecurefunc("ConsoleExec", function(msg)
    local cmd, cvar, value = msg:match("^(%S+)%s+(%S+)%s*(%S*)")
    if cmd then
        if cmd:lower() == "set" then
            TraceCVar(cvar, value)
        else
            TraceCVar(cmd, cvar)
        end
    end
end)

-- ── MODULE LIFECYCLE ──────────────────────────────────────────

function module:OnInitialize()
    SVLoaded = true
    -- Commit any pre-load traces to the DB (only if value hasn't since been overwritten)
    for cvar, trace in pairs(TempTraces) do
        local currentValue = C_CVar_GetCVar(cvar)
        if trace.value == currentValue then
            TFQoLDB.cvarBrowser.modifiedCVars[cvar] = trace.source
        end
    end
end

function module:OnEnable()  end
function module:OnDisable() end

-- ── Public API ────────────────────────────────────────────────
-- Used by the GUI tab

function module:GetModifiedCVars()
    if TFQoLDB and TFQoLDB.cvarBrowser then
        return TFQoLDB.cvarBrowser.modifiedCVars
    end
    return {}
end

addon:RegisterModule("CVarBrowser", module)
