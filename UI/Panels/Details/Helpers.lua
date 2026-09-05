-- Shared row-building utilities for detail modules.
local _, AW = ...

local UI = AW.UI
local L = AW.L
local Util = AW.Util

local function appendRow(rows, label, detail, value, waypoint, raiderIOURL, warcraftLogsURL, classFile)
    local row = {
        label = label or L.DETAIL_UNKNOWN,
        detail = detail or "",
        value = value or "",
        waypoint = waypoint,
        raiderIOURL = raiderIOURL,
        warcraftLogsURL = warcraftLogsURL,
        classFile = classFile,
    }
    rows[#rows + 1] = row
    return row
end

local function urlEncode(value)
    return (string.gsub(tostring(value or ""), "([^%w%-_%.~])", function(character)
        return string.format("%%%02X", string.byte(character))
    end))
end

local function realmSlug(realm)
    realm = tostring(realm or "")
    realm = string.gsub(realm, "(%l)(%u)", "%1-%2")
    realm = string.gsub(realm, "(%a)(%d)", "%1-%2")
    realm = string.gsub(realm, "’", "")
    realm = string.gsub(realm, "'", "")
    realm = string.gsub(realm, "[()]", "")
    realm = string.gsub(realm, "%s+", "-")
    return urlEncode(Util:UTF8Lower(realm))
end

local function buildRaiderIOURL(name, realm, region)
    if not name or name == "" or not realm or realm == "" then
        return nil
    end

    return string.format(
        "https://raider.io/characters/%s/%s/%s",
        urlEncode(string.lower(region or Util:GetRegionSlug())),
        realmSlug(realm),
        urlEncode(name)
    )
end

local function buildWarcraftLogsURL(name, realm, region)
    if not name or name == "" or not realm or realm == "" then
        return nil
    end

    return string.format(
        "https://www.warcraftlogs.com/character/%s/%s/%s",
        urlEncode(string.lower(region or Util:GetRegionSlug())),
        realmSlug(realm),
        urlEncode(name)
    )
end

local function getRaiderIOProfile(companion)
    local score = tonumber(companion.mythicPlusScore)
    local region = companion.region or Util:GetRegionSlug()
    local realm = companion.realm

    if RaiderIO and type(RaiderIO.GetProfile) == "function" and companion.name and realm then
        local ok, profile = pcall(RaiderIO.GetProfile, companion.name, realm, region)
        if ok and type(profile) == "table" then
            local mythicProfile = profile.mythicKeystoneProfile
            if type(mythicProfile) == "table" and mythicProfile.hasRenderableData ~= false then
                score = tonumber(mythicProfile.currentScore) or score
            end
            region = profile.region or region
            realm = profile.realm or realm
        end
    end

    if score and score <= 0 then
        score = nil
    end
    return score, region, realm
end

local SEARCH_REPLACEMENTS = {
    ["À"] = "a", ["Â"] = "a", ["Ä"] = "a", ["à"] = "a", ["â"] = "a", ["ä"] = "a",
    ["Ç"] = "c", ["ç"] = "c",
    ["É"] = "e", ["È"] = "e", ["Ê"] = "e", ["Ë"] = "e",
    ["é"] = "e", ["è"] = "e", ["ê"] = "e", ["ë"] = "e",
    ["Î"] = "i", ["Ï"] = "i", ["î"] = "i", ["ï"] = "i",
    ["Ô"] = "o", ["Ö"] = "o", ["Œ"] = "oe", ["ô"] = "o", ["ö"] = "o", ["œ"] = "oe",
    ["Ù"] = "u", ["Û"] = "u", ["Ü"] = "u", ["ù"] = "u", ["û"] = "u", ["ü"] = "u",
    ["Ÿ"] = "y", ["ÿ"] = "y",
}

local function normalizeSearchText(value)
    value = tostring(value or "")
    for character, replacement in pairs(SEARCH_REPLACEMENTS) do
        value = string.gsub(value, character, replacement)
    end
    return Util:UTF8Lower(value)
end

local function sortedEntries(entries, field, scorer)
    local result = {}

    for key, value in pairs(entries or {}) do
        local score
        if scorer then
            score = scorer(value, key)
        elseif type(value) == "table" then
            score = tonumber(value[field]) or 0
        else
            score = tonumber(value) or 0
        end

        result[#result + 1] = {
            key = key,
            value = value,
            score = tonumber(score) or 0,
        }
    end

    table.sort(result, function(left, right)
        if left.score == right.score then
            local leftName = type(left.value) == "table" and left.value.name or left.key
            local rightName = type(right.value) == "table" and right.value.name or right.key
            return tostring(leftName or "") < tostring(rightName or "")
        end
        return left.score > right.score
    end)

    return result
end

local function joinDetails(...)
    local parts = {}

    for index = 1, select("#", ...) do
        local value = select(index, ...)
        if value and value ~= "" then
            parts[#parts + 1] = tostring(value)
        end
    end

    return table.concat(parts, "  •  ")
end

UI.DetailHelpers = {
    appendRow = appendRow,
    buildRaiderIOURL = buildRaiderIOURL,
    buildWarcraftLogsURL = buildWarcraftLogsURL,
    getRaiderIOProfile = getRaiderIOProfile,
    joinDetails = joinDetails,
    normalizeSearchText = normalizeSearchText,
    sortedEntries = sortedEntries,
}
UI.DetailBuilders = UI.DetailBuilders or {}

