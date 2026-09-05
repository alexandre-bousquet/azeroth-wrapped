-- NPC interaction detail rows.
local _, AW = ...

local UI = AW.UI
local L = AW.L
local Util = AW.Util
local Helpers = UI.DetailHelpers

local function buildNPCRows(summary)
    local rows = {}
    local searchText = UI.npcSearchText or ""
    local serviceOrder = {
        "merchant",
        "quest",
        "bank",
        "guildBank",
        "trainer",
        "flightMaster",
        "auctionHouse",
        "mailbox",
        "stableMaster",
        "transmogrifier",
        "voidStorage",
        "itemUpgrade",
        "craftingOrders",
        "scrapping",
        "gossip",
    }

    for _, entry in ipairs(Helpers.sortedEntries(summary.npcs, "interactions")) do
        local npc = entry.value
        local services = {}
        for _, service in ipairs(serviceOrder) do
            if service ~= "gossip" and npc.services and npc.services[service] then
                local label = L["NPC_SERVICE_" .. service]
                if label then
                    services[#services + 1] = label
                end
            end
        end

        if #services == 0 and npc.services and npc.services.gossip then
            services[1] = L.NPC_SERVICE_gossip
        end

        local serviceText = #services > 0 and table.concat(services, ", ") or nil
        local searchableText = Helpers.normalizeSearchText(table.concat({
            npc.name or "",
            npc.title or "",
            serviceText or "",
        }, " "))

        if searchText == "" or string.find(searchableText, searchText, 1, true) then
            local x = tonumber(npc.x)
            local y = tonumber(npc.y)
            local positionText
            local waypoint
            if npc.isSummoned or Util:IsKnownSummonedNPC(npc.npcID) then
                positionText = L.DETAIL_NPC_SUMMONED
            elseif npc.isMount then
                positionText = L.DETAIL_NPC_MOBILE
            elseif npc.mapID and x and y then
                local locationName = npc.mapName or npc.zoneName or L.UNKNOWN_ZONE
                if npc.zoneName and npc.mapName and npc.zoneName ~= npc.mapName then
                    locationName = string.format("%s - %s", npc.mapName, npc.zoneName)
                end
                positionText = string.format(L.DETAIL_NPC_POSITION, locationName, x * 100, y * 100)
                waypoint = {
                    mapID = npc.mapID,
                    x = x,
                    y = y,
                    name = npc.name or L.UNKNOWN_NPC,
                }
            end

            Helpers.appendRow(
                rows,
                npc.name or L.UNKNOWN_NPC,
                Helpers.joinDetails(npc.title, positionText),
                string.format(L.DETAIL_INTERACTIONS, npc.interactions or 0),
                waypoint
            )
        end
    end

    return rows
end

UI.DetailBuilders.npcs = buildNPCRows

