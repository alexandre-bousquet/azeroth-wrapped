-- Calendar heatmap and daily activity panel.
local ADDON_NAME, AW = ...

local UI = AW.UI
local L = AW.L
local Theme = AW.Theme
local Util = AW.Util

local GRID_LEFT = 34
local GRID_TOP = -58
local MAX_CELL_SIZE = 18
local MIN_CELL_SIZE = 6
local ACTIVITY_ROW_HEIGHT = 38

local INTENSITY_COLORS = {
    { 0.065, 0.082, 0.125, 0.98 },
    { 0.055, 0.18, 0.20, 1 },
    { 0.07, 0.31, 0.32, 1 },
    { 0.12, 0.50, 0.49, 1 },
    Theme.cyan,
}

local CATEGORY_COLORS = {
    dungeon = Theme.gold,
    raid = Theme.danger,
    outdoor = Theme.purple,
}

local CATEGORY_ICONS = {
    dungeon = "Interface/Icons/INV_Misc_Key_14",
    raid = "Interface/Icons/Achievement_Boss_LichKing",
    outdoor = "Interface/Icons/INV_Misc_Map_01",
}

local function splitLocalizedNames(value)
    local names = {}
    for name in string.gmatch(tostring(value or ""), "[^|]+") do
        names[#names + 1] = name
    end
    return names
end

local WEEKDAY_NAMES = splitLocalizedNames(L.CALENDAR_WEEKDAY_NAMES)
local MONTH_NAMES = splitLocalizedNames(L.CALENDAR_MONTH_NAMES)
local SHORT_MONTH_NAMES = splitLocalizedNames(L.CALENDAR_SHORT_MONTH_NAMES)

local function formatCalendarDate(timestamp)
    local value = date("*t", timestamp)
    local weekday = ((value.wday + 5) % 7) + 1
    local replacements = {
        weekday = WEEKDAY_NAMES[weekday] or "",
        day = tostring(value.day),
        month = MONTH_NAMES[value.month] or tostring(value.month),
        year = tostring(value.year),
    }
    return (string.gsub(L.CALENDAR_DATE_PATTERN, "{(%w+)}", function(token)
        return replacements[token] or token
    end))
end

local function formatCalendarMonth(timestamp)
    local value = date("*t", timestamp)
    return SHORT_MONTH_NAMES[value.month] or tostring(value.month)
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

local function normalizeDetail(value)
    value = Util:UTF8Lower(tostring(value or ""))
    value = string.gsub(value, "^%s+", "")
    return string.gsub(value, "%s+$", "")
end

local function joinUniqueDetails(excludedValue, ...)
    local parts = {}
    local seen = {}
    local excludedKey = normalizeDetail(excludedValue)
    if excludedKey ~= "" then
        seen[excludedKey] = true
    end

    for index = 1, select("#", ...) do
        local value = select(index, ...)
        local key = normalizeDetail(value)
        if key ~= "" and not seen[key] then
            parts[#parts + 1] = tostring(value)
            seen[key] = true
        end
    end
    return table.concat(parts, "  •  ")
end

local function getIntensity(day)
    local onlineSeconds = tonumber(day and day.onlineSeconds) or 0
    local activeSeconds = tonumber(day and day.activeSeconds) or 0
    if onlineSeconds <= 0 then
        return 1
    elseif activeSeconds < 1800 then
        return 2
    elseif activeSeconds < 7200 then
        return 3
    elseif activeSeconds < 14400 then
        return 4
    end
    return 5
end

local function formatCount(count, singular, plural)
    return Util:FormatCount(count or 0, singular, plural)
end

local function getActivityCategory(activity)
    if activity.category == "raid" then
        return "raid"
    elseif activity.category == "dungeon" then
        return "dungeon"
    end
    return "outdoor"
end

local function formatActivityDetail(activity, displayName)
    local category = getActivityCategory(activity)
    local categoryLabel = category == "raid" and L.DETAIL_RAID
        or category == "dungeon" and L.DETAIL_DUNGEON
        or L.DETAIL_OUTDOOR
    local kindLabel = L["DETAIL_ACTIVITY_KIND_" .. (activity.kind or "other")]
    local difficultyLabel = activity.difficultyName
    local timerLabel
    local runSeconds = tonumber(activity.runSeconds)

    if category == "dungeon" then
        local keystoneLevel = tonumber(activity.keystoneLevel)
        if keystoneLevel and keystoneLevel > 0 then
            difficultyLabel = string.format(L.DETAIL_MYTHIC_PLUS, keystoneLevel)
        end
    elseif activity.kind == "delve" then
        local delveTier = tonumber(activity.delveTier)
        difficultyLabel = delveTier and delveTier > 0
            and string.format(L.DETAIL_DELVE_TIER, delveTier)
            or L.DETAIL_DELVE_TIER_UNKNOWN
    end

    if runSeconds and runSeconds > 0 then
        timerLabel = string.format(L.DETAIL_ACTIVITY_TIMER, Util:FormatTimer(runSeconds))
    end

    return joinUniqueDetails(
        displayName,
        categoryLabel,
        kindLabel,
        difficultyLabel,
        timerLabel,
        activity.instanceName
    )
end

local function formatActivityValue(activity)
    local completions = math.max(1, tonumber(activity.completions) or 1)
    if activity.legacyAggregate and completions > 1 then
        return string.format(L.CALENDAR_ACTIVITY_MULTIPLE, completions)
    elseif activity.completedAt then
        return date(L.CALENDAR_ACTIVITY_TIME_FORMAT, activity.completedAt)
    end
    return ""
end

local function createActivityRow(parent, index)
    local row = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    row:SetPoint("TOPLEFT", 0, -((index - 1) * ACTIVITY_ROW_HEIGHT))
    row:SetPoint("RIGHT", 0, 0)
    row:SetHeight(ACTIVITY_ROW_HEIGHT - 3)
    Theme:ApplyBackdrop(row, index % 2 == 0 and Theme.surfaceHover or Theme.surface, Theme.border)

    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(22, 22)
    row.icon:SetPoint("LEFT", 9, 0)

    row.label = Theme:CreateText(row, "GameFontHighlight", 12, Theme.text)
    row.label:SetPoint("TOPLEFT", 40, -5)
    row.label:SetPoint("RIGHT", -138, 0)
    row.label:SetJustifyH("LEFT")
    row.label:SetWordWrap(false)

    row.detail = Theme:CreateText(row, "GameFontHighlightSmall", 9, Theme.muted)
    row.detail:SetPoint("TOPLEFT", 40, -21)
    row.detail:SetPoint("RIGHT", -138, 0)
    row.detail:SetJustifyH("LEFT")
    row.detail:SetWordWrap(false)

    row.value = Theme:CreateText(row, "GameFontHighlightSmall", 10, Theme.text)
    row.value:SetPoint("RIGHT", -10, 0)
    row.value:SetWidth(120)
    row.value:SetJustifyH("RIGHT")

    row.character = Theme:CreateText(row, "GameFontHighlightSmall", 9, Theme.muted)
    row.character:SetWidth(120)
    row.character:SetJustifyH("RIGHT")
    row.character:SetWordWrap(false)
    row.character:Hide()

    return row
end

function UI:CreateCalendarView(panel)
    if panel.calendarView then
        return panel.calendarView
    end

    local view = CreateFrame("Frame", nil, panel)
    view:SetPoint("TOPLEFT", 16, -76)
    view:SetPoint("BOTTOMRIGHT", -16, 14)
    view.cells = {}
    view.monthLabels = {}
    view.activityRows = {}

    view.title = Theme:CreateText(view, "GameFontNormal", 13, Theme.cyan)
    view.title:SetPoint("TOPLEFT", 0, -1)
    view.title:SetText(L.CALENDAR_TITLE)

    view.periodStats = Theme:CreateText(view, "GameFontHighlightSmall", 9, Theme.muted)
    view.periodStats:SetPoint("TOPLEFT", 0, -22)
    view.periodStats:SetPoint("RIGHT", 0, 0)
    view.periodStats:SetJustifyH("LEFT")

    view.legend = CreateFrame("Frame", nil, view)
    view.legend:SetSize(170, 18)
    view.legend:SetPoint("TOPRIGHT", 0, 0)
    view.legend.less = Theme:CreateText(view.legend, "GameFontHighlightSmall", 9, Theme.muted)
    view.legend.less:SetText(L.CALENDAR_LESS)
    local swatches = {}
    for index = 2, #INTENSITY_COLORS do
        local swatch = view.legend:CreateTexture(nil, "ARTWORK")
        swatch:SetSize(9, 9)
        swatch:SetColorTexture(unpack(INTENSITY_COLORS[index]))
        swatches[#swatches + 1] = swatch
    end
    view.legend.more = Theme:CreateText(view.legend, "GameFontHighlightSmall", 9, Theme.muted)
    view.legend.more:SetPoint("RIGHT", 0, 0)
    view.legend.more:SetText(L.CALENDAR_MORE)

    local previous = view.legend.more
    for index = #swatches, 1, -1 do
        swatches[index]:SetPoint("RIGHT", previous, "LEFT", -3, 0)
        previous = swatches[index]
    end
    view.legend.less:SetPoint("RIGHT", previous, "LEFT", -7, 0)

    view.weekdayLabels = {}
    for weekday = 1, 7 do
        local label = Theme:CreateText(view, "GameFontHighlightSmall", 9, Theme.muted)
        label:SetWidth(24)
        label:SetJustifyH("RIGHT")
        label:SetText(L["CALENDAR_WEEKDAY_" .. weekday])
        view.weekdayLabels[weekday] = label
    end

    view.dayPanel = CreateFrame("Frame", nil, view)
    view.dayPanel:SetPoint("LEFT", 0, 0)
    view.dayPanel:SetPoint("RIGHT", 0, 0)
    view.dayPanel:SetHeight(1)

    view.dayTitle = Theme:CreateText(view.dayPanel, "GameFontNormal", 13, Theme.text)
    view.dayTitle:SetPoint("TOPLEFT", 0, 0)
    view.dayTitle:SetPoint("RIGHT", -180, 0)
    view.dayTitle:SetJustifyH("LEFT")

    view.dayStats = Theme:CreateText(view.dayPanel, "GameFontHighlightSmall", 10, Theme.muted)
    view.dayStats:SetPoint("TOPLEFT", view.dayTitle, "BOTTOMLEFT", 0, -4)
    view.dayStats:SetPoint("RIGHT", 0, 0)
    view.dayStats:SetJustifyH("LEFT")

    view.activityTitle = Theme:CreateText(view.dayPanel, "GameFontNormalSmall", 10, Theme.cyan)
    view.activityTitle:SetPoint("TOPLEFT", view.dayStats, "BOTTOMLEFT", 0, -16)
    view.activityTitle:SetText(L.CALENDAR_ACTIVITIES_TITLE)

    view.activityScroll = CreateFrame(
        "ScrollFrame",
        ADDON_NAME .. "CalendarActivityScrollFrame",
        view.dayPanel,
        "UIPanelScrollFrameTemplate"
    )
    view.activityScroll:SetPoint("TOPLEFT", view.activityTitle, "BOTTOMLEFT", 0, -7)
    view.activityScroll:SetPoint("BOTTOMRIGHT", view, "BOTTOMRIGHT", -22, 0)
    view.activityScrollBar = view.activityScroll.ScrollBar
        or _G[view.activityScroll:GetName() .. "ScrollBar"]

    view.activityList = CreateFrame("Frame", nil, view.activityScroll)
    view.activityList:SetSize(1, 1)
    view.activityScroll:SetScrollChild(view.activityList)

    view.empty = Theme:CreateText(view.activityList, "GameFontHighlight", 11, Theme.muted)
    view.empty:SetPoint("TOPLEFT", 3, -6)
    view.empty:SetText(L.CALENDAR_NO_ACTIVITIES)

    view:Hide()
    panel.calendarView = view
    return view
end

function UI:UpdateCalendarCellBorder(cell)
    if not cell or not cell.day then
        return
    end

    if self.calendarSelectedDayKey == cell.day.key then
        cell:SetBackdropBorderColor(unpack(Theme.cyan))
    elseif cell.day.isToday then
        cell:SetBackdropBorderColor(unpack(Theme.gold))
    else
        cell:SetBackdropBorderColor(unpack(Theme.border))
    end
end

function UI:ShowCalendarTooltip(cell)
    local day = cell and cell.day
    if not day or not GameTooltip then
        return
    end

    GameTooltip:SetOwner(cell, "ANCHOR_RIGHT")
    GameTooltip:SetText(
        formatCalendarDate(day.timestamp),
        Theme.text[1],
        Theme.text[2],
        Theme.text[3]
    )
    GameTooltip:AddLine(string.format(L.CALENDAR_TOOLTIP_TIME,
        Util:FormatDuration(day.onlineSeconds),
        Util:FormatDuration(day.activeSeconds),
        Util:FormatDuration(day.afkSeconds)
    ), Theme.muted[1], Theme.muted[2], Theme.muted[3], true)
    GameTooltip:AddLine(joinDetails(
        formatCount(day.sessionCount, L.CALENDAR_SESSION_ONE, L.CALENDAR_SESSION_MANY),
        formatCount(day.completedActivityCount, L.CALENDAR_ACTIVITY_ONE, L.CALENDAR_ACTIVITY_MANY),
        formatCount(day.deaths, L.DETAIL_DEATHS_ONE, L.DETAIL_DEATHS)
    ), Theme.muted[1], Theme.muted[2], Theme.muted[3], true)

    GameTooltip:Show()
end

function UI:SelectCalendarDay(dayKey)
    local view = self.detailPanel and self.detailPanel.calendarView
    if not view or not view.timeline or not view.timeline.daysByKey[dayKey] then
        return
    end

    self.calendarSelectedDayKey = dayKey
    self:RefreshCalendarDay(view.timeline.daysByKey[dayKey])
    for _, cell in ipairs(view.cells) do
        if cell:IsShown() then
            self:UpdateCalendarCellBorder(cell)
        end
    end
end

function UI:RefreshCalendarDay(day)
    local view = self.detailPanel and self.detailPanel.calendarView
    if not view or not day then
        return
    end

    Theme:SetText(view.dayTitle, formatCalendarDate(day.timestamp))
    Theme:SetText(view.dayStats, joinDetails(
        string.format(L.CALENDAR_ONLINE, Util:FormatDuration(day.onlineSeconds)),
        string.format(L.CALENDAR_ACTIVE, Util:FormatDuration(day.activeSeconds)),
        string.format(L.CALENDAR_AFK, Util:FormatDuration(day.afkSeconds)),
        formatCount(day.sessionCount, L.CALENDAR_SESSION_ONE, L.CALENDAR_SESSION_MANY),
        formatCount(day.completedActivityCount, L.CALENDAR_ACTIVITY_ONE, L.CALENDAR_ACTIVITY_MANY),
        formatCount(day.deaths, L.DETAIL_DEATHS_ONE, L.DETAIL_DEATHS)
    ))

    local activities = day.completedActivities or {}
    local showActivityCharacters = UI:ShouldShowActivityCharacters()
    local resetScroll = view.displayedDayKey ~= day.key
    view.displayedDayKey = day.key
    view.empty:SetShown(#activities == 0)

    for index, activity in ipairs(activities) do
        local row = view.activityRows[index]
        if not row then
            row = createActivityRow(view.activityList, index)
            view.activityRows[index] = row
        end
        local category = getActivityCategory(activity)
        local color = CATEGORY_COLORS[category] or Theme.text
        row.icon:SetTexture(CATEGORY_ICONS[category])
        row.icon:SetVertexColor(color[1], color[2], color[3])
        Theme:SetText(row.label, activity.name or L.UNKNOWN_ACTIVITY)
        Theme:SetText(row.detail, formatActivityDetail(activity, activity.name))
        Theme:SetText(row.value, formatActivityValue(activity))
        row.value:ClearAllPoints()
        row.character:ClearAllPoints()
        row.character:Hide()

        local activityCharacter = activity.characterKey
            and AW.Database.db.characters
            and AW.Database.db.characters[activity.characterKey]
        if showActivityCharacters and activityCharacter then
            row.value:SetPoint("TOPRIGHT", -10, -5)
            Theme:SetText(row.character, activityCharacter.name or L.UNKNOWN_PLAYER)
            row.character:SetPoint("BOTTOMRIGHT", -10, 5)
            local classColor = Util:GetClassColor(activityCharacter.classFile)
            row.character:SetTextColor(unpack(classColor or Theme.muted))
            row.character:Show()
        else
            row.value:SetPoint("RIGHT", -10, 0)
        end
        row:Show()
    end

    for index = #activities + 1, #view.activityRows do
        view.activityRows[index]:Hide()
    end

    local contentHeight = math.max(28, #activities * ACTIVITY_ROW_HEIGHT)
    local viewHeight = tonumber(view:GetHeight()) or 0
    if viewHeight < 200 then
        viewHeight = 470
    end
    local viewportHeight = math.max(0, tonumber(view.activityScroll:GetHeight()) or 0)
    if viewportHeight < 20 then
        viewportHeight = math.max(20, viewHeight + (view.dayPanel.awTopOffset or -200) - 62)
    end
    local previousScroll = resetScroll and 0 or math.max(0, view.activityScroll:GetVerticalScroll() or 0)
    local needsScrollBar = contentHeight > (viewportHeight + 1)
    if view.activityScrollBar then
        view.activityScrollBar:SetShown(needsScrollBar)
    end

    local scrollWidth = tonumber(view.activityScroll:GetWidth()) or 0
    if scrollWidth < 100 then
        local viewWidth = tonumber(view:GetWidth()) or 0
        scrollWidth = (viewWidth >= 300 and viewWidth or 820) - 22
    end
    local contentWidth = math.max(1, scrollWidth - 2)
    view.activityList:SetSize(contentWidth, contentHeight)
    local maxScroll = math.max(0, contentHeight - viewportHeight)
    view.activityScroll:SetVerticalScroll(math.min(previousScroll, maxScroll))
end

local function getOrCreateCalendarCell(view, index)
    local cell = view.cells[index]
    if cell then
        return cell
    end

    cell = CreateFrame("Button", nil, view, "BackdropTemplate")
    Theme:ApplyBackdrop(cell, Theme.surface, Theme.border)
    cell.dayNumber = Theme:CreateText(cell, "GameFontHighlightSmall", 10, Theme.text)
    cell.dayNumber:SetPoint("LEFT", 6, 0)
    cell.activityCount = Theme:CreateText(cell, "GameFontHighlightSmall", 9, Theme.gold)
    cell.activityCount:SetPoint("RIGHT", -6, 0)
    cell.activityMarks = {}
    for markerIndex = 1, 3 do
        local marker = cell:CreateTexture(nil, "OVERLAY")
        marker:Hide()
        cell.activityMarks[markerIndex] = marker
    end
    cell:SetScript("OnEnter", function(button)
        button:SetBackdropBorderColor(unpack(Theme.text))
        UI:ShowCalendarTooltip(button)
    end)
    cell:SetScript("OnLeave", function(button)
        UI:UpdateCalendarCellBorder(button)
        if GameTooltip then
            GameTooltip:Hide()
        end
    end)
    cell:SetScript("OnClick", function(button)
        if button.day then
            UI:SelectCalendarDay(button.day.key)
        end
    end)
    view.cells[index] = cell
    return cell
end

local function updateActivityMarkers(cell, day, cellWidth, cellHeight)
    local categories = {}
    for _, category in ipairs({ "dungeon", "raid", "outdoor" }) do
        if (tonumber(day.activityCounts and day.activityCounts[category]) or 0) > 0 then
            categories[#categories + 1] = category
        end
    end

    local markerGap = cellHeight >= 10 and 1 or 0
    local markerHeight = cellHeight >= 10 and 3 or 1
    local availableWidth = math.max(1, cellWidth - 2 - ((#categories - 1) * markerGap))
    local markerWidth = #categories > 0 and math.max(1, math.floor(availableWidth / #categories)) or 1
    local offset = 1

    for index, marker in ipairs(cell.activityMarks) do
        marker:ClearAllPoints()
        local category = categories[index]
        if category then
            marker:SetColorTexture(unpack(CATEGORY_COLORS[category]))
            marker:SetPoint("BOTTOMLEFT", offset, 1)
            marker:SetSize(markerWidth, markerHeight)
            marker:Show()
            offset = offset + markerWidth + markerGap
        else
            marker:Hide()
        end
    end
end

function UI:RefreshCalendar(summary)
    local panel = self.detailPanel
    local view = panel and panel.calendarView
    if not view then
        return
    end

    local timeline = self.previewMode and AW.Summary:BuildPreviewTimeline()
        or AW.Summary:BuildTimeline(self.periodKey, self.characterFilter)
    view.timeline = timeline
    summary = summary or self.currentSummary or {}
    Theme:SetText(view.periodStats, joinDetails(
        string.format(L.CALENDAR_ONLINE, Util:FormatDuration(summary.onlineSeconds)),
        string.format(L.CALENDAR_ACTIVE, Util:FormatDuration(summary.activeSeconds)),
        string.format(L.CALENDAR_AFK, Util:FormatDuration(summary.afkSeconds)),
        formatCount(summary.sessionCount, L.CALENDAR_SESSION_ONE, L.CALENDAR_SESSION_MANY),
        string.format(L.LONGEST_SESSION, Util:FormatDuration(summary.longestSession)),
        string.format(L.DAYS_PLAYED, summary.daysPlayed or 0)
    ))
    local days = timeline.days or {}
    if #days == 0 then
        return
    end

    local firstWeekday = days[1].weekday or 1
    local weekCount = math.floor(((firstWeekday - 1) + #days - 1) / 7) + 1
    local viewWidth = tonumber(view:GetWidth()) or 0
    if viewWidth < 300 then
        viewWidth = 820
    end
    local availableWidth = viewWidth - GRID_LEFT
    local compactCalendar = #days <= 42
    local gap = compactCalendar and 4 or (weekCount > 60 and 1 or 2)
    local cellWidth
    local cellHeight
    local horizontalStep
    local verticalStep
    local gridHeight

    if compactCalendar then
        cellWidth = math.floor((viewWidth - (6 * gap)) / 7)
        cellHeight = #days <= 7 and 32 or 24
        horizontalStep = cellWidth + gap
        verticalStep = cellHeight + gap
        gridHeight = (weekCount * cellHeight) + ((weekCount - 1) * gap)
    else
        cellWidth = math.floor((availableWidth - ((weekCount - 1) * gap)) / math.max(1, weekCount))
        cellWidth = math.max(MIN_CELL_SIZE, math.min(MAX_CELL_SIZE, cellWidth))
        cellHeight = cellWidth
        horizontalStep = cellWidth + gap
        verticalStep = cellHeight + gap
        gridHeight = (7 * cellHeight) + (6 * gap)
    end

    for weekday, label in ipairs(view.weekdayLabels) do
        label:ClearAllPoints()
        if compactCalendar then
            label:SetWidth(cellWidth)
            label:SetJustifyH("CENTER")
            label:SetPoint("BOTTOM", view, "TOPLEFT", ((weekday - 1) * horizontalStep) + (cellWidth / 2), GRID_TOP + 7)
        else
            label:SetWidth(24)
            label:SetJustifyH("RIGHT")
            label:SetPoint("RIGHT", view, "TOPLEFT", GRID_LEFT - 8, GRID_TOP - ((weekday - 1) * verticalStep) - (cellHeight / 2))
        end
    end

    local lastMonthX = -100
    local visibleMonthLabels = 0
    for index, day in ipairs(days) do
        local offset = (firstWeekday - 1) + index - 1
        local column = compactCalendar and (offset % 7) or math.floor(offset / 7)
        local row = compactCalendar and math.floor(offset / 7) or (offset % 7)
        local x = column * horizontalStep
        local cell = getOrCreateCalendarCell(view, index)
        cell:ClearAllPoints()
        cell:SetPoint("TOPLEFT", view, "TOPLEFT", (compactCalendar and 0 or GRID_LEFT) + x, GRID_TOP - (row * verticalStep))
        cell:SetSize(cellWidth, cellHeight)
        cell.day = day
        cell:SetBackdropColor(unpack(INTENSITY_COLORS[getIntensity(day)]))
        cell.dayNumber:SetShown(compactCalendar)
        cell.activityCount:SetShown(compactCalendar and day.completedActivityCount > 0)
        if compactCalendar then
            cell.dayNumber:SetText(tostring(date("*t", day.timestamp).day))
            cell.activityCount:SetText(string.format(L.CALENDAR_ACTIVITY_MULTIPLE, day.completedActivityCount))
        end
        updateActivityMarkers(cell, day, cellWidth, cellHeight)
        self:UpdateCalendarCellBorder(cell)
        cell:Show()

        local dayValue = date("*t", day.timestamp)
        if not compactCalendar and (index == 1 or dayValue.day == 1) then
            if x - lastMonthX >= 34 then
                visibleMonthLabels = visibleMonthLabels + 1
                local label = view.monthLabels[visibleMonthLabels]
                if not label then
                    label = Theme:CreateText(view, "GameFontHighlightSmall", 9, Theme.muted)
                    label:SetWidth(38)
                    label:SetJustifyH("LEFT")
                    view.monthLabels[visibleMonthLabels] = label
                end
                label:ClearAllPoints()
                label:SetPoint("BOTTOMLEFT", view, "TOPLEFT", GRID_LEFT + x, GRID_TOP + 7)
                label:SetText(formatCalendarMonth(day.timestamp))
                label:Show()
                lastMonthX = x
            end
        end
    end

    for index = #days + 1, #view.cells do
        view.cells[index].day = nil
        view.cells[index]:Hide()
    end
    for index = visibleMonthLabels + 1, #view.monthLabels do
        view.monthLabels[index]:Hide()
    end

    local selectedDay = timeline.daysByKey[self.calendarSelectedDayKey]
    if not selectedDay then
        for index = #days, 1, -1 do
            if days[index].onlineSeconds > 0 or days[index].completedActivityCount > 0 then
                selectedDay = days[index]
                break
            end
        end
        selectedDay = selectedDay or days[#days]
        self.calendarSelectedDayKey = selectedDay.key
    end

    local dayPanelTop = GRID_TOP - gridHeight - 22
    view.dayPanel:ClearAllPoints()
    view.dayPanel:SetPoint("TOPLEFT", view, "TOPLEFT", 0, dayPanelTop)
    view.dayPanel:SetPoint("RIGHT", 0, 0)
    view.dayPanel.awTopOffset = dayPanelTop
    self:RefreshCalendarDay(selectedDay)

    for _, cell in ipairs(view.cells) do
        if cell:IsShown() then
            self:UpdateCalendarCellBorder(cell)
        end
    end
end
