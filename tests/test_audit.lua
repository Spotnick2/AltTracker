------------------------------------------------------------
-- test_audit.lua — gear audit: link parsing, packed-field handling, the CLA
-- bad-enchant denylist, gem quality, and meta-gem activation.
--
-- Covers:
--   * Scanner's item-link parsing and the packed "ench:sockets:g1:g2:g3" field
--     it writes, including the unresolved "?" socket count.
--   * EnchantData integrity — the 136-row workbook transcription.
--   * Bad-enchant lookup with and without a slot restriction (255 / 723 / 2841
--     are the rows a flat [id] -> name map would silently lose).
--   * AltTracker.AuditCharacter end to end.
--
-- Run from the repo root with the Lua 5.1 interpreter:
--   & 'C:\Program Files (x86)\Lua\5.1\lua.exe' tests\test_audit.lua
------------------------------------------------------------

dofile("tests/wow_stubs.lua")

AltTracker = {}
AltTrackerDB = {}
AltTrackerConfig = {}

assert(loadfile("Plugins/Roster/EnchantData.lua"))()
assert(loadfile("Plugins/Roster/Audit.lua"))()

-- Scanner.lua needs the core globals it touches at load time.
assert(loadfile("Theme.lua"))()
assert(loadfile("Scanner.lua"))()

local A = AltTracker._testAudit
local S = AltTracker._testScanner
assert(A, "Audit test seam missing")
assert(S, "Scanner test seam missing")

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
        " (got " .. tostring(a) .. ", want " .. tostring(b) .. ")")
end

------------------------------------------------------------
-- 1. Item-link parsing
------------------------------------------------------------

local function mods(link)
    local e, g1, g2, g3, g4 = S.ParseItemMods(link)
    return string.format("%d/%d/%d/%d/%d", e, g1, g2, g3, g4)
end

eq(mods("|cffa335ee|Hitem:30734:2661:24028:35759:0:0:0:0:70:0|h[Spellstrike Pants]|h|r"),
   "2661/24028/35759/0/0", "parses enchant + gems out of a full coloured hyperlink")
eq(mods("item:30734:2661:24028:35759:0:0:0:0:70:0"),
   "2661/24028/35759/0/0", "parses a bare itemString")
eq(mods("|Hitem:30734::::::::70:0|h[Pants]|h"),
   "0/0/0/0/0", "empty enchant and gem fields read as 0, not nil")
eq(mods("|Hitem:30734:2661:::::-25:12345:70:0|h[Pants]|h"),
   "2661/0/0/0/0", "a negative suffix later in the string does not break the match")
eq(mods("item:30734:2661:24028:35759:32409:0:0:0:70:0:1:2:3"),
   "2661/24028/35759/32409/0", "trailing client-version fields are tolerated")
eq(mods("item:30734:0:1:2:3:4"), "0/1/2/3/4", "gem4 is captured, not silently dropped")
eq(mods(nil), "0/0/0/0/0", "nil link is handled")
eq(mods(""), "0/0/0/0/0", "empty link is handled")

------------------------------------------------------------
-- 2. PackGearMod + socket resolution
------------------------------------------------------------

WoW.items[30734] = { name = "Spellstrike Pants", quality = 4, ilvl = 141,
    itemType = "Armor", subType = "Cloth", equipLoc = "INVTYPE_LEGS",
    classID = 4, subClassID = 1, sockets = { red = 1, yellow = 1 } }
WoW.items[28963] = { name = "Warp-Spring Coil", quality = 4, ilvl = 141,
    itemType = "Armor", subType = "Miscellaneous", equipLoc = "INVTYPE_TRINKET",
    classID = 4, subClassID = 0 }   -- no sockets at all

eq(S.PackGearMod("item:30734:2661:24028:35759:0:0", 30734), "2661:2:24028:35759:0",
   "packs enchant, resolved socket count and gems")
eq(S.PackGearMod("item:28963:0:0:0:0:0", 28963), "0:0:0:0:0",
   "an item with no sockets packs a CONFIRMED zero, not '?'")
eq(S.PackGearMod("item:99999:2661:0:0:0:0", 99999), "2661:?:0:0:0",
   "an uncached item packs '?' — a false 0 would permanently hide a missing gem")
eq(S.PackGearMod("", 0), "", "empty link packs to empty")
eq(S.SocketCount(30734), 2, "socket count sums the EMPTY_SOCKET_* stats")
eq(S.SocketCount(99999), nil, "socket count is nil (not 0) on a cache miss")

------------------------------------------------------------
-- 3. ParseGearMod — including malformed peer input
------------------------------------------------------------

local function parse(packed)
    local e, sock, gems, ok = A.ParseGearMod(packed)
    return string.format("%s/%s/%d/%s", tostring(e), tostring(sock), #gems, tostring(ok))
end

eq(parse("2661:2:24028:35759:0"), "2661/2/2/true", "valid packed value")
eq(parse("0:0:0:0:0"),            "0/0/0/true",    "confirmed empty: 0 sockets, no gems")
eq(parse("2661:?:0:0:0"),         "2661/nil/0/true", "'?' yields a nil socket count but stays valid")
eq(parse(""),                     "0/nil/0/false",  "empty slot is not valid data")
eq(parse(nil),                    "0/nil/0/false",  "absent field is not valid data")

-- Peer input: anything malformed must read as unresolved, never as a clean slot.
eq(parse("2661:2:24028"),      "0/nil/0/false", "too few components rejected")
eq(parse("2661:2:1:2:3:4"),    "0/nil/0/false", "too many components rejected")
eq(parse("abc:2:0:0:0"),       "0/nil/0/false", "non-numeric enchant rejected")
eq(parse("2661:x:0:0:0"),      "0/nil/0/false", "non-numeric socket count rejected")
eq(parse("2661:9:0:0:0"),      "2661/3/0/true", "an absurd socket count is clamped to 3, not trusted")

------------------------------------------------------------
-- 4. EnchantData integrity (the hand-transcribed table)
------------------------------------------------------------

local ids, rows = 0, 0
local validSlots = { head=1, shoulder=1, chest=1, legs=1, feet=1, wrist=1,
                     hands=1, back=1, mainhand=1, offhand=1 }
for id, entry in pairs(AltTracker.BadEnchants) do
    ids = ids + 1
    check(type(id) == "number" and id > 0, "bad enchant key is a positive number: " .. tostring(id))
    if entry.any then rows = rows + 1 end
    if entry.slots then
        for slotKey, name in pairs(entry.slots) do
            rows = rows + 1
            check(validSlots[slotKey] ~= nil, "slot key '" .. tostring(slotKey) .. "' is valid (enchant " .. id .. ")")
            check(type(name) == "string" and name ~= "", "enchant " .. id .. "/" .. slotKey .. " has a name")
        end
    end
end
eq(ids, 110, "BadEnchants holds every distinct enchant id from the workbook")
eq(rows, 135, "…and every row (136 workbook rows, one exact duplicate collapsed)")

local metas = 0
for _ in pairs(AltTracker.MetaGems) do metas = metas + 1 end
eq(metas, 18, "all 18 TBC meta gems carry an activation requirement")

local excluded = 0
for _ in pairs(AltTracker.AuditExcludedItems) do excluded = excluded + 1 end
eq(excluded, 37, "all 37 excluded-gear items transcribed")

------------------------------------------------------------
-- 5. Bad-enchant lookup — the duplicate-id rows
------------------------------------------------------------

-- 255 carries BOTH an unrestricted row and three slot-restricted ones.
eq(A.BadEnchantName(255, "feet"),     "Boots - 3 Spi",   "255 resolves its feet-specific label")
eq(A.BadEnchantName(255, "wrist"),    "Bracers - 3 Spi", "255 resolves its wrist-specific label")
eq(A.BadEnchantName(255, "offhand"),  "Shield - 3 Spi",  "255 resolves its offhand-specific label")
eq(A.BadEnchantName(255, "mainhand"), "Weapon - 3 Spi",  "255 falls back to the unrestricted label")

-- 723 is the other id with both forms.
eq(A.BadEnchantName(723, "wrist"),    "Bracers - 3 Int", "723 prefers the slot-specific label")
eq(A.BadEnchantName(723, "mainhand"), "Weapon - 3 Int",  "723 falls back to the unrestricted label")

-- 2841 is restricted to five slots with no unrestricted row.
eq(A.BadEnchantName(2841, "head"), "Heavy Knothide Kit", "2841 matches head")
eq(A.BadEnchantName(2841, "feet"), "Heavy Knothide Kit", "2841 matches feet")
eq(A.BadEnchantName(2841, "back"), nil, "2841 does NOT match a slot it isn't restricted to")

eq(A.BadEnchantName(2669, "mainhand"), "Weapon - 40SP", "unrestricted weapon enchant matches")
eq(A.BadEnchantName(999999, "head"),   nil, "an unknown enchant id is not flagged")

------------------------------------------------------------
-- 6. Enchantable slots, including the offhand rule
------------------------------------------------------------

WoW.items[2822] = { name = "Shield", quality = 4, equipLoc = "INVTYPE_SHIELD", classID = 4, subClassID = 6 }
WoW.items[28188] = { name = "Offhand Sword", quality = 4, equipLoc = "INVTYPE_WEAPONOFFHAND", classID = 2, subClassID = 7 }
WoW.items[29273] = { name = "Khadgar's Knapsack", quality = 4, equipLoc = "INVTYPE_HOLDABLE", classID = 4, subClassID = 0 }

check(A.IsEnchantable("head", 30734),     "head is enchantable")
check(not A.IsEnchantable("neck", 30734), "neck is not enchantable")
check(not A.IsEnchantable("ring1", 30734), "rings are skipped (Enchanting-only in TBC)")
check(not A.IsEnchantable("ranged", 30734), "ranged is deferred, not audited")
check(A.IsEnchantable("offhand", 2822),   "a SHIELD in the offhand is enchantable")
check(A.IsEnchantable("offhand", 28188),  "an offhand WEAPON is enchantable (shield-only was wrong)")
check(not A.IsEnchantable("offhand", 29273), "a held-in-off-hand frill is NOT enchantable")
check(not A.IsEnchantable("offhand", 99999), "an uncached offhand is skipped rather than guessed at")

------------------------------------------------------------
-- 7. Gem colours and meta activation
------------------------------------------------------------

local function gem(id, quality, subClassID)
    WoW.items[id] = { name = "Gem" .. id, quality = quality, itemType = "Gem",
                      classID = 3, subClassID = subClassID }
end
gem(24028, 3, 0)   -- Red, rare
gem(35759, 3, 2)   -- Yellow, rare
gem(24033, 3, 1)   -- Blue, rare
gem(30550, 3, 3)   -- Purple, rare  (red + blue)
gem(35760, 3, 5)   -- Orange, rare  (red + yellow)
gem(23112, 1, 0)   -- Red, common
gem(24054, 2, 1)   -- Blue, uncommon
gem(25896, 3, 6)   -- Meta

local c = A.GemColorCounts({ 24028, 35759, 24033 })
eq(c.red, 1, "one red gem counted")
eq(c.blue, 1, "one blue gem counted")
eq(c.yellow, 1, "one yellow gem counted")

c = A.GemColorCounts({ 30550 })
eq(c.red, 1, "a purple gem counts as red…")
eq(c.blue, 1, "…and as blue")
eq(c.yellow, 0, "…but not as yellow")

c = A.GemColorCounts({ 35760 })
eq(c.red, 1, "an orange gem counts as red…")
eq(c.yellow, 1, "…and as yellow")

c = A.GemColorCounts({ 99999 })
eq(c.unknown, 1, "an uncached gem is counted as unknown, never guessed")

-- Minimum-count requirement: 32409 needs 2 of each colour.
check(A.MetaIsActive({ red = 2, blue = 2, yellow = 2 },
      { red = 2, blue = 2, yellow = 2, meta = 1, unknown = 0 }), "minimum-count meta active at exactly the threshold")
check(not A.MetaIsActive({ red = 2, blue = 2, yellow = 2 },
      { red = 2, blue = 1, yellow = 2, meta = 1, unknown = 0 }), "minimum-count meta inactive one short")

-- Relative requirement: 25897 needs strictly more red than blue.
check(A.MetaIsActive({ moreRedThanBlue = true },
      { red = 3, blue = 2, yellow = 0, meta = 1, unknown = 0 }), "relative meta active when red > blue")
check(not A.MetaIsActive({ moreRedThanBlue = true },
      { red = 2, blue = 2, yellow = 0, meta = 1, unknown = 0 }), "relative meta inactive when red == blue (CLA uses strict >)")
check(not A.MetaIsActive({ moreBlueThanYellow = true },
      { red = 0, blue = 1, yellow = 3, meta = 1, unknown = 0 }), "moreBlueThanYellow inactive when yellow leads")

------------------------------------------------------------
-- 8. AuditCharacter end to end
------------------------------------------------------------

local function baseChar()
    local c = { level = 70, class = "MAGE" }
    for _, slot in ipairs(A.SLOT_ORDER) do
        c["gearid_" .. slot]   = 30734
        c["gearq_" .. slot]    = 4
        c["gearname_" .. slot] = "Spellstrike Pants"
        c["gearmod_" .. slot]  = "2661:2:24028:35759:0"   -- enchanted, fully gemmed
    end
    -- Keep the paper-doll honest: slots that can't be enchanted still need ids.
    c.gearid_offhand = 28188
    c.gearid_mainhand = 28188
    return c
end

local function codes(issues)
    local seen = {}
    for _, i in ipairs(issues or {}) do seen[i.code] = (seen[i.code] or 0) + 1 end
    return seen
end

-- 8a. Absent gearmod_ must be "unavailable", never "clean".
local legacy = { level = 70, gearid_head = 30734, gearq_head = 4 }
eq(AltTracker.AuditCharacter(legacy), nil,
   "a record with no gearmod_ at all returns nil (unavailable), not an empty list")

-- 8b. A fully kitted character reports nothing.
local clean = baseChar()
local issues = AltTracker.AuditCharacter(clean)
check(issues ~= nil, "a record WITH gearmod_ returns a list")
eq(#issues, 0, "a fully enchanted, fully gemmed character has no issues")

-- 8c. Missing enchant.
local c = baseChar()
c.gearmod_legs = "0:2:24028:35759:0"
eq(codes(AltTracker.AuditCharacter(c)).noEnchant, 1, "an unenchanted enchantable slot is flagged")

-- 8d. Subpar enchant, labelled from the workbook.
c = baseChar()
c.gearmod_legs = "2745:2:24028:35759:0"   -- "Legs - Silver Thread"
issues = AltTracker.AuditCharacter(c)
eq(codes(issues).badEnchant, 1, "a denylisted enchant is flagged")
eq(issues[1].label, "Legs - Silver Thread", "…and carries the workbook's label")

-- 8e. Missing gems: one issue per empty socket.
c = baseChar()
c.gearmod_legs = "2661:2:0:0:0"
eq(codes(AltTracker.AuditCharacter(c)).noGem, 2, "two empty sockets produce two issues")

-- 8f. An unresolved socket count must suppress gem checks entirely.
c = baseChar()
c.gearmod_legs = "2661:?:0:0:0"
eq(codes(AltTracker.AuditCharacter(c)).noGem, nil,
   "'?' sockets suppress the gem check — a cache miss must not fabricate a finding")

-- 8g. Gem quality threshold.
c = baseChar()
c.gearmod_legs = "2661:2:23112:24054:0"   -- common + uncommon
local got = codes(AltTracker.AuditCharacter(c))
eq(got.commonGem, 1, "a common gem is flagged at the default Rare minimum")
eq(got.uncommonGem, 1, "an uncommon gem is flagged at the default Rare minimum")

AltTrackerConfig.minGemQuality = 0
eq(codes(AltTracker.AuditCharacter(c)).commonGem, nil, "minGemQuality 0 disables gem quality checks")
AltTrackerConfig.minGemQuality = 4
eq(codes(AltTracker.AuditCharacter(baseChar())).rareGem, 34,
   "at an Epic minimum every rare gem is flagged")
AltTrackerConfig.minGemQuality = nil

-- 8h. Empty slots.
c = baseChar()
c.gearid_head = 0
eq(codes(AltTracker.AuditCharacter(c)).noItem, 1, "an empty head slot is flagged")

c = baseChar()
c.gearid_offhand = 0
eq(codes(AltTracker.AuditCharacter(c)).noItem, nil,
   "an empty offhand is NEVER flagged — it is correct for two-hander users")

-- 8i. Level gate.
c = baseChar()
c.level = 60
eq(#AltTracker.AuditCharacter(c), 0, "a character below auditMinLevel produces no issues")
AltTrackerConfig.auditMinLevel = 60
c.gearmod_legs = "0:2:24028:35759:0"
eq(codes(AltTracker.AuditCharacter(c)).noEnchant, 1, "lowering auditMinLevel re-enables the audit")
AltTrackerConfig.auditMinLevel = nil

-- 8j. Quality floor: a levelling green with no enchant is not a finding.
c = baseChar()
c.gearq_legs = 1
c.gearmod_legs = "0:0:0:0:0"
eq(codes(AltTracker.AuditCharacter(c)).noEnchant, nil,
   "an unenchanted common-quality item is below the quality floor")

-- 8k. Excluded gear is never flagged.
c = baseChar()
c.gearid_mainhand = 19970          -- Arcanite Fishing Pole
c.gearmod_mainhand = "0:0:0:0:0"
eq(codes(AltTracker.AuditCharacter(c)).noEnchant, nil, "excluded gear is skipped entirely")

-- 8l. Meta gem activation, end to end.
c = baseChar()
for _, slot in ipairs(A.SLOT_ORDER) do c["gearmod_" .. slot] = "2661:0:0:0:0" end
c.gearmod_head = "2661:2:25896:24033:0"   -- meta 25896 needs 3 blue; only 1 present
eq(codes(AltTracker.AuditCharacter(c)).metaInactive, 1, "an unsatisfied meta gem is flagged")

c.gearmod_chest = "2661:2:24033:24033:0"  -- +2 more blue => 3 blue total
eq(codes(AltTracker.AuditCharacter(c)).metaInactive, nil, "a satisfied meta gem is not flagged")

-- 8m. Issues are ordered most-severe-first.
c = baseChar()
c.gearid_head = 0                          -- noItem, rank 1
c.gearmod_legs = "2745:2:24028:35759:0"    -- badEnchant, rank 5
issues = AltTracker.AuditCharacter(c)
eq(issues[1].code, "noItem", "the most severe issue sorts first")
eq(issues[#issues].code, "badEnchant", "the least severe sorts last")

------------------------------------------------------------
-- 9. Renderer smoke test
--
-- RosterAudit.lua builds frames, so this only checks it runs end to end
-- against the stubs without erroring and reports the right header text --
-- enough to catch a typo'd field or a nil-index on the render path.
------------------------------------------------------------

assert(loadfile("Plugins/Roster/RosterAudit.lua"))()
local RA = AltTracker.RosterAudit
check(RA ~= nil, "RosterAudit exposes its module table")

RA.BuildTab(WoW.makeFrame())

local headerText
RA.header.SetText = function(_, t) headerText = t end

RA.RenderTab(nil)
eq(headerText, "No character selected.", "no selection is reported as such")

RA.RenderTab({ level = 70 })
eq(headerText, "No gear detail synced for this character.",
   "a record without gearmod_ is reported as unsynced, NOT as clean")

RA.RenderTab(baseChar())
eq(headerText, "No issues found.", "a clean character reports no issues")

c = baseChar()
c.gearid_head = 0
RA.RenderTab(c)
eq(headerText, "1 issue", "a single issue is pluralised correctly")

c = baseChar()
c.gearid_head = 0
c.gearmod_legs = "0:2:24028:35759:0"
RA.RenderTab(c)
eq(headerText, "2 issues", "multiple issues are counted")

local y = RA.RenderTab(c)
check(y < -34, "RenderTab returns a y below the header so the scroll child sizes")

-- Badges + tooltip index
local buttons = { head = WoW.makeFrame(), legs = WoW.makeFrame(), chest = WoW.makeFrame() }
RA.ApplyBadges(c, buttons)
check(RA.bySlot.head ~= nil, "the head slot is indexed for badging")
check(RA.bySlot.legs ~= nil, "the legs slot is indexed for badging")
eq(RA.bySlot.chest, nil, "a clean slot gets no badge entry")
eq(RA.bySlot.head[1].code, "noItem", "the slot index carries the issue")

RA.ApplyBadges(baseChar(), buttons)
eq(RA.bySlot.head, nil, "re-running against a clean character clears the index")

RA.ApplyBadges(nil, buttons)
eq(next(RA.bySlot), nil, "a nil character clears the index rather than erroring")

RA.AddTooltipLines("head")   -- must not error with an empty index
eq(RA.SlotLabel("mainhand"), "Main Hand", "slot labels resolve for the fallback row name")

------------------------------------------------------------
-- Uncached gems must queue a repaint, not read as clean
--
-- The audit stays silent on a gem it cannot resolve (reporting "no gem" off a
-- cache miss would be a fabricated finding). That silence is only safe if
-- something re-runs the audit once the item lands -- otherwise the tab keeps
-- saying "No issues found" and the badges stay clear forever.
------------------------------------------------------------

AltTracker.PendingAuditItems = nil

local uncached = baseChar()
-- 88888 is never registered in WoW.items, so both GetItemInfo (quality) and
-- GetItemInfoInstant (colour) come back empty for it.
uncached.gearmod_legs = "2661:1:88888:0:0"
local uncachedIssues = AltTracker.AuditCharacter(uncached)

check(uncachedIssues ~= nil, "an uncached gem still returns a list, not nil")
eq((codes(uncachedIssues))["commonGem"], nil, "an unresolved gem is never reported as low quality")
check(AltTracker.PendingAuditItems ~= nil, "an unresolved gem creates the pending queue")
check(AltTracker.PendingAuditItems[88888], "the unresolved gem id is queued for a retry")

-- A gem that resolves cleanly must NOT be queued: a pending entry that never
-- clears would repaint the roster on every unrelated cache event.
AltTracker.PendingAuditItems = nil
AltTracker.AuditCharacter(baseChar())
check(AltTracker.PendingAuditItems == nil or next(AltTracker.PendingAuditItems) == nil,
      "fully cached gems queue nothing")

-- GemColorCounts reports which ids it could not read, so the caller can queue
-- them without a second lookup.
local cc, unresolved = A.GemColorCounts({ 24028, 99999 })
eq(cc.unknown, 1, "the unresolved gem is still counted as unknown")
eq(#unresolved, 1, "GemColorCounts returns the unresolved ids")
eq(unresolved[1], 99999, "…and they are the right ids")

------------------------------------------------------------
print(("audit tests passed: %d"):format(testsRun - failures))
if failures > 0 then
    print(("audit tests FAILED: %d of %d"):format(failures, testsRun))
    os.exit(1)
end
