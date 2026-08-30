-- ════════════════════════════════════════════════════════════════
-- Part 7: Module — Group Joined Reminder
-- (Prints a chat message when joining a Mythic+ or Mythic group
--  via the Premade Groups finder)
-- ════════════════════════════════════════════════════════════════

local _, addon = ...
local module = {}
addon:RegisterModule("GroupJoinedReminder", module)

local moduleEnabled = false
local pendingGroupName = nil

local frame = CreateFrame("Frame")

-- ── PRIVATE HELPERS ───────────────────────────────────────────

local function CheckAndPrint()
    local entryData = C_LFGList.GetActiveEntryInfo()
    if not entryData then return end

    local activityId = entryData.activityIDs[1]
    if not activityId then return end

    local activityInfo = C_LFGList.GetActivityInfoTable(activityId)
    if not activityInfo then return end
    if not activityInfo.isMythicPlusActivity and not activityInfo.isMythicActivity then return end

    local msg = activityInfo.fullName
    if pendingGroupName and pendingGroupName ~= "" then
        msg = msg .. " " .. pendingGroupName
    end
    print("|cffcba6f7[TF QoL]|r Joined: " .. msg)
end

-- ── EVENT HANDLING ────────────────────────────────────────────

frame:SetScript("OnEvent", function(self, event, ...)
    if not moduleEnabled then return end

    if event == "GROUP_LEFT" then
        pendingGroupName = nil

    elseif event == "LFG_LIST_JOINED_GROUP" then
        local _, groupName = ...
        pendingGroupName = groupName
        CheckAndPrint()

    elseif event == "LFG_LIST_ACTIVE_ENTRY_UPDATE" then
        local created = ...
        if created then
            CheckAndPrint()
        end
    end
end)

-- ── MODULE LIFECYCLE ──────────────────────────────────────────

function module:OnEnable()
    moduleEnabled = true
    frame:RegisterEvent("GROUP_LEFT")
    frame:RegisterEvent("LFG_LIST_JOINED_GROUP")
    frame:RegisterEvent("LFG_LIST_ACTIVE_ENTRY_UPDATE")
end

function module:OnDisable()
    moduleEnabled = false
    frame:UnregisterAllEvents()
end
