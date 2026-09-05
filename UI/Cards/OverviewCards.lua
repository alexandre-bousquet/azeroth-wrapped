-- Built-in overview cards and their presentation callbacks.
local _, AW = ...

local UI = AW.UI
local L = AW.L
local Theme = AW.Theme
local Util = AW.Util

local function setText(fontString, value)
    Theme:SetText(fontString, value)
end

UI:RegisterCard({
    key = "time",
    titleKey = "CARD_TIME",
    icon = "Interface/Icons/INV_Misc_PocketWatch_01",
    accent = Theme.cyan,
    render = function(card, summary)
        setText(card.primary, summary.hasData and string.format(L.ONLINE_TIME, Util:FormatDuration(summary.onlineSeconds)) or L.EMPTY_VALUE)
        setText(card.secondary, string.format(L.SESSION_COUNT, summary.sessionCount or 0))
        setText(card.tertiary, string.format(L.LONGEST_SESSION, Util:FormatDuration(summary.longestSession)))
    end,
})

UI:RegisterCard({
    key = "world",
    titleKey = "CARD_WORLD",
    icon = "Interface/Icons/INV_Misc_Map_01",
    accent = Theme.gold,
    render = function(card, summary)
        local topZone = summary.topZone
        setText(card.primary, topZone and topZone.name or L.EMPTY_VALUE)
        setText(card.secondary, string.format(L.ZONES_VISITED, summary.zoneCount or 0))
        setText(card.tertiary, topZone and string.format(L.TIME_SPENT, Util:FormatDuration(topZone.seconds)) or "")
    end,
})

UI:RegisterCard({
    key = "fate",
    titleKey = "CARD_FATE",
    icon = "Interface/Icons/Ability_Rogue_FeignDeath",
    accent = Theme.danger,
    render = function(card, summary)
        setText(
            card.primary,
            summary.deaths.total > 0
                and Util:FormatCount(summary.deaths.total, L.DEATH_COUNT_ONE, L.DEATH_COUNT)
                or L.NO_DEATHS
        )
        setText(card.secondary, summary.deadliestLocation and string.format(L.DEADLIEST, summary.deadliestLocation.name) or "")
        setText(card.tertiary, string.format(L.DAYS_PLAYED, summary.daysPlayed or 0))
    end,
})

UI:RegisterCard({
    key = "companion",
    titleKey = "CARD_COMPANION",
    icon = "Interface/Icons/Achievement_GuildPerk_EverybodysFriend",
    accent = Theme.purple,
    render = function(card, summary)
        local companion = summary.topGroupmate
        local name = companion and companion.name or L.EMPTY_VALUE
        local realm = companion and companion.realm or ""
        if companion and AW.Database.db.settings.anonymousShare then
            name = L.PRIVATE_PLAYER
            realm = ""
        end
        setText(card.primary, name)
        setText(card.secondary, realm)
        setText(card.tertiary, companion and string.format(L.TOGETHER_TIME, Util:FormatMinutes(companion.seconds)) or "")
    end,
})

UI:RegisterCard({
    key = "identity",
    titleKey = "CARD_IDENTITY",
    icon = "Interface/Icons/Achievement_Character_Human_Male",
    accent = Theme.cyan,
    render = function(card, summary)
        local character = summary.topCharacter
        setText(card.primary, character and character.name or L.EMPTY_VALUE)
        setText(card.secondary, character and string.format(L.TOP_CHARACTER, Util:FormatDuration(character.seconds)) or "")
        setText(card.tertiary, string.format(L.MAIN_ACTIVITY, L["ACTIVITY_" .. (summary.topActivityKey or "unknown")] or L.ACTIVITY_unknown))
    end,
})

UI:RegisterCard({
    key = "npcs",
    titleKey = "CARD_ENCOUNTERS",
    icon = "Interface/Icons/INV_Misc_Book_09",
    accent = Theme.gold,
    render = function(card, summary)
        local npc = summary.topNPC
        setText(card.primary, npc and npc.name or L.EMPTY_VALUE)
        setText(card.secondary, string.format(L.NPC_COUNT, summary.npcCount or 0))
        setText(card.tertiary, npc and string.format(L.NPC_INTERACTIONS, npc.interactions or 0) or "")
    end,
})

UI:RegisterCard({
    key = "gold",
    titleKey = "CARD_GOLD",
    icon = "Interface/Icons/INV_Misc_Coin_01",
    accent = Theme.gold,
    render = function(card, summary)
        if summary.hasMoneyData then
            local primary = summary.money.changes > 0 and Util:FormatGold(summary.money.net, true) or L.NO_GOLD_CHANGE
            setText(card.primary, primary)
            setText(card.secondary, string.format(L.GOLD_EARNED_SPENT, Util:FormatGold(summary.money.earned), Util:FormatGold(summary.money.spent)))
            setText(card.tertiary, string.format(L.GOLD_BALANCE, Util:FormatGold(summary.knownBalance)))
        else
            setText(card.primary, L.EMPTY_VALUE)
            setText(card.secondary, "")
            setText(card.tertiary, "")
        end
    end,
})

UI:RegisterCard({
    key = "activities",
    titleKey = "CARD_ACTIVITIES",
    icon = "Interface/Icons/Achievement_Boss_LichKing",
    accent = Theme.danger,
    render = function(card, summary)
        if not summary.hasCompletedActivityData then
            setText(card.primary, L.NO_COMPLETED_ACTIVITIES)
            setText(card.secondary, "")
            setText(card.tertiary, "")
            return
        end

        local activities = summary.completedActivities
        local dungeonCount = tonumber(activities.dungeon) or 0
        local raidBossCount = tonumber(activities.raid) or 0
        local outdoorCount = tonumber(activities.outdoor) or 0
        local dungeonText = string.format(dungeonCount > 1 and L.ACTIVITY_DUNGEON_MANY or L.ACTIVITY_DUNGEON_ONE, dungeonCount)
        local raidText = string.format(raidBossCount > 1 and L.ACTIVITY_RAID_BOSS_MANY or L.ACTIVITY_RAID_BOSS_ONE, raidBossCount)
        local outdoorText = string.format(outdoorCount > 1 and L.ACTIVITY_OUTDOOR_MANY or L.ACTIVITY_OUTDOOR_ONE, outdoorCount)

        setText(card.primary, string.format(L.ACTIVITY_COUNT, activities.total))
        setText(card.secondary, string.format(L.ACTIVITY_BREAKDOWN, dungeonText, raidText, outdoorText))
        setText(
            card.tertiary,
            summary.latestCompletedActivity
                and string.format(L.LAST_COMPLETED_ACTIVITY, summary.latestCompletedActivity.name or L.UNKNOWN_ACTIVITY)
                or ""
        )
    end,
})
