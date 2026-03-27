AltTracker = AltTracker or {}

-- Vertical rep column helper (now with icon support)
local function rep(label, field, vertLabel, icon)
    return { label=label, field=field, width=22, align="RIGHT",
             type="rep", vertical=true, verticalLabel=vertLabel, group="rep",
             repIcon=icon }
end

-- Combined Aldor/Scryers
local function repCombo(label, field1, field2, vertLabel, icon)
    return { label=label, field=field1, field2=field2, width=22, align="RIGHT",
             type="repCombined", vertical=true, verticalLabel=vertLabel, group="rep",
             repIcon=icon }
end

-- Profession skill column
local function prof(label, skillField, maxField, icon)
    return { label=label, field=skillField, maxField=maxField, width=38,
             align="RIGHT", type="profSkill", profIcon=icon, group="prof" }
end

AltTracker.Columns = {
    -- Frozen (col 1 = Name)
    { label="Name",  field="name",  width=140, align="LEFT", type="name", group="always" },

    -- Always-visible identity
    { label="Class", field="class", width=22, align="CENTER", type="classIcon", group="always" },
    { label="Spec",  field="spec",  width=22, align="CENTER", type="specIcon",  group="always" },
    { label="Race",  field="race",  width=22, align="CENTER", type="raceIcon",  group="always" },
    { label="Lvl",   field="level", width=35, align="RIGHT",  type="number",    group="always" },
    { label="iLvl",  field="ilvl",  width=45, align="RIGHT",  type="number",    group="always" },
    { label="BiS",   field="bisCount", width=38, align="RIGHT", type="bisCount", group="always" },

    -- Gear slots (group="gear") — using colorful icons from Interface\Icons
    { label="Head",      field="gear_head",     width=32, align="RIGHT", type="gearSlot", group="gear",
      slotIcon="Interface\\Icons\\INV_Helmet_04" },
    { label="Neck",      field="gear_neck",     width=32, align="RIGHT", type="gearSlot", group="gear",
      slotIcon="Interface\\Icons\\INV_Jewelry_Amulet_06" },
    { label="Shoulder",  field="gear_shoulder", width=32, align="RIGHT", type="gearSlot", group="gear",
      slotIcon="Interface\\Icons\\INV_Shoulder_02" },
    { label="Back",      field="gear_back",     width=32, align="RIGHT", type="gearSlot", group="gear",
      slotIcon="Interface\\Icons\\INV_Misc_Cape_11" },
    { label="Chest",     field="gear_chest",    width=32, align="RIGHT", type="gearSlot", group="gear",
      slotIcon="Interface\\Icons\\INV_Chest_Chain_05" },
    { label="Wrist",     field="gear_wrist",    width=32, align="RIGHT", type="gearSlot", group="gear",
      slotIcon="Interface\\Icons\\INV_Bracer_07" },
    { label="Hands",     field="gear_hands",    width=32, align="RIGHT", type="gearSlot", group="gear",
      slotIcon="Interface\\Icons\\INV_Gauntlets_05" },
    { label="Waist",     field="gear_waist",    width=32, align="RIGHT", type="gearSlot", group="gear",
      slotIcon="Interface\\Icons\\INV_Belt_01" },
    { label="Legs",      field="gear_legs",     width=32, align="RIGHT", type="gearSlot", group="gear",
      slotIcon="Interface\\Icons\\INV_Pants_06" },
    { label="Feet",      field="gear_feet",     width=32, align="RIGHT", type="gearSlot", group="gear",
      slotIcon="Interface\\Icons\\INV_Boots_09" },
    { label="Ring 1",    field="gear_ring1",    width=32, align="RIGHT", type="gearSlot", group="gear",
      slotIcon="Interface\\Icons\\INV_Jewelry_Ring_03" },
    { label="Ring 2",    field="gear_ring2",    width=32, align="RIGHT", type="gearSlot", group="gear",
      slotIcon="Interface\\Icons\\INV_Jewelry_Ring_03" },
    { label="Trinket 1", field="gear_trinket1", width=32, align="RIGHT", type="gearSlot", group="gear",
      slotIcon="Interface\\Icons\\INV_Jewelry_Talisman_07" },
    { label="Trinket 2", field="gear_trinket2", width=32, align="RIGHT", type="gearSlot", group="gear",
      slotIcon="Interface\\Icons\\INV_Jewelry_Talisman_07" },
    { label="Main Hand", field="gear_mainhand", width=32, align="RIGHT", type="gearSlot", group="gear",
      slotIcon="Interface\\Icons\\INV_Sword_04" },
    { label="Off Hand",  field="gear_offhand",  width=32, align="RIGHT", type="gearSlot", group="gear",
      slotIcon="Interface\\Icons\\INV_Shield_04" },
    { label="Ranged",    field="gear_ranged",   width=32, align="RIGHT", type="gearSlot", group="gear",
      slotIcon="Interface\\Icons\\INV_Weapon_Bow_05" },

    -- Info (always visible — shown in name tooltip but kept as columns too)
    { label="Guild",       field="guild",       width=110, align="LEFT",  type="text",       group="always" },
    { label="Rest XP",     field="restPercent", width=50,  align="RIGHT", type="restXP",     group="always" },
    { label="Gold",        field="money",       width=150, align="RIGHT", type="money",      group="always" },
    { label="Last Online", field="lastUpdate",  width=85,  align="RIGHT", type="lastOnline", group="always" },

    -- Professions
    prof("Alchemy",       "prof_Alchemy",        "profmax_Alchemy",        "Interface\\Icons\\Trade_Alchemy"),
    prof("Blacksmithing", "prof_Blacksmithing",  "profmax_Blacksmithing",  "Interface\\Icons\\Trade_BlackSmithing"),
    prof("Enchanting",    "prof_Enchanting",     "profmax_Enchanting",     "Interface\\Icons\\Trade_Engraving"),
    prof("Engineering",   "prof_Engineering",    "profmax_Engineering",    "Interface\\Icons\\Trade_Engineering"),
    prof("Jewelcrafting", "prof_Jewelcrafting",  "profmax_Jewelcrafting",  "Interface\\Icons\\INV_Misc_Gem_01"),
    prof("Leatherworking","prof_Leatherworking", "profmax_Leatherworking", "Interface\\Icons\\Trade_LeatherWorking"),
    prof("Tailoring",     "prof_Tailoring",      "profmax_Tailoring",      "Interface\\Icons\\Trade_Tailoring"),
    prof("Herbalism",     "prof_Herbalism",      "profmax_Herbalism",      "Interface\\Icons\\Trade_Herbalism"),
    prof("Mining",        "prof_Mining",         "profmax_Mining",         "Interface\\Icons\\Trade_Mining"),
    prof("Skinning",      "prof_Skinning",       "profmax_Skinning",       "Interface\\Icons\\INV_Misc_Pelt_Wolf_01"),
    prof("Cooking",       "cooking",             "cookingMax",             "Interface\\Icons\\INV_Misc_Food_15"),
    prof("Fishing",       "fishing",             "fishingMax",             "Interface\\Icons\\Trade_Fishing"),
    prof("First Aid",     "firstAid",            "firstAidMax",            "Interface\\Icons\\Spell_Holy_SealOfSacrifice"),
    prof("Riding",        "riding",              "ridingMax",              "Interface\\Icons\\Ability_Mount_RidingHorse"),

    -- Reputations (with faction icons for headers)
    repCombo("Aldor / Scryers", "aldor", "scryer", "Al/Scr", "Interface\\Icons\\INV_Enchant_ShardBrilliantSmall"),
    rep("The Sha'tar",           "shatar",       "Sha'tr", "Interface\\Icons\\Spell_Holy_PowerWordBarrier"),
    rep("Lower City",            "lowercity",    "LowCit", "Interface\\Icons\\Spell_Shadow_DetectLesserInvisibility"),
    rep("Cenarion Expedition",   "cenarion",     "CenExp", "Interface\\Icons\\INV_Misc_Head_Dragon_Green"),
    rep("The Consortium",        "consortium",   "Consrt", "Interface\\Icons\\INV_Misc_Gem_Bloodstone_03"),
    rep("Keepers of Time",       "keepers",      "KoT",    "Interface\\Icons\\INV_Misc_Head_Dragon_Bronze"),
    rep("The Violet Eye",        "violeteye",    "VioEye", "Interface\\Icons\\INV_Jewelry_Ring_54"),
    rep("Sporeggar",             "sporeggar",    "Spore",  "Interface\\Icons\\INV_Mushroom_11"),
    rep("Honor Hold",            "honorhold",    "HonHld", "Interface\\Icons\\Spell_Holy_SealOfValor"),
    rep("Thrallmar",             "thrallmar",    "Thrall", "Interface\\Icons\\Spell_Shadow_DeathPact"),
    rep("Kurenai",               "kurenai",      "Kurnai", "Interface\\Icons\\INV_Misc_Foot_Centaur"),
    rep("The Mag'har",           "maghar",       "Mag'hr", "Interface\\Icons\\INV_Misc_Head_Orc_01"),
    rep("Ogri'la",               "ogrila",       "Ogri'l", "Interface\\Icons\\INV_Misc_Apexis_Crystal"),
    rep("Sha'tari Skyguard",     "skyguard",     "Skygrd", "Interface\\Icons\\Ability_Mount_FlyingMachine"),
    rep("Netherwing",            "netherwing",   "Netwng", "Interface\\Icons\\Ability_Mount_NetherdrakePurple"),
    rep("Ashtongue Deathsworn",  "ashtongue",    "Ashtnge","Interface\\Icons\\Spell_Shadow_SummonVoidWalker"),
    rep("The Scale of the Sands","scaleofsands", "ScalSd", "Interface\\Icons\\INV_Misc_Head_Dragon_Bronze"),
    rep("Shattered Sun",         "shatteredsun", "ShatSun","Interface\\Icons\\Spell_Holy_RighteousFury"),
}

function AltTracker.GetTotalColumnWidth()
    local total = 20
    for _, col in ipairs(AltTracker.Columns) do
        total = total + col.width
    end
    return total
end