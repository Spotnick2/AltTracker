------------------------------------------------------------
-- test_comm.lua — AltTracker sync/communication protocol tests.
--
-- Exercises the wire format in Core.lua (base64 codec, checksum,
-- character + full-DB serialization, and the chunk -> reassemble
-- receive path) with no game client, via the tests/wow_stubs.lua mock
-- and the AltTracker._test seam.
--
-- Run from the repo root with the Lua 5.1 interpreter:
--   & 'C:\Program Files (x86)\Lua\5.1\lua.exe' tests\test_comm.lua
------------------------------------------------------------

dofile("tests/wow_stubs.lua")

-- SavedVariables the addon expects to already exist.
AltTracker       = {}
AltTrackerDB     = {}
AltTrackerConfig = {}

assert(loadfile("Core.lua"))()

local T       = AltTracker._test
local PREFIX  = T.PREFIX
local onEvent = T.frame:GetScript("OnEvent")

------------------------------------------------------------
-- Tiny assert harness (ParseBuddy style)
------------------------------------------------------------

local testsRun, failures = 0, 0
local function check(cond, msg)
    testsRun = testsRun + 1
    if not cond then
        failures = failures + 1
        print("  FAIL: " .. (msg or "assertion failed"))
    end
end
local function eq(a, b, msg)
    check(a == b, (msg or "values differ") ..
        " (expected " .. tostring(b) .. ", got " .. tostring(a) .. ")")
end

-- Deliver a raw wire message to the receive handler as if from `sender`.
local function receive(message, sender)
    onEvent(T.frame, "CHAT_MSG_ADDON", PREFIX, message, "WHISPER", sender or "Peer-Realm")
end

local function chatHas(substr)
    for _, line in ipairs(WoW.chat) do
        if line:find(substr, 1, true) then return true end
    end
    return false
end

local function dbCount()
    local n = 0
    for _ in pairs(AltTrackerDB) do n = n + 1 end
    return n
end

-- Split captured wire into its CHUNK messages and the DONE message.
local CHUNK_PREFIX = T.MSG_CHUNK_V .. "|"
local function splitWire(messages)
    local chunks, done = {}, nil
    for _, m in ipairs(messages) do
        if m:sub(1, #CHUNK_PREFIX) == CHUNK_PREFIX then chunks[#chunks + 1] = m
        else done = m end
    end
    return chunks, done
end

-- Pull the stream id out of a captured CHUNK message.
local function sidOf(chunkMessage)
    return chunkMessage:match("^" .. T.MSG_CHUNK_V .. "|(%d+)|")
end

-- Populate AltTrackerDB with n fresh characters using a unique guid prefix.
local function seedDB(prefix, n)
    AltTrackerDB = {}
    for i = 1, n do
        local g = prefix .. i
        AltTrackerDB[g] = { guid = g, name = "Char" .. i, class = "WARRIOR",
                            level = 60 + i, ilvl = 100 + i, lastUpdate = 1000 }
    end
end

------------------------------------------------------------
-- 1. Base64 codec
------------------------------------------------------------

eq(T.Base64Encode("Man"), "TWFu", "base64 vector: Man")
eq(T.Base64Encode("Ma"),  "TWE=", "base64 vector: Ma")
eq(T.Base64Encode("M"),   "TQ==", "base64 vector: M")
eq(T.Base64Encode(""),    "",     "base64 of empty string")

for _, s in ipairs({
    "", "a", "ab", "abc", "abcd",
    "guid:Player-1\nname:Bob\nlevel:70",
    string.char(0, 1, 2, 127, 200, 254, 255),
}) do
    eq(T.Base64Decode(T.Base64Encode(s)), s, "base64 round-trip (len " .. #s .. ")")
end

------------------------------------------------------------
-- 2. Checksum
------------------------------------------------------------

eq(T.ComputeChecksum("hello"), T.ComputeChecksum("hello"), "checksum is deterministic")
check(T.ComputeChecksum("hello") ~= T.ComputeChecksum("hellp"), "checksum reacts to a 1-byte change")
eq(#T.ComputeChecksum("anything at all"), 8, "checksum is 8 hex chars")

------------------------------------------------------------
-- 3. Character serialize / deserialize round-trip
------------------------------------------------------------

local char = {
    guid = "Player-4-0001", name = "Bob", class = "WARRIOR",
    level = 70, ilvl = 123.6, account = 1, lastUpdate = 1000,
    gearlink_head = "|Hitem:12345|h[Helm]|h",  -- must be excluded (local-only)
    specIcon = 98765,                            -- must be excluded (client-specific)
    someTable = { nested = true },               -- must be excluded (table)
}
local s = T.SerializeChar(char)
check(not s:find("gearlink_head", 1, true), "gearlink_ fields excluded from serialization")
check(not s:find("specIcon", 1, true),      "specIcon excluded from serialization")
check(not s:find("someTable", 1, true),     "table-valued fields excluded from serialization")

local d = T.DeserializeChar(s)
eq(d.guid,  "Player-4-0001", "guid round-trips")
eq(d.name,  "Bob",           "name round-trips")
eq(d.class, "WARRIOR",       "class round-trips")
eq(d.level, 70,              "integer field round-trips as a number")
eq(d.ilvl,  123.6,           "float field round-trips as a number")
eq(d.lastUpdate, 1000,       "lastUpdate round-trips")
check(T.DeserializeChar("name:NoGuid\nlevel:10") == nil, "record without a guid is rejected")

------------------------------------------------------------
-- 4. Full-DB serialize / deserialize round-trip
------------------------------------------------------------

seedDB("Player-DB-", 3)
local payload = T.SerializeFullDB(false)
local _, sepCount = payload:gsub(T.CHAR_SEP, "")
eq(sepCount, 3, "one ==END== separator per character")

AltTrackerDB = {}
T.DeserializeFullDB(payload, "Peer")
eq(dbCount(), 3, "all characters restored from full-DB payload")
eq(AltTrackerDB["Player-DB-2"] and AltTrackerDB["Player-DB-2"].name, "Char2", "a specific char restored")
eq(AltTrackerDB["Player-DB-1"].level, 61, "numeric field restored as a number")

------------------------------------------------------------
-- 5. Validation: class change for an existing guid is rejected
------------------------------------------------------------

WoW.reset()
AltTrackerDB = { ["Player-V-1"] = { guid = "Player-V-1", name = "Vee", class = "MAGE", level = 70, lastUpdate = 500 } }
local badPayload = T.SerializeChar(
    { guid = "Player-V-1", name = "Vee", class = "WARRIOR", level = 70, lastUpdate = 600 }
) .. "\n" .. T.CHAR_SEP
T.DeserializeFullDB(badPayload, "Peer")
eq(AltTrackerDB["Player-V-1"].class, "MAGE", "class change is rejected — original retained")
check(chatHas("Rejected"), "class-change rejection is reported to the user")

------------------------------------------------------------
-- 6. Last-write-wins timestamp merge
------------------------------------------------------------

AltTrackerDB = { ["Player-T-1"] = { guid = "Player-T-1", name = "Tee", class = "PRIEST", level = 70, ilvl = 200, lastUpdate = 1000 } }
-- Incoming is >60s OLDER than local: keep local.
T.DeserializeFullDB(T.SerializeChar(
    { guid = "Player-T-1", name = "Tee", class = "PRIEST", level = 70, ilvl = 50, lastUpdate = 900 }
) .. "\n" .. T.CHAR_SEP, "Peer")
eq(AltTrackerDB["Player-T-1"].ilvl, 200, "older incoming (>60s) does not overwrite newer local")
-- Incoming within 60s: accept.
T.DeserializeFullDB(T.SerializeChar(
    { guid = "Player-T-1", name = "Tee", class = "PRIEST", level = 70, ilvl = 250, lastUpdate = 970 }
) .. "\n" .. T.CHAR_SEP, "Peer")
eq(AltTrackerDB["Player-T-1"].ilvl, 250, "incoming within 60s overwrites local")

------------------------------------------------------------
-- 7. End-to-end wire round-trip: chunk -> reassemble
------------------------------------------------------------

WoW.reset()
seedDB("Player-W-", 6)
T.ChunkAndSendPayload(T.SerializeFullDB(false), "WHISPER", "Wire")
WoW.flushTimers()                       -- fire the paced C_Timer.After sends
local wire = WoW.sentMessages()
local chunks, done = splitWire(wire)
check(#chunks >= 2, "a 6-character DB spans multiple chunks")
check(done ~= nil, "a DONE message is sent after the chunks")

AltTrackerDB = {}
WoW.chat = {}
for _, m in ipairs(wire) do receive(m, "Wire-Realm") end
check(not chatHas("mismatch"), "clean round-trip has no checksum mismatch")
check(not chatHas("missing"),  "clean round-trip reports no missing chunks")
eq(dbCount(), 6, "all 6 characters reassembled from the wire")
eq(AltTrackerDB["Player-W-3"] and AltTrackerDB["Player-W-3"].name, "Char3", "a specific char survived the wire round-trip")

------------------------------------------------------------
-- 8. Out-of-order chunk delivery still reassembles
------------------------------------------------------------

AltTrackerDB = {}
WoW.chat = {}
for i = #chunks, 1, -1 do receive(chunks[i], "Wire-Realm") end  -- reversed
receive(done, "Wire-Realm")
check(not chatHas("mismatch"), "out-of-order delivery still checksums correctly")
eq(dbCount(), 6, "out-of-order chunks reassemble to the full DB")

------------------------------------------------------------
-- 9. Dropped chunk is detected and triggers an auto-resync
------------------------------------------------------------

WoW.reset()
seedDB("Player-D-", 6)
T.ChunkAndSendPayload(T.SerializeFullDB(false), "WHISPER", "Drop")
WoW.flushTimers()
local dChunks, dDone = splitWire(WoW.sentMessages())
check(#dChunks >= 2, "need multiple chunks to simulate a drop")

AltTrackerDB = {}
WoW.chat = {}
WoW.sent = {}
for i = 1, #dChunks - 1 do receive(dChunks[i], "Drop-Realm") end  -- drop the last chunk
receive(dDone, "Drop-Realm")
check(chatHas("missing") or chatHas("incomplete"), "a missing chunk is detected and reported")
eq(dbCount(), 0, "DB is not updated when a chunk is missing")
WoW.flushTimers()  -- run the queued resync request
local reqSent = false
for _, m in ipairs(WoW.sentMessages()) do
    if m == T.MSG_REQUEST_V then reqSent = true end
end
check(reqSent, "receiver auto-requests a resync after a drop")

------------------------------------------------------------
-- 10. Checksum mismatch discards the data AND auto-requests a resync (H2)
------------------------------------------------------------

WoW.reset()
seedDB("Player-C-", 3)
T.ChunkAndSendPayload(T.SerializeFullDB(false), "WHISPER", "Corrupt")
WoW.flushTimers()
local cChunks = splitWire(WoW.sentMessages())
local cSid = sidOf(cChunks[1])

AltTrackerDB = {}
WoW.chat = {}
WoW.sent = {}
for _, m in ipairs(cChunks) do receive(m, "Corrupt-Realm") end
receive(T.MSG_DONE_V .. "|" .. cSid .. "|DEADBEEF", "Corrupt-Realm")  -- correct sid, wrong checksum
check(chatHas("mismatch"), "checksum mismatch is detected")
eq(dbCount(), 0, "data is discarded on checksum mismatch")
WoW.flushTimers()   -- run the queued resync request
local cReq = false
for _, m in ipairs(WoW.sentMessages()) do
    if m == T.MSG_REQUEST_V then cReq = true end
end
check(cReq, "checksum mismatch now auto-requests a resync (H2 fix)")

------------------------------------------------------------
-- 11. Packets from ourselves are ignored
------------------------------------------------------------

WoW.reset()
AltTrackerDB = {}
receive(T.MSG_CHUNK_V .. "|1|1/1|" .. T.Base64Encode("guid:Player-Self\nname:Me\n"), "Tester-Realm")
receive(T.MSG_DONE_V .. "|1|00000000", "Tester-Realm")
eq(dbCount(), 0, "our own packets (sender == player) are ignored")

------------------------------------------------------------
-- 12. Account-only serialization filter
------------------------------------------------------------

WoW.reset()
AltTrackerConfig = { accountNumber = 2 }
AltTrackerDB = {
    ["Player-Acct-mine"]  = { guid = "Player-Acct-mine",  name = "Mine",  class = "MAGE",   level = 70, account = 2, lastUpdate = 1 },
    ["Player-Acct-other"] = { guid = "Player-Acct-other", name = "Other", class = "ROGUE",  level = 70, account = 5, lastUpdate = 1 },
    ["Player-Acct-untag"] = { guid = "Player-Acct-untag", name = "Untag", class = "PRIEST", level = 70,              lastUpdate = 1 },
}
local mineOnly = T.SerializeFullDB(true)
check(mineOnly:find("Player-Acct-mine",  1, true), "account filter includes my-account char")
check(mineOnly:find("Player-Acct-untag", 1, true), "account filter includes untagged char")
check(not mineOnly:find("Player-Acct-other", 1, true), "account filter excludes a different account's char")
check(T.SerializeFullDB(false):find("Player-Acct-other", 1, true), "unfiltered serialize includes every account")

------------------------------------------------------------
-- 13. Oversized line is byte-split across chunks and reassembled byte-exact
------------------------------------------------------------

WoW.reset()
local bigVal = string.rep("Z", 400)   -- one field far larger than MAX_CHUNK
check(#("notes:" .. bigVal) > T.MAX_CHUNK, "the notes line exceeds MAX_CHUNK (" .. T.MAX_CHUNK .. ")")
AltTrackerDB = { ["Player-Big-1"] = { guid = "Player-Big-1", name = "Big", class = "WARRIOR", level = 70, notes = bigVal, lastUpdate = 1000 } }
T.ChunkAndSendPayload(T.SerializeFullDB(false), "WHISPER", "Big")
WoW.flushTimers()
local bigChunks = splitWire(WoW.sentMessages())
check(#bigChunks >= 3, "an oversized line is split into several chunks")
AltTrackerDB = {}
WoW.chat = {}
for _, m in ipairs(WoW.sentMessages()) do receive(m, "Big-Realm") end
check(not chatHas("mismatch"), "oversized-line stream checksums correctly")
eq(AltTrackerDB["Player-Big-1"] and AltTrackerDB["Player-Big-1"].notes, bigVal, "oversized field value reassembled byte-exact")

------------------------------------------------------------
-- 14. Merge clears stale profession fields when a peer drops a profession
------------------------------------------------------------

WoW.reset()
AltTrackerDB = { ["Player-Prof-1"] = { guid = "Player-Prof-1", name = "Pro", class = "WARRIOR", level = 70, prof1 = "Mining", prof_Mining = 300, lastUpdate = 1000 } }
T.DeserializeFullDB(T.SerializeChar(
    { guid = "Player-Prof-1", name = "Pro", class = "WARRIOR", level = 70, lastUpdate = 1000 }
) .. "\n" .. T.CHAR_SEP, "Peer")
eq(AltTrackerDB["Player-Prof-1"].prof_Mining, nil, "stale prof_ field cleared on merge")
eq(AltTrackerDB["Player-Prof-1"].prof1, nil, "stale prof1 cleared on merge")

------------------------------------------------------------
-- 15. Plugin per-character payload round-trips through serialization
------------------------------------------------------------

WoW.reset()
local delivered = {}
AltTracker.plugins = {
    { id = "demo",
      OnSerialize   = function(guid) return "blob-for:" .. guid end,
      OnDeserialize = function(guid, blob) delivered[guid] = blob end },
}
local ps = T.SerializeChar({ guid = "Player-Plug-1", name = "Plug", class = "MAGE", level = 70, lastUpdate = 1 })
check(ps:find("plugin_demo:blob-for:Player-Plug-1", 1, true), "plugin data serialized as plugin_<id>:<blob>")
T.DeserializeChar(ps)
eq(delivered["Player-Plug-1"], "blob-for:Player-Plug-1", "plugin OnDeserialize receives its blob for the char")
AltTracker.plugins = {}   -- reset so it doesn't affect other cases

------------------------------------------------------------
-- 16. Name change for an existing guid is rejected
------------------------------------------------------------

WoW.reset()
AltTrackerDB = { ["Player-Name-1"] = { guid = "Player-Name-1", name = "Alice", class = "MAGE", level = 70, lastUpdate = 500 } }
T.DeserializeFullDB(T.SerializeChar(
    { guid = "Player-Name-1", name = "Bob", class = "MAGE", level = 70, lastUpdate = 600 }
) .. "\n" .. T.CHAR_SEP, "Peer")
eq(AltTrackerDB["Player-Name-1"].name, "Alice", "name change rejected — original retained")
check(chatHas("name changed") or chatHas("Rejected"), "name-change rejection reported")

------------------------------------------------------------
-- 17. Malformed / out-of-range chunks are discarded and reported
------------------------------------------------------------

WoW.reset()
AltTrackerDB = {}
receive(T.MSG_CHUNK_V .. "|1|not-a-valid-header", "Junk-Realm")
check(chatHas("Malformed"), "malformed chunk header is reported")
WoW.chat = {}
receive(T.MSG_CHUNK_V .. "|1|9/3|" .. T.Base64Encode("x"), "Junk-Realm")
check(chatHas("Out-of-range"), "out-of-range seq (seq > total) is reported")
eq(T.Base64Decode("@@@@"), nil, "malformed base64 body decodes to nil")

------------------------------------------------------------
-- 18. DONE with no received chunks is a safe no-op
------------------------------------------------------------

WoW.reset()
AltTrackerDB = {}
receive(T.MSG_DONE_V .. "|1|00000000", "Ghost-Realm")
eq(dbCount(), 0, "DONE with no buffered chunks stores nothing and does not error")

------------------------------------------------------------
-- 19. Duplicate chunk delivery is idempotent
------------------------------------------------------------

WoW.reset()
seedDB("Player-Dup-", 4)
T.ChunkAndSendPayload(T.SerializeFullDB(false), "WHISPER", "Dup")
WoW.flushTimers()
local dupChunks, dupDone = splitWire(WoW.sentMessages())
AltTrackerDB = {}
WoW.chat = {}
receive(dupChunks[1], "Dup-Realm")
receive(dupChunks[1], "Dup-Realm")   -- same seq delivered twice
for i = 2, #dupChunks do receive(dupChunks[i], "Dup-Realm") end
receive(dupDone, "Dup-Realm")
check(not chatHas("mismatch"), "duplicate chunk does not corrupt reassembly")
eq(dbCount(), 4, "duplicate chunk delivery is idempotent")

------------------------------------------------------------
-- 20. Two interleaved streams from one sender do not clobber (H1)
------------------------------------------------------------

WoW.reset()
-- Stream A: chars IA1..IA3
AltTrackerDB = {}
for i = 1, 3 do local g = "Player-IA-" .. i; AltTrackerDB[g] = { guid = g, name = "IA" .. i, class = "MAGE",  level = 60, ilvl = 100, lastUpdate = 1 } end
T.ChunkAndSendPayload(T.SerializeFullDB(false), "WHISPER", "Inter")
WoW.flushTimers()
local aChunks, aDone = splitWire(WoW.sentMessages())
-- Stream B: a DIFFERENT set of chars IB1..IB3, same sender
WoW.sent = {}
AltTrackerDB = {}
for i = 1, 3 do local g = "Player-IB-" .. i; AltTrackerDB[g] = { guid = g, name = "IB" .. i, class = "ROGUE", level = 60, ilvl = 100, lastUpdate = 1 } end
T.ChunkAndSendPayload(T.SerializeFullDB(false), "WHISPER", "Inter")
WoW.flushTimers()
local bChunks, bDone = splitWire(WoW.sentMessages())
check(sidOf(aChunks[1]) ~= sidOf(bChunks[1]), "the two streams carry distinct stream ids")

-- Deliver the two streams' chunks interleaved, then both DONEs.
AltTrackerDB = {}
WoW.chat = {}
local maxc = math.max(#aChunks, #bChunks)
for i = 1, maxc do
    if aChunks[i] then receive(aChunks[i], "Inter-Realm") end
    if bChunks[i] then receive(bChunks[i], "Inter-Realm") end
end
receive(aDone, "Inter-Realm")
receive(bDone, "Inter-Realm")
check(not chatHas("mismatch"), "interleaved streams each checksum correctly (no clobbering)")
local bothOk = true
for i = 1, 3 do
    if not AltTrackerDB["Player-IA-" .. i] then bothOk = false end
    if not AltTrackerDB["Player-IB-" .. i] then bothOk = false end
end
check(bothOk, "both interleaved streams reassembled independently")
eq(dbCount(), 6, "all 6 chars from two interleaved streams stored")

------------------------------------------------------------
-- Summary
------------------------------------------------------------

if failures == 0 then
    print("comm tests passed: " .. testsRun)
else
    print("comm tests FAILED: " .. failures .. " of " .. testsRun)
    os.exit(1)
end
