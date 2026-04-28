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

local CAMERA_PRESENTATION_DEFAULTS_VERSION = 10

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

    -- World camera presentation defaults (live player only). The target is a
    -- portrait-like composition: the camera swings around to the player's
    -- front, pushes the character left of the sheet, and restores everything
    -- on close.
    if AltTrackerConfig.enableWorldCameraPresentation == nil then
        AltTrackerConfig.enableWorldCameraPresentation = true
    end
    if AltTrackerConfig.worldCameraPresentationDebug == nil then
        AltTrackerConfig.worldCameraPresentationDebug = false
    end
    if AltTrackerConfig.worldCameraEnterDuration == nil then
        AltTrackerConfig.worldCameraEnterDuration = 1.50
    end
    if AltTrackerConfig.worldCameraExitDuration == nil then
        AltTrackerConfig.worldCameraExitDuration = 0.45
    end
    -- v10 camera migration: mirror Narcissus Classic's eased 1.5s yaw, but
    -- use the leftward direction that keeps AltTracker's composition visible.
    -- Because the yaw speed eases down during the move, the configured degree
    -- value needs to be higher than the apparent final rotation. Visual zoom
    -- is closer, while shoulder placement still uses the old 6.2 reference
    -- because the user's ideal state came from zooming in after placement.
    do
        local version = tonumber(AltTrackerConfig.worldCameraPresentationDefaultsVersion) or 0
        if version < CAMERA_PRESENTATION_DEFAULTS_VERSION then
            local duration = tonumber(AltTrackerConfig.worldCameraEnterDuration)
            if not duration or duration < 1.0 or math.abs(duration - 0.60) < 0.01 then
                AltTrackerConfig.worldCameraEnterDuration = 1.50
            end

            AltTrackerConfig.worldCameraZoomPreset = 2.2
            AltTrackerConfig.worldCameraShoulderZoomReference = 6.2
            AltTrackerConfig.worldCameraMountedZoomPreset = 8.0
            AltTrackerConfig.worldCameraMountedShoulderOffset = 8.0
            AltTrackerConfig.worldCameraForceMountedPresentation = false
            AltTrackerConfig.worldCameraYawDegrees = 430
            AltTrackerConfig.worldCameraYawOffset = -0.22
            AltTrackerConfig.worldCameraShoulderMult = 1.0

            AltTrackerConfig.worldCameraContinuousOrbit = true
            AltTrackerConfig.worldCameraPresentationDefaultsVersion = CAMERA_PRESENTATION_DEFAULTS_VERSION
        end
    end
    if AltTrackerConfig.worldCameraZoomPreset == nil then
        AltTrackerConfig.worldCameraZoomPreset = 2.2
    end
    if AltTrackerConfig.worldCameraShoulderZoomReference == nil then
        AltTrackerConfig.worldCameraShoulderZoomReference = 6.2
    end
    if AltTrackerConfig.worldCameraMountedZoomPreset == nil then
        AltTrackerConfig.worldCameraMountedZoomPreset = 8.0
    end
    if AltTrackerConfig.worldCameraMountedShoulderOffset == nil then
        AltTrackerConfig.worldCameraMountedShoulderOffset = 8.0
    end
    if AltTrackerConfig.worldCameraForceMountedPresentation == nil then
        AltTrackerConfig.worldCameraForceMountedPresentation = false
    end
    if AltTrackerConfig.worldCameraYawOffset == nil then
        AltTrackerConfig.worldCameraYawOffset = -0.22
    end
    if AltTrackerConfig.worldCameraYawDegrees == nil then
        AltTrackerConfig.worldCameraYawDegrees = 430
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
    -- Continuous slow orbit follows Narcissus's default camera presentation:
    -- after the entry yaw, the world keeps turning slowly around the player.
    if AltTrackerConfig.worldCameraContinuousOrbit == nil then
        AltTrackerConfig.worldCameraContinuousOrbit = true
    end
    if AltTrackerConfig.worldCameraOrbitSpeed == nil then
        -- Matches Narcissus's ZoomFactor.toSpeed; slow enough to be ambient,
        -- fast enough to be visible. Tweak with /run AltTrackerConfig.worldCameraOrbitSpeed = N
        AltTrackerConfig.worldCameraOrbitSpeed = 0.005
    end
    if AltTrackerConfig.enableWorldCameraSalute == nil then
        AltTrackerConfig.enableWorldCameraSalute = false
    end

    -- Open-window UX defaults
    if AltTrackerConfig.enableOpenAnimation == nil then
        AltTrackerConfig.enableOpenAnimation = true
    end
    if AltTrackerConfig.rememberWindowPosition == nil then
        AltTrackerConfig.rememberWindowPosition = true
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
