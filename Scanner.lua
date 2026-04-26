AltTracker = AltTracker or {}

local PRIMARY_PROFESSIONS = {
    ["Alchemy"] = true,
    ["Blacksmithing"] = true,
    ["Enchanting"] = true,
    ["Engineering"] = true,
    ["Herbalism"] = true,
    ["Leatherworking"] = true,
    ["Mining"] = true,
    ["Skinning"] = true,
    ["Tailoring"] = true,
    ["Jewelcrafting"] = true,
}

-- All trackable professions for flat field reset
local ALL_PROFESSIONS = {
    "Alchemy","Blacksmithing","Enchanting","Engineering",
    "Herbalism","Leatherworking","Mining","Skinning","Tailoring","Jewelcrafting",
}

------------------------------------------------------------
-- Gear slots
------------------------------------------------------------

local GEAR_SLOTS = {
    { id=1,  key="head"     },
    { id=2,  key="neck"     },
    { id=3,  key="shoulder" },
    { id=15, key="back"     },
    { id=5,  key="chest"    },
    { id=9,  key="wrist"    },
    { id=10, key="hands"    },
    { id=6,  key="waist"    },
    { id=7,  key="legs"     },
    { id=8,  key="feet"     },
    { id=11, key="ring1"    },
    { id=12, key="ring2"    },
    { id=13, key="trinket1" },
    { id=14, key="trinket2" },
    { id=16, key="mainhand" },
    { id=17, key="offhand"  },
    { id=18, key="ranged"   },
}

local function Round2(value)
    return math.floor((tonumber(value) or 0) * 100 + 0.5) / 100
end

local function ResetCharacter(char)

    -- primary professions (legacy fields kept for compat)
    char.prof1 = ""
    char.prof2 = ""
    char.prof1Skill = 0
    char.prof2Skill = 0
    char.prof1Max = 0
    char.prof2Max = 0

    -- flat per-profession fields used by new columns
    for _, name in ipairs(ALL_PROFESSIONS) do
        char["prof_"..name]    = nil
        char["profmax_"..name] = nil
    end

    -- secondary professions
    char.fishing = 0
    char.fishingMax = 0
    char.cooking = 0
    char.cookingMax = 0
    char.firstAid = 0
    char.firstAidMax = 0
    char.riding = 0
    char.ridingMax = 0

    -- gear slots
    for _, slot in ipairs(GEAR_SLOTS) do
        char["gear_"..slot.key]     = 0
        char["gearq_"..slot.key]    = 0   -- item quality (5 = legendary)
        char["gearname_"..slot.key] = ""   -- item name (for BiS matching)
        char["gearlink_"..slot.key] = ""   -- full item link (for tooltips)
    end

end

function AltTracker.ScanCharacter()

    AltTrackerDB = AltTrackerDB or {}

    local guid = UnitGUID("player")
    local name = UnitName("player")
    local realm = GetRealmName()

    if not guid then
        return
    end

    --------------------------------------------------------
    -- Use GUID as unique character key
    --------------------------------------------------------

    AltTrackerDB[guid] = AltTrackerDB[guid] or {}
    local char = AltTrackerDB[guid]

    char.guid = guid
    char.name = name
    char.realm = realm

    -- Account number: set once with /alts account 1 (or 2, etc.)
    -- Stored globally so all chars on this client share the same value.
    AltTrackerConfig = AltTrackerConfig or {}
    char.account = AltTrackerConfig.accountNumber or ""

    --------------------------------------------------------
    -- Basic character info
    --------------------------------------------------------

    local classLocalized, classFile = UnitClass("player")
    char.class = classFile

    char.race = select(2, UnitRace("player"))

    -- Gender: 2 = male, 3 = female
    local gender = UnitSex("player")
    char.gender = (gender == 3) and "Female" or "Male"

    char.level = UnitLevel("player")

    --------------------------------------------------------
    -- Guild
    --------------------------------------------------------

    local guild = GetGuildInfo("player")
    char.guild = guild or ""

    --------------------------------------------------------
    -- Active spec (talent tree with most points)
    --------------------------------------------------------

    local maxPoints = 0
    local specName  = ""
    local specIcon  = ""
    if GetNumTalentTabs then
        for tab = 1, GetNumTalentTabs() do
            -- TBC Classic returns: id, name, description, icon, pointsSpent, ...
            local _, tabName, _, iconTexture, pointsSpent = GetTalentTabInfo(tab)
            pointsSpent = tonumber(pointsSpent) or 0
            if pointsSpent > maxPoints then
                maxPoints  = pointsSpent
                specName   = tabName or ""
                specIcon   = iconTexture or ""
            end
        end
    end
    char.spec     = specName
    char.specIcon = specIcon

    --------------------------------------------------------
    -- Item level
    --------------------------------------------------------

    if GetAverageItemLevel then
        local ilvl = select(2, GetAverageItemLevel())
        char.ilvl = ilvl
    end

    --------------------------------------------------------
    -- Money
    --------------------------------------------------------

    char.money = GetMoney()

    --------------------------------------------------------
    -- Rested XP
    --
    -- We store the current snapshot plus enough context to
    -- extrapolate rested XP forward for this character while
    -- they're offline.  See RowRenderer for the extrapolation.
    --   restXP       : current rested XP (raw)
    --   restPercent  : rested as % of XP-to-next-level (0..150)
    --   xpMax        : UnitXPMax at scan time — needed so the
    --                  renderer can re-divide if the restXP
    --                  value is still useful offline
    --   restedArea   : true if the character was in an inn /
    --                  rested-state zone at scan time.  In TBC,
    --                  rested XP accrues at 2x the normal rate
    --                  while in a rested area.
    --   restTimestamp: when the snapshot was taken.  Normally
    --                  the same as lastUpdate but kept separate
    --                  so we can always trust it for the
    --                  offline extrapolation math.
    --------------------------------------------------------

    local rested = GetXPExhaustion() or 0
    local nextXP = UnitXPMax("player") or 1

    char.restXP = rested
    char.restPercent = math.floor((rested / nextXP) * 100)
    char.xpMax = nextXP
    char.restedArea = IsResting and IsResting() or false
    char.restTimestamp = time()

    -- XP progress toward next level (0-100%), only meaningful below cap
    local currentXP = UnitXP("player") or 0
    char.xpPercent = math.floor((currentXP / nextXP) * 100)

    --------------------------------------------------------
    -- Reset profession data
    --------------------------------------------------------

    ResetCharacter(char)

    --------------------------------------------------------
    -- Core stat snapshot (for offline detail view)
    --------------------------------------------------------

    local _, statStr = UnitStat("player", 1)
    local _, statAgi = UnitStat("player", 2)
    local _, statSta = UnitStat("player", 3)
    local _, statInt = UnitStat("player", 4)
    local _, statSpi = UnitStat("player", 5)

    char.stat_str = statStr or 0
    char.stat_agi = statAgi or 0
    char.stat_sta = statSta or 0
    char.stat_int = statInt or 0
    char.stat_spi = statSpi or 0

    char.stat_hp = UnitHealthMax("player") or 0

    local manaMax = 0
    if UnitPowerMax then
        manaMax = UnitPowerMax("player", 0) or 0
    elseif UnitManaMax then
        manaMax = UnitManaMax("player") or 0
    elseif UnitMana then
        manaMax = UnitMana("player") or 0
    end
    char.stat_mana = manaMax

    local _, effectiveArmor = UnitArmor("player")
    char.stat_armor = effectiveArmor or 0

    local baseAP, posAP, negAP = UnitAttackPower("player")
    char.stat_ap = (baseAP or 0) + (posAP or 0) + (negAP or 0)

    local spellPower = 0
    if GetSpellBonusDamage then
        for school = 2, 7 do
            local sp = GetSpellBonusDamage(school) or 0
            if sp > spellPower then
                spellPower = sp
            end
        end
    end
    char.stat_sp = spellPower

    char.stat_crit = 0
    if GetCombatRatingBonus and CR_CRIT_MELEE then
        char.stat_crit = Round2(GetCombatRatingBonus(CR_CRIT_MELEE))
    end

    char.stat_hitpct = 0
    if GetCombatRatingBonus and CR_HIT_MELEE then
        char.stat_hitpct = Round2(GetCombatRatingBonus(CR_HIT_MELEE))
    end

    char.stat_haste = 0
    if GetCombatRatingBonus and CR_HASTE_MELEE then
        char.stat_haste = Round2(GetCombatRatingBonus(CR_HASTE_MELEE))
    end

    local baseDef, modDef = UnitDefense("player")
    char.stat_defense = (baseDef or 0) + (modDef or 0)

    char.stat_resilience = 0
    local resilIndex = CR_RESILIENCE_CRIT_TAKEN
        or COMBAT_RATING_RESILIENCE_PLAYER_DAMAGE_TAKEN
        or CR_RESILIENCE_PLAYER_DAMAGE_TAKEN
    if GetCombatRating and resilIndex then
        char.stat_resilience = GetCombatRating(resilIndex) or 0
    end

    --------------------------------------------------------
    -- Scan professions
    --------------------------------------------------------

    local primaryCount = 0

    for i = 1, GetNumSkillLines() do

        local skillName, isHeader, _, rank, _, _, maxRank = GetSkillLineInfo(i)

        if not isHeader and skillName then

            if skillName == "Fishing" then
                char.fishing = rank or 0
                char.fishingMax = maxRank or 0

            elseif skillName == "Cooking" then
                char.cooking = rank or 0
                char.cookingMax = maxRank or 0

            elseif skillName == "First Aid" then
                char.firstAid = rank or 0
                char.firstAidMax = maxRank or 0

            elseif skillName == "Riding" then
                char.riding = rank or 0
                char.ridingMax = maxRank or 0

            elseif PRIMARY_PROFESSIONS[skillName] then

                primaryCount = primaryCount + 1

                -- Flat field for new column layout
                char["prof_"..skillName]    = rank or 0
                char["profmax_"..skillName] = maxRank or 0

                if primaryCount == 1 then
                    char.prof1 = skillName
                    char.prof1Skill = rank or 0
                    char.prof1Max = maxRank or 0

                elseif primaryCount == 2 then
                    char.prof2 = skillName
                    char.prof2Skill = rank or 0
                    char.prof2Max = maxRank or 0
                end
            end
        end
    end

    --------------------------------------------------------
    -- Reputations
    --------------------------------------------------------

    if AltTracker.ScanReputations then
        AltTracker.ScanReputations(char)
    end

    -- CD definitions are used by Core.lua event handlers and RowRenderer tooltips.
    -- Actual cooldown scanning happens via TRADE_SKILL_SHOW and UNIT_SPELLCAST_SUCCEEDED
    -- events in Core.lua — NOT here at login, because GetSpellCooldown is unreliable
    -- unless the tradeskill window is open.
    AltTracker.ProfCooldownDefs = {
        -- Maps tradeskill recipe name → { storageKey, displayName }
        -- Used when scanning via GetTradeSkillCooldown(i)
        ["Primal Mooncloth"] = { key="cd_Mooncloth",   profKey="Tailoring", name="Primal Mooncloth"  },
        ["Shadowcloth"]      = { key="cd_Shadowcloth", profKey="Tailoring", name="Shadowcloth"       },
        ["Spellcloth"]       = { key="cd_Spellcloth",  profKey="Tailoring", name="Spellcloth"        },

        -- Alchemy: all transmutes share one 2-day CD; any transmute recipe reveals it
        ["Transmute: Primal Might"]  = { key="cd_Transmute", profKey="Alchemy", name="Transmute" },
        ["Transmute: Primal Fire"]   = { key="cd_Transmute", profKey="Alchemy", name="Transmute" },
        ["Transmute: Primal Earth"]  = { key="cd_Transmute", profKey="Alchemy", name="Transmute" },
        ["Transmute: Primal Water"]  = { key="cd_Transmute", profKey="Alchemy", name="Transmute" },
        ["Transmute: Primal Air"]    = { key="cd_Transmute", profKey="Alchemy", name="Transmute" },
        ["Transmute: Primal Mana"]   = { key="cd_Transmute", profKey="Alchemy", name="Transmute" },
        ["Transmute: Primal Life"]   = { key="cd_Transmute", profKey="Alchemy", name="Transmute" },
        ["Transmute: Primal Shadow"] = { key="cd_Transmute", profKey="Alchemy", name="Transmute" },
        ["Transmute: Skyfire Diamond"]   = { key="cd_Transmute", profKey="Alchemy", name="Transmute" },
        ["Transmute: Earthstorm Diamond"]= { key="cd_Transmute", profKey="Alchemy", name="Transmute" },

        -- Jewelcrafting daily
        ["Brilliant Glass"] = { key="cd_BrilliantGlass", profKey="Jewelcrafting", name="Brilliant Glass" },
    }

    -- Summary table used by RowRenderer: which keys to show per profession column
    AltTracker.ProfCDKeys = {
        Tailoring    = { {key="cd_Mooncloth",name="Primal Mooncloth"}, {key="cd_Shadowcloth",name="Shadowcloth"}, {key="cd_Spellcloth",name="Spellcloth"} },
        Alchemy      = { {key="cd_Transmute",name="Transmute"} },
        Jewelcrafting= { {key="cd_BrilliantGlass",name="Brilliant Glass"} },
    }

    --------------------------------------------------------
    -- Gear slots — item level per slot
    -- GetItemInfo can return nil at login if the item isn't in the
    -- client cache yet. We track whether any slots are still pending
    -- so we can retry once the cache is populated.
    --------------------------------------------------------

    local pendingLinks = {}  -- links that returned nil from GetItemInfo

    for _, slot in ipairs(GEAR_SLOTS) do
        local link = GetInventoryItemLink("player", slot.id)
        if link then
            local itemName, _, quality, ilvl = GetItemInfo(link)
            if ilvl then
                char["gear_"..slot.key]      = ilvl
                char["gearq_"..slot.key]     = quality or 0
                char["gearname_"..slot.key]  = itemName or ""
                char["gearlink_"..slot.key]  = link
            else
                -- Item link exists but data not cached yet — keep old value,
                -- queue link for retry once GET_ITEM_INFO_RECEIVED fires.
                pendingLinks[link] = slot.key
            end
        else
            char["gear_"..slot.key]      = 0
            char["gearq_"..slot.key]     = 0
            char["gearname_"..slot.key]  = ""
            char["gearlink_"..slot.key]  = ""
        end
    end

    -- Only stamp lastUpdate when we have complete data.
    -- If any items are pending cache we deliberately leave the timestamp
    -- unchanged so peers don't reject a later corrected version.
    if not next(pendingLinks) then
        char.lastUpdate = time()
    end

    -- Register for cache-ready events to fill in pending slots
    if next(pendingLinks) then
        AltTracker.PendingGearLinks = AltTracker.PendingGearLinks or {}
        for link, key in pairs(pendingLinks) do
            AltTracker.PendingGearLinks[link] = { key = key, guid = char.guid }
        end
    end

    return char

end
