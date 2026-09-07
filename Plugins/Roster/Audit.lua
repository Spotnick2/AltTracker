------------------------------------------------------------
-- AltTracker Roster - gear audit evaluator
--
-- Turns a character record into a list of gear problems, in the spirit of
-- CLA's "gear issues" sheet: missing/subpar enchants, missing/low-quality
-- gems, inactive meta gems, and empty slots.
--
-- Pure logic, no frames -- RosterAudit.lua renders the result. Reference data
-- lives in EnchantData.lua. Both load before AltTrackerRoster.lua.
--
-- Input is char["gearmod_<slot>"], written by Scanner.lua and synced by
-- Core.lua as a packed "<ench>:<sockets>:<g1>:<g2>:<g3>" string. Four states
-- must stay distinguishable or a legacy record reads as a flawless character:
--
--   nil   field absent      -> record predates gearmod_; audit unavailable
--   ""    slot empty        -> nothing equipped
--   "?"   sockets unresolved-> item was uncached at scan time; skip gem checks
--   "0"   sockets confirmed -> item genuinely has no sockets
--
-- Values that arrive over sync are PEER INPUT and are validated accordingly.
------------------------------------------------------------

AltTracker = AltTracker or {}

------------------------------------------------------------
-- Slots, in paper-doll order
------------------------------------------------------------

local SLOT_ORDER = {
    "head", "neck", "shoulder", "back", "chest", "wrist", "hands", "waist",
    "legs", "feet", "ring1", "ring2", "trinket1", "trinket2",
    "mainhand", "offhand", "ranged",
}

-- An empty offhand is correct for anyone using a two-hander, so CLA never
-- reports slot 16 as missing and neither do we.
local NO_ITEM_SKIP = { offhand = true }

local MAX_SOCKETS = 3   -- TBC caps items at three sockets

------------------------------------------------------------
-- Issue codes
--
-- Colours are CLA's spreadsheet fills. They are tuned for a white sheet and
-- will glare on the addon's charcoal background, so the renderer uses them at
-- full strength only for the dot and the severity bar (see RosterAudit.lua).
-- `rank` orders the list, most severe first.
------------------------------------------------------------

AltTracker.AUDIT_CODES = {
    noItem       = { rank = 1, label = "no item",       r = 1.000, g = 0.027, b = 0.027 },
    noEnchant    = { rank = 2, label = "no enchant",    r = 0.973, g = 0.667, b = 0.667 },
    noGem        = { rank = 3, label = "no gem",        r = 0.969, g = 0.812, b = 0.882 },
    metaInactive = { rank = 4, label = "meta gem inactive", r = 0.976, g = 0.796, b = 0.612 },
    badEnchant   = { rank = 5, label = "cheap enchant", r = 0.992, g = 0.949, b = 0.808 },
    commonGem    = { rank = 6, label = "common gem",    r = 0.718, g = 0.718, b = 0.718 },
    uncommonGem  = { rank = 7, label = "uncommon gem",  r = 0.749, g = 0.933, b = 0.682 },
    rareGem      = { rank = 8, label = "rare gem",      r = 0.663, g = 0.761, b = 0.945 },
}

------------------------------------------------------------
-- Packed-field parsing
------------------------------------------------------------

-- Returns enchantID (number), sockets (number or nil when unresolved),
-- gems (array of non-zero gem IDs), ok (false when the slot is empty or the
-- value is malformed).
--
-- Anything that fails validation is reported as unresolved rather than
-- trusted: a malformed value from a peer must never read as "0 sockets,
-- no enchant", which would look like a clean slot.
local function ParseGearMod(packed)
    if type(packed) ~= "string" or packed == "" then
        return 0, nil, {}, false
    end

    local ench, sock, g1, g2, g3 =
        packed:match("^(%-?%d+):([%d%?]+):(%-?%d+):(%-?%d+):(%-?%d+)$")
    if not ench then
        return 0, nil, {}, false
    end

    local sockets = tonumber(sock)
    if sockets then
        if sockets < 0 then
            sockets = 0
        elseif sockets > MAX_SOCKETS then
            sockets = MAX_SOCKETS
        end
    end

    local gems = {}
    for _, id in ipairs({ tonumber(g1) or 0, tonumber(g2) or 0, tonumber(g3) or 0 }) do
        if id > 0 then gems[#gems + 1] = id end
    end

    return tonumber(ench) or 0, sockets, gems, true
end

------------------------------------------------------------
-- Item / gem lookups
------------------------------------------------------------

-- itemEquipLoc for an item id, or nil when the client hasn't cached it.
local function EquipLoc(itemID)
    if not itemID or itemID == 0 then return nil end
    if type(GetItemInfoInstant) == "function" then
        local ok, _, _, _, equipLoc = pcall(GetItemInfoInstant, itemID)
        if ok and equipLoc and equipLoc ~= "" then return equipLoc end
    end
    if type(GetItemInfo) == "function" then
        local ok, res = pcall(function() return select(9, GetItemInfo(itemID)) end)
        if ok and res and res ~= "" then return res end
    end
    return nil
end

-- Gem colour contributions. Hybrids count for BOTH of their component
-- colours, which is what makes CLA's overlapping hardcoded ID lists
-- unnecessary: purple satisfies a red OR a blue requirement, and so on.
local GEM_SUBCLASS = {
    [0] = { "red" },
    [1] = { "blue" },
    [2] = { "yellow" },
    [3] = { "red", "blue" },              -- Purple
    [4] = { "blue", "yellow" },           -- Green
    [5] = { "red", "yellow" },            -- Orange
    [6] = { "meta" },
    [7] = {},                             -- Simple (no colour requirement satisfied)
    [8] = { "red", "blue", "yellow" },    -- Prismatic
}

-- Returns the colour list for a gem, or nil when it can't be resolved.
-- classID must be 3 (Gem): reading an arbitrary item's subclass as a gem
-- colour would be a quiet logic error.
local function GemColors(gemID)
    if not gemID or gemID == 0 then return nil end
    if type(GetItemInfoInstant) ~= "function" then return nil end
    local ok, _, _, _, _, _, classID, subClassID = pcall(GetItemInfoInstant, gemID)
    if not ok or classID ~= 3 or subClassID == nil then return nil end
    return GEM_SUBCLASS[subClassID]
end

local function GemQuality(gemID)
    if not gemID or gemID == 0 then return nil end
    if type(GetItemInfo) ~= "function" then return nil end
    local ok, res = pcall(function() return select(3, GetItemInfo(gemID)) end)
    if ok then return tonumber(res) end
    return nil
end

-- Tally colours across every equipped gem. Meta gems satisfy no ordinary
-- colour requirement, so they are counted separately.
local function GemColorCounts(allGems)
    local counts = { red = 0, blue = 0, yellow = 0, meta = 0, unknown = 0 }
    for _, gemID in ipairs(allGems) do
        local colors = GemColors(gemID)
        if colors then
            for _, c in ipairs(colors) do counts[c] = counts[c] + 1 end
        else
            counts.unknown = counts.unknown + 1
        end
    end
    return counts
end

-- CLA writes its requirements as strict ">" on counts; EnchantData stores the
-- equivalent ">=" minimums plus the three relative rules.
local function MetaIsActive(req, counts)
    if req.red    and counts.red    < req.red    then return false end
    if req.blue   and counts.blue   < req.blue   then return false end
    if req.yellow and counts.yellow < req.yellow then return false end
    if req.moreRedThanBlue    and not (counts.red  > counts.blue)   then return false end
    if req.moreRedThanYellow  and not (counts.red  > counts.yellow) then return false end
    if req.moreBlueThanYellow and not (counts.blue > counts.yellow) then return false end
    return true
end

------------------------------------------------------------
-- Enchant lookup
--
-- slots[slotKey] first, then any. Several IDs carry both forms, and one ID can
-- be restricted to different slots with a different label each, so this must
-- consult every shape rather than a flat [id] -> name map.
------------------------------------------------------------

local function BadEnchantName(enchantID, slotKey)
    local entry = AltTracker.BadEnchants and AltTracker.BadEnchants[enchantID]
    if not entry then return nil end
    if entry.slots and entry.slots[slotKey] then return entry.slots[slotKey] end
    return entry.any
end

-- Enchantable slots are mostly static, but offhand depends on what's in it:
-- a weapon takes weapon enchants and a shield takes shield enchants, while a
-- held-in-off-hand frill cannot be enchanted at all. When the item isn't
-- cached we return false rather than guess -- better a missed warning than a
-- false one.
local function IsEnchantable(slotKey, itemID)
    if not (AltTracker.ENCHANTABLE_SLOTS and AltTracker.ENCHANTABLE_SLOTS[slotKey]) then
        return false
    end
    if slotKey ~= "offhand" then return true end
    local loc = EquipLoc(itemID)
    if not loc then return false end
    return loc ~= "INVTYPE_HOLDABLE"
end

------------------------------------------------------------
-- Config
------------------------------------------------------------

local function MinGemQuality()
    local v = AltTrackerConfig and tonumber(AltTrackerConfig.minGemQuality)
    if v == nil then return 3 end   -- Rare
    return v
end

local function MinLevel()
    local v = AltTrackerConfig and tonumber(AltTrackerConfig.auditMinLevel)
    if v == nil then return 70 end
    return v
end

------------------------------------------------------------
-- AltTracker.AuditCharacter
--
-- Returns an array of issue records sorted most-severe-first, or nil when the
-- record carries no gearmod_ data at all (an old or not-yet-synced record --
-- which must NOT be presented as "no issues").
------------------------------------------------------------

function AltTracker.AuditCharacter(char)
    if type(char) ~= "table" then return nil end

    local hasData = false
    for _, slotKey in ipairs(SLOT_ORDER) do
        if char["gearmod_" .. slotKey] ~= nil then hasData = true break end
    end
    if not hasData then return nil end

    local issues = {}
    if (tonumber(char.level) or 0) < MinLevel() then return issues end

    local minGemQ = MinGemQuality()
    local mainhandLoc = EquipLoc(tonumber(char.gearid_mainhand) or 0)
    local twoHanding = (mainhandLoc == "INVTYPE_2HWEAPON")

    local allGems, metaGemID, metaSlot, metaItemName = {}, nil, nil, nil

    local function add(slotKey, code, itemName, itemID, text)
        local def = AltTracker.AUDIT_CODES[code]
        issues[#issues + 1] = {
            slot = slotKey, code = code, rank = def.rank,
            itemID = itemID, itemName = itemName,
            label = text or def.label,
            r = def.r, g = def.g, b = def.b,
        }
    end

    for slotIndex, slotKey in ipairs(SLOT_ORDER) do
        local itemID   = tonumber(char["gearid_" .. slotKey]) or 0
        local itemName = char["gearname_" .. slotKey] or ""
        local quality  = tonumber(char["gearq_" .. slotKey]) or 0
        local packed   = char["gearmod_" .. slotKey]

        if itemID == 0 then
            -- Empty slot. Skip the ones that are legitimately empty.
            if not NO_ITEM_SKIP[slotKey] and not (twoHanding and slotKey == "offhand") then
                add(slotKey, "noItem", nil, 0)
            end
        elseif not AltTracker.AuditExcludedItems[itemID] then
            local ench, sockets, gems, ok = ParseGearMod(packed)

            -- Only judge gear that is worth judging: a levelling green with no
            -- enchant is not a finding.
            local worthJudging = (quality >= 2)

            if ok and worthJudging then
                if IsEnchantable(slotKey, itemID) then
                    if ench == 0 then
                        add(slotKey, "noEnchant", itemName, itemID)
                    else
                        local badName = BadEnchantName(ench, slotKey)
                        if badName then
                            add(slotKey, "badEnchant", itemName, itemID, badName)
                        end
                    end
                end

                -- Gem checks are suppressed entirely when the socket count is
                -- unresolved: reporting "no gem" off a cache miss would be a
                -- fabricated finding.
                if sockets and minGemQ > 0 then
                    for _ = 1, sockets - #gems do
                        add(slotKey, "noGem", itemName, itemID)
                    end
                    for _, gemID in ipairs(gems) do
                        local gq = GemQuality(gemID)
                        if gq and gq < minGemQ then
                            local code = (gq <= 1 and "commonGem")
                                      or (gq == 2 and "uncommonGem")
                                      or "rareGem"
                            add(slotKey, code, itemName, itemID)
                        end
                    end
                end
            end

            for _, gemID in ipairs(gems) do
                allGems[#allGems + 1] = gemID
                if AltTracker.MetaGems[gemID] then
                    metaGemID, metaSlot, metaItemName = gemID, slotKey, itemName
                end
            end
        end
    end

    -- Meta activation depends on every equipped gem, so it can only be judged
    -- after the whole loop.
    if metaGemID then
        local counts = GemColorCounts(allGems)
        -- An unresolvable gem could be the one that satisfies the requirement,
        -- so stay silent rather than report a false negative.
        if counts.unknown == 0 and not MetaIsActive(AltTracker.MetaGems[metaGemID], counts) then
            add(metaSlot, "metaInactive", metaItemName, tonumber(char["gearid_" .. metaSlot]) or 0)
        end
    end

    local order = {}
    for i, issue in ipairs(issues) do order[issue] = i end
    table.sort(issues, function(a, b)
        if a.rank ~= b.rank then return a.rank < b.rank end
        return order[a] < order[b]   -- stable: keep paper-doll order within a rank
    end)

    return issues
end

------------------------------------------------------------
-- Test seam (harmless in-game), mirroring AltTracker._test in Core.lua.
------------------------------------------------------------

AltTracker._testAudit = {
    ParseGearMod   = ParseGearMod,
    GemColorCounts = GemColorCounts,
    MetaIsActive   = MetaIsActive,
    BadEnchantName = BadEnchantName,
    IsEnchantable  = IsEnchantable,
    EquipLoc       = EquipLoc,
    SLOT_ORDER     = SLOT_ORDER,
}
