-- RosterScene.lua — "Campsite" scene view for the AltTracker Roster plugin.
--
-- A WoW-Midnight-style character-select look: the top-N alts shown together over a dark
-- night backdrop, each with a name, click to select (synced with the sidebar list), a
-- highlighted selection, and a hover tooltip.
--
--   * Phase B (preferred): true transparent CUTOUTS (AltTrackerSceneManifest) placed on one
--     shared backdrop, scaled to a common height and standing on a shared ground line —
--     the real Midnight look.
--   * Phase A (fallback): if no cutout exists for a character, it is drawn as a framed
--     opaque portrait card (or a class-icon card if it has no render at all).
--
-- Separate file on purpose: AltTrackerRoster.lua sits right at Lua 5.1's 200-locals limit,
-- so the scene lives in its own chunk. The main file passes what it needs via an `api`
-- table (see AltTracker.RosterScene.Build).

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

local DEFAULT_SRC_W = 512
local DEFAULT_SRC_H = 896

-- cutout scene layout
local SCENE_NAME_BAND   = 26      -- reserved strip at the bottom for name labels
local SCENE_FLOOR_INSET = 8       -- feet sit this far above the name band
local SCENE_HEIGHT_FRAC = 0.94    -- character height as a fraction of the usable height
local SCENE_MAX_W_FRAC  = 1.12    -- cap a character's width at this fraction of its slot
local SCENE_DIM_UNSEL   = 0.60    -- non-selected cutouts are dimmed to this brightness

-- framed-card fallback layout (Phase A)
local CARD_MAX_W  = 160
local CARD_INSET  = 4
local CARD_GAP    = 12
local CARD_TOP    = 12
local CARD_BOTTOM = 12
local PLATE_H     = 22

-- ---------------------------------------------------------------------------
-- Small helpers
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
-- Used only by the framed-card fallback.
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

local function HideBorder(frame)
    if frame._border then
        for _, tex in pairs(frame._border) do tex:Hide() end
    end
end

local function ShowBorder(frame)
    if frame._border then
        for _, tex in pairs(frame._border) do tex:Show() end
    end
end

-- Load a texture (cached by path). Returns true on success.
local function LoadTexture(tex, path)
    if tex._appliedPath == path and path ~= nil then return true end
    tex:SetTexture(nil)
    if type(path) ~= "string" or path == "" then tex._appliedPath = nil; return false end
    local ok = pcall(tex.SetTexture, tex, path)
    if not ok or not tex:GetTexture() then
        tex:SetTexture(nil); tex._appliedPath = nil; return false
    end
    tex._appliedPath = path
    return true
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
-- Card pool (one Button per scene slot; reused by both cutout and card modes)
-- ---------------------------------------------------------------------------
local function EnsureCard(i)
    if cards[i] then return cards[i] end

    local card = CreateFrame("Button", nil, root, "BackdropTemplate")
    card._baseLevel = (root:GetFrameLevel() or 1) + 2
    card:SetFrameLevel(card._baseLevel)

    card.portrait = card:CreateTexture(nil, "ARTWORK")
    card.classIcon = card:CreateTexture(nil, "ARTWORK")
    card.classIcon:Hide()

    card.plate = card:CreateTexture(nil, "BORDER")
    card.plate:Hide()

    card.name = card:CreateFontString(nil, "OVERLAY", "GameFontNormal")
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

local function ReleaseCards(fromIndex)
    for i = fromIndex, #cards do
        cards[i].char = nil
        cards[i]:EnableMouse(false)
        cards[i]:Hide()
    end
end

-- ── Cutout binding (Phase B) ────────────────────────────────────────────────
-- Places a transparent cutout scaled to a common height, standing on the ground line.
local function BindCutout(card, char, selected, slotCenterX, slotW, usableH)
    card.char = char
    card:EnableMouse(true)

    local cutPath, cw, ch = api.resolveCutout(char)
    cw = tonumber(cw) or DEFAULT_SRC_W
    ch = tonumber(ch) or DEFAULT_SRC_H

    local targetH = usableH * SCENE_HEIGHT_FRAC
    local maxW = slotW * SCENE_MAX_W_FRAC
    local scale = math.min(targetH / ch, maxW / cw)
    local w = math.max(1, cw * scale)
    local h = math.max(1, ch * scale)

    card:ClearAllPoints()
    card:SetSize(w, h)
    card:SetPoint("BOTTOM", root, "BOTTOMLEFT", slotCenterX, SCENE_NAME_BAND + SCENE_FLOOR_INSET)

    card.plate:Hide()
    HideBorder(card)
    card.classIcon:Hide()

    card.portrait:ClearAllPoints()
    card.portrait:SetAllPoints(card)
    card.portrait:SetTexCoord(0, 1, 0, 1)
    LoadTexture(card.portrait, cutPath)
    card.portrait:Show()

    -- selection: selected is full-bright and on top; others dimmed
    if selected then
        card.portrait:SetVertexColor(1, 1, 1)
        card:SetFrameLevel(card._baseLevel + 20)
    else
        card.portrait:SetVertexColor(SCENE_DIM_UNSEL, SCENE_DIM_UNSEL, SCENE_DIM_UNSEL + 0.03)
        card:SetFrameLevel(card._baseLevel)
    end

    -- name label pinned to a shared row in the name band, centered under this slot
    card.name:ClearAllPoints()
    card.name:SetPoint("BOTTOM", root, "BOTTOMLEFT", slotCenterX, 5)
    card.name:SetWidth(slotW)
    card.name:SetText(char.name or "?")
    if selected then
        local ar, ag, ab = AccentRGB()
        card.name:SetTextColor(1, 1, 1)
        local _ = ar + ag + ab
    else
        local r, g, b = ClassRGB((char.class or ""):upper())
        card.name:SetTextColor(r * 0.9, g * 0.9, b * 0.9)
    end
    card.name:Show()

    card:Show()
end

-- ── Framed-card binding (Phase A fallback) ──────────────────────────────────
local function BindCard(card, char, selected, cardW, cardH, x)
    card.char = char
    card:EnableMouse(true)

    card:ClearAllPoints()
    card:SetSize(cardW, cardH)
    card:SetPoint("TOPLEFT", root, "TOPLEFT", x, -CARD_TOP)
    AltTracker.ApplyBGOnly(card, 0.05, 0.05, 0.065, 0.92)

    local classToken = (char.class or ""):upper()
    local portraitW = cardW - CARD_INSET * 2
    local portraitH = cardH - CARD_INSET - PLATE_H

    card.portrait:ClearAllPoints()
    card.portrait:SetPoint("TOPLEFT", card, "TOPLEFT", CARD_INSET, -CARD_INSET)
    card.portrait:SetPoint("BOTTOMRIGHT", card, "BOTTOMRIGHT", -CARD_INSET, PLATE_H)
    card.portrait:SetVertexColor(1, 1, 1)

    local path, srcW, srcH = api.resolvePortrait and api.resolvePortrait(char)
    if path and LoadTexture(card.portrait, path) then
        local u1, u2, v1, v2 = CoverTexCoord(portraitW, portraitH, tonumber(srcW) or DEFAULT_SRC_W, tonumber(srcH) or DEFAULT_SRC_H)
        card.portrait:SetTexCoord(u1, u2, v1, v2)
        card.portrait:Show()
        card.classIcon:Hide()
    else
        card.portrait:Hide()
        if api.classIconPath then
            card.classIcon:ClearAllPoints()
            card.classIcon:SetSize(56, 56)
            card.classIcon:SetPoint("CENTER", card, "CENTER", 0, PLATE_H / 2)
            card.classIcon:SetTexture(api.classIconPath(classToken))
            card.classIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        end
        card.classIcon:Show()
    end

    card.plate:ClearAllPoints()
    card.plate:SetHeight(PLATE_H)
    card.plate:SetPoint("BOTTOMLEFT", card, "BOTTOMLEFT", 0, 0)
    card.plate:SetPoint("BOTTOMRIGHT", card, "BOTTOMRIGHT", 0, 0)
    card.plate:Show()

    card.name:ClearAllPoints()
    card.name:SetPoint("LEFT", card.plate, "LEFT", 6, 0)
    card.name:SetPoint("RIGHT", card.plate, "RIGHT", -6, 0)
    card.name:SetText(char.name or "?")
    card.name:Show()

    if selected then
        local ar, ag, ab = AccentRGB()
        SetBorder(card, 2, ar, ag, ab, 1); ShowBorder(card)
        card.plate:SetColorTexture(ar * 0.35, ag * 0.35, ab * 0.35, 0.95)
        card.name:SetTextColor(1, 1, 1)
        card:SetFrameLevel(card._baseLevel + 10)
    else
        SetBorder(card, 1, 0.22, 0.22, 0.26, 0.9); ShowBorder(card)
        card.plate:SetColorTexture(0.05, 0.05, 0.06, 0.9)
        local r, g, b = ClassRGB(classToken)
        card.name:SetTextColor(r, g, b)
        card:SetFrameLevel(card._baseLevel)
    end

    card:Show()
end

-- ---------------------------------------------------------------------------
-- Backdrop
-- ---------------------------------------------------------------------------
local function BuildBackdrop()
    AltTracker.ApplyBGOnly(root, 0.035, 0.04, 0.055, 1)   -- night sky

    root.ground = root:CreateTexture(nil, "BACKGROUND")
    root.ground:SetColorTexture(0.075, 0.07, 0.062, 1)     -- warmer campsite floor
    root.ground:SetPoint("BOTTOMLEFT", root, "BOTTOMLEFT", 0, 0)
    root.ground:SetPoint("BOTTOMRIGHT", root, "BOTTOMRIGHT", 0, 0)
    root.ground:SetPoint("TOP", root, "BOTTOM", 0, 160)

    root.horizon = root:CreateTexture(nil, "BACKGROUND")
    root.horizon:SetHeight(1)
    root.horizon:SetPoint("BOTTOMLEFT", root.ground, "TOPLEFT", 0, 0)
    root.horizon:SetPoint("BOTTOMRIGHT", root.ground, "TOPRIGHT", 0, 0)
    root.horizon:SetColorTexture(0.0, 0.0, 0.0, 0.35)
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

-- Does the whole camp have cutouts? (all-or-nothing keeps the scene visually consistent;
-- a single missing cutout falls the whole scene back to framed cards.)
local function CampHasCutouts(camp)
    if not api.resolveCutout then return false end
    for i = 1, #camp do
        local p = api.resolveCutout(camp[i])
        if not p then return false end
    end
    return #camp > 0
end

function RosterScene.Render(camp, selectedGuid)
    if not root then return end
    lastCamp, lastSelected = camp, selectedGuid

    local n = camp and #camp or 0
    if n == 0 then
        hintText:Show()
        ReleaseCards(1)
        return
    end
    hintText:Hide()

    local rW = math.max(1, root:GetWidth())
    local rH = math.max(1, root:GetHeight())

    if CampHasCutouts(camp) then
        local slotW = rW / n
        local usableH = math.max(1, rH - SCENE_NAME_BAND - SCENE_FLOOR_INSET - 8)
        for i = 1, n do
            local card = EnsureCard(i)
            local char = camp[i]
            BindCutout(card, char, char.guid == selectedGuid, slotW * (i - 0.5), slotW, usableH)
        end
    else
        -- Phase A framed-card fallback
        local cardW = math.max(1, math.min(CARD_MAX_W, (rW - CARD_GAP * (n + 1)) / n))
        local cardH = math.max(1, rH - CARD_TOP - CARD_BOTTOM)
        local totalW = cardW * n + CARD_GAP * (n - 1)
        local startX = math.max(CARD_GAP, (rW - totalW) * 0.5)
        for i = 1, n do
            local card = EnsureCard(i)
            local char = camp[i]
            BindCard(card, char, char.guid == selectedGuid, cardW, cardH, startX + (i - 1) * (cardW + CARD_GAP))
        end
    end

    ReleaseCards(n + 1)
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
