-- Character detail rows.
local _, AW = ...

local UI = AW.UI
local L = AW.L
local Util = AW.Util
local Helpers = UI.DetailHelpers

local function buildCharacterRows(summary)
    local rows = {}
    local searchText = UI.characterSearchText or ""

    for _, entry in ipairs(Helpers.sortedEntries(summary.characters, "seconds")) do
        local character = entry.value
        local storedCharacter = AW.Database.db.characters[entry.key] or {}
        local name = character.name or storedCharacter.name or L.UNKNOWN_PLAYER
        local className = character.className or storedCharacter.className or character.classFile
        local realm = character.realm or storedCharacter.realm
        local searchableText = Helpers.normalizeSearchText(table.concat({
            name or "",
            realm or "",
            className or "",
            character.classFile or storedCharacter.classFile or "",
        }, " "))

        if searchText == "" or string.find(searchableText, searchText, 1, true) then
            Helpers.appendRow(
                rows,
                name,
                Helpers.joinDetails(
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

UI.DetailBuilders.identity = buildCharacterRows

