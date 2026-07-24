------------------------------------------------------------
-- AltTrackerWarband — consolidated cross-alt bag + bank inventory (P3).
--
-- A single "Warband bank"-style grid of every item across all tracked
-- characters (bags + bank), each unique item shown once as a stack with its
-- total count, grouped by item type, with a search that dims non-matches in
-- place and a per-item tooltip listing which alt holds how many.
--
-- We capture + sync our OWN data (not another addon's SavedVariables) so the
-- other account's characters merge in over AltTracker's transport.
--
-- Persistence (plugin-owned; kept out of the core AltTrackerDB record):
--   AltTrackerWarbandDB[guid] = {
--       bags = { [itemID] = count },   -- summed across bags 0..4
--       bank = { [itemID] = count },   -- summed across bank -1, 5..11
--       bagsStamp, bankStamp,          -- when each section last changed
--       stamp = max(bagsStamp,bankStamp)  -- drives the delta watermark
--   }
-- bags and bank are SEPARATE maps: bags refresh live on BAG_UPDATE, but the
-- bank is only readable while its frame is open, so a bag rescan must never
-- clobber the (intentionally stale) bank snapshot.
------------------------------------------------------------

AltTrackerWarbandDB = AltTrackerWarbandDB or {}

local ADDON_ID     = "warband"
local BLOB_VERSION = "v1"

local BAG_IDS   = { 0, 1, 2, 3, 4 }
local BANK_IDS  = { -1, 5, 6, 7, 8, 9, 10, 11 }
local MAIN_BANK = -1
local BANK_STALE = 7 * 86400   -- flag a bank snapshot as "may be out of date" past this

local AT_WB = { cells = {}, headers = {}, isActive = false, search = "" }

-- Bank-session state for the transactional bank scan.
local isBankOpen  = false
local bankGen     = 0
local bagsPending = false
local bankPending = false

-- Async item metadata we've asked the client to load (re-render on arrival).
local requestedIDs = {}

local function Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cff00ccff[AltTracker Warband]|r " .. msg)
end

------------------------------------------------------------
-- Container API shim — the classic flat globals and the modern C_Container
-- namespace both exist across builds; detect the return SHAPE at runtime
-- rather than assuming a struct just because C_Container is present.
------------------------------------------------------------

local CGetNumSlots = (C_Container and C_Container.GetContainerNumSlots) or _G.GetContainerNumSlots
local CGetItemID   = (C_Container and C_Container.GetContainerItemID)   or _G.GetContainerItemID
local CGetItemLink = (C_Container and C_Container.GetContainerItemLink) or _G.GetContainerItemLink
local CGetItemInfo = (C_Container and C_Container.GetContainerItemInfo) or _G.GetContainerItemInfo

local function ItemIDFromLink(link)
    if type(link) ~= "string" then return nil end
    return tonumber(link:match("item:(%d+)"))
end

-- Read one slot. Returns:
--   itemID, count   for an occupied, well-formed slot
--   nil             for an empty slot
--   nil, "bad"      occupied but the count is unreadable (caller aborts the scan)
local function ReadSlot(bag, slot)
    local itemID
    if CGetItemID then itemID = CGetItemID(bag, slot) end
    if not itemID or itemID == 0 then
        itemID = ItemIDFromLink(CGetItemLink and CGetItemLink(bag, slot))
    end
    if not itemID or itemID == 0 then return nil end

    local count
    if CGetItemInfo then
        local a, b = CGetItemInfo(bag, slot)
        count = (type(a) == "table") and a.stackCount or b   -- struct vs positional
    end
    count = tonumber(count)
    if not count or count < 1 then return nil, "bad" end
    return itemID, count
end

-- Sum a set of containers into { [itemID] = count }. Returns nil if any
-- occupied slot is unreadable, so a mid-transition scan aborts instead of
-- recording garbage.
local function ScanContainerSet(ids)
    if not CGetNumSlots then return nil end
    local map = {}
    for _, bag in ipairs(ids) do
        local n = CGetNumSlots(bag)
        if n and n > 0 then
            for slot = 1, n do
                local id, count = ReadSlot(bag, slot)
                if id then
                    map[id] = (map[id] or 0) + count
                elseif count == "bad" then
                    return nil
                end
            end
        end
    end
    return map
end

local function mapsEqual(a, b)
    if a == b then return true end
    if not a or not b then return false end
    for k, v in pairs(a) do if b[k] ~= v then return false end end
    for k in pairs(b) do if a[k] == nil then return false end end
    return true
end

local function GetDB(guid)
    AltTrackerWarbandDB[guid] = AltTrackerWarbandDB[guid] or {}
    return AltTrackerWarbandDB[guid]
end

-- Commit a freshly-built section map for the current player, but only if it
-- actually changed — otherwise cosmetic BAG_UPDATEs would churn the sync.
local function ApplyScan(sectionKey, stampKey, newMap)
    if not newMap then return end
    local guid = UnitGUID("player")
    if not guid then return end
    local db = GetDB(guid)
    if mapsEqual(db[sectionKey], newMap) then return end

    db[sectionKey] = newMap
    db[stampKey]   = time()
    db.stamp       = math.max(db.bagsStamp or 0, db.bankStamp or 0)
    if AltTracker.TouchCharacter then AltTracker.TouchCharacter(guid) end
    if AT_WB.isActive and AT_WB.Refresh then AT_WB.Refresh() end
end

local function ScanBags()
    ApplyScan("bags", "bagsStamp", ScanContainerSet(BAG_IDS))
end

-- Transactional bank scan. A genuinely emptied bank MUST be allowed to replace
-- a non-empty snapshot, so we never gate on "candidate is empty". The bank is
-- only readable while open, so we require isBankOpen and a plausible main-bank
-- slot count; a scan whose bank session ended before it ran is blocked at
-- SCHEDULE time via the generation counter (see ScheduleBank), not here — an
-- in-flight synchronous scan can't have its own generation change under it.
local function ScanBank()
    if not isBankOpen then return end
    local mainN = CGetNumSlots and CGetNumSlots(MAIN_BANK)
    if not mainN or mainN <= 0 then return end   -- slots not ready yet
    local candidate = ScanContainerSet(BANK_IDS)
    if not candidate then return end              -- malformed mid-transition: abort
    ApplyScan("bank", "bankStamp", candidate)
end

local function ScheduleBags()
    if bagsPending then return end
    bagsPending = true
    C_Timer.After(1, function() bagsPending = false; ScanBags() end)
end

-- Capture the bank generation at schedule time; if the bank closed (or
-- closed-then-reopened) before this fires, the generation no longer matches
-- and we drop the stale scan instead of committing it over a good snapshot.
local function ScheduleBank()
    if bankPending then return end
    bankPending = true
    local gen = bankGen
    C_Timer.After(1, function()
        bankPending = false
        if gen == bankGen and isBankOpen then ScanBank() end
    end)
end

------------------------------------------------------------
-- Event routing
------------------------------------------------------------

local function OnBagUpdate(bag)
    bag = tonumber(bag)
    if bag and (bag == MAIN_BANK or (bag >= 5 and bag <= 11)) then
        if isBankOpen then ScheduleBank() end   -- bank-bag change while open
        return
    end
    ScheduleBags()   -- bags 0..4 (or a nil/unspecified bag)
end

local function OnBankOpened()
    isBankOpen = true
    bankGen = bankGen + 1
    ScanBank()          -- immediate...
    ScheduleBank()      -- ...plus a follow-up in case slot counts aren't ready yet
end

local function OnBankClosed()
    isBankOpen = false
    bankGen = bankGen + 1   -- invalidate any in-flight scheduled scan
end

------------------------------------------------------------
-- Sync — compact, single-line, no "\n". Only itemID+count integers ride the
-- wire (item links are reconstructed client-side, like the core gear scan).
--   v1|s=<stamp>|kt=<bankStamp>|b=id,count;id,count|k=id,count;...
------------------------------------------------------------

local function EncodeMap(map)
    local ids = {}
    for id in pairs(map or {}) do ids[#ids + 1] = id end
    table.sort(ids)   -- deterministic output for tests/diffs/compression
    local parts = {}
    for _, id in ipairs(ids) do parts[#parts + 1] = id .. "," .. map[id] end
    return table.concat(parts, ";")
end

-- Parse "id,count;id,count" into { [id]=count }. Returns nil on any malformed
-- entry so a corrupt blob cannot half-replace good data.
local function ParseMap(s)
    local map = {}
    if not s or s == "" then return map end
    for pair in s:gmatch("([^;]+)") do
        local id, count = pair:match("^(%d+),(%d+)$")
        id, count = tonumber(id), tonumber(count)
        if not id or not count or id < 1 or count < 1 then return nil end
        map[id] = count
    end
    return map
end

local function SerializePlayer(guid, sinceTS)
    local db = AltTrackerWarbandDB[guid]
    if not db then return "" end
    local stamp = db.stamp or 0
    -- Strict "<": the core delta includes a char at lastUpdate >= sinceTS
    -- (resend-on-equality is idempotent), so skipping at equality would drop a
    -- same-second change permanently once the watermark reaches it.
    if sinceTS and sinceTS > 0 and stamp < sinceTS then return "" end
    return BLOB_VERSION
        .. "|s=" .. stamp
        .. "|kt=" .. (db.bankStamp or 0)
        .. "|b=" .. EncodeMap(db.bags)
        .. "|k=" .. EncodeMap(db.bank)
end

local function DeserializePlayer(guid, blob)
    if not guid or not blob or blob == "" then return end
    local ver, rest = blob:match("^(v%d+)|(.+)$")
    if ver ~= BLOB_VERSION then return end   -- unknown version: ignore, don't wipe

    local incomingStamp = tonumber(rest:match("s=(%d+)"))
    if not incomingStamp then return end
    -- Stale-reject: never let an older (or duplicate) relayed record roll back
    -- fresher local inventory. Covers the "Core applies plugin blobs before it
    -- validates/accepts the character record" ordering gap for our threat model.
    local existing = AltTrackerWarbandDB[guid]
    if existing and (existing.stamp or 0) >= incomingStamp then return end

    local bags = ParseMap(rest:match("b=([^|]*)"))
    local bank = ParseMap(rest:match("k=([^|]*)"))
    if not bags or not bank then return end   -- malformed: keep existing good data

    local bankStamp = tonumber(rest:match("kt=(%d+)")) or incomingStamp
    local db = GetDB(guid)
    db.bags = bags
    db.bank = bank
    db.stamp = incomingStamp
    db.bagsStamp = incomingStamp
    db.bankStamp = bankStamp
    if AT_WB.isActive and AT_WB.Refresh then AT_WB.Refresh() end
end

------------------------------------------------------------
-- Read model for the grid: merge every character's bags+bank by itemID.
--   agg[itemID] = { total, holders = { {name,class,realm,bags,bank,bankStamp} } }
------------------------------------------------------------

local function gather()
    AltTrackerDB = AltTrackerDB or {}
    local agg = {}
    for guid, c in pairs(AltTrackerDB) do
        if type(c) == "table" and c.name then
            local wb = AltTrackerWarbandDB[guid]
            if type(wb) == "table" then
                local per = {}
                if wb.bags then
                    for id, n in pairs(wb.bags) do per[id] = { bags = n, bank = 0 } end
                end
                if wb.bank then
                    for id, n in pairs(wb.bank) do
                        per[id] = per[id] or { bags = 0, bank = 0 }
                        per[id].bank = n
                    end
                end
                for id, v in pairs(per) do
                    local a = agg[id]
                    if not a then a = { total = 0, holders = {} }; agg[id] = a end
                    a.total = a.total + v.bags + v.bank
                    a.holders[#a.holders + 1] = {
                        name = c.name, class = c.class, realm = c.realm,
                        bags = v.bags, bank = v.bank, bankStamp = wb.bankStamp,
                    }
                end
            end
        end
    end
    return agg
end

------------------------------------------------------------
-- Display — a scrollable grid grouped by item type. Icon + total count per
-- unique item; hover lists which alt holds how many; search dims non-matches
-- in place (stable layout, so it's a cheap per-cell alpha/desaturate pass).
------------------------------------------------------------

local PAD       = 12
local TITLE_H   = 26
local ICON      = 32
local STRIDE    = 42     -- icon + gutter
local HDR_H     = 22
local GROUP_GAP = 10

-- Item classID -> section label, in display order. Unknown classes fall into "Other".
local CLASS_LABEL = {
    [7] = "Trade Goods", [0] = "Consumables", [3] = "Gems", [2] = "Weapons",
    [4] = "Armor", [9] = "Recipes", [5] = "Reagents", [6] = "Projectiles",
    [11] = "Quivers", [1] = "Containers", [12] = "Quest", [13] = "Keys",
    [15] = "Miscellaneous",
}
local GROUP_ORDER = { 7, 0, 3, 2, 4, 9, 5, 6, 11, 1, 12, 13, 15 }

local panel, scroll, content, titleFS, emptyFS, searchBox

local function fmtCount(n)
    if n >= 1000 then return string.format("%.1fk", n / 1000) end
    return tostring(n)
end

local function RequestMeta(id)
    if requestedIDs[id] then return end
    requestedIDs[id] = true
    if GetItemInfo then GetItemInfo(id) end   -- schedules the async cache load
end

local function DupName(holders, name)
    local c = 0
    for _, h in ipairs(holders) do if h.name == name then c = c + 1 end end
    return c > 1
end

-- Build the tooltip manually with AddLine rather than SetHyperlink + append:
-- a hyperlink'd tooltip re-renders itself from the item link (async item-info
-- callback), which wipes any custom lines appended after it — so the per-alt
-- breakdown, which is the whole point of this view, would vanish. We show a
-- quality-coloured item-name header instead and keep full control of the body.
local function CellOnEnter(self)
    local e = self.entry
    if not e then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:ClearLines()

    local r, g, b = 1, 1, 1
    local qc = e.quality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[e.quality]
    if qc then r, g, b = qc.r, qc.g, qc.b end
    GameTooltip:AddLine(e.name or ("Item " .. e.id), r, g, b)
    GameTooltip:AddDoubleLine("Total across alts", tostring(e.total), 0.7, 0.7, 0.7, 1, 1, 1)
    GameTooltip:AddLine(" ")

    local holders = {}
    for _, h in ipairs(e.holders or {}) do holders[#holders + 1] = h end
    table.sort(holders, function(a, b2) return (a.name or "") < (b2.name or "") end)

    local now = time()
    local stale = false
    for _, h in ipairs(holders) do
        local cc = (h.class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[h.class]) or { r = .9, g = .9, b = .9 }
        local nm = h.name or "?"
        if h.realm and DupName(e.holders, h.name) then nm = nm .. "-" .. h.realm end
        local parts = {}
        if (h.bags or 0) > 0 then parts[#parts + 1] = "Bags " .. h.bags end
        if (h.bank or 0) > 0 then parts[#parts + 1] = "Bank " .. h.bank end
        GameTooltip:AddDoubleLine(nm, table.concat(parts, ", "), cc.r, cc.g, cc.b, 0.85, 0.85, 0.85)
        if (h.bank or 0) > 0 and h.bankStamp and (now - h.bankStamp) > BANK_STALE then stale = true end
    end
    if stale then GameTooltip:AddLine("Bank data may be out of date", .55, .55, .55) end
    GameTooltip:Show()
end

local function hideFrom(pool, from)
    for k = from, #pool do if pool[k] then pool[k]:Hide() end end
end

local function getHeader(i)
    local fs = AT_WB.headers[i]
    if not fs then
        fs = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        fs:SetJustifyH("LEFT")
        fs:SetTextColor(unpack((AltTracker.C and AltTracker.C.TEXT_BRIGHT) or { 1, 1, 1 }))
        AT_WB.headers[i] = fs
    end
    return fs
end

local function getCell(i)
    local cell = AT_WB.cells[i]
    if not cell then
        cell = CreateFrame("Button", nil, content, "BackdropTemplate")
        cell:SetSize(ICON, ICON)
        cell:EnableMouse(true)
        cell:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
        cell.icon = cell:CreateTexture(nil, "ARTWORK")
        cell.icon:SetPoint("TOPLEFT", 1, -1)
        cell.icon:SetPoint("BOTTOMRIGHT", -1, 1)
        cell.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        cell.count = cell:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
        cell.count:SetPoint("BOTTOMRIGHT", -1, 1)
        cell:SetScript("OnEnter", CellOnEnter)
        cell:SetScript("OnLeave", function() GameTooltip:Hide() end)
        AT_WB.cells[i] = cell
    end
    return cell
end

-- Resolve metadata, bucket by item type, sort each bucket by quality then name.
-- Returns an ordered list of { label, items = { entry, ... } }.
local function buildBuckets(agg)
    local buckets = {}
    for id, a in pairs(agg) do
        local icon, classID
        if GetItemInfoInstant then
            local _, _, _, _, ic, cid = GetItemInfoInstant(id)
            icon, classID = ic, cid
        end
        local name, _, quality = nil, nil, nil
        if GetItemInfo then name, _, quality = GetItemInfo(id) end
        if not name then RequestMeta(id) end
        if not icon and GetItemIcon then icon = GetItemIcon(id) end

        local key = CLASS_LABEL[classID or -1] and classID or "other"
        buckets[key] = buckets[key] or {}
        table.insert(buckets[key], {
            id = id, total = a.total, holders = a.holders,
            icon = icon, name = name, quality = quality,
        })
    end

    local groups = {}
    local function pushGroup(key, label)
        local list = buckets[key]
        if list and #list > 0 then
            table.sort(list, function(x, y)
                local qx, qy = x.quality or -1, y.quality or -1
                if qx ~= qy then return qx > qy end
                return (x.name or ("zzz" .. x.id)) < (y.name or ("zzz" .. y.id))
            end)
            groups[#groups + 1] = { label = label, items = list }
        end
    end
    for _, cid in ipairs(GROUP_ORDER) do pushGroup(cid, CLASS_LABEL[cid]) end
    pushGroup("other", "Other")
    return groups
end

local function ApplySearchDim()
    local q = AT_WB.search or ""
    for i = 1, #AT_WB.cells do
        local cell = AT_WB.cells[i]
        if cell:IsShown() then
            local match = (q == "")
            if not match then
                local nm = cell.itemName
                match = nm and nm:lower():find(q, 1, true) and true or false
            end
            cell.icon:SetDesaturated(not match)
            cell:SetAlpha(match and 1 or 0.25)
        end
    end
end
AT_WB.ApplySearchDim = ApplySearchDim

function AT_WB.Refresh()
    if not panel or not panel:IsShown() then return end
    local agg = gather()
    if not next(agg) then
        hideFrom(AT_WB.cells, 1)
        hideFrom(AT_WB.headers, 1)
        emptyFS:Show()
        content:SetHeight(1)
        return
    end
    emptyFS:Hide()

    local groups = buildBuckets(agg)
    local width = scroll:GetWidth()
    if not width or width < 100 then width = 400 end
    local cols = math.max(1, math.floor((width - PAD) / STRIDE))

    local ci, hi, y = 0, 0, 0
    for _, g in ipairs(groups) do
        hi = hi + 1
        local hdr = getHeader(hi)
        hdr:ClearAllPoints()
        hdr:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
        hdr:SetText(g.label .. "  |cff888888(" .. #g.items .. ")|r")
        hdr:Show()
        y = y + HDR_H

        local col = 0
        for _, e in ipairs(g.items) do
            ci = ci + 1
            local cell = getCell(ci)
            cell:ClearAllPoints()
            cell:SetPoint("TOPLEFT", content, "TOPLEFT", col * STRIDE, -y)
            cell.icon:SetTexture(e.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
            cell.count:SetText(e.total > 1 and fmtCount(e.total) or "")
            local qc = e.quality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[e.quality]
            if qc then cell:SetBackdropBorderColor(qc.r, qc.g, qc.b, 1)
            else cell:SetBackdropBorderColor(0.3, 0.3, 0.3, 1) end
            cell.entry = e
            cell.itemName = e.name
            cell:Show()
            col = col + 1
            if col >= cols then col = 0; y = y + STRIDE end
        end
        if col > 0 then y = y + STRIDE end
        y = y + GROUP_GAP
    end

    hideFrom(AT_WB.cells, ci + 1)
    hideFrom(AT_WB.headers, hi + 1)
    content:SetWidth(width)
    content:SetHeight(math.max(y, 1))
    ApplySearchDim()
end

------------------------------------------------------------
-- Panel + activation (mirrors the Instances plugin lifecycle)
------------------------------------------------------------

local function BuildPanel(mainFrame)
    if panel then return end
    local sidebarW = (AltTracker.LAYOUT and AltTracker.LAYOUT.SIDEBAR_WIDTH) or 230
    local titleH   = (AltTracker.LAYOUT and AltTracker.LAYOUT.TITLE_H) or 30

    panel = CreateFrame("Frame", nil, mainFrame, "BackdropTemplate")
    panel:SetPoint("TOPLEFT", mainFrame, "TOPLEFT", sidebarW + 1, -titleH)
    panel:SetPoint("BOTTOMRIGHT", mainFrame, "BOTTOMRIGHT", 0, 1)
    AltTracker.ApplyBGOnly(panel, AltTracker.C.BG_MAIN[1], AltTracker.C.BG_MAIN[2], AltTracker.C.BG_MAIN[3], AltTracker.C.BG_MAIN[4])
    panel:Hide()

    titleFS = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    titleFS:SetPoint("TOPLEFT", panel, "TOPLEFT", PAD, -PAD + 2)
    titleFS:SetText("Warband Inventory")
    titleFS:SetTextColor(unpack(AltTracker.C.TEXT_BRIGHT))

    searchBox = CreateFrame("EditBox", nil, panel, "SearchBoxTemplate")
    searchBox:SetSize(190, 20)
    searchBox:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -PAD, -PAD + 4)
    searchBox:HookScript("OnTextChanged", function(self)
        AT_WB.search = (self:GetText() or ""):lower()
        ApplySearchDim()
    end)

    scroll = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", panel, "TOPLEFT", PAD, -(TITLE_H + 8))
    scroll:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -28, PAD)
    content = CreateFrame("Frame", nil, scroll)
    content:SetSize(1, 1)
    scroll:SetScrollChild(content)

    emptyFS = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    emptyFS:SetPoint("TOPLEFT", panel, "TOPLEFT", PAD, -(TITLE_H + 12))
    emptyFS:SetText("No inventory captured yet. Log in on your alts (and open a bank) to populate this.")
    emptyFS:SetTextColor(unpack(AltTracker.C.TEXT_DIM))
    emptyFS:Hide()
end

local function HookRefresh()
    if AT_WB._refreshHooked or type(AltTracker.RefreshSheet) ~= "function" then return end
    local prev = AltTracker.RefreshSheet
    AltTracker.RefreshSheet = function(...)
        prev(...)
        if AT_WB.isActive then C_Timer.After(0, function() if AT_WB.isActive then AT_WB.Refresh() end end) end
    end
    AT_WB._refreshHooked = true
end

function AT_WB.Activate(mainFrame)
    BuildPanel(mainFrame)
    HookRefresh()
    AT_WB.isActive = true

    if mainFrame.bodyScroll   then mainFrame.bodyScroll:Hide()   end
    if mainFrame.frozenScroll then mainFrame.frozenScroll:Hide() end
    if mainFrame.headerScroll then mainFrame.headerScroll:Hide() end
    if mainFrame.frozenHeader then mainFrame.frozenHeader:Hide() end
    if mainFrame.hScrollBar   then mainFrame.hScrollBar:Hide()   end
    if mainFrame.totalsBar    then mainFrame.totalsBar:Hide()    end

    panel:Show()
    ScanBags()                     -- freshen our own bags on open
    if isBankOpen then ScanBank() end
    AT_WB.Refresh()
end

function AT_WB.Deactivate(mainFrame)
    AT_WB.isActive = false
    if panel then panel:Hide() end
    if mainFrame.bodyScroll   then mainFrame.bodyScroll:Show()   end
    if mainFrame.frozenScroll then mainFrame.frozenScroll:Show() end
    if mainFrame.headerScroll then mainFrame.headerScroll:Show() end
    if mainFrame.frozenHeader then mainFrame.frozenHeader:Show() end
    if mainFrame.hScrollBar   then mainFrame.hScrollBar:Show()   end
    if mainFrame.totalsBar    then mainFrame.totalsBar:Show()    end
end

------------------------------------------------------------
-- Bootstrap + events
------------------------------------------------------------

local function BootstrapPlugin(isOnDemand)
    if not AltTracker or not AltTracker.RegisterPlugin then
        Print("AltTracker not found — make sure it is installed and enabled.")
        return
    end
    AltTracker.RegisterPlugin({
        id            = ADDON_ID,
        label         = "Warband",
        icon          = "Interface\\Icons\\INV_Misc_Bag_08",
        _isPlugin     = true,
        OnActivate    = function(mf) AT_WB.Activate(mf) end,
        OnDeactivate  = function(mf) AT_WB.Deactivate(mf) end,
        OnSerialize   = function(g, s) return SerializePlayer(g, s) end,
        OnDeserialize = function(g, b) DeserializePlayer(g, b) end,
        _test = {
            SerializePlayer = SerializePlayer, DeserializePlayer = DeserializePlayer,
            gather = gather, ScanBags = ScanBags, ScanBank = ScanBank,
            EncodeMap = EncodeMap, ParseMap = ParseMap, mapsEqual = mapsEqual,
            OnBagUpdate = OnBagUpdate, OnBankOpened = OnBankOpened, OnBankClosed = OnBankClosed,
        },
    })

    -- Full-baseline pull when we hold no inventory yet (fresh install / wiped DB)
    -- or when re-enabled mid-session — the peer watermark may already be ahead
    -- of missing data, which a delta pull would never backfill.
    if AltTracker.ResetPeerWatermarks then
        local hasData = false
        for _, cdb in pairs(AltTrackerWarbandDB) do
            if type(cdb) == "table" and ((cdb.bags and next(cdb.bags)) or (cdb.bank and next(cdb.bank))) then
                hasData = true; break
            end
        end
        if isOnDemand or not hasData then AltTracker.ResetPeerWatermarks() end
    end

    C_Timer.After(3, ScanBags)   -- prime our own bags after the login event storm
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("BAG_UPDATE")
frame:RegisterEvent("BANKFRAME_OPENED")
frame:RegisterEvent("BANKFRAME_CLOSED")
frame:RegisterEvent("PLAYERBANKSLOTS_CHANGED")
frame:RegisterEvent("GET_ITEM_INFO_RECEIVED")
frame:SetScript("OnEvent", function(self, event, arg1, arg2)
    if event == "PLAYER_LOGIN" then
        C_Timer.After(1, function() BootstrapPlugin(false) end)
    elseif event == "BAG_UPDATE" then
        OnBagUpdate(arg1)
    elseif event == "BANKFRAME_OPENED" then
        OnBankOpened()
    elseif event == "BANKFRAME_CLOSED" then
        OnBankClosed()
    elseif event == "PLAYERBANKSLOTS_CHANGED" then
        if isBankOpen then ScheduleBank() end
    elseif event == "GET_ITEM_INFO_RECEIVED" then
        local id, success = arg1, arg2
        if id and success and requestedIDs[id] then
            requestedIDs[id] = nil
            if AT_WB.isActive then
                if self._metaTimer then self._metaTimer:Cancel() end
                self._metaTimer = C_Timer.NewTimer(0.2, function()
                    self._metaTimer = nil
                    if AT_WB.isActive and AT_WB.Refresh then AT_WB.Refresh() end
                end)
            end
        end
    end
end)

-- Loaded on demand after login: PLAYER_LOGIN already fired, so bootstrap now
-- (and treat it as an on-demand enable so we force a baseline).
if IsLoggedIn() then
    C_Timer.After(1, function() BootstrapPlugin(true) end)
end
