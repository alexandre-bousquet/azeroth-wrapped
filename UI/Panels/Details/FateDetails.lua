-- Death-history detail rows.
local _, AW = ...

local UI = AW.UI
local L = AW.L
local Util = AW.Util
local Helpers = UI.DetailHelpers

local function buildDeathRows(summary)
    local rows = {}
    local details = {}

    for _, death in ipairs((summary.deaths and summary.deaths.details) or {}) do
        details[#details + 1] = death
    end

    table.sort(details, function(first, second)
        return (tonumber(first.timestamp) or 0) > (tonumber(second.timestamp) or 0)
    end)

    local environmentalLabels = {
        DROWNING = L.DEATH_CAUSE_DROWNING,
        FALLING = L.DEATH_CAUSE_FALL,
        FATIGUE = L.DEATH_CAUSE_FATIGUE,
        FIRE = L.DEATH_CAUSE_FIRE,
        LAVA = L.DEATH_CAUSE_LAVA,
        SLIME = L.DEATH_CAUSE_SLIME,
    }

    local function formatDamage(amount)
        amount = tonumber(amount)
        if not amount or amount <= 0 then
            return nil
        end
        local formatted = BreakUpLargeNumbers and BreakUpLargeNumbers(math.floor(amount)) or tostring(math.floor(amount))
        return string.format(L.DEATH_DAMAGE, formatted)
    end

    for _, death in ipairs(details) do
        local category = death.category
        local label
        local sourceName = AW.Database.db.settings.anonymousShare and nil or death.sourceName
        local spellName = death.spellName
        local bossContext

        if category == "boss" then
            label = string.format(L.DEATH_CAUSE_BOSS, death.encounterName or sourceName or L.UNKNOWN_BOSS)
            if sourceName == death.encounterName then
                sourceName = nil
            end
        elseif category == "fall" then
            label = L.DEATH_CAUSE_FALL
        elseif category == "environment" then
            label = environmentalLabels[death.environmentalType] or L.DEATH_CAUSE_ENVIRONMENT
        elseif category == "attack" then
            if not spellName and death.event == "SWING_DAMAGE" then
                spellName = L.DEATH_MELEE_ATTACK
            elseif not spellName and death.event == "RANGE_DAMAGE" then
                spellName = L.DEATH_RANGED_ATTACK
            end
            label = string.format(L.DEATH_CAUSE_ATTACK, spellName or L.DEATH_UNKNOWN_ATTACK)
            spellName = nil
        else
            label = L.DEATH_CAUSE_UNKNOWN
        end

        if category ~= "boss" and death.encounterName then
            bossContext = string.format(L.DEATH_CAUSE_BOSS, death.encounterName)
        end

        Helpers.appendRow(
            rows,
            label,
            Helpers.joinDetails(death.locationName, bossContext, spellName, sourceName, formatDamage(death.amount)),
            death.timestamp and date(L.DEATH_DATE_FORMAT, death.timestamp) or ""
        )
    end

    local missingDetails = math.max(0, ((summary.deaths and summary.deaths.total) or 0) - #details)
    if #details > 0 and missingDetails > 0 then
        Helpers.appendRow(
            rows,
            Util:FormatCount(missingDetails, L.DEATH_WITHOUT_DETAILS_ONE, L.DEATH_WITHOUT_DETAILS),
            "",
            ""
        )
        return rows
    elseif #details > 0 then
        return rows
    end

    for _, entry in ipairs(Helpers.sortedEntries(summary.deaths and summary.deaths.locations, "deaths")) do
        local location = entry.value
        Helpers.appendRow(
            rows,
            location.name or L.UNKNOWN_ZONE,
            "",
            Util:FormatCount(location.deaths, L.DETAIL_DEATHS_ONE, L.DETAIL_DEATHS)
        )
    end
    return rows
end

UI.DetailBuilders.fate = buildDeathRows

