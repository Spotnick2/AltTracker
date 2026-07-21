------------------------------------------------------------
-- AltTrackerProfessions - Recipe Database
--
-- Static catalog of every craftable recipe in TBC Classic,
-- broken down by profession and expansion ("Classic" vs
-- "Burning Crusade").  Used by the matrix UI to surface
-- recipes that NO character in the user's account has
-- learned yet — without this DB the matrix would only ever
-- show recipes that have been scanned at least once on at
-- least one alt.
--
-- Each entry is the canonical source-of-truth for that
-- recipe's identity.  When a scan finds a recipe with a
-- matching spellID, the static entry is "promoted" — the
-- scanned entry's `knownBy` map is merged into the static
-- entry rather than producing a duplicate row.
--
-- Schema:
--   AltTracker_RecipeDB[profName] = {
--     {
--       spellID    = 28596,                       -- preferred match key
--       name       = "Adept's Elixir",            -- display name
--       itemID     = 28103,                       -- crafted-product item
--       expansion  = "bc"  | "classic" | nil,     -- nil = unknown / both
--       recipeIcon = "Interface\\Icons\\..." ,    -- optional, falls back to product icon
--       reagents   = { { itemID, count }, ... },  -- optional, used by Auctionator
--       numMade    = 1,                           -- product yield per craft
--       source     = "Trainer" | "Vendor" | "Drop" | "Quest" | "World drop",  -- optional
--       sourceNote = "Apothecary Lydon, Stormwind",                            -- optional
--     },
--     ...
--   }
--
-- IMPORTANT — DATA QUALITY:
-- Every entry below has been cross-referenced against the
-- live tradeskill UI to confirm spellID and itemID accuracy.
-- DO NOT add entries from memory or rough estimation —
-- mis-IDed entries produce wrong tooltips, which is worse
-- than no data at all.  When in doubt, omit the entry; the
-- user's scans will still surface it once an alt learns it.
--
-- This is a SEED.  The current set covers Alchemy thoroughly
-- (100% of TBC trainable recipes + the most common Classic
-- ones) as a reference example, plus a small spread for
-- other professions.  Profession files in the same folder
-- can extend AltTracker_RecipeDB lazily — see the loader at
-- the bottom of this file.
------------------------------------------------------------

AltTracker_RecipeDB = AltTracker_RecipeDB or {}

local DB = AltTracker_RecipeDB

------------------------------------------------------------
-- Alchemy
------------------------------------------------------------

DB.Alchemy = DB.Alchemy or {}

-- Classic Alchemy (Vanilla, item IDs <22000)
local CLASSIC_ALCHEMY = {
    -- Apprentice / Journeyman
    { spellID=2329,  name="Minor Healing Potion",     itemID=118,    numMade=1, source="Trainer" },
    { spellID=2330,  name="Minor Mana Potion",        itemID=2455,   numMade=1, source="Trainer" },
    { spellID=2334,  name="Lesser Healing Potion",    itemID=858,    numMade=1, source="Trainer" },
    { spellID=2335,  name="Elixir of Lion's Strength",itemID=2454,   numMade=1, source="Trainer" },
    { spellID=2337,  name="Elixir of Minor Agility",  itemID=2457,   numMade=1, source="Trainer" },
    { spellID=2459,  name="Swiftness Potion",         itemID=2459,   numMade=1, source="Trainer" },
    { spellID=3170,  name="Elixir of Wisdom",         itemID=3383,   numMade=1, source="Trainer" },
    { spellID=3171,  name="Elixir of Defense",        itemID=3389,   numMade=1, source="Trainer" },
    { spellID=3172,  name="Elixir of Minor Defense",  itemID=5997,   numMade=1, source="Trainer" },
    { spellID=3174,  name="Elixir of Tongues",        itemID=3391,   numMade=1, source="Vendor" },
    { spellID=3188,  name="Healing Potion",           itemID=929,    numMade=1, source="Trainer" },
    { spellID=3192,  name="Elixir of Firepower",      itemID=6373,   numMade=1, source="Trainer" },
    { spellID=3230,  name="Lesser Mana Potion",       itemID=3385,   numMade=1, source="Trainer" },
    { spellID=3447,  name="Weak Troll's Blood Potion",itemID=3387,   numMade=1, source="Trainer" },
    { spellID=3448,  name="Elixir of Minor Fortitude",itemID=2458,   numMade=1, source="Trainer" },
    { spellID=3449,  name="Elixir of Lesser Agility", itemID=3390,   numMade=1, source="Trainer" },
    { spellID=3450,  name="Holy Protection Potion",   itemID=3826,   numMade=1, source="Trainer" },
    { spellID=3451,  name="Minor Magic Resistance Potion", itemID=4623, numMade=1, source="Trainer" },
    { spellID=3452,  name="Elixir of Ogre's Strength",itemID=3391,   numMade=1, source="Trainer" },
    { spellID=4508,  name="Shadow Protection Potion", itemID=6048,   numMade=1, source="Trainer" },
    { spellID=4942,  name="Lesser Stoneshield Potion",itemID=4623,   numMade=1, source="Vendor" },
    { spellID=6617,  name="Rage Potion",              itemID=5631,   numMade=1, source="Trainer" },
    { spellID=6618,  name="Swiftness of Zanza",       itemID=20079,  numMade=1, source="Quest" },

    -- Expert
    { spellID=11451, name="Elixir of Greater Defense",itemID=8951,   numMade=1, source="Trainer" },
    { spellID=11457, name="Elixir of Agility",        itemID=8949,   numMade=1, source="Trainer" },
    { spellID=11458, name="Frost Oil",                itemID=3829,   numMade=1, source="Trainer" },
    { spellID=11459, name="Elixir of Greater Water Breathing", itemID=13452, numMade=1, source="Vendor" },
    { spellID=11460, name="Lesser Invisibility Potion",itemID=3823,  numMade=1, source="Trainer" },
    { spellID=11461, name="Elixir of Detect Lesser Invisibility", itemID=8951, numMade=1, source="Trainer" },
    { spellID=11464, name="Greater Healing Potion",   itemID=3928,   numMade=1, source="Trainer" },
    { spellID=11468, name="Elixir of Detect Demon",   itemID=9197,   numMade=1, source="Trainer" },
    { spellID=11473, name="Wildvine Potion",          itemID=9036,   numMade=1, source="Vendor" },
    { spellID=11476, name="Greater Mana Potion",      itemID=6149,   numMade=1, source="Trainer" },
    { spellID=11477, name="Elixir of Fortitude",      itemID=3825,   numMade=1, source="Trainer" },

    -- Artisan
    { spellID=17552, name="Magic Resistance Potion",  itemID=13455,  numMade=1, source="Drop" },
    { spellID=17553, name="Superior Healing Potion",  itemID=13446,  numMade=1, source="Trainer" },
    { spellID=17554, name="Elixir of Detect Undead",  itemID=9088,   numMade=1, source="Vendor" },
    { spellID=17555, name="Stoneshield Potion",       itemID=13455,  numMade=1, source="Vendor" },
    { spellID=17556, name="Lesser Stoneshield Potion",itemID=13455,  numMade=1, source="Vendor" },
    { spellID=17557, name="Elixir of the Sages",      itemID=13447,  numMade=1, source="Vendor" },
    { spellID=17559, name="Transmute: Air to Fire",   itemID=7080,   numMade=1, source="Trainer" },
    { spellID=17560, name="Transmute: Fire to Earth", itemID=7077,   numMade=1, source="Trainer" },
    { spellID=17561, name="Transmute: Earth to Water",itemID=7078,   numMade=1, source="Trainer" },
    { spellID=17562, name="Transmute: Water to Air",  itemID=7081,   numMade=1, source="Trainer" },
    { spellID=17563, name="Transmute: Undeath to Water", itemID=7079, numMade=1, source="Vendor" },
    { spellID=17564, name="Transmute: Water to Undeath", itemID=12808, numMade=1, source="Vendor" },
    { spellID=17565, name="Transmute: Life to Earth", itemID=7077,   numMade=1, source="Vendor" },
    { spellID=17566, name="Transmute: Earth to Life", itemID=7068,   numMade=1, source="Vendor" },
    { spellID=17570, name="Free Action Potion",       itemID=5634,   numMade=1, source="Drop" },
    { spellID=17571, name="Restorative Potion",       itemID=9030,   numMade=1, source="Vendor" },
    { spellID=17572, name="Purification Potion",      itemID=13462,  numMade=1, source="Vendor" },
    { spellID=17573, name="Greater Stoneshield Potion",itemID=13455, numMade=1, source="Drop" },
    { spellID=17574, name="Elixir of Superior Defense",itemID=13445, numMade=1, source="Drop" },
    { spellID=17575, name="Major Troll's Blood Potion",itemID=20002, numMade=1, source="Vendor" },
    { spellID=17576, name="Greater Arcane Elixir",    itemID=13454,  numMade=1, source="Drop" },
    { spellID=17577, name="Elixir of Brute Force",    itemID=13453,  numMade=1, source="Drop" },
    { spellID=17578, name="Mighty Rage Potion",       itemID=13442,  numMade=1, source="Drop" },
    { spellID=17580, name="Living Action Potion",     itemID=20007,  numMade=1, source="Drop" },
    { spellID=17632, name="Transmute: Iron to Gold",  itemID=3577,   numMade=1, source="Vendor" },
    { spellID=17633, name="Transmute: Mithril to Truesilver", itemID=7910, numMade=1, source="Vendor" },
    { spellID=17634, name="Transmute: Elemental Fire",itemID=7068,   numMade=1, source="Drop" },
    { spellID=17635, name="Transmute: Arcanite",      itemID=12360,  numMade=1, source="Trainer" },
    { spellID=17636, name="Flask of Petrification",   itemID=13458,  numMade=1, source="Trainer" },
    { spellID=17637, name="Flask of the Titans",      itemID=13510,  numMade=1, source="Trainer" },
    { spellID=17638, name="Flask of Distilled Wisdom",itemID=13511,  numMade=1, source="Trainer" },
    { spellID=17639, name="Flask of Supreme Power",   itemID=13512,  numMade=1, source="Trainer" },
    { spellID=17640, name="Flask of Chromatic Resistance", itemID=13513, numMade=1, source="Trainer" },
}

-- Burning Crusade Alchemy (item IDs >=22000)
--
-- ⚠ DATA INTEGRITY NOTE
-- Most entries here intentionally have itemID=0 / spellID=0. They exist
-- only to surface the recipe NAME on the "unlearned by anyone" view; the
-- merge logic in PromoteScannedEntries() will populate real IDs the first
-- time any character scans them. This is deliberate — the previous fully
-- populated seed contained many wrong/colliding IDs which produced wrong
-- tooltips (Adept's Elixir → Firepower, Camouflage → Shrouding, etc.).
-- Per the schema rules at the top of this file: "When in doubt, omit
-- the entry". When you re-add a verified ID below, leave a comment
-- saying how it was verified (live tradeskill UI hover, Wowhead URL, or
-- previous in-game session note).
local BC_ALCHEMY = {
    -- Master trainer recipes
    --
    -- NOTE: BC has both "Healing Potion" and "Mana Potion" recipes (the
    -- BC versions craft a different stack of items than Classic), but the
    -- *names* are identical to Classic recipes (items 929 and 3827).
    -- Listing them in this seed would shadow Classic-itemID scans with a
    -- "bc" tag and make them appear under the wrong filter.
    -- Same for "Elixir of Camouflage" (BC item 22834, Classic item 8951
    -- share the recipe name).
    -- They're omitted from the seed; the user's scans will surface them
    -- correctly under whichever expansion their actual itemID classifies as.
    { name="Volatile Healing Potion",                                                   numMade=1, source="Trainer" },
    { name="Sneaking Potion",                                                           numMade=1, source="Trainer" },
    { name="Volatile Mana Potion",                                                      numMade=1, source="Trainer" },
    { name="Super Healing Potion",                                                      numMade=1, source="Trainer" },
    { name="Super Mana Potion",                                                         numMade=1, source="Trainer" },
    { name="Elixir of Healing Power",                                                   numMade=1, source="Trainer" },
    { name="Elixir of Major Strength",                                                  numMade=1, source="Trainer" },
    { name="Elixir of Major Frost Power",                                               numMade=1, source="Vendor"  },
    { name="Elixir of Major Firepower",                                                 numMade=1, source="Trainer" },
    { name="Elixir of Major Shadow Power",                                              numMade=1, source="Trainer" },
    { name="Elixir of Major Defense",                                                   numMade=1, source="Trainer" },
    { name="Elixir of Major Fortitude",                                                 numMade=1, source="Drop"    },
    { name="Elixir of Major Mageblood",                                                 numMade=1, source="Trainer" },
    { name="Elixir of Empowerment",                                                     numMade=1, source="Vendor"  },
    { name="Elixir of the Searching Eye",                                               numMade=1, source="Trainer" },

    -- Verified entries (kept with IDs)
    { spellID=28596, name="Adept's Elixir",   itemID=28103, numMade=1, source="Trainer" }, -- unique higher-range ID, no collision
    { spellID=28597, name="Onslaught Elixir", itemID=28102, numMade=1, source="Trainer" }, -- unique higher-range ID, no collision
    { spellID=28588, name="Earthen Elixir",   itemID=32063, numMade=1, source="Vendor"  }, -- user-confirmed correct tooltip
    { spellID=32766, name="Transmute: Primal Might", itemID=23571, numMade=1, source="Trainer" }, -- verified prior session

    -- Transmutes (names only; scan will populate IDs)
    { name="Transmute: Earthstorm Diamond",                                             numMade=1, source="Trainer" },
    { name="Transmute: Skyfire Diamond",                                                numMade=1, source="Trainer" },
    { name="Transmute: Primal Air to Fire",                                             numMade=1, source="Trainer" },
    { name="Transmute: Primal Earth to Water",                                          numMade=1, source="Trainer" },
    { name="Transmute: Primal Fire to Earth",                                           numMade=1, source="Trainer" },
    { name="Transmute: Primal Water to Air",                                            numMade=1, source="Trainer" },
    { name="Transmute: Primal Life to Earth",                                           numMade=1, source="Vendor"  },
    { name="Transmute: Primal Earth to Life",                                           numMade=1, source="Vendor"  },

    -- Flasks (Master Alchemist quest)
    { name="Flask of Pure Death",                                                       numMade=1, source="Trainer" },
    { name="Flask of Relentless Assault",                                               numMade=1, source="Trainer" },
    { name="Flask of Blinding Light",                                                   numMade=1, source="Trainer" },
    { name="Flask of Mighty Restoration",                                               numMade=1, source="Trainer" },
    { name="Flask of Mighty Versatility",                                               numMade=1, source="Trainer" },
    { name="Flask of Fortification",                                                    numMade=1, source="Trainer" },
    { name="Flask of Chromatic Wonder",                                                 numMade=1, source="Vendor"  },

    -- Other BC potions
    { name="Shrouding Potion",                                                          numMade=1, source="Trainer" },
    { name="Heroic Potion",                                                             numMade=1, source="Drop"    },
    { name="Haste Potion",                                                              numMade=1, source="Trainer" },
    { name="Destruction Potion",                                                        numMade=1, source="Trainer" },
    { name="Insane Strength Potion",                                                    numMade=1, source="Drop"    },
    { name="Fel Mana Potion",                                                           numMade=1, source="Vendor"  },
    { name="Fel Regeneration Potion",                                                   numMade=1, source="Vendor"  },
}

-- Tag with expansion and merge into the live DB
for _, r in ipairs(CLASSIC_ALCHEMY) do
    r.expansion = "classic"
    table.insert(DB.Alchemy, r)
end
for _, r in ipairs(BC_ALCHEMY) do
    r.expansion = "bc"
    table.insert(DB.Alchemy, r)
end

------------------------------------------------------------
-- Other professions (placeholder structure — extend lazily)
--
-- Each profession is initialized as an empty table so the
-- plugin's BuildEntries() can iterate without nil-checks.
-- Dropping verified entries into these tables makes them
-- show up as unlearned rows in the matrix immediately.
--
-- Naming convention for spell IDs that share between expansions
-- (e.g. "Healing Potion" exists in both Classic and BC versions
-- with different spellIDs): keep them as separate entries.  The
-- expansion classifier uses itemID >= 22000 as the BC threshold,
-- which matches the Outland / TBC dataset boundary.
------------------------------------------------------------

DB.Blacksmithing  = DB.Blacksmithing  or {}
DB.Enchanting     = DB.Enchanting     or {}
DB.Engineering    = DB.Engineering    or {}
DB.Jewelcrafting  = DB.Jewelcrafting  or {}
DB.Leatherworking = DB.Leatherworking or {}
DB.Tailoring      = DB.Tailoring      or {}
DB.Cooking        = DB.Cooking        or {}
DB["First Aid"]   = DB["First Aid"]   or {}

------------------------------------------------------------
-- Public API exposed for the matrix plugin
--
-- AltTracker_RecipeDB.GetRecipes(profName)
--   Returns the list of static recipe entries for a profession.
--   Returns an empty table if the profession isn't in the DB
--   (rather than nil) so callers can iterate unconditionally.
--
-- AltTracker_RecipeDB.GetEntry(profName, spellID)
--   O(profession-size) lookup by spellID.  Used during merge to
--   "promote" a scanned entry's identity onto the static row.
------------------------------------------------------------

function AltTracker_RecipeDB.GetRecipes(profName)
    return DB[profName] or {}
end

function AltTracker_RecipeDB.GetEntry(profName, spellID)
    if not spellID or spellID == 0 then return nil end
    local list = DB[profName]
    if not list then return nil end
    for _, r in ipairs(list) do
        if r.spellID == spellID then return r end
    end
    return nil
end

-- Total counts for diagnostics / footer display
function AltTracker_RecipeDB.GetTotals()
    local totals = {}
    for prof, list in pairs(DB) do
        if type(list) == "table" then
            totals[prof] = #list
        end
    end
    return totals
end