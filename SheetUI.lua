AltTracker = AltTracker or {}

------------------------------------------------------------
-- Layout constants
-- Tuned for ElvUI-style density: compact rows, tight header,
-- no wasted vertical space.
------------------------------------------------------------

local ROW_HEIGHT    = 22
local HEADER_HEIGHT = 28     -- compact; gear/skills/rep icon sections override to 32
local SIDEBAR_WIDTH = 190
local FRAME_W       = 1150   -- default; sections override via preferW
local FRAME_H       = 460    -- default; sections override via preferH
local currentHeaderHeight = HEADER_HEIGHT

-- Title bar occupies the top of the frame; everything sits below it.
local TITLE_H       = 30
-- Column header and body start below the title bar.
local HEADER_TOP_Y  = TITLE_H + 4    -- = 34 (4px gap between title bar and column header)

-- BODY_TOP_Y depends on the *current* header height, which changes per
-- section (compact 28 for text-heavy sections, 32 for icon-heavy ones).
-- Always call this; never cache the value at file load time.
local function BodyTopY()
    return HEADER_TOP_Y + currentHeaderHeight + 1
end

-- Public layout contract — plugins read these to align their content with the
-- main frame. Single source of truth for the global header height, sidebar
-- width, and row metrics. Plugins MUST anchor their panels at TITLE_H below
-- the main frame top, not at 0, or they'll overlap the AltTracker title bar.
AltTracker.LAYOUT = AltTracker.LAYOUT or {}
AltTracker.LAYOUT.TITLE_H        = TITLE_H
AltTracker.LAYOUT.SIDEBAR_WIDTH  = SIDEBAR_WIDTH
AltTracker.LAYOUT.HEADER_HEIGHT  = HEADER_HEIGHT
AltTracker.LAYOUT.ROW_HEIGHT     = ROW_HEIGHT
AltTracker.LAYOUT.FOOTER_HEIGHT  = 22

------------------------------------------------------------
-- Section definitions
-- Each section lists exactly which column fields to show
-- (excluding the frozen Name column which is always shown).
------------------------------------------------------------

-- Central icon path — set after AltTracker.MEDIA_PATH is defined in Theme.lua
local function IC(name)
    return (AltTracker.MEDIA_PATH or "Interface\\AddOns\\AltTracker\\Media\\")
        .. "Icons\\" .. name .. ".tga"
end

local SECTIONS = {
    {
        id    = "summary",
        label = "Account Summary",
        icon  = IC("account-summary"),
        -- Width = sidebar(190) + frozen(156) + scrollable cols(619) + scrollbar(20) = 985
        preferW = 985,
        preferH = 400,
        fields = {
            "class","spec","race","level","ilvl",
            "guild","restPercent","money","lastUpdate",
        },
    },
    {
        id    = "gear",
        label = "Gear Progression",
        icon  = IC("gear-progression"),
        headerHeight = 32,
        -- Width = sidebar(190) + frozen(156) + identity(380) + 17 slots×38(646) + scrollbar(20) = 1392
        -- Capped at 1350 with h-scroll for the last slot or two
        preferW = 1350,
        preferH = 420,
        fields = {
            "class","spec","race","level","ilvl","bisCount",
            "gear_head","gear_neck","gear_shoulder","gear_back","gear_chest",
            "gear_wrist","gear_hands","gear_waist","gear_legs","gear_feet",
            "gear_ring1","gear_ring2","gear_trinket1","gear_trinket2",
            "gear_mainhand","gear_offhand","gear_ranged",
        },
    },
    {
        id    = "skills",
        label = "Skills",
        icon  = IC("skills"),
        headerHeight = 32,
        -- Width = sidebar(190) + frozen(156) + identity(119) + 14 profs×44(616) + scrollbar(20) = 1101
        preferW = 1111,
        preferH = 410,
        fields = {
            "class","spec","race","level",
            "prof_Alchemy","prof_Blacksmithing","prof_Enchanting","prof_Engineering",
            "prof_Jewelcrafting","prof_Leatherworking","prof_Tailoring",
            "prof_Herbalism","prof_Mining","prof_Skinning",
            "cooking","fishing","firstAid","riding",
        },
    },
    {
        id    = "rep",
        label = "Reputations",
        icon  = IC("reputations"),
        headerHeight = 32,
        -- Width = sidebar(190) + frozen(156) + identity(119) + 18 rep×28(504) + scrollbar(20) = 989
        preferW = 999,
        preferH = 410,
        fields = {
            "class","spec","race","level",
            "aldor","scryer","shatar","lowercity",
            "cenarion","consortium","keepers","violeteye","sporeggar",
            "honorhold","thrallmar","kurenai","maghar",
            "ogrila","skyguard","netherwing","ashtongue","scaleofsands","shatteredsun",
        },
    },
}

-- Build a lookup: field → column def, used when building section col lists
local function BuildFieldLookup()
    local t = {}
    for _, col in ipairs(AltTracker.Columns) do
        t[col.field] = col
    end
    return t
end

------------------------------------------------------------
-- State
------------------------------------------------------------

local frame
local sidebarBtns    = {}
local activeSection  = SECTIONS[1]
local scrollableCols = {}   -- columns for the current section

local headerButtons  = {}
local frozenHeader
local frozenScroll
local frozenBodyContent
local frozenRows = {}
local headerScroll
local headerContent
local bodyScroll
local bodyContent
local hScrollBar
local totalsBar
local rows = {}

-- Row pools keyed by section id so we reuse without SetParent(nil)
local rowPools         = {}   -- rowPools[sectionId] = { rows={}, frozenRows={} }
local function GetPool(sectionId)
    if not rowPools[sectionId] then
        rowPools[sectionId] = { rows={}, frozenRows={} }
    end
    return rowPools[sectionId]
end

local displayList = {}
local sortColumn  = "level"
local sortAsc     = false
local hideLow     = true  -- runtime value; set from config in CreateFrameIfNeeded()
local collapsed   = {}

local totalChars = 0
local totalLevel = 0
local totalGold  = 0

local FROZEN_WIDTH
local NAME_COL_WIDTH

local function ComputeFrozenWidth()
    NAME_COL_WIDTH = AltTracker.Columns[1].width
    FROZEN_WIDTH   = 10 + NAME_COL_WIDTH + 6
end

------------------------------------------------------------
-- Helpers
------------------------------------------------------------

local function StackChars(text)
    local t = {}
    for i = 1, #text do t[i] = text:sub(i,i) end
    return table.concat(t, "\n")
end

local function GetCharacterStore()
    if type(AltTrackerDB)~="table" then return {} end
    if type(AltTrackerDB.characters)=="table" then return AltTrackerDB.characters end
    return AltTrackerDB
end

local function GetScrollableWidth()
    local padding=6; local total=10
    for _, col in ipairs(scrollableCols) do total=total+col.width+padding end
    return total
end

------------------------------------------------------------
-- Build scrollable column list for a section
------------------------------------------------------------

local function BuildScrollableColsForSection(section)
    wipe(scrollableCols)
    local lookup = BuildFieldLookup()
    for _, field in ipairs(section.fields) do
        -- aldor/scryer is a special combined column
        if field == "aldor" then
            -- find the repCombined column
            for _, col in ipairs(AltTracker.Columns) do
                if col.type == "repCombined" and col.field == "aldor" then
                    scrollableCols[#scrollableCols+1] = col
                    break
                end
            end
        elseif lookup[field] then
            scrollableCols[#scrollableCols+1] = lookup[field]
        end
    end
end

------------------------------------------------------------
-- Display list
------------------------------------------------------------

local function BuildDisplayList()
    wipe(displayList)
    totalChars=0; totalLevel=0; totalGold=0
    local store = GetCharacterStore()

    -- Totals reflect EVERY character in the DB, not just the filtered view.
    -- Bank alts below 58 still hold gold, and users expect the total gold
    -- number to match other addons (ElvUI, etc.) that account for them.
    for _, char in next, store do
        if type(char)=="table" and char.name then
            totalLevel = totalLevel + (char.level or 0)
            totalGold  = totalGold  + (char.money or 0)
            totalChars = totalChars + 1
        end
    end

    local allChars = {}
    for _, char in next, store do
        if type(char)=="table" and char.name then
            if not hideLow or (char.level or 0)>=58 then
                table.insert(allChars, char)
            end
        end
    end
    table.sort(allChars, function(a,b)
        local v1, v2
        -- Special-case the "level" sort: use a fractional effective level
        -- so that 61.78 sorts above 61.50, above 61.30 — matching what
        -- users see in the tooltip progress indicator.
        if sortColumn == "level" then
            v1 = (a.level or 0) + ((a.xpPercent or 0) / 100)
            v2 = (b.level or 0) + ((b.xpPercent or 0) / 100)
        else
            v1 = a[sortColumn]; if v1==nil then v1="" end
            v2 = b[sortColumn]; if v2==nil then v2="" end
        end
        if v1==v2 then
            local i1=a.ilvl or 0; local i2=b.ilvl or 0
            if i1~=i2 then return i1>i2 end
            return (a.name or "")<(b.name or "")
        end
        if type(v1)~=type(v2) then v1=tostring(v1); v2=tostring(v2) end
        if sortAsc then return v1<v2 else return v1>v2 end
    end)
    local realmOrder, realmChars = {}, {}
    for _, char in ipairs(allChars) do
        local realm = char.realm or "Unknown"
        if not realmChars[realm] then realmChars[realm]={}; table.insert(realmOrder,realm) end
        table.insert(realmChars[realm], char)
    end
    for _, realm in ipairs(realmOrder) do
        local chars=realmChars[realm]; local sumLvl=0; local sumGold=0
        for _, c in ipairs(chars) do
            sumLvl=sumLvl+(c.level or 0); sumGold=sumGold+(c.money or 0)
        end
        table.insert(displayList,{kind="group",realm=realm,count=#chars,
            sumLevel=sumLvl,sumGold=sumGold,collapsed=collapsed[realm]})
        if not collapsed[realm] then
            for _, char in ipairs(chars) do
                table.insert(displayList,{kind="char",data=char})
            end
        end
    end
end

------------------------------------------------------------
-- Row pool management (no SetParent — safe)
------------------------------------------------------------

local function CountVisibleRows()
    return math.max(1, math.floor(bodyScroll:GetHeight()/ROW_HEIGHT)+2)
end

local function EnsureRows(needed)
    local pool = GetPool(activeSection.id)
    -- Scrollable rows
    if #pool.rows < needed then
        for i=#pool.rows+1, needed do
            local row = AltTracker.CreateRow(bodyContent, ROW_HEIGHT, scrollableCols)
            pool.rows[i]=row
            row:SetPoint("TOPLEFT",bodyContent,"TOPLEFT",0,-((i-1)*ROW_HEIGHT))
            row:SetPoint("RIGHT",bodyContent,"RIGHT",0,0)
        end
    end
    -- Frozen rows
    if #pool.frozenRows < needed then
        for i=#pool.frozenRows+1, needed do
            local frow = AltTracker.CreateFrozenRow(frozenBodyContent, ROW_HEIGHT, NAME_COL_WIDTH)
            pool.frozenRows[i]=frow
            frow:SetPoint("TOPLEFT",frozenBodyContent,"TOPLEFT",0,-((i-1)*ROW_HEIGHT))
            frow:SetWidth(FROZEN_WIDTH)
        end
    end
    rows      = pool.rows
    frozenRows= pool.frozenRows
end

local function HideAllRows()
    -- Hide rows from ALL pools so only active section is visible
    for _, pool in pairs(rowPools) do
        for _, row   in ipairs(pool.rows)       do row:Hide()  end
        for _, frow  in ipairs(pool.frozenRows) do frow:Hide() end
    end
end

local function UpdateRows()
    HideAllRows()
    local needed=CountVisibleRows()
    EnsureRows(needed)
    local offset=bodyScroll:GetVerticalScroll()
    local firstIndex=math.floor(offset/ROW_HEIGHT)+1
    for i=1, needed do
        local item=displayList[firstIndex+i-1]
        local row=rows[i]; local frow=frozenRows[i]
        if not row or not frow then break end
        if item then
            if item.kind=="group" then
                AltTracker.RenderGroupRow(row,item)
                AltTracker.RenderFrozenGroupRow(frow,item)
            else
                AltTracker.RenderRow(row,item.data,firstIndex+i-1,scrollableCols)
                AltTracker.RenderFrozenCharRow(frow,item.data,firstIndex+i-1)
            end
        else
            AltTracker.HideRow(row)
            AltTracker.HideFrozenRow(frow)
        end
    end
end

------------------------------------------------------------
-- Scroll sizing
------------------------------------------------------------

local GOLD_ICON_SM = "|TInterface\\MoneyFrame\\UI-GoldIcon:13:13:2:0|t"

local function UpdateTotalsBar()
    if not totalsBar then return end
    local ar, ag, ab = AltTracker.GetAccentRGB()
    local accentHex = string.format("|cff%02x%02x%02x", ar*255, ag*255, ab*255)

    -- Rep section: show standing legend in the totals bar instead of char counts
    if activeSection and activeSection.id == "rep" then
        local legend = "|cff00ffffE|r Exalted  "
            .. "|cff00ffccR|r Revered  "
            .. "|cff00ff00H|r Honored  "
            .. "|cff66ff66F|r Friendly  "
            .. "|cffffffffN|r Neutral  "
            .. "|cffff6600U|r Unfriendly  "
            .. "|cffcc0000X|r Hated  "
            .. "|cffaaaaaa- Unknown|r"
        totalsBar.left:SetText(legend)
        if totalsBar.mid then totalsBar.mid:SetText("") end
        totalsBar.right:SetText(
            accentHex .. totalChars .. "|r |cffaaaaaa chars|r")
        return
    end

    -- Compute iLvl average across visible characters
    local totalIlvl, ilvlCount = 0, 0
    local store = GetCharacterStore()
    for _, char in next, store do
        if type(char)=="table" and char.name and (not hideLow or (char.level or 0)>=58) then
            if char.ilvl and char.ilvl > 0 then
                totalIlvl = totalIlvl + char.ilvl
                ilvlCount  = ilvlCount  + 1
            end
        end
    end
    local avgIlvlStr = ""
    if ilvlCount > 0 then
        avgIlvlStr = string.format("|cffaaaaaa%.1f|r avg iLvl", totalIlvl / ilvlCount)
    end

    totalsBar.left:SetText(
        accentHex .. totalChars .. "|r |cffaaaaaa chars  " ..
        accentHex .. totalLevel .. "|r |cffaaaaaa total levels|r")
    if totalsBar.mid then totalsBar.mid:SetText(avgIlvlStr) end
    totalsBar.right:SetText(
        "|cffaaaaaa" .. math.floor(totalGold/10000) .. GOLD_ICON_SM .. " total gold|r")
end

------------------------------------------------------------
-- Layout-aware scrollbar visibility.
--
-- Single source of truth: this function decides BOTH scrollbar visibility
-- and scroll-frame anchors. Frame sizing (ComputeContentSize) reads the
-- same flags via _layoutNeedsHScroll / _layoutNeedsVScroll on the frame.
--
-- Rules (from the spec):
--   - No vertical scrollbar gutter unless content exceeds visible area.
--   - No horizontal scrollbar unless columns exceed visible width.
--   - When a scrollbar is visible, reserve only enough space for it.
------------------------------------------------------------

local SCROLLBAR_GUTTER_W = 18  -- width of vertical scrollbar + a 2px breathing edge
-- The OptionsSliderTemplate slider thumb visually extends ~6px above its
-- nominal frame bounds. A 14px gutter wasn't enough; the thumb peeked into
-- the body area as a dark square (most visible on h-scrollable sections
-- like Gear Progression). 20 puts the thumb cleanly below the body row.
local HSCROLL_GUTTER_H   = 20

local function ApplyContentAnchors(needsH, needsV)
    -- Single source of truth for content-area anchors. Header, body, and
    -- frozen scrolls all use the SAME right offset, so the column header
    -- never extends beyond the body grid (and vice versa).
    --
    --   needsH: leave room at the bottom for the horizontal scrollbar
    --   needsV: leave room on the right for the vertical scrollbar
    local footerTop  = (AltTracker.LAYOUT.FOOTER_HEIGHT or 22) + 1   -- +1 for the totals border line
    local bodyBot    = footerTop + (needsH and HSCROLL_GUTTER_H or 0)
    local rightInset = needsV and SCROLLBAR_GUTTER_W or 2

    bodyScroll:ClearAllPoints()
    bodyScroll:SetPoint("TOPLEFT",     frame, "TOPLEFT",     SIDEBAR_WIDTH + FROZEN_WIDTH, -BodyTopY())
    bodyScroll:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -rightInset, bodyBot)

    frozenScroll:ClearAllPoints()
    frozenScroll:SetPoint("TOPLEFT",    frame, "TOPLEFT",    SIDEBAR_WIDTH, -BodyTopY())
    frozenScroll:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", SIDEBAR_WIDTH, bodyBot)
    frozenScroll:SetWidth(FROZEN_WIDTH)

    -- Header right edge MUST equal body right edge — same rightInset.
    -- Without this, the last column header is clipped (no v-scroll) or
    -- overflows past the v-scrollbar (with v-scroll).
    if headerScroll then
        headerScroll:ClearAllPoints()
        headerScroll:SetPoint("TOPLEFT",  frame, "TOPLEFT",  SIDEBAR_WIDTH + FROZEN_WIDTH, -HEADER_TOP_Y)
        headerScroll:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -rightInset, -HEADER_TOP_Y)
        headerScroll:SetHeight(currentHeaderHeight)
    end

    -- Horizontal scrollbar uses the same right inset as the body so it
    -- never extends past the body's visible area (which would let its
    -- backdrop track peek out from under the bodyScroll's clip region).
    -- Y position is footerTop+1 (just above totals bar's top border line)
    -- so the slider's thumb texture, which extends above nominal bounds,
    -- still sits inside HSCROLL_GUTTER_H without intruding on body rows.
    if hScrollBar then
        hScrollBar:ClearAllPoints()
        hScrollBar:SetPoint("BOTTOMLEFT",  frame, "BOTTOMLEFT",  SIDEBAR_WIDTH + 4, footerTop + 1)
        hScrollBar:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -rightInset,       footerTop + 1)
    end
end

local function UpdateScroll()
    local totalH   = #displayList * ROW_HEIGHT
    local contentW = GetScrollableWidth()

    -- Two-pass layout. Pass 1 with no scrollbars assumed; if either flag
    -- comes back true, re-anchor with the correct gutters and re-measure.
    -- Two passes is enough: a v-scrollbar appearing makes the viewport
    -- narrower, which can flip h-scroll on, but at most one flip per axis.
    local function measure(needsH, needsV)
        ApplyContentAnchors(needsH, needsV)
        return contentW > bodyScroll:GetWidth(), totalH > bodyScroll:GetHeight()
    end

    local needsH, needsV = measure(false, false)
    if needsH or needsV then
        local h2, v2 = measure(needsH, needsV)
        if h2 ~= needsH or v2 ~= needsV then
            -- Pass 3 only when the second pass changed the answer (rare:
            -- v-scrollbar appearing made h-scroll suddenly necessary, etc.)
            needsH, needsV = h2, v2
            ApplyContentAnchors(needsH, needsV)
        end
    end

    local maxH = math.max(0, contentW - bodyScroll:GetWidth())

    -- Vertical scrollbar (auto-created by UIPanelScrollFrameTemplate)
    local vbar = _G["AltTrackerBodyScrollScrollBar"]
    if vbar then
        if needsV then vbar:Show() else vbar:Hide() end
    end

    -- Sync content sizes
    bodyContent:SetSize(contentW,            math.max(totalH, bodyScroll:GetHeight()))
    frozenBodyContent:SetSize(FROZEN_WIDTH,  math.max(totalH, frozenScroll:GetHeight()))
    headerContent:SetSize(contentW,          currentHeaderHeight)

    -- Horizontal scrollbar visibility
    hScrollBar:SetMinMaxValues(0, maxH)
    hScrollBar:SetValue(0)
    if needsH then hScrollBar:Show() else hScrollBar:Hide() end

    -- Reset scroll positions
    headerScroll:SetHorizontalScroll(0)
    bodyScroll:SetHorizontalScroll(0)
    bodyScroll:SetVerticalScroll(0)
    frozenScroll:SetVerticalScroll(0)

    -- Publish flags so ComputeContentSize can size the frame to match
    if frame then
        frame._layoutNeedsHScroll = needsH
        frame._layoutNeedsVScroll = needsV
    end
end

------------------------------------------------------------
-- Sort arrows
------------------------------------------------------------

local function UpdateSortArrows()
    local ar, ag, ab = AltTracker.GetAccentRGB()
    for _, btn in ipairs(headerButtons) do
        if btn.field==sortColumn then
            if btn.arrow then btn.arrow:Show()
                btn.arrow:SetTexCoord(0,1, sortAsc and 0 or 1, sortAsc and 1 or 0)
            end
            if btn.iconTex then btn.iconTex:SetVertexColor(ar, ag, ab)
            else btn.label:SetTextColor(ar, ag, ab) end
        else
            if btn.arrow then btn.arrow:Hide() end
            if btn.iconTex then btn.iconTex:SetVertexColor(1,1,1)
            else btn.label:SetTextColor(unpack(AltTracker.C.TEXT_NORM)) end
        end
    end
end

------------------------------------------------------------
-- Header construction
------------------------------------------------------------

local COL_TOOLTIPS = {
    level="Level", ilvl="Item Level", bisCount="Best-in-Slot items equipped",
    gear_head="Head", gear_neck="Neck", gear_shoulder="Shoulders",
    gear_back="Back", gear_chest="Chest", gear_wrist="Wrists",
    gear_hands="Hands", gear_waist="Waist", gear_legs="Legs",
    gear_feet="Feet", gear_ring1="Ring 1", gear_ring2="Ring 2",
    gear_trinket1="Trinket 1", gear_trinket2="Trinket 2",
    gear_mainhand="Main Hand", gear_offhand="Off Hand", gear_ranged="Ranged",
}

local headerDividers = {}   -- textures created per BuildHeaders call, tracked for cleanup

local function ClearHeaders()
    wipe(headerButtons)
    for _, child in ipairs({headerContent:GetChildren()}) do child:Hide() end
    for _, div in ipairs(headerDividers) do div:Hide() end
    wipe(headerDividers)
end

local function BuildHeaders()
    ClearHeaders()

    -- Re-add the frozen Name button (always present, created in CreateFrameIfNeeded)
    -- It's in frozenHeader, not headerContent, so nothing to do here

    local padding=6; local x=10
    for i, col in ipairs(scrollableCols) do
        local btn=CreateFrame("Button",nil,headerContent)
        btn:SetPoint("LEFT",x,0); btn:SetSize(col.width,currentHeaderHeight); btn.field=col.field

        if col.vertical and not col.repIcon then
            local lbl=btn:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
            lbl:SetPoint("TOP",btn,"TOP",0,-2); lbl:SetPoint("BOTTOM",btn,"BOTTOM",0,2)
            lbl:SetWidth(col.width); lbl:SetJustifyH("CENTER"); lbl:SetJustifyV("TOP")
            lbl:SetWordWrap(true); lbl:SetNonSpaceWrap(true)
            lbl:SetText(StackChars(col.verticalLabel or col.label))
            btn.label=lbl
            btn:SetScript("OnClick",function()
                if sortColumn==col.field then sortAsc=not sortAsc
                else sortColumn=col.field; sortAsc=false end
                UpdateSortArrows(); BuildDisplayList(); UpdateScroll(); UpdateRows(); UpdateTotalsBar()
            end)
            btn:SetScript("OnEnter",function()
                local ar,ag,ab = AltTracker.GetAccentRGB()
                lbl:SetTextColor(ar,ag,ab)
                GameTooltip:SetOwner(btn,"ANCHOR_BOTTOM"); GameTooltip:ClearLines()
                GameTooltip:AddLine(col.label,1,1,1)
                if col.type=="repCombined" then GameTooltip:AddLine("|cffaaaaaa(shows whichever is active)|r",1,1,1) end
                GameTooltip:AddLine("Sort by "..col.label,0.7,0.7,0.7); GameTooltip:Show()
            end)
            btn:SetScript("OnLeave",function()
                if sortColumn~=col.field then lbl:SetTextColor(unpack(AltTracker.C.TEXT_NORM)) end
                GameTooltip:Hide()
            end)
        elseif col.slotSlug or col.profIcon or col.slotIcon or col.repIcon or col.headerIcon then
            -- slotSlug: faction-aware gear icon resolved at header-build time
            local iconPath = (col.slotSlug and AltTracker.GetGearIconPath and AltTracker.GetGearIconPath(col.slotSlug))
                or col.profIcon or col.slotIcon or col.repIcon or col.headerIcon
            local sz=math.min(currentHeaderHeight-4,col.width-2)
            local tex=btn:CreateTexture(nil,"OVERLAY")
            tex:SetSize(sz,sz); tex:SetPoint("CENTER",btn,"CENTER",0,0); tex:SetTexture(iconPath)
            -- For the built-in round WoW icons we auto-crop the pixel border
            -- (0.08..0.92 tex coords). Custom art (headerIcon) ships already
            -- trimmed and transparent, so we use the full texture untouched.
            if not col.headerIcon then
                tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            end
            btn.label=btn:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall"); btn.label:SetText("")
            btn.iconTex=tex
            btn:SetScript("OnClick",function()
                if sortColumn==col.field then sortAsc=not sortAsc
                else sortColumn=col.field; sortAsc=false end
                UpdateSortArrows(); BuildDisplayList(); UpdateScroll(); UpdateRows(); UpdateTotalsBar()
            end)
            btn:SetScript("OnEnter",function()
                local ar,ag,ab = AltTracker.GetAccentRGB()
                tex:SetVertexColor(ar,ag,ab)
                GameTooltip:SetOwner(btn,"ANCHOR_BOTTOM"); GameTooltip:ClearLines()
                local tipText = COL_TOOLTIPS[col.field] or col.label
                GameTooltip:AddLine(tipText,1,1,1)
                GameTooltip:AddLine("Sort by "..col.label,0.7,0.7,0.7); GameTooltip:Show()
            end)
            btn:SetScript("OnLeave",function()
                tex:SetVertexColor(1,1,1)
                GameTooltip:Hide()
            end)
        elseif col.type=="classIcon" or col.type=="specIcon" or col.type=="raceIcon" then
            -- Small centered header label for icon columns
            local SHORT = {classIcon="C", specIcon="S", raceIcon="R"}
            local lbl=btn:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
            lbl:SetAllPoints(); lbl:SetJustifyH("CENTER"); lbl:SetJustifyV("MIDDLE")
            lbl:SetText(SHORT[col.type] or "")
            btn.label=lbl
            btn:SetScript("OnClick",function()
                if sortColumn==col.field then sortAsc=not sortAsc
                else sortColumn=col.field; sortAsc=false end
                UpdateSortArrows(); BuildDisplayList(); UpdateScroll(); UpdateRows(); UpdateTotalsBar()
            end)
            btn:SetScript("OnEnter",function()
                local ar,ag,ab = AltTracker.GetAccentRGB()
                lbl:SetTextColor(ar,ag,ab)
                GameTooltip:SetOwner(btn,"ANCHOR_BOTTOM"); GameTooltip:ClearLines()
                GameTooltip:AddLine(col.label,1,1,1)
                GameTooltip:AddLine("Sort by "..col.label,0.7,0.7,0.7); GameTooltip:Show()
            end)
            btn:SetScript("OnLeave",function()
                if sortColumn~=col.field then lbl:SetTextColor(unpack(AltTracker.C.TEXT_NORM)) end
                GameTooltip:Hide()
            end)
        else
            local lbl=btn:CreateFontString(nil,"OVERLAY","GameFontHighlight")
            lbl:SetPoint("LEFT",2,0); lbl:SetPoint("RIGHT",-10,0)
            lbl:SetJustifyH(col.align or "LEFT"); lbl:SetJustifyV("MIDDLE"); lbl:SetText(col.label)
            btn.label=lbl
            local arrow=btn:CreateTexture(nil,"OVERLAY")
            arrow:SetTexture("Interface\\Buttons\\UI-SortArrow")
            arrow:SetSize(8,8); arrow:SetPoint("RIGHT",btn,"RIGHT",-1,0); arrow:Hide()
            btn.arrow=arrow
            btn:SetScript("OnClick",function()
                if sortColumn==col.field then sortAsc=not sortAsc
                else sortColumn=col.field; sortAsc=false end
                UpdateSortArrows(); BuildDisplayList(); UpdateScroll(); UpdateRows(); UpdateTotalsBar()
            end)
            btn:SetScript("OnEnter",function()
                local ar,ag,ab = AltTracker.GetAccentRGB()
                lbl:SetTextColor(ar,ag,ab)
                local tip=COL_TOOLTIPS[col.field]
                if tip then
                    GameTooltip:SetOwner(btn,"ANCHOR_BOTTOM"); GameTooltip:ClearLines()
                    GameTooltip:AddLine(tip,1,1,1); GameTooltip:AddLine("Sort by "..tip,0.7,0.7,0.7); GameTooltip:Show()
                end
            end)
            btn:SetScript("OnLeave",function()
                if sortColumn~=col.field then lbl:SetTextColor(unpack(AltTracker.C.TEXT_NORM)) end
                GameTooltip:Hide()
            end)
        end

        table.insert(headerButtons,btn)
        if i<#scrollableCols then
            local div=headerContent:CreateTexture(nil,"OVERLAY")
            div:SetSize(1,currentHeaderHeight); div:SetPoint("LEFT",x+col.width+math.floor(padding/2),0)
            div:SetColorTexture(unpack(AltTracker.C.SEP))
            table.insert(headerDividers, div)
        end
        x=x+col.width+padding
    end
    UpdateSortArrows()
end

------------------------------------------------------------
-- Per-section window resize.
-- SetSize changes only the dimensions, never the anchor points, so the
-- window stays wherever the user left it.  No need to ClearAllPoints.
------------------------------------------------------------

local function ResizeFrame(w, h)
    if not frame then return end
    frame:SetSize(w, h)
end

------------------------------------------------------------
-- Content-driven frame sizing
--
-- Width  = sidebar + frozen Name col + scrollable cols + vertical scrollbar
-- Height = title bar + column header + (clamped row count × ROW_HEIGHT) + footer
--
-- The section's static preferW/preferH on the SECTIONS table is no longer the
-- source of truth — those left empty borders around the table when the user
-- had fewer alts than the static height assumed, or when the addon was
-- toggled (ShowSheet used to reset to FRAME_W/FRAME_H, blowing away the
-- previous SwitchSection resize). Now the frame snaps tight to whatever's
-- being shown, so the grid feels attached to the frame edges.
------------------------------------------------------------

local MIN_BODY_ROWS = 4   -- minimum row slots so the frame doesn't shrink to a sliver
local MAX_BODY_ROWS = 22  -- cap so users with 50+ alts still get a scrollable view

local function ComputeContentSize()
    local rawRowCount = #displayList
    local rowCount    = rawRowCount
    if rowCount < MIN_BODY_ROWS then rowCount = MIN_BODY_ROWS end
    if rowCount > MAX_BODY_ROWS then rowCount = MAX_BODY_ROWS end

    -- Will the visible row count fit? If we capped rowCount below, that
    -- means the user has more characters than the viewport can show, so
    -- a vertical scrollbar will be needed. This is the single decision
    -- point for v-scrollbar gutter reservation.
    local needsV = rawRowCount > rowCount

    -- Width is determined entirely by columns + sidebar + frozen + maybe
    -- v-scrollbar gutter. There's no horizontal-scrollbar contribution to
    -- width because the h-scrollbar lives below the body, not beside it.
    local w = SIDEBAR_WIDTH + (FROZEN_WIDTH or 156) + GetScrollableWidth()
            + (needsV and SCROLLBAR_GUTTER_W or 4)

    -- Whether h-scroll is needed is decided by content width vs the
    -- viewport width AT THIS frame width — which we just computed.
    -- The viewport width = w - SIDEBAR_WIDTH - FROZEN_WIDTH - rightInset.
    local rightInset = needsV and SCROLLBAR_GUTTER_W or 2
    local viewportW  = w - SIDEBAR_WIDTH - FROZEN_WIDTH - rightInset
    local needsH     = GetScrollableWidth() > viewportW

    local h = TITLE_H                                       -- title bar
            + 4                                             -- gap title→header
            + currentHeaderHeight                           -- column header
            + 1                                             -- separator under header
            + (rowCount * ROW_HEIGHT)                       -- body
            + (needsH and HSCROLL_GUTTER_H or 0)            -- h-scrollbar gutter
            + (AltTracker.LAYOUT.FOOTER_HEIGHT or 22)       -- totals bar
            + 2                                             -- breath above frame border
    return w, h, needsH, needsV
end

local function ResizeFrameToContent()
    if not frame then return end
    -- Plugins (Recipes, Options) manage their own sizing — don't fight them.
    if activeSection and activeSection._isPlugin then return end
    local w, h, needsH, needsV = ComputeContentSize()
    frame:SetSize(w, h)
    -- ComputeContentSize is the authority on scrollbar visibility — it's
    -- derived purely from row count and column width vs the frame size we
    -- just set, so it's always self-consistent. UpdateScroll's measure()
    -- might disagree by a pixel due to rounding; ComputeContentSize wins.
    frame._layoutNeedsHScroll = needsH
    frame._layoutNeedsVScroll = needsV
    -- Apply final anchors and sync content sizes / scrollbar visibility.
    UpdateScroll()
end

------------------------------------------------------------
-- Section switching
------------------------------------------------------------

local function AdjustHeaderHeight(h)
    currentHeaderHeight = h
    if frozenHeader then frozenHeader:SetHeight(h) end
    if headerScroll then headerScroll:SetHeight(h) end
    if headerContent then headerContent:SetHeight(h) end
    -- Body scroll TOPLEFT anchors are handled by ApplyContentAnchors via
    -- BodyTopY(), which reads currentHeaderHeight. UpdateScroll always runs
    -- after this in SwitchSection, so no need to set anchors here.
end

local function SwitchSection(section)
    -- If a plugin is currently active, deactivate it first
    if activeSection._isPlugin and activeSection.OnDeactivate then
        activeSection.OnDeactivate(frame)
    end

    -- If the previous section was a plugin, restore the normal content frames
    if activeSection._isPlugin and frame then
        if frame.bodyScroll   then frame.bodyScroll:Show()   end
        if frame.frozenScroll then frame.frozenScroll:Show() end
        if frame.headerScroll then frame.headerScroll:Show() end
        if frame.frozenHeader then frame.frozenHeader:Show() end
        if frame.hScrollBar   then frame.hScrollBar:Show()  end
        if frame.totalsBar    then frame.totalsBar:Show()   end
    end

    activeSection = section

    -- Adjust header height for this section
    AdjustHeaderHeight(section.headerHeight or HEADER_HEIGHT)

    -- Highlight active sidebar button using theme accent
    local ar, ag, ab = AltTracker.GetAccentRGB()
    for _, btn in ipairs(sidebarBtns) do
        if btn.sectionId == section.id then
            btn:SetBackdropColor(
                AltTracker.C.BG_BTN_ACTIVE[1], AltTracker.C.BG_BTN_ACTIVE[2],
                AltTracker.C.BG_BTN_ACTIVE[3], AltTracker.C.BG_BTN_ACTIVE[4])
            btn.lbl:SetTextColor(ar, ag, ab)
            if btn.icon then btn.icon:SetAlpha(1.0) end
            if btn.accentStripe then
                btn.accentStripe:SetColorTexture(ar, ag, ab, 1)
                btn.accentStripe:Show()
            end
        else
            btn:SetBackdropColor(
                AltTracker.C.BG_BTN_IDLE[1], AltTracker.C.BG_BTN_IDLE[2],
                AltTracker.C.BG_BTN_IDLE[3], AltTracker.C.BG_BTN_IDLE[4])
            btn.lbl:SetTextColor(unpack(AltTracker.C.TEXT_DIM))
            if btn.icon then btn.icon:SetAlpha(0.65) end
            if btn.accentStripe then btn.accentStripe:Hide() end
        end
    end

    BuildScrollableColsForSection(section)
    BuildHeaders()
    UpdateScroll()
    local needed=CountVisibleRows()
    EnsureRows(needed)
    BuildDisplayList()
    UpdateRows()
    UpdateTotalsBar()

    -- Snap the frame to the actual content size for this section.
    -- Plugins (and the built-in Options pseudo-section) manage their own
    -- size in OnActivate, so ResizeFrameToContent early-outs for them.
    ResizeFrameToContent()
end

------------------------------------------------------------
-- Main frame
------------------------------------------------------------

local function CreateFrameIfNeeded()
    if frame then return end

    -- Restore persisted hideLow preference; default to true if never saved
    AltTrackerConfig = AltTrackerConfig or {}
    if AltTrackerConfig.hideLow == nil then
        AltTrackerConfig.hideLow = true
    end
    hideLow = AltTrackerConfig.hideLow

    ComputeFrozenWidth()
    BuildScrollableColsForSection(activeSection)

    frame=CreateFrame("Frame","AltTrackerSheet",UIParent,"BackdropTemplate")
    frame:SetSize(FRAME_W, FRAME_H)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("DIALOG"); frame:SetToplevel(true)
    AltTracker.ApplyBackdrop(frame,
        AltTracker.C.BG_MAIN[1], AltTracker.C.BG_MAIN[2],
        AltTracker.C.BG_MAIN[3], AltTracker.C.BG_MAIN[4])
    frame:SetScale(AltTrackerConfig.scale or 1.0)
    frame:SetMovable(true); frame:EnableMouse(false)  -- drag handled by titleBar
    tinsert(UISpecialFrames,"AltTrackerSheet")

    --------------------------------------------------------
    -- Title bar — full-width, spans the top of the frame.
    -- Owns drag, title text, and close button.
    --------------------------------------------------------

    local titleBar = CreateFrame("Frame", nil, frame)
    titleBar:SetPoint("TOPLEFT",  frame, "TOPLEFT",  0, 0)
    titleBar:SetPoint("TOPRIGHT", frame, "TOPRIGHT",  0, 0)
    titleBar:SetHeight(TITLE_H)
    titleBar:EnableMouse(true)
    titleBar:RegisterForDrag("LeftButton")
    titleBar:SetScript("OnDragStart", function() frame:StartMoving() end)
    titleBar:SetScript("OnDragStop",  function() frame:StopMovingOrSizing() end)

    -- Title bar background (slightly lighter than main to distinguish)
    local tbBg = titleBar:CreateTexture(nil, "BACKGROUND")
    tbBg:SetAllPoints()
    tbBg:SetColorTexture(0.10, 0.10, 0.10, 1)

    -- Bottom separator on title bar
    local tbSep = titleBar:CreateTexture(nil, "OVERLAY")
    tbSep:SetHeight(1)
    tbSep:SetPoint("BOTTOMLEFT",  titleBar, "BOTTOMLEFT",  0, 0)
    tbSep:SetPoint("BOTTOMRIGHT", titleBar, "BOTTOMRIGHT", 0, 0)
    tbSep:SetColorTexture(0, 0, 0, 1)

    -- Title text
    local titleText = titleBar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    titleText:SetPoint("LEFT", SIDEBAR_WIDTH + 10, 0)
    titleText:SetText("AltTracker")
    local function UpdateTitleTextColor()
        local r, g, b = AltTracker.GetAccentRGB()
        titleText:SetTextColor(r, g, b)
    end
    UpdateTitleTextColor()
    AltTracker.RegisterThemeCallback(UpdateTitleTextColor)

    -- Close button inside title bar, far right
    local close = CreateFrame("Button", nil, titleBar, "BackdropTemplate")
    close:SetSize(18, 18)
    close:SetPoint("RIGHT", titleBar, "RIGHT", -6, 0)
    close:SetFrameLevel(titleBar:GetFrameLevel() + 5)
    AltTracker.ApplyBackdrop(close, 0.18, 0.05, 0.05, 1)
    local closeX = close:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    closeX:SetAllPoints(); closeX:SetJustifyH("CENTER"); closeX:SetText("|cffdddddd×|r")
    close:SetScript("OnClick",  function() frame:Hide() end)
    close:SetScript("OnEnter",  function() close:SetBackdropColor(0.35, 0.08, 0.08, 1) end)
    close:SetScript("OnLeave",  function() close:SetBackdropColor(0.18, 0.05, 0.05, 1) end)

    --------------------------------------------------------
    -- Left sidebar
    --------------------------------------------------------

    local sidebar=CreateFrame("Frame",nil,frame,"BackdropTemplate")
    sidebar:SetPoint("TOPLEFT",frame,"TOPLEFT",1,-TITLE_H)
    sidebar:SetPoint("BOTTOMLEFT",frame,"BOTTOMLEFT",1,1)
    -- Fill flush to the SIDEBAR_WIDTH divider line. Was SIDEBAR_WIDTH-8,
    -- which left an 8px dead band between the sidebar's right edge and
    -- the grid's left edge — visible as a vertical strip of empty dark
    -- space in screenshots.
    sidebar:SetWidth(SIDEBAR_WIDTH-1)
    AltTracker.ApplyBGOnly(sidebar,
        AltTracker.C.BG_SIDEBAR[1], AltTracker.C.BG_SIDEBAR[2],
        AltTracker.C.BG_SIDEBAR[3], AltTracker.C.BG_SIDEBAR[4])

    -- Sidebar right border (1px separator)
    local sbRightLine = sidebar:CreateTexture(nil,"OVERLAY")
    sbRightLine:SetWidth(1)
    sbRightLine:SetPoint("TOPRIGHT",sidebar,"TOPRIGHT",0,0)
    sbRightLine:SetPoint("BOTTOMRIGHT",sidebar,"BOTTOMRIGHT",0,0)
    sbRightLine:SetColorTexture(0, 0, 0, 1)

    -- Thin top divider to visually separate first button from the sidebar top edge
    local sbDivider=sidebar:CreateTexture(nil,"ARTWORK")
    sbDivider:SetHeight(1)
    sbDivider:SetPoint("TOPLEFT",sidebar,"TOPLEFT",0,-4)
    sbDivider:SetPoint("TOPRIGHT",sidebar,"TOPRIGHT",0,-4)
    sbDivider:SetColorTexture(unpack(AltTracker.C.SEP))

    -- Section buttons start just below the top divider
    local btnY = -8
    for _, section in ipairs(SECTIONS) do
        local btn=CreateFrame("Button",nil,sidebar,"BackdropTemplate")
        btn:SetHeight(26)
        btn:SetPoint("TOPLEFT",sidebar,"TOPLEFT",0,btnY)
        btn:SetPoint("TOPRIGHT",sidebar,"TOPRIGHT",0,btnY)
        AltTracker.ApplyBGOnly(btn,
            AltTracker.C.BG_BTN_IDLE[1], AltTracker.C.BG_BTN_IDLE[2],
            AltTracker.C.BG_BTN_IDLE[3], AltTracker.C.BG_BTN_IDLE[4])
        btn.sectionId = section.id

        -- Left accent stripe (shown only when active)
        local stripe=btn:CreateTexture(nil,"OVERLAY")
        stripe:SetWidth(2)
        stripe:SetPoint("TOPLEFT",btn,"TOPLEFT",0,0)
        stripe:SetPoint("BOTTOMLEFT",btn,"BOTTOMLEFT",0,0)
        stripe:Hide()
        btn.accentStripe = stripe

        -- Icon — alpha dims/brightens rather than tinting so artwork colors show
        local icon=btn:CreateTexture(nil,"ARTWORK")
        icon:SetSize(18,18); icon:SetPoint("LEFT",6,0)
        icon:SetTexture(section.icon)
        icon:SetAlpha(0.65)  -- inactive

        -- Label
        local lbl=btn:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
        lbl:SetPoint("LEFT",28,0); lbl:SetPoint("RIGHT",-4,0)
        lbl:SetJustifyH("LEFT"); lbl:SetText(section.label)
        lbl:SetTextColor(unpack(AltTracker.C.TEXT_DIM))
        btn.lbl=lbl; btn.icon=icon

        btn:SetScript("OnClick",function() SwitchSection(section) end)
        btn:SetScript("OnEnter",function()
            if activeSection.id~=section.id then
                btn:SetBackdropColor(
                    AltTracker.C.BG_BTN_HOVER[1], AltTracker.C.BG_BTN_HOVER[2],
                    AltTracker.C.BG_BTN_HOVER[3], AltTracker.C.BG_BTN_HOVER[4])
                lbl:SetTextColor(unpack(AltTracker.C.TEXT_BRIGHT))
                icon:SetAlpha(0.85)
            end
        end)
        btn:SetScript("OnLeave",function()
            if activeSection.id~=section.id then
                btn:SetBackdropColor(
                    AltTracker.C.BG_BTN_IDLE[1], AltTracker.C.BG_BTN_IDLE[2],
                    AltTracker.C.BG_BTN_IDLE[3], AltTracker.C.BG_BTN_IDLE[4])
                lbl:SetTextColor(unpack(AltTracker.C.TEXT_DIM))
                icon:SetAlpha(0.65)
            end
        end)

        table.insert(sidebarBtns,btn)
        btnY = btnY - 27
    end

    --------------------------------------------------------
    -- Plugin buttons (registered via AltTracker.RegisterPlugin)
    -- We store the current Y offset on the sidebar so that
    -- AddPluginButton (called live when a plugin registers late)
    -- can append below whatever is already there.
    --------------------------------------------------------

    sidebar._pluginBtnY = btnY  -- tracked so late-registering plugins can append

    local function MakePluginButton(plugin)
        local pbtn=CreateFrame("Button",nil,sidebar,"BackdropTemplate")
        pbtn:SetHeight(26)
        pbtn:SetPoint("TOPLEFT",sidebar,"TOPLEFT",0,sidebar._pluginBtnY)
        pbtn:SetPoint("TOPRIGHT",sidebar,"TOPRIGHT",0,sidebar._pluginBtnY)
        AltTracker.ApplyBGOnly(pbtn,
            AltTracker.C.BG_BTN_IDLE[1], AltTracker.C.BG_BTN_IDLE[2],
            AltTracker.C.BG_BTN_IDLE[3], AltTracker.C.BG_BTN_IDLE[4])
        pbtn.sectionId = plugin.id

        local stripe=pbtn:CreateTexture(nil,"OVERLAY")
        stripe:SetWidth(2)
        stripe:SetPoint("TOPLEFT",pbtn,"TOPLEFT",0,0)
        stripe:SetPoint("BOTTOMLEFT",pbtn,"BOTTOMLEFT",0,0)
        stripe:Hide()
        pbtn.accentStripe = stripe

        local icon=pbtn:CreateTexture(nil,"ARTWORK")
        icon:SetSize(18,18); icon:SetPoint("LEFT",6,0)
        if plugin.icon then
            icon:SetTexture(plugin.icon)
        end
        icon:SetAlpha(0.65)  -- inactive: dim artwork without color-tinting

        local lbl=pbtn:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
        lbl:SetPoint("LEFT",28,0); lbl:SetPoint("RIGHT",-4,0)
        lbl:SetJustifyH("LEFT"); lbl:SetText(plugin.label)
        lbl:SetTextColor(0.5,0.85,0.85)
        pbtn.lbl=lbl; pbtn.icon=icon

        pbtn:SetScript("OnClick",function()
            for _, b in ipairs(sidebarBtns) do
                b:SetBackdropColor(
                    AltTracker.C.BG_BTN_IDLE[1], AltTracker.C.BG_BTN_IDLE[2],
                    AltTracker.C.BG_BTN_IDLE[3], AltTracker.C.BG_BTN_IDLE[4])
                if b.lbl then b.lbl:SetTextColor(unpack(AltTracker.C.TEXT_DIM)) end
                if b.accentStripe then b.accentStripe:Hide() end
                if b.icon then b.icon:SetAlpha(0.65) end
            end
            pbtn:SetBackdropColor(
                AltTracker.C.BG_BTN_ACTIVE[1], AltTracker.C.BG_BTN_ACTIVE[2],
                AltTracker.C.BG_BTN_ACTIVE[3], AltTracker.C.BG_BTN_ACTIVE[4])
            stripe:SetColorTexture(0, 0.85, 0.85, 1); stripe:Show()
            lbl:SetTextColor(0,1,0.9)
            icon:SetAlpha(1.0)
            if activeSection._isPlugin and activeSection.OnDeactivate then
                activeSection.OnDeactivate(frame)
            end
            activeSection = plugin
            plugin.OnActivate(frame)
        end)
        pbtn:SetScript("OnEnter",function()
            if activeSection.id~=plugin.id then
                pbtn:SetBackdropColor(
                    AltTracker.C.BG_BTN_HOVER[1], AltTracker.C.BG_BTN_HOVER[2],
                    AltTracker.C.BG_BTN_HOVER[3], AltTracker.C.BG_BTN_HOVER[4])
                lbl:SetTextColor(0.7,1,1)
                icon:SetAlpha(0.85)
            end
        end)
        pbtn:SetScript("OnLeave",function()
            if activeSection.id~=plugin.id then
                pbtn:SetBackdropColor(
                    AltTracker.C.BG_BTN_IDLE[1], AltTracker.C.BG_BTN_IDLE[2],
                    AltTracker.C.BG_BTN_IDLE[3], AltTracker.C.BG_BTN_IDLE[4])
                lbl:SetTextColor(0.5,0.85,0.85)
                icon:SetAlpha(0.65)
            end
        end)

        table.insert(sidebarBtns,pbtn)
        sidebar._pluginBtnY = sidebar._pluginBtnY - 27
    end

    -- Render any plugins already registered before the frame was built
    for _, plugin in ipairs(AltTracker.plugins) do
        MakePluginButton(plugin)
    end

    -- Expose so late-registering plugins (loaded after SheetUI) get a button
    AltTracker.AddPluginButton = MakePluginButton

    --------------------------------------------------------
    -- Built-in Options section
    -- Shown as a plugin-style section in the sidebar.
    -- Fully self-contained — theme/scale callbacks never
    -- call SwitchSection or re-enter ApplyTheme.
    --------------------------------------------------------

    -- Options content: sized to fit inside the content area
    local optionsFrame = CreateFrame("Frame", nil, frame)
    optionsFrame:SetPoint("TOPLEFT", frame, "TOPLEFT", SIDEBAR_WIDTH + 1, -TITLE_H)
    optionsFrame:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 1)
    optionsFrame:Hide()

    -- Background
    local optBG = optionsFrame:CreateTexture(nil, "BACKGROUND")
    optBG:SetAllPoints()
    optBG:SetColorTexture(unpack(AltTracker.C.BG_MAIN))

    -- ── Layout ──────────────────────────────────────────────
    -- We build everything at fixed offsets from TOPLEFT so
    -- nothing can overflow or go off-screen.
    local P = 18   -- left/right padding inside the options panel
    local Y = -12  -- current Y cursor (negative = down from top)

    local function MakeLabel(text, fontObj, yExtra)
        local fs = optionsFrame:CreateFontString(nil, "OVERLAY", fontObj or "GameFontNormal")
        fs:SetPoint("TOPLEFT", P, Y + (yExtra or 0))
        fs:SetText(text)
        return fs
    end

    -- Title
    local optTitle = MakeLabel("Options", "GameFontNormal")
    local function SyncTitleColor()
        local r, g, b = AltTracker.GetAccentRGB()
        optTitle:SetTextColor(r, g, b)
    end
    SyncTitleColor()
    AltTracker.RegisterThemeCallback(SyncTitleColor)
    Y = Y - 22

    -- Thin divider
    local optDiv1 = optionsFrame:CreateTexture(nil, "ARTWORK")
    optDiv1:SetHeight(1)
    optDiv1:SetPoint("TOPLEFT",  optionsFrame, "TOPLEFT",  0,     Y)
    optDiv1:SetPoint("TOPRIGHT", optionsFrame, "TOPRIGHT", 0,     Y)
    optDiv1:SetColorTexture(unpack(AltTracker.C.SEP))
    Y = Y - 16

    -- ── Appearance section ────────────────────────────────
    local optSectionHdr = optionsFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    optSectionHdr:SetPoint("TOPLEFT", P, Y)
    optSectionHdr:SetText("APPEARANCE")
    optSectionHdr:SetTextColor(unpack(AltTracker.C.TEXT_DIM))
    Y = Y - 20

    -- Theme row
    local optThemeLabel = optionsFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    optThemeLabel:SetPoint("TOPLEFT", P, Y)
    optThemeLabel:SetText("Theme")
    optThemeLabel:SetTextColor(unpack(AltTracker.C.TEXT_NORM))

    local BTNY = Y + 1   -- vertically aligned with label text
    local BTN_W, BTN_H = 72, 22

    local optDarkBtn = CreateFrame("Button", nil, optionsFrame, "BackdropTemplate")
    optDarkBtn:SetSize(BTN_W, BTN_H)
    optDarkBtn:SetPoint("TOPLEFT", P + 60, BTNY)
    AltTracker.ApplyBackdrop(optDarkBtn, 0.12, 0.12, 0.12, 1)
    local optDarkLbl = optDarkBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    optDarkLbl:SetAllPoints(); optDarkLbl:SetJustifyH("CENTER"); optDarkLbl:SetText("Dark")

    local optClassBtn = CreateFrame("Button", nil, optionsFrame, "BackdropTemplate")
    optClassBtn:SetSize(BTN_W, BTN_H)
    optClassBtn:SetPoint("LEFT", optDarkBtn, "RIGHT", 8, 0)
    AltTracker.ApplyBackdrop(optClassBtn, 0.12, 0.12, 0.12, 1)
    local optClassLbl = optClassBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    optClassLbl:SetAllPoints(); optClassLbl:SetJustifyH("CENTER"); optClassLbl:SetText("Class")

    -- Theme hint text (to right of buttons)
    local optThemeHint = optionsFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    optThemeHint:SetPoint("LEFT", optClassBtn, "RIGHT", 14, 0)
    optThemeHint:SetPoint("RIGHT", optionsFrame, "RIGHT", -P, 0)
    optThemeHint:SetJustifyH("LEFT"); optThemeHint:SetWordWrap(true)
    optThemeHint:SetTextColor(unpack(AltTracker.C.TEXT_DIM))
    optThemeHint:SetText("Class uses current player class color as accent.")

    -- Refresh theme button highlight (no callbacks, no side effects)
    -- Must NOT call ApplyTheme or SwitchSection
    local function RefreshThemeBtns()
        local cur = AltTrackerConfig and AltTrackerConfig.theme or "dark"
        local ar, ag, ab = AltTracker.GetAccentRGB()
        if cur == "dark" then
            optDarkLbl:SetTextColor(ar, ag, ab)
            optClassLbl:SetTextColor(unpack(AltTracker.C.TEXT_NORM))
        else
            optDarkLbl:SetTextColor(unpack(AltTracker.C.TEXT_NORM))
            optClassLbl:SetTextColor(ar, ag, ab)
        end
    end
    -- Sync when accent changes (sidebar callback won't call SwitchSection)
    AltTracker.RegisterThemeCallback(function()
        if optionsFrame:IsShown() then RefreshThemeBtns() end
    end)

    optDarkBtn:SetScript("OnClick", function()
        AltTrackerConfig = AltTrackerConfig or {}
        AltTrackerConfig.theme = "dark"
        RefreshThemeBtns()
        AltTracker.ApplyTheme()
    end)
    optClassBtn:SetScript("OnClick", function()
        AltTrackerConfig = AltTrackerConfig or {}
        AltTrackerConfig.theme = "class"
        RefreshThemeBtns()
        AltTracker.ApplyTheme()
    end)

    Y = Y - 34

    -- ── Scale row ─────────────────────────────────────────
    -- Layout target:
    --   Scale       0.75 ──────●────── 1.25      Reset
    --                          1.00
    --
    -- The slider's template-provided Low/High font strings are anchored to
    -- the slider's bottom-left / bottom-right corners. We add a matching
    -- "1.00" mid-tick anchored to the bottom-center so all three ticks live
    -- on the same baseline. The current numeric value is shown via tooltip
    -- on the slider, not as a floating label that collides with .Low at
    -- smaller UI scales.
    local optScaleLabel = optionsFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    optScaleLabel:SetPoint("TOPLEFT", P, Y)
    optScaleLabel:SetText("Scale")
    optScaleLabel:SetTextColor(unpack(AltTracker.C.TEXT_NORM))

    local optScaleSlider = CreateFrame("Slider", nil, optionsFrame, "OptionsSliderTemplate")
    optScaleSlider:SetPoint("TOPLEFT", P + 60, Y + 4)
    optScaleSlider:SetWidth(280); optScaleSlider:SetHeight(16)
    optScaleSlider:SetMinMaxValues(0.75, 1.25)
    optScaleSlider:SetValueStep(0.05)
    -- NOTE: SetObeyStepOnDrag does NOT exist in TBC Classic 2.5.x — omitted.

    if optScaleSlider.Low  then optScaleSlider.Low:SetText("0.75")  end
    if optScaleSlider.High then optScaleSlider.High:SetText("1.25") end

    -- 1.00 mid-tick on the same baseline as Low/High
    local optScaleMid = optionsFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    optScaleMid:SetPoint("TOP", optScaleSlider, "BOTTOM", 0, 2)
    optScaleMid:SetText("1.00")
    optScaleMid:SetTextColor(unpack(AltTracker.C.TEXT_DIM))

    local optScaleReset = CreateFrame("Button", nil, optionsFrame, "BackdropTemplate")
    optScaleReset:SetSize(58, 20)
    optScaleReset:SetPoint("LEFT", optScaleSlider, "RIGHT", 16, 0)
    AltTracker.ApplyBackdrop(optScaleReset, 0.12, 0.12, 0.12, 1)
    local optScaleResetLbl = optScaleReset:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    optScaleResetLbl:SetAllPoints(); optScaleResetLbl:SetJustifyH("CENTER"); optScaleResetLbl:SetText("Reset")

    -- Tooltip showing the live scale value (replaces the old floating label)
    optScaleSlider:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(string.format("Scale: %.2f", self:GetValue()), 1, 1, 1)
        GameTooltip:Show()
    end)
    optScaleSlider:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- Flag to prevent recursive firing when we set value programmatically
    local optSliderUpdating = false
    optScaleSlider:SetScript("OnValueChanged", function(self, value)
        if optSliderUpdating then return end
        local rounded = math.floor(value / 0.05 + 0.5) * 0.05
        rounded = math.max(0.75, math.min(1.25, rounded))
        AltTracker.SetScale(rounded)
        if GameTooltip:IsOwned(self) then
            GameTooltip:SetText(string.format("Scale: %.2f", rounded), 1, 1, 1)
        end
    end)
    optScaleReset:SetScript("OnClick", function()
        optSliderUpdating = true
        optScaleSlider:SetValue(1.0)
        optSliderUpdating = false
        AltTracker.SetScale(1.0)
    end)

    Y = Y - 44   -- a bit more room for the mid-tick baseline below the slider

    -- ── Helper text ───────────────────────────────────────
    local optHint = optionsFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    optHint:SetPoint("TOPLEFT", P, Y)
    optHint:SetPoint("RIGHT", optionsFrame, "RIGHT", -P, 0)
    optHint:SetJustifyH("LEFT"); optHint:SetWordWrap(true)
    optHint:SetTextColor(unpack(AltTracker.C.TEXT_DIM))
    optHint:SetText("Class theme uses the current player class color as the UI accent. "
        .."Character rows still use each character's own class color.")

    -- OnShow: safely refresh all controls from saved config
    optionsFrame:SetScript("OnShow", function()
        AltTrackerConfig = AltTrackerConfig or {}
        local scale = AltTrackerConfig.scale or 1.0
        optSliderUpdating = true
        optScaleSlider:SetValue(scale)
        optSliderUpdating = false
        RefreshThemeBtns()
    end)

    -- Add the Options sidebar button
    do
        local optSect = {
            id = "options",
            label = "Options",
            icon  = (AltTracker.MEDIA_PATH or "Interface\\AddOns\\AltTracker\\Media\\")
                    .. "Icons\\options.tga",
            _isPlugin  = true,
            preferW = 760,
            preferH = 340,
            OnActivate = function(f)
                f.bodyScroll:Hide(); f.frozenScroll:Hide()
                f.headerScroll:Hide(); f.frozenHeader:Hide()
                f.hScrollBar:Hide(); f.totalsBar:Hide()
                optionsFrame:Show()
                ResizeFrame(760, 340)
            end,
            OnDeactivate = function(f)
                optionsFrame:Hide()
                f.totalsBar:Show()
            end,
        }
        MakePluginButton(optSect)
    end

    local sbDiv2=sidebar:CreateTexture(nil,"ARTWORK")
    sbDiv2:SetHeight(1)
    sbDiv2:SetPoint("BOTTOMLEFT",sidebar,"BOTTOMLEFT",0,42)
    sbDiv2:SetPoint("BOTTOMRIGHT",sidebar,"BOTTOMRIGHT",0,42)
    sbDiv2:SetColorTexture(unpack(AltTracker.C.SEP))

    -- "Filter" label row (compact)
    local filterRow=CreateFrame("Frame",nil,sidebar)
    filterRow:SetHeight(20)
    filterRow:SetPoint("BOTTOMLEFT",sidebar,"BOTTOMLEFT",0,22)
    filterRow:SetPoint("BOTTOMRIGHT",sidebar,"BOTTOMRIGHT",0,22)
    local filterIcon=filterRow:CreateTexture(nil,"OVERLAY")
    filterIcon:SetSize(11,11); filterIcon:SetPoint("LEFT",8,0)
    filterIcon:SetTexture((AltTracker.MEDIA_PATH or "Interface\\AddOns\\AltTracker\\Media\\") .. "Icons\\filter.tga")
    filterIcon:SetTexCoord(0.08,0.92,0.08,0.92)
    filterIcon:SetVertexColor(unpack(AltTracker.C.TEXT_DIM))
    local filterLbl=filterRow:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
    filterLbl:SetPoint("LEFT",22,0); filterLbl:SetText("Filter")
    filterLbl:SetTextColor(unpack(AltTracker.C.TEXT_DIM))

    -- "Hide below 58" styled checkbox
    local check=CreateFrame("CheckButton",nil,sidebar,"UICheckButtonTemplate")
    check:SetSize(18,18)
    check:SetPoint("BOTTOMLEFT",sidebar,"BOTTOMLEFT",4,4)
    check:SetChecked(hideLow)
    check.text:SetText("Hide below 58")
    check.text:SetTextColor(unpack(AltTracker.C.TEXT_DIM))
    check:SetScript("OnClick",function(self)
        hideLow=self:GetChecked()
        AltTrackerConfig.hideLow = hideLow
        BuildDisplayList(); UpdateScroll(); UpdateRows(); UpdateTotalsBar()
        ResizeFrameToContent()
    end)

    --------------------------------------------------------
    -- Totals bar
    --------------------------------------------------------

    totalsBar=CreateFrame("Frame",nil,frame,"BackdropTemplate")
    totalsBar:SetPoint("BOTTOMLEFT",frame,"BOTTOMLEFT",SIDEBAR_WIDTH,1)
    totalsBar:SetPoint("BOTTOMRIGHT",frame,"BOTTOMRIGHT",-1,1)
    totalsBar:SetHeight(22)
    AltTracker.ApplyBGOnly(totalsBar,
        AltTracker.C.BG_FOOTER[1], AltTracker.C.BG_FOOTER[2],
        AltTracker.C.BG_FOOTER[3], AltTracker.C.BG_FOOTER[4])
    -- top border line
    local totLine=frame:CreateTexture(nil,"OVERLAY"); totLine:SetHeight(1)
    totLine:SetPoint("BOTTOMLEFT",totalsBar,"TOPLEFT",0,0)
    totLine:SetPoint("BOTTOMRIGHT",totalsBar,"TOPRIGHT",0,0)
    totLine:SetColorTexture(unpack(AltTracker.C.SEP))
    totalsBar.left=totalsBar:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
    totalsBar.left:SetPoint("LEFT",10,0)
    totalsBar.left:SetTextColor(unpack(AltTracker.C.TEXT_NORM))
    totalsBar.mid=totalsBar:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
    totalsBar.mid:SetPoint("CENTER",totalsBar,"CENTER",0,0)
    totalsBar.mid:SetJustifyH("CENTER")
    totalsBar.mid:SetTextColor(unpack(AltTracker.C.TEXT_DIM))
    totalsBar.right=totalsBar:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
    totalsBar.right:SetPoint("RIGHT",-10,0); totalsBar.right:SetJustifyH("RIGHT")
    totalsBar.right:SetTextColor(unpack(AltTracker.C.TEXT_NORM))

    --------------------------------------------------------
    -- Frozen header (Name column)
    --------------------------------------------------------

    frozenHeader=CreateFrame("Frame",nil,frame)
    frozenHeader:SetPoint("TOPLEFT",frame,"TOPLEFT",SIDEBAR_WIDTH,-HEADER_TOP_Y)
    frozenHeader:SetSize(FROZEN_WIDTH,HEADER_HEIGHT)
    local fhBg=frozenHeader:CreateTexture(nil,"BACKGROUND")
    fhBg:SetAllPoints()
    fhBg:SetColorTexture(
        AltTracker.C.BG_HEADER[1], AltTracker.C.BG_HEADER[2],
        AltTracker.C.BG_HEADER[3], AltTracker.C.BG_HEADER[4])
    local fhLine=frozenHeader:CreateTexture(nil,"OVERLAY")
    fhLine:SetHeight(1); fhLine:SetPoint("BOTTOMLEFT"); fhLine:SetPoint("BOTTOMRIGHT")
    fhLine:SetColorTexture(unpack(AltTracker.C.SEP))

    -- Name header button (persistent)
    do
        local col=AltTracker.Columns[1]
        local btn=CreateFrame("Button",nil,frozenHeader)
        btn:SetPoint("LEFT",10,0); btn:SetSize(col.width,currentHeaderHeight); btn.field=col.field
        local lbl=btn:CreateFontString(nil,"OVERLAY","GameFontHighlight")
        lbl:SetPoint("LEFT",2,0); lbl:SetPoint("RIGHT",-10,0)
        lbl:SetJustifyH("LEFT"); lbl:SetJustifyV("MIDDLE"); lbl:SetText(col.label); btn.label=lbl
        local arrow=btn:CreateTexture(nil,"OVERLAY")
        arrow:SetTexture("Interface\\Buttons\\UI-SortArrow")
        arrow:SetSize(8,8); arrow:SetPoint("RIGHT",btn,"RIGHT",-1,0); arrow:Hide(); btn.arrow=arrow
        btn:SetScript("OnClick",function()
            if sortColumn==col.field then sortAsc=not sortAsc
            else sortColumn=col.field; sortAsc=false end
            UpdateSortArrows(); BuildDisplayList(); UpdateScroll(); UpdateRows(); UpdateTotalsBar()
        end)
        btn:SetScript("OnEnter",function()
            local ar,ag,ab = AltTracker.GetAccentRGB()
            lbl:SetTextColor(ar,ag,ab)
        end)
        btn:SetScript("OnLeave",function()
            if sortColumn~=col.field then lbl:SetTextColor(unpack(AltTracker.C.TEXT_NORM)) end
        end)
        table.insert(headerButtons,btn)
    end

    --------------------------------------------------------
    -- Scrollable header
    --------------------------------------------------------

    headerScroll=CreateFrame("ScrollFrame",nil,frame)
    headerScroll:SetPoint("TOPLEFT",frame,"TOPLEFT",SIDEBAR_WIDTH+FROZEN_WIDTH,-HEADER_TOP_Y)
    headerScroll:SetPoint("TOPRIGHT",frame,"TOPRIGHT",-20,-HEADER_TOP_Y)
    headerScroll:SetHeight(HEADER_HEIGHT)
    headerContent=CreateFrame("Frame",nil,headerScroll)
    headerContent:SetSize(GetScrollableWidth(),HEADER_HEIGHT)
    headerScroll:SetScrollChild(headerContent)
    local hBg=headerContent:CreateTexture(nil,"BACKGROUND")
    hBg:SetAllPoints()
    hBg:SetColorTexture(
        AltTracker.C.BG_HEADER[1], AltTracker.C.BG_HEADER[2],
        AltTracker.C.BG_HEADER[3], AltTracker.C.BG_HEADER[4])
    local hLine=headerContent:CreateTexture(nil,"OVERLAY")
    hLine:SetHeight(1); hLine:SetPoint("BOTTOMLEFT"); hLine:SetPoint("BOTTOMRIGHT")
    hLine:SetColorTexture(unpack(AltTracker.C.SEP))

    -- 1px vertical separator between frozen name col and scrollable header ONLY.
    -- Anchored to frozenHeader bounds so it never extends into the body area.
    local sep=frame:CreateTexture(nil,"OVERLAY"); sep:SetWidth(1)
    sep:SetPoint("TOPLEFT",   frozenHeader,"TOPLEFT",  0, 0)
    sep:SetPoint("BOTTOMLEFT",frozenHeader,"BOTTOMLEFT",0, 0)
    sep:SetColorTexture(unpack(AltTracker.C.SEP))

    -- Sidebar right border (1px full-height, starts below title bar)
    local sbBorder=frame:CreateTexture(nil,"OVERLAY"); sbBorder:SetWidth(1)
    sbBorder:SetPoint("TOPLEFT",frame,"TOPLEFT",SIDEBAR_WIDTH,-TITLE_H)
    sbBorder:SetPoint("BOTTOMLEFT",frame,"BOTTOMLEFT",SIDEBAR_WIDTH,0)
    sbBorder:SetColorTexture(0, 0, 0, 1)

    --------------------------------------------------------
    -- Frozen body scroll
    --------------------------------------------------------

    frozenScroll=CreateFrame("ScrollFrame",nil,frame)
    frozenScroll:SetPoint("TOPLEFT",frame,"TOPLEFT",SIDEBAR_WIDTH,-BodyTopY())
    frozenScroll:SetPoint("BOTTOMLEFT",frame,"BOTTOMLEFT",SIDEBAR_WIDTH,36)
    frozenScroll:SetWidth(FROZEN_WIDTH); frozenScroll:SetClipsChildren(true)
    frozenBodyContent=CreateFrame("Frame",nil,frozenScroll)
    frozenBodyContent:SetSize(FROZEN_WIDTH,400)
    frozenScroll:SetScrollChild(frozenBodyContent)

    --------------------------------------------------------
    -- Body scroll
    --------------------------------------------------------

    bodyScroll=CreateFrame("ScrollFrame","AltTrackerBodyScroll",frame,"UIPanelScrollFrameTemplate")
    bodyScroll:SetPoint("TOPLEFT",frame,"TOPLEFT",SIDEBAR_WIDTH+FROZEN_WIDTH,-BodyTopY())
    bodyScroll:SetPoint("BOTTOMRIGHT",frame,"BOTTOMRIGHT",-10,36)
    bodyScroll:EnableMouseWheel(true); bodyScroll:SetClipsChildren(true)
    bodyContent=CreateFrame("Frame",nil,bodyScroll)
    bodyScroll:SetScrollChild(bodyContent)
    bodyScroll:SetScript("OnVerticalScroll",function(self,offset)
        self:SetVerticalScroll(offset); frozenScroll:SetVerticalScroll(offset); UpdateRows()
    end)

    --------------------------------------------------------
    -- Horizontal scrollbar
    --------------------------------------------------------

    hScrollBar=CreateFrame("Slider","AltTrackerHorizontalScroll",frame,"OptionsSliderTemplate")
    hScrollBar:SetOrientation("HORIZONTAL")
    hScrollBar:SetPoint("BOTTOMLEFT",frame,"BOTTOMLEFT",SIDEBAR_WIDTH+4,24)
    hScrollBar:SetPoint("BOTTOMRIGHT",frame,"BOTTOMRIGHT",-4,24)
    hScrollBar:SetHeight(10); hScrollBar:SetMinMaxValues(0,0); hScrollBar:SetValueStep(20)
    -- The OptionsSliderTemplate auto-creates "Low"/"High" font strings anchored
    -- to the slider corners. They're meaningless for a horizontal scroll
    -- position (the thumb itself shows where you are), and they were leaking
    -- into the totals bar area at smaller scales / wider sections. Kill them.
    if hScrollBar.Low  then hScrollBar.Low:Hide();  hScrollBar.Low:SetText("")  end
    if hScrollBar.High then hScrollBar.High:Hide(); hScrollBar.High:SetText("") end
    hScrollBar:SetScript("OnValueChanged",function(self,value)
        bodyScroll:SetHorizontalScroll(value); headerScroll:SetHorizontalScroll(value)
    end)

    --------------------------------------------------------
    -- Mouse wheel
    --------------------------------------------------------

    bodyScroll:SetScript("OnMouseWheel",function(self,delta)
        if IsShiftKeyDown() then
            local maxH=math.max(0,GetScrollableWidth()-(self:GetWidth()+20))
            local new=math.max(0,math.min(headerScroll:GetHorizontalScroll()-delta*40,maxH))
            headerScroll:SetHorizontalScroll(new); self:SetHorizontalScroll(new); hScrollBar:SetValue(new)
        else
            local contentH=#displayList*ROW_HEIGHT; local viewH=self:GetHeight()
            local maxScroll=math.max(0,contentH-viewH)
            if maxScroll==0 then return end
            local newOffset=math.max(0,math.min(self:GetVerticalScroll()-delta*40,maxScroll))
            if newOffset==self:GetVerticalScroll() then return end
            self:SetVerticalScroll(newOffset); frozenScroll:SetVerticalScroll(newOffset); UpdateRows()
        end
    end)

    -- Build initial headers and activate first section
    BuildHeaders()
    SwitchSection(SECTIONS[1])

    -- Re-apply accent colours whenever the user changes theme.
    -- We must NOT call SwitchSection here — if the active section is a
    -- plugin/Options, SwitchSection calls OnDeactivate which hides the
    -- active panel.  Instead, directly update only the accent-sensitive
    -- elements: sidebar button stripe/label colors and sort arrows.
    AltTracker.RegisterThemeCallback(function()
        local ar, ag, ab = AltTracker.GetAccentRGB()
        for _, btn in ipairs(sidebarBtns) do
            if btn.sectionId == activeSection.id then
                btn.lbl:SetTextColor(ar, ag, ab)
                if btn.accentStripe then
                    btn.accentStripe:SetColorTexture(ar, ag, ab, 1)
                end
                if btn.icon then btn.icon:SetAlpha(1.0) end
            else
                btn.lbl:SetTextColor(unpack(AltTracker.C.TEXT_DIM))
                if btn.icon then btn.icon:SetAlpha(0.65) end
            end
        end
        UpdateSortArrows()
        UpdateTotalsBar()
    end)

    --------------------------------------------------------
    -- Expose key sub-frames on the main frame object so that
    -- plugins (e.g. AltTrackerProfessions) can hide/show the
    -- normal content area when they take over the display.
    --------------------------------------------------------
    frame.bodyScroll   = bodyScroll
    frame.frozenScroll = frozenScroll
    frame.headerScroll = headerScroll
    frame.frozenHeader = frozenHeader
    frame.hScrollBar   = hScrollBar
    frame.totalsBar    = totalsBar

    frame:Hide()
end

------------------------------------------------------------
-- Public API
------------------------------------------------------------

local function Refresh()
    BuildDisplayList()
    local needed=CountVisibleRows()
    EnsureRows(needed)
    UpdateScroll()
    UpdateRows()
    UpdateTotalsBar()
    -- Refresh fires whenever data changes (login, scan finish, alt added).
    -- Snap the frame so it grows/shrinks with the visible row count rather
    -- than leaving leftover dead space below the last row.
    ResizeFrameToContent()
end

function AltTracker.ShowSheet()
    CreateFrameIfNeeded()
    if frame:IsShown() then frame:Hide(); return end
    -- Don't reset to FRAME_W/FRAME_H here — that was the bug that left an
    -- oversized container around the grid. Refresh() calls
    -- ResizeFrameToContent which sizes the frame to match the data exactly.
    frame:Show(); Refresh()
end

function AltTracker.RefreshSheet()
    if frame and frame:IsShown() then Refresh() end
end

function AltTracker.EnsureSheetVisible()
    CreateFrameIfNeeded()
    if not frame:IsShown() then frame:Show(); Refresh() end
end

function AltTracker.ToggleRealm(realm)
    collapsed[realm]=not collapsed[realm]
    BuildDisplayList(); UpdateScroll(); UpdateRows(); UpdateTotalsBar()
    ResizeFrameToContent()
end