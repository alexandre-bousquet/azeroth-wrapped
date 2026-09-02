local ADDON_NAME, AW = ...

AW.Tracker = CreateFrame("Frame")
local Tracker = AW.Tracker
local Database = AW.Database
local Util = AW.Util

local NPC_EVENTS = {
    GOSSIP_SHOW = "gossip",
    MERCHANT_SHOW = "merchant",
    QUEST_GREETING = "quest",
    QUEST_DETAIL = "quest",
    BANKFRAME_OPENED = "bank",
    GUILDBANKFRAME_OPENED = "guildBank",
    TRAINER_SHOW = "trainer",
    TAXIMAP_OPENED = "flightMaster",
    AUCTION_HOUSE_SHOW = "auctionHouse",
    MAIL_SHOW = "mailbox",
    PET_STABLE_SHOW = "stableMaster",
    TRANSMOGRIFY_OPEN = "transmogrifier",
    VOID_STORAGE_CONTENTS_UPDATE = "voidStorage",
}

local NPC_INTERACTION_TYPES = {}

local function addNPCInteractionType(typeName, service)
    local interactionTypes = Enum and Enum.PlayerInteractionType
    local interactionType = interactionTypes and interactionTypes[typeName]
    if interactionType ~= nil then
        NPC_INTERACTION_TYPES[interactionType] = service
    end
end

addNPCInteractionType("Gossip", "gossip")
addNPCInteractionType("Merchant", "merchant")
addNPCInteractionType("QuestGiver", "quest")
addNPCInteractionType("Banker", "bank")
addNPCInteractionType("AccountBanker", "bank")
addNPCInteractionType("GuildBanker", "guildBank")
addNPCInteractionType("Auctioneer", "auctionHouse")
addNPCInteractionType("MailInfo", "mailbox")
addNPCInteractionType("Transmogrifier", "transmogrifier")
addNPCInteractionType("VoidStorageBanker", "voidStorage")
addNPCInteractionType("ItemUpgrade", "itemUpgrade")
addNPCInteractionType("ProfessionsCustomerOrder", "craftingOrders")
addNPCInteractionType("ScrappingMachine", "scrapping")

local NPC_TOOLTIP_NAME = ADDON_NAME .. "NPCTitleScannerTooltip"
local npcTooltip = CreateFrame("GameTooltip", NPC_TOOLTIP_NAME, UIParent, "GameTooltipTemplate")
npcTooltip:SetOwner(UIParent, "ANCHOR_NONE")

local function isSecret(value)
    return issecretvalue and issecretvalue(value)
end

local function getPlayerAFKState()
    if not UnitIsAFK then
        return false
    end

    local afkState = UnitIsAFK("player")
    if isSecret(afkState) then
        return AW.runtime.playerIsAFK == true
    end

    local isAFK = afkState == true
    AW.runtime.playerIsAFK = isAFK
    return isAFK
end

local function getNPCID(guid)
    if isSecret(guid) or not guid then
        return nil
    end

    local unitType, _, _, _, _, npcID = strsplit("-", guid)
    if unitType == "Creature" or unitType == "Vehicle" then
        return tonumber(npcID)
    end

    return nil
end

local function cleanTooltipText(text)
    if type(text) ~= "string" or isSecret(text) then
        return nil
    end

    text = string.gsub(text, "|c%x%x%x%x%x%x%x%x", "")
    text = string.gsub(text, "|r", "")
    return strtrim(text)
end

local function isUnitLevelText(text)
    local levelTemplate = cleanTooltipText(TOOLTIP_UNIT_LEVEL)
    if not levelTemplate then
        return false
    end

    local markerStart = string.find(levelTemplate, "%s", 1, true)
    local prefix = markerStart and string.sub(levelTemplate, 1, markerStart - 1) or levelTemplate
    prefix = string.lower(strtrim(prefix))
    return prefix ~= "" and string.sub(string.lower(text), 1, #prefix) == prefix
end

local function extractNPCTitle(text, allowPlainText)
    text = cleanTooltipText(text)
    if not text then
        return nil
    end

    local title = string.match(text, "^%s*<(.+)>%s*$")
    if title and title ~= "" then
        return title
    end

    if allowPlainText and text ~= "" and not isUnitLevelText(text) then
        return text
    end

    return nil
end

local function getNPCTitle()
    if C_TooltipInfo and C_TooltipInfo.GetUnit then
        local ok, tooltip = pcall(C_TooltipInfo.GetUnit, "npc")
        if ok and type(tooltip) == "table" and type(tooltip.lines) == "table" then
            local titleLine = tooltip.lines[2]
            local title = titleLine and extractNPCTitle(titleLine.leftText, #tooltip.lines > 2)
            if title then
                return title
            end
        end
    end

    npcTooltip:ClearLines()
    local ok = pcall(npcTooltip.SetUnit, npcTooltip, "npc")
    if ok then
        local fontString = _G[NPC_TOOLTIP_NAME .. "TextLeft2"]
        local title = fontString and extractNPCTitle(fontString:GetText(), npcTooltip:NumLines() > 2)
        if title then
            npcTooltip:Hide()
            return title
        end
    end
    npcTooltip:Hide()

    return nil
end

local function unitCheck(api, ...)
    if not api then
        return false
    end

    local ok, value = pcall(api, ...)
    if not ok or isSecret(value) then
        return false
    end
    return value == true
end

local function isMountNPC(guid)
    if not isSecret(guid) and guid and string.match(guid, "^Vehicle%-") then
        return true
    end

    return unitCheck(UnitIsUnit, "npc", "vehicle")
        or unitCheck(UnitInVehicle, "npc")
        or unitCheck(UnitPlayerControlled, "npc")
        or unitCheck(UnitIsOtherPlayersPet, "npc")
        or unitCheck(UnitIsMinion, "npc")
end

local function getCoordinates(position)
    if not position or isSecret(position) then
        return nil, nil
    end

    local ok
    local x, y
    if position.GetXY then
        ok, x, y = pcall(position.GetXY, position)
        if not ok then
            return nil, nil
        end
    else
        x, y = position.x, position.y
    end

    if isSecret(x) or isSecret(y) then
        return nil, nil
    end

    x = tonumber(x)
    y = tonumber(y)
    if not x or not y or (x == 0 and y == 0) or x < 0 or x > 1 or y < 0 or y > 1 then
        return nil, nil
    end

    return x, y
end

local function getWorldUnitMapPosition(mapID, unitToken)
    if not UnitPosition or not C_Map or not C_Map.GetMapPosFromWorldPos or not CreateVector2D then
        return nil, nil
    end

    local ok, worldY, worldX, _, instanceID = pcall(UnitPosition, unitToken)
    if not ok or isSecret(worldX) or isSecret(worldY) or isSecret(instanceID) then
        return nil, nil
    end

    worldX = tonumber(worldX)
    worldY = tonumber(worldY)
    instanceID = tonumber(instanceID)
    if not worldX or not worldY or not instanceID then
        return nil, nil
    end

    local worldPosition
    ok, worldPosition = pcall(CreateVector2D, worldY, worldX)
    if not ok or not worldPosition then
        return nil, nil
    end

    local position
    ok, _, position = pcall(C_Map.GetMapPosFromWorldPos, instanceID, worldPosition, mapID)
    if not ok then
        return nil, nil
    end

    return getCoordinates(position)
end

local function getMapPosition(mapID, unitToken)
    if not mapID or not unitToken or not C_Map then
        return nil, nil
    end

    if C_Map.GetPlayerMapPosition then
        local ok, position = pcall(C_Map.GetPlayerMapPosition, mapID, unitToken)
        if ok then
            local x, y = getCoordinates(position)
            if x and y then
                return x, y
            end
        end
    end

    return getWorldUnitMapPosition(mapID, unitToken)
end

local function getNPCMapPosition(mapID)
    local x, y = getMapPosition(mapID, "npc")
    if x and y then
        return x, y, "npc"
    end

    x, y = getMapPosition(mapID, "player")
    if x and y then
        return x, y, "player"
    end

    return nil, nil, nil
end

local function getMapInfo()
    local mapID = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player") or nil
    local mapName

    if mapID and C_Map.GetMapInfo then
        local info = C_Map.GetMapInfo(mapID)
        mapName = info and info.name
    end

    return mapID, mapName or GetZoneText() or AW.L.UNKNOWN_ZONE
end

local function getCanonicalWorldMap(mapID)
    if not mapID or not C_Map or not C_Map.GetMapInfo then
        return mapID, nil
    end

    local info = C_Map.GetMapInfo(mapID)
    local zoneMapType = Enum and Enum.UIMapType and Enum.UIMapType.Zone
    local attempts = 0

    while info and zoneMapType and info.mapType and info.mapType > zoneMapType
        and info.parentMapID and info.parentMapID > 0 and attempts < 10
    do
        mapID = info.parentMapID
        info = C_Map.GetMapInfo(mapID)
        attempts = attempts + 1
    end

    if info and zoneMapType and info.mapType ~= zoneMapType then
        return nil, nil
    end

    return mapID, info and info.name
end

local function getTrackedZoneInfo()
    local inInstance, instanceType = IsInInstance()
    local uiMapID = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player") or nil

    if inInstance and instanceType ~= "none" then
        local instanceName, _, _, _, _, _, _, instanceID = GetInstanceInfo()
        if not instanceID or instanceID <= 0 or not instanceName or instanceName == "" then
            return nil
        end

        return string.format("instance:%d", instanceID), {
            instanceID = instanceID,
            instanceType = instanceType,
            mapID = uiMapID,
            name = instanceName,
        }
    end

    local mapID, mapName = getCanonicalWorldMap(uiMapID)
    if not mapID then
        return nil
    end

    return tostring(mapID), {
        mapID = mapID,
        name = mapName or GetRealZoneText() or GetZoneText() or AW.L.UNKNOWN_ZONE,
    }
end

local function getLocation()
    local mapID, mapName = getMapInfo()
    local subZone = GetSubZoneText and GetSubZoneText() or ""
    local displayName = subZone ~= "" and subZone or mapName
    local key = string.format("%s:%s", tostring(mapID or 0), displayName or "")
    return key, mapID, displayName
end

local function getActivity()
    local inInstance, instanceType = IsInInstance()

    if inInstance then
        if instanceType == "party" then
            return "party"
        elseif instanceType == "raid" then
            return "raid"
        elseif instanceType == "pvp" then
            return "pvp"
        elseif instanceType == "arena" then
            return "arena"
        elseif instanceType == "scenario" then
            return "scenario"
        end
        return "unknown"
    end

    if IsResting and IsResting() then
        return "resting"
    end

    return "world"
end

local function ensureDayCharacter(day, characterKey, character)
    if not day.characters[characterKey] then
        day.characters[characterKey] = {
            key = characterKey,
            name = character.name,
            realm = character.realm,
            classFile = character.classFile,
            seconds = 0,
            activeSeconds = 0,
            afkSeconds = 0,
            deaths = 0,
        }
    end

    local dayCharacter = day.characters[characterKey]
    dayCharacter.name = character.name
    dayCharacter.realm = character.realm
    dayCharacter.className = character.className
    dayCharacter.classFile = character.classFile
    return dayCharacter
end

local function ensureDayMoneyCharacter(day, characterKey, startingBalance, character)
    local wallets = day.money.characters

    if not wallets[characterKey] then
        wallets[characterKey] = {
            characterKey = characterKey,
            start = startingBalance,
            last = startingBalance,
            net = 0,
            earned = 0,
            spent = 0,
            changes = 0,
        }
    end

    local wallet = wallets[characterKey]
    if character then
        wallet.name = character.name
        wallet.realm = character.realm
    end
    return wallet
end

local function fetchWarbandMoney()
    local accountBankType = Enum and Enum.BankType and Enum.BankType.Account
    if not accountBankType or not C_Bank or not C_Bank.FetchDepositedMoney then
        return nil
    end

    if C_PlayerInfo and C_PlayerInfo.HasAccountInventoryLock then
        local lockOK, hasAccountInventoryLock = pcall(C_PlayerInfo.HasAccountInventoryLock)
        if not lockOK or not hasAccountInventoryLock then
            return nil
        end
    end

    local moneyOK, warbandMoney = pcall(C_Bank.FetchDepositedMoney, accountBankType)
    if not moneyOK or isSecret(warbandMoney) or type(warbandMoney) ~= "number" then
        return nil
    end

    return math.max(0, warbandMoney)
end

local function getTrackedMoney()
    local playerMoney = tonumber(GetMoney()) or 0
    local warbandMoney = fetchWarbandMoney()
    local trackedWarbandMoney = warbandMoney

    if trackedWarbandMoney == nil then
        trackedWarbandMoney = tonumber(Database.db.meta.warbandMoneyCopper) or 0
    end

    return playerMoney + trackedWarbandMoney, playerMoney, warbandMoney, trackedWarbandMoney
end

function Tracker:MarkSessionForDay(day, dayKey)
    if AW.runtime.lastDayKey ~= dayKey then
        day.sessionCount = (day.sessionCount or 0) + 1
        AW.runtime.lastDayKey = dayKey
    end
end

function Tracker:RecordZoneVisit()
    if not AW.runtime.loggedIn or not Database.db.settings.enabled then
        return
    end

    local day = Database:GetDay()
    local zoneKey, zoneInfo = getTrackedZoneInfo()
    if not zoneKey or not zoneInfo then
        return
    end

    local isNewZoneForDay = not day.zones[zoneKey]
    if AW.runtime.lastZoneKey == zoneKey and not isNewZoneForDay then
        return
    end

    if isNewZoneForDay then
        day.zones[zoneKey] = {
            instanceID = zoneInfo.instanceID,
            instanceType = zoneInfo.instanceType,
            mapID = zoneInfo.mapID,
            name = zoneInfo.name,
            seconds = 0,
            visits = 0,
        }
    end
    day.zones[zoneKey].visits = (day.zones[zoneKey].visits or 0) + 1
    AW.runtime.lastZoneKey = zoneKey
end

function Tracker:RecordDeath()
    if not Database.db.settings.enabled then
        return
    end

    local day = Database:GetDay()
    local locationKey, mapID, locationName = getLocation()
    local characterKey, character = Database:TouchCharacter()
    local dayCharacter = ensureDayCharacter(day, characterKey, character)

    day.deaths.total = (day.deaths.total or 0) + 1
    dayCharacter.deaths = (dayCharacter.deaths or 0) + 1

    if not day.deaths.locations[locationKey] then
        day.deaths.locations[locationKey] = {
            mapID = mapID,
            name = locationName,
            deaths = 0,
        }
    end
    day.deaths.locations[locationKey].deaths = day.deaths.locations[locationKey].deaths + 1

    local activeEncounter = AW.runtime.activeEncounter
    local deathDetail = {
        timestamp = Util:Now(),
        characterKey = characterKey,
        mapID = mapID,
        locationName = locationName,
        category = activeEncounter and "boss" or "unknown",
        encounterID = activeEncounter and activeEncounter.encounterID or nil,
        encounterName = activeEncounter and activeEncounter.encounterName or nil,
    }
    local deathDatabase = Database.db
    day.deaths.details[#day.deaths.details + 1] = deathDetail
    Database.db.meta.updatedAt = deathDetail.timestamp

    local function safeField(value)
        if value == nil or isSecret(value) then
            return nil
        end
        local valueType = type(value)
        if valueType == "string" or valueType == "number" or valueType == "boolean" then
            return value
        end
        return nil
    end

    local function captureRecap()
        if Database.db ~= deathDatabase then
            return true
        end

        if not C_DeathRecap or not C_DeathRecap.GetRecapEvents then
            return false
        end

        local ok, events = pcall(C_DeathRecap.GetRecapEvents)
        if not ok or isSecret(events) or type(events) ~= "table" then
            return false
        end

        local fatalEvent = events[1]
        if isSecret(fatalEvent) or type(fatalEvent) ~= "table" then
            return false
        end

        local eventType = safeField(fatalEvent.event)
        local environmentalType = safeField(fatalEvent.environmentalType)
        if type(environmentalType) == "string" then
            environmentalType = string.upper(environmentalType)
        end

        deathDetail.event = eventType
        deathDetail.environmentalType = environmentalType
        deathDetail.spellID = safeField(fatalEvent.spellId)
        deathDetail.spellName = safeField(fatalEvent.spellName)
        deathDetail.amount = safeField(fatalEvent.amount)
        deathDetail.overkill = safeField(fatalEvent.overkill)

        local hideCaster = safeField(fatalEvent.hideCaster)
        if not hideCaster then
            deathDetail.sourceName = safeField(fatalEvent.sourceName)
        end

        if eventType == "ENVIRONMENTAL_DAMAGE" and environmentalType == "FALLING" then
            deathDetail.category = "fall"
        elseif eventType == "ENVIRONMENTAL_DAMAGE" then
            deathDetail.category = "environment"
        elseif deathDetail.encounterName then
            deathDetail.category = "boss"
        else
            deathDetail.category = "attack"
        end

        Database.db.meta.updatedAt = Util:Now()
        if AW.UI and AW.UI.detailKey == "fate" and AW.UI.RefreshDetails then
            AW.UI:RefreshDetails()
        end
        return true
    end

    if C_Timer and C_Timer.After then
        C_Timer.After(0.2, function()
            if not captureRecap() then
                C_Timer.After(0.8, captureRecap)
            end
        end)
    else
        captureRecap()
    end
end

function Tracker:StartEncounter(encounterID, encounterName, difficultyID, groupSize)
    AW.runtime.activeEncounter = {
        encounterID = encounterID,
        encounterName = encounterName,
        difficultyID = difficultyID,
        groupSize = groupSize,
    }
end

function Tracker:EndEncounter(encounterID)
    AW.runtime.activeEncounter = nil
end

function Tracker:RecordNPCInteraction(service)
    if not Database.db.settings.enabled or not Database.db.settings.trackNPCs then
        return false
    end

    local name = UnitName("npc")
    if not name or name == "" then
        return false
    end

    local day = Database:GetDay()
    local mapID, mapName = getMapInfo()
    local x, y, positionSource = getNPCMapPosition(mapID)
    local guid = UnitGUID("npc")
    local npcID = getNPCID(guid)
    local title = getNPCTitle()
    local mountNPC = isMountNPC(guid)
    local key = string.format("%s:%s", tostring(mapID or 0), name)

    if not day.npcs[key] then
        day.npcs[key] = { name = name, mapID = mapID, interactions = 0, services = {} }
    end

    local npc = day.npcs[key]
    npc.services = type(npc.services) == "table" and npc.services or {}
    npc.name = name
    npc.guid = not isSecret(guid) and guid or npc.guid
    npc.npcID = npcID or npc.npcID
    npc.title = title or npc.title
    npc.isMount = mountNPC or npc.isMount
    npc.mapID = mapID or npc.mapID
    npc.mapName = mapName or npc.mapName
    npc.zoneName = (GetSubZoneText and GetSubZoneText() ~= "" and GetSubZoneText()) or npc.zoneName
    npc.lastSeenAt = Util:Now()

    local hasExactPosition = npc.positionSource == "npc"
    if x and y and (positionSource == "npc" or not hasExactPosition) then
        npc.x = x
        npc.y = y
        npc.positionSource = positionSource
        npc.positionSeenAt = npc.lastSeenAt
    end

    if service then
        npc.services[service] = true
    end

    local now = GetTime()
    if AW.runtime.lastNPC ~= key or (now - AW.runtime.lastNPCAt) >= 5 then
        npc.interactions = (npc.interactions or 0) + 1
        AW.runtime.lastNPC = key
        AW.runtime.lastNPCAt = now
    end

    Database.db.meta.updatedAt = npc.lastSeenAt
    return true, positionSource == "npc"
end

function Tracker:RecordPlayerInteraction(interactionType)
    local service = NPC_INTERACTION_TYPES[interactionType]
    if not service then
        return
    end

    local recorded, hasExactPosition = self:RecordNPCInteraction(service)
    if (not recorded or not hasExactPosition) and C_Timer and C_Timer.After then
        C_Timer.After(0.1, function()
            if AW.runtime.loggedIn then
                Tracker:RecordNPCInteraction(service)
            end
        end)
    end
end

function Tracker:RecordMoneyBaseline()
    if not GetMoney then
        return
    end

    local currentMoney, playerMoney, warbandMoney, trackedWarbandMoney = getTrackedMoney()
    local now = Util:Now()
    local day, dayKey = Database:GetDay(now)

    AW.runtime.lastTrackedMoneyCopper = currentMoney
    AW.runtime.lastTrackedWarbandMoneyCopper = trackedWarbandMoney
    AW.runtime.hasLiveWarbandMoney = warbandMoney ~= nil
    AW.runtime.moneyDayKey = dayKey

    if not Database.db.settings.enabled or not Database.db.settings.trackMoney then
        return
    end

    local characterKey, character = Database:TouchCharacter(now)
    local wallet = ensureDayMoneyCharacter(day, characterKey, currentMoney, character)
    wallet.last = currentMoney
    character.moneyCopper = playerMoney
    character.moneyUpdatedAt = now
    if warbandMoney ~= nil then
        Database.db.meta.warbandMoneyCopper = warbandMoney
        Database.db.meta.warbandMoneyUpdatedAt = now
    end
end

function Tracker:RecordMoneyChange()
    if not GetMoney then
        return
    end

    local currentMoney, playerMoney, warbandMoney, trackedWarbandMoney = getTrackedMoney()
    local previousMoney = AW.runtime.lastTrackedMoneyCopper
    local now = Util:Now()
    local day, dayKey = Database:GetDay(now)

    if previousMoney == nil then
        AW.runtime.lastTrackedMoneyCopper = currentMoney
        AW.runtime.lastTrackedWarbandMoneyCopper = trackedWarbandMoney
        AW.runtime.hasLiveWarbandMoney = warbandMoney ~= nil
        AW.runtime.moneyDayKey = dayKey
        self:RecordMoneyBaseline()
        return
    end

    if warbandMoney ~= nil and not AW.runtime.hasLiveWarbandMoney then
        previousMoney = previousMoney - (AW.runtime.lastTrackedWarbandMoneyCopper or 0) + trackedWarbandMoney
    end

    if not Database.db.settings.enabled or not Database.db.settings.trackMoney then
        AW.runtime.lastTrackedMoneyCopper = currentMoney
        AW.runtime.lastTrackedWarbandMoneyCopper = trackedWarbandMoney
        AW.runtime.hasLiveWarbandMoney = AW.runtime.hasLiveWarbandMoney or warbandMoney ~= nil
        AW.runtime.moneyDayKey = dayKey
        return
    end

    local characterKey, character = Database:TouchCharacter(now)
    local wallet = ensureDayMoneyCharacter(day, characterKey, previousMoney, character)
    local delta = currentMoney - previousMoney

    if delta ~= 0 then
        wallet.net = (wallet.net or 0) + delta
        wallet.changes = (wallet.changes or 0) + 1
        day.money.net = (day.money.net or 0) + delta
        day.money.changes = (day.money.changes or 0) + 1

        if delta > 0 then
            wallet.earned = (wallet.earned or 0) + delta
            day.money.earned = (day.money.earned or 0) + delta
        else
            local spent = math.abs(delta)
            wallet.spent = (wallet.spent or 0) + spent
            day.money.spent = (day.money.spent or 0) + spent
        end
    end

    wallet.last = currentMoney
    character.moneyCopper = playerMoney
    character.moneyUpdatedAt = now
    if warbandMoney ~= nil then
        Database.db.meta.warbandMoneyCopper = warbandMoney
        Database.db.meta.warbandMoneyUpdatedAt = now
    end
    Database.db.meta.updatedAt = now
    AW.runtime.lastTrackedMoneyCopper = currentMoney
    AW.runtime.lastTrackedWarbandMoneyCopper = trackedWarbandMoney
    AW.runtime.hasLiveWarbandMoney = AW.runtime.hasLiveWarbandMoney or warbandMoney ~= nil
    AW.runtime.moneyDayKey = dayKey
end

function Tracker:ScheduleMoneyChange()
    AW.runtime.moneyUpdateToken = (AW.runtime.moneyUpdateToken or 0) + 1
    local updateToken = AW.runtime.moneyUpdateToken

    if not C_Timer or not C_Timer.After then
        self:RecordMoneyChange()
        return
    end

    C_Timer.After(0.1, function()
        if AW.runtime.loggedIn and AW.runtime.moneyUpdateToken == updateToken then
            Tracker:RecordMoneyChange()
        end
    end)
end

function Tracker:RecordCompletedActivity(activityKey, activity)
    if not Database.db.settings.enabled or not Database.db.settings.trackEncounters then
        return
    end

    activity = activity or {}
    local elapsed = GetTime()
    local signature = string.format("%s:%s", tostring(activity.category or "outdoor"), tostring(activityKey))

    local recentlyRecorded = (elapsed - (AW.runtime.lastActivityAt or 0)) < 5
    if AW.runtime.lastActivitySignature == signature and recentlyRecorded then
        return
    end

    if activity.category == "outdoor" and (AW.runtime.lastOutdoorActivityAt or 0) > 0
        and (elapsed - AW.runtime.lastOutdoorActivityAt) < 5
    then
        local currentIsScenario = activity.kind == "scenario" or activity.kind == "delve"
        local previousKind = AW.runtime.lastOutdoorActivityKind
        local previousIsScenario = previousKind == "scenario" or previousKind == "delve"
        if currentIsScenario ~= previousIsScenario then
            return
        end
    end

    local now = Util:Now()
    local day = Database:GetDay(now)
    local completed = day.completedActivities
    local category = activity.category == "raid" and "raid"
        or activity.category == "dungeon" and "dungeon"
        or "outdoor"

    completed.total = (completed.total or 0) + 1
    completed[category] = (completed[category] or 0) + 1

    if not completed.entries[activityKey] then
        completed.entries[activityKey] = { completions = 0 }
    end

    local entry = completed.entries[activityKey]
    for field, value in pairs(activity) do
        if value ~= nil then
            entry[field] = value
        end
    end
    local runSeconds = tonumber(activity.runSeconds)
    if runSeconds and runSeconds > 0
        and (not entry.bestRunSeconds or runSeconds < entry.bestRunSeconds)
    then
        entry.bestRunSeconds = runSeconds
    end
    entry.category = category
    entry.completions = (entry.completions or 0) + 1
    entry.lastCompletedAt = now

    local history = type(completed.history) == "table" and completed.history or {}
    completed.history = history
    local historyEntry = {
        activityKey = activityKey,
        category = category,
        completions = 1,
        completedAt = now,
        sequence = #history + 1,
    }
    for field, value in pairs(activity) do
        if value ~= nil then
            historyEntry[field] = value
        end
    end
    historyEntry.category = category
    historyEntry.completions = 1
    historyEntry.completedAt = now
    history[#history + 1] = historyEntry

    Database.db.meta.updatedAt = now
    AW.runtime.lastActivitySignature = signature
    AW.runtime.lastActivityAt = elapsed
    if category == "outdoor" then
        AW.runtime.lastOutdoorActivityAt = elapsed
        AW.runtime.lastOutdoorActivityKind = activity.kind
    elseif category == "dungeon" then
        AW.runtime.lastDungeonCompletionAt = elapsed
    end
end

local function getQuestTitle(questID)
    if not C_QuestLog or type(C_QuestLog.GetTitleForQuestID) ~= "function" then
        return nil
    end
    local ok, title = pcall(C_QuestLog.GetTitleForQuestID, questID)
    return ok and title or nil
end

local function getPreyDisplayInfo(title)
    if type(title) ~= "string" or title == "" then
        return title, AW.L.DETAIL_PREY_NORMAL
    end

    -- Hard and Nightmare hunts have a localized difficulty suffix in their
    -- quest title. Normal hunts have no suffix.
    local name, difficultyName = title:match("^(.-)%s*%(([^()]*)%)%s*$")
    if name and name ~= "" and difficultyName and difficultyName ~= "" then
        return name, difficultyName
    end
    return title, AW.L.DETAIL_PREY_NORMAL
end

function Tracker:UpdateActivePreyQuest()
    local questID
    if C_QuestLog and type(C_QuestLog.GetActivePreyQuest) == "function" then
        local ok, activeQuestID = pcall(C_QuestLog.GetActivePreyQuest)
        if ok then
            questID = activeQuestID
        end
    end
    -- Keep the last known prey quest until its turn-in event. The quest log can
    -- refresh and remove it just before QUEST_TURNED_IN is dispatched.
    if questID then
        AW.runtime.activePreyQuestID = questID
        local title = getQuestTitle(questID)
        local name, difficultyName = getPreyDisplayInfo(title)
        local activePrey = AW.runtime.activePrey
        if not activePrey or activePrey.questID ~= questID then
            activePrey = {
                questID = questID,
                startedAt = GetTime(),
            }
            AW.runtime.activePrey = activePrey
        end
        activePrey.name = name or activePrey.name
        activePrey.difficultyName = difficultyName or activePrey.difficultyName
    end
end

local function questFlag(functionName, questID)
    local api = C_QuestLog and C_QuestLog[functionName]
    if type(api) ~= "function" then
        return false
    end
    local ok, value = pcall(api, questID)
    return ok and value == true
end

function Tracker:RecordOutdoorQuest(questID)
    questID = tonumber(questID)
    if not questID then
        return
    end

    local isPrey = questID == AW.runtime.activePreyQuestID
    local isWorldQuest = questFlag("IsWorldQuest", questID)
    local isTask = questFlag("IsQuestTask", questID)
    local isInvasion = questFlag("IsQuestInvasion", questID)
    local isThreat = questFlag("IsThreatQuest", questID)
    if not isPrey and not isWorldQuest and not isTask and not isInvasion and not isThreat then
        return
    end

    local name = getQuestTitle(questID)
    local difficultyName
    local runSeconds
    if isPrey then
        name, difficultyName = getPreyDisplayInfo(name)
        local activePrey = AW.runtime.activePrey
        if activePrey and activePrey.questID == questID then
            name = activePrey.name or name
            difficultyName = activePrey.difficultyName or difficultyName
            local startedAt = tonumber(activePrey.startedAt)
            if startedAt then
                runSeconds = math.max(0, GetTime() - startedAt)
            end
        end
    end

    local kind = isPrey and "prey" or (isTask and not isWorldQuest and "bonusObjective" or "worldQuest")
    self:RecordCompletedActivity("quest:" .. tostring(questID), {
        questID = questID,
        name = name or AW.L.UNKNOWN_ACTIVITY,
        category = "outdoor",
        kind = kind,
        instanceName = GetZoneText and GetZoneText() or nil,
        difficultyName = difficultyName,
        runSeconds = runSeconds,
    })
end

local function getScenarioInfo()
    local scenarioName
    local scenarioID
    if C_ScenarioInfo and type(C_ScenarioInfo.GetScenarioInfo) == "function" then
        local ok, info = pcall(C_ScenarioInfo.GetScenarioInfo)
        if ok and type(info) == "table" then
            scenarioName = info.name
            scenarioID = info.scenarioID
        end
    elseif C_Scenario and type(C_Scenario.GetInfo) == "function" then
        local values = { pcall(C_Scenario.GetInfo) }
        if values[1] then
            scenarioName = values[2]
            scenarioID = values[14]
        end
    end
    return scenarioName, scenarioID
end

local function extractDelveTier(text)
    if type(text) ~= "string" or text == "" then
        return nil
    end

    local clean = string.gsub(string.gsub(text, "|c%x%x%x%x%x%x%x%x", ""), "|r", "")
    local localizedPrefix = type(AW.L.DETAIL_DELVE_TIER) == "string"
        and string.match(AW.L.DETAIL_DELVE_TIER, "^%s*(.-)%s*%%d")
        or nil
    local prefixes = { "Tier", "tier", "Niveau", "niveau", "Échelon", "échelon" }
    if localizedPrefix and localizedPrefix ~= "" then
        table.insert(prefixes, 1, localizedPrefix)
    end

    for _, prefix in ipairs(prefixes) do
        if prefix and prefix ~= "" then
            local _, prefixEnd = string.find(clean, prefix, 1, true)
            if prefixEnd then
                local tier = tonumber(string.match(string.sub(clean, prefixEnd + 1), "(%d+)"))
                if tier and tier >= 1 and tier <= 11 then
                    return tier
                end
            end
        end
    end

    return nil
end

local function getObjectiveTrackerDelveTier()
    local root = _G.ObjectiveTrackerFrame or _G.ScenarioObjectiveTracker
    if not root then
        return nil
    end

    local visited = {}
    local function scan(frame)
        if not frame or visited[frame] then
            return nil
        end
        visited[frame] = true

        if frame.IsForbidden and frame:IsForbidden() then
            return nil
        end

        if frame.GetNumRegions and frame.GetRegions then
            for index = 1, frame:GetNumRegions() do
                local region = select(index, frame:GetRegions())
                if region and region.GetObjectType and region:GetObjectType() == "FontString"
                    and (not region.IsShown or region:IsShown())
                then
                    local tier = extractDelveTier(region:GetText())
                    if tier then
                        return tier
                    end
                end
            end
        end

        if frame.GetNumChildren and frame.GetChildren then
            for index = 1, frame:GetNumChildren() do
                local tier = scan(select(index, frame:GetChildren()))
                if tier then
                    return tier
                end
            end
        end

        return nil
    end

    local ok, tier = pcall(scan, root)
    return ok and tier or nil
end

local function getActiveDelveTier()
    if C_DelvesUI and type(C_DelvesUI.GetActiveDelveTier) == "function" then
        local ok, tierInfo = pcall(C_DelvesUI.GetActiveDelveTier)
        local tier = ok and type(tierInfo) == "table" and tonumber(tierInfo.tier) or nil
        if tier and tier >= 1 and tier <= 11 then
            return tierInfo
        end
    end

    local _, _, _, difficultyName = GetInstanceInfo()
    local scenarioName = getScenarioInfo()
    local tier = extractDelveTier(difficultyName) or extractDelveTier(scenarioName)
    if not tier and C_Scenario and type(C_Scenario.GetStepInfo) == "function" then
        local ok, stepName = pcall(C_Scenario.GetStepInfo)
        if ok then
            tier = extractDelveTier(stepName)
        end
    end
    tier = tier or getObjectiveTrackerDelveTier()

    return tier and { tier = tier } or nil
end

function Tracker:UpdateActiveDelve()
    if not C_DelvesUI or type(C_DelvesUI.HasActiveDelve) ~= "function" then
        return nil
    end

    local ok, hasActiveDelve = pcall(C_DelvesUI.HasActiveDelve)
    if not ok or not hasActiveDelve then
        -- Preserve the last data briefly: Blizzard can close the active Delve
        -- before SCENARIO_COMPLETED reaches addons.
        if AW.runtime.activeDelve then
            AW.runtime.activeDelve.isActive = false
        end
        return AW.runtime.activeDelve
    end

    local scenarioName, scenarioID = getScenarioInfo()
    local instanceName, _, _, _, _, _, _, instanceID
    if GetInstanceInfo then
        instanceName, _, _, _, _, _, _, instanceID = GetInstanceInfo()
    end
    local mapID = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player") or nil
    local identifier = scenarioID or instanceID or mapID or scenarioName or instanceName or "unknown"
    local tierInfo = getActiveDelveTier()

    local activeDelve = AW.runtime.activeDelve
    if not activeDelve or activeDelve.identifier ~= identifier or activeDelve.isActive == false then
        activeDelve = {
            identifier = identifier,
            startedAt = GetTime(),
        }
        AW.runtime.activeDelve = activeDelve
    end
    activeDelve.isActive = true
    activeDelve.scenarioID = scenarioID or activeDelve.scenarioID
    activeDelve.name = scenarioName or activeDelve.name
    activeDelve.instanceID = instanceID or activeDelve.instanceID
    activeDelve.instanceName = instanceName or activeDelve.instanceName
    activeDelve.delveTier = tierInfo and tonumber(tierInfo.tier) or activeDelve.delveTier
    activeDelve.difficultyID = tierInfo and tonumber(tierInfo.difficultyID) or activeDelve.difficultyID
    return activeDelve
end

function Tracker:StartDungeonRun(challengeMapID, resetStart)
    local _, detectedType = IsInInstance()
    if detectedType ~= "party" then
        AW.runtime.activeDungeon = nil
        return nil
    end

    local instanceName, instanceType, difficultyID, difficultyName, _, _, _, instanceID
    if GetInstanceInfo then
        instanceName, instanceType, difficultyID, difficultyName, _, _, _, instanceID = GetInstanceInfo()
    end

    local activeChallengeMapID = challengeMapID
    if not activeChallengeMapID and C_ChallengeMode
        and type(C_ChallengeMode.GetActiveChallengeMapID) == "function"
    then
        local ok, mapID = pcall(C_ChallengeMode.GetActiveChallengeMapID)
        if ok then
            activeChallengeMapID = mapID
        end
    end

    local keystoneLevel
    if activeChallengeMapID and C_ChallengeMode
        and type(C_ChallengeMode.GetActiveKeystoneInfo) == "function"
    then
        local ok, level = pcall(C_ChallengeMode.GetActiveKeystoneInfo)
        if ok then
            keystoneLevel = tonumber(level)
        end
    end

    local current = AW.runtime.activeDungeon
    local sameDungeon = current and current.instanceID == instanceID
    if sameDungeon and not resetStart then
        current.challengeMapID = activeChallengeMapID or current.challengeMapID
        current.keystoneLevel = keystoneLevel or current.keystoneLevel
        current.isChallengeMode = activeChallengeMapID ~= nil or current.isChallengeMode
        return current
    end

    current = {
        startedAt = GetTime(),
        instanceID = instanceID,
        instanceName = instanceName or AW.L.UNKNOWN_INSTANCE,
        instanceType = instanceType,
        difficultyID = difficultyID,
        difficultyName = difficultyName,
        challengeMapID = activeChallengeMapID,
        keystoneLevel = keystoneLevel,
        isChallengeMode = activeChallengeMapID ~= nil,
    }
    AW.runtime.activeDungeon = current
    return current
end

function Tracker:RecordDungeonCompletion()
    local _, instanceType = IsInInstance()
    if instanceType ~= "party" then
        return false
    end
    if (AW.runtime.lastDungeonCompletionAt or 0) > 0
        and (GetTime() - AW.runtime.lastDungeonCompletionAt) < 5
    then
        return true
    end

    local run = AW.runtime.activeDungeon or self:StartDungeonRun()
    if not run then
        return true
    end

    local challengeModeActive = run.isChallengeMode
    if not challengeModeActive and C_ChallengeMode
        and type(C_ChallengeMode.IsChallengeModeActive) == "function"
    then
        local ok, active = pcall(C_ChallengeMode.IsChallengeModeActive)
        challengeModeActive = ok and active == true
    end
    if challengeModeActive then
        return true
    end

    local runSeconds = math.max(0, GetTime() - (tonumber(run.startedAt) or GetTime()))
    local activityKey = string.format(
        "dungeon:%s:%s",
        tostring(run.instanceID or run.instanceName),
        tostring(run.difficultyID or 0)
    )
    self:RecordCompletedActivity(activityKey, {
        name = run.instanceName,
        category = "dungeon",
        kind = "dungeon",
        instanceID = run.instanceID,
        instanceName = run.instanceName,
        difficultyID = run.difficultyID,
        difficultyName = run.difficultyName,
        runSeconds = runSeconds,
    })
    AW.runtime.activeDungeon = nil
    return true
end

function Tracker:RecordChallengeModeCompletion()
    if not C_ChallengeMode or type(C_ChallengeMode.GetChallengeCompletionInfo) ~= "function" then
        return
    end

    local ok, info = pcall(C_ChallengeMode.GetChallengeCompletionInfo)
    if not ok or type(info) ~= "table" then
        return
    end

    local challengeMapID = tonumber(info.mapChallengeModeID)
    if not challengeMapID or challengeMapID == 0 then
        return
    end

    local dungeonName
    local instanceMapID
    if type(C_ChallengeMode.GetMapUIInfo) == "function" then
        local mapOK, name, _, _, _, _, mapID = pcall(C_ChallengeMode.GetMapUIInfo, challengeMapID)
        if mapOK then
            dungeonName = name
            instanceMapID = mapID
        end
    end

    local run = AW.runtime.activeDungeon or {}
    local keystoneLevel = tonumber(info.level) or tonumber(run.keystoneLevel) or 0
    local rawTime = tonumber(info.time) or 0
    local runSeconds = rawTime > 10000 and (rawTime / 1000) or rawTime
    local upgradeLevels = math.max(0, tonumber(info.keystoneUpgradeLevels) or 0)
    local activityKey = string.format(
        "dungeon:challenge:%s:%s",
        tostring(challengeMapID),
        tostring(keystoneLevel)
    )

    self:RecordCompletedActivity(activityKey, {
        name = dungeonName or run.instanceName or AW.L.UNKNOWN_INSTANCE,
        category = "dungeon",
        kind = "dungeon",
        instanceID = run.instanceID or instanceMapID,
        instanceName = dungeonName or run.instanceName,
        challengeMapID = challengeMapID,
        keystoneLevel = keystoneLevel,
        runSeconds = runSeconds,
        onTime = info.onTime == true,
        keystoneUpgradeLevels = upgradeLevels,
    })
    AW.runtime.activeDungeon = nil
end

function Tracker:RecordScenarioCompletion()
    local scenarioName, scenarioID = getScenarioInfo()

    local instanceName, instanceType, _, difficultyName, _, _, _, instanceID
    if GetInstanceInfo then
        instanceName, instanceType, _, difficultyName, _, _, _, instanceID = GetInstanceInfo()
    end
    if instanceType == "party" or instanceType == "raid" then
        return
    end

    local isDelve = false
    if C_ScenarioInfo and type(C_ScenarioInfo.IsTieredEntranceScenario) == "function" then
        local ok, value = pcall(C_ScenarioInfo.IsTieredEntranceScenario)
        isDelve = ok and value == true
    end

    local delveRun
    local tierInfo
    if isDelve then
        delveRun = self:UpdateActiveDelve() or AW.runtime.activeDelve
        tierInfo = getActiveDelveTier()
    end

    local runSeconds
    if delveRun and tonumber(delveRun.startedAt) then
        runSeconds = math.max(0, GetTime() - tonumber(delveRun.startedAt))
    end
    local delveTier = tierInfo and tonumber(tierInfo.tier)
        or (delveRun and tonumber(delveRun.delveTier))
    local delveDifficultyID = tierInfo and tonumber(tierInfo.difficultyID)
        or (delveRun and tonumber(delveRun.difficultyID))

    local mapID = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player") or nil
    local identifier = scenarioID or instanceID or mapID or scenarioName or "unknown"
    local activityKey = "scenario:" .. tostring(identifier)
    self:RecordCompletedActivity(activityKey, {
        scenarioID = scenarioID,
        name = isDelve and (instanceName or scenarioName)
            or scenarioName
            or instanceName
            or AW.L.UNKNOWN_ACTIVITY,
        category = "outdoor",
        kind = isDelve and "delve" or "scenario",
        instanceID = instanceID,
        instanceName = instanceName,
        difficultyName = difficultyName,
        difficultyID = isDelve and delveDifficultyID or nil,
        delveTier = isDelve and delveTier or nil,
        runSeconds = isDelve and runSeconds or nil,
    })
    if isDelve then
        AW.runtime.activeDelve = nil
    end
end

function Tracker:RecordEncounter(encounterID, encounterName, difficultyID, groupSize, success)
    if success ~= 1 and success ~= true then
        return
    end

    if not Database.db.settings.enabled or not Database.db.settings.trackEncounters then
        return
    end

    local _, detectedType = IsInInstance()
    local instanceName
    local instanceType
    local instanceDifficultyID
    local difficultyName
    local instanceID

    if GetInstanceInfo then
        instanceName, instanceType, instanceDifficultyID, difficultyName, _, _, _, instanceID = GetInstanceInfo()
    end

    if detectedType == "raid" then
        instanceType = detectedType
    end

    if instanceType ~= "raid" then
        return
    end

    difficultyID = difficultyID or instanceDifficultyID
    encounterName = encounterName or AW.L.UNKNOWN_BOSS
    instanceName = instanceName or AW.L.UNKNOWN_INSTANCE

    local encounterKey = string.format(
        "%s:%s:%s",
        instanceType,
        tostring(instanceID or 0),
        tostring(encounterID or encounterName)
    )
    local signature = string.format("%s:%s", encounterKey, tostring(difficultyID or 0))
    local elapsed = GetTime()

    if AW.runtime.lastEncounterSignature == signature and (elapsed - AW.runtime.lastEncounterAt) < 5 then
        return
    end

    local now = Util:Now()
    local day = Database:GetDay(now)
    local encounters = day.encounters
    local category = "raid"

    encounters.total = (encounters.total or 0) + 1
    encounters[category] = (encounters[category] or 0) + 1

    if not encounters.bosses[encounterKey] then
        encounters.bosses[encounterKey] = {
            encounterID = encounterID,
            name = encounterName,
            instanceID = instanceID,
            instanceName = instanceName,
            instanceType = instanceType,
            kills = 0,
        }
    end

    local boss = encounters.bosses[encounterKey]
    boss.name = encounterName
    boss.instanceName = instanceName
    boss.difficultyID = difficultyID
    boss.difficultyName = difficultyName
    boss.groupSize = groupSize
    boss.kills = (boss.kills or 0) + 1
    boss.lastKilledAt = now

    self:RecordCompletedActivity(encounterKey, {
        encounterID = encounterID,
        name = encounterName,
        category = category,
        kind = "boss",
        instanceID = instanceID,
        instanceName = instanceName,
        instanceType = instanceType,
        difficultyID = difficultyID,
        difficultyName = difficultyName,
        groupSize = groupSize,
    })

    Database.db.meta.updatedAt = now
    AW.runtime.lastEncounterSignature = signature
    AW.runtime.lastEncounterAt = elapsed
end

function Tracker:AccumulateGroupmates(day, delta)
    if not Database.db.settings.trackGroupmates or not IsInGroup() then
        return
    end

    local prefix
    local count

    if IsInRaid() then
        prefix = "raid"
        count = GetNumGroupMembers()
    else
        prefix = "party"
        count = GetNumSubgroupMembers()
    end

    for index = 1, count do
        local unit = prefix .. index
        if UnitExists(unit) and not UnitIsUnit(unit, "player")
            and UnitIsConnected(unit) and UnitIsPlayer(unit)
        then
            local name, realm = UnitFullName(unit)
            name = name or UnitName(unit)
            realm = realm or GetRealmName()

            if name then
                local guid = UnitGUID(unit)
                local fullName = realm and realm ~= "" and string.format("%s-%s", name, realm) or name
                local key = guid or fullName
                local className, classFile = UnitClass(unit)
                local now = Util:Now()
                local groupmate = day.groupmates[key]
                local shouldRefreshProfile = not groupmate
                    or (now - (tonumber(groupmate.profileUpdatedAt) or 0)) >= 60
                local guildName = groupmate and groupmate.guildName
                if shouldRefreshProfile and GetGuildInfo then
                    local ok, value = pcall(GetGuildInfo, unit)
                    if ok and not isSecret(value) and value ~= "" then
                        guildName = value
                    end
                end

                local mythicPlusScore = not shouldRefreshProfile and groupmate and groupmate.mythicPlusScore
                local region = (groupmate and groupmate.region) or Util:GetRegionSlug()
                if shouldRefreshProfile and RaiderIO and type(RaiderIO.GetProfile) == "function" then
                    local ok, profile = pcall(RaiderIO.GetProfile, unit)
                    local mythicProfile = ok and type(profile) == "table" and profile.mythicKeystoneProfile
                    if type(mythicProfile) == "table" and mythicProfile.hasRenderableData ~= false then
                        mythicPlusScore = tonumber(mythicProfile.currentScore)
                        region = profile.region or region
                    end
                end

                if shouldRefreshProfile and (not mythicPlusScore or mythicPlusScore <= 0)
                    and C_PlayerInfo and C_PlayerInfo.GetPlayerMythicPlusRatingSummary
                then
                    local ok, rating = pcall(C_PlayerInfo.GetPlayerMythicPlusRatingSummary, unit)
                    if ok and type(rating) == "table" then
                        local currentSeasonScore = rating.currentSeasonScore
                        if not isSecret(currentSeasonScore) then
                            mythicPlusScore = tonumber(currentSeasonScore)
                        end
                    end
                end

                if mythicPlusScore and mythicPlusScore <= 0 then
                    mythicPlusScore = nil
                end

                if not groupmate then
                    groupmate = {
                        guid = guid,
                        name = name,
                        realm = realm,
                        fullName = fullName,
                        className = className,
                        classFile = classFile,
                        isPlayer = true,
                        guildName = guildName,
                        mythicPlusScore = mythicPlusScore,
                        region = region,
                        profileUpdatedAt = now,
                        seconds = 0,
                    }
                    day.groupmates[key] = groupmate
                end

                groupmate.name = name
                groupmate.realm = realm
                groupmate.fullName = fullName
                groupmate.className = className
                groupmate.classFile = classFile
                groupmate.isPlayer = true
                groupmate.guildName = guildName or groupmate.guildName
                groupmate.mythicPlusScore = mythicPlusScore or groupmate.mythicPlusScore
                groupmate.region = region or groupmate.region
                if shouldRefreshProfile then
                    groupmate.profileUpdatedAt = now
                end
                groupmate.seconds = groupmate.seconds + delta
            end
        end
    end
end

function Tracker:Accumulate(delta)
    if not AW.runtime.loggedIn or not Database.db.settings.enabled then
        return
    end

    local now = Util:Now()
    local day, dayKey = Database:GetDay(now)
    local characterKey, character = Database:TouchCharacter(now)
    local dayCharacter = ensureDayCharacter(day, characterKey, character)
    local isAFK = getPlayerAFKState()

    self:MarkSessionForDay(day, dayKey)

    day.onlineSeconds = (day.onlineSeconds or 0) + delta
    dayCharacter.seconds = (dayCharacter.seconds or 0) + delta

    if isAFK and Database.db.settings.trackAFK then
        day.afkSeconds = (day.afkSeconds or 0) + delta
        dayCharacter.afkSeconds = (dayCharacter.afkSeconds or 0) + delta
    else
        day.activeSeconds = (day.activeSeconds or 0) + delta
        dayCharacter.activeSeconds = (dayCharacter.activeSeconds or 0) + delta
    end

    local zoneKey, zoneInfo = getTrackedZoneInfo()
    if zoneKey and zoneInfo then
        local isNewZoneForDay = not day.zones[zoneKey]
        if isNewZoneForDay then
            day.zones[zoneKey] = {
                instanceID = zoneInfo.instanceID,
                instanceType = zoneInfo.instanceType,
                mapID = zoneInfo.mapID,
                name = zoneInfo.name,
                seconds = 0,
                visits = 0,
            }
        end
        if isNewZoneForDay or AW.runtime.lastZoneKey ~= zoneKey then
            day.zones[zoneKey].visits = (day.zones[zoneKey].visits or 0) + 1
            AW.runtime.lastZoneKey = zoneKey
        end
        day.zones[zoneKey].seconds = day.zones[zoneKey].seconds + delta
    end

    local activity = getActivity()
    day.activities[activity] = (day.activities[activity] or 0) + delta

    self:AccumulateGroupmates(day, delta)

    if AW.runtime.session then
        local sessionDuration = math.max(0, now - AW.runtime.session.startedAt)
        day.longestSession = math.max(day.longestSession or 0, sessionDuration)
    end

    Database.db.meta.updatedAt = now
end

function Tracker:OnUpdate(elapsed)
    AW.runtime.elapsed = AW.runtime.elapsed + elapsed
    AW.runtime.liveRefreshElapsed = AW.runtime.liveRefreshElapsed + elapsed

    if AW.runtime.elapsed >= AW.CONST.SAMPLE_INTERVAL then
        local delta = math.min(AW.runtime.elapsed, AW.CONST.MAX_ACCUMULATION_GAP)
        AW.runtime.elapsed = 0
        self:Accumulate(delta)
    end

    if AW.runtime.liveRefreshElapsed >= AW.CONST.LIVE_REFRESH_INTERVAL then
        AW.runtime.liveRefreshElapsed = 0
        if AW.UI and AW.UI.frame and AW.UI.frame:IsShown() and not AW.UI.previewMode then
            AW.UI:Refresh()
        end
    end
end

function Tracker:OnAddonLoaded()
    Database:Initialize()
    AW.Locale:ApplyPreference(Database.db.settings.locale)
    AW.Locale:RefreshStaticPopups()
    AW.Periods:RefreshSeason()
    if AW.UI and AW.UI.ApplyDefaultPeriod then
        AW.UI:ApplyDefaultPeriod()
    end
    if AW.UI and AW.UI.CreateMinimapButton then
        AW.UI:CreateMinimapButton()
    end
    if AW.Options and AW.Options.Initialize then
        AW.Options:Initialize()
    end
    AW.runtime.initialized = true
end

function Tracker:OnPlayerLogin()
    if not AW.runtime.initialized then
        self:OnAddonLoaded()
    end

    AW.runtime.loggedIn = true
    AW.runtime.elapsed = 0
    AW.runtime.liveRefreshElapsed = 0
    AW.runtime.playerIsAFK = false
    AW.runtime.lastActivitySignature = nil
    AW.runtime.lastActivityAt = 0
    AW.runtime.lastOutdoorActivityAt = 0
    AW.runtime.lastOutdoorActivityKind = nil
    AW.runtime.lastDungeonCompletionAt = 0
    AW.runtime.activePrey = nil
    AW.runtime.activeDelve = nil
    Database:StartSession()

    local day, dayKey = Database:GetDay()
    self:MarkSessionForDay(day, dayKey)
    self:RecordMoneyBaseline()
    self:RecordZoneVisit()
    self:UpdateActivePreyQuest()
    self:UpdateActiveDelve()
    self:StartDungeonRun()
    self:SetScript("OnUpdate", function(_, elapsed)
        Tracker:OnUpdate(elapsed)
    end)
end

function Tracker:OnPlayerLogout()
    self:Accumulate(math.min(AW.runtime.elapsed, AW.CONST.MAX_ACCUMULATION_GAP))
    AW.runtime.elapsed = 0
    Database:CloseSession()
    AW.runtime.loggedIn = false
    AW.runtime.lastTrackedMoneyCopper = nil
    AW.runtime.lastTrackedWarbandMoneyCopper = 0
    AW.runtime.hasLiveWarbandMoney = false
    AW.runtime.moneyDayKey = nil
    AW.runtime.moneyUpdateToken = (AW.runtime.moneyUpdateToken or 0) + 1
    AW.runtime.activeEncounter = nil
    AW.runtime.activePreyQuestID = nil
    AW.runtime.activePrey = nil
    AW.runtime.activeDelve = nil
    AW.runtime.activeDungeon = nil
end

function Tracker:OnEvent(event, ...)
    if event == "ADDON_LOADED" then
        local loadedAddon = ...
        if loadedAddon == ADDON_NAME then
            self:OnAddonLoaded()
        end
    elseif event == "PLAYER_LOGIN" then
        self:OnPlayerLogin()
    elseif event == "PLAYER_LOGOUT" then
        self:OnPlayerLogout()
    elseif event == "PLAYER_ENTERING_WORLD" then
        AW.runtime.activeEncounter = nil
        self:RecordZoneVisit()
        self:UpdateActiveDelve()
        self:StartDungeonRun()
    elseif event == "ZONE_CHANGED_NEW_AREA" or event == "ZONE_CHANGED" or event == "ZONE_CHANGED_INDOORS" then
        self:RecordZoneVisit()
    elseif event == "PLAYER_DEAD" then
        self:RecordDeath()
    elseif event == "PLAYER_MONEY" or event == "ACCOUNT_MONEY" then
        self:ScheduleMoneyChange()
    elseif event == "ENCOUNTER_START" then
        self:StartEncounter(...)
    elseif event == "ENCOUNTER_END" then
        local encounterID = ...
        self:RecordEncounter(...)
        self:EndEncounter(encounterID)
    elseif event == "CHALLENGE_MODE_START" then
        local challengeMapID = ...
        self:StartDungeonRun(challengeMapID, true)
    elseif event == "CHALLENGE_MODE_COMPLETED" then
        self:RecordChallengeModeCompletion()
    elseif event == "CHALLENGE_MODE_RESET" then
        AW.runtime.activeDungeon = nil
    elseif event == "SCENARIO_COMPLETED" then
        if not self:RecordDungeonCompletion() then
            self:RecordScenarioCompletion()
        end
    elseif event == "LFG_COMPLETION_REWARD" then
        self:RecordDungeonCompletion()
    elseif event == "QUEST_TURNED_IN" then
        local questID = ...
        self:RecordOutdoorQuest(questID)
        if questID == AW.runtime.activePreyQuestID then
            AW.runtime.activePreyQuestID = nil
            AW.runtime.activePrey = nil
        end
    elseif event == "QUEST_LOG_UPDATE" then
        self:UpdateActivePreyQuest()
    elseif event == "ACTIVE_DELVE_DATA_UPDATE" or event == "WALK_IN_DATA_UPDATE"
        or event == "SCENARIO_UPDATE"
    then
        self:UpdateActiveDelve()
    elseif event == "PLAYER_INTERACTION_MANAGER_FRAME_SHOW" then
        self:RecordPlayerInteraction(...)
    elseif NPC_EVENTS[event] then
        self:RecordNPCInteraction(NPC_EVENTS[event])
        if event == "BANKFRAME_OPENED" then
            self:ScheduleMoneyChange()
        end
    end
end

Tracker:SetScript("OnEvent", function(_, event, ...)
    Tracker:OnEvent(event, ...)
end)

Tracker:RegisterEvent("ADDON_LOADED")
Tracker:RegisterEvent("PLAYER_LOGIN")
Tracker:RegisterEvent("PLAYER_LOGOUT")
Tracker:RegisterEvent("PLAYER_ENTERING_WORLD")
Tracker:RegisterEvent("ZONE_CHANGED_NEW_AREA")
Tracker:RegisterEvent("ZONE_CHANGED")
Tracker:RegisterEvent("ZONE_CHANGED_INDOORS")
Tracker:RegisterEvent("PLAYER_DEAD")
Tracker:RegisterEvent("PLAYER_MONEY")
pcall(Tracker.RegisterEvent, Tracker, "ACCOUNT_MONEY")
Tracker:RegisterEvent("ENCOUNTER_START")
Tracker:RegisterEvent("ENCOUNTER_END")
Tracker:RegisterEvent("CHALLENGE_MODE_START")
Tracker:RegisterEvent("CHALLENGE_MODE_COMPLETED")
Tracker:RegisterEvent("CHALLENGE_MODE_RESET")
Tracker:RegisterEvent("QUEST_TURNED_IN")
Tracker:RegisterEvent("QUEST_LOG_UPDATE")
pcall(Tracker.RegisterEvent, Tracker, "SCENARIO_COMPLETED")
pcall(Tracker.RegisterEvent, Tracker, "SCENARIO_UPDATE")
pcall(Tracker.RegisterEvent, Tracker, "ACTIVE_DELVE_DATA_UPDATE")
pcall(Tracker.RegisterEvent, Tracker, "WALK_IN_DATA_UPDATE")
pcall(Tracker.RegisterEvent, Tracker, "LFG_COMPLETION_REWARD")
Tracker:RegisterEvent("PLAYER_INTERACTION_MANAGER_FRAME_SHOW")

local unsupportedNPCEvents = {}
for event in pairs(NPC_EVENTS) do
    local registered = pcall(Tracker.RegisterEvent, Tracker, event)
    if not registered then
        unsupportedNPCEvents[#unsupportedNPCEvents + 1] = event
    end
end

for _, event in ipairs(unsupportedNPCEvents) do
    NPC_EVENTS[event] = nil
end
