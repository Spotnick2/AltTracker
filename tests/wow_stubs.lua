------------------------------------------------------------
-- wow_stubs.lua
--
-- Minimal World of Warcraft API surface so AltTracker's addon files
-- can be loaded and unit-tested under stock Lua 5.1 (the interpreter
-- WoW itself uses), with no game client.
--
-- Only what the modules touch at load time, plus the handful of APIs
-- the functions under test call. Tests can drive behaviour through the
-- exported `WoW` table (e.g. WoW.SetLoaded, WoW.loadCalls) and reset
-- between cases with WoW.reset().
--
-- Load this FIRST in every test file:  dofile("tests/wow_stubs.lua")
------------------------------------------------------------

local WoW = {
    loaded = {}, loadCalls = {}, timers = {}, chat = {},
    sent = {},            -- captured C_ChatInfo.SendAddonMessage payloads
    sendResult = true,    -- what SendAddonMessage returns (set false to simulate throttle)
    loggedIn = true,
}

-- Chainable fake frame: any method returns the frame so builder-style
-- chains don't blow up; SetScript/GetScript actually store handlers.
local function makeFrame()
    local f = {}
    local function chain() return f end
    f.RegisterEvent      = chain
    f.UnregisterEvent    = chain
    f.RegisterAllEvents  = chain
    f.SetPoint           = chain
    f.SetSize            = chain
    f.SetWidth           = chain
    f.SetHeight          = chain
    f.Show               = chain
    f.Hide               = chain
    f.SetScript = function(self, event, fn) self["_script_"..tostring(event)] = fn; return self end
    f.GetScript = function(self, event) return self["_script_"..tostring(event)] end
    f.HookScript = function(self, event, fn) return self end
    f.CreateTexture    = function() return makeFrame() end
    f.CreateFontString = function() return makeFrame() end
    f.CreateAnimationGroup = function() return makeFrame() end
    -- Anything else called as a method becomes a no-op returning the frame.
    setmetatable(f, { __index = function() return chain end })
    return f
end
WoW.makeFrame = makeFrame

------------------------------------------------------------
-- Globals the addon expects
------------------------------------------------------------

function CreateFrame() return makeFrame() end

C_Timer = {
    -- Record scheduled callbacks; tests flush them deterministically
    -- with WoW.flushTimers() instead of waiting on real time.
    After = function(_, fn) table.insert(WoW.timers, fn) end,
    NewTimer  = function(_, fn) return { Cancel = function() end } end,
    NewTicker = function(_, fn) return { Cancel = function() end } end,
}

C_ChatInfo = {
    RegisterAddonMessagePrefix = function() return true end,
    -- Capture the wire messages so tests can inspect / replay them into
    -- a "receiver". Signature mirrors WoW: (prefix, message, channel, target).
    SendAddonMessage = function(prefix, message, channel, target)
        table.insert(WoW.sent, { prefix = prefix, message = message, channel = channel, target = target })
        return WoW.sendResult
    end,
}

-- ChatThrottleLib passthrough: the real CTL paces via an OnUpdate pump we don't
-- drive here, so in tests it just forwards to the captured SendAddonMessage.
ChatThrottleLib = {
    SendAddonMessage = function(_, _prio, prefix, text, chattype, target)
        return C_ChatInfo.SendAddonMessage(prefix, text, chattype, target)
    end,
}

-- WoW's strsplit: each char of `delim` is a separator; `limit` caps the number
-- of returned pieces (the last piece keeps the un-split remainder). Returns
-- multiple values.
function strsplit(delim, s, limit)
    s = s or ""
    local out, start = {}, 1
    while true do
        if limit and #out == limit - 1 then
            out[#out + 1] = s:sub(start)
            break
        end
        local hit
        for di = 1, #delim do
            local p = s:find(delim:sub(di, di), start, true)
            if p and (not hit or p < hit) then hit = p end
        end
        if not hit then
            out[#out + 1] = s:sub(start)
            break
        end
        out[#out + 1] = s:sub(start, hit - 1)
        start = hit + 1
    end
    return unpack(out)
end

SlashCmdList = {}

DEFAULT_CHAT_FRAME = {
    AddMessage = function(_, msg) table.insert(WoW.chat, msg) end,
}

RAID_CLASS_COLORS = setmetatable({}, { __index = function() return { r = 1, g = 1, b = 1 } end })

-- Minimal GameTooltip so plugins that hook/append tooltip lines load & bootstrap.
GameTooltip = {
    HookScript    = function() end,
    SetOwner      = function() end,
    ClearLines    = function() end,
    AddLine       = function() end,
    AddDoubleLine = function() end,
    SetHyperlink  = function() end,
    NumLines      = function() return 0 end,
    GetItem       = function() return nil, nil end,
    Show          = function() end,
    Hide          = function() end,
}

-- Addon load state. C_AddOns is intentionally left nil so AltTracker's
-- loader falls back to these globals, which the tests control.
function IsAddOnLoaded(name) return WoW.loaded[name] == true end
function LoadAddOn(name)
    table.insert(WoW.loadCalls, name)
    WoW.loaded[name] = true   -- a successful load marks the addon loaded
    return true
end

function IsLoggedIn() return WoW.loggedIn end
UnitGUID  = function() return "Player-TEST-0001" end
UnitName  = function() return "Tester" end
UnitClass = function() return "Warrior", "WARRIOR" end
UnitRace  = function() return "Orc", "Orc" end
UnitSex   = function() return 2 end
UnitLevel = function() return 70 end
GetRealmName = function() return "TestRealm" end
-- Clock: real os.time() by default, but tests can pin it via WoW.now = <epoch>
-- (and advance it) to drive time-dependent logic like the sync-watch deadline.
time = function() return WoW.now or os.time() end

------------------------------------------------------------
-- Test-control helpers
------------------------------------------------------------

function WoW.reset()
    WoW.loaded, WoW.loadCalls, WoW.timers, WoW.chat, WoW.sent, WoW.loggedIn =
        {}, {}, {}, {}, {}, true
    WoW.sendResult = true
    WoW.now = nil   -- unpin the clock (fall back to os.time())
end

-- All captured wire messages (the `message` field of each SendAddonMessage).
function WoW.sentMessages()
    local msgs = {}
    for _, m in ipairs(WoW.sent) do msgs[#msgs + 1] = m.message end
    return msgs
end

function WoW.SetLoaded(name, isLoaded) WoW.loaded[name] = isLoaded and true or nil end

function WoW.flushTimers()
    local q = WoW.timers
    WoW.timers = {}
    for _, fn in ipairs(q) do fn() end
end

_G.WoW = WoW
return WoW
