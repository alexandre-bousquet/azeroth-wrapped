-- Slash-command parsing and dispatch.
local _, AW = ...

local L = AW.L

StaticPopupDialogs["AZEROTH_WRAPPED_RESET"] = {
    text = L.RESET_CONFIRM,
    button1 = YES,
    button2 = NO,
    OnAccept = function(_, data)
        local periodKey = data and data.periodKey or "ALL"
        AW.Database:DeletePeriod(periodKey)
        AW.Periods:RefreshSeason()
        AW.Database:StartSession()
        local day, dayKey = AW.Database:GetDay()
        AW.Tracker:MarkSessionForDay(day, dayKey)
        AW.Tracker:RecordMoneyBaseline()
        AW.Tracker:RecordZoneVisit()
        if AW.UI and AW.UI.RefreshMinimapButton then
            AW.UI:RefreshMinimapButton()
        end
        if AW.UI and AW.UI.NormalizeCharacterFilter then
            AW.UI:NormalizeCharacterFilter()
        end
        AW:Print(string.format(L.RESET_DONE, AW.Periods:GetResetLabel(periodKey)))
        if AW.UI and AW.UI.frame and AW.UI.frame:IsShown() then
            AW.UI:Refresh()
        end
        if AW.Options and AW.Options.Refresh then
            AW.Options:Refresh()
        end
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

function AW:ShowResetConfirmation(periodKey)
    periodKey = AW.Periods:IsValid(periodKey) and periodKey or "ALL"
    StaticPopup_Show(
        "AZEROTH_WRAPPED_RESET",
        AW.Periods:GetResetLabel(periodKey),
        nil,
        { periodKey = periodKey }
    )
end

local function normalize(message)
    return string.lower(string.match(message or "", "^%s*(.-)%s*$"))
end

local function handleCommand(message)
    if not AW.runtime.initialized then
        AW.Database:Initialize()
        AW.Periods:RefreshSeason()
        AW.runtime.initialized = true
    end

    local command = normalize(message)

    if command == "" or command == "show" or command == "open" then
        AW.UI:Toggle()
    elseif AW.isDev and (command == "preview" or command == "demo" or command == "aperçu" or command == "apercu") then
        AW.UI:Show(nil, true)
    elseif command == "week" or command == "semaine" then
        AW.UI:Show("WEEK")
    elseif command == "month" or command == "mois" then
        AW.UI:Show("MONTH")
    elseif command == "season" or command == "saison" then
        AW.UI:Show("SEASON")
    elseif command == "year" or command == "année" or command == "annee" then
        AW.UI:Show("YEAR")
    elseif command == "all" or command == "tout" then
        AW.UI:Show("ALL")
    elseif command == "privacy" or command == "confidentialité" or command == "confidentialite" then
        local settings = AW.Database.db.settings
        settings.anonymousShare = not settings.anonymousShare
        AW:Print(settings.anonymousShare and L.PRIVACY_ON or L.PRIVACY_OFF)
        if AW.UI.frame and AW.UI.frame:IsShown() then
            AW.UI:Refresh()
        end
    elseif command == "tracking" or command == "collecte" then
        local settings = AW.Database.db.settings
        settings.enabled = not settings.enabled
        if settings.enabled then
            AW.Tracker:RecordMoneyBaseline()
        end
        AW:Print(settings.enabled and L.TRACKING_ON or L.TRACKING_OFF)
    elseif command == "status" or command == "statut" then
        local settings = AW.Database.db.settings
        AW:Print(string.format(
            L.STATUS,
            settings.enabled and L.STATUS_ENABLED or L.STATUS_DISABLED,
            AW.Database:CountDays(),
            AW.version
        ))
    elseif command == "reset" or command == "effacer" then
        AW:ShowResetConfirmation()
    else
        AW:Print(AW.isDev and L.HELP_DEV or L.HELP)
    end
end

SLASH_AZEROTHWRAPPED1 = "/azerothwrapped"
SLASH_AZEROTHWRAPPED2 = "/aw"
SlashCmdList.AZEROTHWRAPPED = handleCommand
