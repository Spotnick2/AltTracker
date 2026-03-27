AltTracker = AltTracker or {}

------------------------------------------------------------
-- Layout constants
------------------------------------------------------------

local ROW_HEIGHT    = 22
local HEADER_HEIGHT = 36     -- default; sections can override via headerHeight
local SIDEBAR_WIDTH = 165
local FRAME_W       = 1300
local FRAME_H       = 620
local currentHeaderHeight = HEADER_HEIGHT

-- No title bar — header starts near the top
local HEADER_TOP_Y  = 12
local BODY_TOP_Y    = HEADER_TOP_Y + HEADER_HEIGHT + 2

------------------------------------------------------------
-- Section definitions
-- Each section lists exactly which column fields to show
-- (excluding the frozen Name column which is always shown).
------------------------------------------------------------

local SECTIONS = {
    {
        id    = "summary",
        label = "Account Summary",
        icon  = "Interface\\Icons\\INV_Misc_Note_05",
        fields = {
            "class","spec","race","level","ilvl",
            "guild","restPercent","money","lastUpdate",
        },
    },
    {
        id    = "gear",
        label = "Gear Progression",
        icon  = "Interface\\Icons\\INV_Sword_04",
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
        icon  = "Interface\\Icons\\Trade_Alchemy",
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
        icon  = "Interface\\Icons\\INV_Misc_Token_ArgentDawn",
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
local hideLow     = true
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
    local allChars = {}
    for _, char in next, store do
        if type(char)=="table" and char.name then
            if not hideLow or (char.level or 0)>=58 then
                table.insert(allChars, char)
            end
        end
    end
    table.sort(allChars, function(a,b)
        local v1=a[sortColumn]; if v1==nil then v1="" end
        local v2=b[sortColumn]; if v2==nil then v2="" end
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
            totalLevel=totalLevel+(c.level or 0); totalGold=totalGold+(c.money or 0)
            totalChars=totalChars+1
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
    totalsBar.left:SetText("|cffaaaaaa"..totalChars.." characters|r   |cffaaaaaa"..totalLevel.." total levels|r")
    totalsBar.right:SetText("|cffaaaaaa"..math.floor(totalGold/10000)..GOLD_ICON_SM.." total gold|r")
end

local function UpdateScroll()
    local totalH=#displayList*ROW_HEIGHT
    bodyContent:SetSize(GetScrollableWidth(), math.max(totalH, bodyScroll:GetHeight()))
    frozenBodyContent:SetSize(FROZEN_WIDTH, math.max(totalH, frozenScroll:GetHeight()))
    local maxH=math.max(0, GetScrollableWidth()-(bodyScroll:GetWidth()+20))
    hScrollBar:SetMinMaxValues(0,maxH)
    hScrollBar:SetValue(0)
    -- Hide scrollbar when everything fits horizontally
    if maxH <= 0 then hScrollBar:Hide() else hScrollBar:Show() end
    headerScroll:SetHorizontalScroll(0)
    bodyScroll:SetHorizontalScroll(0)
    bodyScroll:SetVerticalScroll(0)
    frozenScroll:SetVerticalScroll(0)
    headerContent:SetSize(GetScrollableWidth(), currentHeaderHeight)
end

------------------------------------------------------------
-- Sort arrows
------------------------------------------------------------

local function UpdateSortArrows()
    for _, btn in ipairs(headerButtons) do
        if btn.field==sortColumn then
            if btn.arrow then btn.arrow:Show()
                btn.arrow:SetTexCoord(0,1, sortAsc and 0 or 1, sortAsc and 1 or 0)
            end
            if btn.iconTex then btn.iconTex:SetVertexColor(1,0.82,0)
            else btn.label:SetTextColor(1,0.82,0) end
        else
            if btn.arrow then btn.arrow:Hide() end
            if btn.iconTex then btn.iconTex:SetVertexColor(1,1,1)
            else btn.label:SetTextColor(0.9,0.9,0.9) end
        end
    end
end

------------------------------------------------------------
-- Header construction
------------------------------------------------------------

local COL_TOOLTIPS = {
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
                lbl:SetTextColor(1,0.82,0)
                GameTooltip:SetOwner(btn,"ANCHOR_BOTTOM"); GameTooltip:ClearLines()
                GameTooltip:AddLine(col.label,1,1,1)
                if col.type=="repCombined" then GameTooltip:AddLine("|cffaaaaaa(shows whichever is active)|r",1,1,1) end
                GameTooltip:AddLine("Sort by "..col.label,0.7,0.7,0.7); GameTooltip:Show()
            end)
            btn:SetScript("OnLeave",function()
                if sortColumn~=col.field then lbl:SetTextColor(0.9,0.9,0.9) end
                GameTooltip:Hide()
            end)
        elseif col.profIcon or col.slotIcon or col.repIcon then
            local iconPath = col.profIcon or col.slotIcon or col.repIcon
            local sz=math.min(currentHeaderHeight-4,col.width-2)
            local tex=btn:CreateTexture(nil,"OVERLAY")
            tex:SetSize(sz,sz); tex:SetPoint("CENTER",btn,"CENTER",0,0); tex:SetTexture(iconPath)
            btn.label=btn:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall"); btn.label:SetText("")
            btn.iconTex=tex
            btn:SetScript("OnClick",function()
                if sortColumn==col.field then sortAsc=not sortAsc
                else sortColumn=col.field; sortAsc=false end
                UpdateSortArrows(); BuildDisplayList(); UpdateScroll(); UpdateRows(); UpdateTotalsBar()
            end)
            btn:SetScript("OnEnter",function()
                tex:SetVertexColor(1,0.82,0)
                GameTooltip:SetOwner(btn,"ANCHOR_BOTTOM"); GameTooltip:ClearLines()
                GameTooltip:AddLine(col.label,1,1,1)
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
                lbl:SetTextColor(1,0.82,0)
                GameTooltip:SetOwner(btn,"ANCHOR_BOTTOM"); GameTooltip:ClearLines()
                GameTooltip:AddLine(col.label,1,1,1)
                GameTooltip:AddLine("Sort by "..col.label,0.7,0.7,0.7); GameTooltip:Show()
            end)
            btn:SetScript("OnLeave",function()
                if sortColumn~=col.field then lbl:SetTextColor(0.9,0.9,0.9) end
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
                lbl:SetTextColor(1,0.82,0)
                local tip=COL_TOOLTIPS[col.field]
                if tip then
                    GameTooltip:SetOwner(btn,"ANCHOR_BOTTOM"); GameTooltip:ClearLines()
                    GameTooltip:AddLine(tip,1,1,1); GameTooltip:AddLine("Sort by "..tip,0.7,0.7,0.7); GameTooltip:Show()
                end
            end)
            btn:SetScript("OnLeave",function()
                if sortColumn~=col.field then lbl:SetTextColor(0.9,0.9,0.9) end
                GameTooltip:Hide()
            end)
        end

        table.insert(headerButtons,btn)
        if i<#scrollableCols then
            local div=headerContent:CreateTexture(nil,"OVERLAY")
            div:SetSize(1,currentHeaderHeight); div:SetPoint("LEFT",x+col.width+math.floor(padding/2),0)
            div:SetColorTexture(0.35,0.35,0.45,1)
            table.insert(headerDividers, div)
        end
        x=x+col.width+padding
    end
    UpdateSortArrows()
end

------------------------------------------------------------
-- Section switching
------------------------------------------------------------

local function AdjustHeaderHeight(h)
    currentHeaderHeight = h
    local bodyY = HEADER_TOP_Y + h + 2
    if frozenHeader then frozenHeader:SetHeight(h) end
    if headerScroll then headerScroll:SetHeight(h) end
    if headerContent then headerContent:SetHeight(h) end
    -- Reposition body scroll frames
    if frozenScroll then
        frozenScroll:SetPoint("TOPLEFT", frame, "TOPLEFT", SIDEBAR_WIDTH, -bodyY)
    end
    if bodyScroll then
        bodyScroll:SetPoint("TOPLEFT", frame, "TOPLEFT", SIDEBAR_WIDTH + FROZEN_WIDTH, -bodyY)
    end
end

local function SwitchSection(section)
    activeSection = section

    -- Adjust header height for this section
    AdjustHeaderHeight(section.headerHeight or HEADER_HEIGHT)

    -- Highlight active sidebar button
    for _, btn in ipairs(sidebarBtns) do
        if btn.sectionId == section.id then
            btn:SetBackdropColor(0.20,0.20,0.35,1)
            btn.lbl:SetTextColor(1,0.82,0)
        else
            btn:SetBackdropColor(0.08,0.08,0.14,1)
            btn.lbl:SetTextColor(0.75,0.75,0.75)
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
end

------------------------------------------------------------
-- Main frame
------------------------------------------------------------

local function CreateFrameIfNeeded()
    if frame then return end

    ComputeFrozenWidth()
    BuildScrollableColsForSection(activeSection)

    frame=CreateFrame("Frame","AltTrackerSheet",UIParent,"BackdropTemplate")
    frame:SetSize(FRAME_W, FRAME_H)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("DIALOG"); frame:SetToplevel(true)
    frame:SetBackdrop({
        bgFile="Interface/Tooltips/UI-Tooltip-Background",
        edgeFile="Interface/DialogFrame/UI-DialogBox-Border",
        tile=true,tileSize=16,edgeSize=32,
        insets={left=8,right=8,top=8,bottom=8},
    })
    frame:SetBackdropColor(0.05,0.05,0.08,0.97)
    frame:SetMovable(true); frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart",frame.StartMoving)
    frame:SetScript("OnDragStop",frame.StopMovingOrSizing)
    tinsert(UISpecialFrames,"AltTrackerSheet")

    -- Close button (top-right, raised above header scroll)
    local close=CreateFrame("Button",nil,frame,"UIPanelCloseButton")
    close:SetPoint("TOPRIGHT",-5,-5)
    close:SetFrameLevel(frame:GetFrameLevel()+10)

    --------------------------------------------------------
    -- Left sidebar
    --------------------------------------------------------

    local sidebar=CreateFrame("Frame",nil,frame,"BackdropTemplate")
    sidebar:SetPoint("TOPLEFT",frame,"TOPLEFT",10,-10)
    sidebar:SetPoint("BOTTOMLEFT",frame,"BOTTOMLEFT",10,10)
    sidebar:SetWidth(SIDEBAR_WIDTH-8)
    sidebar:SetBackdrop({
        bgFile="Interface/Tooltips/UI-Tooltip-Background",
        edgeFile="Interface/Buttons/WHITE8X8",
        tile=true,tileSize=8,edgeSize=1,
    })
    sidebar:SetBackdropColor(0.07,0.07,0.12,0.95)
    sidebar:SetBackdropBorderColor(0.25,0.25,0.35,1)

    -- Sidebar title
    local sbTitle=sidebar:CreateFontString(nil,"OVERLAY","GameFontNormal")
    sbTitle:SetPoint("TOPLEFT",8,-10)
    sbTitle:SetText("|cff00ccffAltTracker|r")

    local sbDivider=sidebar:CreateTexture(nil,"ARTWORK")
    sbDivider:SetHeight(1)
    sbDivider:SetPoint("TOPLEFT",sidebar,"TOPLEFT",4,-26)
    sbDivider:SetPoint("TOPRIGHT",sidebar,"TOPRIGHT",-4,-26)
    sbDivider:SetColorTexture(0.3,0.3,0.45,1)

    -- Section buttons
    local btnY = -34
    for _, section in ipairs(SECTIONS) do
        local btn=CreateFrame("Button",nil,sidebar,"BackdropTemplate")
        btn:SetHeight(28)
        btn:SetPoint("TOPLEFT",sidebar,"TOPLEFT",4,btnY)
        btn:SetPoint("TOPRIGHT",sidebar,"TOPRIGHT",-4,btnY)
        btn:SetBackdrop({
            bgFile="Interface/Tooltips/UI-Tooltip-Background",
            edgeFile="Interface/Buttons/WHITE8X8",
            tile=true,tileSize=8,edgeSize=1,
        })
        btn:SetBackdropColor(0.08,0.08,0.14,1)
        btn:SetBackdropBorderColor(0.2,0.2,0.3,1)
        btn.sectionId = section.id

        -- Icon
        local icon=btn:CreateTexture(nil,"ARTWORK")
        icon:SetSize(18,18); icon:SetPoint("LEFT",6,0)
        icon:SetTexture(section.icon)
        icon:SetTexCoord(0.08,0.92,0.08,0.92)

        -- Label
        local lbl=btn:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
        lbl:SetPoint("LEFT",28,0); lbl:SetPoint("RIGHT",-4,0)
        lbl:SetJustifyH("LEFT"); lbl:SetText(section.label)
        lbl:SetTextColor(0.75,0.75,0.75)
        btn.lbl=lbl; btn.icon=icon

        btn:SetScript("OnClick",function() SwitchSection(section) end)
        btn:SetScript("OnEnter",function()
            if activeSection.id~=section.id then
                btn:SetBackdropColor(0.13,0.13,0.22,1)
                lbl:SetTextColor(1,1,1)
            end
        end)
        btn:SetScript("OnLeave",function()
            if activeSection.id~=section.id then
                btn:SetBackdropColor(0.08,0.08,0.14,1)
                lbl:SetTextColor(0.75,0.75,0.75)
            end
        end)

        table.insert(sidebarBtns,btn)
        btnY = btnY - 32
    end

    -- Bottom divider above checkbox
    local sbDiv2=sidebar:CreateTexture(nil,"ARTWORK")
    sbDiv2:SetHeight(1)
    sbDiv2:SetPoint("BOTTOMLEFT",sidebar,"BOTTOMLEFT",4,40)
    sbDiv2:SetPoint("BOTTOMRIGHT",sidebar,"BOTTOMRIGHT",-4,40)
    sbDiv2:SetColorTexture(0.3,0.3,0.45,1)

    -- "Hide below 58" checkbox at bottom of sidebar
    local check=CreateFrame("CheckButton",nil,sidebar,"UICheckButtonTemplate")
    check:SetPoint("BOTTOMLEFT",sidebar,"BOTTOMLEFT",2,12)
    check:SetChecked(true)
    check.text:SetText("Hide below 58")
    check:SetScript("OnClick",function(self)
        hideLow=self:GetChecked()
        BuildDisplayList(); UpdateScroll(); UpdateRows(); UpdateTotalsBar()
    end)

    --------------------------------------------------------
    -- Totals bar
    --------------------------------------------------------

    totalsBar=CreateFrame("Frame",nil,frame,"BackdropTemplate")
    totalsBar:SetPoint("BOTTOMLEFT",frame,"BOTTOMLEFT",SIDEBAR_WIDTH,36)
    totalsBar:SetPoint("BOTTOMRIGHT",frame,"BOTTOMRIGHT",-10,36)
    totalsBar:SetHeight(20)
    totalsBar:SetBackdrop({bgFile="Interface/Tooltips/UI-Tooltip-Background",tile=true,tileSize=8})
    totalsBar:SetBackdropColor(0.08,0.08,0.14,0.95)
    local totLine=frame:CreateTexture(nil,"OVERLAY"); totLine:SetHeight(1)
    totLine:SetPoint("BOTTOMLEFT",totalsBar,"TOPLEFT",0,0)
    totLine:SetPoint("BOTTOMRIGHT",totalsBar,"TOPRIGHT",0,0)
    totLine:SetColorTexture(0.30,0.30,0.45,1)
    totalsBar.left=totalsBar:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
    totalsBar.left:SetPoint("LEFT",12,0)
    totalsBar.right=totalsBar:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
    totalsBar.right:SetPoint("RIGHT",-12,0); totalsBar.right:SetJustifyH("RIGHT")

    --------------------------------------------------------
    -- Frozen header (Name column)
    --------------------------------------------------------

    frozenHeader=CreateFrame("Frame",nil,frame)
    frozenHeader:SetPoint("TOPLEFT",frame,"TOPLEFT",SIDEBAR_WIDTH,-HEADER_TOP_Y)
    frozenHeader:SetSize(FROZEN_WIDTH,HEADER_HEIGHT)
    local fhBg=frozenHeader:CreateTexture(nil,"BACKGROUND")
    fhBg:SetAllPoints(); fhBg:SetColorTexture(0.10,0.10,0.18,1)
    local fhLine=frozenHeader:CreateTexture(nil,"OVERLAY")
    fhLine:SetHeight(1); fhLine:SetPoint("BOTTOMLEFT"); fhLine:SetPoint("BOTTOMRIGHT")
    fhLine:SetColorTexture(0.40,0.40,0.55,1)

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
        btn:SetScript("OnEnter",function() lbl:SetTextColor(1,0.82,0) end)
        btn:SetScript("OnLeave",function()
            if sortColumn~=col.field then lbl:SetTextColor(0.9,0.9,0.9) end
        end)
        table.insert(headerButtons,btn)
    end

    --------------------------------------------------------
    -- Scrollable header
    --------------------------------------------------------

    headerScroll=CreateFrame("ScrollFrame",nil,frame)
    headerScroll:SetPoint("TOPLEFT",frame,"TOPLEFT",SIDEBAR_WIDTH+FROZEN_WIDTH,-HEADER_TOP_Y)
    headerScroll:SetPoint("TOPRIGHT",frame,"TOPRIGHT",-32,-HEADER_TOP_Y)
    headerScroll:SetHeight(HEADER_HEIGHT)
    headerContent=CreateFrame("Frame",nil,headerScroll)
    headerContent:SetSize(GetScrollableWidth(),HEADER_HEIGHT)
    headerScroll:SetScrollChild(headerContent)
    local hBg=headerContent:CreateTexture(nil,"BACKGROUND")
    hBg:SetAllPoints(); hBg:SetColorTexture(0.10,0.10,0.18,1)
    local hLine=headerContent:CreateTexture(nil,"OVERLAY")
    hLine:SetHeight(1); hLine:SetPoint("BOTTOMLEFT"); hLine:SetPoint("BOTTOMRIGHT")
    hLine:SetColorTexture(0.40,0.40,0.55,1)

    -- Vertical separator between frozen and scrollable
    local sep=frame:CreateTexture(nil,"OVERLAY"); sep:SetWidth(2)
    sep:SetPoint("TOPLEFT",frame,"TOPLEFT",SIDEBAR_WIDTH+FROZEN_WIDTH,-HEADER_TOP_Y)
    sep:SetPoint("BOTTOMLEFT",frame,"BOTTOMLEFT",SIDEBAR_WIDTH+FROZEN_WIDTH,58)
    sep:SetColorTexture(0.45,0.45,0.65,1)

    -- Sidebar right border
    local sbBorder=frame:CreateTexture(nil,"OVERLAY"); sbBorder:SetWidth(1)
    sbBorder:SetPoint("TOPLEFT",frame,"TOPLEFT",SIDEBAR_WIDTH,-10)
    sbBorder:SetPoint("BOTTOMLEFT",frame,"BOTTOMLEFT",SIDEBAR_WIDTH,10)
    sbBorder:SetColorTexture(0.25,0.25,0.40,1)

    --------------------------------------------------------
    -- Frozen body scroll
    --------------------------------------------------------

    frozenScroll=CreateFrame("ScrollFrame",nil,frame)
    frozenScroll:SetPoint("TOPLEFT",frame,"TOPLEFT",SIDEBAR_WIDTH,-BODY_TOP_Y)
    frozenScroll:SetPoint("BOTTOMLEFT",frame,"BOTTOMLEFT",SIDEBAR_WIDTH,58)
    frozenScroll:SetWidth(FROZEN_WIDTH); frozenScroll:SetClipsChildren(true)
    frozenBodyContent=CreateFrame("Frame",nil,frozenScroll)
    frozenBodyContent:SetSize(FROZEN_WIDTH,400)
    frozenScroll:SetScrollChild(frozenBodyContent)

    --------------------------------------------------------
    -- Body scroll
    --------------------------------------------------------

    bodyScroll=CreateFrame("ScrollFrame","AltTrackerBodyScroll",frame,"UIPanelScrollFrameTemplate")
    bodyScroll:SetPoint("TOPLEFT",frame,"TOPLEFT",SIDEBAR_WIDTH+FROZEN_WIDTH,-BODY_TOP_Y)
    bodyScroll:SetPoint("BOTTOMRIGHT",frame,"BOTTOMRIGHT",-10,58)
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
    hScrollBar:SetPoint("BOTTOMLEFT",frame,"BOTTOMLEFT",SIDEBAR_WIDTH+20,15)
    hScrollBar:SetPoint("BOTTOMRIGHT",frame,"BOTTOMRIGHT",-30,15)
    hScrollBar:SetHeight(16); hScrollBar:SetMinMaxValues(0,0); hScrollBar:SetValueStep(20)
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
end

function AltTracker.ShowSheet()
    CreateFrameIfNeeded()
    if frame:IsShown() then frame:Hide(); return end
    -- Ensure frame uses current dimensions (in case code was updated after initial creation)
    frame:SetSize(FRAME_W, FRAME_H)
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
end