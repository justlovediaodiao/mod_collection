local UEHelpers = require("UEHelpers")

-- Set to 60 if you use 60 fps videos from A Lot of Videos for Campaign Evolvedmod mod. Otherwise DO NOT CHANGE IT.
local CINEMATIC_VIDEO_FPS = 30

-- If multi-frame generation is enabled, set this value to the frame generation multiplier.
local FRAME_GENERATION_MULTIPLIER = 2


local POLL_INTERVAL_MS = 250

local cinematicSubsystem = nil
local userSettings = nil
local lastCinematicState = nil
local lastFrameGenerationState = nil
local lastConfiguredCap = nil
local overrideApplied = false
local savedGameplayCap = nil
local cinematicMissingLogged = false
local settingsMissingLogged = false
local cinematicReadErrorLogged = false
local controllerMissingLogged = false
local consoleErrorLogged = false

local function isValid(object)
    return object ~= nil and object:IsValid()
end

local function readProperty(object, propertyName)
    local success, value = pcall(function()
        return object[propertyName]
    end)

    if not success then
        return nil
    end

    return value
end

local function readCinematicState()
    if not isValid(cinematicSubsystem) then
        return nil
    end

    local success, inProgress = pcall(function()
        return cinematicSubsystem:IsCinematicInProgress()
    end)

    if not success or type(inProgress) ~= "boolean" then
        if not cinematicReadErrorLogged then
            print(string.format(
                "[CinematicFGFix] Unable to read IsCinematicInProgress; lua_type=%s.\n",
                type(inProgress)
            ))
            cinematicReadErrorLogged = true
        end
        return nil
    end

    cinematicReadErrorLogged = false
    return inProgress
end

local function runConsoleCommand(command)
    local controller = UEHelpers:GetPlayerController()
    local world = UEHelpers:GetWorld()
    local kismetSystemLibrary = UEHelpers:GetKismetSystemLibrary()

    if not isValid(controller) or not isValid(world) or not isValid(kismetSystemLibrary) then
        if not controllerMissingLogged then
            print("[CinematicFGFix] Waiting for console-command context.\n")
            controllerMissingLogged = true
        end
        return false
    end

    controllerMissingLogged = false

    local success, errorMessage = pcall(function()
        kismetSystemLibrary:ExecuteConsoleCommand(world, command, controller)
    end)

    if not success then
        if not consoleErrorLogged then
            print(string.format(
                "[CinematicFGFix] ExecuteConsoleCommand failed for '%s': %s\n",
                command,
                tostring(errorMessage)
            ))
            consoleErrorLogged = true
        end
        return false
    end

    consoleErrorLogged = false
    return true
end

local function readOutputCap()
    local kismetSystemLibrary = UEHelpers:GetKismetSystemLibrary()
    if not isValid(kismetSystemLibrary) then
        return nil
    end

    local success, value = pcall(function()
        return kismetSystemLibrary:GetConsoleVariableFloatValue("t.MaxFPS")
    end)

    if not success then
        return nil
    end

    return tonumber(value)
end

local function setOutputCap(cap)
    if not runConsoleCommand(string.format("t.MaxFPS %.6g", cap)) then
        return false
    end

    local actualCap = readOutputCap()
    if actualCap ~= nil then
        print(string.format(
            "[CinematicFGFix] t.MaxFPS readback: %.6g\n",
            actualCap
        ))
    end

    return actualCap ~= nil and math.abs(actualCap - cap) < 0.01
end

local function getCinematicOutputCap(frameGeneration)
    if frameGeneration == true then
        return CINEMATIC_VIDEO_FPS * FRAME_GENERATION_MULTIPLIER
    end

    return CINEMATIC_VIDEO_FPS
end

print("[CinematicFGFix] Loaded.\n")

LoopInGameThreadWithDelay(POLL_INTERVAL_MS, function()
    if not isValid(cinematicSubsystem) then
        cinematicSubsystem = FindFirstOf("BlamCinematicSubsystem")
        if isValid(cinematicSubsystem) then
            print("[CinematicFGFix] Found BlamCinematicSubsystem.\n")
            cinematicMissingLogged = false
        elseif not cinematicMissingLogged then
            print("[CinematicFGFix] Waiting for BlamCinematicSubsystem.\n")
            cinematicMissingLogged = true
        end
    end

    if not isValid(userSettings) then
        userSettings = FindFirstOf("MeteoriteGameUserSettings")
        if isValid(userSettings) then
            print("[CinematicFGFix] Found MeteoriteGameUserSettings.\n")
            settingsMissingLogged = false
        elseif not settingsMissingLogged then
            print("[CinematicFGFix] Waiting for MeteoriteGameUserSettings.\n")
            settingsMissingLogged = true
        end
    end

    local inProgress = readCinematicState()
    if inProgress == nil then
        return
    end

    if inProgress ~= lastCinematicState then
        print(string.format(
            "[CinematicFGFix] IsCinematicInProgress=%s\n",
            tostring(inProgress)
        ))
        lastCinematicState = inProgress
    end

    local frameGeneration = nil
    local configuredCap = nil
    if isValid(userSettings) then
        frameGeneration = readProperty(userSettings, "bFrameGeneration")
        configuredCap = tonumber(readProperty(userSettings, "MaximumFrameRate"))

        if frameGeneration ~= nil and frameGeneration ~= lastFrameGenerationState then
            print(string.format(
                "[CinematicFGFix] bFrameGeneration=%s\n",
                tostring(frameGeneration)
            ))
            lastFrameGenerationState = frameGeneration
        end

        if configuredCap ~= nil and configuredCap ~= lastConfiguredCap then
            print(string.format(
                "[CinematicFGFix] MaximumFrameRate=%s\n",
                tostring(configuredCap)
            ))
            lastConfiguredCap = configuredCap
        end
    end

    local cinematicOutputCap = getCinematicOutputCap(frameGeneration)

    if inProgress then
        if not overrideApplied
            and cinematicOutputCap > 30
            and configuredCap ~= nil
        then
            if runConsoleCommand("r.Streamline.DLSSG.Enable 1")
                and setOutputCap(cinematicOutputCap)
            then
                savedGameplayCap = configuredCap
                overrideApplied = true
                print(string.format(
                    "[CinematicFGFix] Cinematic cap applied: %.6g (configured gameplay cap: %.6g).\n",
                    cinematicOutputCap,
                    savedGameplayCap
                ))
            end
        elseif overrideApplied then
            local actualCap = readOutputCap()
            if actualCap ~= nil and math.abs(actualCap - cinematicOutputCap) >= 0.01 then
                print(string.format(
                    "[CinematicFGFix] Cinematic cap changed externally to %.6g; reapplying %.6g.\n",
                    actualCap,
                    cinematicOutputCap
                ))
                setOutputCap(cinematicOutputCap)
            end
        end
    elseif overrideApplied then
        if setOutputCap(savedGameplayCap) then
            print(string.format(
                "[CinematicFGFix] Gameplay cap restored: %.6g.\n",
                savedGameplayCap
            ))
            overrideApplied = false
            savedGameplayCap = nil
        end
    end
end)
