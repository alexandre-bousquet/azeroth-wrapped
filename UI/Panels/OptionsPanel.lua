-- Blizzard Settings panel and addon preferences.
local _, AW = ...

AW.Options = {}
local Options = AW.Options
local L = AW.L

local LOCALE_OPTIONS = { "AUTO", "enUS", "frFR" }
local CARD_ROW_HEIGHT = 28
Options.resetPeriodKey = "ALL"

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
    if self.characterDropdown and AW.UI and AW.UI.GetCharacterFilterLabel then
        self.characterDropdown:SetDefaultText(AW.UI:GetCharacterFilterLabel(true))
    end
    if self.resetPeriodDropdown then
        self.resetPeriodDropdown:SetDefaultText(AW.Periods:GetResetLabel(self.resetPeriodKey))
    end
    if self.cardList then
        self:RefreshCardList()
    end
end

function Options:RefreshCardList()
    local order, hidden = AW.UI:GetCardOrder()
    self.cardListContent:SetHeight(math.max(1, #order * CARD_ROW_HEIGHT))
    local maximumOffset = math.max(0, (#order * CARD_ROW_HEIGHT) - self.cardList:GetHeight())
    self.cardList:SetVerticalScroll(math.min(self.cardList:GetVerticalScroll(), maximumOffset))

    for index, row in ipairs(self.cardRows) do
        local cardKey = order[index]
        local definition = cardKey and AW.UI.cardDefinitions[cardKey]
        row.cardKey = cardKey
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", 0, -((index - 1) * CARD_ROW_HEIGHT))
        row:SetPoint("RIGHT", -2, 0)
        row:SetHeight(CARD_ROW_HEIGHT - 2)
        row:SetShown(definition ~= nil)
        if definition then
            row.label:SetText(L[definition.titleKey])
            row.label:SetFontObject(hidden[cardKey] and GameFontDisable or GameFontHighlight)
            row.enabledCheck:SetChecked(not hidden[cardKey])
            local isDragged = cardKey == self.draggedCardKey
            row.highlight:SetShown(isDragged)
            row.handle:SetAlpha(isDragged and 0.45 or 0.8)
        end
    end
end

function Options:StartCardDrag(cardKey)
    if not cardKey then
        return
    end
    self.draggedCardKey = cardKey
    self.cardList:SetScript("OnUpdate", function(_, elapsed)
        Options:UpdateCardDrag(elapsed)
    end)
    self:RefreshCardList()
end

function Options:StopCardDrag()
    self.draggedCardKey = nil
    if self.cardList then
        self.cardList:SetScript("OnUpdate", nil)
        self:RefreshCardList()
    end
end

function Options:UpdateCardDrag(elapsed)
    if not self.draggedCardKey then
        return
    end
    if IsMouseButtonDown and not IsMouseButtonDown("LeftButton") then
        self:StopCardDrag()
        return
    end

    local _, cursorY = GetCursorPosition()
    local scale = self.cardList:GetEffectiveScale()
    local listTop = self.cardList:GetTop()
    if not cursorY or not scale or scale == 0 or not listTop then
        return
    end

    cursorY = cursorY / scale
    local listBottom = self.cardList:GetBottom()
    local maximumOffset = math.max(0, self.cardList:GetVerticalScrollRange())
    local scrollOffset = self.cardList:GetVerticalScroll()
    local scrollSpeed = CARD_ROW_HEIGHT * 5 * (tonumber(elapsed) or 0)
    if listBottom and cursorY < listBottom + 16 then
        scrollOffset = math.min(maximumOffset, scrollOffset + scrollSpeed)
        self.cardList:SetVerticalScroll(scrollOffset)
    elseif cursorY > listTop - 16 then
        scrollOffset = math.max(0, scrollOffset - scrollSpeed)
        self.cardList:SetVerticalScroll(scrollOffset)
    end

    local contentY = listTop - cursorY + scrollOffset
    local order = AW.UI:GetCardOrder()
    local targetIndex = math.max(1, math.min(#order, math.floor(contentY / CARD_ROW_HEIGHT) + 1))
    local currentIndex
    for index, cardKey in ipairs(order) do
        if cardKey == self.draggedCardKey then
            currentIndex = index
            break
        end
    end

    if currentIndex and currentIndex ~= targetIndex then
        AW.UI:ReorderCard(self.draggedCardKey, targetIndex)
        self:RefreshCardList()
    end
end

function Options:Open()
    self:Initialize()

    if Settings and Settings.OpenToCategory and self.category then
        local categoryID = self.category.GetID and self.category:GetID()
            or self.category.ID
            or AW.displayName
        Settings.OpenToCategory(categoryID)
    elseif InterfaceOptionsFrame_OpenToCategory and self.panel then
        InterfaceOptionsFrame_OpenToCategory(self.panel)
    end
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

    local pageScroll = CreateFrame(
        "ScrollFrame",
        "AzerothWrappedSettingsScrollFrame",
        panel,
        "UIPanelScrollFrameTemplate"
    )
    pageScroll:SetPoint("TOPLEFT", 0, -4)
    pageScroll:SetPoint("BOTTOMRIGHT", -28, 4)
    pageScroll:EnableMouseWheel(true)
    pageScroll:SetScript("OnMouseWheel", function(selfScroll, delta)
        local maximum = math.max(0, selfScroll:GetVerticalScrollRange())
        local nextOffset = selfScroll:GetVerticalScroll() - (delta * 48)
        selfScroll:SetVerticalScroll(math.max(0, math.min(maximum, nextOffset)))
    end)

    local content = CreateFrame("Frame", nil, pageScroll)
    content:SetSize(620, 660)
    pageScroll:SetScrollChild(content)
    self.pageScroll = pageScroll

    createLabel(content, L.OPTIONS_TITLE, "GameFontNormalLarge", 24, -24)

    createLabel(content, L.OPTIONS_LANGUAGE, "GameFontNormal", 24, -64)
    local languageDescription = createLabel(content, L.OPTIONS_LANGUAGE_DESC, "GameFontHighlightSmall", 24, -84)
    languageDescription:SetWidth(540)

    local languageDropdown = CreateFrame("DropdownButton", nil, content, "WowStyle1DropdownTemplate")
    languageDropdown:SetPoint("TOPLEFT", 24, -106)
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

    createLabel(content, L.OPTIONS_DEFAULT_PERIOD, "GameFontNormal", 24, -158)
    local periodDescription = createLabel(content, L.OPTIONS_DEFAULT_PERIOD_DESC, "GameFontHighlightSmall", 24, -178)
    periodDescription:SetWidth(540)

    local periodDropdown = CreateFrame("DropdownButton", nil, content, "WowStyle1DropdownTemplate")
    periodDropdown:SetPoint("TOPLEFT", 24, -200)
    setupDropdown(periodDropdown, AW.Periods.order, function()
        local settings = getSettings()
        return settings and settings.defaultPeriod or "WEEK"
    end, function(periodKey)
        return AW.Periods:GetResetLabel(periodKey)
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

    createLabel(content, L.OPTIONS_CHARACTER_FILTER, "GameFontNormal", 24, -252)
    local characterDescription = createLabel(
        content,
        L.OPTIONS_CHARACTER_FILTER_DESC,
        "GameFontHighlightSmall",
        24,
        -272
    )
    characterDescription:SetWidth(540)

    local characterDropdown = CreateFrame("DropdownButton", nil, content, "WowStyle1DropdownTemplate")
    characterDropdown:SetPoint("TOPLEFT", 24, -294)
    AW.UI:SetupCharacterDropdown(characterDropdown, 240)
    self.characterDropdown = characterDropdown

    createLabel(content, L.OPTIONS_CARDS, "GameFontNormal", 24, -346)
    local cardDescription = createLabel(content, L.OPTIONS_CARDS_DESC, "GameFontHighlightSmall", 24, -366)
    cardDescription:SetWidth(600)

    local cardListContainer = CreateFrame("Frame", nil, content, "InsetFrameTemplate")
    cardListContainer:SetPoint("TOPLEFT", 24, -394)
    cardListContainer:SetSize(540, 156)

    local cardList = CreateFrame(
        "ScrollFrame",
        "AzerothWrappedCardOrderScrollFrame",
        cardListContainer,
        "UIPanelScrollFrameTemplate"
    )
    cardList:SetPoint("TOPLEFT", 5, -5)
    cardList:SetPoint("BOTTOMRIGHT", -27, 5)
    cardList:EnableMouseWheel(true)
    cardList:SetScript("OnMouseWheel", function(selfList, delta)
        local maximum = math.max(0, selfList:GetVerticalScrollRange())
        local nextOffset = selfList:GetVerticalScroll() - (delta * CARD_ROW_HEIGHT)
        selfList:SetVerticalScroll(math.max(0, math.min(maximum, nextOffset)))
    end)

    local cardListContent = CreateFrame("Frame", nil, cardList)
    cardListContent:SetSize(500, 1)
    cardList:SetScrollChild(cardListContent)
    self.cardList = cardList
    self.cardListContent = cardListContent

    self.cardRows = {}
    for index = 1, #AW.UI.defaultCardOrder do
        local row = CreateFrame("Button", nil, cardListContent)
        local currentRow = row
        row:RegisterForDrag("LeftButton")

        row.highlight = row:CreateTexture(nil, "BACKGROUND")
        row.highlight:SetAllPoints()
        row.highlight:SetAtlas("Options_List_Hover")
        row.highlight:Hide()

        row.handle = CreateFrame("Frame", nil, row)
        row.handle:SetPoint("LEFT", 5, 0)
        row.handle:SetSize(28, 22)
        row.handle:SetAlpha(0.8)

        row.handle.icon = row.handle:CreateTexture(nil, "ARTWORK")
        row.handle.icon:SetTexture("Interface\\PaperDollInfoFrame\\statsortarrows")
        row.handle.icon:SetPoint("CENTER")
        row.handle.icon:SetSize(14, 14)

        row.label = row:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
        row.label:SetPoint("LEFT", row.handle, "RIGHT", 10, 0)
        row.label:SetPoint("RIGHT", -40, 0)
        row.label:SetJustifyH("LEFT")

        row.enabledCheck = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
        row.enabledCheck:SetPoint("RIGHT", -5, 0)
        row.enabledCheck:SetSize(24, 24)

        self.cardRows[index] = row
        currentRow:SetScript("OnEnter", function(selfRow)
            if selfRow.cardKey ~= Options.draggedCardKey then
                selfRow.highlight:Show()
            end
        end)
        currentRow:SetScript("OnLeave", function(selfRow)
            if selfRow.cardKey ~= Options.draggedCardKey then
                selfRow.highlight:Hide()
            end
        end)
        currentRow:SetScript("OnDragStart", function(selfRow)
            Options:StartCardDrag(selfRow.cardKey)
        end)
        currentRow:SetScript("OnDragStop", function()
            Options:StopCardDrag()
        end)
        currentRow.enabledCheck:SetScript("OnClick", function(selfCheck)
            if currentRow.cardKey then
                AW.UI:SetCardEnabled(currentRow.cardKey, selfCheck:GetChecked())
                Options:RefreshCardList()
            end
        end)
    end

    createLabel(content, L.OPTIONS_RESET_TITLE, "GameFontNormal", 24, -570)
    local resetDescription = createLabel(content, L.OPTIONS_RESET_DESC, "GameFontHighlightSmall", 24, -590)
    resetDescription:SetWidth(540)

    local resetPeriodDropdown = CreateFrame("DropdownButton", nil, content, "WowStyle1DropdownTemplate")
    resetPeriodDropdown:SetPoint("TOPLEFT", 24, -614)
    setupDropdown(resetPeriodDropdown, AW.Periods.order, function()
        return Options.resetPeriodKey
    end, function(periodKey)
        return AW.Periods:GetLabel(periodKey)
    end, function(periodKey)
        if AW.Periods:IsValid(periodKey) then
            Options.resetPeriodKey = periodKey
        end
    end)
    self.resetPeriodDropdown = resetPeriodDropdown

    local resetButton = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
    resetButton:SetPoint("LEFT", resetPeriodDropdown, "RIGHT", 12, 0)
    resetButton:SetSize(220, 26)
    resetButton:SetText(L.OPTIONS_RESET_BUTTON)
    resetButton:SetScript("OnClick", function()
        AW:ShowResetConfirmation(Options.resetPeriodKey)
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
    panel:SetScript("OnHide", function()
        Options:StopCardDrag()
    end)

    local category = Settings.RegisterCanvasLayoutCategory(panel, AW.displayName)
    Settings.RegisterAddOnCategory(category)

    self.panel = panel
    self.category = category
    self.initialized = true
end
