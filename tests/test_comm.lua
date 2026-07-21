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

-- Split captured wire into its CHUNK3 messages and the DONE message.
local function splitWire(messages)
    local chunks, done = {}, nil
    for _, m in ipairs(messages) do
        if m:sub(1, 7) == "CHUNK3|" then chunks[#chunks + 1] = m
        else done = m end
    end
    return chunks, done
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
    if m == "REQ" .. T.PROTOCOL_VERSION then reqSent = true end
end
check(reqSent, "receiver auto-requests a resync after a drop")

------------------------------------------------------------
-- 10. Checksum mismatch discards the data
------------------------------------------------------------

WoW.reset()
seedDB("Player-C-", 3)
T.ChunkAndSendPayload(T.SerializeFullDB(false), "WHISPER", "Corrupt")
WoW.flushTimers()
local cChunks = splitWire(WoW.sentMessages())

AltTrackerDB = {}
WoW.chat = {}
for _, m in ipairs(cChunks) do receive(m, "Corrupt-Realm") end
receive("DONE" .. T.PROTOCOL_VERSION .. "|DEADBEEF", "Corrupt-Realm")  -- wrong checksum
check(chatHas("mismatch"), "checksum mismatch is detected")
eq(dbCount(), 0, "data is discarded on checksum mismatch")

------------------------------------------------------------
-- 11. Packets from ourselves are ignored
------------------------------------------------------------

WoW.reset()
AltTrackerDB = {}
receive("CHUNK3|1/1|" .. T.Base64Encode("guid:Player-Self\nname:Me\n"), "Tester-Realm")
receive("DONE" .. T.PROTOCOL_VERSION .. "|00000000", "Tester-Realm")
eq(dbCount(), 0, "our own packets (sender == player) are ignored")

------------------------------------------------------------
-- Summary
------------------------------------------------------------

if failures == 0 then
    print("comm tests passed: " .. testsRun)
else
    print("comm tests FAILED: " .. failures .. " of " .. testsRun)
    os.exit(1)
end
