-- Generic detail-panel rendering and navigation.
local ADDON_NAME, AW = ...

local UI = AW.UI
local L = AW.L
local Theme = AW.Theme
local Util = AW.Util
local Helpers = UI.DetailHelpers
local DetailBuilders = UI.DetailBuilders

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

    row.character = Theme:CreateText(row, "GameFontHighlightSmall", 10, Theme.muted)
    row.character:SetWidth(180)
    row.character:SetJustifyH("RIGHT")
    row.character:SetWordWrap(false)
    row.character:Hide()

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
        local normalized = Helpers.normalizeSearchText(text)
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
    local builder = DetailBuilders[detailKey]
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
    panel.subtitle:SetText(string.format(
        "%s  •  %s  •  %s",
        periodLabel,
        self:GetCharacterFilterLabel(),
        L.DETAIL_SUBTITLE
    ))

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
        Helpers.appendRow(rows, string.format(L.DETAIL_MORE, totalRows - MAX_DETAIL_ROWS), "", "")
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
        Theme:SetText(row.character, rowData.characterName)
        row:SetBackdropBorderColor(unpack(Theme.border))
        local classColor = Util:GetClassColor(rowData.classFile)
        row.label:SetTextColor(unpack(classColor or Theme.text))

        row.waypoint:ClearAllPoints()
        row.raiderIO:ClearAllPoints()
        row.warcraftLogs:ClearAllPoints()
        row.value:ClearAllPoints()
        row.character:ClearAllPoints()
        row.character:Hide()
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

        if rowData.characterName and not previousAction then
            row.value:ClearAllPoints()
            row.value:SetPoint("TOPRIGHT", -13, -8)
            row.value:SetWidth(180)
            row.character:SetPoint("BOTTOMRIGHT", -13, 8)
            local characterColor = Util:GetClassColor(rowData.characterClassFile)
            row.character:SetTextColor(unpack(characterColor or Theme.muted))
            row.character:Show()
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
    self:ApplyCardLayout()
end

