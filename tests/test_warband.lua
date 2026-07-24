------------------------------------------------------------
-- test_warband.lua — Warband plugin: bag/bank scan, delta sync, aggregation.
--
-- Loads the plugin under tests/wow_stubs.lua + a minimal AltTracker host and a
-- controllable C_Container "world", and drives its data model (no UI, no game
-- client). Covers the correctness cases the Codex review flagged.
--
--   & 'C:\Program Files (x86)\Lua\5.1\lua.exe' tests\test_warband.lua
------------------------------------------------------------

dofile("tests/wow_stubs.lua")

------------------------------------------------------------
-- Controllable container world. The plugin captures its C_Container shim at
-- load time, so these must exist BEFORE the plugin is loaded.
--   WORLD[bag] = { size = N, [slot] = { id=, count= } }
--   API_MODE toggles the GetContainerItemInfo return shape (struct/positional).
------------------------------------------------------------
local WORLD = {}
local API_MODE = "struct"

local function setContainer(bag, size, items)
    local t = { size = size }
    for slot, it in pairs(items or {}) do t[slot] = it end
    WORLD[bag] = t
end
local function clearWorld() WORLD = {} end

C_Container = {
    GetContainerNumSlots = function(bag) local b = WORLD[bag]; return b and b.size or 0 end,
    GetContainerItemID = function(bag, slot)
        local b = WORLD[bag]; local s = b and b[slot]
        return s and s.id or nil
    end,
    GetContainerItemLink = function(bag, slot)
        local b = WORLD[bag]; local s = b and b[slot]
        if not s then return nil end
        return "|cff9d9d9d|Hitem:" .. s.id .. "::::::::70:::::::|h[Item]|h|r"
    end,
    GetContainerItemInfo = function(bag, slot)
        local b = WORLD[bag]; local s = b and b[slot]
        if not s then return nil end
        if API_MODE == "struct" then
            return { stackCount = s.count, iconFileID = 123, itemID = s.id }
        end
        return 123, s.count   -- positional: texture, count, ...
    end,
}

-- Item metadata (display-only; harmless for the data tests).
GetItemInfoInstant = function(id) return id, "Trade Goods", nil, nil, 133000, 7 end
GetItemInfo = function(id) return "Item" .. id, "|Hitem:" .. id .. "|h[Item]|h", 1 end
GetItemIcon = function() return 133000 end
ITEM_QUALITY_COLORS = setmetatable({}, { __index = function() return { r = 1, g = 1, b = 1 } end })

------------------------------------------------------------
-- Minimal AltTracker host
------------------------------------------------------------
local registered
AltTracker = {
    plugins = {},
    RegisterPlugin = function(p) registered = p; table.insert(AltTracker.plugins, p) end,
    TouchCharacter = function(guid) WoW.touched = WoW.touched or {}; WoW.touched[guid] = true end,
    ResetPeerWatermarks = function() WoW.wmReset = (WoW.wmReset or 0) + 1 end,
}
AltTrackerDB = {}
AltTrackerWarbandDB = {}

assert(loadfile("Plugins/Warband/AltTrackerWarband.lua"))()
WoW.flushTimers()   -- fire the deferred _Bootstrap -> RegisterPlugin

local GUID = "Player-TEST-0001"   -- what the stubbed UnitGUID returns

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
check(T ~= nil and T.ScanBags ~= nil, "_test seam exposed")
check((WoW.wmReset or 0) >= 1, "bootstrap on an empty DB resets peer watermarks for a full baseline")

------------------------------------------------------------
-- 1. ScanBags builds a summed {id:count} map
------------------------------------------------------------
WoW.now = 1000
AltTrackerWarbandDB[GUID] = nil
API_MODE = "struct"
setContainer(0, 4, { [1] = { id = 100, count = 5 }, [2] = { id = 100, count = 3 }, [3] = { id = 200, count = 1 } })
WoW.touched = {}
T.ScanBags()
local db = AltTrackerWarbandDB[GUID]
eq(db.bags[100], 8, "stacks of the same item are summed across slots")
eq(db.bags[200], 1, "a distinct item is captured")
check(WoW.touched[GUID], "a real inventory change touches the character (drives the delta)")

------------------------------------------------------------
-- 2. A bag rescan preserves the (stale) bank snapshot
------------------------------------------------------------
setContainer(-1, 28, { [1] = { id = 900, count = 2 } })
T.OnBankOpened()   -- sets isBankOpen, bumps gen, scans the bank immediately
eq(AltTrackerWarbandDB[GUID].bank[900], 2, "bank captured while the frame is open")
setContainer(0, 4, { [1] = { id = 100, count = 1 } })
T.ScanBags()
eq(AltTrackerWarbandDB[GUID].bank[900], 2, "a later bag rescan does NOT clobber the bank map")
T.OnBankClosed()

------------------------------------------------------------
-- 3. An unchanged rescan neither touches nor re-stamps
------------------------------------------------------------
WoW.now = 2000
setContainer(0, 4, { [1] = { id = 100, count = 1 } })
T.ScanBags()                 -- establish
local s1 = AltTrackerWarbandDB[GUID].bagsStamp
WoW.touched = {}
WoW.now = 3000
T.ScanBags()                 -- identical contents
check(next(WoW.touched) == nil, "an unchanged rescan does not touch the character")
eq(AltTrackerWarbandDB[GUID].bagsStamp, s1, "an unchanged rescan does not bump the stamp (no sync churn)")

------------------------------------------------------------
-- 4. Serialize -> Deserialize round-trip, single line (no newline)
------------------------------------------------------------
AltTrackerWarbandDB["G1"] = { bags = { [100] = 8, [200] = 1 }, bank = { [900] = 2 }, bagsStamp = 100, bankStamp = 90, stamp = 100 }
local blob = T.SerializePlayer("G1", 0)
check(not blob:find("\n"), "blob contains no newline (safe as a plugin_ line)")
AltTrackerWarbandDB["G2"] = nil
T.DeserializePlayer("G2", blob)
local d2 = AltTrackerWarbandDB["G2"]
eq(d2.bags[100], 8, "bags round-trip through the wire format")
eq(d2.bank[900], 2, "bank round-trips")
eq(d2.stamp, 100, "overall stamp round-trips")
eq(d2.bankStamp, 90, "bank stamp round-trips (for staleness display)")

------------------------------------------------------------
-- 5. gather() aggregates bags+bank across characters
------------------------------------------------------------
AltTrackerDB = {
    ["G1"] = { guid = "G1", name = "Alpha", class = "MAGE" },
    ["G2"] = { guid = "G2", name = "Bravo", class = "ROGUE" },
    ["G3"] = { guid = "G3", name = "NoInv", class = "PRIEST" },   -- no warband data
}
AltTrackerWarbandDB = {
    ["G1"] = { bags = { [100] = 8 }, bank = { [100] = 2, [200] = 5 } },
    ["G2"] = { bags = { [100] = 1 } },
}
local agg = T.gather()
eq(agg[100].total, 11, "item total sums bags+bank across alts (8 + 2 + 1)")
eq(#agg[100].holders, 2, "both holders of item 100 are listed")
eq(agg[200].total, 5, "a single-holder item totals correctly")
check(agg[300] == nil, "items nobody holds don't appear")

------------------------------------------------------------
-- 6. Delta skip: strict "<" — RESEND on equality (idempotent)
------------------------------------------------------------
AltTrackerWarbandDB["GD"] = { bags = { [1] = 1 }, bank = {}, stamp = 500 }
eq(T.SerializePlayer("GD", 501), "", "skip when stamp < sinceTS")
check(T.SerializePlayer("GD", 500) ~= "", "RESEND when stamp == sinceTS (else same-second change is lost)")
check(T.SerializePlayer("GD", 499) ~= "", "send when stamp > sinceTS")
check(T.SerializePlayer("GD", 0) ~= "", "a full sync always sends")

------------------------------------------------------------
-- 7. A large (350-item) blob round-trips intact
------------------------------------------------------------
local big = {}
for i = 1, 350 do big[1000 + i] = (i % 60) + 1 end
AltTrackerWarbandDB["GBIG"] = { bags = big, bank = {}, stamp = 700, bankStamp = 700 }
local bigBlob = T.SerializePlayer("GBIG", 0)
check(not bigBlob:find("\n"), "large blob still has no newline")
AltTrackerWarbandDB["GBIG2"] = nil
T.DeserializePlayer("GBIG2", bigBlob)
local db2 = AltTrackerWarbandDB["GBIG2"]
local ok, cnt = true, 0
for id, c in pairs(big) do if db2.bags[id] ~= c then ok = false end end
for _ in pairs(db2.bags) do cnt = cnt + 1 end
check(ok and cnt == 350, "all 350 items round-trip with correct counts")

------------------------------------------------------------
-- 8. An emptied section replaces the map (does NOT preserve stale)
------------------------------------------------------------
-- scan path: bag emptied
AltTrackerWarbandDB[GUID] = nil
clearWorld()
setContainer(0, 4, { [1] = { id = 100, count = 1 } })
T.ScanBags()
setContainer(0, 4, {})   -- now empty
T.ScanBags()
check(next(AltTrackerWarbandDB[GUID].bags) == nil, "emptying the bags replaces the map (genuine emptying honoured)")
-- deserialize path: newer empty blob clears
AltTrackerWarbandDB["GE"] = { bags = { [1] = 1 }, bank = {}, stamp = 100 }
T.DeserializePlayer("GE", "v1|s=200|kt=200|b=|k=")
check(next(AltTrackerWarbandDB["GE"].bags) == nil, "a newer empty blob clears bags")

------------------------------------------------------------
-- 9. A malformed blob does not wipe existing good data
------------------------------------------------------------
AltTrackerWarbandDB["GM"] = { bags = { [100] = 5 }, bank = {}, stamp = 100 }
T.DeserializePlayer("GM", "v1|s=200|kt=200|b=100,5;GARBAGE|k=")
eq(AltTrackerWarbandDB["GM"].bags[100], 5, "a malformed entry leaves existing data intact")
eq(AltTrackerWarbandDB["GM"].stamp, 100, "a malformed blob does not advance the stamp")

------------------------------------------------------------
-- 10. A stale/equal incoming blob does not roll back fresh local data
------------------------------------------------------------
AltTrackerWarbandDB["GS"] = { bags = { [100] = 9 }, bank = {}, stamp = 500 }
T.DeserializePlayer("GS", "v1|s=300|kt=300|b=100,1|k=")
eq(AltTrackerWarbandDB["GS"].bags[100], 9, "an older (stale relayed) blob does not roll back fresh data")
T.DeserializePlayer("GS", "v1|s=500|kt=500|b=100,1|k=")
eq(AltTrackerWarbandDB["GS"].bags[100], 9, "an equal-stamp blob does not overwrite")
T.DeserializePlayer("GS", "v1|s=600|kt=600|b=100,1|k=")
eq(AltTrackerWarbandDB["GS"].bags[100], 1, "a strictly newer blob is accepted")

------------------------------------------------------------
-- 11. Both struct and positional container-API shapes scan correctly
------------------------------------------------------------
AltTrackerWarbandDB[GUID] = nil
clearWorld()
API_MODE = "struct"
setContainer(0, 4, { [1] = { id = 100, count = 7 } })
T.ScanBags()
eq(AltTrackerWarbandDB[GUID].bags[100], 7, "struct GetContainerItemInfo (.stackCount) reads the count")
API_MODE = "flat"
setContainer(0, 4, { [1] = { id = 100, count = 4 } })
T.ScanBags()
eq(AltTrackerWarbandDB[GUID].bags[100], 4, "positional GetContainerItemInfo (2nd return) reads the count")
API_MODE = "struct"

------------------------------------------------------------
-- 12. A bank scan scheduled before close does not commit after close (gen guard)
------------------------------------------------------------
AltTrackerWarbandDB[GUID] = nil
clearWorld()
setContainer(-1, 28, { [1] = { id = 900, count = 2 } })
T.OnBankOpened()     -- commits {900=2}; also schedules a follow-up ScanBank (captures gen)
eq(AltTrackerWarbandDB[GUID].bank[900], 2, "bank scanned on open")
setContainer(-1, 28, { [1] = { id = 901, count = 9 } })   -- bank contents change
T.OnBankClosed()     -- bumps generation -> pending scheduled scan is now stale
WoW.flushTimers()    -- fire the follow-up; generation mismatch -> no commit
eq(AltTrackerWarbandDB[GUID].bank[900], 2, "post-close scheduled scan keeps the pre-close snapshot")
check(AltTrackerWarbandDB[GUID].bank[901] == nil, "the changed post-close contents are not committed")

------------------------------------------------------------
-- 13. CountItem: single-item cross-alt sum for the global tooltip hook
------------------------------------------------------------
AltTrackerDB = {
    ["G1"] = { guid = "G1", name = "Alpha", class = "MAGE" },
    ["G2"] = { guid = "G2", name = "Bravo", class = "ROGUE" },
    ["G3"] = { guid = "G3", name = "Cara",  class = "PRIEST" },
}
AltTrackerWarbandDB = {
    ["G1"] = { bags = { [55] = 4 }, bank = { [55] = 6 } },   -- 10 total, both locations
    ["G2"] = { bags = { [55] = 2 } },                        -- 2 in bags
    ["G3"] = { bags = { [999] = 1 } },                       -- doesn't hold 55
}
local total, holders = T.CountItem(55)
eq(total, 12, "CountItem sums an item across every alt's bags+bank (4+6+2)")
eq(#holders, 2, "only alts that actually hold the item are listed")
local zero = T.CountItem(12345)
eq(zero, 0, "an item nobody holds totals zero")

------------------------------------------------------------
-- 14. Keyring (-2) is scanned as carried inventory, so keys are findable
------------------------------------------------------------
WoW.now = 100000
AltTrackerWarbandDB[GUID] = nil
clearWorld()
API_MODE = "struct"
setContainer(0, 4, { [1] = { id = 100, count = 1 } })       -- a regular bag item
setContainer(-2, 4, { [1] = { id = 13699, count = 1 } })    -- a key in the keyring
T.ScanBags()
eq(AltTrackerWarbandDB[GUID].bags[13699], 1, "a key in the keyring (-2) is captured by the scan")
eq(AltTrackerWarbandDB[GUID].bags[100], 1, "a regular bag item is still captured alongside the keyring")

------------------------------------------------------------
if failures == 0 then
    print("warband tests passed: " .. testsRun)
else
    print("warband tests FAILED: " .. failures .. " of " .. testsRun)
    os.exit(1)
end
