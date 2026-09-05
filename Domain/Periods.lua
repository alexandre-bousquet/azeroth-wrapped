-- Date-range rules used by summaries and reset operations.
local _, AW = ...

AW.Periods = {}
local Periods = AW.Periods
local Util = AW.Util

Periods.order = { "WEEK", "MONTH", "SEASON", "YEAR", "ALL" }

function Periods:IsValid(periodKey)
    for _, knownPeriodKey in ipairs(self.order) do
        if periodKey == knownPeriodKey then
            return true
        end
    end

    return false
end

local function midnight(value)
    return time({
        year = value.year,
        month = value.month,
        day = value.day,
        hour = 0,
        min = 0,
        sec = 0,
    })
end

function Periods:RefreshSeason()
    local seasonID

    if C_MythicPlus and C_MythicPlus.GetCurrentSeason then
        local ok, value = pcall(C_MythicPlus.GetCurrentSeason)
        if ok and value and value > 0 then
            seasonID = value
        end
    end

    local key = seasonID and tostring(seasonID) or "current"
    local seasons = AW.Database.db.meta.seasons

    if not seasons[key] then
        seasons[key] = {
            id = seasonID,
            firstSeenAt = Util:Now(),
        }
    end

    AW.Database.db.meta.currentSeasonKey = key
    return key, seasons[key]
end

function Periods:GetRange(periodKey, timestamp)
    local now = timestamp or Util:Now()
    local current = date("*t", now)

    if periodKey == "WEEK" then
        local mondayOffset = (current.wday + 5) % 7
        return midnight(current) - (mondayOffset * 86400), now
    elseif periodKey == "MONTH" then
        return time({ year = current.year, month = current.month, day = 1, hour = 0 }), now
    elseif periodKey == "YEAR" then
        return time({ year = current.year, month = 1, day = 1, hour = 0 }), now
    elseif periodKey == "SEASON" then
        local seasonKey = AW.Database.db.meta.currentSeasonKey
        local season = seasonKey and AW.Database.db.meta.seasons[seasonKey]
        local firstSeenAt = (season and season.firstSeenAt) or AW.Database.db.meta.createdAt
        return Util:StartOfDay(firstSeenAt), now
    end

    return 0, now
end

function Periods:GetLabel(periodKey)
    local L = AW.L

    if periodKey == "WEEK" then
        return L.PERIOD_WEEK
    elseif periodKey == "MONTH" then
        return L.PERIOD_MONTH
    elseif periodKey == "YEAR" then
        return L.PERIOD_YEAR
    elseif periodKey == "ALL" then
        return L.PERIOD_ALL
    elseif periodKey == "SEASON" then
        return L.SEASON_FALLBACK
    end

    return periodKey
end

function Periods:GetResetLabel(periodKey)
    if periodKey == "ALL" then
        return AW.L.RESET_PERIOD_ALL
    end
    return self:GetLabel(periodKey)
end
