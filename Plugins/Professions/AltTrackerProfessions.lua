------------------------------------------------------------
-- AltTrackerProfessions
--
-- Recipe matrix plugin for AltTracker.
--
-- Layout (left to right):
--   [ recipe-scroll-icon | product-icon | recipe name ]
--   [ % known | (optional) AH | (optional) Craft ]
--   [ char1 ... charN ]
--
-- The character columns use class + race icons stacked, mirroring the
-- visual language of the main AltTracker Account Summary. Rows group
-- under per-profession section headers that are click-to-collapse.
--
-- Persistence:
--   AltTrackerProfessionsDB[guid] = { name, realm, class, race, gender, level,
--                                     recipes = { [profName] = { ... } } }
--   AltTrackerProfessionsDB._ui    = { collapsed = { [profName]=true } }
------------------------------------------------------------

AltTrackerProfessionsDB = AltTrackerProfessionsDB or {}

local ADDON_ID = "professions"
local AT_PROFS = {}
AT_PROFS.isActive = false

------------------------------------------------------------
-- Utility
------------------------------------------------------------

local function Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cff00ccff[AltTracker Professions]|r " .. msg)
end

local function GetCharDB(guid)
    AltTrackerProfessionsDB[guid] = AltTrackerProfessionsDB[guid] or {}
    AltTrackerProfessionsDB[guid].recipes = AltTrackerProfessionsDB[guid].recipes or {}
    return AltTrackerProfessionsDB[guid]
end

local function GetUIState()
    -- Hide under a non-GUID-looking key so iteration skips it.
    AltTrackerProfessionsDB._ui = AltTrackerProfessionsDB._ui or { collapsed = {} }
    AltTrackerProfessionsDB._ui.collapsed = AltTrackerProfessionsDB._ui.collapsed or {}
    return AltTrackerProfessionsDB._ui
end

local function ExtractItemID(link)
    if not link then return 0 end
    local id = link:match("item:(%d+)")
    return tonumber(id) or 0
end

local function ExtractSpellID(link)
    if not link then return 0 end
    local id = link:match("enchant:(%d+)")
    return tonumber(id) or 0
end

-- Iterate ONLY actual character records (skip the _ui bookkeeping entry)
local function IterCharacters()
    return function(db, key)
        local k, v = next(db, key)
        while k ~= nil and (type(k) ~= "string" or k:sub(1,1) == "_") do
            k, v = next(db, k)
        end
        return k, v
    end, AltTrackerProfessionsDB, nil
end

------------------------------------------------------------
-- Expansion heuristic
------------------------------------------------------------

local TBC_ITEM_ID_THRESHOLD = 22000

local function ClassifyExpansion(itemID)
    if not itemID or itemID == 0 then return "unknown" end
    if itemID >= TBC_ITEM_ID_THRESHOLD then return "bc" end
    return "classic"
end

------------------------------------------------------------
-- Tracked professions + profession-specific placeholder recipe icons
-- These are scroll/parchment icons that DIFFERENTIATE the "recipe"
-- (column 1) from the "crafted product" (column 2), so the user can
-- see at a glance which profession taught the recipe.
------------------------------------------------------------

local TRACKABLE_PROFESSIONS = {
    ["Alchemy"]=true, ["Blacksmithing"]=true, ["Enchanting"]=true,
    ["Engineering"]=true, ["Jewelcrafting"]=true, ["Leatherworking"]=true,
    ["Tailoring"]=true, ["Cooking"]=true, ["First Aid"]=true,
}

local PROF_ORDER = {
    "Alchemy","Blacksmithing","Enchanting","Engineering",
    "Jewelcrafting","Leatherworking","Tailoring","Cooking","First Aid",
}

-- Button icons (unchanged — these are the profession filter pills)
local PROF_ICONS = {
    Alchemy        = "Interface\\Icons\\Trade_Alchemy",
    Blacksmithing  = "Interface\\Icons\\Trade_BlackSmithing",
    Enchanting     = "Interface\\Icons\\Trade_Engraving",
    Engineering    = "Interface\\Icons\\Trade_Engineering",
    Jewelcrafting  = "Interface\\Icons\\INV_Misc_Gem_01",
    Leatherworking = "Interface\\Icons\\Trade_LeatherWorking",
    Tailoring      = "Interface\\Icons\\Trade_Tailoring",
    Cooking        = "Interface\\Icons\\INV_Misc_Food_15",
    ["First Aid"]  = "Interface\\Icons\\Spell_Holy_SealOfSacrifice",
}

-- Per-profession recipe "scroll" placeholders. In TBC every profession
-- has its own recipe item art, reflected here — these are the icons
-- that appear on the pattern/plans/formula/design/schematic/recipe items
-- sold by trainers and recipe vendors. Column 1 uses one of these when
-- GetTradeSkillIcon didn't give us a usable recipe icon.
local PROF_RECIPE_PLACEHOLDER = {
    Alchemy        = "Interface\\Icons\\INV_Scroll_03",
    Blacksmithing  = "Interface\\Icons\\INV_Scroll_05",
    Enchanting     = "Interface\\Icons\\INV_Scroll_02",
    Engineering    = "Interface\\Icons\\INV_Scroll_04",
    Jewelcrafting  = "Interface\\Icons\\INV_Scroll_01",
    Leatherworking = "Interface\\Icons\\INV_Misc_Note_05",
    Tailoring      = "Interface\\Icons\\INV_Misc_Note_01",
    Cooking        = "Interface\\Icons\\INV_Misc_Note_02",
    ["First Aid"]  = "Interface\\Icons\\INV_Misc_Book_11",
}

local GENERIC_PRODUCT_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"

------------------------------------------------------------
-- Item icon cache (for the PRODUCT column — we want the real crafted
-- item's icon, not the recipe icon). Lazily populated via GetItemInfo,
-- which queries the server if the item isn't cached locally.
------------------------------------------------------------

local iconCache    = {}
local requestedIDs = {}

local function RequestItemIcon(itemID)
    if not itemID or itemID == 0 then return nil end
    if iconCache[itemID] then return iconCache[itemID] end
    local _, _, _, _, _, _, _, _, _, icon = GetItemInfo(itemID)
    if icon then
        iconCache[itemID] = icon
        return icon
    end
    if not requestedIDs[itemID] then
        requestedIDs[itemID] = true
        -- calling GetItemInfo above already schedules the server fetch;
        -- we'll re-render on GET_ITEM_INFO_RECEIVED.
    end
    return nil
end

------------------------------------------------------------
-- Auctionator integration (soft dependency, unchanged)
------------------------------------------------------------

local AUCTIONATOR_CALLER_ID = "AltTrackerProfessions"

local function IsAuctionatorAvailable()
    return _G.Auctionator and _G.Auctionator.API and _G.Auctionator.API.v1
       and _G.Auctionator.API.v1.GetAuctionPriceByItemID ~= nil
end

local function GetAHPriceCopper(itemID)
    if not IsAuctionatorAvailable() or not itemID or itemID == 0 then return nil end
    local ok, price = pcall(_G.Auctionator.API.v1.GetAuctionPriceByItemID,
                            AUCTIONATOR_CALLER_ID, itemID)
    if ok and type(price) == "number" and price > 0 then return price end
    return nil
end

local function GetVendorPriceCopper(itemID)
    if not IsAuctionatorAvailable() or not itemID or itemID == 0 then return nil end
    local ok, price = pcall(_G.Auctionator.API.v1.GetVendorPriceByItemID,
                            AUCTIONATOR_CALLER_ID, itemID)
    if ok and type(price) == "number" and price > 0 then return price end
    return nil
end

local function ComputeCraftCost(entry)
    if not IsAuctionatorAvailable() then return nil end
    if not entry.reagents or #entry.reagents == 0 then return nil end
    local total = 0
    for _, r in ipairs(entry.reagents) do
        local unit = GetVendorPriceCopper(r.itemID) or GetAHPriceCopper(r.itemID)
        if unit then total = total + unit * (r.count or 1) end
    end
    if total == 0 then return nil end
    return total
end

local function FormatMoney(copper)
    if not copper or copper <= 0 then return "|cff555555—|r" end
    local g = math.floor(copper / 10000)
    local s = math.floor((copper % 10000) / 100)
    local c = copper % 100
    if g > 0 then
        return string.format("|cffffd70a%d|rg|cffc7c7cf%d|rs", g, s)
    elseif s > 0 then
        return string.format("|cffc7c7cf%d|rs|cffeda55f%d|rc", s, c)
    else
        return string.format("|cffeda55f%d|rc", c)
    end
end

------------------------------------------------------------
-- Scanning
------------------------------------------------------------

-- A compact signature over a profession's scanned recipes — ids AND the
-- metadata that affects display/craft-cost (reagents, numMade, icon,
-- difficulty). Used to decide when a character's recipes actually changed, so
-- we only mark it dirty (and re-sync its blob) on real changes, not every scan.
local function RecipeSig(recipeList)
    local parts = {}
    for _, r in ipairs(recipeList) do
        local rg = {}
        if r.reagents then
            for _, x in ipairs(r.reagents) do
                rg[#rg + 1] = (x.itemID or 0) .. ":" .. (x.count or 1)
            end
        end
        parts[#parts + 1] = table.concat({
            r.name or "", r.itemID or 0, r.spellID or 0, r.numMade or 1,
            r.difficulty or "", r.recipeIcon or "", table.concat(rg, ","),
        }, "\1")
    end
    local s = table.concat(parts, "\2")
    local h = 0
    for i = 1, #s do h = (h * 31 + string.byte(s, i)) % 0xFFFFFFFF end
    return string.format("%08X-%d", h, #recipeList)
end

local function ScanCurrentTradeskill()
    if not GetTradeSkillLine then return end
    local profName = GetTradeSkillLine()
    if not profName or not TRACKABLE_PROFESSIONS[profName] then return end

    local guid = UnitGUID("player")
    if not guid then return end

    local db = GetCharDB(guid)
    db.name   = UnitName("player")
    db.realm  = GetRealmName()
    db.class  = select(2, UnitClass("player"))
    db.race   = select(2, UnitRace("player"))
    local g   = UnitSex("player")
    db.gender = (g == 3) and "Female" or "Male"
    db.level  = UnitLevel("player") or 0

    db.recipes[profName] = {}
    local recipeList = db.recipes[profName]

    local newCds     = {}   -- label -> absolute expiry (recipes currently on cooldown)
    local seenLabels = {}   -- every craft label seen this scan (for respec/unlearn pruning)

    local numSkills = GetNumTradeSkills()
    for i = 1, numSkills do
        local recipeName, recipeType = GetTradeSkillInfo(i)
        if recipeName and recipeType ~= "header" then
            local itemLink   = GetTradeSkillItemLink and GetTradeSkillItemLink(i)
            local itemID     = ExtractItemID(itemLink)
            local recipeLink = GetTradeSkillRecipeLink and GetTradeSkillRecipeLink(i)
            local spellID    = ExtractSpellID(recipeLink)
            local recipeIcon = GetTradeSkillIcon and GetTradeSkillIcon(i) or nil
            local numMade    = 1
            if GetTradeSkillNumMade then
                local lo = GetTradeSkillNumMade(i)
                numMade = lo or 1
            end

            local reagents = {}
            if GetTradeSkillNumReagents then
                for ri = 1, GetTradeSkillNumReagents(i) do
                    local _, _, count = GetTradeSkillReagentInfo(i, ri)
                    local rLink = GetTradeSkillReagentItemLink and GetTradeSkillReagentItemLink(i, ri)
                    local rID   = ExtractItemID(rLink)
                    if rID > 0 then
                        table.insert(reagents, { itemID = rID, count = count or 1 })
                    end
                end
            end

            table.insert(recipeList, {
                name       = recipeName,
                itemID     = itemID,
                difficulty = recipeType or "",
                recipeIcon = recipeIcon,
                spellID    = spellID,
                numMade    = numMade,
                reagents   = reagents,
            })

            -- Generic craft-cooldown capture. Collapse a shared-CD family
            -- ("Transmute: Primal Might", "Transmute: Primal Fire", …) to one label
            -- by taking the part before the first colon — locale-independent, and
            -- it dedupes the family to a single entry (they share one expiry).
            local label = recipeName:match("^([^:]+):") or recipeName
            seenLabels[label] = true
            local cd = GetTradeSkillCooldown and GetTradeSkillCooldown(i) or 0
            if cd and cd > 0 then
                newCds[label] = time() + cd   -- on cooldown now
            end
        end
    end

    -- Write this profession's cooldowns onto the SHARED character record as dynamic
    -- cd_<prof>@<label> fields. Flat fields ride the normal char sync (no recipe-
    -- blob coupling) and are read by RowRenderer/Roster/Toasts. A field is dropped
    -- only when its craft is no longer in the skill list (unlearned / respec); a
    -- known craft that's merely READY keeps its past expiry so the UI can show
    -- "Ready" and the cooldown-ready toast can fire. Other professions' fields are
    -- left untouched (we only ever see one profession's skills per scan).
    local coreChar = AltTrackerDB and AltTrackerDB[guid]
    if coreChar then
        local prefix, cdChanged = "cd_" .. profName .. "@", false
        for k in pairs(coreChar) do
            if type(k) == "string" then
                if k:sub(1, #prefix) == prefix and not seenLabels[k:sub(#prefix + 1)] then
                    coreChar[k] = nil; cdChanged = true          -- craft unlearned / respec'd away
                elseif (k:find("^cd_") and not k:find("@", 1, true)) or k:find("^known_") then
                    coreChar[k] = nil; cdChanged = true          -- purge legacy fixed-key cooldowns
                end
            end
        end
        for label, expiry in pairs(newCds) do
            local k = prefix .. label
            local old = coreChar[k]
            if not old or math.abs(old - expiry) > 60 then       -- 60s tolerance: ignore scan-timing jitter
                coreChar[k] = expiry; cdChanged = true
            end
        end
        if cdChanged and AltTracker.TouchCharacter then AltTracker.TouchCharacter(guid) end
    end

    -- Mark the character dirty only when this profession's recipes actually
    -- changed (set or metadata), so a played character re-syncs its recipe blob
    -- when it learns something, but NOT on every unrelated scan/login.
    db._recipeSig = db._recipeSig or {}
    local sig = RecipeSig(recipeList)
    if db._recipeSig[profName] ~= sig then
        db._recipeSig[profName] = sig
        db.recipesStamp = time()
        if AltTracker.TouchCharacter then AltTracker.TouchCharacter(guid) end
    end

    if AT_PROFS.isActive and AT_PROFS.RefreshResults then AT_PROFS.RefreshResults() end
end

------------------------------------------------------------
-- Serialization (unchanged 7-field format)
------------------------------------------------------------

local SEP_PROF    = "|"
local SEP_RECIPE  = "~"
local SEP_FIELD   = "^"
local SEP_REAGENT = ","
local SEP_RFIELD  = ";"

local function Scrub(s)
    if not s then return "" end
    return (tostring(s):gsub("[\n|~%^,;]", ""))
end

local function SerializeReagents(reagents)
    if not reagents or #reagents == 0 then return "" end
    local parts = {}
    for _, r in ipairs(reagents) do
        parts[#parts + 1] = tostring(r.itemID or 0) .. SEP_RFIELD .. tostring(r.count or 1)
    end
    return table.concat(parts, SEP_REAGENT)
end

local function DeserializeReagents(blob)
    local out = {}
    if not blob or blob == "" then return out end
    for pair in string.gmatch(blob, "([^" .. SEP_REAGENT .. "]+)") do
        local id, cnt = pair:match("(%d+)" .. SEP_RFIELD .. "(%d+)")
        if id then
            table.insert(out, { itemID = tonumber(id), count = tonumber(cnt) or 1 })
        end
    end
    return out
end

local function SerializePlayer(guid, sinceTS)
    local db = AltTrackerProfessionsDB[guid]
    if not db or not db.recipes then return "" end
    -- Delta skip: recipesStamp rides the character's lastUpdate, so a peer whose
    -- watermark (sinceTS) already covers it has these recipes. Returning "" omits
    -- the recipe line entirely, and the receiver keeps its existing recipe data.
    -- Strict "<": the core delta includes a char at lastUpdate >= sinceTS, so
    -- skipping at equality would drop a same-second change once the watermark
    -- reaches it. Resend-on-equality is idempotent.
    if sinceTS and sinceTS > 0 and (db.recipesStamp or 0) < sinceTS then
        return ""
    end
    local profBlocks = {}
    for profName, recipeList in pairs(db.recipes) do
        if type(recipeList) == "table" and #recipeList > 0 then
            local parts = { profName }
            for _, r in ipairs(recipeList) do
                parts[#parts + 1] = table.concat({
                    Scrub(r.name), tostring(r.itemID or 0), Scrub(r.difficulty),
                    Scrub(r.recipeIcon or ""), tostring(r.spellID or 0),
                    tostring(r.numMade or 1), SerializeReagents(r.reagents),
                }, SEP_FIELD)
            end
            profBlocks[#profBlocks + 1] = table.concat(parts, SEP_RECIPE)
        end
    end
    return table.concat(profBlocks, SEP_PROF)
end

local function DeserializePlayer(guid, blob)
    if not guid or not blob or blob == "" then return end
    local db = GetCharDB(guid)
    db.recipes = {}
    for profBlock in string.gmatch(blob, "([^" .. SEP_PROF .. "]+)") do
        local profName
        local recipeList = {}
        local idx = 0
        for part in string.gmatch(profBlock, "([^" .. SEP_RECIPE .. "]+)") do
            idx = idx + 1
            if idx == 1 then
                profName = part
            else
                local fields = {}
                for f in string.gmatch(part .. SEP_FIELD, "([^" .. SEP_FIELD .. "]*)" .. SEP_FIELD) do
                    fields[#fields + 1] = f
                end
                if #fields >= 1 then
                    table.insert(recipeList, {
                        name       = fields[1] or "",
                        itemID     = tonumber(fields[2]) or 0,
                        difficulty = fields[3] or "",
                        recipeIcon = (fields[4] ~= "" and fields[4]) or nil,
                        spellID    = tonumber(fields[5]) or 0,
                        numMade    = tonumber(fields[6]) or 1,
                        reagents   = DeserializeReagents(fields[7] or ""),
                    })
                end
            end
        end
        if profName and TRACKABLE_PROFESSIONS[profName] then
            db.recipes[profName] = recipeList
        end
    end
    if AT_PROFS.isActive and AT_PROFS.RefreshResults then AT_PROFS.RefreshResults() end
end

------------------------------------------------------------
-- Event frame
------------------------------------------------------------

-- Registers this plugin with AltTracker and snapshots the current
-- character. Normally driven by PLAYER_LOGIN, but also fired immediately
-- when the addon is loaded on demand *after* login (LoadOnDemand), when
-- PLAYER_LOGIN would never arrive again.
local function BootstrapPlugin(isOnDemand)
    if not AltTracker or not AltTracker.RegisterPlugin then
        Print("AltTracker not found — make sure it is installed and enabled.")
        return
    end
    local guid = UnitGUID("player")
    if guid then
        local db = GetCharDB(guid)
        db.name   = UnitName("player")
        db.realm  = GetRealmName()
        db.class  = select(2, UnitClass("player"))
        db.race   = select(2, UnitRace("player"))
        local g   = UnitSex("player")
        db.gender = (g == 3) and "Female" or "Male"
        db.level  = UnitLevel("player") or 0
    end
    AltTracker.RegisterPlugin({
        id            = ADDON_ID,
        label         = "Recipes",
        icon          = (AltTracker.MEDIA_PATH or "Interface\\AddOns\\AltTracker\\Media\\")
                        .. "Icons\\recipes.tga",
        _isPlugin     = true,
        OnActivate    = function(mainFrame) AT_PROFS.Activate(mainFrame) end,
        OnDeactivate  = function(mainFrame) AT_PROFS.Deactivate(mainFrame) end,
        OnSerialize   = function(g, sinceTS) return SerializePlayer(g, sinceTS) end,
        OnDeserialize = function(g, blob) DeserializePlayer(g, blob) end,
        _test         = { SerializePlayer = SerializePlayer,
                          DeserializePlayer = DeserializePlayer, RecipeSig = RecipeSig,
                          ScanCurrentTradeskill = ScanCurrentTradeskill },
    })

    -- Force a full baseline so a receiver isn't stranded with a character
    -- watermark ahead of missing/stale recipe data — either we hold no recipe
    -- data at all (fresh install / wiped DB) or the user just re-enabled this
    -- plugin mid-session (isOnDemand), having missed syncs while disabled.
    if AltTracker.ResetPeerWatermarks then
        local hasRecipes = false
        for _, cdb in pairs(AltTrackerProfessionsDB) do
            if type(cdb) == "table" and type(cdb.recipes) == "table" and next(cdb.recipes) then
                hasRecipes = true
                break
            end
        end
        if isOnDemand or not hasRecipes then
            AltTracker.ResetPeerWatermarks()
        end
    end
end

local scanFrame = CreateFrame("Frame")
scanFrame:RegisterEvent("PLAYER_LOGIN")
scanFrame:RegisterEvent("TRADE_SKILL_SHOW")
scanFrame:RegisterEvent("TRADE_SKILL_UPDATE")
scanFrame:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
scanFrame:RegisterEvent("GET_ITEM_INFO_RECEIVED")

scanFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "PLAYER_LOGIN" then
        C_Timer.After(1, function() BootstrapPlugin(false) end)
        return
    end
    if event == "TRADE_SKILL_SHOW" or event == "TRADE_SKILL_UPDATE" then
        ScanCurrentTradeskill()
        return
    end
    if event == "UNIT_SPELLCAST_SUCCEEDED" then
        local unit = ...
        if unit ~= "player" then return end
        -- A completed craft sets its cooldown a beat later; re-scan to capture it
        -- while the tradeskill window is still open (GetTradeSkillLine() ~= nil).
        C_Timer.After(0.5, function()
            if GetTradeSkillLine and GetTradeSkillLine() then ScanCurrentTradeskill() end
        end)
        return
    end
    if event == "GET_ITEM_INFO_RECEIVED" then
        local itemID, success = ...
        if itemID and success and requestedIDs[itemID] then
            local _, _, _, _, _, _, _, _, _, icon = GetItemInfo(itemID)
            if icon then iconCache[itemID] = icon end
            requestedIDs[itemID] = nil
            if AT_PROFS.isActive and AT_PROFS.RefreshResults then
                if scanFrame._refreshTimer then scanFrame._refreshTimer:Cancel() end
                scanFrame._refreshTimer = C_Timer.NewTimer(0.2, function()
                    scanFrame._refreshTimer = nil
                    AT_PROFS.RefreshResults()
                end)
            end
        end
        return
    end
end)

-- Loaded on demand after login: PLAYER_LOGIN already fired, so bootstrap now.
-- This path is the user enabling the plugin mid-session, so force a baseline.
if IsLoggedIn() then
    C_Timer.After(1, function() BootstrapPlugin(true) end)
end

------------------------------------------------------------
-- UI constants
------------------------------------------------------------

local ROW_HEIGHT           = 22
local HEADER_HEIGHT        = 50        -- character-header strip (class icon + race icon)
local COL_W_RECIPE_ICON    = 26
local COL_W_PRODUCT_ICON   = 26
local COL_W_NAME           = 220       -- wider now that % column is gone
local COL_W_AH             = 72
local COL_W_CRAFT          = 72
local COL_W_CHAR           = 26
local ICON_SIZE            = 20
local HDR_CLASS_ICON       = 18
local HDR_RACE_ICON        = 14

local CLASS_COLORS = {
    WARRIOR={0.78,0.61,0.43}, PALADIN={0.96,0.55,0.73}, HUNTER={0.67,0.83,0.45},
    ROGUE={1.00,0.96,0.41},   PRIEST={1.00,1.00,1.00},  SHAMAN={0.00,0.44,0.87},
    MAGE={0.41,0.80,0.94},    WARLOCK={0.58,0.51,0.79}, DRUID={1.00,0.49,0.04},
    DEATHKNIGHT={0.77,0.12,0.23},
}
local function ClassColor(cf)
    local c = CLASS_COLORS[cf]
    if c then return c[1], c[2], c[3] end
    return 0.75, 0.75, 0.75
end

local CLASS_DISPLAY = {
    WARRIOR="Warrior", PALADIN="Paladin", HUNTER="Hunter", ROGUE="Rogue",
    PRIEST="Priest", SHAMAN="Shaman", MAGE="Mage", WARLOCK="Warlock",
    DRUID="Druid", DEATHKNIGHT="Death Knight",
}
local RACE_DISPLAY = {
    Human="Human", Dwarf="Dwarf", Gnome="Gnome", NightElf="Night Elf",
    Draenei="Draenei", Orc="Orc", Troll="Troll", Tauren="Tauren",
    Scourge="Undead", BloodElf="Blood Elf",
}

-- Race icons use the same atlas-based approach as the main AltTracker
-- Account Summary: |A:raceicon-<atlas>-<gender>:18:18|a translates to
-- tex:SetAtlas("raceicon-<atlas>-<gender>") for Texture widgets. The
-- atlas sprites are bundled in the Classic client for all 10 races,
-- including Blood Elf (which the file-path approach was failing to
-- find reliably).
local RACE_ATLAS = {
    Human="human", Dwarf="dwarf", Gnome="gnome", NightElf="nightelf",
    Draenei="draenei", Orc="orc", Troll="troll", Tauren="tauren",
    Scourge="undead", BloodElf="bloodelf", Goblin="goblin",
}

local function ClassIconPath(classFile)
    if not classFile or classFile == "" then return nil end
    local name = classFile:sub(1,1):upper() .. classFile:sub(2):lower()
    return "Interface\\Icons\\ClassIcon_" .. name
end

local function ApplyRaceIconAtlas(tex, race, gender)
    local atlas = race and RACE_ATLAS[race]
    if not atlas then
        tex:Hide()
        return false
    end
    local g = (gender == "Female") and "female" or "male"
    local atlasName = "raceicon-" .. atlas .. "-" .. g
    -- SetAtlas returns no value; if the atlas doesn't exist the
    -- texture goes blank. Wrap defensively in case of future API
    -- changes.
    local ok = pcall(tex.SetAtlas, tex, atlasName)
    if not ok then
        tex:Hide()
        return false
    end
    tex:Show()
    return true
end

-- Gradient used for the % known column (same red→yellow→green
-- progression as the rested XP column in the main AltTracker sheet).
local function PctGradientColor(pct)
    -- pct is 0..100. 0=red, 50=yellow, 100=green.
    local r, g
    if pct <= 50 then
        local t = pct / 50
        r = 1; g = t
    else
        local t = (pct - 50) / 50
        r = 1 - t; g = 1
    end
    return r, g, 0
end

local function GetLeftWidth()
    local w = COL_W_RECIPE_ICON + COL_W_PRODUCT_ICON + COL_W_NAME + 6
    if IsAuctionatorAvailable() then
        w = w + COL_W_AH + 4 + COL_W_CRAFT + 4
    end
    return w
end

------------------------------------------------------------
-- Panel state
------------------------------------------------------------

local panel
local searchBox
local countLabel
local matrixScroll
local matrixContent
local charHeaderStrip
local leftColumnHeader
local showMissingCheckbox

local activeExpansion = "bc"
local activeProf      = nil
local showMissingOnly = false

local expButtons      = {}
local profButtons     = {}
local profButtonBorders = {}  -- highlight borders for the active prof button
local rowPool         = {}
local sectionRowPool  = {}
local headerPool      = {}
local selectedEntryKey = nil

------------------------------------------------------------
-- Data
------------------------------------------------------------

local function CollectCharacters()
    local chars = {}
    for guid, data in IterCharacters() do
        if type(data) == "table" and data.name then
            local hasAny = false
            if type(data.recipes) == "table" then
                for _, list in pairs(data.recipes) do
                    if type(list) == "table" and #list > 0 then hasAny = true; break end
                end
            end
            if hasAny then
                -- Cross-reference AltTrackerDB for identity fields that the
                -- plugin may not have locally (e.g. characters synced via
                -- the main AltTracker sync but never scanned on this client).
                local atd = _G.AltTrackerDB and _G.AltTrackerDB[guid]
                table.insert(chars, {
                    guid   = guid,
                    name   = data.name,
                    class  = data.class or (atd and atd.class) or "",
                    race   = data.race  or (atd and atd.race),
                    gender = data.gender or (atd and atd.gender),
                    level  = data.level or (atd and atd.level) or 0,
                })
            end
        end
    end
    -- Sort by level descending (same default as main Account Summary),
    -- tiebreak by name ascending.
    table.sort(chars, function(a, b)
        if a.level ~= b.level then return a.level > b.level end
        return a.name < b.name
    end)
    return chars
end

local function PassesExpansion(entry)
    if activeExpansion == "all" then return true end

    -- The scan's itemID is closer to the truth than any seed-baked
    -- expansion tag — when we know the itemID, classify by it. Only fall
    -- back to the seed's expansion field when we have no itemID at all.
    -- This protects against seed entries whose names collide with recipes
    -- in another expansion (a seed tagged "bc" being shadowed onto a
    -- Classic itemID, etc.).
    local itemID = entry.itemID or 0
    local exp
    if itemID > 0 then
        exp = ClassifyExpansion(itemID)
    else
        exp = entry.expansion or "unknown"
    end

    if activeExpansion == "bc" then
        return exp == "bc" or exp == "unknown"
    end
    if activeExpansion == "classic" then
        return exp == "classic"
    end
    return true
end

local function BuildEntries()
    local byKey = {}
    local order = {}

    -- Pass 1: fold every character's scanned recipes into byKey, keyed
    -- on (profession, recipeName).  This is what was working before —
    -- gives us one row per recipe with knownBy populated for every alt
    -- that has it.
    for guid, data in IterCharacters() do
        if type(data) == "table" and data.name and type(data.recipes) == "table" then
            for profName, recipeList in pairs(data.recipes) do
                if TRACKABLE_PROFESSIONS[profName] and type(recipeList) == "table" then
                    for _, r in ipairs(recipeList) do
                        local key = profName .. "\0" .. (r.name or "")
                        local entry = byKey[key]
                        if not entry then
                            entry = {
                                key        = key,
                                profName   = profName,
                                recipe     = r.name or "",
                                itemID     = r.itemID or 0,
                                spellID    = r.spellID or 0,
                                recipeIcon = r.recipeIcon,
                                numMade    = r.numMade or 1,
                                reagents   = r.reagents,
                                knownBy    = {},
                            }
                            byKey[key] = entry
                            table.insert(order, key)
                        else
                            if entry.itemID == 0 and (r.itemID or 0) > 0 then entry.itemID = r.itemID end
                            if entry.spellID == 0 and (r.spellID or 0) > 0 then entry.spellID = r.spellID end
                            if not entry.recipeIcon and r.recipeIcon then entry.recipeIcon = r.recipeIcon end
                            if (not entry.reagents or #entry.reagents == 0) and r.reagents and #r.reagents > 0 then
                                entry.reagents = r.reagents
                            end
                        end
                        entry.knownBy[guid] = true
                    end
                end
            end
        end
    end

    -- Pass 2: layer in the static recipe database.  For every static
    -- entry, either MERGE its identity onto the matching scanned entry
    -- (so we get the source/expansion fields without duplicating the
    -- row) or CREATE a brand-new entry with empty knownBy so the user
    -- sees recipes that nobody in the account has learned yet.
    --
    -- Match key is (profession, recipeName).  spellID is more reliable
    -- when present, but recipe names are stable and we can't always
    -- count on a scanned entry having the spellID populated yet.
    if AltTracker_RecipeDB and AltTracker_RecipeDB.GetRecipes then
        for profName, _ in pairs(TRACKABLE_PROFESSIONS) do
            local staticList = AltTracker_RecipeDB.GetRecipes(profName)
            for _, s in ipairs(staticList) do
                local key = profName .. "\0" .. (s.name or "")
                local entry = byKey[key]
                if entry then
                    -- Promote: scanned entry exists, augment with
                    -- static metadata for richer display.
                    if (entry.spellID or 0) == 0 and s.spellID then
                        entry.spellID = s.spellID
                    end
                    if (entry.itemID or 0) == 0 and s.itemID then
                        entry.itemID = s.itemID
                    end
                    if not entry.expansion and s.expansion then
                        entry.expansion = s.expansion
                    end
                    if not entry.source and s.source then
                        entry.source = s.source
                    end
                    if not entry.sourceNote and s.sourceNote then
                        entry.sourceNote = s.sourceNote
                    end
                else
                    -- Create: nobody scanned this recipe, surface it
                    -- as an unlearned row.
                    entry = {
                        key        = key,
                        profName   = profName,
                        recipe     = s.name or "",
                        itemID     = s.itemID or 0,
                        spellID    = s.spellID or 0,
                        recipeIcon = s.recipeIcon,
                        numMade    = s.numMade or 1,
                        reagents   = s.reagents,
                        expansion  = s.expansion,
                        source     = s.source,
                        sourceNote = s.sourceNote,
                        knownBy    = {},
                        _fromDB    = true,
                    }
                    byKey[key] = entry
                    table.insert(order, key)
                end
            end
        end
    end

    local entries = {}
    for _, key in ipairs(order) do entries[#entries + 1] = byKey[key] end
    return entries
end

local function EntryPassesFilters(entry, searchText, charsInView)
    if activeProf and entry.profName ~= activeProf then return false end
    if not PassesExpansion(entry) then return false end
    if searchText and searchText ~= "" then
        if not entry.recipe:lower():find(searchText, 1, true) then return false end
    end
    if showMissingOnly and charsInView then
        -- Keep rows where at least one visible character is MISSING the recipe
        local missingAny = false
        for _, c in ipairs(charsInView) do
            if not entry.knownBy[c.guid] then missingAny = true; break end
        end
        if not missingAny then return false end
    end
    return true
end

------------------------------------------------------------
-- Smart search auto-context
------------------------------------------------------------

local function MaybeAutoContextSearch(searchText)
    if not searchText or searchText == "" then return end
    if activeProf then return end
    local bestProf, bestScore
    local q = searchText:lower()

    -- Pass A: scanned recipes (what the user's alts have learned)
    for guid, data in IterCharacters() do
        if type(data) == "table" and type(data.recipes) == "table" then
            for profName, recipeList in pairs(data.recipes) do
                if TRACKABLE_PROFESSIONS[profName] and type(recipeList) == "table" then
                    for _, r in ipairs(recipeList) do
                        local n = (r.name or ""):lower()
                        local idx = n:find(q, 1, true)
                        if idx then
                            local score = (idx - 1) * 1000 + #n
                            if not bestScore or score < bestScore then
                                bestScore = score
                                bestProf  = profName
                            end
                        end
                    end
                end
            end
        end
    end

    -- Pass B: static recipe DB.  Same scoring.  Lets the user search
    -- for a recipe they haven't learned yet and still snap to the
    -- correct profession context.
    if AltTracker_RecipeDB and AltTracker_RecipeDB.GetRecipes then
        for profName in pairs(TRACKABLE_PROFESSIONS) do
            local list = AltTracker_RecipeDB.GetRecipes(profName)
            for _, s in ipairs(list) do
                local n = (s.name or ""):lower()
                local idx = n:find(q, 1, true)
                if idx then
                    local score = (idx - 1) * 1000 + #n
                    if not bestScore or score < bestScore then
                        bestScore = score
                        bestProf  = profName
                    end
                end
            end
        end
    end

    if bestProf then
        activeProf      = bestProf
        activeExpansion = "all"
        if AT_PROFS._RestyleFilterButtons then AT_PROFS._RestyleFilterButtons() end
    end
end

------------------------------------------------------------
-- Tooltips (SetHyperlink — the TBC-correct API)
------------------------------------------------------------

local function ShowRecipeTooltip(anchor, entry)
    GameTooltip:SetOwner(anchor, "ANCHOR_RIGHT")
    GameTooltip:ClearLines()
    if entry.spellID and entry.spellID > 0 then
        GameTooltip:SetHyperlink("enchant:" .. entry.spellID)
    elseif entry.itemID and entry.itemID > 0 then
        GameTooltip:SetHyperlink("item:" .. entry.itemID)
    else
        GameTooltip:SetText(entry.recipe, 1, 1, 1)
    end

    -- Augment with static-DB metadata when present.  We use AddLine
    -- on the existing tooltip rather than building one from scratch
    -- so the native recipe / item info still renders above.
    if entry.source then
        local line = "|cffaaaaaaSource:|r " .. entry.source
        if entry.sourceNote then
            line = line .. " — " .. entry.sourceNote
        end
        GameTooltip:AddLine(" ", 1, 1, 1)
        GameTooltip:AddLine(line, 0.85, 0.85, 0.55)
    end
    if entry._fromDB and next(entry.knownBy) == nil then
        GameTooltip:AddLine("|cffff8080Not learned by any character.|r", 1, 0.5, 0.5)
    end

    GameTooltip:Show()
end

local function ShowProductTooltip(anchor, entry)
    if not (entry.itemID and entry.itemID > 0) then
        ShowRecipeTooltip(anchor, entry); return
    end
    GameTooltip:SetOwner(anchor, "ANCHOR_RIGHT")
    GameTooltip:ClearLines()
    GameTooltip:SetHyperlink("item:" .. entry.itemID)
    GameTooltip:Show()
end

------------------------------------------------------------
-- Check/miss cell textures
------------------------------------------------------------

local CHECK_TEXTURE = "Interface\\RAIDFRAME\\ReadyCheck-Ready"
local MISS_TEXTURE  = "Interface\\RAIDFRAME\\ReadyCheck-NotReady"

local function GetRow(index)
    if rowPool[index] then return rowPool[index] end

    local row = CreateFrame("Frame", nil, matrixContent)
    row:SetHeight(ROW_HEIGHT)
    row:EnableMouse(true)

    local bg = row:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(); bg:SetColorTexture(1, 1, 1, 0)
    row.bg = bg

    local selBorder = row:CreateTexture(nil, "BORDER")
    selBorder:SetAllPoints(); selBorder:SetColorTexture(0, 1, 0.9, 0)
    row.selBorder = selBorder

    local hover = row:CreateTexture(nil, "ARTWORK")
    hover:SetAllPoints(); hover:SetColorTexture(0.15, 0.30, 0.30, 0)
    row.hover = hover

    -- Recipe icon button (column 1)
    local riBtn = CreateFrame("Button", nil, row)
    riBtn:SetSize(ICON_SIZE, ICON_SIZE)
    riBtn:SetPoint("LEFT", row, "LEFT", 3, 0)
    local riTex = riBtn:CreateTexture(nil, "ARTWORK")
    riTex:SetAllPoints(); riTex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    riBtn.tex = riTex
    row.recipeIcon = riBtn

    -- Product icon button (column 2)
    local piBtn = CreateFrame("Button", nil, row)
    piBtn:SetSize(ICON_SIZE, ICON_SIZE)
    piBtn:SetPoint("LEFT", riBtn, "RIGHT", 6, 0)
    local piTex = piBtn:CreateTexture(nil, "ARTWORK")
    piTex:SetAllPoints(); piTex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    piBtn.tex = piTex
    row.productIcon = piBtn

    -- Name button (column 3)
    local nameBtn = CreateFrame("Button", nil, row)
    nameBtn:SetPoint("LEFT", piBtn, "RIGHT", 6, 0)
    nameBtn:SetSize(COL_W_NAME, ROW_HEIGHT)
    local nameText = nameBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    nameText:SetPoint("LEFT", nameBtn, "LEFT", 0, 0)
    nameText:SetPoint("RIGHT", nameBtn, "RIGHT", 0, 0)
    nameText:SetJustifyH("LEFT")
    nameText:SetWordWrap(false); nameText:SetNonSpaceWrap(false)
    nameBtn.text = nameText
    row.nameBtn = nameBtn

    -- % known
    local pctText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    pctText:SetJustifyH("RIGHT"); pctText:SetJustifyV("MIDDLE")
    row.pctText = pctText

    -- AH + Craft
    local ahText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    ahText:SetJustifyH("RIGHT"); ahText:SetJustifyV("MIDDLE")
    row.ahText = ahText

    local craftText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    craftText:SetJustifyH("RIGHT"); craftText:SetJustifyV("MIDDLE")
    row.craftText = craftText

    row.checkCells = {}
    row.entry = nil

    local function ShowHover()  row.hover:SetColorTexture(0.15, 0.30, 0.30, 0.35) end
    local function HideHover()  row.hover:SetColorTexture(0.15, 0.30, 0.30, 0) end

    local function SelectThisRow()
        if row.entry then
            selectedEntryKey = row.entry.key
            AT_PROFS._RefreshSelectionVisuals()
        end
    end
    row:SetScript("OnMouseDown", SelectThisRow)

    riBtn:SetScript("OnEnter", function(self)
        if row.entry then ShowRecipeTooltip(self, row.entry); ShowHover() end
    end)
    riBtn:SetScript("OnLeave", function() GameTooltip:Hide(); HideHover() end)
    riBtn:SetScript("OnClick", SelectThisRow)

    piBtn:SetScript("OnEnter", function(self)
        if row.entry then ShowProductTooltip(self, row.entry); ShowHover() end
    end)
    piBtn:SetScript("OnLeave", function() GameTooltip:Hide(); HideHover() end)
    piBtn:SetScript("OnClick", SelectThisRow)

    nameBtn:SetScript("OnEnter", function(self)
        if row.entry then ShowRecipeTooltip(self, row.entry); ShowHover() end
    end)
    nameBtn:SetScript("OnLeave", function() GameTooltip:Hide(); HideHover() end)
    nameBtn:SetScript("OnClick", SelectThisRow)

    rowPool[index] = row
    return row
end

local function GetCheckCell(row, index)
    if row.checkCells[index] then return row.checkCells[index] end
    local cell = CreateFrame("Frame", nil, row)
    cell:SetSize(COL_W_CHAR, ROW_HEIGHT)
    local tex = cell:CreateTexture(nil, "OVERLAY")
    tex:SetSize(12, 12)
    tex:SetPoint("CENTER", cell, "CENTER", 0, 0)
    cell.tex = tex
    row.checkCells[index] = cell
    return cell
end

-- Collapsible profession section header
local function GetSectionRow(index)
    if sectionRowPool[index] then return sectionRowPool[index] end
    local row = CreateFrame("Button", nil, matrixContent)
    row:SetHeight(ROW_HEIGHT)
    row:EnableMouse(true)

    local bg = row:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(); bg:SetColorTexture(0.10, 0.25, 0.25, 0.6)
    row.bg = bg

    local hover = row:CreateTexture(nil, "ARTWORK")
    hover:SetAllPoints(); hover:SetColorTexture(0.15, 0.45, 0.45, 0)
    row.hover = hover

    -- Expand/collapse arrow — use WoW's built-in plus/minus textures
    -- rather than Unicode arrows, which rendered as placeholder boxes
    -- in the default game font.
    local arrow = row:CreateTexture(nil, "OVERLAY")
    arrow:SetSize(14, 14)
    arrow:SetPoint("LEFT", row, "LEFT", 6, 0)
    row.arrow = arrow

    local tex = row:CreateTexture(nil, "ARTWORK")
    tex:SetSize(16, 16); tex:SetPoint("LEFT", arrow, "RIGHT", 4, 0)
    tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    row.icon = tex

    local lbl = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    lbl:SetPoint("LEFT", tex, "RIGHT", 6, 0)
    lbl:SetTextColor(0, 1, 0.9)
    row.label = lbl

    local count = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    count:SetPoint("LEFT", lbl, "RIGHT", 10, 0)
    count:SetTextColor(0.6, 0.6, 0.6)
    row.count = count

    -- Per-character "known count for this profession", aligned with
    -- each character column. Populated lazily during render.
    row.charCountCells = {}

    row:SetScript("OnEnter", function() row.hover:SetColorTexture(0.15, 0.45, 0.45, 0.35) end)
    row:SetScript("OnLeave", function() row.hover:SetColorTexture(0.15, 0.45, 0.45, 0) end)

    row:SetScript("OnClick", function()
        local ui = GetUIState()
        local prof = row._profName
        if not prof then return end
        ui.collapsed[prof] = not ui.collapsed[prof] or nil
        AT_PROFS.RefreshResults()
    end)

    sectionRowPool[index] = row
    return row
end

-- Per-character small count FontString on a section-header row.
-- Created lazily, one per char column.
local function GetSectionCharCount(secRow, index)
    if secRow.charCountCells[index] then return secRow.charCountCells[index] end
    local fs = secRow:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    fs:SetWidth(COL_W_CHAR)
    fs:SetJustifyH("CENTER"); fs:SetJustifyV("MIDDLE")
    secRow.charCountCells[index] = fs
    return fs
end

-- Character column header (class icon above, race icon below)
local function GetCharHeader(index)
    if headerPool[index] then return headerPool[index] end
    local h = CreateFrame("Frame", nil, charHeaderStrip)
    h:SetSize(COL_W_CHAR, HEADER_HEIGHT)
    h:EnableMouse(true)

    local bg = h:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(); bg:SetColorTexture(0.10, 0.10, 0.15, 0.6)
    h.bg = bg

    local classTex = h:CreateTexture(nil, "ARTWORK")
    classTex:SetSize(HDR_CLASS_ICON, HDR_CLASS_ICON)
    classTex:SetPoint("TOP", h, "TOP", 0, -4)
    classTex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    h.classTex = classTex

    local raceTex = h:CreateTexture(nil, "ARTWORK")
    raceTex:SetSize(HDR_RACE_ICON, HDR_RACE_ICON)
    raceTex:SetPoint("TOP", classTex, "BOTTOM", 0, -3)
    -- No SetTexCoord here — atlas sprites provide their own coords
    h.raceTex = raceTex

    -- Small class-colored dot as a fallback / accent at the bottom
    local accent = h:CreateTexture(nil, "OVERLAY")
    accent:SetSize(COL_W_CHAR - 4, 2)
    accent:SetPoint("BOTTOM", h, "BOTTOM", 0, 2)
    h.accent = accent

    h:SetScript("OnEnter", function(self)
        if self._charData then
            local c = self._charData
            GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
            GameTooltip:ClearLines()
            local cr, cg, cb = ClassColor(c.class)
            GameTooltip:AddLine(c.name, cr, cg, cb)
            if c.level and c.level > 0 then
                local line = "Level " .. c.level
                if c.race and RACE_DISPLAY[c.race] then
                    line = line .. " " .. RACE_DISPLAY[c.race]
                end
                if c.class and CLASS_DISPLAY[c.class] then
                    line = line .. " " .. CLASS_DISPLAY[c.class]
                end
                GameTooltip:AddLine(line, 0.8, 0.8, 0.8)
            end
            GameTooltip:Show()
        end
    end)
    h:SetScript("OnLeave", function() GameTooltip:Hide() end)

    headerPool[index] = h
    return h
end

------------------------------------------------------------
-- Filter button restyling
--
-- Inactive profession icons are desaturated (50% brightness) and have
-- a subtle dark border. Active profession icon renders at full color
-- with a bright yellow border so it stands out unambiguously.
------------------------------------------------------------

function AT_PROFS._RestyleFilterButtons()
    local ar, ag, ab = AltTracker.GetAccentRGB()
    for k, b in pairs(expButtons) do
        if k == activeExpansion and not activeProf then
            -- Active expansion button: dark neutral bg + accent text
            b:SetBackdropColor(0.18, 0.18, 0.18, 1)
            b:SetBackdropBorderColor(ar, ag, ab, 1)
            b.lbl:SetTextColor(ar, ag, ab)
        else
            b:SetBackdropColor(0.10, 0.10, 0.10, 1)
            b:SetBackdropBorderColor(0, 0, 0, 1)
            b.lbl:SetTextColor(0.55, 0.55, 0.55)
        end
    end
    for pn, fb in pairs(profButtons) do
        if pn == activeProf then
            fb:SetBackdropColor(0.18, 0.18, 0.18, 1)
            fb:SetBackdropBorderColor(ar, ag, ab, 1)
            fb.iconTex:SetAlpha(1.0)
            if profButtonBorders[pn] then profButtonBorders[pn]:Show() end
        else
            fb:SetBackdropColor(0.10, 0.10, 0.10, 1)
            fb:SetBackdropBorderColor(0, 0, 0, 1)
            fb.iconTex:SetAlpha(0.45)
            if profButtonBorders[pn] then profButtonBorders[pn]:Hide() end
        end
    end
end

function AT_PROFS._RefreshSelectionVisuals()
    local ar, ag, ab = AltTracker.GetAccentRGB()
    for _, row in ipairs(rowPool) do
        if row:IsShown() and row.entry and row.entry.key == selectedEntryKey then
            row.selBorder:SetColorTexture(ar, ag, ab, 0.25)
        else
            row.selBorder:SetColorTexture(0, 0, 0, 0)
        end
    end
end

local function SetExpansionFilter(expKey)
    activeExpansion = expKey
    activeProf = nil
    AT_PROFS._RestyleFilterButtons()
    AT_PROFS.RefreshResults()
end

local function SetProfessionFilter(profName)
    activeProf = profName
    if profName then activeExpansion = "all" end
    AT_PROFS._RestyleFilterButtons()
    AT_PROFS.RefreshResults()
end

------------------------------------------------------------
-- Panel construction
------------------------------------------------------------

local function BuildPanel(mainFrame)
    if panel then return end

    -- Read layout contract from AltTracker. Fall back to the known defaults
    -- if the plugin somehow loads before SheetUI publishes the table.
    local L         = (AltTracker and AltTracker.LAYOUT) or {}
    local SIDEBAR_W = L.SIDEBAR_WIDTH or 190
    local TITLE_H   = L.TITLE_H        or 30

    -- Anchor the plugin panel inside the content area, below the global title
    -- bar. PANEL_T was 0 here, which made "Recipes" overlap "AltTracker" in
    -- the title bar. The plugin hides the totals bar on activate (see
    -- AT_PROFS.Activate) so the panel still extends to the bottom edge of the
    -- frame the way it always did.
    local PANEL_L   = SIDEBAR_W
    local PANEL_T   = TITLE_H
    local PANEL_R   = 0
    local PANEL_B   = 1

    panel = CreateFrame("Frame", "AltTrackerProfessionsPanel", mainFrame, "BackdropTemplate")
    panel:SetPoint("TOPLEFT",     mainFrame, "TOPLEFT",     PANEL_L,  -PANEL_T)
    panel:SetPoint("BOTTOMRIGHT", mainFrame, "BOTTOMRIGHT", -PANEL_R, PANEL_B)
    AltTracker.ApplyBGOnly(panel, 0.06, 0.06, 0.06, 0.97)

    -- Header
    local header = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    header:SetPoint("TOPLEFT", 12, -10)
    header:SetText("Recipes")
    -- Color matches the current theme accent
    C_Timer.After(0, function()
        local r, g, b = AltTracker.GetAccentRGB()
        header:SetTextColor(r, g, b)
    end)
    AltTracker.RegisterThemeCallback(function()
        local r, g, b = AltTracker.GetAccentRGB()
        header:SetTextColor(r, g, b)
    end)

    local hint = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hint:SetPoint("LEFT", header, "RIGHT", 8, 0)
    hint:SetTextColor(0.45, 0.45, 0.45)
    hint:SetText("✓ = learned  ✗ = not learned  Click profession header to collapse")

    -- Search
    local searchLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    searchLabel:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -10)
    searchLabel:SetTextColor(0.50, 0.50, 0.50)
    searchLabel:SetText("Search:")

    searchBox = CreateFrame("EditBox", "AltTrackerProfSearchBox", panel, "InputBoxTemplate")
    searchBox:SetSize(260, 20)
    searchBox:SetPoint("LEFT", searchLabel, "RIGHT", 8, 0)
    searchBox:SetAutoFocus(false)
    searchBox:SetMaxLetters(80)
    searchBox:SetScript("OnTextChanged", function(self, userInput)
        if userInput then
            local text = strtrim(self:GetText() or ""):lower()
            MaybeAutoContextSearch(text)
        end
        AT_PROFS.RefreshResults()
    end)
    searchBox:SetScript("OnEscapePressed", function(self) self:SetText(""); self:ClearFocus() end)

    local clearBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    clearBtn:SetSize(50, 22)
    clearBtn:SetPoint("LEFT", searchBox, "RIGHT", 6, 0)
    clearBtn:SetText("Clear")
    clearBtn:SetScript("OnClick", function() searchBox:SetText(""); searchBox:ClearFocus() end)

    -- "Show only unknown" toggle
    showMissingCheckbox = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
    showMissingCheckbox:SetSize(24, 24)
    showMissingCheckbox:SetPoint("LEFT", clearBtn, "RIGHT", 12, 0)
    showMissingCheckbox.text:SetText("Only rows with missing characters")
    showMissingCheckbox.text:SetTextColor(0.8, 0.8, 0.8)
    showMissingCheckbox:SetChecked(false)
    showMissingCheckbox:SetScript("OnClick", function(self)
        showMissingOnly = self:GetChecked() and true or false
        AT_PROFS.RefreshResults()
    end)

    -- Expansion filter row
    local expLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    expLabel:SetPoint("TOPLEFT", searchLabel, "BOTTOMLEFT", 0, -10)
    expLabel:SetText("Expansion:")
    expLabel:SetTextColor(0.50, 0.50, 0.50)

    local function MakeExpButton(expKey, text, anchor, xOff)
        local b = CreateFrame("Button", nil, panel, "BackdropTemplate")
        b:SetSize(110, 20)
        b:SetPoint("LEFT", anchor, "RIGHT", xOff or 6, 0)
        AltTracker.ApplyBackdrop(b, 0.10, 0.10, 0.10, 1)
        local lbl = b:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
        lbl:SetAllPoints(); lbl:SetJustifyH("CENTER"); lbl:SetText(text)
        lbl:SetTextColor(0.60, 0.60, 0.60)
        b.lbl = lbl
        b:SetScript("OnClick", function() SetExpansionFilter(expKey) end)
        expButtons[expKey] = b
        return b
    end

    local expBC      = MakeExpButton("bc",      "Burning Crusade",   expLabel, 8)
    local expClassic = MakeExpButton("classic", "World of Warcraft", expBC,    6)
    MakeExpButton("all", "Everything", expClassic, 6)

    -- Profession filter row
    local filterLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    filterLabel:SetPoint("TOPLEFT", expLabel, "BOTTOMLEFT", 0, -10)
    filterLabel:SetText("Profession:")
    filterLabel:SetTextColor(0.50, 0.50, 0.50)

    local prevBtn
    for i, profName in ipairs(PROF_ORDER) do
        local fb = CreateFrame("Button", nil, panel, "BackdropTemplate")
        fb:SetSize(24, 24)
        if i == 1 then
            fb:SetPoint("TOPLEFT", filterLabel, "TOPRIGHT", 8, 4)
        else
            fb:SetPoint("LEFT", prevBtn, "RIGHT", 3, 0)
        end
        AltTracker.ApplyBackdrop(fb, 0.10, 0.10, 0.10, 1)

        local tex = fb:CreateTexture(nil,"OVERLAY")
        tex:SetPoint("TOPLEFT",     fb, "TOPLEFT",     3, -3)
        tex:SetPoint("BOTTOMRIGHT", fb, "BOTTOMRIGHT", -3, 3)
        tex:SetTexture(PROF_ICONS[profName])
        tex:SetTexCoord(0.08,0.92,0.08,0.92)
        tex:SetAlpha(0.45)   -- inactive: dim not tint
        fb.iconTex = tex

        fb:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText(profName, 1, 1, 1)
            GameTooltip:AddLine("|cffaaaaaaClick to filter · click again to clear|r", 1, 1, 1)
            GameTooltip:Show()
        end)
        fb:SetScript("OnLeave", function() GameTooltip:Hide() end)

        local pn = profName
        fb:SetScript("OnClick", function()
            if activeProf == pn then
                activeProf = nil
                activeExpansion = "bc"
                AT_PROFS._RestyleFilterButtons()
                AT_PROFS.RefreshResults()
            else
                SetProfessionFilter(pn)
            end
        end)
        profButtons[profName] = fb
        prevBtn = fb
    end

    -- Divider + count label
    local divider = panel:CreateTexture(nil, "ARTWORK")
    divider:SetHeight(1)
    divider:SetPoint("TOPLEFT",  filterLabel, "BOTTOMLEFT",  0, -8)
    divider:SetPoint("TOPRIGHT", panel,       "TOPRIGHT",  -12, 0)
    divider:SetColorTexture(0.22, 0.22, 0.22, 1)

    countLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    countLabel:SetPoint("TOPLEFT", divider, "BOTTOMLEFT", 0, -6)
    countLabel:SetTextColor(0.55, 0.55, 0.55)
    countLabel:SetText("0 recipes")

    charHeaderStrip = CreateFrame("Frame", nil, panel)
    charHeaderStrip:SetPoint("TOPLEFT",  countLabel, "BOTTOMLEFT", 0, -4)
    charHeaderStrip:SetPoint("TOPRIGHT", panel,       "TOPRIGHT", -26, 0)
    charHeaderStrip:SetHeight(HEADER_HEIGHT)

    leftColumnHeader = CreateFrame("Frame", nil, charHeaderStrip)
    leftColumnHeader:SetPoint("TOPLEFT", charHeaderStrip, "TOPLEFT", 0, 0)
    leftColumnHeader:SetHeight(HEADER_HEIGHT)
    local lbg = leftColumnHeader:CreateTexture(nil, "BACKGROUND")
    lbg:SetAllPoints(); lbg:SetColorTexture(0.11, 0.11, 0.11, 1)
    local lh = leftColumnHeader:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    lh:SetPoint("BOTTOMLEFT", leftColumnHeader, "BOTTOMLEFT", 6, 4)
    lh:SetTextColor(0.7, 0.7, 0.7)
    leftColumnHeader.recipeLabel = lh

    local lhPct = leftColumnHeader:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    lhPct:SetJustifyH("RIGHT"); lhPct:SetTextColor(0.7, 0.7, 0.7)
    leftColumnHeader.pctLabel = lhPct

    local lhAH = leftColumnHeader:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    lhAH:SetJustifyH("RIGHT"); lhAH:SetTextColor(0.7, 0.7, 0.7)
    leftColumnHeader.ahLabel = lhAH

    local lhCraft = leftColumnHeader:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    lhCraft:SetJustifyH("RIGHT"); lhCraft:SetTextColor(0.7, 0.7, 0.7)
    leftColumnHeader.craftLabel = lhCraft

    matrixScroll = CreateFrame("ScrollFrame", "AltTrackerProfMatrixScroll", panel, "UIPanelScrollFrameTemplate")
    matrixScroll:SetPoint("TOPLEFT",     charHeaderStrip, "BOTTOMLEFT",  0, -2)
    matrixScroll:SetPoint("BOTTOMRIGHT", panel,           "BOTTOMRIGHT", -26, 12)

    matrixContent = CreateFrame("Frame", nil, matrixScroll)
    matrixContent:SetSize(matrixScroll:GetWidth(), 1)
    matrixScroll:SetScrollChild(matrixContent)

    matrixScroll:HookScript("OnSizeChanged", function(self, w, h)
        if matrixContent then matrixContent:SetWidth(w) end
    end)

    AT_PROFS._RestyleFilterButtons()
    panel:Hide()
end

------------------------------------------------------------
-- Render
------------------------------------------------------------

function AT_PROFS.RefreshResults()
    if not panel or not panel:IsShown() then return end
    if not matrixScroll or not matrixContent then return end

    local searchText = strtrim(searchBox and searchBox:GetText() or ""):lower()
    local chars      = CollectCharacters()
    local entries    = BuildEntries()
    local ui         = GetUIState()

    local filtered = {}
    for _, e in ipairs(entries) do
        if EntryPassesFilters(e, searchText, chars) then
            filtered[#filtered + 1] = e
        end
    end

    -- Compute known count (over all collected chars)
    local charCount = #chars
    for _, e in ipairs(filtered) do
        local n = 0
        for _ in pairs(e.knownBy or {}) do n = n + 1 end
        e._knownCount = n
        e._knownPct = (charCount > 0) and math.floor((n / charCount) * 100 + 0.5) or 0
    end

    -- Sort: profession first; within a profession known-by-many first,
    -- then name asc.
    table.sort(filtered, function(a, b)
        if a.profName ~= b.profName then return a.profName < b.profName end
        if a._knownCount ~= b._knownCount then return a._knownCount > b._knownCount end
        return a.recipe < b.recipe
    end)

    local fixedLeftW = GetLeftWidth()
    local hasAH = IsAuctionatorAvailable()

    -- Character header strip
    for _, h in ipairs(headerPool) do h:Hide() end
    for i, c in ipairs(chars) do
        local h = GetCharHeader(i)
        h._charData = c
        h:ClearAllPoints()
        h:SetPoint("TOPLEFT", charHeaderStrip, "TOPLEFT", fixedLeftW + (i - 1) * COL_W_CHAR, 0)

        local classIcon = ClassIconPath(c.class)
        if classIcon then
            h.classTex:SetTexture(classIcon); h.classTex:Show()
        else
            h.classTex:Hide()
        end
        ApplyRaceIconAtlas(h.raceTex, c.race, c.gender)
        local r, g, b = ClassColor(c.class)
        h.accent:SetColorTexture(r, g, b, 0.9)
        h:Show()
    end

    -- Left header labels: Recipe | AH | Craft
    leftColumnHeader:SetWidth(fixedLeftW)
    leftColumnHeader.recipeLabel:SetText("|cffaaaaaaRecipe|r")

    if leftColumnHeader.pctLabel then leftColumnHeader.pctLabel:Hide() end

    if hasAH then
        local ahX = COL_W_RECIPE_ICON + COL_W_PRODUCT_ICON + COL_W_NAME + 6 + COL_W_AH
        leftColumnHeader.ahLabel:ClearAllPoints()
        leftColumnHeader.ahLabel:SetPoint("BOTTOMRIGHT", leftColumnHeader, "BOTTOMLEFT", ahX, 4)
        leftColumnHeader.ahLabel:SetText("|cffaaaaaaAH|r")
        leftColumnHeader.ahLabel:Show()

        local craftX = ahX + 4 + COL_W_CRAFT
        leftColumnHeader.craftLabel:ClearAllPoints()
        leftColumnHeader.craftLabel:SetPoint("BOTTOMRIGHT", leftColumnHeader, "BOTTOMLEFT", craftX, 4)
        leftColumnHeader.craftLabel:SetText("|cffaaaaaaCraft|r")
        leftColumnHeader.craftLabel:Show()
    else
        leftColumnHeader.ahLabel:Hide()
        leftColumnHeader.craftLabel:Hide()
    end

    for _, r in ipairs(rowPool)        do r:Hide() end
    for _, r in ipairs(sectionRowPool) do r:Hide() end

    -- Pre-compute per-profession totals and per-char known counts.
    -- profTotals[prof] = total filtered recipes in that profession.
    -- profCharKnown[prof][guid] = how many of those the char knows.
    local profTotals = {}
    local profCharKnown = {}
    for _, e in ipairs(filtered) do
        profTotals[e.profName] = (profTotals[e.profName] or 0) + 1
        profCharKnown[e.profName] = profCharKnown[e.profName] or {}
        for guid in pairs(e.knownBy or {}) do
            profCharKnown[e.profName][guid] = (profCharKnown[e.profName][guid] or 0) + 1
        end
    end

    local rowIdx  = 0
    local secIdx  = 0
    local lastProf
    local yCursor = 0
    local visibleEntries = 0

    for _, e in ipairs(filtered) do
        -- Section header (each unique profession in the filtered list)
        if e.profName ~= lastProf then
            secIdx = secIdx + 1
            local sec = GetSectionRow(secIdx)
            sec._profName = e.profName
            sec:ClearAllPoints()
            sec:SetPoint("TOPLEFT",  matrixContent, "TOPLEFT",  0, -yCursor)
            sec:SetPoint("TOPRIGHT", matrixContent, "TOPRIGHT", 0, -yCursor)
            local collapsed = ui.collapsed[e.profName]
            sec.arrow:SetTexture(collapsed
                and "Interface\\Buttons\\UI-PlusButton-Up"
                or  "Interface\\Buttons\\UI-MinusButton-Up")
            sec.icon:SetTexture(PROF_ICONS[e.profName] or PROF_RECIPE_PLACEHOLDER[e.profName])
            sec.label:SetText(e.profName)
            local profTotal = profTotals[e.profName] or 0
            local profNoun  = (profTotal == 1) and "recipe" or "recipes"
            sec.count:SetText(string.format("|cffaaaaaa(%d %s)|r", profTotal, profNoun))

            -- Per-character known counts, one cell per char column,
            -- aligned with the matrix char columns below.  Each cell
            -- shows "K/T" where K is how many recipes in this
            -- profession the character knows and T is the total
            -- filtered recipes in the profession.  Colour is the same
            -- red-to-green gradient used elsewhere for completion.
            for i, c in ipairs(chars) do
                local fs = GetSectionCharCount(sec, i)
                fs:ClearAllPoints()
                fs:SetPoint("LEFT", sec, "LEFT", fixedLeftW + (i - 1) * COL_W_CHAR, 0)
                local known = (profCharKnown[e.profName] and profCharKnown[e.profName][c.guid]) or 0
                local pct   = (profTotal > 0) and (known / profTotal * 100) or 0
                local pr, pg, pb = PctGradientColor(pct)
                fs:SetText(string.format("|cff%02x%02x%02x%d|r",
                    math.floor(pr*255), math.floor(pg*255), math.floor(pb*255), known))
                fs:Show()
            end
            -- Hide leftovers if char count shrank since previous render
            for i = charCount + 1, #sec.charCountCells do
                sec.charCountCells[i]:Hide()
            end

            sec:Show()
            yCursor = yCursor + ROW_HEIGHT
            lastProf = e.profName
        end

        if not ui.collapsed[e.profName] then
            rowIdx = rowIdx + 1
            visibleEntries = visibleEntries + 1
            local row = GetRow(rowIdx)
            row.entry = e
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT",  matrixContent, "TOPLEFT",  0, -yCursor)
            row:SetPoint("TOPRIGHT", matrixContent, "TOPRIGHT", 0, -yCursor)

            local nobody = (e._knownCount == 0)
            if rowIdx % 2 == 0 then
                row.bg:SetColorTexture(0.10, 0.10, 0.14, nobody and 0.5 or 0.35)
            else
                row.bg:SetColorTexture(0.06, 0.06, 0.10, nobody and 0.5 or 0.35)
            end

            -- Column 1: profession-specific RECIPE scroll icon.
            -- We use the placeholder (per profession) rather than the
            -- crafted product icon — the user explicitly wanted a
            -- visual distinction between the two columns.
            row.recipeIcon.tex:SetTexture(PROF_RECIPE_PLACEHOLDER[e.profName] or "Interface\\Icons\\INV_Scroll_03")
            if nobody then
                -- Desaturate + dim so "nobody can make this" rows read
                -- as inactive at a glance.
                if row.recipeIcon.tex.SetDesaturated then row.recipeIcon.tex:SetDesaturated(true) end
                row.recipeIcon.tex:SetVertexColor(0.55, 0.55, 0.55)
            else
                if row.recipeIcon.tex.SetDesaturated then row.recipeIcon.tex:SetDesaturated(false) end
                row.recipeIcon.tex:SetVertexColor(1, 1, 1)
            end

            -- Column 2: actual crafted-product icon (via GetItemInfo cache).
            if e.itemID and e.itemID > 0 then
                local icon = RequestItemIcon(e.itemID)
                if icon then
                    row.productIcon.tex:SetTexture(icon)
                    if nobody then
                        if row.productIcon.tex.SetDesaturated then row.productIcon.tex:SetDesaturated(true) end
                        row.productIcon.tex:SetVertexColor(0.55, 0.55, 0.55)
                    else
                        if row.productIcon.tex.SetDesaturated then row.productIcon.tex:SetDesaturated(false) end
                        row.productIcon.tex:SetVertexColor(1, 1, 1)
                    end
                else
                    -- Still waiting on item cache — show the recipe icon
                    -- dimmed, rather than a big red "?".
                    if row.productIcon.tex.SetDesaturated then row.productIcon.tex:SetDesaturated(true) end
                    row.productIcon.tex:SetTexture(PROF_RECIPE_PLACEHOLDER[e.profName] or GENERIC_PRODUCT_ICON)
                    row.productIcon.tex:SetVertexColor(0.5, 0.5, 0.5)
                end
                row.productIcon:Show()
            else
                -- Recipes with no crafted item (enchantments etc.)
                if row.productIcon.tex.SetDesaturated then row.productIcon.tex:SetDesaturated(true) end
                row.productIcon.tex:SetTexture(GENERIC_PRODUCT_ICON)
                row.productIcon.tex:SetVertexColor(0.25, 0.25, 0.25)
                row.productIcon:Show()
            end

            row.nameBtn.text:SetText(e.recipe)
            if nobody then
                row.nameBtn.text:SetTextColor(0.55, 0.55, 0.55)
            else
                row.nameBtn.text:SetTextColor(0.95, 0.95, 0.95)
            end

            -- % Known column is gone — per-row; the profession section
            -- header row now carries per-character known counts instead.
            row.pctText:Hide()

            if hasAH then
                local ahX    = COL_W_RECIPE_ICON + COL_W_PRODUCT_ICON + COL_W_NAME + 6 + COL_W_AH
                local craftX = ahX + 4 + COL_W_CRAFT

                row.ahText:ClearAllPoints()
                row.ahText:SetPoint("RIGHT", row, "LEFT", ahX, 0)
                row.ahText:SetWidth(COL_W_AH)
                row.ahText:SetText(FormatMoney(GetAHPriceCopper(e.itemID)))
                row.ahText:Show()

                row.craftText:ClearAllPoints()
                row.craftText:SetPoint("RIGHT", row, "LEFT", craftX, 0)
                row.craftText:SetWidth(COL_W_CRAFT)
                local craftCost = ComputeCraftCost(e)
                if craftCost and e.numMade and e.numMade > 1 then
                    craftCost = math.floor(craftCost / e.numMade)
                end
                row.craftText:SetText(FormatMoney(craftCost))
                row.craftText:Show()
            else
                row.ahText:Hide()
                row.craftText:Hide()
            end

            -- Check/miss cells per character
            for i, c in ipairs(chars) do
                local cell = GetCheckCell(row, i)
                cell:ClearAllPoints()
                cell:SetPoint("LEFT", row, "LEFT", fixedLeftW + (i - 1) * COL_W_CHAR, 0)
                if e.knownBy and e.knownBy[c.guid] then
                    cell.tex:SetTexture(CHECK_TEXTURE)
                    cell.tex:SetVertexColor(1, 1, 1)
                    cell.tex:Show()
                else
                    -- Visible "not learned" marker — a dim red X — so the
                    -- user can distinguish "not learned" from "no data".
                    cell.tex:SetTexture(MISS_TEXTURE)
                    cell.tex:SetVertexColor(0.8, 0.3, 0.3)
                    cell.tex:SetAlpha(0.65)
                    cell.tex:Show()
                end
                cell:Show()
            end
            for i = charCount + 1, #row.checkCells do
                row.checkCells[i]:Hide()
            end

            row:Show()
            yCursor = yCursor + ROW_HEIGHT
        end
    end

    if countLabel then
        local noun = (visibleEntries == 1) and "recipe" or "recipes"
        countLabel:SetText(visibleEntries .. " " .. noun)
    end

    matrixContent:SetHeight(math.max(yCursor + 4, matrixScroll:GetHeight()))
    AT_PROFS._RefreshSelectionVisuals()
end

------------------------------------------------------------
-- Activate / Deactivate
------------------------------------------------------------

function AT_PROFS.Activate(mainFrame)
    BuildPanel(mainFrame)
    AT_PROFS.isActive = true

    if mainFrame.bodyScroll   then mainFrame.bodyScroll:Hide()   end
    if mainFrame.frozenScroll then mainFrame.frozenScroll:Hide() end
    if mainFrame.headerScroll then mainFrame.headerScroll:Hide() end
    if mainFrame.frozenHeader then mainFrame.frozenHeader:Hide() end
    if mainFrame.hScrollBar   then mainFrame.hScrollBar:Hide()   end
    if mainFrame.totalsBar    then mainFrame.totalsBar:Hide()    end

    -- Recipes benefits from more vertical space for the scroll list.
    -- SetSize changes only the dimensions; the frame stays at its current position.
    local f = _G["AltTrackerSheet"]
    if f then f:SetSize(1050, 490) end

    panel:Show()
    AT_PROFS.RefreshResults()
    if searchBox then searchBox:SetFocus() end

    -- Pre-fetch all product icons to warm the client cache
    for guid, data in IterCharacters() do
        if type(data) == "table" and type(data.recipes) == "table" then
            for _, list in pairs(data.recipes) do
                if type(list) == "table" then
                    for _, r in ipairs(list) do
                        if r.itemID and r.itemID > 0 then RequestItemIcon(r.itemID) end
                    end
                end
            end
        end
    end
end

function AT_PROFS.Deactivate(mainFrame)
    AT_PROFS.isActive = false
    if panel then panel:Hide() end

    if mainFrame.bodyScroll   then mainFrame.bodyScroll:Show()   end
    if mainFrame.frozenScroll then mainFrame.frozenScroll:Show() end
    if mainFrame.headerScroll then mainFrame.headerScroll:Show() end
    if mainFrame.frozenHeader then mainFrame.frozenHeader:Show() end
    if mainFrame.hScrollBar   then mainFrame.hScrollBar:Show()   end
    if mainFrame.totalsBar    then mainFrame.totalsBar:Show()    end
end