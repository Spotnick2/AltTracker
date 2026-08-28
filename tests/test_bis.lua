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
if failures > 0 then
    print("bis tests FAILED: " .. failures .. " of " .. testsRun)
    os.exit(1)
end
print("bis tests passed: " .. testsRun)
