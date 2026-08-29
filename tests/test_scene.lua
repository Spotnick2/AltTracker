------------------------------------------------------------
-- test_scene.lua — RosterScene (Roster "Campsite" view) pure logic.
--
-- Covers the frame-free helpers exposed on AltTracker.RosterScene._test:
--   * SelectCamp    — filter + top-N-by-level/iLvl camp selection
--   * CoverTexCoord — aspect-fill ("cover") texcoord math
--   * CarouselSlots — hero-carousel slot assignment (what makes it turn)
--
-- The module creates no frames at load time, so it loads cleanly under the stubs.
-- Run from the repo root with the Lua 5.1 interpreter:
--   & 'C:\Program Files (x86)\Lua\5.1\lua.exe' tests\test_scene.lua
------------------------------------------------------------

dofile("tests/wow_stubs.lua")

AltTracker = {}
assert(loadfile("Plugins/Roster/RosterScene.lua"))()

local S = AltTracker.RosterScene._test
assert(S and S.SelectCamp and S.CoverTexCoord and S.CarouselSlots, "test seam not exposed")

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
    check(a == b, (msg or "values differ") ..
        " (expected " .. tostring(b) .. ", got " .. tostring(a) .. ")")
end
local function approx(a, b, msg)
    check(type(a) == "number" and math.abs(a - b) < 1e-6, (msg or "values differ") ..
        " (expected ~" .. tostring(b) .. ", got " .. tostring(a) .. ")")
end
local function names(list)
    local out = {}
    for i, c in ipairs(list) do out[i] = c.name end
    return table.concat(out, ",")
end

------------------------------------------------------------
-- SelectCamp
------------------------------------------------------------

-- Ordering: strongest first by level, then iLvl, then name. The store is a flat
-- GUID-keyed table that also contains non-character junk keys — those must be skipped.
do
    local store = {
        ["g1"] = { guid = "g1", name = "Bravo",  level = 70, ilvl = 120 },
        ["g2"] = { guid = "g2", name = "Alpha",  level = 70, ilvl = 130 }, -- higher iLvl than Bravo
        ["g3"] = { guid = "g3", name = "Charlie",level = 62, ilvl = 200 }, -- lower level, loses to L70s
        ["g4"] = { guid = "g4", name = "Delta",  level = 70, ilvl = 120 }, -- tie w/ Bravo on lvl+ilvl -> name
        config = "not-a-character",           -- junk key, no .name
        ["gx"] = 42,                          -- junk key, not a table
    }
    local camp = S.SelectCamp(store, false, 6)
    eq(#camp, 4, "SelectCamp keeps only the 4 real characters")
    -- Alpha(70,130) > Bravo(70,120)==Delta(70,120 -> name Bravo<Delta) > Charlie(62)
    eq(names(camp), "Alpha,Bravo,Delta,Charlie", "SelectCamp orders by level, then iLvl, then name")
end

-- top-N cap
do
    local store = {}
    for i = 1, 10 do
        store["g" .. i] = { guid = "g" .. i, name = "C" .. i, level = i, ilvl = i }
    end
    local camp = S.SelectCamp(store, false, 6)
    eq(#camp, 6, "SelectCamp caps at maxN")
    eq(camp[1].level, 10, "SelectCamp[1] is the highest level")
    eq(camp[6].level, 5, "SelectCamp[6] is the 6th highest level")
    eq(S.SelectCamp(store, false)[1].level, 10, "SelectCamp default maxN still returns strongest first")
    eq(#S.SelectCamp(store, false), 6, "SelectCamp default maxN is 6")
end

-- hideLow filter (mirrors BuildEntries: drop < level 58)
do
    local store = {
        ["a"] = { guid = "a", name = "Main",  level = 70, ilvl = 100 },
        ["b"] = { guid = "b", name = "Bank",  level = 30, ilvl = 1 },
        ["c"] = { guid = "c", name = "Edge",  level = 58, ilvl = 1 },
    }
    eq(#S.SelectCamp(store, true, 6), 2, "hideLow drops characters below level 58 (keeps 58+)")
    eq(#S.SelectCamp(store, false, 6), 3, "without hideLow all characters are eligible")
end

-- degenerate inputs
do
    eq(#S.SelectCamp(nil, false, 6), 0, "nil store -> empty camp")
    eq(#S.SelectCamp({}, false, 6), 0, "empty store -> empty camp")
end

------------------------------------------------------------
-- CoverTexCoord  (returns uMin, uMax, vMin, vMax)
------------------------------------------------------------

-- matching aspect -> no crop
do
    local u1, u2, v1, v2 = S.CoverTexCoord(100, 100, 512, 512)
    approx(u1, 0, "square/square uMin"); approx(u2, 1, "square/square uMax")
    approx(v1, 0, "square/square vMin"); approx(v2, 1, "square/square vMax")
end

-- tall source (512x896) into a WIDE frame -> crop vertically, keep full width
do
    local u1, u2, v1, v2 = S.CoverTexCoord(200, 100, 512, 896)
    approx(u1, 0, "tall-into-wide keeps full width uMin")
    approx(u2, 1, "tall-into-wide keeps full width uMax")
    -- pad = (1 - (512/896)/(200/100)) / 2
    local pad = (1 - (512 / 896) / (200 / 100)) * 0.5
    approx(v1, pad, "tall-into-wide crops top")
    approx(v2, 1 - pad, "tall-into-wide crops bottom (symmetric)")
    check(v1 > 0 and v2 < 1, "tall-into-wide actually crops the vertical axis")
end

-- tall source (512x896) into a TALLER frame -> crop horizontally, keep full height
do
    local u1, u2, v1, v2 = S.CoverTexCoord(100, 400, 512, 896)
    approx(v1, 0, "tall-into-taller keeps full height vMin")
    approx(v2, 1, "tall-into-taller keeps full height vMax")
    local pad = (1 - (100 / 400) / (512 / 896)) * 0.5
    approx(u1, pad, "tall-into-taller crops left")
    approx(u2, 1 - pad, "tall-into-taller crops right (symmetric)")
end

-- guards against zero/degenerate dimensions (no divide-by-zero, stays in range)
do
    local u1, u2, v1, v2 = S.CoverTexCoord(0, 0, 0, 0)
    check(u1 >= 0 and u2 <= 1 and v1 >= 0 and v2 <= 1, "degenerate dims stay within [0,1]")
end

------------------------------------------------------------
-- CarouselSlots — the carousel must TURN, not reshuffle.
--
-- Slots are the signed circular distance to the selection, so advancing shifts
-- every card by exactly one slot. The previous fan-out-by-iteration-order
-- assignment moved only two cards and left the rest frozen, which reads as two
-- figures swapping places rather than a rank rotating.
------------------------------------------------------------

local function slotList(n, sIdx)
    local out = {}
    local s = S.CarouselSlots(n, sIdx)
    for i = 1, n do out[i] = s[i] end
    return out
end

for n = 1, 8 do
    for sIdx = 1, n do
        eq(S.CarouselSlots(n, sIdx)[sIdx], 0,
           "selected character should hold slot 0 (n=" .. n .. ", sel=" .. sIdx .. ")")

        local seen, dup = {}, false
        for _, k in ipairs(slotList(n, sIdx)) do
            if seen[k] then dup = true end
            seen[k] = true
        end
        check(not dup, "slots must be unique (n=" .. n .. ", sel=" .. sIdx .. ")")
    end
end

-- THE regression: advancing the selection slides every card one slot, except the
-- single card that wraps from one end of the rank to the other.
for n = 2, 8 do
    for sIdx = 1, n do
        local nextIdx = (sIdx % n) + 1
        local before, after = S.CarouselSlots(n, sIdx), S.CarouselSlots(n, nextIdx)
        local shifted, wrapped = 0, 0
        for i = 1, n do
            if after[i] - before[i] == -1 then shifted = shifted + 1 else wrapped = wrapped + 1 end
        end
        eq(shifted, n - 1,
           "advancing should slide n-1 cards one slot (n=" .. n .. ", sel=" .. sIdx .. ")")
        eq(wrapped, 1,
           "exactly one card should wrap end-to-end (n=" .. n .. ", sel=" .. sIdx .. ")")
    end
end

------------------------------------------------------------
-- Summary
------------------------------------------------------------
if failures == 0 then
    print("scene tests passed: " .. testsRun)
else
    print("scene tests FAILED: " .. failures .. " of " .. testsRun)
    os.exit(1)
end
