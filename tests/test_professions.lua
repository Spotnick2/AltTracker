------------------------------------------------------------
-- test_professions.lua — Recipes plugin: change-detection + delta skip.
--
-- Loads the plugin under tests/wow_stubs.lua + a minimal AltTracker host stub,
-- and drives its serialize/deserialize seam. No game client.
--
--   & 'C:\Program Files (x86)\Lua\5.1\lua.exe' tests\test_professions.lua
------------------------------------------------------------

dofile("tests/wow_stubs.lua")

-- Minimal AltTracker host: capture the plugin registration + the hooks the
-- plugin calls during bootstrap and serialize.
local registered
AltTracker = {
    plugins = {},
    MEDIA_PATH = "Interface\\AddOns\\AltTracker\\Media\\",
    RegisterPlugin = function(p) registered = p; table.insert(AltTracker.plugins, p) end,
    TouchCharacter = function(guid) WoW.touched = WoW.touched or {}; WoW.touched[guid] = true end,
    ResetPeerWatermarks = function() WoW.wmReset = (WoW.wmReset or 0) + 1 end,
}
AltTrackerProfessionsDB = {}

assert(loadfile("Plugins/Professions/AltTrackerProfessions.lua"))()

-- Bootstrap is deferred via C_Timer.After (the IsLoggedIn guard). Fire it.
WoW.flushTimers()

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
check(T ~= nil and T.SerializePlayer ~= nil, "_test seam is exposed")

------------------------------------------------------------
-- Bootstrap forces a baseline (empty DB / on-demand enable)
------------------------------------------------------------
check((WoW.wmReset or 0) >= 1, "bootstrap on an empty/re-enabled plugin resets peer watermarks")

------------------------------------------------------------
-- RecipeSig detects set AND metadata changes
------------------------------------------------------------
local base = { { name = "A", itemID = 1, spellID = 5, numMade = 1, difficulty = "trivial", reagents = { { itemID = 9, count = 1 } } } }
local same = { { name = "A", itemID = 1, spellID = 5, numMade = 1, difficulty = "trivial", reagents = { { itemID = 9, count = 1 } } } }
local reagentChanged = { { name = "A", itemID = 1, spellID = 5, numMade = 1, difficulty = "trivial", reagents = { { itemID = 9, count = 2 } } } }
local setChanged = { base[1], { name = "B", itemID = 2, reagents = {} } }
eq(T.RecipeSig(base), T.RecipeSig(same), "identical recipe lists hash equal")
check(T.RecipeSig(base) ~= T.RecipeSig(reagentChanged), "a reagent-count change alters the signature")
check(T.RecipeSig(base) ~= T.RecipeSig(setChanged), "a set change alters the signature")

------------------------------------------------------------
-- Delta skip: recipesStamp vs the requester's watermark
------------------------------------------------------------
local guid = "Player-Prof-1"
AltTrackerProfessionsDB[guid] = {
    name = "Craf",
    recipes = { Alchemy = { { name = "Elixir of Testing", itemID = 111, spellID = 222,
        difficulty = "optimal", numMade = 1, reagents = { { itemID = 333, count = 2 } } } } },
    recipesStamp = 1000,
}
check(T.SerializePlayer(guid, 0)    ~= "", "full sync (sinceTS 0) serializes the recipe blob")
check(T.SerializePlayer(guid, 500)  ~= "", "recipes changed since watermark are sent")
eq(T.SerializePlayer(guid, 1000), "", "skip when recipesStamp == watermark")
eq(T.SerializePlayer(guid, 2000), "", "skip when watermark is ahead of recipesStamp")

------------------------------------------------------------
-- Round-trip: serialize on a sender, deserialize into a fresh receiver
------------------------------------------------------------
local blob = T.SerializePlayer(guid, 0)
local rguid = "Player-Prof-2"
AltTrackerProfessionsDB[rguid] = nil
T.DeserializePlayer(rguid, blob)
local rdb = AltTrackerProfessionsDB[rguid]
check(rdb and rdb.recipes and rdb.recipes.Alchemy, "receiver reconstructs the profession's recipes")
eq(rdb and rdb.recipes and rdb.recipes.Alchemy and rdb.recipes.Alchemy[1].name, "Elixir of Testing", "recipe name round-trips")
eq(rdb and rdb.recipes.Alchemy[1].reagents[1].itemID, 333, "reagent itemID round-trips (craft-cost data intact)")
eq(rdb and rdb.recipes.Alchemy[1].reagents[1].count, 2, "reagent count round-trips")

------------------------------------------------------------
-- Generic craft-cooldown capture (Professions plugin scan)
------------------------------------------------------------
WoW.now = 10000
local cguid = UnitGUID("player")   -- "Player-TEST-0001"
AltTrackerDB = { [cguid] = { guid = cguid, name = "Scanner", lastUpdate = 0 } }

-- Stub an open tradeskill window from a list of { name=, cd= } (cd seconds; 0 or
-- absent = not on cooldown). Only the fields the scan reads for cooldowns matter.
local function setTradeskill(profName, recipes)
    _G.GetTradeSkillLine        = function() return profName end
    _G.GetNumTradeSkills        = function() return #recipes end
    _G.GetTradeSkillInfo        = function(i) return recipes[i] and recipes[i].name, "optimal" end
    _G.GetTradeSkillCooldown    = function(i) return recipes[i] and recipes[i].cd or 0 end
    _G.GetTradeSkillItemLink    = function() return nil end
    _G.GetTradeSkillRecipeLink  = function() return nil end
    _G.GetTradeSkillIcon        = function() return nil end
    _G.GetTradeSkillNumMade     = function() return 1 end
    _G.GetTradeSkillNumReagents = function() return 0 end
end

WoW.touched = nil
setTradeskill("Alchemy", {
    { name = "Transmute: Primal Might", cd = 3600 },
    { name = "Transmute: Primal Fire",  cd = 3600 },   -- shares the transmute CD
    { name = "Elixir of Testing",       cd = 0 },      -- not on cooldown
})
T.ScanCurrentTradeskill()
local rec = AltTrackerDB[cguid]
eq(rec["cd_Alchemy@Transmute"], 13600, "on-CD craft stored as cd_<prof>@<label> absolute expiry")
check(rec["cd_Alchemy@Elixir of Testing"] == nil, "a recipe not on cooldown creates no field")
local nAlch = 0
for k in pairs(rec) do if type(k) == "string" and k:find("^cd_Alchemy@") then nAlch = nAlch + 1 end end
eq(nAlch, 1, "shared-CD transmute family collapses to a single entry")
check(WoW.touched and WoW.touched[cguid], "a cooldown change marks the character dirty (TouchCharacter)")

-- Re-scan while the transmute is now ready (cd 0): the field is KEPT (past expiry)
-- so the UI can show Ready and the cooldown-ready toast can still fire.
WoW.now = 20000
setTradeskill("Alchemy", {
    { name = "Transmute: Primal Might", cd = 0 },
    { name = "Elixir of Testing",       cd = 0 },
})
T.ScanCurrentTradeskill()
eq(AltTrackerDB[cguid]["cd_Alchemy@Transmute"], 13600, "a ready-but-known craft keeps its expiry (not pruned)")

-- Unlearn the transmute (absent from the skill list): its field is pruned.
setTradeskill("Alchemy", { { name = "Elixir of Testing", cd = 0 } })
T.ScanCurrentTradeskill()
check(AltTrackerDB[cguid]["cd_Alchemy@Transmute"] == nil, "an unlearned craft's cooldown field is pruned")

-- Legacy fixed-key cooldowns / known_ flags are purged on the next scan.
AltTrackerDB[cguid].cd_Mooncloth = 999999
AltTrackerDB[cguid].known_cd_Mooncloth = 1
WoW.now = 30000
setTradeskill("Tailoring", { { name = "Primal Mooncloth", cd = 7200 } })
T.ScanCurrentTradeskill()
check(AltTrackerDB[cguid].cd_Mooncloth == nil, "legacy fixed-key cooldown purged")
check(AltTrackerDB[cguid].known_cd_Mooncloth == nil, "legacy known_ flag purged")
eq(AltTrackerDB[cguid]["cd_Tailoring@Primal Mooncloth"], 37200, "cloth cooldown captured under a dynamic key")

------------------------------------------------------------
if failures == 0 then
    print("professions tests passed: " .. testsRun)
else
    print("professions tests FAILED: " .. failures .. " of " .. testsRun)
    os.exit(1)
end
