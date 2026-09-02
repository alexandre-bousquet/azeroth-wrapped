local _, AW = ...

local Locale = {
    dictionaries = {},
    current = nil,
}

AW.Locale = Locale

function Locale:Register(locale, translations)
    if type(locale) ~= "string" or type(translations) ~= "table" then
        return
    end

    self.dictionaries[locale] = translations
end

function Locale:DetectDefault()
    return GetLocale() == "frFR" and "frFR" or "enUS"
end

function Locale:NormalizePreference(preference)
    if preference == "enUS" or preference == "frFR" then
        return preference
    end

    return "AUTO"
end

function Locale:ResolvePreference(preference)
    preference = self:NormalizePreference(preference)
    return preference == "AUTO" and self:DetectDefault() or preference
end

function Locale:GetSavedPreference()
    local savedDatabase = _G[AW.savedVariableName or "AzerothWrappedDB"]
    local settings = type(savedDatabase) == "table" and savedDatabase.settings or nil
    return self:NormalizePreference(type(settings) == "table" and settings.locale or nil)
end

function Locale:ApplyPreference(preference)
    self:Set(self:ResolvePreference(preference))
end

function Locale:RefreshStaticPopups()
    local resetDialog = StaticPopupDialogs and StaticPopupDialogs.AZEROTH_WRAPPED_RESET
    if resetDialog then
        resetDialog.text = AW.L.RESET_CONFIRM
    end

    local popupKey = string.upper(string.gsub(AW.name or "AzerothWrapped", "%W", "_")) .. "_PROFILE_URL"
    local profileDialog = StaticPopupDialogs and StaticPopupDialogs[popupKey]
    if profileDialog then
        profileDialog.text = AW.L.PROFILE_URL_COPY_TITLE
        profileDialog.button1 = AW.L.CLOSE
    end
end

function Locale:Set(locale)
    if not self.dictionaries[locale] then
        locale = "enUS"
    end

    self.current = locale
end

function Locale:GetCurrent()
    return self.current
end

function Locale:Get(key, ...)
    local dictionary = self.dictionaries[self.current] or self.dictionaries.enUS or {}
    local fallback = self.dictionaries.enUS or {}
    local value = dictionary[key] or fallback[key] or key

    if select("#", ...) > 0 then
        local ok, formatted = pcall(string.format, value, ...)
        if ok then
            return formatted
        end
    end

    return value
end


Locale.current = Locale:ResolvePreference(Locale:GetSavedPreference())

AW.L = setmetatable({}, {
    __index = function(_, key)
        return Locale:Get(key)
    end,
})

function AW:GetText(key, ...)
    return Locale:Get(key, ...)
end
