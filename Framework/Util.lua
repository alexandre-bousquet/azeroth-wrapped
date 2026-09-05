-- Generic helpers with no persistence or UI ownership.
local _, AW = ...

AW.Util = {}
local Util = AW.Util

local KNOWN_SUMMONED_NPC_IDS = {
    [35642] = true, -- Jeeves
}

local CYRILLIC_LOWER_REPLACEMENTS = {
    ["А"] = "а", ["Б"] = "б", ["В"] = "в", ["Г"] = "г", ["Д"] = "д", ["Е"] = "е",
    ["Ё"] = "ё", ["Ж"] = "ж", ["З"] = "з", ["И"] = "и", ["Й"] = "й", ["К"] = "к",
    ["Л"] = "л", ["М"] = "м", ["Н"] = "н", ["О"] = "о", ["П"] = "п", ["Р"] = "р",
    ["С"] = "с", ["Т"] = "т", ["У"] = "у", ["Ф"] = "ф", ["Х"] = "х", ["Ц"] = "ц",
    ["Ч"] = "ч", ["Ш"] = "ш", ["Щ"] = "щ", ["Ъ"] = "ъ", ["Ы"] = "ы", ["Ь"] = "ь",
    ["Э"] = "э", ["Ю"] = "ю", ["Я"] = "я",
}

function Util:UTF8Lower(value)
    value = string.lower(tostring(value or ""))
    for uppercase, lowercase in pairs(CYRILLIC_LOWER_REPLACEMENTS) do
        value = string.gsub(value, uppercase, lowercase)
    end
    return value
end

function Util:Now()
    if GetServerTime then
        return GetServerTime()
    end

    return time()
end

function Util:IsKnownSummonedNPC(npcID)
    return KNOWN_SUMMONED_NPC_IDS[tonumber(npcID)] == true
end

function Util:DayKey(timestamp)
    return date("%Y-%m-%d", timestamp or self:Now())
end

function Util:StartOfDay(timestamp)
    local value = date("*t", timestamp or self:Now())
    return time({
        year = value.year,
        month = value.month,
        day = value.day,
        hour = 0,
        min = 0,
        sec = 0,
    })
end

function Util:TimestampFromDayKey(dayKey)
    local year, month, day = string.match(dayKey or "", "^(%d%d%d%d)%-(%d%d)%-(%d%d)$")
    if not year then
        return nil
    end

    return time({
        year = tonumber(year),
        month = tonumber(month),
        day = tonumber(day),
        hour = 12,
        min = 0,
        sec = 0,
    })
end

function Util:GetCharacterKey()
    local name, realm = UnitFullName("player")
    name = name or UnitName("player") or "Unknown"
    realm = realm or GetRealmName() or "Unknown"
    realm = string.gsub(realm, "%s+", "")
    return string.format("%s-%s", name, realm), name, realm
end

function Util:FormatDuration(seconds)
    seconds = math.max(0, math.floor(tonumber(seconds) or 0))

    local days = math.floor(seconds / 86400)
    local hours = math.floor((seconds % 86400) / 3600)
    local minutes = math.floor((seconds % 3600) / 60)

    if days > 0 then
        return string.format("%dj %02dh", days, hours)
    end

    if hours > 0 then
        return string.format("%dh %02dmin", hours, minutes)
    end

    if minutes > 0 then
        return string.format("%dmin", minutes)
    end

    return string.format("%ds", seconds)
end

function Util:FormatMinutes(seconds)
    seconds = math.max(0, math.floor(tonumber(seconds) or 0))
    return string.format("%d min", math.floor(seconds / 60))
end

function Util:FormatTimer(seconds)
    seconds = math.max(0, math.floor(tonumber(seconds) or 0))
    local hours = math.floor(seconds / 3600)
    local minutes = math.floor((seconds % 3600) / 60)
    local remainingSeconds = seconds % 60

    if hours > 0 then
        return string.format("%d:%02d:%02d", hours, minutes, remainingSeconds)
    end
    return string.format("%d:%02d", minutes, remainingSeconds)
end

function Util:GetRegionSlug()
    local regionByID = {
        [1] = "us",
        [2] = "kr",
        [3] = "eu",
        [4] = "tw",
        [5] = "cn",
    }
    local regionID = GetCurrentRegion and GetCurrentRegion()
    return regionByID[regionID] or "eu"
end

function Util:GetClassName(classFile, className)
    if className and className ~= "" then
        return className
    end
    local localizedNames = LOCALIZED_CLASS_NAMES_MALE or {}
    return localizedNames[classFile] or classFile
end

function Util:GetClassColor(classFile)
    local customColor = CUSTOM_CLASS_COLORS and CUSTOM_CLASS_COLORS[classFile]
    local color = customColor or (RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile])
    if not color then
        return nil
    end
    return {
        tonumber(color.r) or 1,
        tonumber(color.g) or 1,
        tonumber(color.b) or 1,
        1,
    }
end

local function groupDigits(value, separator)
    local digits = tostring(math.max(0, math.floor(tonumber(value) or 0)))
    local firstGroupLength = #digits % 3

    if firstGroupLength == 0 then
        firstGroupLength = 3
    end

    local groups = { string.sub(digits, 1, firstGroupLength) }
    for index = firstGroupLength + 1, #digits, 3 do
        groups[#groups + 1] = string.sub(digits, index, index + 2)
    end

    return table.concat(groups, separator or ",")
end

function Util:FormatNumber(value)
    value = math.floor(tonumber(value) or 0)
    local sign = value < 0 and "-" or ""
    return sign .. groupDigits(math.abs(value), AW.L.NUMBER_GROUP_SEPARATOR)
end

function Util:FormatGold(copper, includeSign)
    copper = math.floor(tonumber(copper) or 0)

    local absoluteCopper = math.abs(copper)
    local gold = math.floor(absoluteCopper / 10000)
    local hundredths = math.floor(((absoluteCopper % 10000) + 50) / 100)

    if hundredths >= 100 then
        gold = gold + 1
        hundredths = 0
    end

    local amount = groupDigits(gold, AW.L.NUMBER_GROUP_SEPARATOR)
    if hundredths > 0 then
        amount = string.format("%s%s%02d", amount, AW.L.DECIMAL_SEPARATOR, hundredths)
    end

    local sign = ""
    if includeSign and copper > 0 then
        sign = "+"
    elseif copper < 0 then
        sign = "-"
    end

    return string.format("%s%s %s", sign, amount, AW.L.GOLD_SHORT)
end

function Util:Count(tableValue)
    local count = 0
    for _ in pairs(tableValue or {}) do
        count = count + 1
    end
    return count
end

function Util:TopEntry(entries, field)
    local topKey
    local topValue
    local topScore = -1

    for key, value in pairs(entries or {}) do
        local score
        if type(value) == "table" then
            score = tonumber(value[field]) or 0
        else
            score = tonumber(value) or 0
        end

        if score > topScore then
            topKey = key
            topValue = value
            topScore = score
        end
    end

    return topKey, topValue, topScore
end

function Util:AddMetric(target, key, amount)
    target[key] = (target[key] or 0) + (amount or 0)
end

function Util:AddStructuredMetric(target, key, source, numericFields)
    if not target[key] then
        target[key] = {}
    end

    local destination = target[key]
    for field, value in pairs(source or {}) do
        if numericFields[field] then
            destination[field] = (destination[field] or 0) + (tonumber(value) or 0)
        elseif destination[field] == nil then
            destination[field] = value
        end
    end

    return destination
end

function Util:SafeFormat(pattern, ...)
    local ok, result = pcall(string.format, pattern, ...)
    return ok and result or pattern
end

function Util:FormatCount(count, singularPattern, pluralPattern)
    count = math.max(0, math.floor(tonumber(count) or 0))
    return self:SafeFormat(count == 1 and singularPattern or pluralPattern, count)
end
