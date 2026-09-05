-- Read-only aggregation of persisted tracking data for presentation.
local _, AW = ...

AW.Summary = {}
local Summary = AW.Summary
local Util = AW.Util

local NUMERIC_FIELDS = {
    seconds = true,
    activeSeconds = true,
    afkSeconds = true,
    deaths = true,
    visits = true,
    interactions = true,
    kills = true,
    completions = true,
    net = true,
    earned = true,
    spent = true,
    changes = true,
    sessionCount = true,
}

local function hasCharacterFilter(characterFilter)
    return type(characterFilter) == "table"
end

local function includesCharacter(characterFilter, characterKey)
    return not hasCharacterFilter(characterFilter) or characterFilter[characterKey] == true
end

local function mergeStructured(target, source)
    for key, value in pairs(source or {}) do
        Util:AddStructuredMetric(target, key, value, NUMERIC_FIELDS)
    end
end

local function mergeCompletedActivities(target, source)
    for key, activity in pairs(source or {}) do
        if type(activity) == "table" then
            local destination = target[key]
            if not destination then
                destination = { completions = 0 }
                target[key] = destination
            end

            destination.completions = (destination.completions or 0) + (tonumber(activity.completions) or 0)

            local bestRunSeconds = tonumber(activity.bestRunSeconds) or tonumber(activity.runSeconds)
            if bestRunSeconds and bestRunSeconds > 0
                and (not destination.bestRunSeconds or bestRunSeconds < destination.bestRunSeconds)
            then
                destination.bestRunSeconds = bestRunSeconds
            end

            local sourceCompletedAt = tonumber(activity.lastCompletedAt) or 0
            local destinationCompletedAt = tonumber(destination.lastCompletedAt) or 0
            if destination.name == nil or sourceCompletedAt >= destinationCompletedAt then
                for field, value in pairs(activity) do
                    if field ~= "completions" and field ~= "bestRunSeconds" then
                        destination[field] = value
                    end
                end
            end
        end
    end
end

local function mergeActivityHistory(target, source)
    for _, activity in ipairs(source or {}) do
        if type(activity) == "table" then
            local snapshot = {}
            for field, value in pairs(activity) do
                snapshot[field] = value
            end
            target[#target + 1] = snapshot
        end
    end
end

local function findLatestCompletedActivity(completedActivities)
    local latest
    local latestTime = -1
    local latestSequence = -1

    for _, activity in ipairs((completedActivities and completedActivities.history) or {}) do
        local completedAt = tonumber(activity.completedAt) or 0
        local sequence = tonumber(activity.sequence) or 0
        if completedAt > latestTime or (completedAt == latestTime and sequence > latestSequence) then
            latest = activity
            latestTime = completedAt
            latestSequence = sequence
        end
    end

    if latest then
        return latest
    end

    for _, activity in pairs((completedActivities and completedActivities.entries) or {}) do
        local completedAt = tonumber(activity.lastCompletedAt) or 0
        if not latest or completedAt > latestTime then
            latest = activity
            latestTime = completedAt
        end
    end

    return latest
end

local function mergeZones(target, source)
    for sourceKey, zone in pairs(source or {}) do
        local name = type(zone) == "table" and zone.name or nil
        local key = name and name ~= "" and name or tostring(sourceKey)
        local destination = target[key]
        if not destination then
            destination = { seconds = 0, visits = 0 }
            target[key] = destination
        end

        destination.seconds = destination.seconds + (tonumber(zone.seconds) or 0)
        destination.visits = destination.visits + (tonumber(zone.visits) or 0)
        destination.name = name or destination.name

        if zone.instanceID or not destination.mapID then
            destination.instanceID = zone.instanceID or destination.instanceID
            destination.instanceType = zone.instanceType or destination.instanceType
            destination.mapID = zone.mapID or destination.mapID
        end
    end
end

local function mergeGroupmates(target, source)
    for key, groupmate in pairs(source or {}) do
        local guid = type(groupmate) == "table" and groupmate.guid or nil
        local isPlayer = type(groupmate) == "table"
            and groupmate.isPlayer ~= false
            and (type(guid) ~= "string" or string.match(guid, "^Player%-") ~= nil)
        if isPlayer then
            local destination = target[key]
            if not destination then
                destination = { seconds = 0, profileUpdatedAt = 0 }
                target[key] = destination
            end

            destination.seconds = destination.seconds + (tonumber(groupmate.seconds) or 0)

            local sourceUpdatedAt = tonumber(groupmate.profileUpdatedAt) or 0
            if not destination.name or sourceUpdatedAt >= (tonumber(destination.profileUpdatedAt) or 0) then
                destination.guid = groupmate.guid or destination.guid
                destination.name = groupmate.name or destination.name
                destination.realm = groupmate.realm or destination.realm
                destination.fullName = groupmate.fullName or destination.fullName
                destination.className = groupmate.className or destination.className
                destination.classFile = groupmate.classFile or destination.classFile
                destination.guildName = groupmate.guildName or destination.guildName
                destination.mythicPlusScore = groupmate.mythicPlusScore or destination.mythicPlusScore
                destination.region = groupmate.region or destination.region
                destination.isPlayer = true
                destination.profileUpdatedAt = sourceUpdatedAt
            end
        end
    end
end

local function mergeNPCs(target, source)
    for key, npc in pairs(source or {}) do
        local destination = target[key]
        if not destination then
            destination = { interactions = 0, services = {} }
            target[key] = destination
        end

        destination.interactions = (destination.interactions or 0) + (tonumber(npc.interactions) or 0)
        destination.services = type(destination.services) == "table" and destination.services or {}
        for service, available in pairs(npc.services or {}) do
            if available then
                destination.services[service] = true
            end
        end
        destination.isMount = npc.isMount or destination.isMount
        destination.isSummoned = npc.isSummoned or destination.isSummoned
            or Util:IsKnownSummonedNPC(npc.npcID)

        local destinationSeenAt = tonumber(destination.lastSeenAt) or 0
        local sourceSeenAt = tonumber(npc.lastSeenAt) or 0
        if not destination.name or sourceSeenAt >= destinationSeenAt then
            destination.name = npc.name or destination.name
            destination.guid = npc.guid or destination.guid
            destination.npcID = npc.npcID or destination.npcID
            destination.title = npc.title or destination.title
            destination.mapID = npc.mapID or destination.mapID
            destination.mapName = npc.mapName or destination.mapName
            destination.zoneName = npc.zoneName or destination.zoneName
            destination.lastSeenAt = npc.lastSeenAt or destination.lastSeenAt
        end

        local excludesPosition = destination.isMount or destination.isSummoned
            or Util:IsKnownSummonedNPC(destination.npcID)
        if excludesPosition then
            destination.x = nil
            destination.y = nil
            destination.positionSource = nil
            destination.positionSeenAt = nil
        end

        local sourceHasPosition = not excludesPosition and npc.x ~= nil and npc.y ~= nil
        local destinationHasPosition = destination.x ~= nil and destination.y ~= nil
        local sourceIsExact = npc.positionSource == "npc"
        local destinationIsExact = destination.positionSource == "npc"
        local sourcePositionSeenAt = tonumber(npc.positionSeenAt) or sourceSeenAt
        local destinationPositionSeenAt = tonumber(destination.positionSeenAt) or destinationSeenAt
        local shouldReplacePosition = sourceHasPosition and (
            not destinationHasPosition
            or (sourceIsExact and not destinationIsExact)
            or (sourceIsExact == destinationIsExact and sourcePositionSeenAt >= destinationPositionSeenAt)
        )

        if shouldReplacePosition then
            destination.mapID = npc.mapID or destination.mapID
            destination.mapName = npc.mapName or destination.mapName
            destination.zoneName = npc.zoneName or destination.zoneName
            destination.x = npc.x
            destination.y = npc.y
            destination.positionSource = npc.positionSource
            destination.positionSeenAt = npc.positionSeenAt or npc.lastSeenAt
        end
    end
end

local function mergeCharacterGroupmates(target, metadata, counters)
    for key, seconds in pairs(counters or {}) do
        local groupmate = type(metadata and metadata[key]) == "table" and metadata[key] or {}
        local source = {}
        for field, value in pairs(groupmate) do
            source[field] = value
        end
        source.seconds = tonumber(seconds) or 0
        mergeGroupmates(target, { [key] = source })
    end
end

local function mergeCharacterNPCs(target, metadata, counters)
    for key, interactions in pairs(counters or {}) do
        local npc = type(metadata and metadata[key]) == "table" and metadata[key] or {}
        local source = {}
        for field, value in pairs(npc) do
            source[field] = value
        end
        source.interactions = tonumber(interactions) or 0
        mergeNPCs(target, { [key] = source })
    end
end

local function mergeFilteredCompletedActivity(result, activity)
    local completions = math.max(1, tonumber(activity.completions) or 1)
    local category = activity.category == "raid" and "raid"
        or activity.category == "dungeon" and "dungeon"
        or "outdoor"
    local activityKey = activity.activityKey
        or string.format("%s:%s:%s", category, tostring(activity.kind or "other"), tostring(activity.name or "unknown"))
    local snapshot = {}
    for field, value in pairs(activity) do
        snapshot[field] = value
    end
    snapshot.category = category
    snapshot.completions = completions
    snapshot.lastCompletedAt = snapshot.lastCompletedAt or snapshot.completedAt

    result.completedActivities.total = result.completedActivities.total + completions
    result.completedActivities[category] = result.completedActivities[category] + completions
    mergeCompletedActivities(result.completedActivities.entries, { [activityKey] = snapshot })
    mergeActivityHistory(result.completedActivities.history, { activity })

    if category == "raid" and activity.kind == "boss" then
        result.encounters.total = result.encounters.total + completions
        result.encounters.raid = result.encounters.raid + completions
        local boss = {}
        for field, value in pairs(activity) do
            boss[field] = value
        end
        boss.kills = completions
        mergeStructured(result.encounters.bosses, { [activityKey] = boss })
    end
end

local function getTimeCounters(container, totalField)
    container = type(container) == "table" and container or {}
    local total = math.max(0, tonumber(container[totalField]) or 0)
    local active = math.max(0, tonumber(container.activeSeconds) or 0)
    local afk = math.max(0, tonumber(container.afkSeconds) or 0)

    total = math.max(total, active + afk)
    afk = math.min(afk, total)
    return total, total - afk, afk
end

local function nextCalendarDay(timestamp)
    local value = date("*t", timestamp)
    return time({
        year = value.year,
        month = value.month,
        day = value.day + 1,
        hour = 12,
        min = 0,
        sec = 0,
    })
end

local function getMondayWeekday(timestamp)
    local value = date("*t", timestamp)
    return ((value.wday + 5) % 7) + 1
end

local function getTimelineStart(periodKey, startAt, endAt)
    if periodKey ~= "ALL" then
        return startAt
    end

    local oldestTimestamp
    for dayKey, day in pairs(AW.Database.db.days or {}) do
        local timestamp = tonumber(day.startedAt) or Util:TimestampFromDayKey(dayKey)
        if timestamp and (not oldestTimestamp or timestamp < oldestTimestamp) then
            oldestTimestamp = timestamp
        end
    end

    return oldestTimestamp or tonumber(AW.Database.db.meta.createdAt) or endAt
end

local function copyActivity(activity)
    local snapshot = {}
    for field, value in pairs(activity or {}) do
        snapshot[field] = value
    end
    return snapshot
end

local function buildTimelineDay(dayKey, timestamp, day, characterFilter)
    day = type(day) == "table" and day or {}
    local filtered = hasCharacterFilter(characterFilter)
    local onlineSeconds, activeSeconds, afkSeconds
    local sessionCount = 0
    local deaths = 0
    local activities = {}
    local topCharacter
    local topCharacterSeconds = -1

    if filtered then
        onlineSeconds, activeSeconds, afkSeconds = 0, 0, 0
        for characterKey, character in pairs(day.characters or {}) do
            if includesCharacter(characterFilter, characterKey) then
                local characterOnline, characterActive, characterAFK = getTimeCounters(character, "seconds")
                onlineSeconds = onlineSeconds + characterOnline
                activeSeconds = activeSeconds + characterActive
                afkSeconds = afkSeconds + characterAFK
                sessionCount = sessionCount + (tonumber(character.sessionCount) or 0)
                deaths = deaths + (tonumber(character.deaths) or 0)

                for activity, seconds in pairs(character.activities or {}) do
                    Util:AddMetric(activities, activity, seconds)
                end

                if characterOnline > topCharacterSeconds then
                    topCharacter = character
                    topCharacterSeconds = characterOnline
                end
            end
        end
    else
        onlineSeconds, activeSeconds, afkSeconds = getTimeCounters(day, "onlineSeconds")
        sessionCount = tonumber(day.sessionCount) or 0
        deaths = tonumber(day.deaths and day.deaths.total) or 0
        activities = day.activities or {}

        for _, character in pairs(day.characters or {}) do
            local seconds = tonumber(character.seconds) or 0
            if seconds > topCharacterSeconds then
                topCharacter = character
                topCharacterSeconds = seconds
            end
        end
    end

    local completed = type(day.completedActivities) == "table" and day.completedActivities or {}
    local activityHistory = {}
    local activityCounts = { dungeon = 0, raid = 0, outdoor = 0 }

    for _, activity in ipairs(completed.history or {}) do
        if type(activity) == "table" and includesCharacter(characterFilter, activity.characterKey) then
            local snapshot = copyActivity(activity)
            activityHistory[#activityHistory + 1] = snapshot
            local category = snapshot.category == "raid" and "raid"
                or snapshot.category == "dungeon" and "dungeon"
                or "outdoor"
            activityCounts[category] = activityCounts[category] + math.max(1, tonumber(snapshot.completions) or 1)
        end
    end

    if not filtered and #activityHistory == 0 then
        for activityKey, activity in pairs(completed.entries or {}) do
            if type(activity) == "table" then
                local snapshot = copyActivity(activity)
                snapshot.activityKey = snapshot.activityKey or activityKey
                snapshot.completedAt = snapshot.completedAt or tonumber(day.startedAt) or timestamp
                snapshot.legacyAggregate = true
                activityHistory[#activityHistory + 1] = snapshot
                local category = snapshot.category == "raid" and "raid"
                    or snapshot.category == "dungeon" and "dungeon"
                    or "outdoor"
                activityCounts[category] = activityCounts[category] + math.max(1, tonumber(snapshot.completions) or 1)
            end
        end
    end

    table.sort(activityHistory, function(left, right)
        local leftTime = tonumber(left.completedAt) or 0
        local rightTime = tonumber(right.completedAt) or 0
        if leftTime == rightTime then
            return (tonumber(left.sequence) or 0) < (tonumber(right.sequence) or 0)
        end
        return leftTime < rightTime
    end)

    local totalActivities = filtered and 0 or (tonumber(completed.total) or 0)
    if filtered or totalActivities <= 0 then
        totalActivities = activityCounts.dungeon + activityCounts.raid + activityCounts.outdoor
    end

    return {
        key = dayKey,
        timestamp = timestamp,
        weekday = getMondayWeekday(timestamp),
        onlineSeconds = onlineSeconds,
        activeSeconds = activeSeconds,
        afkSeconds = afkSeconds,
        sessionCount = sessionCount,
        deaths = deaths,
        completedActivityCount = totalActivities,
        completedActivities = activityHistory,
        activityCounts = activityCounts,
        activities = activities,
        topCharacter = topCharacter,
    }
end

function Summary:BuildTimeline(periodKey, characterFilter)
    local startAt, endAt = AW.Periods:GetRange(periodKey)
    startAt = getTimelineStart(periodKey, startAt, endAt)

    local cursor = Util:TimestampFromDayKey(Util:DayKey(startAt))
    local endDay = Util:TimestampFromDayKey(Util:DayKey(endAt))
    local todayKey = Util:DayKey(endAt)
    local timeline = {
        periodKey = periodKey,
        startAt = startAt,
        endAt = endAt,
        days = {},
        daysByKey = {},
        totalActivities = 0,
    }

    while cursor and endDay and cursor <= endDay do
        local dayKey = Util:DayKey(cursor)
        local day = buildTimelineDay(dayKey, cursor, AW.Database.db.days[dayKey], characterFilter)
        day.isToday = dayKey == todayKey
        timeline.days[#timeline.days + 1] = day
        timeline.daysByKey[dayKey] = day
        timeline.totalActivities = timeline.totalActivities + day.completedActivityCount
        cursor = nextCalendarDay(cursor)
    end

    return timeline
end

function Summary:BuildMoneyTimeline(periodKey, knownBalance, characterFilter)
    local startAt, endAt = AW.Periods:GetRange(periodKey)
    startAt = getTimelineStart(periodKey, startAt, endAt)

    local cursor = Util:TimestampFromDayKey(Util:DayKey(startAt))
    local endDay = Util:TimestampFromDayKey(Util:DayKey(endAt))
    local days = {}
    local periodNet = 0

    while cursor and endDay and cursor <= endDay do
        local dayKey = Util:DayKey(cursor)
        local storedDay = AW.Database.db.days[dayKey]
        local money = type(storedDay) == "table" and type(storedDay.money) == "table"
            and storedDay.money or {}
        local net = 0
        local changes = 0
        if hasCharacterFilter(characterFilter) then
            for characterKey, wallet in pairs(money.characters or {}) do
                if includesCharacter(characterFilter, characterKey) then
                    net = net + (tonumber(wallet.net) or 0)
                    changes = changes + (tonumber(wallet.changes) or 0)
                end
            end
        else
            net = tonumber(money.net) or 0
            changes = tonumber(money.changes) or 0
        end

        days[#days + 1] = {
            key = dayKey,
            timestamp = cursor,
            net = net,
            changes = changes,
        }
        periodNet = periodNet + net
        cursor = nextCalendarDay(cursor)
    end

    local balance = (tonumber(knownBalance) or 0) - periodNet
    local timeline = {
        periodKey = periodKey,
        startAt = startAt,
        endAt = endAt,
        openingBalance = balance,
        closingBalance = tonumber(knownBalance) or 0,
        net = periodNet,
        points = {
            {
                timestamp = startAt,
                balance = balance,
                opening = true,
            },
        },
    }

    for _, day in ipairs(days) do
        balance = balance + day.net
        timeline.points[#timeline.points + 1] = {
            key = day.key,
            timestamp = day.timestamp,
            balance = balance,
            net = day.net,
            changes = day.changes,
        }
    end

    return timeline
end

function Summary:BuildPreviewTimeline()
    local now = Util:Now()
    local startAt = now - (6 * 86400)
    local cursor = Util:TimestampFromDayKey(Util:DayKey(startAt))
    local endDay = Util:TimestampFromDayKey(Util:DayKey(now))
    local timeline = {
        periodKey = "PREVIEW",
        startAt = startAt,
        endAt = now,
        days = {},
        daysByKey = {},
        totalActivities = 0,
    }
    local samples = {
        { online = 7200, active = 6480, sessions = 1, deaths = 0 },
        { online = 14400, active = 12600, sessions = 2, deaths = 1 },
        { online = 3600, active = 3300, sessions = 1, deaths = 0 },
        { online = 21600, active = 18360, sessions = 2, deaths = 4 },
        { online = 10800, active = 9720, sessions = 1, deaths = 1 },
        { online = 25200, active = 21600, sessions = 1, deaths = 5 },
        { online = 14400, active = 12180, sessions = 1, deaths = 1 },
    }
    local previewHistory = self:BuildPreview().completedActivities.history or {}
    local activitiesByDay = {}
    for _, activity in ipairs(previewHistory) do
        local activityDayKey = Util:DayKey(activity.completedAt or now)
        activitiesByDay[activityDayKey] = activitiesByDay[activityDayKey] or {}
        activitiesByDay[activityDayKey][#activitiesByDay[activityDayKey] + 1] = copyActivity(activity)
    end

    local index = 1
    while cursor and endDay and cursor <= endDay do
        local dayKey = Util:DayKey(cursor)
        local sample = samples[index] or samples[#samples]
        local activities = activitiesByDay[dayKey] or {}
        local counts = { dungeon = 0, raid = 0, outdoor = 0 }
        for _, activity in ipairs(activities) do
            local category = activity.category == "raid" and "raid"
                or activity.category == "dungeon" and "dungeon"
                or "outdoor"
            counts[category] = counts[category] + 1
        end
        table.sort(activities, function(left, right)
            return (tonumber(left.completedAt) or 0) < (tonumber(right.completedAt) or 0)
        end)

        local day = {
            key = dayKey,
            timestamp = cursor,
            weekday = getMondayWeekday(cursor),
            isToday = dayKey == Util:DayKey(now),
            onlineSeconds = sample.online,
            activeSeconds = sample.active,
            afkSeconds = math.max(0, sample.online - sample.active),
            sessionCount = sample.sessions,
            deaths = sample.deaths,
            completedActivityCount = #activities,
            completedActivities = activities,
            activityCounts = counts,
            activities = {},
        }
        timeline.days[#timeline.days + 1] = day
        timeline.daysByKey[dayKey] = day
        timeline.totalActivities = timeline.totalActivities + #activities
        cursor = nextCalendarDay(cursor)
        index = index + 1
    end

    return timeline
end

function Summary:Build(periodKey, characterFilter)
    local startAt, endAt = AW.Periods:GetRange(periodKey)
    local filtered = hasCharacterFilter(characterFilter)
    local result = {
        periodKey = periodKey,
        startAt = startAt,
        endAt = endAt,
        onlineSeconds = 0,
        activeSeconds = 0,
        afkSeconds = 0,
        sessionCount = 0,
        longestSession = 0,
        daysPlayed = 0,
        characters = {},
        zones = {},
        activities = {},
        deaths = { total = 0, locations = {}, details = {} },
        groupmates = {},
        npcs = {},
        money = { net = 0, earned = 0, spent = 0, changes = 0, characters = {} },
        encounters = { total = 0, dungeon = 0, raid = 0, bosses = {} },
        completedActivities = { total = 0, dungeon = 0, raid = 0, outdoor = 0, entries = {}, history = {} },
    }

    for dayKey, day in pairs(AW.Database.db.days) do
        local timestamp = day.startedAt or Util:TimestampFromDayKey(dayKey)
        if timestamp and timestamp >= startAt and timestamp <= endAt then
            if filtered then
                local dayHasData = false

                for characterKey, dayCharacter in pairs(day.characters or {}) do
                    if includesCharacter(characterFilter, characterKey) then
                        local onlineSeconds, activeSeconds, afkSeconds = getTimeCounters(dayCharacter, "seconds")
                        local sessions = tonumber(dayCharacter.sessionCount) or 0
                        local characterDeaths = tonumber(dayCharacter.deaths) or 0

                        result.onlineSeconds = result.onlineSeconds + onlineSeconds
                        result.activeSeconds = result.activeSeconds + activeSeconds
                        result.afkSeconds = result.afkSeconds + afkSeconds
                        result.sessionCount = result.sessionCount + sessions
                        result.longestSession = math.max(result.longestSession, tonumber(dayCharacter.longestSession) or 0)
                        result.deaths.total = result.deaths.total + characterDeaths

                        mergeStructured(result.characters, { [characterKey] = dayCharacter })
                        local destinationCharacter = result.characters[characterKey]
                        destinationCharacter.longestSession = math.max(
                            tonumber(destinationCharacter.longestSession) or 0,
                            tonumber(dayCharacter.longestSession) or 0
                        )
                        mergeZones(result.zones, dayCharacter.zones)
                        mergeCharacterGroupmates(result.groupmates, day.groupmates, dayCharacter.groupmates)
                        mergeCharacterNPCs(result.npcs, day.npcs, dayCharacter.npcs)

                        for activity, seconds in pairs(dayCharacter.activities or {}) do
                            Util:AddMetric(result.activities, activity, seconds)
                        end

                        if onlineSeconds > 0 or sessions > 0 or characterDeaths > 0
                            or next(dayCharacter.activities or {}) ~= nil
                            or next(dayCharacter.zones or {}) ~= nil
                            or next(dayCharacter.npcs or {}) ~= nil
                        then
                            dayHasData = true
                        end
                    end
                end

                for _, death in ipairs((day.deaths and day.deaths.details) or {}) do
                    if type(death) == "table" and includesCharacter(characterFilter, death.characterKey) then
                        result.deaths.details[#result.deaths.details + 1] = death
                        local locationName = death.locationName or (AW.L and AW.L.UNKNOWN_ZONE) or "Unknown zone"
                        local locationKey = string.format("%s:%s", tostring(death.mapID or 0), locationName)
                        local location = result.deaths.locations[locationKey]
                        if not location then
                            location = { mapID = death.mapID, name = locationName, deaths = 0 }
                            result.deaths.locations[locationKey] = location
                        end
                        location.deaths = location.deaths + 1
                    end
                end

                for characterKey, wallet in pairs((day.money and day.money.characters) or {}) do
                    if includesCharacter(characterFilter, characterKey) then
                        result.money.net = result.money.net + (tonumber(wallet.net) or 0)
                        result.money.earned = result.money.earned + (tonumber(wallet.earned) or 0)
                        result.money.spent = result.money.spent + (tonumber(wallet.spent) or 0)
                        result.money.changes = result.money.changes + (tonumber(wallet.changes) or 0)
                        mergeStructured(result.money.characters, { [characterKey] = wallet })
                        if (tonumber(wallet.changes) or 0) > 0 then
                            dayHasData = true
                        end
                    end
                end

                for _, activity in ipairs((day.completedActivities and day.completedActivities.history) or {}) do
                    if type(activity) == "table" and includesCharacter(characterFilter, activity.characterKey) then
                        mergeFilteredCompletedActivity(result, activity)
                        dayHasData = true
                    end
                end

                if dayHasData then
                    result.daysPlayed = result.daysPlayed + 1
                end
            else
                local onlineSeconds, activeSeconds, afkSeconds = getTimeCounters(day, "onlineSeconds")
                result.daysPlayed = result.daysPlayed + 1
                result.onlineSeconds = result.onlineSeconds + onlineSeconds
                result.activeSeconds = result.activeSeconds + activeSeconds
                result.afkSeconds = result.afkSeconds + afkSeconds
                result.sessionCount = result.sessionCount + (day.sessionCount or 0)
                result.longestSession = math.max(result.longestSession, day.longestSession or 0)
                result.deaths.total = result.deaths.total + ((day.deaths and day.deaths.total) or 0)
                result.money.net = result.money.net + ((day.money and day.money.net) or 0)
                result.money.earned = result.money.earned + ((day.money and day.money.earned) or 0)
                result.money.spent = result.money.spent + ((day.money and day.money.spent) or 0)
                result.money.changes = result.money.changes + ((day.money and day.money.changes) or 0)
                result.encounters.total = result.encounters.total + ((day.encounters and day.encounters.total) or 0)
                result.encounters.dungeon = result.encounters.dungeon + ((day.encounters and day.encounters.dungeon) or 0)
                result.encounters.raid = result.encounters.raid + ((day.encounters and day.encounters.raid) or 0)
                result.completedActivities.total = result.completedActivities.total + ((day.completedActivities and day.completedActivities.total) or 0)
                result.completedActivities.dungeon = result.completedActivities.dungeon + ((day.completedActivities and day.completedActivities.dungeon) or 0)
                result.completedActivities.raid = result.completedActivities.raid + ((day.completedActivities and day.completedActivities.raid) or 0)
                result.completedActivities.outdoor = result.completedActivities.outdoor + ((day.completedActivities and day.completedActivities.outdoor) or 0)

                mergeStructured(result.characters, day.characters)
                mergeZones(result.zones, day.zones)
                mergeGroupmates(result.groupmates, day.groupmates)
                mergeNPCs(result.npcs, day.npcs)
                mergeStructured(result.deaths.locations, day.deaths and day.deaths.locations)
                for _, death in ipairs((day.deaths and day.deaths.details) or {}) do
                    result.deaths.details[#result.deaths.details + 1] = death
                end
                mergeStructured(result.encounters.bosses, day.encounters and day.encounters.bosses)
                mergeCompletedActivities(result.completedActivities.entries, day.completedActivities and day.completedActivities.entries)
                mergeActivityHistory(result.completedActivities.history, day.completedActivities and day.completedActivities.history)
                mergeStructured(result.money.characters, day.money and day.money.characters)

                for activity, seconds in pairs(day.activities or {}) do
                    Util:AddMetric(result.activities, activity, seconds)
                end
            end
        end
    end

    local _, topCharacter = Util:TopEntry(result.characters, "seconds")
    local _, topZone = Util:TopEntry(result.zones, "seconds")
    local topActivityKey, _, topActivitySeconds = Util:TopEntry(result.activities)
    local _, deadliestLocation = Util:TopEntry(result.deaths.locations, "deaths")
    local _, topGroupmate = Util:TopEntry(result.groupmates, "seconds")
    local _, topNPC = Util:TopEntry(result.npcs, "interactions")
    local _, topBoss = Util:TopEntry(result.encounters.bosses, "kills")
    local _, topCompletedActivity = Util:TopEntry(result.completedActivities.entries, "completions")
    local latestCompletedActivity = findLatestCompletedActivity(result.completedActivities)

    local knownBalance = 0
    local trackedWallets = 0
    for characterKey, character in pairs(AW.Database.db.characters or {}) do
        if includesCharacter(characterFilter, characterKey) and character.moneyCopper ~= nil then
            knownBalance = knownBalance + (tonumber(character.moneyCopper) or 0)
            trackedWallets = trackedWallets + 1
        end
    end
    knownBalance = knownBalance + (tonumber(AW.Database.db.meta.warbandMoneyCopper) or 0)

    result.topCharacter = topCharacter
    result.topZone = topZone
    result.topActivityKey = topActivityKey or "unknown"
    result.topActivitySeconds = math.max(0, topActivitySeconds or 0)
    result.deadliestLocation = deadliestLocation
    result.topGroupmate = topGroupmate
    result.topNPC = topNPC
    result.topBoss = topBoss
    result.topCompletedActivity = topCompletedActivity
    result.latestCompletedActivity = latestCompletedActivity
    result.zoneCount = Util:Count(result.zones)
    result.npcCount = Util:Count(result.npcs)
    result.uniqueBossCount = Util:Count(result.encounters.bosses)
    result.uniqueCompletedActivityCount = Util:Count(result.completedActivities.entries)
    result.knownBalance = knownBalance
    result.warbandBalance = tonumber(AW.Database.db.meta.warbandMoneyCopper)
    result.trackedWallets = trackedWallets
    result.hasMoneyData = trackedWallets > 0
    result.moneyTimeline = self:BuildMoneyTimeline(periodKey, knownBalance, characterFilter)
    result.hasEncounterData = result.encounters.total > 0
    result.hasCompletedActivityData = result.completedActivities.total > 0
    result.hasData = result.onlineSeconds > 0
        or result.sessionCount > 0
        or result.hasMoneyData
        or result.hasEncounterData
        or result.hasCompletedActivityData

    return result
end

function Summary:BuildPreview()
    return {
        periodKey = "PREVIEW",
        startAt = Util:Now() - (7 * 86400),
        endAt = Util:Now(),
        onlineSeconds = 97200,
        activeSeconds = 84240,
        afkSeconds = 12960,
        sessionCount = 9,
        longestSession = 17100,
        daysPlayed = 5,
        zoneCount = 18,
        npcCount = 47,
        characters = {
            ["preview-main"] = { name = UnitName("player") or "Kalixia", realm = GetRealmName(), className = "Mage", classFile = "MAGE", seconds = 84240, activeSeconds = 78120, afkSeconds = 6120, deaths = 7 },
            ["preview-alt"] = { name = "Worriades", realm = GetRealmName(), className = "Warrior", classFile = "WARRIOR", seconds = 12960, activeSeconds = 11800, afkSeconds = 1160, deaths = 5 },
        },
        zones = {
            ["2393"] = { name = GetZoneText() ~= "" and GetZoneText() or "Silvermoon City", seconds = 22620, visits = 7 },
            ["2662"] = { name = "The Dark Heart", seconds = 17400, visits = 4 },
            ["2339"] = { name = "Dornogal", seconds = 12600, visits = 5 },
        },
        deaths = {
            total = 12,
            locations = {
                ["2662:The Dark Heart"] = { name = "The Dark Heart", deaths = 5 },
                ["2820:Sporefall"] = { name = "Sporefall", deaths = 4 },
                ["2393:Silvermoon City"] = { name = "Silvermoon City", deaths = 3 },
            },
            details = {
                { timestamp = Util:Now() - 7200, category = "boss", encounterName = "Void Speaker Eirich", spellName = "Entropic Reckoning", sourceName = "Void Speaker Eirich", locationName = "The Dark Heart", amount = 1845621 },
                { timestamp = Util:Now() - 16200, category = "fall", environmentalType = "FALLING", locationName = "Dornogal", amount = 932481 },
                { timestamp = Util:Now() - 86400, category = "attack", spellName = "Shadow Bolt", sourceName = "Nightfall Ritualist", locationName = "Sporefall", amount = 641205 },
            },
        },
        groupmates = {
            ["preview-teuteu"] = { name = "Teuteu", realm = "Hyjal", classFile = "MAGE", isPlayer = true, guildName = "Les Gardiens d'Azeroth", mythicPlusScore = 2847, region = "eu", seconds = 31800 },
            ["preview-lucia"] = { name = "Lucïa", realm = "Hyjal", classFile = "PRIEST", isPlayer = true, guildName = "Échos du Vide", mythicPlusScore = 2312, region = "eu", seconds = 24120 },
            ["preview-krog"] = { name = "Krog", realm = "Silvermoon", classFile = "WARRIOR", isPlayer = true, region = "eu", seconds = 18300 },
        },
        npcs = {
            ["2393:Innkeeper Tarelvir"] = {
                name = "Innkeeper Tarelvir",
                title = "Innkeeper",
                mapID = 2393,
                mapName = "Silvermoon City",
                zoneName = "The Bazaar",
                x = 0.548,
                y = 0.712,
                services = { merchant = true },
                interactions = 8,
            },
            ["2339:Brann Bronzebeard"] = {
                name = "Brann Bronzebeard",
                title = "Delve Companion",
                mapID = 2339,
                mapName = "Dornogal",
                x = 0.474,
                y = 0.442,
                services = { gossip = true },
                interactions = 6,
            },
            ["2393:Auctioneer Chilton"] = {
                name = "Auctioneer Chilton",
                title = "Auctioneer",
                mapID = 2393,
                mapName = "Silvermoon City",
                zoneName = "The Bazaar",
                x = 0.612,
                y = 0.531,
                services = { auctionHouse = true },
                interactions = 4,
            },
        },
        topCharacter = { name = UnitName("player") or "Kalixia", seconds = 84240 },
        topZone = { name = GetZoneText() ~= "" and GetZoneText() or "Silvermoon City", seconds = 22620 },
        topActivityKey = "party",
        topActivitySeconds = 33600,
        deadliestLocation = { name = "The Dark Heart", deaths = 5 },
        topGroupmate = { name = "Teuteu", realm = "Hyjal", classFile = "MAGE", isPlayer = true, guildName = "Les Gardiens d'Azeroth", mythicPlusScore = 2847, region = "eu", seconds = 31800 },
        topNPC = { name = "Innkeeper Tarelvir", interactions = 8 },
        money = {
            net = 12450000,
            earned = 19300000,
            spent = 6850000,
            changes = 38,
            characters = {
                ["preview-main"] = { name = UnitName("player") or "Kalixia", net = 10300000, earned = 15200000, spent = 4900000, changes = 27, balance = 604500000 },
                ["preview-alt"] = { name = "Worriades", net = 2150000, earned = 4100000, spent = 1950000, changes = 11, balance = 176745000 },
            },
        },
        moneyTimeline = {
            periodKey = "PREVIEW",
            startAt = Util:Now() - (6 * 86400),
            endAt = Util:Now(),
            openingBalance = 851295000,
            closingBalance = 863745000,
            net = 12450000,
            points = {
                { timestamp = Util:Now() - (6 * 86400), balance = 851295000, opening = true },
                { timestamp = Util:Now() - (6 * 86400), balance = 852495000, net = 1200000, changes = 4 },
                { timestamp = Util:Now() - (5 * 86400), balance = 851845000, net = -650000, changes = 3 },
                { timestamp = Util:Now() - (4 * 86400), balance = 856145000, net = 4300000, changes = 8 },
                { timestamp = Util:Now() - (3 * 86400), balance = 856145000, net = 0, changes = 0 },
                { timestamp = Util:Now() - (2 * 86400), balance = 858745000, net = 2600000, changes = 7 },
                { timestamp = Util:Now() - 86400, balance = 860245000, net = 1500000, changes = 6 },
                { timestamp = Util:Now(), balance = 863745000, net = 3500000, changes = 10 },
            },
        },
        knownBalance = 863745000,
        warbandBalance = 82500000,
        trackedWallets = 3,
        hasMoneyData = true,
        encounters = {
            total = 17,
            dungeon = 13,
            raid = 4,
            bosses = {
                ["raid:2820:3200"] = { name = "Rotmire", instanceName = "Sporefall", instanceType = "raid", difficultyName = "Heroic", kills = 3 },
                ["party:2662:2900"] = { name = "Void Speaker Eirich", instanceName = "The Dark Heart", instanceType = "party", difficultyName = "Mythic", kills = 2 },
                ["party:2662:2901"] = { name = "Coaglamation", instanceName = "The Dark Heart", instanceType = "party", difficultyName = "Mythic", kills = 2 },
            },
        },
        completedActivities = {
            total = 12,
            dungeon = 3,
            raid = 4,
            outdoor = 5,
            entries = {
                ["raid:2820:3200"] = { name = "Rotmire", category = "raid", kind = "boss", instanceName = "Sporefall", difficultyName = "Heroic", completions = 3 },
                ["dungeon:challenge:503:10"] = { name = "The Dark Heart", category = "dungeon", kind = "dungeon", keystoneLevel = 10, runSeconds = 1662, bestRunSeconds = 1598, onTime = true, keystoneUpgradeLevels = 2, completions = 2 },
                ["dungeon:2662:23"] = { name = "The Dark Heart", category = "dungeon", kind = "dungeon", difficultyName = "Mythic", runSeconds = 2104, bestRunSeconds = 2104, completions = 1 },
                ["scenario:2393"] = { name = "The Sinkhole", category = "outdoor", kind = "delve", instanceName = "Khaz Algar", delveTier = 8, runSeconds = 934, bestRunSeconds = 901, completions = 3 },
                ["quest:90001"] = { name = "Prey: The Void Stalker", category = "outdoor", kind = "prey", instanceName = "Eversong Woods", difficultyName = "Nightmare", runSeconds = 1268, bestRunSeconds = 1192, completions = 2 },
            },
            history = {
                { name = "Rotmire", category = "raid", kind = "boss", instanceName = "Sporefall", difficultyName = "Heroic", completedAt = Util:Now() - 900 },
                { name = "The Dark Heart", category = "dungeon", kind = "dungeon", keystoneLevel = 10, runSeconds = 1598, onTime = true, keystoneUpgradeLevels = 2, completedAt = Util:Now() - 2400 },
                { name = "The Sinkhole", category = "outdoor", kind = "delve", instanceName = "Khaz Algar", delveTier = 8, runSeconds = 901, completedAt = Util:Now() - 4300 },
                { name = "Prey: The Void Stalker", category = "outdoor", kind = "prey", instanceName = "Eversong Woods", difficultyName = "Nightmare", runSeconds = 1192, completedAt = Util:Now() - 7200 },
                { name = "Queen Ansurek", category = "raid", kind = "boss", instanceName = "Nerub-ar Palace", difficultyName = "Heroic", completedAt = Util:Now() - 10800 },
                { name = "The Dark Heart", category = "dungeon", kind = "dungeon", difficultyName = "Mythic", runSeconds = 2104, completedAt = Util:Now() - 14400 },
                { name = "Rotmire", category = "raid", kind = "boss", instanceName = "Sporefall", difficultyName = "Heroic", completedAt = Util:Now() - 18000 },
                { name = "The Sinkhole", category = "outdoor", kind = "delve", instanceName = "Khaz Algar", delveTier = 8, runSeconds = 934, completedAt = Util:Now() - 21600 },
                { name = "The Dark Heart", category = "dungeon", kind = "dungeon", keystoneLevel = 10, runSeconds = 1662, onTime = true, keystoneUpgradeLevels = 1, completedAt = Util:Now() - 86400 },
                { name = "Prey: The Void Stalker", category = "outdoor", kind = "prey", instanceName = "Eversong Woods", difficultyName = "Nightmare", runSeconds = 1268, completedAt = Util:Now() - 90000 },
                { name = "Rotmire", category = "raid", kind = "boss", instanceName = "Sporefall", difficultyName = "Heroic", completedAt = Util:Now() - 93600 },
                { name = "The Sinkhole", category = "outdoor", kind = "delve", instanceName = "Khaz Algar", delveTier = 8, runSeconds = 922, completedAt = Util:Now() - 97200 },
            },
        },
        uniqueBossCount = 11,
        topBoss = { name = "Rotmire", kills = 3, instanceName = "Sporefall", instanceType = "raid" },
        uniqueCompletedActivityCount = 5,
        topCompletedActivity = { name = "Rotmire", category = "raid", kind = "boss", completions = 3 },
        latestCompletedActivity = { name = "Rotmire", category = "raid", kind = "boss", completedAt = Util:Now() - 900 },
        hasEncounterData = true,
        hasCompletedActivityData = true,
        hasData = true,
        isPreview = true,
    }
end
