-- Main window composition, navigation, and presentation refresh.
local _, AW = ...

local UI = AW.UI
local L = AW.L
local Theme = AW.Theme


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

    frame.cardScroll = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
    frame.cardScroll:SetPoint("TOPLEFT", 28, -150)
    frame.cardScroll:SetPoint("BOTTOMRIGHT", -28, 70)
    frame.cardScroll:EnableMouseWheel(true)
    frame.cardScroll:SetScript("OnMouseWheel", function(scroll, delta)
        local target = (scroll:GetVerticalScroll() or 0) - (delta * 60)
        scroll:SetVerticalScroll(math.max(0, math.min(target, scroll:GetVerticalScrollRange() or 0)))
    end)

    frame.cardContent = CreateFrame("Frame", nil, frame.cardScroll)
    frame.cardContent:SetSize(854, 1)
    frame.cardScroll:SetScrollChild(frame.cardContent)

    for index, definition in ipairs(self.cardDefinitionList) do
        self:CreateCard(frame.cardContent, definition, index)
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
    for _, definition in ipairs(self.cardDefinitionList) do
        local card = self.cards[definition.key]
        if card and type(definition.render) == "function" then
            definition.render(card, summary)
        end
    end

    local character = summary.topCharacter
    local topZone = summary.topZone
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
