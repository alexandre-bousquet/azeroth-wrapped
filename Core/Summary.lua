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
}

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

        local sourceHasPosition = npc.x ~= nil and npc.y ~= nil
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

local function getTimeCounters(container, totalField)
    container = type(container) == "table" and container or {}
    local total = math.max(0, tonumber(container[totalField]) or 0)
    local active = math.max(0, tonumber(container.activeSeconds) or 0)
    local afk = math.max(0, tonumber(container.afkSeconds) or 0)

    total = math.max(total, active + afk)
    afk = math.min(afk, total)
    return total, total - afk, afk
end

function Summary:Build(periodKey)
    local startAt, endAt = AW.Periods:GetRange(periodKey)
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

    local _, topCharacter = Util:TopEntry(result.characters, "seconds")
    local _, topZone = Util:TopEntry(result.zones, "seconds")
    local topActivityKey, _, topActivitySeconds = Util:TopEntry(result.activities)
    local _, deadliestLocation = Util:TopEntry(result.deaths.locations, "deaths")
    local _, topGroupmate = Util:TopEntry(result.groupmates, "seconds")
    local _, topNPC = Util:TopEntry(result.npcs, "interactions")
    local _, topBoss = Util:TopEntry(result.encounters.bosses, "kills")
    local _, topCompletedActivity = Util:TopEntry(result.completedActivities.entries, "completions")

    local knownBalance = 0
    local trackedWallets = 0
    for _, character in pairs(AW.Database.db.characters or {}) do
        if character.moneyCopper ~= nil then
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
    result.zoneCount = Util:Count(result.zones)
    result.npcCount = Util:Count(result.npcs)
    result.uniqueBossCount = Util:Count(result.encounters.bosses)
    result.uniqueCompletedActivityCount = Util:Count(result.completedActivities.entries)
    result.knownBalance = knownBalance
    result.warbandBalance = tonumber(AW.Database.db.meta.warbandMoneyCopper)
    result.trackedWallets = trackedWallets
    result.hasMoneyData = trackedWallets > 0
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
        hasEncounterData = true,
        hasCompletedActivityData = true,
        hasData = true,
        isPreview = true,
    }
end
