-- Companion detail rows and profile links.
local _, AW = ...

local UI = AW.UI
local L = AW.L
local Util = AW.Util
local Helpers = UI.DetailHelpers

local function buildCompanionRows(summary)
    local rows = {}
    local private = AW.Database.db.settings.anonymousShare
    local searchText = UI.companionSearchText or ""
    local playerCompanions = {}

    for key, companion in pairs(summary.groupmates or {}) do
        local guid = type(companion) == "table" and companion.guid or nil
        if type(companion) == "table"
            and companion.isPlayer ~= false
            and (type(guid) ~= "string" or string.match(guid, "^Player%-"))
        then
            playerCompanions[key] = companion
        end
    end

    for index, entry in ipairs(Helpers.sortedEntries(playerCompanions, "seconds")) do
        local companion = entry.value
        local name = companion.name or L.UNKNOWN_PLAYER
        local classFile = companion.classFile
        local className = Util:GetClassName(classFile, companion.className)
        local realm = companion.realm
        local guildName = companion.guildName
        local score, region, profileRealm = Helpers.getRaiderIOProfile(companion)
        local raiderIOURL = Helpers.buildRaiderIOURL(companion.name, profileRealm, region)
        local warcraftLogsURL = Helpers.buildWarcraftLogsURL(companion.name, profileRealm, region)

        if private then
            name = string.format(L.PRIVATE_PLAYER_NUMBER, index)
            realm = nil
            guildName = nil
            score = nil
            raiderIOURL = nil
            warcraftLogsURL = nil
        end

        local guildText = guildName and string.format(L.DETAIL_COMPANION_GUILD, guildName)
        local scoreText = score and string.format(L.DETAIL_COMPANION_SCORE, math.floor(score + 0.5))
        local displayName = className and string.format(L.DETAIL_COMPANION_NAME_CLASS, name, className) or name
        local searchableText = Helpers.normalizeSearchText(table.concat({
            name or "",
            className or "",
            classFile or "",
            realm or "",
            guildName or "",
        }, " "))

        if searchText == "" or string.find(searchableText, searchText, 1, true) then
            Helpers.appendRow(
                rows,
                displayName,
                Helpers.joinDetails(
                    realm,
                    guildText,
                    scoreText
                ),
                Util:FormatMinutes(companion.seconds),
                nil,
                raiderIOURL,
                warcraftLogsURL,
                classFile
            )
        end
    end

    return rows
end

UI.DetailBuilders.companion = buildCompanionRows

