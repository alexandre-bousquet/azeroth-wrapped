-- Character and warband gold detail rows.
local _, AW = ...

local UI = AW.UI
local L = AW.L
local Util = AW.Util
local Helpers = UI.DetailHelpers

local function buildMoneyRows(summary)
    local rows = {}
    local wallets = summary.money and summary.money.characters or {}
    local warbandBalance = tonumber(summary.warbandBalance)

    if warbandBalance ~= nil then
        Helpers.appendRow(
            rows,
            L.DETAIL_GOLD_WARBAND,
            string.format(L.DETAIL_GOLD_BALANCE, Util:FormatGold(warbandBalance)),
            ""
        )
    end

    for _, entry in ipairs(Helpers.sortedEntries(wallets, nil, function(wallet)
        return (tonumber(wallet.earned) or 0) + (tonumber(wallet.spent) or 0)
    end)) do
        local wallet = entry.value
        local storedCharacter = AW.Database.db.characters[entry.key] or {}
        local name = wallet.name or storedCharacter.name or entry.key
        local balance = wallet.balance
        if balance == nil then
            balance = storedCharacter.moneyCopper
        end

        local flow = string.format(
            L.DETAIL_GOLD_FLOW,
            Util:FormatGold(wallet.earned),
            Util:FormatGold(wallet.spent)
        )
        local balanceText = balance ~= nil and string.format(L.DETAIL_GOLD_BALANCE, Util:FormatGold(balance)) or nil
        local net = (wallet.changes or 0) > 0 and Util:FormatGold(wallet.net, true) or L.NO_GOLD_CHANGE

        Helpers.appendRow(rows, name, Helpers.joinDetails(flow, balanceText), net)
    end

    return rows
end

UI.DetailBuilders.gold = buildMoneyRows

