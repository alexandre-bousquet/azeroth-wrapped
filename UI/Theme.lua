local _, AW = ...

AW.Theme = {
    cyrillicFont = "Fonts\\FRIZQT___CYR.TTF",
    background = { 0.035, 0.047, 0.078, 0.98 },
    surface = { 0.065, 0.082, 0.125, 0.98 },
    surfaceHover = { 0.085, 0.105, 0.155, 1 },
    border = { 0.16, 0.21, 0.31, 1 },
    text = { 0.94, 0.96, 1, 1 },
    muted = { 0.60, 0.66, 0.76, 1 },
    cyan = { 0.26, 0.85, 0.82, 1 },
    gold = { 1.00, 0.78, 0.34, 1 },
    purple = { 0.62, 0.45, 0.96, 1 },
    danger = { 0.95, 0.34, 0.46, 1 },
}

local Theme = AW.Theme

function Theme:ApplyFont(fontInstance, size)
    local font, currentSize, flags = fontInstance:GetFont()
    fontInstance.awDefaultFont = font
    fontInstance.awFontSize = size or currentSize or 12
    fontInstance.awFontFlags = flags
    fontInstance:SetFont(font, fontInstance.awFontSize, flags)
end

function Theme:ContainsCyrillic(value)
    return type(value) == "string" and string.find(value, "[\208\209][\128-\191]") ~= nil
end

function Theme:ApplyTextFont(fontInstance, value)
    if not fontInstance.awDefaultFont then
        self:ApplyFont(fontInstance)
    end

    local font = self:ContainsCyrillic(value) and self.cyrillicFont or fontInstance.awDefaultFont
    fontInstance:SetFont(font, fontInstance.awFontSize, fontInstance.awFontFlags)
end

function Theme:SetText(fontInstance, value)
    value = value or ""
    self:ApplyTextFont(fontInstance, value)
    fontInstance:SetText(value)
end

function Theme:ApplyBackdrop(frame, background, border)
    frame:SetBackdrop({
        bgFile = "Interface/Buttons/WHITE8x8",
        edgeFile = "Interface/Buttons/WHITE8x8",
        edgeSize = 1,
    })
    frame:SetBackdropColor(unpack(background or self.surface))
    frame:SetBackdropBorderColor(unpack(border or self.border))
end

function Theme:CreateText(parent, template, size, color)
    local text = parent:CreateFontString(nil, "OVERLAY", template or "GameFontHighlight")
    self:ApplyFont(text, size)
    text:SetTextColor(unpack(color or self.text))
    return text
end

function Theme:CreateButton(parent, label, width)
    local button = CreateFrame("Button", nil, parent, "BackdropTemplate")
    button:SetSize(width or 112, 30)
    self:ApplyBackdrop(button, self.surface, self.border)

    button.label = self:CreateText(button, "GameFontHighlightSmall", 12, self.text)
    button.label:SetPoint("CENTER")
    button.label:SetText(label)

    button:SetScript("OnEnter", function(selfButton)
        selfButton:SetBackdropColor(unpack(Theme.surfaceHover))
        selfButton:SetBackdropBorderColor(unpack(Theme.cyan))
    end)
    button:SetScript("OnLeave", function(selfButton)
        if not selfButton.selected then
            selfButton:SetBackdropColor(unpack(Theme.surface))
            selfButton:SetBackdropBorderColor(unpack(Theme.border))
        end
    end)

    return button
end

function Theme:SetButtonSelected(button, selected)
    button.selected = selected
    if selected then
        button:SetBackdropColor(0.07, 0.20, 0.23, 1)
        button:SetBackdropBorderColor(unpack(self.cyan))
        button.label:SetTextColor(unpack(self.cyan))
    else
        button:SetBackdropColor(unpack(self.surface))
        button:SetBackdropBorderColor(unpack(self.border))
        button.label:SetTextColor(unpack(self.text))
    end
end
