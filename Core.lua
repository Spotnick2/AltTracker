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
--
-- v3 → v4: chunked transmission now embeds a sequence number and total
--          chunk count in each CHUNK message, so the receiver can
--          reassemble in order and detect dropped packets.
-- v4 → v5: chunk bodies are now base64-encoded.  This eliminates
--          deterministic byte-mangling we were seeing on the addon
--          channel (most likely whitespace-/control-char normalization
--          somewhere in the chat pipeline) — encoding to base64 means
--          the wire bytes are pure printable ASCII from the
--          [A-Za-z0-9+/=] alphabet, none of which any sane chat
--          pipeline rewrites.  Receiver decodes back to bytes before
--          checksum validation.
local PROTOCOL_VERSION = "5"
local MSG_REQUEST_V = MSG_REQUEST .. PROTOCOL_VERSION   -- "REQ5"
local MSG_DONE_V    = MSG_DONE    .. PROTOCOL_VERSION   -- "DONE5"
local MSG_CHUNK_V   = MSG_CHUNK   .. "3"                -- "CHUNK3"

-- WoW addon messages are capped at 255 bytes.
-- Wire packet format: "CHUNK2|<seq>/<total>|<base64-encoded-body>"
--   Header worst case: "CHUNK2|9999/9999|" = 17 bytes
--   Base64 expansion:  ceil(N/3)*4 chars per N raw bytes (~33% growth)
--   Budget per packet: 255 - 17 = 238 base64 bytes available
--   Raw chunk size:    floor(238 / 4) * 3 = 177 bytes
-- Round down to 174 for a safety margin.  Result: 174 raw payload bytes
-- per chunk, encoded to 232 b64 chars, plus 17 byte header = 249 total
-- on the wire (well under the 255 cap).
local MAX_CHUNK = 174
local CHUNK_BURST_COUNT    = 8     -- packets allowed before we slow down
local CHUNK_BURST_INTERVAL = 0.1   -- seconds between burst packets
local CHUNK_STEADY_INTERVAL = 1.05 -- seconds between sustained packets

-- incomingBuffers[senderShort] = {
--   chunks = { [seq] = chunkBody, ... },   -- sparse; receiver fills as packets arrive
--   total  = N,                            -- total chunks announced (latest seen)
-- }
-- A sequenced reassembly buffer.  Replaces the previous single-string
-- buffer because chunks can arrive out of order on the addon channel
-- and silent reordering was producing checksum mismatches.
local incomingBuffers = {}

-- Set of senders we've already nagged about being on an outdated
-- protocol version, to avoid spamming the chat frame on every chunk.
local outdatedSenders = {}

-- Per-sender count of how many times we've auto-requested a resync
-- after detecting missing chunks.  Capped at 2 to prevent loops if
-- a peer is fundamentally broken.  Reset to nil after a successful
-- DONE.
local autoRetryCounts = {}

-- Per-peer time of the last sync request we sent.  Used to throttle
-- duplicate requests — if /alts is run again before the first sync
-- completes, or two events fire close together (PLAYER_LOGIN +
-- CHAT_MSG_SYSTEM peer-online), we don't want to spam REQ messages.
-- Keyed by peer name (no realm suffix).
local lastRequestedAt = {}
local REQUEST_THROTTLE = 300  -- 5 minutes between automatic re-requests

-- Stale-buffer cleanup.  If a sender's stream gets cut off mid-flight
-- (DC, /reload on their end, sender ran out of credits to keep sending,
-- etc.) we'd otherwise hold onto a partial buffer forever.  Every 60s
-- we sweep buffers whose lastTouched is older than 120s and drop them.
-- The threshold is generous because the rate-limited sender now paces
-- at ~1 chunk/sec, so a 100-character DB takes ~2 minutes legitimately.
C_Timer.NewTicker(60, function()
    local now = time()
    for key, buf in pairs(incomingBuffers) do
        if buf.lastTouched and (now - buf.lastTouched) > 120 then
            incomingBuffers[key] = nil
        end
    end
end)

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
                                      -- gearid_* stays included (compact + sync-safe)
        and k ~= "specIcon"            -- numeric fileID, client-specific
        then
            parts[#parts+1] = k .. ":" .. tostring(v)
        end
    end

    -- Plugin extensions: each registered plugin may contribute one line of
    -- opaque per-character data that will round-trip through sync.  The
    -- plugin is responsible for encoding its own data into a string with
    -- no newline characters.  Lines are stored as "plugin_<id>:<blob>".
    if AltTracker.plugins then
        for _, plugin in ipairs(AltTracker.plugins) do
            if plugin.OnSerialize and c.guid then
                local ok, blob = pcall(plugin.OnSerialize, c.guid)
                if ok and type(blob) == "string" and blob ~= "" and not blob:find("\n") then
                    parts[#parts+1] = "plugin_" .. plugin.id .. ":" .. blob
                end
            end
        end
    end

    return table.concat(parts, "\n")

end

------------------------------------------------------------
-- Deserialize character
------------------------------------------------------------

local function DeserializeChar(msg)

    local c = {}
    local pluginPayloads = nil  -- lazy-init

    for line in string.gmatch(msg, "([^\n]+)") do

        local k, v = line:match("^([^:]+):(.+)$")

        if k then
            local pid = k:match("^plugin_(.+)$")
            if pid then
                pluginPayloads = pluginPayloads or {}
                pluginPayloads[pid] = v
            else
                local num = tonumber(v)
                c[k] = num or v
            end
        end

    end

    if not c.guid then
        return
    end

    -- Dispatch any plugin payloads to their owners.  Done AFTER c.guid
    -- is confirmed so plugins can trust the character exists.
    if pluginPayloads and AltTracker.plugins then
        for _, plugin in ipairs(AltTracker.plugins) do
            local blob = pluginPayloads[plugin.id]
            if blob and plugin.OnDeserialize then
                pcall(plugin.OnDeserialize, c.guid, blob)
            end
        end
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

------------------------------------------------------------
-- Base64 codec
--
-- Chunks transmitted over WoW's addon channel are now base64-
-- encoded.  Reasoning: even though SendAddonMessage's docs
-- claim it transmits all bytes 1-255 verbatim, the user has
-- been seeing deterministic checksum mismatches with the
-- exact same hashes both sides every time, even when all
-- chunks arrived.  The likeliest culprit is some kind of
-- whitespace / control-character normalization happening
-- somewhere in the channel — leading/trailing whitespace
-- stripping is a common pattern in chat-server pipelines.
--
-- Encoding the chunk body as base64 sidesteps this entire
-- class of issues at the cost of a 33% size overhead.  Each
-- chunk's bytes after the header are now pure printable
-- ASCII from the base64 alphabet — A-Z, a-z, 0-9, +, /, =
-- — none of which any sane chat pipeline touches.
--
-- The encoding is plain RFC 4648 with `=` padding.
------------------------------------------------------------

local B64_ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local B64_DECODE = {}
for i = 1, #B64_ALPHABET do
    B64_DECODE[B64_ALPHABET:sub(i,i)] = i - 1
end

local function Base64Encode(s)
    if not s or s == "" then return "" end
    local out = {}
    local n = #s
    for i = 1, n, 3 do
        local b1 = string.byte(s, i)
        local b2 = string.byte(s, i+1) or 0
        local b3 = string.byte(s, i+2) or 0
        local n1 = math.floor(b1 / 4)
        local n2 = (b1 % 4) * 16 + math.floor(b2 / 16)
        local n3 = (b2 % 16) * 4 + math.floor(b3 / 64)
        local n4 = b3 % 64
        out[#out+1] = B64_ALPHABET:sub(n1+1, n1+1)
        out[#out+1] = B64_ALPHABET:sub(n2+1, n2+1)
        if i+1 <= n then
            out[#out+1] = B64_ALPHABET:sub(n3+1, n3+1)
        else
            out[#out+1] = "="
        end
        if i+2 <= n then
            out[#out+1] = B64_ALPHABET:sub(n4+1, n4+1)
        else
            out[#out+1] = "="
        end
    end
    return table.concat(out)
end

local function Base64Decode(s)
    if not s or s == "" then return "" end
    -- Strip any whitespace that might have crept in (defensive)
    s = s:gsub("%s", "")
    local out = {}
    local n = #s
    for i = 1, n, 4 do
        local c1 = s:sub(i,   i)
        local c2 = s:sub(i+1, i+1)
        local c3 = s:sub(i+2, i+2)
        local c4 = s:sub(i+3, i+3)
        local n1 = B64_DECODE[c1]
        local n2 = B64_DECODE[c2]
        local n3 = B64_DECODE[c3] or 0
        local n4 = B64_DECODE[c4] or 0
        if not n1 or not n2 then return nil end  -- malformed
        local b1 = n1 * 4 + math.floor(n2 / 16)
        local b2 = (n2 % 16) * 16 + math.floor(n3 / 4)
        local b3 = (n3 % 4) * 64 + n4
        out[#out+1] = string.char(b1)
        if c3 ~= "=" and c3 ~= "" then out[#out+1] = string.char(b2) end
        if c4 ~= "=" and c4 ~= "" then out[#out+1] = string.char(b3) end
    end
    return table.concat(out)
end


--
-- Called by SendCharacter / SendFullDatabase. Splits the payload into
-- chunks no larger than MAX_CHUNK, computes one checksum over the
-- reassembled stream, and sends each chunk as
--   "CHUNK2|<seq>/<total>|<chunkBody>"
-- followed by "DONE4|<checksum>".
--
-- Both sides must agree on the byte sequence in order — the sequence
-- numbers let the receiver reassemble even if packets arrive out of
-- order, and detect drops (a missing seq gets reported on DONE).
------------------------------------------------------------

local function ChunkAndSendPayload(payload, channel, target)

    local lines = {}
    for line in (payload .. "\n"):gmatch("([^\n]*)\n") do
        lines[#lines + 1] = line
    end

    -- Build chunks no larger than MAX_CHUNK bytes.  If a single line
    -- is itself longer than MAX_CHUNK (which happens for the
    -- plugin_<id>:<blob> line when a character has hundreds of recipes
    -- with reagents), we split it at byte boundaries.  The receiver
    -- doesn't care about line boundaries inside chunks — reassembly
    -- just concatenates back into the original byte stream — so it's
    -- safe to split anywhere.
    local chunks = {}
    local current = {}
    local currentLen = 0

    local function FlushCurrent()
        if #current > 0 then
            chunks[#chunks + 1] = table.concat(current, "\n") .. "\n"
            current = {}
            currentLen = 0
        end
    end

    for _, line in ipairs(lines) do
        local lineLen = #line + 1   -- include the trailing \n we'll add
        if lineLen <= MAX_CHUNK then
            -- Normal case: line fits within one chunk
            if currentLen + lineLen > MAX_CHUNK and #current > 0 then
                FlushCurrent()
            end
            current[#current + 1] = line
            currentLen = currentLen + lineLen
        else
            -- Oversized line: flush whatever's pending, then emit the
            -- line as standalone chunks of MAX_CHUNK raw bytes each.
            -- Split is at byte boundaries, NOT at character boundaries,
            -- so any UTF-8 multi-byte characters inside might land in
            -- two halves — that's OK because the receiver doesn't
            -- inspect chunks individually, only the reassembled stream.
            FlushCurrent()
            local pos = 1
            while pos <= #line do
                local segLen = math.min(MAX_CHUNK, #line - pos + 1)
                local segment = line:sub(pos, pos + segLen - 1)
                chunks[#chunks + 1] = segment
                pos = pos + segLen
            end
            -- Emit the line's terminating \n as a tiny standalone chunk
            -- so reassembly still produces "<line>\n" in the right place.
            chunks[#chunks + 1] = "\n"
        end
    end
    FlushCurrent()

    local total    = #chunks
    local checksum = ComputeChecksum(table.concat(chunks))

    -- Pace the send schedule to stay below the addon-channel rate
    -- limiter:
    --   * Burst:  the first CHUNK_BURST_COUNT packets fire at 100ms
    --             intervals — fits inside WoW's 10-message allowance.
    --   * Steady: anything past that paces at 1.05s/packet so we
    --             stay just under the 1/sec refill rate.
    --
    -- offsets[i] = absolute delay (seconds from now) to send chunk i.
    local offsets = {}
    do
        local t = 0
        for i = 1, total do
            if i > 1 then
                if i <= CHUNK_BURST_COUNT then
                    t = t + CHUNK_BURST_INTERVAL
                else
                    t = t + CHUNK_STEADY_INTERVAL
                end
            end
            offsets[i] = t
        end
    end
    local doneOffset = (offsets[total] or 0) + CHUNK_STEADY_INTERVAL

    for idx, chunk in ipairs(chunks) do
        local delay = offsets[idx]
        C_Timer.After(delay, function()
            local header = MSG_CHUNK_V .. "|" .. idx .. "/" .. total .. "|"
            -- Encode the raw chunk to base64 before transmission.
            -- This sidesteps any byte-level normalization the addon
            -- channel might apply (whitespace stripping, control-char
            -- rewriting, etc.) — we observed deterministic checksum
            -- mismatches in v4 even when all chunks arrived, with the
            -- exact same hashes both retries, which strongly suggested
            -- a deterministic transformation in transit.  Base64 keeps
            -- the wire bytes inside [A-Za-z0-9+/=] which no chat
            -- pipeline touches.
            local encoded = Base64Encode(chunk)
            local result = C_ChatInfo.SendAddonMessage(PREFIX, header .. encoded, channel, target)
            if result == false or result == nil then
                Print("|cffff8800[AltTracker]|r SendAddonMessage rejected chunk " ..
                      idx .. "/" .. total ..
                      " (likely server-side throttle). The receiver will request a resync.")
            end
        end)
    end

    -- DONE carries the checksum.  Sent ~one steady tick after the last
    -- chunk so the channel has time to actually deliver everything.
    C_Timer.After(doneOffset, function()
        C_ChatInfo.SendAddonMessage(PREFIX, MSG_DONE_V .. "|" .. checksum, channel, target)
    end)

end

------------------------------------------------------------
-- Send single-character update
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
    ChunkAndSendPayload(payload, "GUILD")

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
    ChunkAndSendPayload(payload, channel, target)

end

------------------------------------------------------------
-- Request sync
--
-- RequestCharacters fires a REQ to a single target.  It throttles
-- duplicate requests to the same peer within REQUEST_THROTTLE seconds
-- so /alts followed quickly by another /alts (or PLAYER_LOGIN +
-- CHAT_MSG_SYSTEM peer-online firing close together) doesn't double
-- up.  `force=true` bypasses the throttle for explicit user actions
-- like /alts sync.  Returns true if a REQ was actually sent.
------------------------------------------------------------

local function RequestCharacters(channel, target, force)

    channel = channel or "GUILD"

    if target then
        local now = time()
        if not force then
            local last = lastRequestedAt[target]
            if last and (now - last) < REQUEST_THROTTLE then
                return false
            end
        end
        lastRequestedAt[target] = now
    end

    C_ChatInfo.SendAddonMessage(PREFIX, MSG_REQUEST_V, channel, target)
    return true

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

------------------------------------------------------------
-- BroadcastRequest fires a REQ at every whitelisted peer.  Each
-- per-peer call goes through the throttle, so a peer we just talked
-- to gets skipped.  Returns the list of peers we actually pinged so
-- the caller can give meaningful user feedback.
------------------------------------------------------------

local function BroadcastRequest(force)
    local targets = GetSyncTargets()
    local pinged, skipped = {}, {}
    for _, t in ipairs(targets) do
        local ok = RequestCharacters(t.channel, t.target, force)
        if ok then
            pinged[#pinged + 1] = t.target
        else
            skipped[#skipped + 1] = t.target
        end
    end
    return pinged, skipped
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
frame:RegisterEvent("PLAYER_MONEY")
frame:RegisterEvent("PLAYER_UPDATE_RESTING")
frame:RegisterEvent("PLAYER_XP_UPDATE")
frame:RegisterEvent("TRADE_SKILL_SHOW")
frame:RegisterEvent("TRADE_SKILL_UPDATE")
frame:RegisterEvent("TRADE_SKILL_CLOSE")
frame:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
frame:RegisterEvent("CHAT_MSG_SYSTEM")    -- detect peer "X has come online" notifications

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
            -- Stagger replies with entropy from the receiver's name +
            -- current time, so that two clients on the same machine
            -- replying to a broadcast don't pick the same delay (math.random
            -- on its own would be seeded identically right after launch).
            -- Result: each peer gets a deterministic-but-distinct delay
            -- between 1.0 and 4.0 seconds.
            local seed = 0
            local me = UnitName("player") or ""
            for i = 1, #me do seed = seed + string.byte(me, i) end
            local delay = 1 + ((seed + (time() % 1000)) % 30) / 10
            C_Timer.After(delay, function()
                SendFullDatabase(replyChannel, replyTarget)
            end)
            return
        end

        -- Older request from a previous protocol version — ignore
        if cmd == MSG_REQUEST or cmd == "REQ2" or cmd == "REQ3" or cmd == "REQ4" then
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

        -- Old chunk from a peer running an earlier protocol — discard.
        -- We can't safely reassemble a v3 (no seq) or v4 (raw bytes)
        -- chunk under the v5 codec, so we tell the user to update both
        -- ends and move on.  Logged once per sender per session to
        -- avoid spamming the chat frame on multi-chunk streams.
        if cmd == MSG_CHUNK or cmd == "CHUNK2" then
            local key = sender and sender:match("^([^%-]+)") or sender
            outdatedSenders = outdatedSenders or {}
            if not outdatedSenders[key] then
                outdatedSenders[key] = true
                Print("|cffff8800[AltTracker]|r Ignoring chunked sync from " .. key ..
                      " (outdated addon version — please update AltTracker on both ends).")
            end
            return
        end

        -- v5 sequenced chunk: "CHUNK3|<seq>/<total>|<base64-body>"
        --
        -- We strip the "<seq>/<total>|" header off `payload`, then
        -- base64-decode the rest to recover the raw chunk bytes.
        -- The decoded bytes are what the sender originally hashed,
        -- so reassembly + checksum on the receiver hashes the same
        -- byte stream.  Out-of-order and repeated arrivals are both
        -- handled correctly: a repeat just overwrites the same slot;
        -- an out-of-order arrival lands at its real index.
        if cmd == MSG_CHUNK_V then

            local key = sender and sender:match("^([^%-]+)") or sender

            if not payload then return end
            local seqStr, totalStr, encodedBody = payload:match("^(%d+)/(%d+)|(.*)$")
            if not seqStr then
                -- Malformed header — treat as drop, log once and discard.
                Print("|cffff8800[AltTracker]|r Malformed chunk from "..key..", discarded.")
                return
            end
            local seq   = tonumber(seqStr)
            local total = tonumber(totalStr)
            if not seq or not total or seq < 1 or seq > total then
                Print("|cffff8800[AltTracker]|r Out-of-range chunk seq from "..key..", discarded.")
                return
            end

            local chunkBody = Base64Decode(encodedBody or "")
            if not chunkBody then
                Print("|cffff8800[AltTracker]|r Base64 decode failed on chunk " ..
                      seq .. "/" .. total .. " from " .. key .. ", discarding.")
                return
            end

            local buf = incomingBuffers[key]
            if not buf then
                buf = { chunks = {}, total = total, lastTouched = time() }
                incomingBuffers[key] = buf
            else
                buf.total = total           -- in case sender retried with a different count
                buf.lastTouched = time()
            end
            buf.chunks[seq] = chunkBody

            return
        end

        -- Versioned DONE — reassemble the buffer in seq order, verify
        -- completeness, then run the checksum.  Missing chunks are
        -- reported by index so the user / sender knows what got dropped.
        if cmd == MSG_DONE_V then

            local key = sender and sender:match("^([^%-]+)") or sender
            local buf = incomingBuffers[key]
            local remoteChecksum = payload

            if buf and buf.total and buf.total > 0 then

                -- Check completeness first
                local missing = {}
                for i = 1, buf.total do
                    if buf.chunks[i] == nil then
                        missing[#missing + 1] = i
                    end
                end

                if #missing > 0 then
                    -- Truncate the missing-chunk list in the printed
                    -- message so a 200-chunk stream with 50 drops doesn't
                    -- flood the chat frame.
                    local detail
                    if #missing <= 8 then
                        detail = table.concat(missing, ",")
                    else
                        local head = {}
                        for i = 1, 8 do head[i] = missing[i] end
                        detail = table.concat(head, ",") .. ",… (+" .. (#missing - 8) .. " more)"
                    end

                    -- Auto-retry: ask the sender for a fresh stream up
                    -- to 2 times before giving up.  The retry counter is
                    -- per-sender so two senders dropping at once each get
                    -- their own budget.  A successful reassembly elsewhere
                    -- will reset the counter (we tear down the buffer at
                    -- the end of every successful DONE).
                    autoRetryCounts = autoRetryCounts or {}
                    autoRetryCounts[key] = (autoRetryCounts[key] or 0) + 1
                    if autoRetryCounts[key] <= 2 then
                        Print("|cffff8800Sync incomplete|r from " .. key ..
                              " — " .. #missing .. "/" .. buf.total ..
                              " chunks missing (" .. detail ..
                              "). Auto-requesting resync (attempt " ..
                              autoRetryCounts[key] .. "/2).")
                        incomingBuffers[key] = nil
                        -- Send a fresh REQ4 to the same peer
                        C_Timer.After(2, function()
                            C_ChatInfo.SendAddonMessage(PREFIX, MSG_REQUEST_V, "WHISPER", key)
                        end)
                    else
                        Print("|cffff0000Sync failed|r from " .. key ..
                              " — " .. #missing .. "/" .. buf.total ..
                              " chunks missing (" .. detail ..
                              ") after 2 auto-retries. Try /alts sync " ..
                              key .. " manually.")
                        autoRetryCounts[key] = nil
                        incomingBuffers[key] = nil
                    end
                    return
                end

                -- All present; reassemble in order.
                local ordered = {}
                for i = 1, buf.total do
                    ordered[i] = buf.chunks[i]
                end
                local buffer = table.concat(ordered)

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

            -- Successful (or empty) DONE — clear retry budget for this peer
            if autoRetryCounts then autoRetryCounts[key] = nil end
            incomingBuffers[key] = nil
            return
        end

        -- Old unversioned DONE from a previous addon version — discard buffer silently
        if cmd == MSG_DONE or cmd == "DONE2" or cmd == "DONE3" or cmd == "DONE4" then
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

        -- Re-register the prefix on login.  Calling it at file load
        -- time isn't always sufficient — same-machine dual-boxing has
        -- racy behaviour where the prefix isn't actually registered
        -- with the server until the client is in-world, so until we
        -- get this call to succeed at login time some early CHAT_MSG_ADDON
        -- traffic was being silently dropped on the receiver side.
        C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)

        C_Timer.After(2, function()

            if AltTracker.ScanCharacter then
                AltTracker.ScanCharacter()
            end

            local targets = GetSyncTargets()
            if #targets > 0 then
                -- Pull-only model: ASK peers for their data rather than
                -- blindly pushing.  Pushing on login created a same-machine
                -- race where two clients started transmitting before
                -- either receiver was primed; the requester-initiated
                -- model guarantees the requester is listening when the
                -- response arrives.
                --
                -- Caveat: this only works when the peer is online at the
                -- moment we request.  If they aren't, our REQ goes
                -- nowhere — that's why CHAT_MSG_SYSTEM also fires a
                -- re-request when a peer comes online later.
                local pinged = BroadcastRequest()
                if #pinged > 0 then
                    Print("Requesting data from: " .. table.concat(pinged, ", "))
                end
            end

        end)

    end

    --------------------------------------------------------
    -- Peer-online re-request
    --
    -- Fixes the worst failure mode of pull-only login sync:
    -- if Memphisto logs in before Drakuzo, Memphisto's REQ at
    -- PLAYER_LOGIN goes nowhere (Drakuzo isn't listening yet),
    -- and Memphisto would never re-attempt — leaving Memphisto
    -- with stale data forever.
    --
    -- When the server tells us a friend/guildie has come online,
    -- we check if they're in our whitelist and, if so, fire a
    -- fresh REQ at them.  The throttle in RequestCharacters
    -- prevents this from double-firing if PLAYER_LOGIN's REQ
    -- happens to also be in flight.
    --
    -- Player-name extraction works off the |Hplayer:NAME|h
    -- hyperlink embedded in the system message, which is
    -- locale-independent.  We don't try to match the English
    -- "has come online" text — that breaks on non-English
    -- clients.
    --------------------------------------------------------

    if event == "CHAT_MSG_SYSTEM" then
        local text = ...
        if not text or type(text) ~= "string" then return end

        -- "X has come online" notifications carry a player link.
        -- "X has gone offline" also carries one — guard against the
        -- gone-offline case so we don't fire a REQ at someone who
        -- just left.  Both messages are sourced from
        -- ERR_FRIEND_ONLINE_SS / ERR_FRIEND_OFFLINE_S in the WoW
        -- globals; the offline string contains "offline" in every
        -- locale (Blizzard reuses the English root in localized
        -- forms in most locales — but as a safety net we also check
        -- ERR_FRIEND_OFFLINE_S literal substring presence).
        local offlineFmt = ERR_FRIEND_OFFLINE_S or ""
        local offlineMarker = offlineFmt:gsub("%%s", ""):gsub("[%[%]%(%)%.%%%+%-%*%?%^%$]", ""):match("(%S[%S%s]*%S)") or "offline"
        if offlineMarker ~= "" and text:find(offlineMarker, 1, true) then
            return
        end

        local peerName = text:match("|Hplayer:([^:|]+)")
        if not peerName then return end

        AltTrackerConfig = AltTrackerConfig or {}
        local whitelist = AltTrackerConfig.whitelist or {}
        local inWhitelist = false
        for _, w in ipairs(whitelist) do
            if w == peerName then inWhitelist = true; break end
        end
        if not inWhitelist then return end

        -- Slight delay so the peer's CHAT_MSG_ADDON handler is fully
        -- primed before we fire — same reasoning as the 2s delay at
        -- PLAYER_LOGIN.
        C_Timer.After(3, function()
            local sent = RequestCharacters("WHISPER", peerName)
            if sent then
                Print(peerName .. " came online — requesting data.")
            end
        end)
        return
    end
    -- (e.g. looting, selling, buying, mailing).  A full ScanCharacter
    -- is not needed — just overwrite the money field directly.
    --------------------------------------------------------

    if event == "PLAYER_MONEY" then
        local guid = UnitGUID("player")
        if guid and AltTrackerDB[guid] then
            AltTrackerDB[guid].money = GetMoney()
            if AltTracker.RefreshSheet then AltTracker.RefreshSheet() end
        end
        return
    end

    --------------------------------------------------------
    -- Rested-XP snapshot refresh
    --
    -- We re-snapshot whenever the player enters or leaves a rested
    -- (inn/city) area, and whenever XP changes (which catches rested
    -- being consumed during play).  We deliberately DO NOT refresh on
    -- PLAYER_LOGOUT — by the time it fires the player frame is being
    -- torn down and GetXPExhaustion() / IsResting() frequently return
    -- bogus zero values, which was previously overwriting good data
    -- with garbage just before SavedVariables were written.
    --
    -- Guarded reads: if GetXPExhaustion returns 0 while the player is
    -- below cap AND the stored snapshot was non-zero AND very recent
    -- (<5s ago), we treat the 0 as transient (likely fired during a
    -- loading transition) and skip the write.
    --------------------------------------------------------

    if event == "PLAYER_UPDATE_RESTING" or event == "PLAYER_XP_UPDATE" then
        local guid = UnitGUID("player")
        local char = guid and AltTrackerDB[guid]
        if char then
            local liveRest = GetXPExhaustion() or 0
            local liveMax  = UnitXPMax("player") or 1
            local lvl      = UnitLevel("player") or 0

            -- Suspicious-zero guard.  Only accept a zero read if we have
            -- a prior non-zero snapshot that is very recent; a fresh zero
            -- between resting-state flips is legit, but a zero right on
            -- PLAYER_XP_UPDATE when rested was previously e.g. 40% is
            -- almost certainly a transient loading-screen read.
            local prevPct  = char.restPercent or 0
            local prevTime = char.restTimestamp or 0
            local elapsed  = time() - prevTime
            local suspicious = (liveRest == 0) and (prevPct > 5) and (elapsed < 5) and (lvl < 70)

            if not suspicious then
                char.restXP        = liveRest
                char.xpMax         = liveMax
                char.restPercent   = math.floor((liveRest / liveMax) * 100)
                char.restedArea    = IsResting and IsResting() or false
                char.restTimestamp = time()
            end
        end
        return
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

------------------------------------------------------------
-- Plugin registration API
-- Other addons can register themselves as AltTracker plugins.
-- Each plugin is a table with the following fields:
--   id         (string)   unique identifier, used as the sidebar button key
--   label      (string)   sidebar button label
--   icon       (string)   path to a texture shown on the sidebar button
--   OnActivate (function) called when the user clicks this plugin's sidebar button;
--                         receives the AltTracker main frame as the first argument
--   OnDeactivate (function, optional) called when another section/plugin is selected
------------------------------------------------------------

AltTracker.plugins = AltTracker.plugins or {}

function AltTracker.RegisterPlugin(plugin)
    if not plugin or not plugin.id or not plugin.label or not plugin.OnActivate then
        DEFAULT_CHAT_FRAME:AddMessage("|cff00ccff[AltTracker]|r RegisterPlugin: missing required fields (id, label, OnActivate).")
        return
    end
    -- Prevent duplicate registration across reloads
    for _, p in ipairs(AltTracker.plugins) do
        if p.id == plugin.id then return end
    end
    table.insert(AltTracker.plugins, plugin)
    -- If the sheet is already built, notify it so it can add the button live
    if AltTracker.AddPluginButton then
        AltTracker.AddPluginButton(plugin)
    end
end

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
    -- /alts sync [PlayerName]
    --
    -- With a target: send our data to them AND request theirs back.
    -- Both directions, useful for forcing a fresh exchange.
    --
    -- Without a target: fire a REQ to every whitelisted peer.  This
    -- is the manual equivalent of what PLAYER_LOGIN does at startup
    -- and what CHAT_MSG_SYSTEM does on peer-online; we use `force`
    -- so the throttle doesn't suppress an explicit user-initiated
    -- request.
    ----------------------------------------------------

    if cmd == "sync" then
        if not target or target == "" then
            local pinged, skipped = BroadcastRequest(true)
            if #pinged == 0 and #skipped == 0 then
                Print("No whitelisted peers configured. Add some with /alts whitelist <name>.")
            elseif #pinged == 0 then
                Print("No requests sent (all whitelisted peers throttled).")
            else
                Print("Requesting data from: " .. table.concat(pinged, ", "))
            end
            return
        end
        Print("Sending your data to " .. target .. " and requesting theirs...")
        SendFullDatabase("WHISPER", target)
        AltTrackerConfig = AltTrackerConfig or {}
        local accountOnly = not AltTrackerConfig.sendAllAccounts
        local nChunks = math.ceil(#SerializeFullDB(accountOnly) / MAX_CHUNK)
        -- Mirror the pacing in ChunkAndSendPayload: first CHUNK_BURST_COUNT
        -- chunks at burst rate, the rest at steady rate.  This is just an
        -- estimate so the request goes out roughly when the data finishes.
        local burst  = math.min(nChunks, CHUNK_BURST_COUNT)
        local steady = math.max(nChunks - CHUNK_BURST_COUNT, 0)
        local sendTime = (burst - 1) * CHUNK_BURST_INTERVAL + steady * CHUNK_STEADY_INTERVAL
        C_Timer.After(sendTime + 1, function()
            RequestCharacters("WHISPER", target, true)
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
                BroadcastRequest(true)   -- force: user just wiped DB, bypass throttle
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
    --
    -- Bare /alts opens the AltTracker window and pings whitelisted
    -- peers for a fresh sync — but goes through the same throttle
    -- machinery, so spamming /alts won't carpet-bomb the network.
    -- Throttled peers get silently skipped here (no message), since
    -- the user just opened the UI and doesn't necessarily care that
    -- a recent sync is still being respected.
    ----------------------------------------------------

    if AltTracker.EnsureSheetVisible then
        AltTracker.EnsureSheetVisible()
    end

    local pinged = BroadcastRequest()
    if #pinged > 0 then
        Print("Requesting data from: " .. table.concat(pinged, ", "))
    end

end
