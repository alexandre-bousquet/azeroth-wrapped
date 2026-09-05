-- Play-time detail rows.
local _, AW = ...

local UI = AW.UI
local L = AW.L
local Util = AW.Util
local Helpers = UI.DetailHelpers

local function buildTimeRows(summary)
    local rows = {}
    Helpers.appendRow(rows, L.DETAIL_ONLINE_TIME, "", Util:FormatDuration(summary.onlineSeconds))
    Helpers.appendRow(rows, L.DETAIL_ACTIVE_TIME, "", Util:FormatDuration(summary.activeSeconds))
    Helpers.appendRow(rows, L.DETAIL_AFK_TIME, "", Util:FormatDuration(summary.afkSeconds))
    Helpers.appendRow(rows, L.DETAIL_SESSIONS, "", tostring(summary.sessionCount or 0))
    Helpers.appendRow(rows, L.DETAIL_LONGEST_SESSION, "", Util:FormatDuration(summary.longestSession))
    Helpers.appendRow(rows, L.DETAIL_ACTIVE_DAYS, "", tostring(summary.daysPlayed or 0))
    return rows
end

UI.DetailBuilders.time = buildTimeRows

