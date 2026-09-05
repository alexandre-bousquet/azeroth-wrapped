-- Visited-zone detail rows.
local _, AW = ...

local UI = AW.UI
local L = AW.L
local Util = AW.Util
local Helpers = UI.DetailHelpers

local function buildZoneRows(summary)
    local rows = {}
    for _, entry in ipairs(Helpers.sortedEntries(summary.zones, "seconds")) do
        local zone = entry.value
        Helpers.appendRow(
            rows,
            zone.name or L.UNKNOWN_ZONE,
            string.format(L.DETAIL_VISITS, zone.visits or 0),
            Util:FormatDuration(zone.seconds)
        )
    end
    return rows
end

UI.DetailBuilders.world = buildZoneRows

