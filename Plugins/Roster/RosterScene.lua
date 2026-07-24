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
-- camps, daylight camps, etc.). A nil `file` = the plain procedural floor.
-- The TGAs are power-of-two (1024x1024) with the real image in the top `h` rows and the
-- rest black-padded (WoW needs POT textures to reload reliably). `w`/`h` are the image
-- (content) pixel dims for the cover-crop; `texh` is the TGA's full height for the remap.
local SCENE_BACKDROPS = {
    { id = "campsite", label = "Forest Camp",
      file = "Interface\\AddOns\\AltTracker\\Media\\Scene\\scene-forest.tga", w = 1024, h = 682, texh = 1024 },
    { id = "karazhan", label = "Karazhan",
      file = "Interface\\AddOns\\AltTracker\\Media\\Scene\\scene-karazhan.tga", w = 1024, h = 682, texh = 1024 },
    { id = "darkportal", label = "Dark Portal",
      file = "Interface\\AddOns\\AltTracker\\Media\\Scene\\scene-darkportal.tga", w = 1024, h = 682, texh = 1024 },
    { id = "sunwell", label = "Sunwell Plateau",
      file = "Interface\\AddOns\\AltTracker\\Media\\Scene\\scene-sunwell.tga", w = 1024, h = 682, texh = 1024 },
    { id = "zangarmarsh", label = "Zangarmarsh",
      file = "Interface\\AddOns\\AltTracker\\Media\\Scene\\scene-zangarmarsh.tga", w = 1024, h = 682, texh = 1024 },
    { id = "zulaman", label = "Zul'Aman",
      file = "Interface\\AddOns\\AltTracker\\Media\\Scene\\scene-zulaman.tga", w = 1024, h = 682, texh = 1024 },
    { id = "blacktemple", label = "Black Temple",
      file = "Interface\\AddOns\\AltTracker\\Media\\Scene\\scene-blacktemple.tga", w = 1024, h = 682, texh = 1024 },
    { id = "shattrath", label = "Shattrath",
      file = "Interface\\AddOns\\AltTracker\\Media\\Scene\\scene-shattrath.tga", w = 1024, h = 682, texh = 1024 },
    { id = "plain",    label = "Plain (dark)", file = nil },
}
local curBackdrop = 1     -- index into SCENE_BACKDROPS
local curBW, curBH, curBTH = 1024, 682, 1024

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

    -- info-card text (no-render fallback): race+class, and level+iLvl
    card.sub = card:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    card.sub:SetJustifyH("CENTER"); card.sub:SetWordWrap(false)
    card.sub:Hide()
    card.info = card:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    card.info:SetJustifyH("CENTER"); card.info:SetWordWrap(false)
    card.info:Hide()

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
    card.sub:Hide()
    card.info:Hide()

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

-- ── Character info-card (no-cutout fallback) ────────────────────────────────
-- Shown when a character has no rendered cutout: a class-icon + name + race/class +
-- level/iLvl card (the List view's identity card, per slot), over the same backdrop.
local function BindCard(card, char, selected, cardW, cardH, x, y)
    card.char = char
    card._carousel = false
    card._c = nil   -- drop any carousel tween state
    card:EnableMouse(true)

    card:ClearAllPoints()
    card:SetSize(cardW, cardH)
    card:SetPoint("TOPLEFT", root, "TOPLEFT", x, y)
    card:SetFrameLevel(selected and (card._baseLevel + 10) or card._baseLevel)

    local classToken = (char.class or ""):upper()
    local r, g, b = ClassRGB(classToken)

    card.portrait:Hide()
    card.plate:Hide()

    -- class icon, upper area
    local iconSize = math.max(28, math.min(cardW * 0.44, cardH * 0.40))
    card.classIcon:ClearAllPoints()
    card.classIcon:SetSize(iconSize, iconSize)
    card.classIcon:SetPoint("TOP", card, "TOP", 0, -math.max(8, cardH * 0.10))
    if api.classIconPath then
        card.classIcon:SetTexture(api.classIconPath(classToken))
        card.classIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    end
    card.classIcon:Show()

    -- name
    card.name:ClearAllPoints()
    card.name:SetPoint("TOP", card.classIcon, "BOTTOM", 0, -6)
    card.name:SetPoint("LEFT", card, "LEFT", 4, 0)
    card.name:SetPoint("RIGHT", card, "RIGHT", -4, 0)
    card.name:SetFontObject("GameFontNormal")
    card.name:SetText(char.name or "?")
    card.name:Show()

    -- race + class
    local className = (api.classDisplay and api.classDisplay(classToken)) or (char.class or "")
    local race = (api.raceDisplay and api.raceDisplay(char)) or ""
    card.sub:ClearAllPoints()
    card.sub:SetPoint("TOP", card.name, "BOTTOM", 0, -3)
    card.sub:SetPoint("LEFT", card, "LEFT", 3, 0)
    card.sub:SetPoint("RIGHT", card, "RIGHT", -3, 0)
    card.sub:SetText((race ~= "" and (race .. " ") or "") .. (className or ""))
    card.sub:SetTextColor(0.76, 0.76, 0.80)
    card.sub:Show()

    -- level + iLvl, along the bottom
    card.info:ClearAllPoints()
    card.info:SetPoint("BOTTOM", card, "BOTTOM", 0, 7)
    card.info:SetPoint("LEFT", card, "LEFT", 3, 0)
    card.info:SetPoint("RIGHT", card, "RIGHT", -3, 0)
    local ilvlStr = (char.ilvl and char.ilvl > 0) and string.format("  |  iLvl %.1f", char.ilvl) or ""
    card.info:SetText(string.format("Level %d%s", char.level or 0, ilvlStr))
    card.info:SetTextColor(0.66, 0.71, 0.85)
    card.info:Show()

    if selected then
        local ar, ag, ab = AccentRGB()
        AltTracker.ApplyBGOnly(card, ar * 0.16, ag * 0.16, ab * 0.16, 0.90)
        SetBorder(card, 2, ar, ag, ab, 1); ShowBorder(card)
        card.name:SetTextColor(1, 1, 1)
    else
        AltTracker.ApplyBGOnly(card, 0.06, 0.06, 0.08, 0.82)
        SetBorder(card, 1, 0.24, 0.24, 0.28, 0.9); ShowBorder(card)
        card.name:SetTextColor(r, g, b)
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
        -- the image occupies only the top `curBH/curBTH` of the POT texture; remap v into it
        local vScale = (curBTH and curBTH > 0) and (curBH / curBTH) or 1
        root.image:SetTexCoord(u1, u2, v1 * vScale, v2 * vScale)
    end
end

-- (Re)load and place the current backdrop's texture. This is called from Render — i.e. AFTER
-- the UI is fully up — on purpose: loading the texture at Build/show time renders BLACK after a
-- /reload (works only on a cold client start). The character cutouts never have this problem
-- precisely because they (re)load their textures in Render. LoadTexture caches by path, so the
-- repeated Render calls are cheap; on /reload the cache is empty and it loads fresh here.
local backdropRetries = 0
local function ApplyBackdropTexture(rW, rH)
    if not root or not root.image then return end
    local bd = SCENE_BACKDROPS[curBackdrop]
    local ok = (bd and bd.file and LoadTexture(root.image, bd.file)) or false
    root._hasBackdropImage = ok
    if ok then
        backdropRetries = 0
        root.image:Show()
        if root.ground then root.ground:Hide() end
        if root.horizon then root.horizon:Hide() end
        LayoutBackdrop(rW, rH)
    else
        root.image:Hide()
        if root.ground then root.ground:Show() end
        if root.horizon then root.horizon:Show() end
        -- A real backdrop (bd.file set) can transiently fail to load right after
        -- login — the texture streamer isn't ready yet — and Render isn't
        -- guaranteed to run again on its own, so the dark floor would persist
        -- until the user cycles the picker. Retry on a short timer so it
        -- self-heals. Guarded so the "Plain" backdrop (no file) never retries,
        -- and it stops the moment a load succeeds or the scene is hidden.
        if bd and bd.file and backdropRetries < 12 then
            backdropRetries = backdropRetries + 1
            C_Timer.After(0.25, function()
                if root and root:IsShown() and not root._hasBackdropImage then
                    ApplyBackdropTexture(root:GetWidth(), root:GetHeight())
                end
            end)
        end
    end
end

-- Select backdrop #idx: set its dims/label and persist the choice. Does NOT load the texture —
-- that happens in Render (ApplyBackdropTexture), so it survives /reload.
local function SelectBackdrop(idx)
    local n = #SCENE_BACKDROPS
    if n == 0 then return end
    idx = ((idx - 1) % n) + 1
    curBackdrop = idx
    backdropRetries = 0   -- fresh retry budget for this selection
    local bd = SCENE_BACKDROPS[idx]
    curBW, curBH = bd.w or 1024, bd.h or 682
    curBTH = bd.texh or curBH
    if root and root.picker then root.picker.label:SetText(bd.label or "") end
    if api.setBackdropId then api.setBackdropId(bd.id) end
end

-- Switch to backdrop #idx and apply it immediately (picker cycles, while the scene is visible).
local function ApplyBackdrop(idx)
    SelectBackdrop(idx)
    if root then ApplyBackdropTexture(root:GetWidth(), root:GetHeight()) end
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

    -- restore the saved backdrop (by id), else default to the first. Only SELECT it here;
    -- the texture is loaded later in Render (loading it now would render black after /reload).
    local savedId = api.getBackdropId and api.getBackdropId()
    local startIdx = 1
    if savedId then
        for i, bd in ipairs(SCENE_BACKDROPS) do
            if bd.id == savedId then startIdx = i; break end
        end
    end
    SelectBackdrop(startIdx)
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
        -- The backdrop texture is (re)loaded in Render (which runs right after, via Refresh) —
        -- loading it here/at Build renders black after a /reload.
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

    local rW = math.max(1, root:GetWidth())
    local rH = math.max(1, root:GetHeight())
    -- (re)load + place the backdrop here (render time) so it survives /reload, like the cutouts
    ApplyBackdropTexture(rW, rH)

    local n = camp and #camp or 0
    if n == 0 then
        hintText:Show()
        if root.arrowPrev then root.arrowPrev:Hide(); root.arrowNext:Hide() end
        ReleaseCards(1)
        return
    end
    hintText:Hide()

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
        -- No cutouts (e.g. no Codex renders): a centered grid of character info-cards.
        if root.arrowPrev then root.arrowPrev:Hide(); root.arrowNext:Hide() end
        local gap  = 12
        local cols = (n <= 4) and n or math.ceil(n / 2)
        local rows = math.ceil(n / cols)
        local cardW = math.max(1, math.min(200, (rW - gap * (cols + 1)) / cols))
        local cardH = math.max(1, math.min(250, (rH - gap * (rows + 1)) / rows))
        local gridW = cardW * cols + gap * (cols - 1)
        local gridH = cardH * rows + gap * (rows - 1)
        local startX = (rW - gridW) * 0.5
        local startY = (rH - gridH) * 0.5
        for i = 1, n do
            local card = EnsureCard(i)
            local col  = (i - 1) % cols
            local row  = math.floor((i - 1) / cols)
            local x = startX + col * (cardW + gap)
            local y = -(startY + row * (cardH + gap))
            BindCard(card, camp[i], camp[i].guid == selectedGuid, cardW, cardH, x, y)
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
