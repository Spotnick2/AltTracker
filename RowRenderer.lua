AltTracker = AltTracker or {}

------------------------------------------------------------
-- Profession icons
------------------------------------------------------------

local PROF_ICONS = {
    Alchemy        = "|TInterface\\Icons\\Trade_Alchemy:14:14:0:0|t",
    Blacksmithing  = "|TInterface\\Icons\\Trade_BlackSmithing:14:14:0:0|t",
    Enchanting     = "|TInterface\\Icons\\Trade_Engraving:14:14:0:0|t",
    Engineering    = "|TInterface\\Icons\\Trade_Engineering:14:14:0:0|t",
    Herbalism      = "|TInterface\\Icons\\Trade_Herbalism:14:14:0:0|t",
    Leatherworking = "|TInterface\\Icons\\Trade_LeatherWorking:14:14:0:0|t",
    Mining         = "|TInterface\\Icons\\Trade_Mining:14:14:0:0|t",
    Skinning       = "|TInterface\\Icons\\INV_Misc_Pelt_Wolf_01:14:14:0:0|t",
    Tailoring      = "|TInterface\\Icons\\Trade_Tailoring:14:14:0:0|t",
    Jewelcrafting  = "|TInterface\\Icons\\INV_Misc_Gem_01:14:14:0:0|t",
}

------------------------------------------------------------
-- Class icons
------------------------------------------------------------

local CLASS_DISPLAY = {
    WARRIOR="Warrior", PALADIN="Paladin", HUNTER="Hunter",
    ROGUE="Rogue", PRIEST="Priest", DEATHKNIGHT="Death Knight",
    SHAMAN="Shaman", MAGE="Mage", WARLOCK="Warlock", DRUID="Druid",
}

local function ClassIconText(class)
    if not class then return "" end
    -- ClassIcon_Warrior, ClassIcon_Paladin, etc. — these are portrait atlas icons
    -- capitalized exactly as stored in Interface\Icons\
    local name = class:sub(1,1):upper() .. class:sub(2):lower()
    return "|TInterface\\Icons\\ClassIcon_"..name..":18:18|t"
end

------------------------------------------------------------
-- Race icons — Achievement_Character_Race_Gender
-- Race names in the file system are title-cased with specific spellings.
------------------------------------------------------------

local RACE_FS = {
    -- file system name (may differ from UnitRace internal name)
    Human="Human", Dwarf="Dwarf", Gnome="Gnome",
    NightElf="Nightelf", Draenei="Draenei",
    Orc="Orc", Troll="Troll", Tauren="Tauren",
    Scourge="Undead", BloodElf="Bloodelf", Goblin="Goblin",
}

local RACE_DISPLAY = {
    Human="Human", Dwarf="Dwarf", Gnome="Gnome", NightElf="Night Elf",
    Draenei="Draenei", Orc="Orc", Troll="Troll", Tauren="Tauren",
    Scourge="Undead", BloodElf="Blood Elf", Goblin="Goblin",
}

local function RaceIconText(race, gender)
    local fs = race and RACE_FS[race]
    if not fs then return "" end
    local g = (gender == "Female") and "Female" or "Male"
    return "|TInterface\\Icons\\Achievement_Character_"..fs.."_"..g..":18:18|t"
end

------------------------------------------------------------
-- Spec icon
------------------------------------------------------------

local function SpecIconText(specIcon)
    if not specIcon or specIcon == "" or specIcon == 0 then return "" end
    -- specIcon can be a numeric fileID or a path string — both work with |T
    return "|T"..tostring(specIcon)..":18:18|t"
end

------------------------------------------------------------
-- Race display — atlas-based icons (raceicon-name-gender)
-- Atlas names from ChatLinkIcons addon reference
------------------------------------------------------------

local RACE_ATLAS = {
    Human="human", Dwarf="dwarf", Gnome="gnome", NightElf="nightelf",
    Draenei="draenei", Orc="orc", Troll="troll", Tauren="tauren",
    Scourge="undead", BloodElf="bloodelf", Goblin="goblin",
}

local function RaceIconText(race, gender)
    local atlas = race and RACE_ATLAS[race]
    if not atlas then return "" end
    local g = (gender == "Female") and "female" or "male"
    return "|A:raceicon-"..atlas.."-"..g..":18:18|a"
end

------------------------------------------------------------
-- BiS lookup
-- Returns the tier name(s) for which an item is BiS, or nil.
------------------------------------------------------------

------------------------------------------------------------
-- BiS lookup
-- Returns the tier name(s) for which an item is BiS, or nil.
------------------------------------------------------------

local function IsItemBis(class, spec, slotKey, itemName)
    if not itemName or itemName == "" then return nil end
    if not class or not spec then return nil end

    local bisData = AltTracker.BisData
    if not bisData then return nil end

    local classData = bisData[class]
    if not classData then return nil end

    local specData = classData[spec]
    if not specData then return nil end

    -- Check each tier for this spec
    local matchedTiers = {}
    local TIER_ORDER = {"T4", "T5", "T6", "Sunwell"}
    for _, tier in ipairs(TIER_ORDER) do
        local tierData = specData[tier]
        if tierData and tierData[slotKey] then
            local items = tierData[slotKey]
            if type(items) == "string" then
                if items == itemName then
                    table.insert(matchedTiers, tier)
                end
            elseif type(items) == "table" then
                for _, bisName in ipairs(items) do
                    if bisName == itemName then
                        table.insert(matchedTiers, tier)
                        break
                    end
                end
            end
        end
    end

    if #matchedTiers > 0 then
        return table.concat(matchedTiers, ", ")
    end
    return nil
end

------------------------------------------------------------
-- BiS count for a character
-- Returns: displayCount, colorRatio (0-1)
-- 2H weapons count as 2 slots for the color ratio
-- (since they occupy mainhand+offhand) but 1 for display.
------------------------------------------------------------

local ALL_GEAR_KEYS = {
    "head","neck","shoulder","back","chest","wrist","hands",
    "waist","legs","feet","ring1","ring2","trinket1","trinket2",
    "mainhand","offhand","ranged",
}
local MAX_GEAR_SLOTS = #ALL_GEAR_KEYS  -- 17

local function CountBisItems(char)
    if not char or not char.class or not char.spec then return 0, 0 end
    local count = 0
    for _, slotKey in ipairs(ALL_GEAR_KEYS) do
        local itemName = char["gearname_"..slotKey] or ""
        if IsItemBis(char.class, char.spec, slotKey, itemName) then
            count = count + 1
        end
    end
    -- 2H weapon bonus: if mainhand is BiS and offhand is empty, count +1 for color
    local colorCount = count
    local ohIlvl = char.gear_offhand or 0
    local mhName = char.gearname_mainhand or ""
    if ohIlvl == 0 and IsItemBis(char.class, char.spec, "mainhand", mhName) then
        colorCount = colorCount + 1
    end
    local ratio = colorCount / MAX_GEAR_SLOTS
    return count, math.min(ratio, 1.0)
end

------------------------------------------------------------
-- BiS count gradient: grey (0) → white → green → orange
------------------------------------------------------------

local function BisCountColor(ratio)
    local function lerp(c1, c2, t)
        t = math.max(0, math.min(1, t))
        return {
            r = c1.r + (c2.r - c1.r) * t,
            g = c1.g + (c2.g - c1.g) * t,
            b = c1.b + (c2.b - c1.b) * t,
        }
    end
    local GREY   = { r=0.50, g=0.50, b=0.50 }
    local WHITE  = { r=1.00, g=1.00, b=1.00 }
    local GREEN  = { r=0.12, g=1.00, b=0.00 }
    local ORANGE = { r=1.00, g=0.50, b=0.00 }

    if     ratio >= 0.85 then return lerp(GREEN,  ORANGE, (ratio - 0.85) / 0.15)
    elseif ratio >= 0.50 then return lerp(WHITE,  GREEN,  (ratio - 0.50) / 0.35)
    elseif ratio >= 0.15 then return lerp(GREY,   WHITE,  (ratio - 0.15) / 0.35)
    else                      return GREY
    end
end

------------------------------------------------------------
-- Reputation
------------------------------------------------------------

local REP_TEXT = {
    [1]="Hated",   [2]="Hostile",    [3]="Unfriendly",
    [4]="Neutral", [5]="Friendly",   [6]="Honored",
    [7]="Revered", [8]="Exalted",
}
local REP_TEXT_SHORT = {
    [1]="X", [2]="X", [3]="U",
    [4]="N", [5]="F", [6]="H",
    [7]="R", [8]="E",
}
local REP_COLOR = {
    [1]="|cffcc0000",[2]="|cffff0000",[3]="|cffff6600",
    [4]="|cffffff00",[5]="|cff66ff66",[6]="|cff00ff00",
    [7]="|cff00ffcc",[8]="|cff00ffff",
}

------------------------------------------------------------
-- Money icons
------------------------------------------------------------

local GOLD_ICON   = "|TInterface\\MoneyFrame\\UI-GoldIcon:14:14:2:0|t"
local SILVER_ICON = "|TInterface\\MoneyFrame\\UI-SilverIcon:14:14:2:0|t"
local COPPER_ICON = "|TInterface\\MoneyFrame\\UI-CopperIcon:14:14:2:0|t"
local GOLD_ICON_SM= "|TInterface\\MoneyFrame\\UI-GoldIcon:12:12:2:0|t"

------------------------------------------------------------
-- Format helpers  (all local, also used by frozen row renderer)
------------------------------------------------------------

local function ClassColor(class)
    if not class or not RAID_CLASS_COLORS then return "|cffffffff" end
    local c = RAID_CLASS_COLORS[class] or {r=1,g=1,b=1}
    return string.format("|cff%02x%02x%02x", c.r*255, c.g*255, c.b*255)
end
AltTracker.ClassColor = ClassColor   -- expose for SheetUI frozen rows

local function FormatReputation(v)
    if not v then return "" end
    return (REP_COLOR[v] or "|cffffffff")..(REP_TEXT_SHORT[v] or "").." |r"
end

local function FormatMoney(copper)
    if not copper then return "" end
    local g=floor(copper/10000); local s=floor((copper%10000)/100); local c=copper%100
    return string.format("%d%s %d%s %d%s",g,GOLD_ICON,s,SILVER_ICON,c,COPPER_ICON)
end

local function FormatMoneySmall(copper)
    if not copper then return "" end
    return math.floor(copper/10000)..GOLD_ICON_SM
end

local function FormatMax(value, max)
    if not value then return "" end
    if max and max>0 and value>=max then return "|cffffd100"..value.."|r" end
    return tostring(value)
end

local function FormatProfession(name, skill, max)
    if not name or name=="" then return "" end
    local icon = PROF_ICONS[name] or ""
    return string.format("%s %s %s/%s", icon, name, FormatMax(skill,max), max or "")
end

------------------------------------------------------------
-- iLvl gradient — smooth interpolation between WoW quality
-- colours, capping at Epic (purple).
--
-- Below purple: grey → white → green → blue
-- Within purple: muted purple → rich purple, scaled to the
-- current raid tier ceiling so each phase's gear is visually
-- distinct.
--
-- Update ILVL_CEILING each phase — the purple sub-gradient
-- rescales automatically.  Orange is reserved for legendary
-- item quality in gear slots only (see FormatGearIlvl).
------------------------------------------------------------

-- *** TUNE THIS VALUE EACH PHASE ***
-- Set to the highest epic ilvl available in the current tier.
-- T4 = 125, T5 = 141, T6 = 154, Sunwell = 164
local ILVL_CEILING = 164

-- Fixed breakpoints for the quality colour ramp
local ILVL_POOR     = 60   -- below: grey
local ILVL_COMMON   = 80   -- grey → white ends here
local ILVL_UNCOMMON = 100  -- white → green ends here
local ILVL_RARE     = 115  -- green → blue ends here
local ILVL_EPIC     = 125  -- blue → purple starts here (T4 entry)

local function LerpColor(c1, c2, t)
    t = math.max(0, math.min(1, t))
    return {
        r = c1.r + (c2.r - c1.r) * t,
        g = c1.g + (c2.g - c1.g) * t,
        b = c1.b + (c2.b - c1.b) * t,
    }
end

local function IlvlToColor(ilvl)
    -- Colour anchors
    local GREY       = { r=0.62, g=0.62, b=0.62 }
    local WHITE      = { r=1.00, g=1.00, b=1.00 }
    local GREEN      = { r=0.12, g=1.00, b=0.00 }
    local BLUE       = { r=0.00, g=0.44, b=0.87 }
    -- Purple sub-gradient: muted at T4, rich/vivid at ceiling
    local PURPLE_LOW  = { r=0.47, g=0.20, b=0.73 }  -- #7833BA muted blue-purple
    local PURPLE_HIGH = { r=0.78, g=0.30, b=1.00 }  -- #C74DFF vivid rich purple

    if     ilvl >= ILVL_CEILING then return PURPLE_HIGH
    elseif ilvl >= ILVL_EPIC    then return LerpColor(PURPLE_LOW, PURPLE_HIGH, (ilvl - ILVL_EPIC) / (ILVL_CEILING - ILVL_EPIC))
    elseif ilvl >= ILVL_RARE    then return LerpColor(BLUE,       PURPLE_LOW,  (ilvl - ILVL_RARE) / (ILVL_EPIC - ILVL_RARE))
    elseif ilvl >= ILVL_UNCOMMON then return LerpColor(GREEN,      BLUE,        (ilvl - ILVL_UNCOMMON) / (ILVL_RARE - ILVL_UNCOMMON))
    elseif ilvl >= ILVL_COMMON  then return LerpColor(WHITE,      GREEN,       (ilvl - ILVL_COMMON) / (ILVL_UNCOMMON - ILVL_COMMON))
    elseif ilvl >= ILVL_POOR   then return LerpColor(GREY,       WHITE,       (ilvl - ILVL_POOR) / (ILVL_COMMON - ILVL_POOR))
    else                            return GREY
    end
end

local function FormatItemLevel(ilvl)
    if not ilvl then return "" end
    local c = IlvlToColor(ilvl)
    return string.format("|cff%02x%02x%02x%.1f|r", c.r*255, c.g*255, c.b*255, ilvl)
end

local function FormatSecondarySkill(value, max)
    -- 1 is the untrained default in TBC — treat it the same as 0
    if not value or value <= 1 then return "" end
    return FormatMax(value, max) .. "/" .. (max or "")
end

local function FormatLastOnline(ts, isCurrentPlayer)
    if not ts or ts==0 then return "|cff888888--|r" end
    local diff = time()-ts
    -- Only show "Online" for the character we're actually logged in as
    if isCurrentPlayer and diff<300 then return "|cff00ff00Online|r" end
    if     diff<3600     then return "|cff88ff88"..math.floor(diff/60).."m ago|r"
    elseif diff<86400    then return "|cffffff88"..math.floor(diff/3600).."h ago|r"
    elseif diff<86400*7  then return "|cffaaaaaa"..math.floor(diff/86400).." days|r"
    elseif diff<86400*30 then return "|cff888888"..math.floor(diff/(86400*7)).." weeks|r"
    else                      return "|cff666666"..math.floor(diff/86400).." days|r"
    end
end

------------------------------------------------------------
-- Gear slot coloring — standard WoW item quality colors
--   0 Poor      : grey
--   1 Common    : white
--   2 Uncommon  : green
--   3 Rare      : blue
--   4 Epic      : purple
--   5 Legendary : orange
------------------------------------------------------------

local QUALITY_COLORS = {
    [0] = "|cff9d9d9d",  -- grey   (Poor)
    [1] = "|cffffffff",  -- white  (Common)
    [2] = "|cff1eff00",  -- green  (Uncommon)
    [3] = "|cff0070dd",  -- blue   (Rare)
    [4] = "|cffa335ee",  -- purple (Epic)
    [5] = "|cffff8000",  -- orange (Legendary)
}

local function FormatGearIlvl(slotIlvl, slotQuality)
    if not slotIlvl or slotIlvl == 0 then
        return "|cff444444--|r"
    end
    local v = math.floor(slotIlvl)
    -- Legendary items keep their orange — everything else uses the ilvl gradient
    if slotQuality == 5 then
        return "|cffff8000"..v.."|r"
    end
    local c = IlvlToColor(slotIlvl)
    return string.format("|cff%02x%02x%02x%d|r", c.r*255, c.g*255, c.b*255, v)
end

------------------------------------------------------------
-- Shared row background colours
------------------------------------------------------------

local function SetRowBg(row, index)
    if index%2==0 then row.bg:SetColorTexture(0.09,0.09,0.12,0.5)
    else               row.bg:SetColorTexture(0.05,0.05,0.07,0.5)
    end
end

local GROUP_BG = {0.12, 0.12, 0.22, 1}

------------------------------------------------------------
-- Scrollable row  (receives only the non-frozen columns)
------------------------------------------------------------

local DIVIDER_COLOR = {0.25, 0.25, 0.32, 0.9}

function AltTracker.CreateRow(parent, height, columns)
    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(height)
    row.cells    = {}
    row.repTips  = {}
    row.gearTips = {}
    row.cellTips = {}   -- general per-cell tooltip buttons

    row.bg = row:CreateTexture(nil,"BACKGROUND")
    row.bg:SetAllPoints()

    row.hover = row:CreateTexture(nil,"HIGHLIGHT")
    row.hover:SetAllPoints()
    row.hover:SetColorTexture(1,1,1,0.06)

    local x=10; local padding=6
    for i, col in ipairs(columns) do
        local cell

        if col.type == "classIcon" or col.type == "raceIcon" or col.type == "specIcon" then
            cell = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            cell:SetPoint("LEFT", x, 0)
            cell:SetWidth(col.width)
            cell:SetJustifyH("CENTER")
            cell:SetWordWrap(false)
            row.cells[i] = cell
        else
            cell = row:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
            cell:SetPoint("LEFT",x,0)
            cell:SetWidth(col.width)
            cell:SetJustifyH(col.align or "LEFT")
            cell:SetWordWrap(false)
            row.cells[i] = cell
        end

        -- General tooltip button for classIcon, raceIcon, level, restPercent, profSkill
        if col.type=="classIcon" or col.type=="raceIcon" or col.type=="specIcon"
        or col.field=="level" or col.type=="restXP"
        or col.field=="restPercent" or col.type=="profSkill"
        or col.type=="bisCount" then
            local tip = CreateFrame("Button", nil, row)
            tip:SetPoint("LEFT", x, 0)
            tip:SetSize(col.width, height)
            tip:SetScript("OnEnter", function()
                GameTooltip:SetOwner(tip, "ANCHOR_RIGHT")
                GameTooltip:ClearLines()
                if tip.line1 then GameTooltip:AddLine(tip.line1, 1,1,1) end
                if tip.line2 then GameTooltip:AddLine(tip.line2, 0.8,0.8,0.8) end
                if tip.line3 then GameTooltip:AddLine(tip.line3, 0.7,0.7,0.4) end
                if tip.cdLines then
                    GameTooltip:AddLine(" ", 1,1,1)  -- spacer
                    for _, line in ipairs(tip.cdLines) do
                        GameTooltip:AddLine(line, 1,1,1)
                    end
                end
                GameTooltip:Show()
            end)
            tip:SetScript("OnLeave", function() GameTooltip:Hide() end)
            row.cellTips[i] = tip
        end

        -- Invisible hover button for rep cells
        if col.type == "rep" or col.type == "repCombined" then
            local tip = CreateFrame("Button", nil, row)
            tip:SetPoint("LEFT", x, 0)
            tip:SetSize(col.width, height)
            tip:SetScript("OnEnter", function()
                if tip.standing then
                    GameTooltip:SetOwner(tip, "ANCHOR_RIGHT")
                    GameTooltip:ClearLines()
                    local factionName = tip.activeFactionName or tip.factionLabel or ""
                    GameTooltip:AddLine(factionName, 1, 1, 1)
                    GameTooltip:AddLine(tip.standing, 0.8, 0.8, 0.8)
                    GameTooltip:Show()
                end
            end)
            tip:SetScript("OnLeave", function() GameTooltip:Hide() end)
            tip.factionLabel = col.label
            row.repTips[i] = tip
        end

        -- Invisible hover button for gear slots
        if col.type == "gearSlot" then
            local tip = CreateFrame("Button", nil, row)
            tip:SetPoint("LEFT", x, 0)
            tip:SetSize(col.width, height)

            -- Hover highlight background
            local hoverBg = tip:CreateTexture(nil, "BACKGROUND")
            hoverBg:SetAllPoints()
            hoverBg:SetColorTexture(1, 1, 1, 0.12)
            hoverBg:Hide()
            tip.hoverBg = hoverBg

            tip:SetScript("OnEnter", function()
                hoverBg:Show()
                if tip.itemLink and tip.itemLink ~= "" then
                    -- Extract item ID for safe tooltip display
                    local itemID = tip.itemLink:match("item:(%d+)")
                    if itemID then
                        GameTooltip:SetOwner(tip, "ANCHOR_RIGHT")
                        GameTooltip:SetHyperlink("item:"..itemID)
                        -- Append BiS info below the standard tooltip
                        if tip.bisTier then
                            GameTooltip:AddLine(" ")
                            GameTooltip:AddLine("|cff00ff00★ BiS: "..tip.bisTier.."|r", 0, 1, 0)
                        end
                        GameTooltip:Show()
                    end
                elseif tip.slotIlvl and tip.slotIlvl > 0 then
                    -- Fallback for items without a stored link
                    local qColor = QUALITY_COLORS[tip.slotQuality or 1] or "|cffffffff"
                    GameTooltip:SetOwner(tip, "ANCHOR_RIGHT")
                    GameTooltip:ClearLines()
                    if tip.itemName and tip.itemName ~= "" then
                        GameTooltip:AddLine(qColor..tip.itemName.."|r", 1,1,1)
                    end
                    GameTooltip:AddLine(col.label.." — ilvl "..tip.slotIlvl, 0.8,0.8,0.8)
                    if tip.bisTier then
                        GameTooltip:AddLine(" ")
                        GameTooltip:AddLine("|cff00ff00★ BiS: "..tip.bisTier.."|r", 0, 1, 0)
                    end
                    GameTooltip:Show()
                end
            end)
            tip:SetScript("OnLeave", function()
                hoverBg:Hide()
                GameTooltip:Hide()
            end)
            row.gearTips[i] = tip
        end

        if i<#columns then
            local div = row:CreateTexture(nil,"ARTWORK")
            div:SetSize(1,height-4)
            div:SetPoint("LEFT",x+col.width+math.floor(padding/2),0)
            div:SetColorTexture(unpack(DIVIDER_COLOR))
        end
        x=x+col.width+padding
    end
    return row
end

-- For a scrollable group row: just colour the background.
-- All text/buttons are in the frozen panel.
function AltTracker.RenderGroupRow(row, item)
    row.bg:SetColorTexture(unpack(GROUP_BG))
    for _, cell in ipairs(row.cells) do cell:SetText("") end
    row:Show()
end

function AltTracker.RenderRow(row, char, index, columns)
    SetRowBg(row, index)
    for i, col in ipairs(columns) do
        local value = ""
        local tip   = row.cellTips[i]

        if col.type=="classIcon" then
            value = ClassIconText(char.class)
            if tip then
                tip.line1 = CLASS_DISPLAY[char.class] or char.class
                tip.line2 = char.gender
                tip.line3 = nil
            end

        elseif col.type=="raceIcon" then
            value = RaceIconText(char.race, char.gender)
            if tip then
                tip.line1 = char.race and RACE_DISPLAY[char.race] or char.race
                tip.line2 = char.gender
                tip.line3 = nil
            end

        elseif col.type=="specIcon" then
            value = SpecIconText(char.specIcon)
            if tip then
                local specName = char.spec
                tip.line1 = (specName and specName ~= "") and specName or "Not scanned"
                tip.line2 = nil
                tip.line3 = nil
            end

        elseif col.field=="level" then
            value = FormatMax(char.level, 70)
            if tip then
                local lvl = char.level or 0
                if lvl < 70 then
                    local xpPct = char.xpPercent or 0
                    tip.line1 = "Level " .. lvl
                    tip.line2 = xpPct .. "% through this level"
                    tip.line3 = nil
                else
                    tip.line1 = "Level 70 (max)"
                    tip.line2 = nil; tip.line3 = nil
                end
            end

        elseif col.field=="ilvl" then value = FormatItemLevel(char.ilvl)

        elseif col.type=="bisCount" then
            local count, ratio = CountBisItems(char)
            if count > 0 then
                local pct = math.floor(ratio * 100)
                local c = BisCountColor(ratio)
                value = string.format("|cff%02x%02x%02x%d%%|r", c.r*255, c.g*255, c.b*255, pct)
            else
                value = "|cff555555-|r"
            end
            if tip then
                tip.line1 = count .. " / " .. MAX_GEAR_SLOTS .. " BiS items equipped"
                tip.line2 = char.spec and ("Spec: " .. char.spec) or nil
                tip.line3 = nil
            end

        elseif col.type=="gearSlot" then
            local slotKey = col.field:sub(6)  -- e.g. "head", "neck", etc.
            local v = char[col.field]
            local q = char["gearq_"..slotKey] or 0
            local itemName = char["gearname_"..slotKey] or ""
            local itemLink = char["gearlink_"..slotKey] or ""
            value = FormatGearIlvl(v, q)

            -- BiS check
            local bisTier = IsItemBis(char.class, char.spec, slotKey, itemName)
            if row.gearTips[i] then
                row.gearTips[i].slotIlvl    = v
                row.gearTips[i].slotQuality  = q
                row.gearTips[i].itemName     = itemName
                row.gearTips[i].itemLink     = itemLink
                row.gearTips[i].bisTier      = bisTier
            end
            -- Prepend a green checkmark for BiS items
            if bisTier then
                value = "|TInterface\\RAIDFRAME\\ReadyCheck-Ready:0:0:0:0:64:64:4:60:4:60|t"..value
            end

        elseif col.field=="restPercent" or col.type=="restXP" then
            local p   = char.restPercent or 0
            local lvl = char.level or 0
            -- Gradient: 0%=red, 75%=yellow, 150%=green
            local r, g
            if p <= 75 then
                local t = p / 75
                r = 1; g = t
            else
                local t = (p - 75) / 75
                r = 1 - t; g = 1
            end
            value = string.format("|cff%02x%02x00%d%%|r", math.floor(r*255), math.floor(g*255), p)
            if tip and lvl < 70 then
                local restXP = char.restXP or 0
                if p >= 150 then
                    tip.line1 = "Rested XP: " .. p .. "% (full)"
                    tip.line2 = nil; tip.line3 = nil
                elseif restXP > 0 then
                    local needed  = 150 - p
                    local hours   = math.ceil(needed / 5 * 8)
                    local days    = math.floor(hours / 24)
                    local remHour = hours % 24
                    local timeStr = days > 0 and (days.."d "..remHour.."h") or (hours.."h")
                    tip.line1 = "Rested XP: " .. p .. "%"
                    tip.line2 = "~" .. timeStr .. " offline to reach 150%"
                    tip.line3 = nil
                else
                    tip.line1 = "Rested XP: 0%"
                    tip.line2 = "Log off in an inn to accumulate rested XP"
                    tip.line3 = nil
                end
            elseif tip then
                tip.line1 = "Level cap — rested XP inactive"
                tip.line2 = nil; tip.line3 = nil
            end

        elseif col.type=="profSkill" then
            local skill = char[col.field]
            local max   = col.maxField and char[col.maxField]
            if not skill or skill <= 0 then
                value = ""
            elseif max and max > 0 then
                local ratio = skill / max
                local color
                if skill >= max then
                    -- Maxed (or racial overcap) — green
                    color = "|cff1eff00"
                elseif ratio >= 0.75 then
                    color = "|cffffff00"  -- yellow
                elseif ratio >= 0.50 then
                    color = "|cffff8800"  -- orange
                elseif ratio >= 0.25 then
                    color = "|cffff2020"  -- red
                else
                    color = "|cff808080"  -- grey
                end
                -- Racial cap marker: 375 in a 385-cap profession
                if max > 375 and skill >= 375 and skill < max then
                    value = color..skill.."*|r"
                else
                    value = color..skill.."|r"
                end
            else
                value = tostring(skill)
            end
            if tip then
                tip.line1 = col.label
                tip.line2 = max and ("Max: "..max) or nil
                tip.line3 = (max and max > 375 and skill and skill >= 375 and skill < max)
                    and "* Racial bonus cap — functionally maxed" or nil
                -- Append cooldown info if this profession has tracked CDs
                tip.cdLines = nil
                local defs = AltTracker.ProfCDKeys and AltTracker.ProfCDKeys[col.label]
                if defs and skill and skill > 0 then
                local cdLines = {}
                    local now = time()
                    local shownKeys = {}
                    for _, cd in ipairs(defs) do
                        if not shownKeys[cd.key] then
                            local expiry = char[cd.key]
                            if expiry ~= nil then
                                shownKeys[cd.key] = true
                                if expiry == 0 or expiry <= now then
                                    table.insert(cdLines, "|cff00ff00"..cd.name..": Ready!|r")
                                else
                                    local remaining = expiry - now
                                    local d = math.floor(remaining / 86400)
                                    local h = math.floor((remaining % 86400) / 3600)
                                    local m = math.floor((remaining % 3600) / 60)
                                    local timeStr
                                    if d > 0 then
                                        timeStr = d.."d "..(h > 0 and h.."h" or "")
                                    elseif h > 0 then
                                        timeStr = h.."h "..m.."m"
                                    else
                                        timeStr = m.."m"
                                    end
                                    table.insert(cdLines, "|cffff8800"..cd.name..": "..timeStr.."|r")
                                end
                            end
                        end
                    end
                    if #cdLines > 0 then
                        tip.cdLines = cdLines
                    end
                end
            end
        elseif col.field=="lastUpdate"  then
            local isMe = char.guid == UnitGUID("player")
            value = FormatLastOnline(char.lastUpdate, isMe)
        elseif col.type=="money"        then value = FormatMoney(char[col.field])
        elseif col.type=="rep"          then
            local standing = char[col.field]
            value = FormatReputation(standing)
            if row.repTips[i] then
                row.repTips[i].standing = standing and REP_TEXT[standing] or nil
            end
        elseif col.type=="repCombined"  then
            local v1 = char[col.field]  or 0
            local v2 = char[col.field2] or 0
            local active, activeName
            if v1 >= 3 then
                active, activeName = v1, col.label:match("^([^/]+)")
            elseif v2 >= 3 then
                active, activeName = v2, col.label:match("/(.+)$")
            else
                active = math.max(v1, v2)
                activeName = col.label
            end
            activeName = activeName and activeName:match("^%s*(.-)%s*$") or col.label
            value = (active > 0) and FormatReputation(active) or ""
            if row.repTips[i] then
                row.repTips[i].standing          = active > 0 and REP_TEXT[active] or nil
                row.repTips[i].activeFactionName = activeName
            end
        else
            value = tostring(char[col.field] or "")
        end

        row.cells[i]:SetText(value)
    end
    row:Show()
end

function AltTracker.HideRow(row)
    for _, cell in ipairs(row.cells) do cell:SetText("") end
    row.bg:SetColorTexture(0,0,0,0)
    row:Hide()
end

------------------------------------------------------------
-- Frozen column row  (Name only)
------------------------------------------------------------

function AltTracker.CreateFrozenRow(parent, height, nameColWidth)
    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(height)

    row.bg = row:CreateTexture(nil,"BACKGROUND")
    row.bg:SetAllPoints()

    row.hover = row:CreateTexture(nil,"HIGHLIGHT")
    row.hover:SetAllPoints()
    row.hover:SetColorTexture(1,1,1,0.06)

    local cBtn = CreateFrame("Button", nil, row)
    cBtn:SetSize(16,16); cBtn:SetPoint("LEFT",6,0); cBtn:Hide()
    row.collapseBtn = cBtn
    local cIcon = cBtn:CreateFontString(nil,"OVERLAY","GameFontNormal")
    cIcon:SetAllPoints(); cIcon:SetJustifyH("CENTER")
    row.collapseIcon = cIcon

    local lbl = row:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
    lbl:SetHeight(height); lbl:SetJustifyH("LEFT"); lbl:SetWordWrap(false)
    lbl:SetPoint("LEFT",10,0); lbl:SetWidth(nameColWidth)
    row.nameLabel = lbl

    -- Invisible tooltip button for character rows
    local tipBtn = CreateFrame("Button", nil, row)
    tipBtn:SetAllPoints()
    tipBtn:SetScript("OnEnter", function()
        if not tipBtn.charData then return end
        local c = tipBtn.charData
        local GOLD_ICON = "|TInterface\\MoneyFrame\\UI-GoldIcon:12:12:2:0|t"
        GameTooltip:SetOwner(tipBtn, "ANCHOR_RIGHT")
        GameTooltip:ClearLines()
        GameTooltip:AddLine(AltTracker.ClassColor(c.class)..(c.name or "").."|r", 1,1,1)
        if c.guild and c.guild ~= "" then
            GameTooltip:AddLine("<"..c.guild..">", 0.7,0.7,0.7)
        end
        GameTooltip:AddLine(" ",1,1,1)
        if c.money then
            local gold = math.floor(c.money/10000)
            local silver = math.floor((c.money%10000)/100)
            local copper = c.money % 100
            GameTooltip:AddLine(string.format("Gold: %d%s %ds %dc", gold,GOLD_ICON,silver,copper), 0.9,0.85,0.1)
        end
        if c.lastUpdate then
            local diff = time()-c.lastUpdate
            local isMe = c.guid == UnitGUID("player")
            local onlineStr
            if isMe and diff<300 then onlineStr="|cff00ff00Online|r"
            elseif diff<3600 then onlineStr=math.floor(diff/60).."m ago"
            elseif diff<86400 then onlineStr=math.floor(diff/3600).."h ago"
            else onlineStr=math.floor(diff/86400).."d ago" end
            GameTooltip:AddLine("Last seen: "..onlineStr, 0.7,0.7,0.7)
        end
        GameTooltip:Show()
    end)
    tipBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    row.nameTipBtn = tipBtn

    return row
end

function AltTracker.RenderFrozenGroupRow(row, item)
    row.bg:SetColorTexture(unpack(GROUP_BG))
    row.collapseBtn:Show()
    row.collapseIcon:SetText(item.collapsed and "|cffffd100+|r" or "|cffffd100-|r")

    -- Shift label right to make room for the button
    row.nameLabel:SetPoint("LEFT", row.collapseBtn, "RIGHT", 4, 0)

    local realm = item.realm
    row.collapseBtn:SetScript("OnClick", function()
        if AltTracker.ToggleRealm then AltTracker.ToggleRealm(realm) end
    end)

    local GOLD_ICON_SS = "|TInterface\\MoneyFrame\\UI-GoldIcon:11:11:2:0|t"
    local summary = "|cffaaaaaa"
        ..(item.count or 0).."c  "
        .."Lv "..(item.sumLevel or 0).."  "
        ..math.floor((item.sumGold or 0)/10000)..GOLD_ICON_SS
        .."|r"

    row.nameLabel:SetText("|cffffd100"..(item.realm or "").."|r  "..summary)
    row:Show()
end

function AltTracker.RenderFrozenCharRow(row, char, index)
    SetRowBg(row, index)
    row.collapseBtn:Hide()
    row.nameLabel:SetPoint("LEFT",10,0)
    row.nameLabel:SetText(AltTracker.ClassColor(char.class)..(char.name or "").."|r")
    if row.nameTipBtn then row.nameTipBtn.charData = char end
    row:Show()
end

function AltTracker.HideFrozenRow(row)
    row.bg:SetColorTexture(0,0,0,0)
    row.collapseBtn:Hide()
    row.nameLabel:SetText("")
    if row.nameTipBtn then row.nameTipBtn.charData = nil end
    row:Hide()
end