-- Addon namespace, constants, and runtime state shared by every layer.
local ADDON_NAME, AW = ...

AW.name = ADDON_NAME
AW.displayName = "Azeroth Wrapped"
AW.isDev = ADDON_NAME == "AzerothWrappedDev"
AW.savedVariableName = AW.isDev and "AzerothWrappedDevDB" or "AzerothWrappedDB"
AW.version = (C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata(ADDON_NAME, "Version"))
    or (GetAddOnMetadata and GetAddOnMetadata(ADDON_NAME, "Version"))
    or "dev"

AW.CONST = {
    DB_SCHEMA = 11,
    SAMPLE_INTERVAL = 1,
    MAX_ACCUMULATION_GAP = 300,
    LIVE_REFRESH_INTERVAL = 5,
    MAX_SESSION_HISTORY = 100,
    DEFAULT_RETENTION_DAYS = 730,
}

AW.runtime = {
    initialized = false,
    loggedIn = false,
    elapsed = 0,
    liveRefreshElapsed = 0,
    lastDayKey = nil,
    lastZoneKey = nil,
    lastNPC = nil,
    lastNPCAt = 0,
    lastTrackedMoneyCopper = nil,
    lastTrackedWarbandMoneyCopper = 0,
    hasLiveWarbandMoney = false,
    moneyDayKey = nil,
    moneyUpdateToken = 0,
    playerIsAFK = false,
    lastEncounterSignature = nil,
    lastEncounterAt = 0,
    lastActivitySignature = nil,
    lastActivityAt = 0,
    lastOutdoorActivityAt = 0,
    lastOutdoorActivityKind = nil,
    activePreyQuestID = nil,
    activePrey = nil,
    activeDelve = nil,
    activeDungeon = nil,
    lastDungeonCompletionAt = 0,
    activeEncounter = nil,
    session = nil,
}

local PREFIX = "|cff42d9d0Azeroth|r |cffffc857Wrapped|r"

function AW:Print(message)
    if DEFAULT_CHAT_FRAME then
        DEFAULT_CHAT_FRAME:AddMessage(string.format("%s  %s", PREFIX, tostring(message)))
    end
end

function AW:Debug(message)
    local db = self.Database and self.Database.db
    if db and db.settings and db.settings.debug then
        self:Print("|cff9aa7bd[debug]|r " .. tostring(message))
    end
end
