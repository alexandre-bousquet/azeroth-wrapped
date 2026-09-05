-- Gold balance chart used by the details panel.
local _, AW = ...

local UI = AW.UI
local L = AW.L
local Theme = AW.Theme
local Util = AW.Util

local CHART_HEIGHT = 218
local PLOT_LEFT = 84
local PLOT_RIGHT = 16
local PLOT_TOP = 40
local PLOT_BOTTOM = 28
local MAX_VISIBLE_POINTS = 400
local LINE_CORE_THICKNESS = 2
local LINE_EDGE_THICKNESS = 4
local POINT_SIZE = 7
local COPPER_PER_GOLD = 10000
local TEN_THOUSAND_GOLD_IN_COPPER = 10000 * COPPER_PER_GOLD
local FIFTY_THOUSAND_GOLD_IN_COPPER = 50000 * COPPER_PER_GOLD
local ONE_HUNDRED_THOUSAND_GOLD_IN_COPPER = 100000 * COPPER_PER_GOLD
local FIVE_HUNDRED_THOUSAND_GOLD_IN_COPPER = 500000 * COPPER_PER_GOLD

local function hidePool(pool, firstUnused)
    for index = firstUnused, #pool do
        pool[index]:Hide()
    end
end

local function hideLinePool(pool, firstUnused)
    for index = firstUnused, #pool do
        pool[index].edge:Hide()
        pool[index].core:Hide()
    end
end

local function hasMoneyActivity(point)
    return (tonumber(point.changes) or 0) > 0 or (tonumber(point.net) or 0) ~= 0
end

local function trimToFirstMoneyActivity(points)
    local firstActivityIndex
    for index = 2, #points do
        if hasMoneyActivity(points[index]) then
            firstActivityIndex = index
            break
        end
    end

    if not firstActivityIndex then
        return {}
    end

    local firstActivity = points[firstActivityIndex]
    local previousPoint = points[firstActivityIndex - 1] or firstActivity
    local visible = {
        {
            timestamp = firstActivity.timestamp,
            balance = previousPoint.balance,
            opening = true,
        },
    }

    for index = firstActivityIndex, #points do
        visible[#visible + 1] = points[index]
    end
    return visible
end

local function selectVisiblePoints(points)
    if #points <= MAX_VISIBLE_POINTS then
        return points
    end

    local selectedIndexes = { [1] = true, [#points] = true }
    for index = 2, #points - 1 do
        if hasMoneyActivity(points[index]) then
            selectedIndexes[index] = true
        end
    end

    local step = (#points - 1) / (MAX_VISIBLE_POINTS - 1)
    for visibleIndex = 1, MAX_VISIBLE_POINTS do
        local pointIndex = math.floor(((visibleIndex - 1) * step) + 1.5)
        selectedIndexes[math.min(#points, math.max(1, pointIndex))] = true
    end

    local visible = {}
    local indexes = {}
    for index = 1, #points do
        if selectedIndexes[index] then
            visible[#visible + 1] = points[index]
            indexes[#indexes + 1] = index
        end
    end
    return visible, indexes
end

local function getAxisRoundingStep(minimum, maximum)
    local largestBalance = math.max(math.abs(minimum), math.abs(maximum))
    if largestBalance <= ONE_HUNDRED_THOUSAND_GOLD_IN_COPPER then
        return TEN_THOUSAND_GOLD_IN_COPPER
    elseif largestBalance <= FIVE_HUNDRED_THOUSAND_GOLD_IN_COPPER then
        return FIFTY_THOUSAND_GOLD_IN_COPPER
    end
    return ONE_HUNDRED_THOUSAND_GOLD_IN_COPPER
end

local function getOrCreateLine(chart, index)
    local segment = chart.lines[index]
    if not segment then
        local edge = chart.plot:CreateLine(nil, "ARTWORK")
        edge:SetThickness(LINE_EDGE_THICKNESS)
        edge:SetColorTexture(Theme.gold[1], Theme.gold[2], Theme.gold[3], 0.08)
        edge:SetSnapToPixelGrid(false)
        edge:SetTexelSnappingBias(0)

        local core = chart.plot:CreateLine(nil, "ARTWORK")
        core:SetThickness(LINE_CORE_THICKNESS)
        core:SetColorTexture(Theme.gold[1], Theme.gold[2], Theme.gold[3], 0.50)
        core:SetSnapToPixelGrid(false)
        core:SetTexelSnappingBias(0)

        segment = { edge = edge, core = core }
        chart.lines[index] = segment
    end
    return segment
end

local function showPointTooltip(button)
    local point = button.point
    if not point or not GameTooltip then
        return
    end

    GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
    GameTooltip:SetText(
        point.opening and L.GOLD_CHART_START or date(L.GOLD_CHART_DATE_FORMAT, point.timestamp),
        Theme.gold[1],
        Theme.gold[2],
        Theme.gold[3]
    )
    GameTooltip:AddLine(
        string.format(L.GOLD_CHART_BALANCE, Util:FormatGold(point.balance)),
        Theme.text[1],
        Theme.text[2],
        Theme.text[3]
    )
    if not point.opening then
        local net = tonumber(point.net) or 0
        local color = net < 0 and Theme.danger or (net > 0 and Theme.cyan or Theme.muted)
        GameTooltip:AddLine(
            string.format(L.GOLD_CHART_DAILY_CHANGE, Util:FormatGold(net, true)),
            color[1],
            color[2],
            color[3]
        )
    end
    GameTooltip:Show()
end

local function getOrCreatePoint(chart, index)
    local button = chart.points[index]
    if not button then
        button = CreateFrame("Button", nil, chart.plot)
        button:SetSize(14, 14)
        button:SetFrameLevel(chart.plot:GetFrameLevel() + 2)
        button.dot = button:CreateTexture(nil, "OVERLAY")
        button.dot:SetColorTexture(unpack(Theme.gold))
        button.dot:SetSize(POINT_SIZE, POINT_SIZE)
        button.dot:SetPoint("CENTER")
        button:SetScript("OnEnter", showPointTooltip)
        button:SetScript("OnLeave", function()
            if GameTooltip then
                GameTooltip:Hide()
            end
        end)
        chart.points[index] = button
    end
    return button
end

function UI:CreateGoldChart(panel)
    if panel.goldChart then
        return panel.goldChart
    end

    local chart = CreateFrame("Frame", nil, panel, "BackdropTemplate")
    chart:SetPoint("TOPLEFT", 16, -76)
    chart:SetPoint("TOPRIGHT", -16, -76)
    chart:SetHeight(CHART_HEIGHT)
    Theme:ApplyBackdrop(chart, Theme.surface, Theme.border)

    chart.title = Theme:CreateText(chart, "GameFontNormalSmall", 11, Theme.gold)
    chart.title:SetPoint("TOPLEFT", 12, -10)
    chart.title:SetText(L.GOLD_CHART_TITLE)

    chart.net = Theme:CreateText(chart, "GameFontHighlightSmall", 10, Theme.muted)
    chart.net:SetPoint("TOPRIGHT", -12, -10)
    chart.net:SetJustifyH("RIGHT")

    chart.plot = CreateFrame("Frame", nil, chart)
    chart.plot:SetPoint("TOPLEFT", PLOT_LEFT, -PLOT_TOP)
    chart.plot:SetPoint("BOTTOMRIGHT", -PLOT_RIGHT, PLOT_BOTTOM)

    chart.grid = {}
    chart.yLabels = {}
    for index = 1, 3 do
        local grid = chart.plot:CreateTexture(nil, "BACKGROUND")
        grid:SetColorTexture(Theme.border[1], Theme.border[2], Theme.border[3], 0.7)
        grid:SetPoint("LEFT", 0, 0)
        grid:SetPoint("RIGHT", 0, 0)
        grid:SetHeight(1)
        chart.grid[index] = grid

        local label = Theme:CreateText(chart, "GameFontHighlightSmall", 9, Theme.muted)
        label:SetWidth(PLOT_LEFT - 12)
        label:SetJustifyH("RIGHT")
        chart.yLabels[index] = label
    end

    chart.startDate = Theme:CreateText(chart, "GameFontHighlightSmall", 9, Theme.muted)
    chart.startDate:SetPoint("BOTTOMLEFT", PLOT_LEFT, 9)
    chart.endDate = Theme:CreateText(chart, "GameFontHighlightSmall", 9, Theme.muted)
    chart.endDate:SetPoint("BOTTOMRIGHT", -PLOT_RIGHT, 9)

    chart.empty = Theme:CreateText(chart, "GameFontHighlight", 11, Theme.muted)
    chart.empty:SetPoint("CENTER", chart.plot, "CENTER")
    chart.empty:SetText(L.GOLD_CHART_NO_DATA)

    chart.lines = {}
    chart.points = {}
    chart:Hide()
    panel.goldChart = chart
    return chart
end

function UI:RefreshGoldChart(summary)
    local chart = self.detailPanel and self.detailPanel.goldChart
    local timeline = summary and summary.moneyTimeline
    local sourcePoints = trimToFirstMoneyActivity(timeline and timeline.points or {})
    local linePoints, linePointIndexes = selectVisiblePoints(sourcePoints)
    local hasData = summary and summary.hasMoneyData and #sourcePoints >= 2

    chart.empty:SetShown(not hasData)
    chart.plot:SetShown(hasData and true or false)
    Theme:SetText(chart.net, timeline and string.format(L.GOLD_CHART_NET, Util:FormatGold(timeline.net, true)) or "")

    if not hasData then
        hideLinePool(chart.lines, 1)
        hidePool(chart.points, 1)
        Theme:SetText(chart.startDate, "")
        Theme:SetText(chart.endDate, "")
        for _, label in ipairs(chart.yLabels) do
            Theme:SetText(label, "")
        end
        return
    end

    local minimum = tonumber(sourcePoints[1].balance) or 0
    local maximum = minimum
    for _, point in ipairs(sourcePoints) do
        local balance = tonumber(point.balance) or 0
        minimum = math.min(minimum, balance)
        maximum = math.max(maximum, balance)
    end

    local roundingStep = getAxisRoundingStep(minimum, maximum)
    local axisMinimum = math.floor(minimum / roundingStep) * roundingStep
    local axisMaximum = math.ceil(maximum / roundingStep) * roundingStep
    if axisMinimum == axisMaximum then
        axisMinimum = axisMinimum - roundingStep
        axisMaximum = axisMaximum + roundingStep
    end
    local axisSpread = math.max(1, axisMaximum - axisMinimum)
    local plotWidth = math.max(1, chart.plot:GetWidth())
    local plotHeight = math.max(1, chart.plot:GetHeight())

    for index = 1, 3 do
        local ratio = (index - 1) / 2
        local y = plotHeight * (1 - ratio)
        local value = axisMinimum + (axisSpread * (1 - ratio))
        local grid = chart.grid[index]
        grid:ClearAllPoints()
        grid:SetPoint("LEFT", chart.plot, "BOTTOMLEFT", 0, y)
        grid:SetPoint("RIGHT", chart.plot, "BOTTOMRIGHT", 0, y)

        local label = chart.yLabels[index]
        label:ClearAllPoints()
        label:SetPoint("RIGHT", chart.plot, "BOTTOMLEFT", -7, y)
        Theme:SetText(label, Util:FormatGold(value))
    end

    local previousX
    local previousY
    for index, point in ipairs(linePoints) do
        local sourceIndex = linePointIndexes and linePointIndexes[index] or index
        local x = ((sourceIndex - 1) / (#sourcePoints - 1)) * plotWidth
        local y = ((tonumber(point.balance) or 0) - axisMinimum) / axisSpread * plotHeight

        if index > 1 then
            local segment = getOrCreateLine(chart, index - 1)
            for _, line in pairs(segment) do
                line:ClearAllPoints()
                line:SetStartPoint("BOTTOMLEFT", chart.plot, previousX, previousY)
                line:SetEndPoint("BOTTOMLEFT", chart.plot, x, y)
                line:Show()
            end
        end

        previousX = x
        previousY = y
    end

    local markerCount = 0
    for index, point in ipairs(sourcePoints) do
        if point.opening or hasMoneyActivity(point) then
            markerCount = markerCount + 1
            local x = ((index - 1) / (#sourcePoints - 1)) * plotWidth
            local y = ((tonumber(point.balance) or 0) - axisMinimum) / axisSpread * plotHeight
            local button = getOrCreatePoint(chart, markerCount)
            button:ClearAllPoints()
            button:SetPoint("CENTER", chart.plot, "BOTTOMLEFT", x, y)
            button.point = point
            button.dot:SetVertexColor(1, 1, 1, 1)
            button:Show()
        end
    end

    hideLinePool(chart.lines, #linePoints)
    hidePool(chart.points, markerCount + 1)
    Theme:SetText(chart.startDate, date(L.GOLD_CHART_DATE_FORMAT, sourcePoints[1].timestamp))
    Theme:SetText(chart.endDate, date(L.GOLD_CHART_DATE_FORMAT, sourcePoints[#sourcePoints].timestamp))
end
