AltTracker = AltTracker or {}
AltTrackerDB = AltTrackerDB or {}

------------------------------------------------------------
-- DB cleanup — wipes all entries except the current character,
-- then rescans and requests fresh data from all peers.
-- This is the nuclear option for clearing corruption.
------------------------------------------------------------

local function CleanupDB()
    local guid = UnitGUID("player")

    -- Keep only the current character's entry
    local kept = 0
    for k in pairs(AltTrackerDB) do
        if k ~= guid then
            AltTrackerDB[k] = nil
        else
            kept = 1
        end
    end

    -- Rescan current character to make sure we have fresh data
    if AltTracker.ScanCharacter then
        AltTracker.ScanCharacter()
    end

    return kept
end

------------------------------------------------------------
-- Constants
------------------------------------------------------------

local PREFIX = "ALTTRACKER"
local MSG_CHAR = "CHAR"
local MSG_REQUEST = "REQ"
local MSG_CHUNK = "CHUNK"
local MSG_DONE = "DONE"

-- Protocol version — bump this whenever the serialization format or
-- field set changes in a way that would corrupt an older client's DB.
-- Both sides must match to exchange data. Old clients see an unknown
-- command string and silently drop the packet.
local PROTOCOL_VERSION = "3"
local MSG_REQUEST_V = MSG_REQUEST .. PROTOCOL_VERSION   -- "REQ3"
local MSG_DONE_V    = MSG_DONE    .. PROTOCOL_VERSION   -- "DONE3"

-- WoW addon messages are capped at 255 bytes.
-- "CHUNK|" prefix = 6 bytes, leaving 249 bytes of payload per chunk.
local MAX_CHUNK = 249
local CHUNK_SEND_INTERVAL = 0.1   -- seconds between chunk packets

local incomingBuffers = {}

------------------------------------------------------------
-- Checksum — simple additive hash over payload bytes.
-- Returns a hex string. Computed over the full reassembled
-- buffer so the receiver can detect corruption or truncation.
------------------------------------------------------------

local function ComputeChecksum(str)
    local h = 0
    for i = 1, #str do
        h = (h * 31 + string.byte(str, i)) % 0xFFFFFFFF
    end
    return string.format("%08X", h)
end

------------------------------------------------------------
-- Validation — reject incoming records whose immutable
-- fields (class, name) have changed for an existing GUID.
-- Returns true if the record is safe to accept.
------------------------------------------------------------

local function ValidateIncoming(c, sender)
    if not c or not c.guid then return false end

    local existing = AltTrackerDB[c.guid]
    if not existing then return true end  -- new character, nothing to conflict

    -- Class should never change for a given GUID
    if existing.class and c.class and existing.class ~= c.class then
        Print("|cffff0000Rejected|r data for " .. (c.name or c.guid) ..
              " from " .. (sender or "unknown") ..
              ": class changed (" .. tostring(existing.class) ..
              " -> " .. tostring(c.class) .. ").")
        return false
    end

    -- Name should never change for a given GUID
    if existing.name and c.name and existing.name ~= c.name then
        Print("|cffff0000Rejected|r data for GUID " .. c.guid ..
              " from " .. (sender or "unknown") ..
              ": name changed (" .. tostring(existing.name) ..
              " -> " .. tostring(c.name) .. ").")
        return false
    end

    return true
end

local PLAYER_NAME = UnitName("player")

------------------------------------------------------------
-- Sync routing — whisper-only to whitelisted characters
------------------------------------------------------------

-- Returns a list of {channel, target} pairs to send to.
-- Only contacts whitelisted characters via whisper.
-- Guild broadcast is disabled for now (alt tracker, not guild tracker).
local function GetSyncTargets()
    AltTrackerConfig = AltTrackerConfig or {}

    local whitelist = AltTrackerConfig.whitelist or {}
    if #whitelist == 0 then
        return {}
    end

    local targets = {}
    for _, name in ipairs(whitelist) do
        table.insert(targets, { channel = "WHISPER", target = name })
    end

    return targets
end

------------------------------------------------------------
-- Chat output
------------------------------------------------------------

local function Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cff00ccff[AltTracker]|r " .. msg)
end

------------------------------------------------------------
-- Serialize character
------------------------------------------------------------

local function SerializeChar(c)

    local parts = {}

    for k,v in pairs(c) do
        if type(v) ~= "table"
        and not k:find("^gearlink_")   -- item links are local-only (too large for sync)
        and k ~= "specIcon"            -- numeric fileID, client-specific
        then
            parts[#parts+1] = k .. ":" .. tostring(v)
        end
    end

    return table.concat(parts, "\n")

end

------------------------------------------------------------
-- Deserialize character
------------------------------------------------------------

local function DeserializeChar(msg)

    local c = {}

    for line in string.gmatch(msg, "([^\n]+)") do

        local k, v = line:match("^([^:]+):(.+)$")

        if k then
            local num = tonumber(v)
            c[k] = num or v
        end

    end

    if not c.guid then
        return
    end

    return c

end

------------------------------------------------------------
-- Serialize full DB
------------------------------------------------------------

-- "==END==" on its own line is the character record separator.
-- It cannot appear in any field value, and because we chunk at
-- line boundaries (not arbitrary byte offsets) it always arrives
-- intact — never split across two packets.
local CHAR_SEP = "==END=="

local function SerializeFullDB(accountOnly)

    local entries = {}

    -- When accountOnly is true, only send characters whose account field
    -- matches this client's configured account number.  Characters with
    -- no account set are always included (they haven't been tagged yet).
    AltTrackerConfig = AltTrackerConfig or {}
    local myAccount = AltTrackerConfig.accountNumber

    for _, c in pairs(AltTrackerDB) do
        if type(c) == "table" and c.guid then
            if accountOnly and myAccount and myAccount ~= "" then
                local charAcct = c.account
                if charAcct and charAcct ~= "" and tostring(charAcct) ~= tostring(myAccount) then
                    -- Skip — belongs to a different account
                else
                    entries[#entries + 1] = SerializeChar(c)
                end
            else
                entries[#entries + 1] = SerializeChar(c)
            end
        end
    end

    -- Each entry is followed by a separator line.
    local lines = {}
    for _, entry in ipairs(entries) do
        lines[#lines + 1] = entry
        lines[#lines + 1] = CHAR_SEP
    end

    return table.concat(lines, "\n")

end

------------------------------------------------------------
-- Deserialize full DB
------------------------------------------------------------

local function DeserializeFullDB(payload, sender)

    local current = {}
    local rejected = 0

    for line in (payload .. "\n"):gmatch("([^\n]*)\n") do

        if line == CHAR_SEP then
            -- End of a character block — deserialize what we have.
            local msg = table.concat(current, "\n")
            current = {}

            local c = DeserializeChar(msg)

            if c and c.guid then

                -- Validate immutable fields before merging
                if not ValidateIncoming(c, sender) then
                    rejected = rejected + 1
                else
                    local existing = AltTrackerDB[c.guid] or {}

                    local existingTime = existing.lastUpdate or 0
                    local incomingTime = c.lastUpdate or 0

                    -- Only keep local copy if it is meaningfully newer (>60s).
                    -- Equal timestamps or small differences always accept the
                    -- incoming data — this handles the case where a record was
                    -- sent with incomplete gear (GetItemInfo cache miss) and a
                    -- corrected version arrives shortly after with the same stamp.
                    if existingTime - incomingTime <= 60 then
                        for k,v in pairs(c) do
                            existing[k] = v
                        end
                        AltTrackerDB[c.guid] = existing
                    end
                end

            end

        else
            current[#current + 1] = line
        end

    end

    if rejected > 0 then
        Print("|cffff8800Warning:|r " .. rejected .. " character(s) rejected due to validation failures.")
    end

    if AltTracker.RefreshSheet then
        AltTracker.RefreshSheet()
    end

end

------------------------------------------------------------
-- Send character  (line-aligned chunks — single messages cap at 255 bytes)
------------------------------------------------------------

local function SendCharacter()

    if not AltTracker.ScanCharacter then
        return
    end

    local char = AltTracker.ScanCharacter()

    if not char then
        return
    end

    -- Prefix with MSG_CHAR on its own line so the receiver can
    -- identify this stream as a single-character update.
    local payload = MSG_CHAR .. "\n" .. SerializeChar(char)

    local lines = {}
    for line in (payload .. "\n"):gmatch("([^\n]*)\n") do
        lines[#lines + 1] = line
    end

    local chunks = {}
    local current = {}
    local currentLen = 0

    for _, line in ipairs(lines) do
        local lineLen = #line + 1
        if currentLen + lineLen > MAX_CHUNK and #current > 0 then
            chunks[#chunks + 1] = table.concat(current, "\n") .. "\n"
            current = {}
            currentLen = 0
        end
        current[#current + 1] = line
        currentLen = currentLen + lineLen
    end
    if #current > 0 then
        chunks[#chunks + 1] = table.concat(current, "\n") .. "\n"
    end

    -- Checksum over the reassembled buffer (what the receiver will have)
    local checksum = ComputeChecksum(table.concat(chunks))

    for idx, chunk in ipairs(chunks) do
        C_Timer.After((idx - 1) * CHUNK_SEND_INTERVAL, function()
            C_ChatInfo.SendAddonMessage(
                PREFIX,
                MSG_CHUNK .. "|" .. chunk,
                "GUILD"
            )
        end)
    end

    -- DONE message carries the checksum: "DONE3|<hex>"
    C_Timer.After(#chunks * CHUNK_SEND_INTERVAL, function()
        C_ChatInfo.SendAddonMessage(PREFIX, MSG_DONE_V .. "|" .. checksum, "GUILD")
    end)

end

------------------------------------------------------------
-- Send full DB  (line-aligned chunks, throttled to avoid packet loss)
-- channel: "GUILD", "WHISPER", "PARTY", etc.
-- target:  required for WHISPER, nil otherwise
------------------------------------------------------------

local function SendFullDatabase(channel, target)

    channel = channel or "GUILD"

    -- By default only send characters from the current account.
    -- If sendAllAccounts is enabled in config, send everything.
    AltTrackerConfig = AltTrackerConfig or {}
    local accountOnly = not AltTrackerConfig.sendAllAccounts

    local payload = SerializeFullDB(accountOnly)

    local lines = {}
    for line in (payload .. "\n"):gmatch("([^\n]*)\n") do
        lines[#lines + 1] = line
    end

    local chunks = {}
    local current = {}
    local currentLen = 0

    for _, line in ipairs(lines) do
        local lineLen = #line + 1
        if currentLen + lineLen > MAX_CHUNK and #current > 0 then
            chunks[#chunks + 1] = table.concat(current, "\n") .. "\n"
            current = {}
            currentLen = 0
        end
        current[#current + 1] = line
        currentLen = currentLen + lineLen
    end
    if #current > 0 then
        chunks[#chunks + 1] = table.concat(current, "\n") .. "\n"
    end

    -- Checksum over the reassembled buffer (what the receiver will have)
    local checksum = ComputeChecksum(table.concat(chunks))

    for idx, chunk in ipairs(chunks) do
        C_Timer.After((idx - 1) * CHUNK_SEND_INTERVAL, function()
            C_ChatInfo.SendAddonMessage(
                PREFIX,
                MSG_CHUNK .. "|" .. chunk,
                channel,
                target
            )
        end)
    end

    -- DONE message now carries the checksum: "DONE3|<hex>"
    C_Timer.After(#chunks * CHUNK_SEND_INTERVAL, function()
        C_ChatInfo.SendAddonMessage(PREFIX, MSG_DONE_V .. "|" .. checksum, channel, target)
    end)

end

------------------------------------------------------------
-- Request sync
------------------------------------------------------------

local function RequestCharacters(channel, target)

    channel = channel or "GUILD"
    C_ChatInfo.SendAddonMessage(PREFIX, MSG_REQUEST_V, channel, target)

end

------------------------------------------------------------
-- Fan-out helpers — send to all configured targets
------------------------------------------------------------

local function BroadcastDB()
    local targets = GetSyncTargets()
    for _, t in ipairs(targets) do
        SendFullDatabase(t.channel, t.target)
    end
end

local function BroadcastRequest()
    local targets = GetSyncTargets()
    for _, t in ipairs(targets) do
        RequestCharacters(t.channel, t.target)
    end
end

local function ReceiveCharacter(c, sender)

    if not c or not c.guid then
        return
    end

    -- Validate immutable fields before merging
    if not ValidateIncoming(c, sender) then
        return
    end

    local existing = AltTrackerDB[c.guid] or {}

    for k,v in pairs(c) do
        existing[k] = v
    end

    AltTrackerDB[c.guid] = existing

    if AltTracker.RefreshSheet then
        AltTracker.RefreshSheet()
    end

end

------------------------------------------------------------
-- Frame
------------------------------------------------------------

local frame = CreateFrame("Frame")

frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("CHAT_MSG_ADDON")
frame:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
frame:RegisterEvent("GET_ITEM_INFO_RECEIVED")
frame:RegisterEvent("TRADE_SKILL_SHOW")
frame:RegisterEvent("TRADE_SKILL_UPDATE")
frame:RegisterEvent("TRADE_SKILL_CLOSE")
frame:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")

C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)

------------------------------------------------------------
-- Event handler
------------------------------------------------------------

frame:SetScript("OnEvent", function(self, event, ...)

    if event == "CHAT_MSG_ADDON" then

        local prefix, message, channel, sender = ...

        if prefix ~= PREFIX then
            return
        end

        ----------------------------------------------------
        -- Ignore our own packets
        ----------------------------------------------------

        -- In TBC, sender arrives as "Name-Realm". Strip the realm suffix before comparing.
        local senderName = sender and sender:match("^([^%-]+)") or ""
        if senderName == PLAYER_NAME then
            return
        end

        local cmd, payload = strsplit("|", message, 2)

        -- Versioned request — only reply to clients running the same protocol
        if cmd == MSG_REQUEST_V then
            local replyChannel = (channel == "WHISPER") and "WHISPER" or "GUILD"
            local replyTarget  = (channel == "WHISPER") and senderName or nil
            local delay = math.random(1, 3)
            C_Timer.After(delay, function()
                SendFullDatabase(replyChannel, replyTarget)
            end)
            return
        end

        -- Old unversioned request from a previous addon version — ignore
        if cmd == MSG_REQUEST or cmd == "REQ2" then
            Print("|cffff8800[AltTracker]|r Ignoring sync request from "..senderName.." (outdated addon version).")
            return
        end

        if cmd == MSG_CHAR and payload then

            -- MSG_CHAR is now sent as a chunked stream; this path is kept
            -- only for backward compatibility with older addon versions.
            local c = DeserializeChar(payload)

            if c then
                local senderShort = sender and sender:match("^([^%-]+)") or sender
                Print(senderShort .. " sent character data for " .. (c.name or "unknown") .. ".")
                ReceiveCharacter(c, senderShort)
            end

            return
        end

        if cmd == MSG_CHUNK then

            -- Normalize sender key (TBC sends "Name-Realm")
            local key = sender and sender:match("^([^%-]+)") or sender
            if not incomingBuffers[key] then
                -- Don't print here — we don't know if it's a valid versioned stream yet
            end
            incomingBuffers[key] =
                (incomingBuffers[key] or "") .. (payload or "")

            return
        end

        -- Versioned DONE — process the buffer
        -- In v3+ the payload carries the checksum: "DONE3|<hex>"
        if cmd == MSG_DONE_V then

            local key = sender and sender:match("^([^%-]+)") or sender
            local buffer = incomingBuffers[key]
            local remoteChecksum = payload  -- hex string sent by the sender

            if buffer and #buffer > 0 then

                -- Validate checksum if one was provided
                if remoteChecksum and remoteChecksum ~= "" then
                    local localChecksum = ComputeChecksum(buffer)
                    if localChecksum ~= remoteChecksum then
                        Print("|cffff0000Checksum mismatch|r from " .. key ..
                              " (expected " .. remoteChecksum ..
                              ", got " .. localChecksum ..
                              "). Data discarded — request a resync.")
                        incomingBuffers[key] = nil
                        return
                    end
                end

                if buffer:sub(1, 5) == MSG_CHAR .. "\n" then

                    local charPayload = buffer:sub(6)
                    local c = DeserializeChar(charPayload)

                    if c then
                        Print(key .. " sent character data for " .. (c.name or "unknown") .. ".")
                        ReceiveCharacter(c, key)
                    end

                else

                    Print("Receiving data from " .. key .. "...")

                    local before = 0
                    for _ in pairs(AltTrackerDB) do before = before + 1 end

                    DeserializeFullDB(buffer, key)

                    local after = 0
                    for _ in pairs(AltTrackerDB) do after = after + 1 end

                    local newChars = after - before
                    if newChars > 0 then
                        Print("Sync with " .. key .. " complete. " .. after .. " characters known (" .. newChars .. " new).")
                    else
                        Print("Sync with " .. key .. " complete. " .. after .. " characters known.")
                    end

                end
            end

            incomingBuffers[key] = nil

            return
        end

        -- Old unversioned DONE from a previous addon version — discard buffer silently
        if cmd == MSG_DONE or cmd == "DONE2" then
            local key = sender and sender:match("^([^%-]+)") or sender
            if incomingBuffers[key] then
                incomingBuffers[key] = nil
                Print("|cffff8800Warning:|r Discarded data from "..key.." (outdated addon version — please update AltTracker).")
            end
            return
        end

    end

    --------------------------------------------------------
    -- Login sync
    --------------------------------------------------------

    if event == "PLAYER_LOGIN" then

        C_Timer.After(2, function()

            if AltTracker.ScanCharacter then
                AltTracker.ScanCharacter()
            end

            local targets = GetSyncTargets()
            if #targets > 0 then
                Print("Syncing with whitelisted characters...")
                BroadcastDB()
                C_Timer.After(5, function()
                    BroadcastRequest()
                end)
            end

        end)

    end

    --------------------------------------------------------
    -- Rescan + resend when gear changes in-session
    --------------------------------------------------------

    if event == "PLAYER_EQUIPMENT_CHANGED" then
        -- Debounce: PLAYER_EQUIPMENT_CHANGED fires once per slot changed.
        -- Swapping weapons can fire it multiple times in quick succession.
        -- Cancel any pending scan/broadcast and restart the timer.
        if frame._equipTimer then
            frame._equipTimer:Cancel()
        end
        frame._equipTimer = C_Timer.NewTimer(3, function()
            frame._equipTimer = nil
            if AltTracker.ScanCharacter then
                AltTracker.ScanCharacter()
            end
            -- Refresh sheet locally but don't broadcast — gear data will
            -- sync on the next natural login or /alts command.
            if AltTracker.RefreshSheet then AltTracker.RefreshSheet() end
        end)
    end

    --------------------------------------------------------
    -- Retry pending gear slots when item cache is populated
    --------------------------------------------------------

    if event == "GET_ITEM_INFO_RECEIVED" then
        local itemID, success = ...
        if not success or not AltTracker.PendingGearLinks then return end

        local anyResolved = false
        for link, info in pairs(AltTracker.PendingGearLinks) do
            local quality, ilvl = select(3, GetItemInfo(link))
            if ilvl then
                local char = AltTrackerDB[info.guid]
                if char then
                    char["gear_"..info.key]  = ilvl
                    char["gearq_"..info.key] = quality or 0
                    anyResolved = true
                end
                AltTracker.PendingGearLinks[link] = nil
            end
        end

        -- Stamp lastUpdate once all pending slots resolve, but don't broadcast.
        -- The updated gear will go out on the next login sync.
        if anyResolved and not next(AltTracker.PendingGearLinks) then
            local guid = UnitGUID("player")
            local char = guid and AltTrackerDB[guid]
            if char then char.lastUpdate = time() end
            if AltTracker.RefreshSheet then AltTracker.RefreshSheet() end
        end
    end

    --------------------------------------------------------
    -- Scan profession CDs when tradeskill window opens/updates
    -- GetTradeSkillCooldown(i) is the only reliable source.
    --------------------------------------------------------

    if event == "TRADE_SKILL_CLOSE" then
        frame._tradeSkillOpen = false
        return
    end

    if event == "TRADE_SKILL_SHOW" then
        frame._tradeSkillOpen = true
    end

    if (event == "TRADE_SKILL_SHOW" or event == "TRADE_SKILL_UPDATE")
    and frame._tradeSkillOpen then
        local defs = AltTracker.ProfCooldownDefs
        if not defs or not GetNumTradeSkills then return end

        local guid = UnitGUID("player")
        local char = guid and AltTrackerDB[guid]
        if not char then return end

        local numSkills = GetNumTradeSkills()
        local updated = false

        -- Track which CD recipes this character actually knows.
        -- First clear all known_ flags for this profession window,
        -- then re-set the ones we find.  This way if a character
        -- unlearns a recipe (respec) the flag gets removed.
        local seenKeys = {}

        for i = 1, numSkills do
            local recipeName, recipeType = GetTradeSkillInfo(i)
            if recipeName and recipeType ~= "header" then
                local def = defs[recipeName]
                if def then
                    seenKeys[def.key] = true

                    -- Mark recipe as known
                    if not char["known_" .. def.key] then
                        char["known_" .. def.key] = 1
                        updated = true
                    end

                    local cdSeconds = GetTradeSkillCooldown(i) or 0
                    local newExpiry = cdSeconds > 0 and (time() + cdSeconds) or 0
                    if char[def.key] ~= newExpiry then
                        char[def.key] = newExpiry
                        updated = true
                    end
                end
            end
        end

        -- Clear known_ flags for CD recipes NOT found in this scan
        -- (handles recipe unlearning / profession respec)
        for _, def in pairs(defs) do
            if not seenKeys[def.key] and char["known_" .. def.key] then
                char["known_" .. def.key] = nil
                char[def.key] = nil  -- also clear the CD itself
                updated = true
            end
        end

        if updated then
            if AltTracker.RefreshSheet then AltTracker.RefreshSheet() end
            -- Don't broadcast here — sending chunked addon messages right after
            -- closing the tradeskill window triggers WOW51900319 disconnects.
            -- CDs will sync on next natural login/resync.
        end
        return
    end

    --------------------------------------------------------
    -- Re-scan CDs after a craft completes
    --------------------------------------------------------

    if event == "UNIT_SPELLCAST_SUCCEEDED" then
        local unit = ...
        if unit ~= "player" then return end
        C_Timer.After(0.5, function()
            if not frame._tradeSkillOpen then return end
            if not (GetNumTradeSkills and GetNumTradeSkills() > 0) then return end
            local guid = UnitGUID("player")
            local char = guid and AltTrackerDB[guid]
            if not char then return end
            local defs = AltTracker.ProfCooldownDefs
            if not defs then return end
            for i = 1, GetNumTradeSkills() do
                local recipeName, recipeType = GetTradeSkillInfo(i)
                if recipeName and recipeType ~= "header" then
                    local def = defs[recipeName]
                    if def then
                        local cdSeconds = GetTradeSkillCooldown(i) or 0
                        char[def.key] = cdSeconds > 0 and (time() + cdSeconds) or 0
                    end
                end
            end
            if AltTracker.RefreshSheet then AltTracker.RefreshSheet() end
            -- No broadcast here either — avoid flooding
        end)
        return
    end

end)

------------------------------------------------------------
-- Slash commands
------------------------------------------------------------

SLASH_ALTTRACKER1 = "/alts"
SLASH_ALTTRACKER2 = "/alttracker"

SlashCmdList["ALTTRACKER"] = function(args)

    local cmd, target = args:match("^(%S+)%s+(%S+)$")
    if not cmd then
        cmd = args:match("^(%S+)$")
    end
    cmd = cmd and cmd:lower() or ""

    ----------------------------------------------------
    -- /alts sync PlayerName
    ----------------------------------------------------

    if cmd == "sync" then
        if not target or target == "" then
            Print("Usage: /alts sync PlayerName")
            return
        end
        Print("Sending your data to " .. target .. " and requesting theirs...")
        SendFullDatabase("WHISPER", target)
        AltTrackerConfig = AltTrackerConfig or {}
        local accountOnly = not AltTrackerConfig.sendAllAccounts
        local sendTime = math.ceil(#SerializeFullDB(accountOnly) / MAX_CHUNK) * CHUNK_SEND_INTERVAL
        C_Timer.After(sendTime + 1, function()
            RequestCharacters("WHISPER", target)
        end)
        return
    end

    ----------------------------------------------------
    -- /alts account N  — set this client's account number
    ----------------------------------------------------

    if cmd == "account" then
        local num = tonumber(target)
        if not num then
            Print("Usage: /alts account 1   (or 2, 3, ...)")
            return
        end
        AltTrackerConfig = AltTrackerConfig or {}
        AltTrackerConfig.accountNumber = num
        Print("Account number set to " .. num .. ". It will be included on next scan/sync.")
        return
    end

    ----------------------------------------------------
    -- /alts export
    ----------------------------------------------------

    if cmd == "export" then
        if AltTracker.ShowExport then
            AltTracker.ShowExport()
        end
        return
    end

    ----------------------------------------------------
    -- /alts cleanup  — manually remove duplicate/corrupt DB entries
    ----------------------------------------------------

    if cmd == "cleanup" then
        CleanupDB()
        Print("DB wiped — kept only your current character. Requesting fresh data from peers...")
        if AltTracker.RefreshSheet then AltTracker.RefreshSheet() end
        -- Give the rescan a moment to complete before broadcasting
        C_Timer.After(1, function()
            BroadcastDB()
            C_Timer.After(3, function()
                BroadcastRequest()
            end)
        end)
        return
    end

    ----------------------------------------------------
    -- /alts config  — open the settings panel
    ----------------------------------------------------

    if cmd == "config" then
        if AltTracker.OpenConfig then
            AltTracker.OpenConfig()
        end
        return
    end

    ----------------------------------------------------
    -- /alts  (open sheet + sync via configured mode)
    ----------------------------------------------------

    if AltTracker.EnsureSheetVisible then
        AltTracker.EnsureSheetVisible()
    end

    local targets = GetSyncTargets()
    if #targets > 0 then
        Print("Requesting data from whitelisted characters...")
    end
    BroadcastRequest()

end