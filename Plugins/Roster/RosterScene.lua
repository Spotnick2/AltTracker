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
local animator
local lastCamp, lastSelected

local DEFAULT_SRC_W = 512
local DEFAULT_SRC_H = 896

-- Selectable scenic backdrops. Add entries here as TGAs are generated (raid-themed
-- camps, daylight camps, etc.). A nil `file` = the plain procedural floor. Each backdrop
-- is cover-cropped to the panel; `w`/`h` are the TGA's pixel dims (for the crop math).
local SCENE_BACKDROPS = {
    { id = "campsite", label = "Forest Camp",
      file = "Interface\\AddOns\\AltTracker\\Media\\Scene\\roster-campsite.tga", w = 1024, h = 682 },
    { id = "karazhan", label = "Karazhan",
      file = "Interface\\AddOns\\AltTracker\\Media\\Scene\\karazhan-campsite.tga", w = 1024, h = 682 },
    { id = "darkportal", label = "Dark Portal",
      file = "Interface\\AddOns\\AltTracker\\Media\\Scene\\dark-portal-campsite.tga", w = 1024, h = 682 },
    { id = "sunwell", label = "Sunwell Plateau",
      file = "Interface\\AddOns\\AltTracker\\Media\\Scene\\sunwell-plateau-campsite.tga", w = 1024, h = 682 },
    { id = "zangarmarsh", label = "Zangarmarsh",
      file = "Interface\\AddOns\\AltTracker\\Media\\Scene\\zangarmarsh-coilfang-campsite.tga", w = 1024, h = 682 },
    { id = "zulaman", label = "Zul'Aman",
      file = "Interface\\AddOns\\AltTracker\\Media\\Scene\\zulaman-campsite.tga", w = 1024, h = 682 },
    { id = "plain",    label = "Plain (dark)", file = nil },
}
local curBackdrop = 1     -- index into SCENE_BACKDROPS
local curBW, curBH = 1024, 682

-- cutout "hero carousel" layout: the selected character is centered and largest,
-- the rest flank it symmetrically, shrinking and dimming with distance (perspective).
local SCENE_NAME_BAND    = 26     -- reserved strip at the bottom for name labels
local SCENE_FLOOR_INSET  = 8      -- feet sit this far above the name band
local SCENE_HEIGHT_FRAC  = 0.80   -- center character height as a fraction of usable height
local CAROUSEL_SHRINK    = 0.74   -- each step out from center scales by this
local CAROUSEL_STEP_FRAC = 0.15   -- base horizontal step as a fraction of scene width
local CAROUSEL_MINSCALE  = 0.42   -- floor on the perspective shrink
local CAROUSEL_DIM_STEP  = 0.16   -- brightness lost per step out from center

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
        cards[i]._carousel = false
        cards[i]._c = nil
        cards[i]:EnableMouse(false)
        cards[i]:Hide()
    end
end

-- Move the carousel selection one character left/right (wrapping). Drives the animation.
local function StepSelection(delta)
    local camp = lastCamp
    if not camp or #camp < 2 then return end
    local idx = 1
    for i = 1, #camp do
        if camp[i].guid == lastSelected then idx = i; break end
    end
    idx = ((idx - 1 + delta) % #camp) + 1
    if api.onSelect then api.onSelect(camp[idx].guid) end
end

-- ── Cutout binding (Phase B, hero-carousel) ─────────────────────────────────
-- Apply a card's *current* (animated) geometry: position, size, and brightness.
local function ApplyCardGeom(card)
    local c = card._c
    if not c then return end
    local h = math.max(1, c.h)
    local w = math.max(1, h * (card.aspect or 0.57))
    card:SetSize(w, h)
    card:ClearAllPoints()
    card:SetPoint("BOTTOM", root, "BOTTOMLEFT", c.x, SCENE_NAME_BAND + SCENE_FLOOR_INSET)
    if card.portrait then card.portrait:SetVertexColor(c.b, c.b, c.b) end
end

-- Binds the cutout texture + name and sets the geometry TARGET (x / height / brightness)
-- the animator eases the card toward. Stacking `level` snaps immediately; a brand-new
-- card snaps straight to its target (no fly-in on first open).
local function BindCutoutTarget(card, char, isSelected, xCenter, targetH, brightness, level, minNameW)
    card.char = char
    card._carousel = true
    card:EnableMouse(true)

    local cutPath, cw, ch = api.resolveCutout(char)
    cw = tonumber(cw) or DEFAULT_SRC_W
    ch = tonumber(ch) or DEFAULT_SRC_H
    card.aspect = cw / ch

    card.plate:Hide()
    HideBorder(card)
    card.classIcon:Hide()

    card.portrait:ClearAllPoints()
    card.portrait:SetAllPoints(card)
    card.portrait:SetTexCoord(0, 1, 0, 1)
    LoadTexture(card.portrait, cutPath)
    card.portrait:Show()

    card:SetFrameLevel(level)

    -- name follows the card (anchored to its bottom edge, so it moves with the animation)
    card.name:ClearAllPoints()
    card.name:SetPoint("TOP", card, "BOTTOM", 0, -3)
    card.name:SetWidth(math.max(minNameW, targetH * card.aspect))
    card.name:SetText(char.name or "?")
    if isSelected then
        card.name:SetFontObject("GameFontNormalLarge")
        card.name:SetTextColor(1, 1, 1)
    else
        card.name:SetFontObject("GameFontHighlightSmall")
        local r, g, b = ClassRGB((char.class or ""):upper())
        card.name:SetTextColor(r * brightness, g * brightness, b * brightness)
    end
    card.name:Show()

    card._t = card._t or {}
    card._t.x, card._t.h, card._t.b = xCenter, targetH, brightness
    card._settled = false
    if not card._c then
        card._c = { x = xCenter, h = targetH, b = brightness }  -- new card: snap
    end
    ApplyCardGeom(card)
    card:Show()
end

-- ── Framed-card binding (Phase A fallback) ──────────────────────────────────
local function BindCard(card, char, selected, cardW, cardH, x)
    card.char = char
    card._carousel = false
    card._c = nil   -- drop carousel tween state so re-entering cutout mode snaps
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
-- Cover-crop the current backdrop image to the panel aspect (no stretch).
local function LayoutBackdrop(rW, rH)
    if root and root._hasBackdropImage and root.image then
        local u1, u2, v1, v2 = CoverTexCoord(rW, rH, curBW, curBH)
        root.image:SetTexCoord(u1, u2, v1, v2)
    end
end

-- Apply backdrop #idx: show its image (or the procedural floor when file is nil/missing),
-- update the picker label, and persist the choice.
local function ApplyBackdrop(idx)
    local n = #SCENE_BACKDROPS
    if n == 0 or not root then return end
    idx = ((idx - 1) % n) + 1
    curBackdrop = idx
    local bd = SCENE_BACKDROPS[idx]

    local haveImage = false
    if bd.file and root.image then
        local ok = pcall(root.image.SetTexture, root.image, bd.file)
        haveImage = (ok and root.image:GetTexture()) and true or false
    end
    root._hasBackdropImage = haveImage

    if haveImage then
        curBW, curBH = bd.w or 1024, bd.h or 682
        root.image:Show()
        if root.ground then root.ground:Hide() end
        if root.horizon then root.horizon:Hide() end
        LayoutBackdrop(root:GetWidth(), root:GetHeight())
    else
        if root.image then root.image:Hide() end
        if root.ground then root.ground:Show() end
        if root.horizon then root.horizon:Show() end
    end

    if root.picker then root.picker.label:SetText(bd.label or "") end
    if api.setBackdropId then api.setBackdropId(bd.id) end
end

local function CycleBackdrop(delta)
    ApplyBackdrop(curBackdrop + delta)
end

local function BuildBackdrop()
    AltTracker.ApplyBGOnly(root, 0.035, 0.04, 0.055, 1)   -- base night sky behind everything

    root.image = root:CreateTexture(nil, "BACKGROUND")
    root.image:SetAllPoints(root)
    root.image:Hide()

    -- procedural floor: shown for the "Plain" backdrop (or if an image fails to load)
    root.ground = root:CreateTexture(nil, "BACKGROUND")
    root.ground:SetColorTexture(0.075, 0.07, 0.062, 1)
    root.ground:SetPoint("BOTTOMLEFT", root, "BOTTOMLEFT", 0, 0)
    root.ground:SetPoint("BOTTOMRIGHT", root, "BOTTOMRIGHT", 0, 0)
    root.ground:SetPoint("TOP", root, "BOTTOM", 0, 160)
    root.ground:Hide()

    root.horizon = root:CreateTexture(nil, "BACKGROUND")
    root.horizon:SetHeight(1)
    root.horizon:SetPoint("BOTTOMLEFT", root.ground, "TOPLEFT", 0, 0)
    root.horizon:SetPoint("BOTTOMRIGHT", root.ground, "TOPRIGHT", 0, 0)
    root.horizon:SetColorTexture(0.0, 0.0, 0.0, 0.35)
    root.horizon:Hide()

    -- backdrop picker (◄ label ►) — only shown when there's more than one choice
    if #SCENE_BACKDROPS > 1 then
        local pick = CreateFrame("Frame", nil, root)
        pick:SetSize(240, 22)
        pick:SetPoint("TOP", root, "TOP", 0, -8)
        pick:SetFrameLevel((root:GetFrameLevel() or 1) + 40)

        local pbg = pick:CreateTexture(nil, "BACKGROUND")
        pbg:SetAllPoints(pick)
        pbg:SetColorTexture(0, 0, 0, 0.35)

        local prev = CreateFrame("Button", nil, pick)
        prev:SetSize(24, 22); prev:SetPoint("LEFT", pick, "LEFT", 2, 0)
        prev.t = prev:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        prev.t:SetAllPoints(prev); prev.t:SetText("<")
        prev:SetScript("OnClick", function() CycleBackdrop(-1) end)

        local nxt = CreateFrame("Button", nil, pick)
        nxt:SetSize(24, 22); nxt:SetPoint("RIGHT", pick, "RIGHT", -2, 0)
        nxt.t = nxt:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        nxt.t:SetAllPoints(nxt); nxt.t:SetText(">")
        nxt:SetScript("OnClick", function() CycleBackdrop(1) end)

        pick.label = pick:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        pick.label:SetPoint("CENTER", pick, "CENTER", 0, 0)
        root.picker = pick
    end

    -- restore the saved backdrop (by id), else default to the first
    local savedId = api.getBackdropId and api.getBackdropId()
    local startIdx = 1
    if savedId then
        for i, bd in ipairs(SCENE_BACKDROPS) do
            if bd.id == savedId then startIdx = i; break end
        end
    end
    ApplyBackdrop(startIdx)
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

    -- carousel navigation arrows (shown only in cutout mode with >1 character)
    local function MakeArrow(glyph, side, xo)
        local b = CreateFrame("Button", nil, root)
        b:SetSize(38, 66)
        b:SetPoint(side, root, side, xo, 16)
        b:SetFrameLevel((root:GetFrameLevel() or 1) + 45)
        b.t = b:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
        b.t:SetAllPoints(b)
        b.t:SetText(glyph)
        b.t:SetTextColor(1, 0.95, 0.7)
        b:SetAlpha(0.5)
        b:SetScript("OnEnter", function(s) s:SetAlpha(1) end)
        b:SetScript("OnLeave", function(s) s:SetAlpha(0.5) end)
        b:Hide()
        return b
    end
    root.arrowPrev = MakeArrow("<", "LEFT", 6)
    root.arrowNext = MakeArrow(">", "RIGHT", -6)
    root.arrowPrev:SetScript("OnClick", function() StepSelection(-1) end)
    root.arrowNext:SetScript("OnClick", function() StepSelection(1) end)

    -- carousel animator: eases each card's geometry toward its target each frame
    animator = CreateFrame("Frame")
    animator:SetScript("OnUpdate", function(_, dt)
        if not root or not root:IsShown() then return end
        local k = 1 - math.exp(-dt * 14)   -- frame-rate-independent easing (~0.2s)
        for i = 1, #cards do
            local card = cards[i]
            if card._carousel and card._c and card._t and card:IsShown() then
                local c, t = card._c, card._t
                if math.abs(t.x - c.x) < 0.3 and math.abs(t.h - c.h) < 0.3 and math.abs(t.b - c.b) < 0.004 then
                    if not card._settled then
                        c.x, c.h, c.b = t.x, t.h, t.b
                        ApplyCardGeom(card)
                        card._settled = true
                    end
                else
                    c.x = c.x + (t.x - c.x) * k
                    c.h = c.h + (t.h - c.h) * k
                    c.b = c.b + (t.b - c.b) * k
                    ApplyCardGeom(card)
                    card._settled = false
                end
            end
        end
    end)

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
        if root.arrowPrev then root.arrowPrev:Hide(); root.arrowNext:Hide() end
        ReleaseCards(1)
        return
    end
    hintText:Hide()

    local rW = math.max(1, root:GetWidth())
    local rH = math.max(1, root:GetHeight())
    LayoutBackdrop(rW, rH)

    if CampHasCutouts(camp) then
        local centerX  = rW / 2
        local usableH  = math.max(1, rH - SCENE_NAME_BAND - SCENE_FLOOR_INSET - 8)
        local baseH    = usableH * SCENE_HEIGHT_FRAC
        local step     = rW * CAROUSEL_STEP_FRAC
        local minNameW = rW / n

        -- which camp index is selected? (default to the middle so the scene stays centered)
        local sIdx = math.floor((n + 1) / 2)
        for i = 1, n do
            if camp[i].guid == selectedGuid then sIdx = i; break end
        end

        -- slot k per camp index: selected = 0, the rest fan out +1,-1,+2,-2,...
        local slotOf = {}
        slotOf[sIdx] = 0
        local seq, si = {}, 1
        for d = 1, n do seq[#seq + 1] = d; seq[#seq + 1] = -d end
        for i = 1, n do
            if i ~= sIdx then slotOf[i] = seq[si]; si = si + 1 end
        end

        for i = 1, n do
            local card = EnsureCard(i)
            local char = camp[i]
            local k    = slotOf[i]
            local ak   = math.abs(k)
            local scale = math.max(CAROUSEL_MINSCALE, CAROUSEL_SHRINK ^ ak)
            local off = 0
            for j = 0, ak - 1 do off = off + step * (CAROUSEL_SHRINK ^ j) end
            local x = (k >= 0) and (centerX + off) or (centerX - off)
            local brightness = math.max(0.5, 1 - CAROUSEL_DIM_STEP * ak)
            local level = card._baseLevel + (n - ak)
            BindCutoutTarget(card, char, char.guid == selectedGuid, x, baseH * scale, brightness, level, minNameW)
        end
        if root.arrowPrev then
            if n > 1 then root.arrowPrev:Show(); root.arrowNext:Show()
            else root.arrowPrev:Hide(); root.arrowNext:Hide() end
        end
    else
        -- Phase A framed-card fallback
        if root.arrowPrev then root.arrowPrev:Hide(); root.arrowNext:Hide() end
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
