local _, AW = ...

AW.Database = {}
local Database = AW.Database
local Util = AW.Util

local function ensureTable(parent, key)
    if type(parent[key]) ~= "table" then
        parent[key] = {}
    end
    return parent[key]
end

local function newDatabase(now)
    return {
        schema = AW.CONST.DB_SCHEMA,
        meta = {
            createdAt = now,
            updatedAt = now,
            lastLoginAt = now,
            seasons = {},
        },
        settings = {
            enabled = true,
            debug = false,
            locale = "AUTO",
            defaultPeriod = "WEEK",
            trackAFK = true,
            trackGroupmates = true,
            trackNPCs = true,
            trackMoney = true,
            trackEncounters = true,
            anonymousShare = false,
            retentionDays = AW.CONST.DEFAULT_RETENTION_DAYS,
            minimapButton = {
                hide = false,
                minimapPos = 225,
            },
        },
        characters = {},
        days = {},
        sessions = {},
    }
end

local function repairFalseLogoutMoneyDrops(savedDatabase)
    for _, day in pairs(savedDatabase.days or {}) do
        local money = type(day.money) == "table" and day.money or nil
        if money then
            local wallets = type(money.characters) == "table" and money.characters or {}
            for _, wallet in pairs(wallets) do
                local startingBalance = tonumber(wallet.start) or 0
                local finalBalance = tonumber(wallet.last) or 0
                local net = tonumber(wallet.net) or 0
                local earned = tonumber(wallet.earned) or 0
                local spent = tonumber(wallet.spent) or 0

                local isFalseLogoutDrop = startingBalance > 0
                    and finalBalance > 0
                    and earned == 0
                    and spent == startingBalance
                    and net == -startingBalance

                if isFalseLogoutDrop then
                    money.net = (tonumber(money.net) or 0) + finalBalance
                    money.spent = math.max(0, (tonumber(money.spent) or 0) - finalBalance)
                    money.changes = math.max(0, (tonumber(money.changes) or 0) - 1)
                    wallet.net = net + finalBalance
                    wallet.spent = math.max(0, spent - finalBalance)
                    wallet.changes = math.max(0, (tonumber(wallet.changes) or 0) - 1)
                end
            end
        end
    end
end

local function normalizeTimeCounters(container, totalField)
    if type(container) ~= "table" then
        return
    end

    local total = math.max(0, tonumber(container[totalField]) or 0)
    local active = math.max(0, tonumber(container.activeSeconds) or 0)
    local afk = math.max(0, tonumber(container.afkSeconds) or 0)

    total = math.max(total, active + afk)
    afk = math.min(afk, total)

    container[totalField] = total
    container.afkSeconds = afk
    container.activeSeconds = total - afk
end

local function repairTimeCounters(savedDatabase)
    for _, day in pairs(savedDatabase.days or {}) do
        normalizeTimeCounters(day, "onlineSeconds")
        for _, character in pairs(day.characters or {}) do
            normalizeTimeCounters(character, "seconds")
        end
    end
end

local function migrateCompletedActivities(savedDatabase)
    for _, day in pairs(savedDatabase.days or {}) do
        local encounters = type(day.encounters) == "table" and day.encounters or {}
        local completed = type(day.completedActivities) == "table" and day.completedActivities or nil

        if not completed then
            completed = {
                total = tonumber(encounters.total) or 0,
                dungeon = tonumber(encounters.dungeon) or 0,
                raid = tonumber(encounters.raid) or 0,
                outdoor = 0,
                entries = {},
            }
            day.completedActivities = completed

            for key, boss in pairs(encounters.bosses or {}) do
                if type(boss) == "table" then
                    local entry = {}
                    for field, value in pairs(boss) do
                        entry[field] = value
                    end
                    entry.category = boss.instanceType == "raid" and "raid" or "dungeon"
                    entry.kind = "boss"
                    entry.completions = tonumber(boss.kills) or 0
                    completed.entries[key] = entry
                end
            end
        end
    end
end

local function removeLegacyDungeonBossActivities(savedDatabase)
    for _, day in pairs(savedDatabase.days or {}) do
        local completed = type(day.completedActivities) == "table" and day.completedActivities or nil
        if completed and type(completed.entries) == "table" then
            local removed = 0
            for key, activity in pairs(completed.entries) do
                if type(activity) == "table"
                    and activity.category == "dungeon"
                    and activity.kind == "boss"
                then
                    removed = removed + (tonumber(activity.completions) or 0)
                    completed.entries[key] = nil
                end
            end
            completed.dungeon = math.max(0, (tonumber(completed.dungeon) or 0) - removed)
            completed.total = math.max(0, (tonumber(completed.total) or 0) - removed)
        end
    end
end

local function migrateActivityHistory(savedDatabase)
    for _, day in pairs(savedDatabase.days or {}) do
        local completed = type(day.completedActivities) == "table" and day.completedActivities or nil
        if completed then
            completed.history = type(completed.history) == "table" and completed.history or {}
            if #completed.history == 0 then
                for activityKey, activity in pairs(completed.entries or {}) do
                    if type(activity) == "table" then
                        local snapshot = {}
                        for field, value in pairs(activity) do
                            snapshot[field] = value
                        end
                        snapshot.activityKey = activityKey
                        snapshot.completedAt = tonumber(activity.lastCompletedAt) or tonumber(day.startedAt)
                        snapshot.legacyAggregate = true
                        completed.history[#completed.history + 1] = snapshot
                    end
                end
            end
        end
    end
end

local function removeNPCGroupmates(savedDatabase)
    for _, day in pairs(savedDatabase.days or {}) do
        if type(day.groupmates) == "table" then
            for key, groupmate in pairs(day.groupmates) do
                local guid = type(groupmate) == "table" and groupmate.guid or nil
                local isKnownNPC = type(groupmate) == "table"
                    and groupmate.isPlayer ~= true
                    and groupmate.name == "Valeera"
                    and type(guid) ~= "string"
                if (type(groupmate) == "table" and groupmate.isPlayer == false)
                    or (type(guid) == "string" and not string.match(guid, "^Player%-"))
                    or isKnownNPC
                then
                    day.groupmates[key] = nil
                end
            end
        end
    end
end

function Database:Initialize()
    local now = Util:Now()
    local savedVariableName = AW.savedVariableName or "AzerothWrappedDB"
    local savedDatabase = _G[savedVariableName]

    if type(savedDatabase) ~= "table" then
        savedDatabase = newDatabase(now)
        _G[savedVariableName] = savedDatabase
    end

    savedDatabase.schema = tonumber(savedDatabase.schema) or 0
    local previousSchema = savedDatabase.schema
    ensureTable(savedDatabase, "meta")
    ensureTable(savedDatabase, "settings")
    ensureTable(savedDatabase, "characters")
    ensureTable(savedDatabase, "days")
    ensureTable(savedDatabase, "sessions")
    ensureTable(savedDatabase.meta, "seasons")

    local defaults = newDatabase(now)
    for key, value in pairs(defaults.meta) do
        if savedDatabase.meta[key] == nil then
            savedDatabase.meta[key] = value
        end
    end
    for key, value in pairs(defaults.settings) do
        if savedDatabase.settings[key] == nil then
            savedDatabase.settings[key] = value
        end
    end
    if savedDatabase.settings.locale ~= "AUTO"
        and savedDatabase.settings.locale ~= "enUS"
        and savedDatabase.settings.locale ~= "frFR"
    then
        savedDatabase.settings.locale = "AUTO"
    end
    if savedDatabase.settings.defaultPeriod ~= "WEEK"
        and savedDatabase.settings.defaultPeriod ~= "MONTH"
        and savedDatabase.settings.defaultPeriod ~= "SEASON"
        and savedDatabase.settings.defaultPeriod ~= "YEAR"
        and savedDatabase.settings.defaultPeriod ~= "ALL"
    then
        savedDatabase.settings.defaultPeriod = "WEEK"
    end
    savedDatabase.settings.pinnedNPCs = nil

    if previousSchema < 4 then
        repairFalseLogoutMoneyDrops(savedDatabase)
    end
    if previousSchema < 5 then
        repairTimeCounters(savedDatabase)
    end
    if previousSchema < 6 then
        migrateCompletedActivities(savedDatabase)
    end
    if previousSchema < 7 then
        removeLegacyDungeonBossActivities(savedDatabase)
    end
    if previousSchema < 8 then
        migrateActivityHistory(savedDatabase)
    end
    if previousSchema < 9 then
        removeNPCGroupmates(savedDatabase)
    end

    savedDatabase.schema = AW.CONST.DB_SCHEMA
    savedDatabase.meta.updatedAt = now
    self.db = savedDatabase
    self:PruneOldDays()
end

function Database:GetDay(timestamp)
    local now = timestamp or Util:Now()
    local dayKey = Util:DayKey(now)
    local day = self.db.days[dayKey]

    if type(day) ~= "table" then
        day = {
            key = dayKey,
            startedAt = Util:StartOfDay(now),
            onlineSeconds = 0,
            activeSeconds = 0,
            afkSeconds = 0,
            sessionCount = 0,
            longestSession = 0,
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
        self.db.days[dayKey] = day
    end

    ensureTable(day, "characters")
    ensureTable(day, "zones")
    ensureTable(day, "activities")
    ensureTable(day, "deaths")
    ensureTable(day.deaths, "locations")
    ensureTable(day.deaths, "details")
    ensureTable(day, "groupmates")
    ensureTable(day, "npcs")
    ensureTable(day, "money")
    ensureTable(day.money, "characters")
    ensureTable(day, "encounters")
    ensureTable(day.encounters, "bosses")
    ensureTable(day, "completedActivities")
    ensureTable(day.completedActivities, "entries")
    ensureTable(day.completedActivities, "history")

    day.money.net = tonumber(day.money.net) or 0
    day.money.earned = tonumber(day.money.earned) or 0
    day.money.spent = tonumber(day.money.spent) or 0
    day.money.changes = tonumber(day.money.changes) or 0
    day.encounters.total = tonumber(day.encounters.total) or 0
    day.encounters.dungeon = tonumber(day.encounters.dungeon) or 0
    day.encounters.raid = tonumber(day.encounters.raid) or 0
    day.completedActivities.total = tonumber(day.completedActivities.total) or 0
    day.completedActivities.dungeon = tonumber(day.completedActivities.dungeon) or 0
    day.completedActivities.raid = tonumber(day.completedActivities.raid) or 0
    day.completedActivities.outdoor = tonumber(day.completedActivities.outdoor) or 0

    return day, dayKey
end

function Database:TouchCharacter(timestamp)
    local now = timestamp or Util:Now()
    local characterKey, name, realm = Util:GetCharacterKey()
    local localizedClass, classFile, classID = UnitClass("player")
    local character = self.db.characters[characterKey]

    if type(character) ~= "table" then
        character = {
            key = characterKey,
            name = name,
            realm = realm,
            firstSeenAt = now,
        }
        self.db.characters[characterKey] = character
    end

    character.name = name
    character.realm = realm
    character.className = localizedClass
    character.classFile = classFile
    character.classID = classID
    character.level = UnitLevel("player")
    character.lastSeenAt = now

    return characterKey, character
end

function Database:StartSession(timestamp)
    local now = timestamp or Util:Now()
    local characterKey = self:TouchCharacter(now)
    local mapID = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player") or nil

    AW.runtime.session = {
        startedAt = now,
        characterKey = characterKey,
        startMapID = mapID,
    }

    self.db.meta.lastLoginAt = now
end

function Database:CloseSession(timestamp)
    local current = AW.runtime.session
    if not current then
        return
    end

    local now = timestamp or Util:Now()
    local duration = math.max(0, now - current.startedAt)
    local mapID = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player") or nil

    table.insert(self.db.sessions, 1, {
        startedAt = current.startedAt,
        endedAt = now,
        duration = duration,
        characterKey = current.characterKey,
        startMapID = current.startMapID,
        endMapID = mapID,
    })

    while #self.db.sessions > AW.CONST.MAX_SESSION_HISTORY do
        table.remove(self.db.sessions)
    end

    self.db.meta.updatedAt = now
    AW.runtime.session = nil
end

function Database:PruneOldDays()
    local retentionDays = math.max(30, tonumber(self.db.settings.retentionDays) or AW.CONST.DEFAULT_RETENTION_DAYS)
    local cutoff = Util:Now() - (retentionDays * 86400)

    for dayKey in pairs(self.db.days) do
        local timestamp = Util:TimestampFromDayKey(dayKey)
        if timestamp and timestamp < cutoff then
            self.db.days[dayKey] = nil
        end
    end
end

function Database:CountDays()
    return Util:Count(self.db and self.db.days or {})
end

function Database:Reset()
    local savedVariableName = AW.savedVariableName or "AzerothWrappedDB"
    _G[savedVariableName] = newDatabase(Util:Now())
    self.db = _G[savedVariableName]
    AW.runtime.session = nil
    AW.runtime.lastDayKey = nil
    AW.runtime.lastZoneKey = nil
    AW.runtime.lastTrackedMoneyCopper = nil
    AW.runtime.lastTrackedWarbandMoneyCopper = 0
    AW.runtime.hasLiveWarbandMoney = false
    AW.runtime.moneyDayKey = nil
    AW.runtime.moneyUpdateToken = (AW.runtime.moneyUpdateToken or 0) + 1
    AW.runtime.lastEncounterSignature = nil
    AW.runtime.lastEncounterAt = 0
    AW.runtime.activeEncounter = nil
    AW.runtime.lastActivitySignature = nil
    AW.runtime.lastActivityAt = 0
    AW.runtime.lastOutdoorActivityAt = 0
    AW.runtime.lastOutdoorActivityKind = nil
    AW.runtime.activePreyQuestID = nil
    AW.runtime.activePrey = nil
    AW.runtime.activeDelve = nil
    AW.runtime.activeDungeon = nil
    AW.runtime.lastDungeonCompletionAt = 0
end
