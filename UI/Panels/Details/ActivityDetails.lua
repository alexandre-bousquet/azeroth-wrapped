-- Completed-activity detail rows.
local _, AW = ...

local UI = AW.UI
local L = AW.L
local Util = AW.Util
local Helpers = UI.DetailHelpers

local function buildActivityRows(summary)
    local rows = {}
    local completedActivities = summary.completedActivities or {}
    local history = completedActivities.history or {}
    local activities = {}
    local usesHistory = #history > 0
    local showActivityCharacters = UI:ShouldShowActivityCharacters()

    if usesHistory then
        for index, activity in ipairs(history) do
            activities[#activities + 1] = {
                index = index,
                value = activity,
            }
        end
        table.sort(activities, function(left, right)
            local leftTime = tonumber(left.value.completedAt) or 0
            local rightTime = tonumber(right.value.completedAt) or 0
            if leftTime == rightTime then
                local leftSequence = tonumber(left.value.sequence) or left.index
                local rightSequence = tonumber(right.value.sequence) or right.index
                return leftSequence > rightSequence
            end
            return leftTime > rightTime
        end)
    else
        activities = Helpers.sortedEntries(completedActivities.entries, "completions")
    end

    for _, entry in ipairs(activities) do
        local activity = entry.value
        local category = activity.category or "outdoor"
        if UI.activityFilter == "all" or UI.activityFilter == category then
            local displayName = activity.name or L.UNKNOWN_ACTIVITY
            local categoryLabel = category == "raid" and L.DETAIL_RAID
                or category == "dungeon" and L.DETAIL_DUNGEON
                or L.DETAIL_OUTDOOR
            local kindLabel = L["DETAIL_ACTIVITY_KIND_" .. (activity.kind or "other")]
            local detail

            if category == "dungeon" and activity.kind == "dungeon" then
                local keystoneLevel = tonumber(activity.keystoneLevel)
                local difficultyLabel = keystoneLevel and keystoneLevel > 0
                    and string.format(L.DETAIL_MYTHIC_PLUS, keystoneLevel)
                    or activity.difficultyName
                local runSeconds = tonumber(activity.runSeconds)
                local timerLabel = runSeconds and runSeconds > 0
                    and string.format(L.DETAIL_DUNGEON_TIMER, Util:FormatTimer(runSeconds))
                    or nil
                local keyResult
                if keystoneLevel and keystoneLevel > 0 then
                    local upgradeLevels = tonumber(activity.keystoneUpgradeLevels) or 0
                    if upgradeLevels > 0 then
                        keyResult = string.format(L.DETAIL_KEY_UPGRADE, upgradeLevels)
                    elseif activity.onTime then
                        keyResult = L.DETAIL_KEY_IN_TIME
                    else
                        keyResult = L.DETAIL_KEY_DEPLETED
                    end
                end
                if timerLabel and keyResult then
                    timerLabel = string.format(L.DETAIL_DUNGEON_TIMER_RESULT, timerLabel, keyResult)
                    keyResult = nil
                end
                detail = Helpers.joinDetails(categoryLabel, difficultyLabel, timerLabel, keyResult)
            elseif category == "outdoor" and (activity.kind == "delve" or activity.kind == "prey") then
                local delveTier = tonumber(activity.delveTier)
                local difficultyLabel = delveTier and delveTier > 0
                    and string.format(L.DETAIL_DELVE_TIER, delveTier)
                    or (activity.kind == "delve" and L.DETAIL_DELVE_TIER_UNKNOWN)
                    or activity.difficultyName
                local runSeconds = tonumber(activity.runSeconds)
                local timerLabel = runSeconds and runSeconds > 0
                    and string.format(L.DETAIL_ACTIVITY_TIMER, Util:FormatTimer(runSeconds))
                    or nil
                local instanceName = activity.instanceName
                if activity.kind == "delve" and instanceName
                    and Helpers.normalizeSearchText(activity.name) == Helpers.normalizeSearchText(activity.difficultyName)
                then
                    displayName = instanceName
                end
                if activity.kind == "delve"
                    and Helpers.normalizeSearchText(instanceName) == Helpers.normalizeSearchText(displayName)
                then
                    instanceName = nil
                end
                detail = Helpers.joinDetails(kindLabel, difficultyLabel, timerLabel, instanceName)
            else
                detail = Helpers.joinDetails(categoryLabel, kindLabel, activity.instanceName, activity.difficultyName)
            end

            local activityCharacter = activity.characterKey
                and AW.Database.db.characters
                and AW.Database.db.characters[activity.characterKey]

            local completionCount = tonumber(activity.completions) or 0
            local isSingleLegacyCompletion = activity.legacyAggregate and completionCount == 1
            local completionLabel = activity.completedAt
                and (not activity.legacyAggregate or isSingleLegacyCompletion)
                and date(L.ACTIVITY_DATE_FORMAT, activity.completedAt)
                or string.format(L.DETAIL_COMPLETIONS, completionCount)

            local row = Helpers.appendRow(
                rows,
                displayName,
                detail,
                completionLabel
            )
            if showActivityCharacters and activityCharacter then
                row.characterName = activityCharacter.name or L.UNKNOWN_PLAYER
                row.characterClassFile = activityCharacter.classFile
            end
        end
    end

    return rows
end

UI.DetailBuilders.activities = buildActivityRows

