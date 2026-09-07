------------------------------------------------------------
-- AltTracker Roster - gear audit rendering
--
-- Two surfaces over the one AltTracker.AuditCharacter() result:
--   * corner badges on the paper-doll gear buttons (+ tooltip lines), which
--     answer "where is the problem"
--   * the Audit tab's scrollable list, which answers "what is the problem"
--     without hovering seventeen slots
--
-- This lives in its own file because AltTrackerRoster.lua sits exactly at Lua
-- 5.1's 200-top-level-locals limit -- one more file-scope `local` there fails
-- to compile. Same reason RosterScene.lua is separate. Everything the renderer
-- needs from that file (the gear buttons, the tab content frame) is handed in
-- as an argument rather than reached for, so no private state is promoted to a
-- global.
--
-- Colour handling: AUDIT_CODES carries CLA's spreadsheet fills, which are tuned
-- for a white sheet and would glare on the addon's charcoal background. They
-- are used at full strength only for the dot and the 3px severity bar; the row
-- background gets the same hue at ~15% alpha.
------------------------------------------------------------

AltTracker = AltTracker or {}

local RA = {}
AltTracker.RosterAudit = RA

local ROW_H      = 30    -- two lines: item name over issue label
local ROW_STEP   = 32
local ROW_INSET  = 10
local BAR_W      = 3
local ICON_SIZE  = 18
local BADGE_SIZE = 9

-- Row pool and the frame rows are anchored into, both kept on the module table.
RA.rows = {}
RA.content = nil

------------------------------------------------------------
-- Tab body
------------------------------------------------------------

local function EnsureRow(index)
    local existing = RA.rows[index]
    if existing then return existing end

    local parent = RA.content
    if not parent then return nil end

    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(ROW_H)

    -- Severity tint behind the whole row, and a solid bar down its left edge.
    row.bg = row:CreateTexture(nil, "BACKGROUND")
    row.bg:SetAllPoints(row)
    row.bg:SetColorTexture(0, 0, 0, 0)

    row.bar = row:CreateTexture(nil, "ARTWORK")
    row.bar:SetWidth(BAR_W)
    row.bar:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
    row.bar:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0)

    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(ICON_SIZE, ICON_SIZE)
    row.icon:SetPoint("LEFT", row, "LEFT", BAR_W + 5, 0)
    row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.name:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 6, 1)
    row.name:SetPoint("RIGHT", row, "RIGHT", -4, 0)
    row.name:SetJustifyH("LEFT")

    row.issue = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.issue:SetPoint("TOPLEFT", row.name, "BOTTOMLEFT", 0, -1)
    row.issue:SetPoint("RIGHT", row, "RIGHT", -4, 0)
    row.issue:SetJustifyH("LEFT")

    RA.rows[index] = row
    return row
end

-- Called once from BuildTabs. `content` is tabFrames.audit.
function RA.BuildTab(content)
    RA.content = content

    RA.header = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    RA.header:SetPoint("TOPLEFT", content, "TOPLEFT", ROW_INSET, -12)
    RA.header:SetJustifyH("LEFT")
    RA.header:SetTextColor(unpack(AltTracker.C.TEXT_DIM))
    RA.header:SetText("")
end

-- Populates the tab. Returns the final y so the caller can size the scroll
-- child via SetTabContentHeight("audit", y).
function RA.RenderTab(char)
    if not RA.content then return -10 end

    local issues = char and AltTracker.AuditCharacter(char) or nil
    local y = -34

    if RA.header then
        if not char then
            RA.header:SetText("No character selected.")
        elseif issues == nil then
            -- Distinct from "no issues": this record predates gearmod_, or has
            -- not been synced from a client that writes it.
            RA.header:SetText("No gear detail synced for this character.")
        elseif #issues == 0 then
            RA.header:SetText("No issues found.")
        elseif #issues == 1 then
            RA.header:SetText("1 issue")
        else
            RA.header:SetText(("%d issues"):format(#issues))
        end
    end

    local shown = 0
    for i, issue in ipairs(issues or {}) do
        local row = EnsureRow(i)
        if row then
            shown = i

            row.bar:SetColorTexture(issue.r, issue.g, issue.b, 1)
            row.bg:SetColorTexture(issue.r, issue.g, issue.b, 0.15)

            local icon = issue.itemID and issue.itemID > 0 and GetItemIcon(issue.itemID)
            if icon then
                row.icon:SetTexture(icon)
                row.icon:Show()
            else
                row.icon:Hide()
            end

            local name = issue.itemName
            if not name or name == "" then
                name = AltTracker.RosterAudit.SlotLabel(issue.slot)
            end
            row.name:SetText(name)
            row.name:SetTextColor(unpack(AltTracker.C.TEXT_BRIGHT))

            row.issue:SetText(issue.label)
            row.issue:SetTextColor(issue.r, issue.g, issue.b)

            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", RA.content, "TOPLEFT", ROW_INSET, y)
            row:SetPoint("TOPRIGHT", RA.content, "TOPRIGHT", -ROW_INSET, y)
            row:Show()
            y = y - ROW_STEP
        end
    end

    for i = shown + 1, #RA.rows do
        RA.rows[i]:Hide()
    end

    return y
end

------------------------------------------------------------
-- Paper-doll badges + tooltip lines
------------------------------------------------------------

-- Cache of the last audit, keyed by slot, so the tooltip handler doesn't
-- re-run the whole audit on every mouseover.
RA.bySlot = {}

-- Badge textures, keyed by slot, created once on first use. Kept here rather
-- than assigned onto the Roster plugin's button objects: this module owns its
-- own widgets and does not add fields to another file's frames.
RA.badges = {}

local SLOT_LABELS = {
    head = "Head", neck = "Neck", shoulder = "Shoulder", back = "Back",
    chest = "Chest", wrist = "Wrist", hands = "Hands", waist = "Waist",
    legs = "Legs", feet = "Feet", ring1 = "Ring 1", ring2 = "Ring 2",
    trinket1 = "Trinket 1", trinket2 = "Trinket 2", mainhand = "Main Hand",
    offhand = "Off Hand", ranged = "Ranged",
}

function RA.SlotLabel(slotKey)
    return SLOT_LABELS[slotKey] or slotKey or "?"
end

-- Recompute the per-slot index and stamp badges onto the gear buttons.
-- `gearButtons` is the Roster plugin's slotKey -> button table.
function RA.ApplyBadges(char, gearButtons)
    RA.bySlot = {}

    local issues = char and AltTracker.AuditCharacter(char) or nil
    for _, issue in ipairs(issues or {}) do
        local list = RA.bySlot[issue.slot]
        if not list then
            list = {}
            RA.bySlot[issue.slot] = list
        end
        list[#list + 1] = issue
    end

    if type(gearButtons) ~= "table" then return end

    for slotKey, btn in pairs(gearButtons) do
        local badge = RA.badges[slotKey]
        if not badge then
            badge = btn:CreateTexture(nil, "OVERLAY")
            badge:SetSize(BADGE_SIZE, BADGE_SIZE)
            badge:SetPoint("TOPRIGHT", btn, "TOPRIGHT", -1, -1)
            badge:SetTexture("Interface\\Buttons\\WHITE8X8")
            RA.badges[slotKey] = badge
        end

        -- The worst issue wins the dot; AuditCharacter already sorted by rank.
        local worst = RA.bySlot[slotKey] and RA.bySlot[slotKey][1]
        if worst then
            badge:SetVertexColor(worst.r, worst.g, worst.b, 1)
            badge:Show()
        else
            badge:Hide()
        end
    end
end

-- Issue lines for a slot's gear tooltip. Call between the item lines and
-- GameTooltip:Show().
function RA.AddTooltipLines(slotKey)
    local list = RA.bySlot[slotKey]
    if not list or #list == 0 then return end

    GameTooltip:AddLine(" ")
    for _, issue in ipairs(list) do
        GameTooltip:AddLine("! " .. issue.label, issue.r, issue.g, issue.b)
    end
end
