local _, AW = ...

AW.Options = {}
local Options = AW.Options
local L = AW.L

local LOCALE_OPTIONS = { "AUTO", "enUS", "frFR" }

local function getSettings()
    local db = AW.Database and AW.Database.db
    return db and db.settings or nil
end

local function getLocaleName(locale)
    if locale == "enUS" then
        return L.OPTIONS_LANGUAGE_ENGLISH
    elseif locale == "frFR" then
        return L.OPTIONS_LANGUAGE_FRENCH
    end

    local automaticLocale = AW.Locale:DetectDefault()
    return AW:GetText("OPTIONS_LANGUAGE_AUTO", getLocaleName(automaticLocale))
end

local function createLabel(parent, text, template, x, y)
    local label = parent:CreateFontString(nil, "ARTWORK", template)
    label:SetPoint("TOPLEFT", x, y)
    label:SetJustifyH("LEFT")
    label:SetText(text)
    return label
end

local function setupDropdown(dropdown, values, getValue, getLabel, setValue)
    dropdown:SetWidth(240)
    dropdown:SetDefaultText(getLabel(getValue()))
    dropdown:SetSelectionText(function()
        return getLabel(getValue())
    end)
    dropdown:SetupMenu(function(_, rootDescription)
        for _, value in ipairs(values) do
            local optionValue = value
            rootDescription:CreateRadio(getLabel(optionValue), function()
                return getValue() == optionValue
            end, function()
                setValue(optionValue)
            end)
        end
    end)
end

function Options:Refresh()
    if not self.panel then
        return
    end

    local settings = getSettings()
    if not settings then
        return
    end

    self.languageDropdown:SetDefaultText(getLocaleName(settings.locale))
    self.periodDropdown:SetDefaultText(AW.Periods:GetLabel(settings.defaultPeriod))
end

function Options:Initialize()
    if self.initialized or not Settings or not Settings.RegisterCanvasLayoutCategory then
        return
    end

    local panel = CreateFrame("Frame", "AzerothWrappedSettingsPanel")
    panel.name = AW.displayName
    panel.OnCommit = function() end
    panel.OnDefault = function() end
    panel.OnRefresh = function()
        Options:Refresh()
    end

    createLabel(panel, L.OPTIONS_TITLE, "GameFontNormalLarge", 24, -24)

    createLabel(panel, L.OPTIONS_LANGUAGE, "GameFontNormal", 24, -72)
    local languageDescription = createLabel(panel, L.OPTIONS_LANGUAGE_DESC, "GameFontHighlightSmall", 24, -94)
    languageDescription:SetWidth(540)

    local languageDropdown = CreateFrame("DropdownButton", nil, panel, "WowStyle1DropdownTemplate")
    languageDropdown:SetPoint("TOPLEFT", 24, -122)
    setupDropdown(languageDropdown, LOCALE_OPTIONS, function()
        local settings = getSettings()
        return settings and settings.locale or "AUTO"
    end, getLocaleName, function(value)
        local settings = getSettings()
        if not settings or settings.locale == value then
            return
        end

        settings.locale = value
        StaticPopup_Show("AZEROTH_WRAPPED_RELOAD_LOCALE")
    end)
    self.languageDropdown = languageDropdown

    createLabel(panel, L.OPTIONS_DEFAULT_PERIOD, "GameFontNormal", 24, -188)
    local periodDescription = createLabel(panel, L.OPTIONS_DEFAULT_PERIOD_DESC, "GameFontHighlightSmall", 24, -210)
    periodDescription:SetWidth(540)

    local periodDropdown = CreateFrame("DropdownButton", nil, panel, "WowStyle1DropdownTemplate")
    periodDropdown:SetPoint("TOPLEFT", 24, -238)
    setupDropdown(periodDropdown, AW.Periods.order, function()
        local settings = getSettings()
        return settings and settings.defaultPeriod or "WEEK"
    end, function(periodKey)
        return AW.Periods:GetLabel(periodKey)
    end, function(value)
        local settings = getSettings()
        if not settings or not AW.Periods:IsValid(value) then
            return
        end

        settings.defaultPeriod = value
        if AW.UI and AW.UI.ApplyDefaultPeriod then
            AW.UI:ApplyDefaultPeriod()
            if AW.UI.frame and AW.UI.frame:IsShown() then
                AW.UI:Refresh(true)
            end
        end
    end)
    self.periodDropdown = periodDropdown

    createLabel(panel, L.OPTIONS_RESET_TITLE, "GameFontNormal", 24, -304)
    local resetDescription = createLabel(panel, L.OPTIONS_RESET_DESC, "GameFontHighlightSmall", 24, -326)
    resetDescription:SetWidth(540)

    local resetButton = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    resetButton:SetPoint("TOPLEFT", 24, -356)
    resetButton:SetSize(220, 26)
    resetButton:SetText(L.OPTIONS_RESET_BUTTON)
    resetButton:SetScript("OnClick", function()
        AW:ShowResetConfirmation()
    end)

    StaticPopupDialogs["AZEROTH_WRAPPED_RELOAD_LOCALE"] = {
        text = L.OPTIONS_LANGUAGE_RELOAD_CONFIRM,
        button1 = L.OPTIONS_RELOAD_NOW,
        button2 = L.OPTIONS_RELOAD_LATER,
        OnAccept = function()
            ReloadUI()
        end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
        preferredIndex = 3,
    }

    panel:SetScript("OnShow", function()
        Options:Refresh()
    end)

    local category = Settings.RegisterCanvasLayoutCategory(panel, AW.displayName)
    Settings.RegisterAddOnCategory(category)

    self.panel = panel
    self.category = category
    self.initialized = true
end
