------------------------------------------------------------
-- test_bis.lua — BiS data coverage and the selectable raid phase.
--
-- Covers:
--   * BisData shape — every class/spec carries all six tier tables,
--     each with the full slot set (offhand may legitimately be nil for
--     two-handed setups).
--   * AltTracker.GetBisTier — default, persistence, and fallback when
--     AltTrackerConfig.bisTier names a tier this build doesn't ship.
--   * AltTracker.GetBisTierLabel — key -> display label.
--
-- RowRenderer.lua creates no frames at load time above the seam we use
-- here, but it does touch AltTracker.C, so Theme.lua is loaded first.
-- Run from the repo root with the Lua 5.1 interpreter:
--   & 'C:\Program Files (x86)\Lua\5.1\lua.exe' tests\test_bis.lua
------------------------------------------------------------

dofile("tests/wow_stubs.lua")

AltTracker = {}
AltTrackerConfig = {}
assert(loadfile("Theme.lua"))()
assert(loadfile("BisData.lua"))()
assert(loadfile("RowRenderer.lua"))()

assert(AltTracker.BisData, "BisData not loaded")
assert(AltTracker.GetBisTier, "GetBisTier not exposed")

------------------------------------------------------------
-- Tiny assert harness (ParseBuddy style)
------------------------------------------------------------
local testsRun, failures = 0, 0
local function check(cond, msg)
    testsRun = testsRun + 1
    if not cond then
        failures = failures + 1
        print("  FAIL: " .. (msg or "assertion failed"))
    end
end
local function eq(a, b, msg)
    check(a == b, (msg or "") .. " (got " .. tostring(a) .. ", want " .. tostring(b) .. ")")
end

------------------------------------------------------------
-- Tier coverage
------------------------------------------------------------
local TIERS = { "PreRaid", "T4", "T5", "T6", "ZA", "Sunwell" }
-- offhand is excluded: a two-handed BiS setup leaves it nil by design.
local REQUIRED_SLOTS = {
    "head", "neck", "shoulder", "back", "chest", "wrist", "hands", "waist",
    "legs", "feet", "ring1", "ring2", "trinket1", "trinket2", "mainhand", "ranged",
}

local specCount = 0
for class, classData in pairs(AltTracker.BisData) do
    for spec, specData in pairs(classData) do
        specCount = specCount + 1
        for _, tier in ipairs(TIERS) do
            local tierData = specData[tier]
            check(tierData ~= nil, class .. "/" .. spec .. " missing tier " .. tier)
            if tierData then
                for _, slot in ipairs(REQUIRED_SLOTS) do
                    local v = tierData[slot]
                    check(v ~= nil,
                        class .. "/" .. spec .. "/" .. tier .. " missing slot " .. slot)
                    if v ~= nil then
                        local ok = type(v) == "string" or type(v) == "table"
                        check(ok, class .. "/" .. spec .. "/" .. tier .. "/" .. slot
                            .. " must be a string or a table of alternatives")
                        if type(v) == "string" then
                            check(v ~= "", class .. "/" .. spec .. "/" .. tier
                                .. "/" .. slot .. " is an empty string")
                        end
                    end
                end
            end
        end
    end
end
check(specCount == 27, "expected 27 class/spec combinations, got " .. specCount)

------------------------------------------------------------
-- Phase selection
------------------------------------------------------------
AltTrackerConfig.bisTier = nil
eq(AltTracker.GetBisTier(), "T6", "unset config falls back to the T6 default")

for _, tier in ipairs(TIERS) do
    AltTrackerConfig.bisTier = tier
    eq(AltTracker.GetBisTier(), tier, "selected tier " .. tier .. " is honoured")
end

-- A tier this build doesn't ship (stale SavedVariable, or a downgrade)
-- must not leave the BiS column looking up a nil table.
AltTrackerConfig.bisTier = "T7"
eq(AltTracker.GetBisTier(), "T6", "unknown tier falls back to the default")
AltTrackerConfig.bisTier = ""
eq(AltTracker.GetBisTier(), "T6", "empty tier falls back to the default")

------------------------------------------------------------
-- Unique-equipped conflicts
--
-- Rings and trinkets come in pairs, so a list may legitimately name the
-- same item for both slots -- Ring of Ancient Knowledge and Loop of Forged
-- Power are not unique and really are worn twice. But if a *unique-equipped*
-- item is listed in both slots, no character can ever satisfy it and that
-- spec silently caps a slot short of full BiS.
--
-- Only flag when both slots name the same single item: two identical tables
-- of alternatives are fine, since the character picks a different entry for
-- each slot.
------------------------------------------------------------
local UNIQUE = assert(loadfile("tests/data_unique_equipped.lua"))()
check(next(UNIQUE) ~= nil, "unique-equipped fixture is empty")

local PAIRS = { { "ring1", "ring2" }, { "trinket1", "trinket2" } }
local dupPairs = 0
for class, classData in pairs(AltTracker.BisData) do
    for spec, specData in pairs(classData) do
        for _, tier in ipairs(TIERS) do
            local tierData = specData[tier]
            if tierData then
                for _, pair in ipairs(PAIRS) do
                    local a, b = tierData[pair[1]], tierData[pair[2]]
                    if type(a) == "string" and type(b) == "string" and a == b then
                        dupPairs = dupPairs + 1
                        check(not UNIQUE[a],
                            class .. "/" .. spec .. "/" .. tier .. ": " .. a
                            .. " is unique-equipped but listed in both "
                            .. pair[1] .. " and " .. pair[2])
                    end
                end
            end
        end
    end
end
-- Guard the guard: if the duplicate-pair count ever drops to zero the check
-- above stops testing anything, so make that visible rather than silent.
check(dupPairs > 0, "expected some duplicated ring/trinket pairs to check")

------------------------------------------------------------
-- Tier labels
------------------------------------------------------------
eq(AltTracker.GetBisTierLabel("PreRaid"), "Pre-Raid", "PreRaid label")
eq(AltTracker.GetBisTierLabel("Sunwell"), "SWP", "Sunwell label")
eq(AltTracker.GetBisTierLabel("T6"), "T6", "T6 label")
eq(AltTracker.GetBisTierLabel("nope"), "nope", "unknown key echoes back")

-- Every entry in BIS_TIERS must resolve against real data, or the options
-- row would offer a phase that silently marks nothing as BiS.
for _, t in ipairs(AltTracker.BIS_TIERS) do
    check(t.key and t.label and t.ceiling, "BIS_TIERS entry is incomplete")
    local sample = AltTracker.BisData["WARRIOR"]["Fury"][t.key]
    check(sample ~= nil, "BIS_TIERS offers " .. tostring(t.key) .. " but BisData has no such tier")
end

------------------------------------------------------------
------------------------------------------------------------
-- Interchangeable slots: ring1/ring2 and trinket1/trinket2
--
-- WoW does not care which ring goes in which socket. Scoring strictly by
-- physical slot meant a player wearing exactly the right pair in the opposite
-- order lost credit for BOTH slots. These pin the pairing behaviour down.
------------------------------------------------------------

local countBis = assert(AltTracker._test and AltTracker._test.CountBisItems,
                        "CountBisItems test seam missing")
local isBis     = assert(AltTracker._test and AltTracker._test.IsItemBis,
                        "IsItemBis test seam missing")

-- Find any class/spec whose current-tier list names two different rings and
-- two different trinkets, so the swap is actually observable.
local function FindPairedFixture(tier)
    for class, specs in pairs(AltTracker.BisData) do
        for spec, tiers in pairs(specs) do
            local t = tiers[tier]
            local function one(slot)
                local v = t and t[slot]
                if type(v) == "string" then return v end
                if type(v) == "table" then return v[1] end
                return nil
            end
            local r1, r2 = one("ring1"), one("ring2")
            local t1, t2 = one("trinket1"), one("trinket2")
            if r1 and r2 and r1 ~= r2 and t1 and t2 and t1 ~= t2 then
                return class, spec, t, r1, r2, t1, t2
            end
        end
    end
end

AltTrackerConfig.bisTier = "T6"
local class, spec, tierData, r1, r2, t1, t2 = FindPairedFixture("T6")
-- Declared here so both the pairing block and the tooltip block below can use it.
local CharWith
check(class ~= nil, "no class/spec with two distinct rings and trinkets at T6")

if class then
    -- Each ring is BiS in EITHER socket, and likewise each trinket.
    check(isBis(class, spec, "ring1", r2), "ring2's item should be BiS in ring1")
    check(isBis(class, spec, "ring2", r1), "ring1's item should be BiS in ring2")
    check(isBis(class, spec, "trinket1", t2), "trinket2's item should be BiS in trinket1")
    check(isBis(class, spec, "trinket2", t1), "trinket1's item should be BiS in trinket2")

    -- A non-BiS item is still rejected in both sockets.
    check(not isBis(class, spec, "ring1", "Definitely Not A Real Ring"),
          "unknown ring must not be BiS")

    -- Build a character wearing the full BiS set, then the same set with the
    -- pairs swapped. Both must score identically.
    CharWith = function(swap)
        local c = { class = class, spec = spec, gear_offhand = 1 }
        for slot, v in pairs(tierData) do
            local name = type(v) == "table" and v[1] or v
            if type(name) == "string" then c["gearname_"..slot] = name end
        end
        if swap then
            c.gearname_ring1,    c.gearname_ring2    = r2, r1
            c.gearname_trinket1, c.gearname_trinket2 = t2, t1
        end
        return c
    end

    local straightCount = countBis(CharWith(false))
    local swappedCount  = countBis(CharWith(true))
    eq(swappedCount, straightCount, "swapped ring/trinket pair must score the same")
    check(straightCount >= 4, "fixture should score at least the four paired slots")

    -- Wearing one BiS ring twice must not be credited twice: the pair's entries
    -- are consumed at most once each.
    local dup = CharWith(false)
    dup.gearname_ring2 = r1
    local dupCount = countBis(dup)
    eq(dupCount, straightCount - 1, "duplicate BiS ring must score once, not twice")
end

------------------------------------------------------------
-- Replacement tooltips must respect the partner slot
--
-- Scoring treats ring1/ring2 as one set, so recommending the entry nominally
-- assigned to a socket can name an item already worn in the other one — and
-- equipping it would not raise the score, since each entry is consumed once.
------------------------------------------------------------

local getBisName = assert(AltTracker._test and AltTracker._test.GetBisItemName,
                          "GetBisItemName test seam missing")

if class then
    -- Baseline: with nothing worn, each socket still suggests its own entry.
    local bare = { class = class, spec = spec }
    eq(getBisName(class, spec, "ring1", bare), r1, "empty ring1 should suggest its own entry")
    eq(getBisName(class, spec, "ring2", bare), r2, "empty ring2 should suggest its own entry")

    -- The reported case: ring2's entry is worn in ring1, ring2 holds a non-BiS ring.
    -- ring2 must NOT be told to equip something already on the character.
    local crossed = { class = class, spec = spec,
                      gearname_ring1 = r2, gearname_ring2 = "Definitely Not A Real Ring" }
    local suggestion = getBisName(class, spec, "ring2", crossed)
    check(suggestion ~= r2, "ring2 must not suggest the ring already worn in ring1")
    eq(suggestion, r1, "ring2 should suggest the remaining unworn entry")

    -- Same for trinkets.
    local crossedT = { class = class, spec = spec,
                       gearname_trinket1 = t2, gearname_trinket2 = "Not A Real Trinket" }
    eq(getBisName(class, spec, "trinket2", crossedT), t1,
       "trinket2 should suggest the remaining unworn entry")

    -- Acting on the suggestion must actually raise the score.
    local before = countBis(CharWith(false))
    local partial = CharWith(false)
    partial.gearname_ring1 = r2
    partial.gearname_ring2 = "Definitely Not A Real Ring"
    local partialCount = countBis(partial)
    local advised = getBisName(class, spec, "ring2", partial)
    partial.gearname_ring2 = advised
    local afterCount = countBis(partial)
    eq(partialCount, before - 1, "one missing ring should cost exactly one point")
    eq(afterCount, before, "equipping the advised ring should restore the point")
end

------------------------------------------------------------
-- Duplicate non-unique pairs
--
-- Several lists name the SAME non-unique item for both paired slots (Ring of
-- Ancient Knowledge fills both ring slots for a number of specs). Wearing one
-- copy must still recommend a second, because scoring awards the second point -
-- consuming one occurrence, not every match.
------------------------------------------------------------

local function FindDuplicatePair(tier)
    for cls, specs in pairs(AltTracker.BisData) do
        for sp, tiers in pairs(specs) do
            local t = tiers[tier]
            local function one(slot)
                local v = t and t[slot]
                if type(v) == "string" then return v end
                if type(v) == "table" then return v[1] end
                return nil
            end
            local a, b = one("ring1"), one("ring2")
            if a and b and a == b then return cls, sp, a end
        end
    end
end

local dupClass, dupSpec, dupRing = FindDuplicatePair("T6")
check(dupClass ~= nil, "expected at least one spec naming the same ring for both slots at T6")

if dupClass then
    -- One copy worn, the other slot empty: a second copy is the correct advice.
    local half = { class = dupClass, spec = dupSpec, gearname_ring1 = dupRing }
    eq(getBisName(dupClass, dupSpec, "ring2", half), dupRing,
       "a duplicate non-unique pair should still suggest the second copy")

    -- And equipping it scores the second point.
    local scoreOne = countBis(half)
    half.gearname_ring2 = dupRing
    local scoreTwo = countBis(half)
    eq(scoreTwo, scoreOne + 1, "equipping the second copy should score the second point")

    -- Both already worn: nothing left to suggest for that pair.
    check(getBisName(dupClass, dupSpec, "ring2", half) == nil,
          "with both copies worn the pair is exhausted")
end

if failures > 0 then
    print("bis tests FAILED: " .. failures .. " of " .. testsRun)
    os.exit(1)
end
print("bis tests passed: " .. testsRun)
