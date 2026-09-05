-- Currency gains, expenses, balances, and best-effort spending context.
local _, AW = ...

local CurrencyTracker = CreateFrame("Frame")
AW.CurrencyTracker = CurrencyTracker

local Database = AW.Database
local Util = AW.Util

local MERCHANT_CONTEXT_SECONDS = 3

local function safeNumber(value)
    if issecretvalue and issecretvalue(value) then
        return nil
    end

    local ok, number = pcall(tonumber, value)
    return ok and number or nil
end

local function safeCurrencyInfo(currencyID)
    if not C_CurrencyInfo or not C_CurrencyInfo.GetCurrencyInfo then
        return nil
    end

    local ok, info = pcall(C_CurrencyInfo.GetCurrencyInfo, currencyID)
    if not ok or type(info) ~= "table" or (issecretvalue and issecretvalue(info)) then
        return nil
    end
    return info
end

local function ensureCurrencyEntry(day, currencyID, info)
    local key = tostring(currencyID)
    local entry = day.currencies.entries[key]
    if type(entry) ~= "table" then
        entry = {
            currencyID = currencyID,
            earned = 0,
            spent = 0,
            changes = 0,
            spendingEvents = 0,
            characters = {},
        }
        day.currencies.entries[key] = entry
    end

    entry.currencyID = currencyID
    entry.name = (info and info.name) or entry.name
    entry.iconFileID = (info and info.iconFileID) or entry.iconFileID
    entry.quality = (info and info.quality) or entry.quality
    entry.isAccountWide = info and info.isAccountWide or entry.isAccountWide
    entry.earned = safeNumber(entry.earned) or 0
    entry.spent = safeNumber(entry.spent) or 0
    entry.changes = safeNumber(entry.changes) or 0
    entry.spendingEvents = safeNumber(entry.spendingEvents) or 0
    if type(entry.characters) ~= "table" then
        entry.characters = {}
    end
    return entry
end

local function ensureCharacterEntry(entry, characterKey, characterName)
    local character = entry.characters[characterKey]
    if type(character) ~= "table" then
        character = {
            name = characterName,
            earned = 0,
            spent = 0,
            changes = 0,
            spendingEvents = 0,
        }
        entry.characters[characterKey] = character
    end
    return character
end

function CurrencyTracker:CaptureMerchantPurchase(index, quantity)
    index = safeNumber(index)
    if not index then
        return
    end

    local name
    local itemID
    if C_MerchantFrame and C_MerchantFrame.GetItemInfo then
        local ok, info = pcall(C_MerchantFrame.GetItemInfo, index)
        if ok and type(info) == "table" and not (issecretvalue and issecretvalue(info)) then
            name = info.name
        end
    end

    local link
    if GetMerchantItemLink then
        local ok, value = pcall(GetMerchantItemLink, index)
        if ok then
            link = value
        end
    end
    if link and C_Item and C_Item.GetItemIDForItemInfo then
        local ok, value = pcall(C_Item.GetItemIDForItemInfo, link)
        if ok then
            itemID = safeNumber(value)
        end
    elseif link and GetItemInfoInstant then
        local ok, value = pcall(GetItemInfoInstant, link)
        if ok then
            itemID = safeNumber(value)
        end
    end
    if not name and link and GetItemInfo then
        local ok, value = pcall(GetItemInfo, link)
        if ok then
            name = value
        end
    end

    self.pendingSpend = {
        kind = "vendor",
        name = name,
        itemID = itemID,
        itemLink = link,
        quantity = safeNumber(quantity) or 1,
        expiresAt = GetTime() + MERCHANT_CONTEXT_SECONDS,
    }
end

function CurrencyTracker:GetSpendingContext(destroyReason)
    local pending = self.pendingSpend
    if pending and pending.expiresAt >= GetTime() and (destroyReason == nil or destroyReason == 4) then
        return pending
    end
    if pending and pending.expiresAt < GetTime() then
        self.pendingSpend = nil
    end
    return nil
end

function CurrencyTracker:RecordChange(currencyID, quantity, quantityChange, quantityGainSource, destroyReason)
    currencyID = safeNumber(currencyID)
    if not currencyID or not Database.db then
        return
    end

    local info = safeCurrencyInfo(currencyID)
    local currentQuantity = safeNumber(quantity) or (info and safeNumber(info.quantity))
    local delta = safeNumber(quantityChange)
    local previousQuantity = self.balances and self.balances[currencyID]

    if delta == nil and currentQuantity ~= nil and previousQuantity ~= nil then
        delta = currentQuantity - previousQuantity
    end
    self.balances = self.balances or {}
    if currentQuantity ~= nil then
        self.balances[currencyID] = currentQuantity
    end

    if not delta or delta == 0 then
        return
    end
    if not Database.db.settings.enabled or not Database.db.settings.trackCurrencies then
        return
    end

    local day = Database:GetDay()
    local entry = ensureCurrencyEntry(day, currencyID, info)
    local characterKey, characterName = Util:GetCharacterKey()
    local character = ensureCharacterEntry(entry, characterKey, characterName)
    local earned = delta > 0 and delta or 0
    local spent = delta < 0 and -delta or 0

    day.currencies.earned = (safeNumber(day.currencies.earned) or 0) + earned
    day.currencies.spent = (safeNumber(day.currencies.spent) or 0) + spent
    day.currencies.changes = (safeNumber(day.currencies.changes) or 0) + 1
    entry.earned = entry.earned + earned
    entry.spent = entry.spent + spent
    entry.changes = entry.changes + 1
    character.earned = (safeNumber(character.earned) or 0) + earned
    character.spent = (safeNumber(character.spent) or 0) + spent
    character.changes = (safeNumber(character.changes) or 0) + 1

    if currentQuantity ~= nil then
        entry.balance = currentQuantity
        character.balance = currentQuantity
    end

    if spent > 0 then
        local context = self:GetSpendingContext(safeNumber(destroyReason))
        entry.spendingEvents = entry.spendingEvents + 1
        character.spendingEvents = (safeNumber(character.spendingEvents) or 0) + 1
        day.currencies.transactions[#day.currencies.transactions + 1] = {
            currencyID = currencyID,
            currencyName = entry.name,
            iconFileID = entry.iconFileID,
            amount = spent,
            balance = currentQuantity,
            timestamp = Util:Now(),
            characterKey = characterKey,
            characterName = characterName,
            contextKind = context and context.kind or nil,
            contextName = context and context.name or nil,
            itemID = context and context.itemID or nil,
            itemLink = context and context.itemLink or nil,
            itemQuantity = context and context.quantity or nil,
            destroyReason = safeNumber(destroyReason),
        }
    end

    Database.db.meta.updatedAt = Util:Now()
end

function CurrencyTracker:CaptureBalances()
    if not C_CurrencyInfo or not C_CurrencyInfo.GetCurrencyListSize or not C_CurrencyInfo.GetCurrencyListInfo then
        return
    end

    self.balances = self.balances or {}
    local ok, size = pcall(C_CurrencyInfo.GetCurrencyListSize)
    size = ok and safeNumber(size) or nil
    if not size then
        return
    end

    for index = 1, size do
        local infoOK, info = pcall(C_CurrencyInfo.GetCurrencyListInfo, index)
        if infoOK and type(info) == "table" and not info.isHeader then
            local currencyID = safeNumber(info.currencyID)
            local quantity = safeNumber(info.quantity)
            if currencyID and quantity then
                self.balances[currencyID] = quantity
            end
        end
    end
end

function CurrencyTracker:InstallMerchantHook()
    if self.merchantHookInstalled or not hooksecurefunc or type(BuyMerchantItem) ~= "function" then
        return
    end

    hooksecurefunc("BuyMerchantItem", function(index, quantity)
        CurrencyTracker:CaptureMerchantPurchase(index, quantity)
    end)
    self.merchantHookInstalled = true
end

CurrencyTracker:SetScript("OnEvent", function(_, event, ...)
    if event == "PLAYER_LOGIN" then
        CurrencyTracker:InstallMerchantHook()
        C_Timer.After(1, function()
            CurrencyTracker:CaptureBalances()
        end)
    elseif event == "CURRENCY_DISPLAY_UPDATE" then
        CurrencyTracker:RecordChange(...)
    elseif event == "MERCHANT_SHOW" then
        CurrencyTracker:InstallMerchantHook()
    end
end)

CurrencyTracker:RegisterEvent("PLAYER_LOGIN")
CurrencyTracker:RegisterEvent("CURRENCY_DISPLAY_UPDATE")
CurrencyTracker:RegisterEvent("MERCHANT_SHOW")
