------------------------------------------------------------
-- AltTracker Config
-- Owns the SavedVariable defaults and exposes the public config API
-- (whitelist mutation, defaults init). The standalone config popup
-- has been removed — all settings now live in the in-window Options
-- section (open via /alts config or the minimap right-click).
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
    if AltTrackerConfig.sendAllAccounts == nil then
        AltTrackerConfig.sendAllAccounts = false
    end
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
    -- Appearance defaults
    AltTrackerConfig.theme = AltTrackerConfig.theme or "dark"
    if AltTrackerConfig.scale == nil then
        AltTrackerConfig.scale = 1.0
    end

    -- World camera presentation defaults (live player only).
    -- NOTE: We deliberately do NOT default `worldCameraShoulderOffset` or
    -- `worldCameraPitchOffset` -- the minimal Classic-safe controller does not
    -- touch `test_cameraOverShoulder` (it would trip Blizzard's experimental
    -- ActionCam popup) or pitch CVars. Old saved values are harmless.
    if AltTrackerConfig.enableWorldCameraPresentation == nil then
        AltTrackerConfig.enableWorldCameraPresentation = true
    end
    if AltTrackerConfig.worldCameraPresentationDebug == nil then
        AltTrackerConfig.worldCameraPresentationDebug = false
    end
    if AltTrackerConfig.worldCameraEnterDuration == nil then
        AltTrackerConfig.worldCameraEnterDuration = 0.60
    end
    if AltTrackerConfig.worldCameraExitDuration == nil then
        AltTrackerConfig.worldCameraExitDuration = 0.45
    end
    -- Migration: any zoom below ~7.0 frames the camera too close. With the
    -- single-call zoom strategy plus the temporary cameraDistanceMaxZoomFactor
    -- bump, the new default of 8.5 reliably places the character outside the
    -- addon footprint. Catches all legacy defaults (2.20 / 2.35 / 4.5 / 6.5).
    do
        local zp = tonumber(AltTrackerConfig.worldCameraZoomPreset)
        if zp and zp < 7.0 then
            AltTrackerConfig.worldCameraZoomPreset = nil
        end
    end
    if AltTrackerConfig.worldCameraZoomPreset == nil then
        AltTrackerConfig.worldCameraZoomPreset = 8.5
    end
    if AltTrackerConfig.worldCameraYawOffset == nil then
        AltTrackerConfig.worldCameraYawOffset = -0.22
    end
    if AltTrackerConfig.worldCameraYawDegrees == nil then
        -- A small swing (60deg) rather than a full half-rotation; matches
        -- Narcissus's "settle into pose" feel instead of a spin.
        AltTrackerConfig.worldCameraYawDegrees = 60
    end
    if AltTrackerConfig.worldCameraSavedViewSlot == nil then
        AltTrackerConfig.worldCameraSavedViewSlot = 5
    end
    -- Lateral character placement: multiplier applied on top of Narcissus's
    -- per-race shoulder offset formula (zoom * factor1 + factor2). Higher
    -- pushes the character further LEFT on screen, making more room for
    -- the AltTracker window on the right. 1.0 = Narcissus default.
    if AltTrackerConfig.worldCameraShoulderMult == nil then
        AltTrackerConfig.worldCameraShoulderMult = 1.0
    end
    -- Continuous slow orbit (Narcissus-style "spinning room" effect): keeps
    -- a tiny MoveViewRightStart running for the whole time AltTracker is
    -- open, so the world rotates around the centered player.
    if AltTrackerConfig.worldCameraContinuousOrbit == nil then
        AltTrackerConfig.worldCameraContinuousOrbit = true
    end
    if AltTrackerConfig.worldCameraOrbitSpeed == nil then
        -- Matches Narcissus's ZoomFactor.toSpeed; slow enough to be ambient,
        -- fast enough to be visible. Tweak with /run AltTrackerConfig.worldCameraOrbitSpeed = N
        AltTrackerConfig.worldCameraOrbitSpeed = 0.005
    end

    -- Open-window UX defaults
    if AltTrackerConfig.enableOpenAnimation == nil then
        AltTrackerConfig.enableOpenAnimation = true
    end

    -- Minimap button (LibDBIcon-free; angle-around-minimap persistence)
    AltTrackerConfig.minimapButton = AltTrackerConfig.minimapButton or {}
    if AltTrackerConfig.minimapButton.hide == nil then
        AltTrackerConfig.minimapButton.hide = false
    end
    if AltTrackerConfig.minimapButton.angle == nil then
        AltTrackerConfig.minimapButton.angle = 200 -- lower-left default
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
-- Backwards-compat: the standalone config popup has been replaced by
-- the in-window Options section (sidebar -> Options). Keep the public
-- API surface so /alts config and the minimap right-click still work.
-- AltTracker.OpenConfig() now opens the AltTracker sheet on the Options
-- section directly, instead of building its own popup.
------------------------------------------------------------

function AltTracker.OpenConfig()
    if AltTracker.EnsureSheetVisible then
        AltTracker.EnsureSheetVisible()
    elseif AltTracker.ShowSheet then
        AltTracker.ShowSheet()
    end
    if AltTracker._SwitchToOptions then
        AltTracker._SwitchToOptions()
    end
end

------------------------------------------------------------
-- Init on login
------------------------------------------------------------

local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("PLAYER_LOGIN")
initFrame:SetScript("OnEvent", function()
    EnsureDefaults()
end)