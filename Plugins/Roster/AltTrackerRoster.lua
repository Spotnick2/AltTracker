if type(AltTrackerRosterDB) ~= "table" then
    AltTrackerRosterDB = {}
end
if type(AltTrackerAltsDB) == "table" and next(AltTrackerRosterDB) == nil then
    AltTrackerRosterDB = AltTrackerAltsDB
end
AltTrackerAltsDB = AltTrackerRosterDB

local ADDON_ID = "alts" -- keep stable plugin id for compatibility with existing sidebar state
local AT_ALTS = {}
AT_ALTS.isActive = false

local panel
local selectorPanel
local selectorScroll
local selectorContent
local tabStripFrame
local detailPanel
local centerPanel
local statsPanel
local footerBar

local footerLeft
local footerMid
local footerRight

local rowButtons = {}
local visibleEntries = {}
local gearButtons = {}
local tabButtons = {}
local tabFrames = {}
local tabScrollFrames = {}

local centerClassIcon
local centerNameText
local centerMetaText
local centerGuildText
local centerRaceText
local centerSummaryText
local centerLastSeenText
local centerILvlBadgeValue
local centerGSBadgeValue
local centerModelHost
local centerModelFrame
local centerRenderFrame
local centerRenderTexture
local centerModelStatusText
local centerIdentityPanel
local modelDebugFrame
local modelDebugEdit
local modelDisplayProbeFrame

local statsNameText
local statsMetaText
local statsGuildText
local statsILvlText
local statsGSText

local charRows = {}
local repRows = {}
local profRows = {}
local cooldownRows = {}
local charNoDataText
local repNoDataText
local profNoDataText
local profCooldownHeader

local selectedGuid
local selectedChar
local RenderSelector

local SELECTOR_ROW_H = 32
local SELECTOR_W = 230
local RIGHT_PANEL_W = 360
local PANEL_PAD = 4
local DETAIL_BOTTOM_PAD = 24

local CENTER_PANEL_GAP = 1
local CENTER_IDENTITY_INSET_X = 64
local CENTER_IDENTITY_TOP_Y = 12
local CENTER_IDENTITY_BOTTOM_Y = 342

local GEAR_SLOT_SIZE = 40
local GEAR_SLOT_SPACING = 48
local GEAR_COLUMN_X = 10
local GEAR_TOP_Y = 12
local GEAR_BOTTOM_Y = 390
local GEAR_BOTTOM_SPACING = 44

local MODEL_FACE = 0.18
local MODEL_Z_OFFSET = -0.04
local MODEL_CAM_DEFAULT = 1.08
local MODEL_CAM_LARGE = 1.18
local MODEL_CAM_TAUREN = 1.22
local RENDER_BASE_PATH = "Interface\\AddOns\\AltTracker\\Media\\CharacterRenders\\"
local renderLayout = {
    defaultSourceWidth = 512,
    defaultSourceHeight = 896,
    sourceWidth = 512,
    sourceHeight = 896,
    mode = "cover/fullPanel",
    baseUMin = 0,
    baseUMax = 1,
    baseVMin = 0,
    baseVMax = 1,
}
renderLayout.HERO_ANIM_ENABLED = true
renderLayout.HERO_ANIM_DURATION = 1.15
renderLayout.HERO_ANIM_START_SCALE = 1.06
renderLayout.HERO_ANIM_END_SCALE = 1.00
renderLayout.HERO_ANIM_START_ALPHA = 0.72
renderLayout.HERO_ANIM_END_ALPHA = 1.00

local PREVIEW_MODE_LIVE_MODEL = "liveModelMode"
local PREVIEW_MODE_STATIC_RENDER = "staticRenderMode"
local PREVIEW_MODE_OFFLINE_CARD = "offlineCardMode"

local renderTextureProbeCache = {}

local TAB_HEIGHT = 26
local TAB_STRIP_Y = -88
local TAB_HOST_Y = -121

local STAT_ROW_H = 18
local STAT_ROW_STEP = 20
local STAT_SECTION_HEADER_GAP = 14
local STAT_SECTION_GAP = 8

local GOLD_ICON_SM = "|TInterface\\MoneyFrame\\UI-GoldIcon:13:13:2:0|t"

local CLASS_DISPLAY = {
    WARRIOR="Warrior", PALADIN="Paladin", HUNTER="Hunter", ROGUE="Rogue",
    PRIEST="Priest", SHAMAN="Shaman", MAGE="Mage", WARLOCK="Warlock",
    DRUID="Druid", DEATHKNIGHT="Death Knight",
}

local CLASS_ICON_NAME = {
    WARRIOR="Warrior", PALADIN="Paladin", HUNTER="Hunter", ROGUE="Rogue",
    PRIEST="Priest", SHAMAN="Shaman", MAGE="Mage", WARLOCK="Warlock",
    DRUID="Druid", DEATHKNIGHT="DeathKnight",
}

local RACE_DISPLAY = {
    Human="Human", Dwarf="Dwarf", Gnome="Gnome", NightElf="Night Elf",
    Draenei="Draenei", Orc="Orc", Troll="Troll", Tauren="Tauren",
    Scourge="Undead", BloodElf="Blood Elf",
}
local RACE_FACTION = {
    Human = "Alliance", Dwarf = "Alliance", Gnome = "Alliance", NightElf = "Alliance", Draenei = "Alliance",
    Orc = "Horde", Troll = "Horde", Tauren = "Horde", Scourge = "Horde", BloodElf = "Horde",
}
local FACTION_COLOR = {
    Alliance = "ff4c8dff",
    Horde = "ffff4d4d",
}

local REP_FIELDS = {
    { label="The Aldor", field="aldor" },
    { label="The Scryers", field="scryer" },
    { label="The Sha'tar", field="shatar" },
    { label="Lower City", field="lowercity" },
    { label="Cenarion Expedition", field="cenarion" },
    { label="The Consortium", field="consortium" },
    { label="Keepers of Time", field="keepers" },
    { label="The Violet Eye", field="violeteye" },
    { label="Sporeggar", field="sporeggar" },
    { label="Honor Hold", field="honorhold" },
    { label="Thrallmar", field="thrallmar" },
    { label="Kurenai", field="kurenai" },
    { label="The Mag'har", field="maghar" },
    { label="Ogri'la", field="ogrila" },
    { label="Sha'tari Skyguard", field="skyguard" },
    { label="Netherwing", field="netherwing" },
    { label="Ashtongue Deathsworn", field="ashtongue" },
    { label="The Scale of the Sands", field="scaleofsands" },
    { label="Shattered Sun", field="shatteredsun" },
}

local PROF_FIELDS = {
    { label="Alchemy",       field="prof_Alchemy",       maxField="profmax_Alchemy" },
    { label="Blacksmithing", field="prof_Blacksmithing", maxField="profmax_Blacksmithing" },
    { label="Enchanting",    field="prof_Enchanting",    maxField="profmax_Enchanting" },
    { label="Engineering",   field="prof_Engineering",   maxField="profmax_Engineering" },
    { label="Jewelcrafting", field="prof_Jewelcrafting", maxField="profmax_Jewelcrafting" },
    { label="Leatherworking",field="prof_Leatherworking",maxField="profmax_Leatherworking" },
    { label="Tailoring",     field="prof_Tailoring",     maxField="profmax_Tailoring" },
    { label="Herbalism",     field="prof_Herbalism",     maxField="profmax_Herbalism" },
    { label="Mining",        field="prof_Mining",        maxField="profmax_Mining" },
    { label="Skinning",      field="prof_Skinning",      maxField="profmax_Skinning" },
    { label="Cooking",       field="cooking",            maxField="cookingMax" },
    { label="Fishing",       field="fishing",            maxField="fishingMax" },
    { label="First Aid",     field="firstAid",           maxField="firstAidMax" },
    { label="Riding",        field="riding",             maxField="ridingMax" },
}

-- Craft cooldowns are no longer a fixed list: the Professions plugin captures
-- them generically as dynamic cd_<prof>@<label> fields on the character record,
-- and the professions tab renders whatever it finds into a pool of rows.
local COOLDOWN_ROW_POOL = 16   -- max distinct cooldowns shown at once (plenty for TBC)

local SLOT_LABELS = {
    head="Head", neck="Neck", shoulder="Shoulder", back="Back", chest="Chest", wrist="Wrist", hands="Hands",
    waist="Waist", legs="Legs", feet="Feet", ring1="Ring 1", ring2="Ring 2", trinket1="Trinket 1",
    trinket2="Trinket 2", mainhand="Main Hand", offhand="Off Hand", ranged="Ranged",
}

local SLOT_SLUGS = {
    head="head", neck="neck", shoulder="shoulders", back="back", chest="chest", wrist="wrists", hands="hands",
    waist="waist", legs="legs", feet="feet", ring1="ring1", ring2="ring2", trinket1="trinket1",
    trinket2="trinket2", mainhand="mainhand", offhand="offhand", ranged="ranged",
}

local GEAR_LEFT = { "head", "neck", "shoulder", "back", "chest", "wrist", "hands" }
local GEAR_RIGHT = { "waist", "legs", "feet", "ring1", "ring2", "trinket1", "trinket2" }
local GEAR_BOTTOM = { "mainhand", "offhand", "ranged" }
local MODEL_SLOT_ORDER = {
    "head", "shoulder", "back", "chest", "wrist", "hands", "waist", "legs", "feet",
    "mainhand", "offhand", "ranged",
}
local MODEL_RACE_ID = {
    Human = 1, Orc = 2, Dwarf = 3, NightElf = 4, Scourge = 5,
    Tauren = 6, Gnome = 7, Troll = 8, BloodElf = 10, Draenei = 11,
}
local MODEL_RACE_TOKEN_BY_ID = {
    [1] = "Human", [2] = "Orc", [3] = "Dwarf", [4] = "NightElf", [5] = "Scourge",
    [6] = "Tauren", [7] = "Gnome", [8] = "Troll", [10] = "BloodElf", [11] = "Draenei",
}
local MODEL_RACE_ALIASES = {
    human = "Human",
    orc = "Orc",
    dwarf = "Dwarf",
    nightelf = "NightElf",
    ["night elf"] = "NightElf",
    scourge = "Scourge",
    undead = "Scourge",
    forsaken = "Scourge",
    tauren = "Tauren",
    gnome = "Gnome",
    troll = "Troll",
    bloodelf = "BloodElf",
    ["blood elf"] = "BloodElf",
    draenei = "Draenei",
}
local CLIENT_INTERFACE_VERSION = (type(GetBuildInfo) == "function" and tonumber((select(4, GetBuildInfo())))) or nil
local CLIENT_WOW_PROJECT_ID = tonumber(WOW_PROJECT_ID) or WOW_PROJECT_ID
local IS_TBC_CLASSIC_CLIENT = (type(CLIENT_INTERFACE_VERSION) == "number" and CLIENT_INTERFACE_VERSION < 30000)
    or (type(WOW_PROJECT_BURNING_CRUSADE_CLASSIC) == "number" and WOW_PROJECT_ID == WOW_PROJECT_BURNING_CRUSADE_CLASSIC)
local CLIENT_MODEL_VERDICT = IS_TBC_CLASSIC_CLIENT and "tbc-classic-no-offline-render" or "prime-with-player-supported"

-- Generic offline mannequin mapping (race/gender approximation, not exact customization).
-- Fill additional entries over time as textured + gear-compatible IDs are validated.
local OFFLINE_MANNEQUIN_BY_RACE_GENDER = {
    Human    = { Male = false, Female = false },
    Orc      = { Male = false, Female = false },
    Dwarf    = { Male = false, Female = false },
    NightElf = { Male = false, Female = false },
    Scourge  = { Male = false, Female = false },
    Tauren   = { Male = { kind = "creature", id = 59 }, Female = false },
    Gnome    = { Male = false, Female = false },
    Troll    = { Male = false, Female = false },
    BloodElf = { Male = { kind = "creature", id = 15476 }, Female = false },
    Draenei  = { Male = false, Female = false },
}
local KNOWN_SILHOUETTE_DISPLAY_IDS = {
    [59] = true,   -- Tauren male on this client currently resolves as white silhouette
}

local CHAR_STAT_GROUPS = {
    {
        header = "Status",
        defs = {
            { label="Gold",       key="money",       kind="money",   allowZero=true },
            { label="Rested XP",  key="restPercent", kind="percent0",allowZero=true },
            { label="XP Progress",key="xpPercent",   kind="percent0",allowZero=true },
            { label="Last Online",key="lastUpdate",  kind="lastseen",allowZero=true },
        },
    },
    {
        header = "Resources",
        defs = {
            { label="Health",   key="stat_hp",    kind="int" },
            { label="Mana",     key="stat_mana",  kind="int" },
            { label="Armor",    key="stat_armor", kind="int" },
        },
    },
    {
        header = "Attributes",
        defs = {
            { label="Strength",   key="stat_str", kind="int" },
            { label="Agility",    key="stat_agi", kind="int" },
            { label="Stamina",    key="stat_sta", kind="int" },
            { label="Intellect",  key="stat_int", kind="int" },
            { label="Spirit",     key="stat_spi", kind="int" },
        },
    },
    {
        header = "Combat",
        defs = {
            { label="Attack Power", key="stat_ap",         kind="int" },
            { label="Spell Power",  key="stat_sp",         kind="int" },
            { label="Melee Crit",   key="stat_crit",       kind="percent2" },
            { label="Hit Chance",   key="stat_hitpct",     kind="percent2" },
            { label="Haste",        key="stat_haste",      kind="percent2" },
            { label="Defense",      key="stat_defense",    kind="int" },
            { label="Resilience",   key="stat_resilience", kind="int" },
        },
    },
}

local function ClassIconPath(classToken)
    local iconName = CLASS_ICON_NAME[(classToken or ""):upper()]
    if not iconName then
        return "Interface\\Icons\\INV_Misc_QuestionMark"
    end
    return "Interface\\Icons\\ClassIcon_" .. iconName
end

local function GetCharacterStore()
    if type(AltTrackerDB) ~= "table" then
        return {}
    end
    if type(AltTrackerDB.characters) == "table" then
        return AltTrackerDB.characters
    end
    return AltTrackerDB
end

local function GetUIState()
    AltTrackerRosterDB._ui = AltTrackerRosterDB._ui or {}
    local ui = AltTrackerRosterDB._ui
    ui.collapsed = ui.collapsed or {}
    ui.activeTab = ui.activeTab or "character"
    return ui
end

local function NumberText(value)
    if value == nil then return "-" end
    value = tonumber(value) or 0
    if BreakUpLargeNumbers then
        return BreakUpLargeNumbers(math.floor(value + 0.5))
    end
    return tostring(math.floor(value + 0.5))
end

local function MoneyText(copper)
    if copper == nil then return "-" end
    copper = tonumber(copper) or 0
    local gold = math.floor(copper / 10000)
    local silver = math.floor((copper % 10000) / 100)
    local c = copper % 100
    return string.format("%dg %ds %dc", gold, silver, c)
end

local function LastSeenText(ts)
    ts = tonumber(ts) or 0
    if ts <= 0 then return "Unknown" end
    local delta = math.max(0, time() - ts)
    if delta < 60 then return "Just now" end
    if delta < 3600 then return string.format("%dm ago", math.floor(delta / 60)) end
    if delta < 86400 then return string.format("%dh ago", math.floor(delta / 3600)) end
    if delta < 86400 * 30 then return string.format("%dd ago", math.floor(delta / 86400)) end
    return date("%Y-%m-%d", ts)
end

local function ItemIDFromLink(link)
    if type(link) ~= "string" then return 0 end
    local id = link:match("item:(%d+)")
    return tonumber(id) or 0
end

local function GetGearItemID(char, slotKey)
    if not char then return 0 end
    local id = tonumber(char["gearid_" .. slotKey]) or 0
    if id > 0 then return id end
    return ItemIDFromLink(char["gearlink_" .. slotKey])
end

local function DurationText(sec)
    sec = tonumber(sec) or 0
    if sec <= 0 then return "Ready" end
    local d = math.floor(sec / 86400)
    local h = math.floor((sec % 86400) / 3600)
    local m = math.floor((sec % 3600) / 60)
    if d > 0 then return string.format("%dd %dh", d, h) end
    if h > 0 then return string.format("%dh %dm", h, m) end
    return string.format("%dm", m)
end

local function StandingInfo(standing)
    local labels = {
        [1] = { "Hated",      0.80, 0.20, 0.20 },
        [2] = { "Hostile",    0.95, 0.35, 0.20 },
        [3] = { "Unfriendly", 1.00, 0.50, 0.20 },
        [4] = { "Neutral",    1.00, 1.00, 1.00 },
        [5] = { "Friendly",   0.45, 0.90, 0.45 },
        [6] = { "Honored",    0.20, 1.00, 0.20 },
        [7] = { "Revered",    0.00, 1.00, 0.85 },
        [8] = { "Exalted",    0.00, 1.00, 1.00 },
    }
    return labels[standing]
end

local function GetClassColor(classToken)
    if AltTracker and AltTracker.GetClassRGB then
        return AltTracker.GetClassRGB(classToken)
    end
    return 0.8, 0.8, 0.8
end

local function GetFactionFromChar(char)
    if not char then return nil end
    local value = char.faction
    if type(value) == "string" then
        local lowered = value:lower()
        if lowered == "horde" then return "Horde" end
        if lowered == "alliance" then return "Alliance" end
    end
    return RACE_FACTION[char.race]
end

local function GuildFactionLine(char)
    if not char then return "" end
    local guild = (char.guild and char.guild ~= "") and ("<" .. char.guild .. ">") or "No guild"
    local realm = (char.realm and char.realm ~= "") and char.realm or "Unknown Realm"
    local faction = GetFactionFromChar(char)
    if not faction then
        return string.format("%s - %s", guild, realm)
    end
    local color = FACTION_COLOR[faction] or "ffffffff"
    return string.format("%s - %s |c%s%s|r", guild, realm, color, faction)
end

-- GearScore engine (adapted from TitanGearScore / GearScoreLite formula)
local GS_BRACKET_SIZE
do
    local _, _, _, tocVersion = GetBuildInfo()
    tocVersion = tonumber(tocVersion) or 0
    if tocVersion >= 30000 then
        GS_BRACKET_SIZE = 1000
    elseif tocVersion >= 20000 then
        GS_BRACKET_SIZE = 400
    else
        GS_BRACKET_SIZE = 200
    end
end

local GS_FORMULA = {
    A = {
        [4] = { A = 91.4500, B = 0.6500 },
        [3] = { A = 81.3750, B = 0.8125 },
        [2] = { A = 73.0000, B = 1.0000 },
    },
    B = {
        [4] = { A = 26.0000, B = 1.2000 },
        [3] = { A =  0.7500, B = 1.8000 },
        [2] = { A =  8.0000, B = 2.0000 },
        [1] = { A =  0.0000, B = 2.2500 },
    },
    C = {
        [4] = { A = 0.2500, B = 1.6275 },
    },
}

-- Slot modifier keyed by AltTracker slot names
local GS_SLOT_MOD = {
    head     = 1.0000, neck     = 0.5625, shoulder = 0.7500, back    = 0.5625,
    chest    = 1.0000, wrist    = 0.5625, hands    = 0.7500, waist   = 0.7500,
    legs     = 1.0000, feet     = 0.7500, ring1    = 0.5625, ring2   = 0.5625,
    trinket1 = 0.5625, trinket2 = 0.5625, mainhand = 1.0000, offhand = 1.0000,
    ranged   = 0.3164,
}

local GS_GRADIENT = {
    { 0,                     0.62, 0.62, 0.62 },
    { GS_BRACKET_SIZE,       1.00, 1.00, 1.00 },
    { GS_BRACKET_SIZE * 2,   0.12, 1.00, 0.00 },
    { GS_BRACKET_SIZE * 3,   0.00, 0.44, 0.87 },
    { GS_BRACKET_SIZE * 4,   0.64, 0.21, 0.93 },
    { GS_BRACKET_SIZE * 5,   1.00, 0.50, 0.00 },
}

local function GS_GetBarGradient(score)
    score = score or 0
    if score <= 0 then return GS_GRADIENT[1][2], GS_GRADIENT[1][3], GS_GRADIENT[1][4] end
    for i = 2, #GS_GRADIENT do
        if score <= GS_GRADIENT[i][1] then
            local prev, curr = GS_GRADIENT[i - 1], GS_GRADIENT[i]
            local t = (score - prev[1]) / (curr[1] - prev[1])
            return prev[2] + (curr[2] - prev[2]) * t,
                   prev[3] + (curr[3] - prev[3]) * t,
                   prev[4] + (curr[4] - prev[4]) * t
        end
    end
    local last = GS_GRADIENT[#GS_GRADIENT]
    return last[2], last[3], last[4]
end

function AT_ALTS.IlvlToColor(ilvl)
    local function lerp(c1, c2, t)
        t = math.max(0, math.min(1, t))
        return {
            r = c1.r + (c2.r - c1.r) * t,
            g = c1.g + (c2.g - c1.g) * t,
            b = c1.b + (c2.b - c1.b) * t,
        }
    end
    local GREY = { r=0.62, g=0.62, b=0.62 }
    local WHITE = { r=1.00, g=1.00, b=1.00 }
    local GREEN = { r=0.12, g=1.00, b=0.00 }
    local BLUE = { r=0.00, g=0.44, b=0.87 }
    local PURPLE_LOW = { r=0.47, g=0.20, b=0.73 }
    local PURPLE_HIGH = { r=0.78, g=0.30, b=1.00 }
    local CEILING, POOR, COMMON, UNCOMMON, RARE, EPIC = 164, 60, 80, 100, 115, 125

    ilvl = tonumber(ilvl) or 0
    if ilvl >= CEILING then return PURPLE_HIGH
    elseif ilvl >= EPIC then return lerp(PURPLE_LOW, PURPLE_HIGH, (ilvl - EPIC) / (CEILING - EPIC))
    elseif ilvl >= RARE then return lerp(BLUE, PURPLE_LOW, (ilvl - RARE) / (EPIC - RARE))
    elseif ilvl >= UNCOMMON then return lerp(GREEN, BLUE, (ilvl - UNCOMMON) / (RARE - UNCOMMON))
    elseif ilvl >= COMMON then return lerp(WHITE, GREEN, (ilvl - COMMON) / (UNCOMMON - COMMON))
    elseif ilvl >= POOR then return lerp(GREY, WHITE, (ilvl - POOR) / (COMMON - POOR))
    else return GREY end
end

local function GS_ScoreSlot(ilvl, quality, slotMod)
    if not ilvl or ilvl <= 0 then return 0 end
    if not slotMod or slotMod <= 0 then return 0 end
    local ItemRarity = quality or 0
    local QualityScale = 1
    if ItemRarity == 5 then
        QualityScale = 1.3; ItemRarity = 4
    elseif ItemRarity <= 1 then
        return 0
    end
    local Table
    if     ilvl < 100 and ItemRarity == 4 then Table = GS_FORMULA.C
    elseif ilvl < 168 and ItemRarity == 4 then Table = GS_FORMULA.B
    elseif ilvl < 148 and ItemRarity == 3 then Table = GS_FORMULA.B
    elseif ilvl < 138 and ItemRarity == 2 then Table = GS_FORMULA.B
    elseif ilvl <= 120                     then Table = GS_FORMULA.B
    else                                        Table = GS_FORMULA.A
    end
    if ItemRarity >= 2 and ItemRarity <= 4 and Table[ItemRarity] then
        local gs = math.floor(((ilvl - Table[ItemRarity].A) / Table[ItemRarity].B) * slotMod * 1.8618 * QualityScale)
        return gs < 0 and 0 or gs
    end
    return 0
end

local ALL_GEAR_SLOTS = {
    "head","neck","shoulder","back","chest","wrist","hands",
    "waist","legs","feet","ring1","ring2","trinket1","trinket2",
    "mainhand","offhand","ranged",
}

local function ComputeCharGS(char)
    if not char then return 0 end
    local total = 0
    for _, slotKey in ipairs(ALL_GEAR_SLOTS) do
        local ilvl    = tonumber(char["gear_"  .. slotKey]) or 0
        local quality = tonumber(char["gearq_" .. slotKey]) or 0
        local slotMod = GS_SLOT_MOD[slotKey] or 0
        total = total + GS_ScoreSlot(ilvl, quality, slotMod)
    end
    return math.floor(total)
end

local function SortCharacters(a, b)
    local realmA = a.realm or "Unknown"
    local realmB = b.realm or "Unknown"
    if realmA ~= realmB then return realmA < realmB end

    local accA = (a.account and tostring(a.account) ~= "" and tostring(a.account)) or "Default"
    local accB = (b.account and tostring(b.account) ~= "" and tostring(b.account)) or "Default"
    if accA ~= accB then return accA < accB end

    local lA = a.level or 0
    local lB = b.level or 0
    if lA ~= lB then return lA > lB end

    local iA = a.ilvl or 0
    local iB = b.ilvl or 0
    if iA ~= iB then return iA > iB end

    return (a.name or "") < (b.name or "")
end

local function BuildEntries()
    wipe(visibleEntries)

    local ui = GetUIState()
    local hideLow = AltTrackerConfig and AltTrackerConfig.hideLow

    local chars = {}
    for _, char in next, GetCharacterStore() do
        if type(char) == "table" and char.name then
            if not hideLow or (char.level or 0) >= 58 then
                chars[#chars + 1] = char
            end
        end
    end
    table.sort(chars, SortCharacters)

    local grouped = {}
    local orderedGroups = {}
    for _, char in ipairs(chars) do
        local realm = char.realm or "Unknown"
        local account = (char.account and tostring(char.account) ~= "" and tostring(char.account)) or "Default"
        local key = realm .. "||" .. account
        local g = grouped[key]
        if not g then
            g = { key = key, realm = realm, account = account, chars = {} }
            grouped[key] = g
            orderedGroups[#orderedGroups + 1] = g
        end
        g.chars[#g.chars + 1] = char
    end

    for _, g in ipairs(orderedGroups) do
        g.count = #g.chars
        visibleEntries[#visibleEntries + 1] = { kind = "group", group = g }
        if not ui.collapsed[g.key] then
            for _, char in ipairs(g.chars) do
                visibleEntries[#visibleEntries + 1] = { kind = "char", data = char, group = g }
            end
        end
    end

    selectedGuid = AltTrackerRosterDB.selectedGuid
    selectedChar = nil
    if selectedGuid then
        for _, char in ipairs(chars) do
            if char.guid == selectedGuid then
                selectedChar = char
                break
            end
        end
    end
    if not selectedChar and chars[1] then
        selectedChar = chars[1]
        selectedGuid = selectedChar.guid
        AltTrackerRosterDB.selectedGuid = selectedGuid
    end
end

local function EnsureSelectorRow(i)
    if rowButtons[i] then return rowButtons[i] end

    local row = CreateFrame("Button", nil, selectorContent, "BackdropTemplate")
    row:SetHeight(SELECTOR_ROW_H)
    row:SetPoint("TOPLEFT", selectorContent, "TOPLEFT", 0, -((i - 1) * SELECTOR_ROW_H))
    row:SetPoint("TOPRIGHT", selectorContent, "TOPRIGHT", -2, -((i - 1) * SELECTOR_ROW_H))

    AltTracker.ApplyBGOnly(row, AltTracker.C.BG_ROW_ODD[1], AltTracker.C.BG_ROW_ODD[2], AltTracker.C.BG_ROW_ODD[3], 1)

    row.sel = row:CreateTexture(nil, "OVERLAY")
    row.sel:SetWidth(3)
    row.sel:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
    row.sel:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0)
    row.sel:Hide()

    row.groupAccent = row:CreateTexture(nil, "OVERLAY")
    row.groupAccent:SetWidth(2)
    row.groupAccent:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
    row.groupAccent:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0)
    row.groupAccent:Hide()

    row.classIcon = row:CreateTexture(nil, "ARTWORK")
    row.classIcon:SetSize(20, 20)
    row.classIcon:SetPoint("LEFT", row, "LEFT", 6, 0)

    row.toggle = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    row.toggle:SetPoint("LEFT", row, "LEFT", 8, 0)
    row.toggle:SetTextColor(unpack(AltTracker.C.TEXT_BRIGHT))

    row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    row.name:SetPoint("TOPLEFT", row, "TOPLEFT", 34, -5)
    row.name:SetPoint("RIGHT", row, "RIGHT", -60, 0)
    row.name:SetJustifyH("LEFT")
    row.name:SetWordWrap(false)
    if row.name.SetMaxLines then
        row.name:SetMaxLines(1)
    end

    row.sub = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.sub:SetPoint("TOPLEFT", row.name, "BOTTOMLEFT", 0, -2)
    row.sub:SetPoint("RIGHT", row, "RIGHT", -60, 0)
    row.sub:SetJustifyH("LEFT")
    row.sub:SetTextColor(unpack(AltTracker.C.TEXT_DIM))
    row.sub:SetWordWrap(false)
    if row.sub.SetMaxLines then
        row.sub:SetMaxLines(1)
    end

    row.ilvl = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.ilvl:SetPoint("RIGHT", row, "RIGHT", -8, 0)
    row.ilvl:SetJustifyH("RIGHT")
    row.ilvl:SetTextColor(unpack(AltTracker.C.TEXT_NORM))

    row.sep = row:CreateTexture(nil, "ARTWORK")
    row.sep:SetHeight(1)
    row.sep:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0)
    row.sep:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0, 0)
    row.sep:SetColorTexture(unpack(AltTracker.C.SEP))

    row:SetScript("OnClick", function(self)
        local entry = self.entry
        if not entry then return end

        if entry.kind == "group" then
            local ui = GetUIState()
            local key = entry.group.key
            ui.collapsed[key] = not ui.collapsed[key] or nil
            AT_ALTS.Refresh()
            return
        end

        selectedGuid = entry.data.guid
        AltTrackerRosterDB.selectedGuid = selectedGuid
        AT_ALTS.Refresh()
    end)
    row:SetScript("OnEnter", function(self)
        self.isHovered = true
        RenderSelector()
    end)
    row:SetScript("OnLeave", function(self)
        self.isHovered = false
        RenderSelector()
    end)
    row.isHovered = false

    rowButtons[i] = row
    return row
end

RenderSelector = function()
    local ar, ag, ab = AltTracker.GetAccentRGB()
    local ui = GetUIState()

    for i, entry in ipairs(visibleEntries) do
        local row = EnsureSelectorRow(i)
        row.entry = entry

        if entry.kind == "group" then
            local g = entry.group
            row.classIcon:Hide()
            row.toggle:Show()
            row.groupAccent:Show()
            row.groupAccent:SetColorTexture(ar, ag, ab, 0.85)
            row.toggle:SetText(ui.collapsed[g.key] and "+" or "-")
            row.name:ClearAllPoints()
            row.name:SetPoint("LEFT", row, "LEFT", 26, 0)
            row.name:SetPoint("RIGHT", row, "RIGHT", -55, 0)
            row.sub:ClearAllPoints()
            row.sub:Hide()
            row.name:SetText(g.realm .. " |cffaaaaaa(" .. g.account .. ")|r")
            row.name:SetTextColor(unpack(AltTracker.C.TEXT_BRIGHT))
            row.ilvl:Show()
            row.ilvl:SetText(string.format("%d chars", g.count or 0))
            row.ilvl:SetTextColor(unpack(AltTracker.C.TEXT_DIM))
            row.sel:Hide()
            if row.isHovered then
                row:SetBackdropColor(AltTracker.C.BG_GROUP[1], AltTracker.C.BG_GROUP[2], AltTracker.C.BG_GROUP[3], 1)
                row.name:SetTextColor(unpack(AltTracker.C.TEXT_BRIGHT))
            else
                row:SetBackdropColor(AltTracker.C.BG_GROUP[1], AltTracker.C.BG_GROUP[2], AltTracker.C.BG_GROUP[3], 0.90)
                row.name:SetTextColor(unpack(AltTracker.C.TEXT_BRIGHT))
            end
        else
            local char = entry.data
            local classToken = (char.class or ""):upper()
            local className = CLASS_DISPLAY[classToken] or (char.class or "Unknown")
            local r, g, b = GetClassColor(classToken)

            row.toggle:Hide()
            row.groupAccent:Hide()
            row.classIcon:Show()
            row.classIcon:SetTexture(ClassIconPath(classToken))
            row.classIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            row.name:ClearAllPoints()
            row.name:SetPoint("TOPLEFT", row, "TOPLEFT", 34, -5)
            row.name:SetPoint("RIGHT", row, "RIGHT", -60, 0)
            row.sub:ClearAllPoints()
            row.sub:SetPoint("TOPLEFT", row.name, "BOTTOMLEFT", 0, -2)
            row.sub:SetPoint("RIGHT", row, "RIGHT", -60, 0)
            row.sub:Show()
            row.name:SetTextColor(unpack(AltTracker.C.TEXT_BRIGHT))
            row.name:SetText((AltTracker.ClassColor and AltTracker.ClassColor(classToken) or "") .. (char.name or "") .. "|r")
            row.sub:SetText((char.level or 0) .. " " .. className)
            row.ilvl:Show()
            if char.ilvl and char.ilvl > 0 then
                local c = AT_ALTS.IlvlToColor(char.ilvl)
                row.ilvl:SetTextColor(c.r, c.g, c.b)
                row.ilvl:SetText(string.format("iLvl %.1f", char.ilvl))
            else
                row.ilvl:SetTextColor(unpack(AltTracker.C.TEXT_DIM))
                row.ilvl:SetText("iLvl -")
            end

            row:SetBackdropColor(r * 0.20, g * 0.20, b * 0.20, 0.28)
            if char.guid == selectedGuid then
                row.sel:SetColorTexture(ar, ag, ab, 1)
                row.sel:Show()
                if row.isHovered then
                    row:SetBackdropColor(r * 0.26, g * 0.26, b * 0.26, 0.48)
                else
                    row:SetBackdropColor(r * 0.24, g * 0.24, b * 0.24, 0.42)
                end
            else
                row.sel:Hide()
                if row.isHovered then
                    row:SetBackdropColor(r * 0.24, g * 0.24, b * 0.24, 0.36)
                end
            end
        end

        row:Show()
    end

    for i = #visibleEntries + 1, #rowButtons do
        rowButtons[i].entry = nil
        rowButtons[i].isHovered = false
        rowButtons[i]:Hide()
    end

    if selectorScroll and selectorContent then
        selectorContent:SetWidth(math.max(1, selectorScroll:GetWidth()))
    end
    selectorContent:SetHeight(math.max(selectorScroll:GetHeight(), #visibleEntries * SELECTOR_ROW_H + 2))
end

local function CreateGearButton(parent, slotKey)
    local btn = CreateFrame("Button", nil, parent, "BackdropTemplate")
    btn:SetSize(GEAR_SLOT_SIZE, GEAR_SLOT_SIZE)
    btn:SetFrameStrata(parent:GetFrameStrata() or "MEDIUM")
    btn:SetFrameLevel((parent:GetFrameLevel() or 1) + 30)
    AltTracker.ApplyBackdrop(btn, 0.08, 0.08, 0.08, 1)

    btn.icon = btn:CreateTexture(nil, "ARTWORK")
    btn.icon:SetPoint("TOPLEFT", btn, "TOPLEFT", 2, -2)
    btn.icon:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -2, 2)
    btn.icon:SetTexture("Interface\\Buttons\\WHITE8X8")
    btn.icon:SetTexCoord(0, 1, 0, 1)
    btn.icon:SetVertexColor(0.12, 0.12, 0.12, 1)

    btn.emptyText = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    btn.emptyText:SetPoint("CENTER", btn, "CENTER", 0, 0)
    btn.emptyText:SetJustifyH("CENTER")
    btn.emptyText:SetTextColor(unpack(AltTracker.C.TEXT_DIM))
    btn.emptyText:SetText(SLOT_LABELS[slotKey] or slotKey)

    btn.ilvl = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    btn.ilvl:SetPoint("TOP", btn, "BOTTOM", 0, 1)
    btn.ilvl:SetTextColor(unpack(AltTracker.C.TEXT_DIM))
    btn.ilvl:SetText("")

    btn.slotKey = slotKey

    btn:SetScript("OnEnter", function(self)
        local char = self._char
        if not char then return end
        local key = self.slotKey
        local link = char["gearlink_" .. key]
        local itemID = GetGearItemID(char, key)
        local name = char["gearname_" .. key]
        local ilvl = char["gear_" .. key]

        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:ClearLines()
        GameTooltip:AddLine(SLOT_LABELS[key] or key, 1, 1, 1)
        if link and link ~= "" then
            GameTooltip:SetHyperlink(link)
        elseif itemID > 0 then
            local itemName, itemLink = GetItemInfo(itemID)
            if itemLink then
                GameTooltip:SetHyperlink(itemLink)
            else
                GameTooltip:AddLine(itemName or ("Item ID: " .. itemID), 0.9, 0.9, 0.9)
                GameTooltip:AddLine("Item link not cached on this client", 0.65, 0.65, 0.65)
            end
        else
            if name and name ~= "" then
                GameTooltip:AddLine(name, 0.9, 0.9, 0.9)
            else
                GameTooltip:AddLine("No saved item data", 0.7, 0.7, 0.7)
            end
            if ilvl and ilvl > 0 then
                GameTooltip:AddLine("iLvl " .. ilvl, 0, 0.85, 1)
            end
        end
        GameTooltip:Show()
    end)

    btn:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    return btn
end

local function SetGearButtonEmpty(btn, slotKey)
    local slug = SLOT_SLUGS[slotKey]
    local icon = slug and AltTracker.GetGearIconPath and AltTracker.GetGearIconPath(slug) or nil
    if icon then
        btn.icon:SetTexture(icon)
        btn.icon:SetTexCoord(0, 1, 0, 1)
        btn.icon:SetVertexColor(0.55, 0.55, 0.55, 0.35)
    else
        btn.icon:SetTexture("Interface\\Buttons\\WHITE8X8")
        btn.icon:SetTexCoord(0, 1, 0, 1)
        btn.icon:SetVertexColor(0.12, 0.12, 0.12, 1)
    end
    btn.emptyText:SetText(SLOT_LABELS[slotKey] or slotKey)
    btn.emptyText:Show()
    btn.ilvl:SetText("")
    btn.ilvl:SetTextColor(unpack(AltTracker.C.TEXT_DIM))
    btn:SetBackdropBorderColor(unpack(AltTracker.C.SEP))
end

local function UpdateGearButtons(char)
    for slotKey, btn in pairs(gearButtons) do
        btn._char = char
        if not char then
            SetGearButtonEmpty(btn, slotKey)
        else
            local link = char["gearlink_" .. slotKey]
            local itemID = GetGearItemID(char, slotKey)
            local name = char["gearname_" .. slotKey]
            local quality = tonumber(char["gearq_" .. slotKey]) or 0
            local ilvl = tonumber(char["gear_" .. slotKey]) or 0
            local hasItemData = (link and link ~= "") or itemID > 0 or (name and name ~= "") or ilvl > 0

            local icon
            if link and link ~= "" then
                icon = GetItemIcon(link)
            elseif itemID > 0 then
                icon = GetItemIcon(itemID)
            elseif name and name ~= "" then
                icon = GetItemIcon(name)
            end

            if icon then
                btn.icon:SetTexture(icon)
                btn.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
                btn.icon:SetVertexColor(1, 1, 1, 1)
                btn.emptyText:Hide()
            elseif hasItemData then
                local slug = SLOT_SLUGS[slotKey]
                local fallback = slug and AltTracker.GetGearIconPath and AltTracker.GetGearIconPath(slug) or "Interface\\Buttons\\WHITE8X8"
                btn.icon:SetTexture(fallback)
                btn.icon:SetTexCoord(0, 1, 0, 1)
                btn.icon:SetVertexColor(0.9, 0.9, 0.9, 0.7)
                btn.emptyText:Hide()
            else
                SetGearButtonEmpty(btn, slotKey)
            end

            if hasItemData and ilvl > 0 then
                btn.ilvl:SetText(ilvl)
                local syntheticScore = math.max(0, (ilvl - 60) * 20)
                local ir, ig, ib = GS_GetBarGradient(syntheticScore)
                btn.ilvl:SetTextColor(ir, ig, ib)
            elseif hasItemData then
                btn.ilvl:SetText("")
                btn.ilvl:SetTextColor(unpack(AltTracker.C.TEXT_DIM))
            end

            if hasItemData and quality > 0 and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality] then
                local qc = ITEM_QUALITY_COLORS[quality]
                btn:SetBackdropBorderColor(qc.r, qc.g, qc.b, 1)
            elseif hasItemData then
                btn:SetBackdropBorderColor(unpack(AltTracker.C.SEP))
            end
        end
    end
end

local function SetCenterText(char)
    local fallbackIcon = ClassIconPath("WARRIOR")
    if not char then
        centerClassIcon:SetTexture(fallbackIcon)
        centerClassIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        centerNameText:SetText("No character selected")
        centerMetaText:SetText("")
        centerGuildText:SetText("")
        centerRaceText:SetText("")
        centerSummaryText:SetText("Select a character from the left list.")
        centerLastSeenText:SetText("Offline viewer uses last saved AltTracker data.")
        if centerILvlBadgeValue then centerILvlBadgeValue:SetText("-") end
        if centerGSBadgeValue then centerGSBadgeValue:SetText("-"); centerGSBadgeValue:SetTextColor(0.95, 0.95, 0.95) end
        return
    end

    local classToken = (char.class or ""):upper()
    local className = CLASS_DISPLAY[classToken] or (char.class or "Unknown")
    local raceName = RACE_DISPLAY[char.race] or (char.race or "Unknown")
    local genderText = (char.gender == "Female" or char.gender == "Male") and char.gender or nil
    local spec = (char.spec and char.spec ~= "") and char.spec or "Unknown Spec"
    local guildLine = GuildFactionLine(char)
    local rest = (char.restPercent ~= nil) and (tostring(math.floor(tonumber(char.restPercent) or 0)) .. "%") or "-"
    local gs = ComputeCharGS(char)

    centerClassIcon:SetTexture(ClassIconPath(classToken))
    centerClassIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    centerNameText:SetText((AltTracker.ClassColor and AltTracker.ClassColor(classToken) or "") .. (char.name or "") .. "|r")
    centerMetaText:SetText(string.format("Level %d %s %s", char.level or 0, spec, className))
    centerGuildText:SetText(guildLine)
    centerRaceText:SetText(genderText and (raceName .. " - " .. genderText) or raceName)
    centerSummaryText:SetText(string.format("Gold: %s   Rested: %s", MoneyText(char.money), rest))
    centerLastSeenText:SetText("Last online: " .. LastSeenText(char.lastUpdate))

    if centerILvlBadgeValue then
        if char.ilvl and char.ilvl > 0 then
            centerILvlBadgeValue:SetText(string.format("%.1f", char.ilvl))
        else
            centerILvlBadgeValue:SetText("-")
        end
    end
    if centerGSBadgeValue then
        if gs > 0 then
            local r, g, b = GS_GetBarGradient(gs)
            centerGSBadgeValue:SetText(tostring(gs))
            centerGSBadgeValue:SetTextColor(r, g, b)
        else
            centerGSBadgeValue:SetText("-")
            centerGSBadgeValue:SetTextColor(0.95, 0.95, 0.95)
        end
    end
end

local function SetCenterModelStatus(text, r, g, b)
    if not centerModelStatusText then return end
    if not (AltTrackerRosterDB and AltTrackerRosterDB._debugModelStatus) then
        centerModelStatusText:SetText("")
        centerModelStatusText:Hide()
        if modelDebugFrame and modelDebugFrame:IsShown() then
            modelDebugFrame:Hide()
        end
        return
    end
    centerModelStatusText:SetText(text or "")
    if text and text ~= "" then
        centerModelStatusText:SetTextColor(r or AltTracker.C.TEXT_DIM[1], g or AltTracker.C.TEXT_DIM[2], b or AltTracker.C.TEXT_DIM[3])
        centerModelStatusText:Show()
    else
        centerModelStatusText:Hide()
    end
end

local function DebugModelEnabled()
    return AltTrackerRosterDB and AltTrackerRosterDB._debugModelStatus
end

local function EnsureModelDebugWindow()
    if modelDebugFrame and modelDebugEdit then
        return
    end

    modelDebugFrame = CreateFrame("Frame", "AltTrackerRosterDebugFrame", UIParent, "BackdropTemplate")
    modelDebugFrame:SetSize(860, 460)
    modelDebugFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    modelDebugFrame:SetFrameStrata("DIALOG")
    modelDebugFrame:SetMovable(true)
    modelDebugFrame:SetClampedToScreen(true)
    modelDebugFrame:EnableMouse(true)

    if AltTracker and AltTracker.ApplyBackdrop and AltTracker.C then
        AltTracker.ApplyBackdrop(modelDebugFrame, AltTracker.C.BG_MAIN[1], AltTracker.C.BG_MAIN[2], AltTracker.C.BG_MAIN[3], 1)
    else
        modelDebugFrame:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            edgeSize = 1,
        })
        modelDebugFrame:SetBackdropColor(0.1, 0.1, 0.1, 0.95)
        modelDebugFrame:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)
    end

    local title = modelDebugFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", modelDebugFrame, "TOPLEFT", 12, -10)
    title:SetPoint("TOPRIGHT", modelDebugFrame, "TOPRIGHT", -96, -10)
    title:SetJustifyH("LEFT")
    title:SetText("AltTracker Roster - Preview Debug")

    local hint = modelDebugFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    hint:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
    if AltTracker and AltTracker.C and AltTracker.C.TEXT_DIM then
        hint:SetTextColor(unpack(AltTracker.C.TEXT_DIM))
    else
        hint:SetTextColor(0.7, 0.7, 0.7)
    end
    hint:SetText("Copy from this box instead of chat spam.")

    local close = CreateFrame("Button", nil, modelDebugFrame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", modelDebugFrame, "TOPRIGHT", -2, -2)

    local function SelectAllDebugText()
        if not modelDebugEdit then return end
        modelDebugEdit:SetFocus()
        modelDebugEdit:HighlightText(0, -1)
        modelDebugEdit:SetCursorPosition(0)
    end

    local copyBtn = CreateFrame("Button", nil, modelDebugFrame, "UIPanelButtonTemplate")
    copyBtn:SetSize(56, 20)
    copyBtn:SetPoint("TOPRIGHT", modelDebugFrame, "TOPRIGHT", -36, -10)
    copyBtn:SetText("Copy")
    copyBtn:SetScript("OnClick", function()
        SelectAllDebugText()
    end)

    local dragHandle = CreateFrame("Frame", nil, modelDebugFrame)
    dragHandle:SetPoint("TOPLEFT", modelDebugFrame, "TOPLEFT", 0, 0)
    dragHandle:SetPoint("TOPRIGHT", modelDebugFrame, "TOPRIGHT", -96, 0)
    dragHandle:SetHeight(40)
    dragHandle:EnableMouse(true)
    dragHandle:RegisterForDrag("LeftButton")
    dragHandle:SetScript("OnDragStart", function()
        if modelDebugFrame then modelDebugFrame:StartMoving() end
    end)
    dragHandle:SetScript("OnDragStop", function()
        if modelDebugFrame then modelDebugFrame:StopMovingOrSizing() end
    end)

    local scroll = CreateFrame("ScrollFrame", nil, modelDebugFrame, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", modelDebugFrame, "TOPLEFT", 12, -44)
    scroll:SetPoint("BOTTOMRIGHT", modelDebugFrame, "BOTTOMRIGHT", -30, 12)

    modelDebugEdit = CreateFrame("EditBox", nil, scroll)
    modelDebugEdit:SetMultiLine(true)
    modelDebugEdit:SetAutoFocus(false)
    modelDebugEdit:SetFontObject(ChatFontNormal or GameFontHighlightSmall)
    modelDebugEdit:SetWidth(790)
    modelDebugEdit:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
        if modelDebugFrame then modelDebugFrame:Hide() end
    end)
    modelDebugEdit:SetScript("OnEditFocusGained", function(self)
        self:HighlightText(0, -1)
    end)
    modelDebugEdit:SetScript("OnMouseUp", function()
        SelectAllDebugText()
    end)
    modelDebugEdit:SetScript("OnTextChanged", function(self)
        local contentHeight = 1
        if type(self.GetTextHeight) == "function" then
            local ok, value = pcall(self.GetTextHeight, self)
            if ok and type(value) == "number" then
                contentHeight = value
            end
        elseif type(self.GetStringHeight) == "function" then
            local ok, value = pcall(self.GetStringHeight, self)
            if ok and type(value) == "number" then
                contentHeight = value
            end
        elseif type(self.GetFontString) == "function" then
            local fs = self:GetFontString()
            if fs and type(fs.GetStringHeight) == "function" then
                local ok, value = pcall(fs.GetStringHeight, fs)
                if ok and type(value) == "number" then
                    contentHeight = value
                end
            end
        end
        self:SetHeight(math.max(1, contentHeight + 20))
    end)
    modelDebugEdit:SetText("")
    scroll:SetScrollChild(modelDebugEdit)

    modelDebugFrame:Hide()
end

local function PushModelDebugWindow(msg)
    if not DebugModelEnabled() then return end
    EnsureModelDebugWindow()
    if not modelDebugEdit then return end

    local stamp = date("%H:%M:%S")
    local payload = string.format("[%s] %s", stamp, msg or "")
    modelDebugEdit:SetText(payload)
    modelDebugFrame:Show()
    modelDebugEdit:SetFocus()
    modelDebugEdit:HighlightText(0, -1)
    modelDebugEdit:SetCursorPosition(0)
end

local function GetCharacterKeyParts(char)
    local realmRaw = (char and char.realm and tostring(char.realm):gsub("^%s+", ""):gsub("%s+$", "") ~= "")
        and tostring(char.realm):gsub("^%s+", ""):gsub("%s+$", "") or "Unknown"
    local accountRaw = (char and char.account and tostring(char.account):gsub("^%s+", ""):gsub("%s+$", "") ~= "")
        and tostring(char.account):gsub("^%s+", ""):gsub("%s+$", "") or "Default"
    local nameRaw = (char and char.name and tostring(char.name):gsub("^%s+", ""):gsub("%s+$", "") ~= "")
        and tostring(char.name):gsub("^%s+", ""):gsub("%s+$", "") or "NoName"
    return realmRaw, accountRaw, nameRaw
end

local function BuildManifestLookupKey(char)
    local realmRaw, accountRaw, nameRaw = GetCharacterKeyParts(char)
    return realmRaw .. ":" .. accountRaw .. ":" .. nameRaw
end

local function NormalizeManifestImagePath(imagePath)
    if type(imagePath) ~= "string" or imagePath == "" then
        return nil
    end
    if imagePath:find("^Interface\\", 1, false) then
        return imagePath
    end
    return RENDER_BASE_PATH .. imagePath:gsub("^\\+", "")
end

local function CollectRenderCandidates(char)
    local candidates = {}
    local manifestKey = BuildManifestLookupKey(char)
    local manifestEntry = (type(AltTrackerRenderManifest) == "table") and AltTrackerRenderManifest[manifestKey] or nil
    local manifestPath = manifestEntry and NormalizeManifestImagePath(manifestEntry.image) or nil
    local sourceWidth = tonumber(manifestEntry and manifestEntry.width) or renderLayout.defaultSourceWidth
    local sourceHeight = tonumber(manifestEntry and manifestEntry.height) or renderLayout.defaultSourceHeight

    if manifestPath then
        candidates[#candidates + 1] = {
            path = manifestPath,
            source = "manifest",
            manifestKey = manifestKey,
            sourceWidth = sourceWidth,
            sourceHeight = sourceHeight,
        }
    end

    return candidates, manifestPath ~= nil, manifestKey
end

local function LayoutCenterRenderTexture()
    if not centerRenderFrame or not centerRenderTexture then return end
    local host = (centerRenderFrame and centerRenderFrame.clipFrame) or centerRenderFrame
    local frameW = math.max(1, host:GetWidth())
    local frameH = math.max(1, host:GetHeight())
    local srcW = math.max(1, tonumber(renderLayout.sourceWidth) or renderLayout.defaultSourceWidth)
    local srcH = math.max(1, tonumber(renderLayout.sourceHeight) or renderLayout.defaultSourceHeight)

    local frameAspect = frameW / frameH
    local sourceAspect = srcW / srcH

    local uMin, uMax, vMin, vMax = 0, 1, 0, 1
    if sourceAspect > frameAspect then
        local visibleU = frameAspect / sourceAspect
        local padU = (1 - visibleU) * 0.5
        uMin, uMax = padU, 1 - padU
    elseif sourceAspect < frameAspect then
        local visibleV = sourceAspect / frameAspect
        local padV = (1 - visibleV) * 0.5
        vMin, vMax = padV, 1 - padV
    end

    centerRenderTexture:ClearAllPoints()
    centerRenderTexture:SetAllPoints((centerRenderFrame and centerRenderFrame.animFrame) or centerRenderFrame)
    renderLayout.baseUMin = uMin
    renderLayout.baseUMax = uMax
    renderLayout.baseVMin = vMin
    renderLayout.baseVMax = vMax
    centerRenderTexture:SetTexCoord(uMin, uMax, vMin, vMax)
end

local function SetCenterRenderSourceSize(sourceWidth, sourceHeight)
    renderLayout.sourceWidth = math.max(1, tonumber(sourceWidth) or renderLayout.defaultSourceWidth)
    renderLayout.sourceHeight = math.max(1, tonumber(sourceHeight) or renderLayout.defaultSourceHeight)
end

local function ClearCenterRenderTexture()
    SetCenterRenderSourceSize(renderLayout.defaultSourceWidth, renderLayout.defaultSourceHeight)
    if centerRenderTexture then
        centerRenderTexture:SetTexture(nil)
        renderLayout.baseUMin = 0
        renderLayout.baseUMax = 1
        renderLayout.baseVMin = 0
        renderLayout.baseVMax = 1
        centerRenderTexture:SetTexCoord(0, 1, 0, 1)
    end
end

local function TryApplyRenderTexture(path, sourceWidth, sourceHeight)
    if not centerRenderTexture or type(path) ~= "string" or path == "" then
        return false, "invalid-path"
    end
    SetCenterRenderSourceSize(sourceWidth, sourceHeight)
    centerRenderTexture:SetTexture(nil)
    local ok = pcall(centerRenderTexture.SetTexture, centerRenderTexture, path)
    if not ok then
        return false, "settexture-call-failed"
    end
    local applied = centerRenderTexture:GetTexture()
    if not applied then
        centerRenderTexture:SetTexture(nil)
        return false, "missing-or-invalid-texture"
    end
    centerRenderTexture:SetTexture(path)
    LayoutCenterRenderTexture()
    return true, ""
end

local function SetPreviewMode(mode)
    if centerModelHost then
        if mode == PREVIEW_MODE_STATIC_RENDER then
            centerModelHost:Hide()
        else
            centerModelHost:Show()
        end
    end
    if centerModelFrame then
        if mode == PREVIEW_MODE_LIVE_MODEL then
            centerModelFrame:Show()
        else
            centerModelFrame:Hide()
        end
    end
    if centerRenderFrame then
        if mode == PREVIEW_MODE_STATIC_RENDER then
            centerRenderFrame:Show()
        else
            centerRenderFrame:Hide()
        end
    end
    if centerIdentityPanel then
        if mode == PREVIEW_MODE_OFFLINE_CARD then
            centerIdentityPanel:Show()
        else
            centerIdentityPanel:Hide()
        end
    end
end

local function IsCurrentPlayerCharacter(char)
    if not char then return false end
    local playerGuid = UnitGUID and UnitGUID("player") or nil
    if char.guid and playerGuid and char.guid == playerGuid then
        return true
    end
    if char.guid and playerGuid and char.guid ~= "" and playerGuid ~= "" and char.guid ~= playerGuid then
        return false
    end
    local playerName = UnitName and UnitName("player") or nil
    if playerName and char.name and char.name == playerName then
        local playerRealm = GetRealmName and GetRealmName() or nil
        return not playerRealm or not char.realm or char.realm == "" or char.realm == playerRealm
    end
    return false
end

local function PushPreviewDebugWindow(report)
    if not DebugModelEnabled() then return end
    local frameW = centerRenderFrame and math.floor((centerRenderFrame:GetWidth() or 0) + 0.5) or 0
    local frameH = centerRenderFrame and math.floor((centerRenderFrame:GetHeight() or 0) + 0.5) or 0
    local msg = string.format(
        "mode=%s currentPlayer=%s manifestHit=%s manifestKey=%s source=%s path=%s frame=%dx%d sourceSize=%sx%s layout=%s fallback=%s heroAnim=%s",
        tostring(report.mode or ""),
        tostring(report.currentPlayer or false),
        tostring(report.manifestHit or false),
        tostring(report.manifestKey or ""),
        tostring(report.renderSource or ""),
        tostring(report.renderPath or ""),
        frameW,
        frameH,
        tostring(report.sourceWidth or renderLayout.sourceWidth or ""),
        tostring(report.sourceHeight or renderLayout.sourceHeight or ""),
        tostring(report.layoutMode or renderLayout.mode),
        tostring(report.fallbackReason or ""),
        tostring(report.heroAnim or "")
    )
    PushModelDebugWindow(msg)
end

local function SafeCall(fn, ...)
    if type(fn) ~= "function" then
        return false, nil, nil, nil, nil, nil, nil
    end
    local ok, a, b, c, d, e, f = pcall(fn, ...)
    if not ok then
        return false, nil, nil, nil, nil, nil, nil
    end
    return true, a, b, c, d, e, f
end

local function CollectUnitApiInfo()
    return {
        UnitRace = type(UnitRace) == "function",
        UnitSex = type(UnitSex) == "function",
        UnitClass = type(UnitClass) == "function",
        UnitGUID = type(UnitGUID) == "function",
        UnitName = type(UnitName) == "function",
        GetInventoryItemLink = type(GetInventoryItemLink) == "function",
        UnitDisplayID = type(UnitDisplayID) == "function",
        UnitModel = type(UnitModel) == "function",
        GetPlayerModelDisplayInfo = type(GetPlayerModelDisplayInfo) == "function",
        C_PlayerInfo_GetDisplayID = type(C_PlayerInfo) == "table" and type(C_PlayerInfo.GetDisplayID) == "function",
        GetFacialHairCustomization = type(GetFacialHairCustomization) == "function",
        GetCustomizationChoices = type(GetCustomizationChoices) == "function",
        C_BarberShop_GetCustomizationTypeInfo = type(C_BarberShop) == "table" and type(C_BarberShop.GetCustomizationTypeInfo) == "function",
    }
end

local function ReadLivePlayerDisplayID()
    if type(C_PlayerInfo) == "table" and type(C_PlayerInfo.GetDisplayID) == "function" then
        local ok, value = SafeCall(C_PlayerInfo.GetDisplayID, "player")
        if ok then
            local id = tonumber(value)
            if id and id > 0 then return id, "C_PlayerInfo.GetDisplayID(player)" end
        end
        ok, value = SafeCall(C_PlayerInfo.GetDisplayID)
        if ok then
            local id = tonumber(value)
            if id and id > 0 then return id, "C_PlayerInfo.GetDisplayID()" end
        end
    end

    if type(UnitDisplayID) == "function" then
        local ok, value = SafeCall(UnitDisplayID, "player")
        if ok then
            local id = tonumber(value)
            if id and id > 0 then return id, "UnitDisplayID(player)" end
        end
    end

    if type(GetPlayerModelDisplayInfo) == "function" then
        local ok, value = SafeCall(GetPlayerModelDisplayInfo)
        if ok then
            local id = tonumber(value)
            if id and id > 0 then return id, "GetPlayerModelDisplayInfo()" end
        end
    end

    return nil, "unavailable"
end

local function ReadLivePlayerModelPath()
    if type(UnitModel) ~= "function" then
        return nil
    end
    local ok, value = SafeCall(UnitModel, "player")
    if ok and type(value) == "string" and value ~= "" then
        return value
    end
    return nil
end

local function ProbeCurrentPlayerAppearance(char)
    local probe = {
        unitApi = CollectUnitApiInfo(),
        isCurrent = false,
        savedDisplayID = tonumber(char and (char.displayid or char.modelDisplayID) or 0) or 0,
        savedModelPath = (char and type(char.modelPath) == "string" and char.modelPath ~= "") and char.modelPath or nil,
        savedRaceKey = char and char.raceKey or nil,
        savedSexID = tonumber(char and char.sexID or 0) or 0,
        skin = nil,
        face = nil,
        hairStyle = nil,
        hairColor = nil,
        facialHair = nil,
        features = nil,
    }

    if not char or not char.guid or not UnitGUID or UnitGUID("player") ~= char.guid then
        return probe
    end

    probe.isCurrent = true
    probe.playerGuid = UnitGUID and UnitGUID("player") or nil
    probe.playerName = UnitName and UnitName("player") or nil
    probe.liveRace = UnitRace and select(2, UnitRace("player")) or nil
    local sexRaw = UnitSex and UnitSex("player") or nil
    probe.liveSexRaw = sexRaw
    if sexRaw == 3 or sexRaw == 1 then
        probe.liveGender = "Female"
        probe.liveSexID = 1
    elseif sexRaw == 2 or sexRaw == 0 then
        probe.liveGender = "Male"
        probe.liveSexID = 0
    else
        probe.liveGender = nil
        probe.liveSexID = nil
    end
    probe.liveClass = UnitClass and select(2, UnitClass("player")) or nil
    probe.liveDisplayID, probe.liveDisplaySource = ReadLivePlayerDisplayID()
    probe.liveModelPath = ReadLivePlayerModelPath()

    if type(GetFacialHairCustomization) == "function" then
        local ok, value = SafeCall(GetFacialHairCustomization)
        if ok then
            probe.facialHair = tonumber(value) or value
        end
    end

    return probe
end

local function FormatStrategyDebug(results)
    if type(results) ~= "table" or #results == 0 then
        return "none"
    end
    local chunks = {}
    for _, result in ipairs(results) do
        local valueText = tostring(result.value or "")
        if valueText == "" then valueText = "-" end
        chunks[#chunks+1] = string.format(
            "%s{v=%s tried=%s base=%s visual=%s sil=%s try=%d/%d skip=%s fail=%s}",
            tostring(result.id or "?"),
            valueText,
            tostring(result.attempted or false),
            tostring(result.baseCallOK or false),
            tostring(result.visualModelLikelyValid or false),
            tostring(result.silhouetteRisk or false),
            tonumber(result.tryOnSucceeded or 0),
            tonumber(result.tryOnAttempts or 0),
            tostring(result.skippedReason or ""),
            tostring(result.failureReason or "")
        )
    end
    return table.concat(chunks, " ; ")
end

local function FormatDisplayProbeDebug(probe)
    if type(probe) ~= "table" then
        return "none"
    end
    return string.format(
        "displayID=%s source=%s attempted=%s ok=%s modelPath=%s modelFileID=%s displayInfo=%s silhouetteRisk=%s note=%s",
        tostring(probe.displayID or ""),
        tostring(probe.source or ""),
        tostring(probe.setDisplayAttempted or false),
        tostring(probe.setDisplayOK or false),
        tostring(probe.testModelPath or ""),
        tostring(probe.testModelFileID or ""),
        tostring(probe.testDisplayInfo or ""),
        tostring(probe.silhouetteRisk or false),
        tostring(probe.note or "")
    )
end

local function DebugModelReport(report)
    if not DebugModelEnabled() then return end
    if not DEFAULT_CHAT_FRAME or not DEFAULT_CHAT_FRAME.AddMessage then return end

    local signature = table.concat({
        tostring(report and report.charGuid or ""),
        tostring(report and report.path or ""),
        tostring(report and report.fallbackReason or ""),
        tostring(report and report.tryOnSucceeded or 0),
        tostring(report and report.baseSetOK and 1 or 0),
        tostring(report and report.selectedStrategy or ""),
        tostring(report and report.silhouetteRisk and 1 or 0),
    }, "|")
    if AT_ALTS._lastModelDebugSignature == signature then
        return
    end
    AT_ALTS._lastModelDebugSignature = signature

    local api = report and report.api or {}
    local probe = report and report.playerAppearance or {}
    local unitApi = probe.unitApi or {}
    local msg = string.format(
        "char=%s race=%s gender=%s class=%s raceNorm=%s genderNorm=%s key=%s currentByGUID=%s currentByName=%s frame=%s path=%s setUnit=%s baseMethod=%s baseOK=%s setDisplayAttempt=%s displayID=%s setDisplayOK=%s setDisplayExact=%s exactDisplayID=%s exactDisplayOK=%s setModel=%s modelPath=%s setModelOK=%s mannequinUsed=%s mannequinKey=%s mannequinID=%s mannequinKind=%s links=%d ids=%d try=%d/%d fallback=%s reason=%s player[current=%s guid=%s race=%s sexRaw=%s sexID=%s class=%s liveDisplayID=%s liveDisplaySource=%s liveModelPath=%s savedDisplayID=%s savedModelPath=%s skin=%s face=%s hairStyle=%s hairColor=%s facialHair=%s features=%s] unitApi[UnitRace=%s UnitSex=%s UnitClass=%s UnitGUID=%s UnitName=%s GetInventoryItemLink=%s UnitDisplayID=%s UnitModel=%s GetPlayerModelDisplayInfo=%s C_PlayerInfo.GetDisplayID=%s GetFacialHairCustomization=%s GetCustomizationChoices=%s C_BarberShop.GetCustomizationTypeInfo=%s] modelApi[SetCustomRace=%s SetRace=%s SetModel=%s SetBarberShopAlternateForm=%s TryOn=%s Undress=%s SetCreature=%s SetDisplayInfo=%s RefreshCamera=%s SetCamera=%s SetFacing=%s SetPosition=%s SetCamDistanceScale=%s]",
        tostring(report and report.charName or ""),
        tostring(report and report.raceRaw or ""),
        tostring(report and report.genderRaw or ""),
        tostring(report and report.classRaw or ""),
        tostring(report and report.raceNormalized or ""),
        tostring(report and report.genderNormalized or ""),
        tostring(report and report.normalizedKey or ""),
        tostring(report and report.isCurrentByGUID or false),
        tostring(report and report.isCurrentByName or false),
        tostring(report and report.modelFrameType or "unknown"),
        tostring(report and report.path or "none"),
        tostring(report and report.setUnitUsed or false),
        tostring(report and report.baseMethod or "none"),
        tostring(report and report.baseSetOK or false),
        tostring(report and report.setDisplayInfoAttempted or false),
        tostring(report and report.displayID or ""),
        tostring(report and report.setDisplayInfoOK or false),
        tostring(report and report.setDisplayInfoExactAttempted or false),
        tostring(report and report.exactDisplayID or ""),
        tostring(report and report.setDisplayInfoExactOK or false),
        tostring(report and report.setModelAttempted or false),
        tostring(report and report.savedModelPath or ""),
        tostring(report and report.setModelOK or false),
        tostring(report and report.usedMannequin or false),
        tostring(report and report.mannequinKey or ""),
        tostring(report and report.mannequinID or ""),
        tostring(report and report.mannequinKind or ""),
        tonumber(report and report.gearLinksAvailable or 0),
        tonumber(report and report.gearIDsAvailable or 0),
        tonumber(report and report.tryOnAttempts or 0),
        tonumber(report and report.tryOnSucceeded or 0),
        tostring(report and report.fallbackTriggered or false),
        tostring(report and report.fallbackReason or ""),
        tostring(probe and probe.isCurrent or false),
        tostring(probe and probe.playerGuid or ""),
        tostring(probe and probe.liveRace or ""),
        tostring(probe and probe.liveSexRaw or ""),
        tostring(probe and probe.liveSexID or ""),
        tostring(probe and probe.liveClass or ""),
        tostring(probe and probe.liveDisplayID or ""),
        tostring(probe and probe.liveDisplaySource or "unavailable"),
        tostring(probe and probe.liveModelPath or ""),
        tostring(probe and probe.savedDisplayID or ""),
        tostring(probe and probe.savedModelPath or ""),
        tostring(probe and probe.skin or "nil"),
        tostring(probe and probe.face or "nil"),
        tostring(probe and probe.hairStyle or "nil"),
        tostring(probe and probe.hairColor or "nil"),
        tostring(probe and probe.facialHair or "nil"),
        tostring(probe and probe.features or "nil"),
        tostring(unitApi.UnitRace or false),
        tostring(unitApi.UnitSex or false),
        tostring(unitApi.UnitClass or false),
        tostring(unitApi.UnitGUID or false),
        tostring(unitApi.UnitName or false),
        tostring(unitApi.GetInventoryItemLink or false),
        tostring(unitApi.UnitDisplayID or false),
        tostring(unitApi.UnitModel or false),
        tostring(unitApi.GetPlayerModelDisplayInfo or false),
        tostring(unitApi.C_PlayerInfo_GetDisplayID or false),
        tostring(unitApi.GetFacialHairCustomization or false),
        tostring(unitApi.GetCustomizationChoices or false),
        tostring(unitApi.C_BarberShop_GetCustomizationTypeInfo or false),
        tostring(api.SetCustomRace or false),
        tostring(api.SetRace or false),
        tostring(api.SetModel or false),
        tostring(api.SetBarberShopAlternateForm or false),
        tostring(api.TryOn or false),
        tostring(api.Undress or false),
        tostring(api.SetCreature or false),
        tostring(api.SetDisplayInfo or false),
        tostring(api.RefreshCamera or false),
        tostring(api.SetCamera or false),
        tostring(api.SetFacing or false),
        tostring(api.SetPosition or false),
        tostring(api.SetCamDistanceScale or false)
    )
    msg = msg .. string.format(
        " strategy=%s baseCallOK=%s visualLikely=%s silhouetteRisk=%s silhouetteReason=%s normalFallback=%s debugFallback=%s normalReason=%s client[interfaceVersion=%s wowProjectID=%s verdict=%s] strategyResults=[%s] playerDisplayIDProbe=[%s]",
        tostring(report and report.selectedStrategy or ""),
        tostring(report and report.baseCallOK or false),
        tostring(report and report.visualModelLikelyValid or false),
        tostring(report and report.silhouetteRisk or false),
        tostring(report and report.silhouetteReason or ""),
        tostring(report and report.normalModeWouldFallback or false),
        tostring(report and report.debugModeWouldFallback or false),
        tostring(report and report.fallbackReason or ""),
        tostring(report and report.interfaceVersion or ""),
        tostring(report and report.wowProjectID or ""),
        tostring(report and report.clientVerdict or ""),
        FormatStrategyDebug(report and report.strategyResults),
        FormatDisplayProbeDebug(report and report.playerDisplayIDProbe)
    )

    PushModelDebugWindow(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cff00ccff[AltTracker Roster]|r Model debug updated (see debug window).")
end

local function NormalizeRaceForModel(value)
    local raceID
    if type(value) == "number" then
        raceID = math.floor(value)
    elseif type(value) == "string" and value ~= "" then
        local num = tonumber(value)
        if num then
            raceID = math.floor(num)
        end
    end
    if raceID and MODEL_RACE_TOKEN_BY_ID[raceID] then
        return MODEL_RACE_TOKEN_BY_ID[raceID], raceID
    end

    if type(value) ~= "string" then
        return nil, nil
    end
    local raw = value:gsub("^%s+", ""):gsub("%s+$", "")
    if raw == "" then return nil, nil end
    if MODEL_RACE_ID[raw] then
        return raw, MODEL_RACE_ID[raw]
    end
    local folded = raw:gsub("_", " "):lower()
    local token = MODEL_RACE_ALIASES[folded] or MODEL_RACE_ALIASES[folded:gsub("%s+", "")]
    if token and MODEL_RACE_ID[token] then
        return token, MODEL_RACE_ID[token]
    end
    return nil, nil
end

local function NormalizeGenderForModel(value)
    local num = tonumber(value)
    if num then
        if num == 3 or num == 1 then
            return "Female", 1
        elseif num == 2 or num == 0 then
            return "Male", 0
        end
    end

    if type(value) == "string" then
        local s = value:lower()
        if s == "female" or s == "f" then
            return "Female", 1
        elseif s == "male" or s == "m" then
            return "Male", 0
        end
    end
    return nil, nil
end

local function GetOfflineMannequinSpec(raceToken, genderLabel)
    if type(raceToken) ~= "string" or raceToken == "" then
        return nil
    end
    if type(genderLabel) ~= "string" or genderLabel == "" then
        return nil
    end
    local raceMap = OFFLINE_MANNEQUIN_BY_RACE_GENDER[raceToken]
    if type(raceMap) ~= "table" then
        return nil
    end
    local spec = raceMap[genderLabel]
    if type(spec) ~= "table" then
        return nil
    end

    local id = tonumber(spec.id) or 0
    if id <= 0 then
        return nil
    end
    local kind = (spec.kind == "displayid") and "displayid" or "creature"
    return {
        id = id,
        kind = kind,
    }
end

local function CollectModelApiInfo()
    if not centerModelFrame then return {} end
    return {
        SetUnit = type(centerModelFrame.SetUnit) == "function",
        SetRace = type(centerModelFrame.SetRace) == "function",
        SetCustomRace = type(centerModelFrame.SetCustomRace) == "function",
        SetCreature = type(centerModelFrame.SetCreature) == "function",
        SetDisplayInfo = type(centerModelFrame.SetDisplayInfo) == "function",
        SetModel = type(centerModelFrame.SetModel) == "function",
        SetBarberShopAlternateForm = type(centerModelFrame.SetBarberShopAlternateForm) == "function",
        Undress = type(centerModelFrame.Undress) == "function",
        TryOn = type(centerModelFrame.TryOn) == "function",
        RefreshCamera = type(centerModelFrame.RefreshCamera) == "function",
        SetCamera = type(centerModelFrame.SetCamera) == "function",
        SetFacing = type(centerModelFrame.SetFacing) == "function",
        SetPosition = type(centerModelFrame.SetPosition) == "function",
        SetPortraitZoom = type(centerModelFrame.SetPortraitZoom) == "function",
        SetCamDistanceScale = type(centerModelFrame.SetCamDistanceScale) == "function",
        GetModel = type(centerModelFrame.GetModel) == "function",
        GetModelFileID = type(centerModelFrame.GetModelFileID) == "function",
        GetDisplayInfo = type(centerModelFrame.GetDisplayInfo) == "function",
    }
end

local function CountOfflineGear(char)
    local links, ids = 0, 0
    for _, key in ipairs(MODEL_SLOT_ORDER) do
        local link = char and char["gearlink_" .. key]
        if link and link ~= "" then
            links = links + 1
        end
        local itemID = GetGearItemID(char, key)
        if itemID and itemID > 0 then
            ids = ids + 1
        end
    end
    return links, ids
end

local function ClearCenterModel()
    if not centerModelFrame then return end
    if centerModelFrame.Undress then
        pcall(centerModelFrame.Undress, centerModelFrame)
    end
    if centerModelFrame.ClearModel then
        pcall(centerModelFrame.ClearModel, centerModelFrame)
    end
end

local function ApplyModelCameraDefaults(char, report)
    if not centerModelFrame then return end

    local raceToken = select(1, NormalizeRaceForModel(char and char.race))
    local distance = MODEL_CAM_DEFAULT
    if raceToken == "Tauren" then
        distance = MODEL_CAM_TAUREN
    elseif raceToken == "Draenei" or raceToken == "Scourge" then
        distance = MODEL_CAM_LARGE
    end

    if centerModelFrame.SetFacing then
        local ok = pcall(centerModelFrame.SetFacing, centerModelFrame, MODEL_FACE)
        if report then report.setFacingOK = ok end
    end
    if centerModelFrame.SetPosition then
        local ok = pcall(centerModelFrame.SetPosition, centerModelFrame, 0, 0, MODEL_Z_OFFSET)
        if report then report.setPositionOK = ok end
    end
    if centerModelFrame.SetPortraitZoom then
        local ok = pcall(centerModelFrame.SetPortraitZoom, centerModelFrame, 0)
        if report then report.setPortraitZoomOK = ok end
    end
    if centerModelFrame.SetCamDistanceScale then
        local ok = pcall(centerModelFrame.SetCamDistanceScale, centerModelFrame, distance)
        if report then report.setCamDistanceOK = ok end
    end
    if centerModelFrame.SetCamera then
        pcall(centerModelFrame.SetCamera, centerModelFrame, 0)
    end
    if centerModelFrame.RefreshCamera then
        pcall(centerModelFrame.RefreshCamera, centerModelFrame)
    end
end

local function CaptureModelIdentity(model)
    local info = {
        modelPath = nil,
        modelFileID = nil,
        displayInfo = nil,
    }
    if not model then
        return info
    end

    if type(model.GetModel) == "function" then
        local ok, value = SafeCall(model.GetModel, model)
        if ok and type(value) == "string" and value ~= "" then
            info.modelPath = value
        end
    end

    if type(model.GetModelFileID) == "function" then
        local ok, value = SafeCall(model.GetModelFileID, model)
        if ok then
            value = tonumber(value)
            if value and value > 0 then
                info.modelFileID = value
            end
        end
    end

    if type(model.GetDisplayInfo) == "function" then
        local ok, value = SafeCall(model.GetDisplayInfo, model)
        if ok then
            value = tonumber(value)
            if value and value > 0 then
                info.displayInfo = value
            end
        end
    end

    return info
end

local function EnsureModelDisplayProbeFrame()
    if modelDisplayProbeFrame then
        return modelDisplayProbeFrame
    end

    local ok, model = pcall(CreateFrame, "DressUpModel", nil, UIParent)
    if not ok or not model then
        model = CreateFrame("PlayerModel", nil, UIParent)
    end
    modelDisplayProbeFrame = model
    modelDisplayProbeFrame:SetSize(1, 1)
    modelDisplayProbeFrame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 0, 0)
    modelDisplayProbeFrame:Hide()
    return modelDisplayProbeFrame
end

local function ProbeCurrentPlayerDisplayIDPath()
    local probe = {
        available = false,
        displayID = nil,
        source = nil,
        setDisplayAttempted = false,
        setDisplayOK = false,
        testModelPath = nil,
        testModelFileID = nil,
        testDisplayInfo = nil,
        silhouetteRisk = false,
        note = "",
    }

    local displayID, source = ReadLivePlayerDisplayID()
    probe.displayID = displayID
    probe.source = source
    if not displayID or displayID <= 0 then
        probe.note = "no-live-displayid"
        return probe
    end
    probe.available = true

    local testModel = EnsureModelDisplayProbeFrame()
    if not testModel then
        probe.note = "no-probe-frame"
        return probe
    end
    if testModel.ClearModel then
        pcall(testModel.ClearModel, testModel)
    end

    if type(testModel.SetDisplayInfo) ~= "function" then
        probe.note = "probe-missing-setdisplayinfo"
        return probe
    end

    probe.setDisplayAttempted = true
    local ok = pcall(testModel.SetDisplayInfo, testModel, displayID)
    probe.setDisplayOK = ok
    if ok and testModel.Undress then
        pcall(testModel.Undress, testModel)
    end
    local identity = CaptureModelIdentity(testModel)
    probe.testModelPath = identity.modelPath
    probe.testModelFileID = identity.modelFileID
    probe.testDisplayInfo = identity.displayInfo
    if ok and (KNOWN_SILHOUETTE_DISPLAY_IDS[displayID] or ((not identity.modelPath) and (not identity.modelFileID))) then
        probe.silhouetteRisk = true
    end
    return probe
end

local function TryOnOfflineGear(char, report)
    local attempts, succeeded = 0, 0
    if not centerModelFrame or not centerModelFrame.TryOn then
        return attempts, succeeded
    end

    for _, key in ipairs(MODEL_SLOT_ORDER) do
        local link = char["gearlink_" .. key]
        local itemID = GetGearItemID(char, key)
        if link and link ~= "" then
            attempts = attempts + 1
            local ok = pcall(centerModelFrame.TryOn, centerModelFrame, link)
            if ok then
                succeeded = succeeded + 1
            elseif itemID > 0 then
                attempts = attempts + 1
                local okByID = pcall(centerModelFrame.TryOn, centerModelFrame, itemID)
                if okByID then
                    succeeded = succeeded + 1
                end
            end
        elseif itemID > 0 then
            attempts = attempts + 1
            local ok = pcall(centerModelFrame.TryOn, centerModelFrame, itemID)
            if ok then
                succeeded = succeeded + 1
            end
        end
    end

    report.tryOnAttempts = attempts
    report.tryOnSucceeded = succeeded
    return attempts, succeeded
end

local function EvaluateDisplayStrategyRisk(result, report)
    result.silhouetteRisk = false
    result.silhouetteReason = ""

    if result.kind ~= "displayid" and result.kind ~= "creature" then
        return
    end

    local displayID = tonumber(result.value) or 0
    if result.kind == "displayid" and displayID > 0 and KNOWN_SILHOUETTE_DISPLAY_IDS[displayID] then
        result.silhouetteRisk = true
        result.silhouetteReason = "known-white-silhouette-displayid"
        return
    end

    local identity = result.modelIdentity or {}
    if displayID > 0 and (not identity.modelPath) and (not identity.modelFileID) then
        result.silhouetteRisk = true
        if result.kind == "creature" then
            result.silhouetteReason = "mannequin-missing-model-identity"
        elseif IS_TBC_CLASSIC_CLIENT then
            result.silhouetteReason = "tbc-displayid-missing-model-identity"
        else
            result.silhouetteReason = "displayid-missing-model-identity"
        end
        return
    end

    local probe = report.playerDisplayIDProbe
    if result.kind == "displayid" and probe and probe.available and probe.silhouetteRisk and displayID > 0 and probe.displayID == displayID then
        result.silhouetteRisk = true
        result.silhouetteReason = "current-player-displayid-probe-silhouette-risk"
    end
end

local function ApplyOfflineStrategyToModel(char, report, strategy)
    if not strategy then
        return false, 0, 0
    end

    ClearCenterModel()
    if centerModelFrame and centerModelFrame.Show then
        pcall(centerModelFrame.Show, centerModelFrame)
    end

    local baseCallOK = false
    if strategy.kind == "primeunit" then
        baseCallOK = centerModelFrame.SetUnit and pcall(centerModelFrame.SetUnit, centerModelFrame, "player") or false
    elseif strategy.kind == "displayid" then
        baseCallOK = centerModelFrame.SetDisplayInfo and pcall(centerModelFrame.SetDisplayInfo, centerModelFrame, strategy.value) or false
    elseif strategy.kind == "creature" then
        baseCallOK = centerModelFrame.SetCreature and pcall(centerModelFrame.SetCreature, centerModelFrame, strategy.value) or false
    elseif strategy.kind == "modelpath" then
        baseCallOK = centerModelFrame.SetModel and pcall(centerModelFrame.SetModel, centerModelFrame, strategy.value) or false
    end
    if not baseCallOK then
        return false, 0, 0
    end

    if centerModelFrame.Undress then
        pcall(centerModelFrame.Undress, centerModelFrame)
    end
    ApplyModelCameraDefaults(char, report)

    local attempts, succeeded = TryOnOfflineGear(char, report)
    return true, attempts, succeeded
end

local function TryOfflineBaseStrategy(char, report, strategy)
    local result = {
        id = strategy.id,
        label = strategy.label,
        kind = strategy.kind,
        value = strategy.value,
        debugOnly = strategy.debugOnly or false,
        normalAllowed = strategy.normalAllowed ~= false,
        normalBlockReason = strategy.normalBlockReason or "",
        attempted = false,
        available = strategy.available,
        skippedReason = "",
        baseCallOK = false,
        visualModelLikelyValid = false,
        silhouetteRisk = false,
        silhouetteReason = "",
        tryOnAttempts = 0,
        tryOnSucceeded = 0,
        modelIdentity = {
            modelPath = nil,
            modelFileID = nil,
            displayInfo = nil,
        },
        failureReason = "",
    }

    if not strategy.available then
        result.skippedReason = strategy.unavailableReason or "strategy-unavailable"
        return result
    end

    result.attempted = true
    if strategy.kind ~= "primeunit" and strategy.kind ~= "displayid" and strategy.kind ~= "creature" and strategy.kind ~= "modelpath" then
        result.failureReason = "unknown-strategy-kind"
        return result
    end

    local baseCallOK, attempts, succeeded = ApplyOfflineStrategyToModel(char, report, strategy)
    result.baseCallOK = baseCallOK
    if not result.baseCallOK then
        if strategy.kind == "primeunit" then
            result.failureReason = "setunit-player-prime-failed"
        else
            result.failureReason = strategy.id .. "-call-failed"
        end
        return result
    end

    result.tryOnAttempts = attempts
    result.tryOnSucceeded = succeeded
    result.modelIdentity = CaptureModelIdentity(centerModelFrame)

    EvaluateDisplayStrategyRisk(result, report)

    local gearTotal = (report.gearLinksAvailable or 0) + (report.gearIDsAvailable or 0)
    if gearTotal <= 0 then
        result.failureReason = "no-gear-data"
        result.visualModelLikelyValid = false
    elseif succeeded <= 0 then
        result.failureReason = "tryon-failed-all-items"
        result.visualModelLikelyValid = false
    elseif result.silhouetteRisk then
        result.failureReason = "offline-mannequin-silhouette-risk"
        result.visualModelLikelyValid = false
    else
        result.visualModelLikelyValid = true
        if not result.normalAllowed and result.normalBlockReason ~= "" then
            result.failureReason = result.normalBlockReason
        end
    end

    return result
end

local function TryRenderCurrentPlayerModel(char, report)
    if not char then
        return false
    end
    local playerGuid = UnitGUID and UnitGUID("player") or nil
    local playerName = UnitName and UnitName("player") or nil
    local savedGuid = type(char.guid) == "string" and char.guid or ""
    local savedName = type(char.name) == "string" and char.name or ""
    local currentByGuid = savedGuid ~= "" and playerGuid and playerGuid == savedGuid
    local currentByNameFallback = savedGuid == "" and savedName ~= "" and playerName and playerName == savedName
    if not currentByGuid and not currentByNameFallback then
        return false
    end
    if savedGuid == "" and playerGuid then
        char.guid = playerGuid
        if report then
            report.charGuid = playerGuid
        end
    end
    report.path = "current-player"
    report.setUnitUsed = false
    if centerModelFrame and centerModelFrame.SetUnit then
        report.setUnitUsed = true
        local ok = pcall(centerModelFrame.SetUnit, centerModelFrame, "player")
        report.setUnitOK = ok
        if ok then
            ApplyModelCameraDefaults(char, report)
            report.baseSetOK = true
            report.baseMethod = "SetUnit(player)"
            return true
        end
    end
    report.fallbackReason = report.fallbackReason or "setunit-failed"
    return false
end

local function TryRenderOfflineModel(char, report)
    if not char or not centerModelFrame then
        if report then report.fallbackReason = "no-char-or-model-frame" end
        return false, false
    end

    local raceToken, raceID = NormalizeRaceForModel(char.race)
    local genderLabel, sexID = NormalizeGenderForModel(char.gender)
    local debugEnabled = DebugModelEnabled()
    report.path = "offline-mannequin"
    report.raceNormalized = raceToken
    report.raceID = raceID
    report.genderNormalized = genderLabel
    report.sexID = sexID
    report.normalizedKey = (raceToken and genderLabel) and (raceToken .. ":" .. genderLabel) or nil
    report.exactDisplayID = tonumber(char.displayid or char.modelDisplayID or 0) or 0
    report.savedModelPath = (type(char.modelPath) == "string" and char.modelPath ~= "") and char.modelPath or nil
    report.displayID = nil
    report.mannequinKey = report.normalizedKey
    report.mannequinID = nil
    report.mannequinKind = nil
    report.playerDisplayIDProbe = ProbeCurrentPlayerDisplayIDPath()
    report.strategyResults = {}
    report.baseCallOK = false
    report.visualModelLikelyValid = false
    report.silhouetteRisk = false
    report.silhouetteReason = ""
    report.selectedStrategy = ""
    report.normalModeWouldFallback = true
    report.debugModeWouldFallback = true

    if not raceToken then
        report.fallbackReason = "missing-or-unsupported-race"
    elseif sexID == nil then
        report.fallbackReason = "missing-or-unsupported-gender"
    end

    local strategies = {}
    local mannequinSpec = GetOfflineMannequinSpec(raceToken, genderLabel)
    if mannequinSpec then
        report.mannequinID = mannequinSpec.id
        report.mannequinKind = mannequinSpec.kind
        report.displayID = mannequinSpec.id

        if mannequinSpec.kind == "creature" then
            table.insert(strategies, {
                id = "mannequin-creature",
                label = "SetCreature(offline-mannequin)",
                kind = "creature",
                value = mannequinSpec.id,
                debugOnly = false,
                available = type(centerModelFrame.SetCreature) == "function",
                unavailableReason = "missing-setcreature-api",
            })
            table.insert(strategies, {
                id = "mannequin-display",
                label = "SetDisplayInfo(offline-mannequin)",
                kind = "displayid",
                value = mannequinSpec.id,
                debugOnly = false,
                available = type(centerModelFrame.SetDisplayInfo) == "function",
                unavailableReason = "missing-setdisplayinfo-api",
            })
        else
            table.insert(strategies, {
                id = "mannequin-display",
                label = "SetDisplayInfo(offline-mannequin)",
                kind = "displayid",
                value = mannequinSpec.id,
                debugOnly = false,
                available = type(centerModelFrame.SetDisplayInfo) == "function",
                unavailableReason = "missing-setdisplayinfo-api",
            })
            table.insert(strategies, {
                id = "mannequin-creature",
                label = "SetCreature(offline-mannequin)",
                kind = "creature",
                value = mannequinSpec.id,
                debugOnly = false,
                available = type(centerModelFrame.SetCreature) == "function",
                unavailableReason = "missing-setcreature-api",
            })
        end
    elseif report.fallbackReason == "" then
        report.fallbackReason = "missing-offline-mannequin-mapping"
    end

    table.insert(strategies, {
        id = "saved-displayid",
        label = "SetDisplayInfo(saved-displayid)",
        kind = "displayid",
        value = report.exactDisplayID,
        debugOnly = true,
        available = debugEnabled and report.exactDisplayID > 0 and type(centerModelFrame.SetDisplayInfo) == "function",
        unavailableReason = (not debugEnabled) and "debug-mode-disabled"
            or ((report.exactDisplayID > 0) and "missing-setdisplayinfo-api" or "missing-saved-displayid"),
    })
    table.insert(strategies, {
        id = "saved-modelpath",
        label = "SetModel(saved-modelPath)",
        kind = "modelpath",
        value = report.savedModelPath,
        debugOnly = true,
        available = debugEnabled and report.savedModelPath and type(centerModelFrame.SetModel) == "function",
        unavailableReason = (not debugEnabled) and "debug-mode-disabled"
            or (report.savedModelPath and "missing-setmodel-api" or "missing-saved-modelpath"),
    })

    local selectedNormal
    local selectedDebug
    local selectedResult
    local strategyById = {}

    for _, strategy in ipairs(strategies) do
        strategyById[strategy.id] = strategy
        local result = TryOfflineBaseStrategy(char, report, strategy)
        table.insert(report.strategyResults, result)

        if strategy.id == "mannequin-display" then
            report.setDisplayInfoAttempted = result.attempted
            report.setDisplayInfoOK = result.baseCallOK
        elseif strategy.id == "mannequin-creature" then
            report.setCreatureAttempted = result.attempted
            report.setCreatureOK = result.baseCallOK
        elseif strategy.id == "saved-displayid" then
            report.setDisplayInfoExactAttempted = result.attempted
            report.setDisplayInfoExactOK = result.baseCallOK
        elseif strategy.id == "saved-modelpath" then
            report.setModelAttempted = result.attempted
            report.setModelOK = result.baseCallOK
        end

        local gearTotal = (report.gearLinksAvailable or 0) + (report.gearIDsAvailable or 0)
        local canShowInDebug = result.baseCallOK and (gearTotal <= 0 or result.tryOnSucceeded > 0)
        local canShowInNormal = result.normalAllowed and (not result.debugOnly) and canShowInDebug and result.visualModelLikelyValid and not result.silhouetteRisk
        if not selectedNormal and canShowInNormal then
            selectedNormal = result
        end
        if not selectedDebug and canShowInDebug then
            selectedDebug = result
        end
    end

    report.normalModeWouldFallback = (selectedNormal == nil)
    report.debugModeWouldFallback = (selectedDebug == nil)

    if debugEnabled then
        selectedResult = selectedNormal or selectedDebug
    else
        selectedResult = selectedNormal
    end

    if selectedResult and selectedResult.baseCallOK then
        local strategyDef = strategyById[selectedResult.id]
        local applyOK, applyAttempts, applySucceeded = ApplyOfflineStrategyToModel(char, report, strategyDef or selectedResult)
        if applyOK then
        report.baseSetOK = true
        report.baseCallOK = true
        report.visualModelLikelyValid = selectedResult.visualModelLikelyValid
        report.silhouetteRisk = selectedResult.silhouetteRisk
        report.silhouetteReason = selectedResult.silhouetteReason
        report.baseMethod = selectedResult.label
        report.selectedStrategy = selectedResult.id
        report.tryOnAttempts = applyAttempts
        report.tryOnSucceeded = applySucceeded
        report.setUnitUsed = false
        report.setUnitOK = false
        report.usedExactDisplayID = selectedResult.id == "saved-displayid"
        report.usedMappedDisplayID = selectedResult.id == "mannequin-display"
        report.usedMannequin = (selectedResult.id == "mannequin-display" or selectedResult.id == "mannequin-creature")
        report.usedModelPath = selectedResult.id == "saved-modelpath"
        report.usedCreature = selectedResult.id == "mannequin-creature"
        report.displayID = (selectedResult.kind == "displayid" or selectedResult.kind == "creature") and tonumber(selectedResult.value) or report.displayID
        if report.silhouetteRisk then
            report.fallbackReason = selectedResult.failureReason ~= "" and selectedResult.failureReason or "offline-mannequin-silhouette-risk"
        end
        return true, applySucceeded > 0
        end
        if report.fallbackReason == "" then
            report.fallbackReason = "selected-strategy-reapply-failed"
        end
    end

    report.baseSetOK = false
    report.baseCallOK = false
    report.visualModelLikelyValid = false
    report.selectedStrategy = ""
    for _, result in ipairs(report.strategyResults) do
        if result.baseCallOK and result.silhouetteRisk and (debugEnabled or not result.debugOnly) then
            report.fallbackReason = result.failureReason ~= "" and result.failureReason or "offline-mannequin-silhouette-risk"
            return false, false
        end
        if report.fallbackReason == "" and result.failureReason and result.failureReason ~= "" then
            report.fallbackReason = result.failureReason
        elseif result.skippedReason and result.skippedReason ~= "" and report.fallbackReason == "" then
            report.fallbackReason = result.skippedReason
        end
    end
    if report.fallbackReason == "" then
        report.fallbackReason = "offline-mannequin-failed"
    end
    return false, false
end

local function UpdateCenterModel(char, selectionChanged)
    if not centerModelFrame or not centerIdentityPanel then return end
    local animFrame = centerRenderFrame and centerRenderFrame.animFrame
    if animFrame then
        animFrame:SetScript("OnUpdate", nil)
        animFrame:SetScale(renderLayout.HERO_ANIM_END_SCALE)
        animFrame:SetAlpha(renderLayout.HERO_ANIM_END_ALPHA)
        if centerRenderTexture then
            centerRenderTexture:SetTexCoord(
                renderLayout.baseUMin or 0,
                renderLayout.baseUMax or 1,
                renderLayout.baseVMin or 0,
                renderLayout.baseVMax or 1
            )
        end
    end
    ClearCenterModel()
    ClearCenterRenderTexture()
    local heroAnimState = renderLayout.HERO_ANIM_ENABLED and "skipped-no-static-render" or "disabled"

    if not char then
        SetPreviewMode(PREVIEW_MODE_OFFLINE_CARD)
        PushPreviewDebugWindow({
            mode = PREVIEW_MODE_OFFLINE_CARD,
            currentPlayer = false,
            fallbackReason = "no-selected-character",
            sourceWidth = renderLayout.sourceWidth,
            sourceHeight = renderLayout.sourceHeight,
            layoutMode = renderLayout.mode,
            heroAnim = heroAnimState,
        })
        SetCenterModelStatus("Debug: offlineCardMode (no selected character)", AltTracker.C.TEXT_DIM[1], AltTracker.C.TEXT_DIM[2], AltTracker.C.TEXT_DIM[3])
        return
    end

    local candidates, manifestHit, manifestKey = CollectRenderCandidates(char)
    local renderSource
    local renderPath
    for _, candidate in ipairs(candidates) do
        local cache = renderTextureProbeCache[candidate.path]
        if cache == nil then
            local ok = TryApplyRenderTexture(candidate.path, candidate.sourceWidth, candidate.sourceHeight)
            cache = ok and true or false
            renderTextureProbeCache[candidate.path] = cache
        end
        if cache then
            local applyOk = TryApplyRenderTexture(candidate.path, candidate.sourceWidth, candidate.sourceHeight)
            if applyOk then
                renderSource = candidate.source
                renderPath = candidate.path
                renderLayout.sourceWidth = candidate.sourceWidth or renderLayout.sourceWidth
                renderLayout.sourceHeight = candidate.sourceHeight or renderLayout.sourceHeight
                break
            end
            renderTextureProbeCache[candidate.path] = false
        end
    end

    if renderPath then
        SetPreviewMode(PREVIEW_MODE_STATIC_RENDER)
        if selectionChanged then
            if not renderLayout.HERO_ANIM_ENABLED or not animFrame then
                heroAnimState = "disabled"
            else
                local startScale = renderLayout.HERO_ANIM_START_SCALE
                local endScale = renderLayout.HERO_ANIM_END_SCALE
                local startAlpha = renderLayout.HERO_ANIM_START_ALPHA
                local endAlpha = renderLayout.HERO_ANIM_END_ALPHA
                local duration = math.max(0.01, tonumber(renderLayout.HERO_ANIM_DURATION) or 0.9)
                local startedAt = GetTime and GetTime() or 0
                local baseUMin = renderLayout.baseUMin or 0
                local baseUMax = renderLayout.baseUMax or 1
                local baseVMin = renderLayout.baseVMin or 0
                local baseVMax = renderLayout.baseVMax or 1
                local baseUCenter = (baseUMin + baseUMax) * 0.5
                local baseVCenter = (baseVMin + baseVMax) * 0.5
                local baseUHalf = math.max(0.0001, (baseUMax - baseUMin) * 0.5)
                local baseVHalf = math.max(0.0001, (baseVMax - baseVMin) * 0.5)

                animFrame:SetScale(endScale)
                animFrame:SetAlpha(startAlpha)
                do
                    local startUHalf = baseUHalf / math.max(0.0001, startScale)
                    local startVHalf = baseVHalf / math.max(0.0001, startScale)
                    centerRenderTexture:SetTexCoord(
                        baseUCenter - startUHalf,
                        baseUCenter + startUHalf,
                        baseVCenter - startVHalf,
                        baseVCenter + startVHalf
                    )
                end
                animFrame:SetScript("OnUpdate", function(self)
                    local now = GetTime and GetTime() or (startedAt + duration)
                    local t = (now - startedAt) / duration
                    if t >= 1 then
                        self:SetScale(endScale)
                        self:SetAlpha(endAlpha)
                        centerRenderTexture:SetTexCoord(baseUMin, baseUMax, baseVMin, baseVMax)
                        self:SetScript("OnUpdate", nil)
                        return
                    end
                    if t < 0 then t = 0 end
                    local eased = 1 - ((1 - t) * (1 - t))
                    local zoom = startScale + ((endScale - startScale) * eased)
                    local uHalf = baseUHalf / math.max(0.0001, zoom)
                    local vHalf = baseVHalf / math.max(0.0001, zoom)
                    centerRenderTexture:SetTexCoord(
                        baseUCenter - uHalf,
                        baseUCenter + uHalf,
                        baseVCenter - vHalf,
                        baseVCenter + vHalf
                    )
                    self:SetAlpha(startAlpha + ((endAlpha - startAlpha) * eased))
                end)
                heroAnimState = "played"
            end
        end
        PushPreviewDebugWindow({
            mode = PREVIEW_MODE_STATIC_RENDER,
            currentPlayer = IsCurrentPlayerCharacter(char),
            manifestHit = manifestHit,
            manifestKey = manifestKey,
            renderSource = renderSource,
            renderPath = renderPath,
            fallbackReason = "",
            sourceWidth = renderLayout.sourceWidth,
            sourceHeight = renderLayout.sourceHeight,
            layoutMode = renderLayout.mode,
            heroAnim = heroAnimState,
        })
        SetCenterModelStatus("Debug: staticRenderMode (" .. tostring(renderSource or "unknown") .. ")", 0.75, 0.88, 1.0)
        return
    end

    if IsCurrentPlayerCharacter(char) then
        local currentReport = { path = "current-player", fallbackReason = "setunit-failed" }
        if TryRenderCurrentPlayerModel(char, currentReport) then
            SetPreviewMode(PREVIEW_MODE_LIVE_MODEL)
            PushPreviewDebugWindow({
                mode = PREVIEW_MODE_LIVE_MODEL,
                currentPlayer = true,
                manifestHit = manifestHit,
                manifestKey = manifestKey,
                renderSource = "live-model",
                renderPath = "",
                fallbackReason = "",
                sourceWidth = renderLayout.sourceWidth,
                sourceHeight = renderLayout.sourceHeight,
                layoutMode = renderLayout.mode,
                heroAnim = heroAnimState,
            })
            SetCenterModelStatus("Debug: liveModelMode (current player)", 0.75, 0.88, 1.0)
            return
        end
        SetPreviewMode(PREVIEW_MODE_OFFLINE_CARD)
        PushPreviewDebugWindow({
            mode = PREVIEW_MODE_OFFLINE_CARD,
            currentPlayer = true,
            manifestHit = manifestHit,
            manifestKey = manifestKey,
            renderSource = "live-model",
            renderPath = "",
            fallbackReason = currentReport.fallbackReason or "setunit-failed",
            sourceWidth = renderLayout.sourceWidth,
            sourceHeight = renderLayout.sourceHeight,
            layoutMode = renderLayout.mode,
            heroAnim = heroAnimState,
        })
        SetCenterModelStatus("Debug: offlineCardMode (current player SetUnit failed)", AltTracker.C.TEXT_DIM[1], AltTracker.C.TEXT_DIM[2], AltTracker.C.TEXT_DIM[3])
        return
    end

    SetPreviewMode(PREVIEW_MODE_OFFLINE_CARD)
    PushPreviewDebugWindow({
        mode = PREVIEW_MODE_OFFLINE_CARD,
        currentPlayer = false,
        manifestHit = manifestHit,
        manifestKey = manifestKey,
        renderSource = "",
        renderPath = "",
        fallbackReason = "no-render-image",
        sourceWidth = renderLayout.sourceWidth,
        sourceHeight = renderLayout.sourceHeight,
        layoutMode = renderLayout.mode,
        heroAnim = heroAnimState,
    })
    SetCenterModelStatus("Debug: offlineCardMode (no render image)", AltTracker.C.TEXT_DIM[1], AltTracker.C.TEXT_DIM[2], AltTracker.C.TEXT_DIM[3])
end

local function FormatCharRowValue(char, def)
    if not char then return "-" end
    local value = char[def.key]
    if value == nil then return "-" end

    if def.kind == "money" then
        return MoneyText(value)
    elseif def.kind == "int" then
        return NumberText(value)
    elseif def.kind == "percent0" then
        return string.format("%d%%", math.floor(tonumber(value) or 0))
    elseif def.kind == "percent2" then
        return string.format("%.2f%%", tonumber(value) or 0)
    elseif def.kind == "lastseen" then
        return LastSeenText(value)
    end
    return tostring(value)
end

local function HasDisplayValue(char, def)
    if not char then return false end
    local value = char[def.key]
    if value == nil then return false end
    if def.allowZero then return true end
    if type(value) == "number" then
        return value > 0
    end
    local num = tonumber(value)
    if num then
        return num > 0
    end
    return value ~= ""
end

-- Forward declarations: these helpers are referenced before their bodies.
local ClampTabScroll
local SetTabContentHeight

local function UpdateCharacterRows(char)
    if not charRows.groups then return end

    local y = -10
    local detailedVisible = false

    for gi, group in ipairs(charRows.groups) do
        local groupHasVisible = false
        for _, entry in ipairs(group.rows) do
            if HasDisplayValue(char, entry.def) then
                groupHasVisible = true
                break
            end
        end

        if groupHasVisible then
            group.header:Show()
            group.header:ClearAllPoints()
            group.header:SetPoint("TOPLEFT", tabFrames.character, "TOPLEFT", 10, y)
            group.header:SetPoint("TOPRIGHT", tabFrames.character, "TOPRIGHT", -10, y)
            y = y - STAT_SECTION_HEADER_GAP

            for _, entry in ipairs(group.rows) do
                local show = HasDisplayValue(char, entry.def)
                if show then
                    entry.row.value:SetText(FormatCharRowValue(char, entry.def))
                    entry.row:ClearAllPoints()
                    entry.row:SetPoint("TOPLEFT", tabFrames.character, "TOPLEFT", 10, y)
                    entry.row:SetPoint("TOPRIGHT", tabFrames.character, "TOPRIGHT", -10, y)
                    entry.row:Show()
                    y = y - STAT_ROW_STEP
                    if gi > 1 then
                        detailedVisible = true
                    end
                else
                    entry.row:Hide()
                end
            end
            y = y - STAT_SECTION_GAP
        else
            group.header:Hide()
            for _, entry in ipairs(group.rows) do
                entry.row:Hide()
            end
        end
    end

    if charNoDataText then
        if not detailedVisible then
            charNoDataText:SetText("Detailed stats are not available yet. Log into this character to scan full stats.")
            charNoDataText:Show()
        else
            charNoDataText:Hide()
        end
    end
    SetTabContentHeight("character", y)
end

local function UpdateRepRows(char)
    local y = -10
    local shown = 0
    for i, row in ipairs(repRows) do
        local def = REP_FIELDS[i]
        local standing = char and tonumber(char[def.field]) or nil
        if standing then
            local info = StandingInfo(standing)
            if info then
                row.value:SetText(info[1])
                row.value:SetTextColor(info[2], info[3], info[4])
            else
                row.value:SetText(tostring(standing))
                row.value:SetTextColor(unpack(AltTracker.C.TEXT_DIM))
            end
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", tabFrames.reputations, "TOPLEFT", 10, y)
            row:SetPoint("TOPRIGHT", tabFrames.reputations, "TOPRIGHT", -10, y)
            row:Show()
            y = y - STAT_ROW_STEP
            shown = shown + 1
        else
            row:Hide()
        end
    end
    if repNoDataText then
        if shown == 0 then
            repNoDataText:Show()
        else
            repNoDataText:Hide()
        end
    end
    SetTabContentHeight("reputations", y)
end

local function UpdateProfRows(char)
    local y = -10
    local profShown = 0
    for i, row in ipairs(profRows) do
        local def = PROF_FIELDS[i]
        local skill = char and tonumber(char[def.field]) or nil
        local maxSkill = char and tonumber(char[def.maxField]) or nil
        if (skill and skill > 0) or (maxSkill and maxSkill > 0) then
            row.value:SetText(string.format("%d / %d", skill or 0, maxSkill or 0))
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", tabFrames.professions, "TOPLEFT", 10, y)
            row:SetPoint("TOPRIGHT", tabFrames.professions, "TOPRIGHT", -10, y)
            row:Show()
            y = y - STAT_ROW_STEP
            profShown = profShown + 1
        else
            row:Hide()
        end
    end

    local now = time()
    local cooldownShown = 0
    if profCooldownHeader then
        profCooldownHeader:Hide()
    end

    -- Gather this character's live craft cooldowns — dynamic cd_<prof>@<label>
    -- fields written by the Professions plugin — soonest-ready first. Expired
    -- ones aren't shown (the craft is available again).
    local cds = {}
    if char then
        for k, v in pairs(char) do
            if type(k) == "string" then
                local label = k:match("^cd_.-@(.+)$")
                local ts = label and tonumber(v)
                if label and ts and ts > 0 then
                    cds[#cds + 1] = { label = label, ts = ts }
                end
            end
        end
        table.sort(cds, function(a, b) return a.ts < b.ts end)
    end

    for i, row in ipairs(cooldownRows) do
        local cd = cds[i]
        if cd then
            if cooldownShown == 0 and profCooldownHeader then
                y = y - 4
                profCooldownHeader:ClearAllPoints()
                profCooldownHeader:SetPoint("TOPLEFT", tabFrames.professions, "TOPLEFT", 10, y)
                profCooldownHeader:SetText("Cooldowns")
                profCooldownHeader:Show()
                y = y - STAT_SECTION_HEADER_GAP
            end

            row.label:SetText(cd.label)
            if cd.ts <= now then
                row.value:SetText("Ready")
                row.value:SetTextColor(0.45, 1.0, 0.45)
            else
                row.value:SetText("Ready in " .. DurationText(cd.ts - now))
                row.value:SetTextColor(unpack(AltTracker.C.TEXT_NORM))
            end
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", tabFrames.professions, "TOPLEFT", 10, y)
            row:SetPoint("TOPRIGHT", tabFrames.professions, "TOPRIGHT", -10, y)
            row:Show()
            y = y - STAT_ROW_STEP
            cooldownShown = cooldownShown + 1
        else
            row:Hide()
        end
    end

    if profNoDataText then
        if profShown == 0 and cooldownShown == 0 then
            profNoDataText:Show()
        else
            profNoDataText:Hide()
        end
    end
    SetTabContentHeight("professions", y)
end

local function SetActiveTab(tabId)
    local ui = GetUIState()
    ui.activeTab = tabId

    local ar, ag, ab = AltTracker.GetAccentRGB()
    for _, tab in ipairs(tabButtons) do
        if tab.id == tabId then
            tab:SetBackdropColor(AltTracker.C.BG_BTN_ACTIVE[1], AltTracker.C.BG_BTN_ACTIVE[2], AltTracker.C.BG_BTN_ACTIVE[3], AltTracker.C.BG_BTN_ACTIVE[4])
            tab.label:SetTextColor(ar, ag, ab)
            if tab.accent then
                tab.accent:SetColorTexture(ar, ag, ab, 1)
                tab.accent:Show()
            end
        else
            tab:SetBackdropColor(AltTracker.C.BG_BTN_IDLE[1], AltTracker.C.BG_BTN_IDLE[2], AltTracker.C.BG_BTN_IDLE[3], AltTracker.C.BG_BTN_IDLE[4])
            tab.label:SetTextColor(unpack(AltTracker.C.TEXT_DIM))
            if tab.accent then tab.accent:Hide() end
        end
    end

    for id, f in pairs(tabScrollFrames) do
        if id == tabId then f:Show() else f:Hide() end
    end
    ClampTabScroll(tabId)
end

local function UpdateStatsHeader(char)
    if not char then
        statsNameText:SetText("No character selected")
        statsMetaText:SetText("")
        statsGuildText:SetText("")
        statsILvlText:SetText("-")
        if statsGSText then statsGSText:SetText("-"); statsGSText:SetTextColor(0.95, 0.95, 0.95) end
        return
    end

    local classToken = (char.class or ""):upper()
    local className = CLASS_DISPLAY[classToken] or (char.class or "Unknown")
    local spec = (char.spec and char.spec ~= "") and char.spec or "Unknown Spec"
    local guildLine = GuildFactionLine(char)

    statsNameText:SetText((AltTracker.ClassColor and AltTracker.ClassColor(classToken) or "") .. (char.name or "") .. "|r")
    statsMetaText:SetText(string.format("Level %d %s %s", char.level or 0, spec, className))
    statsGuildText:SetText(guildLine)
    if char.ilvl and char.ilvl > 0 then
        statsILvlText:SetText(string.format("%.1f", char.ilvl))
    else
        statsILvlText:SetText("-")
    end

    if statsGSText then
        local gs = ComputeCharGS(char)
        if gs > 0 then
            local r, g, b = GS_GetBarGradient(gs)
            statsGSText:SetText(tostring(gs))
            statsGSText:SetTextColor(r, g, b)
        else
            statsGSText:SetText("-")
            statsGSText:SetTextColor(0.95, 0.95, 0.95)
        end
    end
end

local function UpdateDetail()
    local selectionKey = ""
    if selectedChar then
        local guid = selectedChar.guid
        if type(guid) == "string" and guid ~= "" then
            selectionKey = "guid:" .. guid
        else
            selectionKey = "char:" .. BuildManifestLookupKey(selectedChar)
        end
    end
    local selectionChanged = selectionKey ~= (AT_ALTS._lastDetailSelectionKey or "")
    AT_ALTS._lastDetailSelectionKey = selectionKey
    SetCenterText(selectedChar)
    UpdateCenterModel(selectedChar, selectionChanged)
    UpdateGearButtons(selectedChar)
    UpdateStatsHeader(selectedChar)
    UpdateCharacterRows(selectedChar)
    UpdateRepRows(selectedChar)
    UpdateProfRows(selectedChar)
end

local function UpdateFooter()
    local totalChars, totalLevel, totalGold = 0, 0, 0
    local ilvlTotal, ilvlCount = 0, 0
    for _, char in next, GetCharacterStore() do
        if type(char) == "table" and char.name then
            totalChars = totalChars + 1
            totalLevel = totalLevel + (char.level or 0)
            totalGold = totalGold + (char.money or 0)
            if char.ilvl and char.ilvl > 0 then
                ilvlTotal = ilvlTotal + char.ilvl
                ilvlCount = ilvlCount + 1
            end
        end
    end

    local ar, ag, ab = AltTracker.GetAccentRGB()
    local accentHex = string.format("|cff%02x%02x%02x", ar * 255, ag * 255, ab * 255)
    footerLeft:SetText(accentHex .. totalChars .. "|r |cffaaaaaachars  " .. accentHex .. totalLevel .. "|r |cffaaaaaatotal levels|r")
    if ilvlCount > 0 then
        footerMid:SetText(string.format("|cffaaaaaa%.1f|r avg iLvl", ilvlTotal / ilvlCount))
    else
        footerMid:SetText("")
    end
    footerRight:SetText("|cffaaaaaa" .. math.floor(totalGold / 10000) .. GOLD_ICON_SM .. " total gold|r")
end

-- Highlight the active List/Scene toggle button.
function AT_ALTS._UpdateViewToggle()
    local btns = AT_ALTS._viewButtons
    if not btns then return end
    local mode = (GetUIState().viewMode == "scene") and "scene" or "list"
    local ar, ag, ab = AltTracker.GetAccentRGB()
    for id, btn in pairs(btns) do
        if id == mode then
            AltTracker.ApplyBGOnly(btn, ar * 0.30, ag * 0.30, ab * 0.30, 0.95)
            btn.label:SetTextColor(1, 1, 1)
        else
            AltTracker.ApplyBGOnly(btn, AltTracker.C.BG_BTN_IDLE[1], AltTracker.C.BG_BTN_IDLE[2], AltTracker.C.BG_BTN_IDLE[3], AltTracker.C.BG_BTN_IDLE[4])
            btn.label:SetTextColor(unpack(AltTracker.C.TEXT_DIM))
        end
    end
end

-- Show/hide the panels for the current view mode. Scene mode hides the
-- center + stats panels as whole units and shows the RosterScene overlay.
function AT_ALTS.ApplyViewMode()
    local scene = (GetUIState().viewMode == "scene")
    if scene then
        if centerPanel then centerPanel:Hide() end
        if statsPanel then statsPanel:Hide() end
        if AltTracker.RosterScene then AltTracker.RosterScene.SetVisible(true) end
    else
        if AltTracker.RosterScene then AltTracker.RosterScene.SetVisible(false) end
        if centerPanel then centerPanel:Show() end
        if statsPanel then statsPanel:Show() end
    end
    AT_ALTS._UpdateViewToggle()
end

function AT_ALTS.SetViewMode(mode)
    GetUIState().viewMode = (mode == "scene") and "scene" or "list"
    AT_ALTS.ApplyViewMode()
    AT_ALTS.Refresh()
end

function AT_ALTS.Refresh()
    if not panel or not AT_ALTS.isActive then return end
    BuildEntries()
    RenderSelector()
    if GetUIState().viewMode == "scene" and AltTracker.RosterScene then
        local camp = AltTracker.RosterScene.SelectCamp(
            GetCharacterStore(), AltTrackerConfig and AltTrackerConfig.hideLow, 6)
        AltTracker.RosterScene.Render(camp, selectedGuid)
    else
        UpdateDetail()
    end
    UpdateFooter()
end

local function CreateStatsRow(parent, topY, labelText)
    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(STAT_ROW_H)
    row:SetPoint("TOPLEFT", parent, "TOPLEFT", 10, topY)
    row:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -10, topY)

    row.label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.label:SetPoint("LEFT", row, "LEFT", 0, 0)
    row.label:SetJustifyH("LEFT")
    row.label:SetText(labelText)
    row.label:SetTextColor(unpack(AltTracker.C.TEXT_NORM))

    row.value = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.value:SetPoint("RIGHT", row, "RIGHT", 0, 0)
    row.value:SetJustifyH("RIGHT")
    row.value:SetTextColor(unpack(AltTracker.C.TEXT_BRIGHT))

    local line = row:CreateTexture(nil, "ARTWORK")
    line:SetHeight(1)
    line:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, -2)
    line:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0, -2)
    line:SetColorTexture(unpack(AltTracker.C.SEP))

    return row
end

ClampTabScroll = function(tabId)
    local scroll = tabScrollFrames[tabId]
    local content = tabFrames[tabId]
    if not scroll or not content then return end
    local max = math.max(0, (content:GetHeight() or 0) - (scroll:GetHeight() or 0))
    local cur = scroll:GetVerticalScroll() or 0
    if cur < 0 then
        scroll:SetVerticalScroll(0)
    elseif cur > max then
        scroll:SetVerticalScroll(max)
    end
end

SetTabContentHeight = function(tabId, finalY)
    local content = tabFrames[tabId]
    if not content then return end
    local h = math.max(1, math.floor((-finalY) + 24))
    content:SetHeight(h)
    ClampTabScroll(tabId)
end

local function LayoutTabButtons()
    if not tabStripFrame or #tabButtons == 0 then return end

    local inset = 8
    local gap = 4
    local available = (tabStripFrame:GetWidth() or 0) - (inset * 2) - (gap * (#tabButtons - 1))
    if available <= 0 then return end

    local btnW = math.floor(available / #tabButtons)
    local useShort = btnW < 90

    for i, btn in ipairs(tabButtons) do
        btn:ClearAllPoints()
        btn:SetSize(btnW, TAB_HEIGHT)
        btn:SetPoint("LEFT", tabStripFrame, "LEFT", inset + (i - 1) * (btnW + gap), 0)
        btn.label:SetText((useShort and btn.shortLabel) or btn.fullLabel)
    end
end

local function BuildTabs()
    tabStripFrame = CreateFrame("Frame", nil, statsPanel)
    tabStripFrame:SetPoint("TOPLEFT", statsPanel, "TOPLEFT", 0, TAB_STRIP_Y)
    tabStripFrame:SetPoint("TOPRIGHT", statsPanel, "TOPRIGHT", 0, TAB_STRIP_Y)
    tabStripFrame:SetHeight(TAB_HEIGHT)

    local tabs = {
        { id = "character", label = "Character", short = "Char" },
        { id = "reputations", label = "Reputations", short = "Reps" },
        { id = "professions", label = "Professions", short = "Profs" },
    }

    for i, t in ipairs(tabs) do
        local btn = CreateFrame("Button", nil, tabStripFrame, "BackdropTemplate")
        AltTracker.ApplyBGOnly(btn, AltTracker.C.BG_BTN_IDLE[1], AltTracker.C.BG_BTN_IDLE[2], AltTracker.C.BG_BTN_IDLE[3], AltTracker.C.BG_BTN_IDLE[4])
        btn.id = t.id
        btn.fullLabel = t.label
        btn.shortLabel = t.short

        btn.label = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        btn.label:SetPoint("LEFT", btn, "LEFT", 2, 0)
        btn.label:SetPoint("RIGHT", btn, "RIGHT", -2, 0)
        btn.label:SetJustifyH("CENTER")
        btn.label:SetWordWrap(false)
        btn.label:SetText(t.label)
        btn.label:SetTextColor(unpack(AltTracker.C.TEXT_DIM))

        btn.accent = btn:CreateTexture(nil, "OVERLAY")
        btn.accent:SetHeight(2)
        btn.accent:SetPoint("BOTTOMLEFT", btn, "BOTTOMLEFT", 1, 0)
        btn.accent:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -1, 0)
        btn.accent:Hide()

        btn:SetScript("OnClick", function(self)
            SetActiveTab(self.id)
        end)

        tabButtons[#tabButtons + 1] = btn
    end

    tabStripFrame:SetScript("OnSizeChanged", function()
        LayoutTabButtons()
    end)
    LayoutTabButtons()

    local stripSep = statsPanel:CreateTexture(nil, "ARTWORK")
    stripSep:SetHeight(1)
    stripSep:SetPoint("TOPLEFT", statsPanel, "TOPLEFT", 0, TAB_HOST_Y + 1)
    stripSep:SetPoint("TOPRIGHT", statsPanel, "TOPRIGHT", 0, TAB_HOST_Y + 1)
    stripSep:SetColorTexture(unpack(AltTracker.C.SEP))

    local tabHost = CreateFrame("Frame", nil, statsPanel)
    tabHost:SetPoint("TOPLEFT", statsPanel, "TOPLEFT", 0, TAB_HOST_Y)
    tabHost:SetPoint("BOTTOMRIGHT", statsPanel, "BOTTOMRIGHT", 0, 4)

    local function CreateTabBody(tabId)
        local scroll = CreateFrame("ScrollFrame", nil, tabHost)
        scroll:SetAllPoints()
        scroll:EnableMouseWheel(true)
        scroll:SetScript("OnMouseWheel", function(self, delta)
            local step = STAT_ROW_STEP * 2
            local cur = self:GetVerticalScroll() or 0
            local content = tabFrames[tabId]
            local max = 0
            if content then
                max = math.max(0, (content:GetHeight() or 0) - (self:GetHeight() or 0))
            end
            local nextOffset = math.max(0, math.min(cur - (delta * step), max))
            self:SetVerticalScroll(nextOffset)
        end)

        local content = CreateFrame("Frame", nil, scroll)
        content:SetPoint("TOPLEFT", scroll, "TOPLEFT", 0, 0)
        content:SetWidth(math.max(1, scroll:GetWidth() or 1))
        content:SetHeight(1)
        scroll:SetScrollChild(content)

        scroll:SetScript("OnSizeChanged", function(self)
            if content then
                content:SetWidth(math.max(1, self:GetWidth() or 1))
            end
            ClampTabScroll(tabId)
        end)

        tabScrollFrames[tabId] = scroll
        tabFrames[tabId] = content
    end

    CreateTabBody("character")
    CreateTabBody("reputations")
    CreateTabBody("professions")
    tabScrollFrames.reputations:Hide()
    tabScrollFrames.professions:Hide()

    charRows = { groups = {} }
    repRows = {}
    profRows = {}
    cooldownRows = {}

    local y = -10
    for _, groupDef in ipairs(CHAR_STAT_GROUPS) do
        local group = {}
        group.header = tabFrames.character:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        group.header:SetText(groupDef.header)
        group.header:SetTextColor(unpack(AltTracker.C.TEXT_DIM))
        group.rows = {}

        for _, def in ipairs(groupDef.defs) do
            local row = CreateStatsRow(tabFrames.character, y, def.label)
            row:Hide()
            group.rows[#group.rows + 1] = { row = row, def = def }
            y = y - STAT_ROW_STEP
        end
        group.header:Hide()
        y = y - STAT_SECTION_GAP
        charRows.groups[#charRows.groups + 1] = group
    end

    charNoDataText = tabFrames.character:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    charNoDataText:SetPoint("TOPLEFT", tabFrames.character, "TOPLEFT", 10, -12)
    charNoDataText:SetPoint("RIGHT", tabFrames.character, "RIGHT", -10, 0)
    charNoDataText:SetJustifyH("LEFT")
    charNoDataText:SetTextColor(unpack(AltTracker.C.TEXT_DIM))
    charNoDataText:SetText("")
    charNoDataText:Hide()

    y = -10
    for i, def in ipairs(REP_FIELDS) do
        local row = CreateStatsRow(tabFrames.reputations, y, def.label)
        repRows[i] = row
        y = y - STAT_ROW_STEP
    end
    repNoDataText = tabFrames.reputations:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    repNoDataText:SetPoint("TOPLEFT", tabFrames.reputations, "TOPLEFT", 10, -12)
    repNoDataText:SetPoint("RIGHT", tabFrames.reputations, "RIGHT", -10, 0)
    repNoDataText:SetJustifyH("LEFT")
    repNoDataText:SetTextColor(unpack(AltTracker.C.TEXT_DIM))
    repNoDataText:SetText("No reputation data available.")
    repNoDataText:Hide()

    y = -10
    for i, def in ipairs(PROF_FIELDS) do
        local row = CreateStatsRow(tabFrames.professions, y, def.label)
        profRows[i] = row
        y = y - STAT_ROW_STEP
    end

    profCooldownHeader = tabFrames.professions:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    profCooldownHeader:SetText("Cooldowns")
    profCooldownHeader:SetTextColor(unpack(AltTracker.C.TEXT_DIM))
    profCooldownHeader:Hide()

    y = y - STAT_SECTION_GAP
    for i = 1, COOLDOWN_ROW_POOL do
        local row = CreateStatsRow(tabFrames.professions, y, "")  -- label set dynamically at render
        row:Hide()
        cooldownRows[i] = row
        y = y - STAT_ROW_STEP
    end

    profNoDataText = tabFrames.professions:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    profNoDataText:SetPoint("TOPLEFT", tabFrames.professions, "TOPLEFT", 10, -12)
    profNoDataText:SetPoint("RIGHT", tabFrames.professions, "RIGHT", -10, 0)
    profNoDataText:SetJustifyH("LEFT")
    profNoDataText:SetTextColor(unpack(AltTracker.C.TEXT_DIM))
    profNoDataText:SetText("No profession data available.")
    profNoDataText:Hide()
end

local function BuildDetailPanel()
    detailPanel = CreateFrame("Frame", nil, panel)
    statsPanel = CreateFrame("Frame", nil, detailPanel, "BackdropTemplate")
    detailPanel:SetPoint("TOPLEFT", panel, "TOPLEFT", SELECTOR_W + PANEL_PAD, -PANEL_PAD)
    detailPanel:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -PANEL_PAD, DETAIL_BOTTOM_PAD)

    statsPanel:SetPoint("TOPRIGHT", detailPanel, "TOPRIGHT", 0, 0)
    statsPanel:SetPoint("BOTTOMRIGHT", detailPanel, "BOTTOMRIGHT", 0, 0)
    statsPanel:SetWidth(RIGHT_PANEL_W)
    AltTracker.ApplyBackdrop(statsPanel, AltTracker.C.BG_MAIN[1], AltTracker.C.BG_MAIN[2], AltTracker.C.BG_MAIN[3], 1)

    centerPanel = CreateFrame("Frame", nil, detailPanel, "BackdropTemplate")
    centerPanel:SetPoint("TOPLEFT", detailPanel, "TOPLEFT", 0, 0)
    centerPanel:SetPoint("BOTTOMLEFT", detailPanel, "BOTTOMLEFT", 0, 0)
    centerPanel:SetPoint("RIGHT", statsPanel, "LEFT", -CENTER_PANEL_GAP, 0)
    AltTracker.ApplyBackdrop(centerPanel, AltTracker.C.BG_MAIN[1], AltTracker.C.BG_MAIN[2], AltTracker.C.BG_MAIN[3], 1)

    local centerDivider = centerPanel:CreateTexture(nil, "OVERLAY")
    centerDivider:SetWidth(1)
    centerDivider:SetPoint("TOPRIGHT", centerPanel, "TOPRIGHT", 0, 0)
    centerDivider:SetPoint("BOTTOMRIGHT", centerPanel, "BOTTOMRIGHT", 0, 0)
    centerDivider:SetColorTexture(unpack(AltTracker.C.SEP))

    centerModelHost = CreateFrame("Frame", nil, centerPanel, "BackdropTemplate")
    centerModelHost:SetPoint("TOPLEFT", centerPanel, "TOPLEFT", CENTER_IDENTITY_INSET_X, -CENTER_IDENTITY_TOP_Y)
    centerModelHost:SetPoint("TOPRIGHT", centerPanel, "TOPRIGHT", -CENTER_IDENTITY_INSET_X, -CENTER_IDENTITY_TOP_Y)
    centerModelHost:SetPoint("BOTTOM", centerPanel, "TOP", 0, -CENTER_IDENTITY_BOTTOM_Y)
    AltTracker.ApplyBackdrop(centerModelHost, 0.08, 0.08, 0.08, 0.92)

    do
        local ok, model = pcall(CreateFrame, "DressUpModel", nil, centerModelHost)
        if ok and model then
            centerModelFrame = model
        else
            centerModelFrame = CreateFrame("PlayerModel", nil, centerModelHost)
        end
    end
    centerModelFrame:SetAllPoints(centerModelHost)
    centerModelFrame:Hide()

    centerRenderFrame = CreateFrame("Frame", nil, centerPanel, "BackdropTemplate")
    centerRenderFrame:SetPoint("TOPLEFT", centerPanel, "TOPLEFT", 1, -1)
    centerRenderFrame:SetPoint("BOTTOMRIGHT", centerPanel, "BOTTOMRIGHT", -1, 1)
    centerRenderFrame:SetFrameLevel((centerPanel:GetFrameLevel() or 1) + 1)
    centerRenderFrame:EnableMouse(false)
    AltTracker.ApplyBGOnly(centerRenderFrame, 0.03, 0.03, 0.03, 0.98)
    centerRenderFrame:Hide()

    centerRenderFrame.clipFrame = CreateFrame("Frame", nil, centerRenderFrame)
    centerRenderFrame.clipFrame:SetAllPoints(centerRenderFrame)
    centerRenderFrame.clipFrame:EnableMouse(false)
    centerRenderFrame.canClip = false
    if centerRenderFrame.clipFrame.SetClipsChildren then
        local ok = pcall(centerRenderFrame.clipFrame.SetClipsChildren, centerRenderFrame.clipFrame, true)
        centerRenderFrame.canClip = ok and true or false
    end

    centerRenderFrame.animFrame = CreateFrame("Frame", nil, centerRenderFrame.clipFrame)
    centerRenderFrame.animFrame:SetAllPoints(centerRenderFrame.clipFrame)
    centerRenderFrame.animFrame:EnableMouse(false)
    centerRenderFrame.animFrame:SetScale(renderLayout.HERO_ANIM_END_SCALE)
    centerRenderFrame.animFrame:SetAlpha(renderLayout.HERO_ANIM_END_ALPHA)

    centerRenderTexture = centerRenderFrame.animFrame:CreateTexture(nil, "ARTWORK")
    centerRenderTexture:SetTexture(nil)
    centerRenderTexture:SetTexCoord(0, 1, 0, 1)
    centerRenderTexture:SetAllPoints(centerRenderFrame.animFrame)

    local renderOverlay = centerRenderFrame:CreateTexture(nil, "OVERLAY")
    renderOverlay:SetAllPoints(centerRenderFrame)
    renderOverlay:SetColorTexture(0.05, 0.05, 0.05, 0.33)

    centerRenderFrame:SetScript("OnSizeChanged", function()
        LayoutCenterRenderTexture()
    end)
    LayoutCenterRenderTexture()

    centerIdentityPanel = CreateFrame("Frame", nil, centerModelHost, "BackdropTemplate")
    centerIdentityPanel:SetAllPoints(centerModelHost)
    AltTracker.ApplyBGOnly(centerIdentityPanel, AltTracker.C.BG_MAIN[1], AltTracker.C.BG_MAIN[2], AltTracker.C.BG_MAIN[3], 0.88)

    centerClassIcon = centerIdentityPanel:CreateTexture(nil, "ARTWORK")
    centerClassIcon:SetSize(64, 64)
    centerClassIcon:SetPoint("TOP", centerIdentityPanel, "TOP", 0, -16)
    centerClassIcon:SetTexture(ClassIconPath("WARRIOR"))
    centerClassIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    centerNameText = centerIdentityPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    centerNameText:SetPoint("TOP", centerClassIcon, "BOTTOM", 0, -8)
    centerNameText:SetText("No character selected")

    centerMetaText = centerIdentityPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    centerMetaText:SetPoint("TOP", centerNameText, "BOTTOM", 0, -4)
    centerMetaText:SetTextColor(unpack(AltTracker.C.TEXT_NORM))
    centerMetaText:SetText("")

    centerGuildText = centerIdentityPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    centerGuildText:SetPoint("TOP", centerMetaText, "BOTTOM", 0, -5)
    centerGuildText:SetTextColor(unpack(AltTracker.C.TEXT_DIM))
    centerGuildText:SetText("")

    centerRaceText = centerIdentityPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    centerRaceText:SetPoint("TOP", centerGuildText, "BOTTOM", 0, -2)
    centerRaceText:SetTextColor(unpack(AltTracker.C.TEXT_DIM))
    centerRaceText:SetText("")

    local badgeILvl = CreateFrame("Frame", nil, centerIdentityPanel, "BackdropTemplate")
    badgeILvl:SetSize(66, 34)
    badgeILvl:SetPoint("TOP", centerRaceText, "BOTTOM", -38, -10)
    AltTracker.ApplyBackdrop(badgeILvl, 0.10, 0.10, 0.10, 0.95)

    local badgeILabel = badgeILvl:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    badgeILabel:SetPoint("TOP", badgeILvl, "TOP", 0, -5)
    badgeILabel:SetText("iLvl")
    badgeILabel:SetTextColor(unpack(AltTracker.C.TEXT_DIM))

    centerILvlBadgeValue = badgeILvl:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    centerILvlBadgeValue:SetPoint("TOP", badgeILabel, "BOTTOM", 0, -1)
    centerILvlBadgeValue:SetTextColor(0.95, 0.95, 0.95)
    centerILvlBadgeValue:SetText("-")

    local badgeGS = CreateFrame("Frame", nil, centerIdentityPanel, "BackdropTemplate")
    badgeGS:SetSize(66, 34)
    badgeGS:SetPoint("TOP", centerRaceText, "BOTTOM", 38, -10)
    AltTracker.ApplyBackdrop(badgeGS, 0.10, 0.10, 0.10, 0.95)

    local badgeGLabel = badgeGS:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    badgeGLabel:SetPoint("TOP", badgeGS, "TOP", 0, -5)
    badgeGLabel:SetText("GS")
    badgeGLabel:SetTextColor(unpack(AltTracker.C.TEXT_DIM))

    centerGSBadgeValue = badgeGS:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    centerGSBadgeValue:SetPoint("TOP", badgeGLabel, "BOTTOM", 0, -1)
    centerGSBadgeValue:SetTextColor(0.95, 0.95, 0.95)
    centerGSBadgeValue:SetText("-")

    centerSummaryText = centerIdentityPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    centerSummaryText:SetPoint("TOP", badgeILvl, "BOTTOM", 38, -10)
    centerSummaryText:SetWidth(230)
    centerSummaryText:SetJustifyH("CENTER")
    centerSummaryText:SetTextColor(unpack(AltTracker.C.TEXT_NORM))
    centerSummaryText:SetText("")

    centerLastSeenText = centerIdentityPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    centerLastSeenText:SetPoint("TOP", centerSummaryText, "BOTTOM", 0, -4)
    centerLastSeenText:SetWidth(230)
    centerLastSeenText:SetJustifyH("CENTER")
    centerLastSeenText:SetTextColor(unpack(AltTracker.C.TEXT_DIM))
    centerLastSeenText:SetText("")

    centerModelStatusText = centerPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    centerModelStatusText:SetPoint("BOTTOM", centerPanel, "BOTTOM", 0, 6)
    centerModelStatusText:SetTextColor(unpack(AltTracker.C.TEXT_DIM))
    centerModelStatusText:SetText("")
    centerModelStatusText:Hide()

    for i, key in ipairs(GEAR_LEFT) do
        local btn = CreateGearButton(centerPanel, key)
        btn:SetPoint("TOPLEFT", centerPanel, "TOPLEFT", GEAR_COLUMN_X, -(GEAR_TOP_Y + (i - 1) * GEAR_SLOT_SPACING))
        gearButtons[key] = btn
    end
    for i, key in ipairs(GEAR_RIGHT) do
        local btn = CreateGearButton(centerPanel, key)
        btn:SetPoint("TOPRIGHT", centerPanel, "TOPRIGHT", -GEAR_COLUMN_X, -(GEAR_TOP_Y + (i - 1) * GEAR_SLOT_SPACING))
        gearButtons[key] = btn
    end
    for i, key in ipairs(GEAR_BOTTOM) do
        local btn = CreateGearButton(centerPanel, key)
        btn:SetPoint("TOP", centerPanel, "TOP", -GEAR_BOTTOM_SPACING + (i - 1) * GEAR_BOTTOM_SPACING, -GEAR_BOTTOM_Y)
        gearButtons[key] = btn
    end

    statsNameText = statsPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    statsNameText:SetPoint("TOPLEFT", statsPanel, "TOPLEFT", 10, -10)
    statsNameText:SetText("No character selected")

    statsMetaText = statsPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    statsMetaText:SetPoint("TOPLEFT", statsNameText, "BOTTOMLEFT", 0, -4)
    statsMetaText:SetTextColor(unpack(AltTracker.C.TEXT_NORM))

    statsGuildText = statsPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    statsGuildText:SetPoint("TOPLEFT", statsMetaText, "BOTTOMLEFT", 0, -5)
    statsGuildText:SetTextColor(unpack(AltTracker.C.TEXT_DIM))

    local ilvlLabel = statsPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    ilvlLabel:SetPoint("TOPRIGHT", statsPanel, "TOPRIGHT", -42, -20)
    ilvlLabel:SetText("iLvl")
    ilvlLabel:SetTextColor(unpack(AltTracker.C.TEXT_DIM))

    statsILvlText = statsPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    statsILvlText:SetPoint("TOP", ilvlLabel, "BOTTOM", 0, -2)
    statsILvlText:SetTextColor(0.95, 0.95, 0.95)
    statsILvlText:SetText("-")

    local gsLabel = statsPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    gsLabel:SetPoint("TOP", statsILvlText, "BOTTOM", 0, -4)
    gsLabel:SetText("GS")
    gsLabel:SetTextColor(unpack(AltTracker.C.TEXT_DIM))

    statsGSText = statsPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    statsGSText:SetPoint("TOP", gsLabel, "BOTTOM", 0, -1)
    statsGSText:SetTextColor(0.95, 0.95, 0.95)
    statsGSText:SetText("-")

    BuildTabs()
end

local function BuildSelectorPanel()
    selectorPanel = CreateFrame("Frame", nil, panel, "BackdropTemplate")
    selectorPanel:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, 0)
    selectorPanel:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 0, 22)
    selectorPanel:SetWidth(SELECTOR_W)
    AltTracker.ApplyBackdrop(selectorPanel, AltTracker.C.BG_SIDEBAR[1], AltTracker.C.BG_SIDEBAR[2], AltTracker.C.BG_SIDEBAR[3], 1)

    local title = selectorPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", selectorPanel, "TOPLEFT", 10, -9)
    title:SetText("Roster")
    local tr, tg, tb = AltTracker.GetAccentRGB()
    title:SetTextColor(tr, tg, tb)

    local div = selectorPanel:CreateTexture(nil, "ARTWORK")
    div:SetHeight(1)
    div:SetPoint("TOPLEFT", selectorPanel, "TOPLEFT", 0, -28)
    div:SetPoint("TOPRIGHT", selectorPanel, "TOPRIGHT", 0, -28)
    div:SetColorTexture(unpack(AltTracker.C.SEP))

    selectorScroll = CreateFrame("ScrollFrame", nil, selectorPanel)
    selectorScroll:SetPoint("TOPLEFT", selectorPanel, "TOPLEFT", 2, -30)
    selectorScroll:SetPoint("BOTTOMRIGHT", selectorPanel, "BOTTOMRIGHT", -4, -2)
    selectorScroll:EnableMouseWheel(true)
    selectorScroll:SetScript("OnMouseWheel", function(self, delta)
        local cur = self:GetVerticalScroll()
        local step = SELECTOR_ROW_H * 2
        local max = math.max(0, selectorContent:GetHeight() - self:GetHeight())
        local newOffset = math.max(0, math.min(cur - delta * step, max))
        self:SetVerticalScroll(newOffset)
    end)

    selectorContent = CreateFrame("Frame", nil, selectorScroll)
    selectorContent:SetSize(math.max(1, selectorScroll:GetWidth()), 1)
    selectorScroll:SetScrollChild(selectorContent)
    selectorScroll:SetScript("OnSizeChanged", function(self)
        if selectorContent then
            selectorContent:SetWidth(math.max(1, self:GetWidth()))
        end
    end)
end

local function BuildFooter()
    footerBar = CreateFrame("Frame", nil, panel, "BackdropTemplate")
    footerBar:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 0, 0)
    footerBar:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", 0, 0)
    footerBar:SetHeight(22)
    AltTracker.ApplyBGOnly(footerBar, AltTracker.C.BG_FOOTER[1], AltTracker.C.BG_FOOTER[2], AltTracker.C.BG_FOOTER[3], AltTracker.C.BG_FOOTER[4])

    local line = footerBar:CreateTexture(nil, "OVERLAY")
    line:SetHeight(1)
    line:SetPoint("TOPLEFT", footerBar, "TOPLEFT", 0, 0)
    line:SetPoint("TOPRIGHT", footerBar, "TOPRIGHT", 0, 0)
    line:SetColorTexture(unpack(AltTracker.C.SEP))

    footerLeft = footerBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    footerLeft:SetPoint("LEFT", footerBar, "LEFT", 10, 0)
    footerLeft:SetTextColor(unpack(AltTracker.C.TEXT_NORM))

    footerMid = footerBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    footerMid:SetPoint("CENTER", footerBar, "CENTER", 0, 0)
    footerMid:SetTextColor(unpack(AltTracker.C.TEXT_DIM))

    footerRight = footerBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    footerRight:SetPoint("RIGHT", footerBar, "RIGHT", -10, 0)
    footerRight:SetJustifyH("RIGHT")
    footerRight:SetTextColor(unpack(AltTracker.C.TEXT_NORM))
end

local function BuildPanel(mainFrame)
    if panel then return end

    local sidebarW = (AltTracker.LAYOUT and AltTracker.LAYOUT.SIDEBAR_WIDTH) or 230
    local titleH = (AltTracker.LAYOUT and AltTracker.LAYOUT.TITLE_H) or 30

    panel = CreateFrame("Frame", nil, mainFrame, "BackdropTemplate")
    panel:SetPoint("TOPLEFT", mainFrame, "TOPLEFT", sidebarW + 1, -titleH)
    panel:SetPoint("BOTTOMRIGHT", mainFrame, "BOTTOMRIGHT", 0, 1)
    AltTracker.ApplyBGOnly(panel, AltTracker.C.BG_MAIN[1], AltTracker.C.BG_MAIN[2], AltTracker.C.BG_MAIN[3], AltTracker.C.BG_MAIN[4])
    panel:Hide()

    BuildSelectorPanel()
    BuildFooter()
    BuildDetailPanel()

    -- Scene ("Campsite") view module. Pass the narrow set of file-local helpers it
    -- needs as callbacks so the module (a separate chunk) stays decoupled.
    if AltTracker.RosterScene then
        AltTracker.RosterScene.Build(detailPanel, {
            resolvePortrait = function(char)
                local candidates = CollectRenderCandidates(char)
                local c = candidates and candidates[1]
                if c and c.path then return c.path, c.sourceWidth, c.sourceHeight end
            end,
            resolveCutout = function(char)
                if type(AltTrackerSceneManifest) ~= "table" then return nil end
                local entry = AltTrackerSceneManifest[BuildManifestLookupKey(char)]
                if not entry or not entry.image then return nil end
                return NormalizeManifestImagePath(entry.image), tonumber(entry.width), tonumber(entry.height)
            end,
            classIconPath = ClassIconPath,
            classDisplay  = function(token) return CLASS_DISPLAY[(token or ""):upper()] end,
            raceDisplay   = function(char) return char and (RACE_DISPLAY[char.race or ""] or char.race) or nil end,
            onSelect = function(guid)
                selectedGuid = guid
                AltTrackerRosterDB.selectedGuid = guid
                AT_ALTS.Refresh()
            end,
            openDetails = function(guid)
                selectedGuid = guid
                AltTrackerRosterDB.selectedGuid = guid
                AT_ALTS.SetViewMode("list")  -- jump to the List view focused on this character
            end,
        })
    end

    -- List / Scene toggle in the selector header (right-aligned, above the divider).
    do
        local defs = { { id = "list", label = "List" }, { id = "scene", label = "Scene" } }
        AT_ALTS._viewButtons = AT_ALTS._viewButtons or {}
        local BTN_W, BTN_H, GAP = 46, 18, 3
        for i, d in ipairs(defs) do
            local btn = CreateFrame("Button", nil, selectorPanel, "BackdropTemplate")
            btn:SetSize(BTN_W, BTN_H)
            btn:SetPoint("TOPRIGHT", selectorPanel, "TOPRIGHT", -6 - (#defs - i) * (BTN_W + GAP), -6)
            btn.label = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            btn.label:SetPoint("CENTER", btn, "CENTER", 0, 0)
            btn.label:SetText(d.label)
            btn:SetScript("OnClick", function() AT_ALTS.SetViewMode(d.id) end)
            AT_ALTS._viewButtons[d.id] = btn
        end
    end

    if not AT_ALTS._themeCallbackRegistered then
        AltTracker.RegisterThemeCallback(function()
            if not panel then return end
            UpdateFooter()
            local ui = GetUIState()
            SetActiveTab(ui.activeTab or "character")
            RenderSelector()
            AT_ALTS._UpdateViewToggle()
            if AltTracker.RosterScene then AltTracker.RosterScene.RepaintTheme() end
        end)
        AT_ALTS._themeCallbackRegistered = true
    end
end

local function HookRefresh()
    if AT_ALTS._refreshHooked then return end
    if type(AltTracker.RefreshSheet) ~= "function" then return end

    local prev = AltTracker.RefreshSheet
    AltTracker.RefreshSheet = function(...)
        prev(...)
        -- Coalesce bursts of RefreshSheet events into a single deferred repaint
        -- (scene mode lays out several large textures, so avoid re-doing it N times).
        if AT_ALTS.isActive and not AT_ALTS._refreshPending then
            AT_ALTS._refreshPending = true
            C_Timer.After(0, function()
                AT_ALTS._refreshPending = false
                if AT_ALTS.isActive then
                    AT_ALTS.Refresh()
                end
            end)
        end
    end
    AT_ALTS._refreshHooked = true
end

function AT_ALTS.Activate(mainFrame)
    BuildPanel(mainFrame)
    HookRefresh()

    AT_ALTS.isActive = true
    AT_ALTS._lastDetailSelectionKey = nil

    if mainFrame.bodyScroll   then mainFrame.bodyScroll:Hide()   end
    if mainFrame.frozenScroll then mainFrame.frozenScroll:Hide() end
    if mainFrame.headerScroll then mainFrame.headerScroll:Hide() end
    if mainFrame.frozenHeader then mainFrame.frozenHeader:Hide() end
    if mainFrame.hScrollBar   then mainFrame.hScrollBar:Hide()   end
    if mainFrame.totalsBar    then mainFrame.totalsBar:Hide()    end

    local f = _G["AltTrackerSheet"]
    if f then f:SetSize(1120, 560) end

    panel:Show()
    local ui = GetUIState()
    SetActiveTab(ui.activeTab or "character")
    AT_ALTS.ApplyViewMode()
    AT_ALTS.Refresh()
end

function AT_ALTS.Deactivate(mainFrame)
    AT_ALTS.isActive = false
    if panel then panel:Hide() end

    if mainFrame.bodyScroll   then mainFrame.bodyScroll:Show()   end
    if mainFrame.frozenScroll then mainFrame.frozenScroll:Show() end
    if mainFrame.headerScroll then mainFrame.headerScroll:Show() end
    if mainFrame.frozenHeader then mainFrame.frozenHeader:Show() end
    if mainFrame.hScrollBar   then mainFrame.hScrollBar:Show()   end
    if mainFrame.totalsBar    then mainFrame.totalsBar:Show()    end
end

-- Registers this plugin with AltTracker. Normally driven by PLAYER_LOGIN,
-- but also fired immediately when the addon is loaded on demand *after*
-- login (LoadOnDemand), when PLAYER_LOGIN would never arrive again.
-- Attached to AT_ALTS (an existing table) rather than a new top-level local:
-- this chunk sits right at Lua 5.1's 200-locals-per-function limit.
function AT_ALTS._Bootstrap()
    if not AltTracker or not AltTracker.RegisterPlugin then
        DEFAULT_CHAT_FRAME:AddMessage("|cff00ccff[AltTracker Roster]|r AltTracker not found.")
        return
    end

    HookRefresh()

    AltTracker.RegisterPlugin({
        id           = ADDON_ID,
        label        = "Roster",
        icon         = "Interface\\AddOns\\AltTrackerRoster\\Media\\Icons\\roster.tga",
        _isPlugin    = true,
        OnActivate   = function(mainFrame) AT_ALTS.Activate(mainFrame) end,
        OnDeactivate = function(mainFrame) AT_ALTS.Deactivate(mainFrame) end,
    })
end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:SetScript("OnEvent", function(_, event)
    if event ~= "PLAYER_LOGIN" then return end
    C_Timer.After(1, AT_ALTS._Bootstrap)
end)

-- Loaded on demand after login: PLAYER_LOGIN already fired, so bootstrap now.
if IsLoggedIn() then
    C_Timer.After(1, AT_ALTS._Bootstrap)
end

