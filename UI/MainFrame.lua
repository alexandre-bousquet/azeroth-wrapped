local ADDON_NAME, AW = ...

AW.UI = {
    periodKey = "WEEK",
    previewMode = false,
    detailKey = nil,
    npcSearchText = "",
    companionSearchText = "",
    characterSearchText = "",
    activityFilter = "all",
    characterFilter = nil,
    cards = {},
    periodButtons = {},
}

local UI = AW.UI
local L = AW.L
local Theme = AW.Theme
local Util = AW.Util
local MINIMAP_LAUNCHER_NAME = "AzerothWrapped"
local MINIMAP_ICON = "Interface\\AddOns\\" .. ADDON_NAME .. "\\Media\\AzerothWrappedIcon.png"

function UI:ApplyDefaultPeriod()
    local db = AW.Database and AW.Database.db
    local settings = db and db.settings
    local defaultPeriod = settings and settings.defaultPeriod or "WEEK"
    self.periodKey = AW.Periods:IsValid(defaultPeriod) and defaultPeriod or "WEEK"
end

local CARD_DEFINITIONS = {
    { key = "time", titleKey = "CARD_TIME", icon = "Interface/Icons/INV_Misc_PocketWatch_01", accent = Theme.cyan },
    { key = "world", titleKey = "CARD_WORLD", icon = "Interface/Icons/INV_Misc_Map_01", accent = Theme.gold },
    { key = "fate", titleKey = "CARD_FATE", icon = "Interface/Icons/Ability_Rogue_FeignDeath", accent = Theme.danger },
    { key = "companion", titleKey = "CARD_COMPANION", icon = "Interface/Icons/Achievement_GuildPerk_EverybodysFriend", accent = Theme.purple },
    { key = "identity", titleKey = "CARD_IDENTITY", icon = "Interface/Icons/Achievement_Character_Human_Male", accent = Theme.cyan },
    { key = "npcs", titleKey = "CARD_ENCOUNTERS", icon = "Interface/Icons/INV_Misc_Book_09", accent = Theme.gold },
    { key = "gold", titleKey = "CARD_GOLD", icon = "Interface/Icons/INV_Misc_Coin_01", accent = Theme.gold },
    { key = "activities", titleKey = "CARD_ACTIVITIES", icon = "Interface/Icons/Achievement_Boss_LichKing", accent = Theme.danger },
}

local CARD_DEFINITIONS_BY_KEY = {}
local DEFAULT_CARD_ORDER = {}
for _, definition in ipairs(CARD_DEFINITIONS) do
    CARD_DEFINITIONS_BY_KEY[definition.key] = definition
    DEFAULT_CARD_ORDER[#DEFAULT_CARD_ORDER + 1] = definition.key
end

UI.cardDefinitions = CARD_DEFINITIONS_BY_KEY
UI.defaultCardOrder = DEFAULT_CARD_ORDER

local function setText(fontString, value)
    Theme:SetText(fontString, value)
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
                card:SetPoint("TOPLEFT", 28 + (column * 438), -158 - (row * 144))
                card:Show()
                visibleIndex = visibleIndex + 1
            end
        end
    end
end

local function getCharacterFilterSettings()
    local database = AW.Database and AW.Database.db
    return database and database.settings or nil
end

function UI:LoadCharacterFilter()
    local settings = getCharacterFilterSettings()
    if self.characterFilterSettings == settings then
        return
    end

    self.characterFilterSettings = settings
    self.characterFilter = settings and settings.characterFilter or nil
end

function UI:SetCharacterFilter(characterFilter)
    local settings = getCharacterFilterSettings()
    self.characterFilterSettings = settings
    self.characterFilter = characterFilter
    if settings then
        settings.characterFilter = characterFilter
    end
end

function UI:GetCharacterChoices()
    local choices = {}
    for characterKey, character in pairs((AW.Database.db and AW.Database.db.characters) or {}) do
        choices[#choices + 1] = {
            key = characterKey,
            name = character.name or L.UNKNOWN_PLAYER,
            realm = character.realm or "",
            classFile = character.classFile,
        }
    end

    table.sort(choices, function(left, right)
        local leftName = string.lower(string.format("%s-%s", left.name, left.realm))
        local rightName = string.lower(string.format("%s-%s", right.name, right.realm))
        return leftName < rightName
    end)
    return choices
end

function UI:NormalizeCharacterFilter()
    self:LoadCharacterFilter()
    if type(self.characterFilter) ~= "table" then
        self:SetCharacterFilter(nil)
        return
    end

    local choices = self:GetCharacterChoices()
    local selected = 0
    local normalized = {}
    for _, choice in ipairs(choices) do
        if self.characterFilter[choice.key] then
            selected = selected + 1
            normalized[choice.key] = true
        end
    end

    if selected == 0 or selected == #choices then
        self:SetCharacterFilter(nil)
    else
        self:SetCharacterFilter(normalized)
    end
end

function UI:IsCharacterSelected(characterKey)
    return type(self.characterFilter) ~= "table" or self.characterFilter[characterKey] == true
end

function UI:GetCharacterFilterLabel(ignorePreview)
    self:LoadCharacterFilter()
    if self.previewMode and not ignorePreview then
        return L.CHARACTER_FILTER_PREVIEW
    end

    local choices = self:GetCharacterChoices()
    if type(self.characterFilter) ~= "table" then
        return L.CHARACTER_FILTER_ALL
    end

    local count = 0
    local selectedName
    for _, choice in ipairs(choices) do
        if self.characterFilter[choice.key] then
            count = count + 1
            selectedName = choice.name
        end
    end

    if count == 1 then
        return selectedName or L.UNKNOWN_PLAYER
    end
    return string.format(L.CHARACTER_FILTER_COUNT, count)
end

function UI:ShouldShowActivityCharacters()
    if type(self.characterFilter) == "table" then
        local selectedCount = 0
        for _, selected in pairs(self.characterFilter) do
            if selected then
                selectedCount = selectedCount + 1
            end
        end
        return selectedCount > 1
    end

    return #self:GetCharacterChoices() > 1
end

function UI:ToggleCharacterFilter(characterKey)
    self:LoadCharacterFilter()
    local choices = self:GetCharacterChoices()
    if type(self.characterFilter) ~= "table" then
        local selectedCharacters = {}
        for _, choice in ipairs(choices) do
            selectedCharacters[choice.key] = true
        end
        self:SetCharacterFilter(selectedCharacters)
    end

    if self.characterFilter[characterKey] then
        local selected = 0
        for _, choice in ipairs(choices) do
            if self.characterFilter[choice.key] then
                selected = selected + 1
            end
        end
        if selected <= 1 then
            return
        end
        self.characterFilter[characterKey] = nil
    else
        self.characterFilter[characterKey] = true
    end

    self:NormalizeCharacterFilter()
    self.previewMode = false
    self:Refresh(true)
    if AW.Options and AW.Options.Refresh then
        AW.Options:Refresh()
    end
end

function UI:SetupCharacterDropdown(dropdown, width)
    dropdown:SetWidth(width or 240)
    dropdown:SetDefaultText(self:GetCharacterFilterLabel(true))
    dropdown:SetSelectionText(function()
        return UI:GetCharacterFilterLabel(true)
    end)
    dropdown:SetupMenu(function(_, rootDescription)
        rootDescription:CreateButton(L.CHARACTER_FILTER_ALL, function()
            UI:SetCharacterFilter(nil)
            UI.previewMode = false
            UI:Refresh(true)
            if AW.Options and AW.Options.Refresh then
                AW.Options:Refresh()
            end
        end)
        rootDescription:CreateDivider()

        for _, choice in ipairs(UI:GetCharacterChoices()) do
            local characterKey = choice.key
            local label = choice.realm ~= "" and string.format(L.CHARACTER_FILTER_NAME_REALM, choice.name, choice.realm)
                or choice.name
            rootDescription:CreateCheckbox(label, function()
                return UI:IsCharacterSelected(characterKey)
            end, function()
                UI:ToggleCharacterFilter(characterKey)
            end)
        end
    end)
end

local function getMinimapSettings()
    local database = AW.Database and AW.Database.db
    if not database or type(database.settings) ~= "table" then
        return nil
    end

    if type(database.settings.minimapButton) ~= "table" then
        database.settings.minimapButton = {
            hide = false,
            minimapPos = 225,
        }
    end

    return database.settings.minimapButton
end

function UI:CreateMinimapButton()
    if self.MinimapButton then
        return self.MinimapButton
    end

    local dataBroker = LibStub and LibStub("LibDataBroker-1.1", true)
    local iconLibrary = LibStub and LibStub("LibDBIcon-1.0", true)
    local settings = getMinimapSettings()
    if not dataBroker or not iconLibrary or not settings then
        return nil
    end

    local launcher = dataBroker:NewDataObject(MINIMAP_LAUNCHER_NAME, {
        type = "launcher",
        label = AW.displayName,
        icon = MINIMAP_ICON,
        iconCoords = { 0, 1, 0, 1 },
        OnClick = function(_, button)
            if button == "LeftButton" then
                UI:Toggle()
            elseif button == "RightButton" and AW.Options and AW.Options.Open then
                AW.Options:Open()
            end
        end,
        OnTooltipShow = function(tooltip)
            tooltip:AddLine(AW.displayName)
            tooltip:AddLine(L.MINIMAP_TOOLTIP, 1, 1, 1, true)
            tooltip:AddLine(L.MINIMAP_TOOLTIP_RIGHT, 1, 1, 1, true)
        end,
    })

    iconLibrary:Register(MINIMAP_LAUNCHER_NAME, launcher, settings)
    self.MinimapButtonLibrary = iconLibrary
    self.MinimapButton = iconLibrary:GetMinimapButton(MINIMAP_LAUNCHER_NAME)
    return self.MinimapButton
end

function UI:RefreshMinimapButton()
    local settings = getMinimapSettings()
    if self.MinimapButtonLibrary and settings then
        self.MinimapButtonLibrary:Refresh(MINIMAP_LAUNCHER_NAME, settings)
        self.MinimapButton = self.MinimapButtonLibrary:GetMinimapButton(MINIMAP_LAUNCHER_NAME)
    end
end

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

function UI:CreateFrame()
    if self.frame then
        return self.frame
    end

    local frame = CreateFrame("Frame", "AzerothWrappedFrame", UIParent, "BackdropTemplate")
    frame:SetSize(920, 790)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("DIALOG")
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:SetScript("OnShow", function()
        UI:Refresh()
    end)
    frame:SetScript("OnHide", function()
        if UI.CloseDetails then
            UI:CloseDetails()
        end
    end)
    if UISpecialFrames then
        UISpecialFrames[#UISpecialFrames + 1] = frame:GetName()
    end
    Theme:ApplyBackdrop(frame, Theme.background, Theme.border)

    frame.glow = frame:CreateTexture(nil, "BACKGROUND")
    frame.glow:SetTexture("Interface/Buttons/WHITE8x8")
    frame.glow:SetGradient("VERTICAL", CreateColor(0.05, 0.18, 0.22, 0.9), CreateColor(0.035, 0.047, 0.078, 0))
    frame.glow:SetPoint("TOPLEFT", 1, -1)
    frame.glow:SetPoint("TOPRIGHT", -1, -1)
    frame.glow:SetHeight(116)

    frame.title = Theme:CreateText(frame, "GameFontNormalHuge", 27, Theme.text)
    frame.title:SetPoint("TOPLEFT", 28, -25)
    frame.title:SetText(L.TITLE)

    frame.subtitle = Theme:CreateText(frame, "GameFontHighlightSmall", 12, Theme.muted)
    frame.subtitle:SetPoint("TOPLEFT", frame.title, "BOTTOMLEFT", 1, -5)
    frame.subtitle:SetText(L.TAGLINE)

    frame.close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    frame.close:SetPoint("TOPRIGHT", -8, -8)

    local previous
    for _, periodKey in ipairs(AW.Periods.order) do
        local button = Theme:CreateButton(frame, AW.Periods:GetLabel(periodKey), 128)
        if previous then
            button:SetPoint("LEFT", previous, "RIGHT", 8, 0)
        else
            button:SetPoint("TOPLEFT", 28, -102)
        end
        button:SetScript("OnClick", function()
            UI.previewMode = false
            UI.periodKey = periodKey
            UI:Refresh(true)
        end)
        self.periodButtons[periodKey] = button
        previous = button
    end

    for index, definition in ipairs(CARD_DEFINITIONS) do
        self:CreateCard(frame, definition, index)
    end

    self:CreateDetailPanel(frame)

    frame.footer = Theme:CreateText(frame, "GameFontHighlight", 13, Theme.muted)
    frame.footer:SetPoint("BOTTOMLEFT", 28, 26)
    frame.footer:SetPoint("RIGHT", -270, 0)
    frame.footer:SetJustifyH("LEFT")

    if AW.isDev then
        frame.preview = Theme:CreateButton(frame, L.PREVIEW, 92)
        frame.preview:SetPoint("BOTTOMRIGHT", -136, 18)
        frame.preview:SetScript("OnClick", function()
            UI.previewMode = not UI.previewMode
            UI:Refresh(true)
        end)
    end

    frame.capture = Theme:CreateButton(frame, L.CAPTURE, 100)
    frame.capture:SetPoint("BOTTOMRIGHT", -28, 18)
    frame.capture:SetScript("OnClick", function()
        UI:Capture()
    end)

    frame:Hide()
    self.frame = frame
    self:ApplyCardLayout()
    return frame
end

function UI:UpdateButtons()
    for periodKey, button in pairs(self.periodButtons) do
        button.label:SetText(AW.Periods:GetLabel(periodKey))
        Theme:SetButtonSelected(button, not self.previewMode and periodKey == self.periodKey)
    end
end

function UI:UpdateCards(summary)
    local empty = L.EMPTY_VALUE

    setText(self.cards.time.primary, summary.hasData and string.format(L.ONLINE_TIME, Util:FormatDuration(summary.onlineSeconds)) or empty)
    setText(self.cards.time.secondary, string.format(L.SESSION_COUNT, summary.sessionCount or 0))
    setText(self.cards.time.tertiary, string.format(L.LONGEST_SESSION, Util:FormatDuration(summary.longestSession)))

    local topZone = summary.topZone
    setText(self.cards.world.primary, topZone and topZone.name or empty)
    setText(self.cards.world.secondary, string.format(L.ZONES_VISITED, summary.zoneCount or 0))
    setText(self.cards.world.tertiary, topZone and string.format(L.TIME_SPENT, Util:FormatDuration(topZone.seconds)) or "")

    setText(
        self.cards.fate.primary,
        summary.deaths.total > 0
            and Util:FormatCount(summary.deaths.total, L.DEATH_COUNT_ONE, L.DEATH_COUNT)
            or L.NO_DEATHS
    )
    setText(self.cards.fate.secondary, summary.deadliestLocation and string.format(L.DEADLIEST, summary.deadliestLocation.name) or "")
    setText(self.cards.fate.tertiary, string.format(L.DAYS_PLAYED, summary.daysPlayed or 0))

    local companion = summary.topGroupmate
    local companionName = companion and companion.name or empty
    local companionRealm = companion and companion.realm or ""
    if companion and AW.Database.db.settings.anonymousShare then
        companionName = L.PRIVATE_PLAYER
        companionRealm = ""
    end
    setText(self.cards.companion.primary, companionName)
    setText(self.cards.companion.secondary, companionRealm)
    setText(self.cards.companion.tertiary, companion and string.format(L.TOGETHER_TIME, Util:FormatMinutes(companion.seconds)) or "")

    local character = summary.topCharacter
    setText(self.cards.identity.primary, character and character.name or empty)
    setText(self.cards.identity.secondary, character and string.format(L.TOP_CHARACTER, Util:FormatDuration(character.seconds)) or "")
    setText(self.cards.identity.tertiary, string.format(L.MAIN_ACTIVITY, L["ACTIVITY_" .. (summary.topActivityKey or "unknown")] or L.ACTIVITY_unknown))

    local npc = summary.topNPC
    setText(self.cards.npcs.primary, npc and npc.name or empty)
    setText(self.cards.npcs.secondary, string.format(L.NPC_COUNT, summary.npcCount or 0))
    setText(self.cards.npcs.tertiary, npc and string.format(L.NPC_INTERACTIONS, npc.interactions or 0) or "")

    if summary.hasMoneyData then
        local goldPrimary = summary.money.changes > 0
            and Util:FormatGold(summary.money.net, true)
            or L.NO_GOLD_CHANGE
        setText(self.cards.gold.primary, goldPrimary)
        setText(self.cards.gold.secondary, string.format(
            L.GOLD_EARNED_SPENT,
            Util:FormatGold(summary.money.earned),
            Util:FormatGold(summary.money.spent)
        ))
        setText(self.cards.gold.tertiary, string.format(L.GOLD_BALANCE, Util:FormatGold(summary.knownBalance)))
    else
        setText(self.cards.gold.primary, empty)
        setText(self.cards.gold.secondary, "")
        setText(self.cards.gold.tertiary, "")
    end

    if summary.hasCompletedActivityData then
        local dungeonCount = tonumber(summary.completedActivities.dungeon) or 0
        local raidBossCount = tonumber(summary.completedActivities.raid) or 0
        local outdoorCount = tonumber(summary.completedActivities.outdoor) or 0
        local dungeonText = string.format(
            dungeonCount > 1 and L.ACTIVITY_DUNGEON_MANY or L.ACTIVITY_DUNGEON_ONE,
            dungeonCount
        )
        local raidBossText = string.format(
            raidBossCount > 1 and L.ACTIVITY_RAID_BOSS_MANY or L.ACTIVITY_RAID_BOSS_ONE,
            raidBossCount
        )
        local outdoorText = string.format(
            outdoorCount > 1 and L.ACTIVITY_OUTDOOR_MANY or L.ACTIVITY_OUTDOOR_ONE,
            outdoorCount
        )
        setText(self.cards.activities.primary, string.format(L.ACTIVITY_COUNT, summary.completedActivities.total))
        setText(self.cards.activities.secondary, string.format(
            L.ACTIVITY_BREAKDOWN,
            dungeonText,
            raidBossText,
            outdoorText
        ))
        setText(
            self.cards.activities.tertiary,
            summary.latestCompletedActivity and string.format(
                L.LAST_COMPLETED_ACTIVITY,
                summary.latestCompletedActivity.name or L.UNKNOWN_ACTIVITY
            ) or ""
        )
    else
        setText(self.cards.activities.primary, L.NO_COMPLETED_ACTIVITIES)
        setText(self.cards.activities.secondary, "")
        setText(self.cards.activities.tertiary, "")
    end

    if summary.hasData and character and topZone then
        local identity = L["ACTIVITY_" .. (summary.topActivityKey or "unknown")] or L.ACTIVITY_unknown
        self.frame.footer:SetText(string.format(L.FOOTER_STORY, character.name, topZone.name, identity))
    else
        self.frame.footer:SetText(L.FOOTER_EMPTY)
    end
end

function UI:Refresh(resetDetailScroll)
    if not self.frame then
        return
    end

    if not AW.isDev then
        self.previewMode = false
    end

    self:NormalizeCharacterFilter()
    local summary = self.previewMode and AW.Summary:BuildPreview()
        or AW.Summary:Build(self.periodKey, self.characterFilter)
    self.currentSummary = summary
    self:UpdateButtons()
    self:UpdateCards(summary)
    self:ApplyCardLayout()

    if self.detailKey then
        self:RefreshDetails(summary, resetDetailScroll)
    end

    local periodLabel = self.previewMode and L.PREVIEW or AW.Periods:GetLabel(self.periodKey)
    self.frame.subtitle:SetText(string.format("%s  •  %s", periodLabel, L.TAGLINE))
end

function UI:Toggle()
    local frame = self:CreateFrame()
    if frame:IsShown() then
        frame:Hide()
    else
        frame:Show()
    end
end

function UI:Show(periodKey, preview)
    local frame = self:CreateFrame()
    if periodKey then
        self.periodKey = periodKey
    end
    self.previewMode = AW.isDev and preview == true
    frame:Show()
    self:Refresh()
end

function UI:Capture()
    if not self.frame then
        return
    end

    self.frame.close:Hide()
    if self.frame.preview then
        self.frame.preview:Hide()
    end
    self.frame.capture:Hide()
    local detailBackWasShown = self.detailPanel
        and self.detailPanel:IsShown()
        and self.detailPanel.back:IsShown()
    if detailBackWasShown then
        self.detailPanel.back:Hide()
    end

    C_Timer.After(0.25, function()
        Screenshot()
        C_Timer.After(0.75, function()
            if UI.frame then
                UI.frame.close:Show()
                if UI.frame.preview then
                    UI.frame.preview:Show()
                end
                UI.frame.capture:Show()
                if detailBackWasShown and UI.detailPanel then
                    UI.detailPanel.back:Show()
                end
                AW:Print(L.SCREENSHOT_TAKEN)
            end
        end)
    end)
end
