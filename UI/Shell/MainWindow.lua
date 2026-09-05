-- Main window composition, navigation, and presentation refresh.
local _, AW = ...

local UI = AW.UI
local L = AW.L
local Theme = AW.Theme
local Util = AW.Util

local function setText(fontString, value)
    Theme:SetText(fontString, value)
end

function UI:ApplyDefaultPeriod()
    local db = AW.Database and AW.Database.db
    local settings = db and db.settings
    local defaultPeriod = settings and settings.defaultPeriod or "WEEK"
    self.periodKey = AW.Periods:IsValid(defaultPeriod) and defaultPeriod or "WEEK"
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

    for index, definition in ipairs(self.cardDefinitionList) do
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
    self.frame.subtitle:SetText(string.format("%s  â€¢  %s", periodLabel, L.TAGLINE))
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


