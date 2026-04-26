------------------------------------------------------------
-- AltTracker Toasts
-- Shows ONE aggregate notification whenever any tracked
-- profession cooldown has become ready since the last time
-- we notified about it.  The toast lists every ready CD,
-- auto-dismisses after TOAST_DURATION seconds, and closes
-- immediately on click.
--
-- Config keys (in AltTrackerConfig):
--   toastsEnabled       : boolean (master toggle, default true)
--   toastProfessions    : { Tailoring=true, Alchemy=true, ... }
--   toastsShown         : { [notifyKey]=expiryTimestamp }  (persistent)
--
-- A "notifyKey" is "guid:cdKey:expiry" — same as before, but
-- now persisted across sessions so a CD that has already been
-- announced once is never announced again, no matter how many
-- times you log between alts.
------------------------------------------------------------

AltTracker = AltTracker or {}

------------------------------------------------------------
-- Constants
------------------------------------------------------------

local TOAST_DURATION    = 10      -- seconds the toast stays visible
local TOAST_FADE_TIME   = 1       -- seconds to fade out
local TOAST_WIDTH       = 360
local TOAST_HEADER_H    = 34
local TOAST_LINE_H      = 18
local TOAST_PADDING     = 10
local TOAST_OFFSET_Y    = 120     -- pixels above screen center
local NOTIFIED_TTL      = 7*24*3600   -- prune persisted entries older than 7 days

------------------------------------------------------------
-- Cooldown definitions (mirror of Scanner.lua's ProfCDKeys)
------------------------------------------------------------

local CD_DEFS = {
    { profKey = "Tailoring",     key = "cd_Mooncloth",      name = "Primal Mooncloth", minSkill = 350 },
    { profKey = "Tailoring",     key = "cd_Shadowcloth",    name = "Shadowcloth",      minSkill = 350 },
    { profKey = "Tailoring",     key = "cd_Spellcloth",     name = "Spellcloth",       minSkill = 350 },
    { profKey = "Alchemy",       key = "cd_Transmute",      name = "Transmute",        minSkill = 350 },
    { profKey = "Jewelcrafting", key = "cd_BrilliantGlass", name = "Brilliant Glass",  minSkill = 350 },
}

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
    if not profs then return true end
    if profs[profKey] == false then return false end
    return true
end

local function CharHasProfession(char, profKey, minSkill)
    minSkill = minSkill or 0
    local skill = tonumber(char["prof_" .. profKey]) or 0
    if skill >= minSkill then return true end
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

local CLASS_COLORS = {
    WARRIOR = "ffc69b6d", PALADIN = "fff48cba", HUNTER  = "ffaad372",
    ROGUE   = "fffff468", PRIEST  = "ffffffff", SHAMAN  = "ff0070dd",
    MAGE    = "ff3fc7eb", WARLOCK = "ff8788ee", DRUID   = "ffff7c0a",
}

local PROF_ICONS = {
    Tailoring     = "Interface/Icons/Trade_Tailoring",
    Alchemy       = "Interface/Icons/Trade_Alchemy",
    Jewelcrafting = "Interface/Icons/INV_Misc_Gem_01",
}

------------------------------------------------------------
-- Persistent notified-set management
-- Stored as  AltTrackerConfig.toastsShown[key] = expiry
-- We keep the expiry as the value (not just `true`) so we
-- can GC entries whose expiry is far in the past.
------------------------------------------------------------

local function GetShownSet()
    AltTrackerConfig = AltTrackerConfig or {}
    AltTrackerConfig.toastsShown = AltTrackerConfig.toastsShown or {}
    return AltTrackerConfig.toastsShown
end

local function PruneShownSet()
    local set = GetShownSet()
    local cutoff = time() - NOTIFIED_TTL
    for k, expiry in pairs(set) do
        if type(expiry) ~= "number" or expiry < cutoff then
            set[k] = nil
        end
    end
end

------------------------------------------------------------
-- Aggregate toast frame (built lazily, reused for each toast)
------------------------------------------------------------

local toastFrame
local toastLines = {}   -- reusable FontStrings for list entries

local function BuildToastFrame()
    if toastFrame then return toastFrame end

    local f = CreateFrame("Frame", "AltTrackerAggregateToast", UIParent, "BackdropTemplate")
    f:SetSize(TOAST_WIDTH, TOAST_HEADER_H + TOAST_LINE_H + TOAST_PADDING * 2)
    f:SetFrameStrata("FULLSCREEN_DIALOG")
    f:SetBackdrop({
        bgFile   = "Interface/Tooltips/UI-Tooltip-Background",
        edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    f:SetBackdropColor(0.08, 0.08, 0.12, 0.95)
    f:SetBackdropBorderColor(0.4, 0.4, 0.5, 0.9)

    -- Header icon (changes per-call based on profession composition)
    local icon = f:CreateTexture(nil, "ARTWORK")
    icon:SetSize(26, 26)
    icon:SetPoint("TOPLEFT", 10, -6)
    icon:SetTexture("Interface/Icons/INV_Misc_PocketWatch_01")
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    f.icon = icon

    -- Header title
    local title = f:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    title:SetPoint("TOPLEFT",  icon, "TOPRIGHT", 8, -4)
    title:SetPoint("TOPRIGHT", f,    "TOPRIGHT", -30, -4)
    title:SetJustifyH("LEFT")
    title:SetTextColor(1, 0.82, 0)
    f.title = title

    -- Subtitle with dismiss hint
    local sub = f:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    sub:SetPoint("TOPLEFT",  title, "BOTTOMLEFT", 0, -2)
    sub:SetPoint("TOPRIGHT", title, "BOTTOMRIGHT", 0, -2)
    sub:SetJustifyH("LEFT")
    sub:SetText("|cff888888Click to dismiss · auto-hides in 10s|r")
    f.sub = sub

    -- Close button (clickable X)
    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetSize(24, 24)
    close:SetPoint("TOPRIGHT", 2, 2)
    close:SetScript("OnClick", function()
        if AltTracker.DismissToast then AltTracker.DismissToast() end
    end)
    f.close = close

    -- Whole frame also clickable
    f:EnableMouse(true)
    f:SetScript("OnMouseDown", function(self, button)
        if button == "LeftButton" then
            if AltTracker.DismissToast then AltTracker.DismissToast() end
        end
    end)

    -- Fade-out animation
    local ag = f:CreateAnimationGroup()
    local fadeOut = ag:CreateAnimation("Alpha")
    fadeOut:SetFromAlpha(1)
    fadeOut:SetToAlpha(0)
    fadeOut:SetDuration(TOAST_FADE_TIME)
    fadeOut:SetSmoothing("OUT")
    ag:SetScript("OnFinished", function()
        f:Hide()
        f:SetAlpha(1)
    end)
    f.fadeGroup = ag

    f:Hide()
    toastFrame = f
    return f
end

local function GetToastLine(index, parent)
    if toastLines[index] then return toastLines[index] end
    local fs = parent:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    fs:SetJustifyH("LEFT")
    toastLines[index] = fs
    return fs
end

------------------------------------------------------------
-- Dismiss / show
------------------------------------------------------------

function AltTracker.DismissToast()
    if toastFrame and toastFrame:IsShown() then
        if toastFrame._fadeTimer then
            toastFrame._fadeTimer:Cancel()
            toastFrame._fadeTimer = nil
        end
        if toastFrame.fadeGroup:IsPlaying() then
            toastFrame.fadeGroup:Stop()
        end
        toastFrame:Hide()
        toastFrame:SetAlpha(1)
    end
end

-- readyList = { { charName, charClass, cdName, profKey }, ... }
function AltTracker.ShowAggregateToast(readyList)
    if not readyList or #readyList == 0 then return end

    local f = BuildToastFrame()

    -- Cancel any existing fade / animation
    if f._fadeTimer then f._fadeTimer:Cancel(); f._fadeTimer = nil end
    if f.fadeGroup:IsPlaying() then f.fadeGroup:Stop() end
    f:SetAlpha(1)

    -- Title
    local n = #readyList
    if n == 1 then
        f.title:SetText("|cffffd200 Cooldown ready|r")
    else
        f.title:SetText(string.format("|cffffd200 %d cooldowns ready|r", n))
    end

    -- Icon: single-profession → prof icon; mixed → pocket watch
    local seenProfs = {}
    for _, r in ipairs(readyList) do seenProfs[r.profKey or ""] = true end
    local profCount = 0
    local singleProf
    for k in pairs(seenProfs) do profCount = profCount + 1; singleProf = k end
    if profCount == 1 and PROF_ICONS[singleProf] then
        f.icon:SetTexture(PROF_ICONS[singleProf])
    else
        f.icon:SetTexture("Interface/Icons/INV_Misc_PocketWatch_01")
    end

    -- Layout lines
    for _, fs in ipairs(toastLines) do fs:Hide(); fs:SetText("") end

    local yCursor = -(TOAST_HEADER_H + 4)
    for i, r in ipairs(readyList) do
        local fs = GetToastLine(i, f)
        fs:ClearAllPoints()
        fs:SetPoint("TOPLEFT",  f, "TOPLEFT",  TOAST_PADDING + 2, yCursor)
        fs:SetPoint("TOPRIGHT", f, "TOPRIGHT", -TOAST_PADDING,    yCursor)
        local color = CLASS_COLORS[r.charClass or ""] or "ffffffff"
        fs:SetText(string.format("|c%s%s|r  —  %s", color, r.charName, r.cdName))
        fs:Show()
        yCursor = yCursor - TOAST_LINE_H
    end

    -- Resize to fit
    local neededH = TOAST_HEADER_H + (n * TOAST_LINE_H) + TOAST_PADDING * 2 + 4
    f:SetSize(TOAST_WIDTH, neededH)

    -- Anchor and show
    f:ClearAllPoints()
    f:SetPoint("TOP", UIParent, "CENTER", 0, TOAST_OFFSET_Y)
    f:Show()

    -- Schedule auto-fade
    f._fadeTimer = C_Timer.NewTimer(TOAST_DURATION, function()
        f._fadeTimer = nil
        if f:IsShown() then
            f.fadeGroup:Play()
        end
    end)
end

------------------------------------------------------------
-- Cooldown scanner
-- Collects every character (own AND synced accounts) that has
-- a newly-ready CD, and raises a single aggregate toast.
------------------------------------------------------------

local function ScanCooldowns()
    AltTrackerDB = AltTrackerDB or {}
    AltTrackerConfig = AltTrackerConfig or {}

    if AltTrackerConfig.toastsEnabled == false then return end

    PruneShownSet()
    local shown = GetShownSet()
    local now   = time()

    local ready          = {}
    local newlyNotified  = {}

    for guid, char in pairs(AltTrackerDB) do
        if type(char) == "table" and char.name then
            for _, def in ipairs(CD_DEFS) do
                -- For records synced from another account, the known_ flag
                -- may be absent if the source never logged it.  We still
                -- trust the CD if the character has the profession AND a
                -- non-zero CD timestamp is recorded (the timestamp itself
                -- is proof the recipe was cast at some point).
                local hasProfSkill = CharHasProfession(char, def.profKey, def.minSkill)
                local knowsRecipe  = char["known_" .. def.key]
                local hasCDStamp   = char[def.key] and char[def.key] ~= 0
                local looksValid   = hasProfSkill and (knowsRecipe or hasCDStamp)

                if IsToastEnabled(def.profKey) and looksValid then
                    local expiry = char[def.key]
                    if expiry and expiry > 0 and expiry <= now then
                        local nKey = guid .. ":" .. def.key .. ":" .. expiry
                        if not shown[nKey] then
                            table.insert(ready, {
                                charName  = char.name,
                                charClass = char.class or "WARRIOR",
                                cdName    = def.name,
                                profKey   = def.profKey,
                            })
                            newlyNotified[nKey] = expiry
                        end
                    end
                end
            end
        end
    end

    if #ready > 0 then
        table.sort(ready, function(a, b)
            if a.charName ~= b.charName then return a.charName < b.charName end
            return a.cdName < b.cdName
        end)
        AltTracker.ShowAggregateToast(ready)
        for k, v in pairs(newlyNotified) do shown[k] = v end
    end
end

-- Expose for manual testing / debug
AltTracker.ScanCooldowns = ScanCooldowns

------------------------------------------------------------
-- Startup
--
-- We deliberately scan cooldowns ONCE per session, a short
-- while after login, and never again.  The idea: when you log
-- in, you want to know what's off cooldown right now so you
-- can go use it — but once you've seen (and dismissed) the
-- toast, poking you again 30 seconds later is noise, not a
-- feature.  If more cooldowns come off during the session,
-- you'll see them next time you log in.
--
-- The 15-second delay gives the AltTracker sync protocol a
-- chance to finish pulling fresh data from whitelisted
-- accounts before we build the toast, so cooldowns on alts
-- from your other account show up in the same single toast.
------------------------------------------------------------

local LOGIN_SCAN_DELAY = 15      -- seconds after PLAYER_LOGIN

local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("PLAYER_LOGIN")
initFrame:SetScript("OnEvent", function()
    C_Timer.After(LOGIN_SCAN_DELAY, function()
        PruneShownSet()
        ScanCooldowns()
    end)
end)
