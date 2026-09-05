-- Summary-card definitions, preferences, layout, and widget creation.
local _, AW = ...

local UI = AW.UI
local L = AW.L
local Theme = AW.Theme

local CARD_DEFINITIONS = {}
local CARD_DEFINITIONS_BY_KEY = {}
local DEFAULT_CARD_ORDER = {}

UI.cardDefinitions = CARD_DEFINITIONS_BY_KEY
UI.defaultCardOrder = DEFAULT_CARD_ORDER

function UI:RegisterCard(definition)
    if type(definition) ~= "table" or type(definition.key) ~= "string"
        or definition.key == "" or CARD_DEFINITIONS_BY_KEY[definition.key]
    then
        return false
    end

    CARD_DEFINITIONS[#CARD_DEFINITIONS + 1] = definition
    CARD_DEFINITIONS_BY_KEY[definition.key] = definition
    DEFAULT_CARD_ORDER[#DEFAULT_CARD_ORDER + 1] = definition.key
    return true
end

local function getCardSettings()
    local database = AW.Database and AW.Database.db
    return database and database.settings or nil
end

function UI:NormalizeCardSettings()
    local settings = getCardSettings()
    if not settings then
        return DEFAULT_CARD_ORDER, {}
    end

    local order = {}
    local seen = {}
    if type(settings.cardOrder) == "table" then
        for _, cardKey in ipairs(settings.cardOrder) do
            if CARD_DEFINITIONS_BY_KEY[cardKey] and not seen[cardKey] then
                seen[cardKey] = true
                order[#order + 1] = cardKey
            end
        end
    end
    for _, cardKey in ipairs(DEFAULT_CARD_ORDER) do
        if not seen[cardKey] then
            order[#order + 1] = cardKey
        end
    end

    local hidden = {}
    if type(settings.hiddenCards) == "table" then
        for cardKey, isHidden in pairs(settings.hiddenCards) do
            if isHidden and CARD_DEFINITIONS_BY_KEY[cardKey] then
                hidden[cardKey] = true
            end
        end
    end

    settings.cardOrder = order
    settings.hiddenCards = hidden
    return order, hidden
end

function UI:GetCardOrder()
    return self:NormalizeCardSettings()
end

function UI:IsCardEnabled(cardKey)
    local _, hidden = self:NormalizeCardSettings()
    return CARD_DEFINITIONS_BY_KEY[cardKey] ~= nil and not hidden[cardKey]
end

function UI:SetCardEnabled(cardKey, enabled)
    if not CARD_DEFINITIONS_BY_KEY[cardKey] then
        return
    end

    local settings = getCardSettings()
    if not settings then
        return
    end
    local _, hidden = self:NormalizeCardSettings()
    if enabled then
        hidden[cardKey] = nil
    else
        hidden[cardKey] = true
    end
    settings.hiddenCards = hidden
    self:ApplyCardLayout()
end

function UI:ReorderCard(cardKey, targetIndex)
    local settings = getCardSettings()
    if not settings or not CARD_DEFINITIONS_BY_KEY[cardKey] then
        return
    end

    local order = self:NormalizeCardSettings()
    local reordered = {}
    for _, orderedKey in ipairs(order) do
        if orderedKey ~= cardKey then
            reordered[#reordered + 1] = orderedKey
        end
    end

    targetIndex = math.max(1, math.min(tonumber(targetIndex) or 1, #reordered + 1))
    table.insert(reordered, targetIndex, cardKey)

    settings.cardOrder = reordered
    self:ApplyCardLayout()
end

function UI:ApplyCardLayout()
    if not self.frame then
        return
    end

    local order, hidden = self:NormalizeCardSettings()
    if self.frame.cardScroll then
        self.frame.cardScroll:SetShown(not self.detailKey)
    end
    local visibleIndex = 0
    for _, cardKey in ipairs(order) do
        local card = self.cards[cardKey]
        if card then
            card:ClearAllPoints()
            if self.detailKey or hidden[cardKey] then
                card:Hide()
            else
                local column = visibleIndex % 2
                local row = math.floor(visibleIndex / 2)
                card:SetPoint("TOPLEFT", column * 438, -(row * 144))
                card:Show()
                visibleIndex = visibleIndex + 1
            end
        end
    end

    if self.frame.cardContent then
        local rows = math.ceil(visibleIndex / 2)
        local viewportHeight = self.frame.cardScroll:GetHeight()
        local requiredHeight = math.max(1, rows) * 144 - 12
        local contentHeight = math.max(viewportHeight, requiredHeight)
        self.frame.cardContent:SetHeight(contentHeight)
        if self.frame.cardScroll.ScrollBar then
            self.frame.cardScroll.ScrollBar:SetShown(requiredHeight > viewportHeight)
        end
        if requiredHeight <= viewportHeight then
            self.frame.cardScroll:SetVerticalScroll(0)
        end
    end
end

UI.cardDefinitionList = CARD_DEFINITIONS

function UI:CreateCard(parent, definition, index)
    local title = L[definition.titleKey]
    local card = CreateFrame("Button", nil, parent, "BackdropTemplate")
    card:SetSize(416, 132)
    card:RegisterForClicks("LeftButtonUp")
    card.definition = definition

    Theme:ApplyBackdrop(card)

    card.accent = card:CreateTexture(nil, "ARTWORK")
    card.accent:SetColorTexture(unpack(definition.accent))
    card.accent:SetPoint("TOPLEFT", 0, 0)
    card.accent:SetPoint("BOTTOMLEFT", 0, 0)
    card.accent:SetWidth(4)

    card.icon = card:CreateTexture(nil, "ARTWORK")
    card.icon:SetSize(34, 34)
    card.icon:SetPoint("TOPRIGHT", -16, -14)
    card.icon:SetTexture(definition.icon)
    card.icon:SetDesaturated(true)
    card.icon:SetAlpha(0.35)

    card.title = Theme:CreateText(card, "GameFontNormalSmall", 11, definition.accent)
    card.title:SetPoint("TOPLEFT", 18, -15)
    card.title:SetText(title)

    card.primary = Theme:CreateText(card, "GameFontHighlight", 22, Theme.text)
    card.primary:SetPoint("TOPLEFT", 18, -39)
    card.primary:SetPoint("RIGHT", card.icon, "LEFT", -10, 0)
    card.primary:SetJustifyH("LEFT")
    card.primary:SetWordWrap(false)

    card.secondary = Theme:CreateText(card, "GameFontHighlightSmall", 12, Theme.muted)
    card.secondary:SetPoint("TOPLEFT", 18, -76)
    card.secondary:SetPoint("RIGHT", -18, 0)
    card.secondary:SetJustifyH("LEFT")

    card.tertiary = Theme:CreateText(card, "GameFontHighlightSmall", 11, Theme.muted)
    card.tertiary:SetPoint("TOPLEFT", 18, -99)
    card.tertiary:SetPoint("RIGHT", -18, 0)
    card.tertiary:SetJustifyH("LEFT")

    card:SetScript("OnEnter", function(selfCard)
        selfCard:SetBackdropColor(unpack(Theme.surfaceHover))
        selfCard:SetBackdropBorderColor(unpack(definition.accent))
        if GameTooltip then
            GameTooltip:SetOwner(selfCard, "ANCHOR_CURSOR")
            GameTooltip:SetText(title, definition.accent[1], definition.accent[2], definition.accent[3])
            GameTooltip:AddLine(L.CARD_CLICK_HINT, Theme.muted[1], Theme.muted[2], Theme.muted[3], true)
            GameTooltip:Show()
        end
    end)
    card:SetScript("OnLeave", function(selfCard)
        selfCard:SetBackdropColor(unpack(Theme.surface))
        selfCard:SetBackdropBorderColor(unpack(Theme.border))
        if GameTooltip then
            GameTooltip:Hide()
        end
    end)
    card:SetScript("OnClick", function()
        if GameTooltip then
            GameTooltip:Hide()
        end
        UI:OpenDetails(definition.key)
    end)

    self.cards[definition.key] = card
end
