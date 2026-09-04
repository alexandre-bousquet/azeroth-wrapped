local ADDON_NAME, AW = ...

local UI = AW.UI
local L = AW.L
local Theme = AW.Theme
local Util = AW.Util

local MAX_DETAIL_ROWS = 100
local ROW_HEIGHT = 50
local DEFAULT_SCROLL_TOP = -76
local SEARCH_SCROLL_TOP = -111
local GOLD_SCROLL_TOP = -310
local ACTIVITY_TAB_WIDTH = 203.5
local PROFILE_URL_POPUP = string.upper(string.gsub(ADDON_NAME or "AzerothWrapped", "%W", "_")) .. "_PROFILE_URL"

StaticPopupDialogs[PROFILE_URL_POPUP] = {
    text = L.PROFILE_URL_COPY_TITLE,
    button1 = L.CLOSE,
    hasEditBox = true,
    editBoxWidth = 360,
    maxLetters = 0,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

local function appendRow(rows, label, detail, value, waypoint, raiderIOURL, warcraftLogsURL, classFile)
    rows[#rows + 1] = {
        label = label or L.DETAIL_UNKNOWN,
        detail = detail or "",
        value = value or "",
        waypoint = waypoint,
        raiderIOURL = raiderIOURL,
        warcraftLogsURL = warcraftLogsURL,
        classFile = classFile,
    }
end

local function urlEncode(value)
    return (string.gsub(tostring(value or ""), "([^%w%-_%.~])", function(character)
        return string.format("%%%02X", string.byte(character))
    end))
end

local function realmSlug(realm)
    realm = tostring(realm or "")
    realm = string.gsub(realm, "(%l)(%u)", "%1-%2")
    realm = string.gsub(realm, "(%a)(%d)", "%1-%2")
    realm = string.gsub(realm, "’", "")
    realm = string.gsub(realm, "'", "")
    realm = string.gsub(realm, "[()]", "")
    realm = string.gsub(realm, "%s+", "-")
    return urlEncode(Util:UTF8Lower(realm))
end

local function buildRaiderIOURL(name, realm, region)
    if not name or name == "" or not realm or realm == "" then
        return nil
    end

    return string.format(
        "https://raider.io/characters/%s/%s/%s",
        urlEncode(string.lower(region or Util:GetRegionSlug())),
        realmSlug(realm),
        urlEncode(name)
    )
end

local function buildWarcraftLogsURL(name, realm, region)
    if not name or name == "" or not realm or realm == "" then
        return nil
    end

    return string.format(
        "https://www.warcraftlogs.com/character/%s/%s/%s",
        urlEncode(string.lower(region or Util:GetRegionSlug())),
        realmSlug(realm),
        urlEncode(name)
    )
end

local function getRaiderIOProfile(companion)
    local score = tonumber(companion.mythicPlusScore)
    local region = companion.region or Util:GetRegionSlug()
    local realm = companion.realm

    if RaiderIO and type(RaiderIO.GetProfile) == "function" and companion.name and realm then
        local ok, profile = pcall(RaiderIO.GetProfile, companion.name, realm, region)
        if ok and type(profile) == "table" then
            local mythicProfile = profile.mythicKeystoneProfile
            if type(mythicProfile) == "table" and mythicProfile.hasRenderableData ~= false then
                score = tonumber(mythicProfile.currentScore) or score
            end
            region = profile.region or region
            realm = profile.realm or realm
        end
    end

    if score and score <= 0 then
        score = nil
    end
    return score, region, realm
end

local SEARCH_REPLACEMENTS = {
    ["À"] = "a", ["Â"] = "a", ["Ä"] = "a", ["à"] = "a", ["â"] = "a", ["ä"] = "a",
    ["Ç"] = "c", ["ç"] = "c",
    ["É"] = "e", ["È"] = "e", ["Ê"] = "e", ["Ë"] = "e",
    ["é"] = "e", ["è"] = "e", ["ê"] = "e", ["ë"] = "e",
    ["Î"] = "i", ["Ï"] = "i", ["î"] = "i", ["ï"] = "i",
    ["Ô"] = "o", ["Ö"] = "o", ["Œ"] = "oe", ["ô"] = "o", ["ö"] = "o", ["œ"] = "oe",
    ["Ù"] = "u", ["Û"] = "u", ["Ü"] = "u", ["ù"] = "u", ["û"] = "u", ["ü"] = "u",
    ["Ÿ"] = "y", ["ÿ"] = "y",
}

local function normalizeSearchText(value)
    value = tostring(value or "")
    for character, replacement in pairs(SEARCH_REPLACEMENTS) do
        value = string.gsub(value, character, replacement)
    end
    return Util:UTF8Lower(value)
end

local function sortedEntries(entries, field, scorer)
    local result = {}

    for key, value in pairs(entries or {}) do
        local score
        if scorer then
            score = scorer(value, key)
        elseif type(value) == "table" then
            score = tonumber(value[field]) or 0
        else
            score = tonumber(value) or 0
        end

        result[#result + 1] = {
            key = key,
            value = value,
            score = tonumber(score) or 0,
        }
    end

    table.sort(result, function(left, right)
        if left.score == right.score then
            local leftName = type(left.value) == "table" and left.value.name or left.key
            local rightName = type(right.value) == "table" and right.value.name or right.key
            return tostring(leftName or "") < tostring(rightName or "")
        end
        return left.score > right.score
    end)

    return result
end

local function joinDetails(...)
    local parts = {}

    for index = 1, select("#", ...) do
        local value = select(index, ...)
        if value and value ~= "" then
            parts[#parts + 1] = tostring(value)
        end
    end

    return table.concat(parts, "  •  ")
end

local function buildTimeRows(summary)
    local rows = {}
    appendRow(rows, L.DETAIL_ONLINE_TIME, "", Util:FormatDuration(summary.onlineSeconds))
    appendRow(rows, L.DETAIL_ACTIVE_TIME, "", Util:FormatDuration(summary.activeSeconds))
    appendRow(rows, L.DETAIL_AFK_TIME, "", Util:FormatDuration(summary.afkSeconds))
    appendRow(rows, L.DETAIL_SESSIONS, "", tostring(summary.sessionCount or 0))
    appendRow(rows, L.DETAIL_LONGEST_SESSION, "", Util:FormatDuration(summary.longestSession))
    appendRow(rows, L.DETAIL_ACTIVE_DAYS, "", tostring(summary.daysPlayed or 0))
    return rows
end

local function buildZoneRows(summary)
    local rows = {}
    for _, entry in ipairs(sortedEntries(summary.zones, "seconds")) do
        local zone = entry.value
        appendRow(
            rows,
            zone.name or L.UNKNOWN_ZONE,
            string.format(L.DETAIL_VISITS, zone.visits or 0),
            Util:FormatDuration(zone.seconds)
        )
    end
    return rows
end

local function buildDeathRows(summary)
    local rows = {}
    local details = {}

    for _, death in ipairs((summary.deaths and summary.deaths.details) or {}) do
        details[#details + 1] = death
    end

    table.sort(details, function(first, second)
        return (tonumber(first.timestamp) or 0) > (tonumber(second.timestamp) or 0)
    end)

    local environmentalLabels = {
        DROWNING = L.DEATH_CAUSE_DROWNING,
        FALLING = L.DEATH_CAUSE_FALL,
        FATIGUE = L.DEATH_CAUSE_FATIGUE,
        FIRE = L.DEATH_CAUSE_FIRE,
        LAVA = L.DEATH_CAUSE_LAVA,
        SLIME = L.DEATH_CAUSE_SLIME,
    }

    local function formatDamage(amount)
        amount = tonumber(amount)
        if not amount or amount <= 0 then
            return nil
        end
        local formatted = BreakUpLargeNumbers and BreakUpLargeNumbers(math.floor(amount)) or tostring(math.floor(amount))
        return string.format(L.DEATH_DAMAGE, formatted)
    end

    for _, death in ipairs(details) do
        local category = death.category
        local label
        local sourceName = AW.Database.db.settings.anonymousShare and nil or death.sourceName
        local spellName = death.spellName
        local bossContext

        if category == "boss" then
            label = string.format(L.DEATH_CAUSE_BOSS, death.encounterName or sourceName or L.UNKNOWN_BOSS)
            if sourceName == death.encounterName then
                sourceName = nil
            end
        elseif category == "fall" then
            label = L.DEATH_CAUSE_FALL
        elseif category == "environment" then
            label = environmentalLabels[death.environmentalType] or L.DEATH_CAUSE_ENVIRONMENT
        elseif category == "attack" then
            if not spellName and death.event == "SWING_DAMAGE" then
                spellName = L.DEATH_MELEE_ATTACK
            elseif not spellName and death.event == "RANGE_DAMAGE" then
                spellName = L.DEATH_RANGED_ATTACK
            end
            label = string.format(L.DEATH_CAUSE_ATTACK, spellName or L.DEATH_UNKNOWN_ATTACK)
            spellName = nil
        else
            label = L.DEATH_CAUSE_UNKNOWN
        end

        if category ~= "boss" and death.encounterName then
            bossContext = string.format(L.DEATH_CAUSE_BOSS, death.encounterName)
        end

        appendRow(
            rows,
            label,
            joinDetails(death.locationName, bossContext, spellName, sourceName, formatDamage(death.amount)),
            death.timestamp and date(L.DEATH_DATE_FORMAT, death.timestamp) or ""
        )
    end

    local missingDetails = math.max(0, ((summary.deaths and summary.deaths.total) or 0) - #details)
    if #details > 0 and missingDetails > 0 then
        appendRow(
            rows,
            Util:FormatCount(missingDetails, L.DEATH_WITHOUT_DETAILS_ONE, L.DEATH_WITHOUT_DETAILS),
            "",
            ""
        )
        return rows
    elseif #details > 0 then
        return rows
    end

    for _, entry in ipairs(sortedEntries(summary.deaths and summary.deaths.locations, "deaths")) do
        local location = entry.value
        appendRow(
            rows,
            location.name or L.UNKNOWN_ZONE,
            "",
            Util:FormatCount(location.deaths, L.DETAIL_DEATHS_ONE, L.DETAIL_DEATHS)
        )
    end
    return rows
end

local function buildCompanionRows(summary)
    local rows = {}
    local private = AW.Database.db.settings.anonymousShare
    local searchText = UI.companionSearchText or ""
    local playerCompanions = {}

    for key, companion in pairs(summary.groupmates or {}) do
        local guid = type(companion) == "table" and companion.guid or nil
        if type(companion) == "table"
            and companion.isPlayer ~= false
            and (type(guid) ~= "string" or string.match(guid, "^Player%-"))
        then
            playerCompanions[key] = companion
        end
    end

    for index, entry in ipairs(sortedEntries(playerCompanions, "seconds")) do
        local companion = entry.value
        local name = companion.name or L.UNKNOWN_PLAYER
        local classFile = companion.classFile
        local className = Util:GetClassName(classFile, companion.className)
        local realm = companion.realm
        local guildName = companion.guildName
        local score, region, profileRealm = getRaiderIOProfile(companion)
        local raiderIOURL = buildRaiderIOURL(companion.name, profileRealm, region)
        local warcraftLogsURL = buildWarcraftLogsURL(companion.name, profileRealm, region)

        if private then
            name = string.format(L.PRIVATE_PLAYER_NUMBER, index)
            realm = nil
            guildName = nil
            score = nil
            raiderIOURL = nil
            warcraftLogsURL = nil
        end

        local guildText = guildName and string.format(L.DETAIL_COMPANION_GUILD, guildName)
        local scoreText = score and string.format(L.DETAIL_COMPANION_SCORE, math.floor(score + 0.5))
        local displayName = className and string.format(L.DETAIL_COMPANION_NAME_CLASS, name, className) or name
        local searchableText = normalizeSearchText(table.concat({
            name or "",
            className or "",
            classFile or "",
            realm or "",
            guildName or "",
        }, " "))

        if searchText == "" or string.find(searchableText, searchText, 1, true) then
            appendRow(
                rows,
                displayName,
                joinDetails(
                    realm,
                    guildText,
                    scoreText
                ),
                Util:FormatMinutes(companion.seconds),
                nil,
                raiderIOURL,
                warcraftLogsURL,
                classFile
            )
        end
    end

    return rows
end

local function buildCharacterRows(summary)
    local rows = {}
    local searchText = UI.characterSearchText or ""

    for _, entry in ipairs(sortedEntries(summary.characters, "seconds")) do
        local character = entry.value
        local storedCharacter = AW.Database.db.characters[entry.key] or {}
        local name = character.name or storedCharacter.name or L.UNKNOWN_PLAYER
        local className = character.className or storedCharacter.className or character.classFile
        local realm = character.realm or storedCharacter.realm
        local searchableText = normalizeSearchText(table.concat({
            name or "",
            realm or "",
            className or "",
            character.classFile or storedCharacter.classFile or "",
        }, " "))

        if searchText == "" or string.find(searchableText, searchText, 1, true) then
            appendRow(
                rows,
                name,
                joinDetails(
                    className,
                    realm,
                    Util:FormatCount(character.deaths, L.DETAIL_CHARACTER_DEATHS_ONE, L.DETAIL_CHARACTER_DEATHS)
                ),
                Util:FormatDuration(character.seconds)
            )
        end
    end

    return rows
end

local function buildNPCRows(summary)
    local rows = {}
    local searchText = UI.npcSearchText or ""
    local serviceOrder = {
        "merchant",
        "quest",
        "bank",
        "guildBank",
        "trainer",
        "flightMaster",
        "auctionHouse",
        "mailbox",
        "stableMaster",
        "transmogrifier",
        "voidStorage",
        "itemUpgrade",
        "craftingOrders",
        "scrapping",
        "gossip",
    }

    for _, entry in ipairs(sortedEntries(summary.npcs, "interactions")) do
        local npc = entry.value
        local services = {}
        for _, service in ipairs(serviceOrder) do
            if service ~= "gossip" and npc.services and npc.services[service] then
                local label = L["NPC_SERVICE_" .. service]
                if label then
                    services[#services + 1] = label
                end
            end
        end

        if #services == 0 and npc.services and npc.services.gossip then
            services[1] = L.NPC_SERVICE_gossip
        end

        local serviceText = #services > 0 and table.concat(services, ", ") or nil
        local searchableText = normalizeSearchText(table.concat({
            npc.name or "",
            npc.title or "",
            serviceText or "",
        }, " "))

        if searchText == "" or string.find(searchableText, searchText, 1, true) then
            local x = tonumber(npc.x)
            local y = tonumber(npc.y)
            local positionText
            local waypoint
            if npc.isSummoned or Util:IsKnownSummonedNPC(npc.npcID) then
                positionText = L.DETAIL_NPC_SUMMONED
            elseif npc.isMount then
                positionText = L.DETAIL_NPC_MOBILE
            elseif npc.mapID and x and y then
                local locationName = npc.mapName or npc.zoneName or L.UNKNOWN_ZONE
                if npc.zoneName and npc.mapName and npc.zoneName ~= npc.mapName then
                    locationName = string.format("%s - %s", npc.mapName, npc.zoneName)
                end
                positionText = string.format(L.DETAIL_NPC_POSITION, locationName, x * 100, y * 100)
                waypoint = {
                    mapID = npc.mapID,
                    x = x,
                    y = y,
                    name = npc.name or L.UNKNOWN_NPC,
                }
            end

            appendRow(
                rows,
                npc.name or L.UNKNOWN_NPC,
                joinDetails(npc.title, positionText),
                string.format(L.DETAIL_INTERACTIONS, npc.interactions or 0),
                waypoint
            )
        end
    end

    return rows
end

local function buildMoneyRows(summary)
    local rows = {}
    local wallets = summary.money and summary.money.characters or {}
    local warbandBalance = tonumber(summary.warbandBalance)

    if warbandBalance ~= nil then
        appendRow(
            rows,
            L.DETAIL_GOLD_WARBAND,
            string.format(L.DETAIL_GOLD_BALANCE, Util:FormatGold(warbandBalance)),
            ""
        )
    end

    for _, entry in ipairs(sortedEntries(wallets, nil, function(wallet)
        return (tonumber(wallet.earned) or 0) + (tonumber(wallet.spent) or 0)
    end)) do
        local wallet = entry.value
        local storedCharacter = AW.Database.db.characters[entry.key] or {}
        local name = wallet.name or storedCharacter.name or entry.key
        local balance = wallet.balance
        if balance == nil then
            balance = storedCharacter.moneyCopper
        end

        local flow = string.format(
            L.DETAIL_GOLD_FLOW,
            Util:FormatGold(wallet.earned),
            Util:FormatGold(wallet.spent)
        )
        local balanceText = balance ~= nil and string.format(L.DETAIL_GOLD_BALANCE, Util:FormatGold(balance)) or nil
        local net = (wallet.changes or 0) > 0 and Util:FormatGold(wallet.net, true) or L.NO_GOLD_CHANGE

        appendRow(rows, name, joinDetails(flow, balanceText), net)
    end

    return rows
end


local function buildActivityRows(summary)
    local rows = {}
    local completedActivities = summary.completedActivities or {}
    local history = completedActivities.history or {}
    local activities = {}
    local usesHistory = #history > 0

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
        activities = sortedEntries(completedActivities.entries, "completions")
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
                detail = joinDetails(categoryLabel, difficultyLabel, timerLabel, keyResult)
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
                    and normalizeSearchText(activity.name) == normalizeSearchText(activity.difficultyName)
                then
                    displayName = instanceName
                end
                if activity.kind == "delve"
                    and normalizeSearchText(instanceName) == normalizeSearchText(displayName)
                then
                    instanceName = nil
                end
                detail = joinDetails(kindLabel, difficultyLabel, timerLabel, instanceName)
            else
                detail = joinDetails(categoryLabel, kindLabel, activity.instanceName, activity.difficultyName)
            end

            local completionCount = tonumber(activity.completions) or 0
            local isSingleLegacyCompletion = activity.legacyAggregate and completionCount == 1
            local completionLabel = activity.completedAt
                and (not activity.legacyAggregate or isSingleLegacyCompletion)
                and date(L.ACTIVITY_DATE_FORMAT, activity.completedAt)
                or string.format(L.DETAIL_COMPLETIONS, completionCount)

            appendRow(
                rows,
                displayName,
                detail,
                completionLabel
            )
        end
    end

    return rows
end

local DETAIL_BUILDERS = {
    time = buildTimeRows,
    world = buildZoneRows,
    fate = buildDeathRows,
    companion = buildCompanionRows,
    identity = buildCharacterRows,
    npcs = buildNPCRows,
    gold = buildMoneyRows,
    activities = buildActivityRows,
}

function UI:SetNPCWaypoint(waypoint)
    if not waypoint or not C_Map or not C_Map.SetUserWaypoint
        or not UiMapPoint or not UiMapPoint.CreateFromCoordinates
    then
        AW:Print(L.WAYPOINT_UNAVAILABLE)
        return
    end

    if C_Map.CanSetUserWaypointOnMap then
        local ok, canSet = pcall(C_Map.CanSetUserWaypointOnMap, waypoint.mapID)
        if not ok or not canSet then
            AW:Print(L.WAYPOINT_UNAVAILABLE)
            return
        end
    end

    local ok, point = pcall(UiMapPoint.CreateFromCoordinates, waypoint.mapID, waypoint.x, waypoint.y)
    if not ok or not point then
        AW:Print(L.WAYPOINT_UNAVAILABLE)
        return
    end

    ok = pcall(C_Map.SetUserWaypoint, point)
    if not ok then
        AW:Print(L.WAYPOINT_UNAVAILABLE)
        return
    end

    if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then
        pcall(C_SuperTrack.SetSuperTrackedUserWaypoint, true)
    end
    AW:Print(string.format(L.WAYPOINT_SET, waypoint.name))
end

function UI:ShowProfileURL(profileURL)
    if not profileURL then
        return
    end

    local dialog = StaticPopup_Show(PROFILE_URL_POPUP)
    if not dialog then
        return
    end

    local editBox = dialog.EditBox or dialog.editBox
    if editBox then
        editBox:SetText(profileURL)
        editBox:HighlightText()
        editBox:SetFocus()
    end
end

function UI:CreateDetailRow(parent, index)
    local row = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    row:SetSize(790, ROW_HEIGHT - 4)
    row:SetPoint("TOPLEFT", 0, -((index - 1) * ROW_HEIGHT))
    Theme:ApplyBackdrop(row, index % 2 == 0 and Theme.surfaceHover or Theme.surface, Theme.border)

    row.label = Theme:CreateText(row, "GameFontHighlight", 13, Theme.text)
    row.label:SetPoint("TOPLEFT", 13, -8)
    row.label:SetPoint("RIGHT", -205, 0)
    row.label:SetJustifyH("LEFT")
    row.label:SetWordWrap(false)

    row.detail = Theme:CreateText(row, "GameFontHighlightSmall", 10, Theme.muted)
    row.detail:SetPoint("TOPLEFT", 13, -27)
    row.detail:SetPoint("RIGHT", -205, 0)
    row.detail:SetJustifyH("LEFT")
    row.detail:SetWordWrap(false)

    row.value = Theme:CreateText(row, "GameFontHighlight", 12, Theme.text)
    row.value:SetPoint("RIGHT", -13, 0)
    row.value:SetWidth(180)
    row.value:SetJustifyH("RIGHT")
    row.value:SetWordWrap(false)

    row.waypoint = Theme:CreateButton(row, L.DETAIL_WAYPOINT, 88)
    row.waypoint:SetSize(88, 26)
    row.waypoint:SetScript("OnClick", function(button)
        UI:SetNPCWaypoint(button.data)
    end)
    row.waypoint:Hide()

    row.raiderIO = Theme:CreateButton(row, L.DETAIL_RAIDERIO, 88)
    row.raiderIO:SetSize(88, 26)
    row.raiderIO:SetScript("OnClick", function(button)
        UI:ShowProfileURL(button.profileURL)
    end)
    row.raiderIO:Hide()

    row.warcraftLogs = Theme:CreateButton(row, L.DETAIL_WARCRAFT_LOGS, 112)
    row.warcraftLogs:SetSize(112, 26)
    row.warcraftLogs:SetScript("OnClick", function(button)
        UI:ShowProfileURL(button.profileURL)
    end)
    row.warcraftLogs:Hide()

    return row
end

local function updateDetailScrollLayout(panel, rowCount, scrollTop, resetScroll)
    local contentHeight = math.max(1, rowCount * ROW_HEIGHT)
    scrollTop = scrollTop or DEFAULT_SCROLL_TOP
    local previousScroll = resetScroll and 0 or math.max(0, panel.scroll:GetVerticalScroll() or 0)

    panel.scroll:ClearAllPoints()
    panel.scroll:SetPoint("TOPLEFT", 16, scrollTop)
    panel.scroll:SetPoint("BOTTOMRIGHT", -34, 14)

    local viewportHeight = math.max(0, panel.scroll:GetHeight() or 0)
    local needsScrollBar = contentHeight > (viewportHeight + 1)

    if panel.scrollBar then
        panel.scrollBar:SetShown(needsScrollBar)
    end

    panel.scroll:ClearAllPoints()
    panel.scroll:SetPoint("TOPLEFT", 16, scrollTop)
    panel.scroll:SetPoint("BOTTOMRIGHT", needsScrollBar and -34 or -16, 14)

    local scrollWidth = math.max(1, panel.scroll:GetWidth() or 1)
    local contentWidth = math.max(1, scrollWidth - (needsScrollBar and 24 or 0))
    panel.content:SetSize(contentWidth, contentHeight)

    for _, row in ipairs(panel.rows) do
        row:SetWidth(contentWidth)
    end

    local maxScroll = math.max(0, contentHeight - viewportHeight)
    panel.scroll:SetVerticalScroll(math.min(previousScroll, maxScroll))
end

function UI:CreateDetailPanel(parent)
    if self.detailPanel then
        return self.detailPanel
    end

    local panel = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    panel:SetPoint("TOPLEFT", 28, -158)
    panel:SetPoint("BOTTOMRIGHT", -28, 70)
    panel:SetFrameLevel(parent:GetFrameLevel() + 10)
    panel:EnableMouse(true)
    Theme:ApplyBackdrop(panel, Theme.background, Theme.border)

    panel.icon = panel:CreateTexture(nil, "ARTWORK")
    panel.icon:SetSize(30, 30)
    panel.icon:SetPoint("TOPLEFT", 17, -14)
    panel.icon:SetDesaturated(true)
    panel.icon:SetAlpha(0.55)

    panel.title = Theme:CreateText(panel, "GameFontNormalLarge", 19, Theme.text)
    panel.title:SetPoint("TOPLEFT", 58, -14)
    panel.title:SetPoint("RIGHT", -120, 0)
    panel.title:SetJustifyH("LEFT")

    panel.subtitle = Theme:CreateText(panel, "GameFontHighlightSmall", 11, Theme.muted)
    panel.subtitle:SetPoint("TOPLEFT", panel.title, "BOTTOMLEFT", 0, -5)
    panel.subtitle:SetPoint("RIGHT", -120, 0)
    panel.subtitle:SetJustifyH("LEFT")

    panel.back = Theme:CreateButton(panel, L.DETAIL_BACK, 88)
    panel.back:SetPoint("TOPRIGHT", -15, -14)
    panel.back:SetScript("OnClick", function()
        UI:CloseDetails()
    end)

    panel.divider = panel:CreateTexture(nil, "ARTWORK")
    panel.divider:SetColorTexture(unpack(Theme.border))
    panel.divider:SetPoint("TOPLEFT", 16, -63)
    panel.divider:SetPoint("TOPRIGHT", -16, -63)
    panel.divider:SetHeight(1)

    panel.searchBox = CreateFrame("EditBox", nil, panel, "BackdropTemplate")
    panel.searchBox:SetHeight(28)
    panel.searchBox:SetPoint("TOPLEFT", 16, -73)
    panel.searchBox:SetPoint("TOPRIGHT", -16, -73)
    panel.searchBox:SetAutoFocus(false)
    panel.searchBox:SetFontObject(GameFontHighlightSmall)
    Theme:ApplyFont(panel.searchBox, 11)
    panel.searchBox:SetTextInsets(10, 10, 0, 0)
    panel.searchBox:SetTextColor(unpack(Theme.text))
    Theme:ApplyBackdrop(panel.searchBox, Theme.surface, Theme.border)

    panel.searchPlaceholder = Theme:CreateText(panel.searchBox, "GameFontHighlightSmall", 11, Theme.muted)
    panel.searchPlaceholder:SetPoint("LEFT", 10, 0)
    panel.searchPlaceholder:SetText(L.DETAIL_NPC_SEARCH)

    panel.searchBox:SetScript("OnTextChanged", function(editBox)
        local text = editBox:GetText() or ""
        Theme:ApplyTextFont(editBox, text)
        panel.searchPlaceholder:SetShown(text == "")
        local normalized = normalizeSearchText(text)
        if UI.detailKey == "npcs" and UI.npcSearchText ~= normalized then
            UI.npcSearchText = normalized
            UI:RefreshDetails(nil, true)
        elseif UI.detailKey == "companion" and UI.companionSearchText ~= normalized then
            UI.companionSearchText = normalized
            UI:RefreshDetails(nil, true)
        elseif UI.detailKey == "identity" and UI.characterSearchText ~= normalized then
            UI.characterSearchText = normalized
            UI:RefreshDetails(nil, true)
        end
    end)
    panel.searchBox:SetScript("OnEnterPressed", function(editBox)
        editBox:ClearFocus()
    end)
    panel.searchBox:SetScript("OnEscapePressed", function(editBox)
        editBox:ClearFocus()
        if UI.frame then
            UI.frame:Hide()
        end
    end)
    panel.searchBox:Hide()

    panel.activityTabs = {}
    local activityTabDefinitions = {
        { key = "all", label = L.ACTIVITY_TAB_ALL },
        { key = "dungeon", label = L.ACTIVITY_TAB_DUNGEONS },
        { key = "raid", label = L.ACTIVITY_TAB_RAIDS },
        { key = "outdoor", label = L.ACTIVITY_TAB_OUTDOOR },
    }
    local previousTab
    for _, definition in ipairs(activityTabDefinitions) do
        local filterKey = definition.key
        local tab = Theme:CreateButton(panel, definition.label, ACTIVITY_TAB_WIDTH)
        tab:SetSize(ACTIVITY_TAB_WIDTH, 28)
        if previousTab then
            tab:SetPoint("LEFT", previousTab, "RIGHT", 6, 0)
        else
            tab:SetPoint("TOPLEFT", 16, -73)
        end
        tab:SetScript("OnClick", function()
            UI.activityFilter = filterKey
            UI:RefreshDetails(nil, true)
        end)
        tab:Hide()
        panel.activityTabs[filterKey] = tab
        previousTab = tab
    end

    panel.scroll = CreateFrame("ScrollFrame", ADDON_NAME .. "DetailScrollFrame", panel, "UIPanelScrollFrameTemplate")
    panel.scroll:SetPoint("TOPLEFT", 16, -76)
    panel.scroll:SetPoint("BOTTOMRIGHT", -34, 14)
    panel.scrollBar = panel.scroll.ScrollBar or _G[panel.scroll:GetName() .. "ScrollBar"]

    panel.content = CreateFrame("Frame", nil, panel.scroll)
    panel.content:SetSize(790, 1)
    panel.scroll:SetScrollChild(panel.content)
    panel.rows = {}

    if self.CreateCalendarView then
        self:CreateCalendarView(panel)
    end
    if self.CreateGoldChart then
        self:CreateGoldChart(panel)
    end

    panel:Hide()
    self.detailPanel = panel
    return panel
end

function UI:GetDetailRows(detailKey, summary)
    local builder = DETAIL_BUILDERS[detailKey]
    return builder and builder(summary) or {}
end

function UI:RefreshDetails(summary, resetScroll)
    local panel = self.detailPanel
    local card = self.detailKey and self.cards[self.detailKey]
    if not panel or not card then
        return
    end

    local isNPCDetail = self.detailKey == "npcs"
    local isCompanionDetail = self.detailKey == "companion"
    local isCharacterDetail = self.detailKey == "identity"
    local hasSearch = isNPCDetail or isCompanionDetail or isCharacterDetail
    local hasActivityTabs = self.detailKey == "activities"
    local hasCalendar = self.detailKey == "time" and panel.calendarView and self.RefreshCalendar
    local hasGoldChart = self.detailKey == "gold" and panel.goldChart and self.RefreshGoldChart
    local scrollTop = hasGoldChart and GOLD_SCROLL_TOP
        or (hasActivityTabs or hasSearch) and SEARCH_SCROLL_TOP
        or DEFAULT_SCROLL_TOP
    local searchPlaceholder = isCompanionDetail and L.DETAIL_COMPANION_SEARCH
        or isCharacterDetail and L.DETAIL_CHARACTER_SEARCH
        or L.DETAIL_NPC_SEARCH
    panel.searchPlaceholder:SetText(searchPlaceholder)
    panel.searchBox:SetShown(hasSearch)
    for key, tab in pairs(panel.activityTabs) do
        tab:SetShown(hasActivityTabs)
        Theme:SetButtonSelected(tab, hasActivityTabs and self.activityFilter == key)
    end
    panel.scroll:ClearAllPoints()
    panel.scroll:SetPoint("TOPLEFT", 16, scrollTop)
    panel.scroll:SetPoint("BOTTOMRIGHT", -34, 14)

    summary = summary or self.currentSummary

    panel.title:SetText(L[card.definition.titleKey])
    panel.title:SetTextColor(unpack(card.definition.accent))
    panel.icon:SetTexture(card.definition.icon)

    local periodLabel = self.previewMode and L.PREVIEW or AW.Periods:GetLabel(self.periodKey)
    panel.subtitle:SetText(string.format("%s  •  %s", periodLabel, L.DETAIL_SUBTITLE))

    panel.scroll:SetShown(not hasCalendar)
    if panel.calendarView then
        panel.calendarView:SetShown(hasCalendar and true or false)
    end
    if panel.goldChart then
        panel.goldChart:SetShown(hasGoldChart and true or false)
    end
    if hasCalendar then
        self:RefreshCalendar(summary)
        return
    end
    if hasGoldChart then
        self:RefreshGoldChart(summary)
    end

    local rows = self:GetDetailRows(self.detailKey, summary)
    local totalRows = #rows

    if totalRows == 0 then
        local hasNPCSearch = isNPCDetail and (self.npcSearchText or "") ~= ""
        local hasCompanionSearch = isCompanionDetail and (self.companionSearchText or "") ~= ""
        local hasCharacterSearch = isCharacterDetail and (self.characterSearchText or "") ~= ""
        local emptyLabel = hasNPCSearch and L.DETAIL_NPC_SEARCH_EMPTY
            or hasCompanionSearch and L.DETAIL_COMPANION_SEARCH_EMPTY
            or hasCharacterSearch and L.DETAIL_CHARACTER_SEARCH_EMPTY
            or L.DETAIL_EMPTY
        rows[1] = { label = emptyLabel, detail = "", value = "" }
    elseif totalRows > MAX_DETAIL_ROWS and self.detailKey ~= "activities" then
        for index = totalRows, MAX_DETAIL_ROWS + 1, -1 do
            rows[index] = nil
        end
        appendRow(rows, string.format(L.DETAIL_MORE, totalRows - MAX_DETAIL_ROWS), "", "")
    end

    for index, rowData in ipairs(rows) do
        local row = panel.rows[index]
        if not row then
            row = self:CreateDetailRow(panel.content, index)
            panel.rows[index] = row
        end

        Theme:SetText(row.label, rowData.label)
        Theme:SetText(row.detail, rowData.detail)
        Theme:SetText(row.value, rowData.value)
        row:SetBackdropBorderColor(unpack(Theme.border))
        local classColor = Util:GetClassColor(rowData.classFile)
        row.label:SetTextColor(unpack(classColor or Theme.text))

        row.waypoint:ClearAllPoints()
        row.raiderIO:ClearAllPoints()
        row.warcraftLogs:ClearAllPoints()
        row.value:ClearAllPoints()
        row.waypoint:Hide()
        row.raiderIO:Hide()
        row.warcraftLogs:Hide()

        local actionButtons = {}
        if rowData.waypoint then
            row.waypoint.data = rowData.waypoint
            actionButtons[#actionButtons + 1] = row.waypoint
        else
            row.waypoint.data = nil
        end

        if rowData.warcraftLogsURL then
            row.warcraftLogs.profileURL = rowData.warcraftLogsURL
            actionButtons[#actionButtons + 1] = row.warcraftLogs
        else
            row.warcraftLogs.profileURL = nil
        end

        if rowData.raiderIOURL then
            row.raiderIO.profileURL = rowData.raiderIOURL
            actionButtons[#actionButtons + 1] = row.raiderIO
        else
            row.raiderIO.profileURL = nil
        end

        local previousAction
        for _, actionButton in ipairs(actionButtons) do
            if previousAction then
                actionButton:SetPoint("RIGHT", previousAction, "LEFT", -6, 0)
            else
                actionButton:SetPoint("RIGHT", -10, 0)
            end
            actionButton:Show()
            previousAction = actionButton
        end

        if previousAction then
            row.value:SetPoint("RIGHT", previousAction, "LEFT", -8, 0)
            row.value:SetWidth(100)
        else
            row.value:SetPoint("RIGHT", -13, 0)
            row.value:SetWidth(180)
        end

        local textRightInset = previousAction and -225 or -205
        for index = 2, #actionButtons do
            textRightInset = textRightInset - actionButtons[index]:GetWidth() - 6
        end
        row.label:ClearAllPoints()
        row.detail:ClearAllPoints()
        row.detail:SetPoint("TOPLEFT", 13, -27)
        row.detail:SetPoint("RIGHT", textRightInset, 0)
        if rowData.detail and rowData.detail ~= "" then
            row.label:SetPoint("TOPLEFT", 13, -8)
            row.label:SetPoint("RIGHT", textRightInset, 0)
            row.detail:Show()
        else
            row.label:SetPoint("LEFT", 13, 0)
            row.label:SetPoint("RIGHT", textRightInset, 0)
            row.detail:Hide()
        end

        row:Show()
    end

    for index = #rows + 1, #panel.rows do
        panel.rows[index]:Hide()
    end

    updateDetailScrollLayout(panel, #rows, scrollTop, resetScroll)
end

function UI:OpenDetails(detailKey)
    local card = self.cards[detailKey]
    if not card then
        return
    end

    self.detailKey = detailKey
    if detailKey == "activities" then
        self.activityFilter = "all"
    end
    for _, summaryCard in pairs(self.cards) do
        summaryCard:Hide()
    end
    self.detailPanel:Show()
    self:RefreshDetails(nil, true)
end

function UI:CloseDetails()
    self.detailKey = nil
    if self.detailPanel then
        self.npcSearchText = ""
        self.companionSearchText = ""
        self.characterSearchText = ""
        self.activityFilter = "all"
        self.detailPanel.searchBox:SetText("")
        self.detailPanel.searchBox:ClearFocus()
        if self.detailPanel.calendarView then
            self.detailPanel.calendarView:Hide()
        end
        if self.detailPanel.goldChart then
            self.detailPanel.goldChart:Hide()
        end
        self.detailPanel:Hide()
    end
    if GameTooltip then
        GameTooltip:Hide()
    end
    for _, summaryCard in pairs(self.cards) do
        summaryCard:Show()
    end
end
