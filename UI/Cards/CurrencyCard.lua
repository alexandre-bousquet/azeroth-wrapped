-- Currency overview card.
local _, AW = ...

local UI = AW.UI
local L = AW.L
local Theme = AW.Theme
local Util = AW.Util

UI:RegisterCard({
    key = "currencies",
    titleKey = "CARD_CURRENCIES",
    icon = "Interface/Icons/INV_Misc_Coin_17",
    accent = Theme.purple,
    render = function(card, summary)
        local currency = summary.topSpentCurrency
        if not summary.hasCurrencyData or not currency then
            Theme:SetText(card.primary, L.EMPTY_VALUE)
            Theme:SetText(card.secondary, "")
            Theme:SetText(card.tertiary, "")
            return
        end

        Theme:SetText(card.primary, currency.name or L.UNKNOWN_CURRENCY)
        Theme:SetText(card.secondary, string.format(L.CURRENCY_CARD_SPENT, Util:FormatNumber(currency.spent)))
        Theme:SetText(card.tertiary, Util:FormatCount(
            summary.currencies.spendingEvents,
            L.CURRENCY_CARD_EVENT_ONE,
            L.CURRENCY_CARD_EVENT_MANY
        ))
    end,
})
