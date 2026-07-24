------------------------------------------------------------
-- test_instances.lua — Raids plugin: lockout parse, cross-alt gather,
-- killmask decode, and canonical (tabbed) row building.
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
AltTrackerConfig = {}

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
check(T and T.parseLockout and T.gather and T.decodeMask and T.matchRaid
      and T.columnsForView and T.buildDisplayRows and T.toggleCollapse, "_test seam exposed")

------------------------------------------------------------
-- matchRaid: bind a live lockout name to a canonical raid by substring
------------------------------------------------------------
eq(T.matchRaid("karazhan") and T.matchRaid("karazhan").apiName, "Karazhan", "exact name binds")
eq(T.matchRaid("coilfang: serpentshrine cavern") and T.matchRaid("coilfang: serpentshrine cavern").apiName,
   "Serpentshrine Cavern", "prefixed name binds by substring (the Coilfang case)")
eq(T.matchRaid("the eye") and T.matchRaid("the eye").apiName, "Tempest Keep", "alias binds (The Eye -> Tempest Keep)")
check(T.matchRaid("some unknown raid") == nil, "an unknown name binds to nothing")

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

-- CRITICAL back-compat guard: a si_boss_ mask value ("5", no pipes) must be
-- REJECTED by parseLockout, so old clients never render it as a bogus raid row.
check(T.parseLockout("si_boss_Karazhan@1", "5") == nil, "si_boss_ mask value is rejected (no pipes)")
check(T.parseLockout("si_boss_Serpentshrine Cavern@2", "42") == nil, "si_boss_ with spaces is rejected too")

------------------------------------------------------------
-- decodeMask: positional killmask -> boolean-per-boss
------------------------------------------------------------
local m0 = T.decodeMask(0, 3)
check(not m0[1] and not m0[2] and not m0[3], "mask 0 => nothing killed")
local m5 = T.decodeMask(5, 3)   -- binary 101 => bosses 1 and 3
check(m5[1] and not m5[2] and m5[3], "mask 5 => bosses 1 and 3 killed")
local mClamp = T.decodeMask(5, 2)
eq(#mClamp, 2, "decode length clamps to requested boss count")
-- local scans store a string, synced records a number: both must decode alike
local ms = T.decodeMask("5", 3)
check(ms[1] and not ms[2] and ms[3], "string mask decodes identically to number mask")

------------------------------------------------------------
-- gather: ALL tracked characters + per-char lockouts keyed by canonical name,
-- with si_boss_ masks attached
------------------------------------------------------------
AltTrackerDB = {
    ["P1"] = { guid = "P1", name = "Bravo", class = "MAGE", level = 70, ilvl = 120,
               ["si_Karazhan@1"] = "103560|7|11|10|Normal",
               ["si_boss_Karazhan@1"] = "5",                      -- bosses 1 & 3 dead
               ["si_Gruul's Lair@1"] = "110000|2|2|25|Normal" },
    ["P2"] = { guid = "P2", name = "Alpha", class = "ROGUE", level = 70, ilvl = 135,
               ["si_Karazhan@1"] = "104000|11|11|10|Normal" },
    ["P3"] = { guid = "P3", name = "NoLock", class = "PRIEST", level = 62, ilvl = 90 },
}
local allChars, lookup = T.gather()
eq(#allChars, 3, "gather returns every tracked character (including no-lockout alts)")
check(lookup["P1"]["karazhan"] and lookup["P1"]["karazhan"].prog == 7, "lookup maps a char+raid (by name) to its lockout")
eq(lookup["P1"]["karazhan"].mask, 5, "si_boss_ killmask attached to the matching lockout")
check(lookup["P3"] == nil, "a char with no lockouts has no lookup entry")
check(lookup["P2"]["gruul's lair"] == nil, "a char not saved to a raid has no entry for it")

------------------------------------------------------------
-- columnsForView: level-gated filler columns, ranked by level then ilvl
------------------------------------------------------------
local cols = T.columnsForView(allChars, lookup)
eq(#cols, 3, "all level-60+ characters are columns (P3@62 included as a filler)")
eq(cols[1].name, "Alpha", "ranked by ilvl within level (Alpha 135 before Bravo 120)")
eq(cols[3].name, "NoLock", "the level-62 alt ranks last")

------------------------------------------------------------
-- buildDisplayRows: collapsible expansion groups (BC first), Other trailer
------------------------------------------------------------
AltTrackerDB = {
    -- the SSC lockout uses the game's prefixed name — it must still bind to the
    -- canonical Serpentshrine Cavern row, NOT spill into an Other row.
    ["P1"] = { guid = "P1", name = "Bravo", class = "MAGE", level = 70,
               ["si_Coilfang: Serpentshrine Cavern@2"] = "200000|4|6|25|Normal",
               ["si_Some Unknown Raid@1"] = "210000|1|3|25|Normal" },
}
local _, look2 = T.gather()
check(look2["P1"]["serpentshrine cavern"] ~= nil, "prefixed SSC lockout keyed under its canonical name")

-- Ensure a known collapse state for this test (both groups expanded).
if T.isCollapsed("bc") then T.toggleCollapse("bc") end
if T.isCollapsed("vanilla") then T.toggleCollapse("vanilla") end

local rows = T.buildDisplayRows(look2)
check(rows[1].isGroup and rows[1].label == "Burning Crusade", "latest expansion (BC) group is on top")
eq(rows[2].raid.apiName, "Karazhan", "BC group opens with Karazhan (progression order)")
eq(rows[10].raid.apiName, "Sunwell Plateau", "BC group ends with Sunwell Plateau (9 raids)")
check(rows[11].isGroup and rows[11].label == "Classic", "Classic group follows the 9 BC raids")
eq(rows[12].raid.apiName, "Molten Core", "Classic group opens with Molten Core")
-- After the 7 Classic raids comes the Other group for the unknown lockout.
local otherHdr = rows[11 + 7 + 1]
check(otherHdr and otherHdr.isGroup and otherHdr.label == "Other", "unrecognised lockout gets an Other group")

-- Collapsing hides a group's raid rows but keeps its header.
T.toggleCollapse("bc")
local collapsed = T.buildDisplayRows(look2)
check(collapsed[1].isGroup and collapsed[1].label == "Burning Crusade", "collapsed BC header still shown")
check(collapsed[2].isGroup and collapsed[2].label == "Classic", "no BC raid rows when collapsed")
T.toggleCollapse("bc")  -- restore

------------------------------------------------------------
if failures == 0 then
    print("instances tests passed: " .. testsRun)
else
    print("instances tests FAILED: " .. failures .. " of " .. testsRun)
    os.exit(1)
end
