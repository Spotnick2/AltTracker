------------------------------------------------------------
-- AltTracker Toasts
-- Shows a small notification when a profession cooldown
-- expires, telling you which character and which cooldown.
--
-- Config keys (in AltTrackerConfig):
--   toastsEnabled       : boolean (master toggle, default true)
--   toastProfessions    : { Tailoring=true, Alchemy=true, ... }
--
-- Cooldown data lives on each character record as unix
-- timestamps: cd_Mooncloth, cd_Transmute, etc.  A value
-- of 0 means "no CD tracked" (skip), >0 and <= time()
-- means "ready".
------------------------------------------------------------

AltTracker = AltTracker or {}

------------------------------------------------------------
-- Constants
------------------------------------------------------------

local CHECK_INTERVAL  = 30     -- seconds between CD scans
local TOAST_DURATION  = 6      -- seconds the toast stays visible
local TOAST_FADE_TIME = 1      -- seconds to fade out
local TOAST_WIDTH     = 320
local TOAST_HEIGHT    = 52
local TOAST_SPACING   = 6      -- vertical gap between stacked toasts
local TOAST_OFFSET_Y  = 80     -- pixels above screen center for topmost toast
local MAX_TOASTS      = 5      -- max visible at once (queue the rest)

------------------------------------------------------------
-- All cooldown definitions (mirrored from Scanner.lua's
-- ProfCDKeys, but defined locally so Toasts.lua doesn't
-- depend on ScanCharacter having run first).
------------------------------------------------------------

local CD_DEFS = {
    { profKey = "Tailoring",     key = "cd_Mooncloth",      name = "Primal Mooncloth", minSkill = 350 },
    { profKey = "Tailoring",     key = "cd_Shadowcloth",    name = "Shadowcloth",      minSkill = 350 },
    { profKey = "Tailoring",     key = "cd_Spellcloth",     name = "Spellcloth",       minSkill = 350 },
    { profKey = "Alchemy",       key = "cd_Transmute",      name = "Transmute",        minSkill = 350 },
    { profKey = "Jewelcrafting", key = "cd_BrilliantGlass", name = "Brilliant Glass",  minSkill = 350 },
}

------------------------------------------------------------
-- State
------------------------------------------------------------

-- Tracks which (guid + cdKey + expiryTimestamp) combos we
-- have already shown a toast for this session.  Keyed as
-- "guid:cdKey:expiry" → true.
local notified = {}

-- Pool of toast frames (created on demand, recycled)
local toastPool  = {}
local activeToasts = {}
local toastQueue   = {}

------------------------------------------------------------
-- Helpers
------------------------------------------------------------

local function Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cff00ccff[AltTracker]|r " .. msg)
end

local function IsToastEnabled(profKey)
    AltTrackerConfig = AltTrackerConfig or {}
    if AltTrackerConfig.toastsEnabled == false then return false end

    local profs = AltTrackerConfig.toastProfessions
    if not profs then return true end  -- no per-prof config yet → all enabled

    -- If the profession key exists and is explicitly false, suppress
    if profs[profKey] == false then return false end
    return true
end

-- Returns true if the character has the given profession at or above
-- the required minimum skill.  Checks the flat "prof_<n>" field set
-- by Scanner.lua, and falls back to prof1/prof2 legacy fields.
local function CharHasProfession(char, profKey, minSkill)
    minSkill = minSkill or 0

    -- New flat field: prof_Tailoring, prof_Alchemy, etc.
    local skill = tonumber(char["prof_" .. profKey]) or 0
    if skill >= minSkill then return true end

    -- Legacy fields -- check skill level from prof1Skill / prof2Skill
    if char.prof1 == profKey then
        local s = tonumber(char.prof1Skill) or 0
        if s >= minSkill then return true end
    end
    if char.prof2 == profKey then
        local s = tonumber(char.prof2Skill) or 0
        if s >= minSkill then return true end
    end

    return false
end

-- Strip cooldown fields from own-account characters who don't have
-- the matching profession.  These are orphans from old sync bugs.
-- Only touches characters on this account — synced profession data
-- from other accounts can't be trusted either.
local function CleanOrphanedCooldowns()
    AltTrackerDB = AltTrackerDB or {}
    AltTrackerConfig = AltTrackerConfig or {}

    local myAccount = AltTrackerConfig.accountNumber
    if not myAccount or myAccount == "" then return end

    local cleaned = 0
    for guid, char in pairs(AltTrackerDB) do
        if type(char) == "table" then
            local charAcct = char.account
            if charAcct and tostring(charAcct) == tostring(myAccount) then
                for _, def in ipairs(CD_DEFS) do
                    if char[def.key] then
                        local hasProfSkill = CharHasProfession(char, def.profKey, def.minSkill)
                        local knowsRecipe  = char["known_" .. def.key]
                        if not hasProfSkill or not knowsRecipe then
                            char[def.key] = nil
                            -- Also clean the known_ flag if profession is gone
                            if not hasProfSkill then
                                char["known_" .. def.key] = nil
                            end
                            cleaned = cleaned + 1
                        end
                    end
                end
            end
        end
    end
    if cleaned > 0 then
        Print("Cleaned " .. cleaned .. " orphaned cooldown field(s).")
    end
end

------------------------------------------------------------
-- Toast frame factory
------------------------------------------------------------

-- Class colors for the character name
local CLASS_COLORS = {
    WARRIOR     = "ffc69b6d",
    PALADIN     = "fff48cba",
    HUNTER      = "ffaad372",
    ROGUE       = "fffff468",
    PRIEST      = "ffffffff",
    SHAMAN      = "ff0070dd",
    MAGE        = "ff3fc7eb",
    WARLOCK     = "ff8788ee",
    DRUID       = "ffff7c0a",
}

local function CreateToast()
    local f = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    f:SetSize(TOAST_WIDTH, TOAST_HEIGHT)
    f:SetFrameStrata("FULLSCREEN_DIALOG")
    f:SetBackdrop({
        bgFile   = "Interface/Tooltips/UI-Tooltip-Background",
        edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    f:SetBackdropColor(0.08, 0.08, 0.12, 0.92)
    f:SetBackdropBorderColor(0.4, 0.4, 0.5, 0.8)

    -- Icon placeholder (left side)
    local icon = f:CreateTexture(nil, "ARTWORK")
    icon:SetSize(28, 28)
    icon:SetPoint("LEFT", 10, 0)
    icon:SetTexture("Interface/Icons/INV_Misc_Gear_01")
    f.icon = icon

    -- Title line (character name + cooldown name)
    local title = f:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    title:SetPoint("TOPLEFT", icon, "TOPRIGHT", 8, -2)
    title:SetPoint("RIGHT", f, "RIGHT", -10, 0)
    title:SetJustifyH("LEFT")
    f.title = title

    -- Subtitle line
    local sub = f:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -2)
    sub:SetPoint("RIGHT", f, "RIGHT", -10, 0)
    sub:SetJustifyH("LEFT")
    sub:SetTextColor(0.7, 0.7, 0.7)
    f.subtitle = sub

    -- Fade-out animation group
    local ag = f:CreateAnimationGroup()
    local fadeOut = ag:CreateAnimation("Alpha")
    fadeOut:SetFromAlpha(1)
    fadeOut:SetToAlpha(0)
    fadeOut:SetDuration(TOAST_FADE_TIME)
    fadeOut:SetSmoothing("OUT")
    ag:SetScript("OnFinished", function()
        f:Hide()
        f:SetAlpha(1)
        -- Return to pool
        for i, t in ipairs(activeToasts) do
            if t == f then
                table.remove(activeToasts, i)
                break
            end
        end
        table.insert(toastPool, f)
        -- Reposition remaining toasts
        AltTracker.RepositionToasts()
        -- Show next queued toast if any
        AltTracker.DrainToastQueue()
    end)
    f.fadeGroup = ag

    f:Hide()
    return f
end

local function AcquireToast()
    local f = table.remove(toastPool)
    if not f then
        f = CreateToast()
    end
    return f
end

------------------------------------------------------------
-- Profession icons (best-effort mapping)
------------------------------------------------------------

local PROF_ICONS = {
    Tailoring     = "Interface/Icons/Trade_Tailoring",
    Alchemy       = "Interface/Icons/Trade_Alchemy",
    Jewelcrafting = "Interface/Icons/INV_Misc_Gem_01",
}

------------------------------------------------------------
-- Toast positioning + display
------------------------------------------------------------

function AltTracker.RepositionToasts()
    for i, f in ipairs(activeToasts) do
        f:ClearAllPoints()
        -- Stack downward from above center
        local yOff = TOAST_OFFSET_Y - ((i - 1) * (TOAST_HEIGHT + TOAST_SPACING))
        f:SetPoint("TOP", UIParent, "CENTER", 0, yOff)
    end
end

function AltTracker.DrainToastQueue()
    while #toastQueue > 0 and #activeToasts < MAX_TOASTS do
        local info = table.remove(toastQueue, 1)
        AltTracker.ShowToast(info.charName, info.charClass, info.cdName, info.profKey)
    end
end

function AltTracker.ShowToast(charName, charClass, cdName, profKey)
    -- If we're at capacity, queue it
    if #activeToasts >= MAX_TOASTS then
        table.insert(toastQueue, {
            charName  = charName,
            charClass = charClass,
            cdName    = cdName,
            profKey   = profKey,
        })
        return
    end

    local f = AcquireToast()

    -- Class-colored name
    local colorCode = CLASS_COLORS[charClass] or "ffffffff"
    f.title:SetText("|c" .. colorCode .. charName .. "|r — " .. cdName)
    f.subtitle:SetText("Cooldown ready!")

    -- Profession icon
    local iconPath = PROF_ICONS[profKey] or "Interface/Icons/INV_Misc_Gear_01"
    f.icon:SetTexture(iconPath)

    table.insert(activeToasts, f)
    AltTracker.RepositionToasts()

    f:SetAlpha(1)
    f:Show()

    -- Schedule fade-out
    C_Timer.After(TOAST_DURATION, function()
        if f:IsShown() then
            f.fadeGroup:Play()
        end
    end)
end

------------------------------------------------------------
-- Cooldown scanner — runs periodically, fires toasts
------------------------------------------------------------

local function ScanCooldowns()
    AltTrackerDB = AltTrackerDB or {}
    AltTrackerConfig = AltTrackerConfig or {}

    if AltTrackerConfig.toastsEnabled == false then return end

    -- Only show toasts for characters on this account.
    -- We can only trust profession/CD data for characters we've
    -- actually logged into — synced data may be corrupted.
    local myAccount = AltTrackerConfig.accountNumber
    if not myAccount or myAccount == "" then
        -- No account number configured — fall back to only the
        -- current character's GUID to avoid showing garbage.
        myAccount = nil
    end

    local currentGUID = UnitGUID("player")
    local now = time()

    for guid, char in pairs(AltTrackerDB) do
        if type(char) == "table" and char.name then

            -- Account filter: either matches our account number,
            -- or if no account is configured, only current character.
            local isOurs = false
            if myAccount then
                local charAcct = char.account
                isOurs = charAcct and tostring(charAcct) == tostring(myAccount)
            else
                isOurs = (guid == currentGUID)
            end

            if isOurs then
                for _, def in ipairs(CD_DEFS) do
                    -- Must have: profession at min skill AND the specific recipe learned
                    local knownRecipe = char["known_" .. def.key]
                    if IsToastEnabled(def.profKey)
                       and CharHasProfession(char, def.profKey, def.minSkill)
                       and knownRecipe then
                        local expiry = char[def.key]
                        -- expiry > 0 means a real tracked CD; <= now means it's ready
                        if expiry and expiry > 0 and expiry <= now then
                            local nKey = guid .. ":" .. def.key .. ":" .. expiry
                            if not notified[nKey] then
                                notified[nKey] = true
                                AltTracker.ShowToast(
                                    char.name,
                                    char.class or "WARRIOR",
                                    def.name,
                                    def.profKey
                                )
                            end
                        end
                    end
                end
            end

        end
    end
end

------------------------------------------------------------
-- Startup — begin periodic scanning after login
------------------------------------------------------------

local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("PLAYER_LOGIN")
initFrame:SetScript("OnEvent", function()
    -- Short delay so SavedVariables and initial scan are done
    C_Timer.After(5, function()
        -- Clean orphaned CD fields from past sync issues
        CleanOrphanedCooldowns()
        -- Initial scan
        ScanCooldowns()
        -- Repeat every CHECK_INTERVAL
        C_Timer.NewTicker(CHECK_INTERVAL, ScanCooldowns)
    end)
end)
