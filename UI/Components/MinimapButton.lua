-- DataBroker launcher and minimap icon integration.
local ADDON_NAME, AW = ...

local UI = AW.UI
local L = AW.L
local MINIMAP_LAUNCHER_NAME = "AzerothWrapped"
local MINIMAP_ICON = "Interface\\AddOns\\" .. ADDON_NAME .. "\\Media\\AzerothWrappedIcon.png"

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

