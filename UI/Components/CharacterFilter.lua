-- Character selection state and dropdown behavior.
local _, AW = ...

local UI = AW.UI
local L = AW.L

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

