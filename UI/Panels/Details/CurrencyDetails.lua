-- Currency expense history and per-currency fallback summary.
local _, AW = ...

local UI = AW.UI
local L = AW.L
local Util = AW.Util
local Helpers = UI.DetailHelpers

local DESTROY_REASON_KEYS = {
    [0] = "CHEAT",
    [1] = "SPELL",
    [2] = "VERSION_UPDATE",
    [3] = "QUEST",
    [4] = "VENDOR",
    [5] = "TRADE",
    [6] = "CAPPED",
    [7] = "GARRISON",
    [8] = "CORPSE",
    [9] = "BONUS_ROLL",
    [10] = "FACTION_CONVERSION",
    [11] = "CRAFTING_ORDER",
    [12] = "SCRIPT",
    [13] = "CONCENTRATION",
    [14] = "ACCOUNT_TRANSFER",
    [15] = "HONOR_LOSS",
    [16] = "CRAFTING_REAGENT",
    [17] = "ACCOUNT_CONVERSION",
}

local function getReasonLabel(destroyReason)
    local key = DESTROY_REASON_KEYS[tonumber(destroyReason)]
    return key and L["CURRENCY_REASON_" .. key] or L.CURRENCY_REASON_UNKNOWN
end

local function buildCurrencyRows(summary)
    local rows = {}
    local currencies = summary.currencies or {}
    local transactions = {}

    for _, transaction in ipairs(currencies.transactions or {}) do
        transactions[#transactions + 1] = transaction
    end
    table.sort(transactions, function(left, right)
        return (tonumber(left.timestamp) or 0) > (tonumber(right.timestamp) or 0)
    end)

    for _, transaction in ipairs(transactions) do
        local reason = getReasonLabel(transaction.destroyReason)
        local target = transaction.contextName or transaction.itemLink or reason
        local storedCurrency = currencies.entries and currencies.entries[tostring(transaction.currencyID)]
        local currencyName = transaction.currencyName
            or (storedCurrency and storedCurrency.name)
            or L.UNKNOWN_CURRENCY
        local timestamp = transaction.timestamp and date(L.CURRENCY_DATE_FORMAT, transaction.timestamp) or nil
        local amount = string.format(L.CURRENCY_TRANSACTION_AMOUNT, Util:FormatNumber(transaction.amount))
        local currencyDetail = string.format("%s (%s)", currencyName, amount)
        local row = Helpers.appendRow(
            rows,
            target,
            Helpers.joinDetails(currencyDetail, transaction.contextName and reason or nil),
            timestamp or ""
        )

        local character = transaction.characterKey
            and summary.characters
            and summary.characters[transaction.characterKey]
        row.characterName = transaction.characterName or (character and character.name)
        row.characterClassFile = character and character.classFile
    end

    if #rows == 0 then
        for _, entry in ipairs(Helpers.sortedEntries(currencies.entries, "spent")) do
            local currency = entry.value
            Helpers.appendRow(
                rows,
                currency.name or L.UNKNOWN_CURRENCY,
                string.format(
                    L.CURRENCY_EARNED_SPENT,
                    Util:FormatNumber(currency.earned),
                    Util:FormatNumber(currency.spent)
                ),
                currency.balance ~= nil
                    and string.format(L.CURRENCY_BALANCE, Util:FormatNumber(currency.balance))
                    or ""
            )
        end
    end

    return rows
end

UI.DetailBuilders.currencies = buildCurrencyRows
