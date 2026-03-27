------------------------------------------------------------
-- AltTracker Config
-- Registers an addon config panel in Interface → AddOns.
-- Stores everything in AltTrackerConfig (SavedVariable).
--
-- Settings:
--   syncMode   : "guild" | "whisper"
--   whitelist  : { "Name-Realm", ... }  (used in whisper mode)
--   accountNumber : number
------------------------------------------------------------

AltTracker      = AltTracker or {}
AltTrackerConfig = AltTrackerConfig or {}

------------------------------------------------------------
-- Defaults
------------------------------------------------------------

local function EnsureDefaults()
    AltTrackerConfig.syncMode      = AltTrackerConfig.syncMode      or "whisper"
    AltTrackerConfig.whitelist     = AltTrackerConfig.whitelist     or {}
    AltTrackerConfig.accountNumber = AltTrackerConfig.accountNumber or ""
    -- Default: only send characters from the current account during sync.
    -- Set to true to broadcast the entire DB (all accounts) instead.
    if AltTrackerConfig.sendAllAccounts == nil then
        AltTrackerConfig.sendAllAccounts = false
    end
    -- Toast notifications for profession cooldowns
    if AltTrackerConfig.toastsEnabled == nil then
        AltTrackerConfig.toastsEnabled = true
    end
    if not AltTrackerConfig.toastProfessions then
        AltTrackerConfig.toastProfessions = {
            Tailoring     = true,
            Alchemy       = true,
            Jewelcrafting = true,
        }
    end
end

------------------------------------------------------------
-- Helpers
------------------------------------------------------------

local function IsWhitelisted(name)
    for _, n in ipairs(AltTrackerConfig.whitelist) do
        if n:lower() == name:lower() then return true end
    end
    return false
end

local function AddToWhitelist(name)
    if name == "" or IsWhitelisted(name) then return false end
    table.insert(AltTrackerConfig.whitelist, name)
    return true
end

local function RemoveFromWhitelist(name)
    for i, n in ipairs(AltTrackerConfig.whitelist) do
        if n:lower() == name:lower() then
            table.remove(AltTrackerConfig.whitelist, i)
            return true
        end
    end
    return false
end

-- Expose so Core.lua can call these
AltTracker.IsWhitelisted    = IsWhitelisted
AltTracker.AddToWhitelist   = AddToWhitelist
AltTracker.RemoveFromWhitelist = RemoveFromWhitelist
AltTracker.EnsureConfigDefaults = EnsureDefaults

------------------------------------------------------------
-- Panel frame
------------------------------------------------------------

local panel
local listRows = {}
local LIST_ROW_HEIGHT = 18
local LIST_VISIBLE    = 12

local function RefreshList()
    local wl = AltTrackerConfig.whitelist
    for i, row in ipairs(listRows) do
        local name = wl[i]
        if name then
            row.label:SetText(name)
            row.removeBtn:Show()
            row:Show()
        else
            row:Hide()
        end
    end
end

local function BuildPanel()
    if panel then return end
    EnsureDefaults()

    panel = CreateFrame("Frame", "AltTrackerConfigPanel", UIParent, "BackdropTemplate")
    panel.name = "AltTracker"
    panel:SetSize(520, 680)
    panel:SetPoint("CENTER")
    panel:SetFrameStrata("DIALOG")
    panel:SetToplevel(true)
    panel:SetMovable(true)
    panel:EnableMouse(true)
    panel:RegisterForDrag("LeftButton")
    panel:SetScript("OnDragStart", panel.StartMoving)
    panel:SetScript("OnDragStop",  panel.StopMovingOrSizing)
    panel:SetBackdrop({
        bgFile   = "Interface/Tooltips/UI-Tooltip-Background",
        edgeFile = "Interface/DialogFrame/UI-DialogBox-Border",
        tile=true, tileSize=16, edgeSize=32,
        insets={left=8,right=8,top=8,bottom=8},
    })
    panel:SetBackdropColor(0.05, 0.05, 0.08, 0.97)
    tinsert(UISpecialFrames, "AltTrackerConfigPanel")  -- Esc closes it

    local closeBtn = CreateFrame("Button", nil, panel, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", -5, -5)

    --------------------------------------------------------
    -- Title
    --------------------------------------------------------

    local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("AltTracker")

    local subtitle = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
    subtitle:SetTextColor(0.7, 0.7, 0.7)
    subtitle:SetText("Alt character tracking and sync")

    local divider = panel:CreateTexture(nil, "ARTWORK")
    divider:SetHeight(1)
    divider:SetPoint("TOPLEFT",  subtitle, "BOTTOMLEFT",  0, -10)
    divider:SetPoint("TOPRIGHT", panel,    "TOPRIGHT",  -16, -52)
    divider:SetColorTexture(0.3, 0.3, 0.3, 1)

    --------------------------------------------------------
    -- Account number
    --------------------------------------------------------

    local acctLabel = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    acctLabel:SetPoint("TOPLEFT", divider, "BOTTOMLEFT", 0, -16)
    acctLabel:SetText("Account Number")

    local acctBox = CreateFrame("EditBox", "AltTrackerConfigAcctBox", panel, "InputBoxTemplate")
    acctBox:SetSize(60, 20)
    acctBox:SetPoint("LEFT", acctLabel, "RIGHT", 12, 0)
    acctBox:SetAutoFocus(false)
    acctBox:SetMaxLetters(3)
    acctBox:SetNumeric(true)
    acctBox:SetText(tostring(AltTrackerConfig.accountNumber or ""))
    acctBox:SetScript("OnEnterPressed", function(self)
        AltTrackerConfig.accountNumber = tonumber(self:GetText()) or ""
        self:ClearFocus()
    end)
    acctBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

    local acctHint = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    acctHint:SetPoint("LEFT", acctBox, "RIGHT", 8, 0)
    acctHint:SetTextColor(0.6, 0.6, 0.6)
    acctHint:SetText("Used in exports to identify which WoW account a char belongs to")

    --------------------------------------------------------
    -- Send scope checkbox
    --------------------------------------------------------

    local sendAllCheck = CreateFrame("CheckButton", "AltTrackerConfigSendAll", panel, "UICheckButtonTemplate")
    sendAllCheck:SetSize(26, 26)
    sendAllCheck:SetPoint("TOPLEFT", acctLabel, "BOTTOMLEFT", -2, -10)
    sendAllCheck:SetChecked(AltTrackerConfig.sendAllAccounts or false)
    sendAllCheck:SetScript("OnClick", function(self)
        AltTrackerConfig.sendAllAccounts = self:GetChecked() and true or false
    end)

    local sendAllLabel = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    sendAllLabel:SetPoint("LEFT", sendAllCheck, "RIGHT", 4, 0)
    sendAllLabel:SetText("Send all accounts when syncing")

    local sendAllHint = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    sendAllHint:SetPoint("LEFT", sendAllLabel, "RIGHT", 10, 0)
    sendAllHint:SetTextColor(0.6, 0.6, 0.6)
    sendAllHint:SetText("Default: only send characters from this account")

    --------------------------------------------------------
    -- Whitelist section header
    --------------------------------------------------------

    local wlHeader = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    wlHeader:SetPoint("TOPLEFT", sendAllCheck, "BOTTOMLEFT", 2, -14)
    wlHeader:SetText("Sync Whitelist")

    local wlHint = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    wlHint:SetPoint("LEFT", wlHeader, "RIGHT", 10, 0)
    wlHint:SetTextColor(0.6, 0.6, 0.6)
    wlHint:SetText("Characters on your other WoW accounts to sync with (Name or Name-Realm)")

    --------------------------------------------------------
    -- Add character row
    --------------------------------------------------------

    local addBox = CreateFrame("EditBox", "AltTrackerConfigAddBox", panel, "InputBoxTemplate")
    addBox:SetSize(180, 20)
    addBox:SetPoint("TOPLEFT", wlHeader, "BOTTOMLEFT", 0, -10)
    addBox:SetAutoFocus(false)
    addBox:SetMaxLetters(60)
    addBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

    local addBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    addBtn:SetSize(80, 22)
    addBtn:SetPoint("LEFT", addBox, "RIGHT", 8, 0)
    addBtn:SetText("Add")
    addBtn:SetScript("OnClick", function()
        local name = strtrim(addBox:GetText())
        if name == "" then return end
        if AddToWhitelist(name) then
            addBox:SetText("")
            RefreshList()
        end
    end)
    addBox:SetScript("OnEnterPressed", function(self)
        addBtn:Click()
        self:ClearFocus()
    end)

    -- "Add current character" convenience button
    local addSelfBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    addSelfBtn:SetSize(140, 22)
    addSelfBtn:SetPoint("LEFT", addBtn, "RIGHT", 6, 0)
    addSelfBtn:SetText("Add This Character")
    addSelfBtn:SetScript("OnClick", function()
        local name = UnitName("player")
        local realm = GetRealmName()
        if name and realm then
            local full = name .. "-" .. realm
            if AddToWhitelist(full) then RefreshList() end
        end
    end)

    --------------------------------------------------------
    -- Scrollable whitelist
    --------------------------------------------------------

    local listFrame = CreateFrame("Frame", nil, panel, "BackdropTemplate")
    listFrame:SetPoint("TOPLEFT", addBox, "BOTTOMLEFT", 0, -10)
    listFrame:SetSize(420, LIST_ROW_HEIGHT * LIST_VISIBLE + 4)
    listFrame:SetBackdrop({
        bgFile = "Interface/Tooltips/UI-Tooltip-Background",
        edgeFile = "Interface/Buttons/WHITE8X8",
        tile = true, tileSize = 8, edgeSize = 1,
    })
    listFrame:SetBackdropColor(0.05, 0.05, 0.07, 0.9)
    listFrame:SetBackdropBorderColor(0.3, 0.3, 0.35, 1)

    for i = 1, LIST_VISIBLE do
        local row = CreateFrame("Frame", nil, listFrame)
        row:SetSize(420, LIST_ROW_HEIGHT)
        row:SetPoint("TOPLEFT", listFrame, "TOPLEFT", 0, -((i - 1) * LIST_ROW_HEIGHT) - 2)

        -- Alternating background
        local bg = row:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        if i % 2 == 0 then
            bg:SetColorTexture(0.10, 0.10, 0.14, 0.5)
        else
            bg:SetColorTexture(0.06, 0.06, 0.10, 0.5)
        end

        local lbl = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        lbl:SetPoint("LEFT", 8, 0)
        lbl:SetWidth(340)
        lbl:SetJustifyH("LEFT")
        row.label = lbl

        local removeBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
        removeBtn:SetSize(58, 16)
        removeBtn:SetPoint("RIGHT", row, "RIGHT", -4, 0)
        removeBtn:SetText("Remove")
        removeBtn:SetScript("OnClick", function()
            local name = lbl:GetText()
            if RemoveFromWhitelist(name) then RefreshList() end
        end)
        row.removeBtn = removeBtn

        listRows[i] = row
    end

    --------------------------------------------------------
    -- Cooldown Toast Notifications
    --------------------------------------------------------

    local toastDivider = panel:CreateTexture(nil, "ARTWORK")
    toastDivider:SetHeight(1)
    toastDivider:SetPoint("TOPLEFT",  listFrame, "BOTTOMLEFT",  0, -16)
    toastDivider:SetPoint("TOPRIGHT", panel,     "TOPRIGHT",  -16, 0)
    toastDivider:SetColorTexture(0.3, 0.3, 0.3, 1)

    local toastHeader = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    toastHeader:SetPoint("TOPLEFT", toastDivider, "BOTTOMLEFT", 0, -10)
    toastHeader:SetText("Cooldown Notifications")

    local toastHint = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    toastHint:SetPoint("LEFT", toastHeader, "RIGHT", 10, 0)
    toastHint:SetTextColor(0.6, 0.6, 0.6)
    toastHint:SetText("Show a toast when a profession cooldown expires")

    -- Master toggle
    local toastMasterCheck = CreateFrame("CheckButton", "AltTrackerConfigToastMaster", panel, "UICheckButtonTemplate")
    toastMasterCheck:SetSize(26, 26)
    toastMasterCheck:SetPoint("TOPLEFT", toastHeader, "BOTTOMLEFT", -2, -8)
    toastMasterCheck:SetChecked(AltTrackerConfig.toastsEnabled ~= false)
    toastMasterCheck:SetScript("OnClick", function(self)
        AltTrackerConfig.toastsEnabled = self:GetChecked() and true or false
    end)

    local toastMasterLabel = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    toastMasterLabel:SetPoint("LEFT", toastMasterCheck, "RIGHT", 4, 0)
    toastMasterLabel:SetText("Enable cooldown toast notifications")

    -- Per-profession toggles
    local TOAST_PROFS = {
        { key = "Tailoring",     label = "Tailoring (Mooncloth, Shadowcloth, Spellcloth)" },
        { key = "Alchemy",       label = "Alchemy (Transmute)" },
        { key = "Jewelcrafting", label = "Jewelcrafting (Brilliant Glass)" },
    }

    local profChecks = {}
    local prevAnchor = toastMasterCheck

    for _, prof in ipairs(TOAST_PROFS) do
        local cb = CreateFrame("CheckButton", "AltTrackerConfigToast_" .. prof.key, panel, "UICheckButtonTemplate")
        cb:SetSize(26, 26)
        cb:SetPoint("TOPLEFT", prevAnchor, "BOTTOMLEFT", (prevAnchor == toastMasterCheck) and 20 or 0, -2)
        cb:SetChecked(AltTrackerConfig.toastProfessions[prof.key] ~= false)
        cb:SetScript("OnClick", function(self)
            AltTrackerConfig.toastProfessions[prof.key] = self:GetChecked() and true or false
        end)

        local lbl = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        lbl:SetPoint("LEFT", cb, "RIGHT", 4, 0)
        lbl:SetText(prof.label)

        profChecks[prof.key] = cb
        prevAnchor = cb
    end

    --------------------------------------------------------
    -- Show/hide toggle button in top-right
    --------------------------------------------------------

    panel:SetScript("OnShow", function()
        EnsureDefaults()
        acctBox:SetText(tostring(AltTrackerConfig.accountNumber or ""))
        sendAllCheck:SetChecked(AltTrackerConfig.sendAllAccounts or false)
        toastMasterCheck:SetChecked(AltTrackerConfig.toastsEnabled ~= false)
        for profKey, cb in pairs(profChecks) do
            cb:SetChecked(AltTrackerConfig.toastProfessions[profKey] ~= false)
        end
        RefreshList()
    end)

    panel:Hide()
end

------------------------------------------------------------
-- Public: open/close config window
------------------------------------------------------------

function AltTracker.OpenConfig()
    BuildPanel()
    if panel:IsShown() then
        panel:Hide()
    else
        panel:Show()
    end
end

------------------------------------------------------------
-- Init on login
------------------------------------------------------------

local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("PLAYER_LOGIN")
initFrame:SetScript("OnEvent", function()
    EnsureDefaults()
    BuildPanel()
end)