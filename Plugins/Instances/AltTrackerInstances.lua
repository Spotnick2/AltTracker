------------------------------------------------------------
-- AltTrackerInstances — cross-alt raid-lockout matrix (P2).
--
-- Pure display. The lockout data is captured + synced by AltTracker core
-- (Core.lua ScanSavedInstances) into flat cd-style fields on each character
-- record: si_<name>@<difficulty> = "expiresAt|progress|total|maxPlayers|diffName".
-- This plugin reads those fields and lays them out SavedInstances-style:
--   rows = raids (the union across all alts that have a lockout),
--   cols = characters (only those with at least one lockout),
--   cell = boss progress "X/Y", coloured by how soon it resets; hover = detail.
--
-- LoadOnDemand: registers on PLAYER_LOGIN, or immediately if enabled mid-session.
------------------------------------------------------------

local ADDON_ID = "AltTrackerInstances"
local AT_SI = { headers = {}, rowLabels = {}, cells = {}, seps = {} }

local NAME_COL_W = 168   -- left column: raid name
local COL_W      = 52    -- per-character column
local HEADER_H   = 24
local ROW_H      = 20
local PAD_X      = 12
local PAD_Y      = 10
local TITLE_H    = 22
local MAX_COLS   = 24
local MAX_ROWS   = 16

local panel, titleFS, emptyFS

local function Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cff00ccff[AltTracker Raids]|r " .. msg)
end

-- "in 2d 4h" style, from a seconds-remaining value.
local function fmtDur(sec)
    sec = tonumber(sec) or 0
    if sec <= 0 then return "now" end
    local d = math.floor(sec / 86400)
    local h = math.floor((sec % 86400) / 3600)
    local m = math.floor((sec % 3600) / 60)
    if d > 0 then return d .. "d " .. h .. "h" end
    if h > 0 then return h .. "h " .. m .. "m" end
    return m .. "m"
end

-- Colour a cell by how soon the lockout resets (planning cue).
local function resetColor(remaining)
    if remaining < 12 * 3600 then return 1.00, 0.42, 0.34   -- <12h — going soon
    elseif remaining < 2 * 86400 then return 1.00, 0.82, 0.30 -- <2 days
    else return 0.52, 0.90, 0.52 end                          -- plenty of time
end

-- Parse "si_<name>@<diff>" + "expiresAt|prog|total|size|diffName".
local function parseLockout(key, val)
    local name, diff = key:match("^si_(.+)@(%d+)$")
    if not name then return nil end
    local e, p, t, size, dname = val:match("^(%d+)|(%d*)|(%d*)|(%d*)|(.*)$")
    if not e then return nil end
    return {
        raidKey  = key,
        name     = name,
        diff     = tonumber(diff) or 0,
        expires  = tonumber(e) or 0,
        prog     = tonumber(p) or 0,
        total    = tonumber(t) or 0,
        size     = tonumber(size) or 0,
        diffName = dname or "",
    }
end

-- Collect the characters (with any lockout) and the union of raids.
local function gather()
    local chars, raidOrder, raidSeen, lookup = {}, {}, {}, {}
    AltTrackerDB = AltTrackerDB or {}
    for guid, c in pairs(AltTrackerDB) do
        if type(c) == "table" and c.name then
            local mine = nil
            for k, v in pairs(c) do
                if type(k) == "string" and type(v) == "string" and k:find("^si_") then
                    local lk = parseLockout(k, v)
                    if lk then
                        mine = mine or {}
                        mine[lk.raidKey] = lk
                        if not raidSeen[lk.raidKey] then
                            raidSeen[lk.raidKey] = lk
                            raidOrder[#raidOrder + 1] = lk
                        end
                    end
                end
            end
            if mine then
                chars[#chars + 1] = { guid = guid, name = c.name, class = c.class }
                lookup[guid] = mine
            end
        end
    end
    table.sort(chars, function(a, b) return (a.name or "") < (b.name or "") end)
    table.sort(raidOrder, function(a, b)
        if a.name ~= b.name then return a.name < b.name end
        return a.diff < b.diff
    end)
    return chars, raidOrder, lookup
end

------------------------------------------------------------
-- Widget pools (created lazily, parented to the panel)
------------------------------------------------------------

local function getHeader(i)
    local fs = AT_SI.headers[i]
    if not fs then
        fs = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        fs:SetJustifyH("CENTER")
        fs:SetWidth(COL_W)
        AT_SI.headers[i] = fs
    end
    return fs
end

local function getRowLabel(j)
    local fs = AT_SI.rowLabels[j]
    if not fs then
        fs = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        fs:SetJustifyH("LEFT")
        fs:SetWidth(NAME_COL_W)
        AT_SI.rowLabels[j] = fs
    end
    return fs
end

-- Each cell is a mouse-enabled frame with a centered fontstring + a tooltip.
local function getCell(j, i)
    AT_SI.cells[j] = AT_SI.cells[j] or {}
    local cell = AT_SI.cells[j][i]
    if not cell then
        cell = CreateFrame("Frame", nil, panel)
        cell:SetSize(COL_W, ROW_H)
        cell.text = cell:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        cell.text:SetPoint("CENTER")
        cell:EnableMouse(true)
        cell:SetScript("OnEnter", function(self)
            if not self.info then return end
            local d = self.info
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(d.charName, 1, 1, 1)
            local sub = d.diffName ~= "" and d.diffName or (d.size > 0 and (d.size .. "-man") or "")
            GameTooltip:AddLine(d.raidName .. (sub ~= "" and (" |cff888888(" .. sub .. ")|r") or ""), 0.8, 0.8, 0.8)
            if d.total > 0 then
                GameTooltip:AddLine("Bosses: " .. d.prog .. "/" .. d.total, 0.9, 0.9, 0.9)
            end
            local rem = d.expires - time()
            if rem > 0 then
                GameTooltip:AddLine("Resets in " .. fmtDur(rem), 0.6, 0.85, 1)
            else
                GameTooltip:AddLine("Reset available", 0.5, 1, 0.5)
            end
            GameTooltip:Show()
        end)
        cell:SetScript("OnLeave", function() GameTooltip:Hide() end)
        AT_SI.cells[j][i] = cell
    end
    return cell
end

------------------------------------------------------------
-- Layout
------------------------------------------------------------

local function hideFrom(pool, from)
    for k = from, #pool do if pool[k] then pool[k]:Hide() end end
end

function AT_SI.Refresh()
    if not panel or not panel:IsShown() then return end

    local chars, raids, lookup = gather()
    local now = time()

    -- Empty state
    if #chars == 0 or #raids == 0 then
        for _, fs in ipairs(AT_SI.headers) do fs:Hide() end
        for _, fs in ipairs(AT_SI.rowLabels) do fs:Hide() end
        for _, row in ipairs(AT_SI.cells) do for _, c in ipairs(row) do c:Hide() end end
        emptyFS:Show()
        return
    end
    emptyFS:Hide()

    local nCols = math.min(#chars, MAX_COLS)
    local nRows = math.min(#raids, MAX_ROWS)

    -- Column headers = character names (class-coloured).
    for i = 1, nCols do
        local ch = chars[i]
        local fs = getHeader(i)
        fs:ClearAllPoints()
        fs:SetPoint("TOPLEFT", panel, "TOPLEFT", PAD_X + NAME_COL_W + (i - 1) * COL_W, -(PAD_Y + TITLE_H))
        local nm = ch.name or "?"
        if #nm > 8 then nm = nm:sub(1, 8) end
        fs:SetText(nm)
        local cc = ch.class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[ch.class]
        if cc then fs:SetTextColor(cc.r, cc.g, cc.b) else fs:SetTextColor(0.9, 0.9, 0.9) end
        fs:Show()
    end
    hideFrom(AT_SI.headers, nCols + 1)

    -- Rows = raids; left label + one cell per character.
    local rowTop = PAD_Y + TITLE_H + HEADER_H
    for j = 1, nRows do
        local raid = raids[j]
        local y = -(rowTop + (j - 1) * ROW_H)

        local lbl = getRowLabel(j)
        lbl:ClearAllPoints()
        lbl:SetPoint("TOPLEFT", panel, "TOPLEFT", PAD_X, y - 3)
        local diffSuffix = (raid.size > 0 and raid.diff > 1) and (" |cff888888H|r") or ""
        lbl:SetText(raid.name .. diffSuffix)
        lbl:SetTextColor(unpack(AltTracker.C.TEXT_NORM))
        lbl:Show()

        for i = 1, nCols do
            local cell = getCell(j, i)
            cell:ClearAllPoints()
            cell:SetPoint("TOPLEFT", panel, "TOPLEFT", PAD_X + NAME_COL_W + (i - 1) * COL_W, y)
            local lk = lookup[chars[i].guid] and lookup[chars[i].guid][raid.raidKey]
            if lk and lk.expires > now then
                cell.text:SetText(lk.total > 0 and (lk.prog .. "/" .. lk.total) or "\226\151\143")  -- "●" if no boss count
                cell.text:SetTextColor(resetColor(lk.expires - now))
                cell.info = {
                    charName = chars[i].name, raidName = raid.name,
                    prog = lk.prog, total = lk.total, size = lk.size,
                    diffName = lk.diffName, expires = lk.expires,
                }
                cell:Show()
            else
                cell.text:SetText("")
                cell.info = nil
                cell:Show()   -- kept shown (empty) so the grid stays aligned
            end
        end
        for i = nCols + 1, #(AT_SI.cells[j] or {}) do AT_SI.cells[j][i]:Hide() end
    end
    -- Hide any leftover rows from a previous (larger) render.
    hideFrom(AT_SI.rowLabels, nRows + 1)
    for j = nRows + 1, #AT_SI.cells do
        for _, c in ipairs(AT_SI.cells[j]) do c:Hide() end
    end
end

------------------------------------------------------------
-- Panel + activation
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
    titleFS:SetPoint("TOPLEFT", panel, "TOPLEFT", PAD_X, -PAD_Y + 2)
    titleFS:SetText("Raid Lockouts")
    titleFS:SetTextColor(unpack(AltTracker.C.TEXT_BRIGHT))

    emptyFS = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    emptyFS:SetPoint("TOPLEFT", panel, "TOPLEFT", PAD_X, -(PAD_Y + TITLE_H + 6))
    emptyFS:SetText("No raid lockouts on any tracked character.")
    emptyFS:SetTextColor(unpack(AltTracker.C.TEXT_DIM))
    emptyFS:Hide()
end

local function HookRefresh()
    if AT_SI._refreshHooked or type(AltTracker.RefreshSheet) ~= "function" then return end
    local prev = AltTracker.RefreshSheet
    AltTracker.RefreshSheet = function(...)
        prev(...)
        if AT_SI.isActive then C_Timer.After(0, function() if AT_SI.isActive then AT_SI.Refresh() end end) end
    end
    AT_SI._refreshHooked = true
end

function AT_SI.Activate(mainFrame)
    BuildPanel(mainFrame)
    HookRefresh()
    AT_SI.isActive = true

    if mainFrame.bodyScroll   then mainFrame.bodyScroll:Hide()   end
    if mainFrame.frozenScroll then mainFrame.frozenScroll:Hide() end
    if mainFrame.headerScroll then mainFrame.headerScroll:Hide() end
    if mainFrame.frozenHeader then mainFrame.frozenHeader:Hide() end
    if mainFrame.hScrollBar   then mainFrame.hScrollBar:Hide()   end
    if mainFrame.totalsBar    then mainFrame.totalsBar:Hide()    end

    panel:Show()
    if AltTracker.RequestLockouts then AltTracker.RequestLockouts() end  -- refresh our own lockouts
    AT_SI.Refresh()
end

function AT_SI.Deactivate(mainFrame)
    AT_SI.isActive = false
    if panel then panel:Hide() end
    if mainFrame.bodyScroll   then mainFrame.bodyScroll:Show()   end
    if mainFrame.frozenScroll then mainFrame.frozenScroll:Show() end
    if mainFrame.headerScroll then mainFrame.headerScroll:Show() end
    if mainFrame.frozenHeader then mainFrame.frozenHeader:Show() end
    if mainFrame.hScrollBar   then mainFrame.hScrollBar:Show()   end
    if mainFrame.totalsBar    then mainFrame.totalsBar:Show()    end
end

function AT_SI._Bootstrap()
    if not AltTracker or not AltTracker.RegisterPlugin then
        DEFAULT_CHAT_FRAME:AddMessage("|cff00ccff[AltTracker Raids]|r AltTracker not found.")
        return
    end
    HookRefresh()
    AltTracker.RegisterPlugin({
        id           = ADDON_ID,
        label        = "Raids",
        icon         = (AltTracker.MEDIA_PATH or "Interface\\AddOns\\AltTracker\\Media\\") .. "Icons\\raid.tga",
        _isPlugin    = true,
        OnActivate   = function(mainFrame) AT_SI.Activate(mainFrame) end,
        OnDeactivate = function(mainFrame) AT_SI.Deactivate(mainFrame) end,
        _test        = { parseLockout = parseLockout, gather = gather },
    })
end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:SetScript("OnEvent", function(_, event)
    if event ~= "PLAYER_LOGIN" then return end
    C_Timer.After(1, AT_SI._Bootstrap)
end)

-- Loaded on demand after login: PLAYER_LOGIN already fired, so bootstrap now.
if IsLoggedIn() then
    C_Timer.After(1, AT_SI._Bootstrap)
end
