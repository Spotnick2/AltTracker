------------------------------------------------------------
-- test_instances.lua — Raids plugin: lockout parse + cross-alt gather.
--
-- Loads the plugin under tests/wow_stubs.lua + a minimal AltTracker host
-- stub and exercises its pure read-model (no UI). No game client.
--
--   & 'C:\Program Files (x86)\Lua\5.1\lua.exe' tests\test_instances.lua
------------------------------------------------------------

dofile("tests/wow_stubs.lua")

local registered
AltTracker = {
    RegisterPlugin = function(p) registered = p end,
    -- HookRefresh only wraps this if it's a function; leave it nil here.
}
AltTrackerDB = {}

assert(loadfile("Plugins/Instances/AltTrackerInstances.lua"))()
WoW.flushTimers()   -- fire the deferred _Bootstrap -> RegisterPlugin

local testsRun, failures = 0, 0
local function check(cond, msg)
    testsRun = testsRun + 1
    if not cond then failures = failures + 1; print("  FAIL: " .. (msg or "assertion failed")) end
end
local function eq(a, b, msg)
    check(a == b, (msg or "values differ") .. " (expected " .. tostring(b) .. ", got " .. tostring(a) .. ")")
end

check(registered ~= nil, "plugin registered with AltTracker")
local T = registered and registered._test
check(T and T.parseLockout and T.gather, "_test seam exposed")

------------------------------------------------------------
-- parseLockout: unpack a packed si_ field
------------------------------------------------------------
local lk = T.parseLockout("si_Karazhan@1", "103560|7|11|10|Normal")
check(lk ~= nil, "parseLockout accepts a well-formed field")
eq(lk.name, "Karazhan", "raid name parsed")
eq(lk.diff, 1, "difficulty parsed")
eq(lk.expires, 103560, "expiry parsed")
eq(lk.prog, 7, "progress parsed")
eq(lk.total, 11, "boss total parsed")
eq(lk.size, 10, "raid size parsed")
eq(lk.diffName, "Normal", "difficulty name parsed")
check(T.parseLockout("gear_head", "50") == nil, "a non-si_ key is rejected")
-- a name with an apostrophe + spaces still round-trips through the key regex
local g = T.parseLockout("si_Gruul's Lair@1", "110000|2|2|25|Normal")
eq(g and g.name, "Gruul's Lair", "raid name with apostrophe/space parses")

------------------------------------------------------------
-- gather: union of raids across only the characters that have lockouts
------------------------------------------------------------
AltTrackerDB = {
    ["P1"] = { guid = "P1", name = "Bravo",  class = "MAGE",
               ["si_Karazhan@1"] = "103560|7|11|10|Normal",
               ["si_Gruul's Lair@1"] = "110000|2|2|25|Normal" },
    ["P2"] = { guid = "P2", name = "Alpha",  class = "ROGUE",
               ["si_Karazhan@1"] = "104000|11|11|10|Normal" },
    ["P3"] = { guid = "P3", name = "NoLock", class = "PRIEST" },   -- no si_ fields
}
local chars, raids, lookup = T.gather()
eq(#chars, 2, "only characters with a lockout are included (NoLock excluded)")
eq(chars[1].name, "Alpha", "characters sorted by name (Alpha before Bravo)")
eq(#raids, 2, "raid rows are the union across alts (Karazhan + Gruul), deduped")
check(lookup["P1"]["si_Karazhan@1"].prog == 7, "lookup maps a char+raid to its lockout")
check(lookup["P2"]["si_Gruul's Lair@1"] == nil, "a char not saved to a raid has no entry for it")

------------------------------------------------------------
if failures == 0 then
    print("instances tests passed: " .. testsRun)
else
    print("instances tests FAILED: " .. failures .. " of " .. testsRun)
    os.exit(1)
end
