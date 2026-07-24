-- RosterScene.lua — "Campsite" scene view for the AltTracker Roster plugin.
--
-- A WoW-Midnight-style character-select look: the top-N alts shown side by side as
-- framed portrait cards over a dark night backdrop, each with a name plate, click to
-- select (kept in sync with the sidebar list), a highlighted selection, and a hover
-- tooltip. Phase A uses the existing opaque 512x896 portraits as framed cards; there is
-- no transparent-cutout / compositing work here (that is a separate, later project).
--
-- This is a separate file on purpose: AltTrackerRoster.lua sits right at Lua 5.1's
-- 200-locals-per-function limit, so the scene lives in its own chunk. The main file
-- passes everything it needs through a small `api` table (see AltTracker.RosterScene.Build),
-- so this module does not depend on the main file's file-local helpers.

AltTracker = AltTracker or {}

local RosterScene = {}
AltTracker.RosterScene = RosterScene

-- ---------------------------------------------------------------------------
-- Module state
-- ---------------------------------------------------------------------------
local api = {}
local root
local hintText
local cards = {}
local lastCamp, lastSelected

local CARD_MAX_W   = 160
local CARD_INSET   = 4
local CARD_GAP     = 12
local CARD_TOP     = 12
local CARD_BOTTOM  = 12
local PLATE_H      = 22
local DEFAULT_SRC_W = 512
local DEFAULT_SRC_H = 896

-- ---------------------------------------------------------------------------
-- Small helpers (kept local to this chunk; the cover math mirrors
-- LayoutCenterRenderTexture in AltTrackerRoster.lua but is tiny and self-contained)
-- ---------------------------------------------------------------------------
local function AccentRGB()
    if AltTracker.GetAccentRGB then return AltTracker.GetAccentRGB() end
    return 0.9, 0.75, 0.35
end

local function ClassRGB(classToken)
    if AltTracker.GetClassRGB then return AltTracker.GetClassRGB(classToken) end
    return 0.8, 0.8, 0.8
end

-- Aspect-fill ("cover") texcoords: crop the overflowing axis, keep the image centered.
local function CoverTexCoord(fw, fh, sw, sh)
    fw, fh = math.max(1, fw), math.max(1, fh)
    sw, sh = math.max(1, sw), math.max(1, sh)
    local frameAspect = fw / fh
    local sourceAspect = sw / sh
    local uMin, uMax, vMin, vMax = 0, 1, 0, 1
    if sourceAspect > frameAspect then
        local pad = (1 - frameAspect / sourceAspect) * 0.5
        uMin, uMax = pad, 1 - pad
    elseif sourceAspect < frameAspect then
        local pad = (1 - sourceAspect / frameAspect) * 0.5
        vMin, vMax = pad, 1 - pad
    end
    return uMin, uMax, vMin, vMax
end

local function EnsureBorder(frame)
    if frame._border then return frame._border end
    local b = {
        top    = frame:CreateTexture(nil, "OVERLAY"),
        bottom = frame:CreateTexture(nil, "OVERLAY"),
        left   = frame:CreateTexture(nil, "OVERLAY"),
        right  = frame:CreateTexture(nil, "OVERLAY"),
    }
    frame._border = b
    return b
end

local function SetBorder(frame, thickness, r, g, bl, a)
    local b = EnsureBorder(frame)
    for _, tex in pairs(b) do tex:SetColorTexture(r, g, bl, a) end
    b.top:ClearAllPoints()
    b.top:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    b.top:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
    b.top:SetHeight(thickness)
    b.bottom:ClearAllPoints()
    b.bottom:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
    b.bottom:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
    b.bottom:SetHeight(thickness)
    b.left:ClearAllPoints()
    b.left:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    b.left:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
    b.left:SetWidth(thickness)
    b.right:ClearAllPoints()
    b.right:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
    b.right:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
    b.right:SetWidth(thickness)
end

-- Load a portrait texture (cached by path) and cover-fit it into the given host dims.
local function ApplyPortrait(tex, path, hostW, hostH, srcW, srcH)
    if type(path) ~= "string" or path == "" then return false end
    if tex._appliedPath ~= path then
        tex:SetTexture(nil)
        local ok = pcall(tex.SetTexture, tex, path)
        if not ok or not tex:GetTexture() then
            tex:SetTexture(nil)
            tex._appliedPath = nil
            return false
        end
        tex._appliedPath = path
    end
    local u1, u2, v1, v2 = CoverTexCoord(hostW, hostH, srcW or DEFAULT_SRC_W, srcH or DEFAULT_SRC_H)
    tex:SetTexCoord(u1, u2, v1, v2)
    return true
end

-- ---------------------------------------------------------------------------
-- Tooltip
-- ---------------------------------------------------------------------------
local function ShowCardTooltip(card)
    local char = card.char
    if not char then return end
    local classToken = (char.class or ""):upper()
    GameTooltip:SetOwner(card, "ANCHOR_RIGHT")
    GameTooltip:AddLine(char.name or "?", 1, 1, 1)
    local className = (api.classDisplay and api.classDisplay(classToken)) or classToken
    GameTooltip:AddLine(string.format("Level %d %s", char.level or 0, className or ""), 0.82, 0.82, 0.82)
    local race = api.raceDisplay and api.raceDisplay(char)
    if race and race ~= "" then GameTooltip:AddLine(race, 0.7, 0.7, 0.7) end
    if char.guild and char.guild ~= "" then
        GameTooltip:AddLine("<" .. char.guild .. ">", 0.55, 0.8, 0.55)
    end
    if char.ilvl and char.ilvl > 0 then
        GameTooltip:AddLine(string.format("iLvl %.1f", char.ilvl), 0.6, 0.72, 1.0)
    end
    GameTooltip:Show()
end

-- ---------------------------------------------------------------------------
-- Card pool
-- ---------------------------------------------------------------------------
local function EnsureCard(i)
    if cards[i] then return cards[i] end

    local card = CreateFrame("Button", nil, root, "BackdropTemplate")
    AltTracker.ApplyBGOnly(card, 0.05, 0.05, 0.065, 0.92)
    card._baseLevel = (root:GetFrameLevel() or 1) + 2
    card:SetFrameLevel(card._baseLevel)

    -- portrait fills the card above the name plate; cover-fit texcoords crop overflow,
    -- so no child clipping is required.
    card.portrait = card:CreateTexture(nil, "ARTWORK")
    card.portrait:SetPoint("TOPLEFT", card, "TOPLEFT", CARD_INSET, -CARD_INSET)
    card.portrait:SetPoint("BOTTOMRIGHT", card, "BOTTOMRIGHT", -CARD_INSET, PLATE_H)

    -- class-icon fallback for characters that have no rendered portrait
    card.classIcon = card:CreateTexture(nil, "ARTWORK")
    card.classIcon:SetSize(56, 56)
    card.classIcon:SetPoint("CENTER", card.portrait, "CENTER", 0, 0)
    card.classIcon:Hide()

    -- name plate along the bottom
    card.plate = card:CreateTexture(nil, "OVERLAY")
    card.plate:SetHeight(PLATE_H)
    card.plate:SetPoint("BOTTOMLEFT", card, "BOTTOMLEFT", 0, 0)
    card.plate:SetPoint("BOTTOMRIGHT", card, "BOTTOMRIGHT", 0, 0)
    card.plate:SetColorTexture(0.05, 0.05, 0.06, 0.9)

    card.name = card:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    card.name:SetPoint("LEFT", card.plate, "LEFT", 6, 0)
    card.name:SetPoint("RIGHT", card.plate, "RIGHT", -6, 0)
    card.name:SetJustifyH("CENTER")
    card.name:SetWordWrap(false)
    if card.name.SetMaxLines then card.name:SetMaxLines(1) end

    card:SetScript("OnClick", function(self)
        if self.char and api.onSelect then api.onSelect(self.char.guid) end
    end)
    card:SetScript("OnDoubleClick", function(self)
        if self.char and api.openDetails then api.openDetails(self.char.guid) end
    end)
    card:SetScript("OnEnter", ShowCardTooltip)
    card:SetScript("OnLeave", function() GameTooltip:Hide() end)

    cards[i] = card
    return card
end

local function BindCard(card, char, selected, cardW, cardH)
    card.char = char
    card:EnableMouse(true)

    local classToken = (char.class or ""):upper()
    local portraitW = cardW - CARD_INSET * 2
    local portraitH = cardH - CARD_INSET - PLATE_H

    local path, srcW, srcH = api.resolvePortrait and api.resolvePortrait(char)
    if path and ApplyPortrait(card.portrait, path, portraitW, portraitH, srcW, srcH) then
        card.portrait:Show()
        card.classIcon:Hide()
    else
        card.portrait:Hide()
        card.portrait._appliedPath = nil
        if api.classIconPath then
            card.classIcon:SetTexture(api.classIconPath(classToken))
            card.classIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        end
        card.classIcon:Show()
    end

    card.name:SetText(char.name or "?")

    if selected then
        local ar, ag, ab = AccentRGB()
        SetBorder(card, 2, ar, ag, ab, 1)
        card.plate:SetColorTexture(ar * 0.35, ag * 0.35, ab * 0.35, 0.95)
        card.name:SetTextColor(1, 1, 1)
        card:SetFrameLevel(card._baseLevel + 10)
    else
        SetBorder(card, 1, 0.22, 0.22, 0.26, 0.9)
        card.plate:SetColorTexture(0.05, 0.05, 0.06, 0.9)
        local r, g, b = ClassRGB(classToken)
        card.name:SetTextColor(r, g, b)
        card:SetFrameLevel(card._baseLevel)
    end
end

-- ---------------------------------------------------------------------------
-- Backdrop
-- ---------------------------------------------------------------------------
local function BuildBackdrop()
    -- night sky
    AltTracker.ApplyBGOnly(root, 0.04, 0.045, 0.06, 1)

    -- lighter "ground" band in the lower third to suggest a floor / campsite
    root.ground = root:CreateTexture(nil, "BACKGROUND")
    root.ground:SetColorTexture(0.08, 0.075, 0.065, 1)
    root.ground:SetPoint("BOTTOMLEFT", root, "BOTTOMLEFT", 0, 0)
    root.ground:SetPoint("BOTTOMRIGHT", root, "BOTTOMRIGHT", 0, 0)
    root.ground:SetPoint("TOP", root, "BOTTOM", 0, 150)

    root.horizon = root:CreateTexture(nil, "BACKGROUND")
    root.horizon:SetHeight(1)
    root.horizon:SetPoint("BOTTOMLEFT", root.ground, "TOPLEFT", 0, 0)
    root.horizon:SetPoint("BOTTOMRIGHT", root.ground, "TOPRIGHT", 0, 0)
    root.horizon:SetColorTexture(0.0, 0.0, 0.0, 0.4)
end

-- ---------------------------------------------------------------------------
-- Camp selection (pure — no frames/globals, so it is unit-testable)
--
-- Picks the characters that stand in the scene: filter out non-character keys and
-- (optionally) low-level alts, then take the strongest `maxN` by level, then iLvl,
-- then name. NOTE: this deliberately does NOT reuse the sidebar's SortCharacters,
-- which orders realm/account first — taking its first N would not be "top-N by level".
-- ---------------------------------------------------------------------------
function RosterScene.SelectCamp(store, hideLow, maxN)
    maxN = maxN or 6
    local chars = {}
    if type(store) == "table" then
        for _, char in next, store do
            if type(char) == "table" and char.name then
                if not hideLow or (char.level or 0) >= 58 then
                    chars[#chars + 1] = char
                end
            end
        end
    end
    table.sort(chars, function(a, b)
        local lA, lB = a.level or 0, b.level or 0
        if lA ~= lB then return lA > lB end
        local iA, iB = a.ilvl or 0, b.ilvl or 0
        if iA ~= iB then return iA > iB end
        return (a.name or "") < (b.name or "")
    end)
    for i = #chars, maxN + 1, -1 do chars[i] = nil end
    return chars
end

-- ---------------------------------------------------------------------------
-- Public API
-- ---------------------------------------------------------------------------
function RosterScene.Build(parent, callbacks)
    if callbacks then api = callbacks end
    if root then return end

    root = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    root:SetAllPoints(parent)
    root:Hide()
    BuildBackdrop()

    hintText = root:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    hintText:SetPoint("CENTER", root, "CENTER", 0, 0)
    hintText:SetTextColor(0.7, 0.7, 0.7)
    hintText:SetText("No characters to display.")
    hintText:Hide()

    root:SetScript("OnSizeChanged", function()
        if root:IsShown() then RosterScene.Render(lastCamp, lastSelected) end
    end)
end

function RosterScene.SetVisible(show)
    if not root then return end
    if show then
        root:Show()
    else
        root:Hide()
        GameTooltip:Hide()
    end
end

function RosterScene.Render(camp, selectedGuid)
    if not root then return end
    lastCamp, lastSelected = camp, selectedGuid

    local n = camp and #camp or 0
    if n == 0 then
        hintText:Show()
        for i = 1, #cards do
            cards[i].char = nil
            cards[i]:EnableMouse(false)
            cards[i]:Hide()
        end
        return
    end
    hintText:Hide()

    local rW = math.max(1, root:GetWidth())
    local rH = math.max(1, root:GetHeight())
    local cardW = math.min(CARD_MAX_W, (rW - CARD_GAP * (n + 1)) / n)
    cardW = math.max(1, cardW)
    local cardH = math.max(1, rH - CARD_TOP - CARD_BOTTOM)
    local totalW = cardW * n + CARD_GAP * (n - 1)
    local startX = math.max(CARD_GAP, (rW - totalW) * 0.5)

    for i = 1, n do
        local card = EnsureCard(i)
        local char = camp[i]
        card:ClearAllPoints()
        card:SetSize(cardW, cardH)
        card:SetPoint("TOPLEFT", root, "TOPLEFT", startX + (i - 1) * (cardW + CARD_GAP), -CARD_TOP)
        BindCard(card, char, char.guid == selectedGuid, cardW, cardH)
        card:Show()
    end

    for i = n + 1, #cards do
        cards[i].char = nil
        cards[i]:EnableMouse(false)
        cards[i]:Hide()
    end
end

function RosterScene.RepaintTheme()
    if not root or not root:IsShown() then return end
    RosterScene.Render(lastCamp, lastSelected)
end

-- Test seam (harmless in-game): expose pure internals for tests/test_scene.lua.
RosterScene._test = {
    CoverTexCoord = CoverTexCoord,
    SelectCamp    = RosterScene.SelectCamp,
}
