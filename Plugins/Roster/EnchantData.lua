------------------------------------------------------------
-- AltTracker Roster - Enchant / gem audit reference data (TBC)
--
-- Provenance: transcribed mechanically (never by hand) from the "gear issues"
--   sheet of "WoW Classic TBC - Combat Log Analytics V1.6.0a.xlsx" (CLA).
--   Columns B/C are its "cheap or bad enchants" table; columns E/F its
--   "excluded gear" list. Regenerate with Tools/gen_enchant_data.py rather
--   than editing this file by hand.
--
-- IMPORTANT - DATA QUALITY
--   DO NOT add entries from memory or rough estimation. Every row below came
--   out of the workbook verbatim. To extend the table, extend the source
--   workbook and re-transcribe. When in doubt, omit the entry.
--
-- Schema:
--   AltTracker.BadEnchants[enchantID] = {
--       any   = "name",              -- applies to any slot (may be nil)
--       slots = { feet = "name" },   -- slot-restricted names (may be absent)
--   }
--   Lookup order is slots[slotKey] first, then any. Two enchant IDs carry BOTH
--   forms (255 and 723), and one ID can be restricted to several slots with a
--   different label each (2841 covers five), so a flat [id] = name map would
--   silently lose rows.
--
-- CLA judges enchants by denylist: a slot with no enchant is "missing", an
-- enchant listed here is "subpar", and anything else is treated as fine. That
-- means unavoidable false negatives for any weak enchant the workbook omits -
-- present these as CLA-derived advice, not authoritative truth.
--
-- TBC item data is static, so this set is closed and needs no refresh.
------------------------------------------------------------

AltTracker = AltTracker or {}

-- 136 workbook rows -> 110 distinct enchant IDs
AltTracker.BadEnchants = {
    [15] = { any = "8 Armor" },
    [16] = { any = "16 Armor" },
    [17] = { any = "24 Armor" },
    [18] = { any = "32 Armor" },
    [24] = { slots = { chest = "Chest - 5 Mana" } },
    [41] = { slots = { wrist = "Bracers - 5 HP", chest = "Chest - 5 HP" } },
    [43] = { slots = { offhand = "Shield - Iron Spike" } },
    [44] = { slots = { chest = "Chest - 10 Absorb" } },
    [63] = { slots = { chest = "Chest - 25 Absorb" } },
    [65] = { slots = { back = "Cloak - 1 Res" } },
    [66] = { slots = { wrist = "Bracers - 1 Sta", feet = "Boots - 1 Sta", offhand = "Shield - 1 Sta" } },
    [241] = { any = "Weapon - 2 Dmg" },
    [242] = { slots = { chest = "Chest - 15 HP" } },
    [246] = { slots = { chest = "Chest - 20 Mana" } },
    [247] = { slots = { feet = "Boots - 1 Agi", back = "Cloak - 1 Agi" } },
    [248] = { slots = { wrist = "Bracers - 1 Str" } },
    [254] = { slots = { chest = "Chest - 25 HP" } },
    [255] = { any = "Weapon - 3 Spi", slots = { wrist = "Bracers - 3 Spi", feet = "Boots - 3 Spi", offhand = "Shield - 3 Spi" } },
    [256] = { slots = { back = "Cloak - 5 FR" } },
    [463] = { slots = { offhand = "Shield - Mith Spike" } },
    [464] = { slots = { feet = "Boots - Mount Speed" } },
    [723] = { any = "Weapon - 3 Int", slots = { wrist = "Bracers - 3 Int" } },
    [724] = { slots = { wrist = "Bracers - 3 Sta", feet = "Boots - 3 Sta", offhand = "Shield - 3 Sta" } },
    [744] = { slots = { back = "Cloak - 20 Armor" } },
    [783] = { slots = { back = "Cloak - 10 Armor" } },
    [803] = { any = "Weapon - Fiery" },
    [805] = { any = "Weapon - 4 Dmg" },
    [823] = { slots = { wrist = "Bracers - 3 Str" } },
    [843] = { slots = { chest = "Chest - 30 Mana" } },
    [844] = { slots = { hands = "Gloves - 3 Mining" } },
    [845] = { slots = { hands = "Gloves - 3 Herb" } },
    [846] = { slots = { hands = "Gloves - 2 Fishing" } },
    [847] = { slots = { chest = "Chest - 1 Stats" } },
    [848] = { slots = { back = "Cloak - 30 Armor", offhand = "Shield - 30 Armor" } },
    [849] = { slots = { feet = "Boots - 3 Agi" } },
    [850] = { slots = { chest = "Chest - 35 HP" } },
    [851] = { slots = { wrist = "Bracers - 5 Spi", offhand = "Shield - 5 Spi" } },
    [852] = { slots = { wrist = "Bracers - 5 Sta", feet = "Boots - 5 Sta", offhand = "Shield - 5 Sta" } },
    [854] = { any = "Weapon - Elemental" },
    [856] = { slots = { wrist = "Bracers - 5 Str", hands = "Gloves - 5 Str" } },
    [857] = { slots = { chest = "Chest - 50 Mana" } },
    [865] = { slots = { hands = "Gloves - 5 Skinn" } },
    [866] = { slots = { chest = "Chest - 2 Stats" } },
    [884] = { slots = { back = "Cloak - 50 Armor" } },
    [903] = { slots = { back = "Cloak - 3 Res" } },
    [904] = { slots = { hands = "Gloves - 5 Agi", feet = "Boots - 5 Agi" } },
    [905] = { slots = { wrist = "Bracers - 5 Int" } },
    [906] = { slots = { hands = "Gloves - 5 Mining" } },
    [907] = { slots = { wrist = "Bracers - 7 Spi", offhand = "Shield - 7 Spi" } },
    [908] = { slots = { chest = "Chest - 50 HP" } },
    [909] = { slots = { hands = "Gloves - 5 Herb" } },
    [910] = { slots = { back = "Cloak - Stealth" } },
    [911] = { any = "Boots - Minor Speed" },
    [913] = { slots = { chest = "Chest - 65 Mana" } },
    [923] = { slots = { wrist = "Bracers - 3 Def" } },
    [924] = { slots = { wrist = "Bracers - 1 Def" } },
    [925] = { slots = { wrist = "Bracers - 2 Def" } },
    [927] = { slots = { wrist = "Bracers - 7 Str", hands = "Gloves - 7 Str" } },
    [928] = { slots = { chest = "Chest - 3 Stats" } },
    [929] = { slots = { wrist = "Bracers - 7 Sta", feet = "Boots - 7 Sta", offhand = "Shield - 7 Sta" } },
    [930] = { slots = { hands = "Gloves - Mount Speed" } },
    [943] = { any = "Weapon - 3 Dmg" },
    [963] = { any = "Weapon - 7 Dmg" },
    [1704] = { slots = { offhand = "Shield - Thor Spike" } },
    [1843] = { any = "40 Armor" },
    [1885] = { slots = { wrist = "Bracers - 9 Str" } },
    [1886] = { slots = { wrist = "Bracers - 9 Sta" } },
    [1887] = { slots = { hands = "Gloves - 7 Agi", feet = "Boots - 7 Agi" } },
    [1889] = { slots = { back = "Cloak - 70 Armor" } },
    [1891] = { slots = { chest = "Chest - 4 Stats" } },
    [1893] = { slots = { chest = "Chest - 100 Mana" } },
    [1896] = { any = "Weapon - 9 Dmg" },
    [1898] = { any = "Weapon - Lifesteal" },
    [1899] = { any = "Weapon - Unholy" },
    [1900] = { any = "Weapon - Crusader" },
    [1903] = { any = "Weapon - 9 Spi" },
    [1904] = { any = "Weapon - 9 Int" },
    [2443] = { any = "Weapon - 7 Frost" },
    [2463] = { slots = { back = "Cloak - 7 FR" } },
    [2503] = { any = "3 Def" },
    [2568] = { any = "Weapon - 22 Int" },
    [2583] = { slots = { legs = "Head/Legs - ZG" } },
    [2584] = { any = "Head/Legs - ZG" },
    [2585] = { any = "Head/Legs - ZG" },
    [2586] = { any = "Head/Legs - ZG" },
    [2587] = { any = "Head/Legs - ZG" },
    [2588] = { any = "Head/Legs - ZG" },
    [2589] = { any = "Head/Legs - ZG" },
    [2590] = { any = "Head/Legs - ZG" },
    [2591] = { any = "Head/Legs - ZG" },
    [2604] = { any = "Shoulder - ZG" },
    [2605] = { any = "Shoulder - ZG" },
    [2606] = { any = "Shoulder - ZG" },
    [2646] = { any = "Weapon - 25 Agi" },
    [2669] = { any = "Weapon - 40SP" },
    [2745] = { any = "Legs - Silver Thread" },
    [2747] = { any = "Legs - Mystic Thread" },
    [2792] = { any = "Knothide Kit" },
    [2841] = { slots = { head = "Heavy Knothide Kit", shoulder = "Heavy Knothide Kit", chest = "Heavy Knothide Kit", legs = "Heavy Knothide Kit", feet = "Heavy Knothide Kit" } },
    [2934] = { slots = { hands = "Gloves - Blasting" } },
    [2938] = { slots = { back = "Cloak - Spell Pen" } },
    [2977] = { any = "Shoulder - Aldor Hon" },
    [2979] = { any = "Shoulder - Aldor Hon" },
    [2981] = { any = "Shoulder - Aldor Hon" },
    [2983] = { any = "Shoulder - Aldor Hon" },
    [2990] = { any = "Shoulder - Scryer Hon" },
    [2992] = { any = "Shoulder - Scryer Hon" },
    [2994] = { any = "Shoulder - Scryer Hon" },
    [2996] = { any = "Shoulder - Scryer Hon" },
    [3010] = { any = "Legs - 40AP/10Crit" },
}

-- Slots that can carry a permanent enchant in TBC.
--
-- Rings are Enchanting-only, so CLA skips them and so do we: profession
-- eligibility is not derivable from a synced record. Ranged is deferred -
-- scopes apply only to bows/guns/crossbows, never to wands, thrown, idols,
-- librams or totems, so it needs its own subtype gate.
--
-- offhand is CONDITIONAL, resolved in Audit.lua: an offhand WEAPON takes
-- weapon enchants and a SHIELD takes shield enchants; only a held-in-
-- off-hand frill (INVTYPE_HOLDABLE) cannot be enchanted at all.
AltTracker.ENCHANTABLE_SLOTS = {
    head = true, shoulder = true, chest = true, legs = true, feet = true,
    wrist = true, hands = true, back = true, mainhand = true, offhand = true,
}

-- Items CLA never flags (fishing poles, joke/utility gear, ...).
AltTracker.AuditExcludedItems = {
    [15138] = true,  -- Onyxia Scale Cloak
    [9449] = true,  -- Manual Crowd Pummeler
    [19022] = true,  -- Nat Pagle's Extreme Angler FC-5000
    [19970] = true,  -- Arcanite Fishing Pole
    [25978] = true,  -- Seth's Graphite Fishing Pole
    [6365] = true,  -- Strong Fishing Pole
    [12225] = true,  -- Blump Family Fishing Pole
    [6367] = true,  -- Big Iron Fishing Pole
    [6366] = true,  -- Darkwood Fishing Pole
    [6256] = true,  -- Fishing Pole
    [38175] = true,  -- The Horseman's Blade
    [21864] = true,  -- Soulcloth Shoulders
    [21865] = true,  -- Soulcloth Vest
    [21868] = true,  -- Arcanoweave Robe
    [23509] = true,  -- Enchanted Adamantite Breastplate
    [23512] = true,  -- Enchanted Adamantite Leggings
    [21867] = true,  -- Arcanoweave Boots
    [23511] = true,  -- Enchanted Adamantite Boots
    [21863] = true,  -- Soulcloth Gloves
    [28301] = true,  -- Syrannis' Mystic Sheen
    [31938] = true,  -- Enigmatic Cloak
    [27449] = true,  -- Blood Knight Defender
    [29495] = true,  -- Enchanted Clefthoof Leggings
    [29489] = true,  -- Enchanted Felscale Leggings
    [29497] = true,  -- Enchanted Clefthoof Boots
    [29491] = true,  -- Enchanted Felscale Boots
    [21866] = true,  -- Arcanoweave Bracers
    [29496] = true,  -- Enchanted Clefthoof Gloves
    [29490] = true,  -- Enchanted Felscale Gloves
    [30831] = true,  -- Cloak of Arcane Evasion
    [30311] = true,  -- Warp Slicer
    [30312] = true,  -- Infinity Blade
    [30313] = true,  -- Staff of Disintegration
    [30314] = true,  -- Phaseshift Bulwark
    [30316] = true,  -- Devastation
    [30317] = true,  -- Cosmic Infuser
    [30318] = true,  -- Netherstrand Longbow
}

------------------------------------------------------------
-- Meta gem activation requirements
--
-- Ported from the metaGemActive block of the CLA script. Requirements come
-- in TWO shapes, and a single minimum-count rule would misclassify several:
--   * minimum counts  - red / blue / yellow  (">=" thresholds)
--   * relative counts - moreRedThanBlue, moreRedThanYellow,
--                       moreBlueThanYellow
-- CLA writes these as strict ">" comparisons; the minimums below are the
-- equivalent ">=" values.
------------------------------------------------------------

AltTracker.MetaGems = {
    [25890] = { red = 2, blue = 2, yellow = 2 },
    [25893] = { moreBlueThanYellow = true },
    [25894] = { red = 1, yellow = 2 },
    [25895] = { moreRedThanYellow = true },
    [25896] = { blue = 3 },
    [25897] = { moreRedThanBlue = true },
    [25898] = { blue = 5 },
    [25899] = { red = 2, blue = 2, yellow = 2 },
    [25901] = { red = 2, blue = 2, yellow = 2 },
    [28556] = { red = 1, yellow = 2 },
    [28557] = { red = 1, yellow = 2 },
    [32409] = { red = 2, blue = 2, yellow = 2 },
    [32410] = { red = 2, blue = 2, yellow = 2 },
    [32640] = { moreBlueThanYellow = true },
    [32641] = { yellow = 3 },
    [34220] = { blue = 2 },
    [35501] = { blue = 2, yellow = 1 },
    [35503] = { red = 3 },
}
